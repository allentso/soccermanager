-- systems/history_manager.lua
-- 名人堂/历史记录系统 - 记录每赛季冠军、奖项、重要转会、经理变动

local EventBus = require("scripts/app/event_bus")

local HistoryManager = {}

local GLOBAL_TOP_TRANSFERS_LIMIT = 5

local function _copyDate(date)
    if not date then return nil end
    return { year = date.year, month = date.month, day = date.day }
end

local function _transferSnapshot(record)
    return {
        season = record.season,
        date = _copyDate(record.date),
        playerId = record.playerId,
        playerName = record.playerName,
        fromTeamId = record.fromTeamId,
        fromTeamName = record.fromTeamName,
        toTeamId = record.toTeamId,
        toTeamName = record.toTeamName,
        amount = record.amount or 0,
        type = record.type or "permanent",
    }
end

local function _refreshGlobalTopTransfers(gameState, record)
    if not record or record.type ~= "permanent" or (record.amount or 0) <= 0 then return end
    gameState._globalTopTransfers = gameState._globalTopTransfers or {}

    table.insert(gameState._globalTopTransfers, _transferSnapshot(record))
    table.sort(gameState._globalTopTransfers, function(a, b)
        if (a.amount or 0) ~= (b.amount or 0) then return (a.amount or 0) > (b.amount or 0) end
        if (a.season or 0) ~= (b.season or 0) then return (a.season or 0) < (b.season or 0) end
        return (a.playerName or "") < (b.playerName or "")
    end)

    while #gameState._globalTopTransfers > GLOBAL_TOP_TRANSFERS_LIMIT do
        table.remove(gameState._globalTopTransfers)
    end
end

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
    if not gameState._teamLegendStats then
        gameState._teamLegendStats = {}
    end
    if not gameState._managerSaleHistory then
        gameState._managerSaleHistory = {}
    end
    if not gameState._globalTopTransfers then
        gameState._globalTopTransfers = {}
        -- 旧档 best-effort 回填：只能从尚未被 cap 裁掉的 _transferHistory 重建。
        for _, t in ipairs(gameState._transferHistory or {}) do
            _refreshGlobalTopTransfers(gameState, t)
        end
    end
    if not gameState.followedPlayers then
        gameState.followedPlayers = {}
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

    -- 杯赛冠军
    if gameState.domesticCups then
        record.domesticCups = {}
        for leagueKey, cup in pairs(gameState.domesticCups) do
            if cup.winner then
                local winnerTeam = gameState.teams[cup.winner]
                record.domesticCups[leagueKey] = {
                    name = cup.name,
                    winnerId = cup.winner,
                    winnerName = winnerTeam and winnerTeam.name or "?",
                }
            end
        end
    end

    -- 欧冠 / 欧联杯冠军
    if gameState.championsLeague and gameState.championsLeague.champion then
        local tid = gameState.championsLeague.champion
        local team = gameState.teams[tid]
        record.uclChampion = {
            teamId = tid,
            teamName = team and team.name or "?",
        }
    end
    if gameState.europaLeague and gameState.europaLeague.champion then
        local tid = gameState.europaLeague.champion
        local team = gameState.teams[tid]
        record.uelChampion = {
            teamId = tid,
            teamName = team and team.name or "?",
        }
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
    _refreshGlobalTopTransfers(gameState, record)

    -- 只保留最近 200 条
    while #gameState._transferHistory > 200 do
        table.remove(gameState._transferHistory, 1)
    end

    -- 玩家作为经理卖出的高额交易单独存一份，不受上面全局 200 条 cap 影响：
    -- 全局转会记录会被大量 AI 间交易迅速挤掉，玩家自己的经典转会故事在长档
    -- 里会消失。这里只记录"玩家球队卖给别队"的有偿永久转会。
    if record.type == "permanent"
        and gameState.playerTeamId
        and record.fromTeamId == gameState.playerTeamId
        and record.toTeamId ~= gameState.playerTeamId
        and (record.amount or 0) > 0 then
        local player = gameState.players[record.playerId]
        table.insert(gameState._managerSaleHistory, {
            season = record.season,
            date = record.date,
            playerId = record.playerId,
            playerName = record.playerName,
            overallAtSale = player and player.overall or nil,
            fromTeamId = record.fromTeamId,
            fromTeamName = record.fromTeamName,
            toTeamId = record.toTeamId,
            toTeamName = record.toTeamName,
            amount = record.amount,
        })

        -- 玩家出售记录远少于全球交易，200 条足够覆盖整个长档
        while #gameState._managerSaleHistory > 200 do
            table.remove(gameState._managerSaleHistory, 1)
        end
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
-- 欧洲杯冠军记录
------------------------------------------------------

function HistoryManager.recordEuroChampion(gameState, data)
    HistoryManager._ensureData(gameState)

    if not gameState._euroHistory then
        gameState._euroHistory = {}
    end

    table.insert(gameState._euroHistory, {
        season = data.season,
        championId = data.championId,
        championName = data.championName,
        runnerUpId = data.runnerUpId,
        runnerUpName = data.runnerUpName,
    })
end

function HistoryManager.getEuroHistory(gameState)
    HistoryManager._ensureData(gameState)
    return gameState._euroHistory or {}
end

------------------------------------------------------
-- 玩家国家队执教历史
------------------------------------------------------

--- 记录玩家执教国家队的赛事成绩
---@param gameState table
---@param data {season:number, competition:string, nationId:string, nationName:string, result:string, matchesPlayed:number, wins:number, draws:number, losses:number}
function HistoryManager.recordNTCoachResult(gameState, data)
    if not gameState._ntCoachHistory then
        gameState._ntCoachHistory = {}
    end
    table.insert(gameState._ntCoachHistory, {
        season = data.season,
        competition = data.competition,       -- "euro" | "worldcup"
        nationId = data.nationId,
        nationName = data.nationName,
        result = data.result,                 -- "冠军" / "亚军" / "四强" / "八强" / "十六强" / "小组赛出局"
        matchesPlayed = data.matchesPlayed or 0,
        wins = data.wins or 0,
        draws = data.draws or 0,
        losses = data.losses or 0,
    })
end

--- 获取玩家国家队执教历史
function HistoryManager.getNTCoachHistory(gameState)
    return gameState._ntCoachHistory or {}
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
--- 覆盖联赛、国内杯、欧冠、欧联、世界杯、欧洲杯六类冠军，按赛季聚合。
function HistoryManager.getChampionsList(gameState)
    HistoryManager._ensureData(gameState)

    local champions = {}
    local bySeasonIndex = {}  -- season -> champions 下标，用于合并国际赛事记录

    for _, record in ipairs(gameState.worldHistory) do
        local seasonChampions = {
            season = record.season,
            year = record.year,
            leagues = {},
            continental = {},
            cups = {},
            international = {},  -- 世界杯/欧洲杯（国家队），按赛季合并进来
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
        if record.uclChampion then
            table.insert(seasonChampions.continental, {
                competitionName = "欧洲冠军联赛",
                teamId = record.uclChampion.teamId,
                teamName = record.uclChampion.teamName,
            })
        end
        if record.uelChampion then
            table.insert(seasonChampions.continental, {
                competitionName = "欧洲联赛",
                teamId = record.uelChampion.teamId,
                teamName = record.uelChampion.teamName,
            })
        end
        for _, cupData in pairs(record.domesticCups or {}) do
            if cupData.winnerId then
                table.insert(seasonChampions.cups, {
                    competitionName = cupData.name or "国内杯赛",
                    teamId = cupData.winnerId,
                    teamName = cupData.winnerName,
                })
            end
        end
        table.insert(champions, seasonChampions)
        bySeasonIndex[record.season] = #champions
    end

    -- 合并世界杯/欧洲杯冠军（国家队维度，与俱乐部赛事按赛季对齐展示；
    -- 若该赛季没有对应的 worldHistory 记录则单独补一条）
    local function mergeInternational(historyList, competitionName)
        for _, rec in ipairs(historyList or {}) do
            local entry = {
                competitionName = competitionName,
                championName = rec.championName or rec.championId,
                runnerUpName = rec.runnerUpName,
            }
            local idx = bySeasonIndex[rec.season]
            if idx then
                table.insert(champions[idx].international, entry)
            else
                table.insert(champions, {
                    season = rec.season,
                    year = rec.season,
                    leagues = {},
                    continental = {},
                    cups = {},
                    international = { entry },
                })
                bySeasonIndex[rec.season] = #champions
            end
        end
    end

    mergeInternational(gameState._worldCupHistory, "世界杯")
    mergeInternational(gameState._euroHistory, "欧洲杯")

    table.sort(champions, function(a, b) return (a.season or 0) < (b.season or 0) end)

    return champions
end

--- 获取某球队的全部荣誉（联赛/国内杯/欧冠/欧联冠军，按赛季倒序）。
--- 统一的球队荣誉查询口径，避免 UI 层各自重复聚合 worldHistory。
function HistoryManager.getTeamHonors(gameState, teamId)
    HistoryManager._ensureData(gameState)

    local honors = {}
    for _, record in ipairs(gameState.worldHistory) do
        for _, leagueRecord in pairs(record.leagues or {}) do
            if leagueRecord.champion and leagueRecord.champion.teamId == teamId then
                table.insert(honors, {
                    season = record.season,
                    competition = "league",
                    title = leagueRecord.name or "联赛冠军",
                    detail = tostring(leagueRecord.champion.points or 0) .. "分",
                })
            end
        end
        if record.uclChampion and record.uclChampion.teamId == teamId then
            table.insert(honors, {
                season = record.season,
                competition = "ucl",
                title = "欧洲冠军联赛",
                detail = "冠军",
            })
        end
        if record.uelChampion and record.uelChampion.teamId == teamId then
            table.insert(honors, {
                season = record.season,
                competition = "uel",
                title = "欧洲联赛",
                detail = "冠军",
            })
        end
        for _, cupData in pairs(record.domesticCups or {}) do
            if cupData.winnerId == teamId then
                table.insert(honors, {
                    season = record.season,
                    competition = "cup",
                    title = cupData.name or "杯赛",
                    detail = "冠军",
                })
            end
        end
    end

    table.sort(honors, function(a, b) return (a.season or 0) > (b.season or 0) end)
    return honors
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

------------------------------------------------------
-- 队史传奇聚合（按球队维度记录效力过的球员生涯贡献）
--
-- 与 player.careerHistory（每球员只保留最近 5 季，超出折叠进 careerTotals，
-- 丢失按球队拆分的细节）和退役球员对象（Housekeeping 延迟一季后物理删除）
-- 不同，这里在每个赛季末把当季数据增量累加进
-- gameState._teamLegendStats[teamId][playerId]，不依赖任何会被折叠/裁剪
-- 的数据源，因此队史榜在长档中依然保持准确。
------------------------------------------------------

--- 赛季末聚合：把本赛季每个球员的出场/进球/助攻/零封、随队夺得的冠军数、
--- 个人荣誉，累加进其效力球队的传奇统计。
--- 必须在 SeasonManager._recordPlayerCareerHistory 写入本赛季 careerHistory
--- 之后调用（本函数读取刚追加的那条记录）。
---@param gameState table
---@param awards table|nil AwardsManager.processSeasonAwards 的返回值
function HistoryManager.updateTeamLegendStats(gameState, awards)
    HistoryManager._ensureData(gameState)
    local season = gameState.season

    -- 1) 本赛季各类冠军归属：同一球队若多冠可叠加计数，与"团队荣誉"数量口径一致
    local trophyCountByTeam = {}
    local function addTrophy(teamId)
        if not teamId then return end
        trophyCountByTeam[teamId] = (trophyCountByTeam[teamId] or 0) + 1
    end
    for _, lg in pairs(gameState.leagues or {}) do
        local sorted = lg:getSortedStandings()
        if sorted[1] then addTrophy(sorted[1].teamId) end
    end
    for _, cup in pairs(gameState.domesticCups or {}) do
        if cup.winner then addTrophy(cup.winner) end
    end
    if gameState.championsLeague and gameState.championsLeague.champion then
        addTrophy(gameState.championsLeague.champion)
    end
    if gameState.europaLeague and gameState.europaLeague.champion then
        addTrophy(gameState.europaLeague.champion)
    end

    local function ensureEntry(teamId, playerId, playerName, position)
        local teamMap = gameState._teamLegendStats[teamId]
        if not teamMap then
            teamMap = {}
            gameState._teamLegendStats[teamId] = teamMap
        end
        local entry = teamMap[playerId]
        if not entry then
            entry = {
                playerId = playerId,
                playerName = playerName,
                position = position,
                firstSeason = season,
                lastSeason = season,
                seasons = 0,
                appearances = 0,
                goals = 0,
                assists = 0,
                cleanSheets = 0,
                teamTitles = 0,
                individualAwards = {},
            }
            teamMap[playerId] = entry
        end
        return entry
    end

    -- 2) 逐球员累加本赛季出场数据（读取刚写入的本赛季 careerHistory 记录）
    for playerId, player in pairs(gameState.players) do
        local hist = player.careerHistory
        local rec = hist and hist[#hist]
        if rec and rec.season == season then
            local teamId = rec.teamId
            -- 退役球员在 _processRetirements 中已被清空 teamId，回退读取
            -- 退役前暂存的球队 ID（同一次 endSeason 内设置，见 season_manager.lua）
            if not teamId and player.retiredSeason == season then
                teamId = player._retiredFromTeamId
            end
            if teamId then
                local entry = ensureEntry(teamId, playerId, player.displayName, player.position)
                entry.playerName = player.displayName
                entry.position = player.position or entry.position
                entry.lastSeason = season
                entry.seasons = entry.seasons + 1
                entry.appearances = entry.appearances + (rec.appearances or 0)
                entry.goals = entry.goals + (rec.goals or 0)
                entry.assists = entry.assists + (rec.assists or 0)
                entry.cleanSheets = entry.cleanSheets + (rec.cleanSheets or 0)
                entry.teamTitles = entry.teamTitles + (trophyCountByTeam[teamId] or 0)
            end
        end
    end

    -- 3) 个人荣誉归属：直接使用奖项自带的 teamId（在退役处理之前计算，不受影响）
    if awards then
        local function markAward(data, key)
            if not data or not data.playerId or not data.teamId then return end
            local entry = ensureEntry(data.teamId, data.playerId, data.playerName, nil)
            entry.individualAwards[key] = (entry.individualAwards[key] or 0) + 1
        end
        for _, la in pairs(awards.leagues or {}) do
            markAward(la.goldenBoot, "goldenBoot")
            markAward(la.bestPlayer, "mvp")
            markAward(la.bestYoungPlayer, "bestYoungPlayer")
            markAward(la.topAssists, "topAssists")
            markAward(la.goldenGlove or la.bestGoalkeeper, "goldenGlove")
        end
        if awards.ballonDor and awards.ballonDor[1] then
            markAward(awards.ballonDor[1], "ballonDor")
        end
    end
end

--- 队史传奇展示用的奖项图标/文案元数据，UI 层统一从这里取，避免各处硬编码不一致。
HistoryManager.LEGEND_AWARD_META = {
    { key = "ballonDor",       label = "金球奖",  icon = "🏆" },
    { key = "goldenBoot",      label = "金靴奖",  icon = "⚽" },
    { key = "mvp",             label = "最佳球员", icon = "🌟" },
    { key = "bestYoungPlayer", label = "最佳新秀", icon = "🌱" },
    { key = "topAssists",      label = "助攻王",  icon = "🎯" },
    { key = "goldenGlove",     label = "金手套",  icon = "🧤" },
}

--- 查询某球队的队史球星榜（默认按总进球数降序排列，取 Top10）。
function HistoryManager.getTeamLegendStats(gameState, teamId, limit)
    HistoryManager._ensureData(gameState)
    local teamMap = gameState._teamLegendStats[teamId]
    if not teamMap then return {} end

    local list = {}
    for _, entry in pairs(teamMap) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        if (a.goals or 0) ~= (b.goals or 0) then return (a.goals or 0) > (b.goals or 0) end
        if (a.appearances or 0) ~= (b.appearances or 0) then return (a.appearances or 0) > (b.appearances or 0) end
        if (a.teamTitles or 0) ~= (b.teamTitles or 0) then return (a.teamTitles or 0) > (b.teamTitles or 0) end
        return (a.playerName or "") < (b.playerName or "")
    end)

    limit = limit or 10
    local result = {}
    for i = 1, math.min(limit, #list) do
        result[i] = list[i]
    end
    return result
end

--- 获取玩家作为经理卖出的高额交易历史（按金额降序，默认 Top20）。
function HistoryManager.getManagerSaleHistory(gameState, limit)
    HistoryManager._ensureData(gameState)

    local sorted = {}
    for _, t in ipairs(gameState._managerSaleHistory) do
        table.insert(sorted, t)
    end
    table.sort(sorted, function(a, b) return (a.amount or 0) > (b.amount or 0) end)

    limit = limit or 20
    local result = {}
    for i = 1, math.min(limit, #sorted) do
        result[i] = sorted[i]
    end
    return result
end

--- 获取开档至今全球标王 Top5（固定快照，不受 _transferHistory cap 影响）。
function HistoryManager.getGlobalTopTransfers(gameState, limit)
    HistoryManager._ensureData(gameState)

    limit = limit or GLOBAL_TOP_TRANSFERS_LIMIT
    local result = {}
    for i = 1, math.min(limit, #(gameState._globalTopTransfers or {})) do
        result[i] = gameState._globalTopTransfers[i]
    end
    return result
end

------------------------------------------------------
-- 传奇/球员关注追踪
------------------------------------------------------

local function _followKey(playerId)
    return tonumber(playerId) or playerId
end

function HistoryManager.isPlayerFollowed(gameState, playerId)
    HistoryManager._ensureData(gameState)
    if not playerId then return false end
    local key = _followKey(playerId)
    return gameState.followedPlayers[key] ~= nil or gameState.followedPlayers[tostring(key)] ~= nil
end

function HistoryManager.followPlayer(gameState, player)
    HistoryManager._ensureData(gameState)
    if not player or not player.id then return nil end

    local team = player.teamId and gameState.teams[player.teamId] or nil
    local date = gameState.date or {}
    local entry = {
        playerId = player.id,
        playerName = player.displayName or player.name or "?",
        position = player.position,
        teamId = player.teamId,
        teamName = team and team.name or nil,
        overall = player.overall,
        followedSeason = gameState.season,
        followedDate = { year = date.year, month = date.month, day = date.day },
    }
    gameState.followedPlayers[_followKey(player.id)] = entry
    return entry
end

function HistoryManager.unfollowPlayer(gameState, playerId)
    HistoryManager._ensureData(gameState)
    if not playerId then return end
    local key = _followKey(playerId)
    gameState.followedPlayers[key] = nil
    gameState.followedPlayers[tostring(key)] = nil
end

function HistoryManager.toggleFollowPlayer(gameState, player)
    if not player or not player.id then return false end
    if HistoryManager.isPlayerFollowed(gameState, player and player.id) then
        HistoryManager.unfollowPlayer(gameState, player.id)
        return false
    end
    HistoryManager.followPlayer(gameState, player)
    return true
end

function HistoryManager.getFollowedPlayers(gameState)
    HistoryManager._ensureData(gameState)
    local result = {}
    for key, entry in pairs(gameState.followedPlayers or {}) do
        local playerId = tonumber(key) or (type(entry) == "table" and entry.playerId) or key
        if type(entry) == "table" then
            table.insert(result, entry)
        else
            local player = gameState.players[playerId]
            table.insert(result, {
                playerId = playerId,
                playerName = player and player.displayName or tostring(playerId),
                teamId = player and player.teamId or nil,
                position = player and player.position or nil,
                overall = player and player.overall or nil,
            })
        end
    end
    table.sort(result, function(a, b)
        return (a.playerName or "") < (b.playerName or "")
    end)
    return result
end

function HistoryManager.isFollowedNewsArticle(gameState, article)
    if not article then return false end
    HistoryManager._ensureData(gameState)
    local followed = gameState.followedPlayers or {}
    if next(followed) == nil then return false end

    local function isFollowed(playerId)
        if not playerId then return false end
        local key = _followKey(playerId)
        return followed[key] ~= nil or followed[tostring(key)] ~= nil
    end

    if isFollowed(article.playerId) then return true end

    for _, pid in ipairs(article.relatedPlayers or {}) do
        if isFollowed(pid) then return true end
    end

    if article.relatedTeams then
        local followedTeams = {}
        for key, entry in pairs(followed) do
            local playerId = tonumber(key) or (type(entry) == "table" and entry.playerId) or key
            local livePlayer = gameState.players[playerId]
            if livePlayer and livePlayer.teamId then
                followedTeams[livePlayer.teamId] = true
            end
            if type(entry) == "table" and entry.teamId then
                followedTeams[entry.teamId] = true
            end
        end
        for _, tid in ipairs(article.relatedTeams) do
            if followedTeams[tid] then return true end
        end
    end

    return false
end

function HistoryManager.getFollowedNews(gameState)
    HistoryManager._ensureData(gameState)
    local result = {}
    for _, article in ipairs(gameState.news or {}) do
        if HistoryManager.isFollowedNewsArticle(gameState, article) then
            table.insert(result, article)
        end
    end
    return result
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
