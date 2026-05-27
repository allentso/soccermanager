-- ui/screens/training.lua
-- 训练管理页面 - 增强版：强度/周计划/个人训练

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")

local Training = {}

-- 训练重点选项
local TRAINING_FOCUS_OPTIONS = {
    { key = "balanced",   label = "综合训练", desc = "均衡提升全队能力", icon = "⚖" },
    { key = "attack",     label = "进攻训练", desc = "射门、盘带、传球", icon = "⚡" },
    { key = "defense",    label = "防守训练", desc = "抢断、防守、定位", icon = "🛡" },
    { key = "fitness",    label = "体能训练", desc = "速度、耐力、力量", icon = "💪" },
    { key = "technical",  label = "技术训练", desc = "盘带、传球、视野", icon = "⚽" },
    { key = "tactical",   label = "战术训练", desc = "决断、定位、配合", icon = "🧠" },
}

-- 训练强度选项
local INTENSITY_OPTIONS = {
    { key = "low",    label = "轻量", desc = "效果-50% | 恢复快 | 受伤率极低", color = Theme.COLORS.SECONDARY },
    { key = "medium", label = "均衡", desc = "标准效果 | 正常消耗", color = Theme.COLORS.ACCENT },
    { key = "high",   label = "高压", desc = "效果+50% | 消耗大 | 受伤率×2", color = Theme.COLORS.DANGER },
}

-- 周训练计划选项
local WEEKLY_PLAN_OPTIONS = {
    { key = "intensive", label = "密集训练", desc = "每天训练，体能消耗大，效果最佳" },
    { key = "balanced",  label = "均衡安排", desc = "训练+恢复交替，适合赛季中" },
    { key = "light",     label = "轻松恢复", desc = "以恢复为主，适合密集赛程期" },
}

-- 当前查看的标签
local _activeTab = "team"  -- team / individual / groups

function Training.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    local team = gameState:getPlayerTeam()
    if not team then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    if params and params.tab then _activeTab = params.tab end

    -- 当前训练设置
    local currentFocus = team.trainingFocus or "balanced"
    local currentIntensity = team.trainingIntensity or "medium"
    local currentPlan = team.weeklyPlan or "balanced"

    -- 获取球队球员
    local players = gameState:getTeamPlayers(team.id)
    local avgFitness = 0
    local injuredCount = 0
    local lowFitnessCount = 0
    for _, p in ipairs(players) do
        avgFitness = avgFitness + (p.fitness or 80)
        if p.injured then injuredCount = injuredCount + 1 end
        if p.fitness and p.fitness < 70 then lowFitnessCount = lowFitnessCount + 1 end
    end
    avgFitness = #players > 0 and math.floor(avgFitness / #players) or 0

    -- 标签栏
    local tabButtons = {}
    local tabDefs = {
        { key = "team", label = "全队训练" },
        { key = "groups", label = "分组训练" },
        { key = "individual", label = "个人训练" },
    }
    for _, t in ipairs(tabDefs) do
        local isActive = t.key == _activeTab
        table.insert(tabButtons, UI.Button {
            text = t.label,
            height = 30, paddingLeft = 16, paddingRight = 16,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 15, fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            onClick = function()
                _activeTab = t.key
                Router.replaceWith("training", { tab = t.key })
            end,
        })
    end

    -- 内容
    local content
    if _activeTab == "team" then
        content = Training._buildTeamTab(team, currentFocus, currentIntensity, currentPlan, avgFitness, injuredCount, lowFitnessCount, #players)
    elseif _activeTab == "groups" then
        content = Training._buildGroupsTab(team, players, gameState)
    else
        content = Training._buildIndividualTab(players, gameState)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "训练管理", fontSize = 17,
                        color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                        flexGrow = 1, textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- 二级导航
            Theme.SquadSubNav("training"),

            -- 训练标签
            UI.Panel {
                width = "100%", height = 42,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 12,
                children = tabButtons,
            },

            -- 内容
            UI.ScrollView {
                flexGrow = 1, flexBasis = 0, scrollY = true,
                padding = 14,
                children = { content },
            },

            Theme.MainNav("squad"),
        }
    }
end

-- 全队训练标签
function Training._buildTeamTab(team, currentFocus, currentIntensity, currentPlan, avgFitness, injuredCount, lowFitnessCount, playerCount)
    -- 状态概览
    local fitnessColor = avgFitness >= 75 and Theme.COLORS.SECONDARY
        or (avgFitness >= 60 and Theme.COLORS.WARNING or Theme.COLORS.DANGER)

    -- 训练重点按钮
    local focusButtons = {}
    for _, opt in ipairs(TRAINING_FOCUS_OPTIONS) do
        local isActive = opt.key == currentFocus
        table.insert(focusButtons, UI.Button {
            text = opt.icon .. " " .. opt.label,
            width = "48%", height = 50,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            borderWidth = isActive and 0 or 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 6,
            onClick = function()
                team.trainingFocus = opt.key
                Router.replaceWith("training", { tab = "team" })
            end,
        })
    end

    -- 强度按钮
    local intensityButtons = {}
    for _, opt in ipairs(INTENSITY_OPTIONS) do
        local isActive = opt.key == currentIntensity
        table.insert(intensityButtons, UI.Panel {
            flexGrow = 1, marginRight = 6,
            children = {
                UI.Button {
                    text = opt.label,
                    width = "100%", height = 36,
                    backgroundColor = isActive and opt.color or Theme.COLORS.BG_CARD,
                    borderRadius = 8,
                    borderWidth = isActive and 0 or 1,
                    borderColor = Theme.COLORS.BORDER,
                    fontSize = 13,
                    color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                    fontWeight = isActive and "bold" or "normal",
                    onClick = function()
                        team.trainingIntensity = opt.key
                        Router.replaceWith("training", { tab = "team" })
                    end,
                },
                UI.Label {
                    text = opt.desc,
                    fontSize = 9, color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 3, textAlign = "center",
                },
            }
        })
    end

    -- 周计划按钮
    local planButtons = {}
    for _, opt in ipairs(WEEKLY_PLAN_OPTIONS) do
        local isActive = opt.key == currentPlan
        table.insert(planButtons, UI.Button {
            text = opt.label,
            width = "100%", height = 42,
            backgroundColor = isActive and {33, 80, 130, 255} or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            borderWidth = isActive and 1 or 1,
            borderColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BORDER,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 6,
            onClick = function()
                team.weeklyPlan = opt.key
                Router.replaceWith("training", { tab = "team" })
            end,
        })
    end

    return UI.Panel {
        width = "100%",
        children = {
            -- 球队状态概览
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "球队体能状态" },
                    UI.Panel {
                        width = "100%", height = 20,
                        backgroundColor = {38, 46, 71, 255}, borderRadius = 10,
                        marginTop = 8, overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = avgFitness .. "%",
                                height = "100%",
                                backgroundColor = fitnessColor,
                                borderRadius = 10,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", marginTop = 8, flexWrap = "wrap",
                        children = {
                            Theme.StatPill { label = "平均体能", value = avgFitness .. "%", valueColor = fitnessColor },
                            Theme.StatPill { label = "伤病", value = injuredCount, valueColor = injuredCount > 0 and Theme.COLORS.DANGER or nil },
                            Theme.StatPill { label = "低体能", value = lowFitnessCount, valueColor = lowFitnessCount > 0 and Theme.COLORS.WARNING or nil },
                            Theme.StatPill { label = "球员数", value = playerCount },
                        }
                    },
                }
            },

            -- 训练重点
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "训练重点" },
                    UI.Label {
                        text = Training._getFocusDesc(currentFocus),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap",
                        justifyContent = "space-between",
                        children = focusButtons,
                    },
                }
            },

            -- 训练强度
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "训练强度" },
                    UI.Panel {
                        width = "100%", flexDirection = "row", marginTop = 8,
                        children = intensityButtons,
                    },
                }
            },

            -- 周训练计划
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "周训练计划" },
                    UI.Label {
                        text = Training._getPlanDesc(currentPlan),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                    },
                    UI.Panel { width = "100%", children = planButtons },
                }
            },
        }
    }
end

-- 个人训练标签
function Training._buildIndividualTab(players, gameState)
    -- 按位置排序
    local posOrder = {GK=1, CB=2, LB=3, RB=4, CDM=5, CM=6, LM=7, RM=8, CAM=9, LW=10, RW=11, CF=12, ST=13}
    table.sort(players, function(a, b)
        local oa = posOrder[a.position] or 99
        local ob = posOrder[b.position] or 99
        if oa ~= ob then return oa < ob end
        return a.overall > b.overall
    end)

    local INDIVIDUAL_FOCUS_OPTIONS = {
        { key = nil,         label = "跟队" },
        { key = "shooting",  label = "射门" },
        { key = "passing",   label = "传球" },
        { key = "defending", label = "防守" },
        { key = "fitness",   label = "体能" },
        { key = "dribbling", label = "盘带" },
    }

    local rows = {}
    for _, p in ipairs(players) do
        if not p.injured then
            local currentFocus = p.trainingFocus
            local focusLabel = "跟队"
            for _, opt in ipairs(INDIVIDUAL_FOCUS_OPTIONS) do
                if opt.key == currentFocus then
                    focusLabel = opt.label
                    break
                end
            end

            table.insert(rows, UI.Panel {
                width = "100%", height = 48,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label {
                        text = p.position,
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 32,
                    },
                    UI.Label {
                        text = p.displayName,
                        fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1, flexShrink = 1,
                    },
                    UI.Label {
                        text = tostring(p.overall),
                        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, width = 26,
                    },
                    UI.Button {
                        text = focusLabel,
                        width = 60, height = 28,
                        backgroundColor = currentFocus and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
                        borderRadius = 6, fontSize = 11,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            Training._showIndividualMenu(p, INDIVIDUAL_FOCUS_OPTIONS)
                        end,
                    },
                },
            })
        end
    end

    if #rows == 0 then
        table.insert(rows, UI.Label {
            text = "所有球员均受伤中",
            fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginTop = 20, textAlign = "center",
        })
    end

    return UI.Panel {
        width = "100%",
        children = {
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "个人训练分配" },
                    UI.Label {
                        text = "为每位球员设置专项训练，覆盖全队训练重点",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                    },
                    UI.Panel { width = "100%", children = rows },
                }
            },
        }
    }
end

-- 个人训练选择弹窗
function Training._showIndividualMenu(player, options)
    local menuItems = {
        UI.Label {
            text = player.displayName .. " - 个人训练",
            fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold", marginBottom = 12, textAlign = "center",
        },
    }

    for _, opt in ipairs(options) do
        local isActive = player.trainingFocus == opt.key
        table.insert(menuItems, UI.Button {
            text = (isActive and "● " or "  ") .. opt.label,
            width = "100%", height = 40,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 8, fontSize = 14,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginBottom = 4,
            onClick = function()
                player.trainingFocus = opt.key
                UI.CloseOverlay()
                Router.replaceWith("training", { tab = "individual" })
            end,
        })
    end

    table.insert(menuItems, UI.Button {
        text = "取消",
        width = "100%", height = 40,
        backgroundColor = Theme.COLORS.TRANSPARENT,
        borderWidth = 1, borderColor = Theme.COLORS.BORDER,
        borderRadius = 8, fontSize = 14, color = Theme.COLORS.TEXT_MUTED,
        marginTop = 6,
        onClick = function() UI.CloseOverlay() end,
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "flex-end",
        backgroundColor = {0, 0, 0, 150},
        onClick = function() UI.CloseOverlay() end,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderTopLeftRadius = 16, borderTopRightRadius = 16,
                padding = 20, paddingBottom = 30,
                children = menuItems,
            },
        },
    })
end

function Training._getFocusDesc(focus)
    for _, opt in ipairs(TRAINING_FOCUS_OPTIONS) do
        if opt.key == focus then return "当前: " .. opt.desc end
    end
    return ""
end

function Training._getPlanDesc(plan)
    for _, opt in ipairs(WEEKLY_PLAN_OPTIONS) do
        if opt.key == plan then return "当前: " .. opt.desc end
    end
    return ""
end

------------------------------------------------------
-- 分组训练标签
------------------------------------------------------

-- 预设分组模板
local GROUP_PRESETS = {
    { name = "进攻组", focus = "attack" },
    { name = "防守组", focus = "defense" },
    { name = "体能组", focus = "fitness" },
}

function Training._buildGroupsTab(team, players, gameState)
    local groups = team.trainingGroups or {}

    -- 统计未分组球员
    local assignedSet = {}
    for _, group in pairs(groups) do
        if group.playerIds then
            for _, pid in ipairs(group.playerIds) do
                assignedSet[pid] = true
            end
        end
    end
    local unassignedCount = 0
    for _, p in ipairs(players) do
        if not assignedSet[p.id] and not p.injured then
            unassignedCount = unassignedCount + 1
        end
    end

    -- 构建分组卡片列表
    local groupCards = {}

    -- 现有分组
    local groupNames = {}
    for name in pairs(groups) do table.insert(groupNames, name) end
    table.sort(groupNames)

    for _, gName in ipairs(groupNames) do
        local group = groups[gName]
        local focusLabel = "综合"
        for _, opt in ipairs(TRAINING_FOCUS_OPTIONS) do
            if opt.key == group.focus then focusLabel = opt.icon .. " " .. opt.label; break end
        end

        local memberLabels = {}
        local memberCount = group.playerIds and #group.playerIds or 0
        if group.playerIds then
            for i, pid in ipairs(group.playerIds) do
                if i > 4 then
                    table.insert(memberLabels, UI.Label {
                        text = "+" .. (memberCount - 4) .. "人",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                    })
                    break
                end
                local p = gameState.players[pid]
                if p then
                    table.insert(memberLabels, UI.Label {
                        text = p.displayName,
                        fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                        marginRight = 8,
                    })
                end
            end
        end

        table.insert(groupCards, Theme.Card {
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Label {
                            text = gName, fontSize = 15, fontWeight = "bold",
                            color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1,
                        },
                        UI.Label {
                            text = focusLabel, fontSize = 12,
                            color = Theme.COLORS.ACCENT,
                        },
                    }
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", flexWrap = "wrap",
                    marginTop = 6,
                    children = memberLabels,
                },
                UI.Label {
                    text = memberCount .. " 人",
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", marginTop = 8,
                    children = {
                        UI.Button {
                            text = "编辑", height = 30, paddingLeft = 12, paddingRight = 12,
                            backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 6, fontSize = 12,
                            color = Theme.COLORS.TEXT_PRIMARY, marginRight = 8,
                            onClick = function()
                                Training._showEditGroupOverlay(team, gName, players, gameState)
                            end,
                        },
                        UI.Button {
                            text = "删除", height = 30, paddingLeft = 12, paddingRight = 12,
                            backgroundColor = Theme.COLORS.DANGER, borderRadius = 6, fontSize = 12,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                team.trainingGroups[gName] = nil
                                Router.replaceWith("training", { tab = "groups" })
                            end,
                        },
                    }
                },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        children = {
            -- 说明
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "训练分组" },
                    UI.Label {
                        text = "将球员分配到不同训练组，每组可设置独立训练重点。未分组球员跟随全队训练。",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 6,
                    },
                    UI.Label {
                        text = "未分组球员: " .. unassignedCount .. " 人（跟随全队训练）",
                        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                    },
                }
            },

            -- 现有分组
            UI.Panel { width = "100%", children = groupCards },

            -- 新建分组按钮
            Theme.Card {
                children = {
                    UI.Button {
                        text = "+ 新建训练分组",
                        width = "100%", height = 44,
                        backgroundColor = {33, 80, 130, 255},
                        borderRadius = 8, fontSize = 14, fontWeight = "bold",
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            Training._showCreateGroupOverlay(team, players)
                        end,
                    },

                    -- 快速预设
                    (#groupNames == 0) and UI.Panel {
                        width = "100%", marginTop = 10,
                        children = {
                            UI.Label {
                                text = "快速预设",
                                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 6,
                            },
                            UI.Button {
                                text = "一键生成: 进攻组 / 防守组 / 体能组",
                                width = "100%", height = 36,
                                backgroundColor = Theme.COLORS.BG_CARD,
                                borderRadius = 6, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                                fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                                onClick = function()
                                    Training._applyGroupPreset(team, players)
                                    Router.replaceWith("training", { tab = "groups" })
                                end,
                            },
                        }
                    } or UI.Panel { width = 0 },
                }
            },
        }
    }
end

------------------------------------------------------
-- 快速预设：按阵容角色自动分组
------------------------------------------------------
function Training._applyGroupPreset(team, players)
    local attackGroup = { focus = "attack", playerIds = {} }
    local defenseGroup = { focus = "defense", playerIds = {} }
    local fitnessGroup = { focus = "fitness", playerIds = {} }

    local attackPos = { ST = true, CF = true, LW = true, RW = true, CAM = true }
    local defensePos = { CB = true, LB = true, RB = true, GK = true, CDM = true }

    for _, p in ipairs(players) do
        if not p.injured then
            if attackPos[p.position] then
                table.insert(attackGroup.playerIds, p.id)
            elseif defensePos[p.position] then
                table.insert(defenseGroup.playerIds, p.id)
            else
                table.insert(fitnessGroup.playerIds, p.id)
            end
        end
    end

    team.trainingGroups = {
        ["进攻组"] = attackGroup,
        ["防守组"] = defenseGroup,
        ["体能组"] = fitnessGroup,
    }
end

------------------------------------------------------
-- 新建分组弹窗
------------------------------------------------------
function Training._showCreateGroupOverlay(team, players)
    local newName = "新分组"
    local newFocus = "balanced"

    local focusBtns = {}
    for _, opt in ipairs(TRAINING_FOCUS_OPTIONS) do
        table.insert(focusBtns, UI.Button {
            text = opt.icon .. " " .. opt.label,
            width = "48%", height = 38,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 6, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
            fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
            onClick = function()
                -- 创建分组
                if not team.trainingGroups then team.trainingGroups = {} end
                -- 避免重名
                local finalName = opt.label .. "组"
                local idx = 1
                while team.trainingGroups[finalName] do
                    idx = idx + 1
                    finalName = opt.label .. "组" .. idx
                end
                team.trainingGroups[finalName] = { focus = opt.key, playerIds = {} }
                UI.CloseOverlay()
                Router.replaceWith("training", { tab = "groups" })
            end,
        })
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = {0, 0, 0, 150},
        onClick = function() UI.CloseOverlay() end,
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12, padding = 20,
                children = {
                    UI.Label {
                        text = "新建训练分组",
                        fontSize = 16, fontWeight = "bold",
                        color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 12,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "选择训练重点（将以此命名分组）：",
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap",
                        justifyContent = "space-between",
                        children = focusBtns,
                    },
                    UI.Button {
                        text = "取消", width = "100%", height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                        borderRadius = 8, fontSize = 13, color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 10,
                        onClick = function() UI.CloseOverlay() end,
                    },
                }
            },
        },
    })
end

------------------------------------------------------
-- 编辑分组弹窗（添加/移除球员 + 修改focus）
------------------------------------------------------
function Training._showEditGroupOverlay(team, groupName, players, gameState)
    local group = team.trainingGroups[groupName]
    if not group then return end

    -- 当前组内球员集合
    local inGroup = {}
    if group.playerIds then
        for _, pid in ipairs(group.playerIds) do inGroup[pid] = true end
    end

    -- 构建球员切换列表
    local playerRows = {}
    local posOrder = {GK=1, CB=2, LB=3, RB=4, CDM=5, CM=6, LM=7, RM=8, CAM=9, LW=10, RW=11, CF=12, ST=13}
    local sortedPlayers = {}
    for _, p in ipairs(players) do
        if not p.injured then table.insert(sortedPlayers, p) end
    end
    table.sort(sortedPlayers, function(a, b)
        local oa = posOrder[a.position] or 99
        local ob = posOrder[b.position] or 99
        if oa ~= ob then return oa < ob end
        return a.overall > b.overall
    end)

    for _, p in ipairs(sortedPlayers) do
        local isIn = inGroup[p.id] == true
        table.insert(playerRows, UI.Button {
            text = (isIn and "✓ " or "   ") .. p.position .. " " .. p.displayName .. " (" .. p.overall .. ")",
            width = "100%", height = 36,
            backgroundColor = isIn and {33, 80, 130, 255} or Theme.COLORS.BG_DARK,
            borderRadius = 4, fontSize = 12, marginBottom = 2,
            color = isIn and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            textAlign = "left", paddingLeft = 10,
            onClick = function()
                if isIn then
                    -- 移除
                    local newIds = {}
                    for _, pid in ipairs(group.playerIds) do
                        if pid ~= p.id then table.insert(newIds, pid) end
                    end
                    group.playerIds = newIds
                else
                    -- 添加（从其他组移除）
                    for _, g in pairs(team.trainingGroups) do
                        if g.playerIds then
                            local filtered = {}
                            for _, pid in ipairs(g.playerIds) do
                                if pid ~= p.id then table.insert(filtered, pid) end
                            end
                            g.playerIds = filtered
                        end
                    end
                    if not group.playerIds then group.playerIds = {} end
                    table.insert(group.playerIds, p.id)
                end
                UI.CloseOverlay()
                Training._showEditGroupOverlay(team, groupName, players, gameState)
            end,
        })
    end

    -- focus 选择
    local focusBtns = {}
    for _, opt in ipairs(TRAINING_FOCUS_OPTIONS) do
        local isActive = opt.key == group.focus
        table.insert(focusBtns, UI.Button {
            text = opt.icon,
            width = 36, height = 36,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_DARK,
            borderRadius = 18, fontSize = 14, marginRight = 4,
            color = Theme.COLORS.TEXT_PRIMARY,
            onClick = function()
                group.focus = opt.key
                UI.CloseOverlay()
                Training._showEditGroupOverlay(team, groupName, players, gameState)
            end,
        })
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "flex-end",
        backgroundColor = {0, 0, 0, 150},
        children = {
            UI.Panel {
                width = "100%", height = "80%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderTopLeftRadius = 16, borderTopRightRadius = 16,
                padding = 16,
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        marginBottom = 10,
                        children = {
                            UI.Label {
                                text = "编辑: " .. groupName,
                                fontSize = 16, fontWeight = "bold",
                                color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1,
                            },
                            UI.Button {
                                text = "完成", width = 60, height = 30,
                                backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 6,
                                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                                onClick = function()
                                    UI.CloseOverlay()
                                    Router.replaceWith("training", { tab = "groups" })
                                end,
                            },
                        }
                    },

                    -- 训练重点切换
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        marginBottom = 10,
                        children = {
                            UI.Label {
                                text = "重点: ", fontSize = 12,
                                color = Theme.COLORS.TEXT_MUTED, marginRight = 6,
                            },
                            table.unpack(focusBtns),
                        },
                    },

                    -- 球员列表
                    UI.Label {
                        text = "点击球员切换分配（✓ = 已在组内）",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 6,
                    },
                    UI.ScrollView {
                        flexGrow = 1, flexBasis = 0, scrollY = true,
                        children = { UI.Panel { width = "100%", children = playerRows } },
                    },
                }
            },
        },
    })
end

return Training
