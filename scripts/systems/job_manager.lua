-- systems/job_manager.lua
-- 解雇/求职系统：失业状态、职位空缺、申请/应聘、主动邀约

local EventBus = require("scripts/app/event_bus")
local MessageManager = require("scripts/systems/message_manager")

local JobManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local MAX_JOB_LISTINGS = 5            -- 最多显示的空缺职位
local APPLICATION_COOLDOWN_DAYS = 7   -- 申请冷却期
local AI_HIRE_DELAY_DAYS = 14         -- AI球队雇新教练延迟
local OFFER_COOLDOWN_DAYS = 5         -- 主动邀约间隔
local OFFER_EXPIRE_DAYS = 7           -- 邀约过期天数
local MAX_CONCURRENT_OFFERS = 3       -- 最多同时持有邀约数

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
    gameState._pendingOffers = {}  -- 清空旧邀约
    gameState._offerCooldown = 3   -- 被解雇后3天开始收到邀约

    -- 更新经理状态
    local manager = gameState:getPlayerManager()
    if manager then
        -- 记录履历
        local team = gameState.teams[prevTeamId]
        if manager.addCareerEntry and team then
            manager:addCareerEntry(prevTeamId, team.name or "未知", manager._hiredSeason or gameState.season, gameState.season, {
                reason = "sacked",
            })
        end
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
        gameState.teams[prevTeamId]._vacantDays = 0
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

    local success = Random() < baseChance

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

--- 接受主动邀约
---@param gameState table
---@param teamId number
---@return boolean success
function JobManager.acceptOffer(gameState, teamId)
    if not gameState._isUnemployed then return false end

    local team = gameState.teams[teamId]
    if not team then return false end

    -- 清空其他邀约
    gameState._pendingOffers = {}

    -- 接受工作
    JobManager._acceptJob(gameState, teamId)
    return true
end

--- 拒绝主动邀约
---@param gameState table
---@param teamId number
function JobManager.declineOffer(gameState, teamId)
    local offers = gameState._pendingOffers or {}
    for i, offer in ipairs(offers) do
        if offer.teamId == teamId then
            table.remove(offers, i)
            break
        end
    end

    local team = gameState.teams[teamId]
    if team then
        gameState:sendMessage({
            category = "job",
            title = "已婉拒邀约",
            body = string.format("你婉拒了 %s 的主教练邀约。", team.name or "球队"),
            priority = "normal",
        })
    end
end

--- 每日处理（冷却倒计时、AI填补空缺、主动邀约）
---@param gameState table
function JobManager.processDaily(gameState)
    -- 玩家申请冷却
    if (gameState._applicationCooldown or 0) > 0 then
        gameState._applicationCooldown = gameState._applicationCooldown - 1
    end

    -- 邀约冷却
    if (gameState._offerCooldown or 0) > 0 then
        gameState._offerCooldown = gameState._offerCooldown - 1
    end

    -- 清理过期邀约
    JobManager._cleanExpiredOffers(gameState)

    -- 主动邀约系统：空缺球队主动联系失业玩家
    if gameState._isUnemployed and (gameState._offerCooldown or 0) <= 0 then
        JobManager._generateProactiveOffers(gameState)
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

    -- 随机产生新空缺（小概率，模拟AI教练主动辞职/合同到期）
    if Random() < 0.003 then  -- ~0.3% 每天
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

--- 获取待处理邀约列表
---@param gameState table
---@return table[]
function JobManager.getPendingOffers(gameState)
    return gameState._pendingOffers or {}
end

------------------------------------------------------
-- 主动邀约系统
------------------------------------------------------

--- 空缺球队主动向失业玩家发送邀约
function JobManager._generateProactiveOffers(gameState)
    local manager = gameState:getPlayerManager()
    if not manager then return end
    local managerRep = manager.reputation or 30

    -- 已有太多未处理邀约
    local pending = gameState._pendingOffers or {}
    if #pending >= MAX_CONCURRENT_OFFERS then return end

    -- 收集所有空缺球队，按声望匹配度排序
    local candidates = {}
    for teamId, team in pairs(gameState.teams) do
        if team.managerVacant then
            -- 已经发过邀约的跳过
            local alreadyOffered = false
            for _, offer in ipairs(pending) do
                if offer.teamId == teamId then alreadyOffered = true; break end
            end
            if not alreadyOffered then
                local teamRep = team.reputation or 50
                -- 球队声望不能比经理高太多（超过40差距的不会主动来）
                if teamRep - managerRep <= 40 then
                    -- 匹配分数：声望越接近越可能发邀约
                    local matchScore = 100 - math.abs(teamRep - managerRep)
                    -- 空缺时间越长越急迫
                    local urgency = math.min(10, (team._vacantDays or 0) / 2)
                    table.insert(candidates, {
                        teamId = teamId,
                        score = matchScore + urgency,
                    })
                end
            end
        end
    end

    if #candidates == 0 then return end

    -- 按分数排序，取最佳候选
    table.sort(candidates, function(a, b) return a.score > b.score end)

    -- 每天最多产生1个邀约，概率基于失业天数（越久越容易收到）
    local unemployedDays = JobManager.getUnemployedDays(gameState)
    local offerChance = math.min(0.6, 0.15 + unemployedDays * 0.02)  -- 15%基础，每天+2%，上限60%

    if Random() < offerChance then
        local chosen = candidates[1]
        local team = gameState.teams[chosen.teamId]
        if not team then return end

        -- 记录邀约
        local offer = {
            teamId = chosen.teamId,
            teamName = team.name or team.shortName,
            teamRep = team.reputation or 50,
            leagueName = JobManager._getTeamLeagueName(gameState, chosen.teamId),
            sentDate = {
                year = gameState.date.year,
                month = gameState.date.month,
                day = gameState.date.day,
            },
            expireDays = OFFER_EXPIRE_DAYS,
        }
        if not gameState._pendingOffers then gameState._pendingOffers = {} end
        table.insert(gameState._pendingOffers, offer)

        -- 设置冷却（避免连续收到邀约）
        gameState._offerCooldown = OFFER_COOLDOWN_DAYS

        -- 发送邮箱消息
        local boardObj = team.boardObjective or "待定"
        gameState:sendMessage({
            category = "job",
            title = "💼 主教练邀约 - " .. (team.name or "球队"),
            body = string.format(
                "%s 的董事会向你发出了主教练邀约！\n\n" ..
                "📋 球队信息:\n" ..
                "• 球队: %s\n" ..
                "• 联赛: %s\n" ..
                "• 声望: %d\n" ..
                "• 赛季目标: %s\n\n" ..
                "这份邀约将在 %d 天后过期。",
                team.name, team.name, offer.leagueName,
                offer.teamRep, boardObj, OFFER_EXPIRE_DAYS
            ),
            priority = "high",
            actions = {
                {
                    label = "接受邀约",
                    actionId = "accept_job_offer",
                    data = { teamId = chosen.teamId },
                },
                {
                    label = "婉拒",
                    actionId = "decline_job_offer",
                    data = { teamId = chosen.teamId },
                },
            },
        })
    end
end

--- 清理过期邀约
function JobManager._cleanExpiredOffers(gameState)
    local offers = gameState._pendingOffers
    if not offers then return end

    local i = 1
    while i <= #offers do
        local offer = offers[i]
        offer.expireDays = (offer.expireDays or OFFER_EXPIRE_DAYS) - 1
        if offer.expireDays <= 0 then
            -- 过期：球队不再等待
            table.remove(offers, i)
        else
            i = i + 1
        end
    end
end

------------------------------------------------------
-- AI教练雇佣逻辑（增强版：声望匹配 + 概率接受）
------------------------------------------------------

function JobManager._aiHireManager(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return end

    local teamRep = team.reputation or 50

    -- 寻找失业AI经理
    local bestCandidate = nil
    local bestScore = -1
    for _, mgr in pairs(gameState.managers or {}) do
        if mgr.isUnemployed and not mgr.isPlayer then
            local mgrRep = mgr.reputation or 30
            -- 声望匹配分数
            local matchScore = 100 - math.abs(teamRep - mgrRep)
            -- AI经理是否接受：球队声望越高于自己越愿意
            local willingness = 0.5 + (teamRep - mgrRep) * 0.01  -- 球队声望高→更愿意
            willingness = math.max(0.2, math.min(0.95, willingness))

            if Random() < willingness and matchScore > bestScore then
                bestScore = matchScore
                bestCandidate = mgr
            end
        end
    end

    if bestCandidate then
        -- 失业AI经理接受邀约
        bestCandidate.teamId = teamId
        bestCandidate.isUnemployed = false
        bestCandidate._unemployedSince = nil
        bestCandidate._hiredSeason = gameState.season

        team.managerVacant = false
        team.vacantSince = nil
        team._vacantDays = nil
        team.boardSatisfaction = 50  -- 新教练蜜月期
        team.boardWarnings = 0

        gameState:addNews({
            category = "transfers",
            title = "新帅上任",
            body = string.format("%s 聘请 %s 为新任主教练。",
                team.name or "球队", bestCandidate.displayName or "新教练"),
        })
    else
        -- 没有合适的失业AI经理，生成一位新经理
        local WorldGenerator = require("scripts/systems/world_generator")
        local newMgr = WorldGenerator.generateAIManager(gameState, teamId, team.country)
        if newMgr then
            newMgr._hiredSeason = gameState.season
        end

        team.managerVacant = false
        team.vacantSince = nil
        team._vacantDays = nil
        team.boardSatisfaction = 50
        team.boardWarnings = 0

        gameState:addNews({
            category = "transfers",
            title = "新帅上任",
            body = string.format("%s 任命了新的主教练。", team.name or "球队"),
        })
    end
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
    gameState._pendingOffers = {}
    gameState._offerCooldown = 0

    -- 更新经理
    local manager = gameState:getPlayerManager()
    if manager then
        manager.teamId = teamId
        manager.isUnemployed = false
        manager._hiredSeason = gameState.season
    end

    -- 清除球队空缺
    team.managerVacant = false
    team.vacantSince = nil
    team._vacantDays = nil
    team.boardSatisfaction = 50  -- 新官上任蜜月期
    team.boardWarnings = 0

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

    -- 生成赛季目标
    local BoardManager = require("scripts/systems/board_manager")
    local rep = team.reputation or 50
    local tier = BoardManager._getReputationTier(rep)
    local OBJECTIVES_LOCAL = {
        elite   = { targets = {"夺冠", "前2名", "前3名"} },
        strong  = { targets = {"前3名", "前4名", "上半区"} },
        mid     = { targets = {"上半区", "前10名", "避免降级"} },
        weak    = { targets = {"保级", "避免垫底", "前15名"} },
        lowest  = { targets = {"保级", "避免垫底"} },
    }
    local targets = OBJECTIVES_LOCAL[tier].targets
    team.boardObjective = targets[RandomInt(1, #targets)]

    gameState:sendMessage({
        category = "job",
        title = "任命通知",
        body = string.format(
            "恭喜！你已被 %s 聘为新任主教练！\n\n" ..
            "📋 球队信息:\n" ..
            "• 联赛: %s\n" ..
            "• 声望: %d\n" ..
            "• 赛季目标: %s\n\n" ..
            "祝你好运！",
            team.name or team.shortName,
            JobManager._getTeamLeagueName(gameState, teamId),
            team.reputation or 50,
            team.boardObjective
        ),
        priority = "high",
    })

    EventBus.emit("player_hired", {teamId = teamId})
end

function JobManager._randomVacancy(gameState)
    -- 排除玩家球队和已空缺球队
    local candidates = {}
    for teamId, team in pairs(gameState.teams) do
        if teamId ~= gameState.playerTeamId and not team.managerVacant then
            table.insert(candidates, teamId)
        end
    end
    if #candidates == 0 then return end

    local teamId = candidates[RandomInt(1, #candidates)]
    local team = gameState.teams[teamId]

    -- 找到该队经理
    local managerId = nil
    for id, mgr in pairs(gameState.managers or {}) do
        if mgr.teamId == teamId and not mgr.isPlayer then
            managerId = id
            break
        end
    end

    -- 标记空缺
    team.managerVacant = true
    team.vacantSince = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
    team._vacantDays = 0

    -- 更新经理状态
    if managerId and gameState.managers[managerId] then
        local mgr = gameState.managers[managerId]
        mgr.teamId = nil
        mgr.isUnemployed = true
        mgr._unemployedSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
    end

    -- 决定离职原因
    local reasons = {
        "因个人原因辞去主教练职务",
        "与董事会理念不合，双方协商解约",
        "合同到期后未能续约",
        "因家庭原因宣布离任",
    }
    local reason = reasons[RandomInt(1, #reasons)]

    -- 发布新闻
    gameState:addNews({
        category = "transfers",
        title = "教练离任",
        body = string.format("%s 的主教练%s。", team.name or "球队", reason),
    })

    -- 如果玩家失业，提醒有新空缺
    if gameState._isUnemployed then
        gameState:sendMessage({
            category = "job",
            title = "新职位空缺",
            body = string.format("%s 正在招聘主教练，你可以等待邀约或前往求职页面申请。",
                team.name or team.shortName),
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
-- manager_sacked 事件由 board_manager._triggerPlayerSack 触发后直接调用 handleSacked
-- 无需额外的 EventBus 监听

return JobManager
