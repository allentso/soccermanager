-- systems/transfers/free_agents.lua
-- 自由球员签约状态机，从 transfer_manager.lua 拆分。

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

return function(TransferManager)
    ------------------------------------------------------
    -- 自由球员合同谈判状态机
    ------------------------------------------------------

    --- 发起自由球员合同谈判
    -- 返回 negotiation 对象或 nil + 错误消息
    function TransferManager.offerFreeAgent(gameState, playerId, wageOffer, yearsOffer)
        TransferManager._ensureData(gameState)

        local windowOk = TransferManager._checkTransferWindow(gameState)
        if not windowOk then
            return nil, "当前不在转会窗口期（夏窗7-8月/冬窗1月），无法签约自由球员"
        end

        -- 拒绝冷却期检查
        local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
        if not cooldownOk then return nil, cooldownErr end

        local lockOk, lockErr = TransferManager._checkPreContractLock(gameState, playerId)
        if not lockOk then return nil, lockErr end

        local player = gameState.players[playerId]
        if not player then return nil, "球员不存在" end
        if player.teamId then return nil, "球员已有球队" end
        if player.retired then return nil, "球员已退役" end

        local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
        if not moveOk then return nil, moveErr end

        local team = gameState:getPlayerTeam()
        if not team then return nil, "无法获取球队" end

        -- 检查是否已对该球员有进行中的谈判
        if not gameState.transfers.freeAgentNegos then
            gameState.transfers.freeAgentNegos = {}
        end
        for _, n in ipairs(gameState.transfers.freeAgentNegos) do
            if n.playerId == playerId
                and (n.status == "pending" or n.status == "negotiating"
                    or n.status == "awaiting_confirmation") then
                return nil, "已有进行中的谈判"
            end
        end

        wageOffer = wageOffer or player.wage
        yearsOffer = yearsOffer or 2

        -- 球员期望：基于能力和年龄
        local expectedWage = player.wage  -- 球员当前期望周薪
        local expectedYears = TransferManager._calcExpectedYears(player, gameState.date.year)

        local nego = {
            id = gameState.transfers.nextBidId,
            playerId = playerId,
            teamId = gameState.playerTeamId,
            status = "pending",       -- pending → negotiating → accepted/rejected/cancelled
            wageOffer = wageOffer,
            yearsOffer = yearsOffer,
            -- 球员期望（用于AI判断）
            expectedWage = expectedWage,
            expectedYears = expectedYears,
            -- AI谈判状态
            counterWage = nil,        -- AI还价周薪
            counterYears = nil,       -- AI还价年限
            currentRound = 0,
            maxRounds = randInt(2, 4),
            mood = 50,                -- 球员心情 0-100
            rounds = {},              -- 谈判历史
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            responseDate = nil,
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.freeAgentNegos, nego)

        gameState:sendMessage({
            category = "transfer",
            title = "合同谈判已发起",
            body = string.format("你向自由球员 %s 提出了合同邀约（周薪 %s，%d年）。等待回复...",
                player.displayName, fmtMoney(wageOffer), yearsOffer),
            priority = "normal",
        })

        return nego
    end

    --- 玩家修改合同条件（加薪/改合同年限）
    function TransferManager.reviseOffer(gameState, negoId, newWage, newYears)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return false, "无谈判数据" end

        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and nego.status == "negotiating" then
                if not nego.isPreContract then
                    local windowOk = TransferManager._checkTransferWindow(gameState)
                    if not windowOk then
                        return false, "当前不在转会窗口期（夏窗7-8月/冬窗1月），无法签约自由球员"
                    end
                end
                local player = gameState.players[nego.playerId]
                if not player then return false, "球员不存在" end

                nego.currentRound = (nego.currentRound or 0) + 1
                table.insert(nego.rounds, {
                    round = nego.currentRound,
                    offerWage = newWage,
                    offerYears = newYears,
                    counterWage = nego.counterWage,
                    counterYears = nego.counterYears,
                    result = "revised",
                })

                nego.wageOffer = newWage
                nego.yearsOffer = newYears
                nego.status = "pending"
                nego.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

                -- 修改条件改善心情
                local wageImprovement = (newWage - (nego.counterWage or nego.expectedWage)) / math.max(nego.expectedWage, 1) * 30
                local yearsBonus = (newYears >= (nego.counterYears or nego.expectedYears)) and 5 or -3
                nego.mood = math.min(100, math.max(0, (nego.mood or 50) + wageImprovement + yearsBonus + 3))

                gameState:sendMessage({
                    category = "transfer",
                    title = "修改合同条件",
                    body = string.format("你向 %s 提出了修改后的合同（周薪 %s，%d年）。第%d轮谈判。",
                        player.displayName, fmtMoney(newWage), newYears, nego.currentRound),
                    priority = "normal",
                })
                return true
            end
        end
        return false, "未找到该谈判"
    end

    --- 取消自由球员谈判
    function TransferManager.cancelFreeAgentNego(gameState, negoId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return false end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and (nego.status == "pending" or nego.status == "negotiating") then
                nego.status = "cancelled"
                return true
            end
        end
        return false
    end

    --- 玩家确认签入自由球员（公开API，从 inbox action 调用）
    function TransferManager.confirmFreeAgent(gameState, negoId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return nil, "无谈判数据" end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and nego.status == "awaiting_confirmation" then
                if not nego.isPreContract then
                    local windowOk = TransferManager._checkTransferWindow(gameState)
                    if not windowOk then
                        nego.status = "cancelled"
                        nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                        return nil, "当前不在转会窗口期（夏窗7-8月/冬窗1月），无法签约自由球员"
                    end
                end
                local player = gameState.players[nego.playerId]
                local team = gameState.teams[nego.teamId]
                if not player or not team then
                    nego.status = "rejected"
                    return nil, "球员或球队数据异常"
                end
                -- 防止重复签约
                if player.teamId then
                    nego.status = "cancelled"
                    gameState:sendMessage({
                        category = "transfer",
                        title = "签约失败",
                        body = string.format("%s 已被其他球队签下。", player.displayName),
                        priority = "normal",
                    })
                    return nil, "球员已被签走"
                end
                -- 检查工资预算
                local canAfford, reason = TransferManager.checkWageBudget(gameState, nego.teamId, nego.wageOffer)
                if not canAfford then
                    nego.status = "rejected"
                    gameState:sendMessage({
                        category = "transfer",
                        title = "签约失败",
                        body = string.format("无法签下 %s：%s", player.displayName, reason),
                        priority = "normal",
                    })
                    return nil, reason
                end
                -- 执行签约
                nego.status = "accepted"
                if team:isSquadFullFor(gameState) then
                    nego.status = "rejected"
                    gameState:sendMessage({
                        category = "transfer",
                        title = "签约失败",
                        body = string.format("无法签下 %s：一线队已满员（最多 %d 人）。",
                            player.displayName, team:getEffectiveSquadMax(gameState)),
                        priority = "normal",
                    })
                    return nil, "一线队已满员"
                end
                if not TransferManager._assignPlayerToTeam(gameState, player, team.id) then
                    nego.status = "rejected"
                    return nil, "一线队已满员"
                end
                player.wage = nego.wageOffer
                player.contractEnd = {year = gameState.date.year + nego.yearsOffer, month = 6}
                player.squadRole = "first_team"
                player.listedForSale = false
                player:calculateReputation(team.reputation or 300)
                player:calculateValue(gameState.date.year)
                TransferManager._markPlayerWindowMove(gameState, player.id)
                gameState:sendMessage({
                    category = "transfer",
                    title = "自由签约完成!",
                    body = string.format("%s 已作为自由球员加盟球队（周薪 %s，合同 %d年）。",
                        player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
                    priority = "normal",
                })
                NewsGenerator.publishTransferNews(gameState, {
                    playerId = player.id,
                    toTeamId = team.id,
                    amount = 0,
                    type = "free",
                })
                local ok, HistoryManager = pcall(require, "scripts/systems/history_manager")
                if ok and HistoryManager then
                    HistoryManager.recordTransfer(gameState, {
                        playerId = player.id,
                        playerName = player.displayName,
                        fromTeamId = nil,
                        toTeamId = team.id,
                        amount = 0,
                        type = "free",
                        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
                    })
                end
                EventBus.emit("transfer_completed", {playerId = player.id, teamId = team.id, type = "free"})
                return nego, nil
            end
        end
        return nil, "未找到待确认的自由球员签约"
    end

    --- 玩家放弃自由球员签约（公开API，从 inbox action 调用）
    function TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return false end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId and nego.status == "awaiting_confirmation" then
                local player = gameState.players[nego.playerId]
                nego.status = "cancelled"
                nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "签约已放弃",
                    body = string.format("你放弃了签入自由球员 %s。",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
                return true
            end
        end
        return false
    end

    --- 获取玩家的自由球员谈判列表
    function TransferManager.getFreeAgentNegos(gameState)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then
            gameState.transfers.freeAgentNegos = {}
        end
        local result = {}
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.teamId == gameState.playerTeamId then
                table.insert(result, nego)
            end
        end
        table.sort(result, function(a, b) return a.id > b.id end)
        return result
    end

    --- 获取指定谈判
    function TransferManager.getFreeAgentNegoById(gameState, negoId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return nil end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.id == negoId then return nego end
        end
        return nil
    end

    --- 检查是否已对某自由球员有pending谈判
    function TransferManager.hasPendingFreeAgentNego(gameState, playerId)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return false end
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.playerId == playerId
                and (nego.status == "pending" or nego.status == "negotiating"
                    or nego.status == "awaiting_confirmation") then
                return true
            end
        end
        return false
    end

    --- AI 每日处理自由球员谈判（由 processDailyBids 的调用者一并调用）
    function TransferManager.processDailyFreeAgentNegos(gameState)
        TransferManager._ensureData(gameState)
        if not gameState.transfers.freeAgentNegos then return end

        if not TransferManager.isInTransferWindow(gameState) then
            local cancelled = 0
            for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
                if not nego.isPreContract and _ACTIVE_FREE_AGENT_NEGO_STATUSES[nego.status] then
                    nego.status = "cancelled"
                    nego.cancelReason = "transfer_window_closed"
                    nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                    cancelled = cancelled + 1
                end
            end
            if cancelled > 0 then
                gameState:sendMessage({
                    category = "transfer",
                    title = "自由球员谈判已取消",
                    body = string.format("转会窗口已关闭，%d 笔未完成的自由球员签约已自动取消。", cancelled),
                    priority = "normal",
                })
            end
        end

        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.status == "pending" then
                local refDate = nego.responseDate or nego.date
                local daysSince = TransferManager._daysBetween(refDate, gameState.date)
                local waitDays = (nego.currentRound or 0) > 0 and 1 or randInt(1, 2)
                if daysSince >= waitDays then
                    TransferManager._processFreeAgentResponse(gameState, nego)
                end
            elseif nego.status == "negotiating" then
                -- 等太久玩家没回应
                local daysSinceResponse = TransferManager._daysBetween(nego.responseDate or nego.date, gameState.date)
                if daysSinceResponse >= 4 then
                    nego.mood = math.max(0, (nego.mood or 50) - 25)
                    if (nego.currentRound or 0) >= (nego.maxRounds or 3) then
                        nego.status = "rejected"
                        nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                        local player = gameState.players[nego.playerId]
                        gameState:sendMessage({
                            category = "transfer",
                            title = "谈判破裂",
                            body = string.format("%s 认为你缺乏诚意，拒绝了加盟邀请。",
                                player and player.displayName or "该球员"),
                            priority = "normal",
                        })
                    else
                        nego.status = "rejected"
                        nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                        local player = gameState.players[nego.playerId]
                        gameState:sendMessage({
                            category = "transfer",
                            title = "谈判失败",
                            body = string.format("%s 等待太久，已接受其他球队的邀请。",
                                player and player.displayName or "该球员"),
                            priority = "normal",
                        })
                    end
                end
            elseif nego.status == "awaiting_confirmation" then
                if TransferManager.isFreeAgentSignDeferred(nego, gameState) then
                    goto continue_free_nego_timeout
                end
                -- 玩家未及时确认，球员失去耐心（5天超时，推迟后延长3天）
                local confirmDate = nego.confirmDate or nego.responseDate or nego.date
                local daysSince = TransferManager._daysBetween(confirmDate, gameState.date)
                local limit = SIGN_CONFIRM_TIMEOUT_DAYS + (nego.confirmDeferUsed and SIGN_CONFIRM_DEFER_DAYS or 0)
                if daysSince >= limit then
                    nego.status = "rejected"
                    nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                    local player = gameState.players[nego.playerId]
                    gameState:sendMessage({
                        category = "transfer",
                        title = "签约机会错过",
                        body = string.format("%s 等不到你的回复，已转投其他球队。",
                            player and player.displayName or "该球员"),
                        priority = "normal",
                    })
                end
            end
            ::continue_free_nego_timeout::
        end
    end

    --- AI 回应自由球员谈判
    function TransferManager._processFreeAgentResponse(gameState, nego)
        local player = gameState.players[nego.playerId]
        if not player then
            nego.status = "rejected"
            return
        end

        local wageRatio = nego.wageOffer / math.max(nego.expectedWage, 1)
        local yearsOk = nego.yearsOffer >= (nego.expectedYears or 2)
        local round = nego.currentRound or 0
        local mood = nego.mood or 50
        local maxRounds = nego.maxRounds or 3

        -- 超轮次直接拒绝
        if round >= maxRounds then
            nego.status = "rejected"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "谈判破裂",
                body = string.format("%s 在多轮谈判后决定不加入你的球队。", player.displayName),
                priority = "normal",
            })
            return
        end

        -- 接受阈值：wage >= expected * threshold, 且年限合适
        -- mood好时阈值低（球员愿意降薪）
        local wageThreshold = 1.0 - (mood / 300) - round * 0.03  -- mood=100,round=3时阈值≈0.57
        wageThreshold = math.max(0.7, wageThreshold)  -- 最低不能低于0.7倍期望

        if wageRatio >= wageThreshold and yearsOk then
            -- 接受
            TransferManager._completeFreeAgentSigning(gameState, nego)
        elseif wageRatio >= 0.5 then
            -- 还价
            nego.status = "negotiating"
            nego.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            -- 计算counter wage：球员要求的工资（随轮次逐渐降低要求）
            local baseMultiplier = 1.1 - round * 0.05  -- 第0轮要1.1x,第3轮要0.95x
            -- mood好时要价更低
            baseMultiplier = baseMultiplier - (mood - 50) / 250
            baseMultiplier = math.max(0.85, baseMultiplier)

            local counterWage = math.floor(nego.expectedWage * baseMultiplier / 100) * 100
            -- counter不能低于玩家已出价（否则直接接受）
            if counterWage <= nego.wageOffer then
                TransferManager._completeFreeAgentSigning(gameState, nego)
                return
            end
            nego.counterWage = counterWage

            -- 合同年限：球员年轻想短约，老球员想长约
            local counterYears = nego.expectedYears
            if not yearsOk then
                counterYears = nego.expectedYears
            else
                counterYears = nego.yearsOffer  -- 年限ok就不还价
            end
            nego.counterYears = counterYears

            table.insert(nego.rounds, {
                round = round + 1,
                offerWage = nego.wageOffer,
                offerYears = nego.yearsOffer,
                counterWage = counterWage,
                counterYears = counterYears,
                result = "counter",
            })

            gameState:sendMessage({
                category = "transfer",
                title = "合同还价",
                body = string.format(
                    "%s 拒绝了你的合同条件（周薪 %s/%d年）。\n他要求至少 周薪 %s / %d年 才愿意签约。\n(第%d/%d轮谈判)",
                    player.displayName,
                    fmtMoney(nego.wageOffer), nego.yearsOffer,
                    fmtMoney(counterWage), counterYears,
                    (round + 1), maxRounds),
                priority = "high",
                popup = true,
            })
        else
            -- 出价太低，直接拒绝
            nego.status = "rejected"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            nego.mood = math.max(0, (nego.mood or 50) - 20)
            gameState:sendMessage({
                category = "transfer",
                title = "邀约被拒",
                body = string.format("%s 认为你的工资报价太低，直接拒绝了加盟邀请。(期望至少 %s/周)",
                    player.displayName, fmtMoney(nego.expectedWage)),
                priority = "normal",
            })
        end
    end

    --- 完成自由球员签约（内部调用）
    function TransferManager._completeFreeAgentSigning(gameState, nego)
        local player = gameState.players[nego.playerId]
        if not player then
            nego.status = "rejected"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return
        end

        if not nego.isPreContract then
            local windowOk = TransferManager._checkTransferWindow(gameState)
            if not windowOk then
                nego.status = "cancelled"
                nego.cancelReason = "transfer_window_closed"
                nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                return
            end
        end

        -- 防止重复签约：球员已有球队时直接取消
        if player.teamId then
            nego.status = "cancelled"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return
        end

        local team = gameState.teams[nego.teamId]
        if not team then
            nego.status = "rejected"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return
        end

        -- 检查工资预算是否能承担新球员薪水
        local canAfford, reason = TransferManager.checkWageBudget(gameState, nego.teamId, nego.wageOffer)
        if not canAfford then
            nego.status = "rejected"
            nego.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "签约失败",
                body = string.format("无法签下自由球员 %s：%s",
                    player.displayName, reason),
                priority = "normal",
            })
            return
        end

        -- 预签约：不立即转移球员，等合同到期后由 processPreContracts 执行
        if nego.isPreContract then
            nego.status = "accepted"
            player.preContractLockedBy = nego.teamId  -- 锁定标记
            gameState:sendMessage({
                category = "transfer",
                title = "预签约达成!",
                body = string.format("%s 同意预签约（周薪 %s，%d年）。合同到期后正式加入。",
                    player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
                priority = "normal",
            })
            NewsGenerator.publishTransferNews(gameState, {
                playerId = player.id,
                fromTeamId = player.teamId,
                toTeamId = nego.teamId,
                amount = 0,
                type = "precontract",
            })
            return
        end

        -- 自由球员同意加盟，等待玩家最终确认
        -- 只有玩家自己发起的谈判需要确认（非AI内部调用）
        if nego.teamId == gameState.playerTeamId then
            nego.status = "awaiting_confirmation"
            nego.confirmDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "球员同意签约!",
                body = string.format(
                    "%s 愿意以自由身加盟（周薪 %s，%d年）。是否确认签入？",
                    player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
                priority = "high",
                popup = true,
                actions = {
                    { label = "确认签入", actionId = "confirm_free_agent", data = { negoId = nego.id } },
                    { label = "放弃签约", actionId = "cancel_free_agent", data = { negoId = nego.id } },
                },
            })
            return
        end

        -- AI球队签约自由球员：立即执行
        nego.status = "accepted"
        TransferManager._assignPlayerToTeam(gameState, player, team.id)
        player.wage = nego.wageOffer
        player.contractEnd = {year = gameState.date.year + nego.yearsOffer, month = 6}
        player.squadRole = "first_team"
        player.listedForSale = false

        -- 更新名气和身价
        player:calculateReputation(team.reputation or 300)
        player:calculateValue(gameState.date.year)

        gameState:sendMessage({
            category = "transfer",
            title = "自由签约完成!",
            body = string.format("%s 已作为自由球员加盟球队（周薪 %s，合同 %d年）。",
                player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
            priority = "normal",
        })

        NewsGenerator.publishTransferNews(gameState, {
            playerId = player.id,
            toTeamId = team.id,
            amount = 0,
            type = "free",
        })

        -- 记录到历史
        local ok, HistoryManager = pcall(require, "scripts/systems/history_manager")
        if ok then
            HistoryManager.recordTransfer(gameState, {
                playerId = player.id,
                playerName = player.displayName,
                fromTeamId = nil,
                toTeamId = team.id,
                amount = 0,
                type = "free",
            })
        end
    end

    --- 计算球员期望合同年限
    function TransferManager._calcExpectedYears(player, currentYear)
        local age = 25
        if currentYear and player.birthYear then
            age = currentYear - player.birthYear
        elseif player.getAge and currentYear then
            age = player:getAge(currentYear)
        end
        if age >= 33 then return 1 end     -- 老将想要至少1年保障
        if age >= 30 then return 2 end     -- 30+想要2年
        if age >= 27 then return 3 end     -- 巅峰球员想要3年
        return 2                            -- 年轻球员接受2年
    end

    --- 旧接口保持向后兼容（直接签约，用于AI签约等内部流程）
    function TransferManager.signFreeAgent(gameState, playerId, wage, years)
        TransferManager._ensureData(gameState)
        local windowOk = TransferManager._checkTransferWindow(gameState)
        if not windowOk then
            return false, "当前不在转会窗口期（夏窗7-8月/冬窗1月），无法签约自由球员"
        end

        local player = gameState.players[playerId]
        if not player then return false, "球员不存在" end
        if player.teamId then return false, "球员已有球队" end
        if player.retired then return false, "球员已退役" end

        local team = gameState:getPlayerTeam()
        if not team then return false, "无法获取球队" end
        if FinanceManager.isTransferRestricted(team) then
            return false, "财务危机中：董事会限制新签约"
        end

        wage = wage or player.wage
        years = years or 2

        TransferManager._assignPlayerToTeam(gameState, player, team.id)
        player.wage = wage
        player.contractEnd = {year = gameState.date.year + years, month = 6}
        player.squadRole = "first_team"
        player.listedForSale = false

        gameState:sendMessage({
            category = "transfer",
            title = "自由签约完成!",
            body = string.format("%s 已作为自由球员加盟球队（周薪 %s，合同 %d年）。",
                player.displayName, fmtMoney(wage), years),
            priority = "normal",
        })

        NewsGenerator.publishTransferNews(gameState, {
            playerId = player.id,
            toTeamId = team.id,
            amount = 0,
            type = "free",
        })

        local ok, HistoryManager = pcall(require, "scripts/systems/history_manager")
        if ok then
            HistoryManager.recordTransfer(gameState, {
                playerId = player.id,
                playerName = player.displayName,
                fromTeamId = nil,
                toTeamId = team.id,
                amount = 0,
                type = "free",
            })
        end

        return true
    end

    --- 获取自由球员列表（无球队的非退役球员）
    --- positionFilter 可为位置组（GK/DEF/MID/FWD）或具体位置（CB/ST 等）
    function TransferManager.getFreeAgents(gameState, positionFilter)
        local Constants = require("scripts/app/constants")
        local result = {}
        local positionSet = nil
        if positionFilter then
            local groupPositions = Constants.POSITION_GROUPS[positionFilter]
            if groupPositions then
                positionSet = {}
                for _, pos in ipairs(groupPositions) do
                    positionSet[pos] = true
                end
            else
                local normalized = Constants.normalizePosition(positionFilter)
                positionSet = normalized and { [normalized] = true } or nil
            end
        end

        for _, player in pairs(gameState.players) do
            if not player.teamId and not player.retired
                and not player._isVirtual
                and not player.preContractLockedBy then
                if not positionSet or positionSet[player.position] then
                    table.insert(result, player)
                end
            end
        end

        -- 按能力排序
        table.sort(result, function(a, b) return a.overall > b.overall end)
        return result
    end
end
