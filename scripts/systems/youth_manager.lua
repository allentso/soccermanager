-- systems/youth_manager.lua
-- 青训系统：青年球员刷新、签入、提拔至一线队

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

local YouthManager = {}
require("scripts/systems/youth/generation")(YouthManager)
require("scripts/systems/youth/legend_gacha")(YouthManager)
require("scripts/systems/youth/ai_monthly")(YouthManager)

local Helpers = require("scripts/systems/youth/youth_helpers")
local randInt = Helpers.randInt


------------------------------------------------------
-- 常量
------------------------------------------------------
local YOUTH_REFRESH_INTERVAL = 3   -- 每3个月刷新一批（processMonthly每月调用一次）
local YOUTH_POOL_SIZE = 10         -- 每次刷新10名候选
local MAX_YOUTH_SQUAD = 18         -- AI 球队青训上限
local MAX_YOUTH_SQUAD_PLAYER = 30  -- 玩家球队青训上限
local MAX_CUSTOM_YOUTH = 23        -- 玩家自建青训球员上限
local MAX_CUSTOM_YOUTH_NAME_CHARS = 12  -- 自建球员姓名上限（按字符计，非字节）
local INITIAL_YOUTH_COUNT = 10     -- 每队初始青训人数
local AI_TIER2_YOUTH_COUNT = 7     -- 次级 AI 队青训目标，降低长档球员总量
local YOUTH_MIN_AGE = 15
local YOUTH_MAX_AGE = 18
local YOUTH_WAGE = 500             -- 青训球员固定周薪

-- AI 自动提拔 OVR 门槛（按球队声望）
local AI_PROMOTE_MIN_OVR_BY_REP = {
    { minRep = 900, ovr = 70 },
    { minRep = 800, ovr = 65 },
    { minRep = 700, ovr = 60 },
    { minRep = 620, ovr = 57 },
    { minRep = 0,   ovr = 55 },
}
local AI_PROMOTE_HIGH_POT_90_AGE = 20
local AI_PROMOTE_HIGH_POT_85_AGE = 19
local AI_PROMOTE_GEM_MIN_OVR = 68   -- 潜力≥90 妖人最低即战力

-- 青训设施分层生成（Lv1~5；对外仍暴露 youthQuality 乘数，内部按等级查表）
YouthManager.YOUTH_FACILITY_TIERS = {
    -- 潜力三角分布 potLo / potMode / potHi（按声望档分级）：
    --   低声望(L1) = 低均值 + 高方差（多数平庸，偶出妖人，"搏一搏"）
    --   高声望(L5) = 高均值 + 低方差（稳定产出好苗，少出废品）
    -- floorLift：当前 OVR 下限微调（高声望青训"出道即更高"）
    { potLo = 42, potMode = 54, potHi = 88, floorLift = 0 },  -- L1 社区青训点
    { potLo = 45, potMode = 60, potHi = 90, floorLift = 1 },  -- L2 区级
    { potLo = 50, potMode = 67, potHi = 91, floorLift = 3 },  -- L3 市级
    { potLo = 56, potMode = 74, potHi = 92, floorLift = 5 },  -- L4 省级精英
    { potLo = 63, potMode = 81, potHi = 92, floorLift = 7 },  -- L5 国家级营
}

YouthManager.YOUTH_FACILITY_NAMES = {
    "社区青训点", "区级青训中心", "市级青训学院", "省级精英基地", "国家级青训营",
}

-- 导出常量供 UI 使用
YouthManager.MAX_YOUTH_SQUAD = MAX_YOUTH_SQUAD
YouthManager.MAX_YOUTH_SQUAD_PLAYER = MAX_YOUTH_SQUAD_PLAYER
YouthManager.MAX_CUSTOM_YOUTH = MAX_CUSTOM_YOUTH
YouthManager.YOUTH_POOL_SIZE = YOUTH_POOL_SIZE
YouthManager.INITIAL_YOUTH_COUNT = INITIAL_YOUTH_COUNT
YouthManager.AI_TIER2_YOUTH_COUNT = AI_TIER2_YOUTH_COUNT
YouthManager.YOUTH_REFRESH_INTERVAL = YOUTH_REFRESH_INTERVAL
YouthManager.YOUTH_WAGE = YOUTH_WAGE
YouthManager.YOUTH_MIN_AGE = YOUTH_MIN_AGE
YouthManager.YOUTH_MAX_AGE = YOUTH_MAX_AGE

--- 获取指定球队的青训名额上限（玩家 30，AI 18）
function YouthManager.getMaxYouthSquad(gameState, teamOrId)
    if not gameState then return MAX_YOUTH_SQUAD end
    local teamId = teamOrId
    if type(teamOrId) == "table" then
        teamId = teamOrId.id
    end
    if gameState.playerTeamId and teamId == gameState.playerTeamId then
        return MAX_YOUTH_SQUAD_PLAYER
    end
    return MAX_YOUTH_SQUAD
end

------------------------------------------------------
-- 青训名单辅助
------------------------------------------------------

--- 球员是否仍属于本队青训编制（含租借在外）
local function _belongsToYouthSquad(player, teamId)
    if not player then return false end
    return player.teamId == teamId or player._loanOriginTeamId == teamId
end

local function _isInFirstTeam(team, playerId)
    for _, pid in ipairs(team.playerIds or {}) do
        if pid == playerId then return true end
    end
    return false
end

local function _indexYouthRefs(team)
    local seen = {}
    for _, pid in ipairs(team._youthPlayerIds or {}) do
        seen[pid] = true
    end
    return seen
end

--- 球员是否在该队青训名单（含仅 _youthPlayerIds、未进一线队的情况）
---@param gameState table
---@param playerId number
---@param teamId number|nil
---@return boolean
function YouthManager.isOnTeamYouthSquad(gameState, playerId, teamId)
    if not gameState or not playerId or not teamId then return false end
    local team = gameState.teams[teamId]
    if not team then return false end
    for _, pid in ipairs(team._youthPlayerIds or {}) do
        if pid == playerId then return true end
    end
    return false
end

--- 已签入青训队、可走转会流程的球员（非 _youthCandidates）
---@param gameState table
---@param player table|nil
---@return boolean
function YouthManager.isYouthSquadPlayer(gameState, player)
    if not player or not player.isYouth or not player.teamId then return false end
    local team = gameState and gameState.teams and gameState.teams[player.teamId]
    if team then
        YouthManager.reconcileYouthRefsForTeam(gameState, team)
    end
    return YouthManager.isOnTeamYouthSquad(gameState, player.id, player.teamId)
end

--- 清除球队青训名单中的残留引用（与 Housekeeping.purgeStaleYouthRefs 规则对齐）
local function _purgeStaleYouthRefsForTeam(gameState, team)
    team._youthPlayerIds = team._youthPlayerIds or {}
    for i = #team._youthPlayerIds, 1, -1 do
        local pid = team._youthPlayerIds[i]
        local p = gameState.players[pid]
        local stillOurs = _belongsToYouthSquad(p, team.id)
        -- 已转会离队，或已是一线队球员（转会/提拔完成）→ 清除残留
        local alreadyFirstTeam = stillOurs and p and not p.isYouth and _isInFirstTeam(team, pid)
        if not stillOurs or alreadyFirstTeam then
            table.remove(team._youthPlayerIds, i)
        end
    end
end

--- 修复仍属于本队但缺失 _youthPlayerIds 引用的青训球员（旧版满员提拔失败会造成）
local function _restoreMissingYouthRefsForTeam(gameState, team)
    team._youthPlayerIds = team._youthPlayerIds or {}
    local seen = _indexYouthRefs(team)
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    local restored = 0

    for pid, player in pairs(gameState.players or {}) do
        local playerId = player.id or pid
        if not seen[playerId]
            and player.isYouth
            and _belongsToYouthSquad(player, team.id)
            and not _isInFirstTeam(team, playerId)
            and #team._youthPlayerIds < maxSquad then
            table.insert(team._youthPlayerIds, playerId)
            seen[playerId] = true
            restored = restored + 1
        end
    end

    return restored
end

function YouthManager.reconcileYouthRefsForTeam(gameState, team)
    if not gameState or not team then return 0 end
    _purgeStaleYouthRefsForTeam(gameState, team)
    return _restoreMissingYouthRefsForTeam(gameState, team)
end

function YouthManager.reconcileYouthRefs(gameState)
    if not gameState then return 0 end
    local restored = 0
    for _, team in pairs(gameState.teams or {}) do
        restored = restored + YouthManager.reconcileYouthRefsForTeam(gameState, team)
    end
    return restored
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每月处理：刷新青训候选池（玩家球队）+ AI 球队青训管理
---@param gameState table
function YouthManager.processMonthly(gameState)
    YouthManager.purgeOverageYouth(gameState)

    -- 玩家球队候选刷新
    gameState._youthCandidates = gameState._youthCandidates or {}
    gameState._youthRefreshCounter = (gameState._youthRefreshCounter or 0) + 1

    if gameState._youthRefreshCounter >= YOUTH_REFRESH_INTERVAL then
        gameState._youthRefreshCounter = 0
        YouthManager._refreshCandidates(gameState)
    end

    -- AI 球队青训管理（每月执行一次简化逻辑）
    YouthManager._processAITeamsMonthly(gameState)

    -- 青训在训球员工资随能力缓慢上调
    YouthManager.syncYouthAcademyWages(gameState)
end

--- 同步所有球队青训在训球员周薪
function YouthManager.syncYouthAcademyWages(gameState)
    for teamId, team in pairs(gameState.teams or {}) do
        for _, pid in ipairs(team._youthPlayerIds or {}) do
            local player = gameState.players[pid]
            if player and player.teamId == teamId then
                local newWage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)
                if newWage > (player.wage or 0) then
                    player.wage = newWage
                end
            end
        end
    end
end

--- 获取当前青训候选球员列表
---@param gameState table
---@return table[]
function YouthManager.getCandidates(gameState)
    return gameState._youthCandidates or {}
end

--- 签入候选青训球员
---@param gameState table
---@param candidateIndex number 候选列表中的索引
---@return boolean success, string? error
function YouthManager.signCandidate(gameState, candidateIndex)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    gameState._youthCandidates = gameState._youthCandidates or {}
    local candidate = gameState._youthCandidates[candidateIndex]
    if not candidate then return false, "候选球员不存在" end

    -- 青训名额检查
    team._youthPlayerIds = team._youthPlayerIds or {}
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    if #team._youthPlayerIds >= maxSquad then
        return false, string.format("青训名额已满(%d人)", maxSquad)
    end

    -- 创建球员实体（birthYear 必须保持为整数，不可被修改）
    -- 传奇球员自带专属特质（从 JSON 数据继承）
    local legendTraits = nil
    if candidate.isLegend and candidate.legendData and candidate.legendData.traits then
        legendTraits = candidate.legendData.traits
    end

    local playerData = {
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = Nationality.normalize(candidate.nationality),
        birthYear = math.floor(candidate.birthYear),
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = YOUTH_WAGE,
        isYouth = true,
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
        traits = legendTraits,
        -- 传奇球员额外字段
        isLegend = candidate.isLegend or false,
        legendName = candidate.legendName,
        legendData = candidate.legendData,
        legendTag = candidate.legendTag,
    }
    local player = gameState:addPlayer(playerData)

    -- 设置球队归属
    player.teamId = team.id
    player.wage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)

    -- 初始化潜力评级
    player.paRating = PotentialSystem.rawToRating(player.potential)
    player.actualPotential = PotentialSystem.generateActualPotential(player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)

    -- 加入青训队
    table.insert(team._youthPlayerIds, player.id)

    -- 从候选池移除
    table.remove(gameState._youthCandidates, candidateIndex)

    MessageManager.send(gameState, "youth_signed", {player.displayName, player.position})

    EventBus.emit("youth_signed", {teamId = team.id, playerId = player.id})
    return true
end

--- 提拔青训球员到一线队
---@param gameState table
---@param playerId number
---@return boolean success, string? error
function YouthManager.promote(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    -- 检查是否在青训队
    team._youthPlayerIds = team._youthPlayerIds or {}
    local youthIndex = nil
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == playerId then
            youthIndex = i
            break
        end
    end
    if not youthIndex then return false, "该球员不在青训队中" end

    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.listedForSale then return false, "请先取消挂牌出售" end
    if player.listedForLoan then return false, "请先取消外租挂牌" end

    -- 归属校验：防止残留引用误覆盖已转会球员的合同（BUG-20260611-06 玩家手动提拔路径）
    if player.teamId ~= team.id then
        return false, "该球员已不属于本队"
    end

    local alreadyFirstTeam = _isInFirstTeam(team, playerId)
    if not alreadyFirstTeam and team:isSquadFullFor(gameState) then
        return false, string.format("一线队已满员（最多 %d 人）", team:getEffectiveSquadMax(gameState))
    end
    table.remove(team._youthPlayerIds, youthIndex)
    if not alreadyFirstTeam then
        table.insert(team.playerIds, playerId)
    end

    player.isYouth = false
    player.teamId = team.id

    -- 已在一线队（如转会后残留引用）：仅清除青训身份，保留现有合同
    if not alreadyFirstTeam then
        player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
        player.wage = FinanceManager.estimateYouthPromoteWage(player, team, gameState)
        MessageManager.send(gameState, "youth_promoted", {player.displayName})
        EventBus.emit("youth_promoted", {teamId = team.id, playerId = playerId})
    end

    return true
end

--- 从首发/替补名单移除球员
local function _removeFromLineup(team, playerId)
    if team.startingXI then
        for slot, pid in pairs(team.startingXI) do
            if pid == playerId then team.startingXI[slot] = nil end
        end
    end
    if team.benchIds then
        for i = #team.benchIds, 1, -1 do
            if team.benchIds[i] == playerId then
                table.remove(team.benchIds, i)
            end
        end
    end
end

--- 检查一线队球员是否可下放至青训队
---@param gameState table
---@param playerId number
---@param teamId number|nil 默认玩家球队
---@return boolean ok
---@return string|nil error
function YouthManager.canDemoteToYouth(gameState, playerId, teamId)
    local team = teamId and gameState.teams[teamId] or gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end
    if player.teamId ~= team.id then return false, "该球员不属于本队" end
    if player.squadRole == "loaned" then return false, "外租中球员无法下放" end
    if player.isYouth or YouthManager.isOnTeamYouthSquad(gameState, playerId, team.id) then
        return false, "该球员已在青训队"
    end
    if not _isInFirstTeam(team, playerId) then return false, "该球员不在一线队" end

    local age = player:getAge(gameState.date.year)
    if age > Constants.YOUTH_PHASE_MAX_AGE then
        return false, string.format("%d岁以上球员无法下放至青训队", Constants.YOUTH_PHASE_MAX_AGE)
    end
    if player.isLegend then return false, "传奇球员无法下放至青训队" end
    if player.listedForSale then return false, "请先取消挂牌出售" end
    if player.listedForLoan then return false, "请先取消外租挂牌" end

    local TransferManager = require("scripts/systems/transfer_manager")
    if TransferManager.hasPendingIncomingBid(gameState, playerId) then
        return false, "该球员有活跃转会报价，请先处理"
    end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    if #team._youthPlayerIds >= maxSquad then
        return false, string.format("青训名额已满(%d人)", maxSquad)
    end

    local safe, reason = FinanceManager.checkSquadSafety(gameState, playerId)
    if not safe then return false, reason end

    return true, nil
end

--- 将一线队年轻球员下放至青训队（promote 的逆操作）
---@param gameState table
---@param playerId number
---@return boolean success, string|nil error
function YouthManager.demoteToYouth(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    local ok, err = YouthManager.canDemoteToYouth(gameState, playerId, team.id)
    if not ok then return false, err end

    local player = gameState.players[playerId]

    for i, pid in ipairs(team.playerIds) do
        if pid == playerId then
            table.remove(team.playerIds, i)
            break
        end
    end
    _removeFromLineup(team, playerId)

    team._youthPlayerIds = team._youthPlayerIds or {}
    table.insert(team._youthPlayerIds, playerId)

    player.isYouth = true
    player.squadRole = "youth"
    player.teamId = team.id
    player.wage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)
    player.listedForSale = false
    player.listedForLoan = false

    MessageManager.send(gameState, "youth_demoted", {player.displayName})
    EventBus.emit("youth_demoted", {teamId = team.id, playerId = playerId})

    return true
end

--- 释放青训球员
--- 潜力 raw >= 70 的球员保留为自由球员（可出现在转会市场）
--- 低潜力球员直接从数据库移除以防止数据膨胀
---@param gameState table
---@param playerId number
---@return boolean success, string? error
function YouthManager.release(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    team._youthPlayerIds = team._youthPlayerIds or {}
    local found = false
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == playerId then
            table.remove(team._youthPlayerIds, i)
            found = true
            break
        end
    end
    if not found then return false, "该球员不在青训队中" end

    local player = gameState.players[playerId]
    if player and player.teamId ~= team.id then
        return false, "该球员已不属于本队"
    end
    if player then
        if player.listedForSale then return false, "请先取消挂牌出售" end
        local TransferManager = require("scripts/systems/transfer_manager")
        if TransferManager.hasPendingIncomingBid(gameState, playerId) then
            TransferManager.delistPlayer(gameState, player)
        end

        player.listedForSale = false
        player.listedForLoan = false
        player.isYouth = false
        player.teamId = nil

        local rawPotential = player.potential or 0
        if rawPotential >= 70 then
            -- 有潜力的球员释放为自由球员，可出现在转会市场
            -- （自由球员池由 Housekeeping.purgeExcessFreeAgents 控制上限，防止泄漏膨胀）
            player.isFreeAgent = true
            player.releasedDate = {
                year = gameState.date.year,
                month = gameState.date.month,
                day = gameState.date.day,
            }
        else
            -- 低潜力球员直接移除，避免数据库膨胀
            gameState.players[playerId] = nil
        end
    end

    return true
end

--- 获取球队青训球员列表
---@param gameState table
---@return table[]
function YouthManager.getYouthSquad(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return {} end

    YouthManager.reconcileYouthRefsForTeam(gameState, team)

    team._youthPlayerIds = team._youthPlayerIds or {}
    local result = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p and p.isYouth and _belongsToYouthSquad(p, team.id) then
            table.insert(result, p)
        end
    end
    return result
end

--- 是否为自建青训球员
---@param player table|nil
---@return boolean
function YouthManager.isCustomYouthPlayer(player)
    return player ~= nil and player.isCustomYouth == true
end

--- 获取本队全部自建球员（含已提拔至一线队；名额按全队占用计，不因提拔释放）
---@param gameState table
---@return table[]
function YouthManager.getCustomYouthSquad(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return {} end

    local result = {}
    for _, p in pairs(gameState.players or {}) do
        if p.teamId == team.id and YouthManager.isCustomYouthPlayer(p) then
            table.insert(result, p)
        end
    end
    table.sort(result, function(a, b)
        if a.isYouth ~= b.isYouth then
            return a.isYouth == true
        end
        return (a.id or 0) < (b.id or 0)
    end)
    return result
end

--- 获取常规青训球员列表（不含自建）
---@param gameState table
---@return table[]
function YouthManager.getRegularYouthSquad(gameState)
    local result = {}
    for _, p in ipairs(YouthManager.getYouthSquad(gameState)) do
        if not YouthManager.isCustomYouthPlayer(p) then
            table.insert(result, p)
        end
    end
    return result
end

--- 获取自建青训名额上限
---@return number
function YouthManager.getMaxCustomYouthSlots()
    return MAX_CUSTOM_YOUTH
end

--- 自建球员姓名最大字符数
function YouthManager.getMaxCustomYouthNameChars()
    return MAX_CUSTOM_YOUTH_NAME_CHARS
end

--- TextField maxLength：引擎对中文按 2 单位计长，12 字需 24
function YouthManager.getCustomYouthNameInputLimit()
    return MAX_CUSTOM_YOUTH_NAME_CHARS * 2
end

local function _getCustomYouthAdState(gameState)
    gameState.customYouthAdState = gameState.customYouthAdState or {
        createUnlocks = 0,
        paBoosts = {},
    }
    gameState.customYouthAdState.paBoosts = gameState.customYouthAdState.paBoosts or {}
    gameState.customYouthAdState.createUnlocks = gameState.customYouthAdState.createUnlocks or 0
    return gameState.customYouthAdState
end

--- 是否可创建自建青训球员：第一名免费，之后每创建一名都需要先看一次广告
---@param gameState table
---@return boolean canCreate
---@return string|nil reason
function YouthManager.canCreateCustomYouthPlayer(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    local customCount = #YouthManager.getCustomYouthSquad(gameState)
    if customCount >= MAX_CUSTOM_YOUTH then
        return false, string.format("自建球员名额已满(%d人)", MAX_CUSTOM_YOUTH)
    end

    if customCount == 0 then
        return true
    end

    local state = _getCustomYouthAdState(gameState)
    if state.createUnlocks >= customCount then
        return true
    end
    return false, "观看广告后可继续创建下一名自建球员"
end

--- 观看广告后解锁下一次自建球员创建资格
---@param gameState table
---@return boolean success
function YouthManager.unlockNextCustomYouthCreate(gameState)
    local state = _getCustomYouthAdState(gameState)
    local customCount = #YouthManager.getCustomYouthSquad(gameState)
    state.createUnlocks = math.max(state.createUnlocks, customCount)
    return true
end

local function _ratingToRawPotential(paRating)
    local raw = 99
    for p = 30, 99 do
        if math.abs(PotentialSystem.rawToRating(p) - paRating) < 0.01 then
            raw = p
            break
        end
    end
    return raw
end

--- 观看广告提升自建球员 PA：PA Rating +0.5，最高 10.0
---@param gameState table
---@param player table
---@return boolean success
---@return table|string resultOrError
function YouthManager.boostCustomYouthPa(gameState, player)
    if not YouthManager.isCustomYouthPlayer(player) then
        return false, "只有自建球员可以通过广告提升潜力"
    end
    local currentRating = player.paRating or PotentialSystem.rawToRating(player.potential or player.actualPotential or 60)
    if currentRating >= 10.0 then
        return false, "该球员潜力已达到上限"
    end

    local oldRating = currentRating
    local newRating = math.min(10.0, currentRating + 0.5)
    local oldActual = player.actualPotential or player.potential or 60
    player.paRating = newRating
    player.potential = math.max(player.potential or 0, _ratingToRawPotential(newRating))

    local state = _getCustomYouthAdState(gameState)
    state.paBoosts[tostring(player.id)] = (state.paBoosts[tostring(player.id)] or 0) + 1
    local seed = (gameState.potentialSeed or 0) + player.id * 7919 + state.paBoosts[tostring(player.id)] * 104729
    local newActual = PotentialSystem.generateActualPotential(newRating, seed)
    player.actualPotential = math.max(oldActual, newActual)

    return true, {
        oldRating = oldRating,
        newRating = newRating,
        oldActual = oldActual,
        newActual = player.actualPotential,
    }
end

--- 创建自建青训球员
---@param gameState table
---@param opts table { displayName: string, position?: string, nationality?: string }
---@return boolean success, table|string resultOrError
function YouthManager.createCustomYouthPlayer(gameState, opts)
    opts = opts or {}
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    local canCreate, reason = YouthManager.canCreateCustomYouthPlayer(gameState)
    if not canCreate then
        return false, reason or string.format("自建球员名额已满(%d人)", MAX_CUSTOM_YOUTH)
    end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local maxSquad = YouthManager.getMaxYouthSquad(gameState, team)
    if #team._youthPlayerIds >= maxSquad then
        return false, string.format("青训名额已满(%d人)", maxSquad)
    end

    local displayName = tostring(opts.displayName or ""):match("^%s*(.-)%s*$") or ""
    if displayName == "" then
        return false, "请输入球员姓名"
    end
    if TextUtil.utf8Len(displayName) > MAX_CUSTOM_YOUTH_NAME_CHARS then
        return false, string.format("姓名不能超过%d字", MAX_CUSTOM_YOUTH_NAME_CHARS)
    end
    if TextUtil.containsSensitiveNameWord(displayName) then
        return false, "姓名包含敏感词，请更换后再试"
    end

    local position = Constants.normalizePosition(opts.position) or "ST"
    if not opts.nationality or tostring(opts.nationality) == "" then
        return false, "请选择国籍"
    end
    local nationality = Nationality.normalize(opts.nationality)

    local facilityYouthBonus = YouthManager._getTeamYouthFacilityBonus(gameState, team.id)
    local usedNames = YouthManager._collectYouthUsedNames(gameState, team.id)
    local candidate = YouthManager._generateYouthPlayer(
        gameState,
        facilityYouthBonus,
        usedNames,
        team.country,
        position,
        { displayName = displayName, nationality = nationality }
    )

    local playerData = {
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = displayName,
        nationality = candidate.nationality,
        birthYear = candidate.birthYear,
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = YOUTH_WAGE,
        isYouth = true,
        isCustomYouth = true,
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
    }
    local player = gameState:addPlayer(playerData)
    player.teamId = team.id
    player.wage = FinanceManager.estimateYouthAcademyWage(player, team, gameState)
    player.paRating = PotentialSystem.rawToRating(player.potential)
    player.actualPotential = PotentialSystem.generateActualPotential(
        player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)

    table.insert(team._youthPlayerIds, player.id)
    MessageManager.send(gameState, "youth_signed", {player.displayName, player.position})
    return true, player
end

--- 确定青训球员的训练焦点（复用 TrainingManager 优先级链）
--- 优先级：player.trainingFocus > team.trainingGroups 分组 > team.trainingFocus > "balanced"
---@param team table
---@param player table
---@return string focusKey
local function _resolveYouthFocus(team, player)
    -- 1. 个人训练焦点（UI "个人训练"页面设置）
    if player.trainingFocus and TrainingManager.FOCUS_ATTRS[player.trainingFocus] then
        return player.trainingFocus
    end
    -- 2. 分组训练焦点（UI "分组训练"页面设置）
    if team.trainingGroups then
        for _, group in pairs(team.trainingGroups) do
            if group.playerIds then
                for _, pid in ipairs(group.playerIds) do
                    if pid == player.id then
                        if group.focus and TrainingManager.FOCUS_ATTRS[group.focus] then
                            return group.focus
                        end
                    end
                end
            end
        end
    end
    -- 3. 全队训练焦点（UI "全队训练"页面设置）
    if team.trainingFocus and TrainingManager.FOCUS_ATTRS[team.trainingFocus] then
        return team.trainingFocus
    end
    -- 4. 默认平衡训练
    return "balanced"
end

--- 22+ 仍在青训名单：自动解约并删库 / 转自由球员（全队含 AI）
---@param gameState table
---@return number purged
function YouthManager.purgeOverageYouth(gameState)
    local seasonYear = TrainingManager.getSeasonStartYear(gameState)
    local purged = 0

    for _, team in pairs(gameState.teams or {}) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        for i = #team._youthPlayerIds, 1, -1 do
            local pid = team._youthPlayerIds[i]
            local player = gameState.players[pid]
            if player and player:getAge(seasonYear) > Constants.YOUTH_PHASE_MAX_AGE then
                table.remove(team._youthPlayerIds, i)
                player.isYouth = false
                player.teamId = nil
                player.contractEnd = nil
                player.wage = 0

                local rawPotential = player.potential or 0
                if rawPotential >= 70 then
                    player.isFreeAgent = true
                    player.releasedDate = {
                        year = gameState.date.year,
                        month = gameState.date.month,
                        day = gameState.date.day,
                    }
                else
                    gameState.players[pid] = nil
                end
                purged = purged + 1
            end
        end
    end

    return purged
end

--- 对单个球队执行青训球员训练（与一线队同 schedule / 同公式 + 微调加成）
local function _trainTeamYouth(gameState, team, staffMult)
    if not TrainingManager.isTrainingDay(team, gameState.dayOfWeek) then
        return
    end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local FinanceManager = require("scripts/systems/finance_manager")
    local facilityBonus = FinanceManager.getFacilityBonuses(team).trainingGain or 1.0
    local intensityConfig = TrainingManager._getIntensity().medium
    local seasonStartYear = TrainingManager.getSeasonStartYear(gameState)

    local legendPositions = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p and p.isLegend then legendPositions[p.position] = true end
    end
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and p.isLegend then legendPositions[p.position] = true end
    end

    for _, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if player and player.teamId == team.id and player.attributes then
            if TrainingManager.getSeasonAge(player, seasonStartYear) <= Constants.YOUTH_PHASE_MAX_AGE then
                TrainingManager._trainPlayer(
                    gameState, team, player, intensityConfig,
                    (staffMult or 1.0) * facilityBonus, legendPositions,
                    {
                        useYouthGap = true,
                        trainingBonusMult = Constants.YOUTH_TRAINING_BONUS,
                        skipInjuryAndFitness = true,
                    })
            end
        end
    end
end

--- AI 球队按声望的自动提拔 OVR 门槛
---@param team table
---@return number
function YouthManager._getAIPromoteMinOvr(team)
    local rep = team and team.reputation or 600
    for _, tier in ipairs(AI_PROMOTE_MIN_OVR_BY_REP) do
        if rep >= tier.minRep then return tier.ovr end
    end
    return 55
end

--- 是否满足 AI 自动提拔条件（含高潜延迟）
---@param gameState table
---@param team table
---@param player table
---@return boolean
function YouthManager._shouldAIPromoteYouth(gameState, team, player)
    if not player or not team then return false end
    local age = gameState.date.year - (player.birthYear or 2000)
    if age < 18 then return false end

    local minOvr = YouthManager._getAIPromoteMinOvr(team)
    local ovr = player.overall or 0
    local pot = player.actualPotential or player.potential or 0

    if pot >= 90 then
        if age < AI_PROMOTE_HIGH_POT_90_AGE then return false end
        minOvr = math.max(minOvr, AI_PROMOTE_GEM_MIN_OVR)
    elseif pot >= 85 then
        if age < AI_PROMOTE_HIGH_POT_85_AGE then return false end
    end

    return ovr >= minOvr
end

--- 每日训练：所有球队青训球员成长
function YouthManager.processDailyTraining(gameState)
    for teamId, team in pairs(gameState.teams) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        if #team._youthPlayerIds > 0 then
            local staffMult = StaffManager.getYouthTrainingMultiplier(gameState, teamId)
            _trainTeamYouth(gameState, team, staffMult)
        end
    end
end

------------------------------------------------------



return YouthManager
