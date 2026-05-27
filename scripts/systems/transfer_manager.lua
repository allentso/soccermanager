-- systems/transfer_manager.lua
-- 转会管理系统 - 处理出价、谈判、完成转会

local EventBus = require("scripts/app/event_bus")

local TransferManager = {}

------------------------------------------------------
-- 报价管理
------------------------------------------------------

-- 初始化转会数据（如果不存在）
function TransferManager._ensureData(gameState)
    if not gameState.transfers then
        gameState.transfers = {
            bids = {},       -- 所有活跃报价
            history = {},    -- 历史完成的转会
            nextBidId = 1,
        }
    end
    if not gameState.scoutReports then
        gameState.scoutReports = {}
    end
end

-- 发起报价
function TransferManager.makeBid(gameState, playerId, amount, wageOffer)
    TransferManager._ensureData(gameState)
    local player = gameState.players[playerId]
    if not player then return nil end

    -- 生成AI耐心上限（3-5轮）
    local maxRounds = RandomInt(3, 5)

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
        -- 多轮谈判新增字段
        counterAmount = nil,      -- AI的还价金额
        currentRound = 0,         -- 当前回合
        maxRounds = maxRounds,    -- 耐心上限
        mood = 50,                -- AI心情(0-100): 0=怒 50=中立 100=热情
        rounds = {},              -- 历史记录: {round, offer, counter, result}
    }

    gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
    table.insert(gameState.transfers.bids, bid)

    -- 通知消息
    gameState:sendMessage({
        category = "transfer",
        title = "报价已提交",
        body = string.format("你对 %s 的报价 (%.0fK) 已经提交，等待对方回复。",
            player.displayName, amount / 1000),
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

            -- 记录本轮
            bid.currentRound = (bid.currentRound or 0) + 1
            table.insert(bid.rounds, {
                round = bid.currentRound,
                offer = newAmount,
                counter = bid.counterAmount,
                result = "raised",
            })

            -- 更新出价
            bid.amount = newAmount
            if newWage then bid.wageOffer = newWage end
            bid.status = "pending"  -- 重新回到等待AI回应
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            -- 加价让AI心情好转
            local improvement = (newAmount - (bid.counterAmount or player.value)) / player.value * 40
            bid.mood = math.min(100, math.max(0, (bid.mood or 50) + improvement + 5))

            gameState:sendMessage({
                category = "transfer",
                title = "加价报价已提交",
                body = string.format("你对 %s 的加价报价 (%.0fK) 已提交，等待回复。(第%d轮)",
                    player.displayName, newAmount / 1000, bid.currentRound),
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
        if bid.id == bidId then return bid end
    end
    return nil
end

-- 检查是否已对某球员有pending报价
function TransferManager.hasPendingBid(gameState, playerId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and
           bid.buyerTeamId == gameState.playerTeamId and
           (bid.status == "pending" or bid.status == "negotiating") then
            return true
        end
    end
    return false
end

-- 获取玩家的所有报价
function TransferManager.getPlayerBids(gameState)
    TransferManager._ensureData(gameState)
    local result = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.buyerTeamId == gameState.playerTeamId then
            table.insert(result, bid)
        end
    end
    -- 按日期倒序
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

-- 获取别队对玩家球队球员的待处理报价（卖方视角）
function TransferManager.getPendingSellBids(gameState)
    TransferManager._ensureData(gameState)
    local result = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.sellerTeamId == gameState.playerTeamId and bid.status == "pending" then
            table.insert(result, bid)
        end
    end
    return result
end

-- 取消报价
function TransferManager.cancelBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" then
            bid.status = "cancelled"
            return true
        end
    end
    return false
end

------------------------------------------------------
-- AI 报价处理（每天调用）
------------------------------------------------------

function TransferManager.processDailyBids(gameState)
    TransferManager._ensureData(gameState)

    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "pending" then
            -- 1-2天后回复（加价轮次更快）
            local refDate = bid.responseDate or bid.date
            local daysSince = TransferManager._daysBetween(refDate, gameState.date)
            local waitDays = (bid.currentRound or 0) > 0 and 1 or RandomInt(1, 3)
            if daysSince >= waitDays then
                TransferManager._processAIResponse(gameState, bid)
            end
        elseif bid.status == "negotiating" then
            -- 谈判中如果超过耐心天数且玩家未加价 → 最终裁决
            local daysSinceResponse = TransferManager._daysBetween(bid.responseDate or bid.date, gameState.date)
            local maxRounds = bid.maxRounds or 4
            if daysSinceResponse >= 5 then
                -- 等太久没加价，AI失去耐心
                bid.mood = math.max(0, (bid.mood or 50) - 20)
                if (bid.currentRound or 0) >= maxRounds then
                    TransferManager._rejectBid(gameState, bid, "谈判破裂，对方已失去耐心。")
                else
                    TransferManager._rejectBid(gameState, bid, "你的回复太慢，对方决定不再等待。")
                end
            end
        end
    end
end

-- AI回应出价（生成具体counter-offer）
function TransferManager._processAIResponse(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then
        bid.status = "rejected"
        return
    end

    local ratio = bid.amount / math.max(player.value, 1)
    local round = bid.currentRound or 0
    local mood = bid.mood or 50
    local maxRounds = bid.maxRounds or 4

    -- 超过最大轮次 → 直接拒绝
    if round >= maxRounds then
        TransferManager._rejectBid(gameState, bid, "谈判回合耗尽，对方决定不出售。")
        return
    end

    -- 接受阈值：基础1.3，mood越高阈值越低
    local acceptThreshold = 1.3 - (mood / 200)  -- mood=100时阈值1.0, mood=0时阈值1.3
    -- 随着轮次增加，阈值降低（对方越来越务实）
    acceptThreshold = acceptThreshold - round * 0.05

    if ratio >= math.max(acceptThreshold, 0.9) then
        -- 达到接受阈值 → 直接接受
        TransferManager._acceptBid(gameState, bid)
    elseif ratio >= 0.6 then
        -- 进入/继续谈判 → 生成counter-offer
        bid.status = "negotiating"
        bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

        -- 计算AI还价：基于身价 * 倍率（随轮次逐渐降低）
        local baseMultiplier = 1.35 - round * 0.07  -- 第0轮1.35, 第3轮1.14
        -- mood越好，还价越低
        baseMultiplier = baseMultiplier - (mood - 50) / 200
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

        -- 记录本轮
        table.insert(bid.rounds, {
            round = round + 1,
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
                "%s 拒绝了你的 %.0fK 报价。\n%s 要求至少 %.0fK 才愿意放人。\n(第%d/%d轮谈判)",
                sellerName, bid.amount / 1000,
                sellerName, counter / 1000,
                (round + 1), maxRounds),
            priority = "high",
        })
    else
        -- 报价太低，直接拒绝
        bid.mood = math.max(0, (bid.mood or 50) - 15)
        TransferManager._rejectBid(gameState, bid,
            string.format("你的报价远低于 %s 的实际价值 (%.0fK)，对方直接拒绝了。",
                player.displayName, player.value / 1000))
    end
end

-- 接受报价
function TransferManager._acceptBid(gameState, bid)
    bid.status = "accepted"
    local player = gameState.players[bid.playerId]
    if not player then return end

    -- 完成转会
    TransferManager._completeTransfer(gameState, bid)
end

-- 拒绝报价
function TransferManager._rejectBid(gameState, bid, reason)
    bid.status = "rejected"
    local player = gameState.players[bid.playerId]
    gameState:sendMessage({
        category = "transfer",
        title = "报价被拒绝",
        body = reason or string.format("你对 %s 的报价已被拒绝。",
            player and player.displayName or "该球员"),
        priority = "normal",
    })
end

-- 完成转会
function TransferManager._completeTransfer(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then return end

    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not buyerTeam then return end

    -- 从卖方阵容移除
    if sellerTeam then
        for i, pid in ipairs(sellerTeam.playerIds) do
            if pid == player.id then
                table.remove(sellerTeam.playerIds, i)
                break
            end
        end
        -- 卖方获得转会费
        sellerTeam.balance = sellerTeam.balance + bid.amount
    end

    -- 加入买方阵容
    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = bid.buyerTeamId
    player.listedForSale = false
    player.listedForLoan = false

    -- 扣除转会费
    buyerTeam.balance = buyerTeam.balance - bid.amount

    -- 记录交易
    local transaction = {
        type = "transfer_out" ,
        amount = -bid.amount,
        description = "引进 " .. player.displayName,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
    }
    if not buyerTeam.transactions then buyerTeam.transactions = {} end
    table.insert(buyerTeam.transactions, 1, transaction)

    if sellerTeam then
        local sellTransaction = {
            type = "transfer_in",
            amount = bid.amount,
            description = "出售 " .. player.displayName,
            date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        }
        if not sellerTeam.transactions then sellerTeam.transactions = {} end
        table.insert(sellerTeam.transactions, 1, sellTransaction)
    end

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

    -- 通知玩家
    gameState:sendMessage({
        category = "transfer",
        title = "转会完成!",
        body = string.format("%s 已正式加盟球队！转会费: %.0fK",
            player.displayName, bid.amount / 1000),
        priority = "high",
    })

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %.0fK 的转会费从 %s 转会至 %s。",
            player.displayName, bid.amount / 1000,
            sellerTeam and sellerTeam.name or "自由球员市场",
            buyerTeam.name),
        relatedTeams = {bid.sellerTeamId, bid.buyerTeamId},
    })

    EventBus.emit("transfer_completed", bid)
end

------------------------------------------------------
-- 球探系统
------------------------------------------------------

-- 球探自动发现球员（每周调用）
function TransferManager.processScoutReport(gameState)
    TransferManager._ensureData(gameState)

    local team = gameState:getPlayerTeam()
    if not team then return end

    -- 查找球探
    local scoutAbility = 0
    local scoutCount = 0
    for _, sid in ipairs(team.staffIds) do
        local s = gameState.staff[sid]
        if s and s.role == "scout" then
            scoutAbility = scoutAbility + (s.ability or 10)
            scoutCount = scoutCount + 1
        end
    end
    if scoutCount == 0 then return end

    -- 每位球探每周发现1个球员
    local discoverCount = scoutCount
    local allPlayers = {}
    for _, p in pairs(gameState.players) do
        if p.teamId ~= gameState.playerTeamId and not p.retired then
            table.insert(allPlayers, p)
        end
    end
    if #allPlayers == 0 then return end

    for _ = 1, discoverCount do
        local idx = RandomInt(1, #allPlayers)
        local player = allPlayers[idx]

        -- 检查是否已有该球员的报告
        local already = false
        for _, r in ipairs(gameState.scoutReports) do
            if r.playerId == player.id then
                already = true
                break
            end
        end

        if not already then
            -- 球探评估潜力（有一定误差）
            local error_range = math.max(1, 15 - scoutAbility)
            local scoutedPotential = player.potential + RandomInt(-error_range, error_range)
            scoutedPotential = math.max(30, math.min(99, scoutedPotential))

            table.insert(gameState.scoutReports, 1, {
                playerId = player.id,
                scoutedPotential = scoutedPotential,
                discoveredDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            })

            -- 保留最近20条
            while #gameState.scoutReports > 20 do
                table.remove(gameState.scoutReports)
            end
        end
    end

    -- 通知
    if discoverCount > 0 then
        gameState:sendMessage({
            category = "scout",
            title = "球探报告",
            body = string.format("球探发现了 %d 名潜在引援目标，请在转会市场-球探页面查看。", discoverCount),
            priority = "low",
        })
    end
end

------------------------------------------------------
-- AI 主动出价系统
------------------------------------------------------

--- AI 球队每周主动寻找转会目标（由 turn_processor 周一调用）
function TransferManager.processAITransfers(gameState)
    TransferManager._ensureData(gameState)

    -- 转会窗口检查（简化：6-8月 和 1月为转会窗口）
    local month = gameState.date.month
    local inWindow = (month >= 6 and month <= 8) or month == 1
    if not inWindow then return end

    -- 每周每支AI球队有5%概率发起转会
    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto continue end
        if Random() > 0.05 then goto continue end

        -- 检查球队是否需要球员（阵容不足20人或某位置短缺）
        local need = TransferManager._assessTeamNeed(gameState, team)
        if not need then goto continue end

        -- 寻找合适目标
        local target = TransferManager._findTransferTarget(gameState, team, need)
        if not target then goto continue end

        -- AI 发起转会
        TransferManager._executeAITransfer(gameState, team, target)

        ::continue::
    end

    -- 额外机制：主动关注玩家挂牌球员（每个挂牌球员每天15%概率吸引买家）
    local playerTeam = gameState.teams[gameState.playerTeamId]
    if playerTeam then
        for _, pid in ipairs(playerTeam.playerIds) do
            local player = gameState.players[pid]
            if player and player.listedForSale and not TransferManager.hasPendingIncomingBid(gameState, pid) then
                if Random() < 0.15 then
                    -- 寻找有能力且有需求的买家
                    local buyer = TransferManager._findBuyerForPlayer(gameState, player)
                    if buyer then
                        TransferManager._executeAITransfer(gameState, buyer, player)
                    end
                end
            end
        end
    end
end

--- 评估球队需求（返回需要的位置或 nil）
function TransferManager._assessTeamNeed(gameState, team)
    local posCount = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    local Constants = require("scripts/app/constants")

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired and not player.injured then
            for group, positions in pairs(Constants.POSITION_GROUPS) do
                for _, pos in ipairs(positions) do
                    if player.position == pos then
                        posCount[group] = posCount[group] + 1
                    end
                end
            end
        end
    end

    -- 判断短缺
    if posCount.GK < 2 then return "GK" end
    if posCount.DEF < 4 then return "DEF" end
    if posCount.MID < 4 then return "MID" end
    if posCount.FWD < 3 then return "FWD" end

    -- 阵容太小
    if #team.playerIds < 18 then
        local groups = {"DEF", "MID", "FWD"}
        return groups[RandomInt(1, 3)]
    end

    return nil
end

--- 寻找转会目标
function TransferManager._findTransferTarget(gameState, buyerTeam, needGroup)
    local Constants = require("scripts/app/constants")
    local targetPositions = Constants.POSITION_GROUPS[needGroup] or {}
    local candidates = {}

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end
        if player.teamId == buyerTeam.id then goto continue end
        -- 玩家球队的球员：只有挂牌出售的才会被AI考虑
        if player.teamId == gameState.playerTeamId and not player.listedForSale then goto continue end

        -- 位置匹配
        local posMatch = false
        for _, pos in ipairs(targetPositions) do
            if player.position == pos then posMatch = true; break end
        end
        if not posMatch then goto continue end

        -- 财力检查（出价不超过球队余额的30%）
        if player.value > buyerTeam.balance * 0.3 then goto continue end

        -- 能力匹配（不买太弱或太强的）
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, buyerTeam)
        if player.overall < teamAvg - 10 or player.overall > teamAvg + 15 then goto continue end

        table.insert(candidates, player)
        ::continue::
    end

    if #candidates == 0 then return nil end

    -- 从候选中随机选一个
    return candidates[RandomInt(1, #candidates)]
end

--- 执行 AI 转会
function TransferManager._executeAITransfer(gameState, buyerTeam, player)
    local sellerTeam = gameState.teams[player.teamId]

    -- AI 报价 = 身价 × (1.0~1.3)
    local offerAmount = math.floor(player.value * (1.0 + Random() * 0.3))

    -- 如果目标是玩家球队球员（挂牌出售的），生成收购报价让玩家决定
    if player.teamId == gameState.playerTeamId then
        TransferManager._createIncomingBid(gameState, buyerTeam, player, offerAmount)
        return
    end

    -- 卖方判断是否接受
    local ratio = offerAmount / player.value
    local acceptChance = 0
    if ratio >= 1.3 then acceptChance = 0.9
    elseif ratio >= 1.1 then acceptChance = 0.6
    elseif ratio >= 0.9 then acceptChance = 0.3
    else acceptChance = 0.1 end

    -- 核心球员不轻易卖
    if player.overall >= 75 then
        acceptChance = acceptChance * 0.5
    end

    if Random() > acceptChance then return end  -- 卖方拒绝

    -- 完成转会
    if sellerTeam then
        for i, pid in ipairs(sellerTeam.playerIds) do
            if pid == player.id then
                table.remove(sellerTeam.playerIds, i)
                break
            end
        end
        sellerTeam.balance = sellerTeam.balance + offerAmount
    end

    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false
    player.listedForLoan = false
    buyerTeam.balance = buyerTeam.balance - offerAmount

    -- 记录
    table.insert(gameState.transfers.history, {
        playerId = player.id,
        playerName = player.displayName,
        fromTeamId = sellerTeam and sellerTeam.id or nil,
        toTeamId = buyerTeam.id,
        amount = offerAmount,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        isAI = true,
    })

    -- 生成新闻
    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %.0fK 的转会费从 %s 转会至 %s。",
            player.displayName, offerAmount / 1000,
            sellerTeam and sellerTeam.name or "自由球员市场",
            buyerTeam.name),
        relatedTeams = {sellerTeam and sellerTeam.id, buyerTeam.id},
    })

    -- 记录到历史系统
    local ok, HistoryManager = pcall(require, "scripts/systems/history_manager")
    if ok then
        HistoryManager.recordTransfer(gameState, {
            playerId = player.id,
            playerName = player.displayName,
            fromTeamId = sellerTeam and sellerTeam.id or nil,
            toTeamId = buyerTeam.id,
            amount = offerAmount,
            type = "permanent",
        })
    end
end

------------------------------------------------------
-- AI 对玩家球队球员的收购报价
------------------------------------------------------

--- 检查球员是否已有待处理的收购报价
function TransferManager.hasPendingIncomingBid(gameState, playerId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingBid and bid.status == "pending" then
            return true
        end
    end
    return false
end

--- 为挂牌球员寻找合适的买家
function TransferManager._findBuyerForPlayer(gameState, player)
    local Constants = require("scripts/app/constants")
    local candidates = {}

    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto skip end
        -- 财力检查
        if player.value > team.balance * 0.4 then goto skip end
        -- 能力匹配
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
        if player.overall < teamAvg - 8 or player.overall > teamAvg + 12 then goto skip end
        table.insert(candidates, team)
        ::skip::
    end

    if #candidates == 0 then return nil end
    return candidates[RandomInt(1, #candidates)]
end

--- 创建 AI 对玩家球员的收购报价（让玩家决策）
function TransferManager._createIncomingBid(gameState, buyerTeam, player, offerAmount)
    TransferManager._ensureData(gameState)

    local bid = {
        id = gameState.transfers.nextBidId,
        playerId = player.id,
        buyerTeamId = buyerTeam.id,
        sellerTeamId = gameState.playerTeamId,
        amount = offerAmount,
        playerValue = player.value,
        status = "pending",
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        responseDate = nil,
        wageOffer = player.wage,
        isIncomingBid = true,  -- 标记为收到的报价（区别于玩家发出的）
        currentRound = 0,
        maxRounds = 3,
        mood = 50,
        rounds = {},
    }

    gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
    table.insert(gameState.transfers.bids, bid)

    -- 通知消息
    gameState:sendMessage({
        category = "transfer",
        title = "收到报价: " .. player.displayName,
        body = string.format("%s 对 %s 出价 %.0fK（球员身价 %.0fK）。\n前往阵容页长按该球员处理报价。",
            buyerTeam.name, player.displayName, offerAmount / 1000, player.value / 1000),
        priority = "high",
        data = { bidId = bid.id, playerId = player.id },
    })

    return bid
end

--- 接受收到的报价（玩家操作）
function TransferManager.acceptIncomingBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" and bid.isIncomingBid then
            bid.status = "completed"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            TransferManager._completeIncomingSale(gameState, bid)
            return true
        end
    end
    return false
end

--- 拒绝收到的报价（玩家操作）
function TransferManager.rejectIncomingBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" and bid.isIncomingBid then
            bid.status = "rejected"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "报价已拒绝",
                body = string.format("你拒绝了 %s 对 %s 的报价（%.0fK）。",
                    buyerTeam and buyerTeam.name or "未知球队",
                    player and player.displayName or "未知球员",
                    bid.amount / 1000),
                priority = "normal",
            })
            return true
        end
    end
    return false
end

--- 完成收到的出售转会
function TransferManager._completeIncomingSale(gameState, bid)
    local player = gameState.players[bid.playerId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not player or not sellerTeam or not buyerTeam then return end

    -- 移出卖方球队
    for i, pid in ipairs(sellerTeam.playerIds) do
        if pid == player.id then
            table.remove(sellerTeam.playerIds, i)
            break
        end
    end
    -- 移出首发
    if sellerTeam.startingXI then
        for i, pid in ipairs(sellerTeam.startingXI) do
            if pid == player.id then
                table.remove(sellerTeam.startingXI, i)
                break
            end
        end
    end

    sellerTeam.balance = sellerTeam.balance + bid.amount
    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false
    buyerTeam.balance = buyerTeam.balance - bid.amount

    -- 记录转会历史
    table.insert(gameState.transfers.history, {
        playerId = player.id,
        playerName = player.displayName,
        fromTeamId = sellerTeam.id,
        toTeamId = buyerTeam.id,
        amount = bid.amount,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        isAI = false,
    })

    -- 通知
    gameState:sendMessage({
        category = "transfer",
        title = "转会完成: " .. player.displayName,
        body = string.format("%s 以 %.0fK 转会至 %s，资金已到账。",
            player.displayName, bid.amount / 1000, buyerTeam.name),
        priority = "high",
    })

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %.0fK 的转会费从 %s 转会至 %s。",
            player.displayName, bid.amount / 1000, sellerTeam.name, buyerTeam.name),
        relatedTeams = {sellerTeam.id, buyerTeam.id},
    })

    -- 记录到历史系统
    local ok, HistoryManager = pcall(require, "scripts/systems/history_manager")
    if ok then
        HistoryManager.recordTransfer(gameState, {
            playerId = player.id,
            playerName = player.displayName,
            fromTeamId = sellerTeam.id,
            toTeamId = buyerTeam.id,
            amount = bid.amount,
            type = "permanent",
        })
    end
end

------------------------------------------------------
-- 租借系统
------------------------------------------------------

--- 发起租借请求（玩家操作）
function TransferManager.makeLoanBid(gameState, playerId, duration)
    TransferManager._ensureData(gameState)
    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end
    if not player.teamId then return nil, "球员没有俱乐部" end
    if player.teamId == gameState.playerTeamId then return nil, "不能租借自己的球员" end

    -- 租借费 = 周薪 × 租期周数 × 0.5
    duration = duration or 26  -- 默认半赛季（26周）
    local loanFee = math.floor(player.wage * duration * 0.5)

    local bid = {
        id = gameState.transfers.nextBidId,
        playerId = playerId,
        buyerTeamId = gameState.playerTeamId,
        sellerTeamId = player.teamId,
        amount = loanFee,
        status = "pending",
        type = "loan",
        loanDuration = duration,  -- 周数
        wageShare = 0.5,  -- 租借方承担50%工资
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
    }

    gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
    table.insert(gameState.transfers.bids, bid)

    gameState:sendMessage({
        category = "transfer",
        title = "租借请求已提交",
        body = string.format("你对 %s 的租借请求已提交（%d周，租借费 %.0fK）。",
            player.displayName, duration, loanFee / 1000),
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
        loan.remainingWeeks = (loan.remainingWeeks or 0) - (1 / 7)  -- 每天减 1/7 周
        if loan.remainingWeeks <= 0 then
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
    if not player then return end

    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    if not buyerTeam then return end

    -- 球员标记为租借状态
    player.squadRole = "loaned"
    player._loanOriginTeamId = bid.sellerTeamId
    player.teamId = bid.buyerTeamId

    -- 从卖方阵容移除
    if sellerTeam then
        for i, pid in ipairs(sellerTeam.playerIds) do
            if pid == player.id then
                table.remove(sellerTeam.playerIds, i)
                break
            end
        end
    end

    -- 加入买方阵容
    table.insert(buyerTeam.playerIds, player.id)

    -- 扣除租借费
    buyerTeam.balance = buyerTeam.balance - bid.amount
    if sellerTeam then
        sellerTeam.balance = sellerTeam.balance + bid.amount
    end

    -- 记录活跃租借
    if not gameState._activeLoans then gameState._activeLoans = {} end
    table.insert(gameState._activeLoans, {
        playerId = player.id,
        playerName = player.displayName,
        originTeamId = bid.sellerTeamId,
        loanTeamId = bid.buyerTeamId,
        remainingWeeks = bid.loanDuration,
        wageShare = bid.wageShare,
    })

    bid.status = "completed"

    gameState:sendMessage({
        category = "transfer",
        title = "租借完成!",
        body = string.format("%s 已租借加盟球队（%d周）。", player.displayName, bid.loanDuration),
        priority = "high",
    })
end

--- 返还租借球员
function TransferManager._returnLoanPlayer(gameState, loan)
    local player = gameState.players[loan.playerId]
    if not player then return end

    local loanTeam = gameState.teams[loan.loanTeamId]
    local originTeam = gameState.teams[loan.originTeamId]

    -- 从租借球队移除
    if loanTeam then
        for i, pid in ipairs(loanTeam.playerIds) do
            if pid == player.id then
                table.remove(loanTeam.playerIds, i)
                break
            end
        end
    end

    -- 回到原球队
    if originTeam then
        table.insert(originTeam.playerIds, player.id)
    end
    player.teamId = loan.originTeamId
    player.squadRole = "first_team"
    player._loanOriginTeamId = nil

    -- 通知（如果涉及玩家球队）
    if loan.loanTeamId == gameState.playerTeamId then
        gameState:sendMessage({
            category = "transfer",
            title = "租借到期",
            body = string.format("%s 的租借期已满，已返回 %s。",
                player.displayName, originTeam and originTeam.name or "原球队"),
            priority = "normal",
        })
    elseif loan.originTeamId == gameState.playerTeamId then
        gameState:sendMessage({
            category = "transfer",
            title = "球员归队",
            body = string.format("%s 的租借期已满，已返回球队。", player.displayName),
            priority = "normal",
        })
    end
end

------------------------------------------------------
-- 自由球员合同谈判状态机
------------------------------------------------------

--- 发起自由球员合同谈判
-- 返回 negotiation 对象或 nil + 错误消息
function TransferManager.offerFreeAgent(gameState, playerId, wageOffer, yearsOffer)
    TransferManager._ensureData(gameState)
    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end
    if player.teamId then return nil, "球员已有球队" end
    if player.retired then return nil, "球员已退役" end

    local team = gameState:getPlayerTeam()
    if not team then return nil, "无法获取球队" end

    -- 检查是否已对该球员有进行中的谈判
    if not gameState.transfers.freeAgentNegos then
        gameState.transfers.freeAgentNegos = {}
    end
    for _, n in ipairs(gameState.transfers.freeAgentNegos) do
        if n.playerId == playerId and (n.status == "pending" or n.status == "negotiating") then
            return nil, "已有进行中的谈判"
        end
    end

    wageOffer = wageOffer or player.wage
    yearsOffer = yearsOffer or 2

    -- 球员期望：基于能力和年龄
    local expectedWage = player.wage  -- 球员当前期望周薪
    local expectedYears = TransferManager._calcExpectedYears(player)

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
        maxRounds = RandomInt(2, 4),
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
        body = string.format("你向自由球员 %s 提出了合同邀约（周薪 %.1fK，%d年）。等待回复...",
            player.displayName, wageOffer / 1000, yearsOffer),
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
                body = string.format("你向 %s 提出了修改后的合同（周薪 %.1fK，%d年）。第%d轮谈判。",
                    player.displayName, newWage / 1000, newYears, nego.currentRound),
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
        if nego.playerId == playerId and (nego.status == "pending" or nego.status == "negotiating") then
            return true
        end
    end
    return false
end

--- AI 每日处理自由球员谈判（由 processDailyBids 的调用者一并调用）
function TransferManager.processDailyFreeAgentNegos(gameState)
    TransferManager._ensureData(gameState)
    if not gameState.transfers.freeAgentNegos then return end

    for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
        if nego.status == "pending" then
            local refDate = nego.responseDate or nego.date
            local daysSince = TransferManager._daysBetween(refDate, gameState.date)
            local waitDays = (nego.currentRound or 0) > 0 and 1 or RandomInt(1, 2)
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
        end
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
                "%s 拒绝了你的合同条件（周薪 %.1fK/%d年）。\n他要求至少 周薪 %.1fK / %d年 才愿意签约。\n(第%d/%d轮谈判)",
                player.displayName,
                nego.wageOffer / 1000, nego.yearsOffer,
                counterWage / 1000, counterYears,
                (round + 1), maxRounds),
            priority = "high",
        })
    else
        -- 出价太低，直接拒绝
        nego.status = "rejected"
        nego.mood = math.max(0, (nego.mood or 50) - 20)
        gameState:sendMessage({
            category = "transfer",
            title = "邀约被拒",
            body = string.format("%s 认为你的工资报价太低，直接拒绝了加盟邀请。(期望至少 %.1fK/周)",
                player.displayName, nego.expectedWage / 1000),
            priority = "normal",
        })
    end
end

--- 完成自由球员签约（内部调用）
function TransferManager._completeFreeAgentSigning(gameState, nego)
    local player = gameState.players[nego.playerId]
    if not player then
        nego.status = "rejected"
        return
    end

    local team = gameState.teams[nego.teamId]
    if not team then
        nego.status = "rejected"
        return
    end

    nego.status = "accepted"

    -- 执行签约
    table.insert(team.playerIds, player.id)
    player.teamId = team.id
    player.wage = nego.wageOffer
    player.contractEnd = {year = gameState.date.year + nego.yearsOffer, month = 6}
    player.squadRole = "first_team"
    player.listedForSale = false

    gameState:sendMessage({
        category = "transfer",
        title = "自由签约完成!",
        body = string.format("%s 已作为自由球员加盟球队（周薪 %.1fK，合同 %d年）。",
            player.displayName, nego.wageOffer / 1000, nego.yearsOffer),
        priority = "high",
    })

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "自由签约: " .. player.displayName,
        body = string.format("%s 以自由身加盟 %s，签约 %d 年。",
            player.displayName, team.name, nego.yearsOffer),
        relatedTeams = {team.id},
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
function TransferManager._calcExpectedYears(player)
    local age = player.age or 25
    if age >= 33 then return 1 end     -- 老将想要至少1年保障
    if age >= 30 then return 2 end     -- 30+想要2年
    if age >= 27 then return 3 end     -- 巅峰球员想要3年
    return 2                            -- 年轻球员接受2年
end

--- 旧接口保持向后兼容（直接签约，用于AI签约等内部流程）
function TransferManager.signFreeAgent(gameState, playerId, wage, years)
    TransferManager._ensureData(gameState)
    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.teamId then return false, "球员已有球队" end
    if player.retired then return false, "球员已退役" end

    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队" end

    wage = wage or player.wage
    years = years or 2

    table.insert(team.playerIds, player.id)
    player.teamId = team.id
    player.wage = wage
    player.contractEnd = {year = gameState.date.year + years, month = 6}
    player.squadRole = "first_team"
    player.listedForSale = false

    gameState:sendMessage({
        category = "transfer",
        title = "自由签约完成!",
        body = string.format("%s 已作为自由球员加盟球队（周薪 %.1fK，合同 %d年）。",
            player.displayName, wage / 1000, years),
        priority = "high",
    })

    gameState:addNews({
        category = "transfer_news",
        title = "自由签约: " .. player.displayName,
        body = string.format("%s 以自由身加盟 %s，签约 %d 年。",
            player.displayName, team.name, years),
        relatedTeams = {team.id},
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
function TransferManager.getFreeAgents(gameState, positionFilter)
    local result = {}
    for _, player in pairs(gameState.players) do
        if not player.teamId and not player.retired then
            if not positionFilter or player.position == positionFilter then
                table.insert(result, player)
            end
        end
    end

    -- 按能力排序
    table.sort(result, function(a, b) return a.overall > b.overall end)
    return result
end

--- 获取活跃租借列表
function TransferManager.getActiveLoans(gameState)
    return gameState._activeLoans or {}
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

function TransferManager._daysBetween(date1, date2)
    -- 简化计算：假设每月30天
    local d1 = date1.year * 365 + date1.month * 30 + date1.day
    local d2 = date2.year * 365 + date2.month * 30 + date2.day
    return d2 - d1
end

function TransferManager._getTeamAverageOverall(gameState, team)
    local total = 0
    local count = 0
    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            total = total + player.overall
            count = count + 1
        end
    end
    return count > 0 and math.floor(total / count) or 50
end

------------------------------------------------------
-- ★ 主动向指定球队推销球员
------------------------------------------------------

--- 向指定球队推销球员（玩家操作）
--- @param gameState table
--- @param playerId number 要推销的球员ID
--- @param targetTeamId number 目标买家球队ID
--- @param askingPrice number|nil 要价（nil则用球员身价×1.2）
--- @return table|nil bid 生成的报价对象
--- @return string|nil error 错误信息
function TransferManager.offerToClub(gameState, playerId, targetTeamId, askingPrice)
    TransferManager._ensureData(gameState)
    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end
    if player.teamId ~= gameState.playerTeamId then return nil, "只能推销自己的球员" end

    local targetTeam = gameState.teams[targetTeamId]
    if not targetTeam then return nil, "目标球队不存在" end
    if targetTeamId == gameState.playerTeamId then return nil, "不能向自己推销" end

    -- 检查球队关系（如有敌对关系则拒绝）
    if TransferManager._isRivalry(gameState, gameState.playerTeamId, targetTeamId) then
        return nil, "对方与你的球队关系敌对，拒绝交易"
    end

    askingPrice = askingPrice or math.floor(player.value * 1.2)

    -- 检查目标球队是否买得起
    local budget = TransferManager._getTransferBudget(gameState, targetTeam)
    if askingPrice > budget * 0.6 then
        return nil, string.format("%s 的转会预算不足以支付要价", targetTeam.name)
    end

    -- 检查球员态度（球员可能拒绝去该球队）
    local willing, reason = TransferManager._checkPlayerWillingness(gameState, player, targetTeam)
    if not willing then
        return nil, string.format("%s 不愿意去 %s（%s）", player.displayName, targetTeam.name, reason)
    end

    -- 创建推销报价（标记为推销，AI视角处理）
    local bid = {
        id = gameState.transfers.nextBidId,
        playerId = playerId,
        buyerTeamId = targetTeamId,
        sellerTeamId = gameState.playerTeamId,
        amount = askingPrice,
        playerValue = player.value,
        status = "pending",
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        responseDate = nil,
        wageOffer = player.wage,
        isIncomingBid = false,
        isPushSale = true,  -- 标记为主动推销
        currentRound = 0,
        maxRounds = RandomInt(2, 4),
        mood = 40,  -- AI初始态度较保守（毕竟是被推销）
        rounds = {},
    }

    gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
    table.insert(gameState.transfers.bids, bid)

    gameState:sendMessage({
        category = "transfer",
        title = "推销报价已发出",
        body = string.format("你向 %s 推销了 %s（要价 %.0fK）。等待对方回复...",
            targetTeam.name, player.displayName, askingPrice / 1000),
        priority = "normal",
    })

    return bid
end

--- AI 处理收到的推销报价（每日在 processDailyBids 中调用）
function TransferManager._processPushSaleResponse(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then
        bid.status = "rejected"
        return
    end

    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not buyerTeam then
        bid.status = "rejected"
        return
    end

    -- AI 评估：球员是否满足需求
    local need = TransferManager._assessTeamNeed(gameState, buyerTeam)
    local teamAvg = TransferManager._getTeamAverageOverall(gameState, buyerTeam)
    local positionMatch = need and TransferManager._playerMatchesNeed(player, need)

    -- 基础兴趣度
    local interest = 30  -- 被推销的默认兴趣较低
    if positionMatch then interest = interest + 30 end
    if player.overall > teamAvg then interest = interest + 20 end
    if player.overall > teamAvg + 5 then interest = interest + 15 end

    -- 价格影响
    local ratio = bid.amount / math.max(player.value, 1)
    if ratio <= 0.9 then interest = interest + 20  -- 低于身价，划算
    elseif ratio <= 1.1 then interest = interest + 10
    elseif ratio > 1.4 then interest = interest - 30  -- 要价过高
    end

    -- 预算检查
    local budget = TransferManager._getTransferBudget(gameState, buyerTeam)
    if bid.amount > budget * 0.5 then interest = interest - 20 end

    if interest >= 60 then
        -- 有兴趣，但可能压价
        if ratio <= 1.1 then
            -- 价格合适，直接接受
            TransferManager._acceptPushSale(gameState, bid)
        else
            -- 还价
            bid.status = "negotiating"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            local counterRatio = 0.85 + Random() * 0.2  -- 0.85~1.05 × 身价
            local counter = math.floor(player.value * counterRatio / 1000) * 1000
            counter = math.max(counter, math.floor(bid.amount * 0.7))
            bid.counterAmount = counter

            table.insert(bid.rounds, {
                round = 1,
                offer = bid.amount,
                counter = counter,
                result = "counter",
            })

            gameState:sendMessage({
                category = "transfer",
                title = "推销还价",
                body = string.format("%s 对 %s 有兴趣，但只愿意出 %.0fK（你要价 %.0fK）。",
                    buyerTeam.name, player.displayName, counter / 1000, bid.amount / 1000),
                priority = "high",
            })
        end
    else
        -- 没兴趣
        bid.status = "rejected"
        gameState:sendMessage({
            category = "transfer",
            title = "推销被拒",
            body = string.format("%s 对 %s 没有兴趣。", buyerTeam.name, player.displayName),
            priority = "normal",
        })
    end
end

--- 接受推销还价（玩家操作）
function TransferManager.acceptPushSaleCounter(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.isPushSale and bid.status == "negotiating" then
            bid.amount = bid.counterAmount
            TransferManager._acceptPushSale(gameState, bid)
            return true
        end
    end
    return false
end

--- 拒绝推销还价（玩家操作）
function TransferManager.rejectPushSaleCounter(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.isPushSale and bid.status == "negotiating" then
            bid.status = "cancelled"
            gameState:sendMessage({
                category = "transfer",
                title = "推销取消",
                body = "你拒绝了对方的还价，推销已取消。",
                priority = "normal",
            })
            return true
        end
    end
    return false
end

--- 完成推销交易（内部）
function TransferManager._acceptPushSale(gameState, bid)
    bid.status = "completed"
    local player = gameState.players[bid.playerId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not player or not sellerTeam or not buyerTeam then return end

    -- 从卖方移除
    for i, pid in ipairs(sellerTeam.playerIds) do
        if pid == player.id then
            table.remove(sellerTeam.playerIds, i)
            break
        end
    end
    if sellerTeam.startingXI then
        for i, pid in ipairs(sellerTeam.startingXI) do
            if pid == player.id then
                table.remove(sellerTeam.startingXI, i)
                break
            end
        end
    end

    -- 处理付款（支持分期）
    local installments = bid.installments
    if installments and #installments > 0 then
        -- 分期付款：首付立即到账，余下记录为应收款
        local firstPay = installments[1].amount
        sellerTeam.balance = sellerTeam.balance + firstPay
        buyerTeam.balance = buyerTeam.balance - firstPay
        -- 后续分期记入应收/应付
        if not sellerTeam._pendingReceivables then sellerTeam._pendingReceivables = {} end
        if not buyerTeam._pendingPayables then buyerTeam._pendingPayables = {} end
        for i = 2, #installments do
            local inst = installments[i]
            table.insert(sellerTeam._pendingReceivables, {
                amount = inst.amount, dueDate = inst.dueDate,
                fromTeamId = buyerTeam.id, playerId = player.id,
            })
            table.insert(buyerTeam._pendingPayables, {
                amount = inst.amount, dueDate = inst.dueDate,
                toTeamId = sellerTeam.id, playerId = player.id,
            })
        end
    else
        -- 一次性付款
        sellerTeam.balance = sellerTeam.balance + bid.amount
        buyerTeam.balance = buyerTeam.balance - bid.amount
    end

    -- 加入买方
    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false

    -- 记录
    table.insert(gameState.transfers.history, {
        playerId = player.id,
        playerName = player.displayName,
        fromTeamId = sellerTeam.id,
        toTeamId = buyerTeam.id,
        amount = bid.amount,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        isPushSale = true,
    })

    gameState:sendMessage({
        category = "transfer",
        title = "推销成功!",
        body = string.format("%s 已以 %.0fK 转会至 %s。",
            player.displayName, bid.amount / 1000, buyerTeam.name),
        priority = "high",
    })

    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %.0fK 的转会费从 %s 转会至 %s。",
            player.displayName, bid.amount / 1000, sellerTeam.name, buyerTeam.name),
        relatedTeams = {sellerTeam.id, buyerTeam.id},
    })

    EventBus.emit("transfer_completed", bid)
end

--- 检查球员位置是否匹配需求
function TransferManager._playerMatchesNeed(player, needGroup)
    local Constants = require("scripts/app/constants")
    local positions = Constants.POSITION_GROUPS[needGroup] or {}
    for _, pos in ipairs(positions) do
        if player.position == pos then return true end
    end
    return false
end

------------------------------------------------------
-- ★ 球员转会态度系统
------------------------------------------------------

--- 检查球员是否愿意去目标球队
--- @return boolean willing
--- @return string|nil reason
function TransferManager._checkPlayerWillingness(gameState, player, targetTeam)
    -- 1. 球队声望差距过大（球员不愿降级）
    local currentTeam = gameState.teams[player.teamId]
    if currentTeam and targetTeam.reputation < currentTeam.reputation * 0.6 then
        return false, "不愿降级到低声望球队"
    end

    -- 2. 球员士气高且是核心球员 → 不太想走
    if player.morale >= 80 and player.squadRole == "key" then
        if Random() < 0.6 then
            return false, "作为核心球员，不想离开"
        end
    end

    -- 3. 球队关系敌对（球员不去死敌）
    if currentTeam and TransferManager._isRivalry(gameState, currentTeam.id, targetTeam.id) then
        if Random() < 0.8 then
            return false, "不愿去死敌球队"
        end
    end

    -- 4. 士气极低时更愿意离开
    -- (不阻止转会，这里始终返回 true)

    return true, nil
end

--- 获取球员对转会的态度描述（用于UI展示）
--- @return string attitude "eager"|"open"|"reluctant"|"refusing"
--- @return string description
function TransferManager.getPlayerTransferAttitude(gameState, playerId, targetTeamId)
    local player = gameState.players[playerId]
    if not player then return "refusing", "球员不存在" end

    local targetTeam = targetTeamId and gameState.teams[targetTeamId]

    -- 基础意愿
    local willingness = 50  -- 中性

    -- 士气影响
    if player.morale < 30 then willingness = willingness + 30  -- 很想走
    elseif player.morale < 50 then willingness = willingness + 15
    elseif player.morale > 80 then willingness = willingness - 20
    end

    -- 角色影响
    if player.squadRole == "key" then willingness = willingness - 15
    elseif player.squadRole == "squad" or player.squadRole == "youth" then willingness = willingness + 10
    end

    -- 目标球队声望影响
    if targetTeam then
        local currentTeam = gameState.teams[player.teamId]
        if currentTeam then
            local repDiff = targetTeam.reputation - currentTeam.reputation
            if repDiff > 200 then willingness = willingness + 25
            elseif repDiff > 0 then willingness = willingness + 10
            elseif repDiff < -200 then willingness = willingness - 25
            elseif repDiff < 0 then willingness = willingness - 10
            end
        end
    end

    -- 挂牌出售的球员更愿意走
    if player.listedForSale then willingness = willingness + 20 end

    -- 转为态度分级
    if willingness >= 75 then return "eager", "迫切想离开"
    elseif willingness >= 50 then return "open", "愿意考虑转会"
    elseif willingness >= 30 then return "reluctant", "不太情愿离开"
    else return "refusing", "拒绝转会"
    end
end

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
    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end
    if not player.releaseClause then return nil, "该球员没有解约金条款" end
    if player.teamId == gameState.playerTeamId then return nil, "不能触发自己球员的解约金" end

    local team = gameState:getPlayerTeam()
    if not team then return nil, "无法获取球队" end

    local amount = player.releaseClause
    local budget = TransferManager._getTransferBudget(gameState, team)
    if amount > budget then
        return nil, string.format("解约金 %.0fK 超出转会预算 %.0fK", amount / 1000, budget / 1000)
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

    -- 但仍需球员同意个人条款（简化：直接完成）
    TransferManager._completeTransfer(gameState, bid)

    gameState:sendMessage({
        category = "transfer",
        title = "解约金触发!",
        body = string.format("你触发了 %s 的解约金条款（%.0fK），转会自动完成。",
            player.displayName, amount / 1000),
        priority = "high",
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
    local bid = TransferManager.makeBid(gameState, playerId, amount, wageOffer)
    if not bid then return nil, "创建报价失败" end

    -- 附加条款
    clauses = clauses or {}

    -- 分期付款
    if clauses.installments and clauses.installments >= 2 then
        local numInstall = math.min(clauses.installments, 4)
        local perInstall = math.floor(amount / numInstall)
        local installList = {}
        for i = 1, numInstall do
            table.insert(installList, {
                amount = (i == numInstall) and (amount - perInstall * (numInstall - 1)) or perInstall,
                dueDate = {
                    year = gameState.date.year + math.floor((i - 1) * 6 / 12),
                    month = ((gameState.date.month + (i - 1) * 6 - 1) % 12) + 1,
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
                    team.balance = team.balance - p.amount
                    -- 对方收款
                    local receiver = gameState.teams[p.toTeamId]
                    if receiver then
                        receiver.balance = receiver.balance + p.amount
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
                table.sort(bids, function(a, b)
                    local aVal = a._effectiveValue or a.amount
                    local bVal = b._effectiveValue or b.amount
                    return aVal > bVal
                end)
                -- 通知竞价失败者
                for i = 2, #bids do
                    if bids[i].buyerTeamId == gameState.playerTeamId then
                        bids[i].status = "rejected"
                        gameState:sendMessage({
                            category = "transfer",
                            title = "竞价失败",
                            body = string.format("有其他球队对 %s 出了更高价，你的报价被拒绝。",
                                player.displayName),
                            priority = "normal",
                        })
                    end
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
    local expectedYears = TransferManager._calcExpectedYears(player)

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
        maxRounds = RandomInt(2, 3),
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
        body = string.format("你向 %s 发起了预签约邀请（周薪 %.1fK，%d年）。合同到期后生效。",
            player.displayName, wageOffer / 1000, yearsOffer),
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
                -- 从原球队移除
                local oldTeam = gameState.teams[player.teamId]
                if oldTeam then
                    for i, pid in ipairs(oldTeam.playerIds) do
                        if pid == player.id then
                            table.remove(oldTeam.playerIds, i)
                            break
                        end
                    end
                end

                -- 加入新球队
                local newTeam = gameState.teams[nego.teamId]
                if newTeam then
                    table.insert(newTeam.playerIds, player.id)
                    player.teamId = nego.teamId
                    player.wage = nego.wageOffer
                    player.contractEnd = {year = gameState.date.year + nego.yearsOffer, month = 6}
                    player.squadRole = "first_team"

                    nego.status = "completed"

                    gameState:sendMessage({
                        category = "transfer",
                        title = "预签约生效!",
                        body = string.format("%s 合同到期，正式加入球队！（周薪 %.1fK，%d年）",
                            player.displayName, nego.wageOffer / 1000, nego.yearsOffer),
                        priority = "high",
                    })

                    gameState:addNews({
                        category = "transfer_news",
                        title = "预签约生效: " .. player.displayName,
                        body = string.format("%s 合同到期，以自由身正式加盟 %s。",
                            player.displayName, newTeam.name),
                        relatedTeams = {nego.teamId},
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
        return false, string.format("工资总额 %.0fK 将超出工资预算 %.0fK",
            newTotal / 1000, wageBudget / 1000)
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
        if player and player.nationality == leagueCountry then
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
    if player.nationality == team.country then return false end

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
    if not gameState._teamRelations then return false end
    local key = teamId1 < teamId2
        and (teamId1 .. "_" .. teamId2)
        or (teamId2 .. "_" .. teamId1)
    local rel = gameState._teamRelations[key]
    return rel and rel <= -50  -- -100 ~ +100，-50以下视为敌对
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
    local playerCountry = player.nationality
    local teamCountry = nil
    if player.teamId then
        local playerTeam = gameState.teams[player.teamId]
        if playerTeam then teamCountry = playerTeam.country end
    end

    for _, region in ipairs(network.regions) do
        if region == playerCountry or region == teamCountry then
            return true
        end
    end
    return false
end

------------------------------------------------------
-- 修改 processDailyBids 以支持推销报价
------------------------------------------------------

-- 增强原有的 processDailyBids，处理推销报价
local _originalProcessDailyBids = TransferManager.processDailyBids
function TransferManager.processDailyBids(gameState)
    TransferManager._ensureData(gameState)

    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "pending" then
            -- 推销报价走不同路径
            if bid.isPushSale then
                local refDate = bid.responseDate or bid.date
                local daysSince = TransferManager._daysBetween(refDate, gameState.date)
                if daysSince >= RandomInt(1, 3) then
                    TransferManager._processPushSaleResponse(gameState, bid)
                end
            else
                -- 原有逻辑: 普通报价
                local refDate = bid.responseDate or bid.date
                local daysSince = TransferManager._daysBetween(refDate, gameState.date)
                local waitDays = (bid.currentRound or 0) > 0 and 1 or RandomInt(1, 3)
                if daysSince >= waitDays then
                    -- 检查解约金
                    local player = gameState.players[bid.playerId]
                    if player and TransferManager._checkReleaseClause(player, bid.amount) then
                        TransferManager._acceptBid(gameState, bid)
                    else
                        TransferManager._processAIResponse(gameState, bid)
                    end
                end
            end
        elseif bid.status == "negotiating" then
            if not bid.isPushSale then
                local daysSinceResponse = TransferManager._daysBetween(bid.responseDate or bid.date, gameState.date)
                local maxRounds = bid.maxRounds or 4
                if daysSinceResponse >= 5 then
                    bid.mood = math.max(0, (bid.mood or 50) - 20)
                    if (bid.currentRound or 0) >= maxRounds then
                        TransferManager._rejectBid(gameState, bid, "谈判破裂，对方已失去耐心。")
                    else
                        TransferManager._rejectBid(gameState, bid, "你的回复太慢，对方决定不再等待。")
                    end
                end
            end
        end
    end

    -- 竞争性报价处理
    TransferManager.processCompetitiveBids(gameState)
end

return TransferManager
