-- systems/audio_manager.lua
-- 音频管理器：仅保留比赛相关音效

local SettingsManager = require("scripts/persistence/settings_manager")

local AudioManager = {}

-- 音效路径映射
AudioManager.SFX = {
    -- 比赛相关
    WHISTLE       = "audio/sfx/match_whistle.ogg",
    CROWD_CHEER   = "audio/sfx/crowd_cheer.ogg",
    CROWD_AMBIENT = "audio/sfx/crowd_ambient.ogg",
    -- UI 反馈
    UI_TAP        = "audio/sfx/ui_tap.ogg",
    UI_DENY       = "audio/sfx/ui_deny.ogg",
}

-- 内部状态
local _sfxNode = nil
local _ambientNode = nil
local _ambientSource = nil
local _initialized = false

------------------------------------------------------
-- 初始化
------------------------------------------------------
function AudioManager.init()
    if _initialized then return end
    _initialized = true

    -- 创建音效播放节点
    _sfxNode = Node()

    -- 创建球场氛围音播放节点（独立控制，可循环）
    _ambientNode = Node()
    _ambientSource = _ambientNode:CreateComponent("SoundSource")
    _ambientSource.soundType = SOUND_EFFECT
    _ambientSource.gain = 0.4
end

------------------------------------------------------
-- 音效播放
------------------------------------------------------
function AudioManager.playSFX(path, gain)
    if not _initialized then AudioManager.init() end
    if not path then return end

    -- 检查音效音量是否为0（避免无意义播放）
    local sfxVol = (SettingsManager.get("sfxVolume") or 80) / 100
    local masterVol = (SettingsManager.get("masterVolume") or 80) / 100
    if sfxVol <= 0 or masterVol <= 0 then return end

    local sound = cache:GetResource("Sound", path)
    if not sound then
        log:Write(LOG_WARNING, "AudioManager: 无法加载音效 " .. tostring(path))
        return
    end

    -- 为每个音效创建独立的 SoundSource（允许同时播放多个音效）
    local source = _sfxNode:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source.gain = gain or 1.0
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sound)
end

------------------------------------------------------
-- 球场氛围音（比赛模拟持续播放）
------------------------------------------------------
function AudioManager.startCrowdAmbient()
    if not _initialized then AudioManager.init() end
    local sound = cache:GetResource("Sound", AudioManager.SFX.CROWD_AMBIENT)
    if not sound then return end
    sound.looped = true
    _ambientSource.gain = 0.4
    _ambientSource:Play(sound)
end

function AudioManager.stopCrowdAmbient()
    if _ambientSource then
        _ambientSource:Stop()
    end
end

function AudioManager.isCrowdAmbientPlaying()
    return _ambientSource and _ambientSource.playing
end

------------------------------------------------------
-- 比赛音效便捷方法
------------------------------------------------------
function AudioManager.whistle()
    AudioManager.playSFX(AudioManager.SFX.WHISTLE, 0.5)
end

function AudioManager.cheer()
    AudioManager.playSFX(AudioManager.SFX.CROWD_CHEER, 0.9)
end

------------------------------------------------------
-- UI 反馈音效
------------------------------------------------------
function AudioManager.tap()
    AudioManager.playSFX(AudioManager.SFX.UI_TAP, 0.4)
end

function AudioManager.deny()
    AudioManager.playSFX(AudioManager.SFX.UI_DENY, 0.45)
end

return AudioManager
