-- ui/screens/player_detail.lua
-- 球员详情页面 - 增强版：多标签页（概览/属性/合同/统计/生涯/训练）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TrainingManager = require("scripts/systems/training_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ContractManager = require("scripts/systems/contract_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferManager = require("scripts/systems/transfer_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local StatsTab = require("scripts/ui/screens/player_detail/stats_tab")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")

local PlayerDetail = {}

------------------------------------------------------
-- 潜力星级显示（复用逻辑，与 youth.lua 一致）
------------------------------------------------------
local function _getScoutAccuracy(gameState)
    local teamId = gameState.playerTeamId
    local scoutBonus = StaffManager.getScoutingBonus(gameState, teamId)
    local facilityBonus = 1.0
    local team = gameState.teams[teamId]
    if team and team.finance and team.finance.facilities then
        local scoutFacility = team.finance.facilities.scouting or 0
        facilityBonus = 1.0 + scoutFacility * 0.05
    end
    return math.min(0.95, (0.50 + scoutBonus) * facilityBonus)
end

local function _getPotentialStars(potential, scoutAccuracy)
    -- 若已解锁潜力透视，直接显示精确值
    local gs = _G.gameState
    if gs and gs.potentialRevealed then
        local rating = PotentialSystem.rawToRating(potential)
        return 5, string.format("%.1f", rating)
    end

    local paRating = PotentialSystem.rawToRating(potential)
    local exactStars = (paRating - 1.0) / 9.0 * 4.0 + 1.0
    local accuracy = scoutAccuracy or 0.6
    local maxError = (1.0 - accuracy) * 1.5
    local seed = potential * 7 + 13
    local pseudoRandom = (math.sin(seed) * 10000) % 1.0
    local errorOffset = (pseudoRandom - 0.5) * 2 * maxError
    local displayStars = math.floor(exactStars + errorOffset + 0.5)
    displayStars = math.max(1, math.min(5, displayStars))
    local starText = string.rep("★", displayStars) .. string.rep("☆", 5 - displayStars)
    return displayStars, starText
end

-- 当前选中的标签
local _activeTab = "overview"  -- overview / attributes / contract / stats

function PlayerDetail.create(params)
    local gameState = _G.gameState
    local playerId = params and params.playerId
    if not gameState or not playerId then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    local player = gameState.players[playerId]
    if not player then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "球员不存在", color = Theme.COLORS.TEXT_PRIMARY } }
        }
    end

    -- 如果通过params传入了tab，使用它
    if params.tab then _activeTab = params.tab end

    local team = player.teamId and gameState.teams[player.teamId]
    local age = player:getAge(gameState.date.year)

    -- 标签栏
    local tabs = {
        { key = "overview",   label = "概览" },
        { key = "attributes", label = "属性" },
        { key = "contract",   label = "合同" },
        { key = "stats",      label = "统计" },
        { key = "career",     label = "生涯" },
        { key = "training",   label = "训练" },
    }
    local tabButtons = {}
    for _, t in ipairs(tabs) do
        local isActive = t.key == _activeTab
        table.insert(tabButtons, UI.Button {
            text = t.label,
            height = 32,
            paddingLeft = 14, paddingRight = 14,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 4,
            onClick = function()
                _activeTab = t.key
                Router.replaceWith("player_detail", { playerId = playerId, tab = t.key })
            end,
        })
    end

    -- 构建当前 tab 内容
    local tabContent
    if _activeTab == "overview" then
        tabContent = PlayerDetail._buildOverview(player, team, age, gameState)
    elseif _activeTab == "attributes" then
        tabContent = PlayerDetail._buildAttributes(player)
    elseif _activeTab == "contract" then
        tabContent = PlayerDetail._buildContract(player, team, age, gameState)
    elseif _activeTab == "stats" then
        tabContent = PlayerDetail._buildStats(player, gameState)
    elseif _activeTab == "career" then
        tabContent = PlayerDetail._buildCareer(player, team, age, gameState)
    elseif _activeTab == "training" then
        tabContent = PlayerDetail._buildTraining(player, team, gameState)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            _activeTab = "overview"
                            Router.back()
                        end,
                    },
                    UI.Label {
                        text = player.displayName,
                        fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = tostring(player.overall),
                        fontSize = 16, color = Theme.COLORS.SECONDARY,
                        fontWeight = "bold", width = 36, textAlign = "center",
                    },
                }
            },

            -- 头部简要信息
            UI.Panel {
                width = "100%", paddingLeft = 14, paddingRight = 14,
                paddingTop = 8, paddingBottom = 8,
                backgroundColor = Theme.COLORS.BG_HEADER,
                flexDirection = "row", flexWrap = "wrap",
                children = {
                    Theme.StatPill { label = "位置", value = Constants.POSITION_NAMES[player.position] or player.position },
                    Theme.StatPill { label = "年龄", value = age },
                    Theme.StatPill { label = "体能", value = player.fitness,
                        valueColor = player.fitness >= 75 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING },
                    Theme.StatPill { label = "士气", value = player.morale,
                        valueColor = player.morale >= 60 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING },
                    Theme.StatPill { label = "球队", value = team and team.name or "自由" },
                }
            },

            -- 标签栏
            UI.Panel {
                width = "100%", height = 44,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = tabButtons,
            },

            -- 内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = { tabContent },
            },
        }
    }
end

-- 概览标签
function PlayerDetail._buildOverview(player, team, age, gameState)
    -- 位置颜色（统一使用 Theme.posColor）
    -- local posColor = Theme.posColor(player.position)  -- 备用，如需位置颜色可取消注释

    -- 关键属性（按位置选择6个最重要的）
    local keyAttrs = PlayerDetail._getKeyAttributes(player)

    local keyAttrItems = {}
    for _, ka in ipairs(keyAttrs) do
        local color = ka.value >= 15 and Theme.COLORS.SECONDARY
            or (ka.value >= 12 and {128, 230, 128, 255}
            or (ka.value <= 6 and Theme.COLORS.DANGER
            or (ka.value <= 9 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_PRIMARY)))
        table.insert(keyAttrItems, UI.Panel {
            width = "48%", height = 32,
            flexDirection = "row", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label { text = ka.label, fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                -- 简易条形图
                UI.Panel {
                    width = 60, height = 6, backgroundColor = {38, 46, 71, 255}, borderRadius = 3,
                    marginRight = 6,
                    children = {
                        UI.Panel {
                            width = math.floor(ka.value / 20 * 100) .. "%",
                            height = "100%",
                            backgroundColor = color,
                            borderRadius = 3,
                        },
                    }
                },
                UI.Label { text = tostring(ka.value), fontSize = 12, color = color, fontWeight = "bold", width = 20 },
            }
        })
    end

    -- 赛季亮点
    local stats = player.seasonStats or {}
    local highlights = {}
    if (stats.goals or 0) > 0 then
        table.insert(highlights, stats.goals .. "球")
    end
    if (stats.assists or 0) > 0 then
        table.insert(highlights, stats.assists .. "助")
    end
    if (stats.appearances or 0) > 0 then
        table.insert(highlights, stats.appearances .. "场")
    end
    local highlightText = #highlights > 0 and table.concat(highlights, " / ") or "本赛季暂无数据"

    return UI.Panel {
        width = "100%",
        children = {
            -- 身份信息
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "基本信息" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = {
                            Theme.StatPill { label = "国籍", value = player.nationality },
                            Theme.StatPill { label = "潜力", value = select(2, _getPotentialStars(player.actualPotential or player.potential or 0, _getScoutAccuracy(gameState))), valueColor = Theme.COLORS.ACCENT },
                            Theme.StatPill { label = "惯用脚", value = player.preferredFoot == "right" and "右" or "左" },
                            Theme.StatPill { label = "弱足", value = player.weakFoot .. "星" },
                            Theme.StatPill { label = "身价", value = PlayerDetail._formatMoney(player.value) },
                        }
                    },
                }
            },

            -- 关键属性
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "关键属性" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = keyAttrItems,
                    },
                }
            },

            -- 本赛季表现
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "本赛季" },
                    UI.Label {
                        text = highlightText,
                        fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", marginTop = 4,
                    },
                }
            },

            -- 状态
            (player.injured or player.listedForSale) and Theme.Card {
                children = {
                    Theme.Subtitle { text = "状态标记" },
                    player.injured and UI.Label {
                        text = "受伤中（剩余 " .. (player.injuryDays or 0) .. " 天）",
                        fontSize = 13, color = Theme.COLORS.DANGER, marginTop = 4,
                    } or UI.Panel { height = 0 },
                    player.listedForSale and UI.Label {
                        text = "已挂牌出售",
                        fontSize = 13, color = Theme.COLORS.ACCENT, marginTop = 4,
                    } or UI.Panel { height = 0 },
                }
            } or UI.Panel { height = 0 },

            -- 转会操作（非己方球员）
            PlayerDetail._buildTransferAction(player, gameState),
        }
    }
end

-- 转会操作区域（概览底部）
function PlayerDetail._buildTransferAction(player, gameState)
    -- 只对非己方球员显示
    if player.teamId == gameState.playerTeamId then
        return UI.Panel { height = 0 }
    end

    local hasBid = TransferManager.hasPendingBid(gameState, player.id)
    local releaseClause = TransferManager.getReleaseClause(gameState, player.id)
    local attitude = TransferManager.getPlayerTransferAttitude(gameState, player.id, gameState.playerTeamId)

    local attitudeText = attitude == "eager" and "想转会" or (attitude == "open" and "愿考虑" or (attitude == "reluctant" and "不情愿" or "拒绝"))
    local attitudeColor = attitude == "eager" and Theme.COLORS.SECONDARY
        or (attitude == "open" and Theme.COLORS.ACCENT
        or (attitude == "reluctant" and Theme.COLORS.WARNING or Theme.COLORS.DANGER))

    local actionChildren = {
        Theme.Subtitle { text = "转会" },
        -- 态度和信息行
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginTop = 6, marginBottom = 10,
            children = {
                UI.Label { text = "转会态度: ", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Panel {
                    backgroundColor = {attitudeColor[1], attitudeColor[2], attitudeColor[3], 30},
                    borderRadius = 4, paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2, marginRight = 10,
                    children = { UI.Label { text = attitudeText, fontSize = 12, color = attitudeColor, fontWeight = "bold" } },
                },
                releaseClause and UI.Label {
                    text = "解约金: " .. PlayerDetail._formatMoney(releaseClause),
                    fontSize = 12, color = {255, 200, 80, 255},
                } or UI.Panel { height = 0 },
            },
        },
    }

    if hasBid then
        table.insert(actionChildren, UI.Button {
            text = "已提交报价",
            width = "100%", height = 40,
            backgroundColor = Theme.COLORS.TEXT_MUTED,
            borderRadius = 8, fontSize = 14,
            color = Theme.COLORS.TEXT_PRIMARY,
        })
    elseif releaseClause then
        table.insert(actionChildren, UI.Button {
            text = "触发解约金 · " .. PlayerDetail._formatMoney(releaseClause),
            width = "100%", height = 40,
            backgroundColor = {120, 90, 20, 255},
            borderRadius = 8, fontSize = 14, fontWeight = "bold",
            color = {255, 220, 80, 255},
            onClick = function()
                TransferManager.triggerReleaseClause(gameState, player.id)
                UI.Toast.Show({ message = "已触发解约金买断", variant = "success" })
                Router.replaceWith("player_detail", { playerId = player.id, tab = "overview" })
            end,
        })
    else
        table.insert(actionChildren, UI.Button {
            text = "提交转会报价",
            width = "100%", height = 40,
            backgroundColor = Theme.COLORS.PRIMARY,
            borderRadius = 8, fontSize = 14, fontWeight = "bold",
            color = Theme.COLORS.TEXT_PRIMARY,
            onClick = function()
                PlayerDetail._showBidSheet(gameState, player)
            end,
        })
    end

    return Theme.Card { children = actionChildren }
end

-- 球员详情页的报价弹窗
function PlayerDetail._showBidSheet(gameState, player)
    local Market = require("scripts/ui/screens/market")
    Market._showBidSheet(gameState, player, "all", "", "all")
end

-- 属性标签
function PlayerDetail._buildAttributes(player)
    local a = player.attributes

    local function AttrRow(label, value)
        local color = Theme.COLORS.TEXT_PRIMARY
        if value >= 15 then color = Theme.COLORS.SECONDARY
        elseif value >= 12 then color = {128, 230, 128, 255}
        elseif value <= 6 then color = Theme.COLORS.DANGER
        elseif value <= 9 then color = Theme.COLORS.WARNING
        end
        return UI.Panel {
            width = "48%", height = 30,
            flexDirection = "row", alignItems = "center",
            children = {
                UI.Label { text = label, fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Panel {
                    width = 50, height = 5, backgroundColor = {38, 46, 71, 255}, borderRadius = 2,
                    marginRight = 6,
                    children = {
                        UI.Panel {
                            width = math.floor(value / 20 * 100) .. "%",
                            height = "100%", backgroundColor = color, borderRadius = 2,
                        },
                    }
                },
                UI.Label { text = tostring(value), fontSize = 12, color = color, fontWeight = "bold", width = 22 },
            }
        }
    end

    local children = {
        -- 身体属性
        Theme.Card {
            children = {
                Theme.Subtitle { text = "身体" },
                UI.Panel {
                    flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                    children = {
                        AttrRow("速度", a.speed),
                        AttrRow("体能", a.stamina),
                        AttrRow("力量", a.strength),
                        AttrRow("敏捷", a.agility),
                        AttrRow("制空", a.aerial),
                    }
                },
            }
        },

        -- 技术属性
        Theme.Card {
            children = {
                Theme.Subtitle { text = "技术" },
                UI.Panel {
                    flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                    children = {
                        AttrRow("传球", a.passing),
                        AttrRow("射门", a.shooting),
                        AttrRow("盘带", a.dribbling),
                        AttrRow("抢断", a.tackling),
                        AttrRow("视野", a.vision),
                    }
                },
            }
        },

        -- 心理属性
        Theme.Card {
            children = {
                Theme.Subtitle { text = "心理" },
                UI.Panel {
                    flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                    children = {
                        AttrRow("防守", a.defending),
                        AttrRow("站位", a.positioning),
                        AttrRow("决策", a.decisions),
                        AttrRow("镇定", a.composure),
                        AttrRow("侵略", a.aggression),
                        AttrRow("合作", a.teamwork),
                        AttrRow("领导", a.leadership),
                    }
                },
            }
        },
    }

    -- 门将属性
    if player.position == "GK" then
        table.insert(children, Theme.Card {
            children = {
                Theme.Subtitle { text = "门将" },
                UI.Panel {
                    flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                    children = {
                        AttrRow("手型", a.handling),
                        AttrRow("反应", a.reflexes),
                    }
                },
            }
        })
    end

    return UI.Panel { width = "100%", children = children }
end

-- 合同标签
function PlayerDetail._buildContract(player, team, age, gameState)
    local contractEnd = player.contractEnd
    local contractText = "无合同"
    local monthsLeft = 0
    if contractEnd then
        monthsLeft = (contractEnd.year - gameState.date.year) * 12
            + (contractEnd.month - gameState.date.month)
        contractText = string.format("%d年%d月到期（剩余%d个月）",
            contractEnd.year, contractEnd.month, math.max(0, monthsLeft))
    end

    local contractColor = Theme.COLORS.TEXT_PRIMARY
    if monthsLeft <= 6 then contractColor = Theme.COLORS.DANGER
    elseif monthsLeft <= 12 then contractColor = Theme.COLORS.WARNING
    end

    return UI.Panel {
        width = "100%",
        children = {
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "合同详情" },
                    UI.Panel {
                        marginTop = 8,
                        children = {
                            PlayerDetail._infoRow("合同状态", contractText, contractColor),
                            PlayerDetail._infoRow("周薪", PlayerDetail._formatMoney(player.wage) .. "/周", Theme.COLORS.ACCENT),
                            PlayerDetail._infoRow("年薪（估）", PlayerDetail._formatMoney(player.wage * 52), Theme.COLORS.TEXT_SECONDARY),
                            PlayerDetail._infoRow("市场价值", PlayerDetail._formatMoney(player.value), Theme.COLORS.TEXT_PRIMARY),
                            PlayerDetail._infoRow("所属球队", team and team.name or "自由球员", Theme.COLORS.TEXT_PRIMARY),
                        }
                    },
                }
            },

            -- 转会状态
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "转会状态" },
                    UI.Panel {
                        marginTop = 6,
                        children = {
                            PlayerDetail._infoRow("挂牌出售", player.listedForSale and "是" or "否",
                                player.listedForSale and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED),
                            PlayerDetail._infoRow("租借状态", player.squadRole == "loaned" and "租借中" or "在队",
                                player.squadRole == "loaned" and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED),
                        }
                    },
                }
            },

            -- 薪资占比
            team and Theme.Card {
                children = {
                    Theme.Subtitle { text = "薪资在球队中的占比" },
                    UI.Panel {
                        marginTop = 8,
                        children = {
                            UI.Panel {
                                width = "100%", height = 20,
                                backgroundColor = {38, 46, 71, 255}, borderRadius = 10,
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = math.min(100, math.floor(player.wage / math.max(1, team.wageBudget) * 100)) .. "%",
                                        height = "100%",
                                        backgroundColor = Theme.COLORS.ACCENT,
                                        borderRadius = 10,
                                    },
                                }
                            },
                            UI.Label {
                                text = string.format("%.1f%% 的周薪预算", player.wage / math.max(1, team.wageBudget) * 100),
                                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                            },
                        }
                    },
                }
            } or UI.Panel { height = 0 },

            -- 阵容角色设置（仅本队球员）
            (team and team.id == gameState.playerTeamId) and PlayerDetail._buildSquadRoleCard(player, gameState) or UI.Panel { height = 0 },

            -- 合同操作（仅当是本队球员时显示）
            (team and team.id == gameState.playerTeamId) and PlayerDetail._buildContractActions(player, team, gameState) or UI.Panel { height = 0 },
        }
    }
end

------------------------------------------------------
-- 阵容角色设置卡片
------------------------------------------------------
local SQUAD_ROLES = {
    { id = "key",      label = "核心球员", desc = "绝对主力，期望每场首发", color = {255, 200, 50, 255} },
    { id = "rotation", label = "轮换球员", desc = "主要轮换，定期获得机会", color = {100, 180, 255, 255} },
    { id = "squad",    label = "阵容球员", desc = "候补力量，偶尔出场", color = {160, 160, 170, 255} },
    { id = "youth",    label = "青年球员", desc = "培养阶段，以锻炼为主", color = {120, 220, 150, 255} },
}

function PlayerDetail._buildSquadRoleCard(player, gameState)
    if player.squadRole == "loaned" then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "阵容角色" },
                UI.Label {
                    text = "该球员目前处于租借状态，无法更改阵容角色。",
                    fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6,
                },
            }
        }
    end

    local currentRole = player.squadRole or "rotation"
    local roleButtons = {}

    for _, role in ipairs(SQUAD_ROLES) do
        local isActive = (currentRole == role.id)
        table.insert(roleButtons, UI.Button {
            text = role.label,
            width = "48%",
            height = 36,
            backgroundColor = isActive and role.color or {50, 58, 80, 255},
            borderRadius = 8,
            fontSize = 12,
            color = isActive and {20, 20, 30, 255} or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 6,
            onClick = function()
                if not isActive then
                    local oldRole = player.squadRole
                    player.squadRole = role.id
                    -- 角色变更影响士气
                    local MoraleManager = require("scripts/systems/morale_manager")
                    MoraleManager.onSquadRoleChange(player, oldRole, role.id)
                    Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                end
            end,
        })
    end

    -- 当前角色描述
    local currentDesc = ""
    for _, role in ipairs(SQUAD_ROLES) do
        if role.id == currentRole then currentDesc = role.desc; break end
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "阵容角色" },
            UI.Label {
                text = currentDesc,
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4, marginBottom = 8,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "space-between",
                children = roleButtons,
            },
        }
    }
end

-- 合同操作区（终止合同、挂牌出售）
function PlayerDetail._buildContractActions(player, team, gameState)
    local isSafe, safetyReason = FinanceManager.checkSquadSafety(gameState, player.id)

    -- 终止合同按钮
    local terminateBtn
    if isSafe then
        terminateBtn = UI.Button {
            text = "终止合同",
            width = "100%", height = 44,
            backgroundColor = Theme.COLORS.DANGER,
            borderRadius = 8,
            fontSize = 14,
            color = {255, 255, 255, 255},
            onClick = function()
                ContractManager.terminateContract(gameState, player.id)
                Router.navigate("squad")
            end,
        }
    else
        terminateBtn = UI.Button {
            text = "终止合同 (阵容不足)",
            width = "100%", height = 44,
            backgroundColor = {50, 55, 75, 255},
            borderRadius = 8,
            fontSize = 14,
            color = Theme.COLORS.TEXT_MUTED,
            disabled = true,
            onClick = function()
                gameState:sendMessage({
                    category = "squad",
                    title = "无法终止合同",
                    body = "无法终止 " .. player.displayName .. " 的合同：" .. (safetyReason or "阵容深度不足"),
                    priority = "normal",
                })
                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
            end,
        }
    end

    -- 赔偿金计算显示
    local monthsLeft = 0
    if player.contractEnd then
        monthsLeft = (player.contractEnd.year - gameState.date.year) * 12
            + (player.contractEnd.month - gameState.date.month)
    end
    local compensation = math.floor(player.wage * 4 * math.max(0, monthsLeft) * 0.5)

    -- 续约按钮
    local renewBtn
    local suggestedTerms = ContractManager.getSuggestedTerms(player, team, gameState)
    if suggestedTerms then
        renewBtn = UI.Button {
            text = string.format("续约 (建议: %s/周 × %d年)",
                PlayerDetail._formatMoney(suggestedTerms.wage), suggestedTerms.years),
            width = "100%", height = 44,
            backgroundColor = Theme.COLORS.SECONDARY,
            borderRadius = 8,
            fontSize = 14,
            color = {255, 255, 255, 255},
            marginBottom = 10,
            onClick = function()
                ConfirmDialog.show({
                    title = "续约谈判",
                    message = string.format(
                        "向 %s 提出续约：\n周薪: %s（范围 %s ~ %s）\n年限: %d 年",
                        player.displayName,
                        PlayerDetail._formatMoney(suggestedTerms.wage),
                        PlayerDetail._formatMoney(suggestedTerms.minWage),
                        PlayerDetail._formatMoney(suggestedTerms.maxWage),
                        suggestedTerms.years
                    ),
                    confirmText = "提出续约",
                    danger = false,
                    onConfirm = function()
                        local success, err = ContractManager.renewContract(
                            gameState, player.id, suggestedTerms.wage, suggestedTerms.years)
                        if success then
                            gameState:sendMessage({
                                category = "transfer",
                                title = "续约成功",
                                body = player.displayName .. " 已同意续约，新合同为期 "
                                    .. suggestedTerms.years .. " 年。",
                                priority = "high",
                            })
                        else
                            gameState:sendMessage({
                                category = "transfer",
                                title = "续约失败",
                                body = player.displayName .. " 拒绝续约：" .. (err or "条件不满足"),
                                priority = "normal",
                            })
                        end
                        Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                    end,
                })
            end,
        }
    else
        renewBtn = UI.Panel { height = 0 }
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "合同操作" },
            -- 续约按钮
            renewBtn,
            -- 赔偿金提示
            compensation > 0 and UI.Label {
                text = string.format("终止合同需支付赔偿金: %s", PlayerDetail._formatMoney(compensation)),
                fontSize = 12,
                color = Theme.COLORS.WARNING,
                marginTop = 4,
                marginBottom = 8,
            } or UI.Label {
                text = "合同即将到期，无需赔偿",
                fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED,
                marginTop = 4,
                marginBottom = 8,
            },
            -- 安全检查提示
            (not isSafe) and UI.Label {
                text = safetyReason or "阵容深度不足",
                fontSize = 11,
                color = Theme.COLORS.DANGER,
                marginBottom = 6,
            } or UI.Panel { height = 0 },
            -- 挂牌出售 / 取消挂牌按钮
            PlayerDetail._buildListForSaleBtn(player, isSafe, safetyReason, gameState),
            -- 终止按钮
            terminateBtn,
        }
    }
end

-- 挂牌出售 / 取消挂牌 / 收到报价处理
function PlayerDetail._buildListForSaleBtn(player, isSafe, safetyReason, gameState)
    -- 如果有收到的报价，优先显示报价操作
    local incomingBids = TransferManager.getPendingSellBids(gameState)
    for _, bid in ipairs(incomingBids) do
        if bid.playerId == player.id and bid.isIncomingBid then
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local buyerName = buyerTeam and buyerTeam.name or "未知球队"
            return UI.Panel {
                width = "100%", marginBottom = 10,
                children = {
                    UI.Label {
                        text = "收到报价：" .. buyerName .. " 出价 " .. FinanceManager.formatMoney(bid.amount),
                        fontSize = 13, color = Theme.COLORS.ACCENT,
                        fontWeight = "bold", marginBottom = 8,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        children = {
                            UI.Button {
                                text = "接受报价",
                                flexGrow = 1, height = 40,
                                backgroundColor = Theme.COLORS.SECONDARY,
                                borderRadius = 8, fontSize = 14,
                                color = {255, 255, 255, 255},
                                marginRight = 6,
                                onClick = function()
                                    ConfirmDialog.show({
                                        title = "确认出售",
                                        message = string.format("确认以 %.0fK 将 %s 出售给 %s？",
                                            bid.amount / 1000, player.displayName, buyerName),
                                        confirmText = "确认出售",
                                        danger = false,
                                        onConfirm = function()
                                            TransferManager.acceptIncomingBid(gameState, bid.id)
                                            Router.replaceWith("market", { tab = "listed" })
                                        end,
                                    })
                                end,
                            },
                            UI.Button {
                                text = "拒绝",
                                width = 70, height = 40,
                                backgroundColor = Theme.COLORS.DANGER,
                                borderRadius = 8, fontSize = 14,
                                color = {255, 255, 255, 255},
                                onClick = function()
                                    TransferManager.rejectIncomingBid(gameState, bid.id)
                                    Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                                end,
                            },
                        },
                    },
                },
            }
        end
    end

    -- 已挂牌 → 取消挂牌
    if player.listedForSale then
        return UI.Button {
            text = "取消挂牌出售",
            width = "100%", height = 44,
            backgroundColor = {80, 80, 100, 255},
            borderRadius = 8, fontSize = 14,
            color = Theme.COLORS.WARNING,
            marginBottom = 10,
            onClick = function()
                player.listedForSale = false
                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
            end,
        }
    end

    -- 未挂牌 + 安全 → 挂牌出售
    if isSafe then
        return UI.Button {
            text = "挂牌出售",
            width = "100%", height = 44,
            backgroundColor = Theme.COLORS.ACCENT,
            borderRadius = 8, fontSize = 14,
            color = {255, 255, 255, 255},
            marginBottom = 10,
            onClick = function()
                player.listedForSale = true
                gameState:sendMessage({
                    category = "transfer",
                    title = player.displayName .. " 已挂牌",
                    body = player.displayName .. " 已被挂牌出售，等待买家报价。",
                    priority = "normal",
                })
                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
            end,
        }
    end

    -- 未挂牌 + 阵容不安全 → 灰色不可用
    return UI.Button {
        text = "挂牌出售 (阵容不足)",
        width = "100%", height = 44,
        backgroundColor = {50, 55, 75, 255},
        borderRadius = 8, fontSize = 14,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 10,
        disabled = true,
        onClick = function()
            gameState:sendMessage({
                category = "squad",
                title = "无法挂牌出售",
                body = "无法挂牌 " .. player.displayName .. "：" .. (safetyReason or "阵容深度不足"),
                priority = "normal",
            })
        end,
    }
end

-- 统计标签
function PlayerDetail._buildStats(player, gameState)
    return StatsTab.build(player, gameState)
end

-- 辅助：信息行
function PlayerDetail._infoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%", height = 34,
        flexDirection = "row", alignItems = "center",
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label { text = label, fontSize = 13, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
            UI.Label { text = value, fontSize = 13, color = valueColor or Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
        }
    }
end

-- 辅助：格式化金额
function PlayerDetail._formatMoney(amount)
    return FinanceManager.formatMoney(amount)
end

-- 辅助：按位置获取关键属性
function PlayerDetail._getKeyAttributes(player)
    local a = player.attributes
    local pos = player.position
    if pos == "GK" then
        return {
            {label="手型", value=a.handling}, {label="反应", value=a.reflexes},
            {label="站位", value=a.positioning}, {label="制空", value=a.aerial},
            {label="镇定", value=a.composure}, {label="决策", value=a.decisions},
        }
    elseif pos == "CB" then
        return {
            {label="防守", value=a.defending}, {label="抢断", value=a.tackling},
            {label="制空", value=a.aerial}, {label="力量", value=a.strength},
            {label="站位", value=a.positioning}, {label="镇定", value=a.composure},
        }
    elseif pos == "LB" or pos == "RB" then
        return {
            {label="防守", value=a.defending}, {label="抢断", value=a.tackling},
            {label="速度", value=a.speed}, {label="体能", value=a.stamina},
            {label="传球", value=a.passing}, {label="盘带", value=a.dribbling},
        }
    elseif pos == "CDM" then
        return {
            {label="抢断", value=a.tackling}, {label="防守", value=a.defending},
            {label="传球", value=a.passing}, {label="站位", value=a.positioning},
            {label="体能", value=a.stamina}, {label="力量", value=a.strength},
        }
    elseif pos == "ST" or pos == "CF" then
        return {
            {label="射门", value=a.shooting}, {label="镇定", value=a.composure},
            {label="站位", value=a.positioning}, {label="速度", value=a.speed},
            {label="盘带", value=a.dribbling}, {label="制空", value=a.aerial},
        }
    elseif pos == "LW" or pos == "RW" then
        return {
            {label="速度", value=a.speed}, {label="盘带", value=a.dribbling},
            {label="敏捷", value=a.agility}, {label="射门", value=a.shooting},
            {label="传球", value=a.passing}, {label="视野", value=a.vision},
        }
    else -- CM/CAM/LM/RM
        return {
            {label="传球", value=a.passing}, {label="视野", value=a.vision},
            {label="体能", value=a.stamina}, {label="决策", value=a.decisions},
            {label="盘带", value=a.dribbling}, {label="射门", value=a.shooting},
        }
    end
end

-- 生涯标签
function PlayerDetail._buildCareer(player, team, age, gameState)
    -- 球员生涯概况（基于现有数据推导）
    local careerYears = age - 16  -- 假设16岁开始职业生涯
    if careerYears < 0 then careerYears = 0 end

    -- 合同历史概要
    local contractEnd = player.contractEnd
    local joinedInfo = "未知"
    if contractEnd then
        -- 推算入队时间（假设合同期通常3-5年）
        local contractLen = contractEnd.year - gameState.date.year
        local joinYear = contractEnd.year - math.max(3, contractLen + 1)
        if team then
            joinedInfo = string.format("%d年加入%s", joinYear, team.name)
        end
    end

    -- 能力成长状态（使用星级替代具体数值）
    local effectivePotential = player.actualPotential or player.potential or 0
    local scoutAcc = _getScoutAccuracy(gameState)
    local potStars, potStarText = _getPotentialStars(effectivePotential, scoutAcc)
    local potentialGap = effectivePotential - (player.overall or 0)
    local growthStatus = "已达巅峰"
    local growthColor = Theme.COLORS.TEXT_MUTED
    if potentialGap > 15 then
        growthStatus = "高成长空间"
        growthColor = Theme.COLORS.ACCENT
    elseif potentialGap > 8 then
        growthStatus = "仍有成长空间"
        growthColor = Theme.COLORS.SECONDARY
    elseif potentialGap > 3 then
        growthStatus = "接近巅峰"
        growthColor = Theme.COLORS.WARNING
    end

    -- 年龄阶段
    local phase = "青年期"
    local phaseColor = Theme.COLORS.ACCENT
    if age >= 32 then
        phase = "退役期"
        phaseColor = Theme.COLORS.DANGER
    elseif age >= 29 then
        phase = "衰退期"
        phaseColor = Theme.COLORS.WARNING
    elseif age >= 25 then
        phase = "巅峰期"
        phaseColor = Theme.COLORS.SECONDARY
    elseif age >= 21 then
        phase = "成长期"
        phaseColor = {128, 230, 128, 255}
    end

    return UI.Panel {
        width = "100%",
        children = {
            -- 生涯概况
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "生涯概况" },
                    UI.Panel {
                        marginTop = 8,
                        children = {
                            PlayerDetail._infoRow("职业年限", tostring(careerYears) .. "年", Theme.COLORS.TEXT_PRIMARY),
                            PlayerDetail._infoRow("年龄阶段", phase, phaseColor),
                            PlayerDetail._infoRow("成长状态", growthStatus, growthColor),
                            PlayerDetail._infoRow("当前球队", team and team.name or "自由球员", Theme.COLORS.TEXT_PRIMARY),
                            PlayerDetail._infoRow("加入时间", joinedInfo, Theme.COLORS.TEXT_MUTED),
                        }
                    },
                }
            },

            -- 能力发展
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "能力发展" },
                    UI.Panel {
                        marginTop = 8,
                        children = {
                            UI.Panel {
                                width = "100%", flexDirection = "row", alignItems = "center",
                                marginBottom = 8,
                                children = {
                                    UI.Label { text = "当前能力", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 80 },
                                    UI.Panel {
                                        flexGrow = 1, height = 12, backgroundColor = {38, 46, 71, 255}, borderRadius = 6,
                                        children = {
                                            UI.Panel {
                                                width = math.floor((player.overall or 0) / 99 * 100) .. "%",
                                                height = "100%", backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 6,
                                            },
                                        }
                                    },
                                    UI.Label { text = tostring(player.overall or 0), fontSize = 13, color = Theme.COLORS.SECONDARY,
                                        fontWeight = "bold", width = 30, textAlign = "right" },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", alignItems = "center",
                                marginBottom = 8,
                                children = {
                                    UI.Label { text = "潜力评级", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 80 },
                                    UI.Label { text = potStarText, fontSize = 14, color = Theme.COLORS.ACCENT,
                                        fontWeight = "bold", flexGrow = 1 },
                                },
                            },

                            UI.Label {
                                text = string.format("可发展空间: %s", growthStatus),
                                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                            },
                        }
                    },
                }
            },

            -- 球员特性
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "球员特性" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = PlayerDetail._buildTraits(player),
                    },
                }
            },
        }
    }
end

-- 训练标签
function PlayerDetail._buildTraining(player, team, gameState)
    local currentFocus = player.trainingFocus or "跟随全队"
    local teamFocus = team and team.trainingFocus or "balanced"

    -- 训练重点选项
    local focusOptions = {
        { key = nil,         label = "跟随全队", desc = "使用球队训练方案" },
        { key = "attack",    label = "进攻", desc = "射门/盘带/传球/视野" },
        { key = "defense",   label = "防守", desc = "抢断/防守/站位/制空" },
        { key = "fitness",   label = "体能", desc = "速度/耐力/力量/敏捷" },
        { key = "technical", label = "技术", desc = "盘带/传球/视野/镇定" },
        { key = "tactical",  label = "战术", desc = "决策/站位/合作/视野" },
    }

    local focusItems = {}
    for _, opt in ipairs(focusOptions) do
        local isActive = (player.trainingFocus == opt.key)
        table.insert(focusItems, UI.Button {
            text = opt.label,
            width = "100%",
            height = 52,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            borderWidth = isActive and 2 or 1,
            borderColor = isActive and Theme.COLORS.ACCENT or Theme.COLORS.BORDER,
            fontSize = 14,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginBottom = 6,
            onClick = function()
                player.trainingFocus = opt.key
                Router.replaceWith("player_detail", { playerId = player.id, tab = "training" })
            end,
        })
    end

    -- 提示信息
    local focusLabel = currentFocus
    if type(currentFocus) == "string" then
        for _, opt in ipairs(focusOptions) do
            if opt.key == player.trainingFocus then
                focusLabel = opt.label
                break
            end
        end
    end
    if not player.trainingFocus then
        focusLabel = "跟随全队"
    end

    -- 训练效果
    local attrList = {}
    local activeKey = player.trainingFocus or teamFocus
    local attrs = TrainingManager.FOCUS_ATTRS[activeKey]
    if attrs then
        for _, attrName in ipairs(attrs) do
            table.insert(attrList, attrName)
        end
    end

    local attrLabels = {
        speed = "速度", stamina = "体能", strength = "力量", agility = "敏捷",
        passing = "传球", shooting = "射门", dribbling = "盘带", tackling = "抢断",
        defending = "防守", positioning = "站位", vision = "视野", decisions = "决策",
        composure = "镇定", teamwork = "合作", aerial = "制空",
    }

    local effectPills = {}
    for _, attr in ipairs(attrList) do
        table.insert(effectPills, Theme.StatPill {
            label = "", value = attrLabels[attr] or attr,
            valueColor = Theme.COLORS.ACCENT,
        })
    end

    return UI.Panel {
        width = "100%",
        children = {
            -- 当前状态
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "个人训练" },
                    UI.Panel {
                        marginTop = 6,
                        children = {
                            PlayerDetail._infoRow("当前重点", focusLabel, Theme.COLORS.ACCENT),
                            PlayerDetail._infoRow("球队方案", Constants.TRAINING_FOCUS_NAMES and Constants.TRAINING_FOCUS_NAMES[teamFocus] or teamFocus, Theme.COLORS.TEXT_MUTED),
                            PlayerDetail._infoRow("体能", tostring(player.fitness) .. "%",
                                player.fitness >= 75 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING),
                        }
                    },
                }
            },

            -- 训练效果
            (#effectPills > 0) and Theme.Card {
                children = {
                    Theme.Subtitle { text = "训练提升属性" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = effectPills,
                    },
                }
            } or UI.Panel { height = 0 },

            -- 选择训练重点
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "选择训练重点" },
                    UI.Panel {
                        marginTop = 8,
                        children = focusItems,
                    },
                }
            },
        }
    }
end

-- 辅助：构建球员特性标签
function PlayerDetail._buildTraits(player)
    local traits = player.traits or {}
    if #traits == 0 then
        return {
            UI.Label { text = "暂无特性标签", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
        }
    end
    local items = {}
    for _, trait in ipairs(traits) do
        table.insert(items, UI.Panel {
            backgroundColor = {38, 60, 90, 255},
            borderRadius = 12,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 4, paddingBottom = 4,
            marginRight = 6, marginBottom = 4,
            children = {
                UI.Label { text = trait, fontSize = 11, color = Theme.COLORS.ACCENT },
            },
        })
    end
    return items
end

return PlayerDetail
