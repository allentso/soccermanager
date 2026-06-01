-- systems/objectives_manager.lua
-- 赛季目标系统（长期赛季目标 + 短期月度目标）

local EventBus = require("scripts/app/event_bus")

local ObjectivesManager = {}

------------------------------------------------------
-- 目标模板
------------------------------------------------------

-- 赛季目标（根据球队实力自动生成）
local SEASON_OBJECTIVES = {
    -- 联赛相关
    { id = "league_champion", text = "赢得联赛冠军", category = "league",
      check = function(gs) return gs.worldHistory and #gs.worldHistory > 0 end,
      tier = "elite" },
    { id = "league_top4", text = "联赛前4名（欧冠资格）", category = "league",
      tier = "strong" },
    { id = "league_top_half", text = "联赛上半区完赛", category = "league",
      tier = "mid" },
    { id = "league_survive", text = "联赛保级成功", category = "league",
      tier = "weak" },

    -- 欧冠相关
    { id = "ucl_champion", text = "赢得欧冠冠军", category = "ucl",
      tier = "elite" },
    { id = "ucl_semifinal", text = "欧冠打入4强", category = "ucl",
      tier = "strong" },
    { id = "ucl_r16", text = "欧冠晋级16强", category = "ucl",
      tier = "mid" },

    -- 财务相关
    { id = "finance_profit", text = "赛季财务盈利", category = "finance",
      tier = "any" },
    { id = "finance_balance_50m", text = "赛季末余额超过50M", category = "finance",
      tier = "strong" },

    -- 青训相关
    { id = "youth_develop", text = "提升至少1名青年球员能力+5", category = "squad",
      tier = "any" },
}

-- 短期月度目标（动态生成）
local MONTHLY_TEMPLATES = {
    { id = "monthly_unbeaten_3", text = "连续3场不败", category = "form" },
    { id = "monthly_win_3", text = "本月赢得3场比赛", category = "form" },
    { id = "monthly_clean_sheet", text = "本月至少2场零封", category = "defense" },
    { id = "monthly_goals_8", text = "本月攻入8+球", category = "attack" },
    { id = "monthly_no_loss", text = "本月不败", category = "form" },
    { id = "monthly_top_scorer", text = "队内射手本月进3+球", category = "attack" },
}

------------------------------------------------------
-- 生成董事会目标提案（供玩家选择）
------------------------------------------------------

function ObjectivesManager._getTier(gameState)
    local team = gameState.teams[gameState.playerTeamId]
    if not team then return "mid" end
    local rep = team.reputation or 50
    if rep >= 85 then return "elite"
    elseif rep >= 70 then return "strong"
    elseif rep >= 50 then return "mid"
    else return "weak" end
end

function ObjectivesManager._isInUCL(gameState)
    if gameState.championsLeague and gameState.championsLeague.qualifiedTeams then
        for _, tid in ipairs(gameState.championsLeague.qualifiedTeams) do
            if tid == gameState.playerTeamId then return true end
        end
    end
    return false
end

--- 获取联赛目标候选列表（按 tier 推荐，也给相邻难度选项）
function ObjectivesManager.generateProposals(gameState)
    local tier = ObjectivesManager._getTier(gameState)
    local inUCL = ObjectivesManager._isInUCL(gameState)

    local tierOrder = { "elite", "strong", "mid", "weak" }
    local tierIdx = 1
    for i, t in ipairs(tierOrder) do
        if t == tier then tierIdx = i; break end
    end

    -- 联赛目标候选：当前tier + 上/下各一档
    local leagueOptions = {}
    for _, obj in ipairs(SEASON_OBJECTIVES) do
        if obj.category == "league" then
            local recommended = (obj.tier == tier)
            -- 相邻tier也加入
            local adjacent = false
            for i2, t2 in ipairs(tierOrder) do
                if t2 == obj.tier and math.abs(i2 - tierIdx) <= 1 then
                    adjacent = true; break
                end
            end
            if adjacent then
                table.insert(leagueOptions, {
                    id = obj.id, text = obj.text, category = "league",
                    tier = obj.tier, recommended = recommended,
                })
            end
        end
    end

    -- 欧冠目标候选
    local uclOptions = {}
    if inUCL then
        for _, obj in ipairs(SEASON_OBJECTIVES) do
            if obj.category == "ucl" then
                local recommended = (obj.tier == tier)
                local adjacent = false
                for i2, t2 in ipairs(tierOrder) do
                    if t2 == obj.tier and math.abs(i2 - tierIdx) <= 1 then
                        adjacent = true; break
                    end
                end
                if adjacent then
                    table.insert(uclOptions, {
                        id = obj.id, text = obj.text, category = "ucl",
                        tier = obj.tier, recommended = recommended,
                    })
                end
            end
        end
    end

    -- 财务目标候选
    local financeOptions = {}
    for _, obj in ipairs(SEASON_OBJECTIVES) do
        if obj.category == "finance" then
            table.insert(financeOptions, {
                id = obj.id, text = obj.text, category = "finance",
                tier = obj.tier or "any", recommended = (obj.id == "finance_profit"),
            })
        end
    end

    return {
        league = leagueOptions,
        ucl = uclOptions,
        finance = financeOptions,
        inUCL = inUCL,
    }
end

------------------------------------------------------
-- 确认目标选择
------------------------------------------------------

-- 目标档次→数值权重（用于计算预算调整）
local TIER_WEIGHT = { elite = 4, strong = 3, mid = 2, weak = 1 }

function ObjectivesManager.confirmObjectives(gameState, selectedIds)
    local seasonObjectives = {}
    for _, sid in ipairs(selectedIds) do
        for _, obj in ipairs(SEASON_OBJECTIVES) do
            if obj.id == sid then
                table.insert(seasonObjectives, {
                    id = obj.id,
                    text = obj.text,
                    category = obj.category,
                    tier = obj.tier,
                    status = "active",
                    progress = 0,
                })
                break
            end
        end
    end

    -- 至少有一个目标
    if #seasonObjectives == 0 then
        table.insert(seasonObjectives, {
            id = "finance_profit", text = "赛季财务盈利",
            category = "finance", tier = "any", status = "active", progress = 0,
        })
    end

    -- 计算预算调整：目标野心越低，董事会给的预算越少
    local team = gameState.teams[gameState.playerTeamId]
    local budgetChange = ObjectivesManager._calcBudgetAdjustment(gameState, team, seasonObjectives)

    local monthlyObjective = ObjectivesManager._generateMonthly(gameState)

    gameState.objectives = {
        season = seasonObjectives,
        monthly = monthlyObjective,
        completedCount = 0,
        totalCount = #seasonObjectives + 1,
    }

    -- 新闻通知
    local lines = { "本赛季目标已确定:" }
    for i, obj in ipairs(seasonObjectives) do
        table.insert(lines, string.format("  %d. %s", i, obj.text))
    end
    if monthlyObjective then
        table.insert(lines, string.format("\n本月目标: %s", monthlyObjective.text))
    end
    if budgetChange and budgetChange.message then
        table.insert(lines, "\n" .. budgetChange.message)
    end

    gameState:sendMessage({
        category = "board",
        title = "赛季目标确认",
        body = table.concat(lines, "\n"),
        priority = "normal",
    })
end

------------------------------------------------------
-- 预算调整逻辑
------------------------------------------------------
function ObjectivesManager._calcBudgetAdjustment(gameState, team, seasonObjectives)
    if not team then return nil end

    local teamTier = ObjectivesManager._getTier(gameState)
    local teamWeight = TIER_WEIGHT[teamTier] or 2

    -- 累计联赛+欧冠两项目标的档次偏移
    local totalDiff = 0
    for _, obj in ipairs(seasonObjectives) do
        if (obj.category == "league" or obj.category == "ucl") and TIER_WEIGHT[obj.tier] then
            totalDiff = totalDiff + (TIER_WEIGHT[obj.tier] - teamWeight)
        end
    end

    -- 根据累计偏移计算预算因子
    local factor = 1.0
    if totalDiff == 0 then
        factor = 1.0
    elseif totalDiff == -1 then
        factor = 0.85
    elseif totalDiff == -2 then
        factor = 0.70
    elseif totalDiff == -3 then
        factor = 0.55
    elseif totalDiff <= -4 then
        factor = 0.40
    elseif totalDiff == 1 then
        factor = 1.08
    elseif totalDiff == 2 then
        factor = 1.15
    elseif totalDiff >= 3 then
        factor = 1.20
    end

    -- 不需要调整
    if factor == 1.0 then return nil end

    -- 记录原始值
    local oldTransfer = team.transferBudget or 0
    local oldWage = team.wageBudget or 0

    -- 应用调整
    team.transferBudget = math.floor(oldTransfer * factor)
    team.wageBudget = math.floor(oldWage * factor)

    -- 生成说明文字
    local message
    if factor < 1.0 then
        local cutPct = math.floor((1.0 - factor) * 100)
        message = string.format(
            "董事会根据目标调整预算：转会预算 %.1fM → %.1fM，工资预算 %.0fK/周 → %.0fK/周（削减%d%%）",
            oldTransfer / 1000000, team.transferBudget / 1000000,
            oldWage / 1000, team.wageBudget / 1000,
            cutPct
        )
    else
        local boostPct = math.floor((factor - 1.0) * 100)
        message = string.format(
            "董事会对高目标追加投入：转会预算 %.1fM → %.1fM，工资预算 %.0fK/周 → %.0fK/周（增加%d%%）",
            oldTransfer / 1000000, team.transferBudget / 1000000,
            oldWage / 1000, team.wageBudget / 1000,
            boostPct
        )
    end

    return { factor = factor, message = message }
end

------------------------------------------------------
-- 初始化赛季目标（自动，作为兜底）
------------------------------------------------------

function ObjectivesManager.initSeason(gameState)
    local tier = ObjectivesManager._getTier(gameState)
    local inUCL = ObjectivesManager._isInUCL(gameState)

    local selectedIds = {}

    -- 联赛目标（当前 tier）
    for _, obj in ipairs(SEASON_OBJECTIVES) do
        if obj.category == "league" and obj.tier == tier then
            table.insert(selectedIds, obj.id); break
        end
    end

    -- 欧冠目标
    if inUCL then
        for _, obj in ipairs(SEASON_OBJECTIVES) do
            if obj.category == "ucl" and obj.tier == tier then
                table.insert(selectedIds, obj.id); break
            end
        end
    end

    -- 财务目标
    table.insert(selectedIds, "finance_profit")

    ObjectivesManager.confirmObjectives(gameState, selectedIds)
end

------------------------------------------------------
-- 生成月度目标
------------------------------------------------------

function ObjectivesManager._generateMonthly(gameState)
    -- 随机选一个月度模板
    local idx = RandomInt(1, #MONTHLY_TEMPLATES)
    local template = MONTHLY_TEMPLATES[idx]
    return {
        id = template.id,
        text = template.text,
        category = template.category,
        status = "active",
        progress = 0,
        target = 3,  -- 默认目标值
        startMonth = gameState.date.month,
    }
end

------------------------------------------------------
-- 每月检查（月末自动调用）
------------------------------------------------------

function ObjectivesManager.onMonthEnd(gameState)
    local objectives = gameState.objectives
    if not objectives then return end

    -- 评估月度目标
    local monthly = objectives.monthly
    if monthly and monthly.status == "active" then
        local completed = ObjectivesManager._checkMonthlyCompletion(gameState, monthly)
        if completed then
            monthly.status = "completed"
            objectives.completedCount = (objectives.completedCount or 0) + 1
            gameState:sendMessage({
                category = "board",
                title = "月度目标达成!",
                body = monthly.text,
                priority = "normal",
            })
        else
            monthly.status = "failed"
        end
    end

    -- 生成新月度目标
    objectives.monthly = ObjectivesManager._generateMonthly(gameState)
    objectives.totalCount = (objectives.totalCount or 0) + 1
end

function ObjectivesManager._checkMonthlyCompletion(gameState, monthly)
    -- 简化检查：基于 recentForm
    local team = gameState.teams[gameState.playerTeamId]
    if not team or not team.recentForm then return false end

    local form = team.recentForm
    if monthly.id == "monthly_unbeaten_3" then
        -- 最近3场不败
        local count = 0
        for i = math.max(1, #form - 2), #form do
            if form[i] == "W" or form[i] == "D" then count = count + 1 end
        end
        return count >= 3
    elseif monthly.id == "monthly_win_3" then
        local wins = 0
        for _, r in ipairs(form) do
            if r == "W" then wins = wins + 1 end
        end
        return wins >= 3
    elseif monthly.id == "monthly_no_loss" then
        for _, r in ipairs(form) do
            if r == "L" then return false end
        end
        return #form > 0
    end

    -- 其他目标默认随机概率（简化）
    return RandomInt(1, 100) <= 40
end

------------------------------------------------------
-- 赛季结束评估
------------------------------------------------------

function ObjectivesManager.onSeasonEnd(gameState)
    local objectives = gameState.objectives
    if not objectives then return end

    local team = gameState.teams[gameState.playerTeamId]
    if not team then return end

    -- 评估赛季目标
    for _, obj in ipairs(objectives.season) do
        if obj.status == "active" then
            local completed = ObjectivesManager._checkSeasonObjective(gameState, obj)
            if completed then
                obj.status = "completed"
                objectives.completedCount = (objectives.completedCount or 0) + 1
            else
                obj.status = "failed"
            end
        end
    end

    -- 计算总体完成率
    local total = objectives.totalCount or 1
    local completed = objectives.completedCount or 0
    local rate = math.floor(completed / total * 100)

    -- 董事会满意度调整
    if gameState.boardConfidence then
        if rate >= 80 then
            gameState.boardConfidence = math.min(100, gameState.boardConfidence + 15)
        elseif rate >= 50 then
            gameState.boardConfidence = math.min(100, gameState.boardConfidence + 5)
        elseif rate < 30 then
            gameState.boardConfidence = math.max(0, gameState.boardConfidence - 15)
        end
    end

    gameState:sendMessage({
        category = "board",
        title = "赛季目标总结",
        body = string.format("目标完成率: %d%%\n董事会满意度: %d%%",
            rate, gameState.boardConfidence or 50),
        priority = "high",
    })
end

function ObjectivesManager._checkSeasonObjective(gameState, obj)
    local team = gameState.teams[gameState.playerTeamId]
    if not team then return false end

    if obj.id == "league_champion" then
        -- 检查联赛冠军
        local lg = gameState.leagues and gameState.leagues[team.leagueId]
        if lg then
            local standings = lg:getSortedStandings()
            return #standings > 0 and standings[1].teamId == gameState.playerTeamId
        end
    elseif obj.id == "league_top4" then
        local lg = gameState.leagues and gameState.leagues[team.leagueId]
        if lg then
            local standings = lg:getSortedStandings()
            for i = 1, math.min(4, #standings) do
                if standings[i].teamId == gameState.playerTeamId then return true end
            end
        end
    elseif obj.id == "league_top_half" then
        local lg = gameState.leagues and gameState.leagues[team.leagueId]
        if lg then
            local standings = lg:getSortedStandings()
            local half = math.ceil(#standings / 2)
            for i = 1, half do
                if standings[i].teamId == gameState.playerTeamId then return true end
            end
        end
    elseif obj.id == "league_survive" then
        local lg = gameState.leagues and gameState.leagues[team.leagueId]
        if lg then
            local standings = lg:getSortedStandings()
            -- 最后3名降级
            local relegationZone = #standings - 2
            for i = 1, math.max(0, relegationZone - 1) do
                if standings[i].teamId == gameState.playerTeamId then return true end
            end
        end
    elseif obj.id == "ucl_champion" then
        local ucl = gameState.championsLeague
        return ucl and ucl.champion == gameState.playerTeamId
    elseif obj.id == "ucl_semifinal" then
        local ucl = gameState.championsLeague
        if ucl and ucl.knockout and ucl.knockout.sf then
            for _, f in ipairs(ucl.knockout.sf) do
                if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
                    return true
                end
            end
        end
    elseif obj.id == "ucl_r16" then
        local ucl = gameState.championsLeague
        if ucl and ucl.knockout and ucl.knockout.r16 then
            for _, f in ipairs(ucl.knockout.r16) do
                if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
                    return true
                end
            end
        end
    elseif obj.id == "finance_profit" then
        return (team.balance or 0) > (team.initialBalance or 0)
    end

    return false
end

------------------------------------------------------
-- 获取当前目标摘要（用于Dashboard）
------------------------------------------------------

function ObjectivesManager.getSummary(gameState)
    local objectives = gameState.objectives
    if not objectives then
        return {
            hasObjectives = false,
            seasonText = "目标: 未设定",
            monthlyText = nil,
            completedCount = 0,
            totalCount = 0,
            progressPct = 0,
        }
    end

    -- 找到主要赛季目标
    local mainSeason = objectives.season and objectives.season[1]
    local seasonText = mainSeason and mainSeason.text or "未设定"
    local seasonStatus = mainSeason and mainSeason.status or "active"

    -- 月度目标
    local monthly = objectives.monthly
    local monthlyText = monthly and monthly.text or nil
    local monthlyStatus = monthly and monthly.status or "active"

    local completed = objectives.completedCount or 0
    local total = objectives.totalCount or 1
    local pct = math.floor(completed / total * 100)

    return {
        hasObjectives = true,
        seasonText = seasonText,
        seasonStatus = seasonStatus,
        monthlyText = monthlyText,
        monthlyStatus = monthlyStatus,
        completedCount = completed,
        totalCount = total,
        progressPct = pct,
        allSeasonObjectives = objectives.season,
    }
end

return ObjectivesManager
