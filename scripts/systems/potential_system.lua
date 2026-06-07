-- systems/potential_system.lua
-- 潜力抽象值系统（类似 FM 星级）
--
-- 设计思路:
--   1. 原始 potential (37-98) 转换为 PA Rating (1.0 - 10.0, 步进0.5)
--   2. 每局游戏开始时, 根据 PA Rating 生成"局内实际潜力"(actualPotential)
--   3. 高评级 → 高中心值 + 低波动 (确定性强)
--      低评级 → 低中心值 + 高波动 (不确定性大, 可能超预期也可能令人失望)
--   4. UI 显示 PA Rating (半星), 实际数值对球探能力有关联

local PotentialSystem = {}

------------------------------------------------------
-- PA Rating 等级表
-- 每个等级定义:
--   rating: 抽象评级 (1.0 - 10.0)
--   centerMin/centerMax: 该等级实际潜力的中心区间
--   variance: 最大上下波动 (高斯分布 1σ 约束内)
------------------------------------------------------

PotentialSystem.RATING_TABLE = {
    -- rating, centerMin, centerMax, variance(±), 描述
    { rating = 10.0, centerMin = 96, centerMax = 99, variance = 1,  desc = "传奇巨星" },
    { rating = 9.5,  centerMin = 93, centerMax = 97, variance = 2,  desc = "绝对巨星" },
    { rating = 9.0,  centerMin = 90, centerMax = 94, variance = 2,  desc = "世界顶级" },
    { rating = 8.5,  centerMin = 87, centerMax = 91, variance = 3,  desc = "世界级" },
    { rating = 8.0,  centerMin = 83, centerMax = 88, variance = 3,  desc = "顶级球员" },
    { rating = 7.5,  centerMin = 79, centerMax = 84, variance = 4,  desc = "一线球员" },
    { rating = 7.0,  centerMin = 75, centerMax = 80, variance = 4,  desc = "优秀球员" },
    { rating = 6.5,  centerMin = 72, centerMax = 77, variance = 5,  desc = "可靠球员" },
    { rating = 6.0,  centerMin = 68, centerMax = 74, variance = 5,  desc = "中上球员" },
    { rating = 5.5,  centerMin = 65, centerMax = 71, variance = 5,  desc = "中游球员" },
    { rating = 5.0,  centerMin = 62, centerMax = 68, variance = 6,  desc = "联赛中游" },
    { rating = 4.5,  centerMin = 58, centerMax = 65, variance = 6,  desc = "联赛替补" },
    { rating = 4.0,  centerMin = 55, centerMax = 62, variance = 6,  desc = "轮换球员" },
    { rating = 3.5,  centerMin = 52, centerMax = 58, variance = 7,  desc = "板凳末端" },
    { rating = 3.0,  centerMin = 48, centerMax = 55, variance = 7,  desc = "低级联赛" },
    { rating = 2.5,  centerMin = 44, centerMax = 52, variance = 7,  desc = "业余水平" },
    { rating = 2.0,  centerMin = 40, centerMax = 48, variance = 7,  desc = "业余球员" },
    { rating = 1.5,  centerMin = 36, centerMax = 44, variance = 7,  desc = "初学者" },
    { rating = 1.0,  centerMin = 30, centerMax = 40, variance = 8,  desc = "无潜力" },
}

------------------------------------------------------
-- 原始潜力 → PA Rating 映射
------------------------------------------------------

--- 将原始潜力值(0-100)映射为PA Rating(1.0-10.0, 步进0.5)
--- 使用分段线性映射，确保分布合理
--- @param rawPotential number 原始潜力值(37-98)
--- @return number paRating PA评级(1.0-10.0)
function PotentialSystem.rawToRating(rawPotential)
    local p = rawPotential or 60

    -- 分段映射表: {原始值下限, 原始值上限, 评级下限, 评级上限}
    -- 高端区间更窄（更难获得高评级），低端区间更宽
    local segments = {
        { 96, 99, 10.0, 10.0 },  -- 96-99 → 10.0 (传奇)
        { 93, 95,  9.5,  9.5 },  -- 93-95 → 9.5
        { 90, 92,  9.0,  9.0 },  -- 90-92 → 9.0
        { 87, 89,  8.5,  8.5 },  -- 87-89 → 8.5
        { 84, 86,  8.0,  8.0 },  -- 84-86 → 8.0
        { 81, 83,  7.5,  7.5 },  -- 81-83 → 7.5
        { 78, 80,  7.0,  7.0 },  -- 78-80 → 7.0
        { 75, 77,  6.5,  6.5 },  -- 75-77 → 6.5
        { 72, 74,  6.0,  6.0 },  -- 72-74 → 6.0
        { 69, 71,  5.5,  5.5 },  -- 69-71 → 5.5
        { 66, 68,  5.0,  5.0 },  -- 66-68 → 5.0
        { 63, 65,  4.5,  4.5 },  -- 63-65 → 4.5
        { 60, 62,  4.0,  4.0 },  -- 60-62 → 4.0
        { 56, 59,  3.5,  3.5 },  -- 56-59 → 3.5
        { 52, 55,  3.0,  3.0 },  -- 52-55 → 3.0
        { 47, 51,  2.5,  2.5 },  -- 47-51 → 2.5
        { 42, 46,  2.0,  2.0 },  -- 42-46 → 2.0
        { 37, 41,  1.5,  1.5 },  -- 37-41 → 1.5
    }

    for _, seg in ipairs(segments) do
        if p >= seg[1] and p <= seg[2] then
            return seg[3]
        end
    end

    -- 超出范围
    if p >= 96 then return 10.0 end
    return 1.0
end

------------------------------------------------------
-- 生成局内实际潜力
------------------------------------------------------

--- 简单的确定性伪随机生成器 (xorshift32)
--- 避免污染全局 math.random 状态
--- @param state number[] 单元素数组, state[1] 为当前状态
--- @return number 0~1 之间的浮点数
local function seededRandom(state)
    local s = state[1]
    s = s ~ (s << 13)
    s = s & 0xFFFFFFFF
    s = s ~ (s >> 17)
    s = s & 0xFFFFFFFF
    s = s ~ (s << 5)
    s = s & 0xFFFFFFFF
    state[1] = s
    return (s % 1000000) / 1000000.0
end

--- 简单的 Box-Muller 近似高斯随机
--- @param state number[]|nil 如提供则用确定性 PRNG, 否则用引擎 Random()
--- @return number 标准正态分布随机值（约-3到+3）
local function gaussianRandom(state)
    local u1, u2
    if state then
        u1 = seededRandom(state)
        u2 = seededRandom(state)
    else
        u1 = Random()
        u2 = Random()
    end
    -- 避免 log(0)
    if u1 < 0.0001 then u1 = 0.0001 end
    local z = math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)
    -- 限制在 [-2.5, 2.5] 防止极端值
    return math.max(-2.5, math.min(2.5, z))
end

--- 根据 PA Rating 获取该等级的参数
--- @param paRating number
--- @return table|nil 等级参数 {rating, centerMin, centerMax, variance, desc}
function PotentialSystem.getRatingParams(paRating)
    for _, entry in ipairs(PotentialSystem.RATING_TABLE) do
        if math.abs(entry.rating - paRating) < 0.01 then
            return entry
        end
    end
    -- 未找到精确匹配，找最近的
    local best = PotentialSystem.RATING_TABLE[#PotentialSystem.RATING_TABLE]
    local bestDiff = math.abs(best.rating - paRating)
    for _, entry in ipairs(PotentialSystem.RATING_TABLE) do
        local diff = math.abs(entry.rating - paRating)
        if diff < bestDiff then
            best = entry
            bestDiff = diff
        end
    end
    return best
end

--- 生成一个球员的局内实际潜力值
--- @param paRating number PA评级 (1.0-10.0)
--- @param seed number|nil 可选随机种子(用于存档一致性, 使用独立 PRNG 不污染全局状态)
--- @return number actualPotential 局内实际潜力 (整数)
function PotentialSystem.generateActualPotential(paRating, seed)
    local params = PotentialSystem.getRatingParams(paRating)
    if not params then
        return 60  -- fallback
    end

    -- 使用独立的 xorshift PRNG, 不污染全局 math.random 状态
    ---@type number[]|nil
    local state = nil
    if seed then
        state = { math.max(1, seed) }  -- xorshift 状态不能为 0
    end

    -- 1. 在中心区间内均匀选一个基准点
    local centerRange = params.centerMax - params.centerMin
    local rVal = state and seededRandom(state) or Random()
    local baseValue = params.centerMin + rVal * centerRange

    -- 2. 施加高斯波动
    local noise = gaussianRandom(state) * (params.variance * 0.6)
    -- variance 是最大幅度, 乘以0.6使1σ约为variance的60%，2σ才接近满幅
    -- 这样大部分值落在 ±variance*0.6 内，偶尔有 ±variance*1.2 的极端值

    local actualPotential = math.floor(baseValue + noise + 0.5)

    -- 3. 硬限制: 不超出合理范围
    local hardMin = params.centerMin - params.variance
    local hardMax = params.centerMax + params.variance
    actualPotential = math.max(hardMin, math.min(hardMax, actualPotential))

    -- 全局限制
    actualPotential = math.max(30, math.min(99, actualPotential))

    return actualPotential
end

------------------------------------------------------
-- 批量处理接口
------------------------------------------------------

--- 为所有球员生成 PA Rating 和局内实际潜力
--- 应在每局游戏开始/加载数据后调用一次
--- @param gameState table GameState实例
function PotentialSystem.initializeAllPlayers(gameState)
    if not gameState or not gameState.players then return end

    -- 使用游戏种子（若有）确保同一存档结果一致
    local baseSeed = gameState.potentialSeed or Time:GetSystemTime()
    gameState.potentialSeed = baseSeed

    local count = 0
    for id, player in pairs(gameState.players) do
        -- 1. 计算 PA Rating（基于原始 potential）
        local paRating = PotentialSystem.rawToRating(player.potential)
        player.paRating = paRating

        -- 2. 生成局内实际潜力（使用球员id作为种子偏移，确保每人不同但可复现）
        local playerSeed = baseSeed + id * 7919  -- 用质数偏移避免模式
        local actualPotential = PotentialSystem.generateActualPotential(paRating, playerSeed)
        player.actualPotential = actualPotential

        count = count + 1
    end

    log:Write(LOG_INFO, string.format(
        "PotentialSystem: 已为 %d 名球员初始化潜力系统 (seed=%d)", count, baseSeed))
end

--- 获取PA Rating的显示文本（半星格式）
--- @param paRating number
--- @return string 如 "9.5" 或 "8.0"
function PotentialSystem.getRatingDisplay(paRating)
    if not paRating then return "-" end
    if paRating == math.floor(paRating) then
        return string.format("%.1f", paRating)
    end
    return string.format("%.1f", paRating)
end

--- 获取PA Rating对应的描述文本
--- @param paRating number
--- @return string 如 "世界级" "顶级球员"
function PotentialSystem.getRatingDesc(paRating)
    local params = PotentialSystem.getRatingParams(paRating)
    return params and params.desc or "未知"
end

--- 获取PA Rating对应的颜色等级（用于UI显示）
--- @param paRating number
--- @return string 颜色标识 "legendary"|"elite"|"good"|"average"|"poor"
function PotentialSystem.getRatingTier(paRating)
    if not paRating then return "average" end
    if paRating >= 9.5 then return "legendary"
    elseif paRating >= 8.0 then return "elite"
    elseif paRating >= 6.5 then return "good"
    elseif paRating >= 4.5 then return "average"
    else return "poor"
    end
end

--- 获取球员潜力的可见范围（模拟球探不确定性）
--- 球探看到的是一个范围，而不是精确值
--- @param player table 球员对象
--- @param scoutAccuracy number 球探准确度 0.0-1.0 (1.0=完美)
--- @return number low 最低可能值
--- @return number high 最高可能值
function PotentialSystem.getScoutedRange(player, scoutAccuracy)
    local actual = player.actualPotential or player.potential or 60
    local accuracy = scoutAccuracy or 0.7

    -- 准确度越高，范围越窄
    local spread = math.floor((1.0 - accuracy) * 15)  -- 0.7准确度 → ±4.5
    spread = math.max(1, spread)

    local low = math.max(30, actual - spread)
    local high = math.min(99, actual + spread)

    return low, high
end

------------------------------------------------------
-- 重新掷骰（用于新赛季/特殊事件）
------------------------------------------------------

--- 为单个球员重新生成实际潜力（保持PA Rating不变）
--- 用于新赛季开始或特殊剧情事件
--- @param player table 球员对象
--- @param newSeed number|nil 新种子
--- @return number 新的实际潜力
function PotentialSystem.rerollActualPotential(player, newSeed)
    local paRating = player.paRating
    if not paRating then
        paRating = PotentialSystem.rawToRating(player.potential)
        player.paRating = paRating
    end

    local seed = newSeed or (Time:GetSystemTime() + (player.id or 0) * 13)
    local newActual = PotentialSystem.generateActualPotential(paRating, seed)
    player.actualPotential = newActual
    return newActual
end

return PotentialSystem
