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

--- 从有空余青训名额的球队中随机选一个作为转生目标
---@param gameState table
---@return string|nil teamId
local function pickRandomTeamWithYouthSlot(gameState)
    local teamIds = {}
    for teamId, team in pairs(gameState.teams) do
        team._youthPlayerIds = team._youthPlayerIds or {}
        if #team._youthPlayerIds < MAX_YOUTH_SQUAD then
            table.insert(teamIds, teamId)
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
        team._youthPlayerIds = team._youthPlayerIds or {}
        if #team._youthPlayerIds > 0 then
            table.insert(candidates, teamId)
        end
    end
    if #candidates == 0 then return nil, nil end
    local teamId = candidates[RandomInt(1, #candidates)]
    local team = gameState.teams[teamId]
    local youthIds = team._youthPlayerIds
    local youthId = youthIds[RandomInt(1, #youthIds)]
    return teamId, youthId
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

--- 根据 matchName 查找转生名单条目
---@param matchName string
---@return ReincarnationEntry|nil
local function findEntryByMatchName(matchName)
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if entry.matchName == matchName then return entry end
    end
    return nil
end

--- 是否已有转生完成记录
---@param gameState table
---@return boolean
function ReincarnationManager.hasAnyReincarnation(gameState)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}
    for _ in pairs(gameState._reincarnationsDone) do
        return true
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

--- 选取本存档的转生目标（世界中存在的传奇之一）
---@param gameState table
---@return ReincarnationEntry|nil
function ReincarnationManager.pickTargetEntry(gameState)
    local available = {}
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        local player = select(1, ReincarnationManager.findPlayerForEntry(gameState, entry))
        if player then
            table.insert(available, entry)
        end
    end
    if #available == 0 then return nil end
    return available[RandomInt(1, #available)]
end

--- 确保存档已分配转生目标
---@param gameState table
---@return ReincarnationEntry|nil
function ReincarnationManager.ensureTarget(gameState)
    if ReincarnationManager.hasAnyReincarnation(gameState) then return nil end
    if gameState._reincarnationTarget then
        return findEntryByMatchName(gameState._reincarnationTarget)
    end
    local entry = ReincarnationManager.pickTargetEntry(gameState)
    if entry then
        gameState._reincarnationTarget = entry.matchName
    end
    return entry
end

--- 新档初始化：记录开局赛季，首季末强制转生
---@param gameState table
function ReincarnationManager.initNewGame(gameState)
    if ReincarnationManager.hasAnyReincarnation(gameState) then return end
    gameState._gameStartSeason = gameState.season
    gameState._reincarnationFirstSeasonEnd = true
    ReincarnationManager.ensureTarget(gameState)
end

--- 老档读档迁移：尚无转生时补设目标；目标已退役则立即转生
---@param gameState table
function ReincarnationManager.bootstrapLegacySave(gameState)
    if ReincarnationManager.hasAnyReincarnation(gameState) then return end
    local entry = ReincarnationManager.ensureTarget(gameState)
    if not entry then return end

    local player, isRetired = ReincarnationManager.findPlayerForEntry(gameState, entry)
    if not player then return end
    if isRetired then
        ReincarnationManager.spawnRebirth(gameState, entry, player)
    end
end

--- 强制传奇球员退役（首季末新档专用）
---@param gameState table
---@param player table
function ReincarnationManager.forceRetireLegend(gameState, player)
    if player.retired then return end
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
    if gameState._reincarnationsDone[entry.matchName] then
        return false
    end

    local targetTeamId, replacedYouthId = pickRandomYouthToReplace(gameState)
    if not targetTeamId then
        targetTeamId = pickRandomTeamWithYouthSlot(gameState)
    end
    if not targetTeamId then
        print(string.format(
            "[ReincarnationManager] 转生跳过 %s：无可用青训名额",
            sourcePlayer.displayName or entry.matchName))
        return false
    end

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
    newPlayer.paRating = PotentialSystem.rawToRating(newPlayer.potential)
    newPlayer.actualPotential = PotentialSystem.generateActualPotential(
        newPlayer.paRating, (gameState.potentialSeed or 0) + newPlayer.id * 7919)

    team._youthPlayerIds = team._youthPlayerIds or {}
    table.insert(team._youthPlayerIds, newPlayer.id)

    gameState._reincarnationsDone[entry.matchName] = {
        season = gameState.season,
        playerId = newPlayer.id,
        teamId = targetTeamId,
        sourcePlayerId = sourcePlayer.id,
        replacedYouthId = replacedYouthId,
    }

    print(string.format("[ReincarnationManager] 转生触发: %s → 16岁青训，加入 %s",
        sourcePlayer.displayName or entry.matchName, team.name or targetTeamId))
    return true
end

------------------------------------------------------
-- 核心逻辑
------------------------------------------------------

--- 处理转生：在赛季结算退役处理之后调用
---@param gameState table
function ReincarnationManager.processReincarnations(gameState)
    if ReincarnationManager.hasAnyReincarnation(gameState) then return end

    local entry = ReincarnationManager.ensureTarget(gameState)
    if not entry then return end

    local player, isRetired = ReincarnationManager.findPlayerForEntry(gameState, entry)
    if not player then return end

    -- 新档：开局赛季结束时强制退役并转生
    if gameState._reincarnationFirstSeasonEnd
        and gameState._gameStartSeason
        and gameState.season == gameState._gameStartSeason
        and not isRetired then
        ReincarnationManager.forceRetireLegend(gameState, player)
        isRetired = true
        gameState._reincarnationFirstSeasonEnd = nil
    end

    if not isRetired then return end

    ReincarnationManager.spawnRebirth(gameState, entry, player)
end

-- 测试用：暴露名字匹配逻辑
ReincarnationManager._nameMatches = nameMatches

return ReincarnationManager
