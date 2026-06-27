-- systems/world_cup.lua
-- 世界杯管理系统（2026美加墨世界杯，48队12组）

local Tournament = require("scripts/domain/tournament")
local League = require("scripts/domain/league")
local Player = require("scripts/domain/player")
local EventBus = require("scripts/app/event_bus")
local RecordsManager = require("scripts/systems/records_manager")
local HistoryManager = require("scripts/systems/history_manager")
local NationIconRegistry = require("scripts/data/nation_icon_registry")
local Nationality = require("scripts/domain/nationality")

local WorldCup = {}

-- 世界杯年份
local FIRST_WORLD_CUP = 2026
local CYCLE = 4

------------------------------------------------------
-- 2030+：动态参赛国家池
-- 种子队（传统强队，每届必定入围）
-- 候补池（其余国家，每届随机抽取填满48支）
------------------------------------------------------

local SEED_NATIONS = {
    -- 欧洲传统强队（14支）
    {code = "FRA", name = "法国"},
    {code = "GER", name = "德国"},
    {code = "ESP", name = "西班牙"},
    {code = "ENG", name = "英格兰"},
    {code = "POR", name = "葡萄牙"},
    {code = "NED", name = "荷兰"},
    {code = "BEL", name = "比利时"},
    {code = "CRO", name = "克罗地亚"},
    -- 南美传统强队（4支）
    {code = "BRA", name = "巴西"},
    {code = "ARG", name = "阿根廷"},
    {code = "URU", name = "乌拉圭"},
    {code = "COL", name = "哥伦比亚"},
    -- 其他大洲顶尖（4支）
    {code = "USA", name = "美国"},
    {code = "MEX", name = "墨西哥"},
    {code = "JPN", name = "日本"},
    {code = "KOR", name = "韩国"},
}

-- 2030 起：中国队保底入围 + 执教邀请
local GUARANTEED_CHINA_CODE = "CHN"
local GUARANTEED_CHINA_NATION = {code = "CHN", name = "中国"}
local FIRST_WC_GUARANTEED_CHINA = 2030

function WorldCup.isGuaranteedChinaOfferYear(year)
    return year >= FIRST_WC_GUARANTEED_CHINA and WorldCup.isWorldCupYear(year)
end

local function _ensureChinaInWorldCup(allNations, selectedCodes, wcYear)
    if not WorldCup.isGuaranteedChinaOfferYear(wcYear) then return end
    if selectedCodes[GUARANTEED_CHINA_CODE] then return end
    table.insert(allNations, GUARANTEED_CHINA_NATION)
    selectedCodes[GUARANTEED_CHINA_CODE] = true
end

local function _addGuaranteedChinaOffer(offers, offerSet, qualifiedSet, year, isGuaranteedYearFn)
    if not isGuaranteedYearFn(year) then return end
    if not qualifiedSet[GUARANTEED_CHINA_CODE] or offerSet[GUARANTEED_CHINA_CODE] then return end
    table.insert(offers, GUARANTEED_CHINA_CODE)
    offerSet[GUARANTEED_CHINA_CODE] = true
end

local NON_SEED_NATIONS = {
    -- 欧洲
    {code = "SUI", name = "瑞士"},
    {code = "AUT", name = "奥地利"},
    {code = "TUR", name = "土耳其"},
    {code = "SWE", name = "瑞典"},
    {code = "NOR", name = "挪威"},
    {code = "SCO", name = "苏格兰"},
    {code = "CZE", name = "捷克"},
    {code = "POL", name = "波兰"},
    {code = "BIH", name = "波黑"},
    -- 南美
    {code = "ECU", name = "厄瓜多尔"},
    {code = "PAR", name = "巴拉圭"},
    {code = "PER", name = "秘鲁"},
    -- 非洲
    {code = "MAR", name = "摩洛哥"},
    {code = "SEN", name = "塞内加尔"},
    {code = "GHA", name = "加纳"},
    {code = "CIV", name = "科特迪瓦"},
    {code = "EGY", name = "埃及"},
    {code = "ALG", name = "阿尔及利亚"},
    {code = "TUN", name = "突尼斯"},
    {code = "RSA", name = "南非"},
    {code = "COD", name = "刚果金"},
    {code = "CPV", name = "佛得角"},
    -- 亚洲
    {code = "KSA", name = "沙特"},
    {code = "IRN", name = "伊朗"},
    {code = "AUS", name = "澳大利亚"},
    {code = "QAT", name = "卡塔尔"},
    {code = "IRQ", name = "伊拉克"},
    {code = "UZB", name = "乌兹别克"},
    {code = "JOR", name = "约旦"},
    -- 2030+ 保底入围（供玩家执教）
    {code = "CHN", name = "中国"},
    -- 中北美
    {code = "CAN", name = "加拿大"},
    {code = "PAN", name = "巴拿马"},
    {code = "HON", name = "洪都拉斯"},
    {code = "CUW", name = "库拉索"},
    {code = "HAI", name = "海地"},
    -- 大洋洲
    {code = "NZL", name = "新西兰"},
}

------------------------------------------------------
-- 国籍代码规范化（见 scripts/domain/nationality.lua）
------------------------------------------------------

--- 将 FIFA 国家代码转为球员数据中的 nationality 代码
function WorldCup._toPlayerNat(fifaCode)
    return Nationality.toPlayerNat(fifaCode)
end

function WorldCup._normalizePlayerNat(code)
    return Nationality.normalize(code)
end

function WorldCup._playerMatchesNat(playerNat, targetNat)
    return Nationality.matches(playerNat, targetNat)
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
        {code = "QAT", name = "卡塔尔"},
        {code = "SUI", name = "瑞士"},
    },
    C = {
        {code = "BRA", name = "巴西"},
        {code = "MAR", name = "摩洛哥"},
        {code = "HAI", name = "海地"},
        {code = "SCO", name = "苏格兰"},
    },
    D = {
        {code = "USA", name = "美国"},
        {code = "PAR", name = "巴拉圭"},
        {code = "AUS", name = "澳大利亚"},
        {code = "TUR", name = "土耳其"},
    },
    E = {
        {code = "GER", name = "德国"},
        {code = "CUW", name = "库拉索"},
        {code = "CIV", name = "科特迪瓦"},
        {code = "ECU", name = "厄瓜多尔"},
    },
    F = {
        {code = "NED", name = "荷兰"},
        {code = "JPN", name = "日本"},
        {code = "SWE", name = "瑞典"},
        {code = "TUN", name = "突尼斯"},
    },
    G = {
        {code = "BEL", name = "比利时"},
        {code = "EGY", name = "埃及"},
        {code = "IRN", name = "伊朗"},
        {code = "NZL", name = "新西兰"},
    },
    H = {
        {code = "ESP", name = "西班牙"},
        {code = "CPV", name = "佛得角"},
        {code = "KSA", name = "沙特"},
        {code = "URU", name = "乌拉圭"},
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
        {code = "AUT", name = "奥地利"},
        {code = "JOR", name = "约旦"},
    },
    K = {
        {code = "POR", name = "葡萄牙"},
        {code = "COD", name = "刚果金"},
        {code = "UZB", name = "乌兹别克"},
        {code = "COL", name = "哥伦比亚"},
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
    -- A组: 1=MEX, 2=RSA, 3=KOR, 4=CZE
    {"A", 1, 1, 2, 6, 12}, {"A", 1, 3, 4, 6, 12},
    {"A", 2, 4, 2, 6, 19}, {"A", 2, 1, 3, 6, 19},
    {"A", 3, 2, 3, 6, 25}, {"A", 3, 4, 1, 6, 25},
    -- B组: 1=CAN, 2=BIH, 3=QAT, 4=SUI
    {"B", 1, 1, 2, 6, 13}, {"B", 1, 3, 4, 6, 14},
    {"B", 2, 4, 2, 6, 19}, {"B", 2, 1, 3, 6, 19},
    {"B", 3, 4, 1, 6, 25}, {"B", 3, 2, 3, 6, 25},
    -- C组: 1=BRA, 2=MAR, 3=HAI, 4=SCO
    {"C", 1, 1, 2, 6, 14}, {"C", 1, 3, 4, 6, 14},
    {"C", 2, 4, 2, 6, 20}, {"C", 2, 1, 3, 6, 20},
    {"C", 3, 2, 3, 6, 25}, {"C", 3, 4, 1, 6, 25},
    -- D组: 1=USA, 2=PAR, 3=AUS, 4=TUR
    {"D", 1, 1, 2, 6, 13}, {"D", 1, 3, 4, 6, 14},
    {"D", 2, 1, 3, 6, 20}, {"D", 2, 4, 2, 6, 20},
    {"D", 3, 4, 1, 6, 26}, {"D", 3, 2, 3, 6, 26},
    -- E组: 1=GER, 2=CUW, 3=CIV, 4=ECU
    {"E", 1, 1, 2, 6, 15}, {"E", 1, 3, 4, 6, 15},
    {"E", 2, 1, 3, 6, 21}, {"E", 2, 4, 2, 6, 21},
    {"E", 3, 2, 3, 6, 26}, {"E", 3, 4, 1, 6, 26},
    -- F组: 1=NED, 2=JPN, 3=SWE, 4=TUN
    {"F", 1, 1, 2, 6, 15}, {"F", 1, 3, 4, 6, 15},
    {"F", 2, 1, 3, 6, 21}, {"F", 2, 4, 2, 6, 21},
    {"F", 3, 2, 3, 6, 26}, {"F", 3, 4, 1, 6, 26},
    -- G组: 1=BEL, 2=EGY, 3=IRN, 4=NZL
    {"G", 1, 1, 2, 6, 16}, {"G", 1, 3, 4, 6, 16},
    {"G", 2, 1, 3, 6, 22}, {"G", 2, 4, 2, 6, 22},
    {"G", 3, 4, 1, 6, 27}, {"G", 3, 2, 3, 6, 27},
    -- H组: 1=ESP, 2=CPV, 3=KSA, 4=URU
    {"H", 1, 1, 2, 6, 16}, {"H", 1, 3, 4, 6, 16},
    {"H", 2, 1, 3, 6, 22}, {"H", 2, 4, 2, 6, 22},
    {"H", 3, 4, 1, 6, 27}, {"H", 3, 2, 3, 6, 27},
    -- I组: 1=FRA, 2=SEN, 3=IRQ, 4=NOR
    {"I", 1, 1, 2, 6, 17}, {"I", 1, 3, 4, 6, 17},
    {"I", 2, 1, 3, 6, 23}, {"I", 2, 4, 2, 6, 23},
    {"I", 3, 4, 1, 6, 27}, {"I", 3, 2, 3, 6, 27},
    -- J组: 1=ARG, 2=ALG, 3=AUT, 4=JOR
    {"J", 1, 1, 2, 6, 17}, {"J", 1, 3, 4, 6, 17},
    {"J", 2, 1, 3, 6, 23}, {"J", 2, 4, 2, 6, 23},
    {"J", 3, 4, 1, 6, 28}, {"J", 3, 2, 3, 6, 28},
    -- K组: 1=POR, 2=COD, 3=UZB, 4=COL
    {"K", 1, 1, 2, 6, 18}, {"K", 1, 3, 4, 6, 18},
    {"K", 2, 1, 3, 6, 24}, {"K", 2, 4, 2, 6, 24},
    {"K", 3, 4, 1, 6, 28}, {"K", 3, 2, 3, 6, 28},
    -- L组: 1=ENG, 2=CRO, 3=GHA, 4=PAN
    {"L", 1, 1, 2, 6, 18}, {"L", 1, 3, 4, 6, 18},
    {"L", 2, 1, 3, 6, 24}, {"L", 2, 4, 2, 6, 24},
    {"L", 3, 4, 1, 6, 28}, {"L", 3, 2, 3, 6, 28},
}

-- 淘汰赛日期
local KNOCKOUT_DATES = {
    -- 32强（1/16决赛）6.30 - 7.4（16场）
    r32 = {
        {6, 30}, {6, 30}, {6, 30}, {6, 30},
        {7, 1}, {7, 1}, {7, 1}, {7, 1},
        {7, 2}, {7, 2}, {7, 2}, {7, 2},
        {7, 3}, {7, 3}, {7, 4}, {7, 4},
    },
    -- 16强（1/8决赛）7.5 - 7.8
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
    -- 从2026真实分组
    for _, teams in pairs(GROUPS) do
        for _, t in ipairs(teams) do
            _nationNameMap[t.code] = t.name
        end
    end
    -- 从种子队和候补池补充（覆盖2030+新增国家）
    for _, t in ipairs(SEED_NATIONS) do
        _nationNameMap[t.code] = _nationNameMap[t.code] or t.name
    end
    for _, t in ipairs(NON_SEED_NATIONS) do
        _nationNameMap[t.code] = _nationNameMap[t.code] or t.name
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

--- 根据国家中文名反查 FIFA 代码（旧存档兼容用）
function WorldCup._getNationCodeByName(name)
    local map = getNationNameMap()
    for code, n in pairs(map) do
        if n == name then return code end
    end
    return nil
end

function WorldCup.getNationIconPath(code)
    return NationIconRegistry.getPathByFifaCode(code)
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

    -- 确定本届参赛的48支国家
    local allNations = {}  -- { {code=..., name=...}, ... }

    if wcYear == FIRST_WORLD_CUP then
        -- 2026：使用固定的真实48支
        for _, teams in pairs(GROUPS) do
            for _, t in ipairs(teams) do
                table.insert(allNations, t)
            end
        end
    else
        -- 2030+：种子队必进 + 从候补池随机抽取剩余名额
        -- 如果玩家有国家队，确保该国必定参赛
        local playerNation = WorldCup._getPlayerNation(gameState)

        -- 先加入所有种子队
        local selectedCodes = {}
        for _, t in ipairs(SEED_NATIONS) do
            table.insert(allNations, t)
            selectedCodes[t.code] = true
        end

        -- 如果玩家国家队不在种子中，优先加入
        if playerNation and not selectedCodes[playerNation] then
            for _, t in ipairs(NON_SEED_NATIONS) do
                if t.code == playerNation then
                    table.insert(allNations, t)
                    selectedCodes[t.code] = true
                    break
                end
            end
        end

        _ensureChinaInWorldCup(allNations, selectedCodes, wcYear)

        -- 从候补池随机抽取填满48支
        local candidates = {}
        for _, t in ipairs(NON_SEED_NATIONS) do
            if not selectedCodes[t.code] then
                table.insert(candidates, t)
            end
        end
        -- Fisher-Yates 洗牌候补
        for i = #candidates, 2, -1 do
            local j = math.floor(Random() * i) + 1
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end
        -- 取前N个填满48支
        local remaining = 48 - #allNations
        for i = 1, math.min(remaining, #candidates) do
            table.insert(allNations, candidates[i])
        end
    end

    local allNationCodes = {}
    for _, t in ipairs(allNations) do
        table.insert(allNationCodes, t.code)
    end

    local wc = Tournament.new({
        name = "世界杯",
        shortName = "WC",
        type = "world_cup",
        season = wcYear,
        qualifiedTeams = allNationCodes,
    })

    -- 分组逻辑：2026使用真实分组，后续届次随机抽签
    local groupNames = {"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"}
    wc.groups = {}

    if wcYear == FIRST_WORLD_CUP then
        -- 2026：使用真实分组
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
        end
    else
        -- 2030+：将48支参赛队伍随机分入12组
        local shuffled = {}
        for i, t in ipairs(allNations) do shuffled[i] = t end
        for i = #shuffled, 2, -1 do
            local j = math.floor(Random() * i) + 1
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        end
        for g = 1, 12 do
            local gName = groupNames[g]
            local teamIds = {}
            for k = 1, 4 do
                local idx = (g - 1) * 4 + k
                table.insert(teamIds, shuffled[idx].code)
            end
            wc.groups[gName] = {
                teamIds = teamIds,
                standings = {},
                fixtures = {},
            }
        end
    end

    -- 初始化各组积分榜
    for _, group in pairs(wc.groups) do
        for _, tid in ipairs(group.teamIds) do
            group.standings[tid] = {
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

    -- 生成小组赛赛程（使用固定日期模板）
    WorldCup._generateGroupFixtures(wc, wcYear)

    wc.phase = Tournament.PHASE_GROUP

    -- 存储
    gameState.worldCup = wc

    -- 新闻
    local titleStr = wcYear == FIRST_WORLD_CUP
        and string.format("%d 美加墨世界杯分组揭晓！", wcYear)
        or string.format("%d 世界杯分组抽签结果揭晓！", wcYear)
    gameState:addNews({
        category = "world_cup_news",
        title = titleStr,
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
-- 32强（1/16决赛）：48队赛制，共16场
-- 出线规则：每组前2名（24队）+ 8个最佳第三名 = 32队
-- 对阵：组第一 vs 最佳第三名（交叉配对，避免同组）
--        组第二 vs 另一组的组第一或第二（交叉配对）
------------------------------------------------------

function WorldCup._advanceToR32(gameState, wc)
    -- 收集所有组的排名
    local groupNames = {}
    for name in pairs(wc.groups) do
        table.insert(groupNames, name)
    end
    table.sort(groupNames)

    local allFirsts = {}   -- 12个组第一
    local allSeconds = {}  -- 12个组第二
    local allThirds = {}   -- 12个组第三（选最佳8个）

    for _, gName in ipairs(groupNames) do
        local sorted = wc:getGroupSortedStandings(gName)
        if sorted[1] then
            table.insert(allFirsts, {teamId = sorted[1].teamId, group = gName, data = sorted[1]})
        end
        if sorted[2] then
            table.insert(allSeconds, {teamId = sorted[2].teamId, group = gName, data = sorted[2]})
        end
        if sorted[3] then
            table.insert(allThirds, {teamId = sorted[3].teamId, group = gName, data = sorted[3]})
        end
    end

    -- 按成绩选8个最佳第三名（积分 > 净胜球 > 进球）
    table.sort(allThirds, function(a, b)
        if a.data.points ~= b.data.points then return a.data.points > b.data.points end
        if a.data.goalDifference ~= b.data.goalDifference then return a.data.goalDifference > b.data.goalDifference end
        return a.data.goalsFor > b.data.goalsFor
    end)

    local qualifiedThirds = {}
    for i = 1, math.min(8, #allThirds) do
        table.insert(qualifiedThirds, allThirds[i])
    end

    -- 32支出线队伍：12个第一 + 12个第二 + 8个最佳第三 = 32
    -- 对阵规则：组第一 vs 最佳第三（交叉配对，避免同组）
    --           组第二 vs 组第二（交叉配对，避免同组）
    local matchups = {}

    -- 上半区（8场）：12个组第一 vs 8个最佳第三 + 4个组第二
    -- 组第一按组名排序固定位置，第三名按成绩排序交叉配对
    local usedThirds = {}
    local firstsWithoutOpponent = {}

    for _, first in ipairs(allFirsts) do
        local paired = false
        for j, third in ipairs(qualifiedThirds) do
            if not usedThirds[j] and third.group ~= first.group then
                table.insert(matchups, {first.teamId, third.teamId})
                usedThirds[j] = true
                paired = true
                break
            end
        end
        if not paired then
            -- 尝试配对任意未用的第三
            for j, third in ipairs(qualifiedThirds) do
                if not usedThirds[j] then
                    table.insert(matchups, {first.teamId, third.teamId})
                    usedThirds[j] = true
                    paired = true
                    break
                end
            end
        end
        if not paired then
            table.insert(firstsWithoutOpponent, first)
        end
    end

    -- 剩余没配到第三名的组第一，从第二名中挑选对手（交叉配对）
    -- 按成绩排序第二名
    table.sort(allSeconds, function(a, b)
        if a.data.points ~= b.data.points then return a.data.points > b.data.points end
        if a.data.goalDifference ~= b.data.goalDifference then return a.data.goalDifference > b.data.goalDifference end
        return a.data.goalsFor > b.data.goalsFor
    end)

    local usedSeconds = {}
    for _, first in ipairs(firstsWithoutOpponent) do
        -- 找一个非同组的第二名（从排名靠后的开始，因为靠前的留给下半区互配）
        for j = #allSeconds, 1, -1 do
            if not usedSeconds[j] and allSeconds[j].group ~= first.group then
                table.insert(matchups, {first.teamId, allSeconds[j].teamId})
                usedSeconds[j] = true
                break
            end
        end
    end

    -- 下半区：剩余的第二名互相配对（交叉配对，避免同组）
    local remainingSeconds = {}
    for j, sec in ipairs(allSeconds) do
        if not usedSeconds[j] then
            table.insert(remainingSeconds, sec)
        end
    end

    -- 配对剩余第二名（相邻配对，但避免同组）
    local usedRemaining = {}
    for i, sec1 in ipairs(remainingSeconds) do
        if not usedRemaining[i] then
            for j = i + 1, #remainingSeconds do
                if not usedRemaining[j] and remainingSeconds[j].group ~= sec1.group then
                    table.insert(matchups, {sec1.teamId, remainingSeconds[j].teamId})
                    usedRemaining[i] = true
                    usedRemaining[j] = true
                    break
                end
            end
        end
    end

    -- 如有落单的第二名（极端情况同组冲突），强制配对
    local unpaired = {}
    for i, sec in ipairs(remainingSeconds) do
        if not usedRemaining[i] then
            table.insert(unpaired, sec)
        end
    end
    for i = 1, #unpaired - 1, 2 do
        table.insert(matchups, {unpaired[i].teamId, unpaired[i + 1].teamId})
    end

    -- 生成fixture（共16场）
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
            isKnockout = true,
        })
    end

    wc.knockout.r32 = fixtures
    wc.phase = "r32"

    gameState:addNews({
        category = "world_cup_news",
        title = "世界杯32强对阵出炉！",
        body = WorldCup._formatR32Draw(gameState, wc, matchups, {}),
    })
end

function WorldCup._advanceToR16(gameState, wc)
    local winners = WorldCup._getSingleLegWinners(wc, "r32")
    if #winners < 2 then return end

    -- 16个R32胜者配对打8场R16
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

    for _, f in ipairs(fixtures) do f.isKnockout = true end
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

    for _, f in ipairs(fixtures) do f.isKnockout = true end
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

    for _, f in ipairs(fixtures) do f.isKnockout = true end
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

    for _, f in ipairs(fixtures) do f.isKnockout = true end
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
        -- 平局 → 读取点球大战结果
        if finalFixture._penaltyWinner then
            winner = finalFixture._penaltyWinner
        else
            winner = Random() < 0.5 and finalFixture.homeTeamId or finalFixture.awayTeamId
        end
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

    -- 记录世界杯冠军到历史
    local runnerUp = (winner == finalFixture.homeTeamId) and finalFixture.awayTeamId or finalFixture.homeTeamId

    -- 声望：玩家国家队冠/亚军
    if playerNation then
        local ReputationManager = require("scripts/systems/reputation_manager")
        if playerNation == winner then
            ReputationManager.nationalCupResultUpdate(gameState, true)
        elseif playerNation == runnerUp then
            ReputationManager.nationalCupResultUpdate(gameState, false)
        end
    end
    HistoryManager.recordWorldCupChampion(gameState, {
        season = wc.season,
        championId = winner,
        championName = championName,
        runnerUpId = runnerUp,
        runnerUpName = WorldCup._getNationName(runnerUp),
    })

    EventBus.emit("world_cup_completed", winner)

    -- 世界杯结束后，自动解除国家队主教练身份
    if gameState.nationalTeamCoach then
        local coachNation = gameState.nationalTeamCoach.nation
        local coachNationName = WorldCup._getNationName(coachNation)
        local isChampion = (coachNation == winner)

        -- 记录玩家执教成绩
        local result = WorldCup._calcCoachResult(wc, coachNation, winner, runnerUp)
        local w, d, l = WorldCup._calcCoachMatchRecord(wc, coachNation)
        HistoryManager.recordNTCoachResult(gameState, {
            season = wc.season,
            competition = "worldcup",
            nationId = coachNation,
            nationName = coachNationName,
            result = result,
            matchesPlayed = w + d + l,
            wins = w,
            draws = d,
            losses = l,
        })

        gameState:sendMessage({
            category = "national_team",
            title = "国家队任期结束",
            body = isChampion
                and string.format("恭喜！你带领%s夺得世界杯冠军！国家队任期已圆满结束，你将回归俱乐部工作。", coachNationName)
                or string.format("世界杯已结束，你的%s国家队主教练任期已到期。感谢你的付出，现在将回归俱乐部工作。", coachNationName),
            priority = "high",
        })

        -- 清除国家队教练状态
        gameState.nationalTeamCoach = nil
        -- 切回俱乐部模式
        if gameState.currentRole == "national_team" then
            gameState.currentRole = "club"
        end
    end
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
                -- 平局 → 读取点球大战结果（由 _applyWCResult 写入）
                if f._penaltyWinner then
                    table.insert(winners, f._penaltyWinner)
                else
                    -- 兜底：不应出现（淘汰赛已强制加时+点球）
                    table.insert(winners, Random() < 0.5 and f.homeTeamId or f.awayTeamId)
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
                -- 平局 → 读取点球败者
                if f._penaltyWinner then
                    local loser = (f._penaltyWinner == f.homeTeamId) and f.awayTeamId or f.homeTeamId
                    table.insert(losers, loser)
                else
                    table.insert(losers, Random() < 0.5 and f.awayTeamId or f.homeTeamId)
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

-- 国家队声望分档（S=顶级强队, A=强队, B=中上, C=中等）
-- 声望越高的教练越有可能收到更高档位国家的邀约
local NATION_TIERS = {
    S = {"BRA", "FRA", "ARG", "ENG", "ESP", "GER"},
    A = {"POR", "NED", "BEL", "URU", "CRO", "COL", "ITA"},
    B = {"MEX", "USA", "JPN", "KOR", "SUI", "SEN", "MAR", "AUS", "CAN", "SWE", "TUR", "SCO", "AUT"},
    C = {"CZE", "NOR", "ECU", "IRN", "TUN", "EGY", "GHA", "ALG", "QAT",
         "RSA", "KSA", "NZL", "UZB", "IRQ", "PAN", "PAR", "CIV", "BIH",
         "CPV", "CUW", "COD", "JOR", "HAI", "CHN"},
}

-- 声望 → 可收到邀约的档位（1-99量纲，累加，高声望可以收到所有低档的）
local REP_TIER_THRESHOLDS = {
    {minRep = 70, tiers = {"S", "A", "B", "C"}},   -- 世界级教练：所有档位
    {minRep = 55, tiers = {"A", "B", "C"}},         -- 洲际级教练：A档及以下
    {minRep = 40, tiers = {"B", "C"}},              -- 国内级教练：B档及以下
    {minRep = 25, tiers = {"C"}},                   -- 地区级教练：C档
}

function WorldCup._checkNationalTeamInvitation(gameState, qualifiedNations, wcYear)
    gameState.nationalTeamCoach = nil

    local manager = gameState:getPlayerManager()
    if not manager then return end

    local rep = manager.reputation or 30
    if rep < NT_REP_THRESHOLD then
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯即将开幕",
            body = string.format("%d 美加墨世界杯分组抽签已完成！但目前你的执教声望不够(%d/%d)，未能获得任何国家队邀请。继续努力吧！",
                wcYear, math.floor(rep), NT_REP_THRESHOLD),
            priority = "normal",
        })
        return
    end

    -- 构建入围国家的快速查找表
    local qualifiedSet = {}
    for _, code in ipairs(qualifiedNations) do
        qualifiedSet[code] = true
    end

    -- 获取经理的联赛国籍（保底邀约）
    local leagueNation = WorldCup._getManagerLeagueNation(gameState)
    local offers = {}
    local offerSet = {}  -- 防重复

    -- 0) 中国队保底邀约（2030+，玩家可直接选择）
    _addGuaranteedChinaOffer(offers, offerSet, qualifiedSet, wcYear, WorldCup.isGuaranteedChinaOfferYear)

    -- 1) 联赛国籍保底：如果该国入围世界杯，保证发来邀请
    if leagueNation and qualifiedSet[leagueNation] then
        table.insert(offers, leagueNation)
        offerSet[leagueNation] = true
    end

    -- 2) 声望分档：根据声望确定可收到邀约的档位
    local availableTiers = {}
    for _, threshold in ipairs(REP_TIER_THRESHOLDS) do
        if rep >= threshold.minRep then
            availableTiers = threshold.tiers
            break
        end
    end

    -- 收集所有可能邀约的国家（已入围 + 在对应档位 + 不重复）
    local tierCandidates = {}
    for _, tier in ipairs(availableTiers) do
        local nations = NATION_TIERS[tier]
        if nations then
            for _, code in ipairs(nations) do
                if qualifiedSet[code] and not offerSet[code] then
                    table.insert(tierCandidates, {code = code, tier = tier})
                end
            end
        end
    end

    -- 随机打乱候选列表
    for i = #tierCandidates, 2, -1 do
        local j = RandomInt(1, i)
        tierCandidates[i], tierCandidates[j] = tierCandidates[j], tierCandidates[i]
    end

    -- 声望越高，邀约概率越大
    -- S档: 基础50%概率, A档: 40%, B档: 30%, C档: 25%
    local TIER_PROBABILITY = {S = 0.50, A = 0.40, B = 0.30, C = 0.25}
    -- 声望加成：每超过档位要求10点 → +5%概率
    local MAX_OFFERS = 4

    for _, candidate in ipairs(tierCandidates) do
        if #offers >= MAX_OFFERS then break end
        local baseProb = TIER_PROBABILITY[candidate.tier] or 0.25
        -- 声望越高概率越大（每多50点声望 +10%）
        local repBonus = math.min(0.30, (rep - NT_REP_THRESHOLD) / 500)
        local prob = math.min(0.85, baseProb + repBonus)
        if Random() < prob then
            table.insert(offers, candidate.code)
            offerSet[candidate.code] = true
        end
    end

    -- 如果连保底都没有，提示无邀约
    if #offers == 0 then
        gameState:sendMessage({
            category = "world_cup",
            title = "世界杯抽签揭晓",
            body = string.format("%d 美加墨世界杯分组抽签已完成。遗憾的是，没有国家队向你发出执教邀请。", wcYear),
            priority = "normal",
        })
        return
    end

    -- 构建邀约消息
    local bodyLines = {
        string.format("%d 美加墨世界杯分组抽签已完成！\n", wcYear),
        string.format("凭借你的执教声望(%d)，以下国家队向你发出了主教练邀请：\n", math.floor(rep)),
    }
    local actions = {}
    for i, code in ipairs(offers) do
        local name = WorldCup._getNationName(code)
        local group = WorldCup._getGroupForNation(code) or "?"
        table.insert(bodyLines, string.format("  %d. %s（%s组）", i, name, group))
        table.insert(actions, {
            label = "执教" .. name,
            actionId = "accept_nt_coach",
            data = { nation = code },
        })
    end
    table.insert(bodyLines, "\n选择一支国家队接受邀请，你将负责选拔26人大名单并带队征战世界杯。")
    table.insert(actions, { label = "全部婉拒", actionId = "decline_nt_coach", data = {} })

    gameState._pendingNTCoachOffers = {
        season = gameState.season,
        nations = {},
        offeredDate = {
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        },
    }
    for _, code in ipairs(offers) do
        table.insert(gameState._pendingNTCoachOffers.nations, code)
    end

    local msg = gameState:sendMessage({
        category = "world_cup",
        title = "🏆 国家队主教练邀请",
        body = table.concat(bodyLines, "\n"),
        priority = "high",
        popup = true,
        actions = actions,
    })
    if msg and gameState._pendingNTCoachOffers then
        gameState._pendingNTCoachOffers.inviteMessageId = msg.id
    end
end

--- 是否存在待回复的国家队执教邀请
function WorldCup.hasPendingCoachInvite(gameState)
    local pending = gameState._pendingNTCoachOffers
    return pending ~= nil and pending.nations ~= nil and #pending.nations > 0
end

--- 清除国家队执教邀请待办（接受/婉拒后调用）
function WorldCup.clearPendingCoachInvite(gameState)
    gameState._pendingNTCoachOffers = nil
end

--- 世界杯小组赛开幕日（该届最早一场小组赛）
function WorldCup.getGroupStageKickoffDate(wcYear)
    local minMonth, minDay = 12, 99
    for _, entry in ipairs(GROUP_FIXTURES) do
        local month, day = entry[5], entry[6]
        if month < minMonth or (month == minMonth and day < minDay) then
            minMonth, minDay = month, day
        end
    end
    return { year = wcYear, month = minMonth, day = minDay }
end

--- 距世界杯小组赛开幕还有多少天（已过开幕日则返回 0）
function WorldCup.daysUntilGroupStageKickoff(gameState)
    if not gameState or not WorldCup.isWorldCupYear(gameState.season) then
        return nil
    end
    local kickoff = WorldCup.getGroupStageKickoffDate(gameState.season)
    local TransferManager = require("scripts/systems/transfer_manager")
    local days = TransferManager._daysBetween(gameState.date, kickoff)
    return math.max(0, days)
end

--- 是否需要阻断以确认国家队大名单（距开幕 ≤7 天且尚未锁定）
---@return boolean needsBlock
---@return string|nil nation
---@return number|nil daysLeft
function WorldCup.needsSquadConfirmationBlock(gameState)
    local ntCoach = gameState.nationalTeamCoach
    if not ntCoach or ntCoach.squadConfirmed == true then
        return false
    end
    if not WorldCup.isWorldCupYear(gameState.season) then
        return false
    end
    local days = WorldCup.daysUntilGroupStageKickoff(gameState)
    if days == nil or days > 7 then
        return false
    end
    return true, ntCoach.nation, days
end

--- 获取经理所在联赛对应的国家FIFA代码（作为保底邀约）
function WorldCup._getManagerLeagueNation(gameState)
    local teamId = gameState.playerTeamId
    if not teamId then return nil end
    local _, leagueKey = gameState:getTeamLeague(teamId)
    if not leagueKey then return nil end

    -- 联赛shortName → FIFA代码映射
    local LEAGUE_TO_NATION = {
        premier_league = "ENG",
        la_liga = "ESP",
        bundesliga = "GER",
        serie_a = "ITA",  -- 意大利未参加本届世界杯，不会作为保底
        ligue_1 = "FRA",
        CSL = "CHN",
    }
    return LEAGUE_TO_NATION[leagueKey]
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

--- 补全国际大赛 fixture 的运行时标记（_isWC/_isEuro 不持久化，读档/子页面返回后可能丢失）
function WorldCup.ensureIntlFixtureFlags(gameState, fixture)
    if not fixture or fixture._isWC or fixture._isEuro then return end
    if gameState.teams[fixture.homeTeamId] and gameState.teams[fixture.awayTeamId] then
        return
    end
    local euro = gameState.euroCup
    if euro and euro.phase ~= "not_started" and euro.phase ~= "completed" then
        fixture._isEuro = true
        fixture._isWC = true
        return
    end
    local wc = gameState.worldCup
    if wc and wc.phase ~= "not_started" and wc.phase ~= "completed" then
        fixture._isWC = true
    end
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

function WorldCup._getPlayerNation(gameState)
    -- 只有玩家确实接受了国家队教练邀请时，才返回其执教的国家
    if gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation then
        return gameState.nationalTeamCoach.nation
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

function WorldCup._formatR32Draw(gameState, wc, matchups, byeTeams)
    local lines = {string.format("【32强赛（%d场）】\n", #matchups)}
    for i, m in ipairs(matchups) do
        local n1 = WorldCup._getNationName(m[1])
        local n2 = WorldCup._getNationName(m[2])
        table.insert(lines, string.format("%d. %s vs %s", i, n1, n2))
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

local function _filterSavedPlayerIds(ids, validSet)
    if not ids then return {} end
    local filtered = {}
    for _, pid in ipairs(ids) do
        if validSet[pid] then
            table.insert(filtered, pid)
        end
    end
    return filtered
end

local function _resolveNationalTeamLineup(gameState, saved, validIds)
    local validSet = {}
    for _, pid in ipairs(validIds) do validSet[pid] = true end

    local startingIds = _filterSavedPlayerIds(saved and saved.startingXI, validSet)
    if #startingIds < 11 then
        local players = {}
        for _, pid in ipairs(validIds) do
            local p = gameState.players[pid]
            if p then table.insert(players, p) end
        end
        table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
        startingIds = WorldCup._pickStartingXI(players)
    end

    local startingSet = {}
    for _, pid in ipairs(startingIds) do startingSet[pid] = true end

    local benchIds = _filterSavedPlayerIds(saved and saved.benchIds, validSet)
    local filteredBench = {}
    for _, pid in ipairs(benchIds) do
        if not startingSet[pid] then
            table.insert(filteredBench, pid)
        end
    end

    return startingIds, filteredBench
end

local function _shallowCopyTable(t)
    if not t then return nil end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

local function _applySavedNationalTeamTactics(team, saved)
    if not saved then return end
    if saved.formationVariant then
        team.formationVariant = saved.formationVariant
    end
    if saved.slotRoles then
        team.slotRoles = _shallowCopyTable(saved.slotRoles)
    end
    if saved.slotOffsets then
        team.slotOffsets = _shallowCopyTable(saved.slotOffsets)
    end
    if saved.customSlots then
        team.customSlots = _shallowCopyTable(saved.customSlots)
    end
    if saved.playerDuties then
        team.playerDuties = _shallowCopyTable(saved.playerDuties)
    end
    if saved.captain then team.captain = saved.captain end
    if saved.penaltyTaker then team.penaltyTaker = saved.penaltyTaker end
    if saved.freeKickTaker then team.freeKickTaker = saved.freeKickTaker end
    if saved.cornerTaker then team.cornerTaker = saved.cornerTaker end
end

function WorldCup.buildNationalTeam(gameState, nationCode)
    local ntCoach = gameState.nationalTeamCoach
    if ntCoach and ntCoach.nation == nationCode and ntCoach.squad and #ntCoach.squad > 0 then
        return WorldCup._buildFromPlayerSquad(gameState, nationCode, ntCoach)
    end

    local playerNat = WorldCup._toPlayerNat(nationCode)
    local nationPlayers = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and not player.injured and WorldCup._playerMatchesNat(player.nationality, playerNat) then
            table.insert(nationPlayers, player)
        end
    end
    table.sort(nationPlayers, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    -- 球员不足23人时生成虚拟球员补位
    local TARGET_SQUAD = 23
    if #nationPlayers < TARGET_SQUAD then
        local generated = WorldCup._generateVirtualPlayers(
            gameState, nationCode, playerNat, nationPlayers, TARGET_SQUAD - #nationPlayers
        )
        for _, vp in ipairs(generated) do
            table.insert(nationPlayers, vp)
        end
    end

    local squadSize = math.min(TARGET_SQUAD, #nationPlayers)
    local squadIds = {}
    for i = 1, squadSize do
        table.insert(squadIds, nationPlayers[i].id)
    end

    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local startingIds, benchIds = _resolveNationalTeamLineup(gameState, saved, squadIds)
    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"

    local team = {
        id = nationCode,
        name = WorldCup._getNationName(nationCode),
        shortName = nationCode,
        iconPath = WorldCup.getNationIconPath(nationCode),
        formation = formation,
        playStyle = playStyle,
        attackMode = "balanced",
        startingXI = startingIds,
        benchIds = benchIds,
        playerIds = squadIds,
        playerDuties = {},
        slotRoles = {},
        recentForm = {},
        _isNationalTeam = true,
    }
    _applySavedNationalTeamTactics(team, saved)
    return team
end

function WorldCup._pickStartingXI(players)
    local posGroups = { GK = {}, DEF = {}, MID = {}, FWD = {} }
    for _, p in ipairs(players) do
        local pos = p.position or "MID"
        if pos == "GK" then
            table.insert(posGroups.GK, p)
        elseif pos == "CB" or pos == "LB" or pos == "RB" then
            table.insert(posGroups.DEF, p)
        elseif pos == "ST" or pos == "LW" or pos == "RW" then
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
-- 虚拟球员生成（为球员不足的国家队补位）
------------------------------------------------------

--- 根据国家档位确定虚拟球员能力值范围
local TIER_OVR_RANGE = {
    S = {min = 68, max = 82},   -- 巴西、法国等强队（不应缺人，保底用）
    A = {min = 62, max = 76},   -- 葡萄牙、荷兰等
    B = {min = 55, max = 70},   -- 墨西哥、美国等
    C = {min = 48, max = 64},   -- 卡塔尔、库拉索等
}

--- 获取国家所属档位
local function _getNationTier(nationCode)
    for tier, nations in pairs(NATION_TIERS) do
        for _, code in ipairs(nations) do
            if code == nationCode then return tier end
        end
    end
    return "C"  -- 未知国家默认C档
end

--- 根据阵容缺口确定需要哪些位置的虚拟球员
local function _getNeededPositions(existingPlayers, count)
    -- 统计现有位置分布
    local posCount = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    for _, p in ipairs(existingPlayers) do
        local pos = p.position or "CM"
        if pos == "GK" then posCount.GK = posCount.GK + 1
        elseif pos == "CB" or pos == "LB" or pos == "RB" then posCount.DEF = posCount.DEF + 1
        elseif pos == "ST" or pos == "LW" or pos == "RW" then posCount.FWD = posCount.FWD + 1
        else posCount.MID = posCount.MID + 1
        end
    end

    -- 目标分布: 3GK, 8DEF, 7MID, 5FWD = 23
    local targets = {
        {group = "GK", target = 3, positions = {"GK"}},
        {group = "DEF", target = 8, positions = {"CB", "CB", "CB", "CB", "LB", "LB", "RB", "RB"}},
        {group = "MID", target = 7, positions = {"CM", "CM", "CM", "CDM", "CDM", "CAM", "CAM"}},
        {group = "FWD", target = 5, positions = {"ST", "ST", "LW", "RW", "ST"}},
    }

    local needed = {}
    for _, t in ipairs(targets) do
        local deficit = math.max(0, t.target - posCount[t.group])
        for i = 1, deficit do
            if #needed >= count then break end
            table.insert(needed, t.positions[((i - 1) % #t.positions) + 1])
        end
        if #needed >= count then break end
    end

    -- 如果还不够（极端情况），用CM补
    while #needed < count do
        table.insert(needed, "CM")
    end

    return needed
end

--- 生成单个位置的属性模板
local function _generateAttributes(position, ovr)
    local base = math.max(30, ovr - 15)
    local high = math.min(99, ovr + 10)

    local attrs = {
        pace = base + RandomInt(0, 15),
        stamina = base + RandomInt(5, 20),
        strength = base + RandomInt(0, 15),
        agility = base + RandomInt(0, 15),
        passing = base + RandomInt(0, 15),
        shooting = base + RandomInt(0, 10),
        tackling = base + RandomInt(0, 10),
        dribbling = base + RandomInt(0, 15),
        defending = base + RandomInt(0, 10),
        positioning = base + RandomInt(5, 15),
        vision = base + RandomInt(0, 12),
        decisions = base + RandomInt(5, 15),
        composure = base + RandomInt(5, 15),
        aggression = base + RandomInt(0, 15),
        teamwork = base + RandomInt(5, 15),
        leadership = base + RandomInt(0, 10),
        handling = 10,
        reflexes = 10,
        aerial = base + RandomInt(0, 15),
    }

    -- 按位置特化属性
    if position == "GK" then
        attrs.handling = high - RandomInt(0, 8)
        attrs.reflexes = high - RandomInt(0, 8)
        attrs.positioning = high - RandomInt(0, 10)
        attrs.shooting = RandomInt(10, 25)
        attrs.dribbling = RandomInt(20, 40)
        attrs.tackling = RandomInt(10, 25)
    elseif position == "CB" then
        attrs.defending = high - RandomInt(0, 5)
        attrs.tackling = high - RandomInt(0, 8)
        attrs.aerial = high - RandomInt(0, 8)
        attrs.strength = high - RandomInt(0, 5)
    elseif position == "LB" or position == "RB" then
        attrs.defending = high - RandomInt(0, 8)
        attrs.tackling = high - RandomInt(0, 10)
        attrs.pace = high - RandomInt(0, 5)
        attrs.stamina = high - RandomInt(0, 5)
    elseif position == "CDM" then
        attrs.tackling = high - RandomInt(0, 5)
        attrs.defending = high - RandomInt(0, 8)
        attrs.positioning = high - RandomInt(0, 5)
        attrs.passing = high - RandomInt(0, 10)
    elseif position == "CM" then
        attrs.passing = high - RandomInt(0, 5)
        attrs.vision = high - RandomInt(0, 8)
        attrs.stamina = high - RandomInt(0, 5)
    elseif position == "CAM" then
        attrs.passing = high - RandomInt(0, 5)
        attrs.vision = high - RandomInt(0, 5)
        attrs.dribbling = high - RandomInt(0, 8)
        attrs.shooting = high - RandomInt(0, 10)
    elseif position == "LW" or position == "RW" then
        attrs.pace = high - RandomInt(0, 5)
        attrs.dribbling = high - RandomInt(0, 5)
        attrs.shooting = high - RandomInt(0, 10)
    elseif position == "ST" then
        attrs.shooting = high - RandomInt(0, 5)
        attrs.positioning = high - RandomInt(0, 5)
        attrs.composure = high - RandomInt(0, 8)
    end

    -- 限制在合理范围内
    for k, v in pairs(attrs) do
        attrs[k] = math.max(10, math.min(99, v))
    end

    return attrs
end

--- 根据 overall 估算身价（简化版 Player:calculateValue）
local function _estimateValue(ovr, age)
    local D = 1.15
    local C = 336.7  -- 6,000,000 / 1.15^70
    local base = C * (D ^ ovr)

    -- 年龄修正
    local ageMult
    if age <= 20 then ageMult = 0.55
    elseif age <= 22 then ageMult = 0.7 + (age - 20) * 0.15
    elseif age <= 25 then ageMult = 1.0 + (age - 22) * 0.05
    elseif age <= 27 then ageMult = 1.15 - (age - 25) * 0.075
    elseif age <= 29 then ageMult = 1.0 - (age - 27) * 0.1
    elseif age <= 31 then ageMult = 0.8 - (age - 29) * 0.1
    elseif age <= 33 then ageMult = 0.6 - (age - 31) * 0.1
    else ageMult = math.max(0.15, 0.4 - (age - 33) * 0.1)
    end

    return math.floor(base * ageMult)
end

--- 根据身价估算周薪
local function _estimateWage(value)
    -- 简化：周薪约为身价的 0.1%~0.15%（年薪约5%~8%）
    return math.max(500, math.floor(value * 0.0012))
end

--- 中国队虚拟球员中文全名（与青训 CN 池一致）
local _VP_CHN_NAMES = {
    "李浩然", "王子轩", "张宇航", "刘梓豪", "陈俊杰",
    "杨天翼", "赵志远", "黄博文", "周昊天", "吴瑞祥",
    "徐嘉伟", "孙明哲", "胡晨曦", "朱逸飞", "高鹏程",
    "林思远", "何泽宇", "郭煜城", "马星辰", "罗承恩",
    "梁铭轩", "宋睿智", "郑翰林", "谢文昊", "韩致远",
    "唐鸿飞", "冯修远", "于凯旋", "董子墨", "萧晋鹏",
    "许嘉树", "沈逸凡", "曹宇轩", "邓子豪", "彭思齐",
    "曾文博", "彭宇航", "吕晨阳", "丁梓睿", "任天佑",
    "姜皓轩", "范子谦", "方嘉懿", "石锦程", "姚启航",
    "谭俊豪", "邱子墨", "秦宇辰", "江浩然", "汪明轩",
}

--- 为虚拟球员生成随机姓名（按国家风格）
local _VP_LAST_NAMES = {
    BRA = {"Silva", "Santos", "Oliveira", "Souza", "Lima", "Costa", "Pereira", "Almeida", "Ferreira", "Rodrigues", "Barbosa", "Ribeiro", "Martins"},
    ARG = {"González", "Fernández", "Rodríguez", "López", "Martínez", "García", "Romero", "Álvarez", "Moreno", "Díaz", "Torres", "Ruiz"},
    ENG = {"Smith", "Johnson", "Williams", "Brown", "Jones", "Taylor", "Davies", "Wilson", "Evans", "Wright", "Hall", "Walker"},
    FRA = {"Martin", "Bernard", "Dubois", "Thomas", "Robert", "Richard", "Petit", "Durand", "Leroy", "Moreau", "Simon", "Laurent"},
    GER = {"Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Schulz", "Hoffmann", "Koch"},
    ESP = {"García", "Martínez", "López", "Rodríguez", "Fernández", "González", "Sánchez", "Pérez", "Ruiz", "Díaz"},
    ITA = {"Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco"},
    POR = {"Silva", "Santos", "Ferreira", "Pereira", "Oliveira", "Costa", "Rodrigues", "Martins", "Sousa", "Fernandes"},
    NED = {"De Jong", "Van Dijk", "Bakker", "Visser", "Smit", "Meijer", "De Boer", "Peters", "Mulder", "Bos"},
    JPN = {"Tanaka", "Suzuki", "Yamamoto", "Watanabe", "Nakamura", "Kobayashi", "Sato", "Ito", "Takahashi", "Kimura"},
    KOR = {"Kim", "Park", "Lee", "Choi", "Jung", "Kang", "Cho", "Yoon", "Jang", "Lim", "Han", "Shin"},
    MAR = {"El Amrani", "Bennani", "Tazi", "Idrissi", "Ouali", "Berrada", "Zouak", "Lahlou", "Fassi", "Naciri"},
    MEX = {"Hernández", "García", "Martínez", "López", "González", "Rodríguez", "Pérez", "Sánchez", "Ramírez", "Torres"},
    USA = {"Williams", "Johnson", "Brown", "Davis", "Miller", "Wilson", "Moore", "Taylor", "Anderson", "Thomas"},
    URU = {"González", "Rodríguez", "Silva", "Martínez", "García", "López", "Fernández", "Pérez", "Suárez", "Álvarez"},
    COL = {"García", "Rodríguez", "Martínez", "López", "González", "Hernández", "Sánchez", "Ramírez", "Torres", "Díaz"},
    SEN = {"Diop", "Diallo", "Ndiaye", "Sow", "Ba", "Fall", "Gueye", "Sarr", "Cissé", "Sy", "Diouf", "Mbaye"},
    AUS = {"Smith", "Jones", "Williams", "Brown", "Wilson", "Taylor", "Johnson", "White", "Martin", "Thompson"},
    CAN = {"Smith", "Brown", "Wilson", "Johnson", "Williams", "Jones", "Miller", "Davis", "Martin", "Thompson"},
}
local _VP_FIRST_NAMES = {
    BRA = {"Lucas", "Gabriel", "Matheus", "Felipe", "Rafael", "Bruno", "Vitor", "Pedro", "Thiago", "Diego"},
    ARG = {"Matías", "Nicolás", "Lucas", "Facundo", "Santiago", "Leandro", "Gonzalo", "Federico", "Alejandro", "Emiliano"},
    ENG = {"James", "Oliver", "Harry", "George", "Jack", "Charlie", "Leo", "Thomas", "William", "Oscar"},
    FRA = {"Lucas", "Louis", "Gabriel", "Hugo", "Jules", "Adam", "Léo", "Nathan", "Ethan", "Paul"},
    GER = {"Lukas", "Leon", "Finn", "Elias", "Jonas", "Ben", "Noah", "Paul", "Felix", "Tim"},
    ESP = {"Pablo", "Daniel", "Hugo", "Mateo", "Alejandro", "Álvaro", "Adrián", "David", "Mario", "Diego"},
    ITA = {"Leonardo", "Francesco", "Alessandro", "Lorenzo", "Mattia", "Andrea", "Gabriele", "Riccardo", "Tommaso", "Marco"},
    POR = {"João", "Diogo", "Rafael", "Tiago", "Pedro", "Gonçalo", "André", "Rui", "Nuno", "Bruno"},
    NED = {"Daan", "Sem", "Jesse", "Luuk", "Lars", "Tim", "Thijs", "Thomas", "Bram", "Stijn"},
    JPN = {"Yuto", "Takumi", "Daiki", "Riku", "Kaito", "Haruto", "Kenji", "Shota", "Yuki", "Ren"},
    KOR = {"Min-Jae", "Ji-Sung", "Seung-Ho", "Jun-Ho", "Hyun-Woo", "Tae-Young", "Dong-Hyun", "Sung-Jin", "Woo-Jin", "Jae-Hyun"},
    MAR = {"Youssef", "Adam", "Mohamed", "Amine", "Ayoub", "Hamza", "Oussama", "Bilal", "Karim", "Soufiane"},
    MEX = {"Diego", "Santiago", "Sebastián", "Mateo", "Leonardo", "Emiliano", "Miguel", "Alejandro", "Daniel", "Carlos"},
    USA = {"James", "Michael", "Tyler", "Brandon", "Joshua", "Ryan", "Ethan", "Dylan", "Kyle", "Christian"},
    URU = {"Matías", "Santiago", "Nicolás", "Facundo", "Agustín", "Rodrigo", "Federico", "Gonzalo", "Martín", "Diego"},
    COL = {"Santiago", "Mateo", "Sebastián", "Alejandro", "Samuel", "Daniel", "Nicolás", "David", "Juan", "Andrés"},
    SEN = {"Moussa", "Ibrahima", "Ousmane", "Mamadou", "Aliou", "Cheikh", "Abdoulaye", "Pape", "Ismaïla", "Sadio"},
    AUS = {"Liam", "Oliver", "Jack", "Thomas", "James", "Daniel", "Ethan", "Noah", "Lucas", "Harry"},
    CAN = {"Liam", "Noah", "Oliver", "Lucas", "Ethan", "James", "Benjamin", "Mason", "Logan", "Alexander"},
}

local function _generateVPName(nationCode)
    if nationCode == "CHN" then
        local full = _VP_CHN_NAMES[RandomInt(1, #_VP_CHN_NAMES)] or "李浩然"
        return full, full, full
    end
    local lastPool = _VP_LAST_NAMES[nationCode] or _VP_LAST_NAMES.ENG
    local firstPool = _VP_FIRST_NAMES[nationCode] or _VP_FIRST_NAMES.ENG
    local first = firstPool[RandomInt(1, #firstPool)] or "Alex"
    local last = lastPool[RandomInt(1, #lastPool)] or "Smith"
    -- 返回 displayName 格式：首字母. 姓 （如 "L. Silva"）
    local initial = first:sub(1, 1)
    -- 处理 UTF-8 多字节首字母
    local b = first:byte(1)
    if b >= 192 and b < 224 then initial = first:sub(1, 2)
    elseif b >= 224 and b < 240 then initial = first:sub(1, 3)
    elseif b >= 240 then initial = first:sub(1, 4) end
    return initial .. ". " .. last, first, last
end

--- 创建完整数据结构的虚拟球员（与真实球员同粒度）
---@param vpId string
---@param displayName string
---@param nationCode string
---@param playerNat string
---@param pos string
---@param ovr number
---@param gameYear number 当前游戏年份
---@return table
local function _createVirtualPlayer(vpId, displayName, nationCode, playerNat, pos, ovr, gameYear)
    local age = RandomInt(23, 32)  -- 国脚典型年龄段
    local birthYear = gameYear - age
    local potential = ovr + RandomInt(0, 5)
    local value = _estimateValue(ovr, age)
    local wage = _estimateWage(value)
    local reputation = math.max(15, math.min(70, ovr - 10 + RandomInt(-5, 5)))

    local vp = {
        id = vpId,
        -- 名称相关
        match_name = displayName,
        full_name = displayName,
        displayName = displayName,
        firstName = "",
        lastName = displayName,
        -- 国籍
        nationality = playerNat,
        football_nation = playerNat,
        -- 位置
        position = pos,
        natural_position = pos,
        naturalPositions = {pos},
        alternate_positions = {},
        -- 能力
        overall = ovr,
        ovr = ovr,
        potential = potential,
        actualPotential = potential,
        paRating = nil,
        attributes = _generateAttributes(pos, ovr),
        -- 身体/状态
        fitness = RandomInt(75, 95),
        morale = RandomInt(60, 80),
        condition = 100,
        retired = false,
        injured = false,
        injuryDays = 0,
        injury = nil,
        -- 年龄
        birthYear = birthYear,
        age = age,
        -- 合同/经济（无俱乐部 = 自由球员）
        teamId = nil,
        value = value,
        wage = wage,
        contractEnd = nil,
        releaseClause = nil,
        -- 身份/角色
        squadRole = "rotation",
        reputation = reputation,
        listedForSale = false,
        listedForLoan = false,
        preContractLockedBy = nil,
        -- 技术特征
        preferredFoot = Random() > 0.75 and "left" or "right",
        weakFoot = RandomInt(1, 4),
        traits = {},
        -- 统计
        seasonStats = {
            appearances = 0,
            goals = 0,
            assists = 0,
            yellowCards = 0,
            redCards = 0,
            avgRating = 0,
            cleanSheets = 0,
        },
        careerHistory = {},
        -- 士气系统
        morale_core = {
            manager_trust = 50,
            unresolved_issue = nil,
            recent_treatment = nil,
            last_talk_day = 0,
            talk_fatigue = 0,
        },
        -- 训练
        trainingFocus = nil,
        -- 标记
        _isVirtual = true,
    }
    return setmetatable(vp, { __index = Player })
end

--- 为指定国家队生成虚拟球员，注入 gameState.players
---@param gameState table
---@param nationCode string FIFA国家代码
---@param playerNat string 球员数据国籍代码
---@param existingPlayers table 已有的真实球员列表
---@param needed number 需要生成的数量
---@return table 生成的虚拟球员列表
function WorldCup._generateVirtualPlayers(gameState, nationCode, playerNat, existingPlayers, needed)
    local tier = _getNationTier(nationCode)
    local ovrRange = TIER_OVR_RANGE[tier] or TIER_OVR_RANGE.C
    local positions = _getNeededPositions(existingPlayers, needed)
    local generated = {}

    -- 确保缓存表存在（避免每次WC重复生成）
    if not gameState._wcVirtualPlayers then
        gameState._wcVirtualPlayers = {}
    end

    -- 如果之前已经为该国生成过，直接复用
    if gameState._wcVirtualPlayers[nationCode] then
        local cached = gameState._wcVirtualPlayers[nationCode]
        for _, vp in ipairs(cached) do
            -- 确保仍在 gameState.players 中
            if not gameState.players[vp.id] then
                gameState.players[vp.id] = vp
            end
            table.insert(generated, vp)
        end
        return generated
    end

    local nationName = WorldCup._getNationName(nationCode) or nationCode
    local gameYear = gameState.date and gameState.date.year or 2025

    for i = 1, needed do
        local pos = positions[i]
        local ovr = RandomInt(ovrRange.min, ovrRange.max)
        local vpId = string.format("wc-vp-%s-%03d", nationCode, i)
        local name, vpFirst, vpLast = _generateVPName(nationCode)

        local vp = _createVirtualPlayer(vpId, name, nationCode, playerNat, pos, ovr, gameYear)
        vp.firstName = vpFirst
        vp.lastName = vpLast

        -- 注入 gameState.players 使 getMatchPlayers 能找到
        gameState.players[vpId] = vp
        table.insert(generated, vp)
    end

    -- 缓存本次生成结果
    gameState._wcVirtualPlayers[nationCode] = generated

    return generated
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

    -- 回退：当有效球员不足时（如联赛数据未加载），用虚拟球员补充
    local TARGET_SQUAD = 23
    if #validIds < TARGET_SQUAD then
        local playerNat = WorldCup._toPlayerNat(nationCode)
        -- 收集现有有效球员对象，供 _generateVirtualPlayers 判断位置分布
        local existingPlayers = {}
        for _, pid in ipairs(validIds) do
            local p = gameState.players[pid]
            if p then table.insert(existingPlayers, p) end
        end
        local needed = TARGET_SQUAD - #validIds
        local generated = WorldCup._generateVirtualPlayers(
            gameState, nationCode, playerNat, existingPlayers, needed
        )
        for _, vp in ipairs(generated) do
            table.insert(validIds, vp.id)
        end
        print(string.format("[WorldCup] _buildFromPlayerSquad: %s had %d valid players, generated %d virtual players",
            nationCode, #validIds - #generated, #generated))
    end

    local saved = gameState._nationalTeamSettings and gameState._nationalTeamSettings[nationCode]
    local startingIds, benchIds = _resolveNationalTeamLineup(gameState, saved, validIds)
    local formation = (saved and saved.formation) or "4-3-3"
    local playStyle = (saved and saved.playStyle) or "Balanced"

    local team = {
        id = nationCode,
        name = WorldCup._getNationName(nationCode),
        shortName = nationCode,
        iconPath = WorldCup.getNationIconPath(nationCode),
        formation = formation,
        playStyle = playStyle,
        attackMode = "balanced",
        startingXI = startingIds,
        benchIds = benchIds,
        playerIds = validIds,
        playerDuties = {},
        slotRoles = {},
        recentForm = {},
        _isNationalTeam = true,
    }
    _applySavedNationalTeamTactics(team, saved)
    return team
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
        formationVariant = team.formationVariant,
        startingXI = _shallowCopyTable(team.startingXI),
        benchIds = _shallowCopyTable(team.benchIds),
        slotRoles = _shallowCopyTable(team.slotRoles),
        slotOffsets = _shallowCopyTable(team.slotOffsets),
        customSlots = _shallowCopyTable(team.customSlots),
        playerDuties = _shallowCopyTable(team.playerDuties),
        captain = team.captain,
        penaltyTaker = team.penaltyTaker,
        freeKickTaker = team.freeKickTaker,
        cornerTaker = team.cornerTaker,
    }
end

------------------------------------------------------
-- 获取某国籍所有可选球员（大名单选择界面用）
------------------------------------------------------

function WorldCup.getAvailablePlayers(gameState, nationCode)
    local playerNat = WorldCup._toPlayerNat(nationCode)
    local players = {}
    for _, player in pairs(gameState.players) do
        if not player.retired and WorldCup._playerMatchesNat(player.nationality, playerNat) then
            table.insert(players, player)
        end
    end
    table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    -- 确保每个位置组至少 MIN_PER_GROUP 个候选人
    local MIN_PER_GROUP = 5
    local posCount = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    for _, p in ipairs(players) do
        local pos = p.position or "CM"
        if pos == "GK" then posCount.GK = posCount.GK + 1
        elseif pos == "CB" or pos == "LB" or pos == "RB" then posCount.DEF = posCount.DEF + 1
        elseif pos == "ST" or pos == "LW" or pos == "RW" then posCount.FWD = posCount.FWD + 1
        else posCount.MID = posCount.MID + 1
        end
    end

    -- 计算各组缺口
    local fillPositions = {}
    local groupFill = {
        {group = "GK",  current = posCount.GK,  positions = {"GK"}},
        {group = "DEF", current = posCount.DEF, positions = {"CB", "LB", "RB", "CB", "LB"}},
        {group = "MID", current = posCount.MID, positions = {"CM", "CDM", "CAM", "CM", "CDM"}},
        {group = "FWD", current = posCount.FWD, positions = {"ST", "LW", "RW", "ST", "ST"}},
    }
    for _, g in ipairs(groupFill) do
        local deficit = math.max(0, MIN_PER_GROUP - g.current)
        for i = 1, deficit do
            table.insert(fillPositions, g.positions[((i - 1) % #g.positions) + 1])
        end
    end

    -- 如果有缺口，生成虚拟球员补位
    if #fillPositions > 0 then
        local tier = _getNationTier(nationCode)
        local ovrRange = TIER_OVR_RANGE[tier] or TIER_OVR_RANGE.C
        local nationName = WorldCup._getNationName(nationCode) or nationCode

        -- 使用独立缓存键避免与 buildNationalTeam 的缓存冲突
        local cacheKey = nationCode .. "_pool"
        if not gameState._wcVirtualPlayers then
            gameState._wcVirtualPlayers = {}
        end

        if gameState._wcVirtualPlayers[cacheKey] then
            -- 复用已缓存的候选池虚拟球员
            for _, vp in ipairs(gameState._wcVirtualPlayers[cacheKey]) do
                if not gameState.players[vp.id] then
                    gameState.players[vp.id] = vp
                end
                table.insert(players, vp)
            end
        else
            local generated = {}
            local baseIdx = 100  -- 偏移避免与 buildNationalTeam 的 ID 冲突
            local gameYear = gameState.date and gameState.date.year or 2025
            for i, pos in ipairs(fillPositions) do
                local ovr = RandomInt(ovrRange.min, ovrRange.max)
                local vpId = string.format("wc-vp-%s-%03d", nationCode, baseIdx + i)
                local name, vpFirst, vpLast = _generateVPName(nationCode)

                local vp = _createVirtualPlayer(vpId, name, nationCode, playerNat, pos, ovr, gameYear)
                vp.firstName = vpFirst
                vp.lastName = vpLast
                gameState.players[vpId] = vp
                table.insert(generated, vp)
                table.insert(players, vp)
            end
            gameState._wcVirtualPlayers[cacheKey] = generated
        end

        -- 重新排序
        table.sort(players, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
    end

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

------------------------------------------------------
-- 执教成绩计算辅助
------------------------------------------------------

--- 计算玩家执教的最终结果字符串
function WorldCup._calcCoachResult(wc, coachNation, winner, runnerUp)
    if coachNation == winner then return "冠军" end
    if coachNation == runnerUp then return "亚军" end

    -- 检查半决赛参与者（四强）
    local sfFixtures = wc.knockout and wc.knockout.sf
    if sfFixtures then
        for _, f in ipairs(sfFixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "四强"
            end
        end
    end

    -- 检查八强赛参与者
    local qfFixtures = wc.knockout and wc.knockout.qf
    if qfFixtures then
        for _, f in ipairs(qfFixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "八强"
            end
        end
    end

    -- 检查十六强参与者
    local r16Fixtures = wc.knockout and wc.knockout.r16
    if r16Fixtures then
        for _, f in ipairs(r16Fixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "十六强"
            end
        end
    end

    -- 检查三十二强参与者
    local r32Fixtures = wc.knockout and wc.knockout.r32
    if r32Fixtures then
        for _, f in ipairs(r32Fixtures) do
            if f.homeTeamId == coachNation or f.awayTeamId == coachNation then
                return "三十二强"
            end
        end
    end

    return "小组赛出局"
end

--- 计算执教期间的胜/平/负记录
function WorldCup._calcCoachMatchRecord(wc, coachNation)
    local wins, draws, losses = 0, 0, 0

    -- 小组赛
    if wc.groups then
        for _, group in pairs(wc.groups) do
            for _, f in ipairs(group.fixtures or {}) do
                if f.status == "finished" and (f.homeTeamId == coachNation or f.awayTeamId == coachNation) then
                    local isHome = (f.homeTeamId == coachNation)
                    local myGoals = isHome and f.homeGoals or f.awayGoals
                    local opGoals = isHome and f.awayGoals or f.homeGoals
                    if myGoals > opGoals then wins = wins + 1
                    elseif myGoals < opGoals then losses = losses + 1
                    else draws = draws + 1 end
                end
            end
        end
    end

    -- 淘汰赛各轮
    local koPhases = {"r32", "r16", "qf", "sf", "final"}
    for _, phase in ipairs(koPhases) do
        local fixtures = wc.knockout and wc.knockout[phase]
        if fixtures then
            for _, f in ipairs(fixtures) do
                if f.status == "finished" and (f.homeTeamId == coachNation or f.awayTeamId == coachNation) then
                    if f._isThirdPlace then
                        -- 三四名决赛也计入
                    end
                    local isHome = (f.homeTeamId == coachNation)
                    local myGoals = isHome and f.homeGoals or f.awayGoals
                    local opGoals = isHome and f.awayGoals or f.homeGoals
                    if myGoals > opGoals then
                        wins = wins + 1
                    elseif myGoals < opGoals then
                        losses = losses + 1
                    else
                        -- 淘汰赛平局，根据点球判断
                        if f._penaltyWinner == coachNation then
                            wins = wins + 1
                        else
                            losses = losses + 1
                        end
                    end
                end
            end
        end
    end

    return wins, draws, losses
end

return WorldCup
