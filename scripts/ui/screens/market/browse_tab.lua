-- ui/screens/market/browse_tab.lua
-- ??/???????????? market.lua ???

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

local MarketHelpers = require("scripts/ui/screens/market/market_helpers")
local getPositionGroup = MarketHelpers.getPositionGroup
local _getPotentialStars = MarketHelpers.getPotentialStars
local function _market()
    return require("scripts/ui/screens/market")
end

local OVR_RANGES = {
    { key = "all",  label = "??", min = 0,  max = 99 },
    { key = "80+",  label = "80+",  min = 80, max = 99 },
    { key = "70-79", label = "70-79", min = 70, max = 79 },
    { key = "60-69", label = "60-69", min = 60, max = 69 },
    { key = "<60",  label = "<60",  min = 0,  max = 59 },
}

-- ????????
local AGE_RANGES = {
    { key = "all", label = "??", min = 0, max = 99 },
    { key = "u21", label = "U21", min = 0, max = 21 },
    { key = "22-25", label = "22-25", min = 22, max = 25 },
    { key = "26-29", label = "26-29", min = 26, max = 29 },
    { key = "30+", label = "30+", min = 30, max = 99 },
}

-- ????
function Tab.build(gameState, posFilter, searchQuery, ovrRange, ageRange)
    searchQuery = (searchQuery or ""):match("^%s*(.-)%s*$") or ""
    ovrRange = ovrRange or "all"
    ageRange = ageRange or "all"
    local children = {}

    -- ?????
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

    -- ???
    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingBottom = 6,
        children = {
            UI.TextField {
                width = "100%", height = 34,
                placeholder = "????/??/??...",
                value = searchQuery,
                fontSize = 12,
                borderRadius = 8,
                onSubmit = function(self, text)
                    Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = text, ovrRange = ovrRange, ageRange = ageRange })
                end,
            },
        },
    })

    -- OVR ????
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
    -- ????????????? ??/OVR/???? ???
    table.insert(ovrBtns, UI.Panel { flexGrow = 1 })
    table.insert(ovrBtns, UI.Label { text = "???", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginRight = 6 })
    table.insert(ovrBtns, UI.Label { text = "??", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "right", marginRight = 10 })
    table.insert(ovrBtns, UI.Panel { width = 50 })  -- ???????

    table.insert(children, UI.Panel {
        width = "100%", height = 36, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        children = ovrBtns,
    })

    -- ??????
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

    -- ?? OVR ??
    local ovrMin, ovrMax = 0, 99
    for _, r in ipairs(OVR_RANGES) do
        if r.key == ovrRange then ovrMin, ovrMax = r.min, r.max break end
    end

    -- ??????
    local ageMin, ageMax = 0, 99
    for _, r in ipairs(AGE_RANGES) do
        if r.key == ageRange then ageMin, ageMax = r.min, r.max break end
    end

    -- ???????????????????????"????"?????????????????
    local lowerQuery = searchQuery:lower()
    local isSearching = lowerQuery ~= ""
    local availablePlayers = {}
    for _, p in pairs(gameState.players) do
        if p.retired then goto continue end

        local isFreeAgent = not p.teamId
        local onOtherTeam = p.teamId and p.teamId ~= gameState.playerTeamId
        local onOwnTeamWithSearch = isSearching and p.teamId == gameState.playerTeamId
        local eligible = onOtherTeam or onOwnTeamWithSearch or (isSearching and isFreeAgent)
        if not eligible then goto continue end

        -- ????????????????????????
        local posMatch = false
        if posFilter == "SHORTLIST" then
            posMatch = gameState.shortlist and gameState.shortlist[p.id] == true
        elseif posFilter == "all" then
            posMatch = true
        else
            posMatch = getPositionGroup(p.position) == posFilter
        end
        if not posMatch then goto continue end

        -- OVR ???????
        local playerAge = p:getAge(gameState.date.year)
        if p.overall < ovrMin or p.overall > ovrMax
            or playerAge < ageMin or playerAge > ageMax then
            goto continue
        end

        -- ????????/??/??/????
        if isSearching and not ScoutManager.playerMatchesMarketSearch(gameState, p, lowerQuery) then
            goto continue
        end

        table.insert(availablePlayers, p)
        ::continue::
    end

    -- ??????????????????
    if isSearching then
        table.sort(availablePlayers, function(a, b)
            local rankA = ScoutManager.getPlayerSearchRank(a, lowerQuery)
            local rankB = ScoutManager.getPlayerSearchRank(b, lowerQuery)
            if rankA ~= rankB then return rankA > rankB end
            return a.overall > b.overall
        end)
    else
        table.sort(availablePlayers, function(a, b) return a.overall > b.overall end)
    end

    local maxShow = isSearching and math.min(100, #availablePlayers) or math.min(40, #availablePlayers)
    local scoutAcc = MarketHelpers.getScoutAccuracy(gameState)
    for i = 1, maxShow do
        local p = availablePlayers[i]
        local team = gameState.teams[p.teamId]
        local isFreeAgent = not p.teamId
        local hasBid = TransferManager.hasPendingBid(gameState, p.id)
        local movedThisWindow = TransferManager.hasMovedInCurrentWindow(gameState, p.id)
        local releaseClause = TransferManager.getReleaseClause(gameState, p.id)
        local attitude, attitudeDesc = TransferManager.getPlayerTransferAttitude(gameState, p.id, gameState.playerTeamId)
        local competingBids = TransferManager.getCompetingBids(gameState, p.id)

        -- ???????
        local attitudeText = attitude == "eager" and "???" or (attitude == "open" and "???" or (attitude == "reluctant" and "???" or "??"))
        if attitude == "refusing" and attitudeDesc and attitudeDesc ~= "" then
            attitudeText = attitudeDesc
        end
        local attitudeColor = attitude == "eager" and Theme.COLORS.SECONDARY
            or (attitude == "open" and Theme.COLORS.ACCENT
            or (attitude == "reluctant" and Theme.COLORS.WARNING or Theme.COLORS.DANGER))

        -- ??????
        local extraTags = {}
        if releaseClause then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {80, 60, 20, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "?? " .. _market()._formatValue(releaseClause), fontSize = 9, color = {255, 200, 80, 255} } },
            })
        end
        if p.isYouth then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {30, 70, 50, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "??", fontSize = 9, color = {120, 220, 150, 255} } },
            })
        end
        if #competingBids > 0 then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {80, 30, 30, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = #competingBids .. "???", fontSize = 9, color = {255, 120, 120, 255} } },
            })
        end
        if p.teamId and gameState.playerTeamId and TransferManager.isRivalry(gameState, p.teamId, gameState.playerTeamId) then
            table.insert(extraTags, UI.Panel {
                backgroundColor = {120, 30, 30, 255}, borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2, marginRight = 4,
                children = { UI.Label { text = "??", fontSize = 9, color = {255, 160, 160, 255}, fontWeight = "bold" } },
            })
        end

        table.insert(children, UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                -- ?????? + ??? + ?? + ????
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
                                UI.Label { text = "??", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, fontWeight = "bold" },
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
                            text = movedThisWindow and "??" or (hasBid and "??" or (isFreeAgent and "??" or (releaseClause and "??" or "??"))),
                            width = 50, height = 28,
                            backgroundColor = (movedThisWindow or hasBid) and Theme.COLORS.TEXT_MUTED or Theme.COLORS.GOLD,
                            borderRadius = 6, fontSize = 12,
                            color = (movedThisWindow or hasBid) and Theme.COLORS.TEXT_PRIMARY or "#1A1A1A",
                            onClick = function()
                                if movedThisWindow then
                                    TransferLimitDialog.show(p.displayName, gameState)
                                    return
                                end
                                if isFreeAgent then
                                    Router.replaceWith("market", { tab = "free", posFilter = posFilter })
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
                                        UI.Toast.Show({ message = "????????", variant = "success" })
                                        Router.replaceWith("market", { tab = "browse", posFilter = posFilter, searchQuery = searchQuery, ovrRange = ovrRange, ageRange = ageRange })
                                    else
                                        Tab.showBidSheet(gameState, p, posFilter, searchQuery, ovrRange, ageRange)
                                    end
                                end
                            end,
                        },
                    },
                },
                -- ?????? | ?? | ?? | ?? | ??
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                    children = {
                        UI.Label {
                            text = (team and team.name or "??"),
                            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexShrink = 1,
                        },
                        UI.Label { text = " ? ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = p:getAge(gameState.date.year) .. "?", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label { text = " ? ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = _market()._formatValue(p.value), fontSize = 11, color = Theme.COLORS.ACCENT },
                        UI.Label { text = " ? ", fontSize = 11, color = Theme.COLORS.BORDER },
                        UI.Label { text = attitudeText, fontSize = 11, color = attitudeColor },
                        UI.Panel { flexGrow = 1 },
                        table.unpack(extraTags),
                    },
                },
            },
        })
    end

    if maxShow == 0 then
        local emptyText
        if posFilter == "SHORTLIST" then
            emptyText = "????????????????"
        elseif isSearching then
            emptyText = "???????????????????????"
        else
            emptyText = "?????"
        end
        table.insert(children, UI.Panel {
            width = "100%", height = 100,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = emptyText, fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    end

    if isSearching and #availablePlayers > maxShow then
        table.insert(children, UI.Panel {
            width = "100%", paddingTop = 8, paddingBottom = 12,
            alignItems = "center",
            children = {
                UI.Label {
                    text = string.format("? %d ??????? %d ?", #availablePlayers, maxShow),
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                },
            },
        })
    end

    return children
end

-- ??????
function Tab.showBidSheet(gameState, player, posFilter, searchQuery, ovrRange, ageRange)
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
        { key = "simple", label = "??????????", installments = 1, bonus = 0, sellOn = 0 },
        { key = "standard", label = "2??????8%???10%", installments = 2, bonus = 0.08, sellOn = 10 },
        { key = "heavy", label = "3??????12%???15%", installments = 3, bonus = 0.12, sellOn = 15 },
    }
    local yearsOptions = { 2, 3, 4, 5 }

    -- ??
    local selectedClauseIdx = 2
    local selectedYearsIdx = 2

    -- ????????
    local bidField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "???????",
        value = tostring(math.floor(baseValue * 1.1 / 10000)),
        fontSize = 14, borderRadius = 6,
    }

    local wageField = UI.TextField {
        flexGrow = 1, height = 38,
        placeholder = "???????",
        value = _market()._amountToWanText(suggestedWage),
        fontSize = 14, borderRadius = 6,
    }

    -- ??????
    local bidPresets = {
        { label = "?0.9", multiplier = 0.9 },
        { label = "?1.0", multiplier = 1.0 },
        { label = "?1.1", multiplier = 1.1 },
        { label = "?1.2", multiplier = 1.2 },
        { label = "?1.35", multiplier = 1.35 },
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

    -- ????????????????? AI ???????
    local wagePresets = { 0.9, 1.0, 1.2, 1.5 }
    local wagePresetBtns = {}
    for _, mul in ipairs(wagePresets) do
        local wageAmount = math.max(500, math.floor(suggestedWage * mul))
        table.insert(wagePresetBtns, UI.Button {
            text = _market()._formatValue(wageAmount),
            height = 28, paddingLeft = 6, paddingRight = 6, marginRight = 4,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 5, fontSize = 11,
            color = Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                wageField:SetValue(_market()._amountToWanText(wageAmount))
            end,
        })
    end

    -- ???????????????
    local clauseBtns = {}
    for i, c in ipairs(clauseOptions) do
        local btn = UI.Button {
            text = (i == selectedClauseIdx and "? " or "  ") .. c.label,
            width = "100%", height = 34, marginBottom = 3,
            backgroundColor = (i == selectedClauseIdx) and Theme.COLORS.ACCENT or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12, textAlign = "left", paddingLeft = 10,
            color = (i == selectedClauseIdx) and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function(self)
                selectedClauseIdx = i
                for j, b in ipairs(clauseBtns) do
                    local isSel = (j == i)
                    b:SetText((isSel and "? " or "  ") .. clauseOptions[j].label)
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

    -- ????
    local yearsBtns = {}
    for i, y in ipairs(yearsOptions) do
        local btn = UI.Button {
            text = (i == selectedYearsIdx and "? " or "") .. y .. "?",
            height = 30, marginRight = 6,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = (i == selectedYearsIdx) and Theme.COLORS.SECONDARY or {38, 46, 71, 255},
            borderRadius = 6, fontSize = 12,
            color = (i == selectedYearsIdx) and {20, 20, 20, 255} or Theme.COLORS.TEXT_SECONDARY,
            onClick = function(self)
                selectedYearsIdx = i
                for j, b in ipairs(yearsBtns) do
                    local isSel = (j == i)
                    b:SetText((isSel and "? " or "") .. yearsOptions[j] .. "?")
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

    -- ????
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 12,
        children = {
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label { text = player.displayName, fontSize = 16, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY },
                    UI.Label {
                        text = string.format("%s | %s | ?? %d | %d?",
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
                    UI.Label { text = "?? " .. _market()._formatValue(baseValue), fontSize = 12, color = Theme.COLORS.ACCENT },
                },
            },
        }
    })

    -- ???????
    local budgetRows = {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 3,
            children = {
                UI.Label { text = "??????", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = FinanceManager.formatMoney(budget), fontSize = 12, fontWeight = "bold",
                    color = budget > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.DANGER },
            },
        },
    }
    if pendingPayables > 0 then
        table.insert(budgetRows, UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 3,
            children = {
                UI.Label { text = "??????", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = "-" .. FinanceManager.formatMoney(pendingPayables), fontSize = 12,
                    color = Theme.COLORS.WARNING or Theme.COLORS.DANGER },
            },
        })
    end
    table.insert(budgetRows, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        children = {
            UI.Label { text = "???????/??", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
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

    -- ????
    table.insert(children, UI.Label { text = "???????", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
        children = { bidField },
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10,
        children = bidPresetBtns,
    })

    -- ????
    table.insert(children, UI.Label { text = "????", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 })
    for _, btn in ipairs(clauseBtns) do
        table.insert(children, btn)
    end

    -- ????
    table.insert(children, UI.Label { text = "??????/??", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginTop = 10, marginBottom = 4 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
        children = { wageField },
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10,
        children = wagePresetBtns,
    })

    -- ????
    table.insert(children, UI.Label { text = "????", fontSize = 13, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6 })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        children = yearsBtns,
    })

    -- ????
    local submitBtn = UI.Button {
        text = "????",
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
                    and string.format("????????? %s????????? %s?",
                        FinanceManager.formatMoney(budget), FinanceManager.formatMoney(pendingPayables))
                    or ("???????????: " .. FinanceManager.formatMoney(budget))
                UI.Toast.Show({ message = hint, variant = "error" })
                return
            end

            -- ??????????????????????
            if wageBudget > 0 and (currentWage + offeredWage) > wageBudget then
                AudioManager.deny()
                UI.Toast.Show({
                    message = string.format("???????????? %s ????? %s???????????????",
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
                UI.Toast.Show({ message = "?????", variant = "success" })
            else
                if not TransferLimitDialog.handleError(bidErr, player.displayName, gameState) then
                    AudioManager.deny()
                    UI.Toast.Show({ message = bidErr or "????", variant = "error" })
                end
            end
            BottomSheet.close()
            Router.replaceWith("market", { tab = "my_bids" })
        end,
    }

    BottomSheet.showCustom({
        title = "???? ? " .. player.displayName,
        height = 680,
        showCancel = true,
        children = children,
        footer = submitBtn,
    })
end

return Tab
