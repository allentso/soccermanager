-- ui/screens/market.lua
-- 转会市场页面 - 搜索/筛选/出价/我的报价

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local LoansTab = require("scripts/ui/screens/market/loans_tab")
local BrowseTab = require("scripts/ui/screens/market/browse_tab")
local MyBidsTab = require("scripts/ui/screens/market/my_bids_tab")
local ListedTab = require("scripts/ui/screens/market/listed_tab")
local ScoutTab = require("scripts/ui/screens/market/scout_tab")
local FreeAgentsTab = require("scripts/ui/screens/market/free_agents_tab")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
local AudioManager = require("scripts/systems/audio_manager")
local YouthManager = require("scripts/systems/youth_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")

local Market = {}


-- 租借工资比例选择状态（按 bidId 记忆）
local _loanShareSelection = {}

local _buildDeferTransferButton

------------------------------------------------------
-- 潜力星级（与 youth/player_detail 一致）
------------------------------------------------------
local function _getScoutAccuracy(gameState)
    return ScoutManager.getAccuracy(gameState)
end

local function _getPotentialStars(potential, scoutAccuracy)
    -- 若已解锁潜力透视，直接显示精确值
    local gs = _G.gameState
    if gs and gs.potentialRevealed then
        local rating = PotentialSystem.rawToRating(potential)
        return 5, string.format("%.1f", rating)
    end

    local paRating = PotentialSystem.rawToRating(potential)
    local exactStars = (paRating - 1.0) / 9.0 * 4.0 + 1.0
    local accuracy = scoutAccuracy or 0.6
    local maxError = (1.0 - accuracy) * 1.5
    local seed = potential * 7 + 13
    local pseudoRandom = (math.sin(seed) * 10000) % 1.0
    local errorOffset = (pseudoRandom - 0.5) * 2 * maxError
    local displayStars = math.floor(exactStars + errorOffset + 0.5)
    displayStars = math.max(1, math.min(5, displayStars))
    local starText = string.rep("★", displayStars) .. string.rep("☆", 5 - displayStars)
    return displayStars, starText
end

-- 页面Tab
local TABS = {
    { key = "browse",   label = "搜索" },
    { key = "free",     label = "自由" },
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
    { key = "SHORTLIST", label = "候选" },
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

------------------------------------------------------
-- 转会窗口状态 Banner
------------------------------------------------------
function Market._buildWindowBanner(gameState)
    local month = gameState.date.month
    local inWindow = TransferManager.isInTransferWindow(gameState)

    local text, bgColor, textColor
    if inWindow then
        local windowName, closingMonth
        if month >= 7 and month <= 8 then
            windowName = "夏季转会窗"
            closingMonth = 8
        else
            windowName = "冬季转会窗"
            closingMonth = 1
        end
        local isLastMonth = (month == closingMonth)
        if isLastMonth then
            text = "⏰ " .. windowName .. "本月底关闭"
            bgColor = {180, 120, 30, 40}
            textColor = Theme.COLORS.WARNING
        else
            text = "✅ " .. windowName .. "开启中（" .. closingMonth .. "月底关闭）"
            bgColor = {40, 140, 80, 30}
            textColor = Theme.COLORS.FINANCE_GREEN
        end
    else
        local nextWindow
        if month >= 2 and month <= 6 then
            nextWindow = "夏窗7月开启"
        elseif month >= 9 and month <= 12 then
            nextWindow = "冬窗1月开启"
        else
            nextWindow = "夏窗7月开启"
        end
        text = "🔒 转会窗口关闭中 · 下个窗口：" .. nextWindow
        bgColor = {80, 80, 100, 30}
        textColor = Theme.COLORS.TEXT_MUTED
    end

    return UI.Panel {
        width = "100%",
        height = 32,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = bgColor,
        children = {
            UI.Label {
                text = text,
                fontSize = 11,
                color = textColor,
            },
        },
    }
end

function Market.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local currentTab = (params and params.tab) or "browse"
    local posFilter = (params and params.posFilter) or "all"
    local searchQuery = (params and params.searchQuery) or ""
    local ovrRange = (params and params.ovrRange) or "all"
    local ageRange = (params and params.ageRange) or "all"

    -- 根据Tab选择内容
    local contentChildren = {}
    if currentTab == "browse" then
        contentChildren = Market._buildBrowseContent(gameState, posFilter, searchQuery, ovrRange, ageRange)
    elseif currentTab == "free" then
        contentChildren = Market._buildFreeAgentsContent(gameState, posFilter)
    elseif currentTab == "loans" then
        contentChildren = Market._buildLoansContent(gameState)
    elseif currentTab == "my_bids" then
        contentChildren = Market._buildMyBidsContent(gameState)
    elseif currentTab == "scout" then
        local rawLeague = params and params.scoutLeague or nil
        local rawPos = params and params.scoutPos or nil
        local rawNat = params and params.scoutNat or nil
        local scoutFilters = {
            league = (rawLeague ~= "__nil") and rawLeague or nil,
            position = (rawPos ~= "__nil") and rawPos or nil,
            nationality = (rawNat ~= "__nil") and rawNat or nil,
            ageKey = params and params.scoutAge or nil,
        }
        local scoutSubTab = (params and params.scoutSubTab) or "explore"
        contentChildren = Market._buildScoutContent(gameState, scoutFilters, scoutSubTab)
    elseif currentTab == "listed" then
        local listedSubTab = (params and params.listedSubTab) or "status"
        contentChildren = Market._buildListedContent(gameState, listedSubTab)
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
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 17,
            fontSize = 12,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            onClick = function()
                Router.replaceWith("market", { tab = tab.key, posFilter = posFilter, searchQuery = searchQuery, ovrRange = ovrRange, ageRange = ageRange })
            end,
        })
    end

    if params and params.batchConfirm then
        local batchKind = params.batchConfirm
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            if batchKind == "sign" then
                Market._showBatchTransferSignConfirmSheet(gameState)
            elseif batchKind == "sale" then
                Market._showBatchSaleConfirmSheet(gameState)
            elseif batchKind == "free" then
                Market._showBatchFreeAgentConfirmSheet(gameState)
            end
        end)
    end

    if params and params.highlightBidId then
        local bidId = params.highlightBidId
        local deeplinkTab = params.tab or currentTab
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            local bid = TransferManager.getBidById(gameState, bidId)
            if not bid then return end
            if deeplinkTab == "my_bids" and bid.status == "awaiting_confirmation" then
                local pending = TransferManager.getPendingTransferSignConfirmations(gameState)
                if #pending > 1 then
                    Market._showBatchTransferSignConfirmSheet(gameState, pending)
                    return
                end
                local player = gameState.players[bid.playerId]
                if player then
                    Market._showTransferSignConfirmSheet(gameState, bid)
                else
                    ConfirmDialog.show({
                        title = "签约已失效",
                        message = "该球员已无法签入（可能已从转会市场消失）。是否取消此交易以继续推进时间？",
                        confirmText = "取消交易",
                        danger = true,
                        onConfirm = function()
                            TransferManager.cancelTransferConfirmation(gameState, bid.id)
                            Router.replaceWith("market", { tab = "my_bids" })
                        end,
                    })
                end
                return
            end
            if deeplinkTab == "listed" and bid.status == "awaiting_sale_confirmation" then
                local pendingSales = TransferManager.getPendingSaleConfirmations(gameState)
                if #pendingSales > 1 then
                    Market._showBatchSaleConfirmSheet(gameState, pendingSales)
                    return
                end
            end
            local player = gameState.players[bid.playerId]
            if player then
                Market._showOfferSheet(gameState, player, bid)
            elseif bid.status == "awaiting_sale_confirmation" then
                ConfirmDialog.show({
                    title = "报价已失效",
                    message = "该球员的出售报价已无法处理（球员可能已离队）。是否取消此交易以继续推进时间？",
                    confirmText = "取消交易",
                    danger = true,
                    onConfirm = function()
                        TransferManager.cancelSale(gameState, bid.id)
                        Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                    end,
                })
            end
        end)
    end

    if params and params.highlightNegoId then
        local negoId = params.highlightNegoId
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            local pendingFree = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
            if #pendingFree > 1 then
                Market._showBatchFreeAgentConfirmSheet(gameState, pendingFree)
                return
            end
            local nego = TransferManager.getFreeAgentNegoById(gameState, negoId)
            if nego and nego.status == "awaiting_confirmation" then
                local player = gameState.players[nego.playerId]
                if player then
                    Market._showFreeAgentConfirmSheet(gameState, nego)
                else
                    ConfirmDialog.show({
                        title = "签约已失效",
                        message = "该自由球员已无法签入（可能已从自由球员市场消失）。是否取消此签约以继续推进时间？",
                        confirmText = "取消签约",
                        danger = true,
                        onConfirm = function()
                            TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
                            Router.replaceWith("market", { tab = "free" })
                        end,
                    })
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
                        text = "动态", width = 44, height = 30,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        borderRadius = 4,
                        fontSize = 12, color = Theme.COLORS.ACCENT,
                        onClick = function() Router.navigate("transfer_hub") end,
                    },
                }
            },

            -- 转会窗口状态条
            Market._buildWindowBanner(gameState),

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

-- OVR 范围筛选选项

-- 我的报价

-- 挂牌出售（我方球员：一线队 + 青训队）

------------------------------------------------------
-- 批量确认弹窗（多人待确认合并一页）
------------------------------------------------------
local function _finishBatchSheet(opts, tabKey)
    if opts and opts.onComplete then
        opts.onComplete()
    elseif tabKey then
        Router.replaceWith("market", { tab = tabKey })
    end
end

local function _deferDaysLabel()
    return string.format("推迟%d天", TransferManager.getSignConfirmDeferDays())
end

local function _onDeferSignSuccess(gameState, playerName, tabKey, opts)
    UI.Toast.Show({
        message = string.format("已将 %s 的签入推迟 %d 天，可先推进时间筹钱",
            playerName, TransferManager.getSignConfirmDeferDays()),
        variant = "info",
    })
    if tabKey == "my_bids" then
        local remaining = TransferManager.getPendingTransferSignConfirmations(gameState)
        if remaining and #remaining > 0 then
            Market._showBatchTransferSignConfirmSheet(gameState, remaining, opts)
            return
        end
    elseif tabKey == "free" then
        local remaining = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
        if remaining and #remaining > 0 then
            Market._showBatchFreeAgentConfirmSheet(gameState, remaining, opts)
            return
        end
    end
    _finishBatchSheet(opts, tabKey)
end

_buildDeferTransferButton = function(gameState, bidId, playerName, tabKey, opts, compact)
    if not TransferManager.canDeferTransferSignConfirmation(gameState, bidId) then return nil end
    return UI.Button {
        text = _deferDaysLabel(),
        width = compact and 72 or "100%",
        flexGrow = compact and nil or 1,
        height = compact and 34 or 40,
        marginRight = compact and 4 or 0,
        marginBottom = compact and 0 or 8,
        backgroundColor = {38, 46, 71, 255},
        borderRadius = compact and 6 or 8,
        fontSize = compact and 11 or 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        onClick = function()
            local ok, err = TransferManager.deferTransferSignConfirmation(gameState, bidId)
            if ok then
                if opts and opts.closeSheetForAction then
                    opts.closeSheetForAction()
                else
                    BottomSheet.close()
                end
                _onDeferSignSuccess(gameState, playerName, tabKey, opts)
            else
                AudioManager.deny()
                UI.Toast.Show({ message = err or "无法推迟", variant = "error" })
            end
        end,
    }
end

Market._buildDeferTransferButton = _buildDeferTransferButton

local function _buildDeferFreeAgentButton(gameState, negoId, playerName, tabKey, opts, compact)
    if not TransferManager.canDeferFreeAgentSignConfirmation(gameState, negoId) then return nil end
    return UI.Button {
        text = _deferDaysLabel(),
        width = compact and 72 or "100%",
        flexGrow = compact and nil or 1,
        height = compact and 34 or 40,
        marginRight = compact and 4 or 0,
        marginBottom = compact and 0 or 8,
        backgroundColor = {38, 46, 71, 255},
        borderRadius = compact and 6 or 8,
        fontSize = compact and 11 or 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        onClick = function()
            local ok, err = TransferManager.deferFreeAgentSignConfirmation(gameState, negoId)
            if ok then
                if opts and opts.closeSheetForAction then
                    opts.closeSheetForAction()
                else
                    BottomSheet.close()
                end
                _onDeferSignSuccess(gameState, playerName, tabKey, opts)
            else
                AudioManager.deny()
                UI.Toast.Show({ message = err or "无法推迟", variant = "error" })
            end
        end,
    }
end
Market._buildDeferFreeAgentButton = _buildDeferFreeAgentButton

Market.POSITION_FILTERS = POSITION_FILTERS
Market._loanShareSelection = _loanShareSelection

function Market._showBatchTransferSignConfirmSheet(gameState, pendingList, opts)
    opts = opts or {}
    pendingList = pendingList or TransferManager.getPendingTransferSignConfirmations(gameState)
    if #pendingList == 0 then return end
    local suppressCloseComplete = false
    local sheetOpts = {}
    for k, v in pairs(opts) do sheetOpts[k] = v end
    local function closeSheetForAction()
        suppressCloseComplete = true
        BottomSheet.close()
    end
    sheetOpts.closeSheetForAction = closeSheetForAction
    local function finish(tabKey)
        suppressCloseComplete = true
        _finishBatchSheet(opts, tabKey)
    end

    local rows = {}
    for _, item in ipairs(pendingList) do
        local bid = TransferManager.getBidById(gameState, item.bidId)
        if bid then
            local isLoan = bid.type == "loan"
            local detail = isLoan
                and string.format("租借费 %s · %d周 · 你方 %.0f%% 工资",
                    Market._formatValue(bid.amount or 0), bid.loanDuration or 26, (bid.wageShare or 0.5) * 100)
                or string.format("转会费 %s · 周薪 %s · %d年",
                    Market._formatValue(bid.amount or 0),
                    Market._formatValue(bid.wageOffer or 0),
                    bid.contractYears or 3)
            local bidId = item.bidId
            local rowActions = {
                UI.Button {
                    text = isLoan and "确认租入" or "确认签入",
                    flexGrow = 1, height = 34, marginRight = 6,
                    backgroundColor = {0, 200, 83, 255},
                    borderRadius = 6, fontSize = 12, fontWeight = "bold",
                    color = {255, 255, 255, 255},
                    onClick = function()
                        if isLoan then
                            local confirmed, err = TransferManager.confirmLoan(gameState, bidId)
                            if confirmed then
                                UI.Toast.Show({ message = item.playerName .. " 租借完成", variant = "success" })
                            else
                                UI.Toast.Show({ message = err or "租借失败", variant = "error" })
                            end
                        else
                            TransferManager.confirmTransfer(gameState, bidId)
                            UI.Toast.Show({ message = item.playerName .. " 签约完成", variant = "success" })
                        end
                        closeSheetForAction()
                        local remaining = TransferManager.getPendingTransferSignConfirmations(gameState)
                        if #remaining > 0 then
                            Market._showBatchTransferSignConfirmSheet(gameState, remaining, opts)
                        else
                            finish("my_bids")
                        end
                    end,
                },
                UI.Button {
                    text = "放弃", width = 56, height = 34,
                    backgroundColor = {60, 40, 40, 255},
                    borderRadius = 6, fontSize = 12, color = Theme.COLORS.DANGER,
                    onClick = function()
                        if isLoan then
                            TransferManager.cancelLoanConfirmation(gameState, bidId)
                        else
                            TransferManager.cancelTransferConfirmation(gameState, bidId)
                        end
                        UI.Toast.Show({ message = "已放弃 " .. item.playerName, variant = "info" })
                        closeSheetForAction()
                        local remaining = TransferManager.getPendingTransferSignConfirmations(gameState)
                        if #remaining > 0 then
                            Market._showBatchTransferSignConfirmSheet(gameState, remaining, opts)
                        else
                            finish("my_bids")
                        end
                    end,
                },
            }
            local deferBtn = _buildDeferTransferButton(gameState, bidId, item.playerName, "my_bids", sheetOpts, true)
            if deferBtn then
                table.insert(rowActions, 1, deferBtn)
            end
            table.insert(rows, UI.Panel {
                width = "100%", padding = 10, marginBottom = 8,
                backgroundColor = {30, 38, 55, 255}, borderRadius = 8,
                borderWidth = 1, borderColor = {0, 200, 83, 60},
                children = {
                    UI.Label {
                        text = item.playerName .. (isLoan and " [租借]" or ""),
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                    },
                    UI.Label {
                        text = (item.sellerName or "卖方") .. " · " .. detail,
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", marginTop = 8,
                        children = rowActions,
                    },
                },
            })
        end
    end

    local footer = UI.Panel {
        width = "100%", flexDirection = "row", marginTop = 4,
        children = {
            UI.Button {
                text = string.format("全部签入 (%d人)", #pendingList),
                flexGrow = 1, height = 44,
                backgroundColor = {0, 200, 83, 255},
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    closeSheetForAction()
                    local okCount, failCount, lastErr = TransferManager.confirmAllPendingTransfers(gameState)
                    if okCount > 0 then
                        UI.Toast.Show({
                            message = string.format("已签入 %d 名球员", okCount),
                            variant = failCount > 0 and "warning" or "success",
                        })
                    end
                    if failCount > 0 then
                        AudioManager.deny()
                        UI.Toast.Show({ message = lastErr or string.format("%d 笔签入失败", failCount), variant = "error" })
                        local remaining = TransferManager.getPendingTransferSignConfirmations(gameState)
                        if #remaining > 0 then
                            Market._showBatchTransferSignConfirmSheet(gameState, remaining, opts)
                            return
                        end
                    end
                    finish("my_bids")
                end,
            },
        },
    }

    BottomSheet.showCustom({
        title = string.format("待确认签入 (%d人)", #pendingList),
        height = math.min(560, 200 + #pendingList * 110),
        showCancel = true,
        children = rows,
        footer = footer,
        onClose = function()
            if opts.onComplete and not suppressCloseComplete then opts.onComplete() end
        end,
    })
end

function Market._showBatchSaleConfirmSheet(gameState, pendingList, opts)
    opts = opts or {}
    pendingList = pendingList or TransferManager.getPendingSaleConfirmations(gameState)
    if #pendingList == 0 then return end
    local suppressCloseComplete = false
    local sheetOpts = {}
    for k, v in pairs(opts) do sheetOpts[k] = v end
    local function closeSheetForAction()
        suppressCloseComplete = true
        BottomSheet.close()
    end
    sheetOpts.closeSheetForAction = closeSheetForAction
    local function finish(tabKey)
        suppressCloseComplete = true
        _finishBatchSheet(opts, tabKey)
    end

    local totalAmount = 0
    local rows = {}
    for _, item in ipairs(pendingList) do
        totalAmount = totalAmount + (item.amount or 0)
        local bidId = item.bidId
        table.insert(rows, UI.Panel {
            width = "100%", padding = 10, marginBottom = 8,
            backgroundColor = {30, 38, 55, 255}, borderRadius = 8,
            borderWidth = 1, borderColor = {Theme.COLORS.SECONDARY[1], Theme.COLORS.SECONDARY[2], Theme.COLORS.SECONDARY[3], 60},
            children = {
                UI.Label {
                    text = item.playerName,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                },
                UI.Label {
                    text = string.format("买方: %s · 金额 %s",
                        item.buyerName or "买方", Market._formatValue(item.amount or 0)),
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", marginTop = 8,
                    children = {
                        UI.Button {
                            text = "确认出售",
                            flexGrow = 1, height = 34, marginRight = 6,
                            backgroundColor = Theme.COLORS.SECONDARY,
                            borderRadius = 6, fontSize = 12, fontWeight = "bold",
                            color = {255, 255, 255, 255},
                            onClick = function()
                                closeSheetForAction()
                                ConfirmDialog.show({
                                    title = "确认出售",
                                    message = string.format("确认以 %s 将 %s 出售给 %s？",
                                        Market._formatValue(item.amount or 0), item.playerName, item.buyerName or "买方"),
                                    confirmText = "确认出售",
                                    onConfirm = function()
                                        local ok, err = TransferManager.confirmSale(gameState, bidId)
                                        if ok then
                                            UI.Toast.Show({ message = item.playerName .. " 已出售", variant = "success" })
                                        else
                                            AudioManager.deny()
                                            UI.Toast.Show({ message = err or "出售失败", variant = "error" })
                                        end
                                        local remaining = TransferManager.getPendingSaleConfirmations(gameState)
                                        if #remaining > 0 then
                                            Market._showBatchSaleConfirmSheet(gameState, remaining, opts)
                                        else
                                            finish("listed")
                                        end
                                    end,
                                    onCancel = function()
                                        Market._showBatchSaleConfirmSheet(gameState, pendingList, opts)
                                    end,
                                })
                            end,
                        },
                        UI.Button {
                            text = "取消", width = 56, height = 34,
                            backgroundColor = {60, 40, 40, 255},
                            borderRadius = 6, fontSize = 12, color = Theme.COLORS.DANGER,
                            onClick = function()
                                TransferManager.cancelSale(gameState, bidId)
                                UI.Toast.Show({ message = "已取消 " .. item.playerName .. " 的交易", variant = "info" })
                                closeSheetForAction()
                                local remaining = TransferManager.getPendingSaleConfirmations(gameState)
                                if #remaining > 0 then
                                    Market._showBatchSaleConfirmSheet(gameState, remaining, opts)
                                else
                                    finish("listed")
                                end
                            end,
                        },
                    },
                },
            },
        })
    end

    local footer = UI.Panel {
        width = "100%", flexDirection = "row", marginTop = 4,
        children = {
            UI.Button {
                text = string.format("全部卖出 (%d人)", #pendingList),
                flexGrow = 1, height = 44,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    closeSheetForAction()
                    ConfirmDialog.show({
                        title = "全部确认出售",
                        message = string.format("确认出售 %d 名球员，合计 %s？\n此操作不可撤销。",
                            #pendingList, Market._formatValue(totalAmount)),
                        confirmText = "全部卖出",
                        onConfirm = function()
                            local okCount, failCount, lastErr = TransferManager.confirmAllPendingSales(gameState)
                            if okCount > 0 then
                                UI.Toast.Show({
                                    message = string.format("已出售 %d 名球员", okCount),
                                    variant = failCount > 0 and "warning" or "success",
                                })
                            end
                            if failCount > 0 then
                                AudioManager.deny()
                                UI.Toast.Show({ message = lastErr or string.format("%d 笔出售失败", failCount), variant = "error" })
                                local remaining = TransferManager.getPendingSaleConfirmations(gameState)
                                if #remaining > 0 then
                                    Market._showBatchSaleConfirmSheet(gameState, remaining, opts)
                                    return
                                end
                            end
                            finish("listed")
                        end,
                        onCancel = function()
                            Market._showBatchSaleConfirmSheet(gameState, pendingList, opts)
                        end,
                    })
                end,
            },
        },
    }

    BottomSheet.showCustom({
        title = string.format("待确认出售 (%d人)", #pendingList),
        height = math.min(560, 200 + #pendingList * 110),
        showCancel = true,
        children = rows,
        footer = footer,
        onClose = function()
            if opts.onComplete and not suppressCloseComplete then opts.onComplete() end
        end,
    })
end

function Market.isIncomingBidNotifyMessage(msg)
    if msg.messageType == "incoming_bid_received" then return true end
    if not msg.data or not msg.data.bidId or not msg.data.playerId then return false end
    if msg.actions and #msg.actions > 0 then return false end
    local title = msg.title or ""
    return title:find("^收到报价:") ~= nil or title:find("^收到挖角报价:") ~= nil
end

function Market._showBatchIncomingBidNotifySheet(gameState, msgList, opts)
    opts = opts or {}
    if not msgList or #msgList == 0 then return end

    local items = {}
    for _, msg in ipairs(msgList) do
        local bid = msg.data and TransferManager.getBidById(gameState, msg.data.bidId)
        local player = msg.data and gameState.players[msg.data.playerId]
        if bid and player and bid.status == "pending" and bid.isIncomingBid then
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            table.insert(items, {
                msg = msg,
                bid = bid,
                player = player,
                buyerName = buyerTeam and buyerTeam.name or "未知球队",
                isPoachBid = msg.data.isPoachBid or bid.isPoachBid,
            })
        end
    end
    if #items == 0 then
        if opts.onComplete then opts.onComplete() end
        return
    end

    table.sort(items, function(a, b)
        return (a.bid.amount or 0) > (b.bid.amount or 0)
    end)

    local rows = {}
    for _, item in ipairs(items) do
        local playerValue = item.player.value or item.bid.playerValue or 0
        local ratio = playerValue > 0 and math.floor((item.bid.amount or 0) / playerValue * 100) or 0
        local ratioColor = ratio >= 100 and Theme.COLORS.SECONDARY
            or ratio >= 80 and Theme.COLORS.WARNING
            or Theme.COLORS.DANGER
        local poachTag = item.isPoachBid and " [挖角]" or ""
        table.insert(rows, UI.Panel {
            width = "100%", padding = 10, marginBottom = 8,
            backgroundColor = {30, 38, 55, 255}, borderRadius = 8,
            borderWidth = 1,
            borderColor = {Theme.COLORS.SECONDARY[1], Theme.COLORS.SECONDARY[2], Theme.COLORS.SECONDARY[3], 60},
            children = {
                UI.Label {
                    text = item.player.displayName .. poachTag,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                },
                UI.Label {
                    text = string.format("%s 出价 %s（身价 %s · %d%%）",
                        item.buyerName,
                        Market._formatValue(item.bid.amount or 0),
                        Market._formatValue(playerValue),
                        ratio),
                    fontSize = 11, color = ratioColor, marginTop = 4,
                },
            },
        })
    end

    table.insert(rows, UI.Label {
        text = "前往转会市场「待售」或阵容页长按球员处理报价。",
        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4, marginBottom = 4,
    })

    local suppressCloseComplete = false
    local footer = UI.Panel {
        width = "100%", flexDirection = "row", marginTop = 4,
        children = {
            UI.Button {
                text = "知道了",
                flexGrow = 1, height = 44,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    suppressCloseComplete = true
                    for _, item in ipairs(items) do
                        item.msg.read = true
                    end
                    BottomSheet.close()
                    if opts.onComplete then opts.onComplete() end
                end,
            },
        },
    }

    BottomSheet.showCustom({
        title = string.format("收到报价 (%d笔)", #items),
        height = math.min(560, 180 + #items * 72),
        showCancel = true,
        children = rows,
        footer = footer,
        onClose = function()
            if not suppressCloseComplete then
                for _, item in ipairs(items) do
                    item.msg.read = true
                end
            end
            if opts.onComplete and not suppressCloseComplete then opts.onComplete() end
        end,
    })
end

function Market._showBatchFreeAgentConfirmSheet(gameState, pendingList, opts)
    opts = opts or {}
    pendingList = pendingList or TransferManager.getPendingFreeAgentSignConfirmations(gameState)
    if #pendingList == 0 then return end
    local suppressCloseComplete = false
    local sheetOpts = {}
    for k, v in pairs(opts) do sheetOpts[k] = v end
    local function closeSheetForAction()
        suppressCloseComplete = true
        BottomSheet.close()
    end
    sheetOpts.closeSheetForAction = closeSheetForAction
    local function finish(tabKey)
        suppressCloseComplete = true
        _finishBatchSheet(opts, tabKey)
    end

    local rows = {}
    for _, item in ipairs(pendingList) do
        local negoId = item.negoId
        local rowActions = {
            UI.Button {
                text = "确认签入",
                flexGrow = 1, height = 34, marginRight = 6,
                backgroundColor = {0, 200, 83, 255},
                borderRadius = 6, fontSize = 12, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    local _, err = TransferManager.confirmFreeAgent(gameState, negoId)
                    if err then
                        AudioManager.deny()
                        UI.Toast.Show({ message = err, variant = "error" })
                    else
                        UI.Toast.Show({ message = item.playerName .. " 签约完成", variant = "success" })
                    end
                    closeSheetForAction()
                    local remaining = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
                    if #remaining > 0 then
                        Market._showBatchFreeAgentConfirmSheet(gameState, remaining, opts)
                    else
                        finish("free")
                    end
                end,
            },
            UI.Button {
                text = "放弃", width = 56, height = 34,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 6, fontSize = 12, color = Theme.COLORS.DANGER,
                onClick = function()
                    TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
                    UI.Toast.Show({ message = "已放弃 " .. item.playerName, variant = "info" })
                    closeSheetForAction()
                    local remaining = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
                    if #remaining > 0 then
                        Market._showBatchFreeAgentConfirmSheet(gameState, remaining, opts)
                    else
                        finish("free")
                    end
                end,
            },
        }
        local deferBtn = _buildDeferFreeAgentButton(gameState, negoId, item.playerName, "free", sheetOpts, true)
        if deferBtn then
            table.insert(rowActions, 1, deferBtn)
        end
        table.insert(rows, UI.Panel {
            width = "100%", padding = 10, marginBottom = 8,
            backgroundColor = {30, 38, 55, 255}, borderRadius = 8,
            borderWidth = 1, borderColor = {0, 200, 83, 60},
            children = {
                UI.Label {
                    text = item.playerName,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                },
                UI.Label {
                    text = string.format("周薪 %s · 合同 %d年",
                        Market._formatValue(item.wageOffer or 0), item.yearsOffer or 3),
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", marginTop = 8,
                    children = rowActions,
                },
            },
        })
    end

    local footer = UI.Panel {
        width = "100%", flexDirection = "row", marginTop = 4,
        children = {
            UI.Button {
                text = string.format("全部签入 (%d人)", #pendingList),
                flexGrow = 1, height = 44,
                backgroundColor = {0, 200, 83, 255},
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    closeSheetForAction()
                    local okCount, failCount, lastErr = TransferManager.confirmAllPendingFreeAgents(gameState)
                    if okCount > 0 then
                        UI.Toast.Show({
                            message = string.format("已签入 %d 名自由球员", okCount),
                            variant = failCount > 0 and "warning" or "success",
                        })
                    end
                    if failCount > 0 then
                        AudioManager.deny()
                        UI.Toast.Show({ message = lastErr or string.format("%d 笔签入失败", failCount), variant = "error" })
                        local remaining = TransferManager.getPendingFreeAgentSignConfirmations(gameState)
                        if #remaining > 0 then
                            Market._showBatchFreeAgentConfirmSheet(gameState, remaining, opts)
                            return
                        end
                    end
                    finish("free")
                end,
            },
        },
    }

    BottomSheet.showCustom({
        title = string.format("待确认签入自由球员 (%d人)", #pendingList),
        height = math.min(560, 200 + #pendingList * 100),
        showCancel = true,
        children = rows,
        footer = footer,
        onClose = function()
            if opts.onComplete and not suppressCloseComplete then opts.onComplete() end
        end,
    })
end

------------------------------------------------------
-- 报价处理弹窗
------------------------------------------------------
function Market._showTransferSignConfirmSheet(gameState, bid)
    local player = gameState.players[bid.playerId]
    if not player then return end
    local sellerTeam = bid.sellerTeamId and gameState.teams[bid.sellerTeamId]
    local sellerName = sellerTeam and sellerTeam.name or "卖方"
    local bidId = bid.id
    local isLoan = bid.type == "loan"
    local sheetChildren = {
            UI.Panel {
                width = "100%", backgroundColor = {30, 38, 55, 255},
                borderRadius = 8, padding = 12, marginBottom = 12,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 6,
                        children = {
                            UI.Label { text = "出租方", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = sellerName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 6,
                        children = {
                            UI.Label { text = isLoan and "租借费" or "转会费", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = Market._formatValue(bid.amount or 0), fontSize = 14, color = Theme.COLORS.SECONDARY, fontWeight = "bold" },
                        }
                    },
                    isLoan and UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 6,
                        children = {
                            UI.Label { text = "租期 / 工资分担", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = string.format("%d周 · 你方 %.0f%%",
                                    bid.loanDuration or 26, (bid.wageShare or 0.5) * 100),
                                fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY,
                            },
                        }
                    } or UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = "周薪 / 合同", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = string.format("%s · %d年",
                                    Market._formatValue(bid.wageOffer or 0),
                                    bid.contractYears or 3),
                                fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY,
                            },
                        }
                    },
                }
            },
            UI.Button {
                text = isLoan and "确认租入" or "确认签入",
                width = "100%", height = 44,
                backgroundColor = {0, 200, 83, 255},
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                marginBottom = 8,
                onClick = function()
                    BottomSheet.close()
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
    }
    local deferBtn = _buildDeferTransferButton(gameState, bidId, player.displayName, "my_bids", nil, false)
    if deferBtn then
        table.insert(sheetChildren, deferBtn)
    end
    table.insert(sheetChildren, UI.Button {
                text = "放弃",
                width = "100%", height = 42,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 8, fontSize = 14,
                color = Theme.COLORS.DANGER,
                onClick = function()
                    BottomSheet.close()
                    if isLoan then
                        TransferManager.cancelLoanConfirmation(gameState, bidId)
                    else
                        TransferManager.cancelTransferConfirmation(gameState, bidId)
                    end
                    UI.Toast.Show({ message = isLoan and "已放弃租借" or "已放弃签约", variant = "info" })
                    Router.replaceWith("market", { tab = "my_bids" })
                end,
            })

    BottomSheet.showCustom({
        title = (isLoan and "确认租入 - " or "确认签入 - ") .. player.displayName,
        height = isLoan and (deferBtn and 380 or 320) or (deferBtn and 360 or 300),
        showCancel = true,
        children = sheetChildren,
    })
end

function Market._showFreeAgentConfirmSheet(gameState, nego)
    local player = gameState.players[nego.playerId]
    if not player then return end
    local negoId = nego.id

    local sheetChildren = {
            UI.Panel {
                width = "100%", backgroundColor = {30, 38, 55, 255},
                borderRadius = 8, padding = 12, marginBottom = 12,
                children = {
                    UI.Label {
                        text = string.format("周薪: %s · 合同: %d年",
                            Market._formatValue(nego.wageOffer or 0),
                            nego.yearsOffer or 3),
                        fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                    },
                    UI.Label {
                        text = "球员已同意条款，等待你最终确认",
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6,
                    },
                }
            },
            UI.Button {
                text = "确认签入",
                width = "100%", height = 44,
                backgroundColor = {0, 200, 83, 255},
                borderRadius = 8, fontSize = 15, fontWeight = "bold",
                color = {255, 255, 255, 255},
                marginBottom = 8,
                onClick = function()
                    BottomSheet.close()
                    local _, err = TransferManager.confirmFreeAgent(gameState, negoId)
                    if err then
                        AudioManager.deny()
                        UI.Toast.Show({ message = err, variant = "error" })
                    else
                        UI.Toast.Show({ message = "签约完成！球员已加入球队", variant = "success" })
                    end
                    Router.replaceWith("market", { tab = "free" })
                end,
            },
    }
    local deferBtn = _buildDeferFreeAgentButton(gameState, negoId, player.displayName, "free", nil, false)
    if deferBtn then
        table.insert(sheetChildren, deferBtn)
    end
    table.insert(sheetChildren, UI.Button {
                text = "放弃",
                width = "100%", height = 42,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 8, fontSize = 14,
                color = Theme.COLORS.DANGER,
                onClick = function()
                    BottomSheet.close()
                    TransferManager.cancelFreeAgentConfirmation(gameState, negoId)
                    UI.Toast.Show({ message = "已放弃签约", variant = "info" })
                    Router.replaceWith("market", { tab = "free" })
                end,
            })

    BottomSheet.showCustom({
        title = "确认签入 - " .. player.displayName,
        height = deferBtn and 340 or 280,
        showCancel = true,
        children = sheetChildren,
    })
end

function Market._showOfferSheet(gameState, player, preferredBid, opts)
    opts = opts or {}
    if preferredBid and preferredBid.playerId == player.id then
        -- 深链或列表已选定 bid，直接展示
    else
        preferredBid = nil
    end

    local allBids = TransferManager.getIncomingBidsForPlayer(gameState, player.id)
    if #allBids == 0 and not preferredBid then
        local incomingBids = TransferManager.getPendingSellBids(gameState)
        for _, b in ipairs(incomingBids) do
            if b.playerId == player.id and b.isIncomingBid then
                table.insert(allBids, b)
                break
            end
        end
    end
    if #allBids == 0 and not preferredBid then return end

    if not opts.forceSingle and #allBids > 1 then
        Market._showCompetingOffersSheet(gameState, player, allBids)
        return
    end

    local bid = preferredBid or TransferManager.pickPrimaryIncomingSaleBid(gameState, player.id)
    if not bid then return end
    local buyerTeam = gameState.teams[bid.buyerTeamId]
    local buyerName = buyerTeam and buyerTeam.name or "未知球队"
    local bidAmount = bid.amount
    local playerValue = player.value or 0

    -- 根据bid状态展示不同UI
    if bid.status == "counter_pending" then
        -- 还价等待AI回复中
        BottomSheet.showCustom({
            title = "等待回复 - " .. player.displayName,
            height = 260,
            showCancel = true,
            children = {
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
                                UI.Label { text = "你的要价", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                                UI.Label { text = Market._formatValue(bid.counterAskAmount or bidAmount), fontSize = 14, color = Theme.COLORS.ACCENT, fontWeight = "bold" },
                            }
                        },
                    }
                },
                UI.Panel {
                    width = "100%", padding = 12, alignItems = "center",
                    children = {
                        UI.Label { text = "对方正在考虑你的还价...", fontSize = 14, color = Theme.COLORS.WARNING },
                        UI.Label { text = "请等待几天后查看结果", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6 },
                    }
                },
            }
        })
        return
    end

    if bid.status == "player_considering_sale" then
        -- 球员正在考虑是否接受转会
        local daysLeft = (bid.playerConsiderSaleDays or 2)
        if bid.playerConsiderSaleDate then
            local daysPassed = TransferManager._daysBetween(bid.playerConsiderSaleDate, gameState.date)
            daysLeft = math.max(0, (bid.playerConsiderSaleDays or 2) - daysPassed)
        end
        BottomSheet.showCustom({
            title = "球员考虑中 - " .. player.displayName,
            height = 280,
            showCancel = true,
            children = {
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
                                UI.Label { text = "成交金额", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                                UI.Label { text = Market._formatValue(bidAmount), fontSize = 14, color = Theme.COLORS.SECONDARY, fontWeight = "bold" },
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
                UI.Panel {
                    width = "100%", padding = 12, alignItems = "center",
                    children = {
                        UI.Label { text = "球员正在考虑是否接受转会...", fontSize = 14, color = {255, 180, 60, 255} },
                        UI.Label {
                            text = daysLeft > 0 and string.format("预计 %d 天后给出答复", daysLeft) or "即将给出答复",
                            fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6,
                        },
                        bid.isDeadlineDeal and UI.Label {
                            text = "⚠️ 关窗日加急处理", fontSize = 11, color = Theme.COLORS.WARNING, marginTop = 4,
                        } or nil,
                    }
                },
            }
        })
        return
    end

    if bid.status == "awaiting_sale_confirmation" then
        -- 等待玩家最终确认出售
        BottomSheet.showCustom({
            title = "确认出售 - " .. player.displayName,
            height = 320,
            showCancel = false,
            children = {
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
                                UI.Label { text = "成交金额", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                                UI.Label { text = Market._formatValue(bidAmount), fontSize = 14, color = Theme.COLORS.SECONDARY, fontWeight = "bold" },
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
                UI.Button {
                    text = "确认出售",
                    width = "100%", height = 44,
                    backgroundColor = Theme.COLORS.SECONDARY,
                    borderRadius = 8, fontSize = 15,
                    color = {255, 255, 255, 255},
                    marginBottom = 8,
                    onClick = function()
                        BottomSheet.close()
                        ConfirmDialog.show({
                            title = "最终确认",
                            message = string.format("确认以 %s 将 %s 出售给 %s？\n此操作不可撤销。",
                                Market._formatValue(bidAmount), player.displayName, buyerName),
                            confirmText = "确认出售",
                            danger = false,
                            onConfirm = function()
                                local ok, err = TransferManager.confirmSale(gameState, bid.id)
                                if ok then
                                    UI.Toast.Show({ message = "交易完成！球员已出售", variant = "success" })
                                else
                                    AudioManager.deny()
                                    UI.Toast.Show({ message = err or "出售失败", variant = "error" })
                                end
                                Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                            end,
                        })
                    end,
                },
                UI.Button {
                    text = "取消交易",
                    width = "100%", height = 42,
                    backgroundColor = {60, 40, 40, 255},
                    borderRadius = 8, fontSize = 14,
                    color = Theme.COLORS.DANGER,
                    onClick = function()
                        BottomSheet.close()
                        TransferManager.cancelSale(gameState, bid.id)
                        UI.Toast.Show({ message = "交易已取消", variant = "info" })
                        Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                    end,
                },
            }
        })
        return
    end

    -- 默认 pending 状态 —— 原有的接受/还价/拒绝流程
    local suggestedCounter = math.floor(playerValue * 1.1 / 1000) * 1000

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
                    TransferManager.acceptIncomingBid(gameState, bid.id)
                    UI.Toast.Show({ message = "已同意报价，等待球员考虑是否离队", variant = "success" })
                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
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
                                        message = string.format("要求 %s 支付 %s。\n对方需要时间考虑（1-3天）。",
                                            buyerName, Market._formatValue(askAmount)),
                                        confirmText = "确认还价",
                                        danger = false,
                                        onConfirm = function()
                                            TransferManager.counterIncomingBid(gameState, bid.id, askAmount)
                                            UI.Toast.Show({ message = "还价已发出，等待对方回复", variant = "success" })
                                            Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
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
                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
                end,
            },
        }
    })
end

--- 多份竞争报价对比面板
function Market._showCompetingOffersSheet(gameState, player, bids)
    local playerValue = player.value or 0
    local bidCards = {}

    local function statusMeta(bid)
        if bid.status == "awaiting_sale_confirmation" then
            return "待最终确认", Theme.COLORS.SECONDARY
        elseif bid.status == "counter_pending" then
            return "还价中", Theme.COLORS.WARNING
        elseif bid.status == "player_considering_sale" then
            return "球员考虑中", {255, 180, 60, 255}
        end
        return "待处理", Theme.COLORS.ACCENT
    end

    local function reopenRemaining()
        local remaining = TransferManager.getIncomingBidsForPlayer(gameState, player.id)
        if #remaining > 1 then
            Market._showCompetingOffersSheet(gameState, player, remaining)
        elseif #remaining == 1 then
            Market._showOfferSheet(gameState, player, remaining[1], { forceSingle = true })
        else
            Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
        end
    end

    for i, bid in ipairs(bids) do
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local buyerName = buyerTeam and buyerTeam.name or "未知球队"
        local ratio = playerValue > 0 and math.floor(bid.amount / playerValue * 100) or 0
        local ratioColor = ratio >= 100 and Theme.COLORS.SECONDARY or
                           ratio >= 80  and Theme.COLORS.WARNING or Theme.COLORS.DANGER
        local statusText, statusColor = statusMeta(bid)
        local detailText = Market._formatValue(bid.amount or 0)
        if bid.status == "counter_pending" then
            detailText = string.format("原报价 %s · 你的要价 %s",
                Market._formatValue(bid.amount or 0),
                Market._formatValue(bid.counterAskAmount or bid.amount or 0))
        elseif bid.status == "awaiting_sale_confirmation" then
            detailText = "成交金额 " .. Market._formatValue(bid.amount or 0)
        elseif bid.status == "player_considering_sale" then
            detailText = "已接受报价 " .. Market._formatValue(bid.amount or 0)
        end

        local actionChildren = {}
        if bid.status == "pending" then
            table.insert(actionChildren, UI.Button {
                text = "处理",
                flexGrow = 1, height = 34, marginRight = 4,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 6, fontSize = 12,
                color = {255, 255, 255, 255},
                onClick = function()
                    BottomSheet.close()
                    Market._showOfferSheet(gameState, player, bid, { forceSingle = true })
                end,
            })
            table.insert(actionChildren, UI.Button {
                text = "拒绝",
                width = 60, height = 34,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.DANGER,
                onClick = function()
                    TransferManager.rejectIncomingBid(gameState, bid.id)
                    UI.Toast.Show({ message = "已拒绝 " .. buyerName .. " 的报价", variant = "info" })
                    BottomSheet.close()
                    reopenRemaining()
                end,
            })
        elseif bid.status == "awaiting_sale_confirmation" then
            table.insert(actionChildren, UI.Button {
                text = "确认出售",
                flexGrow = 1, height = 34, marginRight = 4,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 6, fontSize = 12, fontWeight = "bold",
                color = {255, 255, 255, 255},
                onClick = function()
                    BottomSheet.close()
                    ConfirmDialog.show({
                        title = "确认出售",
                        message = string.format("确认以 %s 将 %s 出售给 %s？",
                            Market._formatValue(bid.amount or 0), player.displayName, buyerName),
                        confirmText = "确认出售",
                        onConfirm = function()
                            local ok, err = TransferManager.confirmSale(gameState, bid.id)
                            if ok then
                                UI.Toast.Show({ message = player.displayName .. " 已出售", variant = "success" })
                            else
                                AudioManager.deny()
                                UI.Toast.Show({ message = err or "出售失败", variant = "error" })
                            end
                            reopenRemaining()
                        end,
                    })
                end,
            })
            table.insert(actionChildren, UI.Button {
                text = "取消",
                width = 60, height = 34,
                backgroundColor = {60, 40, 40, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.DANGER,
                onClick = function()
                    TransferManager.cancelSale(gameState, bid.id)
                    UI.Toast.Show({ message = "已取消 " .. buyerName .. " 的交易", variant = "info" })
                    BottomSheet.close()
                    reopenRemaining()
                end,
            })
        else
            table.insert(actionChildren, UI.Button {
                text = "查看",
                flexGrow = 1, height = 34,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    BottomSheet.close()
                    Market._showOfferSheet(gameState, player, bid, { forceSingle = true })
                end,
            })
        end

        table.insert(bidCards, UI.Panel {
            width = "100%", backgroundColor = {30, 38, 55, 255},
            borderRadius = 8, padding = 10, marginBottom = 8,
            borderWidth = 1,
            borderColor = i == 1 and Theme.COLORS.ACCENT or {Theme.COLORS.BORDER[1], Theme.COLORS.BORDER[2], Theme.COLORS.BORDER[3], 80},
            children = {
                -- 头部：球队名 + 推荐标记
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
                    children = {
                        UI.Label { text = buyerName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1 },
                        UI.Panel {
                            backgroundColor = {statusColor[1], statusColor[2], statusColor[3], 35},
                            borderRadius = 4, paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                            marginRight = i == 1 and 6 or 0,
                            children = { UI.Label { text = statusText, fontSize = 10, color = statusColor } }
                        },
                        i == 1 and UI.Panel {
                            backgroundColor = {Theme.COLORS.ACCENT[1], Theme.COLORS.ACCENT[2], Theme.COLORS.ACCENT[3], 40},
                            borderRadius = 4, paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                            children = { UI.Label { text = "最高", fontSize = 10, color = Theme.COLORS.ACCENT } }
                        } or nil,
                    }
                },
                -- 报价金额 + 比率
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8,
                    children = {
                        UI.Label { text = detailText, fontSize = 13, color = bid.status == "counter_pending" and Theme.COLORS.WARNING or Theme.COLORS.ACCENT, fontWeight = "bold" },
                        bid.status == "pending" and UI.Label { text = string.format("  (%d%%身价)", ratio), fontSize = 11, color = ratioColor, marginLeft = 4 } or nil,
                    }
                },
                -- 操作按钮
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    children = actionChildren,
                },
            }
        })
    end

    -- 构建内容：头部信息 + 各报价卡片（BottomSheet 自带 ScrollView，不要再嵌套）
    local sheetChildren = {
        UI.Panel {
            width = "100%", flexDirection = "row", marginBottom = 10,
            children = {
                UI.Label { text = "球员身价: ", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = Market._formatValue(playerValue), fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold" },
                UI.Label { text = string.format("  · %d 家球队出价", #bids), fontSize = 12, color = Theme.COLORS.ACCENT, marginLeft = 8 },
            }
        },
    }
    for _, card in ipairs(bidCards) do
        table.insert(sheetChildren, card)
    end

    BottomSheet.showCustom({
        title = string.format("竞争报价 - %s（%d份）", player.displayName, #bids),
        height = math.min(500, 120 + #bids * 130),
        showCancel = true,
        children = sheetChildren,
    })
end

-- 球探（探索任务 + 报告）

-- 自由球员

-- 租借市场（当前租借 + 发起租借）
function Market._buildLoansContent(gameState)
    return LoansTab.build(gameState)
end

-- 租借报价面板（复用转会报价交互）
function Market._showLoanOfferSheet(gameState, player, duration)
    duration = duration or player.loanListDuration or 26
    local sourceTeam = player.teamId and gameState.teams[player.teamId]
    local benchmark = TransferManager.getLoanFeeBenchmark(player, duration)
    local shareOptions = {
        { label = "50%", value = 0.5 },
        { label = "75%", value = 0.75 },
        { label = "100%", value = 1.0 },
    }
    local selectedShareIdx = 1

    local feeField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "输入租借费（万）",
        value = tostring(math.max(1, math.floor(benchmark / 10000))),
        fontSize = 14, borderRadius = 6,
    }

    local feePresetBtns = {}
    for _, mul in ipairs({ 0.8, 1.0, 1.15, 1.3 }) do
        local amount = math.max(1, math.floor(benchmark * mul / 10000))
        table.insert(feePresetBtns, UI.Button {
            text = Market._formatValue(amount * 10000),
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                feeField:SetValue(tostring(amount))
            end,
        })
    end

    local shareBtns = {}
    for i, opt in ipairs(shareOptions) do
        table.insert(shareBtns, UI.Button {
            text = opt.label,
            height = 32, paddingLeft = 12, paddingRight = 12, marginRight = 6,
            backgroundColor = (i == selectedShareIdx) and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12,
            color = Theme.COLORS.TEXT_PRIMARY,
            onClick = function()
                selectedShareIdx = i
            end,
        })
    end

    local playerId = player.id
    local submitBtn = UI.Button {
        text = "提交租借报价",
        width = "100%", height = 44, marginTop = 12,
        backgroundColor = Theme.COLORS.GOLD,
        borderRadius = 8, fontSize = 15, fontWeight = "bold",
        color = "#1A1A1A",
        onClick = function()
            local feeText = feeField:GetValue() or ""
            local feeAmount = tonumber(feeText)
            if not feeAmount or feeAmount <= 0 then
                AudioManager.deny()
                UI.Toast.Show({ message = "请输入有效的租借费", variant = "error" })
                return
            end
            local offeredFee = math.floor(feeAmount * 10000)
            local wageShare = shareOptions[selectedShareIdx].value
            local bid, err = TransferManager.makeLoanBid(gameState, playerId, duration, offeredFee, wageShare)
            if bid then
                UI.Toast.Show({ message = "租借报价已提交", variant = "success" })
                BottomSheet.close()
                Router.replaceWith("market", { tab = "my_bids" })
            elseif not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                AudioManager.deny()
                UI.Toast.Show({ message = err or "租借报价失败", variant = "error" })
            end
        end,
    }

    BottomSheet.showCustom({
        title = "租借报价 — " .. player.displayName,
        height = 480,
        showCancel = true,
        children = {
            UI.Label {
                text = (sourceTeam and sourceTeam.name or "?") .. " · " .. tostring(duration) .. " 周",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
            },
            UI.Label { text = "租借费（万）", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4, children = { feeField } },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 12, children = feePresetBtns },
            UI.Label {
                text = "参考租借费: " .. Market._formatValue(benchmark),
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
            },
            UI.Label { text = "你方承担球员工资比例", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 },
            UI.Panel { width = "100%", flexDirection = "row", marginBottom = 8, children = shareBtns },
            UI.Label {
                text = "流程：俱乐部谈判租借费 → 球员考虑 → 协商条款 → 你确认租入",
                fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
            },
        },
        footer = submitBtn,
    })
end

-- 格式化金额
function Market._formatValue(amount)
    return FinanceManager.formatMoney(amount)
end

-- 金额转「万」输入框文本（支持低于 1 万的小数）
function Market._amountToWanText(amount)
    amount = math.max(0, math.floor(amount or 0))
    if amount >= 10000 then
        return tostring(math.floor(amount / 10000))
    end
    local wan = amount / 10000
    local text = string.format("%.4f", wan)
    text = text:gsub("0+$", ""):gsub("%.$", "")
    return text ~= "" and text or "0"
end


function Market._buildBrowseContent(gameState, posFilter, searchQuery, ovrRange, ageRange)
    return BrowseTab.build(gameState, posFilter, searchQuery, ovrRange, ageRange)
end

function Market._showBidSheet(gameState, player, posFilter, searchQuery, ovrRange, ageRange)
    return BrowseTab.showBidSheet(gameState, player, posFilter, searchQuery, ovrRange, ageRange)
end

function Market._buildMyBidsContent(gameState)
    return MyBidsTab.build(gameState)
end

function Market._buildListedContent(gameState, listedSubTab)
    return ListedTab.build(gameState, listedSubTab)
end

function Market._buildScoutContent(gameState, scoutFilters, subTab)
    return ScoutTab.build(gameState, scoutFilters, subTab)
end

function Market._buildFreeAgentsContent(gameState, posFilter)
    return FreeAgentsTab.build(gameState, posFilter)
end

function Market._showFreeAgentOfferSheet(gameState, player, posFilter)
    return FreeAgentsTab.showFreeAgentOfferSheet(gameState, player, posFilter)
end

return Market
