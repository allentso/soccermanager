-- ui/screens/create_manager.lua
-- 创建经理页面

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")

local CreateManager = {}

function CreateManager.create()
    local firstNameField = nil
    local lastNameField = nil

    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        padding = 20,
        children = {
            -- 标题
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60,
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
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- 表单区域
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                alignItems = "center",
                justifyContent = "center",
                paddingLeft = 20,
                paddingRight = 20,
                children = {
                    UI.Label {
                        text = "输入你的姓名",
                        fontSize = 15,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        marginBottom = 24,
                    },

                    -- 姓氏
                    UI.Label {
                        text = "姓氏",
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_MUTED,
                        width = "100%",
                        marginBottom = 6,
                    },
                    UI.TextField {
                        id = "lastName",
                        width = "100%",
                        height = 44,
                        placeholder = "请输入姓氏",
                        fontSize = 15,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 8,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginBottom = 16,
                    },

                    -- 名字
                    UI.Label {
                        text = "名字",
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_MUTED,
                        width = "100%",
                        marginBottom = 6,
                    },
                    UI.TextField {
                        id = "firstName",
                        width = "100%",
                        height = 44,
                        placeholder = "请输入名字",
                        fontSize = 15,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 8,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginBottom = 30,
                    },

                    -- 确认按钮
                    Theme.PrimaryButton {
                        text = "开始选择球队",
                        onClick = function()
                            local fnField = UI.FindById("firstName")
                            local lnField = UI.FindById("lastName")
                            local firstName = fnField and fnField:GetText() or ""
                            local lastName = lnField and lnField:GetText() or ""
                            -- 默认值
                            if firstName == "" then firstName = "Alex" end
                            if lastName == "" then lastName = "Manager" end
                            -- 传递数据到选择球队页面
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
