---@diagnostic disable: param-type-mismatch
-- ui/screens/main_menu.lua
-- 主菜单页面

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local SaveManager = require("scripts/persistence/save_manager")
local Constants = require("scripts/app/constants")

local MainMenu = {}

function MainMenu.create()
    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = "#000000",
        backgroundImage = "image/splash_coach_bench.png",
        justifyContent = "flex-end",
        alignItems = "center",
        paddingBottom = 60,
        children = {
            -- 游戏标题区域
            UI.Panel {
                width = "100%",
                alignItems = "center",
                marginBottom = 40,
                children = {
                    -- 主标题
                    UI.Label {
                        text = "足球经理",
                        fontSize = 52,
                        fontWeight = "bold",
                        color = "#FFFFFF",
                        letterSpacing = 10,
                        textShadowColor = "rgba(212,175,55,0.7)",
                        textShadowOffset = { x = 0, y = 2 },
                        textShadowRadius = 16,
                    },
                    -- 副标题行：装饰线 + 文字 + 装饰线
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        marginTop = 12,
                        children = {
                            -- 左装饰线
                            UI.Panel {
                                width = 36,
                                height = 1,
                                backgroundColor = "rgba(212,175,55,0.6)",
                            },
                            -- 菱形点缀
                            UI.Label {
                                text = "◆",
                                fontSize = 8,
                                color = "rgba(212,175,55,0.8)",
                                marginLeft = 8,
                                marginRight = 8,
                            },
                            UI.Label {
                                text = "冠军之路",
                                fontSize = 20,
                                color = "rgba(212,175,55,0.95)",
                                letterSpacing = 8,
                                fontWeight = "bold",
                                textShadowColor = "rgba(212,175,55,0.5)",
                                textShadowOffset = { x = 0, y = 0 },
                                textShadowRadius = 8,
                            },
                            -- 菱形点缀
                            UI.Label {
                                text = "◆",
                                fontSize = 8,
                                color = "rgba(212,175,55,0.8)",
                                marginLeft = 8,
                                marginRight = 8,
                            },
                            -- 右装饰线
                            UI.Panel {
                                width = 36,
                                height = 1,
                                backgroundColor = "rgba(212,175,55,0.6)",
                            },
                        },
                    },
                },
            },

            -- 新游戏按钮（主按钮，金色渐变感）
            UI.Panel {
                width = 280,
                height = 56,
                borderRadius = 28,
                backgroundColor = "rgba(212,175,55,0.9)",
                justifyContent = "center",
                alignItems = "center",
                marginBottom = 14,
                shadowColor = "rgba(212,175,55,0.4)",
                shadowOffset = { x = 0, y = 4 },
                shadowRadius = 12,
                onClick = function()
                    Router.navigate("create_manager")
                end,
                children = {
                    UI.Label {
                        text = "开始新赛季",
                        fontSize = 19,
                        fontWeight = "bold",
                        color = "#1A1A1A",
                        letterSpacing = 3,
                    },
                },
            },

            -- 读取存档按钮（次要按钮，边框风格）
            UI.Panel {
                width = 280,
                height = 56,
                borderRadius = 28,
                backgroundColor = "rgba(255,255,255,0.06)",
                borderWidth = 1,
                borderColor = "rgba(255,255,255,0.25)",
                justifyContent = "center",
                alignItems = "center",
                marginBottom = 24,
                onClick = function()
                    Router.navigate("load_game")
                end,
                children = {
                    UI.Label {
                        text = "读取存档",
                        fontSize = 18,
                        color = "rgba(255,255,255,0.85)",
                        letterSpacing = 3,
                    },
                },
            },

            -- 版本号（只显示大版本号）
            UI.Label {
                text = Constants.VERSION_MAJOR,
                fontSize = 13,
                color = "rgba(255,255,255,0.3)",
            },
        },
    }
end

return MainMenu
