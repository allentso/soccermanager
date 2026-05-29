-- systems/team_talk_manager.lua
-- Team Talk 系统：6 种语气 × 3 种上下文，带性格加权和递减回报

local Constants = require("scripts/app/constants")

local TeamTalkManager = {}

------------------------------------------------------
-- 常量定义
------------------------------------------------------

-- 6 种训话语气
TeamTalkManager.TONES = {
    "calm",          -- 冷静
    "motivational",  -- 激励
    "assertive",     -- 强势
    "aggressive",    -- 激进
    "praise",        -- 表扬
    "disappointed",  -- 失望
}

-- 4 种上下文
TeamTalkManager.CONTEXTS = {
    "pre_match", -- 赛前
    "winning",   -- 领先
    "drawing",   -- 平局
    "losing",    -- 落后
}

-- 语气对应的基础 delta（5 档：strong_pos / mild_pos / neutral / mild_neg / strong_neg）
local TONE_DELTAS = {
    calm         = { 5,  3,  1, -1, -3 },
    motivational = { 9,  5,  1, -2, -5 },
    assertive    = { 6,  3,  0, -3, -6 },
    aggressive   = { 7,  2, -1, -5, -9 },
    praise       = { 8,  5,  1, -2, -4 },
    disappointed = { 3,  1, -2, -5, -8 },
}

-- 上下文 × 语气 权重矩阵（决定反应档位的概率分布）
-- 每行 = 5 个权重对应 5 个 band: [strong_pos, mild_pos, neutral, mild_neg, strong_neg]
-- 值越高 = 该 band 越可能触发
local CONTEXT_WEIGHTS = {
    pre_match = {
        calm         = { 25, 35, 25, 10,  5 },  -- 赛前+冷静 → 适度正面
        motivational = { 35, 35, 20,  8,  2 },  -- 赛前+激励 → 非常正面
        assertive    = { 20, 30, 25, 18,  7 },  -- 赛前+强势 → 适中
        aggressive   = { 15, 20, 25, 25, 15 },  -- 赛前+激进 → 部分球员反感
        praise       = { 30, 35, 20, 10,  5 },  -- 赛前+表扬 → 正面
        disappointed = {  8, 15, 25, 30, 22 },  -- 赛前+失望 → 负面"还没打呢"
    },
    winning = {
        calm         = { 30, 40, 20,  8,  2 },  -- 领先+冷静 → 大概率正面
        motivational = { 25, 35, 20, 15,  5 },  -- 领先+激励 → 适度，偶尔觉得没必要
        assertive    = { 15, 25, 25, 25, 10 },  -- 领先+强势 → 球员可能不爽"何必这样"
        aggressive   = { 10, 15, 20, 30, 25 },  -- 领先+激进 → 大概率负面"又不是输了"
        praise       = { 40, 35, 15,  8,  2 },  -- 领先+表扬 → 非常正面
        disappointed = {  5, 10, 20, 35, 30 },  -- 领先+失望 → 强烈负面"明明赢着"
    },
    drawing = {
        calm         = { 20, 35, 30, 10,  5 },
        motivational = { 35, 30, 20, 10,  5 },  -- 平局+激励 → 最均衡正面
        assertive    = { 25, 30, 25, 15,  5 },
        aggressive   = { 15, 20, 25, 25, 15 },
        praise       = { 15, 30, 30, 20,  5 },  -- 平局+表扬 → 中性偏正
        disappointed = { 10, 20, 25, 30, 15 },
    },
    losing = {
        calm         = { 10, 20, 30, 25, 15 },  -- 落后+冷静 → 可能嫌不够紧张
        motivational = { 30, 30, 20, 15,  5 },  -- 落后+激励 → 正面（需要鼓舞）
        assertive    = { 25, 30, 25, 15,  5 },  -- 落后+强势 → 适合战术型球员
        aggressive   = { 30, 25, 20, 15, 10 },  -- 落后+激进 → 可能激发斗志
        praise       = {  5, 15, 25, 35, 20 },  -- 落后+表扬 → "凭什么夸"
        disappointed = { 20, 25, 25, 20, 10 },  -- 落后+失望 → 部分球员被激将
    },
}

------------------------------------------------------
-- 核心接口
------------------------------------------------------

--- 计算一次训话对单个球员的士气影响
---@param player table Player 对象
---@param tone string 语气（6 选 1）
---@param context string 上下文（winning/drawing/losing）
---@param gameDay number 当前游戏天数（用于递减回报）
---@return number delta 士气变化（已 clamp）
---@return string band 命中的反应档位描述
function TeamTalkManager.calculateEffect(player, tone, context, gameDay)
    -- 1. 获取权重分布
    local weights = CONTEXT_WEIGHTS[context] and CONTEXT_WEIGHTS[context][tone]
    if not weights then return 0, "neutral" end

    -- 2. 性格修正：(composure + leadership - aggression) / 6, clamp [-20, 20]
    local a = player.attributes or {}
    local personalityShift = math.floor(
        ((a.composure or 10) + (a.leadership or 10) - (a.aggression or 10)) / 6
    )
    personalityShift = math.max(-20, math.min(20, personalityShift))

    -- 性格正值 → 更容易正面反应（增加 strong_pos/mild_pos 权重）
    -- 性格负值 → 更容易负面反应（增加 mild_neg/strong_neg 权重）
    local adjustedWeights = {}
    for i = 1, 5 do
        adjustedWeights[i] = weights[i]
    end
    if personalityShift > 0 then
        adjustedWeights[1] = adjustedWeights[1] + personalityShift
        adjustedWeights[2] = adjustedWeights[2] + math.floor(personalityShift * 0.5)
    else
        adjustedWeights[4] = adjustedWeights[4] - personalityShift
        adjustedWeights[5] = adjustedWeights[5] - math.floor(personalityShift * 0.5)
    end

    -- 3. 信任度修正：高信任 → 正面反应概率增加
    local trust = player.morale_core and player.morale_core.manager_trust or 50
    local trustBonus = math.floor((trust - 50) / 10)  -- -5 to +5
    adjustedWeights[1] = adjustedWeights[1] + trustBonus
    adjustedWeights[5] = adjustedWeights[5] - trustBonus

    -- 4. 确保权重非负
    for i = 1, 5 do
        adjustedWeights[i] = math.max(1, adjustedWeights[i])
    end

    -- 5. 加权随机选择 band
    local totalWeight = 0
    for i = 1, 5 do totalWeight = totalWeight + adjustedWeights[i] end
    local roll = math.random(1, totalWeight)
    local bandIndex = 1
    local cumulative = 0
    for i = 1, 5 do
        cumulative = cumulative + adjustedWeights[i]
        if roll <= cumulative then
            bandIndex = i
            break
        end
    end

    -- 6. 获取基础 delta
    local deltas = TONE_DELTAS[tone]
    local baseDelta = deltas[bandIndex]

    -- 7. 递减回报：talk_fatigue 每点减少 20% 效果
    local fatigue = player.morale_core and player.morale_core.talk_fatigue or 0
    local fatigueMultiplier = math.max(0.2, 1.0 - fatigue * 0.2)
    local finalDelta = math.floor(baseDelta * fatigueMultiplier + 0.5)

    -- 8. Clamp 到 [-12, 12]
    finalDelta = math.max(-12, math.min(12, finalDelta))

    -- Band 描述
    local bandNames = { "strong_pos", "mild_pos", "neutral", "mild_neg", "strong_neg" }

    return finalDelta, bandNames[bandIndex]
end

--- 对整队执行训话
---@param gameState table
---@param tone string
---@param context string
---@return table[] results { playerId, name, delta, band }
function TeamTalkManager.deliverTeamTalk(gameState, tone, context)
    local team = gameState:getPlayerTeam()
    if not team then return {} end

    local gameDay = TeamTalkManager._getGameDay(gameState)
    local results = {}

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and not player.retired then
            -- 检查冷却（同一天不重复）
            local mc = player.morale_core
            if not mc then
                player.morale_core = {
                    manager_trust = 50, unresolved_issue = nil,
                    recent_treatment = nil, last_talk_day = 0, talk_fatigue = 0,
                }
                mc = player.morale_core
            end

            local delta, band = TeamTalkManager.calculateEffect(player, tone, context, gameDay)

            -- 应用士气变化
            player.morale = math.max(0, math.min(100, (player.morale or 50) + delta))

            -- 更新信任度（正面反应 +1 信任，负面 -1）
            if band == "strong_pos" or band == "mild_pos" then
                mc.manager_trust = math.min(100, mc.manager_trust + 1)
            elseif band == "mild_neg" or band == "strong_neg" then
                mc.manager_trust = math.max(0, mc.manager_trust - 1)
            end

            -- 更新递减回报
            mc.talk_fatigue = math.min(5, mc.talk_fatigue + 1)
            mc.last_talk_day = gameDay

            table.insert(results, {
                playerId = pid,
                name = player.displayName,
                position = player.position,
                delta = delta,
                band = band,
                newMorale = player.morale,
            })
        end
    end

    return results
end

--- 每日衰减 talk_fatigue（每天 -0.5，最低 0）
function TeamTalkManager.dailyDecay(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    for _, pid in ipairs(team.playerIds) do
        local player = gameState.players[pid]
        if player and player.morale_core then
            local mc = player.morale_core
            if mc.talk_fatigue > 0 then
                -- 每两天衰减 1 点
                mc.talk_fatigue = math.max(0, mc.talk_fatigue - 0.5)
            end
        end
    end
end

------------------------------------------------------
-- UI 辅助
------------------------------------------------------

--- 获取语气的中文名称
function TeamTalkManager.getToneName(tone)
    local names = {
        calm = "冷静",
        motivational = "激励",
        assertive = "强势",
        aggressive = "激进",
        praise = "表扬",
        disappointed = "失望",
    }
    return names[tone] or tone
end

--- 获取上下文的中文名称
function TeamTalkManager.getContextName(context)
    local names = {
        pre_match = "赛前",
        winning = "领先",
        drawing = "平局",
        losing = "落后",
    }
    return names[context] or context
end

--- 获取反应 band 的中文描述和颜色
function TeamTalkManager.getBandDisplay(band)
    local displays = {
        strong_pos = { text = "非常积极", color = {80, 200, 80, 255} },
        mild_pos   = { text = "积极", color = {120, 200, 120, 255} },
        neutral    = { text = "无反应", color = {180, 180, 180, 255} },
        mild_neg   = { text = "消极", color = {200, 150, 80, 255} },
        strong_neg = { text = "非常消极", color = {200, 80, 80, 255} },
    }
    return displays[band] or { text = "未知", color = {128, 128, 128, 255} }
end

------------------------------------------------------
-- 内部工具
------------------------------------------------------

function TeamTalkManager._getGameDay(gameState)
    -- 简单计算：year*365 + month*30 + day
    local d = gameState.date or {}
    return (d.year or 0) * 365 + (d.month or 0) * 30 + (d.day or 0)
end

return TeamTalkManager
