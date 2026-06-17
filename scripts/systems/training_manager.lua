-- systems/training_manager.lua
-- 训练系统：强度影响、职员加成、个人训练、周计划、出场挂钩成长

local Constants = require("scripts/app/constants")
local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local PositionTrainingManager = require("scripts/systems/position_training_manager")

local TrainingManager = {}

local _eventFlavorsModule
local function _getEventFlavors()
    if not _eventFlavorsModule then
        _eventFlavorsModule = require("scripts/match/event_flavors")
    end
    return _eventFlavorsModule
end

------------------------------------------------------
-- 训练重点定义
------------------------------------------------------
TrainingManager.FOCUS_ATTRS = {
    attack = {"shooting", "dribbling", "passing", "vision", "composure"},
    defense = {"tackling", "defending", "positioning", "aerial", "strength"},
    fitness = {"speed", "stamina", "strength", "agility"},
    technical = {"dribbling", "passing", "vision", "composure", "decisions"},
    tactical = {"decisions", "positioning", "teamwork", "vision", "composure"},
    balanced = {"speed", "stamina", "strength", "passing", "shooting",
        "tackling", "dribbling", "defending", "positioning", "vision", "decisions"},
    shooting = {"shooting", "composure", "positioning", "vision"},
    passing = {"passing", "vision", "decisions", "composure"},
    defending = {"tackling", "defending", "positioning", "strength", "aerial"},
    dribbling = {"dribbling", "agility", "composure", "speed"},
}

TrainingManager.WEEKLY_PLAN = {
    intensive = {
        trainDays = {true, true, true, true, true, false, false},
        label = "密集训练",
    },
    balanced = {
        trainDays = {true, false, true, false, true, false, false},
        label = "均衡安排",
    },
    light = {
        trainDays = {false, true, false, true, false, false, false},
        label = "轻量恢复",
    },
}

function TrainingManager._getIntensity(trainingMods)
    local mods = trainingMods or DifficultySettings.getTrainingModifiers()
    return mods.intensity
end

--- 当前赛季用于挂钩判定的年份（赛季初年龄）
function TrainingManager.getSeasonStartYear(gameState)
    return gameState.season or (gameState.date and gameState.date.year) or 2025
end

function TrainingManager.getSeasonAge(player, seasonStartYear)
    return player:getAge(seasonStartYear or 2025)
end

function TrainingManager.getAppsQuotaForSeasonAge(seasonAge)
    if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then return 0 end
    if seasonAge >= Constants.ADULT_TRAINING_APPS_AGE_CAP then
        return Constants.ADULT_TRAINING_APPS_MAX
    end
    return Constants.ADULT_TRAINING_APPS_START
        + (seasonAge - Constants.ADULT_TRAINING_APPS_AGE_FLOOR) * Constants.ADULT_TRAINING_APPS_STEP
end

--- 22+ 球员：俱乐部出场决定训练效率；≤21 恒为 1.0
--- @param trainingMods table|nil 可选，AI 批量训练日缓存
function TrainingManager.getParticipationFactor(player, seasonStartYear, trainingMods)
    local seasonAge = TrainingManager.getSeasonAge(player, seasonStartYear)
    if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then
        return 1.0
    end
    local apps = (player.seasonStats and player.seasonStats.appearances) or 0
    local quota = TrainingManager.getAppsQuotaForSeasonAge(seasonAge)
    if quota <= 0 then return 1.0 end
    local t = apps / quota
    local factor = math.max(Constants.ADULT_TRAINING_APPS_FLOOR, math.min(1.0, t))
    local mods = trainingMods or DifficultySettings.getTrainingModifiers()
    local scale = mods.participationScale or 1.0
    return math.max(Constants.ADULT_TRAINING_APPS_FLOOR, math.min(1.0, factor * scale))
end

--- UI 用：训练效率与出场进度摘要
function TrainingManager.getParticipationSummary(player, gameState)
    local seasonYear = TrainingManager.getSeasonStartYear(gameState)
    local seasonAge = TrainingManager.getSeasonAge(player, seasonYear)
    local apps = (player.seasonStats and player.seasonStats.appearances) or 0

    if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then
        return {
            applies = false,
            seasonAge = seasonAge,
            apps = apps,
            quota = 0,
            factor = 1.0,
            shortLabel = "青年期",
            detailLabel = "训练不受出场限制",
        }
    end

    local quota = TrainingManager.getAppsQuotaForSeasonAge(seasonAge)
    local factor = TrainingManager.getParticipationFactor(player, seasonYear)
    local pct = math.floor(factor * 100 + 0.5)
    return {
        applies = true,
        seasonAge = seasonAge,
        apps = apps,
        quota = quota,
        factor = factor,
        shortLabel = string.format("%d/%d · %d%%", apps, quota, pct),
        detailLabel = string.format("本季俱乐部出场 %d / %d · 训练效率 %d%%", apps, quota, pct),
    }
end

function TrainingManager.isTrainingDay(team, dayOfWeek)
    local weeklyPlan = team.weeklyPlan or "balanced"
    local planConfig = TrainingManager.WEEKLY_PLAN[weeklyPlan] or TrainingManager.WEEKLY_PLAN.balanced
    return planConfig.trainDays[dayOfWeek] == true
end

------------------------------------------------------
-- 每日训练（玩家队 + AI 队共用逻辑）
------------------------------------------------------
function TrainingManager.processDaily(gameState)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end
    local team = gameState.teams[playerTeamId]
    if not team then return end
    TrainingManager._processTeamDaily(gameState, team, { notifyInjury = true })
end

function TrainingManager.processAITeams(gameState)
    local trainingMods = DifficultySettings.getTrainingModifiers()
    local seasonStartYear = TrainingManager.getSeasonStartYear(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId ~= gameState.playerTeamId then
            TrainingManager._processTeamDaily(gameState, team, {
                notifyInjury = false,
                aiFastPath = true,
                trainingMods = trainingMods,
                seasonStartYear = seasonStartYear,
            })
        end
    end
end

function TrainingManager._processTeamDaily(gameState, team, opts)
    opts = opts or {}
    if not TrainingManager.isTrainingDay(team, gameState.dayOfWeek) then
        TrainingManager._restDay(gameState, team)
        return
    end

    local trainingMods = opts.trainingMods or DifficultySettings.getTrainingModifiers()
    local intensity = team.trainingIntensity or "medium"
    local intensityTable = TrainingManager._getIntensity(trainingMods)
    local intensityConfig = intensityTable[intensity] or intensityTable.medium
    local staffBonus = TrainingManager._calcStaffBonus(gameState, team)
    local facilityBonus = FinanceManager.getFacilityBonuses(team).trainingGain

    local legendPositions = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and p.isLegend then
            legendPositions[p.position] = true
        end
    end

    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured then
            TrainingManager._trainPlayer(
                gameState, team, p, intensityConfig,
                staffBonus * facilityBonus, legendPositions, opts)
            if not opts.aiFastPath then
                PositionTrainingManager.processDrillDay(p)
            end
        end
    end
end

------------------------------------------------------
-- 内部：训练单个球员
------------------------------------------------------
function TrainingManager._trainPlayer(gameState, team, player, intensityConfig, staffBonus, legendPositions, opts)
    opts = opts or {}

    local focusKey = player.trainingFocus
    if not opts.aiFastPath and not focusKey and team.trainingGroups then
        for _, group in pairs(team.trainingGroups) do
            if group.playerIds then
                for _, pid in ipairs(group.playerIds) do
                    if pid == player.id then focusKey = group.focus; break end
                end
            end
            if focusKey then break end
        end
    end
    focusKey = focusKey or team.trainingFocus or "balanced"
    local focusAttrs = TrainingManager.FOCUS_ATTRS[focusKey] or TrainingManager.FOCUS_ATTRS.balanced

    local trainingMods = opts.trainingMods or DifficultySettings.getTrainingModifiers()
    local baseChance = trainingMods.baseChance
    baseChance = baseChance * intensityConfig.growthMultiplier
    baseChance = baseChance * staffBonus

    local seasonStartYear = opts.seasonStartYear or TrainingManager.getSeasonStartYear(gameState)
    local age = player:getAge(gameState.date.year)
    local ageFactor = 1.0
    if age <= 21 then ageFactor = 1.4
    elseif age <= 24 then ageFactor = 1.2
    elseif age >= 30 then ageFactor = 0.6
    elseif age >= 33 then ageFactor = 0.3
    end
    baseChance = baseChance * ageFactor

    local potential = player.actualPotential or player.potential or 70
    local overall = player.overall or 50
    local gapDivisor = opts.useYouthGap and trainingMods.youthGapDivisor or trainingMods.gapDivisor
    local gapFloor = opts.useYouthGap and trainingMods.youthGapFloor or trainingMods.gapFloor
    local gapFactor = math.max(gapFloor, (potential - overall) / gapDivisor)
    baseChance = baseChance * gapFactor

    if player.isLegend then
        baseChance = baseChance * 1.5
    end
    if not player.isLegend and legendPositions and legendPositions[player.position] then
        baseChance = baseChance * 1.2
    end

    baseChance = baseChance * (opts.trainingBonusMult or 1.0)
    baseChance = baseChance * TrainingManager.getParticipationFactor(player, seasonStartYear, trainingMods)

    if Random() < baseChance then
        local attrCap = player:getAttrCap()
        local overallCap = player:getOverallCap()
        if (player.overall or 0) < overallCap then
            local maxAttempts = #focusAttrs
            for _ = 1, maxAttempts do
                local attr = focusAttrs[RandomInt(1, #focusAttrs)]
                if player.attributes[attr] and player.attributes[attr] < attrCap then
                    player.attributes[attr] = player.attributes[attr] + 1
                    player:calculateOverall()
                    break
                end
            end
        end
    end

    if opts.skipInjuryAndFitness then
        return
    end

    local fitnessLoss = RandomInt(0, intensityConfig.fitnessLoss)
    player.fitness = DifficultySettings.clampFitness(player.fitness - fitnessLoss)

    if Random() < intensityConfig.injuryChance then
        local extraChance = player.fitness < 60 and 0.02 or 0
        if Random() < (0.5 + extraChance) then
            local EventFlavors = _getEventFlavors()
            local intensity = opts.intensity or team.trainingIntensity or "medium"
            local injury = EventFlavors.rollTrainingInjury(gameState, player, {
                intensity = intensity,
                maxDays = 14,
                injuryRisk = opts.injuryRisk or 1.0,
            })
            EventFlavors.applyToPlayer(player, injury)
            if opts.notifyInjury then
                EventFlavors.onInjuryApplied(gameState, player, injury, "training")
            end
        end
    end
end

function TrainingManager._restDay(gameState, team)
    local intensity = team.trainingIntensity or "medium"
    local intensityConfig = TrainingManager._getIntensity()[intensity]
        or TrainingManager._getIntensity().medium

    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured then
            local recovery = 2 + intensityConfig.fitnessRecoveryBonus
            p.fitness = math.min(100, p.fitness + math.max(1, recovery))
        end
    end
end

function TrainingManager._calcStaffBonus(gameState, team)
    local bonus = 0.85
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then
            if s.role == "coach" then
                local coaching = s.attributes and s.attributes.coaching or 10
                bonus = bonus + coaching * 0.025
            elseif s.role == "assistant" then
                local coaching = s.attributes and s.attributes.coaching or 8
                bonus = bonus + coaching * 0.015
            end
        end
    end
    return math.min(1.35, bonus)
end

function TrainingManager.setTeamFocus(gameState, focus)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager.FOCUS_ATTRS[focus] then return false end
    team.trainingFocus = focus
    return true
end

function TrainingManager.setIntensity(gameState, intensity)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager._getIntensity()[intensity] then return false end
    team.trainingIntensity = intensity
    return true
end

function TrainingManager.setWeeklyPlan(gameState, plan)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager.WEEKLY_PLAN[plan] then return false end
    team.weeklyPlan = plan
    return true
end

function TrainingManager.setPlayerFocus(gameState, playerId, focus)
    local player = gameState.players[playerId]
    if not player then return false end
    if focus and not TrainingManager.FOCUS_ATTRS[focus] then return false end
    player.trainingFocus = focus
    return true
end

return TrainingManager
