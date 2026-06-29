-- match/tactics_resolver.lua
-- Pure tactical calculations shared by the match engine and tests.

local Constants = require("scripts/app/constants")
local FormationShape = require("scripts/match/formation_shape")
local PositionFit = require("scripts/domain/position_fit")
local Team = require("scripts/domain/team")
local TraitEffects = require("scripts/match/trait_effects")
local RoleSynergy = require("scripts/match/role_synergy")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local Nationality = require("scripts/domain/nationality")

local TacticsResolver = {}

TacticsResolver.ATTACK_MODES = {
    shortPassing = { attack = 1.02, possession = 1.08, tempo = 0.94, shotQuality = 1.03 },
    longBall = { attack = 1.03, possession = 0.92, tempo = 1.08, aerial = 1.12 },
    wingPlay = { attack = 1.05, possession = 0.98, tempo = 1.05, crossing = 1.12 },
    throughBalls = { attack = 1.07, possession = 0.98, tempo = 1.06, shotQuality = 1.08 },
    balanced = { attack = 1.0, possession = 1.0, tempo = 1.0, shotQuality = 1.0 },
}

local STYLE_MODIFIERS = {
    Balanced   = { attack = 1.0,  defense = 1.0,  possession = 1.0,  tempo = 1.0,  press = 1.0,  foul = 1.0,  staminaDrain = 1.0,  injury = 1.0 },
    Attacking  = { attack = 1.11, defense = 0.92, possession = 1.03, tempo = 1.08, press = 1.04, foul = 1.03, staminaDrain = 1.08, injury = 1.0 },
    Defensive  = { attack = 0.90, defense = 1.16, possession = 0.94, tempo = 0.92, press = 0.96, foul = 1.08, staminaDrain = 0.82, injury = 0.92 },
    Possession = { attack = 0.98, defense = 1.04, possession = 1.16, tempo = 0.9,  press = 0.97, foul = 0.92, staminaDrain = 0.88, injury = 0.95 },
    Counter    = { attack = 1.04, defense = 1.02, possession = 0.9,  tempo = 1.12, press = 0.96, foul = 1.0,  staminaDrain = 1.05, injury = 1.0,  counter = 1.12 },
    HighPress  = { attack = 1.06, defense = 0.97, possession = 1.06, tempo = 1.14, press = 1.18, foul = 1.12, staminaDrain = 1.22, injury = 1.08 },
}

--- 获取指定风格的修正系数表（公开方法，供外部快速读取 staminaDrain 等字段）
function TacticsResolver.getStyleModifiers(styleName)
    return STYLE_MODIFIERS[styleName] or STYLE_MODIFIERS.Balanced
end

-- 赛后体力消耗基准（位置组 → {min, max}；2026-06 下调约 35% 以匹配恢复速率）
TacticsResolver.POSITION_STAMINA_DRAIN = {
    GK  = { 5, 8 },
    DEF = { 9, 13 },
    MID = { 12, 17 },
    FWD = { 10, 14 },
}

-- 风格×位置协同加成 (对特定位置组产生额外乘数)
local STYLE_POSITION_SYNERGY = {
    Attacking  = { FWD = { attack = 1.08 } },
    Defensive  = { DEF = { defense = 1.06 } },
    Possession = { MID = { possession = 1.10 } },
    Counter    = { FWD = { attack = 1.06 } },  -- 快速前锋在 buildTeamContext 中额外判断 speed
    HighPress  = { MID = { press = 1.08 } },   -- 高耐力中场在 buildTeamContext 中额外判断
}

-- 阵型-风格兼容度 (formation defCount → style → multiplier)
local FORMATION_STYLE_SYNERGY = {
    -- { defCount条件, style, 维度, 乘数 }
    { cond = function(d) return d >= 5 end, style = "Counter",    dim = "counter",    mul = 1.05 },
    { cond = function(d) return d >= 5 end, style = "HighPress",  dim = "press",      mul = 0.95 },
    { cond = function(d) return d >= 5 end, style = "Possession", dim = "possession", mul = 1.03 },
    { cond = function(d) return d <= 3 end, style = "Defensive",  dim = "defense",    mul = 0.96 },
    { cond = function(d) return d <= 3 end, style = "Attacking",  dim = "attack",     mul = 1.02 },
}

local DUTIES = {
    attack = { attack = 1.18, defense = 0.86 },
    support = { attack = 1.0, defense = 1.0 },
    defend = { attack = 0.86, defense = 1.18 },
}

-- P1-3: 进攻模式与角色契合度映射表
local ATTACK_MODE_ROLE_FIT = {
    wingPlay = {
        roles = { touchline = true, winger = true, wide = true, wingBack = true },
        dim = "attack", perPlayer = 0.02, cap = 0.06,
    },
    throughBalls = {
        roles = { shadow = true, poacher = true, advanced = true },
        dim = "shotQuality", perPlayer = 0.03, cap = 0.09,
    },
    shortPassing = {
        roles = { deepLying = true, ballPlaying = true, playmaker = true },
        dim = "possession", perPlayer = 0.02, cap = 0.06,
    },
    longBall = {
        roles = { targetMan = true },
        dim = "aerial", perPlayer = 0.04, cap = 0.04,
        extraDim = "attack", extraPer = 0.02, extraCap = 0.02,
    },
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

-- chanceCreation 钳制：保留 50% 实力压缩与 ±18% 状态波动，仅抬高上限避免强队恒撞顶
-- 旧上限 1.70 时 dampedRatio≈2.08 几乎必达顶；2.40 时强打弱约 8% 撞顶、均值不再锁死
local CHANCE_CREATION_MIN = 0.55
-- 测试可经 _G.BALANCE_SIM_CC_MAX 覆盖上限（全面模拟对比用）
local CHANCE_CREATION_MAX = _G.BALANCE_SIM_CC_MAX or 2.40

-- 攻防量纲校准：buildTeamContext 的防守权重总和约为进攻的1.4倍
-- （4-4-2 全员同属性实测 defense/attack≈1.41），比值计算前先归一，
-- 否则同实力对局 attackVsDefense 恒 <1，20分OVR差在比值中几乎消失
TacticsResolver.DEF_TO_ATK_SCALE = 1.40

-- 实力差直通系数：保留首发 OVR 锚点，但降低斜率，避免进攻属性先进入 attack/shotQuality
-- 后又通过高 OVR 二次放大机会创造。
local STRENGTH_GAP_SLOPE = 0.006
local STRENGTH_FACTOR_MIN, STRENGTH_FACTOR_MAX = 0.82, 1.18

local function attr(player, key, fallback)
    local attributes = player.attributes or {}
    return attributes[key] or fallback or 10
end

--- 获取带角色修正的属性值
local function roleAttr(player, key, modifiers, fallback)
    local base = attr(player, key, fallback)
    if modifiers and modifiers[key] then
        return base * modifiers[key]
    end
    return base
end

local function positionGroup(position)
    if position == "GK" then return "GK" end
    if position == "CB" or position == "LB" or position == "RB" then return "DEF" end
    if position == "ST" or position == "LW" or position == "RW" then return "FWD" end
    return "MID"
end

function TacticsResolver.getMatchPlayers(gameState, team)
    local players = {}
    local effectiveXI = Team.buildEffectiveStartingXI(gameState, team)
    for i = 1, 11 do
        local playerId = effectiveXI[i]
        local player = playerId and gameState.players[playerId]
        if player then
            table.insert(players, player)
        end
    end
    return players
end

function TacticsResolver.calculateChemistry(players)
    if #players < 2 then return 1.0 end

    local total = 0
    local pairs = 0
    for i = 1, #players do
        for j = i + 1, #players do
            local first = players[i]
            local second = players[j]
            local bond = 0.5
            if first.nationality and Nationality.matches(first.nationality, second.nationality) then
                bond = bond + 0.18
            end
            if positionGroup(first.position) == positionGroup(second.position) then
                bond = bond + 0.12
            end
            local apps = math.min(
                (first.seasonStats and first.seasonStats.appearances) or 0,
                (second.seasonStats and second.seasonStats.appearances) or 0
            )
            bond = bond + math.min(0.35, apps * 0.02)
            total = total + math.min(1.25, bond)
            pairs = pairs + 1
        end
    end

    if pairs == 0 then return 1.0 end
    return clamp(0.94 + (total / pairs) * 0.11, 0.94, 1.08)
end

function TacticsResolver.buildTeamContext(gameState, team)
    local players = TacticsResolver.getMatchPlayers(gameState, team)
    local style = team.playStyle or "Balanced"
    local styleMod = STYLE_MODIFIERS[style] or STYLE_MODIFIERS.Balanced
    local mode = team.attackMode or "balanced"
    local modeMod = TacticsResolver.ATTACK_MODES[mode] or TacticsResolver.ATTACK_MODES.balanced
    local duties = team.playerDuties or {}

    local attack = 0
    local defense = 0
    local possession = 0
    local discipline = 0
    local stamina = 0
    local morale = 0
    local shotQuality = 0
    local aerial = 0
    local counts = { GK = 0, DEF = 0, MID = 0, FWD = 0 }
    local traitAcc = {
        setPieceMult = 1.0,
        saveBonus = 0,
        foulMult = 1.0,
        tempo = 0,
        counter = 0,
        press = 0,
        formVolatility = 0,
        bigGameBoost = 0,
    }

    -- 角色修正：根据 slotRoles + 槽位类型获取 modifiers
    local slotRoles = team.slotRoles or {}
    local startingXI = Team.buildEffectiveStartingXI(gameState, team)
    local formation = team.formation or "4-4-2"
    local slots = FormationShape.getFormationSlots(team)

    -- 建立 playerId -> slotIndex 映射
    local playerSlotIndex = {}
    for i = 1, 11 do
        local pid = startingXI[i]
        if pid then
            playerSlotIndex[pid] = i
        end
    end

    for _, player in ipairs(players) do
        local slotIdx = playerSlotIndex[player.id]
        local slotPos = slotIdx and slots[slotIdx]
        local group = positionGroup(slotPos or player.position)
        counts[group] = counts[group] + 1

        -- 查找该球员的角色修正系数（按槽位类型，非注册位置）
        local mods = nil
        local roleKey = (slotIdx and slotRoles[slotIdx]) or "default"
        if slotIdx and slotPos and slotRoles[slotIdx] then
            local role = Constants.getPositionRole(slotPos, slotRoles[slotIdx])
            if role then mods = role.modifiers end
        end

        -- P2-1: 附加位置区域和角色信息到球员对象（供 pickShooter/pickAssister 使用）
        player._slotZone = group   -- "GK"/"DEF"/"MID"/"FWD"
        player._roleKey = roleKey  -- 角色 key（如 "poacher", "playmaker"）
        player._slotPos = slotPos  -- 精确槽位（如 "ST", "CAM", "RW"）

        local fitnessMods = DifficultySettings.getFitnessModifiers()
        local fitnessMul = clamp((player.fitness or 80) / 100, fitnessMods.fitnessMulMin, 1.05)
        local moraleMul = clamp(0.82 + ((player.morale or 60) / 100) * 0.28, 0.82, 1.1)
        local duty = DUTIES[duties[player.id] or "support"] or DUTIES.support

        local playerAttack = 0
        local playerDefense = 0
        if group == "GK" then
            playerDefense = roleAttr(player, "reflexes", mods, 5) * 2.4 + roleAttr(player, "handling", mods, 5) * 1.8 + roleAttr(player, "positioning", mods) * 1.0
            possession = possession + roleAttr(player, "passing", mods) * 0.35 + roleAttr(player, "decisions", mods) * 0.3
        elseif group == "DEF" then
            playerAttack = roleAttr(player, "passing", mods) * 0.55 + roleAttr(player, "aerial", mods) * 0.25
            playerDefense = roleAttr(player, "defending", mods) * 2.0 + roleAttr(player, "tackling", mods) * 1.4 + roleAttr(player, "positioning", mods) * 1.1
            possession = possession + roleAttr(player, "passing", mods) * 0.75 + roleAttr(player, "decisions", mods) * 0.55
        elseif group == "MID" then
            playerAttack = roleAttr(player, "passing", mods) * 1.15 + roleAttr(player, "vision", mods) * 1.0 + roleAttr(player, "shooting", mods) * 0.55
            playerDefense = roleAttr(player, "tackling", mods) * 0.9 + roleAttr(player, "positioning", mods) * 0.75 + roleAttr(player, "teamwork", mods) * 0.45
            possession = possession + roleAttr(player, "passing", mods) * 1.2 + roleAttr(player, "vision", mods) * 0.95 + roleAttr(player, "decisions", mods) * 0.85
        else
            playerAttack = roleAttr(player, "shooting", mods) * 1.65 + roleAttr(player, "dribbling", mods) * 0.9 + roleAttr(player, "positioning", mods) * 1.0
            playerDefense = roleAttr(player, "teamwork", mods) * 0.35 + roleAttr(player, "aggression", mods) * 0.25
            possession = possession + roleAttr(player, "dribbling", mods) * 0.8 + roleAttr(player, "passing", mods) * 0.65
        end

        do
            local delta = {
                attack = 0, defense = 0, possession = 0, shotQuality = 0, aerial = 0,
                stamina = 0, discipline = 0, counter = 0, press = 0, tempo = 0,
                setPieceMult = traitAcc.setPieceMult,
                formVolatility = traitAcc.formVolatility,
                bigGameBoost = traitAcc.bigGameBoost,
            }
            TraitEffects.applyTeamContribution(player, group, delta)
            attack = attack + delta.attack
            defense = defense + delta.defense
            possession = possession + delta.possession
            shotQuality = shotQuality + delta.shotQuality
            aerial = aerial + delta.aerial
            stamina = stamina + delta.stamina
            discipline = discipline + delta.discipline
            traitAcc.counter = traitAcc.counter + (delta.counter or 0)
            traitAcc.press = traitAcc.press + (delta.press or 0)
            traitAcc.tempo = traitAcc.tempo + (delta.tempo or 0)
            traitAcc.setPieceMult = delta.setPieceMult
            traitAcc.formVolatility = delta.formVolatility
            traitAcc.bigGameBoost = delta.bigGameBoost
        end

        -- 风格×位置协同加成
        local synergy = STYLE_POSITION_SYNERGY[style]
        local groupSynergy = synergy and synergy[group]
        local synergyAttack = 1.0
        local synergyDefense = 1.0
        if groupSynergy then
            synergyAttack = groupSynergy.attack or 1.0
            synergyDefense = groupSynergy.defense or 1.0
            if groupSynergy.possession then
                possession = possession + playerAttack * 0.08  -- 间接提升控球贡献
            end
        end
        -- Counter 特殊：快速前锋额外加成
        if style == "Counter" and group == "FWD" and attr(player, "speed") >= 14 then
            synergyAttack = synergyAttack + 0.04
        end
        -- HighPress 特殊：高耐力中场额外加成
        if style == "HighPress" and group == "MID" and attr(player, "stamina") >= 14 then
            synergyAttack = synergyAttack + 0.03
        end

        local positionFitMul = PositionFit.getFitMul(player, slotPos)
        attack = attack + playerAttack * fitnessMul * moraleMul * duty.attack * synergyAttack * positionFitMul
        defense = defense + playerDefense * fitnessMul * moraleMul * duty.defense * synergyDefense * positionFitMul
        discipline = discipline + (21 - roleAttr(player, "aggression", mods)) + roleAttr(player, "decisions", mods) * 0.45
        stamina = stamina + roleAttr(player, "stamina", mods) * fitnessMul
        morale = morale + (player.morale or 60)
        shotQuality = shotQuality + roleAttr(player, "composure", mods) * 0.35 + roleAttr(player, "shooting", mods) * 0.25
        aerial = aerial + roleAttr(player, "aerial", mods) * 0.25
    end

    local playerCount = math.max(1, #players)
    local chemistry = TacticsResolver.calculateChemistry(players)
    local shapeAnalysis = FormationShape.analyze(team)
    local defenderCount = (shapeAnalysis.lineCounts and shapeAnalysis.lineCounts.DEF) or counts.DEF
    local shapeMods = shapeAnalysis.combinedMods or {}

    local formationAttack = 1.0
    local formationDefense = 1.0
    if defenderCount >= 5 then
        formationAttack = 0.92
        formationDefense = 1.1
    elseif defenderCount <= 3 then
        formationAttack = 1.07
        formationDefense = 0.92
    end

    local avgFitness = 0
    local ovrSum = 0
    for _, player in ipairs(players) do
        avgFitness = avgFitness + (player.fitness or 80)
        ovrSum = ovrSum + (player.overall or 60)
    end
    avgFitness = avgFitness / playerCount

    local finalAttack = math.max(1, attack / 10 * styleMod.attack * (modeMod.attack or 1.0) * formationAttack * chemistry * (shapeMods.attack or 1.0))
    local finalDefense = math.max(1, defense / 10 * styleMod.defense * formationDefense * chemistry * (shapeMods.defense or 1.0))
    local finalPossession = math.max(1, possession / 10 * styleMod.possession * (modeMod.possession or 1.0) * chemistry * (shapeMods.possession or 1.0))
    local finalPress = clamp((styleMod.press or 1.0) * (shapeMods.press or 1.0), 0.75, 1.35)

    -- 前场堆叠仍能提供压制，但中场与防线承压会传导到控球、防守与最终射门链。
    local fwdOverload = math.max(0, counts.FWD - 2)
    local midfieldShortage = math.max(0, 3 - counts.MID)
    if fwdOverload > 0 then
        finalAttack = finalAttack * clamp(1.0 - fwdOverload * 0.012, 0.94, 1.0)
        finalDefense = finalDefense * clamp(1.0 - fwdOverload * 0.025 - midfieldShortage * 0.020, 0.88, 1.0)
        finalPossession = finalPossession * clamp(1.0 - fwdOverload * 0.020 - midfieldShortage * 0.030, 0.86, 1.0)
    end

    -- 阵型-风格兼容度修正
    for _, rule in ipairs(FORMATION_STYLE_SYNERGY) do
        if rule.style == style and rule.cond(defenderCount) then
            if rule.dim == "attack" then finalAttack = finalAttack * rule.mul
            elseif rule.dim == "defense" then finalDefense = finalDefense * rule.mul
            elseif rule.dim == "possession" then finalPossession = finalPossession * rule.mul
            elseif rule.dim == "counter" then -- applied below
            elseif rule.dim == "press" then finalPress = finalPress * rule.mul
            end
        end
    end

    -- 阵型-风格 counter 修正
    local finalCounter = (styleMod.counter or 1.0) * (shapeMods.counter or 1.0)
    for _, rule in ipairs(FORMATION_STYLE_SYNERGY) do
        if rule.style == style and rule.dim == "counter" and rule.cond(defenderCount) then
            finalCounter = finalCounter * rule.mul
        end
    end

    local traitSummary = TraitEffects.finalizeTeamSummary(players, traitAcc)
    finalCounter = finalCounter + traitSummary.counter
    finalPress = finalPress + traitSummary.press
    local finalTempo = clamp(styleMod.tempo * (modeMod.tempo or 1.0) * (shapeMods.tempo or 1.0) + traitSummary.tempo, 0.75, 1.40)
    local finalFoulRate = clamp(
        (styleMod.foul or 1.0) * (100 / math.max(30, discipline / playerCount * 8)) * traitSummary.foulMult,
        0.55, 1.55)

    -- P1-1: 角色协同加成
    local synergyMods, synergyTags = RoleSynergy.evaluate(players, slots, slotRoles, startingXI)
    finalAttack = finalAttack * (synergyMods.attack or 1.0)
    finalDefense = finalDefense * (synergyMods.defense or 1.0)
    finalPossession = finalPossession * (synergyMods.possession or 1.0)
    finalTempo = finalTempo * (synergyMods.tempo or 1.0)
    finalPress = finalPress * (synergyMods.press or 1.0)
    finalCounter = finalCounter * (synergyMods.counter or 1.0)
    shotQuality = shotQuality * (synergyMods.shotQuality or 1.0)
    aerial = aerial * (synergyMods.aerial or 1.0)

    -- P1-2: 职责极端失衡惩罚（仅极端场景，不惩罚正常倾向性）
    local dutyDist = { attack = 0, support = 0, defend = 0 }
    for i = 1, 11 do
        local pid = startingXI[i]
        if pid and i ~= 1 then  -- 排除 GK（slotIdx=1）
            local d = duties[pid] or "support"
            dutyDist[d] = (dutyDist[d] or 0) + 1
        end
    end
    -- 后卫全设为 support/attack 无人专注防守 → 防守脆弱
    if dutyDist.defend == 0 and counts.DEF >= 3 then
        finalDefense = finalDefense * 0.95
    end
    -- 全守极端：无人 attack 且 support ≤ 2 → 进攻乏力
    if dutyDist.attack == 0 and dutyDist.support <= 2 then
        finalAttack = finalAttack * 0.94
    end

    -- P1-3: 进攻模式×角色契合度
    local fitRule = ATTACK_MODE_ROLE_FIT[mode]
    if fitRule then
        local fitCount = 0
        for i = 1, 11 do
            local pid = startingXI[i]
            local roleKey = slotRoles[i] or "default"
            if pid and fitRule.roles[roleKey] then
                fitCount = fitCount + 1
            end
        end
        if fitCount > 0 then
            local bonus = math.min(fitCount * fitRule.perPlayer, fitRule.cap)
            if fitRule.dim == "attack" then
                finalAttack = finalAttack * (1.0 + bonus)
            elseif fitRule.dim == "possession" then
                finalPossession = finalPossession * (1.0 + bonus)
            elseif fitRule.dim == "shotQuality" then
                shotQuality = shotQuality * (1.0 + bonus)
            elseif fitRule.dim == "aerial" then
                aerial = aerial * (1.0 + bonus)
            end
            -- extraDim（如 longBall 的额外 attack 加成）
            if fitRule.extraDim and fitRule.extraPer then
                local extraBonus = math.min(fitCount * fitRule.extraPer, fitRule.extraCap or fitRule.extraPer)
                if fitRule.extraDim == "attack" then
                    finalAttack = finalAttack * (1.0 + extraBonus)
                end
            end
        end
    end

    local StaffManager = require("scripts/systems/staff_manager")
    local staffProficiency = StaffManager.getTacticalProficiency(gameState, team.id)
    local adjAttack = finalAttack * (1.0 + staffProficiency)
    local adjDefense = finalDefense * (1.0 + staffProficiency * 0.6)
    local adjPossession = finalPossession * (1.0 + staffProficiency * 0.4)

    return {
        team = team,
        players = players,
        style = style,
        attackMode = mode,
        counts = counts,
        chemistry = chemistry,
        avgFitness = avgFitness,
        avgMorale = morale / playerCount,
        avgStamina = stamina / playerCount,
        attack = adjAttack,
        defense = adjDefense,
        possession = adjPossession,
        tacticalProficiency = staffProficiency,
        -- averageOverall: 综合战力评分，供 match_engine 使用（取代硬编码 70）
        averageOverall = (adjAttack + adjDefense + adjPossession) / 3,
        -- avgPlayerOverall: 首发球员 OVR 均值（与属性权重解耦的实力锚点）
        avgPlayerOverall = ovrSum / playerCount,
        tempo = finalTempo,
        press = finalPress,
        foulRate = finalFoulRate,
        injuryRisk = clamp((styleMod.injury or 1.0) * (avgFitness < 65 and 1.25 or 1.0), 0.8, 1.55),
        staminaDrain = styleMod.staminaDrain or 1.0,
        shotQuality = math.max(1, shotQuality / playerCount * (modeMod.shotQuality or 1.0)),
        aerial = math.max(1, aerial / playerCount * (modeMod.aerial or 1.0)),
        counter = finalCounter,
        traitSummary = traitSummary,
        shapeMods = shapeMods,
        synergyTags = synergyTags,
    }
end

function TacticsResolver.matchupModifiers(myContext, opponentContext, isHome, formFactor)
    -- 攻防量纲归一：同实力对局比值≈1.0（见 DEF_TO_ATK_SCALE 注释）
    local opponentPress = clamp(opponentContext.press or 1.0, 0.75, 1.40)
    local pressSuppression = clamp(1.0 + (opponentPress - 1.0) * 0.22, 0.96, 1.10)
    local attackVsDefense = (myContext.attack * TacticsResolver.DEF_TO_ATK_SCALE)
        / math.max(1, opponentContext.defense * pressSuppression)
    local possessionShare = myContext.possession / math.max(1, myContext.possession + opponentContext.possession)
    local homeBonus = isHome and 1.06 or 1.0
    local redPenalty = 1.0 - ((myContext.redCards or 0) * 0.14)
    local opponentRedBonus = 1.0 + ((opponentContext.redCards or 0) * 0.10)

    -- 士气差异加成
    local moraleBonus = clamp((myContext.avgMorale - 50) / 250, -0.05, 0.05)

    -- 比赛日状态波动（±12%，模拟"今天状态好/差"）
    -- 引擎应传入单场固定采样值；缺省时退化为调用时采样（兼容旧调用方）
    formFactor = formFactor or (0.88 + Random() * 0.24)  -- [0.88, 1.12]

    -- 线性阻尼压缩实力差距：将所有比值往1.0方向拉（60%压缩）
    -- 原始2.0 → 1.40, 原始0.5 → 0.80（弱队比原来好，强队比原来弱）
    local dampedRatio = 1.0 + (attackVsDefense - 1.0) * 0.40

    -- 实力差直通：平均 OVR 差直接乘入机会创造，防止实力差被属性聚合稀释
    local ovrGap = (myContext.avgPlayerOverall or 70) - (opponentContext.avgPlayerOverall or 70)
    local strengthFactor = clamp(1.0 + ovrGap * STRENGTH_GAP_SLOPE, STRENGTH_FACTOR_MIN, STRENGTH_FACTOR_MAX)

    local chanceCreation = dampedRatio * strengthFactor * homeBonus * redPenalty * opponentRedBonus * formFactor + moraleBonus

    return {
        chanceCreation = clamp(chanceCreation, CHANCE_CREATION_MIN, CHANCE_CREATION_MAX),
        possessionShare = clamp(possessionShare + (isHome and 0.03 or -0.03), 0.32, 0.68),
        shotQuality = clamp(myContext.shotQuality / 10, 0.65, 1.40),
        foulRate = myContext.foulRate,
        injuryRisk = myContext.injuryRisk,
        tempo = myContext.tempo,
        press = myContext.press,
        counter = myContext.counter,
    }
end

function TacticsResolver.chooseWeighted(players, weightFn)
    local total = 0
    local weighted = {}
    for _, player in ipairs(players or {}) do
        local weight = math.max(0, weightFn(player) or 0)
        if weight > 0 then
            total = total + weight
            table.insert(weighted, { player = player, cumulative = total })
        end
    end
    if total <= 0 or #weighted == 0 then
        return players and players[1] or nil
    end
    local roll = Random() * total
    for _, entry in ipairs(weighted) do
        if roll <= entry.cumulative then return entry.player end
    end
    return weighted[#weighted].player
end

return TacticsResolver
