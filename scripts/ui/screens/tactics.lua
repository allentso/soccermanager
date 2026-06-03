-- ui/screens/tactics.lua
-- 战术设置页面 - 含球场视图和定位球角色分配

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local AIManager = require("scripts/systems/ai_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local WorldCup = require("scripts/systems/world_cup")

local Tactics = {}

---@type string
local _activeTab = "formation" -- formation | setpiece

-- 局部 ScrollView 引用，用于局部刷新避免整页重建
---@type any
local _formationScrollView = nil

-- 阵型变体位置坐标映射 (x%, y% 从球场左下角计算, x=横向0-100, y=纵向0-100从底到顶)
-- 键: "阵型:变体key"
local FORMATION_POSITIONS = {
    -- 4-4-2
    ["4-4-2:flat"] = {
        {50, 5},   -- GK
        {15, 25}, {38, 28}, {62, 28}, {85, 25}, -- DEF
        {15, 52}, {38, 55}, {62, 55}, {85, 52}, -- MID (RM CM CM LM)
        {35, 80}, {65, 80},                      -- FWD
    },
    ["4-4-2:diamond"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {50, 45}, {50, 65}, {85, 52}, -- RM CDM CAM LM
        {35, 80}, {65, 80},
    },
    ["4-4-2:hold"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {38, 48}, {62, 48}, {85, 52}, -- RM CDM CDM LM
        {35, 80}, {65, 80},
    },

    -- 4-3-3
    ["4-3-3:hold"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {50, 42}, {65, 50},            -- CM CDM CM (正三角)
        {20, 80}, {50, 82}, {80, 80},
    },
    ["4-3-3:attack"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {65, 50}, {50, 62},            -- CM CM CAM (倒三角)
        {20, 80}, {50, 82}, {80, 80},
    },
    ["4-3-3:flat"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {30, 52}, {50, 55}, {70, 52},            -- CM CM CM (平行)
        {20, 80}, {50, 82}, {80, 80},
    },

    -- 3-5-2
    ["3-5-2:default"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 48}, {67, 55}, {90, 50}, -- RM CM CDM CM LM
        {35, 80}, {65, 80},
    },
    ["3-5-2:attack"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {50, 62}, {50, 48}, {67, 52}, {90, 50}, -- RM CAM CDM CM LM
        {35, 80}, {65, 80},
    },
    ["3-5-2:dhold"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {50, 55}, {38, 46}, {62, 46}, {90, 50}, -- RM CM CDM CDM LM
        {35, 80}, {65, 80},
    },

    -- 4-2-3-1
    ["4-2-3-1:wide"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},                       -- CDM CDM
        {50, 65}, {80, 68}, {20, 68},             -- CAM RW LW
        {50, 85},
    },
    ["4-2-3-1:narrow"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},                       -- CDM CDM
        {50, 65}, {68, 63}, {32, 63},             -- CAM CAM CAM (内收)
        {50, 85},
    },
    ["4-2-3-1:asym"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},                       -- CDM CDM
        {50, 65}, {80, 68}, {32, 63},             -- CAM RW CAM
        {50, 85},
    },

    -- 5-3-2
    ["5-3-2:flat"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {50, 55}, {70, 52},             -- CM CM CM
        {35, 80}, {65, 80},
    },
    ["5-3-2:hold"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {35, 52}, {50, 45}, {65, 52},             -- CM CDM CM
        {35, 80}, {65, 80},
    },
    ["5-3-2:attack"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {70, 52}, {50, 62},             -- CM CM CAM
        {35, 80}, {65, 80},
    },

    -- 4-5-1
    ["4-5-1:default"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 55}, {50, 48}, {67, 55}, {85, 50}, -- RM CM CDM CM LM
        {50, 82},
    },
    ["4-5-1:diamond"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {50, 42}, {50, 62}, {67, 55}, {85, 50}, -- RM CDM CAM CM LM
        {50, 82},
    },
    ["4-5-1:flat"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 53}, {50, 55}, {67, 53}, {85, 50}, -- RM CM CM CM LM
        {50, 82},
    },
}

--- 获取当前阵型+变体的球场坐标（兼容 fallback）
local function getFormationPositions(formation, variantKey)
    local key = formation .. ":" .. (variantKey or "")
    if FORMATION_POSITIONS[key] then
        return FORMATION_POSITIONS[key]
    end
    -- fallback: 尝试该阵型的第一个变体
    local defaultVKey = Constants.getDefaultVariant(formation)
    local defaultKey = formation .. ":" .. defaultVKey
    if FORMATION_POSITIONS[defaultKey] then
        return FORMATION_POSITIONS[defaultKey]
    end
    return FORMATION_POSITIONS["4-4-2:flat"]
end

-- 定位球角色定义
local SET_PIECE_ROLES = {
    { key = "captain",       label = "队长",     icon = "©" },
    { key = "penaltyTaker",  label = "点球手",   icon = "⚽" },
    { key = "freeKickTaker", label = "任意球手", icon = "🎯" },
    { key = "cornerTaker",   label = "角球手",   icon = "📐" },
    { key = "throwInTaker",  label = "界外球手", icon = "🤾" },
}

function Tactics.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无数据" } }
        }
    end

    -- 判断当前身份：国家队模式 vs 俱乐部模式
    local isNTMode = gameState.currentRole == "national_team"
        and gameState.nationalTeamCoach ~= nil
        and gameState.worldCup ~= nil

    local team
    if isNTMode then
        local nationCode = gameState.nationalTeamCoach.nation
        team = WorldCup.buildNationalTeam(gameState, nationCode)
    else
        team = gameState:getPlayerTeam()
    end

    if not team then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "未选择球队" } }
        }
    end

    -- 读取 params 中的 tab
    if params and params.tab then
        _activeTab = params.tab
    end

    local content
    if _activeTab == "setpiece" then
        content = Tactics._buildSetPieceContent(gameState, team)
    else
        content = Tactics._buildFormationContent(gameState, team, isNTMode)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "战术设置",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- 二级导航
            Theme.SquadSubNav("tactics"),

            -- 内部 tab 切换
            Tactics._buildTabBar(),

            -- 内容（保存引用用于局部刷新）
            (function()
                local sv = UI.ScrollView {
                    flexGrow = 1,
                    flexBasis = 0,
                    scrollY = true,
                    padding = 14,
                    children = content,
                }
                if _activeTab == "formation" then
                    _formationScrollView = sv
                end
                return sv
            end)(),

            -- 底部导航
            Theme.MainNav("squad"),
        }
    }
end

-- Tab切换栏
function Tactics._buildTabBar()
    local tabs = {
        { key = "formation", label = "阵型与球场" },
        { key = "setpiece",  label = "定位球人选" },
    }
    local children = {}
    for _, t in ipairs(tabs) do
        local isActive = t.key == _activeTab
        table.insert(children, UI.Button {
            text = t.label,
            height = 34,
            paddingLeft = 16,
            paddingRight = 16,
            backgroundColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.TRANSPARENT,
            borderRadius = 17,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 8,
            onClick = function()
                if not isActive then
                    _activeTab = t.key
                    Router.replaceWith("tactics", { tab = t.key })
                end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        height = 48,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14,
        backgroundColor = Theme.COLORS.BG_DARK,
        children = children,
    }
end

---------------------------------------------------------------------------
-- 阵型与球场视图
---------------------------------------------------------------------------

-- 构建阵型内容子元素
local function _buildFormationChildren(gameState, team, isNTMode)
    local currentFormation = team.formation or "4-4-2"
    local currentPlayStyle = team.playStyle or "Balanced"
    if not team.formationVariant then
        team.formationVariant = Constants.getDefaultVariant(currentFormation)
    end
    local currentVariant = team.formationVariant

    -- 国家队模式下保存战术设置的辅助函数
    local function saveNTSettings()
        if isNTMode and gameState.nationalTeamCoach then
            WorldCup.saveNationalTeamSettings(gameState, gameState.nationalTeamCoach.nation, team)
        end
    end

    -- 前置声明刷新函数：清空 ScrollView 并重建内容
    local function refresh()
        saveNTSettings()
        if _formationScrollView then
            _formationScrollView:ClearChildren()
            local newChildren = _buildFormationChildren(gameState, team, isNTMode)
            -- 用单一 Panel 包裹所有子元素，确保 ScrollView 高度计算正确
            _formationScrollView:AddChild(UI.Panel {
                width = "100%",
                children = newChildren,
            })
        end
    end

    -- 阵型按钮
    local formationChildren = {}
    for _, fmt in ipairs(Constants.FORMATIONS) do
        local isActive = fmt == currentFormation
        table.insert(formationChildren, UI.Button {
            text = fmt,
            width = "30%",
            height = 42,
            backgroundColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            borderWidth = isActive and 0 or 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 14,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 8,
            onClick = function()
                if fmt ~= team.formation then
                    team.formation = fmt
                    team.formationVariant = Constants.getDefaultVariant(fmt)
                    AIManager.rearrangeForFormation(gameState, team)
                end
                refresh()
            end,
        })
    end

    -- 阵型变体按钮
    local variantChildren = {}
    local variants = Constants.FORMATION_VARIANTS[currentFormation] or {}
    for _, v in ipairs(variants) do
        local isActive = v.key == currentVariant
        table.insert(variantChildren, UI.Button {
            text = v.name,
            height = 36,
            paddingLeft = 14,
            paddingRight = 14,
            backgroundColor = isActive and {212, 175, 55, 40} or Theme.COLORS.BG_SURFACE,
            borderRadius = 18,
            borderWidth = isActive and 2 or 1,
            borderColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BORDER,
            fontSize = 12,
            color = isActive and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 8,
            marginBottom = 6,
            onClick = function()
                if v.key ~= team.formationVariant then
                    team.formationVariant = v.key
                    AIManager.rearrangeForFormation(gameState, team)
                end
                refresh()
            end,
        })
    end

    -- 当前变体描述
    local activeVariant = Constants.getVariant(currentFormation, currentVariant)
    local variantDesc = activeVariant and activeVariant.desc or ""

    -- 打法按钮
    local styleChildren = {}
    for _, style in ipairs(Constants.PLAY_STYLES) do
        local isActive = style == currentPlayStyle
        local displayName = Constants.PLAY_STYLE_NAMES[style] or style
        table.insert(styleChildren, UI.Button {
            text = displayName,
            width = "30%",
            height = 42,
            backgroundColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            borderWidth = isActive and 0 or 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 8,
            onClick = function()
                team.playStyle = style
                refresh()
            end,
        })
    end

    -- 球场视图
    local pitchView = Tactics._buildPitchView(gameState, team, currentFormation)

    return {
        -- 阵型选择
        Theme.Card {
            children = {
                Theme.Subtitle { text = "阵型" },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    justifyContent = "space-between",
                    children = formationChildren,
                },
            }
        },

        -- 变体选择
        Theme.Card {
            children = {
                Theme.Subtitle { text = currentFormation .. " 变体" },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    children = variantChildren,
                },
                variantDesc ~= "" and UI.Label {
                    text = variantDesc,
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 4,
                } or nil,
            }
        },

        -- 球场可视化
        pitchView,

        -- 打法选择
        Theme.Card {
            children = {
                Theme.Subtitle { text = "比赛风格" },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    justifyContent = "space-between",
                    children = styleChildren,
                },
            }
        },

        -- 首发列表
        Tactics._buildStartingXICard(gameState, team),
    }
end

function Tactics._buildFormationContent(gameState, team, isNTMode)
    local items = _buildFormationChildren(gameState, team, isNTMode)
    -- 返回单一 Panel 包裹，ScrollView 只有一个直接子节点
    -- 避免 UpdateContentSize 递归进入绝对定位子元素导致高度计算异常
    return { UI.Panel { width = "100%", children = items } }
end

-- 球场视图: 用 UI 面板模拟球场+球员点位（点击可换人）
-- 风格 → 各位置组的箭头方向 (dx, dy) 和颜色
local STYLE_ARROWS = {
    Attacking = {
        GK = nil, DEF = { 0, -1 }, MID = { 0, -1 }, FWD = { 0, -1 },
        color = {255, 120, 80, 180}, label = "全员压上 · 射门机会↑ 体力消耗↑",
    },
    Defensive = {
        GK = nil, DEF = { 0, 1 }, MID = { 0, 1 }, FWD = nil,
        color = {100, 180, 255, 180}, label = "退守低位 · 防守↑ 体力消耗↓↓",
    },
    Possession = {
        GK = nil, DEF = nil, MID = { 0, 0 }, FWD = { 0, 1 },
        color = {150, 220, 120, 180}, label = "控球转移 · 控球率↑ 体力消耗↓",
    },
    Counter = {
        GK = nil, DEF = { 0, 1 }, MID = nil, FWD = { 0, -1 },
        color = {255, 220, 80, 180}, label = "防守反击 · 反击↑ 节奏↑",
    },
    HighPress = {
        GK = nil, DEF = { 0, -1 }, MID = { 0, -1 }, FWD = { 0, -1 },
        color = {255, 80, 200, 180}, label = "高位逼抢 · 压迫↑↑ 体力消耗↑↑",
    },
    Balanced = {
        color = {200, 200, 200, 120}, label = "均衡策略 · 攻守平衡",
    },
}

-- 位置颜色统一使用 Theme.posColor()

function Tactics._buildPitchView(gameState, team, formation)
    local variantKey = team.formationVariant
    local positions = getFormationPositions(formation, variantKey)
    local startingXI = team.startingXI or {}
    local slots = AIManager._getFormationSlots(formation, variantKey)
    local pitchW = 340
    local pitchH = 460
    local playStyle = team.playStyle or "Balanced"
    local arrowDef = STYLE_ARROWS[playStyle] or STYLE_ARROWS.Balanced

    -- 球员点位
    local dots = {}
    local slotRoles = team.slotRoles or {}
    for i, pos in ipairs(positions) do
        local px = pos[1]
        local py = pos[2]

        -- 应用角色站位偏移
        local roleKey = slotRoles[i]
        if roleKey and roleKey ~= "default" then
            local slotPos = slots[i]
            local role = Constants.getPositionRole(slotPos, roleKey)
            if role and role.posOffset then
                px = px + role.posOffset[1]
                py = py + role.posOffset[2]
                -- 限制在合理范围
                px = math.max(2, math.min(98, px))
                py = math.max(2, math.min(98, py))
            end
        end

        -- 换算成绝对像素偏移 (基于pitchW/pitchH)
        local left = math.floor((100 - px) / 100 * pitchW) - 16  -- 镜像x轴：px小=右侧(RM), px大=左侧(LM)
        local top = math.floor((100 - py) / 100 * pitchH) - 16 - 12 -- 翻转y，顶部=进攻端；-12补偿内嵌箭头高度

        local player = startingXI[i] and gameState.players[startingXI[i]]
        local label = player and (string.sub(player.displayName, 1, 6)) or tostring(i)
        local slotPos = slots[i] or "CM"
        local dotColor = Theme.posColor(slotPos)
        local slotIdx = i

        -- 检查是否有角色设定
        local hasRole = roleKey and roleKey ~= "default"

        -- 确定位置组用于箭头
        local group = "MID"
        if slotPos == "GK" then group = "GK"
        elseif slotPos == "CB" or slotPos == "LB" or slotPos == "RB" then group = "DEF"
        elseif slotPos == "ST" or slotPos == "CF" or slotPos == "LW" or slotPos == "RW" then group = "FWD"
        end

        -- 风格箭头指示
        local arrowDir = arrowDef[group]
        local arrowLabel = nil
        if arrowDir then
            local dy = arrowDir[2]
            if dy == -1 then arrowLabel = "▲"       -- 向上(进攻方向)
            elseif dy == 1 then arrowLabel = "▼"    -- 向下(防守方向)
            else arrowLabel = "●" end               -- 原地(控球)
        end

        -- 箭头放入球员 Panel 内部，避免独立 absolute 遮挡名字和拦截点击
        local arrowElement = nil
        if arrowLabel then
            arrowElement = UI.Label {
                text = arrowLabel,
                fontSize = 9,
                color = arrowDef.color,
                textAlign = "center",
                height = 12,
            }
        end

        table.insert(dots, UI.Panel {
            position = "absolute",
            left = left,
            top = top,
            width = 40,
            alignItems = "center",
            onClick = function()
                Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots)
            end,
            children = {
                -- 风格箭头（在圆点上方）
                arrowElement or UI.Panel { height = 12 },
                -- 圆点
                UI.Panel {
                    width = 20,
                    height = 20,
                    borderRadius = 10,
                    backgroundColor = dotColor,
                    borderWidth = hasRole and 2 or 0,
                    borderColor = {255, 255, 255, 200},
                },
                -- 名字在圆点下方
                UI.Label {
                    text = label,
                    fontSize = 9,
                    color = {255, 255, 255, 230},
                    textAlign = "center",
                    marginTop = 2,
                },
            },
        })
    end

    -- 球场线条 (中线、中圈用面板模拟)
    local fieldLines = {
        -- 中线
        UI.Panel {
            position = "absolute",
            left = 0,
            top = math.floor(pitchH / 2) - 1,
            width = pitchW,
            height = 1,
            backgroundColor = {255, 255, 255, 50},
        },
        -- 中圈
        UI.Panel {
            position = "absolute",
            left = math.floor(pitchW / 2) - 30,
            top = math.floor(pitchH / 2) - 30,
            width = 60,
            height = 60,
            borderRadius = 30,
            borderWidth = 1,
            borderColor = {255, 255, 255, 50},
            backgroundColor = Theme.COLORS.TRANSPARENT,
        },
        -- 上方禁区
        UI.Panel {
            position = "absolute",
            left = math.floor(pitchW / 2) - 55,
            top = 0,
            width = 110,
            height = 60,
            borderWidth = 1,
            borderColor = {255, 255, 255, 50},
            backgroundColor = Theme.COLORS.TRANSPARENT,
        },
        -- 下方禁区
        UI.Panel {
            position = "absolute",
            left = math.floor(pitchW / 2) - 55,
            top = pitchH - 60,
            width = 110,
            height = 60,
            borderWidth = 1,
            borderColor = {255, 255, 255, 50},
            backgroundColor = Theme.COLORS.TRANSPARENT,
        },
    }

    -- 合并球场线条和球员点位
    local pitchChildren = {}
    for _, l in ipairs(fieldLines) do table.insert(pitchChildren, l) end
    for _, d in ipairs(dots) do table.insert(pitchChildren, d) end

    -- 风格效果描述
    local styleDescLabel = arrowDef.label and UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginTop = 8,
        paddingVertical = 6,
        paddingHorizontal = 10,
        borderRadius = 6,
        backgroundColor = {arrowDef.color[1], arrowDef.color[2], arrowDef.color[3], 30},
        children = {
            UI.Label {
                text = "▶",
                fontSize = 10,
                color = arrowDef.color,
                marginRight = 6,
            },
            UI.Label {
                text = arrowDef.label,
                fontSize = 11,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexShrink = 1,
            },
        },
    } or nil

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "球场视图 · " .. formation },
            UI.Label {
                text = "点击位置可更换球员",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
            },
            UI.Panel {
                width = pitchW,
                height = pitchH,
                backgroundColor = {20, 80, 40, 255},
                borderRadius = 8,
                borderWidth = 2,
                borderColor = {255, 255, 255, 60},
                alignSelf = "center",
                marginTop = 8,
                overflow = "hidden",
                children = pitchChildren,
            },
            styleDescLabel,
        }
    }
end

-- 首发列表卡片（点击可换人，卡片风格）
function Tactics._buildStartingXICard(gameState, team)
    local startingXI = team.startingXI or {}
    local formation = team.formation or "4-4-2"
    local slots = AIManager._getFormationSlots(formation, team.formationVariant)

    local startingChildren = {}
    for i, pid in ipairs(startingXI) do
        local p = gameState.players[pid]
        if p then
            local slotPos = slots[i] or p.position
            local slotIdx = i

            -- 位置颜色（统一）
            local posColor = Theme.posColor(slotPos)

            local posFullName = Constants.POSITION_NAMES[slotPos] or slotPos

            -- 角色标签（所有位置都展示）
            local slotRoles = team.slotRoles or {}
            local roleKey = slotRoles[slotIdx] or "default"
            local roleLabel = nil
            local roleData = Constants.getPositionRole(slotPos, roleKey)
            if roleData then roleLabel = roleData.name end

            table.insert(startingChildren, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                paddingTop = 7, paddingBottom = 7,
                borderBottomWidth = (i < #startingXI) and 1 or 0,
                borderColor = Theme.COLORS.BORDER,
                onClick = function()
                    Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots)
                end,
                children = {
                    -- 序号
                    UI.Label {
                        text = tostring(i),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        width = 20,
                    },
                    -- 位置徽章
                    UI.Panel {
                        backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                        borderRadius = 3,
                        paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                        marginRight = 6,
                        children = {
                            UI.Label { text = posFullName, fontSize = 10, color = posColor, fontWeight = "bold" },
                        },
                    },
                    -- 角色标签
                    roleLabel and UI.Panel {
                        backgroundColor = (roleKey ~= "default") and {212, 175, 55, 25} or {255, 255, 255, 10},
                        borderRadius = 3,
                        paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                        marginRight = 6,
                        children = {
                            UI.Label {
                                text = roleLabel, fontSize = 9,
                                color = (roleKey ~= "default") and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
                            },
                        },
                    } or nil,
                    -- 球员姓名
                    UI.Label {
                        text = p.displayName,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    -- 能力值
                    UI.Label {
                        text = tostring(p.overall),
                        fontSize = 14,
                        color = p.overall >= 70 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_SECONDARY,
                        width = 28,
                        fontWeight = "bold",
                        textAlign = "right",
                    },
                }
            })
        end
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "首发11人 (" .. #startingXI .. "/11)" },
            UI.Label {
                text = "点击球员或球场位置可更换首发",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2, marginBottom = 4,
            },
            UI.Panel {
                width = "100%",
                marginTop = 6,
                children = startingChildren,
            },
        }
    }
end

---------------------------------------------------------------------------
-- 球场点击换人：点击某个位置弹出候选列表
---------------------------------------------------------------------------
function Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots)
    local startingXI = team.startingXI or {}
    local currentPid = startingXI[slotIdx]
    local currentPlayer = currentPid and gameState.players[currentPid]
    local slotPos = slots[slotIdx] or "MID"

    -- 国家队模式判断
    local isNTMode = gameState.currentRole == "national_team"
        and gameState.nationalTeamCoach ~= nil
        and gameState.worldCup ~= nil

    local function saveAfterChange()
        if isNTMode and gameState.nationalTeamCoach then
            WorldCup.saveNationalTeamSettings(gameState, gameState.nationalTeamCoach.nation, team)
        end
    end

    -- 收集候选球员：所有队内非首发球员 + 其他首发（用于位置互换）
    local benchCandidates = {}
    local swapCandidates = {}

    -- 将首发 ID 存入 set 方便查找
    local startingSet = {}
    for _, pid in ipairs(startingXI) do
        startingSet[pid] = true
    end

    -- 板凳球员（不在首发中）
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not startingSet[pid] and not p.injured and not p.suspended then
            local score = AIManager._playerPositionScore(p, slotPos)
            table.insert(benchCandidates, { player = p, score = score, source = "bench" })
        end
    end

    -- 其他首发（位置互换）
    for i, pid in ipairs(startingXI) do
        if i ~= slotIdx then
            local p = gameState.players[pid]
            if p then
                local score = AIManager._playerPositionScore(p, slotPos)
                table.insert(swapCandidates, { player = p, score = score, index = i, source = "swap" })
            end
        end
    end

    -- 按适配分排序
    table.sort(benchCandidates, function(a, b) return a.score > b.score end)
    table.sort(swapCandidates, function(a, b) return a.score > b.score end)

    -- 构建弹窗内容
    local children = {}

    -- 当前位置信息
    local posLabel = Constants.POSITION_NAMES[slotPos] or slotPos
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 10,
        children = {
            UI.Label {
                text = string.format("位置 #%d: %s", slotIdx, posLabel),
                fontSize = 14, fontWeight = "bold", color = Theme.COLORS.ACCENT, flexGrow = 1,
            },
            currentPlayer and UI.Label {
                text = "当前: " .. currentPlayer.displayName .. " (" .. currentPlayer.overall .. ")",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            } or nil,
        }
    })

    -- 角色选择区域
    local posRoles = Constants.POSITION_ROLES[slotPos]
    if posRoles and #posRoles > 1 then
        -- 确保 slotRoles 表存在
        if not team.slotRoles then team.slotRoles = {} end
        local currentRoleKey = team.slotRoles[slotIdx] or "default"

        local roleBtns = {}
        for _, role in ipairs(posRoles) do
            local isActive = role.key == currentRoleKey
            table.insert(roleBtns, UI.Button {
                text = role.name,
                height = 30,
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = isActive and {212, 175, 55, 50} or {38, 46, 71, 255},
                borderRadius = 15,
                borderWidth = isActive and 2 or 1,
                borderColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BORDER,
                fontSize = 11,
                color = isActive and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = isActive and "bold" or "normal",
                marginRight = 6, marginBottom = 4,
                onClick = function()
                    if role.key == "default" then
                        team.slotRoles[slotIdx] = nil
                    else
                        team.slotRoles[slotIdx] = role.key
                    end
                    saveAfterChange()
                    BottomSheet.close()
                    Router.replaceWith("tactics", { tab = "formation" })
                end,
            })
        end

        -- 当前角色的描述
        local activeRole = Constants.getPositionRole(slotPos, currentRoleKey)
        local roleDesc = activeRole and activeRole.desc or ""

        table.insert(children, UI.Panel {
            width = "100%", marginBottom = 10,
            children = {
                UI.Label {
                    text = "球员角色", fontSize = 12, fontWeight = "bold",
                    color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", flexWrap = "wrap",
                    children = roleBtns,
                },
                roleDesc ~= "" and UI.Label {
                    text = roleDesc, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                } or nil,
            }
        })
    end

    -- 板凳球员列表
    if #benchCandidates > 0 then
        table.insert(children, UI.Label {
            text = "替补球员", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginTop = 6, marginBottom = 4,
        })
        local maxBench = math.min(8, #benchCandidates)
        for i = 1, maxBench do
            local c = benchCandidates[i]
            local p = c.player
            local scoreColor = c.score >= 80 and Theme.COLORS.SECONDARY or (c.score >= 60 and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED)
            table.insert(children, UI.Button {
                text = string.format("%s  %s  能力%d  适配%d",
                    Constants.POSITION_NAMES[p.position] or p.position,
                    p.displayName, p.overall, math.floor(c.score)),
                width = "100%", height = 36, marginBottom = 2,
                backgroundColor = {38, 46, 71, 255}, borderRadius = 6,
                fontSize = 12, textAlign = "left", paddingLeft = 10,
                color = scoreColor,
                onClick = function()
                    -- 将该板凳球员放入 slotIdx 位置，移除原球员
                    team.startingXI[slotIdx] = p.id
                    saveAfterChange()
                    BottomSheet.close()
                    Router.replaceWith("tactics", { tab = "formation" })
                end,
            })
        end
    end

    -- 位置互换
    if #swapCandidates > 0 then
        table.insert(children, UI.Label {
            text = "位置互换（与其他首发交换）", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginTop = 10, marginBottom = 4,
        })
        local maxSwap = math.min(5, #swapCandidates)
        for i = 1, maxSwap do
            local c = swapCandidates[i]
            local p = c.player
            local otherSlotPos = slots[c.index] or "?"
            table.insert(children, UI.Button {
                text = string.format("↔ %s (%s #%d, 能力%d)",
                    p.displayName,
                    Constants.POSITION_NAMES[otherSlotPos] or otherSlotPos,
                    c.index, p.overall),
                width = "100%", height = 36, marginBottom = 2,
                backgroundColor = {50, 40, 60, 255}, borderRadius = 6,
                fontSize = 12, textAlign = "left", paddingLeft = 10,
                color = {180, 160, 220, 255},
                onClick = function()
                    -- 交换两个位置的球员
                    local tmp = team.startingXI[slotIdx]
                    team.startingXI[slotIdx] = team.startingXI[c.index]
                    team.startingXI[c.index] = tmp
                    saveAfterChange()
                    BottomSheet.close()
                    Router.replaceWith("tactics", { tab = "formation" })
                end,
            })
        end
    end

    -- 估算弹窗高度：固定部分（标题/位置信息/关闭按钮/padding）+ 各列表区域
    -- 标题 39 + 位置信息行 44 + 关闭按钮 54 + 上下 padding 32 ≈ 169
    local fixed = 169
    -- 球员角色区域（仅当该位置有多个角色可选时显示）
    if posRoles and #posRoles > 1 then
        fixed = fixed + 96  -- 标签 + 角色按钮（可能换行）+ 描述
    end
    -- 替补球员列表（含标签）
    local benchH = #benchCandidates > 0 and (26 + math.min(8, #benchCandidates) * 38) or 0
    -- 位置互换列表（含标签）
    local swapH = #swapCandidates > 0 and (26 + math.min(5, #swapCandidates) * 38) or 0
    local sheetHeight = fixed + benchH + swapH
    -- 取屏幕 85% 高度为上限
    local maxH = math.floor(graphics:GetHeight() / graphics:GetDPR() * 0.85)
    sheetHeight = math.min(sheetHeight, maxH)

    BottomSheet.showCustom({
        title = "更换球员 — " .. posLabel,
        height = sheetHeight,
        showCancel = true,
        children = children,
    })
end

---------------------------------------------------------------------------
-- 定位球人选
---------------------------------------------------------------------------
function Tactics._buildSetPieceContent(gameState, team)
    local startingXI = team.startingXI or {}

    local rows = {}
    for _, role in ipairs(SET_PIECE_ROLES) do
        local currentId = team[role.key]
        local currentPlayer = currentId and gameState.players[currentId]
        local currentName = currentPlayer and currentPlayer.displayName or "未设置"

        -- 候选球员列表（首发球员）
        local candidates = {}
        for _, pid in ipairs(startingXI) do
            local p = gameState.players[pid]
            if p then
                table.insert(candidates, p)
            end
        end

        table.insert(rows, Tactics._buildRoleAssignRow(role, currentName, currentId, candidates, team))
    end

    return {
        Theme.Card {
            children = {
                Theme.Subtitle { text = "定位球角色分配" },
                UI.Label {
                    text = "点击球员名切换人选（从首发中选择）",
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginBottom = 10,
                },
                UI.Panel {
                    width = "100%",
                    children = rows,
                },
            }
        },
    }
end

-- 单个角色分配行，点击可切换人选
function Tactics._buildRoleAssignRow(role, currentName, currentId, candidates, team)
    return UI.Panel {
        width = "100%",
        height = 52,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 10,
        paddingRight = 10,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 图标
            UI.Label {
                text = role.icon,
                fontSize = 18,
                width = 30,
            },
            -- 角色名
            UI.Label {
                text = role.label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                width = 72,
            },
            -- 当前人选（可点击切换）
            UI.Button {
                text = currentName,
                flexGrow = 1,
                height = 36,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 8,
                fontSize = 13,
                color = Theme.COLORS.TEXT_PRIMARY,
                textAlign = "left",
                paddingLeft = 10,
                onClick = function()
                    -- 循环切换到下一个首发球员
                    if #candidates == 0 then return end
                    local nextIdx = 1
                    for i, c in ipairs(candidates) do
                        if c.id == currentId then
                            nextIdx = (i % #candidates) + 1
                            break
                        end
                    end
                    team[role.key] = candidates[nextIdx].id
                    Router.replaceWith("tactics", { tab = "setpiece" })
                end,
            },
            -- 切换提示
            UI.Label {
                text = "▶",
                fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED,
                width = 20,
                textAlign = "center",
            },
        }
    }
end

return Tactics
