-- systems/training_manager.lua
-- 训练系统：强度影响、职员加成、个人训练、周计划

local Constants = require("scripts/app/constants")
local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")

local TrainingManager = {}

------------------------------------------------------
-- 训练重点定义
------------------------------------------------------
TrainingManager.FOCUS_ATTRS = {
    -- Team-level focus categories
    attack = {"shooting", "dribbling", "passing", "vision", "composure"},
    defense = {"tackling", "defending", "positioning", "aerial", "strength"},
    fitness = {"speed", "stamina", "strength", "agility"},
    technical = {"dribbling", "passing", "vision", "composure", "decisions"},
    tactical = {"decisions", "positioning", "teamwork", "vision", "composure"},
    balanced = {"speed", "stamina", "strength", "passing", "shooting",
        "tackling", "dribbling", "defending", "positioning", "vision", "decisions"},
    -- Individual-specific focus (for player.trainingFocus)
    shooting = {"shooting", "composure", "positioning", "vision"},
    passing = {"passing", "vision", "decisions", "composure"},
    defending = {"tackling", "defending", "positioning", "strength", "aerial"},
    dribbling = {"dribbling", "agility", "composure", "speed"},
}

------------------------------------------------------
-- 强度配置
------------------------------------------------------
TrainingManager.INTENSITY = {
    low = {
        growthMultiplier = 0.5,     -- 属性增长慢
        fitnessLoss = 1,            -- 体能消耗少
        injuryChance = 0.003,       -- 受伤概率低
        fitnessRecoveryBonus = 2,   -- 额外体能恢复
    },
    medium = {
        growthMultiplier = 1.0,
        fitnessLoss = 2,
        injuryChance = 0.01,
        fitnessRecoveryBonus = 0,
    },
    high = {
        growthMultiplier = 1.8,
        fitnessLoss = 3,
        injuryChance = 0.025,
        fitnessRecoveryBonus = -1,  -- 恢复更慢
    },
}

------------------------------------------------------
-- 周计划配置
------------------------------------------------------
TrainingManager.WEEKLY_PLAN = {
    intensive = {  -- 周一~周五全训，周末轻松
        trainDays = {true, true, true, true, true, false, false},
        label = "密集训练",
    },
    balanced = {   -- 周一三五训练，二四恢复
        trainDays = {true, false, true, false, true, false, false},
        label = "均衡安排",
    },
    light = {      -- 周二四训练
        trainDays = {false, true, false, true, false, false, false},
        label = "轻量恢复",
    },
}

------------------------------------------------------
-- 每日训练处理（由 turn_processor 调用）
------------------------------------------------------
function TrainingManager.processDaily(gameState)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    local team = gameState.teams[playerTeamId]
    if not team then return end

    -- 检查今天是否是训练日（根据周计划）
    local weeklyPlan = team.weeklyPlan or "balanced"
    local planConfig = TrainingManager.WEEKLY_PLAN[weeklyPlan] or TrainingManager.WEEKLY_PLAN.balanced
    local dayOfWeek = gameState.dayOfWeek  -- 1=周一

    if not planConfig.trainDays[dayOfWeek] then
        -- 非训练日：额外体能恢复
        TrainingManager._restDay(gameState, team)
        return
    end

    -- 训练日处理
    local intensity = team.trainingIntensity or "medium"
    local intensityConfig = TrainingManager.INTENSITY[intensity] or TrainingManager.INTENSITY.medium

    -- 计算职员加成
    local staffBonus = TrainingManager._calcStaffBonus(gameState, team)
    local facilityBonus = FinanceManager.getFacilityBonuses(team).trainingGain

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.injured then
            TrainingManager._trainPlayer(gameState, team, p, intensityConfig, staffBonus * facilityBonus)
        end
    end
end

------------------------------------------------------
-- AI 球队简化训练（由 turn_processor 调用）
------------------------------------------------------
function TrainingManager.processAITeams(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId ~= gameState.playerTeamId then
            -- AI 球队使用简化训练逻辑
            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p and not p.injured then
                    -- 简单概率增长
                    if Random() < 0.03 then
                        local attrs = TrainingManager.FOCUS_ATTRS.balanced
                        local attr = attrs[RandomInt(1, #attrs)]
                        if p.attributes[attr] and p.attributes[attr] < 20 then
                            p.attributes[attr] = p.attributes[attr] + 1
                            p:calculateOverall()
                        end
                    end
                    -- 体能消耗
                    p.fitness = math.max(50, p.fitness - RandomInt(0, 2))
                end
            end
        end
    end
end

------------------------------------------------------
-- 内部：训练单个球员
------------------------------------------------------
function TrainingManager._trainPlayer(gameState, team, player, intensityConfig, staffBonus)
    -- 确定训练属性（优先级：个人focus > 分组focus > 全队focus）
    local focusKey = player.trainingFocus
    if not focusKey and team.trainingGroups then
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

    -- 基础增长概率
    local baseChance = 0.06

    -- 强度修正
    baseChance = baseChance * intensityConfig.growthMultiplier

    -- 职员加成（0.85 ~ 1.35）
    baseChance = baseChance * staffBonus

    -- 年龄修正（年轻球员成长快，老球员慢）
    local age = (player.birthYear and (gameState.date.year - player.birthYear)) or 25
    local ageFactor = 1.0
    if age <= 21 then ageFactor = 1.4
    elseif age <= 24 then ageFactor = 1.2
    elseif age >= 30 then ageFactor = 0.6
    elseif age >= 33 then ageFactor = 0.3
    end
    baseChance = baseChance * ageFactor

    -- 潜力修正（距离潜力越远成长越容易，使用局内实际潜力）
    local potential = player.actualPotential or player.potential or 70
    local overall = player.overall or 50
    local gapFactor = math.max(0.2, (potential - overall) / 30)
    baseChance = baseChance * gapFactor

    -- 尝试属性增长
    if Random() < baseChance then
        local attr = focusAttrs[RandomInt(1, #focusAttrs)]
        if player.attributes[attr] and player.attributes[attr] < 20 then
            player.attributes[attr] = player.attributes[attr] + 1
            player:calculateOverall()
        end
    end

    -- 体能消耗
    local fitnessLoss = RandomInt(0, intensityConfig.fitnessLoss)
    player.fitness = math.max(40, player.fitness - fitnessLoss)

    -- 训练伤病
    if Random() < intensityConfig.injuryChance then
        -- 低体能增加受伤概率
        local extraChance = player.fitness < 60 and 0.02 or 0
        if Random() < (0.5 + extraChance) then
            player.injured = true
            player.injuryDays = RandomInt(3, 14)
            if player.teamId == gameState.playerTeamId then
                gameState:sendMessage({
                    category = "injury",
                    title = "训练伤病",
                    body = string.format("%s 在训练中受伤，预计 %d 天恢复。",
                        player.displayName, player.injuryDays),
                    priority = "high",
                })
            end
        end
    end
end

------------------------------------------------------
-- 内部：休息日
------------------------------------------------------
function TrainingManager._restDay(gameState, team)
    local intensity = team.trainingIntensity or "medium"
    local intensityConfig = TrainingManager.INTENSITY[intensity] or TrainingManager.INTENSITY.medium

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.injured then
            -- 额外恢复
            local recovery = 2 + intensityConfig.fitnessRecoveryBonus
            p.fitness = math.min(100, p.fitness + math.max(1, recovery))
        end
    end
end

------------------------------------------------------
-- 内部：计算职员加成
------------------------------------------------------
function TrainingManager._calcStaffBonus(gameState, team)
    local bonus = 0.85  -- 无职员时基础值

    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then
            if s.role == "coach" then
                -- 教练属性影响训练质量
                local coaching = s.attributes and s.attributes.coaching or 10
                bonus = bonus + coaching * 0.025  -- 每点教练属性 +2.5%
            elseif s.role == "assistant" then
                -- 助理教练有少量加成
                local coaching = s.attributes and s.attributes.coaching or 8
                bonus = bonus + coaching * 0.015
            end
        end
    end

    -- 上限 1.35
    return math.min(1.35, bonus)
end

------------------------------------------------------
-- 设置训练重点（UI 调用）
------------------------------------------------------
function TrainingManager.setTeamFocus(gameState, focus)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager.FOCUS_ATTRS[focus] then return false end
    team.trainingFocus = focus
    return true
end

-- 设置训练强度（UI 调用）
function TrainingManager.setIntensity(gameState, intensity)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager.INTENSITY[intensity] then return false end
    team.trainingIntensity = intensity
    return true
end

-- 设置周计划（UI 调用）
function TrainingManager.setWeeklyPlan(gameState, plan)
    local team = gameState:getPlayerTeam()
    if not team then return false end
    if not TrainingManager.WEEKLY_PLAN[plan] then return false end
    team.weeklyPlan = plan
    return true
end

-- 设置球员个人训练（UI 调用）
function TrainingManager.setPlayerFocus(gameState, playerId, focus)
    local player = gameState.players[playerId]
    if not player then return false end
    if focus and not TrainingManager.FOCUS_ATTRS[focus] then return false end
    player.trainingFocus = focus  -- nil = 跟随团队
    return true
end

return TrainingManager
