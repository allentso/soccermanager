-- systems/ai_manager.lua
-- AI 球队管理系统 - 自动调阵容/训练重点/转会决策

local Constants = require("scripts/app/constants")

local AIManager = {}

------------------------------------------------------
-- 每周处理（周一调用）
------------------------------------------------------

function AIManager.processWeekly(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId == gameState.playerTeamId then goto continue end
        if not team or #team.playerIds < 11 then goto continue end

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
    local slots = AIManager._getFormationSlots(formation)

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

--- 获取阵型对应的位置槽位
function AIManager._getFormationSlots(formation)
    local formations = {
        ["4-4-2"] = {"GK", "RB", "CB", "CB", "LB", "RM", "CM", "CM", "LM", "ST", "ST"},
        ["4-3-3"] = {"GK", "RB", "CB", "CB", "LB", "CDM", "CM", "CM", "RW", "ST", "LW"},
        ["3-5-2"] = {"GK", "CB", "CB", "CB", "RM", "CM", "CDM", "CM", "LM", "ST", "ST"},
        ["4-2-3-1"] = {"GK", "RB", "CB", "CB", "LB", "CDM", "CDM", "CAM", "RW", "LW", "ST"},
        ["4-5-1"] = {"GK", "RB", "CB", "CB", "LB", "RM", "CM", "CDM", "CM", "LM", "ST"},
        ["5-3-2"] = {"GK", "RB", "CB", "CB", "CB", "LB", "CM", "CM", "CM", "ST", "ST"},
    }
    return formations[formation] or formations["4-4-2"]
end

--- 计算球员在某位置上的适配得分
function AIManager._playerPositionScore(player, slot)
    local pos = player.position
    local attrs = player.attributes or {}

    -- 完全匹配
    if pos == slot then return player.overall end

    -- 位置组兼容性
    local compatibility = {
        GK = {GK = 1.0},
        CB = {CB = 1.0, RB = 0.6, LB = 0.6, CDM = 0.5},
        RB = {RB = 1.0, CB = 0.6, RM = 0.7, LB = 0.8},
        LB = {LB = 1.0, CB = 0.6, LM = 0.7, RB = 0.8},
        CDM = {CDM = 1.0, CM = 0.8, CB = 0.5},
        CM = {CM = 1.0, CDM = 0.8, CAM = 0.7, RM = 0.6, LM = 0.6},
        CAM = {CAM = 1.0, CM = 0.7, RW = 0.6, LW = 0.6, ST = 0.5},
        RM = {RM = 1.0, RW = 0.9, CM = 0.6, RB = 0.5, LM = 0.7},
        LM = {LM = 1.0, LW = 0.9, CM = 0.6, LB = 0.5, RM = 0.7},
        RW = {RW = 1.0, RM = 0.9, ST = 0.6, CAM = 0.6, LW = 0.7},
        LW = {LW = 1.0, LM = 0.9, ST = 0.6, CAM = 0.6, RW = 0.7},
        ST = {ST = 1.0, CAM = 0.6, RW = 0.5, LW = 0.5},
    }

    local posCompat = compatibility[slot]
    if posCompat and posCompat[pos] then
        return player.overall * posCompat[pos]
    end

    -- 无兼容性：大幅降低
    return player.overall * 0.3
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
                -- 不放核心球员（能力前5）
                if p.overall < (team.averageOverall or 50) - 3 then
                    -- 检查不重复添加
                    local alreadyListed = false
                    for _, lid in ipairs(team.transferList) do
                        if lid == p.id then alreadyListed = true; break end
                    end
                    if not alreadyListed then
                        table.insert(team.transferList, p.id)
                    end
                end
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
                local ratio = (p.wage or 0) / math.max(1, p.overall)
                if ratio > worstRatio and #team.playerIds > 18 then
                    worstRatio = ratio
                    worstValue = p
                end
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
    local slots = AIManager._getFormationSlots(formation)
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

return AIManager
