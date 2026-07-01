-- ui/screens/youth/recruit_tab.lua
-- 候选人招募标签页，从 youth.lua 拆分。

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
local sdk = sdk
local function _youth() return require("scripts/ui/screens/youth") end

local Tab = {}

function Tab.build(candidates, gameState)
    if #candidates == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "候选球员" },
                UI.Label {
                    text = "暂无候选球员，球探每月会发现新的青年球员。",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 8,
                },
            },
        }
    end

    local rows = {}
    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 4,
        children = {
            Theme.Subtitle { text = "候选球员", marginBottom = 0 },
            UI.Button {
                text = string.format("一键签入 %d", #candidates),
                height = 30,
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 15,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                onClick = function()
                    _youth()._signAllCandidates(candidates, gameState)
                end,
            },
        },
    })
    -- 球探偏差提示
    table.insert(rows, UI.Label {
        text = "* 数据为球探预估，签入后实际能力可能略有偏差",
        fontSize = 10,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 8,
    })

    for i, candidate in ipairs(candidates) do
        table.insert(rows, Tab._buildCandidateCard(candidate, i, gameState))
    end

    return Theme.Card { children = rows }
end

function Tab._buildCandidateCard(candidate, index, gameState)
    local posColor = Theme.posColor(candidate.position)

    -- 潜力星级
    local scoutAccuracy = _youth()._getTeamScoutAccuracy(gameState)
    local potStars, potStarText = _youth()._getPotentialStars(candidate.potential, scoutAccuracy)
    local potColor = Theme.COLORS.TEXT_MUTED
    if potStars >= 4 then potColor = Theme.COLORS.ACCENT
    elseif potStars >= 3 then potColor = Theme.COLORS.SECONDARY
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 位置徽章（与阵容页统一样式）
            UI.Panel {
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[candidate.position] or candidate.position,
                        fontSize = 10, color = posColor, fontWeight = "bold",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = candidate.displayName,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("%d岁 | %s | 能力%d",
                            candidate.age,
                            ScoutManager.getNationName(candidate.nationality) or "?",
                            candidate.overall),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 潜力星级
            UI.Panel {
                alignItems = "center",
                marginRight = 10,
                children = {
                    UI.Label {
                        text = potStarText,
                        fontSize = 12,
                        color = potColor,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "潜力",
                        fontSize = 9,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 签入按钮
            UI.Button {
                text = "签入",
                width = 52,
                height = 28,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 6,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                onClick = function()
                    Tab._confirmSign(candidate, index, gameState)
                end,
            },
        },
    }
end

------------------------------------------------------
-- 签入确认
------------------------------------------------------
function Tab._confirmSign(candidate, index, gameState)
    local scoutAccuracy = _youth()._getTeamScoutAccuracy(gameState)
    local _, potStarText = _youth()._getPotentialStars(candidate.potential, scoutAccuracy)
    local team = gameState.teams[gameState.playerTeamId]
    local previewPlayer = {
        overall = candidate.overall,
        potential = candidate.potential,
        actualPotential = candidate.potential,
        birthYear = gameState.date.year - (candidate.age or 16),
        position = candidate.position,
    }
    local wagePreview = FinanceManager.estimateYouthAcademyWage(previewPlayer, team, gameState)
    ConfirmDialog.showWithDetails({
        title = "签入青训球员",
        details = {
            { label = "姓名", value = candidate.displayName },
            { label = "位置", value = Constants.POSITION_NAMES[candidate.position] or candidate.position },
            { label = "年龄", value = tostring(candidate.age) .. "岁" },
            { label = "能力", value = tostring(candidate.overall) },
            { label = "潜力", value = potStarText, valueColor = Theme.COLORS.ACCENT },
            { label = "周薪", value = FinanceManager.formatMoney(wagePreview) },
            { label = "合同", value = "3年" },
        },
        confirmText = "确认签入",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, err = YouthManager.signCandidate(gameState, index)
            if ok then
                SaveManager.save(gameState, "auto")
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "签入失败",
                    message = err or "无法签入该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end


return Tab
