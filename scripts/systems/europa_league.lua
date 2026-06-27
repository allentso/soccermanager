-- systems/europa_league.lua
-- 欧联杯管理（24队小瑞士制联赛阶段 + 附加赛 + 淘汰赛）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local ChampionsLeague = require("scripts/systems/champions_league")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")
local ReputationManager = require("scripts/systems/reputation_manager")
local FinanceManager = require("scripts/systems/finance_manager")

local EuropaLeague = {}

local UEL_SPOTS_PER_LEAGUE = 4
local TOTAL_TEAMS = 24
local NUM_POTS = 3
local TEAMS_PER_POT = 8

local UEL_PRIZE = {
    participation = 4000000,
    directR16     = 2500000,
    playoffWinner = 1500000,
    champion      = 15000000,
    runnerUp      = 8000000,
}

local UEL_SCHEDULE = {
    league_start    = { month = 9, day = 25 },
    playoff_start   = { month = 2, day = 13 },
    r16_start       = { month = 3, day = 6 },
    qf_start        = { month = 4, day = 10 },
    sf_start        = { month = 4, day = 24 },
    final_date      = { month = 5, day = 28 },
}

local CORE_LEAGUE_KEYS = { "EPL", "LaLiga", "SerieA", "Bundesliga", "Ligue1" }

------------------------------------------------------
-- 初始化
------------------------------------------------------

local function _countLeaguePhaseFixturesPerTeam(lp)
    local teamIds = lp.teamIds or {}
    local counts = {}
    for _, tid in ipairs(teamIds) do
        counts[tid] = 0
    end
    for _, f in ipairs(lp.fixtures or {}) do
        counts[f.homeTeamId] = (counts[f.homeTeamId] or 0) + 1
        counts[f.awayTeamId] = (counts[f.awayTeamId] or 0) + 1
    end
    return counts
end

local function _leaguePhaseFixtureCountsValid(lp)
    if not lp then return false end
    local teamIds = lp.teamIds or {}
    if #teamIds == 0 then return false end
    local matchesPerTeam = (#(lp.pots or {}) * (lp.opponentsPerPot or 2))
    if matchesPerTeam == 0 then matchesPerTeam = 6 end
    local expectedTotal = math.floor(#teamIds * matchesPerTeam / 2)
    if #(lp.fixtures or {}) ~= expectedTotal then
        return false
    end
    local counts = _countLeaguePhaseFixturesPerTeam(lp)
    for _, tid in ipairs(teamIds) do
        if (counts[tid] or 0) ~= matchesPerTeam then
            return false
        end
    end
    return true
end

local function _leaguePhaseKickoffDate(uelSeason)
    return League._alignToWeekday({
        year = uelSeason,
        month = UEL_SCHEDULE.league_start.month,
        day = UEL_SCHEDULE.league_start.day,
    }, 4)
end

function EuropaLeague._getUclTeamSet(gameState)
    local set = {}
    local ucl = gameState.championsLeague
    if ucl and ucl.qualifiedTeams then
        for _, tid in ipairs(ucl.qualifiedTeams) do
            set[tid] = true
        end
    end
    return set
end

function EuropaLeague.initialize(gameState)
    local season = gameState.season
    local qualifiedTeams = EuropaLeague._getQualifiedTeams(gameState)

    if #qualifiedTeams < TOTAL_TEAMS then
        qualifiedTeams = EuropaLeague._fillSlots(gameState, qualifiedTeams, TOTAL_TEAMS)
    end
    while #qualifiedTeams > TOTAL_TEAMS do
        table.remove(qualifiedTeams)
    end

    local pots = EuropaLeague._seedIntoPots(gameState, qualifiedTeams)

    local uel = Tournament.new({
        name = "欧洲联赛",
        shortName = "UEL",
        type = "uel",
        season = season,
        qualifiedTeams = qualifiedTeams,
    })

    uel:initLeaguePhase(qualifiedTeams, pots, Tournament.UEL_LEAGUE_PHASE_CONFIG)

    local leagueStart = {
        year = season,
        month = UEL_SCHEDULE.league_start.month,
        day = UEL_SCHEDULE.league_start.day,
    }
    for attempt = 1, 5 do
        uel:drawLeaguePhaseFixtures(leagueStart)
        if _leaguePhaseFixtureCountsValid(uel.leaguePhase) then
            break
        end
        if attempt == 5 then
            log:Write(LOG_ERROR, "[UEL] 联赛阶段赛程生成失败（5次重试后仍异常）")
        end
    end

    gameState.europaLeague = uel

    EuropaLeague._payParticipationBonuses(gameState, qualifiedTeams, season)

    gameState:addNews({
        category = "uel_news",
        title = "欧联杯联赛阶段抽签揭晓",
        body = EuropaLeague._formatLeagueDrawResult(gameState, uel),
    })

    return uel
end

function EuropaLeague._payParticipationBonuses(gameState, teamIds, season)
    gameState._uelFinance = gameState._uelFinance or {}
    if gameState._uelFinance.participationSeason == season then return end
    gameState._uelFinance.participationSeason = season

    for _, tid in ipairs(teamIds or {}) do
        FinanceManager.addIncome(gameState, tid, UEL_PRIZE.participation,
            "欧联杯联赛阶段参赛奖金", "prize")
        if tid == gameState.playerTeamId then
            gameState:sendMessage({
                category = "finance",
                title = "欧联杯参赛奖金",
                body = string.format("球队获得欧联杯联赛阶段参赛奖金 %s。",
                    FinanceManager.formatMoney(UEL_PRIZE.participation)),
                priority = "normal",
            })
        end
    end
end

------------------------------------------------------
-- 存档迁移
------------------------------------------------------

function EuropaLeague.migrateIfNeeded(gameState)
    if gameState.europaLeague then return false end
    if not gameState.leagues then return false end

    EuropaLeague.initialize(gameState)
    print("[EuropaLeague] Migration: initialized UEL for existing save (season " .. tostring(gameState.season) .. ")")

    local currentDate = gameState.date
    local TurnProcessor = require("scripts/core/turn_processor")
    local MatchEngine = require("scripts/match/match_engine")
    local simulatedCount = 0

    for _ = 1, 30 do
        local hasOverdue = false
        local uel = gameState.europaLeague
        if not uel or uel.phase == Tournament.PHASE_COMPLETED then break end

        local overdue = TurnProcessor._collectOverdueContinentalFixtures(uel, currentDate)
        for _, fixture in ipairs(overdue) do
            hasOverdue = true
            fixture._isUEL = true
            local isPlayer = fixture.homeTeamId == gameState.playerTeamId
                or fixture.awayTeamId == gameState.playerTeamId
            if isPlayer and not gameState._cheatAutoPlay then
                fixture._pendingPlayerMatch = true
            else
                local report = MatchEngine.simulate(gameState, fixture)
                if report then
                    TurnProcessor._applyContinentalResult(gameState, uel, fixture, report)
                    simulatedCount = simulatedCount + 1
                end
            end
        end

        EuropaLeague.checkPhaseAdvance(gameState)
        if not hasOverdue then break end
    end

    if simulatedCount > 0 then
        print("[EuropaLeague] Migration: auto-simulated " .. simulatedCount .. " overdue fixtures")
    end
    return true
end

------------------------------------------------------
-- 分档（3档×8队）
------------------------------------------------------

function EuropaLeague._seedIntoPots(gameState, teamIds)
    local sorted = {}
    for _, tid in ipairs(teamIds) do
        local team = gameState.teams[tid]
        table.insert(sorted, { id = tid, rep = team and team.reputation or 0 })
    end
    table.sort(sorted, function(a, b) return a.rep > b.rep end)

    local pots = { {}, {}, {} }
    for i, entry in ipairs(sorted) do
        local potIdx = math.min(NUM_POTS, math.ceil(i / TEAMS_PER_POT))
        table.insert(pots[potIdx], entry.id)
    end
    return pots
end

------------------------------------------------------
-- 资格（排除欧冠球队）
------------------------------------------------------

function EuropaLeague._isLeagueActive(gameState, leagueKey)
    local lg = gameState.leagues and gameState.leagues[leagueKey]
    if lg and (lg.tier or 1) >= 2 then return false end
    return lg ~= nil
end

function EuropaLeague._getQualifiedTeams(gameState)
    local uclSet = EuropaLeague._getUclTeamSet(gameState)
    local qualified = {}
    local qualifiedSet = {}

    local function addTeam(tid)
        if not tid or uclSet[tid] or qualifiedSet[tid] then return end
        if not gameState.teams[tid] then return end
        qualifiedSet[tid] = true
        table.insert(qualified, tid)
    end

    local lastSeason = nil
    for _, record in ipairs(gameState.worldHistory or {}) do
        if record.season == gameState.season - 1 then
            lastSeason = record
            break
        end
    end

    if lastSeason and lastSeason.leagues then
        local uclSpots = ChampionsLeague.getUclSpots(gameState)
        for _, leagueKey in ipairs(CORE_LEAGUE_KEYS) do
            if not EuropaLeague._isLeagueActive(gameState, leagueKey) then
                goto continue_hist
            end
            local leagueRecord = lastSeason.leagues[leagueKey]
            local uclCount = uclSpots[leagueKey] or 0
            if leagueRecord and leagueRecord.standings then
                for i = uclCount + 1, uclCount + UEL_SPOTS_PER_LEAGUE do
                    local entry = leagueRecord.standings[i]
                    if entry then addTeam(entry.teamId) end
                end
            end
            ::continue_hist::
        end
    else
        for _, leagueKey in ipairs(CORE_LEAGUE_KEYS) do
            if not EuropaLeague._isLeagueActive(gameState, leagueKey) then
                goto continue_init
            end
            local lg = gameState.leagues[leagueKey]
            local uclSpots = ChampionsLeague.getUclSpots(gameState)
            local uclCount = uclSpots[leagueKey] or 0
            if lg then
                local leagueTeams = {}
                for _, tid in ipairs(lg.teamIds) do
                    local team = gameState.teams[tid]
                    if team and not uclSet[tid] then
                        table.insert(leagueTeams, team)
                    end
                end
                table.sort(leagueTeams, function(a, b)
                    return (a.reputation or 0) > (b.reputation or 0)
                end)
                for i = 1, math.min(UEL_SPOTS_PER_LEAGUE, #leagueTeams) do
                    addTeam(leagueTeams[i].id)
                end
            end
            ::continue_init::
        end
    end

    return qualified
end

function EuropaLeague._fillSlots(gameState, existing, target)
    local uclSet = EuropaLeague._getUclTeamSet(gameState)
    local existingSet = {}
    for _, tid in ipairs(existing) do existingSet[tid] = true end

    local candidates = {}
    for leagueKey, lg in pairs(gameState.leagues) do
        if not EuropaLeague._isLeagueActive(gameState, leagueKey) then
            goto continue_fill
        end
        for _, tid in ipairs(lg.teamIds) do
            if not existingSet[tid] and not uclSet[tid] then
                local team = gameState.teams[tid]
                if team then table.insert(candidates, team) end
            end
        end
        ::continue_fill::
    end
    table.sort(candidates, function(a, b)
        return (a.reputation or 0) > (b.reputation or 0)
    end)

    local result = {}
    for _, tid in ipairs(existing) do table.insert(result, tid) end
    for _, team in ipairs(candidates) do
        if #result >= target then break end
        table.insert(result, team.id)
    end
    return result
end

------------------------------------------------------
-- 阶段推进
------------------------------------------------------

function EuropaLeague.checkPhaseAdvance(gameState)
    local uel = gameState.europaLeague
    if not uel or uel.phase == Tournament.PHASE_COMPLETED then return end

    if uel.phase == Tournament.PHASE_LEAGUE and uel:isLeaguePhaseComplete() then
        EuropaLeague._advanceToPlayoff(gameState, uel)
    end
    if uel.phase == Tournament.PHASE_PLAYOFF and uel:isKnockoutRoundComplete("playoff") then
        EuropaLeague._advanceToR16(gameState, uel)
    end
    if uel.phase == Tournament.PHASE_R16 and uel:isKnockoutRoundComplete("r16") then
        EuropaLeague._advanceToQF(gameState, uel)
    end
    if uel.phase == Tournament.PHASE_QF and uel:isKnockoutRoundComplete("qf") then
        EuropaLeague._advanceToSF(gameState, uel)
    end
    if uel.phase == Tournament.PHASE_SF and uel:isKnockoutRoundComplete("sf") then
        EuropaLeague._advanceToFinal(gameState, uel)
    end
    if uel.phase == Tournament.PHASE_FINAL and uel:isKnockoutRoundComplete("final") then
        EuropaLeague._completeTournament(gameState, uel)
    end
end

function EuropaLeague._advanceToPlayoff(gameState, uel)
    local directR16, playoffTeams = uel:getLeaguePhaseAdvancers()
    uel._directR16 = directR16

    local matchups = {}
    for i = 1, 8 do
        local highSeed = playoffTeams[i]
        local lowSeed = playoffTeams[17 - i]
        if highSeed and lowSeed then
            table.insert(matchups, { lowSeed, highSeed })
        end
    end

    local startDate = {
        year = gameState.season + 1,
        month = UEL_SCHEDULE.playoff_start.month,
        day = UEL_SCHEDULE.playoff_start.day,
    }
    uel:generateKnockoutRound("playoff", matchups, startDate)

    if not uel._leagueAdvanceBonusesPaid then
        uel._leagueAdvanceBonusesPaid = true
        for _, tid in ipairs(directR16) do
            FinanceManager.addIncome(gameState, tid, UEL_PRIZE.directR16,
                "欧联杯直通16强奖金", "prize")
        end
    end

    gameState:addNews({
        category = "uel_news",
        title = "欧联杯联赛阶段结束！附加赛对阵出炉",
        body = EuropaLeague._formatPlayoffNews(gameState, directR16, matchups),
    })
end

function EuropaLeague._advanceToR16(gameState, uel)
    local playoffWinners = uel:getKnockoutWinners("playoff")
    local directR16 = uel._directR16 or {}

    local seeds = {}
    for _, tid in ipairs(directR16) do table.insert(seeds, tid) end

    local unseeded = {}
    for _, tid in ipairs(playoffWinners) do table.insert(unseeded, tid) end
    for i = #unseeded, 2, -1 do
        local j = RandomInt(1, i)
        unseeded[i], unseeded[j] = unseeded[j], unseeded[i]
    end

    local matchups = {}
    for i = 1, math.min(#seeds, #unseeded) do
        table.insert(matchups, { unseeded[i], seeds[i] })
    end

    local startDate = {
        year = gameState.season + 1,
        month = UEL_SCHEDULE.r16_start.month,
        day = UEL_SCHEDULE.r16_start.day,
    }
    uel:generateKnockoutRound("r16", matchups, startDate)

    if not uel._playoffBonusesPaid then
        uel._playoffBonusesPaid = true
        for _, tid in ipairs(playoffWinners) do
            FinanceManager.addIncome(gameState, tid, UEL_PRIZE.playoffWinner,
                "欧联杯附加赛晋级奖金", "prize")
        end
    end

    gameState:addNews({
        category = "uel_news",
        title = "欧联杯16强对阵出炉",
        body = EuropaLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function EuropaLeague._advanceToQF(gameState, uel)
    local winners = uel:getKnockoutWinners("r16")
    if #winners < 2 then return end
    for i = #winners, 2, -1 do
        local j = RandomInt(1, i)
        winners[i], winners[j] = winners[j], winners[i]
    end
    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, { winners[i], winners[i + 1] })
        end
    end
    local startDate = {
        year = gameState.season + 1,
        month = UEL_SCHEDULE.qf_start.month,
        day = UEL_SCHEDULE.qf_start.day,
    }
    uel:generateKnockoutRound("qf", matchups, startDate)
    gameState:addNews({
        category = "uel_news",
        title = "欧联杯8强对阵抽签",
        body = EuropaLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function EuropaLeague._advanceToSF(gameState, uel)
    local winners = uel:getKnockoutWinners("qf")
    if #winners < 2 then return end
    for i = #winners, 2, -1 do
        local j = RandomInt(1, i)
        winners[i], winners[j] = winners[j], winners[i]
    end
    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, { winners[i], winners[i + 1] })
        end
    end
    local startDate = {
        year = gameState.season + 1,
        month = UEL_SCHEDULE.sf_start.month,
        day = UEL_SCHEDULE.sf_start.day,
    }
    uel:generateKnockoutRound("sf", matchups, startDate)
    gameState:addNews({
        category = "uel_news",
        title = "欧联杯4强对阵确定",
        body = EuropaLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function EuropaLeague._advanceToFinal(gameState, uel)
    local winners = uel:getKnockoutWinners("sf")
    if #winners < 2 then return end

    local finalDate = {
        year = gameState.season + 1,
        month = UEL_SCHEDULE.final_date.month,
        day = UEL_SCHEDULE.final_date.day,
    }
    uel:generateFinal({ winners[1], winners[2] }, finalDate)

    local team1 = gameState.teams[winners[1]]
    local team2 = gameState.teams[winners[2]]
    gameState:addNews({
        category = "uel_news",
        title = "欧联杯决赛对阵确定！",
        body = string.format("%s vs %s\n决赛日期: %d年%d月%d日",
            team1 and team1.name or "?",
            team2 and team2.name or "?",
            finalDate.year, finalDate.month, finalDate.day),
    })
end

function EuropaLeague._completeTournament(gameState, uel)
    local winners = uel:getKnockoutWinners("final")
    if #winners == 0 then return end

    uel.champion = winners[1]
    uel.phase = Tournament.PHASE_COMPLETED

    local champion = gameState.teams[uel.champion]
    gameState:addNews({
        category = "uel_news",
        title = string.format("%s 赢得欧联杯冠军!", champion and champion.name or "?"),
        body = string.format("%s 在 %d-%d 赛季欧洲联赛中夺冠！",
            champion and champion.name or "?", uel.season, uel.season + 1),
    })

    if champion then
        FinanceManager.addIncome(gameState, champion.id, UEL_PRIZE.champion,
            "欧联杯冠军奖金", "prize")
    end

    if uel.champion == gameState.playerTeamId then
        gameState:sendMessage({
            category = "league",
            title = "恭喜！欧联杯冠军！",
            body = string.format("你的球队赢得了欧洲联赛！\n冠军奖金 %s 已到账。",
                FinanceManager.formatMoney(UEL_PRIZE.champion)),
            priority = "high",
        })
    end

    ReputationManager.cupResultUpdate(gameState, uel.champion, true)

    local finalFixture = uel.knockout.final and uel.knockout.final[1]
    if finalFixture then
        local finalistId = (finalFixture.homeTeamId == uel.champion)
            and finalFixture.awayTeamId or finalFixture.homeTeamId
        uel.finalist = finalistId
        local finalist = gameState.teams[finalistId]
        if finalist then
            FinanceManager.addIncome(gameState, finalistId, UEL_PRIZE.runnerUp,
                "欧联杯亚军奖金", "prize")
        end
        ReputationManager.cupResultUpdate(gameState, finalistId, false)
        if finalistId == gameState.playerTeamId then
            gameState:sendMessage({
                category = "league",
                title = "欧联杯决赛惜败",
                body = string.format("你的球队在欧联杯决赛中惜败，获得亚军。\n亚军奖金 %s 已到账。",
                    FinanceManager.formatMoney(UEL_PRIZE.runnerUp)),
                priority = "high",
            })
        end
    end

    RecordsManager.onUELChampionship(gameState, uel.champion)

    gameState._uelCompletedSeasons = gameState._uelCompletedSeasons or {}
    gameState._uelCompletedSeasons[tostring(uel.season)] = uel.champion

    EventBus.emit("uel_completed", uel.champion)
end

------------------------------------------------------
-- 新闻格式化
------------------------------------------------------

function EuropaLeague._formatLeagueDrawResult(gameState, uel)
    local lp = uel.leaguePhase
    if not lp then return "抽签完成" end

    local lines = { "欧联杯联赛阶段（24队瑞士制）:\n" }
    local potNames = { "第一档", "第二档", "第三档" }

    for i, pot in ipairs(lp.pots) do
        table.insert(lines, "【" .. (potNames[i] or ("第" .. i .. "档")) .. "】")
        local names = {}
        for _, tid in ipairs(pot) do
            local team = gameState.teams[tid]
            table.insert(names, team and team.name or "?")
        end
        table.insert(lines, "  " .. table.concat(names, "、"))
        table.insert(lines, "")
    end

    table.insert(lines, "每队将进行6场比赛（3主3客），争夺24队单一积分榜排名。")
    table.insert(lines, "前8名直接晋级16强，9-24名进入附加赛。")
    return table.concat(lines, "\n")
end

function EuropaLeague._formatPlayoffNews(gameState, directR16, matchups)
    local lines = { "直接晋级16强:" }
    for i, tid in ipairs(directR16) do
        local team = gameState.teams[tid]
        table.insert(lines, string.format("  %d. %s", i, team and team.name or "?"))
    end
    table.insert(lines, "\n附加赛对阵:")
    for i, m in ipairs(matchups) do
        local t1 = gameState.teams[m[1]]
        local t2 = gameState.teams[m[2]]
        table.insert(lines, string.format("  %d. %s vs %s", i, t1 and t1.name or "?", t2 and t2.name or "?"))
    end
    return table.concat(lines, "\n")
end

function EuropaLeague._formatKnockoutDraw(gameState, matchups)
    local lines = {}
    for i, m in ipairs(matchups) do
        local t1 = gameState.teams[m[1]]
        local t2 = gameState.teams[m[2]]
        table.insert(lines, string.format("%d. %s vs %s",
            i, t1 and t1.name or "?", t2 and t2.name or "?"))
    end
    return table.concat(lines, "\n")
end

return EuropaLeague
