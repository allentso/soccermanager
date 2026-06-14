-- systems/records_manager.lua
-- 记录系统 - 管理奖杯、联赛记录、球员记录、经理生涯统计

local EventBus = require("scripts/app/event_bus")

local RecordsManager = {}

local function _incrementManagerTrophyStat(gameState)
    local mgr = gameState:getPlayerManager()
    if mgr and mgr.stats then
        mgr.stats.trophies = (mgr.stats.trophies or 0) + 1
    end
end

------------------------------------------------------
-- 数据结构初始化
------------------------------------------------------

function RecordsManager._ensureData(gameState)
    if not gameState.records then
        gameState.records = {}
    end
    local r = gameState.records

    if not r.trophies then r.trophies = {} end

    if not r.leagueRecords then
        r.leagueRecords = {
            highestPoints = nil,        -- { teamName, teamId, points, season }
            mostWins = nil,             -- { teamName, teamId, wins, season }
            fewestGoalsConceded = nil,  -- { teamName, teamId, goalsAgainst, season }
            consecutiveChampionships = nil, -- { teamName, teamId, count, startSeason, endSeason }
        }
    end

    if not r.playerRecords then
        r.playerRecords = {
            singleSeasonGoals = nil,    -- { playerName, playerId, goals, season, teamName }
            singleSeasonAssists = nil,
            singleSeasonRating = nil,   -- { playerName, playerId, rating, season, teamName }
            allTimeGoals = {},           -- Top10: { playerName, playerId, goals }
            allTimeAssists = {},
            allTimeAppearances = {},
            uclSingleSeasonGoals = nil, -- { playerName, playerId, goals, season, teamName }
        }
    end

    if not r.managerRecords then
        r.managerRecords = {
            totalSeasons = 0,
            leagueTitles = 0,
            uclTitles = 0,
            cupTitles = 0,
            worldCupTitles = 0,
            euroTitles = 0,
            bestLeagueFinish = 999,
            totalWins = 0,
            totalDraws = 0,
            totalLosses = 0,
            totalMatches = 0,
            winRate = 0,
            longestWinStreak = 0,
            currentWinStreak = 0,
            longestUnbeatenStreak = 0,
            currentUnbeatenStreak = 0,
            totalSpent = 0,
            totalEarned = 0,
            youthPromoted = 0,
        }
    end
end

------------------------------------------------------
-- 比赛结束后更新经理统计（仅限玩家球队的比赛）
------------------------------------------------------

function RecordsManager.onMatchEnd(gameState, fixture)
    RecordsManager._ensureData(gameState)

    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    -- 只统计玩家球队参与的比赛
    local isHome = fixture.homeTeamId == playerTeamId
    local isAway = fixture.awayTeamId == playerTeamId
    if not isHome and not isAway then return end

    local mr = gameState.records.managerRecords
    mr.totalMatches = mr.totalMatches + 1

    local homeGoals = fixture.homeGoals or 0
    local awayGoals = fixture.awayGoals or 0

    local won = false
    local drawn = false
    if isHome then
        if homeGoals > awayGoals then won = true
        elseif homeGoals == awayGoals then drawn = true end
    else
        if awayGoals > homeGoals then won = true
        elseif awayGoals == homeGoals then drawn = true end
    end

    if won then
        mr.totalWins = mr.totalWins + 1
        mr.currentWinStreak = mr.currentWinStreak + 1
        mr.currentUnbeatenStreak = mr.currentUnbeatenStreak + 1
        if mr.currentWinStreak > mr.longestWinStreak then
            mr.longestWinStreak = mr.currentWinStreak
        end
        if mr.currentUnbeatenStreak > mr.longestUnbeatenStreak then
            mr.longestUnbeatenStreak = mr.currentUnbeatenStreak
        end
    elseif drawn then
        mr.totalDraws = mr.totalDraws + 1
        mr.currentWinStreak = 0
        mr.currentUnbeatenStreak = mr.currentUnbeatenStreak + 1
        if mr.currentUnbeatenStreak > mr.longestUnbeatenStreak then
            mr.longestUnbeatenStreak = mr.currentUnbeatenStreak
        end
    else
        mr.totalLosses = mr.totalLosses + 1
        mr.currentWinStreak = 0
        mr.currentUnbeatenStreak = 0
    end

    -- 更新胜率
    if mr.totalMatches > 0 then
        mr.winRate = math.floor((mr.totalWins / mr.totalMatches) * 1000) / 10  -- 保留一位小数
    end

    -- 同步更新经理域对象的统计（供 manager_view UI 使用）
    local manager = gameState:getPlayerManager()
    if manager and manager.stats then
        if won then
            manager.stats.wins = (manager.stats.wins or 0) + 1
        elseif drawn then
            manager.stats.draws = (manager.stats.draws or 0) + 1
        else
            manager.stats.losses = (manager.stats.losses or 0) + 1
        end
    end
end

------------------------------------------------------
-- 赛季结束时更新所有记录
------------------------------------------------------

function RecordsManager.onSeasonEnd(gameState)
    RecordsManager._ensureData(gameState)

    local r = gameState.records
    local mr = r.managerRecords
    local season = gameState.season

    -- 增加执教赛季计数
    mr.totalSeasons = mr.totalSeasons + 1

    -- ====== 检查联赛记录 ======
    RecordsManager._checkLeagueRecords(gameState, season)

    -- ====== 检查球员单赛季记录 ======
    RecordsManager._checkPlayerSeasonRecords(gameState, season)

    -- ====== 更新球员历史累计 Top10 ======
    RecordsManager._updateAllTimePlayerRecords(gameState)

    -- ====== 检查玩家球队是否夺冠（联赛） ======
    RecordsManager._checkLeagueChampionship(gameState, season)

    -- ====== 更新经理最佳排名 ======
    if gameState.league and gameState.playerTeamId then
        local pos = gameState.league:getTeamPosition(gameState.playerTeamId)
        if pos and pos < mr.bestLeagueFinish then
            mr.bestLeagueFinish = pos
        end
    end
end

------------------------------------------------------
-- 检查联赛记录
------------------------------------------------------

function RecordsManager._checkLeagueRecords(gameState, season)
    local lr = gameState.records.leagueRecords
    local brokenRecords = {}

    for leagueKey, lg in pairs(gameState.leagues) do
        local sorted = lg:getSortedStandings()
        if not sorted or #sorted == 0 then goto nextLeague end

        local champion = sorted[1]
        local team = gameState.teams[champion.teamId]
        local teamName = team and team.name or "?"

        -- 最高积分
        if not lr.highestPoints or champion.points > lr.highestPoints.points then
            lr.highestPoints = {
                teamName = teamName,
                teamId = champion.teamId,
                points = champion.points,
                season = season,
                leagueName = lg.name,
            }
            table.insert(brokenRecords, {
                type = "highestPoints",
                desc = string.format("最高赛季积分: %s (%d分)", teamName, champion.points),
            })
        end

        -- 最多胜场
        if not lr.mostWins or champion.wins > lr.mostWins.wins then
            lr.mostWins = {
                teamName = teamName,
                teamId = champion.teamId,
                wins = champion.wins,
                season = season,
                leagueName = lg.name,
            }
            table.insert(brokenRecords, {
                type = "mostWins",
                desc = string.format("单赛季最多胜场: %s (%d胜)", teamName, champion.wins),
            })
        end

        -- 最少失球（遍历所有队伍找最少的）
        for _, entry in ipairs(sorted) do
            if entry.played and entry.played > 0 then
                if not lr.fewestGoalsConceded or entry.goalsAgainst < lr.fewestGoalsConceded.goalsAgainst then
                    local t = gameState.teams[entry.teamId]
                    lr.fewestGoalsConceded = {
                        teamName = t and t.name or "?",
                        teamId = entry.teamId,
                        goalsAgainst = entry.goalsAgainst,
                        season = season,
                        leagueName = lg.name,
                    }
                    table.insert(brokenRecords, {
                        type = "fewestGoalsConceded",
                        desc = string.format("单赛季最少失球: %s (%d球)", t and t.name or "?", entry.goalsAgainst),
                    })
                end
            end
        end

        -- 连续冠军（只检查玩家联赛的冠军）
        if leagueKey == gameState.playerLeagueId then
            RecordsManager._checkConsecutiveChampionships(gameState, champion.teamId, teamName, season)
        end

        ::nextLeague::
    end

    -- 如果有记录被打破，发送事件
    if #brokenRecords > 0 then
        EventBus.emit("records_broken", { records = brokenRecords, season = season })
    end
end

------------------------------------------------------
-- 连续冠军检测
------------------------------------------------------

function RecordsManager._checkConsecutiveChampionships(gameState, championTeamId, teamName, season)
    local lr = gameState.records.leagueRecords

    -- 向前追溯：从历史中检查该队连续夺冠了几次
    local count = 1  -- 当前赛季已经是冠军
    local startSeason = season

    -- 从历史记录中往回查
    local history = gameState.worldHistory or {}
    for i = #history, 1, -1 do
        local record = history[i]
        if record.season >= season then goto nextRecord end -- 跳过当前/未来赛季

        local wasChampion = false
        for lk, lr2 in pairs(record.leagues or {}) do
            if lk == gameState.playerLeagueId and lr2.champion and lr2.champion.teamId == championTeamId then
                wasChampion = true
                break
            end
        end

        if wasChampion then
            count = count + 1
            startSeason = record.season
        else
            break  -- 连续中断
        end

        ::nextRecord::
    end

    if count >= 2 then
        if not lr.consecutiveChampionships or count > lr.consecutiveChampionships.count then
            lr.consecutiveChampionships = {
                teamName = teamName,
                teamId = championTeamId,
                count = count,
                startSeason = startSeason,
                endSeason = season,
            }
        end
    end
end

------------------------------------------------------
-- 检查球员单赛季记录
------------------------------------------------------

function RecordsManager._checkPlayerSeasonRecords(gameState, season)
    local pr = gameState.records.playerRecords
    local brokenRecords = {}

    for _, player in pairs(gameState.players) do
        if player.retired then goto nextPlayer end
        local stats = player.seasonStats
        if not stats or (stats.appearances or 0) < 5 then goto nextPlayer end

        local team = gameState.teams[player.teamId]
        local teamName = team and team.name or "?"

        -- 单赛季最多进球
        if stats.goals and stats.goals > 0 then
            if not pr.singleSeasonGoals or stats.goals > pr.singleSeasonGoals.goals then
                pr.singleSeasonGoals = {
                    playerName = player.displayName,
                    playerId = player.id,
                    goals = stats.goals,
                    season = season,
                    teamName = teamName,
                }
                table.insert(brokenRecords, {
                    type = "singleSeasonGoals",
                    desc = string.format("单赛季最多进球: %s (%d球)", player.displayName, stats.goals),
                })
            end
        end

        -- 单赛季最多助攻
        if stats.assists and stats.assists > 0 then
            if not pr.singleSeasonAssists or stats.assists > pr.singleSeasonAssists.assists then
                pr.singleSeasonAssists = {
                    playerName = player.displayName,
                    playerId = player.id,
                    assists = stats.assists,
                    season = season,
                    teamName = teamName,
                }
                table.insert(brokenRecords, {
                    type = "singleSeasonAssists",
                    desc = string.format("单赛季最多助攻: %s (%d次)", player.displayName, stats.assists),
                })
            end
        end

        -- 单赛季最高评分（至少10场）
        if stats.appearances >= 10 and stats.avgRating and stats.avgRating > 0 then
            if not pr.singleSeasonRating or stats.avgRating > pr.singleSeasonRating.rating then
                pr.singleSeasonRating = {
                    playerName = player.displayName,
                    playerId = player.id,
                    rating = stats.avgRating,
                    season = season,
                    teamName = teamName,
                }
                table.insert(brokenRecords, {
                    type = "singleSeasonRating",
                    desc = string.format("单赛季最高评分: %s (%.1f)", player.displayName, stats.avgRating),
                })
            end
        end

        ::nextPlayer::
    end

    if #brokenRecords > 0 then
        EventBus.emit("player_records_broken", { records = brokenRecords, season = season })
    end
end

------------------------------------------------------
-- 更新球员历史累计 Top10
------------------------------------------------------

function RecordsManager._updateAllTimePlayerRecords(gameState)
    local pr = gameState.records.playerRecords

    -- 从所有球员的 careerHistory 累计统计
    local goalTotals = {}    -- { playerId = total }
    local assistTotals = {}
    local appTotals = {}

    for _, player in pairs(gameState.players) do
        if player.retired then goto nextPlayer end
        local totalGoals = (player.seasonStats and player.seasonStats.goals or 0)
        local totalAssists = (player.seasonStats and player.seasonStats.assists or 0)
        local totalApps = (player.seasonStats and player.seasonStats.appearances or 0)

        -- 累加历史赛季数据
        for _, hist in ipairs(player.careerHistory or {}) do
            totalGoals = totalGoals + (hist.goals or 0)
            totalAssists = totalAssists + (hist.assists or 0)
            totalApps = totalApps + (hist.appearances or 0)
        end

        -- 累加被 Housekeeping 折叠的早期赛季汇总
        if player.careerTotals then
            totalGoals = totalGoals + (player.careerTotals.goals or 0)
            totalAssists = totalAssists + (player.careerTotals.assists or 0)
            totalApps = totalApps + (player.careerTotals.appearances or 0)
        end

        if totalGoals > 0 then
            table.insert(goalTotals, { playerName = player.displayName, playerId = player.id, value = totalGoals })
        end
        if totalAssists > 0 then
            table.insert(assistTotals, { playerName = player.displayName, playerId = player.id, value = totalAssists })
        end
        if totalApps > 0 then
            table.insert(appTotals, { playerName = player.displayName, playerId = player.id, value = totalApps })
        end

        ::nextPlayer::
    end

    -- 排序取 Top10
    table.sort(goalTotals, function(a, b) return a.value > b.value end)
    table.sort(assistTotals, function(a, b) return a.value > b.value end)
    table.sort(appTotals, function(a, b) return a.value > b.value end)

    pr.allTimeGoals = {}
    for i = 1, math.min(10, #goalTotals) do
        table.insert(pr.allTimeGoals, goalTotals[i])
    end

    pr.allTimeAssists = {}
    for i = 1, math.min(10, #assistTotals) do
        table.insert(pr.allTimeAssists, assistTotals[i])
    end

    pr.allTimeAppearances = {}
    for i = 1, math.min(10, #appTotals) do
        table.insert(pr.allTimeAppearances, appTotals[i])
    end
end

------------------------------------------------------
-- 联赛夺冠检查（赛季结束时调用）
------------------------------------------------------

function RecordsManager._checkLeagueChampionship(gameState, season)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId or not gameState.league then return end

    local sorted = gameState.league:getSortedStandings()
    if not sorted or #sorted == 0 then return end

    if sorted[1].teamId == playerTeamId then
        local team = gameState:getPlayerTeam()
        local teamName = team and team.name or "?"

        -- 添加奖杯
        table.insert(gameState.records.trophies, {
            season = season,
            year = gameState.date.year,
            competition = "league",
            competitionName = gameState.league.name or "联赛",
            teamId = playerTeamId,
            teamName = teamName,
            points = sorted[1].points,
            wins = sorted[1].wins,
        })

        -- 更新经理记录
        gameState.records.managerRecords.leagueTitles = gameState.records.managerRecords.leagueTitles + 1

        -- 触发夺冠事件（UI 层监听）
        EventBus.emit("championship_won", {
            competition = "league",
            competitionName = gameState.league.name or "联赛",
            teamId = playerTeamId,
            teamName = teamName,
            season = season,
            stats = sorted[1],
        })
    end
end

------------------------------------------------------
-- UCL 夺冠（由 champions_league 调用）
------------------------------------------------------

function RecordsManager.onUCLChampionship(gameState, winnerTeamId)
    RecordsManager._ensureData(gameState)

    local playerTeamId = gameState.playerTeamId
    if winnerTeamId ~= playerTeamId then return end

    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "?"
    local season = gameState.season

    table.insert(gameState.records.trophies, {
        season = season,
        year = gameState.date.year,
        competition = "ucl",
        competitionName = "欧洲冠军联赛",
        teamId = playerTeamId,
        teamName = teamName,
    })

    gameState.records.managerRecords.uclTitles = gameState.records.managerRecords.uclTitles + 1
    _incrementManagerTrophyStat(gameState)

    EventBus.emit("championship_won", {
        competition = "ucl",
        competitionName = "欧洲冠军联赛",
        teamId = playerTeamId,
        teamName = teamName,
        season = season,
    })
end

------------------------------------------------------
-- 国内杯赛夺冠（由 domestic_cup 调用）
------------------------------------------------------

function RecordsManager.onDomesticCupChampionship(gameState, cupName, winnerTeamId)
    RecordsManager._ensureData(gameState)

    local playerTeamId = gameState.playerTeamId
    if winnerTeamId ~= playerTeamId then return end

    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "?"
    local season = gameState.season

    table.insert(gameState.records.trophies, {
        season = season,
        year = gameState.date.year,
        competition = "cup",
        competitionName = cupName,
        teamId = playerTeamId,
        teamName = teamName,
    })

    gameState.records.managerRecords.cupTitles = (gameState.records.managerRecords.cupTitles or 0) + 1
    _incrementManagerTrophyStat(gameState)

    EventBus.emit("championship_won", {
        competition = "cup",
        competitionName = cupName,
        teamId = playerTeamId,
        teamName = teamName,
        season = season,
    })
end

------------------------------------------------------
-- 世界杯夺冠（由 world_cup 调用）
------------------------------------------------------

function RecordsManager.onWorldCupChampionship(gameState, winnerNationCode)
    RecordsManager._ensureData(gameState)

    local playerNation = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation
    if not playerNation or winnerNationCode ~= playerNation then return end

    local playerTeamId = gameState.playerTeamId
    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "?"
    local season = gameState.season

    table.insert(gameState.records.trophies, {
        season = season,
        year = gameState.date.year,
        competition = "worldcup",
        competitionName = "世界杯",
        teamId = playerTeamId,
        teamName = teamName,
    })

    gameState.records.managerRecords.worldCupTitles = gameState.records.managerRecords.worldCupTitles + 1
    _incrementManagerTrophyStat(gameState)

    EventBus.emit("championship_won", {
        competition = "worldcup",
        competitionName = "世界杯",
        teamId = playerTeamId,
        teamName = teamName,
        season = season,
    })
end

function RecordsManager.onEuroChampionship(gameState, winnerNationCode)
    RecordsManager._ensureData(gameState)

    local playerNation = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation
    if not playerNation or winnerNationCode ~= playerNation then return end

    local playerTeamId = gameState.playerTeamId
    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "?"
    local season = gameState.season

    table.insert(gameState.records.trophies, {
        season = season,
        year = gameState.date.year,
        competition = "euro",
        competitionName = "欧洲杯",
        teamId = playerTeamId,
        teamName = teamName,
    })

    gameState.records.managerRecords.euroTitles = (gameState.records.managerRecords.euroTitles or 0) + 1
    _incrementManagerTrophyStat(gameState)

    EventBus.emit("championship_won", {
        competition = "euro",
        competitionName = "欧洲杯",
        teamId = playerTeamId,
        teamName = teamName,
        season = season,
    })
end

------------------------------------------------------
-- 转会完成时更新经理统计
------------------------------------------------------

function RecordsManager.onTransferComplete(gameState, transferData)
    RecordsManager._ensureData(gameState)

    local mr = gameState.records.managerRecords
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    local amount = transferData.amount or 0
    if transferData.toTeamId == playerTeamId then
        -- 买入
        mr.totalSpent = mr.totalSpent + amount
    elseif transferData.fromTeamId == playerTeamId then
        -- 卖出
        mr.totalEarned = mr.totalEarned + amount
    end
end

------------------------------------------------------
-- 青训提拔时更新
------------------------------------------------------

function RecordsManager.onYouthPromoted(gameState)
    RecordsManager._ensureData(gameState)
    gameState.records.managerRecords.youthPromoted = gameState.records.managerRecords.youthPromoted + 1
end

------------------------------------------------------
-- 查询接口
------------------------------------------------------

function RecordsManager.getTrophies(gameState)
    RecordsManager._ensureData(gameState)
    return gameState.records.trophies
end

function RecordsManager.getTrophyCount(gameState)
    RecordsManager._ensureData(gameState)
    local counts = { league = 0, ucl = 0, cup = 0, euro = 0, worldcup = 0, total = 0 }
    for _, trophy in ipairs(gameState.records.trophies) do
        local comp = trophy.competition or "league"
        counts[comp] = (counts[comp] or 0) + 1
        counts.total = counts.total + 1
    end
    return counts
end

function RecordsManager.getLeagueRecords(gameState)
    RecordsManager._ensureData(gameState)
    return gameState.records.leagueRecords
end

function RecordsManager.getPlayerRecords(gameState)
    RecordsManager._ensureData(gameState)
    return gameState.records.playerRecords
end

function RecordsManager.getManagerRecords(gameState)
    RecordsManager._ensureData(gameState)
    return gameState.records.managerRecords
end

------------------------------------------------------
-- 存档迁移：旧存档首次加载时从 worldHistory 回溯
------------------------------------------------------

local function _hasTrophy(records, competition, season)
    for _, trophy in ipairs(records.trophies or {}) do
        if trophy.competition == competition and trophy.season == season then
            return true
        end
    end
    return false
end

function RecordsManager._reconcileTitleCounts(gameState)
    RecordsManager._ensureData(gameState)
    local mr = gameState.records.managerRecords
    local league, ucl, cup, wc = 0, 0, 0, 0
    for _, trophy in ipairs(gameState.records.trophies) do
        if trophy.competition == "league" then league = league + 1
        elseif trophy.competition == "ucl" then ucl = ucl + 1
        elseif trophy.competition == "cup" then cup = cup + 1
        elseif trophy.competition == "worldcup" then wc = wc + 1 end
    end
    mr.leagueTitles = math.max(mr.leagueTitles or 0, league)
    mr.uclTitles = math.max(mr.uclTitles or 0, ucl)
    mr.cupTitles = math.max(mr.cupTitles or 0, cup)
    mr.worldCupTitles = math.max(mr.worldCupTitles or 0, wc)
end

function RecordsManager.syncManagerProfile(gameState)
    RecordsManager._ensureData(gameState)
    local mgr = gameState:getPlayerManager()
    if not mgr then return end

    mgr.stats = mgr.stats or {}
    local trophyCount = #gameState.records.trophies
    if trophyCount > (mgr.stats.trophies or 0) then
        mgr.stats.trophies = trophyCount
    end

    local mr = gameState.records.managerRecords
    if mr.totalMatches == 0 and (mgr.stats.wins or 0) > 0 then
        mr.totalWins = mgr.stats.wins or 0
        mr.totalDraws = mgr.stats.draws or 0
        mr.totalLosses = mgr.stats.losses or 0
        mr.totalMatches = mr.totalWins + mr.totalDraws + mr.totalLosses
        if mr.totalMatches > 0 then
            mr.winRate = math.floor((mr.totalWins / mr.totalMatches) * 1000) / 10
        end
    end

    RecordsManager._reconcileTitleCounts(gameState)
end

function RecordsManager.migrateFromHistory(gameState)
    RecordsManager._ensureData(gameState)

    local playerTeamId = gameState.playerTeamId
    local r = gameState.records

    -- 从 worldHistory 回溯联赛冠军
    if playerTeamId then
        for _, record in ipairs(gameState.worldHistory or {}) do
            for leagueKey, leagueRecord in pairs(record.leagues or {}) do
                if leagueRecord.champion and leagueRecord.champion.teamId == playerTeamId then
                    if not _hasTrophy(r, "league", record.season) then
                        table.insert(r.trophies, {
                            season = record.season,
                            year = record.year,
                            competition = "league",
                            competitionName = leagueRecord.name or leagueKey,
                            teamId = playerTeamId,
                            teamName = leagueRecord.champion.teamName,
                            points = leagueRecord.champion.points,
                        })
                    end
                end
            end
        end
    end

    -- 从 UCL 完成记录回溯欧冠冠军
    if playerTeamId and gameState._uclCompletedSeasons then
        for seasonKey, winnerId in pairs(gameState._uclCompletedSeasons) do
            if winnerId == playerTeamId then
                local season = tonumber(seasonKey) or seasonKey
                if not _hasTrophy(r, "ucl", season) then
                    local team = gameState.teams[playerTeamId]
                    table.insert(r.trophies, {
                        season = season,
                        year = season,
                        competition = "ucl",
                        competitionName = "欧洲冠军联赛",
                        teamId = playerTeamId,
                        teamName = team and team.name or "?",
                    })
                end
            end
        end
    end

    -- 从世界杯历史回溯（玩家当时执教的国家队）
    local coachNation = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation
    for _, wcRecord in ipairs(gameState._worldCupHistory or {}) do
        if coachNation and wcRecord.championId == coachNation then
            if not _hasTrophy(r, "worldcup", wcRecord.season) then
                local team = playerTeamId and gameState.teams[playerTeamId]
                table.insert(r.trophies, {
                    season = wcRecord.season,
                    year = wcRecord.season,
                    competition = "worldcup",
                    competitionName = "世界杯",
                    teamId = playerTeamId,
                    teamName = team and team.name or wcRecord.championName,
                })
            end
        end
    end

    RecordsManager._reconcileTitleCounts(gameState)
end

return RecordsManager
