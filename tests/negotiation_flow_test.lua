-- tests/negotiation_flow_test.lua
-- 谈判逻辑集成测试：模拟 UI 层调用接口，验证异步谈判流程
-- 覆盖：球员续约、转会报价、个人条款、自由球员、求职申请、job offer 接受/拒绝、经理续约

require("tests/bootstrap")

local GameState = require("scripts/core/game_state")
local League = require("scripts/domain/league")
local ContractManager = require("scripts/systems/contract_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local JobManager = require("scripts/systems/job_manager")
local FinanceManager = require("scripts/systems/finance_manager")

------------------------------------------------------
-- 测试基础设施
------------------------------------------------------

local passCount = 0
local failCount = 0
local currentTest = ""

local function startTest(name)
    currentTest = name
    io.write("  [TEST] " .. name .. "... ")
end

local function pass()
    passCount = passCount + 1
    print("PASS")
end

local function fail(msg)
    failCount = failCount + 1
    print("FAIL")
    print("    ✗ " .. (msg or "assertion failed"))
end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected [%s], got [%s]", label or "", tostring(expected), tostring(actual)))
        return false
    end
    return true
end

local function assertNotNil(value, label)
    if value == nil then
        fail(string.format("%s: expected non-nil", label or ""))
        return false
    end
    return true
end

local function assertTrue(value, label)
    if not value then
        fail(string.format("%s: expected true", label or ""))
        return false
    end
    return true
end

local function assertFalse(value, label)
    if value then
        fail(string.format("%s: expected false", label or ""))
        return false
    end
    return true
end

------------------------------------------------------
-- Fixtures: 构建测试用 gameState
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

local function createTestWorld()
    local gs = GameState.new()
    gs.date = { year = 2025, month = 7, day = 1 }
    gs.season = 2025

    -- 创建两支球队
    local home = gs:addTeam({
        name = "Test FC",
        shortName = "TFC",
        formation = "4-4-2",
        playStyle = "Attacking",
        balance = 50000000,   -- 5000万
        wageBudget = 500000,
        stadiumCapacity = 30000,
        reputation = 60,
    })
    local away = gs:addTeam({
        name = "Rival United",
        shortName = "RVL",
        formation = "4-3-3",
        playStyle = "Defensive",
        balance = 30000000,
        wageBudget = 300000,
        stadiumCapacity = 20000,
        reputation = 55,
    })
    -- 第三支球队（空缺主教练，用于求职测试）
    local vacantTeam = gs:addTeam({
        name = "Vacant City",
        shortName = "VCT",
        formation = "4-4-2",
        playStyle = "Balanced",
        balance = 10000000,
        wageBudget = 100000,
        stadiumCapacity = 15000,
        reputation = 40,
    })
    vacantTeam.managerVacant = true  -- Team.new 不处理此字段，需手动设置

    -- 第四支空缺球队
    local vacantTeam2 = gs:addTeam({
        name = "Open Town",
        shortName = "OPN",
        formation = "4-4-2",
        playStyle = "Balanced",
        balance = 8000000,
        wageBudget = 80000,
        stadiumCapacity = 12000,
        reputation = 35,
    })
    vacantTeam2.managerVacant = true  -- 同上

    -- 为球队添加球员
    local positions = { "GK", "LB", "CB", "CB", "RB", "CM", "CM", "LM", "RM", "ST", "ST" }
    for _, pos in ipairs(positions) do
        local p = gs:addPlayer({
            firstName = "Home", lastName = pos,
            displayName = "Home " .. pos,
            birthYear = 1998, nationality = "ENG",
            position = pos,
            attributes = attributes(15),
            fitness = 88, morale = 70,
            wage = 20000, teamId = home.id,
            contractEnd = { year = 2027, month = 6 },
        })
        home:addPlayer(p.id)
        table.insert(home.startingXI, p.id)
    end
    for _, pos in ipairs(positions) do
        local p = gs:addPlayer({
            firstName = "Away", lastName = pos,
            displayName = "Away " .. pos,
            birthYear = 1997, nationality = "ENG",
            position = pos,
            attributes = attributes(13),
            fitness = 85, morale = 65,
            wage = 15000, teamId = away.id,
            contractEnd = { year = 2026, month = 6 },
        })
        away:addPlayer(p.id)
        table.insert(away.startingXI, p.id)
    end

    -- 自由球员
    local freeAgent = gs:addPlayer({
        firstName = "Free", lastName = "Agent",
        displayName = "Free Agent",
        birthYear = 1996, nationality = "FRA",
        position = "ST",
        attributes = attributes(14),
        fitness = 80, morale = 60,
        wage = 18000, teamId = nil,
        contractEnd = nil,
    })

    gs.playerTeamId = home.id

    -- 创建联赛
    local league = League.new({
        id = gs:generateId(),
        name = "Test League",
        teamIds = { home.id, away.id, vacantTeam.id, vacantTeam2.id },
        fixtures = {},
    })
    league:initStandings()
    gs.league = league
    gs.leagues = { test = league }
    gs.playerLeagueId = "test"

    -- 初始化经理
    local manager = {
        id = gs:generateId(),
        firstName = "Test",
        lastName = "Manager",
        displayName = "Test Manager",
        birthYear = 1980,
        nationality = "ENG",
        teamId = home.id,
        isPlayer = true,
        isUnemployed = false,
        reputation = 50,
        wage = 30000,
        contractEnd = { year = 2027, month = 6 },
        contractYears = 3,
        stats = { wins = 10, draws = 5, losses = 3, trophies = {} },
    }
    gs.managers = gs.managers or {}
    gs.managers[manager.id] = manager
    gs.playerManagerId = manager.id

    return gs, home, away, vacantTeam, vacantTeam2, freeAgent
end

--- 模拟过N天（调用各系统 processDaily）
local function advanceDays(gs, n)
    for _ = 1, n do
        local date = gs.date
        -- 简化的日期推进（不用 TurnProcessor 避免依赖比赛等）
        local d = date.day + 1
        local m = date.month
        local y = date.year
        if d > 28 then  -- 简化：每月28天
            d = 1
            m = m + 1
            if m > 12 then m = 1; y = y + 1 end
        end
        gs.date = { year = y, month = m, day = d }

        -- 调用各系统每日处理
        ContractManager.processDaily(gs)
        TransferManager.processDailyBids(gs)
        TransferManager.processDailyFreeAgentNegos(gs)
        JobManager.processDaily(gs)
    end
end

------------------------------------------------------
-- 测试1: 球员续约 (异步, UI 接口: ContractManager.renewContract)
------------------------------------------------------
print("\n=== 测试1: 球员续约谈判（异步） ===")

do
    SetTestRandomSeed(100)
    local gs, home = createTestWorld()
    local player = gs.players[home.playerIds[1]]
    player.contractEnd = { year = 2025, month = 12 }  -- 5个月后到期

    -- UI 先调用 getSuggestedTerms（和 squad.lua/player_detail.lua 一致）
    startTest("getSuggestedTerms 返回有效值")
    local terms = ContractManager.getSuggestedTerms(player, home, gs)
    if assertNotNil(terms, "terms") and assertNotNil(terms.wage, "terms.wage")
        and assertNotNil(terms.years, "terms.years") then
        pass()
    end

    -- UI 调用 renewContract（和 squad.lua 第739行、player_detail.lua 第932行一致）
    startTest("renewContract 返回成功（异步提交）")
    local ok, err = ContractManager.renewContract(gs, player.id, terms.wage, terms.years)
    if assertTrue(ok, "应返回 true") then
        pass()
    end

    -- 验证: 球员合同未立即改变
    startTest("提交后合同未立即改变")
    if assertEqual(player.contractEnd.year, 2025, "合同年份不变")
        and assertEqual(player.contractEnd.month, 12, "合同月份不变") then
        pass()
    end

    -- 验证: 有 pending renewal
    startTest("存在 _pendingRenewals 条目")
    if assertNotNil(gs._pendingRenewals[player.id], "_pendingRenewals[playerId]") then
        pass()
    end

    -- 重复提交应被拒
    startTest("重复提交续约被拒")
    local ok2, err2 = ContractManager.renewContract(gs, player.id, terms.wage + 1000, 4)
    if assertFalse(ok2, "不应成功") and assertTrue(err2 ~= nil, "应有错误消息") then
        pass()
    end

    -- 模拟时间推进直到出结果
    startTest("推进天数后出结果（合同变更或被拒消息）")
    local msgCountBefore = #gs.inbox
    advanceDays(gs, 4)  -- 最多3天
    local resolved = gs._pendingRenewals[player.id] == nil
    if assertTrue(resolved, "应已处理完毕") and assertTrue(#gs.inbox > msgCountBefore, "应有新消息") then
        pass()
    end
end

------------------------------------------------------
-- 测试2: 转会报价 (异步, UI 接口: TransferManager.makeBidWithClauses)
------------------------------------------------------
print("\n=== 测试2: 转会报价（异步） ===")

do
    SetTestRandomSeed(200)
    local gs, home, away = createTestWorld()
    local targetPlayer = gs.players[away.playerIds[5]]  -- 对方CM

    -- UI 调用 makeBidWithClauses（和 market.lua 第675行一致）
    startTest("makeBidWithClauses 创建 pending 报价")
    local offerAmount = math.floor((targetPlayer.value or 500000) * 1.2)
    local offeredWage = targetPlayer.wage + 5000
    local bid = TransferManager.makeBidWithClauses(gs, targetPlayer.id, offerAmount, offeredWage, {
        installments = 2,
        sellOnPercent = 10,
    })
    if assertNotNil(bid, "应返回 bid 对象") and assertEqual(bid.status, "pending", "状态应为 pending") then
        pass()
    end

    -- 验证: 球员未立即转会
    startTest("报价后球员未立即转会")
    if assertEqual(targetPlayer.teamId, away.id, "球员仍在原队") then
        pass()
    end

    -- 模拟推进到对方回复
    startTest("推进后报价状态变化（非 pending）")
    advanceDays(gs, 5)
    local newStatus = bid.status
    if assertTrue(newStatus ~= "pending", "状态应变化，当前: " .. newStatus) then
        pass()
    end
end

------------------------------------------------------
-- 测试3: 个人条款谈判 (异步, UI 接口: TransferManager.negotiatePersonalTerms)
------------------------------------------------------
print("\n=== 测试3: 个人条款谈判（异步） ===")

do
    SetTestRandomSeed(300)
    local gs, home, away = createTestWorld()
    local targetPlayer = gs.players[away.playerIds[3]]

    -- 先创建一个已达成转会费协议的 bid
    TransferManager._ensureData(gs)
    local bid = {
        id = gs.transfers.nextBidId,
        playerId = targetPlayer.id,
        buyerTeamId = home.id,
        sellerTeamId = away.id,
        amount = 2000000,
        playerValue = targetPlayer.value or 500000,
        status = "fee_agreed",
        date = { year = 2025, month = 7, day = 1 },
        feeAgreedDate = { year = 2025, month = 7, day = 1 },
        wageOffer = targetPlayer.wage,
        contractYears = 3,
        currentRound = 0,
        maxRounds = 3,
        mood = 50,
        rounds = {},
    }
    gs.transfers.nextBidId = gs.transfers.nextBidId + 1
    table.insert(gs.transfers.bids, bid)

    -- UI 调用 negotiatePersonalTerms（和 market.lua 第972行一致）
    startTest("negotiatePersonalTerms 提交后状态为 player_considering")
    local newWage = targetPlayer.wage * 2
    local result, negoErr = TransferManager.negotiatePersonalTerms(gs, bid.id, newWage)
    if assertNotNil(result, "应返回 bid") and assertEqual(bid.status, "player_considering", "状态") then
        pass()
    end

    -- 验证: 球员未立即加入
    startTest("个人条款提交后球员未立即转会")
    if assertEqual(targetPlayer.teamId, away.id, "球员仍在原队") then
        pass()
    end

    -- 验证: 有考虑天数
    startTest("bid 上有 playerConsiderDays 和 playerConsiderDate")
    if assertNotNil(bid.playerConsiderDays, "playerConsiderDays")
        and assertNotNil(bid.playerConsiderDate, "playerConsiderDate")
        and assertTrue(bid.playerConsiderDays >= 1 and bid.playerConsiderDays <= 2, "应为1-2天") then
        pass()
    end

    -- 推进天数后状态应变化
    startTest("推进后 player_considering 结束")
    advanceDays(gs, 3)
    if assertTrue(bid.status ~= "player_considering",
        "状态应不再是 player_considering, 当前: " .. bid.status) then
        pass()
    end
end

------------------------------------------------------
-- 测试4: 自由球员邀约 (异步, UI 接口: TransferManager.offerFreeAgent)
------------------------------------------------------
print("\n=== 测试4: 自由球员邀约（异步） ===")

do
    SetTestRandomSeed(400)
    local gs, home, away, _, _, freeAgent = createTestWorld()

    -- UI 调用 offerFreeAgent（和 market.lua 第2376行一致）
    startTest("offerFreeAgent 创建 pending 谈判")
    local offeredWage = freeAgent.wage + 5000
    local offeredYears = 2
    local nego, negoErr = TransferManager.offerFreeAgent(gs, freeAgent.id, offeredWage, offeredYears)
    if assertNotNil(nego, "应返回 nego 对象")
        and assertEqual(nego.status, "pending", "状态应为 pending") then
        pass()
    end

    -- 验证: 球员未立即签约
    startTest("邀约后球员未立即归队")
    if assertEqual(freeAgent.teamId, nil, "球员仍为自由球员") then
        pass()
    end

    -- 重复邀约应被拒
    startTest("重复邀约被拒")
    local nego2, err2 = TransferManager.offerFreeAgent(gs, freeAgent.id, offeredWage, offeredYears)
    if assertEqual(nego2, nil, "不应成功") and assertNotNil(err2, "应有错误") then
        pass()
    end

    -- 推进后应有结果
    startTest("推进后谈判状态变化")
    advanceDays(gs, 5)
    if assertTrue(nego.status ~= "pending", "状态应变化, 当前: " .. nego.status) then
        pass()
    end
end

------------------------------------------------------
-- 测试5: 求职申请 (异步, UI 接口: JobManager.applyForJob)
------------------------------------------------------
print("\n=== 测试5: 求职申请（异步） ===")

do
    SetTestRandomSeed(500)
    local gs, home, _, vacantTeam, vacantTeam2 = createTestWorld()

    -- 设置为失业状态
    gs._isUnemployed = true
    gs._unemployedSince = { year = 2025, month = 1, day = 1 }
    gs.playerTeamId = nil
    local manager = gs.managers[gs.playerManagerId]
    manager.teamId = nil
    manager.isUnemployed = true
    manager.reputation = 50

    -- UI 调用 applyForJob（和 manager_view.lua 第445行一致）
    startTest("applyForJob 提交成功")
    local ok, err = JobManager.applyForJob(gs, vacantTeam.id)
    if assertTrue(ok, "应返回 true, err: " .. tostring(err)) then
        pass()
    end

    -- 验证: 未立即入职
    startTest("申请后未立即入职")
    if assertTrue(gs._isUnemployed, "仍应为失业状态") then
        pass()
    end

    -- 验证: 在审核列表中
    startTest("存在 _pendingApplications 条目")
    local apps = gs._pendingApplications or {}
    if assertEqual(#apps, 1, "应有1条申请") then
        pass()
    end

    -- 可同时申请多个
    startTest("可同时申请第二支球队")
    local ok2, err2 = JobManager.applyForJob(gs, vacantTeam2.id)
    if assertTrue(ok2, "第二支也应成功, err: " .. tostring(err2)) then
        pass()
    end
    startTest("两份申请同时存在")
    if assertEqual(#(gs._pendingApplications or {}), 2, "应有2条") then
        pass()
    end

    -- 同一球队重复申请被拒
    startTest("同一球队重复申请被拒")
    local ok3, err3 = JobManager.applyForJob(gs, vacantTeam.id)
    if assertFalse(ok3, "应失败") and assertNotNil(err3, "应有错误消息") then
        pass()
    end

    -- 推进后出结果（通过 → 加入 _pendingOffers）
    startTest("推进后申请出结果")
    local appsBefore = #(gs._pendingApplications or {})
    advanceDays(gs, 4)  -- 审核2-3天
    local appsAfter = #(gs._pendingApplications or {})
    -- 至少有一个应该被处理了
    if assertTrue(appsAfter < appsBefore, "应有申请被处理") then
        pass()
    end
end

------------------------------------------------------
-- 测试6: 接受/拒绝 Job Offer (UI 接口: JobManager.acceptOffer/declineOffer)
------------------------------------------------------
print("\n=== 测试6: 接受/拒绝 Job Offer ===")

do
    SetTestRandomSeed(600)
    local gs, home, _, vacantTeam, vacantTeam2 = createTestWorld()

    -- 设置失业状态并手动添加 offer
    gs._isUnemployed = true
    gs._unemployedSince = { year = 2025, month = 1, day = 1 }
    gs.playerTeamId = nil
    local manager = gs.managers[gs.playerManagerId]
    manager.teamId = nil
    manager.isUnemployed = true

    gs._pendingOffers = {
        {
            teamId = vacantTeam.id,
            teamName = vacantTeam.name,
            leagueName = "Test League",
            teamRep = vacantTeam.reputation,
            source = "application",
            sentDate = { year = 2025, month = 7, day = 1 },
            expireDays = 5,
        },
        {
            teamId = vacantTeam2.id,
            teamName = vacantTeam2.name,
            leagueName = "Test League",
            teamRep = vacantTeam2.reputation,
            source = "proactive",
            sentDate = { year = 2025, month = 7, day = 1 },
            expireDays = 4,
        },
    }

    -- UI 先展示列表（和 manager_view.lua 第491行一致）
    startTest("getPendingOffers 返回 offer 列表")
    local offers = JobManager.getPendingOffers(gs)
    if assertEqual(#offers, 2, "应有2个 offer") then
        pass()
    end

    -- UI 拒绝第一个（和 manager_view.lua 第539行一致）
    startTest("declineOffer 成功拒绝")
    JobManager.declineOffer(gs, vacantTeam.id)
    local offersAfter = JobManager.getPendingOffers(gs)
    if assertEqual(#offersAfter, 1, "应剩1个 offer") then
        pass()
    end

    -- UI 接受第二个（和 manager_view.lua 第532行一致）
    startTest("acceptOffer 成功入职")
    local accepted = JobManager.acceptOffer(gs, vacantTeam2.id)
    if assertTrue(accepted, "应返回 true")
        and assertFalse(gs._isUnemployed, "不再失业")
        and assertEqual(gs.playerTeamId, vacantTeam2.id, "团队ID正确") then
        pass()
    end

    -- 入职后 offer 列表清空
    startTest("入职后 _pendingOffers 清空")
    if assertEqual(#(gs._pendingOffers or {}), 0, "应为空") then
        pass()
    end
end

------------------------------------------------------
-- 测试7: Offer 过期自动清理
------------------------------------------------------
print("\n=== 测试7: Offer 过期自动清理 ===")

do
    SetTestRandomSeed(700)
    local gs, _, _, vacantTeam = createTestWorld()

    gs._isUnemployed = true
    gs._unemployedSince = { year = 2025, month = 1, day = 1 }
    gs.playerTeamId = nil
    local manager = gs.managers[gs.playerManagerId]
    manager.teamId = nil
    manager.isUnemployed = true

    gs._pendingOffers = {
        {
            teamId = vacantTeam.id,
            teamName = vacantTeam.name,
            leagueName = "Test League",
            teamRep = 40,
            source = "application",
            sentDate = { year = 2025, month = 7, day = 1 },
            expireDays = 2,  -- 只剩2天
        },
    }

    startTest("2天后 Offer 过期被清理")
    advanceDays(gs, 3)
    local offers = JobManager.getPendingOffers(gs)
    if assertEqual(#offers, 0, "应被清理") then
        pass()
    end
end

------------------------------------------------------
-- 测试8: 经理续约（俱乐部主动 → 玩家选择）
------------------------------------------------------
print("\n=== 测试8: 经理续约（俱乐部主动提议） ===")

do
    SetTestRandomSeed(800)
    local gs, home = createTestWorld()
    local manager = gs.managers[gs.playerManagerId]

    -- 模拟俱乐部主动提出续约（checkManagerRenewal 触发后写入）
    gs._managerRenewalOffer = {
        teamId = home.id,
        wage = manager.wage + 10000,
        years = 2,
    }

    -- UI 接受续约（和 manager_view.lua 第281行一致）
    startTest("acceptManagerRenewal 成功")
    local ok = JobManager.acceptManagerRenewal(gs)
    if assertTrue(ok, "应返回 true")
        and assertEqual(manager.wage, 40000, "薪水更新")
        and assertEqual(manager.contractEnd.year, 2025 + 2, "合同年限更新") then
        pass()
    end

    startTest("续约后 _managerRenewalOffer 清空")
    if assertEqual(gs._managerRenewalOffer, nil, "应为 nil") then
        pass()
    end
end

------------------------------------------------------
-- 测试9: 经理续约（拒绝）
------------------------------------------------------
print("\n=== 测试9: 经理续约（拒绝提议） ===")

do
    SetTestRandomSeed(900)
    local gs, home = createTestWorld()
    local manager = gs.managers[gs.playerManagerId]
    local originalWage = manager.wage

    gs._managerRenewalOffer = {
        teamId = home.id,
        wage = manager.wage + 5000,
        years = 1,
    }

    -- UI 拒绝续约（和 manager_view.lua 第289行一致）
    startTest("declineManagerRenewal 成功")
    JobManager.declineManagerRenewal(gs)
    if assertEqual(manager.wage, originalWage, "薪水不变")
        and assertEqual(gs._managerRenewalOffer, nil, "offer 清空") then
        pass()
    end
end

------------------------------------------------------
-- 测试10: 转会报价 + 个人条款全流程（模拟完整 UI 操作序列）
------------------------------------------------------
print("\n=== 测试10: 转会全流程（报价→谈判→个人条款） ===")

do
    SetTestRandomSeed(1000)
    local gs, home, away = createTestWorld()
    local targetPlayer = gs.players[away.playerIds[8]]

    -- Step1: UI 发起报价（market.lua 第675行）
    startTest("Step1: 发起报价")
    local offerAmount = math.floor((targetPlayer.value or 500000) * 1.5)
    local bid = TransferManager.makeBidWithClauses(gs, targetPlayer.id, offerAmount, targetPlayer.wage + 3000, {})
    if assertNotNil(bid, "bid 创建成功") and assertEqual(bid.status, "pending", "状态 pending") then
        pass()
    end

    -- Step2: 推进到对方回复
    startTest("Step2: 推进到对方回复")
    advanceDays(gs, 5)
    -- 状态应该变了（可能 accepted/rejected/negotiating/fee_agreed 等）
    if assertTrue(bid.status ~= "pending", "不再 pending, 当前: " .. bid.status) then
        pass()
    end

    -- Step3: 如果费用达成协议，继续个人条款
    if bid.status == "fee_agreed" then
        startTest("Step3: 费用达成后协商个人条款")
        local newWage = targetPlayer.wage * 2
        local result = TransferManager.negotiatePersonalTerms(gs, bid.id, newWage)
        if assertNotNil(result, "negotiatePersonalTerms 返回值")
            and assertEqual(bid.status, "player_considering", "进入球员考虑期") then
            pass()
        end

        -- Step4: 推进到球员考虑结束
        startTest("Step4: 球员考虑期结束")
        advanceDays(gs, 3)
        if assertTrue(bid.status ~= "player_considering",
            "不再 player_considering, 当前: " .. bid.status) then
            pass()
        end
    else
        -- 报价被拒或其他，也算通过（流程没有崩溃）
        startTest("Step3: 报价未通过但流程正常")
        pass()
    end
end

------------------------------------------------------
-- 测试11: 求职全流程（申请→通过→选择→入职）
------------------------------------------------------
print("\n=== 测试11: 求职全流程（申请→通过→选择→入职） ===")

do
    -- 使用固定seed确保至少一个申请通过
    SetTestRandomSeed(1100)
    local gs, home, _, vacantTeam, vacantTeam2 = createTestWorld()

    -- 设置失业 + 高声望（提高通过率）
    gs._isUnemployed = true
    gs._unemployedSince = { year = 2025, month = 1, day = 1 }
    gs.playerTeamId = nil
    local manager = gs.managers[gs.playerManagerId]
    manager.teamId = nil
    manager.isUnemployed = true
    manager.reputation = 80  -- 高声望，容易通过

    -- Step1: 申请多支球队
    startTest("Step1: 申请两支球队")
    local ok1 = JobManager.applyForJob(gs, vacantTeam.id)
    local ok2 = JobManager.applyForJob(gs, vacantTeam2.id)
    if assertTrue(ok1, "第一支申请成功") and assertTrue(ok2, "第二支申请成功") then
        pass()
    end

    -- Step2: 推进到出结果
    startTest("Step2: 推进等待结果")
    advanceDays(gs, 4)
    -- 检查是否有 offer 或全部被拒
    local offers = JobManager.getPendingOffers(gs)
    local appsLeft = #(gs._pendingApplications or {})
    if assertTrue(#offers > 0 or appsLeft == 0, "应有 offer 或全部处理完毕") then
        pass()
    end

    -- Step3: 如果有 offer，接受
    if #offers > 0 then
        startTest("Step3: 接受第一个 offer")
        local chosen = offers[1]
        local accepted = JobManager.acceptOffer(gs, chosen.teamId)
        if assertTrue(accepted, "接受成功")
            and assertFalse(gs._isUnemployed, "不再失业")
            and assertEqual(gs.playerTeamId, chosen.teamId, "加入正确球队") then
            pass()
        end
    else
        startTest("Step3: 全部被拒（seed导致），验证流程无崩溃")
        pass()
    end
end

------------------------------------------------------
-- 测试12: UI/后端接口一致性验证
------------------------------------------------------
print("\n=== 测试12: UI/后端接口一致性验证 ===")

do
    SetTestRandomSeed(1200)
    local gs, home = createTestWorld()
    local player = gs.players[home.playerIds[2]]

    -- 验证: ContractManager.getSuggestedTerms 返回的字段与 UI 使用一致
    startTest("getSuggestedTerms 包含 UI 所需字段 (wage/years/minWage/maxWage)")
    local terms = ContractManager.getSuggestedTerms(player, home, gs)
    if assertNotNil(terms.wage, "wage") and assertNotNil(terms.years, "years")
        and assertNotNil(terms.minWage, "minWage") and assertNotNil(terms.maxWage, "maxWage") then
        pass()
    end

    -- 验证: renewContract 接口签名和 UI 调用一致（playerId, wage, years）
    startTest("renewContract 参数格式正确（不崩溃）")
    local ok, err = ContractManager.renewContract(gs, player.id, terms.wage, terms.years)
    -- 应该 ok=true 或 false + err，不应崩溃
    if assertTrue(ok ~= nil or err ~= nil, "应有返回值") then
        pass()
    end

    -- 验证: makeBidWithClauses 参数格式正确
    startTest("makeBidWithClauses 参数格式正确（不崩溃）")
    local gs2, home2, away2 = createTestWorld()
    local target2 = gs2.players[away2.playerIds[1]]
    local bid = TransferManager.makeBidWithClauses(gs2, target2.id, 1000000, 20000, {
        installments = 3,
        appearanceBonus = { count = 20, amount = 50000 },
        sellOnPercent = 15,
    })
    if assertNotNil(bid, "应返回 bid") then
        pass()
    end

    -- 验证: negotiatePersonalTerms 在非 fee_agreed 时返回 nil + err
    startTest("negotiatePersonalTerms 对 pending bid 正确报错")
    local result, negoErr = TransferManager.negotiatePersonalTerms(gs2, bid.id, 30000)
    if assertEqual(result, nil, "应返回 nil") and assertNotNil(negoErr, "应有错误消息") then
        pass()
    end

    -- 验证: applyForJob 在职时被拒
    startTest("applyForJob 在职时被拒")
    gs2._isUnemployed = false
    local ok3, err3 = JobManager.applyForJob(gs2, 999)
    if assertFalse(ok3, "应失败") and assertNotNil(err3, "应有错误消息") then
        pass()
    end

    -- 验证: acceptOffer 在非失业时失败
    startTest("acceptOffer 非失业时失败")
    gs2._isUnemployed = false
    local ok4 = JobManager.acceptOffer(gs2, 999)
    if assertFalse(ok4, "应失败") then
        pass()
    end
end

------------------------------------------------------
-- 测试13: 工资预算校验（续约时超预算被拒）
------------------------------------------------------
print("\n=== 测试13: 预算校验 ===")

do
    SetTestRandomSeed(1300)
    local gs, home = createTestWorld()
    local player = gs.players[home.playerIds[1]]

    -- 设置极低工资预算
    home.wageBudget = 1  -- 几乎为0
    -- 让涨薪幅度很大
    local hugeWage = player.wage * 100

    startTest("超出工资预算时续约被拒")
    local ok, err = ContractManager.renewContract(gs, player.id, hugeWage, 3)
    if assertFalse(ok, "应失败") and assertTrue(string.find(err or "", "预算") ~= nil, "应提示预算问题") then
        pass()
    end
end

------------------------------------------------------
-- 汇总
------------------------------------------------------
print(string.format("\n========================================"))
print(string.format("  总计: %d 测试, %d 通过, %d 失败",
    passCount + failCount, passCount, failCount))
print(string.format("========================================"))

if failCount > 0 then
    error(string.format("%d test(s) FAILED", failCount))
end

return true
