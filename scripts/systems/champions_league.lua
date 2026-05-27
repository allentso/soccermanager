-- systems/champions_league.lua
-- 欧冠联赛管理（资格赛、抽签、推进阶段）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local EventBus = require("scripts/app/event_bus")

local ChampionsLeague = {}

-- 各联赛欧冠名额
local UCL_SPOTS = {
    EPL = 4,
    LaLiga = 4,
    SerieA = 4,
    Bundesliga = 4,
    Ligue1 = 3,
}

-- 欧冠日程（基于赛季月份）
local UCL_SCHEDULE = {
    group_start = {month = 9, day = 17},    -- 9月中旬开始小组赛
    r16_start   = {month = 2, day = 18},    -- 2月中旬开始1/8决赛
    qf_start    = {month = 4, day = 8},     -- 4月初1/4决赛
    sf_start    = {month = 4, day = 29},    -- 4月底半决赛
    final_date  = {month = 5, day = 28},    -- 5月底决赛
}

------------------------------------------------------
-- 初始化本赛季欧冠
------------------------------------------------------

function ChampionsLeague.initialize(gameState)
    local season = gameState.season
    local qualifiedTeams = ChampionsLeague._getQualifiedTeams(gameState)

    if #qualifiedTeams < 16 then
        -- 名额不足16队，补充高声望球队
        qualifiedTeams = ChampionsLeague._fillSlots(gameState, qualifiedTeams, 16)
    end

    -- 限制为16队（4组，每组4队）
    while #qualifiedTeams > 16 do
        table.remove(qualifiedTeams)
    end

    -- 创建锦标赛实例
    local ucl = Tournament.new({
        name = "欧洲冠军联赛",
        shortName = "UCL",
        type = "ucl",
        season = season,
        qualifiedTeams = qualifiedTeams,
    })

    -- 抽签分组（4组，每组4队）
    ucl:drawGroups(qualifiedTeams, 4)

    -- 生成小组赛赛程
    local groupStart = {
        year = season,
        month = UCL_SCHEDULE.group_start.month,
        day = UCL_SCHEDULE.group_start.day,
    }
    ucl:generateGroupFixtures(groupStart)

    -- 存储到 gameState
    gameState.championsLeague = ucl

    -- 通知
    gameState:addNews({
        category = "ucl_news",
        title = "欧冠小组赛抽签揭晓",
        body = ChampionsLeague._formatDrawResult(gameState, ucl),
    })

    return ucl
end

------------------------------------------------------
-- 获取合格球队（上赛季排名）
------------------------------------------------------

function ChampionsLeague._getQualifiedTeams(gameState)
    local qualified = {}

    -- 查看上赛季历史记录
    local lastSeason = nil
    for _, record in ipairs(gameState.worldHistory or {}) do
        if record.season == gameState.season - 1 then
            lastSeason = record
            break
        end
    end

    if lastSeason and lastSeason.leagues then
        -- 基于上赛季排名分配名额
        for leagueKey, spots in pairs(UCL_SPOTS) do
            local leagueRecord = lastSeason.leagues[leagueKey]
            if leagueRecord and leagueRecord.standings then
                for i = 1, math.min(spots, #leagueRecord.standings) do
                    local teamId = leagueRecord.standings[i].teamId
                    if teamId and gameState.teams[teamId] then
                        table.insert(qualified, teamId)
                    end
                end
            end
        end
    end

    -- 如果是第一个赛季（没有历史记录），按声望选取
    if #qualified == 0 then
        qualified = ChampionsLeague._getInitialQualifiers(gameState)
    end

    return qualified
end

-- 首赛季：按声望从各联赛选取顶级球队
function ChampionsLeague._getInitialQualifiers(gameState)
    local qualified = {}

    for leagueKey, spots in pairs(UCL_SPOTS) do
        local lg = gameState.leagues[leagueKey]
        if lg then
            -- 按声望排序该联赛球队
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
    end

    return qualified
end

-- 补充名额（按声望选取尚未入选的球队）
function ChampionsLeague._fillSlots(gameState, existing, target)
    local existingSet = {}
    for _, tid in ipairs(existing) do existingSet[tid] = true end

    -- 收集所有尚未入选的球队，按声望排序
    local candidates = {}
    for _, lg in pairs(gameState.leagues) do
        for _, tid in ipairs(lg.teamIds) do
            if not existingSet[tid] then
                local team = gameState.teams[tid]
                if team then
                    table.insert(candidates, team)
                end
            end
        end
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
-- 推进欧冠阶段（在赛季中检测）
------------------------------------------------------

function ChampionsLeague.checkPhaseAdvance(gameState)
    local ucl = gameState.championsLeague
    if not ucl or ucl.phase == Tournament.PHASE_COMPLETED then return end

    -- 小组赛结束 → 生成1/8决赛
    if ucl.phase == Tournament.PHASE_GROUP and ucl:isGroupStageComplete() then
        ChampionsLeague._advanceToR16(gameState, ucl)
    end

    -- 1/8决赛结束 → 生成1/4决赛
    if ucl.phase == Tournament.PHASE_R16 and ucl:isKnockoutRoundComplete("r16") then
        ChampionsLeague._advanceToQF(gameState, ucl)
    end

    -- 1/4决赛结束 → 生成半决赛
    if ucl.phase == Tournament.PHASE_QF and ucl:isKnockoutRoundComplete("qf") then
        ChampionsLeague._advanceToSF(gameState, ucl)
    end

    -- 半决赛结束 → 生成决赛
    if ucl.phase == Tournament.PHASE_SF and ucl:isKnockoutRoundComplete("sf") then
        ChampionsLeague._advanceToFinal(gameState, ucl)
    end

    -- 决赛结束 → 产生冠军
    if ucl.phase == Tournament.PHASE_FINAL and ucl:isKnockoutRoundComplete("final") then
        ChampionsLeague._completeTournament(gameState, ucl)
    end
end

------------------------------------------------------
-- 阶段推进内部函数
------------------------------------------------------

function ChampionsLeague._advanceToR16(gameState, ucl)
    local advancers = ucl:getGroupAdvancers(2)  -- 每组前2名

    -- 抽签配对：小组第一 vs 另一组第二（不同组）
    local firsts = {}
    local seconds = {}
    for _, a in ipairs(advancers) do
        if a.position == 1 then
            table.insert(firsts, a)
        else
            table.insert(seconds, a)
        end
    end

    -- 洗牌第二名
    for i = #seconds, 2, -1 do
        local j = RandomInt(1, i)
        seconds[i], seconds[j] = seconds[j], seconds[i]
    end

    -- 配对（确保不同组）
    local matchups = {}
    local usedSeconds = {}
    for _, first in ipairs(firsts) do
        for j, second in ipairs(seconds) do
            if not usedSeconds[j] and second.groupName ~= first.groupName then
                table.insert(matchups, {first.teamId, second.teamId})
                usedSeconds[j] = true
                break
            end
        end
    end
    -- 如果有剩余未配对的（同组冲突），强制配对
    for j, second in ipairs(seconds) do
        if not usedSeconds[j] then
            for _, first in ipairs(firsts) do
                local found = false
                for _, m in ipairs(matchups) do
                    if m[1] == first.teamId then found = true; break end
                end
                if not found then
                    table.insert(matchups, {first.teamId, second.teamId})
                    usedSeconds[j] = true
                    break
                end
            end
        end
    end

    local startDate = {
        year = gameState.season + 1,
        month = UCL_SCHEDULE.r16_start.month,
        day = UCL_SCHEDULE.r16_start.day,
    }
    ucl:generateKnockoutRound("r16", matchups, startDate)

    -- 新闻
    gameState:addNews({
        category = "ucl_news",
        title = "欧冠小组赛结束！16强对阵出炉",
        body = ChampionsLeague._formatKnockoutDraw(gameState, matchups),
    })
end

function ChampionsLeague._advanceToQF(gameState, ucl)
    local winners = ucl:getKnockoutWinners("r16")
    if #winners < 2 then return end

    -- 随机配对
    for i = #winners, 2, -1 do
        local j = RandomInt(1, i)
        winners[i], winners[j] = winners[j], winners[i]
    end

    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, {winners[i], winners[i + 1]})
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
            table.insert(matchups, {winners[i], winners[i + 1]})
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
    ucl:generateFinal({winners[1], winners[2]}, finalDate)

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
            title = string.format("🏆 %s 赢得欧冠冠军!", champion and champion.name or "?"),
            body = string.format("%s 在 %d-%d 赛季欧洲冠军联赛中夺冠！",
                champion and champion.name or "?", ucl.season, ucl.season + 1),
        })

        -- 冠军奖金
        if champion then
            local prize = 2000000
            champion.balance = champion.balance + prize
            if not champion.transactions then champion.transactions = {} end
            table.insert(champion.transactions, 1, {
                type = "prize",
                amount = prize,
                description = "欧冠冠军奖金",
                date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
            })
        end

        -- 如果是玩家球队
        if ucl.champion == gameState.playerTeamId then
            gameState:sendMessage({
                category = "league",
                title = "恭喜！欧冠冠军！",
                body = "你的球队赢得了欧洲冠军联赛！这是足坛最高荣誉！\n冠军奖金 2.0M 已到账。",
                priority = "high",
            })
        end

        EventBus.emit("ucl_completed", ucl.champion)
    end
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

function ChampionsLeague._formatDrawResult(gameState, ucl)
    local lines = {"欧冠小组赛分组:\n"}
    local groupNames = {}
    for name, _ in pairs(ucl.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    for _, name in ipairs(groupNames) do
        local group = ucl.groups[name]
        table.insert(lines, "【" .. name .. "组】")
        for _, tid in ipairs(group.teamIds) do
            local team = gameState.teams[tid]
            table.insert(lines, "  " .. (team and team.name or "?"))
        end
        table.insert(lines, "")
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
