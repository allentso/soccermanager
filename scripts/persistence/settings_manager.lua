-- persistence/settings_manager.lua
-- 设置持久化：独立于游戏存档，全局设置读写

local Constants = require("scripts/app/constants")
local EventBus = require("scripts/app/event_bus")

local SettingsManager = {}

------------------------------------------------------
-- 配置
------------------------------------------------------
local SETTINGS_FILE = "settings.json"

-- 默认设置值
local DEFAULTS = {
    -- 音频
    masterVolume = 80,
    musicVolume = 60,
    sfxVolume = 80,

    -- 游戏
    autoSave = true,
    autoSaveInterval = 5,   -- 每N个回合自动保存
    currencyUnit = "short", -- "short" (K/M) | "full"
    gameSpeed = "normal",   -- "slow" | "normal" | "fast"
    confirmActions = true,  -- 重要操作前确认弹窗

    -- 显示
    showTutorials = true,
    showNotifications = true,
    compactMode = false,    -- 紧凑UI模式
}

-- 运行时设置缓存
local _cache = nil

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 初始化：从文件加载设置，若文件不存在则使用默认值
function SettingsManager.init()
    _cache = SettingsManager._loadFromFile()
    if not _cache then
        _cache = {}
        for k, v in pairs(DEFAULTS) do
            _cache[k] = v
        end
    end
    -- 补齐新增字段
    for k, v in pairs(DEFAULTS) do
        if _cache[k] == nil then
            _cache[k] = v
        end
    end

    -- 同步到 gameState（如果已有）
    SettingsManager._syncToGameState()

    -- 应用音频设置
    SettingsManager._applyAudio()
end

--- 获取设置值
---@param key string
---@return any
function SettingsManager.get(key)
    if not _cache then SettingsManager.init() end
    local val = _cache[key]
    if val ~= nil then return val end
    return DEFAULTS[key]
end

--- 设置值并自动持久化
---@param key string
---@param value any
function SettingsManager.set(key, value)
    if not _cache then SettingsManager.init() end
    _cache[key] = value
    SettingsManager._saveToFile()
    SettingsManager._syncToGameState()

    -- 音频设置即时生效
    if key == "masterVolume" or key == "musicVolume" or key == "sfxVolume" then
        SettingsManager._applyAudio()
    end

    EventBus.emit("settings_changed", { key = key, value = value })
end

--- 批量设置
---@param kvPairs table {key = value, ...}
function SettingsManager.setMultiple(kvPairs)
    if not _cache then SettingsManager.init() end
    local audioChanged = false
    for k, v in pairs(kvPairs) do
        _cache[k] = v
        if k == "masterVolume" or k == "musicVolume" or k == "sfxVolume" then
            audioChanged = true
        end
    end
    SettingsManager._saveToFile()
    SettingsManager._syncToGameState()
    if audioChanged then
        SettingsManager._applyAudio()
    end
    EventBus.emit("settings_changed", { bulk = true })
end

--- 重置为默认值
function SettingsManager.resetToDefaults()
    _cache = {}
    for k, v in pairs(DEFAULTS) do
        _cache[k] = v
    end
    SettingsManager._saveToFile()
    SettingsManager._syncToGameState()
    SettingsManager._applyAudio()
    EventBus.emit("settings_changed", { reset = true })
end

--- 获取所有设置（副本）
---@return table
function SettingsManager.getAll()
    if not _cache then SettingsManager.init() end
    local copy = {}
    for k, v in pairs(_cache) do
        copy[k] = v
    end
    return copy
end

--- 获取默认值
---@return table
function SettingsManager.getDefaults()
    local copy = {}
    for k, v in pairs(DEFAULTS) do
        copy[k] = v
    end
    return copy
end

--- 检查自动保存是否应触发（基于回合计数）
---@param turnCount number 当前回合数
---@return boolean
function SettingsManager.shouldAutoSave(turnCount)
    if not SettingsManager.get("autoSave") then return false end
    local interval = SettingsManager.get("autoSaveInterval") or 5
    return (turnCount % interval) == 0
end

------------------------------------------------------
-- 内部实现
------------------------------------------------------

--- 从文件加载
function SettingsManager._loadFromFile()
    if not fileSystem:FileExists(SETTINGS_FILE) then
        return nil
    end

    local file = File(SETTINGS_FILE, FILE_READ)
    if not file or not file:IsOpen() then
        return nil
    end

    local content = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, content)
    if not ok or type(data) ~= "table" then
        log:Write(LOG_WARNING, "SettingsManager: 设置文件解析失败，使用默认值")
        return nil
    end
    return data
end

--- 保存到文件
function SettingsManager._saveToFile()
    if not _cache then return end

    local jsonStr = cjson.encode(_cache)
    if not jsonStr then
        log:Write(LOG_ERROR, "SettingsManager: JSON编码失败")
        return
    end

    local file = File(SETTINGS_FILE, FILE_WRITE)
    if not file or not file:IsOpen() then
        log:Write(LOG_ERROR, "SettingsManager: 无法写入设置文件")
        return
    end
    file:WriteString(jsonStr)
    file:Close()
end

--- 同步到 gameState.settings（供 UI 读取）
function SettingsManager._syncToGameState()
    if _G.gameState then
        _G.gameState.settings = SettingsManager.getAll()
    end
end

--- 应用音频设置到引擎
function SettingsManager._applyAudio()
    if not audio then return end
    local master = (SettingsManager.get("masterVolume") or 80) / 100
    local music = (SettingsManager.get("musicVolume") or 60) / 100
    local sfx = (SettingsManager.get("sfxVolume") or 80) / 100

    -- 引擎音频设置
    audio:SetMasterGain(SOUND_MASTER, master)
    audio:SetMasterGain(SOUND_MUSIC, master * music)
    audio:SetMasterGain(SOUND_EFFECT, master * sfx)
end

return SettingsManager
