-- domain/team.lua
-- 球队数据模型

local Constants = require("scripts/app/constants")

local Team = {}
Team.__index = Team

-- 槽位表/ID 表：JSON 反序列化后键可能变字符串，统一为数字键
local function normalizeIntegerKeyTable(raw, valueAsNumber)
    if type(raw) ~= "table" then return {} end
    local out = {}
    for k, v in pairs(raw) do
        if v ~= nil then
            local numKey = tonumber(k)
            if numKey then
                out[numKey] = valueAsNumber and (tonumber(v) or v) or v
            end
        end
    end
    return out
end

local function cloneIdList(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for i, v in ipairs(raw) do
        out[i] = tonumber(v) or v
    end
    return out
end

local function normalizeSlotOffsets(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for k, v in pairs(raw) do
        local idx = tonumber(k) or k
        if type(v) == "table" then
            local dx = tonumber(v[1] or v.dx) or 0
            local dy = tonumber(v[2] or v.dy) or 0
            if dx ~= 0 or dy ~= 0 then
                out[idx] = { dx, dy }
            end
        end
    end
    return out
end

local function normalizeLineupPreset(preset)
    if type(preset) ~= "table" then return nil end
    return {
        formation = preset.formation or "4-4-2",
        formationVariant = preset.formationVariant,
        startingXI = normalizeIntegerKeyTable(preset.startingXI, true),
        benchIds = cloneIdList(preset.benchIds),
        slotRoles = normalizeIntegerKeyTable(preset.slotRoles),
        slotOffsets = normalizeSlotOffsets(preset.slotOffsets),
        customSlots = normalizeIntegerKeyTable(preset.customSlots),
        playerDuties = normalizeIntegerKeyTable(preset.playerDuties),
        captain = preset.captain and (tonumber(preset.captain) or preset.captain) or nil,
        penaltyTaker = preset.penaltyTaker and (tonumber(preset.penaltyTaker) or preset.penaltyTaker) or nil,
        freeKickTaker = preset.freeKickTaker and (tonumber(preset.freeKickTaker) or preset.freeKickTaker) or nil,
        cornerTaker = preset.cornerTaker and (tonumber(preset.cornerTaker) or preset.cornerTaker) or nil,
    }
end

local function tablesEqual(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then return false end
    end
    return true
end

local function idListsEqual(a, b)
    a = a or {}
    b = b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function slotOffsetsEqual(a, b)
    a = a or {}
    b = b or {}
    for k, v in pairs(a) do
        local bv = b[k]
        if not bv then return false end
        if (v[1] or v.dx or 0) ~= (bv[1] or bv.dx or 0) then return false end
        if (v[2] or v.dy or 0) ~= (bv[2] or bv.dy or 0) then return false end
    end
    for k, v in pairs(b) do
        if a[k] == nil and v ~= nil then return false end
    end
    return true
end

--- 捕获当前阵容状态快照（用于 A/B 方案）
function Team.captureLineupSnapshot(team)
    return {
        formation = team.formation or "4-4-2",
        formationVariant = team.formationVariant,
        startingXI = normalizeIntegerKeyTable(team.startingXI, true),
        benchIds = cloneIdList(team.benchIds),
        slotRoles = normalizeIntegerKeyTable(team.slotRoles),
        slotOffsets = normalizeSlotOffsets(team.slotOffsets),
        customSlots = normalizeIntegerKeyTable(team.customSlots),
        playerDuties = normalizeIntegerKeyTable(team.playerDuties),
        captain = team.captain,
        penaltyTaker = team.penaltyTaker,
        freeKickTaker = team.freeKickTaker,
        cornerTaker = team.cornerTaker,
    }
end

function Team.lineupSnapshotsEqual(a, b)
    if not a or not b then return false end
    if a.formation ~= b.formation then return false end
    if a.formationVariant ~= b.formationVariant then return false end
    if not tablesEqual(a.startingXI, b.startingXI) then return false end
    if not idListsEqual(a.benchIds, b.benchIds) then return false end
    if not tablesEqual(a.slotRoles or {}, b.slotRoles or {}) then return false end
    if not slotOffsetsEqual(a.slotOffsets or {}, b.slotOffsets or {}) then return false end
    if not tablesEqual(a.customSlots or {}, b.customSlots or {}) then return false end
    if not tablesEqual(a.playerDuties or {}, b.playerDuties or {}) then return false end
    if a.captain ~= b.captain then return false end
    if a.penaltyTaker ~= b.penaltyTaker then return false end
    if a.freeKickTaker ~= b.freeKickTaker then return false end
    if a.cornerTaker ~= b.cornerTaker then return false end
    return true
end

function Team.applyLineupSnapshot(team, snapshot)
    if not snapshot then return end
    team.formation = snapshot.formation or team.formation or "4-4-2"
    team.formationVariant = snapshot.formationVariant
    team.startingXI = normalizeIntegerKeyTable(snapshot.startingXI, true)
    team.benchIds = cloneIdList(snapshot.benchIds)
    team.slotRoles = normalizeIntegerKeyTable(snapshot.slotRoles)
    team.slotOffsets = normalizeSlotOffsets(snapshot.slotOffsets)
    team.customSlots = normalizeIntegerKeyTable(snapshot.customSlots)
    team.playerDuties = normalizeIntegerKeyTable(snapshot.playerDuties)
    team.captain = snapshot.captain
    team.penaltyTaker = snapshot.penaltyTaker
    team.freeKickTaker = snapshot.freeKickTaker
    team.cornerTaker = snapshot.cornerTaker
end

function Team.ensureLineupPresets(team)
    if not team.lineupPresets then
        local snap = Team.captureLineupSnapshot(team)
        team.lineupPresets = { A = snap, B = Team.captureLineupSnapshot(team) }
    end
    if not team.activeLineupPreset or not team.lineupPresets[team.activeLineupPreset] then
        team.activeLineupPreset = "A"
    end
end

function Team.saveActiveLineupPreset(team)
    Team.ensureLineupPresets(team)
    team.lineupPresets[team.activeLineupPreset] = Team.captureLineupSnapshot(team)
end

function Team.switchLineupPreset(team, presetKey)
    Team.ensureLineupPresets(team)
    if not team.lineupPresets[presetKey] then return false end
    team.activeLineupPreset = presetKey
    Team.applyLineupSnapshot(team, team.lineupPresets[presetKey])
    return true
end

function Team.isLineupPresetDirty(team)
    Team.ensureLineupPresets(team)
    local saved = team.lineupPresets[team.activeLineupPreset]
    return not Team.lineupSnapshotsEqual(Team.captureLineupSnapshot(team), saved)
end

--- 构建有效首发槽位表：保留健康球员，空槽/伤员槽按阵型位置选最佳替补
---@return table<integer, string|nil>
function Team.buildEffectiveStartingXI(gameState, team)
    local FormationShape = require("scripts/match/formation_shape")
    local PositionFit = require("scripts/domain/position_fit")
    local slots = FormationShape.getFormationSlots(team)
    local source = team.startingXI or {}
    local effective = {}
    local usedIds = {}

    for i = 1, 11 do
        local pid = source[i]
        local p = pid and gameState.players[pid]
        if p and not p.injured and not p.retired then
            effective[i] = pid
            usedIds[pid] = true
        end
    end

    for i = 1, 11 do
        if not effective[i] then
            local slotPos = slots[i] or "MID"
            local bestPid, bestScore = nil, -1
            for _, pid in ipairs(team.playerIds or {}) do
                if not usedIds[pid] then
                    local p = gameState.players[pid]
                    if p and not p.injured and not p.retired then
                        -- 门将槽仅允许门将补位，避免无门将时把中场填到 GK
                        if slotPos == "GK" and Constants.normalizePosition(p.position) ~= "GK" then
                            goto continueCandidate
                        end
                        local score = PositionFit.getPositionScore(p, slotPos)
                        if score > bestScore then
                            bestScore = score
                            bestPid = pid
                        end
                    end
                end
                ::continueCandidate::
            end
            if bestPid then
                effective[i] = bestPid
                usedIds[bestPid] = true
            end
        end
    end

    return effective
end

--- 将 buildEffectiveStartingXI 结果写回 team.startingXI
function Team.fillStartingGaps(gameState, team)
    local effective = Team.buildEffectiveStartingXI(gameState, team)
    team.startingXI = team.startingXI or {}
    for i = 1, 11 do
        team.startingXI[i] = effective[i]
    end
    return team.startingXI
end

function Team.new(data)
    local self = setmetatable({}, Team)
    -- 基础信息
    self.id = data.id or 0
    self.name = data.name or "Unknown"
    self.shortName = data.shortName or "UNK"
    self.city = data.city or ""
    self.country = data.country or "ENG"
    self.colors = data.colors or {primary = "#ffffff", secondary = "#000000"}
    self.jsonTeamId = data.jsonTeamId or nil
    self._generatedCountry = data._generatedCountry or nil
    self.iconPath = data.iconPath or nil
    self.stadiumName = data.stadiumName or "Stadium"
    self.stadiumCapacity = data.stadiumCapacity or 30000
    self.stadiumExpanding = data.stadiumExpanding or nil
    self.stadiumExpandWeeksLeft = data.stadiumExpandWeeksLeft or nil
    self.stadiumExpandTarget = data.stadiumExpandTarget or nil
    self.foundedYear = data.foundedYear or 1900

    -- 竞技
    self.reputation = data.reputation or 500
    self.formation = data.formation or "4-4-2"
    self.formationVariant = data.formationVariant or nil
    self.playStyle = data.playStyle or "Balanced"
    -- startingXI 按阵型槽位 1..11 索引，允许空洞（未填槽位）
    self.startingXI = normalizeIntegerKeyTable(data.startingXI, true)
    self.benchIds = normalizeIntegerKeyTable(data.benchIds, true)
    self.slotRoles = normalizeIntegerKeyTable(data.slotRoles)
    self.slotOffsets = normalizeSlotOffsets(data.slotOffsets)
    self.customSlots = normalizeIntegerKeyTable(data.customSlots)
    self.playerDuties = normalizeIntegerKeyTable(data.playerDuties)
    self.captain = data.captain or nil
    self.penaltyTaker = data.penaltyTaker or nil
    self.freeKickTaker = data.freeKickTaker or nil
    self.cornerTaker = data.cornerTaker or nil

    -- 阵容方案 A/B（俱乐部模式）
    self.activeLineupPreset = data.activeLineupPreset or "A"
    self.lineupPresets = nil
    if data.lineupPresets then
        self.lineupPresets = {}
        for key, preset in pairs(data.lineupPresets) do
            self.lineupPresets[key] = normalizeLineupPreset(preset)
        end
    end

    -- 财务
    self.balance = data.balance or 50000000          -- 默认5000万
    self.wageBudget = data.wageBudget or 1000000      -- 默认100万/周
    self.transferBudget = data.transferBudget or 25000000  -- 默认2500万
    self._baseWageBudget = data._baseWageBudget or nil
    self._financialScale = data._financialScale or nil
    self.seasonIncome = data.seasonIncome or 0
    self.seasonExpense = data.seasonExpense or 0
    self.incomeBreakdown = data.incomeBreakdown or {}
    self.transactions = data.transactions or {}
    self.facilities = data.facilities or { training = 1, medical = 1, scouting = 1 }
    self.ticketStrategy = data.ticketStrategy or nil
    self._lastMatchRevenue = data._lastMatchRevenue or nil
    self.transferList = data.transferList or {}

    -- 赞助合同（存档恢复）
    self.sponsorContracts = data.sponsorContracts or nil
    self.sponsorMonthlyTotal = data.sponsorMonthlyTotal or nil
    self.sponsorContractChosen = data.sponsorContractChosen or nil
    self.pendingSponsorOffers = data.pendingSponsorOffers or nil

    -- 联赛排名（由 League:syncTeamPositions 维护）
    self.leaguePosition = data.leaguePosition or nil

    -- 人员
    self.managerId = data.managerId or nil
    self.playerIds = data.playerIds or {}
    self.staffIds = data.staffIds or {}
    self._youthPlayerIds = data._youthPlayerIds or {}

    -- 训练
    self.trainingFocus = data.trainingFocus or "balanced"
    self.trainingIntensity = data.trainingIntensity or Constants.TRAINING_INTENSITY.MEDIUM
    -- 训练分组: { [groupName] = { focus = "attack", playerIds = {...} } }
    self.trainingGroups = data.trainingGroups or {}

    -- 赛季统计
    self.seasonStats = data.seasonStats or {
        wins = 0, draws = 0, losses = 0,
        goalsFor = 0, goalsAgainst = 0,
    }

    -- 历史
    self.history = data.history or {}
    self.recentForm = data.recentForm or {}  -- "W","D","L"
    self.monthlyStats = data.monthlyStats or nil
    self._lastMonthlyStats = data._lastMonthlyStats or nil

    -- 董事会 / 教练空缺
    self.boardObjective = data.boardObjective or nil
    self.boardSatisfaction = data.boardSatisfaction or nil
    self.boardWarnings = data.boardWarnings or 0
    self.managerVacant = data.managerVacant or false
    self.vacantSince = data.vacantSince or nil
    self._vacantDays = data._vacantDays or nil

    return self
end

-- 获取球队总工资
function Team:getTotalWages(gameState)
    local total = 0
    for _, pid in ipairs(self.playerIds) do
        local p = gameState.players[pid]
        if p then total = total + p.wage end
    end
    for _, sid in ipairs(self.staffIds) do
        local s = gameState.staff[sid]
        if s then total = total + s.wage end
    end
    return total
end

-- 获取打法中文名
function Team:getPlayStyleName()
    return Constants.PLAY_STYLE_NAMES[self.playStyle] or self.playStyle
end

--- 一线队注册上限（与 Constants.FIRST_TEAM_MAX 一致）
function Team.getFirstTeamMax()
    local Constants = require("scripts/app/constants")
    return Constants.FIRST_TEAM_MAX or 30
end

--- 一线队是否已达注册上限
function Team:isFirstTeamFull()
    return #self.playerIds >= Team.getFirstTeamMax()
end

--- AI 窗口期"卖弱换强"软超员上限（关窗收敛回 FIRST_TEAM_MAX）
function Team.getAISquadHardMax()
    local Constants = require("scripts/app/constants")
    return Constants.AI_SQUAD_HARD_MAX or 33
end

--- 是否已达 AI 软超员上限（AI 升级囤兵的天花板）
function Team:isAISquadHardFull()
    return #self.playerIds >= Team.getAISquadHardMax()
end

--- 玩家转会窗内软顶（先签后清缓冲，关窗前须减回 FIRST_TEAM_MAX）
function Team.getPlayerWindowSquadMax()
    local Constants = require("scripts/app/constants")
    return Constants.PLAYER_WINDOW_SQUAD_MAX or 33
end

-- 内联窗口判断（避免 require transfer_manager 造成循环依赖）
local function _isTransferWindowMonth(gameState)
    if not gameState or not gameState.date then return false end
    local m = gameState.date.month
    return (m >= 7 and m <= 8) or m == 1
end

--- 当前有效一线队上限：玩家在转会窗内享受软顶（33），其余一律常规上限（30）
--- @param gameState table|nil
--- @return number
function Team:getEffectiveSquadMax(gameState)
    if gameState and self.id == gameState.playerTeamId and _isTransferWindowMonth(gameState) then
        return Team.getPlayerWindowSquadMax()
    end
    return Team.getFirstTeamMax()
end

--- 按"有效上限"判断是否已满（玩家窗内 33、其余 30；对 AI 等价于 isFirstTeamFull）
--- @param gameState table|nil
--- @return boolean
function Team:isSquadFullFor(gameState)
    return #self.playerIds >= self:getEffectiveSquadMax(gameState)
end

--- 添加球员到一线队名单
--- @param opts table|nil { allowOverCap = boolean } 租借归队等少数场景可突破硬顶
--- @return boolean added 是否成功加入（已满或重复则 false / 已存在则 true）
function Team:addPlayer(playerId, opts)
    opts = opts or {}
    for _, pid in ipairs(self.playerIds) do
        if pid == playerId then return true end
    end
    if not opts.allowOverCap and #self.playerIds >= Team.getFirstTeamMax() then
        return false
    end
    table.insert(self.playerIds, playerId)
    return true
end

-- 移除球员
function Team:removePlayer(playerId)
    for i, pid in ipairs(self.playerIds) do
        if pid == playerId then
            table.remove(self.playerIds, i)
            -- startingXI 是阵型槽位表，移除球员时清空槽位，不压缩索引
            for slot, sid in pairs(self.startingXI or {}) do
                if sid == playerId then
                    self.startingXI[slot] = nil
                end
            end
            if self.benchIds then
                for j = #self.benchIds, 1, -1 do
                    if self.benchIds[j] == playerId then
                        table.remove(self.benchIds, j)
                    end
                end
            end
            return
        end
    end
end

-- 记录财务流水
function Team:addTransaction(type, amount, description, date)
    table.insert(self.transactions, {
        type = type,
        amount = amount,
        description = description,
        date = date
    })
    if amount > 0 then
        self.seasonIncome = self.seasonIncome + amount
    else
        self.seasonExpense = self.seasonExpense + math.abs(amount)
    end
    self.balance = self.balance + amount
end

-- 序列化
function Team:serialize()
    return {
        id = self.id,
        name = self.name,
        shortName = self.shortName,
        city = self.city,
        country = self.country,
        colors = self.colors,
        jsonTeamId = self.jsonTeamId,
        _generatedCountry = self._generatedCountry,
        iconPath = self.iconPath,
        stadiumName = self.stadiumName,
        stadiumCapacity = self.stadiumCapacity,
        stadiumExpanding = self.stadiumExpanding,
        stadiumExpandWeeksLeft = self.stadiumExpandWeeksLeft,
        stadiumExpandTarget = self.stadiumExpandTarget,
        foundedYear = self.foundedYear,
        reputation = self.reputation,
        formation = self.formation,
        formationVariant = self.formationVariant,
        playStyle = self.playStyle,
        startingXI = self.startingXI,
        benchIds = self.benchIds,
        slotRoles = self.slotRoles,
        slotOffsets = self.slotOffsets,
        customSlots = self.customSlots,
        playerDuties = self.playerDuties,
        captain = self.captain,
        penaltyTaker = self.penaltyTaker,
        freeKickTaker = self.freeKickTaker,
        cornerTaker = self.cornerTaker,
        activeLineupPreset = self.activeLineupPreset,
        lineupPresets = self.lineupPresets,
        balance = self.balance,
        wageBudget = self.wageBudget,
        transferBudget = self.transferBudget,
        _baseWageBudget = self._baseWageBudget,
        _financialScale = self._financialScale,
        seasonIncome = self.seasonIncome,
        seasonExpense = self.seasonExpense,
        incomeBreakdown = self.incomeBreakdown,
        transactions = self.transactions,
        facilities = self.facilities,
        ticketStrategy = self.ticketStrategy,
        _lastMatchRevenue = self._lastMatchRevenue,
        transferList = self.transferList,
        sponsorContracts = self.sponsorContracts,
        sponsorMonthlyTotal = self.sponsorMonthlyTotal,
        sponsorContractChosen = self.sponsorContractChosen,
        pendingSponsorOffers = self.pendingSponsorOffers,
        leaguePosition = self.leaguePosition,
        managerId = self.managerId,
        playerIds = self.playerIds,
        staffIds = self.staffIds,
        trainingFocus = self.trainingFocus,
        trainingIntensity = self.trainingIntensity,
        trainingGroups = self.trainingGroups,
        seasonStats = self.seasonStats,
        history = self.history,
        recentForm = self.recentForm,
        monthlyStats = self.monthlyStats,
        _lastMonthlyStats = self._lastMonthlyStats,
        _youthPlayerIds = self._youthPlayerIds,
        boardObjective = self.boardObjective,
        boardSatisfaction = self.boardSatisfaction,
        boardWarnings = self.boardWarnings,
        managerVacant = self.managerVacant,
        vacantSince = self.vacantSince,
        _vacantDays = self._vacantDays,
    }
end

return Team
