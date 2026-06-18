-- domain/player.lua
-- 球员数据模型

local Constants = require("scripts/app/constants")

local Player = {}
Player.__index = Player

------------------------------------------------------
-- 紧凑序列化（存档瘦身）
--
-- attributes/seasonStats 在存档里按固定顺序存为数组，省去每名球员
-- 重复存储的长键名（实测每人节省约 0.4KB，几千名球员可省数 MB）。
-- 旧存档（对象格式）和新存档（数组格式）都能读：见 _unpackNumeric。
-- 注意：顺序一旦发布不可改动，只能在末尾追加新字段！
------------------------------------------------------
local ATTR_ORDER = {
    "speed", "stamina", "strength", "agility", "passing", "shooting",
    "tackling", "dribbling", "defending", "positioning", "vision",
    "decisions", "composure", "aggression", "teamwork", "leadership",
    "handling", "reflexes", "aerial",
}
local STATS_ORDER = {
    "appearances", "goals", "assists", "yellowCards", "redCards",
    "avgRating", "cleanSheets",
}

local function packNumeric(t, order)
    if type(t) ~= "table" then return nil end
    local out = {}
    for i, k in ipairs(order) do
        out[i] = t[k] or 0
    end
    return out
end

-- 兼容两种格式：数组（新存档）按固定顺序还原；对象（旧存档/运行时）原样返回
local function unpackNumeric(t, order)
    if type(t) ~= "table" then return t end
    if t[1] == nil then return t end  -- 对象格式（无数组部分）
    local out = {}
    for i, k in ipairs(order) do
        out[k] = t[i]
    end
    return out
end

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

    -- 核心属性 (1-20)；存档中可能是紧凑数组格式，先还原
    self.attributes = unpackNumeric(data.attributes, ATTR_ORDER) or {}
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
    self.injuryKind = data.injuryKind or nil
    self.injuryKindName = data.injuryKindName or nil
    self.injurySeverity = data.injurySeverity or nil
    self.injurySeverityName = data.injurySeverityName or nil
    self.injurySeasonEnding = data.injurySeasonEnding or false
    self.retired = data.retired or false
    self.retiredSeason = data.retiredSeason or nil  -- 退役赛季（Housekeeping 延迟一季后物理删除）

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
    self.paRating = data.paRating or nil         -- PA抽象评级 (1.0-10.0)
    self.actualPotential = data.actualPotential or nil  -- 局内实际潜力

    -- 合同
    self.contractEnd = data.contractEnd or nil  -- {year, month}
    self.wage = (data.wage and data.wage > 0) and data.wage or 1000
    self.value = data.value or 100000
    self.releaseClause = data.releaseClause or nil

    -- 球队归属
    self.teamId = data.teamId or nil
    -- 阵容角色: "key"=绝对主力, "rotation"=轮换球员, "squad"=阵容球员, "youth"=青年球员, "loaned"=租借
    self.squadRole = data.squadRole or "rotation"
    self.isYouth = data.isYouth or false

    -- 职业历史 (每赛季记录；超过上限的早期赛季由 Housekeeping 折叠进 careerTotals)
    self.careerHistory = data.careerHistory or {}
    self.careerTotals = data.careerTotals or nil  -- {seasons, appearances, goals, assists, ...}

    -- 赛季统计（存档中可能是紧凑数组格式，先还原）
    self.seasonStats = unpackNumeric(data.seasonStats, STATS_ORDER) or {
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
    self.positionTrainingTarget = data.positionTrainingTarget or nil
    self.positionTrainingProgress = data.positionTrainingProgress or 0
    self.positionTrainingDrillProgress = data.positionTrainingDrillProgress or 0

    -- 转会
    self.listedForSale = data.listedForSale or false
    self.listedForLoan = data.listedForLoan or false
    self.loanListDuration = data.loanListDuration
    self._transferWindowKey = data._transferWindowKey or nil

    -- 名气/声望 (1-100，影响身价)
    self.reputation = data.reputation or 30

    -- 传奇球员标记（须在 traits 归一化之前设置）
    self.isLegend = data.isLegend or false
    self.legendName = data.legendName or nil
    self.legendData = data.legendData or nil

    -- 转生球员标记（用于立绘展示和 UI 识别）
    self.isReincarnation = data.isReincarnation or false
    self.reincarnationMatchName = data.reincarnationMatchName or nil

    -- 转生球员固有特性（不受 calculateTraits 属性达标覆盖）
    self.innateTraits = data.innateTraits or nil

    -- 球员特性：传奇走传奇池，普通走标准池
    self.traits = Player.normalizeTraits(data.traits or {}, self.isLegend, self.position)

    return self
end

-- 计算当前年龄
function Player:getAge(currentYear)
    return currentYear - self.birthYear
end

--- 获取该球员的单项属性上限
--- 传奇球员: 23; 巨星(PA>=95): 21; 普通球员: ceil(pot/5), 上限20
---@return number
function Player:getAttrCap()
    -- 传奇球员最高突破到23
    if self.isLegend then
        return Constants.LEGEND_ATTR_MAX
    end
    local pot = self.actualPotential or self.potential or 60
    if pot >= Constants.SUPERSTAR_POTENTIAL_THRESHOLD then
        return Constants.SUPERSTAR_ATTR_MAX
    end
    return math.min(Constants.ATTR_MAX, math.ceil(pot / 5))
end

--- 基于局内潜力估算的总评上限（非传奇）
---@return number
function Player:getPotentialOverallCap()
    if self.isLegend then
        return Constants.LEGEND_OVERALL_MAX
    end
    local pot = self.actualPotential or self.potential or 60
    if pot >= Constants.SUPERSTAR_POTENTIAL_THRESHOLD then
        return Constants.SUPERSTAR_OVERALL_MAX
    end
    return math.min(Constants.ABILITY_MAX, math.floor(pot * 1.1 + 1))
end

--- 将属性与总评钳制到潜力上限（数据加载 / 初始化后调用）
function Player:clampToPotentialCaps()
    if not self.attributes then return end
    local attrCap = self:getAttrCap()
    for key, val in pairs(self.attributes) do
        if type(val) == "number" then
            self.attributes[key] = math.min(val, attrCap)
        end
    end
    self:calculateOverall()
    local ovrCap = self:getPotentialOverallCap()
    if (self.overall or 0) > ovrCap then
        self.overall = ovrCap
    end
end

--- 获取该球员的总评上限
---@return number
function Player:getOverallCap()
    return self:getPotentialOverallCap()
end

--- 获取 UI 显示用的总评（上限99，后台可能存到101）
---@return number
function Player:displayOverall()
    return math.min(Constants.ABILITY_MAX, self.overall or 0)
end

--- 获取 UI 显示用的单项属性值（上限20，后台可能存到21）
---@param key string 属性键名
---@return number
function Player:displayAttr(key)
    local val = self.attributes[key] or 0
    return math.min(Constants.ATTR_MAX, val)
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
    local overallCap = self:getOverallCap()
    overall = math.max(Constants.ABILITY_MIN, math.min(overallCap, overall))
    self.overall = overall
    return overall
end

--- 静态方法：根据位置和属性表预计算 overall（不需要 Player 实例）
--- 用于候选球员生成时确保 UI 显示值与签入后一致
---@param pos string
---@param a table
---@return number
function Player.calculateOverallFromAttrs(pos, a)
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

    local posWeights
    if pos == "GK" then
        posWeights = { handling = 3.0, reflexes = 3.0, positioning = 2.0, aerial = 1.5, composure = 1.0, decisions = 0.5 }
    elseif pos == "CB" then
        posWeights = { defending = 2.5, tackling = 2.0, aerial = 2.0, strength = 1.5, composure = 1.5, leadership = 1.5, decisions = 1.0 }
    elseif pos == "LB" or pos == "RB" then
        posWeights = { speed = 2.0, passing = 2.0, defending = 1.5, tackling = 1.5, stamina = 1.5, dribbling = 1.0, vision = 1.0, positioning = 0.5 }
    elseif pos == "CDM" then
        posWeights = { tackling = 2.5, defending = 2.0, passing = 2.0, positioning = 1.5, stamina = 1.5, strength = 1.0, decisions = 0.5 }
    elseif pos == "CM" then
        posWeights = { passing = 2.5, vision = 2.0, dribbling = 2.0, stamina = 2.0, shooting = 1.5, decisions = 1.5, composure = 1.0 }
    elseif pos == "CAM" then
        posWeights = { vision = 2.5, dribbling = 2.5, passing = 2.0, shooting = 2.0, composure = 1.5, decisions = 1.0, agility = 0.5 }
    elseif pos == "LM" or pos == "RM" then
        posWeights = { speed = 2.0, dribbling = 2.0, passing = 2.0, stamina = 2.0, agility = 1.5, shooting = 1.0, vision = 1.0 }
    elseif pos == "LW" or pos == "RW" then
        posWeights = { dribbling = 3.0, agility = 2.0, shooting = 2.0, speed = 1.5, passing = 1.5, composure = 1.0, vision = 1.0 }
    elseif pos == "ST" then
        posWeights = { shooting = 3.0, composure = 2.5, speed = 2.0, positioning = 1.5, dribbling = 1.0, strength = 1.0, aerial = 0.5 }
    elseif pos == "CF" then
        posWeights = { shooting = 2.5, composure = 2.0, dribbling = 2.0, vision = 1.5, passing = 1.5, speed = 1.0, positioning = 1.0 }
    else
        posWeights = { passing = 1.5, shooting = 1.5, dribbling = 1.5, defending = 1.0, speed = 1.0, stamina = 1.0, decisions = 1.0 }
    end

    local posSum = 0
    local posTotalW = 0
    for attr, w in pairs(posWeights) do
        posSum = posSum + (a[attr] or 10) * w
        posTotalW = posTotalW + w
    end
    local posScore = posSum / posTotalW

    local finalScore = baseScore * 0.40 + posScore * 0.60

    local ovrRaw
    if finalScore <= 13 then
        ovrRaw = finalScore * 5.0 + 8
    elseif finalScore <= 15.5 then
        ovrRaw = 73 + (finalScore - 13) * 6.5
    else
        ovrRaw = 89.25 + (finalScore - 15.5) * 4.5
    end

    local overall = math.floor(ovrRaw)
    return math.max(Constants.ABILITY_MIN, math.min(Constants.ABILITY_MAX, overall))
end

-- 计算市场价值（指数模型 + 年龄曲线 + 潜力溢价/折旧 + 合同年限折价 + 名气修正）
-- 校准: OVR70≈6M, OVR75≈12M, OVR80≈24M, OVR85≈49M, OVR90≈98M（黄金年龄基础值）
function Player:calculateValue(currentYear)
    local age = self:getAge(currentYear)
    local ovr = self.overall

    -- 1. 基础值：平缓指数 value = C * D^ovr
    -- D = 1.15 → 每5点OVR翻一倍（1.15^5≈2.01）
    local D = 1.15
    local C = 336.7  -- 6,000,000 / 1.15^70
    local base = C * (D ^ ovr)

    -- 2. 年龄修正（纯能力维度：黄金期23-27加成，老将贬值）
    local ageMult
    if age <= 19 then
        ageMult = 0.65
    elseif age <= 21 then
        ageMult = 0.65 + (age - 19) * 0.15   -- 19→0.65, 21→0.95
    elseif age <= 23 then
        ageMult = 0.95 + (age - 21) * 0.075  -- 21→0.95, 23→1.10
    elseif age <= 27 then
        ageMult = 1.10 + (age - 23) * 0.025  -- 23→1.10, 27→1.20
    elseif age <= 29 then
        ageMult = 1.20 - (age - 27) * 0.10   -- 27→1.20, 29→1.00
    elseif age <= 31 then
        ageMult = 1.00 - (age - 29) * 0.12   -- 29→1.00, 31→0.76
    elseif age <= 33 then
        ageMult = 0.76 - (age - 31) * 0.13   -- 31→0.76, 33→0.50
    elseif age <= 35 then
        ageMult = 0.50 - (age - 33) * 0.12   -- 33→0.50, 35→0.26
    else
        ageMult = math.max(0.10, 0.26 - (age - 35) * 0.08)
    end
    base = base * ageMult

    -- 3. 潜力修正（核心改动：年轻高潜大幅溢价，年长未兑现逐步折旧）
    local effectivePotential = self.actualPotential or self.potential
    if effectivePotential and effectivePotential > ovr then
        local potGap = effectivePotential - ovr  -- 潜差

        -- 潜力可信度权重：年轻时潜力最值钱，随年龄递减
        -- 18岁=100%权重，25岁=40%权重，28岁=10%权重，30+=0%
        local potWeight
        if age <= 18 then
            potWeight = 1.0
        elseif age <= 22 then
            potWeight = 1.0 - (age - 18) * 0.10   -- 18→1.0, 22→0.6
        elseif age <= 25 then
            potWeight = 0.6 - (age - 22) * 0.13   -- 22→0.6, 25→0.21
        elseif age <= 28 then
            potWeight = 0.21 - (age - 25) * 0.06  -- 25→0.21, 28→0.03
        else
            potWeight = 0  -- 29+岁：潜力不再影响身价
        end

        -- 潜力溢价系数（非线性：潜差越大溢价越猛）
        -- potGap=10 → +50%~100%, potGap=20 → +150%~300%, potGap=30 → +300%~600%
        local potMult = 1.0
        if potWeight > 0 then
            -- 指数曲线：小潜差温和，大潜差爆炸
            local rawBonus = (1.04 ^ potGap) - 1  -- potGap=10→0.48, 20→1.19, 30→2.24
            potMult = 1.0 + rawBonus * potWeight * 2.0
        end
        base = base * potMult
    end

    -- 4. 名气修正（reputation 1-100 → 乘数 0.75~1.4）
    local rep = self.reputation or 30
    local repMult
    if rep >= 80 then
        repMult = 1.15 + (rep - 80) * 0.0125  -- 80→1.15, 100→1.40
    elseif rep >= 60 then
        repMult = 1.0 + (rep - 60) * 0.0075   -- 60→1.0, 80→1.15
    elseif rep >= 40 then
        repMult = 0.9 + (rep - 40) * 0.005    -- 40→0.9, 60→1.0
    else
        repMult = 0.75 + rep * 0.00375         -- 0→0.75, 40→0.9
    end
    base = base * repMult

    -- 5. 合同剩余年限折价（最后1年打6折，2年打8折）
    if self.contractEnd then
        local contractMonths = (self.contractEnd.year - currentYear) * 12
            + (self.contractEnd.month or 6) - 6  -- 粗算到赛季中期
        contractMonths = math.max(0, contractMonths)

        local contractMult
        if contractMonths <= 6 then
            contractMult = 0.50   -- 半年内到期：半价（快可以免签了）
        elseif contractMonths <= 12 then
            contractMult = 0.65   -- 1年内
        elseif contractMonths <= 24 then
            contractMult = 0.80   -- 2年内
        elseif contractMonths <= 36 then
            contractMult = 0.92   -- 3年内
        else
            contractMult = 1.0    -- 3年+：无折扣
        end
        base = base * contractMult
    end

    -- 取整到十万级（100000）
    self.value = math.floor(base / 100000) * 100000
    -- 最低值50万
    if self.value < 500000 then self.value = 500000 end
    return self.value
end

-- 计算球员名气（基于球队声望、能力评级、阵容角色）
-- teamReputation: 球队声望 (1-1000 范围，如 Arsenal≈636, Man City≈599)
function Player:calculateReputation(teamReputation)
    -- 球队声望贡献 (team rep 100-1000 → 10-50分)
    local teamContrib = math.floor((teamReputation or 300) / 20)
    teamContrib = math.max(5, math.min(50, teamContrib))

    -- OVR贡献 (ovr 60-95 → 5-45分)
    local ovrContrib = math.max(0, (self.overall - 55)) * 1.15
    ovrContrib = math.max(5, math.min(45, ovrContrib))

    -- 角色加成
    local roleBonus = 0
    if self.squadRole == "key" then
        roleBonus = 8
    elseif self.squadRole == "first_team" or self.squadRole == "rotation" then
        roleBonus = 3
    end

    local rep = math.floor(teamContrib * 0.4 + ovrContrib * 0.6 + roleBonus)
    rep = math.max(1, math.min(100, rep))
    self.reputation = rep
    return rep
end

-- 获取位置中文名
function Player:getPositionName()
    return Constants.POSITION_NAMES[self.position] or self.position
end

------------------------------------------------------
-- 球员特性系统（标准池：属性自动判定；传奇池：JSON 导入专属）
------------------------------------------------------

--- 传奇身份被动（全体传奇自带，非 traits 数组条目）
Player.LEGEND_IDENTITY = {
    id = "legend_identity",
    name = "传奇身份",
    desc = "提高属性与总评上限；提高训练成长；带动同位置队友训练；稳定赛后评分",
}

--- 仅门将可持有的特质 id
Player.GK_ONLY_TRAIT_IDS = {
    shot_stopper = true,
    sweeper_keeper = true,
}

---@param traitId string|nil
---@return boolean
function Player.isGkOnlyTrait(traitId)
    local id = Player.normalizeTraitId(traitId)
    return id ~= nil and Player.GK_ONLY_TRAIT_IDS[id] == true
end

--- FM / 传奇 JSON 特质名 → 局内 snake_case id
Player.EXTERNAL_TRAIT_ALIASES = {
    Poacher = "poacher", poacher = "poacher",
    Dribbler = "dribbler", dribbler = "dribbler",
    Visionary = "visionary", visionary = "visionary",
    Playmaker = "playmaker", playmaker = "playmaker",
    Finisher = "clinical", finisher = "clinical",
    Trickster = "trickster", trickster = "trickster",
    Leader = "captain", leader = "captain",
    AerialThreat = "aerial_threat", aerial_threat = "aerial_threat",
    BallPlayingDefender = "ball_playing_defender", ball_playing_defender = "ball_playing_defender",
    BoxToBox = "box_to_box", box_to_box = "box_to_box",
    Crosser = "crosser", crosser = "crosser",
    DeadBall = "dead_ball", dead_ball = "dead_ball",
    Distributor = "distributor", distributor = "distributor",
    Engine = "engine", engine = "engine",
    Overlapper = "overlapper", overlapper = "overlapper",
    Reflexes = "shot_stopper", reflexes = "shot_stopper",
    Speedster = "pace_merchant", speedster = "pace_merchant",
    Stopper = "ball_winner", stopper = "ball_winner",
    BallWinner = "ball_winner", ball_winner = "ball_winner",
    Sweeper = "sweeper_keeper", sweeper = "sweeper_keeper",
    Libero = "libero", libero = "libero",
    Clinical = "clinical", clinical = "clinical",
    LongShot = "long_shot", long_shot = "long_shot",
    BigGame = "big_game", big_game = "big_game",
}

--- 传奇特质池（仅传奇球员可持有；sharedWithStandard 表示与普通池同名机制）
Player.LEGEND_TRAIT_DEFINITIONS = {
    { id = "poacher", name = "禁区猎手", desc = "显著提高门前射门机会", sharedWithStandard = true },
    { id = "clinical", name = "临门一脚", desc = "显著提高射正与进球转化", sharedWithStandard = true },
    { id = "dribbler", name = "盘带大师", desc = "显著提高持球突破与射门创造", sharedWithStandard = true },
    { id = "playmaker", name = "组织核心", desc = "显著提高控球与助攻创造", sharedWithStandard = true },
    { id = "captain", name = "队长气质", desc = "显著降低犯规与黄牌风险", sharedWithStandard = true },
    { id = "aerial_threat", name = "空霸", desc = "显著提高空中对抗与头球威胁", sharedWithStandard = true },
    { id = "dead_ball", name = "定位球专家", desc = "显著提高定位球与点球表现", sharedWithStandard = true },
    { id = "engine", name = "永动机", desc = "显著提高全队体能输出", sharedWithStandard = true },
    { id = "pace_merchant", name = "飞毛腿", desc = "显著提高反击速度与比赛节奏", sharedWithStandard = true },
    { id = "ball_winner", name = "抢断机器", desc = "显著提高防守与压迫", sharedWithStandard = true },
    { id = "shot_stopper", name = "扑救专家", desc = "显著降低对手射正进球率", sharedWithStandard = true },
    { id = "sweeper_keeper", name = "出击型门将", desc = "显著提高出击、控球与反击发起", sharedWithStandard = true },
    -- 传奇池独占（普通球员不可获得）
    { id = "visionary", name = "视野大师", desc = "提高深位传球与助攻创造", legendExclusive = true },
    { id = "trickster", name = "魔术师", desc = "提高个人突破与冷门进球", legendExclusive = true },
    { id = "distributor", name = "分发大师", desc = "提高控球与转移节奏", legendExclusive = true },
    { id = "ball_playing_defender", name = "出球后卫", desc = "提高后场出球与组织", legendExclusive = true },
    { id = "libero", name = "清道夫", desc = "提高防线兜底、补位与后场出球", legendExclusive = true },
    { id = "box_to_box", name = "全能中场", desc = "提高中场攻防覆盖", legendExclusive = true },
    { id = "crosser", name = "传中高手", desc = "提高边路传中与助攻", legendExclusive = true },
    { id = "overlapper", name = "插上助攻", desc = "提高边卫前插与反击配合", legendExclusive = true },
}

local LEGEND_TRAIT_ID_SET = {}
local LEGEND_EXCLUSIVE_SET = {}
for _, def in ipairs(Player.LEGEND_TRAIT_DEFINITIONS) do
    LEGEND_TRAIT_ID_SET[def.id] = true
    if def.legendExclusive then
        LEGEND_EXCLUSIVE_SET[def.id] = true
    end
end

---@param traitId string
---@return boolean
function Player.isLegendPoolTrait(traitId)
    return LEGEND_TRAIT_ID_SET[Player.normalizeTraitId(traitId) or ""] == true
end

---@param traitId string
---@return boolean
function Player.isLegendExclusiveTrait(traitId)
    return LEGEND_EXCLUSIVE_SET[Player.normalizeTraitId(traitId) or ""] == true
end

---@param traitId string
---@return boolean 是否与标准池同名、且传奇持有时可强化
function Player.isLegendSharedTrait(traitId)
    local id = Player.normalizeTraitId(traitId)
    if not id then return false end
    for _, def in ipairs(Player.LEGEND_TRAIT_DEFINITIONS) do
        if def.id == id and def.sharedWithStandard then
            return true
        end
    end
    return false
end

--- 传奇共享特质效果倍率（比赛内特质数值）
---@return number
function Player.getLegendSharedTraitMult()
    return Constants.LEGEND_SHARED_TRAIT_MULT
end

---@return table|nil 传奇身份被动（UI 专用）
function Player:getLegendIdentity()
    if not self.isLegend then return nil end
    return Player.LEGEND_IDENTITY
end

---@param raw string|nil
---@return string|nil
function Player.normalizeTraitId(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local mapped = Player.EXTERNAL_TRAIT_ALIASES[raw]
    if mapped then return mapped end
    if raw:match("^[a-z][a-z0-9_]*$") then return raw end
    return raw:lower()
end

--- JSON 别名 + 位置 → 最终 trait id（Sweeper 在 GK 为出击型门将，在场员为清道夫）
---@param raw string|nil
---@param position string|nil
---@return string|nil
function Player.resolveTraitId(raw, position)
    local id = Player.normalizeTraitId(raw)
    if not id then return nil end
    if id == "sweeper_keeper" and position and position ~= "GK" then
        return "libero"
    end
    if position and position ~= "GK" and Player.isGkOnlyTrait(id) then
        return nil
    end
    return id
end

---@param traits string[]|nil
---@param isLegend boolean|nil
---@param position string|nil
---@return string[]
function Player.normalizeTraits(traits, isLegend, position)
    local out, seen = {}, {}
    for _, raw in ipairs(traits or {}) do
        local id = Player.resolveTraitId(raw, position)
        if not id or seen[id] then goto continue end
        if isLegend then
            if Player.isLegendPoolTrait(id) then
                seen[id] = true
                table.insert(out, id)
            end
        else
            if not Player.isLegendExclusiveTrait(id) and Player.getStandardTraitDefinition(id) then
                seen[id] = true
                table.insert(out, id)
            end
        end
        ::continue::
    end
    return out
end

---@param player table
---@param traitId string
---@return boolean
function Player.hasTrait(player, traitId)
    if not player then return false end
    local want = Player.normalizeTraitId(traitId)
    if not want then return false end

    local function owns(id)
        for _, raw in ipairs(player.traits or {}) do
            if Player.normalizeTraitId(raw) == id then return true end
        end
        return false
    end

    if owns(want) then return true end
    return false
end

---@param traitId string
---@return table|nil
function Player.getLegendTraitDefinition(traitId)
    local id = Player.normalizeTraitId(traitId)
    if not id then return nil end
    for _, def in ipairs(Player.LEGEND_TRAIT_DEFINITIONS) do
        if def.id == id then
            return {
                id = def.id,
                name = def.name,
                desc = def.desc,
                pool = "legend",
                legendExclusive = def.legendExclusive or false,
                sharedWithStandard = def.sharedWithStandard or false,
            }
        end
    end
    return nil
end

---@param traitId string
---@return table|nil
function Player.getStandardTraitDefinition(traitId)
    local id = Player.normalizeTraitId(traitId)
    if not id then return nil end
    for _, def in ipairs(Player.TRAIT_DEFINITIONS) do
        if def.id == id then
            return {
                id = def.id,
                name = def.name,
                desc = def.desc,
                pool = "standard",
                legendExclusive = false,
                sharedWithStandard = Player.isLegendPoolTrait(id),
            }
        end
    end
    return nil
end

---@param traitId string
---@return table|nil
function Player.getTraitDefinition(traitId)
    return Player.getLegendTraitDefinition(traitId)
        or Player.getStandardTraitDefinition(traitId)
end

-- 标准特质池：属性达标自动判定（普通球员）
Player.TRAIT_DEFINITIONS = {
    {id = "pace_merchant", name = "飞毛腿", desc = "提高反击速度与比赛节奏",
        check = function(a) return a.speed >= 17 and a.agility >= 14 end},
    {id = "powerhouse", name = "力量怪兽", desc = "提高对抗、制空与防守",
        check = function(a) return a.strength >= 17 and a.aggression >= 14 end},
    {id = "playmaker", name = "组织核心", desc = "提高控球与助攻创造",
        check = function(a) return a.passing >= 16 and a.vision >= 16 and a.decisions >= 14 end},
    {id = "dribbler", name = "盘带大师", desc = "提高持球突破与射门创造",
        check = function(a) return a.dribbling >= 17 and a.agility >= 15 end},
    {id = "dead_ball", name = "定位球专家", desc = "提高定位球与点球表现",
        check = function(a) return a.passing >= 16 and a.shooting >= 15 and a.composure >= 14 end},
    {id = "clinical", name = "临门一脚", desc = "提高射正与进球转化",
        check = function(a) return a.shooting >= 17 and a.composure >= 15 end},
    {id = "long_shot", name = "远射威胁", desc = "提高远射倾向；降低射正稳定性",
        check = function(a) return a.shooting >= 16 and a.strength >= 13 end},
    {id = "poacher", name = "禁区猎手", desc = "提高门前射门机会",
        check = function(a) return a.positioning >= 17 and a.composure >= 15 and a.shooting >= 14 end},
    {id = "brick_wall", name = "铜墙铁壁", desc = "提高后卫线防守硬度",
        check = function(a) return a.defending >= 17 and a.tackling >= 16 end},
    {id = "ball_winner", name = "抢断机器", desc = "提高防守与压迫；略提高黄牌风险",
        check = function(a) return a.tackling >= 17 and a.aggression >= 14 and a.stamina >= 14 end},
    {id = "aerial_threat", name = "空霸", desc = "提高空中对抗与头球威胁",
        check = function(a) return a.aerial >= 17 and a.strength >= 14 end},
    {id = "captain", name = "队长气质", desc = "降低犯规与黄牌风险",
        check = function(a) return a.leadership >= 17 and a.teamwork >= 14 and a.composure >= 14 end},
    {id = "team_player", name = "团队楷模", desc = "提高团队配合与助攻意愿",
        check = function(a) return a.teamwork >= 17 and a.decisions >= 14 end},
    {id = "engine", name = "永动机", desc = "提高全队体能输出",
        check = function(a) return a.stamina >= 18 and a.speed >= 13 end},
    {id = "big_game", name = "大场面先生", desc = "提高关键战进球与状态稳定性",
        check = function(a) return a.composure >= 17 and a.decisions >= 15 end},
    {id = "inconsistent", name = "状态起伏", desc = "降低发挥稳定性；提高黄牌风险",
        check = function(a) return a.composure <= 8 and a.decisions <= 10 end},
    {id = "shot_stopper", name = "扑救专家", desc = "降低对手射正进球率",
        gkOnly = true,
        check = function(a) return a.reflexes >= 17 and a.handling >= 15 end},
    {id = "sweeper_keeper", name = "出击型门将", desc = "提高出击、控球与反击发起",
        gkOnly = true,
        check = function(a) return a.reflexes >= 14 and a.speed >= 12 and a.positioning >= 15 end},
    {id = "wonderkid", name = "未来之星", desc = "标识高潜力年轻球员",
        check = function(a, player, currentYear) return player and player.potential >= 85 and player:getAge(currentYear or 2024) <= 21 end},
    {id = "veteran", name = "经验老将", desc = "提高比赛阅读与纪律性",
        check = function(a, player, currentYear) return player and player:getAge(currentYear or 2024) >= 32 and a.decisions >= 15 and a.composure >= 14 end},
}

--- 根据当前属性自动计算球员特性（传奇球员仅保留传奇池导入特质）
function Player:calculateTraits(currentYear)
    if self.isLegend then
        self.traits = Player.normalizeTraits(self.traits, true, self.position)
        return self.traits
    end

    local newTraits = {}
    local a = self.attributes
    local isGk = self.position == "GK"

    for _, def in ipairs(Player.TRAIT_DEFINITIONS) do
        local passed = false
        if def.gkOnly and not isGk then
            passed = false
        elseif def.id == "wonderkid" then
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

    -- 转生球员：合并固有特性（不受属性达标限制）
    if self.innateTraits then
        local seen = {}
        for _, id in ipairs(newTraits) do seen[id] = true end
        for _, raw in ipairs(self.innateTraits) do
            local id = Player.resolveTraitId(raw, self.position)
            if id and not seen[id] and (isGk or not Player.isGkOnlyTrait(id)) then
                table.insert(newTraits, id)
                seen[id] = true
            end
        end
    end

    self.traits = Player.normalizeTraits(newTraits, false, self.position)
    return self.traits
end

--- 获取特性详情列表（用于 UI 展示；不含传奇身份被动）
function Player:getTraitDetails()
    local details = {}
    for _, traitId in ipairs(self.traits or {}) do
        local def
        if self.isLegend then
            def = Player.getLegendTraitDefinition(traitId)
                or Player.getStandardTraitDefinition(traitId)
        else
            def = Player.getStandardTraitDefinition(traitId)
        end
        if def then
            table.insert(details, {
                id = def.id,
                name = def.name,
                desc = def.desc,
                pool = def.pool,
                legendExclusive = def.legendExclusive,
            })
        end
    end
    return details
end

--- 是否可参加俱乐部比赛/训练（伤停、退役、停赛）
function Player:isMatchAvailable()
    return not self.injured and not self.retired and not self.suspended
end

--- 伤停原因文案（UI / 转会拒绝提示）
---@return string|nil
function Player:getInjuryBlockReason()
    if not self.injured then return nil end
    if self.injurySeasonEnding then
        return string.format("赛季报销（%s，预计 %d 天后恢复）",
            self.injuryKindName or "严重伤病", self.injuryDays or 0)
    end
    if self.injuryKindName then
        return string.format("受伤中（%s · %s，剩余 %d 天）",
            self.injuryKindName,
            self.injurySeverityName or "恢复中",
            self.injuryDays or 0)
    end
    return string.format("受伤中（剩余 %d 天）", self.injuryDays or 0)
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
        attributes = packNumeric(self.attributes, ATTR_ORDER),
        fitness = self.fitness,
        morale = self.morale,
        condition = self.condition,
        injured = self.injured,
        injuryDays = self.injuryDays,
        injuryKind = self.injuryKind,
        injuryKindName = self.injuryKindName,
        injurySeverity = self.injurySeverity,
        injurySeverityName = self.injurySeverityName,
        injurySeasonEnding = self.injurySeasonEnding,
        retired = self.retired,
        retiredSeason = self.retiredSeason,
        overall = self.overall,
        potential = self.potential,
        paRating = self.paRating,
        actualPotential = self.actualPotential,
        contractEnd = self.contractEnd,
        wage = self.wage,
        value = self.value,
        releaseClause = self.releaseClause,
        teamId = self.teamId,
        squadRole = self.squadRole,
        careerHistory = self.careerHistory,
        careerTotals = self.careerTotals,
        seasonStats = packNumeric(self.seasonStats, STATS_ORDER),
        trainingFocus = self.trainingFocus,
        positionTrainingTarget = self.positionTrainingTarget,
        positionTrainingProgress = self.positionTrainingProgress,
        positionTrainingDrillProgress = self.positionTrainingDrillProgress,
        listedForSale = self.listedForSale,
        listedForLoan = self.listedForLoan,
        loanListDuration = self.loanListDuration,
        _transferWindowKey = self._transferWindowKey,
        traits = self.traits,
        reputation = self.reputation,
        morale_core = self.morale_core,
        isYouth = self.isYouth or false,
        isLegend = self.isLegend or false,
        legendName = self.legendName,
        legendData = self.legendData,
        isReincarnation = self.isReincarnation or false,
        reincarnationMatchName = self.reincarnationMatchName,
        innateTraits = self.innateTraits,
    }
end

return Player
