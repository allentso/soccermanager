-- systems/domestic_cup.lua
-- 国内杯赛管理（足总杯、国王杯等）
-- 纯淘汰制，单场定胜负（平局 → 加时 → 点球）

local League = require("scripts/domain/league")
local Tournament = require("scripts/domain/tournament")
local EventBus = require("scripts/app/event_bus")
local RealDataLoader = require("scripts/data/real_data_loader")

local DomesticCup = {}

local function _cupDateKey(date)
    if type(date) ~= "table" then return nil end
    local y = tonumber(date.year)
    local m = tonumber(date.month)
    local d = tonumber(date.day)
    if not y or not m or not d then return nil end
    return string.format("%04d-%02d-%02d", y, m, d)
end

local function _cupDateBefore(a, b)
    if a.year ~= b.year then return a.year < b.year end
    if a.month ~= b.month then return a.month < b.month end
    return a.day < b.day
end

function DomesticCup.invalidateFixtureCaches(gameState)
    if not gameState then return end
    gameState._domesticCupFixtureDateIndex = nil
    gameState._domesticCupScheduledMeta = nil
end

function DomesticCup._ensureCupFixtureDateIndex(gameState)
    if gameState._domesticCupFixtureDateIndex then
        return gameState._domesticCupFixtureDateIndex
    end

    local index = {}
    for leagueKey, cup in pairs(gameState.domesticCups or {}) do
        local cupKey = cup.leagueKey or leagueKey
        for _, roundFixtures in ipairs(cup.rounds or {}) do
            for _, f in ipairs(roundFixtures) do
                f._cupLeague = f._cupLeague or cupKey
                local key = f.date and _cupDateKey(f.date)
                if key then
                    local bucket = index[key]
                    if not bucket then
                        bucket = {}
                        index[key] = bucket
                    end
                    bucket[#bucket + 1] = f
                end
            end
        end
    end
    gameState._domesticCupFixtureDateIndex = index
    return index
end

local function _ensureCupScheduledMeta(gameState)
    if gameState._domesticCupScheduledMeta then
        return gameState._domesticCupScheduledMeta
    end

    local meta = { anyOverduePossible = false, earliestDate = nil, scheduledCount = 0 }
    for _, cup in pairs(gameState.domesticCups or {}) do
        if cup.phase == "completed" then goto next_cup end
        for _, roundFixtures in ipairs(cup.rounds or {}) do
            for _, fixture in ipairs(roundFixtures) do
                if fixture.status == "scheduled" and fixture.date then
                    meta.scheduledCount = meta.scheduledCount + 1
                    if not meta.earliestDate or _cupDateBefore(fixture.date, meta.earliestDate) then
                        meta.earliestDate = {
                            year = fixture.date.year,
                            month = fixture.date.month,
                            day = fixture.date.day,
                        }
                    end
                end
            end
        end
        ::next_cup::
    end
    gameState._domesticCupScheduledMeta = meta
    return meta
end

local function _cupMayHaveOverdueFixtures(meta, currentDate)
    if not meta or meta.scheduledCount <= 0 or not meta.earliestDate then
        return false
    end
    return _cupDateBefore(meta.earliestDate, currentDate)
end

function DomesticCup._invalidateCupScheduledMeta(gameState)
    if not gameState then return end
    gameState._domesticCupScheduledMeta = nil
end
DomesticCup.CUP_CONFIG = {
    EPL = {
        name = "足总杯",
        shortName = "FA Cup",
        -- 杯赛首轮日期（周二）
        firstRoundMonth = 9,
        firstRoundDay = 24,
        -- 各轮间隔天数（给联赛和欧冠让路）
        roundIntervalDays = 28, -- 每轮间隔约4周
        -- 决赛固定日期
        finalMonth = 5,
        finalDay = 17,
    },
    LaLiga = {
        name = "国王杯",
        shortName = "Copa del Rey",
        firstRoundMonth = 10,
        firstRoundDay = 1,
        roundIntervalDays = 28,
        finalMonth = 5,
        finalDay = 10,
    },
    SerieA = {
        name = "意大利杯",
        shortName = "Coppa Italia",
        firstRoundMonth = 9,
        firstRoundDay = 24,
        roundIntervalDays = 35, -- 意大利杯间隔更大（种子队后进场）
        finalMonth = 5,
        finalDay = 14,
    },
    Bundesliga = {
        name = "德国杯",
        shortName = "DFB-Pokal",
        firstRoundMonth = 10,
        firstRoundDay = 1,
        roundIntervalDays = 35,
        finalMonth = 5,
        finalDay = 24,
    },
    Ligue1 = {
        name = "法国杯",
        shortName = "Coupe de France",
        firstRoundMonth = 10,
        firstRoundDay = 8,
        roundIntervalDays = 35,
        finalMonth = 5,
        finalDay = 7,
    },
    CSL = {
        name = "足协杯",
        shortName = "CFA Cup",
        firstRoundMonth = 9,
        firstRoundDay = 24,
        roundIntervalDays = 28,
        finalMonth = 5,
        finalDay = 10,
    },
}

------------------------------------------------------
-- 参赛球队收集（含已加载次级联赛）
------------------------------------------------------

function DomesticCup._resolveParentCupKey(gameState, leagueKey)
    if RealDataLoader.isSecondDivisionKey(leagueKey) then
        local lg = gameState.leagues and gameState.leagues[leagueKey]
        if lg and lg.parentLeague then
            return lg.parentLeague
        end
    end
    return leagueKey
end

function DomesticCup._collectCupTeamIds(gameState, leagueKey, lg)
    local teamIds = {}
    local seen = {}

    local function addTeam(tid)
        if not tid or seen[tid] then return end
        seen[tid] = true
        table.insert(teamIds, tid)
    end

    for _, tid in ipairs(lg.teamIds or {}) do
        addTeam(tid)
    end

    local childKey = RealDataLoader.getChildLeagueKey(leagueKey)
    if childKey then
        local childLg = gameState.leagues and gameState.leagues[childKey]
        if childLg then
            for _, tid in ipairs(childLg.teamIds or {}) do
                addTeam(tid)
            end
        end
    end

    return teamIds
end

--- 按声望排序（高声望优先轮空）
function DomesticCup._sortTeamsByReputation(gameState, teamIds)
    local sorted = {}
    for _, tid in ipairs(teamIds) do
        local team = gameState.teams[tid]
        table.insert(sorted, { id = tid, rep = team and team.reputation or 0 })
    end
    table.sort(sorted, function(a, b) return a.rep > b.rep end)
    local result = {}
    for _, entry in ipairs(sorted) do
        table.insert(result, entry.id)
    end
    return result
end

------------------------------------------------------
-- 初始化本赛季杯赛（所有联赛）
------------------------------------------------------

function DomesticCup.initialize(gameState)
    gameState.domesticCups = {}
    DomesticCup.invalidateFixtureCaches(gameState)

    for leagueKey, lg in pairs(gameState.leagues) do
        local config = DomesticCup.CUP_CONFIG[leagueKey]
        if config then
            local cup = DomesticCup._initializeCup(gameState, leagueKey, lg, config)
            if cup then
                gameState.domesticCups[leagueKey] = cup
            end
        end
    end
end

--- 初始化单个杯赛
function DomesticCup._initializeCup(gameState, leagueKey, lg, config)
    local teamIds = DomesticCup._sortTeamsByReputation(
        gameState, DomesticCup._collectCupTeamIds(gameState, leagueKey, lg))

    local n = #teamIds
    if n < 4 then return nil end

    -- 高声望球队优先轮空：按声望排序后，末尾低声望队先打第一轮

    -- 计算需要多少轮
    -- 向上取 2 的幂: 20队 → 需要先打一轮让 12 队晋级（变成 16 队 → 再3轮）
    -- 简化方案：20队 → 第1轮 12 场（4队轮空直接进下一轮）→ 16队 → 8 → 4 → 2 → 决赛
    local totalRounds = math.ceil(math.log(n) / math.log(2))
    local targetFirstRound = 2 ^ (totalRounds - 1) -- 第一轮结束后留下多少队
    local firstRoundMatches = n - targetFirstRound
    local byeCount = targetFirstRound - firstRoundMatches -- 轮空队数

    -- 生成第一轮对阵
    local round1Fixtures = {}
    local fixtureId = 1
    local season = gameState.season

    -- 计算第一轮日期（对齐到周二）
    local roundDate = League._alignToWeekday({
        year = season,
        month = config.firstRoundMonth,
        day = config.firstRoundDay,
    }, 2) -- 2=周二

    -- 检测并避让洲际赛事周（欧冠周三 / 欧联周四）
    roundDate = DomesticCup._avoidContinentalWeek(gameState, roundDate)

    -- 前 firstRoundMatches*2 支队伍参加第一轮
    local matchTeams = {}
    for i = 1, firstRoundMatches * 2 do
        table.insert(matchTeams, teamIds[i])
    end

    -- 剩余队伍轮空直接进第二轮
    local byeTeams = {}
    for i = firstRoundMatches * 2 + 1, n do
        table.insert(byeTeams, teamIds[i])
    end

    for i = 1, firstRoundMatches do
        local home = matchTeams[(i - 1) * 2 + 1]
        local away = matchTeams[(i - 1) * 2 + 2]
        table.insert(round1Fixtures, {
            id = leagueKey .. "_cup_r1_" .. fixtureId,
            round = 1,
            homeTeamId = home,
            awayTeamId = away,
            date = { year = roundDate.year, month = roundDate.month, day = roundDate.day },
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            isKnockout = true,
            _isDomesticCup = true,
            _cupLeague = leagueKey,
        })
        fixtureId = fixtureId + 1
    end

    local cup = {
        leagueKey = leagueKey,
        name = config.name,
        shortName = config.shortName,
        season = season,
        phase = "round_1", -- round_1, round_2, ..., final, completed
        totalRounds = totalRounds,
        currentRound = 1,
        config = config,
        -- 各轮 fixture
        rounds = { round1Fixtures },
        -- 轮空队伍（进入第二轮）
        byeTeams = byeTeams,
        -- 各轮日期
        roundDates = { roundDate },
        -- 冠军
        winner = nil,
    }

    return cup
end

------------------------------------------------------
-- 避让洲际赛事周（杯赛周二，若次日周三有欧冠或周四有欧联则推迟一周）
------------------------------------------------------
function DomesticCup._avoidContinentalWeek(gameState, date)
    local wednesday = League._addDays(date, 1)
    local thursday = League._addDays(date, 2)

    local function hasFixtureOn(tournament, targetDate)
        if not tournament or tournament.phase == "completed" then return false end
        local fixtures = tournament:getFixturesForDate(targetDate)
        return fixtures and #fixtures > 0
    end

    if hasFixtureOn(gameState.championsLeague, wednesday)
        or hasFixtureOn(gameState.europaLeague, thursday) then
        return League._addDays(date, 7)
    end

    return date
end

--- 兼容旧调用
function DomesticCup._avoidUCLWeek(gameState, date)
    return DomesticCup._avoidContinentalWeek(gameState, date)
end

------------------------------------------------------
-- 存档迁移：旧存档无杯赛数据时，延迟初始化（仅首次触发）
-- 初始化后会自动模拟所有过期比赛（含玩家比赛），避免突然弹出大量比赛
------------------------------------------------------
function DomesticCup.migrateIfNeeded(gameState)
    if gameState.domesticCups then return end
    if not gameState.leagues then return end

    -- 初始化杯赛
    DomesticCup.initialize(gameState)
    print("[DomesticCup] Migration: initialized cups for existing save (season " .. tostring(gameState.season) .. ")")

    -- 自动模拟所有过期比赛（包括玩家的），让杯赛追赶到当前进度
    local currentDate = gameState.date
    local MatchEngine = require("scripts/match/match_engine")
    local simulatedCount = 0

    -- 循环模拟直到没有过期比赛（因为模拟完一轮后 checkPhaseAdvance 会生成下一轮）
    for _ = 1, 20 do -- 安全上限，防止无限循环
        local hasOverdue = false
        for _, cup in pairs(gameState.domesticCups) do
            if cup.phase == "completed" then goto skip_cup end
            for _, roundFixtures in ipairs(cup.rounds) do
                for _, fixture in ipairs(roundFixtures) do
                    if fixture.status == "scheduled" and fixture.date then
                        local isBefore = false
                        if fixture.date.year < currentDate.year then isBefore = true
                        elseif fixture.date.year == currentDate.year then
                            if fixture.date.month < currentDate.month then isBefore = true
                            elseif fixture.date.month == currentDate.month then
                                isBefore = fixture.date.day < currentDate.day
                            end
                        end
                        if isBefore then
                            hasOverdue = true
                            fixture._isDomesticCup = true
                            fixture._cupLeague = cup.leagueKey
                            local report = MatchEngine.simulate(gameState, fixture)
                            if report then
                                DomesticCup.applyResult(gameState, fixture, report)
                                simulatedCount = simulatedCount + 1
                            end
                        end
                    end
                end
            end
            ::skip_cup::
        end

        -- 推进阶段（生成下一轮）
        DomesticCup.checkPhaseAdvance(gameState)

        if not hasOverdue then break end
    end

    if simulatedCount > 0 then
        print("[DomesticCup] Migration: auto-simulated " .. simulatedCount .. " overdue fixtures")
    end
    DomesticCup.invalidateFixtureCaches(gameState)
end

------------------------------------------------------
-- 获取指定日期的杯赛比赛
------------------------------------------------------
function DomesticCup.getFixturesForDate(gameState, date)
    local result = {}
    local cups = gameState.domesticCups
    if not cups then return result end

    local key = _cupDateKey(date)
    if not key then return result end

    local bucket = DomesticCup._ensureCupFixtureDateIndex(gameState)[key]
    if not bucket then return result end

    for _, f in ipairs(bucket) do
        if f.status == "scheduled" then
            local cupKey = f._cupLeague
            local cup = cupKey and cups[cupKey]
            if cup and cup.phase ~= "completed" then
                f._isDomesticCup = true
                table.insert(result, f)
            end
        end
    end
    return result
end

------------------------------------------------------
-- 应用杯赛比赛结果
------------------------------------------------------
function DomesticCup.applyResult(gameState, fixture, report)
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"
    DomesticCup._invalidateCupScheduledMeta(gameState)
    gameState._domesticCupFixtureDateIndex = nil

    -- 存储加时/点球数据
    if report.extraTime then
        fixture.extraTime = report.extraTime
        local pen = report.extraTime.penalties
        if pen then
            fixture.penalties = {
                homeScore = pen.homeScore or pen.homeScored,
                awayScore = pen.awayScore or pen.awayScored,
                winner = pen.winner,
            }
            fixture._penaltyWinner = pen.winner
        end
    end

    -- 更新球员出场/进球等统计
    local PlaceholderEngine = require("scripts/match/placeholder_engine")
    PlaceholderEngine.applyPlayerMatchStats(gameState, fixture, report)
end

------------------------------------------------------
-- 检查阶段推进（每轮比赛全部完成后推进到下一轮）
------------------------------------------------------
function DomesticCup.checkPhaseAdvance(gameState)
    local cups = gameState.domesticCups
    if not cups then return end

    for leagueKey, cup in pairs(cups) do
        if cup.phase ~= "completed" then
            DomesticCup._checkCupAdvance(gameState, cup)
        end
    end
end

function DomesticCup._checkCupAdvance(gameState, cup)
    local currentRound = cup.currentRound
    local roundFixtures = cup.rounds[currentRound]
    if not roundFixtures then return end

    -- 检查当前轮次是否全部完成
    for _, f in ipairs(roundFixtures) do
        if f.status ~= "finished" then
            return -- 还有比赛没打完
        end
    end

    -- 收集晋级者
    local winners = {}
    for _, f in ipairs(roundFixtures) do
        local winnerId
        if f._penaltyWinner then
            winnerId = f._penaltyWinner
        elseif (f.homeGoals or 0) > (f.awayGoals or 0) then
            winnerId = f.homeTeamId
        elseif (f.awayGoals or 0) > (f.homeGoals or 0) then
            winnerId = f.awayTeamId
        else
            -- 常规时间平局但无点球记录（不应发生），默认主场晋级
            winnerId = f.homeTeamId
        end
        table.insert(winners, winnerId)
    end

    -- 第一轮结束后，加入轮空队伍
    if currentRound == 1 and cup.byeTeams and #cup.byeTeams > 0 then
        for _, tid in ipairs(cup.byeTeams) do
            table.insert(winners, tid)
        end
        cup.byeTeams = {} -- 清空
    end

    -- 如果只剩 1 支队伍 → 杯赛冠军
    if #winners == 1 then
        cup.winner = winners[1]
        cup.phase = "completed"
        DomesticCup._announceWinner(gameState, cup)
        return
    end

    -- 如果只剩 2 支队伍 → 决赛
    if #winners == 2 then
        cup.currentRound = currentRound + 1
        cup.phase = "final"
        local finalFixtures = DomesticCup._generateNextRound(gameState, cup, winners, true)
        table.insert(cup.rounds, finalFixtures)
        return
    end

    -- 生成下一轮对阵
    cup.currentRound = currentRound + 1
    cup.phase = "round_" .. cup.currentRound
    local nextFixtures = DomesticCup._generateNextRound(gameState, cup, winners, false)
    table.insert(cup.rounds, nextFixtures)
end

------------------------------------------------------
-- 生成下一轮对阵
------------------------------------------------------
function DomesticCup._generateNextRound(gameState, cup, teamIds, isFinal)
    local config = cup.config
    local roundNum = cup.currentRound
    local fixtures = {}

    -- 打乱顺序（重新抽签）
    for i = #teamIds, 2, -1 do
        local j = RandomInt(1, i)
        teamIds[i], teamIds[j] = teamIds[j], teamIds[i]
    end

    -- 计算日期
    local roundDate
    if isFinal then
        -- 决赛使用固定日期
        roundDate = League._alignToWeekday({
            year = cup.season + 1, -- 决赛在次年5月
            month = config.finalMonth,
            day = config.finalDay,
        }, 2) -- 周二
    else
        -- 普通轮次：上一轮日期 + 间隔
        local prevDate = cup.roundDates[#cup.roundDates]
        roundDate = League._addDays(prevDate, config.roundIntervalDays)
        roundDate = League._alignToWeekday(roundDate, 2) -- 对齐到周二
        -- 避让洲际赛事周
        roundDate = DomesticCup._avoidContinentalWeek(gameState, roundDate)
    end
    table.insert(cup.roundDates, roundDate)

    -- 生成对阵
    local numMatches = math.floor(#teamIds / 2)
    for i = 1, numMatches do
        local home = teamIds[(i - 1) * 2 + 1]
        local away = teamIds[(i - 1) * 2 + 2]
        table.insert(fixtures, {
            id = cup.leagueKey .. "_cup_r" .. roundNum .. "_" .. i,
            round = roundNum,
            homeTeamId = home,
            awayTeamId = away,
            date = { year = roundDate.year, month = roundDate.month, day = roundDate.day },
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            isKnockout = true,
            _isDomesticCup = true,
            _cupLeague = cup.leagueKey,
        })
    end

    return fixtures
end

------------------------------------------------------
-- 从已完成轮次中查找决赛对手
------------------------------------------------------
function DomesticCup._getFinalistId(cup, winnerId)
    for i = #(cup.rounds or {}), 1, -1 do
        for _, f in ipairs(cup.rounds[i]) do
            if f.status == "finished" then
                if f.homeTeamId == winnerId then return f.awayTeamId end
                if f.awayTeamId == winnerId then return f.homeTeamId end
            end
        end
    end
    return nil
end

------------------------------------------------------
-- 冠军公告
------------------------------------------------------
function DomesticCup._announceWinner(gameState, cup)
    local team = gameState.teams[cup.winner]
    local teamName = team and team.name or "未知"

    gameState:addNews({
        category = "cup_news",
        title = string.format("%s冠军: %s!", cup.name, teamName),
        body = string.format("%s 赢得了 %d 赛季 %s 冠军！", teamName, tonumber(cup.season) or 0, cup.name),
    })

    -- 记录奖杯（仅玩家球队触发 RecordsManager）
    local RecordsManager = require("scripts/systems/records_manager")
    RecordsManager.onDomesticCupChampionship(gameState, cup.name, cup.winner)

    -- 声望：冠军 / 亚军
    local ReputationManager = require("scripts/systems/reputation_manager")
    ReputationManager.cupResultUpdate(gameState, cup.winner, true)
    local finalistId = DomesticCup._getFinalistId(cup, cup.winner)
    if finalistId then
        ReputationManager.cupResultUpdate(gameState, finalistId, false)
    end

    -- 如果是玩家球队
    if cup.winner == gameState.playerTeamId then
        gameState:sendMessage({
            category = "achievement",
            title = cup.name .. " 冠军！",
            body = string.format("恭喜！你的球队赢得了 %s 冠军！\n这是一个伟大的成就！", cup.name),
            priority = "high",
        })
        -- 奖金
        local FinanceManager = require("scripts/systems/finance_manager")
        local prize = 5000000 -- 500万杯赛冠军奖金
        FinanceManager.addIncome(gameState, gameState.playerTeamId, prize, cup.name .. "冠军奖金", "prize")
    end
end

------------------------------------------------------
-- 判断所有杯赛是否已完成
------------------------------------------------------
function DomesticCup.allCompleted(gameState)
    local cups = gameState.domesticCups
    if not cups then return true end

    for _, cup in pairs(cups) do
        if cup.phase ~= "completed" then
            return false
        end
    end
    return true
end

------------------------------------------------------
-- 判断玩家是否还在杯赛中（用于 UI 展示）
------------------------------------------------------
function DomesticCup.isPlayerInCup(gameState)
    local cups = gameState.domesticCups
    if not cups or not gameState.playerTeamId then return false end

    local playerLeagueKey = nil
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds or {}) do
            if tid == gameState.playerTeamId then
                playerLeagueKey = leagueKey
                break
            end
        end
        if playerLeagueKey then break end
    end

    if not playerLeagueKey then return false end

    local cupKey = DomesticCup._resolveParentCupKey(gameState, playerLeagueKey)
    local cup = cups[cupKey]
    if not cup or cup.phase == "completed" then return false end

    -- 检查玩家是否还在当前轮次或轮空队中
    local roundFixtures = cup.rounds[cup.currentRound]
    if roundFixtures then
        for _, f in ipairs(roundFixtures) do
            if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
                return true
            end
        end
    end
    -- 检查轮空
    if cup.byeTeams then
        for _, tid in ipairs(cup.byeTeams) do
            if tid == gameState.playerTeamId then return true end
        end
    end
    return false
end

------------------------------------------------------
-- 补救过期杯赛比赛
------------------------------------------------------
function DomesticCup.catchUpOverdueFixtures(gameState, currentDate)
    local cups = gameState.domesticCups
    if not cups then return {} end

    local scheduledMeta = _ensureCupScheduledMeta(gameState)
    if not _cupMayHaveOverdueFixtures(scheduledMeta, currentDate) then
        return {}
    end

    local playerTeamId = gameState.playerTeamId
    local playerOverdue = {}
    local MatchEngine = require("scripts/match/match_engine")
    local simulatedAny = false

    for _, cup in pairs(cups) do
        if cup.phase == "completed" then goto next_cup end

        for _, roundFixtures in ipairs(cup.rounds) do
            for _, fixture in ipairs(roundFixtures) do
                if fixture.status == "scheduled" and fixture.date then
                    if not _cupDateBefore(fixture.date, currentDate) then goto continue_fixture end

                    fixture._isDomesticCup = true
                    fixture._cupLeague = cup.leagueKey
                    local isPlayerMatch = playerTeamId and
                        (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)

                    if isPlayerMatch and not gameState._cheatAutoPlay then
                        fixture._pendingPlayerMatch = true
                        table.insert(playerOverdue, fixture)
                    else
                        local report = MatchEngine.simulate(gameState, fixture)
                        if report then
                            DomesticCup.applyResult(gameState, fixture, report)
                            simulatedAny = true
                        end
                    end
                end
                ::continue_fixture::
            end
        end

        ::next_cup::
    end

    if simulatedAny or #playerOverdue > 0 then
        DomesticCup.checkPhaseAdvance(gameState)
    end

    return playerOverdue
end

------------------------------------------------------
-- 判断指定 fixture 是否是玩家的杯赛比赛
------------------------------------------------------
function DomesticCup.isPlayerCupMatch(gameState, fixture)
    if not fixture._isDomesticCup then return false end
    local playerTeamId = gameState.playerTeamId
    return playerTeamId and (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)
end

------------------------------------------------------
-- 序列化（存档用）
------------------------------------------------------
function DomesticCup.serialize(gameState)
    local cups = gameState.domesticCups
    if not cups then return nil end

    local data = {}
    for leagueKey, cup in pairs(cups) do
        data[leagueKey] = {
            leagueKey = cup.leagueKey,
            name = cup.name,
            shortName = cup.shortName,
            season = cup.season,
            phase = cup.phase,
            totalRounds = cup.totalRounds,
            currentRound = cup.currentRound,
            config = cup.config,
            rounds = cup.rounds,
            byeTeams = cup.byeTeams,
            roundDates = cup.roundDates,
            winner = cup.winner,
        }
    end
    return data
end

------------------------------------------------------
-- 反序列化（读档用）
------------------------------------------------------
function DomesticCup.deserialize(gameState, data)
    if not data then
        gameState.domesticCups = nil
        return
    end
    gameState.domesticCups = data
end

return DomesticCup
