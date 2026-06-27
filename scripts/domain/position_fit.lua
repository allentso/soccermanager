-- domain/position_fit.lua
-- 位置适性系数与适配得分（比赛 + UI 统一）

local FormationShape = require("scripts/match/formation_shape")
local Constants = require("scripts/app/constants")

local PositionFit = {}

PositionFit.PRIMARY_MUL = 1.00
PositionFit.NATURAL_MUL = 0.95
PositionFit.LEARNING_MIN = 0.70
PositionFit.LEARNING_MAX = 0.90
PositionFit.MISMATCH_FLOOR = 0.30
PositionFit.LEARN_COMPAT_MIN = 0.6
PositionFit.MAX_NATURAL_POSITIONS = 3

local function compatMatrix()
    return FormationShape.SLOT_COMPATIBILITY
end

function PositionFit.hasNaturalPosition(player, slotPos)
    if not player or not slotPos then return false end
    slotPos = Constants.normalizePosition(slotPos)
    if not slotPos then return false end
    for _, pos in ipairs(player.naturalPositions or {}) do
        if Constants.normalizePosition(pos) == slotPos then return true end
    end
    return false
end

function PositionFit.getCompatMul(slotPos, playerPos)
    slotPos = Constants.normalizePosition(slotPos)
    playerPos = Constants.normalizePosition(playerPos)
    if not slotPos or not playerPos then return PositionFit.MISMATCH_FLOOR end
    if slotPos == playerPos then return 1.0 end
    local row = compatMatrix()[slotPos]
    if row and row[playerPos] then
        return row[playerPos]
    end
    return PositionFit.MISMATCH_FLOOR
end

--- 位置适性乘数（比赛攻防贡献用）
--- 优先级：主位置 > 学习目标 > 副位置 > 错位
function PositionFit.getFitMul(player, slotPos)
    if not player or not slotPos then return 1.0 end
    slotPos = Constants.normalizePosition(slotPos)
    if not slotPos then return PositionFit.MISMATCH_FLOOR end

    local primary = Constants.normalizePosition(player.position)
    if slotPos == primary then
        return PositionFit.PRIMARY_MUL
    end

    local target = Constants.normalizePosition(player.positionTrainingTarget)
    if target and slotPos == target then
        local progress = player.positionTrainingProgress or 0
        local t = math.max(0, math.min(100, progress)) / 100
        return PositionFit.LEARNING_MIN
            + (PositionFit.LEARNING_MAX - PositionFit.LEARNING_MIN) * t
    end

    if PositionFit.hasNaturalPosition(player, slotPos) then
        return PositionFit.NATURAL_MUL
    end

    return PositionFit.getCompatMul(slotPos, primary)
end

--- UI / AI 适配得分
function PositionFit.getPositionScore(player, slotPos)
    if not player then return 0 end
    local ovr = player.overall or 50
    return ovr * PositionFit.getFitMul(player, slotPos)
end

function PositionFit.canLearnPosition(player, slotPos)
    if not player or not slotPos then return false end
    slotPos = Constants.normalizePosition(slotPos)
    if not slotPos then return false end
    local primary = Constants.normalizePosition(player.position)
    if primary == "GK" or slotPos == "GK" then
        return primary == "GK" and slotPos == "GK"
    end
    if PositionFit.hasNaturalPosition(player, slotPos) then
        return false
    end
    if #(player.naturalPositions or {}) >= PositionFit.MAX_NATURAL_POSITIONS then
        return false
    end
    local row = compatMatrix()[primary]
    if not row then return false end
    return (row[slotPos] or 0) >= PositionFit.LEARN_COMPAT_MIN
end

function PositionFit.getLearnablePositions(player)
    local out = {}
    if not player then return out end
    local primary = Constants.normalizePosition(player.position)
    local row = compatMatrix()[primary]
    if not row then return out end

    local seen = {}
    for pos, compat in pairs(row) do
        if compat >= PositionFit.LEARN_COMPAT_MIN
            and pos ~= player.position
            and pos ~= primary
            and not PositionFit.hasNaturalPosition(player, pos)
            and not seen[pos]
        then
            seen[pos] = true
            table.insert(out, pos)
        end
    end

    table.sort(out)
    return out
end

function PositionFit.formatNaturalPositions(player, nameMap)
    if not player then return "" end
    nameMap = nameMap or {}
    local parts = {}
    local seen = {}
    for _, pos in ipairs(player.naturalPositions or { player.position }) do
        local normalized = Constants.normalizePosition(pos)
        if normalized and not seen[normalized] then
            seen[normalized] = true
            local label = nameMap[normalized] or normalized
            if normalized == Constants.normalizePosition(player.position) then
                table.insert(parts, label)
            else
                table.insert(parts, label)
            end
        end
    end
    if #parts == 0 then
        return nameMap[player.position] or player.position
    end
    return table.concat(parts, " · ")
end

return PositionFit
