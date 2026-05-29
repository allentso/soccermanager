-- ui/screens/finance.lua
-- 财务管理页面 - 增强版：趋势可视化 / 分类过滤 / 详细流水

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local FinanceManager = require("scripts/systems/finance_manager")

local Finance = {}

-- 状态持久化
local _activeTab = "overview"  -- overview | facilities | transactions
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
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "财务管理",
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
            Theme.MoreSubNav("finance"),

            -- 标签切换：概览 / 流水
            Finance._buildTabBar(),

            -- 内容
            content,

            -- 底部导航
            Theme.MainNav("more"),
        }
    }
end

------------------------------------------------------
-- 标签栏
------------------------------------------------------
function Finance._buildTabBar()
    local tabs = {
        { key = "overview", label = "财务概览" },
        { key = "facilities", label = "设施" },
        { key = "transactions", label = "收支流水" },
    }
    local tabBtns = {}
    for _, t in ipairs(tabs) do
        local isActive = t.key == _activeTab
        table.insert(tabBtns, UI.Button {
            text = t.label,
            height = 32,
            paddingLeft = 16,
            paddingRight = 16,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            fontSize = 13,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
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
-- 概览标签
------------------------------------------------------
function Finance._buildOverview(team, gameState)
    -- 工资计算
    local totalPlayerWage = 0
    local totalStaffWage = 0
    local highestWagePlayer = nil
    local highestWage = 0
    local top5Wages = {}

    local playerWages = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then
            totalPlayerWage = totalPlayerWage + (p.wage or 0)
            table.insert(playerWages, { name = p.displayName, wage = p.wage or 0 })
            if p.wage and p.wage > highestWage then
                highestWage = p.wage
                highestWagePlayer = p
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
    local wageBudgetUsage = team.wageBudget > 0 and math.floor(totalWeeklyWage / team.wageBudget * 100) or 0
    local wageStatusColor = wageBudgetUsage > 90 and Theme.COLORS.DANGER
        or (wageBudgetUsage > 70 and Theme.COLORS.WARNING or Theme.COLORS.SECONDARY)

    -- 净资产计算
    local netIncome = (team.seasonIncome or 0) - (team.seasonExpense or 0)
    local netColor = netIncome >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER

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
            -- 资金总览卡片
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "资金状况" },
                    -- 大字显示余额
                    UI.Label {
                        text = Finance._formatMoney(team.balance),
                        fontSize = 28,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginTop = 4,
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
                            Theme.StatPill { label = "工资预算", value = Finance._formatMoney(team.wageBudget) .. "/周" },
                        }
                    },
                }
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

            -- 工资预算使用率
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
                                text = "  " .. Finance._formatMoney(totalWeeklyWage) .. " / " .. Finance._formatMoney(team.wageBudget) .. " 周预算",
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

            -- 近期收支趋势
            Finance._buildTrendCard(team),

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
                            backgroundColor = cost and Theme.COLORS.PRIMARY or Theme.COLORS.TEXT_MUTED,
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

    return UI.ScrollView {
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        padding = 14,
        children = rows,
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
            marginBottom = 6,
            children = {
                -- 周标签
                UI.Label {
                    text = "W" .. tonumber(weekLabel),
                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    marginBottom = 2,
                },
                -- 收入条
                UI.Panel {
                    width = "100%", height = 8,
                    backgroundColor = {38, 46, 71, 255},
                    borderRadius = 4,
                    overflow = "hidden",
                    marginBottom = 2,
                    children = {
                        UI.Panel {
                            width = math.max(2, incPct) .. "%",
                            height = "100%",
                            backgroundColor = Theme.COLORS.SECONDARY,
                            borderRadius = 4,
                        },
                    }
                },
                -- 支出条
                UI.Panel {
                    width = "100%", height = 8,
                    backgroundColor = {38, 46, 71, 255},
                    borderRadius = 4,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = math.max(2, expPct) .. "%",
                            height = "100%",
                            backgroundColor = Theme.COLORS.DANGER,
                            borderRadius = 4,
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
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
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
            local catLabel = ""
            if tx.category == "transfer" then catLabel = "[转会]"
            elseif tx.category == "wage" then catLabel = "[薪资]"
            elseif tx.category == "prize" then catLabel = "[奖金]"
            elseif tx.category == "ticket" then catLabel = "[票房]"
            elseif tx.category == "sponsor" then catLabel = "[赞助]"
            else catLabel = ""
            end

            local dateStr = ""
            if tx.week and tx.season then
                dateStr = "S" .. tx.season .. " W" .. tx.week
            elseif tx.date then
                dateStr = tx.date
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
                                text = (catLabel ~= "" and catLabel .. " " or "") .. (tx.description or "未知"),
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
-- 财务健康卡片 + 恢复手段
------------------------------------------------------
function Finance._buildHealthCard(team, gameState)
    local teamId = gameState.playerTeamId
    local status, details = FinanceManager.getFinanceHealth(gameState, teamId)
    local label = FinanceManager.getHealthLabel(status)

    -- 颜色映射
    local healthColors = {
        stable   = Theme.COLORS.SECONDARY,
        watch    = Theme.COLORS.ACCENT,
        warning  = Theme.COLORS.WARNING,
        critical = Theme.COLORS.DANGER,
    }
    local healthColor = healthColors[status] or Theme.COLORS.TEXT_MUTED

    -- 描述文本
    local descTexts = {
        stable   = "俱乐部财务状况良好，继续保持！",
        watch    = "财务出现压力信号，建议关注开支。",
        warning  = "财务紧张，需要控制支出或寻求收入来源。",
        critical = "财务危机！必须立即采取行动避免破产。",
    }
    local desc = descTexts[status] or ""

    -- 恢复手段按钮
    local fin = team.finance or {}
    local injectCount = fin.boardInjectionsThisSeason or 0
    local sponsorCount = fin.sponsorSeeksThisSeason or 0
    local commercialCD = FinanceManager.getCommercialCooldown(gameState)

    local recoveryBtns = {}

    -- 董事注资按钮
    local injectAvail = injectCount < 2
    table.insert(recoveryBtns, UI.Button {
        text = injectAvail
            and string.format("董事注资 (%d/2)", injectCount)
            or "注资已用尽",
        height = 36,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = injectAvail and Theme.COLORS.PRIMARY or {50, 55, 75, 255},
        borderRadius = 8,
        fontSize = 12,
        color = injectAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginRight = 8,
        marginBottom = 6,
        disabled = not injectAvail,
        onClick = function()
            if not injectAvail then return end
            local ok, msg = FinanceManager.requestBoardInjection(gameState)
            if ok then
                gameState:sendMessage({ category = "finance", title = "注资成功", body = msg, priority = "normal" })
            else
                gameState:sendMessage({ category = "finance", title = "注资失败", body = msg, priority = "low" })
            end
            Router.replaceWith("finance")
        end,
    })

    -- 赞助推介按钮
    local sponsorAvail = sponsorCount < 3
    table.insert(recoveryBtns, UI.Button {
        text = sponsorAvail
            and string.format("赞助推介 (%d/3)", sponsorCount)
            or "推介已用尽",
        height = 36,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = sponsorAvail and {45, 90, 70, 255} or {50, 55, 75, 255},
        borderRadius = 8,
        fontSize = 12,
        color = sponsorAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginRight = 8,
        marginBottom = 6,
        disabled = not sponsorAvail,
        onClick = function()
            if not sponsorAvail then return end
            local ok, msg = FinanceManager.seekSponsorship(gameState)
            if ok then
                gameState:sendMessage({ category = "finance", title = "推介成功", body = msg, priority = "normal" })
            else
                gameState:sendMessage({ category = "finance", title = "推介失败", body = msg, priority = "low" })
            end
            Router.replaceWith("finance")
        end,
    })

    -- 商业活动按钮
    local commercialAvail = commercialCD == 0
    table.insert(recoveryBtns, UI.Button {
        text = commercialAvail
            and "举办商业活动"
            or string.format("商业活动 (冷却%d天)", commercialCD),
        height = 36,
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = commercialAvail and {60, 75, 120, 255} or {50, 55, 75, 255},
        borderRadius = 8,
        fontSize = 12,
        color = commercialAvail and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
        marginBottom = 6,
        disabled = not commercialAvail,
        onClick = function()
            if not commercialAvail then return end
            local ok, msg = FinanceManager.hostCommercialEvent(gameState)
            if ok then
                gameState:sendMessage({ category = "finance", title = "商业活动成功", body = msg, priority = "normal" })
            else
                gameState:sendMessage({ category = "finance", title = "活动失败", body = msg, priority = "low" })
            end
            Router.replaceWith("finance")
        end,
    })

    return Theme.Card {
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    Theme.Subtitle { text = "财务健康" },
                    UI.Panel { flexGrow = 1 },
                    -- 状态徽章
                    UI.Panel {
                        paddingLeft = 10, paddingRight = 10,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = healthColor,
                        borderRadius = 10,
                        children = {
                            UI.Label {
                                text = label,
                                fontSize = 12,
                                color = {255, 255, 255, 255},
                                fontWeight = "bold",
                            },
                        }
                    },
                }
            },
            -- 描述
            UI.Label {
                text = desc,
                fontSize = 12,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginTop = 6,
            },
            -- 细节指标
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                marginTop = 8,
                children = {
                    Theme.StatPill { label = "工资占比", value = string.format("%.0f%%", details.wagePct or 0) },
                    Theme.StatPill { label = "资金可撑", value = tostring(math.min(99, details.runwayWeeks or 0)) .. "周" },
                }
            },
            -- 分隔线
            Theme.Divider(),
            -- 恢复手段
            UI.Label {
                text = "财务恢复手段",
                fontSize = 13,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
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
    if not amount then return "0" end
    local abs = math.abs(amount)
    if abs >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif abs >= 1000 then
        return string.format("%.0fK", amount / 1000)
    else
        return tostring(math.floor(amount))
    end
end

return Finance
