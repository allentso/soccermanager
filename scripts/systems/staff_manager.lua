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
StaffManager.MAX_STAFF_PER_TEAM = 6
local MAX_STAFF_PER_TEAM = StaffManager.MAX_STAFF_PER_TEAM
local HIRE_FEE_MULTIPLIER = 4  -- 签约费 = 周薪 × 4
local ROLE_STACK_MULTS = { 1.0, 0.6, 0.25, 0.10 }
local FREE_STAFF_MAX = Constants.FREE_STAFF_MAX or 20

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
local ALL_ROLES = {
    Constants.STAFF_ROLES.ASSISTANT,
    Constants.STAFF_ROLES.COACH,
    Constants.STAFF_ROLES.SCOUT,
    Constants.STAFF_ROLES.PHYSIO,
}

------------------------------------------------------
-- 缓存
------------------------------------------------------

function StaffManager.invalidateCache(gameState, teamId)
    if not gameState then return end
    gameState._staffBonusCache = gameState._staffBonusCache or {}
    if teamId then
        gameState._staffBonusCache[teamId] = nil
    else
        gameState._staffBonusCache = {}
    end
end

local function _roleStackWeight(index)
    return ROLE_STACK_MULTS[index] or ROLE_STACK_MULTS[#ROLE_STACK_MULTS]
end

local function _stackedSum(staffList, scoreFn)
    table.sort(staffList, function(a, b)
        return scoreFn(a) > scoreFn(b)
    end)
    local total = 0
    for i, s in ipairs(staffList) do
        total = total + scoreFn(s) * _roleStackWeight(i)
    end
    return total
end

local function _staffByRole(gameState, team, role)
    local list = {}
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == role then
            table.insert(list, s)
        end
    end
    return list
end

local function _allTeamStaff(gameState, team)
    local list = {}
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then table.insert(list, s) end
    end
    return list
end

local function _computeBonusesForTeam(gameState, teamId, staffIdList)
    local bonuses = {
        training = 0,
        scouting = 0,
        physio = 0,
        youthDev = 0,
        tactical = 0,
    }

    local team = gameState.teams[teamId]
    if not team then return bonuses end

    local virtualTeam = { staffIds = staffIdList or team.staffIds or {} }
    local assistants = _staffByRole(gameState, virtualTeam, Constants.STAFF_ROLES.ASSISTANT)
    local coaches = _staffByRole(gameState, virtualTeam, Constants.STAFF_ROLES.COACH)
    local scouts = _staffByRole(gameState, virtualTeam, Constants.STAFF_ROLES.SCOUT)
    local physios = _staffByRole(gameState, virtualTeam, Constants.STAFF_ROLES.PHYSIO)
    local allStaff = {}
    for _, sid in ipairs(virtualTeam.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then table.insert(allStaff, s) end
    end

    bonuses.training = bonuses.training
        + _stackedSum(coaches, function(s) return (s.attributes.training or 0) * 0.5 end)
        + _stackedSum(assistants, function(s) return (s.attributes.training or 0) * 0.3 end)

    bonuses.scouting = bonuses.scouting
        + _stackedSum(scouts, function(s) return (s.attributes.scouting or 0) * 0.5 end)

    bonuses.physio = bonuses.physio
        + _stackedSum(physios, function(s) return (s.attributes.physiotherapy or 0) * 0.5 end)

    bonuses.tactical = bonuses.tactical
        + _stackedSum(assistants, function(s) return (s.attributes.tactical or 0) * 0.4 end)
        + _stackedSum(coaches, function(s) return (s.attributes.tactical or 0) * 0.15 end)

    bonuses.youthDev = _stackedSum(allStaff, function(s)
        return (s.attributes.youthDev or 0) * 0.15
    end)

    return bonuses
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 获取球队加成汇总（供训练/球探/青训/伤病恢复使用）
---@param gameState table
---@param teamId number
---@return table {training, scouting, physio, youthDev, tactical}
function StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    if staffIdList then
        return _computeBonusesForTeam(gameState, teamId, staffIdList)
    end

    gameState._staffBonusCache = gameState._staffBonusCache or {}
    local cached = gameState._staffBonusCache[teamId]
    if cached then return cached end

    local bonuses = _computeBonusesForTeam(gameState, teamId)
    gameState._staffBonusCache[teamId] = bonuses
    return bonuses
end

--- 获取训练加成百分比（0~30%）
function StaffManager.getTrainingBonus(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    return math.min(0.30, bonuses.training / 100)
end

function StaffManager.getTrainingTier(gameState, teamId, staffIdList)
    local pct = StaffManager.getTrainingBonus(gameState, teamId, staffIdList)
    if pct >= 0.24 then return "顶级", pct
    elseif pct >= 0.18 then return "强", pct
    elseif pct >= 0.10 then return "普通", pct
    else return "弱", pct
    end
end

function StaffManager.getInjuryRecoveryBonus(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    return math.min(3, math.floor(bonuses.physio / 3))
end

function StaffManager.getScoutingBonus(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    return math.min(0.20, bonuses.scouting / 50)
end

function StaffManager.getYouthTrainingMultiplier(gameState, teamId, staffIdList)
    local team = gameState.teams[teamId]
    if not team then return 1.0 end

    local bonuses = {}
    for _, sid in ipairs(staffIdList or team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then
            local rating = math.min(20, s.attributes.youthDev or 10)
            if rating > 15 then
                table.insert(bonuses, (rating - 15) * 0.01)
            end
        end
    end
    table.sort(bonuses, function(a, b) return a > b end)

    local pct = 0
    for i, bonus in ipairs(bonuses) do
        pct = pct + bonus * _roleStackWeight(i)
    end
    return 1.0 + pct
end

function StaffManager.getYouthTrainingTierLabel(gameState, teamId, staffIdList)
    local mult = StaffManager.getYouthTrainingMultiplier(gameState, teamId, staffIdList)
    local pct = (mult - 1.0) * 100
    if pct >= 4 then return "快", mult
    elseif pct >= 2 then return "较快", mult
    elseif pct > 0.5 then return "略快", mult
    else return "标准", mult
    end
end

function StaffManager.getTacticalBonus(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    return math.min(0.08, bonuses.tactical / 160)
end

function StaffManager.getTacticalProficiency(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    return math.min(0.025, bonuses.tactical / 320)
end

function StaffManager.getTrainingInjuryRiskMultiplier(gameState, teamId, staffIdList)
    local bonuses = StaffManager.getTeamBonuses(gameState, teamId, staffIdList)
    local physioReduce = math.min(0.25, bonuses.physio / 120)
    return math.max(0.70, 1.0 - physioReduce)
end

--- 估算球探准确度（与 ScoutManager 公式对齐，供 UI 展示）
function StaffManager.estimateScoutingAccuracy(gameState, teamId, staffIdList)
    local team = gameState.teams[teamId]
    if not team then return 0.5 end

    local bestAbility = 0
    for _, sid in ipairs(staffIdList or team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == Constants.STAFF_ROLES.SCOUT then
            local ability = s.attributes and s.attributes.scouting or 10
            if ability > bestAbility then bestAbility = ability end
        end
    end

    local scoutBonus = StaffManager.getScoutingBonus(gameState, teamId, staffIdList)
    local facilityBonus = FinanceManager.getFacilityBonuses(team).scoutingAccuracy

    return math.min(0.97, (0.50 + bestAbility * 0.02 + scoutBonus) * facilityBonus)
end

--- 团队效果快照（UI / 招聘对比）
function StaffManager.getTeamEffectSnapshot(gameState, teamId, staffIdList)
    local trainingPct = StaffManager.getTrainingBonus(gameState, teamId, staffIdList)
    local trainingTier = StaffManager.getTrainingTier(gameState, teamId, staffIdList)
    local youthTier, youthMult = StaffManager.getYouthTrainingTierLabel(gameState, teamId, staffIdList)
    local tacticalProf = StaffManager.getTacticalProficiency(gameState, teamId, staffIdList)
    local scoutingAccuracy = StaffManager.estimateScoutingAccuracy(gameState, teamId, staffIdList)

    return {
        trainingPct = trainingPct,
        trainingTier = trainingTier,
        trainingLabel = string.format("成长 +%d%% (%s)", math.floor(trainingPct * 100 + 0.5), trainingTier),
        scoutingAccuracy = scoutingAccuracy,
        scoutingLabel = string.format("准确度 %d%%", math.floor(scoutingAccuracy * 100 + 0.5)),
        injuryRecoveryDays = StaffManager.getInjuryRecoveryBonus(gameState, teamId, staffIdList),
        injuryLabel = string.format("每日额外恢复 +%d天", StaffManager.getInjuryRecoveryBonus(gameState, teamId, staffIdList)),
        youthTrainingMult = youthMult,
        youthLabel = string.format("青训训练 %s (+%d%%)", youthTier, math.floor((youthMult - 1.0) * 100 + 0.5)),
        tacticalProficiency = tacticalProf,
        tacticalLabel = string.format("战术熟练 +%d%%", math.floor(tacticalProf * 100 + 0.5)),
        tacticalPct = StaffManager.getTacticalBonus(gameState, teamId, staffIdList),
    }
end

function StaffManager.previewHireDelta(gameState, teamId, candidateStaff)
    local team = gameState.teams[teamId]
    if not team or not candidateStaff then return nil end

    local before = StaffManager.getTeamEffectSnapshot(gameState, teamId)
    local virtualIds = {}
    for _, sid in ipairs(team.staffIds or {}) do
        table.insert(virtualIds, sid)
    end
    table.insert(virtualIds, candidateStaff.id)

    local after = StaffManager.getTeamEffectSnapshot(gameState, teamId, virtualIds)

    return {
        before = before,
        after = after,
        trainingDelta = after.trainingPct - before.trainingPct,
        scoutingDelta = after.scoutingAccuracy - before.scoutingAccuracy,
        injuryDelta = after.injuryRecoveryDays - before.injuryRecoveryDays,
        youthDelta = after.youthTrainingMult - before.youthTrainingMult,
        tacticalDelta = after.tacticalProficiency - before.tacticalProficiency,
    }
end

function StaffManager.getRoleMixHints(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return {} end

    local roleCount = {}
    for _, role in ipairs(ALL_ROLES) do
        roleCount[role] = 0
    end
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and roleCount[s.role] ~= nil then
            roleCount[s.role] = roleCount[s.role] + 1
        end
    end

    local hints = {}
    if roleCount[Constants.STAFF_ROLES.SCOUT] == 0 then
        table.insert(hints, "缺少球探，无法派遣球探任务")
    end
    if roleCount[Constants.STAFF_ROLES.PHYSIO] == 0 then
        table.insert(hints, "缺少理疗师，伤病恢复较慢")
    end
    if roleCount[Constants.STAFF_ROLES.COACH] + roleCount[Constants.STAFF_ROLES.ASSISTANT] >= 3 then
        table.insert(hints, "教练组偏重训练（同岗递减收益）")
    end
    if roleCount[Constants.STAFF_ROLES.SCOUT] >= 2 then
        table.insert(hints, "球探编制较多（第2人仅60%效果）")
    end

    local physioBonus = StaffManager.getInjuryRecoveryBonus(gameState, teamId)
    if physioBonus <= 0 and roleCount[Constants.STAFF_ROLES.PHYSIO] > 0 then
        table.insert(hints, "理疗能力偏弱")
    end

    return hints
end

function StaffManager.getStaffChipText(gameState, teamId, context)
    local snap = StaffManager.getTeamEffectSnapshot(gameState, teamId)
    if context == "training" then
        return "教练组：" .. snap.trainingLabel
    elseif context == "youth" then
        return "青训职员：" .. snap.youthLabel
    elseif context == "scout" then
        return "球探组：" .. snap.scoutingLabel
    elseif context == "medical" then
        return "医疗组：" .. snap.injuryLabel
    end
    return snap.trainingLabel
end

------------------------------------------------------
-- 雇佣/解约
------------------------------------------------------

function StaffManager.hire(gameState, teamId, staffId)
    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end

    local s = gameState.staff[staffId]
    if not s then return false, "职员不存在" end
    if s.teamId then return false, "该职员已在其他球队任职" end

    if #(team.staffIds or {}) >= MAX_STAFF_PER_TEAM then
        return false, string.format("职员数量已达上限(%d人)", MAX_STAFF_PER_TEAM)
    end

    local fee = s.wage * HIRE_FEE_MULTIPLIER
    if team.balance < fee then
        return false, string.format("资金不足，签约费需 %s", FinanceManager.formatMoney(fee))
    end

    if not FinanceManager.withinWageBudget(gameState, teamId, s.wage) then
        return false, "超出周薪预算，无法签约该职员"
    end

    team.balance = team.balance - fee
    team.seasonExpense = (team.seasonExpense or 0) + fee
    FinanceManager.addTransaction(team, {
        amount = -fee,
        description = string.format("签约职员 %s", s.displayName),
        category = "staff",
        season = gameState.season,
    })

    s.teamId = teamId
    team.staffIds = team.staffIds or {}
    table.insert(team.staffIds, staffId)

    StaffManager._removeFromFreePool(gameState, staffId)
    StaffManager.invalidateCache(gameState, teamId)

    if teamId == gameState.playerTeamId then
        gameState:sendMessage({
            category = "system",
            title = "职员签约",
            body = string.format("已签约 %s（%s），周薪 %s。",
                s.displayName,
                Constants.STAFF_ROLE_NAMES[s.role] or s.role,
                FinanceManager.formatMoney(s.wage)),
            priority = "low",
        })
    end

    EventBus.emit("staff_hired", {teamId = teamId, staffId = staffId, role = s.role})
    return true
end

function StaffManager.fire(gameState, teamId, staffId)
    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end

    local s = gameState.staff[staffId]
    if not s then return false, "职员不存在" end
    if s.teamId ~= teamId then return false, "该职员不在你的球队" end

    local compensation = s.wage * 4
    if team.balance < compensation then
        return false, string.format("资金不足，解约补偿需 %s", FinanceManager.formatMoney(compensation))
    end

    team.balance = team.balance - compensation
    team.seasonExpense = (team.seasonExpense or 0) + compensation
    FinanceManager.addTransaction(team, {
        amount = -compensation,
        description = string.format("解约职员 %s (补偿金)", s.displayName),
        category = "staff",
        season = gameState.season,
    })

    s.teamId = nil
    for i, sid in ipairs(team.staffIds) do
        if sid == staffId then
            table.remove(team.staffIds, i)
            break
        end
    end

    StaffManager._addToFreePool(gameState, staffId)
    StaffManager.invalidateCache(gameState, teamId)

    if teamId == gameState.playerTeamId then
        gameState:sendMessage({
            category = "system",
            title = "职员解约",
            body = string.format("已解约 %s，支付补偿金 %s。",
                s.displayName, FinanceManager.formatMoney(compensation)),
            priority = "low",
        })
    end

    EventBus.emit("staff_fired", {teamId = teamId, staffId = staffId, role = s.role})
    return true
end

------------------------------------------------------
-- 生成职员
------------------------------------------------------

local function _reputationToQuality(rep)
    rep = rep or 600
    return math.max(5, math.min(18, math.floor(5 + (rep - 500) / 70)))
end

function StaffManager._buildStaffData(role, country, quality, opts)
    opts = opts or {}
    quality = quality or RandomInt(5, 16)

    local attrs = {
        training = math.max(1, quality + RandomInt(-3, 3)),
        tactical = math.max(1, quality + RandomInt(-3, 3)),
        scouting = math.max(1, quality + RandomInt(-3, 3)),
        physiotherapy = math.max(1, quality + RandomInt(-3, 3)),
        youthDev = math.max(1, quality + RandomInt(-3, 3)),
    }

    if role == Constants.STAFF_ROLES.COACH then
        attrs.training = math.min(20, attrs.training + 3)
    elseif role == Constants.STAFF_ROLES.SCOUT then
        attrs.scouting = math.min(20, attrs.scouting + 4)
    elseif role == Constants.STAFF_ROLES.PHYSIO then
        attrs.physiotherapy = math.min(20, attrs.physiotherapy + 4)
    elseif role == Constants.STAFF_ROLES.ASSISTANT then
        attrs.tactical = math.min(20, attrs.tactical + 3)
    end

    local avgAttr = (attrs.training + attrs.scouting + attrs.physiotherapy
        + attrs.youthDev + attrs.tactical) / 5
    local wage = math.floor(avgAttr * 400 + RandomInt(0, 1000))

    local firstName = opts.firstName or FIRST_NAMES[RandomInt(1, #FIRST_NAMES)]
    local lastName = opts.lastName or LAST_NAMES[RandomInt(1, #LAST_NAMES)]

    return {
        firstName = firstName,
        lastName = lastName,
        displayName = firstName .. " " .. lastName,
        nationality = country or NATIONALITIES[RandomInt(1, #NATIONALITIES)],
        birthYear = RandomInt(1960, 1990),
        role = role,
        wage = wage,
        attributes = attrs,
    }
end

function StaffManager.generateTeamStaff(gameState, teamId, country, role)
    local team = gameState.teams[teamId]
    if not team then return nil end
    local quality = _reputationToQuality(team.reputation)
    local staffData = StaffManager._buildStaffData(role, country, quality)
    staffData.teamId = teamId
    local staff = gameState:addStaff(staffData)
    team.staffIds = team.staffIds or {}
    table.insert(team.staffIds, staff.id)
    StaffManager.invalidateCache(gameState, teamId)
    return staff
end

------------------------------------------------------
-- 自由职员池管理
------------------------------------------------------

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

local function _staffPoolScore(s)
    local attrs = s.attributes or {}
    return (attrs.training or 0)
        + (attrs.scouting or 0)
        + (attrs.physiotherapy or 0)
        + (attrs.youthDev or 0)
        + (attrs.tactical or 0)
end

function StaffManager._pruneFreePool(gameState, maxCount)
    maxCount = maxCount or FREE_STAFF_MAX
    gameState._freeStaffIds = gameState._freeStaffIds or {}
    if not gameState.staff then
        gameState._freeStaffIds = {}
        return
    end

    local entries = {}
    local seen = {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        local s = gameState.staff[sid]
        local seenKey = tostring(sid)
        if s and not s.teamId and not seen[seenKey] then
            table.insert(entries, {
                id = sid,
                staff = s,
                score = _staffPoolScore(s),
                sortId = tonumber(sid) or tonumber(s.id) or 0,
            })
            seen[seenKey] = true
        end
    end

    table.sort(entries, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.sortId < b.sortId
    end)

    local keep = {}
    local keptById = {}

    local function keepEntry(entry)
        local key = tostring(entry.id)
        if #keep < maxCount and not keptById[key] then
            table.insert(keep, entry)
            keptById[key] = true
        end
    end

    -- 保留每个岗位中最好的候选，避免裁剪后破坏岗位覆盖。
    for _, role in ipairs(ALL_ROLES) do
        for _, entry in ipairs(entries) do
            if entry.staff.role == role then
                keepEntry(entry)
                break
            end
        end
    end

    for _, entry in ipairs(entries) do
        keepEntry(entry)
    end

    local nextIds = {}
    for _, entry in ipairs(keep) do
        table.insert(nextIds, entry.id)
    end

    for _, entry in ipairs(entries) do
        if not keptById[tostring(entry.id)] then
            gameState.staff[entry.id] = nil
            if entry.staff.id and entry.staff.id ~= entry.id then
                gameState.staff[entry.staff.id] = nil
            end
        end
    end

    gameState._freeStaffIds = nextIds
end

function StaffManager.generateFreeStaff(gameState, count, opts)
    opts = opts or {}
    count = count or Constants.FREE_STAFF_COUNT or 8
    gameState._freeStaffIds = gameState._freeStaffIds or {}

    local rep = opts.reputation
    if not rep and gameState.playerTeamId then
        local pt = gameState.teams[gameState.playerTeamId]
        rep = pt and pt.reputation or 600
    end
    local quality = _reputationToQuality(rep)

    for _ = 1, count do
        local role = opts.forcedRole or ALL_ROLES[RandomInt(1, #ALL_ROLES)]
        local staffData = StaffManager._buildStaffData(role, nil, quality)
        local staff = gameState:addStaff(staffData)
        table.insert(gameState._freeStaffIds, staff.id)
    end
    StaffManager._pruneFreePool(gameState)
end

function StaffManager.ensureFreePoolOnLoad(gameState)
    gameState._freeStaffIds = gameState._freeStaffIds or {}

    local valid = {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        local s = gameState.staff[sid]
        if s and not s.teamId then
            table.insert(valid, sid)
        end
    end
    gameState._freeStaffIds = valid

    local inPool = {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        inPool[sid] = true
    end
    for id, s in pairs(gameState.staff) do
        if s and not s.teamId and not inPool[id] then
            table.insert(gameState._freeStaffIds, id)
            inPool[id] = true
        end
    end

    StaffManager._ensurePoolRoleCoverage(gameState)

    local target = Constants.FREE_STAFF_COUNT or 8
    local deficit = target - #gameState._freeStaffIds
    if deficit > 0 then
        StaffManager.generateFreeStaff(gameState, deficit)
    end
    StaffManager._pruneFreePool(gameState)
end

function StaffManager._ensurePoolRoleCoverage(gameState)
    local rolesInPool = {}
    for _, sid in ipairs(gameState._freeStaffIds or {}) do
        local s = gameState.staff[sid]
        if s and not s.teamId then
            rolesInPool[s.role] = true
        end
    end
    for _, role in ipairs(ALL_ROLES) do
        if not rolesInPool[role] then
            StaffManager.generateFreeStaff(gameState, 1, { forcedRole = role })
            rolesInPool[role] = true
        end
    end
end

function StaffManager.refreshFreePool(gameState)
    gameState._freeStaffIds = gameState._freeStaffIds or {}

    local valid = {}
    for _, sid in ipairs(gameState._freeStaffIds) do
        local s = gameState.staff[sid]
        if s and not s.teamId then
            table.insert(valid, sid)
        end
    end
    gameState._freeStaffIds = valid

    StaffManager._ensurePoolRoleCoverage(gameState)

    local target = Constants.FREE_STAFF_COUNT or 8
    local deficit = target - #gameState._freeStaffIds
    if deficit > 0 then
        StaffManager.generateFreeStaff(gameState, deficit)
    end
    StaffManager._pruneFreePool(gameState)
end

------------------------------------------------------
-- AI 月度职员管理
------------------------------------------------------

function StaffManager.processAIMonthly(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId == gameState.playerTeamId then goto continue end

        local haveRole = {}
        for _, sid in ipairs(team.staffIds or {}) do
            local s = gameState.staff[sid]
            if s then haveRole[s.role] = true end
        end

        for _, role in ipairs(ALL_ROLES) do
            if not haveRole[role] then
                StaffManager.generateTeamStaff(gameState, teamId, team.country, role)
            end
        end

        if (team.reputation or 0) >= 750 and (team.balance or 0) > 500000 and Random() < 0.12 then
            local worstStaff, worstScore, worstSid
            for _, sid in ipairs(team.staffIds or {}) do
                local s = gameState.staff[sid]
                if s and s.attributes then
                    local score = (s.attributes.training or 0) + (s.attributes.scouting or 0)
                        + (s.attributes.physiotherapy or 0) + (s.attributes.youthDev or 0)
                        + (s.attributes.tactical or 0)
                    if not worstScore or score < worstScore then
                        worstScore = score
                        worstStaff = s
                        worstSid = sid
                    end
                end
            end
            if worstStaff and worstScore and worstScore < 60 then
                for i, sid in ipairs(team.staffIds) do
                    if sid == worstSid then
                        table.remove(team.staffIds, i)
                        break
                    end
                end
                worstStaff.teamId = nil
                StaffManager.generateTeamStaff(gameState, teamId, team.country, worstStaff.role)
            end
        end

        ::continue::
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
    StaffManager._pruneFreePool(gameState)
end

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

function StaffManager._getStaffContribution(s)
    local parts = {}
    if s.role == Constants.STAFF_ROLES.ASSISTANT then
        table.insert(parts, string.format("训练贡献 %.1f", (s.attributes.training or 0) * 0.3))
        table.insert(parts, string.format("战术贡献 %.1f", (s.attributes.tactical or 0) * 0.4))
    elseif s.role == Constants.STAFF_ROLES.COACH then
        table.insert(parts, string.format("训练贡献 %.1f", (s.attributes.training or 0) * 0.5))
    elseif s.role == Constants.STAFF_ROLES.SCOUT then
        table.insert(parts, string.format("球探贡献 %.1f", (s.attributes.scouting or 0) * 0.5))
    elseif s.role == Constants.STAFF_ROLES.PHYSIO then
        table.insert(parts, string.format("康复贡献 %.1f", (s.attributes.physiotherapy or 0) * 0.5))
    end
    if (s.attributes.youthDev or 0) >= 10 then
        table.insert(parts, string.format("青训贡献 %.1f", (s.attributes.youthDev or 0) * 0.15))
    end
    return table.concat(parts, " · ")
end

return StaffManager
