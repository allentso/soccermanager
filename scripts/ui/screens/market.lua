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
                    UI.Panel { width = 50 },
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
    -- 默认选中溢价(idx 3) + 标准条款(idx 2) + 薪资×1.0(idx 2) + 3年合同(idx 2)
    Market._showBidSheet_render(gameState, player, posFilter, 3, 2, 2, 2)
end

-- 报价弹窗统一渲染（含选项切换后重绘）
function Market._showBidSheet_render(gameState, player, posFilter, bidIdx, clauseIdx, wageIdx, yearsIdx)
    local team = gameState:getPlayerTeam()
    local budget = team and team.transferBudget or 0
    local baseValue = player.value
    local sellerTeam = gameState.teams[player.teamId]
    local currentWage = player.wage or 5000

    local bidOptions = {
        { label = "低报 (身价×0.9)", multiplier = 0.9 },
        { label = "平价 (身价×1.0)", multiplier = 1.0 },
        { label = "溢价 (身价×1.1)", multiplier = 1.1 },
        { label = "高价 (身价×1.2)", multiplier = 1.2 },
        { label = "诚意满满 (身价×1.35)", multiplier = 1.35 },
    }
    local clauseOptions = {
        { key = "simple", label = "一次付清·无附加条款", installments = 1, bonus = 0, sellOn = 0 },
        { key = "standard", label = "2期·出场奖金8%·转售10%", installments = 2, bonus = 0.08, sellOn = 10 },
        { key = "heavy", label = "3期·出场奖金12%·转售15%", installments = 3, bonus = 0.12, sellOn = 15 },
    }
    -- 个人条款选项：薪资
    local wageOptions = {
        { label = "低薪 (当前×0.9)", multiplier = 0.9 },
        { label = "平薪 (当前×1.0)", multiplier = 1.0 },
        { label = "加薪 (当前×1.2)", multiplier = 1.2 },
        { label = "高薪 (当前×1.5)", multiplier = 1.5 },
    }
    -- 个人条款选项：合同年限
    local yearsOptions = { 2, 3, 4, 5 }

    local selectedBidIdx = bidIdx
    local selectedClauseIdx = clauseIdx
    local selectedWageIdx = wageIdx or 2
    local selectedYearsIdx = yearsIdx or 2
    local offerAmount = math.floor(baseValue * bidOptions[selectedBidIdx].multiplier)
    local clause = clauseOptions[selectedClauseIdx]
    local appearanceBonus = math.floor(baseValue * clause.bonus)
    local offeredWage = math.floor(currentWage * wageOptions[selectedWageIdx].multiplier)
    local offeredYears = yearsOptions[selectedYearsIdx]

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

    -- 报价金额选择
    table.insert(children, UI.Label { text = "报价金额", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 })
    for i, opt in ipairs(bidOptions) do
        local amount = math.floor(baseValue * opt.multiplier)
        local isSelected = i == selectedBidIdx
        local canAfford = amount <= budget
        table.insert(children, UI.Button {
            text = string.format("%s%s — %s", isSelected and "● " or "  ", opt.label, Market._formatValue(amount)),
            width = "100%", height = 34, marginBottom = 3,
            backgroundColor = isSelected and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12, textAlign = "left", paddingLeft = 10,
            color = not canAfford and Theme.COLORS.DANGER or (isSelected and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY),
            onClick = function()
                if canAfford then
                    BottomSheet.close()
                    Market._showBidSheet_render(gameState, player, posFilter, i, selectedClauseIdx, selectedWageIdx, selectedYearsIdx)
                end
            end,
        })
    end

    -- 条款选择
    table.insert(children, UI.Label { text = "合同条款", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginTop = 10, marginBottom = 6 })
    for i, c in ipairs(clauseOptions) do
        local isSelected = i == selectedClauseIdx
        table.insert(children, UI.Button {
            text = (isSelected and "● " or "  ") .. c.label,
            width = "100%", height = 34, marginBottom = 3,
            backgroundColor = isSelected and Theme.COLORS.ACCENT or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12, textAlign = "left", paddingLeft = 10,
            color = isSelected and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                BottomSheet.close()
                Market._showBidSheet_render(gameState, player, posFilter, selectedBidIdx, i, selectedWageIdx, selectedYearsIdx)
            end,
        })
    end

    -- 个人条款：周薪
    table.insert(children, UI.Label { text = "球员周薪", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginTop = 10, marginBottom = 6 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        children = (function()
            local btns = {}
            for i, w in ipairs(wageOptions) do
                local isSelected = i == selectedWageIdx
                local wage = math.floor(currentWage * w.multiplier)
                table.insert(btns, UI.Button {
                    text = (isSelected and "● " or "") .. Market._formatValue(wage) .. "/周",
                    height = 30, marginRight = 4, marginBottom = 3,
                    paddingLeft = 8, paddingRight = 8,
                    backgroundColor = isSelected and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
                    borderRadius = 6, fontSize = 11,
                    color = isSelected and {20, 20, 20, 255} or Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        BottomSheet.close()
                        Market._showBidSheet_render(gameState, player, posFilter, selectedBidIdx, selectedClauseIdx, i, selectedYearsIdx)
                    end,
                })
            end
            return btns
        end)(),
    })

    -- 个人条款：合同年限
    table.insert(children, UI.Label { text = "合同年限", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginTop = 8, marginBottom = 6 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        children = (function()
            local btns = {}
            for i, y in ipairs(yearsOptions) do
                local isSelected = i == selectedYearsIdx
                table.insert(btns, UI.Button {
                    text = (isSelected and "● " or "") .. y .. "年",
                    height = 30, marginRight = 6,
                    paddingLeft = 10, paddingRight = 10,
                    backgroundColor = isSelected and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
                    borderRadius = 6, fontSize = 12,
                    color = isSelected and {20, 20, 20, 255} or Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        BottomSheet.close()
                        Market._showBidSheet_render(gameState, player, posFilter, selectedBidIdx, selectedClauseIdx, selectedWageIdx, i)
                    end,
                })
            end
            return btns
        end)(),
    })

    -- 财务摘要
    table.insert(children, UI.Panel {
        width = "100%", marginTop = 10, padding = 10,
        backgroundColor = {20, 30, 50, 255}, borderRadius = 8,
        children = {
            UI.Panel { width = "100%", flexDirection = "row", children = {
                UI.Label { text = "转会预算:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = Market._formatValue(budget), fontSize = 12, color = Theme.COLORS.SECONDARY },
            }},
            UI.Panel { width = "100%", flexDirection = "row", marginTop = 4, children = {
                UI.Label { text = "报价金额:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = Market._formatValue(offerAmount), fontSize = 12, color = Theme.COLORS.ACCENT, fontWeight = "bold" },
            }},
            UI.Panel { width = "100%", flexDirection = "row", marginTop = 4, children = {
                UI.Label { text = "预算剩余:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label {
                    text = Market._formatValue(budget - offerAmount),
                    fontSize = 12,
                    color = (budget - offerAmount) >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER,
                },
            }},
            UI.Panel { width = "100%", flexDirection = "row", marginTop = 4, children = {
                UI.Label { text = "球员周薪:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = Market._formatValue(offeredWage) .. "/周", fontSize = 12, color = Theme.COLORS.SECONDARY },
            }},
            UI.Panel { width = "100%", flexDirection = "row", marginTop = 4, children = {
                UI.Label { text = "合同年限:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = offeredYears .. "年", fontSize = 12, color = Theme.COLORS.SECONDARY },
            }},
            clause.bonus > 0 and UI.Panel { width = "100%", flexDirection = "row", marginTop = 4, children = {
                UI.Label { text = "出场奖金(20场):", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = Market._formatValue(appearanceBonus), fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
            }} or nil,
            clause.sellOn > 0 and UI.Panel { width = "100%", flexDirection = "row", marginTop = 2, children = {
                UI.Label { text = "转售分成:", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = clause.sellOn .. "%", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
            }} or nil,
        },
    })

    -- 提交按钮（固定在底部，不参与滚动）
    local canSubmit = offerAmount <= budget
    local submitBtn = UI.Button {
        text = canSubmit and ("提交报价 " .. Market._formatValue(offerAmount)) or "预算不足",
        width = "100%", height = 44, marginTop = 12,
        backgroundColor = canSubmit and Theme.COLORS.PRIMARY or Theme.COLORS.TEXT_MUTED,
        borderRadius = 8, fontSize = 15, fontWeight = "bold",
        color = Theme.COLORS.TEXT_PRIMARY,
        onClick = function()
            if canSubmit then
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
                end
                BottomSheet.close()
                Router.replaceWith("market", { tab = "my_bids" })
            end
        end,
    }

    BottomSheet.showCustom({
        title = "转会报价 — " .. player.displayName,
        height = 780,
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
            -- 检查是否有收到报价
            local hasBid = TransferManager.hasPendingIncomingBid(gameState, p.id)
            table.insert(children, UI.Panel {
                width = "100%", height = 52,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 12, paddingRight = 12,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                backgroundColor = hasBid and {40, 50, 30, 255} or {0, 0, 0, 0},
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[p.position] or p.position,
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36,
                    },
                    UI.Label {
                        text = p.displayName .. (hasBid and " (有报价!)" or ""),
                        fontSize = 13, color = hasBid and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_PRIMARY, flexGrow = 1, flexShrink = 1,
                    },
                    UI.Label {
                        text = tostring(p.overall),
                        fontSize = 13, color = Theme.COLORS.SECONDARY, width = 28, fontWeight = "bold",
                    },
                    UI.Label {
                        text = Market._formatValue(p.value),
                        fontSize = 11, color = Theme.COLORS.ACCENT, width = 50,
                    },
                    hasBid and UI.Button {
                        text = "处理",
                        width = 46, height = 26,
                        backgroundColor = Theme.COLORS.ACCENT,
                        borderRadius = 4, fontSize = 11,
                        color = {255, 255, 255, 255},
                        onClick = function()
                            Router.navigate("player_detail", { playerId = p.id, tab = "contract" })
                        end,
                    } or UI.Button {
                        text = "取消",
                        width = 46, height = 26,
                        backgroundColor = {80, 80, 100, 255},
                        borderRadius = 4, fontSize = 11,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            p.listedForSale = false
                            Router.replaceWith("market", { tab = "listed" })
                        end,
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
            width = "100%", height = 48,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label {
                    text = Constants.POSITION_NAMES[p.position] or p.position,
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36,
                },
                UI.Label {
                    text = p.displayName,
                    fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1, flexShrink = 1,
                },
                UI.Label {
                    text = tostring(p.overall),
                    fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, width = 28,
                },
                UI.Label {
                    text = Market._formatValue(p.value),
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 50,
                },
                isSafe and UI.Button {
                    text = "挂牌",
                    width = 46, height = 26,
                    backgroundColor = Theme.COLORS.ACCENT,
                    borderRadius = 4, fontSize = 11,
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
                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 46, textAlign = "center",
                },
            },
        })
    end

    return children
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
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                                end,
                            },
                            UI.Button {
                                text = "放弃", height = 26, paddingLeft = 6, paddingRight = 6,
                                backgroundColor = Theme.COLORS.DANGER, borderRadius = 4, fontSize = 10,
                                color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4,
                                onClick = function()
                                    TransferManager.cancelFreeAgentNego(gameState, negoId)
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
                            text = string.format("第%d轮: 你出 %.1fK → 对方要 %.1fK",
                                r.round, (r.offerWage or 0) / 1000, (r.counterWage or 0) / 1000),
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
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("%.0fK", amount / 1000)
    else
        return tostring(amount)
    end
end

return Market
