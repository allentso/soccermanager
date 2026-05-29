-- ui/components/team_icon.lua
-- 俱乐部图标组件：有队徽则显示 PNG，否则显示简称 fallback 徽章
--
-- 用法：
--   local TeamIcon = require("scripts/ui/components/team_icon")
--   TeamIcon { team = teamObj, size = 36 }
--   TeamIcon.listItem { size = 44, id = "icon" }  -- VirtualList 模板
--   TeamIcon.bindListItem(widget, team)           -- VirtualList bindItem

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local TeamIconRegistry = require("scripts/data/team_icon_registry")

local TeamIcon = {}

--- @param props table
---   team: table|nil - 球队对象
---   size?: number - 边长，默认 36
---   marginRight?: number
---   marginLeft?: number
---   id?: string
function TeamIcon.create(props)
    local team = props.team
    local size = props.size or 36
    local iconPath = TeamIconRegistry.getPathForTeam(team)
    local radius = math.floor(size / 2)

    if iconPath then
        return UI.Panel {
            width = size,
            height = size,
            marginRight = props.marginRight,
            marginLeft = props.marginLeft,
            overflow = "hidden",
            borderRadius = radius,
            backgroundImage = iconPath,
            backgroundFit = "contain",
            id = props.id,
        }
    end

    return TeamIcon._fallbackBadge(team, size, props)
end

--- VirtualList 列表项图标模板（bind 时切换 backgroundImage 或 fallback 文字）
function TeamIcon.listItem(props)
    local size = props.size or 36
    local radius = math.floor(size / 2)

    return UI.Panel {
        id = props.id or "icon",
        width = size,
        height = size,
        marginRight = props.marginRight,
        marginLeft = props.marginLeft,
        backgroundColor = {60, 60, 80, 255},
        borderRadius = radius,
        justifyContent = "center",
        alignItems = "center",
        overflow = "hidden",
        backgroundFit = "contain",
        children = {
            UI.Label {
                id = "iconText",
                fontSize = size >= 32 and 11 or 9,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
            },
        },
    }
end

--- VirtualList bindItem 时更新图标
--- @param widget any 带 id="icon" 的 Panel
--- @param team table|nil
function TeamIcon.bindListItem(widget, team)
    if not widget then return end

    local iconPath = TeamIconRegistry.getPathForTeam(team)
    local bgColor = TeamIconRegistry.getFallbackColor(team)
    local text = TeamIconRegistry.getFallbackText(team)

    if iconPath then
        widget:SetStyle({
            backgroundColor = {0, 0, 0, 0},
            backgroundImage = iconPath,
        })
    else
        widget:SetStyle({
            backgroundColor = bgColor,
            backgroundImage = "",
        })
    end

    local lbl = widget:FindById("iconText")
    if lbl then
        if iconPath then
            lbl:SetVisible(false)
        else
            lbl:SetText(text)
            lbl:SetVisible(true)
        end
    end
end

function TeamIcon._fallbackBadge(team, size, props)
    local radius = math.floor(size / 2)
    return UI.Panel {
        width = size,
        height = size,
        marginRight = props.marginRight,
        marginLeft = props.marginLeft,
        backgroundColor = TeamIconRegistry.getFallbackColor(team),
        borderRadius = radius,
        justifyContent = "center",
        alignItems = "center",
        id = props.id,
        children = {
            UI.Label {
                text = TeamIconRegistry.getFallbackText(team),
                fontSize = size >= 32 and 11 or 9,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
            },
        },
    }
end

setmetatable(TeamIcon, {
    __call = function(_, props)
        return TeamIcon.create(props)
    end,
})

return TeamIcon
