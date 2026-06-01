-- ui/screens/market.lua
-- 转会市场页面 - 搜索/筛选/出价/我的报价

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local LoansTab = require("scripts/ui/screens/market/loans_tab")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local Market = {}

-- 页面Tab
local TABS = {
    { key = "browse",   label = "浏览" },
    { key = "free",     label = "自由球员" },
    { key = "loans",    label = "租借" },
    { key = "scout",    label = "球探" },
    { key = "my_bids",  label = "报价" },
    { key = "listed",   label = "出售" },
}

-- 位置筛选
local POSITION_FILTERS = {
    { key = "all", label = "全部" },
    { key = "GK",  label = "门将" },
    { key = "DEF", label = "后卫" },
    { key = "MID", label = "中场" },
    { key = "FWD", label = "前锋" },
}

-- 判断球员属于哪个位置组
local function getPositionGroup(pos)
    for group, positions in pairs(Constants.POSITION_GROUPS) do
        for _, p in ipairs(positions) do
            if p == pos then return group end
        end
    end
    return "MID"
end

function Market.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local currentTab = (params and params.tab) or "browse"
    local posFilter = (params and params.posFilter) or "all"

    -- 根据Tab选择内容
    local contentChildren = {}
    if currentTab == "browse" then
        contentChildren = Market._buildBrowseContent(gameState, posFilter)
    elseif currentTab == "free" then
        contentChildren = Market._buildFreeAgentsContent(gameState, posFilter)
    elseif currentTab == "loans" then
        contentChildren = Market._buildLoansContent(gameState)
    elseif currentTab == "my_bids" then
        contentChildren = Market._buildMyBidsContent(gameState)
    elseif currentTab == "scout" then
        contentChildren = Market._buildScoutContent(gameState)
    elseif currentTab == "listed" then
        contentChildren = Market._buildListedContent(gameState)
    end

    -- Tab按钮
    local tabButtons = {}
    for _, tab in ipairs(TABS) do
        local isActive = tab.key == currentTab
        table.insert(tabButtons, UI.Button {
            text = tab.label,
            height = 34,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 17,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 6,
            onClick = function()
                Router.replaceWith("market", { tab = tab.key, posFilter = posFilter })
            end,
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
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "转会市场",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Button {
                        text = "球探", width = 44, height = 30,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        borderRadius = 4,
                        fontSize = 12, color = Theme.COLORS.ACCENT,
                        onClick = function() Router.navigate("scouting") end,
                    },
                    UI.Button {
                        text = "动态", width = 44, height = 30,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        borderRadius = 4,
                        fontSize = 12, color = Theme.COLORS.ACCENT,
                        onClick = function() Router.navigate("transfer_hub") end,
                    },
                }
            },

            -- Tab栏
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

            -- 内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = contentChildren,
            },

            -- 底部导航
            Theme.MainNav("market"),
        }
    }
end

-- 浏览球员
function Market._buildBrowseContent(gameState, posFilter)
    local children = {}

    -- 位置筛选条
    local filterBtns = {}
    for _, f in ipairs(POSITION_FILTERS) do
        local isActive = f.key == posFilter
        table.insert(filterBtns, UI.Button {
            text = f.label,
            height = 28,
            paddingLeft = 8,
            paddingRight = 8,
            backgroundColor = isActive and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Router.replaceWith("market", { tab = "browse", posFilter = f.key })
            end,
        })
    end

    table.insert(children, UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        children = filterBtns,
    })

    -- 收集可转会球员
    local availablePlayers = {}
    for _, p in pairs(gameState.players) do
        if p.teamId ~= gameState.playerTeamId and not p.retired then
            -- 位置过滤
            if posFilter == "all" or getPositionGroup(p.position) == posFilter then
                table.insert(availablePlayers, p)
            end
        end
    end

    -- 按能力排序取前40
    table.sort(availablePlayers, function(a, b) return a.overall > b.overall end)

    -- 球员列表
    local maxShow = math.min(40, #availablePlayers)
    for i = 1, maxShow do
        local p = availablePlayers[i]
        local team = gameState.teams[p.teamId]
        local hasBid = TransferManager.hasPendingBid(gameState, p.id)
        local releaseClause = TransferManager.getReleaseClause(gameState, p.id)
        local attitude = TransferManager.getPlayerTransferAttitude(gameState, p.id, gameState.playerTeamId)
        local competingBids = TransferManager.getCompetingBids(gameState, p.id)

        -- 态度颜色和文本
        local attitudeText = attitude == "eager" and "想转会" or (attitude == "open" and "愿考虑" or (attitude == "reluctant" and "不情愿" or "拒绝"))
        local attitudeColor = attitude == "eager" and Theme.COLORS.SECONDARY
            or (attitude == "open" and Theme.COLORS.ACCENT
            or (attitude == "reluctant" and Theme.COLORS.WARNING or Theme.COLORS.DANGER))

        -- 附加信息标签
        local extraTags = {}
        if releaseClause then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {80, 60, 20, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "解约 " .. Market._formatValue(releaseClause), fontSize = 9, color = {255, 200, 80, 255} } },
            })
        end
        if #competingBids > 0 then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {80, 30, 30, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = #competingBids .. "队竞价", fontSize = 9, color = {255, 120, 120, 255} } },
            })
        end

        table.insert(children, UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                -- 第一行：名字 + 能力值 + 身价 + 报价按钮
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Panel {
                            backgroundColor = {attitudeColor[1], attitudeColor[2], attitudeColor[3], 30},
                            borderRadius = 3, paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1, marginRight = 8,
                            children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = attitudeColor } },
                        },
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                            children = {
                                UI.Label { text = p.displayName, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            },
                        },
                        UI.Label {
                            text = tostring(p.overall),
                            fontSize = 16, color = Theme.COLORS.SECONDARY, fontWeight = "bold", marginRight = 10,
                        },
                        UI.Button {
                            text = hasBid and "已报" or (releaseClause and "解约" or "报价"),
                            width = 50, height = 28,
                            backgroundColor = hasBid and Theme.COLORS.TEXT_MUTED or Theme.COLORS.PRIMARY,
                            borderRadius = 6, fontSize = 12,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                if not hasBid then
                                    if releaseClause then
                                        TransferManager.triggerReleaseClause(gameState, p.id)
                                        UI.Toast.Show({ message = "已触发解约金买断", variant = "success" })
                                        Router.replaceWith("market", { tab = "browse", posFilter = posFilter })
                                    else
                                        Market._showBidSheet(gameState, p, posFilter)
                                    end
                                end
                            end,
                        },
                    },
                },
                -- 第二行：球队 | 年龄 | 身价 | 态度 | 标签
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                    children = {
                        UI.Label {
                            text = (team and team.name or "自由"),
                            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexShrink = 1,
                        },
                        UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = p:getAge(gameState.date.year) .. "岁", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = Market._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                        UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = attitudeText, fontSize = 11, color = attitudeColor },
                        UI.Panel { flexGrow = 1 },
                        table.unpack(extraTags),
                    },
                },
            },
        })
    end

    if maxShow == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 100,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "未找到球员", fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    end

    return children
end

-- 报价谈判弹窗
function Market._showBidSheet(gameState, player, posFilter)
    local team = gameState:getPlayerTeam()
    local budget = team and team.transferBudget or 0
    local baseValue = player.value
    local sellerTeam = gameState.teams[player.teamId]
    local currentWage = player.wage or 5000

    local clauseOptions = {
        { key = "simple", label = "一次付清·无附加条款", installments = 1, bonus = 0, sellOn = 0 },
        { key = "standard", label = "2期·出场奖金8%·转售10%", installments = 2, bonus = 0.08, sellOn = 10 },
        { key = "heavy", label = "3期·出场奖金12%·转售15%", installments = 3, bonus = 0.12, sellOn = 15 },
    }
    local yearsOptions = { 2, 3, 4, 5 }

    -- 状态
    local selectedClauseIdx = 2
    local selectedYearsIdx = 2

    -- 创建带引用的控件
    local bidField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "输入报价（万）",
        value = tostring(math.floor(baseValue * 1.1 / 10000)),
        fontSize = 14, borderRadius = 6,
    }

    local wageField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "输入周薪（万）",
        value = tostring(math.floor(currentWage / 10000)),
        fontSize = 14, borderRadius = 6,
    }

    -- 快捷报价按钮
    local bidPresets = {
        { label = "×0.9", multiplier = 0.9 },
        { label = "×1.0", multiplier = 1.0 },
        { label = "×1.1", multiplier = 1.1 },
        { label = "×1.2", multiplier = 1.2 },
        { label = "×1.35", multiplier = 1.35 },
    }
    local bidPresetBtns = {}
    for _, p in ipairs(bidPresets) do
        local amount = math.floor(baseValue * p.multiplier / 10000)
        table.insert(bidPresetBtns, UI.Button {
            text = p.label,
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                bidField:SetValue(tostring(amount))
            end,
        })
    end

    -- 快捷周薪按钮
    local wagePresets = { 0.9, 1.0, 1.2, 1.5 }
    local wagePresetBtns = {}
    for _, mul in ipairs(wagePresets) do
        local wage = math.floor(currentWage * mul / 10000)
        table.insert(wagePresetBtns, UI.Button {
            text = Market._formatValue(wage * 10000),
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                wageField:SetValue(tostring(wage))
            end,
        })
    end

    -- 条款按钮（用闭包切换选中状态）
    local clauseBtns = {}
    for i, c in ipairs(clauseOptions) do
        local btn = UI.Button {
            text = (i == selectedClauseIdx and "● " or "  ") .. c.label,
            width = "100%", height = 34, marginBottom = 3,
            backgroundColor = (i == selectedClauseIdx) and Theme.COLORS.ACCENT or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12, textAlign = "left", paddingLeft = 10,
            color = (i == selectedClauseIdx) and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function(self)
                selectedClauseIdx = i
                for j, b in ipairs(clauseBtns) do
                    local isSel = (j == i)
                    b:SetText((isSel and "● " or "  ") .. clauseOptions[j].label)
                    b:SetStyle({
                        width = "100%",
                        backgroundColor = isSel and Theme.COLORS.ACCENT or {38, 46, 71, 255},
                        color = isSel and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                    })
                end
            end,
        }
        table.insert(clauseBtns, btn)
    end

    -- 年限按钮
    local yearsBtns = {}
    for i, y in ipairs(yearsOptions) do
        local btn = UI.Button {
            text = (i == selectedYearsIdx and "● " or "") .. y .. "年",
            height = 30, marginRight = 6,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = (i == selectedYearsIdx) and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12,
            color = (i == selectedYearsIdx) and {20, 20, 20, 255} or Theme.COLORS.TEXT_SECONDARY,
            onClick = function(self)
                selectedYearsIdx = i
                for j, b in ipairs(yearsBtns) do
                    local isSel = (j == i)
                    b:SetText((isSel and "● " or "") .. yearsOptions[j] .. "年")
                    b:SetStyle({
                        backgroundColor = isSel and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
                        color = isSel and {20, 20, 20, 255} or Theme.COLORS.TEXT_SECONDARY,
                    })
                end
            end,
        }
        table.insert(yearsBtns, btn)
    end

    local children = {}

    -- 球员信息
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 12,
        children = {
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label { text = player.displayName, fontSize = 16, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY },
                    UI.Label {
                        text = string.format("%s | %s | 能力 %d | %d岁",
                            sellerTeam and sellerTeam.name or "?",
                            Constants.POSITION_NAMES[player.position] or player.position,
                            player.overall,
                            player:getAge(gameState.date.year)),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 3,
                    },
                }
            },
            UI.Panel {
                backgroundColor = {Theme.COLORS.ACCENT[1], Theme.COLORS.ACCENT[2], Theme.COLORS.ACCENT[3], 40},
                borderRadius = 6, paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                children = {
                    UI.Label { text = "身价 " .. Market._formatValue(baseValue), fontSize = 12, color = Theme.COLORS.ACCENT },
                },
            },
        }
    })

    -- 报价金额
    table.insert(children, UI.Label { text = "报价金额（万）", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
        children = { bidField },
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10,
        children = bidPresetBtns,
    })

    -- 合同条款
    table.insert(children, UI.Label { text = "合同条款", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 })
    for _, btn in ipairs(clauseBtns) do
        table.insert(children, btn)
    end

    -- 球员周薪
    table.insert(children, UI.Label { text = "球员周薪（万/周）", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginTop = 10, marginBottom = 4 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
        children = { wageField },
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10,
        children = wagePresetBtns,
    })

    -- 合同年限
    table.insert(children, UI.Label { text = "合同年限", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        children = yearsBtns,
    })

    -- 提交按钮
    local submitBtn = UI.Button {
        text = "提交报价",
        width = "100%", height = 44, marginTop = 12,
        backgroundColor = Theme.COLORS.PRIMARY,
        borderRadius = 8, fontSize = 15, fontWeight = "bold",
        color = Theme.COLORS.TEXT_PRIMARY,
        onClick = function()
            local bidText = bidField:GetValue() or ""
            local bidAmount = tonumber(bidText)
            if not bidAmount or bidAmount <= 0 then return end
            local offerAmount = math.floor(bidAmount * 10000)

            local wageText = wageField:GetValue() or ""
            local wageAmount = tonumber(wageText)
            if not wageAmount or wageAmount <= 0 then return end
            local offeredWage = math.floor(wageAmount * 10000)

            if offerAmount > budget then return end

            local clause = clauseOptions[selectedClauseIdx]
            local offeredYears = yearsOptions[selectedYearsIdx]
            local appearanceBonus = math.floor(baseValue * clause.bonus)

            local clauses = {}
            if clause.installments > 1 then
                clauses.installments = clause.installments
            end
            if clause.bonus > 0 then
                clauses.appearanceBonus = { count = 20, amount = appearanceBonus }
            end
            if clause.sellOn > 0 then
                clauses.sellOnPercent = clause.sellOn
            end
            local bid = TransferManager.makeBidWithClauses(gameState, player.id, offerAmount, offeredWage, clauses)
            if bid then
                bid.contractYears = offeredYears
                UI.Toast.Show({ message = "报价已提交", variant = "success" })
            else
                UI.Toast.Show({ message = "报价失败", variant = "error" })
            end
            BottomSheet.close()
            Router.replaceWith("market", { tab = "my_bids" })
        end,
    }

    BottomSheet.showCustom({
        title = "转会报价 — " .. player.displayName,
        height = 680,
        showCancel = true,
        children = children,
        footer = submitBtn,
    })
end

-- 我的报价
function Market._buildMyBidsContent(gameState)
    local children = {}
    local bids = TransferManager.getPlayerBids(gameState)

    if #bids == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无活跃报价", fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
        return children
    end

    for _, bid in ipairs(bids) do
        local player = gameState.players[bid.playerId]
        local sellerTeam = player and gameState.teams[bid.sellerTeamId] or nil

        -- 状态颜色/文本
        local statusText = "处理中"
        local statusColor = Theme.COLORS.ACCENT
        if bid.status == "accepted" or bid.status == "completed" then
            statusText = "已接受"
            statusColor = Theme.COLORS.SECONDARY
        elseif bid.status == "rejected" then
            statusText = "被拒绝"
            statusColor = Theme.COLORS.DANGER
        elseif bid.status == "negotiating" then
            statusText = string.format("谈判中 %d/%d", (bid.currentRound or 0) + 1, bid.maxRounds or 4)
            statusColor = {156, 39, 176, 255}
        elseif bid.status == "fee_agreed" then
            statusText = "待协商个人条款"
            statusColor = Theme.COLORS.WARNING
        elseif bid.status == "cancelled" then
            statusText = "已撤回"
            statusColor = Theme.COLORS.TEXT_MUTED
        end

        local cardChildren = {
            -- 头部：球员信息 + 状态
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = player and player.displayName or "未知球员",
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            },
                            UI.Label {
                                text = (sellerTeam and sellerTeam.name or "自由") ..
                                    " | " .. (player and Constants.POSITION_NAMES[player.position] or ""),
                                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                            },
                        }
                    },
                    -- 状态标签
                    UI.Panel {
                        backgroundColor = {statusColor[1], statusColor[2], statusColor[3], 40},
                        borderRadius = 4,
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 3, paddingBottom = 3,
                        children = {
                            UI.Label { text = statusText, fontSize = 11, color = statusColor },
                        }
                    },
                }
            },
            -- 报价金额行
            UI.Panel {
                flexDirection = "row", marginTop = 8, alignItems = "center",
                children = {
                    UI.Label {
                        text = "我方报价: " .. Market._formatValue(bid.amount),
                        fontSize = 13, color = Theme.COLORS.ACCENT,
                    },
                    UI.Label {
                        text = "  身价: " .. Market._formatValue(bid.playerValue or 0),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
                        flexGrow = 1,
                    },
                    -- 撤回按钮（pending状态可用）
                    (bid.status == "pending" or bid.status == "negotiating") and UI.Button {
                        text = "撤回",
                        width = 50, height = 26,
                        backgroundColor = Theme.COLORS.DANGER,
                        borderRadius = 4, fontSize = 11,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            TransferManager.cancelBid(gameState, bid.id)
                            UI.Toast.Show({ message = "报价已撤回", variant = "info" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    } or nil,
                }
            },
        }

        -- 谈判中：显示对方还价 + 加价按钮
        if bid.status == "negotiating" and bid.counterAmount then
            -- 对方还价信息
            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8, padding = 10,
                backgroundColor = {156, 39, 176, 20}, borderRadius = 6,
                borderWidth = 1, borderColor = {156, 39, 176, 80},
                children = {
                    UI.Label {
                        text = "对方要价: " .. Market._formatValue(bid.counterAmount),
                        fontSize = 14, color = {156, 39, 176, 255}, fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("差距: %s (%.0f%%)",
                            Market._formatValue(bid.counterAmount - bid.amount),
                            (bid.counterAmount - bid.amount) / math.max(bid.amount, 1) * 100),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 3,
                    },
                }
            })

            -- 加价快捷按钮
            local gap = bid.counterAmount - bid.amount
            local raise25 = bid.amount + math.floor(gap * 0.25 / 1000) * 1000
            local raise50 = bid.amount + math.floor(gap * 0.5 / 1000) * 1000
            local raiseFull = bid.counterAmount

            table.insert(cardChildren, UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 8,
                justifyContent = "space-between",
                children = {
                    UI.Button {
                        text = "+25%\n" .. Market._formatValue(raise25),
                        width = "30%", height = 44,
                        backgroundColor = {60, 80, 40, 255}, borderRadius = 6,
                        fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            TransferManager.raiseBid(gameState, bid.id, raise25)
                            UI.Toast.Show({ message = "加价已提交", variant = "success" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                    UI.Button {
                        text = "+50%\n" .. Market._formatValue(raise50),
                        width = "30%", height = 44,
                        backgroundColor = {80, 80, 40, 255}, borderRadius = 6,
                        fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            TransferManager.raiseBid(gameState, bid.id, raise50)
                            UI.Toast.Show({ message = "加价已提交", variant = "success" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                    UI.Button {
                        text = "满足要价\n" .. Market._formatValue(raiseFull),
                        width = "36%", height = 44,
                        backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 6,
                        fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                        onClick = function()
                            TransferManager.raiseBid(gameState, bid.id, raiseFull)
                            UI.Toast.Show({ message = "已满足对方要价", variant = "success" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                }
            })

            -- 谈判历史（如有多轮）
            if bid.rounds and #bid.rounds > 1 then
                local historyChildren = {
                    UI.Label { text = "谈判历史", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
                }
                for i, r in ipairs(bid.rounds) do
                    table.insert(historyChildren, UI.Panel {
                        width = "100%", flexDirection = "row", height = 20, alignItems = "center",
                        children = {
                            UI.Label { text = "R" .. tostring(r.round), fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                            UI.Label { text = "出价 " .. Market._formatValue(r.offer), fontSize = 10, color = Theme.COLORS.ACCENT, flexGrow = 1 },
                            UI.Label { text = "还价 " .. Market._formatValue(r.counter), fontSize = 10, color = {156, 39, 176, 255} },
                        }
                    })
                end
                table.insert(cardChildren, UI.Panel {
                    width = "100%", marginTop = 6, paddingTop = 6,
                    borderTopWidth = 1, borderColor = Theme.COLORS.BORDER,
                    children = historyChildren,
                })
            end
        end

        -- fee_agreed：个人条款协商入口
        if bid.status == "fee_agreed" then
            local attempts = bid.personalTermsAttempts or 0
            local remaining = 3 - attempts
            local currentWage = bid.wageOffer or 0

            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8, padding = 10,
                backgroundColor = {Theme.COLORS.WARNING[1], Theme.COLORS.WARNING[2], Theme.COLORS.WARNING[3], 20},
                borderRadius = 6,
                borderWidth = 1, borderColor = {Theme.COLORS.WARNING[1], Theme.COLORS.WARNING[2], Theme.COLORS.WARNING[3], 80},
                children = {
                    UI.Label {
                        text = "转会费已达成协议，球员拒绝了当前个人条款",
                        fontSize = 12, color = Theme.COLORS.WARNING, fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("当前报价周薪: %s · 剩余协商机会: %d次",
                            Market._formatValue(currentWage), remaining),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                    },
                }
            })

            -- 薪资调整输入 + 快捷按钮
            local wageField = UI.TextField {
                flexGrow = 1, height = 38,
                placeholder = "输入新周薪（万）",
                value = tostring(math.floor(currentWage * 1.2 / 10000)),
                fontSize = 14, borderRadius = 6,
            }

            -- 快捷加薪按钮
            local wagePresets = {
                { label = "+20%", multiplier = 1.2 },
                { label = "+50%", multiplier = 1.5 },
                { label = "×2", multiplier = 2.0 },
            }
            local wagePresetBtns = {}
            for _, wp in ipairs(wagePresets) do
                local newWage = math.floor(currentWage * wp.multiplier / 10000)
                table.insert(wagePresetBtns, UI.Button {
                    text = wp.label .. " (" .. Market._formatValue(newWage * 10000) .. ")",
                    height = 28, paddingLeft = 8, paddingRight = 8, marginRight = 4,
                    backgroundColor = {38, 46, 71, 255},
                    borderRadius = 5, fontSize = 11,
                    color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        wageField:SetValue(tostring(newWage))
                    end,
                })
            end

            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8,
                children = {
                    UI.Label { text = "调整周薪报价（万/周）", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
                        children = { wageField },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8,
                        children = wagePresetBtns,
                    },
                },
            })

            -- 重新协商按钮 + 放弃按钮
            local bidId = bid.id
            table.insert(cardChildren, UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 8,
                children = {
                    UI.Button {
                        text = "重新协商个人条款",
                        flexGrow = 1, height = 40, marginRight = 8,
                        backgroundColor = Theme.COLORS.WARNING,
                        borderRadius = 6, fontSize = 14, fontWeight = "bold",
                        color = {20, 20, 20, 255},
                        onClick = function()
                            local wageText = wageField:GetValue() or ""
                            local wageAmount = tonumber(wageText)
                            if not wageAmount or wageAmount <= 0 then return end
                            local newWage = math.floor(wageAmount * 10000)
                            TransferManager.negotiatePersonalTerms(gameState, bidId, newWage)
                            UI.Toast.Show({ message = "新合同报价已发送", variant = "success" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                    UI.Button {
                        text = "放弃",
                        width = 60, height = 40,
                        backgroundColor = {60, 40, 40, 255},
                        borderRadius = 6, fontSize = 13,
                        color = Theme.COLORS.DANGER,
                        onClick = function()
                            TransferManager.cancelBid(gameState, bidId)
                            UI.Toast.Show({ message = "已放弃签约", variant = "info" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                },
            })
        end

        table.insert(children, Theme.Card { children = cardChildren })
    end

    return children
end

-- 挂牌出售（我方球员）
function Market._buildListedContent(gameState)
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 分类球员：已挂牌 vs 可挂牌
    local listedPlayers = {}
    local availablePlayers = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then
            if p.listedForSale then
                table.insert(listedPlayers, p)
            else
                table.insert(availablePlayers, p)
            end
        end
    end

    -- === 已挂牌球员区 ===
    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 10, paddingBottom = 6,
        children = {
            UI.Label {
                text = string.format("已挂牌出售 (%d人)", #listedPlayers),
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
            },
        }
    })

    if #listedPlayers == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 50,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无挂牌球员，从下方选择球员挂牌", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, p in ipairs(listedPlayers) do
            local hasBid = TransferManager.hasPendingIncomingBid(gameState, p.id)
            local posColor = hasBid and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED

            -- 获取报价信息
            local bidInfo = ""
            if hasBid then
                local bids = TransferManager.getPendingSellBids(gameState)
                for _, b in ipairs(bids) do
                    if b.playerId == p.id and b.isIncomingBid then
                        local buyer = gameState.teams[b.buyerTeamId]
                        bidInfo = (buyer and buyer.name or "未知") .. " 出价 " .. Market._formatValue(b.amount)
                        break
                    end
                end
            end

            table.insert(children, UI.Panel {
                width = "100%",
                paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                backgroundColor = hasBid and {40, 50, 30, 255} or {0, 0, 0, 0},
                children = {
                    -- 第一行：位置徽章 + 名字 + 能力值 + 按钮
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Panel {
                                backgroundColor = {posColor[1], posColor[2], posColor[3], 30},
                                borderRadius = 3, paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1, marginRight = 8,
                                children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = posColor } },
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                                children = {
                                    UI.Label { text = p.displayName, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                },
                            },
                            UI.Label {
                                text = tostring(p.overall),
                                fontSize = 16, color = Theme.COLORS.SECONDARY, fontWeight = "bold", marginRight = 10,
                            },
                            hasBid and UI.Button {
                                text = "处理",
                                width = 50, height = 28,
                                backgroundColor = Theme.COLORS.ACCENT,
                                borderRadius = 6, fontSize = 12,
                                color = {255, 255, 255, 255},
                                onClick = function()
                                    Market._showOfferSheet(gameState, p)
                                end,
                            } or UI.Button {
                                text = "取消",
                                width = 50, height = 28,
                                backgroundColor = {80, 80, 100, 255},
                                borderRadius = 6, fontSize = 12,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                onClick = function()
                                    p.listedForSale = false
                                    Router.replaceWith("market", { tab = "listed" })
                                end,
                            },
                        },
                    },
                    -- 第二行：身价 | 报价状态
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                        children = {
                            UI.Label { text = Market._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                            UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                            UI.Label {
                                text = hasBid and bidInfo or "等待报价",
                                fontSize = 11,
                                color = hasBid and Theme.COLORS.FINANCE_GREEN or Theme.COLORS.TEXT_MUTED,
                            },
                        },
                    },
                },
            })
        end
    end

    -- === 可挂牌球员区 ===
    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 14, paddingBottom = 6,
        borderTopWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = "选择球员挂牌出售",
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
            },
            UI.Label {
                text = "挂牌后 AI 球队会主动报价",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
            },
        }
    })

    -- 按能力排序，方便用户选择
    table.sort(availablePlayers, function(a, b) return a.overall > b.overall end)

    for _, p in ipairs(availablePlayers) do
        local isSafe, _ = FinanceManager.checkSquadSafety(gameState, p.id)
        table.insert(children, UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                -- 第一行：位置徽章 + 名字 + 能力值 + 挂牌按钮
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Panel {
                            backgroundColor = {Theme.COLORS.TEXT_MUTED[1], Theme.COLORS.TEXT_MUTED[2], Theme.COLORS.TEXT_MUTED[3], 30},
                            borderRadius = 3, paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1, marginRight = 8,
                            children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = Theme.COLORS.TEXT_MUTED } },
                        },
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                            children = {
                                UI.Label { text = p.displayName, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            },
                        },
                        UI.Label {
                            text = tostring(p.overall),
                            fontSize = 16, color = Theme.COLORS.SECONDARY, fontWeight = "bold", marginRight = 10,
                        },
                        isSafe and UI.Button {
                            text = "挂牌",
                            width = 50, height = 28,
                            backgroundColor = Theme.COLORS.ACCENT,
                            borderRadius = 6, fontSize = 12,
                            color = {255, 255, 255, 255},
                            onClick = function()
                                p.listedForSale = true
                                gameState:sendMessage({
                                    category = "transfer",
                                    title = p.displayName .. " 已挂牌",
                                    body = p.displayName .. " 已被挂牌出售，等待买家报价。",
                                    priority = "normal",
                                })
                                Router.replaceWith("market", { tab = "listed" })
                            end,
                        } or UI.Label {
                            text = "不可",
                            fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 50, textAlign = "center",
                        },
                    },
                },
                -- 第二行：身价 + 周薪
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                    children = {
                        UI.Label { text = Market._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                        UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = Market._formatValue(p.wage or 0) .. "/周", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    },
                },
            },
        })
    end

    return children
end

------------------------------------------------------
-- 报价处理弹窗
------------------------------------------------------
function Market._showOfferSheet(gameState, player)
    local incomingBids = TransferManager.getPendingSellBids(gameState)
    local bid = nil
    for _, b in ipairs(incomingBids) do
        if b.playerId == player.id and b.isIncomingBid then
            bid = b
            break
        end
    end
    if not bid then return end

    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local buyerName = buyerTeam and buyerTeam.name or "未知球队"
    local bidAmount = bid.amount
    local playerValue = player.value or 0

    -- 计算还价建议（身价的110%）
    local suggestedCounter = math.floor(playerValue * 1.1 / 1000) * 1000

    local ConfirmDialog = require("scripts/ui/components/confirm_dialog")

    BottomSheet.showCustom({
        title = "报价处理 - " .. player.displayName,
        height = 430,
        showCancel = false,
        children = {
            -- 报价信息
            UI.Panel {
                width = "100%", backgroundColor = {30, 38, 55, 255},
                borderRadius = 8, padding = 12, marginBottom = 12,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 6,
                        children = {
                            UI.Label { text = "买方球队", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = buyerName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 6,
                        children = {
                            UI.Label { text = "报价金额", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = Market._formatValue(bidAmount), fontSize = 14, color = Theme.COLORS.ACCENT, fontWeight = "bold" },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "球员身价", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = Market._formatValue(playerValue), fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY },
                        }
                    },
                }
            },
            -- 操作按钮
            UI.Button {
                text = "接受报价 (" .. Market._formatValue(bidAmount) .. ")",
                width = "100%", height = 42,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 8, fontSize = 14,
                color = {255, 255, 255, 255},
                marginBottom = 8,
                onClick = function()
                    BottomSheet.close()
                    ConfirmDialog.show({
                        title = "确认出售",
                        message = string.format("确认以 %s 将 %s 出售给 %s？",
                            Market._formatValue(bidAmount), player.displayName, buyerName),
                        confirmText = "确认出售",
                        danger = false,
                        onConfirm = function()
                            TransferManager.acceptIncomingBid(gameState, bid.id)
                            UI.Toast.Show({ message = "交易完成！球员已出售", variant = "success" })
                            Router.replaceWith("market", { tab = "listed" })
                        end,
                    })
                end,
            },
            -- 还价区域：输入框 + 按钮
            UI.Panel {
                width = "100%", marginBottom = 8,
                children = {
                    UI.Label { text = "还价金额（万）", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        children = (function()
                            local counterField = UI.TextField {
                                flexGrow = 1, height = 40,
                                placeholder = "输入金额，如 " .. tostring(math.floor(suggestedCounter / 10000)),
                                value = tostring(math.floor(suggestedCounter / 10000)),
                                fontSize = 15,
                                borderRadius = 6,
                                marginRight = 8,
                            }
                            local counterBtn = UI.Button {
                                text = "发起还价",
                                width = 90, height = 40,
                                backgroundColor = {50, 65, 90, 255},
                                borderRadius = 6, fontSize = 13,
                                color = Theme.COLORS.ACCENT,
                                onClick = function()
                                    local inputText = counterField:GetValue() or ""
                                    local amount = tonumber(inputText)
                                    if not amount or amount <= 0 then return end
                                    local askAmount = math.floor(amount * 10000) -- 万 → 实际金额

                                    BottomSheet.close()
                                    ConfirmDialog.show({
                                        title = "还价谈判",
                                        message = string.format("要求 %s 支付 %s。\n对方可能接受或拒绝。",
                                            buyerName, Market._formatValue(askAmount)),
                                        confirmText = "确认还价",
                                        danger = false,
                                        onConfirm = function()
                                            local ok, result = TransferManager.counterIncomingBid(gameState, bid.id, askAmount)
                                            UI.Toast.Show({ message = "还价已发出", variant = "success" })
                                            Router.replaceWith("market", { tab = "listed" })
                                        end,
                                    })
                                end,
                            }
                            return { counterField, counterBtn }
                        end)(),
                    },
                },
            },
            UI.Button {
                text = "拒绝报价",
                width = "100%", height = 42,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 8, fontSize = 14,
                color = Theme.COLORS.DANGER,
                onClick = function()
                    BottomSheet.close()
                    TransferManager.rejectIncomingBid(gameState, bid.id)
                    UI.Toast.Show({ message = "已拒绝报价", variant = "info" })
                    Router.replaceWith("market", { tab = "listed" })
                end,
            },
        }
    })
end

-- 球探报告
function Market._buildScoutContent(gameState)
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 获取球探
    local scouts = {}
    for _, sid in ipairs(team.staffIds) do
        local s = gameState.staff[sid]
        if s and s.role == "scout" then
            table.insert(scouts, s)
        end
    end

    if #scouts == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            padding = 20,
            children = {
                UI.Label { text = "没有球探", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                UI.Label {
                    text = "球队没有球探，无法发现新球员。\n请在职员页面雇佣球探。",
                    fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                    textAlign = "center",
                },
            }
        })
        return children
    end

    -- 显示球探信息
    table.insert(children, Theme.Card {
        children = {
            Theme.Subtitle { text = "球探团队" },
            UI.Label {
                text = string.format("当前有 %d 名球探", #scouts),
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, marginTop = 4,
            },
        }
    })

    -- 球探报告（已发现的球员）
    local scoutReports = gameState.scoutReports or {}
    if #scoutReports == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 80,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无球探报告", fontSize = 13, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = "球探会在每周自动发现新球员", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
            }
        })
    else
        -- 显示最近10条球探报告
        for i = 1, math.min(10, #scoutReports) do
            local report = scoutReports[i]
            local player = gameState.players[report.playerId]
            if player then
                local team2 = gameState.teams[player.teamId]
                table.insert(children, UI.Panel {
                    width = "100%", height = 56,
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = 12, paddingRight = 12,
                    borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                    children = {
                        UI.Label {
                            text = Constants.POSITION_NAMES[player.position] or player.position,
                            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36,
                        },
                        UI.Panel {
                            flexGrow = 1,
                            children = {
                                UI.Label { text = player.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
                                UI.Label {
                                    text = (team2 and team2.name or "自由") .. " | " ..
                                        player:getAge(gameState.date.year) .. "岁 | 潜力" .. report.scoutedPotential,
                                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                                },
                            }
                        },
                        UI.Label {
                            text = tostring(player.overall),
                            fontSize = 13, color = Theme.COLORS.SECONDARY, width = 28, fontWeight = "bold",
                        },
                        UI.Button {
                            text = "出价",
                            width = 46, height = 26,
                            backgroundColor = Theme.COLORS.PRIMARY,
                            borderRadius = 4, fontSize = 11,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                local offerAmount = math.floor(player.value * 1.1)
                                TransferManager.makeBid(gameState, player.id, offerAmount)
                                UI.Toast.Show({ message = "报价已提交", variant = "success" })
                                Router.replaceWith("market", { tab = "scout" })
                            end,
                        },
                    },
                })
            end
        end
    end

    return children
end

-- 自由球员
function Market._buildFreeAgentsContent(gameState, posFilter)
    local children = {}

    -- 活跃谈判面板
    local negos = TransferManager.getFreeAgentNegos(gameState)
    local activeNegos = {}
    for _, n in ipairs(negos) do
        if n.status == "pending" or n.status == "negotiating" then
            table.insert(activeNegos, n)
        end
    end

    if #activeNegos > 0 then
        table.insert(children, UI.Panel {
            width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 4,
            children = { UI.Label { text = "进行中的合同谈判 (" .. #activeNegos .. ")", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.WARNING } }
        })
        for _, nego in ipairs(activeNegos) do
            local player = gameState.players[nego.playerId]
            if player then
                local negoChildren = {}
                -- 基本信息行
                local statusText = nego.status == "pending" and "等待回复..." or "对方还价"
                local statusColor = nego.status == "pending" and Theme.COLORS.TEXT_MUTED or Theme.COLORS.WARNING
                table.insert(negoChildren, UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Label { text = player.displayName, fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                        UI.Label { text = statusText .. " (第" .. (nego.currentRound or 0) + 1 .. "/" .. (nego.maxRounds or 3) .. "轮)",
                            fontSize = 10, color = statusColor },
                    }
                })
                -- 当前报价
                table.insert(negoChildren, UI.Label {
                    text = string.format("你的报价: 周薪 %.1fK / %d年", nego.wageOffer / 1000, nego.yearsOffer),
                    fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 4,
                })

                -- 如果有还价，显示还价面板 + 操作按钮
                if nego.status == "negotiating" and nego.counterWage then
                    table.insert(negoChildren, UI.Panel {
                        width = "100%", marginTop = 6, padding = 8,
                        backgroundColor = {80, 40, 120, 80}, borderRadius = 6,
                        children = {
                            UI.Label { text = string.format("球员要求: 周薪 %.1fK / %d年",
                                nego.counterWage / 1000, nego.counterYears or nego.expectedYears),
                                fontSize = 12, fontWeight = "bold", color = {200, 160, 255, 255} },
                            UI.Label { text = string.format("差距: %.1fK/周 (%.0f%%)",
                                (nego.counterWage - nego.wageOffer) / 1000,
                                ((nego.counterWage - nego.wageOffer) / math.max(nego.wageOffer, 1)) * 100),
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    })

                    -- 快速加薪按钮
                    local raise25 = math.floor((nego.wageOffer + (nego.counterWage - nego.wageOffer) * 0.5) / 100) * 100
                    local raiseFull = nego.counterWage

                    local negoId = nego.id
                    local counterYears = nego.counterYears or nego.expectedYears
                    table.insert(negoChildren, UI.Panel {
                        width = "100%", flexDirection = "row", marginTop = 6, flexWrap = "wrap",
                        children = {
                            UI.Button {
                                text = string.format("+50%% (%.1fK)", raise25 / 1000),
                                height = 26, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 4, fontSize = 10,
                                color = Theme.COLORS.TEXT_PRIMARY, marginRight = 4, marginBottom = 4,
                                onClick = function()
                                    TransferManager.reviseOffer(gameState, negoId, raise25, counterYears)
                                    UI.Toast.Show({ message = "加薪报价已发送", variant = "success" })
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                                end,
                            },
                            UI.Button {
                                text = string.format("满足 (%.1fK)", raiseFull / 1000),
                                height = 26, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = {46, 139, 87, 255}, borderRadius = 4, fontSize = 10,
                                color = Theme.COLORS.TEXT_PRIMARY, marginRight = 4, marginBottom = 4,
                                onClick = function()
                                    TransferManager.reviseOffer(gameState, negoId, raiseFull, counterYears)
                                    UI.Toast.Show({ message = "已满足球员要求", variant = "success" })
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                                end,
                            },
                            UI.Button {
                                text = "放弃", height = 26, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = Theme.COLORS.DANGER, borderRadius = 4, fontSize = 10,
                                color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4,
                                onClick = function()
                                    TransferManager.cancelFreeAgentNego(gameState, negoId)
                                    UI.Toast.Show({ message = "已放弃谈判", variant = "info" })
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                                end,
                            },
                        }
                    })
                else
                    -- pending状态只能取消
                    local negoId = nego.id
                    table.insert(negoChildren, UI.Panel {
                        width = "100%", flexDirection = "row", marginTop = 6,
                        children = {
                            UI.Button {
                                text = "取消谈判", height = 26, paddingLeft = 8, paddingRight = 8,
                                backgroundColor = Theme.COLORS.DANGER, borderRadius = 4, fontSize = 10,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                onClick = function()
                                    TransferManager.cancelFreeAgentNego(gameState, negoId)
                                    UI.Toast.Show({ message = "已取消谈判", variant = "info" })
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                                end,
                            },
                        }
                    })
                end

                -- 谈判历史
                if #nego.rounds > 0 then
                    local histItems = {}
                    for _, r in ipairs(nego.rounds) do
                        table.insert(histItems, UI.Label {
                            text = string.format("第%d轮: 你出 %s → 对方要 %s",
                                r.round, FinanceManager.formatMoney(r.offerWage or 0), FinanceManager.formatMoney(r.counterWage or 0)),
                            fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 1,
                        })
                    end
                    table.insert(negoChildren, UI.Panel {
                        width = "100%", marginTop = 6, children = histItems,
                    })
                end

                table.insert(children, UI.Panel {
                    width = "100%", padding = 10, marginLeft = 8, marginRight = 8, marginBottom = 6,
                    backgroundColor = {30, 35, 55, 255}, borderRadius = 8,
                    borderWidth = 1, borderColor = Theme.COLORS.WARNING,
                    children = negoChildren,
                })
            end
        end
    end

    -- 位置筛选条
    local filterBtns = {}
    for _, f in ipairs(POSITION_FILTERS) do
        local isActive = f.key == posFilter
        table.insert(filterBtns, UI.Button {
            text = f.label, height = 28, paddingLeft = 8, paddingRight = 8,
            backgroundColor = isActive and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
            borderRadius = 14, fontSize = 11,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Router.replaceWith("market", { tab = "free", posFilter = f.key })
            end,
        })
    end
    table.insert(children, UI.Panel {
        width = "100%", height = 44, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, children = filterBtns,
    })

    -- 获取自由球员
    local filterPos = posFilter ~= "all" and posFilter or nil
    local freeAgents = TransferManager.getFreeAgents(gameState, filterPos)

    -- 按能力排序
    table.sort(freeAgents, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    if #freeAgents == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 100, alignItems = "center", justifyContent = "center",
            children = { UI.Label { text = "暂无自由球员", fontSize = 14, color = Theme.COLORS.TEXT_MUTED } }
        })
        return children
    end

    -- 表头
    table.insert(children, UI.Panel {
        width = "100%", height = 28, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, backgroundColor = {23, 28, 46, 200},
        children = {
            UI.Label { text = "位置", width = 36, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
            UI.Label { text = "球员", flexGrow = 1, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
            UI.Label { text = "能力", width = 28, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
            UI.Label { text = "年龄", width = 28, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
            UI.Label { text = "操作", width = 56, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
        }
    })

    local maxShow = math.min(30, #freeAgents)
    for i = 1, maxShow do
        local p = freeAgents[i]
        local age = p.age or (p.getAge and p:getAge(gameState.date.year)) or "?"
        local hasPending = TransferManager.hasPendingFreeAgentNego(gameState, p.id)

        local actionBtn
        if hasPending then
            actionBtn = UI.Label {
                text = "谈判中", width = 56, fontSize = 10,
                color = Theme.COLORS.WARNING, textAlign = "center",
            }
        else
            local playerId = p.id
            local wage = p.wage or 1000
            actionBtn = UI.Button {
                text = "邀约", width = 50, height = 26,
                backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 4, fontSize = 11,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    TransferManager.offerFreeAgent(gameState, playerId, wage, 2)
                    UI.Toast.Show({ message = "邀约已发送", variant = "success" })
                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                end,
            }
        end

        table.insert(children, UI.Panel {
            width = "100%", height = 52, flexDirection = "row", alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36 },
                UI.Panel { flexGrow = 1, flexShrink = 1,
                    onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                    children = {
                        UI.Label { text = p.displayName or p.name or "?", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
                        UI.Label { text = "周薪期望: " .. Market._formatValue(p.wage or 1000), fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                    }
                },
                UI.Label { text = tostring(p.overall or "?"), fontSize = 13, color = Theme.COLORS.SECONDARY, width = 28, fontWeight = "bold" },
                UI.Label { text = tostring(age), fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, width = 28, textAlign = "center" },
                actionBtn,
            },
        })
    end

    return children
end

-- 租借市场（当前租借 + 发起租借）
function Market._buildLoansContent(gameState)
    return LoansTab.build(gameState)
end

-- 格式化金额
function Market._formatValue(amount)
    return FinanceManager.formatMoney(amount)
end

return Market
