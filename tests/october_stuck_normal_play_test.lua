-- tests/october_stuck_normal_play_test.lua
-- 模拟正常玩法（非autoplay）来复现卡死问题
-- 直接使用游戏现有接口: Dashboard._findNextMatch + TurnProcessor.advanceDay

require("tests/bootstrap")
SetTestRandomSeed(42)

local GameState = require("scripts/core/game_state")
local League = require("scripts/domain/league")
local TurnProcessor = require("scripts/core/turn_processor")
local SeasonManager = require("scripts/systems/season_manager")
local EventBus = require("scripts/app/event_bus")
local ChampionsLeague = require("scripts/systems/champions_league")
local WorldCup = require("scripts/systems/world_cup")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local Constants = require("scripts/app/constants")
local TrainingManager = require("scripts/systems/training_manager")
local YouthManager = require("scripts/systems/youth_manager")
local PotentialSystem = require("scripts/systems/potential_system")
local MatchEngine = require("scripts/match/match_engine")
local Dashboard = require("scripts/ui/screens/dashboard")

------------------------------------------------------
-- 辅助：构建 20 队游戏状态（复用 bootstrap 逻辑）
------------------------------------------------------

local function attributes(value)
    return {
        speed = value, stamina = value, strength = value, agility = value,
        passing = value, shooting = value, tackling = value, dribbling = value,
        defending = value, positioning = value, vision = value, decisions = value,
        composure = value, aggression = 10, teamwork = value, leadership = value,
        handling = value, reflexes = value, aerial = value,
    }
end

local function populateTeam(gameState, team, ability)
    local positions = { "GK", "LB", "CB", "CB", "RB", "CM", "CM", "CM", "LM", "RM", "ST",
                        "GK", "LB", "CB", "RB", "CM", "CM", "LM", "ST" }
    local teamRep = team.reputation or 50
    local overallBase = math.floor(teamRep * 0.9) + RandomInt(-5, 5)
    overallBase = math.max(35, math.min(90, overallBase))
    for i, position in ipairs(positions) do
        local playerOverall = overallBase + RandomInt(-5, 5)
        playerOverall = math.max(30, math.min(92, playerOverall))
        local wage = math.floor(playerOverall * playerOverall * 2 + RandomInt(500, 2000))
        local player = gameState:addPlayer({
            firstName = team.shortName, lastName = position .. i,
            displayName = team.shortName .. " " .. position .. i,
            birthYear = 1995 + RandomInt(0, 8), nationality = "ENG",
            position = position, attributes = attributes(ability + RandomInt(-3, 3)),
            overall = playerOverall, fitness = 85 + RandomInt(0, 10),
            morale = 65 + RandomInt(0, 15), wage = wage, teamId = team.id,
            contractEnd = { year = 2030, month = 6 },
        })
        team:addPlayer(player.id)
        if i <= 11 then table.insert(team.startingXI, player.id) end
    end
end

local function createLeague(gameState, leagueKey, leagueName, teamCount, baseAbility, country)
    local teamIds = {}
    local repTiers = { 95, 90, 85, 80, 75, 70, 65, 60, 55, 50, 48, 45, 42, 40, 38, 35, 33, 30, 28, 25 }
    local balanceTiers = {
        200000000, 180000000, 160000000, 140000000, 120000000,
        100000000, 85000000, 70000000, 60000000, 50000000,
        45000000, 40000000, 35000000, 30000000, 25000000,
        22000000, 20000000, 18000000, 15000000, 12000000,
    }
    for i = 1, teamCount do
        local repIdx = math.min(i, #repTiers)
        local team = gameState:addTeam({
            name = leagueName .. " Team " .. i, shortName = leagueKey .. i,
            formation = "4-4-2", playStyle = (i % 2 == 0) and "Attacking" or "Defensive",
            balance = balanceTiers[repIdx] or 10000000, wageBudget = 50000,
            stadiumCapacity = 40000 + RandomInt(-10000, 20000),
            country = country, reputation = repTiers[repIdx] or 25,
        })
        populateTeam(gameState, team, baseAbility + RandomInt(-2, 2))
        table.insert(teamIds, team.id)
    end
    local league = League.new({
        id = gameState:generateId(), name = leagueName, country = country,
        teamIds = teamIds, fixtures = {},
    })
    league:initStandings()
    gameState.leagues[leagueKey] = league
    return league, teamIds
end

local function buildFullGameState()
    local gs = GameState.new()
    gs.date = { year = 2026, month = 8, day = 10 }
    gs.season = 2026
    gs.dayOfWeek = 1
    gs._cheatAutoPlay = false  -- !! 正常玩法模式

    local leagues = {
        { key = "EPL", name = "英超", ability = 16, country = "ENG" },
        { key = "LaLiga", name = "西甲", ability = 15, country = "ESP" },
        { key = "SerieA", name = "意甲", ability = 15, country = "ITA" },
        { key = "Bundesliga", name = "德甲", ability = 14, country = "GER" },
        { key = "Ligue1", name = "法甲", ability = 13, country = "FRA" },
    }
    for _, info in ipairs(leagues) do
        createLeague(gs, info.key, info.name, 20, info.ability, info.country)
    end

    local playerLeague = gs.leagues["EPL"]
    gs.playerTeamId = playerLeague.teamIds[1]
    gs.league = playerLeague
    gs.playerLeagueId = "EPL"

    local leagueStartDate = { year = gs.season, month = Constants.SEASON_START_MONTH, day = Constants.SEASON_START_DAY }
    for _, lg in pairs(gs.leagues) do
        lg.season = gs.season
        lg.currentRound = 1
        lg:generateFixtures(leagueStartDate)
    end
    ChampionsLeague.initialize(gs)
    WorldCup.initialize(gs)
    ObjectivesManager.initSeason(gs)
    return gs
end

------------------------------------------------------
-- 模拟"玩家打比赛"：当 advanceDay 返回 _pendingPlayerMatch 时
-- 玩家会进 pre_match → match_live → 结算，等价于直接模拟
------------------------------------------------------
local function playPendingMatches(gs)
    local played = 0
    -- 联赛
    for _, lg in pairs(gs.leagues or {}) do
        for _, f in ipairs(lg.fixtures or {}) do
            if f._pendingPlayerMatch and f.status == "scheduled" then
                local report = MatchEngine.simulate(gs, f)
                if report then MatchEngine.applyResult(gs, f, report) end
                f._pendingPlayerMatch = nil
                played = played + 1
            end
        end
    end
    -- UCL
    local ucl = gs.championsLeague
    if ucl then
        if ucl.leaguePhase and ucl.leaguePhase.fixtures then
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f._pendingPlayerMatch and f.status == "scheduled" then
                    local report = MatchEngine.simulate(gs, f)
                    if report then TurnProcessor._applyUCLResult(gs, f, report) end
                    f._pendingPlayerMatch = nil
                    played = played + 1
                end
            end
        end
        if ucl.knockout then
            for _, phase in ipairs({"playoff", "r16", "qf", "sf", "final"}) do
                local fixtures = ucl.knockout[phase]
                if fixtures then
                    for _, f in ipairs(fixtures) do
                        if f._pendingPlayerMatch and f.status == "scheduled" then
                            local report = MatchEngine.simulate(gs, f)
                            if report then TurnProcessor._applyUCLResult(gs, f, report) end
                            f._pendingPlayerMatch = nil
                            played = played + 1
                        end
                    end
                end
            end
        end
    end
    -- WC（简化）
    local wc = gs.worldCup
    if wc and wc.phase ~= "not_started" and wc.phase ~= "completed" then
        if wc.phase == "group" then
            for _, group in pairs(wc.groups or {}) do
                for _, f in ipairs(group.fixtures or {}) do
                    if f._pendingPlayerMatch and f.status == "scheduled" then
                        local report = TurnProcessor._simulateWCMatch(gs, f)
                        if report then TurnProcessor._applyWCResult(gs, f, report) end
                        f._pendingPlayerMatch = nil
                        played = played + 1
                    end
                end
            end
        end
        if wc.knockout then
            for _, phase in ipairs({"r16", "qf", "sf", "third", "final"}) do
                local fixtures = wc.knockout[phase]
                if fixtures then
                    for _, f in ipairs(fixtures) do
                        if f._pendingPlayerMatch and f.status == "scheduled" then
                            local report = TurnProcessor._simulateWCMatch(gs, f)
                            if report then TurnProcessor._applyWCResult(gs, f, report) end
                            f._pendingPlayerMatch = nil
                            played = played + 1
                        end
                    end
                end
            end
        end
    end
    return played
end

------------------------------------------------------
-- 赛季结束事件处理
------------------------------------------------------
local seasonEndCount = 0
EventBus.on("season_end", function()
    seasonEndCount = seasonEndCount + 1
    local gs = _G.gameState
    if gs then SeasonManager.endSeason(gs) end
end)

------------------------------------------------------
-- 执行模拟
------------------------------------------------------
print("=== 正常玩法模式 卡死测试 (使用 Dashboard._findNextMatch) ===")
print("")

local gs = buildFullGameState()
_G.gameState = gs

print(string.format("英超: %d队, %d场", #gs.league.teamIds, #gs.league.fixtures))
print(string.format("初始: %d/%d/%d, 赛季=%d", gs.date.year, gs.date.month, gs.date.day, gs.season))
print("")

local totalDays = 0
local maxDays = 1200
local TARGET_DATE = { year = 2027, month = 11, day = 1 }
local matchesPlayed = 0
local noMatchStreak = 0
local lastMonth = gs.date.month

local function isPastTarget(date)
    if date.year > TARGET_DATE.year then return true end
    if date.year == TARGET_DATE.year then
        if date.month > TARGET_DATE.month then return true end
        if date.month == TARGET_DATE.month and date.day >= TARGET_DATE.day then return true end
    end
    return false
end

while not isPastTarget(gs.date) and totalDays < maxDays do
    -- ★ 使用游戏真实接口查找下一场比赛
    local daysToMatch, nextFixture, isUCL, isWC = Dashboard._findNextMatch(gs)

    if not nextFixture then
        -- 找不到比赛 → 模拟 doSkipToMatchDay: maxSkip = max(0,1) = 1
        noMatchStreak = noMatchStreak + 1
        local prevSeason = gs.season
        TurnProcessor.advanceDay(gs)
        totalDays = totalDays + 1
        matchesPlayed = matchesPlayed + playPendingMatches(gs)

        if gs.season ~= prevSeason then noMatchStreak = 0 end
    else
        -- 找到比赛 → 模拟 doSkipToMatchDay: 推进 daysToMatch 天
        if noMatchStreak > 5 then
            print(string.format("  [恢复] %d天无比赛后 @ %d/%d/%d", noMatchStreak, gs.date.year, gs.date.month, gs.date.day))
        end
        noMatchStreak = 0

        local skipDays = math.max(daysToMatch, 1)
        -- 如果 daysToMatch == 0 表示今天就有比赛（逾期或当天），也需要推进一天让 advanceDay 触发
        if daysToMatch == 0 then
            -- 当天比赛：直接"打"掉它（如果是逾期的 _pendingPlayerMatch）
            if nextFixture._pendingPlayerMatch or nextFixture.status == "scheduled" then
                -- 模拟玩家打这场比赛
                if nextFixture._isWC then
                    local report = TurnProcessor._simulateWCMatch(gs, nextFixture)
                    if report then TurnProcessor._applyWCResult(gs, nextFixture, report) end
                elseif nextFixture._isUCL or isUCL then
                    local report = MatchEngine.simulate(gs, nextFixture)
                    if report then TurnProcessor._applyUCLResult(gs, nextFixture, report) end
                else
                    local report = MatchEngine.simulate(gs, nextFixture)
                    if report then MatchEngine.applyResult(gs, nextFixture, report) end
                end
                nextFixture._pendingPlayerMatch = nil
                matchesPlayed = matchesPlayed + 1
            end
            -- 不推进日期（和真实 doAdvanceDay 一样：daysToMatch==0 直接进比赛）
            -- 但如果比赛打完了，后面再循环就会找到下一场
            goto continue_loop
        end

        -- 正常跳天
        local prevSeason = gs.season
        for i = 1, skipDays do
            TurnProcessor.advanceDay(gs)
            totalDays = totalDays + 1
            matchesPlayed = matchesPlayed + playPendingMatches(gs)
            if gs.season ~= prevSeason then break end
        end
    end

    ::continue_loop::

    -- 月度报告
    if gs.date.month ~= lastMonth then
        lastMonth = gs.date.month
        if (gs.date.year == 2027 and gs.date.month >= 4) or gs.date.year > 2027 then
            local uclPhase = gs.championsLeague and gs.championsLeague.phase or "nil"
            local leagueFinished = 0
            for _, f in ipairs(gs.league.fixtures) do
                if f.status == "finished" then leagueFinished = leagueFinished + 1 end
            end
            print(string.format("  [%d/%d/%d] league=%d/%d UCL=%s season=%d streak=%d days=%d",
                gs.date.year, gs.date.month, gs.date.day,
                leagueFinished, #gs.league.fixtures, uclPhase,
                gs.season, noMatchStreak, totalDays))
        end
    end

    -- 卡死检测
    if noMatchStreak > 30 then
        print(string.format("\n!!! 卡死: 连续 %d 天找不到比赛 !!!", noMatchStreak))
        print(string.format("  日期: %d/%d/%d, 赛季: %d, 总天数: %d", gs.date.year, gs.date.month, gs.date.day, gs.season, totalDays))

        local uclPhase = gs.championsLeague and gs.championsLeague.phase or "nil"
        local leagueFinished, leagueScheduled = 0, 0
        for _, f in ipairs(gs.league.fixtures) do
            if f.status == "finished" then leagueFinished = leagueFinished + 1 end
            if f.status == "scheduled" then leagueScheduled = leagueScheduled + 1 end
        end
        print(string.format("  联赛: finished=%d scheduled=%d total=%d", leagueFinished, leagueScheduled, #gs.league.fixtures))
        print(string.format("  UCL phase: %s", uclPhase))

        -- UCL 剩余比赛
        local ucl = gs.championsLeague
        if ucl and ucl.knockout then
            for _, phase in ipairs({"playoff", "r16", "qf", "sf", "final"}) do
                local fixtures = ucl.knockout[phase]
                if fixtures then
                    local sched, fin = 0, 0
                    for _, f in ipairs(fixtures) do
                        if f.status == "scheduled" then sched = sched + 1 end
                        if f.status == "finished" then fin = fin + 1 end
                    end
                    if sched > 0 then
                        print(string.format("    UCL %s: scheduled=%d finished=%d", phase, sched, fin))
                        -- 打印前2场 scheduled 的日期
                        local shown = 0
                        for _, f in ipairs(fixtures) do
                            if f.status == "scheduled" and shown < 2 then
                                print(string.format("      -> %s vs %s @ %d/%d/%d",
                                    tostring(f.homeTeamId), tostring(f.awayTeamId),
                                    f.date.year, f.date.month, f.date.day))
                                shown = shown + 1
                            end
                        end
                    end
                end
            end
        end

        -- overdue check
        local overdue = TurnProcessor.peekOverduePlayerFixture(gs)
        print(string.format("  peekOverdue: %s", overdue and string.format("yes @ %d/%d/%d", overdue.date.year, overdue.date.month, overdue.date.day) or "nil"))
        print(string.format("  _seasonEndProcessing: %s", tostring(gs._seasonEndProcessing)))

        error("卡死! 连续" .. noMatchStreak .. "天 Dashboard._findNextMatch 返回 nil")
    end
end

------------------------------------------------------
-- 结果
------------------------------------------------------
print("")
print("=== 测试完成 ===")
print(string.format("总天数: %d, 最终: %d/%d/%d, 赛季: %d", totalDays, gs.date.year, gs.date.month, gs.date.day, gs.season))
print(string.format("玩家比赛: %d, 赛季结束: %d", matchesPlayed, seasonEndCount))

if isPastTarget(gs.date) then
    print("\n✅ 成功模拟到2027年11月")
else
    print("\n❌ 未能到达目标日期")
end
