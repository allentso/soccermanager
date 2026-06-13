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

-- 槽位兼容位置（与 AIManager._playerPositionScore 一致）
FormationShape.SLOT_COMPATIBILITY = {
    GK = { GK = 1.0 },
    CB = { CB = 1.0, RB = 0.6, LB = 0.6, CDM = 0.5 },
    RB = { RB = 1.0, CB = 0.6, RM = 0.7, LB = 0.8 },
    LB = { LB = 1.0, CB = 0.6, LM = 0.7, RB = 0.8 },
    CDM = { CDM = 1.0, CM = 0.8, CB = 0.5 },
    CM = { CM = 1.0, CDM = 0.8, CAM = 0.7, RM = 0.6, LM = 0.6 },
    CAM = { CAM = 1.0, CM = 0.7, RW = 0.6, LW = 0.6, ST = 0.5 },
    RM = { RM = 1.0, RW = 0.9, CM = 0.6, RB = 0.5, LM = 0.7 },
    LM = { LM = 1.0, LW = 0.9, CM = 0.6, LB = 0.5, RM = 0.7 },
    RW = { RW = 1.0, RM = 0.9, ST = 0.6, CAM = 0.6, LW = 0.7 },
    LW = { LW = 1.0, LM = 0.9, ST = 0.6, CAM = 0.6, RW = 0.7 },
    ST = { ST = 1.0, CAM = 0.6, RW = 0.5, LW = 0.5 },
    CF = { CF = 1.0, ST = 0.9, CAM = 0.6 },
}

FormationShape.POSITION_ORDER = {
    "GK", "LB", "CB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "CF", "ST",
}

-- 按实际槽位 DEF/MID/FWD 数量自动归类
local STRUCTURE_ARCHETYPES = {
    { key = "532", def = 5, mid = 3, fwd = 2, label = "5-3-2型",
      effectDesc = "五后卫低位，防守稳固",
      modifiers = { attack = 0.96, defense = 1.05, possession = 1.0, press = 0.96 } },
    { key = "451", def = 4, mid = 5, fwd = 1, label = "4-5-1型",
      effectDesc = "五中场覆盖，控球消耗",
      modifiers = { attack = 0.95, defense = 1.04, possession = 1.03, press = 0.97 } },
    { key = "442", def = 4, mid = 4, fwd = 2, label = "4-4-2型",
      effectDesc = "经典均衡，攻守平衡",
      modifiers = { attack = 1.0, defense = 1.0, possession = 1.02 } },
    { key = "433", def = 4, mid = 3, fwd = 3, label = "4-3-3型",
      effectDesc = "三前锋宽度，前场压制",
      modifiers = { attack = 1.03, possession = 1.02, press = 1.02 } },
    { key = "4231", def = 4, mid = 5, fwd = 1, label = "4-2-3-1型",
      effectDesc = "双后腰层次，前场组推进",
      modifiers = { attack = 1.03, possession = 1.01, tempo = 1.02 } },
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

local POS_LINE = {
    GK = "GK",
    CB = "DEF", LB = "DEF", RB = "DEF",
    CDM = "MID", CM = "MID", CAM = "MID", RM = "MID", LM = "MID",
    LW = "FWD", RW = "FWD", ST = "FWD", CF = "FWD",
}

local NUDGE_STEP = 8
local MAX_OFFSET = 14
local STRUCTURE_MATCH_TOLERANCE = 2

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
    local fallback = Constants.FORMATION_VARIANTS["4-4-2"]
    return fallback and fallback[1].slots or { "GK", "RB", "CB", "CB", "LB", "RM", "CM", "CM", "LM", "ST", "ST" }
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
        slots[i] = customSlots[i] or base[i]
    end
    return slots
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
    local slots = FormationShape.getFormationSlots(team)
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

function FormationShape.getCompatiblePositions(slotPos)
    if slotPos == "GK" then return { "GK" } end
    local row = FormationShape.SLOT_COMPATIBILITY[slotPos]
    if not row then return { slotPos } end

    local orderIdx = {}
    for i, pos in ipairs(FormationShape.POSITION_ORDER) do
        orderIdx[pos] = i
    end

    local list = {}
    for pos, compat in pairs(row) do
        if compat >= 0.5 then
            table.insert(list, pos)
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

function FormationShape.classifyStructure(slots)
    local lines = countLines(slots)
    local best, bestDist = CUSTOM_STRUCTURE, 999

    for _, archetype in ipairs(STRUCTURE_ARCHETYPES) do
        local dist = math.abs(lines.DEF - archetype.def)
            + math.abs(lines.MID - archetype.mid)
            + math.abs(lines.FWD - archetype.fwd)
        if dist < bestDist then
            bestDist = dist
            best = archetype
        end
    end

    if bestDist > STRUCTURE_MATCH_TOLERANCE then
        return CUSTOM_STRUCTURE, lines, bestDist
    end
    return best, lines, bestDist
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

local function buildAnalysis(team, slotsOverride)
    local formation = team.formation or "4-4-2"
    local variantKey = team.formationVariant or Constants.getDefaultVariant(formation)
    local slots = slotsOverride or FormationShape.getFormationSlots(team)
    local structure, lineCounts = FormationShape.classifyStructure(slots)
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

    local slotTypeCounts = analyzeSlotTypes(slots)
    local zoneMods, zoneTags = zoneDensityModifiers(zoneCounts, slotTypeCounts)

    local combined = emptyMods()
    mergeMods(combined, structureMods)
    mergeMods(combined, zoneMods)

    local effectLines = {}
    table.insert(effectLines, "识别形态：" .. structure.label .. "（" .. lineCounts.DEF .. "-" .. lineCounts.MID .. "-" .. lineCounts.FWD .. "）")
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
