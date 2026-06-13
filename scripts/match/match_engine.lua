-- match/match_engine.lua
-- Minute-based match simulation with session-based stepwise API.
-- Supports both one-shot simulate() (for AI matches) and stepwise session API (for player matches).

local TacticsResolver = require("scripts/match/tactics_resolver")
local MatchReport = require("scripts/match/match_report")
local PlaceholderEngine = require("scripts/match/placeholder_engine")
local MatchSession = require("scripts/match/match_session")
local TraitEffects = require("scripts/match/trait_effects")
local SetPieceResolver = require("scripts/match/set_piece_resolver")
local EventFlavors = require("scripts/match/event_flavors")

local MatchEngine = {}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function attr(player, key, fallback)
    local attributes = player and player.attributes or {}
    return attributes[key] or fallback or 10
end

local function poisson(lambda)
    if lambda <= 0 then return 0 end
    local limit = math.exp(-lambda)
    local k = 0
    local p = 1
    repeat
        k = k + 1
        p = p * Random()
    until p <= limit
    return k - 1
end

local function positionGroup(position)
    if position == "GK" then return "GK" end
    if position == "CB" or position == "LB" or position == "RB" then return "DEF" end
    if position == "ST" or position == "CF" or position == "LW" or position == "RW" then return "FWD" end
    return "MID"
end

local function pickShooter(context, opts)
    opts = opts or {}
    return TacticsResolver.chooseWeighted(context.players, function(player)
        local group = positionGroup(player.position)
        local weight = attr(player, "shooting") * 1.0 + attr(player, "positioning") * 0.6 + attr(player, "composure") * 0.4
        if group == "FWD" then weight = weight * 3.0
        elseif player.position == "CAM" then weight = weight * 2.0
        elseif group == "MID" then weight = weight * 0.9
        elseif group == "DEF" then weight = weight * 0.2 + attr(player, "aerial") * 0.25
        else weight = 0.05 end
        return TraitEffects.modifyShooterWeight(player, group, weight, opts)
    end)
end

local function pickAssister(context, scorer)
    if Random() > 0.68 then return nil end
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if scorer and player.id == scorer.id then return 0 end
        local group = positionGroup(player.position)
        local weight = attr(player, "passing") * 0.9 + attr(player, "vision") * 0.8 + attr(player, "decisions") * 0.45
        if player.position == "CAM" then weight = weight * 1.8
        elseif group == "MID" then weight = weight * 1.35
        elseif player.position == "LW" or player.position == "RW" then weight = weight * 1.25
        elseif player.position == "LB" or player.position == "RB" then weight = weight * 0.9
        elseif group == "FWD" then weight = weight * 0.7
        else weight = weight * 0.35 end
        return TraitEffects.modifyAssisterWeight(player, group, weight)
    end)
end

local function pickCardPlayer(context)
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if player.position == "GK" then return 0.1 end
        local weight = attr(player, "aggression") * 0.8 + (21 - attr(player, "decisions")) * 0.35
        return TraitEffects.modifyCardWeight(player, weight)
    end)
end

-- 风格对各位置组的受伤风险权重
local STYLE_INJURY_POSITION_WEIGHT = {
    HighPress  = { MID = 1.30, DEF = 1.10, FWD = 1.05 },
    Counter    = { DEF = 1.15, FWD = 1.08 },
    Attacking  = { DEF = 1.10, FWD = 1.05 },
    Defensive  = { MID = 0.90, FWD = 0.90 },
    Possession = { MID = 0.92, DEF = 0.92 },
}

local function pickInjuryPlayer(context)
    local styleWeights = STYLE_INJURY_POSITION_WEIGHT[context.style] or {}
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if player.position == "GK" then return 0.15 end
        local group = positionGroup(player.position)
        local lowFitness = 105 - (player.fitness or 80)
        local base = math.max(1, lowFitness) + (21 - attr(player, "stamina")) * 1.3
        -- 风格×位置额外权重
        local posWeight = styleWeights[group] or 1.0
        return base * posWeight
    end)
end

function MatchEngine._simulateMinutes(fixture, homeContext, awayContext, startMinute, endMinute, state, options)
    options = options or {}
    local events = state.events

    -- 单场"今日状态"采样（±18%）：整场固定，存入 state 以兼容分段模拟（session）
    -- 注意不能逐分钟重掷，否则 90 次平均后波动退化为 ±2%，丢失单场状态语义
    if not state._homeFormFactor then
        state._homeFormFactor = TraitEffects.sampleFormFactor(homeContext.traitSummary)
        state._awayFormFactor = TraitEffects.sampleFormFactor(awayContext.traitSummary)
    end

    -- 弱侧大比分护栏：明显弱旅（OVR差>=12）领先2球后，后续进球概率指数递减
    -- 消灭"70队 5:0 打爆 90队"，不限制强队打弱队的大比分
    local function weakSideGoalDampen(forHome)
        local myCtx = forHome and homeContext or awayContext
        local oppCtx = forHome and awayContext or homeContext
        local gap = (oppCtx.avgPlayerOverall or 70) - (myCtx.avgPlayerOverall or 70)
        if gap < 12 then return 1.0 end
        local lead = forHome and (state.homeGoals - state.awayGoals) or (state.awayGoals - state.homeGoals)
        if lead < 2 then return 1.0 end
        return 0.6 ^ (lead - 1)
    end

    -- 动量系统：连续进攻增加机会（模拟真实足球进球扎堆）
    local homeMomentum = state._homeMomentum or 0
    local awayMomentum = state._awayMomentum or 0

    -- 体力衰减系统：基于比赛进行时间 + 风格消耗 + 球员平均耐力
    -- fatigueFactor 会降低攻防输出 (1.0 → ~0.88 在90分钟末尾)
    local homeStaminaDrain = homeContext.staminaDrain or 1.0
    local awayStaminaDrain = awayContext.staminaDrain or 1.0
    local homeAvgStamina = homeContext.avgStamina or 12
    local awayAvgStamina = awayContext.avgStamina or 12

    for minute = startMinute, endMinute do
        -- 体力衰减：前45分钟几乎无影响，后45分钟线性加剧
        -- staminaDrain越高衰减越快，avgStamina越高衰减越慢
        -- 公式: baseFatigue起始于第30分钟后生效, 90分钟时≈0.12
        local elapsed = minute
        local baseFatigue = clamp((elapsed - 30) / 500, 0, 0.12)
        -- staminaDrain放大: HighPress(1.22)→fatigue×1.22; Possession(0.88)→fatigue×0.88
        -- avgStamina抵消: 高耐力阵容衰减更慢 (stamina=15→×0.82, stamina=10→×1.0, stamina=6→×1.16)
        local staminaResist = 1.0 - (homeAvgStamina - 10) * 0.045
        local homeFatigue = clamp(1.0 - baseFatigue * homeStaminaDrain * staminaResist, 0.85, 1.0)
        staminaResist = 1.0 - (awayAvgStamina - 10) * 0.045
        local awayFatigue = clamp(1.0 - baseFatigue * awayStaminaDrain * staminaResist, 0.85, 1.0)

        local homeMod = TacticsResolver.matchupModifiers(homeContext, awayContext, true, state._homeFormFactor)
        local awayMod = TacticsResolver.matchupModifiers(awayContext, homeContext, false, state._awayFormFactor)

        -- 将疲劳应用到进攻创造力和射门质量（不影响防守太多，防守靠站位）
        homeMod.chanceCreation = homeMod.chanceCreation * homeFatigue
        homeMod.shotQuality = homeMod.shotQuality * homeFatigue
        awayMod.chanceCreation = awayMod.chanceCreation * awayFatigue
        awayMod.shotQuality = awayMod.shotQuality * awayFatigue

        local avgTempo = (homeMod.tempo + awayMod.tempo) / 2
        local homePossessionChance = homeMod.possessionShare
        local attackingHome = Random() < homePossessionChance
        local attackContext = attackingHome and homeContext or awayContext
        local defendContext = attackingHome and awayContext or homeContext
        local attackMod = attackingHome and homeMod or awayMod
        local attackingTeamId = attackingHome and fixture.homeTeamId or fixture.awayTeamId

        -- 动量衰减 + 累积
        if attackingHome then
            homeMomentum = math.min(0.12, homeMomentum + 0.015)
            awayMomentum = math.max(0, awayMomentum - 0.02)
        else
            awayMomentum = math.min(0.12, awayMomentum + 0.015)
            homeMomentum = math.max(0, homeMomentum - 0.02)
        end
        local momentum = attackingHome and homeMomentum or awayMomentum

        -- 定位球机会通道（FM 风格三阶段：机会 → 发球质量 → 终结检定）
        -- 类型: 角球52% / 任意球33% / 点球9% / 乌龙6%
        -- 机会率 0.012/分钟/队，经过滤链后进球期望 ≈ 0.30/队/场（蒙特卡洛校准）
        local setPieceOpportunity = 0.012
        for _, side in ipairs({{true, homeContext, fixture.homeTeamId}, {false, awayContext, fixture.awayTeamId}}) do
            local spIsHome, spContext, spTeamId = side[1], side[2], side[3]
            local spOppCtx = spIsHome and awayContext or homeContext
            local spGap = (spContext.avgPlayerOverall or 70) - (spOppCtx.avgPlayerOverall or 70)
            local spScale = clamp(1.0 + spGap * 0.025, 0.60, 1.25)
            local spTraitMult = (spContext.traitSummary and spContext.traitSummary.setPieceMult) or 1.0
            if Random() < setPieceOpportunity * spScale * spTraitMult then
                local addShot = function(onTarget, goal)
                    if spIsHome then
                        state.homeShots = state.homeShots + 1
                        if onTarget then state.homeShotsOnTarget = state.homeShotsOnTarget + 1 end
                        if goal then state.homeGoals = state.homeGoals + 1 end
                    else
                        state.awayShots = state.awayShots + 1
                        if onTarget then state.awayShotsOnTarget = state.awayShotsOnTarget + 1 end
                        if goal then state.awayGoals = state.awayGoals + 1 end
                    end
                end

                local spTypeRoll = Random()
                if spTypeRoll < 0.06 then
                    -- 乌龙球：防守方失误，免后续检定（但受弱旅护栏约束）
                    if Random() < weakSideGoalDampen(spIsHome) then
                        local scorer = pickShooter(spOppCtx)
                        addShot(true, true)
                        table.insert(events, {
                            type = "goal",
                            minute = minute,
                            playerId = scorer and scorer.id,
                            teamId = spTeamId,
                            isOwnGoal = true,
                            isSetPiece = true,
                            setPieceKind = "own_goal",
                            isExtraTime = minute > 90 or nil,
                            templateIdx = RandomInt(1, 100),
                        })
                        if spIsHome then homeMomentum = 0 else awayMomentum = 0 end
                    end
                elseif spTypeRoll < 0.15 then
                    -- 场内点球：指定主罚人 + 统一点球模型
                    local taker = SetPieceResolver.resolveTaker(spContext, "penalty")
                    local keeper = nil
                    for _, p in ipairs(spOppCtx.players or {}) do
                        if p.position == "GK" then keeper = p break end
                    end
                    local chance = SetPieceResolver.penaltyChance(taker, keeper)
                        * weakSideGoalDampen(spIsHome)
                    if Random() < chance then
                        addShot(true, true)
                        table.insert(events, {
                            type = "goal",
                            minute = minute,
                            playerId = taker and taker.id,
                            teamId = spTeamId,
                            isPenalty = true,
                            isSetPiece = true,
                            setPieceKind = "penalty",
                            isExtraTime = minute > 90 or nil,
                            templateIdx = RandomInt(1, 100),
                        })
                        if spIsHome then homeMomentum = 0 else awayMomentum = 0 end
                    else
                        -- 点球未进：60% 门将扑出，40% 射失（射偏/中框不区分）
                        if Random() < 0.60 then
                            addShot(true, false)
                            table.insert(events, {
                                type = "save",
                                minute = minute,
                                playerId = taker and taker.id,
                                teamId = spTeamId,
                                isSetPiece = true,
                                isPenalty = true,
                                templateIdx = RandomInt(1, 100),
                            })
                        else
                            addShot(false, false)
                            table.insert(events, {
                                type = "shot_off_target",
                                minute = minute,
                                playerId = taker and taker.id,
                                teamId = spTeamId,
                                isPenalty = true,
                                isSetPiece = true,
                                templateIdx = RandomInt(1, 100),
                            })
                        end
                    end
                else
                    -- 角球(52%) / 任意球(33%)
                    local spKind = spTypeRoll < 0.67 and "corner" or "free_kick"
                    local taker = SetPieceResolver.resolveTaker(spContext, spKind)

                    -- 阶段1: 发球质量（主罚合成能力 → 通过率 0.35~0.80）
                    local takerSkill = SetPieceResolver.synthSkill(taker, spKind)
                    local delivery = clamp(0.30 + takerSkill / 40, 0.35, 0.80)
                    if Random() >= delivery then
                        -- 发球失败：一半静默，一半生成射偏解说
                        if Random() < 0.50 then
                            addShot(false, false)
                            table.insert(events, {
                                type = "shot_off_target",
                                minute = minute,
                                playerId = taker and taker.id,
                                teamId = spTeamId,
                                isSetPiece = true,
                                templateIdx = RandomInt(1, 100),
                            })
                        end
                    else
                        -- 阶段2: 终结者（任意球 45% 主罚直接射门，其余争顶头球链）
                        local finisher, finishScore
                        if spKind == "free_kick" and Random() < 0.45 then
                            finisher = taker
                            finishScore = attr(finisher, "shooting") * 0.60
                                + attr(finisher, "composure") * 0.40
                        else
                            finisher = SetPieceResolver.pickAerialFinisher(spContext) or taker
                            finishScore = attr(finisher, "aerial") * 0.55
                                + attr(finisher, "strength") * 0.25
                                + attr(finisher, "positioning") * 0.20
                        end

                        -- 阶段3: 进球检定（攻防量纲同为 1-20，直接相减）
                        local aerialDef = SetPieceResolver.aerialDefense(spOppCtx)
                        local edge = (finishScore - aerialDef) / 20
                        local goalChance = clamp(
                            0.24 + edge * 0.35 + (delivery - 0.55) * 0.30,
                            0.08, 0.45)
                        local finisherGroup = positionGroup(finisher and finisher.position or "ST")
                        local saveBonus = (spOppCtx.traitSummary and spOppCtx.traitSummary.saveBonus) or 0
                        goalChance = TraitEffects.modifyGoalChance(finisher, finisherGroup, goalChance, {
                            isSetPiece = true,
                            defenderSaveBonus = saveBonus,
                        })
                        goalChance = goalChance * weakSideGoalDampen(spIsHome)

                        if Random() < goalChance then
                            addShot(true, true)
                            table.insert(events, {
                                type = "goal",
                                minute = minute,
                                playerId = finisher and finisher.id,
                                assistPlayerId = (taker and finisher and taker.id ~= finisher.id)
                                    and taker.id or nil,
                                teamId = spTeamId,
                                isSetPiece = true,
                                setPieceKind = spKind,
                                takerId = taker and taker.id,
                                isExtraTime = minute > 90 or nil,
                                templateIdx = RandomInt(1, 100),
                            })
                            if spIsHome then homeMomentum = 0 else awayMomentum = 0 end
                        else
                            -- 未进：65% 扑救 / 35% 中框（与运动战一致）
                            addShot(true, false)
                            local saveType = Random() < 0.65 and "save" or "hit_post"
                            table.insert(events, {
                                type = saveType,
                                minute = minute,
                                playerId = finisher and finisher.id,
                                teamId = spTeamId,
                                isSetPiece = true,
                                templateIdx = RandomInt(1, 100),
                            })
                        end
                    end
                end
            end
        end

        -- Phase 概率：基础值 + 进攻力加成 + 动量
        local basePhaseChance = options.phaseChance or 0.42
        local attackBoost = clamp((attackMod.chanceCreation - 1.0) * 0.10, -0.05, 0.04)
        local phaseChance = clamp(basePhaseChance + attackBoost + momentum, 0.33, 0.52)

        if Random() < phaseChance * avgTempo then
            local shotChance = clamp(0.28 + attackMod.chanceCreation * 0.16, 0.22, 0.50)
            if Random() < shotChance then
                local isHome = attackingHome
                if isHome then state.homeShots = state.homeShots + 1 else state.awayShots = state.awayShots + 1 end

                local shooter = pickShooter(attackContext)
                local shooterGroup = positionGroup(shooter and shooter.position or "CM")
                local finishing = (attr(shooter, "shooting") * 1.0 + attr(shooter, "composure") * 0.8 + attr(shooter, "positioning") * 0.4) / 20
                -- 防守压力（量纲归一后同实力≈1.0；归一前同实力恒撞 1.40 上限）
                local defensePressure = clamp(
                    defendContext.defense / TacticsResolver.DEF_TO_ATK_SCALE / math.max(1, attackContext.attack),
                    0.60, 1.40)
                local onTargetChance = clamp(0.38 + finishing * 0.12 - defensePressure * 0.05, 0.28, 0.56)
                onTargetChance = TraitEffects.modifyOnTargetChance(shooter, shooterGroup, onTargetChance)
                if Random() < onTargetChance then
                    if isHome then state.homeShotsOnTarget = state.homeShotsOnTarget + 1 else state.awayShotsOnTarget = state.awayShotsOnTarget + 1 end

                    -- 进球概率：下限降至0.08，弱队面对强防线转化率更低
                    local goalChance = clamp(0.20 + finishing * 0.08 * attackMod.shotQuality - defensePressure * 0.05, 0.08, 0.34)
                    local saveBonus = (defendContext.traitSummary and defendContext.traitSummary.saveBonus) or 0
                    goalChance = TraitEffects.modifyGoalChance(shooter, shooterGroup, goalChance, {
                        defenderSaveBonus = saveBonus,
                    })
                    goalChance = goalChance * weakSideGoalDampen(isHome)
                    if Random() < goalChance then
                        local assister = pickAssister(attackContext, shooter)
                        table.insert(events, {
                            type = "goal",
                            minute = minute,
                            playerId = shooter and shooter.id,
                            assistPlayerId = assister and assister.id,
                            teamId = attackingTeamId,
                            isExtraTime = minute > 90 or nil,
                            templateIdx = RandomInt(1, 100),
                        })
                        if isHome then state.homeGoals = state.homeGoals + 1 else state.awayGoals = state.awayGoals + 1 end
                        -- 进球后重置动量（对手可能反扑）
                        if isHome then homeMomentum = 0 else awayMomentum = 0 end
                    else
                        -- 射正但未进球 → 精彩扑救或击中门框
                        local saveType = Random() < 0.65 and "save" or "hit_post"
                        table.insert(events, {
                            type = saveType,
                            minute = minute,
                            playerId = shooter and shooter.id,
                            teamId = attackingTeamId,
                            templateIdx = RandomInt(1, 100),
                        })
                    end
                else
                    -- 射门未射正 → 射偏/高出横梁（约40%产生解说事件）
                    if Random() < 0.40 then
                        table.insert(events, {
                            type = "shot_off_target",
                            minute = minute,
                            playerId = shooter and shooter.id,
                            teamId = attackingTeamId,
                            templateIdx = RandomInt(1, 100),
                        })
                    end
                end
            end
        end

        local foulBase = 0.055
        local foulSideHome = Random() < 0.5
        local foulContext = foulSideHome and homeContext or awayContext
        local foulMod = foulSideHome and homeMod or awayMod
        if Random() < foulBase * foulMod.foulRate then
            if foulSideHome then state.homeFouls = state.homeFouls + 1 else state.awayFouls = state.awayFouls + 1 end
            local cardRoll = Random()
            if cardRoll < 0.18 then
                local player = pickCardPlayer(foulContext)
                local eventType = Random() < 0.08 and "red_card" or "yellow_card"
                local reason = EventFlavors.rollCardReason(eventType == "red_card")
                table.insert(events, {
                    type = eventType,
                    minute = minute,
                    playerId = player and player.id,
                    teamId = foulSideHome and fixture.homeTeamId or fixture.awayTeamId,
                    cardReason = reason.id,
                    cardReasonName = reason.name,
                    templateIdx = RandomInt(1, 100),
                })
                if eventType == "red_card" then
                    foulContext.redCards = (foulContext.redCards or 0) + 1
                end
            end
        end

        local injuryChance = (options.injuryChance or 0.0014) * ((homeContext.injuryRisk + awayContext.injuryRisk) / 2)
        if Random() < injuryChance then
            local injuredHome = Random() < 0.5
            local context = injuredHome and homeContext or awayContext
            local player = pickInjuryPlayer(context)
            local injuryRisk = context.injuryRisk or 1.0
            local seChance = EventFlavors.computeSeasonEndingChance(player, {
                injuryRisk = injuryRisk,
                year = options.currentYear,
                baseChance = options.seasonEndingBase or EventFlavors.BASE_SEASON_ENDING_MATCH,
            })
            local injury = EventFlavors.rollMatchInjury({
                allowSeasonEnding = options.allowSeasonEnding,
                seasonDaysRemaining = options.seasonDaysRemaining,
                seasonEndingChance = seChance,
                maxDays = options.maxDays,
            })
            table.insert(events, {
                type = "injury",
                minute = minute,
                playerId = player and player.id,
                teamId = injuredHome and fixture.homeTeamId or fixture.awayTeamId,
                injuryDays = injury.days,
                injuryKind = injury.kind,
                injuryKindName = injury.kindName,
                injurySeverity = injury.severity,
                injurySeverityName = injury.severityName,
                injurySeasonEnding = injury.isSeasonEnding,
                templateIdx = RandomInt(1, 100),
            })
        end

        state.homePossessionTicks = state.homePossessionTicks + (attackingHome and 1 or 0)
        state.totalPossessionTicks = state.totalPossessionTicks + 1
    end

    -- 保存动量状态（步进式比赛跨 step 保持）
    state._homeMomentum = homeMomentum
    state._awayMomentum = awayMomentum
end

local function selectPenaltyKickers(context)
    local kickers = {}
    for _, player in ipairs(context.players or {}) do
        if player.position ~= "GK" then table.insert(kickers, player) end
    end
    -- 统一排序：PK 合成能力 + 特质；球队指定主罚人置顶
    table.sort(kickers, function(a, b)
        return SetPieceResolver.shootoutScore(a, context.team)
             > SetPieceResolver.shootoutScore(b, context.team)
    end)
    if #kickers == 0 and context.players and context.players[1] then
        table.insert(kickers, context.players[1])
    end
    while #kickers < 5 and #kickers > 0 do table.insert(kickers, kickers[#kickers]) end
    return kickers
end

local function findGoalkeeper(context)
    for _, player in ipairs(context.players or {}) do
        if player.position == "GK" then return player end
    end
    return context.players and context.players[1] or nil
end

-- 点球检定统一走 SetPieceResolver（场内点球与点球大战同一模型）
local function takePenalty(kicker, goalkeeper)
    return SetPieceResolver.takePenalty(kicker, goalkeeper)
end

--- 解析 fixture 对应的主客队（俱乐部或世界杯虚拟国家队）
function MatchEngine._resolveTeams(gameState, fixture)
    if fixture._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        local homeTeam = WorldCup.buildNationalTeam(gameState, fixture.homeTeamId)
        local awayTeam = WorldCup.buildNationalTeam(gameState, fixture.awayTeamId)
        return homeTeam, awayTeam
    end
    return gameState.teams[fixture.homeTeamId], gameState.teams[fixture.awayTeamId]
end

--- 淘汰赛加时 + 点球（单场决胜或两回合次回合决胜共用）
---@return table extraTime
---@return table state 更新后的模拟状态（含加时进球）
function MatchEngine.simulateExtraTimeAndPenalties(fixture, homeContext, awayContext, state)
    state = state or {
        events = {},
        homeGoals = 0,
        awayGoals = 0,
        homeShots = 0,
        awayShots = 0,
        homeShotsOnTarget = 0,
        awayShotsOnTarget = 0,
        homeFouls = 0,
        awayFouls = 0,
        homePossessionTicks = 0,
        totalPossessionTicks = 0,
    }

    local beforeHome = state.homeGoals or 0
    local beforeAway = state.awayGoals or 0
    MatchEngine._simulateMinutes(fixture, homeContext, awayContext, 91, 120, state, {
        phaseChance = 0.35,
        injuryChance = 0.0018,
    })

    local extraTime = {
        played = true,
        homeExtraGoals = state.homeGoals - beforeHome,
        awayExtraGoals = state.awayGoals - beforeAway,
    }
    if state.homeGoals == state.awayGoals then
        extraTime.penalties = MatchEngine._simulatePenaltyShootout(homeContext, awayContext, fixture)
    end
    return extraTime, state
end

function MatchEngine._simulatePenaltyShootout(homeContext, awayContext, fixture)
    local homeKickers = selectPenaltyKickers(homeContext)
    local awayKickers = selectPenaltyKickers(awayContext)
    local homeKeeper = findGoalkeeper(homeContext)
    local awayKeeper = findGoalkeeper(awayContext)
    local homeScore, awayScore = 0, 0
    local rounds = {}

    for round = 1, 5 do
        local homeKicker = homeKickers[((round - 1) % #homeKickers) + 1]
        local awayKicker = awayKickers[((round - 1) % #awayKickers) + 1]
        local homeScored = takePenalty(homeKicker, awayKeeper)
        local awayScored = takePenalty(awayKicker, homeKeeper)
        if homeScored then homeScore = homeScore + 1 end
        if awayScored then awayScore = awayScore + 1 end
        table.insert(rounds, {
            round = round,
            homeScored = homeScored,
            awayScored = awayScored,
            homeKickerId = homeKicker and homeKicker.id,
            awayKickerId = awayKicker and awayKicker.id,
        })

        local remaining = 5 - round
        if homeScore - awayScore > remaining or awayScore - homeScore > remaining then break end
    end

    local suddenDeath = 0
    while homeScore == awayScore and suddenDeath < 10 do
        suddenDeath = suddenDeath + 1
        local index = 5 + suddenDeath
        local homeKicker = homeKickers[((index - 1) % #homeKickers) + 1]
        local awayKicker = awayKickers[((index - 1) % #awayKickers) + 1]
        local homeScored = takePenalty(homeKicker, awayKeeper)
        local awayScored = takePenalty(awayKicker, homeKeeper)
        if homeScored then homeScore = homeScore + 1 end
        if awayScored then awayScore = awayScore + 1 end
        table.insert(rounds, {
            round = index,
            homeScored = homeScored,
            awayScored = awayScored,
            homeKickerId = homeKicker and homeKicker.id,
            awayKickerId = awayKicker and awayKicker.id,
            isSuddenDeath = true,
        })
        if homeScored ~= awayScored then break end
    end

    local winnerId = homeScore > awayScore and fixture.homeTeamId or fixture.awayTeamId
    return {
        homeScore = homeScore,
        awayScore = awayScore,
        homeScored = homeScore,
        awayScored = awayScore,
        rounds = rounds,
        winner = winnerId,
    }
end

function MatchEngine.simulate(gameState, fixture)
    local homeTeam, awayTeam = MatchEngine._resolveTeams(gameState, fixture)
    if not homeTeam or not awayTeam then return nil end

    local homeContext = TacticsResolver.buildTeamContext(gameState, homeTeam)
    local awayContext = TacticsResolver.buildTeamContext(gameState, awayTeam)
    if #homeContext.players == 0 or #awayContext.players == 0 then return nil end

    local state = {
        events = {},
        homeGoals = 0,
        awayGoals = 0,
        homeShots = 0,
        awayShots = 0,
        homeShotsOnTarget = 0,
        awayShotsOnTarget = 0,
        homeFouls = 0,
        awayFouls = 0,
        homePossessionTicks = 0,
        totalPossessionTicks = 0,
    }

    MatchEngine._simulateMinutes(fixture, homeContext, awayContext, 1, 90, state, {
        allowSeasonEnding = true,
        seasonDaysRemaining = EventFlavors.estimateSeasonDaysRemaining(gameState),
        currentYear = gameState.date and gameState.date.year,
    })

    local extraTime = nil
    if fixture.isKnockout and state.homeGoals == state.awayGoals then
        extraTime = MatchEngine.simulateExtraTimeAndPenalties(fixture, homeContext, awayContext, state)
    end

    state.extraTime = extraTime
    state.homeCorners = math.max(0, math.floor(state.homeShots * 0.28 + poisson(1.1)))
    state.awayCorners = math.max(0, math.floor(state.awayShots * 0.28 + poisson(1.0)))
    state.homePossession = state.totalPossessionTicks > 0 and (state.homePossessionTicks / state.totalPossessionTicks) or 0.5

    return MatchReport.build(fixture, homeContext, awayContext, state.events, state)
end

--- 创建步进式比赛会话（玩家比赛使用）
---@param gameState table
---@param fixture table
---@return MatchSession|nil
function MatchEngine.startMatch(gameState, fixture)
    if fixture._isWC then
        return MatchSession.newWC(gameState, fixture)
    end
    return MatchSession.new(gameState, fixture)
end

--- 完成比赛会话，生成最终报告并应用结果
---@param session MatchSession
---@param gameState table
---@param fixture table
---@return table report
function MatchEngine.finishMatch(session, gameState, fixture)
    -- 幂等性保护：防止重复调用导致积分榜重复计算
    if fixture.status == "finished" then
        return session:buildReport()
    end

    local report = session:buildReport()
    ---@diagnostic disable-next-line: return-type-mismatch
    if not report then return nil end

    -- 还原存档阵容（临场换人仅存在于 session / report）
    if session.restoreKickoffLineups then
        session:restoreKickoffLineups()
    end

    -- 应用比赛结果（积分榜、球员数据等）
    if fixture._isWC then
        local TurnProcessor = require("scripts/core/turn_processor")
        TurnProcessor._applyWCResult(gameState, fixture, report)
        -- 世界杯比赛不更新俱乐部士气/声望/财务
        return report
    elseif fixture._isUCL then
        local TurnProcessor = require("scripts/core/turn_processor")
        TurnProcessor._applyUCLResult(gameState, fixture, report)
    else
        PlaceholderEngine.applyResult(gameState, fixture, report)
    end

    -- 赛后士气 & 声望更新（仅俱乐部比赛）
    local MoraleManager = require("scripts/systems/morale_manager")
    local ReputationManager = require("scripts/systems/reputation_manager")
    local FinanceManager = require("scripts/systems/finance_manager")

    local homeGoals = report.homeGoals or 0
    local awayGoals = report.awayGoals or 0
    local homeResult, awayResult
    if homeGoals > awayGoals then
        homeResult, awayResult = "W", "L"
    elseif homeGoals < awayGoals then
        homeResult, awayResult = "L", "W"
    else
        homeResult, awayResult = "D", "D"
    end
    local goalDiff = homeGoals - awayGoals
    MoraleManager.postMatchUpdate(gameState, fixture.homeTeamId, homeResult, nil)
    MoraleManager.postMatchUpdate(gameState, fixture.awayTeamId, awayResult, nil)
    ReputationManager.postMatchUpdate(gameState, fixture.homeTeamId, fixture.awayTeamId, homeResult, goalDiff)
    ReputationManager.postMatchUpdate(gameState, fixture.awayTeamId, fixture.homeTeamId, awayResult, -goalDiff)

    -- 主场票房（返回明细供赛后展示）
    local revenueDetails = FinanceManager.processMatchDayRevenue(gameState, fixture.homeTeamId, true, fixture.awayTeamId)
    if revenueDetails and fixture.homeTeamId == gameState.playerTeamId then
        report.matchDayRevenue = revenueDetails
    end

    return report
end

function MatchEngine.applyResult(gameState, fixture, report)
    return PlaceholderEngine.applyResult(gameState, fixture, report)
end

function MatchEngine.generateOpponentAnalysis(gameState, opponentTeamId)
    return PlaceholderEngine.generateOpponentAnalysis(gameState, opponentTeamId)
end

return MatchEngine
