-- match/match_engine.lua
-- Minute-based match simulation with the same public contract as placeholder_engine.

local TacticsResolver = require("scripts/match/tactics_resolver")
local MatchReport = require("scripts/match/match_report")
local PlaceholderEngine = require("scripts/match/placeholder_engine")

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

local function hasTrait(player, traitId)
    for _, id in ipairs(player.traits or {}) do
        if id == traitId then return true end
    end
    return false
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

local function pickShooter(context)
    return TacticsResolver.chooseWeighted(context.players, function(player)
        local group = positionGroup(player.position)
        local weight = attr(player, "shooting") * 0.8 + attr(player, "positioning") * 0.55 + attr(player, "composure") * 0.45
        if group == "FWD" then weight = weight * 2.4
        elseif player.position == "CAM" then weight = weight * 1.7
        elseif group == "MID" then weight = weight * 1.05
        elseif group == "DEF" then weight = weight * 0.3 + attr(player, "aerial") * 0.2
        else weight = 0.05 end
        if hasTrait(player, "clinical") or hasTrait(player, "poacher") then weight = weight * 1.2 end
        return weight
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
        if hasTrait(player, "playmaker") then weight = weight * 1.25 end
        return weight
    end)
end

local function pickCardPlayer(context)
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if player.position == "GK" then return 0.1 end
        return attr(player, "aggression") * 0.8 + (21 - attr(player, "decisions")) * 0.35
    end)
end

local function pickInjuryPlayer(context)
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if player.position == "GK" then return 0.15 end
        local lowFitness = 105 - (player.fitness or 80)
        return math.max(1, lowFitness) + (21 - attr(player, "stamina")) * 1.3
    end)
end

function MatchEngine._simulateMinutes(fixture, homeContext, awayContext, startMinute, endMinute, state, options)
    options = options or {}
    local events = state.events

    for minute = startMinute, endMinute do
        local homeMod = TacticsResolver.matchupModifiers(homeContext, awayContext, true)
        local awayMod = TacticsResolver.matchupModifiers(awayContext, homeContext, false)
        local avgTempo = (homeMod.tempo + awayMod.tempo) / 2
        local homePossessionChance = homeMod.possessionShare
        local attackingHome = Random() < homePossessionChance
        local attackContext = attackingHome and homeContext or awayContext
        local defendContext = attackingHome and awayContext or homeContext
        local attackMod = attackingHome and homeMod or awayMod
        local attackingTeamId = attackingHome and fixture.homeTeamId or fixture.awayTeamId

        local phaseChance = options.phaseChance or 0.24
        if Random() < phaseChance * avgTempo then
            local shotChance = clamp(0.2 * attackMod.chanceCreation, 0.08, 0.56)
            if Random() < shotChance then
                local isHome = attackingHome
                if isHome then state.homeShots = state.homeShots + 1 else state.awayShots = state.awayShots + 1 end

                local shooter = pickShooter(attackContext)
                local finishing = (attr(shooter, "shooting") * 0.9 + attr(shooter, "composure") * 0.75 + attr(shooter, "positioning") * 0.35) / 20
                local defensePressure = clamp(defendContext.defense / math.max(1, attackContext.attack), 0.55, 1.65)
                local onTargetChance = clamp(0.34 + finishing * 0.12 - defensePressure * 0.07, 0.22, 0.62)
                if Random() < onTargetChance then
                    if isHome then state.homeShotsOnTarget = state.homeShotsOnTarget + 1 else state.awayShotsOnTarget = state.awayShotsOnTarget + 1 end

                    local goalChance = clamp(0.08 + finishing * 0.055 * attackMod.shotQuality - defensePressure * 0.025, 0.035, 0.24)
                    if hasTrait(shooter, "clinical") then goalChance = goalChance + 0.018 end
                    if Random() < goalChance then
                        local assister = pickAssister(attackContext, shooter)
                        table.insert(events, {
                            type = "goal",
                            minute = minute,
                            playerId = shooter and shooter.id,
                            assistPlayerId = assister and assister.id,
                            teamId = attackingTeamId,
                            isExtraTime = minute > 90 or nil,
                        })
                        if isHome then state.homeGoals = state.homeGoals + 1 else state.awayGoals = state.awayGoals + 1 end
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
                table.insert(events, {
                    type = eventType,
                    minute = minute,
                    playerId = player and player.id,
                    teamId = foulSideHome and fixture.homeTeamId or fixture.awayTeamId,
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
            table.insert(events, {
                type = "injury",
                minute = minute,
                playerId = player and player.id,
                teamId = injuredHome and fixture.homeTeamId or fixture.awayTeamId,
                injuryDays = RandomInt(3, 21),
            })
        end

        state.homePossessionTicks = state.homePossessionTicks + (attackingHome and 1 or 0)
        state.totalPossessionTicks = state.totalPossessionTicks + 1
    end
end

local function selectPenaltyKickers(context)
    local kickers = {}
    for _, player in ipairs(context.players or {}) do
        if player.position ~= "GK" then table.insert(kickers, player) end
    end
    table.sort(kickers, function(a, b)
        local aScore = attr(a, "shooting") + attr(a, "composure") * 0.8
        local bScore = attr(b, "shooting") + attr(b, "composure") * 0.8
        return aScore > bScore
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

local function takePenalty(kicker, goalkeeper)
    local kickerScore = attr(kicker, "shooting") + attr(kicker, "composure") * 0.8 + ((kicker and kicker.morale or 60) - 50) * 0.04
    local keeperScore = attr(goalkeeper, "reflexes", 5) + attr(goalkeeper, "handling", 5) * 0.6
    local chance = clamp(0.74 + (kickerScore - keeperScore) / 220, 0.52, 0.92)
    return Random() < chance
end

function MatchEngine._simulatePenaltyShootout(homeContext, awayContext)
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

    return {
        homeScore = homeScore,
        awayScore = awayScore,
        rounds = rounds,
        winner = homeScore > awayScore and "home" or "away",
    }
end

function MatchEngine.simulate(gameState, fixture)
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
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

    MatchEngine._simulateMinutes(fixture, homeContext, awayContext, 1, 90, state)

    local extraTime = nil
    if fixture.isKnockout and state.homeGoals == state.awayGoals then
        local beforeHome = state.homeGoals
        local beforeAway = state.awayGoals
        MatchEngine._simulateMinutes(fixture, homeContext, awayContext, 91, 120, state, {
            phaseChance = 0.19,
            injuryChance = 0.0018,
        })
        extraTime = {
            played = true,
            homeExtraGoals = state.homeGoals - beforeHome,
            awayExtraGoals = state.awayGoals - beforeAway,
        }
        if state.homeGoals == state.awayGoals then
            extraTime.penalties = MatchEngine._simulatePenaltyShootout(homeContext, awayContext)
        end
    end

    state.extraTime = extraTime
    state.homeCorners = math.max(0, math.floor(state.homeShots * 0.28 + poisson(1.1)))
    state.awayCorners = math.max(0, math.floor(state.awayShots * 0.28 + poisson(1.0)))
    state.homePossession = state.totalPossessionTicks > 0 and (state.homePossessionTicks / state.totalPossessionTicks) or 0.5

    return MatchReport.build(fixture, homeContext, awayContext, state.events, state)
end

function MatchEngine.applyResult(gameState, fixture, report)
    return PlaceholderEngine.applyResult(gameState, fixture, report)
end

function MatchEngine.generateOpponentAnalysis(gameState, opponentTeamId)
    return PlaceholderEngine.generateOpponentAnalysis(gameState, opponentTeamId)
end

return MatchEngine
