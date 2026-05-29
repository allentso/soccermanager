-- ui/screens/settings.lua
-- 设置页面 - 音量、自动保存、货币单位、游戏速度等

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local SaveManager = require("scripts/persistence/save_manager")
local EventBus = require("scripts/app/event_bus")

local Settings = {}

-- 默认设置
local _defaults = {
    masterVolume = 80,
    musicVolume = 60,
    sfxVolume = 80,
    autoSave = true,
    autoSaveInterval = 5,   -- 每5个回合自动保存
    currencyUnit = "short", -- short(K/M) | full(完整数字)
    gameSpeed = "normal",   -- slow | normal | fast
    confirmActions = true,  -- 重要操作前确认
    showTutorials = true,
}

-- 持久化设置（初始化为默认值）
local _settings = {}
for k, v in pairs(_defaults) do _settings[k] = v end

------------------------------------------------------
-- 主入口
------------------------------------------------------
function Settings.create(params)
    -- 从 gameState 读取设置
    if _G.gameState and _G.gameState.settings then
        for k, v in pairs(_G.gameState.settings) do
            _settings[k] = v
        end
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Settings._saveSettings()
                            Router.back()
                        end,
                    },
                    UI.Label {
                        text = "设置",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Button {
                        text = "重置",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 13,
                        color = Theme.COLORS.DANGER,
                        onClick = function()
                            for k, v in pairs(_defaults) do _settings[k] = v end
                            Settings._saveSettings()
                            Router.replaceWith("settings")
                        end,
                    },
                }
            },

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = {
                    -- 音频设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("音频设置"),
                            Settings._sliderRow("主音量", _settings.masterVolume, function(v)
                                _settings.masterVolume = v
                                Settings._saveSettings()
                            end),
                            Settings._sliderRow("音乐音量", _settings.musicVolume, function(v)
                                _settings.musicVolume = v
                                Settings._saveSettings()
                            end),
                            Settings._sliderRow("音效音量", _settings.sfxVolume, function(v)
                                _settings.sfxVolume = v
                                Settings._saveSettings()
                            end),
                        }
                    },

                    -- 游戏设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("游戏设置"),
                            Settings._selectRow("游戏速度", {
                                { key = "slow", label = "慢速" },
                                { key = "normal", label = "正常" },
                                { key = "fast", label = "快速" },
                            }, _settings.gameSpeed, function(v)
                                _settings.gameSpeed = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                            Settings._selectRow("货币显示", {
                                { key = "short", label = "简写(K/M)" },
                                { key = "full", label = "完整数字" },
                            }, _settings.currencyUnit, function(v)
                                _settings.currencyUnit = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                        }
                    },

                    -- 自动保存设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("存档设置"),
                            Settings._toggleRow("自动保存", _settings.autoSave, function(v)
                                _settings.autoSave = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                            _settings.autoSave and Settings._selectRow("保存频率", {
                                { key = 3, label = "每3回合" },
                                { key = 5, label = "每5回合" },
                                { key = 10, label = "每10回合" },
                            }, _settings.autoSaveInterval, function(v)
                                _settings.autoSaveInterval = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end) or UI.Panel { height = 0 },
                            Settings._toggleRow("操作确认提示", _settings.confirmActions, function(v)
                                _settings.confirmActions = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                        }
                    },

                    -- 帮助
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("关于"),
                            Settings._infoRow("版本", "v" .. Constants.VERSION),
                            Settings._infoRow("存档版本", "v" .. Constants.SAVE_VERSION),
                            Theme.Divider(),
                            UI.Button {
                                text = "查看存档管理",
                                width = "100%",
                                height = 40,
                                backgroundColor = {38, 46, 71, 255},
                                borderRadius = 8,
                                fontSize = 13,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                marginTop = 6,
                                onClick = function()
                                    Settings._saveSettings()
                                    Router.navigate("load_game")
                                end,
                            },
                        }
                    },

                    -- 底部间距
                    UI.Panel { height = 20 },
                }
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }
end

------------------------------------------------------
-- 组件工厂
------------------------------------------------------
function Settings._sectionTitle(text)
    return UI.Label {
        text = text,
        fontSize = 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginBottom = 10,
    }
end

function Settings._sliderRow(label, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 44,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                width = 70,
            },
            UI.Slider {
                flexGrow = 1,
                value = value,
                min = 0,
                max = 100,
                height = 30,
                onChange = function(self, v)
                    if onChange then onChange(math.floor(v)) end
                end,
            },
            UI.Label {
                text = tostring(math.floor(value)) .. "%",
                fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED,
                width = 40,
                textAlign = "right",
            },
        }
    }
end

function Settings._toggleRow(label, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 44,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexGrow = 1,
            },
            UI.Button {
                text = value and "开启" or "关闭",
                width = 60, height = 30,
                backgroundColor = value and Theme.COLORS.SECONDARY or {60, 60, 80, 255},
                borderRadius = 15,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    if onChange then onChange(not value) end
                end,
            },
        }
    }
end

function Settings._selectRow(label, options, currentValue, onChange)
    local btns = {}
    for _, opt in ipairs(options) do
        local isActive = opt.key == currentValue
        table.insert(btns, UI.Button {
            text = opt.label,
            height = 28,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 4,
            onClick = function()
                if onChange then onChange(opt.key) end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        marginBottom = 8,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 6,
            },
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                children = btns,
            },
        }
    }
end

function Settings._infoRow(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 36,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexGrow = 1,
            },
            UI.Label {
                text = value,
                fontSize = 13,
                color = Theme.COLORS.TEXT_MUTED,
            },
        }
    }
end

------------------------------------------------------
-- 保存设置到 gameState
------------------------------------------------------
function Settings._saveSettings()
    if _G.gameState then
        _G.gameState.settings = {}
        for k, v in pairs(_settings) do
            _G.gameState.settings[k] = v
        end
        -- 持久化到磁盘
        SaveManager.save(_G.gameState, "auto")
    end
end

return Settings
