-- match/match_session.lua
-- 比赛会话状态对象 - 支持步进式模拟和中场指令

local TacticsResolver = require("scripts/match/tactics_resolver")

---@class MatchSession
local MatchSession = {}
MatchSession.__index = MatchSession

--- 比赛阶段枚举
MatchSession.PHASE = {
    PRE_KICK_OFF = "pre_kick_off",
    FIRST_HALF = "first_half",
    HALF_TIME = "half_time",
    SECOND_HALF = "second_half",
    FULL_TIME = "full_time",
    EXTRA_FIRST = "extra_first",
    EXTRA_HALF_TIME = "extra_half_time",
    EXTRA_SECOND = "extra_second",
    PENALTIES = "penalties",
    FINISHED = "finished",
}

--- 指令类型枚举
MatchSession.COMMAND = {
    SUBSTITUTE = "substitute",
    CHANGE_PLAY_STYLE = "change_play_style",
    CHANGE_FORMATION = "change_formation",
    CHANGE_INSTRUCTION = "change_instruction",
}

local function cloneStartingXI(xi)
    if not xi then return {} end
    local copy = {}
    for k, v in pairs(xi) do
        if type(k) == "number" and v then
            copy[k] = v
        end
    end
    return copy
end

local function snapshotContextIds(players)
    local ids = {}
    for _, p in ipairs(players or {}) do
        ids[#ids + 1] = p.id
    end
    return ids
end

function MatchSession._cloneStartingXI(xi)
    return cloneStartingXI(xi)
end

function MatchSession._initLineupTracking(self, homeTeam, awayTeam, homeContext, awayContext)
    self.kickoffStartingXI = {
        home = cloneStartingXI(homeTeam and homeTeam.startingXI),
        away = cloneStartingXI(awayTeam and awayTeam.startingXI),
    }
    self.shadowLineup = {
        home = cloneStartingXI(homeTeam and homeTeam.startingXI),
        away = cloneStartingXI(awayTeam and awayTeam.startingXI),
    }
    self.appearanceIds = { home = {}, away = {} }
    for _, p in ipairs(homeContext.players or {}) do
        self.appearanceIds.home[p.id] = true
    end
    for _, p in ipairs(awayContext.players or {}) do
        self.appearanceIds.away[p.id] = true
    end
    self.subbedOffIds = { home = {}, away = {} }
end

--- 赛后还原存档阵容（临场换人仅存在于 session，不写 permanent startingXI）
function MatchSession:restoreKickoffLineups()
    if self._isWC or not self.kickoffStartingXI then return end

    local homeTeam = self.gameState.teams[self.fixture.homeTeamId]
    local awayTeam = self.gameState.teams[self.fixture.awayTeamId]
    if homeTeam and self.kickoffStartingXI.home then
        homeTeam.startingXI = cloneStartingXI(self.kickoffStartingXI.home)
    end
    if awayTeam and self.kickoffStartingXI.away then
        awayTeam.startingXI = cloneStartingXI(self.kickoffStartingXI.away)
    end
end

--- 创建新比赛会话
---@param gameState table
---@param fixture table
---@return MatchSession|nil
function MatchSession.new(gameState, fixture)
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    if not homeTeam or not awayTeam then return nil end

    local homeContext = TacticsResolver.buildTeamContext(gameState, homeTeam)
    local awayContext = TacticsResolver.buildTeamContext(gameState, awayTeam)
    if #homeContext.players == 0 or #awayContext.players == 0 then return nil end

    local self = setmetatable({}, MatchSession)

    self.gameState = gameState
    self.fixture = fixture
    self.homeContext = homeContext
    self.awayContext = awayContext

    -- 比赛状态
    self.phase = MatchSession.PHASE.PRE_KICK_OFF
    self.currentMinute = 0
    self.events = {}

    -- 比分 & 统计
    self.homeGoals = 0
    self.awayGoals = 0
    self.homeShots = 0
    self.awayShots = 0
    self.homeShotsOnTarget = 0
    self.awayShotsOnTarget = 0
    self.homeFouls = 0
    self.awayFouls = 0
    self.homePossessionTicks = 0
    self.totalPossessionTicks = 0

    -- 换人和战术记录（仅玩家球队）
    self.substitutions = {}
    self.subsRemaining = 3
    self.tacticalInstruction = "balanced"

    -- 替补名单
    self.bench = self:_buildBench(gameState, homeTeam, awayTeam)

    -- 跟踪被换下的球员（从 context.players 中移除）
    self.removedPlayerIds = { home = {}, away = {} }
    MatchSession._initLineupTracking(self, homeTeam, awayTeam, homeContext, awayContext)

    local EventFlavors = require("scripts/match/event_flavors")
    self._seasonDaysRemaining = EventFlavors.estimateSeasonDaysRemaining(gameState)

    return self
end

--- 创建世界杯比赛会话（国家队虚拟对象）
---@param gameState table
---@param fixture table
---@return MatchSession|nil
function MatchSession.newWC(gameState, fixture)
    local WorldCup = require("scripts/systems/world_cup")

    -- 用 WorldCup 构建虚拟国家队对象
    local homeTeam = WorldCup.buildNationalTeam(gameState, fixture.homeTeamId)
    local awayTeam = WorldCup.buildNationalTeam(gameState, fixture.awayTeamId)
    if not homeTeam or not awayTeam then return nil end

    local homeContext = TacticsResolver.buildTeamContext(gameState, homeTeam)
    local awayContext = TacticsResolver.buildTeamContext(gameState, awayTeam)
    if #homeContext.players == 0 or #awayContext.players == 0 then return nil end

    local self = setmetatable({}, MatchSession)

    self.gameState = gameState
    self.fixture = fixture
    self.homeContext = homeContext
    self.awayContext = awayContext
    self._isWC = true
    self._wcHomeTeam = homeTeam
    self._wcAwayTeam = awayTeam

    -- 比赛状态
    self.phase = MatchSession.PHASE.PRE_KICK_OFF
    self.currentMinute = 0
    self.events = {}

    -- 比分 & 统计
    self.homeGoals = 0
    self.awayGoals = 0
    self.homeShots = 0
    self.awayShots = 0
    self.homeShotsOnTarget = 0
    self.awayShotsOnTarget = 0
    self.homeFouls = 0
    self.awayFouls = 0
    self.homePossessionTicks = 0
    self.totalPossessionTicks = 0

    -- 换人和战术记录（玩家国家队）
    self.substitutions = {}
    self.subsRemaining = 3
    self.tacticalInstruction = "balanced"

    -- 替补名单（玩家国家队的替补）
    local playerNation = WorldCup._getPlayerNation(gameState)
    local playerTeam = (fixture.homeTeamId == playerNation) and homeTeam or awayTeam
    self.bench = self:_buildWCBench(gameState, playerTeam)

    -- 跟踪被换下的球员
    self.removedPlayerIds = { home = {}, away = {} }
    MatchSession._initLineupTracking(self, homeTeam, awayTeam, homeContext, awayContext)

    return self
end

--- 构建替补名单（玩家球队）
function MatchSession:_buildBench(gameState, homeTeam, awayTeam)
    local playerTeamId = gameState.playerTeamId
    local team = gameState.teams[playerTeamId]
    if not team then return {} end

    local startingSet = {}
    if team.startingXI then
        for _, pid in ipairs(team.startingXI or {}) do
            startingSet[pid] = true
        end
    end

    -- 如果有手动选择的替补席，优先使用
    if team.benchIds and #team.benchIds > 0 then
        local result = {}
        for _, pid in ipairs(team.benchIds) do
            local p = gameState.players[pid]
            if p and not p.injured and not startingSet[p.id] then
                table.insert(result, p)
            end
        end
        -- 手动列表中伤病球员自动补位（从剩余球员中选最强的）
        if #result < 7 then
            local usedSet = {}
            for _, r in ipairs(result) do usedSet[r.id] = true end
            local extras = {}
            for _, pid in ipairs(team.playerIds or {}) do
                local p = gameState.players[pid]
                if p and not p.injured and not startingSet[p.id] and not usedSet[p.id] then
                    table.insert(extras, p)
                end
            end
            table.sort(extras, function(a, b) return a.overall > b.overall end)
            for i = 1, math.min(7 - #result, #extras) do
                table.insert(result, extras[i])
            end
        end
        return result
    end

    -- 自动模式：按 overall 排序取前7
    local bench = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not startingSet[p.id] then
            table.insert(bench, p)
        end
    end
    table.sort(bench, function(a, b) return a.overall > b.overall end)

    local result = {}
    for i = 1, math.min(7, #bench) do
        table.insert(result, bench[i])
    end
    return result
end

--- 构建世界杯替补名单（国家队）
function MatchSession:_buildWCBench(gameState, nationalTeam)
    local bench = {}
    local startingSet = {}
    if nationalTeam.startingXI then
        for _, pid in ipairs(nationalTeam.startingXI) do
            startingSet[pid] = true
        end
    end

    for _, pid in ipairs(nationalTeam.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not p.retired and not startingSet[p.id] then
            table.insert(bench, p)
        end
    end
    table.sort(bench, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    -- 最多12名替补
    local result = {}
    for i = 1, math.min(12, #bench) do
        table.insert(result, bench[i])
    end
    return result
end

--- 获取当前模拟状态（用于传给 _simulateMinutes）
function MatchSession:_getSimState()
    return {
        events = self.events,
        homeGoals = self.homeGoals,
        awayGoals = self.awayGoals,
        homeShots = self.homeShots,
        awayShots = self.awayShots,
        homeShotsOnTarget = self.homeShotsOnTarget,
        awayShotsOnTarget = self.awayShotsOnTarget,
        homeFouls = self.homeFouls,
        awayFouls = self.awayFouls,
        homePossessionTicks = self.homePossessionTicks,
        totalPossessionTicks = self.totalPossessionTicks,
    }
end

--- 同步模拟状态回 session
function MatchSession:_syncSimState(state)
    self.homeGoals = state.homeGoals
    self.awayGoals = state.awayGoals
    self.homeShots = state.homeShots
    self.awayShots = state.awayShots
    self.homeShotsOnTarget = state.homeShotsOnTarget
    self.awayShotsOnTarget = state.awayShotsOnTarget
    self.homeFouls = state.homeFouls
    self.awayFouls = state.awayFouls
    self.homePossessionTicks = state.homePossessionTicks
    self.totalPossessionTicks = state.totalPossessionTicks
end

--- 步进模拟指定分钟数
---@param minutes number 要模拟的分钟数
---@return table newEvents 本次模拟产生的新事件
function MatchSession:stepMinutes(minutes)
    if self.phase == MatchSession.PHASE.FINISHED or
       self.phase == MatchSession.PHASE.PENALTIES then
        return {}
    end

    -- 如果还在赛前，先切换到上半场
    if self.phase == MatchSession.PHASE.PRE_KICK_OFF then
        self.phase = MatchSession.PHASE.FIRST_HALF
    end

    -- 如果在中场休息，切换到下半场
    if self.phase == MatchSession.PHASE.HALF_TIME then
        self.phase = MatchSession.PHASE.SECOND_HALF
    end

    -- 如果在加时中场，切换到加时下半场
    if self.phase == MatchSession.PHASE.EXTRA_HALF_TIME then
        self.phase = MatchSession.PHASE.EXTRA_SECOND
    end

    local eventsBefore = #self.events
    local targetMinute = self.currentMinute + minutes

    -- 确定本阶段的终点
    local phaseEnd = self:_getPhaseEndMinute()
    local actualTarget = math.min(targetMinute, phaseEnd)

    if actualTarget > self.currentMinute then
        local MatchEngine = require("scripts/match/match_engine")
        local state = self:_getSimState()
        local options = self:_getPhaseOptions()

        MatchEngine._simulateMinutes(
            self.fixture, self.homeContext, self.awayContext,
            self.currentMinute + 1, actualTarget, state, options
        )

        self:_syncSimState(state)
        self.currentMinute = actualTarget
    end

    -- 检查阶段转换
    self:_checkPhaseTransition()

    -- 返回新事件
    local newEvents = {}
    for i = eventsBefore + 1, #self.events do
        table.insert(newEvents, self.events[i])
    end
    return newEvents
end

--- 获取当前阶段的终止分钟
function MatchSession:_getPhaseEndMinute()
    if self.phase == MatchSession.PHASE.FIRST_HALF then
        return 45
    elseif self.phase == MatchSession.PHASE.SECOND_HALF then
        return 90
    elseif self.phase == MatchSession.PHASE.EXTRA_FIRST then
        return 105
    elseif self.phase == MatchSession.PHASE.EXTRA_SECOND then
        return 120
    end
    return self.currentMinute
end

--- 获取当前阶段的模拟选项
function MatchSession:_getPhaseOptions()
    local options
    if self.phase == MatchSession.PHASE.EXTRA_FIRST or
       self.phase == MatchSession.PHASE.EXTRA_SECOND then
        options = { phaseChance = 0.35, injuryChance = 0.0018 }
    else
        options = {}
    end
    options.allowSeasonEnding = true
    options.seasonDaysRemaining = self._seasonDaysRemaining
    if self.gameState and self.gameState.date then
        options.currentYear = self.gameState.date.year
    end
    return options
end

--- 检查阶段转换
function MatchSession:_checkPhaseTransition()
    if self.phase == MatchSession.PHASE.FIRST_HALF and self.currentMinute >= 45 then
        self.phase = MatchSession.PHASE.HALF_TIME
    elseif self.phase == MatchSession.PHASE.SECOND_HALF and self.currentMinute >= 90 then
        -- 淘汰赛平局 → 加时
        if self.fixture.isKnockout and self.homeGoals == self.awayGoals then
            self.phase = MatchSession.PHASE.EXTRA_FIRST
        else
            self.phase = MatchSession.PHASE.FULL_TIME
        end
    elseif self.phase == MatchSession.PHASE.EXTRA_FIRST and self.currentMinute >= 105 then
        self.phase = MatchSession.PHASE.EXTRA_HALF_TIME
    elseif self.phase == MatchSession.PHASE.EXTRA_SECOND and self.currentMinute >= 120 then
        if self.homeGoals == self.awayGoals then
            self.phase = MatchSession.PHASE.PENALTIES
        else
            self.phase = MatchSession.PHASE.FULL_TIME
        end
    end
end

--- 应用比赛指令
---@param command table { type, ... }
---@return boolean success
---@return string|nil error
function MatchSession:applyCommand(command)
    if not command or not command.type then
        return false, "invalid command"
    end

    if command.type == MatchSession.COMMAND.SUBSTITUTE then
        return self:_applySubstitution(command)
    elseif command.type == MatchSession.COMMAND.CHANGE_PLAY_STYLE then
        return self:_applyPlayStyleChange(command)
    elseif command.type == MatchSession.COMMAND.CHANGE_FORMATION then
        return self:_applyFormationChange(command)
    elseif command.type == MatchSession.COMMAND.CHANGE_INSTRUCTION then
        return self:_applyInstructionChange(command)
    end

    return false, "unknown command type: " .. tostring(command.type)
end

--- 执行换人
function MatchSession:_applySubstitution(command)
    if self.subsRemaining <= 0 then
        return false, "no substitutions remaining"
    end

    local offPlayerId = command.offPlayerId
    local onPlayerId = command.onPlayerId
    local teamId = command.teamId or self.gameState.playerTeamId

    if not offPlayerId or not onPlayerId then
        return false, "missing player ids"
    end

    -- 确定操作的 context
    local context, side
    if teamId == self.fixture.homeTeamId then
        context = self.homeContext
        side = "home"
    else
        context = self.awayContext
        side = "away"
    end

    -- 从场上移除
    local removed = false
    for i, p in ipairs(context.players) do
        if p.id == offPlayerId then
            table.remove(context.players, i)
            removed = true
            break
        end
    end
    if not removed then
        return false, "player not on pitch"
    end

    -- 添加替补球员到场上
    local onPlayer = self.gameState.players[onPlayerId]
    if not onPlayer then
        return false, "substitute player not found"
    end
    table.insert(context.players, onPlayer)

    -- 更新 shadow 槽位表（支持稀疏 startingXI；不修改存档中的 team.startingXI）
    if self.shadowLineup and self.shadowLineup[side] then
        for slot, pid in pairs(self.shadowLineup[side]) do
            if pid == offPlayerId then
                self.shadowLineup[side][slot] = onPlayerId
                if context.team and context.team.slotRoles then
                    context.team.slotRoles[slot] = nil
                end
                break
            end
        end
    end

    self.appearanceIds[side][onPlayerId] = true
    self.subbedOffIds[side][offPlayerId] = true
    self.removedPlayerIds[side][offPlayerId] = true

    -- 重新计算 context 的聚合值
    self:_recalculateContext(context, side)

    -- 记录换人
    self.subsRemaining = self.subsRemaining - 1
    local subEvent = {
        type = "substitution",
        minute = self.currentMinute,
        offPlayerId = offPlayerId,
        onPlayerId = onPlayerId,
        teamId = teamId,
    }
    table.insert(self.events, subEvent)
    table.insert(self.substitutions, subEvent)

    -- 从替补名单中移除上场球员
    for i, p in ipairs(self.bench) do
        if p.id == onPlayerId then
            table.remove(self.bench, i)
            break
        end
    end

    return true, nil
end

--- 切换比赛风格（playStyle）
function MatchSession:_applyPlayStyleChange(command)
    local newStyle = command.playStyle
    if not newStyle then return false, "missing playStyle" end

    local teamId = command.teamId or self.gameState.playerTeamId
    local context
    if teamId == self.fixture.homeTeamId then
        context = self.homeContext
    else
        context = self.awayContext
    end

    -- 更新 context 的 style
    context.style = newStyle
    local team = context.team
    if team then team.playStyle = newStyle end

    -- 重新计算
    local side = teamId == self.fixture.homeTeamId and "home" or "away"
    self:_recalculateContext(context, side)

    table.insert(self.events, {
        type = "tactical_change",
        minute = self.currentMinute,
        instruction = "style:" .. newStyle,
        teamId = teamId,
    })

    return true, nil
end

--- 切换阵型
function MatchSession:_applyFormationChange(command)
    local newFormation = command.formation
    if not newFormation then return false, "missing formation" end

    local teamId = command.teamId or self.gameState.playerTeamId
    local context
    if teamId == self.fixture.homeTeamId then
        context = self.homeContext
    else
        context = self.awayContext
    end

    local team = context.team
    if team then
        team.formation = newFormation
        -- 切阵型时重置变体为新阵型默认变体
        local Constants = require("scripts/app/constants")
        team.formationVariant = Constants.getDefaultVariant(newFormation)
    end

    local side = teamId == self.fixture.homeTeamId and "home" or "away"
    self:_recalculateContext(context, side)

    table.insert(self.events, {
        type = "tactical_change",
        minute = self.currentMinute,
        instruction = "formation:" .. newFormation,
        teamId = teamId,
    })

    return true, nil
end

--- 切换战术指示（进攻/防守倾向）
function MatchSession:_applyInstructionChange(command)
    local instruction = command.instruction
    if not instruction then return false, "missing instruction" end

    self.tacticalInstruction = instruction

    -- 将 instruction 映射为对 context 的实时修正
    local teamId = command.teamId or self.gameState.playerTeamId
    local context
    if teamId == self.fixture.homeTeamId then
        context = self.homeContext
    else
        context = self.awayContext
    end

    -- 应用实时修正因子
    local modifiers = {
        all_out_attack = { attack = 1.25, defense = 0.80 },
        attacking      = { attack = 1.12, defense = 0.93 },
        balanced       = { attack = 1.00, defense = 1.00 },
        defensive      = { attack = 0.90, defense = 1.12 },
        park_the_bus   = { attack = 0.75, defense = 1.25 },
        time_wasting   = { attack = 0.80, defense = 1.10, tempo = 0.75 },
    }

    local mod = modifiers[instruction] or modifiers.balanced
    context._instructionMod = mod

    table.insert(self.events, {
        type = "tactical_change",
        minute = self.currentMinute,
        instruction = instruction,
        teamId = teamId,
    })

    return true, nil
end

--- 重新计算 context 聚合属性（换人/战术变更后）
--- 采用渐变混合：30% 新值 + 70% 旧值，避免战术变更导致数值突变
function MatchSession:_recalculateContext(context, side)
    local team = context.team
    if not team then return end

    local savedXI = team.startingXI
    if self.shadowLineup and self.shadowLineup[side] then
        team.startingXI = self.shadowLineup[side]
    end

    -- 使用 shadow 阵容重算战术聚合，但保持当前场上球员列表
    local newCtx = TacticsResolver.buildTeamContext(self.gameState, team)
    team.startingXI = savedXI
    newCtx.players = context.players

    -- 渐变混合比例：30% 新值，70% 旧值（模拟球员需要时间适应新指令）
    local BLEND_NEW = 0.30
    local BLEND_OLD = 1.0 - BLEND_NEW

    local function blend(oldVal, newVal)
        if not oldVal then return newVal end
        if not newVal then return oldVal end
        return oldVal * BLEND_OLD + newVal * BLEND_NEW
    end

    context.attack = blend(context.attack, newCtx.attack)
    context.defense = blend(context.defense, newCtx.defense)
    context.possession = blend(context.possession, newCtx.possession)
    context.tempo = blend(context.tempo, newCtx.tempo)
    context.press = blend(context.press, newCtx.press)
    context.foulRate = blend(context.foulRate, newCtx.foulRate)
    context.injuryRisk = blend(context.injuryRisk, newCtx.injuryRisk)
    context.shotQuality = blend(context.shotQuality, newCtx.shotQuality)
    context.aerial = blend(context.aerial, newCtx.aerial)
    context.counter = blend(context.counter, newCtx.counter)
    context.chemistry = blend(context.chemistry, newCtx.chemistry)
    context.averageOverall = blend(context.averageOverall, newCtx.averageOverall)
    context.avgPlayerOverall = blend(context.avgPlayerOverall, newCtx.avgPlayerOverall)

    -- 应用战术指示修正
    if context._instructionMod then
        local mod = context._instructionMod
        context.attack = context.attack * (mod.attack or 1.0)
        context.defense = context.defense * (mod.defense or 1.0)
        if mod.tempo then context.tempo = context.tempo * mod.tempo end
    end
end

--- 执行点球大战
---@return table penaltyResult
function MatchSession:simulatePenalties()
    local MatchEngine = require("scripts/match/match_engine")
    local result = MatchEngine._simulatePenaltyShootout(self.homeContext, self.awayContext, self.fixture)
    self.phase = MatchSession.PHASE.FINISHED
    return result
end

--- 比赛是否结束
function MatchSession:isFinished()
    return self.phase == MatchSession.PHASE.FULL_TIME or
           self.phase == MatchSession.PHASE.FINISHED
end

--- 是否在中场休息
function MatchSession:isHalfTime()
    return self.phase == MatchSession.PHASE.HALF_TIME or
           self.phase == MatchSession.PHASE.EXTRA_HALF_TIME
end

--- 是否需要点球
function MatchSession:needsPenalties()
    return self.phase == MatchSession.PHASE.PENALTIES
end

--- 获取当前比分文本
function MatchSession:getScoreText()
    return string.format("%d - %d", self.homeGoals, self.awayGoals)
end

--- 获取当前比赛状态信息（供 UI 使用）
function MatchSession:getStatus()
    local phaseNames = {
        [MatchSession.PHASE.PRE_KICK_OFF] = "赛前",
        [MatchSession.PHASE.FIRST_HALF] = "上半场",
        [MatchSession.PHASE.HALF_TIME] = "中场休息",
        [MatchSession.PHASE.SECOND_HALF] = "下半场",
        [MatchSession.PHASE.FULL_TIME] = "已结束",
        [MatchSession.PHASE.EXTRA_FIRST] = "加时上半场",
        [MatchSession.PHASE.EXTRA_HALF_TIME] = "加时中场",
        [MatchSession.PHASE.EXTRA_SECOND] = "加时下半场",
        [MatchSession.PHASE.PENALTIES] = "点球大战",
        [MatchSession.PHASE.FINISHED] = "已结束",
    }
    return {
        phase = self.phase,
        phaseName = phaseNames[self.phase] or "未知",
        minute = self.currentMinute,
        homeGoals = self.homeGoals,
        awayGoals = self.awayGoals,
        subsRemaining = self.subsRemaining,
        instruction = self.tacticalInstruction,
    }
end

--- 构建最终报告（比赛结束后调用）
function MatchSession:buildReport()
    local MatchReport = require("scripts/match/match_report")

    local poisson = function(lambda)
        if lambda <= 0 then return 0 end
        local limit = math.exp(-lambda)
        local k = 0
        local p = 1
        repeat
            k = k + 1
            p = p * Random()
        until p <= limit
        return k - 1
    end

    local simState = {
        events = self.events,
        homeGoals = self.homeGoals,
        awayGoals = self.awayGoals,
        homeShots = self.homeShots,
        awayShots = self.awayShots,
        homeShotsOnTarget = self.homeShotsOnTarget,
        awayShotsOnTarget = self.awayShotsOnTarget,
        homeFouls = self.homeFouls,
        awayFouls = self.awayFouls,
        homePossessionTicks = self.homePossessionTicks,
        totalPossessionTicks = self.totalPossessionTicks,
        homePossession = self.totalPossessionTicks > 0
            and (self.homePossessionTicks / self.totalPossessionTicks) or 0.5,
        homeCorners = math.max(0, math.floor(self.homeShots * 0.28 + poisson(1.1))),
        awayCorners = math.max(0, math.floor(self.awayShots * 0.28 + poisson(1.0))),
    }

    -- 加时赛信息
    if self.fixture.isKnockout then
        local homeExtraGoals = 0
        local awayExtraGoals = 0
        for _, evt in ipairs(self.events) do
            if evt.type == "goal" and evt.minute > 90 then
                if evt.teamId == self.fixture.homeTeamId then
                    homeExtraGoals = homeExtraGoals + 1
                else
                    awayExtraGoals = awayExtraGoals + 1
                end
            end
        end
        if self.currentMinute > 90 then
            simState.extraTime = {
                played = true,
                homeExtraGoals = homeExtraGoals,
                awayExtraGoals = awayExtraGoals,
            }
            if self._penaltyResult then
                simState.extraTime.penalties = self._penaltyResult
            end
        end
    end

    return MatchReport.build(self.fixture, self.homeContext, self.awayContext, self.events, simState, {
        appearanceIds = self.appearanceIds,
        substitutions = self.substitutions,
        ratingLineup = {
            home = snapshotContextIds(self.homeContext.players),
            away = snapshotContextIds(self.awayContext.players),
        },
    })
end

return MatchSession
