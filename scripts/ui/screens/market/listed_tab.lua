-- ui/screens/market/listed_tab.lua
-- 出售标签页，从 market.lua 拆分。

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

function Tab._collectTeamRosterPlayers(gameState, team)
    local seen, result = {}, {}
    local function add(p)
        if p and not p.retired and not seen[p.id] then
            seen[p.id] = true
            result[#result + 1] = p
        end
    end
    for _, pid in ipairs(team.playerIds or {}) do
        add(gameState.players[pid])
    end
    for _, pid in ipairs(team._youthPlayerIds or {}) do
        add(gameState.players[pid])
    end
    return result
end

local function _buildListedSalePlayerRow(gameState, team, p, opts)
    opts = opts or {}
    local showCancelWhenNoBid = opts.showCancelWhenNoBid ~= false
    local emptyBidText = opts.emptyBidText or "等待报价"

    local incomingBids = TransferManager.getIncomingBidsForPlayer(gameState, p.id)
    local hasBid = #incomingBids > 0
    local posColor = Theme.posColor(p.position)
    local inTransferWindow = TransferManager.isInTransferWindow(gameState)

    local bidInfo = ""
    local bidColor = Theme.COLORS.FINANCE_GREEN
    local btnText = "处理"
    local primaryBid = nil
    if hasBid then
        primaryBid = TransferManager.pickPrimaryIncomingSaleBid(gameState, p.id)
        if #incomingBids > 1 then
            local pendingCount, awaitingCount, consideringCount, counterCount = 0, 0, 0, 0
            for _, b in ipairs(incomingBids) do
                if b.status == "pending" then
                    pendingCount = pendingCount + 1
                elseif b.status == "awaiting_sale_confirmation" then
                    awaitingCount = awaitingCount + 1
                elseif b.status == "player_considering_sale" then
                    consideringCount = consideringCount + 1
                elseif b.status == "counter_pending" then
                    counterCount = counterCount + 1
                end
            end

            bidInfo = string.format("%d份报价 · 最高 %s", #incomingBids, _market()._formatValue(incomingBids[1].amount or 0))
            if awaitingCount > 0 then
                bidInfo = bidInfo .. string.format(" · %d笔待确认", awaitingCount)
                bidColor = Theme.COLORS.SECONDARY
                btnText = "确认"
            elseif pendingCount > 0 then
                bidInfo = bidInfo .. string.format(" · %d笔待处理", pendingCount)
                bidColor = Theme.COLORS.ACCENT
                btnText = "处理"
            elseif consideringCount > 0 then
                bidInfo = bidInfo .. " · 球员考虑中"
                bidColor = {255, 180, 60, 255}
                btnText = "查看"
            elseif counterCount > 0 then
                bidInfo = bidInfo .. " · 还价中"
                bidColor = Theme.COLORS.WARNING
                btnText = "查看"
            else
                bidColor = Theme.COLORS.TEXT_MUTED
                btnText = "查看"
            end
        elseif primaryBid then
            local buyer = gameState.teams[primaryBid.buyerTeamId]
            if primaryBid.status == "counter_pending" then
                bidInfo = "还价中 · 等待" .. (buyer and buyer.name or "对方") .. "回复"
                bidColor = Theme.COLORS.WARNING
                btnText = "查看"
            elseif primaryBid.status == "player_considering_sale" then
                bidInfo = "球员考虑中 · " .. (buyer and buyer.name or "买方") .. " " .. _market()._formatValue(primaryBid.amount)
                bidColor = {255, 180, 60, 255}
                btnText = "查看"
            elseif primaryBid.status == "awaiting_sale_confirmation" then
                bidInfo = "待确认 · " .. _market()._formatValue(primaryBid.amount) .. " → " .. (buyer and buyer.name or "买方")
                bidColor = Theme.COLORS.SECONDARY
                btnText = "确认"
            else
                bidInfo = (buyer and buyer.name or "未知") .. " 出价 " .. _market()._formatValue(primaryBid.amount)
            end
        end
    end

    local actionButton
    if hasBid then
        actionButton = UI.Button {
            text = btnText,
            width = 50, height = 28,
            backgroundColor = Theme.COLORS.ACCENT,
            borderRadius = 6, fontSize = 12,
            color = {255, 255, 255, 255},
            onClick = function()
                if #incomingBids > 1 then
                    _market()._showOfferSheet(gameState, p)
                    return
                end
                if primaryBid and primaryBid.status == "awaiting_sale_confirmation" then
                    local batchSales = TransferManager.getPendingSaleConfirmations(gameState, team.id)
                    if #batchSales > 1 then
                        _market()._showBatchSaleConfirmSheet(gameState, batchSales)
                        return
                    end
                end
                _market()._showOfferSheet(gameState, p, primaryBid)
            end,
        }
    elseif showCancelWhenNoBid then
        actionButton = UI.Panel {
            flexDirection = "row",
            children = {
                UI.Button {
                    text = "改价",
                    width = 50, height = 28,
                    backgroundColor = {50, 65, 90, 255},
                    borderRadius = 6, fontSize = 12,
                    color = Theme.COLORS.ACCENT,
                    marginRight = 6,
                    onClick = function()
                        SaleListingPriceSheet.show({
                            gameState = gameState,
                            player = p,
                            onDone = function()
                                Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                            end,
                        })
                    end,
                },
                UI.Button {
                    text = "取消",
                    width = 50, height = 28,
                    backgroundColor = {80, 80, 100, 255},
                    borderRadius = 6, fontSize = 12,
                    color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        TransferManager.delistPlayer(gameState, p)
                        Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                    end,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        backgroundColor = hasBid and {40, 50, 30, 255} or {0, 0, 0, 0},
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Panel {
                        backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
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
                    actionButton,
                },
            },
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                children = {
                    UI.Label { text = "身价 " .. _market()._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                    UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                    UI.Label {
                        text = "挂牌价 " .. _market()._formatValue(TransferManager.getSaleAskingPrice(p)),
                        fontSize = 11,
                        color = Theme.COLORS.SECONDARY,
                    },
                    UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                    UI.Label {
                        text = hasBid and bidInfo
                            or (inTransferWindow and emptyBidText
                                or "窗口关闭 · 下窗继续"),
                        fontSize = 11,
                        color = hasBid and bidColor
                            or (inTransferWindow and Theme.COLORS.TEXT_MUTED or Theme.COLORS.WARNING),
                    },
                },
            },
        },
    }
end

function Tab.build(gameState, listedSubTab)
    listedSubTab = listedSubTab or "status"
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 分类球员：已挂牌 / 被挖角 / 可挂牌（含青训名单）
    local listedPlayers = {}
    local poachedPlayers = {}
    local availablePlayers = {}
    local listedPlayerIds = {}
    for _, p in ipairs(Tab._collectTeamRosterPlayers(gameState, team)) do
        if p.squadRole == "loaned" and p.listedForSale then
            p.listedForSale = false
        end
        if p.listedForSale and p.squadRole ~= "loaned" then
            table.insert(listedPlayers, p)
            listedPlayerIds[p.id] = true
        elseif p.squadRole ~= "loaned" then
            table.insert(availablePlayers, p)
        end
    end

    local function _playerStillOnTeam(p, playerId)
        if not p then return false end
        if p.teamId == team.id then return true end
        return YouthManager.isOnTeamYouthSquad(gameState, playerId or p.id, team.id)
    end

    for _, playerId in ipairs(TransferManager.getPlayersWithActiveIncomingSales(gameState, team.id)) do
        if not listedPlayerIds[playerId] then
            local p = gameState.players[playerId]
            if _playerStillOnTeam(p, playerId) and p.squadRole ~= "loaned" then
                table.insert(poachedPlayers, p)
            end
        end
    end

    local statusCount = #listedPlayers + #poachedPlayers
    local subTabs = {
        { key = "list", label = "选择挂牌" },
        { key = "status", label = string.format("待售 (%d)", statusCount) },
    }
    local subTabButtons = {}
    for _, st in ipairs(subTabs) do
        local isActive = st.key == listedSubTab
        table.insert(subTabButtons, UI.Button {
            text = st.label,
            height = 30,
            paddingLeft = 14, paddingRight = 14,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 15,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 8,
            onClick = function()
                Router.replaceWith("market", { tab = "listed", listedSubTab = st.key })
            end,
        })
    end
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
        children = subTabButtons,
    })

    if listedSubTab == "list" then
        table.insert(children, UI.Panel {
            width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
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

        table.sort(availablePlayers, function(a, b) return a.overall > b.overall end)

        for _, p in ipairs(availablePlayers) do
            local isSafe, _ = FinanceManager.checkSquadSafety(gameState, p.id)
            table.insert(children, UI.Panel {
                width = "100%",
                paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
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
                                    SaleListingPriceSheet.show({
                                        gameState = gameState,
                                        player = p,
                                        onDone = function()
                                            Router.replaceWith("market", { tab = "listed", listedSubTab = "list" })
                                        end,
                                    })
                                end,
                            } or UI.Label {
                                text = "不可",
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 50, textAlign = "center",
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                        children = {
                            UI.Label { text = _market()._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                            UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.BORDER },
                            UI.Label { text = _market()._formatValue(p.wage or 0) .. "/周", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                        },
                    },
                },
            })
        end

        return children
    end

    -- === 待售子页：已挂牌 + 被挖角 ===
    local pendingSales = TransferManager.getPendingSaleConfirmations(gameState, team.id)
    if #pendingSales > 1 then
        table.insert(children, UI.Panel {
            width = "100%", padding = 12, marginLeft = 12, marginRight = 12, marginBottom = 8,
            backgroundColor = {Theme.COLORS.SECONDARY[1], Theme.COLORS.SECONDARY[2], Theme.COLORS.SECONDARY[3], 25},
            borderRadius = 8, borderWidth = 1,
            borderColor = {Theme.COLORS.SECONDARY[1], Theme.COLORS.SECONDARY[2], Theme.COLORS.SECONDARY[3], 80},
            children = {
                UI.Label {
                    text = string.format("%d 笔出售待最终确认", #pendingSales),
                    fontSize = 13, color = Theme.COLORS.SECONDARY, fontWeight = "bold", marginBottom = 8,
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
                                _market()._showBatchSaleConfirmSheet(gameState, pendingSales)
                            end,
                        },
                        UI.Button {
                            text = string.format("全部卖出 (%d人)", #pendingSales),
                            flexGrow = 1, height = 36,
                            backgroundColor = Theme.COLORS.SECONDARY,
                            borderRadius = 6, fontSize = 13, fontWeight = "bold",
                            color = {255, 255, 255, 255},
                            onClick = function()
                                local totalAmount = 0
                                for _, item in ipairs(pendingSales) do
                                    totalAmount = totalAmount + (item.amount or 0)
                                end
                                ConfirmDialog.show({
                                    title = "全部确认出售",
                                    message = string.format("确认出售 %d 名球员，合计 %s？\n此操作不可撤销。",
                                        #pendingSales, _market()._formatValue(totalAmount)),
                                    confirmText = "全部卖出",
                                    onConfirm = function()
                                        local okCount, failCount, lastErr = TransferManager.confirmAllPendingSales(gameState, team.id)
                                        if okCount > 0 then
                                            UI.Toast.Show({
                                                message = string.format("已出售 %d 名球员", okCount),
                                                variant = failCount > 0 and "warning" or "success",
                                            })
                                        end
                                        if failCount > 0 then
                                            AudioManager.deny()
                                            UI.Toast.Show({ message = lastErr or "部分出售失败", variant = "error" })
                                        end
                                        Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                                    end,
                                })
                            end,
                        },
                    },
                },
            },
        })
    end

    local pendingAcceptCount = 0
    local listedPlayerIdList = {}
    for _, p in ipairs(listedPlayers) do
        listedPlayerIdList[#listedPlayerIdList + 1] = p.id
        local bid = TransferManager.pickPrimaryIncomingSaleBid(gameState, p.id)
        if bid and bid.status == "pending" then
            pendingAcceptCount = pendingAcceptCount + 1
        end
    end

    local listedHeaderChildren = {
        UI.Label {
            text = string.format("已挂牌出售 (%d人)", #listedPlayers),
            fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
        },
    }
    if pendingAcceptCount > 0 then
        table.insert(listedHeaderChildren, UI.Button {
            text = "一键同意",
            height = 30,
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = Theme.COLORS.ACCENT,
            borderRadius = 15,
            fontSize = 12,
            color = {255, 255, 255, 255},
            fontWeight = "bold",
            onClick = function()
                ConfirmDialog.show({
                    title = "一键同意报价",
                    message = string.format(
                        "确认同意 %d 笔待处理报价？\n同意后球员将进入考虑期，随后可确认出售。",
                        pendingAcceptCount),
                    confirmText = "全部同意",
                    onConfirm = function()
                        local okCount, failCount = TransferManager.acceptAllPendingIncomingBids(
                            gameState, listedPlayerIdList)
                        if okCount > 0 then
                            UI.Toast.Show({
                                message = string.format("已同意 %d 笔报价", okCount),
                                variant = failCount > 0 and "warning" or "success",
                            })
                        end
                        if failCount > 0 then
                            AudioManager.deny()
                            UI.Toast.Show({ message = "部分报价无法同意", variant = "error" })
                        end
                        Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                    end,
                })
            end,
        })
    end

    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 10, paddingBottom = 6,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        children = listedHeaderChildren,
    })

    if #listedPlayers == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 44,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无挂牌球员", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, p in ipairs(listedPlayers) do
            table.insert(children, _buildListedSalePlayerRow(gameState, team, p, {
                showCancelWhenNoBid = true,
                emptyBidText = "等待报价",
            }))
        end
    end

    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 14, paddingBottom = 6,
        borderTopWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = string.format("将被挖角 (%d人)", #poachedPlayers),
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
            },
            UI.Label {
                text = "未挂牌但收到 AI 球队主动报价",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
            },
        }
    })

    if #poachedPlayers == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 44,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无挖角报价", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, p in ipairs(poachedPlayers) do
            table.insert(children, _buildListedSalePlayerRow(gameState, team, p, {
                showCancelWhenNoBid = false,
                emptyBidText = "挖角报价处理中",
            }))
        end
    end

    return children
end

return Tab
