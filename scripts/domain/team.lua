-- domain/team.lua
-- 球队数据模型

local Constants = require("scripts/app/constants")

local Team = {}
Team.__index = Team

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
    self.foundedYear = data.foundedYear or 1900

    -- 竞技
    self.reputation = data.reputation or 500
    self.formation = data.formation or "4-4-2"
    self.playStyle = data.playStyle or "Balanced"
    self.startingXI = data.startingXI or {}  -- 球员ID列表
    self.benchIds = data.benchIds or {}      -- 手动选择的替补席球员ID列表（空则自动计算）
    self.captain = data.captain or nil
    self.penaltyTaker = data.penaltyTaker or nil
    self.freeKickTaker = data.freeKickTaker or nil
    self.cornerTaker = data.cornerTaker or nil

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
        foundedYear = self.foundedYear,
        reputation = self.reputation,
        formation = self.formation,
        playStyle = self.playStyle,
        startingXI = self.startingXI,
        benchIds = self.benchIds,
        captain = self.captain,
        penaltyTaker = self.penaltyTaker,
        freeKickTaker = self.freeKickTaker,
        cornerTaker = self.cornerTaker,
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
        _youthPlayerIds = self._youthPlayerIds,
    }
end

return Team
