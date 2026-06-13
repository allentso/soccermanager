-- systems/reincarnation_manager.lua
-- 转生机制：退役传奇球员以青训新星身份重新出现在随机球队

local Constants = require("scripts/app/constants")
local PotentialSystem = require("scripts/systems/potential_system")
local Player = require("scripts/domain/player")

local ReincarnationManager = {}

------------------------------------------------------
-- 转生名单：只有名单中的球员退役后才会触发转生
-- 每个条目包含：匹配信息 + 转生后的青训属性模板
------------------------------------------------------

---@class ReincarnationEntry
---@field matchName string 用于匹配退役球员的 displayName（模糊匹配）
---@field matchAltNames string[] 备选名字（兼容不同数据源的拼写）
---@field rebirthFirstName string 转生后名字
---@field rebirthLastName string 转生后姓氏
---@field rebirthDisplayName string 转生后显示名
---@field nationality string 国籍（继承）
---@field position string 位置（继承）
---@field potential number 转生后潜力值（极高）
---@field attrBonus table<string, number> 位置专精额外加成

---@type ReincarnationEntry[]
ReincarnationManager.REINCARNATION_LIST = {
    {
        matchName = "Lionel Messi",
        matchAltNames = {"L. Messi", "Messi", "梅西"},
        rebirthFirstName = "里奥",
        rebirthLastName = "梅西尼",
        rebirthDisplayName = "里奥·梅西尼",
        nationality = "Argentina",
        position = "RW",
        potential = 96,
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
        matchAltNames = {"C. Ronaldo", "CR7", "Ronaldo", "C罗"},
        rebirthFirstName = "克里斯",
        rebirthLastName = "罗纳尔迪尼奥",
        rebirthDisplayName = "克里斯·罗纳尔迪尼奥",
        nationality = "Portugal",
        position = "ST",
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
    local pName = player.displayName or ""
    if pName == entry.matchName then return true end
    for _, alt in ipairs(entry.matchAltNames) do
        if pName == alt then return true end
    end
    -- 也检查 firstName + lastName 组合
    local fullName = (player.firstName or "") .. " " .. (player.lastName or "")
    if fullName == entry.matchName then return true end
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

--- 从所有球队中随机选一个作为转生目标
---@param gameState table
---@return string|nil teamId
local function pickRandomTeam(gameState)
    local teamIds = {}
    for teamId, _ in pairs(gameState.teams) do
        table.insert(teamIds, teamId)
    end
    if #teamIds == 0 then return nil end
    return teamIds[RandomInt(1, #teamIds)]
end

------------------------------------------------------
-- 核心逻辑
------------------------------------------------------

--- 处理转生：在赛季结算退役处理之后调用
--- 检查刚退役的传奇球员，若匹配转生名单则生成对应青训新星
---@param gameState table
function ReincarnationManager.processReincarnations(gameState)
    -- 记录本次已触发的转生（避免重复）
    gameState._reincarnationsDone = gameState._reincarnationsDone or {}

    local rebirthCount = 0

    for _, entry in ipairs(ReincarnationManager.REINCARNATION_LIST) do
        -- 如果该条目已经转生过，跳过
        if gameState._reincarnationsDone[entry.matchName] then
            goto continue_entry
        end

        -- 在所有球员中查找：已退役 + 名字匹配 + 本赛季退役
        local foundRetired = false
        for _, player in pairs(gameState.players) do
            if player.retired and player.retiredSeason == gameState.season then
                if nameMatches(player, entry) then
                    foundRetired = true
                    break
                end
            end
        end

        if not foundRetired then
            goto continue_entry
        end

        -- 触发转生：在随机球队生成青训新星
        local targetTeamId = pickRandomTeam(gameState)
        if not targetTeamId then
            goto continue_entry
        end

        local team = gameState.teams[targetTeamId]
        if not team then
            goto continue_entry
        end

        -- 生成转生球员数据
        local rebirthAge = 16
        local birthYear = gameState.date.year - rebirthAge
        local overall = RandomInt(42, 52)  -- 起步较低，但潜力极高
        local attributes = generateRebirthAttributes(entry.position, overall, entry.attrBonus)
        local actualOverall = Player.calculateOverallFromAttrs(entry.position, attributes)
        if actualOverall < 40 then actualOverall = 40 end

        local playerData = {
            firstName = entry.rebirthFirstName,
            lastName = entry.rebirthLastName,
            displayName = entry.rebirthDisplayName,
            nationality = entry.nationality,
            birthYear = birthYear,
            position = entry.position,
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

        -- 初始化潜力评级
        newPlayer.paRating = PotentialSystem.rawToRating(newPlayer.potential)
        newPlayer.actualPotential = PotentialSystem.generateActualPotential(
            newPlayer.paRating, (gameState.potentialSeed or 0) + newPlayer.id * 7919)

        -- 加入青训队
        team._youthPlayerIds = team._youthPlayerIds or {}
        table.insert(team._youthPlayerIds, newPlayer.id)

        -- 标记已转生
        gameState._reincarnationsDone[entry.matchName] = {
            season = gameState.season,
            playerId = newPlayer.id,
            teamId = targetTeamId,
        }

        -- 发送全局新闻
        gameState:sendMessage({
            category = "transfer",
            title = "天才新星出现",
            body = string.format(
                "%s 的青训营中出现了一名天赋异禀的少年 %s（%s，%d岁），球探认为他有着不可思议的潜力！",
                team.name or "某球队",
                entry.rebirthDisplayName,
                entry.position,
                rebirthAge
            ),
            priority = "high",
        })

        rebirthCount = rebirthCount + 1
        print(string.format("[ReincarnationManager] 转生触发: %s → %s，加入 %s 青训",
            entry.matchName, entry.rebirthDisplayName, team.name or targetTeamId))

        ::continue_entry::
    end

    if rebirthCount > 0 then
        print(string.format("[ReincarnationManager] 本赛季共 %d 名传奇球员转生", rebirthCount))
    end
end

return ReincarnationManager
