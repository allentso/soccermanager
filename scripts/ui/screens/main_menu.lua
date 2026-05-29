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
        backgroundColor = Theme.COLORS.BG_DARK,
        alignItems = "center",
        justifyContent = "center",
        padding = 30,
        children = {
            -- 游戏标题
            UI.Label {
                text = "OpenFoot Manager",
                fontSize = 28,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                marginBottom = 6,
            },
            UI.Label {
                text = "足球经理",
                fontSize = 16,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 50,
            },

            -- 新游戏按钮
            UI.Button {
                text = "新游戏",
                width = 220,
                height = 48,
                backgroundColor = Theme.COLORS.PRIMARY,
                borderRadius = 10,
                fontSize = 17,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                marginBottom = 16,
                onClick = function()
                    Router.navigate("create_manager")
                end,
            },

            -- 读取存档按钮
            UI.Button {
                text = "读取存档",
                width = 220,
                height = 48,
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 10,
                fontSize = 17,
                color = Theme.COLORS.TEXT_PRIMARY,
                marginBottom = 16,
                onClick = function()
                    Router.navigate("load_game")
                end,
            },

            -- 版本号
            UI.Label {
                text = "v" .. Constants.VERSION,
                fontSize = 11,
                color = Theme.COLORS.TEXT_MUTED,
                marginTop = 40,
            },
        },
    }
end

return MainMenu
