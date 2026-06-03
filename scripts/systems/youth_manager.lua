-- systems/youth_manager.lua
-- 青训系统：青年球员刷新、签入、提拔至一线队

local Constants = require("scripts/app/constants")
local Player = require("scripts/domain/player")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local PotentialSystem = require("scripts/systems/potential_system")

local YouthManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local YOUTH_REFRESH_INTERVAL = 3   -- 每3个月刷新一批（processMonthly每月调用一次）
local YOUTH_POOL_SIZE = 5          -- 每次刷新5名候选
local MAX_YOUTH_SQUAD = 8          -- 最多8名青训球员
local YOUTH_MIN_AGE = 15
local YOUTH_MAX_AGE = 18
local YOUTH_WAGE = 500             -- 青训球员固定周薪

-- 名字池
local YOUTH_FIRST_NAMES = {
    "Ethan", "Lucas", "Noah", "Oliver", "Jack",
    "Hugo", "Leo", "Kai", "Finn", "Oscar",
    "Max", "Ben", "Sam", "Ryan", "Dylan",
    "Pablo", "Marco", "Luca", "Tom", "Adam",
}
local YOUTH_LAST_NAMES = {
    "Williams", "Davis", "Miller", "Wilson", "Moore",
    "Taylor", "Clark", "Harris", "Young", "King",
    "Wright", "Hill", "Green", "Baker", "Adams",
    "Cruz", "Santos", "Torres", "Reyes", "Diaz",
}

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每月处理：刷新青训候选池
---@param gameState table
function YouthManager.processMonthly(gameState)
    gameState._youthCandidates = gameState._youthCandidates or {}
    gameState._youthRefreshCounter = (gameState._youthRefreshCounter or 0) + 1

    if gameState._youthRefreshCounter >= YOUTH_REFRESH_INTERVAL then
        gameState._youthRefreshCounter = 0
        YouthManager._refreshCandidates(gameState)
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
    if #team._youthPlayerIds >= MAX_YOUTH_SQUAD then
        return false, string.format("青训名额已满(%d人)", MAX_YOUTH_SQUAD)
    end

    -- 创建球员实体
    local playerData = {
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = candidate.nationality,
        birthYear = candidate.birthYear,
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = YOUTH_WAGE,
        isYouth = true,
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
    }
    local player = gameState:addPlayer(playerData)

    -- 设置球队归属
    player.teamId = team.id

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

    -- 检查是否在青训队
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

    -- 加入一线队
    table.insert(team.playerIds, playerId)

    local player = gameState.players[playerId]
    if player then
        player.isYouth = false
        player.teamId = team.id
        -- 提拔后给予正式合同
        player.contractEnd = {year = gameState.date.year + 3, month = 6, day = 30}
        player.wage = math.max(YOUTH_WAGE * 2, math.floor(player.overall * 80))

        MessageManager.send(gameState, "youth_promoted", {player.displayName})
        EventBus.emit("youth_promoted", {teamId = team.id, playerId = playerId})
    end

    return true
end

--- 释放青训球员
---@param gameState table
---@param playerId number
---@return boolean success, string? error
function YouthManager.release(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

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

    -- 标记为已释放（不从 players 表删除，保留历史）
    local player = gameState.players[playerId]
    if player then
        player.retired = true
        player.isYouth = false
    end

    return true
end

--- 获取球队青训球员列表
---@param gameState table
---@return table[]
function YouthManager.getYouthSquad(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return {} end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local result = {}
    for _, pid in ipairs(team._youthPlayerIds) do
        local p = gameState.players[pid]
        if p then
            table.insert(result, p)
        end
    end
    return result
end

--- 每日训练：青训球员成长（受青训加成影响）
---@param gameState table
function YouthManager.processDailyTraining(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    team._youthPlayerIds = team._youthPlayerIds or {}
    local youthBonus = StaffManager.getYouthDevBonus(gameState, team.id)

    for _, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if player and player.attributes then
            -- 每天有小概率提升某项属性
            local growthChance = 0.03 + youthBonus  -- 3% + 加成（最高 ~18%）
            if Random() < growthChance then
                -- 随机选一项属性
                local attrKeys = {}
                for k, _ in pairs(player.attributes) do
                    table.insert(attrKeys, k)
                end
                if #attrKeys > 0 then
                    local key = attrKeys[RandomInt(1, #attrKeys)]
                    local maxVal = math.min(20, math.floor((player.actualPotential or player.potential or 60) / 5))
                    if player.attributes[key] < maxVal then
                        player.attributes[key] = player.attributes[key] + 1
                        player:calculateOverall()
                    end
                end
            end
        end
    end
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

function YouthManager._refreshCandidates(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local youthDevBonus = StaffManager.getYouthDevBonus(gameState, team.id)

    -- 青训设施加成：提升潜力和质量
    local FinanceManager = require("scripts/systems/finance_manager")
    local facilityBonuses = FinanceManager.getFacilityBonuses(team)
    local facilityYouthBonus = facilityBonuses.youthQuality or 1.0

    local candidates = {}

    for _ = 1, YOUTH_POOL_SIZE do
        local candidate = YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)
        table.insert(candidates, candidate)
    end

    gameState._youthCandidates = candidates

    -- 通知
    gameState:sendMessage({
        category = "youth",
        title = "青训报告",
        body = string.format("球探发现了 %d 名有潜力的青年球员，请前往青训页面查看。", #candidates),
        priority = "normal",
    })
end

function YouthManager._generateYouthPlayer(gameState, youthDevBonus, facilityYouthBonus)
    facilityYouthBonus = facilityYouthBonus or 1.0
    local positions = {"GK", "CB", "LB", "RB", "CM", "CDM", "CAM", "LW", "RW", "ST"}
    local position = positions[RandomInt(1, #positions)]

    local age = RandomInt(YOUTH_MIN_AGE, YOUTH_MAX_AGE)
    local birthYear = gameState.date.year - age

    -- 潜力受青训教练加成 + 青训设施加成影响
    -- 设施加成：提高潜力下限（Lv5 时下限从45提升到 ~57）
    local potentialFloor = math.floor(45 * facilityYouthBonus)
    local basePotential = RandomInt(potentialFloor, 85)
    local potential = math.min(99, basePotential + math.floor(youthDevBonus * 30))

    -- 当前能力（设施加成提升起始能力）
    local overallCap = math.max(25, math.floor(potential * 0.5))
    local overallFloor = math.floor(25 * facilityYouthBonus)
    local overall = RandomInt(overallFloor, overallCap)

    -- 生成属性（基于 overall 和位置）
    local attributes = YouthManager._generateAttributes(position, overall)

    local firstName = YOUTH_FIRST_NAMES[RandomInt(1, #YOUTH_FIRST_NAMES)]
    local lastName = YOUTH_LAST_NAMES[RandomInt(1, #YOUTH_LAST_NAMES)]
    local nationalities = {"ENG", "ESP", "GER", "ITA", "FRA", "BRA", "ARG", "POR"}

    return {
        firstName = firstName,
        lastName = lastName,
        displayName = firstName .. " " .. lastName,
        nationality = nationalities[RandomInt(1, #nationalities)],
        birthYear = birthYear,
        position = position,
        potential = potential,
        overall = overall,
        attributes = attributes,
        age = age,
    }
end

function YouthManager._generateAttributes(position, overall)
    local baseVal = math.max(1, math.floor(overall / 7))

    -- 使用与 Player 模型一致的属性键名
    local attrs = {
        speed = baseVal + RandomInt(-2, 3),
        stamina = baseVal + RandomInt(-2, 3),
        strength = baseVal + RandomInt(-2, 3),
        agility = baseVal + RandomInt(-2, 3),
        passing = baseVal + RandomInt(-2, 3),
        shooting = baseVal + RandomInt(-2, 3),
        tackling = baseVal + RandomInt(-2, 3),
        dribbling = baseVal + RandomInt(-2, 3),
        defending = baseVal + RandomInt(-2, 3),
        positioning = baseVal + RandomInt(-2, 3),
        vision = baseVal + RandomInt(-2, 3),
        decisions = baseVal + RandomInt(-2, 3),
        composure = baseVal + RandomInt(-2, 3),
        aggression = baseVal + RandomInt(-2, 3),
        teamwork = baseVal + RandomInt(-2, 3),
        leadership = baseVal + RandomInt(-2, 3),
        aerial = baseVal + RandomInt(-2, 3),
        handling = 1,
        reflexes = 1,
    }

    -- 位置专精
    if position == "GK" then
        attrs.handling = baseVal + RandomInt(2, 5)
        attrs.reflexes = baseVal + RandomInt(2, 5)
        attrs.positioning = attrs.positioning + RandomInt(1, 3)
        attrs.composure = attrs.composure + RandomInt(1, 2)
    elseif position == "CB" then
        attrs.defending = attrs.defending + RandomInt(2, 4)
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.strength = attrs.strength + RandomInt(1, 3)
        attrs.aerial = attrs.aerial + RandomInt(1, 3)
    elseif position == "LB" or position == "RB" then
        attrs.defending = attrs.defending + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(2, 4)
        attrs.stamina = attrs.stamina + RandomInt(1, 3)
    elseif position == "CDM" then
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.defending = attrs.defending + RandomInt(1, 3)
        attrs.passing = attrs.passing + RandomInt(1, 3)
    elseif position == "CM" or position == "CAM" then
        attrs.passing = attrs.passing + RandomInt(2, 4)
        attrs.vision = attrs.vision + RandomInt(1, 3)
        attrs.dribbling = attrs.dribbling + RandomInt(1, 3)
    elseif position == "LW" or position == "RW" then
        attrs.speed = attrs.speed + RandomInt(2, 4)
        attrs.dribbling = attrs.dribbling + RandomInt(2, 3)
        attrs.agility = attrs.agility + RandomInt(1, 3)
    elseif position == "ST" or position == "CF" then
        attrs.shooting = attrs.shooting + RandomInt(2, 4)
        attrs.composure = attrs.composure + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(1, 3)
    end

    -- 限制范围
    for k, v in pairs(attrs) do
        attrs[k] = math.max(1, math.min(20, v))
    end
    return attrs
end

return YouthManager
