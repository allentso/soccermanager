-- match/event_flavors.lua
-- 比赛事件风味：伤病种类/严重程度、卡牌原因等结构化子类型
-- 引擎在生成事件时掷出风味字段，UI（match_live / match_result / 消息中心）据此展示

local EventFlavors = {}

------------------------------------------------------
-- 伤病种类（天数区间决定严重程度）
------------------------------------------------------

EventFlavors.INJURY_TYPES = {
    { id = "knock",          name = "轻微撞伤",   minDays = 2,  maxDays = 5,  weight = 22 },
    { id = "muscle_strain",  name = "肌肉拉伤",   minDays = 4,  maxDays = 10, weight = 24 },
    { id = "ankle_sprain",   name = "脚踝扭伤",   minDays = 5,  maxDays = 14, weight = 18 },
    { id = "hamstring",      name = "腿筋拉伤",   minDays = 8,  maxDays = 18, weight = 13 },
    { id = "groin",          name = "腹股沟拉伤", minDays = 7,  maxDays = 16, weight = 8 },
    { id = "back",           name = "背部不适",   minDays = 3,  maxDays = 8,  weight = 4 },
    { id = "concussion",     name = "脑震荡",     minDays = 5,  maxDays = 12, weight = 4 },
    { id = "knee_ligament",  name = "膝韧带损伤", minDays = 18, maxDays = 45, weight = 5 },
    { id = "metatarsal",     name = "跖骨骨折",   minDays = 30, maxDays = 60, weight = 2 },
}

-- 全局硬上限：任何伤病（含赛季报销）不超过约一年
EventFlavors.INJURY_MAX_DAYS = 300
EventFlavors.SEASON_ENDING_MIN_DAYS = 180

-- 赛季报销（ACL/重大手术等）：极低权重，仅比赛/高强度场景单独掷出
EventFlavors.SEASON_ENDING_TYPES = {
    { id = "acl_rupture",    name = "前十字韧带断裂", weight = 45 },
    { id = "major_surgery",  name = "重大手术",       weight = 35 },
    { id = "achilles",       name = "跟腱断裂",       weight = 20 },
}

-- 条件触发赛季报销的基础概率（已发生伤病后的子掷骰，非每场直接掷）
EventFlavors.BASE_SEASON_ENDING_MATCH = 0.012          -- 目标：每场约 0.1%–0.3%
EventFlavors.BASE_SEASON_ENDING_TRAINING_HIGH = 0.009  -- 高强度训练略高（相对训练触发率）

-- 严重程度阈值（按实际天数划分）
EventFlavors.SEVERITY_LEVELS = {
    { id = "minor",    name = "轻伤", maxDays = 7 },
    { id = "moderate", name = "中度", maxDays = 18 },
    { id = "severe",   name = "重伤", maxDays = math.huge },
}

function EventFlavors.severityForDays(days)
    for _, level in ipairs(EventFlavors.SEVERITY_LEVELS) do
        if days <= level.maxDays then
            return level.id, level.name
        end
    end
    return "severe", "重伤"
end

--- 伤病天数硬上限（约一年）
---@param days number
---@return number
function EventFlavors.clampInjuryDays(days)
    days = math.floor(days or 0)
    if days < 1 then return 1 end
    return math.min(EventFlavors.INJURY_MAX_DAYS, days)
end

--- 估算距赛季结束的剩余天数（用于赛季报销时长）
--- 注意：联赛 fixtures 为全联盟场次，不能直接用未打场次×间隔（会膨胀到千天以上）
function EventFlavors.estimateSeasonDaysRemaining(gameState)
    if not gameState or not gameState.league or not gameState.league.fixtures then
        return EventFlavors.SEASON_ENDING_MIN_DAYS
    end

    local teamId = gameState.playerTeamId
    local teamFixturesRemaining = 0
    for _, f in ipairs(gameState.league.fixtures) do
        if f.status ~= "finished" then
            if not teamId or f.homeTeamId == teamId or f.awayTeamId == teamId then
                teamFixturesRemaining = teamFixturesRemaining + 1
            end
        end
    end

    -- 每队场次间隔约 7 天；无 playerTeamId 时按单队 38 场估算
    if teamFixturesRemaining == 0 and not teamId then
        teamFixturesRemaining = 19
    end

    local days = math.floor(teamFixturesRemaining * 7)
    days = math.max(EventFlavors.SEASON_ENDING_MIN_DAYS, days)
    return EventFlavors.clampInjuryDays(days)
end

--- 计算赛季报销子概率（在已触发伤病的前提下），受年龄/体能/injuryRisk/强度影响
---@param player table|nil
---@param opts table|nil { baseChance?, year?, injuryRisk?, intensityMult? }
---@return number
function EventFlavors.computeSeasonEndingChance(player, opts)
    opts = opts or {}
    local base = opts.baseChance or EventFlavors.BASE_SEASON_ENDING_MATCH

    local age = 25
    if player and player.getAge then
        age = player:getAge(opts.year or 2026)
    end

    local ageMult = 1.0
    if age >= 33 then ageMult = 1.35
    elseif age >= 30 then ageMult = 1.20
    elseif age >= 27 then ageMult = 1.08
    elseif age <= 21 then ageMult = 0.85
    end

    local fitness = (player and player.fitness) or 80
    local fitnessMult = 1.0
    if fitness < 55 then fitnessMult = 1.45
    elseif fitness < 70 then fitnessMult = 1.20
    elseif fitness >= 90 then fitnessMult = 0.88
    end

    local riskMult = math.max(0.8, math.min(1.55, opts.injuryRisk or 1.0))
    local intensityMult = opts.intensityMult or 1.0

    local chance = base * ageMult * fitnessMult * riskMult * intensityMult
    return math.max(0.004, math.min(0.035, chance))
end

local function rollSeasonEndingInjury(seasonDaysRemaining)
    local total = 0
    for _, t in ipairs(EventFlavors.SEASON_ENDING_TYPES) do
        total = total + t.weight
    end
    local roll = Random() * total
    local picked = EventFlavors.SEASON_ENDING_TYPES[1]
    local acc = 0
    for _, t in ipairs(EventFlavors.SEASON_ENDING_TYPES) do
        acc = acc + t.weight
        if roll <= acc then picked = t break end
    end
    local days = EventFlavors.clampInjuryDays(
        math.max(EventFlavors.SEASON_ENDING_MIN_DAYS, seasonDaysRemaining or EventFlavors.SEASON_ENDING_MIN_DAYS))
    return {
        kind = picked.id,
        kindName = picked.name,
        days = days,
        severity = "season_ending",
        severityName = "赛季报销",
        isSeasonEnding = true,
    }
end

--- 比赛伤病：可选极低概率赛季报销
---@param opts table|nil { maxDays?, allowSeasonEnding?, seasonDaysRemaining?, seasonEndingChance? }
function EventFlavors.rollMatchInjury(opts)
    opts = opts or {}
    if opts.allowSeasonEnding then
        local chance = opts.seasonEndingChance or 0.002
        if Random() < chance then
            return rollSeasonEndingInjury(opts.seasonDaysRemaining)
        end
    end
    return EventFlavors.rollInjury(opts.maxDays)
end

--- 训练伤病：中低强度仅轻伤；高强度可极低概率赛季报销
---@param gameState table|nil
---@param player table
---@param opts table|nil { intensity?, maxDays?, injuryRisk?, year? }
function EventFlavors.rollTrainingInjury(gameState, player, opts)
    opts = opts or {}
    local intensity = opts.intensity or "medium"
    local maxDays = opts.maxDays or 14

    if intensity ~= "high" then
        return EventFlavors.rollInjury(maxDays)
    end

    local year = opts.year
    if not year and gameState and gameState.date then
        year = gameState.date.year
    end

    local seChance = EventFlavors.computeSeasonEndingChance(player, {
        baseChance = EventFlavors.BASE_SEASON_ENDING_TRAINING_HIGH,
        year = year,
        injuryRisk = opts.injuryRisk or 1.0,
        intensityMult = 1.25,
    })

    return EventFlavors.rollMatchInjury({
        maxDays = maxDays,
        allowSeasonEnding = true,
        seasonDaysRemaining = gameState and EventFlavors.estimateSeasonDaysRemaining(gameState),
        seasonEndingChance = seChance,
    })
end

--- 将伤病写入球员存档字段
function EventFlavors.applyToPlayer(player, injury)
    if not player or not injury then return end
    player.injured = true
    player.injuryDays = EventFlavors.clampInjuryDays(injury.days or 7)
    player.injuryKind = injury.kind
    player.injuryKindName = injury.kindName
    player.injurySeverity = injury.severity
    player.injurySeverityName = injury.severityName
    player.injurySeasonEnding = injury.isSeasonEnding
        or injury.severity == "season_ending"
        or false
end

--- 伤愈时清除伤病字段
function EventFlavors.clearInjury(player)
    if not player then return end
    player.injured = false
    player.injuryDays = 0
    player.injuryKind = nil
    player.injuryKindName = nil
    player.injurySeverity = nil
    player.injurySeverityName = nil
    player.injurySeasonEnding = nil
end

--- 老存档修复：伤病天数超过硬上限时截断（读档/每日幂等）
---@param gameState table
---@return number fixed
function EventFlavors.repairExcessiveInjuryDays(gameState)
    local fixed = 0
    for _, p in pairs(gameState.players or {}) do
        if p.injured and (p.injuryDays or 0) > EventFlavors.INJURY_MAX_DAYS then
            p.injuryDays = EventFlavors.INJURY_MAX_DAYS
            fixed = fixed + 1
        end
    end
    return fixed
end

--- 伤病应用后的统一通知（玩家 inbox + 联赛伤病新闻）
---@param source string|nil "match"|"training"
function EventFlavors.onInjuryApplied(gameState, player, injury, source)
    if not gameState or not player or not injury then return end
    if player.teamId == gameState.playerTeamId then
        EventFlavors.notifyInjuryMessage(gameState, player, injury, source)
    end
    local NewsGenerator = require("scripts/systems/news_generator")
    NewsGenerator.tryInjuryNews(gameState, player, injury.days or player.injuryDays or 0)
end

--- 向玩家发送伤病通知（比赛/训练/随机事件统一入口）
---@param source string|nil "match"|"training"
function EventFlavors.notifyInjuryMessage(gameState, player, injury, source)
    if not gameState or not player or not injury then return end
    if player.teamId ~= gameState.playerTeamId then return end

    local MessageManager = require("scripts/systems/message_manager")
    if injury.isSeasonEnding or injury.severity == "season_ending" then
        MessageManager.send(gameState, "injury_season_ending", {
            player.displayName,
            injury.kindName or "严重伤病",
            injury.days or player.injuryDays or 180,
        })
        return
    end

    local title = (source == "training") and "训练伤病" or "比赛伤病"
    local days = injury.days or player.injuryDays or 7
    local priority = (days >= 14) and "high" or "normal"
    gameState:sendMessage({
        category = "injury",
        title = title,
        body = string.format("%s 受伤（%s · %s），预计 %d 天恢复。",
            player.displayName,
            injury.kindName or "未知",
            injury.severityName or "伤情待定",
            days),
        priority = priority,
    })
end

--- 掷一次伤病：返回 { kind, kindName, days, severity, severityName }
---@param maxDays number|nil 可选天数上限（如训练伤病传 14，排除重伤类型并截断天数）
function EventFlavors.rollInjury(maxDays)
    -- 过滤超出上限的伤病类型（minDays > maxDays 的整类剔除）
    local pool = EventFlavors.INJURY_TYPES
    if maxDays then
        pool = {}
        for _, t in ipairs(EventFlavors.INJURY_TYPES) do
            if t.minDays <= maxDays then table.insert(pool, t) end
        end
        if #pool == 0 then pool = EventFlavors.INJURY_TYPES end
    end

    local total = 0
    for _, t in ipairs(pool) do
        total = total + t.weight
    end
    local roll = Random() * total
    local picked = pool[1]
    local acc = 0
    for _, t in ipairs(pool) do
        acc = acc + t.weight
        if roll <= acc then picked = t break end
    end
    local days = RandomInt(picked.minDays, math.min(picked.maxDays, maxDays or picked.maxDays))
    days = EventFlavors.clampInjuryDays(days)
    local severity, severityName = EventFlavors.severityForDays(days)
    return {
        kind = picked.id,
        kindName = picked.name,
        days = days,
        severity = severity,
        severityName = severityName,
    }
end

------------------------------------------------------
-- 卡牌原因
------------------------------------------------------

EventFlavors.YELLOW_REASONS = {
    { id = "reckless_tackle", name = "鲁莽铲球",     weight = 30 },
    { id = "tactical_foul",   name = "战术犯规",     weight = 24 },
    { id = "shirt_pull",      name = "拉拽对手",     weight = 16 },
    { id = "handball",        name = "故意手球",     weight = 8 },
    { id = "dissent",         name = "抗议判罚",     weight = 12 },
    { id = "time_wasting",    name = "拖延比赛",     weight = 6 },
    { id = "simulation",      name = "假摔",         weight = 4 },
}

EventFlavors.RED_REASONS = {
    { id = "serious_foul",    name = "严重犯规",         weight = 40 },
    { id = "violent_conduct", name = "暴力行为",         weight = 20 },
    { id = "dogso",           name = "破坏明显得分机会", weight = 28 },
    { id = "retaliation",     name = "报复动作",         weight = 12 },
}

local function rollWeighted(list)
    local total = 0
    for _, t in ipairs(list) do total = total + t.weight end
    local roll = Random() * total
    local acc = 0
    for _, t in ipairs(list) do
        acc = acc + t.weight
        if roll <= acc then return t end
    end
    return list[#list]
end

--- 掷卡牌原因：返回 { id, name }
function EventFlavors.rollCardReason(isRed)
    local picked = rollWeighted(isRed and EventFlavors.RED_REASONS or EventFlavors.YELLOW_REASONS)
    return { id = picked.id, name = picked.name }
end

return EventFlavors
