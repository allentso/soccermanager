-- systems/objectives_manager.lua
-- 赛季目标系统（长期赛季目标 + 短期月度目标）

local EventBus = require("scripts/app/event_bus")
local BoardManager = require("scripts/systems/board_manager")
local TransferManager = require("scripts/systems/transfer_manager")

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

-- 短期月度目标（按 effective tier 分档，生成时写入阈值字段）
local TIER_RANK = { lowest = 0, weak = 1, mid = 2, strong = 3, elite = 4 }
local RANK_TIER = { [0] = "lowest", [1] = "weak", [2] = "mid", [3] = "strong", [4] = "elite" }

local MONTHLY_TEMPLATES = {
    -- weak / lowest（lowest 生成时归并到 weak 池）
    { id = "monthly_wins", text = "本月赢得1场比赛", tier = "weak", minWins = 1, category = "form" },
    { id = "monthly_unbeaten_streak", text = "连续2场不败", tier = "weak", streak = 2, category = "form" },
    { id = "monthly_goals", text = "本月攻入3+球", tier = "weak", minGoals = 3, category = "attack" },
    { id = "monthly_clean_sheets", text = "本月至少1场零封", tier = "weak", minCleanSheets = 1, category = "defense" },
    { id = "monthly_top_scorer", text = "队内射手本月进1+球", tier = "weak", minScorerGoals = 1, category = "attack" },
    -- mid
    { id = "monthly_wins", text = "本月赢得2场比赛", tier = "mid", minWins = 2, category = "form" },
    { id = "monthly_unbeaten_streak", text = "连续3场不败", tier = "mid", streak = 3, category = "form" },
    { id = "monthly_goals", text = "本月攻入5+球", tier = "mid", minGoals = 5, category = "attack" },
    { id = "monthly_clean_sheets", text = "本月至少1场零封", tier = "mid", minCleanSheets = 1, category = "defense" },
    { id = "monthly_top_scorer", text = "队内射手本月进2+球", tier = "mid", minScorerGoals = 2, category = "attack" },
    -- strong
    { id = "monthly_wins", text = "本月赢得3场比赛", tier = "strong", minWins = 3, category = "form" },
    { id = "monthly_unbeaten_streak", text = "连续3场不败", tier = "strong", streak = 3, category = "form" },
    { id = "monthly_goals", text = "本月攻入7+球", tier = "strong", minGoals = 7, category = "attack" },
    { id = "monthly_clean_sheets", text = "本月至少2场零封", tier = "strong", minCleanSheets = 2, category = "defense" },
    { id = "monthly_top_scorer", text = "队内射手本月进3+球", tier = "strong", minScorerGoals = 3, category = "attack" },
    -- elite
    { id = "monthly_wins", text = "本月赢得4场比赛", tier = "elite", minWins = 4, category = "form" },
    { id = "monthly_no_loss", text = "本月不败", tier = "elite", category = "form" },
    { id = "monthly_goals", text = "本月攻入10+球", tier = "elite", minGoals = 10, category = "attack" },
    { id = "monthly_clean_sheets", text = "本月至少2场零封", tier = "elite", minCleanSheets = 2, category = "defense" },
    { id = "monthly_top_scorer", text = "队内射手本月进4+球", tier = "elite", minScorerGoals = 4, category = "attack" },
}

------------------------------------------------------
-- 生成董事会目标提案（供玩家选择）
------------------------------------------------------

function ObjectivesManager._getTier(gameState)
    local teamId = gameState.playerTeamId
    if not teamId then return "mid" end
    return BoardManager.computeEffectiveTier(gameState, teamId)
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
    local tierRank = { lowest = 0, weak = 1, mid = 2, strong = 3, elite = 4 }
    local effRank = tierRank[tier] or 2

    local function tierAllowed(objTier)
        local objRank = tierRank[objTier]
        if not objRank then return false end
        return objRank >= effRank - 1 and objRank <= effRank + 1
    end

    -- 联赛目标候选：有效 tier ±1 档
    local leagueOptions = {}
    for _, obj in ipairs(SEASON_OBJECTIVES) do
        if obj.category == "league" and tierAllowed(obj.tier) then
            table.insert(leagueOptions, {
                id = obj.id, text = obj.text, category = "league",
                tier = obj.tier, recommended = (obj.tier == tier),
            })
        end
    end

    -- 欧冠目标候选
    local uclOptions = {}
    if inUCL then
        for _, obj in ipairs(SEASON_OBJECTIVES) do
            if obj.category == "ucl" and tierAllowed(obj.tier) then
                table.insert(uclOptions, {
                    id = obj.id, text = obj.text, category = "ucl",
                    tier = obj.tier, recommended = (obj.tier == tier),
                })
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

    local monthlies = ObjectivesManager._generateMonthlies(gameState)

    gameState.objectives = {
        season = seasonObjectives,
        monthlies = monthlies,
        completedCount = 0,
        totalCount = #seasonObjectives + #monthlies,
    }

    -- 新闻通知
    local lines = { "本赛季目标已确定:" }
    for i, obj in ipairs(seasonObjectives) do
        table.insert(lines, string.format("  %d. %s", i, obj.text))
    end
    if #monthlies > 0 then
        table.insert(lines, "\n本月目标:")
        for i, obj in ipairs(monthlies) do
            table.insert(lines, string.format("  %d. %s", i, obj.text))
        end
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

    BoardManager.syncFromObjectives(gameState)
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
-- 月度目标（德比按当月赛程生成，无德比则随机通用目标）
------------------------------------------------------

--- 旧存档 single monthly → monthlies 数组
function ObjectivesManager._getMonthlies(objectives)
    if not objectives then return {} end
    if objectives.monthlies then return objectives.monthlies end
    if objectives.monthly then
        objectives.monthlies = { objectives.monthly }
        objectives.monthly = nil
    end
    return objectives.monthlies or {}
end

function ObjectivesManager._normalizeMonthlyTier(tier)
    if tier == "lowest" then return "weak" end
    return tier or "mid"
end

function ObjectivesManager._collectTemplatesForRank(rank)
    local out = {}
    for _, tmpl in ipairs(MONTHLY_TEMPLATES) do
        if TIER_RANK[tmpl.tier] == rank then
            table.insert(out, tmpl)
        end
    end
    return out
end

--- 按 effective tier 抽取通用月度模板（先精确匹配，再 ±1 档扩展）
function ObjectivesManager._pickMonthlyTemplate(gameState)
    local tier = ObjectivesManager._normalizeMonthlyTier(ObjectivesManager._getTier(gameState))
    local rank = TIER_RANK[tier] or 2

    local pool = ObjectivesManager._collectTemplatesForRank(rank)
    if #pool == 0 then
        for delta = 1, 4 do
            local lower = rank - delta
            if lower >= 0 then
                pool = ObjectivesManager._collectTemplatesForRank(lower)
                if #pool > 0 then break end
            end
            local upper = rank + delta
            if upper <= 4 then
                pool = ObjectivesManager._collectTemplatesForRank(upper)
                if #pool > 0 then break end
            end
        end
    end
    if #pool == 0 then
        pool = MONTHLY_TEMPLATES
    end

    return pool[RandomInt(1, #pool)]
end

function ObjectivesManager._instantiateMonthlyTemplate(gameState, template)
    local obj = {
        id = template.id,
        text = template.text,
        category = template.category,
        tier = template.tier,
        status = "active",
        progress = 0,
        startMonth = gameState.date.month,
        startYear = gameState.date.year,
    }
    if template.minWins then obj.minWins = template.minWins end
    if template.streak then obj.streak = template.streak end
    if template.minGoals then obj.minGoals = template.minGoals end
    if template.minCleanSheets then obj.minCleanSheets = template.minCleanSheets end
    if template.minScorerGoals then obj.minScorerGoals = template.minScorerGoals end
    return obj
end

function ObjectivesManager._generateGenericMonthly(gameState)
    local template = ObjectivesManager._pickMonthlyTemplate(gameState)
    return ObjectivesManager._instantiateMonthlyTemplate(gameState, template)
end

function ObjectivesManager._derbyRequiresWin(gameState)
    local tier = ObjectivesManager._normalizeMonthlyTier(ObjectivesManager._getTier(gameState))
    return tier == "strong" or tier == "elite"
end

function ObjectivesManager._collectFixturesInMonth(gameState, teamId, year, month)
    local lg = gameState:getTeamLeague(teamId)
    if not lg then return {} end

    local fixtures = {}
    for _, f in ipairs(lg.fixtures or {}) do
        local d = f.date
        if d and tonumber(d.year) == tonumber(year) and tonumber(d.month) == tonumber(month) then
            if f.homeTeamId == teamId or f.awayTeamId == teamId then
                table.insert(fixtures, f)
            end
        end
    end

    table.sort(fixtures, function(a, b)
        local da, db = a.date or {}, b.date or {}
        if da.day ~= db.day then return (da.day or 0) < (db.day or 0) end
        return (a.id or 0) < (b.id or 0)
    end)
    return fixtures
end

function ObjectivesManager._collectDerbyFixturesInMonth(gameState, teamId, year, month)
    local derbies = {}
    for _, f in ipairs(ObjectivesManager._collectFixturesInMonth(gameState, teamId, year, month)) do
        local opponentId = f.homeTeamId == teamId and f.awayTeamId or f.homeTeamId
        if opponentId and TransferManager.isRivalry(gameState, teamId, opponentId) then
            table.insert(derbies, f)
        end
    end
    return derbies
end

function ObjectivesManager._makeDerbyMonthly(gameState, fixture, teamId, year, month)
    local opponentId = fixture.homeTeamId == teamId and fixture.awayTeamId or fixture.homeTeamId
    local opp = opponentId and gameState.teams[opponentId]
    local oppName = (opp and ((opp.shortName and opp.shortName ~= "") and opp.shortName or opp.name)) or "对手"
    local needWin = ObjectivesManager._derbyRequiresWin(gameState)
    if needWin then
        return {
            id = "monthly_derby_win",
            text = string.format("赢下对阵%s的德比", oppName),
            category = "derby",
            tier = ObjectivesManager._normalizeMonthlyTier(ObjectivesManager._getTier(gameState)),
            status = "active",
            progress = 0,
            startMonth = month,
            startYear = year,
            fixtureId = fixture.id,
            opponentTeamId = opponentId,
        }
    end
    return {
        id = "monthly_derby_points",
        text = string.format("对阵%s至少拿1分", oppName),
        category = "derby",
        tier = ObjectivesManager._normalizeMonthlyTier(ObjectivesManager._getTier(gameState)),
        status = "active",
        progress = 0,
        startMonth = month,
        startYear = year,
        fixtureId = fixture.id,
        opponentTeamId = opponentId,
    }
end

function ObjectivesManager._generateMonthlies(gameState)
    local year = gameState.date.year
    local month = gameState.date.month
    local teamId = gameState.playerTeamId
    if not teamId then
        return { ObjectivesManager._generateGenericMonthly(gameState) }
    end

    local monthlies = {}
    for _, f in ipairs(ObjectivesManager._collectDerbyFixturesInMonth(gameState, teamId, year, month)) do
        table.insert(monthlies, ObjectivesManager._makeDerbyMonthly(gameState, f, teamId, year, month))
    end

    if #monthlies == 0 then
        if #ObjectivesManager._collectFixturesInMonth(gameState, teamId, year, month) > 0 then
            table.insert(monthlies, ObjectivesManager._generateGenericMonthly(gameState))
        end
    end
    return monthlies
end

--- 兼容旧调用
function ObjectivesManager._generateMonthly(gameState)
    return ObjectivesManager._generateGenericMonthly(gameState)
end

------------------------------------------------------
-- 月度比赛统计（供月末评估）
------------------------------------------------------

local function emptyMonthlyStats(year, month)
    return {
        year = year,
        month = month,
        wins = 0,
        draws = 0,
        losses = 0,
        goalsFor = 0,
        goalsAgainst = 0,
        cleanSheets = 0,
        results = {},
        playerGoals = {},
    }
end

function ObjectivesManager._ensureMonthlyStats(team, year, month)
    if not team.monthlyStats then
        team.monthlyStats = emptyMonthlyStats(year, month)
        return team.monthlyStats
    end
    if team.monthlyStats.year ~= year or team.monthlyStats.month ~= month then
        team._lastMonthlyStats = team.monthlyStats
        team.monthlyStats = emptyMonthlyStats(year, month)
    end
    return team.monthlyStats
end

--- 比赛结束后累计当月统计（联赛/杯赛均计入）
---@param gameState table
---@param teamId number
---@param goalsFor number
---@param goalsAgainst number
---@param events? table
function ObjectivesManager.recordMatchResult(gameState, teamId, goalsFor, goalsAgainst, events)
    local team = gameState.teams[teamId]
    if not team then return end

    local d = gameState.date
    local ms = ObjectivesManager._ensureMonthlyStats(team, d.year, d.month)

    goalsFor = goalsFor or 0
    goalsAgainst = goalsAgainst or 0

    local result
    if goalsFor > goalsAgainst then
        ms.wins = ms.wins + 1
        result = "W"
    elseif goalsFor < goalsAgainst then
        ms.losses = ms.losses + 1
        result = "L"
    else
        ms.draws = ms.draws + 1
        result = "D"
    end

    ms.goalsFor = ms.goalsFor + goalsFor
    ms.goalsAgainst = ms.goalsAgainst + goalsAgainst
    if goalsAgainst == 0 then
        ms.cleanSheets = ms.cleanSheets + 1
    end
    table.insert(ms.results, result)

    for _, evt in ipairs(events or {}) do
        if evt.type == "goal" and not evt.isOwnGoal then
            local p = gameState.players[evt.playerId]
            if p and p.teamId == teamId then
                ms.playerGoals[evt.playerId] = (ms.playerGoals[evt.playerId] or 0) + 1
            end
        end
    end

    if teamId == gameState.playerTeamId then
        ObjectivesManager.refreshActiveMonthlies(gameState)
    end
end

function ObjectivesManager._getMonthlyStatsForEval(team, monthly, gameState)
    local function monthMatches(ms)
        if not ms then return false end
        if monthly.startMonth and tonumber(ms.month) ~= tonumber(monthly.startMonth) then
            return false
        end
        if monthly.startYear and tonumber(ms.year) ~= tonumber(monthly.startYear) then
            return false
        end
        return true
    end

    if monthMatches(team._lastMonthlyStats) then return team._lastMonthlyStats end
    if monthMatches(team.monthlyStats) then return team.monthlyStats end

    -- 当月 active 目标：优先用当前 live 统计（兼容缺 startMonth 的旧存档）
    if monthly.status == "active" and team.monthlyStats and gameState and gameState.date then
        local ms = team.monthlyStats
        if tonumber(ms.year) == tonumber(gameState.date.year)
            and tonumber(ms.month) == tonumber(gameState.date.month) then
            return ms
        end
    end

    return emptyMonthlyStats(monthly.startYear or 0, monthly.startMonth or 0)
end

local function hasConsecutiveUnbeaten(results, needed)
    local streak = 0
    for _, r in ipairs(results or {}) do
        if r == "W" or r == "D" then
            streak = streak + 1
            if streak >= needed then return true end
        else
            streak = 0
        end
    end
    return false
end

local function maxPlayerGoals(playerGoals)
    local best = 0
    for _, count in pairs(playerGoals or {}) do
        if count > best then best = count end
    end
    return best
end

------------------------------------------------------
-- 月度进度（Dashboard 实时展示 + 赛后即时结算）
------------------------------------------------------

function ObjectivesManager.getMonthlyProgress(gameState, monthly, team)
    if not monthly then
        return { current = 0, target = 1, pct = 0, met = false, label = "—" }
    end
    if monthly.status == "completed" then
        return { current = 1, target = 1, pct = 100, met = true, label = "已完成" }
    end
    if monthly.status == "failed" then
        return { current = 0, target = 1, pct = 0, met = false, label = "未达成" }
    end
    if monthly.status == "skipped" then
        return { current = 0, target = 1, pct = 0, met = false, label = "无比赛，已跳过" }
    end

    if monthly.id == "monthly_derby_win" or monthly.id == "monthly_derby_points" then
        local fixture = ObjectivesManager._findFixtureById(gameState, gameState.playerTeamId, monthly.fixtureId)
        if not fixture or fixture.status ~= "finished" then
            return { current = 0, target = 1, pct = 0, met = false, label = "0/1 场" }
        end
        local met = ObjectivesManager._checkDerbyMonthlyCompletion(gameState, monthly)
        return {
            current = met and 1 or 0,
            target = 1,
            pct = met and 100 or 0,
            met = met,
            label = met and "已达成" or "未达成",
        }
    end

    local stats = team and ObjectivesManager._getMonthlyStatsForEval(team, monthly, gameState) or nil
    if not stats then
        return { current = 0, target = 1, pct = 0, met = false, label = "0/1" }
    end

    if monthly.minWins then
        local current = stats.wins or 0
        local target = monthly.minWins
        return {
            current = current, target = target,
            pct = math.min(100, math.floor(current / math.max(target, 1) * 100)),
            met = current >= target,
            label = string.format("%d/%d 胜", current, target),
        }
    end
    if monthly.streak then
        local streak = 0
        for _, r in ipairs(stats.results or {}) do
            if r == "W" or r == "D" then streak = streak + 1 else streak = 0 end
        end
        local target = monthly.streak
        return {
            current = streak, target = target,
            pct = math.min(100, math.floor(streak / math.max(target, 1) * 100)),
            met = hasConsecutiveUnbeaten(stats.results, target),
            label = string.format("%d/%d 场不败", streak, target),
        }
    end
    if monthly.minGoals then
        local current = stats.goalsFor or 0
        local target = monthly.minGoals
        return {
            current = current, target = target,
            pct = math.min(100, math.floor(current / math.max(target, 1) * 100)),
            met = current >= target,
            label = string.format("%d/%d 球", current, target),
        }
    end
    if monthly.minCleanSheets then
        local current = stats.cleanSheets or 0
        local target = monthly.minCleanSheets
        return {
            current = current, target = target,
            pct = math.min(100, math.floor(current / math.max(target, 1) * 100)),
            met = current >= target,
            label = string.format("%d/%d 零封", current, target),
        }
    end
    if monthly.minScorerGoals then
        local current = maxPlayerGoals(stats.playerGoals)
        local target = monthly.minScorerGoals
        return {
            current = current, target = target,
            pct = math.min(100, math.floor(current / math.max(target, 1) * 100)),
            met = current >= target,
            label = string.format("%d/%d 球", current, target),
        }
    end
    if monthly.id == "monthly_no_loss" then
        local played = (stats.wins or 0) + (stats.draws or 0) + (stats.losses or 0)
        local losses = stats.losses or 0
        local met = played > 0 and losses == 0
        return {
            current = played, target = played > 0 and played or 1,
            pct = met and 100 or (played > 0 and math.floor((played - losses) / played * 100) or 0),
            met = met,
            label = met and "不败" or string.format("%d 负", losses),
        }
    end

    local met = ObjectivesManager._checkMonthlyCompletion(monthly, stats)
    return { current = met and 1 or 0, target = 1, pct = met and 100 or 0, met = met, label = met and "已达成" or "进行中" }
end

function ObjectivesManager._markMonthlyCompleted(gameState, objectives, team, monthly)
    if monthly.status == "completed" then return end
    monthly.status = "completed"
    objectives.completedCount = (objectives.completedCount or 0) + 1
    if team then
        team.boardSatisfaction = math.min(100, (team.boardSatisfaction or 50) + 5)
    end
    gameState:sendMessage({
        category = "board",
        title = "月度目标达成!",
        body = monthly.text .. "\n董事会满意度 +5",
        priority = "normal",
    })
end

function ObjectivesManager._markMonthlyFailed(gameState, objectives, team, monthly)
    if monthly.status == "failed" or monthly.status == "completed" then return end
    monthly.status = "failed"
    if team then
        team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - 3)
    end
    gameState:sendMessage({
        category = "board",
        title = "月度目标未达成",
        body = monthly.text .. "\n董事会满意度 -3",
        priority = "normal",
    })
end

local function monthBefore(y1, m1, y2, m2)
    y1, m1, y2, m2 = tonumber(y1) or 0, tonumber(m1) or 0, tonumber(y2) or 0, tonumber(m2) or 0
    if y1 ~= y2 then return y1 < y2 end
    return m1 < m2
end

--- 月度目标所属月份是否已结束（避免当月 1 号刚生成就被评估）
function ObjectivesManager._monthlyPeriodEnded(monthly, date)
    if not monthly.startMonth or not monthly.startYear or not date then return true end
    return monthBefore(monthly.startYear, monthly.startMonth, date.year, date.month)
end

--- 当月实际参与的比赛场次（德比看 fixture 是否完赛，通用目标看统计）
function ObjectivesManager._monthlyMatchesPlayed(gameState, team, monthly)
    if monthly.id == "monthly_derby_points" or monthly.id == "monthly_derby_win" then
        local fixture = ObjectivesManager._findFixtureById(gameState, gameState.playerTeamId, monthly.fixtureId)
        if not fixture or fixture.status ~= "finished" then return 0 end
        return 1
    end
    local stats = team and ObjectivesManager._getMonthlyStatsForEval(team, monthly, gameState) or nil
    if not stats then return 0 end
    return (stats.wins or 0) + (stats.draws or 0) + (stats.losses or 0)
end

function ObjectivesManager._markMonthlySkipped(gameState, objectives, team, monthly)
    if monthly.status == "failed" or monthly.status == "completed" or monthly.status == "skipped" then return end
    monthly.status = "skipped"
end

--- 比赛后刷新当月 active 月度目标（德比/胜场等达标即结算）
function ObjectivesManager.refreshActiveMonthlies(gameState)
    local objectives = gameState.objectives
    if not objectives then return end
    local teamId = gameState.playerTeamId
    if not teamId then return end
    local team = gameState.teams[teamId]
    if not team then return end

    for _, monthly in ipairs(ObjectivesManager._getMonthlies(objectives)) do
        if monthly.status == "active" then
            if not monthly.startMonth and gameState.date then
                monthly.startMonth = gameState.date.month
                monthly.startYear = gameState.date.year
            end
            local prog = ObjectivesManager.getMonthlyProgress(gameState, monthly, team)
            monthly.progress = prog.pct
            if prog.met then
                ObjectivesManager._markMonthlyCompleted(gameState, objectives, team, monthly)
            end
        end
    end
end

------------------------------------------------------
-- 每月检查（月末自动调用）
------------------------------------------------------

function ObjectivesManager._evaluateMonthlyObjective(gameState, team, monthly)
    if monthly.id == "monthly_derby_points" or monthly.id == "monthly_derby_win" then
        return ObjectivesManager._checkDerbyMonthlyCompletion(gameState, monthly)
    end
    local stats = team and ObjectivesManager._getMonthlyStatsForEval(team, monthly, gameState) or nil
    return ObjectivesManager._checkMonthlyCompletion(monthly, stats)
end

function ObjectivesManager.onMonthEnd(gameState)
    local objectives = gameState.objectives
    if not objectives then return end

    local team = gameState.teams[gameState.playerTeamId]
    local monthlies = ObjectivesManager._getMonthlies(objectives)

    for _, monthly in ipairs(monthlies) do
        if monthly.status == "active" then
            if not ObjectivesManager._monthlyPeriodEnded(monthly, gameState.date) then
                goto continue_monthly
            end
            if ObjectivesManager._monthlyMatchesPlayed(gameState, team, monthly) == 0 then
                ObjectivesManager._markMonthlySkipped(gameState, objectives, team, monthly)
                goto continue_monthly
            end
            local completed = ObjectivesManager._evaluateMonthlyObjective(gameState, team, monthly)
            if completed then
                ObjectivesManager._markMonthlyCompleted(gameState, objectives, team, monthly)
            else
                ObjectivesManager._markMonthlyFailed(gameState, objectives, team, monthly)
            end
        end
        ::continue_monthly::
    end

    if team then
        team._lastMonthlyStats = nil
    end

    local newMonthlies = ObjectivesManager._generateMonthlies(gameState)
    objectives.monthlies = newMonthlies
    objectives.monthly = nil
    objectives.totalCount = (objectives.totalCount or 0) + #newMonthlies
end

function ObjectivesManager._findFixtureById(gameState, teamId, fixtureId)
    if not fixtureId then return nil end
    local lg = gameState:getTeamLeague(teamId)
    if lg and lg.fixtures then
        for _, f in ipairs(lg.fixtures) do
            if f.id == fixtureId then return f end
        end
    end
    for _, league in pairs(gameState.leagues or {}) do
        for _, f in ipairs(league.fixtures or {}) do
            if f.id == fixtureId then return f end
        end
    end
    return nil
end

function ObjectivesManager._checkDerbyMonthlyCompletion(gameState, monthly)
    local teamId = gameState.playerTeamId
    if not teamId or not monthly.fixtureId then return false end

    local fixture = ObjectivesManager._findFixtureById(gameState, teamId, monthly.fixtureId)
    if not fixture or fixture.status ~= "finished" then return false end

    local isHome = fixture.homeTeamId == teamId
    local goalsFor = isHome and fixture.homeGoals or fixture.awayGoals
    local goalsAgainst = isHome and fixture.awayGoals or fixture.homeGoals
    if monthly.id == "monthly_derby_win" then
        return goalsFor > goalsAgainst
    end
    return goalsFor >= goalsAgainst
end

function ObjectivesManager._checkMonthlyCompletion(monthly, stats)
    if monthly.id == "monthly_derby_points" or monthly.id == "monthly_derby_win" then
        return false
    end
    if not stats then return false end

    if monthly.minWins then
        return (stats.wins or 0) >= monthly.minWins
    end
    if monthly.streak then
        return hasConsecutiveUnbeaten(stats.results, monthly.streak)
    end
    if monthly.minGoals then
        return (stats.goalsFor or 0) >= monthly.minGoals
    end
    if monthly.minCleanSheets then
        return (stats.cleanSheets or 0) >= monthly.minCleanSheets
    end
    if monthly.minScorerGoals then
        return maxPlayerGoals(stats.playerGoals) >= monthly.minScorerGoals
    end

    local played = (stats.wins or 0) + (stats.draws or 0) + (stats.losses or 0)
    if monthly.id == "monthly_no_loss" then
        return played > 0 and (stats.losses or 0) == 0
    end

    -- 旧存档兼容
    if monthly.id == "monthly_unbeaten_3" then
        return hasConsecutiveUnbeaten(stats.results, 3)
    elseif monthly.id == "monthly_win_3" then
        return (stats.wins or 0) >= 3
    elseif monthly.id == "monthly_clean_sheet" then
        return (stats.cleanSheets or 0) >= 2
    elseif monthly.id == "monthly_goals_8" then
        return (stats.goalsFor or 0) >= 8
    elseif monthly.id == "monthly_top_scorer" and not monthly.minScorerGoals then
        return maxPlayerGoals(stats.playerGoals) >= 3
    end

    return false
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

    -- 检查是否有联赛冠军/前列成就（用于保护性加分）
    local hasLeagueSuccess = false
    for _, obj in ipairs(objectives.season) do
        if obj.category == "league" and obj.status == "completed" then
            hasLeagueSuccess = true
            break
        end
    end

    -- 董事会满意度调整（联赛成功时给予保护性加分）
    team.boardSatisfaction = team.boardSatisfaction or 50
    if rate >= 80 then
        team.boardSatisfaction = math.min(100, team.boardSatisfaction + 15)
    elseif rate >= 50 then
        team.boardSatisfaction = math.min(100, team.boardSatisfaction + 5)
    elseif rate < 30 then
        if hasLeagueSuccess then
            team.boardSatisfaction = math.max(0, team.boardSatisfaction - 5)
        else
            team.boardSatisfaction = math.max(0, team.boardSatisfaction - 15)
        end
    end

    -- 联赛成功额外加满意度（联赛是核心指标，应强于其他目标失败的惩罚）
    if hasLeagueSuccess then
        team.boardSatisfaction = math.min(100, team.boardSatisfaction + 10)
        if (team.boardWarnings or 0) > 0 then
            team.boardWarnings = math.max(0, team.boardWarnings - 1)
        end
    end

    gameState:sendMessage({
        category = "board",
        title = "赛季目标总结",
        body = string.format("目标完成率: %d%%\n董事会满意度: %d%%",
            rate, team.boardSatisfaction or 50),
        priority = "normal",
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

    -- 月度目标（可多条德比）
    local monthlies = ObjectivesManager._getMonthlies(objectives)
    local monthlyText, monthlyStatus
    if #monthlies == 1 then
        monthlyText = monthlies[1].text
        monthlyStatus = monthlies[1].status
    elseif #monthlies > 1 then
        local derbyCount = 0
        for _, m in ipairs(monthlies) do
            if m.category == "derby" then derbyCount = derbyCount + 1 end
        end
        if derbyCount > 0 then
            monthlyText = string.format("本月%d场德比目标", derbyCount)
        else
            monthlyText = monthlies[1].text
        end
        monthlyStatus = monthlies[1].status
    end

    local completed = objectives.completedCount or 0
    local total = objectives.totalCount or 1
    local pct = math.floor(completed / total * 100)

    local team = gameState.teams[gameState.playerTeamId]
    local seasonCompleted, seasonTotal = 0, 0
    for _, obj in ipairs(objectives.season or {}) do
        seasonTotal = seasonTotal + 1
        if obj.status == "completed" then seasonCompleted = seasonCompleted + 1 end
    end

    local monthlyProgressList = {}
    local activeMonthly = nil
    for _, m in ipairs(monthlies) do
        if m.status == "active" then
            local prog = ObjectivesManager.getMonthlyProgress(gameState, m, team)
            table.insert(monthlyProgressList, {
                text = m.text,
                status = m.status,
                progress = prog,
            })
            if not activeMonthly then activeMonthly = prog end
        end
    end

    return {
        hasObjectives = true,
        seasonText = seasonText,
        seasonStatus = seasonStatus,
        monthlyText = monthlyText,
        monthlyStatus = monthlyStatus,
        monthlies = monthlies,
        monthlyProgressList = monthlyProgressList,
        activeMonthlyProgress = activeMonthly,
        completedCount = completed,
        totalCount = total,
        seasonCompletedCount = seasonCompleted,
        seasonTotalCount = seasonTotal,
        progressPct = pct,
        allSeasonObjectives = objectives.season,
    }
end

return ObjectivesManager
