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
    if not tablesEqual(a.slotOffsets or {}, b.slotOffsets or {}) then return false end
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

-- 添加球员
function Team:addPlayer(playerId)
    for _, pid in ipairs(self.playerIds) do
        if pid == playerId then return end
    end
    table.insert(self.playerIds, playerId)
end

-- 移除球员
function Team:removePlayer(playerId)
    for i, pid in ipairs(self.playerIds) do
        if pid == playerId then
            table.remove(self.playerIds, i)
            -- 从首发中移除
            for j, sid in ipairs(self.startingXI) do
                if sid == playerId then
                    table.remove(self.startingXI, j)
                    break
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
