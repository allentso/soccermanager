-- match/set_piece_resolver.lua
-- 定位球能力合成、主罚人解析与点球检定（FM 风格，无独立属性入库）
--
-- 设计要点：
-- * 不新增存档属性：FK/CR/PK 由现有 19 项属性运行时合成（1-20 量纲）
-- * 主罚人来源：team.penaltyTaker / freeKickTaker / cornerTaker（已有字段，
--   此前从未被引擎读取）；不可用时按合成能力自动推断
-- * 点球检定统一：场内点球与点球大战共用 takePenalty

local Player = require("scripts/domain/player")
local TraitEffects = require("scripts/match/trait_effects")

local SetPieceResolver = {}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function attr(player, key, fallback)
    local attributes = player and player.attributes or {}
    return attributes[key] or fallback or 10
end

local function has(player, traitId)
    return Player.hasTrait(player, traitId)
end

------------------------------------------------------
-- 合成定位球能力（1-20）
------------------------------------------------------

--- kind: "penalty" | "free_kick" | "corner"
function SetPieceResolver.synthSkill(player, kind)
    if not player then return 8 end
    local skill
    if kind == "penalty" then
        skill = attr(player, "shooting") * 0.45
            + attr(player, "composure") * 0.40
            + attr(player, "decisions") * 0.15
    elseif kind == "corner" then
        skill = attr(player, "passing") * 0.50
            + attr(player, "vision") * 0.30
            + attr(player, "composure") * 0.20
        if has(player, "crosser") then skill = skill * 1.12 end
    else -- free_kick
        skill = attr(player, "shooting") * 0.55
            + attr(player, "passing") * 0.25
            + attr(player, "composure") * 0.20
    end

    if has(player, "dead_ball") then
        local bonus = (kind == "corner") and 1.5 or ((kind == "penalty") and 2.0 or 2.5)
        -- 传奇共享特质放大与 trait_effects 一致
        if player.isLegend and Player.isLegendSharedTrait
            and Player.isLegendSharedTrait("dead_ball") then
            local Constants = require("scripts/app/constants")
            bonus = bonus * (Constants.LEGEND_SHARED_TRAIT_MULT or 1.0)
        end
        skill = skill + bonus
    end
    if has(player, "inconsistent") then
        skill = skill - 1.5
    end

    -- 门将不主罚（清道夫门将也只压到很低）
    if player.position == "GK" then
        skill = math.min(skill, 8)
    end
    return clamp(skill, 1, 22)
end

------------------------------------------------------
-- 主罚人解析
------------------------------------------------------

local TAKER_FIELD = {
    penalty = "penaltyTaker",
    free_kick = "freeKickTaker",
    corner = "cornerTaker",
}

--- 从场上球员中解析主罚人；指定主罚不在场则按合成能力推断
---@param context table TacticsResolver.buildTeamContext 结果
---@param kind string "penalty"|"free_kick"|"corner"
---@return table|nil taker
function SetPieceResolver.resolveTaker(context, kind)
    local players = context and context.players or {}
    if #players == 0 then return nil end

    local field = TAKER_FIELD[kind]
    local assignedId = field and context.team and context.team[field]
    if assignedId then
        for _, player in ipairs(players) do
            if player.id == assignedId and player.position ~= "GK" then
                return player
            end
        end
    end

    -- 自动推断：合成能力最高者（dead_ball 已含在合成值内）
    local best, bestScore = nil, -1
    for _, player in ipairs(players) do
        if player.position ~= "GK" then
            local score = SetPieceResolver.synthSkill(player, kind)
            if score > bestScore then
                best, bestScore = player, score
            end
        end
    end
    return best or players[1]
end

--- 自动分配球队三个主罚角色（写回 team 字段，供 UI 展示与存档）
function SetPieceResolver.autoAssign(gameState, team)
    local ids = {}
    for _, pid in pairs(team.startingXI or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not p.retired then
            table.insert(ids, p)
        end
    end
    if #ids == 0 then return end

    for kind, field in pairs(TAKER_FIELD) do
        local best, bestScore = nil, -1
        for _, p in ipairs(ids) do
            if p.position ~= "GK" then
                local score = SetPieceResolver.synthSkill(p, kind)
                if score > bestScore then best, bestScore = p, score end
            end
        end
        if best then team[field] = best.id end
    end
end

------------------------------------------------------
-- 争顶终结者 / 防空强度
------------------------------------------------------

local function positionGroup(position)
    if position == "GK" then return "GK" end
    if position == "CB" or position == "LB" or position == "RB" then return "DEF" end
    if position == "ST" or position == "CF" or position == "LW" or position == "RW" then return "FWD" end
    return "MID"
end

--- 角球/任意球争顶终结者（头球链）
function SetPieceResolver.pickAerialFinisher(context)
    local TacticsResolver = require("scripts/match/tactics_resolver")
    return TacticsResolver.chooseWeighted(context.players, function(player)
        if player.position == "GK" then return 0 end
        local group = positionGroup(player.position)
        local weight = attr(player, "aerial") * 2.0
            + attr(player, "strength") * 1.2
            + attr(player, "positioning") * 0.8
        if group == "FWD" then weight = weight * 1.30
        elseif player.position == "CB" then weight = weight * 1.15 end
        if has(player, "aerial_threat") then weight = weight * 1.35 end
        if has(player, "powerhouse") then weight = weight * 1.12 end
        return weight
    end)
end

--- 防守方防空强度（1-20 量纲：取最佳 3 名防空者均值，与单人属性可直接相减）
--- 防守端特质：空霸/力量怪兽/铜墙铁壁同样提升防定位球能力（与进攻端对称）
function SetPieceResolver.aerialDefense(context)
    local scores = {}
    for _, player in ipairs(context and context.players or {}) do
        if player.position ~= "GK" then
            local score = attr(player, "aerial") * 0.6
                + attr(player, "strength") * 0.25
                + attr(player, "positioning") * 0.15
            if has(player, "aerial_threat") then score = score + 1.2 end
            if has(player, "powerhouse") then score = score + 0.8 end
            if has(player, "brick_wall") then score = score + 0.8 end
            table.insert(scores, score)
        end
    end
    table.sort(scores, function(a, b) return a > b end)
    local n = math.min(3, #scores)
    if n == 0 then return 10 end
    local sum = 0
    for i = 1, n do sum = sum + scores[i] end
    return sum / n
end

------------------------------------------------------
-- 点球（场内与点球大战统一）
------------------------------------------------------

--- 点球命中概率（不掷骰）
function SetPieceResolver.penaltyChance(kicker, goalkeeper)
    local pk = SetPieceResolver.synthSkill(kicker, "penalty")
    local kickerScore = pk + attr(kicker, "composure", 10) * 0.5
        + ((kicker and kicker.morale or 60) - 50) * 0.02
    local keeperScore = attr(goalkeeper, "reflexes", 5)
        + attr(goalkeeper, "handling", 5) * 0.5
    local chance = clamp(0.76 + (kickerScore - keeperScore) / 110, 0.55, 0.92)
    chance = TraitEffects.modifyPenaltyChance(kicker, goalkeeper, chance)
    return clamp(chance, 0.45, 0.96)
end

--- 掷骰版（点球大战使用）
function SetPieceResolver.takePenalty(kicker, goalkeeper)
    return Random() < SetPieceResolver.penaltyChance(kicker, goalkeeper)
end

--- 点球大战主罚排序分（指定主罚人置顶）
function SetPieceResolver.shootoutScore(player, team)
    local score = SetPieceResolver.synthSkill(player, "penalty")
        + attr(player, "shooting") * 0.3
    score = TraitEffects.penaltyKickerScore(player, score)
    if team and team.penaltyTaker == player.id then
        score = score + 100  -- 指定主罚永远第一个踢
    end
    return score
end

return SetPieceResolver
