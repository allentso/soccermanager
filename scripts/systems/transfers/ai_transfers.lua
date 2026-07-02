-- systems/transfers/ai_transfers.lua
-- AI 自动转会调度、候选池、执行，从 transfer_manager.lua 拆分。

local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")
local StaffManager = require("scripts/systems/staff_manager")
local Helpers = require("scripts/systems/transfers/transfer_helpers")
local randInt = Helpers.randInt
local fmtMoney = Helpers.fmtMoney
local _posToGroup = Helpers.posToGroup

return function(TransferManager)
    local function _transferDiagTime(gameState, key, fn, ...)
        return Helpers.transferDiagTime(TransferManager, gameState, key, fn, ...)
    end
    ------------------------------------------------------
    -- AI 主动出价系统
    ------------------------------------------------------

    local AI_TRANSFER_BATCH_SIZE = 40
    local AI_TRANSFER_PASSES_PER_WEEK = 1
    local AI_TRANSFER_BASELINE_PASSES_PER_WEEK = 2
    local AI_DAILY_LISTED_MATCH_SCALE = 0.5
    local AI_LOAN_LIST_MAX_GLOBAL = 5
    local AI_INCOMING_SALE_MAX_COMPETING_BIDS = 3
    local AI_TRANSFER_WEIGHT_HIGH = 1.0
    local AI_TRANSFER_WEIGHT_MID = 0.75
    local AI_TRANSFER_WEIGHT_LOW = 0.50

    local function _getAITransferLoadScale()
        return AI_TRANSFER_PASSES_PER_WEEK / AI_TRANSFER_BASELINE_PASSES_PER_WEEK
    end

    --- 按联赛 tier / 声望决定 AI 主动引援周频权重（次级队降频，豪门保持全频）
    function TransferManager._getAITransferWeightForTeam(gameState, team)
        if not team then return AI_TRANSFER_WEIGHT_LOW end
        local rep = team.reputation or 600
        local RealDataLoader = require("scripts/data/real_data_loader")
        local _, leagueKey = RealDataLoader.getTeamLeague(gameState, team.id)
        local league = gameState.leagues and leagueKey and gameState.leagues[leagueKey]
        local tier = league and league.tier or 1
        if tier >= 2 then return AI_TRANSFER_WEIGHT_LOW end
        if rep >= 800 then return AI_TRANSFER_WEIGHT_HIGH end
        if rep >= 650 then return AI_TRANSFER_WEIGHT_MID end
        return AI_TRANSFER_WEIGHT_LOW
    end

    local function _splitAITransferTeamsByWeight(gameState, teams)
        local high, mid, low = {}, {}, {}
        for _, team in ipairs(teams) do
            local weight = TransferManager._getAITransferWeightForTeam(gameState, team)
            if weight >= AI_TRANSFER_WEIGHT_HIGH then
                high[#high + 1] = team
            elseif weight >= AI_TRANSFER_WEIGHT_MID then
                mid[#mid + 1] = team
            else
                low[#low + 1] = team
            end
        end
        return high, mid, low
    end

    local function _pickRotatingBatch(teams, cursor, batchSize)
        local total = #teams
        if total == 0 or batchSize <= 0 then return {}, cursor end
        batchSize = math.min(total, batchSize)
        if cursor < 1 or cursor > total then cursor = 1 end
        local batch = {}
        for i = 0, batchSize - 1 do
            local idx = ((cursor + i - 1) % total) + 1
            batch[#batch + 1] = teams[idx]
        end
        return batch, ((cursor + batchSize - 1) % total) + 1
    end

    function TransferManager._getDailyQuota(gameState, totalPerPass, passesPerWeek)
        local weeklyQuota = math.floor(((tonumber(totalPerPass) or 0) * (passesPerWeek or AI_TRANSFER_PASSES_PER_WEEK)) + 0.5)
        local base = math.floor(weeklyQuota / 7)
        local remainder = weeklyQuota % 7
        local dow = tonumber(gameState and gameState.dayOfWeek) or 1
        return base + ((dow >= 1 and dow <= remainder) and 1 or 0)
    end

    function TransferManager._getAITransferDailyQuota(gameState, teams)
        teams = teams or TransferManager._getAITransferOrderedTeams(gameState)
        local high, mid, low = _splitAITransferTeamsByWeight(gameState, teams)
        return TransferManager._getDailyQuota(gameState, #high, AI_TRANSFER_WEIGHT_HIGH)
            + TransferManager._getDailyQuota(gameState, #mid, AI_TRANSFER_WEIGHT_MID)
            + TransferManager._getDailyQuota(gameState, #low, AI_TRANSFER_WEIGHT_LOW)
    end

    function TransferManager._getAITransferOrderedTeams(gameState)
        TransferManager._ensureData(gameState)
        local teamMap = {}
        local ids = {}
        for _, team in pairs(gameState.teams or {}) do
            if team.id ~= gameState.playerTeamId then
                teamMap[team.id] = team
                ids[#ids + 1] = team.id
            end
        end
        table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)

        local key = TransferManager.getTransferWindowKey(gameState) or "no_window"
        local order = gameState.transfers._aiTransferTeamOrder
        local valid = gameState.transfers._aiTransferOrderWindowKey == key
            and order
            and #order == #ids

        if valid then
            for _, id in ipairs(order) do
                if not teamMap[id] then
                    valid = false
                    break
                end
            end
        end

        if not valid then
            order = {}
            for i, id in ipairs(ids) do order[i] = id end
            -- 每个转会窗首次进入时洗牌一次；窗口内保持顺序稳定，避免每日随机抖动。
            for i = #order, 2, -1 do
                local j = randInt(1, i)
                order[i], order[j] = order[j], order[i]
            end
            gameState.transfers._aiTransferTeamOrder = order
            gameState.transfers._aiTransferOrderWindowKey = key
            gameState.transfers._aiTransferCursor = 1
        end

        local teams = {}
        for _, id in ipairs(order or {}) do
            local team = teamMap[id]
            if team then teams[#teams + 1] = team end
        end
        return teams
    end

    function TransferManager._getAITransferBatchTeams(gameState, opts)
        opts = opts or {}
        local teams = TransferManager._getAITransferOrderedTeams(gameState)

        local total = #teams
        if total == 0 then
            gameState.transfers._aiTransferCursor = nil
            return {}
        end
        if total <= AI_TRANSFER_BATCH_SIZE and not opts.daily then
            gameState.transfers._aiTransferCursor = nil
            return teams
        end

        if opts.daily then
            local high, mid, low = _splitAITransferTeamsByWeight(gameState, teams)
            local batch = {}
            local hq = TransferManager._getDailyQuota(gameState, #high, AI_TRANSFER_WEIGHT_HIGH)
            local mq = TransferManager._getDailyQuota(gameState, #mid, AI_TRANSFER_WEIGHT_MID)
            local lq = TransferManager._getDailyQuota(gameState, #low, AI_TRANSFER_WEIGHT_LOW)
            local part
            part, gameState.transfers._aiTransferCursorHigh =
                _pickRotatingBatch(high, tonumber(gameState.transfers._aiTransferCursorHigh) or 1, hq)
            for _, team in ipairs(part) do batch[#batch + 1] = team end
            part, gameState.transfers._aiTransferCursorMid =
                _pickRotatingBatch(mid, tonumber(gameState.transfers._aiTransferCursorMid) or 1, mq)
            for _, team in ipairs(part) do batch[#batch + 1] = team end
            part, gameState.transfers._aiTransferCursorLow =
                _pickRotatingBatch(low, tonumber(gameState.transfers._aiTransferCursorLow) or 1, lq)
            for _, team in ipairs(part) do batch[#batch + 1] = team end
            TransferManager._transferDiagAdd(gameState, "aiTeamsProcessed", #batch)
            return batch
        end

        local cursor = tonumber(gameState.transfers._aiTransferCursor) or 1
        if cursor < 1 or cursor > total then cursor = 1 end

        local batchSize = AI_TRANSFER_BATCH_SIZE
        local batch = {}
        for i = 0, batchSize - 1 do
            local idx = ((cursor + i - 1) % total) + 1
            batch[#batch + 1] = teams[idx]
        end
        gameState.transfers._aiTransferCursor = ((cursor + batchSize - 1) % total) + 1
        return batch
    end

    function TransferManager._processAITransferTeamBatch(gameState, batchTeams)
        if not batchTeams or #batchTeams == 0 then return end
        -- 预分桶可转会球员（本次 pass 共用），避免每队全表扫描造成的卡顿
        local candidatePool = TransferManager._buildTransferCandidatePool(gameState)
        -- 预建「玩家球队有活跃报价的球员」集合（本次 pass 共用），供 _findTransferTarget O(1) 查表，
        -- 避免对每个候选都 O(bids) 全扫 hasActiveBidOnPlayer（bids 累积时的二次方退化）
        local playerBidSet = TransferManager._buildPlayerActiveBidSet(gameState, gameState.playerTeamId)

        -- 大存档按批轮转处理 AI 主动引援，避免周一/周四所有 AI 队集中制造尖峰。
        for _, team in ipairs(batchTeams) do
            if not TransferManager._shouldAITryTransfer(gameState, team) then goto continue end

            -- 评估需求：包括"补缺"和"升级"两种动机
            local need, upgradeMode = TransferManager._assessTeamNeed(gameState, team)
            if not need then goto continue end

            -- 寻找合适目标（豪门有机会进入重磅模式；本窗未达自由签约上限时纳入自由球员）
            local blockbuster = TransferManager._shouldAIBlockbusterMode(gameState, team)
            local allowFreeAgents = TransferManager._canAISignFreeAgent(gameState, team)
            local target = TransferManager._findTransferTarget(gameState, team, need, upgradeMode, {
                blockbuster = blockbuster,
                allowFreeAgents = allowFreeAgents,
                pool = candidatePool,
                playerBidSet = playerBidSet,
            })
            if not target then goto continue end

            if target.teamId == nil then
                -- 自由球员：走签约路径（无转会费，受每窗上限约束）
                TransferManager._executeAIFreeSign(gameState, team, target)
            else
                -- AI 发起付费转会（升级动机允许满员时"卖弱换强"先买后卖）
                local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
                TransferManager._executeAITransfer(gameState, team, target, {
                    upgradeMode = upgradeMode,
                    blockbuster = blockbuster,
                    teamAvg = teamAvg,
                    sellToBuy = upgradeMode,
                })
            end

            ::continue::
        end
    end

    function TransferManager._processPlayerListedLoanOffers(gameState, opts)
        opts = opts or {}
        -- 额外：处理外租挂牌球员（AI主动租借玩家挂牌外租的球员）
        local MAX_INCOMING_LOAN_BIDS = 2
        local attractChance = opts.attractChance or 0.70
        for _, player in ipairs(TransferManager._getListedPlayers(gameState, "listedForLoan")) do
            if player.teamId ~= gameState.playerTeamId then goto skipLoanPlayer end  -- 只处理玩家球队的外租挂牌
            if TransferManager.isPlayerRejectingAllOffers(player) then goto skipLoanPlayer end
            -- 检查已有的租借报价数量
            local existingLoanBids = TransferManager.getIncomingLoanBidsForPlayer(gameState, player.id)
            if #existingLoanBids >= MAX_INCOMING_LOAN_BIDS then goto skipLoanPlayer end
            if Random() > attractChance then goto skipLoanPlayer end

            local loanBuyer = TransferManager._findLoanBuyerForPlayer(gameState, player)
            if loanBuyer then
                if not TransferManager.hasPendingIncomingLoanBid(gameState, player.id, loanBuyer.id) then
                    TransferManager._createIncomingLoanBid(gameState, loanBuyer, player)
                end
            end
            ::skipLoanPlayer::
        end
    end

    function TransferManager._processWeeklyTransferMarketPulse(gameState, opts)
        opts = opts or {}
        -- 挂牌出售：每日在 processDailyBids 中推进；此处保留额外市场脉冲
        TransferManager._processListedPlayerOffers(gameState, {
            playerAttractChance = opts.playerAttractChance or 0.80,
            aiAttractChance = opts.aiAttractChance or 0.30,
            maxAIAttempts = opts.maxAIAttempts or 120,
        })
        TransferManager._processPlayerListedLoanOffers(gameState, {
            attractChance = opts.loanAttractChance or 0.70,
        })
    end

    local function _isTransferWindowMonth(gameState)
        local month = gameState.date and gameState.date.month
        -- AI 主动转会从 7 月开始，避免 6 月新赛季/国际大赛期间过早启动重负载市场模拟。
        -- 玩家与 AI 的夏窗月份统一为 7-8 月，冬窗为 1 月。
        return (month and month >= 7 and month <= 8) or month == 1
    end

    --- AI 球队主动寻找转会目标（兼容测试/诊断：一次 pass，最多 40 队；小世界全量）
    function TransferManager.processAITransfers(gameState)
        TransferManager._ensureData(gameState)
        TransferManager._bumpTeamOvrGen()  -- 新 pass：刷新队均缓存（覆盖跨日成长/成交）
        if not _isTransferWindowMonth(gameState) then return end

        TransferManager.pruneDormantAIListings(gameState)
        -- AI主动挂牌多余球员（增加市场供给）
        TransferManager._aiListPlayersForSale(gameState)
        -- AI 挂牌符合画像的年轻/缺勤球员外租（仅转会窗）
        TransferManager._aiListPlayersForLoan(gameState)

        local batchTeams = TransferManager._getAITransferBatchTeams(gameState)
        TransferManager._processAITransferTeamBatch(gameState, batchTeams)
        TransferManager._processWeeklyTransferMarketPulse(gameState)
    end

    --- 真实日程推进使用：把原先每周两次 AI 主动引援摊到每天，降低周一/周四尖峰。
    function TransferManager.processDailyAITransferSlice(gameState)
        TransferManager._ensureData(gameState)
        TransferManager._bumpTeamOvrGen()
        if not _isTransferWindowMonth(gameState) then return end

        local batchTeams = TransferManager._getAITransferBatchTeams(gameState, { daily = true })

        -- AI 挂牌改为周频：窗口首日（月初）全量 + 每周一增量，避免每天排序开销
        local isWindowFirstDay = (gameState.date.day == 1)
        local isMonday = (gameState.dayOfWeek == 1)
        if isWindowFirstDay or isMonday then
            _transferDiagTime(gameState, "pruneDormantMs", TransferManager.pruneDormantAIListings, gameState)
            _transferDiagTime(gameState, "listSaleMs", TransferManager._aiListPlayersForSale, gameState, { teams = isWindowFirstDay and nil or batchTeams })
            _transferDiagTime(gameState, "listLoanMs", TransferManager._aiListPlayersForLoan, gameState, {
                teams = isWindowFirstDay and nil or batchTeams,
                maxGlobal = AI_LOAN_LIST_MAX_GLOBAL,
            })
        end
        _transferDiagTime(gameState, "marketPulseMs", TransferManager._processWeeklyTransferMarketPulse, gameState, {
            -- playerAttractChance 提高到 0.40：合并了原 processDailyBids 中的 0.35 概率入口
            playerAttractChance = 0.40,
            aiAttractChance = 0.30 * AI_TRANSFER_PASSES_PER_WEEK / 7,
            maxAIAttempts = TransferManager._getDailyQuota(gameState, 120, AI_TRANSFER_PASSES_PER_WEEK),
            loanAttractChance = 0.70 * AI_TRANSFER_PASSES_PER_WEEK / 7,
        })
        _transferDiagTime(gameState, "activeTransferMs", TransferManager._processAITransferTeamBatch, gameState, batchTeams)
    end

    --- 挂牌球员每日/每周吸引 AI 买家（冬窗仅 1 月，需每日推进）
    ---@param opts table|nil { playerAttractChance: number, aiAttractChance: number, maxAIAttempts: number }
    function TransferManager._processListedPlayerOffers(gameState, opts)
        if not TransferManager.isInTransferWindow(gameState) then return end

        opts = opts or {}
        local playerAttract = opts.playerAttractChance or 0.35
        local aiAttract = opts.aiAttractChance or 0.15
        local maxAIAttempts = opts.maxAIAttempts

        -- 预建 incoming 报价索引（playerId -> {n, awaiting, buyers}），一次 O(bids) 遍历。
        -- 替代循环内对每个挂牌球员各 3 次 O(bids) 全扫（_hasAwaitingSaleConfirmation /
        -- getIncomingBidsForPlayer / hasPendingIncomingBid）——这是 bids 累积时挂牌撮合
        -- 退化为 O(挂牌×bids) 二次方的主因。状态集合与上述三函数保持一致。
        local INCOMING_ACTIVE = {
            pending = true, counter_pending = true,
            awaiting_sale_confirmation = true, player_considering_sale = true,
        }
        local incIdx = {}
        for _, bid in ipairs(gameState.transfers.bids) do
            if bid.isIncomingBid and INCOMING_ACTIVE[bid.status] then
                local e = incIdx[bid.playerId]
                if not e then e = { n = 0, awaiting = false, buyers = {} }; incIdx[bid.playerId] = e end
                e.n = e.n + 1
                if bid.status == "awaiting_sale_confirmation" then e.awaiting = true end
                if bid.buyerTeamId then e.buyers[bid.buyerTeamId] = true end
            end
        end

        local playerAttracted = {}
        local aiAttracted = {}
        local marketIndex = TransferManager._buildListedMarketIndex(gameState)
        TransferManager._transferDiagAdd(gameState, "listedMarketIndexed", #(marketIndex.flat or {}))
        for _, player in ipairs(marketIndex.flat or {}) do
            -- 便宜的随机吸引门槛优先，过滤掉绝大多数球员，避免无谓的报价扫描
            local isPlayerTeamPlayer = (player.teamId == gameState.playerTeamId)
            if isPlayerTeamPlayer and TransferManager.isPlayerRejectingAllOffers(player) then
                goto skipPlayer
            end
            if not isPlayerTeamPlayer and TransferManager._isAIListedForSaleDormant(gameState, player) then
                goto skipPlayer
            end
            local attractChance = isPlayerTeamPlayer and playerAttract or aiAttract
            if Random() > attractChance then goto skipPlayer end

            local idx = incIdx[player.id]
            if idx and idx.awaiting then goto skipPlayer end          -- 等价 _hasAwaitingSaleConfirmation
            if idx and idx.n >= AI_INCOMING_SALE_MAX_COMPETING_BIDS then goto skipPlayer end  -- 等价 getIncomingBidsForPlayer 计数

            local entry = { player = player, idx = idx }
            if isPlayerTeamPlayer then
                playerAttracted[#playerAttracted + 1] = entry
            else
                aiAttracted[#aiAttracted + 1] = entry
            end
            ::skipPlayer::
        end

        if #playerAttracted == 0 and #aiAttracted == 0 then return end

        -- 只有存在实际撮合候选时才构建买家快照，避免转会窗每日空跑也重算全联盟队均/预算。
        local teamCache = TransferManager._buildBuyerTeamCache(gameState)
        local function processEntry(entry)
            local player = entry.player
            local idx = entry.idx
            local buyer = TransferManager._findBuyerForPlayer(gameState, player, teamCache)
            if buyer and not (idx and idx.buyers[buyer.id]) then       -- 等价 hasPendingIncomingBid(player, buyer)
                TransferManager._executeAITransfer(gameState, buyer, player)
            end
        end

        -- 玩家挂牌优先处理；AI-AI 挂牌撮合可限流，避免大存档中每天数百次隐藏交易尝试卡顿。
        for _, entry in ipairs(playerAttracted) do
            processEntry(entry)
        end
        local aiAttempts = 0
        for _, entry in ipairs(aiAttracted) do
            if maxAIAttempts and aiAttempts >= maxAIAttempts then break end
            aiAttempts = aiAttempts + 1
            processEntry(entry)
        end
    end

    --- AI主动挂牌多余球员（增加市场供给）
    ---@param opts table|nil { teams: table[] }
    function TransferManager._aiListPlayersForSale(gameState, opts)
        opts = opts or {}
        local Constants = require("scripts/app/constants")
        local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
        local listedChanged = false
        local teams = opts.teams
        if not teams then
            teams = {}
            for _, team in pairs(gameState.teams or {}) do teams[#teams + 1] = team end
        end
        for _, team in ipairs(teams) do
            if team.id == gameState.playerTeamId then goto skipTeam end
            local target = AiSquadPolicy.getTargetSquadSize(team)
            if #team.playerIds <= target then goto skipTeam end
            -- 阵容过大(>目标+2)时，主动挂牌多余球员
            if #team.playerIds > target + 2 then
                local surplus = #team.playerIds - target
                local listed = 0
                -- 按OVR排序，挂牌最弱的
                local sorted = {}
                for _, pid in ipairs(team.playerIds) do
                    local p = gameState.players[pid]
                    if p and not p.retired and not p.listedForSale and p.squadRole ~= "loaned"
                        and p._aiDelistedWindowKey ~= TransferManager.getTransferWindowKey(gameState) then
                        table.insert(sorted, p)
                    end
                end
                table.sort(sorted, function(a, b) return a.overall < b.overall end)
                for _, p in ipairs(sorted) do
                    if listed >= surplus then break end
                    if #team.playerIds - listed <= target then break end
                    if not TransferManager._isAIProtectedCore(gameState, team, p) then
                        p.listedForSale = true
                        TransferManager._markAIListedForSale(gameState, p)
                        listedChanged = true
                        listed = listed + 1
                    end
                end
            end
            -- 30岁以上且OVR下滑的球员，20%概率挂牌（核心保护）
            local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p and not p.retired and not p.listedForSale and p.squadRole ~= "loaned"
                    and p._aiDelistedWindowKey ~= TransferManager.getTransferWindowKey(gameState) then
                    if #team.playerIds <= target then goto skipList end
                    if TransferManager._isAIProtectedCore(gameState, team, p) then goto skipList end
                    local age = p:getAge(gameState.date.year)
                    if age >= 31 and p.overall < 72 and p.overall < teamAvg - 2 and Random() < 0.20 then
                        p.listedForSale = true
                        TransferManager._markAIListedForSale(gameState, p)
                        listedChanged = true
                    end
                    ::skipList::
                end
            end
            ::skipTeam::
        end
        if listedChanged then TransferManager._invalidateListedPlayerCache(gameState) end
    end

    -- 各角色赛季预期出场（用于判断「缺乏出场」）
    local LOAN_ROLE_SEASON_APPS = {
        key = 32, rotation = 18, squad = 8, youth = 6,
    }

    local AI_LOAN_LIST_MIN_SCORE = 32
    local AI_LOAN_LIST_MAX_AGE = 26
    local AI_LOAN_LIST_MAX_PER_TEAM = 1

    -- Phase2: 豪门重磅引援（仅 AI 主动寻援）
    local AI_ELITE_REP_THRESHOLD = 700
    local AI_BLOCKBUSTER_CHANCE_BY_TIER = { 0.20, 0.40, 0.50 }
    local AI_UPGRADE_MIN_OVR_GAP = 3       -- 默认升级门槛（无球队上下文时）
    local AI_UPGRADE_OVR_GAP_BY_REP = {
        { minRep = 900, gap = 5 },
        { minRep = 800, gap = 4 },
        { minRep = 700, gap = 3 },
        { minRep = 620, gap = 2 },
        { minRep = 0,   gap = 2 },
    }
    local AI_MAXSPEND_NORMAL_RATIO = 0.95
    local AI_MAXSPEND_BLOCKBUSTER_RATIO = 0.35
    local AI_LISTED_WEIGHT = 1.5
    local AI_BLOCKBUSTER_OVR_BONUS = 3       -- 重磅模式 OVR 上限 = 队均+15+3
    local AI_STAR_OVR_GAP = 8
    local AI_STAR_BID_MIN = 1.2
    local AI_STAR_BID_MAX = 1.5
    local AI_STAR_ACCEPT_BONUS = 0.10

    -- AI 主动挖玩家未挂牌球员：只允许强队偶发挖妖人/巨星，避免骚扰玩家。
    local AI_POACH_PLAYER_REP_MIN = 700
    local AI_POACH_PLAYER_SCORE_MULT = 0.70
    local AI_POACH_PLAYER_MAX_GLOBAL_PER_WINDOW = 2
    local AI_POACH_PLAYER_MAX_PER_BUYER_WINDOW = 1
    local AI_POACH_PLAYER_BID_MIN = 1.15
    local AI_POACH_PLAYER_BID_MAX = 1.35

    -- AI↔AI 非挂牌卖方保护：对齐玩家买 AI 未挂牌球员时的非卖品溢价。
    local AI_SELLER_UNLISTED_RATIO_DIVISOR = 1.3
    local AI_SELLER_PROTECTED_MIN_RATIO = 1.4
    local AI_SELLER_PROTECTED_MULT = 0.2
    local AI_SELLER_PROSPECT_MULT = 0.3
    local AI_SELLER_LISTED_ACCEPT_BONUS = 0.35

    local function _blockbusterOvrBonus(team)
        local bonus = AI_BLOCKBUSTER_OVR_BONUS
        local rep = team and team.reputation or 0
        if rep >= 900 then bonus = bonus + 5
        elseif rep >= 800 then bonus = bonus + 2
        end
        return bonus
    end

    --- 测试/诊断用：临时覆盖升级门槛（nil 恢复默认）
    function TransferManager._setAIUpgradeMinOvrGap(gap)
        TransferManager._aiUpgradeMinOvrGapOverride = gap
    end

    function TransferManager._getAIUpgradeMinOvrGap(team)
        if TransferManager._aiUpgradeMinOvrGapOverride then
            return TransferManager._aiUpgradeMinOvrGapOverride
        end
        if team then
            local rep = team.reputation or 600
            for _, tier in ipairs(AI_UPGRADE_OVR_GAP_BY_REP) do
                if rep >= tier.minRep then return tier.gap end
            end
        end
        return AI_UPGRADE_MIN_OVR_GAP
    end

    --- AI 核心球员：非必要不挂牌/不出售（key、队均+5、首发且队均+2）
    function TransferManager._isAIProtectedCore(gameState, team, player)
        if not player or not team then return false end
        if player.squadRole == "key" then return true end
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
        local ovr = player.overall or 50
        if ovr >= teamAvg + 5 then return true end
        if TransferManager._isPlayerInStartingXI(team, player.id) and ovr >= teamAvg + 2 then
            return true
        end
        return false
    end

    function TransferManager._getAIPoachPlayerWindowKey(gameState)
        return TransferManager.getTransferWindowKey(gameState) or "no_window"
    end

    function TransferManager._getAIPoachPlayerGlobalCount(gameState)
        TransferManager._ensureData(gameState)
        local key = TransferManager._getAIPoachPlayerWindowKey(gameState)
        if gameState.transfers._aiPoachPlayerWindowKey ~= key then return 0 end
        return gameState.transfers._aiPoachPlayerCount or 0
    end

    function TransferManager._getAIPoachPlayerBuyerCount(gameState, buyerTeam)
        if not buyerTeam then return 0 end
        local key = TransferManager._getAIPoachPlayerWindowKey(gameState)
        if buyerTeam._aiPoachPlayerWindowKey ~= key then return 0 end
        return buyerTeam._aiPoachPlayerCount or 0
    end

    function TransferManager._canAICreatePlayerPoachBid(gameState, buyerTeam, player)
        if not gameState or not buyerTeam or not player then return false end
        if (buyerTeam.reputation or 0) < AI_POACH_PLAYER_REP_MIN then return false end
        if TransferManager._getAIPoachPlayerGlobalCount(gameState) >= AI_POACH_PLAYER_MAX_GLOBAL_PER_WINDOW then
            return false
        end
        if TransferManager._getAIPoachPlayerBuyerCount(gameState, buyerTeam) >= AI_POACH_PLAYER_MAX_PER_BUYER_WINDOW then
            return false
        end
        return true
    end

    function TransferManager._markAIPoachPlayerBid(gameState, buyerTeam)
        if not gameState or not buyerTeam then return end
        TransferManager._ensureData(gameState)
        local key = TransferManager._getAIPoachPlayerWindowKey(gameState)
        if gameState.transfers._aiPoachPlayerWindowKey ~= key then
            gameState.transfers._aiPoachPlayerWindowKey = key
            gameState.transfers._aiPoachPlayerCount = 0
        end
        gameState.transfers._aiPoachPlayerCount = (gameState.transfers._aiPoachPlayerCount or 0) + 1

        if buyerTeam._aiPoachPlayerWindowKey ~= key then
            buyerTeam._aiPoachPlayerWindowKey = key
            buyerTeam._aiPoachPlayerCount = 0
        end
        buyerTeam._aiPoachPlayerCount = (buyerTeam._aiPoachPlayerCount or 0) + 1
    end

    -- 卖弱换强：升级目标须比被换下者强的最小分差
    local AI_SELL_TO_BUY_MIN_GAP = 4

    -- 自由球员签约：每队每个转会窗最多签入的自由球员数量上限
    local AI_FREE_SIGN_MAX_PER_WINDOW = 2
    -- 自由球员候选加权（免转会费，吸引力略高于同分付费目标）
    local AI_FREE_AGENT_WEIGHT = 1.2

    --- 本周窗标识（用于"每队每周最多 1 笔卖弱换强"限流）
    function TransferManager._currentWeekKey(gameState)
        local d = gameState.date or {}
        local y = d.year or 0
        local m = d.month or 0
        local w = math.floor(((d.day or 1) - 1) / 7)
        return y * 1000 + m * 10 + w
    end

    --- 本窗已签入自由球员数量（窗口切换自动归零）
    function TransferManager._getAIFreeSignCount(gameState, team)
        local key = TransferManager.getTransferWindowKey(gameState)
        if not key then return 0 end
        if team._freeSignWindowKey ~= key then return 0 end
        return team._freeSignCount or 0
    end

    --- 本窗是否还能再签自由球员（上限 AI_FREE_SIGN_MAX_PER_WINDOW）
    function TransferManager._canAISignFreeAgent(gameState, team)
        return TransferManager._getAIFreeSignCount(gameState, team) < AI_FREE_SIGN_MAX_PER_WINDOW
    end

    --- 累加本窗自由球员签约计数
    function TransferManager._incAIFreeSignCount(gameState, team)
        local key = TransferManager.getTransferWindowKey(gameState)
        if not key then return end
        if team._freeSignWindowKey ~= key then
            team._freeSignWindowKey = key
            team._freeSignCount = 0
        end
        team._freeSignCount = (team._freeSignCount or 0) + 1
    end

    --- 找队内"可换下"的最弱冗余球员（同位置组优先，排除核心/受保护球员）
    --- @param group string|nil 限定位置组（"GK"/"DEF"/"MID"/"FWD"）；nil 则全队
    --- @return table|nil player
    function TransferManager._aiPickWeakestExpendable(gameState, team, group)
        local Constants = require("scripts/app/constants")
        local groupPositions = group and Constants.POSITION_GROUPS[group] or nil
        local function inGroup(p)
            if not groupPositions then return true end
            for _, pos in ipairs(groupPositions) do
                if p.position == pos then return true end
            end
            return false
        end

        local weakest, weakestOvr = nil, math.huge
        for _, pid in ipairs(team.playerIds or {}) do
            local p = gameState.players[pid]
            if p and not p.retired and p.squadRole ~= "loaned"
                and not p.listedForSale and inGroup(p)
                and not TransferManager._isAIProtectedCore(gameState, team, p) then
                local ovr = p.overall or 50
                if ovr < weakestOvr then
                    weakestOvr = ovr
                    weakest = p
                end
            end
        end
        return weakest
    end

    --- 关窗/读档兜底：把 AI 队收敛回常规上限（释放最弱非核心球员为自由球员）
    ---@param opts table|nil { silent = boolean }
    ---@return number released 释放人数
    function TransferManager.enforceAISquadCap(gameState, opts)
        opts = opts or {}
        if not gameState or not gameState.teams then return 0 end
        local Team = require("scripts/domain/team")
        local cap = Team.getFirstTeamMax()
        local released = 0

        for tid, team in pairs(gameState.teams) do
            if tid == gameState.playerTeamId then goto skipTeam end
            local guard = 0
            while #team.playerIds > cap and guard < 20 do
                guard = guard + 1
                local w = TransferManager._aiPickWeakestExpendable(gameState, team, nil)
                if not w then
                    -- 全部受保护时，退而选纯 OVR 最低的非外租球员，确保能收敛
                    local fallback, fbOvr = nil, math.huge
                    for _, pid in ipairs(team.playerIds) do
                        local p = gameState.players[pid]
                        if p and not p.retired and p.squadRole ~= "loaned" and (p.overall or 50) < fbOvr then
                            fbOvr = p.overall or 50
                            fallback = p
                        end
                    end
                    w = fallback
                end
                if not w then break end
                TransferManager._aiReleaseToFreeAgent(gameState, w)
                released = released + 1
            end
            ::skipTeam::
        end

        return released
    end

    --- 将球员释放为自由球员（解约：清队籍、挂牌、活跃报价）
    function TransferManager._aiReleaseToFreeAgent(gameState, player)
        if not player then return end
        -- 释放为自由球员属低频路径（窗口关闭收敛），保留全队防御性清理，避免任何残留引用
        TransferManager._removePlayerFromAllTeams(gameState, player.id)
        TransferManager._invalidateActiveBidsForPlayer(gameState, player.id, {})
        player.teamId = nil
        player.listedForSale = false
        player.listedForLoan = false
        player.saleAskingPrice = nil
        player.loanListDuration = nil
        player.squadRole = nil
        TransferManager._invalidateListedPlayerCache(gameState)
    end

    --- 升级/重磅引援评分（偏 OVR、轻身价；年轻高潜额外加权）
    function TransferManager._scoreAITransferCandidate(player, teamAvg, opts)
        opts = opts or {}
        local ovr = player.overall or 50
        local value = math.max(player.value or 1, 1)
        local score
        if opts.upgradeMode or opts.blockbuster then
            local ovrAbove = math.max(0, ovr - teamAvg)
            local ovrPow = opts.blockbuster and 1.45 or 1.30
            local valuePow = opts.blockbuster and 0.08 or 0.10
            score = (ovr ^ ovrPow) * (1 + ovrAbove * 0.12) / (value ^ valuePow)
        else
            score = ovr * (value ^ 0.15)
        end
        if player.listedForSale then
            score = score * AI_LISTED_WEIGHT
        end
        local pot = player.actualPotential or player.potential or ovr
        local potGap = pot - ovr
        if opts.gameState and player.getAge then
            local age = player:getAge(opts.gameState.date.year)
            if age <= 21 and potGap >= 8 then
                score = score * (1 + math.min(0.5, potGap * 0.03))
            end
        end
        return score
    end

    function TransferManager._getSeasonProgress(gameState)
        local Constants = require("scripts/app/constants")
        local startMonth = Constants.SEASON_START_MONTH or 8
        local monthsElapsed = gameState.date.month - startMonth
        if monthsElapsed < 0 then monthsElapsed = monthsElapsed + 12 end
        return math.max(0, math.min(1, monthsElapsed / 10))
    end

    function TransferManager._isPlayerInStartingXI(team, playerId)
        for _, pid in pairs(team.startingXI or {}) do
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
    ---@param opts table|nil { teams: table[], maxGlobal: number }
    function TransferManager._aiListPlayersForLoan(gameState, opts)
        if not TransferManager.isInTransferWindow(gameState) then return end

        opts = opts or {}
        local maxGlobal = opts.maxGlobal or AI_LOAN_LIST_MAX_GLOBAL
        local teams = opts.teams
        if not teams then
            teams = {}
            for _, team in pairs(gameState.teams or {}) do teams[#teams + 1] = team end
        end

        local globalListed = 0
        local listedChanged = false
        for _, team in ipairs(teams) do
            if team.id == gameState.playerTeamId then goto skipTeam end
            if globalListed >= maxGlobal then break end

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
                if globalListed >= maxGlobal then break end
                local entry = candidates[i]
                local p = entry.player
                local pAge = p:getAge(gameState.date.year)
                p.listedForLoan = true
                p.loanListDuration = (pAge <= 21) and 52 or 26
                listedChanged = true
                globalListed = globalListed + 1
            end

            ::skipTeam::
        end
        if listedChanged then TransferManager._invalidateListedPlayerCache(gameState) end
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

    --- 豪门本周是否进入重磅引援模式（仅主动寻援）
    function TransferManager._shouldAIBlockbusterMode(gameState, team)
        if not TransferManager._isAITeamAffluent(team) then return false end
        if (team.reputation or 0) < AI_ELITE_REP_THRESHOLD then return false end
        local tier = DifficultySettings.get().transferTier or 2
        local chance = AI_BLOCKBUSTER_CHANCE_BY_TIER[tier] or AI_BLOCKBUSTER_CHANCE_BY_TIER[2]
        return Random() <= chance
    end

    --- AI 主动寻援单笔上限（测试/诊断用）
    function TransferManager._getAIMaxSpend(buyerTeam, blockbuster)
        if blockbuster then
            return math.floor((buyerTeam.balance or 0) * AI_MAXSPEND_BLOCKBUSTER_RATIO)
        end
        local budget = TransferManager._getAIEffectiveBudget(buyerTeam)
        return math.floor(budget * AI_MAXSPEND_NORMAL_RATIO)
    end

    --- 加权随机抽取候选球员（candidates: { player, score }[]）
    function TransferManager._pickWeightedCandidate(candidates)
        if #candidates == 0 then return nil end
        if #candidates == 1 then return candidates[1].player end

        local total = 0
        for _, entry in ipairs(candidates) do
            total = total + entry.score
        end
        if total <= 0 then
            return candidates[randInt(1, #candidates)].player
        end

        local roll = Random() * total
        local acc = 0
        for _, entry in ipairs(candidates) do
            acc = acc + entry.score
            if roll <= acc then return entry.player end
        end
        return candidates[#candidates].player
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
        local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
        local targetSize = AiSquadPolicy.getTargetSquadSize(team)
        if #team.playerIds < targetSize then
            local groups = {"DEF", "MID", "FWD"}
            return groups[randInt(1, 3)], false
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

    -- 候选池 band 阈值（基于 effectiveBandOvr 分档）
    local CANDIDATE_BAND_ELITE_MIN = 72
    local CANDIDATE_BAND_MID_MIN = 58
    local CANDIDATE_BAND_KEYS = { "elite", "mid", "low" }
    local CANDIDATE_SCAN_MAX_PER_SLICE = 180
    local CANDIDATE_PROSPECT_SCAN_MAX = 120

    local function _newBandBuckets()
        return { GK = {}, DEF = {}, MID = {}, FWD = {} }
    end

    --- 建池用有效 OVR：年轻高潜球员上浮至更高 band，避免妖人只落在 low 池
    function TransferManager._effectiveBandOvr(player, gameState)
        local ovr = player.overall or 50
        local pot = player.actualPotential or player.potential or ovr
        local year = gameState and gameState.date and gameState.date.year or 2026
        local age = player.getAge and player:getAge(year) or (year - (player.birthYear or 2000))
        local potGap = pot - ovr

        if age <= 21 then
            local uplift = math.min(12, potGap * 0.35)
            if pot >= 88 then uplift = uplift + 3 end
            return ovr + uplift
        elseif age <= 23 and potGap >= 6 then
            return ovr + math.min(6, potGap * 0.25)
        end
        return ovr
    end

    function TransferManager._candidateBandKey(effectiveOvr)
        if effectiveOvr >= CANDIDATE_BAND_ELITE_MIN then return "elite" end
        if effectiveOvr >= CANDIDATE_BAND_MID_MIN then return "mid" end
        return "low"
    end

    --- 年轻妖人侧车索引（blockbuster/upgrade 时额外扫描，允许低于 minOvr）
    function TransferManager._isProspectSidecar(player, gameState)
        local ovr = player.overall or 50
        local pot = player.actualPotential or player.potential or ovr
        local year = gameState and gameState.date and gameState.date.year or 2026
        local age = player.getAge and player:getAge(year) or (year - (player.birthYear or 2000))
        local potGap = pot - ovr
        return age <= 21 and potGap >= 8 and pot >= 82
    end

    --- 妖人 OVR 窗口例外：即战力不足但潜力极高，豪门/升级模式可低于 minOvr 考察
    function TransferManager._qualifiesProspectOvrBypass(player, gameState, opts)
        opts = opts or {}
        if not opts.blockbuster and not opts.upgradeMode then return false end
        if not TransferManager._isProspectSidecar(player, gameState) then return false end
        local pOvr = player.overall or 50
        if pOvr > (opts.maxOvr or 99) then return false end
        if pOvr >= (opts.minOvr or 0) then return true end
        if opts.blockbuster then return true end
        -- upgradeMode：次级队也可挖同级 young gem，但仍受 maxOvr 约束
        local pot = player.actualPotential or player.potential or pOvr
        local potGap = pot - pOvr
        return potGap >= 6 and pot >= 78
    end

    function TransferManager._canAIConsiderPlayerPoach(gameState, buyerTeam, player, opts)
        opts = opts or {}
        if not gameState or not buyerTeam or not player then return false end
        if player.teamId ~= gameState.playerTeamId or player.listedForSale then return false end
        if TransferManager.isPlayerOnLoan(player) then return false end
        if not opts.blockbuster and not opts.upgradeMode then return false end
        if not TransferManager._canAICreatePlayerPoachBid(gameState, buyerTeam, player) then return false end

        local anchor = opts.anchor
        if not anchor then
            local ok, AiSquadPolicy = pcall(require, "scripts/systems/ai_squad_policy")
            local repTarget = ok and AiSquadPolicy.getRepTargetOvr(buyerTeam) or 0
            anchor = math.max(TransferManager._getTeamAverageOverall(gameState, buyerTeam), repTarget)
        end

        local pOvr = player.overall or 50
        if pOvr >= anchor + AI_STAR_OVR_GAP then return true end
        return TransferManager._isProspectSidecar(player, gameState)
    end

    function TransferManager._getAISellerAcceptChance(gameState, sellerTeam, player, offerAmount, opts)
        opts = opts or {}
        if not player then return 0 end

        local value = math.max(player.value or 1, 1)
        local ratio = (offerAmount or 0) / value
        local listed = player.listedForSale
        local effectiveRatio = listed and ratio or (ratio / AI_SELLER_UNLISTED_RATIO_DIVISOR)
        local acceptChance = 0
        if effectiveRatio >= 1.3 then acceptChance = 0.95
        elseif effectiveRatio >= 1.1 then acceptChance = 0.80
        elseif effectiveRatio >= 1.0 then acceptChance = 0.60
        elseif effectiveRatio >= 0.85 then acceptChance = 0.35
        else acceptChance = 0.15 end

        local protectedCore = sellerTeam and not listed
            and TransferManager._isAIProtectedCore(gameState, sellerTeam, player)
        local prospect = not listed and TransferManager._isProspectSidecar(player, gameState)

        if protectedCore and ratio < AI_SELLER_PROTECTED_MIN_RATIO then
            return 0
        end

        if listed then
            acceptChance = math.min(0.95, acceptChance + AI_SELLER_LISTED_ACCEPT_BONUS)
        end

        -- 阵容臃肿只影响非核心冗员，避免“人多所以卖核心”。
        if sellerTeam and #sellerTeam.playerIds > 25 and not protectedCore then
            acceptChance = math.min(0.95, acceptChance + 0.20)
        end

        if opts.isStarTarget and not protectedCore and not prospect then
            acceptChance = math.min(0.95, acceptChance + AI_STAR_ACCEPT_BONUS)
        end

        if protectedCore then
            acceptChance = acceptChance * AI_SELLER_PROTECTED_MULT
        end
        if prospect then
            acceptChance = acceptChance * AI_SELLER_PROSPECT_MULT
        end

        return math.max(0, math.min(0.95, acceptChance))
    end

    --- 买家声望决定日常扫描哪些 band（blockbuster 时中游队也可触 elite）
    function TransferManager._getCandidateBandsForBuyer(buyerTeam, blockbuster)
        local rep = buyerTeam and buyerTeam.reputation or 600
        if rep >= 800 then
            return CANDIDATE_BAND_KEYS
        end
        if rep >= 650 then
            if blockbuster then return CANDIDATE_BAND_KEYS end
            return { "mid", "low" }
        end
        return { "mid", "low" }
    end

    --- 合并各 band 某位置组（测试/诊断兼容 flat pool[group]）
    function TransferManager._mergeCandidatePoolGroup(pool, group)
        if not pool then return {} end
        if not pool.bands then return pool[group] or {} end
        local out = {}
        for _, bandKey in ipairs(CANDIDATE_BAND_KEYS) do
            local bucket = pool.bands[bandKey] and pool.bands[bandKey][group]
            if bucket then
                for _, p in ipairs(bucket) do out[#out + 1] = p end
            end
        end
        table.sort(out, function(a, b) return (a.overall or 50) < (b.overall or 50) end)
        return out
    end

    --- 按位置组 + OVR band 预分桶可转会球员，窗口级缓存（同一转会窗内复用）。
    --- 池存球员引用；consider() 实时检查 teamId/retired/listedForSale。
    function TransferManager._buildTransferCandidatePool(gameState)
        TransferManager._ensureData(gameState)
        local transfers = gameState.transfers
        local windowKey = TransferManager.getTransferWindowKey(gameState) or ""
        if transfers._candidatePoolWindowKey == windowKey and transfers._candidatePoolCache then
            TransferManager._transferDiagAdd(gameState, "candidatePoolCacheHits", 1)
            return transfers._candidatePoolCache
        end

        local t0 = os.clock()
        local p2g = _posToGroup()
        local bands = { elite = _newBandBuckets(), mid = _newBandBuckets(), low = _newBandBuckets() }
        local prospects = _newBandBuckets()
        for _, player in pairs(gameState.players) do
            if not player.retired and not player._isVirtual then
                local g = p2g[player.position]
                if g then
                    local eff = TransferManager._effectiveBandOvr(player, gameState)
                    local bandKey = TransferManager._candidateBandKey(eff)
                    local bucket = bands[bandKey][g]
                    bucket[#bucket + 1] = player
                    if TransferManager._isProspectSidecar(player, gameState) then
                        local pg = prospects[g]
                        pg[#pg + 1] = player
                    end
                end
            end
        end

        local function byOvr(a, b) return (a.overall or 50) < (b.overall or 50) end
        for _, bandKey in ipairs(CANDIDATE_BAND_KEYS) do
            local band = bands[bandKey]
            table.sort(band.GK, byOvr)
            table.sort(band.DEF, byOvr)
            table.sort(band.MID, byOvr)
            table.sort(band.FWD, byOvr)
        end
        for _, g in ipairs({ "GK", "DEF", "MID", "FWD" }) do
            table.sort(prospects[g], byOvr)
        end

        local pool = { bands = bands, prospects = prospects }
        transfers._candidatePoolCache = pool
        transfers._candidatePoolWindowKey = windowKey
        TransferManager._transferDiagAdd(gameState, "candidatePoolBuilds", 1)
        TransferManager._transferDiagAdd(gameState, "candidatePoolMs", (os.clock() - t0) * 1000)
        for _, bandKey in ipairs(CANDIDATE_BAND_KEYS) do
            local n = 0
            for _, group in ipairs({ "GK", "DEF", "MID", "FWD" }) do
                n = n + #(bands[bandKey][group] or {})
            end
            TransferManager._transferDiagAdd(gameState, "candidatePool" .. bandKey:gsub("^%l", string.upper), n)
        end
        return pool
    end

    --- 寻找转会目标
    ---@param opts table|nil { blockbuster: boolean, allowFreeAgents: boolean, pool: table }
    function TransferManager._findTransferTarget(gameState, buyerTeam, needGroup, upgradeMode, opts)
        opts = opts or {}
        local blockbuster = opts.blockbuster or false
        local allowFreeAgents = opts.allowFreeAgents or false
        local Constants = require("scripts/app/constants")
        local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
        local targetPositions = Constants.POSITION_GROUPS[needGroup] or {}
        local candidates = {}
        local budget = TransferManager._getAIEffectiveBudget(buyerTeam)
        local maxSpend = TransferManager._getAIMaxSpend(buyerTeam, blockbuster)
        local teamAvg = TransferManager._getTeamAverageOverall(gameState, buyerTeam)
        local ovrCeiling = 15 + (blockbuster and _blockbusterOvrBonus(buyerTeam) or 0)
        local repMin = AiSquadPolicy.getRepMinOvr(buyerTeam, upgradeMode and "upgrade" or "fill")
        -- 引援锚点：不随下滑的队均走，至少锚定“声望应有队均”。
        -- 这样队均跌到 70 的豪门，仍会按 80 的水平去够星，而不是把 72 当合格升级目标。
        local repTarget = AiSquadPolicy.getRepTargetOvr(buyerTeam)
        local anchor = math.max(teamAvg, repTarget)

        -- 能力窗口（队内常量，提前算出，避免逐球员重复计算）
        local minOvr
        if upgradeMode then
            minOvr = math.max(teamAvg + TransferManager._getAIUpgradeMinOvrGap(buyerTeam), repMin)
        else
            minOvr = math.max(teamAvg - 12, repMin)
        end
        local maxOvr = anchor + ovrCeiling
        local transferTier = DifficultySettings.get().transferTier or 2

        local fullPool = opts.pool
        local bandKeys = fullPool and fullPool.bands
            and TransferManager._getCandidateBandsForBuyer(buyerTeam, blockbuster) or nil
        local useBandPool = bandKeys ~= nil
        local seen = {}

        local function consider(player)
            if seen[player.id] then return end
            if player.retired then return end
            if TransferManager.hasMovedInCurrentWindow(gameState, player.id) then return end
            local isFree = (player.teamId == nil)
            local isPlayerPoachTarget = false
            if isFree then
                if not allowFreeAgents then return end
                if player._isVirtual then return end
            else
                if player.teamId == buyerTeam.id then return end
                if player.teamId == gameState.playerTeamId and not player.listedForSale then
                    if not TransferManager._canAIConsiderPlayerPoach(gameState, buyerTeam, player, {
                        blockbuster = blockbuster,
                        upgradeMode = upgradeMode,
                        anchor = anchor,
                    }) then
                        return
                    end
                    isPlayerPoachTarget = true
                end
                if opts.playerBidSet then
                    if opts.playerBidSet[player.id] then return end
                elseif TransferManager.hasActiveBidOnPlayer(gameState, player.id, { buyerTeamId = gameState.playerTeamId }) then
                    return
                end
            end

            if not useBandPool then
                local posMatch = false
                for _, pos in ipairs(targetPositions) do
                    if player.position == pos then posMatch = true; break end
                end
                if not posMatch then return end
            end

            local expectedCost = player.listedForSale and TransferManager.getSaleAskingPrice(player) or (player.value or 0)
            if not isFree and expectedCost > maxSpend then return end

            local pOvr = player.overall or 50
            local inWindow = pOvr >= minOvr and pOvr <= maxOvr
            if not inWindow then
                if not TransferManager._qualifiesProspectOvrBypass(player, gameState, {
                    blockbuster = blockbuster,
                    upgradeMode = upgradeMode,
                    minOvr = minOvr,
                    maxOvr = maxOvr,
                }) then
                    return
                end
            end

            local pWage = player.wage or 0
            if pWage > 0 and pOvr < 78 then
                local fairWage = 25 * math.exp(0.117 * pOvr)
                if pWage > fairWage * 1.5 and transferTier <= 2 then return end
            end

            seen[player.id] = true
            local score = TransferManager._scoreAITransferCandidate(player, anchor, {
                upgradeMode = upgradeMode,
                blockbuster = blockbuster,
                gameState = gameState,
            })
            if isFree then score = score * AI_FREE_AGENT_WEIGHT end
            if isPlayerPoachTarget then score = score * AI_POACH_PLAYER_SCORE_MULT end
            if score > 0 then
                candidates[#candidates + 1] = { player = player, score = score }
            end
        end

        local function considerSlice(slice)
            if not slice or #slice == 0 then return end
            local n = #slice
            local lo, hi = 1, n + 1
            while lo < hi do
                local mid = math.floor((lo + hi) / 2)
                if (slice[mid].overall or 50) < minOvr then
                    lo = mid + 1
                else
                    hi = mid
                end
            end
            local upper = lo - 1
            local ulo, uhi = lo, n + 1
            while ulo < uhi do
                local mid = math.floor((ulo + uhi) / 2)
                if (slice[mid].overall or 50) <= maxOvr then
                    ulo = mid + 1
                else
                    uhi = mid
                end
            end
            upper = ulo - 1
            if upper >= lo then
                -- 候选 slice 在大世界会非常宽；保留能力窗高端样本，避免每队重复扫数千人。
                local start = math.max(lo, upper - CANDIDATE_SCAN_MAX_PER_SLICE + 1)
                for i = start, upper do
                    consider(slice[i])
                end
            end
        end

        local function considerProspects(slice)
            if not slice or #slice == 0 or not (blockbuster or upgradeMode) then return end
            local start = math.max(1, #slice - CANDIDATE_PROSPECT_SCAN_MAX + 1)
            for i = start, #slice do
                local p = slice[i]
                if (p.overall or 50) <= maxOvr then
                    consider(p)
                end
            end
        end

        if useBandPool then
            for _, bandKey in ipairs(bandKeys) do
                local band = fullPool.bands[bandKey]
                if band then considerSlice(band[needGroup]) end
            end
            considerProspects(fullPool.prospects and fullPool.prospects[needGroup])
        elseif fullPool and fullPool[needGroup] then
            considerSlice(fullPool[needGroup])
        else
            for _, player in pairs(gameState.players) do consider(player) end
        end

        if #candidates == 0 then return nil end

        return TransferManager._pickWeightedCandidate(candidates)
    end

    --- 执行 AI 转会（返回 true 表示成交）
    ---@param opts table|nil { upgradeMode: boolean, teamAvg: number }
    function TransferManager._executeAITransfer(gameState, buyerTeam, player, opts)
        opts = opts or {}
        -- 预签约锁定检查：已被预签约的球员不可再交易
        if player.preContractLockedBy then return false end
        if TransferManager.isPlayerOnLoan(player) then return false end
        local moveOk = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
        if not moveOk then return false end

        -- 满员处理：仅"AI↔AI 主动升级"允许窗口期先买后卖超员（关窗收敛回 30）；
        -- 其余场景（买玩家挂牌球员/普通满员）维持硬顶拒绝。
        local swapOutPlayer = nil
        if buyerTeam:isFirstTeamFull() then
            local isAIvsAI = player.teamId and player.teamId ~= gameState.playerTeamId
            if opts.sellToBuy and isAIvsAI
                and TransferManager.isInTransferWindow(gameState)
                and not buyerTeam:isAISquadHardFull()
                and TransferManager._currentWeekKey(gameState) ~= buyerTeam._sellToBuyWeekKey then
                local w = TransferManager._aiPickWeakestExpendable(gameState, buyerTeam, nil)
                if w and (player.overall or 0) >= (w.overall or 0) + AI_SELL_TO_BUY_MIN_GAP then
                    swapOutPlayer = w  -- 成交后挂牌该最弱者，腾出名额
                else
                    return false  -- 没有值得换下的冗余球员，不强行倒腾
                end
            else
                return false
            end
        end

        local sellerTeam = gameState.teams[player.teamId]

        local teamAvg = opts.teamAvg or TransferManager._getTeamAverageOverall(gameState, buyerTeam)
        local pOvr = player.overall or 50
        local isPlayerTeamTarget = player.teamId == gameState.playerTeamId
        if isPlayerTeamTarget and TransferManager.isPlayerRejectingAllOffers(player) then
            return false
        end
        local isPlayerPoachBid = isPlayerTeamTarget and not player.listedForSale
        local isStarTarget = opts.upgradeMode
            and not player.listedForSale
            and pOvr >= teamAvg + AI_STAR_OVR_GAP
        if isPlayerPoachBid then
            if not TransferManager._canAIConsiderPlayerPoach(gameState, buyerTeam, player, {
                blockbuster = opts.blockbuster,
                upgradeMode = opts.upgradeMode,
            }) then
                return false
            end
        end

        -- AI 报价：玩家主动设置挂牌价时围绕要价出价；普通挂牌仍沿用身价折算。
        local multiplier
        local priceBase = player.value or 0
        if player.listedForSale then
            if isPlayerTeamTarget and player.saleAskingPrice then
                priceBase = TransferManager.getSaleAskingPrice(player)
                multiplier = 0.95 + Random() * 0.10
            else
                multiplier = 0.85 + Random() * 0.25
            end
        elseif isPlayerPoachBid then
            if isStarTarget or TransferManager._isProspectSidecar(player, gameState) then
                multiplier = AI_STAR_BID_MIN + Random() * (AI_STAR_BID_MAX - AI_STAR_BID_MIN)
            else
                multiplier = AI_POACH_PLAYER_BID_MIN + Random() * (AI_POACH_PLAYER_BID_MAX - AI_POACH_PLAYER_BID_MIN)
            end
        elseif isStarTarget then
            multiplier = AI_STAR_BID_MIN + Random() * (AI_STAR_BID_MAX - AI_STAR_BID_MIN)
        else
            multiplier = 1.0 + Random() * 0.3
        end
        local offerAmount = math.floor(priceBase * multiplier)
        if isPlayerTeamTarget and player.listedForSale and player.saleAskingPrice
            and offerAmount > TransferManager._getAIEffectiveBudget(buyerTeam) then
            return false
        end

        -- 目标是玩家球队球员时，只生成收购报价让玩家决策；未挂牌挖角也不会静默成交。
        if isPlayerTeamTarget then
            if TransferManager.hasPendingIncomingBid(gameState, player.id, buyerTeam.id) then return false end
            if #TransferManager.getIncomingBidsForPlayer(gameState, player.id) >= AI_INCOMING_SALE_MAX_COMPETING_BIDS then
                return false
            end
            TransferManager._createIncomingBid(gameState, buyerTeam, player, offerAmount, {
                isPoachBid = isPlayerPoachBid,
            })
            if isPlayerPoachBid then
                TransferManager._markAIPoachPlayerBid(gameState, buyerTeam)
            end
            return true  -- 报价已创建，算作活动
        end

        -- 卖方判断是否接受
        local acceptChance = TransferManager._getAISellerAcceptChance(gameState, sellerTeam, player, offerAmount, {
            isStarTarget = isStarTarget,
        })

        if Random() > acceptChance then return false end  -- 卖方拒绝

        -- AI 工资谈判：基于市场合理薪资，避免无限通胀
        local marketWage = TransferManager.getSuggestedTransferWage(player, buyerTeam, gameState)
        local newWage = math.floor(marketWage * (0.95 + Random() * 0.15))  -- 市场价 -5% ~ +10%
        -- 保底不低于原工资（球员不接受降薪）
        newWage = math.max(player.wage, newWage)

        local canAfford, _ = TransferManager._checkAIWageBudgetForSigning(gameState, buyerTeam, newWage)
        if not canAfford then return false end  -- 工资超预算（含挂牌出售可腾出空间），放弃

        -- 完成转会
        if sellerTeam then
            -- 通过 FinanceManager 处理卖方入账（更新 balance、transferBudget、seasonIncome、流水）
            FinanceManager.processTransferIn(gameState, sellerTeam.id, offerAmount, player.displayName or player.firstName)
        end

        TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id,
            swapOutPlayer and { allowOverCap = true } or nil)
        if player.teamId ~= buyerTeam.id then return false end
        player.listedForSale = false
        player.listedForLoan = false
        player.saleAskingPrice = nil
        TransferManager._clearAIListedForSaleMeta(player)
        player.isYouth = false
        player.squadRole = "first_team"
        player.wage = newWage  -- 更新球员工资
        player.contractEnd = {year = gameState.date.year + TransferManager._calcExpectedYears(player, gameState.date.year), month = 6}

        -- 卖弱换强：成交后挂牌被换下的最弱者腾名额，并记本周限流标记
        if swapOutPlayer then
            swapOutPlayer.listedForSale = true
            TransferManager._markAIListedForSale(gameState, swapOutPlayer)
            TransferManager._invalidateListedPlayerCache(gameState)
            buyerTeam._sellToBuyWeekKey = TransferManager._currentWeekKey(gameState)
        end

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

    --- AI 签入自由球员（无转会费，仅工资）。受"每队每窗 AI_FREE_SIGN_MAX_PER_WINDOW 名"上限约束。
    ---@return boolean signed
    function TransferManager._executeAIFreeSign(gameState, buyerTeam, player)
        if not buyerTeam or not player then return false end
        if player.teamId ~= nil then return false end       -- 仅限真正的自由球员
        if player._isVirtual or player.retired then return false end
        if player.preContractLockedBy then return false end
        -- 满员则不签（自由签约不触发卖弱换强）
        if buyerTeam:isFirstTeamFull() then return false end
        -- 本窗签约数量上限
        if not TransferManager._canAISignFreeAgent(gameState, buyerTeam) then return false end
        -- 本窗该球员是否已动过
        local moveOk = TransferManager._checkPlayerWindowMoveLimit(gameState, player.id)
        if not moveOk then return false end

        -- 工资谈判（与付费转会一致：市场价 -5% ~ +10%，不低于原薪）
        local marketWage = TransferManager.getSuggestedTransferWage(player, buyerTeam, gameState)
        local newWage = math.floor(marketWage * (0.95 + Random() * 0.15))
        newWage = math.max(player.wage or 0, newWage)

        local canAfford = TransferManager._checkAIWageBudgetForSigning(gameState, buyerTeam, newWage)
        if not canAfford then return false end

        if not TransferManager._assignPlayerToTeam(gameState, player, buyerTeam.id) then return false end
        if player.teamId ~= buyerTeam.id then return false end

        player.listedForSale = false
        player.listedForLoan = false
        player.isYouth = false
        player.isFreeAgent = nil
        player.squadRole = "first_team"
        player.wage = newWage
        player.contractEnd = { year = gameState.date.year + TransferManager._calcExpectedYears(player, gameState.date.year), month = 6 }

        player:calculateReputation(buyerTeam.reputation or 300)
        player:calculateValue(gameState.date.year)

        TransferManager._markPlayerWindowMove(gameState, player.id)
        TransferManager._incAIFreeSignCount(gameState, buyerTeam)

        table.insert(gameState.transfers.history, {
            playerId = player.id,
            playerName = player.displayName,
            fromTeamId = nil,
            toTeamId = buyerTeam.id,
            amount = 0,
            date = { year = gameState.date.year, month = gameState.date.month, day = gameState.date.day },
            isAI = true,
            type = "free",
        })

        return true
    end
end
