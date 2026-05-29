-- ui/theme.lua
-- UI主题配置和通用组件工厂

local Constants = require("scripts/app/constants")
local UI = require("urhox-libs/UI")

local Theme = {}

Theme.COLORS = Constants.COLORS

-- 通用卡片
function Theme.Card(props)
    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 12,
        padding = 14,
        marginBottom = 10,
        children = props.children or {},
    }
end

-- 顶部状态栏
function Theme.TopBar(props)
    return UI.Panel {
        width = "100%",
        height = 52,
        backgroundColor = Theme.COLORS.BG_HEADER,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14,
        paddingRight = 14,
        children = props.children or {},
    }
end

-- 底部导航栏
function Theme.BottomNav(props)
    return UI.Panel {
        width = "100%",
        height = 60,
        backgroundColor = Theme.COLORS.BG_HEADER,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-around",
        borderTopWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = props.children or {},
    }
end

-- 导航按钮
function Theme.NavButton(props)
    local isActive = props.active or false
    return UI.Button {
        text = props.label or "",
        width = 60,
        height = 44,
        backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
        borderRadius = 8,
        fontSize = 12,
        color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = props.onClick,
    }
end

-- 二级导航标签栏
-- items: { { key, label, screen, params? }, ... }
-- activeKey: 当前激活的子标签 key
function Theme.SubNav(items, activeKey)
    local Router = require("scripts/app/router")
    local tabs = {}
    for _, item in ipairs(items) do
        local isActive = item.key == activeKey
        table.insert(tabs, UI.Button {
            text = item.label,
            height = 32,
            paddingLeft = 14,
            paddingRight = 14,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 4,
            onClick = function()
                if not isActive then
                    Router.replaceWith(item.screen, item.params)
                end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = Theme.COLORS.BG_HEADER,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = tabs,
    }
end

-- 球队组二级导航: 阵容 / 训练 / 战术
function Theme.SquadSubNav(activeKey)
    return Theme.SubNav({
        { key = "squad",    label = "阵容", screen = "squad" },
        { key = "training", label = "训练", screen = "training" },
        { key = "tactics",  label = "战术", screen = "tactics" },
        { key = "youth",    label = "青训", screen = "youth" },
        { key = "staff",    label = "职员", screen = "staff" },
    }, activeKey)
end

-- 更多组二级导航: 消息 / 新闻 / 财务
function Theme.MoreSubNav(activeKey)
    return Theme.SubNav({
        { key = "inbox",   label = "消息", screen = "inbox" },
        { key = "news",    label = "新闻", screen = "news" },
        { key = "finance", label = "财务", screen = "finance" },
    }, activeKey)
end

-- 市场组二级导航: 转会 / 球探 / 转会中心
function Theme.MarketSubNav(activeKey)
    return Theme.SubNav({
        { key = "market",       label = "转会市场", screen = "market" },
        { key = "transfer_hub", label = "转会中心", screen = "transfer_hub" },
        { key = "scouting",     label = "球探", screen = "scouting" },
    }, activeKey)
end

-- 全局统一底部导航栏
-- activeTab: "home" | "squad" | "league" | "market"
function Theme.MainNav(activeTab)
    local Router = require("scripts/app/router")
    return Theme.BottomNav {
        children = {
            Theme.NavButton {
                label = "赛事",
                active = (activeTab == "league"),
                onClick = function()
                    if activeTab ~= "league" then Router.navigate("league") end
                end,
            },
            Theme.NavButton {
                label = "球队",
                active = (activeTab == "squad"),
                onClick = function()
                    if activeTab ~= "squad" then Router.navigate("squad") end
                end,
            },
            Theme.NavButton {
                label = "主页",
                active = (activeTab == "home"),
                onClick = function()
                    if activeTab ~= "home" then Router.navigate("dashboard") end
                end,
            },
            Theme.NavButton {
                label = "市场",
                active = (activeTab == "market"),
                onClick = function()
                    if activeTab ~= "market" then Router.navigate("market") end
                end,
            },
        }
    }
end

-- 标题文本
function Theme.Title(props)
    return UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 18,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginBottom = props.marginBottom or 8,
    }
end

-- 副标题
function Theme.Subtitle(props)
    return UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 13,
        color = Theme.COLORS.TEXT_SECONDARY,
        marginBottom = props.marginBottom or 4,
    }
end

-- 数据标签
function Theme.StatPill(props)
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = props.bgColor or {38, 46, 71, 255},
        borderRadius = 6,
        paddingLeft = 8,
        paddingRight = 8,
        paddingTop = 4,
        paddingBottom = 4,
        marginRight = 6,
        marginBottom = 4,
        children = {
            UI.Label {
                text = props.label or "",
                fontSize = 11,
                color = Theme.COLORS.TEXT_MUTED,
                marginRight = 4,
            },
            UI.Label {
                text = tostring(props.value or ""),
                fontSize = 12,
                color = props.valueColor or Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
            },
        }
    }
end

-- 球员行组件
function Theme.PlayerRow(props)
    local player = props.player
    if not player then return UI.Panel{height=0} end

    local posColor = Theme.COLORS.TEXT_SECONDARY
    if player.position == "GK" then posColor = {255, 204, 0, 255}
    elseif player.position == "CB" or player.position == "LB" or player.position == "RB" then posColor = {77, 179, 255, 255}
    elseif player.position == "ST" or player.position == "CF" or player.position == "LW" or player.position == "RW" then posColor = {255, 102, 102, 255}
    else posColor = {102, 255, 128, 255}
    end

    return UI.Panel {
        width = "100%",
        height = 52,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 位置
            UI.Label {
                text = Constants.POSITION_NAMES[player.position] or player.position,
                fontSize = 12,
                color = posColor,
                width = 48,
                fontWeight = "bold",
            },
            -- 姓名
            UI.Label {
                text = player.displayName or (player.firstName .. " " .. player.lastName),
                fontSize = 14,
                color = Theme.COLORS.TEXT_PRIMARY,
                flexGrow = 1,
            },
            -- 能力
            UI.Label {
                text = tostring(player.overall),
                fontSize = 14,
                color = player.overall >= 70 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_SECONDARY,
                width = 30,
                fontWeight = "bold",
            },
            -- 状态
            UI.Label {
                text = player.injured and "伤" or tostring(player.fitness),
                fontSize = 12,
                color = player.injured and Theme.COLORS.DANGER or Theme.COLORS.TEXT_MUTED,
                width = 30,
            },
        },
        onClick = props.onClick,
    }
end

-- 分隔线
function Theme.Divider()
    return UI.Panel {
        width = "100%",
        height = 1,
        backgroundColor = Theme.COLORS.BORDER,
        marginTop = 6,
        marginBottom = 6,
    }
end

-- 操作按钮（主要）
function Theme.PrimaryButton(props)
    return UI.Button {
        text = props.text or "确认",
        width = props.width or "100%",
        height = props.height or 44,
        backgroundColor = Theme.COLORS.PRIMARY,
        borderRadius = 8,
        fontSize = 15,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        onClick = props.onClick,
    }
end

-- 操作按钮（次要）
function Theme.SecondaryButton(props)
    return UI.Button {
        text = props.text or "取消",
        width = props.width or "100%",
        height = props.height or 44,
        backgroundColor = {51, 59, 84, 255},
        borderRadius = 8,
        fontSize = 15,
        color = Theme.COLORS.TEXT_SECONDARY,
        onClick = props.onClick,
    }
end

return Theme
