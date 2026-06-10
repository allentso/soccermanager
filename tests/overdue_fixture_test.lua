-- tests/overdue_fixture_test.lua
-- 测试赛程积压（overdue fixture snowball）修复
-- 验证：逾期比赛不应消耗额外日历天数

local Fixtures = require("tests/fixtures/minimal_game_state")
local TurnProcessor = require("scripts/core/turn_processor")
local League = require("scripts/domain/league")

SetTestRandomSeed(999)

------------------------------------------------------
-- 辅助函数
------------------------------------------------------
local function makeDate(y, m, d)
    return { year = y, month = m, day = d }
end

--- 创建一个有多场逾期比赛的 gameState
local function setupOverdueScenario()
    local gameState, home, away = Fixtures.twoTeams()

    -- 添加第三支队伍（以构成完整联赛）
    local third = gameState:addTeam({
        name = "Third FC",
        shortName = "TFC",
        formation = "4-4-2",
        playStyle = "Balanced",
        balance = 500000,
        wageBudget = 15000,
        stadiumCapacity = 15000,
    })
    -- 给第三支队伍加球员（避免模拟时报错）
    local positions = { "GK", "LB", "CB", "CB", "RB", "CM", "CM", "LM", "RM", "ST", "ST" }
    for _, pos in ipairs(positions) do
        local p = gameState:addPlayer({
            firstName = pos, lastName = "Third", displayName = pos .. " Third",
            birthYear = 1998, nationality = "ENG", position = pos,
            attributes = {
                speed = 12, stamina = 12, strength = 12, agility = 12,
                passing = 12, shooting = 12, tackling = 12, dribbling = 12,
                defending = 12, positioning = 12, vision = 12, decisions = 12,
                composure = 12, aggression = 10, teamwork = 12, leadership = 12,
                handling = 12, reflexes = 12, aerial = 12,
            },
            fitness = 88, morale = 70, wage = 800, teamId = third.id,
        })
        third:addPlayer(p.id)
        table.insert(third.startingXI, p.id)
    end

    -- 重建联赛（3支球队）
    local league = League.new({
        id = 1,
        name = "Test Bundesliga",
        teamIds = { home.id, away.id, third.id },
        fixtures = {},
    })
    league:initStandings()
    gameState.league = league
    gameState.leagues = { test = league }

    -- 手动排赛程：
    -- Round 1: 8月10日 home vs away, third 轮空（简化）
    -- Round 2: 8月17日 home vs third, away 轮空
    -- Round 3: 8月24日 away vs home
    -- Round 4: 8月31日 third vs home
    -- Round 5: 9月7日  home vs away (第二循环)
    league.fixtures = {
        -- Round 1: Aug 10 (已过期) - home vs away
        { id = 101, homeTeamId = home.id, awayTeamId = away.id, date = makeDate(2024, 8, 10), status = "scheduled", round = 1 },
        -- Round 1: Aug 10 (已过期) - 第三队 vs 无关队（简化为3队循环赛）
        -- Round 2: Aug 17 (已过期) - home vs third
        { id = 102, homeTeamId = home.id, awayTeamId = third.id, date = makeDate(2024, 8, 17), status = "scheduled", round = 2 },
        -- Round 2: Aug 17 (已过期) - away vs ... (无关)
        { id = 103, homeTeamId = away.id, awayTeamId = third.id, date = makeDate(2024, 8, 17), status = "scheduled", round = 2 },
        -- Round 3: Aug 24 (已过期) - away vs home
        { id = 104, homeTeamId = away.id, awayTeamId = home.id, date = makeDate(2024, 8, 24), status = "scheduled", round = 3 },
        -- Round 3: Aug 24 (已过期) - third vs ... (无关)
        { id = 105, homeTeamId = third.id, awayTeamId = away.id, date = makeDate(2024, 8, 24), status = "scheduled", round = 3 },
        -- Round 4: Sep 7 (未来) - home vs away
        { id = 106, homeTeamId = home.id, awayTeamId = away.id, date = makeDate(2024, 9, 7), status = "scheduled", round = 4 },
        -- Round 4: Sep 7 (未来) - third vs ... (无关)
        { id = 107, homeTeamId = third.id, awayTeamId = away.id, date = makeDate(2024, 9, 7), status = "scheduled", round = 4 },
    }

    -- 当前日期设为 8月28日（比 Round 1/2/3 都晚，这些都是逾期）
    gameState.date = makeDate(2024, 8, 28)
    gameState.dayOfWeek = 3 -- 周三

    return gameState, home, away, third, league
end

------------------------------------------------------
-- TEST 1: peekOverduePlayerFixture 能正确检测逾期比赛
------------------------------------------------------
print("  [Test 1] peekOverduePlayerFixture detects overdue matches")

local gameState, home = setupOverdueScenario()

local overdueFixture = TurnProcessor.peekOverduePlayerFixture(gameState)
assert(overdueFixture ~= nil, "should find an overdue player fixture")
assert(overdueFixture.homeTeamId == home.id or overdueFixture.awayTeamId == home.id,
    "overdue fixture should involve player team")
assert(overdueFixture.status == "scheduled", "overdue fixture should still be scheduled")

-- 验证日期在当前日期之前
assert(TurnProcessor._isDateBefore(overdueFixture.date, gameState.date),
    "overdue fixture date should be before current date")

print("    PASS: peekOverduePlayerFixture correctly detects overdue fixture (id=" .. overdueFixture.id .. ")")

------------------------------------------------------
-- TEST 2: peekOverduePlayerFixture 不修改任何状态
------------------------------------------------------
print("  [Test 2] peekOverduePlayerFixture is read-only (no side effects)")

local gameState2 = setupOverdueScenario()
local dateBefore = { year = gameState2.date.year, month = gameState2.date.month, day = gameState2.date.day }

-- 调用多次
TurnProcessor.peekOverduePlayerFixture(gameState2)
TurnProcessor.peekOverduePlayerFixture(gameState2)
TurnProcessor.peekOverduePlayerFixture(gameState2)

-- 日期不应变化
assert(gameState2.date.year == dateBefore.year and
       gameState2.date.month == dateBefore.month and
       gameState2.date.day == dateBefore.day,
    "peekOverduePlayerFixture should NOT advance the date")

-- 所有比赛状态不应变化
local league2 = gameState2.leagues.test
local scheduledCount = 0
for _, f in ipairs(league2.fixtures) do
    if f.status == "scheduled" then scheduledCount = scheduledCount + 1 end
end
assert(scheduledCount == 7, "no fixtures should be simulated by peek (all 7 should remain scheduled)")

print("    PASS: no side effects after multiple peek calls")

------------------------------------------------------
-- TEST 3: 旧逻辑（advanceDay）每场逾期消耗1天 - 雪球效应
------------------------------------------------------
print("  [Test 3] advanceDay consumes 1 day per overdue match (snowball behavior)")

local gameState3 = setupOverdueScenario()
local startDate = { year = gameState3.date.year, month = gameState3.date.month, day = gameState3.date.day }

-- 模拟旧的 dashboard 行为：连续调用 advanceDay 直到处理完所有逾期比赛
-- 每次调用消耗1天 + 处理1场逾期玩家比赛
local daysConsumed = 0
local playerOverdueFound = 0

for attempt = 1, 20 do -- 安全上限防止死循环
    local fixtures = TurnProcessor.advanceDay(gameState3)
    daysConsumed = daysConsumed + 1

    -- 模拟 dashboard: 找到第一个 _pendingPlayerMatch 并"处理"它
    local foundPlayer = false
    for _, f in ipairs(fixtures) do
        if f._pendingPlayerMatch then
            -- 模拟玩家打了这场比赛
            f.status = "finished"
            f.homeGoals = 1
            f.awayGoals = 0
            f._pendingPlayerMatch = nil
            playerOverdueFound = playerOverdueFound + 1
            foundPlayer = true
            break
        end
    end

    -- 如果没有更多玩家逾期比赛，检查 peek 是否也返回 nil
    if not foundPlayer then
        local stillOverdue = TurnProcessor.peekOverduePlayerFixture(gameState3)
        if not stillOverdue then
            break -- 所有逾期已处理
        end
    end
end

-- 3场逾期的玩家比赛（Round 1, 2, 3 各有一场涉及玩家队）
assert(playerOverdueFound == 3,
    string.format("should find 3 overdue player matches, got %d", playerOverdueFound))

-- 旧逻辑：至少消耗3天（每场逾期1天）
-- 注意：可能消耗更多，因为 catch-up 只发生在日期推进后
assert(daysConsumed >= 3,
    string.format("old behavior should consume >= 3 days, consumed %d", daysConsumed))

-- 日期应该前进了 daysConsumed 天
local expectedDay = startDate.day + daysConsumed
print(string.format("    PASS: old behavior consumed %d days for %d overdue matches (date: 8/%d → 8/%d+)",
    daysConsumed, playerOverdueFound, startDate.day, startDate.day + daysConsumed))

------------------------------------------------------
-- TEST 4: 新逻辑（peek + 不推进日期）消耗 0 天处理逾期
------------------------------------------------------
print("  [Test 4] new logic: peek before advance prevents snowball")

local gameState4 = setupOverdueScenario()
local startDate4 = { year = gameState4.date.year, month = gameState4.date.month, day = gameState4.date.day }
local daysConsumed4 = 0
local playerOverdueHandled4 = 0

for attempt = 1, 20 do
    -- 新逻辑：先 peek，如果有逾期，不推进日期，直接处理
    local overdueF = TurnProcessor.peekOverduePlayerFixture(gameState4)
    if overdueF then
        -- 模拟玩家打了这场比赛（不推进日期！）
        overdueF.status = "finished"
        overdueF.homeGoals = 2
        overdueF.awayGoals = 1
        overdueF._pendingPlayerMatch = nil
        playerOverdueHandled4 = playerOverdueHandled4 + 1
    else
        -- 没有逾期比赛了，正常推进
        break
    end
end

assert(playerOverdueHandled4 == 3,
    string.format("should handle 3 overdue matches, got %d", playerOverdueHandled4))

-- 关键断言：日期完全没变！
assert(gameState4.date.year == startDate4.year and
       gameState4.date.month == startDate4.month and
       gameState4.date.day == startDate4.day,
    string.format("new logic should NOT advance date! Expected 8/28, got %d/%d",
        gameState4.date.month, gameState4.date.day))

daysConsumed4 = 0 -- 日期没变 = 0天消耗
print(string.format("    PASS: new logic consumed 0 days for %d overdue matches (date unchanged: 8/28)",
    playerOverdueHandled4))

------------------------------------------------------
-- TEST 5: 其他队的比赛差距对比
------------------------------------------------------
print("  [Test 5] compare games-played gap between old and new logic")

-- 旧逻辑下：重新跑一次，统计各队完成比赛数
local gameState5a = setupOverdueScenario()
for attempt = 1, 20 do
    local fixtures = TurnProcessor.advanceDay(gameState5a)
    local foundPlayer = false
    for _, f in ipairs(fixtures) do
        if f._pendingPlayerMatch then
            f.status = "finished"
            f.homeGoals = 1
            f.awayGoals = 0
            f._pendingPlayerMatch = nil
            foundPlayer = true
            break
        end
    end
    if not foundPlayer then
        if not TurnProcessor.peekOverduePlayerFixture(gameState5a) then break end
    end
end

-- 统计各队完成比赛数
local function countFinished(gs, teamId)
    local count = 0
    for _, lg in pairs(gs.leagues or {}) do
        for _, f in ipairs(lg.fixtures) do
            if f.status == "finished" and (f.homeTeamId == teamId or f.awayTeamId == teamId) then
                count = count + 1
            end
        end
    end
    return count
end

local homeFinished5a = countFinished(gameState5a, gameState5a.playerTeamId)
-- 其他队可能已完成更多比赛（因为 catch-up 自动模拟了它们的逾期比赛）
local league5a = gameState5a.leagues.test
local maxOtherFinished5a = 0
for _, tid in ipairs(league5a.teamIds) do
    if tid ~= gameState5a.playerTeamId then
        local c = countFinished(gameState5a, tid)
        maxOtherFinished5a = math.max(maxOtherFinished5a, c)
    end
end

print(string.format("    Old logic: player team=%d games, max other=%d games, gap=%d",
    homeFinished5a, maxOtherFinished5a, maxOtherFinished5a - homeFinished5a))

-- 新逻辑下：peek 处理逾期后，再统一推进
local gameState5b = setupOverdueScenario()
-- 先处理所有逾期（不推进日期）
for attempt = 1, 20 do
    local overdueF = TurnProcessor.peekOverduePlayerFixture(gameState5b)
    if overdueF then
        overdueF.status = "finished"
        overdueF.homeGoals = 2
        overdueF.awayGoals = 1
    else
        break
    end
end
-- 然后推进一天（模拟正常继续游戏）
TurnProcessor.advanceDay(gameState5b)

local homeFinished5b = countFinished(gameState5b, gameState5b.playerTeamId)
local maxOtherFinished5b = 0
for _, tid in ipairs(league5a.teamIds) do
    if tid ~= gameState5b.playerTeamId then
        local c = countFinished(gameState5b, tid)
        maxOtherFinished5b = math.max(maxOtherFinished5b, c)
    end
end

print(string.format("    New logic: player team=%d games, max other=%d games, gap=%d",
    homeFinished5b, maxOtherFinished5b, maxOtherFinished5b - homeFinished5b))

-- 新逻辑下，玩家队应该完成 >= 旧逻辑的比赛数（因为没有浪费天数）
assert(homeFinished5b >= homeFinished5a,
    "new logic should not have fewer player games than old logic")

-- 新逻辑下的差距不应比旧逻辑大
local gapOld = maxOtherFinished5a - homeFinished5a
local gapNew = maxOtherFinished5b - homeFinished5b
assert(gapNew <= gapOld,
    string.format("new logic gap (%d) should be <= old logic gap (%d)", gapNew, gapOld))

print(string.format("    PASS: gap reduced from %d to %d", gapOld, gapNew))

------------------------------------------------------
-- TEST 6: 没有逾期时 peek 返回 nil
------------------------------------------------------
print("  [Test 6] peekOverduePlayerFixture returns nil when no overdue matches")

local gameState6, home6 = Fixtures.twoTeams()
-- 默认 fixture 的日期和 gameState 日期都是 8月10日（今天，不是逾期）
local result6 = TurnProcessor.peekOverduePlayerFixture(gameState6)
assert(result6 == nil, "should return nil when no overdue matches (today's match is not overdue)")

-- 把比赛日期设到未来
gameState6.leagues.test.fixtures[1].date = makeDate(2024, 8, 15)
local result6b = TurnProcessor.peekOverduePlayerFixture(gameState6)
assert(result6b == nil, "should return nil for future fixtures")

print("    PASS: returns nil correctly for today/future fixtures")

------------------------------------------------------
print("\n  === All overdue fixture tests PASSED ===")
return true
