-- systems/transfers/transfer_helpers.lua
-- 转会系统共享工具函数与常量

local M = {}

M.SIGN_CONFIRM_TIMEOUT_DAYS = 5
M.SIGN_CONFIRM_DEFER_DAYS = 3

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

-- 金额格式化（M/K自适应）
function M.fmtMoney(amount)
    if not amount then return "0" end
    local abs = math.abs(amount)
    if abs >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif abs >= 1000 then
        return string.format("%.0fK", amount / 1000)
    else
        return tostring(math.floor(amount))
    end
end

function M.bidIdsEqual(a, b)
    if a == nil or b == nil then return false end
    return a == b or tonumber(a) == tonumber(b)
end

local _posToGroupCache = nil
function M.posToGroup()
    if _posToGroupCache then return _posToGroupCache end
    local Constants = require("scripts/app/constants")
    local m = {}
    for group, positions in pairs(Constants.POSITION_GROUPS) do
        for _, pos in ipairs(positions) do m[pos] = group end
    end
    _posToGroupCache = m
    return m
end

function M.transferDiagEnabled(gameState)
    return gameState and gameState._transferDiag ~= nil
end

function M.transferDiagTime(TransferManager, gameState, key, fn, ...)
    if not M.transferDiagEnabled(gameState) then
        return fn(...)
    end
    local t0 = os.clock()
    local a, b, c, d, e = fn(...)
    TransferManager._transferDiagAdd(gameState, key, (os.clock() - t0) * 1000)
    return a, b, c, d, e
end

return M
