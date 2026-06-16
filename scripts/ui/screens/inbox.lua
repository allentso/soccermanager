-- ui/screens/inbox.lua
-- 收件箱页面 - 带分类标签、优先级视觉层级、消息详情、动作按钮
-- 设计：紧急红/重要橙/普通蓝 三级优先级 / 可操作消息突出 / 语义色分类

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local FinanceManager = require("scripts/systems/finance_manager")
local MessageManager = require("scripts/systems/message_manager")

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
    -- 比赛类
    match_result = "match",
    match_preview = "match",
    pre_match = "match",
    match_report = "match",
    -- 伤病类
    injury = "injury",
    injury_news = "injury",
    -- 转会类
    transfer = "transfer",
    transfer_news = "transfer",
    scout = "transfer",
    contract = "transfer",
    job = "transfer",
    transfers = "transfer",
    -- 公告/其他（board）
    welcome = "board",
    league = "board",
    league_news = "board",
    board = "board",
    system = "board",
    finance = "board",
    training = "board",
    media = "board",
    morale = "board",
    squad = "board",
    youth = "board",
    staff = "board",
    season_news = "board",
    ucl_news = "board",
    world_cup = "board",
    world_cup_news = "board",
    manager_news = "board",
    milestone = "board",
    form = "board",
    defense = "board",
    attack = "board",
    -- 财务子分类（归入公告）
    wage = "board",
    ticket = "board",
    prize = "board",
    sponsor = "board",
    broadcast = "board",
    merchandise = "board",
    maintenance = "board",
    facility = "board",
    injection = "board",
    commercial = "board",
}

-- 分类颜色（语义色）
local CATEGORY_COLORS = {
    match = Theme.COLORS.GOLD,
    injury = Theme.COLORS.DANGER,
    board = Theme.COLORS.FINANCE_GREEN,
    transfer = Theme.COLORS.MATCH_ORANGE,
}

-- 分类图标
local CATEGORY_ICONS = {
    match = "⚽",
    injury = "🏥",
    board = "📋",
    transfer = "🔄",
}

-- 分类标签文字
local CATEGORY_LABELS = {
    match = "比赛",
    injury = "伤病",
    board = "公告",
    transfer = "转会",
}

-- 旧存档兼容：templateId 作为 title 时的中文映射
local TITLE_FALLBACK = {
    scout_report_ready = "球探报告完成",
    scout_report = "球探报告",
    youth_signed = "青训签约",
    youth_promoted = "青训提拔",
    youth_demoted = "下放青训",
    finance_warning = "财务警告",
    finance_crisis = "财务危机",
    contract_expiring_6m = "合同到期提醒",
    contract_expiring_3m = "合同即将到期",
    contract_expired = "球员离队",
    transfer_bid_received = "收到报价",
    transfer_completed = "转会完成",
    training_growth = "训练提升",
    training_injury = "训练伤病",
    injury_recovered = "伤愈复出",
    injury_season_ending = "赛季报销",
    board_objective = "董事会目标",
    board_warning = "董事会警告",
    match_result = "比赛结果",
    match_preview = "赛前预告",
}

-- 优先级颜色（critical > high > normal > low）
local PRIORITY_COLORS = {
    critical = Theme.COLORS.DANGER,
    high = Theme.COLORS.DANGER,
    normal = Theme.COLORS.GOLD,
    low = Theme.COLORS.TEXT_MUTED,
}

local PRIORITY_LABELS = {
    critical = "重大",
    high = "紧急",
    normal = "普通",
    low = "低",
}

local PRIORITY_ICONS = {
    critical = "🔴",
    high = "🟠",
    normal = "🔵",
    low = "⚪",
}

------------------------------------------------------
-- 动作处理器：根据 actionId 执行跳转或操作
------------------------------------------------------
local MessageActionHandlers = require("scripts/ui/message_action_handlers")

local function runInboxAction(actionId, data)
    local gameState = _G.gameState
    if not gameState then return end
    local ok, route, params = MessageActionHandlers.run(gameState, actionId, data)
    if not ok then return end
    if route == "dashboard" then
        Router.replaceWith("dashboard")
    elseif route then
        Router.navigate(route, params)
    else
        Router.replaceWith("inbox")
    end
end

local ACTION_HANDLERS = setmetatable({}, {
    __index = function(_, key)
        return function(data)
            runInboxAction(key, data)
        end
    end,
})

------------------------------------------------------
-- 消息详情面板
------------------------------------------------------
function Inbox._showDetail(msg, currentTab)
    local gameState = _G.gameState
    local msgCat = CATEGORY_MAP[msg.category] or "board"
    local catColor = CATEGORY_COLORS[msgCat] or Theme.COLORS.TEXT_MUTED
    local catIcon = CATEGORY_ICONS[msgCat] or "📋"
    local priorityLabel = PRIORITY_LABELS[msg.priority] or "普通"
    local priorityColor = PRIORITY_COLORS[msg.priority] or Theme.COLORS.GOLD
    local priorityIcon = PRIORITY_ICONS[msg.priority] or "🔵"

    -- 旧存档兼容：WC邀请消息如果没有actions，从正文中解析国家并动态生成
    if msg.title == "🏆 国家队主教练邀请" and (not msg.actions or #msg.actions == 0) then
        local WorldCup = require("scripts/systems/world_cup")
        local parsedActions = {}
        -- 从正文解析国家名，格式如 "  1. 英格兰（L组）"
        for line in (msg.body or ""):gmatch("[^\n]+") do
            local name = line:match("^%s*%d+%.%s*(.-)（")
            if name then
                -- 反查FIFA代码
                local code = WorldCup._getNationCodeByName(name)
                if code then
                    table.insert(parsedActions, {
                        label = "执教" .. name,
                        actionId = "accept_nt_coach",
                        data = { nation = code },
                    })
                end
            end
        end
        if #parsedActions > 0 then
            table.insert(parsedActions, { label = "全部婉拒", actionId = "decline_nt_coach", data = {} })
            msg.actions = parsedActions
        end
    end

    -- 标记已读
    msg.read = true

    local contentChildren = {}

    -- 标题区（重新设计：语义色突出）
    table.insert(contentChildren, UI.Panel {
        width = "100%",
        marginBottom = 14,
        children = {
            -- 顶部标签行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 8,
                children = {
                    -- 分类标签
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        backgroundColor = {catColor[1], catColor[2], catColor[3], 25},
                        borderRadius = 6,
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 4, paddingBottom = 4,
                        marginRight = 8,
                        children = {
                            UI.Label {
                                text = catIcon .. " " .. (CATEGORY_LABELS[msgCat] or "消息"),
                                fontSize = 11,
                                color = catColor,
                                fontWeight = "bold",
                            }
                        }
                    },
                    -- 优先级标签
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        backgroundColor = {priorityColor[1], priorityColor[2], priorityColor[3], 25},
                        borderRadius = 6,
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 3, paddingBottom = 3,
                        children = {
                            UI.Label {
                                text = priorityIcon .. " " .. priorityLabel,
                                fontSize = 10,
                                color = priorityColor,
                            }
                        }
                    },
                    -- 空白填充
                    UI.Panel { flexGrow = 1 },
                    -- 日期
                    UI.Label {
                        text = msg.date and string.format("%d/%d/%d", msg.date.year, msg.date.month, msg.date.day) or "",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
            -- 标题
            UI.Label {
                text = TITLE_FALLBACK[msg.title] or msg.title or "消息",
                fontSize = 17,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
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

    -- 动作按钮区（如有）
    local hasActions = msg.actions and #msg.actions > 0
    if hasActions then
        table.insert(contentChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.COLORS.BORDER,
            marginBottom = 12,
        })

        for idx, act in ipairs(msg.actions) do
            -- 第一个动作用主色，后续用次级
            local btnColor = idx == 1 and Theme.COLORS.GOLD or Theme.COLORS.BG_SURFACE
            local txtColor = idx == 1 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY
            table.insert(contentChildren, UI.Button {
                text = act.label or "操作",
                width = "100%",
                height = 40,
                backgroundColor = btnColor,
                borderRadius = 8,
                fontSize = 14,
                color = txtColor,
                fontWeight = idx == 1 and "bold" or "normal",
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

    -- 智能上下文跳转
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
                backgroundColor = Theme.COLORS.BG_SURFACE,
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

    -- 动态计算面板高度：正文 + 动作按钮
    local sheetHeight = 400
    if msg.actions and #msg.actions > 0 then
        sheetHeight = 400 + #msg.actions * 48
    end
    -- 正文较长时额外增高
    local bodyLen = msg.body and #msg.body or 0
    if bodyLen > 200 then
        sheetHeight = sheetHeight + 60
    end
    -- 限制最大高度为屏幕 85%（BottomSheet 内部 ScrollView 保证可滚动）
    sheetHeight = math.min(720, sheetHeight)

    BottomSheet.showCustom({
        children = contentChildren,
        showCancel = true,
        height = sheetHeight,
    })
end

------------------------------------------------------
-- 智能上下文推导
------------------------------------------------------
function Inbox._getContextActions(msg)
    local actions = {}
    local cat = msg.category

    if cat == "contract" then
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.GOLD,
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
    elseif cat == "transfer" then
        table.insert(actions, {
            label = "前往转会市场",
            color = Theme.COLORS.MATCH_ORANGE,
            action = function() Router.navigate("market") end,
        })
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.GOLD,
                action = function()
                    Router.navigate("player_detail", { playerId = msg.extra.playerId })
                end,
            })
        end
    elseif cat == "scout" then
        table.insert(actions, {
            label = "前往转会市场",
            color = Theme.COLORS.MATCH_ORANGE,
            action = function() Router.navigate("market") end,
        })
    elseif cat == "injury" then
        if msg.extra and msg.extra.playerId then
            table.insert(actions, {
                label = "查看球员",
                color = Theme.COLORS.GOLD,
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
    elseif cat == "match_result" or cat == "match_preview" or cat == "pre_match" then
        table.insert(actions, {
            label = "查看赛事",
            color = Theme.COLORS.GOLD,
            action = function() Router.navigate("league") end,
        })
    elseif cat == "finance" then
        table.insert(actions, {
            label = "查看财务",
            color = Theme.COLORS.FINANCE_GREEN,
            action = function() Router.navigate("finance") end,
        })
    elseif cat == "training" then
        table.insert(actions, {
            label = "查看训练",
            color = Theme.COLORS.FINANCE_GREEN,
            action = function() Router.navigate("training") end,
        })
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

    local currentTab = (params and params.tab) or "all"

    -- 过滤
    local filteredMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        local msgCat = CATEGORY_MAP[msg.category] or "board"
        if currentTab == "all" or msgCat == currentTab then
            table.insert(filteredMsgs, msg)
        end
    end

    -- 排序：未读优先 + 高优先级优先，再按日期
    table.sort(filteredMsgs, function(a, b)
        -- 未读优先
        if (not a.read) ~= (not b.read) then return not a.read end
        -- 同为未读时，高优先级在前
        if not a.read and not b.read then
            local pa = MessageManager.priorityRank(a.priority)
            local pb = MessageManager.priorityRank(b.priority)
            if pa ~= pb then return pa > pb end
        end
        -- 日期新→旧
        local function dateKey(msg)
            if not msg.date then return 0 end
            return (msg.date.year or 0) * 10000 + (msg.date.month or 0) * 100 + (msg.date.day or 0)
        end
        return dateKey(a) > dateKey(b)
    end)

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
            labelText = cat.label .. " " .. unread
        end
        table.insert(tabButtons, UI.Button {
            text = labelText,
            height = 32,
            paddingLeft = 12,
            paddingRight = 12,
            backgroundColor = isActive and Theme.COLORS.GOLD or Theme.COLORS.BG_SURFACE,
            borderRadius = 16,
            fontSize = 12,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
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
        local catIcon = CATEGORY_ICONS[msgCat] or "📋"
        local hasActions = (msg.actions and #msg.actions > 0)
        local isUrgent = MessageManager.isUrgent(msg.priority)
        local priorityColor = PRIORITY_COLORS[msg.priority] or Theme.COLORS.GOLD

        local rowBg = Theme.COLORS.TRANSPARENT
        if isUnread and msg.priority == "critical" then
            rowBg = {50, 15, 15, 255}
        elseif isUnread and isUrgent then
            rowBg = {40, 20, 20, 255}
        elseif isUnread then
            rowBg = {20, 28, 48, 255}
        end

        table.insert(msgRows, UI.Panel {
            width = "100%",
            paddingLeft = 12,
            paddingRight = 12,
            paddingTop = 11,
            paddingBottom = 11,
            backgroundColor = rowBg,
            borderBottomWidth = 1,
            -- 紧急消息加左边框
            borderLeftWidth = isUrgent and 3 or 0,
            borderColor = isUrgent and Theme.COLORS.DANGER or Theme.COLORS.BORDER,
            children = {
                -- Row 1: 图标 + 分类 + 标题 + 日期 + 指示器
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        -- 分类图标圆点
                        UI.Panel {
                            width = 24, height = 24,
                            borderRadius = 12,
                            backgroundColor = {catColor[1], catColor[2], catColor[3], 30},
                            alignItems = "center",
                            justifyContent = "center",
                            marginRight = 8,
                            children = {
                                UI.Label {
                                    text = catIcon,
                                    fontSize = 11,
                                }
                            }
                        },
                        -- 标题区
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            children = {
                                ---@diagnostic disable-next-line: param-type-mismatch
                                UI.Label {
                                    text = TITLE_FALLBACK[msg.title] or msg.title or "消息",
                                    fontSize = 14,
                                    color = isUnread and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                                    fontWeight = isUnread and "bold" or "normal",
                                },
                            }
                        },
                        -- 可操作标记
                        hasActions and UI.Panel {
                            backgroundColor = {Theme.COLORS.MATCH_ORANGE[1], Theme.COLORS.MATCH_ORANGE[2], Theme.COLORS.MATCH_ORANGE[3], 30},
                            borderRadius = 4,
                            paddingLeft = 5, paddingRight = 5,
                            paddingTop = 2, paddingBottom = 2,
                            marginLeft = 6,
                            children = {
                                UI.Label {
                                    text = "待处理",
                                    fontSize = 9,
                                    color = Theme.COLORS.MATCH_ORANGE,
                                    fontWeight = "bold",
                                }
                            }
                        } or UI.Panel { width = 0 },
                        -- 日期
                        UI.Label {
                            text = msg.date and string.format("%d/%d", msg.date.month, msg.date.day) or "",
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginLeft = 6,
                        },
                        -- 未读/优先级圆点
                        (isUnread or hasActions) and UI.Panel {
                            width = 8, height = 8,
                            borderRadius = 4,
                            backgroundColor = priorityColor,
                            marginLeft = 6,
                        } or UI.Panel { width = 0 },
                    },
                },
                -- Row 2: 摘要
                UI.Label {
                    text = msg.body and (#msg.body > 60 and msg.body:sub(1, 60) .. "..." or msg.body) or "",
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 4,
                    marginLeft = 32,
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

    local totalUnread = unreadCounts.all or 0

    if params and params.openMessageId then
        local msgId = params.openMessageId
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            for _, msg in ipairs(gameState.inbox) do
                if msg.id == msgId then
                    Inbox._showDetail(msg, currentTab)
                    break
                end
            end
        end)
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
                        text = "←", width = 36, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 18, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "收件箱",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    totalUnread > 0 and UI.Button {
                        text = "全读",
                        width = 50, height = 28,
                        backgroundColor = Theme.COLORS.BG_SURFACE,
                        borderRadius = 14,
                        fontSize = 11, color = Theme.COLORS.GOLD,
                        onClick = function()
                            for _, msg in ipairs(gameState.inbox) do msg.read = true end
                            Router.replaceWith("inbox", { tab = currentTab })
                        end,
                    } or UI.Panel { width = 50 },
                }
            },

            -- 二级导航
            Theme.MoreSubNav("inbox"),

            -- 分类标签栏
            UI.ScrollView {
                width = "100%",
                height = 48,
                scrollX = true,
                scrollY = false,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_HEADER,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = tabButtons,
            },

            -- 欧冠广告横幅（原图比例 1024x683 ≈ 1.5:1）
            UI.Panel {
                width = "100%", aspectRatio = 1024/683, overflow = "hidden",
                backgroundImage = "image/banner_ucl_sponsors.png",
                backgroundSize = "cover",
            },

            -- 消息列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = msgRows,
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }
end

return Inbox
