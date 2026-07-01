-- systems/transfers/misc_clauses.lua
-- 违约金/分期/竞争报价/预签/预算/关系/球探网络，从 transfer_manager.lua 拆分。

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")
local StaffManager = require("scripts/systems/staff_manager")
local Helpers = require("scripts/systems/transfers/transfer_helpers")
local randInt = Helpers.randInt
local fmtMoney = Helpers.fmtMoney

return function(TransferManager)
    ------------------------------------------------------
    -- ★ 解约金条款系统
    ------------------------------------------------------

    --- 为球员设置解约金条款（续约/签约时调用）
    function TransferManager.setReleaseClause(gameState, playerId, amount)
        local player = gameState.players[playerId]
        if not player then return false end
        player.releaseClause = amount  -- nil 表示无解约金
        return true
    end

    --- 获取球员解约金
    function TransferManager.getReleaseClause(gameState, playerId)
        local player = gameState.players[playerId]
        if not player then return nil end
        return player.releaseClause
    end

    --- 触发解约金购买（直接购买，无需谈判）
    function TransferManager.triggerReleaseClause(gameState, playerId)
        TransferManager._ensureData(gameState)

        -- 转会窗口检查
        local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
        if not windowOk then return nil, windowErr end

        -- 预签约锁定检查
        local lockOk, lockErr = TransferManager._checkPreContractLock(gameState, playerId)
        if not lockOk then return nil, lockErr end

        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end
        if not player.releaseClause then return nil, "该球员没有解约金条款" end
        if player.teamId == gameState.playerTeamId then return nil, "不能触发自己球员的解约金" end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
        if not moveOk then return nil, moveErr end

        local team = gameState:getPlayerTeam()
        if not team then return nil, "无法获取球队" end

        local amount = player.releaseClause
        local budget = TransferManager._getTransferBudget(gameState, team)
        if amount > budget then
            return nil, string.format("解约金 %s 超出转会预算 %s", fmtMoney(amount), fmtMoney(budget))
        end

        -- 解约金条款 → 卖方必须接受（合同规定）
        local bid = {
            id = gameState.transfers.nextBidId,
            playerId = playerId,
            buyerTeamId = gameState.playerTeamId,
            sellerTeamId = player.teamId,
            amount = amount,
            playerValue = player.value,
            status = "accepted",
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            isReleaseClause = true,
            currentRound = 0,
            maxRounds = 0,
            mood = 0,
            rounds = {},
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.bids, bid)

        local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
        if not consent then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return nil, reason
        end

        -- 解约金强制俱乐部接受，但球员仍需同意加盟
        TransferManager._completeTransfer(gameState, bid, { suppressMessage = true })

        gameState:sendMessage({
            category = "transfer",
            title = "解约金触发!",
            body = string.format("你触发了 %s 的解约金条款（%s），转会自动完成。",
                player.displayName, fmtMoney(amount)),
            priority = "normal",
        })

        return bid
    end

    --- 在 AI 报价时检查解约金（若报价 >= 解约金则自动接受）
    function TransferManager._checkReleaseClause(player, bidAmount)
        if player.releaseClause and bidAmount >= player.releaseClause then
            return true
        end
        return false
    end

    ------------------------------------------------------
    -- ★ 分期付款 / 附加条款
    ------------------------------------------------------

    --- 创建带附加条款的报价
    --- @param clauses table 附加条款配置
    ---   clauses.installments: number 分期数（2-4期）
    ---   clauses.appearanceBonus: {count=number, amount=number} 出场奖金
    ---   clauses.sellOnPercent: number 未来转售分成百分比 (0-50)
    function TransferManager.makeBidWithClauses(gameState, playerId, amount, wageOffer, clauses)
        TransferManager._ensureData(gameState)
        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end

        -- 先创建基础报价
        local bid, bidErr = TransferManager.makeBid(gameState, playerId, amount, wageOffer)
        if not bid then return nil, bidErr or "创建报价失败" end

        -- 附加条款
        clauses = clauses or {}

        -- 分期付款
        if clauses.installments and clauses.installments >= 2 then
            local numInstall = math.min(clauses.installments, 4)
            local perInstall = math.floor(amount / numInstall)
            local installList = {}
            for i = 1, numInstall do
                local totalMonth = gameState.date.month + (i - 1) * 6
                table.insert(installList, {
                    amount = (i == numInstall) and (amount - perInstall * (numInstall - 1)) or perInstall,
                    dueDate = {
                        year = gameState.date.year + math.floor((totalMonth - 1) / 12),
                        month = ((totalMonth - 1) % 12) + 1,
                        day = 1,
                    },
                })
            end
            bid.installments = installList
        end

        -- 出场奖金
        if clauses.appearanceBonus then
            bid.appearanceBonus = {
                count = clauses.appearanceBonus.count or 25,
                amount = clauses.appearanceBonus.amount or math.floor(amount * 0.1),
            }
        end

        -- 未来转售分成
        if clauses.sellOnPercent and clauses.sellOnPercent > 0 then
            bid.sellOnPercent = math.min(50, math.max(0, clauses.sellOnPercent))
        end

        -- 附加条款让AI更容易接受（降低价格需求）
        local bonusValue = 0
        if bid.installments then bonusValue = bonusValue + amount * 0.05 end  -- 分期对卖方不利
        if bid.appearanceBonus then bonusValue = bonusValue + bid.appearanceBonus.amount * 0.5 end
        if bid.sellOnPercent then bonusValue = bonusValue + player.value * bid.sellOnPercent / 100 * 0.3 end

        -- 将附加条款价值加入AI评估的总价
        bid._effectiveValue = amount + bonusValue

        return bid
    end

    --- 玩家阵容人数阈值提醒（28/30/33）：上升沿触发，每个转会窗每个档位仅提醒一次
    --- 仅在转会窗内提醒（窗外靠 TimeBlocker 阻断兜底）
    function TransferManager._notifyPlayerSquadThresholds(gameState)
        local team = gameState.teams[gameState.playerTeamId]
        if not team then return end
        local windowKey = TransferManager.getTransferWindowKey(gameState)
        if not windowKey then return end

        -- 跨窗重置已提醒档位
        if team._squadNotifyWindow ~= windowKey then
            team._squadNotifyWindow = windowKey
            team._squadNotifyLevel = 0
        end

        local Team = require("scripts/domain/team")
        local hardCap = Team.getFirstTeamMax()          -- 30 注册上限
        local warningCap = Team.getPlayerWindowSquadMax()  -- 33 提醒档位
        local count = #team.playerIds

        local level = 0
        if count >= warningCap then level = warningCap
        elseif count >= hardCap then level = hardCap
        elseif count >= 28 then level = 28 end

        if level <= (team._squadNotifyLevel or 0) then return end
        team._squadNotifyLevel = level

        local body
        if level >= warningCap then
            body = string.format(
                "一线队已达 %d 人，明显超出注册上限 %d 人。转会窗内交易仍可完成，但关窗前必须减回 %d 人（出售 / 解约 / 下放青训）。",
                count, hardCap, hardCap)
        elseif level >= hardCap then
            body = string.format(
                "一线队已达注册上限 %d 人。转会窗内交易仍可完成，但关窗前必须减回 %d 人（出售 / 解约 / 下放青训）。",
                hardCap, hardCap)
        else
            body = string.format(
                "一线队已达 %d 人，接近常规上限 %d 人。可考虑挂牌出售或下放青训，提前腾出名额。",
                count, hardCap)
        end

        gameState:sendMessage({
            category = "transfer",
            title = "阵容人数提醒",
            body = body,
            priority = (level >= hardCap) and "high" or "normal",
        })
    end

    --- 汇总某队未付分期负债总额（已承诺但尚未支付的现金义务）
    --- @return number 未付分期总额
    function TransferManager.getPendingPayablesTotal(team)
        if not team or not team._pendingPayables then return 0 end
        local total = 0
        for _, p in ipairs(team._pendingPayables) do
            total = total + (p.amount or 0)
        end
        return total
    end

    --- 处理分期付款到期（每月初调用）
    function TransferManager.processInstallments(gameState)
        for _, team in pairs(gameState.teams) do
            -- 处理应付款
            if team._pendingPayables then
                local paid = {}
                for i, p in ipairs(team._pendingPayables) do
                    local due = p.dueDate
                    if gameState.date.year > due.year or
                       (gameState.date.year == due.year and gameState.date.month >= due.month) then
                        -- 余额不足警告（仅对玩家球队发送）
                        if team.balance < p.amount and team.id == gameState.playerTeamId then
                            gameState:sendMessage({
                                category = "finance",
                                title = "财务危机警告",
                                body = string.format(
                                    "转会分期付款 %s 到期，但球队余额仅 %s。强制扣款将导致负债！",
                                    fmtMoney(p.amount), fmtMoney(team.balance)),
                                priority = "high",
                            })
                        end
                        team.balance = team.balance - p.amount
                        team.seasonExpense = (team.seasonExpense or 0) + p.amount
                        TransferManager._addTransferTransaction(team, -p.amount, "转会分期付款", {
                            year = gameState.date.year,
                            month = gameState.date.month,
                            day = gameState.date.day,
                        }, gameState)
                        -- 对方收款
                        local receiver = gameState.teams[p.toTeamId]
                        if receiver then
                            FinanceManager.processTransferIn(gameState, receiver.id, p.amount, "分期收款")
                            TransferManager._addTransferTransaction(receiver, p.amount, "转会分期收款", {
                                year = gameState.date.year,
                                month = gameState.date.month,
                                day = gameState.date.day,
                            }, gameState)
                            if receiver._pendingReceivables then
                                for r = #receiver._pendingReceivables, 1, -1 do
                                    local receivable = receiver._pendingReceivables[r]
                                    if receivable.playerId == p.playerId and
                                       receivable.fromTeamId == team.id and
                                       receivable.amount == p.amount then
                                        table.remove(receiver._pendingReceivables, r)
                                        break
                                    end
                                end
                            end
                        end
                        table.insert(paid, i)
                    end
                end
                for j = #paid, 1, -1 do
                    table.remove(team._pendingPayables, paid[j])
                end
            end
        end
    end

    ------------------------------------------------------
    -- ★ 竞争性报价（多队争抢）
    ------------------------------------------------------

    --- 获取指定球员的所有活跃报价（含AI）
    function TransferManager.getCompetingBids(gameState, playerId)
        TransferManager._ensureData(gameState)
        local result = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == playerId and
               (bid.status == "pending" or bid.status == "negotiating") then
                table.insert(result, bid)
            end
        end
        table.sort(result, function(a, b) return a.amount > b.amount end)
        return result
    end

    --- AI 每日检查竞争性报价（如果有多个报价，选最优）
    function TransferManager.processCompetitiveBids(gameState)
        TransferManager._ensureData(gameState)

        -- 按球员分组收集活跃报价
        local bidsByPlayer = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if (bid.status == "pending" or bid.status == "negotiating") and not bid.isPushSale then
                if not bidsByPlayer[bid.playerId] then
                    bidsByPlayer[bid.playerId] = {}
                end
                table.insert(bidsByPlayer[bid.playerId], bid)
            end
        end

        -- 对有多个报价的球员，AI选择最高出价
        for playerId, bids in pairs(bidsByPlayer) do
            if #bids >= 2 then
                local player = gameState.players[playerId]
                if not player then goto nextPlayer end
                -- 如果球员属于非玩家球队，AI自动选最优
                if player.teamId ~= gameState.playerTeamId then
                    -- 检查玩家是否有正在谈判中的报价（给玩家加价机会，不直接淘汰）
                    local playerHasNegotiating = false
                    for _, bid in ipairs(bids) do
                        if bid.buyerTeamId == gameState.playerTeamId and bid.status == "negotiating" then
                            playerHasNegotiating = true
                            break
                        end
                    end

                    -- 如果玩家正在谈判中，暂不仲裁，给玩家加价机会
                    if playerHasNegotiating then
                        -- 竞价警告去重：同一球员至少间隔3天才发一次警告
                        local playerBid = nil
                        for _, bid in ipairs(bids) do
                            if bid.buyerTeamId == gameState.playerTeamId then
                                playerBid = bid
                                break
                            end
                        end
                        local shouldWarn = true
                        if playerBid and playerBid._lastCompetitionWarning then
                            local daysSinceWarn = TransferManager._daysBetween(playerBid._lastCompetitionWarning, gameState.date)
                            if daysSinceWarn < 3 then shouldWarn = false end
                        end
                        if shouldWarn then
                            if playerBid then
                                playerBid._lastCompetitionWarning = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                            end
                            gameState:sendMessage({
                                category = "transfer",
                                title = "竞价警告",
                                body = string.format("其他球队也在竞争 %s，请尽快加价以保持竞争力。",
                                    player.displayName),
                                priority = "high",
                                popup = true,
                            })
                        end
                        goto nextPlayer
                    end

                    table.sort(bids, function(a, b)
                        local aVal = a._effectiveValue or a.amount
                        local bVal = b._effectiveValue or b.amount
                        return aVal > bVal
                    end)
                    -- 通知竞价失败者
                    for i = 2, #bids do
                        bids[i].status = "rejected"
                        bids[i].rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                        if bids[i].buyerTeamId == gameState.playerTeamId then
                            gameState:sendMessage({
                                category = "transfer",
                                title = "竞价失败",
                                body = string.format("有其他球队对 %s 出了更高价，你的报价被拒绝。",
                                    player.displayName),
                                priority = "normal",
                            })
                        end
                    end
                    if bids[1].status == "pending" or bids[1].status == "negotiating" then
                        TransferManager._acceptBid(gameState, bids[1])
                    end
                end
                ::nextPlayer::
            end
        end
    end

    ------------------------------------------------------
    -- ★ 预签约（合同最后6个月）
    ------------------------------------------------------

    --- 检查球员是否可预签约（合同剩余 <= 6个月）
    function TransferManager.canPreContract(gameState, playerId)
        local player = gameState.players[playerId]
        if not player then return false end
        if not player.contractEnd then return false end
        if player.teamId == gameState.playerTeamId then return false end

        local monthsLeft = (player.contractEnd.year - gameState.date.year) * 12
            + (player.contractEnd.month - gameState.date.month)
        return monthsLeft <= 6
    end

    --- 发起预签约谈判（类似自由球员谈判，但球员尚在原球队）
    function TransferManager.offerPreContract(gameState, playerId, wageOffer, yearsOffer)
        TransferManager._ensureData(gameState)

        -- 拒绝冷却期检查
        local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
        if not cooldownOk then return nil, cooldownErr end

        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end

        if not TransferManager.canPreContract(gameState, playerId) then
            return nil, "该球员合同剩余超过6个月，不可预签约"
        end

        -- 检查是否已有谈判
        if TransferManager.hasPendingFreeAgentNego(gameState, playerId) then
            return nil, "已有进行中的谈判"
        end

        -- 复用自由球员谈判逻辑
        if not gameState.transfers.freeAgentNegos then
            gameState.transfers.freeAgentNegos = {}
        end

        wageOffer = wageOffer or math.floor(player.wage * 1.2)
        yearsOffer = yearsOffer or 3

        local expectedWage = math.floor(player.wage * 1.1)  -- 预签约球员期望涨薪
        local expectedYears = TransferManager._calcExpectedYears(player, gameState.date.year)

        local nego = {
            id = gameState.transfers.nextBidId,
            playerId = playerId,
            teamId = gameState.playerTeamId,
            status = "pending",
            wageOffer = wageOffer,
            yearsOffer = yearsOffer,
            expectedWage = expectedWage,
            expectedYears = expectedYears,
            counterWage = nil,
            counterYears = nil,
            currentRound = 0,
            maxRounds = randInt(2, 3),
            mood = 45,  -- 预签约球员稍有戒心
            rounds = {},
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            responseDate = nil,
            isPreContract = true,  -- 标记预签约
            effectiveDate = player.contractEnd,  -- 合同到期后生效
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.freeAgentNegos, nego)

        gameState:sendMessage({
            category = "transfer",
            title = "预签约谈判发起",
            body = string.format("你向 %s 发起了预签约邀请（周薪 %s，%d年）。合同到期后生效。",
                player.displayName, fmtMoney(wageOffer), yearsOffer),
            priority = "normal",
        })

        return nego
    end

    --- 处理预签约到期生效（赛季末调用）
    function TransferManager.processPreContracts(gameState)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return end

        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.isPreContract and nego.status == "accepted" then
                local player = gameState.players[nego.playerId]
                if not player then goto nextNego end

                -- 检查是否到期
                local contractEnd = nego.effectiveDate
                if contractEnd and
                   (gameState.date.year > contractEnd.year or
                    (gameState.date.year == contractEnd.year and gameState.date.month >= contractEnd.month)) then
                    -- 从原球队移除（含青训名单）
                    local newTeam = gameState.teams[nego.teamId]
                    if newTeam then
                        local fromTeamId = player.teamId
                        TransferManager._assignPlayerToTeam(gameState, player, nego.teamId)
                        player.wage = nego.wageOffer
                        player.contractEnd = {year = gameState.date.year + nego.yearsOffer, month = 6}
                        player.squadRole = "first_team"
                        player.isYouth = false
                        player.preContractLockedBy = nil  -- 清除预签约锁定

                        nego.status = "completed"

                        gameState:sendMessage({
                            category = "transfer",
                            title = "预签约生效!",
                            body = string.format("%s 合同到期，正式加入球队！（周薪 %s，%d年）",
                                player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
                            priority = "normal",
                        })

                        NewsGenerator.publishTransferNews(gameState, {
                            playerId = player.id,
                            fromTeamId = fromTeamId,
                            toTeamId = nego.teamId,
                            amount = 0,
                            type = "precontract_active",
                        })
                    end
                end
                ::nextNego::
            end
        end
    end

    ------------------------------------------------------
    -- ★ 转会/工资预算分离
    ------------------------------------------------------

    --- 获取球队转会预算（分离模式）
    function TransferManager._getTransferBudget(gameState, team)
        -- 优先使用独立转会预算，否则用总余额
        if team.transferBudget and team.transferBudget > 0 then
            return team.transferBudget
        end
        return team.balance
    end

    --- 获取球队工资预算
    function TransferManager._getWageBudget(gameState, team)
        return team.wageBudget or math.floor(team.balance * 0.3)
    end

    --- 估算 AI 买人时可释放的工资（已挂牌出售的一线队球员）
    function TransferManager._getAIListedWageHeadroom(gameState, team)
        local total = 0
        for _, pid in ipairs(team.playerIds or {}) do
            local p = gameState.players[pid]
            if p and p.listedForSale then
                total = total + (p.wage or 0)
            end
        end
        return total
    end

    --- AI 签约工资检查：计入挂牌出售后可腾出的工资空间
    function TransferManager._checkAIWageBudgetForSigning(gameState, team, additionalWage)
        if not team then return false, "球队不存在" end

        -- 单次遍历同时累加在册总工资与挂牌可腾出工资（替代两次全队扫描）
        local currentWages = 0
        local releasable = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p then
                local w = p.wage or 0
                currentWages = currentWages + w
                if p.listedForSale then releasable = releasable + w end
            end
        end

        local wageBudget = TransferManager._getWageBudget(gameState, team)
        local newTotal = currentWages + additionalWage - releasable

        if newTotal > wageBudget then
            return false, string.format("工资总额 %s 将超出工资预算 %s",
                fmtMoney(newTotal), fmtMoney(wageBudget))
        end
        return true
    end

    --- 检查签约是否超出工资预算
    function TransferManager.checkWageBudget(gameState, teamId, additionalWage)
        local team = gameState.teams[teamId]
        if not team then return false, "球队不存在" end

        local currentWages = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p then currentWages = currentWages + p.wage end
        end

        local wageBudget = TransferManager._getWageBudget(gameState, team)
        local newTotal = currentWages + additionalWage

        if newTotal > wageBudget then
            return false, string.format("工资总额 %s 将超出工资预算 %s",
                fmtMoney(newTotal), fmtMoney(wageBudget))
        end
        return true
    end

    --- 调整转会/工资预算分配（玩家操作）
    function TransferManager.adjustBudgets(gameState, transferBudget, wageBudget)
        local team = gameState:getPlayerTeam()
        if not team then return false end

        -- 两个预算总和不能超过总余额
        if transferBudget + wageBudget * 52 > team.balance * 2 then
            return false, "预算分配超出总财力"
        end

        team.transferBudget = transferBudget
        team.wageBudget = wageBudget
        return true
    end

    ------------------------------------------------------
    -- ★ 本土球员配额
    ------------------------------------------------------

    --- 检查球队本土球员配额
    --- @return boolean compliant 是否合规
    --- @return number homegrown 本土球员数
    --- @return number required 要求数量
    function TransferManager.checkHomegrownQuota(gameState, teamId)
        local team = gameState.teams[teamId or gameState.playerTeamId]
        if not team then return true, 0, 0 end

        local Constants = require("scripts/app/constants")
        local required = Constants.HOMEGROWN_QUOTA or 8  -- 默认至少8名本土球员
        local homegrown = 0

        -- 国籍与联赛所在国相同视为本土
        local leagueCountry = team.country or "ENG"
        for _, pid in ipairs(team.playerIds) do
            local player = gameState.players[pid]
            if player and Nationality.matches(player.nationality, leagueCountry) then
                homegrown = homegrown + 1
            end
        end

        return homegrown >= required, homegrown, required
    end

    --- 转会前检查配额合规性（引入外籍球员时警告）
    function TransferManager.wouldViolateQuota(gameState, playerId)
        local player = gameState.players[playerId]
        if not player then return false end

        local team = gameState:getPlayerTeam()
        if not team then return false end

        -- 如果引进的是本土球员，不会违反配额
        if Nationality.matches(player.nationality, team.country) then return false end

        -- 检查当前配额
        local compliant, homegrown, required = TransferManager.checkHomegrownQuota(gameState)
        if not compliant then
            return true  -- 已经不合规了，还要引进外援
        end

        -- 即使合规，检查引进后是否仍合规
        -- (需要看是否有外援占满名额)
        local maxSquad = 25  -- 标准注册名额
        local foreignCount = #team.playerIds - homegrown
        if foreignCount >= (maxSquad - required) then
            return true  -- 外援名额已满
        end

        return false
    end

    ------------------------------------------------------
    -- ★ 球队关系系统
    ------------------------------------------------------

    --- 检查两队是否为敌对关系
    function TransferManager._isRivalry(gameState, teamId1, teamId2)
        if not teamId1 or not teamId2 or teamId1 == teamId2 then return false end
        if not gameState._teamRelations then return false end
        local id1 = tostring(teamId1)
        local id2 = tostring(teamId2)
        local key = id1 < id2
            and (id1 .. "_" .. id2)
            or (id2 .. "_" .. id1)
        local rel = gameState._teamRelations[key]
        return rel and rel <= -50  -- -100 ~ +100，-50以下视为敌对
    end

    --- 公开 API：是否死敌
    function TransferManager.isRivalry(gameState, teamId1, teamId2)
        return TransferManager._isRivalry(gameState, teamId1, teamId2)
    end

    --- 获取球队的所有死敌 teamId 列表
    function TransferManager.getRivalTeams(gameState, teamId)
        local rivals = {}
        if not gameState._teamRelations or not teamId then return rivals end
        for key, rel in pairs(gameState._teamRelations) do
            if rel <= -50 then
                local id1, id2 = key:match("^(%d+)_(%d+)$")
                id1, id2 = tonumber(id1), tonumber(id2)
                if id1 == teamId then
                    table.insert(rivals, id2)
                elseif id2 == teamId then
                    table.insert(rivals, id1)
                end
            end
        end
        return rivals
    end

    --- 设置球队关系（初始化/事件触发）
    function TransferManager.setTeamRelation(gameState, teamId1, teamId2, value)
        if not gameState._teamRelations then gameState._teamRelations = {} end
        local key = teamId1 < teamId2
            and (teamId1 .. "_" .. teamId2)
            or (teamId2 .. "_" .. teamId1)
        gameState._teamRelations[key] = math.max(-100, math.min(100, value))
    end

    --- 获取球队关系值
    function TransferManager.getTeamRelation(gameState, teamId1, teamId2)
        if not gameState._teamRelations then return 0 end
        local key = teamId1 < teamId2
            and (teamId1 .. "_" .. teamId2)
            or (teamId2 .. "_" .. teamId1)
        return gameState._teamRelations[key] or 0
    end

    ------------------------------------------------------
    -- ★ 球探网络覆盖系统
    ------------------------------------------------------

    --- 获取球探网络覆盖的地区
    function TransferManager.getScoutNetwork(gameState)
        TransferManager._ensureData(gameState)
        if not gameState.scoutNetwork then
            -- 默认覆盖本国
            local team = gameState:getPlayerTeam()
            local homeCountry = team and team.country or "ENG"
            gameState.scoutNetwork = {
                regions = { homeCountry },  -- 已覆盖地区
                maxRegions = 3,  -- 最大覆盖地区数（随球探数量增加）
            }
        end
        return gameState.scoutNetwork
    end

    --- 添加球探网络覆盖地区
    function TransferManager.addScoutRegion(gameState, region)
        local network = TransferManager.getScoutNetwork(gameState)

        -- 检查是否已覆盖
        for _, r in ipairs(network.regions) do
            if r == region then return false, "已覆盖该地区" end
        end

        -- 检查上限
        if #network.regions >= network.maxRegions then
            return false, string.format("球探网络已达上限（%d个地区）", network.maxRegions)
        end

        table.insert(network.regions, region)
        gameState:sendMessage({
            category = "scout",
            title = "球探网络扩展",
            body = string.format("球探网络已覆盖新地区: %s", region),
            priority = "low",
        })
        return true
    end

    --- 移除球探网络覆盖地区
    function TransferManager.removeScoutRegion(gameState, region)
        local network = TransferManager.getScoutNetwork(gameState)
        for i, r in ipairs(network.regions) do
            if r == region then
                table.remove(network.regions, i)
                return true
            end
        end
        return false
    end

    --- 球探发现球员时检查地区覆盖（修改原有 processScoutReport）
    function TransferManager._isPlayerInScoutNetwork(gameState, player)
        local network = TransferManager.getScoutNetwork(gameState)
        -- 球员所在球队的国家 或 球员国籍 在覆盖范围内
        local playerCountry = Nationality.normalize(player.nationality)
        local teamCountry = nil
        if player.teamId then
            local playerTeam = gameState.teams[player.teamId]
            if playerTeam then teamCountry = Nationality.normalize(playerTeam.country) end
        end

        for _, region in ipairs(network.regions) do
            local normRegion = Nationality.normalize(region)
            if normRegion == playerCountry or normRegion == teamCountry then
                return true
            end
        end
        return false
    end
end
