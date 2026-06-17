-- systems/champions_league.lua
-- 欧冠联赛管理（2024/25新赛制：36队瑞士制联赛阶段 + 附加赛 + 淘汰赛）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")
local ReputationManager = require("scripts/systems/reputation_manager")
local FinanceManager = require("scripts/systems/finance_manager")

local ChampionsLeague = {}

-- 各联赛欧冠名额：五大联赛各 7 席，英超额外 +1（合计 36）
local UCL_SPOTS_PER_LEAGUE = 7
local UCL_SPOTS_EPL_BONUS = 1

-- 加载中超时：英超额外名额转给中超冠军（五大联赛仍各 7 席，合计仍为 36）
local UCL_SPOTS_CSL_CHAMPION = 1

-- 首赛季不参与欧冠席位分配，从第2赛季起按上赛季积分榜取名额
local UCL_SPOTS_FROM_SEASON_2 = {
    CSL = true,
}

--- 当前存档的联赛欧冠名额表（随是否加载中超动态变化）
function ChampionsLeague.getUclSpots(gameState)
    local spots = {
        EPL = UCL_SPOTS_PER_LEAGUE + UCL_SPOTS_EPL_BONUS,
        LaLiga = UCL_SPOTS_PER_LEAGUE,
        SerieA = UCL_SPOTS_PER_LEAGUE,
        Bundesliga = UCL_SPOTS_PER_LEAGUE,
        Ligue1 = UCL_SPOTS_PER_LEAGUE,
    }
    if gameState and gameState.leagues and gameState.leagues.CSL then
        spots.EPL = UCL_SPOTS_PER_LEAGUE
        spots.CSL = UCL_SPOTS_CSL_CHAMPION
    end
    return spots
end

local TOTAL_TEAMS = 36

-- 欧冠日程（2024/25 新赛制）
local UCL_SCHEDULE = {
    league_start    = { month = 9, day = 17 },  -- 9月中旬联赛阶段开始
    playoff_start   = { month = 2, day = 11 },  -- 2月附加赛
    r16_start       = { month = 3, day = 4 },   -- 3月1/8决赛
    qf_start        = { month = 4, day = 8 },   -- 4月1/4决赛
    sf_start        = { month = 4, day = 29 },  -- 4月底半决赛
    final_date      = { month = 5, day = 31 },  -- 5月底/6月初决赛
}

------------------------------------------------------
-- 初始化本赛季欧冠（36队瑞士制）
------------------------------------------------------

local function _countLeaguePhaseFixturesPerTeam(lp)
    local teamIds = lp.teamIds or {}
    local counts = {}
    for _, tid in ipairs(teamIds) do
        counts[tid] = 0
    end
    for _, f in ipairs(lp.fixtures or {}) do
        counts[f.homeTeamId] = (counts[f.homeTeamId] or 0) + 1
        counts[f.awayTeamId] = (counts[f.awayTeamId] or 0) + 1
    end
    return counts
end

local function _leaguePhaseFixtureCountsValid(lp)
    if not lp then return false end
    local teamIds = lp.teamIds or {}
    if #teamIds == 0 then return false end
    local expectedTotal = math.floor(#teamIds * 8 / 2)
    if #(lp.fixtures or {}) ~= expectedTotal then
        return false
    end
    local counts = _countLeaguePhaseFixturesPerTeam(lp)
    for _, tid in ipairs(teamIds) do
        if (counts[tid] or 0) ~= 8 then
            return false
        end
    end
    return true
end

local function _leaguePhaseKickoffDate(uclSeason)
    return League._alignToWeekday({
        year = uclSeason,
        month = UCL_SCHEDULE.league_start.month,
        day = UCL_SCHEDULE.league_start.day,
    }, 3)
end

local function _leaguePhaseHasFinishedMatch(lp)
    for _, f in ipairs(lp.fixtures or {}) do
        if f.status ~= "scheduled" then
            return true
        end
    end
    return false
end

function ChampionsLeague.initialize(gameState)
    local season = gameState.season
    local qualifiedTeams = ChampionsLeague._getQualifiedTeams(gameState)

    -- 确保恰好36队
    if #qualifiedTeams < TOTAL_TEAMS then
        qualifiedTeams = ChampionsLeague._fillSlots(gameState, qualifiedTeams, TOTAL_TEAMS)
    end
    while #qualifiedTeams > TOTAL_TEAMS do
        table.remove(qualifiedTeams)
    end

    -- 按声望排名分4档（每档9队）
    local pots = ChampionsLeague._seedIntoPots(gameState, qualifiedTeams)

    -- 创建锦标赛实例
    local ucl = Tournament.new({
        name = "欧洲冠军联赛",
        shortName = "UCL",
        type = "ucl",
        season = season,
        qualifiedTeams = qualifiedTeams,
    })

    -- 初始化联赛阶段（36队单一积分榜）
    ucl:initLeaguePhase(qualifiedTeams, pots)

    -- 抽签生成联赛阶段赛程（每队8场：每档2个对手，4主4客）
    local leagueStart = {
        year = season,
        month = UCL_SCHEDULE.league_start.month,
        day = UCL_SCHEDULE.league_start.day,
    }
    for attempt = 1, 5 do
        ucl:drawLeaguePhaseFixtures(leagueStart)
        if _leaguePhaseFixtureCountsValid(ucl.leaguePhase) then
            break
        end
        if attempt == 5 then
            log:Write(LOG_ERROR, "[UCL] 联赛阶段赛程生成失败（5次重试后仍异常）")
        end
    end

    -- 存储到 gameState
    gameState.championsLeague = ucl

    -- 新闻
    gameState:addNews({
        category = "ucl_news",
        title = "欧冠联赛阶段抽签揭晓",
        body = ChampionsLeague._formatLeagueDrawResult(gameState, ucl),
    })

    return ucl
end

------------------------------------------------------
-- 存档迁移：旧格式（小组赛）→ 新格式（瑞士制）
------------------------------------------------------

local function _rebuildLeaguePhaseStandings(ucl)
    local lp = ucl.leaguePhase
    if not lp or not lp.standings then return end
    for _, s in pairs(lp.standings) do
        s.played = 0
        s.wins = 0
        s.draws = 0
        s.losses = 0
        s.goalsFor = 0
        s.goalsAgainst = 0
        s.goalDifference = 0
        s.points = 0
    end
    for _, f in ipairs(lp.fixtures or {}) do
        if f.status == "finished" then
            ucl:updateLeagueStanding(f)
        end
    end
end

local function _trimExcessLeaguePhaseFixtures(ucl)
    local lp = ucl.leaguePhase
    local teamIds = lp.teamIds or {}
    local counts = _countLeaguePhaseFixturesPerTeam(lp)

    while true do
        local overTeam = nil
        for _, tid in ipairs(teamIds) do
            if (counts[tid] or 0) > 8 then
                overTeam = tid
                break
            end
        end
        if not overTeam then break end

        local removed = false
        for i = #lp.fixtures, 1, -1 do
            local f = lp.fixtures[i]
            if f.status == "scheduled"
                and (f.homeTeamId == overTeam or f.awayTeamId == overTeam) then
                table.remove(lp.fixtures, i)
                counts[f.homeTeamId] = counts[f.homeTeamId] - 1
                counts[f.awayTeamId] = counts[f.awayTeamId] - 1
                removed = true
                break
            end
        end
        if not removed then break end
    end

    _rebuildLeaguePhaseStandings(ucl)
end

--- 读档/主页继续前：修复联赛阶段赛程缺失，并补模拟已逾期的非玩家欧冠比赛
function ChampionsLeague.repairStuckProgress(gameState)
    local ucl = gameState.championsLeague
    if not ucl or ucl.phase ~= Tournament.PHASE_LEAGUE then
        return false
    end

    local lp = ucl.leaguePhase
    if not lp then return false end

    local repaired = false

    -- 赛程为空或场次异常：在尚无赛果时重新抽签
    if not _leaguePhaseHasFinishedMatch(lp) and not _leaguePhaseFixtureCountsValid(lp) then
        log:Write(LOG_INFO, "[UCL] 检测到联赛阶段赛程缺失/异常，重新抽签...")
        local leagueStart = {
            year = ucl.season or gameState.season,
            month = UCL_SCHEDULE.league_start.month,
            day = UCL_SCHEDULE.league_start.day,
        }
        for attempt = 1, 5 do
            ucl:drawLeaguePhaseFixtures(leagueStart)
            if _leaguePhaseFixtureCountsValid(lp) then break end
        end
        lp._scheduleFixed = nil
        lp._fixtureCountFixed = nil
        repaired = true
    end

    -- 已过开幕日且有逾期场次但积分榜仍为 0：补模拟非玩家比赛
    local TurnProcessor = require("scripts/core/turn_processor")
    local kickoff = _leaguePhaseKickoffDate(ucl.season or gameState.season)
    if TurnProcessor._isDateBeforeOrEqual(kickoff, gameState.date) then
        local hasOverdue = false
        for _, f in ipairs(lp.fixtures or {}) do
            if f.status == "scheduled" and f.date
                and TurnProcessor._isDateBefore(f.date, gameState.date) then
                hasOverdue = true
                break
            end
        end
        if hasOverdue then
            TurnProcessor.simulateNonPlayerOverdueUCLFixtures(gameState)
            ChampionsLeague.checkPhaseAdvance(gameState)
            repaired = true
        end
    end

    return repaired
end

function ChampionsLeague.migrateIfNeeded(gameState)
    local ucl = gameState.championsLeague
    if not ucl then return false end

    -- 检测旧格式：有 groups 且没有 leaguePhase
    if ucl.groups and next(ucl.groups) and not ucl.leaguePhase then
        log:Write(LOG_INFO, "[UCL] 检测到旧格式存档，正在迁移为2024/25瑞士制...")

        -- 收集旧小组赛中的所有球队
        local oldTeams = {}
        for _, group in pairs(ucl.groups) do
            if group.teamIds then
                for _, tid in ipairs(group.teamIds) do
                    table.insert(oldTeams, tid)
                end
            elseif group.standings then
                for teamId, _ in pairs(group.standings) do
                    table.insert(oldTeams, teamId)
                end
            end
        end

        -- 补充到36队
        if #oldTeams < TOTAL_TEAMS then
            oldTeams = ChampionsLeague._fillSlots(gameState, oldTeams, TOTAL_TEAMS)
        end
        while #oldTeams > TOTAL_TEAMS do
            table.remove(oldTeams)
        end

        -- 分档
        local pots = ChampionsLeague._seedIntoPots(gameState, oldTeams)

        -- 重新初始化联赛阶段
        ucl.qualifiedTeams = oldTeams
        ucl.groups = {}  -- 清除旧小组数据
        ucl:initLeaguePhase(oldTeams, pots)

        -- 重新抽签
        local leagueStart = {
            year = ucl.season or gameState.season,
            month = UCL_SCHEDULE.league_start.month,
            day = UCL_SCHEDULE.league_start.day,
        }
        ucl:drawLeaguePhaseFixtures(leagueStart)

        -- 新闻通知
        gameState:addNews({
            category = "ucl_news",
            title = "欧冠赛制改革：瑞士制联赛阶段启用",
            body = "欧冠本赛季起采用全新瑞士制联赛阶段，36支球队同组竞技，每队出战8场。前8名直接晋级16强，9-24名进入附加赛。",
        })

        log:Write(LOG_INFO, "[UCL] 迁移完成，36队瑞士制联赛阶段已初始化")
        return true
    end

    -- 检测旧抽签 bug：部分球队联赛阶段不是恰好 8 场（补充配对允许对手已有 8 场时再加赛）
    if ucl.leaguePhase and ucl.leaguePhase.fixtures and not ucl.leaguePhase._fixtureCountFixed then
        local lp = ucl.leaguePhase
        if not _leaguePhaseFixtureCountsValid(lp) then
            local anyFinished = false
            for _, f in ipairs(lp.fixtures) do
                if f.status ~= "scheduled" then
                    anyFinished = true
                    break
                end
            end

            if not anyFinished then
                log:Write(LOG_INFO, "[UCL] 检测到联赛阶段赛程场次异常，重新抽签...")
                local leagueStart = {
                    year = ucl.season or gameState.season,
                    month = UCL_SCHEDULE.league_start.month,
                    day = UCL_SCHEDULE.league_start.day,
                }
                ucl:drawLeaguePhaseFixtures(leagueStart)
                lp._scheduleFixed = nil
            else
                log:Write(LOG_INFO, "[UCL] 检测到联赛阶段赛程场次异常，移除多余未赛比赛...")
                _trimExcessLeaguePhaseFixtures(ucl)
            end

            gameState:addNews({
                category = "ucl_news",
                title = "欧冠联赛阶段赛程已修正",
                body = "系统检测到部分球队联赛阶段场次异常（应为每队8场），已自动修正赛程与积分榜。",
            })
            lp._fixtureCountFixed = true
            return true
        end
        lp._fixtureCountFixed = true
    end

    -- 检测赛程冲突：同一比赛日同一队有多场比赛（旧算法bug）
    -- 仅修复一次：修复后标记 _scheduleFixed 防止每次 advanceDay 都重复洗牌
    if ucl.leaguePhase and ucl.leaguePhase.fixtures and not ucl.leaguePhase._scheduleFixed then
        local lp = ucl.leaguePhase
        local hasConflict = false

        -- 检查是否有冲突：teamId → { [matchday] = count }
        local teamDayCounts = {}
        for _, f in ipairs(lp.fixtures) do
            if f.status == "scheduled" and f.matchday then
                for _, tid in ipairs({ f.homeTeamId, f.awayTeamId }) do
                    if not teamDayCounts[tid] then teamDayCounts[tid] = {} end
                    teamDayCounts[tid][f.matchday] = (teamDayCounts[tid][f.matchday] or 0) + 1
                    if teamDayCounts[tid][f.matchday] > 1 then
                        hasConflict = true
                    end
                end
            end
        end

        if hasConflict then
            log:Write(LOG_INFO, "[UCL] 检测到赛程冲突（同一比赛日同队多场），重新分配比赛日...")

            -- 只重新分配未完成比赛的日期，保留已完成比赛不变
            local scheduledFixtures = {}
            for _, f in ipairs(lp.fixtures) do
                if f.status == "scheduled" then
                    table.insert(scheduledFixtures, f)
                end
            end

            -- 重建比赛日日期
            local leagueStart = {
                year = ucl.season or gameState.season,
                month = UCL_SCHEDULE.league_start.month,
                day = UCL_SCHEDULE.league_start.day,
            }
            local matchDays = {}
            local date = League._alignToWeekday(
                { year = leagueStart.year, month = leagueStart.month, day = leagueStart.day }, 3)
            for i = 1, 8 do
                table.insert(matchDays, { year = date.year, month = date.month, day = date.day })
                date = League._addDays(date, 14)
            end

            local teamIds = lp.teamIds or {}
            local maxPerDay = math.max(1, math.floor(#teamIds / 2))

            -- 洗牌待重新分配的赛程
            for i = #scheduledFixtures, 2, -1 do
                local j = RandomInt(1, i)
                scheduledFixtures[i], scheduledFixtures[j] = scheduledFixtures[j], scheduledFixtures[i]
            end

            -- 收集已完成比赛占用的slot
            local teamDayUsed = {}
            for _, tid in ipairs(teamIds) do
                teamDayUsed[tid] = {}
            end
            local daySlots = {}
            for i = 1, 8 do
                daySlots[i] = 0
            end
            for _, f in ipairs(lp.fixtures) do
                if f.status ~= "scheduled" and f.matchday then
                    daySlots[f.matchday] = daySlots[f.matchday] + 1
                    if teamDayUsed[f.homeTeamId] then
                        teamDayUsed[f.homeTeamId][f.matchday] = true
                    end
                    if teamDayUsed[f.awayTeamId] then
                        teamDayUsed[f.awayTeamId][f.matchday] = true
                    end
                end
            end

            -- 贪心重新分配
            for _, f in ipairs(scheduledFixtures) do
                local assigned = false
                for d = 1, 8 do
                    if daySlots[d] < maxPerDay and
                       not teamDayUsed[f.homeTeamId][d] and
                       not teamDayUsed[f.awayTeamId][d] then
                        f.date = matchDays[d]
                        f.matchday = d
                        daySlots[d] = daySlots[d] + 1
                        if teamDayUsed[f.homeTeamId] then
                            teamDayUsed[f.homeTeamId][d] = true
                        end
                        if teamDayUsed[f.awayTeamId] then
                            teamDayUsed[f.awayTeamId][d] = true
                        end
                        assigned = true
                        break
                    end
                end
                if not assigned then
                    -- fallback: 找负载最轻且至少一方无冲突的比赛日
                    local bestDay = nil
                    local bestCount = 999
                    for d = 1, 8 do
                        local homeUsed = teamDayUsed[f.homeTeamId] and teamDayUsed[f.homeTeamId][d]
                        local awayUsed = teamDayUsed[f.awayTeamId] and teamDayUsed[f.awayTeamId][d]
                        -- 优先找双方都没用过的；其次找至少一方没用过的
                        if not homeUsed and not awayUsed and daySlots[d] < bestCount then
                            bestDay = d
                            bestCount = daySlots[d]
                        end
                    end
                    -- 如果还没找到，退而求其次：找负载最轻的
                    if not bestDay then
                        bestDay = 1
                        bestCount = daySlots[1]
                        for d = 2, 8 do
                            if daySlots[d] < bestCount then
                                bestDay = d
                                bestCount = daySlots[d]
                            end
                        end
                    end
                    f.date = matchDays[bestDay]
                    f.matchday = bestDay
                    daySlots[bestDay] = daySlots[bestDay] + 1
                    if teamDayUsed[f.homeTeamId] then
                        teamDayUsed[f.homeTeamId][bestDay] = true
                    end
                    if teamDayUsed[f.awayTeamId] then
                        teamDayUsed[f.awayTeamId][bestDay] = true
                    end
                end
            end

            -- 标记已修复，防止后续每次 advanceDay 都重复检测和洗牌
            lp._scheduleFixed = true
            log:Write(LOG_INFO, "[UCL] 赛程重新分配完成，共处理 " .. #scheduledFixtures .. " 场比赛")
            return true
        end

        -- 无冲突，标记为已检查
        lp._scheduleFixed = true
    end

    -- 检测并修复"UCL 被新赛季覆盖"bug（v2迁移）
    -- 场景：旧版本中联赛结束后 _startNewSeason 直接覆盖了进行中的 UCL
    -- 检测条件：season > 1 且上赛季没有 UCL 正常完成的记录
    if not gameState._uclOverwritePatched and gameState.season and gameState.season > 1 then
        gameState._uclCompletedSeasons = gameState._uclCompletedSeasons or {}
        local prevSeason = tostring(gameState.season - 1)

        -- 如果上赛季有完成记录，说明 UCL 正常结束，无需修复
        if not gameState._uclCompletedSeasons[prevSeason] then
            -- 启发式判断：如果当前 UCL 全部赛程都未开始（全 scheduled），
            -- 且当前日期在联赛阶段首场之前，高度怀疑是 bug 导致的覆盖
            local allScheduled = true
            if ucl.leaguePhase and ucl.leaguePhase.fixtures then
                for _, f in ipairs(ucl.leaguePhase.fixtures) do
                    if f.status ~= "scheduled" then
                        allScheduled = false
                        break
                    end
                end
            end

            if allScheduled then
                log:Write(LOG_INFO, "[UCL] 检测到上赛季UCL可能被覆盖（无完成记录），执行补偿迁移...")

                -- 从当前赛季合格球队中按声望选出模拟冠军（排除玩家，避免误判）
                local candidateTeams = {}
                if ucl.qualifiedTeams then
                    for _, tid in ipairs(ucl.qualifiedTeams) do
                        if tid ~= gameState.playerTeamId then
                            local team = gameState.teams[tid]
                            if team then
                                table.insert(candidateTeams, { id = tid, rep = team.reputation or 0 })
                            end
                        end
                    end
                end
                table.sort(candidateTeams, function(a, b) return a.rep > b.rep end)

                -- 从前8名中随机选一个作为上赛季冠军
                local topN = math.min(8, #candidateTeams)
                local retroChampionId = nil
                if topN > 0 then
                    local idx = RandomInt(1, topN)
                    retroChampionId = candidateTeams[idx].id
                end

                if retroChampionId then
                    local retroChampion = gameState.teams[retroChampionId]
                    local championName = retroChampion and retroChampion.name or "?"

                    -- 回填完成记录
                    gameState._uclCompletedSeasons[prevSeason] = retroChampionId

                    -- 在 worldHistory 中补充 UCL 记录
                    for _, record in ipairs(gameState.worldHistory) do
                        if record.season == gameState.season - 1 then
                            record.uclChampion = {
                                teamId = retroChampionId,
                                teamName = championName,
                            }
                            break
                        end
                    end

                    -- 如果玩家球队在合格名单中，补发参赛奖金（联赛阶段基础奖金）
                    local playerInUCL = false
                    if ucl.qualifiedTeams then
                        for _, tid in ipairs(ucl.qualifiedTeams) do
                            if tid == gameState.playerTeamId then
                                playerInUCL = true
                                break
                            end
                        end
                    end

                    if playerInUCL then
                        local playerTeam = gameState:getPlayerTeam()
                        if playerTeam then
                            local compensation = 10000000  -- 10M 参赛补偿
                            playerTeam.balance = playerTeam.balance + compensation
                            playerTeam.transferBudget = (playerTeam.transferBudget or 0) + compensation
                            playerTeam.seasonIncome = (playerTeam.seasonIncome or 0) + compensation
                            playerTeam.incomeBreakdown = playerTeam.incomeBreakdown or {}
                            playerTeam.incomeBreakdown.prize = (playerTeam.incomeBreakdown.prize or 0) + compensation
                            FinanceManager.addTransaction(playerTeam, {
                                amount = compensation,
                                description = "欧冠参赛补偿（赛程修复）",
                                category = "prize",
                                season = gameState.season,
                                week = FinanceManager._getWeekNumber(gameState),
                            })
                        end
                    end

                    -- 发送通知消息
                    gameState:sendMessage({
                        category = "league",
                        title = "欧冠赛程修复通知",
                        body = string.format(
                            "由于赛程系统升级，上赛季欧冠赛事数据已补全。\n" ..
                            "上赛季欧冠冠军：%s\n" ..
                            "%s",
                            championName,
                            playerInUCL and "您的球队已获得欧冠参赛补偿金 10.0M。" or ""
                        ),
                        priority = "normal",
                    })

                    log:Write(LOG_INFO, string.format(
                        "[UCL] 补偿迁移完成：回填上赛季冠军=%s, 玩家补偿=%s",
                        championName, playerInUCL and "10M" or "无"))
                end
            end
        end

        -- 标记已处理，防止重复执行
        gameState._uclOverwritePatched = true
    end

    if ChampionsLeague.repairStuckProgress(gameState) then
        return true
    end

    return false
end

------------------------------------------------------
-- 分档（4档×9队，按声望排序）
------------------------------------------------------

function ChampionsLeague._seedIntoPots(gameState, teamIds)
    -- 按声望排序
    local sorted = {}
    for _, tid in ipairs(teamIds) do
        local team = gameState.teams[tid]
        table.insert(sorted, { id = tid, rep = team and team.reputation or 0 })
    end
    table.sort(sorted, function(a, b) return a.rep > b.rep end)

    local pots = { {}, {}, {}, {} }
    for i, entry in ipairs(sorted) do
        local potIdx = math.min(4, math.ceil(i / 9))
        table.insert(pots[potIdx], entry.id)
    end
    return pots
end

------------------------------------------------------
-- 获取合格球队
------------------------------------------------------

function ChampionsLeague._getQualifiedTeams(gameState)
    local qualified = {}

    -- 上赛季历史记录
    local lastSeason = nil
    for _, record in ipairs(gameState.worldHistory or {}) do
        if record.season == gameState.season - 1 then
            lastSeason = record
            break
        end
    end

    if lastSeason and lastSeason.leagues then
        local uclSpots = ChampionsLeague.getUclSpots(gameState)
        for leagueKey, spots in pairs(uclSpots) do
            if not ChampionsLeague._isLeagueUclActive(gameState, leagueKey) then
                goto continue_hist_league
            end
            local leagueRecord = lastSeason.leagues[leagueKey]
            if leagueRecord and leagueRecord.standings then
                for i = 1, math.min(spots, #leagueRecord.standings) do
                    local teamId = leagueRecord.standings[i].teamId
                    if teamId and gameState.teams[teamId] then
                        table.insert(qualified, teamId)
                    end
                end
            end
            ::continue_hist_league::
        end
    end

    -- 首赛季（无历史）→ 按声望
    if #qualified == 0 then
        qualified = ChampionsLeague._getInitialQualifiers(gameState)
    end

    return qualified
end

--- 联赛是否已解锁欧冠席位（含「第2赛季起」规则）
function ChampionsLeague._isLeagueUclActive(gameState, leagueKey)
    if not UCL_SPOTS_FROM_SEASON_2[leagueKey] then
        return gameState.leagues[leagueKey] ~= nil
    end
    for _, record in ipairs(gameState.worldHistory or {}) do
        if record.leagues and record.leagues[leagueKey] then
            return true
        end
    end
    return false
end

-- 首赛季：按声望从各联赛选取
function ChampionsLeague._getInitialQualifiers(gameState)
    local qualified = {}
    local uclSpots = ChampionsLeague.getUclSpots(gameState)
    for leagueKey, spots in pairs(uclSpots) do
        if UCL_SPOTS_FROM_SEASON_2[leagueKey] then
            goto continue_league
        end
        local lg = gameState.leagues[leagueKey]
        if lg then
            local leagueTeams = {}
            for _, tid in ipairs(lg.teamIds) do
                local team = gameState.teams[tid]
                if team then
                    table.insert(leagueTeams, team)
                end
            end
            table.sort(leagueTeams, function(a, b)
                return (a.reputation or 0) > (b.reputation or 0)
            end)
            for i = 1, math.min(spots, #leagueTeams) do
                table.insert(qualified, leagueTeams[i].id)
            end
        end
        ::continue_league::
    end
    return qualified
end

-- 补充名额到 target 队
function ChampionsLeague._fillSlots(gameState, existing, target)
    local existingSet = {}
    for _, tid in ipairs(existing) do existingSet[tid] = true end

    local candidates = {}
    for leagueKey, lg in pairs(gameState.leagues) do
        if not ChampionsLeague._isLeagueUclActive(gameState, leagueKey) then
            goto continue_league_fill
        end
        for _, tid in ipairs(lg.teamIds) do
            if not existingSet[tid] then
                local team = gameState.teams[tid]
                if team then
                    table.insert(candidates, team)
                end
            end
        end
        ::continue_league_fill::
    end
    table.sort(candidates, function(a, b)
        return (a.reputation or 0) > (b.reputation or 0)
    end)

    local result = {}
    for _, tid in ipairs(existing) do table.insert(result, tid) end
    for _, team in ipairs(candidates) do
        if #result >= target then break end
        table.insert(result, team.id)
    end
    return result
end

------------------------------------------------------
-- 推进欧冠阶段
------------------------------------------------------

function ChampionsLeague.checkPhaseAdvance(gameState)
    local ucl = gameState.championsLeague
    if not ucl or ucl.phase == Tournament.PHASE_COMPLETED then return end

    -- 联赛阶段结束 → 生成附加赛
    if ucl.phase == Tournament.PHASE_LEAGUE and ucl:isLeaguePhaseComplete() then
        ChampionsLeague._advanceToPlayoff(gameState, ucl)
    end

    -- 附加赛结束 → 生成1/8决赛
    if ucl.phase == Tournament.PHASE_PLAYOFF and ucl:isKnockoutRoundComplete("playoff") then
        ChampionsLeague._advanceToR16(gameState, ucl)
    end

    -- 1/8决赛结束 → 1/4决赛
    if ucl.phase == Tournament.PHASE_R16 and ucl:isKnockoutRoundComplete("r16") then
        ChampionsLeague._advanceToQF(gameState, ucl)
    end

    -- 1/4决赛结束 → 半决赛
    if ucl.phase == Tournament.PHASE_QF and ucl:isKnockoutRoundComplete("qf") then
        ChampionsLeague._advanceToSF(gameState, ucl)
    end

    -- 半决赛结束 → 决赛
    if ucl.phase == Tournament.PHASE_SF and ucl:isKnockoutRoundComplete("sf") then
        ChampionsLeague._advanceToFinal(gameState, ucl)
    end

    -- 决赛结束 → 冠军
    if ucl.phase == Tournament.PHASE_FINAL and ucl:isKnockoutRoundComplete("final") then
        ChampionsLeague._completeTournament(gameState, ucl)
    end
end

------------------------------------------------------
-- 联赛阶段 → 附加赛（9-24名争8个16强席位）
------------------------------------------------------

function ChampionsLeague._advanceToPlayoff(gameState, ucl)
    local directR16, playoffTeams = ucl:getLeaguePhaseAdvancers()

    -- 存储直接晋级16强的球队
    ucl._directR16 = directR16

    -- 附加赛配对：9 vs 24, 10 vs 23, 11 vs 22, ... 16 vs 17
    -- 排名高的球队拥有次回合主场优势
    local matchups = {}
    for i = 1, 8 do
        local highSeed = playoffTeams[i]          -- 9-16名
        local lowSeed = playoffTeams[17 - i]      -- 17-24名
        if highSeed and lowSeed then
            table.insert(matchups, { lowSeed, highSeed })  -- 低排名先主场
        end
    end

    local startDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.playoff_start.month,
        day = UCL_SCHEDULE.playoff_start.day,
    }
    ucl:generateKnockoutRound("playoff", matchups, startDate)

    -- 新闻
    gameState:addNews({
        category = "ucl_news",
        title = "欧冠联赛阶段结束！附加赛对阵出炉",
        body = ChampionsLeague._formatPlayoffNews(gameState, ucl, directR16, matchups),
    })
end

------------------------------------------------------
-- 附加赛 → 1/8决赛
------------------------------------------------------

function ChampionsLeague._advanceToR16(gameState, ucl)
    local playoffWinners = ucl:getKnockoutWinners("playoff")
    local directR16 = ucl._directR16 or {}

    -- 16强对阵：联赛阶段前8（种子队）vs 附加赛8个胜者
    -- 种子队次回合主场
    local seeds = {}
    for _, tid in ipairs(directR16) do table.insert(seeds, tid) end

    -- 洗牌附加赛胜者
    local unseeded = {}
    for _, tid in ipairs(playoffWinners) do table.insert(unseeded, tid) end
    for i = #unseeded, 2, -1 do
        local j = RandomInt(1, i)
        unseeded[i], unseeded[j] = unseeded[j], unseeded[i]
    end

    local matchups = {}
    for i = 1, math.min(#seeds, #unseeded) do
        table.insert(matchups, { unseeded[i], seeds[i] })  -- 非种子先主场
    end

    local startDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.r16_start.month,
        day = UCL_SCHEDULE.r16_start.day,
    }
    ucl:generateKnockoutRound("r16", matchups, startDate)

    gameState:addNews({
        category = "ucl_news",
        title = "欧冠16强对阵出炉",
        body = ChampionsLeague._formatKnockoutDraw(gameState, matchups),
    })
end

------------------------------------------------------
-- 后续淘汰赛阶段
------------------------------------------------------

function ChampionsLeague._advanceToQF(gameState, ucl)
    local winners = ucl:getKnockoutWinners("r16")
    if #winners < 2 then return end

    for i = #winners, 2, -1 do
        local j = RandomInt(1, i)
        winners[i], winners[j] = winners[j], winners[i]
    end

    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, { winners[i], winners[i + 1] })
        end
    end

    local startDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.qf_start.month,
        day = UCL_SCHEDULE.qf_start.day,
    }
    ucl:generateKnockoutRound("qf", matchups, startDate)

    gameState:addNews({
        category = "ucl_news",
        title = "欧冠8强对阵抽签",
        body = ChampionsLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function ChampionsLeague._advanceToSF(gameState, ucl)
    local winners = ucl:getKnockoutWinners("qf")
    if #winners < 2 then return end

    for i = #winners, 2, -1 do
        local j = RandomInt(1, i)
        winners[i], winners[j] = winners[j], winners[i]
    end

    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, { winners[i], winners[i + 1] })
        end
    end

    local startDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.sf_start.month,
        day = UCL_SCHEDULE.sf_start.day,
    }
    ucl:generateKnockoutRound("sf", matchups, startDate)

    gameState:addNews({
        category = "ucl_news",
        title = "欧冠4强对阵确定",
        body = ChampionsLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function ChampionsLeague._advanceToFinal(gameState, ucl)
    local winners = ucl:getKnockoutWinners("sf")
    if #winners < 2 then return end

    local finalDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.final_date.month,
        day = UCL_SCHEDULE.final_date.day,
    }
    ucl:generateFinal({ winners[1], winners[2] }, finalDate)

    local team1 = gameState.teams[winners[1]]
    local team2 = gameState.teams[winners[2]]
    gameState:addNews({
        category = "ucl_news",
        title = "欧冠决赛对阵确定！",
        body = string.format("%s vs %s\n决赛日期: %d年%d月%d日",
            team1 and team1.name or "?",
            team2 and team2.name or "?",
            finalDate.year, finalDate.month, finalDate.day),
    })
end

function ChampionsLeague._completeTournament(gameState, ucl)
    local winners = ucl:getKnockoutWinners("final")
    if #winners > 0 then
        ucl.champion = winners[1]
        ucl.phase = Tournament.PHASE_COMPLETED

        local champion = gameState.teams[ucl.champion]
        gameState:addNews({
            category = "ucl_news",
            title = string.format("%s 赢得欧冠冠军!", champion and champion.name or "?"),
            body = string.format("%s 在 %d-%d 赛季欧洲冠军联赛中夺冠！",
                champion and champion.name or "?", ucl.season, ucl.season + 1),
        })

        -- 冠军奖金
        if champion then
            local prize = 40000000  -- 欧冠冠军总奖金 40M
            champion.balance = champion.balance + prize
            champion.transferBudget = (champion.transferBudget or 0) + prize
            champion.seasonIncome = (champion.seasonIncome or 0) + prize
            champion.incomeBreakdown = champion.incomeBreakdown or {}
            champion.incomeBreakdown.prize = (champion.incomeBreakdown.prize or 0) + prize
            FinanceManager.addTransaction(champion, {
                amount = prize,
                description = "欧冠冠军奖金",
                category = "prize",
                season = gameState.season,
                week = FinanceManager._getWeekNumber(gameState),
            })
        end

        -- 玩家球队
        if ucl.champion == gameState.playerTeamId then
            gameState:sendMessage({
                category = "league",
                title = "恭喜！欧冠冠军！",
                body = "你的球队赢得了欧洲冠军联赛！这是足坛最高荣誉！\n冠军奖金 40.0M 已到账。",
                priority = "high",
            })
        end

        -- 声望更新：冠军
        ReputationManager.cupResultUpdate(gameState, ucl.champion, true)

        -- 亚军处理
        local finalFixture = ucl.knockout.final and ucl.knockout.final[1]
        if finalFixture then
            local finalistId = (finalFixture.homeTeamId == ucl.champion) and finalFixture.awayTeamId or finalFixture.homeTeamId
            ucl.finalist = finalistId

            -- 亚军奖金
            local finalist = gameState.teams[finalistId]
            if finalist then
                local runnerUpPrize = 20000000  -- 欧冠亚军奖金 20M
                finalist.balance = finalist.balance + runnerUpPrize
                finalist.transferBudget = (finalist.transferBudget or 0) + runnerUpPrize
                finalist.seasonIncome = (finalist.seasonIncome or 0) + runnerUpPrize
                finalist.incomeBreakdown = finalist.incomeBreakdown or {}
                finalist.incomeBreakdown.prize = (finalist.incomeBreakdown.prize or 0) + runnerUpPrize
                FinanceManager.addTransaction(finalist, {
                    amount = runnerUpPrize,
                    description = "欧冠亚军奖金",
                    category = "prize",
                    season = gameState.season,
                    week = FinanceManager._getWeekNumber(gameState),
                })
            end

            -- 声望更新：亚军
            ReputationManager.cupResultUpdate(gameState, finalistId, false)

            -- 玩家球队是亚军
            if finalistId == gameState.playerTeamId then
                gameState:sendMessage({
                    category = "league",
                    title = "欧冠决赛惜败",
                    body = "你的球队在欧冠决赛中惜败，获得亚军。\n虽然遗憾，但这已经是伟大的征程！\n亚军奖金 3.0M 已到账。",
                    priority = "high",
                })
            end
        end

        -- 记录系统：UCL 夺冠
        RecordsManager.onUCLChampionship(gameState, ucl.champion)

        -- 标记本赛季 UCL 已正常完成（用于存档迁移检测）
        gameState._uclCompletedSeasons = gameState._uclCompletedSeasons or {}
        gameState._uclCompletedSeasons[tostring(ucl.season)] = ucl.champion

        EventBus.emit("ucl_completed", ucl.champion)
    end
end

------------------------------------------------------
-- 新闻格式化
------------------------------------------------------

function ChampionsLeague._formatLeagueDrawResult(gameState, ucl)
    local lp = ucl.leaguePhase
    if not lp then return "抽签完成" end

    local lines = { "欧冠联赛阶段（36队瑞士制）:\n" }
    local potNames = { "第一档", "第二档", "第三档", "第四档" }

    for i, pot in ipairs(lp.pots) do
        table.insert(lines, "【" .. potNames[i] .. "】")
        local names = {}
        for _, tid in ipairs(pot) do
            local team = gameState.teams[tid]
            table.insert(names, team and team.name or "?")
        end
        table.insert(lines, "  " .. table.concat(names, "、"))
        table.insert(lines, "")
    end

    table.insert(lines, "每队将进行8场比赛（4主4客），争夺36队单一积分榜排名。")
    table.insert(lines, "前8名直接晋级16强，9-24名进入附加赛，25-36名淘汰。")
    return table.concat(lines, "\n")
end

function ChampionsLeague._formatPlayoffNews(gameState, ucl, directR16, matchups)
    local lines = { "直接晋级16强:" }
    for i, tid in ipairs(directR16) do
        local team = gameState.teams[tid]
        table.insert(lines, string.format("  %d. %s", i, team and team.name or "?"))
    end
    table.insert(lines, "\n附加赛对阵:")
    for i, m in ipairs(matchups) do
        local t1 = gameState.teams[m[1]]
        local t2 = gameState.teams[m[2]]
        table.insert(lines, string.format("  %d. %s vs %s", i, t1 and t1.name or "?", t2 and t2.name or "?"))
    end
    return table.concat(lines, "\n")
end

function ChampionsLeague._formatKnockoutDraw(gameState, matchups)
    local lines = {}
    for i, m in ipairs(matchups) do
        local t1 = gameState.teams[m[1]]
        local t2 = gameState.teams[m[2]]
        table.insert(lines, string.format("%d. %s vs %s",
            i, t1 and t1.name or "?", t2 and t2.name or "?"))
    end
    return table.concat(lines, "\n")
end

return ChampionsLeague
