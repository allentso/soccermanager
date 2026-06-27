-- systems/season_manager.lua
-- 赛季循环管理 - 赛季结算、奖金发放、球员成长、新赛季初始化

local Constants = require("scripts/app/constants")
local League = require("scripts/domain/league")
local EventBus = require("scripts/app/event_bus")
local ChampionsLeague = require("scripts/systems/champions_league")
local WorldCup = require("scripts/systems/world_cup")
local EuroCup = require("scripts/systems/euro_cup")
local AwardsManager = require("scripts/systems/awards_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local HistoryManager = require("scripts/systems/history_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local RecordsManager = require("scripts/systems/records_manager")
local PotentialSystem = require("scripts/systems/potential_system")
local TrainingManager = require("scripts/systems/training_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local ReincarnationManager = require("scripts/systems/reincarnation_manager")
local DomesticCup = require("scripts/systems/domestic_cup")
local RealDataLoader = require("scripts/data/real_data_loader")

local SeasonManager = {}

local function _dateSerial(date)
    if not date then return 0 end
    return (tonumber(date.year) or 0) * 365
        + (tonumber(date.month) or 0) * 30
        + (tonumber(date.day) or 0)
end

--- 安全网：确保仍在任的玩家球队属于一个顶级联赛，且新赛季有国内联赛赛程。
--- 过去类似逻辑只在设置/诊断页触发；放到核心层避免首页只找到欧冠/国际赛。
---@param gameState table
---@return boolean fixed
function SeasonManager.ensurePlayerLeagueIntegrity(gameState)
    if not gameState or not gameState.playerTeamId or not gameState.leagues then return false end

    local playerTeamId = gameState.playerTeamId
    local foundLeague, foundLeagueKey
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds or {}) do
            if tid == playerTeamId then
                foundLeague = lg
                foundLeagueKey = leagueKey
                break
            end
        end
        if foundLeague then break end
    end

    local fixed = false
    if not foundLeague then
        foundLeagueKey = gameState.playerLeagueId
        foundLeague = foundLeagueKey and gameState.leagues[foundLeagueKey] or nil
        if not foundLeague then
            foundLeague = gameState.league
            for leagueKey, lg in pairs(gameState.leagues or {}) do
                if lg == foundLeague then
                    foundLeagueKey = leagueKey
                    break
                end
            end
        end
        if not foundLeague then
            for leagueKey, lg in pairs(gameState.leagues or {}) do
                foundLeague = lg
                foundLeagueKey = leagueKey
                break
            end
        end

        if foundLeague then
            foundLeague.teamIds = foundLeague.teamIds or {}
            table.insert(foundLeague.teamIds, playerTeamId)
            fixed = true

            -- 若异常状态里玩家队还残留在二级储备池，移除避免下次升降级重复处理。
            for _, sd in pairs(gameState.secondDivision or {}) do
                for i = #(sd.teamIds or {}), 1, -1 do
                    if sd.teamIds[i] == playerTeamId then
                        table.remove(sd.teamIds, i)
                    end
                end
            end
        end
    end

    if not foundLeague then return fixed end

    gameState.league = foundLeague
    gameState.playerLeagueId = foundLeagueKey or gameState.playerLeagueId

    local seasonStart = {
        year = gameState.season or (gameState.date and gameState.date.year) or 2026,
        month = Constants.SEASON_START_MONTH,
        day = Constants.SEASON_START_DAY,
    }
    local currentSerial = _dateSerial(gameState.date)
    local seasonStartSerial = _dateSerial(seasonStart)

    local hasAnyPlayerFixture = false
    local hasScheduledPlayerFixture = false
    for _, f in ipairs(foundLeague.fixtures or {}) do
        if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
            hasAnyPlayerFixture = true
            if f.status == "scheduled" then
                hasScheduledPlayerFixture = true
                break
            end
        end
    end

    local shouldRebuildFixtures = fixed
        or not foundLeague.fixtures
        or #foundLeague.fixtures == 0
        or not hasAnyPlayerFixture
        or (not hasScheduledPlayerFixture and currentSerial <= seasonStartSerial)

    if shouldRebuildFixtures then
        foundLeague:initStandings()
        foundLeague.season = gameState.season
        foundLeague.currentRound = 1
        foundLeague:generateFixtures(seasonStart)
        fixed = true
    elseif foundLeague.standings and not foundLeague.standings[playerTeamId] then
        foundLeague.standings[playerTeamId] = {
            teamId = playerTeamId,
            played = 0,
            wins = 0,
            draws = 0,
            losses = 0,
            goalsFor = 0,
            goalsAgainst = 0,
            goalDifference = 0,
            points = 0,
        }
        fixed = true
    end

    if fixed then
        gameState.pendingPlayerFixture = nil
        gameState._leagueFixtureDateIndex = nil
        gameState._cachedNextMatch = nil
    end
    return fixed
end

------------------------------------------------------
-- 赛季结束处理（当玩家所在联赛赛季完成时触发，处理所有联赛）
------------------------------------------------------

function SeasonManager.endSeason(gameState)
    if not gameState.league then
        gameState._seasonEndProcessing = nil
        return
    end

    -- 用 pcall 保护赛季结算步骤，确保 _startNewSeason 一定执行
    local awards = nil
    local ok, err = pcall(function()
        -- 0. 赛季目标评估（必须在奖金/升降级之前，基于最终排名）
        ObjectivesManager.onSeasonEnd(gameState)

        -- 0.3 赛季排名声望奖励（必须在董事会评估之前，使声望反映真实成绩）
        local ReputationManager = require("scripts/systems/reputation_manager")
        ReputationManager.seasonEndUpdate(gameState)

        -- 0.4 经理冠军统计更新（联赛冠军 +1 trophies）
        if gameState.playerTeamId then
            local playerLeague = nil
            for _, lg in pairs(gameState.leagues or {}) do
                for _, tid in ipairs(lg.teamIds or {}) do
                    if tid == gameState.playerTeamId then
                        playerLeague = lg
                        break
                    end
                end
                if playerLeague then break end
            end
            if playerLeague then
                local pos = playerLeague:getTeamPosition(gameState.playerTeamId)
                if pos == 1 then
                    local mgr = gameState:getPlayerManager()
                    if mgr and mgr.stats then
                        mgr.stats.trophies = (mgr.stats.trophies or 0) + 1
                    end
                end
            end
        end

        -- 0.5 董事会赛季末评估（所有球队，可能触发解雇）
        local BoardManager = require("scripts/systems/board_manager")
        BoardManager.seasonEndEvaluation(gameState)

        -- 1. 为所有联赛发放赛季奖金
        SeasonManager._distributeSeasonPrizes(gameState)

        -- 1.2 赞助合同绩效条款结算（前3名奖金/降级罚款）
        if gameState.league and gameState.playerTeamId then
            local playerPosition = gameState.league:getTeamPosition(gameState.playerTeamId)
            local totalTeams = #gameState.league.teamIds
            if playerPosition and totalTeams > 0 then
                FinanceManager.settleSponsorPerformanceClauses(gameState, playerPosition, totalTeams)
            end
        end

        -- 1.5 升降级处理（必须在新赛季初始化之前）
        SeasonManager._processPromotionRelegation(gameState)

        -- 2. B3: 赛季奖项计算（在球员成长之前，基于本赛季数据）
        awards = AwardsManager.processSeasonAwards(gameState)

        -- 3. 球员成长/退化（全局）
        SeasonManager._processPlayerDevelopment(gameState)

        -- 3.5 赛季末薪资审查（成长后重估合同）
        local ContractManager = require("scripts/systems/contract_manager")
        ContractManager.processSeasonWageReview(gameState)

        -- 4. B3: 重新计算所有球员特性（成长后）
        SeasonManager._recalculateTraits(gameState)

        -- 5. 合同到期处理（全局）
        SeasonManager._processContractExpiry(gameState)

        -- 6. 球员退役（全局）
        SeasonManager._processRetirements(gameState)

        -- 6.1. 转生机制：退役传奇球员以青训新星身份重生
        ReincarnationManager.processReincarnations(gameState)

        -- 6.5. 记录球员职业历史（必须在重置统计之前）
        SeasonManager._recordPlayerCareerHistory(gameState)

        -- 6.6. 记录系统：赛季记录检查（必须在重置统计之前）
        RecordsManager.onSeasonEnd(gameState)

        -- 8. 记录赛季完整历史（含奖项、财务快照；必须在 reset 之前）
        -- 注意：曾经这里还会调用 _recordSeasonHistory 再写一条"旧格式"记录，
        -- 导致 worldHistory 每赛季出现两条重复数据（存档膨胀 + 历史页重复）。
        -- recordSeasonEnd 的记录是其超集，旧调用已移除；
        -- 老存档中的重复记录由 Housekeeping.dedupeWorldHistory 在读档时合并。
        HistoryManager.recordSeasonEnd(gameState, awards)

        -- 7. 重置赛季统计（全局）
        SeasonManager._resetSeasonStats(gameState)

        -- 7.5 重置赛季财务统计（seasonIncome/seasonExpense 归零）
        FinanceManager.resetSeasonFinance(gameState)
    end)

    if not ok then
        print("[SeasonManager] ERROR in endSeason pre-steps: " .. tostring(err))
    end

    -- 10. 初始化新赛季（所有联赛）—— 无论上面是否出错都必须执行
    local ok2, err2 = pcall(SeasonManager._startNewSeason, gameState)
    if not ok2 then
        print("[SeasonManager] CRITICAL ERROR in _startNewSeason: " .. tostring(err2))
    end

    -- 清除 guard 标志，允许下个赛季再次触发
    gameState._seasonEndProcessing = nil

    -- 通知
    gameState:sendMessage({
        category = "league",
        title = "新赛季开始!",
        body = string.format("%d-%d 赛季已经开始！祝你好运。", gameState.season, gameState.season + 1),
        priority = "normal",
    })

    EventBus.emit("new_season_started", gameState.season)
end

------------------------------------------------------
-- 赛季奖金（为所有联赛发放）
------------------------------------------------------

function SeasonManager._distributeSeasonPrizes(gameState)
    local prizes = Constants.SEASON_END_PRIZE

    for leagueKey, lg in pairs(gameState.leagues) do
        local sorted = lg:getSortedStandings()

        for i, entry in ipairs(sorted) do
            local team = gameState.teams[entry.teamId]
            if team then
                -- 使用 FinanceManager 统一处理：更新 balance、transferBudget、seasonIncome、incomeBreakdown、流水
                FinanceManager.awardSeasonPrize(gameState, entry.teamId, i)
            end
        end

        -- 为每个联赛生成冠军新闻
        local champion = sorted[1] and gameState.teams[sorted[1].teamId]
        if champion then
            gameState:addNews({
                category = "season_news",
                title = string.format("%d赛季%s冠军: %s!", gameState.season, lg.name, champion.name),
                body = string.format("%s 以 %d 分的成绩赢得%s冠军！\n" ..
                    "1. %s - %d分\n2. %s - %d分\n3. %s - %d分",
                    champion.name, sorted[1].points, lg.name,
                    gameState.teams[sorted[1].teamId] and gameState.teams[sorted[1].teamId].name or "?", sorted[1].points,
                    sorted[2] and gameState.teams[sorted[2].teamId] and gameState.teams[sorted[2].teamId].name or "?", sorted[2] and sorted[2].points or 0,
                    sorted[3] and gameState.teams[sorted[3].teamId] and gameState.teams[sorted[3].teamId].name or "?", sorted[3] and sorted[3].points or 0
                ),
            })
        end
    end

    -- 玩家联赛奖金通知
    if gameState.league and gameState.playerTeamId then
        local playerPosition = gameState.league:getTeamPosition(gameState.playerTeamId)
        local playerPrize = prizes[playerPosition] or 100000
        local team = gameState:getPlayerTeam()
        if team then
            if playerPosition == 1 then
                -- 联赛冠军特殊庆祝
                local championBonus = 20000000  -- 额外夺冠奖金 20M
                team.balance = team.balance + championBonus
                team.transferBudget = (team.transferBudget or 0) + championBonus
                team.seasonIncome = (team.seasonIncome or 0) + championBonus
                team.incomeBreakdown = team.incomeBreakdown or {}
                team.incomeBreakdown.prize = (team.incomeBreakdown.prize or 0) + championBonus
                FinanceManager.addTransaction(team, {
                    amount = championBonus,
                    description = gameState.league.name .. "冠军奖金",
                    category = "prize",
                    season = gameState.season,
                    week = FinanceManager._getWeekNumber(gameState),
                })

                gameState:sendMessage({
                    category = "achievement",
                    title = "联赛冠军！",
                    body = string.format(
                        "恭喜！你的球队赢得了 %d赛季 %s 冠军！\n\n" ..
                        "这是对整个赛季努力的最佳回报！\n" ..
                        "赛季奖金: %.1fM\n冠军奖金: %.1fM\n当前余额: %.1fM",
                        gameState.season, gameState.league.name,
                        playerPrize / 1000000, championBonus / 1000000, team.balance / 1000000),
                    priority = "high",
                })
            elseif playerPosition == 2 then
                -- 亚军
                gameState:sendMessage({
                    category = "finance",
                    title = "联赛亚军",
                    body = string.format("赛季结束！球队获得%s亚军，距冠军仅一步之遥。\n赛季奖金 %.1fM 已到账。\n当前余额: %.1fM",
                        gameState.league.name, playerPrize / 1000000, team.balance / 1000000),
                    priority = "normal",
                })
            elseif playerPosition == 3 then
                -- 季军
                gameState:sendMessage({
                    category = "finance",
                    title = "联赛季军",
                    body = string.format("赛季结束！球队获得%s第3名，表现出色。\n赛季奖金 %.1fM 已到账。\n当前余额: %.1fM",
                        gameState.league.name, playerPrize / 1000000, team.balance / 1000000),
                    priority = "normal",
                })
            else
                gameState:sendMessage({
                    category = "finance",
                    title = "赛季奖金到账",
                    body = string.format("赛季结束！球队获得%s第%d名。\n赛季奖金 %.1fM 已到账。\n当前余额: %.1fM",
                        gameState.league.name, playerPosition, playerPrize / 1000000, team.balance / 1000000),
                    priority = "normal",
                })
            end
        end
    end
end

------------------------------------------------------
-- B3: 重新计算所有球员特性
------------------------------------------------------

function SeasonManager._recalculateTraits(gameState)
    local Player = require("scripts/domain/player")
    for _, player in pairs(gameState.players) do
        if not player.retired and player.calculateTraits then
            player:calculateTraits(gameState.date.year)
        end
    end
end

------------------------------------------------------
-- 球员成长/退化
------------------------------------------------------

function SeasonManager._processPlayerDevelopment(gameState)
    local seasonStartYear = TrainingManager.getSeasonStartYear(gameState)
    local trainingMods = DifficultySettings.getTrainingModifiers()
    local growthCfg = trainingMods.seasonEndGrowth or {}
    local declineCfg = trainingMods.decline or { mid = 0.20, late = 0.40 }

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end

        local age = player:getAge(gameState.date.year)
        local seasonAge = TrainingManager.getSeasonAge(player, seasonStartYear)
        local growthChance = 0
        local declineChance = 0

        if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then
            growthChance = growthCfg.u21 or Constants.U21_SEASON_END_GROWTH_CHANCE
        elseif age <= 24 then
            growthChance = growthCfg.youngAdult or 0.35
        elseif age <= Constants.AGE_PEAK_END then
            growthChance = growthCfg.peak or 0.10
        elseif age >= Constants.AGE_DECLINE_MID_START and age <= Constants.AGE_DECLINE_MID_END then
            declineChance = declineCfg.mid or 0.20
        else
            declineChance = declineCfg.late or 0.40
        end

        if growthChance > 0 and seasonAge > Constants.YOUTH_PHASE_MAX_AGE then
            growthChance = growthChance * TrainingManager.getParticipationFactor(player, seasonStartYear)
        end

        if declineChance > 0 and player.teamId then
            local team = gameState.teams[player.teamId]
            if team then
                local TransferManager = require("scripts/systems/transfer_manager")
                if TransferManager._isAIProtectedCore(gameState, team, player) then
                    declineChance = declineChance * 0.35
                end
            end
        end

        local attrNames = {"speed", "stamina", "strength", "agility", "passing",
            "shooting", "tackling", "dribbling", "defending", "positioning",
            "vision", "decisions", "composure", "aggression", "teamwork",
            "leadership", "aerial", "handling", "reflexes"}

        for _, attr in ipairs(attrNames) do
            if growthChance > 0 and Random() < growthChance then
                local attrCap = player:getAttrCap()
                if player.attributes[attr] and player.attributes[attr] < attrCap then
                    player.attributes[attr] = player.attributes[attr] + 1
                end
            elseif declineChance > 0 and Random() < declineChance then
                if player.attributes[attr] and player.attributes[attr] > 1 then
                    if (attr == "speed" or attr == "stamina" or attr == "agility") and Random() < 0.3 then
                        player.attributes[attr] = math.max(1, player.attributes[attr] - 2)
                    else
                        player.attributes[attr] = player.attributes[attr] - 1
                    end
                end
            end
        end

        player:calculateOverall()
        if player.teamId then
            local team = gameState.teams[player.teamId]
            local teamRep = team and team.reputation or 300
            player:calculateReputation(teamRep)
        end
        player:calculateValue(gameState.date.year)

        ::continue::
    end
end

------------------------------------------------------
-- 合同到期
------------------------------------------------------

local function _teamAvgOverall(gameState, team)
    if not team then return 50 end
    local total, count = 0, 0
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.retired then
            total = total + (p.overall or 50)
            count = count + 1
        end
    end
    return count > 0 and (total / count) or 50
end

function SeasonManager._processContractExpiry(gameState)
    local expiredPlayers = {}

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end
        if player.contractEnd then
            -- 必须同时比较年份和月份：合同到6月才到期，赛季5月结束时不应视为到期
            local cy = player.contractEnd.year
            local cm = player.contractEnd.month or 6
            local gy = gameState.date.year
            local gm = gameState.date.month or 6
            if cy < gy or (cy == gy and cm <= gm) then
                -- 合同到期
                table.insert(expiredPlayers, player)
            end
        end
        ::continue::
    end

    for _, player in ipairs(expiredPlayers) do
        local team = gameState.teams[player.teamId]

        -- AI球队自动续约大部分球员
        if player.teamId ~= gameState.playerTeamId then
            local renewChance = 0.7
            if team then
                local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
                local teamAvg = _teamAvgOverall(gameState, team)
                local targetSize = AiSquadPolicy.getTargetSquadSize(team)
                local teamSize = #team.playerIds
                if teamSize <= targetSize then
                    renewChance = renewChance + 0.15
                end
                if AiSquadPolicy.hasPositionShortage(gameState, team) then
                    renewChance = renewChance + 0.15
                end
                local repMin = AiSquadPolicy.getRepMinOvr(team, "fill")
                if (team.reputation or 0) >= 800 and (player.overall or 0) >= repMin - 6 then
                    renewChance = renewChance + 0.10
                end
                if player.squadRole == "key"
                    or (player.overall or 0) >= teamAvg + 5 then
                    renewChance = 0.95
                end
                renewChance = math.min(0.98, renewChance)
            end
            if Random() < renewChance then
                player.contractEnd = {year = gameState.date.year + RandomInt(1, 3), month = 6}
                local marketWage = FinanceManager.estimateMarketWage(player, team, gameState)
                player.wage = math.max(player.wage or 0, math.floor(marketWage * 0.88 / 100) * 100)
                player:calculateValue(gameState.date.year)
            else
                -- 释放球员
                if team then
                    for i, pid in ipairs(team.playerIds) do
                        if pid == player.id then
                            table.remove(team.playerIds, i)
                            break
                        end
                    end
                end
                player.teamId = nil
                player.contractEnd = nil
                player:calculateValue(gameState.date.year)
            end
        else
            -- 玩家球队球员合同到期：按市场工资重估后续约
            local marketWage = FinanceManager.estimateMarketWage(player, team, gameState)
            local newWage = math.max(player.wage or 0, math.floor(marketWage * 0.90 / 100) * 100)
            player.wage = newWage
            player.contractEnd = {year = gameState.date.year + 1, month = 6}
            player:calculateValue(gameState.date.year)
            gameState:sendMessage({
                category = "contract",
                title = "合同自动续约",
                body = string.format("%s 的合同已到期，已按市场水平自动续约1年（周薪 %s）。",
                    player.displayName, FinanceManager.formatMoney(newWage)),
                priority = "normal",
            })
        end
    end
end

------------------------------------------------------
-- 退役处理
------------------------------------------------------

function SeasonManager._processRetirements(gameState)
    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end

        local age = player:getAge(gameState.date.year + 1)  -- 下赛季的年龄
        if age >= Constants.RETIREMENT_MIN_AGE then
            -- 年龄越大退役概率越高
            local retireChance = (age - Constants.RETIREMENT_MIN_AGE + 1) * 0.15
            if Random() < retireChance then
                player.retired = true
                -- 记录退役赛季：Housekeeping 会在下一赛季物理删除（保留一季供总结页展示）
                player.retiredSeason = gameState.season
                -- 从球队中移除
                local team = gameState.teams[player.teamId]
                if team then
                    for i, pid in ipairs(team.playerIds) do
                        if pid == player.id then
                            table.remove(team.playerIds, i)
                            break
                        end
                    end
                end

                -- 如果是玩家球队的
                if player.teamId == gameState.playerTeamId then
                    gameState:sendMessage({
                        category = "system",
                        title = "球员退役",
                        body = string.format("%s 宣布退役。感谢他为球队做出的贡献！", player.displayName),
                        priority = "normal",
                    })
                end

                player.teamId = nil
            end
        end
        ::continue::
    end

    local AIManager = require("scripts/systems/ai_manager")
    AIManager.ensureAllTargetSquads(gameState)
end

------------------------------------------------------
-- 记录球员职业历史（每赛季结算时调用，在重置统计之前）
------------------------------------------------------

function SeasonManager._recordPlayerCareerHistory(gameState)
    local season = gameState.season or 1

    for _, player in pairs(gameState.players) do
        local stats = player.seasonStats
        if not stats then goto continue_player end

        -- 只记录有出场的赛季；无出场的 AI 球员不记录
        -- （此前"有合同就记录"导致几千名 AI 青训/替补每季产生全零记录，存档膨胀）
        local apps = stats.appearances or 0
        if apps == 0 and player.teamId ~= gameState.playerTeamId then goto continue_player end

        local record = {
            season = season,
            teamId = player.teamId,
            age = player.birthYear and (gameState.date.year - player.birthYear) or nil,
            overall = player.overall,
            squadRole = player.squadRole,
            appearances = apps,
            goals = stats.goals or 0,
            assists = stats.assists or 0,
            avgRating = stats.avgRating or 0,
            yellowCards = stats.yellowCards or 0,
            redCards = stats.redCards or 0,
            cleanSheets = stats.cleanSheets or 0,
        }

        table.insert(player.careerHistory, record)

        ::continue_player::
    end
end

------------------------------------------------------
-- 重置赛季统计（全局）
------------------------------------------------------

function SeasonManager._resetSeasonStats(gameState)
    for _, player in pairs(gameState.players) do
        player.seasonStats = {
            appearances = 0,
            goals = 0,
            assists = 0,
            yellowCards = 0,
            redCards = 0,
            avgRating = 0,
            cleanSheets = 0,
        }
        player._benchCount = nil
    end

    -- 重置球队近期状态 + 赛季统计 + 财务恢复计数器
    local FinanceManager = require("scripts/systems/finance_manager")
    for _, team in pairs(gameState.teams) do
        team.recentForm = {}
        team.monthlyStats = nil
        team._lastMonthlyStats = nil
        team.seasonStats = {
            wins = 0, draws = 0, losses = 0,
            goalsFor = 0, goalsAgainst = 0,
        }
        FinanceManager.resetRecoveryCounters(team)
    end
end

------------------------------------------------------
-- 记录赛季历史（所有联赛）
------------------------------------------------------

-- （已移除）_recordSeasonHistory：与 HistoryManager.recordSeasonEnd 重复写 worldHistory，
-- 造成存档每赛季膨胀一份完整排名。历史重复数据由 Housekeeping.dedupeWorldHistory 清理。

------------------------------------------------------
-- 升降级系统
------------------------------------------------------

-- 升降级配置：每个联赛的降级名额
local RELEGATION_SPOTS = 3   -- 倒数3名降级
local PROMOTION_SPOTS = 3    -- 前3名升级

-- 二级联赛名称映射
local SECOND_DIVISION_NAMES = {
    EPL = "英冠",
    LaLiga = "西乙",
    SerieA = "意乙",
    Bundesliga = "德乙",
    Ligue1 = "法乙",
    CSL = "中甲",
}

local LEAGUE_COUNTRIES = {
    EPL = "ENG",
    LaLiga = "ES",
    SerieA = "IT",
    Bundesliga = "DE",
    Ligue1 = "FR",
    CSL = "CHN",
}

local function _getLeagueCountry(leagueKey, league)
    return LEAGUE_COUNTRIES[leagueKey] or (league and league.country) or "ENG"
end

--- 补模拟联赛中尚未完成的比赛（升降级前确保积分榜最终化）
function SeasonManager._simulateRemainingLeagueFixtures(gameState, lg)
    if not lg or lg:isSeasonComplete() then return end
    local MatchEngine = require("scripts/match/match_engine")
    for _, fixture in ipairs(lg.fixtures or {}) do
        if fixture.status == "scheduled" then
            local report = MatchEngine.simulate(gameState, fixture)
            if report then
                MatchEngine.applyResult(gameState, fixture, report)
            end
        end
    end
end

--- 处理所有联赛的升降级
function SeasonManager._processPromotionRelegation(gameState)
    local RealDataLoader = require("scripts/data/real_data_loader")
    local JobManager = require("scripts/systems/job_manager")
    local usesLegacySecondPool = not RealDataLoader.areSecondDivisionsLoaded(gameState)

    -- 仅未加载真实次级联赛时使用旧版抽象储备池
    if usesLegacySecondPool and not gameState.secondDivision then
        gameState.secondDivision = {}
    end

    local promotionNews = {}

    for leagueKey, lg in pairs(gameState.leagues) do
        if (lg.tier or 1) >= 2 or lg.parentLeague then goto continue_league end
        if RealDataLoader.NO_PROMOTION_LEAGUES[leagueKey] then goto continue_league end

        local sorted = lg:getSortedStandings()
        local totalTeams = #sorted
        if totalTeams < 6 then goto continue_league end

        local childKey = RealDataLoader.getChildLeagueKey(leagueKey)
        local childLg = childKey and gameState.leagues[childKey]
        local useFullSecondDiv = childLg ~= nil

        local secondDiv
        if useFullSecondDiv then
            secondDiv = childLg
            -- 玩家顶级联赛先结束时，次级联赛可能还有未赛场次
            SeasonManager._simulateRemainingLeagueFixtures(gameState, childLg)
            if not lg:isSeasonComplete() then
                SeasonManager._simulateRemainingLeagueFixtures(gameState, lg)
            end
        else
            if not gameState.secondDivision[leagueKey] then
                SeasonManager._initSecondDivision(gameState, leagueKey, lg)
            else
                SeasonManager._repairSecondDivisionTeamCountries(gameState, leagueKey, lg)
            end
            secondDiv = gameState.secondDivision[leagueKey]
        end

        local relegatedTeams = {}
        for i = totalTeams - RELEGATION_SPOTS + 1, totalTeams do
            if sorted[i] then
                local tid = sorted[i].teamId
                if tid == gameState.playerTeamId and gameState._cheatAutoPlay then
                    -- 作弊跳赛季时不允许玩家球队降级
                else
                    table.insert(relegatedTeams, tid)
                end
            end
        end

        local promotedTeams = {}
        local secondSorted = useFullSecondDiv
            and childLg:getSortedStandings()
            or SeasonManager._getSecondDivSorted(secondDiv)
        for i = 1, math.min(PROMOTION_SPOTS, #secondSorted) do
            table.insert(promotedTeams, secondSorted[i].teamId)
        end

        if not useFullSecondDiv then
            while #promotedTeams < RELEGATION_SPOTS do
                local newTeam = SeasonManager._generatePromotionTeam(gameState, leagueKey, _getLeagueCountry(leagueKey, lg))
                table.insert(promotedTeams, newTeam.id)
                table.insert(secondDiv.teamIds, newTeam.id)
            end
        end

        -- 升降级人数必须对等，避免联赛球队数漂移
        local swapCount = math.min(#relegatedTeams, #promotedTeams)
        while #relegatedTeams > swapCount do
            table.remove(relegatedTeams)
        end
        while #promotedTeams > swapCount do
            table.remove(promotedTeams)
        end

        local secondDivName = useFullSecondDiv
            and childLg.name
            or (SECOND_DIVISION_NAMES[leagueKey] or "二级联赛")

        for _, teamId in ipairs(relegatedTeams) do
            SeasonManager._removeTeamFromLeagueList(lg.teamIds, teamId)
            table.insert(secondDiv.teamIds, teamId)

            local team = gameState.teams[teamId]
            local teamName = team and team.name or "未知球队"

            if teamId == gameState.playerTeamId then
                if useFullSecondDiv then
                    JobManager.handleRelegationToSecondTier(gameState, teamId, childKey, secondDivName)
                else
                    gameState:sendMessage({
                        category = "league",
                        title = "球队降级!",
                        body = string.format("非常遗憾，%s 排名联赛倒数，下赛季将降级至%s。",
                            teamName, secondDivName),
                        priority = "critical",
                    })
                    JobManager.handleRelegation(gameState, teamId, secondDivName)
                end
            end

            table.insert(promotionNews, {
                type = "relegated",
                teamId = teamId,
                teamName = teamName,
                leagueKey = leagueKey,
            })
        end

        for _, teamId in ipairs(promotedTeams) do
            SeasonManager._removeTeamFromLeagueList(secondDiv.teamIds, teamId)
            table.insert(lg.teamIds, teamId)

            local team = gameState.teams[teamId]
            local teamName = team and team.name or "未知球队"
            if team then
                team._promotedThisSeason = true
            end

            if teamId == gameState.playerTeamId then
                gameState:sendMessage({
                    category = "league",
                    title = "球队升级!",
                    body = string.format("恭喜！%s 赢得%s冠军，下赛季将升级至%s！",
                        teamName, secondDivName, lg.name),
                    priority = "critical",
                })
            end

            table.insert(promotionNews, {
                type = "promoted",
                teamId = teamId,
                teamName = teamName,
                leagueKey = leagueKey,
            })
        end

        if not useFullSecondDiv then
            SeasonManager._simulateSecondDivision(gameState, leagueKey, secondDiv)
        end

        ::continue_league::
    end

    gameState.lastPromotionRelegation = promotionNews

    if gameState.playerTeamId then
        for leagueKey, lg in pairs(gameState.leagues) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == gameState.playerTeamId then
                    gameState.league = lg
                    gameState.playerLeagueId = leagueKey
                    goto league_updated
                end
            end
        end
        ::league_updated::
    end

    if #promotionNews > 0 then
        SeasonManager._generatePromotionRelegationNews(gameState, promotionNews)
    end
end

function SeasonManager._removeTeamFromLeagueList(teamIds, teamId)
    for i, tid in ipairs(teamIds) do
        if tid == teamId then
            table.remove(teamIds, i)
            return
        end
    end
end

--- 修复旧存档里因缺少 CHN 素材而生成成其他国家风格的中超升降级球队
function SeasonManager._repairSecondDivisionTeamCountries(gameState, leagueKey, league)
    local expectedCountry = _getLeagueCountry(leagueKey, league)
    if expectedCountry ~= "CHN" then return end

    for _, teamId in ipairs(league.teamIds or {}) do
        local team = gameState.teams and gameState.teams[teamId]
        if team and not team.jsonTeamId and (team.country ~= expectedCountry or team._generatedCountry ~= expectedCountry) then
            SeasonManager._localizeGeneratedPromotionTeam(gameState, team, expectedCountry)
        end
    end

    local secondDiv = gameState.secondDivision and gameState.secondDivision[leagueKey]
    if not secondDiv then return end

    for _, teamId in ipairs(secondDiv.teamIds or {}) do
        local team = gameState.teams and gameState.teams[teamId]
        if team and not team.jsonTeamId and (team.country ~= expectedCountry or team._generatedCountry ~= expectedCountry) then
            SeasonManager._localizeGeneratedPromotionTeam(gameState, team, expectedCountry)
        end
    end
end

--- 初始化某联赛的二级联赛储备池（首次触发时程序化生成球队）
function SeasonManager._initSecondDivision(gameState, leagueKey, league)
    gameState.secondDivision[leagueKey] = {
        teamIds = {},
        standings = {},
    }
    local secondDiv = gameState.secondDivision[leagueKey]
    local country = _getLeagueCountry(leagueKey, league)

    -- 生成 6 支二级联赛球队作为初始储备
    local count = 6
    for _ = 1, count do
        local team = SeasonManager._generatePromotionTeam(gameState, leagueKey, country)
        table.insert(secondDiv.teamIds, team.id)
    end
end

--- 获取二级联赛排名
function SeasonManager._getSecondDivSorted(secondDiv)
    if not secondDiv.standings or next(secondDiv.standings) == nil then
        -- 无赛季数据，随机排序
        local result = {}
        for _, tid in ipairs(secondDiv.teamIds) do
            table.insert(result, { teamId = tid, points = RandomInt(30, 80) })
        end
        table.sort(result, function(a, b) return a.points > b.points end)
        return result
    end

    local sorted = {}
    for _, s in pairs(secondDiv.standings) do
        table.insert(sorted, s)
    end
    table.sort(sorted, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
        return a.goalsFor > b.goalsFor
    end)
    return sorted
end

--- 模拟二级联赛整赛季（抽象模拟，不生成真实赛程）
function SeasonManager._simulateSecondDivision(gameState, leagueKey, secondDiv)
    secondDiv.standings = {}

    for _, tid in ipairs(secondDiv.teamIds) do
        local team = gameState.teams[tid]
        local strength = SeasonManager._getTeamStrength(gameState, tid)

        -- 基于实力生成模拟积分（实力越强基准分越高）
        local basePoints = math.floor(strength * 0.8 + RandomInt(-10, 10))
        local played = 30 + RandomInt(0, 8)  -- 模拟30-38轮
        local wins = math.floor(basePoints / 3)
        local draws = RandomInt(3, 10)
        local losses = played - wins - draws
        if losses < 0 then losses = 0; draws = played - wins end
        local goalsFor = wins * 2 + draws + RandomInt(0, 15)
        local goalsAgainst = losses * 2 + draws + RandomInt(0, 10)

        secondDiv.standings[tid] = {
            teamId = tid,
            played = played,
            wins = wins,
            draws = draws,
            losses = losses,
            goalsFor = goalsFor,
            goalsAgainst = goalsAgainst,
            goalDifference = goalsFor - goalsAgainst,
            points = wins * 3 + draws,
        }
    end
end

--- 获取球队综合实力评分
function SeasonManager._getTeamStrength(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return 50 end

    local total = 0
    local count = 0
    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            total = total + (player.overall or 50)
            count = count + 1
        end
    end
    return count > 0 and math.floor(total / count) or 50
end

--- 程序化球员：同队 displayName 去重
local function _pickUniqueRegenName(usedNames, firstNames, lastNames)
    for _ = 1, 80 do
        local lastName = lastNames[RandomInt(1, #lastNames)]
        local firstName = firstNames[RandomInt(1, #firstNames)]
        local displayName = lastName .. " " .. firstName
        if not usedNames[displayName] then
            usedNames[displayName] = true
            return firstName, lastName, displayName
        end
    end
    local lastName = lastNames[RandomInt(1, #lastNames)]
    local firstName = firstNames[RandomInt(1, #firstNames)]
    local middle = firstNames[RandomInt(1, #firstNames)]:sub(1, 1)
    local displayName = lastName .. " " .. firstName .. " " .. middle .. "."
    usedNames[displayName] = true
    return firstName, lastName, displayName
end

--- 生成一支升级球队（程序化创建）
function SeasonManager._generatePromotionTeam(gameState, leagueKey, country)
    country = country or _getLeagueCountry(leagueKey, nil)
    -- 球队名称素材（按国家）
    local namePool = SeasonManager._getTeamNamePool(country)
    local cityPool = SeasonManager._getCityPool(country)

    -- 避免重名
    local name, city
    for _ = 1, 20 do
        city = cityPool[RandomInt(1, #cityPool)]
        local suffix = namePool[RandomInt(1, #namePool)]
        name = city .. suffix
        -- 检查是否已存在
        local exists = false
        for _, t in pairs(gameState.teams) do
            if t.name == name then exists = true; break end
        end
        if not exists then break end
    end

    local team = gameState:addTeam({
        name = name,
        shortName = name,
        city = city,
        country = country,
        _generatedCountry = country,
        colors = {
            primary = string.format("#%02x%02x%02x", RandomInt(0, 200), RandomInt(0, 200), RandomInt(0, 200)),
            secondary = "#ffffff",
        },
        stadiumName = city .. "球场",
        stadiumCapacity = RandomInt(8000, 25000),
        foundedYear = RandomInt(1890, 1970),
    })

    -- 生成基础阵容（实力略低于顶级联赛）
    SeasonManager._generateSquadForTeam(gameState, team, leagueKey)

    local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
    AiSquadPolicy.ensureFinancialBaseline(team)

    return team
end

--- 旧存档升降级候选队国家错误时，只替换程序化展示素材，保留队伍 id/财务/战绩
function SeasonManager._localizeGeneratedPromotionTeam(gameState, team, country)
    local namePool = SeasonManager._getTeamNamePool(country)
    local cityPool = SeasonManager._getCityPool(country)
    local city = cityPool[RandomInt(1, #cityPool)]
    local name = city .. namePool[RandomInt(1, #namePool)]

    for _ = 1, 20 do
        local exists = false
        for _, other in pairs(gameState.teams or {}) do
            if other ~= team and other.name == name then
                exists = true
                break
            end
        end
        if not exists then break end
        city = cityPool[RandomInt(1, #cityPool)]
        name = city .. namePool[RandomInt(1, #namePool)]
    end

    team.name = name
    team.shortName = name
    team.city = city
    team.country = country
    team._generatedCountry = country
    team.stadiumName = city .. "球场"

    local lastNames = SeasonManager._getLastNamePool(country)
    local firstNames = SeasonManager._getFirstNamePool(country)
    local usedNames = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local player = gameState.players and gameState.players[pid]
        if player then
            local firstName, lastName, displayName = _pickUniqueRegenName(usedNames, firstNames, lastNames)
            player.firstName = firstName
            player.lastName = lastName
            player.displayName = displayName
            player.nationality = country
        end
    end
end

--- 为新球队生成阵容
function SeasonManager._generateSquadForTeam(gameState, team, leagueKey)
    local positions = {"GK", "GK", "CB", "CB", "CB", "LB", "RB", "CM", "CM", "CDM",
                       "CAM", "LW", "RW", "ST", "ST", "CB", "CM", "RW"}

    -- 二级联赛球员能力范围（低于顶级联赛）
    local baseMin, baseMax = 5, 12

    local lastNames = SeasonManager._getLastNamePool(team.country)
    local firstNames = SeasonManager._getFirstNamePool(team.country)
    local usedNames = {}

    for _, pos in ipairs(positions) do
        local age = RandomInt(19, 32)
        local firstName, lastName, displayName = _pickUniqueRegenName(usedNames, firstNames, lastNames)

        local playerData = {
            firstName = firstName,
            lastName = lastName,
            displayName = displayName,
            birthYear = gameState.date.year - age,
            nationality = team.country,
            position = pos,
            preferredFoot = Random() < 0.8 and "right" or "left",
            attributes = {},
            contractEnd = {year = gameState.date.year + RandomInt(1, 4), month = 6},
            wage = RandomInt(300, 2000),
            teamId = team.id,
        }

        local attrNames = {"speed", "stamina", "strength", "agility", "passing",
            "shooting", "tackling", "dribbling", "defending", "positioning",
            "vision", "decisions", "composure", "aggression", "teamwork",
            "leadership", "aerial"}
        local baseAbility = RandomInt(baseMin, baseMax)
        for _, attr in ipairs(attrNames) do
            playerData.attributes[attr] = math.max(1, math.min(20, baseAbility + RandomInt(-3, 3)))
        end
        if pos == "GK" then
            playerData.attributes.handling = RandomInt(6, 14)
            playerData.attributes.reflexes = RandomInt(6, 14)
        end
        playerData.potential = math.min(99, baseAbility * 5 + RandomInt(5, 25))

        local player = gameState:addPlayer(playerData)
        player.paRating = PotentialSystem.rawToRating(player.potential)
        player.actualPotential = PotentialSystem.generateActualPotential(player.paRating, (gameState.potentialSeed or os.time()) + player.id * 7919)
        player.teamId = team.id
        table.insert(team.playerIds, player.id)
    end
end

--- 球队名称池
function SeasonManager._getTeamNamePool(country)
    local pools = {
        ENG = {"联", "城", "流浪者", "竞技", "镇", "FC", "联合"},
        ES  = {"竞技", "皇家", "体育", "联合", "FC"},
        IT  = {"FC", "联合", "竞技", "体育", "1905"},
        DE  = {"FC", "体育", "联合", "09", "04"},
        FR  = {"FC", "竞技", "体育", "奥林匹克", "联合"},
        CHN = {"队", "FC", "竞技", "联合", "城", "龙狮", "雄狮", "蓝鲸"},
    }
    return pools[country] or pools.ENG
end

function SeasonManager._getCityPool(country)
    local pools = {
        ENG = {"布里斯托", "诺丁汉", "谢菲尔德", "伯明翰", "利兹", "桑德兰", "米德尔斯堡",
               "斯旺西", "伍尔弗", "伯恩茅斯", "卡迪夫", "德比", "哈德斯菲尔德", "雷丁"},
        ES  = {"巴列卡诺", "拉科鲁尼亚", "萨拉戈萨", "埃尔切", "莱加内斯", "马拉加",
               "阿尔巴塞特", "特内里费", "卡塔赫纳", "布尔戈斯", "桑坦德"},
        IT  = {"布雷西亚", "巴里", "帕尔马", "帕莱莫", "佩鲁贾", "卡利亚里", "弗洛西诺内",
               "比萨", "科森扎", "克雷莫纳", "摩德纳", "雷焦"},
        DE  = {"汉诺威", "纽伦堡", "汉堡", "凯泽斯劳滕", "帕德博恩", "达姆施塔特",
               "杜塞尔多夫", "马格德堡", "布伦瑞克", "罗斯托克"},
        FR  = {"梅斯", "卡昂", "洛里昂", "欧塞尔", "特鲁瓦", "阿雅克肖",
               "昂热", "南锡", "格勒诺布尔", "巴黎FC", "瓦朗谢纳"},
        CHN = {"南京", "青岛", "苏州", "无锡", "南通", "大连", "沈阳", "长春", "石家庄", "济南",
               "佛山", "东莞", "厦门", "昆明", "西安", "武汉", "长沙", "南昌", "成都", "重庆"},
    }
    return pools[country] or pools.ENG
end

function SeasonManager._getLastNamePool(country)
    local pools = {
        ENG = {"Smith", "Johnson", "Williams", "Brown", "Jones", "Taylor", "Davies",
               "Wilson", "Evans", "Thomas", "Roberts", "Walker", "Wright", "Hall",
               "Green", "Baker", "Adams", "Campbell", "Mitchell", "Carter"},
        ES  = {"García", "Martínez", "López", "Rodríguez", "Fernández", "González",
               "Sánchez", "Pérez", "Ruiz", "Díaz", "Hernández", "Moreno", "Muñoz", "Romero"},
        IT  = {"Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano",
               "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "Mancini"},
        DE  = {"Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer",
               "Wagner", "Becker", "Schulz", "Hoffmann", "Koch", "Richter", "Klein", "Wolf"},
        FR  = {"Martin", "Bernard", "Dubois", "Thomas", "Robert", "Richard",
               "Petit", "Durand", "Leroy", "Moreau", "Simon", "Laurent", "Lefevre", "Mercier"},
        CHN = {"王", "李", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴", "徐", "孙",
               "马", "朱", "胡", "郭", "何", "高", "林", "罗", "郑", "梁", "谢", "宋"},
    }
    return pools[country] or pools.ENG
end

function SeasonManager._getFirstNamePool(country)
    local pools = {
        ENG = {"James", "Oliver", "Harry", "George", "Jack", "Charlie", "Leo",
               "Thomas", "William", "Oscar", "Daniel", "Ben", "Sam", "Luke",
               "Henry", "Alfie", "Freddie", "Archie", "Ethan", "Noah"},
        ES  = {"Pablo", "Daniel", "Hugo", "Mateo", "Alejandro", "Álvaro",
               "Adrián", "David", "Mario", "Diego", "Sergio", "Carlos",
               "Iván", "Javier", "Raúl", "Marcos", "Rubén", "Ángel"},
        IT  = {"Leonardo", "Francesco", "Alessandro", "Lorenzo", "Mattia",
               "Andrea", "Gabriele", "Riccardo", "Tommaso", "Edoardo",
               "Luca", "Filippo", "Matteo", "Davide", "Simone"},
        DE  = {"Lukas", "Leon", "Luca", "Finn", "Elias", "Jonas",
               "Ben", "Noah", "Paul", "Felix", "Maximilian", "Tim",
               "Niklas", "Moritz", "Jan", "Florian", "Tobias", "Simon"},
        FR  = {"Lucas", "Louis", "Gabriel", "Raphaël", "Arthur", "Hugo",
               "Jules", "Adam", "Léo", "Nathan", "Ethan", "Paul",
               "Antoine", "Maxime", "Clément", "Théo", "Enzo", "Tom"},
        CHN = {"伟", "磊", "强", "洋", "杰", "涛", "超", "鹏", "鑫", "浩", "博", "宇",
               "俊", "健", "凯", "晨", "昊", "旭", "坤", "航", "毅", "宁", "泽", "睿"},
    }
    return pools[country] or pools.ENG
end

--- 生成升降级新闻
function SeasonManager._generatePromotionRelegationNews(gameState, newsItems)
    -- 按联赛分组
    local byLeague = {}
    for _, item in ipairs(newsItems) do
        if not byLeague[item.leagueKey] then byLeague[item.leagueKey] = {} end
        table.insert(byLeague[item.leagueKey], item)
    end

    for leagueKey, items in pairs(byLeague) do
        local lg = gameState.leagues[leagueKey]
        local leagueName = lg and lg.name or leagueKey
        local secondName = SECOND_DIVISION_NAMES[leagueKey] or "二级联赛"

        local relegated = {}
        local promoted = {}
        for _, item in ipairs(items) do
            if item.type == "relegated" then
                table.insert(relegated, item.teamName)
            else
                table.insert(promoted, item.teamName)
            end
        end

        local body = ""
        if #relegated > 0 then
            body = body .. "降级至" .. secondName .. ": " .. table.concat(relegated, ", ") .. "\n"
        end
        if #promoted > 0 then
            body = body .. "升级至" .. leagueName .. ": " .. table.concat(promoted, ", ")
        end

        gameState:addNews({
            category = "season_news",
            title = string.format("%s 升降级公告", leagueName),
            body = body,
        })
    end
end

------------------------------------------------------
-- 新赛季初始化（所有联赛）
------------------------------------------------------

------------------------------------------------------
-- 新赛季预算分配
-- 根据球队余额、声望、实际周薪支出重新计算合理的转会预算和工资预算
-- 公式参照 real_data_loader: transferBudget ≈ wageBudget * 25, balance ≈ wageBudget * 80
------------------------------------------------------
function SeasonManager._allocateSeasonBudgets(gameState)
    local AiSquadPolicy = require("scripts/systems/ai_squad_policy")
    local TransferManager = require("scripts/systems/transfer_manager")

    for _, team in pairs(gameState.teams) do
        AiSquadPolicy.ensureFinancialBaseline(team)
        local actualWeeklyWage = FinanceManager.getWeeklyWageTotal(gameState, team.id)

        local baseWb = team._baseWageBudget or team.wageBudget or 200000
        local floorFactor = AiSquadPolicy.getFinancialFloorFactor(team)
        local wageFloor = math.floor(baseWb * floorFactor)

        -- 工资预算：基于实际支出 + 小幅缓冲，但不无限跟涨
        local incomeScale = FinanceManager._getWageScale(team)
        local incomeBasedWageCap = math.floor((team._lastSeasonIncome or team.seasonIncome or 0) / 520 * incomeScale)
        local newWageBudget = math.max(
            200000,
            wageFloor,
            math.floor(actualWeeklyWage * 1.08),
            math.min(math.floor(actualWeeklyWage * 1.25), incomeBasedWageCap > 0 and incomeBasedWageCap or math.floor(actualWeeklyWage * 1.25))
        )

        -- 现金安全垫：至少覆盖 16 周工资 + 未付分期
        local pendingPayables = TransferManager.getPendingPayablesTotal and TransferManager.getPendingPayablesTotal(team) or 0
        local cashReserve = math.floor(actualWeeklyWage * 16 + pendingPayables + newWageBudget * 4)
        local spendableBalance = math.max(0, (team.balance or 0) - cashReserve)

        local rep = team.reputation or 600
        local repFactor = 0.45 + math.max(0, math.min(1.0, (rep - 400) / 400))
        local balanceBased = math.floor(spendableBalance * 0.18 * repFactor)

        local tierFloor
        if rep >= 780 then tierFloor = 8000000
        elseif rep >= 680 then tierFloor = 5000000
        elseif rep >= 580 then tierFloor = 2500000
        else tierFloor = 1000000
        end

        local floor = math.floor(newWageBudget * 6)
        local cap = math.floor(math.max(0, team.balance or 0) * 0.35)
        local newTransferBudget = math.max(tierFloor, math.min(cap, math.max(floor, balanceBased)))

        if FinanceManager.isTransferRestricted(team) then
            newTransferBudget = math.floor(newTransferBudget * 0.5)
        end

        team._lastSeasonIncome = team.seasonIncome or team._lastSeasonIncome
        team.wageBudget = newWageBudget
        team.transferBudget = newTransferBudget
    end

    local ContractManager = require("scripts/systems/contract_manager")
    ContractManager.resetSeasonWageFlags(gameState)
end

function SeasonManager._startNewSeason(gameState)
    -- 清除旧赛季遗留的比赛待处理标记（防止第二赛季卡住）
    gameState.pendingPlayerFixture = nil

    -- 更新赛季年份
    gameState.season = gameState.season + 1

    -- 国际大赛年（世界杯/欧洲杯）从6月1日开始，否则从8月10日开始
    local isIntlYear = EuroCup.isInternationalTournamentYear(gameState.season)
    if isIntlYear then
        gameState.date = {
            year = gameState.season,
            month = 6,
            day = 1,
        }
    else
        -- 新赛季从夏窗开启（7月1日）起步，便于赛季结算后先处理转会
        gameState.date = {
            year = gameState.season,
            month = 7,
            day = 1,
        }
    end
    gameState.dayOfWeek = 1

    -- 联赛始终从8月开始（与世界杯日期无关）
    local leagueStartDate = {
        year = gameState.season,
        month = Constants.SEASON_START_MONTH,
        day = Constants.SEASON_START_DAY,
    }
    for _, lg in pairs(gameState.leagues) do
        lg:initStandings()
        lg.season = gameState.season
        lg.currentRound = 1
        lg:generateFixtures(leagueStartDate)
    end

    -- 新赛季重建了所有联赛 fixture；无论后续安全网是否实际修复，都必须丢弃旧日期索引。
    gameState._leagueFixtureDateIndex = nil
    gameState._cachedNextMatch = nil
    gameState._fixMisalignedLeagueFixturesDone = nil
    gameState._stuckProgressRepairDone = nil
    SeasonManager.ensurePlayerLeagueIntegrity(gameState)

    -- 清理旧的转会报价
    if gameState.transfers then
        gameState.transfers.bids = {}
    end

    -- 重置经理续约标记（每赛季重新检查）
    gameState._managerRenewalOffered = nil

    -- 清理旧的球探报告和自动发现
    gameState.scoutReports = {}
    gameState.scoutDiscoveries = {}

    -- 重新分配各队赛季预算（转会预算 + 工资预算）
    SeasonManager._allocateSeasonBudgets(gameState)

    -- 初始化本赛季欧冠
    ChampionsLeague.initialize(gameState)

    -- 初始化本赛季欧联杯
    local EuropaLeague = require("scripts/systems/europa_league")
    EuropaLeague.initialize(gameState)

    -- 初始化国内杯赛（足总杯、国王杯等）
    DomesticCup.initialize(gameState)

    -- 国际大赛（欧洲杯年与世界杯年互斥）
    -- 清理上一届已完赛的赛事数据
    if gameState.worldCup and gameState.worldCup.phase == "completed" then
        gameState.worldCup = nil
    end
    if gameState.euroCup and gameState.euroCup.phase == "completed" then
        gameState.euroCup = nil
    end
    if EuroCup.isEuroYear(gameState.season) then
        EuroCup.initialize(gameState)
    else
        WorldCup.initialize(gameState)
    end

    -- 初始化赛季目标系统
    ObjectivesManager.initSeason(gameState)

    -- 为所有球队生成新赛季董事会目标
    local BoardManager = require("scripts/systems/board_manager")
    BoardManager.generateSeasonObjectives(gameState)

    for _, team in pairs(gameState.teams) do
        team._promotedThisSeason = nil
    end

    -- 生成新赛季赞助合同选项（玩家需在赛季初选择）
    local FinanceManager = require("scripts/systems/finance_manager")
    FinanceManager.generateSponsorOffers(gameState)

    -- AI 一线队人数保底（新赛季开始前补齐）
    local AIManager = require("scripts/systems/ai_manager")
    AIManager.ensureAllTargetSquads(gameState)

    -- B3: 赛季前瞻新闻
    NewsGenerator.generateSeasonPreview(gameState)
end

return SeasonManager
