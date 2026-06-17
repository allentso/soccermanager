-- systems/ai_squad_policy.lua
-- AI 阵容规模、引援质量底线、财务底盘分档（供 AIManager / TransferManager / SeasonManager 共用）

local Constants = require("scripts/app/constants")

local AiSquadPolicy = {}

local TARGET_BY_REP = {
    { minRep = 900, size = 27 },
    { minRep = 800, size = 25 },
    { minRep = 700, size = 23 },
    { minRep = 620, size = 22 },
    { minRep = 0,   size = 21 },
}

local REP_MIN_OVR_BY_REP = {
    { minRep = 900, ovr = 74 },
    { minRep = 800, ovr = 70 },
    { minRep = 700, ovr = 66 },
    { minRep = 620, ovr = 62 },
    { minRep = 0,   ovr = 56 },
}

local FINANCIAL_FLOOR_BY_REP = {
    { minRep = 900, factor = 0.85 },
    { minRep = 800, factor = 0.75 },
    { minRep = 700, factor = 0.65 },
    { minRep = 0,   factor = 0.50 },
}

local function tierLookup(tiers, rep, field, default)
    rep = rep or 600
    for _, tier in ipairs(tiers) do
        if rep >= tier.minRep then
            return tier[field]
        end
    end
    return default
end

--- 一线队目标人数（按声望）
function AiSquadPolicy.getTargetSquadSize(team)
    if not team then return Constants.AI_FIRST_TEAM_MIN or 20 end
    return tierLookup(TARGET_BY_REP, team.reputation or 600, "size", 21)
end

--- 引援质量底线：mode = "upgrade" | "fill" | "emergency"
function AiSquadPolicy.getRepMinOvr(team, mode)
    local base = tierLookup(REP_MIN_OVR_BY_REP, team and team.reputation or 600, "ovr", 56)
    mode = mode or "upgrade"
    if mode == "upgrade" then
        return base
    elseif mode == "fill" then
        return base - 4
    elseif mode == "emergency" then
        return base - 8
    end
    return base
end

--- 工资预算底盘系数（按声望）
function AiSquadPolicy.getFinancialFloorFactor(team)
    return tierLookup(FINANCIAL_FLOOR_BY_REP, team and team.reputation or 600, "factor", 0.50)
end

--- 初始化/补全球队财务底盘字段
function AiSquadPolicy.ensureFinancialBaseline(team)
    if not team then return end
    local wb = team.wageBudget or team._baseWageBudget or 200000
    if not team._baseWageBudget or team._baseWageBudget <= 0 then
        team._baseWageBudget = wb
    end
    if not team._financialScale or team._financialScale <= 0 then
        team._financialScale = math.sqrt(wb / 2000000)
    end
end

function AiSquadPolicy.countPositionGroups(gameState, team)
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

--- GK<2 / DEF<4 / MID<4 / FWD<2
function AiSquadPolicy.hasPositionShortage(gameState, team)
    local posCount = AiSquadPolicy.countPositionGroups(gameState, team)
    return posCount.GK < 2 or posCount.DEF < 4 or posCount.MID < 4 or posCount.FWD < 2
end

return AiSquadPolicy
