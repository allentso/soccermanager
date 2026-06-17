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
    if gameState._reincarnationsDone[entry.matchName] then
        return true
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

--- 新档初始化：记录开局赛季，首季末让名单内所有存在的传奇转生
---@param gameState table
function ReincarnationManager.initNewGame(gameState)
    gameState._gameStartSeason = gameState.season
    gameState._reincarnationFirstSeasonEnd = true
end

--- 新档首季末：强制退役名单内所有未转生的源球员，供本赛季转生循环匹配
---@param gameState table
function ReincarnationManager._maybeForceFirstSeasonRetire(gameState)
    if not gameState._reincarnationFirstSeasonEnd then return end
    if not gameState._gameStartSeason or gameState.season ~= gameState._gameStartSeason then
        return
    end

    gameState._reincarnationFirstSeasonEnd = nil
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if not ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
            local player = select(1, ReincarnationManager.findPlayerForEntry(gameState, entry))
            if player then
                ReincarnationManager.forceRetireLegend(gameState, player)
            end
        end
    end
end

--- 老档读档迁移：名单内未转生且已退役的源球员，立即补转生；未退役的留待自然退役
---@param gameState table
function ReincarnationManager.bootstrapLegacySave(gameState)
    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if not ReincarnationManager.hasReincarnationForEntry(gameState, entry) then
            local player, isRetired = ReincarnationManager.findPlayerForEntry(gameState, entry)
            if player and isRetired then
                ReincarnationManager.spawnRebirth(gameState, entry, player)
            elseif not player then
                local fallback = ReincarnationManager.createFallbackSource(entry)
                if fallback then
                    ReincarnationManager.spawnRebirth(gameState, entry, fallback)
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
