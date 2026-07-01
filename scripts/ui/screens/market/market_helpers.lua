-- ui/screens/market/market_helpers.lua
-- 转会市场 UI 共享工具

local Constants = require("scripts/app/constants")
local PotentialSystem = require("scripts/systems/potential_system")

local M = {}

function M.getScoutAccuracy(gameState)
    local ScoutManager = require("scripts/systems/scout_manager")
    return ScoutManager.getAccuracy(gameState)
end

function M.getPotentialStars(potential, scoutAccuracy)
    local gs = _G.gameState
    if gs and gs.potentialRevealed then
        local rating = PotentialSystem.rawToRating(potential)
        return 5, string.format("%.1f", rating)
    end

    local paRating = PotentialSystem.rawToRating(potential)
    local exactStars = (paRating - 1.0) / 9.0 * 4.0 + 1.0
    local accuracy = scoutAccuracy or 0.6
    local maxError = (1.0 - accuracy) * 1.5
    local seed = potential * 7 + 13
    local pseudoRandom = (math.sin(seed) * 10000) % 1.0
    local errorOffset = (pseudoRandom - 0.5) * 2 * maxError
    local displayStars = math.floor(exactStars + errorOffset + 0.5)
    displayStars = math.max(1, math.min(5, displayStars))
    local starText = string.rep("★", displayStars) .. string.rep("☆", 5 - displayStars)
    return displayStars, starText
end

function M.getPositionGroup(pos)
    for group, positions in pairs(Constants.POSITION_GROUPS) do
        for _, p in ipairs(positions) do
            if p == pos then return group end
        end
    end
    return "MID"
end

return M
