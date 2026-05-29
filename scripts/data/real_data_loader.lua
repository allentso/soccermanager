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
    CenterBack = "CB",
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
    Striker = "ST",
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

-- 联赛文件配置
RealDataLoader.LEAGUE_FILES = {
    {file = "fm2024_premier_league.json",  name = "英超",    country = "ENG", shortName = "EPL"},
    {file = "fm2024_la_liga.json",         name = "西甲",    country = "ES",  shortName = "LaLiga"},
    {file = "fm2024_serie_a.json",         name = "意甲",    country = "IT",  shortName = "SerieA"},
    {file = "fm2024_bundesliga.json",      name = "德甲",    country = "DE",  shortName = "Bundesliga"},
    {file = "fm2024_ligue_1.json",         name = "法甲",    country = "FR",  shortName = "Ligue1"},
}

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

    -- 1. 导入球队
    for _, tData in ipairs(leagueData.teams) do
        local team = gameState:addTeam({
            name = tData.name,
            shortName = tData.short_name or "",
            jsonTeamId = tData.id,
            iconPath = TeamIconRegistry.getPathByJsonId(tData.id),
            city = tData.city or "",
            country = tData.country or leagueConfig.country,
            colors = tData.colors or {primary = "#333333", secondary = "#ffffff"},
            stadiumName = tData.stadium_name or "",
            stadiumCapacity = tData.stadium_capacity or 30000,
            foundedYear = tData.founded_year or 1900,
            reputation = tData.reputation or 500,
            playStyle = tData.play_style or "Balanced",
            formation = tData.formation or "4-4-2",
            -- 用wage_budget推算合理财务（FM原始finance/transfer_budget数值偏低）
            -- 现实参照: 顶级俱乐部(周薪5M+)转会预算~150M, 余额~500M
            balance = (tData.wage_budget or 200000) * 80,
            wageBudget = tData.wage_budget or 200000,
            transferBudget = (tData.wage_budget or 200000) * 25,
            trainingFocus = tData.training_focus or "balanced",
            trainingIntensity = (tData.training_intensity or "Medium"):lower(),
        })

        teamIdMap[tData.id] = team.id
        table.insert(teamIds, team.id)
    end

    -- 2. 导入球员
    for _, pData in ipairs(leagueData.players) do
        local position, naturalPositions = mapPositions(pData.position, pData.alternate_positions)
        local attrs = convertAttributes(pData.attributes or {})
        local birthYear = extractBirthYear(pData.date_of_birth)
        local contractEnd = extractContractEnd(pData.contract_end)

        -- 解析teamId
        local gameTeamId = teamIdMap[pData.team_id]

        local player = gameState:addPlayer({
            firstName = pData.full_name or pData.match_name or "Unknown",
            lastName = "",
            displayName = pData.match_name or pData.full_name or "Unknown",
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
            wage = pData.wage or 5000,
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

    -- 4. 创建联赛对象
    local league = League.new({
        id = leagueConfig.shortName,
        name = leagueConfig.name,
        country = leagueConfig.country,
        season = gameState.season,
        teamIds = teamIds,
    })

    -- 使用JSON中的赛程（如果有），否则自动生成
    if leagueData.league and leagueData.league.fixtures and #leagueData.league.fixtures > 0 then
        -- 转换JSON赛程格式到游戏格式
        league.fixtures = RealDataLoader._convertFixtures(leagueData.league.fixtures, teamIdMap)
        league.totalRounds = RealDataLoader._calcTotalRounds(#teamIds)
        league.currentRound = 1
    else
        league:generateFixtures({
            year = gameState.date.year,
            month = gameState.date.month,
            day = gameState.date.day,
        })
    end

    league:initStandings()

    return league, teamIdMap, playerIdMap
end

-- 转换JSON赛程为游戏格式
function RealDataLoader._convertFixtures(jsonFixtures, teamIdMap)
    local fixtures = {}
    local fixtureId = 1

    for _, jf in ipairs(jsonFixtures) do
        local homeId = teamIdMap[jf.home_team_id]
        local awayId = teamIdMap[jf.away_team_id]
        if homeId and awayId then
            -- 解析日期字符串 "2024-08-17"
            local year, month, day = jf.date:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
            table.insert(fixtures, {
                id = fixtureId,
                round = (jf.matchday or 0) + 1,
                homeTeamId = homeId,
                awayTeamId = awayId,
                date = {
                    year = tonumber(year) or 2024,
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

    return fixtures
end

-- 计算总轮次 (n-1)*2
function RealDataLoader._calcTotalRounds(teamCount)
    return (teamCount - 1) * 2
end

--- 加载所有五大联赛到 gameState
--- @param gameState table GameState实例
--- @return boolean success
function RealDataLoader.loadAllLeagues(gameState)
    log:Write(LOG_INFO, "RealDataLoader: 开始加载五大联赛数据...")

    gameState.leagues = {}
    local totalPlayers = 0
    local totalTeams = 0

    for _, config in ipairs(RealDataLoader.LEAGUE_FILES) do
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

return RealDataLoader
