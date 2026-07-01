-- systems/youth/legend_gacha.lua
-- 传奇球星池抽卡，从 youth_manager.lua 拆分。

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local Team = require("scripts/domain/team")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")
local TrainingManager = require("scripts/systems/training_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local FinanceManager = require("scripts/systems/finance_manager")
local Nationality = require("scripts/domain/nationality")
local LegendGachaCloud = require("scripts/persistence/legend_gacha_cloud")
local TextUtil = require("scripts/app/text_util")
local Helpers = require("scripts/systems/youth/youth_helpers")
local randInt = Helpers.randInt

return function(YouthManager)
    ------------------------------------------------------
    -- 传奇球星池抽卡配置
    ------------------------------------------------------
    local LEGEND_UNLOCK_ADS = 10        -- 看10次广告解锁传奇池
    local LEGEND_PULL_PER_AD = 3        -- 解锁后每次广告获得3次抽取
    local LEGEND_TEN_PULL_ADS = 3       -- 3次广告 = +15抽
    local LEGEND_PITY_COUNT = 8         -- 8次十连（80抽）硬保底
    local LEGEND_FIRST_GUARANTEED = true -- 首次十连保底一个传奇
    local LEGEND_MAX_PER_PULL = 1       -- 每次十连最多出1个传奇
    -- 保底档位单槽概率（前缓后陡；十连≈1-(1-r)^10）
    -- 曲线：38%→40%→43%→47%→51%→54%→55%→100%(硬保底)
    local LEGEND_PITY_RATES = {
        0.0470,  -- 第2次十连 ≈38%
        0.0508,  -- ≈40%
        0.0554,  -- ≈43%
        0.0610,  -- ≈47%
        0.0670,  -- ≈51%
        0.0725,  -- ≈54%
        0.0813,  -- ≈55% 封顶
    }

    ---@param pityLevel integer 0=保底重置后首次，递增
    local function _legendRateForPityLevel(pityLevel)
        pityLevel = math.max(0, pityLevel)
        local idx = math.min(pityLevel + 1, #LEGEND_PITY_RATES)
        return LEGEND_PITY_RATES[idx]
    end

    -- 英文完整位置名 → 游戏简写位置映射（wonderkids JSON 使用完整英文）
    local POSITION_MAP = {
        Goalkeeper = "GK",
        CentreBack = "CB",
        LeftBack = "LB",
        RightBack = "RB",
        DefensiveMidfielder = "CDM",
        CentralMidfielder = "CM",
        AttackingMidfielder = "CAM",
        LeftMidfielder = "LM",
        RightMidfielder = "RM",
        LeftWing = "LW",
        RightWing = "RW",
        Striker = "ST",
        CentreForward = "ST",
        CenterForward = "ST",
    }

    local function mapPosition(pos)
        return Helpers.mapPosition(pos, POSITION_MAP)
    end

    ------------------------------------------------------
    -- 传奇球星池抽卡系统（叙事标签分池）
    ------------------------------------------------------

    local LegendTagPools = require("scripts/data/legend_tag_pools")

    YouthManager.LEGEND_CLOUD_SYNCING = "legend_cloud_syncing"
    YouthManager.LEGEND_CLOUD_CONFLICT = "legend_cloud_conflict"

    --- 云存档模式下是否允许修改传奇抽卡账本
    ---@return boolean
    function YouthManager.canMutateLegendGacha()
        if LegendGachaCloud.hasPendingConflict() then return false end
        if not LegendGachaCloud.isEnabled() then return true end
        return LegendGachaCloud.canMutate()
    end

    --- 云存档是否已完成首次同步
    ---@return boolean
    function YouthManager.isLegendGachaCloudReady()
        if LegendGachaCloud.hasPendingConflict() then return false end
        if not LegendGachaCloud.isEnabled() then return true end
        return LegendGachaCloud.isReady()
    end

    ---@return table|nil
    function YouthManager.getLegendGachaPendingAccountAttach()
        return LegendGachaCloud.getPendingAccountAttach()
    end

    ---@return table|nil
    function YouthManager.getLegendGachaPendingConflict()
        return LegendGachaCloud.getPendingConflict()
    end

    --- 探测账号级云账本（本地未开启时）
    function YouthManager.probeLegendGachaAccountLedger(events)
        return LegendGachaCloud.probeAccountLedger(events)
    end

    --- 确认接入账号云账本
    function YouthManager.acceptLegendGachaAccountLedger(gameState)
        return LegendGachaCloud.acceptRemoteAccountLedger(gameState)
    end

    --- 冲突时选择使用云端
    function YouthManager.resolveLegendGachaConflictUseCloud(gameState)
        return LegendGachaCloud.resolveConflictUseCloud(gameState)
    end

    ---@return boolean ok
    ---@return string|nil err
    local function _requireLegendGachaMutate()
        if LegendGachaCloud.hasPendingConflict() then
            return false, YouthManager.LEGEND_CLOUD_CONFLICT
        end
        if LegendGachaCloud.isEnabled() and not LegendGachaCloud.canMutate() then
            return false, YouthManager.LEGEND_CLOUD_SYNCING
        end
        return true
    end

    --- 获取抽卡状态
    ---@param gameState table
    ---@return table state
    function YouthManager.getLegendGachaState(gameState)
        if LegendGachaCloud.hasPendingConflict() then
            return LegendGachaCloud.getSaveMirror(gameState)
        end
        if LegendGachaCloud.isEnabled() then
            local cloudState = LegendGachaCloud.tryGetState()
            if LegendGachaCloud.isReady() and not LegendGachaCloud.hasPendingConflict() then
                LegendGachaCloud.syncMirrorToSave(gameState, cloudState)
                return cloudState
            end
            return LegendGachaCloud.getSaveMirror(gameState)
        end

        return LegendGachaCloud.getSaveMirror(gameState)
    end

    --- 是否已领取当前轮次的传奇抽卡补偿（300抽）
    --- 旧版领3球员曾用 compensationClaimed=true 或 compensationClaimedRound="2.5"，均不阻塞本活动
    ---@param state table|nil
    ---@return boolean
    function YouthManager.hasClaimedLegendGachaCompensation(state)
        if not state then return false end
        if state.compensation300PullClaimed == true then
            return true
        end
        return state.compensationClaimedRound == Constants.LEGEND_GACHA_COMPENSATION_ROUND
    end

    --- 全部叙事标签池定义
    ---@return table[]
    function YouthManager.getLegendTagPools()
        return LegendTagPools.getAllPools()
    end

    --- 当前选中的标签池 id
    ---@param gameState table
    ---@return string poolId
    function YouthManager.getSelectedLegendPoolId(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        return state.selectedPoolId
    end

    --- 当前选中的标签池详情
    ---@param gameState table
    ---@return table|nil
    function YouthManager.getSelectedLegendPool(gameState)
        return LegendTagPools.getPool(YouthManager.getSelectedLegendPoolId(gameState))
    end

    --- 切换标签池（解锁后可随时切换，不消耗次数）
    ---@param gameState table
    ---@param poolId string
    ---@return boolean ok
    function YouthManager.setSelectedLegendPool(gameState, poolId)
        local okMutate = _requireLegendGachaMutate()
        if not okMutate then return false end
        if not LegendTagPools.isValidPoolId(poolId) then
            return false
        end
        local state = YouthManager.getLegendGachaState(gameState)
        state.selectedPoolId = poolId
        LegendGachaCloud.markDirty(gameState)
        return true
    end

    ---@param state table gacha state
    ---@return table set
    local function _getPulledLegendSet(state)
        local set = {}
        for _, id in ipairs(state.pulledLegendIds or {}) do
            set[id] = true
        end
        for _, name in ipairs(state.pulledLegends or {}) do
            set[name] = true
        end
        return set
    end

    ---@param set table
    ---@param lData table
    ---@return boolean
    local function _isLegendPulled(set, lData)
        if lData.id and set[lData.id] then return true end
        local key = lData.full_name_cn or lData.match_name
        return key and set[key] or false
    end

    local function _markLegendKeys(set, legendData, legendName)
        if type(legendData) == "table" and legendData.id then set[legendData.id] = true end
        if legendName then set[legendName] = true end
    end

    --- 云账本 + 当前存档已有传奇实体/候选。仅用于本地互斥，不写回云端。
    ---@param gameState table
    ---@param state table
    ---@return table set
    local function _getEffectiveLegendSet(gameState, state)
        local set = _getPulledLegendSet(state)
        if not gameState then return set end

        for _, p in pairs(gameState.players or {}) do
            if type(p) == "table" and p.isLegend then
                _markLegendKeys(set, p.legendData, p.legendName)
            end
        end
        for _, c in ipairs(gameState._youthCandidates or {}) do
            if type(c) == "table" and c.isLegend then
                _markLegendKeys(set, c.legendData, c.legendName)
            end
        end
        return set
    end

    ---@param state table
    ---@param lData table
    local function _markLegendPulled(state, lData)
        if lData.id then
            local dup = false
            for _, id in ipairs(state.pulledLegendIds) do
                if id == lData.id then dup = true break end
            end
            if not dup then
                table.insert(state.pulledLegendIds, lData.id)
            end
        end
        local key = lData.full_name_cn or lData.match_name or "传奇"
        local nameDup = false
        for _, name in ipairs(state.pulledLegends) do
            if name == key then nameDup = true break end
        end
        if not nameDup then
            table.insert(state.pulledLegends, key)
        end
    end

    --- 某标签池收集进度
    ---@param gameState table
    ---@param poolId string|nil 默认当前池
    ---@return table { total, remaining, collected, exhausted }
    function YouthManager.getLegendPoolProgress(gameState, poolId)
        poolId = poolId or YouthManager.getSelectedLegendPoolId(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        local pulledSet = _getEffectiveLegendSet(gameState, state)
        local members = LegendTagPools.getPoolPlayers(poolId)
        local remaining = 0
        for _, p in ipairs(members) do
            if not _isLegendPulled(pulledSet, p) then
                remaining = remaining + 1
            end
        end
        local total = #members
        return {
            total = total,
            remaining = remaining,
            collected = total - remaining,
            exhausted = total > 0 and remaining == 0,
        }
    end

    --- 某标签池全部成员及收集状态（供"查看名单"展示）
    ---@param gameState table
    ---@param poolId string|nil 默认当前池
    ---@return table[] list { data = legendData, collected = boolean }
    function YouthManager.getLegendPoolMembers(gameState, poolId)
        poolId = poolId or YouthManager.getSelectedLegendPoolId(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        local pulledSet = _getEffectiveLegendSet(gameState, state)
        local out = {}
        for _, p in ipairs(LegendTagPools.getPoolPlayers(poolId)) do
            table.insert(out, {
                data = p,
                collected = _isLegendPulled(pulledSet, p),
            })
        end
        return out
    end

    --- 构建当前标签池可抽传奇列表（排除全局已拥有）
    ---@param gameState table
    ---@return table[] legendPool
    ---@return string poolId
    local function _buildLegendPoolForPull(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        local poolId = state.selectedPoolId
        local pulledSet = _getEffectiveLegendSet(gameState, state)
        local legendPool = {}
        for _, p in ipairs(LegendTagPools.getPoolPlayers(poolId)) do
            if not _isLegendPulled(pulledSet, p) then
                table.insert(legendPool, p)
            end
        end
        return legendPool, poolId
    end

    ---@param gameState table
    ---@param lData table
    ---@return table candidate
    local function _makeLegendCandidate(gameState, lData)
        local mappedPos = mapPosition(lData.position)
        local legendYouthMods = DifficultySettings.getYouthModifiers()
        local legendAge = randInt(legendYouthMods.legendMinAge, legendYouthMods.legendMaxAge)
        local legendOverall = randInt(legendYouthMods.legendOverallMin, legendYouthMods.legendOverallMax)
        local legendAttrs = YouthManager._generateLegendAttributes(mappedPos, legendOverall, lData)
        local preCalcOverall = Player.calculateOverallFromAttrs(mappedPos, legendAttrs)
        return {
            firstName = lData.full_name_cn or lData.match_name or "传奇",
            lastName = lData.full_name_cn or lData.match_name or "球星",
            displayName = lData.full_name_cn or lData.match_name or "传奇球星",
            nationality = Nationality.normalize(lData.football_nation or lData.nationality or "BRA"),
            birthYear = gameState.date.year - legendAge,
            position = mappedPos,
            potential = lData.potential or 95,
            overall = preCalcOverall,
            attributes = legendAttrs,
            age = legendAge,
            isLegend = true,
            legendName = lData.full_name_cn or lData.match_name,
            legendData = lData,
            legendTag = lData.legendTag or YouthManager.getSelectedLegendPoolId(gameState),
        }
    end

    --- 是否已收集该传奇（全局去重，跨标签池）
    ---@param gameState table
    ---@param lData table
    ---@return boolean
    function YouthManager.isLegendCollected(gameState, lData)
        local state = YouthManager.getLegendGachaState(gameState)
        return _isLegendPulled(_getEffectiveLegendSet(gameState, state), lData)
    end

    --- 标记传奇已收集（签入/补偿/抽卡后调用）
    ---@param gameState table
    ---@param lData table
    function YouthManager.markLegendCollected(gameState, lData)
        local okMutate, err = _requireLegendGachaMutate()
        if not okMutate then return false, err end
        local state = YouthManager.getLegendGachaState(gameState)
        _markLegendPulled(state, lData)
        LegendGachaCloud.markDirty(gameState)
        return true
    end

    -- 漏签补偿：传奇 JSON 索引（lazy）
    local _legendById = nil
    local _legendByName = nil

    local function _ensureLegendIndex()
        if _legendById then return end
        local LegendsLoader = require("scripts/data/legends_loader")
        _legendById = {}
        _legendByName = {}
        for _, p in ipairs(LegendsLoader.loadAllPlayers()) do
            if p.id then _legendById[p.id] = p end
            local name = p.full_name_cn or p.match_name
            if name then _legendByName[name] = p end
        end
    end

    --- 按 id 或中文名查找传奇 JSON 数据
    ---@param idOrName string
    ---@return table|nil lData
    function YouthManager.findLegendData(idOrName)
        if not idOrName or idOrName == "" then return nil end
        _ensureLegendIndex()
        return _legendById[idOrName] or _legendByName[idOrName]
    end

    ---@param set table
    ---@param lData table
    ---@return boolean
    local function _legendKeysPresent(set, lData)
        if lData.id and set[lData.id] then return true end
        local name = lData.full_name_cn or lData.match_name
        return name and set[name] or false
    end

    ---@param gameState table
    ---@return table set
    local function _collectLegendKeysFromPlayers(gameState)
        local set = {}
        for _, p in pairs(gameState.players or {}) do
            if p.isLegend then
                if p.legendData and p.legendData.id then set[p.legendData.id] = true end
                if p.legendName then set[p.legendName] = true end
            end
        end
        return set
    end

    ---@param gameState table
    ---@return table set
    local function _collectLegendKeysFromCandidates(gameState)
        local set = {}
        for _, c in ipairs(gameState._youthCandidates or {}) do
            if c.isLegend then
                if c.legendData and c.legendData.id then set[c.legendData.id] = true end
                if c.legendName then set[c.legendName] = true end
            end
        end
        return set
    end

    --- 已抽但未签入、且存档中无对应 Player 实体的传奇（漏签）
    ---@param gameState table
    ---@return table[] lData list
    function YouthManager.getOrphanedPulledLegends(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        local entityKeys = _collectLegendKeysFromPlayers(gameState)
        local pendingKeys = _collectLegendKeysFromCandidates(gameState)
        local seen = {}
        local out = {}

        local function tryAdd(lData)
            if not lData then return end
            local dedupeKey = lData.id or (lData.full_name_cn or lData.match_name)
            if not dedupeKey or seen[dedupeKey] then return end
            if _legendKeysPresent(entityKeys, lData) then return end
            if _legendKeysPresent(pendingKeys, lData) then return end
            seen[dedupeKey] = true
            table.insert(out, lData)
        end

        for _, id in ipairs(state.pulledLegendIds or {}) do
            tryAdd(YouthManager.findLegendData(id))
        end
        for _, name in ipairs(state.pulledLegends or {}) do
            tryAdd(YouthManager.findLegendData(name))
        end
        return out
    end

    --- 补签漏签传奇：重建候选并直接签入青训队
    ---@param gameState table
    ---@param lData table
    ---@return boolean ok
    ---@return string|nil err
    function YouthManager.reclaimOrphanedLegend(gameState, lData)
        if not lData then return false, "无效的传奇数据" end

        local stillOrphan = false
        for _, o in ipairs(YouthManager.getOrphanedPulledLegends(gameState)) do
            if lData.id and o.id == lData.id then
                stillOrphan = true
                break
            end
            local a = lData.full_name_cn or lData.match_name
            local b = o.full_name_cn or o.match_name
            if a and b and a == b then
                stillOrphan = true
                break
            end
        end
        if not stillOrphan then
            return false, "该传奇无需补签或已在候选/队中"
        end

        local candidate = _makeLegendCandidate(gameState, lData)
        gameState._youthCandidates = gameState._youthCandidates or {}
        table.insert(gameState._youthCandidates, candidate)
        local idx = #gameState._youthCandidates
        local ok, err = YouthManager.signCandidate(gameState, idx)
        if not ok then
            table.remove(gameState._youthCandidates, idx)
            return false, err
        end
        return true
    end

    --- 观看广告（解锁阶段）
    ---@param gameState table
    ---@return boolean unlocked 是否刚刚解锁
    ---@return number progress 当前进度
    function YouthManager.watchAdForUnlock(gameState)
        local okMutate, err = _requireLegendGachaMutate()
        if not okMutate then
            local s = YouthManager.getLegendGachaState(gameState)
            return false, s and s.adsWatched or 0, err
        end
        local state = YouthManager.getLegendGachaState(gameState)
        if state.unlocked then return false, LEGEND_UNLOCK_ADS end

        state.adsWatched = state.adsWatched + 1
        if state.adsWatched >= LEGEND_UNLOCK_ADS then
            state.unlocked = true
            -- 解锁赠送30连抽
            state.pulls = state.pulls + 30
            log:Write(LOG_INFO, "YouthManager: 传奇池已解锁，赠送30次抽取")
            LegendGachaCloud.markDirty(gameState)
            return true, state.adsWatched
        end
        LegendGachaCloud.markDirty(gameState)
        return false, state.adsWatched
    end

    --- 观看广告获得抽取次数（解锁后）
    --- 每次看广告+2次，看满3次后补满至10次
    ---@param gameState table
    ---@return number newPulls 本次新增次数
    function YouthManager.watchAdForPulls(gameState)
        local okMutate, err = _requireLegendGachaMutate()
        if not okMutate then return 0, err end
        local state = YouthManager.getLegendGachaState(gameState)
        if not state.unlocked then return 0 end

        state.pullAdProgress = (state.pullAdProgress or 0) + 1
        local added = LEGEND_PULL_PER_AD
        state.pulls = state.pulls + added

        -- 看满3次，额外奖励6次（本轮合计 3+3+3+6=15）
        if state.pullAdProgress >= LEGEND_TEN_PULL_ADS then
            local bonus = 6
            state.pulls = state.pulls + bonus
            added = added + bonus
            state.pullAdProgress = 0
        end
        LegendGachaCloud.markDirty(gameState)
        return added
    end

    --- 获取当前广告进度
    ---@param gameState table
    ---@return number progress 当前进度 (0~2)
    ---@return number total 总需广告数 (3)
    function YouthManager.getPullAdProgress(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        return state.pullAdProgress or 0, LEGEND_TEN_PULL_ADS
    end

    --- 是否可以进行十连抽
    ---@param gameState table
    ---@return boolean
    function YouthManager.canTenPull(gameState)
        local state = YouthManager.getLegendGachaState(gameState)
        return state.unlocked and state.pulls >= 10
    end

    --- 获取解锁所需广告次数
    function YouthManager.getUnlockAdsRequired()
        return LEGEND_UNLOCK_ADS
    end

    --- 获取十连抽所需广告次数
    function YouthManager.getTenPullAdsRequired()
        return LEGEND_TEN_PULL_ADS
    end

    --- 执行单抽：消耗1次抽取机会，在候选池中追加1名球员（可出传奇）
    ---@param gameState table
    ---@return table|nil candidate 生成的球员，nil表示次数不足
    function YouthManager.doSinglePull(gameState)
        local okMutate, err = _requireLegendGachaMutate()
        if not okMutate then return nil, err end
        local state = YouthManager.getLegendGachaState(gameState)
        if not state.unlocked or state.pulls < 1 then
            return nil
        end

        state.pulls = state.pulls - 1

        -- 单抽计数器（每10次单抽等效一次十连的保底进度）
        state.singlePullCounter = (state.singlePullCounter or 0) + 1
        if state.singlePullCounter >= 10 then
            state.singlePullCounter = 0
            state.pityCounter = state.pityCounter + 1
        end

        local team = gameState:getPlayerTeam()
        local facilityYouthBonus = 1.0
        if team then
            facilityYouthBonus = YouthManager._getTeamYouthFacilityBonus(gameState, team.id)
        end

        -- 判断是否出传奇
        local isLegend = false
        local isPity = (state.pityCounter >= LEGEND_PITY_COUNT)

        local legendPool = _buildLegendPoolForPull(gameState)

        if #legendPool > 0 then
            if isPity then
                isLegend = true
            elseif state.firstTenPull and LEGEND_FIRST_GUARANTEED and state.singlePullCounter == 0 then
                -- 首次保底：第10次单抽（刚归零时）触发
                isLegend = true
            else
                local rate = _legendRateForPityLevel(state.pityCounter)
                if Random() < rate then
                    isLegend = true
                end
            end
        end

        local candidate
        if isLegend and #legendPool > 0 then
            local idx = randInt(1, #legendPool)
            local lData = legendPool[idx]

            _markLegendPulled(state, lData)
            candidate = _makeLegendCandidate(gameState, lData)

            -- 出传奇重置保底
            state.pityCounter = 0
            state.singlePullCounter = 0
            if state.firstTenPull then
                state.firstTenPull = false
            end
        else
            local usedNames = team and YouthManager._collectYouthUsedNames(gameState, team.id) or {}
            candidate = YouthManager._generateYouthPlayer(
                gameState, facilityYouthBonus, usedNames, team and team.country)
        end

        -- 追加到当前候选池
        gameState._youthCandidates = gameState._youthCandidates or {}
        table.insert(gameState._youthCandidates, candidate)

        log:Write(LOG_INFO, string.format(
            "YouthManager: 单抽完成(%s)，池=%s，剩余%d次，保底计数%d",
            isLegend and "传奇" or "普通",
            state.selectedPoolId or "?",
            state.pulls, state.pityCounter))

        LegendGachaCloud.markDirty(gameState)
        return candidate
    end

    --- 执行十连抽：刷新候选池为10名球员，按概率出传奇
    ---@param gameState table
    ---@return table|nil results {candidates=候选列表, legendCount=出传奇数, isFirstTenPull=bool}
    function YouthManager.doTenPull(gameState)
        local okMutate, err = _requireLegendGachaMutate()
        if not okMutate then return nil, err end
        local state = YouthManager.getLegendGachaState(gameState)
        if not state.unlocked or state.pulls < 10 then
            return nil
        end

        state.pulls = state.pulls - 10
        state.tenPullCount = state.tenPullCount + 1
        state.pityCounter = state.pityCounter + 1
        -- 十连抽重置单抽计数器（十连直接推进保底，不累积零散单抽）
        state.singlePullCounter = 0

        local isFirst = state.firstTenPull
        local isPity = (state.pityCounter >= LEGEND_PITY_COUNT)

        local legendPool = _buildLegendPoolForPull(gameState)

        local team = gameState:getPlayerTeam()
        local facilityYouthBonus = 1.0
        if team then
            facilityYouthBonus = YouthManager._getTeamYouthFacilityBonus(gameState, team.id)
        end

        local candidates = {}
        local legendCount = 0
        local guaranteedSlot = 0  -- 保底传奇放在第几个位置
        local usedNames = team and YouthManager._collectYouthUsedNames(gameState, team.id) or {}

        -- 判断是否触发保底（前提：池中还有传奇可抽）
        if #legendPool > 0 then
            if isFirst and LEGEND_FIRST_GUARANTEED then
                guaranteedSlot = randInt(1, YouthManager.YOUTH_POOL_SIZE)
            elseif isPity then
                guaranteedSlot = randInt(1, YouthManager.YOUTH_POOL_SIZE)
            end
        end

        for i = 1, YouthManager.YOUTH_POOL_SIZE do
            local isLegend = false

            if i == guaranteedSlot then
                -- 保底位置必出传奇
                isLegend = true
            elseif legendCount < LEGEND_MAX_PER_PULL then
                -- 尚未出传奇时才按概率判定（每次十连最多1个传奇）
                local rate = _legendRateForPityLevel(state.pityCounter - 1)
                if Random() < rate then
                    isLegend = true
                end
            end

            if isLegend and #legendPool > 0 and legendCount < LEGEND_MAX_PER_PULL then
                -- 从当前标签池随机选一个并移除
                local idx = randInt(1, #legendPool)
                local lData = legendPool[idx]
                table.remove(legendPool, idx)  -- 本次十连内不重复

                _markLegendPulled(state, lData)

                local candidate = _makeLegendCandidate(gameState, lData)
                table.insert(candidates, candidate)
                usedNames[candidate.displayName] = true
                legendCount = legendCount + 1
            else
                -- 普通青训球员
                local candidate = YouthManager._generateYouthPlayer(
                    gameState, facilityYouthBonus, usedNames, team and team.country)
                table.insert(candidates, candidate)
            end
        end

        -- 更新保底计数
        if legendCount > 0 then
            state.pityCounter = 0  -- 出了传奇，重置保底
        end
        if isFirst then
            state.firstTenPull = false
        end

        -- 设置为当前候选池
        gameState._youthCandidates = candidates

        log:Write(LOG_INFO, string.format(
            "YouthManager: 十连抽完成，池=%s，出传奇%d名，累计十连%d次，保底计数%d",
            state.selectedPoolId or "?", legendCount, state.tenPullCount, state.pityCounter))

        LegendGachaCloud.markDirty(gameState)
        return {
            candidates = candidates,
            legendCount = legendCount,
            isFirstTenPull = isFirst,
            isPity = isPity,
        }
    end
end
