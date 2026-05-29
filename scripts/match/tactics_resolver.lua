-- match/tactics_resolver.lua
-- Pure tactical calculations shared by the match engine and tests.

local TacticsResolver = {}

TacticsResolver.ATTACK_MODES = {
    shortPassing = { attack = 1.02, possession = 1.08, tempo = 0.94, shotQuality = 1.03 },
    longBall = { attack = 1.03, possession = 0.92, tempo = 1.08, aerial = 1.12 },
    wingPlay = { attack = 1.05, possession = 0.98, tempo = 1.05, crossing = 1.12 },
    throughBalls = { attack = 1.07, possession = 0.98, tempo = 1.06, shotQuality = 1.08 },
    balanced = { attack = 1.0, possession = 1.0, tempo = 1.0, shotQuality = 1.0 },
}

local STYLE_MODIFIERS = {
    Balanced = { attack = 1.0, defense = 1.0, possession = 1.0, tempo = 1.0, press = 1.0, foul = 1.0 },
    Attacking = { attack = 1.14, defense = 0.93, possession = 1.03, tempo = 1.08, press = 1.04, foul = 1.03 },
    Defensive = { attack = 0.88, defense = 1.14, possession = 0.94, tempo = 0.92, press = 0.95, foul = 1.08 },
    Possession = { attack = 0.98, defense = 1.04, possession = 1.16, tempo = 0.9, press = 0.97, foul = 0.92 },
    Counter = { attack = 1.04, defense = 1.02, possession = 0.9, tempo = 1.12, press = 0.96, foul = 1.0, counter = 1.12 },
    HighPress = { attack = 1.08, defense = 0.97, possession = 1.06, tempo = 1.14, press = 1.18, foul = 1.12, injury = 1.08 },
}

local DUTIES = {
    attack = { attack = 1.18, defense = 0.86 },
    support = { attack = 1.0, defense = 1.0 },
    defend = { attack = 0.86, defense = 1.18 },
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function attr(player, key, fallback)
    local attributes = player.attributes or {}
    return attributes[key] or fallback or 10
end

local function hasTrait(player, traitId)
    for _, id in ipairs(player.traits or {}) do
        if id == traitId then return true end
    end
    return false
end

local function positionGroup(position)
    if position == "GK" then return "GK" end
    if position == "CB" or position == "LB" or position == "RB" then return "DEF" end
    if position == "ST" or position == "CF" or position == "LW" or position == "RW" then return "FWD" end
    return "MID"
end

function TacticsResolver.getMatchPlayers(gameState, team)
    local players = {}
    if team.startingXI and #team.startingXI > 0 then
        for _, playerId in ipairs(team.startingXI) do
            local player = gameState.players[playerId]
            if player and not player.injured and not player.retired then
                table.insert(players, player)
            end
        end
    end

    if #players < 11 then
        for _, playerId in ipairs(team.playerIds or {}) do
            if #players >= 11 then break end
            local player = gameState.players[playerId]
            if player and not player.injured and not player.retired then
                local alreadySelected = false
                for _, selected in ipairs(players) do
                    if selected.id == player.id then
                        alreadySelected = true
                        break
                    end
                end
                if not alreadySelected then table.insert(players, player) end
            end
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
            if first.nationality and first.nationality == second.nationality then
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

    for _, player in ipairs(players) do
        local group = positionGroup(player.position)
        counts[group] = counts[group] + 1

        local fitnessMul = clamp((player.fitness or 80) / 100, 0.45, 1.05)
        local moraleMul = clamp(0.82 + ((player.morale or 60) / 100) * 0.28, 0.82, 1.1)
        local duty = DUTIES[duties[player.id] or "support"] or DUTIES.support

        local playerAttack = 0
        local playerDefense = 0
        if group == "GK" then
            playerDefense = attr(player, "reflexes", 5) * 2.4 + attr(player, "handling", 5) * 1.8 + attr(player, "positioning") * 1.0
            possession = possession + attr(player, "passing") * 0.35 + attr(player, "decisions") * 0.3
        elseif group == "DEF" then
            playerAttack = attr(player, "passing") * 0.55 + attr(player, "aerial") * 0.25
            playerDefense = attr(player, "defending") * 2.0 + attr(player, "tackling") * 1.4 + attr(player, "positioning") * 1.1
            possession = possession + attr(player, "passing") * 0.75 + attr(player, "decisions") * 0.55
        elseif group == "MID" then
            playerAttack = attr(player, "passing") * 1.15 + attr(player, "vision") * 1.0 + attr(player, "shooting") * 0.55
            playerDefense = attr(player, "tackling") * 0.9 + attr(player, "positioning") * 0.75 + attr(player, "teamwork") * 0.45
            possession = possession + attr(player, "passing") * 1.2 + attr(player, "vision") * 0.95 + attr(player, "decisions") * 0.85
        else
            playerAttack = attr(player, "shooting") * 1.65 + attr(player, "dribbling") * 0.9 + attr(player, "positioning") * 1.0
            playerDefense = attr(player, "teamwork") * 0.35 + attr(player, "aggression") * 0.25
            possession = possession + attr(player, "dribbling") * 0.8 + attr(player, "passing") * 0.65
        end

        if hasTrait(player, "clinical") or hasTrait(player, "poacher") then shotQuality = shotQuality + 1.5 end
        if hasTrait(player, "playmaker") then possession = possession + 2.0; attack = attack + 1.2 end
        if hasTrait(player, "brick_wall") or hasTrait(player, "ball_winner") then defense = defense + 1.4 end
        if hasTrait(player, "aerial_threat") then aerial = aerial + 1.5 end
        if hasTrait(player, "engine") then stamina = stamina + 2.0 end

        attack = attack + playerAttack * fitnessMul * moraleMul * duty.attack
        defense = defense + playerDefense * fitnessMul * moraleMul * duty.defense
        discipline = discipline + (21 - attr(player, "aggression")) + attr(player, "decisions") * 0.45
        stamina = stamina + attr(player, "stamina") * fitnessMul
        morale = morale + (player.morale or 60)
        shotQuality = shotQuality + attr(player, "composure") * 0.35 + attr(player, "shooting") * 0.25
        aerial = aerial + attr(player, "aerial") * 0.25
    end

    local playerCount = math.max(1, #players)
    local chemistry = TacticsResolver.calculateChemistry(players)
    local formation = team.formation or "4-4-2"
    local defenderCount = tonumber(formation:sub(1, 1)) or counts.DEF

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
    for _, player in ipairs(players) do avgFitness = avgFitness + (player.fitness or 80) end
    avgFitness = avgFitness / playerCount

    return {
        team = team,
        players = players,
        style = style,
        attackMode = mode,
        counts = counts,
        chemistry = chemistry,
        avgFitness = avgFitness,
        avgMorale = morale / playerCount,
        attack = math.max(1, attack / 10 * styleMod.attack * (modeMod.attack or 1.0) * formationAttack * chemistry),
        defense = math.max(1, defense / 10 * styleMod.defense * formationDefense * chemistry),
        possession = math.max(1, possession / 10 * styleMod.possession * (modeMod.possession or 1.0) * chemistry),
        tempo = clamp(styleMod.tempo * (modeMod.tempo or 1.0), 0.75, 1.35),
        press = clamp(styleMod.press or 1.0, 0.75, 1.35),
        foulRate = clamp((styleMod.foul or 1.0) * (100 / math.max(30, discipline / playerCount * 8)), 0.65, 1.55),
        injuryRisk = clamp((styleMod.injury or 1.0) * (avgFitness < 65 and 1.25 or 1.0), 0.8, 1.55),
        shotQuality = math.max(1, shotQuality / playerCount * (modeMod.shotQuality or 1.0)),
        aerial = math.max(1, aerial / playerCount * (modeMod.aerial or 1.0)),
        counter = styleMod.counter or 1.0,
    }
end

function TacticsResolver.matchupModifiers(myContext, opponentContext, isHome)
    local attackVsDefense = myContext.attack / math.max(1, opponentContext.defense)
    local possessionShare = myContext.possession / math.max(1, myContext.possession + opponentContext.possession)
    local homeBonus = isHome and 1.06 or 1.0
    local redPenalty = 1.0 - ((myContext.redCards or 0) * 0.14)
    local opponentRedBonus = 1.0 + ((opponentContext.redCards or 0) * 0.10)

    -- 士气差异加成
    local moraleBonus = clamp((myContext.avgMorale - 50) / 250, -0.05, 0.05)

    -- 比赛日状态波动（±18%随机，模拟"今天状态好/差"）
    local formFactor = 0.82 + Random() * 0.36  -- [0.82, 1.18]

    -- 线性阻尼压缩实力差距：将所有比值往1.0方向拉（50%压缩）
    -- 原始2.0 → 1.50, 原始0.5 → 0.75（弱队比原来好，强队比原来弱）
    local dampedRatio = 1.0 + (attackVsDefense - 1.0) * 0.50

    local chanceCreation = dampedRatio * homeBonus * redPenalty * opponentRedBonus * formFactor + moraleBonus

    return {
        chanceCreation = clamp(chanceCreation, 0.55, 1.70),
        possessionShare = clamp(possessionShare + (isHome and 0.03 or -0.03), 0.32, 0.68),
        shotQuality = clamp(myContext.shotQuality / 10, 0.65, 1.40),
        foulRate = myContext.foulRate,
        injuryRisk = myContext.injuryRisk,
        tempo = myContext.tempo,
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
