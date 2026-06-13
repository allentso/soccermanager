-- match/formation_shape.lua
-- 球场九区划分、阵容形态分析与效果乘数（变体预设 + 区域密度 + 自定义偏移）

local Constants = require("scripts/app/constants")

local FormationShape = {}

-- 球场坐标：x=横向(0左-100右), y=纵向(0己方底线-100对方底线)
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
    ["4-4-2:hold"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {38, 48}, {62, 48}, {85, 52},
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
    ["4-3-3:flat"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {30, 52}, {50, 55}, {70, 52},
        {20, 80}, {50, 82}, {80, 80},
    },
    ["3-5-2:default"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 48}, {67, 55}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["3-5-2:attack"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {50, 62}, {50, 48}, {67, 52}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["3-5-2:dhold"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {50, 55}, {38, 46}, {62, 46}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["4-2-3-1:wide"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {80, 68}, {20, 68},
        {50, 85},
    },
    ["4-2-3-1:narrow"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {68, 63}, {32, 63},
        {50, 85},
    },
    ["4-2-3-1:asym"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {80, 68}, {32, 63},
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
    ["5-3-2:attack"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {70, 52}, {50, 62},
        {35, 80}, {65, 80},
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
    ["4-5-1:flat"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 53}, {50, 55}, {67, 53}, {85, 50},
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

-- 变体预设形态效果（弥补「经典/进攻/双后腰」无独立乘数的问题）
FormationShape.VARIANT_PROFILES = {
    ["4-4-2:flat"]      = { modifiers = { attack = 1.0,  defense = 1.0,  possession = 1.02, press = 1.0  }, effectDesc = "平行中场，宽度与控球均衡" },
    ["4-4-2:diamond"]   = { modifiers = { attack = 1.03, defense = 1.0,  possession = 1.03, tempo = 1.02 }, effectDesc = "菱形纵深，串联前后场" },
    ["4-4-2:hold"]      = { modifiers = { attack = 0.97, defense = 1.05, possession = 0.98, tempo = 0.97 }, effectDesc = "双后腰屏障，防守稳固" },

    ["4-3-3:hold"]      = { modifiers = { attack = 0.98, defense = 1.04, possession = 1.02, press = 0.98 }, effectDesc = "正三角后腰，稳守反击" },
    ["4-3-3:attack"]    = { modifiers = { attack = 1.05, defense = 0.97, possession = 1.02, tempo = 1.04 }, effectDesc = "倒三角前腰，前场堆叠" },
    ["4-3-3:flat"]      = { modifiers = { attack = 1.0,  defense = 1.0,  possession = 1.04, press = 1.02 }, effectDesc = "三中场平行，控球覆盖广" },

    ["3-5-2:default"]   = { modifiers = { attack = 1.02, defense = 1.0,  possession = 1.03, press = 1.0  }, effectDesc = "翼卫拉边，宽度大、控球稳" },
    ["3-5-2:attack"]    = { modifiers = { attack = 1.05, defense = 0.97, possession = 1.02, tempo = 1.03 }, effectDesc = "前腰驱动，中路渗透加强" },
    ["3-5-2:dhold"]     = { modifiers = { attack = 0.96, defense = 1.06, possession = 0.98, tempo = 0.97 }, effectDesc = "双后腰屏障，低位防守" },

    ["4-2-3-1:wide"]    = { modifiers = { attack = 1.04, defense = 1.0,  possession = 0.98, press = 1.02 }, effectDesc = "边锋拉边，宽度进攻" },
    ["4-2-3-1:narrow"]  = { modifiers = { attack = 1.03, defense = 1.0,  possession = 1.04, tempo = 0.98 }, effectDesc = "三前腰收窄，中路渗透" },
    ["4-2-3-1:asym"]    = { modifiers = { attack = 1.04, defense = 0.99, possession = 1.01, tempo = 1.02 }, effectDesc = "不对称站位，单边过载" },

    ["5-3-2:flat"]      = { modifiers = { attack = 0.96, defense = 1.05, possession = 1.0,  press = 0.96 }, effectDesc = "五后卫平行中场，低位防守" },
    ["5-3-2:hold"]      = { modifiers = { attack = 0.95, defense = 1.06, possession = 0.99, tempo = 0.96 }, effectDesc = "单后腰五后卫，极度稳固" },
    ["5-3-2:attack"]    = { modifiers = { attack = 1.02, defense = 1.03, possession = 1.0,  tempo = 1.02 }, effectDesc = "前腰突前，五后卫反击" },

    ["4-5-1:default"]   = { modifiers = { attack = 0.95, defense = 1.04, possession = 1.02, press = 0.97 }, effectDesc = "五中场覆盖，控球消耗" },
    ["4-5-1:diamond"]   = { modifiers = { attack = 0.97, defense = 1.03, possession = 1.04, tempo = 0.98 }, effectDesc = "菱形五中场，中路控制" },
    ["4-5-1:flat"]      = { modifiers = { attack = 0.94, defense = 1.05, possession = 1.03, press = 0.96 }, effectDesc = "五中场平行，极致防守" },
}

local NUDGE_STEP = 8
local MAX_OFFSET = 14

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

function FormationShape.getFormationSlots(formation, variantKey)
    local variant = Constants.getVariant(formation, variantKey)
    if variant and variant.slots then
        return variant.slots
    end
    local fallback = Constants.FORMATION_VARIANTS["4-4-2"]
    return fallback and fallback[1].slots or { "GK", "RB", "CB", "CB", "LB", "RM", "CM", "CM", "LM", "ST", "ST" }
end

function FormationShape.getBasePositions(formation, variantKey)
    local key = formation .. ":" .. (variantKey or Constants.getDefaultVariant(formation))
    local positions = FormationShape.FORMATION_POSITIONS[key]
    if positions then return positions end
    local defaultKey = formation .. ":" .. Constants.getDefaultVariant(formation)
    return FormationShape.FORMATION_POSITIONS[defaultKey] or FormationShape.FORMATION_POSITIONS["4-4-2:flat"]
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
    local slots = FormationShape.getFormationSlots(formation, variantKey)
    local base = positions[slotIdx] or { 50, 50 }
    local x, y = base[1], base[2]

    local slotRoles = team.slotRoles or {}
    local roleKey = slotRoles[slotIdx]
    if roleKey and roleKey ~= "default" then
        local slotPos = slots[slotIdx]
        local role = Constants.getPositionRole(slotPos, roleKey)
        if role and role.posOffset then
            x = x + role.posOffset[1]
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

function FormationShape.getVariantProfile(formation, variantKey)
    local key = formation .. ":" .. (variantKey or Constants.getDefaultVariant(formation))
    local variant = Constants.getVariant(formation, variantKey)
    if variant and variant.modifiers then
        return {
            modifiers = variant.modifiers,
            effectDesc = variant.effectDesc or "",
        }
    end
    return FormationShape.VARIANT_PROFILES[key] or { modifiers = emptyMods(), effectDesc = "标准站位" }
end

local function analyzeSlotTypes(slots)
    local counts = { CDM = 0, CAM = 0, WB = 0, WING = 0 }
    for _, pos in ipairs(slots) do
        if pos == "CDM" then counts.CDM = counts.CDM + 1 end
        if pos == "CAM" then counts.CAM = counts.CAM + 1 end
        if pos == "RM" or pos == "LM" or pos == "LB" or pos == "RB" then counts.WB = counts.WB + 1 end
        if pos == "RW" or pos == "LW" then counts.WING = counts.WING + 1 end
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
    local centralPlayers = zoneCounts.MID_CENTER + zoneCounts.ATT_CENTER + zoneCounts.DEF_CENTER

    if defLine >= 5 then
        mergeMods(mods, { defense = 1.04, attack = 0.98, tempo = 0.98 })
        table.insert(tags, "低位退守")
    end
    if attLine >= 3 then
        mergeMods(mods, { attack = 1.04, defense = 0.97, press = 1.03 })
        table.insert(tags, "前场堆叠")
    end
    if widePlayers >= 4 then
        mergeMods(mods, { attack = 1.03, possession = 0.98, tempo = 1.02 })
        table.insert(tags, "边路宽度")
    elseif widePlayers <= 2 and centralPlayers >= 4 then
        mergeMods(mods, { possession = 1.04, attack = 0.99, tempo = 0.98 })
        table.insert(tags, "中路密集")
    end
    if midLine >= 4 then
        mergeMods(mods, { possession = 1.03, press = 1.02 })
        table.insert(tags, "中场绞杀")
    end
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

function FormationShape.analyze(team)
    local formation = team.formation or "4-4-2"
    local variantKey = team.formationVariant or Constants.getDefaultVariant(formation)
    local slots = FormationShape.getFormationSlots(formation, variantKey)
    local profile = FormationShape.getVariantProfile(formation, variantKey)

    local zoneCounts = {}
    for _, key in ipairs(FormationShape.ZONE_KEYS) do
        zoneCounts[key] = 0
    end
    local slotZones = {}

    for i = 1, 11 do
        local x, y, slotPos = FormationShape.getSlotCoords(team, i)
        local zone = FormationShape.coordsToZone(x, y, slotPos)
        slotZones[i] = zone
        zoneCounts[zone] = (zoneCounts[zone] or 0) + 1
    end

    local slotTypeCounts = analyzeSlotTypes(slots)
    local zoneMods, zoneTags = zoneDensityModifiers(zoneCounts, slotTypeCounts)

    local combined = emptyMods()
    mergeMods(combined, profile.modifiers)
    mergeMods(combined, zoneMods)

    local effectLines = {}
    if profile.effectDesc and profile.effectDesc ~= "" then
        table.insert(effectLines, "变体：" .. profile.effectDesc)
    end
    for _, dim in ipairs(DIMS) do
        local variantDelta = formatDelta(profile.modifiers[dim])
        if variantDelta then
            table.insert(effectLines, "变体" .. DIM_LABELS[dim] .. " " .. variantDelta)
        end
    end
    for _, tag in ipairs(zoneTags) do
        table.insert(effectLines, "区域：" .. tag)
    end

    return {
        formation = formation,
        variantKey = variantKey,
        slots = slots,
        zoneCounts = zoneCounts,
        slotZones = slotZones,
        variantMods = profile.modifiers,
        zoneMods = zoneMods,
        combinedMods = combined,
        tags = zoneTags,
        effectDesc = profile.effectDesc,
        effectLines = effectLines,
    }
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

return FormationShape
