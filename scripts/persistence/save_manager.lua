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
-- 数据消毒：清除会让 cjson.encode 抛错的非法值
-- 触发场景：除零产生的 NaN/Infinity、数组出现空洞（稀疏数组）、
--           误存入的函数/userdata 等。
-- 关键：始终构建新表，绝不修改传入的 live gameState 引用。
-- 输出保持标准 JSON（NaN→0），以保证新老/其它读档逻辑都能解析。
------------------------------------------------------
local MAX_FLOAT = 1e308

local function sanitize(value, seen)
    local vt = type(value)
    if vt == "number" then
        if value ~= value then return 0 end          -- NaN (NaN ~= NaN)
        if value == math.huge then return MAX_FLOAT end
        if value == -math.huge then return -MAX_FLOAT end
        return value
    elseif vt == "string" or vt == "boolean" then
        return value
    elseif vt == "table" then
        if seen[value] then return nil end            -- 打断循环引用
        seen[value] = true

        local out = {}
        local intKeys = nil

        for k, v in pairs(value) do
            if type(k) == "number" and k >= 1 and math.floor(k) == k then
                -- 整数键延后处理，用于压实可能的稀疏数组
                intKeys = intKeys or {}
                intKeys[#intKeys + 1] = k
            elseif type(k) == "string" or type(k) == "number" or type(k) == "boolean" then
                local sv = sanitize(v, seen)
                if sv ~= nil then out[k] = sv end
            end
        end

        if intKeys then
            table.sort(intKeys)
            local n = 0
            for _, k in ipairs(intKeys) do
                local sv = sanitize(value[k], seen)
                if sv ~= nil then
                    n = n + 1
                    out[n] = sv                        -- 连续写入，消除空洞
                end
            end
        end

        seen[value] = nil                              -- 仅在祖先链上视为循环，允许共享子树
        return out
    end
    -- function / userdata / thread：不可序列化，丢弃
    return nil
end

-- 诊断：定位非法值（NaN/Infinity/稀疏数组）的字段路径，便于追根因
-- 仅在编码失败时调用，最多上报 maxReports 处
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
        -- 稀疏数组检测
        if value[1] ~= nil then
            local maxn = 0
            for k in pairs(value) do
                if type(k) == "number" and k > maxn then maxn = k end
            end
            for i = 1, maxn do
                if value[i] == nil then
                    reports[#reports + 1] = path .. " = <稀疏数组, 空洞@" .. i .. "/" .. maxn .. ">"
                    break
                end
            end
        end
        for k, v in pairs(value) do
            reportBadValues(v, path .. "." .. tostring(k), seen, reports, maxReports)
            if #reports >= maxReports then return end
        end
        seen[value] = nil
    end
end

local MAX_SANITIZE_REPORTS = 20  -- 留痕记录上限，避免存档无限膨胀

-- 编码存档数据，失败时先消毒再重试，绝不抛出异常
-- gameState 可选：用于把"坏字段路径"写进存档留痕（_sanitizeReports）
local function encodeSaveData(saveData, gameState)
    local ok, encoded = pcall(cjson.encode, saveData)
    if ok and encoded then
        return encoded
    end

    -- 定位非法值的具体字段路径（追根因用）
    local reports = {}
    reportBadValues(saveData.game_state, "game_state", {}, reports, 10)

    if log then
        log:Write(LOG_WARNING, "SaveManager: JSON编码失败，尝试数据消毒后重试: " .. tostring(encoded))
        if #reports > 0 then
            log:Write(LOG_ERROR, "SaveManager: 检测到非法值字段:\n  " .. table.concat(reports, "\n  "))
        end
    end

    -- 写进存档留痕：即使玩家看不到日志，将来拿到存档也能定位根因
    local cleanedGameState
    if gameState and #reports > 0 then
        gameState._sanitizeReports = gameState._sanitizeReports or {}
        table.insert(gameState._sanitizeReports, {
            saved_at = saveData.saved_at,
            fields = reports,
        })
        while #gameState._sanitizeReports > MAX_SANITIZE_REPORTS do
            table.remove(gameState._sanitizeReports, 1)
        end
        -- 重新序列化以纳入刚写入的留痕，再消毒
        cleanedGameState = sanitize(gameState:serialize(), {})
    else
        cleanedGameState = sanitize(saveData.game_state, {})
    end

    local cleaned = {
        version = saveData.version,
        saved_at = saveData.saved_at,
        game_state = cleanedGameState,
    }

    local ok2, encoded2 = pcall(cjson.encode, cleaned)
    if ok2 and encoded2 then
        return encoded2
    end

    if log then
        log:Write(LOG_ERROR, "SaveManager: JSON编码失败（消毒后仍失败）: " .. tostring(encoded2))
    end
    return nil
end

function SaveManager._doSave(gameState, slot)
    slot = slot or "auto"
    local path = SaveManager.getSavePath(slot)

    -- 确保存档目录存在
    fileSystem:CreateDir(SAVE_DIR)

    local saveData = {
        version = Constants.SAVE_VERSION,
        saved_at = string.format("%d-%02d-%02d", gameState.date.year, gameState.date.month, gameState.date.day),
        game_state = gameState:serialize(),
    }

    local jsonStr = encodeSaveData(saveData, gameState)
    if not jsonStr then
        return false
    end

    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        if log then log:Write(LOG_ERROR, "SaveManager: 无法写入文件 " .. path) end
        return false
    end
    file:WriteString(jsonStr)
    file:Close()
    if log then log:Write(LOG_INFO, "SaveManager: 已保存到 " .. path) end
    return true
end

-- 保存游戏（全程 pcall 保护：存档失败绝不能中断游戏推进/界面刷新）
function SaveManager.save(gameState, slot)
    local ok, result = pcall(SaveManager._doSave, gameState, slot)
    if not ok then
        if log then log:Write(LOG_ERROR, "SaveManager: 保存异常已捕获: " .. tostring(result)) end
        return false
    end
    return result
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
