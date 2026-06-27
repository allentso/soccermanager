-- ui/screens/create_manager.lua
-- 创建经理页面

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")

local CreateManager = {}

local _includeCSL = false
local _includeSecondDivisions = false
local _enableReincarnation = true

local function _toggleIncludeCSLRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginBottom = 28,
        paddingLeft = 4,
        paddingRight = 4,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                marginRight = 12,
                children = {
                    UI.Label {
                        text = "加载中超联赛数据",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "16支球队 · 第2赛季起冠军参加欧冠（占英超额外名额）",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 4,
                    },
                }
            },
            UI.Button {
                text = _includeCSL and "已开启" or "点击开启",
                width = 80,
                height = 32,
                borderRadius = 16,
                backgroundColor = _includeCSL and Theme.COLORS.SECONDARY or Theme.COLORS.BG_CARD_ELEVATED,
                fontSize = 12,
                color = _includeCSL and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = "bold",
                onClick = function()
                    _includeCSL = not _includeCSL
                    Router.replaceWith("create_manager")
                end,
            },
        }
    }
end

local function _toggleIncludeSecondDivisionsRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginBottom = 28,
        paddingLeft = 4,
        paddingRight = 4,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                marginRight = 12,
                children = {
                    UI.Label {
                        text = "加载次级联赛数据",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "英冠/西乙/意乙/德乙/法乙 · 可执教 · 3升3降",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 4,
                    },
                }
            },
            UI.Button {
                text = _includeSecondDivisions and "已开启" or "点击开启",
                width = 80,
                height = 32,
                borderRadius = 16,
                backgroundColor = _includeSecondDivisions and Theme.COLORS.SECONDARY or Theme.COLORS.BG_CARD_ELEVATED,
                fontSize = 12,
                color = _includeSecondDivisions and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = "bold",
                onClick = function()
                    _includeSecondDivisions = not _includeSecondDivisions
                    Router.replaceWith("create_manager")
                end,
            },
        }
    }
end

local function _toggleEnableReincarnationRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        marginBottom = 28,
        paddingLeft = 4,
        paddingRight = 4,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                marginRight = 12,
                children = {
                    UI.Label {
                        text = "开启转生/重生机制",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "开档重生小妖 + 退役转生为16岁青训",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 4,
                    },
                }
            },
            UI.Button {
                text = _enableReincarnation and "已开启" or "已关闭",
                width = 80,
                height = 32,
                borderRadius = 16,
                backgroundColor = _enableReincarnation and Theme.COLORS.SECONDARY or Theme.COLORS.BG_CARD_ELEVATED,
                fontSize = 12,
                color = _enableReincarnation and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = "bold",
                onClick = function()
                    _enableReincarnation = not _enableReincarnation
                    Router.replaceWith("create_manager")
                end,
            },
        }
    }
end

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
                        marginBottom = 20,
                    },

                    _toggleIncludeCSLRow(),

                    _toggleIncludeSecondDivisionsRow(),

                    _toggleEnableReincarnationRow(),

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
                                includeCSL = _includeCSL,
                                includeSecondDivisions = _includeSecondDivisions,
                                enableReincarnation = _enableReincarnation,
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
