-- systems/awards_manager.lua
-- 赛季奖项系统 - 金靴、金手套、最佳球员、最佳年轻球员、最佳助攻、最佳经理
--
-- 字段契约（新写入统一使用左列字段名，右列仅为兼容旧存档的只读别名，
-- 新代码不应再写入右列字段）：
--   result.topAssists    (旧别名 bestAssist，只在读取端做兼容，不再写入)
--   result.goldenGlove    (旧别名 bestGoalkeeper，只在读取端做兼容，不再写入)
--
-- 持久化说明：本模块每赛季计算出的 awards 由调用方（SeasonManager）转交给
-- HistoryManager.recordSeasonEnd() 存入 gameState.worldHistory[].awards，这是
-- 奖项数据唯一的存档权威来源。本模块不再维护自己的历史列表（不再有
-- gameState._seasonAwards），避免出现"运行时有、读档后没有"的数据源分裂。

local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local AwardsManager = {}

------------------------------------------------------
-- 赛季末颁奖（由 season_manager 在赛季结束时调用）
------------------------------------------------------

function AwardsManager.processSeasonAwards(gameState)
    local season = gameState.season
    local awards = {
        season = season,
        leagues = {},
    }

    -- 为每个联赛计算奖项
    for leagueKey, lg in pairs(gameState.leagues) do
        local leagueAwards = AwardsManager._calculateLeagueAwards(gameState, lg)
        awards.leagues[leagueKey] = leagueAwards

        -- 发送新闻
        AwardsManager._announceAwards(gameState, lg.name, leagueAwards)
    end

    -- 全局最佳经理
    awards.bestManager = AwardsManager._calculateBestManager(gameState)

    -- 全局金球奖前三名
    awards.ballonDor = AwardsManager._calculateBallonDor(gameState)

    -- 如果涉及玩家球队的球员获奖，发送消息
    AwardsManager._notifyPlayerAwards(gameState, awards)

    EventBus.emit("season_awards_announced", awards)
    return awards
end

------------------------------------------------------
-- 计算联赛奖项
------------------------------------------------------

function AwardsManager._calculateLeagueAwards(gameState, league)
    local result = {}
    local teamIds = league.teamIds or {}

    -- 收集该联赛所有球员
    local leaguePlayers = {}
    for _, teamId in ipairs(teamIds) do
        local team = gameState.teams[teamId]
        if team then
            for _, pid in ipairs(team.playerIds) do
                local player = gameState.players[pid]
                if player and not player.retired then
                    table.insert(leaguePlayers, player)
                end
            end
        end
    end

    -- 1. 金靴奖（联赛进球最多）
    result.goldenBoot = AwardsManager._findTopScorer(leaguePlayers)

    -- 2. 最佳助攻
    result.topAssists = AwardsManager._findTopAssist(leaguePlayers)

    -- 3. 最佳球员（综合评分：进球 + 助攻 + 场均评分 + 出场数）
    result.bestPlayer = AwardsManager._findBestPlayer(leaguePlayers, gameState)

    -- 4. 最佳年轻球员（23岁及以下）
    result.bestYoungPlayer = AwardsManager._findBestYoungPlayer(leaguePlayers, gameState)

    -- 5. 金手套（门将零封场次最多）
    result.goldenGlove = AwardsManager._findGoldenGlove(leaguePlayers)

    return result
end

------------------------------------------------------
-- 金靴（进球最多）
------------------------------------------------------

function AwardsManager._findTopScorer(players)
    local best = nil
    local bestGoals = 0

    for _, player in ipairs(players) do
        local goals = player.seasonStats and player.seasonStats.goals or 0
        if goals > bestGoals then
            bestGoals = goals
            best = player
        elseif goals == bestGoals and goals > 0 and best then
            -- 相同进球数比较出场数（少出场更优）
            local bestApp = best.seasonStats and best.seasonStats.appearances or 0
            local curApp = player.seasonStats and player.seasonStats.appearances or 0
            if curApp < bestApp then
                best = player
            end
        end
    end

    if best then
        return {
            playerId = best.id,
            playerName = best.displayName,
            teamId = best.teamId,
            goals = bestGoals,
        }
    end
    return nil
end

------------------------------------------------------
-- 最佳助攻
------------------------------------------------------

function AwardsManager._findTopAssist(players)
    local best = nil
    local bestAssists = 0

    for _, player in ipairs(players) do
        local assists = player.seasonStats and player.seasonStats.assists or 0
        if assists > bestAssists then
            bestAssists = assists
            best = player
        end
    end

    if best then
        return {
            playerId = best.id,
            playerName = best.displayName,
            teamId = best.teamId,
            assists = bestAssists,
        }
    end
    return nil
end

------------------------------------------------------
-- 最佳球员（综合评分）
------------------------------------------------------

function AwardsManager._findBestPlayer(players, gameState)
    local best = nil
    local bestScore = 0

    for _, player in ipairs(players) do
        local stats = player.seasonStats or {}
        local appearances = stats.appearances or 0
        if appearances < 10 then goto continue end  -- 出场数不足不参选

        -- 综合评分公式：进球×3 + 助攻×2 + 场均评分×5 + 出场数×0.5
        local score = (stats.goals or 0) * 3
            + (stats.assists or 0) * 2
            + (stats.avgRating or 6.0) * 5
            + appearances * 0.5

        -- 位置修正（门将/后卫进球权重更高）
        if player.position == "GK" or player.position == "CB" then
            score = score + (stats.cleanSheets or 0) * 2
        end

        if score > bestScore then
            bestScore = score
            best = player
        end

        ::continue::
    end

    if best then
        return {
            playerId = best.id,
            playerName = best.displayName,
            teamId = best.teamId,
            overall = best.overall,
            score = math.floor(bestScore * 10) / 10,
        }
    end
    return nil
end

------------------------------------------------------
-- 最佳年轻球员（23岁及以下）
------------------------------------------------------

function AwardsManager._findBestYoungPlayer(players, gameState)
    local year = gameState.date.year
    local best = nil
    local bestScore = 0

    for _, player in ipairs(players) do
        local age = player:getAge(year)
        if age > 23 then goto continue end

        local stats = player.seasonStats or {}
        local appearances = stats.appearances or 0
        if appearances < 5 then goto continue end

        local score = (stats.goals or 0) * 3
            + (stats.assists or 0) * 2
            + (stats.avgRating or 6.0) * 4
            + appearances * 0.3
            + (player.actualPotential or player.potential or 50) * 0.1

        if score > bestScore then
            bestScore = score
            best = player
        end

        ::continue::
    end

    if best then
        return {
            playerId = best.id,
            playerName = best.displayName,
            teamId = best.teamId,
            age = best:getAge(year),
            score = math.floor(bestScore * 10) / 10,
        }
    end
    return nil
end

------------------------------------------------------
-- 金手套（门将零封场次最多）
------------------------------------------------------

function AwardsManager._findGoldenGlove(players)
    local best = nil
    local bestCleanSheets = 0

    for _, player in ipairs(players) do
        if player.position ~= "GK" then goto continue end

        local stats = player.seasonStats or {}
        local cleanSheets = stats.cleanSheets or 0
        local appearances = stats.appearances or 0

        if appearances < 10 then goto continue end

        if cleanSheets > bestCleanSheets then
            bestCleanSheets = cleanSheets
            best = player
        end

        ::continue::
    end

    if best then
        return {
            playerId = best.id,
            playerName = best.displayName,
            teamId = best.teamId,
            cleanSheets = bestCleanSheets,
        }
    end
    return nil
end

-- 兼容旧调用
function AwardsManager._findBestGoalkeeper(players)
    return AwardsManager._findGoldenGlove(players)
end

------------------------------------------------------
-- 金球奖（全世界年度最高个人奖项，取前三名）
------------------------------------------------------

local Nationality = require("scripts/domain/nationality")

local BALLON_TROPHY = {
    leagueChampion = 25,
    topFour = 8,
    domesticCup = 12,
    uclChampion = 30,
    uelChampion = 15,
    clubTreble = 20,   -- 联赛 + 欧冠 + 国内杯
    clubDouble = 8,    -- 上述三项中任意两项
    worldCup = 20,
    euroCup = 12,
}

function AwardsManager._buildTeamTrophyMap(gameState)
    local map = {}

    local function ensure(teamId)
        if not map[teamId] then
            map[teamId] = { domesticCups = 0, ucl = false, uel = false }
        end
        return map[teamId]
    end

    for _, cup in pairs(gameState.domesticCups or {}) do
        if cup.winner then
            ensure(cup.winner).domesticCups = ensure(cup.winner).domesticCups + 1
        end
    end

    local ucl = gameState.championsLeague
    local uclWinner = ucl and (ucl.champion or ucl.winner)
    if uclWinner then
        ensure(uclWinner).ucl = true
    end

    local uel = gameState.europaLeague
    local uelWinner = uel and (uel.champion or uel.winner)
    if uelWinner then
        ensure(uelWinner).uel = true
    end

    return map
end

function AwardsManager._ballonClubTrophyBonus(trophy, leagueAchievement)
    local bonus = 0
    if leagueAchievement.champion then
        bonus = bonus + BALLON_TROPHY.leagueChampion
    elseif leagueAchievement.topFour then
        bonus = bonus + BALLON_TROPHY.topFour
    end

    if not trophy then return bonus end

    bonus = bonus + (trophy.domesticCups or 0) * BALLON_TROPHY.domesticCup
    if trophy.ucl then
        bonus = bonus + BALLON_TROPHY.uclChampion
    elseif trophy.uel then
        bonus = bonus + BALLON_TROPHY.uelChampion
    end

    local majorCount = 0
    if leagueAchievement.champion then majorCount = majorCount + 1 end
    if trophy.ucl then majorCount = majorCount + 1 end
    if (trophy.domesticCups or 0) > 0 then majorCount = majorCount + 1 end
    if majorCount >= 3 then
        bonus = bonus + BALLON_TROPHY.clubTreble
    elseif majorCount == 2 then
        bonus = bonus + BALLON_TROPHY.clubDouble
    end

    return bonus
end

function AwardsManager._ballonNationalTrophyBonus(gameState, playerNat)
    local bonus = 0
    local wc = gameState.worldCup
    if wc and wc.champion and Nationality.matches(playerNat, wc.champion) then
        bonus = bonus + BALLON_TROPHY.worldCup
    end
    local euro = gameState.euroCup
    if euro and euro.champion and Nationality.matches(playerNat, euro.champion) then
        bonus = bonus + BALLON_TROPHY.euroCup
    end
    return bonus
end

function AwardsManager._calculateBallonDor(gameState)
    local candidates = {}
    local teamPositions = {}
    local teamTrophies = AwardsManager._buildTeamTrophyMap(gameState)

    for _, lg in pairs(gameState.leagues or {}) do
        local sorted = lg:getSortedStandings()
        for pos, entry in ipairs(sorted or {}) do
            teamPositions[entry.teamId] = {
                position = pos,
                totalTeams = #sorted,
                champion = pos == 1,
                topFour = pos <= 4,
            }
        end
    end

    for _, player in pairs(gameState.players or {}) do
        if player.retired then goto nextPlayer end
        local stats = player.seasonStats or {}
        local appearances = stats.appearances or 0
        if appearances < 15 then goto nextPlayer end

        local team = gameState.teams[player.teamId]
        if not team then goto nextPlayer end

        local goals = stats.goals or 0
        local assists = stats.assists or 0
        local avgRating = stats.avgRating or 0
        local cleanSheets = stats.cleanSheets or 0
        local achievement = teamPositions[player.teamId] or {}
        local trophy = teamTrophies[player.teamId]

        local score = goals * 3
            + assists * 3
            + avgRating * 8
            + appearances * 0.6
            + (player.reputation or 0) * 0.2
            + (player.overall or 0) * 0.15

        if player.position == "GK" or player.position == "CB" or player.position == "LB" or player.position == "RB" then
            score = score + cleanSheets * 3
        end

        local clubBonus = AwardsManager._ballonClubTrophyBonus(trophy, achievement)
        local nationalBonus = AwardsManager._ballonNationalTrophyBonus(gameState, player.nationality)
        score = score + clubBonus + nationalBonus

        table.insert(candidates, {
            playerId = player.id,
            playerName = player.displayName,
            teamId = player.teamId,
            teamName = team.name,
            position = player.position,
            goals = goals,
            assists = assists,
            appearances = appearances,
            avgRating = avgRating,
            cleanSheets = cleanSheets,
            overall = player.overall,
            reputation = player.reputation,
            trophyBonus = clubBonus + nationalBonus,
            score = math.floor(score * 10) / 10,
            season = gameState.season,
        })

        ::nextPlayer::
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if (a.trophyBonus or 0) ~= (b.trophyBonus or 0) then return (a.trophyBonus or 0) > (b.trophyBonus or 0) end
        if (a.avgRating or 0) ~= (b.avgRating or 0) then return (a.avgRating or 0) > (b.avgRating or 0) end
        return (a.goals or 0) > (b.goals or 0)
    end)

    local top3 = {}
    for i = 1, math.min(3, #candidates) do
        top3[i] = candidates[i]
    end
    return top3
end

------------------------------------------------------
-- 最佳经理（排名超预期最多）
------------------------------------------------------

function AwardsManager._calculateBestManager(gameState)
    local best = nil
    local bestDelta = -999

    for _, lg in pairs(gameState.leagues) do
        local sorted = lg:getSortedStandings()
        local totalTeams = #sorted

        for i, entry in ipairs(sorted) do
            local team = gameState.teams[entry.teamId]
            if not team then goto continue end

            -- 预期排名基于赛季前声望
            local reputation = team.reputation or 50
            -- 声望越高预期排名越高（数字越小）
            local expectedPosition = math.max(1, math.floor(totalTeams * (1 - reputation / 100) + 0.5))
            local actualPosition = i

            -- delta = 预期 - 实际（正值 = 超预期）
            local delta = expectedPosition - actualPosition

            if delta > bestDelta then
                bestDelta = delta
                local manager = team.managerId and gameState.managers and gameState.managers[team.managerId] or nil
                local managerName = manager and manager.displayName or team.name
                best = {
                    teamId = entry.teamId,
                    teamName = team.name,
                    managerId = team.managerId,
                    managerName = managerName,
                    name = managerName,
                    leagueName = lg.name,
                    expectedPosition = expectedPosition,
                    actualPosition = actualPosition,
                    overPerformance = delta,
                }
            end

            ::continue::
        end
    end

    return best
end

------------------------------------------------------
-- 公告新闻
------------------------------------------------------

function AwardsManager._announceAwards(gameState, leagueName, leagueAwards)
    local lines = {}
    local relatedPlayers = {}
    local function addRelatedPlayer(data)
        if data and data.playerId then
            table.insert(relatedPlayers, data.playerId)
        end
    end

    if leagueAwards.goldenBoot then
        local gb = leagueAwards.goldenBoot
        local team = gameState.teams[gb.teamId]
        table.insert(lines, string.format("金靴奖: %s（%s）- %d球",
            gb.playerName, team and team.name or "?", gb.goals))
        addRelatedPlayer(gb)
    end

    if leagueAwards.bestPlayer then
        local bp = leagueAwards.bestPlayer
        local team = gameState.teams[bp.teamId]
        table.insert(lines, string.format("最佳球员: %s（%s）",
            bp.playerName, team and team.name or "?"))
        addRelatedPlayer(bp)
    end

    if leagueAwards.bestYoungPlayer then
        local byp = leagueAwards.bestYoungPlayer
        local team = gameState.teams[byp.teamId]
        table.insert(lines, string.format("最佳年轻球员: %s（%s，%d岁）",
            byp.playerName, team and team.name or "?", byp.age))
        addRelatedPlayer(byp)
    end

    if leagueAwards.topAssists then
        local ta = leagueAwards.topAssists
        local team = gameState.teams[ta.teamId]
        table.insert(lines, string.format("最佳助攻: %s（%s）- %d次助攻",
            ta.playerName, team and team.name or "?", ta.assists))
        addRelatedPlayer(ta)
    end

    local goldenGlove = leagueAwards.goldenGlove or leagueAwards.bestGoalkeeper
    if goldenGlove then
        local bgk = goldenGlove
        local team = gameState.teams[bgk.teamId]
        table.insert(lines, string.format("金手套奖: %s（%s）- %d次零封",
            bgk.playerName, team and team.name or "?", bgk.cleanSheets))
        addRelatedPlayer(bgk)
    end

    if #lines > 0 then
        gameState:addNews({
            category = "season_news",
            title = string.format("%s 赛季奖项揭晓", leagueName),
            body = table.concat(lines, "\n"),
            relatedPlayers = relatedPlayers,
        })
    end
end

------------------------------------------------------
-- 通知玩家获奖
------------------------------------------------------

function AwardsManager._notifyPlayerAwards(gameState, awards)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    local playerAwards = {}

    for _, leagueAwards in pairs(awards.leagues) do
        if leagueAwards.goldenBoot and leagueAwards.goldenBoot.teamId == playerTeamId then
            table.insert(playerAwards, "金靴奖: " .. leagueAwards.goldenBoot.playerName)
        end
        if leagueAwards.bestPlayer and leagueAwards.bestPlayer.teamId == playerTeamId then
            table.insert(playerAwards, "最佳球员: " .. leagueAwards.bestPlayer.playerName)
        end
        if leagueAwards.bestYoungPlayer and leagueAwards.bestYoungPlayer.teamId == playerTeamId then
            table.insert(playerAwards, "最佳年轻球员: " .. leagueAwards.bestYoungPlayer.playerName)
        end
        if leagueAwards.topAssists and leagueAwards.topAssists.teamId == playerTeamId then
            table.insert(playerAwards, "最佳助攻: " .. leagueAwards.topAssists.playerName)
        end
        local goldenGlove = leagueAwards.goldenGlove or leagueAwards.bestGoalkeeper
        if goldenGlove and goldenGlove.teamId == playerTeamId then
            table.insert(playerAwards, "金手套奖: " .. goldenGlove.playerName)
        end
    end

    if awards.ballonDor and awards.ballonDor[1] and awards.ballonDor[1].teamId == playerTeamId then
        table.insert(playerAwards, "金球奖: " .. awards.ballonDor[1].playerName)
    end

    -- 最佳经理
    if awards.bestManager and awards.bestManager.teamId == playerTeamId then
        table.insert(playerAwards, "最佳经理（你！）")
    end

    if #playerAwards > 0 then
        gameState:sendMessage({
            category = "system",
            title = "恭喜！球队球员获得赛季奖项",
            body = "你的球队中有球员获得了本赛季的个人奖项：\n\n" .. table.concat(playerAwards, "\n"),
            priority = "high",
        })
    end
end

-- 查询接口：奖项数据的权威来源是 gameState.worldHistory[].awards
-- （见 HistoryManager.getSeasonHistory / getWorldHistory），本模块不再提供
-- 基于 _seasonAwards 的查询 API，避免读档后返回空结果的陷阱。

return AwardsManager
