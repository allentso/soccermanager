-- persistence/save_manager.lua
-- 存档管理器

local Constants = require("scripts/app/constants")
local Migrations = require("scripts/persistence/migrations")

local SaveManager = {}

-- 存档路径
local SAVE_DIR = "Saves/"

function SaveManager.getSavePath(slot)
    if slot == "auto" then
        return SAVE_DIR .. "autosave.json"
    end
    return SAVE_DIR .. "save_" .. string.format("%03d", slot) .. ".json"
end

function SaveManager.getMetaPath(slot)
    if slot == "auto" then
        return SAVE_DIR .. "autosave.meta.json"
    end
    return SAVE_DIR .. "save_" .. string.format("%03d", slot) .. ".meta.json"
end

------------------------------------------------------
-- 数据消毒/治疗体系
--
-- 重要教训：gameState 中大量表是"整数 ID 映射表"
-- （players[523]、teams[27]、standings[teamId]、shortlist[playerId]），
-- 不能用通用逻辑把它们当稀疏数组压实——那会让所有 ID 错位、毁掉整个世界。
-- 因此：
--   * 数值修复（NaN/Infinity）：通用递归，安全
--   * 空洞压实：只对"白名单中已知的真数组"执行（inbox/news/fixtures 等）
--   * 副本消毒 sanitize：不改键结构，只修数值/丢弃不可序列化类型
------------------------------------------------------
local MAX_FLOAT = 1e308

local function isBadNumber(v)
    return v ~= v or v == math.huge or v == -math.huge
end

local function fixNumber(v)
    if v ~= v then return 0 end                      -- NaN (NaN ~= NaN)
    if v == math.huge then return MAX_FLOAT end
    if v == -math.huge then return -MAX_FLOAT end
    return v
end

-- 副本消毒：构建新表，绝不修改传入数据；键结构原样保留（不压实！）
local function sanitize(value, seen)
    local vt = type(value)
    if vt == "number" then
        return fixNumber(value)
    elseif vt == "string" or vt == "boolean" then
        return value
    elseif vt == "table" then
        if seen[value] then return nil end            -- 打断循环引用
        seen[value] = true
        local out = {}
        for k, v in pairs(value) do
            -- cjson 只接受 string/number 键，其它键丢弃
            if type(k) == "string" or type(k) == "number" then
                local sv = sanitize(v, seen)
                if sv ~= nil then out[k] = sv end
            end
        end
        seen[value] = nil                              -- 仅在祖先链上视为循环，允许共享子树
        return out
    end
    -- function / userdata / thread：不可序列化，丢弃
    return nil
end

-- 深度扫描：是否存在非法数值（主动体检用，不依赖 cjson 是否报错）
local function hasBadNumbersDeep(value, seen)
    local vt = type(value)
    if vt == "number" then
        return isBadNumber(value)
    end
    if vt ~= "table" or seen[value] then return false end
    seen[value] = true
    for _, v in pairs(value) do
        if hasBadNumbersDeep(v, seen) then return true end
    end
    return false
end

-- 就地修复非法数值（只动 NaN/Infinity，键结构/正常值/引用一律不碰）
local function healNumbersInPlace(value, seen)
    if type(value) ~= "table" then return end
    if seen[value] then return end
    seen[value] = true
    for k, v in pairs(value) do
        local vt = type(v)
        if vt == "number" then
            if isBadNumber(v) then
                value[k] = fixNumber(v)
            end
        elseif vt == "table" then
            healNumbersInPlace(v, seen)
        end
    end
end

-- 数组空洞检测：整数键数量 < 最大整数键 ⇒ 有空洞
local function arrayHasHoles(t)
    if type(t) ~= "table" then return false end
    local count, maxk = 0, 0
    for k in pairs(t) do
        if type(k) == "number" and k >= 1 and math.floor(k) == k then
            count = count + 1
            if k > maxk then maxk = k end
        end
    end
    return maxk > count
end

-- 就地压实数组空洞（只对已确认是"真数组"的表调用）
local function compactArray(t)
    if not arrayHasHoles(t) then return false end
    local intKeys = {}
    for k in pairs(t) do
        if type(k) == "number" and k >= 1 and math.floor(k) == k then
            intKeys[#intKeys + 1] = k
        end
    end
    table.sort(intKeys)
    local vals = {}
    for _, k in ipairs(intKeys) do
        vals[#vals + 1] = t[k]
        t[k] = nil
    end
    for i, v in ipairs(vals) do
        t[i] = v
    end
    return true
end

-- 已知"真数组"白名单遍历：live gameState 和 serialize() 副本结构一致，两者通用
-- fn(arr, name) 对每个存在的数组字段调用
local function forEachKnownArray(gs, fn)
    if type(gs) ~= "table" then return end
    local function visit(t, name)
        if type(t) == "table" then fn(t, name) end
    end
    visit(gs.inbox, "inbox")
    visit(gs.news, "news")
    visit(gs.worldHistory, "worldHistory")
    visit(gs.scoutReports, "scoutReports")
    visit(gs.scoutDiscoveries, "scoutDiscoveries")
    if type(gs.transfers) == "table" then
        visit(gs.transfers.bids, "transfers.bids")
        visit(gs.transfers.history, "transfers.history")
    end
    for key, lg in pairs(gs.leagues or {}) do
        if type(lg) == "table" then
            visit(lg.fixtures, "leagues." .. tostring(key) .. ".fixtures")
            visit(lg.teamIds, "leagues." .. tostring(key) .. ".teamIds")
        end
    end
    for _, t in pairs(gs.teams or {}) do
        if type(t) == "table" then
            visit(t.playerIds, "team.playerIds")
            visit(t.staffIds, "team.staffIds")
            -- startingXI / benchIds 为槽位索引表，空洞是合法语义，不可压实
            visit(t.recentForm, "team.recentForm")
            visit(t.transactions, "team.transactions")
        end
    end
    local ucl = gs.championsLeague
    if type(ucl) == "table" then
        if type(ucl.leaguePhase) == "table" then
            visit(ucl.leaguePhase.fixtures, "ucl.leaguePhase.fixtures")
        end
        if type(ucl.knockout) == "table" then
            for phase, arr in pairs(ucl.knockout) do
                visit(arr, "ucl.knockout." .. tostring(phase))
            end
        end
    end
    local wc = gs.worldCup
    if type(wc) == "table" then
        if type(wc.groups) == "table" then
            for gName, group in pairs(wc.groups) do
                if type(group) == "table" then
                    visit(group.fixtures, "wc.groups." .. tostring(gName) .. ".fixtures")
                end
            end
        end
        if type(wc.knockout) == "table" then
            for phase, arr in pairs(wc.knockout) do
                visit(arr, "wc.knockout." .. tostring(phase))
            end
        end
    end
end

-- 诊断：定位非法数值/不可序列化类型的字段路径（追根因用）
-- 注意：不再做通用稀疏检测（ID 映射表会误报），空洞由白名单单独报告
local function reportBadValues(value, path, seen, reports, maxReports)
    if #reports >= maxReports then return end
    local vt = type(value)
    if vt == "number" then
        if value ~= value then
            reports[#reports + 1] = path .. " = NaN"
        elseif value == math.huge or value == -math.huge then
            reports[#reports + 1] = path .. " = Infinity"
        end
    elseif vt == "function" or vt == "userdata" or vt == "thread" then
        reports[#reports + 1] = path .. " = <" .. vt .. ">"
    elseif vt == "table" then
        if seen[value] then return end
        seen[value] = true
        for k, v in pairs(value) do
            reportBadValues(v, path .. "." .. tostring(k), seen, reports, maxReports)
            if #reports >= maxReports then return end
        end
        seen[value] = nil
    end
end

local MAX_SANITIZE_REPORTS = 20  -- 留痕记录上限，避免存档无限膨胀

------------------------------------------------------
-- 保存诊断
--
-- 存档失败一直是"静默"的（玩家看不到引擎日志），导致线上反馈
-- "自动/手动保存都不生效"时完全无法定位。这里记录每次保存的
-- 阶段化结果，UI（存档管理页）可直接展示失败原因。
------------------------------------------------------
SaveManager.lastResult = nil  -- { ok, slot, stage, message, jsonSize, saved_at }

local function setResult(ok, slot, stage, message, jsonSize, saved_at)
    SaveManager.lastResult = {
        ok = ok,
        slot = slot,
        stage = stage,
        message = message and tostring(message) or nil,
        jsonSize = jsonSize,
        saved_at = saved_at,
    }
    if not ok and log then
        log:Write(LOG_ERROR, string.format(
            "SaveManager: 保存失败 slot=%s stage=%s size=%s err=%s",
            tostring(slot), tostring(stage), tostring(jsonSize), tostring(message)))
    end
    -- 失败信息同时尝试落盘（极小文件，便于事后从设备取证；写不进就算了）
    if not ok then
        pcall(function()
            local f = File(SAVE_DIR .. "save_diag.txt", FILE_WRITE)
            if f and f:IsOpen() then
                f:WriteString(string.format("saved_at=%s slot=%s stage=%s size=%s\nerr=%s",
                    tostring(saved_at), tostring(slot), tostring(stage),
                    tostring(jsonSize), tostring(message)))
                f:Close()
            end
        end)
    end
    return ok
end

------------------------------------------------------
-- 读写细节（重要教训）
--
-- 引擎的 WriteString 每次调用都会在内容后写入一个 '\0' 终止符，
-- ReadString 则读到第一个 '\0' 就停止。
-- 因此：
--   * 写入必须一次性 WriteString（曾经的"分块写入"在 JSON 中间
--     每 256KB 嵌入一个 '\0'，导致存档读回时被截断、decode 失败，
--     所有槽位显示"空槽位"——数据其实还在盘上！）
--   * 读取使用 readAllString：跨 '\0' 连续读到 EOF 再拼接，
--     既兼容正常存档（单个尾部 '\0'），也能完整救回被分块写入
--     污染过的存档。
------------------------------------------------------
local function readAllString(file)
    local parts = {}
    local guard = 0
    while guard < 100000 do
        guard = guard + 1
        -- IsEof 可能不存在于某些绑定版本，pcall 保护
        local okEof, eof = pcall(function() return file:IsEof() end)
        if okEof and eof then break end
        local okRead, s = pcall(function() return file:ReadString() end)
        if not okRead or s == nil then break end
        parts[#parts + 1] = s
        -- 无 IsEof 可用且读到空串：避免死循环，直接结束
        if not okEof and s == "" then break end
    end
    return table.concat(parts)
end

local function buildSlotMeta(slot, saveData, jsonSize)
    local gs = saveData and saveData.game_state
    local meta = {
        version = saveData and saveData.version or Constants.SAVE_VERSION,
        saved_at = saveData and saveData.saved_at or nil,
        slot = slot,
        byteSize = jsonSize,
    }

    if gs then
        meta.season = gs.season
        meta.playerTeamId = gs.playerTeamId
        local teamId = gs.playerTeamId
        if teamId and gs.teams then
            local team = gs.teams[tostring(teamId)] or gs.teams[teamId]
            if team then
                meta.team_name = team.name
                meta.balance = team.balance
            end
        end
    end
    return meta
end

local function writeSlotMeta(slot, saveData, jsonSize)
    local meta = buildSlotMeta(slot, saveData, jsonSize)
    local ok, metaJson = pcall(cjson.encode, meta)
    if not ok or not metaJson then return false end

    local f = File(SaveManager.getMetaPath(slot), FILE_WRITE)
    if not f or not f:IsOpen() then return false end
    local okWrite = pcall(function() f:WriteString(metaJson) end)
    f:Close()
    return okWrite
end

local function readSlotMeta(slot)
    local path = SaveManager.getMetaPath(slot)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local content = readAllString(file)
    file:Close()
    local ok, meta = pcall(cjson.decode, content)
    if not ok or type(meta) ~= "table" then return nil end
    meta.slot = slot
    return meta
end

function SaveManager._doSave(gameState, slot)
    slot = slot or "auto"
    local path = SaveManager.getSavePath(slot)

    -- 确保存档目录存在
    fileSystem:CreateDir(SAVE_DIR)

    if gameState.normalizeRuntimeScalars then
        gameState:normalizeRuntimeScalars()
    end
    local d = gameState.date or {}
    local saved_at = string.format("%d-%02d-%02d",
        tonumber(d.year) or 2025, tonumber(d.month) or 8, tonumber(d.day) or 10)

    -- 阶段1：序列化（任何一个 domain 对象 serialize 抛错都会在这里被定位）
    local okSer, gsData = pcall(gameState.serialize, gameState)
    if not okSer then
        return setResult(false, slot, "serialize", gsData, nil, saved_at)
    end

    -- 主动体检：不依赖 cjson 是否报错（有些 cjson 实现会把 NaN 直接写成
    -- 非法 JSON 而"成功"返回，导致存档无法读回）
    local dirtyNumbers = hasBadNumbersDeep(gsData, {})
    local holeReports = {}
    forEachKnownArray(gsData, function(arr, name)
        if arrayHasHoles(arr) then
            holeReports[#holeReports + 1] = "game_state." .. name .. " = <稀疏数组空洞>"
        end
    end)

    if dirtyNumbers or #holeReports > 0 then
        -- 定位非法值字段路径
        local reports = {}
        if dirtyNumbers then
            reportBadValues(gsData, "game_state", {}, reports, 10)
        end
        for _, r in ipairs(holeReports) do
            reports[#reports + 1] = r
        end

        if log then
            log:Write(LOG_WARNING, "SaveManager: 检测到非法存档数据，执行治疗:\n  " .. table.concat(reports, "\n  "))
        end

        -- 写进存档留痕：即使玩家看不到日志，将来拿到存档也能定位根因
        gameState._sanitizeReports = gameState._sanitizeReports or {}
        table.insert(gameState._sanitizeReports, {
            saved_at = saved_at,
            fields = reports,
        })
        while #gameState._sanitizeReports > MAX_SANITIZE_REPORTS do
            table.remove(gameState._sanitizeReports, 1)
        end

        -- 就地治疗 live gameState（防止每次存档重复走慢路径导致卡顿）：
        -- 1) 修复非法数值（只动 NaN/Inf）
        -- 2) 压实白名单数组的空洞（绝不碰 ID 映射表）
        local okHeal, healErr = pcall(function()
            healNumbersInPlace(gameState, {})
            forEachKnownArray(gameState, function(arr) compactArray(arr) end)
        end)
        if not okHeal and log then
            log:Write(LOG_ERROR, "SaveManager: 就地治疗失败: " .. tostring(healErr))
        end

        -- 重新序列化（已治疗 + 纳入留痕），再做副本级消毒兜底
        local okSer2, gsData2 = pcall(function()
            local d = sanitize(gameState:serialize(), {})
            forEachKnownArray(d, function(arr) compactArray(arr) end)
            return d
        end)
        if not okSer2 then
            return setResult(false, slot, "heal_serialize", gsData2, nil, saved_at)
        end
        gsData = gsData2
    end

    local saveData = {
        version = Constants.SAVE_VERSION,
        saved_at = saved_at,
        game_state = gsData,
    }

    -- 阶段2：JSON 编码
    local ok, jsonStr = pcall(cjson.encode, saveData)
    if not ok or not jsonStr then
        -- 最后兜底：完整消毒后再试一次（处理体检未覆盖的情况，如非法键类型）
        local encodeErr1 = jsonStr
        if log then
            log:Write(LOG_WARNING, "SaveManager: JSON编码失败，消毒后重试: " .. tostring(encodeErr1))
        end
        saveData.game_state = sanitize(gsData, {})
        ok, jsonStr = pcall(cjson.encode, saveData)
        if not ok or not jsonStr then
            return setResult(false, slot, "encode",
                tostring(encodeErr1) .. " | retry: " .. tostring(jsonStr), nil, saved_at)
        end
    end
    local jsonSize = #jsonStr

    -- 写前备份：自动存档被高频覆盖，是最容易"写坏即丢档"的文件。
    -- 覆盖前把现有好档复制为 .bak，读档失败时可自动回退（见 load）。
    -- 只备份自动存档：手动槽位是玩家确认后才覆盖的，且要节省存储配额。
    if slot == "auto" and fileSystem:FileExists(path) then
        pcall(function()
            local src = File(path, FILE_READ)
            if src and src:IsOpen() then
                local old = readAllString(src)
                src:Close()
                if #old > 0 then
                    local dst = File(path .. ".bak", FILE_WRITE)
                    if dst and dst:IsOpen() then
                        dst:WriteString(old)
                        dst:Close()
                    end
                end
            end
        end)
    end

    -- 阶段3：打开文件
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        return setResult(false, slot, "open_file", "无法打开 " .. path .. "（存储空间不足/权限受限？）", jsonSize, saved_at)
    end

    -- 阶段4：一次性写入（绝不可分块——WriteString 每次调用都会嵌入 '\0' 终止符）
    local okWrite, writeErr = pcall(function() file:WriteString(jsonStr) end)
    file:Close()
    if not okWrite then
        return setResult(false, slot, "write", writeErr, jsonSize, saved_at)
    end

    -- 阶段5：写后校验——重新打开文件确认实际落盘大小
    -- （配额满/磁盘满时 WriteString 可能"成功"但实际截断）
    local okVerify, verifyErr = pcall(function()
        local rf = File(path, FILE_READ)
        if not rf or not rf:IsOpen() then
            error("写入后无法重新打开文件")
        end
        local actualSize = rf.size or (rf.GetSize and rf:GetSize()) or nil
        rf:Close()
        if actualSize ~= nil and actualSize < jsonSize then
            error(string.format("文件被截断: 期望 %d 字节, 实际 %d 字节（疑似存储空间不足）", jsonSize, actualSize))
        end
    end)
    if not okVerify then
        return setResult(false, slot, "verify", verifyErr, jsonSize, saved_at)
    end

    if log then
        log:Write(LOG_INFO, string.format("SaveManager: 已保存到 %s (%.1f KB)", path, jsonSize / 1024))
    end
    pcall(writeSlotMeta, slot, saveData, jsonSize)
    return setResult(true, slot, "done", nil, jsonSize, saved_at)
end

-- 保存游戏（全程 pcall 保护：存档失败绝不能中断游戏推进/界面刷新）
function SaveManager.save(gameState, slot)
    local ok, result = pcall(SaveManager._doSave, gameState, slot)
    if not ok then
        if log then log:Write(LOG_ERROR, "SaveManager: 保存异常已捕获: " .. tostring(result)) end
        setResult(false, slot or "auto", "unexpected", result, nil, nil)
        return false
    end
    return result
end

-- 最近一次保存失败的简述（无失败时返回 nil），供 UI 展示
function SaveManager.getLastErrorText()
    local r = SaveManager.lastResult
    if not r or r.ok then return nil end
    local sizeStr = r.jsonSize and string.format(" %.1fKB", r.jsonSize / 1024) or ""
    return string.format("[%s]%s %s", tostring(r.stage), sizeStr, tostring(r.message or "未知错误"))
end

-- 从指定路径读取并解析存档数据（nil 表示失败）
local function readSaveData(path)
    if not fileSystem:FileExists(path) then return nil end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local content = readAllString(file)
    file:Close()
    local ok, saveData = pcall(cjson.decode, content)
    if not ok or not saveData or not saveData.game_state then return nil end
    return saveData
end

-- 尝试将 saveData 迁移并恢复到 gameState
local function applySaveData(gameState, saveData, path)
    -- 版本迁移：旧存档升级到最新版本（不影响玩家进度，只修正数据偏差）
    -- pcall 保护：单个迁移步骤出错不应让整个存档无法加载
    local oldVersion = saveData.version or 1
    if oldVersion < Constants.SAVE_VERSION then
        local okMig, newVersion = pcall(Migrations.run, saveData)
        if okMig then
            log:Write(LOG_INFO, "SaveManager: 存档从 v" .. oldVersion .. " 迁移到 v" .. tostring(newVersion))
        else
            log:Write(LOG_ERROR, "SaveManager: 存档迁移异常（继续按原数据加载）: " .. tostring(newVersion))
        end
    end

    -- pcall 保护：旧存档结构差异导致的反序列化异常应优雅失败，而非崩溃
    local okDes, err = pcall(gameState.deserialize, gameState, saveData.game_state)
    if not okDes then
        log:Write(LOG_ERROR, "SaveManager: 反序列化失败 " .. path .. " - " .. tostring(err))
        return false
    end

    -- 读档瘦身：老存档中累积的退役球员/超额自由球员/旧赛果明细/重复历史等
    -- 一次性清理（幂等），防止老存档体积无限膨胀导致保存缓慢甚至失败
    local Housekeeping = require("scripts/persistence/housekeeping")
    local okHk, hkErr = pcall(Housekeeping.run, gameState)
    if not okHk then
        log:Write(LOG_WARNING, "SaveManager: 读档瘦身失败（不影响加载）: " .. tostring(hkErr))
    end

    -- 读档后立即修复错位赛程（旧版中超 3 月 JSON 等），避免未 advanceDay 就卡在逾期比赛
    local okFix, fixErr = pcall(function()
        local RealDataLoader = require("scripts/data/real_data_loader")
        RealDataLoader.fixMisalignedLeagueFixtures(gameState)
        local TurnProcessor = require("scripts/core/turn_processor")
        TurnProcessor.invalidateFixtureCaches(gameState)
    end)
    if not okFix then
        log:Write(LOG_WARNING, "SaveManager: 赛程修复失败（不影响加载）: " .. tostring(fixErr))
    end

    -- 8 月赛程老档：补模拟其他球队逾期比赛，避免积分榜/世界进程冻结
    local okCatchUp, catchUpErr = pcall(function()
        local TurnProcessor = require("scripts/core/turn_processor")
        TurnProcessor.repairStuckProgressOnLoad(gameState)
        gameState._stuckProgressRepairDone = true
    end)
    if not okCatchUp then
        log:Write(LOG_WARNING, "SaveManager: 逾期补赛失败（不影响加载）: " .. tostring(catchUpErr))
    end

    log:Write(LOG_INFO, "SaveManager: 已从 " .. path .. " 加载存档")
    return true
end

-- 加载游戏：主文件失败时自动回退到 .bak 备份
function SaveManager.load(gameState, slot)
    slot = slot or "auto"
    local mainPath = SaveManager.getSavePath(slot)

    for _, path in ipairs({ mainPath, mainPath .. ".bak" }) do
        local saveData = readSaveData(path)
        if saveData then
            if path ~= mainPath then
                log:Write(LOG_WARNING, "SaveManager: 主存档损坏，已回退到备份 " .. path)
            end
            if applySaveData(gameState, saveData, path) then
                return true
            end
        end
    end

    log:Write(LOG_ERROR, "SaveManager: 加载失败（主存档与备份均不可用） " .. mainPath)
    return false
end

-- 检查存档是否存在
function SaveManager.exists(slot)
    local path = SaveManager.getSavePath(slot)
    return fileSystem:FileExists(path)
end

-- 获取存档信息（不加载完整数据；主文件损坏时回退备份）
function SaveManager.getSlotInfo(slot)
    local path = SaveManager.getSavePath(slot)
    if fileSystem:FileExists(path) then
        local meta = readSlotMeta(slot)
        if meta then return meta end
    end

    local data = readSaveData(path) or readSaveData(path .. ".bak")
    if not data then return nil end

    return buildSlotMeta(slot, data, nil)
end

-- 获取所有存档槽信息
function SaveManager.getAllSlots()
    local slots = {}
    for i = 1, Constants.MAX_SAVE_SLOTS do
        slots[i] = SaveManager.getSlotInfo(i)
    end
    -- 自动存档
    slots.auto = SaveManager.getSlotInfo("auto")
    return slots
end

-- 删除存档（连同备份）
function SaveManager.delete(slot)
    local path = SaveManager.getSavePath(slot)
    local metaPath = SaveManager.getMetaPath(slot)
    if fileSystem:FileExists(metaPath) then
        fileSystem:Delete(metaPath)
    end
    if fileSystem:FileExists(path .. ".bak") then
        fileSystem:Delete(path .. ".bak")
    end
    if fileSystem:FileExists(path) then
        fileSystem:Delete(path)
        return true
    end
    return false
end

return SaveManager
