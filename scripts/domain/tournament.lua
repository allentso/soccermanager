-- domain/tournament.lua
-- 锦标赛数据模型（小组赛 + 淘汰赛，用于欧冠/世界杯）

local League = require("scripts/domain/league")

local Tournament = {}
Tournament.__index = Tournament

-- 赛事阶段
Tournament.PHASE_NOT_STARTED = "not_started"
Tournament.PHASE_GROUP = "group"
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
    self.season = data.season or 2024

    -- 阶段
    self.phase = data.phase or Tournament.PHASE_NOT_STARTED

    -- 参赛球队ID
    self.qualifiedTeams = data.qualifiedTeams or {}

    -- 小组赛（key为组名 A/B/C/D...）
    self.groups = data.groups or {}

    -- 淘汰赛
    self.knockout = data.knockout or {
        r16 = {},
        qf = {},
        sf = {},
        final = {},
    }

    -- 冠军
    self.champion = data.champion or nil

    return self
end

------------------------------------------------------
-- 小组赛
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

    -- 分配比赛日期（小组赛共6轮比赛日，每两周一次）
    self:_assignGroupMatchDates(startDate)
end

-- 分配小组赛日期（6轮比赛日）
function Tournament:_assignGroupMatchDates(startDate)
    -- 收集所有小组赛fixture，按轮次分配日期
    -- 每组6场比赛（4队双循环），分6个比赛日
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

-- 生成淘汰赛对阵（两回合制）
function Tournament:generateKnockoutRound(phase, matchups, startDate)
    local fixtures = {}
    local date = {year = startDate.year, month = startDate.month, day = startDate.day}

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

-- 生成决赛对阵（单场定胜负）
function Tournament:generateFinal(matchup, finalDate)
    self.knockout.final = {
        {
            id = "final_1",
            leg = 1,
            matchIndex = 1,
            homeTeamId = matchup[1],
            awayTeamId = matchup[2],
            date = {year = finalDate.year, month = finalDate.month, day = finalDate.day},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        }
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
                -- 平局随机（简化：主场方获胜）
                table.insert(winners, f.homeTeamId)
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
                -- 第一回合的主队 = pair中leg==1的homeTeamId
                local leg1, leg2
                for _, f in ipairs(pair) do
                    if f.leg == 1 then leg1 = f else leg2 = f end
                end
                if leg1 and leg2 then
                    local team1 = leg1.homeTeamId  -- 第一回合主队
                    local team2 = leg1.awayTeamId  -- 第一回合客队
                    local agg1 = leg1.homeGoals + leg2.awayGoals  -- team1 总进球
                    local agg2 = leg1.awayGoals + leg2.homeGoals  -- team2 总进球

                    if agg1 > agg2 then
                        table.insert(winners, team1)
                    elseif agg2 > agg1 then
                        table.insert(winners, team2)
                    else
                        -- 客场进球规则（简化）: team2 在第一回合客场进了更多球
                        local team2Away = leg1.awayGoals
                        local team1Away = leg2.awayGoals
                        if team2Away > team1Away then
                            table.insert(winners, team2)
                        else
                            -- 随机决定（点球大战简化）
                            if Random() < 0.5 then
                                table.insert(winners, team1)
                            else
                                table.insert(winners, team2)
                            end
                        end
                    end
                end
            end
        end
    end

    return winners
end

------------------------------------------------------
-- 获取当天的所有锦标赛比赛
------------------------------------------------------

function Tournament:getFixturesForDate(date)
    local result = {}

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

    -- 淘汰赛
    local knockoutPhases = {"r16", "qf", "sf", "final"}
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

-- 查找fixture所在的小组名
function Tournament:findGroupForFixture(fixture)
    for groupName, group in pairs(self.groups) do
        for _, f in ipairs(group.fixtures) do
            if f.id == fixture.id then
                return groupName
            end
        end
    end
    return nil
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
        knockout = self.knockout,
        champion = self.champion,
    }
end

return Tournament
