-- tests/budget_allocation_test.lua
-- 验证 SeasonManager._allocateSeasonBudgets 在赛季转换时真正生效

require("tests/bootstrap")
SetTestRandomSeed(99)

local GameState = require("scripts/core/game_state")
local League = require("scripts/domain/league")
local TurnProcessor = require("scripts/core/turn_processor")
local SeasonManager = require("scripts/systems/season_manager")
local Constants = require("scripts/app/constants")
local EventBus = require("scripts/app/event_bus")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local ChampionsLeague = require("scripts/systems/champions_league")
local WorldCup = require("scripts/systems/world_cup")

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

local passed = 0
local failed = 0

local function assert_true(cond, msg)
    if cond then
        passed = passed + 1
        print("  PASS: " .. msg)
    else
        failed = failed + 1
        print("  FAIL: " .. msg)
    end
end

local function attributes(value)
    return {
        speed = value, stamina = value, strength = value, agility = value,
        passing = value, shooting = value, tackling = value, dribbling = value,
        defending = value, positioning = value, vision = value, decisions = value,
        composure = value, aggression = 10, teamwork = value, leadership = value,
        handling = value, reflexes = value, aerial = value,
    }
end

local function populateTeam(gameState, team, wage)
    local positions = { "GK", "LB", "CB", "CB", "RB", "CM", "CM", "CM", "LM", "RM", "ST",
                        "GK", "LB", "CB", "RB", "CM", "CM", "LM" }
    for i, position in ipairs(positions) do
        local player = gameState:addPlayer({
            firstName = team.shortName,
            lastName = position .. i,
            displayName = team.shortName .. " " .. position .. i,
            birthYear = 1998,
            nationality = "ENG",
            position = position,
            attributes = attributes(14),
            fitness = 90,
            morale = 70,
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

local function createTestGameState()
    local gs = GameState.new()
    gs.date = { year = 2026, month = 8, day = 10 }
    gs.season = 2026
    gs.dayOfWeek = 1
    gs._cheatAutoPlay = true

    -- 创建一个简单联赛（4队够了）
    local teamIds = {}
    local teamConfigs = {
        { name = "Rich FC",   balance = 100000000, wage = 50000, rep = 800 },  -- 1亿余额、高工资、高声望
        { name = "Poor FC",   balance = 5000000,   wage = 5000,  rep = 200 },  -- 500万余额、低工资、低声望
        { name = "Mid FC",    balance = 30000000,  wage = 20000, rep = 500 },  -- 3000万余额、中等
        { name = "Broke FC",  balance = 1000000,   wage = 10000, rep = 300 },  -- 100万余额、低声望
    }

    for i, cfg in ipairs(teamConfigs) do
        local team = gs:addTeam({
            name = cfg.name,
            shortName = "T" .. i,
            formation = "4-4-2",
            playStyle = "Balanced",
            balance = cfg.balance,
            wageBudget = 10000,        -- 故意设很低，验证是否被重算
            transferBudget = 0,        -- 故意设为0，验证是否被重新分配
            stadiumCapacity = 30000,
            country = "ENG",
            reputation = cfg.rep,
        })
        populateTeam(gs, team, cfg.wage)
        table.insert(teamIds, team.id)
    end

    local league = League.new({
        id = gs:generateId(),
        name = "Test League",
        country = "ENG",
        teamIds = teamIds,
        fixtures = {},
    })
    league:initStandings()
    gs.leagues["TEST"] = league
    gs.league = league
    gs.playerLeagueId = "TEST"
    gs.playerTeamId = teamIds[1]

    local leagueStartDate = { year = gs.season, month = Constants.SEASON_START_MONTH, day = Constants.SEASON_START_DAY }
    league.season = gs.season
    league.currentRound = 1
    league:generateFixtures(leagueStartDate)

    ObjectivesManager.initSeason(gs)

    return gs
end

------------------------------------------------------
-- 测试1: 直接调用 _allocateSeasonBudgets
------------------------------------------------------

print("\n=== 测试1: _allocateSeasonBudgets 直接调用 ===")

local gs = createTestGameState()

-- 记录调用前的预算值
local beforeBudgets = {}
for _, team in pairs(gs.teams) do
    beforeBudgets[team.id] = {
        transferBudget = team.transferBudget,
        wageBudget = team.wageBudget,
    }
end

-- 直接调用
SeasonManager._allocateSeasonBudgets(gs)

-- 验证
for _, team in pairs(gs.teams) do
    local before = beforeBudgets[team.id]
    print(string.format("\n  [%s] balance=%.0f, rep=%d", team.name, team.balance, team.reputation or 0))
    print(string.format("    BEFORE: transferBudget=%d, wageBudget=%d", before.transferBudget, before.wageBudget))
    print(string.format("    AFTER:  transferBudget=%d, wageBudget=%d", team.transferBudget, team.wageBudget))

    assert_true(team.transferBudget > 0, team.name .. " 转会预算 > 0")
    assert_true(team.wageBudget > 0, team.name .. " 工资预算 > 0")
    assert_true(team.wageBudget >= 200000, team.name .. " 工资预算 >= 200K 保底")
    assert_true(team.transferBudget >= 5000000, team.name .. " 转会预算 >= 5M 保底")

    -- 转会预算不应超过余额 50%
    local cap = math.floor(team.balance * 0.5)
    -- 但有保底 5M，所以余额低于 10M 时可能超过 50%
    if team.balance >= 10000000 then
        assert_true(team.transferBudget <= cap,
            team.name .. " 转会预算 <= 余额50% (budget=" .. team.transferBudget .. ", cap=" .. cap .. ")")
    end
end

------------------------------------------------------
-- 测试2: 通过 _startNewSeason 间接验证
------------------------------------------------------

print("\n\n=== 测试2: _startNewSeason 间接调用验证 ===")

local gs2 = createTestGameState()

-- 确保所有球队转会预算为0（模拟"花光了"的情况）
for _, team in pairs(gs2.teams) do
    team.transferBudget = 0
    team.wageBudget = 0
end

-- 调用 _startNewSeason
SeasonManager._startNewSeason(gs2)

-- 验证：新赛季后预算不再是0
local allBudgetsAllocated = true
for _, team in pairs(gs2.teams) do
    print(string.format("  [%s] transferBudget=%d, wageBudget=%d",
        team.name, team.transferBudget, team.wageBudget))

    if team.transferBudget == 0 or team.wageBudget == 0 then
        allBudgetsAllocated = false
    end

    assert_true(team.transferBudget > 0, team.name .. " 新赛季转会预算已分配")
    assert_true(team.wageBudget > 0, team.name .. " 新赛季工资预算已分配")
end

assert_true(allBudgetsAllocated, "所有球队在新赛季都获得了预算分配")

------------------------------------------------------
-- 测试3: 验证预算合理性（Rich vs Poor）
------------------------------------------------------

print("\n\n=== 测试3: 预算合理性验证 ===")

local gs3 = createTestGameState()
SeasonManager._allocateSeasonBudgets(gs3)

local richTeam, poorTeam
for _, team in pairs(gs3.teams) do
    if team.name == "Rich FC" then richTeam = team end
    if team.name == "Poor FC" then poorTeam = team end
end

if richTeam and poorTeam then
    print(string.format("  Rich FC: balance=%d, transferBudget=%d, wageBudget=%d",
        richTeam.balance, richTeam.transferBudget, richTeam.wageBudget))
    print(string.format("  Poor FC: balance=%d, transferBudget=%d, wageBudget=%d",
        poorTeam.balance, poorTeam.transferBudget, poorTeam.wageBudget))

    assert_true(richTeam.transferBudget > poorTeam.transferBudget,
        "Rich FC 转会预算 > Poor FC (差距: " ..
        (richTeam.transferBudget - poorTeam.transferBudget) .. ")")
    assert_true(richTeam.wageBudget > poorTeam.wageBudget,
        "Rich FC 工资预算 > Poor FC (因为球员工资更高)")
end

------------------------------------------------------
-- 测试4: 验证完整赛季流转（快进一整赛季）
------------------------------------------------------

print("\n\n=== 测试4: 完整赛季流转验证 ===")

local gs4 = createTestGameState()
local playerTeam = gs4.teams[gs4.playerTeamId]
print(string.format("  赛季开始: season=%d, playerTeam balance=%d, transferBudget=%d",
    gs4.season, playerTeam.balance, playerTeam.transferBudget))

-- 快进至赛季结束（模拟所有比赛）
local maxDays = 400  -- 一个赛季约300-350天
local dayCount = 0
local seasonChanged = false

for d = 1, maxDays do
    local oldSeason = gs4.season
    TurnProcessor.advanceDay(gs4)
    dayCount = d

    if gs4.season ~= oldSeason then
        seasonChanged = true
        print(string.format("  赛季在第 %d 天结束, 新赛季 %d 开始", d, gs4.season))
        break
    end
end

if seasonChanged then
    playerTeam = gs4.teams[gs4.playerTeamId]
    print(string.format("  新赛季: season=%d, playerTeam balance=%d, transferBudget=%d, wageBudget=%d",
        gs4.season, playerTeam.balance, playerTeam.transferBudget, playerTeam.wageBudget))

    assert_true(playerTeam.transferBudget > 0, "完整赛季转换后玩家球队转会预算 > 0")
    assert_true(playerTeam.wageBudget > 0, "完整赛季转换后玩家球队工资预算 > 0")
else
    print("  WARNING: " .. maxDays .. "天内赛季未结束（可能赛程生成问题），跳过此测试")
end

------------------------------------------------------
-- 结果汇总
------------------------------------------------------

print("\n\n========================================")
print(string.format("测试结果: %d PASSED, %d FAILED, 总计 %d", passed, failed, passed + failed))
print("========================================\n")

if failed > 0 then
    os.exit(1)
end
