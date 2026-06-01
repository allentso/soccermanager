-- match/placeholder_engine.lua
-- 增强比赛引擎：基于球员能力、战术、阵型模拟比赛
-- v2: 士气影响、球员个人指令、动态事件响应、化学值、加时/点球、进攻模式细分、对手分析

local TacticsResolver = require("scripts/match/tactics_resolver")
local RecordsManager = require("scripts/systems/records_manager")

local PlaceholderEngine = {}

------------------------------------------------------
-- 进攻模式定义（细分战术指令）
------------------------------------------------------
PlaceholderEngine.ATTACK_MODES = {
    shortPassing = { passBonus = 1.1, speedPenalty = 0.95, desc = "短传渗透" },
    longBall     = { passBonus = 0.9, speedPenalty = 1.1, aerialBonus = 1.15, desc = "长传冲吊" },
    wingPlay     = { passBonus = 1.0, speedPenalty = 1.05, crossBonus = 1.2, desc = "边路进攻" },
    throughBalls = { passBonus = 1.05, speedPenalty = 1.1, visionBonus = 1.15, desc = "直塞突破" },
    balanced     = { passBonus = 1.0, speedPenalty = 1.0, desc = "均衡进攻" },
}

------------------------------------------------------
-- 球员个人指令定义
------------------------------------------------------
PlaceholderEngine.PLAYER_DUTIES = {
    attack  = { attackWeight = 1.4, defenseWeight = 0.6 },
    support = { attackWeight = 1.0, defenseWeight = 1.0 },
    defend  = { attackWeight = 0.6, defenseWeight = 1.4 },
}

------------------------------------------------------
-- 主入口：模拟一场比赛
------------------------------------------------------

function PlaceholderEngine.simulate(gameState, fixture)
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    if not homeTeam or not awayTeam then return nil end

    -- 使用统一的 buildTeamContext 获取攻/防/控球数值（含角色修正、化学反应、阵型加成）
    local homeCtx = TacticsResolver.buildTeamContext(gameState, homeTeam)
    local awayCtx = TacticsResolver.buildTeamContext(gameState, awayTeam)
    if #homeCtx.players == 0 or #awayCtx.players == 0 then return nil end

    local homePlayers = homeCtx.players
    local awayPlayers = awayCtx.players
    local homeChemistry = homeCtx.chemistry
    local awayChemistry = awayCtx.chemistry

    -- 战术相克加成
    local homeTacticalBonus = PlaceholderEngine._getTacticalBonus(homeTeam, awayTeam)
    local awayTacticalBonus = PlaceholderEngine._getTacticalBonus(awayTeam, homeTeam)

    -- 从统一 context 取攻防值，应用主场优势 + 战术相克
    local homeAttack = homeCtx.attack * 1.08 * (1 + homeTacticalBonus)
    local awayDefense = awayCtx.defense * (1 + awayTacticalBonus)
    local awayAttack = awayCtx.attack * (1 + awayTacticalBonus)
    local homeDefense = homeCtx.defense * 1.08 * (1 + homeTacticalBonus)

    -- 期望进球 = 攻击力 / 防守力 * 基础系数
    local homeExpGoals = (homeAttack / math.max(1, awayDefense)) * 1.4 + Random() * 0.3
    local awayExpGoals = (awayAttack / math.max(1, homeDefense)) * 1.2 + Random() * 0.3

    -- 生成比赛事件（先生成卡牌/伤病，用于动态响应）
    local events = {}

    -- 黄牌/红牌事件
    PlaceholderEngine._generateCardEvents(events, homePlayers, fixture.homeTeamId, homeTeam)
    PlaceholderEngine._generateCardEvents(events, awayPlayers, fixture.awayTeamId, awayTeam)

    -- 伤病事件（低概率）
    PlaceholderEngine._generateInjuryEvents(events, homePlayers, fixture.homeTeamId, gameState)
    PlaceholderEngine._generateInjuryEvents(events, awayPlayers, fixture.awayTeamId, gameState)

    -- 动态事件响应：红牌影响期望进球
    local homeRedCards, awayRedCards = PlaceholderEngine._countRedCards(events, fixture.homeTeamId, fixture.awayTeamId)
    -- 每张红牌降低本队攻击力12%并增加对方攻击力8%
    if homeRedCards > 0 then
        homeExpGoals = homeExpGoals * math.max(0.5, 1.0 - homeRedCards * 0.12)
        awayExpGoals = awayExpGoals * (1.0 + homeRedCards * 0.08)
    end
    if awayRedCards > 0 then
        awayExpGoals = awayExpGoals * math.max(0.5, 1.0 - awayRedCards * 0.12)
        homeExpGoals = homeExpGoals * (1.0 + awayRedCards * 0.08)
    end

    -- 泊松采样确定进球数
    local homeGoals = PlaceholderEngine._poissonRandom(homeExpGoals)
    local awayGoals = PlaceholderEngine._poissonRandom(awayExpGoals)

    -- 限制极端比分
    homeGoals = math.min(homeGoals, 6)
    awayGoals = math.min(awayGoals, 6)

    -- 进球事件
    PlaceholderEngine._generateGoalEvents(events, homePlayers, fixture.homeTeamId, homeGoals, gameState)
    PlaceholderEngine._generateGoalEvents(events, awayPlayers, fixture.awayTeamId, awayGoals, gameState)

    -- 按时间排序
    table.sort(events, function(a, b) return a.minute < b.minute end)

    -- 加时赛/点球大战（淘汰赛平局时）
    local extraTimeReport = nil
    if fixture.isKnockout and homeGoals == awayGoals then
        extraTimeReport = PlaceholderEngine._simulateExtraTime(
            gameState, fixture, homePlayers, awayPlayers, homeTeam, awayTeam,
            homeCtx.attack, awayCtx.attack, homeCtx.defense, awayCtx.defense, events
        )
        homeGoals = homeGoals + extraTimeReport.homeExtraGoals
        awayGoals = awayGoals + extraTimeReport.awayExtraGoals

        -- 点球大战
        if homeGoals == awayGoals then
            extraTimeReport.penalties = PlaceholderEngine._simulatePenaltyShootout(
                homePlayers, awayPlayers, gameState
            )
            -- 点球不计入总比分，但决定胜者
        end
    end

    -- 计算控球率（基于传球/技术对比）
    local homeControl = PlaceholderEngine._calcPossession(homePlayers, awayPlayers, homeTeam, awayTeam)

    -- 计算射门数
    local homeShots = homeGoals + math.floor(homeExpGoals * 2.5) + RandomInt(2, 5)
    local awayShots = awayGoals + math.floor(awayExpGoals * 2.5) + RandomInt(2, 5)
    local homeShotsOnTarget = homeGoals + math.floor((homeShots - homeGoals) * 0.35)
    local awayShotsOnTarget = awayGoals + math.floor((awayShots - awayGoals) * 0.35)

    -- 计算犯规数（基于侵略性）
    local homeFouls = PlaceholderEngine._calcFouls(homePlayers, homeTeam)
    local awayFouls = PlaceholderEngine._calcFouls(awayPlayers, awayTeam)

    -- 球员评分
    local playerRatings = PlaceholderEngine._calcPlayerRatings(
        homePlayers, awayPlayers, homeGoals, awayGoals, events, fixture
    )

    -- 构建报告
    local report = {
        fixtureId = fixture.id,
        homeTeamId = fixture.homeTeamId,
        awayTeamId = fixture.awayTeamId,
        homeGoals = homeGoals,
        awayGoals = awayGoals,
        events = events,
        playerRatings = playerRatings,
        extraTime = extraTimeReport,
        stats = {
            homeShots = homeShots,
            awayShots = awayShots,
            homeShotsOnTarget = homeShotsOnTarget,
            awayShotsOnTarget = awayShotsOnTarget,
            homePossession = homeControl,
            awayPossession = 100 - homeControl,
            homeFouls = homeFouls,
            awayFouls = awayFouls,
            homeCorners = math.floor(homeShots * 0.4) + RandomInt(1, 3),
            awayCorners = math.floor(awayShots * 0.4) + RandomInt(1, 3),
            homeChemistry = math.floor(homeChemistry * 100),
            awayChemistry = math.floor(awayChemistry * 100),
        },
    }

    return report
end

------------------------------------------------------
-- 获取比赛出场球员（首发11人）
------------------------------------------------------

function PlaceholderEngine._getMatchPlayers(gameState, team)
    local players = {}
    -- 优先使用首发阵容
    if team.startingXI and #team.startingXI > 0 then
        for _, pid in ipairs(team.startingXI) do
            local p = gameState.players[pid]
            if p and not p.injured then
                table.insert(players, p)
            end
        end
    end

    -- 如果首发不足11人，从候补中补充
    if #players < 11 then
        for _, pid in ipairs(team.playerIds) do
            if #players >= 11 then break end
            local p = gameState.players[pid]
            if p and not p.injured then
                -- 检查是否已在首发中
                local alreadyIn = false
                for _, existing in ipairs(players) do
                    if existing.id == p.id then alreadyIn = true; break end
                end
                if not alreadyIn then
                    table.insert(players, p)
                end
            end
        end
    end

    return players
end



------------------------------------------------------
-- 战术相克加成
------------------------------------------------------

function PlaceholderEngine._getTacticalBonus(myTeam, opponentTeam)
    local myStyle = myTeam.playStyle or "Balanced"
    local oppStyle = opponentTeam.playStyle or "Balanced"

    -- 战术克制关系
    -- Counter > Attacking (+5%)
    -- Attacking > Defensive (+3%)
    -- Defensive > Counter (+3%)
    -- Balanced 无明显克制
    local bonus = 0

    if myStyle == "Counter" and oppStyle == "Attacking" then
        bonus = 0.05
    elseif myStyle == "Attacking" and oppStyle == "Defensive" then
        bonus = 0.03
    elseif myStyle == "Defensive" and oppStyle == "Counter" then
        bonus = 0.03
    end

    return bonus
end



------------------------------------------------------
-- 控球率计算
------------------------------------------------------

function PlaceholderEngine._calcPossession(homePlayers, awayPlayers, homeTeam, awayTeam)
    local homePass = 0
    local awayPass = 0
    for _, p in ipairs(homePlayers) do
        homePass = homePass + (p.attributes.passing or 10) + (p.attributes.vision or 10) * 0.5
    end
    for _, p in ipairs(awayPlayers) do
        awayPass = awayPass + (p.attributes.passing or 10) + (p.attributes.vision or 10) * 0.5
    end

    -- 战术修正
    local homeStyle = homeTeam.playStyle or "Balanced"
    local awayStyle = awayTeam.playStyle or "Balanced"
    if homeStyle == "Attacking" then homePass = homePass * 1.1
    elseif homeStyle == "Counter" then homePass = homePass * 0.9 end
    if awayStyle == "Attacking" then awayPass = awayPass * 1.1
    elseif awayStyle == "Counter" then awayPass = awayPass * 0.9 end

    local total = homePass + awayPass
    if total == 0 then return 50 end
    local possession = math.floor((homePass / total) * 100)
    -- 限制极端值
    return math.max(30, math.min(70, possession))
end

------------------------------------------------------
-- 犯规数计算
------------------------------------------------------

function PlaceholderEngine._calcFouls(players, team)
    local aggression = 0
    for _, p in ipairs(players) do
        aggression = aggression + (p.attributes.aggression or 10)
    end
    local avg = aggression / math.max(1, #players)
    -- 防守战术犯规更多
    local styleBonus = 0
    if (team.playStyle or "Balanced") == "Defensive" then styleBonus = 3 end
    return math.floor(avg * 0.6 + RandomInt(3, 7) + styleBonus)
end

------------------------------------------------------
-- 生成进球事件
------------------------------------------------------

function PlaceholderEngine._generateGoalEvents(events, players, teamId, goalCount, gameState)
    for i = 1, goalCount do
        local scorer = PlaceholderEngine._pickScorer(players)
        local assister = PlaceholderEngine._pickAssister(players, scorer)
        local minute = PlaceholderEngine._generateGoalMinute()

        if scorer then
            local evt = {
                type = "goal",
                minute = minute,
                playerId = scorer.id,
                teamId = teamId,
            }
            if assister then
                evt.assistPlayerId = assister.id
            end
            table.insert(events, evt)
        end
    end
end

------------------------------------------------------
-- 生成卡牌事件
------------------------------------------------------

function PlaceholderEngine._generateCardEvents(events, players, teamId, team)
    -- 平均每场 2-3 张黄牌
    local yellowChance = 0.2
    if (team.playStyle or "Balanced") == "Defensive" then yellowChance = 0.25 end

    for _, p in ipairs(players) do
        if p.position == "GK" then goto continue end  -- 门将少吃牌
        local aggFactor = (p.attributes.aggression or 10) / 20
        if Random() < yellowChance * aggFactor then
            table.insert(events, {
                type = "yellow_card",
                minute = RandomInt(10, 88),
                playerId = p.id,
                teamId = teamId,
            })
            -- 极少概率两黄变红
            if Random() < 0.05 then
                table.insert(events, {
                    type = "red_card",
                    minute = RandomInt(60, 90),
                    playerId = p.id,
                    teamId = teamId,
                })
            end
        end
        ::continue::
    end
end

------------------------------------------------------
-- 生成比赛伤病事件
------------------------------------------------------

function PlaceholderEngine._generateInjuryEvents(events, players, teamId, gameState)
    -- 每场比赛约3%概率有伤病
    for _, p in ipairs(players) do
        if p.position == "GK" then goto continue end
        -- 低体能球员更容易受伤
        local injuryChance = 0.008
        if p.fitness < 70 then injuryChance = 0.015 end
        if p.fitness < 50 then injuryChance = 0.025 end

        if Random() < injuryChance then
            local injuryDays = RandomInt(3, 21)
            table.insert(events, {
                type = "injury",
                minute = RandomInt(20, 85),
                playerId = p.id,
                teamId = teamId,
                injuryDays = injuryDays,
            })
        end
        ::continue::
    end
end

------------------------------------------------------
-- 生成进球时间分布（更真实：上半场略少）
------------------------------------------------------

function PlaceholderEngine._generateGoalMinute()
    -- 进球在比赛后半段更常见
    local r = Random()
    if r < 0.4 then
        return RandomInt(1, 45)     -- 上半场
    elseif r < 0.85 then
        return RandomInt(46, 85)    -- 下半场
    else
        return RandomInt(86, 93)    -- 补时阶段
    end
end

------------------------------------------------------
-- 选择进球球员（基于射门能力加权）
------------------------------------------------------

function PlaceholderEngine._pickScorer(players)
    if not players or #players == 0 then return nil end
    local weighted = {}
    for _, p in ipairs(players) do
        local weight = 0
        local shooting = p.attributes.shooting or 10
        if p.position == "ST" or p.position == "CF" then
            weight = shooting * 3
        elseif p.position == "LW" or p.position == "RW" then
            weight = shooting * 2
        elseif p.position == "CAM" then
            weight = shooting * 1.5
        elseif p.position == "CM" or p.position == "LM" or p.position == "RM" then
            weight = shooting * 0.8
        elseif p.position == "CDM" then
            weight = shooting * 0.3
        elseif p.position == "CB" or p.position == "LB" or p.position == "RB" then
            weight = shooting * 0.15 + (p.attributes.aerial or 5) * 0.1
        else  -- GK
            weight = 0.05
        end
        weight = math.max(1, math.floor(weight))
        for i = 1, weight do
            table.insert(weighted, p)
        end
    end
    if #weighted == 0 then return players[1] end
    return weighted[RandomInt(1, #weighted)]
end

------------------------------------------------------
-- 选择助攻球员
------------------------------------------------------

function PlaceholderEngine._pickAssister(players, scorer)
    -- 70%的进球有助攻
    if Random() > 0.7 then return nil end
    if not players or #players == 0 then return nil end

    local candidates = {}
    for _, p in ipairs(players) do
        if scorer and p.id == scorer.id then goto continue end
        local weight = 0
        local passing = p.attributes.passing or 10
        local vision = p.attributes.vision or 10
        if p.position == "CAM" then
            weight = (passing + vision) * 2
        elseif p.position == "CM" or p.position == "LM" or p.position == "RM" then
            weight = (passing + vision) * 1.5
        elseif p.position == "LW" or p.position == "RW" then
            weight = (passing + vision) * 1.2
        elseif p.position == "LB" or p.position == "RB" then
            weight = passing * 0.8
        elseif p.position == "ST" or p.position == "CF" then
            weight = passing * 0.6
        else
            weight = passing * 0.3
        end
        weight = math.max(1, math.floor(weight))
        for i = 1, weight do
            table.insert(candidates, p)
        end
        ::continue::
    end
    if #candidates == 0 then return nil end
    return candidates[RandomInt(1, #candidates)]
end

------------------------------------------------------
-- 球员比赛评分
------------------------------------------------------

function PlaceholderEngine._calcPlayerRatings(homePlayers, awayPlayers, homeGoals, awayGoals, events, fixture)
    local ratings = {}

    -- 基础分 6.5
    local allPlayers = {}
    for _, p in ipairs(homePlayers) do table.insert(allPlayers, {player = p, teamId = fixture.homeTeamId}) end
    for _, p in ipairs(awayPlayers) do table.insert(allPlayers, {player = p, teamId = fixture.awayTeamId}) end

    for _, entry in ipairs(allPlayers) do
        local p = entry.player
        local rating = 6.5

        -- 进球加分
        for _, evt in ipairs(events) do
            if evt.playerId == p.id then
                if evt.type == "goal" then rating = rating + 1.0
                elseif evt.type == "yellow_card" then rating = rating - 0.3
                elseif evt.type == "red_card" then rating = rating - 1.5
                elseif evt.type == "injury" then rating = rating - 0.5
                end
            end
            if evt.assistPlayerId == p.id then
                rating = rating + 0.5
            end
        end

        -- 球队获胜加分
        local isHome = entry.teamId == fixture.homeTeamId
        if isHome and homeGoals > awayGoals then rating = rating + 0.3
        elseif not isHome and awayGoals > homeGoals then rating = rating + 0.3
        elseif isHome and homeGoals < awayGoals then rating = rating - 0.2
        elseif not isHome and awayGoals < homeGoals then rating = rating - 0.2
        end

        -- 门将：零封加分
        if p.position == "GK" then
            if isHome and awayGoals == 0 then rating = rating + 1.0
            elseif not isHome and homeGoals == 0 then rating = rating + 1.0
            elseif isHome and awayGoals >= 3 then rating = rating - 0.5
            elseif not isHome and homeGoals >= 3 then rating = rating - 0.5
            end
        end

        -- 随机波动
        rating = rating + (Random() - 0.5) * 0.6

        -- 限制范围 [4.0, 10.0]
        rating = math.max(4.0, math.min(10.0, rating))
        rating = math.floor(rating * 10) / 10  -- 保留1位小数

        ratings[p.id] = rating
    end

    return ratings
end



------------------------------------------------------
-- 红牌统计（用于动态事件响应）
------------------------------------------------------

function PlaceholderEngine._countRedCards(events, homeTeamId, awayTeamId)
    local homeReds = 0
    local awayReds = 0
    for _, evt in ipairs(events) do
        if evt.type == "red_card" then
            if evt.teamId == homeTeamId then
                homeReds = homeReds + 1
            elseif evt.teamId == awayTeamId then
                awayReds = awayReds + 1
            end
        end
    end
    return homeReds, awayReds
end

------------------------------------------------------
-- 进攻模式修正
------------------------------------------------------

function PlaceholderEngine._getAttackModeModifiers(team)
    local mode = team.attackMode or "balanced"
    local modeDef = PlaceholderEngine.ATTACK_MODES[mode] or PlaceholderEngine.ATTACK_MODES.balanced

    -- 综合攻击乘数
    local attackMul = 1.0
    attackMul = attackMul * (modeDef.passBonus or 1.0)
    attackMul = attackMul * (modeDef.speedPenalty or 1.0)

    -- 长传额外头球加成
    if modeDef.aerialBonus then
        attackMul = attackMul * ((modeDef.aerialBonus - 1.0) * 0.3 + 1.0)
    end
    -- 边路传中加成
    if modeDef.crossBonus then
        attackMul = attackMul * ((modeDef.crossBonus - 1.0) * 0.3 + 1.0)
    end
    -- 直塞视野加成
    if modeDef.visionBonus then
        attackMul = attackMul * ((modeDef.visionBonus - 1.0) * 0.3 + 1.0)
    end

    return { attackMul = attackMul }
end

------------------------------------------------------
-- 加时赛模拟
------------------------------------------------------

function PlaceholderEngine._simulateExtraTime(gameState, fixture, homePlayers, awayPlayers, homeTeam, awayTeam, homeAttack, awayAttack, homeDefense, awayDefense, events)
    -- 加时赛30分钟（2x15），球员体能下降导致进球率降低
    local fatigueFactor = 0.7  -- 体能衰减后攻击力降低

    local extraHomeExp = (homeAttack * fatigueFactor / math.max(1, awayDefense)) * 0.5 + Random() * 0.15
    local extraAwayExp = (awayAttack * fatigueFactor / math.max(1, homeDefense)) * 0.4 + Random() * 0.15

    local homeExtraGoals = PlaceholderEngine._poissonRandom(extraHomeExp)
    local awayExtraGoals = PlaceholderEngine._poissonRandom(extraAwayExp)

    -- 限制加时赛进球
    homeExtraGoals = math.min(homeExtraGoals, 3)
    awayExtraGoals = math.min(awayExtraGoals, 3)

    -- 生成加时赛进球事件
    for _ = 1, homeExtraGoals do
        local scorer = PlaceholderEngine._pickScorer(homePlayers)
        if scorer then
            table.insert(events, {
                type = "goal",
                minute = RandomInt(91, 120),
                playerId = scorer.id,
                teamId = fixture.homeTeamId,
                isExtraTime = true,
            })
        end
    end
    for _ = 1, awayExtraGoals do
        local scorer = PlaceholderEngine._pickScorer(awayPlayers)
        if scorer then
            table.insert(events, {
                type = "goal",
                minute = RandomInt(91, 120),
                playerId = scorer.id,
                teamId = fixture.awayTeamId,
                isExtraTime = true,
            })
        end
    end

    return {
        homeExtraGoals = homeExtraGoals,
        awayExtraGoals = awayExtraGoals,
        played = true,
    }
end

------------------------------------------------------
-- 点球大战模拟
------------------------------------------------------

function PlaceholderEngine._simulatePenaltyShootout(homePlayers, awayPlayers, gameState)
    -- 5轮点球，平局则继续
    local homeScored = 0
    local awayScored = 0
    local homeMissed = 0
    local awayMissed = 0
    local rounds = {}

    -- 选5名罚球手（按射门属性排序）
    local homeKickers = PlaceholderEngine._selectPenaltyKickers(homePlayers)
    local awayKickers = PlaceholderEngine._selectPenaltyKickers(awayPlayers)

    -- 获取门将
    local homeGK = PlaceholderEngine._findGK(homePlayers)
    local awayGK = PlaceholderEngine._findGK(awayPlayers)

    for round = 1, 5 do
        -- 主队踢
        local homeResult = PlaceholderEngine._takePenalty(homeKickers[round], awayGK)
        if homeResult then homeScored = homeScored + 1 else homeMissed = homeMissed + 1 end

        -- 客队踢
        local awayResult = PlaceholderEngine._takePenalty(awayKickers[round], homeGK)
        if awayResult then awayScored = awayScored + 1 else awayMissed = awayMissed + 1 end

        table.insert(rounds, {
            round = round,
            homeScored = homeResult,
            awayScored = awayResult,
            homeKickerId = homeKickers[round] and homeKickers[round].id,
            awayKickerId = awayKickers[round] and awayKickers[round].id,
        })

        -- 提前结束判断（数学上不可能追平）
        local remaining = 5 - round
        if homeScored - awayScored > remaining then break end  -- 主队已不可追
        if awayScored - homeScored > remaining then break end  -- 客队已不可追
    end

    -- 如果5轮后平局，继续突然死亡
    local suddenDeathRound = 0
    while homeScored == awayScored and suddenDeathRound < 10 do
        suddenDeathRound = suddenDeathRound + 1
        local kickerIdx = 5 + suddenDeathRound
        local hk = homeKickers[((kickerIdx - 1) % #homeKickers) + 1]
        local ak = awayKickers[((kickerIdx - 1) % #awayKickers) + 1]

        local hr = PlaceholderEngine._takePenalty(hk, awayGK)
        local ar = PlaceholderEngine._takePenalty(ak, homeGK)
        if hr then homeScored = homeScored + 1 end
        if ar then awayScored = awayScored + 1 end

        table.insert(rounds, {
            round = 5 + suddenDeathRound,
            homeScored = hr,
            awayScored = ar,
            homeKickerId = hk and hk.id,
            awayKickerId = ak and ak.id,
            isSuddenDeath = true,
        })

        -- 突然死亡：一方进一方没进则结束
        if hr and not ar then break end
        if ar and not hr then break end
    end

    return {
        homeScore = homeScored,
        awayScore = awayScored,
        rounds = rounds,
        winner = homeScored > awayScored and "home" or "away",
    }
end

-- 选择点球手（按射门+沉着排序取前5+循环）
function PlaceholderEngine._selectPenaltyKickers(players)
    local kickers = {}
    for _, p in ipairs(players) do
        if p.position ~= "GK" then
            table.insert(kickers, p)
        end
    end
    table.sort(kickers, function(a, b)
        local aScore = (a.attributes.shooting or 10) + (a.attributes.composure or 10)
        local bScore = (b.attributes.shooting or 10) + (b.attributes.composure or 10)
        return aScore > bScore
    end)
    -- 确保至少有5个
    while #kickers < 10 do
        table.insert(kickers, kickers[1])
    end
    return kickers
end

-- 门将查找
function PlaceholderEngine._findGK(players)
    for _, p in ipairs(players) do
        if p.position == "GK" then return p end
    end
    return players[1]  -- 兜底
end

-- 单次罚点球（返回是否进球）
function PlaceholderEngine._takePenalty(kicker, goalkeeper)
    if not kicker then return Random() > 0.3 end

    -- 进球概率基于：射门+沉着 vs 门将反应+扑救
    local kickerScore = (kicker.attributes.shooting or 10) + (kicker.attributes.composure or 10) * 0.8
    local gkScore = 0
    if goalkeeper then
        gkScore = (goalkeeper.attributes.reflexes or 10) + (goalkeeper.attributes.handling or 10) * 0.5
    end

    -- 基础进球率 75%，根据对比浮动
    local baseChance = 0.75
    local diff = (kickerScore - gkScore) / 40  -- 标准化差值
    local chance = baseChance + diff * 0.15
    chance = math.max(0.5, math.min(0.92, chance))

    -- 士气影响罚球（低士气更容易失手）
    local moralePenalty = ((kicker.morale or 60) - 50) / 200  -- -0.05 ~ +0.25
    chance = chance + moralePenalty * 0.1

    return Random() < chance
end

------------------------------------------------------
-- 对手分析（赛前情报生成）
------------------------------------------------------

function PlaceholderEngine.generateOpponentAnalysis(gameState, opponentTeamId)
    local team = gameState.teams[opponentTeamId]
    if not team then return nil end

    local players = PlaceholderEngine._getMatchPlayers(gameState, team)
    if #players == 0 then return nil end

    -- 计算各维度数据
    local totalOverall = 0
    local totalFitness = 0
    local totalMorale = 0
    local positionCount = {GK = 0, DEF = 0, MID = 0, FWD = 0}
    local topScorer = nil
    local topScorerGoals = 0
    local keyPlayers = {}
    local injuredPlayers = {}

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.retired then
            totalOverall = totalOverall + p.overall
            totalFitness = totalFitness + (p.fitness or 80)
            totalMorale = totalMorale + (p.morale or 60)

            -- 位置统计
            if p.position == "GK" then positionCount.GK = positionCount.GK + 1
            elseif p.position == "CB" or p.position == "LB" or p.position == "RB" then positionCount.DEF = positionCount.DEF + 1
            elseif p.position == "ST" or p.position == "CF" or p.position == "LW" or p.position == "RW" then positionCount.FWD = positionCount.FWD + 1
            else positionCount.MID = positionCount.MID + 1 end

            -- 最佳射手
            local goals = (p.seasonStats and p.seasonStats.goals) or 0
            if goals > topScorerGoals then
                topScorer = p
                topScorerGoals = goals
            end

            -- 关键球员（overall >= 70）
            if p.overall >= 70 then
                table.insert(keyPlayers, { id = p.id, name = p.displayName, overall = p.overall, position = p.position })
            end

            -- 伤病球员
            if p.injured then
                table.insert(injuredPlayers, { id = p.id, name = p.displayName, position = p.position })
            end
        end
    end

    local count = #team.playerIds
    count = math.max(1, count)

    return {
        teamId = opponentTeamId,
        teamName = team.name,
        formation = team.formation or "4-4-2",
        playStyle = team.playStyle or "Balanced",
        attackMode = team.attackMode or "balanced",
        recentForm = team.recentForm or {},
        avgOverall = math.floor(totalOverall / count),
        avgFitness = math.floor(totalFitness / count),
        avgMorale = math.floor(totalMorale / count),
        positionCount = positionCount,
        topScorer = topScorer and {
            name = topScorer.displayName,
            goals = topScorerGoals,
            position = topScorer.position,
        } or nil,
        keyPlayers = keyPlayers,
        injuredPlayers = injuredPlayers,
        squadSize = #team.playerIds,
        -- 战术弱点提示
        weakness = PlaceholderEngine._analyzeWeakness(team, players),
    }
end

-- 分析对手弱点
function PlaceholderEngine._analyzeWeakness(team, players)
    local weaknesses = {}
    local formation = team.formation or "4-4-2"
    local defCount = tonumber(formation:sub(1, 1)) or 4

    -- 防线人数不足
    if defCount <= 3 then
        table.insert(weaknesses, "防线人数较少，可利用边路突破")
    end

    -- 平均体能低
    local totalFit = 0
    for _, p in ipairs(players) do totalFit = totalFit + (p.fitness or 80) end
    if #players > 0 and totalFit / #players < 65 then
        table.insert(weaknesses, "球队整体体能不佳，下半场表现可能下滑")
    end

    -- 士气低落
    local totalMorale = 0
    for _, p in ipairs(players) do totalMorale = totalMorale + (p.morale or 60) end
    if #players > 0 and totalMorale / #players < 45 then
        table.insert(weaknesses, "球队士气低落，施压可能导致崩盘")
    end

    -- 战术弱点
    local style = team.playStyle or "Balanced"
    if style == "Attacking" then
        table.insert(weaknesses, "进攻型打法，防守转换可能存在空当")
    elseif style == "Counter" then
        table.insert(weaknesses, "反击战术，控球施压可压缩其反击空间")
    end

    if #weaknesses == 0 then
        table.insert(weaknesses, "该队整体均衡，无明显弱点")
    end

    return weaknesses
end

------------------------------------------------------
-- 泊松随机数生成
------------------------------------------------------

function PlaceholderEngine._poissonRandom(lambda)
    if lambda <= 0 then return 0 end
    local L = math.exp(-lambda)
    local k = 0
    local p = 1
    repeat
        k = k + 1
        p = p * Random()
    until p <= L
    return k - 1
end

------------------------------------------------------
-- 应用比赛结果到游戏状态
------------------------------------------------------

function PlaceholderEngine.applyResult(gameState, fixture, report)
    -- 更新比赛状态
    fixture.status = "finished"
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.events = report.events
    fixture.playerRatings = report.playerRatings
    fixture.stats = report.stats

    -- 更新正确联赛的积分榜（查找fixture所属联赛）
    local targetLeague = nil
    for _, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds) do
            if tid == fixture.homeTeamId then
                targetLeague = lg
                break
            end
        end
        if targetLeague then break end
    end
    if targetLeague then
        targetLeague:updateStanding(fixture)
    elseif gameState.league then
        -- 兜底：使用玩家联赛
        gameState.league:updateStanding(fixture)
    end

    -- 处理比赛事件
    for _, evt in ipairs(report.events) do
        local p = gameState.players[evt.playerId]
        if not p then goto continue end

        if evt.type == "goal" then
            p.seasonStats.goals = p.seasonStats.goals + 1
        elseif evt.type == "yellow_card" then
            p.seasonStats.yellowCards = p.seasonStats.yellowCards + 1
        elseif evt.type == "red_card" then
            p.seasonStats.redCards = p.seasonStats.redCards + 1
        elseif evt.type == "injury" then
            p.injured = true
            p.injuryDays = evt.injuryDays or RandomInt(3, 14)
            -- 通知玩家球队伤病
            if p.teamId == gameState.playerTeamId then
                gameState:sendMessage({
                    category = "injury",
                    title = "比赛伤病",
                    body = string.format("%s 在比赛中受伤，预计 %d 天恢复。", p.displayName, p.injuryDays),
                    priority = "high",
                })
            end
        end

        -- 助攻统计
        if evt.type == "goal" and evt.assistPlayerId then
            local assister = gameState.players[evt.assistPlayerId]
            if assister then
                assister.seasonStats.assists = assister.seasonStats.assists + 1
            end
        end

        ::continue::
    end

    -- 更新球员出场数和评分
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    local matchPlayers = {}

    if homeTeam then
        local players = PlaceholderEngine._getMatchPlayers(gameState, homeTeam)
        for _, p in ipairs(players) do table.insert(matchPlayers, p) end
    end
    if awayTeam then
        local players = PlaceholderEngine._getMatchPlayers(gameState, awayTeam)
        for _, p in ipairs(players) do table.insert(matchPlayers, p) end
    end

    for _, p in ipairs(matchPlayers) do
        p.seasonStats.appearances = p.seasonStats.appearances + 1
        -- 更新平均评分
        if report.playerRatings and report.playerRatings[p.id] then
            local matchRating = report.playerRatings[p.id]
            local apps = p.seasonStats.appearances
            if apps <= 1 then
                p.seasonStats.avgRating = matchRating
            else
                -- 移动平均
                p.seasonStats.avgRating = p.seasonStats.avgRating + (matchRating - p.seasonStats.avgRating) / apps
                p.seasonStats.avgRating = math.floor(p.seasonStats.avgRating * 10) / 10
            end
        end

        -- 门将零封统计
        if p.position == "GK" then
            local isHome = p.teamId == fixture.homeTeamId
            if (isHome and report.awayGoals == 0) or (not isHome and report.homeGoals == 0) then
                p.seasonStats.cleanSheets = p.seasonStats.cleanSheets + 1
            end
        end
    end

    -- 体能消耗（按位置×风格×个人耐力差异化）
    local drainData = TacticsResolver.POSITION_STAMINA_DRAIN
    -- 预计算每队的 styleDrain（避免重复调用 buildTeamContext）
    local teamStyleDrain = {}
    for _, tid in ipairs({ fixture.homeTeamId, fixture.awayTeamId }) do
        local t = gameState.teams[tid]
        if t then
            local styleMods = TacticsResolver.getStyleModifiers(t.playStyle or "Balanced")
            teamStyleDrain[tid] = styleMods.staminaDrain or 1.0
        end
    end
    for _, p in ipairs(matchPlayers) do
        local styleDrain = teamStyleDrain[p.teamId] or 1.0
        local group = "MID"
        if p.position == "GK" then group = "GK"
        elseif p.position == "CB" or p.position == "LB" or p.position == "RB" then group = "DEF"
        elseif p.position == "ST" or p.position == "CF" or p.position == "LW" or p.position == "RW" then group = "FWD"
        end
        local range = drainData[group] or { 15, 22 }
        local baseDrain = RandomInt(range[1], range[2])
        -- 个人耐力折扣: stamina=20→×1.0, stamina=10→×0.85, stamina=5→×0.775
        local staminaAttr = (p.attributes and p.attributes.stamina) or 10
        local staminaDiscount = 0.7 + (staminaAttr / 20) * 0.3
        local finalDrain = math.floor(baseDrain * styleDrain / staminaDiscount + 0.5)
        p.fitness = math.max(40, (p.fitness or 80) - finalDrain)
    end

    -- 更新球队近期状态
    if homeTeam then
        local form = report.homeGoals > report.awayGoals and "W" or (report.homeGoals == report.awayGoals and "D" or "L")
        table.insert(homeTeam.recentForm, 1, form)
        if #homeTeam.recentForm > 5 then table.remove(homeTeam.recentForm) end
    end
    if awayTeam then
        local form = report.awayGoals > report.homeGoals and "W" or (report.awayGoals == report.homeGoals and "D" or "L")
        table.insert(awayTeam.recentForm, 1, form)
        if #awayTeam.recentForm > 5 then table.remove(awayTeam.recentForm) end
    end

    -- 更新记录系统（经理比赛统计）
    RecordsManager.onMatchEnd(gameState, fixture)

    return report
end

return PlaceholderEngine
