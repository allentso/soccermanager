-- data/team_icon_registry.lua
-- 俱乐部图标路径解析（assets/Data 下的 PNG 队徽）

local JsonLoader = require("scripts/data/json_loader")

local TeamIconRegistry = {}

local _iconsByJsonId = nil

--- 懒加载 team_icons.json 映射表
local function ensureLoaded()
    if _iconsByJsonId then return end
    _iconsByJsonId = {}

    local data = JsonLoader.loadFromResource("Data/team_icons.json")
    if data and data.icons then
        for jsonId, path in pairs(data.icons) do
            if path and path ~= "" then
                _iconsByJsonId[jsonId] = path
            end
        end
    end
end

--- 根据 JSON 球队 id 获取图标资源路径
--- @param jsonTeamId string|nil
--- @return string|nil
function TeamIconRegistry.getPathByJsonId(jsonTeamId)
    if not jsonTeamId then return nil end
    ensureLoaded()
    ---@diagnostic disable-next-line: return-type-mismatch
    return _iconsByJsonId[jsonTeamId]
end

--- 解析球队图标路径（优先 jsonTeamId 查表，保证图标包更新后即时生效）
--- @param team table|nil
--- @return string|nil
function TeamIconRegistry.getPathForTeam(team)
    if not team then return nil end
    if team.jsonTeamId then
        local path = TeamIconRegistry.getPathByJsonId(team.jsonTeamId)
        if path then return path end
    end
    if team.iconPath and team.iconPath ~= "" then
        return team.iconPath
    end
    return nil
end

--- 将 hex 颜色字符串转为 RGBA 数组
--- @param hex string|nil
--- @return table
local function hexToRgba(hex)
    if not hex or hex == "" then return {60, 60, 80, 255} end
    hex = hex:gsub("#", "")
    if #hex ~= 6 then return {60, 60, 80, 255} end
    return {
        tonumber(hex:sub(1, 2), 16) or 60,
        tonumber(hex:sub(3, 4), 16) or 60,
        tonumber(hex:sub(5, 6), 16) or 80,
        255,
    }
end

--- 获取 fallback 徽章背景色（优先球队主色）
--- @param team table|nil
--- @return table
function TeamIconRegistry.getFallbackColor(team)
    if team and team.colors and team.colors.primary then
        return hexToRgba(team.colors.primary)
    end
    return {60, 60, 80, 255}
end

--- 获取 fallback 徽章文字（球队简称）
--- @param team table|nil
--- @return string
function TeamIconRegistry.getFallbackText(team)
    if not team then return "?" end
    local text = team.shortName or team.name or "?"
    if #text > 3 then
        text = text:sub(1, 3)
    end
    return text:upper()
end

return TeamIconRegistry
