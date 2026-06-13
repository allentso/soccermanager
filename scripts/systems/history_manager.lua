-- systems/history_manager.lua
-- 名人堂/历史记录系统 - 记录每赛季冠军、奖项、重要转会、经理变动

local EventBus = require("scripts/app/event_bus")

local HistoryManager = {}

------------------------------------------------------
-- 数据结构初始化
------------------------------------------------------

function HistoryManager._ensureData(gameState)
    if not gameState.worldHistory then
        gameState.worldHistory = {}
    end
    if not gameState._transferHistory then
        gameState._transferHistory = {}
    end
    if not gameState._managerHistory then
        gameState._managerHistory = {}
    end
end

------------------------------------------------------
-- 赛季结束时记录完整历史（由 season_manager 调用）
------------------------------------------------------

function HistoryManager.recordSeasonEnd(gameState, awards)
    HistoryManager._ensureData(gameState)

    local season = gameState.season
    local record = {
        season = season,
        year = gameState.date.year,
        leagues = {},
        awards = awards,
        topTransfers = HistoryManager._getSeasonTopTransfers(gameState, season),
        managerChanges = HistoryManager._getSeasonManagerChanges(gameState, season),
    }

    -- 为每个联赛记录冠军和完整排名
    for leagueKey, lg in pairs(gameState.leagues) do
        local sorted = lg:getSortedStandings()
        local leagueRecord = {
            name = lg.name,
            champion = nil,
            runnerUp = nil,
            standings = {},
        }

        for i, entry in ipairs(sorted) do
            local team = gameState.teams[entry.teamId]
            local standingEntry = {
                position = i,
                teamId = entry.teamId,
                teamName = team and team.name or "?",
                points = entry.points,
                wins = entry.wins,
                draws = entry.draws,
                losses = entry.losses,
                goalsFor = entry.goalsFor,
                goalsAgainst = entry.goalsAgainst,
            }
            table.insert(leagueRecord.standings, standingEntry)

            if i == 1 then
                leagueRecord.champion = {
                    teamId = entry.teamId,
                    teamName = team and team.name or "?",
                    points = entry.points,
                }
            elseif i == 2 then
                leagueRecord.runnerUp = {
                    teamId = entry.teamId,
                    teamName = team and team.name or "?",
                    points = entry.points,
                }
            end
        end

        record.leagues[leagueKey] = leagueRecord
    end

    -- 玩家球队赛季财务快照（总结页展示；须在 resetSeasonFinance 之前写入）
    if gameState.playerTeamId then
        local team = gameState.teams[gameState.playerTeamId]
        if team then
            record.playerFinance = {
                seasonIncome = team.seasonIncome or 0,
                seasonExpense = team.seasonExpense or 0,
                balance = team.balance or 0,
                wageBudget = team.wageBudget or 0,
            }
        end
    end

    if gameState.lastPromotionRelegation then
        record.promotionRelegation = gameState.lastPromotionRelegation
    end

    -- 追加到世界历史
    table.insert(gameState.worldHistory, record)

    EventBus.emit("season_history_recorded", record)
    return record
end

------------------------------------------------------
-- 记录重要转会（由 transfer_manager 完成转会时调用）
------------------------------------------------------

function HistoryManager.recordTransfer(gameState, transferData)
    HistoryManager._ensureData(gameState)

    local record = {
        season = gameState.season,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        playerId = transferData.playerId,
        playerName = transferData.playerName,
        fromTeamId = transferData.fromTeamId,
        toTeamId = transferData.toTeamId,
        amount = transferData.amount,
        type = transferData.type or "permanent", -- permanent, loan, free
    }

    -- 补充球队名
    local fromTeam = gameState.teams[record.fromTeamId]
    local toTeam = gameState.teams[record.toTeamId]
    record.fromTeamName = fromTeam and fromTeam.name or "自由球员"
    record.toTeamName = toTeam and toTeam.name or "?"

    table.insert(gameState._transferHistory, record)

    -- 只保留最近 200 条
    while #gameState._transferHistory > 200 do
        table.remove(gameState._transferHistory, 1)
    end
end

------------------------------------------------------
-- 记录经理变动（被解雇/辞职/新任命）
------------------------------------------------------

function HistoryManager.recordManagerChange(gameState, data)
    HistoryManager._ensureData(gameState)

    local record = {
        season = gameState.season,
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        teamId = data.teamId,
        teamName = data.teamName or "?",
        type = data.type, -- "sacked", "resigned", "appointed"
        managerName = data.managerName or "?",
        reason = data.reason,
    }

    table.insert(gameState._managerHistory, record)

    -- 只保留最近 100 条
    while #gameState._managerHistory > 100 do
        table.remove(gameState._managerHistory, 1)
    end
end

------------------------------------------------------
-- 查询：本赛季重要转会（金额前10）
------------------------------------------------------

function HistoryManager._getSeasonTopTransfers(gameState, season)
    HistoryManager._ensureData(gameState)

    local seasonTransfers = {}
    for _, t in ipairs(gameState._transferHistory) do
        if t.season == season then
            table.insert(seasonTransfers, t)
        end
    end

    -- 按金额降序
    table.sort(seasonTransfers, function(a, b)
        return (a.amount or 0) > (b.amount or 0)
    end)

    -- 取前10条
    local result = {}
    for i = 1, math.min(10, #seasonTransfers) do
        table.insert(result, seasonTransfers[i])
    end
    return result
end

------------------------------------------------------
-- 查询：本赛季经理变动
------------------------------------------------------

function HistoryManager._getSeasonManagerChanges(gameState, season)
    HistoryManager._ensureData(gameState)

    local changes = {}
    for _, m in ipairs(gameState._managerHistory) do
        if m.season == season then
            table.insert(changes, m)
        end
    end
    return changes
end

------------------------------------------------------
-- 世界杯冠军记录
------------------------------------------------------

function HistoryManager.recordWorldCupChampion(gameState, data)
    HistoryManager._ensureData(gameState)

    if not gameState._worldCupHistory then
        gameState._worldCupHistory = {}
    end

    local record = {
        season = data.season,          -- 世界杯举办年份（如2026）
        championId = data.championId,  -- 冠军国家代码
        championName = data.championName,
        runnerUpId = data.runnerUpId,
        runnerUpName = data.runnerUpName,
    }

    table.insert(gameState._worldCupHistory, record)
end

--- 获取世界杯冠军历史列表
function HistoryManager.getWorldCupHistory(gameState)
    HistoryManager._ensureData(gameState)
    return gameState._worldCupHistory or {}
end

------------------------------------------------------
-- UI 查询接口
------------------------------------------------------

--- 获取所有赛季历史
function HistoryManager.getWorldHistory(gameState)
    HistoryManager._ensureData(gameState)
    return gameState.worldHistory
end

--- 获取某赛季历史
function HistoryManager.getSeasonHistory(gameState, season)
    HistoryManager._ensureData(gameState)
    for _, record in ipairs(gameState.worldHistory) do
        if record.season == season then
            return record
        end
    end
    return nil
end

--- 获取所有冠军列表（名人堂核心数据）
function HistoryManager.getChampionsList(gameState)
    HistoryManager._ensureData(gameState)

    local champions = {}
    for _, record in ipairs(gameState.worldHistory) do
        local seasonChampions = {
            season = record.season,
            year = record.year,
            leagues = {},
        }
        for leagueKey, leagueRecord in pairs(record.leagues or {}) do
            if leagueRecord.champion then
                seasonChampions.leagues[leagueKey] = {
                    leagueName = leagueRecord.name,
                    teamId = leagueRecord.champion.teamId,
                    teamName = leagueRecord.champion.teamName,
                    points = leagueRecord.champion.points,
                }
            end
        end
        table.insert(champions, seasonChampions)
    end

    return champions
end

--- 获取某球队的历史成绩
function HistoryManager.getTeamHistory(gameState, teamId)
    HistoryManager._ensureData(gameState)

    local history = {
        championships = 0,
        bestPosition = 999,
        positions = {},   -- {season, position, points, leagueName}
    }

    for _, record in ipairs(gameState.worldHistory) do
        for _, leagueRecord in pairs(record.leagues or {}) do
            for _, standing in ipairs(leagueRecord.standings or {}) do
                if standing.teamId == teamId then
                    table.insert(history.positions, {
                        season = record.season,
                        position = standing.position,
                        points = standing.points,
                        leagueName = leagueRecord.name,
                    })
                    if standing.position < history.bestPosition then
                        history.bestPosition = standing.position
                    end
                    if standing.position == 1 then
                        history.championships = history.championships + 1
                    end
                    break
                end
            end
        end
    end

    return history
end

--- 获取转会历史（支持按球队筛选）
function HistoryManager.getTransferHistory(gameState, teamId)
    HistoryManager._ensureData(gameState)

    if not teamId then
        return gameState._transferHistory
    end

    local result = {}
    for _, t in ipairs(gameState._transferHistory) do
        if t.fromTeamId == teamId or t.toTeamId == teamId then
            table.insert(result, t)
        end
    end
    return result
end

--- 获取经理变动历史
function HistoryManager.getManagerHistory(gameState, teamId)
    HistoryManager._ensureData(gameState)

    if not teamId then
        return gameState._managerHistory
    end

    local result = {}
    for _, m in ipairs(gameState._managerHistory) do
        if m.teamId == teamId then
            table.insert(result, m)
        end
    end
    return result
end

return HistoryManager
