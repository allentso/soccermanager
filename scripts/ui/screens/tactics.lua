-- ui/screens/tactics.lua
-- 战术设置页面 - 含球场视图

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local AIManager = require("scripts/systems/ai_manager")
local FormationShape = require("scripts/match/formation_shape")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local WorldCup = require("scripts/systems/world_cup")
local Team = require("scripts/domain/team")

local Tactics = {}

local function _isNationalTeamMode(gameState)
    return gameState.currentRole == "national_team"
        and gameState.nationalTeamCoach ~= nil
        and (gameState.worldCup ~= nil or gameState.euroCup ~= nil)
end

local function _saveTeamSettings(gameState, team)
    if _isNationalTeamMode(gameState) and gameState.nationalTeamCoach then
        WorldCup.saveNationalTeamSettings(gameState, gameState.nationalTeamCoach.nation, team)
    else
        Team.saveActiveLineupPreset(team)
    end
end

---@type string
local _activeTab = "formation" -- formation | bench

-- 局部 ScrollView 引用，用于局部刷新避免整页重建
---@type any
local _formationScrollView = nil

--- 体力颜色与展示组件（与比赛换人面板一致：名字下方长条 + 百分比）
local function _fitnessColor(fitness)
    if fitness >= 80 then return Theme.COLORS.SECONDARY
    elseif fitness >= 60 then return Theme.COLORS.WARNING
    else return Theme.COLORS.DANGER end
end

local function _buildFitnessNameColumn(displayName, fitness)
    local fitnessColor = _fitnessColor(fitness)
    local barWidthPct = math.max(5, math.min(100, math.floor(fitness)))
    return UI.Panel {
        flexGrow = 1, flexShrink = 1,
        children = {
            UI.Label { text = displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
            UI.Panel {
                width = "100%", height = 4, backgroundColor = {40, 45, 60, 255},
                borderRadius = 2, marginTop = 3,
                children = {
                    UI.Panel {
                        width = tostring(barWidthPct) .. "%", height = 4,
                        backgroundColor = fitnessColor, borderRadius = 2,
                    },
                }
            },
        }
    }
end

local function _buildFitnessPctLabel(fitness)
    return UI.Label {
        text = string.format("%.0f%%", fitness),
        fontSize = 11,
        color = _fitnessColor(fitness),
        fontWeight = "bold",
        width = 36,
        textAlign = "right",
        marginRight = 4,
    }
end

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
    local isNTMode = _isNationalTeamMode(gameState)

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
        _activeTab = params.tab == "setpiece" and "formation" or params.tab
    end

    local content
    if _activeTab == "bench" then
        content = Tactics._buildBenchContent(gameState, team)
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
        { key = "bench",     label = "替补席" },
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
    FormationShape.normalizeFormationVariant(team)
    local currentLayout = team.formationVariant

    -- 保存当前战术设置：国家队写入国家队配置，俱乐部写入当前 A/B 方案
    local function saveNTSettings()
        _saveTeamSettings(gameState, team)
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

    local function applyWithCustomizationConfirm(applyFn, title)
        if FormationShape.hasCustomization(team) then
            ConfirmDialog.show({
                title = title or "切换战术模板",
                message = "将清除自定义位置与站位微调，是否继续？",
                confirmText = "继续切换",
                cancelText = "保留当前",
                onConfirm = function()
                    FormationShape.clearCustomization(team)
                    applyFn()
                    refresh()
                end,
            })
        else
            applyFn()
            refresh()
        end
    end

    -- 阵型按钮
    local formationChildren = {}
    for _, fmt in ipairs(Constants.FORMATIONS) do
        local isActive = fmt == currentFormation
        table.insert(formationChildren, UI.Button {
            text = fmt,
            width = "31%",
            height = 34,
            backgroundColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BG_CARD,
            borderRadius = 6,
            borderWidth = isActive and 0 or 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 6,
            onClick = function()
                if fmt == team.formation then return end
                applyWithCustomizationConfirm(function()
                    team.formation = fmt
                    team.formationVariant = Constants.getDefaultVariant(fmt)
                    AIManager.rearrangeForFormation(gameState, team)
                end, "切换阵型")
            end,
        })
    end

    -- 中场布局预设（平行/菱形等；与阵型按钮分离）
    local layoutChildren = {}
    local layoutOptions = FormationShape.getLayoutOptions(currentFormation)
    for _, layoutKey in ipairs(layoutOptions) do
        local meta = Constants.getLayoutMeta(layoutKey) or {}
        local isActive = layoutKey == currentLayout
        table.insert(layoutChildren, UI.Button {
            text = meta.name or layoutKey,
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
                if layoutKey == team.formationVariant then return end
                applyWithCustomizationConfirm(function()
                    FormationShape.applyLayoutPreset(team, layoutKey)
                    AIManager.rearrangeForFormation(gameState, team)
                end, "切换中场布局")
            end,
        })
    end

    local activeLayout = Constants.getVariant(currentFormation, currentLayout)
    local layoutDesc = activeLayout and activeLayout.desc or ""
    local liveShape = FormationShape.analyze(team)
    if liveShape.alignedWithFormation == false then
        layoutDesc = layoutDesc .. " · ⚠ 实战结构：" .. (liveShape.structure and liveShape.structure.label or "未知")
    end

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

    local result = {}

    -- 阵型选择
    table.insert(result, Theme.Card {
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
    })

    -- 中场布局（多选项时显示；单模板阵型如 4-2-4 隐藏）
    if #layoutOptions > 1 then
        table.insert(result, Theme.Card {
            children = {
                Theme.Subtitle { text = "中场布局" },
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    children = layoutChildren,
                },
                layoutDesc ~= "" and UI.Label {
                    text = layoutDesc,
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 4,
                } or nil,
            }
        })
    end

    -- 球场可视化
    table.insert(result, pitchView)

    -- 打法选择
    table.insert(result, Theme.Card {
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
    })

    -- 首发列表
    table.insert(result, Tactics._buildStartingXICard(gameState, team))

    -- 定位球主罚
    table.insert(result, Tactics._buildSetPieceCard(gameState, team, isNTMode))

    return result
end

---------------------------------------------------------------------------
-- 定位球主罚卡片
---------------------------------------------------------------------------

local SET_PIECE_KINDS = {
    { kind = "penalty",   field = "penaltyTaker",  label = "点球" },
    { kind = "free_kick", field = "freeKickTaker", label = "任意球" },
    { kind = "corner",    field = "cornerTaker",   label = "角球" },
}

function Tactics._buildSetPieceCard(gameState, team, isNTMode)
    local SetPieceResolver = require("scripts/match/set_piece_resolver")

    local function saveNTSettings()
        if isNTMode and gameState.nationalTeamCoach then
            WorldCup.saveNationalTeamSettings(gameState, gameState.nationalTeamCoach.nation, team)
        end
    end

    local rows = {}
    for idx, entry in ipairs(SET_PIECE_KINDS) do
        local takerId = team[entry.field]
        local taker = takerId and gameState.players[takerId]
        local takerText
        if taker then
            takerText = string.format("%s (%.0f)", taker.displayName,
                SetPieceResolver.synthSkill(taker, entry.kind))
        else
            takerText = "自动（能力最佳者）"
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 8, paddingBottom = 8,
            borderBottomWidth = (idx < #SET_PIECE_KINDS) and 1 or 0,
            borderColor = Theme.COLORS.BORDER,
            onClick = function()
                Tactics._showSetPieceTakerSheet(gameState, team, entry, saveNTSettings)
            end,
            children = {
                UI.Label {
                    text = entry.label, fontSize = 13, fontWeight = "bold",
                    color = Theme.COLORS.TEXT_SECONDARY, width = 64,
                },
                UI.Label {
                    text = takerText, fontSize = 13,
                    color = taker and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                    flexGrow = 1,
                },
                UI.Label {
                    text = ">", fontSize = 13, color = Theme.COLORS.TEXT_MUTED,
                },
            },
        })
    end

    return Theme.Card {
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    Theme.Subtitle { text = "定位球主罚" },
                    UI.Panel { flexGrow = 1 },
                    UI.Button {
                        text = "自动分配",
                        height = 28, paddingLeft = 12, paddingRight = 12,
                        backgroundColor = Theme.COLORS.BG_SURFACE,
                        borderRadius = 14, borderWidth = 1,
                        borderColor = Theme.COLORS.BORDER,
                        fontSize = 11, color = Theme.COLORS.ACCENT,
                        onClick = function()
                            SetPieceResolver.autoAssign(gameState, team)
                            saveNTSettings()
                            Router.replaceWith("tactics", { tab = "formation" })
                        end,
                    },
                },
            },
            UI.Label {
                text = "未指定时比赛中按合成能力自动选择主罚人",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2, marginBottom = 4,
            },
            UI.Panel { width = "100%", children = rows },
        },
    }
end

--- 选择某类定位球主罚人（首发 + 替补，按合成能力排序）
function Tactics._showSetPieceTakerSheet(gameState, team, entry, saveNTSettings)
    local SetPieceResolver = require("scripts/match/set_piece_resolver")

    local candidates = {}
    local seen = {}
    local function addCandidate(pid)
        local p = gameState.players[pid]
        if p and not seen[p.id] and not p.injured and not p.retired
            and p.position ~= "GK" then
            seen[p.id] = true
            table.insert(candidates, {
                player = p,
                score = SetPieceResolver.synthSkill(p, entry.kind),
            })
        end
    end
    for _, pid in pairs(team.startingXI or {}) do addCandidate(pid) end
    for _, pid in pairs(team.benchIds or {}) do addCandidate(pid) end
    table.sort(candidates, function(a, b) return a.score > b.score end)

    local children = {}

    -- 「自动」选项
    table.insert(children, UI.Button {
        text = "自动（比赛中选能力最佳者）",
        width = "100%", height = 36, marginBottom = 6,
        backgroundColor = {38, 46, 71, 255}, borderRadius = 6,
        fontSize = 12, textAlign = "left", paddingLeft = 10,
        color = Theme.COLORS.TEXT_SECONDARY,
        onClick = function()
            team[entry.field] = nil
            saveNTSettings()
            BottomSheet.close()
            Router.replaceWith("tactics", { tab = "formation" })
        end,
    })

    local maxShown = math.min(10, #candidates)
    for i = 1, maxShown do
        local c = candidates[i]
        local p = c.player
        local isCurrent = team[entry.field] == p.id
        local traitTag = ""
        local Player = require("scripts/domain/player")
        if Player.hasTrait(p, "dead_ball") then traitTag = " [定位球专家]" end
        table.insert(children, UI.Button {
            text = string.format("%s %s  能力%.0f%s",
                Constants.POSITION_NAMES[p.position] or p.position,
                p.displayName, c.score, traitTag),
            width = "100%", height = 36, marginBottom = 2,
            backgroundColor = isCurrent and {212, 175, 55, 40} or {38, 46, 71, 255},
            borderRadius = 6,
            borderWidth = isCurrent and 1 or 0,
            borderColor = Theme.COLORS.ACCENT,
            fontSize = 12, textAlign = "left", paddingLeft = 10,
            color = isCurrent and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_PRIMARY,
            onClick = function()
                team[entry.field] = p.id
                saveNTSettings()
                BottomSheet.close()
                Router.replaceWith("tactics", { tab = "formation" })
            end,
        })
    end

    local sheetHeight = math.min(169 + 42 + maxShown * 38,
        math.floor(graphics:GetHeight() / graphics:GetDPR() * 0.85))
    BottomSheet.showCustom({
        title = "选择主罚 — " .. entry.label,
        height = sheetHeight,
        showCancel = true,
        children = children,
    })
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
    local startingXI = team.startingXI or {}
    local slots = FormationShape.getFormationSlots(team)
    local pitchW = 340
    local pitchH = 460
    local playStyle = team.playStyle or "Balanced"
    local arrowDef = STYLE_ARROWS[playStyle] or STYLE_ARROWS.Balanced
    local shapeAnalysis = FormationShape.analyze(team)

    local function coordToLeft(px)
        return math.floor((100 - px) / 100 * pitchW)
    end
    local function coordToTop(py)
        return math.floor((100 - py) / 100 * pitchH)
    end

    -- 球员点位
    local dots = {}
    local slotRoles = team.slotRoles or {}
    for i = 1, 11 do
        local px, py, slotPos = FormationShape.getSlotCoords(team, i)
        local left = coordToLeft(px) - 16
        local top = coordToTop(py) - 16 - 12

        local player = startingXI[i] and gameState.players[startingXI[i]]
        local label
        if player then
            local displayLabel = player.shortName or player.lastName or ""
            if displayLabel == "" or displayLabel == player.displayName then
                local dn = player.displayName or ""
                displayLabel = dn:match("·(.+)$") or dn
                if displayLabel == dn and player.match_name and player.match_name ~= "" then
                    displayLabel = player.match_name:match("%s(.+)$") or player.match_name
                end
            end
            local chars = 0
            local byteIdx = 1
            while byteIdx <= #displayLabel and chars < 5 do
                local b = displayLabel:byte(byteIdx)
                if b < 128 then byteIdx = byteIdx + 1
                elseif b < 224 then byteIdx = byteIdx + 2
                elseif b < 240 then byteIdx = byteIdx + 3
                else byteIdx = byteIdx + 4 end
                chars = chars + 1
            end
            label = displayLabel:sub(1, byteIdx - 1)
        else
            label = tostring(i)
        end
        slotPos = slotPos or slots[i] or "CM"
        local dotColor = Theme.posColor(slotPos)
        local slotIdx = i
        local roleKey = slotRoles[i]
        local hasRole = roleKey and roleKey ~= "default"
        local hasCustomOffset = team.slotOffsets and team.slotOffsets[slotIdx]
        local defaultPos = FormationShape.getDefaultSlotPosition(team, slotIdx)
        local hasCustomPos = slotPos ~= defaultPos

        local group = "MID"
        if slotPos == "GK" then group = "GK"
        elseif slotPos == "CB" or slotPos == "LB" or slotPos == "RB" then group = "DEF"
        elseif slotPos == "ST" or slotPos == "LW" or slotPos == "RW" then group = "FWD"
        end

        local arrowDir = arrowDef[group]
        local arrowLabel = nil
        if arrowDir then
            local dy = arrowDir[2]
            if dy == -1 then arrowLabel = "▲"
            elseif dy == 1 then arrowLabel = "▼"
            else arrowLabel = "●" end
        end

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
                arrowElement or UI.Panel { height = 12 },
                UI.Panel {
                    width = 20,
                    height = 20,
                    borderRadius = 10,
                    backgroundColor = dotColor,
                    borderWidth = (hasRole or hasCustomOffset or hasCustomPos) and 2 or 0,
                    borderColor = (hasCustomOffset or hasCustomPos) and {255, 220, 80, 220} or {255, 255, 255, 200},
                },
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

    -- 九区网格线
    local zoneLines = {
        UI.Panel { position = "absolute", left = 0, top = coordToTop(62), width = pitchW, height = 1, backgroundColor = {255, 255, 255, 35} },
        UI.Panel { position = "absolute", left = 0, top = coordToTop(36), width = pitchW, height = 1, backgroundColor = {255, 255, 255, 35} },
        UI.Panel { position = "absolute", left = coordToLeft(68), top = 0, width = 1, height = pitchH, backgroundColor = {255, 255, 255, 28} },
        UI.Panel { position = "absolute", left = coordToLeft(32), top = 0, width = 1, height = pitchH, backgroundColor = {255, 255, 255, 28} },

    }

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
    for _, l in ipairs(zoneLines) do table.insert(pitchChildren, l) end
    for _, l in ipairs(fieldLines) do table.insert(pitchChildren, l) end
    for _, d in ipairs(dots) do table.insert(pitchChildren, d) end

    -- 形态效果描述（变体 + 区域密度）
    local shapeEffectChildren = {}
    for _, line in ipairs(shapeAnalysis.effectLines or {}) do
        table.insert(shapeEffectChildren, UI.Label {
            text = "· " .. line,
            fontSize = 10,
            color = Theme.COLORS.TEXT_MUTED,
            marginBottom = 2,
        })
    end
    local shapeDescLabel = #shapeEffectChildren > 0 and UI.Panel {
        width = "100%",
        marginTop = 6,
        paddingVertical = 6,
        paddingHorizontal = 10,
        borderRadius = 6,
        backgroundColor = {80, 140, 200, 25},
        children = {
            UI.Label {
                text = "阵容形态效果",
                fontSize = 11,
                fontWeight = "bold",
                color = {120, 180, 255, 220},
                marginBottom = 4,
            },
            UI.Panel { width = "100%", children = shapeEffectChildren },
        },
    } or nil

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
                text = "点击球员可换人/改位置/设角色/微调站位（金边=已自定义）",
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
    local slots = FormationShape.getFormationSlots(team)

    local startingChildren = {}
    local starterCount = 0
    for i = 1, 11 do
        local pid = startingXI[i]
        local p = pid and gameState.players[pid]
        if p then
            starterCount = starterCount + 1
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
                paddingTop = 8, paddingBottom = 8,
                borderBottomWidth = (i < 11) and 1 or 0,
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
                        paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                        marginRight = 6, minWidth = 42,
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
                    -- 球员姓名 + 体力条
                    _buildFitnessNameColumn(p.displayName, p.fitness or 100),
                    -- 体力百分比
                    _buildFitnessPctLabel(p.fitness or 100),
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
            Theme.Subtitle { text = "首发11人 (" .. starterCount .. "/11)" },
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
function Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots, section)
    local startingXI = team.startingXI or {}
    local currentPid = startingXI[slotIdx]
    local currentPlayer = currentPid and gameState.players[currentPid]
    local slotPos = slots[slotIdx] or "MID"
    local shapeAnalysis = FormationShape.analyze(team)

    local function saveAfterChange()
        _saveTeamSettings(gameState, team)
    end

    -- 收集候选球员：所有队内非首发球员 + 其他首发（用于位置互换）
    local benchCandidates = {}
    local swapCandidates = {}

    -- 将首发 ID 存入 set 方便查找
    local startingSet = {}
    for i = 1, 11 do
        local pid = startingXI[i]
        if pid then startingSet[pid] = true end
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
    for i = 1, 11 do
        local pid = startingXI[i]
        if i ~= slotIdx and pid then
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

    if section ~= "position" and section ~= "bench" and section ~= "swap" then
        section = #benchCandidates > 0 and "bench" or (#swapCandidates > 0 and "swap" or "position")
    end

    local maxH = math.floor(graphics:GetHeight() / graphics:GetDPR() * 0.85)
    local rowBudget = math.max(3, math.floor((maxH - 277) / 38))
    local maxBenchShown = math.min(8, #benchCandidates, rowBudget)
    local maxSwapShown = math.min(5, #swapCandidates, rowBudget)

    -- 构建弹窗内容
    local children = {}

    local posLabel = Constants.POSITION_NAMES[slotPos] or slotPos
    local zoneKey = shapeAnalysis and shapeAnalysis.slotZones and shapeAnalysis.slotZones[slotIdx]
    local zoneLabel = zoneKey and (FormationShape.ZONE_LABELS[zoneKey] or zoneKey) or "未知区域"

    local function reopen(nextSection)
        Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots, nextSection)
    end

    local function addSectionTabs()
        local tabs = {
            { key = "position", label = "位置" },
            { key = "bench", label = string.format("替补%d", #benchCandidates) },
            { key = "swap", label = string.format("首发互换%d", #swapCandidates) },
        }
        local tabButtons = {}
        for _, tab in ipairs(tabs) do
            local isActive = section == tab.key
            table.insert(tabButtons, UI.Button {
                text = tab.label,
                flexGrow = 1,
                height = 34,
                marginRight = tab.key ~= "swap" and 6 or 0,
                backgroundColor = isActive and Theme.COLORS.ACCENT or {38, 46, 71, 255},
                borderRadius = 17,
                borderWidth = isActive and 0 or 1,
                borderColor = Theme.COLORS.BORDER,
                fontSize = 12,
                color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = isActive and "bold" or "normal",
                onClick = function()
                    if not isActive then reopen(tab.key) end
                end,
            })
        end
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            marginBottom = 12,
            children = tabButtons,
        })
    end

    local function addCloseButton()
        table.insert(children, UI.Button {
            text = "关闭",
            width = "100%", height = 44,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 14,
            color = Theme.COLORS.TEXT_MUTED,
            marginTop = 10,
            onClick = function()
                BottomSheet.close()
            end,
        })
    end

    -- 当前位置信息
    table.insert(children, UI.Panel {
        width = "100%",
        padding = 10,
        marginBottom = 10,
        backgroundColor = {20, 27, 43, 255},
        borderRadius = 10,
        borderWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Label {
                        text = string.format("位置 #%d: %s", slotIdx, posLabel),
                        fontSize = 14, fontWeight = "bold", color = Theme.COLORS.ACCENT, flexGrow = 1,
                    },
                    currentPlayer and UI.Label {
                        text = currentPlayer.displayName .. " (" .. currentPlayer.overall .. ")",
                        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                    } or nil,
                }
            },
            UI.Label {
                text = string.format("阵型 %s · 实战结构 %s · 区域 %s",
                    team.formation or "4-4-2",
                    shapeAnalysis.structure and shapeAnalysis.structure.label or "未知",
                    zoneLabel),
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
                marginTop = 6,
            },
        }
    })

    addSectionTabs()

    local posRoles = Constants.POSITION_ROLES[slotPos]

    if section == "position" then
        -- 位置选择（兼容位置）
        if slotPos ~= "GK" then
            local compatible = FormationShape.getCompatiblePositions(slotPos, zoneKey)
            local posBtns = {}
            for _, pos in ipairs(compatible) do
                local isActive = slotPos == pos
                local label = Constants.POSITION_NAMES[pos] or pos
                if currentPlayer then
                    label = string.format("%s ·适配%d", label, math.floor(AIManager._playerPositionScore(currentPlayer, pos)))
                end
                table.insert(posBtns, UI.Button {
                    text = label,
                    height = 32,
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
                        FormationShape.setSlotPosition(team, slotIdx, pos)
                        saveAfterChange()
                        BottomSheet.close()
                        Router.replaceWith("tactics", { tab = "formation" })
                    end,
                })
            end
            table.insert(children, UI.Panel {
                width = "100%", marginBottom = 10,
                children = {
                    UI.Label {
                        text = "位置选择", fontSize = 12, fontWeight = "bold",
                        color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
                    },
                    UI.Label {
                        text = "切换后识别形态将按新槽位自动更新",
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap",
                        children = posBtns,
                    },
                }
            })
        else
            table.insert(children, UI.Label {
                text = "门将位置不可切换，只能通过替补或首发互换调整人选。",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
            })
        end

        -- 角色选择区域
        if posRoles and #posRoles > 1 then
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

        -- 站位微调（改变球场区域归属，影响形态效果）
        if slotPos ~= "GK" then
            local function nudgeAndRefresh(direction)
                FormationShape.nudgeSlot(team, slotIdx, direction)
                saveAfterChange()
                BottomSheet.close()
                Router.replaceWith("tactics", { tab = "formation" })
            end
            local nudgeBtns = {
                UI.Button { text = "前移", width = "23%", height = 32, fontSize = 11, marginRight = 4, marginBottom = 4,
                    backgroundColor = {38, 46, 71, 255}, borderRadius = 6, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() nudgeAndRefresh("forward") end },
                UI.Button { text = "后移", width = "23%", height = 32, fontSize = 11, marginRight = 4, marginBottom = 4,
                    backgroundColor = {38, 46, 71, 255}, borderRadius = 6, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() nudgeAndRefresh("back") end },
            }
            local x = FormationShape.getSlotCoords(team, slotIdx)
            local isWideSlot = slotPos == "LB" or slotPos == "RB"
                or slotPos == "LM" or slotPos == "RM"
                or slotPos == "LW" or slotPos == "RW"
                or x < 32 or x > 68
            if isWideSlot then
                table.insert(nudgeBtns, UI.Button { text = "拉边", width = "23%", height = 32, fontSize = 11, marginRight = 4, marginBottom = 4,
                    backgroundColor = {38, 46, 71, 255}, borderRadius = 6, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() nudgeAndRefresh("wide") end })
                table.insert(nudgeBtns, UI.Button { text = "内收", width = "23%", height = 32, fontSize = 11, marginBottom = 4,
                    backgroundColor = {38, 46, 71, 255}, borderRadius = 6, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() nudgeAndRefresh("narrow") end })
            end
            table.insert(children, UI.Panel {
                width = "100%",
                children = {
                    UI.Label {
                        text = "站位微调 · 当前区域：" .. zoneLabel,
                        fontSize = 12, fontWeight = "bold",
                        color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap",
                        children = nudgeBtns,
                    },
                    UI.Button {
                        text = "重置此位置",
                        width = "100%", height = 30, marginTop = 4,
                        backgroundColor = {50, 50, 60, 255}, borderRadius = 6,
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        onClick = function()
                            if team.slotOffsets then team.slotOffsets[slotIdx] = nil end
                            local defaultPos = FormationShape.getDefaultSlotPosition(team, slotIdx)
                            FormationShape.setSlotPosition(team, slotIdx, defaultPos)
                            saveAfterChange()
                            BottomSheet.close()
                            Router.replaceWith("tactics", { tab = "formation" })
                        end,
                    },
                }
            })
        end
    elseif section == "bench" then
        table.insert(children, UI.Label {
            text = "替补球员", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
        })
        if #benchCandidates == 0 then
            table.insert(children, UI.Label {
                text = "没有可用替补球员。",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
            })
        else
            local maxBench = maxBenchShown
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
                        team.startingXI[slotIdx] = p.id
                        saveAfterChange()
                        BottomSheet.close()
                        Router.replaceWith("tactics", { tab = "formation" })
                    end,
                })
            end
            if #benchCandidates > maxBench then
                table.insert(children, UI.Label {
                    text = string.format("仅显示最适配的 %d 人，完整名单可在替补席页调整。", maxBench),
                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                })
            end
        end
    else
        table.insert(children, UI.Label {
            text = "位置互换（与其他首发交换）", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
        })
        if #swapCandidates == 0 then
            table.insert(children, UI.Label {
                text = "没有可互换的其他首发。",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
            })
        else
            local maxSwap = maxSwapShown
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
                        local tmp = team.startingXI[slotIdx]
                        team.startingXI[slotIdx] = team.startingXI[c.index]
                        team.startingXI[c.index] = tmp
                        saveAfterChange()
                        BottomSheet.close()
                        Router.replaceWith("tactics", { tab = "formation" })
                    end,
                })
            end
            if #swapCandidates > maxSwap then
                table.insert(children, UI.Label {
                    text = string.format("仅显示最适配的 %d 人。", maxSwap),
                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                })
            end
        end
    end

    addCloseButton()

    local contentHeight = 128  -- 当前信息 + 目录
    if section == "position" then
        contentHeight = contentHeight + (slotPos ~= "GK" and 200 or 36)
        if posRoles and #posRoles > 1 then contentHeight = contentHeight + 86 end
    elseif section == "bench" then
        contentHeight = contentHeight + 28 + math.max(1, maxBenchShown) * 38
        if #benchCandidates > maxBenchShown then contentHeight = contentHeight + 18 end
    else
        contentHeight = contentHeight + 28 + math.max(1, maxSwapShown) * 38
        if #swapCandidates > maxSwapShown then contentHeight = contentHeight + 18 end
    end
    contentHeight = contentHeight + 62  -- 关闭按钮
    local sheetHeight = math.min(maxH, contentHeight + 76)

    BottomSheet.showCustom({
        title = "更换球员 — " .. posLabel,
        height = sheetHeight,
        contentHeight = contentHeight,
        showCancel = false,
        children = children,
    })
end

---------------------------------------------------------------------------
-- 替补席选择
---------------------------------------------------------------------------

--- 获取球员所属位置组 (GK/DEF/MID/FWD)
local function _positionGroup(pos)
    for group, positions in pairs(Constants.POSITION_GROUPS) do
        for _, p in ipairs(positions) do
            if p == pos then return group end
        end
    end
    return "MID" -- 默认归为中场
end

--- 计算替补席综合评分（考虑能力值和体力）
--- 体力低于60的球员大幅降权，低于50的几乎不选
local function _benchScore(player)
    local fitness = player.fitness or 80
    local overall = player.overall or 50
    local fitnessFactor
    if fitness >= 80 then
        fitnessFactor = 1.0
    elseif fitness >= 70 then
        fitnessFactor = 0.85 + (fitness - 70) * 0.015  -- 0.85~1.0
    elseif fitness >= 60 then
        fitnessFactor = 0.65 + (fitness - 60) * 0.02   -- 0.65~0.85
    elseif fitness >= 50 then
        fitnessFactor = 0.4 + (fitness - 50) * 0.025   -- 0.4~0.65
    else
        fitnessFactor = 0.2 + (fitness / 50) * 0.2     -- 0.2~0.4
    end
    return overall * fitnessFactor
end

--- 自动选择最佳7名替补（综合能力值+体力，确保位置覆盖）
local function _autoBench(gameState, team)
    local startingSet = {}
    for _, pid in pairs(team.startingXI or {}) do
        startingSet[pid] = true
    end

    local available = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not startingSet[p.id] then
            table.insert(available, p)
        end
    end

    -- 按综合评分排序
    table.sort(available, function(a, b) return _benchScore(a) > _benchScore(b) end)

    -- 第一步：确保关键位置覆盖（至少1门将替补、1后卫、1中场/前锋）
    local selected = {}
    local selectedSet = {}

    local needGK = true
    local needDEF = true
    local needATK = true -- 中场或前锋

    for _, p in ipairs(available) do
        if #selected >= 7 then break end
        local g = _positionGroup(p.position)
        local picked = false

        if needGK and g == "GK" and (p.fitness or 80) >= 50 then
            needGK = false
            picked = true
        elseif needDEF and g == "DEF" and (p.fitness or 80) >= 50 then
            needDEF = false
            picked = true
        elseif needATK and (g == "FWD" or g == "MID") and (p.fitness or 80) >= 50 then
            needATK = false
            picked = true
        end

        if picked then
            table.insert(selected, p)
            selectedSet[p.id] = true
        end
    end

    -- 第二步：用综合评分填满剩余名额
    for _, p in ipairs(available) do
        if #selected >= 7 then break end
        if not selectedSet[p.id] then
            table.insert(selected, p)
            selectedSet[p.id] = true
        end
    end

    -- 最终按综合评分排序输出
    table.sort(selected, function(a, b) return _benchScore(a) > _benchScore(b) end)

    local ids = {}
    for _, p in ipairs(selected) do
        table.insert(ids, p.id)
    end
    return ids
end

--- 一键配置全队（首发11人 + 替补7人），综合考虑位置适配和体力
local function _autoFullSquad(gameState, team)
    local slots = AIManager._getFormationSlots(team)

    -- 收集全队可用球员（非伤病）
    local allAvailable = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured then
            table.insert(allAvailable, p)
        end
    end

    -- 贪心分配首发：对每个槽位找最佳匹配（位置适配 × 体力权重）
    local newXI = {}
    local usedIds = {}

    for _, slot in ipairs(slots) do
        local bestPlayer = nil
        local bestScore = -1

        for _, p in ipairs(allAvailable) do
            if not usedIds[p.id] then
                local posScore = AIManager._playerPositionScore(p, slot)
                -- 体力权重（与 _benchScore 类似的曲线）
                local fitness = p.fitness or 80
                local fitnessFactor
                if fitness >= 80 then
                    fitnessFactor = 1.0
                elseif fitness >= 70 then
                    fitnessFactor = 0.85 + (fitness - 70) * 0.015
                elseif fitness >= 60 then
                    fitnessFactor = 0.65 + (fitness - 60) * 0.02
                elseif fitness >= 50 then
                    fitnessFactor = 0.4 + (fitness - 50) * 0.025
                else
                    fitnessFactor = 0.2 + (fitness / 50) * 0.2
                end
                local score = posScore * fitnessFactor
                if score > bestScore then
                    bestScore = score
                    bestPlayer = p
                end
            end
        end

        if bestPlayer then
            table.insert(newXI, bestPlayer.id)
            usedIds[bestPlayer.id] = true
        end
    end

    -- 更新首发
    team.startingXI = newXI

    -- 从剩余球员中选替补（复用 _autoBench 逻辑，它会排除首发）
    team.benchIds = _autoBench(gameState, team)
end

--- 获取当前替补席球员列表（手动 or 自动）
local function _getEffectiveBench(gameState, team)
    local startingSet = {}
    for _, pid in pairs(team.startingXI or {}) do
        startingSet[pid] = true
    end

    if team.benchIds and #team.benchIds > 0 then
        local result = {}
        for _, pid in ipairs(team.benchIds) do
            local p = gameState.players[pid]
            if p and not p.injured and not startingSet[p.id] then
                table.insert(result, p)
            end
        end
        return result, true -- true = 手动模式
    end

    -- 自动模式：复用 _autoBench 的逻辑（体力+位置覆盖）
    local autoIds = _autoBench(gameState, team)
    local result = {}
    for _, pid in ipairs(autoIds) do
        local p = gameState.players[pid]
        if p then table.insert(result, p) end
    end
    return result, false -- false = 自动模式
end

function Tactics._buildBenchContent(gameState, team)
    local benchPlayers, isManual = _getEffectiveBench(gameState, team)
    local benchIdSet = {}
    for _, p in ipairs(benchPlayers) do benchIdSet[p.id] = true end

    -- 候选球员：非首发、非替补的健康球员
    local startingSet = {}
    for _, pid in pairs(team.startingXI or {}) do startingSet[pid] = true end

    local candidates = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not startingSet[p.id] and not benchIdSet[p.id] then
            table.insert(candidates, p)
        end
    end
    table.sort(candidates, function(a, b) return _benchScore(a) > _benchScore(b) end)

    -- 构建替补席行
    local benchRows = {}
    for idx, p in ipairs(benchPlayers) do
        local posColor = Theme.posColor(p.position)
        local posName = Constants.POSITION_NAMES[p.position] or p.position
        local fitness = p.fitness or 100
        table.insert(benchRows, UI.Panel {
            width = "100%",
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = (idx % 2 == 0) and {255, 255, 255, 5} or Theme.COLORS.TRANSPARENT,
            children = {
                -- 序号
                UI.Label { text = tostring(idx), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                -- 位置铭牌
                UI.Panel {
                    backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                    marginRight = 6, minWidth = 42,
                    children = {
                        UI.Label { text = posName, fontSize = 10, color = posColor, fontWeight = "bold" },
                    },
                },
                -- 名字 + 体力条
                _buildFitnessNameColumn(p.displayName or p.name, fitness),
                -- 体力百分比
                _buildFitnessPctLabel(fitness),
                -- overall
                UI.Label { text = tostring(p.overall), fontSize = 12, color = Theme.COLORS.ACCENT, fontWeight = "bold", width = 26, textAlign = "right" },
                -- 移除按钮
                UI.Button {
                    text = "✕",
                    width = 28, height = 28,
                    borderRadius = 14,
                    backgroundColor = {255, 80, 80, 30},
                    fontSize = 12,
                    color = {255, 100, 100, 255},
                    marginLeft = 8,
                    onClick = function()
                        -- 自动模式下先初始化 benchIds
                        if not team.benchIds or #team.benchIds == 0 then
                            team.benchIds = {}
                            for _, bp in ipairs(benchPlayers) do
                                table.insert(team.benchIds, bp.id)
                            end
                        end
                        -- 移除该球员
                        local newIds = {}
                        for _, bid in ipairs(team.benchIds) do
                            if bid ~= p.id then table.insert(newIds, bid) end
                        end
                        team.benchIds = newIds
                        _saveTeamSettings(gameState, team)
                        Router.replaceWith("tactics", { tab = "bench" })
                    end,
                },
            },
        })
    end

    -- 构建候选人行
    local candidateRows = {}
    for idx, p in ipairs(candidates) do
        local posColor = Theme.posColor(p.position)
        local posName = Constants.POSITION_NAMES[p.position] or p.position
        local fitness = p.fitness or 100
        table.insert(candidateRows, UI.Panel {
            width = "100%",
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = (idx % 2 == 0) and {255, 255, 255, 5} or Theme.COLORS.TRANSPARENT,
            children = {
                -- 位置铭牌
                UI.Panel {
                    backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                    marginRight = 6, minWidth = 42,
                    children = {
                        UI.Label { text = posName, fontSize = 10, color = posColor, fontWeight = "bold" },
                    },
                },
                -- 名字 + 体力条
                _buildFitnessNameColumn(p.displayName or p.name, fitness),
                -- 体力百分比
                _buildFitnessPctLabel(fitness),
                -- overall
                UI.Label { text = tostring(p.overall), fontSize = 12, color = Theme.COLORS.ACCENT, fontWeight = "bold", width = 26, textAlign = "right" },
                -- 添加按钮（名额已满则禁用）
                UI.Button {
                    text = "+",
                    width = 28, height = 28,
                    borderRadius = 14,
                    backgroundColor = (#benchPlayers < 7) and {80, 200, 120, 40} or {128, 128, 128, 20},
                    fontSize = 14,
                    color = (#benchPlayers < 7) and {80, 220, 120, 255} or Theme.COLORS.TEXT_MUTED,
                    disabled = #benchPlayers >= 7,
                    marginLeft = 8,
                    onClick = function()
                        if #(team.benchIds or {}) >= 7 then return end
                        -- 如果 benchIds 为空，先初始化已有的
                        if not team.benchIds or #team.benchIds == 0 then
                            team.benchIds = {}
                            for _, bp in ipairs(benchPlayers) do
                                table.insert(team.benchIds, bp.id)
                            end
                        end
                        table.insert(team.benchIds, p.id)
                        _saveTeamSettings(gameState, team)
                        Router.replaceWith("tactics", { tab = "bench" })
                    end,
                },
            },
        })
    end

    local modeLabel = isManual and "手动选择" or "自动（按能力值）"
    local modeColor = isManual and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_SECONDARY

    local items = {
        -- 自动模式提示
        (not isManual) and UI.Panel {
            width = "100%",
            backgroundColor = {100, 180, 255, 15},
            borderRadius = 6,
            paddingLeft = 10, paddingRight = 10, paddingTop = 6, paddingBottom = 6,
            marginBottom = 10,
            flexDirection = "row", alignItems = "center",
            children = {
                UI.Label { text = "💡", fontSize = 12, marginRight = 6 },
                UI.Label { text = "点击 ✕ 或 + 将切换为手动模式", fontSize = 11, color = {150, 200, 255, 220} },
            },
        } or UI.Panel { width = 0, height = 0 },
        -- 模式提示 + 操作按钮
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            marginBottom = 12,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Label { text = "当前模式: ", fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY },
                        UI.Label { text = modeLabel, fontSize = 12, color = modeColor, fontWeight = "bold" },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center",
                    children = {
                        -- 一键配置按钮（首发+替补全部自动配置）
                        UI.Button {
                            text = "一键配置",
                            height = 30,
                            paddingLeft = 12, paddingRight = 12,
                            backgroundColor = {Theme.COLORS.ACCENT[1], Theme.COLORS.ACCENT[2], Theme.COLORS.ACCENT[3], 40},
                            borderRadius = 15,
                            fontSize = 12,
                            color = Theme.COLORS.ACCENT,
                            marginRight = 8,
                            onClick = function()
                                _autoFullSquad(gameState, team)
                                _saveTeamSettings(gameState, team)
                                Router.replaceWith("tactics", { tab = "bench" })
                            end,
                        },
                        -- 清空（恢复自动）
                        isManual and UI.Button {
                            text = "恢复自动",
                            height = 30,
                            paddingLeft = 12, paddingRight = 12,
                            backgroundColor = {255, 255, 255, 10},
                            borderRadius = 15,
                            fontSize = 12,
                            color = Theme.COLORS.TEXT_SECONDARY,
                            onClick = function()
                                team.benchIds = {}
                                _saveTeamSettings(gameState, team)
                                Router.replaceWith("tactics", { tab = "bench" })
                            end,
                        } or UI.Panel { width = 0 },
                    },
                },
            },
        },

        -- 替补席列表标题
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            marginBottom = 6,
            children = {
                Theme.Subtitle { text = string.format("替补席 (%d/7)", #benchPlayers) },
            },
        },

        -- 替补席球员列表
        UI.Panel {
            width = "100%",
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            overflow = "hidden",
            marginBottom = 16,
            children = #benchRows > 0 and benchRows or {
                UI.Panel {
                    width = "100%", height = 60,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = "暂无替补球员", fontSize = 13, color = Theme.COLORS.TEXT_MUTED },
                    },
                },
            },
        },

        -- 候选人标题
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            marginBottom = 6,
            children = {
                Theme.Subtitle { text = string.format("可选球员 (%d)", #candidates) },
            },
        },

        -- 候选人列表
        UI.Panel {
            width = "100%",
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            overflow = "hidden",
            children = #candidateRows > 0 and candidateRows or {
                UI.Panel {
                    width = "100%", height = 60,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = "无可用球员", fontSize = 13, color = Theme.COLORS.TEXT_MUTED },
                    },
                },
            },
        },
    }

    return { UI.Panel { width = "100%", children = items } }
end

return Tactics
