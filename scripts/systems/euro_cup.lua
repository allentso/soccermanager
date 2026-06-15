-- systems/euro_cup.lua
-- 欧洲杯管理系统（2028起，24队6组，16强淘汰赛）

local Tournament = require("scripts/domain/tournament")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")
local HistoryManager = require("scripts/systems/history_manager")
local WorldCup = require("scripts/systems/world_cup")

local EuroCup = {}

local FIRST_EURO = 2028
local CYCLE = 4

-- 2028 起：中国队保底入围 + 执教邀请
local GUARANTEED_CHINA_CODE = "CHN"
local GUARANTEED_CHINA_NATION = {code = "CHN", name = "中国"}

function EuroCup.isGuaranteedChinaOfferYear(year)
    return year >= FIRST_EURO and EuroCup.isEuroYear(year)
end

local function _ensureChinaInEuro(allNations, selectedCodes)
    if selectedCodes[GUARANTEED_CHINA_CODE] then return end
    table.insert(allNations, GUARANTEED_CHINA_NATION)
    selectedCodes[GUARANTEED_CHINA_CODE] = true
end

local function _addGuaranteedChinaOffer(offers, offerSet, qualifiedSet, year)
    if not EuroCup.isGuaranteedChinaOfferYear(year) then return end
    if not qualifiedSet[GUARANTEED_CHINA_CODE] or offerSet[GUARANTEED_CHINA_CODE] then return end
    table.insert(offers, GUARANTEED_CHINA_CODE)
    offerSet[GUARANTEED_CHINA_CODE] = true
end

------------------------------------------------------
-- 每届（2028+）：8支欧洲种子必进 + 中国保底 + 候补随机至24支
-- 分组：24队洗牌随机分6组
------------------------------------------------------

local SEED_NATIONS = {
    {code = "FRA", name = "法国"},
    {code = "GER", name = "德国"},
    {code = "ESP", name = "西班牙"},
    {code = "ENG", name = "英格兰"},
    {code = "POR", name = "葡萄牙"},
    {code = "NED", name = "荷兰"},
    {code = "BEL", name = "比利时"},
    {code = "CRO", name = "克罗地亚"},
}

local NON_SEED_NATIONS = {
    {code = "ITA", name = "意大利"},
    {code = "SUI", name = "瑞士"},
    {code = "AUT", name = "奥地利"},
    {code = "TUR", name = "土耳其"},
    {code = "SWE", name = "瑞典"},
    {code = "NOR", name = "挪威"},
    {code = "SCO", name = "苏格兰"},
    {code = "CZE", name = "捷克"},
    {code = "POL", name = "波兰"},
    {code = "BIH", name = "波黑"},
    {code = "HUN", name = "匈牙利"},
    {code = "ALB", name = "阿尔巴尼亚"},
    {code = "SVN", name = "斯洛文尼亚"},
    {code = "DEN", name = "丹麦"},
    {code = "SRB", name = "塞尔维亚"},
    {code = "SVK", name = "斯洛伐克"},
    {code = "ROU", name = "罗马尼亚"},
    {code = "UKR", name = "乌克兰"},
    {code = "GEO", name = "格鲁吉亚"},
    {code = "CHN", name = "中国"},
}

-- 小组赛赛程模板（6组 × 3轮 × 2场）
local GROUP_FIXTURES = {
    {"A", 1, 1, 2, 6, 14}, {"A", 1, 3, 4, 6, 14},
    {"B", 1, 1, 2, 6, 15}, {"B", 1, 3, 4, 6, 15},
    {"C", 1, 1, 2, 6, 16}, {"C", 1, 3, 4, 6, 16},
    {"D", 1, 1, 2, 6, 16}, {"D", 1, 3, 4, 6, 16},
    {"E", 1, 1, 2, 6, 17}, {"E", 1, 3, 4, 6, 17},
    {"F", 1, 1, 2, 6, 18}, {"F", 1, 3, 4, 6, 18},
    {"A", 2, 1, 3, 6, 19}, {"A", 2, 2, 4, 6, 19},
    {"B", 2, 1, 3, 6, 20}, {"B", 2, 2, 4, 6, 20},
    {"C", 2, 1, 3, 6, 20}, {"C", 2, 2, 4, 6, 20},
    {"D", 2, 1, 3, 6, 21}, {"D", 2, 2, 4, 6, 21},
    {"E", 2, 1, 3, 6, 21}, {"E", 2, 2, 4, 6, 21},
    {"F", 2, 1, 3, 6, 22}, {"F", 2, 2, 4, 6, 22},
    {"A", 3, 4, 1, 6, 23}, {"A", 3, 2, 3, 6, 23},
    {"B", 3, 4, 1, 6, 24}, {"B", 3, 2, 3, 6, 24},
    {"C", 3, 4, 1, 6, 24}, {"C", 3, 2, 3, 6, 24},
    {"D", 3, 4, 1, 6, 25}, {"D", 3, 2, 3, 6, 25},
    {"E", 3, 4, 1, 6, 25}, {"E", 3, 2, 3, 6, 25},
    {"F", 3, 4, 1, 6, 26}, {"F", 3, 2, 3, 6, 26},
}

local KNOCKOUT_DATES = {
    r16 = {
        {6, 29}, {6, 29}, {6, 30}, {6, 30},
        {7, 1}, {7, 1}, {7, 2}, {7, 2},
    },
    qf = {{7, 5}, {7, 5}, {7, 6}, {7, 6}},
    sf = {{7, 9}, {7, 10}},
    final = {7, 14},
}

local NT_REP_THRESHOLD = 40

local EURO_NATION_TIERS = {
    S = {"FRA", "GER", "ESP", "ENG"},
    A = {"POR", "NED", "BEL", "CRO", "ITA"},
    B = {"SUI", "AUT", "TUR", "SWE", "POL", "UKR", "DEN", "SRB"},
    C = {"CZE", "NOR", "SCO", "SVK", "ROU", "ALB", "SVN", "HUN", "BIH", "GEO", "CHN"},
}

local REP_TIER_THRESHOLDS = {
    {minRep = 70, tiers = {"S", "A", "B", "C"}},
    {minRep = 55, tiers = {"A", "B", "C"}},
    {minRep = 40, tiers = {"B", "C"}},
    {minRep = 25, tiers = {"C"}},
}

local TIER_PROBABILITY = {S = 0.50, A = 0.40, B = 0.30, C = 0.25}

local _nationNameMap = nil
local function getNationNameMap()
    if _nationNameMap then return _nationNameMap end
    _nationNameMap = {}
    for _, t in ipairs(SEED_NATIONS) do
    end
    for _, t in ipairs(NON_SEED_NATIONS) do
        _nationNameMap[t.code] = _nationNameMap[t.code] or t.name
    end
    return _nationNameMap
end

------------------------------------------------------
-- 公共 API
------------------------------------------------------

function EuroCup.isEuroYear(year)
    if year < FIRST_EURO then return false end
    return (year - FIRST_EURO) % CYCLE == 0
end

function EuroCup._getNationName(code)
    local map = getNationNameMap()
    return map[code] or WorldCup._getNationName(code) or code
end

function EuroCup.getNationIconPath(code)
    return WorldCup.getNationIconPath(code)
end

function EuroCup.buildNationalTeam(gameState, nationCode)
    return WorldCup.buildNationalTeam(gameState, nationCode)
end

function EuroCup.isPlayerNationMatch(gameState, fixture)
    return WorldCup.isPlayerNationMatch(gameState, fixture)
end

function EuroCup._getPlayerNation(gameState)
    return WorldCup._getPlayerNation(gameState)
end

function EuroCup.hasPendingCoachInvite(gameState)
    return WorldCup.hasPendingCoachInvite(gameState)
end

function EuroCup.clearPendingCoachInvite(gameState)
    WorldCup.clearPendingCoachInvite(gameState)
end

function EuroCup.getActiveTournament(gameState)
    if gameState.euroCup and gameState.euroCup.phase ~= Tournament.PHASE_COMPLETED then
        return gameState.euroCup
    end
    if gameState.worldCup and gameState.worldCup.phase ~= Tournament.PHASE_COMPLETED then
        return gameState.worldCup
    end
    return gameState.euroCup or gameState.worldCup
end

function EuroCup.isInternationalTournamentYear(year)
    return EuroCup.isEuroYear(year) or WorldCup.isWorldCupYear(year)
end

------------------------------------------------------
-- 初始化
------------------------------------------------------

function EuroCup.initialize(gameState)
    local euroYear = gameState.season
    if not EuroCup.isEuroYear(euroYear) then
        return nil
    end

    if gameState.euroCup and gameState.euroCup.season == euroYear then
        return gameState.euroCup
    end

    local allNations = {}
    local playerNation = EuroCup._getPlayerNation(gameState)
    local selectedCodes = {}

    for _, t in ipairs(SEED_NATIONS) do
        table.insert(allNations, t)
        selectedCodes[t.code] = true
    end

    if playerNation and not selectedCodes[playerNation] then
        for _, t in ipairs(NON_SEED_NATIONS) do
            if t.code == playerNation then
                table.insert(allNations, t)
                selectedCodes[t.code] = true
                break
            end
        end
    end

    _ensureChinaInEuro(allNations, selectedCodes)

    local candidates = {}
    for _, t in ipairs(NON_SEED_NATIONS) do
        if not selectedCodes[t.code] then
            table.insert(candidates, t)
        end
    end
    for i = #candidates, 2, -1 do
        local j = math.floor(Random() * i) + 1
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
    local remaining = 24 - #allNations
    for i = 1, math.min(remaining, #candidates) do
        table.insert(allNations, candidates[i])
    end

    local allNationCodes = {}
    for _, t in ipairs(allNations) do
        table.insert(allNationCodes, t.code)
    end

    local euro = Tournament.new({
        name = "欧洲杯",
        shortName = "EURO",
        type = "euro",
        season = euroYear,
        qualifiedTeams = allNationCodes,
    })

    local groupNames = {"A", "B", "C", "D", "E", "F"}
    euro.groups = {}

    local shuffled = {}
    for i, t in ipairs(allNations) do shuffled[i] = t end
    for i = #shuffled, 2, -1 do
        local j = math.floor(Random() * i) + 1
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    for g = 1, 6 do
        local gName = groupNames[g]
        local teamIds = {}
        for k = 1, 4 do
            local idx = (g - 1) * 4 + k
            table.insert(teamIds, shuffled[idx].code)
        end
        euro.groups[gName] = {
            teamIds = teamIds,
            standings = {},
            fixtures = {},
        }
    end

    for _, group in pairs(euro.groups) do
        for _, tid in ipairs(group.teamIds) do
            group.standings[tid] = {
                teamId = tid,
                played = 0, wins = 0, draws = 0, losses = 0,
                goalsFor = 0, goalsAgainst = 0, goalDifference = 0, points = 0,
            }
        end
    end

    EuroCup._generateGroupFixtures(euro, euroYear)
    euro.phase = Tournament.PHASE_GROUP
    gameState.euroCup = euro

    gameState:addNews({
        category = "euro_news",
        title = string.format("%d 欧洲杯分组抽签结果揭晓！", euroYear),
        body = EuroCup._formatDrawResult(euro),
    })

    EuroCup._checkNationalTeamInvitation(gameState, allNationCodes, euroYear)
    return euro
end

function EuroCup._generateGroupFixtures(euro, euroYear)
    local fixtureId = 1
    for _, entry in ipairs(GROUP_FIXTURES) do
        local groupName, round, homeIdx, awayIdx, month, day = entry[1], entry[2], entry[3], entry[4], entry[5], entry[6]
        local group = euro.groups[groupName]
        if group then
            table.insert(group.fixtures, {
                id = fixtureId,
                groupName = groupName,
                round = round,
                homeTeamId = group.teamIds[homeIdx],
                awayTeamId = group.teamIds[awayIdx],
                date = {year = euroYear, month = month, day = day},
                status = "scheduled",
                homeGoals = 0,
                awayGoals = 0,
            })
            fixtureId = fixtureId + 1
        end
    end
end

------------------------------------------------------
-- 阶段推进
------------------------------------------------------

function EuroCup.checkPhaseAdvance(gameState)
    local euro = gameState.euroCup
    if not euro or euro.phase == Tournament.PHASE_COMPLETED or euro.phase == Tournament.PHASE_NOT_STARTED then
        return
    end

    if euro.phase == Tournament.PHASE_GROUP and euro:isGroupStageComplete() then
        EuroCup._advanceToR16(gameState, euro)
    end
    if euro.phase == Tournament.PHASE_R16 and EuroCup._isRoundComplete(euro, "r16") then
        EuroCup._advanceToQF(gameState, euro)
    end
    if euro.phase == Tournament.PHASE_QF and EuroCup._isRoundComplete(euro, "qf") then
        EuroCup._advanceToSF(gameState, euro)
    end
    if euro.phase == Tournament.PHASE_SF and EuroCup._isRoundComplete(euro, "sf") then
        EuroCup._advanceToFinal(gameState, euro)
    end
    if euro.phase == Tournament.PHASE_FINAL and EuroCup._isRoundComplete(euro, "final") then
        EuroCup._completeTournament(gameState, euro)
    end
end

function EuroCup._isRoundComplete(euro, phase)
    local fixtures = euro.knockout[phase]
    if not fixtures or #fixtures == 0 then return false end
    for _, f in ipairs(fixtures) do
        if f.status ~= "finished" then return false end
    end
    return true
end

local function _rankKey(data)
    return data.points, data.goalDifference, data.goalsFor
end

local function _pickThird(qualifiedThirds, used, allowedGroups, excludeGroup)
    local allowed = {}
    for _, g in ipairs(allowedGroups) do allowed[g] = true end
    for j, third in ipairs(qualifiedThirds) do
        if not used[j] and allowed[third.group] and third.group ~= excludeGroup then
            used[j] = true
            return third.teamId
        end
    end
    for j, third in ipairs(qualifiedThirds) do
        if not used[j] and third.group ~= excludeGroup then
            used[j] = true
            return third.teamId
        end
    end
    for j, third in ipairs(qualifiedThirds) do
        if not used[j] then
            used[j] = true
            return third.teamId
        end
    end
    return nil
end

function EuroCup._advanceToR16(gameState, euro)
    local groupNames = {"A", "B", "C", "D", "E", "F"}
    local firsts, seconds, allThirds = {}, {}, {}

    for _, gName in ipairs(groupNames) do
        local sorted = euro:getGroupSortedStandings(gName)
        if sorted[1] then firsts[gName] = sorted[1] end
        if sorted[2] then seconds[gName] = sorted[2] end
        if sorted[3] then
            table.insert(allThirds, {teamId = sorted[3].teamId, group = gName, data = sorted[3]})
        end
    end

    table.sort(allThirds, function(a, b)
        local ap, agd, agf = _rankKey(a.data)
        local bp, bgd, bgf = _rankKey(b.data)
        if ap ~= bp then return ap > bp end
        if agd ~= bgd then return agd > bgd end
        return agf > bgf
    end)

    local qualifiedThirds = {}
    for i = 1, math.min(4, #allThirds) do
        table.insert(qualifiedThirds, allThirds[i])
    end

    local usedThirds = {}
    local matchups = {}
    if firsts.A and seconds.C then table.insert(matchups, {firsts.A.teamId, seconds.C.teamId}) end
    if seconds.A and seconds.B then table.insert(matchups, {seconds.A.teamId, seconds.B.teamId}) end
    if firsts.B then
        local t = _pickThird(qualifiedThirds, usedThirds, {"A", "D", "E", "F"}, "B")
        if t then table.insert(matchups, {firsts.B.teamId, t}) end
    end
    if firsts.C then
        local t = _pickThird(qualifiedThirds, usedThirds, {"D", "E", "F"}, "C")
        if t then table.insert(matchups, {firsts.C.teamId, t}) end
    end
    if firsts.D and seconds.F then table.insert(matchups, {firsts.D.teamId, seconds.F.teamId}) end
    if seconds.D and seconds.E then table.insert(matchups, {seconds.D.teamId, seconds.E.teamId}) end
    if firsts.E then
        local t = _pickThird(qualifiedThirds, usedThirds, {"A", "B", "C", "D"}, "E")
        if t then table.insert(matchups, {firsts.E.teamId, t}) end
    end
    if firsts.F then
        local t = _pickThird(qualifiedThirds, usedThirds, {"A", "B", "C"}, "F")
        if t then table.insert(matchups, {firsts.F.teamId, t}) end
    end

    local fixtures = {}
    local dates = KNOCKOUT_DATES.r16
    for i, m in ipairs(matchups) do
        local d = dates[math.min(i, #dates)]
        table.insert(fixtures, {
            id = "r16_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = euro.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            isKnockout = true,
        })
    end

    euro.knockout.r16 = fixtures
    euro.phase = Tournament.PHASE_R16

    gameState:addNews({
        category = "euro_news",
        title = "欧洲杯16强对阵出炉！",
        body = EuroCup._formatKnockoutDraw(matchups),
    })
end

function EuroCup._advanceToQF(gameState, euro)
    EuroCup._advanceKnockoutRound(gameState, euro, "r16", "qf", KNOCKOUT_DATES.qf, "欧洲杯8强对阵！")
end

function EuroCup._advanceToSF(gameState, euro)
    EuroCup._advanceKnockoutRound(gameState, euro, "qf", "sf", KNOCKOUT_DATES.sf, "欧洲杯4强对阵！")
end

function EuroCup._advanceKnockoutRound(gameState, euro, fromPhase, toPhase, dates, newsTitle)
    local winners = EuroCup._getSingleLegWinners(euro, fromPhase)
    if #winners < 2 then return end

    local matchups = {}
    for i = 1, #winners - 1, 2 do
        table.insert(matchups, {winners[i], winners[i + 1]})
    end

    local fixtures = {}
    for i, m in ipairs(matchups) do
        local d = dates[math.min(i, #dates)]
        table.insert(fixtures, {
            id = toPhase .. "_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = euro.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            isKnockout = true,
        })
    end

    euro.knockout[toPhase] = fixtures
    euro.phase = toPhase

    gameState:addNews({
        category = "euro_news",
        title = newsTitle,
        body = EuroCup._formatKnockoutDraw(matchups),
    })
end

function EuroCup._advanceToFinal(gameState, euro)
    local winners = EuroCup._getSingleLegWinners(euro, "sf")
    if #winners < 2 then return end

    local d = KNOCKOUT_DATES.final
    local fixtures = {{
        id = "final_1",
        leg = 1,
        matchIndex = 1,
        homeTeamId = winners[1],
        awayTeamId = winners[2],
        date = {year = euro.season, month = d[1], day = d[2]},
        status = "scheduled",
        homeGoals = 0,
        awayGoals = 0,
        isKnockout = true,
    }}

    euro.knockout.final = fixtures
    euro.phase = Tournament.PHASE_FINAL

    gameState:addNews({
        category = "euro_news",
        title = "欧洲杯决赛对阵确定！",
        body = string.format("%s vs %s\n决赛日期: %d年7月14日",
            EuroCup._getNationName(winners[1]), EuroCup._getNationName(winners[2]), euro.season),
    })
end

function EuroCup._completeTournament(gameState, euro)
    local fixtures = euro.knockout.final
    if not fixtures then return end

    local finalFixture = nil
    for _, f in ipairs(fixtures) do
        if f.status == "finished" then
            finalFixture = f
            break
        end
    end
    if not finalFixture then return end

    local winner
    if finalFixture.homeGoals > finalFixture.awayGoals then
        winner = finalFixture.homeTeamId
    elseif finalFixture.awayGoals > finalFixture.homeGoals then
        winner = finalFixture.awayTeamId
    else
        winner = finalFixture._penaltyWinner or (Random() < 0.5 and finalFixture.homeTeamId or finalFixture.awayTeamId)
    end

    euro.champion = winner
    euro.phase = Tournament.PHASE_COMPLETED

    local championName = EuroCup._getNationName(winner)
    gameState:addNews({
        category = "euro_news",
        title = string.format("🏆 欧洲杯冠军: %s!", championName),
        body = string.format("%s 赢得了 %d 欧洲杯冠军！", championName, euro.season),
    })

    local playerNation = EuroCup._getPlayerNation(gameState)
    if playerNation and playerNation == winner then
        gameState:sendMessage({
            category = "euro_cup",
            title = "🏆 欧洲杯冠军！！！",
            body = string.format("你带领%s赢得了 %d 欧洲杯！这是欧洲足球的最高荣誉！", championName, euro.season),
            priority = "high",
        })
    end

    RecordsManager.onEuroChampionship(gameState, winner)

    local runnerUp = (winner == finalFixture.homeTeamId) and finalFixture.awayTeamId or finalFixture.homeTeamId
    HistoryManager.recordEuroChampion(gameState, {
        season = euro.season,
        championId = winner,
        championName = championName,
        runnerUpId = runnerUp,
        runnerUpName = EuroCup._getNationName(runnerUp),
    })

    EventBus.emit("euro_cup_completed", winner)

    if gameState.nationalTeamCoach then
        local coachNation = gameState.nationalTeamCoach.nation
        local coachNationName = EuroCup._getNationName(coachNation)
        local isChampion = (coachNation == winner)

        -- 记录玩家执教成绩
        local result = EuroCup._calcCoachResult(euro, coachNation, winner, runnerUp)
        local w, d, l = EuroCup._calcCoachMatchRecord(euro, coachNation)
        HistoryManager.recordNTCoachResult(gameState, {
            season = euro.season,
            competition = "euro",
            nationId = coachNation,
            nationName = coachNationName,
            result = result,
            matchesPlayed = w + d + l,
            wins = w,
            draws = d,
            losses = l,
        })

        gameState:sendMessage({
            category = "national_team",
            title = "国家队任期结束",
            body = isChampion
                and string.format("恭喜！你带领%s夺得欧洲杯冠军！国家队任期已圆满结束，你将回归俱乐部工作。", coachNationName)
                or string.format("欧洲杯已结束，你的%s国家队主教练任期已到期。感谢你的付出，现在将回归俱乐部工作。", coachNationName),
            priority = "high",
        })
        gameState.nationalTeamCoach = nil
        if gameState.currentRole == "national_team" then
            gameState.currentRole = "club"
        end
    end
end

function EuroCup._getSingleLegWinners(euro, phase)
    local fixtures = euro.knockout[phase]
    if not fixtures then return {} end
    local winners = {}
    for _, f in ipairs(fixtures) do
        if f.status == "finished" then
            if f.homeGoals > f.awayGoals then
                table.insert(winners, f.homeTeamId)
            elseif f.awayGoals > f.homeGoals then
                table.insert(winners, f.awayTeamId)
            elseif f._penaltyWinner then
                table.insert(winners, f._penaltyWinner)
            else
                table.insert(winners, Random() < 0.5 and f.homeTeamId or f.awayTeamId)
            end
        end
    end
    return winners
end

------------------------------------------------------
-- 国家队邀请
------------------------------------------------------

function EuroCup._getManagerLeagueNation(gameState)
    local teamId = gameState.playerTeamId
    if not teamId then return nil end
    local _, leagueKey = gameState:getTeamLeague(teamId)
    local LEAGUE_TO_NATION = {
        premier_league = "ENG",
        la_liga = "ESP",
        bundesliga = "GER",
        serie_a = "ITA",
        ligue_1 = "FRA",
        CSL = "CHN",
    }
    return LEAGUE_TO_NATION[leagueKey]
end

function EuroCup._getGroupForNation(nationCode, euro)
    if not euro or not euro.groups then return nil end
    for groupName, group in pairs(euro.groups) do
        for _, code in ipairs(group.teamIds) do
            if code == nationCode then return groupName end
        end
    end
    return nil
end

function EuroCup._checkNationalTeamInvitation(gameState, qualifiedNations, euroYear)
    gameState.nationalTeamCoach = nil

    local manager = gameState:getPlayerManager()
    if not manager then return end

    local rep = manager.reputation or 30
    if rep < NT_REP_THRESHOLD then
        gameState:sendMessage({
            category = "euro_cup",
            title = "欧洲杯即将开幕",
            body = string.format("%d 欧洲杯分组抽签已完成！但目前你的执教声望不够(%d/%d)，未能获得任何国家队邀请。",
                euroYear, math.floor(rep), NT_REP_THRESHOLD),
            priority = "normal",
        })
        return
    end

    local qualifiedSet = {}
    for _, code in ipairs(qualifiedNations) do
        qualifiedSet[code] = true
    end

    local leagueNation = EuroCup._getManagerLeagueNation(gameState)
    local offers, offerSet = {}, {}

    -- 中国队保底邀约（2028+，玩家可直接选择）
    _addGuaranteedChinaOffer(offers, offerSet, qualifiedSet, euroYear)

    if leagueNation and qualifiedSet[leagueNation] then
        table.insert(offers, leagueNation)
        offerSet[leagueNation] = true
    end

    local availableTiers = {}
    for _, threshold in ipairs(REP_TIER_THRESHOLDS) do
        if rep >= threshold.minRep then
            availableTiers = threshold.tiers
            break
        end
    end

    local tierCandidates = {}
    for _, tier in ipairs(availableTiers) do
        local nations = EURO_NATION_TIERS[tier]
        if nations then
            for _, code in ipairs(nations) do
                if qualifiedSet[code] and not offerSet[code] then
                    table.insert(tierCandidates, {code = code, tier = tier})
                end
            end
        end
    end

    for i = #tierCandidates, 2, -1 do
        local j = RandomInt(1, i)
        tierCandidates[i], tierCandidates[j] = tierCandidates[j], tierCandidates[i]
    end

    local MAX_OFFERS = 4
    for _, candidate in ipairs(tierCandidates) do
        if #offers >= MAX_OFFERS then break end
        local baseProb = TIER_PROBABILITY[candidate.tier] or 0.25
        local repBonus = math.min(0.30, (rep - NT_REP_THRESHOLD) / 500)
        local prob = math.min(0.85, baseProb + repBonus)
        if Random() < prob then
            table.insert(offers, candidate.code)
            offerSet[candidate.code] = true
        end
    end

    if #offers == 0 then
        gameState:sendMessage({
            category = "euro_cup",
            title = "欧洲杯抽签揭晓",
            body = string.format("%d 欧洲杯分组抽签已完成。遗憾的是，没有国家队向你发出执教邀请。", euroYear),
            priority = "normal",
        })
        return
    end

    local bodyLines = {
        string.format("%d 欧洲杯分组抽签已完成！\n", euroYear),
        string.format("凭借你的执教声望(%d)，以下国家队向你发出了主教练邀请：\n", math.floor(rep)),
    }
    local actions = {}
    local euro = gameState.euroCup
    for i, code in ipairs(offers) do
        local name = EuroCup._getNationName(code)
        local group = EuroCup._getGroupForNation(code, euro) or "?"
        table.insert(bodyLines, string.format("  %d. %s（%s组）", i, name, group))
        table.insert(actions, {
            label = "执教" .. name,
            actionId = "accept_nt_coach",
            data = { nation = code, competition = "euro" },
        })
    end
    table.insert(bodyLines, "\n选择一支国家队接受邀请，你将负责选拔26人大名单并带队征战欧洲杯。")
    table.insert(actions, { label = "全部婉拒", actionId = "decline_nt_coach", data = { competition = "euro" } })

    gameState._pendingNTCoachOffers = {
        season = gameState.season,
        competition = "euro",
        nations = {},
        offeredDate = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        },
    }
    for _, code in ipairs(offers) do
        table.insert(gameState._pendingNTCoachOffers.nations, code)
    end

    local msg = gameState:sendMessage({
        category = "euro_cup",
        title = "🏆 国家队主教练邀请（欧洲杯）",
        body = table.concat(bodyLines, "\n"),
        priority = "high",
        popup = true,
        actions = actions,
    })
    if msg and gameState._pendingNTCoachOffers then
        gameState._pendingNTCoachOffers.inviteMessageId = msg.id
    end
end

function EuroCup.getGroupStageKickoffDate(euroYear)
    local minMonth, minDay = 12, 99
    for _, entry in ipairs(GROUP_FIXTURES) do
        local month, day = entry[5], entry[6]
        if month < minMonth or (month == minMonth and day < minDay) then
            minMonth, minDay = month, day
        end
    end
    return { year = euroYear, month = minMonth, day = minDay }
end

function EuroCup.daysUntilGroupStageKickoff(gameState)
    if not gameState or not EuroCup.isEuroYear(gameState.season) then
        return nil
    end
    local kickoff = EuroCup.getGroupStageKickoffDate(gameState.season)
    local TransferManager = require("scripts/systems/transfer_manager")
    local days = TransferManager._daysBetween(gameState.date, kickoff)
    return math.max(0, days)
end

function EuroCup.needsSquadConfirmationBlock(gameState)
    local ntCoach = gameState.nationalTeamCoach
    if not ntCoach or ntCoach.squadConfirmed == true then
        return false
    end
    if not EuroCup.isEuroYear(gameState.season) then
        return false
    end
    local days = EuroCup.daysUntilGroupStageKickoff(gameState)
    if days == nil or days > 7 then
        return false
    end
    return true, ntCoach.nation, days
end

function EuroCup._formatDrawResult(euro)
    local lines = {string.format("%d 欧洲杯24队分组:\n", euro.season)}
    local groupNames = {}
    for name in pairs(euro.groups) do table.insert(groupNames, name) end
    table.sort(groupNames)
    for _, name in ipairs(groupNames) do
        table.insert(lines, "【" .. name .. "组】")
        for _, code in ipairs(euro.groups[name].teamIds) do
            table.insert(lines, "  " .. EuroCup._getNationName(code))
        end
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

function EuroCup._formatKnockoutDraw(matchups)
    local lines = {"【淘汰赛对阵】\n"}
    for i, m in ipairs(matchups) do
        table.insert(lines, string.format("%d. %s vs %s", i, EuroCup._getNationName(m[1]), EuroCup._getNationName(m[2])))
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------
-- 执教成绩计算辅助
------------------------------------------------------

--- 计算玩家执教的最终结果字符串
function EuroCup._calcCoachResult(euro, coachNation, winner, runnerUp)
    if coachNation == winner then return "冠军" end
    if coachNation == runnerUp then return "亚军" end

    -- 检查半决赛参与者（四强）
    local sfFixtures = euro.knockout and euro.knockout.sf
    if sfFixtures then
        for _, f in ipairs(sfFixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "四强"
            end
        end
    end

    -- 检查八强赛参与者
    local qfFixtures = euro.knockout and euro.knockout.qf
    if qfFixtures then
        for _, f in ipairs(qfFixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "八强"
            end
        end
    end

    -- 检查十六强参与者
    local r16Fixtures = euro.knockout and euro.knockout.r16
    if r16Fixtures then
        for _, f in ipairs(r16Fixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "十六强"
            end
        end
    end

    return "小组赛出局"
end

--- 计算执教期间的胜/平/负记录
function EuroCup._calcCoachMatchRecord(euro, coachNation)
    local wins, draws, losses = 0, 0, 0

    -- 小组赛
    if euro.groups then
        for _, group in pairs(euro.groups) do
            for _, f in ipairs(group.fixtures or {}) do
                if f.status == "finished" and (f.homeTeamId == coachNation or f.awayTeamId == coachNation) then
                    local isHome = (f.homeTeamId == coachNation)
                    local myGoals = isHome and f.homeGoals or f.awayGoals
                    local opGoals = isHome and f.awayGoals or f.homeGoals
                    if myGoals > opGoals then wins = wins + 1
                    elseif myGoals < opGoals then losses = losses + 1
                    else draws = draws + 1 end
                end
            end
        end
    end

    -- 淘汰赛各轮
    local koPhases = {"r16", "qf", "sf", "final"}
    for _, phase in ipairs(koPhases) do
        local fixtures = euro.knockout and euro.knockout[phase]
        if fixtures then
            for _, f in ipairs(fixtures) do
                if f.status == "finished" and (f.homeTeamId == coachNation or f.awayTeamId == coachNation) then
                    local isHome = (f.homeTeamId == coachNation)
                    local myGoals = isHome and f.homeGoals or f.awayGoals
                    local opGoals = isHome and f.awayGoals or f.homeGoals
                    if myGoals > opGoals then
                        wins = wins + 1
                    elseif myGoals < opGoals then
                        losses = losses + 1
                    else
                        -- 淘汰赛平局，根据点球判断
                        if f._penaltyWinner == coachNation then
                            wins = wins + 1
                        else
                            losses = losses + 1
                        end
                    end
                end
            end
        end
    end

    return wins, draws, losses
end

return EuroCup
