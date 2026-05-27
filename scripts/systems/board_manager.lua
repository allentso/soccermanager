-- systems/board_manager.lua
-- 董事会系统：赛季目标、满意度评价、警告、解雇

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

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 生成赛季目标（赛季开始时调用）
---@param gameState table
function BoardManager.generateSeasonObjective(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local rep = team.reputation or 50
    local tier = BoardManager._getReputationTier(rep)
    local targets = OBJECTIVES[tier].targets

    -- 从该档位的目标中随机选一个
    local target = targets[math.random(1, #targets)]
    team.boardObjective = target
    team.boardSatisfaction = 50  -- 初始满意度50%
    team.boardWarnings = 0

    MessageManager.send(gameState, "board_objective", { target })
end

--- 每月评估满意度（月中 15 号调用）
---@param gameState table
function BoardManager.monthlyEvaluation(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end
    if not team.boardObjective then return end

    local league = gameState.league
    if not league then return end

    local position = league:getTeamPosition(team.id)
    if not position then return end

    local threshold = TARGET_THRESHOLDS[team.boardObjective] or 10
    local totalTeams = #league.standings

    -- 计算目标达成度 (-1.0 ~ +1.0)
    local progressRatio = 0
    if position <= threshold then
        -- 达到或超过目标
        progressRatio = (threshold - position) / math.max(threshold, 1)
        progressRatio = math.min(progressRatio, 1.0)
    else
        -- 未达目标
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

    -- 触发消息
    if team.boardSatisfaction < 25 then
        team.boardWarnings = (team.boardWarnings or 0) + 1
        local reason = string.format(
            "球队当前排名第%d，距离目标(%s)差距较大。满意度：%d%%",
            position, team.boardObjective, team.boardSatisfaction
        )
        MessageManager.send(gameState, "board_warning", { reason }, {
            dedupeKey = "board_warning_" .. gameState.date.month,
        })

        -- 连续3次警告→解雇
        if team.boardWarnings >= 3 then
            BoardManager._triggerSack(gameState)
        end
    elseif team.boardSatisfaction >= 75 then
        -- 高满意度重置警告
        team.boardWarnings = 0
    end
end

--- 赛季结束评估
---@param gameState table
function BoardManager.seasonEndEvaluation(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end
    if not team.boardObjective then return end

    local league = gameState.league
    if not league then return end

    local position = league:getTeamPosition(team.id)
    local threshold = TARGET_THRESHOLDS[team.boardObjective] or 10

    if position and position <= threshold then
        -- 目标达成
        team.boardSatisfaction = math.min(100, (team.boardSatisfaction or 50) + 20)
        team.boardWarnings = 0
        gameState:sendMessage({
            category = "board",
            title = "赛季总结 - 目标达成",
            body = string.format("恭喜！球队以第%d名完赛，完成了董事会设定的\"%s\"目标。董事会对您的工作非常满意！",
                position, team.boardObjective),
            priority = "normal",
        })
    else
        -- 目标未达成
        team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - 25)
        gameState:sendMessage({
            category = "board",
            title = "赛季总结 - 目标未达",
            body = string.format("球队以第%d名完赛，未能完成\"%s\"的目标。董事会对此感到失望。",
                position or 0, team.boardObjective),
            priority = "high",
        })

        -- 严重失败直接解雇
        if position and position > threshold + 5 then
            BoardManager._triggerSack(gameState)
        end
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

function BoardManager._triggerSack(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    gameState:sendMessage({
        category = "board",
        title = "解雇通知",
        body = string.format("由于球队成绩持续不佳，董事会决定解除您的主教练职务。感谢您的付出。"),
        priority = "high",
    })

    EventBus.emit("manager_sacked", {
        teamId = team.id,
        managerId = gameState.playerManagerId,
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
