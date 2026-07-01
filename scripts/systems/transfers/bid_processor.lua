-- systems/transfers/bid_processor.lua
-- 出价、AI应答、确认/取消，从 transfer_manager.lua 拆分。

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")
local StaffManager = require("scripts/systems/staff_manager")
local Helpers = require("scripts/systems/transfers/transfer_helpers")
local randInt = Helpers.randInt
local fmtMoney = Helpers.fmtMoney
local SIGN_CONFIRM_TIMEOUT_DAYS = Helpers.SIGN_CONFIRM_TIMEOUT_DAYS
local SIGN_CONFIRM_DEFER_DAYS = Helpers.SIGN_CONFIRM_DEFER_DAYS
local _bidIdsEqual = Helpers.bidIdsEqual

return function(TransferManager)
    -- 发起报价
    function TransferManager.makeBid(gameState, playerId, amount, wageOffer)
        TransferManager._ensureData(gameState)

        -- 转会窗口检查
        local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
        if not windowOk then return nil, windowErr end

        -- 拒绝冷却期检查
        local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
        if not cooldownOk then return nil, cooldownErr end

        -- 预签约锁定检查
        local lockOk, lockErr = TransferManager._checkPreContractLock(gameState, playerId)
        if not lockOk then return nil, lockErr end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
        if not moveOk then return nil, moveErr end

        local buyerTeam = gameState.teams[gameState.playerTeamId]
        if buyerTeam and FinanceManager.isTransferRestricted(buyerTeam) then
            return nil, "财务危机中：董事会限制新引援，请先改善现金流"
        end

        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end
        if not player.teamId then return nil, "自由球员请使用自由签约" end
        if player.teamId == gameState.playerTeamId then return nil, "该球员已在你的球队" end

        -- 生成AI耐心上限（3-5轮）
        local maxRounds = randInt(3, 5)

        local bid = {
            id = gameState.transfers.nextBidId,
            playerId = playerId,
            buyerTeamId = gameState.playerTeamId,
            sellerTeamId = player.teamId,
            amount = amount,
            playerValue = player.value,
            status = "pending",  -- pending, accepted, rejected, negotiating, cancelled, completed
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            responseDate = nil,
            wageOffer = wageOffer or player.wage,
            contractYears = TransferManager._calcExpectedYears(player, gameState.date.year), -- 根据球员年龄动态计算
            -- 多轮谈判新增字段
            counterAmount = nil,      -- AI的还价金额
            currentRound = 0,         -- 当前回合
            maxRounds = maxRounds,    -- 耐心上限
            mood = math.max(0, math.min(100, 50 - DifficultySettings.getTransferModifiers().moodPenalty)),  -- AI心情(0-100), 难度影响初始值
            rounds = {},              -- 历史记录: {round, offer, counter, result}
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.bids, bid)

        -- 通知消息
        gameState:sendMessage({
            category = "transfer",
            title = "报价已提交",
            body = string.format("你对 %s 的报价 (%s) 已经提交，等待对方回复。",
                player.displayName, fmtMoney(amount)),
            priority = "normal",
        })

        return bid
    end

    -- 玩家加价（谈判中使用）
    function TransferManager.raiseBid(gameState, bidId, newAmount, newWage)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "negotiating" then
                local player = gameState.players[bid.playerId]
                if not player then return false end

                -- 记录玩家加价（currentRound 仅由 AI 回应时递增，避免一次加价消耗两轮额度）
                local playerRound = (bid.currentRound or 0) + 1
                table.insert(bid.rounds, {
                    round = playerRound,
                    offer = newAmount,
                    counter = bid.counterAmount,
                    result = "raised",
                })

                -- 更新出价
                bid.amount = newAmount
                if newWage then bid.wageOffer = newWage end
                -- 同步重算分期表，保证各期之和=新报价（避免现金支付与报价/预算不一致）
                if bid.installments and #bid.installments > 0 then
                    local n = #bid.installments
                    local perInstall = math.floor(newAmount / n)
                    for i = 1, n do
                        bid.installments[i].amount = (i == n) and (newAmount - perInstall * (n - 1)) or perInstall
                    end
                end
                bid.status = "pending"  -- 重新回到等待AI回应
                bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

                -- 加价让AI心情好转
                local baseline = bid.type == "loan"
                    and math.max(TransferManager.getLoanFeeBenchmark(player, bid.loanDuration), 1)
                    or math.max(player.value, 1)
                local improvement = (newAmount - (bid.counterAmount or baseline)) / baseline * 40
                bid.mood = math.min(100, math.max(0, (bid.mood or 50) + improvement + 5))

                local feeLabel = bid.type == "loan" and "租借费" or "报价"
                gameState:sendMessage({
                    category = "transfer",
                    title = "加价" .. feeLabel .. "已提交",
                    body = string.format("你对 %s 的加价%s (%s) 已提交，等待回复。(第%d轮)",
                        player.displayName, feeLabel, fmtMoney(newAmount), playerRound),
                    priority = "normal",
                })
                return true
            end
        end
        return false
    end

    -- 获取指定 bid
    function TransferManager.getBidById(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if _bidIdsEqual(bid.id, bidId) then return bid end
        end
        return nil
    end

    -- 检查是否已对某球员有pending报价
    function TransferManager.hasPendingBid(gameState, playerId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == playerId and
               bid.buyerTeamId == gameState.playerTeamId and
               (bid.status == "pending" or bid.status == "negotiating" or bid.status == "fee_agreed"
                or bid.status == "player_considering" or bid.status == "awaiting_confirmation") then
                return true
            end
        end
        return false
    end

    -- 获取玩家的所有报价
    function TransferManager.getPlayerBids(gameState)
        TransferManager._ensureData(gameState)
        local result = {}
        -- 合并活跃 + 归档 bid（UI 展示历史用）
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.buyerTeamId == gameState.playerTeamId then
                result[#result + 1] = bid
            end
        end
        for _, bid in ipairs(gameState.transfers.closedBids) do
            if bid.buyerTeamId == gameState.playerTeamId then
                result[#result + 1] = bid
            end
        end
        -- 按日期倒序
        table.sort(result, function(a, b) return a.id > b.id end)
        return result
    end

    --- 待玩家最终确认的出售（还价已被 AI 接受）
    ---@return table[] { bidId, playerId, playerName, buyerName, amount }
    function TransferManager.getPendingSaleConfirmations(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        if not teamId then return {} end
        TransferManager._ensureData(gameState)
        local result = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.sellerTeamId == teamId
                and bid.isIncomingBid
                and bid.status == "awaiting_sale_confirmation" then
                local player = gameState.players[bid.playerId]
                local buyer = gameState.teams[bid.buyerTeamId]
                table.insert(result, {
                    bidId = bid.id,
                    playerId = bid.playerId,
                    playerName = player and player.displayName or "球员",
                    buyerName = buyer and (buyer.name or buyer.shortName) or "买方",
                    amount = bid.amount,
                })
            end
        end
        return result
    end

    --- 待玩家最终确认的买入（球员已同意加盟）
    ---@return table[] { bidId, playerId, playerName, sellerName, amount }
    function TransferManager.getPendingTransferSignConfirmations(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        if not teamId then return {} end
        TransferManager._ensureData(gameState)
        local result = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.buyerTeamId == teamId
                and bid.status == "awaiting_confirmation"
                and not TransferManager.isSignConfirmDeferred(bid, gameState) then
                local activeLoan = TransferManager.getLoanForPlayer(gameState, bid.playerId)
                if activeLoan and activeLoan.loanTeamId == teamId then
                    TransferManager._cancelStaleLoanBidsForPlayer(gameState, bid.playerId, teamId)
                    goto continue_pending_sign
                end
                local player = gameState.players[bid.playerId]
                local seller = bid.sellerTeamId and gameState.teams[bid.sellerTeamId]
                table.insert(result, {
                    bidId = bid.id,
                    playerId = bid.playerId,
                    playerName = player and player.displayName or "球员",
                    sellerName = seller and (seller.name or seller.shortName) or "卖方",
                    amount = bid.amount,
                })
                ::continue_pending_sign::
            end
        end
        return result
    end

    --- 待玩家最终确认的自由球员签约
    ---@return table[] { negoId, playerId, playerName, wageOffer, yearsOffer }
    function TransferManager.getPendingFreeAgentSignConfirmations(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        if not teamId then return {} end
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return {} end
        local result = {}
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.teamId == teamId and nego.status == "awaiting_confirmation"
                and not TransferManager.isFreeAgentSignDeferred(nego, gameState) then
                local player = gameState.players[nego.playerId]
                if player then
                    table.insert(result, {
                        negoId = nego.id,
                        playerId = nego.playerId,
                        playerName = player.displayName or "球员",
                        wageOffer = nego.wageOffer,
                        yearsOffer = nego.yearsOffer,
                    })
                end
            end
        end
        return result
    end

    --- 批量确认待签入转会/租借
    ---@return number okCount
    ---@return number failCount
    ---@return string|nil lastErr
    function TransferManager.confirmAllPendingTransfers(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        local pending = TransferManager.getPendingTransferSignConfirmations(gameState, teamId)
        local okCount, failCount = 0, 0
        local lastErr = nil
        for _, item in ipairs(pending) do
            local bid = TransferManager.getBidById(gameState, item.bidId)
            if bid and bid.type == "loan" then
                local confirmed, err = TransferManager.confirmLoan(gameState, item.bidId)
                if confirmed then
                    okCount = okCount + 1
                else
                    failCount = failCount + 1
                    lastErr = err
                end
            else
                local result, err = TransferManager.confirmTransfer(gameState, item.bidId)
                if result then
                    okCount = okCount + 1
                else
                    failCount = failCount + 1
                    lastErr = err
                end
            end
        end
        return okCount, failCount, lastErr
    end

    --- 批量确认待出售
    ---@return number okCount
    ---@return number failCount
    ---@return string|nil lastErr
    function TransferManager.confirmAllPendingSales(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        local pending = TransferManager.getPendingSaleConfirmations(gameState, teamId)
        local okCount, failCount = 0, 0
        local lastErr = nil
        for _, item in ipairs(pending) do
            local ok, err = TransferManager.confirmSale(gameState, item.bidId)
            if ok then
                okCount = okCount + 1
            else
                failCount = failCount + 1
                lastErr = err
            end
        end
        return okCount, failCount, lastErr
    end

    --- 批量同意挂牌球员的待处理收购报价（仅 status=pending）
    ---@param playerIds string[] 限定球员 id 列表（如已挂牌名单）
    ---@return number okCount
    ---@return number failCount
    function TransferManager.acceptAllPendingIncomingBids(gameState, playerIds)
        local okCount, failCount = 0, 0
        for _, playerId in ipairs(playerIds or {}) do
            local bid = TransferManager.pickPrimaryIncomingSaleBid(gameState, playerId)
            if bid and bid.status == "pending" then
                if TransferManager.acceptIncomingBid(gameState, bid.id) then
                    okCount = okCount + 1
                else
                    failCount = failCount + 1
                end
            end
        end
        return okCount, failCount
    end

    --- 批量确认待签入自由球员
    ---@return number okCount
    ---@return number failCount
    ---@return string|nil lastErr
    function TransferManager.confirmAllPendingFreeAgents(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        local pending = TransferManager.getPendingFreeAgentSignConfirmations(gameState, teamId)
        local okCount, failCount = 0, 0
        local lastErr = nil
        for _, item in ipairs(pending) do
            local _, err = TransferManager.confirmFreeAgent(gameState, item.negoId)
            if not err then
                okCount = okCount + 1
            else
                failCount = failCount + 1
                lastErr = err
            end
        end
        return okCount, failCount, lastErr
    end

    -- 获取别队对玩家球队球员的待处理报价（卖方视角）
    function TransferManager.getPendingSellBids(gameState)
        TransferManager._ensureData(gameState)
        local result = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.sellerTeamId == gameState.playerTeamId
                and bid.isIncomingBid
                and (bid.status == "pending" or bid.status == "counter_pending"
                     or bid.status == "awaiting_sale_confirmation" or bid.status == "player_considering_sale") then
                table.insert(result, bid)
            end
        end
        return result
    end

    --- 本队仍有活跃 incoming 出售流程的球员 ID（用于市场 UI 兜底，避免取消挂牌后找不到报价入口）
    ---@return number[]
    function TransferManager.getPlayersWithActiveIncomingSales(gameState, teamId)
        teamId = teamId or gameState.playerTeamId
        if not teamId then return {} end
        TransferManager._ensureData(gameState)
        local seen = {}
        local result = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.sellerTeamId == teamId and bid.isIncomingBid
                and (bid.status == "pending" or bid.status == "counter_pending"
                    or bid.status == "awaiting_sale_confirmation" or bid.status == "player_considering_sale") then
                if not seen[bid.playerId] then
                    seen[bid.playerId] = true
                    table.insert(result, bid.playerId)
                end
            end
        end
        return result
    end

    -- 取消报价
    function TransferManager.cancelBid(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and (bid.status == "pending" or bid.status == "negotiating" or bid.status == "fee_agreed") then
                bid.status = "cancelled"
                return true
            end
        end
        return false
    end

    -- AI回应出价（生成具体counter-offer；仅处理玩家作为买方的 outgoing bid）
    function TransferManager._processAIResponse(gameState, bid)
        if bid.isIncomingBid or bid.isPushSale or bid.buyerTeamId ~= gameState.playerTeamId then
            return
        end

        local player = gameState.players[bid.playerId]
        if not player then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return
        end

        local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
        if not sellerOk then
            TransferManager._rejectBid(gameState, bid, sellerErr)
            return
        end

        local ratio = TransferManager._getBidEffectiveValue(bid, player) / math.max(player.value, 1)
        local round = bid.currentRound or 0
        local mood = bid.mood or 50
        local maxRounds = bid.maxRounds or 4

        -- 难度修正
        local diffMods = DifficultySettings.getTransferModifiers()

        -- 接受阈值：基础1.3，mood越高阈值越低
        local acceptThreshold = 1.3 - (mood / 200)  -- mood=100时阈值1.0, mood=0时阈值1.3
        -- 随着轮次增加，阈值降低（对方越来越务实）
        acceptThreshold = acceptThreshold - round * 0.05
        -- 难度偏移：高难度时阈值更高（更难被接受）
        acceptThreshold = acceptThreshold + diffMods.thresholdOffset

        -- 年龄因子：年轻球员溢价更高，老将更容易谈
        -- 以26岁为中性基准，每偏离1岁影响0.02
        local age = player.getAge and player:getAge(gameState.date.year) or 26
        local ageFactor = (26 - age) * 0.02  -- <26: 正值(加价), >26: 负值(降价)
        ageFactor = math.max(-0.15, math.min(0.15, ageFactor))  -- 限制在[-0.15, +0.15]
        acceptThreshold = acceptThreshold + ageFactor

        -- 非卖品溢价：未挂牌球员需要更高报价才会考虑出售
        if not player.listedForSale then
            acceptThreshold = acceptThreshold + 0.3  -- 未挂牌球员额外+0.3倍溢价
        end

        if ratio >= math.max(acceptThreshold, 0.9) then
            -- 达到接受阈值 → 直接接受（优先于回合耗尽，避免满额报价被拒）
            TransferManager._acceptBid(gameState, bid)
        elseif round >= maxRounds then
            TransferManager._rejectBid(gameState, bid, "谈判回合耗尽，对方决定不出售。")
        elseif ratio >= 0.6 then
            -- 进入/继续谈判 → 生成counter-offer
            bid.status = "negotiating"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            -- 计算AI还价：基于身价 * 倍率（随轮次逐渐降低）
            local baseMultiplier = 1.35 - round * 0.07  -- 第0轮1.35, 第3轮1.14
            -- mood越好，还价越低
            baseMultiplier = baseMultiplier - (mood - 50) / 200
            -- 年龄影响还价：年轻球员开价更高，老将更务实
            baseMultiplier = baseMultiplier + ageFactor
            -- 非卖品溢价：未挂牌球员AI要价更高
            if not player.listedForSale then
                baseMultiplier = baseMultiplier + 0.3
            end
            -- 难度偏移：高难度时AI要价更高
            baseMultiplier = baseMultiplier + diffMods.counterMultiplierOffset
            -- 加一点随机波动
            baseMultiplier = baseMultiplier + (Random() - 0.5) * 0.1
            baseMultiplier = math.max(1.0, baseMultiplier)

            local counter = math.floor(player.value * baseMultiplier / 1000) * 1000
            -- counter不能低于当前出价（否则直接接受）
            if counter <= bid.amount then
                TransferManager._acceptBid(gameState, bid)
                return
            end
            bid.counterAmount = counter
            bid.currentRound = round + 1

            -- 记录本轮
            table.insert(bid.rounds, {
                round = bid.currentRound,
                offer = bid.amount,
                counter = counter,
                result = "counter",
            })

            local sellerTeam = gameState.teams[bid.sellerTeamId]
            local sellerName = sellerTeam and sellerTeam.name or "对方俱乐部"
            gameState:sendMessage({
                category = "transfer",
                title = "转会还价",
                body = string.format(
                    "%s 拒绝了你的 %s 报价。\n%s 要求至少 %s 才愿意放人。\n(第%d/%d轮谈判)",
                    sellerName, fmtMoney(bid.amount),
                    sellerName, fmtMoney(counter),
                    (round + 1), maxRounds),
                priority = "high",
                popup = true,
            })
        else
            -- 报价太低，直接拒绝
            bid.mood = math.max(0, (bid.mood or 50) - 15)
            TransferManager._rejectBid(gameState, bid,
                string.format("你的报价远低于 %s 的实际价值 (%s)，对方直接拒绝了。",
                    player.displayName, fmtMoney(player.value)))
        end
    end

    -- 接受报价
    function TransferManager._acceptBid(gameState, bid)
        local player = gameState.players[bid.playerId]
        if not player then return end

        local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
        if not sellerOk then
            TransferManager._rejectBid(gameState, bid, sellerErr)
            return
        end

        -- 转会费已达成，进入球员考虑阶段
        bid.status = "player_considering"
        bid.feeAgreedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        bid.playerConsiderDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

        -- Deadline Day 效应：关窗前<=2天，考虑时间压缩为1天，且个人条款只有1次机会
        local isDeadline = TransferManager.isDeadlineDay(gameState)
        if isDeadline then
            bid.playerConsiderDays = 1
            bid.maxPersonalTermsAttempts = 1  -- 关窗前只给1次个人条款机会
            bid.isDeadlineDeal = true         -- 标记为关窗交易
        else
            bid.playerConsiderDays = randInt(1, 3)
            bid.maxPersonalTermsAttempts = 3  -- 正常情况3次机会
        end
        bid.personalTermsAttempts = 0  -- 个人条款协商次数

        local sellerTeam = gameState.teams[bid.sellerTeamId]
        local deadlineNote = isDeadline and "（关窗日加急处理）" or ""
        if bid.type == "loan" then
            gameState:sendMessage({
                category = "transfer",
                title = "租借费已达成" .. deadlineNote,
                body = string.format("%s 已同意出租 %s！球员正在考虑是否外租，预计需要 %d 天回复。%s",
                    sellerTeam and sellerTeam.name or "对方俱乐部",
                    player.displayName, bid.playerConsiderDays,
                    isDeadline and "\n⚠️ 转会窗口即将关闭，协商时间紧迫！" or ""),
                priority = "high",
                popup = true,
            })
        else
            gameState:sendMessage({
                category = "transfer",
                title = "转会费已达成" .. deadlineNote,
                body = string.format("%s 已同意放人！球员 %s 正在考虑是否加盟，预计需要 %d 天回复。%s",
                    sellerTeam and sellerTeam.name or "对方俱乐部",
                    player.displayName, bid.playerConsiderDays,
                    isDeadline and "\n⚠️ 转会窗口即将关闭，协商时间紧迫！" or ""),
                priority = "high",
                popup = true,
            })
        end
    end

    --- 尝试个人条款协商（内部方法）
    --- 成功则进入等待玩家确认状态，失败则通知玩家可修改工资后重试
    function TransferManager._attemptPersonalTerms(gameState, bid)
        if bid.type == "loan" then
            return TransferManager._attemptLoanTerms(gameState, bid)
        end

        local player = gameState.players[bid.playerId]
        if not player then return end

        bid.personalTermsAttempts = (bid.personalTermsAttempts or 0) + 1

        local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
        local maxAttempts = bid.maxPersonalTermsAttempts or 3

        if consent then
            -- 球员同意个人条款，等待玩家最终确认
            bid.status = "awaiting_confirmation"
            bid.confirmDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "球员同意加盟!",
                body = string.format(
                    "%s 已同意个人条款（周薪 %s）。是否确认签入该球员？",
                    player.displayName, fmtMoney(bid.wageOffer or player.wage)),
                priority = "high",
                popup = true,
                actions = {
                    { label = "确认签入", actionId = "confirm_transfer", data = { bidId = bid.id } },
                    { label = "放弃签约", actionId = "cancel_transfer", data = { bidId = bid.id } },
                },
            })
        else
            -- 个人条款被拒，但转会费协议仍有效
            if bid.personalTermsAttempts >= maxAttempts then
                local deadlineNote = bid.isDeadlineDeal and "（关窗日无更多协商时间）" or ""
                TransferManager._rejectBid(gameState, bid,
                    string.format("与 %s 的个人条款协商已失败%d次，交易取消。%s",
                        player.displayName, maxAttempts, deadlineNote))
            else
                bid.status = "fee_agreed"  -- 保持在fee_agreed状态
                bid.personalTermsNegotiateDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                local remaining = maxAttempts - bid.personalTermsAttempts
                gameState:sendMessage({
                    category = "transfer",
                    title = "个人条款被拒",
                    body = string.format(
                        "%s 拒绝了当前的个人条款（%s）。转会费协议仍有效，你可以修改薪资报价后重新协商（剩余 %d 次机会）。%s",
                        player.displayName, reason or "条件不满意",
                        remaining,
                        bid.isDeadlineDeal and "\n⚠️ 窗口即将关闭，请抓紧时间！" or ""),
                    priority = "high",
                    popup = true,
                    data = { bidId = bid.id, type = "personal_terms_rejected" },
                })
            end
        end
    end

    --- 玩家修改工资后重新协商个人条款（公开API）— 异步：球员考虑1-2天
    function TransferManager.negotiatePersonalTerms(gameState, bidId, newWageOffer)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "fee_agreed" then
                if bid.type == "loan" then
                    return nil, "租借报价请使用工资分担比例协商"
                end
                if bid.buyerTeamId ~= gameState.playerTeamId then
                    return nil, "只能协商自己的报价"
                end
                -- 更新工资报价
                bid.wageOffer = newWageOffer
                -- 设为球员考虑中状态，等待每日处理出结果
                bid.status = "player_considering"
                bid.playerConsiderDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                bid.playerConsiderDays = 1 + math.floor(Random() * 2)  -- 1~2天
                local player = gameState.players[bid.playerId]
                gameState:sendMessage({
                    category = "transfer",
                    title = "个人条款已提出",
                    body = string.format("已向 %s 提出新的薪资方案（周薪 %s），球员正在考虑中...",
                        player and player.displayName or "该球员",
                        fmtMoney(newWageOffer)),
                    priority = "normal",
                })
                return bid, nil
            end
        end
        return nil, "未找到待协商个人条款的报价"
    end

    --- 玩家确认签入球员（公开API，从 inbox action 调用）
    function TransferManager.confirmTransfer(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "awaiting_confirmation" then
                if bid.type == "loan" then
                    return TransferManager.confirmLoan(gameState, bidId)
                end
                local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
                if not sellerOk then
                    TransferManager._rejectBid(gameState, bid, sellerErr)
                    return nil, sellerErr
                end
                bid.status = "accepted"
                TransferManager._completeTransfer(gameState, bid)
                return bid, nil
            end
        end
        return nil, "未找到待确认的转会"
    end

    --- 玩家放弃签约（公开API，从 inbox action 调用）
    function TransferManager.cancelTransferConfirmation(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "awaiting_confirmation" then
                if bid.type == "loan" then
                    return TransferManager.cancelLoanConfirmation(gameState, bidId)
                end
                local player = gameState.players[bid.playerId]
                bid.status = "cancelled"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "签约已放弃",
                    body = string.format("你放弃了签入 %s 的交易。",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
                return bid, nil
            end
        end
        return nil, "未找到待确认的转会"
    end

    --- 签入确认是否处于推迟期（推迟期内不阻断时间推进）
    function TransferManager.isSignConfirmDeferred(bid, gameState)
        if not bid or not bid.confirmDeferredUntil or not gameState or not gameState.date then
            return false
        end
        return TransferManager._daysBetween(gameState.date, bid.confirmDeferredUntil) > 0
    end

    function TransferManager.isFreeAgentSignDeferred(nego, gameState)
        if not nego or not nego.confirmDeferredUntil or not gameState or not gameState.date then
            return false
        end
        return TransferManager._daysBetween(gameState.date, nego.confirmDeferredUntil) > 0
    end

    function TransferManager.getSignConfirmDeferDaysLeft(bid, gameState)
        if not bid or not bid.confirmDeferredUntil then return 0 end
        return math.max(0, TransferManager._daysBetween(gameState.date, bid.confirmDeferredUntil))
    end

    function TransferManager.getFreeAgentSignDeferDaysLeft(nego, gameState)
        if not nego or not nego.confirmDeferredUntil then return 0 end
        return math.max(0, TransferManager._daysBetween(gameState.date, nego.confirmDeferredUntil))
    end

    function TransferManager.getSignConfirmDeferDays()
        return SIGN_CONFIRM_DEFER_DAYS
    end

    function TransferManager.canDeferTransferSignConfirmation(gameState, bidId)
        TransferManager._ensureData(gameState)
        local bid = TransferManager.getBidById(gameState, bidId)
        if not bid or bid.status ~= "awaiting_confirmation" then return false end
        if bid.buyerTeamId ~= gameState.playerTeamId then return false end
        if bid.confirmDeferUsed then return false end
        if TransferManager.isSignConfirmDeferred(bid, gameState) then return false end
        return true
    end

    function TransferManager.canDeferFreeAgentSignConfirmation(gameState, negoId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return false end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and nego.status == "awaiting_confirmation"
                and nego.teamId == gameState.playerTeamId
                and not nego.confirmDeferUsed
                and not TransferManager.isFreeAgentSignDeferred(nego, gameState) then
                return true
            end
        end
        return false
    end

    --- 推迟签入决定 3 天（每笔交易仅可推迟一次；推迟期内可继续推进时间）
    function TransferManager.deferTransferSignConfirmation(gameState, bidId)
        if not TransferManager.canDeferTransferSignConfirmation(gameState, bidId) then
            return false, "无法推迟此签约"
        end
        local bid = TransferManager.getBidById(gameState, bidId)
        local player = gameState.players[bid.playerId]
        bid.confirmDeferUsed = true
        bid.confirmDeferredUntil = TransferManager._addDays(gameState.date, SIGN_CONFIRM_DEFER_DAYS)
        gameState:sendMessage({
            category = "transfer",
            title = "签约已推迟",
            body = string.format(
                "已将 %s 的签入决定推迟 %d 天。你可以在这段时间筹钱或寻找替代人选，到期后需尽快确认。",
                player and player.displayName or "该球员", SIGN_CONFIRM_DEFER_DAYS),
            priority = "normal",
        })
        return true, nil
    end

    function TransferManager.deferFreeAgentSignConfirmation(gameState, negoId)
        if not TransferManager.canDeferFreeAgentSignConfirmation(gameState, negoId) then
            return false, "无法推迟此签约"
        end
        TransferManager._ensureData(gameState)
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and nego.status == "awaiting_confirmation" then
                local player = gameState.players[nego.playerId]
                nego.confirmDeferUsed = true
                nego.confirmDeferredUntil = TransferManager._addDays(gameState.date, SIGN_CONFIRM_DEFER_DAYS)
                gameState:sendMessage({
                    category = "transfer",
                    title = "签约已推迟",
                    body = string.format(
                        "已将自由球员 %s 的签入决定推迟 %d 天。你可以在这段时间筹钱或寻找替代人选，到期后需尽快确认。",
                        player and player.displayName or "该球员", SIGN_CONFIRM_DEFER_DAYS),
                    priority = "normal",
                })
                return true, nil
            end
        end
        return false, "未找到待确认的自由球员签约"
    end

    -- 拒绝报价
    function TransferManager._rejectBid(gameState, bid, reason)
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        local player = gameState.players[bid.playerId]
        local isBuyer = bid.buyerTeamId == gameState.playerTeamId
        local isSeller = bid.sellerTeamId == gameState.playerTeamId

        if not reason then
            if isBuyer then
                reason = string.format("你对 %s 的报价已被拒绝。",
                    player and player.displayName or "该球员")
            elseif isSeller then
                local buyerTeam = gameState.teams[bid.buyerTeamId]
                reason = string.format("%s 对 %s 的报价未能达成。",
                    buyerTeam and buyerTeam.name or "买方球队",
                    player and player.displayName or "该球员")
            else
                reason = "转会报价未能达成。"
            end
        end

        if isBuyer or isSeller then
            gameState:sendMessage({
                category = "transfer",
                title = isSeller and not isBuyer and "出售报价结束" or "报价被拒绝",
                body = reason,
                priority = "normal",
            })
        end
    end

    -- 完成转会
    -- @param opts table|nil 可选参数 { suppressMessage = bool }
    function TransferManager._completeTransfer(gameState, bid, opts)
        local player = gameState.players[bid.playerId]
        if not player then return end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
        if not moveOk then
            TransferManager._rejectBid(gameState, bid, moveErr)
            return
        end

        local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
        if not sellerOk then
            TransferManager._rejectBid(gameState, bid, sellerErr)
            return
        end

        local sellerTeam = gameState.teams[bid.sellerTeamId]
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        if not buyerTeam then return end

        local alreadyAtBuyer = false
        for _, pid in ipairs(buyerTeam.playerIds or {}) do
            if pid == player.id then alreadyAtBuyer = true; break end
        end
        local allowWindowOverCap = TransferManager.isInTransferWindow(gameState)
        if not alreadyAtBuyer and not allowWindowOverCap and buyerTeam:isSquadFullFor(gameState) then
            TransferManager._rejectBid(gameState, bid,
                string.format("买方一线队已满员（最多 %d 人）。", buyerTeam:getEffectiveSquadMax(gameState)))
            return
        end

        -- 加入买方阵容（同时清除其他球队残留引用，避免射手榜重复统计）
        local assignOpts = allowWindowOverCap and { allowOverCap = true } or nil
        if not TransferManager._assignPlayerToTeam(gameState, player, bid.buyerTeamId, assignOpts) then
            TransferManager._rejectBid(gameState, bid, "买方一线队已满员，转会无法完成。")
            return
        end
        player.listedForSale = false
        player.listedForLoan = false
        player.saleAskingPrice = nil
        -- 青训球员被买走后转为一线队身份（避免遗留青训标记被月度青训逻辑误处理）
        player.isYouth = false
        player.squadRole = "first_team"

        TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)
        TransferManager._attachFutureClauses(player, bid)

        -- 更新球员合同（个人条款）
        if bid.wageOffer and bid.wageOffer > 0 then
            player.wage = bid.wageOffer
        end
        if bid.contractYears and bid.contractYears > 0 then
            player.contractEnd = { year = gameState.date.year + bid.contractYears, month = 6 }
        end

        -- 转会后更新名气和身价（新球队声望影响）
        player:calculateReputation(buyerTeam.reputation or 300)
        player:calculateValue(gameState.date.year)

        TransferManager._markPlayerWindowMove(gameState, player.id)

        -- 记录历史
        table.insert(gameState.transfers.history, {
            playerId = player.id,
            playerName = player.displayName,
            fromTeamId = bid.sellerTeamId,
            toTeamId = bid.buyerTeamId,
            amount = bid.amount,
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        })

        bid.status = "completed"

        -- 通知玩家（可被调用方抑制以发送自定义消息）
        if not (opts and opts.suppressMessage) then
            gameState:sendMessage({
                category = "transfer",
                title = "转会完成!",
                body = string.format("%s 已正式加盟球队！转会费: %s",
                    player.displayName, fmtMoney(bid.amount)),
                priority = "normal",
            })
        end

        NewsGenerator.publishTransferNews(gameState, {
            playerId = player.id,
            fromTeamId = bid.sellerTeamId,
            toTeamId = bid.buyerTeamId,
            amount = bid.amount,
            type = "permanent",
        })

        EventBus.emit("transfer_completed", bid)

        -- 清理同一球员的其他活跃报价（球员已转会）
        TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {
            excludeBidId = bid.id,
            soldToTeamId = bid.buyerTeamId,
        })
    end
end
