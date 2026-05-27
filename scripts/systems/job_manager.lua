-- systems/job_manager.lua
-- 解雇/求职系统：失业状态、职位空缺、申请/应聘

local EventBus = require("scripts/app/event_bus")
local MessageManager = require("scripts/systems/message_manager")

local JobManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local MAX_JOB_LISTINGS = 5            -- 最多显示的空缺职位
local APPLICATION_COOLDOWN_DAYS = 7   -- 申请冷却期
local AI_HIRE_DELAY_DAYS = 14         -- AI球队雇新教练延迟

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 处理被解雇后的状态变更
---@param gameState table
function JobManager.handleSacked(gameState)
    local prevTeamId = gameState.playerTeamId

    -- 清除玩家与球队的关联
    gameState.playerTeamId = nil
    gameState._isUnemployed = true
    gameState._unemployedSince = {
        year = gameState.date.year,
        month = gameState.date.month,
        day = gameState.date.day,
    }
    gameState._applicationCooldown = 0

    -- 更新经理状态
    local manager = gameState:getPlayerManager()
    if manager then
        manager.teamId = nil
        manager.isUnemployed = true
    end

    -- 标记原球队需要新教练
    if prevTeamId and gameState.teams[prevTeamId] then
        gameState.teams[prevTeamId].managerVacant = true
        gameState.teams[prevTeamId].vacantSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
    end

    EventBus.emit("player_unemployed", {prevTeamId = prevTeamId})
end

--- 获取当前可申请的职位空缺列表
---@param gameState table
---@return table[] {teamId, teamName, reputation, league}
function JobManager.getVacancies(gameState)
    local vacancies = {}
    for teamId, team in pairs(gameState.teams) do
        if team.managerVacant then
            table.insert(vacancies, {
                teamId = teamId,
                teamName = team.name or team.shortName,
                reputation = team.reputation or 50,
                leagueName = JobManager._getTeamLeagueName(gameState, teamId),
            })
        end
    end
    -- 按声望排序
    table.sort(vacancies, function(a, b) return a.reputation > b.reputation end)
    -- 限制数量
    local result = {}
    for i = 1, math.min(MAX_JOB_LISTINGS, #vacancies) do
        result[i] = vacancies[i]
    end
    return result
end

--- 申请职位
---@param gameState table
---@param teamId number
---@return boolean success, string? error
function JobManager.applyForJob(gameState, teamId)
    if not gameState._isUnemployed then
        return false, "你还在职中，无法申请其他职位"
    end

    if (gameState._applicationCooldown or 0) > 0 then
        return false, string.format("申请冷却中，还需等待 %d 天", gameState._applicationCooldown)
    end

    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end
    if not team.managerVacant then return false, "该职位已被填补" end

    -- 评估成功率（基于声望对比）
    local manager = gameState:getPlayerManager()
    local managerRep = manager and manager.reputation or 30
    local teamRep = team.reputation or 50
    local repDiff = teamRep - managerRep

    -- 成功概率：声望差越大越难
    local baseChance = 0.6
    if repDiff > 30 then
        baseChance = 0.1
    elseif repDiff > 20 then
        baseChance = 0.25
    elseif repDiff > 10 then
        baseChance = 0.40
    elseif repDiff > 0 then
        baseChance = 0.55
    else
        baseChance = 0.75
    end

    local success = math.random() < baseChance

    if success then
        -- 录用！
        JobManager._acceptJob(gameState, teamId)
        return true
    else
        -- 拒绝
        gameState._applicationCooldown = APPLICATION_COOLDOWN_DAYS
        gameState:sendMessage({
            category = "job",
            title = "求职结果",
            body = string.format("%s 拒绝了你的申请。继续寻找其他机会吧。", team.name or team.shortName),
            priority = "normal",
        })
        return false, "申请被拒绝"
    end
end

--- 每日处理（冷却倒计时、AI填补空缺）
---@param gameState table
function JobManager.processDaily(gameState)
    -- 玩家申请冷却
    if (gameState._applicationCooldown or 0) > 0 then
        gameState._applicationCooldown = gameState._applicationCooldown - 1
    end

    -- AI 球队空缺填补
    for teamId, team in pairs(gameState.teams) do
        if team.managerVacant and teamId ~= gameState.playerTeamId then
            team._vacantDays = (team._vacantDays or 0) + 1
            if team._vacantDays >= AI_HIRE_DELAY_DAYS then
                JobManager._aiHireManager(gameState, teamId)
            end
        end
    end

    -- 随机产生新空缺（小概率，模拟AI教练被解雇）
    if math.random() < 0.005 then  -- ~0.5% 每天
        JobManager._randomVacancy(gameState)
    end
end

--- 检查是否处于失业状态
---@param gameState table
---@return boolean
function JobManager.isUnemployed(gameState)
    return gameState._isUnemployed == true
end

--- 获取失业天数
---@param gameState table
---@return number
function JobManager.getUnemployedDays(gameState)
    if not gameState._isUnemployed or not gameState._unemployedSince then
        return 0
    end
    local since = gameState._unemployedSince
    local days = (gameState.date.year - since.year) * 365
        + (gameState.date.month - since.month) * 30
        + (gameState.date.day - since.day)
    return math.max(0, days)
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

function JobManager._acceptJob(gameState, teamId)
    local team = gameState.teams[teamId]

    -- 恢复玩家关联
    gameState.playerTeamId = teamId
    gameState._isUnemployed = false
    gameState._unemployedSince = nil
    gameState._applicationCooldown = 0

    -- 更新经理
    local manager = gameState:getPlayerManager()
    if manager then
        manager.teamId = teamId
        manager.isUnemployed = false
    end

    -- 清除球队空缺
    team.managerVacant = false
    team.vacantSince = nil
    team._vacantDays = nil

    -- 更新玩家联赛引用
    for key, lg in pairs(gameState.leagues) do
        for _, tid in ipairs(lg.teamIds) do
            if tid == teamId then
                gameState.league = lg
                gameState.playerLeagueId = key
                break
            end
        end
    end

    -- 初始化董事会目标
    team.boardSatisfaction = 50
    team.boardWarnings = 0

    gameState:sendMessage({
        category = "job",
        title = "任命通知",
        body = string.format("恭喜！你已被 %s 聘为新任主教练。祝你好运！", team.name or team.shortName),
        priority = "high",
    })

    EventBus.emit("player_hired", {teamId = teamId})
end

function JobManager._aiHireManager(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return end

    team.managerVacant = false
    team.vacantSince = nil
    team._vacantDays = nil

    -- 生成简单的AI经理信息（不需要完整模拟）
    gameState:addNews({
        category = "transfers",
        title = "新帅上任",
        body = string.format("%s 任命了新的主教练。", team.name or team.shortName),
    })
end

function JobManager._randomVacancy(gameState)
    -- 排除玩家球队
    local candidates = {}
    for teamId, team in pairs(gameState.teams) do
        if teamId ~= gameState.playerTeamId and not team.managerVacant then
            table.insert(candidates, teamId)
        end
    end
    if #candidates == 0 then return end

    local teamId = candidates[math.random(1, #candidates)]
    local team = gameState.teams[teamId]
    team.managerVacant = true
    team.vacantSince = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
    team._vacantDays = 0

    -- 发布新闻
    gameState:addNews({
        category = "transfers",
        title = "教练离任",
        body = string.format("%s 宣布与主教练解约。", team.name or team.shortName),
    })

    -- 如果玩家失业，提醒有新空缺
    if gameState._isUnemployed then
        gameState:sendMessage({
            category = "job",
            title = "新职位空缺",
            body = string.format("%s 正在招聘主教练，你可以前往求职页面申请。", team.name or team.shortName),
            priority = "normal",
        })
    end
end

function JobManager._getTeamLeagueName(gameState, teamId)
    for _, lg in pairs(gameState.leagues) do
        for _, tid in ipairs(lg.teamIds) do
            if tid == teamId then
                return lg.name or "未知联赛"
            end
        end
    end
    return "未知联赛"
end

------------------------------------------------------
-- 事件监听初始化
------------------------------------------------------
EventBus.on("manager_sacked", function(data)
    -- 由 board_manager 触发，此处仅标记（实际调用在 turn_processor 中）
end)

return JobManager
