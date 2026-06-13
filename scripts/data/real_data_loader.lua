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
            reputation = RealDataLoader._calcReputation(tData.wage_budget),
            _baseReputation = RealDataLoader._calcReputation(tData.wage_budget),
            playStyle = RealDataLoader._assignPlayStyle(tData),
            formation = RealDataLoader._assignFormation(tData),
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
        -- 转换JSON赛程格式到游戏格式（年份偏移：JSON数据基于2024赛季）
        local yearOffset = (gameState.season or 2025) - 2024
        league.fixtures = RealDataLoader._convertFixtures(leagueData.league.fixtures, teamIdMap, yearOffset)
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
            wage = pData.wage or 50000,  -- 期望周薪（谈判参考）
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

return RealDataLoader
