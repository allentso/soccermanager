-- ui/screens/market/free_agents_tab.lua
-- 自由球员标签页，从 market.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
local AudioManager = require("scripts/systems/audio_manager")
local YouthManager = require("scripts/systems/youth_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")

local Tab = {}

local function _market()
    return require("scripts/ui/screens/market")
end

function Tab.build(gameState, posFilter)
    local children = {}

    -- 待确认签入的自由球员
    local pendingFreeSign = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
    if #pendingFreeSign > 0 then
        local panelChildren = {
            UI.Label {
                text = string.format("待确认签入 (%d人)", #pendingFreeSign),
                fontSize = 13, fontWeight = "bold", color = {0, 200, 83, 255}, marginBottom = 8,
            },
        }
        if #pendingFreeSign > 1 then
            table.insert(panelChildren, UI.Panel {
                width = "100%", flexDirection = "row", marginBottom = 8,
                children = {
                    UI.Button {
                        text = "查看全部",
                        flexGrow = 1, height = 36, marginRight = 8,
                        backgroundColor = {38, 46, 71, 255},
                        borderRadius = 6, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            _market()._showBatchFreeAgentConfirmSheet(gameState, pendingFreeSign)
                        end,
                    },
                    UI.Button {
                        text = string.format("全部签入 (%d人)", #pendingFreeSign),
                        flexGrow = 1, height = 36,
                        backgroundColor = {0, 200, 83, 255},
                        borderRadius = 6, fontSize = 13, fontWeight = "bold",
                        color = {255, 255, 255, 255},
                        onClick = function()
                            local okCount, failCount, lastErr = TransferManager.confirmAllPendingFreeAgents(gameState)
                            if okCount > 0 then
                                UI.Toast.Show({
                                    message = string.format("已签入 %d 名自由球员", okCount),
                                    variant = failCount > 0 and "warning" or "success",
                                })
                            end
                            if failCount > 0 then
                                AudioManager.deny()
                                UI.Toast.Show({ message = lastErr or "部分签入失败", variant = "error" })
                            end
                            Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                        end,
                    },
                },
            })
        end
        for _, item in ipairs(pendingFreeSign) do
            local negoId = item.negoId
            local rowChildren = {
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label { text = item.playerName, fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY },
                        UI.Label {
                            text = string.format("周薪 %s · %d年",
                                _market()._formatValue(item.wageOffer or 0), item.yearsOffer or 3),
                            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                        },
                    },
                },
            }
            local deferBtn = _buildDeferFreeAgentButton(gameState, negoId, item.playerName, "free", nil, true)
            if deferBtn then
                table.insert(rowChildren, deferBtn)
            end
            table.insert(rowChildren, UI.Button {
                text = "确认签入", width = 72, height = 28, marginRight = 4,
                backgroundColor = {0, 200, 83, 255}, borderRadius = 4, fontSize = 11,
                color = {255, 255, 255, 255},
                onClick = function()
                    local _, err = TransferManager.confirmFreeAgent(gameState, negoId)
                    if err then
                        AudioManager.deny()
                        UI.Toast.Show({ message = err, variant = "error" })
                    else
                        UI.Toast.Show({ message = item.playerName .. " 签约完成", variant = "success" })
                    end
                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                end,
            })
            table.insert(rowChildren, UI.Button {
                text = "放弃", width = 44, height = 28,
                backgroundColor = Theme.COLORS.DANGER, borderRadius = 4, fontSize = 11,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
                    UI.Toast.Show({ message = "已放弃签约", variant = "info" })
                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                end,
            })
            table.insert(panelChildren, UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = rowChildren,
            })
        end
        table.insert(children, UI.Panel {
            width = "100%", padding = 10, marginLeft = 8, marginRight = 8, marginBottom = 8,
            backgroundColor = {0, 200, 83, 20}, borderRadius = 8,
            borderWidth = 1, borderColor = {0, 200, 83, 80},
            children = panelChildren,
        })
    end

    local deferredFreeNegos = {}
    for _, nego in ipairs(TransferManager.getFreeAgentNegos(gameState)) do
        if nego.status == "awaiting_confirmation"
            and TransferManager.isFreeAgentSignDeferred(nego, gameState) then
            table.insert(deferredFreeNegos, nego)
        end
    end
    if #deferredFreeNegos > 0 then
        local deferredChildren = {
            UI.Label {
                text = string.format("已推迟签入 (%d人)", #deferredFreeNegos),
                fontSize = 13, fontWeight = "bold", color = Theme.COLORS.WARNING, marginBottom = 8,
            },
        }
        for _, nego in ipairs(deferredFreeNegos) do
            local player = gameState.players[nego.playerId]
            local daysLeft = TransferManager.getFreeAgentSignDeferDaysLeft(nego, gameState)
            local negoId = nego.id
            table.insert(deferredChildren, UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = player and player.displayName or "球员",
                                fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
                            },
                            UI.Label {
                                text = string.format("还剩 %d 天 · 周薪 %s · %d年",
                                    daysLeft,
                                    _market()._formatValue(nego.wageOffer or 0),
                                    nego.yearsOffer or 3),
                                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                            },
                        },
                    },
                    UI.Button {
                        text = "确认", width = 52, height = 28, marginRight = 4,
                        backgroundColor = {0, 200, 83, 255}, borderRadius = 4, fontSize = 11,
                        color = {255, 255, 255, 255},
                        onClick = function()
                            local _, err = TransferManager.confirmFreeAgent(gameState, negoId)
                            if err then
                                AudioManager.deny()
                                UI.Toast.Show({ message = err, variant = "error" })
                            else
                                UI.Toast.Show({ message = "签约完成", variant = "success" })
                            end
                            Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                        end,
                    },
                    UI.Button {
                        text = "放弃", width = 44, height = 28,
                        backgroundColor = Theme.COLORS.DANGER, borderRadius = 4, fontSize = 11,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
                            UI.Toast.Show({ message = "已放弃签约", variant = "info" })
                            Router.replaceWith("market", { tab = "free", posFilter = posFilter })
                        end,
                    },
                },
            })
        end
        table.insert(children, UI.Panel {
            width = "100%", padding = 10, marginLeft = 8, marginRight = 8, marginBottom = 8,
            backgroundColor = {255, 183, 77, 20}, borderRadius = 8,
            borderWidth = 1, borderColor = {255, 183, 77, 80},
            children = deferredChildren,
        })
    end

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
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 14, fontSize = 11,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
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
    local filterPos = (posFilter ~= "all" and posFilter ~= "SHORTLIST") and posFilter or nil
    local freeAgents = TransferManager.getFreeAgents(gameState, filterPos)
    if posFilter == "SHORTLIST" then
        local filtered = {}
        for _, p in ipairs(freeAgents) do
            if gameState.shortlist and gameState.shortlist[p.id] then
                table.insert(filtered, p)
            end
        end
        freeAgents = filtered
    end

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
            actionBtn = UI.Button {
                text = "邀约", width = 50, height = 26,
                backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 4, fontSize = 11,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    Tab.showFreeAgentOfferSheet(gameState, p, posFilter)
                end,
            }
        end

        table.insert(children, UI.Panel {
            width = "100%", height = 52, flexDirection = "row", alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Panel {
                    backgroundColor = {Theme.COLORS.TEXT_MUTED[1], Theme.COLORS.TEXT_MUTED[2], Theme.COLORS.TEXT_MUTED[3], 30},
                    borderRadius = 3, paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1, marginRight = 6,
                    children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = Theme.COLORS.TEXT_MUTED } },
                },
                UI.Panel { flexGrow = 1, flexShrink = 1,
                    onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                    children = {
                        UI.Label { text = p.displayName or p.name or "?", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
                        UI.Label { text = "周薪期望: " .. _market()._formatValue(p.wage or 1000), fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
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

-- 自由球员合同谈判面板
function Tab.showFreeAgentOfferSheet(gameState, player, posFilter)
    local expectedWage = player.wage or 5000
    local yearsOptions = { 1, 2, 3, 4 }
    local selectedYearsIdx = 2

    -- 周薪输入
    local wageField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "输入周薪（万）",
        value = tostring(math.floor(expectedWage / 10000)),
        fontSize = 14, borderRadius = 6,
    }

    -- 快捷周薪按钮
    local wagePresets = { 0.7, 0.85, 1.0, 1.2 }
    local wagePresetBtns = {}
    for _, mul in ipairs(wagePresets) do
        local wage = math.max(1, math.floor(expectedWage * mul / 10000))
        table.insert(wagePresetBtns, UI.Button {
            text = _market()._formatValue(wage * 10000),
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                wageField:SetValue(tostring(wage))
            end,
        })
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
                        text = string.format("%s | 能力 %d | %d岁 | 期望周薪 %s",
                            Constants.POSITION_NAMES[player.position] or player.position,
                            math.min(Constants.ABILITY_MAX, player.overall or 0),
                            player.getAge and player:getAge(gameState.date.year) or "?",
                            _market()._formatValue(expectedWage)),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 3,
                    },
                }
            },
        }
    })

    -- 周薪输入
    table.insert(children, UI.Label { text = "提供周薪（万/周）", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 })
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
        text = "发起谈判",
        width = "100%", height = 44, marginTop = 12,
        backgroundColor = Theme.COLORS.GOLD,
        borderRadius = 8, fontSize = 15, fontWeight = "bold",
        color = "#1A1A1A",
        onClick = function()
            local wageText = wageField:GetValue() or ""
            local wageAmount = tonumber(wageText)
            if not wageAmount or wageAmount <= 0 then
                AudioManager.deny()
                UI.Toast.Show({ message = "请输入有效的周薪", variant = "error" })
                return
            end
            local offeredWage = math.floor(wageAmount * 10000)
            local offeredYears = yearsOptions[selectedYearsIdx]

            local nego, err = TransferManager.offerFreeAgent(gameState, player.id, offeredWage, offeredYears)
            if nego then
                UI.Toast.Show({ message = "合同邀约已发送", variant = "success" })
            elseif not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                AudioManager.deny()
                UI.Toast.Show({ message = err or "邀约失败", variant = "error" })
            end
            BottomSheet.close()
            Router.replaceWith("market", { tab = "free", posFilter = posFilter })
        end,
    }

    BottomSheet.showCustom({
        title = "自由球员邀约 — " .. player.displayName,
        height = 420,
        showCancel = true,
        children = children,
        footer = submitBtn,
    })
end

return Tab
