-- domain/tournament.lua
-- 锦标赛数据模型（联赛阶段/小组赛 + 淘汰赛，用于欧冠/世界杯）

local League = require("scripts/domain/league")

local Tournament = {}
Tournament.__index = Tournament

-- 赛事阶段
Tournament.PHASE_NOT_STARTED = "not_started"
Tournament.PHASE_GROUP = "group"             -- 传统小组赛（世界杯用）
Tournament.PHASE_LEAGUE = "league"           -- 联赛阶段（瑞士制，欧冠2024+用）
Tournament.PHASE_PLAYOFF = "playoff"         -- 附加赛（欧冠9-24名争8个16强名额）
Tournament.PHASE_R16 = "r16"
Tournament.PHASE_QF = "qf"
Tournament.PHASE_SF = "sf"
Tournament.PHASE_FINAL = "final"
Tournament.PHASE_COMPLETED = "completed"

function Tournament.new(data)
    local self = setmetatable({}, Tournament)
    self.id = data.id or 1
    self.name = data.name or "Champions League"
    self.shortName = data.shortName or "UCL"
    self.type = data.type or "ucl"  -- "ucl" / "world_cup"
    self.season = tonumber(data.season) or 2024

    -- 阶段
    self.phase = data.phase or Tournament.PHASE_NOT_STARTED

    -- 参赛球队ID
    self.qualifiedTeams = data.qualifiedTeams or {}

    -- 小组赛（传统模式，key为组名 A/B/C/D...）
    self.groups = data.groups or {}

    -- 修复：小组赛standings的key类型问题（同上）
    if self.groups then
        for _, group in pairs(self.groups) do
            if group.standings then
                local normalized = {}
                for k, v in pairs(group.standings) do
                    local numKey = tonumber(k)
                    normalized[numKey or k] = v
                end
                group.standings = normalized
            end
        end
    end

    -- 联赛阶段（瑞士制，欧冠新赛制）
    self.leaguePhase = data.leaguePhase or nil

    -- 修复：JSON反序列化后standings的key从数字变为字符串的问题
    -- cjson将对象key统一转为字符串，但fixture.homeTeamId/awayTeamId作为值仍是数字
    -- 导致 standings[numericId] 查找失败
    if self.leaguePhase and self.leaguePhase.standings then
        local normalized = {}
        for k, v in pairs(self.leaguePhase.standings) do
            local numKey = tonumber(k)
            normalized[numKey or k] = v
        end
        self.leaguePhase.standings = normalized
    end

    -- 淘汰赛
    self.knockout = data.knockout or {
        playoff = {},
        r32 = {},
        r16 = {},
        qf = {},
        sf = {},
        final = {},
    }

    -- 冠军
    self.champion = data.champion or nil

    -- 联赛阶段直接晋级16强的球队（附加赛阶段使用）
    self._directR16 = data._directR16 or nil

    return self
end

------------------------------------------------------
-- 联赛阶段（瑞士制 - 2024/25 欧冠新赛制）
------------------------------------------------------

--- 默认瑞士制联赛阶段配置（欧冠 36 队）
Tournament.DEFAULT_LEAGUE_PHASE_CONFIG = {
    matchdays = 8,
    opponentsPerPot = 2,
    directAdvanceCount = 8,
    playoffStartRank = 9,
    playoffEndRank = 24,
    weekday = 3,       -- 周三
    dayInterval = 14,
}

--- 欧联杯 24 队小瑞士制配置
Tournament.UEL_LEAGUE_PHASE_CONFIG = {
    matchdays = 6,
    opponentsPerPot = 2,
    directAdvanceCount = 8,
    playoffStartRank = 9,
    playoffEndRank = 24,
    weekday = 4,       -- 周四
    dayInterval = 14,
}

--- 初始化联赛阶段（瑞士制）
---@param teamIds string[] 参赛球队ID
---@param pots table 分档 {{...},{...},...}
---@param config table|nil 可选：matchdays, opponentsPerPot, directAdvanceCount, playoffStartRank, playoffEndRank, weekday, dayInterval
function Tournament:initLeaguePhase(teamIds, pots, config)
    config = config or Tournament.DEFAULT_LEAGUE_PHASE_CONFIG
    self.leaguePhase = {
        teamIds = teamIds,
        pots = pots,
        standings = {},   -- teamId → 积分数据
        fixtures = {},    -- 所有联赛阶段比赛
        matchdays = config.matchdays or 8,
        opponentsPerPot = config.opponentsPerPot or 2,
        directAdvanceCount = config.directAdvanceCount or 8,
        playoffStartRank = config.playoffStartRank or 9,
        playoffEndRank = config.playoffEndRank or 24,
        weekday = config.weekday or 3,
        dayInterval = config.dayInterval or 14,
    }

    -- 初始化积分榜
    for _, tid in ipairs(teamIds) do
        self.leaguePhase.standings[tid] = {
            teamId = tid,
            played = 0,
            wins = 0,
            draws = 0,
            losses = 0,
            goalsFor = 0,
            goalsAgainst = 0,
            goalDifference = 0,
            points = 0,
        }
    end

    self.phase = Tournament.PHASE_LEAGUE
end

--- 瑞士制抽签：每队从每档抽 opponentsPerPot 个对手（主客交替），共 matchdays 场
--- 返回 teamOpponents 或 nil（配对失败时重试）
local function _buildLeaguePhaseOpponents(teamIds, pots, opponentsPerPot)
    opponentsPerPot = opponentsPerPot or 2
    local numPots = #pots
    local expectedMatches = numPots * opponentsPerPot

    local teamOpponents = {}
    local potOppCount = {}
    for _, tid in ipairs(teamIds) do
        teamOpponents[tid] = {}
        potOppCount[tid] = {}
        for p = 1, numPots do
            potOppCount[tid][p] = 0
        end
    end

    local teamPot = {}
    for potIdx, pot in ipairs(pots) do
        for _, tid in ipairs(pot) do
            teamPot[tid] = potIdx
        end
    end

    local pairedSet = {}

    local function isPaired(t1, t2)
        return pairedSet[t1 .. "_" .. t2] or pairedSet[t2 .. "_" .. t1]
    end
    local function markPaired(t1, t2)
        pairedSet[t1 .. "_" .. t2] = true
        pairedSet[t2 .. "_" .. t1] = true
    end

    local function addPairFromPot(tid, cid, potIdx)
        local tidPot = teamPot[tid]
        markPaired(tid, cid)
        local isHomeForTid = (potOppCount[tid][potIdx] == 0)
        table.insert(teamOpponents[tid], { opId = cid, isHome = isHomeForTid })
        table.insert(teamOpponents[cid], { opId = tid, isHome = not isHomeForTid })
        potOppCount[tid][potIdx] = potOppCount[tid][potIdx] + 1
        potOppCount[cid][tidPot] = potOppCount[cid][tidPot] + 1
    end

    local processOrder = {}
    for _, tid in ipairs(teamIds) do
        table.insert(processOrder, tid)
    end
    for i = #processOrder, 2, -1 do
        local j = RandomInt(1, i)
        processOrder[i], processOrder[j] = processOrder[j], processOrder[i]
    end

    for _, tid in ipairs(processOrder) do
        for potIdx, pot in ipairs(pots) do
            while potOppCount[tid][potIdx] < opponentsPerPot do
                local candidates = {}
                for _, cid in ipairs(pot) do
                    if cid ~= tid
                        and not isPaired(tid, cid)
                        and potOppCount[tid][potIdx] < opponentsPerPot
                        and potOppCount[cid][teamPot[tid]] < opponentsPerPot then
                        table.insert(candidates, cid)
                    end
                end
                if #candidates == 0 then
                    return nil
                end
                for i = #candidates, 2, -1 do
                    local j = RandomInt(1, i)
                    candidates[i], candidates[j] = candidates[j], candidates[i]
                end
                addPairFromPot(tid, candidates[1], potIdx)
            end
        end
    end

    for _, tid in ipairs(teamIds) do
        if #teamOpponents[tid] ~= expectedMatches then
            return nil
        end
        for potIdx = 1, numPots do
            if potOppCount[tid][potIdx] ~= opponentsPerPot then
                return nil
            end
        end
    end

    return teamOpponents
end

local function _fixturesFromOpponents(teamIds, teamOpponents)
    local fixtures = {}
    local fixtureId = 1
    local generatedPairs = {}
    for _, tid in ipairs(teamIds) do
        for _, opp in ipairs(teamOpponents[tid]) do
            local pairKey = opp.isHome and (tid .. "_" .. opp.opId) or (opp.opId .. "_" .. tid)
            if not generatedPairs[pairKey] then
                generatedPairs[pairKey] = true
                local homeId = opp.isHome and tid or opp.opId
                local awayId = opp.isHome and opp.opId or tid
                table.insert(fixtures, {
                    id = fixtureId,
                    homeTeamId = homeId,
                    awayTeamId = awayId,
                    date = nil,
                    status = "scheduled",
                    homeGoals = 0,
                    awayGoals = 0,
                    matchday = 0,
                })
                fixtureId = fixtureId + 1
            end
        end
    end
    return fixtures
end

--- 按轮贪心分配比赛日
local function _tryAssignByRoundGreedy(fixtures, teamIds, matchdays, matchDays)
    local maxPerDay = math.floor(#teamIds / 2)
    local n = #fixtures
    local assigned = {}
    for i = 1, n do
        assigned[i] = false
    end

    local function clearAssignment(f)
        f.date = nil
        f.matchday = 0
    end

    local function tryGreedyRound(d)
        if d > matchdays then return true end

        local candidates = {}
        for i = 1, n do
            if not assigned[i] then
                table.insert(candidates, i)
            end
        end
        for i = #candidates, 2, -1 do
            local j = RandomInt(1, i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end

        local usedTeam = {}
        local roundCount = 0
        for _, idx in ipairs(candidates) do
            if roundCount >= maxPerDay then break end
            local f = fixtures[idx]
            if not usedTeam[f.homeTeamId] and not usedTeam[f.awayTeamId] then
                assigned[idx] = true
                usedTeam[f.homeTeamId] = true
                usedTeam[f.awayTeamId] = true
                f.date = matchDays[d]
                f.matchday = d
                roundCount = roundCount + 1
            end
        end

        if roundCount < maxPerDay then
            for i = 1, n do
                if assigned[i] and fixtures[i].matchday == d then
                    assigned[i] = false
                    clearAssignment(fixtures[i])
                end
            end
            return false
        end
        return tryGreedyRound(d + 1)
    end

    if tryGreedyRound(1) then return true end
    return false
end

--- 大赛制（欧冠 36 队）：沿用原贪心 + 退路（部分图无法严格 8 轮 1 因子分解）
local function _assignLeaguePhaseMatchdaysLegacy(fixtures, teamIds, matchdays, matchDays)
    local maxPerDay = math.floor(#teamIds / 2)
    local n = #fixtures

    local function dateKey(date)
        return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
    end

    local teamDateUsed = {}
    for _, tid in ipairs(teamIds) do
        teamDateUsed[tid] = {}
    end

    local function assignFixtureDate(f, dayIdx, date)
        f.date = date
        f.matchday = dayIdx
        teamDateUsed[f.homeTeamId][dateKey(date)] = true
        teamDateUsed[f.awayTeamId][dateKey(date)] = true
    end

    local function nextFreeDateForPair(f, baseDate)
        for offset = 1, 6 do
            local candidate = League._addDays(baseDate, offset)
            local key = dateKey(candidate)
            if not teamDateUsed[f.homeTeamId][key] and not teamDateUsed[f.awayTeamId][key] then
                return candidate
            end
        end
        return baseDate
    end

    for i = n, 2, -1 do
        local j = RandomInt(1, i)
        fixtures[i], fixtures[j] = fixtures[j], fixtures[i]
    end

    local teamDayUsed = {}
    for _, tid in ipairs(teamIds) do
        teamDayUsed[tid] = {}
    end
    local daySlots = {}
    for d = 1, matchdays do
        daySlots[d] = 0
    end

    for _, f in ipairs(fixtures) do
        local assigned = false
        for d = 1, matchdays do
            if daySlots[d] < maxPerDay
                and not teamDayUsed[f.homeTeamId][d]
                and not teamDayUsed[f.awayTeamId][d] then
                assignFixtureDate(f, d, matchDays[d])
                daySlots[d] = daySlots[d] + 1
                teamDayUsed[f.homeTeamId][d] = true
                teamDayUsed[f.awayTeamId][d] = true
                assigned = true
                break
            end
        end
        if not assigned then
            local bestDay = nil
            local bestCount = 999
            for d = 1, matchdays do
                if not teamDayUsed[f.homeTeamId][d]
                    and not teamDayUsed[f.awayTeamId][d]
                    and daySlots[d] < bestCount then
                    bestDay = d
                    bestCount = daySlots[d]
                end
            end
            if not bestDay then
                bestDay = 1
                bestCount = daySlots[1]
                for d = 2, matchdays do
                    if daySlots[d] < bestCount then
                        bestDay = d
                        bestCount = daySlots[d]
                    end
                end
            end
            local date = matchDays[bestDay]
            if teamDayUsed[f.homeTeamId][bestDay] or teamDayUsed[f.awayTeamId][bestDay] then
                date = nextFreeDateForPair(f, date)
            end
            assignFixtureDate(f, bestDay, date)
            daySlots[bestDay] = daySlots[bestDay] + 1
            teamDayUsed[f.homeTeamId][bestDay] = true
            teamDayUsed[f.awayTeamId][bestDay] = true
        end
    end
    return true
end

--- 小赛制（欧联 24 队）：按轮贪心 + 回溯兜底
local function _assignLeaguePhaseMatchdaysSmall(fixtures, teamIds, matchdays, matchDays)
    local maxPerDay = math.floor(#teamIds / 2)
    local n = #fixtures

    for _ = 1, 50 do
        for i = 1, n do
            fixtures[i].date = nil
            fixtures[i].matchday = 0
        end
        if _tryAssignByRoundGreedy(fixtures, teamIds, matchdays, matchDays) then
            return true
        end
    end

    local assigned = {}
    for i = 1, n do
        assigned[i] = false
    end

    local function clearAssignment(f)
        f.date = nil
        f.matchday = 0
    end

    for i = 1, n do
        clearAssignment(fixtures[i])
    end

    local function assignRound(d)
        if d > matchdays then return true end

        local usedTeam = {}
        local roundCount = 0

        local function pickEdge(idx)
            if roundCount == maxPerDay then
                return assignRound(d + 1)
            end
            if idx > n then
                return false
            end

            if assigned[idx] then
                return pickEdge(idx + 1)
            end

            local f = fixtures[idx]
            if not usedTeam[f.homeTeamId] and not usedTeam[f.awayTeamId] then
                assigned[idx] = true
                usedTeam[f.homeTeamId] = true
                usedTeam[f.awayTeamId] = true
                f.date = matchDays[d]
                f.matchday = d
                roundCount = roundCount + 1
                if pickEdge(idx + 1) then return true end
                assigned[idx] = false
                usedTeam[f.homeTeamId] = nil
                usedTeam[f.awayTeamId] = nil
                clearAssignment(f)
                roundCount = roundCount - 1
            end

            return pickEdge(idx + 1)
        end

        return pickEdge(1)
    end

    return assignRound(1)
end

local function _assignLeaguePhaseMatchdays(fixtures, teamIds, matchdays, matchDays)
    return _assignLeaguePhaseMatchdaysSmall(fixtures, teamIds, matchdays, matchDays)
end

---@param startDate table {year, month, day}
---@param drawConfig table|nil 可选覆盖：weekday, dayInterval（其余从 leaguePhase 读取）
function Tournament:drawLeaguePhaseFixtures(startDate, drawConfig)
    local lp = self.leaguePhase
    if not lp then return end

    local pots = lp.pots
    local teamIds = lp.teamIds
    local matchdays = lp.matchdays or 8
    local opponentsPerPot = lp.opponentsPerPot or 2
    local matchesPerTeam = #pots * opponentsPerPot
    local weekday = (drawConfig and drawConfig.weekday) or lp.weekday or 3
    local dayInterval = (drawConfig and drawConfig.dayInterval) or lp.dayInterval or 14

    local matchDays = {}
    local date = League._alignToWeekday(
        { year = startDate.year, month = startDate.month, day = startDate.day }, weekday)
    for i = 1, matchdays do
        table.insert(matchDays, { year = date.year, month = date.month, day = date.day })
        date = League._addDays(date, dayInterval)
    end

    local expectedFixtures = math.floor(#teamIds * matchesPerTeam / 2)
    local fixtures = nil
    local isLargeDraw = expectedFixtures > 72

    for _ = 1, 200 do
        local teamOpponents = _buildLeaguePhaseOpponents(teamIds, pots, opponentsPerPot)
        if teamOpponents then
            local candidateFixtures = _fixturesFromOpponents(teamIds, teamOpponents)
            if #candidateFixtures == expectedFixtures then
                if isLargeDraw then
                    fixtures = candidateFixtures
                    break
                end
                for i = #candidateFixtures, 2, -1 do
                    local j = RandomInt(1, i)
                    candidateFixtures[i], candidateFixtures[j] = candidateFixtures[j], candidateFixtures[i]
                end
                if _assignLeaguePhaseMatchdays(candidateFixtures, teamIds, matchdays, matchDays) then
                    fixtures = candidateFixtures
                    break
                end
            end
        end
    end

    if not fixtures then
        log:Write(LOG_WARNING, "[" .. (self.shortName or "Tournament") .. "] league phase draw failed after retries")
        return
    end

    if isLargeDraw then
        _assignLeaguePhaseMatchdaysLegacy(fixtures, teamIds, matchdays, matchDays)
    end

    lp.fixtures = fixtures
end

--- 更新联赛阶段积分
function Tournament:updateLeagueStanding(fixture)
    local lp = self.leaguePhase
    if not lp then return end

    local home = lp.standings[fixture.homeTeamId]
    local away = lp.standings[fixture.awayTeamId]
    if not home or not away then return end

    home.played = home.played + 1
    away.played = away.played + 1
    home.goalsFor = home.goalsFor + fixture.homeGoals
    home.goalsAgainst = home.goalsAgainst + fixture.awayGoals
    away.goalsFor = away.goalsFor + fixture.awayGoals
    away.goalsAgainst = away.goalsAgainst + fixture.homeGoals

    if fixture.homeGoals > fixture.awayGoals then
        home.wins = home.wins + 1
        home.points = home.points + 3
        away.losses = away.losses + 1
    elseif fixture.homeGoals < fixture.awayGoals then
        away.wins = away.wins + 1
        away.points = away.points + 3
        home.losses = home.losses + 1
    else
        home.draws = home.draws + 1
        home.points = home.points + 1
        away.draws = away.draws + 1
        away.points = away.points + 1
    end

    home.goalDifference = home.goalsFor - home.goalsAgainst
    away.goalDifference = away.goalsFor - away.goalsAgainst
end

--- 获取联赛阶段排名（单一积分榜）
function Tournament:getLeaguePhaseSortedStandings()
    local lp = self.leaguePhase
    if not lp then return {} end
    

    local sorted = {}
    for _, s in pairs(lp.standings) do
        table.insert(sorted, s)
    end
    table.sort(sorted, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
        if a.goalsFor ~= b.goalsFor then return a.goalsFor > b.goalsFor end
        return (a.wins or 0) > (b.wins or 0)
    end)
    return sorted
end

--- 获取球队在联赛阶段的排名位置
function Tournament:getLeaguePhasePosition(teamId)
    local sorted = self:getLeaguePhaseSortedStandings()
    for i, s in ipairs(sorted) do
        if s.teamId == teamId then return i end
    end
    return 0
end

--- 联赛阶段是否完成
function Tournament:isLeaguePhaseComplete()
    local lp = self.leaguePhase
    if not lp or #(lp.fixtures or {}) == 0 then return false end
    for _, f in ipairs(lp.fixtures) do
        if f.status ~= "finished" then return false end
    end
    return true
end

--- 从联赛阶段获取晋级者（阈值来自 leaguePhase 配置）
function Tournament:getLeaguePhaseAdvancers()
    local lp = self.leaguePhase
    local directCount = (lp and lp.directAdvanceCount) or 8
    local playoffStart = (lp and lp.playoffStartRank) or 9
    local playoffEnd = (lp and lp.playoffEndRank) or 24

    local sorted = self:getLeaguePhaseSortedStandings()
    local directR16 = {}
    local playoffTeams = {}

    for i, s in ipairs(sorted) do
        if i <= directCount then
            table.insert(directR16, s.teamId)
        elseif i <= playoffEnd then
            table.insert(playoffTeams, s.teamId)
        end
    end

    return directR16, playoffTeams
end

------------------------------------------------------
-- 小组赛（传统模式 - 世界杯用）
------------------------------------------------------

-- 抽签分组（numGroups 组，每组 groupSize 队）
function Tournament:drawGroups(teamIds, numGroups, seeds)
    self.groups = {}
    local groupNames = {"A", "B", "C", "D", "E", "F", "G", "H"}

    -- 如果提供了种子，按档次分配（简化：随机分配）
    local shuffled = {}
    for _, tid in ipairs(teamIds) do
        table.insert(shuffled, tid)
    end
    -- Fisher-Yates 洗牌
    for i = #shuffled, 2, -1 do
        local j = RandomInt(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local groupSize = math.ceil(#shuffled / numGroups)
    local idx = 1
    for g = 1, numGroups do
        local groupName = groupNames[g]
        local groupTeams = {}
        for _ = 1, groupSize do
            if idx <= #shuffled then
                table.insert(groupTeams, shuffled[idx])
                idx = idx + 1
            end
        end
        self.groups[groupName] = {
            teamIds = groupTeams,
            standings = {},
            fixtures = {},
        }
        -- 初始化小组积分榜
        for _, tid in ipairs(groupTeams) do
            self.groups[groupName].standings[tid] = {
                teamId = tid,
                played = 0,
                wins = 0,
                draws = 0,
                losses = 0,
                goalsFor = 0,
                goalsAgainst = 0,
                goalDifference = 0,
                points = 0,
            }
        end
    end

    self.phase = Tournament.PHASE_GROUP
end

-- 为小组赛生成赛程（双循环：主客各一场）
function Tournament:generateGroupFixtures(startDate)
    local matchDate = {year = startDate.year, month = startDate.month, day = startDate.day}
    local fixtureId = 1

    for groupName, group in pairs(self.groups) do
        local teams = group.teamIds
        local n = #teams
        group.fixtures = {}

        -- 生成双循环赛程
        for i = 1, n do
            for j = i + 1, n do
                -- 主场
                table.insert(group.fixtures, {
                    id = fixtureId,
                    groupName = groupName,
                    round = 1,
                    homeTeamId = teams[i],
                    awayTeamId = teams[j],
                    date = {year = matchDate.year, month = matchDate.month, day = matchDate.day},
                    status = "scheduled",
                    homeGoals = 0,
                    awayGoals = 0,
                })
                fixtureId = fixtureId + 1
            end
        end

        -- 客场（反转主客）
        local firstHalf = #group.fixtures
        for i = 1, firstHalf do
            local f = group.fixtures[i]
            table.insert(group.fixtures, {
                id = fixtureId,
                groupName = groupName,
                round = 2,
                homeTeamId = f.awayTeamId,
                awayTeamId = f.homeTeamId,
                date = {year = matchDate.year, month = matchDate.month, day = matchDate.day},
                status = "scheduled",
                homeGoals = 0,
                awayGoals = 0,
            })
            fixtureId = fixtureId + 1
        end
    end

    -- 分配比赛日期
    self:_assignGroupMatchDates(startDate)
end

-- 分配小组赛日期（6轮比赛日）
function Tournament:_assignGroupMatchDates(startDate)
    local matchDays = {}
    local date = {year = startDate.year, month = startDate.month, day = startDate.day}

    -- 生成6个比赛日日期（每隔14天）
    for i = 1, 6 do
        table.insert(matchDays, {year = date.year, month = date.month, day = date.day})
        date = League._addDays(date, 14)
    end

    for _, group in pairs(self.groups) do
        local fixtures = group.fixtures
        local matchDayIdx = 1
        for i, f in ipairs(fixtures) do
            f.date = matchDays[matchDayIdx]
            f.round = matchDayIdx
            matchDayIdx = matchDayIdx + 1
            if matchDayIdx > 6 then matchDayIdx = 6 end
        end
    end
end

-- 更新小组赛积分
function Tournament:updateGroupStanding(groupName, fixture)
    local group = self.groups[groupName]
    if not group then return end

    local home = group.standings[fixture.homeTeamId]
    local away = group.standings[fixture.awayTeamId]
    if not home or not away then return end

    home.played = home.played + 1
    away.played = away.played + 1
    home.goalsFor = home.goalsFor + fixture.homeGoals
    home.goalsAgainst = home.goalsAgainst + fixture.awayGoals
    away.goalsFor = away.goalsFor + fixture.awayGoals
    away.goalsAgainst = away.goalsAgainst + fixture.homeGoals

    if fixture.homeGoals > fixture.awayGoals then
        home.wins = home.wins + 1
        home.points = home.points + 3
        away.losses = away.losses + 1
    elseif fixture.homeGoals < fixture.awayGoals then
        away.wins = away.wins + 1
        away.points = away.points + 3
        home.losses = home.losses + 1
    else
        home.draws = home.draws + 1
        home.points = home.points + 1
        away.draws = away.draws + 1
        away.points = away.points + 1
    end

    home.goalDifference = home.goalsFor - home.goalsAgainst
    away.goalDifference = away.goalsFor - away.goalsAgainst
end

-- 获取小组排名
function Tournament:getGroupSortedStandings(groupName)
    local group = self.groups[groupName]
    if not group then return {} end

    local sorted = {}
    for _, s in pairs(group.standings) do
        table.insert(sorted, s)
    end
    table.sort(sorted, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
        return a.goalsFor > b.goalsFor
    end)
    return sorted
end

-- 判断小组赛是否全部结束
function Tournament:isGroupStageComplete()
    for _, group in pairs(self.groups) do
        for _, f in ipairs(group.fixtures) do
            if f.status ~= "finished" then
                return false
            end
        end
    end
    return true
end

-- 从小组中提取出线队伍（每组前 advanceCount 名）
function Tournament:getGroupAdvancers(advanceCount)
    advanceCount = advanceCount or 2
    local advancers = {}
    local groupNames = {}
    for name, _ in pairs(self.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    for _, name in ipairs(groupNames) do
        local sorted = self:getGroupSortedStandings(name)
        for i = 1, math.min(advanceCount, #sorted) do
            table.insert(advancers, {
                teamId = sorted[i].teamId,
                groupName = name,
                position = i,
            })
        end
    end
    return advancers
end

------------------------------------------------------
-- 淘汰赛
------------------------------------------------------

--- 标记单场淘汰赛 fixture（欧冠/世界杯/未来国内杯共用）
--- 90分钟平局 → 加时 → 仍平 → 点球
function Tournament.markSingleLegKnockout(fixture)
    fixture.isKnockout = true
    return fixture
end

-- 生成淘汰赛对阵（两回合制）
function Tournament:generateKnockoutRound(phase, matchups, startDate)
    local fixtures = {}
    -- 淘汰赛对齐到周三（欧冠比赛日）
    local date = League._alignToWeekday(
        {year = startDate.year, month = startDate.month, day = startDate.day}, 3)  -- 3=周三

    for i, matchup in ipairs(matchups) do
        -- 第一回合
        table.insert(fixtures, {
            id = phase .. "_" .. i .. "_1",
            leg = 1,
            matchIndex = i,
            homeTeamId = matchup[1],
            awayTeamId = matchup[2],
            date = {year = date.year, month = date.month, day = date.day},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
        -- 第二回合（主客互换）
        local date2 = League._addDays(date, 14)
        table.insert(fixtures, {
            id = phase .. "_" .. i .. "_2",
            leg = 2,
            matchIndex = i,
            homeTeamId = matchup[2],
            awayTeamId = matchup[1],
            date = {year = date2.year, month = date2.month, day = date2.day},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    end

    self.knockout[phase] = fixtures
    self.phase = phase
    return fixtures
end

-- 生成决赛对阵（单场定胜负，对齐到周六）
function Tournament:generateFinal(matchup, finalDate)
    local date = League._alignToWeekday(
        {year = finalDate.year, month = finalDate.month, day = finalDate.day}, 6)  -- 6=周六（决赛传统在周六晚）
    self.knockout.final = {
        Tournament.markSingleLegKnockout({
            id = "final_1",
            leg = 1,
            matchIndex = 1,
            homeTeamId = matchup[1],
            awayTeamId = matchup[2],
            date = date,
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    }
    self.phase = Tournament.PHASE_FINAL
end

-- 判断某轮淘汰赛是否完成
function Tournament:isKnockoutRoundComplete(phase)
    local fixtures = self.knockout[phase]
    if not fixtures or #fixtures == 0 then return false end
    for _, f in ipairs(fixtures) do
        if f.status ~= "finished" then return false end
    end
    return true
end

--- 两回合淘汰决胜（team1=leg1 主队, team2=leg1 客队）
--- 次回合 90 分钟打平且总比分平 → 加时进球计入总比分；仍平 → 点球胜者
---@return string|nil winnerTeamId
local function _resolveTwoLegKnockoutWinner(leg1, leg2)
    local team1 = leg1.homeTeamId
    local team2 = leg1.awayTeamId
    local home = leg2.homeGoals or 0
    local away = leg2.awayGoals or 0

    local agg1 = (leg1.homeGoals or 0) + away
    local agg2 = (leg1.awayGoals or 0) + home

    if agg1 > agg2 then return team1 end
    if agg2 > agg1 then return team2 end

    -- 90 分钟总比分平：次回合加时进球计入总比分（跳过模拟时 ET 未并入 homeGoals）
    local extraTime = leg2.extraTime
    if extraTime and extraTime.played then
        local homeET = extraTime.homeExtraGoals or 0
        local awayET = extraTime.awayExtraGoals or 0
        local agg1WithET = agg1 + awayET
        local agg2WithET = agg2 + homeET
        if agg1WithET > agg2WithET then return team1 end
        if agg2WithET > agg1WithET then return team2 end
    end

    if leg2._penaltyWinner then return leg2._penaltyWinner end
    return nil
end

-- 获取淘汰赛某轮的晋级者
function Tournament:getKnockoutWinners(phase)
    local fixtures = self.knockout[phase]
    if not fixtures then return {} end

    local winners = {}

    if phase == "final" then
        -- 决赛单场
        local f = fixtures[1]
        if f and f.status == "finished" then
            if f.homeGoals > f.awayGoals then
                table.insert(winners, f.homeTeamId)
            elseif f.awayGoals > f.homeGoals then
                table.insert(winners, f.awayTeamId)
            else
                -- 平局 → 读取点球结果
                if f._penaltyWinner then
                    table.insert(winners, f._penaltyWinner)
                else
                    table.insert(winners, f.homeTeamId)
                end
            end
        end
    else
        -- 两回合制，按matchIndex配对
        local pairings = {}
        for _, f in ipairs(fixtures) do
            if not pairings[f.matchIndex] then
                pairings[f.matchIndex] = {}
            end
            table.insert(pairings[f.matchIndex], f)
        end

        for _, pair in pairs(pairings) do
            if #pair == 2 and pair[1].status == "finished" and pair[2].status == "finished" then
                local leg1, leg2
                for _, f in ipairs(pair) do
                    if f.leg == 1 then leg1 = f else leg2 = f end
                end
                if leg1 and leg2 then
                    local winner = _resolveTwoLegKnockoutWinner(leg1, leg2)
                    if winner then
                        table.insert(winners, winner)
                    else
                        -- 兜底（不应出现：总比分/加时/点球均未分出胜负）
                        if RandomInt(1, 2) == 1 then
                            table.insert(winners, leg1.homeTeamId)
                        else
                            table.insert(winners, leg1.awayTeamId)
                        end
                    end
                end
            end
        end
    end

    return winners
end

------------------------------------------------------
-- 通用 - 获取指定日期的比赛
------------------------------------------------------

function Tournament:getFixturesForDate(date)
    local result = {}

    -- 联赛阶段
    if self.phase == Tournament.PHASE_LEAGUE and self.leaguePhase then
        for _, f in ipairs(self.leaguePhase.fixtures) do
            if f.status == "scheduled" and
               f.date and f.date.year == date.year and
               f.date.month == date.month and
               f.date.day == date.day then
                table.insert(result, f)
            end
        end
    end

    -- 小组赛
    if self.phase == Tournament.PHASE_GROUP then
        for _, group in pairs(self.groups) do
            for _, f in ipairs(group.fixtures) do
                if f.status == "scheduled" and
                   f.date.year == date.year and
                   f.date.month == date.month and
                   f.date.day == date.day then
                    table.insert(result, f)
                end
            end
        end
    end

    -- 淘汰赛（含附加赛）
    local knockoutPhases = {"playoff", "r32", "r16", "qf", "sf", "third", "final"}
    for _, phase in ipairs(knockoutPhases) do
        local fixtures = self.knockout[phase]
        if fixtures then
            for _, f in ipairs(fixtures) do
                if f.status == "scheduled" and
                   f.date.year == date.year and
                   f.date.month == date.month and
                   f.date.day == date.day then
                    f.tournamentPhase = phase
                    table.insert(result, f)
                end
            end
        end
    end

    return result
end

------------------------------------------------------
-- 序列化
------------------------------------------------------

function Tournament:serialize()
    return {
        id = self.id,
        name = self.name,
        shortName = self.shortName,
        type = self.type,
        season = self.season,
        phase = self.phase,
        qualifiedTeams = self.qualifiedTeams,
        groups = self.groups,
        leaguePhase = self.leaguePhase,
        knockout = self.knockout,
        champion = self.champion,
        _directR16 = self._directR16,
    }
end

function Tournament.deserialize(data)
    if not data then return nil end
    local t = Tournament.new(data)
    return t
end

return Tournament
