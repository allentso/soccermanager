-- ui/screens/finance.lua
-- 财务管理页面 - 增强版：健康评级 / 风险可视化 / 趋势 / 流水
-- 设计：字母评级A-F / 工资条风险阈值 / 语义色驱动

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local FinanceManager = require("scripts/systems/finance_manager")
local BoardManager = require("scripts/systems/board_manager")

local Finance = {}

-- 状态持久化
local _activeTab = "overview"  -- overview | operations | wages | facilities | transactions
local _txFilter = "ALL"        -- ALL | income | expense | transfer | wage

------------------------------------------------------
-- 主入口
------------------------------------------------------
function Finance.create(params)
    if params and params.tab then _activeTab = params.tab end

    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无数据", color = Theme.COLORS.TEXT_MUTED } }
        }
    end

    local team = gameState:getPlayerTeam()
    if not team then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "未选择球队", color = Theme.COLORS.TEXT_MUTED } }
        }
    end

    -- 内容区域
    local content
    if _activeTab == "transactions" then
        content = Finance._buildTransactions(team, gameState)
    elseif _activeTab == "facilities" then
        content = Finance._buildFacilities(team, gameState)
    elseif _activeTab == "operations" then
        content = Finance._buildOperations(team, gameState)
    elseif _activeTab == "wages" then
        content = Finance._buildWages(team, gameState)
    else
        content = Finance._buildOverview(team, gameState)
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
                        text = "←",
                        width = 36, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "财务管理",
                        fontSize = 17,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 36 },
                }
            },

            -- 标签切换：概览 / 流水
            Finance._buildTabBar(),

            -- 内容
            content,

            -- 底部导航
            Theme.MainNav("home"),
        }
    }
end

------------------------------------------------------
-- 标签栏
------------------------------------------------------
function Finance._buildTabBar()
    local tabs = {
        { key = "overview", label = "总览" },
        { key = "operations", label = "经营" },
        { key = "wages", label = "薪资" },
        { key = "facilities", label = "设施" },
        { key = "transactions", label = "流水" },
    }
    local tabBtns = {}
    for _, t in ipairs(tabs) do
        local isActive = t.key == _activeTab
        table.insert(tabBtns, UI.Button {
            text = t.label,
            height = 32,
            paddingLeft = 16,
            paddingRight = 16,
            backgroundColor = isActive and Theme.COLORS.GOLD or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            fontSize = 13,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            onClick = function()
                if not isActive then
                    _activeTab = t.key
                    Router.replaceWith("finance")
                end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14,
        backgroundColor = Theme.COLORS.BG_HEADER,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = tabBtns,
    }
end

------------------------------------------------------
-- 总览标签（精简：资金 + 健康 + 赛季收支 + 工资概要）
------------------------------------------------------
function Finance._buildOverview(team, gameState)
    -- 工资计算（概要）
    local totalWeeklyWage = Finance._calcTotalWeeklyWage(team, gameState)
    local wageBudget = team.wageBudget or 0
    local wageBudgetUsage = wageBudget > 0 and math.floor(totalWeeklyWage / wageBudget * 100) or 0
    local wageStatusColor = wageBudgetUsage > 90 and Theme.COLORS.DANGER
        or (wageBudgetUsage > 70 and Theme.COLORS.WARNING or Theme.COLORS.SECONDARY)

    -- 净资产计算
    local netIncome = (team.seasonIncome or 0) - (team.seasonExpense or 0)
    local netColor = netIncome >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        padding = 14,
        children = {
            -- 资金总览卡片
            Theme.Card {
                children = (function()
                    local boardStatus = BoardManager.getStatus(gameState)
                    local sat = boardStatus and boardStatus.satisfaction or 50
                    local satColor
                    if sat >= 70 then satColor = Theme.COLORS.FINANCE_GREEN
                    elseif sat >= 40 then satColor = Theme.COLORS.WARNING
                    else satColor = Theme.COLORS.DANGER end

                    return {
                        -- 标题行：俱乐部财务 + 董事会满意度
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            justifyContent = "space-between",
                            children = {
                                UI.Label {
                                    text = "俱乐部财务",
                                    fontSize = 16,
                                    color = Theme.COLORS.TEXT_PRIMARY,
                                    fontWeight = "bold",
                                },
                                UI.Panel {
                                    flexDirection = "row",
                                    alignItems = "center",
                                    paddingLeft = 10, paddingRight = 10,
                                    paddingTop = 4, paddingBottom = 4,
                                    backgroundColor = {satColor[1], satColor[2], satColor[3], 25},
                                    borderRadius = 12,
                                    children = {
                                        UI.Label {
                                            text = "董事会满意 ",
                                            fontSize = 11,
                                            color = Theme.COLORS.TEXT_MUTED,
                                        },
                                        UI.Label {
                                            text = sat .. "%",
                                            fontSize = 13,
                                            color = satColor,
                                            fontWeight = "bold",
                                        },
                                    }
                                },
                            }
                        },
                        -- 大字显示余额
                        UI.Label {
                            text = Finance._formatMoney(team.balance),
                            fontSize = 28,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                            marginTop = 6,
                        },
                        UI.Label {
                            text = "可用资金",
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 2,
                        },
                        Theme.Divider(),
                        UI.Panel {
                            flexDirection = "row",
                            marginTop = 4,
                            flexWrap = "wrap",
                            children = {
                                Theme.StatPill { label = "转会预算", value = Finance._formatMoney(team.transferBudget) },
                                Theme.StatPill { label = "工资预算", value = Finance._formatMoney(wageBudget) .. "/周" },
                            }
                        },
                    }
                end)(),
            },

            -- 财务健康状况
            Finance._buildHealthCard(team, gameState),

            -- 赛季收支对比
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "本赛季收支" },
                    UI.Panel {
                        flexDirection = "row",
                        marginTop = 8,
                        children = {
                            -- 收入
                            UI.Panel {
                                flexGrow = 1,
                                alignItems = "center",
                                children = {
                                    UI.Label { text = "收入", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                                    UI.Label {
                                        text = Finance._formatMoney(team.seasonIncome or 0),
                                        fontSize = 16,
                                        color = Theme.COLORS.SECONDARY,
                                        fontWeight = "bold",
                                        marginTop = 2,
                                    },
                                }
                            },
                            -- 分隔
                            UI.Panel {
                                width = 1, height = 40,
                                backgroundColor = Theme.COLORS.BORDER,
                            },
                            -- 支出
                            UI.Panel {
                                flexGrow = 1,
                                alignItems = "center",
                                children = {
                                    UI.Label { text = "支出", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                                    UI.Label {
                                        text = Finance._formatMoney(team.seasonExpense or 0),
                                        fontSize = 16,
                                        color = Theme.COLORS.DANGER,
                                        fontWeight = "bold",
                                        marginTop = 2,
                                    },
                                }
                            },
                            -- 分隔
                            UI.Panel {
                                width = 1, height = 40,
                                backgroundColor = Theme.COLORS.BORDER,
                            },
                            -- 净利润
                            UI.Panel {
                                flexGrow = 1,
                                alignItems = "center",
                                children = {
                                    UI.Label { text = "净收入", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                                    UI.Label {
                                        text = (netIncome >= 0 and "+" or "") .. Finance._formatMoney(netIncome),
                                        fontSize = 16,
                                        color = netColor,
                                        fontWeight = "bold",
                                        marginTop = 2,
                                    },
                                }
                            },
                        }
                    },
                }
            },

            -- 工资预算概要（精简版）
            Theme.Card {
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", marginBottom = 6,
                        children = {
                            Theme.Subtitle { text = "工资预算" },
                            UI.Panel { flexGrow = 1 },
                            UI.Button {
                                text = "详情 >",
                                height = 26,
                                paddingLeft = 10, paddingRight = 10,
                                backgroundColor = Theme.COLORS.TRANSPARENT,
                                fontSize = 11,
                                color = Theme.COLORS.ACCENT,
                                onClick = function()
                                    _activeTab = "wages"
                                    Router.replaceWith("finance", { tab = "wages" })
                                end,
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%",
                        height = 16,
                        backgroundColor = {38, 46, 71, 255},
                        borderRadius = 8,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.min(100, wageBudgetUsage) .. "%",
                                height = "100%",
                                backgroundColor = wageStatusColor,
                                borderRadius = 8,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row",
                        marginTop = 6,
                        children = {
                            UI.Label {
                                text = wageBudgetUsage .. "%",
                                fontSize = 14,
                                color = wageStatusColor,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "  " .. Finance._formatMoney(totalWeeklyWage) .. " / " .. Finance._formatMoney(wageBudget) .. " 周预算",
                                fontSize = 11,
                                color = Theme.COLORS.TEXT_MUTED,
                            },
                        }
                    },
                }
            },

            -- 快捷入口卡片
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "管理" },
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        marginTop = 6,
                        children = {
                            Finance._quickEntryBtn("预算分配", "operations"),
                            Finance._quickEntryBtn("票价策略", "operations"),
                            Finance._quickEntryBtn("收入分析", "operations"),
                            Finance._quickEntryBtn("赛季预测", "operations"),
                        }
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- 快捷入口按钮
------------------------------------------------------
function Finance._quickEntryBtn(label, targetTab)
    return UI.Button {
        text = label,
        height = 34,
        paddingLeft = 14, paddingRight = 14,
        backgroundColor = {38, 50, 80, 255},
        borderRadius = 8,
        fontSize = 12,
        color = Theme.COLORS.ACCENT,
        marginRight = 8,
        marginBottom = 6,
        onClick = function()
            _activeTab = targetTab
            Router.replaceWith("finance", { tab = targetTab })
        end,
    }
end

------------------------------------------------------
-- 经营标签（预算分配 + 票价策略 + 收入来源 + 预测）
------------------------------------------------------
function Finance._buildOperations(team, gameState)
    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        padding = 14,
        children = {
            -- 经营仪表盘（收入动态 + 票价策略 合并）
            Finance._buildOperationsDashboard(team, gameState),

            -- 预算分配
            Finance._buildBudgetAllocationCard(team, gameState),

            -- 收入来源占比
            Finance._buildIncomeBreakdownCard(team),

            -- 财务预测
            Finance._buildForecastCard(team, gameState),
        }
    }
end

------------------------------------------------------
-- 薪资标签（工资详情 + TOP5 + 趋势）
------------------------------------------------------
function Finance._buildWages(team, gameState)
    -- 工资计算
    local totalPlayerWage = 0
    local totalStaffWage = 0
    local highestWage = 0
    local top5Wages = {}

    local playerWages = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then
            totalPlayerWage = totalPlayerWage + (p.wage or 0)
            table.insert(playerWages, { name = p.displayName, wage = p.wage or 0 })
            if (p.wage or 0) > highestWage then
                highestWage = p.wage
            end
        end
    end
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then totalStaffWage = totalStaffWage + (s.wage or 0) end
    end

    -- Top 5 薪资
    table.sort(playerWages, function(a, b) return a.wage > b.wage end)
    for i = 1, math.min(5, #playerWages) do
        table.insert(top5Wages, playerWages[i])
    end

    local totalWeeklyWage = totalPlayerWage + totalStaffWage
    local monthlyWage = totalWeeklyWage * 4
    local seasonWage = totalWeeklyWage * 46

    -- 预算状况
    local wageBudget = team.wageBudget or 0
    local wageBudgetUsage = wageBudget > 0 and math.floor(totalWeeklyWage / wageBudget * 100) or 0
    local wageStatusColor = wageBudgetUsage > 90 and Theme.COLORS.DANGER
        or (wageBudgetUsage > 70 and Theme.COLORS.WARNING or Theme.COLORS.SECONDARY)

    -- Top5 薪资行
    local top5Rows = {}
    for i, pw in ipairs(top5Wages) do
        local barWidth = highestWage > 0 and math.floor(pw.wage / highestWage * 100) or 0
        table.insert(top5Rows, UI.Panel {
            width = "100%",
            marginTop = 6,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = i .. ". " .. pw.name,
                            fontSize = 12,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = Finance._formatMoney(pw.wage) .. "/周",
                            fontSize = 11,
                            color = Theme.COLORS.ACCENT,
                        },
                    }
                },
                -- 薪资条
                UI.Panel {
                    width = "100%",
                    height = 6,
                    backgroundColor = {38, 46, 71, 255},
                    borderRadius = 3,
                    marginTop = 3,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = barWidth .. "%",
                            height = "100%",
                            backgroundColor = Theme.COLORS.ACCENT,
                            borderRadius = 3,
                        },
                    }
                },
            }
        })
    end

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        padding = 14,
        children = {
            -- 工资预算使用率（完整版）
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "工资预算使用率" },
                    UI.Panel {
                        width = "100%",
                        height = 20,
                        backgroundColor = {38, 46, 71, 255},
                        borderRadius = 10,
                        marginTop = 8,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.min(100, wageBudgetUsage) .. "%",
                                height = "100%",
                                backgroundColor = wageStatusColor,
                                borderRadius = 10,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row",
                        marginTop = 6,
                        children = {
                            UI.Label {
                                text = wageBudgetUsage .. "%",
                                fontSize = 14,
                                color = wageStatusColor,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "  " .. Finance._formatMoney(totalWeeklyWage) .. " / " .. Finance._formatMoney(wageBudget) .. " 周预算",
                                fontSize = 11,
                                color = Theme.COLORS.TEXT_MUTED,
                            },
                        }
                    },
                    Theme.Divider(),
                    UI.Panel {
                        flexDirection = "row",
                        flexWrap = "wrap",
                        marginTop = 4,
                        children = {
                            Theme.StatPill { label = "球员薪资", value = Finance._formatMoney(totalPlayerWage) },
                            Theme.StatPill { label = "职员薪资", value = Finance._formatMoney(totalStaffWage) },
                            Theme.StatPill { label = "月薪总额", value = Finance._formatMoney(monthlyWage) },
                            Theme.StatPill { label = "赛季总薪", value = Finance._formatMoney(seasonWage) },
                        }
                    },
                }
            },

            -- Top5 薪资
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "薪资排行 TOP 5" },
                    UI.Panel {
                        width = "100%",
                        children = top5Rows,
                    },
                }
            },

            -- 近期收支趋势
            Finance._buildTrendCard(team),
        }
    }
end

------------------------------------------------------
-- 工具：计算周薪总额
------------------------------------------------------
function Finance._calcTotalWeeklyWage(team, gameState)
    local totalPlayerWage = 0
    local totalStaffWage = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then totalPlayerWage = totalPlayerWage + (p.wage or 0) end
    end
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then totalStaffWage = totalStaffWage + (s.wage or 0) end
    end
    return totalPlayerWage + totalStaffWage
end

------------------------------------------------------
-- 经营仪表盘（收入动态 + 票价策略 合并）
------------------------------------------------------
function Finance._buildOperationsDashboard(team, gameState)
    local currentStrategy = FinanceManager.getTicketStrategy(team)
    local strategies = FinanceManager.TICKET_STRATEGIES

    -- === 计算核心指标 ===
    -- 上座率
    local attendancePct, attSource
    local lastRevenue = team._lastMatchRevenue
    if type(lastRevenue) == "table" and lastRevenue.attendanceRate then
        attendancePct = math.floor(lastRevenue.attendanceRate * 100)
        attSource = "实际"
    else
        local rep = team.reputation or 50
        local baseRate = 0.65 + rep / 500
        local sBonus = currentStrategy.attendanceBonus or 0
        attendancePct = math.floor(math.min(0.95, math.max(0.50, baseRate + sBonus)) * 100)
        attSource = "预期"
    end
    local attColor = attendancePct >= 85 and Theme.COLORS.FINANCE_GREEN
        or (attendancePct >= 65 and Theme.COLORS.MATCH_ORANGE or Theme.COLORS.DANGER)

    -- 预估月收入
    local rep = team.reputation or 50
    local capacity = team.stadiumCapacity or 30000
    local position = team.leaguePosition or 10
    local estSponsor = math.floor(rep * 15000 + (capacity / 30000) * 500000)
    local estBroadcast = math.floor((rep * 25000 + 1000000) * (1.0 + (20 - position) * 0.05))
    local estMerch = math.floor((rep * 8000 + 300000) * 1.0)
    local estTotal = estSponsor + estBroadcast + estMerch

    -- 下次结算
    local currentDay = gameState.date.day or 1
    local currentMonth = gameState.date.month or 8
    local daysToNext = currentDay <= 1 and 0 or (30 - currentDay + 1)
    local nextSettleText
    if daysToNext <= 0 then
        nextSettleText = "今日"
    elseif daysToNext <= 7 then
        nextSettleText = daysToNext .. "天"
    else
        nextSettleText = daysToNext .. "天"
    end

    -- 最近收支流水
    local incomeCategories = {
        ticket = { label = "票房", color = {72, 160, 220, 255} },
        broadcast = { label = "转播", color = {100, 200, 150, 255} },
        sponsor = { label = "赞助", color = {220, 180, 60, 255} },
        merchandise = { label = "商品", color = {180, 120, 220, 255} },
        prize = { label = "奖金", color = {240, 130, 80, 255} },
        wage = { label = "工资", color = {220, 80, 80, 255} },
        maintenance = { label = "维护", color = {150, 150, 170, 255} },
    }
    local recentItems = {}
    local txs = team.transactions or {}
    local startIdx = math.max(1, #txs - 5)
    for i = #txs, startIdx, -1 do
        local tx = txs[i]
        if tx then
            local catInfo = incomeCategories[tx.category]
            table.insert(recentItems, {
                desc = tx.description or "收支",
                amount = tx.amount or 0,
                label = catInfo and catInfo.label or "其他",
                color = catInfo and catInfo.color or Theme.COLORS.TEXT_MUTED,
            })
        end
    end

    -- === 票价策略选项 ===
    local strategyOptions = {}
    for _, s in ipairs(strategies) do
        local isCurrent = s.key == currentStrategy.key
        local multLabel = string.format("x%.1f", s.multiplier)
        local attLabel = s.attendanceBonus > 0
            and string.format("+%d%%", math.floor(s.attendanceBonus * 100))
            or (s.attendanceBonus < 0
                and string.format("%d%%", math.floor(s.attendanceBonus * 100))
                or "--")

        table.insert(strategyOptions, UI.Button {
            width = "100%",
            height = 52,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = isCurrent and {45, 80, 120, 255} or Theme.COLORS.BG_SURFACE,
            borderRadius = 8,
            borderWidth = isCurrent and 1 or 0,
            borderColor = isCurrent and Theme.COLORS.GOLD or Theme.COLORS.TRANSPARENT,
            marginBottom = 6,
            onClick = function()
                if not isCurrent then
                    FinanceManager.setTicketStrategy(team, s.key)
                    UI.Toast.Show({ message = "已切换为: " .. s.label, variant = "success" })
                    Router.replaceWith("finance", { tab = "operations" })
                end
            end,
            children = {
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = s.label,
                                    fontSize = 14,
                                    color = isCurrent and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                                    fontWeight = isCurrent and "bold" or "normal",
                                },
                                isCurrent and UI.Panel {
                                    marginLeft = 6, paddingLeft = 5, paddingRight = 5,
                                    paddingTop = 1, paddingBottom = 1,
                                    backgroundColor = Theme.COLORS.GOLD,
                                    borderRadius = 4,
                                    children = { UI.Label { text = "当前", fontSize = 9, color = "#1A1A1A" } },
                                } or nil,
                            }
                        },
                        UI.Label { text = s.desc, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                    }
                },
                UI.Panel {
                    alignItems = "flex-end",
                    children = {
                        UI.Label { text = multLabel, fontSize = 16, fontWeight = "bold",
                            color = s.multiplier > 1.0 and Theme.COLORS.SECONDARY or Theme.COLORS.ACCENT },
                        UI.Label { text = attLabel, fontSize = 10, marginTop = 1,
                            color = s.attendanceBonus >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING },
                    }
                },
            }
        })
    end

    -- === 流水列表 ===
    local activityRows = {}
    if #recentItems == 0 then
        table.insert(activityRows, UI.Label {
            text = "暂无收支记录，比赛/月结后自动产生",
            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
        })
    else
        for _, item in ipairs(recentItems) do
            local isIncome = item.amount >= 0
            table.insert(activityRows, UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                paddingTop = 5, paddingBottom = 5,
                borderBottomWidth = 1, borderColor = {255,255,255,12},
                children = {
                    UI.Panel { width = 3, height = 24, borderRadius = 2, backgroundColor = item.color, marginRight = 8 },
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Label { text = item.desc, fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY, maxLines = 1 },
                            UI.Label { text = item.label, fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 1 },
                        }
                    },
                    UI.Label {
                        text = (isIncome and "+" or "") .. FinanceManager.formatMoney(item.amount),
                        fontSize = 12, fontWeight = "bold",
                        color = isIncome and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER,
                    },
                }
            })
        end
    end

    -- === 组装仪表盘 ===
    return Theme.Card {
        children = {
            -- 顶部标题
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 12,
                children = {
                    UI.Label { text = "经营总览", fontSize = 17, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                        backgroundColor = {60, 180, 120, 30}, borderRadius = 8,
                        children = {
                            UI.Label { text = "结算 ", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = nextSettleText, fontSize = 10, color = Theme.COLORS.SECONDARY, fontWeight = "bold" },
                        }
                    },
                }
            },

            -- 三环仪表（上座率 / 月收入 / 球场容量）
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-around", alignItems = "center",
                paddingTop = 4, paddingBottom = 12,
                children = {
                    Theme.RingGauge {
                        value = attendancePct, size = 60, thickness = 4,
                        color = attColor,
                        label = attendancePct .. "%",
                        labelSize = 14,
                        sublabel = attSource .. "上座",
                    },
                    UI.Panel {
                        alignItems = "center",
                        children = {
                            UI.Label { text = "预估月入", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = FinanceManager.formatMoney(estTotal),
                                fontSize = 18, fontWeight = "bold",
                                color = Theme.COLORS.SECONDARY, marginTop = 3,
                            },
                            UI.Label { text = "赞助+转播+商品", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                    Theme.RingGauge {
                        value = math.min(100, math.floor(capacity / 60000 * 100)),
                        size = 60, thickness = 4,
                        color = Theme.COLORS.ACCENT,
                        label = string.format("%.0fw", capacity / 10000),
                        labelSize = 14,
                        sublabel = "球场",
                    },
                }
            },

            -- 预估明细行
            UI.Panel {
                width = "100%", flexDirection = "row",
                paddingTop = 8, paddingBottom = 10,
                borderTopWidth = 1, borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    Finance._dashEstItem("赞助", estSponsor, {220, 180, 60, 255}),
                    Finance._dashEstItem("转播", estBroadcast, {100, 200, 150, 255}),
                    Finance._dashEstItem("商品", estMerch, {180, 120, 220, 255}),
                    Finance._dashEstItem("票房", (type(lastRevenue) == "table" and lastRevenue.revenue) or 0, {72, 160, 220, 255}),
                }
            },

            -- 票价策略区域
            UI.Panel {
                width = "100%", marginTop = 14,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", marginBottom = 8,
                        children = {
                            UI.Label { text = "票价策略", fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                            UI.Label { text = "倍率 x" .. string.format("%.1f", currentStrategy.multiplier),
                                fontSize = 11, color = Theme.COLORS.ACCENT },
                        }
                    },
                    UI.Panel { width = "100%", children = strategyOptions },
                }
            },

            -- 最近流水区域
            UI.Panel {
                width = "100%", marginTop = 14,
                children = {
                    UI.Label { text = "最近收支", fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 },
                    UI.Panel { width = "100%", children = activityRows },
                }
            },
        }
    }
end

-- 仪表盘预估收入子项
function Finance._dashEstItem(label, amount, color)
    return UI.Panel {
        flexGrow = 1, alignItems = "center",
        children = {
            UI.Panel { width = 6, height = 6, borderRadius = 3, backgroundColor = color, marginBottom = 3 },
            UI.Label { text = label, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
            UI.Label {
                text = FinanceManager.formatMoney(amount),
                fontSize = 12, fontWeight = "bold",
                color = Theme.COLORS.TEXT_PRIMARY, marginTop = 2,
            },
        }
    }
end

------------------------------------------------------
-- 设施标签
------------------------------------------------------
function Finance._buildFacilities(team, gameState)
    local facilities = FinanceManager.ensureFacilities(team)
    local bonuses = FinanceManager.getFacilityBonuses(team)
    local rows = {}

    local defs = {
        { key = "training", label = "训练设施", desc = "提升每日训练属性成长", bonus = string.format("训练收益 x%.2f", bonuses.trainingGain) },
        { key = "medical", label = "医疗设施", desc = "提升伤病恢复和长期健康管理", bonus = string.format("恢复效率 x%.2f", bonuses.injuryRecovery) },
        { key = "scouting", label = "球探设施", desc = "提升球探报告准确度和发现质量", bonus = string.format("球探准确 x%.2f", bonuses.scoutingAccuracy) },
        { key = "youth", label = "青训设施", desc = "提升高潜力青训出现几率和平均质量", bonus = string.format("青训质量 x%.2f", bonuses.youthQuality) },
    }

    for _, def in ipairs(defs) do
        local level = facilities[def.key] or 1
        local cost = FinanceManager.getFacilityUpgradeCost(team, def.key)
        table.insert(rows, Theme.Card {
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexGrow = 1,
                            children = {
                                UI.Label { text = def.label .. " Lv." .. level, fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                UI.Label { text = def.desc, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 3 },
                                UI.Label { text = def.bonus, fontSize = 11, color = Theme.COLORS.SECONDARY, marginTop = 5 },
                            }
                        },
                        UI.Button {
                            text = cost and ("升级 " .. Finance._formatMoney(cost)) or "已满级",
                            width = 110,
                            height = 34,
                            backgroundColor = cost and Theme.COLORS.GOLD or Theme.COLORS.TEXT_MUTED,
                            borderRadius = 8,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                if cost then
                                    local ok, err = FinanceManager.upgradeFacility(gameState, def.key)
                                    if not ok and err then
                                        gameState:sendMessage({
                                            category = "finance",
                                            title = "升级失败",
                                            body = err,
                                            priority = "low",
                                        })
                                    end
                                    Router.replaceWith("finance", { tab = "facilities" })
                                end
                            end,
                        },
                    }
                }
            }
        })
    end

    -- 球场扩建卡片
    local stadiumCard = Finance._buildStadiumExpansionCard(team, gameState)
    table.insert(rows, 1, stadiumCard)  -- 放在设施列表最前面

    -- 球场横幅图片（最顶部，原图比例 1032x576 ≈ 1.79:1）
    table.insert(rows, 1, UI.Panel {
        width = "100%", aspectRatio = 1032/576, borderRadius = 10, overflow = "hidden", marginBottom = 10,
        backgroundImage = "image/banner_stadium_night.png",
        backgroundSize = "cover",
    })

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        padding = 14,
        children = rows,
    }
end

------------------------------------------------------
-- 球场扩建卡片
------------------------------------------------------
function Finance._buildStadiumExpansionCard(team, gameState)
    local capacity = team.stadiumCapacity or 30000
    local maxCapacity = FinanceManager.STADIUM_EXPANSION.maxCapacity
    local isExpanding = team.stadiumExpanding
    local weeksLeft = team.stadiumExpandWeeksLeft or 0
    local expandTarget = team.stadiumExpandTarget or capacity

    -- 计算费用
    local cost, err, addedSeats, newCapacity = FinanceManager.getStadiumExpansionCost(team)
    local isMaxed = not cost and not isExpanding

    -- 容量进度条百分比
    local capacityPct = math.floor(capacity / maxCapacity * 100)

    -- 状态文案
    local statusText, statusColor
    if isExpanding then
        statusText = string.format("扩建中… %d 周后完工 → %d 座", weeksLeft, expandTarget)
        statusColor = Theme.COLORS.WARNING
    elseif isMaxed then
        statusText = "已达最大容量"
        statusColor = Theme.COLORS.TEXT_MUTED
    else
        statusText = string.format("可扩建 +%d 座 → %d 座", addedSeats, newCapacity)
        statusColor = Theme.COLORS.SECONDARY
    end

    -- 按钮
    local btnText, btnEnabled
    if isExpanding then
        btnText = string.format("建设中 (%d周)", weeksLeft)
        btnEnabled = false
    elseif isMaxed then
        btnText = "已满级"
        btnEnabled = false
    else
        btnText = "扩建 " .. Finance._formatMoney(cost)
        btnEnabled = (team.balance or 0) >= cost
    end

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Label {
                        text = "球场",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = {60, 130, 200, 40},
                        borderRadius = 8,
                        children = {
                            UI.Label {
                                text = string.format("%d / %d 座", capacity, maxCapacity),
                                fontSize = 10,
                                color = Theme.COLORS.ACCENT,
                            },
                        }
                    },
                }
            },
            -- 容量条
            UI.Panel {
                width = "100%", height = 10, borderRadius = 5,
                backgroundColor = {38, 46, 71, 255},
                overflow = "hidden",
                marginBottom = 6,
                children = {
                    UI.Panel {
                        width = capacityPct .. "%", height = "100%",
                        borderRadius = 5,
                        backgroundColor = isExpanding and Theme.COLORS.WARNING or Theme.COLORS.GOLD,
                    },
                }
            },
            -- 状态
            UI.Label {
                text = statusText,
                fontSize = 12,
                color = statusColor,
                marginBottom = 10,
            },
            -- 扩建按钮
            UI.Button {
                text = btnText,
                width = "100%",
                height = 40,
                backgroundColor = btnEnabled and Theme.COLORS.GOLD or Theme.COLORS.BG_SURFACE,
                borderRadius = 10,
                fontSize = 13,
                fontWeight = "bold",
                color = btnEnabled and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                onClick = function()
                    if not btnEnabled then return end
                    local ok, msg = FinanceManager.expandStadium(gameState)
                    if ok then
                        UI.Toast.Show({ message = msg, variant = "success" })
                    else
                        UI.Toast.Show({ message = msg or "扩建失败", variant = "error" })
                    end
                    Router.replaceWith("finance", { tab = "facilities" })
                end,
            },
            -- 提示
            not isMaxed and not isExpanding and UI.Label {
                text = string.format("每次扩建 +%d 座，耗时 %d 周",
                    FinanceManager.STADIUM_EXPANSION.expansionStep,
                    FinanceManager.STADIUM_EXPANSION.buildWeeks),
                fontSize = 10,
                color = Theme.COLORS.TEXT_MUTED,
                marginTop = 6,
            } or nil,
        }
    }
end

------------------------------------------------------
-- 预算分配滑块卡片
------------------------------------------------------
function Finance._buildBudgetAllocationCard(team, gameState)
    local transferBudget = team.transferBudget or 0
    local wageBudget = team.wageBudget or 0
    local totalBudget = transferBudget + wageBudget

    -- 如果总预算为0，无数据可显示
    if totalBudget <= 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "预算分配" },
                UI.Label { text = "暂无预算数据", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
            }
        }
    end

    -- 当前分配比例
    local transferPct = math.floor(transferBudget / totalBudget * 100)
    local wagePct = 100 - transferPct

    -- 用于就地更新的引用
    local transferBar = UI.Panel {
        width = transferPct .. "%", height = "100%",
        backgroundColor = {72, 160, 220, 255},
        justifyContent = "center", alignItems = "center",
        children = transferPct >= 15 and {
            UI.Label { id = "transferBarLabel", text = "转会 " .. transferPct .. "%", fontSize = 9, color = {255, 255, 255, 255} },
        } or {},
    }
    local wageBar = UI.Panel {
        width = wagePct .. "%", height = "100%",
        backgroundColor = {220, 180, 60, 255},
        justifyContent = "center", alignItems = "center",
        children = wagePct >= 15 and {
            UI.Label { id = "wageBarLabel", text = "薪资 " .. wagePct .. "%", fontSize = 9, color = {30, 30, 30, 255} },
        } or {},
    }
    local transferValueLabel = UI.Label {
        text = Finance._formatMoney(transferBudget),
        fontSize = 14, color = {72, 160, 220, 255}, fontWeight = "bold",
    }
    local wageValueLabel = UI.Label {
        text = Finance._formatMoney(wageBudget),
        fontSize = 14, color = {220, 180, 60, 255}, fontWeight = "bold",
    }

    -- 滑块变更回调：就地更新所有相关控件
    local function onSliderChange(self, newPct)
        local pct = math.floor(newPct)
        local newTransfer = math.floor(totalBudget * pct / 100)
        local newWage = totalBudget - newTransfer
        -- 更新数据
        team.transferBudget = newTransfer
        team.wageBudget = newWage
        -- 就地更新UI
        transferBar:SetStyle({ width = pct .. "%" })
        wageBar:SetStyle({ width = (100 - pct) .. "%" })
        local tLabel = transferBar:FindById("transferBarLabel")
        if tLabel then tLabel:SetText("转会 " .. pct .. "%") end
        local wLabel = wageBar:FindById("wageBarLabel")
        if wLabel then wLabel:SetText("薪资 " .. (100 - pct) .. "%") end
        transferValueLabel:SetText(Finance._formatMoney(newTransfer))
        wageValueLabel:SetText(Finance._formatMoney(newWage))
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "预算分配" },
            -- 当前比例显示条
            UI.Panel {
                width = "100%", height = 24, borderRadius = 12,
                flexDirection = "row", overflow = "hidden",
                marginTop = 8, marginBottom = 6,
                backgroundColor = {38, 46, 71, 255},
                children = { transferBar, wageBar },
            },
            -- 滑块
            UI.Panel {
                width = "100%", marginBottom = 10,
                children = {
                    UI.Slider {
                        value = transferPct,
                        min = 10,
                        max = 90,
                        step = 5,
                        width = "100%",
                        trackColor = {38, 46, 71, 255},
                        fillColor = {72, 160, 220, 255},
                        thumbColor = {255, 255, 255, 255},
                        onChange = onSliderChange,
                    },
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", marginTop = 4,
                        children = {
                            UI.Label { text = "转会多", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = "薪资多", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                        }
                    },
                }
            },
            -- 数值详情
            UI.Panel {
                flexDirection = "row",
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label { text = "转会预算", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            transferValueLabel,
                        }
                    },
                    UI.Panel {
                        flexGrow = 1, alignItems = "flex-end",
                        children = {
                            UI.Label { text = "工资预算/周", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            wageValueLabel,
                        }
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- 收入来源占比卡片
------------------------------------------------------
function Finance._buildIncomeBreakdownCard(team)
    local breakdown = team.incomeBreakdown or {}
    local totalIncome = team.seasonIncome or 0

    if totalIncome <= 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "收入来源" },
                UI.Label { text = "本赛季暂无收入数据", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
            }
        }
    end

    -- 收入源定义（顺序即展示顺序）
    local sources = {
        { key = "ticket",      label = "票房", color = {72, 160, 220, 255} },
        { key = "broadcast",   label = "转播", color = {100, 200, 150, 255} },
        { key = "sponsor",     label = "赞助", color = {220, 180, 60, 255} },
        { key = "merchandise", label = "商品", color = {180, 120, 220, 255} },
        { key = "transfer",    label = "转会", color = {60, 180, 200, 255} },
        { key = "prize",       label = "奖金", color = {240, 130, 80, 255} },
    }

    -- 计算各源占比
    local bars = {}
    local legends = {}
    for _, src in ipairs(sources) do
        local amount = breakdown[src.key] or 0
        if amount > 0 then
            local pct = math.floor(amount / totalIncome * 100)
            if pct >= 1 then
                table.insert(bars, UI.Panel {
                    width = pct .. "%",
                    height = "100%",
                    backgroundColor = src.color,
                })
                table.insert(legends, UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    marginRight = 10,
                    marginBottom = 4,
                    children = {
                        UI.Panel { width = 8, height = 8, borderRadius = 2, backgroundColor = src.color, marginRight = 4 },
                        UI.Label {
                            text = string.format("%s %d%% %s", src.label, pct, Finance._formatMoney(amount)),
                            fontSize = 10, color = Theme.COLORS.TEXT_SECONDARY,
                        },
                    }
                })
            end
        end
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "收入来源构成" },
            -- 堆叠占比条
            UI.Panel {
                width = "100%",
                height = 20,
                borderRadius = 10,
                overflow = "hidden",
                flexDirection = "row",
                marginTop = 8,
                marginBottom = 8,
                backgroundColor = {38, 46, 71, 255},
                children = bars,
            },
            -- 图例
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                children = legends,
            },
        }
    }
end

------------------------------------------------------
-- 财务预测卡片
------------------------------------------------------
function Finance._buildForecastCard(team, gameState)
    local seasonIncome = team.seasonIncome or 0
    local seasonExpense = team.seasonExpense or 0
    local balance = team.balance or 0

    -- 估算已过周数（用简化方法）
    local startMonth = Constants.SEASON_START_MONTH or 8
    local monthsElapsed = gameState.date.month - startMonth
    if monthsElapsed < 0 then monthsElapsed = monthsElapsed + 12 end
    local weeksElapsed = math.max(1, math.floor(monthsElapsed * 4.3) + math.ceil(gameState.date.day / 7))
    local totalSeasonWeeks = 46
    local weeksRemaining = math.max(0, totalSeasonWeeks - weeksElapsed)

    -- 周均收支
    local weeklyAvgIncome = seasonIncome / weeksElapsed
    local weeklyAvgExpense = seasonExpense / weeksElapsed

    -- 预测
    local projectedIncome = weeklyAvgIncome * weeksRemaining
    local projectedExpense = weeklyAvgExpense * weeksRemaining
    local projectedBalance = balance + projectedIncome - projectedExpense

    -- 判断状态
    local statusIcon, statusText, statusColor
    if projectedBalance > balance * 0.8 then
        statusIcon = "OK"
        statusText = "预计安全，可适当投资"
        statusColor = Theme.COLORS.SECONDARY
    elseif projectedBalance > 0 then
        statusIcon = "!!"
        statusText = "预计略紧，建议控制支出"
        statusColor = Theme.COLORS.WARNING
    else
        statusIcon = "XX"
        statusText = "预计赤字！需立即增收或削减"
        statusColor = Theme.COLORS.DANGER
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "赛季末预测" },
            -- 进度条（赛季进度）
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginTop = 6,
                children = {
                    UI.Label { text = "赛季进度", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginRight = 8 },
                    UI.Panel {
                        flexGrow = 1, height = 6, borderRadius = 3,
                        backgroundColor = {38, 46, 71, 255},
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = math.floor(weeksElapsed / totalSeasonWeeks * 100) .. "%",
                                height = "100%", borderRadius = 3,
                                backgroundColor = Theme.COLORS.GOLD,
                            },
                        }
                    },
                    UI.Label {
                        text = string.format(" %d/%d周", weeksElapsed, totalSeasonWeeks),
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
            Theme.Divider(),
            -- 预测数据
            UI.Panel {
                width = "100%", marginTop = 4,
                children = {
                    Finance._forecastRow("当前余额", Finance._formatMoney(balance), Theme.COLORS.TEXT_PRIMARY),
                    Finance._forecastRow("预计剩余收入", "+" .. Finance._formatMoney(projectedIncome), Theme.COLORS.SECONDARY),
                    Finance._forecastRow("预计剩余支出", "-" .. Finance._formatMoney(projectedExpense), Theme.COLORS.DANGER),
                    UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.BORDER, marginTop = 6, marginBottom = 6 },
                    Finance._forecastRow("预计赛季末余额", Finance._formatMoney(projectedBalance), statusColor),
                }
            },
            -- 建议
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                marginTop = 8, paddingLeft = 8, paddingRight = 8,
                paddingTop = 6, paddingBottom = 6,
                backgroundColor = {statusColor[1], statusColor[2], statusColor[3], 20},
                borderRadius = 8,
                children = {
                    UI.Label { text = statusIcon, fontSize = 12, color = statusColor, fontWeight = "bold", marginRight = 8 },
                    UI.Label { text = statusText, fontSize = 12, color = statusColor },
                }
            },
        }
    }
end

function Finance._forecastRow(label, value, valueColor)
    return UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
        children = {
            UI.Label { text = label, fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
            UI.Label { text = value, fontSize = 13, color = valueColor or Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
        }
    }
end

------------------------------------------------------
-- 近期收支趋势卡（按周聚合最近 10 周数据）
------------------------------------------------------
function Finance._buildTrendCard(team)
    local transactions = team.transactions or {}
    if #transactions == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "近期收支趋势" },
                UI.Label {
                    text = "暂无流水数据",
                    fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                },
            }
        }
    end

    -- 按 (season, week) 聚合收支
    local weeklyData = {}
    local weekKeys = {}
    local weekKeySet = {}
    for _, tx in ipairs(transactions) do
        local key = string.format("S%dW%02d", tx.season or 0, tx.week or 0)
        if not weekKeySet[key] then
            weekKeySet[key] = true
            table.insert(weekKeys, key)
        end
        if not weeklyData[key] then
            weeklyData[key] = { income = 0, expense = 0 }
        end
        if (tx.amount or 0) > 0 then
            weeklyData[key].income = weeklyData[key].income + tx.amount
        else
            weeklyData[key].expense = weeklyData[key].expense + math.abs(tx.amount or 0)
        end
    end

    -- 取最近 10 周
    local startIdx = math.max(1, #weekKeys - 9)
    local recentKeys = {}
    for i = startIdx, #weekKeys do
        table.insert(recentKeys, weekKeys[i])
    end

    -- 找最大值（用于计算条形比例）
    local maxVal = 1
    for _, k in ipairs(recentKeys) do
        local d = weeklyData[k]
        if d.income > maxVal then maxVal = d.income end
        if d.expense > maxVal then maxVal = d.expense end
    end

    -- 构建条形图行
    local barRows = {}
    for _, k in ipairs(recentKeys) do
        local d = weeklyData[k]
        local incPct = math.floor(d.income / maxVal * 100)
        local expPct = math.floor(d.expense / maxVal * 100)
        -- 周标签：截取 "W" 后面的部分
        local weekLabel = k:match("W(%d+)") or k

        table.insert(barRows, UI.Panel {
            width = "100%",
            marginBottom = 8,
            children = {
                -- 周标签 + 净值
                UI.Panel {
                    flexDirection = "row", alignItems = "center", marginBottom = 2,
                    children = {
                        UI.Label {
                            text = "W" .. tonumber(weekLabel),
                            fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                            marginRight = 8,
                        },
                        UI.Label {
                            text = "净 " .. Finance._formatMoney(d.income - d.expense),
                            fontSize = 9,
                            color = (d.income >= d.expense) and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER,
                        },
                    }
                },
                -- 收入条 + 标注
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 2,
                    children = {
                        UI.Panel {
                            flexGrow = 1, height = 10,
                            backgroundColor = {38, 46, 71, 255},
                            borderRadius = 5,
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = math.max(2, incPct) .. "%",
                                    height = "100%",
                                    backgroundColor = Theme.COLORS.SECONDARY,
                                    borderRadius = 5,
                                },
                            }
                        },
                        UI.Label {
                            text = Finance._formatMoney(d.income),
                            fontSize = 9, color = Theme.COLORS.SECONDARY,
                            marginLeft = 6, width = 40,
                        },
                    }
                },
                -- 支出条 + 标注
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Panel {
                            flexGrow = 1, height = 10,
                            backgroundColor = {38, 46, 71, 255},
                            borderRadius = 5,
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = math.max(2, expPct) .. "%",
                                    height = "100%",
                                    backgroundColor = Theme.COLORS.DANGER,
                                    borderRadius = 5,
                                },
                            }
                        },
                        UI.Label {
                            text = Finance._formatMoney(d.expense),
                            fontSize = 9, color = Theme.COLORS.DANGER,
                            marginLeft = 6, width = 40,
                        },
                    }
                },
            }
        })
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "近期收支趋势（近" .. #recentKeys .. "周）" },
            -- 图例
            UI.Panel {
                flexDirection = "row", marginTop = 6, marginBottom = 8,
                children = {
                    UI.Panel {
                        width = 10, height = 10, borderRadius = 2,
                        backgroundColor = Theme.COLORS.SECONDARY, marginRight = 4,
                    },
                    UI.Label { text = "收入", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginRight = 12 },
                    UI.Panel {
                        width = 10, height = 10, borderRadius = 2,
                        backgroundColor = Theme.COLORS.DANGER, marginRight = 4,
                    },
                    UI.Label { text = "支出", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                }
            },
            -- 条形图
            UI.Panel {
                width = "100%",
                children = barRows,
            },
        }
    }
end

------------------------------------------------------
-- 流水标签
------------------------------------------------------
function Finance._buildTransactions(team, gameState)
    local transactions = team.transactions or {}

    -- 过滤
    local filtered = {}
    for _, tx in ipairs(transactions) do
        local pass = false
        if _txFilter == "ALL" then
            pass = true
        elseif _txFilter == "income" then
            pass = (tx.amount or 0) > 0
        elseif _txFilter == "expense" then
            pass = (tx.amount or 0) < 0
        elseif _txFilter == "transfer" then
            pass = tx.category == "transfer"
        elseif _txFilter == "wage" then
            pass = tx.category == "wage"
        end
        if pass then
            table.insert(filtered, tx)
        end
    end

    -- 倒序
    local reversed = {}
    for i = #filtered, 1, -1 do
        table.insert(reversed, filtered[i])
    end

    -- 过滤按钮
    local filters = {
        { key = "ALL", label = "全部" },
        { key = "income", label = "收入" },
        { key = "expense", label = "支出" },
        { key = "transfer", label = "转会" },
        { key = "wage", label = "薪资" },
    }
    local filterBtns = {}
    for _, f in ipairs(filters) do
        local isActive = f.key == _txFilter
        table.insert(filterBtns, UI.Button {
            text = f.label,
            height = 28,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 6,
            onClick = function()
                _txFilter = f.key
                Router.replaceWith("finance")
            end,
        })
    end

    -- 统计
    local totalIn, totalOut = 0, 0
    for _, tx in ipairs(reversed) do
        if (tx.amount or 0) > 0 then
            totalIn = totalIn + tx.amount
        else
            totalOut = totalOut + math.abs(tx.amount or 0)
        end
    end

    -- 交易行
    local txRows = {}
    if #reversed == 0 then
        table.insert(txRows, UI.Panel {
            width = "100%",
            height = 80,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label { text = "暂无流水记录", fontSize = 13, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for idx, tx in ipairs(reversed) do
            if idx > 50 then break end  -- 最多显示50条
            local isIncome = (tx.amount or 0) > 0
            local icon = isIncome and "+" or "-"
            local amtColor = isIncome and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER

            -- 分类标签
            local catLabels = {
                transfer = "[转会]",
                wage = "[薪资]",
                prize = "[奖金]",
                ticket = "[票房]",
                sponsor = "[赞助]",
                broadcast = "[转播]",
                merchandise = "[商品]",
                maintenance = "[维护]",
                facility = "[设施]",
                injection = "[注资]",
                commercial = "[商业]",
            }
            local catLabel = catLabels[tx.category] or ""

            local dateStr = ""
            if tx.week and tx.season then
                dateStr = "S" .. tx.season .. " W" .. tx.week
            elseif tx.date then
                if type(tx.date) == "table" then
                    dateStr = (tx.date.year or "") .. "/" .. (tx.date.month or "") .. "/" .. (tx.date.day or "")
                else
                    dateStr = tostring(tx.date)
                end
            end

            table.insert(txRows, UI.Panel {
                width = "100%",
                height = 52,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = {
                    -- 类别指示色
                    UI.Panel {
                        width = 4, height = 32,
                        backgroundColor = amtColor,
                        borderRadius = 2,
                        marginRight = 10,
                    },
                    -- 描述
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = (catLabel ~= "" and catLabel .. " " or "") .. (type(tx.description) == "string" and tx.description or "未知"),
                                fontSize = 13,
                                color = Theme.COLORS.TEXT_PRIMARY,
                            },
                            dateStr ~= "" and UI.Label {
                                text = dateStr,
                                fontSize = 10,
                                color = Theme.COLORS.TEXT_MUTED,
                                marginTop = 2,
                            } or UI.Panel { height = 0 },
                        }
                    },
                    -- 金额
                    UI.Label {
                        text = icon .. Finance._formatMoney(math.abs(tx.amount or 0)),
                        fontSize = 14,
                        color = amtColor,
                        fontWeight = "bold",
                    },
                }
            })
        end
    end

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        children = {
            -- 过滤栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 10, paddingBottom = 10,
                children = filterBtns,
            },

            -- 筛选结果统计
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                paddingLeft = 14, paddingRight = 14,
                paddingBottom = 8,
                children = {
                    UI.Label {
                        text = "共 " .. #reversed .. " 条",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        flexGrow = 1,
                    },
                    totalIn > 0 and UI.Label {
                        text = "入 +" .. Finance._formatMoney(totalIn),
                        fontSize = 11,
                        color = Theme.COLORS.SECONDARY,
                        marginRight = 10,
                    } or UI.Panel { width = 0 },
                    totalOut > 0 and UI.Label {
                        text = "出 -" .. Finance._formatMoney(totalOut),
                        fontSize = 11,
                        color = Theme.COLORS.DANGER,
                    } or UI.Panel { width = 0 },
                }
            },

            -- 交易列表
            UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12,
                marginLeft = 14,
                marginRight = 14,
                overflow = "hidden",
                children = txRows,
            },

            -- 底部间距
            UI.Panel { height = 14 },
        }
    }
end

------------------------------------------------------
-- 财务健康卡片 + 字母评级 + 恢复手段
------------------------------------------------------
function Finance._buildHealthCard(team, gameState)
    local teamId = gameState.playerTeamId
    local status, details = FinanceManager.getFinanceHealth(gameState, teamId)
    local label = FinanceManager.getHealthLabel(status)

    -- 字母评级映射 (A+~F 共6级)
    local gradeMap = {
        excellent = { grade = "A+", desc = "财务卓越，可大胆投资扩张" },
        stable    = { grade = "A",  desc = "财务稳健，运营良好" },
        fair      = { grade = "B",  desc = "财务尚可，建议优化开支" },
        watch     = { grade = "C",  desc = "需要关注，控制支出趋势" },
        warning   = { grade = "D",  desc = "财务紧张，需削减或增收" },
        critical  = { grade = "F",  desc = "财务危机！立即行动避免破产" },
    }
    local gradeInfo = gradeMap[status] or { grade = "C", desc = "" }

    -- 颜色映射
    local healthColors = {
        excellent = {60, 200, 140, 255},
        stable    = Theme.COLORS.FINANCE_GREEN,
        fair      = Theme.COLORS.MATCH_ORANGE,
        watch     = Theme.COLORS.WARNING,
        warning   = {220, 100, 50, 255},
        critical  = Theme.COLORS.DANGER,
    }
    local healthColor = healthColors[status] or Theme.COLORS.TEXT_MUTED

    -- 恢复手段按钮（通过观看广告触发）
    local fin = team.finance or {}
    local injectCount = fin.boardInjectionsThisSeason or 0
    local sponsorCount = fin.sponsorSeeksThisSeason or 0
    local commercialCD = FinanceManager.getCommercialCooldown(gameState)

    -- 广告观看进度（存储在 finance 表中）
    local injectAdProgress = fin.injectAdProgress or 0   -- 需看满3次
    local sponsorAdProgress = fin.sponsorAdProgress or 0 -- 需看满2次

    local recoveryBtns = {}

    -- 广告过渡弹窗
    local function showAdDialog(opts)
        -- opts: { title, desc, totalAds, currentProgress, accentColor, onComplete }
        local progress = opts.currentProgress or 0
        local total = opts.totalAds or 1
        local remaining = total - progress

        -- 构建进度点
        local dots = {}
        for i = 1, total do
            table.insert(dots, UI.Panel {
                width = 20, height = 20,
                borderRadius = 10,
                backgroundColor = i <= progress and opts.accentColor or {60, 70, 100, 255},
                marginRight = i < total and 6 or 0,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = i <= progress and "✓" or tostring(i),
                        fontSize = 10,
                        color = i <= progress and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                    },
                },
            })
        end

        UI.ShowOverlay(UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            backgroundColor = {0, 0, 0, 160},
            onClick = function() UI.CloseOverlay() end,
            children = {
                UI.Panel {
                    width = 280,
                    backgroundColor = Theme.COLORS.BG_CARD,
                    borderRadius = 12,
                    padding = 20,
                    alignItems = "center",
                    onClick = function() end,  -- 阻止穿透关闭
                    children = {
                        -- 标题
                        UI.Label {
                            text = opts.title,
                            fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold", marginBottom = 8,
                        },
                        -- 描述
                        UI.Label {
                            text = opts.desc,
                            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
                            textAlign = "center", marginBottom = 14,
                        },
                        -- 进度指示
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            marginBottom = 14,
                            children = dots,
                        },
                        -- 进度文字
                        UI.Label {
                            text = string.format("已观看 %d/%d 次", progress, total),
                            fontSize = 13, color = opts.accentColor,
                            fontWeight = "bold", marginBottom = 16,
                        },
                        -- 观看按钮
                        UI.Button {
                            text = remaining <= 1 and "观看广告并领取" or string.format("观看广告（还需%d次）", remaining),
                            width = "100%", height = 40,
                            backgroundColor = opts.accentColor,
                            borderRadius = 8,
                            fontSize = 14, color = {255, 255, 255, 255}, fontWeight = "bold",
                            onClick = function()
                                UI.CloseOverlay()
                                sdk:ShowRewardVideoAd(function(result)
                                    if result.success then
                                        opts.onComplete()
                                    else
                                        UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
                                    end
                                end)
                            end,
                        },
                        -- 取消
                        UI.Button {
                            text = "取消",
                            width = "100%", height = 34,
                            backgroundColor = {0, 0, 0, 0},
                            borderRadius = 8,
                            fontSize = 13, color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 6,
                            onClick = function() UI.CloseOverlay() end,
                        },
                    },
                },
            },
        })
    end

    -- 董事注资：看满3次广告触发一次注资
    local injectAvail = injectCount < 2
    local injectLabel = injectAvail
        and string.format("董事注资 (%d/2)", injectCount)
        or "注资已用尽"
    if injectAvail and injectAdProgress > 0 then
        injectLabel = string.format("董事注资 (%d/3)", injectAdProgress)
    end
    table.insert(recoveryBtns, UI.Button {
        text = injectLabel,
        height = 34,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = injectAvail and Theme.COLORS.GOLD or Theme.COLORS.BG_SURFACE,
        borderRadius = 8,
        fontSize = 11,
        color = injectAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginRight = 8,
        marginBottom = 6,
        onClick = function(self)
            if not injectAvail then return end
            team.finance = team.finance or {}
            showAdDialog({
                title = "董事注资",
                desc = "观看广告获得董事会注资，\n缓解资金压力",
                totalAds = 3,
                currentProgress = team.finance.injectAdProgress or 0,
                accentColor = Theme.COLORS.GOLD,
                onComplete = function()
                    team.finance = team.finance or {}
                    local progress = (team.finance.injectAdProgress or 0) + 1
                    if progress >= 3 then
                        team.finance.injectAdProgress = 0
                        local ok, msg = FinanceManager.requestBoardInjection(gameState)
                        if ok then
                            gameState:sendMessage({ category = "finance", title = "注资成功", body = msg, priority = "normal" })
                            UI.Toast.Show({ message = "注资成功: " .. msg, variant = "success" })
                        else
                            UI.Toast.Show({ message = msg or "注资失败", variant = "error" })
                        end
                    else
                        team.finance.injectAdProgress = progress
                        UI.Toast.Show({ message = string.format("观看进度 %d/3，再看%d次即可注资", progress, 3 - progress), variant = "info" })
                    end
                    Router.replaceWith("finance", { tab = "overview" })
                end,
            })
        end,
    })

    -- 赞助推介：看满2次广告触发一次赞助
    local sponsorAvail = sponsorCount < 3
    local sponsorLabel = sponsorAvail
        and string.format("赞助推介 (%d/3)", sponsorCount)
        or "推介已用尽"
    if sponsorAvail and sponsorAdProgress > 0 then
        sponsorLabel = string.format("赞助推介 (%d/2)", sponsorAdProgress)
    end
    table.insert(recoveryBtns, UI.Button {
        text = sponsorLabel,
        height = 34,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = sponsorAvail and {35, 80, 60, 255} or Theme.COLORS.BG_SURFACE,
        borderRadius = 8,
        fontSize = 11,
        color = sponsorAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginRight = 8,
        marginBottom = 6,
        onClick = function(self)
            if not sponsorAvail then return end
            team.finance = team.finance or {}
            showAdDialog({
                title = "赞助推介",
                desc = "观看广告获得新赞助商，\n增加俱乐部收入",
                totalAds = 2,
                currentProgress = team.finance.sponsorAdProgress or 0,
                accentColor = {0, 200, 120, 255},
                onComplete = function()
                    team.finance = team.finance or {}
                    local progress = (team.finance.sponsorAdProgress or 0) + 1
                    if progress >= 2 then
                        team.finance.sponsorAdProgress = 0
                        local ok, msg = FinanceManager.seekSponsorship(gameState)
                        if ok then
                            gameState:sendMessage({ category = "finance", title = "推介成功", body = msg, priority = "normal" })
                            UI.Toast.Show({ message = "推介成功: " .. msg, variant = "success" })
                        else
                            UI.Toast.Show({ message = msg or "推介失败", variant = "error" })
                        end
                    else
                        team.finance.sponsorAdProgress = progress
                        UI.Toast.Show({ message = string.format("观看进度 %d/2，再看%d次即可推介", progress, 2 - progress), variant = "info" })
                    end
                    Router.replaceWith("finance", { tab = "overview" })
                end,
            })
        end,
    })

    -- 商业活动：看1次广告即可触发
    local commercialAvail = commercialCD == 0
    table.insert(recoveryBtns, UI.Button {
        text = commercialAvail
            and "商业活动"
            or string.format("商业活动 (%d天)", commercialCD),
        height = 34,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = commercialAvail and {50, 60, 100, 255} or Theme.COLORS.BG_SURFACE,
        borderRadius = 8,
        fontSize = 11,
        color = commercialAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginBottom = 6,
        onClick = function(self)
            if not commercialAvail then return end
            showAdDialog({
                title = "商业活动",
                desc = "观看广告举办商业活动，\n获得一次性收入",
                totalAds = 1,
                currentProgress = 0,
                accentColor = {100, 120, 200, 255},
                onComplete = function()
                    local ok, msg = FinanceManager.hostCommercialEvent(gameState)
                    if ok then
                        gameState:sendMessage({ category = "finance", title = "商业活动成功", body = msg, priority = "normal" })
                        UI.Toast.Show({ message = "商业活动: " .. msg, variant = "success" })
                    else
                        UI.Toast.Show({ message = msg or "活动失败", variant = "error" })
                    end
                    Router.replaceWith("finance", { tab = "overview" })
                end,
            })
        end,
    })

    return UI.Panel {
        width = "100%",
        backgroundImage = "image/bg_finance_boardroom_20260529082656.png",
        backgroundFit = "cover",
        imageTint = {55, 55, 70, 255},  -- 压暗保证内容可读
        borderRadius = 14,
        padding = 16,
        marginBottom = 12,
        overflow = "hidden",
        borderLeftWidth = 3,
        borderColor = healthColor,
        children = {
            -- 评级区：左侧大字母 + 右侧状态信息
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 10,
                children = {
                    -- 大字母评级
                    UI.Panel {
                        width = 56, height = 56,
                        borderRadius = 28,
                        backgroundColor = {healthColor[1], healthColor[2], healthColor[3], 30},
                        alignItems = "center",
                        justifyContent = "center",
                        marginRight = 14,
                        children = {
                            UI.Label {
                                text = gradeInfo.grade,
                                fontSize = 28,
                                color = healthColor,
                                fontWeight = "bold",
                            }
                        }
                    },
                    -- 右侧信息
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "财务健康",
                                        fontSize = 14,
                                        color = Theme.COLORS.TEXT_PRIMARY,
                                        fontWeight = "bold",
                                        marginRight = 8,
                                    },
                                    UI.Panel {
                                        paddingLeft = 8, paddingRight = 8,
                                        paddingTop = 2, paddingBottom = 2,
                                        backgroundColor = healthColor,
                                        borderRadius = 8,
                                        children = {
                                            UI.Label {
                                                text = label,
                                                fontSize = 10,
                                                color = {255, 255, 255, 255},
                                                fontWeight = "bold",
                                            },
                                        }
                                    },
                                }
                            },
                            UI.Label {
                                text = gradeInfo.desc,
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                marginTop = 4,
                            },
                        }
                    },
                }
            },
            -- 细节指标（横向排列）
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                marginBottom = 10,
                children = {
                    Theme.StatPill { label = "工资占比", value = string.format("%.0f%%", details.wagePct or 0),
                        valueColor = (details.wagePct or 0) > 80 and Theme.COLORS.DANGER or Theme.COLORS.TEXT_PRIMARY },
                    Theme.StatPill { label = "可撑周数", value = tostring(math.min(99, details.runwayWeeks or 0)) .. "周",
                        valueColor = (details.runwayWeeks or 99) < 12 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_PRIMARY },
                }
            },
            -- 分隔
            Theme.Divider(),
            -- 恢复手段
            UI.Label {
                text = "恢复手段",
                fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED,
                marginTop = 4,
                marginBottom = 6,
            },
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                children = recoveryBtns,
            },
        }
    }
end

------------------------------------------------------
-- 工具函数
------------------------------------------------------
function Finance._formatMoney(amount)
    return FinanceManager.formatMoney(amount)
end

return Finance
