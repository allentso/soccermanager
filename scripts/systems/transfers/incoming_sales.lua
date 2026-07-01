-- systems/transfers/incoming_sales.lua
-- 接收报价与出售流程，从 transfer_manager.lua 拆分。

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")
local StaffManager = require("scripts/systems/staff_manager")
local Helpers = require("scripts/systems/transfers/transfer_helpers")
local randInt = Helpers.randInt
local fmtMoney = Helpers.fmtMoney
local _bidIdsEqual = Helpers.bidIdsEqual
local _posToGroup = Helpers.posToGroup

return function(TransferManager)
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

        local activeIncomingBids = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if not bid.isIncomingBid or not activeStatuses[bid.status] then goto continueStale end
            activeIncomingBids[#activeIncomingBids + 1] = bid
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
        for _, bid in ipairs(activeIncomingBids) do
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

        for _, bid in ipairs(activeIncomingBids) do
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

    local _ACTIVE_FREE_AGENT_NEGO_STATUSES = {
        pending = true,
        negotiating = true,
        awaiting_confirmation = true,
    }

    --- 进行中的自由球员谈判所涉球员 ID（Housekeeping 清理自由球员池时须保护）
    ---@param gameState table
    ---@return table<number, boolean>
    function TransferManager.getProtectedFreeAgentPlayerIds(gameState)
        local ids = {}
        TransferManager._ensureData(gameState)
        for _, nego in ipairs(gameState.transfers.freeAgentNegos or {}) do
            if nego.playerId and _ACTIVE_FREE_AGENT_NEGO_STATUSES[nego.status] then
                ids[nego.playerId] = true
            end
        end
        return ids
    end

    --- 读档/每日修复：球员已消失或已加盟别队的自由球员谈判（幂等）
    ---@return table stats { stale }
    function TransferManager.repairStaleFreeAgentNegos(gameState, opts)
        opts = opts or {}
        TransferManager._ensureData(gameState)
        local stats = { stale = 0 }
        local date = gameState.date and {
            year = gameState.date.year, month = gameState.date.month, day = gameState.date.day,
        } or { year = 2025, month = 7, day = 1 }

        for _, nego in ipairs(gameState.transfers.freeAgentNegos or {}) do
            if not _ACTIVE_FREE_AGENT_NEGO_STATUSES[nego.status] then goto continue_nego end
            local player = gameState.players[nego.playerId]
            local stale = not player or player.retired or player.teamId ~= nil
            if stale then
                local wasAwaiting = nego.status == "awaiting_confirmation"
                nego.status = "cancelled"
                nego.rejectedDate = date
                stats.stale = stats.stale + 1
                if not opts.silent and wasAwaiting then
                    gameState:sendMessage({
                        category = "transfer",
                        title = "自由球员签约已失效",
                        body = string.format("%s 已无法签入，相关谈判已自动取消。",
                            player and player.displayName or "该自由球员"),
                        priority = "normal",
                    })
                end
            end
            ::continue_nego::
        end

        return stats
    end

    --- 读档/每日修复：待确认签入但球员已消失的转会报价（幂等）
    ---@return table stats { stale }
    function TransferManager.repairStaleTransferSignBids(gameState, opts)
        opts = opts or {}
        TransferManager._ensureData(gameState)
        local stats = { stale = 0 }
        local date = gameState.date and {
            year = gameState.date.year, month = gameState.date.month, day = gameState.date.day,
        } or { year = 2025, month = 7, day = 1 }

        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.status ~= "awaiting_confirmation" then goto continue_bid end
            local player = gameState.players[bid.playerId]
            if not player then
                bid.status = "cancelled"
                bid.rejectedDate = date
                stats.stale = stats.stale + 1
            end
            ::continue_bid::
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

    --- 预建「指定买家对哪些球员有活跃报价」集合（playerId -> true），一次 O(bids) 遍历。
    --- 供 _findTransferTarget 在批量撮合时 O(1) 查表，替代每候选都 O(bids) 全扫
    --- hasActiveBidOnPlayer——这是转会窗 AI 引援卡顿（bids 累积时退化为 O(候选×bids)）的主因。
    function TransferManager._buildPlayerActiveBidSet(gameState, buyerTeamId)
        TransferManager._ensureData(gameState)
        local set = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if _ACTIVE_BID_STATUSES[bid.status] and bid.buyerTeamId == buyerTeamId then
                set[bid.playerId] = true
            end
        end
        return set
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
    --- 预构建 AI 买家球队快照（队均/有效预算），供同一日多名挂牌球员复用，
    --- 避免对每名挂牌球员都重算全联盟球队的队均与预算（O(挂牌×球队×阵容) → O(球队×阵容)）。
    function TransferManager._buildBuyerTeamCache(gameState)
        local cache = {}
        for _, team in pairs(gameState.teams) do
            if team.id ~= gameState.playerTeamId then
                local needGroup = TransferManager._assessTeamNeed(gameState, team)
                cache[#cache + 1] = {
                    team = team,
                    avg = TransferManager._getTeamAverageOverall(gameState, team),
                    budget = TransferManager._getAIEffectiveBudget(team),
                    rep = team.reputation or 600,
                    needGroup = needGroup,
                    listedBands = TransferManager._getListedBandsForBuyer(team),
                    affluent = TransferManager._isAITeamAffluent(team),
                }
            end
        end
        return cache
    end

    ---@param teamCache table|nil 由 _buildBuyerTeamCache 预构建的买家快照（可选，用于批量场景加速）
    function TransferManager._findBuyerForPlayer(gameState, player, teamCache)
        -- 高薪低能检查：限制 AI 对工资与能力严重不匹配球员的兴趣
        local pWage = player.wage or 0
        local pOvr = player.overall or 50
        if pWage > 0 and pOvr < 78 then
            local fairWage = 25 * math.exp(0.117 * pOvr)
            if pWage > fairWage * 1.5 then
                local transferTier = DifficultySettings.get().transferTier or 2
                if transferTier <= 2 then
                    return nil
                end
            end
        end

        local candidates = {}
        local expectedCost = player.listedForSale and TransferManager.getSaleAskingPrice(player) or (player.value or 0)
        local pValue035 = expectedCost * 0.35
        local pGroup = _posToGroup()[player.position]
        local pBand = TransferManager._listedBandKey(pOvr)
        local function bandVisible(entry)
            if not entry or not entry.listedBands then return true end
            for _, band in ipairs(entry.listedBands) do
                if band == pBand then return true end
            end
            return false
        end

        if teamCache then
            -- 快路径：复用预构建快照（队均/预算稍有滞后不影响撮合，成交时 _executeAITransfer 仍会再校验）
            for i = 1, #teamCache do
                local entry = teamCache[i]
                local team = entry.team
                if team.id == player.teamId then goto skip end
                if team:isFirstTeamFull() then goto skip end
                if pValue035 > entry.budget then goto skip end
                if pOvr < entry.avg - 15 or pOvr > entry.avg + 20 then goto skip end
                if not bandVisible(entry) then goto skip end
                if pGroup and entry.needGroup and entry.needGroup ~= pGroup
                    and #(team.playerIds or {}) >= 22 and not entry.affluent then
                    goto skip
                end
                candidates[#candidates + 1] = team
                ::skip::
            end
        else
            for _, team in pairs(gameState.teams) do
                if team.id == gameState.playerTeamId then goto skip end
                if team.id == player.teamId then goto skip end
                if team:isFirstTeamFull() then goto skip end
                local budget = TransferManager._getAIEffectiveBudget(team)
                if pValue035 > budget then goto skip end
                local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
                if pOvr < teamAvg - 15 or pOvr > teamAvg + 20 then goto skip end
                candidates[#candidates + 1] = team
                ::skip::
            end
        end

        if #candidates == 0 then return nil end
        return candidates[randInt(1, #candidates)]
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
        return candidates[randInt(1, #candidates)]
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
        if TransferManager.isPlayerRejectingAllOffers(player) then return nil end

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
                return TransferManager._completeLoan(gameState, bid)
            end
        end
        return false, "未找到待处理的租借报价"
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
    function TransferManager._createIncomingBid(gameState, buyerTeam, player, offerAmount, opts)
        TransferManager._ensureData(gameState)
        if TransferManager.isPlayerRejectingAllOffers(player) then return nil end
        opts = opts or {}

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
            isPoachBid = opts.isPoachBid or false,
            currentRound = 0,
            maxRounds = 3,
            mood = 50,
            rounds = {},
        }

        gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
        table.insert(gameState.transfers.bids, bid)

        local YouthManager = require("scripts/systems/youth_manager")
        local isYouthSale = YouthManager.isYouthSquadPlayer(gameState, player)
        local handleHint
        if opts.isPoachBid then
            handleHint = isYouthSale
                and "这是对未挂牌青训球员的主动报价，可前往青训页 / 球员详情合同页处理。"
                or "这是对未挂牌球员的主动报价，可前往阵容页长按该球员处理。"
        else
            handleHint = isYouthSale
                and "前往转会市场「待售」或青训页 / 球员详情合同页处理报价。"
                or "前往转会市场「待售」或阵容页长按该球员处理报价。"
        end

        -- 通知消息
        local title = opts.isPoachBid and "收到挖角报价: " or "收到报价: "
        local body = opts.isPoachBid
            and string.format("%s 希望引进未挂牌的 %s，出价 %s（球员身价 %s）。\n%s",
                buyerTeam.name, player.displayName, fmtMoney(offerAmount), fmtMoney(player.value), handleHint)
            or string.format("%s 对 %s 出价 %s（球员身价 %s）。\n%s",
                buyerTeam.name, player.displayName, fmtMoney(offerAmount), fmtMoney(player.value), handleHint)
        gameState:sendMessage({
            category = "transfer",
            messageType = "incoming_bid_received",
            title = title .. player.displayName,
            body = body,
            priority = "high",
            popup = true,
            data = { bidId = bid.id, playerId = player.id, isPoachBid = opts.isPoachBid or false },
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
                    bid.playerConsiderSaleDays = randInt(1, 2)  -- 卖出方球员考虑1-2天
                end

                for _, otherBid in ipairs(gameState.transfers.bids) do
                    if otherBid.playerId == bid.playerId
                        and not _bidIdsEqual(otherBid.id, bid.id)
                        and otherBid.isIncomingBid then
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
                bid.counterWaitDays = randInt(1, 3) -- AI需要1-3天考虑

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
        if not player or not sellerTeam or not buyerTeam then
            if bid then bid.status = "rejected" end
            return false, "出售交易数据异常"
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
        if not TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id, assignOpts) then
            bid.status = "rejected"
            bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
            return false, "买方一线队已满员，出售无法完成"
        end
        player.listedForSale = false
        player.saleAskingPrice = nil
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

        bid.status = "completed"

        -- 清理同一球员的其他活跃报价（球员已转会，其他报价自动失效）
        TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {
            excludeBidId = bid.id,
            soldToTeamId = buyerTeam.id,
        })

        -- 兼容旧状态集合：确保 incoming bid 也被清理。
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
        return true, nil
    end

    --- 确认出售球员（玩家最终确认，公开API）
    function TransferManager.confirmSale(gameState, bidId)
        TransferManager._ensureData(gameState)
        for _, bid in ipairs(gameState.transfers.bids) do
            if _bidIdsEqual(bid.id, bidId) and bid.status == "awaiting_sale_confirmation" and bid.isIncomingBid then
                bid.responseDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
                return TransferManager._completeIncomingSale(gameState, bid)
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
end
