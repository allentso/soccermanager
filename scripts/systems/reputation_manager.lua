-- systems/reputation_manager.lua
-- 声望动态系统：球队和经理声望随胜负/排名/奖项动态变化

local EventBus = require("scripts/app/event_bus")

local ReputationManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
-- 球队声望范围 500-950（与 real_data_loader._calcReputation 一致）
-- 经理声望范围 1-99（独立体系）
local TEAM_REP_MIN = 500
local TEAM_REP_MAX = 950
local MGR_REP_MIN = 1
local MGR_REP_MAX = 99

-- 声望变化幅度（球队声望在 500-950 范围内变动，步长相应放大约 5x）
local MATCH_WIN_REP = 2.5
local MATCH_DRAW_REP = 0.0
local MATCH_LOSS_REP = -1.0
local BIG_WIN_BONUS = 1.5        -- 大胜（3球以上）额外
local UPSET_BONUS = 5.0          -- 以弱胜强（声望差>75）

-- 赛季结束奖励（球队声望级别）
local SEASON_END_BONUS = {
    [1] = 50,  -- 冠军
    [2] = 25,  -- 亚军
    [3] = 15,  -- 季军
    [4] = 5,   -- 第4
}

-- 杯赛/欧冠奖励
local CUP_WINNER_REP = 40        -- 欧冠/顶级杯赛冠军
local CUP_FINALIST_REP = 20      -- 亚军

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 比赛后更新声望（每场比赛后调用）
---@param gameState table
---@param teamId number
---@param opponentId number
---@param result string "W"|"D"|"L"
---@param goalDiff? number 净胜球
function ReputationManager.postMatchUpdate(gameState, teamId, opponentId, result, goalDiff)
    local team = gameState.teams[teamId]
    if not team then return end

    local opponent = gameState.teams[opponentId]
    local opponentRep = opponent and opponent.reputation or 600

    local delta = 0

    -- 基础胜负变化
    if result == "W" then
        delta = MATCH_WIN_REP
    elseif result == "L" then
        delta = MATCH_LOSS_REP
    else
        delta = MATCH_DRAW_REP
    end

    -- 大胜/大败加成
    goalDiff = goalDiff or 0
    if result == "W" and goalDiff >= 3 then
        delta = delta + BIG_WIN_BONUS
    elseif result == "L" and goalDiff <= -3 then
        delta = delta - BIG_WIN_BONUS
    end

    -- 以弱胜强/以强负弱（声望差>75 在 500-950 体系中约等于跨级别）
    local repDiff = opponentRep - (team.reputation or 600)
    if result == "W" and repDiff > 75 then
        delta = delta + UPSET_BONUS
    elseif result == "L" and repDiff < -75 then
        delta = delta - UPSET_BONUS * 0.5
    end

    team.reputation = math.max(TEAM_REP_MIN, math.min(TEAM_REP_MAX, (team.reputation or 600) + delta))

    -- 经理声望同步变化（缩放到经理的 1-99 范围）
    local mgrDelta = delta / 5  -- 球队步长约为经理的5倍
    ReputationManager._updateManagerRep(gameState, teamId, mgrDelta)
end

--- 赛季结束排名奖励
---@param gameState table
function ReputationManager.seasonEndUpdate(gameState)
    -- 遍历所有联赛
    for _, lg in pairs(gameState.leagues) do
        local standings = lg.standings or {}
        for position, entry in ipairs(standings) do
            local teamId = entry.teamId
            local team = gameState.teams[teamId]
            if team then
                local bonus = SEASON_END_BONUS[position] or 0
                -- 低排名扣分
                if position > #standings - 3 then
                    bonus = -10  -- 降级区附近
                elseif position > #standings / 2 then
                    bonus = -2  -- 下半区
                end
                team.reputation = math.max(TEAM_REP_MIN, math.min(TEAM_REP_MAX, (team.reputation or 600) + bonus))

                -- 经理声望（缩放到 1-99）
                if teamId == gameState.playerTeamId then
                    ReputationManager._updateManagerRep(gameState, teamId, bonus / 5)
                end
            end
        end
    end
end

--- 杯赛奖励（冠军/亚军）
---@param gameState table
---@param teamId number
---@param isWinner boolean
function ReputationManager.cupResultUpdate(gameState, teamId, isWinner)
    local team = gameState.teams[teamId]
    if not team then return end

    local bonus = isWinner and CUP_WINNER_REP or CUP_FINALIST_REP
    team.reputation = math.max(TEAM_REP_MIN, math.min(TEAM_REP_MAX, (team.reputation or 600) + bonus))

    -- 经理声望（缩放到 1-99）
    if teamId == gameState.playerTeamId then
        ReputationManager._updateManagerRep(gameState, teamId, bonus / 5)
    end
end

--- 全联赛声望自然回归（每月调用一次，防止通胀/通缩）
---@param gameState table
function ReputationManager.monthlyDecay(gameState)
    for _, team in pairs(gameState.teams) do
        local rep = team.reputation or 600
        -- 声望向基准线缓慢回归（基准线即初始声望，500-950 范围）
        local baseline = team._baseReputation or team.reputation or 600
        if rep > baseline + 25 then
            team.reputation = rep - 1.5
        elseif rep < baseline - 25 then
            team.reputation = rep + 1.0
        end
    end
end

--- 获取声望等级标签
---@param reputation number 球队声望（500-950范围）
---@return string
function ReputationManager.getReputationLabel(reputation)
    if reputation >= 900 then return "世界顶级"
    elseif reputation >= 800 then return "洲际强队"
    elseif reputation >= 700 then return "联赛劲旅"
    elseif reputation >= 620 then return "中游球队"
    elseif reputation >= 550 then return "保级球队"
    else return "弱旅"
    end
end

--- 获取经理声望等级
---@param gameState table
---@return string label, number reputation
function ReputationManager.getManagerReputation(gameState)
    local manager = gameState:getPlayerManager()
    if not manager then return "无名之辈", 0 end
    local rep = manager.reputation or 30
    local label
    if rep >= 85 then label = "传奇教头"
    elseif rep >= 70 then label = "名帅"
    elseif rep >= 55 then label = "知名教练"
    elseif rep >= 40 then label = "普通教练"
    elseif rep >= 25 then label = "新人教练"
    else label = "无名之辈"
    end
    return label, rep
end

------------------------------------------------------
-- AI球队每周更新（简化版）
------------------------------------------------------

--- 基于联赛排名为所有AI球队微调声望
---@param gameState table
function ReputationManager.processWeeklyAI(gameState)
    for _, lg in pairs(gameState.leagues) do
        local standings = lg.standings or {}
        local total = #standings
        for position, entry in ipairs(standings) do
            local teamId = entry.teamId
            if teamId ~= gameState.playerTeamId then
                local team = gameState.teams[teamId]
                if team then
                    -- 排名靠前声望微涨，靠后微降（500-950体系下步长放大）
                    local normalizedPos = position / math.max(total, 1)
                    local delta = (0.5 - normalizedPos) * 1.0
                    team.reputation = math.max(TEAM_REP_MIN, math.min(TEAM_REP_MAX, (team.reputation or 600) + delta))
                end
            end
        end
    end
end

------------------------------------------------------
-- 内部
------------------------------------------------------

function ReputationManager._updateManagerRep(gameState, teamId, delta)
    if teamId ~= gameState.playerTeamId then return end
    local manager = gameState:getPlayerManager()
    if not manager then return end
    manager.reputation = math.max(MGR_REP_MIN, math.min(MGR_REP_MAX, (manager.reputation or 30) + delta))
end

return ReputationManager
