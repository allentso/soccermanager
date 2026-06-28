-- match/formation_shape.lua
-- 球场九区划分、结构自动归类、阵容形态效果（区域密度 + 槽位特征 + 自定义偏移）

local Constants = require("scripts/app/constants")

local FormationShape = {}

FormationShape.FORMATION_POSITIONS = {
    ["4-4-2:flat"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {38, 55}, {62, 55}, {85, 52},
        {35, 80}, {65, 80},
    },
    ["4-4-2:diamond"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {50, 45}, {50, 65}, {85, 52},
        {35, 80}, {65, 80},
    },
    ["4-3-3:hold"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {50, 42}, {65, 50},
        {20, 80}, {50, 82}, {80, 80},
    },
    ["4-3-3:attack"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {65, 50}, {50, 62},
        {20, 80}, {50, 82}, {80, 80},
    },
    ["3-5-2:default"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 48}, {67, 55}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["3-5-2:attack"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {38, 52}, {62, 52}, {50, 64}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["3-4-3:flat"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {38, 52}, {62, 52}, {90, 50},
        {20, 80}, {50, 84}, {80, 80},
    },
    ["3-4-3:stagger"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 52}, {45, 46}, {55, 62}, {90, 52},
        {20, 80}, {50, 84}, {80, 80},
    },
    ["4-2-3-1:wide"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {20, 68}, {80, 68},
        {50, 85},
    },
    ["4-2-3-1:narrow"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {68, 63}, {32, 63},
        {50, 85},
    },
    ["5-3-2:flat"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {50, 55}, {70, 52},
        {35, 80}, {65, 80},
    },
    ["5-3-2:hold"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {35, 52}, {50, 45}, {65, 52},
        {35, 80}, {65, 80},
    },
    ["4-2-4:flat"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {38, 52}, {62, 52},
        {18, 78}, {40, 84}, {60, 84}, {82, 78},
    },
    ["4-5-1:default"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 55}, {50, 48}, {67, 55}, {85, 50},
        {50, 82},
    },
    ["4-5-1:diamond"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {50, 42}, {50, 62}, {67, 55}, {85, 50},
        {50, 82},
    },

    ["5-4-1:flat"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {15, 52}, {38, 55}, {62, 55}, {85, 52},
        {50, 82},
    },
    ["5-4-1:stagger"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {15, 52}, {42, 47}, {58, 62}, {85, 52},
        {50, 82},
    },
}

FormationShape.ZONE_KEYS = {
    "DEF_LEFT", "DEF_CENTER", "DEF_RIGHT",
    "MID_LEFT", "MID_CENTER", "MID_RIGHT",
    "ATT_LEFT", "ATT_CENTER", "ATT_RIGHT",
}

FormationShape.ZONE_LABELS = {
    DEF_LEFT = "后场左路", DEF_CENTER = "后场中路", DEF_RIGHT = "后场右路",
    MID_LEFT = "中场左路", MID_CENTER = "中场中路", MID_RIGHT = "中场右路",
    ATT_LEFT = "前场左路", ATT_CENTER = "前场中路", ATT_RIGHT = "前场右路",
}

-- 槽位兼容位置（与 AIManager._playerPositionScore 一致）
FormationShape.SLOT_COMPATIBILITY = {
    GK = { GK = 1.0 },
    CB = { CB = 1.0, RB = 0.6, LB = 0.6, CDM = 0.5 },
    RB = { RB = 1.0, CB = 0.6, RM = 0.7, RW = 0.5 },
    LB = { LB = 1.0, CB = 0.6, LM = 0.7, LW = 0.5 },
    CDM = { CDM = 1.0, CM = 0.8, CB = 0.5 },
    CM = { CM = 1.0, CDM = 0.8, CAM = 0.7, RM = 0.6, LM = 0.6 },
    CAM = { CAM = 1.0, CM = 0.7, RM = 0.6, LM = 0.6, ST = 0.5 },
    RM = { RM = 1.0, CM = 0.7, CAM = 0.6, RW = 0.8, RB = 0.5 },
    LM = { LM = 1.0, CM = 0.7, CAM = 0.6, LW = 0.8, LB = 0.5 },
    RW = { RW = 1.0, RM = 0.8, ST = 0.6, CAM = 0.6, RB = 0.5 },
    LW = { LW = 1.0, LM = 0.8, ST = 0.6, CAM = 0.6, LB = 0.5 },
    ST = { ST = 1.0, CAM = 0.6, RW = 0.5, LW = 0.5 },
}

FormationShape.POSITION_ORDER = {
    "GK", "LB", "CB", "RB", "CDM", "LM", "CM", "RM", "CAM", "LW", "RW", "ST",
}

-- 按实际槽位 DEF/MID/FWD 数量自动归类
-- 4231 按 4-3-3 线型（双后腰+前场三人组）；窄变体五中场归 451
local STRUCTURE_ARCHETYPES = {
    { key = "532", def = 5, mid = 3, fwd = 2, label = "5-3-2型",
      effectDesc = "五后卫低位，防守稳固",
      modifiers = { attack = 0.96, defense = 1.05, possession = 1.0, press = 0.96 } },
    { key = "541", def = 5, mid = 4, fwd = 1, label = "5-4-1型",
      effectDesc = "五后卫四中场，深度防守",
      modifiers = { attack = 0.94, defense = 1.06, possession = 1.0, press = 0.95 } },
    { key = "451", def = 4, mid = 5, fwd = 1, label = "4-5-1型",
      effectDesc = "五中场覆盖，控球消耗",
      modifiers = { attack = 0.95, defense = 1.04, possession = 1.03, press = 0.97 } },
    { key = "442", def = 4, mid = 4, fwd = 2, label = "4-4-2型",
      effectDesc = "经典均衡，攻守平衡",
      modifiers = { attack = 1.0, defense = 1.0, possession = 1.02 } },
    { key = "433", def = 4, mid = 3, fwd = 3, label = "4-3-3型",
      effectDesc = "三前锋宽度，前场压制",
      modifiers = { attack = 1.03, possession = 1.02, press = 1.02 } },
    { key = "424", def = 4, mid = 2, fwd = 4, label = "4-2-4型",
      effectDesc = "四后卫双中场四前锋，边路爆破",
      modifiers = { attack = 1.05, defense = 0.96, possession = 0.97, press = 1.03 } },
    { key = "4231", def = 4, mid = 3, fwd = 3, label = "4-2-3-1型",
      effectDesc = "双后腰层次，前场组推进",
      modifiers = { attack = 1.03, possession = 1.01, tempo = 1.02 } },
    { key = "343", def = 3, mid = 4, fwd = 3, label = "3-4-3型",
      effectDesc = "三中卫四中场，攻守过渡",
      modifiers = { attack = 1.03, defense = 0.98, possession = 1.01, press = 1.02 } },
    { key = "334", def = 3, mid = 3, fwd = 4, label = "3-3-4型",
      effectDesc = "三中卫四前锋，边路进攻拉满",
      modifiers = { attack = 1.04, defense = 0.97, possession = 0.98, press = 1.03 } },
    { key = "352", def = 3, mid = 5, fwd = 2, label = "3-5-2型",
      effectDesc = "翼卫宽度，中场控制",
      modifiers = { attack = 1.02, possession = 1.03 } },
}

local CUSTOM_STRUCTURE = {
    key = "custom",
    label = "自定义混合",
    effectDesc = "非经典结构，依靠区域密度与角色发挥",
    modifiers = {},
}

-- 选用阵型 → 期望结构（用于锚定与偏离提示）
FormationShape.FORMATION_TO_ARCHETYPE = {
    ["4-4-2"] = "442",
    ["4-3-3"] = "433",
    ["3-4-3"] = "343",
    ["3-5-2"] = "352",
    ["4-2-3-1"] = "4231",
    ["4-2-4"] = "424",
    ["5-3-2"] = "532",
    ["4-5-1"] = "451",
    ["5-4-1"] = "541",
}

-- 模板槽位在大类上的归属（中卫/中场槽位用；翼卫/前锋槽位见 structureLineForSlot）
local TEMPLATE_BUCKET = {
    GK = "GK",
    CB = "DEF", LB = "DEF", RB = "DEF",
    CDM = "MID", CM = "MID", CAM = "MID", LM = "MID", RM = "MID",
    RW = "FWD", LW = "FWD", ST = "FWD",
}

local POS_LINE = {
    GK = "GK",
    CB = "DEF", LB = "DEF", RB = "DEF",
    CDM = "MID", CM = "MID", CAM = "MID", LM = "MID", RM = "MID",
    LW = "FWD", RW = "FWD", ST = "FWD",
}

local NUDGE_STEP = 8
local MAX_OFFSET = 14
local STRUCTURE_MATCH_TOLERANCE = 2
local HEAVY_CUSTOM_THRESHOLD = 3
local FORMATION_ANCHOR_BIAS = 1.5

local WIDE_MID_TEMPLATE_SLOTS = {
    ["4-4-2:flat:6"] = true,
    ["4-4-2:flat:9"] = true,
    ["4-4-2:diamond:6"] = true,
    ["4-4-2:diamond:9"] = true,
    ["3-4-3:flat:5"] = true,
    ["3-4-3:flat:8"] = true,
    ["3-4-3:stagger:5"] = true,
    ["3-4-3:stagger:8"] = true,
    ["3-5-2:default:5"] = true,
    ["3-5-2:default:9"] = true,
    ["3-5-2:attack:5"] = true,
    ["3-5-2:attack:9"] = true,
    ["4-5-1:default:6"] = true,
    ["4-5-1:default:10"] = true,
    ["4-5-1:diamond:6"] = true,
    ["4-5-1:diamond:10"] = true,
    ["5-4-1:flat:7"] = true,
    ["5-4-1:flat:10"] = true,
    ["5-4-1:stagger:7"] = true,
    ["5-4-1:stagger:10"] = true,
}

local function wideMidTemplateKey(team, slotIdx)
    local formation = team.formation or "4-4-2"
    local layoutKey = Constants.normalizeLayoutKey(formation, team.formationVariant)
    local storageKey = Constants.layoutToStorageKey(formation, layoutKey)
    return formation .. ":" .. storageKey .. ":" .. tostring(slotIdx)
end

local function isWideMidTemplateSlot(team, slotIdx)
    return WIDE_MID_TEMPLATE_SLOTS[wideMidTemplateKey(team, slotIdx)] == true
end

local function structureLineForSlot(team, slotIdx, actualPos, useFullCustom)
    if useFullCustom then
        return POS_LINE[actualPos] or "MID"
    end

    local defaultPos = FormationShape.getDefaultSlotPosition(team, slotIdx)
    if isWideMidTemplateSlot(team, slotIdx) then
        return POS_LINE[actualPos] or "MID"
    end

    local defaultBucket = TEMPLATE_BUCKET[defaultPos]
    if defaultBucket == "FWD" then
        return POS_LINE[actualPos] or "FWD"
    end

    return TEMPLATE_BUCKET[defaultPos] or POS_LINE[actualPos] or "MID"
end

local DIMS = { "attack", "defense", "possession", "press", "counter", "tempo" }

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function emptyMods()
    return { attack = 1.0, defense = 1.0, possession = 1.0, press = 1.0, counter = 1.0, tempo = 1.0 }
end

local function mergeMods(base, extra)
    if not extra then return base end
    for _, dim in ipairs(DIMS) do
        base[dim] = (base[dim] or 1.0) * (extra[dim] or 1.0)
    end
    return base
end

local function countInZones(zoneCounts, keys)
    local n = 0
    for _, key in ipairs(keys) do
        n = n + (zoneCounts[key] or 0)
    end
    return n
end

local function resolveTeamArgs(teamOrFormation, variantKey)
    if type(teamOrFormation) == "table" and teamOrFormation.formation then
        local team = teamOrFormation
        return team.formation or "4-4-2",
            team.formationVariant or Constants.getDefaultVariant(team.formation or "4-4-2"),
            team.customSlots
    end
    return teamOrFormation or "4-4-2", variantKey, nil
end

function FormationShape.getBaseFormationSlots(formation, variantKey)
    local variant = Constants.getVariant(formation, variantKey)
    if variant and variant.slots then
        return variant.slots
    end
    local fallback = Constants.getVariant("4-4-2", "flat")
    return fallback and fallback.slots or { "GK", "RB", "CB", "CB", "LB", "RW", "CM", "CM", "LW", "ST", "ST" }
end

--- 获取实际槽位（变体模板 + customSlots 覆盖）
function FormationShape.getFormationSlots(teamOrFormation, variantKey)
    local formation, variant, customSlots = resolveTeamArgs(teamOrFormation, variantKey)
    local base = FormationShape.getBaseFormationSlots(formation, variant)
    if not customSlots then
        return base
    end
    local slots = {}
    for i = 1, 11 do
        slots[i] = Constants.normalizePosition(customSlots[i] or base[i]) or base[i]
    end
    return slots
end

function FormationShape.getBasePositions(formation, layoutOrStorageKey)
    local storageKey = Constants.layoutToStorageKey(formation, layoutOrStorageKey or Constants.getDefaultVariant(formation))
    local key = formation .. ":" .. storageKey
    local positions = FormationShape.FORMATION_POSITIONS[key]
    if positions then return positions end
    local defaultStorage = Constants.layoutToStorageKey(formation, Constants.getDefaultVariant(formation))
    local defaultKey = formation .. ":" .. defaultStorage
    return FormationShape.FORMATION_POSITIONS[defaultKey] or FormationShape.FORMATION_POSITIONS["4-4-2:flat"]
end

--- 当前阵型可选的中场布局 preset key 列表
function FormationShape.getLayoutOptions(formation)
    return Constants.getLayoutOptions(formation)
end

--- 读档/运行时规范化 team.formationVariant（layoutKey）
function FormationShape.normalizeFormationVariant(team)
    if not team then return end
    local formation = team.formation or "4-4-2"
    team.formationVariant = Constants.normalizeLayoutKey(formation, team.formationVariant)
end

--- 应用中场布局预设（清 customSlots / slotOffsets）
function FormationShape.applyLayoutPreset(team, layoutKey)
    if not team then return false end
    local formation = team.formation or "4-4-2"
    local normalized = Constants.normalizeLayoutKey(formation, layoutKey)
    if normalized == team.formationVariant and not FormationShape.hasCustomization(team) then
        return false
    end
    team.formationVariant = normalized
    FormationShape.clearCustomization(team)
    return true
end

function FormationShape.coordsToZone(x, y, slotPos)
    if slotPos == "GK" then return "DEF_CENTER" end
    local depth
    if y < 36 then depth = "DEF"
    elseif y < 62 then depth = "MID"
    else depth = "ATT" end
    local lane
    if x < 32 then lane = "LEFT"
    elseif x < 68 then lane = "CENTER"
    else lane = "RIGHT" end
    return depth .. "_" .. lane
end

function FormationShape.getSlotCoords(team, slotIdx)
    local formation = team.formation or "4-4-2"
    local variantKey = team.formationVariant or Constants.getDefaultVariant(formation)
    local positions = FormationShape.getBasePositions(formation, variantKey)
    local slots = FormationShape.getFormationSlots(team)
    local base = positions[slotIdx] or { 50, 50 }
    local x, y = base[1], base[2]

    local slotRoles = team.slotRoles or {}
    local roleKey = slotRoles[slotIdx]
    if roleKey and roleKey ~= "default" then
        local slotPos = slots[slotIdx]
        local role = Constants.getPositionRole(slotPos, roleKey)
        if role and role.posOffset then
            x = x - role.posOffset[1]
            y = y + role.posOffset[2]
        end
    end

    local slotOffsets = team.slotOffsets or {}
    local custom = slotOffsets[slotIdx]
    if custom then
        x = x + (custom[1] or custom.dx or 0)
        y = y + (custom[2] or custom.dy or 0)
    end

    if slots[slotIdx] ~= "GK" then
        x = clamp(x, 8, 92)
        y = clamp(y, 12, 88)
    end
    return x, y, slots[slotIdx]
end

-- 位置的侧边归属：RIGHT=球场右路, LEFT=球场左路, CENTER=中路
local POS_SIDE = {
    RB = "RIGHT", RM = "RIGHT", RW = "RIGHT",
    LB = "LEFT",  LM = "LEFT",  LW = "LEFT",
}

-- 位置纵深层级（5层：后2 / 后1 / 中1 / 前2 / 前1）
-- 前 group (tiers 4-5): 前场进攻位置
-- 中 group (tier 3): 中场组织位置
-- 后 group (tiers 1-2): 后场防守位置
local POS_DEPTH_TIER = {
    GK = 0,
    CB = 1, RB = 1, LB = 1,
    CDM = 2,
    CM = 3, RM = 3, LM = 3,
    CAM = 4, RW = 4, LW = 4,
    ST = 5,
}

-- 根据当前槽位纵深层级，返回允许的 tier 范围 [min, max]
-- 前 group (4-5): 只看前场 + 中场边界 → tiers 4-5
-- 中 group (3): 看中场 + 相邻 → tiers 2-4
-- 后 group (1-2): 只看后场 + 中场 → tiers 1-3
local function getAllowedDepthRange(slotTier)
    if slotTier >= 4 then return 4, 5 end  -- 前 group
    if slotTier == 3 then return 2, 4 end  -- 中 group
    return 1, 3                             -- 后 group
end

function FormationShape.getCompatiblePositions(slotPos, slotZone)
    if slotPos == "GK" then return { "GK" } end
    local row = FormationShape.SLOT_COMPATIBILITY[slotPos]
    if not row then return { slotPos } end

    -- 解析槽位区域的侧路信息
    local zoneLane = nil  -- "LEFT", "CENTER", "RIGHT"
    if slotZone then
        zoneLane = slotZone:match("_(%w+)$")
    end

    -- 纵深过滤范围
    local slotTier = POS_DEPTH_TIER[slotPos] or 3
    local minTier, maxTier = getAllowedDepthRange(slotTier)

    local orderIdx = {}
    for i, pos in ipairs(FormationShape.POSITION_ORDER) do
        orderIdx[pos] = i
    end

    local list = {}
    for pos, compat in pairs(row) do
        if compat >= 0.5 then
            local dominated = false

            -- 纵深过滤：只保留允许范围内的层级
            local posTier = POS_DEPTH_TIER[pos] or 3
            if posTier < minTier or posTier > maxTier then
                dominated = true
            end

            -- 前锋槽位允许临场改成左右边锋；其他槽位继续按所在区域过滤侧路。
            if not dominated and zoneLane then
                local posSide = POS_SIDE[pos]
                local allowWideForward = slotPos == "ST" and (pos == "LW" or pos == "RW")
                if allowWideForward then
                    dominated = false
                elseif zoneLane == "CENTER" then
                    -- 中路槽位：过滤掉纯边路位置
                    if posSide then dominated = true end
                elseif zoneLane == "LEFT" then
                    -- 低 x 是己方右路，不能给左路位置。
                    if posSide == "LEFT" then dominated = true end
                elseif zoneLane == "RIGHT" then
                    -- 高 x 是己方左路，不能给右路位置。
                    if posSide == "RIGHT" then dominated = true end
                end
            end

            if not dominated then
                table.insert(list, pos)
            end
        end
    end
    table.sort(list, function(a, b)
        return (orderIdx[a] or 99) < (orderIdx[b] or 99)
    end)
    return list
end

function FormationShape.getDefaultSlotPosition(team, slotIdx)
    local formation = team.formation or "4-4-2"
    local variantKey = team.formationVariant or Constants.getDefaultVariant(formation)
    local base = FormationShape.getBaseFormationSlots(formation, variantKey)
    return base[slotIdx]
end

function FormationShape.hasCustomization(team)
    if team.slotOffsets then
        for _, v in pairs(team.slotOffsets) do
            if v then return true end
        end
    end
    if not team.customSlots then return false end
    for slotIdx, pos in pairs(team.customSlots) do
        if pos and pos ~= FormationShape.getDefaultSlotPosition(team, slotIdx) then
            return true
        end
    end
    return false
end

function FormationShape.clearCustomization(team)
    team.customSlots = nil
    team.slotOffsets = nil
end

function FormationShape.setSlotPosition(team, slotIdx, newPos)
    newPos = Constants.normalizePosition(newPos)
    if not newPos or (newPos == "GK" and slotIdx ~= 1) then return false end
    local defaultPos = FormationShape.getDefaultSlotPosition(team, slotIdx)
    if not team.customSlots then team.customSlots = {} end

    if newPos == defaultPos then
        team.customSlots[slotIdx] = nil
    else
        team.customSlots[slotIdx] = newPos
    end

    -- 位置变更后清除不兼容角色
    if team.slotRoles and team.slotRoles[slotIdx] then
        local role = Constants.getPositionRole(newPos, team.slotRoles[slotIdx])
        if not role or team.slotRoles[slotIdx] ~= role.key then
            team.slotRoles[slotIdx] = nil
        end
    end
    return true
end

local function countLines(slots)
    local lines = { DEF = 0, MID = 0, FWD = 0, GK = 0 }
    for _, pos in ipairs(slots) do
        local line = POS_LINE[pos] or "MID"
        lines[line] = (lines[line] or 0) + 1
    end
    return lines
end

--- 统计与模板不同的槽位数量
function FormationShape.countSlotDeviations(team)
    local n = 0
    for i = 1, 11 do
        local custom = team.customSlots and team.customSlots[i]
        if custom and custom ~= FormationShape.getDefaultSlotPosition(team, i) then
            n = n + 1
        end
    end
    return n
end

--- 结构线计数：模板几何 + 翼卫改边锋按前锋计 + 深度自定义全按实际位置
local function countStructureLines(team, slots)
    local deviations = FormationShape.countSlotDeviations(team)
    local useFullCustom = deviations >= HEAVY_CUSTOM_THRESHOLD
    local lines = { DEF = 0, MID = 0, FWD = 0, GK = 0 }
    local countMode = "template"

    for i, pos in ipairs(slots) do
        local defaultPos = FormationShape.getDefaultSlotPosition(team, i)
        local line = structureLineForSlot(team, i, pos, useFullCustom)
        lines[line] = (lines[line] or 0) + 1
        if isWideMidTemplateSlot(team, i)
            and (defaultPos == "LM" or defaultPos == "RM")
            and (pos == "LW" or pos == "RW") then
            countMode = "hybrid"
        end
    end
    if useFullCustom then
        countMode = "custom"
    end
    return lines, countMode
end

function FormationShape.structureAlignsWithFormation(team, structure)
    local expected = FormationShape.FORMATION_TO_ARCHETYPE[team.formation or ""]
    if not expected or not structure then return true end
    return structure.key == expected
end

local function structureLineDistance(lines, archetype)
    return math.abs(lines.DEF - archetype.def)
        + math.abs(lines.MID - archetype.mid)
        + math.abs(lines.FWD - archetype.fwd)
end

function FormationShape.classifyStructure(slots, team)
    team = team or {}
    local lines, countMode = countStructureLines(team, slots)
    local anchorKey = FormationShape.FORMATION_TO_ARCHETYPE[team.formation or ""]
    local best, bestDist, bestRaw = CUSTOM_STRUCTURE, 999, 999

    for _, archetype in ipairs(STRUCTURE_ARCHETYPES) do
        local rawDist = structureLineDistance(lines, archetype)
        local dist = rawDist
        local isAnchor = anchorKey and archetype.key == anchorKey
        if isAnchor then
            dist = dist - FORMATION_ANCHOR_BIAS
        end

        local better = dist < bestDist
        if not better and dist == bestDist then
            -- 同线型并列时：优先选用阵型锚定，再优先精确线型匹配
            if isAnchor and best.key ~= anchorKey then
                better = true
            elseif isAnchor == (best.key == anchorKey) and rawDist < bestRaw then
                better = true
            end
        end

        if better then
            bestDist = dist
            bestRaw = rawDist
            best = archetype
        end
    end

    if bestRaw > STRUCTURE_MATCH_TOLERANCE then
        return CUSTOM_STRUCTURE, lines, bestRaw, countMode
    end
    return best, lines, bestRaw, countMode
end

local function analyzeSlotTypes(slots, slotZones)
    local counts = { CDM = 0, CAM = 0, WB = 0, WING = 0 }
    for i, pos in ipairs(slots) do
        if pos == "CDM" then counts.CDM = counts.CDM + 1 end
        if pos == "CAM" then counts.CAM = counts.CAM + 1 end
        if pos == "LB" or pos == "RB" then
            counts.WB = counts.WB + 1
        end
        if pos == "RW" or pos == "LW" then
            local zone = slotZones and slotZones[i] or ""
            if zone:sub(1, 3) == "ATT" then
                counts.WING = counts.WING + 1
            else
                counts.WB = counts.WB + 1
            end
        end
    end
    return counts
end

local function zoneDensityModifiers(zoneCounts, slotTypeCounts)
    local mods = emptyMods()
    local tags = {}

    local defLine = countInZones(zoneCounts, { "DEF_LEFT", "DEF_CENTER", "DEF_RIGHT" })
    local midLine = countInZones(zoneCounts, { "MID_LEFT", "MID_CENTER", "MID_RIGHT" })
    local attLine = countInZones(zoneCounts, { "ATT_LEFT", "ATT_CENTER", "ATT_RIGHT" })
    local widePlayers = countInZones(zoneCounts, { "MID_LEFT", "MID_RIGHT", "ATT_LEFT", "ATT_RIGHT" })
    local centralPlayers = (zoneCounts.MID_CENTER or 0) + (zoneCounts.ATT_CENTER or 0) + (zoneCounts.DEF_CENTER or 0)

    -- === 现有规则（幅度提升） ===
    if defLine >= 5 then
        mergeMods(mods, { defense = 1.06, attack = 0.97, tempo = 0.97 })
        table.insert(tags, "低位退守")
    end
    if attLine >= 3 then
        mergeMods(mods, { attack = 1.06, defense = 0.96, press = 1.04 })
        table.insert(tags, "前场堆叠")
    end
    if widePlayers >= 4 then
        mergeMods(mods, { attack = 1.05, possession = 0.97, tempo = 1.03 })
        table.insert(tags, "边路宽度")
    elseif widePlayers <= 2 and centralPlayers >= 4 then
        mergeMods(mods, { possession = 1.06, attack = 0.98, tempo = 0.97 })
        table.insert(tags, "中路密集")
    end
    if midLine >= 4 then
        mergeMods(mods, { possession = 1.05, press = 1.03 })
        table.insert(tags, "中场绞杀")
    end

    -- === 新增规则（v2 审查修正版） ===

    -- 后防真空：仅对3后卫且中路只有GK+1人时触发
    -- GK 固定在 DEF_CENTER，所以 DC≤2 意味着中路仅 GK + 1名后卫
    if (zoneCounts.DEF_CENTER or 0) <= 2 and defLine <= 4 then
        -- defLine<=4 确保不是5后卫（5后卫不可能中路薄弱）
        local defenderCount = defLine - 1  -- 减去GK
        if defenderCount <= 3 then
            mergeMods(mods, { defense = 0.96, counter = 0.94 })
            table.insert(tags, "中路防守薄弱")
        end
    end

    -- 中场通道真空：MID_CENTER == 0 且中场线有人（两侧有人中间无人）
    -- 验证：4-2-3-1 的两个 DM(x=35,65) 在 MID_CENTER(32≤x<68)，MC≥2，不会触发 ✓
    -- 触发场景：极端双边路阵型或深度自定义推人后中路完全空了
    if (zoneCounts.MID_CENTER or 0) == 0 and midLine >= 2 then
        mergeMods(mods, { possession = 0.95, tempo = 0.96 })
        table.insert(tags, "中路断联")
    end

    -- 前场单侧集中：一侧 ≥ 2 人，另一侧 0 人
    -- 验证：标准阵型 ATT_L 和 ATT_R 各 0-1 人，不会触发 ✓
    -- 触发场景：nudge 把边锋推向同侧，或自定义非对称前锋线
    local attLeft = zoneCounts.ATT_LEFT or 0
    local attRight = zoneCounts.ATT_RIGHT or 0
    if (attLeft >= 2 and attRight == 0) or (attRight >= 2 and attLeft == 0) then
        mergeMods(mods, { attack = 1.03, possession = 0.98 })
        table.insert(tags, "进攻偏侧集中")
    end

    -- 全阵型紧凑：三条线人数差 ≤ 2 且后场和中场各 ≥ 3 人
    -- 验证：3-4-3 → def=4,mid=4,att=3 → spread=1 → 触发 ✓
    --        4-4-2 → def=5,mid=4,att=2 → spread=3 → 不触发 ✓
    local lineSpread = math.max(defLine, midLine, attLine) - math.min(defLine, midLine, attLine)
    if lineSpread <= 2 and defLine >= 3 and midLine >= 3 then
        mergeMods(mods, { press = 1.04, possession = 1.02 })
        table.insert(tags, "阵型紧凑")
    end

    -- 后场边路覆盖宽（DEF_LEFT + DEF_RIGHT ≥ 4）
    -- 验证：5-3-2 DL=2,DR=2 → 4 → 触发 ✓；4-4-2 DL=1,DR=1 → 2 → 不触发 ✓
    -- 意图：翼卫体系的宽度拉伸效果
    if (zoneCounts.DEF_LEFT or 0) + (zoneCounts.DEF_RIGHT or 0) >= 4 then
        mergeMods(mods, { defense = 1.03, attack = 0.98, press = 0.97 })
        table.insert(tags, "翼卫覆盖宽")
    end

    -- === 槽位类型规则（保持不变） ===
    if slotTypeCounts.CDM >= 2 then
        mergeMods(mods, { defense = 1.04, attack = 0.97, tempo = 0.97 })
        table.insert(tags, "双后腰")
    elseif slotTypeCounts.CDM == 1 and slotTypeCounts.CAM >= 1 then
        mergeMods(mods, { attack = 1.03, possession = 1.02 })
        table.insert(tags, "前后腰联动")
    end
    if slotTypeCounts.CAM >= 2 then
        mergeMods(mods, { attack = 1.03, possession = 1.02, defense = 0.98 })
        table.insert(tags, "多前腰")
    end
    if slotTypeCounts.WING >= 2 then
        mergeMods(mods, { attack = 1.03, tempo = 1.02 })
        table.insert(tags, "双翼齐飞")
    end

    return mods, tags
end

local function formatDelta(value)
    if not value or value == 1.0 then return nil end
    local pct = math.floor((value - 1.0) * 100 + (value >= 1 and 0.5 or -0.5))
    if pct == 0 then return nil end
    if pct > 0 then return "+" .. pct .. "%" end
    return tostring(pct) .. "%"
end

local DIM_LABELS = {
    attack = "进攻", defense = "防守", possession = "控球",
    press = "压迫", counter = "反击", tempo = "节奏",
}

local function buildAnalysis(team, slotsOverride)
    local formation = team.formation or "4-4-2"
    local variantKey = team.formationVariant or Constants.getDefaultVariant(formation)
    local slots = slotsOverride or FormationShape.getFormationSlots(team)
    local structure, lineCounts, _, countMode = FormationShape.classifyStructure(slots, team)
    local alignedWithFormation = FormationShape.structureAlignsWithFormation(team, structure)
    local structureMods = emptyMods()
    mergeMods(structureMods, structure.modifiers)

    local zoneCounts = {}
    for _, key in ipairs(FormationShape.ZONE_KEYS) do
        zoneCounts[key] = 0
    end
    local slotZones = {}

    for i = 1, 11 do
        local x, y, slotPos = FormationShape.getSlotCoords(team, i)
        if slotsOverride and slotsOverride[i] then
            slotPos = slotsOverride[i]
        end
        local zone = FormationShape.coordsToZone(x, y, slotPos)
        slotZones[i] = zone
        zoneCounts[zone] = (zoneCounts[zone] or 0) + 1
    end

    local slotTypeCounts = analyzeSlotTypes(slots, slotZones)
    local zoneMods, zoneTags = zoneDensityModifiers(zoneCounts, slotTypeCounts)

    local combined = emptyMods()
    mergeMods(combined, structureMods)
    mergeMods(combined, zoneMods)

    local effectLines = {}
    table.insert(effectLines, "选用阵型：" .. formation)
    table.insert(effectLines, "实战结构：" .. structure.label .. "（" .. lineCounts.DEF .. "-" .. lineCounts.MID .. "-" .. lineCounts.FWD .. "）")
    if not alignedWithFormation then
        local expectedLabel = FormationShape.FORMATION_TO_ARCHETYPE[formation]
        for _, arch in ipairs(STRUCTURE_ARCHETYPES) do
            if arch.key == expectedLabel then
                table.insert(effectLines, "已偏离选用阵型（期望 " .. arch.label .. "）")
                break
            end
        end
    end
    if countMode == "hybrid" then
        table.insert(effectLines, "边中场前置为边锋，前场线按边锋重算")
    elseif countMode == "custom" then
        table.insert(effectLines, "深度自定义：按实际位置重算结构")
    end
    if structure.effectDesc and structure.effectDesc ~= "" then
        table.insert(effectLines, structure.effectDesc)
    end
    for _, dim in ipairs(DIMS) do
        local delta = formatDelta(structureMods[dim])
        if delta then
            table.insert(effectLines, "结构" .. DIM_LABELS[dim] .. " " .. delta)
        end
    end
    for _, tag in ipairs(zoneTags) do
        table.insert(effectLines, "区域：" .. tag)
    end

    return {
        formation = formation,
        variantKey = variantKey,
        slots = slots,
        lineCounts = lineCounts,
        structure = structure,
        structureMods = structureMods,
        alignedWithFormation = alignedWithFormation,
        countMode = countMode,
        slotDeviations = FormationShape.countSlotDeviations(team),
        zoneCounts = zoneCounts,
        slotZones = slotZones,
        zoneMods = zoneMods,
        combinedMods = combined,
        tags = zoneTags,
        effectDesc = structure.effectDesc,
        effectLines = effectLines,
    }
end

function FormationShape.analyze(team)
    return buildAnalysis(team, nil)
end

--- 预览某槽位改为新位置后的形态（不写回 team）
function FormationShape.previewSlotPosition(team, slotIdx, newPos)
    local slots = FormationShape.getFormationSlots(team)
    local previewSlots = {}
    for i = 1, 11 do
        previewSlots[i] = slots[i]
    end
    previewSlots[slotIdx] = newPos
    return buildAnalysis(team, previewSlots)
end

function FormationShape.getCombinedModifiers(team)
    return FormationShape.analyze(team).combinedMods
end

function FormationShape.getEffectSummary(team)
    local analysis = FormationShape.analyze(team)
    return analysis.effectLines, analysis.combinedMods, analysis.effectDesc
end

function FormationShape.nudgeSlot(team, slotIdx, direction)
    if not team.slotOffsets then team.slotOffsets = {} end
    local offsets = team.slotOffsets[slotIdx] or { 0, 0 }
    local dx, dy = offsets[1] or 0, offsets[2] or 0

    if direction == "forward" then dy = dy + NUDGE_STEP
    elseif direction == "back" then dy = dy - NUDGE_STEP
    elseif direction == "wide" then
        local x = FormationShape.getSlotCoords(team, slotIdx)
        if x < 50 then dx = dx - NUDGE_STEP else dx = dx + NUDGE_STEP end
    elseif direction == "narrow" then
        local x = FormationShape.getSlotCoords(team, slotIdx)
        if x < 50 then dx = dx + NUDGE_STEP else dx = dx - NUDGE_STEP end
    else
        return false
    end

    dx = clamp(dx, -MAX_OFFSET, MAX_OFFSET)
    dy = clamp(dy, -MAX_OFFSET, MAX_OFFSET)
    if dx == 0 and dy == 0 then
        team.slotOffsets[slotIdx] = nil
    else
        team.slotOffsets[slotIdx] = { dx, dy }
    end
    return true
end

function FormationShape.resetSlotOffsets(team)
    team.slotOffsets = nil
end

function FormationShape.resetCustomSlots(team)
    team.customSlots = nil
end

return FormationShape
