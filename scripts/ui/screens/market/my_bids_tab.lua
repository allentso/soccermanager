-- ui/screens/market/my_bids_tab.lua
-- 我的报价标签页，从 market.lua 拆分。

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

function Tab.build(gameState)
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

    local pendingSign = TransferManager.getPendingTransferSignConfirmations(gameState)
    if #pendingSign > 1 then
        table.insert(children, UI.Panel {
            width = "100%", padding = 12, marginBottom = 8,
            backgroundColor = {0, 200, 83, 25}, borderRadius = 8,
            borderWidth = 1, borderColor = {0, 200, 83, 80},
            children = {
                UI.Label {
                    text = string.format("%d 笔转会待最终确认签入", #pendingSign),
                    fontSize = 13, color = {0, 200, 83, 255}, fontWeight = "bold", marginBottom = 8,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    children = {
                        UI.Button {
                            text = "查看全部",
                            flexGrow = 1, height = 36, marginRight = 8,
                            backgroundColor = {38, 46, 71, 255},
                            borderRadius = 6, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                _market()._showBatchTransferSignConfirmSheet(gameState, pendingSign)
                            end,
                        },
                        UI.Button {
                            text = string.format("全部签入 (%d人)", #pendingSign),
                            flexGrow = 1, height = 36,
                            backgroundColor = {0, 200, 83, 255},
                            borderRadius = 6, fontSize = 13, fontWeight = "bold",
                            color = {255, 255, 255, 255},
                            onClick = function()
                                local okCount, failCount, lastErr = TransferManager.confirmAllPendingTransfers(gameState)
                                if okCount > 0 then
                                    UI.Toast.Show({
                                        message = string.format("已签入 %d 名球员", okCount),
                                        variant = failCount > 0 and "warning" or "success",
                                    })
                                end
                                if failCount > 0 then
                                    AudioManager.deny()
                                    UI.Toast.Show({ message = lastErr or "部分签入失败", variant = "error" })
                                end
                                Router.replaceWith("market", { tab = "my_bids" })
                            end,
                        },
                    },
                },
            },
        })
    end

    for _, bid in ipairs(bids) do
        local player = gameState.players[bid.playerId]
        local sellerTeam = player and gameState.teams[bid.sellerTeamId] or nil
        local isLoan = bid.type == "loan"

        -- 状态颜色/文本
        local statusText = "处理中"
        local statusColor = Theme.COLORS.ACCENT
        if bid.status == "accepted" or bid.status == "completed" then
            statusText = isLoan and "租借完成" or "已接受"
            statusColor = Theme.COLORS.SECONDARY
        elseif bid.status == "rejected" then
            statusText = "被拒绝"
            statusColor = Theme.COLORS.DANGER
        elseif bid.status == "negotiating" then
            statusText = string.format("%s谈判 %d/%d", isLoan and "租借费" or "", bid.currentRound or 0, bid.maxRounds or 4)
            statusColor = {156, 39, 176, 255}
        elseif bid.status == "player_considering" then
            statusText = isLoan and "球员考虑外租" or "球员考虑中"
            statusColor = {255, 183, 77, 255}  -- 橙色
        elseif bid.status == "awaiting_confirmation" then
            if TransferManager.isSignConfirmDeferred(bid, gameState) then
                local daysLeft = TransferManager.getSignConfirmDeferDaysLeft(bid, gameState)
                statusText = string.format("已推迟 · %d天后决定", daysLeft)
                statusColor = Theme.COLORS.WARNING
            else
                statusText = isLoan and "待确认租入" or "待确认签入"
                statusColor = {0, 200, 83, 255}  -- 绿色
            end
        elseif bid.status == "fee_agreed" then
            statusText = isLoan and "待协商租借条款" or "待协商个人条款"
            statusColor = Theme.COLORS.WARNING
        elseif bid.status == "cancelled" then
            statusText = "已撤回"
            statusColor = Theme.COLORS.TEXT_MUTED
        end

        local feeLabel = isLoan and "租借费" or "我方报价"
        local refLabel = isLoan and "参考费" or "身价"
        local subtitleExtra = isLoan
            and string.format(" · %d周 · 工资 %.0f%%", bid.loanDuration or 26, (bid.wageShare or 0.5) * 100)
            or ""

        local cardChildren = {
            -- 头部：球员信息 + 状态
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = (player and player.displayName or "未知球员") .. (isLoan and " [租借]" or ""),
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            },
                            UI.Label {
                                text = (sellerTeam and sellerTeam.name or "自由") ..
                                    " | " .. (player and Constants.POSITION_NAMES[player.position] or "") .. subtitleExtra,
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
                        text = feeLabel .. ": " .. _market()._formatValue(bid.amount),
                        fontSize = 13, color = Theme.COLORS.ACCENT,
                    },
                    UI.Label {
                        text = "  " .. refLabel .. ": " .. _market()._formatValue(bid.playerValue or 0),
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
                        text = "对方要价: " .. _market()._formatValue(bid.counterAmount),
                        fontSize = 14, color = {156, 39, 176, 255}, fontWeight = "bold",
                    },
                    UI.Label {
                        text = (isLoan and "租借费差距: " or "差距: ") .. string.format("%s (%.0f%%)",
                            _market()._formatValue(bid.counterAmount - bid.amount),
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
                        text = "+25%\n" .. _market()._formatValue(raise25),
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
                        text = "+50%\n" .. _market()._formatValue(raise50),
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
                        text = "满足要价\n" .. _market()._formatValue(raiseFull),
                        width = "36%", height = 44,
                        backgroundColor = Theme.COLORS.GOLD, borderRadius = 6,
                        fontSize = 11, color = "#1A1A1A", fontWeight = "bold",
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
                            UI.Label { text = "出价 " .. _market()._formatValue(r.offer), fontSize = 10, color = Theme.COLORS.ACCENT, flexGrow = 1 },
                            UI.Label { text = "还价 " .. _market()._formatValue(r.counter), fontSize = 10, color = {156, 39, 176, 255} },
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

        -- player_considering：球员考虑期（等待中，无需操作）
        if bid.status == "player_considering" then
            local daysLeft = (bid.playerConsiderDays or 2)
            local elapsed = 0
            if bid.playerConsiderDate then
                elapsed = TransferManager._daysBetween(bid.playerConsiderDate, gameState.date)
            end
            local remaining = math.max(0, daysLeft - elapsed)

            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8, padding = 10,
                backgroundColor = {255, 183, 77, 20},
                borderRadius = 6,
                borderWidth = 1, borderColor = {255, 183, 77, 80},
                children = {
                    UI.Label {
                        text = isLoan and "球员正在考虑是否外租..." or "球员正在考虑是否加盟...",
                        fontSize = 12, color = {255, 183, 77, 255}, fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("%s已达成协议，预计还需 %d 天回复。%s",
                            isLoan and "租借费" or "转会费",
                            remaining,
                            bid.isDeadlineDeal and "（关窗日加急）" or ""),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                    },
                }
            })
        end

        -- awaiting_confirmation：球员已同意，等待玩家最终确认签入
        if bid.status == "awaiting_confirmation" then
            local deferred = TransferManager.isSignConfirmDeferred(bid, gameState)
            local deferDaysLeft = TransferManager.getSignConfirmDeferDaysLeft(bid, gameState)
            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8, padding = 10,
                backgroundColor = deferred and {255, 183, 77, 20} or {0, 200, 83, 20},
                borderRadius = 6,
                borderWidth = 1,
                borderColor = deferred and {255, 183, 77, 80} or {0, 200, 83, 80},
                children = {
                    UI.Label {
                        text = deferred
                            and string.format("已推迟签入决定 · 还剩 %d 天可继续筹钱", deferDaysLeft)
                            or (isLoan and "球员已同意外租！等待你确认租入" or "球员已同意加盟！等待你确认签入"),
                        fontSize = 12,
                        color = deferred and Theme.COLORS.WARNING or {0, 200, 83, 255},
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = isLoan
                            and string.format("租借费: %s · %d周 · 你方承担 %.0f%% 工资",
                                _market()._formatValue(bid.amount or 0),
                                bid.loanDuration or 26,
                                (bid.wageShare or 0.5) * 100)
                            or string.format("周薪: %s · 合同: %d年",
                                _market()._formatValue(bid.wageOffer or 0),
                                bid.contractYears or 3),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                    },
                }
            })

            local bidId = bid.id
            local playerName = player and player.displayName or "球员"
            local actionRow = {
                UI.Button {
                    text = isLoan and "确认租入" or "确认签入",
                    flexGrow = 1, height = 40, marginRight = 8,
                    backgroundColor = {0, 200, 83, 255},
                    borderRadius = 6, fontSize = 14, fontWeight = "bold",
                    color = {255, 255, 255, 255},
                    onClick = function()
                        if isLoan then
                            local confirmed, err = TransferManager.confirmLoan(gameState, bidId)
                            if confirmed then
                                UI.Toast.Show({ message = "租借完成！球员已租入", variant = "success" })
                            else
                                UI.Toast.Show({ message = err or "租借失败", variant = "error" })
                            end
                        else
                            TransferManager.confirmTransfer(gameState, bidId)
                            UI.Toast.Show({ message = "签约完成！球员已加入球队", variant = "success" })
                        end
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
                        if isLoan then
                            TransferManager.cancelLoanConfirmation(gameState, bidId)
                        else
                            TransferManager.cancelTransferConfirmation(gameState, bidId)
                        end
                        UI.Toast.Show({ message = isLoan and "已放弃租借" or "已放弃签约", variant = "info" })
                        Router.replaceWith("market", { tab = "my_bids" })
                    end,
                },
            }
            local deferBtn = _buildDeferTransferButton(gameState, bidId, playerName, "my_bids", nil, true)
            if deferBtn then
                table.insert(actionRow, 1, deferBtn)
            end
            table.insert(cardChildren, UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 8,
                children = actionRow,
            })
        end

        -- fee_agreed：个人条款 / 租借条款协商入口
        if bid.status == "fee_agreed" and isLoan then
            local attempts = bid.personalTermsAttempts or 0
            local maxAttempts = bid.maxPersonalTermsAttempts or 3
            local remaining = maxAttempts - attempts
            local currentShare = bid.wageShare or 0.5
            local shareOptions = { 0.5, 0.75, 1.0 }
            -- 从模块级变量读取用户选择，无记忆则默认高一档
            local selectedShareIdx = _loanShareSelection[bid.id]
            if not selectedShareIdx then
                -- 默认选高一档（比当前多一档）
                selectedShareIdx = 2
                for i, s in ipairs(shareOptions) do
                    if math.abs(s - currentShare) < 0.01 then
                        selectedShareIdx = math.min(i + 1, #shareOptions)
                        break
                    end
                end
                _loanShareSelection[bid.id] = selectedShareIdx
            end

            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8, padding = 10,
                backgroundColor = {Theme.COLORS.WARNING[1], Theme.COLORS.WARNING[2], Theme.COLORS.WARNING[3], 20},
                borderRadius = 6,
                borderWidth = 1, borderColor = {Theme.COLORS.WARNING[1], Theme.COLORS.WARNING[2], Theme.COLORS.WARNING[3], 80},
                children = {
                    UI.Label {
                        text = "租借费已达成，球员拒绝了当前租借条件",
                        fontSize = 12, color = Theme.COLORS.WARNING, fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("当前工资分担: %.0f%% · 剩余协商机会: %d次",
                            currentShare * 100, remaining),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                    },
                }
            })

            local shareBtns = {}
            local thisBidId = bid.id
            for i, share in ipairs(shareOptions) do
                table.insert(shareBtns, UI.Button {
                    text = string.format("%.0f%%", share * 100),
                    height = 28, paddingLeft = 10, paddingRight = 10, marginRight = 4,
                    backgroundColor = (i == selectedShareIdx) and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
                    borderRadius = 5, fontSize = 11,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        _loanShareSelection[thisBidId] = i
                        Router.replaceWith("market", { tab = "my_bids" })
                    end,
                })
            end

            local bidId = bid.id
            table.insert(cardChildren, UI.Panel {
                width = "100%", marginTop = 8,
                children = {
                    UI.Label { text = "调整你方承担的工资比例", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 },
                    UI.Panel { width = "100%", flexDirection = "row", marginBottom = 8, children = shareBtns },
                }
            })

            table.insert(cardChildren, UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 8,
                children = {
                    UI.Button {
                        text = "重新协商租借条款",
                        flexGrow = 1, height = 40, marginRight = 8,
                        backgroundColor = Theme.COLORS.WARNING,
                        borderRadius = 6, fontSize = 14, fontWeight = "bold",
                        color = {20, 20, 20, 255},
                        onClick = function()
                            local chosenShare = shareOptions[_loanShareSelection[bidId] or selectedShareIdx]
                            TransferManager.negotiateLoanTerms(gameState, bidId, chosenShare)
                            _loanShareSelection[bidId] = nil
                            UI.Toast.Show({ message = "新租借条件已发送", variant = "success" })
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
                            UI.Toast.Show({ message = "已放弃租借", variant = "info" })
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    },
                },
            })
        end

        if bid.status == "fee_agreed" and not isLoan then
            local attempts = bid.personalTermsAttempts or 0
            local maxAttempts = bid.maxPersonalTermsAttempts or 3
            local remaining = maxAttempts - attempts
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
                            _market()._formatValue(currentWage), remaining),
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
                    text = wp.label .. " (" .. _market()._formatValue(newWage * 10000) .. ")",
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

return Tab
