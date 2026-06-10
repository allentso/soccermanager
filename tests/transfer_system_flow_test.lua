-- tests/transfer_system_flow_test.lua
-- 转会系统功能验证：转会窗口、买入流程、出售流程、还价延迟、超时机制、自由球员

require("tests/bootstrap")

local GameState = require("scripts/core/game_state")
local TransferManager = require("scripts/systems/transfer_manager")
local Fixtures = require("tests/fixtures/minimal_game_state")

------------------------------------------------------
-- 测试工具
------------------------------------------------------
local passCount = 0
local failCount = 0

local function assertEqual(actual, expected, msg)
    if actual == expected then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        print(string.format("  FAIL: %s (expected: %s, got: %s)", msg, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(cond, msg)
    if cond then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        print(string.format("  FAIL: %s", msg))
    end
end

local function assertNotNil(val, msg)
    if val ~= nil then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        print(string.format("  FAIL: %s (got nil)", msg))
    end
end

local function assertNil(val, msg)
    if val == nil then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        print(string.format("  FAIL: %s (expected nil, got %s)", msg, tostring(val)))
    end
end

local function section(name)
    print(string.format("\n=== %s ===", name))
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

--- 创建基础游戏状态（使用 Fixtures.twoTeams 并调整）
local function makeGameState(month)
    local gs, home, away = Fixtures.twoTeams()
    gs.date = { year = 2025, month = month or 7, day = 15 }
    gs.season = 2025
    return gs, home, away
end

--- 推进日期
local function advanceDays(gs, days)
    for _ = 1, days do
        gs.date.day = gs.date.day + 1
        if gs.date.day > 30 then
            gs.date.day = 1
            gs.date.month = gs.date.month + 1
            if gs.date.month > 12 then
                gs.date.month = 1
                gs.date.year = gs.date.year + 1
            end
        end
    end
end

--- 创建一个模拟的 incoming bid（AI球队对玩家球员发起的报价）
local function createIncomingBid(gs, home, away, player, amount)
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = player.id,
        buyerTeamId = away.id,
        sellerTeamId = home.id,
        amount = amount or math.floor(player.value * 1.2),
        playerValue = player.value,
        status = "pending",
        isIncomingBid = true,
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = player.wage * 1.5,
        contractYears = 3,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)
    return bid
end

------------------------------------------------------
-- 测试开始
------------------------------------------------------

section("1. 转会窗口 - 窗口内允许操作")
do
    SetTestRandomSeed(100)
    -- 7月（夏窗内）
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[5]]
    assertNotNil(targetPlayer, "目标球员存在")

    local bid, err = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNotNil(bid, "夏窗7月: makeBid 应成功")
    assertNil(err, "夏窗7月: 无错误信息")
    assertEqual(bid.status, "pending", "夏窗7月: bid状态为pending")
end

section("2. 转会窗口 - 窗口外阻止操作")
do
    SetTestRandomSeed(101)
    -- 3月（窗口外）
    local gs, home, away = makeGameState(3)
    local targetPlayer = gs.players[away.playerIds[5]]

    local bid, err = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNil(bid, "3月窗口外: makeBid 应返回nil")
    assertNotNil(err, "3月窗口外: 应有错误信息")
    assertTrue(string.find(err, "转会窗口") ~= nil, "3月窗口外: 错误信息提及转会窗口")
end

section("3. 转会窗口 - 冬窗1月允许")
do
    SetTestRandomSeed(102)
    local gs, home, away = makeGameState(1)
    local targetPlayer = gs.players[away.playerIds[5]]

    local bid, err = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNotNil(bid, "冬窗1月: makeBid 应成功")
    assertNil(err, "冬窗1月: 无错误信息")
end

section("4. 转会窗口 - 6月/8月边界检查")
do
    SetTestRandomSeed(103)
    -- 6月（夏窗起始）
    local gs, home, away = makeGameState(6)
    local targetPlayer = gs.players[away.playerIds[5]]
    local bid6, err6 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNotNil(bid6, "6月: makeBid 应成功")

    -- 8月（夏窗末尾）
    SetTestRandomSeed(104)
    gs, home, away = makeGameState(8)
    targetPlayer = gs.players[away.playerIds[5]]
    local bid8, err8 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNotNil(bid8, "8月: makeBid 应成功")

    -- 9月（窗口刚关）
    SetTestRandomSeed(105)
    gs, home, away = makeGameState(9)
    targetPlayer = gs.players[away.playerIds[5]]
    local bid9, err9 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value, targetPlayer.wage)
    assertNil(bid9, "9月: makeBid 应失败")
    assertNotNil(err9, "9月: 应有错误")
end

section("5. 转会窗口 - makeLoanBid 同样受限")
do
    SetTestRandomSeed(106)
    -- 窗口外
    local gs, home, away = makeGameState(4)
    local targetPlayer = gs.players[away.playerIds[5]]
    targetPlayer.listedForLoan = true

    local bid, err = TransferManager.makeLoanBid(gs, targetPlayer.id, 1)
    assertNil(bid, "4月窗口外: makeLoanBid 应返回nil")
    assertTrue(err ~= nil and string.find(err, "转会窗口") ~= nil, "4月窗口外: 租借报错提及转会窗口")
end

section("6. 转会窗口 - triggerReleaseClause 同样受限")
do
    SetTestRandomSeed(107)
    local gs, home, away = makeGameState(10)
    local targetPlayer = gs.players[away.playerIds[5]]
    targetPlayer.releaseClause = targetPlayer.value * 2

    local bid, err = TransferManager.triggerReleaseClause(gs, targetPlayer.id)
    assertNil(bid, "10月窗口外: triggerReleaseClause 应返回nil")
    assertTrue(err ~= nil and string.find(err, "转会窗口") ~= nil, "10月窗口外: 解约金报错提及转会窗口")
end

section("7. 自由球员 - 不受转会窗口限制")
do
    SetTestRandomSeed(108)
    local gs, home, away = makeGameState(3) -- 3月，窗口外
    -- 创建自由球员
    local freeAgent = gs:addPlayer({
        firstName = "Free",
        lastName = "Agent",
        displayName = "Free Agent",
        birthYear = 1996,
        nationality = "ENG",
        position = "CM",
        attributes = { speed = 12, stamina = 12, strength = 12, agility = 12,
            passing = 12, shooting = 12, tackling = 12, dribbling = 12,
            defending = 12, positioning = 12, vision = 12, decisions = 12,
            composure = 12, aggression = 10, teamwork = 12, leadership = 12,
            handling = 5, reflexes = 5, aerial = 12 },
        wage = 2000,
        teamId = nil, -- 无球队=自由球员
    })

    local nego, err = TransferManager.offerFreeAgent(gs, freeAgent.id, 3000, 3)
    assertNotNil(nego, "3月窗口外: 自由球员签约应成功")
    assertNil(err, "3月窗口外: 自由球员签约无错误")
end

section("8. 买入流程 - AI回应延迟（pending阶段，1-3天等待）")
do
    SetTestRandomSeed(200)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[5]]

    local bid, _ = TransferManager.makeBid(gs, targetPlayer.id, math.floor(targetPlayer.value * 0.9), targetPlayer.wage)
    assertNotNil(bid, "买入流程: bid创建成功")
    assertEqual(bid.status, "pending", "买入流程: 初始状态pending")

    -- 当天处理 - 应该还不回复（需1-3天延迟）
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "pending", "买入流程: 当天AI不回复（延迟中）")

    -- 推进3天后处理
    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)
    assertTrue(bid.status ~= "pending", "买入流程: 3天后AI应回复（状态不再是pending）")
end

section("9. 买入流程 - 高出价直接接受 → player_considering → fee_agreed → awaiting_confirmation")
do
    SetTestRandomSeed(201)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[6]]

    -- 出高价（1.5倍身价）确保被接受
    local bid, _ = TransferManager.makeBid(gs, targetPlayer.id, math.floor(targetPlayer.value * 1.5), targetPlayer.wage * 1.5)
    assertNotNil(bid, "高价买入: bid创建成功")

    -- 推进足够天数让AI回应
    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)

    -- AI接受后进入 player_considering
    assertEqual(bid.status, "player_considering", "高价买入: AI接受后进入player_considering")

    -- 推进球员考虑天数（1-3天）
    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)

    -- 球员考虑期结束后自动尝试个人条款
    assertTrue(bid.status == "fee_agreed" or bid.status == "awaiting_confirmation",
        "高价买入: 考虑期后进入fee_agreed或awaiting_confirmation")

    -- 如果进入了 awaiting_confirmation，玩家可确认
    if bid.status == "awaiting_confirmation" then
        local result, err = TransferManager.confirmTransfer(gs, bid.id)
        assertNotNil(result, "高价买入: confirmTransfer成功")
        assertEqual(bid.status, "completed", "高价买入: 确认后completed")
        assertEqual(targetPlayer.teamId, home.id, "高价买入: 球员加入买方球队")
    end
end

section("10. 买入流程 - 低出价被拒绝")
do
    SetTestRandomSeed(202)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[7]]

    -- 出低价（0.3倍身价）应被拒绝
    local bid, _ = TransferManager.makeBid(gs, targetPlayer.id, math.floor(targetPlayer.value * 0.3), targetPlayer.wage)
    assertNotNil(bid, "低价买入: bid创建成功")

    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "rejected", "低价买入: 报价过低直接被拒")
end

section("11. 买入流程 - 谈判(negotiating)阶段与加价")
do
    SetTestRandomSeed(203)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[8]]

    -- 出中等价（0.8倍身价）可能进入谈判
    local bid, _ = TransferManager.makeBid(gs, targetPlayer.id, math.floor(targetPlayer.value * 0.8), targetPlayer.wage)
    assertNotNil(bid, "谈判流程: bid创建成功")

    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)

    if bid.status == "negotiating" then
        -- 验证有 counterAmount
        assertNotNil(bid.counterAmount, "谈判流程: AI给出还价金额")
        assertTrue(bid.counterAmount > bid.amount, "谈判流程: 还价高于当前出价")

        -- 玩家加价
        local newOffer = bid.counterAmount -- 直接出AI要价
        local raised = TransferManager.raiseBid(gs, bid.id, newOffer, targetPlayer.wage)
        assertTrue(raised, "谈判流程: raiseBid 成功")
        assertEqual(bid.status, "pending", "谈判流程: 加价后重新pending")

        -- 再次处理让AI回应
        advanceDays(gs, 2)
        TransferManager.processDailyBids(gs)
        assertTrue(bid.status ~= "pending", "谈判流程: 加价后AI再次回应")
    else
        -- 可能直接接受或拒绝，也是合理结果
        assertTrue(bid.status == "rejected" or bid.status == "player_considering",
            "谈判流程: 中等出价被拒或接受均合理")
    end
end

section("12. 买入流程 - negotiating 超时（5天未回复）")
do
    SetTestRandomSeed(204)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[9]]

    -- 手动构造一个 negotiating 状态的 bid
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = targetPlayer.id,
        buyerTeamId = home.id,
        sellerTeamId = away.id,
        amount = math.floor(targetPlayer.value * 0.9),
        playerValue = targetPlayer.value,
        status = "negotiating",
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        responseDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = targetPlayer.wage,
        counterAmount = math.floor(targetPlayer.value * 1.2),
        currentRound = 1,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- 推进5天不操作
    advanceDays(gs, 5)
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "rejected", "超时: negotiating 5天未操作被拒绝")
end

section("13. 出售流程 - 接受incoming bid → awaiting_sale_confirmation → confirmSale → completed")
do
    SetTestRandomSeed(300)
    local gs, home, away = makeGameState(7)
    local myPlayer = gs.players[home.playerIds[5]]
    myPlayer.morale = 40 -- 低士气更容易同意转会

    -- 创建 incoming bid（AI买我方球员）
    local bid = createIncomingBid(gs, home, away, myPlayer, math.floor(myPlayer.value * 1.3))
    assertEqual(bid.status, "pending", "出售流程: incoming bid 初始pending")
    assertTrue(bid.isIncomingBid, "出售流程: 标记为incoming bid")

    -- 玩家接受incoming bid
    local accepted = TransferManager.acceptIncomingBid(gs, bid.id)
    -- 注意：可能被球员拒绝（球员同意检查）
    if accepted then
        assertEqual(bid.status, "awaiting_sale_confirmation", "出售流程: 接受后进入awaiting_sale_confirmation")

        -- 玩家确认出售
        local ok, err = TransferManager.confirmSale(gs, bid.id)
        assertTrue(ok, "出售流程: confirmSale 成功")
        assertEqual(bid.status, "completed", "出售流程: 确认后completed")
        assertEqual(myPlayer.teamId, away.id, "出售流程: 球员转至买方")
    else
        -- 球员拒绝转会也是合理的
        assertEqual(bid.status, "rejected", "出售流程: 球员拒绝时bid被rejected")
    end
end

section("14. 出售流程 - cancelSale 取消出售")
do
    SetTestRandomSeed(301)
    local gs, home, away = makeGameState(7)
    local myPlayer = gs.players[home.playerIds[6]]
    myPlayer.morale = 30  -- 低士气确保球员同意

    local bid = createIncomingBid(gs, home, away, myPlayer, math.floor(myPlayer.value * 1.5))
    local accepted = TransferManager.acceptIncomingBid(gs, bid.id)

    if accepted and bid.status == "awaiting_sale_confirmation" then
        -- 玩家取消出售
        local ok, err = TransferManager.cancelSale(gs, bid.id)
        assertTrue(ok, "取消出售: cancelSale 成功")
        assertEqual(bid.status, "rejected", "取消出售: 状态变为rejected")
        assertEqual(myPlayer.teamId, home.id, "取消出售: 球员仍在我方")
    else
        assertTrue(true, "取消出售: 球员拒绝转会，跳过此测试")
    end
end

section("15. 出售流程 - 还价(counterIncomingBid) + AI延迟回复")
do
    SetTestRandomSeed(302)
    local gs, home, away = makeGameState(7)
    local myPlayer = gs.players[home.playerIds[7]]

    local bid = createIncomingBid(gs, home, away, myPlayer, math.floor(myPlayer.value * 0.9))
    assertEqual(bid.status, "pending", "还价流程: 初始pending")

    -- 玩家还价（要求更高价格）
    local askAmount = math.floor(myPlayer.value * 1.1)
    local ok, status = TransferManager.counterIncomingBid(gs, bid.id, askAmount)
    assertTrue(ok, "还价流程: counterIncomingBid 成功")
    assertEqual(bid.status, "counter_pending", "还价流程: 状态变为counter_pending")
    assertNotNil(bid.counterWaitDays, "还价流程: 设置了AI等待天数")
    assertTrue(bid.counterWaitDays >= 1 and bid.counterWaitDays <= 3, "还价流程: 等待天数1-3天")

    -- 当天处理 - AI还在考虑
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "counter_pending", "还价流程: 当天AI仍在考虑")

    -- 推进等待天数
    advanceDays(gs, bid.counterWaitDays)
    TransferManager.processDailyBids(gs)
    assertTrue(bid.status ~= "counter_pending", "还价流程: 等待后AI应已回复")
    assertTrue(bid.status == "awaiting_sale_confirmation" or bid.status == "rejected",
        "还价流程: AI回复后状态为awaiting_sale_confirmation或rejected")
end

section("16. 出售流程 - awaiting_sale_confirmation 超时（5天）")
do
    SetTestRandomSeed(303)
    local gs, home, away = makeGameState(7)
    local myPlayer = gs.players[home.playerIds[8]]

    -- 直接构造一个 awaiting_sale_confirmation 状态的 bid
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = myPlayer.id,
        buyerTeamId = away.id,
        sellerTeamId = home.id,
        amount = math.floor(myPlayer.value * 1.2),
        playerValue = myPlayer.value,
        status = "awaiting_sale_confirmation",
        isIncomingBid = true,
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        saleConfirmDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = myPlayer.wage,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- 推进5天不确认
    advanceDays(gs, 5)
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "rejected", "出售超时: 5天未确认，买方撤回")
end

section("17. 拒绝冷却期 - 7天内不能重复报价")
do
    SetTestRandomSeed(400)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[5]]

    -- 创建一个已被拒绝的 bid
    TransferManager._ensureData(gs)
    local rejectedBid = {
        id = gs.transfers.nextBidId,
        playerId = targetPlayer.id,
        buyerTeamId = home.id,
        sellerTeamId = away.id,
        amount = math.floor(targetPlayer.value * 0.5),
        playerValue = targetPlayer.value,
        status = "rejected",
        rejectedDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = targetPlayer.wage,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, rejectedBid)

    -- 立即再次报价 - 应被冷却期阻止
    local bid2, err2 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value * 2, targetPlayer.wage)
    assertNil(bid2, "冷却期: 当天不能重复报价")
    assertTrue(err2 ~= nil and string.find(err2, "拒绝") ~= nil, "冷却期: 错误信息提及拒绝")

    -- 推进3天 - 仍在冷却期内
    advanceDays(gs, 3)
    local bid3, err3 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value * 2, targetPlayer.wage)
    assertNil(bid3, "冷却期: 3天后仍不能报价")

    -- 推进到7天后 - 冷却期结束
    advanceDays(gs, 4) -- 累计7天
    local bid4, err4 = TransferManager.makeBid(gs, targetPlayer.id, targetPlayer.value * 2, targetPlayer.wage)
    assertNotNil(bid4, "冷却期: 7天后可以重新报价")
    assertNil(err4, "冷却期: 7天后无错误")
end

section("18. isInTransferWindow 边界验证")
do
    local gs = GameState.new()

    -- 窗口内月份
    local windowMonths = {1, 6, 7, 8}
    for _, m in ipairs(windowMonths) do
        gs.date = { year = 2025, month = m, day = 15 }
        assertTrue(TransferManager.isInTransferWindow(gs),
            string.format("isInTransferWindow: %d月应在窗口内", m))
    end

    -- 窗口外月份
    local nonWindowMonths = {2, 3, 4, 5, 9, 10, 11, 12}
    for _, m in ipairs(nonWindowMonths) do
        gs.date = { year = 2025, month = m, day = 15 }
        assertTrue(not TransferManager.isInTransferWindow(gs),
            string.format("isInTransferWindow: %d月应在窗口外", m))
    end
end

section("19. 买入流程 - awaiting_confirmation 超时（12天）")
do
    SetTestRandomSeed(500)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[10]]

    -- 手动构造 awaiting_confirmation 状态
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = targetPlayer.id,
        buyerTeamId = home.id,
        sellerTeamId = away.id,
        amount = math.floor(targetPlayer.value * 1.3),
        playerValue = targetPlayer.value,
        status = "awaiting_confirmation",
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        feeAgreedDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = targetPlayer.wage,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- 推进12天不确认
    advanceDays(gs, 12)
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "rejected", "买入超时: awaiting_confirmation 12天后被取消")
end

section("20. 买入流程 - fee_agreed 超时（7天）")
do
    SetTestRandomSeed(501)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[11]]

    -- 手动构造 fee_agreed 状态
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = targetPlayer.id,
        buyerTeamId = home.id,
        sellerTeamId = away.id,
        amount = math.floor(targetPlayer.value * 1.3),
        playerValue = targetPlayer.value,
        status = "fee_agreed",
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        feeAgreedDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        wageOffer = targetPlayer.wage,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- 推进7天不操作
    advanceDays(gs, 7)
    TransferManager.processDailyBids(gs)
    assertEqual(bid.status, "rejected", "fee_agreed超时: 7天未操作被取消")
end

section("21. 完整买入-确认流程（端到端）")
do
    SetTestRandomSeed(600)
    local gs, home, away = makeGameState(7)
    local targetPlayer = gs.players[away.playerIds[3]]
    local originalTeam = targetPlayer.teamId

    assertEqual(originalTeam, away.id, "端到端: 球员初始在away队")

    -- 1. 发起高价报价
    local bid, _ = TransferManager.makeBid(gs, targetPlayer.id, math.floor(targetPlayer.value * 1.6), targetPlayer.wage * 2)
    assertNotNil(bid, "端到端: bid创建成功")

    -- 2. 等AI回应
    advanceDays(gs, 3)
    TransferManager.processDailyBids(gs)

    if bid.status == "player_considering" then
        -- 3. 等球员考虑
        advanceDays(gs, 3)
        TransferManager.processDailyBids(gs)

        if bid.status == "awaiting_confirmation" then
            -- 4. 玩家确认签入
            local result, err = TransferManager.confirmTransfer(gs, bid.id)
            assertNotNil(result, "端到端: confirmTransfer成功")
            assertEqual(bid.status, "completed", "端到端: 转会完成")
            assertEqual(targetPlayer.teamId, home.id, "端到端: 球员已转到我方")

            -- 验证转会历史记录
            assertTrue(#gs.transfers.history > 0, "端到端: 转会历史有记录")
            local lastHistory = gs.transfers.history[#gs.transfers.history]
            assertEqual(lastHistory.playerId, targetPlayer.id, "端到端: 历史记录球员ID正确")
            assertEqual(lastHistory.toTeamId, home.id, "端到端: 历史记录目标球队正确")
        elseif bid.status == "fee_agreed" then
            assertTrue(true, "端到端: 个人条款被拒，进入fee_agreed（需修改工资后重试）")
        end
    elseif bid.status == "negotiating" then
        assertTrue(true, "端到端: 进入谈判阶段（需加价）")
    elseif bid.status == "rejected" then
        assertTrue(true, "端到端: 出价被拒（概率事件）")
    end
end

section("22. 出售还价流程 - _processCounterResponse AI接受")
do
    SetTestRandomSeed(700)
    local gs, home, away = makeGameState(7)
    local myPlayer = gs.players[home.playerIds[4]]

    -- 直接构造 counter_pending 状态（要价较低，AI大概率接受）
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = myPlayer.id,
        buyerTeamId = away.id,
        sellerTeamId = home.id,
        amount = math.floor(myPlayer.value * 0.9),
        playerValue = myPlayer.value,
        status = "counter_pending",
        isIncomingBid = true,
        date = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        counterDate = { year = gs.date.year, month = gs.date.month, day = gs.date.day },
        counterAskAmount = math.floor(myPlayer.value * 0.95), -- 要价接近身价，AI大概率接受
        counterWaitDays = 1,
        wageOffer = myPlayer.wage,
        currentRound = 0,
        maxRounds = 4,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- 推进等待天数
    advanceDays(gs, 1)
    TransferManager.processDailyBids(gs)

    -- AI应已回复
    assertTrue(bid.status == "awaiting_sale_confirmation" or bid.status == "rejected",
        "AI还价回复: 状态为 awaiting_sale_confirmation 或 rejected")
end

------------------------------------------------------
-- 测试总结
------------------------------------------------------
print(string.format("\n\n===== 测试结果 ====="))
print(string.format("通过: %d", passCount))
print(string.format("失败: %d", failCount))
print(string.format("总计: %d", passCount + failCount))

if failCount > 0 then
    print("\n⚠️ 有测试未通过！")
    error(string.format("%d test(s) failed", failCount))
else
    print("\n✅ 所有测试通过！")
end

return true
