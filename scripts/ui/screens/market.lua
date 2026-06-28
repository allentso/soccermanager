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
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
local AudioManager = require("scripts/systems/audio_manager")
local YouthManager = require("scripts/systems/youth_manager")

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
local OVR_RANGES = {
    { key = "all",  label = "全部", min = 0,  max = 99 },
    { key = "80+",  label = "80+",  min = 80, max = 99 },
    { key = "70-79", label = "70-79", min = 70, max = 79 },
    { key = "60-69", label = "60-69", min = 60, max = 69 },
    { key = "<60",  label = "<60",  min = 0,  max = 59 },
}

-- 年龄范围筛选选项
local AGE_RANGES = {
    { key = "all", label = "全部", min = 0, max = 99 },
    { key = "u21", label = "U21", min = 0, max = 21 },
    { key = "22-25", label = "22-25", min = 22, max = 25 },
    { key = "26-29", label = "26-29", min = 26, max = 29 },
    { key = "30+", label = "30+", min = 30, max = 99 },
}

-- 浏览球员
function Market._buildBrowseContent(gameState, posFilter, searchQuery, ovrRange, ageRange)
    searchQuery = searchQuery or ""
    ovrRange = ovrRange or "all"
    ageRange = ageRange or "all"
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
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 4,
            onClick = function()
                Router.replaceWith("market", { tab = "browse", posFilter = f.key, searchQuery = searchQuery, ovrRange = ovrRange, ageRange = ageRange })
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

    -- 搜索框
    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingBottom = 6,
        children = {
            UI.TextField {
                width = "100%", height = 34,
                placeholder = "搜索球员/球队/国籍...",
                value = searchQuery,
                fontSize = 12,
                borderRadius = 8,
                onSubmit = function(self, text)
                    Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = text, ovrRange = ovrRange, ageRange = ageRange })
                end,
            },
        },
    })

    -- OVR 范围筛选
    local ovrBtns = {}
    for _, r in ipairs(OVR_RANGES) do
        local isActive = r.key == ovrRange
        table.insert(ovrBtns, UI.Button {
            text = r.label,
            height = 26,
            paddingLeft = 7,
            paddingRight = 7,
            backgroundColor = isActive and Theme.COLORS.GOLD_DIM or {38, 46, 71, 255},
            borderRadius = 13,
            fontSize = 10,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = searchQuery, ovrRange = r.key, ageRange = ageRange })
            end,
        })
    end
    -- 右侧追加列标注（与球员行的 星星/OVR/报价按钮 对齐）
    table.insert(ovrBtns, UI.Panel { flexGrow = 1 })
    table.insert(ovrBtns, UI.Label { text = "潜力★", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginRight = 6 })
    table.insert(ovrBtns, UI.Label { text = "能力", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "right", marginRight = 10 })
    table.insert(ovrBtns, UI.Panel { width = 50 })  -- 对齐报价按钮列

    table.insert(children, UI.Panel {
        width = "100%", height = 36, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        children = ovrBtns,
    })

    -- 年龄范围筛选
    local ageBtns = {}
    for _, r in ipairs(AGE_RANGES) do
        local isActive = r.key == ageRange
        table.insert(ageBtns, UI.Button {
            text = r.label,
            height = 26,
            paddingLeft = 7,
            paddingRight = 7,
            backgroundColor = isActive and Theme.COLORS.GOLD_DIM or {38, 46, 71, 255},
            borderRadius = 13,
            fontSize = 10,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = searchQuery, ovrRange = ovrRange, ageRange = r.key })
            end,
        })
    end

    table.insert(children, UI.Panel {
        width = "100%", height = 34, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        children = ageBtns,
    })

    -- 查找 OVR 范围
    local ovrMin, ovrMax = 0, 99
    for _, r in ipairs(OVR_RANGES) do
        if r.key == ovrRange then ovrMin, ovrMax = r.min, r.max break end
    end

    -- 查找年龄范围
    local ageMin, ageMax = 0, 99
    for _, r in ipairs(AGE_RANGES) do
        if r.key == ageRange then ageMin, ageMax = r.min, r.max break end
    end

    -- 收集可转会球员（排除自由球员，自由球员走专门的"自由球员"标签）
    local lowerQuery = searchQuery:lower()
    local availablePlayers = {}
    for _, p in pairs(gameState.players) do
        local onOtherTeam = p.teamId and p.teamId ~= gameState.playerTeamId
        local onOwnTeamWithSearch = lowerQuery ~= "" and p.teamId == gameState.playerTeamId
        if p.teamId and (onOtherTeam or onOwnTeamWithSearch) and not p.retired then
            -- 位置过滤（候选名单模式只显示在候选名单中的球员）
            local posMatch = false
            if posFilter == "SHORTLIST" then
                posMatch = gameState.shortlist and gameState.shortlist[p.id] == true
            elseif posFilter == "all" then
                posMatch = true
            else
                posMatch = getPositionGroup(p.position) == posFilter
            end
            if posMatch then
                -- OVR 和年龄范围过滤
                local playerAge = p:getAge(gameState.date.year)
                if p.overall >= ovrMin and p.overall <= ovrMax
                    and playerAge >= ageMin and playerAge <= ageMax then
                    -- 搜索过滤（球员名、球队名、国籍）
                    if lowerQuery == "" or
                       p.displayName:lower():find(lowerQuery, 1, true) or
                       (gameState.teams[p.teamId] and gameState.teams[p.teamId].name:lower():find(lowerQuery, 1, true)) or
                       ScoutManager.nationalityMatchesSearch(p.nationality, lowerQuery) then
                        table.insert(availablePlayers, p)
                    end
                end
            end
        end
    end

    -- 按能力排序取前40
    table.sort(availablePlayers, function(a, b) return a.overall > b.overall end)

    -- 球员列表
    local scoutAcc = _getScoutAccuracy(gameState)
    local maxShow = math.min(40, #availablePlayers)
    for i = 1, maxShow do
        local p = availablePlayers[i]
        local team = gameState.teams[p.teamId]
        local hasBid = TransferManager.hasPendingBid(gameState, p.id)
        local movedThisWindow = TransferManager.hasMovedInCurrentWindow(gameState, p.id)
        local releaseClause = TransferManager.getReleaseClause(gameState, p.id)
        local attitude, attitudeDesc = TransferManager.getPlayerTransferAttitude(gameState, p.id, gameState.playerTeamId)
        local competingBids = TransferManager.getCompetingBids(gameState, p.id)

        -- 态度颜色和文本
        local attitudeText = attitude == "eager" and "想转会" or (attitude == "open" and "愿考虑" or (attitude == "reluctant" and "不情愿" or "拒绝"))
        if attitude == "refusing" and attitudeDesc and attitudeDesc ~= "" then
            attitudeText = attitudeDesc
        end
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
        if p.isYouth then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {30, 70, 50, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "青训", fontSize = 9, color = {120, 220, 150, 255} } },
            })
        end
        if #competingBids > 0 then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {80, 30, 30, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = #competingBids .. "队竞价", fontSize = 9, color = {255, 120, 120, 255} } },
            })
        end
        if p.teamId and gameState.playerTeamId and TransferManager.isRivalry(gameState, p.teamId, gameState.playerTeamId) then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {120, 30, 30, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "死敌", fontSize = 9, color = {255, 160, 160, 255}, fontWeight = "bold" } },
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
                                ---@diagnostic disable-next-line: param-type-mismatch
                                UI.Label { text = p.displayName, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            },
                        },
                        movedThisWindow and UI.Panel {
                            width = 36, height = 28,
                            backgroundColor = {55, 55, 65, 255},
                            borderRadius = 6,
                            alignItems = "center",
                            justifyContent = "center",
                            marginRight = 6,
                            onClick = function()
                                TransferLimitDialog.show(p.displayName, gameState)
                            end,
                            children = {
                                UI.Label { text = "已转", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, fontWeight = "bold" },
                            },
                        } or UI.Panel { width = 0, height = 0 },
                        p.potential and UI.Label {
                            text = select(2, _getPotentialStars(p.potential, scoutAcc)),
                            fontSize = 10, color = Theme.COLORS.ACCENT, marginRight = 6,
                        } or UI.Panel { width = 0, height = 0 },
                        UI.Label {
                            text = tostring(p.overall),
                            fontSize = 16, color = Theme.COLORS.SECONDARY, fontWeight = "bold", marginRight = 10,
                        },
                        UI.Button {
                            text = movedThisWindow and "已转" or (hasBid and "已报" or (releaseClause and "解约" or "报价")),
                            width = 50, height = 28,
                            backgroundColor = (movedThisWindow or hasBid) and Theme.COLORS.TEXT_MUTED or Theme.COLORS.GOLD,
                            borderRadius = 6, fontSize = 12,
                            color = (movedThisWindow or hasBid) and Theme.COLORS.TEXT_PRIMARY or "#1A1A1A",
                            onClick = function()
                                if movedThisWindow then
                                    TransferLimitDialog.show(p.displayName, gameState)
                                    return
                                end
                                if not hasBid then
                                    if releaseClause then
                                        local _, err = TransferManager.triggerReleaseClause(gameState, p.id)
                                        if err then
                                            if not TransferLimitDialog.handleError(err, p.displayName, gameState) then
                                                AudioManager.deny()
                                                UI.Toast.Show({ message = err, variant = "error" })
                                            end
                                            return
                                        end
                                        UI.Toast.Show({ message = "已触发解约金买断", variant = "success" })
                                        Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = searchQuery, ovrRange = ovrRange, ageRange = ageRange })
                                    else
                                        Market._showBidSheet(gameState, p, posFilter, searchQuery, ovrRange, ageRange)
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
        local emptyText = posFilter == "SHORTLIST" and "候选名单为空，在球员详情页可添加" or "未找到球员"
        table.insert(children, UI.Panel {
            width = "100%", height = 100,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = emptyText, fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    end

    return children
end

-- 报价谈判弹窗
function Market._showBidSheet(gameState, player, posFilter, searchQuery, ovrRange, ageRange)
    if TransferLimitDialog.guardPlayer(gameState, player.id) then
        return
    end

    local team = gameState:getPlayerTeam()
    local budget = team and team.transferBudget or 0
    local pendingPayables = team and TransferManager.getPendingPayablesTotal(team) or 0
    local wageBudget = team and team.wageBudget or 0
    local currentWage = team and FinanceManager.getWeeklyWageTotal(gameState, team.id) or 0
    local baseValue = player.value
    local sellerTeam = gameState.teams[player.teamId]
    local suggestedWage = TransferManager.getSuggestedTransferWage(player, gameState:getPlayerTeam(), gameState)

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
        value = Market._amountToWanText(suggestedWage),
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

    -- 快捷周薪按钮（基于市场合理周薪，与 AI 出价逻辑一致）
    local wagePresets = { 0.9, 1.0, 1.2, 1.5 }
    local wagePresetBtns = {}
    for _, mul in ipairs(wagePresets) do
        local wageAmount = math.max(500, math.floor(suggestedWage * mul))
        table.insert(wagePresetBtns, UI.Button {
            text = Market._formatValue(wageAmount),
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                wageField:SetValue(Market._amountToWanText(wageAmount))
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
                            math.min(Constants.ABILITY_MAX, player.overall or 0),
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

    -- 预算与负债概览
    local budgetRows = {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 3,
            children = {
                UI.Label { text = "可用转会预算", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = FinanceManager.formatMoney(budget), fontSize = 12, fontWeight = "bold",
                    color = budget > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.DANGER },
            },
        },
    }
    if pendingPayables > 0 then
        table.insert(budgetRows, UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 3,
            children = {
                UI.Label { text = "未付分期负债", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = "-" .. FinanceManager.formatMoney(pendingPayables), fontSize = 12,
                    color = Theme.COLORS.WARNING or Theme.COLORS.DANGER },
            },
        })
    end
    table.insert(budgetRows, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        children = {
            UI.Label { text = "周薪预算（已用/总）", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            UI.Label {
                text = string.format("%s / %s", FinanceManager.formatMoney(currentWage), FinanceManager.formatMoney(wageBudget)),
                fontSize = 12, fontWeight = "bold",
                color = currentWage >= wageBudget and Theme.COLORS.DANGER or Theme.COLORS.TEXT_PRIMARY,
            },
        },
    })
    table.insert(children, UI.Panel {
        width = "100%", backgroundColor = {30, 36, 56, 255}, borderRadius = 6,
        padding = 10, marginBottom = 12, children = budgetRows,
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
        backgroundColor = Theme.COLORS.GOLD,
        borderRadius = 8, fontSize = 15, fontWeight = "bold",
        color = "#1A1A1A",
        onClick = function()
            local bidText = bidField:GetValue() or ""
            local bidAmount = tonumber(bidText)
            if not bidAmount or bidAmount <= 0 then return end
            local offerAmount = math.floor(bidAmount * 10000)

            local wageText = wageField:GetValue() or ""
            local wageAmount = tonumber(wageText)
            if not wageAmount or wageAmount <= 0 then return end
            local offeredWage = math.floor(wageAmount * 10000)

            if offerAmount > budget then
                AudioManager.deny()
                local hint = pendingPayables > 0
                    and string.format("转会预算不足！可用 %s（已扣未付分期负债 %s）",
                        FinanceManager.formatMoney(budget), FinanceManager.formatMoney(pendingPayables))
                    or ("转会预算不足！剩余预算: " .. FinanceManager.formatMoney(budget))
                UI.Toast.Show({ message = hint, variant = "error" })
                return
            end

            -- 工资预算硬约束：引援后总周薪不得超出工资预算
            if wageBudget > 0 and (currentWage + offeredWage) > wageBudget then
                AudioManager.deny()
                UI.Toast.Show({
                    message = string.format("工资预算不足！引援后周薪 %s 将超出预算 %s，请降低周薪或先清理高薪球员。",
                        FinanceManager.formatMoney(currentWage + offeredWage), FinanceManager.formatMoney(wageBudget)),
                    variant = "error",
                })
                return
            end

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
            local bid, bidErr = TransferManager.makeBidWithClauses(gameState, player.id, offerAmount, offeredWage, clauses)
            if bid then
                bid.contractYears = offeredYears
                UI.Toast.Show({ message = "报价已提交", variant = "success" })
            else
                if not TransferLimitDialog.handleError(bidErr, player.displayName, gameState) then
                    AudioManager.deny()
                    UI.Toast.Show({ message = bidErr or "报价失败", variant = "error" })
                end
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
                                Market._showBatchTransferSignConfirmSheet(gameState, pendingSign)
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
                        text = feeLabel .. ": " .. Market._formatValue(bid.amount),
                        fontSize = 13, color = Theme.COLORS.ACCENT,
                    },
                    UI.Label {
                        text = "  " .. refLabel .. ": " .. Market._formatValue(bid.playerValue or 0),
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
                        text = (isLoan and "租借费差距: " or "差距: ") .. string.format("%s (%.0f%%)",
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
                                Market._formatValue(bid.amount or 0),
                                bid.loanDuration or 26,
                                (bid.wageShare or 0.5) * 100)
                            or string.format("周薪: %s · 合同: %d年",
                                Market._formatValue(bid.wageOffer or 0),
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

-- 挂牌出售（我方球员：一线队 + 青训队）
function Market._collectTeamRosterPlayers(gameState, team)
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

            bidInfo = string.format("%d份报价 · 最高 %s", #incomingBids, Market._formatValue(incomingBids[1].amount or 0))
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
                bidInfo = "球员考虑中 · " .. (buyer and buyer.name or "买方") .. " " .. Market._formatValue(primaryBid.amount)
                bidColor = {255, 180, 60, 255}
                btnText = "查看"
            elseif primaryBid.status == "awaiting_sale_confirmation" then
                bidInfo = "待确认 · " .. Market._formatValue(primaryBid.amount) .. " → " .. (buyer and buyer.name or "买方")
                bidColor = Theme.COLORS.SECONDARY
                btnText = "确认"
            else
                bidInfo = (buyer and buyer.name or "未知") .. " 出价 " .. Market._formatValue(primaryBid.amount)
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
                    Market._showOfferSheet(gameState, p)
                    return
                end
                if primaryBid and primaryBid.status == "awaiting_sale_confirmation" then
                    local batchSales = TransferManager.getPendingSaleConfirmations(gameState, team.id)
                    if #batchSales > 1 then
                        Market._showBatchSaleConfirmSheet(gameState, batchSales)
                        return
                    end
                end
                Market._showOfferSheet(gameState, p, primaryBid)
            end,
        }
    elseif showCancelWhenNoBid then
        actionButton = UI.Button {
            text = "取消",
            width = 50, height = 28,
            backgroundColor = {80, 80, 100, 255},
            borderRadius = 6, fontSize = 12,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                TransferManager.delistPlayer(gameState, p)
                Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
            end,
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
                    UI.Label { text = Market._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
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

function Market._buildListedContent(gameState, listedSubTab)
    listedSubTab = listedSubTab or "status"
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 分类球员：已挂牌 / 被挖角 / 可挂牌（含青训名单）
    local listedPlayers = {}
    local poachedPlayers = {}
    local availablePlayers = {}
    local listedPlayerIds = {}
    for _, p in ipairs(Market._collectTeamRosterPlayers(gameState, team)) do
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
            if _playerStillOnTeam(p, playerId) then
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
                                    local ok, err = TransferManager.listForSale(gameState, p)
                                    if not ok then
                                        if not TransferLimitDialog.handleError(err, p.displayName, gameState) then
                                            gameState:sendMessage({
                                                category = "transfer",
                                                title = "无法挂牌",
                                                body = err or "条件不满足",
                                                priority = "normal",
                                            })
                                        end
                                        return
                                    end
                                    Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
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
                                Market._showBatchSaleConfirmSheet(gameState, pendingSales)
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
                                        #pendingSales, Market._formatValue(totalAmount)),
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
function Market._buildScoutContent(gameState, scoutFilters, subTab)
    scoutFilters = scoutFilters or {}
    subTab = subTab or "explore"
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 获取球探
    local scouts = {}
    for _, sid in ipairs(team.staffIds or {}) do
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
                    text = "球队没有球探，无法探索球员。\n请在职员页面雇佣球探。",
                    fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                    textAlign = "center",
                },
            }
        })
        return children
    end

    -- ====== 子标签栏 ======
    local reports = ScoutManager.getReports(gameState)
    local subTabs = {
        { key = "explore", label = "探索" },
        { key = "reports", label = string.format("报告 (%d)", #reports) },
    }
    local subTabButtons = {}
    for _, st in ipairs(subTabs) do
        local isActive = st.key == subTab
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
                Router.replaceWith("market", { tab = "scout", scoutSubTab = st.key,
                    scoutLeague = scoutFilters.league, scoutPos = scoutFilters.position,
                    scoutNat = scoutFilters.nationality, scoutAge = scoutFilters.ageKey })
            end,
        })
    end
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
        children = subTabButtons,
    })

    -- ====== 根据子标签显示内容 ======
    if subTab == "explore" then
        Market._buildScoutExploreContent(children, gameState, scoutFilters, scouts)
    else
        Market._buildScoutReportsContent(children, gameState)
    end

    return children
end

-- 球探子页面：探索条件 + 球探团队 + 进行中的任务
-- 模块级状态：球探筛选（避免 Router.replaceWith 重建页面）
Market._exploreFilterState = { league = nil, position = nil, nationality = nil, ageKey = "any" }
Market._exploreContainerRef = nil
Market._exploreGameState = nil
Market._exploreScouts = nil

local SCOUT_POSITIONS = {"GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"}
local AGE_RANGES = {
    { key = "any",   label = "不限",       min = nil, max = nil },
    { key = "u21",   label = "U21",        min = 16,  max = 21 },
    { key = "young", label = "22-27",      min = 22,  max = 27 },
    { key = "peak",  label = "28-32",      min = 28,  max = 32 },
    { key = "vet",   label = "33+",        min = 33,  max = 40 },
}

-- 就地刷新探索区域（不重建页面）
function Market._refreshExploreContainer()
    if Market._exploreContainerRef then
        Market._exploreContainerRef:ClearChildren()
        local innerChildren = Market._buildExploreInner()
        for _, child in ipairs(innerChildren) do
            Market._exploreContainerRef:AddChild(child)
        end
    end
end

-- 生成探索区域的 children 数组
function Market._buildExploreInner()
    local gameState = Market._exploreGameState
    local scouts = Market._exploreScouts or {}
    local fs = Market._exploreFilterState
    local activeTasks = ScoutManager.getActiveTasks(gameState)

    local selLeague = fs.league
    local selPos = fs.position
    local selNat = fs.nationality
    local selAgeKey = fs.ageKey or "any"

    -- 帮助函数：更新筛选并刷新
    local function applyFilter(overrides)
        for k, v in pairs(overrides) do
            if v == "__nil" then
                fs[k] = nil
            else
                fs[k] = v
            end
        end
        Market._refreshExploreContainer()
    end

    local items = {}

    -- 球探团队信息
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8, padding = 12, marginBottom = 10,
        children = {
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label { text = "球探团队", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Label {
                        text = string.format("%d 名球探 · 准确度 %d%% · 任务 %d/3", #scouts, math.floor(ScoutManager.getAccuracy(gameState) * 100), #activeTasks),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                    },
                }
            },
        }
    })

    -- ====== 内嵌筛选区域 ======
    local leagues = ScoutManager.getAvailableLeagues(gameState)

    -- 联赛筛选
    local leagueItems = {}
    local allLeagueActive = (selLeague == nil)
    table.insert(leagueItems, UI.Button {
        text = "全部", height = 28, paddingLeft = 8, paddingRight = 8,
        backgroundColor = allLeagueActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_HEADER,
        borderRadius = 14, marginRight = 6, marginBottom = 4,
        fontSize = 10, color = allLeagueActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ league = "__nil" }) end,
    })
    for _, lg in ipairs(leagues) do
        local active = (selLeague == lg.id)
        table.insert(leagueItems, UI.Button {
            text = lg.name, height = 28, paddingLeft = 8, paddingRight = 8,
            backgroundColor = active and Theme.COLORS.PRIMARY or Theme.COLORS.BG_HEADER,
            borderRadius = 14, marginRight = 6, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ league = lg.id }) end,
        })
    end

    -- 位置筛选
    local posItems = {}
    local allPosActive = (selPos == nil)
    table.insert(posItems, UI.Button {
        text = "全部", height = 26, paddingLeft = 6, paddingRight = 6,
        backgroundColor = allPosActive and Theme.COLORS.ACCENT or Theme.COLORS.BG_HEADER,
        borderRadius = 12, marginRight = 4, marginBottom = 4,
        fontSize = 10, color = allPosActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ position = "__nil" }) end,
    })
    for _, pos in ipairs(SCOUT_POSITIONS) do
        local posName = Constants.POSITION_NAMES[pos] or pos
        local active = (selPos == pos)
        table.insert(posItems, UI.Button {
            text = posName, height = 26, paddingLeft = 6, paddingRight = 6,
            backgroundColor = active and Theme.COLORS.ACCENT or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 4, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ position = pos }) end,
        })
    end

    -- 国籍筛选
    local nationalities = ScoutManager.getAvailableNationalities(gameState)
    local natItems = {}
    local allNatActive = (selNat == nil)
    table.insert(natItems, UI.Button {
        text = "全部", height = 26, paddingLeft = 6, paddingRight = 6,
        backgroundColor = allNatActive and {180, 100, 220, 255} or Theme.COLORS.BG_HEADER,
        borderRadius = 12, marginRight = 4, marginBottom = 4,
        fontSize = 10, color = allNatActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ nationality = "__nil" }) end,
    })
    for _, nat in ipairs(nationalities) do
        local active = (selNat == nat.code)
        table.insert(natItems, UI.Button {
            text = nat.name, height = 26, paddingLeft = 6, paddingRight = 6,
            backgroundColor = active and {180, 100, 220, 255} or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 4, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ nationality = nat.code }) end,
        })
    end

    -- 年龄筛选
    local ageItems = {}
    for _, range in ipairs(AGE_RANGES) do
        local active = (selAgeKey == range.key)
        table.insert(ageItems, UI.Button {
            text = range.label, height = 26, paddingLeft = 8, paddingRight = 8,
            backgroundColor = active and Theme.COLORS.SECONDARY or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 6, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ ageKey = range.key }) end,
        })
    end

    -- 筛选面板
    table.insert(items, UI.Panel {
        width = "100%", backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8, padding = 10, marginBottom = 10,
        children = {
            UI.Label { text = "探索条件", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", marginBottom = 6 },
            -- 联赛
            UI.Label { text = "联赛", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = leagueItems },
            -- 位置
            UI.Label { text = "位置", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = posItems },
            -- 国籍
            UI.Label { text = "国籍", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = natItems },
            -- 年龄
            UI.Label { text = "年龄", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10, children = ageItems },
            -- 派出按钮
            UI.Button {
                text = #activeTasks >= 3 and "任务已满 (3/3)" or "派出球探探索",
                width = "100%", height = 36,
                backgroundColor = #activeTasks >= 3 and Theme.COLORS.BG_HEADER or Theme.COLORS.PRIMARY,
                borderRadius = 8,
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                onClick = function()
                    if #activeTasks >= 3 then
                        UI.Toast.Show({ message = "已达最大任务数 (3/3)", variant = "warning" })
                        return
                    end
                    -- 构造 filters
                    local filters = {}
                    if selLeague then filters.leagueId = selLeague end
                    if selPos then filters.position = selPos end
                    if selNat then filters.nationality = selNat end
                    for _, r in ipairs(AGE_RANGES) do
                        if r.key == selAgeKey and r.min then
                            filters.minAge = r.min
                            filters.maxAge = r.max
                            break
                        end
                    end
                    local ok, err = ScoutManager.createSearchTask(gameState, filters)
                    if ok then
                        UI.Toast.Show({ message = "探索任务已创建", variant = "success" })
                        Market._refreshExploreContainer()
                    else
                        UI.Toast.Show({ message = err or "操作失败", variant = "error" })
                    end
                end,
            },
        }
    })

    -- ====== 进行中的任务 ======
    if #activeTasks > 0 then
        table.insert(items, UI.Label {
            text = string.format("进行中 (%d/3)", #activeTasks),
            fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
            fontWeight = "bold", marginBottom = 6, marginTop = 4,
        })
        for _, task in ipairs(activeTasks) do
            local progressPct = task.progress or 0
            table.insert(items, UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 8, padding = 10, marginBottom = 6,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
                        children = {
                            UI.Label {
                                text = task.description,
                                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1, flexShrink = 1,
                            },
                            UI.Label {
                                text = string.format("剩余 %d 天", task.daysRemaining),
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginLeft = 6,
                            },
                            UI.Button {
                                text = "×", width = 24, height = 24,
                                backgroundColor = {60, 30, 30, 150}, borderRadius = 12,
                                fontSize = 13, color = Theme.COLORS.DANGER, marginLeft = 6,
                                onClick = function()
                                    ConfirmDialog.show({
                                        title = "取消探索任务",
                                        message = "确定取消「" .. task.description .. "」？",
                                        confirmText = "取消任务", danger = true,
                                        onConfirm = function()
                                            ScoutManager.cancelTask(gameState, task.id)
                                            Market._refreshExploreContainer()
                                        end,
                                    })
                                end,
                            },
                        }
                    },
                    -- 进度条
                    UI.Panel {
                        width = "100%", height = 5,
                        backgroundColor = {38, 46, 71, 255}, borderRadius = 3,
                        children = {
                            UI.Panel {
                                width = tostring(progressPct) .. "%", height = 5,
                                backgroundColor = progressPct >= 80 and Theme.COLORS.SECONDARY or Theme.COLORS.PRIMARY,
                                borderRadius = 3,
                            }
                        }
                    },
                }
            })
        end
    end

    return items
end

function Market._buildScoutExploreContent(children, gameState, scoutFilters, scouts)
    -- 初始化模块级状态
    Market._exploreGameState = gameState
    Market._exploreScouts = scouts
    Market._exploreFilterState.league = scoutFilters.league
    Market._exploreFilterState.position = scoutFilters.position
    Market._exploreFilterState.nationality = scoutFilters.nationality
    Market._exploreFilterState.ageKey = scoutFilters.ageKey or "any"

    -- 创建容器并保存引用，筛选变更时通过 SetChildren 就地更新
    local container = UI.Panel {
        width = "100%",
        children = Market._buildExploreInner(),
    }
    Market._exploreContainerRef = container
    table.insert(children, container)
end

-- 球探子页面：球探报告列表
function Market._buildScoutReportsContent(children, gameState)
    local reports = ScoutManager.getReports(gameState)

    if #reports == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 100,
            backgroundColor = Theme.COLORS.BG_CARD, borderRadius = 8,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无球探报告", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                UI.Label { text = "派出球探探索后，报告将在此显示", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6 },
            }
        })
    else
        local REC_COLORS = {
            ["强烈推荐签入"] = {0, 230, 118, 255},
            ["实力强劲，可即战"] = {102, 255, 128, 255},
            ["潜力新星，值得培养"] = {102, 178, 255, 255},
            ["水平尚可，可作补充"] = {255, 204, 0, 255},
            ["不建议签入"] = {255, 100, 100, 255},
        }
        table.insert(children, UI.Label {
            text = string.format("共 %d 份报告", #reports),
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            marginBottom = 8,
        })
        for _, report in ipairs(reports) do
            local recColor = REC_COLORS[report.recommendation] or Theme.COLORS.TEXT_SECONDARY
            table.insert(children, UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 8, padding = 10, marginBottom = 6,
                onClick = function()
                    Router.navigate("player_detail", { playerId = report.playerId })
                end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 3,
                        children = {
                            UI.Label {
                                text = report.playerPosition or "?",
                                fontSize = 10, color = Theme.COLORS.ACCENT, fontWeight = "bold", width = 30,
                            },
                            UI.Label {
                                text = report.playerName,
                                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1,
                            },
                            UI.Label {
                                text = tostring(report.overall),
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label {
                                text = report.recommendation,
                                fontSize = 10, color = recColor, fontWeight = "bold", flexGrow = 1,
                            },
                            UI.Label {
                                text = string.format("%s · %d岁", report.teamName or "?", report.playerAge or 0),
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                            },
                        }
                    },
                }
            })
        end
    end
end

------------------------------------------------------
-- 球探：报告详情
------------------------------------------------------
function Market._showReportDetail(report, gameState)
    local REC_COLORS = {
        ["强烈推荐签入"] = {0, 230, 118, 255},
        ["实力强劲，可即战"] = {102, 255, 128, 255},
        ["潜力新星，值得培养"] = {102, 178, 255, 255},
        ["水平尚可，可作补充"] = {255, 204, 0, 255},
        ["不建议签入"] = {255, 100, 100, 255},
    }
    local recColor = REC_COLORS[report.recommendation] or Theme.COLORS.TEXT_SECONDARY

    -- 属性列表
    local attrChildren = {}
    local attrLabels = {
        pace = "速度", shooting = "射门", passing = "传球",
        dribbling = "盘带", defending = "防守", physical = "身体",
    }
    local attrs = report.attributes or {}
    for key, label in pairs(attrLabels) do
        if attrs[key] then
            table.insert(attrChildren, UI.Panel {
                width = "48%", height = 28,
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Label { text = label, fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label {
                        text = tostring(attrs[key]),
                        fontSize = 12, fontWeight = "bold",
                        color = attrs[key] >= 15 and Theme.COLORS.SECONDARY
                            or (attrs[key] >= 10 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY),
                    },
                }
            })
        end
    end

    -- 合同信息
    local contractText = "未知"
    if report.contractEnd then
        contractText = string.format("%d年%d月到期", report.contractEnd.year or 0, report.contractEnd.month or 0)
    end

    local detailContent = {
        -- 头部：总评 + 潜力
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "center", marginBottom = 12,
            children = {
                UI.Panel {
                    alignItems = "center", marginRight = 24,
                    children = {
                        UI.Label { text = "总评", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label { text = tostring(report.overall), fontSize = 28, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    }
                },
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = "潜力", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label {
                            text = tostring(report.potential or "?"),
                            fontSize = 20, color = Theme.COLORS.SECONDARY, fontWeight = "bold",
                        },
                    }
                },
            }
        },
        -- 推荐评级
        UI.Panel {
            width = "100%", height = 32,
            backgroundColor = {recColor[1], recColor[2], recColor[3], 30},
            borderRadius = 6,
            justifyContent = "center", alignItems = "center", marginBottom = 12,
            children = {
                UI.Label { text = report.recommendation, fontSize = 13, color = recColor, fontWeight = "bold" },
            }
        },
        -- 基本信息
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between", marginBottom = 8,
            children = {
                UI.Label { text = "位置: " .. (report.playerPosition or "?"), fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                UI.Label { text = "年龄: " .. tostring(report.playerAge or 0), fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                UI.Label { text = "准确度: " .. tostring(report.accuracy or 0) .. "%", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
            }
        },
        -- 合同/工资
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between", marginBottom = 12,
            children = {
                UI.Label {
                    text = "工资: " .. FinanceManager.formatMoney(report.wage or 0) .. "/周",
                    fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                },
                UI.Label { text = contractText, fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
            }
        },
        -- 属性
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between",
            children = attrChildren,
        },
    }

    BottomSheet.showCustom({
        title = report.playerName .. " - 球探报告",
        children = detailContent,
        showCancel = true,
    })
end

-- 自由球员
function Market._buildFreeAgentsContent(gameState, posFilter)
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
                            Market._showBatchFreeAgentConfirmSheet(gameState, pendingFreeSign)
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
                                Market._formatValue(item.wageOffer or 0), item.yearsOffer or 3),
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
                                    Market._formatValue(nego.wageOffer or 0),
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
                    Market._showFreeAgentOfferSheet(gameState, p, posFilter)
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

-- 自由球员合同谈判面板
function Market._showFreeAgentOfferSheet(gameState, player, posFilter)
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
                            Market._formatValue(expectedWage)),
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

return Market
