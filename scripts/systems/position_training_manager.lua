-- systems/position_training_manager.lua
-- 第二位置训练：实战 +5%/场，纯训练 +1%/日（封顶 30%）

local PositionFit = require("scripts/domain/position_fit")
local FormationShape = require("scripts/match/formation_shape")

local PositionTrainingManager = {}

PositionTrainingManager.MATCH_PROGRESS = 5
PositionTrainingManager.DRILL_PROGRESS = 1
PositionTrainingManager.DRILL_CAP = 30
PositionTrainingManager.TOTAL_CAP = 100

local function clampProgress(v)
    return math.max(0, math.min(PositionTrainingManager.TOTAL_CAP, v or 0))
end

function PositionTrainingManager.buildPlayerSlotPosMap(team, lineupBySlot)
    local map = {}
    if not team or not lineupBySlot then return map end
    local slots = FormationShape.getFormationSlots(team)
    for slotIdx, pid in pairs(lineupBySlot) do
        if pid and slots[slotIdx] then
            map[pid] = slots[slotIdx]
        end
    end
    return map
end

function PositionTrainingManager.getSlotMapForTeam(team)
    local bySlot = {}
    local startingXI = team.startingXI or {}
    for i = 1, 11 do
        bySlot[i] = startingXI[i]
    end
    return PositionTrainingManager.buildPlayerSlotPosMap(team, bySlot)
end

function PositionTrainingManager.addProgress(player, amount)
    if not player or not player.positionTrainingTarget or amount <= 0 then
        return false
    end
    local before = player.positionTrainingProgress or 0
    player.positionTrainingProgress = clampProgress(before + amount)
    return player.positionTrainingProgress > before
end

function PositionTrainingManager.completeIfReady(player)
    if not player or not player.positionTrainingTarget then return false end
    if (player.positionTrainingProgress or 0) < PositionTrainingManager.TOTAL_CAP then
        return false
    end

    local target = player.positionTrainingTarget
    player.naturalPositions = player.naturalPositions or { player.position }
    local exists = false
    for _, pos in ipairs(player.naturalPositions) do
        if pos == target then exists = true; break end
    end
    if not exists then
        table.insert(player.naturalPositions, target)
    end

    player.positionTrainingTarget = nil
    player.positionTrainingProgress = 0
    player.positionTrainingDrillProgress = 0
    return true
end

function PositionTrainingManager.processDrillDay(player)
    if not player or player.injured then return false end
    local target = player.positionTrainingTarget
    if not target then return false end

    local drill = player.positionTrainingDrillProgress or 0
    if drill >= PositionTrainingManager.DRILL_CAP then
        return false
    end

    local add = math.min(
        PositionTrainingManager.DRILL_PROGRESS,
        PositionTrainingManager.DRILL_CAP - drill
    )
    player.positionTrainingDrillProgress = drill + add
    PositionTrainingManager.addProgress(player, add)
    PositionTrainingManager.completeIfReady(player)
    return true
end

function PositionTrainingManager.processMatchAppearance(player, slotPos)
    if not player or not slotPos then return false end
    local target = player.positionTrainingTarget
    if not target or slotPos ~= target then return false end

    PositionTrainingManager.addProgress(player, PositionTrainingManager.MATCH_PROGRESS)
    return PositionTrainingManager.completeIfReady(player)
end

function PositionTrainingManager.applyPostMatch(gameState, fixture, report)
    if not gameState or not fixture or not report then return end

    local slotMaps = report.playerSlotPos or {}
    local teams = {
        { teamId = fixture.homeTeamId, side = "home" },
        { teamId = fixture.awayTeamId, side = "away" },
    }

    for _, entry in ipairs(teams) do
        local team = gameState.teams[entry.teamId]
        local sideMap = slotMaps[entry.side]
        if not sideMap and team then
            sideMap = PositionTrainingManager.getSlotMapForTeam(team)
        end
        if not sideMap then goto nextTeam end

        local idSet = report.appearanceIds and report.appearanceIds[entry.side]
        if idSet then
            for pid, _ in pairs(idSet) do
                local p = gameState.players[pid]
                local slotPos = sideMap[pid]
                if p and slotPos then
                    PositionTrainingManager.processMatchAppearance(p, slotPos)
                end
            end
        else
            for pid, slotPos in pairs(sideMap) do
                local p = gameState.players[pid]
                if p then
                    PositionTrainingManager.processMatchAppearance(p, slotPos)
                end
            end
        end
        ::nextTeam::
    end
end

function PositionTrainingManager.setTarget(player, slotPos)
    if not player then return false, "球员不存在" end
    if player.positionTrainingTarget then
        return false, "已在学习其他位置"
    end
    if not PositionFit.canLearnPosition(player, slotPos) then
        return false, "无法学习该位置"
    end
    player.positionTrainingTarget = slotPos
    player.positionTrainingProgress = 0
    player.positionTrainingDrillProgress = 0
    return true
end

function PositionTrainingManager.clearTarget(player)
    if not player or not player.positionTrainingTarget then return false end
    player.positionTrainingTarget = nil
    player.positionTrainingProgress = 0
    player.positionTrainingDrillProgress = 0
    return true
end

return PositionTrainingManager
