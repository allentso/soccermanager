-- ui/components/sale_listing_price_sheet.lua
-- 玩家主动挂牌/改价的金额输入面板。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")

local SaleListingPriceSheet = {}

local function formatMoney(amount)
    return FinanceManager.formatMoney(amount or 0)
end

local function amountToWanText(amount)
    amount = math.max(0, math.floor(amount or 0))
    if amount >= 10000 then
        return tostring(math.floor(amount / 10000))
    end
    return string.format("%.2f", amount / 10000)
end

local function parseWanAmount(field)
    local raw = field and field:GetValue() or ""
    local wan = tonumber(raw)
    if not wan or wan <= 0 then return nil end
    return math.floor(wan * 10000)
end

function SaleListingPriceSheet.show(opts)
    opts = opts or {}
    local gameState = opts.gameState
    local player = opts.player
    if not gameState or not player then return end

    local playerValue = math.max(0, math.floor(player.value or 0))
    local currentPrice = player.listedForSale and TransferManager.getSaleAskingPrice(player) or playerValue
    local isAdjusting = player.listedForSale == true

    local priceField = UI.TextField {
        flexGrow = 1, height = 40,
        placeholder = "输入挂牌价（万）",
        value = amountToWanText(currentPrice),
        fontSize = 15,
        borderRadius = 6,
        marginRight = 8,
    }

    local hintLabel = UI.Label {
        text = "",
        fontSize = 11,
        color = Theme.COLORS.TEXT_MUTED,
        marginTop = 6,
        marginBottom = 10,
    }

    local function updateHint(amount)
        amount = amount or parseWanAmount(priceField) or 0
        local ratio = playerValue > 0 and math.floor(amount / playerValue * 100) or 0
        hintLabel:SetText(string.format("AI 会围绕该挂牌价报价；当前约为身价 %d%%。", ratio))
        if ratio < 70 then
            hintLabel:SetStyle({ color = Theme.COLORS.WARNING })
        else
            hintLabel:SetStyle({ color = Theme.COLORS.TEXT_MUTED })
        end
    end

    local presetButtons = {}
    for _, preset in ipairs({
        { label = "×0.6", multiplier = 0.6 },
        { label = "×0.75", multiplier = 0.75 },
        { label = "×0.9", multiplier = 0.9 },
        { label = "身价", multiplier = 1.0 },
    }) do
        table.insert(presetButtons, UI.Button {
            text = preset.label,
            height = 30,
            flexGrow = 1,
            marginRight = 6,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 6,
            fontSize = 12,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                local amount = math.floor(playerValue * preset.multiplier / 10000) * 10000
                amount = math.max(10000, amount)
                priceField:SetValue(amountToWanText(amount))
                updateHint(amount)
            end,
        })
    end

    local function confirm()
        local amount = parseWanAmount(priceField)
        if not amount then
            UI.Toast.Show({ message = "请输入有效挂牌价", variant = "error" })
            return
        end

        local ok, err
        if isAdjusting then
            ok, err = TransferManager.setSaleAskingPrice(gameState, player, amount)
        else
            ok, err = TransferManager.listForSale(gameState, player, amount)
        end

        if not ok then
            if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                UI.Toast.Show({ message = err or "无法挂牌", variant = "warning" })
            end
            return
        end

        BottomSheet.close()
        UI.Toast.Show({
            message = isAdjusting
                and string.format("挂牌价已调整为 %s", formatMoney(TransferManager.getSaleAskingPrice(player)))
                or string.format("%s 已挂牌，挂牌价 %s", player.displayName, formatMoney(TransferManager.getSaleAskingPrice(player))),
            variant = "success",
        })
        if opts.onDone then opts.onDone(player) end
    end

    updateHint(currentPrice)

    BottomSheet.showCustom({
        title = (isAdjusting and "调整挂牌价 - " or "挂牌出售 - ") .. (player.displayName or "球员"),
        height = 360,
        children = {
            UI.Label {
                text = string.format("身价 %s · 当前要价 %s", formatMoney(playerValue), formatMoney(currentPrice)),
                fontSize = 12,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 10,
            },
            UI.Label { text = "挂牌价（万）", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                children = {
                    priceField,
                    UI.Label { text = "万", fontSize = 13, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                },
            },
            hintLabel,
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginBottom = 12,
                children = presetButtons,
            },
            UI.Label {
                text = "一键挂牌不会写入自定义价格，仍按球员实时身价作为默认要价。",
                fontSize = 11,
                color = Theme.COLORS.TEXT_MUTED,
                marginBottom = 4,
            },
        },
        footer = UI.Button {
            text = isAdjusting and "确认改价" or "确认挂牌",
            width = "100%",
            height = 44,
            backgroundColor = Theme.COLORS.ACCENT,
            borderRadius = 8,
            fontSize = 14,
            fontWeight = "bold",
            color = {255, 255, 255, 255},
            onClick = confirm,
        },
    })
end

return SaleListingPriceSheet
