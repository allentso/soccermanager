-- systems/staff_manager.lua
-- 职员管理系统：雇佣/解约/加成计算/自由职员池

local Constants = require("scripts/app/constants")
local Staff = require("scripts/domain/staff")
local EventBus = require("scripts/app/event_bus")
local FinanceManager = require("scripts/systems/finance_manager")

local StaffManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local MAX_STAFF_PER_TEAM = 6
local HIRE_FEE_MULTIPLIER = 4  -- 签约费 = 周薪 × 4

-- 名字池（用于生成随机职员）
local FIRST_NAMES = {
    "James", "David", "Michael", "Robert", "Carlos",
    "Marco", "Jean", "Hans", "Paolo", "Luis",
    "Thomas", "Alex", "Andre", "Peter", "Frank",
}
local LAST_NAMES = {
    "Smith", "Johnson", "Williams", "Brown", "Garcia",
    "Rodriguez", "Martinez", "Mueller", "Rossi", "Silva",
    "Anderson", "Taylor", "Wilson", "Clark", "Wright",
}
local NATIONALITIES = {"ENG", "ESP", "GER", "ITA", "FRA", "BRA", "ARG", "POR", "NED", "SCO"}

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 获取球队加成汇总（供训练/球探/青训/伤病恢复使用）
---@param gameState table
---@param teamId number
---@return table {training, scouting, physio, youthDev, motivation}
function StaffManager.getTeamBonuses(gameState, teamId)
    local bonuses = {
        training = 0,
        scouting = 0,
        physio = 0,
        youthDev = 0,
        motivation = 0,
    }

    local team = gameState.teams[teamId]
    if not team then return bonuses end

    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then
            -- 每个职员按角色贡献加成
            if s.role == Constants.STAFF_ROLES.ASSISTANT then
                bonuses.training = bonuses.training + s.attributes.training * 0.3
                bonuses.motivation = bonuses.motivation + s.attributes.motivation * 0.4
            elseif s.role == Constants.STAFF_ROLES.COACH then
                bonuses.training = bonuses.training + s.attributes.training * 0.5
                bonuses.motivation = bonuses.motivation + s.attributes.motivation * 0.2
            elseif s.role == Constants.STAFF_ROLES.SCOUT then
                bonuses.scouting = bonuses.scouting + s.attributes.scouting * 0.5
            elseif s.role == Constants.STAFF_ROLES.PHYSIO then
                bonuses.physio = bonuses.physio + s.attributes.physiotherapy * 0.5
            end

            -- 通用：青训加成
            bonuses.youthDev = bonuses.youthDev + s.attributes.youthDev * 0.15
        end
    end

    return bonuses
end

--- 获取训练加成百分比（0~30%）
---@param gameState table
---@param teamId number
---@return number 0.0 ~ 0.30
function StaffManager.getTrainingBonus(gameState, teamId)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId)
    -- training 加成上限 30%（基于 20 属性 × 0.5 × 最多3教练 ≈ 30）
    return math.min(0.30, bonuses.training / 100)
end

--- 获取伤病恢复加成天数（减少恢复天数）
---@param gameState table
---@param teamId number
---@return number 0~3 天
function StaffManager.getInjuryRecoveryBonus(gameState, teamId)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId)
    -- physio 加成上限 3 天
    return math.min(3, math.floor(bonuses.physio / 3))
end

--- 获取球探准确度加成（0~20%）
---@param gameState table
---@param teamId number
---@return number 0.0 ~ 0.20
function StaffManager.getScoutingBonus(gameState, teamId)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId)
    return math.min(0.20, bonuses.scouting / 50)
end

--- 获取青训发展加成（0~15%）
---@param gameState table
---@param teamId number
---@return number 0.0 ~ 0.15
function StaffManager.getYouthDevBonus(gameState, teamId)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId)
    return math.min(0.15, bonuses.youthDev / 60)
end

------------------------------------------------------
-- 雇佣/解约
------------------------------------------------------

--- 雇佣职员
---@param gameState table
---@param teamId number
---@param staffId number
---@return boolean success, string? error
function StaffManager.hire(gameState, teamId, staffId)
    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end

    local s = gameState.staff[staffId]
    if not s then return false, "职员不存在" end

    -- 已有归属
    if s.teamId then return false, "该职员已在其他球队任职" end

    -- 人数上限
    if #(team.staffIds or {}) >= MAX_STAFF_PER_TEAM then
        return false, string.format("职员数量已达上限(%d人)", MAX_STAFF_PER_TEAM)
    end

    -- 签约费
    local fee = s.wage * HIRE_FEE_MULTIPLIER
    if team.balance < fee then
        return false, string.format("资金不足，签约费需 %s", FinanceManager.formatMoney(fee))
    end

    -- 扣除签约费
    team.balance = team.balance - fee
    team.seasonExpense = (team.seasonExpense or 0) + fee
    FinanceManager.addTransaction(team, {
        amount = -fee,
        description = string.format("签约职员 %s", s.displayName),
        category = "staff",
        season = gameState.season,
    })

    -- 绑定关系
    s.teamId = teamId
    team.staffIds = team.staffIds or {}
    table.insert(team.staffIds, staffId)

    -- 从自由池移除
    StaffManager._removeFromFreePool(gameState, staffId)

    EventBus.emit("staff_hired", {teamId = teamId, staffId = staffId, role = s.role})
    return true
end

--- 解约职员
---@param gameState table
---@param teamId number
---@param staffId number
---@return boolean success, string? error
function StaffManager.fire(gameState, teamId, staffId)
    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end

    local s = gameState.staff[staffId]
    if not s then return false, "职员不存在" end
    if s.teamId ~= teamId then return false, "该职员不在你的球队" end

    -- 解约补偿 = 4周薪资
    local compensation = s.wage * 4
    team.balance = team.balance - compensation
    team.seasonExpense = (team.seasonExpense or 0) + compensation
    FinanceManager.addTransaction(team, {
        amount = -compensation,
        description = string.format("解约职员 %s (补偿金)", s.displayName),
        category = "staff",
        season = gameState.season,
    })

    -- 解除关系
    s.teamId = nil
    for i, sid in ipairs(team.staffIds) do
        if sid == staffId then
            table.remove(team.staffIds, i)
            break
        end
    end

    -- 加入自由池
    StaffManager._addToFreePool(gameState, staffId)

    EventBus.emit("staff_fired", {teamId = teamId, staffId = staffId, role = s.role})
    return true
end

------------------------------------------------------
-- 自由职员池管理
------------------------------------------------------

--- 获取可雇佣的自由职员列表
---@param gameState table
---@param roleFilter? string 按角色筛选
---@return table[] Staff列表
function StaffManager.getFreeStaff(gameState, roleFilter)
    local result = {}
    gameState._freeStaffIds = gameState._freeStaffIds or {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        local s = gameState.staff[sid]
        if s and not s.teamId then
            if not roleFilter or s.role == roleFilter then
                table.insert(result, s)
            end
        end
    end
    return result
end

--- 初始化自由职员池（开新游戏或赛季更新时调用）
---@param gameState table
---@param count? number 生成数量
function StaffManager.generateFreeStaff(gameState, count)
    count = count or Constants.FREE_STAFF_COUNT or 8
    gameState._freeStaffIds = gameState._freeStaffIds or {}

    local roles = {
        Constants.STAFF_ROLES.ASSISTANT,
        Constants.STAFF_ROLES.COACH,
        Constants.STAFF_ROLES.SCOUT,
        Constants.STAFF_ROLES.PHYSIO,
    }

    for _ = 1, count do
        local role = roles[RandomInt(1, #roles)]
        local quality = RandomInt(5, 16)  -- 基础属性水平

        local attrs = {
            training = math.max(1, quality + RandomInt(-3, 3)),
            tactical = math.max(1, quality + RandomInt(-3, 3)),
            scouting = math.max(1, quality + RandomInt(-3, 3)),
            physiotherapy = math.max(1, quality + RandomInt(-3, 3)),
            youthDev = math.max(1, quality + RandomInt(-3, 3)),
            motivation = math.max(1, quality + RandomInt(-3, 3)),
        }

        -- 角色专精
        if role == Constants.STAFF_ROLES.COACH then
            attrs.training = math.min(20, attrs.training + 3)
        elseif role == Constants.STAFF_ROLES.SCOUT then
            attrs.scouting = math.min(20, attrs.scouting + 4)
        elseif role == Constants.STAFF_ROLES.PHYSIO then
            attrs.physiotherapy = math.min(20, attrs.physiotherapy + 4)
        elseif role == Constants.STAFF_ROLES.ASSISTANT then
            attrs.motivation = math.min(20, attrs.motivation + 3)
            attrs.tactical = math.min(20, attrs.tactical + 2)
        end

        -- 工资与属性相关
        local avgAttr = (attrs.training + attrs.scouting + attrs.physiotherapy + attrs.motivation) / 4
        local wage = math.floor(avgAttr * 400 + RandomInt(0, 1000))

        local specialties = {"fitness", "technical", "tactical", "defense", "attack", "goalkeeper", "youth"}

        local staffData = {
            firstName = FIRST_NAMES[RandomInt(1, #FIRST_NAMES)],
            lastName = LAST_NAMES[RandomInt(1, #LAST_NAMES)],
            nationality = NATIONALITIES[RandomInt(1, #NATIONALITIES)],
            birthYear = RandomInt(1960, 1990),
            role = role,
            wage = wage,
            attributes = attrs,
            specialty = specialties[RandomInt(1, #specialties)],
        }
        staffData.displayName = staffData.firstName .. " " .. staffData.lastName

        local staff = gameState:addStaff(staffData)
        table.insert(gameState._freeStaffIds, staff.id)
    end
end

--- 每赛季补充自由职员池（赛季过渡时调用）
---@param gameState table
function StaffManager.refreshFreePool(gameState)
    gameState._freeStaffIds = gameState._freeStaffIds or {}

    -- 移除已被雇佣的
    local valid = {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        local s = gameState.staff[sid]
        if s and not s.teamId then
            table.insert(valid, sid)
        end
    end
    gameState._freeStaffIds = valid

    -- 补充到至少 8 人
    local deficit = 8 - #gameState._freeStaffIds
    if deficit > 0 then
        StaffManager.generateFreeStaff(gameState, deficit)
    end
end

------------------------------------------------------
-- 内部辅助
------------------------------------------------------

function StaffManager._removeFromFreePool(gameState, staffId)
    gameState._freeStaffIds = gameState._freeStaffIds or {}
    for i, sid in ipairs(gameState._freeStaffIds) do
        if sid == staffId then
            table.remove(gameState._freeStaffIds, i)
            return
        end
    end
end

function StaffManager._addToFreePool(gameState, staffId)
    gameState._freeStaffIds = gameState._freeStaffIds or {}
    table.insert(gameState._freeStaffIds, staffId)
end

------------------------------------------------------
-- 查询API（供UI使用）
------------------------------------------------------

--- 获取球队职员列表及其加成详情
---@param gameState table
---@param teamId number
---@return table[] {staff, contribution}
function StaffManager.getTeamStaffDetails(gameState, teamId)
    local result = {}
    local team = gameState.teams[teamId]
    if not team then return result end

    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then
            local contribution = StaffManager._getStaffContribution(s)
            table.insert(result, {staff = s, contribution = contribution})
        end
    end
    return result
end

--- 计算单个职员的贡献描述
function StaffManager._getStaffContribution(s)
    local parts = {}
    if s.role == Constants.STAFF_ROLES.ASSISTANT then
        table.insert(parts, string.format("训练+%d%%", math.floor(s.attributes.training * 0.3)))
        table.insert(parts, string.format("激励+%d%%", math.floor(s.attributes.motivation * 0.4)))
    elseif s.role == Constants.STAFF_ROLES.COACH then
        table.insert(parts, string.format("训练+%d%%", math.floor(s.attributes.training * 0.5)))
    elseif s.role == Constants.STAFF_ROLES.SCOUT then
        table.insert(parts, string.format("球探+%d%%", math.floor(s.attributes.scouting * 0.5)))
    elseif s.role == Constants.STAFF_ROLES.PHYSIO then
        table.insert(parts, string.format("康复+%d%%", math.floor(s.attributes.physiotherapy * 0.5)))
    end
    if s.attributes.youthDev >= 12 then
        table.insert(parts, string.format("青训+%d%%", math.floor(s.attributes.youthDev * 0.15)))
    end
    return table.concat(parts, ", ")
end

return StaffManager
