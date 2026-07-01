-- systems/youth/youth_helpers.lua
-- 青训系统共享工具函数

local Constants = require("scripts/app/constants")

local M = {}

function M.randInt(minValue, maxValue)
    if maxValue == nil then
        maxValue = minValue
        minValue = 1
    end
    if maxValue < minValue then
        minValue, maxValue = maxValue, minValue
    end
    return minValue + math.floor(Random() * (maxValue - minValue + 1))
end

function M.mapPosition(pos, positionMap)
    if not pos then return "ST" end
    return Constants.normalizePosition((positionMap or {})[pos] or pos) or "ST"
end

return M
