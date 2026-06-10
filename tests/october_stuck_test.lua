-- tests/october_stuck_test.lua
-- 复现问题：使用20队联赛模拟到2027年10月，检测卡死原因
-- 关键差异：原测试用10队(18轮)，实际游戏用20队(38轮)

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

------------------------------------------------------
-- 辅助函数
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
            firstName = team.shortName,
            lastName = position .. i,
            displayName = team.shortName .. " " .. position .. i,
            birthYear = 1995 + RandomInt(0, 8),
            nationality = "ENG",
            position = position,
            attributes = attributes(ability + RandomInt(-3, 3)),
            overall = playerOverall,
            fitness = 85 + RandomInt(0, 10),
            morale = 65 + RandomInt(0, 15),
            wage = wage,
            teamId = team.id,
            contractEnd = { year = 2030, month = 6 },
        })
        team:addPlayer(player.id)
        if i <= 11 then
            table.insert(team.startingXI, player.id)
        end
    end
end

local function createLeague(gameState, leagueKey, leagueName, teamCount, baseAbility, country)
    local teamIds = {}
    -- 20队声望分层
    local repTiers = {
        95, 90, 85, 80, 75, 70, 65, 60, 55, 50,
        48, 45, 42, 40, 38, 35, 33, 30, 28, 25,
    }
    local balanceTiers = {
        200000000, 180000000, 160000000, 140000000, 120000000,
        100000000, 85000000, 70000000, 60000000, 50000000,
        45000000, 40000000, 35000000, 30000000, 25000000,
        22000000, 20000000, 18000000, 15000000, 12000000,
    }
    for i = 1, teamCount do
        local repIdx = math.min(i, #repTiers)
        local team = gameState:addTeam({
            name = leagueName .. " Team " .. i,
            shortName = leagueKey .. i,
            formation = "4-4-2",
            playStyle = (i % 2 == 0) and "Attacking" or "Defensive",
            balance = balanceTiers[repIdx] or 10000000,
            wageBudget = 50000,
            stadiumCapacity = 40000 + RandomInt(-10000, 20000),
            country = country,
            reputation = repTiers[repIdx] or 25,
        })
        populateTeam(gameState, team, baseAbility + RandomInt(-2, 2))
        table.insert(teamIds, team.id)
    end

    local league = League.new({
        id = gameState:generateId(),
        name = leagueName,
        country = country,
        teamIds = teamIds,
        fixtures = {},
    })
    league:initStandings()
    gameState.leagues[leagueKey] = league

    return league, teamIds
end

------------------------------------------------------
-- 构建完整游戏状态（5联赛，20队/联赛 - 匹配真实游戏）
------------------------------------------------------

local function buildFullGameState()
    local gs = GameState.new()
    gs.date = { year = 2026, month = 8, day = 10 }
    gs.season = 2026
    gs.dayOfWeek = 1
    gs._cheatAutoPlay = true  -- 跳过 UI 导航，纯模拟

    -- 创建5大联赛（每个20队 - 匹配真实数据！）
    local leagues = {
        { key = "EPL", name = "英超", ability = 16, country = "ENG" },
        { key = "LaLiga", name = "西甲", ability = 15, country = "ESP" },
        { key = "SerieA", name = "意甲", ability = 15, country = "ITA" },
        { key = "Bundesliga", name = "德甲", ability = 14, country = "GER" },
        { key = "Ligue1", name = "法甲", ability = 13, country = "FRA" },
    }

    for _, leagueInfo in ipairs(leagues) do
        createLeague(gs, leagueInfo.key, leagueInfo.name, 20, leagueInfo.ability, leagueInfo.country)
    end

    -- 设定玩家球队（英超第一支）
    local playerLeague = gs.leagues["EPL"]
    gs.playerTeamId = playerLeague.teamIds[1]
    gs.league = playerLeague
    gs.playerLeagueId = "EPL"

    -- 生成赛程（从当前日期开始）
    local leagueStartDate = { year = gs.season, month = Constants.SEASON_START_MONTH, day = Constants.SEASON_START_DAY }
    for _, lg in pairs(gs.leagues) do
        lg.season = gs.season
        lg.currentRound = 1
        lg:generateFixtures(leagueStartDate)
    end

    -- 初始化欧冠
    ChampionsLeague.initialize(gs)

    -- 初始化世界杯（2026是世界杯年）
    WorldCup.initialize(gs)

    -- 初始化目标系统
    ObjectivesManager.initSeason(gs)

    return gs
end

------------------------------------------------------
-- 注册 season_end 事件
------------------------------------------------------

local seasonEndCount = 0

EventBus.on("season_end", function()
    seasonEndCount = seasonEndCount + 1
    local gs = _G.gameState
    if gs then
        SeasonManager.endSeason(gs)
    end
end)

------------------------------------------------------
-- 诊断函数
------------------------------------------------------

local function getLeagueStatus(gs)
    if not gs.league then return "NO LEAGUE" end
    local scheduled, finished = 0, 0
    for _, f in ipairs(gs.league.fixtures) do
        if f.status == "scheduled" then scheduled = scheduled + 1
        elseif f.status == "finished" then finished = finished + 1 end
    end
    return string.format("finished=%d/scheduled=%d/total=%d", finished, scheduled, #gs.league.fixtures)
end

local function getUCLStatus(gs)
    local ucl = gs.championsLeague
    if not ucl then return "NO UCL" end
    local phase = ucl.phase or "?"
    local lpFinished, lpScheduled = 0, 0
    if ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            if f.status == "finished" then lpFinished = lpFinished + 1
            elseif f.status == "scheduled" then lpScheduled = lpScheduled + 1 end
        end
    end
    return string.format("phase=%s, lp_finished=%d/lp_sched=%d", phase, lpFinished, lpScheduled)
end

local function getWCStatus(gs)
    local wc = gs.worldCup
    if not wc then return "NO WC" end
    return string.format("phase=%s", wc.phase or "?")
end

local function getPlayerNextMatch(gs)
    local playerTeamId = gs.playerTeamId
    -- 联赛
    for _, f in ipairs(gs.league.fixtures) do
        if f.status == "scheduled" and (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId) then
            return string.format("League R%d @ %d/%d/%d", f.round, f.date.year, f.date.month, f.date.day)
        end
    end
    -- UCL
    local ucl = gs.championsLeague
    if ucl and ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            if f.status == "scheduled" and (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId) then
                return string.format("UCL MD%d @ %d/%d/%d", f.matchday or 0, f.date.year, f.date.month, f.date.day)
            end
        end
    end
    return "NONE FOUND"
end

-- 检测是否有逾期未完成的比赛
local function checkOverdueFixtures(gs)
    local currentDate = gs.date
    local playerTeamId = gs.playerTeamId
    local overdueCount = 0
    local playerOverdue = {}

    -- 联赛逾期
    for _, lg in pairs(gs.leagues or {}) do
        for _, f in ipairs(lg.fixtures or {}) do
            if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                overdueCount = overdueCount + 1
                if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                    table.insert(playerOverdue, string.format("League R%d @ %d/%d/%d", f.round, f.date.year, f.date.month, f.date.day))
                end
            end
        end
    end

    -- UCL逾期
    local ucl = gs.championsLeague
    if ucl and ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                overdueCount = overdueCount + 1
                if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                    table.insert(playerOverdue, string.format("UCL MD%d @ %d/%d/%d", f.matchday or 0, f.date.year, f.date.month, f.date.day))
                end
            end
        end
    end

    return overdueCount, playerOverdue
end

------------------------------------------------------
-- 执行模拟
------------------------------------------------------

print("=== 20队联赛 October 2027 卡死复现测试 ===")
print("")

local gs = buildFullGameState()
_G.gameState = gs

-- 验证初始状态
assert(gs.season == 2026, "初始赛季应为2026")
assert(#gs.league.teamIds == 20, "英超应有20队")
assert(#gs.league.fixtures > 0, "联赛赛程应已生成")
print(string.format("英超: %d队, %d场比赛, %d轮", #gs.league.teamIds, #gs.league.fixtures, gs.league.totalRounds))
print(string.format("联赛首场: %d/%d/%d", gs.league.fixtures[1].date.year, gs.league.fixtures[1].date.month, gs.league.fixtures[1].date.day))
print(string.format("联赛末场: %d/%d/%d", gs.league.fixtures[#gs.league.fixtures].date.year, gs.league.fixtures[#gs.league.fixtures].date.month, gs.league.fixtures[#gs.league.fixtures].date.day))
print(string.format("UCL状态: %s", getUCLStatus(gs)))
print(string.format("WC状态: %s", getWCStatus(gs)))
print("")

local totalDays = 0
local maxDays = 800  -- 安全上限（超过2个赛季的长度）
local currentSeason = gs.season
local lastProgressDay = 0
local stuckDetection = { lastFinishedCount = 0, stuckDays = 0 }

-- 目标：模拟到 2027年11月（过了 October 2027）
local TARGET_DATE = { year = 2027, month = 11, day = 1 }

local function isPastTarget(date)
    if date.year > TARGET_DATE.year then return true end
    if date.year == TARGET_DATE.year then
        if date.month > TARGET_DATE.month then return true end
        if date.month == TARGET_DATE.month and date.day >= TARGET_DATE.day then return true end
    end
    return false
end

-- 详细日志：记录关键转折点
local detailedLogEnabled = false
local lastMonth = gs.date.month

while not isPastTarget(gs.date) and totalDays < maxDays do
    local prevSeason = gs.season
    local prevDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day }

    -- 到达 2027年9月 开始详细日志
    if gs.date.year == 2027 and gs.date.month >= 9 and not detailedLogEnabled then
        detailedLogEnabled = true
        print("")
        print("=== 进入详细监控区域 (2027年9月起) ===")
        print(string.format("  日期: %d/%d/%d, 联赛: %s", gs.date.year, gs.date.month, gs.date.day, getLeagueStatus(gs)))
        print(string.format("  UCL: %s", getUCLStatus(gs)))
        print(string.format("  下一场玩家比赛: %s", getPlayerNextMatch(gs)))
    end

    -- 推进一天
    local fixtures = TurnProcessor.advanceDay(gs)
    totalDays = totalDays + 1

    -- 检测赛季变更
    if gs.season ~= prevSeason then
        print(string.format("\n[赛季变更] 赛季 %d → %d (第%d天), 新日期: %d/%d/%d",
            prevSeason, gs.season, totalDays, gs.date.year, gs.date.month, gs.date.day))
        print(string.format("  新联赛: %s", getLeagueStatus(gs)))
        print(string.format("  新UCL: %s", getUCLStatus(gs)))
        print(string.format("  新WC: %s", getWCStatus(gs)))
        currentSeason = gs.season
    end

    -- 每月初打印进度
    if gs.date.month ~= lastMonth then
        lastMonth = gs.date.month
        local overdueCount, playerOverdue = checkOverdueFixtures(gs)
        if detailedLogEnabled or gs.date.month == 1 or totalDays % 100 < 2 then
            print(string.format("  [%d/%d/%d] 联赛:%s | UCL:%s | 逾期:%d | 玩家逾期:%d",
                gs.date.year, gs.date.month, gs.date.day,
                getLeagueStatus(gs), getUCLStatus(gs), overdueCount, #playerOverdue))
            if #playerOverdue > 0 then
                for _, desc in ipairs(playerOverdue) do
                    print(string.format("    !! 玩家逾期: %s", desc))
                end
            end
        end
    end

    -- 卡死检测：如果连续30天联赛比赛完成数没有增长
    local currentFinished = 0
    for _, f in ipairs(gs.league.fixtures) do
        if f.status == "finished" then currentFinished = currentFinished + 1 end
    end

    if currentFinished == stuckDetection.lastFinishedCount then
        stuckDetection.stuckDays = stuckDetection.stuckDays + 1
    else
        stuckDetection.lastFinishedCount = currentFinished
        stuckDetection.stuckDays = 0
    end

    -- 如果联赛进度停滞超过30天且还有未完成比赛，打印诊断
    if stuckDetection.stuckDays == 30 and currentFinished < #gs.league.fixtures then
        print(string.format("\n!!! 联赛进度停滞30天 !!!"))
        print(string.format("  日期: %d/%d/%d (第%d天)", gs.date.year, gs.date.month, gs.date.day, totalDays))
        print(string.format("  联赛: %s", getLeagueStatus(gs)))
        print(string.format("  UCL: %s", getUCLStatus(gs)))
        print(string.format("  WC: %s", getWCStatus(gs)))
        print(string.format("  _seasonEndProcessing: %s", tostring(gs._seasonEndProcessing)))
        local overdueCount, playerOverdue = checkOverdueFixtures(gs)
        print(string.format("  逾期比赛总数: %d, 玩家逾期: %d", overdueCount, #playerOverdue))
        for _, desc in ipairs(playerOverdue) do
            print(string.format("    !! %s", desc))
        end

        -- 找下一场联赛比赛
        local nextLeagueDate = nil
        for _, f in ipairs(gs.league.fixtures) do
            if f.status == "scheduled" then
                if not nextLeagueDate or TurnProcessor._isDateBefore(f.date, nextLeagueDate) then
                    nextLeagueDate = f.date
                end
            end
        end
        if nextLeagueDate then
            print(string.format("  下一场联赛比赛日期: %d/%d/%d", nextLeagueDate.year, nextLeagueDate.month, nextLeagueDate.day))
        else
            print("  没有剩余联赛比赛（全部完成或无赛程）")
        end
    end

    -- 如果停滞超过60天，判定为卡死
    if stuckDetection.stuckDays > 60 and currentFinished < #gs.league.fixtures then
        print(string.format("\n!!! 确认卡死 - 联赛60天无进展 !!!"))
        print(string.format("  最终日期: %d/%d/%d", gs.date.year, gs.date.month, gs.date.day))
        print(string.format("  总模拟天数: %d", totalDays))

        -- 打印所有未完成的联赛比赛
        print("\n  未完成联赛比赛列表（前20场）:")
        local unfinished = 0
        for _, f in ipairs(gs.league.fixtures) do
            if f.status == "scheduled" and unfinished < 20 then
                local isPlayer = (f.homeTeamId == gs.playerTeamId or f.awayTeamId == gs.playerTeamId)
                print(string.format("    R%d: %s vs %s @ %d/%d/%d %s",
                    f.round, tostring(f.homeTeamId), tostring(f.awayTeamId),
                    f.date.year, f.date.month, f.date.day,
                    isPlayer and "[PLAYER]" or ""))
                unfinished = unfinished + 1
            end
        end

        -- 打印UCL未完成比赛
        local ucl = gs.championsLeague
        if ucl and ucl.leaguePhase and ucl.leaguePhase.fixtures then
            print("\n  未完成UCL比赛（前10场）:")
            local uclUnfinished = 0
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f.status == "scheduled" and uclUnfinished < 10 then
                    local isPlayer = (f.homeTeamId == gs.playerTeamId or f.awayTeamId == gs.playerTeamId)
                    print(string.format("    MD%d: %s vs %s @ %d/%d/%d %s",
                        f.matchday or 0, tostring(f.homeTeamId), tostring(f.awayTeamId),
                        f.date.year, f.date.month, f.date.day,
                        isPlayer and "[PLAYER]" or ""))
                    uclUnfinished = uclUnfinished + 1
                end
            end
        end

        error("游戏卡死！联赛60天无进展。")
    end

    -- 每200天打印摘要
    if totalDays % 200 == 0 and not detailedLogEnabled then
        print(string.format("  [进度] 第%d天, 日期=%d/%d/%d, 赛季=%d, 联赛=%s",
            totalDays, gs.date.year, gs.date.month, gs.date.day, gs.season, getLeagueStatus(gs)))
    end
end

------------------------------------------------------
-- 输出结果
------------------------------------------------------

print("")
print("=== 测试完成 ===")
print(string.format("总模拟天数: %d", totalDays))
print(string.format("最终日期: %d/%d/%d", gs.date.year, gs.date.month, gs.date.day))
print(string.format("最终赛季: %d", gs.season))
print(string.format("赛季结束事件触发次数: %d", seasonEndCount))
print(string.format("最终联赛: %s", getLeagueStatus(gs)))
print(string.format("最终UCL: %s", getUCLStatus(gs)))

if isPastTarget(gs.date) then
    print("\n✅ 成功模拟到2027年11月，未检测到卡死！")
else
    print("\n❌ 未能到达目标日期，可能存在问题")
end
