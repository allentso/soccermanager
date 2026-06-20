-- data/real_data_loader.lua
-- 从五大联赛JSON加载真实球员/球队数据

local Constants = require("scripts/app/constants")
local JsonLoader = require("scripts/data/json_loader")
local TeamIconRegistry = require("scripts/data/team_icon_registry")
local League = require("scripts/domain/league")

local RealDataLoader = {}

-- 位置映射：JSON全名 → 游戏内缩写
local POSITION_MAP = {
    Goalkeeper = "GK",
    CentreBack = "CB",     -- JSON使用英式拼写
    CenterBack = "CB",     -- 兼容美式拼写
    LeftBack = "LB",
    RightBack = "RB",
    LeftWingBack = "LB",   -- 翼卫映射为边后卫
    RightWingBack = "RB",
    DefensiveMidfielder = "CDM",
    CentralMidfielder = "CM",
    AttackingMidfielder = "CAM",
    LeftMidfielder = "LM",
    RightMidfielder = "RM",
    LeftWinger = "LW",
    RightWinger = "RW",
    LeftWing = "LW",       -- JSON变体写法
    RightWing = "RW",      -- JSON变体写法
    Striker = "ST",
    CentreForward = "CF",  -- 托蒂等传奇球员使用此位置
    CenterForward = "CF",  -- 兼容美式拼写
}

-- 属性名映射：JSON → 游戏内（pace → speed）
local ATTR_MAP = {
    pace = "speed",
    stamina = "stamina",
    strength = "strength",
    agility = "agility",
    passing = "passing",
    shooting = "shooting",
    tackling = "tackling",
    dribbling = "dribbling",
    defending = "defending",
    positioning = "positioning",
    vision = "vision",
    decisions = "decisions",
    composure = "composure",
    aggression = "aggression",
    teamwork = "teamwork",
    leadership = "leadership",
    handling = "handling",
    reflexes = "reflexes",
    aerial = "aerial",
}

-- 属性缩放：0-100 → 1-20（四舍五入）
local function scaleAttr(value)
    if not value then return 10 end
    local scaled = math.floor(value / 5 + 0.5)
    return math.max(1, math.min(20, scaled))
end

-- 脚法映射
local function mapFootedness(foot)
    if foot == "Left" then return "left"
    elseif foot == "Right" then return "right"
    else return "right"
    end
end

-- 从出生日期提取出生年
local function extractBirthYear(dob)
    if not dob then return 1995 end
    local year = dob:match("^(%d%d%d%d)")
    return tonumber(year) or 1995
end

-- 五大联赛 JSON 快照偏旧，开局年龄统一 -2（birthYear +2）
local CORE_LEAGUE_AGE_OFFSET = 2
local CORE_LEAGUE_AGE_OFFSET_KEYS = {
    EPL = true, LaLiga = true, SerieA = true, Bundesliga = true, Ligue1 = true,
}

-- 从合同结束日期提取 {year, month}
local function extractContractEnd(dateStr)
    if not dateStr then return {year = 2026, month = 6} end
    local year, month = dateStr:match("^(%d%d%d%d)-(%d%d)")
    return {
        year = tonumber(year) or 2026,
        month = tonumber(month) or 6,
    }
end

-- 转换球员属性 (JSON 0-100 → 游戏 1-20)
local function convertAttributes(jsonAttrs)
    local attrs = {}
    for jsonKey, gameKey in pairs(ATTR_MAP) do
        attrs[gameKey] = scaleAttr(jsonAttrs[jsonKey])
    end
    return attrs
end

-- 映射位置列表
local function mapPositions(mainPos, altPositions)
    local main = POSITION_MAP[mainPos] or "CM"
    local positions = {main}
    if altPositions then
        for _, ap in ipairs(altPositions) do
            local mapped = POSITION_MAP[ap]
            if mapped and mapped ~= main then
                table.insert(positions, mapped)
            end
        end
    end
    return main, positions
end

-- 映射 squad_role
local function mapSquadRole(role)
    if role == "Senior" then return "first_team"
    elseif role == "Youth" then return "youth"
    elseif role == "Reserve" then return "reserve"
    else return "first_team"
    end
end

-- 加载单个联赛JSON，返回原始数据
function RealDataLoader.loadLeagueFile(filename)
    local data = JsonLoader.loadFromResource("Data/" .. filename)
    if not data then
        log:Write(LOG_WARNING, "RealDataLoader: 无法加载 " .. filename)
        return nil
    end
    return data
end

-- 五大联赛（始终加载）
RealDataLoader.CORE_LEAGUE_FILES = {
    {file = "fm2024_premier_league.json",  name = "英超",    country = "ENG", shortName = "EPL"},
    {file = "fm2024_la_liga.json",         name = "西甲",    country = "ES",  shortName = "LaLiga"},
    {file = "fm2024_serie_a.json",         name = "意甲",    country = "IT",  shortName = "SerieA"},
    {file = "fm2024_bundesliga.json",      name = "德甲",    country = "DE",  shortName = "Bundesliga"},
    {file = "fm2024_ligue_1.json",         name = "法甲",    country = "FR",  shortName = "Ligue1"},
}

-- 可选联赛（新游戏时由玩家勾选）
RealDataLoader.OPTIONAL_LEAGUES = {
    CSL = {file = "fm2024_csl.json", name = "中超", country = "CHN", shortName = "CSL"},
}

-- 兼容旧引用
RealDataLoader.LEAGUE_FILES = RealDataLoader.CORE_LEAGUE_FILES

--- 根据新游戏选项返回要加载的联赛配置列表
function RealDataLoader.getActiveLeagueConfigs(opts)
    opts = opts or {}
    local configs = {}
    for _, cfg in ipairs(RealDataLoader.CORE_LEAGUE_FILES) do
        table.insert(configs, cfg)
    end
    if opts.includeCSL and RealDataLoader.OPTIONAL_LEAGUES.CSL then
        table.insert(configs, RealDataLoader.OPTIONAL_LEAGUES.CSL)
    end
    return configs
end

--- UI 展示用联赛顺序（仅包含已加载联赛）
function RealDataLoader.getLeagueDisplayOrder(gameState)
    local order = {"EPL", "LaLiga", "SerieA", "Bundesliga", "Ligue1"}
    if gameState and gameState.leagues and gameState.leagues.CSL then
        table.insert(order, "CSL")
    end
    return order
end

--- 按 shortName 查找联赛配置（含可选联赛）
function RealDataLoader.getLeagueConfigByKey(leagueKey)
    for _, cfg in ipairs(RealDataLoader.CORE_LEAGUE_FILES) do
        if cfg.shortName == leagueKey then return cfg end
    end
    for _, cfg in pairs(RealDataLoader.OPTIONAL_LEAGUES) do
        if cfg.shortName == leagueKey then return cfg end
    end
    return nil
end

--- 将一个联赛的JSON数据导入到 gameState 中
--- @param gameState table GameState实例
--- @param leagueData table 从JSON加载的联赛数据
--- @param leagueConfig table 联赛配置 {name, country, shortName}
--- @return table league League实例
function RealDataLoader.importLeague(gameState, leagueData, leagueConfig)
    -- 记录 JSON string id → game integer id 的映射
    local teamIdMap = {}   -- jsonTeamId → gameIntId
    local playerIdMap = {} -- jsonPlayerId → gameIntId

    local teamIds = {}

    -- 中超：固定声望梯度（顶级 550，其余按 wage_budget 排名递减）——存盘值保持减益
    local cslRepMap = nil
    if leagueConfig.shortName == "CSL" then
        cslRepMap = RealDataLoader._buildCSLReputationMap(leagueData.teams)
    end

    -- 1. 导入球队
    for _, tData in ipairs(leagueData.teams) do
        local rep = cslRepMap and cslRepMap[tData.id]
            or RealDataLoader._calcReputation(tData.wage_budget)
        -- 中超：财务与初始声望对应（声望后续仍可通过赛季/比赛变动）
        local wb = cslRepMap and RealDataLoader._reputationToWageBudget(rep)
            or (tData.wage_budget or 200000)
        local team = gameState:addTeam({
            name = tData.name_cn or tData.name,
            shortName = tData.short_name or "",
            jsonTeamId = tData.id,
            iconPath = TeamIconRegistry.getPathByJsonId(tData.id),
            city = tData.city or "",
            country = tData.country or leagueConfig.country,
            colors = tData.colors or {primary = "#333333", secondary = "#ffffff"},
            stadiumName = tData.stadium_name or "",
            stadiumCapacity = tData.stadium_capacity or 30000,
            foundedYear = tData.founded_year or 1900,
            reputation = rep,
            _baseReputation = rep,
            playStyle = RealDataLoader._assignPlayStyle({
                play_style = tData.play_style,
                reputation = rep,
            }),
            formation = RealDataLoader._assignFormation(tData),
            -- 用wage_budget推算合理财务（FM原始finance/transfer_budget数值偏低）
            -- 现实参照: 顶级俱乐部(周薪5M+)转会预算~150M, 余额~500M
            balance = wb * 80,
            wageBudget = wb,
            transferBudget = wb * 25,
            trainingFocus = tData.training_focus or "balanced",
            trainingIntensity = (tData.training_intensity or "Medium"):lower(),
        })

        teamIdMap[tData.id] = team.id
        table.insert(teamIds, team.id)
        team._baseWageBudget = wb
        team._financialScale = math.sqrt(wb / 2000000)
    end

    -- 2. 导入球员
    for _, pData in ipairs(leagueData.players) do
        local position, naturalPositions = mapPositions(pData.position, pData.alternate_positions)
        local attrs = convertAttributes(pData.attributes or {})
        local birthYear = extractBirthYear(pData.date_of_birth)
        if CORE_LEAGUE_AGE_OFFSET_KEYS[leagueConfig.shortName] then
            birthYear = birthYear + CORE_LEAGUE_AGE_OFFSET
        end
        local contractEnd = extractContractEnd(pData.contract_end)

        -- 解析teamId
        local gameTeamId = teamIdMap[pData.team_id]

        -- 名字处理：优先使用中文简称（姓氏部分），以便阵型预览清晰辨识
        local fullNameCn = pData.full_name_cn or ""
        local matchName = pData.match_name or ""
        local fullName = pData.full_name or ""
        -- shortName: 从中文全名取最后一段（·分隔），如"加布里埃尔·热苏斯" → "热苏斯"
        local shortName = fullNameCn:match("·(.+)$") or fullNameCn
        -- 如果 shortName 和 fullNameCn 相同（无·分隔），则本身就是单名
        if shortName == "" then shortName = matchName ~= "" and matchName or fullName end

        local player = gameState:addPlayer({
            firstName = fullNameCn ~= "" and fullNameCn or (fullName ~= "" and fullName or "Unknown"),
            lastName = shortName,
            displayName = fullNameCn ~= "" and fullNameCn or (matchName ~= "" and matchName or fullName),
            match_name = matchName,
            shortName = shortName,
            birthYear = birthYear,
            nationality = pData.football_nation or pData.nationality or "ENG",
            position = position,
            naturalPositions = naturalPositions,
            preferredFoot = mapFootedness(pData.footedness),
            weakFoot = pData.weak_foot or 2,
            attributes = attrs,
            fitness = pData.fitness or 80,
            morale = pData.morale or 60,
            condition = pData.condition or 100,
            overall = pData.ovr or 60,
            potential = pData.potential or 70,
            contractEnd = contractEnd,
            wage = (pData.wage and pData.wage > 0) and pData.wage or 5000,
            value = pData.market_value or 1000000,
            teamId = gameTeamId,
            squadRole = mapSquadRole(pData.squad_role),
            traits = pData.traits or {},
        })

        -- 基于实际属性重新计算OVR（而非直接使用FM原始ovr）
        player:calculateOverall()

        playerIdMap[pData.id] = player.id

        -- 添加到球队
        if gameTeamId then
            local team = gameState.teams[gameTeamId]
            if team then
                team:addPlayer(player.id)
            end
        end
    end

    -- 中超：按工资预算校正球员周薪（全队约 80% 预算利用率）
    if leagueConfig.shortName == "CSL" then
        RealDataLoader._normalizeCSLPlayerWages(gameState, teamIds)
    end

    -- 3. 计算球员名气并重新计算身价（需要球队声望信息）
    for _, player in pairs(gameState.players) do
        if player.teamId then
            local team = gameState.teams[player.teamId]
            local teamRep = team and team.reputation or 300
            player:calculateReputation(teamRep)
            player:calculateValue(gameState.date.year)
        end
    end

    -- 4. 为所有球队自动选首发
    local WorldGenerator = require("scripts/systems/world_generator")
    for _, teamId in ipairs(teamIds) do
        WorldGenerator.autoSelectStartingXI(gameState, teamId)
    end

    -- 创建联赛对象
    local league = League.new({
        id = leagueConfig.shortName,
        name = leagueConfig.name,
        country = leagueConfig.country,
        season = gameState.season,
        teamIds = teamIds,
    })

    local seasonStartDate = {
        year = gameState.season or gameState.date.year,
        month = Constants.SEASON_START_MONTH,
        day = Constants.SEASON_START_DAY,
    }

    -- 中超视为「第六大联赛」：与五大联赛共用 8 月开季、周六双循环，不用 JSON 里的 3 月自然年赛程
    if leagueConfig.shortName == "CSL" then
        league:generateFixtures(seasonStartDate)
    elseif leagueData.league and leagueData.league.fixtures and #leagueData.league.fixtures > 0 then
        -- 转换JSON赛程格式到游戏格式（年份偏移：JSON数据基于2024赛季）
        local yearOffset = (gameState.season or 2025) - 2024
        league.fixtures = RealDataLoader._convertFixtures(leagueData.league.fixtures, teamIdMap, yearOffset)
        league.totalRounds = RealDataLoader._calcTotalRounds(#teamIds)
        league.currentRound = 1
        -- 个别 JSON 赛程早于 8 月赛季起点时平移（如英超 7 月）
        RealDataLoader._shiftFixturesToSeasonStart(league.fixtures, seasonStartDate)
    else
        league:generateFixtures(seasonStartDate)
    end

    league:initStandings()

    return league, teamIdMap, playerIdMap
end

-- 转换JSON赛程为游戏格式
function RealDataLoader._convertFixtures(jsonFixtures, teamIdMap, yearOffset)
    yearOffset = yearOffset or 0
    local fixtures = {}
    local fixtureId = 1

    for _, jf in ipairs(jsonFixtures) do
        -- 过滤掉 matchday 0 的无效/重复赛程
        local matchday = jf.matchday or 0
        if matchday >= 1 then
            local homeId = teamIdMap[jf.home_team_id]
            local awayId = teamIdMap[jf.away_team_id]
            if homeId and awayId then
                -- 解析日期字符串 "2024-08-17"，并应用年份偏移
                local year, month, day = jf.date:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
                table.insert(fixtures, {
                    id = fixtureId,
                    round = matchday,
                    homeTeamId = homeId,
                    awayTeamId = awayId,
                    date = {
                        year = (tonumber(year) or 2024) + yearOffset,
                        month = tonumber(month) or 8,
                        day = tonumber(day) or 1,
                    },
                    status = "scheduled",
                    homeGoals = 0,
                    awayGoals = 0,
                    events = {},
                })
                fixtureId = fixtureId + 1
            end
        end
    end

    return fixtures
end

local function _dateSerial(d)
    return d.year * 372 + d.month * 31 + d.day
end

--- 将 JSON 导入的赛程整体平移，使最早一轮对齐到赛季起点后的首个周六
--- 保留轮次间隔与对阵，仅修正日历（如英超 JSON 7 月 vs 游戏 8 月开季）
function RealDataLoader._shiftFixturesToSeasonStart(fixtures, seasonStartDate)
    if not fixtures or #fixtures == 0 or not seasonStartDate then return end

    local earliest = fixtures[1].date
    for _, f in ipairs(fixtures) do
        if f.date and _dateSerial(f.date) < _dateSerial(earliest) then
            earliest = f.date
        end
    end

    if _dateSerial(earliest) >= _dateSerial(seasonStartDate) then
        return
    end

    local target = League._alignToWeekday(seasonStartDate, 6)
    local offset = _dateSerial(target) - _dateSerial(earliest)
    if offset <= 0 then return end

    for _, f in ipairs(fixtures) do
        if f.date then
            f.date = League._addDays(f.date, offset)
        end
    end
end

--- 读档修复：旧版中超曾导入 3 月 JSON 赛程，尚无赛果时改为 8 月开季双循环
function RealDataLoader.fixMisalignedLeagueFixtures(gameState)
    if gameState._fixMisalignedLeagueFixturesDone then return end

    local seasonStart = {
        year = gameState.season or gameState.date.year,
        month = Constants.SEASON_START_MONTH,
        day = Constants.SEASON_START_DAY,
    }

    local anyFixed = false
    for key, lg in pairs(gameState.leagues or {}) do
        local needsFix = false
        local finishedCount = 0
        local misalignedScheduled = 0
        for _, f in ipairs(lg.fixtures or {}) do
            if f.status == "finished" then
                finishedCount = finishedCount + 1
            elseif f.status == "scheduled" and f.date and _dateSerial(f.date) < _dateSerial(seasonStart) then
                needsFix = true
                misalignedScheduled = misalignedScheduled + 1
            end
        end

        if not needsFix then goto continue_league end

        -- 中超旧档：无赛果或错位赛程占绝大多数 → 整季重建（典型卡住档）
        if key == "CSL" and finishedCount == 0 then
            lg:generateFixtures(seasonStart)
            lg:initStandings()
            anyFixed = true
        elseif key == "CSL" and misalignedScheduled > 0 and misalignedScheduled >= finishedCount then
            -- 少量已赛但大量 3 月残留 → 重建并放弃错位进度（比永久卡死好）
            lg:generateFixtures(seasonStart)
            lg:initStandings()
            anyFixed = true
        elseif finishedCount == 0 then
            RealDataLoader._shiftFixturesToSeasonStart(lg.fixtures, seasonStart)
            anyFixed = true
        end

        ::continue_league::
    end

    if anyFixed then
        gameState.pendingPlayerFixture = nil
    end
    gameState._fixMisalignedLeagueFixturesDone = true
end

-- 计算总轮次 (n-1)*2
function RealDataLoader._calcTotalRounds(teamCount)
    return (teamCount - 1) * 2
end

--- 加载联赛到 gameState
--- @param gameState table GameState实例
--- @param opts table|nil { includeCSL = boolean }
--- @return boolean success
function RealDataLoader.loadAllLeagues(gameState, opts)
    opts = opts or gameState.newGameOptions or {}
    gameState.newGameOptions = opts

    log:Write(LOG_INFO, "RealDataLoader: 开始加载联赛数据...")

    gameState.leagues = {}
    local totalPlayers = 0
    local totalTeams = 0

    for _, config in ipairs(RealDataLoader.getActiveLeagueConfigs(opts)) do
        local data = RealDataLoader.loadLeagueFile(config.file)
        if data then
            local league = RealDataLoader.importLeague(gameState, data, config)
            gameState.leagues[config.shortName] = league
            totalTeams = totalTeams + #league.teamIds
            log:Write(LOG_INFO, "  已加载 " .. config.name ..
                ": " .. #league.teamIds .. " 支球队, " .. #(data.players or {}) .. " 名球员")
        else
            log:Write(LOG_WARNING, "RealDataLoader: 跳过 " .. config.name .. " (文件未找到)")
        end
    end

    -- 计算总球员数
    for _ in pairs(gameState.players) do
        totalPlayers = totalPlayers + 1
    end

    log:Write(LOG_INFO, "RealDataLoader: 加载完成! 联赛:" .. RealDataLoader._countLeagues(gameState) ..
        " 球队:" .. totalTeams .. " 球员:" .. totalPlayers)

    local TeamRivalries = require("scripts/data/team_rivalries")
    local rivalryCount = TeamRivalries.initializeIfNeeded(gameState)
    log:Write(LOG_INFO, "RealDataLoader: 死敌关系 " .. tostring(rivalryCount) .. " 对")

    return totalTeams > 0
end

function RealDataLoader._countLeagues(gameState)
    local count = 0
    for _ in pairs(gameState.leagues or {}) do count = count + 1 end
    return count
end

--- 获取球队所属联赛
--- @param gameState table
--- @param teamId number
--- @return table|nil league
--- @return string|nil leagueKey
function RealDataLoader.getTeamLeague(gameState, teamId)
    if not gameState.leagues then return nil, nil end
    for key, league in pairs(gameState.leagues) do
        for _, tid in ipairs(league.teamIds) do
            if tid == teamId then
                return league, key
            end
        end
    end
    return nil, nil
end

--- 根据 wage_budget 推导球队声望
--- wage_budget 范围约 200K~6.1M，映射到 500~950 reputation
--- 这比 JSON 中的 reputation 字段更准确（原字段实际是 finance/10000，与声望无关）
function RealDataLoader._calcReputation(wageBudget)
    local wb = wageBudget or 200000
    -- 对数映射：让中等球队也有合理区分度
    -- ln(200000)≈12.2, ln(6100000)≈15.6，差值约3.4
    local logWb = math.log(wb)
    local logMin = math.log(200000)   -- 最低周薪预算
    local logMax = math.log(6500000)  -- 最高周薪预算（留余量）
    local ratio = (logWb - logMin) / (logMax - logMin)
    ratio = math.max(0, math.min(1, ratio))
    -- 映射到 500~950
    return math.floor(500 + ratio * 450)
end

--- 中超球队初始声望：顶级 550，按 wage_budget 排名每降一名 -3（全局减益，转会等仍用存盘值）
local CSL_REP_TOP = 550
local CSL_REP_STEP = 3

function RealDataLoader._buildCSLReputationMap(teams)
    local sorted = {}
    for _, t in ipairs(teams) do
        table.insert(sorted, t)
    end
    table.sort(sorted, function(a, b)
        return (a.wage_budget or 0) > (b.wage_budget or 0)
    end)

    local map = {}
    for rank, t in ipairs(sorted) do
        map[t.id] = CSL_REP_TOP - (rank - 1) * CSL_REP_STEP
    end
    return map
end

--- 是否中超球队
function RealDataLoader.isCSLTeam(gameState, teamId)
    local _, key = RealDataLoader.getTeamLeague(gameState, teamId)
    return key == "CSL"
end

--- 将中超减益声望还原为计算用尺度（500~950，与五大联赛一致）
--- 存盘 team.reputation 不变；赛季目标/董事会分档等调用此函数
function RealDataLoader.restoreCSLReputationForCalc(storedRep, teamCount)
    teamCount = math.max(2, teamCount or 16)
    local bottomRep = CSL_REP_TOP - (teamCount - 1) * CSL_REP_STEP
    storedRep = storedRep or bottomRep
    storedRep = math.max(bottomRep, math.min(CSL_REP_TOP, storedRep))
    if CSL_REP_TOP <= bottomRep then
        return 700
    end
    local ratio = (storedRep - bottomRep) / (CSL_REP_TOP - bottomRep)
    return math.floor(530 + ratio * 390)
end

--- 分档/目标等计算用声望：中超还原减益，其他联赛用存盘值
function RealDataLoader.getReputationForCalculation(gameState, teamId, team)
    team = team or (gameState.teams and gameState.teams[teamId])
    if not team then return 600 end
    local stored = team.reputation or 600
    if not RealDataLoader.isCSLTeam(gameState, teamId) then
        return stored
    end
    local league = gameState.leagues and gameState.leagues.CSL
    local teamCount = league and #league.teamIds or 16
    return RealDataLoader.restoreCSLReputationForCalc(stored, teamCount)
end

--- 声望 → 周薪预算（与 _calcReputation 互逆，用于中超等固定初始声望的联赛）
function RealDataLoader._reputationToWageBudget(reputation)
    local rep = reputation or 500
    local ratio = (rep - 500) / 450
    ratio = math.max(0, math.min(1, ratio))
    local logMin = math.log(200000)
    local logMax = math.log(6500000)
    local logWb = logMin + ratio * (logMax - logMin)
    return math.floor(math.exp(logWb))
end

--- 中超球员周薪：按各队 wageBudget 缩放至约 80% 利用率
function RealDataLoader._normalizeCSLPlayerWages(gameState, teamIds)
    local targetUtil = 0.80
    for _, teamId in ipairs(teamIds) do
        local team = gameState.teams[teamId]
        if team then
            local budget = team.wageBudget or 200000
            local total = 0
            local roster = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p then
                    total = total + (p.wage or 0)
                    table.insert(roster, p)
                end
            end
            if total > 0 then
                local factor = (budget * targetUtil) / total
                for _, p in ipairs(roster) do
                    p.wage = math.max(64, math.floor((p.wage or 0) * factor))
                end
            end
        end
    end
end

--- 根据球队声望和特征分配合理风格（避免全部 Balanced）
--- 高声望队更偏进攻/控球，低声望队更偏防守/反击
function RealDataLoader._assignPlayStyle(tData)
    -- 如果数据中已指定非 Balanced 风格，尊重原始数据
    if tData.play_style and tData.play_style ~= "Balanced" then
        return tData.play_style
    end

    local rep = tData.reputation or 500
    local roll = Random()

    -- 高声望（前6名级别）: 进攻/控球/高压为主
    if rep >= 700 then
        if roll < 0.25 then return "Attacking"
        elseif roll < 0.50 then return "Possession"
        elseif roll < 0.70 then return "HighPress"
        elseif roll < 0.85 then return "Balanced"
        else return "Counter"
        end
    -- 中上声望
    elseif rep >= 600 then
        if roll < 0.20 then return "Attacking"
        elseif roll < 0.40 then return "Possession"
        elseif roll < 0.55 then return "Counter"
        elseif roll < 0.70 then return "HighPress"
        elseif roll < 0.85 then return "Balanced"
        else return "Defensive"
        end
    -- 中下声望
    elseif rep >= 500 then
        if roll < 0.25 then return "Counter"
        elseif roll < 0.45 then return "Balanced"
        elseif roll < 0.60 then return "Defensive"
        elseif roll < 0.75 then return "HighPress"
        elseif roll < 0.90 then return "Possession"
        else return "Attacking"
        end
    -- 低声望: 防守/反击为主
    else
        if roll < 0.30 then return "Defensive"
        elseif roll < 0.55 then return "Counter"
        elseif roll < 0.75 then return "Balanced"
        elseif roll < 0.90 then return "HighPress"
        else return "Attacking"
        end
    end
end

--- 根据球队风格分配合理阵型
function RealDataLoader._assignFormation(tData)
    -- 如果数据中已指定非默认阵型，尊重原始数据
    if tData.formation and tData.formation ~= "4-4-2" then
        return tData.formation
    end

    -- 根据随机权重分配阵型
    local formations = {
        {"4-3-3",   0.25},
        {"4-2-3-1", 0.25},
        {"4-4-2",   0.20},
        {"3-5-2",   0.12},
        {"5-3-2",   0.10},
        {"4-5-1",   0.08},
    }

    local roll = Random()
    local cumulative = 0
    for _, entry in ipairs(formations) do
        cumulative = cumulative + entry[2]
        if roll < cumulative then
            return entry[1]
        end
    end
    return "4-4-2"
end

--- 加载传奇球员（非五大联赛）作为自由球员
--- @param gameState table GameState实例
--- @return number count 成功加载的球员数量
function RealDataLoader.loadLegends(gameState)
    local data = RealDataLoader.loadLeagueFile("fm2024_legends_outside_top5.json")
    if not data or not data.players then
        log:Write(LOG_WARNING, "RealDataLoader: 无法加载传奇球员数据")
        return 0
    end

    local count = 0
    for _, pData in ipairs(data.players) do
        local position, naturalPositions = mapPositions(pData.position, pData.alternate_positions)
        local attrs = convertAttributes(pData.attributes or {})
        local birthYear = extractBirthYear(pData.date_of_birth)

        -- 名字处理（同主加载逻辑）
        local fullNameCn = pData.full_name_cn or ""
        local matchName = pData.match_name or ""
        local fullName = pData.full_name or ""
        local shortName = fullNameCn:match("·(.+)$") or fullNameCn
        if shortName == "" then shortName = matchName ~= "" and matchName or fullName end

        -- 传奇球员作为自由球员加入（teamId = nil）
        local player = gameState:addPlayer({
            firstName = fullNameCn ~= "" and fullNameCn or (fullName ~= "" and fullName or "Unknown"),
            lastName = shortName,
            displayName = fullNameCn ~= "" and fullNameCn or (matchName ~= "" and matchName or fullName),
            match_name = matchName,
            shortName = shortName,
            birthYear = birthYear,
            nationality = pData.football_nation or pData.nationality or "ENG",
            position = position,
            naturalPositions = naturalPositions,
            preferredFoot = mapFootedness(pData.footedness),
            weakFoot = pData.weak_foot or 2,
            attributes = attrs,
            fitness = pData.fitness or 80,
            morale = pData.morale or 60,
            condition = pData.condition or 100,
            overall = pData.ovr or 70,
            potential = pData.potential or 70,
            contractEnd = nil,  -- 自由球员无合同
            wage = (pData.wage and pData.wage > 0) and pData.wage or 50000,  -- 期望周薪（谈判参考）
            value = pData.market_value or 1000000,
            teamId = nil,       -- 自由球员
            squadRole = "first_team",
            traits = pData.traits or {},
            isLegend = true,    -- 标记为传奇球员，可突破99总评上限
            legendName = matchName ~= "" and matchName or fullName,
        })

        -- 基于实际属性重新计算OVR
        player:calculateOverall()
        -- 自由球员名气基于其历史声望（用原始ovr推算）
        local estimatedRep = math.min(900, (pData.ovr or 70) * 10)
        player:calculateReputation(estimatedRep)
        player:calculateValue(gameState.date.year)

        count = count + 1
        log:Write(LOG_DEBUG, "  传奇自由球员: " .. (pData.match_name or "?") ..
            " (" .. position .. ", OVR=" .. player.overall .. ")")
    end

    log:Write(LOG_INFO, "RealDataLoader: 加载了 " .. count .. " 名传奇自由球员")
    return count
end

--- 加载青训妖人名单，随机分配到各俱乐部青训队
---@param gameState table
---@return number 加载的球员数
function RealDataLoader.loadWonderkids(gameState)
    local data = RealDataLoader.loadLeagueFile("wonderkids_outside_top5_2025.json")
    if not data or not data.players then
        log:Write(LOG_WARNING, "RealDataLoader: 无法加载青训妖人数据")
        return 0
    end

    -- 收集所有球队 ID
    local teamIds = {}
    for teamId, _ in pairs(gameState.teams) do
        table.insert(teamIds, teamId)
    end
    if #teamIds == 0 then
        log:Write(LOG_WARNING, "RealDataLoader: 没有可用球队，跳过青训分配")
        return 0
    end

    -- 打乱 wonderkids 顺序
    local shuffled = {}
    for _, p in ipairs(data.players) do table.insert(shuffled, p) end
    for i = #shuffled, 2, -1 do
        local j = RandomInt(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local count = 0
    for _, pData in ipairs(shuffled) do
        -- 随机选择一支球队
        local teamId = teamIds[RandomInt(1, #teamIds)]
        local team = gameState.teams[teamId]

        local position, naturalPositions = mapPositions(pData.position, pData.alternate_positions)
        local attrs = convertAttributes(pData.attributes or {})
        local birthYear = extractBirthYear(pData.date_of_birth)

        local fullNameCn = pData.full_name_cn or ""
        local matchName = pData.match_name or ""
        local fullName = pData.full_name or ""
        local shortName = fullNameCn:match("·(.+)$") or fullNameCn
        if shortName == "" then shortName = matchName ~= "" and matchName or fullName end

        local player = gameState:addPlayer({
            firstName = fullNameCn ~= "" and fullNameCn or (fullName ~= "" and fullName or "Unknown"),
            lastName = shortName,
            displayName = fullNameCn ~= "" and fullNameCn or (matchName ~= "" and matchName or fullName),
            match_name = matchName,
            shortName = shortName,
            birthYear = birthYear,
            nationality = pData.football_nation or pData.nationality or "ENG",
            position = position,
            naturalPositions = naturalPositions,
            preferredFoot = mapFootedness(pData.footedness),
            weakFoot = pData.weak_foot or 2,
            attributes = attrs,
            fitness = pData.fitness or 80,
            morale = pData.morale or 70,
            condition = pData.condition or 100,
            overall = pData.ovr or 50,
            potential = pData.potential or 70,
            contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
            wage = 500,  -- 青训球员固定周薪
            value = pData.market_value or 500000,
            teamId = teamId,
            squadRole = "youth",
            isYouth = true,
            traits = pData.traits or {},
        })

        -- 计算OVR和价值
        player:calculateOverall()
        player:calculateValue(gameState.date.year)

        -- 加入球队青训队列表
        team._youthPlayerIds = team._youthPlayerIds or {}
        table.insert(team._youthPlayerIds, player.id)

        count = count + 1
    end

    log:Write(LOG_INFO, "RealDataLoader: 加载了 " .. count .. " 名青训妖人，分配到 " .. #teamIds .. " 支球队")
    return count
end

--- 动态加载一个可选联赛（如 CSL）并导入到 gameState
---@param gameState table
---@param leagueKey string 联赛 shortName（如 "CSL"）
---@return boolean success
function RealDataLoader.loadOptionalLeague(gameState, leagueKey)
    if gameState.leagues[leagueKey] then
        log:Write(LOG_WARNING, "RealDataLoader: 联赛 " .. leagueKey .. " 已加载，跳过")
        return true
    end

    local config = RealDataLoader.OPTIONAL_LEAGUES[leagueKey]
    if not config then
        log:Write(LOG_ERROR, "RealDataLoader: 未知可选联赛 " .. leagueKey)
        return false
    end

    local data = RealDataLoader.loadLeagueFile(config.file)
    if not data then
        log:Write(LOG_ERROR, "RealDataLoader: 无法加载联赛文件 " .. config.file)
        return false
    end

    local league = RealDataLoader.importLeague(gameState, data, config)
    gameState.leagues[leagueKey] = league

    log:Write(LOG_INFO, "RealDataLoader: 动态加载联赛 " .. config.name .. " 完成，" .. #league.teamIds .. " 支球队")
    return true
end

--- 动态卸载一个可选联赛，移除其球队和球员
---@param gameState table
---@param leagueKey string 联赛 shortName（如 "CSL"）
---@return boolean success
function RealDataLoader.unloadOptionalLeague(gameState, leagueKey)
    local league = gameState.leagues[leagueKey]
    if not league then
        log:Write(LOG_WARNING, "RealDataLoader: 联赛 " .. leagueKey .. " 未加载，无需卸载")
        return true
    end

    -- 移除联赛下所有球队的球员
    for _, teamId in ipairs(league.teamIds) do
        local team = gameState.teams[teamId]
        if team then
            -- 移除球队的球员
            local playerIds = team.playerIds or {}
            for _, playerId in ipairs(playerIds) do
                gameState.players[playerId] = nil
            end
            -- 移除青训球员
            if team._youthPlayerIds then
                for _, playerId in ipairs(team._youthPlayerIds) do
                    gameState.players[playerId] = nil
                end
            end
        end
        -- 移除球队
        gameState.teams[teamId] = nil
    end

    -- 移除联赛
    gameState.leagues[leagueKey] = nil

    log:Write(LOG_INFO, "RealDataLoader: 已卸载联赛 " .. leagueKey)
    return true
end

return RealDataLoader
