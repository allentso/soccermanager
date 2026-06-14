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
---@field potential number 转生后潜力值
---@field attrBonus table<string, number> 位置专精额外加成

---@type ReincarnationEntry[]
ReincarnationManager.REINCARNATION_LIST = {
    {
        matchName = "Lionel Messi",
        matchAltNames = {
            "L. Messi", "Messi", "梅西", "莱昂内尔·梅西",
        },
        potential = 99,
        attrBonus = {
            dribbling = 4,
            vision = 3,
            agility = 3,
            passing = 2,
            shooting = 2,
        },
    },
    {
        matchName = "Cristiano Ronaldo",
        matchAltNames = {
            "C. Ronaldo", "CR7", "C罗",
            "克里斯蒂亚诺·罗纳尔多", "罗纳尔多",
        },
        potential = 96,
        attrBonus = {
            shooting = 4,
            speed = 3,
            strength = 3,
            aerial = 2,
            composure = 2,
        },
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
    local namesToCheck = {
        player.displayName,
        player.legendName,
        player.lastName,
        (player.firstName or "") .. " " .. (player.lastName or ""),
    }
    for _, name in ipairs(namesToCheck) do
        if name and name ~= "" then
            if name == entry.matchName then return true end
            for _, alt in ipairs(entry.matchAltNames) do
                if name == alt then return true end
            end
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
local function pickRandomTeam(gameState)
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

------------------------------------------------------
-- 核心逻辑
------------------------------------------------------

--- 处理转生：在赛季结算退役处理之后调用
---@param gameState table
function ReincarnationManager.processReincarnations(gameState)
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}

    local rebirthCount = 0

    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        if gameState._reincarnationsDone[entry.matchName] then
            goto continue_entry
        end

        local retiredPlayer = nil
        for _, player in pairs(gameState.players) do
            if player.retired and player.retiredSeason == gameState.season then
                if nameMatches(player, entry) then
                    retiredPlayer = player
                    break
                end
            end
        end

        if not retiredPlayer then
            goto continue_entry
        end

        local targetTeamId = pickRandomTeam(gameState)
        if not targetTeamId then
            print(string.format(
                "[ReincarnationManager] 转生跳过 %s：所有球队青训名额已满",
                retiredPlayer.displayName or entry.matchName))
            goto continue_entry
        end

        local team = gameState.teams[targetTeamId]
        if not team then
            goto continue_entry
        end

        local rebirthAge = 16
        local birthYear = gameState.date.year - rebirthAge
        local overall = RandomInt(70, 78)
        local position = retiredPlayer.position or "CM"
        local attributes = generateRebirthAttributes(position, overall, entry.attrBonus)
        local actualOverall = Player.calculateOverallFromAttrs(position, attributes)
        if actualOverall < 70 then actualOverall = 70 end

        local playerData = {
            firstName = retiredPlayer.firstName,
            lastName = retiredPlayer.lastName,
            displayName = retiredPlayer.displayName,
            nationality = retiredPlayer.nationality,
            birthYear = birthYear,
            position = position,
            naturalPositions = retiredPlayer.naturalPositions,
            attributes = attributes,
            potential = entry.potential,
            overall = actualOverall,
            wage = 500,
            isYouth = true,
            teamId = targetTeamId,
            squadRole = "youth",
            contractEnd = {year = gameState.date.year + 3, month = 6, day = 30},
        }

        local newPlayer = gameState:addPlayer(playerData)
        newPlayer.teamId = targetTeamId

        -- 转生标记（用于立绘展示和 UI 识别）
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
            sourcePlayerId = retiredPlayer.id,
        }

        rebirthCount = rebirthCount + 1
        print(string.format("[ReincarnationManager] 转生触发: %s → 16岁青训，加入 %s",
            retiredPlayer.displayName or entry.matchName, team.name or targetTeamId))

        ::continue_entry::
    end

    if rebirthCount > 0 then
        print(string.format("[ReincarnationManager] 本赛季共 %d 名传奇球员转生", rebirthCount))
    end
end

-- 测试用：暴露名字匹配逻辑
ReincarnationManager._nameMatches = nameMatches

return ReincarnationManager
