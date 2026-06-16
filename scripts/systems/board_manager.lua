-- systems/board_manager.lua
-- 董事会系统：赛季目标、满意度评价、警告、解雇（玩家 + AI教练）

local EventBus = require("scripts/app/event_bus")
local MessageManager = require("scripts/systems/message_manager")
local RealDataLoader = require("scripts/data/real_data_loader")

local BoardManager = {}

------------------------------------------------------
-- 声望范围常量（与 reputation_manager 一致）
------------------------------------------------------
local TEAM_REP_MIN = 500
local TEAM_REP_MAX = 950
local MGR_REP_MIN = 1
local MGR_REP_MAX = 99

------------------------------------------------------
-- 目标类型定义
------------------------------------------------------
local OBJECTIVES = {
    -- 按声望分档（球队声望范围 500-950）
    elite   = { min = 900, targets = {"夺冠", "前2名", "前3名"} },
    strong  = { min = 800, targets = {"前3名", "前4名", "上半区"} },
    mid     = { min = 700, targets = {"上半区", "前10名", "避免降级"} },
    weak    = { min = 620, targets = {"保级", "避免垫底", "前15名"} },
    lowest  = { min = 0,   targets = {"保级", "避免垫底"} },
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
local AI_SACK_SATISFACTION = 25       -- 满意度低于此值触发解雇
local AI_PROB_SACK_THRESHOLD = 35    -- 满意度低于此值有概率解雇
local AI_WARNING_THRESHOLD = 30       -- 满意度低于此值触发警告
local PLAYER_SACK_WARNINGS = 3       -- 玩家累计警告次数触发解雇

local TIER_RANK = { lowest = 1, weak = 2, mid = 3, strong = 4, elite = 5 }
local RANK_TIER = { "lowest", "weak", "mid", "strong", "elite" }

-- ObjectivesManager 赛季目标 → 董事会评估文案
local LEAGUE_OBJ_TO_BOARD = {
    league_champion = "夺冠",
    league_top4 = "前4名",
    league_top_half = "上半区",
    league_survive = "保级",
}

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 生成赛季目标（赛季开始时为所有球队调用）
---@param gameState table
function BoardManager.generateSeasonObjectives(gameState)
    for teamId, team in pairs(gameState.teams) do
        team.boardSatisfaction = team.boardSatisfaction or 50
        team.boardWarnings = team.boardWarnings or 0

        if teamId == gameState.playerTeamId then
            goto continue_team
        end

        local tier = BoardManager.computeEffectiveTier(gameState, teamId)
        local targets = OBJECTIVES[tier].targets
        team.boardObjective = targets[RandomInt(1, #targets)]

        ::continue_team::
    end

    BoardManager.syncFromObjectives(gameState)

    -- 给玩家发消息（若 objectives 系统已发赛季目标确认，则跳过避免重复）
    local playerTeam = gameState:getPlayerTeam()
    local objectives = gameState.objectives
    local hasObjectiveInbox = objectives and objectives.season and #objectives.season > 0
    if playerTeam and playerTeam.boardObjective and not hasObjectiveInbox then
        MessageManager.send(gameState, "board_objective", { playerTeam.boardObjective }, {
            dedupeKey = "board_objective_" .. tostring(gameState.season or 0),
            permanent = true,
        })
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

        -- 赛季初保护：前3个月董事会更宽容（赛季刚开始排名不稳定）
        local matchesPlayed = 0
        local standings = league.standings or {}
        for _, entry in ipairs(standings) do
            if entry.teamId == teamId then
                matchesPlayed = entry.played or 0
                break
            end
        end
        local earlySeasonFactor = 1.0
        if matchesPlayed < 10 then
            earlySeasonFactor = 0.5  -- 前10场比赛评估力度减半
        end

        -- 计算目标达成度 (-1.0 ~ +1.0)
        local progressRatio = 0
        if position <= threshold then
            progressRatio = (threshold - position) / math.max(threshold, 1)
            progressRatio = math.min(progressRatio, 1.0)
        else
            progressRatio = -(position - threshold) / math.max(totalTeams - threshold, 1)
            progressRatio = math.max(progressRatio, -1.0)
        end

        -- 满意度变化（赛季初力度减弱）
        local delta = math.floor(progressRatio * 15 * earlySeasonFactor)

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

                -- 连续警告→解雇玩家（需要更多次数，给教练更多时间调整）
                if team.boardWarnings >= PLAYER_SACK_WARNINGS then
                    -- 额外保护1：如果经理声望高于球队声望（归一化比较），给予额外容忍
                    local manager = gameState:getPlayerManager()
                    local managerRep = manager and manager.reputation or 30
                    local teamRepForCalc = RealDataLoader.getReputationForCalculation(gameState, teamId, team)
                    local teamRepNorm = MGR_REP_MIN + (teamRepForCalc - TEAM_REP_MIN) / (TEAM_REP_MAX - TEAM_REP_MIN) * (MGR_REP_MAX - MGR_REP_MIN)
                    local extraTolerance = 0
                    if managerRep > teamRepNorm then
                        extraTolerance = extraTolerance + 1
                    end
                    -- 额外保护2：如果当前联赛排名在前3，再给1次容忍
                    if position and position <= 3 then
                        extraTolerance = extraTolerance + 1
                    end
                    if team.boardWarnings >= PLAYER_SACK_WARNINGS + extraTolerance then
                        BoardManager._triggerPlayerSack(gameState)
                    end
                end
            else
                -- AI教练：满意度极低直接解雇，中等偏低有概率解雇
                if team.boardSatisfaction < AI_SACK_SATISFACTION then
                    BoardManager._triggerAISack(gameState, teamId)
                elseif team.boardSatisfaction < AI_PROB_SACK_THRESHOLD and (team.boardWarnings or 0) >= 2 then
                    -- 满意度25-35之间且累计2次警告：30%概率解雇
                    if Random() < 0.30 then
                        BoardManager._triggerAISack(gameState, teamId)
                    end
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
    -- 作弊模式跳过董事会评估（防止测试时被辞退）
    if gameState._cheatAutoPlay then return end

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
            -- 目标未达成：根据偏离程度分级处罚
            local gap = position - threshold
            local penalty = 25
            if gap <= 2 then
                penalty = 10  -- 略微未达标，轻微惩罚
            elseif gap <= 4 then
                penalty = 18  -- 有差距但不严重
            end
            team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - penalty)

            if isPlayerTeam then
                -- 国内成就保护：如果联赛排名在前3，即使未达到更高目标也不会被直接解雇
                local hasDomesticSuccess = (position ~= nil and position <= 3)

                gameState:sendMessage({
                    category = "board",
                    title = "赛季总结 - 目标未达",
                    body = string.format("球队以第%d名完赛，未能完成\"%s\"的目标。%s",
                        position or 0, team.boardObjective,
                        hasDomesticSuccess
                            and "不过董事会认可球队的联赛表现，决定给予更多时间。"
                            or "董事会对此感到失望。"),
                    priority = "high",
                })

                -- 严重失败直接解雇玩家（但有国内成就保护）
                if not hasDomesticSuccess and position and position > threshold + 5 then
                    BoardManager._triggerPlayerSack(gameState)
                end
            else
                -- AI教练：偏离目标 → 解雇（AI不享受保护，但阈值也放宽一点）
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

function BoardManager._findTeamLeague(gameState, teamId)
    for _, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds or {}) do
            if tid == teamId then
                return lg
            end
        end
    end
    return nil
end

function BoardManager._getLeagueRepRank(gameState, teamId)
    local league = BoardManager._findTeamLeague(gameState, teamId)
    if not league then return nil, nil end

    local ranked = {}
    for _, tid in ipairs(league.teamIds or {}) do
        local t = gameState.teams[tid]
        if t then
            table.insert(ranked, { teamId = tid, rep = t.reputation or 600 })
        end
    end
    table.sort(ranked, function(a, b) return a.rep > b.rep end)

    for i, entry in ipairs(ranked) do
        if entry.teamId == teamId then
            return i, #ranked
        end
    end
    return nil, #ranked
end

function BoardManager._leagueRankToTier(rank, total)
    if not rank or not total or total <= 0 then return "mid" end
    local pct = rank / total
    if pct <= 0.15 then return "elite"
    elseif pct <= 0.30 then return "strong"
    elseif pct <= 0.55 then return "mid"
    elseif pct <= 0.80 then return "weak"
    else return "lowest"
    end
end

--- 综合声望与联赛内相对实力，取更保守的分档（避免中游队被分配争冠目标）
---@param gameState table
---@param teamId number
---@return string tier
function BoardManager.computeEffectiveTier(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return "mid" end

    local calcRep = RealDataLoader.getReputationForCalculation(gameState, teamId, team)
    local repTier = BoardManager._getReputationTier(calcRep)
    local rank, total = BoardManager._getLeagueRepRank(gameState, teamId)
    local leagueTier = BoardManager._leagueRankToTier(rank, total)

    local effRank = math.min(TIER_RANK[repTier] or 3, TIER_RANK[leagueTier] or 3)
    if team._promotedThisSeason then
        effRank = math.min(effRank, TIER_RANK.weak)
    end
    return RANK_TIER[effRank] or "mid"
end

--- 将玩家 season objectives 同步到 team.boardObjective（评估系统使用）
---@param gameState table
function BoardManager.syncFromObjectives(gameState)
    local team = gameState:getPlayerTeam()
    if not team or not gameState.objectives then return end

    for _, obj in ipairs(gameState.objectives.season or {}) do
        if obj.category == "league" and LEAGUE_OBJ_TO_BOARD[obj.id] then
            team.boardObjective = LEAGUE_OBJ_TO_BOARD[obj.id]
            return
        end
    end
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
