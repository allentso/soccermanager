-- systems/scout_manager.lua
-- 球探系统：指派球探任务、生成报告、准确度与职员加成

local Constants = require("scripts/app/constants")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")

local ScoutManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local SCOUT_DAYS_BASE = 7     -- 基础球探时间（天）
local MAX_ACTIVE_TASKS = 3    -- 最多同时进行的球探任务
local REPORT_EXPIRY_DAYS = 60 -- 报告60天后过期

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 指派球探观察某球员
---@param gameState table
---@param playerId number 被观察球员ID
---@return boolean success, string? error
function ScoutManager.assignScout(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    -- 确认有球探
    local scouts = ScoutManager._getTeamScouts(gameState, team)
    if #scouts == 0 then
        return false, "球队没有球探，请先雇佣一名球探"
    end

    -- 检查任务数量
    gameState._scoutTasks = gameState._scoutTasks or {}
    local activeCount = 0
    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then activeCount = activeCount + 1 end
    end
    if activeCount >= MAX_ACTIVE_TASKS then
        return false, string.format("同时最多进行 %d 项球探任务", MAX_ACTIVE_TASKS)
    end

    -- 检查目标球员
    local targetPlayer = gameState.players[playerId]
    if not targetPlayer then return false, "目标球员不存在" end

    -- 已有进行中的同一目标
    for _, task in ipairs(gameState._scoutTasks) do
        if task.playerId == playerId and not task.completed then
            return false, "已在观察该球员"
        end
    end

    -- 计算完成天数（受球探能力影响）
    local bestScout = scouts[1]
    for _, s in ipairs(scouts) do
        if s.attributes.scouting > bestScout.attributes.scouting then
            bestScout = s
        end
    end
    local scoutAbility = bestScout.attributes.scouting or 10
    local daysNeeded = math.max(3, SCOUT_DAYS_BASE - math.floor(scoutAbility / 5))

    -- 创建任务
    local task = {
        id = gameState:generateId(),
        playerId = playerId,
        scoutId = bestScout.id,
        startDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        daysRemaining = daysNeeded,
        totalDays = daysNeeded,
        completed = false,
    }
    table.insert(gameState._scoutTasks, task)

    return true
end

--- 取消球探任务
---@param gameState table
---@param taskId number
---@return boolean
function ScoutManager.cancelTask(gameState, taskId)
    gameState._scoutTasks = gameState._scoutTasks or {}
    for i, task in ipairs(gameState._scoutTasks) do
        if task.id == taskId and not task.completed then
            table.remove(gameState._scoutTasks, i)
            return true
        end
    end
    return false
end

--- 每日处理（推进球探任务倒计时）
---@param gameState table
function ScoutManager.processDaily(gameState)
    gameState._scoutTasks = gameState._scoutTasks or {}

    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then
            task.daysRemaining = task.daysRemaining - 1
            if task.daysRemaining <= 0 then
                task.completed = true
                ScoutManager._generateReport(gameState, task)
            end
        end
    end

    -- 清理过期报告
    ScoutManager._cleanupExpiredReports(gameState)
end

--- 获取当前活跃的球探任务
---@param gameState table
---@return table[]
function ScoutManager.getActiveTasks(gameState)
    gameState._scoutTasks = gameState._scoutTasks or {}
    local result = {}
    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then
            local player = gameState.players[task.playerId]
            table.insert(result, {
                id = task.id,
                playerName = player and player.displayName or "未知",
                playerId = task.playerId,
                daysRemaining = task.daysRemaining,
                totalDays = task.totalDays,
                progress = math.floor((1 - task.daysRemaining / task.totalDays) * 100),
            })
        end
    end
    return result
end

--- 获取已完成的球探报告列表
---@param gameState table
---@return table[]
function ScoutManager.getReports(gameState)
    gameState.scoutReports = gameState.scoutReports or {}
    local result = {}
    for _, report in ipairs(gameState.scoutReports) do
        table.insert(result, report)
    end
    -- 按日期倒序
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

--- 获取某球员最新的球探报告
---@param gameState table
---@param playerId number
---@return table|nil
function ScoutManager.getPlayerReport(gameState, playerId)
    gameState.scoutReports = gameState.scoutReports or {}
    for i = #gameState.scoutReports, 1, -1 do
        if gameState.scoutReports[i].playerId == playerId then
            return gameState.scoutReports[i]
        end
    end
    return nil
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

--- 生成球探报告
function ScoutManager._generateReport(gameState, task)
    local player = gameState.players[task.playerId]
    if not player then return end

    local scout = gameState.staff[task.scoutId]
    local scoutAbility = scout and scout.attributes.scouting or 10

    -- 球探加成
    local teamId = gameState.playerTeamId
    local scoutBonus = StaffManager.getScoutingBonus(gameState, teamId)

    -- 准确度 = 球探能力 + 团队加成（60%~95%）
    local accuracy = math.min(0.95, 0.50 + scoutAbility * 0.02 + scoutBonus)

    -- 生成带误差的属性评估
    local reportedAttrs = {}
    local attrs = player.attributes or {}
    for key, val in pairs(attrs) do
        local errorRange = math.floor((1 - accuracy) * 6)  -- 误差范围
        local noise = math.random(-errorRange, errorRange)
        reportedAttrs[key] = math.max(1, math.min(20, val + noise))
    end

    -- 估算总评（带误差）
    local reportedOverall = player.overall or 50
    local overallNoise = math.random(-math.floor((1 - accuracy) * 10), math.floor((1 - accuracy) * 10))
    reportedOverall = math.max(20, math.min(99, reportedOverall + overallNoise))

    -- 潜力评估（年轻球员更准，老球员不太相关）
    local reportedPotential = player.potential or 50
    local age = (player.birthYear and (gameState.date.year - player.birthYear)) or 25
    if age <= 23 then
        local potNoise = math.random(-math.floor((1 - accuracy) * 8), math.floor((1 - accuracy) * 8))
        reportedPotential = math.max(20, math.min(99, reportedPotential + potNoise))
    end

    -- 推荐评级
    local recommendation = ScoutManager._getRecommendation(reportedOverall, reportedPotential, age)

    -- 生成报告
    local report = {
        id = gameState:generateId(),
        playerId = player.id,
        playerName = player.displayName,
        playerPosition = player.position,
        playerAge = age,
        teamName = ScoutManager._getPlayerTeamName(gameState, player),
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        accuracy = math.floor(accuracy * 100),
        overall = reportedOverall,
        potential = reportedPotential,
        attributes = reportedAttrs,
        recommendation = recommendation,
        wage = player.wage,
        value = player.value,
        contractEnd = player.contractEnd,
        expireDay = 0,  -- 将在每日清理中累加
    }

    gameState.scoutReports = gameState.scoutReports or {}
    table.insert(gameState.scoutReports, report)

    -- 发送消息通知
    MessageManager.send(gameState, "scout_report_ready", {
        player.displayName, recommendation
    })
end

function ScoutManager._getRecommendation(overall, potential, age)
    if potential >= 80 and age <= 21 then
        return "强烈推荐签入"
    elseif overall >= 75 then
        return "实力强劲，可即战"
    elseif potential >= 70 and age <= 23 then
        return "潜力新星，值得培养"
    elseif overall >= 60 then
        return "水平尚可，可作补充"
    else
        return "不建议签入"
    end
end

function ScoutManager._getPlayerTeamName(gameState, player)
    for _, team in pairs(gameState.teams) do
        for _, pid in ipairs(team.playerIds) do
            if pid == player.id then
                return team.shortName or team.name
            end
        end
    end
    return "自由球员"
end

function ScoutManager._getTeamScouts(gameState, team)
    local scouts = {}
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == Constants.STAFF_ROLES.SCOUT then
            table.insert(scouts, s)
        end
    end
    return scouts
end

function ScoutManager._cleanupExpiredReports(gameState)
    gameState.scoutReports = gameState.scoutReports or {}
    local valid = {}
    for _, report in ipairs(gameState.scoutReports) do
        report.expireDay = (report.expireDay or 0) + 1
        if report.expireDay <= REPORT_EXPIRY_DAYS then
            table.insert(valid, report)
        end
    end
    gameState.scoutReports = valid
end

return ScoutManager
