-- systems/difficulty_settings.lua
-- 难度参数系统：3档位制，方向统一（档位越高=对玩家越有利）

local Constants = require("scripts/app/constants")

local DifficultySettings = {}

-- 档位：1=保守, 2=正常, 3=宽松
DifficultySettings.TIERS = { 1, 2, 3 }
DifficultySettings.TIER_LABELS = { "保守", "正常", "宽松" }

-- 默认值（中间档）
DifficultySettings.DEFAULTS = {
    transferTier = 2,  -- 转会：1=AI保守 2=正常 3=AI宽松
    matchTier = 2,     -- 比赛：1=稳定 2=正常 3=戏剧性强
    youthTier = 2,     -- 青训：1=起点低 2=正常 3=起点高
    trainingTier = 2,  -- 训练/体力：1=严苛 2=正常 3=宽松（基准已重平衡，默认正常）
}

-- 参数描述（UI展示用）
DifficultySettings.PARAMS = {
    {
        key = "transferTier",
        name = "转会市场",
        desc = "影响AI接受报价的范围和合同容忍度",
        tierHints = { "AI保守，谈判困难", "正常市场环境", "AI宽松，容易成交" },
    },
    {
        key = "matchTier",
        name = "比赛波动",
        desc = "影响比赛随机性与弱队爆冷概率（已校准 OVR 差）",
        tierHints = { "强弱悬殊，冷门极少", "正常随机性，偶有冷门", "冷门较多，结果难预测" },
    },
    {
        key = "youthTier",
        name = "青训质量",
        desc = "影响青训球员初始年龄与能力",
        tierHints = { "初始年龄小、能力低，培养周期长", "正常初始年龄与能力", "初始年龄大、能力高，更快出场" },
    },
    {
        key = "trainingTier",
        name = "训练与体力",
        desc = "影响日常训练成长、赛季末成长、出场挂钩效率、伤病与体力循环",
        tierHints = {
            "日常/赛季成长慢，出场要求严，伤病多",
            "正常成长节奏（推荐）",
            "日常/赛季成长快，出场宽容，伤病少",
        },
    },
}

------------------------------------------------------
-- 读取/写入
------------------------------------------------------

--- 获取难度设置
---@return table difficulty {transferTier, matchTier, youthTier} 值为1/2/3
function DifficultySettings.get()
    local gs = _G.gameState
    if not gs then return DifficultySettings._copyDefaults() end

    gs.settings = gs.settings or {}
    gs.settings.difficulty = gs.settings.difficulty or DifficultySettings._copyDefaults()

    -- 校验值域：防止存档损坏或手动修改导致非法值
    local diff = gs.settings.difficulty
    for _, key in ipairs({"transferTier", "matchTier", "youthTier", "trainingTier"}) do
        local v = diff[key]
        if type(v) ~= "number" or v < 1 or v > 3 then
            diff[key] = DifficultySettings.DEFAULTS[key] or 2
        else
            diff[key] = math.floor(v)
        end
    end

    return diff
end

--- 设置单项难度档位
---@param key string 参数名 (transferTier/matchTier/youthTier)
---@param tier number 1/2/3
function DifficultySettings.set(key, tier)
    local gs = _G.gameState
    if not gs then return end

    gs.settings = gs.settings or {}
    gs.settings.difficulty = gs.settings.difficulty or DifficultySettings._copyDefaults()

    tier = math.max(1, math.min(3, math.floor(tier)))
    gs.settings.difficulty[key] = tier
end

--- 重置所有为默认
function DifficultySettings.resetAll()
    local gs = _G.gameState
    if not gs then return end
    gs.settings = gs.settings or {}
    gs.settings.difficulty = DifficultySettings._copyDefaults()
end

------------------------------------------------------
-- 参数转换（供各系统调用）
------------------------------------------------------

--- 转会：档位越高，AI越宽松
--- tier=1: AI保守（阈值+0.12，还价高+0.10，心情差-6）
--- tier=2: 基准（无偏移）
--- tier=3: AI宽松（阈值-0.12，还价低-0.10，心情好+6）
function DifficultySettings.getTransferModifiers()
    local diff = DifficultySettings.get()
    local tier = diff.transferTier or 2
    -- tier 1→-1, 2→0, 3→+1
    local t = tier - 2

    return {
        thresholdOffset = -t * 0.12,          -- 负=更容易接受
        counterMultiplierOffset = -t * 0.10,  -- 负=还价更低
        moodPenalty = -t * 6,                 -- 负=心情更好
    }
end

--- 比赛：档位越高，戏剧性越强（弱队更有机会）
--- tier=1: 稳定（方差×0.6, 弱队加成0）
--- tier=2: 正常（方差×1.0, 弱队加成0.1）
--- tier=3: 戏剧性（方差×1.4, 弱队加成0.2）
function DifficultySettings.getMatchModifiers()
    local diff = DifficultySettings.get()
    local tier = diff.matchTier or 2

    local configs = {
        { varianceFactor = 0.6, underdogBoost = 0.0 },   -- tier 1: 稳定
        { varianceFactor = 1.0, underdogBoost = 0.1 },   -- tier 2: 正常
        { varianceFactor = 1.4, underdogBoost = 0.2 },   -- tier 3: 戏剧性
    }
    return configs[tier] or configs[2]
end

--- 青训：档位越高，初始越成熟（年龄大+能力高=更快兑现）
--- tier=1: 年轻体(15-16岁, 能力偏低, 传奇16-17/70-80)
--- tier=2: 正常(16-17岁, 正常能力, 传奇17-18/75-85)
--- tier=3: 成熟体(16-18岁, 能力偏高, 传奇18-19/80-88)
function DifficultySettings.getYouthModifiers()
    local diff = DifficultySettings.get()
    local tier = diff.youthTier or 2

    local configs = {
        -- tier 1: 起点低，需长期培养
        {
            minAge = 15, maxAge = 16,
            potentialMin = 55, potentialMax = 85,
            overallMin = 45, overallMax = 65,
            legendMinAge = 16, legendMaxAge = 17,
            legendOverallMin = 70, legendOverallMax = 80,
        },
        -- tier 2: 正常（普通潜力60-90，OVR 50-75；传奇OVR 75-85）
        {
            minAge = 16, maxAge = 17,
            potentialMin = 60, potentialMax = 90,
            overallMin = 50, overallMax = 75,
            legendMinAge = 17, legendMaxAge = 18,
            legendOverallMin = 75, legendOverallMax = 85,
        },
        -- tier 3: 起点高，快速兑现（潜力上限92，仅传奇可突破99总评）
        {
            minAge = 16, maxAge = 18,
            potentialMin = 65, potentialMax = 92,
            overallMin = 55, overallMax = 80,
            legendMinAge = 18, legendMaxAge = 19,
            legendOverallMin = 80, legendOverallMax = 88,
        },
    }
    return configs[tier] or configs[2]
end

--- 体力：档位越高=消耗越低、恢复越快、低体力惩罚越轻
--- tier=2 基准值见 Constants.FITNESS_*（2026-06 全局重平衡）
function DifficultySettings.getFitnessModifiers()
    local diff = DifficultySettings.get()
    local tier = diff.trainingTier or 2

    local configs = {
        {
            drainMultiplier = 1.20,
            recoveryPostMatch = { 2, 4 },
            recoveryRest = { 3, 6 },
            matchFloor = 45,
            fitnessMulMin = 0.50,
        },
        {
            drainMultiplier = 1.0,
            recoveryPostMatch = Constants.FITNESS_RECOVERY_POST_MATCH,
            recoveryRest = Constants.FITNESS_RECOVERY_REST,
            matchFloor = Constants.FITNESS_MATCH_FLOOR,
            fitnessMulMin = Constants.FITNESS_MUL_MIN,
        },
        {
            drainMultiplier = 0.85,
            recoveryPostMatch = { 4, 7 },
            recoveryRest = { 5, 9 },
            matchFloor = 55,
            fitnessMulMin = 0.60,
        },
    }
    return configs[tier] or configs[2]
end

--- 赛后体力 clamp（受训练/体力难度档位影响）
---@param value number
---@return number
function DifficultySettings.clampFitness(value)
    local mods = DifficultySettings.getFitnessModifiers()
    return math.max(mods.matchFloor, math.min(Constants.FITNESS_MAX, value))
end

--- 训练与体力：档位越高=成长越快、伤病越少
--- tier=1: 严苛（成长慢、伤病多）
--- tier=2: 正常（与全局体力基准一致）
--- tier=3: 宽松（成长快、伤病少）
function DifficultySettings.getTrainingModifiers()
    local diff = DifficultySettings.get()
    local tier = diff.trainingTier or 2

    local configs = {
        -- tier 1: 严苛
        {
            baseChance = 0.06,
            gapDivisor = 30,
            gapFloor = 0.2,
            youthGapDivisor = 25,
            youthGapFloor = 0.3,
            participationScale = 0.85,
            seasonEndGrowth = {
                u21 = 0.30,
                youngAdult = 0.26,
                peak = 0.075,
            },
            decline = { mid = 0.23, late = 0.46 },
            intensity = {
                low  = { growthMultiplier = 0.5, fitnessLoss = 1, injuryChance = 0.002, fitnessRecoveryBonus = 2 },
                medium = { growthMultiplier = 1.0, fitnessLoss = 2, injuryChance = 0.010, fitnessRecoveryBonus = 0 },
                high = { growthMultiplier = 1.8, fitnessLoss = 3, injuryChance = 0.025, fitnessRecoveryBonus = -1 },
            },
            -- 周伤病检测
            weeklyInjury = { low = 0.005, medium = 0.015, high = 0.030 },
            injuryDaysMin = 3, injuryDaysMax = 17,
        },
        -- tier 2: 正常（日常训练 + 赛季末成长基准）
        {
            baseChance = 0.08,
            gapDivisor = 38,
            gapFloor = 0.3,
            youthGapDivisor = 32,
            youthGapFloor = 0.4,
            participationScale = 1.0,
            seasonEndGrowth = {
                u21 = Constants.U21_SEASON_END_GROWTH_CHANCE,
                youngAdult = 0.35,
                peak = 0.10,
            },
            decline = { mid = 0.20, late = 0.40 },
            intensity = {
                low  = { growthMultiplier = 0.5, fitnessLoss = 1, injuryChance = 0.001, fitnessRecoveryBonus = 2 },
                medium = { growthMultiplier = 1.0, fitnessLoss = 2, injuryChance = 0.008, fitnessRecoveryBonus = 0 },
                high = { growthMultiplier = 1.8, fitnessLoss = 3, injuryChance = 0.018, fitnessRecoveryBonus = 0 },
            },
            weeklyInjury = { low = 0.003, medium = 0.010, high = 0.020 },
            injuryDaysMin = 3, injuryDaysMax = 14,
        },
        -- tier 3: 宽松
        {
            baseChance = 0.10,
            gapDivisor = 45,
            gapFloor = 0.4,
            youthGapDivisor = 40,
            youthGapFloor = 0.5,
            participationScale = 1.15,
            seasonEndGrowth = {
                u21 = 0.50,
                youngAdult = 0.44,
                peak = 0.125,
            },
            decline = { mid = 0.17, late = 0.34 },
            intensity = {
                low  = { growthMultiplier = 0.5, fitnessLoss = 1, injuryChance = 0.001, fitnessRecoveryBonus = 2 },
                medium = { growthMultiplier = 1.0, fitnessLoss = 1, injuryChance = 0.005, fitnessRecoveryBonus = 0 },
                high = { growthMultiplier = 1.8, fitnessLoss = 2, injuryChance = 0.012, fitnessRecoveryBonus = 0 },
            },
            weeklyInjury = { low = 0.002, medium = 0.008, high = 0.015 },
            injuryDaysMin = 3, injuryDaysMax = 12,
        },
    }
    return configs[tier] or configs[2]
end

--- 成长子系统摘要（日常训练 + 赛季末 + 出场挂钩，供 UI/测试）
function DifficultySettings.getGrowthModifiers()
    local t = DifficultySettings.getTrainingModifiers()
    return {
        dailyBaseChance = t.baseChance,
        gapDivisor = t.gapDivisor,
        gapFloor = t.gapFloor,
        participationScale = t.participationScale or 1.0,
        seasonEnd = t.seasonEndGrowth,
        decline = t.decline,
    }
end

------------------------------------------------------
-- 内部
------------------------------------------------------

function DifficultySettings._copyDefaults()
    local copy = {}
    for k, v in pairs(DifficultySettings.DEFAULTS) do
        copy[k] = v
    end
    return copy
end

return DifficultySettings
