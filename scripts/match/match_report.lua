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
    if meta.playerSlotPos then report.playerSlotPos = meta.playerSlotPos end
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

--- 从 report 或 fixture 读取加时/点球数据（跳过模拟后 extras 常只在 fixture 上）
function MatchReport.getKnockoutExtras(report, fixture)
    if report and report.extraTime then return report.extraTime end
    if fixture and fixture.extraTime then return fixture.extraTime end
    return nil
end

function MatchReport.getPenaltyWinner(report, fixture)
    local extraTime = MatchReport.getKnockoutExtras(report, fixture)
    if extraTime and extraTime.penalties and extraTime.penalties.winner then
        return extraTime.penalties.winner
    end
    if fixture and fixture._penaltyWinner then
        return fixture._penaltyWinner
    end
    return nil
end

--- 将 fixture 上的加时/点球等信息合并进 report（供结果页与消息使用）
function MatchReport.enrichFromFixture(report, fixture, gameState)
    if not report or not fixture then return report end
    if not report.extraTime and fixture.extraTime then
        report.extraTime = fixture.extraTime
    end
    return report
end

local function _findUclLeg1(fixture, gameState)
    if not fixture or not fixture._isUCL or fixture.leg ~= 2 then return nil end
    local ucl = gameState and gameState.championsLeague
    if not ucl or not ucl.knockout then return nil end
    local fixtures = ucl.knockout[ucl.phase]
    if not fixtures then return nil end
    for _, f in ipairs(fixtures) do
        if f.matchIndex == fixture.matchIndex and f.leg == 1 and f.status == "finished" then
            return f
        end
    end
    return nil
end

function MatchReport.formatUclAggregate(fixture, gameState)
    local leg1 = _findUclLeg1(fixture, gameState)
    if not leg1 then return nil end
    local agg1 = (leg1.homeGoals or 0) + (fixture.awayGoals or 0)
    local agg2 = (leg1.awayGoals or 0) + (fixture.homeGoals or 0)
    return string.format("总比分 %d-%d", agg1, agg2)
end

--- 格式化加时/点球明细（不含队名与常规比分）
function MatchReport.formatExtraTimeDetail(homeGoals, awayGoals, extraTime, fixture)
    if not extraTime then return nil end

    local homeET = extraTime.homeExtraGoals or 0
    local awayET = extraTime.awayExtraGoals or 0
    local pen = extraTime.penalties
    local penHome = pen and (pen.homeScore or pen.homeScored or 0) or nil
    local penAway = pen and (pen.awayScore or pen.awayScored or 0) or nil

    -- 欧冠次回合总比分决胜：加时独立模拟，进球不计入 90 分钟比分
    local etSeparate = fixture and fixture._isUCL and fixture.leg == 2

    if penHome ~= nil then
        if etSeparate then
            if homeET > 0 or awayET > 0 then
                return string.format("加时 %d-%d · 点球 %d-%d", homeET, awayET, penHome, penAway)
            end
            return string.format("点球 %d-%d", penHome, penAway)
        end
        local regularHome = (homeGoals or 0) - homeET
        local regularAway = (awayGoals or 0) - awayET
        if homeET > 0 or awayET > 0 then
            return string.format("常规 %d-%d · 加时 %d-%d · 点球 %d-%d",
                regularHome, regularAway, homeGoals, awayGoals, penHome, penAway)
        end
        return string.format("点球 %d-%d", penHome, penAway)
    end

    if homeET > 0 or awayET > 0 then
        if etSeparate then
            return string.format("加时 %d-%d", homeET, awayET)
        end
        local regularHome = (homeGoals or 0) - homeET
        local regularAway = (awayGoals or 0) - awayET
        return string.format("常规 %d-%d · 加时 %d-%d", regularHome, regularAway, homeGoals, awayGoals)
    end

    if extraTime.played then return "加时赛" end
    return nil
end

--- 完整比分摘要：常规比分 + 总比分（欧冠次回合）+ 加时/点球
function MatchReport.formatScoreSummary(homeName, awayName, report, fixture, gameState)
    homeName = homeName or "主队"
    awayName = awayName or "客队"
    local homeGoals = (report and report.homeGoals) or 0
    local awayGoals = (report and report.awayGoals) or 0

    local parts = { string.format("%s %d - %d %s", homeName, homeGoals, awayGoals, awayName) }

    if fixture and gameState then
        local aggText = MatchReport.formatUclAggregate(fixture, gameState)
        if aggText then table.insert(parts, aggText) end
    end

    local extraTime = MatchReport.getKnockoutExtras(report, fixture)
    local etText = MatchReport.formatExtraTimeDetail(homeGoals, awayGoals, extraTime, fixture)
    if etText then
        table.insert(parts, etText)
    elseif fixture and fixture.penalties then
        local pen = fixture.penalties
        table.insert(parts, string.format("点球 %d-%d", pen.homeScore or 0, pen.awayScore or 0))
    end

    return table.concat(parts, " · ")
end

------------------------------------------------------
-- 赛后叙事（P1：丰富 inbox / 新闻正文）
------------------------------------------------------

local function _goalScorerParts(events, gameState, teamId)
    local counts, order = {}, {}
    for _, evt in ipairs(events or {}) do
        if evt.type == "goal" and not evt.isOwnGoal and evt.teamId == teamId and evt.playerId then
            local pid = evt.playerId
            if not counts[pid] then
                counts[pid] = 0
                table.insert(order, pid)
            end
            counts[pid] = counts[pid] + 1
        end
    end
    local parts = {}
    for _, pid in ipairs(order) do
        local p = gameState and gameState.players[pid]
        local name = p and p.displayName or "?"
        local n = counts[pid]
        table.insert(parts, n > 1 and string.format("%s×%d", name, n) or name)
    end
    return parts
end

function MatchReport.formatScorersSummary(events, gameState, homeTeamId, awayTeamId, homeName, awayName)
    local homeScorers = _goalScorerParts(events, gameState, homeTeamId)
    local awayScorers = _goalScorerParts(events, gameState, awayTeamId)
    local lines = {}
    if #homeScorers > 0 then
        table.insert(lines, string.format("%s: %s", homeName or "主队", table.concat(homeScorers, ", ")))
    end
    if #awayScorers > 0 then
        table.insert(lines, string.format("%s: %s", awayName or "客队", table.concat(awayScorers, ", ")))
    end
    if #lines == 0 then
        return "本场无进球。"
    end
    return table.concat(lines, "\n")
end

function MatchReport.formatMOTMLine(report, fixture, gameState)
    local ratings = (report and report.playerRatings) or (fixture and fixture.playerRatings)
    if not ratings then return nil end
    local motmId, motmRating = MatchReport.findMOTM({ playerRatings = ratings })
    if not motmId then return nil end
    local p = gameState and gameState.players[motmId]
    local name = p and p.displayName or "?"
    return string.format("最佳球员: %s (%.1f)", name, motmRating or 0)
end

function MatchReport.getFixtureTags(gameState, fixture, perspectiveTeamId)
    local tags = {}
    if not fixture or not gameState then return tags end

    if fixture._isUCL then table.insert(tags, "ucl")
    elseif fixture._isDomesticCup then table.insert(tags, "cup")
    elseif fixture._isWC or fixture._isEuro then table.insert(tags, "intl")
    end

    local TransferManager = require("scripts/systems/transfer_manager")
    if perspectiveTeamId then
        local oppId = fixture.homeTeamId == perspectiveTeamId and fixture.awayTeamId or fixture.awayTeamId
        if oppId and TransferManager.isRivalry(gameState, perspectiveTeamId, oppId) then
            table.insert(tags, "derby")
        end
    elseif TransferManager.isRivalry(gameState, fixture.homeTeamId, fixture.awayTeamId) then
        table.insert(tags, "derby")
    end

    local function leaguePos(teamId)
        local lg = gameState.league
        if gameState.getTeamLeague then
            lg = gameState:getTeamLeague(teamId) or lg
        end
        if lg and lg.getTeamPosition then
            return lg:getTeamPosition(teamId)
        end
        return nil
    end

    local homePos = leaguePos(fixture.homeTeamId)
    local awayPos = leaguePos(fixture.awayTeamId)
    local totalTeams = 0
    local lg = gameState.league
    if gameState.getTeamLeague then
        lg = gameState:getTeamLeague(fixture.homeTeamId) or lg
    end
    if lg and lg.teamIds then totalTeams = #lg.teamIds end

    if totalTeams >= 6 then
        local relegationLine = totalTeams - 2
        if (homePos and homePos >= relegationLine) or (awayPos and awayPos >= relegationLine) then
            table.insert(tags, "relegation")
        end
        if (homePos and homePos <= 3) or (awayPos and awayPos <= 3) then
            table.insert(tags, "title_race")
        end
    end

    if homePos and awayPos and math.abs(homePos - awayPos) >= 5 then
        local homeGoals = fixture.homeGoals or 0
        local awayGoals = fixture.awayGoals or 0
        if homeGoals ~= awayGoals then
            table.insert(tags, "upset")
        end
    end

    local diff = math.abs((fixture.homeGoals or 0) - (fixture.awayGoals or 0))
    if diff >= 4 then table.insert(tags, "blowout") end

    return tags
end

function MatchReport.buildPostMatchCommentary(gameState, fixture, report, perspectiveTeamId)
    if not fixture or fixture.status ~= "finished" then return nil end

    local homeGoals = fixture.homeGoals or (report and report.homeGoals) or 0
    local awayGoals = fixture.awayGoals or (report and report.awayGoals) or 0
    local tags = MatchReport.getFixtureTags(gameState, fixture, perspectiveTeamId)
    local tagSet = {}
    for _, t in ipairs(tags) do tagSet[t] = true end

    local function has(tag) return tagSet[tag] end

    if perspectiveTeamId then
        local isHome = fixture.homeTeamId == perspectiveTeamId
        local myGoals = isHome and homeGoals or awayGoals
        local oppGoals = isHome and awayGoals or homeGoals
        if myGoals > oppGoals then
            if has("derby") then return "德比战取胜，更衣室气氛高涨！"
            elseif has("blowout") then return "一场酣畅淋漓的大胜，球队士气大振。"
            elseif has("title_race") then return "关键三分到手，争冠希望得以延续。"
            elseif has("relegation") then return "宝贵的胜利，保级形势有所缓解。"
            elseif has("cup") or has("ucl") then return "淘汰赛取胜，向冠军又迈进一步。"
            else return "顺利拿下三分，联赛排名继续稳固。" end
        elseif myGoals < oppGoals then
            if has("derby") then return "德比失利，球迷失望而归。"
            elseif has("relegation") then return "失利令保级形势更加严峻，必须迅速反弹。"
            elseif has("title_race") then return "争冠关键战失手，球队需要重新集结。"
            else return "未能拿下比赛，球队需要尽快调整状态。" end
        else
            if has("derby") then return "德比战平，双方均未占到便宜。"
            elseif has("relegation") then return "平局对保级队而言尚可接受，但仍需抢分。"
            else return "平分秋色，双方各取一分。" end
        end
    end

    -- 中立新闻口吻
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    local homeName = homeTeam and homeTeam.name or "主队"
    local awayName = awayTeam and awayTeam.name or "客队"

    if has("upset") then
        local winner = homeGoals > awayGoals and homeName or awayName
        return string.format("爆出冷门！%s 在不被看好的情况下带走胜利。", winner)
    end
    if has("blowout") then
        local winner = homeGoals > awayGoals and homeName or awayName
        return string.format("%s 以压倒性优势横扫对手，展现强大统治力。", winner)
    end
    if has("derby") then return "死敌对决牵动球迷神经，比赛火药味十足。" end
    if homeGoals > awayGoals then return homeName .. " 在主场全取三分。"
    elseif homeGoals < awayGoals then return awayName .. " 客场凯旋。"
    else return "双方握手言和，各取一分。" end
end

--- 丰富版赛后摘要（inbox / 新闻）
function MatchReport.formatRichMatchBody(gameState, fixture, report, opts)
    opts = opts or {}
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    local homeName = opts.homeName or (homeTeam and homeTeam.name) or "主队"
    local awayName = opts.awayName or (awayTeam and awayTeam.name) or "客队"
    local prefix = opts.prefix or ""
    local events = (report and report.events) or fixture.events

    local lines = {
        prefix .. MatchReport.formatScoreSummary(homeName, awayName, report or fixture, fixture, gameState),
    }

    local scorers = MatchReport.formatScorersSummary(events, gameState, fixture.homeTeamId, fixture.awayTeamId, homeName, awayName)
    if scorers then
        table.insert(lines, scorers)
    end

    local motmLine = MatchReport.formatMOTMLine(report, fixture, gameState)
    if motmLine then
        table.insert(lines, motmLine)
    end

    local commentary = MatchReport.buildPostMatchCommentary(gameState, fixture, report, opts.perspectiveTeamId)
    if commentary then
        table.insert(lines, commentary)
    end

    return table.concat(lines, "\n")
end

--- 玩家比赛 → 新闻稿（同内容，避免重复发）
function MatchReport.publishPlayerMatchNews(gameState, fixture, report, opts)
    if not gameState or not fixture or fixture.status ~= "finished" then return nil end
    if not gameState.playerTeamId then return nil end
    if fixture.homeTeamId ~= gameState.playerTeamId and fixture.awayTeamId ~= gameState.playerTeamId then
        return nil
    end

    local MessageManager = require("scripts/systems/message_manager")
    local dedupeKey = "player_match_news_" .. tostring(fixture.id or 0)
    if MessageManager._isDuplicate(gameState, dedupeKey, true) then return nil end
    MessageManager._markSent(gameState, dedupeKey, true)

    opts = opts or {}
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    local homeName = opts.homeName or (homeTeam and homeTeam.name) or "主队"
    local awayName = opts.awayName or (awayTeam and awayTeam.name) or "客队"
    local title = string.format("赛后报道: %s %d-%d %s", homeName, fixture.homeGoals or 0, fixture.awayGoals or 0, awayName)

    return gameState:addNews({
        category = "match_report",
        title = title,
        body = MatchReport.formatRichMatchBody(gameState, fixture, report, {
            homeName = homeName,
            awayName = awayName,
            perspectiveTeamId = gameState.playerTeamId,
        }),
        relatedTeams = { fixture.homeTeamId, fixture.awayTeamId },
        fixtureId = fixture.id,
    })
end

return MatchReport
