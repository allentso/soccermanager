-- systems/board_manager.lua
-- 董事会系统：赛季目标、满意度评价、警告、解雇（玩家 + AI教练）

local EventBus = require("scripts/app/event_bus")
local MessageManager = require("scripts/systems/message_manager")

local BoardManager = {}

------------------------------------------------------
-- 目标类型定义
------------------------------------------------------
local OBJECTIVES = {
    -- 按声望分档
    elite   = { min = 80, targets = {"夺冠", "前2名", "前3名"} },
    strong  = { min = 65, targets = {"前3名", "前4名", "上半区"} },
    mid     = { min = 45, targets = {"上半区", "前10名", "避免降级"} },
    weak    = { min = 25, targets = {"保级", "避免垫底", "前15名"} },
    lowest  = { min = 0,  targets = {"保级", "避免垫底"} },
}

-- 目标对应的排名阈值（用于评估）
local TARGET_THRESHOLDS = {
    ["夺冠"]   = 1,
    ["前2名"]  = 2,
    ["前3名"]  = 3,
    ["前4名"]  = 4,
    ["上半区"] = 10,
    ["前10名"] = 10,
    ["前15名"] = 15,
    ["保级"]   = 17,
    ["避免垫底"] = 19,
    ["避免降级"] = 17,
}

-- AI教练解雇阈值
local AI_SACK_SATISFACTION = 20       -- 满意度低于此值触发解雇
local AI_WARNING_THRESHOLD = 25       -- 满意度低于此值触发警告
local PLAYER_SACK_WARNINGS = 3       -- 玩家累计警告次数触发解雇

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 生成赛季目标（赛季开始时为所有球队调用）
---@param gameState table
function BoardManager.generateSeasonObjectives(gameState)
    for _, team in pairs(gameState.teams) do
        local rep = team.reputation or 50
        local tier = BoardManager._getReputationTier(rep)
        local targets = OBJECTIVES[tier].targets
        local target = targets[RandomInt(1, #targets)]

        team.boardObjective = target
        team.boardSatisfaction = team.boardSatisfaction or 50  -- 保留上赛季残余满意度，新球队初始50
        team.boardWarnings = team.boardWarnings or 0
    end

    -- 给玩家发消息
    local playerTeam = gameState:getPlayerTeam()
    if playerTeam and playerTeam.boardObjective then
        MessageManager.send(gameState, "board_objective", { playerTeam.boardObjective })
    end
end

--- 旧接口兼容：只给玩家球队生成目标
---@param gameState table
function BoardManager.generateSeasonObjective(gameState)
    BoardManager.generateSeasonObjectives(gameState)
end

--- 每月评估满意度（所有球队）
---@param gameState table
function BoardManager.monthlyEvaluation(gameState)
    for teamId, team in pairs(gameState.teams) do
        if not team.boardObjective then goto continue_team end

        -- 找到该球队所在联赛
        local league = nil
        for _, lg in pairs(gameState.leagues or {}) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == teamId then
                    league = lg
                    break
                end
            end
            if league then break end
        end
        if not league then goto continue_team end

        local position = league:getTeamPosition(teamId)
        if not position then goto continue_team end

        local threshold = TARGET_THRESHOLDS[team.boardObjective] or 10
        local totalTeams = #league.teamIds

        -- 计算目标达成度 (-1.0 ~ +1.0)
        local progressRatio = 0
        if position <= threshold then
            progressRatio = (threshold - position) / math.max(threshold, 1)
            progressRatio = math.min(progressRatio, 1.0)
        else
            progressRatio = -(position - threshold) / math.max(totalTeams - threshold, 1)
            progressRatio = math.max(progressRatio, -1.0)
        end

        -- 满意度变化
        local delta = math.floor(progressRatio * 15)

        -- 近期状态加成
        local form = team.recentForm or {}
        local formBonus = 0
        for _, r in ipairs(form) do
            if r == "W" then formBonus = formBonus + 2
            elseif r == "L" then formBonus = formBonus - 2
            end
        end
        delta = delta + formBonus

        team.boardSatisfaction = math.max(0, math.min(100, (team.boardSatisfaction or 50) + delta))

        -- 判断是否为玩家球队
        local isPlayerTeam = (teamId == gameState.playerTeamId)

        if team.boardSatisfaction < AI_WARNING_THRESHOLD then
            team.boardWarnings = (team.boardWarnings or 0) + 1

            if isPlayerTeam then
                -- 玩家：发警告消息
                local reason = string.format(
                    "球队当前排名第%d，距离目标(%s)差距较大。满意度：%d%%",
                    position, team.boardObjective, team.boardSatisfaction
                )
                MessageManager.send(gameState, "board_warning", { reason }, {
                    dedupeKey = "board_warning_" .. gameState.date.month,
                })

                -- 连续3次警告→解雇玩家
                if team.boardWarnings >= PLAYER_SACK_WARNINGS then
                    BoardManager._triggerPlayerSack(gameState)
                end
            else
                -- AI教练：满意度极低直接解雇
                if team.boardSatisfaction < AI_SACK_SATISFACTION then
                    BoardManager._triggerAISack(gameState, teamId)
                end
            end
        elseif team.boardSatisfaction >= 75 then
            -- 高满意度重置警告
            team.boardWarnings = 0
        end

        ::continue_team::
    end
end

--- 赛季结束评估（所有球队）
---@param gameState table
function BoardManager.seasonEndEvaluation(gameState)
    for teamId, team in pairs(gameState.teams) do
        if not team.boardObjective then goto continue_team end

        -- 找到该球队所在联赛
        local league = nil
        for _, lg in pairs(gameState.leagues or {}) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == teamId then
                    league = lg
                    break
                end
            end
            if league then break end
        end
        if not league then goto continue_team end

        local position = league:getTeamPosition(teamId)
        local threshold = TARGET_THRESHOLDS[team.boardObjective] or 10
        local isPlayerTeam = (teamId == gameState.playerTeamId)

        if position and position <= threshold then
            -- 目标达成
            team.boardSatisfaction = math.min(100, (team.boardSatisfaction or 50) + 20)
            team.boardWarnings = 0

            if isPlayerTeam then
                gameState:sendMessage({
                    category = "board",
                    title = "赛季总结 - 目标达成",
                    body = string.format("恭喜！球队以第%d名完赛，完成了董事会设定的\"%s\"目标。董事会对您的工作非常满意！",
                        position, team.boardObjective),
                    priority = "normal",
                })
            end
        else
            -- 目标未达成
            team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - 25)

            if isPlayerTeam then
                gameState:sendMessage({
                    category = "board",
                    title = "赛季总结 - 目标未达",
                    body = string.format("球队以第%d名完赛，未能完成\"%s\"的目标。董事会对此感到失望。",
                        position or 0, team.boardObjective),
                    priority = "high",
                })

                -- 严重失败直接解雇玩家
                if position and position > threshold + 5 then
                    BoardManager._triggerPlayerSack(gameState)
                end
            else
                -- AI教练：严重偏离目标 → 解雇
                if position and position > threshold + 4 then
                    BoardManager._triggerAISack(gameState, teamId)
                end
            end
        end

        ::continue_team::
    end
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

function BoardManager._getReputationTier(rep)
    for _, tier in ipairs({"elite", "strong", "mid", "weak", "lowest"}) do
        if rep >= OBJECTIVES[tier].min then
            return tier
        end
    end
    return "lowest"
end

--- 解雇玩家教练
function BoardManager._triggerPlayerSack(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    gameState:sendMessage({
        category = "board",
        title = "解雇通知",
        body = string.format(
            "由于球队成绩持续不佳（董事会满意度: %d%%），董事会决定解除您在 %s 的主教练职务。\n\n感谢您的付出，祝您前程似锦。",
            team.boardSatisfaction or 0, team.name or "球队"),
        priority = "high",
    })

    EventBus.emit("manager_sacked", {
        teamId = team.id,
        managerId = gameState.playerManagerId,
        isPlayer = true,
    })

    -- 直接调用 JobManager 处理玩家解雇后的状态（清除球队关联、进入失业状态）
    local JobManager = require("scripts/systems/job_manager")
    JobManager.handleSacked(gameState)
end

--- 解雇AI教练
function BoardManager._triggerAISack(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return end
    if team.managerVacant then return end  -- 已经空缺了

    -- 找到该队的AI经理
    local managerId = nil
    for id, mgr in pairs(gameState.managers or {}) do
        if mgr.teamId == teamId and not mgr.isPlayer then
            managerId = id
            break
        end
    end

    -- 标记球队空缺
    team.managerVacant = true
    team.vacantSince = {
        year = gameState.date.year,
        month = gameState.date.month,
        day = gameState.date.day,
    }
    team._vacantDays = 0
    team.boardWarnings = 0  -- 新教练来了重新算

    -- 更新经理状态
    if managerId and gameState.managers[managerId] then
        local mgr = gameState.managers[managerId]
        -- 记录履历
        if mgr.addCareerEntry then
            mgr:addCareerEntry(teamId, team.name or "未知", mgr._hiredSeason or gameState.season, gameState.season, {
                reason = "sacked",
            })
        end
        mgr.teamId = nil
        mgr.isUnemployed = true
        mgr._unemployedSince = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        }
    end

    -- 生成新闻
    local managerName = ""
    if managerId and gameState.managers[managerId] then
        managerName = gameState.managers[managerId].displayName or "主教练"
    else
        managerName = "主教练"
    end

    gameState:addNews({
        category = "transfers",
        title = "教练解雇",
        body = string.format("%s 因战绩不佳（满意度仅 %d%%）被 %s 解雇。",
            managerName, team.boardSatisfaction or 0, team.name or "球队"),
    })

    -- 如果玩家失业，提醒新空缺
    if gameState._isUnemployed then
        gameState:sendMessage({
            category = "job",
            title = "新职位空缺",
            body = string.format("%s 解雇了主教练，该职位现已空缺。你可以考虑申请。", team.name or "球队"),
            priority = "normal",
        })
    end

    EventBus.emit("ai_manager_sacked", {
        teamId = teamId,
        managerId = managerId,
    })
end

--- 获取当前满意度信息（供UI使用）
---@param gameState table
---@return table|nil {satisfaction, objective, warnings}
function BoardManager.getStatus(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return nil end
    return {
        satisfaction = team.boardSatisfaction or 50,
        objective = team.boardObjective or "未设定",
        warnings = team.boardWarnings or 0,
    }
end

return BoardManager
