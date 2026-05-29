-- ui/screens/tactics.lua
-- 战术设置页面 - 含球场视图和定位球角色分配

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local AIManager = require("scripts/systems/ai_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local Tactics = {}

---@type string
local _activeTab = "formation" -- formation | setpiece

-- 阵型位置坐标映射 (x%, y% 从球场左下角计算, x=横向0-100, y=纵向0-100从底到顶)
local FORMATION_POSITIONS = {
    ["4-4-2"] = {
        {50, 5},   -- GK
        {15, 25}, {38, 28}, {62, 28}, {85, 25}, -- DEF
        {15, 52}, {38, 55}, {62, 55}, {85, 52}, -- MID
        {35, 80}, {65, 80},                      -- FWD
    },
    ["4-3-3"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {30, 52}, {50, 55}, {70, 52},
        {20, 80}, {50, 82}, {80, 80},
    },
    ["3-5-2"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 58}, {67, 55}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["4-2-3-1"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 48}, {65, 48},
        {20, 68}, {50, 70}, {80, 68},
        {50, 85},
    },
    ["5-3-2"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {50, 55}, {70, 52},
        {35, 80}, {65, 80},
    },
    ["4-5-1"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 55}, {50, 58}, {67, 55}, {85, 50},
        {50, 82},
    },
}

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

    local team = gameState:getPlayerTeam()
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
        content = Tactics._buildFormationContent(gameState, team)
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

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = content,
            },

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
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
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
function Tactics._buildFormationContent(gameState, team)
    local currentFormation = team.formation or "4-4-2"
    local currentPlayStyle = team.playStyle or "Balanced"

    -- 阵型按钮
    local formationChildren = {}
    for _, fmt in ipairs(Constants.FORMATIONS) do
        local isActive = fmt == currentFormation
        table.insert(formationChildren, UI.Button {
            text = fmt,
            width = "30%",
            height = 42,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_CARD,
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
                    AIManager.rearrangeForFormation(gameState, team)
                end
                Router.replaceWith("tactics", { tab = "formation" })
            end,
        })
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
                Router.replaceWith("tactics", { tab = "formation" })
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

-- 球场视图: 用 UI 面板模拟球场+球员点位（点击可换人）
function Tactics._buildPitchView(gameState, team, formation)
    local positions = FORMATION_POSITIONS[formation] or FORMATION_POSITIONS["4-4-2"]
    local startingXI = team.startingXI or {}
    local slots = AIManager._getFormationSlots(formation)
    local pitchW = 300
    local pitchH = 420

    -- 球员点位
    local dots = {}
    for i, pos in ipairs(positions) do
        local px = pos[1]
        local py = pos[2]
        -- 换算成绝对像素偏移 (基于pitchW/pitchH)
        local left = math.floor(px / 100 * pitchW) - 16
        local top = math.floor((100 - py) / 100 * pitchH) - 16 -- 翻转y，顶部=进攻端

        local player = startingXI[i] and gameState.players[startingXI[i]]
        local label = player and (string.sub(player.displayName, 1, 6)) or tostring(i)
        local dotColor = i == 1 and {255, 204, 0, 255} or Theme.COLORS.PRIMARY
        local slotIdx = i

        table.insert(dots, UI.Panel {
            position = "absolute",
            left = left,
            top = top,
            width = 32,
            height = 32,
            borderRadius = 16,
            backgroundColor = dotColor,
            justifyContent = "center",
            alignItems = "center",
            onClick = function()
                Tactics._showSlotSwapSheet(gameState, team, slotIdx, slots)
            end,
            children = {
                UI.Label {
                    text = label,
                    fontSize = 8,
                    color = {255, 255, 255, 255},
                    textAlign = "center",
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
                children = pitchChildren,
            },
        }
    }
end

-- 首发列表卡片（点击可换人，卡片风格）
function Tactics._buildStartingXICard(gameState, team)
    local startingXI = team.startingXI or {}
    local formation = team.formation or "4-4-2"
    local slots = AIManager._getFormationSlots(formation)

    -- 位置分类映射
    local POS_GROUP_MAP = {
        GK = "GK", CB = "DEF", LB = "DEF", RB = "DEF",
        CDM = "MID", CM = "MID", LM = "MID", RM = "MID", CAM = "MID",
        LW = "FWD", RW = "FWD", ST = "FWD", CF = "FWD",
    }

    local startingChildren = {}
    for i, pid in ipairs(startingXI) do
        local p = gameState.players[pid]
        if p then
            local slotPos = slots[i] or p.position
            local slotIdx = i

            -- 位置颜色
            local posColor = Theme.COLORS.TEXT_SECONDARY
            local group = POS_GROUP_MAP[slotPos]
            if group == "GK" then posColor = {255, 204, 0, 255}
            elseif group == "DEF" then posColor = {77, 179, 255, 255}
            elseif group == "MID" then posColor = {102, 255, 128, 255}
            elseif group == "FWD" then posColor = {255, 102, 102, 255}
            end

            local posFullName = Constants.POSITION_NAMES[slotPos] or slotPos

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
                        backgroundColor = {posColor[1], posColor[2], posColor[3], 30},
                        borderRadius = 3,
                        paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                        marginRight = 8,
                        children = {
                            UI.Label { text = posFullName, fontSize = 10, color = posColor, fontWeight = "bold" },
                        },
                    },
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
                    BottomSheet.close()
                    Router.replaceWith("tactics", { tab = "formation" })
                end,
            })
        end
    end

    local sheetHeight = 120 + math.min(8, #benchCandidates) * 38 + math.min(5, #swapCandidates) * 38 + 60
    sheetHeight = math.min(sheetHeight, 600)

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
