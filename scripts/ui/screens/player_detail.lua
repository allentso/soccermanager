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
local SaveManager = require("scripts/persistence/save_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local StatsTab = require("scripts/ui/screens/player_detail/stats_tab")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local LegendImageRegistry = require("scripts/data/legend_image_registry")
local ReincarnationImageRegistry = require("scripts/data/reincarnation_image_registry")
local YouthManager = require("scripts/systems/youth_manager")
local PositionFit = require("scripts/domain/position_fit")
local PositionTrainingManager = require("scripts/systems/position_training_manager")

local PlayerDetail = {}

------------------------------------------------------
-- 潜力星级显示（复用逻辑，与 youth.lua 一致）
------------------------------------------------------
local function _getScoutAccuracy(gameState)
    return ScoutManager.getAccuracy(gameState)
end

------------------------------------------------------
-- 球探能力不足时，部分属性显示为 "?"
-- 基于球探准确度和属性伪随机种子决定是否可见
------------------------------------------------------
local function _isAttrRevealed(playerId, attrKey, scoutAccuracy)
    -- 本队球员总是全部可见
    local gs = _G.gameState
    if gs and gs.players[playerId] and gs.players[playerId].teamId == gs.playerTeamId then
        return true
    end
    -- 准确度 >= 0.95 时全部可见
    if scoutAccuracy >= 0.95 then return true end
    -- 用 playerId + attrKey 生成伪随机种子，确保同一球员同一属性结果一致
    local seed = playerId * 31 + string.byte(attrKey, 1) * 7 + (string.byte(attrKey, 2) or 0) * 3
    local pseudoRand = (math.sin(seed) * 10000) % 1.0
    -- 准确度越高，越多属性可见（例如 accuracy=0.7 → 70% 概率可见）
    return pseudoRand < scoutAccuracy
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
                        text = tostring(player:displayOverall()),
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
                    Theme.StatPill {
                        label = "位置",
                        value = PositionFit.formatNaturalPositions(player, Constants.POSITION_NAMES),
                    },
                    Theme.StatPill { label = "年龄", value = age },
                    Theme.StatPill { label = "体能", value = math.floor(player.fitness),
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
    local scoutAcc = _getScoutAccuracy(gameState)

    local keyAttrItems = {}
    for _, ka in ipairs(keyAttrs) do
        local revealed = _isAttrRevealed(player.id, ka.key, scoutAcc)
        -- UI 显示上限: 最高20
        local intValue = math.min(Constants.ATTR_MAX, math.floor(ka.value + 0.5))
        local displayValue = revealed and tostring(intValue) or "?"
        local barWidth = revealed and (math.floor(intValue / 20 * 100) .. "%") or "50%"
        local color
        if not revealed then
            color = Theme.COLORS.TEXT_MUTED
        else
            color = intValue >= 15 and Theme.COLORS.SECONDARY
                or (intValue >= 12 and {128, 230, 128, 255}
                or (intValue <= 6 and Theme.COLORS.DANGER
                or (intValue <= 9 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_PRIMARY)))
        end
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
                            width = barWidth,
                            height = "100%",
                            backgroundColor = revealed and color or {60, 70, 100, 255},
                            borderRadius = 3,
                        },
                    }
                },
                UI.Label { text = displayValue, fontSize = 12, color = color, fontWeight = "bold", width = 20 },
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

    -- 传奇球员立绘卡片
    local legendCard = UI.Panel { height = 0 }
    local legendImgPath = nil
    -- 优先通过 legendData.id 查找
    if player.legendData and player.legendData.id then
        legendImgPath = LegendImageRegistry.getPath(player.legendData.id)
    end
    -- 兜底：通过中文名反查（兼容旧存档中已签入但未保存 legendData 的球员）
    if not legendImgPath then
        legendImgPath = LegendImageRegistry.getPathByName(player.legendName)
            or LegendImageRegistry.getPathByName(player.displayName)
    end
    if legendImgPath then
        legendCard = Theme.Card {
            children = {
                UI.Panel {
                    width = "100%",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            width = "75%",
                            aspectRatio = 3 / 4,
                            borderRadius = 12,
                            overflow = "hidden",
                            backgroundImage = legendImgPath,
                            backgroundSize = "cover",
                        },
                        UI.Label {
                            text = player.legendName or player.displayName or "传奇球星",
                            fontSize = 14,
                            color = {255, 215, 0, 255},
                            fontWeight = "bold",
                            textAlign = "center",
                            marginTop = 10,
                        },
                    },
                },
            },
        }
    end

    -- 转生球员立绘卡片（粉色系，与传奇互斥）
    local reincarnCard = UI.Panel { height = 0 }
    if not legendImgPath and player.isReincarnation then
        local reincarnImgPath = ReincarnationImageRegistry.getPath(player.reincarnationMatchName)
            or ReincarnationImageRegistry.getPathByName(player.displayName)
        if reincarnImgPath then
            reincarnCard = Theme.Card {
                children = {
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = "75%",
                                aspectRatio = 3 / 4,
                                borderRadius = 12,
                                overflow = "hidden",
                                backgroundImage = reincarnImgPath,
                                backgroundSize = "cover",
                            },
                            UI.Label {
                                text = (player.displayName or "转生球星") .. (player.reincarnationTier == "rebirth" and " · 重生" or " · 转生"),
                                fontSize = 14,
                                color = {255, 130, 180, 255},
                                fontWeight = "bold",
                                textAlign = "center",
                                marginTop = 10,
                            },
                        },
                    },
                },
            }
        end
    end

    return UI.Panel {
        width = "100%",
        children = {
            -- 传奇立绘
            legendCard,
            -- 转生立绘
            reincarnCard,

            -- 身份信息
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "基本信息" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = {
                            Theme.StatPill { label = "国籍", value = ScoutManager.getNationName(player.nationality) },
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
                        text = player.injurySeasonEnding
                            and string.format("赛季报销 · %s（预计 %d 天后恢复）",
                                player.injuryKindName or "严重伤病", player.injuryDays or 0)
                            or (player.injuryKindName
                                and string.format("受伤中 · %s（%s，剩余 %d 天）",
                                    player.injuryKindName,
                                    player.injurySeverityName or "恢复中",
                                    player.injuryDays or 0)
                                or ("受伤中（剩余 " .. (player.injuryDays or 0) .. " 天）")),
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
    local movedThisWindow = TransferManager.hasMovedInCurrentWindow(gameState, player.id)
    local releaseClause = TransferManager.getReleaseClause(gameState, player.id)
    local attitude, attitudeDesc = TransferManager.getPlayerTransferAttitude(gameState, player.id, gameState.playerTeamId)

    local attitudeText = attitude == "eager" and "想转会" or (attitude == "open" and "愿考虑" or (attitude == "reluctant" and "不情愿" or "拒绝"))
    if attitude == "refusing" and attitudeDesc and attitudeDesc ~= "" then
        attitudeText = attitudeDesc
    end
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

    -- 候选名单按钮
    local isInShortlist = gameState.shortlist and gameState.shortlist[player.id]
    local shortlistBtn = UI.Button {
        text = isInShortlist and "已加入候选" or "加入候选名单",
        flexGrow = 1, height = 40,
        backgroundColor = isInShortlist and {60, 70, 90, 255} or {45, 55, 80, 255},
        borderRadius = 8, fontSize = 13, fontWeight = "bold",
        color = isInShortlist and Theme.COLORS.TEXT_MUTED or Theme.COLORS.ACCENT,
        borderWidth = 1,
        borderColor = isInShortlist and Theme.COLORS.BORDER or Theme.COLORS.ACCENT,
        onClick = function()
            if not gameState.shortlist then gameState.shortlist = {} end
            if isInShortlist then
                gameState.shortlist[player.id] = nil
                UI.Toast.Show({ message = player.displayName .. " 已移出候选名单", variant = "info" })
            else
                gameState.shortlist[player.id] = true
                UI.Toast.Show({ message = player.displayName .. " 已加入候选名单", variant = "success" })
            end
            Router.replaceWith("player_detail", { playerId = player.id, tab = "overview" })
        end,
    }

    if hasBid then
        table.insert(actionChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            children = {
                UI.Button {
                    text = "已提交报价",
                    flexGrow = 1, height = 40,
                    backgroundColor = Theme.COLORS.TEXT_MUTED,
                    borderRadius = 8, fontSize = 14,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    marginRight = 8,
                },
                shortlistBtn,
            },
        })
    elseif movedThisWindow then
        table.insert(actionChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            children = {
                UI.Button {
                    text = "本窗已转会",
                    flexGrow = 1, height = 40,
                    backgroundColor = Theme.COLORS.TEXT_MUTED,
                    borderRadius = 8, fontSize = 14,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    marginRight = 8,
                    onClick = function()
                        local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                        TransferLimitDialog.show(player.displayName, gameState)
                    end,
                },
                shortlistBtn,
            },
        })
    elseif releaseClause then
        table.insert(actionChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            children = {
                UI.Button {
                    text = "触发解约金 · " .. PlayerDetail._formatMoney(releaseClause),
                    flexGrow = 1, height = 40,
                    backgroundColor = {120, 90, 20, 255},
                    borderRadius = 8, fontSize = 14, fontWeight = "bold",
                    color = {255, 220, 80, 255},
                    marginRight = 8,
                    onClick = function()
                        local _, err = TransferManager.triggerReleaseClause(gameState, player.id)
                        if err then
                            local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                            if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                                UI.Toast.Show({ message = err, variant = "error" })
                            end
                            return
                        end
                        UI.Toast.Show({ message = "已触发解约金买断", variant = "success" })
                        Router.replaceWith("player_detail", { playerId = player.id, tab = "overview" })
                    end,
                },
                shortlistBtn,
            },
        })
    else
        table.insert(actionChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            children = {
                UI.Button {
                    text = "提交转会报价",
                    flexGrow = 1, height = 40,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 8, fontSize = 14, fontWeight = "bold",
                    color = Theme.COLORS.TEXT_PRIMARY,
                    marginRight = 8,
                    onClick = function()
                        PlayerDetail._showBidSheet(gameState, player)
                    end,
                },
                shortlistBtn,
            },
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
    local gameState = _G.gameState
    local scoutAcc = _getScoutAccuracy(gameState)

    local function AttrRow(label, attrKey, value)
        local revealed = _isAttrRevealed(player.id, attrKey, scoutAcc)
        -- UI 显示上限: 最高显示20（后台可能存21）
        local intVal = math.min(Constants.ATTR_MAX, math.floor(value + 0.5))
        local color = Theme.COLORS.TEXT_PRIMARY
        if not revealed then
            color = Theme.COLORS.TEXT_MUTED
        elseif intVal >= 15 then color = Theme.COLORS.SECONDARY
        elseif intVal >= 12 then color = {128, 230, 128, 255}
        elseif intVal <= 6 then color = Theme.COLORS.DANGER
        elseif intVal <= 9 then color = Theme.COLORS.WARNING
        end
        local displayValue = revealed and tostring(intVal) or "?"
        local barWidth = revealed and (math.floor(intVal / 20 * 100) .. "%") or "50%"
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
                            width = barWidth,
                            height = "100%", backgroundColor = revealed and color or {60, 70, 100, 255}, borderRadius = 2,
                        },
                    }
                },
                UI.Label { text = displayValue, fontSize = 12, color = color, fontWeight = "bold", width = 22 },
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
                        AttrRow("速度", "speed", a.speed),
                        AttrRow("体能", "stamina", a.stamina),
                        AttrRow("力量", "strength", a.strength),
                        AttrRow("敏捷", "agility", a.agility),
                        AttrRow("制空", "aerial", a.aerial),
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
                        AttrRow("传球", "passing", a.passing),
                        AttrRow("射门", "shooting", a.shooting),
                        AttrRow("盘带", "dribbling", a.dribbling),
                        AttrRow("抢断", "tackling", a.tackling),
                        AttrRow("视野", "vision", a.vision),
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
                        AttrRow("防守", "defending", a.defending),
                        AttrRow("站位", "positioning", a.positioning),
                        AttrRow("决策", "decisions", a.decisions),
                        AttrRow("镇定", "composure", a.composure),
                        AttrRow("侵略", "aggression", a.aggression),
                        AttrRow("合作", "teamwork", a.teamwork),
                        AttrRow("领导", "leadership", a.leadership),
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
                        AttrRow("手型", "handling", a.handling),
                        AttrRow("反应", "reflexes", a.reflexes),
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

    local isOwnYouth = YouthManager.isYouthSquadPlayer(gameState, player)
    local isOwnSquad = player.teamId == gameState.playerTeamId and player.squadRole ~= "loaned"
        and not isOwnYouth
    local isLoanedOut = player.squadRole == "loaned" and player._loanOriginTeamId == gameState.playerTeamId
    local isLoanedIn = player.teamId == gameState.playerTeamId and player.squadRole == "loaned"
    local loanRecord = TransferManager.getLoanForPlayer(gameState, player.id)
    local loanStatusText = "在队"
    local loanStatusColor = Theme.COLORS.TEXT_MUTED
    if isLoanedIn and loanRecord then
        local fromTeam = gameState.teams[loanRecord.originTeamId]
        loanStatusText = "租入 · 来自 " .. (fromTeam and fromTeam.name or "?")
        loanStatusColor = Theme.COLORS.SECONDARY
    elseif isLoanedOut and loanRecord then
        local toTeam = gameState.teams[loanRecord.loanTeamId]
        loanStatusText = "外租 · 至 " .. (toTeam and toTeam.name or "?")
        loanStatusColor = Theme.COLORS.WARNING
    elseif player.squadRole == "loaned" then
        loanStatusText = "租借中"
        loanStatusColor = Theme.COLORS.WARNING
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
                            PlayerDetail._infoRow("挂牌外租", player.listedForLoan and "是" or "否",
                                player.listedForLoan and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_MUTED),
                            PlayerDetail._infoRow("租借状态", loanStatusText, loanStatusColor),
                            loanRecord and PlayerDetail._infoRow("租期剩余",
                                tostring(TransferManager.formatLoanRemainingWeeks(loanRecord)) .. " 周",
                                Theme.COLORS.TEXT_SECONDARY) or UI.Panel { height = 0 },
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

            -- 阵容角色设置（仅本队非租借球员）
            isOwnSquad and PlayerDetail._buildSquadRoleCard(player, gameState) or UI.Panel { height = 0 },

            -- 下放青训（仅符合条件的年轻球员）
            isOwnSquad and PlayerDetail._buildDemoteToYouthBtn(player, gameState) or UI.Panel { height = 0 },

            -- 合同操作
            isOwnSquad and PlayerDetail._buildContractActions(player, team, gameState) or UI.Panel { height = 0 },
            isOwnYouth and PlayerDetail._buildYouthTransferCard(player, gameState) or UI.Panel { height = 0 },
            isLoanedOut and PlayerDetail._buildRecallLoanCard(player, gameState) or UI.Panel { height = 0 },
            isLoanedIn and PlayerDetail._buildExtendLoanCard(player, gameState) or UI.Panel { height = 0 },
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

function PlayerDetail._buildDemoteToYouthBtn(player, gameState)
    local canDemote, err = YouthManager.canDemoteToYouth(gameState, player.id)
    if not canDemote then
        local ownTeam = gameState:getPlayerTeam()
        local age = player:getAge(gameState.date.year)
        if ownTeam and player.teamId == ownTeam.id and age <= Constants.YOUTH_PHASE_MAX_AGE and err then
            return Theme.Card {
                children = {
                    Theme.Subtitle { text = "青训编制" },
                    UI.Label {
                        text = string.format("当前无法下放：%s", err),
                        fontSize = 11, color = Theme.COLORS.WARNING, marginTop = 6,
                    },
                },
            }
        end
        return UI.Panel { height = 0 }
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "青训编制" },
            UI.Label {
                text = string.format(
                    "将球员移回青训队，不占一线队名额；周薪调整为青训标准。仅 %d 岁及以下球员可下放。",
                    Constants.YOUTH_PHASE_MAX_AGE),
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 6, marginBottom = 10,
            },
            UI.Button {
                text = "下放至青训队",
                width = "100%", height = 44,
                backgroundColor = {120, 220, 150, 255},
                borderRadius = 8, fontSize = 14,
                color = {20, 20, 30, 255},
                fontWeight = "bold",
                onClick = function()
                    ConfirmDialog.show({
                        title = "下放至青训队",
                        message = string.format(
                            "确定将 %s 下放至青训队吗？\n移出一线队名单后可在青训页继续培养或挂牌出售。",
                            player.displayName or ""),
                        confirmText = "确认下放",
                        confirmColor = {120, 220, 150, 255},
                        onConfirm = function()
                            local ok, demoteErr = YouthManager.demoteToYouth(gameState, player.id)
                            if ok then
                                UI.Toast.Show({
                                    message = (player.displayName or "球员") .. " 已下放至青训队",
                                    variant = "success",
                                })
                                Router.replaceWith("youth")
                            else
                                UI.Toast.Show({ message = demoteErr or "下放失败", variant = "warning" })
                            end
                        end,
                    })
                end,
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

    -- 续约按钮（租借球员不显示）
    local renewBtn
    local isLoanPlayer = player._loanOriginTeamId or player.squadRole == "loaned"
    local suggestedTerms = (not isLoanPlayer) and ContractManager.getSuggestedTerms(player, team, gameState) or nil
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
                -- 可调整薪资和年限的续约面板
                local offerWage = suggestedTerms.wage
                local offerYears = suggestedTerms.years
                local wageLabel = UI.Label {
                    text = PlayerDetail._formatMoney(offerWage) .. " /周",
                    fontSize = 15, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
                }
                local yearsLabel = UI.Label {
                    text = tostring(offerYears) .. " 年",
                    fontSize = 15, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
                }
                local chanceLabel = UI.Label {
                    text = "",
                    fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 4,
                }
                -- 计算接受概率提示
                local function updateChanceHint()
                    local ratio = offerWage / math.max(1, suggestedTerms.wage)
                    local hint
                    if ratio >= 1.5 then hint = "接受概率：极高"
                    elseif ratio >= 1.2 then hint = "接受概率：高"
                    elseif ratio >= 1.0 then hint = "接受概率：中等"
                    elseif ratio >= 0.85 then hint = "接受概率：较低"
                    else hint = "接受概率：很低" end
                    chanceLabel:SetText(hint)
                end
                updateChanceHint()

                BottomSheet.showCustom({
                    title = "续约谈判 - " .. player.displayName,
                    height = 400,
                    children = {
                        -- 薪资调整
                        UI.Label { text = "周薪报价", fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4 },
                        wageLabel,
                        UI.Slider {
                            value = offerWage,
                            min = suggestedTerms.minWage,
                            max = suggestedTerms.maxWage,
                            step = math.max(100, math.floor((suggestedTerms.maxWage - suggestedTerms.minWage) / 20)),
                            width = "100%",
                            trackColor = {38, 46, 71, 255},
                            fillColor = Theme.COLORS.SECONDARY,
                            thumbColor = {255, 255, 255, 255},
                            onChange = function(self, v)
                                offerWage = math.floor(v)
                                wageLabel:SetText(PlayerDetail._formatMoney(offerWage) .. " /周")
                                updateChanceHint()
                            end,
                        },
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", marginTop = 2, marginBottom = 12,
                            children = {
                                UI.Label { text = PlayerDetail._formatMoney(suggestedTerms.minWage), fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                                UI.Label { text = PlayerDetail._formatMoney(suggestedTerms.maxWage), fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            }
                        },
                        -- 年限调整
                        UI.Label { text = "合同年限", fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4 },
                        yearsLabel,
                        UI.Slider {
                            value = offerYears,
                            min = 1,
                            max = 5,
                            step = 1,
                            width = "100%",
                            trackColor = {38, 46, 71, 255},
                            fillColor = Theme.COLORS.PRIMARY,
                            thumbColor = {255, 255, 255, 255},
                            onChange = function(self, v)
                                offerYears = math.floor(v)
                                yearsLabel:SetText(tostring(offerYears) .. " 年")
                            end,
                        },
                        UI.Panel {
                            flexDirection = "row", justifyContent = "space-between", marginTop = 2, marginBottom = 8,
                            children = {
                                UI.Label { text = "1年", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                                UI.Label { text = "5年", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            }
                        },
                        -- 接受概率提示
                        chanceLabel,
                        -- 确认按钮
                        UI.Button {
                            text = "提出续约",
                            variant = "primary",
                            width = "100%", height = 44,
                            marginTop = 12,
                            onClick = function()
                                BottomSheet.close()
                                local success, err = ContractManager.renewContract(
                                    gameState, player.id, offerWage, offerYears)
                                if not success then
                                    gameState:sendMessage({
                                        category = "transfer",
                                        title = "续约提议失败",
                                        body = player.displayName .. "：" .. (err or "条件不满足"),
                                        priority = "normal",
                                    })
                                end
                                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                            end,
                        },
                    },
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
            -- 挂牌外租 / 取消外租挂牌
            PlayerDetail._buildListForLoanBtn(player, isSafe, safetyReason, gameState),
            -- 终止按钮
            terminateBtn,
        }
    }
end

-- 挂牌出售 / 取消挂牌 / 收到报价处理
function PlayerDetail._pickPrimaryIncomingSaleBid(gameState, playerId)
    return TransferManager.pickPrimaryIncomingSaleBid(gameState, playerId)
end

function PlayerDetail._buildIncomingSaleBidPanel(player, gameState, bid)
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local buyerName = buyerTeam and buyerTeam.name or "未知球队"
    local amountText = FinanceManager.formatMoney(bid.amount)

    if bid.status == "pending" then
        return UI.Panel {
            width = "100%", marginBottom = 10,
            children = {
                UI.Label {
                    text = "收到报价：" .. buyerName .. " 出价 " .. amountText,
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
                                local ok = TransferManager.acceptIncomingBid(gameState, bid.id)
                                if ok then
                                    UI.Toast.Show({ message = "已同意报价，等待球员考虑是否接受转会", variant = "success" })
                                else
                                    UI.Toast.Show({ message = "无法接受该报价，请刷新页面后重试", variant = "warning" })
                                end
                                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                            end,
                        },
                        UI.Button {
                            text = "拒绝",
                            width = 70, height = 40,
                            backgroundColor = Theme.COLORS.DANGER,
                            borderRadius = 8, fontSize = 14,
                            color = {255, 255, 255, 255},
                            onClick = function()
                                local ok = TransferManager.rejectIncomingBid(gameState, bid.id)
                                if ok then
                                    UI.Toast.Show({ message = "已拒绝报价", variant = "info" })
                                else
                                    UI.Toast.Show({ message = "无法拒绝该报价，请刷新页面后重试", variant = "warning" })
                                end
                                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                            end,
                        },
                    },
                },
            },
        }
    end

    if bid.status == "counter_pending" then
        return UI.Panel {
            width = "100%", marginBottom = 10,
            children = {
                UI.Label {
                    text = "还价中：" .. buyerName .. " · 你的要价 " .. FinanceManager.formatMoney(bid.counterAskAmount or bid.amount),
                    fontSize = 13, color = Theme.COLORS.WARNING,
                    fontWeight = "bold", marginBottom = 6,
                },
                UI.Label {
                    text = "对方正在考虑你的还价，请等待几天后查看结果。",
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                },
                UI.Button {
                    text = "查看还价进度",
                    width = "100%", height = 40,
                    backgroundColor = Theme.COLORS.ACCENT,
                    borderRadius = 8, fontSize = 14,
                    color = {255, 255, 255, 255},
                    onClick = function()
                        Router.replaceWith("market", { tab = "listed", highlightBidId = bid.id })
                    end,
                },
            },
        }
    end

    if bid.status == "player_considering_sale" then
        local daysLeft = bid.playerConsiderSaleDays or 2
        if bid.playerConsiderSaleDate then
            local daysPassed = TransferManager._daysBetween(bid.playerConsiderSaleDate, gameState.date)
            daysLeft = math.max(0, (bid.playerConsiderSaleDays or 2) - daysPassed)
        end
        local progressText = daysLeft > 0
            and string.format("预计 %d 天后给出答复", daysLeft)
            or "即将给出答复"
        return UI.Panel {
            width = "100%", marginBottom = 10,
            children = {
                UI.Label {
                    text = "球员考虑中：" .. buyerName .. " · " .. amountText,
                    fontSize = 13, color = {255, 180, 60, 255},
                    fontWeight = "bold", marginBottom = 6,
                },
                UI.Label {
                    text = "你已同意报价，球员正在考虑是否接受转会。\n" .. progressText,
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                },
                UI.Button {
                    text = "查看详情",
                    width = "100%", height = 40,
                    backgroundColor = Theme.COLORS.ACCENT,
                    borderRadius = 8, fontSize = 14,
                    color = {255, 255, 255, 255},
                    onClick = function()
                        Router.replaceWith("market", { tab = "listed", highlightBidId = bid.id })
                    end,
                },
            },
        }
    end

    if bid.status == "awaiting_sale_confirmation" then
        return UI.Panel {
            width = "100%", marginBottom = 10,
            children = {
                UI.Label {
                    text = "待确认出售：" .. buyerName .. " · " .. amountText,
                    fontSize = 13, color = Theme.COLORS.SECONDARY,
                    fontWeight = "bold", marginBottom = 6,
                },
                UI.Label {
                    text = "球员已同意加盟，请最终确认或取消此次交易。",
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                },
                UI.Button {
                    text = "确认出售",
                    width = "100%", height = 40,
                    backgroundColor = Theme.COLORS.SECONDARY,
                    borderRadius = 8, fontSize = 14,
                    color = {255, 255, 255, 255},
                    marginBottom = 6,
                    onClick = function()
                        ConfirmDialog.show({
                            title = "最终确认",
                            message = string.format("确认以 %s 将 %s 出售给 %s？\n此操作不可撤销。",
                                amountText, player.displayName, buyerName),
                            confirmText = "确认出售",
                            onConfirm = function()
                                local ok = TransferManager.confirmSale(gameState, bid.id)
                                if ok then
                                    UI.Toast.Show({ message = "交易完成！球员已出售", variant = "success" })
                                    Router.replaceWith("market", { tab = "listed" })
                                else
                                    UI.Toast.Show({ message = "确认失败，请前往转会市场重试", variant = "warning" })
                                    Router.replaceWith("market", { tab = "listed", highlightBidId = bid.id })
                                end
                            end,
                        })
                    end,
                },
                UI.Button {
                    text = "取消交易",
                    width = "100%", height = 40,
                    backgroundColor = {60, 40, 40, 255},
                    borderRadius = 8, fontSize = 14,
                    color = Theme.COLORS.DANGER,
                    onClick = function()
                        local ok = TransferManager.cancelSale(gameState, bid.id)
                        if ok then
                            UI.Toast.Show({ message = "交易已取消", variant = "info" })
                        else
                            UI.Toast.Show({ message = "取消失败，请前往转会市场重试", variant = "warning" })
                        end
                        Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                    end,
                },
            },
        }
    end

    return UI.Panel { height = 0 }
end

function PlayerDetail._buildListForSaleBtn(player, isSafe, safetyReason, gameState)
    if player.listedForLoan then
        return UI.Panel { height = 0 }
    end

    local bid = PlayerDetail._pickPrimaryIncomingSaleBid(gameState, player.id)
    if bid then
        return PlayerDetail._buildIncomingSaleBidPanel(player, gameState, bid)
    end

    local inTransferWindow = TransferManager.isInTransferWindow(gameState)

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
                TransferManager.delistPlayer(gameState, player)
                UI.Toast.Show({ message = "已取消挂牌", variant = "info" })
                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
            end,
        }
    end

    -- 未挂牌 + 安全 → 挂牌出售
    if isSafe then
        return UI.Button {
            text = inTransferWindow and "挂牌出售" or "挂牌出售 (非窗期)",
            width = "100%", height = 44,
            backgroundColor = inTransferWindow and Theme.COLORS.ACCENT or {70, 75, 95, 255},
            borderRadius = 8, fontSize = 14,
            color = inTransferWindow and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
            marginBottom = 10,
            onClick = function()
                local ok, err = TransferManager.listForSale(gameState, player)
                if ok then
                    UI.Toast.Show({
                        message = player.displayName .. " 已挂牌，等待买家报价",
                        variant = "success",
                    })
                    Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                else
                    local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                    if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                        UI.Toast.Show({ message = err or "无法挂牌", variant = "warning" })
                    end
                end
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

function PlayerDetail._buildYouthTransferCard(player, gameState)
    return Theme.Card {
        children = {
            Theme.Subtitle { text = "青训转会" },
            UI.Label {
                text = "挂牌出售后可在转会市场「待售」接收报价；与「释放」不同，出售会走正式转会流程。",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 6, marginBottom = 10,
            },
            PlayerDetail._buildListForSaleBtn(player, true, nil, gameState),
        }
    }
end

function PlayerDetail._buildListForLoanBtn(player, isSafe, safetyReason, gameState)
    if player.squadRole == "loaned" or player.listedForSale then
        return UI.Panel { height = 0 }
    end

    if player.listedForLoan then
        return UI.Button {
            text = "取消外租挂牌",
            width = "100%", height = 44,
            backgroundColor = {80, 80, 100, 255},
            borderRadius = 8, fontSize = 14,
            color = Theme.COLORS.WARNING,
            marginBottom = 10,
            onClick = function()
                TransferManager.delistLoan(player)
                Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
            end,
        }
    end

    local inTransferWindow = TransferManager.isInTransferWindow(gameState)
    if isSafe then
        return UI.Button {
            text = inTransferWindow and "挂牌外租" or "挂牌外租 (非窗期)",
            width = "100%", height = 44,
            backgroundColor = inTransferWindow and Theme.COLORS.SECONDARY or {70, 75, 95, 255},
            borderRadius = 8, fontSize = 14,
            color = inTransferWindow and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
            marginBottom = 10,
            onClick = function()
                local ok, err = TransferManager.listForLoan(gameState, player, 26)
                if ok then
                    UI.Toast.Show({
                        message = player.displayName .. " 已挂牌外租",
                        variant = "success",
                    })
                    Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                else
                    local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                    if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                        UI.Toast.Show({ message = err or "无法挂牌外租", variant = "warning" })
                    end
                end
            end,
        }
    end

    return UI.Button {
        text = "挂牌外租 (阵容不足)",
        width = "100%", height = 44,
        backgroundColor = {50, 55, 75, 255},
        borderRadius = 8, fontSize = 14,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 10,
        disabled = true,
        onClick = function()
            gameState:sendMessage({
                category = "squad",
                title = "无法挂牌外租",
                body = "无法挂牌 " .. player.displayName .. "：" .. (safetyReason or "阵容深度不足"),
                priority = "normal",
            })
        end,
    }
end

function PlayerDetail._buildRecallLoanCard(player, gameState)
    local loan = TransferManager.getLoanForPlayer(gameState, player.id)
    return Theme.Card {
        children = {
            Theme.Subtitle { text = "租借操作" },
            UI.Label {
                text = string.format("剩余租期 %s 周，可提前召回球员。",
                    loan and tostring(TransferManager.formatLoanRemainingWeeks(loan)) or "?"),
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6, marginBottom = 10,
            },
            UI.Button {
                text = "召回球员",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.WARNING,
                borderRadius = 8, fontSize = 14,
                color = {20, 20, 30, 255},
                onClick = function()
                    ConfirmDialog.show({
                        title = "确认召回",
                        message = player.displayName .. " 将提前结束租借并归队，确定召回？",
                        confirmText = "召回",
                        onConfirm = function()
                            TransferManager.recallLoan(gameState, player.id)
                            Router.replaceWith("market", { tab = "loans" })
                        end,
                    })
                end,
            },
        }
    }
end

function PlayerDetail._buildExtendLoanCard(player, gameState)
    local loan = TransferManager.getLoanForPlayer(gameState, player.id)
    local extraWeeks = 26
    local fee = math.floor((player.wage or 0) * extraWeeks * 0.35)
    return Theme.Card {
        children = {
            Theme.Subtitle { text = "租借操作" },
            UI.Label {
                text = string.format("剩余 %s 周 · 续租 %d 周约需 %s",
                    loan and tostring(TransferManager.formatLoanRemainingWeeks(loan)) or "?",
                    extraWeeks, PlayerDetail._formatMoney(fee)),
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6, marginBottom = 10,
            },
            UI.Button {
                text = string.format("续租 %d 周", extraWeeks),
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 8, fontSize = 14,
                color = {255, 255, 255, 255},
                onClick = function()
                    ConfirmDialog.show({
                        title = "确认续租",
                        message = string.format(
                            "续租 %d 周约需 %s，确定继续？",
                            extraWeeks, PlayerDetail._formatMoney(fee)),
                        confirmText = "续租",
                        onConfirm = function()
                            local ok, err = TransferManager.extendLoan(gameState, player.id, extraWeeks)
                            if not ok then
                                gameState:sendMessage({
                                    category = "transfer",
                                    title = "续租失败",
                                    body = err or "条件不满足",
                                    priority = "normal",
                                })
                            else
                                SaveManager.save(gameState, "auto")
                            end
                            Router.replaceWith("player_detail", { playerId = player.id, tab = "contract" })
                        end,
                    })
                end,
            },
        }
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

-- 辅助：按位置获取关键属性（key 用于球探模糊计算）
function PlayerDetail._getKeyAttributes(player)
    local a = player.attributes
    local pos = player.position
    if pos == "GK" then
        return {
            {label="手型", key="handling", value=a.handling}, {label="反应", key="reflexes", value=a.reflexes},
            {label="站位", key="positioning", value=a.positioning}, {label="制空", key="aerial", value=a.aerial},
            {label="镇定", key="composure", value=a.composure}, {label="决策", key="decisions", value=a.decisions},
        }
    elseif pos == "CB" then
        return {
            {label="防守", key="defending", value=a.defending}, {label="抢断", key="tackling", value=a.tackling},
            {label="制空", key="aerial", value=a.aerial}, {label="力量", key="strength", value=a.strength},
            {label="站位", key="positioning", value=a.positioning}, {label="镇定", key="composure", value=a.composure},
        }
    elseif pos == "LB" or pos == "RB" then
        return {
            {label="防守", key="defending", value=a.defending}, {label="抢断", key="tackling", value=a.tackling},
            {label="速度", key="speed", value=a.speed}, {label="体能", key="stamina", value=a.stamina},
            {label="传球", key="passing", value=a.passing}, {label="盘带", key="dribbling", value=a.dribbling},
        }
    elseif pos == "CDM" then
        return {
            {label="抢断", key="tackling", value=a.tackling}, {label="防守", key="defending", value=a.defending},
            {label="传球", key="passing", value=a.passing}, {label="站位", key="positioning", value=a.positioning},
            {label="体能", key="stamina", value=a.stamina}, {label="力量", key="strength", value=a.strength},
        }
    elseif pos == "ST" then
        return {
            {label="射门", key="shooting", value=a.shooting}, {label="镇定", key="composure", value=a.composure},
            {label="站位", key="positioning", value=a.positioning}, {label="速度", key="speed", value=a.speed},
            {label="盘带", key="dribbling", value=a.dribbling}, {label="制空", key="aerial", value=a.aerial},
        }
    elseif pos == "LW" or pos == "RW" then
        return {
            {label="速度", key="speed", value=a.speed}, {label="盘带", key="dribbling", value=a.dribbling},
            {label="敏捷", key="agility", value=a.agility}, {label="射门", key="shooting", value=a.shooting},
            {label="传球", key="passing", value=a.passing}, {label="视野", key="vision", value=a.vision},
        }
    else -- CM/CAM
        return {
            {label="传球", key="passing", value=a.passing}, {label="视野", key="vision", value=a.vision},
            {label="体能", key="stamina", value=a.stamina}, {label="决策", key="decisions", value=a.decisions},
            {label="盘带", key="dribbling", value=a.dribbling}, {label="射门", key="shooting", value=a.shooting},
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
                                                width = math.floor(player:displayOverall() / 99 * 100) .. "%",
                                                height = "100%", backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 6,
                                            },
                                        }
                                    },
                                    UI.Label { text = tostring(player:displayOverall()), fontSize = 13, color = Theme.COLORS.SECONDARY,
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
                            (function()
                                local part = TrainingManager.getParticipationSummary(player, gameState)
                                local partColor = part.applies
                                    and (part.factor >= 0.99 and Theme.COLORS.SECONDARY
                                        or (part.factor >= 0.5 and Theme.COLORS.WARNING or Theme.COLORS.DANGER))
                                    or Theme.COLORS.ACCENT
                                return UI.Label {
                                    text = part.detailLabel,
                                    fontSize = 11, color = partColor, marginTop = 6,
                                }
                            end)(),
                        }
                    },
                }
            },

            -- 球员特性
            Theme.Card {
                children = (function()
                    local children = {}
                    local identity = player.getLegendIdentity and player:getLegendIdentity()
                    if identity then
                        table.insert(children, Theme.Subtitle { text = "传奇身份" })
                        table.insert(children, UI.Panel {
                            backgroundColor = {72, 48, 18, 255},
                            borderRadius = 12,
                            paddingLeft = 10, paddingRight = 10,
                            paddingTop = 6, paddingBottom = 6,
                            marginTop = 6, marginBottom = 8,
                            children = {
                                UI.Label {
                                    text = identity.name .. " · " .. identity.desc,
                                    fontSize = 11,
                                    color = {255, 210, 120, 255},
                                },
                            },
                        })
                    end
                    table.insert(children, Theme.Subtitle {
                        text = player.isLegend and "传奇特质" or "球员特性",
                        marginTop = identity and 4 or 0,
                    })
                    table.insert(children, UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 6,
                        children = PlayerDetail._buildTraits(player),
                    })
                    return children
                end)(),
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

    local part = TrainingManager.getParticipationSummary(player, gameState)
    local partColor = part.applies
        and (part.factor >= 0.99 and Theme.COLORS.SECONDARY
            or (part.factor >= 0.5 and Theme.COLORS.WARNING or Theme.COLORS.DANGER))
        or Theme.COLORS.ACCENT

    return UI.Panel {
        width = "100%",
        children = {
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "成长效率" },
                    UI.Panel {
                        marginTop = 6,
                        children = {
                            PlayerDetail._infoRow("出场 / 配额",
                                part.applies and string.format("%d / %d 场", part.apps, part.quota) or "青年期不限",
                                partColor),
                            PlayerDetail._infoRow("训练效率",
                                part.applies and string.format("%d%%", math.floor(part.factor * 100 + 0.5)) or "100%",
                                partColor),
                            UI.Label {
                                text = part.applies
                                    and "22 岁起需俱乐部正式赛出场；出场累计至配额后满效训练。"
                                    or "21 岁及以下不受出场限制；青训同日程略快于一线队。",
                                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                            },
                        }
                    },
                }
            },

            -- 当前状态
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "个人训练" },
                    UI.Panel {
                        marginTop = 6,
                        children = {
                            PlayerDetail._infoRow("当前重点", focusLabel, Theme.COLORS.ACCENT),
                            PlayerDetail._infoRow("球队方案", Constants.TRAINING_FOCUS_NAMES and Constants.TRAINING_FOCUS_NAMES[teamFocus] or teamFocus, Theme.COLORS.TEXT_MUTED),
                            PlayerDetail._infoRow("体能", tostring(math.floor(player.fitness)) .. "%",
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

            PlayerDetail._buildPositionTrainingCard(player),
        }
    }
end

function PlayerDetail._buildPositionTrainingCard(player)
    local posLabel = PositionFit.formatNaturalPositions(player, Constants.POSITION_NAMES)
    local target = player.positionTrainingTarget
    local progress = player.positionTrainingProgress or 0
    local drill = player.positionTrainingDrillProgress or 0

    local statusText
    if target then
        local targetName = Constants.POSITION_NAMES[target] or target
        statusText = string.format("学习 %s · %d%%（训练 %d/30，实战 +5%%/场）",
            targetName, progress, drill)
    else
        statusText = "未设置学习目标；纯训练最多 30%，需目标槽位出场练满"
    end

    local actionButtons = {}
    if target then
        table.insert(actionButtons, UI.Button {
            text = "取消学习",
            width = "100%", height = 40,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
            fontSize = 13, color = Theme.COLORS.DANGER, marginTop = 8,
            onClick = function()
                PositionTrainingManager.clearTarget(player)
                Router.replaceWith("player_detail", { playerId = player.id, tab = "training" })
            end,
        })
    else
        local learnable = PositionFit.getLearnablePositions(player)
        if #learnable > 0 then
            table.insert(actionButtons, UI.Button {
                text = "选择学习目标",
                width = "100%", height = 40,
                backgroundColor = Theme.COLORS.PRIMARY,
                borderRadius = 8, fontSize = 13,
                color = Theme.COLORS.TEXT_PRIMARY, marginTop = 8,
                onClick = function()
                    PlayerDetail._showPositionTargetMenu(player, learnable)
                end,
            })
        else
            table.insert(actionButtons, UI.Label {
                text = "已达位置上限或无可学位置",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
            })
        end
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "位置训练" },
            UI.Label {
                text = "擅长位置：" .. posLabel,
                fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 6,
            },
            UI.Label {
                text = statusText,
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
            },
            target and UI.Panel {
                width = "100%", height = 8,
                backgroundColor = {38, 46, 71, 255}, borderRadius = 4,
                marginTop = 8, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = progress .. "%",
                        height = "100%",
                        backgroundColor = Theme.COLORS.ACCENT,
                        borderRadius = 4,
                    },
                },
            } or UI.Panel { height = 0 },
            UI.Panel { width = "100%", children = actionButtons },
        }
    }
end

function PlayerDetail._showPositionTargetMenu(player, learnable)
    local menuItems = {
        UI.Label {
            text = "选择学习目标位置",
            fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold", marginBottom = 12, textAlign = "center",
        },
    }
    for _, pos in ipairs(learnable) do
        local label = Constants.POSITION_NAMES[pos] or pos
        table.insert(menuItems, UI.Button {
            text = label .. " (" .. pos .. ")",
            width = "100%", height = 40,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 8, fontSize = 14,
            color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 4,
            onClick = function()
                PositionTrainingManager.setTarget(player, pos)
                UI.CloseOverlay()
                Router.replaceWith("player_detail", { playerId = player.id, tab = "training" })
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

-- 辅助：构建球员特性标签
function PlayerDetail._buildTraits(player)
    local details = player.getTraitDetails and player:getTraitDetails() or {}
    if #details == 0 then
        return {
            UI.Label { text = "暂无特性标签", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
        }
    end
    local items = {}
    for _, trait in ipairs(details) do
        local label = trait.name or trait.id
        if trait.desc and trait.desc ~= "" then
            label = label .. " · " .. trait.desc
        end
        local bg = {38, 60, 90, 255}
        local fg = Theme.COLORS.ACCENT
        if trait.pool == "legend" then
            bg = trait.legendExclusive and {68, 42, 98, 255} or {48, 58, 88, 255}
            fg = trait.legendExclusive and {220, 180, 255, 255} or {180, 200, 255, 255}
        end
        local prefix = trait.legendExclusive and "★ " or (trait.pool == "legend" and "◆ " or "")
        table.insert(items, UI.Panel {
            backgroundColor = bg,
            borderRadius = 12,
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 4, paddingBottom = 4,
            marginRight = 6, marginBottom = 4,
            children = {
                UI.Label { text = prefix .. label, fontSize = 11, color = fg },
            },
        })
    end
    return items
end

return PlayerDetail
