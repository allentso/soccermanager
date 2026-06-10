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
            visit(t.startingXI, "team.startingXI")
            visit(t.benchIds, "team.benchIds")
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

-- 分块写入：部分平台对单次写入超大字符串有隐性限制
local WRITE_CHUNK = 256 * 1024

local function writeChunked(file, str)
    local len = #str
    local pos = 1
    while pos <= len do
        local chunk = string.sub(str, pos, math.min(pos + WRITE_CHUNK - 1, len))
        file:WriteString(chunk)
        pos = pos + WRITE_CHUNK
    end
end

function SaveManager._doSave(gameState, slot)
    slot = slot or "auto"
    local path = SaveManager.getSavePath(slot)

    -- 确保存档目录存在
    fileSystem:CreateDir(SAVE_DIR)

    local saved_at = string.format("%d-%02d-%02d", gameState.date.year, gameState.date.month, gameState.date.day)

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

    -- 阶段3：打开文件
    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        return setResult(false, slot, "open_file", "无法打开 " .. path .. "（存储空间不足/权限受限？）", jsonSize, saved_at)
    end

    -- 阶段4：分块写入（避免单次超大字符串写入在部分平台上失败）
    local okWrite, writeErr = pcall(writeChunked, file, jsonStr)
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

-- 加载游戏
function SaveManager.load(gameState, slot)
    slot = slot or "auto"
    local path = SaveManager.getSavePath(slot)

    if not fileSystem:FileExists(path) then
        log:Write(LOG_WARNING, "SaveManager: 存档不存在 " .. path)
        return false
    end

    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        log:Write(LOG_ERROR, "SaveManager: 无法读取文件 " .. path)
        return false
    end

    local content = file:ReadString()
    file:Close()

    local ok, saveData = pcall(cjson.decode, content)
    if not ok or not saveData then
        log:Write(LOG_ERROR, "SaveManager: JSON解析失败 " .. path)
        return false
    end

    if saveData.game_state then
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

        log:Write(LOG_INFO, "SaveManager: 已从 " .. path .. " 加载存档")
        return true
    end

    return false
end

-- 检查存档是否存在
function SaveManager.exists(slot)
    local path = SaveManager.getSavePath(slot)
    return fileSystem:FileExists(path)
end

-- 获取存档信息（不加载完整数据）
function SaveManager.getSlotInfo(slot)
    local path = SaveManager.getSavePath(slot)
    if not fileSystem:FileExists(path) then
        return nil
    end

    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then return nil end
    local content = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, content)
    if not ok or not data then return nil end

    local info = {
        version = data.version,
        saved_at = data.saved_at,
        slot = slot,
    }

    -- 从 game_state 提取元数据（球队名、赛季、资金）
    local gs = data.game_state
    if gs then
        info.season = gs.season
        -- 提取玩家球队名称和资金
        local teamId = gs.playerTeamId
        if teamId and gs.teams then
            local team = gs.teams[tostring(teamId)]
            if team then
                info.team_name = team.name
                info.balance = team.balance
            end
        end
    end

    return info
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

-- 删除存档
function SaveManager.delete(slot)
    local path = SaveManager.getSavePath(slot)
    if fileSystem:FileExists(path) then
        fileSystem:Delete(path)
        return true
    end
    return false
end

return SaveManager
