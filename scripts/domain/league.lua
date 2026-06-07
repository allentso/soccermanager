-- domain/league.lua
-- 联赛数据模型

local League = {}
League.__index = League

function League.new(data)
    local self = setmetatable({}, League)
    self.id = data.id or 1
    self.name = data.name or "超级联赛"
    self.country = data.country or "ENG"
    self.season = data.season or 2026
    self.teamIds = data.teamIds or {}
    self.currentRound = data.currentRound or 0
    self.totalRounds = data.totalRounds or 0

    -- 赛程
    self.fixtures = data.fixtures or {}

    -- 积分榜
    self.standings = data.standings or {}

    return self
end

-- 生成双循环赛程
function League:generateFixtures(startDate)
    local teams = self.teamIds
    local n = #teams
    if n < 2 then return end

    self.fixtures = {}
    self.totalRounds = (n - 1) * 2

    -- Round-robin 生成算法
    local teamList = {}
    for i, tid in ipairs(teams) do
        teamList[i] = tid
    end

    -- 如果奇数队，添加 BYE
    local hasBye = false
    if n % 2 ~= 0 then
        table.insert(teamList, -1)  -- BYE marker
        n = n + 1
        hasBye = true
    end

    local fixtureId = 1
    -- 对齐到最近的周六（联赛比赛日）
    local matchDate = League._alignToWeekday(
        {year = startDate.year, month = startDate.month, day = startDate.day}, 6)  -- 6=周六

    -- 前半赛季（主场）
    for round = 1, n - 1 do
        for i = 1, n / 2 do
            local home = teamList[i]
            local away = teamList[n - i + 1]
            if home ~= -1 and away ~= -1 then
                table.insert(self.fixtures, {
                    id = fixtureId,
                    round = round,
                    homeTeamId = home,
                    awayTeamId = away,
                    date = {year = matchDate.year, month = matchDate.month, day = matchDate.day},
                    status = "scheduled",  -- scheduled, playing, finished
                    homeGoals = 0,
                    awayGoals = 0,
                    events = {},
                })
                fixtureId = fixtureId + 1
            end
        end

        -- 轮转：固定teamList[1]，其余旋转
        local last = teamList[n]
        for i = n, 3, -1 do
            teamList[i] = teamList[i - 1]
        end
        teamList[2] = last

        -- 推进日期（每轮间隔7天）
        matchDate = League._addDays(matchDate, 7)
    end

    -- 后半赛季（主客互换）
    local firstHalfCount = #self.fixtures
    for i = 1, firstHalfCount do
        local f = self.fixtures[i]
        table.insert(self.fixtures, {
            id = fixtureId,
            round = f.round + (n - 1),
            homeTeamId = f.awayTeamId,
            awayTeamId = f.homeTeamId,
            date = {year = matchDate.year, month = matchDate.month, day = matchDate.day},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            events = {},
        })
        fixtureId = fixtureId + 1
        -- 每轮结束后推进日期
        if i < firstHalfCount and self.fixtures[i + 1] and self.fixtures[i + 1].round ~= f.round then
            matchDate = League._addDays(matchDate, 7)
        elseif i == firstHalfCount then
            -- 不需要再推进
        end
    end

    -- 重新按轮次排序后半赛程日期
    local halfStart = firstHalfCount + 1
    local currentRound = self.fixtures[halfStart] and self.fixtures[halfStart].round or 0
    local roundDate = League._addDays(self.fixtures[firstHalfCount].date, 7)
    for i = halfStart, #self.fixtures do
        if self.fixtures[i].round ~= currentRound then
            currentRound = self.fixtures[i].round
            roundDate = League._addDays(roundDate, 7)
        end
        self.fixtures[i].date = {year = roundDate.year, month = roundDate.month, day = roundDate.day}
    end

    self.currentRound = 1
end

-- 初始化积分榜
function League:initStandings()
    self.standings = {}
    for _, tid in ipairs(self.teamIds) do
        self.standings[tid] = {
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

-- 更新积分榜（比赛结束后调用）
function League:updateStanding(fixture)
    local home = self.standings[fixture.homeTeamId]
    local away = self.standings[fixture.awayTeamId]
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

-- 获取排序后的积分榜
function League:getSortedStandings()
    local sorted = {}
    for _, s in pairs(self.standings) do
        table.insert(sorted, s)
    end
    table.sort(sorted, function(a, b)
        if a.points ~= b.points then return a.points > b.points end
        if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
        return a.goalsFor > b.goalsFor
    end)
    return sorted
end

-- 获取球队排名
function League:getTeamPosition(teamId)
    local sorted = self:getSortedStandings()
    for i, s in ipairs(sorted) do
        if s.teamId == teamId then return i end
    end
    return 0
end

-- 获取当前轮次的比赛
function League:getFixturesByRound(round)
    local result = {}
    for _, f in ipairs(self.fixtures) do
        if f.round == round then
            table.insert(result, f)
        end
    end
    return result
end

-- 获取球队下一场比赛
function League:getNextFixture(teamId)
    for _, f in ipairs(self.fixtures) do
        if f.status == "scheduled" and (f.homeTeamId == teamId or f.awayTeamId == teamId) then
            return f
        end
    end
    return nil
end

-- 判断赛季是否结束
function League:isSeasonComplete()
    if not self.fixtures or #self.fixtures == 0 then
        return false  -- 无赛程时不能视为赛季完成
    end
    for _, f in ipairs(self.fixtures) do
        if f.status ~= "finished" then
            return false
        end
    end
    return true
end

-- 日期辅助函数
function League._addDays(date, days)
    local daysInMonth = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    local d = date.day + days
    local m = date.month
    local y = date.year

    while d > daysInMonth[m] do
        d = d - daysInMonth[m]
        m = m + 1
        if m > 12 then
            m = 1
            y = y + 1
        end
    end
    return {year = y, month = m, day = d}
end

--- 计算日期是星期几（Zeller算法简化版）
--- 返回: 1=周一, 2=周二, ..., 6=周六, 7=周日
function League._dayOfWeek(date)
    local y, m, d = date.year, date.month, date.day
    -- 调整1月和2月为上一年的13、14月
    if m <= 2 then
        m = m + 12
        y = y - 1
    end
    local k = y % 100
    local j = math.floor(y / 100)
    local h = (d + math.floor(13 * (m + 1) / 5) + k + math.floor(k / 4) + math.floor(j / 4) - 2 * j) % 7
    -- h: 0=周六, 1=周日, 2=周一, 3=周二, 4=周三, 5=周四, 6=周五
    local dow = ((h + 5) % 7) + 1  -- 转为 1=周一 ... 7=周日
    return dow
end

--- 找到 date 当天或之后最近的指定星期几
--- targetDow: 1=周一 ... 6=周六, 7=周日
function League._alignToWeekday(date, targetDow)
    local currentDow = League._dayOfWeek(date)
    local diff = (targetDow - currentDow) % 7
    if diff == 0 then
        return date  -- 当天就是目标
    end
    return League._addDays(date, diff)
end

function League:serialize()
    return {
        id = self.id,
        name = self.name,
        country = self.country,
        season = self.season,
        teamIds = self.teamIds,
        currentRound = self.currentRound,
        totalRounds = self.totalRounds,
        fixtures = self.fixtures,
        standings = self.standings,
    }
end

return League
