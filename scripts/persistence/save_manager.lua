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

-- 保存游戏
function SaveManager.save(gameState, slot)
    slot = slot or "auto"
    local path = SaveManager.getSavePath(slot)

    -- 确保存档目录存在
    fileSystem:CreateDir(SAVE_DIR)

    local saveData = {
        version = Constants.SAVE_VERSION,
        saved_at = string.format("%d-%02d-%02d", gameState.date.year, gameState.date.month, gameState.date.day),
        game_state = gameState:serialize(),
    }

    local jsonStr = cjson.encode(saveData)
    if not jsonStr then
        log:Write(LOG_ERROR, "SaveManager: JSON编码失败")
        return false
    end

    local file = File(path, FILE_WRITE)
    if not file or not file:IsOpen() then
        log:Write(LOG_ERROR, "SaveManager: 无法写入文件 " .. path)
        return false
    end
    file:WriteString(jsonStr)
    file:Close()
    log:Write(LOG_INFO, "SaveManager: 已保存到 " .. path)
    return true
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
        local oldVersion = saveData.version or 1
        if oldVersion < Constants.SAVE_VERSION then
            local newVersion = Migrations.run(saveData)
            log:Write(LOG_INFO, "SaveManager: 存档从 v" .. oldVersion .. " 迁移到 v" .. newVersion)
        end

        gameState:deserialize(saveData.game_state)
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
