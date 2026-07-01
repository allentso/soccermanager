-- ui/screens/youth/squad_tab.lua
-- 青训花名册标签页，从 youth.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local Nationality = require("scripts/domain/nationality")
local YouthManager = require("scripts/systems/youth_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local LegendImageRegistry = require("scripts/data/legend_image_registry")
local SaveManager = require("scripts/persistence/save_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")
---@diagnostic disable-next-line: undefined-global
local sdk = sdk
local function _youth() return require("scripts/ui/screens/youth") end

local Tab = {}

function Tab.build(youthSquad, gameState)
    if #youthSquad == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "青训球员" },
                UI.Label {
                    text = "还没有青训球员，从候选列表中签入球员开始培养吧。",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 8,
                },
            },
        }
    end

    local rows = {}
    local unlistedCount = 0
    for _, player in ipairs(youthSquad) do
        if player and not player.listedForSale then
            unlistedCount = unlistedCount + 1
        end
    end
    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 4,
        children = {
            Theme.Subtitle { text = string.format("青训球员 (%d人)", #youthSquad), marginBottom = 0 },
            UI.Button {
                text = string.format("一键挂牌 %d", unlistedCount),
                height = 30,
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = unlistedCount > 0 and Theme.COLORS.ACCENT or {51, 59, 84, 255},
                borderRadius = 15,
                fontSize = 12,
                color = unlistedCount > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                fontWeight = "bold",
                onClick = function()
                    _youth()._listAllYouthForSale(youthSquad, gameState)
                end,
            },
        },
    })

    for _, player in ipairs(youthSquad) do
        table.insert(rows, Tab._buildYouthPlayerRow(player, gameState))
    end

    return Theme.Card { children = rows }
end

function Tab._buildYouthPlayerRow(player, gameState)
    local posColor = Theme.posColor(player.position)

    local effectivePot = player.actualPotential or player.potential or 0
    local scoutAccuracy = _youth()._getTeamScoutAccuracy(gameState)
    local potStars, potStarText = _youth()._getPotentialStars(effectivePot, scoutAccuracy)
    local potColor = Theme.COLORS.TEXT_MUTED
    if potStars >= 4 then potColor = Theme.COLORS.ACCENT
    elseif potStars >= 3 then potColor = Theme.COLORS.SECONDARY
    end

    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        onClick = function()
            Tab._showYouthActions(player, gameState)
        end,
        children = {
            -- 位置徽章（与阵容页统一样式）
            UI.Panel {
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[player.position] or player.position,
                        fontSize = 10, color = posColor, fontWeight = "bold",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = player.displayName or (player.firstName .. " " .. player.lastName),
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("%d岁 | 能力%d | 潜力%s%s%s",
                            age, math.min(Constants.ABILITY_MAX, player.overall or 0), potStarText,
                            player.isCustomYouth and " | 自建" or "",
                            player.listedForSale and " | 挂牌中" or ""),
                        fontSize = 11,
                        color = player.listedForSale and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 能力/潜力星级
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginRight = 6,
                    },
                    UI.Label {
                        text = "→",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginRight = 6,
                    },
                    UI.Label {
                        text = potStarText,
                        fontSize = 12,
                        color = potColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

------------------------------------------------------
-- 球员操作菜单
------------------------------------------------------
function Tab._showYouthActions(player, gameState)
    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0
    local actions = {}

    -- 提拔
    table.insert(actions, {
        label = "提拔至一线队",
        color = Theme.COLORS.SECONDARY,
        action = function()
            Tab._confirmPromote(player, gameState)
        end,
    })

    -- 查看详情
    table.insert(actions, {
        label = "查看详情",
        color = Theme.COLORS.TEXT_PRIMARY,
        action = function()
            UI.CloseOverlay()
            Router.navigate("player_detail", { playerId = player.id, tab = "contract" })
        end,
    })

    if player.isCustomYouth then
        local paRating = player.paRating or PotentialSystem.rawToRating(player.potential or player.actualPotential or 60)
        table.insert(actions, {
            label = paRating >= 10.0 and "PA已达上限" or string.format("看广告提升PA %.1f→%.1f", paRating, math.min(10.0, paRating + 0.5)),
            color = paRating >= 10.0 and Theme.COLORS.TEXT_MUTED or Theme.COLORS.ACCENT,
            action = function()
                if paRating >= 10.0 then
                    UI.Toast.Show({ message = "该球员潜力已达到上限", variant = "info" })
                else
                    Tab._watchAdForCustomPaBoost(player, gameState)
                end
            end,
        })
    end

    -- 挂牌出售 / 取消挂牌
    if player.listedForSale then
        table.insert(actions, {
            label = "调整挂牌价",
            color = Theme.COLORS.ACCENT,
            action = function()
                UI.CloseOverlay()
                SaleListingPriceSheet.show({
                    gameState = gameState,
                    player = player,
                    onDone = function()
                        Router.replaceWith("youth")
                    end,
                })
            end,
        })
        table.insert(actions, {
            label = "取消挂牌出售",
            color = Theme.COLORS.TEXT_MUTED,
            action = function()
                TransferManager.delistPlayer(gameState, player)
                Router.replaceWith("youth")
            end,
        })
    else
        table.insert(actions, {
            label = "挂牌出售",
            color = Theme.COLORS.ACCENT,
            action = function()
                UI.CloseOverlay()
                SaleListingPriceSheet.show({
                    gameState = gameState,
                    player = player,
                    onDone = function()
                        Router.replaceWith("youth")
                    end,
                })
            end,
        })
    end

    -- 处理收到的出售报价（与详情页/市场一致，取主报价）
    local bid = TransferManager.pickPrimaryIncomingSaleBid(gameState, player.id)
    if bid then
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local buyerName = buyerTeam and buyerTeam.name or "未知球队"
        if bid.status == "pending" then
            table.insert(actions, {
                label = string.format("接受报价 %s", buyerName),
                color = Theme.COLORS.SECONDARY,
                action = function()
                    local ok = TransferManager.acceptIncomingBid(gameState, bid.id)
                    if ok then
                        UI.Toast.Show({ message = "已同意报价，等待球员考虑是否接受转会", variant = "success" })
                    else
                        UI.Toast.Show({ message = "无法接受该报价", variant = "warning" })
                    end
                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                end,
            })
            table.insert(actions, {
                label = string.format("拒绝报价 %s", buyerName),
                color = Theme.COLORS.DANGER,
                action = function()
                    TransferManager.rejectIncomingBid(gameState, bid.id)
                    Router.replaceWith("youth")
                end,
            })
        elseif bid.status == "awaiting_sale_confirmation" then
            table.insert(actions, {
                label = string.format("确认出售给 %s", buyerName),
                color = Theme.COLORS.SECONDARY,
                action = function()
                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status", highlightBidId = bid.id })
                end,
            })
            table.insert(actions, {
                label = string.format("取消出售（%s）", buyerName),
                color = Theme.COLORS.DANGER,
                action = function()
                    TransferManager.cancelSale(gameState, bid.id)
                    Router.replaceWith("youth")
                end,
            })
        elseif bid.status == "player_considering_sale" or bid.status == "counter_pending" then
            table.insert(actions, {
                label = string.format("查看报价进度（%s）", buyerName),
                color = Theme.COLORS.ACCENT,
                action = function()
                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status", highlightBidId = bid.id })
                end,
            })
        end
    end

    -- 释放
    table.insert(actions, {
        label = "释放球员",
        color = Theme.COLORS.DANGER,
        action = function()
            Tab._confirmRelease(player, gameState)
        end,
    })

    -- 构建 overlay
    local items = {}
    for _, act in ipairs(actions) do
        table.insert(items, UI.Button {
            text = act.label,
            width = "100%",
            height = 44,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            fontSize = 14,
            color = act.color,
            marginBottom = 6,
            onClick = function()
                UI.CloseOverlay()
                act.action()
            end,
        })
    end

    table.insert(items, UI.Button {
        text = "取消",
        width = "100%",
        height = 44,
        backgroundColor = {51, 59, 84, 255},
        borderRadius = 8,
        fontSize = 14,
        color = Theme.COLORS.TEXT_SECONDARY,
        marginTop = 4,
        onClick = function() UI.CloseOverlay() end,
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "flex-end",
        backgroundColor = {0, 0, 0, 150},
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_SECONDARY or {24, 28, 44, 255},
                borderRadius = 16,
                paddingTop = 20,
                paddingBottom = 24,
                paddingLeft = 16,
                paddingRight = 16,
                children = {
                    -- 顶部把手
                    UI.Panel {
                        width = 36,
                        height = 4,
                        backgroundColor = {100, 100, 120, 255},
                        borderRadius = 2,
                        alignSelf = "center",
                        marginBottom = 14,
                    },
                    UI.Label {
                        text = player.displayName or "",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 16,
                    },
                    table.unpack(items),
                },
            },
        },
    })
end

------------------------------------------------------
-- 提拔确认
------------------------------------------------------
function Tab._confirmPromote(player, gameState)
    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0
    local team = gameState.teams[gameState.playerTeamId]
    local newWage = FinanceManager.estimateYouthPromoteWage(player, team, gameState)
    local scoutAccuracy = _youth()._getTeamScoutAccuracy(gameState)
    local _, potStarText = _youth()._getPotentialStars(player.actualPotential or player.potential or 0, scoutAccuracy)

    ConfirmDialog.showWithDetails({
        title = "提拔至一线队",
        details = {
            { label = "姓名", value = player.displayName or "" },
            { label = "位置", value = Constants.POSITION_NAMES[player.position] or player.position },
            { label = "年龄", value = tostring(age) .. "岁" },
            { label = "能力", value = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)) },
            { label = "潜力", value = potStarText, valueColor = Theme.COLORS.ACCENT },
            { label = "新周薪", value = FinanceManager.formatMoney(newWage), valueColor = Theme.COLORS.WARNING },
            { label = "合同", value = "3年" },
        },
        confirmText = "确认提拔",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, err = YouthManager.promote(gameState, player.id)
            if ok then
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "提拔失败",
                    message = err or "无法提拔该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end

------------------------------------------------------
-- 释放确认
------------------------------------------------------
function Tab._confirmRelease(player, gameState)
    ConfirmDialog.show({
        title = "释放青训球员",
        message = string.format("确定要释放 %s 吗？\n该操作不可撤销。",
            player.displayName or ""),
        confirmText = "确认释放",
        confirmColor = Theme.COLORS.DANGER,
        onConfirm = function()
            local ok, err = YouthManager.release(gameState, player.id)
            if ok then
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "释放失败",
                    message = err or "无法释放该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end


return Tab
