-- ui/screens/create_manager.lua
-- 创建经理页面

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")

local CreateManager = {}

function CreateManager.create()
    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "← 返回",
                        width = 80,
                        height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Router.back()
                        end,
                    },
                    UI.Label {
                        text = "创建经理",
                        fontSize = 17,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 80 },
                }
            },

            -- 表单区域
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                alignItems = "center",
                justifyContent = "center",
                paddingLeft = 32,
                paddingRight = 32,
                children = {
                    -- 装饰图标
                    UI.Label {
                        text = "⚽",
                        fontSize = 40,
                        marginBottom = 16,
                    },
                    UI.Label {
                        text = "你的执教生涯从这里开始",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginBottom = 6,
                    },
                    UI.Label {
                        text = "输入你作为主教练的姓名",
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 36,
                    },

                    -- 姓氏输入框
                    UI.Label {
                        text = "姓氏",
                        fontSize = 12,
                        color = Theme.COLORS.GOLD,
                        width = "100%",
                        marginBottom = 6,
                        fontWeight = "bold",
                        letterSpacing = 1,
                    },
                    UI.TextField {
                        id = "lastName",
                        width = "100%",
                        height = 48,
                        placeholder = "请输入姓氏",
                        fontSize = 15,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = Theme.COLORS.BORDER,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginBottom = 18,
                        paddingLeft = 14,
                    },

                    -- 名字输入框
                    UI.Label {
                        text = "名字",
                        fontSize = 12,
                        color = Theme.COLORS.GOLD,
                        width = "100%",
                        marginBottom = 6,
                        fontWeight = "bold",
                        letterSpacing = 1,
                    },
                    UI.TextField {
                        id = "firstName",
                        width = "100%",
                        height = 48,
                        placeholder = "请输入名字",
                        fontSize = 15,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = Theme.COLORS.BORDER,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginBottom = 36,
                        paddingLeft = 14,
                    },

                    -- 确认按钮
                    Theme.PrimaryButton {
                        text = "选择你的球队 →",
                        onClick = function()
                            local fnField = UI.FindById("firstName")
                            local lnField = UI.FindById("lastName")
                            local firstName = fnField and fnField:GetText() or ""
                            local lastName = lnField and lnField:GetText() or ""
                            if firstName == "" then firstName = "Alex" end
                            if lastName == "" then lastName = "Manager" end
                            NavigateTo("select_team", {
                                firstName = firstName,
                                lastName = lastName,
                            })
                        end,
                    },
                }
            },
        },
    }

    return page
end

return CreateManager
