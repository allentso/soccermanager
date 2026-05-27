-- ui/screens/inbox.lua
-- 收件箱页面 - 带分类标签、消息详情、动作按钮、上下文跳转

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local Inbox = {}

-- 消息分类定义
local CATEGORIES = {
    { key = "all",      label = "全部" },
    { key = "match",    label = "比赛" },
    { key = "injury",   label = "伤病" },
    { key = "board",    label = "公告" },
    { key = "transfer", label = "转会" },
}

-- 消息分类归属映射
local CATEGORY_MAP = {
    match_result = "match",
    match_preview = "match",
    pre_match = "match",
    injury = "injury",
    welcome = "board",
    league = "board",
    board = "board",
    system = "board",
    finance = "board",
    training = "board",
    media = "board",
    transfer = "transfer",
    scout = "transfer",
    contract = "transfer",
}

-- 分类颜色
local CATEGORY_COLORS = {
    match = {33, 150, 243, 255},
    injury = {229, 57, 53, 255},
    board = {76, 175, 80, 255},
    transfer = {255, 153, 0, 255},
}

-- 分类图标文字
local CATEGORY_ICONS = {
    match = "[赛]",
    injury = "[伤]",
    board = "[告]",
    transfer = "[转]",
}

-- 优先级颜色
local PRIORITY_COLORS = {
    high = {255, 87, 34, 255},
    normal = {33, 150, 243, 255},
    low = {115, 128, 153, 255},
}

-- 优先级文本
local PRIORITY_LABELS = {
    high = "紧急",
    normal = "普通",
    low = "低",
}

------------------------------------------------------
-- 动作处理器：根据 actionId 执行跳转或操作
------------------------------------------------------
local ACTION_HANDLERS = {
    -- 导航类
    view_player = function(data)
        if data and data.playerId then
            Router.navigate("player_detail", { playerId = data.playerId })
        end
    end,
    renew_contract = function(data)
        if data and data.playerId then
            Router.navigate("player_detail", { playerId = data.playerId, tab = "contract" })
        end
    end,
    view_squad = function()
        Router.navigate("squad")
    end,
    view_finance = function()
        Router.navigate("finance")
    end,
    view_transfer = function()
        Router.navigate("market")
    end,
    view_match = function(data)
        Router.navigate("match_result", data)
    end,
    view_training = function()
        Router.navigate("training")
    end,
    view_league = function()
        Router.navigate("league")
    end,

    -- 决策类：直接影响游戏状态
    grant_raise = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId then return end
        local player = gameState.players[data.playerId]
        if not player then return end
        local raisePercent = data.raisePercent or 20
        player.wage = math.floor(player.wage * (1 + raisePercent / 100))
        player.morale = math.min(100, (player.morale or 60) + 12)
        gameState:sendMessage({
            category = "contract",
            title = "加薪批准",
            body = string.format("已批准 %s 加薪 %d%%，新周薪 %s。",
                player.displayName, raisePercent,
                player.wage >= 1000 and string.format("%.0fK", player.wage/1000) or tostring(player.wage)),
            priority = "normal",
        })
        Router.replaceWith("inbox")
    end,
    deny_raise = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId then return end
        local player = gameState.players[data.playerId]
        if not player then return end
        player.morale = math.max(0, (player.morale or 60) - 10)
        gameState:sendMessage({
            category = "contract",
            title = "加薪拒绝",
            body = string.format("已拒绝 %s 的加薪请求。球员士气下降。", player.displayName),
            priority = "normal",
        })
        Router.replaceWith("inbox")
    end,
    promote_role = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId then return end
        local player = gameState.players[data.playerId]
        if not player then return end
        local newRole = data.newRole or "rotation"
        local MoraleManager = require("scripts/systems/morale_manager")
        local oldRole = player.squadRole
        player.squadRole = newRole
        MoraleManager.onSquadRoleChange(player, oldRole, newRole)
        gameState:sendMessage({
            category = "squad",
            title = "角色调整",
            body = string.format("已将 %s 的阵容角色提升为「%s」。", player.displayName, data.roleLabel or newRole),
            priority = "normal",
        })
        Router.replaceWith("inbox")
    end,
    deny_promotion = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId then return end
        local player = gameState.players[data.playerId]
        if not player then return end
        player.morale = math.max(0, (player.morale or 60) - 8)
        Router.replaceWith("inbox")
    end,
    accept_loan_offer = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId or not data.targetTeamId then return end
        local player = gameState.players[data.playerId]
        if not player then return end
        player.squadRole = "loaned"
        player._loanedTo = data.targetTeamId
        player.morale = math.min(100, (player.morale or 60) + 5)
        gameState:sendMessage({
            category = "transfer",
            title = "租借达成",
            body = string.format("%s 已租借至 %s。", player.displayName, data.targetTeamName or "对方球队"),
            priority = "normal",
        })
        Router.replaceWith("inbox")
    end,
    reject_loan_offer = function(data)
        local gameState = _G.gameState
        if not gameState or not data or not data.playerId then return end
        local player = gameState.players[data.playerId]
        if player then
            player.morale = math.max(0, (player.morale or 60) - 5)
        end
        Router.replaceWith("inbox")
    end,
}

------------------------------------------------------
-- 消息详情面板
------------------------------------------------------
function Inbox._showDetail(msg, currentTab)
    local gameState = _G.gameState
    local msgCat = CATEGORY_MAP[msg.category] or "board"
    local catColor = CATEGORY_COLORS[msgCat] or Theme.COLORS.TEXT_MUTED
    local priorityLabel = PRIORITY_LABELS[msg.priority] or "普通"
    local priorityColor = PRIORITY_COLORS[msg.priority] or Theme.COLORS.PRIMARY

    -- 标记已读
    msg.read = true

    local contentChildren = {}

    -- 标题区
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 12,
        children = {
            -- 分类标签
            UI.Panel {
                width = 36, height = 36,
                borderRadius = 18,
                backgroundColor = {catColor[1], catColor[2], catColor[3], 50},
                alignItems = "center",
                justifyContent = "center",
                marginRight = 10,
                children = {
                    UI.Label {
                        text = CATEGORY_ICONS[msgCat] or "[信]",
                        fontSize = 12,
                        color = catColor,
                    }
                }
            },
            -- 标题+优先级
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                children = {
                    UI.Label {
                        text = msg.title or "消息",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        marginTop = 3,
                        children = {
                            -- 优先级标签
                            UI.Panel {
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 2, paddingBottom = 2,
                                borderRadius = 4,
                                backgroundColor = {priorityColor[1], priorityColor[2], priorityColor[3], 40},
                                marginRight = 8,
                                children = {
                                    UI.Label {
                                        text = priorityLabel,
                                        fontSize = 10,
                                        color = priorityColor,
                                    }
                                }
                            },
                            -- 日期
                            UI.Label {
                                text = msg.date and string.format("%d年%d月%d日", msg.date.year, msg.date.month, msg.date.day) or "",
                                fontSize = 11,
                                color = Theme.COLORS.TEXT_MUTED,
                            },
                        }
                    },
                }
            },
        }
    })

    -- 分隔线
    table.insert(contentChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Theme.COLORS.BORDER,
        marginBottom = 12,
    })

    -- 正文
    table.insert(contentChildren, UI.Label {
        text = msg.body or "",
        fontSize = 14,
        color = Theme.COLORS.TEXT_SECONDARY,
        marginBottom = 16,
    })

    -- 动作按钮区
    local hasActions = msg.actions and #msg.actions > 0
    if hasActions then
        table.insert(contentChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.COLORS.BORDER,
            marginBottom = 12,
        })

        for _, act in ipairs(msg.actions) do
            table.insert(contentChildren, UI.Button {
                text = act.label or "操作",
                width = "100%",
                height = 40,
                backgroundColor = Theme.COLORS.PRIMARY,
                borderRadius = 8,
                fontSize = 14,
                color = Theme.COLORS.TEXT_PRIMARY,
                marginBottom = 6,
                onClick = function()
                    UI.CloseOverlay()
                    local handler = ACTION_HANDLERS[act.actionId]
                    if handler then
                        handler(act.data)
                    end
                end,
            })
        end
    end

    -- 智能上下文跳转（根据消息类别自动推导）
    local contextActions = Inbox._getContextActions(msg)
    if #contextActions > 0 and not hasActions then
        table.insert(contentChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.COLORS.BORDER,
            marginBottom = 12,
        })

        for _, ctx in ipairs(contextActions) do
            table.insert(contentChildren, UI.Button {
                text = ctx.label,
                width = "100%",
                height = 38,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 8,
                fontSize = 13,
                color = ctx.color or Theme.COLORS.ACCENT,
                marginBottom = 4,
                onClick = function()
                    UI.CloseOverlay()
                    ctx.action()
                end,
            })
        end
    end

    -- 删除按钮
    table.insert(contentChildren, UI.Button {
        text = "删除消息",
        width = "100%",
        height = 36,
        backgroundColor = Theme.COLORS.TRANSPARENT,
        borderRadius = 8,
        fontSize = 12,
        color = Theme.COLORS.DANGER,
        marginTop = 8,
        onClick = function()
            UI.CloseOverlay()
            -- 从收件箱中删除
            if gameState then
                for i, m in ipairs(gameState.inbox) do
                    if m == msg then
                        table.remove(gameState.inbox, i)
                        break
                    end
                end
            end
            Router.replaceWith("inbox", { tab = currentTab })
        end,
    })

    BottomSheet.showCustom({
        children = contentChildren,
        showCancel = true,
    })
end

------------------------------------------------------
-- 智能上下文推导：根据消息分类生成跳转按钮
------------------------------------------------------
function Inbox._getContextActions(msg)
    local actions = {}
    local cat = msg.category

    -- 合同相关 → 跳转球员详情/阵容
    if cat == "contract" then
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.PRIMARY,
                action = function()
                    Router.navigate("player_detail", { playerId = msg.extra.playerId })
                end,
            })
        end
        table.insert(actions, {
            label = "查看阵容",
            color = Theme.COLORS.TEXT_SECONDARY,
            action = function() Router.navigate("squad") end,
        })

    -- 转会相关 → 跳转市场
    elseif cat == "transfer" then
        table.insert(actions, {
            label = "前往转会市场",
            color = Theme.COLORS.ACCENT,
            action = function() Router.navigate("market") end,
        })
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.PRIMARY,
                action = function()
                    Router.navigate("player_detail", { playerId = msg.extra.playerId })
                end,
            })
        end

    -- 球探报告 → 跳转市场/球员
    elseif cat == "scout" then
        table.insert(actions, {
            label = "前往转会市场",
            color = Theme.COLORS.ACCENT,
            action = function() Router.navigate("market") end,
        })

    -- 伤病 → 跳转阵容
    elseif cat == "injury" then
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.PRIMARY,
                action = function()
                    Router.navigate("player_detail", { playerId = msg.extra.playerId })
                end,
            })
        end
        table.insert(actions, {
            label = "查看阵容",
            color = Theme.COLORS.TEXT_SECONDARY,
            action = function() Router.navigate("squad") end,
        })

    -- 比赛相关 → 跳转赛事
    elseif cat == "match_result" or cat == "match_preview" or cat == "pre_match" then
        table.insert(actions, {
            label = "查看赛事",
            color = Theme.COLORS.PRIMARY,
            action = function() Router.navigate("league") end,
        })

    -- 财务 → 跳转财务
    elseif cat == "finance" then
        table.insert(actions, {
            label = "查看财务",
            color = Theme.COLORS.SECONDARY,
            action = function() Router.navigate("finance") end,
        })

    -- 训练 → 跳转训练
    elseif cat == "training" then
        table.insert(actions, {
            label = "查看训练",
            color = Theme.COLORS.SECONDARY,
            action = function() Router.navigate("training") end,
        })

    -- 董事会 → 跳主页
    elseif cat == "board" then
        table.insert(actions, {
            label = "查看主页",
            color = Theme.COLORS.TEXT_SECONDARY,
            action = function() Router.navigate("dashboard") end,
        })
    end

    return actions
end

------------------------------------------------------
-- 页面构建
------------------------------------------------------
function Inbox.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    -- 当前选中分类
    local currentTab = (params and params.tab) or "all"

    -- 根据分类过滤消息
    local filteredMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        local msgCat = CATEGORY_MAP[msg.category] or "board"
        if currentTab == "all" or msgCat == currentTab then
            table.insert(filteredMsgs, msg)
        end
    end

    -- 统计各分类未读数
    local unreadCounts = { all = 0, match = 0, injury = 0, board = 0, transfer = 0 }
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read then
            unreadCounts.all = unreadCounts.all + 1
            local cat = CATEGORY_MAP[msg.category] or "board"
            if unreadCounts[cat] then
                unreadCounts[cat] = unreadCounts[cat] + 1
            end
        end
    end

    -- 构建分类标签
    local tabButtons = {}
    for _, cat in ipairs(CATEGORIES) do
        local isActive = cat.key == currentTab
        local unread = unreadCounts[cat.key] or 0
        local labelText = cat.label
        if unread > 0 then
            labelText = cat.label .. "(" .. unread .. ")"
        end
        table.insert(tabButtons, UI.Button {
            text = labelText,
            height = 34,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 17,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 6,
            onClick = function()
                Router.replaceWith("inbox", { tab = cat.key })
            end,
        })
    end

    -- 构建消息行
    local msgRows = {}
    local maxShow = math.min(80, #filteredMsgs)

    for i = 1, maxShow do
        local msg = filteredMsgs[i]
        local isUnread = not msg.read
        local msgCat = CATEGORY_MAP[msg.category] or "board"
        local catColor = CATEGORY_COLORS[msgCat] or Theme.COLORS.TEXT_MUTED
        local catIcon = CATEGORY_ICONS[msgCat] or "[信]"
        local hasActions = (msg.actions and #msg.actions > 0)

        table.insert(msgRows, UI.Panel {
            width = "100%",
            minHeight = 64,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12,
            paddingRight = 12,
            paddingTop = 8,
            paddingBottom = 8,
            backgroundColor = isUnread and {26, 38, 64, 255} or {0, 0, 0, 0},
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                -- 分类图标
                UI.Panel {
                    width = 32, height = 32,
                    borderRadius = 16,
                    backgroundColor = {catColor[1], catColor[2], catColor[3], 40},
                    alignItems = "center",
                    justifyContent = "center",
                    marginRight = 10,
                    children = {
                        UI.Label {
                            text = catIcon,
                            fontSize = 11,
                            color = catColor,
                        }
                    }
                },
                -- 内容区
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = msg.title or "消息",
                            fontSize = 14,
                            color = isUnread and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                            fontWeight = isUnread and "bold" or "normal",
                        },
                        UI.Label {
                            text = msg.body and (#msg.body > 40 and msg.body:sub(1, 40) .. "..." or msg.body) or "",
                            fontSize = 12,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 3,
                        },
                    }
                },
                -- 右侧信息
                UI.Panel {
                    alignItems = "flex-end",
                    marginLeft = 8,
                    children = {
                        -- 日期
                        UI.Label {
                            text = msg.date and string.format("%d/%d", msg.date.month, msg.date.day) or "",
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                        },
                        -- 未读指示 / 动作指示
                        (isUnread or hasActions) and UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            marginTop = 4,
                            children = {
                                -- 未读圆点
                                isUnread and UI.Panel {
                                    width = 8, height = 8,
                                    borderRadius = 4,
                                    backgroundColor = PRIORITY_COLORS[msg.priority] or Theme.COLORS.PRIMARY,
                                    marginRight = hasActions and 4 or 0,
                                } or UI.Panel { width = 0 },
                                -- 有动作标识
                                hasActions and UI.Label {
                                    text = "→",
                                    fontSize = 11,
                                    color = Theme.COLORS.ACCENT,
                                } or UI.Panel { width = 0 },
                            }
                        } or UI.Panel { height = 0 },
                    }
                },
            },
            onClick = function()
                Inbox._showDetail(msg, currentTab)
            end,
        })
    end

    if #msgRows == 0 then
        table.insert(msgRows, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无消息", fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
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
                        onClick = function() Router.navigate("dashboard") end,
                    },
                    UI.Label {
                        text = "收件箱",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Button {
                        text = "全读",
                        width = 50, height = 32,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 12, color = Theme.COLORS.PRIMARY,
                        onClick = function()
                            for _, msg in ipairs(gameState.inbox) do msg.read = true end
                            Router.replaceWith("inbox", { tab = currentTab })
                        end,
                    },
                }
            },

            -- 二级导航
            Theme.MoreSubNav("inbox"),

            -- 分类标签栏
            UI.Panel {
                width = "100%",
                height = 48,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_HEADER,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = tabButtons,
            },

            -- 消息列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = msgRows,
            },

            -- 底部导航
            Theme.MainNav("more"),
        }
    }
end

return Inbox
