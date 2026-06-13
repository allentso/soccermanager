-- match/match_report.lua
-- Builds the canonical report shape consumed by match_live and match_result.

local MatchReport = {}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function round1(value)
    return math.floor(value * 10 + 0.5) / 10
end

local function countGoals(events, teamId)
    local goals = 0
    for _, event in ipairs(events or {}) do
        if event.type == "goal" and event.teamId == teamId then
            goals = goals + 1
        end
    end
    return goals
end

local function eventCount(events, playerId, eventType)
    local count = 0
    for _, event in ipairs(events or {}) do
        if event.playerId == playerId and event.type == eventType then
            count = count + 1
        end
    end
    return count
end

local function assistCount(events, playerId)
    local count = 0
    for _, event in ipairs(events or {}) do
        if event.type == "goal" and event.assistPlayerId == playerId then
            count = count + 1
        end
    end
    return count
end

function MatchReport.calculatePlayerRatings(homeContext, awayContext, events, fixture, homeGoals, awayGoals, meta)
    meta = meta or {}
    local ratings = {}
    local allEntries = {}

    local function appendFromLineup(ids, context, teamId)
        if not ids or #ids == 0 then return end
        local idSet = {}
        for _, pid in ipairs(ids) do
            idSet[pid] = true
        end
        for _, player in ipairs(context.players or {}) do
            if idSet[player.id] then
                table.insert(allEntries, { player = player, teamId = teamId, context = context })
            end
        end
    end

    if meta.ratingLineup then
        appendFromLineup(meta.ratingLineup.home, homeContext, fixture.homeTeamId)
        appendFromLineup(meta.ratingLineup.away, awayContext, fixture.awayTeamId)
    else
        for _, player in ipairs(homeContext.players or {}) do
            table.insert(allEntries, { player = player, teamId = fixture.homeTeamId, context = homeContext })
        end
        for _, player in ipairs(awayContext.players or {}) do
            table.insert(allEntries, { player = player, teamId = fixture.awayTeamId, context = awayContext })
        end
    end

    for _, entry in ipairs(allEntries) do
        local player = entry.player
        local isHome = entry.teamId == fixture.homeTeamId
        local teamGoals = isHome and homeGoals or awayGoals
        local conceded = isHome and awayGoals or homeGoals
        local rating = 6.35

        rating = rating + ((player.overall or 50) - 60) / 60
        rating = rating + (((player.fitness or 80) - 75) / 100)
        rating = rating + (((player.morale or 60) - 60) / 130)

        rating = rating + eventCount(events, player.id, "goal") * 1.0
        rating = rating + assistCount(events, player.id) * 0.45
        rating = rating - eventCount(events, player.id, "yellow_card") * 0.25
        rating = rating - eventCount(events, player.id, "red_card") * 1.35
        rating = rating - eventCount(events, player.id, "injury") * 0.45

        if teamGoals > conceded then rating = rating + 0.25
        elseif teamGoals < conceded then rating = rating - 0.2 end

        if player.position == "GK" then
            if conceded == 0 then rating = rating + 0.8 end
            if conceded >= 3 then rating = rating - 0.45 end
        elseif player.position == "CB" or player.position == "LB" or player.position == "RB" then
            if conceded == 0 then rating = rating + 0.25 end
            if conceded >= 3 then rating = rating - 0.25 end
        end

        rating = rating + (Random() - 0.5) * 0.35
        ratings[player.id] = round1(clamp(rating, 4.0, 10.0))
    end

    return ratings
end

function MatchReport.build(fixture, homeContext, awayContext, events, simState, meta)
    events = events or {}
    simState = simState or {}
    meta = meta or {}
    table.sort(events, function(a, b)
        if a.minute == b.minute then
            local priority = { goal = 1, red_card = 2, yellow_card = 3, injury = 4 }
            return (priority[a.type] or 9) < (priority[b.type] or 9)
        end
        return (a.minute or 0) < (b.minute or 0)
    end)

    local homeGoals = simState.homeGoals or countGoals(events, fixture.homeTeamId)
    local awayGoals = simState.awayGoals or countGoals(events, fixture.awayTeamId)
    local homeShots = math.max(homeGoals, simState.homeShots or homeGoals)
    local awayShots = math.max(awayGoals, simState.awayShots or awayGoals)
    local homeShotsOnTarget = math.max(homeGoals, simState.homeShotsOnTarget or homeGoals)
    local awayShotsOnTarget = math.max(awayGoals, simState.awayShotsOnTarget or awayGoals)
    local homePossession = clamp(math.floor((simState.homePossession or 0.5) * 100 + 0.5), 28, 72)

    local report = {
        fixtureId = fixture.id,
        homeTeamId = fixture.homeTeamId,
        awayTeamId = fixture.awayTeamId,
        homeGoals = homeGoals,
        awayGoals = awayGoals,
        events = events,
        playerRatings = MatchReport.calculatePlayerRatings(
            homeContext, awayContext, events, fixture, homeGoals, awayGoals, meta),
        extraTime = simState.extraTime,
        stats = {
            homeShots = homeShots,
            awayShots = awayShots,
            homeShotsOnTarget = math.min(homeShots, homeShotsOnTarget),
            awayShotsOnTarget = math.min(awayShots, awayShotsOnTarget),
            homePossession = homePossession,
            awayPossession = 100 - homePossession,
            homeFouls = simState.homeFouls or 0,
            awayFouls = simState.awayFouls or 0,
            homeCorners = simState.homeCorners or math.max(1, math.floor(homeShots * 0.32)),
            awayCorners = simState.awayCorners or math.max(1, math.floor(awayShots * 0.32)),
            homeChemistry = math.floor((homeContext.chemistry or 1.0) * 100 + 0.5),
            awayChemistry = math.floor((awayContext.chemistry or 1.0) * 100 + 0.5),
        },
    }

    if meta.appearanceIds then report.appearanceIds = meta.appearanceIds end
    if meta.ratingLineup then report.ratingLineup = meta.ratingLineup end
    if meta.substitutions then report.substitutions = meta.substitutions end
    if meta.liveFitnessApplied then report._liveFitnessApplied = true end

    return report
end

function MatchReport.findMOTM(report)
    local bestPlayerId = nil
    local bestRating = -1
    for playerId, rating in pairs(report.playerRatings or {}) do
        if rating > bestRating then
            bestPlayerId = playerId
            bestRating = rating
        end
    end
    return bestPlayerId, bestRating
end

return MatchReport
