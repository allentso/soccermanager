-- systems/transfer_manager.lua
-- 转会管理系统 - 处理出价、谈判、完成转会

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")

local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")
local StaffManager = require("scripts/systems/staff_manager")

local TransferManager = {}
require("scripts/systems/transfers/transfer_completion")(TransferManager)
require("scripts/systems/transfers/bid_processor")(TransferManager)
require("scripts/systems/transfers/ai_transfers")(TransferManager)
require("scripts/systems/transfers/incoming_sales")(TransferManager)
require("scripts/systems/transfers/loans")(TransferManager)
require("scripts/systems/transfers/free_agents")(TransferManager)
require("scripts/systems/transfers/misc_clauses")(TransferManager)

local Helpers = require("scripts/systems/transfers/transfer_helpers")
local randInt = Helpers.randInt
local fmtMoney = Helpers.fmtMoney
local SIGN_CONFIRM_TIMEOUT_DAYS = Helpers.SIGN_CONFIRM_TIMEOUT_DAYS
local SIGN_CONFIRM_DEFER_DAYS = Helpers.SIGN_CONFIRM_DEFER_DAYS

------------------------------------------------------

-- 初始化转会数据（如果不存在）
function TransferManager._ensureData(gameState)
    if not gameState.transfers then
        gameState.transfers = {
            bids = {},           -- 活跃报价（日常逻辑只扫这里）
            closedBids = {},     -- 终态报价归档（仅 UI 历史展示 + 冷却期查询）
            history = {},        -- 历史完成的转会
            nextBidId = 1,
        }
    end
    if not gameState.transfers.closedBids then
        gameState.transfers.closedBids = {}
    end
    if not gameState.scoutReports then
        gameState.scoutReports = {}
    end
    if not gameState.scoutDiscoveries then
        gameState.scoutDiscoveries = {}
    end
end

function TransferManager._invalidateListedPlayerCache(gameState)
    if not gameState or not gameState.transfers then return end
    gameState.transfers._listedForSaleIds = nil
    gameState.transfers._listedForLoanIds = nil
    gameState.transfers._listedForSaleMarketIds = nil
    gameState.transfers._listedForSaleMarketWindowKey = nil
    TransferManager._invalidateListedMarketIndex(gameState)
end

function TransferManager._invalidateListedMarketIndex(gameState)
    if not gameState or not gameState.transfers then return end
    gameState.transfers._listedMarketIndex = nil
    gameState.transfers._listedMarketIndexWindowKey = nil
end

--- 存档用：剔除 transfers 上所有 _ 前缀运行时缓存（候选池/挂牌索引/AI 轮转等）。
--- 这些字段含球员对象引用，若写入 JSON 会重复 players 体积（实测可达数 MB）。
function TransferManager.copyTransfersForSave(transfers)
    if not transfers then return nil end
    local out = {}
    for k, v in pairs(transfers) do
        if not (type(k) == "string" and k:sub(1, 1) == "_") then
            out[k] = v
        end
    end
    return out
end

--- 读档/存盘前：就地清除运行时缓存（老档可能已污染）。
function TransferManager.stripRuntimeCaches(gameState)
    if not gameState or not gameState.transfers then return end
    for k in pairs(gameState.transfers) do
        if type(k) == "string" and k:sub(1, 1) == "_" then
            gameState.transfers[k] = nil
        end
    end
end

local function _transferDiagEnabled(gameState)
    return gameState and gameState._transferDiag ~= nil
end

function TransferManager._transferDiagAdd(gameState, key, amount)
    if not _transferDiagEnabled(gameState) then return end
    local d = gameState._transferDiag
    d[key] = (d[key] or 0) + (amount or 1)
end

local function _transferDiagTime(gameState, key, fn, ...)
    if not _transferDiagEnabled(gameState) then
        return fn(...)
    end
    local t0 = os.clock()
    local a, b, c, d, e = fn(...)
    TransferManager._transferDiagAdd(gameState, key, (os.clock() - t0) * 1000)
    return a, b, c, d, e
end

local _TERMINAL_BID_STATUSES = {
    rejected = true,
    cancelled = true,
    completed = true,
    accepted = true,  -- accepted 后很快变 completed，兜底归档
}

--- 每日处理末尾调用：将终态 bid 从 bids 移到 closedBids，保持主数组精简。
--- closedBids 保留最近 MAX_CLOSED_BIDS 条（FIFO），防止多赛季无限膨胀。
local MAX_CLOSED_BIDS = 200
function TransferManager._compactBids(gameState)
    TransferManager._ensureData(gameState)
    local bids = gameState.transfers.bids
    local closedBids = gameState.transfers.closedBids
    local alive = {}
    for _, bid in ipairs(bids) do
        if _TERMINAL_BID_STATUSES[bid.status] then
            closedBids[#closedBids + 1] = bid
        else
            alive[#alive + 1] = bid
        end
    end
    -- 只在有变动时替换，避免无谓 GC 压力
    if #alive < #bids then
        gameState.transfers.bids = alive
        -- FIFO 限流：保留最新的 MAX_CLOSED_BIDS 条
        if #closedBids > MAX_CLOSED_BIDS then
            local trimmed = {}
            for i = #closedBids - MAX_CLOSED_BIDS + 1, #closedBids do
                trimmed[#trimmed + 1] = closedBids[i]
            end
            gameState.transfers.closedBids = trimmed
        end
    end
end

--- 获取挂牌球员快照；缓存只存 id，返回前会校验当前挂牌状态，避免成交后 stale id 参与撮合。
---@param field "listedForSale"|"listedForLoan"
---@return table[] players
function TransferManager._getListedPlayers(gameState, field)
    TransferManager._ensureData(gameState)
    local cacheKey = (field == "listedForLoan") and "_listedForLoanIds" or "_listedForSaleIds"
    local ids = gameState.transfers[cacheKey]
    if not ids then
        ids = {}
        for _, player in pairs(gameState.players or {}) do
            if player[field] and not player.retired then
                ids[#ids + 1] = player.id
            end
        end
        gameState.transfers[cacheKey] = ids
    end

    local players = {}
    local compacted
    for _, pid in ipairs(ids) do
        local player = gameState.players and gameState.players[pid]
        if player and player[field] and not player.retired then
            players[#players + 1] = player
        else
            compacted = true
        end
    end

    if compacted then
        local fresh = {}
        for _, player in ipairs(players) do
            fresh[#fresh + 1] = player.id
        end
        gameState.transfers[cacheKey] = fresh
    end

    return players
end

-- 转会窗口检查（7-8月夏窗，1月冬窗）
function TransferManager.isInTransferWindow(gameState)
    local month = gameState.date.month
    return (month >= 7 and month <= 8) or month == 1
end

local function _transferWindowKeyForDate(date)
    if not date then return nil end
    local month = date.month
    local year = date.year
    if month >= 7 and month <= 8 then
        return "summer_" .. tostring(year)
    elseif month == 1 then
        return "winter_" .. tostring(year)
    end
    return nil
end

--- 当前转会窗标识（夏窗/冬窗各算一个窗期）
---@return string|nil
function TransferManager.getTransferWindowKey(gameState)
    if not gameState or not gameState.date then return nil end
    return _transferWindowKeyForDate(gameState.date)
end

function TransferManager._hasPlayerHistoryInTransferWindow(gameState, playerId, windowKey)
    if not gameState or not gameState.transfers or not gameState.transfers.history then return false end
    if not playerId or not windowKey then return false end

    local transfers = gameState.transfers
    local movedSet = transfers._movedPlayerIdsByWindow
    if not movedSet or transfers._movedPlayerIdsWindowKey ~= windowKey then
        movedSet = {}
        for _, record in ipairs(transfers.history or {}) do
            if _transferWindowKeyForDate(record.date) == windowKey and record.playerId ~= nil then
                movedSet[record.playerId] = true
                movedSet[tostring(record.playerId)] = true
            end
        end
        transfers._movedPlayerIdsByWindow = movedSet
        transfers._movedPlayerIdsWindowKey = windowKey
    end

    return movedSet[playerId] == true or movedSet[tostring(playerId)] == true
end

local AI_LISTED_SALE_DORMANT_AFTER_WINDOWS = 2

local function _transferWindowOrdinal(key)
    if type(key) ~= "string" then return nil end
    local season, year = key:match("^(%a+)_(%d+)$")
    year = tonumber(year)
    if not year then return nil end
    if season == "winter" then return year * 2 end
    if season == "summer" then return year * 2 + 1 end
    return nil
end

local function _transferWindowKeyFromOrdinal(ordinal)
    ordinal = tonumber(ordinal)
    if not ordinal then return nil end
    local year = math.floor(ordinal / 2)
    if ordinal % 2 == 0 then
        return "winter_" .. tostring(year)
    end
    return "summer_" .. tostring(year)
end

local function _isLegacyAIListedLowAttraction(gameState, player)
    if not gameState or not player then return false end
    local team = gameState.teams and gameState.teams[player.teamId]
    if not team then return true end

    if TransferManager._isAIProtectedCore
        and TransferManager._isAIProtectedCore(gameState, team, player) then
        return false
    end

    local ovr = player.overall or 0
    local age = player.getAge and player:getAge(gameState.date and gameState.date.year or 0) or 0
    if age >= 31 and ovr < 72 then return true end

    local target = 26
    local ok, AiSquadPolicy = pcall(require, "scripts/systems/ai_squad_policy")
    if ok and AiSquadPolicy and AiSquadPolicy.getTargetSquadSize then
        target = AiSquadPolicy.getTargetSquadSize(team)
    end
    return #(team.playerIds or {}) > target + 2 and ovr < 70
end

function TransferManager._clearAIListedForSaleMeta(player)
    if not player then return end
    player._aiListedForSaleWindowKey = nil
    player._aiDelistedWindowKey = nil
end

local function _normalizeSaleAskingPrice(askingPrice)
    if askingPrice == nil then return nil end
    local amount = tonumber(askingPrice)
    if not amount or amount <= 0 then return nil end
    return math.max(10000, math.floor(amount / 1000) * 1000)
end

--- 获取玩家主动设置的出售挂牌价；未设置时回落到实时身价。
function TransferManager.getSaleAskingPrice(player)
    if not player then return 0 end
    local askingPrice = _normalizeSaleAskingPrice(player.saleAskingPrice)
    if player.listedForSale and askingPrice then
        return askingPrice
    end
    return math.max(0, math.floor(player.value or 0))
end

function TransferManager.isPlayerRejectingAllOffers(player)
    return player and player.rejectAllOffers == true
end

--- 设置球员报价勿扰：开启后不再生成新的出售/租借报价，并拒绝当前待处理报价
---@return boolean success
---@return string|nil error
---@return table|nil stats { rejected, delistedSale, delistedLoan }
function TransferManager.setPlayerRejectAllOffers(gameState, playerId, rejectAll)
    if not gameState or not playerId then return false, "无效球员" end
    TransferManager._ensureData(gameState)

    local player = gameState.players and gameState.players[playerId]
    if not player then return false, "球员不存在" end

    player.rejectAllOffers = rejectAll and true or nil
    local stats = { rejected = 0, delistedSale = false, delistedLoan = false }

    if rejectAll then
        local date = gameState.date and {
            year = gameState.date.year, month = gameState.date.month, day = gameState.date.day,
        } or nil

        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.playerId == playerId
                and bid.status == "pending"
                and (bid.isIncomingBid or bid.isIncomingLoanBid) then
                bid.status = "rejected"
                bid.rejectedDate = date
                bid.responseDate = date
                stats.rejected = stats.rejected + 1
            end
        end

        if player.listedForSale then
            TransferManager.delistPlayer(gameState, player)
            stats.delistedSale = true
        end
        if player.listedForLoan then
            TransferManager.delistLoan(player)
            stats.delistedLoan = true
        end
    end

    TransferManager._invalidateListedPlayerCache(gameState)
    return true, nil, stats
end

--- 调整已挂牌球员的出售挂牌价。
function TransferManager.setSaleAskingPrice(gameState, player, askingPrice)
    if not gameState or not player then return false, "无效球员" end
    if not player.listedForSale then return false, "球员尚未挂牌" end
    if player.teamId ~= gameState.playerTeamId then return false, "只能调整本队球员挂牌价" end

    local normalized = _normalizeSaleAskingPrice(askingPrice)
    if not normalized then return false, "请输入有效挂牌价" end
    player.saleAskingPrice = normalized
    TransferManager._invalidateListedPlayerCache(gameState)
    return true
end

function TransferManager._markAIListedForSale(gameState, player)
    if not player then return end
    player._aiListedForSaleWindowKey = TransferManager.getTransferWindowKey(gameState)
    player._aiDelistedWindowKey = nil
    TransferManager._transferDiagAdd(gameState, "newlyListed", 1)
end

--- 移除休眠 AI 挂牌，防止挂牌市场长期膨胀；同窗内禁止立即重新挂牌。
---@return number pruned
function TransferManager.pruneDormantAIListings(gameState, opts)
    opts = opts or {}
    if not gameState or not TransferManager.isInTransferWindow(gameState) then return 0 end

    local currentKey = TransferManager.getTransferWindowKey(gameState)
    local pruned = 0
    for _, player in ipairs(TransferManager._getListedPlayers(gameState, "listedForSale")) do
        if player.teamId ~= gameState.playerTeamId
            and TransferManager._isAIListedForSaleDormant(gameState, player) then
            player.listedForSale = false
            player._aiListedForSaleWindowKey = nil
            player._aiDelistedWindowKey = currentKey
            pruned = pruned + 1
        end
    end

    if pruned > 0 then
        TransferManager._invalidateListedPlayerCache(gameState)
    end
    TransferManager._transferDiagAdd(gameState, "dormantPruned", pruned)
    return pruned
end

function TransferManager._isAIListedForSaleDormant(gameState, player)
    if not gameState or not player or not player.listedForSale then return false end
    if player.teamId == gameState.playerTeamId then return false end

    local currentKey = TransferManager.getTransferWindowKey(gameState)
    if not currentKey then return false end

    local listedKey = player._aiListedForSaleWindowKey
    if not listedKey then
        -- 旧存档/旧逻辑遗留的 AI 挂牌做一次性保守迁移：
        -- 默认按已挂满 2 个窗口处理，当前窗仍给一次机会；明显低吸引力冗员当前窗直接休眠。
        local currentOrdinal = _transferWindowOrdinal(currentKey)
        if not currentOrdinal then
            player._aiListedForSaleWindowKey = currentKey
            return false
        end
        local ageWindows = AI_LISTED_SALE_DORMANT_AFTER_WINDOWS
        if _isLegacyAIListedLowAttraction(gameState, player) then
            ageWindows = AI_LISTED_SALE_DORMANT_AFTER_WINDOWS + 1
        end
        player._aiListedForSaleWindowKey = _transferWindowKeyFromOrdinal(currentOrdinal - ageWindows)
            or currentKey
        return ageWindows > AI_LISTED_SALE_DORMANT_AFTER_WINDOWS
    end

    local currentOrdinal = _transferWindowOrdinal(currentKey)
    local listedOrdinal = _transferWindowOrdinal(listedKey)
    if not currentOrdinal or not listedOrdinal then
        player._aiListedForSaleWindowKey = currentKey
        return false
    end

    return (currentOrdinal - listedOrdinal) > AI_LISTED_SALE_DORMANT_AFTER_WINDOWS
end

function TransferManager._getListedForSaleMarketPlayers(gameState)
    TransferManager._ensureData(gameState)
    local windowKey = TransferManager.getTransferWindowKey(gameState) or "no_window"
    local ids = gameState.transfers._listedForSaleMarketIds
    if not ids or gameState.transfers._listedForSaleMarketWindowKey ~= windowKey then
        ids = {}
        for _, player in ipairs(TransferManager._getListedPlayers(gameState, "listedForSale")) do
            if player.teamId == gameState.playerTeamId
                or not TransferManager._isAIListedForSaleDormant(gameState, player) then
                ids[#ids + 1] = player.id
            end
        end
        gameState.transfers._listedForSaleMarketIds = ids
        gameState.transfers._listedForSaleMarketWindowKey = windowKey
    end

    local players = {}
    local compacted
    for _, pid in ipairs(ids) do
        local player = gameState.players and gameState.players[pid]
        if player and player.listedForSale and not player.retired
            and (player.teamId == gameState.playerTeamId
                or not TransferManager._isAIListedForSaleDormant(gameState, player)) then
            players[#players + 1] = player
        else
            compacted = true
        end
    end

    if compacted then
        local fresh = {}
        for _, player in ipairs(players) do fresh[#fresh + 1] = player.id end
        gameState.transfers._listedForSaleMarketIds = fresh
    end

    return players
end

local LISTED_BAND_ELITE_MIN = 75
local LISTED_BAND_MID_MIN = 58
local LISTED_BAND_KEYS = { "elite", "mid", "low" }

function TransferManager._listedBandKey(ovr)
    ovr = ovr or 50
    if ovr >= LISTED_BAND_ELITE_MIN then return "elite" end
    if ovr >= LISTED_BAND_MID_MIN then return "mid" end
    return "low"
end

--- 挂牌市场按位置组 + OVR band 索引（窗口级缓存，排除休眠 AI 挂牌）
function TransferManager._buildListedMarketIndex(gameState)
    TransferManager._ensureData(gameState)
    local transfers = gameState.transfers
    local windowKey = TransferManager.getTransferWindowKey(gameState) or "no_window"
    if transfers._listedMarketIndexWindowKey == windowKey and transfers._listedMarketIndex then
        return transfers._listedMarketIndex
    end

    local p2g = Helpers.posToGroup()
    local function newBandBuckets()
        return { elite = {}, mid = {}, low = {} }
    end
    local index = {
        flat = {},
        byGroup = { GK = {}, DEF = {}, MID = {}, FWD = {} },
        byGroupBand = {
            GK = newBandBuckets(), DEF = newBandBuckets(),
            MID = newBandBuckets(), FWD = newBandBuckets(),
        },
    }

    for _, player in ipairs(TransferManager._getListedForSaleMarketPlayers(gameState)) do
        index.flat[#index.flat + 1] = player
        local g = p2g[player.position]
        if g then
            index.byGroup[g][#index.byGroup[g] + 1] = player
            local band = TransferManager._listedBandKey(player.overall or 50)
            local bucket = index.byGroupBand[g][band]
            bucket[#bucket + 1] = player
        end
    end

    transfers._listedMarketIndex = index
    transfers._listedMarketIndexWindowKey = windowKey
    return index
end

function TransferManager._getListedBandsForBuyer(team)
    local rep = team and team.reputation or 600
    if rep >= 800 then return LISTED_BAND_KEYS end
    if rep >= 650 then return { "mid", "low" } end
    return { "low", "mid" }
end

--- 球员在本窗期是否已完成过转会/租借/签约
---@return boolean blocked
---@return string|nil errorMsg
function TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
    local player = gameState.players[playerId]
    if not player then return true, nil end
    local key = TransferManager.getTransferWindowKey(gameState)
    if not key then return true, nil end
    if player._transferWindowKey == key
        or TransferManager._hasPlayerHistoryInTransferWindow(gameState, playerId, key) then
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
        if gameState.transfers
            and gameState.transfers._movedPlayerIdsWindowKey == key
            and gameState.transfers._movedPlayerIdsByWindow then
            gameState.transfers._movedPlayerIdsByWindow[playerId] = true
            gameState.transfers._movedPlayerIdsByWindow[tostring(playerId)] = true
        end
    end
end

--- 球员是否已在当前转会窗完成过转会/租借/签约
function TransferManager.hasMovedInCurrentWindow(gameState, playerId)
    local player = gameState.players[playerId]
    if not player then return false end
    local key = TransferManager.getTransferWindowKey(gameState)
    if not key then return false end
    return player._transferWindowKey == key
        or TransferManager._hasPlayerHistoryInTransferWindow(gameState, playerId, key)
end

--- 获取转会窗口关闭日期
--- @return table|nil {year, month, day} 当前窗口关闭日期，不在窗口期返回nil
function TransferManager.getWindowCloseDate(gameState)
    local month = gameState.date.month
    local year = gameState.date.year
    if month >= 7 and month <= 8 then
        return { year = year, month = 8, day = 31 }  -- 夏窗8月31日关闭
    elseif month == 1 then
        return { year = year, month = 1, day = 31 }  -- 冬窗1月31日关闭
    end
    return nil
end

--- 获取下一个转会窗口开启日期
--- @return table|nil {year, month, day} 已在窗口期内返回 nil
function TransferManager.getNextWindowOpenDate(gameState)
    if not gameState or not gameState.date then return nil end
    if TransferManager.isInTransferWindow(gameState) then return nil end
    local month = gameState.date.month
    local year = gameState.date.year
    if month >= 2 and month <= 6 then
        return { year = year, month = 7, day = 1 }
    elseif month >= 9 and month <= 12 then
        return { year = year + 1, month = 1, day = 1 }
    end
    return nil
end

--- 计算距离下一个转会窗口开启的天数（已在窗口内返回 0）
--- @return number
function TransferManager.daysUntilWindowOpen(gameState)
    local openDate = TransferManager.getNextWindowOpenDate(gameState)
    if not openDate then return 0 end
    return math.max(0, TransferManager._daysBetween(gameState.date, openDate))
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
        return false, "当前不在转会窗口期（夏窗7-8月/冬窗1月），无法进行俱乐部间交易"
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

    -- 检查 bids + closedBids 中的拒绝记录
    local bidSources = { gameState.transfers.bids, gameState.transfers.closedBids }
    for _, source in ipairs(bidSources) do
        if source then
            for _, bid in ipairs(source) do
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
            scoutAbility = scoutAbility + (s.attributes and s.attributes.scouting or 10)
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
    local avgScouting = math.floor(scoutAbility / scoutCount)
    local scoutBonus = StaffManager.getScoutingBonus(gameState, team.id)
    local accuracy = math.min(0.97, 0.50 + avgScouting * 0.02 + scoutBonus)
    local error_range = math.max(1, math.floor((1.0 - accuracy) * 20))

    for _ = 1, discoverCount do
        local idx = randInt(1, #allPlayers)
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
            -- 球探评估潜力（误差与球探准确度挂钩）
            local scoutedPotential = (player.actualPotential or player.potential) + randInt(-error_range, error_range)
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
-- 辅助函数
------------------------------------------------------

function TransferManager._daysBetween(date1, date2)
    -- 简化计算：假设每月30天
    local d1 = date1.year * 365 + date1.month * 30 + date1.day
    local d2 = date2.year * 365 + date2.month * 30 + date2.day
    return d2 - d1
end

function TransferManager._addDays(date, days)
    local y, m, d = date.year, date.month, date.day + (days or 0)
    while d > 30 do
        d = d - 30
        m = m + 1
    end
    while m > 12 do
        m = m - 12
        y = y + 1
    end
    return { year = y, month = m, day = d }
end

function TransferManager._getSignConfirmTimeoutDays(bid)
    return SIGN_CONFIRM_TIMEOUT_DAYS + (bid and bid.confirmDeferUsed and SIGN_CONFIRM_DEFER_DAYS or 0)
end

function TransferManager._processSignConfirmDeferExpiry(gameState, activeBids)
    for _, bid in ipairs(activeBids) do
        if bid.status == "awaiting_confirmation"
            and bid.buyerTeamId == gameState.playerTeamId
            and bid.confirmDeferredUntil
            and not TransferManager.isSignConfirmDeferred(bid, gameState)
            and not bid.confirmDeferExpiryNotified then
            bid.confirmDeferExpiryNotified = true
            bid.confirmDeferredUntil = nil
            local player = gameState.players[bid.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "推迟期已结束",
                body = string.format("%s 的签入决定推迟期已结束，请尽快确认签入或放弃交易。",
                    player and player.displayName or "该球员"),
                priority = "high",
            })
        end
    end
    if not gameState.transfers.freeAgentNegos then return end
    for _, nego in ipairs(gameState.transfers.freeAgentNegos) do
        if nego.status == "awaiting_confirmation"
            and nego.teamId == gameState.playerTeamId
            and nego.confirmDeferredUntil
            and not TransferManager.isFreeAgentSignDeferred(nego, gameState)
            and not nego.confirmDeferExpiryNotified then
            nego.confirmDeferExpiryNotified = true
            nego.confirmDeferredUntil = nil
            local player = gameState.players[nego.playerId]
            gameState:sendMessage({
                category = "transfer",
                title = "推迟期已结束",
                body = string.format("自由球员 %s 的签入决定推迟期已结束，请尽快确认签入或放弃签约。",
                    player and player.displayName or "该球员"),
                priority = "high",
            })
        end
    end
end

--- 队均 OVR 缓存代次：在每个转会处理 pass 开始时递增（覆盖跨日成长/伤退），
--- 并在 _assignPlayerToTeam 阵容变更后递增（覆盖 pass 内成交）。
--- 同一代次内同队的重复查询直接命中缓存，避免 _aiListPlayersForSale 等
--- 逐球员循环重复全队扫描造成的卡顿。
TransferManager._teamOvrGen = TransferManager._teamOvrGen or 0
function TransferManager._bumpTeamOvrGen()
    TransferManager._teamOvrGen = TransferManager._teamOvrGen + 1
end

function TransferManager._getTeamAverageOverall(gameState, team)
    local gen = TransferManager._teamOvrGen
    if team._ovrCacheGen == gen and team._ovrCacheVal then
        return team._ovrCacheVal
    end
    local total = 0
    local count = 0
    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            total = total + player.overall
            count = count + 1
        end
    end
    local avg = count > 0 and math.floor(total / count) or 50
    team._ovrCacheGen = gen
    team._ovrCacheVal = avg
    return avg
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

    local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, playerId)
    if not moveOk then return nil, moveErr end

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
        maxRounds = randInt(2, 4),
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

    local sellerOk, sellerErr = TransferManager._validateBidSeller(gameState, bid)
    if not sellerOk then
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        gameState:sendMessage({
            category = "transfer",
            title = "推销失败",
            body = sellerErr,
            priority = "normal",
        })
        return
    end

    local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
    if not moveOk then
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        gameState:sendMessage({
            category = "transfer",
            title = "推销失败",
            body = moveErr,
            priority = "normal",
        })
        return
    end

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

    local assignOpts = TransferManager.isInTransferWindow(gameState) and { allowOverCap = true } or nil
    if not TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id, assignOpts) then
        bid.status = "rejected"
        bid.rejectedDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        gameState:sendMessage({
            category = "transfer",
            title = "推销失败",
            body = "买方一线队已满员，推销无法完成。",
            priority = "normal",
        })
        return
    end

    bid.status = "completed"

    TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)

    player.listedForSale = false
    player.listedForLoan = false
    player.saleAskingPrice = nil
    TransferManager._clearAIListedForSaleMeta(player)
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

    TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {
        excludeBidId = bid.id,
        soldToTeamId = bid.buyerTeamId,
    })
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
-- 修改 processDailyBids 以支持推销报价
------------------------------------------------------

------------------------------------------------------
-- AI 报价处理（每天调用）
------------------------------------------------------
function TransferManager.processDailyBids(gameState)
    TransferManager._ensureData(gameState)
    TransferManager._bumpTeamOvrGen()  -- 新 pass：刷新队均缓存（覆盖跨日成长/成交）

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
                body = string.format("转会窗口已关闭，%d 笔未完成的俱乐部间交易已自动取消。",
                    cancelledCount),
                priority = "normal",
            })
        end
        TransferManager.clearLoanListingsOutsideWindow(gameState)
        -- 关窗收敛：AI 窗口期"卖弱换强"可能超员(>30)，关窗强制释放最弱者回 30
        TransferManager.enforceAISquadCap(gameState)
        -- 窗口关闭后仍然处理自由球员相关逻辑，但俱乐部间交易不再推进
        -- 下方的处理循环只作用于仍有效的 bid，已 cancelled 的会跳过
    end

    -- 挂牌撮合已统一由 processDailyAITransferSlice → _processWeeklyTransferMarketPulse 处理，
    -- 不再在此重复调用（省一次 incIdx + buyerTeamCache 构建）。
    if TransferManager.isInTransferWindow(gameState) then
        -- 玩家阵容人数阈值提醒（28/30/33）
        TransferManager._notifyPlayerSquadThresholds(gameState)
    end

    -- 存档修复：降频为窗口首日 + 每周一执行（正常流程不产生 stale 数据，无需每天跑）
    local needRepair = (gameState.date.day == 1) or (gameState.dayOfWeek == 1)
        or not gameState.transfers._repairDoneThisWindow
    if needRepair then
        TransferManager.repairIncomingSaleBids(gameState)
        TransferManager.repairStaleFreeAgentNegos(gameState, { silent = true })
        TransferManager.repairStaleTransferSignBids(gameState, { silent = true })
        gameState.transfers._repairDoneThisWindow = true
    end

    -- bids 历史会跨窗口/赛季累积；每日生命周期只关心仍可能推进的报价。
    -- 后续多段处理复用同一 activeBids，避免每天反复扫 completed/rejected/cancelled 历史。
    local dailyActiveStatuses = {
        pending = true,
        negotiating = true,
        player_considering = true,
        fee_agreed = true,
        awaiting_confirmation = true,
        player_considering_sale = true,
        counter_pending = true,
        awaiting_sale_confirmation = true,
    }
    local activeBids = {}
    for _, bid in ipairs(gameState.transfers.bids) do
        if dailyActiveStatuses[bid.status] then
            activeBids[#activeBids + 1] = bid
        end
    end

    for _, bid in ipairs(activeBids) do
        if bid.status == "pending" then
            -- 推销报价走不同路径
            if bid.isPushSale then
                local refDate = bid.responseDate or bid.date
                local daysSince = TransferManager._daysBetween(refDate, gameState.date)
                if daysSince >= randInt(1, 3) then
                    TransferManager._processPushSaleResponse(gameState, bid)
                end
            else
                -- 原有逻辑: 普通报价
                local refDate = bid.responseDate or bid.date
                local daysSince = TransferManager._daysBetween(refDate, gameState.date)
                local waitDays = (bid.currentRound or 0) > 0 and 1 or randInt(1, 3)
                if daysSince >= waitDays then
                    -- 检查解约金
                    local player = gameState.players[bid.playerId]
                    if player and TransferManager._checkReleaseClause(player, bid.amount) then
                        TransferManager._acceptBid(gameState, bid)
                    elseif bid.type == "loan" and not bid.isIncomingLoanBid then
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
    for _, bid in ipairs(activeBids) do
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
    for _, bid in ipairs(activeBids) do
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

    -- 推迟期结束提醒
    TransferManager._processSignConfirmDeferExpiry(gameState, activeBids)

    -- awaiting_confirmation 状态超时处理（5天未确认则取消，推迟后延长3天）
    for _, bid in ipairs(activeBids) do
        if bid.status == "awaiting_confirmation" then
            if TransferManager.isSignConfirmDeferred(bid, gameState) then
                goto continueAwaitingConfirm
            end
            local refDate = bid.confirmDate or bid.feeAgreedDate
            if not refDate then goto continueAwaitingConfirm end
            local daysSinceConfirm = TransferManager._daysBetween(refDate, gameState.date)
            if daysSinceConfirm >= TransferManager._getSignConfirmTimeoutDays(bid) then
                local player = gameState.players[bid.playerId]
                TransferManager._rejectBid(gameState, bid,
                    string.format("%s 等待你的答复太久，决定不再等待。",
                        player and player.displayName or "该球员"))
            end
            ::continueAwaitingConfirm::
        end
    end

    -- player_considering_sale 状态：被出售球员考虑期结束后判断是否同意
    for _, bid in ipairs(activeBids) do
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
    for _, bid in ipairs(activeBids) do
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
    for _, bid in ipairs(activeBids) do
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
    for _, bid in ipairs(activeBids) do
        if bid.status == "counter_pending" and bid.isIncomingBid and bid.counterDate then
            local daysSince = TransferManager._daysBetween(bid.counterDate, gameState.date)
            if daysSince >= (bid.counterWaitDays or 2) then
                TransferManager._processCounterResponse(gameState, bid)
            end
        end
    end

    -- awaiting_sale_confirmation 状态超时处理（出售方向，5天未确认则买方撤回）
    for _, bid in ipairs(activeBids) do
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

    -- 日末归档：将终态 bid 移出主数组，保持次日扫描量精简
    TransferManager._compactBids(gameState)
end

function TransferManager._processLoanBidResponse(gameState, bid)
    -- 兼容旧测试/存档：走完整 AI 租借谈判流程
    TransferManager._processAILoanResponse(gameState, bid)
end

--- 获取所有活跃报价
---@param gameState table
---@return table[]
function TransferManager.getActiveBids(gameState)
    TransferManager._ensureData(gameState)
    local activeBids = {}
    local activeStatuses = {
        pending = true,
        negotiating = true,
        counter_pending = true,
        fee_agreed = true,
        player_considering = true,
        awaiting_confirmation = true,
        awaiting_sale_confirmation = true,
        player_considering_sale = true,
    }
    for _, bid in ipairs(gameState.transfers.bids or {}) do
        if activeStatuses[bid.status] then
            local player = gameState.players[bid.playerId]
            local sellerTeamId = bid.sellerTeamId or bid.fromTeamId
            if player and (not sellerTeamId or player.teamId == sellerTeamId) then
                table.insert(activeBids, bid)
            end
        end
    end
    return activeBids
end

--- 挂牌出售球员（一线队或青训队已签入球员）
---@param gameState table
---@param player table
---@param askingPrice number|nil 玩家手动设置的挂牌价；nil 时按实时身价作为默认要价
---@return boolean success
---@return string|nil error
function TransferManager.listForSale(gameState, player, askingPrice)
    if not gameState or not player then return false, "无效球员" end
    if TransferManager.isPlayerRejectingAllOffers(player) then return false, "该球员已设置拒绝所有报价" end

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

    local normalizedAskingPrice
    if askingPrice ~= nil then
        normalizedAskingPrice = _normalizeSaleAskingPrice(askingPrice)
        if not normalizedAskingPrice then return false, "请输入有效挂牌价" end
    end

    local moveOk, moveErr = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
    if not moveOk then return false, moveErr end

    local windowOk, windowErr = TransferManager._checkTransferWindow(gameState)
    if not windowOk then return false, windowErr end

    player.listedForSale = true
    player.listedForLoan = false
    player.saleAskingPrice = normalizedAskingPrice
    TransferManager._clearAIListedForSaleMeta(player)
    TransferManager._invalidateListedPlayerCache(gameState)
    local priceText = fmtMoney(TransferManager.getSaleAskingPrice(player))
    gameState:sendMessage({
        category = "transfer",
        title = player.displayName .. " 已挂牌",
        body = isYouthSquad
            and string.format("%s 已被挂牌出售（青训），挂牌价 %s，等待买家报价。", player.displayName, priceText)
            or string.format("%s 已被挂牌出售，挂牌价 %s，等待买家报价。", player.displayName, priceText),
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
    player.saleAskingPrice = nil
    TransferManager._clearAIListedForSaleMeta(player)
    if gameState then TransferManager._invalidateListedPlayerCache(gameState) end

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
