-- systems/morale_manager.lua
-- 球员士气系统：核心因素、每周更新、表现加成

local MessageManager = require("scripts/systems/message_manager")
local Constants = require("scripts/app/constants")
local League = require("scripts/domain/league")

local MoraleManager = {}

------------------------------------------------------
-- 士气常量
------------------------------------------------------
local MORALE_MIN = Constants.MORALE_MIN    -- 20
local MORALE_MAX = Constants.MORALE_MAX    -- 100
local MORALE_DEFAULT = 60

-- 士气等级
local MORALE_LEVELS = {
    { min = 80, label = "斗志昂扬", bonus = 0.05 },
    { min = 60, label = "状态良好", bonus = 0.0 },
    { min = 40, label = "情绪一般", bonus = -0.02 },
    { min = 20, label = "心生不满", bonus = -0.05 },
    { min = 0,  label = "极度低落", bonus = -0.10 },
}

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每周更新所有玩家球队球员士气
---@param gameState table
function MoraleManager.processWeekly(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local lowMoralePlayers = {}

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            local delta = MoraleManager._calculateWeeklyDelta(gameState, player, team)
            player.morale = math.max(MORALE_MIN, math.min(MORALE_MAX, (player.morale or MORALE_DEFAULT) + delta))

            -- 收集低士气球员
            if player.morale < 30 then
                table.insert(lowMoralePlayers, player)
            end
        end
    end

    -- 发送低士气警告（最多3个），附带决策按钮
    for i = 1, math.min(3, #lowMoralePlayers) do
        local p = lowMoralePlayers[i]
        local reason = MoraleManager._getLowMoraleReason(gameState, p, team)
        local actions = MoraleManager._buildMoraleActions(gameState, p, team)
        gameState:sendMessage({
            category = "morale",
            title = "球员不满",
            body = string.format("%s 士气低落(%d%%)。%s", p.displayName, p.morale, reason),
            priority = "normal",
            popup = true,
            actions = actions,
        })
    end
end

--- 根据球员不满原因生成决策按钮
function MoraleManager._buildMoraleActions(gameState, player, team)
    local actions = {}
    local role = player.squadRole or "rotation"

    -- 核心球员不上场 → 提供加薪安抚或查看球员
    local isStarter = false
    for _, sid in pairs(team.startingXI or {}) do
        if sid == player.id then isStarter = true; break end
    end

    local hadClubMatch = MoraleManager._teamHadClubMatchInPastDays(gameState, team.id, 7)
    if hadClubMatch and not isStarter and (role == "key" or role == "rotation") then
        -- 建议降低角色期望
        local lowerRole = role == "key" and "rotation" or "squad"
        local lowerLabel = role == "key" and "轮换球员" or "阵容球员"
        table.insert(actions, {
            label = "调整为「" .. lowerLabel .. "」",
            actionId = "promote_role",
            data = { playerId = player.id, newRole = lowerRole, roleLabel = lowerLabel },
        })
    end

    -- 提供加薪安抚选项
    table.insert(actions, {
        label = "加薪安抚 (+20%)",
        actionId = "grant_raise",
        data = { playerId = player.id, raisePercent = 20 },
    })

    -- 查看球员详情
    table.insert(actions, {
        label = "查看球员",
        actionId = "view_player",
        data = { playerId = player.id },
    })

    return actions
end

--- AI球队士气简化更新
---@param gameState table
function MoraleManager.processAITeams(gameState)
    for teamId, team in pairs(gameState.teams) do
        if teamId ~= gameState.playerTeamId then
            -- 声望回归基线：豪门心理更稳（基线高、单赛季低迷不易崩盘），
            -- 小球队更易波动（基线低）。与"青训按声望分方差"同一套分级哲学。
            local rep = team.reputation or 600
            local repBase = 58 + math.max(0, math.min(10, (rep - 550) / 35))  -- 58~68
            -- 近期战绩：胜场抬升目标士气
            local form = team.recentForm or {}
            local wins = 0
            for _, r in ipairs(form) do
                if r == "W" then wins = wins + 1 end
            end
            local targetMorale = repBase + wins * 3

            for _, pid in ipairs(team.playerIds) do
                local player = gameState.players[pid]
                if player and not player.retired then
                    local current = player.morale or MORALE_DEFAULT
                    local delta = (targetMorale - current) * 0.15
                    delta = delta + (Random() - 0.5) * 4
                    player.morale = math.max(MORALE_MIN, math.min(MORALE_MAX, current + delta))
                end
            end
        end
    end
end

--- 比赛后更新士气
---@param gameState table
---@param teamId number
---@param result string "W"|"D"|"L"
---@param playerRatings? table {[playerId] = rating}
function MoraleManager.postMatchUpdate(gameState, teamId, result, playerRatings)
    local team = gameState.teams[teamId]
    if not team then return end

    local baseDelta = 0
    if result == "W" then baseDelta = 5
    elseif result == "L" then baseDelta = -4
    else baseDelta = 1
    end

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player then
            local delta = baseDelta

            -- 首发球员额外加成
            local isStarter = false
            for _, sid in pairs(team.startingXI or {}) do
                if sid == pid then isStarter = true; break end
            end

            if isStarter then
                delta = delta + 2
                -- 高评分额外加成
                if playerRatings and playerRatings[pid] then
                    local rating = playerRatings[pid]
                    if rating >= 8.0 then delta = delta + 3
                    elseif rating >= 7.0 then delta = delta + 1
                    elseif rating < 5.0 then delta = delta - 2
                    end
                end
            else
                -- 替补球员：连续不上场→不满
                player._benchCount = (player._benchCount or 0) + 1
                if player._benchCount >= 3 then
                    delta = delta - 3
                end
            end

            -- 信任度修正：高信任减缓负面影响，放大正面
            local mc = player.morale_core
            if mc then
                local trustFactor = (mc.manager_trust - 50) / 100  -- -0.5 to +0.5
                if delta > 0 then
                    delta = math.floor(delta * (1.0 + trustFactor * 0.3) + 0.5)
                elseif delta < 0 then
                    delta = math.floor(delta * (1.0 - trustFactor * 0.3) + 0.5)
                end
            end

            player.morale = math.max(MORALE_MIN, math.min(MORALE_MAX, (player.morale or MORALE_DEFAULT) + delta))
        end
    end
end

--- 续约成功/失败影响士气
function MoraleManager.onContractEvent(player, success)
    if success then
        player.morale = math.min(MORALE_MAX, (player.morale or MORALE_DEFAULT) + 10)
    else
        player.morale = math.max(MORALE_MIN, (player.morale or MORALE_DEFAULT) - 15)
    end
end

--- 阵容角色变更对士气的影响
---@param player table
---@param oldRole string
---@param newRole string
function MoraleManager.onSquadRoleChange(player, oldRole, newRole)
    -- 角色等级映射 (越高=越重要)
    local ROLE_RANK = { key = 4, rotation = 3, squad = 2, youth = 1 }
    local oldRank = ROLE_RANK[oldRole] or 3
    local newRank = ROLE_RANK[newRole] or 3

    local delta = 0
    if newRank > oldRank then
        -- 提升角色 → 士气提升
        delta = (newRank - oldRank) * 5
    elseif newRank < oldRank then
        -- 降低角色 → 士气下降（高能力球员受降级打击更大）
        delta = (newRank - oldRank) * 6
        if player.overall and player.overall >= 70 then
            delta = delta - 3  -- 高能力球员更不满
        end
    end

    player.morale = math.max(MORALE_MIN, math.min(MORALE_MAX, (player.morale or MORALE_DEFAULT) + delta))
end

--- 获取球员士气等级和加成
---@param player table
---@return string level, number bonus
function MoraleManager.getMoraleLevel(player)
    local morale = player.morale or MORALE_DEFAULT
    for _, level in ipairs(MORALE_LEVELS) do
        if morale >= level.min then
            return level.label, level.bonus
        end
    end
    return "极度低落", -0.10
end

--- 获取球员表现加成系数（用于比赛引擎）
---@param player table
---@return number 0.9 ~ 1.05
function MoraleManager.getPerformanceMultiplier(player)
    local _, bonus = MoraleManager.getMoraleLevel(player)
    return 1.0 + bonus
end

------------------------------------------------------
-- 内部计算
------------------------------------------------------

local function fixtureInvolvesTeam(fixture, teamId)
    return fixture.homeTeamId == teamId or fixture.awayTeamId == teamId
end

local function dateOnOrAfter(a, b)
    if a.year ~= b.year then return a.year > b.year end
    if a.month ~= b.month then return a.month > b.month end
    return a.day >= b.day
end

local function dateOnOrBefore(a, b)
    if a.year ~= b.year then return a.year < b.year end
    if a.month ~= b.month then return a.month < b.month end
    return a.day <= b.day
end

local function dateInRange(date, startDate, endDate)
    return dateOnOrAfter(date, startDate) and dateOnOrBefore(date, endDate)
end

--- 遍历球队相关的已完赛俱乐部赛事（联赛 / 国内杯 / 欧冠）
local function forEachFinishedClubFixture(gameState, teamId, callback)
    for _, lg in pairs(gameState.leagues or {}) do
        for _, fixture in ipairs(lg.fixtures or {}) do
            if fixture.status == "finished" and fixtureInvolvesTeam(fixture, teamId) then
                callback(fixture)
            end
        end
    end

    local ucl = gameState.championsLeague
    if ucl and ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, fixture in ipairs(ucl.leaguePhase.fixtures) do
            if fixture.status == "finished" and fixtureInvolvesTeam(fixture, teamId) then
                callback(fixture)
            end
        end
    end
    if ucl and ucl.knockout then
        for _, phaseFixtures in pairs(ucl.knockout) do
            for _, fixture in ipairs(phaseFixtures or {}) do
                if fixture.status == "finished" and fixtureInvolvesTeam(fixture, teamId) then
                    callback(fixture)
                end
            end
        end
    end

    for _, cup in pairs(gameState.domesticCups or {}) do
        for _, roundFixtures in ipairs(cup.rounds or {}) do
            for _, fixture in ipairs(roundFixtures or {}) do
                if fixture.status == "finished" and fixtureInvolvesTeam(fixture, teamId) then
                    callback(fixture)
                end
            end
        end
    end
end

--- 过去 N 天内球队是否有已完赛的俱乐部比赛（休赛期 / 无赛周返回 false）
function MoraleManager._teamHadClubMatchInPastDays(gameState, teamId, days)
    days = days or 7
    if not gameState or not gameState.date or not teamId then return false end

    local endDate = gameState.date
    local startDate = League._addDays(endDate, -(days - 1))
    local hadMatch = false

    forEachFinishedClubFixture(gameState, teamId, function(fixture)
        if fixture.date and dateInRange(fixture.date, startDate, endDate) then
            hadMatch = true
        end
    end)

    return hadMatch
end

function MoraleManager._calculateWeeklyDelta(gameState, player, team)
    local delta = 0
    local hadClubMatch = MoraleManager._teamHadClubMatchInPastDays(gameState, team.id, 7)

    -- 1. 出场时间因素（仅在有俱乐部比赛的周生效；休赛期不累计不满）
    if hadClubMatch then
        local isStarter = false
        for _, sid in pairs(team.startingXI or {}) do
            if sid == player.id then isStarter = true; break end
        end

        local role = player.squadRole or "rotation"
        if isStarter then
            delta = delta + 2
            player._benchCount = 0
            -- Key 球员在首发中满意度高
            if role == "key" then delta = delta + 1 end
        else
            player._benchCount = (player._benchCount or 0) + 1
            -- 角色期望与实际出场不匹配
            if role == "key" then
                -- 核心球员不首发 → 强烈不满
                if player._benchCount >= 2 then delta = delta - 6
                else delta = delta - 3 end
            elseif role == "rotation" then
                -- 轮换球员偶尔不上场可接受
                if player._benchCount >= 4 then delta = delta - 4
                elseif player._benchCount >= 2 then delta = delta - 2 end
            elseif role == "squad" then
                -- 阵容球员对不上场容忍度高
                if player._benchCount >= 6 then delta = delta - 2 end
            end
            -- youth 角色完全不介意不上场
        end
    end

    -- 2. 球队成绩因素
    local form = team.recentForm or {}
    local formDelta = 0
    for _, r in ipairs(form) do
        if r == "W" then formDelta = formDelta + 1
        elseif r == "L" then formDelta = formDelta - 1
        end
    end
    delta = delta + formDelta

    -- 3. 合同因素（合同快到期且未续约→不安）
    if player.contractEnd then
        local monthsLeft = (player.contractEnd.year - gameState.date.year) * 12
            + (player.contractEnd.month - gameState.date.month)
        if monthsLeft <= 6 then
            delta = delta - 3
        end
    end

    -- 4. 训练强度因素
    if team.trainingIntensity == "high" then
        delta = delta - 1
    elseif team.trainingIntensity == "low" then
        delta = delta + 1
    end

    -- 5. 信任度修正
    local mc = player.morale_core
    if mc then
        local trustFactor = (mc.manager_trust - 50) / 100
        if delta > 0 then
            delta = delta * (1.0 + trustFactor * 0.2)
        elseif delta < 0 then
            delta = delta * (1.0 - trustFactor * 0.2)
        end
    end

    -- 6. 随机波动
    delta = delta + (Random() - 0.5) * 4

    return math.floor(delta)
end

function MoraleManager._getLowMoraleReason(gameState, player, team)
    -- 判断主要原因
    local isStarter = false
    for _, sid in pairs(team.startingXI or {}) do
        if sid == player.id then isStarter = true; break end
    end

    local role = player.squadRole or "rotation"
    local hadClubMatch = MoraleManager._teamHadClubMatchInPastDays(gameState, team.id, 7)

    -- 核心球员未首发 → 最高优先级（仅在有俱乐部比赛的阶段）
    if hadClubMatch and not isStarter and role == "key" and (player._benchCount or 0) >= 2 then
        return "原因：作为核心球员却未能首发出场。考虑调整阵容或降低其角色定位。"
    end

    if hadClubMatch and not isStarter and (player._benchCount or 0) >= 3 then
        return "原因：长期未获得上场机会。"
    end

    if player.contractEnd then
        local monthsLeft = (player.contractEnd.year - gameState.date.year) * 12
            + (player.contractEnd.month - gameState.date.month)
        if monthsLeft <= 6 then
            return "原因：合同即将到期且未收到续约邀请。"
        end
    end

    local form = team.recentForm or {}
    local losses = 0
    for _, r in ipairs(form) do
        if r == "L" then losses = losses + 1 end
    end
    if losses >= 3 then
        return "原因：球队近期成绩不佳。"
    end

    return "原因：综合因素导致情绪低落。"
end

return MoraleManager
