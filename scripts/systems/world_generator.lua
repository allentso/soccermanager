-- systems/world_generator.lua
-- 世界生成系统：加载五大联赛真实数据，保留随机生成用于青训/自由球员

local Constants = require("scripts/app/constants")
local JsonLoader = require("scripts/data/json_loader")
local RealDataLoader = require("scripts/data/real_data_loader")
local League = require("scripts/domain/league")
local ChampionsLeague = require("scripts/systems/champions_league")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local YouthManager = require("scripts/systems/youth_manager")

local WorldGenerator = {}

-- 姓名池缓存
local namePools = nil

local function loadNamePools()
    if namePools then return namePools end
    namePools = JsonLoader.loadNames()
    if not namePools then
        -- 兜底数据
        namePools = {
            ENG = {
                first_names = {"James","Harry","Jack","Oliver","George","Charlie","Thomas","William","Daniel","Ben"},
                last_names = {"Smith","Johnson","Brown","Jones","Taylor","Wilson","Walker","Robinson","Clark","Wright"}
            }
        }
    end
    return namePools
end

-- 随机选取
local function pick(list)
    if not list or #list == 0 then return "Unknown" end
    return list[RandomInt(1, #list)]
end

-- 随机整数
local function randInt(min, max)
    return RandomInt(min, max)
end

-- 随机浮点
local function randFloat(min, max)
    return Random(min, max)
end

-- 根据国家获取姓名
local function getRandomName(country)
    local pools = loadNamePools()
    local pool = pools[country] or pools["ENG"] or pools["GB"]
    if not pool then
        pool = {first_names = {"Player"}, last_names = {"Unknown"}}
    end
    local first = pick(pool.first_names)
    local last = pick(pool.last_names)
    return first, last
end

-- 生成球员属性
local function generateAttributes(position, overall, age)
    local base = overall / 20.0  -- 映射到1-5范围后再乘以4
    local spread = 4

    local function attr(weight)
        local v = base * weight + randFloat(-spread, spread)
        return math.max(Constants.ATTR_MIN, math.min(Constants.ATTR_MAX, math.floor(v)))
    end

    local attrs = {}
    if position == "GK" then
        attrs.handling = attr(4.0)
        attrs.reflexes = attr(4.0)
        attrs.positioning = attr(3.0)
        attrs.aerial = attr(2.5)
        attrs.composure = attr(2.5)
        attrs.decisions = attr(2.0)
        attrs.speed = attr(1.0)
        attrs.stamina = attr(1.5)
        attrs.strength = attr(2.0)
        attrs.agility = attr(2.0)
        attrs.passing = attr(1.5)
        attrs.shooting = attr(0.5)
        attrs.tackling = attr(0.5)
        attrs.dribbling = attr(0.5)
        attrs.defending = attr(1.0)
        attrs.vision = attr(1.5)
        attrs.aggression = attr(1.0)
        attrs.teamwork = attr(2.0)
        attrs.leadership = attr(2.0)
    elseif position == "CB" then
        attrs.defending = attr(4.0)
        attrs.tackling = attr(3.5)
        attrs.aerial = attr(3.0)
        attrs.strength = attr(3.0)
        attrs.positioning = attr(3.0)
        attrs.composure = attr(2.5)
        attrs.decisions = attr(2.0)
        attrs.speed = attr(1.5)
        attrs.stamina = attr(2.0)
        attrs.agility = attr(1.0)
        attrs.passing = attr(2.0)
        attrs.shooting = attr(0.8)
        attrs.dribbling = attr(0.8)
        attrs.vision = attr(1.5)
        attrs.aggression = attr(2.5)
        attrs.teamwork = attr(2.5)
        attrs.leadership = attr(2.5)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    elseif position == "LB" or position == "RB" then
        attrs.speed = attr(3.5)
        attrs.stamina = attr(3.5)
        attrs.defending = attr(3.0)
        attrs.tackling = attr(2.5)
        attrs.passing = attr(2.5)
        attrs.dribbling = attr(2.0)
        attrs.positioning = attr(2.0)
        attrs.agility = attr(2.0)
        attrs.strength = attr(1.5)
        attrs.aerial = attr(1.5)
        attrs.composure = attr(1.5)
        attrs.decisions = attr(1.5)
        attrs.vision = attr(1.5)
        attrs.shooting = attr(1.0)
        attrs.aggression = attr(1.5)
        attrs.teamwork = attr(2.5)
        attrs.leadership = attr(1.5)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    elseif position == "CM" or position == "CDM" or position == "CAM" then
        attrs.passing = attr(3.5)
        attrs.vision = attr(3.0)
        attrs.decisions = attr(3.0)
        attrs.stamina = attr(3.0)
        attrs.tackling = attr(position == "CDM" and 3.0 or 2.0)
        attrs.dribbling = attr(position == "CAM" and 3.0 or 2.0)
        attrs.shooting = attr(position == "CAM" and 2.5 or 1.5)
        attrs.positioning = attr(2.5)
        attrs.composure = attr(2.5)
        attrs.speed = attr(2.0)
        attrs.agility = attr(2.0)
        attrs.strength = attr(2.0)
        attrs.defending = attr(position == "CDM" and 2.5 or 1.5)
        attrs.aerial = attr(1.5)
        attrs.aggression = attr(2.0)
        attrs.teamwork = attr(3.0)
        attrs.leadership = attr(2.5)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    elseif position == "LM" or position == "RM" then
        attrs.passing = attr(3.0)
        attrs.stamina = attr(3.0)
        attrs.speed = attr(3.0)
        attrs.dribbling = attr(2.8)
        attrs.vision = attr(2.5)
        attrs.decisions = attr(2.5)
        attrs.tackling = attr(2.0)
        attrs.defending = attr(1.8)
        attrs.shooting = attr(1.8)
        attrs.positioning = attr(2.2)
        attrs.composure = attr(2.0)
        attrs.teamwork = attr(3.0)
        attrs.agility = attr(2.5)
        attrs.strength = attr(1.8)
        attrs.aerial = attr(1.2)
        attrs.aggression = attr(1.8)
        attrs.leadership = attr(1.8)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    elseif position == "LW" or position == "RW" then
        attrs.speed = attr(3.5)
        attrs.dribbling = attr(3.5)
        attrs.agility = attr(3.0)
        attrs.passing = attr(2.5)
        attrs.shooting = attr(2.5)
        attrs.stamina = attr(2.5)
        attrs.vision = attr(2.0)
        attrs.composure = attr(2.0)
        attrs.decisions = attr(2.0)
        attrs.positioning = attr(2.0)
        attrs.strength = attr(1.5)
        attrs.tackling = attr(1.0)
        attrs.defending = attr(1.0)
        attrs.aerial = attr(1.0)
        attrs.aggression = attr(1.5)
        attrs.teamwork = attr(2.0)
        attrs.leadership = attr(1.5)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    else  -- ST
        attrs.shooting = attr(4.0)
        attrs.composure = attr(3.5)
        attrs.positioning = attr(3.0)
        attrs.speed = attr(2.5)
        attrs.dribbling = attr(2.5)
        attrs.strength = attr(2.5)
        attrs.aerial = attr(2.5)
        attrs.agility = attr(2.0)
        attrs.decisions = attr(2.0)
        attrs.vision = attr(1.5)
        attrs.passing = attr(1.5)
        attrs.stamina = attr(2.0)
        attrs.tackling = attr(0.5)
        attrs.defending = attr(0.5)
        attrs.aggression = attr(2.0)
        attrs.teamwork = attr(2.0)
        attrs.leadership = attr(2.0)
        attrs.handling = attr(0.3)
        attrs.reflexes = attr(0.3)
    end

    return attrs
end

-- 生成一名球员
local function generatePlayer(gameState, teamId, position, country, reputationBase)
    local first, last = getRandomName(country)
    local age = randInt(Constants.AGE_MIN, Constants.AGE_MAX)
    local birthYear = gameState.date.year - age

    -- 基于声望和年龄确定能力
    local overallBase = math.floor(reputationBase / 10) -- 500-900 => 50-90
    overallBase = overallBase + randInt(-8, 8)
    -- 年龄修正
    if age < 21 then overallBase = overallBase - randInt(5, 12)
    elseif age > 32 then overallBase = overallBase - randInt(3, 8)
    end
    overallBase = math.max(Constants.ABILITY_MIN + 10, math.min(Constants.ABILITY_MAX - 5, overallBase))

    -- 潜力（随机生成球员上限92，避免泛滥突破巨星阈值95）
    local GENERATED_POTENTIAL_MAX = 92
    local potential = overallBase + randInt(0, 12)
    if age <= 22 then potential = potential + randInt(2, 7) end
    potential = math.max(overallBase, math.min(GENERATED_POTENTIAL_MAX, potential))

    local attrs = generateAttributes(position, overallBase, age)

    -- 工资基于能力
    local wage = math.floor((overallBase * overallBase * 2) + randInt(500, 2000))

    -- 合同
    local contractYears = randInt(1, 4)
    local contractEnd = {year = gameState.date.year + contractYears, month = 6}

    local player = gameState:addPlayer({
        firstName = first,
        lastName = last,
        displayName = first .. " " .. last,
        birthYear = birthYear,
        nationality = country,
        position = position,
        naturalPositions = {position},
        preferredFoot = Random() > 0.3 and "right" or "left",
        weakFoot = randInt(1, 4),
        attributes = attrs,
        fitness = randInt(70, 95),
        morale = randInt(50, 80),
        condition = randInt(75, 100),
        overall = overallBase,
        potential = potential,
        contractEnd = contractEnd,
        wage = wage,
        teamId = teamId,
        squadRole = "first_team",
    })

    return player
end

-- 生成球队的所有球员
local function generateSquad(gameState, teamId, country, reputation)
    local positions = {}
    -- 2 GK
    for i = 1, Constants.GK_COUNT do table.insert(positions, "GK") end
    -- 7 DEF
    local defPos = {"CB", "CB", "CB", "LB", "LB", "RB", "RB"}
    for _, p in ipairs(defPos) do table.insert(positions, p) end
    -- 7 MID
    local midPos = {"CM", "CM", "CM", "CDM", "CAM", "LM", "RM"}
    for _, p in ipairs(midPos) do table.insert(positions, p) end
    -- 6 FWD
    local fwdPos = {"ST", "ST", "ST", "LW", "RW", "ST"}
    for _, p in ipairs(fwdPos) do table.insert(positions, p) end

    local team = gameState.teams[teamId]
    for _, pos in ipairs(positions) do
        local player = generatePlayer(gameState, teamId, pos, country, reputation)
        -- 计算名气并重新计算身价
        player:calculateReputation(reputation)
        player:calculateValue(gameState.date.year)
        team:addPlayer(player.id)
    end

    -- 自动选择首发11人
    WorldGenerator.autoSelectStartingXI(gameState, teamId)
end

-- 自动选择首发（按球队实际阵型的槽位需求选人）
function WorldGenerator.autoSelectStartingXI(gameState, teamId)
    local AIManager = require("scripts/systems/ai_manager")
    local team = gameState.teams[teamId]
    if not team then return end

    local players = gameState:getTeamPlayers(teamId)
    if #players < 11 then return end

    local slots = AIManager._getFormationSlots(team)

    -- 贪心分配：对每个槽位选最佳匹配球员
    local selected = {}
    local usedIds = {}

    for _, slot in ipairs(slots) do
        local bestPlayer = nil
        local bestScore = -1

        for _, p in ipairs(players) do
            if not usedIds[p.id] and not p.retired and not p.injured then
                local score = AIManager._playerPositionScore(p, slot)
                -- 首次选人加权体能
                score = score * ((p.fitness or 100) / 100)
                if score > bestScore then
                    bestScore = score
                    bestPlayer = p
                end
            end
        end

        if bestPlayer then
            table.insert(selected, bestPlayer.id)
            usedIds[bestPlayer.id] = true
        end
    end

    team.startingXI = selected

    -- 设置队长为能力最高的球员
    local best = nil
    for _, pid in pairs(team.startingXI or {}) do
        local p = gameState.players[pid]
        if p and (not best or p.overall > best.overall) then best = p end
    end
    if best then team.captain = best.id end

    -- 分配阵容角色 (key/rotation/squad/youth)
    local starterSet = {}
    for _, pid in pairs(team.startingXI or {}) do starterSet[pid] = true end

    local allPlayers = gameState:getTeamPlayers(teamId)
    table.sort(allPlayers, function(a, b) return a.overall > b.overall end)

    local keyCount = 0
    for _, p in ipairs(allPlayers) do
        if p.squadRole == "loaned" then
            -- 保持租借状态不变
        elseif starterSet[p.id] then
            -- 首发中前5能力最强为key，其余为rotation
            if keyCount < 5 then
                p.squadRole = "key"
                keyCount = keyCount + 1
            else
                p.squadRole = "rotation"
            end
        else
            -- 替补：年轻低能力为youth，其余为squad
            local age = p.birthYear and (gameState.date.year - p.birthYear) or 25
            if age <= 20 and p.overall < 55 then
                p.squadRole = "youth"
            else
                p.squadRole = "squad"
            end
        end
    end
end

-- 生成职员
local function generateStaff(gameState, teamId, country)
    local roles = {
        Constants.STAFF_ROLES.ASSISTANT,
        Constants.STAFF_ROLES.COACH,
        Constants.STAFF_ROLES.SCOUT,
        Constants.STAFF_ROLES.PHYSIO
    }
    local specialties = {"fitness", "technical", "tactical", "defense", "attack", "goalkeeper", "youth"}
    local team = gameState.teams[teamId]

    for _, role in ipairs(roles) do
        local first, last = getRandomName(country)
        local s = gameState:addStaff({
            firstName = first,
            lastName = last,
            displayName = first .. " " .. last,
            nationality = country,
            birthYear = randInt(1965, 1990),
            role = role,
            teamId = teamId,
            wage = randInt(3000, 8000),
            attributes = {
                training = randInt(8, 16),
                tactical = randInt(8, 16),
                scouting = randInt(8, 16),
                physiotherapy = randInt(8, 16),
                youthDev = randInt(8, 16),
                motivation = randInt(8, 16),
            },
            specialty = pick(specialties),
        })
        team.staffIds[#team.staffIds + 1] = s.id
    end
end

-- 生成AI经理
function WorldGenerator.generateAIManager(gameState, teamId, country)
    local first, last = getRandomName(country)
    local m = gameState:addManager({
        firstName = first,
        lastName = last,
        displayName = first .. " " .. last,
        birthYear = randInt(1960, 1985),
        nationality = country,
        teamId = teamId,
        isPlayer = false,
        reputation = randInt(200, 600),
    })
    local team = gameState.teams[teamId]
    team.managerId = m.id
    return m
end

--- 为联赛内尚未配置职员的球队补全职员与 AI 经理（动态加载联赛时用）
function WorldGenerator.bootstrapLeagueTeams(gameState, leagueKey)
    local lg = gameState.leagues and gameState.leagues[leagueKey]
    if not lg then return end
    for _, teamId in ipairs(lg.teamIds) do
        local team = gameState.teams[teamId]
        if team then
            if not team.staffIds or #team.staffIds == 0 then
                generateStaff(gameState, teamId, team.country)
            end
            if not team.managerId then
                WorldGenerator.generateAIManager(gameState, teamId, team.country)
            end
        end
    end
end

-- 生成完整世界（使用真实联赛数据）
---@param gameState table
---@param opts table|nil { includeCSL = boolean, includeSecondDivisions = boolean, enableReincarnation = boolean }
function WorldGenerator.generate(gameState, opts)
    opts = opts or {}
    if opts.enableReincarnation == nil then
        opts.enableReincarnation = true
    end
    gameState.newGameOptions = opts
    log:Write(LOG_INFO, "WorldGenerator: 开始加载联赛真实数据...")

    local success = RealDataLoader.loadAllLeagues(gameState, opts)
    if not success then
        log:Write(LOG_ERROR, "WorldGenerator: 无法加载联赛数据")
        return false
    end

    -- 为每支球队生成AI经理和职员
    for _, lg in pairs(gameState.leagues) do
        for _, teamId in ipairs(lg.teamIds) do
            local team = gameState.teams[teamId]
            if team then
                -- 生成职员
                generateStaff(gameState, teamId, team.country)
                -- 生成AI经理
                WorldGenerator.generateAIManager(gameState, teamId, team.country)
            end
        end
    end

    -- 生成自由职员
    for i = 1, Constants.FREE_STAFF_COUNT do
        local countries = {"ENG", "ES", "DE", "FR", "IT", "PT", "NL", "BE"}
        local country = pick(countries)
        local first, last = getRandomName(country)
        local roles = {Constants.STAFF_ROLES.COACH, Constants.STAFF_ROLES.SCOUT, Constants.STAFF_ROLES.PHYSIO}
        gameState:addStaff({
            firstName = first,
            lastName = last,
            displayName = first .. " " .. last,
            nationality = country,
            birthYear = randInt(1965, 1990),
            role = pick(roles),
            teamId = nil,
            wage = randInt(2000, 6000),
            attributes = {
                training = randInt(6, 14),
                tactical = randInt(6, 14),
                scouting = randInt(6, 14),
                physiotherapy = randInt(6, 14),
                youthDev = randInt(6, 14),
                motivation = randInt(6, 14),
            },
        })
    end

    -- 加载传奇自由球员（非五大联赛的知名球员）
    RealDataLoader.loadLegends(gameState)

    -- 加载青训妖人名单，随机分配到各俱乐部青训队
    RealDataLoader.loadWonderkids(gameState)

    if opts.enableReincarnation then
        -- 加载重生球员（独立名单，入队逻辑与小妖相同）
        RealDataLoader.loadRebirthPlayers(gameState)
    end

    -- 为所有球队填充青训至10人（已有 wonderkids 的球队只补齐差额）
    YouthManager.fillAllTeamsYouth(gameState)
    gameState._aiYouthRosterBootstrapped = true

    -- 初始化潜力系统（为所有球员生成 PA Rating 和局内实际潜力）
    PotentialSystem.initializeAllPlayers(gameState)

    -- 初始化自由职员池（供玩家招聘）
    StaffManager.generateFreeStaff(gameState)

    -- 初始化首批青训候选球员
    YouthManager._refreshCandidates(gameState)

    -- 初始化首赛季欧冠
    ChampionsLeague.initialize(gameState)

    -- 初始化首赛季欧联杯
    local EuropaLeague = require("scripts/systems/europa_league")
    EuropaLeague.initialize(gameState)

    local ReincarnationManager = require("scripts/systems/reincarnation_manager")
    if ReincarnationManager.isEnabled(gameState) then
        ReincarnationManager.initNewGame(gameState)
    end

    log:Write(LOG_INFO, "WorldGenerator: 世界生成完成! 球员:" .. WorldGenerator._countPlayers(gameState))

    return true
end

function WorldGenerator._countPlayers(gameState)
    local count = 0
    for _ in pairs(gameState.players) do count = count + 1 end
    return count
end

return WorldGenerator
