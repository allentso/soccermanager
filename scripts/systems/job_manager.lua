-- systems/job_manager.lua
-- 解雇/求职系统：失业状态、职位空缺、申请/应聘、主动邀约

local EventBus = require("scripts/app/event_bus")
local MessageManager = require("scripts/systems/message_manager")

local JobManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
-- 球队声望范围（与 reputation_manager 一致）
local TEAM_REP_MIN = 500
local TEAM_REP_MAX = 950
-- 经理声望范围
local MGR_REP_MIN = 1
local MGR_REP_MAX = 99

local MAX_JOB_LISTINGS = 5            -- 最多显示的空缺职位
local APPLICATION_COOLDOWN_DAYS = 7   -- 申请冷却期
local AI_HIRE_DELAY_DAYS = 21         -- AI球队雇新教练延迟
local OFFER_COOLDOWN_DAYS = 5         -- 主动邀约间隔
local OFFER_EXPIRE_DAYS = 7           -- 邀约过期天数
local MAX_CONCURRENT_OFFERS = 3       -- 最多同时持有邀约数

------------------------------------------------------
-- 工具函数
------------------------------------------------------

--- 将球队声望（500-950）归一化到经理声望尺度（1-99）
---@param teamRep number 球队声望（500-950范围）
---@return number 归一化后的值（1-99范围）
local function normalizeTeamRepToMgrScale(teamRep)
    return MGR_REP_MIN + (teamRep - TEAM_REP_MIN) / (TEAM_REP_MAX - TEAM_REP_MIN) * (MGR_REP_MAX - MGR_REP_MIN)
end

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
    gameState._pendingApplications = {}
    gameState._pendingOffers = {}  -- 清空旧邀约
    gameState._offerCooldown = 3   -- 被解雇后3天开始收到邀约
    gameState._firedFromTeamId = prevTeamId  -- 记录解雇来源，新赛季前不会收到该队邀约
    gameState._firedFromSeason = gameState.season

    -- 更新经理状态
    local manager = gameState:getPlayerManager()
    if manager then
        -- 记录履历（含本段任期比赛成绩）
        local team = gameState.teams[prevTeamId]
        if manager.addCareerEntry and team then
            local tenureStats = JobManager._getTenureStats(manager)
            manager:addCareerEntry(prevTeamId, team.name or "未知", manager._hiredSeason or gameState.season, gameState.season, {
                reason = "sacked",
                wins = tenureStats.wins,
                draws = tenureStats.draws,
                losses = tenureStats.losses,
            })
        end
        manager.teamId = nil
        manager.isUnemployed = true
        manager._tenureStartStats = nil
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
            -- 本赛季离开的球队不显示在空缺列表中
            if teamId == gameState._firedFromTeamId and gameState.season == gameState._firedFromSeason then
                goto continue_vacancy
            end
            table.insert(vacancies, {
                teamId = teamId,
                teamName = team.name or team.shortName,
                reputation = team.reputation or 50,
                leagueName = JobManager._getTeamLeagueName(gameState, teamId),
            })
        end
        ::continue_vacancy::
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

--- 申请职位（异步：提交后等待2-3天出结果）
---@param gameState table
---@param teamId number
---@return boolean submitted, string? error
function JobManager.applyForJob(gameState, teamId)
    if not gameState._isUnemployed then
        return false, "你还在职中，无法申请其他职位"
    end

    local team = gameState.teams[teamId]
    if not team then return false, "球队不存在" end
    if not team.managerVacant then return false, "该职位已被填补" end

    -- 检查是否已在审核中
    gameState._pendingApplications = gameState._pendingApplications or {}
    for _, app in ipairs(gameState._pendingApplications) do
        if app.teamId == teamId then
            return false, "该职位已申请，正在审核中"
        end
    end

    -- 提交申请（2-3天后出结果）
    local reviewDays = 2 + math.floor(Random() * 2)  -- 2~3天
    table.insert(gameState._pendingApplications, {
        teamId = teamId,
        teamName = team.name or team.shortName or "未知",
        daysLeft = reviewDays,
    })

    gameState:sendMessage({
        category = "job",
        title = "申请已提交",
        body = string.format("你的申请已发送给 %s，预计 %d 天内会有回复。", team.name or team.shortName, reviewDays),
        priority = "normal",
    })

    return true
end

--- 处理待审核的申请（每日调用）
---@param gameState table
function JobManager._processApplications(gameState)
    if not gameState._pendingApplications then return end
    if #gameState._pendingApplications == 0 then return end

    local remaining = {}
    for _, app in ipairs(gameState._pendingApplications) do
        app.daysLeft = app.daysLeft - 1
        if app.daysLeft <= 0 then
            -- 出结果
            local team = gameState.teams[app.teamId]
            if not team or not team.managerVacant then
                -- 职位已被填补
                gameState:sendMessage({
                    category = "job",
                    title = "求职结果",
                    body = string.format("%s 的空缺职位已被其他人填补。", app.teamName),
                    priority = "normal",
                })
            else
                -- 评估成功率（基于声望对比，归一化到同一尺度）
                local manager = gameState:getPlayerManager()
                local managerRep = manager and manager.reputation or 30
                local teamRepNorm = normalizeTeamRepToMgrScale(team.reputation or TEAM_REP_MIN)
                local repDiff = teamRepNorm - managerRep

                local baseChance = 0.6
                if repDiff > 30 then
                    baseChance = 0.15
                elseif repDiff > 20 then
                    baseChance = 0.30
                elseif repDiff > 10 then
                    baseChance = 0.45
                elseif repDiff > 0 then
                    baseChance = 0.60
                else
                    baseChance = 0.80
                end

                if Random() < baseChance then
                    -- 申请通过 → 加入待确认 offer 列表（玩家需要选择）
                    if not gameState._pendingOffers then gameState._pendingOffers = {} end
                    -- 查找联赛名
                    local leagueName = "未知联赛"
                    for _, lg in pairs(gameState.leagues or {}) do
                        for _, tid in ipairs(lg.teamIds or {}) do
                            if tid == app.teamId then
                                leagueName = lg.name or leagueName
                                break
                            end
                        end
                    end
                    table.insert(gameState._pendingOffers, {
                        teamId = app.teamId,
                        teamName = app.teamName,
                        leagueName = leagueName,
                        teamRep = team.reputation or 50,
                        source = "application",  -- 区分来源：申请通过
                        sentDate = { year = gameState.date.year, month = gameState.date.month, day = gameState.date.day },
                        expireDays = 5,  -- 5天有效期
                    })
                    gameState:sendMessage({
                        category = "job",
                        title = "求职结果 - 申请通过！",
                        body = string.format(
                            "%s 通过了你的主教练申请！\n\n" ..
                            "请在「我的资料」页面的求职中心查看并确认是否接受该职位。\n" ..
                            "该 Offer 将在 5 天后过期。",
                            app.teamName
                        ),
                        priority = "high",
                    })
                else
                    gameState:sendMessage({
                        category = "job",
                        title = "求职结果",
                        body = string.format("%s 经过考虑后拒绝了你的申请。不要气馁，继续尝试！", app.teamName),
                        priority = "normal",
                    })
                end
            end
        else
            table.insert(remaining, app)
        end
    end
    gameState._pendingApplications = remaining
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

--- 每日处理（审核结果、AI填补空缺、主动邀约）
---@param gameState table
function JobManager.processDaily(gameState)
    -- 处理待审核的申请
    if gameState._isUnemployed then
        JobManager._processApplications(gameState)
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

    -- 随机产生新空缺（模拟AI教练主动辞职/合同到期）
    if Random() < 0.04 then  -- 4% 每天（约每25天产生一个空缺）
        JobManager._randomVacancy(gameState)
    end

    -- 经理合同检查（每月1号执行）
    if gameState.date.day == 1 and not gameState._isUnemployed then
        -- 旧存档兼容：首次运行时为经理初始化合同
        local mgr = gameState:getPlayerManager()
        if mgr and mgr.teamId and not mgr.contractEnd then
            JobManager._initManagerContract(mgr, gameState, mgr.teamId)
        end
        JobManager.checkManagerRenewal(gameState)
        JobManager.checkManagerContractExpiry(gameState)
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

--- 是否有待回复的主教练邀约（失业状态）
---@param gameState table
---@return boolean
function JobManager.hasPendingOffers(gameState)
    if not gameState._isUnemployed then return false end
    local offers = gameState._pendingOffers
    return offers ~= nil and #offers > 0
end

--- 待处理邀约数量
---@param gameState table
---@return number
function JobManager.getPendingOfferCount(gameState)
    if not gameState._isUnemployed then return 0 end
    return #(gameState._pendingOffers or {})
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
            -- 解雇/离开的球队在本赛季内不会发起邀约
            if teamId == gameState._firedFromTeamId and gameState.season == gameState._firedFromSeason then
                goto continue_team
            end
            -- 已经发过邀约的跳过
            local alreadyOffered = false
            for _, offer in ipairs(pending) do
                if offer.teamId == teamId then alreadyOffered = true; break end
            end
            if not alreadyOffered then
                local teamRepNorm = normalizeTeamRepToMgrScale(team.reputation or TEAM_REP_MIN)
                -- 球队声望不能比经理高太多（归一化后超过40差距的不会主动来）
                if teamRepNorm - managerRep <= 40 then
                    -- 匹配分数：声望越接近越可能发邀约
                    local matchScore = 100 - math.abs(teamRepNorm - managerRep)
                    -- 空缺时间越长越急迫
                    local urgency = math.min(10, (team._vacantDays or 0) / 2)
                    table.insert(candidates, {
                        teamId = teamId,
                        score = matchScore + urgency,
                    })
                end
            end
        end
        ::continue_team::
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
                math.floor(offer.teamRep), boardObj, OFFER_EXPIRE_DAYS
            ),
            priority = "high",
            popup = true,
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

    local teamRepNorm = normalizeTeamRepToMgrScale(team.reputation or TEAM_REP_MIN)

    -- 寻找失业AI经理
    local bestCandidate = nil
    local bestScore = -1
    for _, mgr in pairs(gameState.managers or {}) do
        if mgr.isUnemployed and not mgr.isPlayer then
            local mgrRep = mgr.reputation or 30
            -- 声望匹配分数（归一化后在同一尺度比较）
            local matchScore = 100 - math.abs(teamRepNorm - mgrRep)
            -- AI经理是否接受：球队声望越高于自己越愿意
            local willingness = 0.5 + (teamRepNorm - mgrRep) * 0.01
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

        team.managerId = bestCandidate.id
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

--- 计算当前任期的比赛成绩（当前累计 - 入职时快照）
function JobManager._getTenureStats(manager)
    local s = manager.stats or {}
    local start = manager._tenureStartStats or { wins = 0, draws = 0, losses = 0 }
    return {
        wins = (s.wins or 0) - (start.wins or 0),
        draws = (s.draws or 0) - (start.draws or 0),
        losses = (s.losses or 0) - (start.losses or 0),
    }
end

function JobManager._acceptJob(gameState, teamId)
    local team = gameState.teams[teamId]

    -- 恢复玩家关联
    gameState.playerTeamId = teamId
    gameState._isUnemployed = false
    gameState._unemployedSince = nil
    gameState._pendingApplications = {}
    gameState._pendingOffers = {}
    gameState._offerCooldown = 0
    gameState._firedFromTeamId = nil
    gameState._firedFromSeason = nil

    -- 更新经理
    local manager = gameState:getPlayerManager()
    if manager then
        manager.teamId = teamId
        manager.isUnemployed = false
        manager._hiredSeason = gameState.season
        -- 记录任期开始时的累计成绩快照（用于离职时计算本段成绩）
        local s = manager.stats or {}
        manager._tenureStartStats = {
            wins = s.wins or 0,
            draws = s.draws or 0,
            losses = s.losses or 0,
        }
        -- 初始化经理合同
        JobManager._initManagerContract(manager, gameState, teamId)
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
    local tier = BoardManager.computeEffectiveTier(gameState, teamId)
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
            math.floor(team.reputation or 50),
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
-- 经理合同系统
------------------------------------------------------

--- 初始化经理合同（新入职时调用）
---@param manager table
---@param gameState table
---@param teamId number
function JobManager._initManagerContract(manager, gameState, teamId)
    local team = gameState.teams[teamId]
    local teamRep = team and team.reputation or 50
    -- 基于球队声望决定初始薪资
    local baseWage = math.floor(1000 + teamRep * 80)  -- 1000 ~ 8920
    manager.wage = baseWage
    manager.contractYears = 2
    manager.contractEnd = {
        year = gameState.date.year + 2,
        month = gameState.date.month,
    }
end

--- 获取经理合同剩余月数
---@param gameState table
---@param manager table
---@return number
function JobManager.getManagerContractMonths(gameState, manager)
    if not manager or not manager.contractEnd then return 99 end
    local endYear = manager.contractEnd.year or 2025
    local endMonth = manager.contractEnd.month or 6
    return (endYear - gameState.date.year) * 12 + (endMonth - gameState.date.month)
end

--- 俱乐部主动续约（每月处理一次，合同剩12个月时触发）
---@param gameState table
function JobManager.checkManagerRenewal(gameState)
    local manager = gameState:getPlayerManager()
    if not manager or not manager.teamId then return end

    local monthsLeft = JobManager.getManagerContractMonths(gameState, manager)

    -- 已经发过续约邀请了，不要重复
    if gameState._managerRenewalOffered then return end

    -- 合同剩余12个月以内时，俱乐部考虑续约
    if monthsLeft > 12 or monthsLeft <= 0 then return end

    local team = gameState.teams[manager.teamId]
    if not team then return end

    -- 俱乐部满意度影响是否续约
    local satisfaction = team.boardSatisfaction or 50
    if satisfaction < 30 then
        -- 不满意，不主动续约
        return
    end

    -- 计算续约条件
    local currentWage = manager.wage or 5000
    local raisePct = 1.0
    if satisfaction >= 70 then raisePct = 1.20  -- 很满意，涨薪20%
    elseif satisfaction >= 50 then raisePct = 1.10  -- 满意，涨薪10%
    else raisePct = 1.0 end  -- 一般，维持原薪

    local offeredWage = math.floor(currentWage * raisePct)
    local offeredYears = 2
    if satisfaction >= 80 then offeredYears = 3 end

    gameState._managerRenewalOffered = true
    gameState._managerRenewalOffer = {
        wage = offeredWage,
        years = offeredYears,
        teamId = manager.teamId,
    }

    gameState:sendMessage({
        category = "contract",
        title = "续约提议 - " .. (team.name or "俱乐部"),
        body = string.format(
            "%s 的董事会对你的工作表示%s，希望与你续约。\n\n" ..
            "📋 续约条件:\n" ..
            "• 新周薪: %s（当前 %s）\n" ..
            "• 合同年限: %d 年\n\n" ..
            "请在下方选择是否接受，或前往「我的资料」页面处理。",
            team.name or "俱乐部",
            satisfaction >= 70 and "非常满意" or "认可",
            JobManager._formatMoney(offeredWage),
            JobManager._formatMoney(currentWage),
            offeredYears
        ),
        priority = "high",
        popup = true,
        actions = {
            {
                label = "接受续约",
                actionId = "accept_manager_renewal",
                data = {},
            },
            {
                label = "拒绝续约",
                actionId = "decline_manager_renewal",
                data = {},
            },
        },
    })
end

--- 接受俱乐部续约
---@param gameState table
---@return boolean success, string? error
function JobManager.acceptManagerRenewal(gameState)
    local offer = gameState._managerRenewalOffer
    if not offer then return false, "没有待处理的续约提议" end

    local manager = gameState:getPlayerManager()
    if not manager then return false, "经理不存在" end

    manager.wage = offer.wage
    manager.contractEnd = {
        year = gameState.date.year + offer.years,
        month = gameState.date.month,
    }
    manager.contractYears = offer.years

    gameState._managerRenewalOffer = nil
    gameState._managerRenewalOffered = nil

    local team = gameState.teams[offer.teamId]
    gameState:sendMessage({
        category = "contract",
        title = "续约成功",
        body = string.format("你已与 %s 成功续约！新合同: %s/周，为期%d年（至%d年%d月）。",
            team and team.name or "俱乐部",
            JobManager._formatMoney(offer.wage),
            offer.years,
            manager.contractEnd.year,
            manager.contractEnd.month),
        priority = "high",
    })
    return true
end

--- 拒绝俱乐部续约
---@param gameState table
function JobManager.declineManagerRenewal(gameState)
    local offer = gameState._managerRenewalOffer
    gameState._managerRenewalOffer = nil
    -- 不重置 _managerRenewalOffered，本赛季不再重复提议

    if offer then
        local team = gameState.teams[offer.teamId]
        gameState:sendMessage({
            category = "contract",
            title = "续约被拒",
            body = string.format("你拒绝了 %s 的续约提议。合同将在到期后结束。",
                team and team.name or "俱乐部"),
            priority = "normal",
        })
    end
end

--- 处理经理合同到期
---@param gameState table
function JobManager.checkManagerContractExpiry(gameState)
    local manager = gameState:getPlayerManager()
    if not manager or not manager.teamId then return end
    if not manager.contractEnd then return end

    local monthsLeft = JobManager.getManagerContractMonths(gameState, manager)
    if monthsLeft <= 0 then
        -- 合同到期，进入自由身
        local prevTeamId = manager.teamId
        local team = gameState.teams[prevTeamId]

        gameState:sendMessage({
            category = "contract",
            title = "合同到期",
            body = string.format("你与 %s 的合同已到期。你现在是自由身。",
                team and team.name or "俱乐部"),
            priority = "high",
        })

        -- 复用 handleSacked 的逻辑（设为失业状态），但原因不同
        if manager.addCareerEntry and team then
            local tenureStats = JobManager._getTenureStats(manager)
            manager:addCareerEntry(prevTeamId, team.name or "未知", manager._hiredSeason or gameState.season, gameState.season, {
                reason = "contract_expired",
                wins = tenureStats.wins,
                draws = tenureStats.draws,
                losses = tenureStats.losses,
            })
        end

        gameState.playerTeamId = nil
        gameState._isUnemployed = true
        gameState._unemployedSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
        gameState._pendingApplications = {}
        gameState._pendingOffers = {}
        gameState._offerCooldown = 3
        gameState._firedFromTeamId = prevTeamId  -- 合同到期离队，新赛季前不会收到该队邀约
        gameState._firedFromSeason = gameState.season
        gameState._managerRenewalOffer = nil
        gameState._managerRenewalOffered = nil

        manager.teamId = nil
        manager.isUnemployed = true
        manager.contractEnd = nil

        if prevTeamId and gameState.teams[prevTeamId] then
            gameState.teams[prevTeamId].managerVacant = true
            gameState.teams[prevTeamId].vacantSince = {
                year = gameState.date.year,
                month = gameState.date.month,
                day = gameState.date.day,
            }
            gameState.teams[prevTeamId]._vacantDays = 0
        end

        EventBus.emit("player_unemployed", {prevTeamId = prevTeamId, reason = "contract_expired"})
    end
end

--- 主动辞职
---@param gameState table
---@return boolean success, string? error
function JobManager.handleResign(gameState)
    local manager = gameState:getPlayerManager()
    if not manager or not manager.teamId then
        return false, "你当前没有执教球队"
    end

    local prevTeamId = manager.teamId
    local team = gameState.teams[prevTeamId]

    -- 记录履历（含本段任期比赛成绩）
    if manager.addCareerEntry and team then
        local tenureStats = JobManager._getTenureStats(manager)
        manager:addCareerEntry(prevTeamId, team.name or "未知", manager._hiredSeason or gameState.season, gameState.season, {
            reason = "resigned",
            wins = tenureStats.wins,
            draws = tenureStats.draws,
            losses = tenureStats.losses,
        })
    end

    -- 进入失业状态
    gameState.playerTeamId = nil
    gameState._isUnemployed = true
    gameState._unemployedSince = {
        year = gameState.date.year,
        month = gameState.date.month,
        day = gameState.date.day,
    }
    gameState._pendingApplications = {}
    gameState._pendingOffers = {}
    gameState._offerCooldown = 5  -- 辞职后5天开始收到邀约
    gameState._firedFromTeamId = prevTeamId  -- 离开的球队新赛季前不会回聘
    gameState._firedFromSeason = gameState.season
    gameState._managerRenewalOffer = nil
    gameState._managerRenewalOffered = nil

    manager.teamId = nil
    manager.isUnemployed = true

    -- 标记球队空缺
    if prevTeamId and gameState.teams[prevTeamId] then
        gameState.teams[prevTeamId].managerVacant = true
        gameState.teams[prevTeamId].vacantSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
        gameState.teams[prevTeamId]._vacantDays = 0
    end

    gameState:sendMessage({
        category = "job",
        title = "辞职成功",
        body = string.format("你已辞去 %s 的主教练职位。现在是自由身，可以寻找新的机会。",
            team and team.name or "俱乐部"),
        priority = "high",
    })

    -- 发布新闻
    gameState:addNews({
        category = "transfers",
        title = "教练离任",
        body = string.format("%s 的主教练%s因个人原因辞去职务。",
            team and team.name or "球队", manager.displayName or ""),
    })

    EventBus.emit("player_unemployed", {prevTeamId = prevTeamId, reason = "resigned"})
    return true
end

--- 顶级联赛降级：强制解约并进入失业状态
---@param gameState table
---@param prevTeamId number
---@param divisionName string 降级目标联赛名称（如「英冠」）
function JobManager.handleRelegation(gameState, prevTeamId, divisionName)
    if not prevTeamId or prevTeamId ~= gameState.playerTeamId then return end
    if gameState._cheatAutoPlay then return end

    local manager = gameState:getPlayerManager()
    local team = gameState.teams[prevTeamId]
    divisionName = divisionName or "二级联赛"

    if manager and manager.addCareerEntry and team then
        local tenureStats = JobManager._getTenureStats(manager)
        manager:addCareerEntry(prevTeamId, team.name or "未知", manager._hiredSeason or gameState.season, gameState.season, {
            reason = "relegated",
            wins = tenureStats.wins,
            draws = tenureStats.draws,
            losses = tenureStats.losses,
        })
    end

    gameState.playerTeamId = nil
    gameState.league = nil
    gameState.playerLeagueId = nil
    gameState._isUnemployed = true
    gameState._unemployedSince = {
        year = gameState.date.year,
        month = gameState.date.month,
        day = gameState.date.day,
    }
    gameState._pendingApplications = {}
    gameState._pendingOffers = {}
    gameState._offerCooldown = 3
    gameState._firedFromTeamId = prevTeamId
    gameState._firedFromSeason = gameState.season
    gameState._managerRenewalOffer = nil
    gameState._managerRenewalOffered = nil

    if manager then
        manager.teamId = nil
        manager.isUnemployed = true
        manager._tenureStartStats = nil
    end

    if team then
        team.managerId = nil
        team.managerVacant = true
        team.vacantSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
        team._vacantDays = 0
    end

    gameState:sendMessage({
        category = "job",
        title = "降级解约",
        body = string.format(
            "球队降级至%s，董事会与你解约。你现在是自由身，需要寻找新的执教机会。",
            divisionName),
        priority = "critical",
    })

    if team then
        gameState:addNews({
            category = "transfers",
            title = "教练离任",
            body = string.format("%s 降级后，主教练%s与俱乐部解约。",
                team.name or "球队", manager and manager.displayName or ""),
        })
    end

    -- 降级后立即由 AI 接管（不等待 processDaily 延迟）
    JobManager._aiHireManager(gameState, prevTeamId)

    EventBus.emit("player_unemployed", { prevTeamId = prevTeamId, reason = "relegated" })
end

--- 格式化金额
function JobManager._formatMoney(amount)
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("%.1fK", amount / 1000)
    end
    return tostring(amount)
end

------------------------------------------------------
-- 事件监听初始化
------------------------------------------------------
-- manager_sacked 事件由 board_manager._triggerPlayerSack 触发后直接调用 handleSacked
-- 无需额外的 EventBus 监听

return JobManager
