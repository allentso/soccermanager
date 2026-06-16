-- systems/transfer_manager.lua
-- 转会管理系统 - 处理出价、谈判、完成转会

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")

local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")

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
    if not gameState.scoutDiscoveries then
        gameState.scoutDiscoveries = {}
    end
end

-- 转会窗口检查（6-8月夏窗，1月冬窗）
function TransferManager.isInTransferWindow(gameState)
    local month = gameState.date.month
    return (month >= 6 and month <= 8) or month == 1
end

--- 当前转会窗标识（夏窗/冬窗各算一个窗期）
---@return string|nil
function TransferManager.getTransferWindowKey(gameState)
    if not gameState or not gameState.date then return nil end
    local month = gameState.date.month
    local year = gameState.date.year
    if month >= 6 and month <= 8 then
        return "summer_" .. tostring(year)
    elseif month == 1 then
        return "winter_" .. tostring(year)
    end
    return nil
end

--- 球员在本窗期是否已完成过转会/租借/签约
---@return boolean blocked
---@return string|nil errorMsg
function TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
    local player = gameState.players[playerId]
    if not player then return true, nil end
    local key = TransferManager.getTransferWindowKey(gameState)
    if not key then return true, nil end
    if player._transferWindowKey == key then
        return false, "该球员在本转会窗已参与过转会/租借/签约，需等到下一窗口"
    end
    return true, nil
end

--- 是否为「本窗已转会」类错误（供 UI 统一弹窗）
function TransferManager.isWindowMoveLimitError(errMsg)
    return type(errMsg) == "string" and errMsg:find("本转会窗已参与过", 1, true) ~= nil
end

function TransferManager._markPlayerWindowMove(gameState, playerId)
    local player = gameState.players[playerId]
    local key = TransferManager.getTransferWindowKey(gameState)
    if player and key then
        player._transferWindowKey = key
    end
end

--- 球员是否已在当前转会窗完成过转会/租借/签约
function TransferManager.hasMovedInCurrentWindow(gameState, playerId)
    local player = gameState.players[playerId]
    if not player then return false end
    local key = TransferManager.getTransferWindowKey(gameState)
    if not key then return false end
    return player._transferWindowKey == key
end

--- 获取转会窗口关闭日期
--- @return table|nil {year, month, day} 当前窗口关闭日期，不在窗口期返回nil
function TransferManager.getWindowCloseDate(gameState)
    local month = gameState.date.month
    local year = gameState.date.year
    if month >= 6 and month <= 8 then
        return { year = year, month = 8, day = 31 }  -- 夏窗8月31日关闭
    elseif month == 1 then
        return { year = year, month = 1, day = 31 }  -- 冬窗1月31日关闭
    end
    return nil
end

--- 计算距离转会窗口关闭的天数
--- @return number 剩余天数（不在窗口返回999）
function TransferManager.daysUntilWindowClose(gameState)
    local closeDate = TransferManager.getWindowCloseDate(gameState)
    if not closeDate then return 999 end
    return TransferManager._daysBetween(gameState.date, closeDate)
end

--- 是否处于 Deadline Day（关窗前<=2天）
function TransferManager.isDeadlineDay(gameState)
    return TransferManager.daysUntilWindowClose(gameState) <= 2
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

    local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
    if not moveOk then return nil, moveErr end

    local player = gameState.players[playerId]
    if not player then return nil, "球员不存在" end
    if not player.teamId then return nil, "自由球员请使用自由签约" end
    if player.teamId == gameState.playerTeamId then return nil, "该球员已在你的球队" end

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
                    player.displayName, feeLabel, fmtMoney(newAmount), bid.currentRound),
                priority = "normal",
            })
            return true
        end
    end
    return false
end

-- 获取指定 bid
local function _bidIdsEqual(a, b)
    if a == nil or b == nil then return false end
    return a == b or tonumber(a) == tonumber(b)
end

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
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.buyerTeamId == gameState.playerTeamId then
            table.insert(result, bid)
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
            and bid.status == "awaiting_confirmation" then
            local player = gameState.players[bid.playerId]
            local seller = bid.sellerTeamId and gameState.teams[bid.sellerTeamId]
            table.insert(result, {
                bidId = bid.id,
                playerId = bid.playerId,
                playerName = player and player.displayName or "球员",
                sellerName = seller and (seller.name or seller.shortName) or "卖方",
                amount = bid.amount,
            })
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
        if nego.teamId == teamId and nego.status == "awaiting_confirmation" then
            local player = gameState.players[nego.playerId]
            table.insert(result, {
                negoId = nego.id,
                playerId = nego.playerId,
                playerName = player and player.displayName or "球员",
                wageOffer = nego.wageOffer,
                yearsOffer = nego.yearsOffer,
            })
        end
    end
    return result
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

    -- 超过最大轮次 → 直接拒绝
    if round >= maxRounds then
        TransferManager._rejectBid(gameState, bid, "谈判回合耗尽，对方决定不出售。")
        return
    end

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
        bid.playerConsiderDays = RandomInt(1, 3)
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

    local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
    if not sellerOk then
        TransferManager._rejectBid(gameState, bid, sellerErr)
        return
    end

    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not buyerTeam then return end

    -- 加入买方阵容（同时清除其他球队残留引用，避免射手榜重复统计）
    TransferManager._assignPlayerToTeam(gameState, player, bid.buyerTeamId)
    player.listedForSale = false
    player.listedForLoan = false
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
            -- 激活球探网络地区过滤
            if TransferManager._isPlayerInScoutNetwork(gameState, p) then
                table.insert(allPlayers, p)
            end
        end
    end
    if #allPlayers == 0 then return end

    -- 使用独立的 scoutDiscoveries 表，避免覆盖手动球探报告
    gameState.scoutDiscoveries = gameState.scoutDiscoveries or {}

    local actualDiscovered = 0
    for _ = 1, discoverCount do
        local idx = RandomInt(1, #allPlayers)
        local player = allPlayers[idx]

        -- 检查是否已有该球员的发现记录
        local already = false
        for _, r in ipairs(gameState.scoutDiscoveries) do
            if r.playerId == player.id then
                already = true
                break
            end
        end
        -- 也检查手动报告中是否已有
        for _, r in ipairs(gameState.scoutReports or {}) do
            if r.playerId == player.id then
                already = true
                break
            end
        end

        if not already then
            -- 球探评估潜力（有一定误差，基于局内实际潜力）
            local avgAbility = math.floor(scoutAbility / scoutCount)
            local error_range = math.max(1, 15 - avgAbility)
            local scoutedPotential = (player.actualPotential or player.potential) + RandomInt(-error_range, error_range)
            scoutedPotential = math.max(30, math.min(99, scoutedPotential))

            table.insert(gameState.scoutDiscoveries, 1, {
                playerId = player.id,
                scoutedPotential = scoutedPotential,
                discoveredDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            })
            actualDiscovered = actualDiscovered + 1

            -- 保留最近20条自动发现
            while #gameState.scoutDiscoveries > 20 do
                table.remove(gameState.scoutDiscoveries)
            end
        end
    end

    -- 通知
    if actualDiscovered > 0 then
        gameState:sendMessage({
            category = "scout",
            title = "球探报告",
            body = string.format("球探发现了 %d 名潜在引援目标，请在转会市场-球探页面查看。", actualDiscovered),
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

    -- AI主动挂牌多余球员（增加市场供给）
    TransferManager._aiListPlayersForSale(gameState)
    -- AI 挂牌符合画像的年轻/缺勤球员外租（仅转会窗）
    TransferManager._aiListPlayersForLoan(gameState)

    -- 每周每支AI球队按难度档位尝试引援；资金充裕者每周必试
    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto continue end
        if not TransferManager._shouldAITryTransfer(gameState, team) then goto continue end

        -- 评估需求：包括"补缺"和"升级"两种动机
        local need, upgradeMode = TransferManager._assessTeamNeed(gameState, team)
        if not need then goto continue end

        -- 寻找合适目标
        local target = TransferManager._findTransferTarget(gameState, team, need, upgradeMode)
        if not target then goto continue end

        -- AI 发起转会
        TransferManager._executeAITransfer(gameState, team, target)

        ::continue::
    end

    -- 额外：处理挂牌球员（AI和玩家的）
    -- 玩家挂牌球员每周60%概率吸引买家，AI挂牌球员30%
    -- 允许同一球员接收最多3份来自不同买家的竞争报价
    local MAX_COMPETING_BIDS = 3
    for _, player in pairs(gameState.players) do
        if not player.listedForSale then goto skipPlayer end
        if player.retired then goto skipPlayer end
        -- 已有待确认出售的bid时，不再接受新的竞争报价（避免多个阻断并存）
        if TransferManager._hasAwaitingSaleConfirmation(gameState, player.id) then goto skipPlayer end
        -- 检查已有的竞争报价数量（允许多家出价，上限 MAX_COMPETING_BIDS）
        local existingBids = TransferManager.getIncomingBidsForPlayer(gameState, player.id)
        if #existingBids >= MAX_COMPETING_BIDS then goto skipPlayer end
        -- 玩家球员更高概率吸引买家（模拟经纪人主动推销）
        local isPlayerTeamPlayer = (player.teamId == gameState.playerTeamId)
        local attractChance = isPlayerTeamPlayer and 0.80 or 0.30
        if Random() > attractChance then goto skipPlayer end

        local buyer = TransferManager._findBuyerForPlayer(gameState, player)
        if buyer then
            -- 确保该买家没有对此球员的重复出价
            if not TransferManager.hasPendingIncomingBid(gameState, player.id, buyer.id) then
                TransferManager._executeAITransfer(gameState, buyer, player)
            end
        end
        ::skipPlayer::
    end

    -- 额外：处理外租挂牌球员（AI主动租借玩家挂牌外租的球员）
    local MAX_INCOMING_LOAN_BIDS = 2
    for _, player in pairs(gameState.players) do
        if not player.listedForLoan then goto skipLoanPlayer end
        if player.retired then goto skipLoanPlayer end
        if player.teamId ~= gameState.playerTeamId then goto skipLoanPlayer end  -- 只处理玩家球队的外租挂牌
        -- 检查已有的租借报价数量
        local existingLoanBids = TransferManager.getIncomingLoanBidsForPlayer(gameState, player.id)
        if #existingLoanBids >= MAX_INCOMING_LOAN_BIDS then goto skipLoanPlayer end
        -- 70%概率每周吸引租借买家
        if Random() > 0.70 then goto skipLoanPlayer end

        local loanBuyer = TransferManager._findLoanBuyerForPlayer(gameState, player)
        if loanBuyer then
            if not TransferManager.hasPendingIncomingLoanBid(gameState, player.id, loanBuyer.id) then
                TransferManager._createIncomingLoanBid(gameState, loanBuyer, player)
            end
        end
        ::skipLoanPlayer::
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
                if p and not p.retired and not p.listedForSale and p.squadRole ~= "loaned" then
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
            if p and not p.retired and not p.listedForSale and p.squadRole ~= "loaned" then
                local age = p:getAge(gameState.date.year)
                if age >= 31 and p.overall < 72 and Random() < 0.20 then
                    p.listedForSale = true
                end
            end
        end
        ::skipTeam::
    end
end

-- 各角色赛季预期出场（用于判断「缺乏出场」）
local LOAN_ROLE_SEASON_APPS = {
    key = 32, rotation = 18, squad = 8, youth = 6,
}

local AI_LOAN_LIST_MIN_SCORE = 32
local AI_LOAN_LIST_MAX_AGE = 26
local AI_LOAN_LIST_MAX_PER_TEAM = 1
local AI_LOAN_LIST_MAX_GLOBAL = 5

function TransferManager._getSeasonProgress(gameState)
    local Constants = require("scripts/app/constants")
    local startMonth = Constants.SEASON_START_MONTH or 8
    local monthsElapsed = gameState.date.month - startMonth
    if monthsElapsed < 0 then monthsElapsed = monthsElapsed + 12 end
    return math.max(0, math.min(1, monthsElapsed / 10))
end

function TransferManager._isPlayerInStartingXI(team, playerId)
    for _, pid in ipairs(team.startingXI or {}) do
        if pid == playerId then return true end
    end
    return false
end

--- 评估 AI 外租挂牌候选（返回分数；不符合画像返回 nil）
function TransferManager._scoreLoanListingCandidate(gameState, player, team)
    if not player or not team then return nil end
    if player.retired or player.injured then return nil end
    if player.listedForLoan or player.listedForSale or player.squadRole == "loaned" then return nil end
    if player.squadRole == "key" then return nil end

    local age = player:getAge(gameState.date.year)
    if age > AI_LOAN_LIST_MAX_AGE then return nil end

    local ovr = player.overall or 50
    if ovr >= 76 then return nil end

    local pot = player.actualPotential or player.potential or ovr
    local potGap = pot - ovr
    local role = player.squadRole or "squad"
    local inXI = TransferManager._isPlayerInStartingXI(team, player.id)
    local apps = (player.seasonStats and player.seasonStats.appearances) or 0
    local progress = TransferManager._getSeasonProgress(gameState)
    local expectedByNow = math.floor((LOAN_ROLE_SEASON_APPS[role] or 8) * progress + 0.5)

    local isYoung = age <= 23
    local isProspect = potGap >= 5 or (isYoung and potGap >= 3)
    local isYouthRole = role == "youth" and age <= 21
    local lacksTime = false
    if not inXI then
        if progress >= 0.15 and apps < math.max(1, math.floor(expectedByNow * 0.35)) then
            lacksTime = true
        elseif (role == "squad" or role == "youth" or role == "rotation")
            and apps < math.max(2, math.floor(expectedByNow * 0.5)) then
            lacksTime = true
        end
    end

    -- 必须满足：年轻有潜力 / 青训定位 / 明显缺勤 之一
    if not isProspect and not isYouthRole and not lacksTime then return nil end
    -- 24+ 且无出场问题、潜力不足 → 不挂牌
    if age >= 24 and not lacksTime and potGap < 4 then return nil end

    local score = 0
    if isYoung then score = score + 12 end
    if age <= 21 then score = score + 8 end
    if isYouthRole then score = score + 22 end
    if potGap >= 10 then score = score + 18
    elseif potGap >= 6 then score = score + 12
    elseif potGap >= 3 then score = score + 6 end
    if lacksTime then score = score + 20 end
    if not inXI then score = score + 10 end
    if apps == 0 and progress >= 0.1 then score = score + 8 end
    if role == "squad" or role == "rotation" then score = score + 5 end
    -- 能力越低越愿意外租锻炼
    if ovr < 62 then score = score + 6
    elseif ovr < 68 then score = score + 3 end

    if score < AI_LOAN_LIST_MIN_SCORE then return nil end
    return score
end

--- AI 在转会窗内挂牌外租候选（按画像评分，非随机）
function TransferManager._aiListPlayersForLoan(gameState)
    if not TransferManager.isInTransferWindow(gameState) then return end

    local globalListed = 0
    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto skipTeam end
        if globalListed >= AI_LOAN_LIST_MAX_GLOBAL then break end

        local candidates = {}
        for _, pid in ipairs(team.playerIds or {}) do
            local p = gameState.players[pid]
            local score = p and TransferManager._scoreLoanListingCandidate(gameState, p, team)
            if score then
                table.insert(candidates, { player = p, score = score })
            end
        end

        if #candidates == 0 then goto skipTeam end

        table.sort(candidates, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return (a.player.overall or 0) < (b.player.overall or 0)
        end)

        for i = 1, math.min(AI_LOAN_LIST_MAX_PER_TEAM, #candidates) do
            if globalListed >= AI_LOAN_LIST_MAX_GLOBAL then break end
            local entry = candidates[i]
            local p = entry.player
            local pAge = p:getAge(gameState.date.year)
            p.listedForLoan = true
            p.loanListDuration = (pAge <= 21) and 52 or 26
            globalListed = globalListed + 1
        end

        ::skipTeam::
    end
end

--- 兼容旧调用点（内部仍受转会窗约束）
function TransferManager.processAILoanListings(gameState)
    TransferManager._aiListPlayersForLoan(gameState)
end

--- AI 有效转会购买力（仅 AI 决策使用，不影响玩家 _getTransferBudget）
function TransferManager._getAIEffectiveBudget(team)
    local balance = team.balance or 0
    local tb = team.transferBudget or 0
    local fromBalance = math.floor(balance * 0.25)
    local effective = math.max(tb, fromBalance)
    return math.min(effective, math.floor(balance * 0.6))
end

--- AI 球队是否资金充裕（有余力持续引援）
function TransferManager._isAITeamAffluent(team)
    return (team.transferBudget or 0) > 5000000 or (team.balance or 0) > 20000000
end

--- 本周是否尝试主动引援（难度档位 + 资金充裕必试）
function TransferManager._shouldAITryTransfer(gameState, team)
    if TransferManager._isAITeamAffluent(team) then return true end
    local tier = DifficultySettings.get().transferTier or 2
    local chances = { 0.45, 0.65, 0.80 }
    local chance = chances[tier] or chances[2]
    return Random() <= chance
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

    local affluent = TransferManager._isAITeamAffluent(team)

    -- 找最弱 outfield 位置组（升级/补强共用）
    local function weakestOutfieldGroup()
        local weakest, weakestOvr = nil, 999
        local groups = {"DEF", "MID", "FWD"}
        for _, g in ipairs(groups) do
            if posAvgOvr[g] > 0 and posAvgOvr[g] < weakestOvr then
                weakestOvr = posAvgOvr[g]
                weakest = g
            end
        end
        return weakest
    end

    -- 优先级3: 升级动机（资金充裕 80%，否则 50%）
    local upgradeChance = affluent and 0.80 or 0.50
    if Random() < upgradeChance then
        local weakest = weakestOutfieldGroup()
        if weakest then
            return weakest, true  -- upgrade mode
        end
    end

    -- 资金充裕时仍补强最弱位置（非升级，候选范围更宽）
    if affluent then
        local weakest = weakestOutfieldGroup()
        if weakest then
            return weakest, false
        end
    end

    return nil, false
end

--- 寻找转会目标
function TransferManager._findTransferTarget(gameState, buyerTeam, needGroup, upgradeMode)
    local Constants = require("scripts/app/constants")
    local targetPositions = Constants.POSITION_GROUPS[needGroup] or {}
    local candidates = {}
    local budget = TransferManager._getAIEffectiveBudget(buyerTeam)
    local teamAvg = TransferManager._getTeamAverageOverall(gameState, buyerTeam)

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end
        if not player.teamId then goto continue end  -- 无俱乐部（自由球员/国家队虚拟球员）不参与俱乐部间转会
        if player.teamId == buyerTeam.id then goto continue end
        -- 玩家球队的球员：只有挂牌出售的才会被AI考虑
        if player.teamId == gameState.playerTeamId and not player.listedForSale then goto continue end
        -- 玩家正在谈判中的球员，AI 不应直接截胡
        if TransferManager.hasActiveBidOnPlayer(gameState, player.id, { buyerTeamId = gameState.playerTeamId }) then
            goto continue
        end

        -- 位置匹配
        local posMatch = false
        for _, pos in ipairs(targetPositions) do
            if player.position == pos then posMatch = true; break end
        end
        if not posMatch then goto continue end

        -- 财力检查（不超过有效预算的85%，且不超过余额的60%）
        local maxSpend = math.min(math.floor(budget * 0.85), math.floor((buyerTeam.balance or 0) * 0.6))
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

        -- 高薪低能惩罚：AI不愿接手工资与能力不匹配的球员
        -- fairWage = 25 * exp(0.117 * ovr)，基于联赛工资分布拟合
        local pWage = player.wage or 0
        local pOvr = player.overall or 50
        if pWage > 0 and pOvr < 78 then
            local fairWage = 25 * math.exp(0.117 * pOvr)
            if pWage > fairWage * 1.5 then
                -- 难度缩放：保守+正常完全跳过，宽松仅降权
                local transferTier = DifficultySettings.get().transferTier or 2
                if transferTier <= 2 then
                    -- 保守+正常：AI不会主动引进高薪低能球员
                    goto continue
                else
                    -- 宽松：轻微降权但不完全排除
                    weight = math.max(1, weight - 1)
                end
            end
        end

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

    -- AI 工资谈判：基于市场合理薪资，避免无限通胀
    local marketWage = TransferManager.getSuggestedTransferWage(player)
    local newWage = math.floor(marketWage * (0.95 + Random() * 0.15))  -- 市场价 -5% ~ +10%
    -- 保底不低于原工资（球员不接受降薪）
    newWage = math.max(player.wage, newWage)

    local canAfford, _ = TransferManager.checkWageBudget(gameState, buyerTeam.id, newWage)
    if not canAfford then return false end  -- 工资超预算，放弃

    -- 完成转会
    if sellerTeam then
        -- 通过 FinanceManager 处理卖方入账（更新 balance、transferBudget、seasonIncome、流水）
        FinanceManager.processTransferIn(gameState, sellerTeam.id, offerAmount, player.displayName or player.firstName)
    end

    TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id)
    player.listedForSale = false
    player.listedForLoan = false
    player.isYouth = false
    player.squadRole = "first_team"
    player.wage = newWage  -- 更新球员工资
    player.contractEnd = {year = gameState.date.year + TransferManager._calcExpectedYears(player, gameState.date.year), month = 6}

    -- 通过 FinanceManager 处理买方出账（更新 balance、seasonExpense、transferBudget、流水）
    FinanceManager.processTransferOut(gameState, buyerTeam.id, offerAmount, player.displayName or player.firstName)

    -- 更新名气和身价
    player:calculateReputation(buyerTeam.reputation or 300)
    player:calculateValue(gameState.date.year)

    TransferManager._markPlayerWindowMove(gameState, player.id)

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

    NewsGenerator.publishTransferNews(gameState, {
        playerId = player.id,
        fromTeamId = sellerTeam and sellerTeam.id or nil,
        toTeamId = buyerTeam.id,
        amount = offerAmount,
        type = "permanent",
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

    -- 清理该球员所有活跃报价（含玩家 pending 报价），避免 AI 截胡后玩家仍可继续买
    TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {
        soldToTeamId = buyerTeam.id,
    })

    return true  -- 交易成功
end

------------------------------------------------------
-- AI 对玩家球队球员的收购报价
------------------------------------------------------

--- 检查某个买家是否已对该球员有待处理的收购报价
--- @param buyerTeamId number|nil 买家ID，nil则检查是否有任何待处理报价
function TransferManager.hasPendingIncomingBid(gameState, playerId, buyerTeamId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingBid
            and (bid.status == "pending" or bid.status == "counter_pending"
                or bid.status == "awaiting_sale_confirmation" or bid.status == "player_considering_sale") then
            -- 如果指定了买家ID，只检查该买家是否重复出价
            if buyerTeamId then
                if bid.buyerTeamId == buyerTeamId then return true end
            else
                return true
            end
        end
    end
    return false
end

--- 获取某球员所有待处理的收购报价（多份报价竞争展示用）
--- @return table[] 该球员的所有活跃incoming bids
function TransferManager.getIncomingBidsForPlayer(gameState, playerId)
    TransferManager._ensureData(gameState)
    local bids = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingBid
            and (bid.status == "pending" or bid.status == "counter_pending"
                or bid.status == "awaiting_sale_confirmation" or bid.status == "player_considering_sale") then
            table.insert(bids, bid)
        end
    end
    -- 按金额降序排列，最高出价在前
    table.sort(bids, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
    return bids
end

local INCOMING_SALE_STATUS_PRIORITY = {
    awaiting_sale_confirmation = 1,
    pending = 2,
    counter_pending = 3,
    player_considering_sale = 4,
}

--- 选取应展示/处理的主报价（状态优先，同状态取最高价）
function TransferManager.pickPrimaryIncomingSaleBid(gameState, playerId)
    local bids = TransferManager.getIncomingBidsForPlayer(gameState, playerId)
    if #bids == 0 then return nil end
    table.sort(bids, function(a, b)
        local pa = INCOMING_SALE_STATUS_PRIORITY[a.status] or 99
        local pb = INCOMING_SALE_STATUS_PRIORITY[b.status] or 99
        if pa ~= pb then return pa < pb end
        return (a.amount or 0) > (b.amount or 0)
    end)
    return bids[1]
end

--- 读档/每日修复 incoming 出售 bid 异常（幂等，老存档加载时也会调用）
---@return table stats { stale, dupAwaiting, superseded }
function TransferManager.repairIncomingSaleBids(gameState, opts)
    opts = opts or {}
    TransferManager._ensureData(gameState)
    local stats = { stale = 0, dupAwaiting = 0, superseded = 0 }
    local date = gameState.date and {
        year = gameState.date.year, month = gameState.date.month, day = gameState.date.day,
    } or { year = 2025, month = 7, day = 1 }

    local YouthManager = require("scripts/systems/youth_manager")
    local activeStatuses = {
        pending = true, counter_pending = true,
        awaiting_sale_confirmation = true, player_considering_sale = true,
    }

    for _, bid in ipairs(gameState.transfers.bids) do
        if not bid.isIncomingBid or not activeStatuses[bid.status] then goto continueStale end
        local player = gameState.players[bid.playerId]
        local sellerTeam = bid.sellerTeamId and gameState.teams[bid.sellerTeamId]
        local stillOnSeller = player and bid.sellerTeamId
            and (player.teamId == bid.sellerTeamId
                or YouthManager.isOnTeamYouthSquad(gameState, bid.playerId, bid.sellerTeamId))
        if not player or not sellerTeam or not stillOnSeller then
            bid.status = "rejected"
            bid.rejectedDate = date
            stats.stale = stats.stale + 1
        end
        ::continueStale::
    end

    local awaitingByPlayer = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.isIncomingBid and bid.status == "awaiting_sale_confirmation" then
            if not awaitingByPlayer[bid.playerId] then
                awaitingByPlayer[bid.playerId] = {}
            end
            table.insert(awaitingByPlayer[bid.playerId], bid)
        end
    end

    local primaryAwaiting = {}
    for playerId, bids in pairs(awaitingByPlayer) do
        table.sort(bids, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
        primaryAwaiting[playerId] = bids[1]
        if #bids > 1 then
            for i = 2, #bids do
                bids[i].status = "rejected"
                bids[i].rejectedDate = date
                stats.dupAwaiting = stats.dupAwaiting + 1
            end
            if not opts.silent then
                local player = gameState.players[playerId]
                gameState:sendMessage({
                    category = "transfer",
                    title = "重复报价已清理",
                    body = string.format("%s 存在多份待确认出售报价，已自动保留最高报价，其余取消。",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
            end
        end
    end

    for _, bid in ipairs(gameState.transfers.bids) do
        if not bid.isIncomingBid or not activeStatuses[bid.status] then goto continueSuper end
        local keeper = primaryAwaiting[bid.playerId]
        if keeper and bid.id ~= keeper.id then
            bid.status = "rejected"
            bid.rejectedDate = date
            stats.superseded = stats.superseded + 1
        end
        ::continueSuper::
    end

    return stats
end

--- 活跃报价状态（未完成、未取消、未拒绝）
local _ACTIVE_BID_STATUSES = {
    pending = true, negotiating = true, counter_pending = true,
    fee_agreed = true, player_considering = true, awaiting_confirmation = true,
    awaiting_sale_confirmation = true, player_considering_sale = true,
}

--- 检查某球员是否有活跃报价（可选限定买家）
--- @param opts table|nil { buyerTeamId, excludeBidId }
function TransferManager.hasActiveBidOnPlayer(gameState, playerId, opts)
    TransferManager._ensureData(gameState)
    opts = opts or {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and _ACTIVE_BID_STATUSES[bid.status]
            and not _bidIdsEqual(bid.id, opts.excludeBidId) then
            if opts.buyerTeamId then
                if bid.buyerTeamId == opts.buyerTeamId then return true end
            else
                return true
            end
        end
    end
    return false
end

--- 球员已转会时作废该球员所有活跃报价（AI 直接成交 / 完成转会后调用）
--- @param opts table|nil { excludeBidId, soldToTeamId }
function TransferManager._invalidateActiveBidsForPlayer(gameState, playerId, opts)
    TransferManager._ensureData(gameState)
    opts = opts or {}
    local player = gameState.players[playerId]
    local buyerName = opts.soldToTeamId and gameState.teams[opts.soldToTeamId]
    buyerName = buyerName and (buyerName.name or buyerName.shortName) or "其他俱乐部"

    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and _ACTIVE_BID_STATUSES[bid.status]
            and not _bidIdsEqual(bid.id, opts.excludeBidId) then
            bid.status = "rejected"
            bid.rejectedDate = { year = gameState.date.year, month = gameState.date.month, day = gameState.date.day }
            if bid.buyerTeamId == gameState.playerTeamId and player then
                gameState:sendMessage({
                    category = "transfer",
                    title = "报价失效",
                    body = string.format("%s 已被 %s 签下，你的报价已自动取消。",
                        player.displayName, buyerName),
                    priority = "normal",
                })
            end
        end
    end
end

--- 验证 bid 的卖方仍是球员当前俱乐部
function TransferManager._validateBidSeller(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then return false, "球员不存在" end
    if player.teamId ~= bid.sellerTeamId then
        return false, string.format("%s 已不在原出售俱乐部，报价无法继续。",
            player.displayName or "该球员")
    end
    return true
end

--- 检查某球员是否已有 awaiting_sale_confirmation 状态的 bid（避免同一球员多个待确认出售阻断时间推进）
--- @param gameState table
--- @param playerId string
--- @param excludeBidId string|nil 排除的 bid id（用于状态转换时排除自身）
--- @return boolean
function TransferManager._hasAwaitingSaleConfirmation(gameState, playerId, excludeBidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingBid
            and bid.status == "awaiting_sale_confirmation"
            and not _bidIdsEqual(bid.id, excludeBidId) then
            return true
        end
    end
    return false
end

--- 为挂牌球员寻找合适的买家
function TransferManager._findBuyerForPlayer(gameState, player)
    local Constants = require("scripts/app/constants")

    -- 高薪低能检查：限制 AI 对工资与能力严重不匹配球员的兴趣
    local pWage = player.wage or 0
    local pOvr = player.overall or 50
    if pWage > 0 and pOvr < 78 then
        local fairWage = 25 * math.exp(0.117 * pOvr)
        if pWage > fairWage * 1.5 then
            local transferTier = DifficultySettings.get().transferTier or 2
            if transferTier <= 2 then
                -- 保守+正常：AI完全不愿接手高薪低能球员
                return nil
            end
            -- 宽松：继续正常匹配（但后续候选池仍有能力/预算门槛）
        end
    end

    local candidates = {}

    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto skip end
        if team.id == player.teamId then goto skip end
        -- 财力检查（挂牌球员折价出售，预算门槛放宽）
        local budget = TransferManager._getAIEffectiveBudget(team)
        -- 允许砍价到身价的35%，所以只要有效预算能承担35%身价就可能匹配
        if player.value * 0.35 > budget then goto skip end
        -- 能力匹配（挂牌球员范围宽松，低于队均15分的也可能作为替补/轮换引入）
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
        if player.overall < teamAvg - 15 or player.overall > teamAvg + 20 then goto skip end
        table.insert(candidates, team)
        ::skip::
    end

    if #candidates == 0 then return nil end
    return candidates[RandomInt(1, #candidates)]
end

--- 为挂牌外租球员寻找合适的租借买家（AI球队）
function TransferManager._findLoanBuyerForPlayer(gameState, player)
    local Constants = require("scripts/app/constants")
    local candidates = {}
    local loanFee = TransferManager.getLoanFeeBenchmark(player)

    for _, team in pairs(gameState.teams) do
        if team.id == gameState.playerTeamId then goto skip end
        if team.id == player.teamId then goto skip end
        -- 预算检查：租借费相对低廉，只要余额够付即可
        if (team.balance or 0) < loanFee * 0.5 then goto skip end
        -- 位置需求检查
        local need = TransferManager._assessTeamNeed(gameState, team)
        if need then
            -- 检查球员位置是否匹配球队需求
            local targetPositions = Constants.POSITION_GROUPS[need] or {}
            local posMatch = false
            for _, pos in ipairs(targetPositions) do
                if player.position == pos then posMatch = true; break end
            end
            if posMatch then
                table.insert(candidates, team)
                goto skip
            end
        end
        -- 即使无紧急需求，阵容较小的球队也可能租借补充深度
        if #(team.playerIds or {}) < 22 then
            table.insert(candidates, team)
        end
        ::skip::
    end

    if #candidates == 0 then return nil end
    return candidates[RandomInt(1, #candidates)]
end

--- 检查是否已存在对某球员的待处理租借报价（避免重复）
function TransferManager.hasPendingIncomingLoanBid(gameState, playerId, buyerTeamId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingLoanBid
            and (bid.status == "pending") then
            if buyerTeamId then
                if bid.buyerTeamId == buyerTeamId then return true end
            else
                return true
            end
        end
    end
    return false
end

--- 获取某球员所有待处理的租借报价
function TransferManager.getIncomingLoanBidsForPlayer(gameState, playerId)
    TransferManager._ensureData(gameState)
    local bids = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.playerId == playerId and bid.isIncomingLoanBid
            and (bid.status == "pending") then
            table.insert(bids, bid)
        end
    end
    return bids
end

--- 创建 AI 对玩家外租挂牌球员的租借报价（让玩家决策）
function TransferManager._createIncomingLoanBid(gameState, buyerTeam, player)
    TransferManager._ensureData(gameState)

    local duration = player.loanListDuration or 26
    local loanFee = TransferManager.getLoanFeeBenchmark(player, duration)
    -- AI 出价在基准的 0.7~1.1 之间浮动
    local offerFee = math.floor(loanFee * (0.7 + Random() * 0.4))
    local wageShare = 0.4 + Random() * 0.3  -- AI 愿意承担 40%~70% 工资

    local bid = {
        id = gameState.transfers.nextBidId,
        playerId = player.id,
        buyerTeamId = buyerTeam.id,
        sellerTeamId = gameState.playerTeamId,
        amount = offerFee,
        loanDuration = duration,
        wageShare = wageShare,
        status = "pending",
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        isIncomingLoanBid = true,  -- 标记为收到的租借报价
        type = "loan",
    }

    gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
    table.insert(gameState.transfers.bids, bid)

    -- 通知玩家
    gameState:sendMessage({
        category = "transfer",
        title = "收到租借报价: " .. player.displayName,
        body = string.format(
            "%s 希望租借 %s（%d周），租借费 %s，对方承担 %.0f%% 工资。",
            buyerTeam.name, player.displayName, duration,
            fmtMoney(offerFee), wageShare * 100),
        priority = "high",
        popup = true,
        actions = {
            { label = "同意外租", actionId = "accept_incoming_loan_bid", data = { bidId = bid.id } },
            { label = "拒绝", actionId = "reject_incoming_loan_bid", data = { bidId = bid.id } },
        },
    })
    return bid
end

--- 玩家接受收到的租借报价 → 直接完成租借
function TransferManager.acceptIncomingLoanBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" and bid.isIncomingLoanBid then
            -- 直接完成租借（球员已主动挂牌，无需再征求球员意见）
            TransferManager._completeLoan(gameState, bid)
            return true
        end
    end
    return false
end

--- 玩家拒绝收到的租借报价
function TransferManager.rejectIncomingLoanBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.id == bidId and bid.status == "pending" and bid.isIncomingLoanBid then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "租借报价已拒绝",
                body = string.format("你拒绝了 %s 对 %s 的租借报价。",
                    buyerTeam and buyerTeam.name or "未知球队",
                    player and player.displayName or "该球员"),
                priority = "normal",
            })
            return true
        end
    end
    return false
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

    local YouthManager = require("scripts/systems/youth_manager")
    local isYouthSale = YouthManager.isYouthSquadPlayer(gameState, player)
    local handleHint = isYouthSale
        and "前往转会市场「待售」或青训页 / 球员详情合同页处理报价。"
        or "前往转会市场「待售」或阵容页长按该球员处理报价。"

    -- 通知消息
    gameState:sendMessage({
        category = "transfer",
        title = "收到报价: " .. player.displayName,
        body = string.format("%s 对 %s 出价 %s（球员身价 %s）。\n%s",
            buyerTeam.name, player.displayName, fmtMoney(offerAmount), fmtMoney(player.value), handleHint),
        priority = "high",
        popup = true,
        data = { bidId = bid.id, playerId = player.id },
    })
    return bid
end

--- 接受收到的报价（玩家操作）→ 进入"等待确认出售"状态
function TransferManager.acceptIncomingBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if _bidIdsEqual(bid.id, bidId) and bid.status == "pending" and bid.isIncomingBid then
            -- 进入"球员考虑中"状态，球员需要时间决定是否接受转会
            bid.status = "player_considering_sale"
            bid.playerConsiderSaleDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}

            -- Deadline Day 效应
            local isDeadline = TransferManager.isDeadlineDay(gameState)
            if isDeadline then
                bid.playerConsiderSaleDays = 1
                bid.isDeadlineDeal = true
            else
                bid.playerConsiderSaleDays = RandomInt(1, 2)  -- 卖出方球员考虑1-2天
            end

            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "球员考虑中: " .. (player and player.displayName or "球员"),
                body = string.format("你已同意 %s 对 %s 的报价（%s）。\n球员正在考虑是否接受转会，预计 %d 天后给出答复。%s",
                    buyerTeam and buyerTeam.name or "未知球队",
                    player and player.displayName or "未知球员",
                    fmtMoney(bid.amount),
                    bid.playerConsiderSaleDays,
                    isDeadline and "\n⚠️ 关窗日加急处理" or ""),
                priority = "high",
            })
            return true
        end
    end
    return false
end

--- 拒绝收到的报价（玩家操作）
function TransferManager.rejectIncomingBid(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if _bidIdsEqual(bid.id, bidId) and bid.status == "pending" and bid.isIncomingBid then
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

--- 还价（玩家要求更高价格）→ 进入"还价待回复"状态，AI延迟1-3天回复
function TransferManager.counterIncomingBid(gameState, bidId, askAmount)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if _bidIdsEqual(bid.id, bidId) and bid.status == "pending" and bid.isIncomingBid then
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local player = gameState.players[bid.playerId]
            if not buyerTeam or not player then return false end

            -- 设为 counter_pending 状态，等待AI回复（1-3天延迟）
            bid.status = "counter_pending"
            bid.counterAskAmount = askAmount
            bid.counterDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            bid.counterWaitDays = RandomInt(1, 3) -- AI需要1-3天考虑

            gameState:sendMessage({
                category = "transfer",
                title = "还价已发出",
                body = string.format("你向 %s 提出了 %s 的要价（%s），等待对方回复...",
                    buyerTeam.name, fmtMoney(askAmount), player.displayName),
                priority = "normal",
                data = { bidId = bid.id, playerId = player.id },
            })
            return true, "counter_sent"
        end
    end
    return false
end

--- 处理AI对还价的回复（由processDailyBids调用，延迟后执行）
function TransferManager._processCounterResponse(gameState, bid)
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local player = gameState.players[bid.playerId]
    if not buyerTeam or not player then
        bid.status = "rejected"
        return
    end

    local askAmount = bid.counterAskAmount or bid.amount
    -- AI 决定是否接受还价
    local ratio = askAmount / (player.value or 1)
    local acceptChance = 0
    if ratio <= 1.0 then acceptChance = 0.9
    elseif ratio <= 1.1 then acceptChance = 0.7
    elseif ratio <= 1.2 then acceptChance = 0.5
    elseif ratio <= 1.3 then acceptChance = 0.3
    else acceptChance = 0.1 end

    if Random() < acceptChance then
        -- 守卫检查：若该球员已有其他 awaiting_sale_confirmation 的 bid，则拒绝本次还价
        if TransferManager._hasAwaitingSaleConfirmation(gameState, bid.playerId, bid.id) then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            bid.responseDate = bid.rejectedDate
            gameState:sendMessage({
                category = "transfer",
                title = "交易取消",
                body = string.format("%s 已有其他待确认的出售报价，%s 的还价协商自动取消。",
                    player.displayName, buyerTeam.name),
                priority = "normal",
            })
            return
        end
        -- AI接受还价 → 进入等待玩家确认出售状态
        bid.amount = askAmount
        bid.status = "awaiting_sale_confirmation"
        bid.saleConfirmDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        gameState:sendMessage({
            category = "transfer",
            title = "还价被接受: " .. player.displayName,
            body = string.format("%s 接受了你的要价 %s。\n请确认出售 %s 或取消交易。",
                buyerTeam.name, fmtMoney(askAmount), player.displayName),
            priority = "high",
            popup = true,
            actions = {
                { label = "确认出售", actionId = "confirm_sale", data = { bidId = bid.id } },
                { label = "取消交易", actionId = "cancel_sale", data = { bidId = bid.id } },
            },
        })
    else
        -- AI 拒绝还价
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
    end
end

--- 完成收到的出售转会
function TransferManager._completeIncomingSale(gameState, bid)
    local player = gameState.players[bid.playerId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    if not player or not sellerTeam or not buyerTeam then return end

    TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id)
    player.listedForSale = false
    player.isYouth = false
    player.squadRole = "first_team"
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

    TransferManager._markPlayerWindowMove(gameState, player.id)

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
        priority = "normal",
    })

    NewsGenerator.publishTransferNews(gameState, {
        playerId = player.id,
        fromTeamId = sellerTeam.id,
        toTeamId = buyerTeam.id,
        amount = bid.amount,
        type = "permanent",
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

    -- 清理同一球员的其他活跃 incoming bid（球员已转会，其他报价自动失效）
    for _, otherBid in ipairs(gameState.transfers.bids) do
        if otherBid.playerId == bid.playerId and otherBid.id ~= bid.id and otherBid.isIncomingBid then
            local activeStatuses = {
                pending = true, counter_pending = true,
                awaiting_sale_confirmation = true, player_considering_sale = true,
            }
            if activeStatuses[otherBid.status] then
                otherBid.status = "rejected"
                otherBid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            end
        end
    end
end

--- 确认出售球员（玩家最终确认，公开API）
function TransferManager.confirmSale(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if _bidIdsEqual(bid.id, bidId) and bid.status == "awaiting_sale_confirmation" and bid.isIncomingBid then
            bid.status = "completed"
            bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            TransferManager._completeIncomingSale(gameState, bid)
            return true, nil
        end
    end
    return false, "未找到待确认的出售交易"
end

--- 取消出售确认（玩家反悔，公开API）
function TransferManager.cancelSale(gameState, bidId)
    TransferManager._ensureData(gameState)
    for _, bid in ipairs(gameState.transfers.bids) do
        if _bidIdsEqual(bid.id, bidId) and bid.status == "awaiting_sale_confirmation" and bid.isIncomingBid then
            local player = gameState.players[bid.playerId]
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            gameState:sendMessage({
                category = "transfer",
                title = "出售已取消",
                body = string.format("你取消了将 %s 出售给 %s 的交易。",
                    player and player.displayName or "该球员",
                    buyerTeam and buyerTeam.name or "买方球队"),
                priority = "normal",
            })
            return true, nil
        end
    end
    return false, "未找到待确认的出售交易"
end

------------------------------------------------------
-- 租借系统
------------------------------------------------------

--- 估算转会报价的合理周薪（与 AI 买人逻辑一致）
function TransferManager.getSuggestedTransferWage(player)
    local wage = player and player.wage or 0
    local value = player and player.value or 0
    return math.max(wage, math.floor(value / 260))
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
            TransferManager._completeLoan(gameState, bid)
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

    if round >= maxRounds then
        TransferManager._rejectBid(gameState, bid, "租借费谈判回合耗尽，对方决定不出租。")
        return
    end

    local acceptThreshold = 1.15 - (mood / 200) - round * 0.05 + diffMods.thresholdOffset
    if player.listedForLoan then acceptThreshold = acceptThreshold - 0.2 end
    if player.squadRole == "youth" or player.squadRole == "squad" then acceptThreshold = acceptThreshold - 0.08 end
    if player.squadRole == "key" then acceptThreshold = acceptThreshold + 0.15 end

    local age = player.getAge and player:getAge(gameState.date.year) or 26
    local ageFactor = math.max(-0.1, math.min(0.1, (26 - age) * 0.015))
    acceptThreshold = acceptThreshold + ageFactor

    if ratio >= math.max(acceptThreshold, 0.85) then
        TransferManager._acceptBid(gameState, bid)
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
        maxRounds = RandomInt(3, 5),
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
    if not player then return end

    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local sellerTeam = gameState.teams[bid.sellerTeamId]
    if not buyerTeam then return end

    -- 球员标记为租借状态
    player.squadRole = "loaned"
    player._loanOriginTeamId = bid.sellerTeamId
    player.teamId = bid.buyerTeamId
    player.listedForSale = false
    player.listedForLoan = false
    player.loanListDuration = nil

    TransferManager._markPlayerWindowMove(gameState, player.id)

    TransferManager._assignPlayerToTeam(gameState, player, bid.buyerTeamId)

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

    -- 回到原球队
    TransferManager._assignPlayerToTeam(gameState, player, loan.originTeamId)
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
        if n.playerId == playerId and (n.status == "pending" or n.status == "negotiating") then
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

--- 玩家确认签入自由球员（公开API，从 inbox action 调用）
function TransferManager.confirmFreeAgent(gameState, negoId)
    TransferManager._ensureData(gameState)
    if not gameState.transfers.freeAgentNegos then return nil, "无谈判数据" end
    for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
        if nego.id == negoId and nego.status == "awaiting_confirmation" then
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
            TransferManager._assignPlayerToTeam(gameState, player, team.id)
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
        elseif nego.status == "awaiting_confirmation" then
            -- 玩家未及时确认，球员失去耐心（5天超时）
            local confirmDate = nego.confirmDate or nego.responseDate or nego.date
            local daysSince = TransferManager._daysBetween(confirmDate, gameState.date)
            if daysSince >= 5 then
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
    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.teamId then return false, "球员已有球队" end
    if player.retired then return false, "球员已退役" end

    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队" end

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
            positionSet = { [positionFilter] = true }
        end
    end

    for _, player in pairs(gameState.players) do
        if not player.teamId and not player.retired then
            if not positionSet or positionSet[player.position] then
                table.insert(result, player)
            end
        end
    end

    -- 按能力排序
    table.sort(result, function(a, b) return a.overall > b.overall end)
    return result
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

--- 租借方续租（延长租期）
function TransferManager.extendLoan(gameState, playerId, extraWeeks)
    TransferManager._ensureData(gameState)
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

    loan.remainingDays = (loan.remainingDays or 0) + extraWeeks * 7
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

    -- 高薪低能惩罚：AI不愿接手工资与能力严重不匹配的球员
    local pWage = player.wage or 0
    local pOvr = player.overall or 50
    if pWage > 0 and pOvr < 78 then
        local fairWage = 25 * math.exp(0.117 * pOvr)
        if pWage > fairWage * 1.5 then
            local transferTier = DifficultySettings.get().transferTier or 2
            if transferTier <= 2 then
                -- 保守+正常：AI直接拒绝高薪低能推销
                bid.status = "rejected"
                return
            end
            -- 宽松：超薪程度影响兴趣但不完全拒绝
            local overpaidRatio = math.min((pWage / fairWage), 3.5)
            local basePenalty = (overpaidRatio - 1.5) * 20  -- 0~40
            interest = interest - math.floor(basePenalty * 0.35)
        end
    end

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
                popup = true,
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

    TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)

    TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id)
    player.listedForSale = false
    player.isYouth = false
    player.squadRole = "first_team"
    TransferManager._attachFutureClauses(player, bid)

    -- 更新球员合同（买方给出的个人条款）
    if bid.wageOffer and bid.wageOffer > 0 then
        player.wage = bid.wageOffer
    end
    player.contractEnd = { year = gameState.date.year + 3, month = 6 }

    -- 更新名气和身价
    player:calculateReputation(buyerTeam.reputation or 300)
    player:calculateValue(gameState.date.year)

    TransferManager._markPlayerWindowMove(gameState, player.id)

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
        priority = "normal",
    })

    NewsGenerator.publishTransferNews(gameState, {
        playerId = player.id,
        fromTeamId = sellerTeam.id,
        toTeamId = buyerTeam.id,
        amount = bid.amount,
        type = "permanent",
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
    -- reputation 实际范围约 500-950，英超内部差距可达 200-350
    -- 阈值要足够高，只在极端降级（如英超豪门→低级别联赛）时才硬拒绝
    -- 33岁以上老将（生涯末期不太挑剔）和22岁以下年轻人（渴望上场机会）对声望不太看重
    local currentTeam = gameState.teams[player.teamId]
    if currentTeam then
        local repDiff = currentTeam.reputation - targetTeam.reputation
        local age = player.birthYear and (gameState.date.year - player.birthYear) or 25
        -- 阈值提高：只有声望差距超过350（如950→600的极端情况）才硬拒绝
        local repThreshold = 350  -- 默认阈值（真正的极端落差）
        if age >= 33 then
            repThreshold = 500  -- 老将：几乎不可能因声望拒绝
        elseif age <= 22 then
            repThreshold = 450  -- 年轻人：渴望出场机会，非常宽容
        end
        if repDiff > repThreshold then
            return false, "不愿降级到低声望球队"
        end
    end

    -- 2. 球员士气高且是核心球员 → 不太想走
    -- 但如果目标球队声望更高，核心球员也会被吸引
    if player.morale >= 80 and player.squadRole == "key" then
        local targetBetter = currentTeam and (targetTeam.reputation > currentTeam.reputation + 50)
        if not targetBetter then
            if Random() < 0.5 then
                return false, "作为核心球员，不想离开"
            end
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

    -- 士气影响（高士气仅轻微降低意愿，不应成为阻止转会的主因）
    if player.morale < 30 then willingness = willingness + 30  -- 很想走
    elseif player.morale < 50 then willingness = willingness + 15
    elseif player.morale > 80 then willingness = willingness - 10
    end

    -- 角色影响（核心球员有一定留队倾向，但不是绝对拒绝）
    if player.squadRole == "key" then willingness = willingness - 10
    elseif player.squadRole == "squad" or player.squadRole == "youth" then willingness = willingness + 10
    end

    -- 目标球队声望影响（reputation 实际范围约 500-950，最大差距~350）
    -- 同联赛内100点差距很常见，不应视为极端降级；200+才是真正的大幅降级
    -- 33+老将和22-年轻人对声望降级的抵触减半
    if targetTeam then
        local currentTeam = gameState.teams[player.teamId]
        if currentTeam then
            local repDiff = targetTeam.reputation - currentTeam.reputation
            local age = player.birthYear and (gameState.date.year - player.birthYear) or 25
            local ageFactor = (age >= 33 or age <= 22) and 0.5 or 1.0
            if repDiff > 200 then willingness = willingness + 45      -- 显著升级（如中游→豪门）
            elseif repDiff > 100 then willingness = willingness + 35  -- 明显升级
            elseif repDiff > 30 then willingness = willingness + 15   -- 小幅升级
            elseif repDiff < -250 then willingness = willingness - math.floor(18 * ageFactor)  -- 极端降级（如豪门→低级联赛）
            elseif repDiff < -150 then willingness = willingness - math.floor(12 * ageFactor)  -- 明显降级
            elseif repDiff < -80 then willingness = willingness - math.floor(5 * ageFactor)    -- 小幅降级
            end
        end
    end

    -- 挂牌出售的球员更愿意走
    if player.listedForSale then willingness = willingness + 20 end

    -- 死敌关系：球员强烈拒绝
    if targetTeam and player.teamId then
        if TransferManager._isRivalry(gameState, player.teamId, targetTeamId) then
            return "refusing", "不愿去死敌球队"
        end
    end

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
    local key = teamId1 < teamId2
        and (teamId1 .. "_" .. teamId2)
        or (teamId2 .. "_" .. teamId1)
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

------------------------------------------------------
-- 修改 processDailyBids 以支持推销报价
------------------------------------------------------

------------------------------------------------------
-- AI 报价处理（每天调用）
------------------------------------------------------
function TransferManager.processDailyBids(gameState)
    TransferManager._ensureData(gameState)

    -- 转会窗口关闭时，自动取消所有未完成的俱乐部间交易，并下架外租挂牌
    if not TransferManager.isInTransferWindow(gameState) then
        local cancelledCount = 0
        for _, bid in ipairs(gameState.transfers.bids) do
            -- 只处理俱乐部间交易（非自由球员）且还在进行中的
            local activeStatuses = {
                pending = true, negotiating = true, player_considering = true,
                fee_agreed = true, awaiting_confirmation = true,
                counter_pending = true, awaiting_sale_confirmation = true,
                player_considering_sale = true,
            }
            if activeStatuses[bid.status] and not bid.isFreeAgent then
                bid.status = "cancelled"
                bid.cancelReason = "transfer_window_closed"
                cancelledCount = cancelledCount + 1
            end
        end
        if cancelledCount > 0 then
            gameState:sendMessage({
                category = "transfer",
                title = "转会窗口已关闭",
                body = string.format("转会窗口已关闭，%d 笔未完成的俱乐部间交易已自动取消。自由球员签约不受影响。",
                    cancelledCount),
                priority = "normal",
            })
        end
        TransferManager.clearLoanListingsOutsideWindow(gameState)
        -- 窗口关闭后仍然处理自由球员相关逻辑，但俱乐部间交易不再推进
        -- 下方的处理循环只作用于仍有效的 bid，已 cancelled 的会跳过
    end

    -- 存档修复：incoming 出售 bid 异常（读档后首日也会执行，此处每日兜底）
    TransferManager.repairIncomingSaleBids(gameState)

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
                        TransferManager._processAILoanResponse(gameState, bid)
                    elseif bid.isIncomingBid then
                        -- 收到的报价由玩家手动接受/还价/拒绝，不走买方 AI 回应
                    else
                        TransferManager._processAIResponse(gameState, bid)
                    end
                end
            end
        elseif bid.status == "negotiating" then
            if not bid.isPushSale and not bid.isIncomingBid then
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

    -- player_considering 状态：球员考虑期结束后自动尝试个人条款协商
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "player_considering" and bid.playerConsiderDate then
            local daysSince = TransferManager._daysBetween(bid.playerConsiderDate, gameState.date)
            if daysSince >= (bid.playerConsiderDays or 2) then
                -- 考虑期结束，进入个人条款协商
                bid.status = "fee_agreed"
                TransferManager._attemptPersonalTerms(gameState, bid)
            end
        end
    end

    -- fee_agreed 状态超时处理（7天未操作则取消）
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "fee_agreed" and bid.feeAgreedDate then
            -- 个人条款被拒后从最后一次协商日起算，避免考虑期占用超时窗口
            local refDate = bid.personalTermsNegotiateDate or bid.feeAgreedDate
            local daysSinceFeeAgreed = TransferManager._daysBetween(refDate, gameState.date)
            if daysSinceFeeAgreed >= 7 then
                local player = gameState.players[bid.playerId]
                TransferManager._rejectBid(gameState, bid,
                    string.format("与 %s 的个人条款协商超时（7天未回应），转会费协议作废。",
                        player and player.displayName or "该球员"))
            end
        end
    end

    -- awaiting_confirmation 状态超时处理（5天未确认则取消）
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "awaiting_confirmation" then
            local refDate = bid.confirmDate or bid.feeAgreedDate
            if not refDate then goto continueAwaitingConfirm end
            local daysSinceConfirm = TransferManager._daysBetween(refDate, gameState.date)
            if daysSinceConfirm >= 5 then
                local player = gameState.players[bid.playerId]
                TransferManager._rejectBid(gameState, bid,
                    string.format("%s 等待你的答复太久，决定不再等待。",
                        player and player.displayName or "该球员"))
            end
            ::continueAwaitingConfirm::
        end
    end

    -- player_considering_sale 状态：被出售球员考虑期结束后判断是否同意
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "player_considering_sale" and bid.isIncomingBid and bid.playerConsiderSaleDate then
            local daysSince = TransferManager._daysBetween(bid.playerConsiderSaleDate, gameState.date)
            if daysSince >= (bid.playerConsiderSaleDays or 2) then
                -- 考虑期结束，判断球员是否同意
                local consent, reason = TransferManager._requirePlayerConsentForTransfer(gameState, bid)
                local player = gameState.players[bid.playerId]
                local buyerTeam = gameState.teams[bid.buyerTeamId]
                local playerName = player and player.displayName or "该球员"
                local buyerName = buyerTeam and buyerTeam.name or "买方球队"

                if consent then
                    -- 守卫检查：若该球员已有其他 awaiting_sale_confirmation 的 bid，则自动拒绝本次
                    -- 避免同一球员产生多个待确认出售阻断时间推进
                    if TransferManager._hasAwaitingSaleConfirmation(gameState, bid.playerId, bid.id) then
                        bid.status = "rejected"
                        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                        gameState:sendMessage({
                            category = "transfer",
                            title = "转会取消",
                            body = string.format("%s 已有其他待确认的转会报价，%s 的报价自动取消。",
                                playerName, buyerName),
                            priority = "normal",
                        })
                        goto continuePlayerConsidering
                    end
                    -- 球员同意，进入等待玩家最终确认出售状态
                    bid.status = "awaiting_sale_confirmation"
                    bid.saleConfirmDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                    gameState:sendMessage({
                        category = "transfer",
                        title = "球员同意转会！",
                        body = string.format("%s 同意加盟 %s！\n请确认出售或取消交易。",
                            playerName, buyerName),
                        priority = "high",
                        actions = {
                            { label = "确认出售", actionId = "confirm_sale", data = { bidId = bid.id } },
                            { label = "取消交易", actionId = "cancel_sale", data = { bidId = bid.id } },
                        },
                        -- 标记为需要弹窗通知
                        popup = true,
                    })
                else
                    -- 球员拒绝转会
                    bid.status = "rejected"
                    bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                    gameState:sendMessage({
                        category = "transfer",
                        title = "球员拒绝转会",
                        body = string.format("%s 拒绝加盟 %s。\n原因：%s",
                            playerName, buyerName, reason or "条件不满意"),
                        priority = "normal",
                    })
                end
            end
        end
        ::continuePlayerConsidering::
    end

    -- pending incoming bid 超时：玩家长期未回复，买方撤回报价
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "pending" and bid.isIncomingBid then
            local daysSince = TransferManager._daysBetween(bid.date, gameState.date)
            if daysSince >= 7 then
                local player = gameState.players[bid.playerId]
                local buyerTeam = gameState.teams[bid.buyerTeamId]
                bid.status = "rejected"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                bid.responseDate = bid.rejectedDate
                gameState:sendMessage({
                    category = "transfer",
                    title = "报价已过期",
                    body = string.format("%s 对 %s 的报价（%s）因长时间未回复已撤回。",
                        buyerTeam and buyerTeam.name or "买方球队",
                        player and player.displayName or "该球员",
                        fmtMoney(bid.amount)),
                    priority = "normal",
                })
            end
        end
    end

    -- pending incoming loan bid 超时：玩家长期未回复，租借方撤回报价
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "pending" and bid.isIncomingLoanBid then
            local daysSince = TransferManager._daysBetween(bid.date, gameState.date)
            if daysSince >= 5 then
                local player = gameState.players[bid.playerId]
                local buyerTeam = gameState.teams[bid.buyerTeamId]
                bid.status = "rejected"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "租借报价已过期",
                    body = string.format("%s 对 %s 的租借报价因长时间未回复已撤回。",
                        buyerTeam and buyerTeam.name or "租借方",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
            end
        end
    end

    -- counter_pending 状态：AI考虑还价（出售方向，1-3天延迟）
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "counter_pending" and bid.isIncomingBid and bid.counterDate then
            local daysSince = TransferManager._daysBetween(bid.counterDate, gameState.date)
            if daysSince >= (bid.counterWaitDays or 2) then
                TransferManager._processCounterResponse(gameState, bid)
            end
        end
    end

    -- awaiting_sale_confirmation 状态超时处理（出售方向，5天未确认则买方撤回）
    for _, bid in ipairs(gameState.transfers.bids) do
        if bid.status == "awaiting_sale_confirmation" and bid.isIncomingBid and bid.saleConfirmDate then
            local daysSince = TransferManager._daysBetween(bid.saleConfirmDate, gameState.date)
            if daysSince >= 5 then
                local player = gameState.players[bid.playerId]
                local buyerTeam = gameState.teams[bid.buyerTeamId]
                bid.status = "rejected"
                bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                gameState:sendMessage({
                    category = "transfer",
                    title = "报价已过期",
                    body = string.format("%s 等待你确认出售 %s 太久（5天），已撤回报价。",
                        buyerTeam and buyerTeam.name or "买方球队",
                        player and player.displayName or "该球员"),
                    priority = "normal",
                })
            end
        end
    end

    -- 竞争性报价处理
    TransferManager.processCompetitiveBids(gameState)
end

function TransferManager._processLoanBidResponse(gameState, bid)
    -- 兼容旧测试/存档：走完整 AI 租借谈判流程
    TransferManager._processAILoanResponse(gameState, bid)
end

--- 获取所有活跃报价（状态为 pending 或 negotiating）
---@param gameState table
---@return table[]
function TransferManager.getActiveBids(gameState)
    TransferManager._ensureData(gameState)
    local activeBids = {}
    for _, bid in ipairs(gameState.transfers.bids or {}) do
        if bid.status == "pending" or bid.status == "negotiating"
            or bid.status == "counter_pending" or bid.status == "awaiting_sale_confirmation" then
            table.insert(activeBids, bid)
        end
    end
    return activeBids
end

--- 挂牌出售球员（一线队或青训队已签入球员）
---@param gameState table
---@param player table
---@return boolean success
---@return string|nil error
function TransferManager.listForSale(gameState, player)
    if not gameState or not player then return false, "无效球员" end

    local YouthManager = require("scripts/systems/youth_manager")
    local isYouthSquad = YouthManager.isYouthSquadPlayer(gameState, player)
    local myTeamId = gameState.playerTeamId

    if isYouthSquad then
        if player.teamId ~= myTeamId then
            return false, "只能挂牌本队青训球员"
        end
    elseif player.teamId ~= myTeamId then
        return false, "只能挂牌本队球员"
    end

    if player.squadRole == "loaned" then return false, "外租中球员无法挂牌" end
    if player.listedForLoan then return false, "请先取消外租挂牌" end
    if player.injured then
        return false, player:getInjuryBlockReason() or "伤员无法挂牌出售"
    end

    local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
    if not moveOk then return false, moveErr end

    local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
    if not windowOk then return false, windowErr end

    player.listedForSale = true
    player.listedForLoan = false
    gameState:sendMessage({
        category = "transfer",
        title = player.displayName .. " 已挂牌",
        body = isYouthSquad
            and string.format("%s 已被挂牌出售（青训），等待买家报价。", player.displayName)
            or string.format("%s 已被挂牌出售，等待买家报价。", player.displayName),
        priority = "normal",
    })
    return true
end

--- 取消挂牌（同时取消该球员所有活跃的 incoming bid，避免残留阻断）
---@param gameState table|nil 传入时会清理活跃bid；不传时仅清除标记（兼容旧调用）
---@param player table
function TransferManager.delistPlayer(gameState, player)
    -- 兼容旧调用方式: delistPlayer(player)
    if player == nil and gameState and gameState.displayName then
        player = gameState
        gameState = nil
    end
    if not gameState and _G.gameState then
        gameState = _G.gameState
    end

    player.listedForSale = false

    -- 清理该球员所有活跃的 incoming bid
    if gameState then
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == player.id and bid.isIncomingBid then
                local activeStatuses = {
                    pending = true, counter_pending = true,
                    awaiting_sale_confirmation = true, player_considering_sale = true,
                }
                if activeStatuses[bid.status] then
                    bid.status = "rejected"
                    bid.rejectedDate = gameState.date and
                        {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day} or nil
                end
            end
        end
    end
end

return TransferManager
