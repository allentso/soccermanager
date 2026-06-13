-- data/team_rivalries.lua
-- 经典死敌关系（jsonTeamId 对），开档时写入 gameState._teamRelations

local TeamRivalries = {}

TeamRivalries.RIVALRY_VALUE = -80  -- ≤ -50 视为敌对（TransferManager._isRivalry）

-- 五大联赛经典德比 / 死敌（与 assets/Data/fm2024_*.json 中 team.id 一致）
-- 第三列为说明（仅文档/审阅，不参与逻辑）
TeamRivalries.PAIRS = {
    -- 英超
    { "manchester-city", "manchester-united", "曼彻斯特德比" },
    { "manchester-united", "liverpool", "西北德比" },
    { "liverpool", "everton", "默西塞德德比" },
    { "arsenal", "tottenham-hotspur", "北伦敦德比" },
    { "chelsea", "tottenham-hotspur", "伦敦德比" },
    { "west-ham-united", "tottenham-hotspur", "伦敦德比" },
    -- 西甲
    { "real-madrid-club-de-futbol", "futbol-club-barcelona", "国家德比" },
    { "real-madrid-club-de-futbol", "club-atletico-de-madrid", "马德里德比" },
    { "futbol-club-barcelona", "real-club-deportivo-espanyol-de-barcelona", "加泰德比" },
    { "sevilla-fc", "real-betis-balompie", "塞维利亚德比" },
    -- 意甲
    { "fc-internazionale-milano", "a-c-milan", "米兰德比" },
    { "a-c-milan", "juventus-fc", "意大利国家德比" },
    { "a-s-roma", "ss-lazio", "罗马德比" },
    { "juventus-fc", "torino-fc", "都灵德比" },
    -- 德甲
    { "fc-bayern-munchen", "borussia-dortmund", "德国国家德比" },
    { "borussia-dortmund", "borussia-monchengladbach", "莱茵德比" },
    -- 法甲
    { "paris-saint-germain-fc", "olympique-de-marseille", "法国国家德比" },
    { "olympique-lyonnais", "olympique-de-marseille", "里昂-马赛" },
}

local function countRelations(relations)
    if not relations then return 0 end
    local n = 0
    for _ in pairs(relations) do n = n + 1 end
    return n
end

--- 审阅用：返回所有死敌对及说明
function TeamRivalries.getPairCatalog()
    local out = {}
    for _, pair in ipairs(TeamRivalries.PAIRS) do
        table.insert(out, {
            jsonTeamIdA = pair[1],
            jsonTeamIdB = pair[2],
            label = pair[3] or "",
        })
    end
    return out
end

--- 批量写入死敌关系
---@param gameState table
---@return number pairsWritten
function TeamRivalries.initialize(gameState)
    local TransferManager = require("scripts/systems/transfer_manager")
    local jsonToGame = {}
    for _, team in pairs(gameState.teams or {}) do
        if team.jsonTeamId then
            jsonToGame[team.jsonTeamId] = team.id
        end
    end

    local written = 0
    for _, pair in ipairs(TeamRivalries.PAIRS) do
        local id1 = jsonToGame[pair[1]]
        local id2 = jsonToGame[pair[2]]
        if id1 and id2 then
            TransferManager.setTeamRelation(gameState, id1, id2, TeamRivalries.RIVALRY_VALUE)
            written = written + 1
        end
    end
    return written
end

--- 仅在关系表为空时初始化（新档 / 旧存档迁移）
---@param gameState table
---@return number pairsWritten
function TeamRivalries.initializeIfNeeded(gameState)
    if countRelations(gameState._teamRelations) > 0 then
        return countRelations(gameState._teamRelations)
    end
    return TeamRivalries.initialize(gameState)
end

return TeamRivalries
