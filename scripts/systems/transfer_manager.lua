-- systems/transfer_manager.lua
-- 转会管理系统 - 处理出价、谈判、完成转会

local EventBus = require("scripts/app/event_bus")

local TransferManager = {}
require("scripts/systems/transfers/transfer_completion")(TransferManager)

-- 金额格式化（M/K自适应）
local function fmtMoney(amount)
    if not amount then return "0" end
    local abs = math.abs(amount)
    if abs >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif abs >= 1000 then
        return string.format("%.0fK", amount / 1000)
    else
        return tostring(math.floor(amount))
    end
end

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

-- 转会窗口检查（6-8月夏窗，1月冬窗）
function TransferManager.isInTransferWindow(gameState)
    local month = gameState.date.month
    return (month >= 6 and month <= 8) or month == 1
end

--- 统一转会窗口校验（用于俱乐部间交易入口）
--- @return boolean ok
--- @return string|nil errorMsg
function TransferManager._checkTransferWindow(gameState)
    if not TransferManager.isInTransferWindow(gameState) then
        return false, "当前不在转会窗口期（夏窗6-8月/冬窗1月），无法进行俱乐部间交易"
    end
    return true, nil
end

--- 检查球员是否已被预签约锁定
--- @return boolean ok
--- @return string|nil errorMsg
function TransferManager._checkPreContractLock(gameState, playerId)
    local player = gameState.players[playerId]
    if player and player.preContractLockedBy then
        local lockerTeam = gameState.teams[player.preContractLockedBy]
        local lockerName = lockerTeam and lockerTeam.name or "其他球队"
        return false, string.format("%s 已与 %s 达成预签约协议，无法再对其报价",
            player.displayName, lockerName)
    end
    return true, nil
end

-- 冷却期常量（天数）
local REJECTION_COOLDOWN_DAYS = 7

--- 简化日期差计算（每月30天近似）
local function _daysBetweenDates(d1, d2)
    local days1 = d1.year * 365 + d1.month * 30 + (d1.day or 1)
    local days2 = d2.year * 365 + d2.month * 30 + (d2.day or 1)
    return days2 - days1
end

--- 检查对某球员的报价/谈判是否在冷却期内
--- @return boolean ok 是否可以发起
--- @return string|nil errorMsg 冷却期提示
function TransferManager._checkRejectionCooldown(gameState, playerId)
    local today = gameState.date

    -- 检查 bids 中的拒绝记录
    if gameState.transfers.bids then
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == playerId
                and bid.buyerTeamId == gameState.playerTeamId
                and bid.status == "rejected"
                and bid.rejectedDate then
                local daysSince = _daysBetweenDates(bid.rejectedDate, today)
                if daysSince >= 0 and daysSince < REJECTION_COOLDOWN_DAYS then
                    local remaining = REJECTION_COOLDOWN_DAYS - daysSince
                    return false, string.format("该球员的报价在 %d 天前被拒绝，需等待 %d 天后才能重新报价", daysSince, remaining)
                end
            end
        end
    end

    -- 检查自由球员谈判中的拒绝记录
    if gameState.transfers.freeAgentNegos then
        for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
            if nego.playerId == playerId
                and nego.teamId == gameState.playerTeamId
                and nego.status == "rejected"
                and nego.rejectedDate then
                local daysSince = _daysBetweenDates(nego.rejectedDate, today)
                if daysSince >= 0 and daysSince < REJECTION_COOLDOWN_DAYS then
                    local remaining = REJECTION_COOLDOWN_DAYS - daysSince
                    return false, string.format("该球员的谈判在 %d 天前被拒绝，需等待 %d 天后才能重新谈判", daysSince, remaining)
                end
            end
        end
    end

    return true, nil
end

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

    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end

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
        contractYears = TransferManager._calcExpectedYears(player), -- 根据球员年龄动态计算
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
                body = string.format("你对 %s 的加价报价 (%s) 已提交，等待回复。(第%d轮)",
                    player.displayName, fmtMoney(newAmount), bid.currentRound),
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
           (bid.status == "pending" or bid.status == "negotiating" or bid.status == "fee_agreed") then
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
        if bid.id == bidId and (bid.status == "pending" or bid.status == "negotiating" or bid.status == "fee_agreed") then
            bid.status = "cancelled"
            return true
        end
    end
    return false
end

-- AI回应出价（生成具体counter-offer）
function TransferManager._processAIResponse(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        return
    end

    local ratio = TransferManager._getBidEffectiveValue(bid, player) / math.max(player.value, 1)
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

    -- 年龄因子：年轻球员溢价更高，老将更容易谈
    -- 以26岁为中性基准，每偏离1岁影响0.02
    local age = player.getAge and player:getAge(gameState.date.year) or 26
    local ageFactor = (26 - age) * 0.02  -- <26: 正值(加价), >26: 负值(降价)
    ageFactor = math.max(-0.15, math.min(0.15, ageFactor))  -- 限制在[-0.15, +0.15]
    acceptThreshold = acceptThreshold + ageFactor

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
        -- 年龄影响还价：年轻球员开价更高，老将更务实
        baseMultiplier = baseMultiplier + ageFactor
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
                "%s 拒绝了你的 %s 报价。\n%s 要求至少 %s 才愿意放人。\n(第%d/%d轮谈判)",
                sellerName, fmtMoney(bid.amount),
                sellerName, fmtMoney(counter),
                (round + 1), maxRounds),
            priority = "high",
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

    -- 转会费已达成，进入个人条款协商阶段
    bid.status = "fee_agreed"
    bid.feeAgreedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
    bid.personalTermsAttempts = 0  -- 个人条款协商次数

    -- 首次自动尝试个人条款协商
    TransferManager._attemptPersonalTerms(gameState, bid)
end

--- 尝试个人条款协商（内部方法）
--- 成功则完成转会，失败则通知玩家可修改工资后重试
function TransferManager._attemptPersonalTerms(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then return end

    bid.personalTermsAttempts = (bid.personalTermsAttempts or 0) + 1

    local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
    if consent then
        -- 个人条款通过，完成转会
        bid.status = "accepted"
        TransferManager._completeTransfer(gameState, bid)
    else
        -- 个人条款被拒，但转会费协议仍有效
        -- 最多允许3次重新协商
        if bid.personalTermsAttempts >= 3 then
            TransferManager._rejectBid(gameState, bid,
                string.format("与 %s 的个人条款协商已失败3次，交易取消。", player.displayName))
        else
            bid.status = "fee_agreed"  -- 保持在fee_agreed状态
            gameState:sendMessage({
                category = "transfer",
                title = "个人条款被拒",
                body = string.format(
                    "%s 拒绝了当前的个人条款（%s）。转会费协议仍有效，你可以修改薪资报价后重新协商（剩余 %d 次机会）。",
                    player.displayName, reason or "条件不满意",
                    3 - bid.personalTermsAttempts),
                priority = "high",
                data = { bidId = bid.id, type = "personal_terms_rejected" },
            })
        end
    end
end

--- 玩家修改工资后重新协商个人条款（公开API）
function TransferManager.negotiatePersonalTerms(gameState, bidId, newWageOffer)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "fee_agreed" then
            if bid.buyerTeamId ~= gameState.playerTeamId then
                return nil, "只能协商自己的报价"
            end
            -- 更新工资报价
            bid.wageOffer = newWageOffer
            -- 重新尝试个人条款
            TransferManager._attemptPersonalTerms(gameState, bid)
            return bid, nil
        end
    end
    return nil, "未找到待协商个人条款的报价"
end

-- 拒绝报价
function TransferManager._rejectBid(gameState, bid, reason)
    bid.status = "rejected"
    bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
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
-- @param opts table|nil 可选参数 { suppressMessage = bool }
function TransferManager._completeTransfer(gameState, bid, opts)
    local player = gameState.players[bid.playerId]
    if not player then return end

    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not buyerTeam then return end

    -- 从卖方阵容移除
    TransferManager._removePlayerFromTeam(sellerTeam, player.id)

    -- 加入买方阵容
    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = bid.buyerTeamId
    player.listedForSale = false
    player.listedForLoan = false

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
            priority = "high",
        })
    end

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %s 的转会费从 %s 转会至 %s。",
            player.displayName, fmtMoney(bid.amount),
            sellerTeam and sellerTeam.name or "自由球员市场",
            buyerTeam.name),
        playerId = player.id,
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

    -- AI主动挂牌出售多余/老化球员（每周处理）
    TransferManager._aiListPlayersForSale(gameState)

    -- 每周每支AI球队有40%概率尝试引援（可多队同时活跃）
    local transfersThisWeek = 0
    local maxTransfersPerWeek = 6  -- 每周全联赛上限6笔完成交易，保持合理
    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto continue end
        if transfersThisWeek >= maxTransfersPerWeek then break end
        if Random() > 0.40 then goto continue end

        -- 评估需求：包括"补缺"和"升级"两种动机
        local need, upgradeMode = TransferManager._assessTeamNeed(gameState, team)
        if not need then goto continue end

        -- 寻找合适目标
        local target = TransferManager._findTransferTarget(gameState, team, need, upgradeMode)
        if not target then goto continue end

        -- AI 发起转会
        local success = TransferManager._executeAITransfer(gameState, team, target)
        if success then
            transfersThisWeek = transfersThisWeek + 1
        end

        ::continue::
    end

    -- 额外：处理挂牌球员（AI和玩家的），每个挂牌球员每周30%概率吸引买家
    for _, player in pairs(gameState.players) do
        if not player.listedForSale then goto skipPlayer end
        if player.retired then goto skipPlayer end
        if TransferManager.hasPendingIncomingBid(gameState, player.id) then goto skipPlayer end
        if transfersThisWeek >= maxTransfersPerWeek + 2 then break end
        if Random() > 0.30 then goto skipPlayer end

        local buyer = TransferManager._findBuyerForPlayer(gameState, player)
        if buyer then
            local success = TransferManager._executeAITransfer(gameState, buyer, player)
            if success then
                transfersThisWeek = transfersThisWeek + 1
            end
        end
        ::skipPlayer::
    end
end

--- AI主动挂牌多余球员（增加市场供给）
function TransferManager._aiListPlayersForSale(gameState)
    local Constants = require("scripts/app/constants")
    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto skipTeam end
        -- 阵容过大(>25人)时，主动挂牌多余球员
        if #team.playerIds > 25 then
            local surplus = #team.playerIds - 23
            local listed = 0
            -- 按OVR排序，挂牌最弱的
            local sorted = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p and not p.retired and not p.listedForSale then
                    table.insert(sorted, p)
                end
            end
            table.sort(sorted, function(a, b) return a.overall < b.overall end)
            for i = 1, math.min(surplus, #sorted) do
                sorted[i].listedForSale = true
                listed = listed + 1
            end
        end
        -- 30岁以上且OVR下滑的球员，20%概率挂牌
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and not p.retired and not p.listedForSale then
                local age = p:getAge(gameState.date.year)
                if age >= 31 and p.overall < 72 and Random() < 0.20 then
                    p.listedForSale = true
                end
            end
        end
        ::skipTeam::
    end
end

--- 评估球队需求（返回需要的位置和是否为升级模式）
--- @return string|nil position group needed
--- @return boolean upgradeMode (true = want to upgrade, not just fill)
function TransferManager._assessTeamNeed(gameState, team)
    local posCount = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    local posAvgOvr = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    local Constants = require("scripts/app/constants")

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            for group, positions in pairs(Constants.POSITION_GROUPS) do
                for _, pos in ipairs(positions) do
                    if player.position == pos then
                        posCount[group] = posCount[group] + 1
                        posAvgOvr[group] = posAvgOvr[group] + player.overall
                    end
                end
            end
        end
    end

    -- 计算各位置平均OVR
    for g, count in pairs(posCount) do
        if count > 0 then posAvgOvr[g] = posAvgOvr[g] / count end
    end

    -- 优先级1: 严重短缺（必须补人）
    if posCount.GK < 2 then return "GK", false end
    if posCount.DEF < 4 then return "DEF", false end
    if posCount.MID < 4 then return "MID", false end
    if posCount.FWD < 2 then return "FWD", false end

    -- 优先级2: 阵容太小
    if #team.playerIds < 20 then
        local groups = {"DEF", "MID", "FWD"}
        return groups[RandomInt(1, 3)], false
    end

    -- 优先级3: 升级动机（50%概率触发——想买比现有更好的球员）
    if Random() < 0.50 then
        -- 找最弱的位置组进行升级
        local weakest, weakestOvr = nil, 999
        local groups = {"DEF", "MID", "FWD"}
        for _, g in ipairs(groups) do
            if posAvgOvr[g] > 0 and posAvgOvr[g] < weakestOvr then
                weakestOvr = posAvgOvr[g]
                weakest = g
            end
        end
        if weakest then
            return weakest, true  -- upgrade mode
        end
    end

    return nil, false
end

--- 寻找转会目标
function TransferManager._findTransferTarget(gameState, buyerTeam, needGroup, upgradeMode)
    local Constants = require("scripts/app/constants")
    local targetPositions = Constants.POSITION_GROUPS[needGroup] or {}
    local candidates = {}
    local budget = buyerTeam.transferBudget or (buyerTeam.balance * 0.5)
    local teamAvg = TransferManager._getTeamAverageOverall(gameState, buyerTeam)

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

        -- 财力检查（不超过转会预算的60%，且不超过余额的50%）
        local maxSpend = math.min(budget * 0.6, buyerTeam.balance * 0.5)
        if player.value > maxSpend then goto continue end

        -- 能力匹配
        if upgradeMode then
            -- 升级模式：只买比队内平均更好的
            if player.overall < teamAvg then goto continue end
            if player.overall > teamAvg + 15 then goto continue end
        else
            -- 补缺模式：范围宽松一些
            if player.overall < teamAvg - 12 then goto continue end
            if player.overall > teamAvg + 15 then goto continue end
        end

        -- 优先考虑挂牌出售的球员（更容易成交）
        local weight = 1
        if player.listedForSale then weight = 3 end
        for w = 1, weight do
            table.insert(candidates, player)
        end
        ::continue::
    end

    if #candidates == 0 then return nil end

    -- 从候选中随机选一个（挂牌球员权重更高）
    return candidates[RandomInt(1, #candidates)]
end

--- 执行 AI 转会（返回 true 表示成交）
function TransferManager._executeAITransfer(gameState, buyerTeam, player)
    -- 预签约锁定检查：已被预签约的球员不可再交易
    if player.preContractLockedBy then return false end

    local sellerTeam = gameState.teams[player.teamId]

    -- AI 报价 = 身价 × (0.9~1.3)，挂牌球员报价稍低
    local multiplier = player.listedForSale and (0.85 + Random() * 0.25) or (1.0 + Random() * 0.3)
    local offerAmount = math.floor(player.value * multiplier)

    -- 如果目标是玩家球队球员（挂牌出售的），生成收购报价让玩家决定
    if player.teamId == gameState.playerTeamId then
        TransferManager._createIncomingBid(gameState, buyerTeam, player, offerAmount)
        return true  -- 报价已创建，算作活动
    end

    -- 卖方判断是否接受
    local ratio = offerAmount / player.value
    local acceptChance = 0
    if ratio >= 1.3 then acceptChance = 0.95
    elseif ratio >= 1.1 then acceptChance = 0.80
    elseif ratio >= 1.0 then acceptChance = 0.60
    elseif ratio >= 0.85 then acceptChance = 0.35
    else acceptChance = 0.15 end

    -- 挂牌出售的球员：大幅提升接受率
    if player.listedForSale then
        acceptChance = math.min(0.95, acceptChance + 0.35)
    end

    -- 核心球员（非挂牌）不轻易卖，但不要砍太狠
    if player.overall >= 80 and not player.listedForSale then
        acceptChance = acceptChance * 0.6
    elseif player.overall >= 75 and not player.listedForSale then
        acceptChance = acceptChance * 0.75
    end

    -- 阵容臃肿的卖方更愿意卖
    if sellerTeam and #sellerTeam.playerIds > 25 then
        acceptChance = math.min(0.95, acceptChance + 0.20)
    end

    if Random() > acceptChance then return false end  -- 卖方拒绝

    -- AI 工资预算检查：新球员薪水不能超出买方工资预算
    local newWage = math.floor(player.wage * (1.1 + Random() * 0.2))  -- AI 涨薪 10-30%
    local canAfford, _ = TransferManager.checkWageBudget(gameState, buyerTeam.id, newWage)
    if not canAfford then return false end  -- 工资超预算，放弃

    -- 完成转会
    if sellerTeam then
        for i, pid in ipairs(sellerTeam.playerIds) do
            if pid == player.id then
                table.remove(sellerTeam.playerIds, i)
                break
            end
        end
        sellerTeam.balance = sellerTeam.balance + offerAmount
        sellerTeam.transferBudget = (sellerTeam.transferBudget or 0) + offerAmount
        sellerTeam.seasonIncome = (sellerTeam.seasonIncome or 0) + offerAmount
    end

    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false
    player.listedForLoan = false
    player.wage = newWage  -- 更新球员工资（AI涨薪后）
    player.contractEnd = {year = gameState.date.year + TransferManager._calcExpectedYears(player), month = 6}
    buyerTeam.balance = buyerTeam.balance - offerAmount
    buyerTeam.seasonExpense = (buyerTeam.seasonExpense or 0) + offerAmount

    -- 扣除转会预算
    if buyerTeam.transferBudget then
        buyerTeam.transferBudget = math.max(0, buyerTeam.transferBudget - offerAmount)
    end

    -- 更新名气和身价
    player:calculateReputation(buyerTeam.reputation or 300)
    player:calculateValue(gameState.date.year)

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
        body = string.format("%s 以 %s 的转会费从 %s 转会至 %s。",
            player.displayName, fmtMoney(offerAmount),
            sellerTeam and sellerTeam.name or "自由球员市场",
            buyerTeam.name),
        playerId = player.id,
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

    return true  -- 交易成功
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
        if team.id == player.teamId then goto skip end
        -- 财力检查（用转会预算的70%作为上限，挂牌球员更有吸引力）
        local budget = team.transferBudget or (team.balance * 0.5)
        if player.value > budget * 0.7 then goto skip end
        -- 能力匹配（挂牌球员范围宽松）
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
        if player.overall < teamAvg - 12 or player.overall > teamAvg + 15 then goto skip end
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
        body = string.format("%s 对 %s 出价 %s（球员身价 %s）。\n前往阵容页长按该球员处理报价。",
            buyerTeam.name, player.displayName, fmtMoney(offerAmount), fmtMoney(player.value)),
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
            local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
            if not consent then
                bid.status = "rejected"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "球员拒绝转会",
                    body = reason,
                    priority = "normal",
                })
                return false
            end
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
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "报价已拒绝",
                body = string.format("你拒绝了 %s 对 %s 的报价（%s）。",
                    buyerTeam and buyerTeam.name or "未知球队",
                    player and player.displayName or "未知球员",
                    fmtMoney(bid.amount)),
                priority = "normal",
            })
            return true
        end
    end
    return false
end

--- 还价（玩家要求更高价格）
function TransferManager.counterIncomingBid(gameState, bidId, askAmount)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" and bid.isIncomingBid then
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            if not buyerTeam or not player then return false end

            -- AI 决定是否接受还价：基于出价与要价的差距
            local ratio = askAmount / (player.value or 1)
            -- 如果要价不超过身价120%，AI有较高概率接受
            local acceptChance = 0
            if ratio <= 1.0 then acceptChance = 0.9
            elseif ratio <= 1.1 then acceptChance = 0.7
            elseif ratio <= 1.2 then acceptChance = 0.5
            elseif ratio <= 1.3 then acceptChance = 0.3
            else acceptChance = 0.1 end

            if math.random() < acceptChance then
                -- AI 接受还价
                bid.amount = askAmount
                bid.status = "completed"
                bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                TransferManager._completeIncomingSale(gameState, bid)
                gameState:sendMessage({
                    category = "transfer",
                    title = "还价被接受",
                    body = string.format("%s 接受了你的要价 %s，%s 转会完成。",
                        buyerTeam.name, fmtMoney(askAmount), player.displayName),
                    priority = "high",
                })
                return true, "accepted"
            else
                -- AI 拒绝还价，撤回报价
                bid.status = "rejected"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "还价被拒绝",
                    body = string.format("%s 认为你的要价 %s 过高，已撤回对 %s 的报价。",
                        buyerTeam.name, fmtMoney(askAmount), player.displayName),
                    priority = "normal",
                })
                return true, "rejected"
            end
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
    TransferManager._removePlayerFromTeam(sellerTeam, player.id)

    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false
    TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)
    TransferManager._attachFutureClauses(player, bid)

    -- 更新球员合同（买方给出的个人条款）
    if bid.wageOffer and bid.wageOffer > 0 then
        player.wage = bid.wageOffer
    end
    player.contractEnd = { year = gameState.date.year + 3, month = 6 }

    -- 更新名气和身价
    player:calculateReputation(buyerTeam.reputation or 300)
    player:calculateValue(gameState.date.year)

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
        body = string.format("%s 以 %s 转会至 %s，资金已到账。",
            player.displayName, fmtMoney(bid.amount), buyerTeam.name),
        priority = "high",
    })

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %s 的转会费从 %s 转会至 %s。",
            player.displayName, fmtMoney(bid.amount), sellerTeam.name, buyerTeam.name),
        playerId = player.id,
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

    -- 转会窗口检查
    local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
    if not windowOk then return nil, windowErr end

    -- 拒绝冷却期检查
    local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
    if not cooldownOk then return nil, cooldownErr end

    -- 预签约锁定检查
    local lockOk, lockErr = TransferManager._checkPreContractLock(gameState, playerId)
    if not lockOk then return nil, lockErr end

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
        body = string.format("你对 %s 的租借请求已提交（%d周，租借费 %s）。",
            player.displayName, duration, fmtMoney(loanFee)),
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
    buyerTeam.seasonExpense = (buyerTeam.seasonExpense or 0) + bid.amount
    if sellerTeam then
        sellerTeam.balance = sellerTeam.balance + bid.amount
        sellerTeam.transferBudget = (sellerTeam.transferBudget or 0) + bid.amount
        sellerTeam.seasonIncome = (sellerTeam.seasonIncome or 0) + bid.amount
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

    -- 更新名气和身价
    if originTeam then
        player:calculateReputation(originTeam.reputation or 300)
    end
    player:calculateValue(gameState.date.year)

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

    -- 拒绝冷却期检查
    local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
    if not cooldownOk then return nil, cooldownErr end

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

    nego.status = "accepted"

    -- 预签约：不立即转移球员，等合同到期后由 processPreContracts 执行
    if nego.isPreContract then
        player.preContractLockedBy = nego.teamId  -- 锁定标记
        gameState:sendMessage({
            category = "transfer",
            title = "预签约达成!",
            body = string.format("%s 同意预签约（周薪 %s，%d年）。合同到期后正式加入。",
                player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
            priority = "high",
        })
        gameState:addNews({
            category = "transfer_news",
            title = "预签约: " .. player.displayName,
            body = string.format("%s 与 %s 达成预签约协议，将在合同到期后正式加盟。",
                player.displayName, team.name),
            playerId = player.id,
            relatedTeams = {nego.teamId, player.teamId},
        })
        return
    end

    -- 自由球员：立即执行签约
    table.insert(team.playerIds, player.id)
    player.teamId = team.id
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
        priority = "high",
    })

    -- 新闻
    gameState:addNews({
        category = "transfer_news",
        title = "自由签约: " .. player.displayName,
        body = string.format("%s 以自由身加盟 %s，签约 %d 年。",
            player.displayName, team.name, nego.yearsOffer),
        playerId = player.id,
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
        body = string.format("%s 已作为自由球员加盟球队（周薪 %s，合同 %d年）。",
            player.displayName, fmtMoney(wage), years),
        priority = "high",
    })

    gameState:addNews({
        category = "transfer_news",
        title = "自由签约: " .. player.displayName,
        body = string.format("%s 以自由身加盟 %s，签约 %d 年。",
            player.displayName, team.name, years),
        playerId = player.id,
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

    -- 转会窗口检查
    local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
    if not windowOk then return nil, windowErr end

    -- 拒绝冷却期检查（推销被拒后也需要冷却）
    local cooldownOk, cooldownErr = TransferManager._checkRejectionCooldown(gameState, playerId)
    if not cooldownOk then return nil, cooldownErr end

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
        body = string.format("你向 %s 推销了 %s（要价 %s）。等待对方回复...",
            targetTeam.name, player.displayName, fmtMoney(askingPrice)),
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
                body = string.format("%s 对 %s 有兴趣，但只愿意出 %s（你要价 %s）。",
                    buyerTeam.name, player.displayName, fmtMoney(counter), fmtMoney(bid.amount)),
                priority = "high",
            })
        end
    else
        -- 没兴趣
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
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
    local player = gameState.players[bid.playerId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not player or not sellerTeam or not buyerTeam then return end

    local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
    if not consent then
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        gameState:sendMessage({
            category = "transfer",
            title = "推销失败",
            body = reason,
            priority = "normal",
        })
        return
    end

    bid.status = "completed"

    -- 从卖方移除
    TransferManager._removePlayerFromTeam(sellerTeam, player.id)
    TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)

    -- 加入买方
    table.insert(buyerTeam.playerIds, player.id)
    player.teamId = buyerTeam.id
    player.listedForSale = false
    TransferManager._attachFutureClauses(player, bid)

    -- 更新球员合同（买方给出的个人条款）
    if bid.wageOffer and bid.wageOffer > 0 then
        player.wage = bid.wageOffer
    end
    player.contractEnd = { year = gameState.date.year + 3, month = 6 }

    -- 更新名气和身价
    player:calculateReputation(buyerTeam.reputation or 300)
    player:calculateValue(gameState.date.year)

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
        body = string.format("%s 已以 %s 转会至 %s。",
            player.displayName, fmtMoney(bid.amount), buyerTeam.name),
        priority = "high",
    })

    gameState:addNews({
        category = "transfer_news",
        title = "官宣: " .. player.displayName .. " 转会",
        body = string.format("%s 以 %s 的转会费从 %s 转会至 %s。",
            player.displayName, fmtMoney(bid.amount), sellerTeam.name, buyerTeam.name),
        playerId = player.id,
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
                    })
                    -- 对方收款
                    local receiver = gameState.teams[p.toTeamId]
                    if receiver then
                        receiver.balance = receiver.balance + p.amount
                        receiver.transferBudget = (receiver.transferBudget or 0) + p.amount
                        receiver.seasonIncome = (receiver.seasonIncome or 0) + p.amount
                        TransferManager._addTransferTransaction(receiver, p.amount, "转会分期收款", {
                            year = gameState.date.year,
                            month = gameState.date.month,
                            day = gameState.date.day,
                        })
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
                    player.preContractLockedBy = nil  -- 清除预签约锁定

                    nego.status = "completed"

                    gameState:sendMessage({
                        category = "transfer",
                        title = "预签约生效!",
                        body = string.format("%s 合同到期，正式加入球队！（周薪 %s，%d年）",
                            player.displayName, fmtMoney(nego.wageOffer), nego.yearsOffer),
                        priority = "high",
                    })

                    gameState:addNews({
                        category = "transfer_news",
                        title = "预签约生效: " .. player.displayName,
                        body = string.format("%s 合同到期，以自由身正式加盟 %s。",
                            player.displayName, newTeam.name),
                        playerId = player.id,
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

------------------------------------------------------
-- AI 报价处理（每天调用）
------------------------------------------------------
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
                    elseif bid.type == "loan" then
                        TransferManager._processLoanBidResponse(gameState, bid)
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

    -- fee_agreed 状态超时处理（7天未操作则取消）
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "fee_agreed" and bid.feeAgreedDate then
            local daysSinceFeeAgreed = TransferManager._daysBetween(bid.feeAgreedDate, gameState.date)
            if daysSinceFeeAgreed >= 7 then
                local player = gameState.players[bid.playerId]
                TransferManager._rejectBid(gameState, bid,
                    string.format("与 %s 的个人条款协商超时（7天未回应），转会费协议作废。",
                        player and player.displayName or "该球员"))
            end
        end
    end

    -- 竞争性报价处理
    TransferManager.processCompetitiveBids(gameState)
end

function TransferManager._processLoanBidResponse(gameState, bid)
    local player = gameState.players[bid.playerId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    if not player or not sellerTeam then
        bid.status = "rejected"
        return
    end

    local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
    if not consent then
        TransferManager._rejectBid(gameState, bid, reason)
        return
    end

    local acceptChance = 0.35
    if player.listedForLoan then acceptChance = acceptChance + 0.35 end
    if player.squadRole == "youth" or player.squadRole == "squad" then acceptChance = acceptChance + 0.15 end
    if bid.amount >= (player.wage or 0) * (bid.loanDuration or 26) * 0.45 then acceptChance = acceptChance + 0.1 end
    if player.squadRole == "key" then acceptChance = acceptChance - 0.25 end

    if Random() < math.max(0.1, math.min(0.9, acceptChance)) then
        TransferManager._completeLoan(gameState, bid)
    else
        TransferManager._rejectBid(gameState, bid, string.format("%s 拒绝了租借 %s 的请求。",
            sellerTeam.name, player.displayName))
    end
end

--- 获取所有活跃报价（状态为 pending 或 negotiating）
---@param gameState table
---@return table[]
function TransferManager.getActiveBids(gameState)
    TransferManager._ensureData(gameState)
    local activeBids = {}
    for _, bid in ipairs(gameState.transfers.bids or {}) do
        if bid.status == "pending" or bid.status == "negotiating" then
            table.insert(activeBids, bid)
        end
    end
    return activeBids
end

--- 挂牌出售球员
---@param gameState table
---@param player table
function TransferManager.listForSale(gameState, player)
    player.listedForSale = true
    gameState:sendMessage({
        category = "transfer",
        title = player.displayName .. " 已挂牌",
        body = player.displayName .. " 已被挂牌出售，等待买家报价。",
        priority = "normal",
    })
end

--- 取消挂牌
---@param player table
function TransferManager.delistPlayer(player)
    player.listedForSale = false
end

return TransferManager
