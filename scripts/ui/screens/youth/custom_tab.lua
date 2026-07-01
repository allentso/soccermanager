-- ui/screens/youth/custom_tab.lua
-- 自定义球员标签页，从 youth.lua 拆分。

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

function Tab._watchAdForCustomCreate(gameState, defaultNat)
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            YouthManager.unlockNextCustomYouthCreate(gameState)
            SaveManager.save(gameState, "auto")
            collectgarbage("collect")
            UI.Toast.Show({ message = "已解锁下一名自建球员创建资格", variant = "success" })
            _youth()._setCustomCreatePos("ST")
            _youth()._setCustomCreateNat(Nationality.normalize(defaultNat or "ENG"))
            Tab._showCreateCustomModal(gameState, defaultNat)
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

function Tab._watchAdForCustomPaBoost(player, gameState)
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local ok, boost = YouthManager.boostCustomYouthPa(gameState, player)
            if ok then
                SaveManager.save(gameState, "auto")
                collectgarbage("collect")
                UI.Toast.Show({
                    message = string.format("PA %.1f → %.1f", boost.oldRating, boost.newRating),
                    variant = "success",
                })
                Router.replaceWith("youth", { tab = "custom" })
            else
                UI.Toast.Show({ message = boost or "提升失败", variant = "warning" })
            end
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

------------------------------------------------------
-- 自建球员
------------------------------------------------------

function Tab._buildCustomPlayerRow(player, gameState)
    local posColor = Theme.posColor(player.position)
    local effectivePot = player.actualPotential or player.potential or 0
    local scoutAccuracy = _youth()._getTeamScoutAccuracy(gameState)
    local _, potStarText = _youth()._getPotentialStars(effectivePot, scoutAccuracy)
    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0
    local paRating = player.paRating or PotentialSystem.rawToRating(player.potential or player.actualPotential or 60)
    local atCap = paRating >= 10.0

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                alignItems = "center",
                onClick = function()
                    _youth()._showYouthActions(player, gameState)
                end,
                children = {
                    UI.Panel {
                        backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                        borderRadius = 3,
                        paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                        marginRight = 8,
                        flexShrink = 0,
                        children = {
                            UI.Label {
                                text = Constants.POSITION_NAMES[player.position] or player.position,
                                fontSize = 10, color = posColor, fontWeight = "bold",
                            },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = player.displayName or (player.firstName .. " " .. player.lastName),
                                fontSize = 13,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = string.format(
                                    "%d岁 | 能力%d | 潜力%s | PA %.1f%s%s",
                                    age,
                                    math.min(Constants.ABILITY_MAX, player.overall or 0),
                                    potStarText,
                                    paRating,
                                    player.isCustomYouth and not player.isYouth and " | 一线队" or "",
                                    player.listedForSale and " | 挂牌中" or ""
                                ),
                                fontSize = 11,
                                color = player.listedForSale and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
                            },
                        },
                    },
                },
            },
            UI.Button {
                text = atCap and "PA已满" or string.format("看广告 +%.1f", 0.5),
                width = 78,
                height = 32,
                flexShrink = 0,
                marginLeft = 8,
                paddingLeft = 6,
                paddingRight = 6,
                backgroundColor = atCap and Theme.COLORS.BG_SURFACE or Theme.COLORS.ACCENT,
                borderRadius = 8,
                fontSize = 10,
                fontWeight = "bold",
                color = atCap and Theme.COLORS.TEXT_MUTED or Theme.COLORS.TEXT_PRIMARY,
                disabled = atCap,
                onClick = function()
                    if atCap then
                        UI.Toast.Show({ message = "该球员潜力已达到上限", variant = "info" })
                    else
                        Tab._watchAdForCustomPaBoost(player, gameState)
                    end
                end,
            },
        },
    }
end

function Tab.build(customSquad, gameState)
    local maxCustom = YouthManager.getMaxCustomYouthSlots()
    local canCreate, createReason = YouthManager.canCreateCustomYouthPlayer(gameState)
    local isFull = #customSquad >= maxCustom
    local needsAd = (not canCreate) and (not isFull)
    local playerTeam = gameState:getPlayerTeam()
    local defaultNat = playerTeam and playerTeam.country or "ENG"

    local rows = {}
    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 4,
        children = {
            Theme.Subtitle {
                text = string.format("自建球员 (%d/%d)", #customSquad, maxCustom),
                marginBottom = 0,
            },
            UI.Button {
                text = isFull and "名额已满" or (needsAd and "看广告创建" or "创建球员"),
                height = 30,
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = isFull and Theme.COLORS.BG_SURFACE or (needsAd and Theme.COLORS.ACCENT or Theme.COLORS.SECONDARY),
                borderRadius = 15,
                fontSize = 12,
                color = isFull and Theme.COLORS.TEXT_MUTED or Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                disabled = isFull,
                onClick = function()
                    if canCreate then
                        _youth()._setCustomCreatePos("ST")
                        _youth()._setCustomCreateNat(Nationality.normalize(defaultNat))
                        Tab._showCreateCustomModal(gameState, defaultNat)
                    elseif needsAd then
                        Tab._watchAdForCustomCreate(gameState, defaultNat)
                    else
                        UI.Toast.Show({ message = createReason or "暂时无法创建", variant = "warning" })
                    end
                end,
            },
        },
    })
    table.insert(rows, UI.Label {
        text = string.format(
            "最多创建 %d 名专属青训；首名免费，之后每次创建前需观看 1 次广告；自建球员可通过广告提升 PA（每次 +0.5）",
            maxCustom
        ),
        fontSize = 10,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 8,
    })

    if #customSquad == 0 then
        table.insert(rows, UI.Label {
            text = "还没有自建球员，点击右上角创建你的第一位专属新星。",
            fontSize = 13,
            color = Theme.COLORS.TEXT_MUTED,
            marginTop = 8,
        })
    else
        for _, player in ipairs(customSquad) do
            table.insert(rows, Tab._buildCustomPlayerRow(player, gameState))
        end
    end

    return Theme.Card { children = rows }
end

function Tab._showCreateCustomModal(gameState, defaultNat)
    if not _youth()._getCustomCreateNat() then
        _youth()._setCustomCreateNat(Nationality.normalize(defaultNat or "ENG"))
    end

    local youthMods = DifficultySettings.getYouthModifiers()
    local selectedNatName = ScoutManager.getNationName(_youth()._getCustomCreateNat()) or _youth()._getCustomCreateNat()

    local function cycleCustomPos(delta)
        local idx = 1
        for i, pos in ipairs(_youth().CUSTOM_POSITION_OPTIONS) do
            if pos == _youth()._getCustomCreatePos() then
                idx = i
                break
            end
        end
        idx = ((idx - 1 + delta) % #_youth().CUSTOM_POSITION_OPTIONS) + 1
        _youth()._setCustomCreatePos(_youth().CUSTOM_POSITION_OPTIONS[idx])
    end

    local function reopenModal()
        UI.CloseOverlay()
        Tab._showCreateCustomModal(gameState, defaultNat)
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 190},
        children = {
            UI.Panel {
                width = "90%",
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Theme.COLORS.BORDER_LIGHT,
                paddingTop = 18,
                paddingBottom = 18,
                paddingLeft = 16,
                paddingRight = 16,
                children = {
                    UI.Label {
                        text = "创建自建球员",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = string.format(
                            "%d–%d岁 · 潜力/能力随俱乐部青训设施随机 · 占用 1 个自建名额",
                            youthMods.minAge or 16,
                            youthMods.maxAge or 18
                        ),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 14,
                    },
                    UI.Label {
                        text = "球员姓名",
                        fontSize = 12,
                        color = Theme.COLORS.GOLD,
                        marginBottom = 6,
                        fontWeight = "bold",
                    },
                    UI.TextField {
                        id = "customYouthName",
                        width = "100%",
                        height = 42,
                        placeholder = string.format("最多%d字", YouthManager.getMaxCustomYouthNameChars()),
                        maxLength = YouthManager.getCustomYouthNameInputLimit(),
                        fontSize = 14,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 10,
                        borderWidth = 1,
                        borderColor = Theme.COLORS.BORDER,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginBottom = 14,
                        paddingLeft = 12,
                    },
                    UI.Label {
                        text = "国籍",
                        fontSize = 12,
                        color = Theme.COLORS.GOLD,
                        marginBottom = 6,
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        marginBottom = 14,
                        children = {
                            UI.Button {
                                text = "‹",
                                width = 36,
                                height = 36,
                                borderRadius = 18,
                                backgroundColor = Theme.COLORS.BG_SURFACE,
                                fontSize = 18,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginRight = 12,
                                onClick = function()
                                    _youth()._cycleCustomNation(-1)
                                    reopenModal()
                                end,
                            },
                            UI.Panel {
                                minWidth = 96,
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = selectedNatName,
                                        fontSize = 15,
                                        color = Theme.COLORS.TEXT_PRIMARY,
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = _youth()._getCustomCreateNat(),
                                        fontSize = 10,
                                        color = Theme.COLORS.TEXT_MUTED,
                                        marginTop = 2,
                                    },
                                },
                            },
                            UI.Button {
                                text = "›",
                                width = 36,
                                height = 36,
                                borderRadius = 18,
                                backgroundColor = Theme.COLORS.BG_SURFACE,
                                fontSize = 18,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginLeft = 12,
                                onClick = function()
                                    _youth()._cycleCustomNation(1)
                                    reopenModal()
                                end,
                            },
                        },
                    },
                    UI.Label {
                        text = "场上位置",
                        fontSize = 12,
                        color = Theme.COLORS.GOLD,
                        marginBottom = 6,
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        marginBottom = 16,
                        children = {
                            UI.Button {
                                text = "‹",
                                width = 36,
                                height = 36,
                                borderRadius = 18,
                                backgroundColor = Theme.COLORS.BG_SURFACE,
                                fontSize = 18,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginRight = 12,
                                onClick = function()
                                    cycleCustomPos(-1)
                                    reopenModal()
                                end,
                            },
                            UI.Panel {
                                minWidth = 88,
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = Constants.POSITION_NAMES[_youth()._getCustomCreatePos()] or _youth()._getCustomCreatePos(),
                                        fontSize = 16,
                                        color = Theme.COLORS.TEXT_PRIMARY,
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = _youth()._getCustomCreatePos(),
                                        fontSize = 10,
                                        color = Theme.COLORS.TEXT_MUTED,
                                        marginTop = 2,
                                    },
                                },
                            },
                            UI.Button {
                                text = "›",
                                width = 36,
                                height = 36,
                                borderRadius = 18,
                                backgroundColor = Theme.COLORS.BG_SURFACE,
                                fontSize = 18,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginLeft = 12,
                                onClick = function()
                                    cycleCustomPos(1)
                                    reopenModal()
                                end,
                            },
                        },
                    },
                    UI.Button {
                        text = "确认创建",
                        width = "100%",
                        height = 42,
                        backgroundColor = Theme.COLORS.SECONDARY,
                        borderRadius = 10,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginBottom = 8,
                        onClick = function()
                            local nameField = UI.FindById("customYouthName")
                            local displayName = nameField and nameField:GetText() or ""
                            local ok, result = YouthManager.createCustomYouthPlayer(gameState, {
                                displayName = displayName,
                                position = _youth()._getCustomCreatePos(),
                                nationality = _youth()._getCustomCreateNat(),
                            })
                            if ok then
                                SaveManager.save(gameState, "auto")
                                UI.CloseOverlay()
                                _youth()._setCustomCreateNat(nil)
                                UI.Toast.Show({
                                    message = (result.displayName or displayName) .. " 已加入自建球员",
                                    variant = "success",
                                })
                                Router.replaceWith("youth", { tab = "custom" })
                            else
                                UI.Toast.Show({
                                    message = result or "创建失败",
                                    variant = "error",
                                })
                            end
                        end,
                    },
                    UI.Button {
                        text = "取消",
                        width = "100%",
                        height = 36,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 10,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            UI.CloseOverlay()
                            _youth()._setCustomCreateNat(nil)
                        end,
                    },
                },
            },
        },
    })
end

return Tab
