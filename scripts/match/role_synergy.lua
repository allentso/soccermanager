-- match/role_synergy.lua
-- 角色协同系统：当特定角色组合出现在阵容中时，产生战术组合效应
-- v2: 使用 constants.lua 中的实际角色 key

local Constants = require("scripts/app/constants")
local FormationShape = require("scripts/match/formation_shape")

local RoleSynergy = {}

-- 同侧判定：基于位置 key 的字母前缀 R/L
-- 中路位置（无前缀或非 R/L 开头）与任何侧都兼容
local function isSameSide(posA, posB)
    local sideA = posA:sub(1, 1)
    local sideB = posB:sub(1, 1)
    -- 只有 R/L 开头的位置才有侧性
    if sideA ~= "R" and sideA ~= "L" then return true end
    if sideB ~= "R" and sideB ~= "L" then return true end
    return sideA == sideB
end

-- roleA/roleB 可以是 string 或 string[]
local function matchesRole(actualRole, expected)
    if type(expected) == "string" then
        return actualRole == expected
    end
    if type(expected) == "table" then
        for _, r in ipairs(expected) do
            if actualRole == r then return true end
        end
    end
    return false
end

-- posX 可以是 string 或 string[]
local function matchesPos(actualPos, expected)
    if type(expected) == "string" then
        return actualPos == expected
    end
    if type(expected) == "table" then
        for _, p in ipairs(expected) do
            if actualPos == p then return true end
        end
    end
    return false
end

-- 协同规则表
-- side: "same" = 必须同侧, "any" = 不限
local ROLE_SYNERGIES = {
    -- === 边路联动 ===
    -- 内切边锋 + 进攻翼卫 = 同侧拉开空间
    {
        posA = { "RW", "LW" }, roleA = "inverted",
        posB = { "RB", "LB" }, roleB = "wingBack",
        side = "same",
        bonus = { attack = 0.05, possession = 0.02 },
        tag = "内切+套边联动",
    },
    -- 贴边边锋 + 防守边后卫 = 边路纵深平衡
    {
        posA = { "RW", "LW" }, roleA = "touchline",
        posB = { "RB", "LB" }, roleB = "defensive",
        side = "same",
        bonus = { attack = 0.02, defense = 0.02 },
        tag = "边路纵深分工",
    },
    -- 贴边边锋/宽幅中场 + 支点前锋 = 传中找人战术
    {
        posA = { "RW", "LW", "RM", "LM" }, roleA = { "touchline", "winger", "wide" },
        posB = { "ST", "CF" }, roleB = "targetMan",
        side = "any",
        bonus = { attack = 0.04, aerial = 0.05 },
        tag = "边路传中战术",
    },

    -- === 中前场配合 ===
    -- 支点前锋 + 影子前锋 = 纵深呼应
    {
        posA = { "ST", "CF" }, roleA = "targetMan",
        posB = { "CAM" }, roleB = "shadow",
        side = "any",
        bonus = { attack = 0.05, shotQuality = 0.06 },
        tag = "支点+影锋呼应",
    },
    -- 伪九号 + 前插中场 = 空间互换
    {
        posA = { "ST" }, roleA = "falseNine",
        posB = { "CM" }, roleB = "advanced",
        side = "any",
        bonus = { possession = 0.04, attack = 0.03 },
        tag = "伪九拉扯空间",
    },
    -- 古典前腰 + 禁区猎手 = 最后一传→终结
    {
        posA = { "CAM" }, roleA = "playmaker",
        posB = { "ST", "CF" }, roleB = "poacher",
        side = "any",
        bonus = { shotQuality = 0.06, attack = 0.02 },
        tag = "组织+终结搭配",
    },

    -- === 后场出球 ===
    -- 出球中卫 + 组织型后腰 = 后场出球体系
    {
        posA = { "CB" }, roleA = "ballPlaying",
        posB = { "CDM" }, roleB = "deepLying",
        side = "any",
        bonus = { possession = 0.04, tempo = 0.02 },
        tag = "后场出球体系",
    },

    -- === 冗余/冲突惩罚 ===
    -- 双扫荡后腰 = 过于保守
    {
        posA = { "CDM" }, roleA = "anchor",
        posB = { "CDM" }, roleB = "anchor",
        side = "any",
        bonus = { defense = 0.03, attack = -0.04, tempo = -0.03 },
        tag = "双守型后腰",
    },
}

-- 维度列表（包含非标准维度 shotQuality, aerial 等）
local ALL_DIMS = { "attack", "defense", "possession", "press", "counter", "tempo", "shotQuality", "aerial" }

--- 评估整支球队的角色协同加成
---@param players table[] 首发球员列表
---@param slots string[] 各槽位的位置 key（GK, CB, RW...）
---@param slotRoles table<integer, string> 各槽位的角色 key
---@param startingXI table<integer, string> playerId 列表（用于建立 playerId→slotIdx 映射）
---@return table mods 各维度的乘性修正（如 { attack = 1.07, defense = 0.99 }）
---@return string[] tags 触发的协同标签列表
function RoleSynergy.evaluate(players, slots, slotRoles, startingXI)
    local mods = {}
    for _, dim in ipairs(ALL_DIMS) do
        mods[dim] = 1.0
    end
    local tags = {}

    -- 建立 playerId → slotIdx
    local playerSlotIndex = {}
    if startingXI then
        for i, pid in ipairs(startingXI) do
            playerSlotIndex[pid] = i
        end
    else
        for i, player in ipairs(players) do
            playerSlotIndex[player.id] = i
        end
    end

    -- 构建参与者列表: { slotIdx, pos, roleKey }
    local participants = {}
    for _, player in ipairs(players) do
        local slotIdx = playerSlotIndex[player.id]
        if slotIdx and slots[slotIdx] then
            local pos = slots[slotIdx]
            local roleKey = (slotRoles and slotRoles[slotIdx]) or "default"
            table.insert(participants, { slotIdx = slotIdx, pos = pos, roleKey = roleKey, player = player })
        end
    end

    -- 遍历协同规则
    for _, rule in ipairs(ROLE_SYNERGIES) do
        local triggered = false

        for i = 1, #participants do
            if triggered then break end
            local pA = participants[i]
            if matchesPos(pA.pos, rule.posA) and matchesRole(pA.roleKey, rule.roleA) then
                for j = 1, #participants do
                    if i ~= j then
                        local pB = participants[j]
                        if matchesPos(pB.pos, rule.posB) and matchesRole(pB.roleKey, rule.roleB) then
                            -- 侧面判定
                            local sideOK = true
                            if rule.side == "same" then
                                sideOK = isSameSide(pA.pos, pB.pos)
                            end
                            if sideOK then
                                -- 应用加成
                                for dim, bonus in pairs(rule.bonus) do
                                    mods[dim] = (mods[dim] or 1.0) + bonus
                                end
                                table.insert(tags, rule.tag)
                                triggered = true
                                break
                            end
                        end
                    end
                end
            end
        end

        -- 双向检测：如果 A-B 没匹配，尝试 B-A（交换 posA/roleA 与 posB/roleB）
        -- 仅对非对称规则需要（posA≠posB 或 roleA≠roleB）
        if not triggered then
            for i = 1, #participants do
                if triggered then break end
                local pA = participants[i]
                if matchesPos(pA.pos, rule.posB) and matchesRole(pA.roleKey, rule.roleB) then
                    for j = 1, #participants do
                        if i ~= j then
                            local pB = participants[j]
                            if matchesPos(pB.pos, rule.posA) and matchesRole(pB.roleKey, rule.roleA) then
                                local sideOK = true
                                if rule.side == "same" then
                                    sideOK = isSameSide(pA.pos, pB.pos)
                                end
                                if sideOK then
                                    for dim, bonus in pairs(rule.bonus) do
                                        mods[dim] = (mods[dim] or 1.0) + bonus
                                    end
                                    table.insert(tags, rule.tag)
                                    triggered = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return mods, tags
end

return RoleSynergy
