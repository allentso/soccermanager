-- systems/reincarnation_manager.lua
-- 转生机制：退役传奇球员以青训新星身份重新出现在随机球队

local PotentialSystem = require("scripts/systems/potential_system")
local Player = require("scripts/domain/player")
local YouthManager = require("scripts/systems/youth_manager")

local ReincarnationManager = {}

local MAX_YOUTH_SQUAD = YouthManager.MAX_YOUTH_SQUAD

------------------------------------------------------
-- 转生名单：只有名单中的球员退役后才会触发转生
------------------------------------------------------

---@class ReincarnationEntry
---@field matchName string 用于匹配退役球员的主键名
---@field matchAltNames string[] 备选名字（兼容不同数据源的拼写）
---@field requireLegend boolean|nil 为 true 时仅匹配 isLegend 球员（防同名联赛球员误占名额）
---@field allowFallbackFirstSeason boolean|nil 为 true 时允许无源球员也在首季末用 fallback 转生
---@field potential number 转生后潜力值
---@field attrBonus table<string, number> 位置专精额外加成

---@type ReincarnationEntry[]
ReincarnationManager.REINCARNATION_LIST = {
    -- ============ S 级 (潜力 96-99, 加成 +14, 3特性) ============
    {
        matchName = "Lionel Messi",
        matchAltNames = { "L. Messi", "Messi", "梅西", "莱昂内尔·梅西" },
        potential = 99,
        attrBonus = { dribbling = 4, vision = 3, agility = 3, passing = 2, shooting = 2 },
        traits = { "dribbler", "playmaker", "clinical" },
    },
    {
        matchName = "Cristiano Ronaldo",
        matchAltNames = { "C. Ronaldo", "CR7", "C罗", "克里斯蒂亚诺·罗纳尔多" },
        potential = 96,
        attrBonus = { shooting = 4, speed = 3, strength = 3, aerial = 2, composure = 2 },
        traits = { "clinical", "pace_merchant", "aerial_threat" },
    },

    -- ============ A 级 (潜力 91-93, 加成 +12, 3特性) ============
    {
        matchName = "Neymar Jr.",
        matchAltNames = { "Neymar", "内马尔", "内马尔·达席尔瓦" },
        potential = 93,
        attrBonus = { dribbling = 4, agility = 3, passing = 3, shooting = 2 },
        traits = { "dribbler", "playmaker", "pace_merchant" },
    },
    {
        matchName = "Robert Lewandowski",
        matchAltNames = { "R. Lewandowski", "Lewandowski", "莱万多夫斯基", "莱万", "罗伯特·莱万多夫斯基" },
        potential = 92,
        attrBonus = { shooting = 4, positioning = 3, composure = 3, aerial = 2 },
        traits = { "clinical", "poacher", "aerial_threat" },
    },
    {
        matchName = "Karim Benzema",
        matchAltNames = { "K. Benzema", "Benzema", "本泽马", "卡里姆·本泽马" },
        potential = 92,
        attrBonus = { shooting = 3, composure = 3, vision = 3, positioning = 3 },
        traits = { "clinical", "playmaker", "big_game" },
    },
    {
        matchName = "Kevin De Bruyne",
        matchAltNames = { "K. De Bruyne", "De Bruyne", "德布劳内", "凯文·德布劳内" },
        potential = 93,
        attrBonus = { passing = 4, vision = 4, shooting = 2, decisions = 2 },
        traits = { "playmaker", "dead_ball", "clinical" },
    },
    {
        matchName = "Luka Modrić",
        matchAltNames = { "L. Modrić", "Modric", "莫德里奇", "卢卡·莫德里奇" },
        potential = 91,
        attrBonus = { passing = 3, vision = 3, decisions = 3, composure = 3 },
        traits = { "playmaker", "captain", "big_game" },
    },
    {
        matchName = "Manuel Neuer",
        matchAltNames = { "M. Neuer", "Neuer", "诺伊尔", "曼努埃尔·诺伊尔" },
        potential = 91,
        attrBonus = { reflexes = 4, handling = 3, positioning = 3, speed = 2 },
        traits = { "shot_stopper", "sweeper_keeper", "captain" },
    },

    -- ============ B 级 (潜力 87-90, 加成 +10, 2特性) ============
    {
        matchName = "Toni Kroos",
        matchAltNames = { "T. Kroos", "Kroos", "克罗斯", "托尼·克罗斯" },
        potential = 90,
        attrBonus = { passing = 4, vision = 3, composure = 3 },
        traits = { "playmaker", "dead_ball" },
    },
    {
        matchName = "Luis Suárez",
        matchAltNames = { "L. Suárez", "Luis Suárez", "路易斯·苏亚雷斯" },
        requireLegend = true,  -- 西甲另有同名「路易斯·苏亚雷斯」(哥伦比亚)，仅传奇苏牙可转生
        potential = 89,
        attrBonus = { shooting = 3, positioning = 3, aggression = 2, composure = 2 },
        traits = { "clinical", "poacher" },
    },
    {
        matchName = "Sergio Ramos",
        matchAltNames = { "S. Ramos", "Ramos", "拉莫斯", "塞尔吉奥·拉莫斯" },
        potential = 89,
        attrBonus = { defending = 3, tackling = 3, aerial = 2, leadership = 2 },
        traits = { "brick_wall", "aerial_threat" },
    },
    {
        matchName = "N'Golo Kanté",
        matchAltNames = { "N. Kanté", "Kante", "坎特", "恩戈洛·坎特" },
        potential = 90,
        attrBonus = { tackling = 3, stamina = 3, speed = 2, decisions = 2 },
        traits = { "ball_winner", "engine" },
    },
    {
        matchName = "Gareth Bale",
        matchAltNames = { "G. Bale", "Bale", "贝尔", "加雷斯·贝尔" },
        potential = 88,
        attrBonus = { speed = 3, shooting = 3, strength = 2, dribbling = 2 },
        traits = { "pace_merchant", "clinical" },
    },
    {
        matchName = "Eden Hazard",
        matchAltNames = { "E. Hazard", "Hazard", "阿扎尔", "埃登·阿扎尔" },
        potential = 88,
        attrBonus = { dribbling = 4, agility = 3, passing = 2, vision = 1 },
        traits = { "dribbler", "playmaker" },
    },
    {
        matchName = "Paul Pogba",
        matchAltNames = { "P. Pogba", "Pogba", "博格巴", "保罗·博格巴" },
        potential = 87,
        attrBonus = { passing = 3, strength = 3, vision = 2, shooting = 2 },
        traits = { "playmaker", "powerhouse" },
    },

    -- ============ 新增转生源 (潜力 86-90) ============
    {
        matchName = "Sergio Busquets",
        matchAltNames = { "S. Busquets", "Sergio Busquets Burgos", "Busquets", "布斯克茨", "塞尔吉奥·布斯克茨" },
        requireLegend = true,
        potential = 89,
        attrBonus = { passing = 3, vision = 3, decisions = 2, composure = 2, tackling = 1, defending = 1 },
        traits = { "playmaker", "ball_winner", "captain" },
    },
    {
        matchName = "Gerard Piqué",
        matchAltNames = { "Gerard Pique", "G. Piqué", "G. Pique", "Piqué", "Pique", "皮克", "杰拉德·皮克" },
        potential = 88,
        allowFallbackFirstSeason = true,
        attrBonus = { defending = 3, aerial = 3, passing = 2, composure = 2 },
        traits = { "brick_wall", "aerial_threat" },
    },
    {
        matchName = "Zlatan Ibrahimović",
        matchAltNames = { "Zlatan Ibrahimovic", "Z. Ibrahimović", "Z. Ibrahimovic", "Ibrahimović", "Ibrahimovic", "Zlatan", "伊布", "兹拉坦·伊布拉希莫维奇" },
        potential = 90,
        allowFallbackFirstSeason = true,
        attrBonus = { shooting = 3, strength = 3, aerial = 2, composure = 2 },
        traits = { "clinical", "aerial_threat", "big_game" },
    },
    {
        matchName = "Pepe",
        matchAltNames = { "K. Pepe", "Kepler Pepe", "Kepler Laveran de Lima Ferreira", "佩佩" },
        potential = 87,
        allowFallbackFirstSeason = true,
        attrBonus = { defending = 3, tackling = 3, aggression = 2, aerial = 2 },
        traits = { "brick_wall", "ball_winner" },
    },
    {
        matchName = "Heung-Min Son",
        matchAltNames = { "H. Son", "Son", "Son Heung-min", "Heung Min Son", "孙兴慜", "孙兴民", "孙兴min" },
        potential = 90,
        attrBonus = { speed = 3, shooting = 3, positioning = 2, composure = 2 },
        traits = { "pace_merchant", "clinical", "big_game" },
    },
    {
        matchName = "Zheng Zhi",
        matchAltNames = { "Z. Zheng", "Zheng", "郑智" },
        potential = 86,
        allowFallbackFirstSeason = true,
        attrBonus = { passing = 3, decisions = 3, leadership = 2, teamwork = 2 },
        traits = { "playmaker", "captain" },
    },
}

-- 老档中退役源球员可能已被 Housekeeping 物理删除；此时无法再读取“本人”对象。
-- 用名单内固定身份兜底，保证老档也能补齐全部转生。
local FALLBACK_SOURCE_BY_MATCH_NAME = {
    ["Lionel Messi"] = {
        displayName = "莱昂内尔·梅西", shortName = "梅西", nationality = "AR", position = "RW",
        naturalPositions = {"RW", "CAM", "ST"},
    },
    ["Cristiano Ronaldo"] = {
        displayName = "克里斯蒂亚诺·罗纳尔多", shortName = "罗纳尔多", nationality = "PT", position = "ST",
        naturalPositions = {"ST", "LW"},
    },
    ["Neymar Jr."] = {
        displayName = "内马尔", shortName = "内马尔", nationality = "BR", position = "LW",
        naturalPositions = {"LW", "CAM"},
    },
    ["Robert Lewandowski"] = {
        displayName = "罗伯特·莱万多夫斯基", shortName = "莱万多夫斯基", nationality = "PL", position = "ST",
        naturalPositions = {"ST"},
    },
    ["Karim Benzema"] = {
        displayName = "卡里姆·本泽马", shortName = "本泽马", nationality = "FR", position = "ST",
        naturalPositions = {"ST", "CF"},
    },
    ["Kevin De Bruyne"] = {
        displayName = "凯文·德布劳内", shortName = "德布劳内", nationality = "BE", position = "CM",
        naturalPositions = {"CM", "CAM"},
    },
    ["Luka Modrić"] = {
        displayName = "卢卡·莫德里奇", shortName = "莫德里奇", nationality = "HR", position = "CM",
        naturalPositions = {"CM", "CAM"},
    },
    ["Manuel Neuer"] = {
        displayName = "曼努埃尔·诺伊尔", shortName = "诺伊尔", nationality = "DE", position = "GK",
        naturalPositions = {"GK"},
    },
    ["Toni Kroos"] = {
        displayName = "托尼·克罗斯", shortName = "克罗斯", nationality = "DE", position = "CM",
        naturalPositions = {"CM", "CDM"},
    },
    ["Luis Suárez"] = {
        displayName = "路易斯·苏亚雷斯", shortName = "苏亚雷斯", nationality = "UY", position = "ST",
        naturalPositions = {"ST"},
    },
    ["Sergio Ramos"] = {
        displayName = "塞尔吉奥·拉莫斯", shortName = "拉莫斯", nationality = "ES", position = "CB",
        naturalPositions = {"CB", "RB"},
    },
    ["N'Golo Kanté"] = {
        displayName = "恩戈洛·坎特", shortName = "坎特", nationality = "FR", position = "CDM",
        naturalPositions = {"CDM", "CM"},
    },
    ["Gareth Bale"] = {
        displayName = "加雷斯·贝尔", shortName = "贝尔", nationality = "WAL", position = "RW",
        naturalPositions = {"RW", "LW", "ST"},
    },
    ["Eden Hazard"] = {
        displayName = "埃登·阿扎尔", shortName = "阿扎尔", nationality = "BE", position = "LW",
        naturalPositions = {"LW", "CAM"},
    },
    ["Paul Pogba"] = {
        displayName = "保罗·博格巴", shortName = "博格巴", nationality = "FR", position = "CM",
        naturalPositions = {"CM", "CDM"},
    },
    ["Sergio Busquets"] = {
        displayName = "塞尔吉奥·布斯克茨", shortName = "布斯克茨", nationality = "ES", position = "CDM",
        naturalPositions = {"CDM", "CM"},
    },
    ["Gerard Piqué"] = {
        displayName = "杰拉德·皮克", shortName = "皮克", nationality = "ES", position = "CB",
        naturalPositions = {"CB"},
    },
    ["Zlatan Ibrahimović"] = {
        displayName = "兹拉坦·伊布拉希莫维奇", shortName = "伊布", nationality = "SE", position = "ST",
        naturalPositions = {"ST", "CF"},
    },
    ["Pepe"] = {
        displayName = "佩佩", shortName = "佩佩", nationality = "PT", position = "CB",
        naturalPositions = {"CB"},
    },
    ["Heung-Min Son"] = {
        displayName = "孙兴慜", shortName = "孙兴慜", nationality = "KR", position = "LW",
        naturalPositions = {"LW", "ST", "RW"},
    },
    ["Zheng Zhi"] = {
        displayName = "郑智", shortName = "郑智", nationality = "CHN", position = "CM",
        naturalPositions = {"CM", "CDM"},
    },
}

-- 旧存档补源：这些球员新增前不在自由球员池中，需要在读档 housekeeping 时补入。
local FREE_AGENT_SOURCE_BY_MATCH_NAME = {
    ["Gerard Piqué"] = {
        displayName = "杰拉德·皮克", shortName = "皮克", nationality = "ES", position = "CB",
        naturalPositions = {"CB"}, birthYear = 1987, overall = 79, potential = 79,
        wage = 80000, value = 4500000,
        attributes = {
            speed = 10, stamina = 12, strength = 16, agility = 11, passing = 16,
            shooting = 11, tackling = 16, dribbling = 13, defending = 17,
            positioning = 17, vision = 15, decisions = 17, composure = 18,
            aggression = 14, teamwork = 15, leadership = 16, handling = 4,
            reflexes = 4, aerial = 17,
        },
        traits = {"Stopper", "AerialThreat", "Playmaker"},
    },
    ["Zlatan Ibrahimović"] = {
        displayName = "兹拉坦·伊布拉希莫维奇", shortName = "伊布", nationality = "SE", position = "ST",
        naturalPositions = {"ST", "CF"}, birthYear = 1981, overall = 80, potential = 80,
        wage = 90000, value = 3500000,
        attributes = {
            speed = 10, stamina = 12, strength = 18, agility = 14, passing = 16,
            shooting = 18, tackling = 7, dribbling = 16, defending = 6,
            positioning = 18, vision = 16, decisions = 17, composure = 18,
            aggression = 16, teamwork = 14, leadership = 17, handling = 4,
            reflexes = 4, aerial = 18,
        },
        traits = {"Finisher", "AerialThreat", "Flair", "BigGame"},
    },
    ["Pepe"] = {
        displayName = "佩佩", shortName = "佩佩", nationality = "PT", position = "CB",
        naturalPositions = {"CB"}, birthYear = 1983, overall = 78, potential = 78,
        wage = 70000, value = 3000000,
        attributes = {
            speed = 12, stamina = 14, strength = 17, agility = 12, passing = 13,
            shooting = 8, tackling = 17, dribbling = 11, defending = 17,
            positioning = 17, vision = 12, decisions = 16, composure = 16,
            aggression = 18, teamwork = 15, leadership = 16, handling = 4,
            reflexes = 4, aerial = 17,
        },
        traits = {"Stopper", "BallWinner", "AerialThreat"},
    },
    ["Zheng Zhi"] = {
        displayName = "郑智", shortName = "郑智", nationality = "CHN", position = "CM",
        naturalPositions = {"CM", "CDM"}, birthYear = 1980, overall = 74, potential = 74,
        wage = 30000, value = 1200000,
        attributes = {
            speed = 10, stamina = 15, strength = 14, agility = 13, passing = 16,
            shooting = 14, tackling = 15, dribbling = 14, defending = 15,
            positioning = 16, vision = 16, decisions = 16, composure = 16,
            aggression = 15, teamwork = 17, leadership = 18, handling = 4,
            reflexes = 4, aerial = 13,
        },
        traits = {"Playmaker", "Leader", "Teamwork"},
    },
}

------------------------------------------------------
-- 内部工具
------------------------------------------------------

--- 检查球员名字是否匹配转生名单中的某个条目
---@param player table
---@param entry ReincarnationEntry
---@return boolean
local function nameMatches(player, entry)
    if entry.requireLegend and not player.isLegend then
        return false
    end
    -- 不能用含 nil 的 ipairs：legendName 为空时会截断后续字段
    -- 注意：不含 lastName 单独匹配——如德甲「斯特凡·贝尔」lastName=贝尔，
    -- 会误占加雷斯·贝尔的转生名额（matchAltNames 含「贝尔」）。
    local namesToCheck = {}
    local function addName(name)
        if name and name ~= "" then
            namesToCheck[#namesToCheck + 1] = name
        end
    end
    addName(player.displayName)
    addName(player.legendName)
    addName(player.match_name)
    addName((player.firstName or "") .. " " .. (player.lastName or ""))
    for _, name in ipairs(namesToCheck) do
        if name == entry.matchName then return true end
        for _, alt in ipairs(entry.matchAltNames) do
            if name == alt then return true end
        end
    end
    return false
end

--- 生成转生青训球员的属性
---@param position string
---@param overall number
---@param attrBonus table<string, number>
---@return table
local function generateRebirthAttributes(position, overall, attrBonus)
    local baseVal = math.max(1, math.floor(overall / 7))

    local attrs = {
        speed = baseVal + RandomInt(-1, 2),
        stamina = baseVal + RandomInt(-1, 2),
        strength = baseVal + RandomInt(-1, 2),
        agility = baseVal + RandomInt(-1, 2),
        passing = baseVal + RandomInt(-1, 2),
        shooting = baseVal + RandomInt(-1, 2),
        tackling = baseVal + RandomInt(-1, 2),
        dribbling = baseVal + RandomInt(-1, 2),
        defending = baseVal + RandomInt(-1, 2),
        positioning = baseVal + RandomInt(-1, 2),
        vision = baseVal + RandomInt(-1, 2),
        decisions = baseVal + RandomInt(-1, 2),
        composure = baseVal + RandomInt(-1, 2),
        aggression = baseVal + RandomInt(-1, 2),
        teamwork = baseVal + RandomInt(-1, 2),
        leadership = baseVal + RandomInt(-2, 1),
        aerial = baseVal + RandomInt(-1, 2),
        handling = 1,
        reflexes = 1,
    }

    -- 位置专精（与 YouthManager 一致）
    if position == "GK" then
        attrs.handling = baseVal + RandomInt(2, 5)
        attrs.reflexes = baseVal + RandomInt(2, 5)
        attrs.positioning = attrs.positioning + RandomInt(1, 3)
    elseif position == "CB" then
        attrs.defending = attrs.defending + RandomInt(2, 4)
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.strength = attrs.strength + RandomInt(1, 3)
    elseif position == "LB" or position == "RB" then
        attrs.defending = attrs.defending + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(2, 4)
    elseif position == "CDM" then
        attrs.tackling = attrs.tackling + RandomInt(2, 4)
        attrs.defending = attrs.defending + RandomInt(1, 3)
    elseif position == "CM" or position == "CAM" then
        attrs.passing = attrs.passing + RandomInt(2, 4)
        attrs.vision = attrs.vision + RandomInt(1, 3)
        attrs.dribbling = attrs.dribbling + RandomInt(1, 3)
    elseif position == "LW" or position == "RW" then
        attrs.speed = attrs.speed + RandomInt(2, 4)
        attrs.dribbling = attrs.dribbling + RandomInt(2, 3)
        attrs.agility = attrs.agility + RandomInt(1, 3)
    elseif position == "ST" or position == "CF" then
        attrs.shooting = attrs.shooting + RandomInt(2, 4)
        attrs.composure = attrs.composure + RandomInt(1, 3)
        attrs.speed = attrs.speed + RandomInt(1, 3)
    end

    -- 转生特殊加成（区别于普通青训）
    for attrKey, bonus in pairs(attrBonus) do
        if attrs[attrKey] then
            ---@diagnostic disable-next-line: assign-type-mismatch
            attrs[attrKey] = math.floor(attrs[attrKey] + bonus)
        end
    end

    -- 限制范围
    for k, v in pairs(attrs) do
        attrs[k] = math.max(1, math.min(20, v))
    end

    return attrs
end

--- 该队青训中是否已有转生球员
---@param gameState table
---@param teamId string|number
---@return boolean
local function teamHasReincarnationYouth(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return false end
    for _, youthId in ipairs(team._youthPlayerIds or {}) do
        local player = gameState.players[youthId]
        if player and (player.isReincarnation or player.reincarnationMatchName) then
            return true
        end
    end
    return false
end

--- 转生落位目标队：永不选玩家球队；同一队最多一名转生
---@param gameState table
---@param teamId string|number
---@return boolean
local function isEligibleReincarnationHost(gameState, teamId)
    if gameState.playerTeamId and teamId == gameState.playerTeamId then
        return false
    end
    if teamHasReincarnationYouth(gameState, teamId) then
        return false
    end
    return true
end

--- 从有空余青训名额的球队中随机选一个作为转生目标
---@param gameState table
---@return string|nil teamId
local function pickRandomTeamWithYouthSlot(gameState)
    local teamIds = {}
    for teamId, team in pairs(gameState.teams) do
        if isEligibleReincarnationHost(gameState, teamId) then
            team._youthPlayerIds = team._youthPlayerIds or {}
            if #team._youthPlayerIds < MAX_YOUTH_SQUAD then
                table.insert(teamIds, teamId)
            end
        end
    end
    if #teamIds == 0 then return nil end
    return teamIds[RandomInt(1, #teamIds)]
end

--- 随机挑选一支有青训的球员并返回待替换者
---@param gameState table
---@return string|nil teamId, number|nil youthId
local function pickRandomYouthToReplace(gameState)
    local candidates = {}
    for teamId, team in pairs(gameState.teams) do
        if not isEligibleReincarnationHost(gameState, teamId) then
            goto continue_team
        end
        team._youthPlayerIds = team._youthPlayerIds or {}
        local replaceable = {}
        for _, youthId in ipairs(team._youthPlayerIds) do
            local player = gameState.players[youthId]
            if player and not player.isReincarnation and not player.reincarnationMatchName then
                table.insert(replaceable, youthId)
            end
        end
        if #replaceable > 0 then
            table.insert(candidates, { teamId = teamId, youthIds = replaceable })
        end
        ::continue_team::
    end
    if #candidates == 0 then return nil, nil end
    local picked = candidates[RandomInt(1, #candidates)]
    local youthId = picked.youthIds[RandomInt(1, #picked.youthIds)]
    return picked.teamId, youthId
end

--- 移除被替换的青训球员
---@param gameState table
---@param teamId string|number
---@param youthId number
local function removeReplacedYouth(gameState, teamId, youthId)
    local team = gameState.teams[teamId]
    if not team then return end
    team._youthPlayerIds = team._youthPlayerIds or {}
    for i, yid in ipairs(team._youthPlayerIds) do
        if yid == youthId then
            table.remove(team._youthPlayerIds, i)
            break
        end
    end
    gameState.players[youthId] = nil
end

--- 是否已有转生完成记录
---@param gameState table
---@return boolean
function ReincarnationManager.hasAnyReincarnation(gameState)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}
    for _ in pairs(gameState._reincarnationsDone) do
        return true
    end
    for _, player in pairs(gameState.players or {}) do
        if player.isReincarnation or player.reincarnationMatchName then
            return true
        end
    end
    return false
end

--- 指定名单条目是否已经转生过
---@param gameState table
---@param entry ReincarnationEntry
---@return boolean
function ReincarnationManager.hasReincarnationForEntry(gameState, entry)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}
    local done = gameState._reincarnationsDone[entry.matchName]
    if done then
        if done.playerId and gameState.players[done.playerId] then
            return true
        end
        -- 记录存在但球员已被清理：视为未完成，允许补转生
        ReincarnationManager.markKnownSource(gameState, entry.matchName)
        gameState._reincarnationsDone[entry.matchName] = nil
    end
    for _, player in pairs(gameState.players or {}) do
        if player.reincarnationMatchName == entry.matchName then
            return true
        end
    end
    return false
end

--- 在世界中查找与条目匹配的球员（现役优先，含已退役）
---@param gameState table
---@param entry ReincarnationEntry
---@return table|nil player, boolean retired
function ReincarnationManager.findPlayerForEntry(gameState, entry)
    local retiredCandidate = nil
    for _, player in pairs(gameState.players) do
        if player.isReincarnation then goto continue_player end
        if not nameMatches(player, entry) then goto continue_player end
        if not player.retired then
            return player, false
        end
        retiredCandidate = player
        ::continue_player::
    end
    if retiredCandidate then
        return retiredCandidate, true
    end
    return nil, false
end

--- 源球员是否在有效球队中服役
---@param gameState table
---@param player table|nil
---@return boolean
function ReincarnationManager.isActiveRosterSource(gameState, player)
    if not player or player.retired then return false end
    if not player.teamId then return false end
    local team = gameState.teams and gameState.teams[player.teamId]
    if not team then return false end
    for _, pid in ipairs(team.playerIds or {}) do
        if pid == player.id then return true end
    end
    return false
end

--- 首季末统一转生条件：自由球员 / 无有效球队 / fallback 源；在役名单球员留待自然退役
---@param gameState table
---@param entry ReincarnationEntry
---@return table|nil sourcePlayer
function ReincarnationManager.getFirstSeasonRebirthSource(gameState, entry)
    local player = select(1, ReincarnationManager.findPlayerForEntry(gameState, entry))
    if player then
        if ReincarnationManager.isActiveRosterSource(gameState, player) then
            return nil
        end
        ReincarnationManager.markKnownSource(gameState, entry.matchName)
        return player
    end

    if entry.allowFallbackFirstSeason and FALLBACK_SOURCE_BY_MATCH_NAME[entry.matchName] then
        return ReincarnationManager.createFallbackSource(entry)
    end
    if ReincarnationManager.shouldUseFallbackSource(gameState, entry) then
        return ReincarnationManager.createFallbackSource(entry)
    end
    return nil
end

--- 新档初始化：记录开局赛季，首季末让自由/无队源球员转生
---@param gameState table
function ReincarnationManager.initNewGame(gameState)
    gameState._gameStartSeason = gameState.season
    gameState._reincarnationFirstSeasonEnd = true
end

--- 新档首季末：自由/无有效球队/fallback 源统一转生；在役球员正常等自然退役
---@param gameState table
function ReincarnationManager._maybeForceFirstSeasonRetire(gameState)
    if not gameState._reincarnationFirstSeasonEnd then return end
    if not gameState._gameStartSeason or gameState.season ~= gameState._gameStartSeason then
        return
    end

    gameState._reincarnationFirstSeasonEnd = nil
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if not ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
            local source = ReincarnationManager.getFirstSeasonRebirthSource(gameState, entry)
            if source then
                ReincarnationManager.spawnRebirth(gameState, entry, source)
            end
        end
    end
end

--- 标记该传奇曾在本存档中出现过（用于源球员已被 purge 后的兜底）
---@param gameState table
---@param matchName string
function ReincarnationManager.markKnownSource(gameState, matchName)
    if not matchName or matchName == "" then return end
    gameState._reincarnationKnownSources = gameState._reincarnationKnownSources or {}
    gameState._reincarnationKnownSources[matchName] = true
end

--- 扫描存档，记录出现过的转生源球员（须在 purgeRetiredPlayers 之前调用）
---@param gameState table
function ReincarnationManager.scanAndMarkKnownSources(gameState)
    gameState._reincarnationKnownSources = gameState._reincarnationKnownSources or {}
    local known = gameState._reincarnationKnownSources

    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if known[entry.matchName] then goto continue_entry end

        local player = select(1, ReincarnationManager.findPlayerForEntry(gameState, entry))
        if player then
            known[entry.matchName] = true
            goto continue_entry
        end

        if gameState._reincarnationsDone and gameState._reincarnationsDone[entry.matchName] then
            known[entry.matchName] = true
            goto continue_entry
        end

        for _, record in ipairs(gameState._transferHistory or {}) do
            local pname = record.playerName
            if pname and nameMatches({ displayName = pname, legendName = pname, match_name = pname }, entry) then
                known[entry.matchName] = true
                break
            end
        end
        if known[entry.matchName] then goto continue_entry end

        local transfers = gameState.transfers
        if transfers and type(transfers.history) == "table" then
            for _, record in ipairs(transfers.history) do
                local pname = record.playerName
                if pname and nameMatches({ displayName = pname, legendName = pname, match_name = pname }, entry) then
                    known[entry.matchName] = true
                    break
                end
            end
        end

        ::continue_entry::
    end
end

--- 源球员已被删除时，是否允许用名单身份兜底
---@param gameState table
---@param entry ReincarnationEntry
---@return boolean
function ReincarnationManager.shouldUseFallbackSource(gameState, entry)
    gameState._reincarnationKnownSources = gameState._reincarnationKnownSources or {}
    return gameState._reincarnationKnownSources[entry.matchName] == true
end

--- 为旧存档补齐新增的自由传奇源球员（只补源，不直接转生）
---@param gameState table
function ReincarnationManager.ensureMissingFreeAgentSources(gameState)
    local added = 0
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        local data = FREE_AGENT_SOURCE_BY_MATCH_NAME[entry.matchName]
        if not data then goto continue_entry end
        if ReincarnationManager.hasReincarnationForEntry(gameState, entry) then goto continue_entry end
        local existing = select(1, ReincarnationManager.findPlayerForEntry(gameState, entry))
        if existing then goto continue_entry end

        local player = gameState:addPlayer({
            firstName = data.displayName,
            lastName = data.shortName,
            displayName = data.displayName,
            shortName = data.shortName,
            match_name = entry.matchName,
            legendName = entry.matchName,
            birthYear = data.birthYear,
            nationality = data.nationality,
            position = data.position,
            naturalPositions = data.naturalPositions,
            preferredFoot = "right",
            weakFoot = 3,
            attributes = data.attributes,
            fitness = 75,
            morale = 75,
            condition = 92,
            overall = data.overall,
            potential = data.potential,
            contractEnd = nil,
            wage = data.wage,
            value = data.value,
            teamId = nil,
            squadRole = "first_team",
            traits = data.traits or {},
            isLegend = true,
        })
        if player.calculateOverall then player:calculateOverall() end
        if player.calculateReputation then player:calculateReputation(math.min(900, (data.overall or 70) * 10)) end
        if player.calculateValue then player:calculateValue(gameState.date and gameState.date.year or gameState.season or 2024) end
        ReincarnationManager.markKnownSource(gameState, entry.matchName)
        added = added + 1
        ::continue_entry::
    end
    return added
end

--- 老档读档迁移：名单内未转生且已退役的源球员，立即补转生；未退役的留待自然退役
---@param gameState table
function ReincarnationManager.bootstrapLegacySave(gameState)
    ReincarnationManager.scanAndMarkKnownSources(gameState)
    ReincarnationManager.ensureMissingFreeAgentSources(gameState)

    -- 老档兼容：已退役的立即补转生；已知源已删除时用 fallback；在役/自由球员留待赛季末
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if not ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
            local player, isRetired = ReincarnationManager.findPlayerForEntry(gameState, entry)
            if player and isRetired then
                ReincarnationManager.markKnownSource(gameState, entry.matchName)
                ReincarnationManager.spawnRebirth(gameState, entry, player)
            elseif not player and ReincarnationManager.shouldUseFallbackSource(gameState, entry) then
                local source = ReincarnationManager.createFallbackSource(entry)
                if source then
                    ReincarnationManager.spawnRebirth(gameState, entry, source)
                end
            end
        end
    end
end

--- 旧档源球员已被删除时，用固定身份构造“本人”兜底
---@param entry ReincarnationEntry
---@return table|nil
function ReincarnationManager.createFallbackSource(entry)
    local data = FALLBACK_SOURCE_BY_MATCH_NAME[entry.matchName]
    if not data then return nil end
    return {
        id = nil,
        firstName = data.displayName,
        lastName = data.shortName,
        displayName = data.displayName,
        legendName = entry.matchName,
        match_name = entry.matchName,
        nationality = data.nationality,
        position = data.position,
        naturalPositions = data.naturalPositions,
        retired = true,
    }
end

--- 强制传奇球员退役（首季末新档专用）
---@param gameState table
---@param player table
function ReincarnationManager.forceRetireLegend(gameState, player)
    player.retired = true
    player.retiredSeason = gameState.season
    local team = player.teamId and gameState.teams[player.teamId]
    if team then
        for i, pid in ipairs(team.playerIds) do
            if pid == player.id then
                table.remove(team.playerIds, i)
                break
            end
        end
        team._youthPlayerIds = team._youthPlayerIds or {}
        for i, yid in ipairs(team._youthPlayerIds) do
            if yid == player.id then
                table.remove(team._youthPlayerIds, i)
                break
            end
        end
    end
    player.teamId = nil
end

--- 生成转生青训并替换随机青训名额
---@param gameState table
---@param entry ReincarnationEntry
---@param sourcePlayer table
---@return boolean spawned
function ReincarnationManager.spawnRebirth(gameState, entry, sourcePlayer)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}
    if ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
        return false
    end

    local targetTeamId, replacedYouthId = pickRandomYouthToReplace(gameState)
    if not targetTeamId then
        targetTeamId = pickRandomTeamWithYouthSlot(gameState)
    end
    if not targetTeamId then
        -- 各队青训已满：仍强制落位到随机 AI 球队（必要时略超编，永不落玩家队）
        local teamIds = {}
        for teamId in pairs(gameState.teams or {}) do
            if isEligibleReincarnationHost(gameState, teamId) then
                teamIds[#teamIds + 1] = teamId
            end
        end
        if #teamIds == 0 then
            print(string.format(
                "[ReincarnationManager] 转生跳过 %s：无可用 AI 球队",
                sourcePlayer.displayName or entry.matchName))
            return false
        end
        targetTeamId = teamIds[RandomInt(1, #teamIds)]
    end

    if not targetTeamId then return false end

    if replacedYouthId then
        removeReplacedYouth(gameState, targetTeamId, replacedYouthId)
    end

    local team = gameState.teams[targetTeamId]
    if not team then return false end

    local rebirthAge = 16
    local birthYear = gameState.date.year - rebirthAge
    local overall = RandomInt(70, 78)
    local position = sourcePlayer.position or "CM"
    local attributes = generateRebirthAttributes(position, overall, entry.attrBonus)
    local actualOverall = Player.calculateOverallFromAttrs(position, attributes)
    if actualOverall < 70 then actualOverall = 70 end

    local playerData = {
        firstName = sourcePlayer.firstName,
        lastName = sourcePlayer.lastName,
        displayName = sourcePlayer.displayName,
        nationality = sourcePlayer.nationality,
        birthYear = birthYear,
        position = position,
        naturalPositions = sourcePlayer.naturalPositions,
        attributes = attributes,
        potential = entry.potential,
        overall = actualOverall,
        wage = 500,
        isYouth = true,
        teamId = targetTeamId,
        squadRole = "youth",
        contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
        traits = entry.traits or {},
        innateTraits = entry.traits or nil,
    }

    local newPlayer = gameState:addPlayer(playerData)
    newPlayer.teamId = targetTeamId
    newPlayer.isReincarnation = true
    newPlayer.reincarnationMatchName = entry.matchName
    -- 保留原名/数据源字段，便于 UI 立绘与球员搜索
    newPlayer.legendName = sourcePlayer.legendName or sourcePlayer.match_name or entry.matchName
    if sourcePlayer.match_name then
        newPlayer.match_name = sourcePlayer.match_name
    end
    newPlayer.paRating = PotentialSystem.rawToRating(newPlayer.potential)
    newPlayer.actualPotential = PotentialSystem.generateActualPotential(
        newPlayer.paRating, (gameState.potentialSeed or 0) + newPlayer.id * 7919)

    team._youthPlayerIds = team._youthPlayerIds or {}
    table.insert(team._youthPlayerIds, newPlayer.id)

    ReincarnationManager.markKnownSource(gameState, entry.matchName)
    gameState._reincarnationsDone[entry.matchName] = {
        season = gameState.season,
        playerId = newPlayer.id,
        teamId = targetTeamId,
        sourcePlayerId = sourcePlayer.id,
        replacedYouthId = replacedYouthId,
    }

    local displayLabel = sourcePlayer.displayName or entry.matchName
    print(string.format("[ReincarnationManager] 转生触发: %s → 16岁青训，加入 %s",
        displayLabel, team.name or targetTeamId))
    return true
end

------------------------------------------------------
-- 核心逻辑
------------------------------------------------------

--- 处理转生：在赛季结算退役处理之后调用
--- 名单内每个源球员独立转生；必须用源球员本人姓名/位置/国籍重生。
---@param gameState table
function ReincarnationManager.processReincarnations(gameState)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}

    ReincarnationManager._maybeForceFirstSeasonRetire(gameState)

    local rebirthCount = 0
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if not ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
            local player, isRetired = ReincarnationManager.findPlayerForEntry(gameState, entry)
            if player and isRetired and player.retiredSeason == gameState.season then
                if ReincarnationManager.spawnRebirth(gameState, entry, player) then
                    rebirthCount = rebirthCount + 1
                end
            end
        end
    end

    if rebirthCount > 0 then
        print(string.format("[ReincarnationManager] 本赛季共 %d 名传奇球员转生", rebirthCount))
    end
end

-- 测试用：暴露名字匹配逻辑
ReincarnationManager._nameMatches = nameMatches

return ReincarnationManager
