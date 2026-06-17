-- systems/ai_manager.lua
-- AI 球队管理系统 - 自动调阵容/训练重点/转会决策

local Constants = require("scripts/app/constants")
local FormationShape = require("scripts/match/formation_shape")
local PositionFit = require("scripts/domain/position_fit")
local TransferManager = require("scripts/systems/transfer_manager")
local AiSquadPolicy = require("scripts/systems/ai_squad_policy")

local AIManager = {}

------------------------------------------------------
-- 每周处理（周一调用）
------------------------------------------------------

function AIManager.processWeekly(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId == gameState.playerTeamId then goto continue end
        if not team then goto continue end

        AIManager.ensureTargetFirstTeamSquad(gameState, team)

        if #team.playerIds < 11 then goto continue end

        -- 1. 自动调整阵容（选择最佳首发11人）
        AIManager._adjustSquad(gameState, team)

        -- 2. 调整训练重点
        AIManager._adjustTrainingFocus(gameState, team)

        -- 3. 球员放入转会名单决策
        AIManager._evaluateTransferList(gameState, team)

        ::continue::
    end
end

------------------------------------------------------
-- 每月处理（1号调用）
------------------------------------------------------

function AIManager.processMonthly(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId == gameState.playerTeamId then goto continue end
        if not team then goto continue end

        AIManager.ensureTargetFirstTeamSquad(gameState, team)

        -- 1. 评估是否需要更换阵型
        AIManager._evaluateFormation(gameState, team)

        -- 2. 薪资管理（释放高薪低能球员）
        AIManager._manageWages(gameState, team)

        ::continue::
    end
end

------------------------------------------------------
-- 自动选择最佳首发阵容
------------------------------------------------------

function AIManager._adjustSquad(gameState, team)
    local players = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.retired and not p.injured then
            table.insert(players, p)
        end
    end

    if #players < 11 then return end

    -- 按位置分组，每个位置选最优
    local formation = team.formation or "4-4-2"
    local slots = AIManager._getFormationSlots(team)

    local selected = {}
    local usedIds = {}

    -- 先按位置需求选择
    for _, slot in ipairs(slots) do
        local bestPlayer = nil
        local bestScore = -1

        for _, p in ipairs(players) do
            if usedIds[p.id] then goto skip end

            local score = AIManager._playerPositionScore(p, slot)
            -- 加权体能和状态
            score = score * (p.fitness / 100) * (p.morale and p.morale / 100 or 1.0)

            if score > bestScore then
                bestScore = score
                bestPlayer = p
            end

            ::skip::
        end

        if bestPlayer then
            table.insert(selected, bestPlayer.id)
            usedIds[bestPlayer.id] = true
        end
    end

    -- 保存首发阵容
    team.startingXI = selected
end

--- 获取阵型对应的位置槽位（支持变体与 team.customSlots）
function AIManager._getFormationSlots(formationOrTeam, variantKey)
    if type(formationOrTeam) == "table" and formationOrTeam.formation then
        return FormationShape.getFormationSlots(formationOrTeam)
    end
    return FormationShape.getBaseFormationSlots(formationOrTeam, variantKey)
end

--- 计算球员在某位置上的适配得分
function AIManager._playerPositionScore(player, slot)
    return PositionFit.getPositionScore(player, slot)
end

------------------------------------------------------
-- 调整训练重点
------------------------------------------------------

function AIManager._adjustTrainingFocus(gameState, team)
    -- 基于球队弱点决定训练重点
    local avgAttrs = AIManager._getTeamAverageAttrs(gameState, team)

    -- 找到最弱的属性组
    local groups = {
        attack = {"shooting", "dribbling", "composure"},
        defense = {"tackling", "defending", "positioning"},
        fitness = {"speed", "stamina", "strength"},
        technical = {"passing", "vision", "decisions"},
    }

    local weakest = "balanced"
    local weakestAvg = 999

    for groupName, attrs in pairs(groups) do
        local sum = 0
        local count = 0
        for _, attr in ipairs(attrs) do
            if avgAttrs[attr] then
                sum = sum + avgAttrs[attr]
                count = count + 1
            end
        end
        if count > 0 then
            local avg = sum / count
            if avg < weakestAvg then
                weakestAvg = avg
                weakest = groupName
            end
        end
    end

    team.trainingFocus = weakest

    -- 训练强度：排名差时加强，排名好时减轻（避免伤病）
    local position = 999
    for _, lg in pairs(gameState.leagues or {}) do
        local pos = lg:getTeamPosition(team.id)
        if pos and pos < position then position = pos end
    end

    local totalTeams = 0
    for _, lg in pairs(gameState.leagues or {}) do
        totalTeams = math.max(totalTeams, #(lg.teamIds or {}))
    end

    if totalTeams > 0 then
        local ratio = position / totalTeams
        if ratio > 0.7 then
            team.trainingIntensity = "high"
        elseif ratio < 0.3 then
            team.trainingIntensity = "low"
        else
            team.trainingIntensity = "normal"
        end
    end
end

--- 获取球队平均属性
function AIManager._getTeamAverageAttrs(gameState, team)
    local totals = {}
    local count = 0

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.retired and p.attributes then
            count = count + 1
            for attr, val in pairs(p.attributes) do
                totals[attr] = (totals[attr] or 0) + val
            end
        end
    end

    local avgs = {}
    if count > 0 then
        for attr, total in pairs(totals) do
            avgs[attr] = total / count
        end
    end
    return avgs
end

------------------------------------------------------
-- 转会名单评估
------------------------------------------------------

function AIManager._evaluateTransferList(gameState, team)
    if not team.transferList then team.transferList = {} end

    -- 清理已转出的球员
    local newList = {}
    for _, pid in ipairs(team.transferList) do
        local p = gameState.players[pid]
        if p and p.teamId == team.id then
            table.insert(newList, pid)
        end
    end
    team.transferList = newList

    -- 评估是否有多余球员可以放入转会名单
    -- 规则：同位置超过4人时，放最弱的上名单
    local posCounts = {}
    local posPlayers = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.retired then
            local group = AIManager._getPositionGroup(p.position)
            posCounts[group] = (posCounts[group] or 0) + 1
            if not posPlayers[group] then posPlayers[group] = {} end
            table.insert(posPlayers[group], p)
        end
    end

    for group, players in pairs(posPlayers) do
        if #players > 4 then
            -- 按能力排序，最弱的放入转会名单
            table.sort(players, function(a, b) return a.overall < b.overall end)
            local excess = #players - 4
            for i = 1, excess do
                local p = players[i]
                if TransferManager._isAIProtectedCore(gameState, team, p) then goto skipList end
                -- 不放明显低于队均的替补（原逻辑保留为额外过滤）
                local teamAvg = TransferManager._getTeamAverageOverall(gameState, team)
                if p.overall < teamAvg - 3 then
                    -- 检查不重复添加
                    local alreadyListed = false
                    for _, lid in ipairs(team.transferList) do
                        if lid == p.id then alreadyListed = true; break end
                    end
                    if not alreadyListed then
                        table.insert(team.transferList, p.id)
                    end
                end
                ::skipList::
            end
        end
    end
end

--- 获取位置大组
function AIManager._getPositionGroup(position)
    local groups = {
        GK = "goalkeeper",
        CB = "defense", RB = "defense", LB = "defense",
        CDM = "midfield", CM = "midfield", CAM = "midfield",
        RM = "midfield", LM = "midfield",
        RW = "attack", LW = "attack", ST = "attack",
    }
    return groups[position] or "midfield"
end

------------------------------------------------------
-- 评估阵型
------------------------------------------------------

function AIManager._evaluateFormation(gameState, team)
    -- 基于球员位置分布选择最合适的阵型
    local posCounts = {goalkeeper = 0, defense = 0, midfield = 0, attack = 0}

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.retired and not p.injured then
            local group = AIManager._getPositionGroup(p.position)
            posCounts[group] = (posCounts[group] or 0) + 1
        end
    end

    -- 选择阵型
    local defRatio = posCounts.defense / math.max(1, posCounts.defense + posCounts.midfield + posCounts.attack)
    local midRatio = posCounts.midfield / math.max(1, posCounts.defense + posCounts.midfield + posCounts.attack)
    local atkRatio = posCounts.attack / math.max(1, posCounts.defense + posCounts.midfield + posCounts.attack)

    if atkRatio >= 0.4 then
        team.formation = "4-3-3"
    elseif defRatio >= 0.45 then
        team.formation = "5-3-2"
    elseif midRatio >= 0.5 then
        team.formation = "4-5-1"
    else
        team.formation = "4-4-2"
    end
end

------------------------------------------------------
-- 薪资管理
------------------------------------------------------

function AIManager._manageWages(gameState, team)
    -- 计算工资总额占比
    local totalWage = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then totalWage = totalWage + (p.wage or 0) end
    end

    -- 如果工资超过余额的 20%（月工资*4 > 余额的 80%），释放最高薪低能球员
    local monthlyWage = totalWage * 4  -- 4周
    if monthlyWage > team.balance * 0.2 and team.balance > 0 then
        -- 找到薪资最不合理的球员（工资/能力比最高）
        local worstValue = nil
        local worstRatio = 0

        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and not p.retired then
                if TransferManager._isAIProtectedCore(gameState, team, p) then goto skipWage end
                local ratio = (p.wage or 0) / math.max(1, p.overall)
                if ratio > worstRatio and #team.playerIds > Constants.AI_FIRST_TEAM_MIN then
                    worstRatio = ratio
                    worstValue = p
                end
                ::skipWage::
            end
        end

        -- 将该球员放入转会名单
        if worstValue and team.transferList then
            local alreadyListed = false
            for _, lid in ipairs(team.transferList) do
                if lid == worstValue.id then alreadyListed = true; break end
            end
            if not alreadyListed then
                table.insert(team.transferList, worstValue.id)
            end
        end
    end
end

------------------------------------------------------
-- AI转会决策（在转会窗口时由 turn_processor 调用）
------------------------------------------------------

function AIManager.makeTransferDecisions(gameState)
    -- 此函数调用 TransferManager 的 AI 转会逻辑
    -- 已在 transfer_manager.lua 的 processAITransfers 中实现
    local ok, TransferManager = pcall(require, "scripts/systems/transfer_manager")
    if ok then
        TransferManager.processAITransfers(gameState)
    end
end

------------------------------------------------------
-- 公开 API：切换阵型后重新安排首发
------------------------------------------------------

--- 根据新阵型重新排列 startingXI（供玩家手动切换阵型时调用）
--- 对每个槽位从全队中选择最佳匹配球员（首发优先加分，但允许替补替换不适配的首发）
function AIManager.rearrangeForFormation(gameState, team)
    local formation = team.formation or "4-4-2"
    local slots = AIManager._getFormationSlots(team)
    local oldXI = team.startingXI or {}

    -- 构建老首发 id 集合（用于加分）
    local oldStarterSet = {}
    for _, pid in ipairs(oldXI) do
        oldStarterSet[pid] = true
    end

    -- 获取全队可用球员
    local allAvailable = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.retired and not p.injured then
            table.insert(allAvailable, p)
        end
    end

    -- 贪心分配：对每个槽位从全队中找最佳匹配
    local newXI = {}
    local usedIds = {}

    for _, slot in ipairs(slots) do
        local bestPlayer = nil
        local bestScore = -1

        for _, p in ipairs(allAvailable) do
            if not usedIds[p.id] then
                local score = AIManager._playerPositionScore(p, slot)
                -- 老首发球员获得少量加分（同等条件下优先留用，但不阻止更适配的替补上位）
                if oldStarterSet[p.id] then
                    score = score * 1.05
                end
                if score > bestScore then
                    bestScore = score
                    bestPlayer = p
                end
            end
        end

        if bestPlayer then
            table.insert(newXI, bestPlayer.id)
            usedIds[bestPlayer.id] = true
        end
    end

    team.startingXI = newXI
end

------------------------------------------------------
-- AI 一线队最低人数保底（< AI_FIRST_TEAM_MIN 时强制补员）
------------------------------------------------------

local AI_EMERGENCY_MIN_OVR = 45
local AI_EMERGENCY_PROMOTE_AGE = 18

function AIManager.ensureAllTargetSquads(gameState)
    for teamId, team in pairs(gameState.teams or {}) do
        if teamId ~= gameState.playerTeamId then
            AIManager.ensureTargetFirstTeamSquad(gameState, team)
        end
    end
end

function AIManager.ensureAllMinimumSquads(gameState)
    AIManager.ensureAllTargetSquads(gameState)
end

---@param gameState table
---@param team table
function AIManager.ensureTargetFirstTeamSquad(gameState, team)
    if not team or team.id == gameState.playerTeamId then return end

    AIManager.ensureMinimumFirstTeamSquad(gameState, team)

    local target = AiSquadPolicy.getTargetSquadSize(team)
    local fillMinOvr = AiSquadPolicy.getRepMinOvr(team, "fill")
    local safety = 0
    while #team.playerIds < target and not team:isFirstTeamFull() and safety < target * 4 do
        safety = safety + 1
        local needGroup = AIManager._getCriticalPositionNeed(gameState, team)
        if AIManager._tryPromoteYouthForTarget(gameState, team, needGroup, fillMinOvr) then
        elseif AIManager._trySignFreeAgentForTarget(gameState, team, needGroup, fillMinOvr) then
        elseif AIManager._tryPromoteYouthForTarget(gameState, team, needGroup, fillMinOvr - 4) then
        elseif AIManager._trySignFreeAgentForTarget(gameState, team, needGroup, fillMinOvr - 4) then
        elseif AIManager._tryGenerateYouthForTarget(gameState, team, needGroup, fillMinOvr - 6) then
        else
            break
        end
    end
end

---@param gameState table
---@param team table
function AIManager.ensureMinimumFirstTeamSquad(gameState, team)
    if not team or team.id == gameState.playerTeamId then return end

    local minSize = Constants.AI_FIRST_TEAM_MIN or 20
    local safety = 0
    while #team.playerIds < minSize and not team:isFirstTeamFull() and safety < minSize * 4 do
        safety = safety + 1
        local needGroup = AIManager._getCriticalPositionNeed(gameState, team)
        if AIManager._tryPromoteYouthForMinimum(gameState, team, needGroup) then
        elseif AIManager._trySignFreeAgentForMinimum(gameState, team, needGroup) then
        elseif AIManager._tryGenerateYouthForMinimum(gameState, team, needGroup) then
        else
            break
        end
    end
end

function AIManager._countPositionGroups(gameState, team)
    local posCount = { GK = 0, DEF = 0, MID = 0, FWD = 0 }
    for _, pid in ipairs(team.playerIds or {}) do
        local player = gameState.players[pid]
        if player and not player.retired then
            for group, positions in pairs(Constants.POSITION_GROUPS) do
                for _, pos in ipairs(positions) do
                    if player.position == pos then
                        posCount[group] = posCount[group] + 1
                        break
                    end
                end
            end
        end
    end
    return posCount
end

function AIManager._getCriticalPositionNeed(gameState, team)
    local posCount = AIManager._countPositionGroups(gameState, team)
    if posCount.GK < 2 then return "GK" end
    if posCount.DEF < 4 then return "DEF" end
    if posCount.MID < 4 then return "MID" end
    if posCount.FWD < 2 then return "FWD" end
    local groups = {"DEF", "MID", "FWD"}
    return groups[RandomInt(1, #groups)]
end

function AIManager._playerMatchesGroup(player, needGroup)
    if not needGroup then return true end
    local positions = Constants.POSITION_GROUPS[needGroup]
    if not positions then return true end
    for _, pos in ipairs(positions) do
        if player.position == pos then return true end
    end
    return false
end

function AIManager._finalizeEmergencySign(gameState, team, player, years)
    years = years or 2
    player.isYouth = false
    player.isFreeAgent = nil
    player.listedForSale = false
    player.listedForLoan = false
    player.wage = math.max(500, math.floor((player.overall or 50) * 80))
    player.contractEnd = { year = gameState.date.year + years, month = 6, day = 30 }
    player.squadRole = player.squadRole or "squad"
end

function AIManager._tryPromoteYouthForTarget(gameState, team, needGroup, minOvr)
    minOvr = minOvr or AiSquadPolicy.getRepMinOvr(team, "fill")
    team._youthPlayerIds = team._youthPlayerIds or {}
    local bestIdx, bestOvr = nil, -1
    local fallbackIdx, fallbackOvr = nil, -1

    for i, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if not player or player.teamId ~= team.id then goto continueYouth end
        local age = gameState.date.year - (player.birthYear or 2000)
        if age < AI_EMERGENCY_PROMOTE_AGE or (player.overall or 0) < minOvr then
            goto continueYouth
        end
        if AIManager._playerMatchesGroup(player, needGroup) then
            if (player.overall or 0) > bestOvr then
                bestOvr = player.overall
                bestIdx = i
            end
        elseif (player.overall or 0) > fallbackOvr then
            fallbackOvr = player.overall
            fallbackIdx = i
        end
        ::continueYouth::
    end

    local idx = bestIdx or fallbackIdx
    if not idx then return false end

    local pid = team._youthPlayerIds[idx]
    table.remove(team._youthPlayerIds, idx)
    local player = gameState.players[pid]
    if not player then return false end

    if not TransferManager._assignPlayerToTeam(gameState, player, team.id) then
        table.insert(team._youthPlayerIds, pid)
        return false
    end
    AIManager._finalizeEmergencySign(gameState, team, player, 3)
    return true
end

function AIManager._trySignFreeAgentForTarget(gameState, team, needGroup, minOvr)
    minOvr = minOvr or 45
    local groupsToTry = { needGroup, nil }
    local best = nil
    for _, group in ipairs(groupsToTry) do
        local freeAgents = TransferManager.getFreeAgents(gameState, group)
        for _, player in ipairs(freeAgents) do
            if player.teamId or player.retired then goto nextFa end
            if (player.overall or 0) < minOvr then goto nextFa end
            if needGroup and not AIManager._playerMatchesGroup(player, needGroup) then goto nextFa end
            if not best or (player.overall or 0) > (best.overall or 0) then
                best = player
            end
            ::nextFa::
        end
    end
    if not best then return false end
    if TransferManager._assignPlayerToTeam(gameState, best, team.id) then
        AIManager._finalizeEmergencySign(gameState, team, best, 2)
        return true
    end
    return false
end

function AIManager._tryGenerateYouthForTarget(gameState, team, needGroup, minOvr)
    minOvr = minOvr or AiSquadPolicy.getRepMinOvr(team, "emergency")
    local YouthManager = require("scripts/systems/youth_manager")
    local PotentialSystem = require("scripts/systems/potential_system")
    local Nationality = require("scripts/domain/nationality")
    local Player = require("scripts/domain/player")

    local youthDevBonus, facilityYouthBonus =
        YouthManager._getTeamYouthGenBonuses(gameState, team.id)
    local usedNames = {}

    local candidate = nil
    for _ = 1, 16 do
        local roll = YouthManager._generateYouthPlayer(
            gameState, youthDevBonus, facilityYouthBonus, usedNames, team.country)
        if (roll.overall or 0) >= minOvr then
            if needGroup ~= "GK" or roll.position == "GK" then
                candidate = roll
                break
            end
        end
        if not candidate or (roll.overall or 0) > (candidate.overall or 0) then
            if needGroup ~= "GK" or roll.position == "GK" then
                candidate = roll
            end
        end
    end
    if not candidate then return false end

    if needGroup == "GK" and candidate.position ~= "GK" then
        candidate.position = "GK"
        candidate.attributes = YouthManager._generateAttributes("GK", candidate.overall)
        candidate.overall = Player.calculateOverallFromAttrs("GK", candidate.attributes)
    elseif needGroup and needGroup ~= "GK" then
        local positions = Constants.POSITION_GROUPS[needGroup]
        if positions and not AIManager._playerMatchesGroup({ position = candidate.position }, needGroup) then
            candidate.position = positions[RandomInt(1, #positions)]
            candidate.attributes = YouthManager._generateAttributes(candidate.position, candidate.overall)
            candidate.overall = Player.calculateOverallFromAttrs(candidate.position, candidate.attributes)
        end
    end

    if (candidate.overall or 0) < minOvr then
        candidate.overall = minOvr
        candidate.attributes = YouthManager._generateAttributes(candidate.position, candidate.overall)
        candidate.overall = Player.calculateOverallFromAttrs(candidate.position, candidate.attributes)
    end

    if candidate.age < AI_EMERGENCY_PROMOTE_AGE then
        candidate.birthYear = gameState.date.year - AI_EMERGENCY_PROMOTE_AGE
        candidate.age = AI_EMERGENCY_PROMOTE_AGE
    end

    local player = gameState:addPlayer({
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = Nationality.normalize(candidate.nationality),
        birthYear = math.floor(candidate.birthYear),
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = 500,
        teamId = team.id,
        contractEnd = { year = gameState.date.year + 3, month = 6, day = 30 },
    })
    player.paRating = PotentialSystem.rawToRating(player.potential)
    player.actualPotential = PotentialSystem.generateActualPotential(
        player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)
    player:calculateOverall()

    if not TransferManager._assignPlayerToTeam(gameState, player, team.id) then
        gameState.players[player.id] = nil
        return false
    end
    AIManager._finalizeEmergencySign(gameState, team, player, 3)
    return true
end

function AIManager._tryPromoteYouthForMinimum(gameState, team, needGroup)
    team._youthPlayerIds = team._youthPlayerIds or {}
    local bestIdx, bestOvr = nil, -1
    local fallbackIdx, fallbackOvr = nil, -1

    for i, pid in ipairs(team._youthPlayerIds) do
        local player = gameState.players[pid]
        if not player or player.teamId ~= team.id then goto continueYouth end
        local age = gameState.date.year - (player.birthYear or 2000)
        if age < AI_EMERGENCY_PROMOTE_AGE or (player.overall or 0) < AI_EMERGENCY_MIN_OVR then
            goto continueYouth
        end
        if AIManager._playerMatchesGroup(player, needGroup) then
            if (player.overall or 0) > bestOvr then
                bestOvr = player.overall
                bestIdx = i
            end
        elseif (player.overall or 0) > fallbackOvr then
            fallbackOvr = player.overall
            fallbackIdx = i
        end
        ::continueYouth::
    end

    local idx = bestIdx or fallbackIdx
    if not idx then return false end

    local pid = team._youthPlayerIds[idx]
    table.remove(team._youthPlayerIds, idx)
    local player = gameState.players[pid]
    if not player then return false end

    if not TransferManager._assignPlayerToTeam(gameState, player, team.id) then
        table.insert(team._youthPlayerIds, pid)
        return false
    end
    AIManager._finalizeEmergencySign(gameState, team, player, 3)
    return true
end

function AIManager._trySignFreeAgentForMinimum(gameState, team, needGroup)
    local groupsToTry = { needGroup, nil }
    for _, group in ipairs(groupsToTry) do
        local freeAgents = TransferManager.getFreeAgents(gameState, group)
        for _, player in ipairs(freeAgents) do
            if player.teamId or player.retired then goto nextFa end
            if TransferManager._assignPlayerToTeam(gameState, player, team.id) then
                AIManager._finalizeEmergencySign(gameState, team, player, 2)
                return true
            end
            ::nextFa::
        end
    end
    return false
end

function AIManager._tryGenerateYouthForMinimum(gameState, team, needGroup)
    local YouthManager = require("scripts/systems/youth_manager")
    local PotentialSystem = require("scripts/systems/potential_system")
    local Nationality = require("scripts/domain/nationality")
    local Player = require("scripts/domain/player")

    local youthDevBonus, facilityYouthBonus =
        YouthManager._getTeamYouthGenBonuses(gameState, team.id)
    local usedNames = {}

    local candidate = nil
    for _ = 1, 12 do
        local roll = YouthManager._generateYouthPlayer(
            gameState, youthDevBonus, facilityYouthBonus, usedNames, team.country)
        if needGroup ~= "GK" or roll.position == "GK" then
            candidate = roll
            break
        end
    end
    if not candidate then return false end

    if needGroup == "GK" and candidate.position ~= "GK" then
        candidate.position = "GK"
        candidate.attributes = YouthManager._generateAttributes("GK", candidate.overall)
        candidate.overall = Player.calculateOverallFromAttrs("GK", candidate.attributes)
    elseif needGroup and needGroup ~= "GK" then
        local positions = Constants.POSITION_GROUPS[needGroup]
        if positions and not AIManager._playerMatchesGroup({ position = candidate.position }, needGroup) then
            candidate.position = positions[RandomInt(1, #positions)]
            candidate.attributes = YouthManager._generateAttributes(candidate.position, candidate.overall)
            candidate.overall = Player.calculateOverallFromAttrs(candidate.position, candidate.attributes)
        end
    end

    if candidate.age < AI_EMERGENCY_PROMOTE_AGE then
        candidate.birthYear = gameState.date.year - AI_EMERGENCY_PROMOTE_AGE
        candidate.age = AI_EMERGENCY_PROMOTE_AGE
    end

    local player = gameState:addPlayer({
        firstName = candidate.firstName,
        lastName = candidate.lastName,
        displayName = candidate.displayName,
        nationality = Nationality.normalize(candidate.nationality),
        birthYear = math.floor(candidate.birthYear),
        position = candidate.position,
        attributes = candidate.attributes,
        potential = candidate.potential,
        overall = candidate.overall,
        wage = 500,
        teamId = team.id,
        contractEnd = { year = gameState.date.year + 3, month = 6, day = 30 },
    })
    player.paRating = PotentialSystem.rawToRating(player.potential)
    player.actualPotential = PotentialSystem.generateActualPotential(
        player.paRating, (gameState.potentialSeed or 0) + player.id * 7919)
    player:calculateOverall()

    if not TransferManager._assignPlayerToTeam(gameState, player, team.id) then
        gameState.players[player.id] = nil
        return false
    end
    AIManager._finalizeEmergencySign(gameState, team, player, 3)
    return true
end

return AIManager
