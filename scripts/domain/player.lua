-- domain/player.lua
-- 球员数据模型

local Constants = require("scripts/app/constants")

local Player = {}
Player.__index = Player

function Player.new(data)
    local self = setmetatable({}, Player)
    -- 身份
    self.id = data.id or 0
    self.firstName = data.firstName or ""
    self.lastName = data.lastName or ""
    self.displayName = data.displayName or (self.firstName .. " " .. self.lastName)
    self.birthYear = data.birthYear or 2000
    self.nationality = data.nationality or "ENG"

    -- 位置
    self.position = data.position or "CM"
    self.naturalPositions = data.naturalPositions or {self.position}

    -- 脚法
    self.preferredFoot = data.preferredFoot or "right"
    self.weakFoot = data.weakFoot or 2  -- 1-5

    -- 核心属性 (1-20)
    self.attributes = data.attributes or {}
    self.attributes.speed = self.attributes.speed or 10
    self.attributes.stamina = self.attributes.stamina or 10
    self.attributes.strength = self.attributes.strength or 10
    self.attributes.agility = self.attributes.agility or 10
    self.attributes.passing = self.attributes.passing or 10
    self.attributes.shooting = self.attributes.shooting or 10
    self.attributes.tackling = self.attributes.tackling or 10
    self.attributes.dribbling = self.attributes.dribbling or 10
    self.attributes.defending = self.attributes.defending or 10
    self.attributes.positioning = self.attributes.positioning or 10
    self.attributes.vision = self.attributes.vision or 10
    self.attributes.decisions = self.attributes.decisions or 10
    self.attributes.composure = self.attributes.composure or 10
    self.attributes.aggression = self.attributes.aggression or 10
    self.attributes.teamwork = self.attributes.teamwork or 10
    self.attributes.leadership = self.attributes.leadership or 10
    self.attributes.handling = self.attributes.handling or 5  -- GK
    self.attributes.reflexes = self.attributes.reflexes or 5  -- GK
    self.attributes.aerial = self.attributes.aerial or 10

    -- 动态状态
    self.fitness = data.fitness or Constants.FITNESS_DEFAULT
    self.morale = data.morale or Constants.MORALE_DEFAULT
    self.condition = data.condition or 100  -- 长期体能
    self.injured = data.injured or false
    self.injuryDays = data.injuryDays or 0
    self.retired = data.retired or false

    -- 士气核心（Team Talk 系统扩展）
    self.morale_core = data.morale_core or {
        manager_trust = 50,         -- 对教练信任度 0-100
        unresolved_issue = nil,     -- 当前未解决的不满（string|nil）
        recent_treatment = nil,     -- 最近待遇变化: "positive"|"negative"|nil
        last_talk_day = 0,          -- 上次被训话的游戏日（防spam）
        talk_fatigue = 0,           -- 训话疲劳度 0-5（递减回报）
    }

    -- 评分
    self.overall = data.overall or 50
    self.potential = data.potential or 60

    -- 合同
    self.contractEnd = data.contractEnd or nil  -- {year, month}
    self.wage = data.wage or 1000
    self.value = data.value or 100000
    self.releaseClause = data.releaseClause or nil

    -- 球队归属
    self.teamId = data.teamId or nil
    -- 阵容角色: "key"=绝对主力, "rotation"=轮换球员, "squad"=阵容球员, "youth"=青年球员, "loaned"=租借
    self.squadRole = data.squadRole or "rotation"

    -- 职业历史 (每赛季记录)
    self.careerHistory = data.careerHistory or {}

    -- 赛季统计
    self.seasonStats = data.seasonStats or {
        appearances = 0,
        goals = 0,
        assists = 0,
        yellowCards = 0,
        redCards = 0,
        avgRating = 0,
        cleanSheets = 0
    }

    -- 训练
    self.trainingFocus = data.trainingFocus or nil

    -- 转会
    self.listedForSale = data.listedForSale or false
    self.listedForLoan = data.listedForLoan or false

    -- 球员特性标签
    self.traits = data.traits or {}

    return self
end

-- 计算当前年龄
function Player:getAge(currentYear)
    return currentYear - self.birthYear
end

-- 计算综合能力（全属性基础 + 位置核心属性加成）
-- 设计思路：
-- 1. baseScore: 所有17项属性的均值（体现球员综合素质）
-- 2. posScore: 位置核心属性的加权均值（体现位置适配度）
-- 3. 混合: baseScore * 25% + posScore * 75%（位置适配更重要，综合素质兜底）
-- 4. 分段线性映射到OVR（低段平缓、中段陡峭、高段衰减）
function Player:calculateOverall()
    local pos = self.position
    local a = self.attributes

    -- 1. 全属性基础分
    local allAttrs
    if pos == "GK" then
        allAttrs = {
            "handling", "reflexes", "positioning", "aerial",
            "composure", "decisions", "agility", "strength", "speed",
        }
    else
        allAttrs = {
            "speed", "stamina", "strength", "agility",
            "passing", "shooting", "tackling", "dribbling", "defending",
            "positioning", "vision", "decisions", "composure",
            "aggression", "teamwork", "leadership", "aerial",
        }
    end

    local baseSum = 0
    local baseCount = 0
    for _, attr in ipairs(allAttrs) do
        baseSum = baseSum + (a[attr] or 10)
        baseCount = baseCount + 1
    end
    local baseScore = baseSum / baseCount

    -- 2. 位置核心属性加权分（每个位置6-8个核心属性）
    local posWeights

    if pos == "GK" then
        posWeights = {
            handling = 3.0, reflexes = 3.0, positioning = 2.0,
            aerial = 1.5, composure = 1.0, decisions = 0.5,
        }
    elseif pos == "CB" then
        posWeights = {
            defending = 2.5, tackling = 2.0, aerial = 2.0,
            strength = 1.5, composure = 1.5, leadership = 1.5, decisions = 1.0,
        }
    elseif pos == "LB" or pos == "RB" then
        posWeights = {
            speed = 2.0, passing = 2.0, defending = 1.5,
            tackling = 1.5, stamina = 1.5, dribbling = 1.0, vision = 1.0, positioning = 0.5,
        }
    elseif pos == "CDM" then
        posWeights = {
            tackling = 2.5, defending = 2.0, passing = 2.0,
            positioning = 1.5, stamina = 1.5, strength = 1.0, decisions = 0.5,
        }
    elseif pos == "CM" then
        posWeights = {
            passing = 2.5, vision = 2.0, dribbling = 2.0,
            stamina = 2.0, shooting = 1.5, decisions = 1.5, composure = 1.0,
        }
    elseif pos == "CAM" then
        posWeights = {
            vision = 2.5, dribbling = 2.5, passing = 2.0,
            shooting = 2.0, composure = 1.5, decisions = 1.0, agility = 0.5,
        }
    elseif pos == "LM" or pos == "RM" then
        posWeights = {
            speed = 2.0, dribbling = 2.0, passing = 2.0,
            stamina = 2.0, agility = 1.5, shooting = 1.0, vision = 1.0,
        }
    elseif pos == "LW" or pos == "RW" then
        posWeights = {
            dribbling = 3.0, agility = 2.0, shooting = 2.0,
            speed = 1.5, passing = 1.5, composure = 1.0, vision = 1.0,
        }
    elseif pos == "ST" then
        posWeights = {
            shooting = 3.0, composure = 2.5, speed = 2.0,
            positioning = 1.5, dribbling = 1.0, strength = 1.0, aerial = 0.5,
        }
    elseif pos == "CF" then
        posWeights = {
            shooting = 2.5, composure = 2.0, dribbling = 2.0,
            vision = 1.5, passing = 1.5, speed = 1.0, positioning = 1.0,
        }
    else
        posWeights = {
            passing = 1.5, shooting = 1.5, dribbling = 1.5, defending = 1.0,
            speed = 1.0, stamina = 1.0, decisions = 1.0,
        }
    end

    local posSum = 0
    local posTotalW = 0
    for attr, w in pairs(posWeights) do
        posSum = posSum + (a[attr] or 10) * w
        posTotalW = posTotalW + w
    end
    local posScore = posSum / posTotalW

    -- 3. 混合: 基础40% + 位置60%（全属性均衡占比高，弱项惩罚显著）
    local finalScore = baseScore * 0.40 + posScore * 0.60

    -- 4. 分段线性映射到OVR
    -- 校准点: ~12.5→73(普通), ~14.5→83(优秀), ~15.5→89(顶级), ~16.5→93(世界级)
    local ovrRaw
    if finalScore <= 13 then
        ovrRaw = finalScore * 5.0 + 8
    elseif finalScore <= 15.5 then
        -- 13→73, 15.5→89.25: 斜率6.5（核心区间拉开差距）
        ovrRaw = 73 + (finalScore - 13) * 6.5
    else
        -- 15.5→89.25起, 斜率4.5（防止超高分溢出）
        ovrRaw = 89.25 + (finalScore - 15.5) * 4.5
    end

    local overall = math.floor(ovrRaw)
    overall = math.max(Constants.ABILITY_MIN, math.min(Constants.ABILITY_MAX, overall))
    self.overall = overall
    return overall
end

-- 计算市场价值（指数模型，对齐现实：OVR90≈200M, OVR80≈25M, OVR70≈3M）
function Player:calculateValue(currentYear)
    local age = self:getAge(currentYear)
    local ovr = self.overall

    -- 指数公式: value = C * D^ovr
    -- 校准: OVR90→200M, OVR70→3M
    local D = 1.2337  -- (200M/3M)^(1/20)
    local C = 1.24    -- 3M / D^70
    local base = C * (D ^ ovr)

    -- 年龄修正（黄金期23-27加成，老将大幅贬值）
    local ageMult
    if age <= 20 then
        ageMult = 0.5
    elseif age <= 22 then
        ageMult = 0.7 + (age - 20) * 0.15  -- 20→0.7, 22→1.0
    elseif age <= 25 then
        ageMult = 1.0 + (age - 22) * 0.067  -- 22→1.0, 25→1.2
    elseif age <= 27 then
        ageMult = 1.2 - (age - 25) * 0.1    -- 25→1.2, 27→1.0
    elseif age <= 29 then
        ageMult = 1.0 - (age - 27) * 0.125  -- 27→1.0, 29→0.75
    elseif age <= 31 then
        ageMult = 0.75 - (age - 29) * 0.125 -- 29→0.75, 31→0.5
    elseif age <= 33 then
        ageMult = 0.5 - (age - 31) * 0.1    -- 31→0.5, 33→0.3
    else
        ageMult = math.max(0.1, 0.3 - (age - 33) * 0.075) -- 33→0.3, 35+→0.15
    end
    base = base * ageMult

    -- 潜力修正（年轻高潜力球员溢价）
    if self.potential > ovr then
        local potGap = self.potential - ovr
        local potMult = 1.0 + potGap * 0.03  -- 每1点潜力差+3%
        base = base * potMult
    end

    -- 取整到万级（10000）
    self.value = math.floor(base / 10000) * 10000
    -- 最低值50万
    if self.value < 500000 then self.value = 500000 end
    return self.value
end

-- 获取位置中文名
function Player:getPositionName()
    return Constants.POSITION_NAMES[self.position] or self.position
end

------------------------------------------------------
-- 球员特性系统（基于属性自动计算）
------------------------------------------------------

-- 特性定义表：每个特性对应计算规则
Player.TRAIT_DEFINITIONS = {
    -- 速度类
    {id = "pace_merchant", name = "飞毛腿", desc = "极快的跑动速度",
        check = function(a) return a.speed >= 17 and a.agility >= 14 end},
    -- 力量类
    {id = "powerhouse", name = "力量怪兽", desc = "身体对抗极强",
        check = function(a) return a.strength >= 17 and a.aggression >= 14 end},
    -- 技术类
    {id = "playmaker", name = "组织核心", desc = "出色的传球视野",
        check = function(a) return a.passing >= 16 and a.vision >= 16 and a.decisions >= 14 end},
    {id = "dribbler", name = "盘带大师", desc = "突破能力极强",
        check = function(a) return a.dribbling >= 17 and a.agility >= 15 end},
    {id = "dead_ball", name = "定位球专家", desc = "精准的任意球/角球",
        check = function(a) return a.passing >= 16 and a.shooting >= 15 and a.composure >= 14 end},
    -- 射门类
    {id = "clinical", name = "临门一脚", desc = "射门极为精准",
        check = function(a) return a.shooting >= 17 and a.composure >= 15 end},
    {id = "long_shot", name = "远射威胁", desc = "远射能力出色",
        check = function(a) return a.shooting >= 16 and a.strength >= 13 end},
    {id = "poacher", name = "禁区猎手", desc = "嗅觉灵敏的终结者",
        check = function(a) return a.positioning >= 17 and a.composure >= 15 and a.shooting >= 14 end},
    -- 防守类
    {id = "brick_wall", name = "铜墙铁壁", desc = "防守极为可靠",
        check = function(a) return a.defending >= 17 and a.tackling >= 16 end},
    {id = "ball_winner", name = "抢断机器", desc = "积极的防守拦截",
        check = function(a) return a.tackling >= 17 and a.aggression >= 14 and a.stamina >= 14 end},
    -- 头球类
    {id = "aerial_threat", name = "空霸", desc = "制空能力突出",
        check = function(a) return a.aerial >= 17 and a.strength >= 14 end},
    -- 团队类
    {id = "captain", name = "队长气质", desc = "天生的领导者",
        check = function(a) return a.leadership >= 17 and a.teamwork >= 14 and a.composure >= 14 end},
    {id = "team_player", name = "团队楷模", desc = "无私的团队球员",
        check = function(a) return a.teamwork >= 17 and a.decisions >= 14 end},
    -- 耐力类
    {id = "engine", name = "永动机", desc = "不知疲倦的跑动",
        check = function(a) return a.stamina >= 18 and a.speed >= 13 end},
    -- 心理类
    {id = "big_game", name = "大场面先生", desc = "关键比赛发挥出色",
        check = function(a) return a.composure >= 17 and a.decisions >= 15 end},
    {id = "inconsistent", name = "状态起伏", desc = "表现不够稳定",
        check = function(a) return a.composure <= 8 and a.decisions <= 10 end},
    -- 门将特性
    {id = "shot_stopper", name = "扑救专家", desc = "出色的反应扑救",
        check = function(a) return a.reflexes >= 17 and a.handling >= 15 end},
    {id = "sweeper_keeper", name = "出击型门将", desc = "善于出击的门将",
        check = function(a) return a.reflexes >= 14 and a.speed >= 12 and a.positioning >= 15 end},
    -- 年轻天才
    {id = "wonderkid", name = "未来之星", desc = "潜力极高的年轻球员",
        check = function(a, player) return player and player.potential >= 85 and player:getAge(2024) <= 21 end},
    -- 老将
    {id = "veteran", name = "经验老将", desc = "丰富的比赛经验",
        check = function(a, player) return player and player:getAge(2024) >= 32 and a.decisions >= 15 and a.composure >= 14 end},
}

--- 根据当前属性自动计算球员特性
function Player:calculateTraits(currentYear)
    local newTraits = {}
    local a = self.attributes

    for _, def in ipairs(Player.TRAIT_DEFINITIONS) do
        -- wonderkid 和 veteran 需要传入 player 和 year
        local passed = false
        if def.id == "wonderkid" then
            passed = self.potential >= 85 and self:getAge(currentYear or 2024) <= 21
        elseif def.id == "veteran" then
            passed = self:getAge(currentYear or 2024) >= 32 and a.decisions >= 15 and a.composure >= 14
        else
            passed = def.check(a)
        end

        if passed then
            table.insert(newTraits, def.id)
        end
    end

    self.traits = newTraits
    return newTraits
end

--- 获取特性详情列表（用于 UI 展示）
function Player:getTraitDetails()
    local details = {}
    for _, traitId in ipairs(self.traits or {}) do
        for _, def in ipairs(Player.TRAIT_DEFINITIONS) do
            if def.id == traitId then
                table.insert(details, {
                    id = def.id,
                    name = def.name,
                    desc = def.desc,
                })
                break
            end
        end
    end
    return details
end

------------------------------------------------------

-- 序列化为存档数据
function Player:serialize()
    return {
        id = self.id,
        firstName = self.firstName,
        lastName = self.lastName,
        displayName = self.displayName,
        birthYear = self.birthYear,
        nationality = self.nationality,
        position = self.position,
        naturalPositions = self.naturalPositions,
        preferredFoot = self.preferredFoot,
        weakFoot = self.weakFoot,
        attributes = self.attributes,
        fitness = self.fitness,
        morale = self.morale,
        condition = self.condition,
        injured = self.injured,
        injuryDays = self.injuryDays,
        retired = self.retired,
        overall = self.overall,
        potential = self.potential,
        contractEnd = self.contractEnd,
        wage = self.wage,
        value = self.value,
        releaseClause = self.releaseClause,
        teamId = self.teamId,
        squadRole = self.squadRole,
        careerHistory = self.careerHistory,
        seasonStats = self.seasonStats,
        trainingFocus = self.trainingFocus,
        listedForSale = self.listedForSale,
        listedForLoan = self.listedForLoan,
        traits = self.traits,
    }
end

return Player
