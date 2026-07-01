-- systems/transfers/loans.lua
-- 租借出价/上架/生命周期，从 transfer_manager.lua 拆分。

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
    -- 租借系统
    ------------------------------------------------------

    --- 估算转会报价的合理周薪（与 AI 买人逻辑一致）
    function TransferManager.getSuggestedTransferWage(player, team, gameState)
        local FinanceManager = require("scripts/systems/finance_manager")
        return FinanceManager.estimateMarketWage(player, team, gameState)
    end

    --- 计算参考租借费（周薪 × 租期 × 0.5）
    function TransferManager.getLoanFeeBenchmark(player, duration)
        duration = duration or (player and player.loanListDuration) or 26
        return math.floor((player and player.wage or 0) * duration * 0.5)
    end

    --- 尝试租借条款协商（工资分担等）
    function TransferManager._attemptLoanTerms(gameState, bid)
        local player = gameState.players[bid.playerId]
        if not player then return end

        bid.personalTermsAttempts = (bid.personalTermsAttempts or 0) + 1

        local consent, reason = TransferManager._requirePlayerConsentForLoan(gameState, bid)
        local maxAttempts = bid.maxPersonalTermsAttempts or 3
        local wageShare = bid.wageShare or 0.5

        if consent then
            bid.status = "awaiting_confirmation"
            bid.confirmDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "球员同意外租!",
                body = string.format(
                    "%s 已同意租借至你的球队（%d周，租借费 %s，你方承担 %.0f%% 工资）。是否确认租入？",
                    player.displayName, bid.loanDuration or 26, fmtMoney(bid.amount), wageShare * 100),
                priority = "high",
                popup = true,
                actions = {
                    { label = "确认租入", actionId = "confirm_loan", data = { bidId = bid.id } },
                    { label = "放弃租借", actionId = "cancel_loan", data = { bidId = bid.id } },
                },
            })
        else
            if bid.personalTermsAttempts >= maxAttempts then
                local deadlineNote = bid.isDeadlineDeal and "（关窗日无更多协商时间）" or ""
                TransferManager._rejectBid(gameState, bid,
                    string.format("与 %s 的租借条款协商已失败%d次，交易取消。%s",
                        player.displayName, maxAttempts, deadlineNote))
            else
                bid.status = "fee_agreed"
                bid.personalTermsNegotiateDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                local remaining = maxAttempts - bid.personalTermsAttempts
                gameState:sendMessage({
                    category = "transfer",
                    title = "球员拒绝租借条款",
                    body = string.format(
                        "%s 拒绝了当前租借条件（%s）。租借费协议仍有效，可提高工资分担比例后重新协商（剩余 %d 次机会）。%s",
                        player.displayName, reason or "条件不满意",
                        remaining,
                        bid.isDeadlineDeal and "\n⚠️ 窗口即将关闭，请抓紧时间！" or ""),
                    priority = "high",
                    popup = true,
                    data = { bidId = bid.id, type = "loan_terms_rejected" },
                })
            end
        end
    end

    --- 玩家调整工资分担后重新协商租借条款
    function TransferManager.negotiateLoanTerms(gameState, bidId, newWageShare)
        TransferManager._ensureData(gameState)
        newWageShare = math.max(0.3, math.min(1.0, newWageShare or 0.5))
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "fee_agreed" and bid.type == "loan" then
                if bid.buyerTeamId ~= gameState.playerTeamId then
                    return nil, "只能协商自己的租借报价"
                end
                local player = gameState.players[bid.playerId]
                bid.wageShare = newWageShare
                bid.wageOffer = math.floor((player and player.wage or 0) * newWageShare)
                bid.status = "player_considering"
                bid.playerConsiderDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                bid.playerConsiderDays = 1 + math.floor(Random() * 2)
                gameState:sendMessage({
                    category = "transfer",
                    title = "租借条款已提出",
                    body = string.format("已向 %s 提出新的租借条件（你方承担 %.0f%% 工资），球员正在考虑中...",
                        player and player.displayName or "该球员", newWageShare * 100),
                    priority = "normal",
                })
                return bid, nil
            end
        end
        return nil, "未找到待协商的租借报价"
    end

    --- 玩家确认租入
    function TransferManager.confirmLoan(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "awaiting_confirmation" and bid.type == "loan" then
                bid.status = "accepted"
                local ok, err = TransferManager._completeLoan(gameState, bid)
                if not ok then return nil, err end
                return bid, nil
            end
        end
        return nil, "未找到待确认的租借"
    end

    --- 玩家放弃租借
    function TransferManager.cancelLoanConfirmation(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.id == bidId and bid.status == "awaiting_confirmation" and bid.type == "loan" then
                local player = gameState.players[bid.playerId]
                bid.status = "cancelled"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "租借已放弃",
                    body = string.format("你放弃了租入 %s 的交易。",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
                return bid, nil
            end
        end
        return nil, "未找到待确认的租借"
    end

    --- AI 俱乐部回应租借费报价（复用转会多轮谈判逻辑）
    function TransferManager._processAILoanResponse(gameState, bid)
        if bid.isIncomingBid or bid.isPushSale or bid.buyerTeamId ~= gameState.playerTeamId then
            return
        end

        local player = gameState.players[bid.playerId]
        if not player then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return
        end

        local benchmark = math.max(bid.playerValue or TransferManager.getLoanFeeBenchmark(player, bid.loanDuration), 1)
        local ratio = (bid.amount or 0) / benchmark
        local round = bid.currentRound or 0
        local mood = bid.mood or 50
        local maxRounds = bid.maxRounds or 4
        local diffMods = DifficultySettings.getTransferModifiers()

        local acceptThreshold = 1.15 - (mood / 200) - round * 0.05 + diffMods.thresholdOffset
        if player.listedForLoan then acceptThreshold = acceptThreshold - 0.2 end
        if player.squadRole == "youth" or player.squadRole == "squad" then acceptThreshold = acceptThreshold - 0.08 end
        if player.squadRole == "key" then acceptThreshold = acceptThreshold + 0.15 end

        local age = player.getAge and player:getAge(gameState.date.year) or 26
        local ageFactor = math.max(-0.1, math.min(0.1, (26 - age) * 0.015))
        acceptThreshold = acceptThreshold + ageFactor

        if ratio >= math.max(acceptThreshold, 0.85) then
            TransferManager._acceptBid(gameState, bid)
        elseif round >= maxRounds then
            TransferManager._rejectBid(gameState, bid, "租借费谈判回合耗尽，对方决定不出租。")
        elseif ratio >= 0.55 then
            bid.status = "negotiating"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            local baseMultiplier = 1.25 - round * 0.06 - (mood - 50) / 200 + ageFactor + diffMods.counterMultiplierOffset
            if not player.listedForLoan then baseMultiplier = baseMultiplier + 0.15 end
            if player.squadRole == "key" then baseMultiplier = baseMultiplier + 0.1 end
            baseMultiplier = baseMultiplier + (Random() - 0.5) * 0.08
            baseMultiplier = math.max(1.0, baseMultiplier)

            local counter = math.floor(benchmark * baseMultiplier / 1000) * 1000
            if counter <= bid.amount then
                TransferManager._acceptBid(gameState, bid)
                return
            end
            bid.counterAmount = counter
            bid.currentRound = round + 1

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
                title = "租借费还价",
                body = string.format(
                    "%s 拒绝了你的租借费 %s。\n%s 要求至少 %s 才愿意出租。\n(第%d/%d轮谈判)",
                    sellerName, fmtMoney(bid.amount),
                    sellerName, fmtMoney(counter),
                    (round + 1), maxRounds),
                priority = "high",
                popup = true,
            })
        else
            bid.mood = math.max(0, (bid.mood or 50) - 15)
            TransferManager._rejectBid(gameState, bid,
                string.format("你的租借费报价远低于 %s 的期望（参考 %s），对方直接拒绝了。",
                    player.displayName, fmtMoney(benchmark)))
        end
    end

    --- 发起租借报价（玩家操作）
    function TransferManager.makeLoanBid(gameState, playerId, duration, amount, wageShare)
        TransferManager._ensureData(gameState)

        local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
        if not windowOk then return nil, windowErr end

        local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
        if not cooldownOk then return nil, cooldownErr end

        local lockOk, lockErr = TransferManager._checkPreContractLock(gameState, playerId)
        if not lockOk then return nil, lockErr end

        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end
        if not player.teamId then return nil, "球员没有俱乐部" end
        if player.teamId == gameState.playerTeamId then return nil, "不能租借自己的球员" end
        if TransferManager.hasPendingBid(gameState, playerId) then return nil, "已有该球员的活跃报价" end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
        if not moveOk then return nil, moveErr end

        duration = duration or player.loanListDuration or 26
        wageShare = math.max(0.3, math.min(1.0, wageShare or 0.5))
        local benchmark = TransferManager.getLoanFeeBenchmark(player, duration)
        amount = amount or benchmark
        if amount <= 0 then return nil, "租借费必须大于0" end

        local bid = {
            id = gameState.transfers.nextBidId,
            playerId = playerId,
            buyerTeamId = gameState.playerTeamId,
            sellerTeamId = player.teamId,
            amount = amount,
            playerValue = benchmark,
            status = "pending",
            type = "loan",
            loanDuration = duration,
            wageShare = wageShare,
            wageOffer = math.floor((player.wage or 0) * wageShare),
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            responseDate = nil,
            counterAmount = nil,
            currentRound = 0,
            maxRounds = randInt(3, 5),
            mood = math.max(0, math.min(100, 50 - DifficultySettings.getTransferModifiers().moodPenalty)),
            rounds = {},
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.bids, bid)

        gameState:sendMessage({
            category = "transfer",
            title = "租借报价已提交",
            body = string.format("你对 %s 的租借报价已提交（%d周，租借费 %s，你方承担 %.0f%% 工资）。",
                player.displayName, duration, fmtMoney(amount), wageShare * 100),
            priority = "normal",
        })

        return bid
    end

    --- 处理租借到期（由 turn_processor 每日调用）
    function TransferManager.processLoanExpiry(gameState)
        TransferManager._ensureData(gameState)

        if not gameState._activeLoans then gameState._activeLoans = {} end

        local expired = {}
        for i, loan in ipairs(gameState._activeLoans) do
            -- 兼容旧存档：将 remainingWeeks 转为整数天数
            if not loan.remainingDays then
                loan.remainingDays = math.floor((loan.remainingWeeks or 0) * 7 + 0.5)
            end
            loan.remainingDays = loan.remainingDays - 1
            if loan.remainingDays <= 0 then
                table.insert(expired, i)
            end
        end

        -- 从后向前移除已到期租借
        for i = #expired, 1, -1 do
            local idx = expired[i]
            local loan = gameState._activeLoans[idx]
            TransferManager._returnLoanPlayer(gameState, loan)
            table.remove(gameState._activeLoans, idx)
        end
    end

    --- 完成租借（内部调用）
    function TransferManager._completeLoan(gameState, bid)
        local player = gameState.players[bid.playerId]
        if not player then
            if bid then bid.status = "rejected" end
            return false, "球员不存在"
        end

        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local sellerTeam = gameState.teams[bid.sellerTeamId]
        if not buyerTeam or not sellerTeam then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return false, "租借交易数据异常"
        end

        local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
        if not sellerOk then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return false, sellerErr
        end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
        if not moveOk then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return false, moveErr
        end

        local assignOpts = TransferManager.isInTransferWindow(gameState) and { allowOverCap = true } or nil
        if not TransferManager._assignPlayerToTeam(gameState, player, bid.buyerTeamId, assignOpts) then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return false, "租借方一线队已满员，租借无法完成"
        end

        player.squadRole = "loaned"
        player._loanOriginTeamId = bid.sellerTeamId
        player.listedForSale = false
        player.listedForLoan = false
        player.loanListDuration = nil

        TransferManager._markPlayerWindowMove(gameState, player.id)

        -- 扣除租借费
        buyerTeam.balance = buyerTeam.balance - bid.amount
        buyerTeam.seasonExpense = (buyerTeam.seasonExpense or 0) + bid.amount
        if sellerTeam then
            FinanceManager.processTransferIn(gameState, sellerTeam.id, bid.amount, player.displayName)
        end

        -- 记录活跃租借
        if not gameState._activeLoans then gameState._activeLoans = {} end
        table.insert(gameState._activeLoans, {
            playerId = player.id,
            playerName = player.displayName,
            originTeamId = bid.sellerTeamId,
            loanTeamId = bid.buyerTeamId,
            remainingDays = (bid.loanDuration or 0) * 7,  -- 转为整数天数，避免浮点误差
            wageShare = bid.wageShare,
        })

        bid.status = "completed"

        if bid.buyerTeamId == gameState.playerTeamId then
            gameState:sendMessage({
                category = "transfer",
                title = "租借完成!",
                body = string.format("%s 已租借加盟球队（%d周）。", player.displayName, bid.loanDuration),
                priority = "normal",
            })
        end

        NewsGenerator.publishTransferNews(gameState, {
            playerId = player.id,
            fromTeamId = bid.sellerTeamId,
            toTeamId = bid.buyerTeamId,
            amount = bid.amount or 0,
            type = "loan",
        })

        TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {
            excludeBidId = bid.id,
            soldToTeamId = bid.buyerTeamId,
        })
        return true, nil
    end

    --- 返还租借球员
    ---@param opts table|nil { reason = "recall"|nil }
    function TransferManager._returnLoanPlayer(gameState, loan, opts)
        opts = opts or {}
        local player = gameState.players[loan.playerId]
        if not player then return end

        local loanTeam = gameState.teams[loan.loanTeamId]
        local originTeam = gameState.teams[loan.originTeamId]

        player.listedForLoan = false
        player.loanListDuration = nil
        player.listedForSale = false

        -- 回到原球队（租借归队允许暂时突破硬顶，避免球员无处可去）
        TransferManager._assignPlayerToTeam(gameState, player, loan.originTeamId, { allowOverCap = true })
        player.squadRole = "first_team"
        player._loanOriginTeamId = nil

        -- 更新名气和身价
        if originTeam then
            player:calculateReputation(originTeam.reputation or 300)
        end
        player:calculateValue(gameState.date.year)

        if loan.loanTeamId == gameState.playerTeamId then
            local title = opts.reason == "recall" and "租借结束（召回）" or "租借到期"
            gameState:sendMessage({
                category = "transfer",
                title = title,
                body = string.format("%s 的租借期已满，已返回 %s。",
                    player.displayName, originTeam and originTeam.name or "原球队"),
                priority = "normal",
            })
        elseif opts.reason == "recall" and loan.originTeamId == gameState.playerTeamId then
            gameState:sendMessage({
                category = "transfer",
                title = "球员已召回",
                body = string.format("%s 已被提前召回。", player.displayName),
                priority = "normal",
            })
        end
    end
    --- 格式化租借剩余时间（天 → 周，向上取整）
    function TransferManager.formatLoanRemainingWeeks(loan)
        if not loan then return "?" end
        local days = loan.remainingDays
        if days == nil and loan.remainingWeeks then
            days = loan.remainingWeeks * 7
        end
        if not days then return "?" end
        return math.max(1, math.ceil(days / 7))
    end

    --- 查找球员当前活跃租借记录
    function TransferManager.getLoanForPlayer(gameState, playerId)
        for _, loan in ipairs(gameState._activeLoans or {}) do
            if loan.playerId == playerId then return loan end
        end
        return nil
    end

    --- 挂牌外租（出租方）
    function TransferManager.listForLoan(gameState, player, durationWeeks)
        if not player or not gameState then return false, "无效球员" end
        if player.teamId ~= gameState.playerTeamId then return false, "只能挂牌本队球员" end
        if TransferManager.isPlayerRejectingAllOffers(player) then return false, "该球员已设置拒绝所有报价" end
        if player.squadRole == "loaned" then return false, "球员已在外租" end
        if player.listedForSale then return false, "请先取消出售挂牌" end
        if player.injured then
            return false, player:getInjuryBlockReason() or "伤员无法挂牌外租"
        end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
        if not moveOk then return false, moveErr end

        local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
        if not windowOk then return false, windowErr end

        player.listedForLoan = true
        player.loanListDuration = durationWeeks or 26
        player.listedForSale = false
        TransferManager._invalidateListedPlayerCache(gameState)

        gameState:sendMessage({
            category = "transfer",
            title = player.displayName .. " 已挂牌外租",
            body = string.format("%s 已开放租借（默认 %d 周），等待其他球队报价。",
                player.displayName, player.loanListDuration or 26),
            priority = "normal",
        })
        return true
    end

    --- 取消外租挂牌
    function TransferManager.delistLoan(player)
        if not player then return end
        player.listedForLoan = false
        player.loanListDuration = nil
        if _G.gameState then TransferManager._invalidateListedPlayerCache(_G.gameState) end
    end

    --- 转会窗关闭后自动下架所有外租挂牌（窗内可挂牌，窗外不可展示/成交）
    ---@param opts table|nil { silent = boolean } 读档自愈时不发通知
    ---@return number delisted 下架人数
    ---@return number myDelisted 玩家球队下架人数
    function TransferManager.clearLoanListingsOutsideWindow(gameState, opts)
        opts = opts or {}
        if not gameState or TransferManager.isInTransferWindow(gameState) then
            return 0, 0
        end

        local delisted = 0
        local myDelisted = 0
        for _, player in pairs(gameState.players or {}) do
            if player.listedForLoan then
                local isMine = player.teamId == gameState.playerTeamId
                TransferManager.delistLoan(player)
                delisted = delisted + 1
                if isMine then myDelisted = myDelisted + 1 end
            end
        end
        if delisted > 0 then TransferManager._invalidateListedPlayerCache(gameState) end

        if not opts.silent and myDelisted > 0 then
            gameState:sendMessage({
                category = "transfer",
                title = "外租挂牌已下架",
                body = string.format(
                    "转会窗口已关闭，你球队的 %d 名外租挂牌已自动下架。下次开窗后可重新挂牌。",
                    myDelisted),
                priority = "normal",
            })
        end

        return delisted, myDelisted
    end

    --- 出租方强制召回（提前结束租期）
    function TransferManager.recallLoan(gameState, playerId)
        TransferManager._ensureData(gameState)
        local loan = TransferManager.getLoanForPlayer(gameState, playerId)
        if not loan then return false, "未找到活跃租借" end
        if loan.originTeamId ~= gameState.playerTeamId then
            return false, "只有出租方可召回球员"
        end

        TransferManager._returnLoanPlayer(gameState, loan, { reason = "recall" })
        for i, l in ipairs(gameState._activeLoans) do
            if l.playerId == playerId then
                table.remove(gameState._activeLoans, i)
                break
            end
        end

        return true
    end

    --- 清理同一球员上已失效的租借报价（球员已在队但 bid 仍停在待确认）
    function TransferManager._cancelStaleLoanBidsForPlayer(gameState, playerId, teamId)
        TransferManager._ensureData(gameState)
        if not playerId or not teamId then return end
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == playerId
                and bid.buyerTeamId == teamId
                and bid.type == "loan"
                and (bid.status == "awaiting_confirmation" or bid.status == "fee_agreed") then
                bid.status = "cancelled"
                bid.rejectedDate = {
                    year = gameState.date.year,
                    month = gameState.date.month,
                    day = gameState.date.day,
                }
            end
        end
    end

    --- 租借方续租（延长租期）
    function TransferManager.extendLoan(gameState, playerId, extraWeeks)
        TransferManager._ensureData(gameState)
        if not gameState._activeLoans then gameState._activeLoans = {} end
        extraWeeks = extraWeeks or 26
        local loan = TransferManager.getLoanForPlayer(gameState, playerId)
        if not loan then return false, "未找到活跃租借" end
        if loan.loanTeamId ~= gameState.playerTeamId then
            return false, "只有当前租用方可续租"
        end

        local player = gameState.players[playerId]
        local fee = player and math.floor((player.wage or 0) * extraWeeks * 0.35) or 0
        local team = gameState.teams[gameState.playerTeamId]
        if team and fee > 0 and team.balance < fee then
            return false, "余额不足以支付续租费用"
        end

        if not loan.remainingDays then
            loan.remainingDays = math.floor((tonumber(loan.remainingWeeks) or 0) * 7 + 0.5)
        end
        loan.remainingDays = (tonumber(loan.remainingDays) or 0) + extraWeeks * 7
        loan.remainingWeeks = nil

        TransferManager._cancelStaleLoanBidsForPlayer(gameState, playerId, gameState.playerTeamId)
        if team and fee > 0 then
            team.balance = team.balance - fee
            team.seasonExpense = (team.seasonExpense or 0) + fee
            local originTeam = gameState.teams[loan.originTeamId]
            if originTeam then
                originTeam.balance = originTeam.balance + fee
                originTeam.seasonIncome = (originTeam.seasonIncome or 0) + fee
            end
        end

        gameState:sendMessage({
            category = "transfer",
            title = "续租成功",
            body = string.format("%s 租期延长 %d 周。", player and player.displayName or "球员", extraWeeks),
            priority = "normal",
        })
        return true
    end

    --- 获取活跃租借列表
    function TransferManager.getActiveLoans(gameState)
        return gameState._activeLoans or {}
    end
end
