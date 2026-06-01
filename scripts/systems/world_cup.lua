-- systems/world_cup.lua
-- 世界杯管理系统（4年一届，首届 2026）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")

local WorldCup = {}

-- 世界杯年份判断
local FIRST_WORLD_CUP = 2026
local CYCLE = 4

-- 参赛国家（按实力排序的国家列表）
local NATIONS = {
    {code = "BRA", name = "巴西"},
    {code = "FRA", name = "法国"},
    {code = "ARG", name = "阿根廷"},
    {code = "ENG", name = "英格兰"},
    {code = "ESP", name = "西班牙"},
    {code = "GER", name = "德国"},
    {code = "ITA", name = "意大利"},
    {code = "POR", name = "葡萄牙"},
    {code = "NED", name = "荷兰"},
    {code = "BEL", name = "比利时"},
    {code = "CRO", name = "克罗地亚"},
    {code = "URU", name = "乌拉圭"},
    {code = "COL", name = "哥伦比亚"},
    {code = "MEX", name = "墨西哥"},
    {code = "USA", name = "美国"},
    {code = "JPN", name = "日本"},
}

-- 世界杯日程（在赛季间隙举行，6月-7月）
local WC_SCHEDULE = {
    group_start = {month = 6, day = 14},
    r16_start   = {month = 7, day = 1},
    qf_start    = {month = 7, day = 9},
    sf_start    = {month = 7, day = 14},
    final_date  = {month = 7, day = 18},
}

------------------------------------------------------
-- 判断是否世界杯年
------------------------------------------------------

function WorldCup.isWorldCupYear(year)
    if year < FIRST_WORLD_CUP then return false end
    return (year - FIRST_WORLD_CUP) % CYCLE == 0
end

------------------------------------------------------
-- 初始化世界杯（赛季结束时检查）
------------------------------------------------------

function WorldCup.initialize(gameState)
    local wcYear = gameState.season + 1  -- 世界杯在赛季结束后的夏天举行
    if not WorldCup.isWorldCupYear(wcYear) then
        return nil
    end

    -- 已经存在则不重复初始化
    if gameState.worldCup and gameState.worldCup.season == wcYear then
        return gameState.worldCup
    end

    -- 为每个国家计算整体实力（基于该国籍球员的平均 overall）
    local nationStrength = WorldCup._calculateNationStrengths(gameState)

    -- 选出16支参赛国家队
    local qualifiedNations = WorldCup._getQualifiedNations(nationStrength)

    -- 创建锦标赛实例
    local wc = Tournament.new({
        name = "世界杯",
        shortName = "WC",
        type = "world_cup",
        season = wcYear,
        qualifiedTeams = qualifiedNations,  -- 这里存储的是国家 code 列表
    })

    -- 抽签分组（4组，每组4队）
    wc:drawGroups(qualifiedNations, 4)

    -- 生成小组赛赛程
    local groupStart = {
        year = wcYear,
        month = WC_SCHEDULE.group_start.month,
        day = WC_SCHEDULE.group_start.day,
    }
    wc:generateGroupFixtures(groupStart)

    -- 存储到 gameState
    gameState.worldCup = wc

    -- 新闻
    gameState:addNews({
        category = "world_cup_news",
        title = string.format("%d 世界杯分组抽签揭晓！", wcYear),
        body = WorldCup._formatDrawResult(gameState, wc),
    })

    -- 国家队主教练邀请逻辑
    WorldCup._checkNationalTeamInvitation(gameState, qualifiedNations, wcYear)

    return wc
end

------------------------------------------------------
-- 国家队邀请：基于教练声望和国籍
------------------------------------------------------
local NT_REP_THRESHOLD = 40  -- 最低声望要求（"普通教练"以上）

function WorldCup._checkNationalTeamInvitation(gameState, qualifiedNations, wcYear)
    -- 清除上一届的状态
    gameState.nationalTeamCoach = nil

    local manager = gameState:getPlayerManager()
    if not manager then return end

    -- 教练的国籍
    local managerNation = manager.nationality
    if not managerNation then return end

    -- 检查该国家是否入围世界杯
    local nationQualified = false
    for _, code in ipairs(qualifiedNations) do
        if code == managerNation then
            nationQualified = true
            break
        end
    end
    if not nationQualified then
        -- 国家没入围，发通知但不邀请
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯抽签揭晓",
            body = string.format("%d 世界杯分组抽签已完成。遗憾的是，%s未能入围本届赛事。",
                wcYear, WorldCup._getNationName(managerNation)),
            priority = "normal",
        })
        return
    end

    -- 检查声望是否够格
    local rep = manager.reputation or 30
    if rep < NT_REP_THRESHOLD then
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯即将开幕",
            body = string.format("%s入围了 %d 世界杯！但目前你的执教声望不够(%d/%d)，未能获得国家队邀请。继续努力吧！",
                WorldCup._getNationName(managerNation), wcYear, math.floor(rep), NT_REP_THRESHOLD),
            priority = "normal",
        })
        return
    end

    -- 声望足够 → 发送邀请（带操作按钮）
    local nationName = WorldCup._getNationName(managerNation)
    gameState:sendMessage({
        category = "world_cup",
        title = "国家队主教练邀请",
        body = string.format(
            "%s足协正式邀请你出任 %d 世界杯国家队主教练！\n\n" ..
            "你的执教声望(%d)已经获得认可。接受邀请后，你将负责选拔国家队大名单并带队征战世界杯。",
            nationName, wcYear, math.floor(rep)),
        priority = "high",
        actions = {
            { label = "接受邀请", actionId = "accept_nt_coach", data = { nation = managerNation } },
            { label = "婉拒", actionId = "decline_nt_coach", data = { nation = managerNation } },
        },
    })
end

------------------------------------------------------
-- 检查阶段推进
------------------------------------------------------

function WorldCup.checkPhaseAdvance(gameState)
    local wc = gameState.worldCup
    if not wc or wc.phase == Tournament.PHASE_COMPLETED or wc.phase == Tournament.PHASE_NOT_STARTED then
        return
    end

    -- 小组赛结束 → 生成1/8决赛
    if wc.phase == Tournament.PHASE_GROUP and wc:isGroupStageComplete() then
        WorldCup._advanceToR16(gameState, wc)
    end

    -- 1/8决赛结束 → 生成1/4决赛
    if wc.phase == Tournament.PHASE_R16 and wc:isKnockoutRoundComplete("r16") then
        WorldCup._advanceToQF(gameState, wc)
    end

    -- 1/4决赛结束 → 生成半决赛
    if wc.phase == Tournament.PHASE_QF and wc:isKnockoutRoundComplete("qf") then
        WorldCup._advanceToSF(gameState, wc)
    end

    -- 半决赛结束 → 生成决赛
    if wc.phase == Tournament.PHASE_SF and wc:isKnockoutRoundComplete("sf") then
        WorldCup._advanceToFinal(gameState, wc)
    end

    -- 决赛结束 → 产生冠军
    if wc.phase == Tournament.PHASE_FINAL and wc:isKnockoutRoundComplete("final") then
        WorldCup._completeTournament(gameState, wc)
    end
end

------------------------------------------------------
-- 计算各国家队实力
------------------------------------------------------

function WorldCup._calculateNationStrengths(gameState)
    local nationPlayers = {}  -- code -> {overall总和, 球员数}

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end
        local nat = player.nationality
        if nat then
            if not nationPlayers[nat] then
                nationPlayers[nat] = {totalOverall = 0, count = 0}
            end
            nationPlayers[nat].totalOverall = nationPlayers[nat].totalOverall + (player.overall or 50)
            nationPlayers[nat].count = nationPlayers[nat].count + 1
        end
        ::continue::
    end

    -- 计算平均实力
    local strengths = {}
    for code, data in pairs(nationPlayers) do
        strengths[code] = {
            code = code,
            avgOverall = data.count > 0 and (data.totalOverall / data.count) or 50,
            playerCount = data.count,
        }
    end
    return strengths
end

------------------------------------------------------
-- 选出参赛国家（16支）
------------------------------------------------------

function WorldCup._getQualifiedNations(nationStrength)
    -- 优先从预设国家列表中选取（保证多样性）
    local qualified = {}
    local added = {}

    -- 先加入预设的16国
    for _, nation in ipairs(NATIONS) do
        if #qualified >= 16 then break end
        table.insert(qualified, nation.code)
        added[nation.code] = true
    end

    -- 如果不够16，补充其他国家（按实力排序）
    if #qualified < 16 then
        local candidates = {}
        for code, data in pairs(nationStrength) do
            if not added[code] and data.playerCount >= 5 then
                table.insert(candidates, data)
            end
        end
        table.sort(candidates, function(a, b)
            return a.avgOverall > b.avgOverall
        end)
        for _, c in ipairs(candidates) do
            if #qualified >= 16 then break end
            table.insert(qualified, c.code)
        end
    end

    return qualified
end

------------------------------------------------------
-- 阶段推进
------------------------------------------------------

function WorldCup._advanceToR16(gameState, wc)
    local advancers = wc:getGroupAdvancers(2)

    -- 配对：A1 vs B2, B1 vs A2, C1 vs D2, D1 vs C2
    local firsts = {}
    local seconds = {}
    for _, a in ipairs(advancers) do
        if a.position == 1 then
            table.insert(firsts, a)
        else
            table.insert(seconds, a)
        end
    end

    -- 洗牌seconds
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
    -- 强制配对剩余
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

    -- 世界杯淘汰赛为单场淘汰制（不同于欧冠两回合）
    -- 复用 generateKnockoutRound 但只看 leg1 结果
    local startDate = {
        year = wc.season,
        month = WC_SCHEDULE.r16_start.month,
        day = WC_SCHEDULE.r16_start.day,
    }
    wc:generateKnockoutRound("r16", matchups, startDate)

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯16强对阵出炉",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToQF(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "r16")
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
        year = wc.season,
        month = WC_SCHEDULE.qf_start.month,
        day = WC_SCHEDULE.qf_start.day,
    }
    wc:generateKnockoutRound("qf", matchups, startDate)

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯8强对阵",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToSF(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "qf")
    if #winners < 2 then return end

    local matchups = {}
    for i = 1, #winners, 2 do
        if winners[i + 1] then
            table.insert(matchups, {winners[i], winners[i + 1]})
        end
    end

    local startDate = {
        year = wc.season,
        month = WC_SCHEDULE.sf_start.month,
        day = WC_SCHEDULE.sf_start.day,
    }
    wc:generateKnockoutRound("sf", matchups, startDate)

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯4强对阵",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToFinal(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "sf")
    if #winners < 2 then return end

    local finalDate = {
        year = wc.season,
        month = WC_SCHEDULE.final_date.month,
        day = WC_SCHEDULE.final_date.day,
    }
    wc:generateFinal({winners[1], winners[2]}, finalDate)

    local n1 = WorldCup._getNationName(winners[1])
    local n2 = WorldCup._getNationName(winners[2])
    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯决赛对阵确定！",
        body = string.format("%s vs %s\n决赛日期: %d年%d月%d日",
            n1, n2, finalDate.year, finalDate.month, finalDate.day),
    })
end

function WorldCup._completeTournament(gameState, wc)
    -- 决赛是单场，直接取 final fixture
    local fixtures = wc.knockout.final
    if not fixtures or #fixtures == 0 then return end

    local f = fixtures[1]
    if f.status ~= "finished" then return end

    local winner
    if f.homeGoals > f.awayGoals then
        winner = f.homeTeamId
    elseif f.awayGoals > f.homeGoals then
        winner = f.awayTeamId
    else
        -- 平局：点球大战（随机）
        winner = Random() < 0.5 and f.homeTeamId or f.awayTeamId
    end

    wc.champion = winner
    wc.phase = Tournament.PHASE_COMPLETED

    local championName = WorldCup._getNationName(winner)
    gameState:addNews({
        category = "world_cup_news",
        title = string.format("世界杯冠军: %s!", championName),
        body = string.format("%s 赢得了 %d 年世界杯冠军！",
            championName, wc.season),
    })

    -- 如果有玩家球员参赛
    local playerNation = WorldCup._getPlayerNation(gameState)
    if playerNation and playerNation == winner then
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯冠军！",
            body = string.format("你所在的国家队赢得了 %d 世界杯！这是足球的最高荣誉！", wc.season),
            priority = "high",
        })
    end

    -- 记录系统：世界杯夺冠
    RecordsManager.onWorldCupChampionship(gameState, winner)

    EventBus.emit("world_cup_completed", winner)
end

------------------------------------------------------
-- 单场淘汰制胜者获取（世界杯不同于欧冠的两回合制）
------------------------------------------------------

function WorldCup._getSingleLegWinners(wc, phase)
    local fixtures = wc.knockout[phase]
    if not fixtures then return {} end

    local winners = {}
    -- 世界杯使用 generateKnockoutRound（产生两个 fixture per matchup），
    -- 但我们只看 leg1 作为单场淘汰
    local seen = {}
    for _, f in ipairs(fixtures) do
        if f.leg == 1 and f.status == "finished" and not seen[f.matchIndex] then
            seen[f.matchIndex] = true
            if f.homeGoals > f.awayGoals then
                table.insert(winners, f.homeTeamId)
            elseif f.awayGoals > f.homeGoals then
                table.insert(winners, f.awayTeamId)
            else
                -- 点球大战（随机）
                if Random() < 0.5 then
                    table.insert(winners, f.homeTeamId)
                else
                    table.insert(winners, f.awayTeamId)
                end
            end
        end
    end
    return winners
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

function WorldCup._getPlayerNation(gameState)
    -- 优先使用已确认的国家队执教身份
    if gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation then
        return gameState.nationalTeamCoach.nation
    end
    -- 退化方案：教练自身国籍
    local manager = gameState:getPlayerManager()
    if manager and manager.nationality then
        return manager.nationality
    end
    return nil
end

function WorldCup._getNationName(code)
    for _, n in ipairs(NATIONS) do
        if n.code == code then return n.name end
    end
    return code  -- 未知国家返回代码
end

function WorldCup._formatDrawResult(gameState, wc)
    local lines = {"世界杯小组赛分组:\n"}
    local groupNames = {}
    for name, _ in pairs(wc.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    for _, name in ipairs(groupNames) do
        local group = wc.groups[name]
        table.insert(lines, "【" .. name .. "组】")
        for _, code in ipairs(group.teamIds) do
            local nationName = WorldCup._getNationName(code)
            table.insert(lines, "  " .. nationName)
        end
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end

function WorldCup._formatKnockoutDraw(gameState, wc, matchups)
    local lines = {}
    for i, m in ipairs(matchups) do
        local n1 = WorldCup._getNationName(m[1])
        local n2 = WorldCup._getNationName(m[2])
        table.insert(lines, string.format("%d. %s vs %s", i, n1, n2))
    end
    return table.concat(lines, "\n")
end

------------------------------------------------------
-- 构建临时国家队对象（用于玩家手动操控比赛）
------------------------------------------------------

function WorldCup.buildNationalTeam(gameState, nationCode)
    -- 如果是玩家国家队且已选择大名单，优先使用玩家的选择
    local ntCoach = gameState.nationalTeamCoach
    if ntCoach and ntCoach.nation == nationCode and ntCoach.squad and #ntCoach.squad > 0 then
        return WorldCup._buildFromPlayerSquad(gameState, nationCode, ntCoach)
    end

    -- 收集该国籍所有可用球员
    local nationPlayers = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and not player.injured and player.nationality == nationCode then
            table.insert(nationPlayers, player)
        end
    end

    -- 按 overall 排序
    table.sort(nationPlayers, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    -- 选出23人大名单
    local squadSize = math.min(23, #nationPlayers)
    local squadIds = {}
    local startingIds = {}
    for i = 1, squadSize do
        table.insert(squadIds, nationPlayers[i].id)
    end

    -- 选出最佳11人首发（按位置分配）
    local positionSlots = { GK = 1, CB = 2, LB = 1, RB = 1, MID = 3, FWD = 3 }
    local posGroups = { GK = {}, DEF = {}, MID = {}, FWD = {} }
    for _, p in ipairs(nationPlayers) do
        local pos = p.position or "MID"
        if pos == "GK" then
            table.insert(posGroups.GK, p)
        elseif pos == "CB" or pos == "LB" or pos == "RB" then
            table.insert(posGroups.DEF, p)
        elseif pos == "ST" or pos == "CF" or pos == "LW" or pos == "RW" then
            table.insert(posGroups.FWD, p)
        else
            table.insert(posGroups.MID, p)
        end
    end

    -- GK x1, DEF x4, MID x3, FWD x3
    local targets = { { group = "GK", count = 1 }, { group = "DEF", count = 4 }, { group = "MID", count = 3 }, { group = "FWD", count = 3 } }
    local used = {}
    for _, target in ipairs(targets) do
        local pool = posGroups[target.group]
        local added = 0
        for _, p in ipairs(pool) do
            if added >= target.count then break end
            if not used[p.id] then
                table.insert(startingIds, p.id)
                used[p.id] = true
                added = added + 1
            end
        end
    end

    -- 如果不足11人，从剩余球员补充
    if #startingIds < 11 then
        for _, pid in ipairs(squadIds) do
            if #startingIds >= 11 then break end
            if not used[pid] then
                table.insert(startingIds, pid)
                used[pid] = true
            end
        end
    end

    -- 如果存在玩家之前保存的国家队设置，使用它
    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"

    -- 构建虚拟 team 对象
    local nationName = WorldCup._getNationName(nationCode)
    local nationalTeam = {
        id = nationCode,  -- 用国家代码作为ID
        name = nationName,
        shortName = nationCode,
        formation = formation,
        playStyle = playStyle,
        attackMode = "balanced",
        startingXI = startingIds,
        playerIds = squadIds,
        playerDuties = {},
        slotRoles = {},
        recentForm = {},
        _isNationalTeam = true,
    }

    return nationalTeam
end

------------------------------------------------------
-- 保存玩家对国家队的战术设置
------------------------------------------------------

function WorldCup.saveNationalTeamSettings(gameState, nationCode, team)
    if not gameState._nationalTeamSettings then
        gameState._nationalTeamSettings = {}
    end
    gameState._nationalTeamSettings[nationCode] = {
        formation = team.formation,
        playStyle = team.playStyle,
        startingXI = team.startingXI,
    }
end

------------------------------------------------------
-- 判断某个 fixture 是否是玩家国家队的比赛
------------------------------------------------------

function WorldCup.isPlayerNationMatch(gameState, fixture)
    local playerNation = WorldCup._getPlayerNation(gameState)
    if not playerNation then return false end
    return fixture.homeTeamId == playerNation or fixture.awayTeamId == playerNation
end

------------------------------------------------------
-- 从玩家选择的大名单构建国家队对象
------------------------------------------------------

function WorldCup._buildFromPlayerSquad(gameState, nationCode, ntCoach)
    local squadIds = ntCoach.squad
    -- 验证球员可用性（排除受伤/退役）
    local validIds = {}
    for _, pid in ipairs(squadIds) do
        local p = gameState.players[pid]
        if p and not p.retired and not p.injured then
            table.insert(validIds, pid)
        end
    end

    -- 首发11人（使用保存的设置或自动选择）
    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local startingIds = (saved and saved.startingXI) or {}

    -- 如果没有保存的首发或者首发不足11人，自动补齐
    if #startingIds < 11 then
        local posGroups = { GK = {}, DEF = {}, MID = {}, FWD = {} }
        for _, pid in ipairs(validIds) do
            local p = gameState.players[pid]
            if p then
                local pos = p.position or "MID"
                if pos == "GK" then
                    table.insert(posGroups.GK, p)
                elseif pos == "CB" or pos == "LB" or pos == "RB" then
                    table.insert(posGroups.DEF, p)
                elseif pos == "ST" or pos == "CF" or pos == "LW" or pos == "RW" then
                    table.insert(posGroups.FWD, p)
                else
                    table.insert(posGroups.MID, p)
                end
            end
        end
        startingIds = {}
        local used = {}
        local targets = { { group = "GK", count = 1 }, { group = "DEF", count = 4 }, { group = "MID", count = 3 }, { group = "FWD", count = 3 } }
        for _, target in ipairs(targets) do
            local pool = posGroups[target.group]
            local added = 0
            for _, p in ipairs(pool) do
                if added >= target.count then break end
                if not used[p.id] then
                    table.insert(startingIds, p.id)
                    used[p.id] = true
                    added = added + 1
                end
            end
        end
        -- 不足11人补充
        for _, pid in ipairs(validIds) do
            if #startingIds >= 11 then break end
            if not used[pid] then
                table.insert(startingIds, pid)
                used[pid] = true
            end
        end
    end

    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"
    local nationName = WorldCup._getNationName(nationCode)

    return {
        id = nationCode,
        name = nationName,
        shortName = nationCode,
        formation = formation,
        playStyle = playStyle,
        attackMode = "balanced",
        startingXI = startingIds,
        playerIds = validIds,
        playerDuties = {},
        slotRoles = {},
        recentForm = {},
        _isNationalTeam = true,
    }
end

------------------------------------------------------
-- 获取某国籍所有可选球员（供大名单选择界面使用）
------------------------------------------------------

function WorldCup.getAvailablePlayers(gameState, nationCode)
    local players = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and player.nationality == nationCode then
            table.insert(players, player)
        end
    end
    table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
    return players
end

return WorldCup
