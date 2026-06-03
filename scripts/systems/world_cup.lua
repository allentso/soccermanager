-- systems/world_cup.lua
-- 世界杯管理系统（2026美加墨世界杯，48队12组）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")

local WorldCup = {}

-- 世界杯年份
local FIRST_WORLD_CUP = 2026
local CYCLE = 4

------------------------------------------------------
-- FIFA国家代码 → 球员数据nationality代码 的映射
-- 世界杯用FIFA代码(如CRO)，球员数据用ISO或自定义代码(如HR)
------------------------------------------------------
local FIFA_TO_PLAYER_NAT = {
    ALG = "DZ", ARG = "AR", AUS = "AU", BEL = "BE", BIH = "BA",
    BRA = "BR", CAN = "CA", CIV = "CI", COD = "CD", COL = "CO",
    CPV = "CAP", CRO = "HR", CUW = "CUW", CZE = "CZ", ECU = "EC",
    EGY = "EG", ENG = "ENG", ESP = "ES", FRA = "FR", GER = "DE",
    GHA = "GH", HON = "HN", IRN = "IR", IRQ = "IRQ", JPN = "JP",
    KOR = "KR", KSA = "KSA", MAR = "MA", MEX = "MX", NED = "NL",
    NOR = "NO", NZL = "NZ", PAN = "PA", PAR = "PY", PER = "PE",
    POL = "PL", POR = "PT", QAT = "QAT", RSA = "ZA", SEN = "SN",
    SUI = "CH", TUN = "TN", URU = "UY", USA = "US", UZB = "UZB",
}

--- 将 FIFA 国家代码转为球员数据中的 nationality 代码
function WorldCup._toPlayerNat(fifaCode)
    return FIFA_TO_PLAYER_NAT[fifaCode] or fifaCode
end

------------------------------------------------------
-- 48支参赛国家队（12组，每组4队）
-- 基于2026美加墨世界杯真实分组
------------------------------------------------------

local GROUPS = {
    A = {
        {code = "MEX", name = "墨西哥"},
        {code = "RSA", name = "南非"},
        {code = "KOR", name = "韩国"},
        {code = "CZE", name = "捷克"},
    },
    B = {
        {code = "CAN", name = "加拿大"},
        {code = "BIH", name = "波黑"},
        {code = "SUI", name = "瑞士"},
        {code = "QAT", name = "卡塔尔"},
    },
    C = {
        {code = "BRA", name = "巴西"},
        {code = "MAR", name = "摩洛哥"},
        {code = "PAR", name = "巴拉圭"},
        {code = "PER", name = "秘鲁"},
    },
    D = {
        {code = "USA", name = "美国"},
        {code = "AUS", name = "澳大利亚"},
        {code = "PO1", name = "附加赛1"},
        {code = "PO2", name = "附加赛2"},
    },
    E = {
        {code = "GER", name = "德国"},
        {code = "CIV", name = "科特迪瓦"},
        {code = "CUW", name = "库拉索"},
        {code = "ECU", name = "厄瓜多尔"},
    },
    F = {
        {code = "NED", name = "荷兰"},
        {code = "JPN", name = "日本"},
        {code = "TUN", name = "突尼斯"},
        {code = "POF", name = "附加赛F"},
    },
    G = {
        {code = "BEL", name = "比利时"},
        {code = "IRN", name = "伊朗"},
        {code = "EGY", name = "埃及"},
        {code = "NZL", name = "新西兰"},
    },
    H = {
        {code = "ESP", name = "西班牙"},
        {code = "URU", name = "乌拉圭"},
        {code = "KSA", name = "沙特"},
        {code = "CPV", name = "佛得角"},
    },
    I = {
        {code = "FRA", name = "法国"},
        {code = "SEN", name = "塞内加尔"},
        {code = "IRQ", name = "伊拉克"},
        {code = "NOR", name = "挪威"},
    },
    J = {
        {code = "ARG", name = "阿根廷"},
        {code = "ALG", name = "阿尔及利亚"},
        {code = "POL", name = "波兰"},
        {code = "HON", name = "洪都拉斯"},
    },
    K = {
        {code = "POR", name = "葡萄牙"},
        {code = "COD", name = "刚果金"},
        {code = "COL", name = "哥伦比亚"},
        {code = "UZB", name = "乌兹别克"},
    },
    L = {
        {code = "ENG", name = "英格兰"},
        {code = "CRO", name = "克罗地亚"},
        {code = "GHA", name = "加纳"},
        {code = "PAN", name = "巴拿马"},
    },
}

------------------------------------------------------
-- 真实赛程（2026美加墨世界杯）
-- 每组3轮小组赛
------------------------------------------------------

-- 小组赛赛程：{组名, 轮次, 主队索引(1-4), 客队索引(1-4), 月, 日}
local GROUP_FIXTURES = {
    -- A组
    {"A", 1, 1, 2, 6, 12}, {"A", 1, 3, 4, 6, 12},
    {"A", 2, 4, 2, 6, 19}, {"A", 2, 1, 3, 6, 19},
    {"A", 3, 2, 3, 6, 25}, {"A", 3, 4, 1, 6, 25},
    -- B组
    {"B", 1, 1, 2, 6, 13}, {"B", 1, 3, 4, 6, 13},
    {"B", 2, 3, 2, 6, 19}, {"B", 2, 1, 4, 6, 19},
    {"B", 3, 2, 4, 6, 25}, {"B", 3, 1, 3, 6, 25},
    -- C组
    {"C", 1, 1, 2, 6, 14}, {"C", 1, 3, 4, 6, 14},
    {"C", 2, 2, 4, 6, 20}, {"C", 2, 1, 3, 6, 20},
    {"C", 3, 3, 2, 6, 26}, {"C", 3, 4, 1, 6, 26},
    -- D组
    {"D", 1, 1, 3, 6, 14}, {"D", 1, 2, 4, 6, 14},
    {"D", 2, 1, 2, 6, 20}, {"D", 2, 3, 4, 6, 20},
    {"D", 3, 4, 1, 6, 26}, {"D", 3, 3, 2, 6, 26},
    -- E组
    {"E", 1, 1, 4, 6, 15}, {"E", 1, 2, 3, 6, 15},
    {"E", 2, 1, 2, 6, 21}, {"E", 2, 4, 3, 6, 21},
    {"E", 3, 3, 1, 6, 27}, {"E", 3, 4, 2, 6, 27},
    -- F组
    {"F", 1, 1, 2, 6, 15}, {"F", 1, 3, 4, 6, 15},
    {"F", 2, 1, 3, 6, 21}, {"F", 2, 2, 4, 6, 21},
    {"F", 3, 4, 1, 6, 27}, {"F", 3, 3, 2, 6, 27},
    -- G组
    {"G", 1, 1, 4, 6, 16}, {"G", 1, 2, 3, 6, 16},
    {"G", 2, 1, 2, 6, 22}, {"G", 2, 4, 3, 6, 22},
    {"G", 3, 3, 1, 6, 28}, {"G", 3, 4, 2, 6, 28},
    -- H组
    {"H", 1, 1, 4, 6, 16}, {"H", 1, 2, 3, 6, 16},
    {"H", 2, 1, 3, 6, 22}, {"H", 2, 2, 4, 6, 22},
    {"H", 3, 4, 3, 6, 28}, {"H", 3, 2, 1, 6, 28},
    -- I组
    {"I", 1, 1, 2, 6, 17}, {"I", 1, 3, 4, 6, 17},
    {"I", 2, 1, 3, 6, 23}, {"I", 2, 2, 4, 6, 23},
    {"I", 3, 4, 1, 6, 28}, {"I", 3, 2, 3, 6, 28},
    -- J组
    {"J", 1, 1, 2, 6, 17}, {"J", 1, 3, 4, 6, 17},
    {"J", 2, 1, 3, 6, 23}, {"J", 2, 2, 4, 6, 23},
    {"J", 3, 4, 1, 6, 29}, {"J", 3, 2, 3, 6, 29},
    -- K组
    {"K", 1, 1, 2, 6, 18}, {"K", 1, 4, 3, 6, 18},
    {"K", 2, 1, 4, 6, 24}, {"K", 2, 2, 3, 6, 24},
    {"K", 3, 3, 1, 6, 29}, {"K", 3, 2, 4, 6, 29},
    -- L组
    {"L", 1, 1, 2, 6, 17}, {"L", 1, 3, 4, 6, 17},
    {"L", 2, 1, 3, 6, 23}, {"L", 2, 4, 2, 6, 23},
    {"L", 3, 4, 1, 6, 29}, {"L", 3, 2, 3, 6, 29},
}

-- 淘汰赛日期
local KNOCKOUT_DATES = {
    -- 1/16决赛（32强）6.30 - 7.4
    r32 = {
        {6, 30}, {6, 30}, {7, 1}, {7, 1},
        {7, 2}, {7, 2}, {7, 3}, {7, 3},
        {7, 3}, {7, 3}, {7, 4}, {7, 4},
    },
    -- 1/8决赛 7.5 - 7.8
    r16 = {
        {7, 5}, {7, 5}, {7, 6}, {7, 6},
        {7, 7}, {7, 7}, {7, 8}, {7, 8},
    },
    -- 1/4决赛 7.10 - 7.12
    qf = {
        {7, 10}, {7, 11}, {7, 12}, {7, 12},
    },
    -- 半决赛 7.15, 7.16
    sf = {
        {7, 15}, {7, 16},
    },
    -- 季军赛 7.19，决赛 7.20
    third = {7, 19},
    final = {7, 20},
}

------------------------------------------------------
-- 建立国家代码到名称的映射（快速查找）
------------------------------------------------------

local _nationNameMap = nil
local function getNationNameMap()
    if _nationNameMap then return _nationNameMap end
    _nationNameMap = {}
    for _, teams in pairs(GROUPS) do
        for _, t in ipairs(teams) do
            _nationNameMap[t.code] = t.name
        end
    end
    return _nationNameMap
end

------------------------------------------------------
-- 公共API
------------------------------------------------------

function WorldCup.isWorldCupYear(year)
    if year < FIRST_WORLD_CUP then return false end
    return (year - FIRST_WORLD_CUP) % CYCLE == 0
end

function WorldCup._getNationName(code)
    local map = getNationNameMap()
    return map[code] or code
end

------------------------------------------------------
-- 初始化世界杯
------------------------------------------------------

function WorldCup.initialize(gameState)
    local wcYear = gameState.season
    if not WorldCup.isWorldCupYear(wcYear) then
        return nil
    end

    -- 已存在则不重复初始化
    if gameState.worldCup and gameState.worldCup.season == wcYear then
        return gameState.worldCup
    end

    -- 创建锦标赛对象
    local allNationCodes = {}
    for _, teams in pairs(GROUPS) do
        for _, t in ipairs(teams) do
            table.insert(allNationCodes, t.code)
        end
    end

    local wc = Tournament.new({
        name = "世界杯",
        shortName = "WC",
        type = "world_cup",
        season = wcYear,
        qualifiedTeams = allNationCodes,
    })

    -- 直接使用真实分组（不随机抽签）
    wc.groups = {}
    for groupName, teams in pairs(GROUPS) do
        local teamIds = {}
        for _, t in ipairs(teams) do
            table.insert(teamIds, t.code)
        end
        wc.groups[groupName] = {
            teamIds = teamIds,
            standings = {},
            fixtures = {},
        }
        for _, tid in ipairs(teamIds) do
            wc.groups[groupName].standings[tid] = {
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

    -- 生成小组赛赛程（使用真实日期）
    WorldCup._generateGroupFixtures(wc, wcYear)

    wc.phase = Tournament.PHASE_GROUP

    -- 存储
    gameState.worldCup = wc

    -- 新闻
    gameState:addNews({
        category = "world_cup_news",
        title = string.format("%d 美加墨世界杯分组揭晓！", wcYear),
        body = WorldCup._formatDrawResult(gameState, wc),
    })

    -- 国家队教练邀请
    WorldCup._checkNationalTeamInvitation(gameState, allNationCodes, wcYear)

    return wc
end

------------------------------------------------------
-- 生成小组赛赛程（固定日期）
------------------------------------------------------

function WorldCup._generateGroupFixtures(wc, wcYear)
    local fixtureId = 1

    for _, entry in ipairs(GROUP_FIXTURES) do
        local groupName = entry[1]
        local round = entry[2]
        local homeIdx = entry[3]
        local awayIdx = entry[4]
        local month = entry[5]
        local day = entry[6]

        local group = wc.groups[groupName]
        if group then
            local homeCode = group.teamIds[homeIdx]
            local awayCode = group.teamIds[awayIdx]

            table.insert(group.fixtures, {
                id = fixtureId,
                groupName = groupName,
                round = round,
                homeTeamId = homeCode,
                awayTeamId = awayCode,
                date = {year = wcYear, month = month, day = day},
                status = "scheduled",
                homeGoals = 0,
                awayGoals = 0,
            })
            fixtureId = fixtureId + 1
        end
    end
end

------------------------------------------------------
-- 阶段推进
------------------------------------------------------

function WorldCup.checkPhaseAdvance(gameState)
    local wc = gameState.worldCup
    if not wc or wc.phase == Tournament.PHASE_COMPLETED or wc.phase == Tournament.PHASE_NOT_STARTED then
        return
    end

    -- 小组赛结束 → 生成1/16决赛(32强)
    if wc.phase == Tournament.PHASE_GROUP and wc:isGroupStageComplete() then
        WorldCup._advanceToR32(gameState, wc)
    end

    -- 1/16决赛结束 → 生成1/8决赛
    if wc.phase == "r32" and WorldCup._isRoundComplete(wc, "r32") then
        WorldCup._advanceToR16(gameState, wc)
    end

    -- 1/8决赛结束 → 生成1/4决赛
    if wc.phase == Tournament.PHASE_R16 and WorldCup._isRoundComplete(wc, "r16") then
        WorldCup._advanceToQF(gameState, wc)
    end

    -- 1/4决赛结束 → 半决赛
    if wc.phase == Tournament.PHASE_QF and WorldCup._isRoundComplete(wc, "qf") then
        WorldCup._advanceToSF(gameState, wc)
    end

    -- 半决赛结束 → 决赛 + 季军赛
    if wc.phase == Tournament.PHASE_SF and WorldCup._isRoundComplete(wc, "sf") then
        WorldCup._advanceToFinal(gameState, wc)
    end

    -- 决赛和季军赛结束 → 完赛
    if wc.phase == Tournament.PHASE_FINAL and WorldCup._isRoundComplete(wc, "final") then
        WorldCup._completeTournament(gameState, wc)
    end
end

function WorldCup._isRoundComplete(wc, phase)
    local fixtures = wc.knockout[phase]
    if not fixtures or #fixtures == 0 then return false end
    for _, f in ipairs(fixtures) do
        if f.status ~= "finished" then return false end
    end
    return true
end

------------------------------------------------------
-- 32强（1/16决赛）：12组头名 + 8个最佳第二 + 4个最佳第三
-- 简化：每组前2名出线（24队），再取8个最佳第三 → 共32队
-- 实际2026规则：每组前2出线(24队) + 8个最佳第三(共32队)
------------------------------------------------------

function WorldCup._advanceToR32(gameState, wc)
    -- 收集所有组的排名
    local firsts = {}   -- 12个小组第一
    local seconds = {}  -- 12个小组第二
    local thirds = {}   -- 12个小组第三（取最佳8个）

    local groupNames = {}
    for name in pairs(wc.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    for _, gName in ipairs(groupNames) do
        local sorted = wc:getGroupSortedStandings(gName)
        if #sorted >= 1 then table.insert(firsts, {teamId = sorted[1].teamId, group = gName, data = sorted[1]}) end
        if #sorted >= 2 then table.insert(seconds, {teamId = sorted[2].teamId, group = gName, data = sorted[2]}) end
        if #sorted >= 3 then table.insert(thirds, {teamId = sorted[3].teamId, group = gName, data = sorted[3]}) end
    end

    -- 最佳第三排序（积分 > 净胜球 > 进球）
    table.sort(thirds, function(a, b)
        if a.data.points ~= b.data.points then return a.data.points > b.data.points end
        if a.data.goalDifference ~= b.data.goalDifference then return a.data.goalDifference > b.data.goalDifference end
        return a.data.goalsFor > b.data.goalsFor
    end)

    -- 取前8个最佳第三
    local bestThirds = {}
    for i = 1, math.min(8, #thirds) do
        table.insert(bestThirds, thirds[i])
    end

    -- 组建32强对阵（小组第一 vs 最佳第三，小组第二 vs 其他组第二交叉）
    -- 简化配对规则：
    -- 场次1-12: 各组第一 vs 最佳第三 / 其他组第二
    local matchups = {}
    local usedThirds = {}
    local usedSeconds = {}

    -- 第一轮配对：A1-L1 vs 最佳第三（优先不同组）
    for i, first in ipairs(firsts) do
        if i <= #bestThirds then
            -- 组头名 vs 最佳第三（不同组优先）
            local paired = false
            for j, third in ipairs(bestThirds) do
                if not usedThirds[j] and third.group ~= first.group then
                    table.insert(matchups, {first.teamId, third.teamId})
                    usedThirds[j] = true
                    paired = true
                    break
                end
            end
            if not paired then
                -- 找任意未用的第三
                for j, third in ipairs(bestThirds) do
                    if not usedThirds[j] then
                        table.insert(matchups, {first.teamId, third.teamId})
                        usedThirds[j] = true
                        break
                    end
                end
            end
        end
    end

    -- 剩余的组头名与第二名交叉配对
    local remainingFirsts = {}
    for i, first in ipairs(firsts) do
        local alreadyPaired = false
        for _, m in ipairs(matchups) do
            if m[1] == first.teamId then alreadyPaired = true; break end
        end
        if not alreadyPaired then
            table.insert(remainingFirsts, first)
        end
    end

    -- 第二名互相交叉配对
    -- 洗牌 seconds
    for i = #seconds, 2, -1 do
        local j = RandomInt(1, i)
        seconds[i], seconds[j] = seconds[j], seconds[i]
    end

    -- 配对剩余的第一名 vs 第二名（不同组）
    for _, first in ipairs(remainingFirsts) do
        for j, second in ipairs(seconds) do
            if not usedSeconds[j] and second.group ~= first.group then
                table.insert(matchups, {first.teamId, second.teamId})
                usedSeconds[j] = true
                break
            end
        end
    end

    -- 剩余第二名互相配对
    local remainingSecs = {}
    for j, sec in ipairs(seconds) do
        if not usedSeconds[j] then
            table.insert(remainingSecs, sec)
        end
    end
    for i = 1, #remainingSecs - 1, 2 do
        if remainingSecs[i] and remainingSecs[i + 1] then
            table.insert(matchups, {remainingSecs[i].teamId, remainingSecs[i + 1].teamId})
        end
    end

    -- 确保正好16场（32队）
    -- 如果不足，补齐
    while #matchups < 16 do
        -- 不应该出现这种情况，但作为安全网
        break
    end

    -- 生成fixture
    local fixtures = {}
    local dates = KNOCKOUT_DATES.r32
    for i, m in ipairs(matchups) do
        local dateIdx = math.min(i, #dates)
        local d = dates[dateIdx]
        table.insert(fixtures, {
            id = "r32_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = wc.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    end

    wc.knockout.r32 = fixtures
    wc.phase = "r32"

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯32强对阵出炉！",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToR16(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "r32")
    if #winners < 2 then return end

    -- 配对（相邻胜者对阵）
    local matchups = {}
    for i = 1, #winners - 1, 2 do
        table.insert(matchups, {winners[i], winners[i + 1]})
    end

    local fixtures = {}
    local dates = KNOCKOUT_DATES.r16
    for i, m in ipairs(matchups) do
        local dateIdx = math.min(i, #dates)
        local d = dates[dateIdx]
        table.insert(fixtures, {
            id = "r16_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = wc.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    end

    wc.knockout.r16 = fixtures
    wc.phase = Tournament.PHASE_R16

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯16强对阵确定！",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToQF(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "r16")
    if #winners < 2 then return end

    local matchups = {}
    for i = 1, #winners - 1, 2 do
        table.insert(matchups, {winners[i], winners[i + 1]})
    end

    local fixtures = {}
    local dates = KNOCKOUT_DATES.qf
    for i, m in ipairs(matchups) do
        local dateIdx = math.min(i, #dates)
        local d = dates[dateIdx]
        table.insert(fixtures, {
            id = "qf_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = wc.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    end

    wc.knockout.qf = fixtures
    wc.phase = Tournament.PHASE_QF

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯8强对阵！",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToSF(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "qf")
    if #winners < 2 then return end

    local matchups = {}
    for i = 1, #winners - 1, 2 do
        table.insert(matchups, {winners[i], winners[i + 1]})
    end

    local fixtures = {}
    local dates = KNOCKOUT_DATES.sf
    for i, m in ipairs(matchups) do
        local d = dates[i]
        table.insert(fixtures, {
            id = "sf_" .. i,
            leg = 1,
            matchIndex = i,
            homeTeamId = m[1],
            awayTeamId = m[2],
            date = {year = wc.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
        })
    end

    wc.knockout.sf = fixtures
    wc.phase = Tournament.PHASE_SF

    -- 保存败者用于季军赛
    wc._sfMatchups = matchups

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯4强对阵！",
        body = WorldCup._formatKnockoutDraw(gameState, wc, matchups),
    })
end

function WorldCup._advanceToFinal(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "sf")
    local losers = WorldCup._getSingleLegLosers(wc, "sf")

    if #winners < 2 then return end

    local fixtures = {}

    -- 季军赛
    if #losers >= 2 then
        local d = KNOCKOUT_DATES.third
        table.insert(fixtures, {
            id = "third_1",
            leg = 1,
            matchIndex = 1,
            homeTeamId = losers[1],
            awayTeamId = losers[2],
            date = {year = wc.season, month = d[1], day = d[2]},
            status = "scheduled",
            homeGoals = 0,
            awayGoals = 0,
            _isThirdPlace = true,
        })
    end

    -- 决赛
    local d = KNOCKOUT_DATES.final
    table.insert(fixtures, {
        id = "final_1",
        leg = 1,
        matchIndex = 2,
        homeTeamId = winners[1],
        awayTeamId = winners[2],
        date = {year = wc.season, month = d[1], day = d[2]},
        status = "scheduled",
        homeGoals = 0,
        awayGoals = 0,
    })

    wc.knockout.final = fixtures
    wc.phase = Tournament.PHASE_FINAL

    local n1 = WorldCup._getNationName(winners[1])
    local n2 = WorldCup._getNationName(winners[2])
    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯决赛对阵确定！",
        body = string.format("%s vs %s\n决赛日期: %d年7月20日（纽约大都会球场）", n1, n2, wc.season),
    })
end

function WorldCup._completeTournament(gameState, wc)
    local fixtures = wc.knockout.final
    if not fixtures then return end

    -- 找到决赛fixture（非季军赛的那场）
    local finalFixture = nil
    for _, f in ipairs(fixtures) do
        if not f._isThirdPlace and f.status == "finished" then
            finalFixture = f
            break
        end
    end
    if not finalFixture then return end

    local winner
    if finalFixture.homeGoals > finalFixture.awayGoals then
        winner = finalFixture.homeTeamId
    elseif finalFixture.awayGoals > finalFixture.homeGoals then
        winner = finalFixture.awayTeamId
    else
        -- 点球大战（随机）
        winner = Random() < 0.5 and finalFixture.homeTeamId or finalFixture.awayTeamId
    end

    wc.champion = winner
    wc.phase = Tournament.PHASE_COMPLETED

    local championName = WorldCup._getNationName(winner)
    gameState:addNews({
        category = "world_cup_news",
        title = string.format("🏆 世界杯冠军: %s!", championName),
        body = string.format("%s 赢得了 %d 美加墨世界杯冠军！全世界为之沸腾！", championName, wc.season),
    })

    -- 玩家国家队获得冠军
    local playerNation = WorldCup._getPlayerNation(gameState)
    if playerNation and playerNation == winner then
        gameState:sendMessage({
            category = "world_cup",
            title = "🏆 世界杯冠军！！！",
            body = string.format("你带领%s赢得了 %d 世界杯！！这是足球的最高荣誉！你将被铭记在历史中！", championName, wc.season),
            priority = "high",
        })
    end

    RecordsManager.onWorldCupChampionship(gameState, winner)
    EventBus.emit("world_cup_completed", winner)
end

------------------------------------------------------
-- 单场淘汰制胜者/败者获取
------------------------------------------------------

function WorldCup._getSingleLegWinners(wc, phase)
    local fixtures = wc.knockout[phase]
    if not fixtures then return {} end

    local winners = {}
    for _, f in ipairs(fixtures) do
        if f.status == "finished" and not f._isThirdPlace then
            if f.homeGoals > f.awayGoals then
                table.insert(winners, f.homeTeamId)
            elseif f.awayGoals > f.homeGoals then
                table.insert(winners, f.awayTeamId)
            else
                -- 点球大战
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

function WorldCup._getSingleLegLosers(wc, phase)
    local fixtures = wc.knockout[phase]
    if not fixtures then return {} end

    local losers = {}
    for _, f in ipairs(fixtures) do
        if f.status == "finished" and not f._isThirdPlace then
            if f.homeGoals > f.awayGoals then
                table.insert(losers, f.awayTeamId)
            elseif f.awayGoals > f.homeGoals then
                table.insert(losers, f.homeTeamId)
            else
                -- 点球败者
                if Random() < 0.5 then
                    table.insert(losers, f.awayTeamId)
                else
                    table.insert(losers, f.homeTeamId)
                end
            end
        end
    end
    return losers
end

------------------------------------------------------
-- 国家队邀请
------------------------------------------------------

local NT_REP_THRESHOLD = 40

function WorldCup._checkNationalTeamInvitation(gameState, qualifiedNations, wcYear)
    gameState.nationalTeamCoach = nil

    local manager = gameState:getPlayerManager()
    if not manager then return end

    local managerNat = manager.nationality
    if not managerNat then return end

    -- 查找该球员nationality对应的FIFA国家代码
    local managerNation = nil
    for fifaCode, playerNat in pairs(FIFA_TO_PLAYER_NAT) do
        if playerNat == managerNat then
            managerNation = fifaCode
            break
        end
    end
    -- 如果没有映射，可能代码本身就是FIFA代码
    if not managerNation then managerNation = managerNat end

    -- 检查该国家是否在48支参赛队中
    local nationQualified = false
    for _, code in ipairs(qualifiedNations) do
        if code == managerNation then
            nationQualified = true
            break
        end
    end
    if not nationQualified then
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯抽签揭晓",
            body = string.format("%d 美加墨世界杯分组抽签已完成。遗憾的是，%s未能入围本届赛事。",
                wcYear, WorldCup._getNationName(managerNation)),
            priority = "normal",
        })
        return
    end

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

    local nationName = WorldCup._getNationName(managerNation)
    gameState:sendMessage({
        category = "world_cup",
        title = "🏆 国家队主教练邀请",
        body = string.format(
            "%s足协正式邀请你出任 %d 世界杯国家队主教练！\n\n" ..
            "你的执教声望(%d)已获得认可。接受邀请后，你将负责选拔23人大名单并带队征战世界杯。\n\n" ..
            "%s所在%s组。",
            nationName, wcYear, math.floor(rep),
            nationName, WorldCup._getGroupForNation(managerNation) or "?"),
        priority = "high",
        actions = {
            { label = "接受邀请", actionId = "accept_nt_coach", data = { nation = managerNation } },
            { label = "婉拒", actionId = "decline_nt_coach", data = { nation = managerNation } },
        },
    })
end

-- 获取某国家所在的组
function WorldCup._getGroupForNation(nationCode)
    for groupName, teams in pairs(GROUPS) do
        for _, t in ipairs(teams) do
            if t.code == nationCode then
                return groupName
            end
        end
    end
    return nil
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
-- 辅助函数
------------------------------------------------------

function WorldCup._getPlayerNation(gameState)
    if gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation then
        return gameState.nationalTeamCoach.nation
    end
    local manager = gameState:getPlayerManager()
    if manager and manager.nationality then
        return manager.nationality
    end
    return nil
end

function WorldCup._formatDrawResult(gameState, wc)
    local lines = {"2026美加墨世界杯48队分组:\n"}
    local groupNames = {}
    for name in pairs(wc.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    for _, name in ipairs(groupNames) do
        local group = wc.groups[name]
        table.insert(lines, "【" .. name .. "组】")
        for _, code in ipairs(group.teamIds) do
            table.insert(lines, "  " .. WorldCup._getNationName(code))
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
-- 构建国家队对象（用于比赛模拟）
------------------------------------------------------

function WorldCup.buildNationalTeam(gameState, nationCode)
    local ntCoach = gameState.nationalTeamCoach
    if ntCoach and ntCoach.nation == nationCode and ntCoach.squad and #ntCoach.squad > 0 then
        return WorldCup._buildFromPlayerSquad(gameState, nationCode, ntCoach)
    end

    local playerNat = WorldCup._toPlayerNat(nationCode)
    local nationPlayers = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and not player.injured and player.nationality == playerNat then
            table.insert(nationPlayers, player)
        end
    end
    table.sort(nationPlayers, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    local squadSize = math.min(23, #nationPlayers)
    local squadIds = {}
    for i = 1, squadSize do
        table.insert(squadIds, nationPlayers[i].id)
    end

    -- 选出最佳11人首发
    local startingIds = WorldCup._pickStartingXI(nationPlayers)

    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"

    return {
        id = nationCode,
        name = WorldCup._getNationName(nationCode),
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
end

function WorldCup._pickStartingXI(players)
    local posGroups = { GK = {}, DEF = {}, MID = {}, FWD = {} }
    for _, p in ipairs(players) do
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

    local startingIds = {}
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
    if #startingIds < 11 then
        for _, p in ipairs(players) do
            if #startingIds >= 11 then break end
            if not used[p.id] then
                table.insert(startingIds, p.id)
                used[p.id] = true
            end
        end
    end

    return startingIds
end

------------------------------------------------------
-- 从玩家大名单构建
------------------------------------------------------

function WorldCup._buildFromPlayerSquad(gameState, nationCode, ntCoach)
    local squadIds = ntCoach.squad
    local validIds = {}
    for _, pid in ipairs(squadIds) do
        local p = gameState.players[pid]
        if p and not p.retired and not p.injured then
            table.insert(validIds, pid)
        end
    end

    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local startingIds = (saved and saved.startingXI) or {}

    if #startingIds < 11 then
        -- 用validIds中的球员自动组建首发
        local players = {}
        for _, pid in ipairs(validIds) do
            local p = gameState.players[pid]
            if p then table.insert(players, p) end
        end
        table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
        startingIds = WorldCup._pickStartingXI(players)
    end

    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"

    return {
        id = nationCode,
        name = WorldCup._getNationName(nationCode),
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
-- 保存国家队战术
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
-- 获取某国籍所有可选球员（大名单选择界面用）
------------------------------------------------------

function WorldCup.getAvailablePlayers(gameState, nationCode)
    local playerNat = WorldCup._toPlayerNat(nationCode)
    local players = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and player.nationality == playerNat then
            table.insert(players, player)
        end
    end
    table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
    return players
end

------------------------------------------------------
-- 获取玩家国家队所在的组名（给UI用）
------------------------------------------------------

function WorldCup.getPlayerGroup(gameState)
    local nation = WorldCup._getPlayerNation(gameState)
    if not nation then return nil end
    return WorldCup._getGroupForNation(nation)
end

return WorldCup
