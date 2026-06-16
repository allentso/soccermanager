-- scripts/match/trait_effects.lua
-- 球员特质在比赛中的唯一效果（战术聚合 + 事件权重）

local Player = require("scripts/domain/player")
local Constants = require("scripts/app/constants")

local TraitEffects = {}

local LEGEND_SHARED_MULT = Constants.LEGEND_SHARED_TRAIT_MULT

local function has(player, traitId)
    return Player.hasTrait(player, traitId)
end

--- 传奇 + 共享特质：加成数值放大
local function legendSharedActive(player, traitId)
    return player and player.isLegend and has(player, traitId)
        and Player.isLegendSharedTrait(traitId)
end

local function scaleAdd(player, traitId, amount)
    if legendSharedActive(player, traitId) then
        return amount * LEGEND_SHARED_MULT
    end
    return amount
end

--- 乘性增益（如射门权重 ×1.38）
local function scaleMult(player, traitId, multiplier)
    if legendSharedActive(player, traitId) then
        return 1 + (multiplier - 1) * LEGEND_SHARED_MULT
    end
    return multiplier
end

--- 乘性减益（如黄牌权重 ×0.50、犯规率 ×0.90，越低越好）
local function scaleReduction(player, traitId, multiplier)
    if legendSharedActive(player, traitId) then
        return 1 - (1 - multiplier) * LEGEND_SHARED_MULT
    end
    return multiplier
end

local function bump(acc, field, player, traitId, amount)
    if has(player, traitId) then
        acc[field] = (acc[field] or 0) + scaleAdd(player, traitId, amount)
    end
end

local function isWide(player)
    local pos = player and player.position or ""
    return pos == "LW" or pos == "RW" or pos == "LB" or pos == "RB"
        or pos == "LWB" or pos == "RWB"
end

local function isFullback(player)
    local pos = player and player.position or ""
    return pos == "LB" or pos == "RB" or pos == "LWB" or pos == "RWB"
end

local function isDeepMid(player)
    local pos = player and player.position or ""
    return pos == "CM" or pos == "CDM" or pos == "DM"
end

--- 战术上下文：每名首发球员的特质累加到球队维度
---@param player table
---@param group string GK|DEF|MID|FWD
---@param acc table mutable accumulator
function TraitEffects.applyTeamContribution(player, group, acc)
    if group == "GK" then
        bump(acc, "defense", player, "shot_stopper", 2.8)
        if has(player, "sweeper_keeper") then
            bump(acc, "possession", player, "sweeper_keeper", 1.2)
            bump(acc, "defense", player, "sweeper_keeper", 1.0)
            bump(acc, "counter", player, "sweeper_keeper", 0.05)
        end
        return
    end

    bump(acc, "shotQuality", player, "clinical", 1.3)
    if has(player, "poacher") and group == "FWD" then
        bump(acc, "attack", player, "poacher", 1.0)
    end
    if has(player, "long_shot") and (group == "MID" or group == "FWD") then
        acc.shotQuality = acc.shotQuality + 0.75
    end
    if has(player, "dribbler") and (group == "MID" or group == "FWD") then
        bump(acc, "attack", player, "dribbler", 0.95)
    end
    if has(player, "trickster") and (group == "MID" or group == "FWD") then
        acc.attack = acc.attack + 1.15
        acc.possession = acc.possession + 0.45
    end
    if has(player, "playmaker") then
        bump(acc, "possession", player, "playmaker", 1.8)
        bump(acc, "attack", player, "playmaker", 0.85)
    end
    if has(player, "visionary") then
        acc.possession = acc.possession + 1.5
    end
    if has(player, "distributor") then
        acc.possession = acc.possession + 2.1
    end
    if has(player, "crosser") then
        acc.aerial = acc.aerial + 1.05
        if isWide(player) then acc.attack = acc.attack + 0.55 end
    end
    if has(player, "ball_playing_defender") and group == "DEF" then
        acc.possession = acc.possession + 1.15
        acc.attack = acc.attack + 0.45
    end
    if has(player, "libero") and group == "DEF" then
        acc.defense = acc.defense + 1.25
        acc.possession = acc.possession + 0.85
        acc.counter = acc.counter + 0.03
    end
    if has(player, "box_to_box") and group == "MID" then
        acc.attack = acc.attack + 0.65
        acc.defense = acc.defense + 0.65
    end
    if has(player, "overlapper") and isFullback(player) then
        acc.attack = acc.attack + 1.05
        acc.counter = acc.counter + 0.035
    end
    if has(player, "brick_wall") and group == "DEF" then
        acc.defense = acc.defense + 1.85
    end
    if has(player, "ball_winner") then
        bump(acc, "defense", player, "ball_winner", 0.95)
        bump(acc, "press", player, "ball_winner", 0.03)
    end
    bump(acc, "aerial", player, "aerial_threat", 1.65)
    if has(player, "powerhouse") and (group == "DEF" or group == "MID") then
        acc.aerial = acc.aerial + 0.75
        acc.defense = acc.defense + 0.55
    end
    if has(player, "pace_merchant") and (group == "MID" or group == "FWD") then
        bump(acc, "counter", player, "pace_merchant", 0.045)
        bump(acc, "tempo", player, "pace_merchant", 0.018)
    end
    bump(acc, "stamina", player, "engine", 2.25)
    if has(player, "dead_ball") then
        bump(acc, "shotQuality", player, "dead_ball", 0.95)
        bump(acc, "setPieceMult", player, "dead_ball", 0.07)
    end
    bump(acc, "discipline", player, "captain", 4.0)
    if has(player, "team_player") then
        acc.possession = acc.possession + 0.75
        acc.discipline = acc.discipline + 1.0
    end
    if has(player, "big_game") then
        acc.shotQuality = acc.shotQuality + 0.65
        acc.defense = acc.defense + 0.55
    end
    if has(player, "inconsistent") then
        acc.shotQuality = acc.shotQuality - 0.85
        acc.formVolatility = acc.formVolatility + 0.05
    end
    if has(player, "wonderkid") then
        acc.attack = acc.attack + 0.55
    end
    if has(player, "veteran") then
        acc.discipline = acc.discipline + 2.5
        acc.defense = acc.defense + 0.5
    end
end

---@return table fresh team trait summary
function TraitEffects.newTeamAccumulator()
    return {
        setPieceMult = 1.0,
        saveBonus = 0,
        foulMult = 1.0,
        tempo = 0,
        counter = 0,
        press = 0,
        formVolatility = 0,
        bigGameBoost = 0,
    }
end

--- 遍历阵容后汇总特质标签（定位球、门将、犯规、状态波动）
---@param players table[]
---@param acc table from newTeamAccumulator fields merged during applyTeamContribution
---@return table traitSummary
function TraitEffects.finalizeTeamSummary(players, acc)
    local summary = {
        setPieceMult = acc.setPieceMult or 1.0,
        saveBonus = acc.saveBonus or 0,
        foulMult = acc.foulMult or 1.0,
        tempo = acc.tempo or 0,
        counter = acc.counter or 0,
        press = acc.press or 0,
        formVolatility = acc.formVolatility or 0,
        bigGameBoost = acc.bigGameBoost or 0,
    }

    for _, player in ipairs(players or {}) do
        if has(player, "captain") then
            summary.foulMult = summary.foulMult * scaleReduction(player, "captain", 0.90)
        end
        if has(player, "shot_stopper") and player.position == "GK" then
            summary.saveBonus = summary.saveBonus + scaleAdd(player, "shot_stopper", 0.014)
        end
        if has(player, "sweeper_keeper") and player.position == "GK" then
            summary.saveBonus = summary.saveBonus + scaleAdd(player, "sweeper_keeper", 0.007)
        end
        if has(player, "distributor") then
            summary.tempo = summary.tempo + 0.014
        end
        if has(player, "big_game") then
            summary.bigGameBoost = summary.bigGameBoost + 0.018
        end
    end

    -- 定位球触发上限收紧：dead_ball 主要强度已转入 FK/CR/PK 合成（set_piece_resolver）
    -- 双重叠乘下限制机会倍率，避免特质队定位球贡献超 +25%
    summary.setPieceMult = math.min(1.25, summary.setPieceMult)
    summary.saveBonus = math.min(0.06, summary.saveBonus)
    summary.foulMult = math.max(0.65, summary.foulMult)
    summary.formVolatility = math.min(0.22, summary.formVolatility)
    summary.bigGameBoost = math.min(0.08, summary.bigGameBoost)
    return summary
end

--- 采样单场状态（大场面更稳、状态起伏更波动）
--- v2: 基础范围从 ±18% 压缩到 ±12%，让战术决策的信噪比从 ~1:4 提升到 ~1:1.5
function TraitEffects.sampleFormFactor(traitSummary, baseForm)
    baseForm = baseForm or (0.88 + Random() * 0.24)  -- [0.88, 1.12] (±12%)
    local summary = traitSummary or {}
    local volatility = summary.formVolatility or 0
    if volatility > 0 then
        baseForm = baseForm + (Random() - 0.5) * volatility
    end
    local boost = summary.bigGameBoost or 0
    if boost > 0 then
        baseForm = baseForm + boost * 0.35
    end
    if baseForm < 0.76 then return 0.76 end
    if baseForm > 1.18 then return 1.18 end
    return baseForm
end

---@param player table
---@param group string
---@param weight number
---@param opts table|nil { isSetPiece: boolean }
function TraitEffects.modifyShooterWeight(player, group, weight, opts)
    opts = opts or {}
    if has(player, "poacher") and group == "FWD" then
        weight = weight * scaleMult(player, "poacher", 1.38)
    end
    if has(player, "clinical") then
        weight = weight * scaleMult(player, "clinical", 1.10)
    end
    if has(player, "long_shot") and group == "MID" then
        weight = weight * 1.24
    end
    if has(player, "dribbler") and (group == "FWD" or player.position == "CAM") then
        weight = weight * scaleMult(player, "dribbler", 1.20)
    end
    if has(player, "trickster") and (group == "FWD" or group == "MID" or player.position == "CAM") then
        weight = weight * 1.16
    end
    if opts.isSetPiece and has(player, "aerial_threat") then
        weight = weight * scaleMult(player, "aerial_threat", 1.28)
    end
    if opts.isSetPiece and has(player, "powerhouse") then
        weight = weight * 1.12
    end
    return weight
end

---@param player table
---@param group string
---@param weight number
function TraitEffects.modifyAssisterWeight(player, group, weight)
    if has(player, "playmaker") and (group == "MID" or player.position == "CAM") then
        weight = weight * scaleMult(player, "playmaker", 1.34)
    end
    if has(player, "visionary") then
        weight = weight * 1.26
        if group == "DEF" or isDeepMid(player) then weight = weight * 1.12 end
    end
    if has(player, "distributor") and (group == "MID" or group == "DEF") then
        weight = weight * 1.26
    end
    if has(player, "crosser") and isWide(player) then
        weight = weight * 1.40
    end
    if has(player, "overlapper") and isFullback(player) then
        weight = weight * 1.32
    end
    if has(player, "ball_playing_defender") and group == "DEF" then
        weight = weight * 1.20
    end
    if has(player, "libero") and group == "DEF" then
        weight = weight * 1.18
    end
    if has(player, "team_player") then
        weight = weight * 1.08
    end
    return weight
end

---@param shooter table
---@param group string
---@param onTargetChance number
function TraitEffects.modifyOnTargetChance(shooter, group, onTargetChance)
    if has(shooter, "clinical") then
        onTargetChance = onTargetChance + scaleAdd(shooter, "clinical", 0.045)
    end
    if has(shooter, "poacher") and group == "FWD" then
        onTargetChance = onTargetChance + scaleAdd(shooter, "poacher", 0.028)
    end
    if has(shooter, "long_shot") and group == "MID" then
        onTargetChance = onTargetChance - 0.028
    end
    if has(shooter, "dribbler") then
        onTargetChance = onTargetChance + scaleAdd(shooter, "dribbler", 0.018)
    end
    if has(shooter, "inconsistent") then
        onTargetChance = onTargetChance - 0.035
    end
    return onTargetChance
end

---@param shooter table
---@param group string
---@param goalChance number
---@param opts table|nil { isSetPiece: boolean, defenderSaveBonus: number }
function TraitEffects.modifyGoalChance(shooter, group, goalChance, opts)
    opts = opts or {}
    if has(shooter, "clinical") then
        goalChance = goalChance + scaleAdd(shooter, "clinical", 0.034)
    end
    if has(shooter, "poacher") and group == "FWD" then
        goalChance = goalChance + scaleAdd(shooter, "poacher", 0.016)
    end
    if has(shooter, "long_shot") and group == "MID" then
        goalChance = goalChance + 0.020
    end
    if has(shooter, "trickster") then
        goalChance = goalChance + 0.012
    end
    if has(shooter, "big_game") then
        goalChance = goalChance + 0.014
    end
    if opts.isSetPiece then
        if has(shooter, "dead_ball") then
            goalChance = goalChance + scaleAdd(shooter, "dead_ball", 0.022)
        end
        if has(shooter, "aerial_threat") then
            goalChance = goalChance + scaleAdd(shooter, "aerial_threat", 0.018)
        end
    end
    if has(shooter, "inconsistent") then
        goalChance = goalChance - 0.018
    end
    local saveBonus = opts.defenderSaveBonus or 0
    if saveBonus > 0 then
        goalChance = goalChance - saveBonus
    end
    return goalChance
end

---@param player table
---@param weight number
function TraitEffects.modifyCardWeight(player, weight)
    if has(player, "captain") then
        weight = weight * scaleReduction(player, "captain", 0.50)
    end
    if has(player, "team_player") then
        weight = weight * 0.82
    end
    if has(player, "ball_winner") then
        weight = weight * 1.28
    end
    if has(player, "inconsistent") then
        weight = weight * 1.18
    end
    if has(player, "veteran") then
        weight = weight * 0.88
    end
    return weight
end

---@param kicker table
---@param goalkeeper table|nil
---@param chance number
function TraitEffects.modifyPenaltyChance(kicker, goalkeeper, chance)
    if kicker and has(kicker, "dead_ball") then
        chance = chance + scaleAdd(kicker, "dead_ball", 0.045)
    end
    if kicker and has(kicker, "clinical") then
        chance = chance + scaleAdd(kicker, "clinical", 0.035)
    end
    if kicker and has(kicker, "big_game") then
        chance = chance + 0.025
    end
    if kicker and has(kicker, "inconsistent") then
        chance = chance - 0.04
    end
    if goalkeeper and has(goalkeeper, "shot_stopper") then
        chance = chance - scaleAdd(goalkeeper, "shot_stopper", 0.05)
    end
    if goalkeeper and has(goalkeeper, "sweeper_keeper") then
        chance = chance - scaleAdd(goalkeeper, "sweeper_keeper", 0.025)
    end
    return chance
end

--- 点球主罚优先级加分（用于排序）
function TraitEffects.penaltyKickerScore(player, baseScore)
    local score = baseScore
    if has(player, "dead_ball") then score = score + scaleAdd(player, "dead_ball", 4.5) end
    if has(player, "clinical") then score = score + scaleAdd(player, "clinical", 3.0) end
    if has(player, "poacher") then score = score + scaleAdd(player, "poacher", 1.5) end
    if has(player, "inconsistent") then score = score - 2.0 end
    return score
end

return TraitEffects
