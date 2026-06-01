-- ui/screens/sponsor_select.lua
-- 赞助合同选择屏幕（赛季初阻断事件）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local FinanceManager = require("scripts/systems/finance_manager")

local SponsorSelect = {}

------------------------------------------------------
-- 工具函数
------------------------------------------------------
local function formatMoney(amount)
    return FinanceManager.formatMoney(amount)
end

local function tagColor(tag)
    if tag == "stable" then
        return {60, 180, 100, 255}
    elseif tag == "balanced" then
        return {200, 160, 40, 255}
    else
        return {220, 80, 60, 255}
    end
end

------------------------------------------------------
-- 创建页面
------------------------------------------------------
function SponsorSelect.create(params)
    local gameState = _G.gameState
    local team = gameState:getPlayerTeam()
    local offers = team and team.pendingSponsorOffers or {}

    -- 当前选择（每种类型默认选中第1个）
    local selections = { primary = 1, kit = 1, sleeve = 1 }

    -- 各类型的选项卡片引用（用于高亮选中态）
    local cardRefs = { primary = {}, kit = {}, sleeve = {} }

    -- 底部合计标签引用
    local totalLabel = nil
    local confirmBtn = nil

    -- 计算当前合计月收入
    local function calcTotal()
        local sum = 0
        for sType, idx in pairs(selections) do
            local typeOffers = offers[sType]
            if typeOffers and typeOffers[idx] then
                sum = sum + typeOffers[idx].monthlyAmount
            end
        end
        return sum
    end

    -- 刷新选中态高亮
    local function refreshHighlight(sType)
        for i, card in ipairs(cardRefs[sType]) do
            if i == selections[sType] then
                card:SetBackgroundColor(Theme.COLORS.PRIMARY[1], Theme.COLORS.PRIMARY[2], Theme.COLORS.PRIMARY[3], 40)
                card:SetBorderColor(Theme.COLORS.PRIMARY)
            else
                card:SetBackgroundColor(Theme.COLORS.BG_CARD[1], Theme.COLORS.BG_CARD[2], Theme.COLORS.BG_CARD[3], 255)
                card:SetBorderColor(Theme.COLORS.BORDER)
            end
        end
        -- 更新合计
        if totalLabel then
            totalLabel:SetText(string.format("合计月收入: %s/月", formatMoney(calcTotal())))
        end
    end

    -- 构建单个赞助类型选择区域
    local function buildTypeSection(sType)
        local typeOffers = offers[sType] or {}
        if #typeOffers == 0 then return UI.Panel { height = 0 } end

        local typeLabel = typeOffers[1] and typeOffers[1].typeLabel or sType
        local optionCards = {}

        for i, offer in ipairs(typeOffers) do
            local isSelected = (selections[sType] == i)
            local tColor = tagColor(offer.tag)

            local card = UI.Panel {
                width = "100%",
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 12, paddingRight = 12,
                marginBottom = 8,
                backgroundColor = isSelected
                    and {Theme.COLORS.PRIMARY[1], Theme.COLORS.PRIMARY[2], Theme.COLORS.PRIMARY[3], 40}
                    or Theme.COLORS.BG_CARD,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = isSelected and Theme.COLORS.PRIMARY or Theme.COLORS.BORDER,
                onClick = function()
                    selections[sType] = i
                    refreshHighlight(sType)
                end,
                children = {
                    -- 第一行：品牌 + 标签
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        marginBottom = 6,
                        children = {
                            UI.Label {
                                text = offer.brand,
                                fontSize = 14,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                                flexGrow = 1,
                            },
                            UI.Panel {
                                paddingLeft = 6, paddingRight = 6,
                                paddingTop = 2, paddingBottom = 2,
                                backgroundColor = tColor,
                                borderRadius = 4,
                                children = {
                                    UI.Label {
                                        text = offer.profileLabel,
                                        fontSize = 10,
                                        color = {255, 255, 255, 255},
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 第二行：金额明细
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label {
                                text = string.format("%s/月", formatMoney(offer.monthlyAmount)),
                                fontSize = 13,
                                color = Theme.COLORS.SUCCESS,
                                marginRight = 12,
                            },
                            UI.Label {
                                text = offer.topFinishBonus > 0
                                    and string.format("前3奖金+%s", formatMoney(offer.topFinishBonus))
                                    or "无绩效奖金",
                                fontSize = 11,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                marginRight = 12,
                            },
                            UI.Label {
                                text = offer.relegationPenalty > 0
                                    and string.format("降级罚-%s", formatMoney(offer.relegationPenalty))
                                    or "无罚款",
                                fontSize = 11,
                                color = offer.relegationPenalty > 0 and Theme.COLORS.DANGER or Theme.COLORS.TEXT_MUTED,
                            },
                        },
                    },
                    -- 第三行：描述
                    UI.Label {
                        text = offer.desc,
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            }

            cardRefs[sType][i] = card
            table.insert(optionCards, card)
        end

        return UI.Panel {
            width = "100%",
            marginBottom = 16,
            children = {
                -- 类型标题
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    marginBottom = 8,
                    children = {
                        UI.Panel {
                            width = 4, height = 16,
                            backgroundColor = Theme.COLORS.PRIMARY,
                            borderRadius = 2,
                            marginRight = 8,
                        },
                        UI.Label {
                            text = typeLabel,
                            fontSize = 14,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                    },
                },
                table.unpack(optionCards),
            },
        }
    end

    -- 底部合计 + 确认按钮
    totalLabel = UI.Label {
        text = string.format("合计月收入: %s/月", formatMoney(calcTotal())),
        fontSize = 15,
        color = Theme.COLORS.SUCCESS,
        fontWeight = "bold",
    }

    confirmBtn = UI.Button {
        text = "确认签约",
        width = "100%",
        height = 44,
        backgroundColor = Theme.COLORS.PRIMARY,
        borderRadius = 10,
        fontSize = 15,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginTop = 10,
        onClick = function()
            local ok = FinanceManager.acceptSponsorContract(gameState, selections)
            if ok then
                UI.Toast.Show("赞助合同已签署！", "success")
                Router.navigate("dashboard")
            end
        end,
    }

    -- 构建主页面
    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar({ title = "赛季赞助签约" }),

            -- 赛季说明
            UI.Panel {
                width = "100%",
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 10, paddingBottom = 8,
                children = {
                    UI.Label {
                        text = string.format("第 %d 赛季 · 选择每个类型的赞助方案", gameState.season or 1),
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_SECONDARY,
                    },
                },
            },

            -- 滚动内容
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                scrollY = true,
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 4, paddingBottom = 16,
                children = {
                    buildTypeSection("primary"),
                    buildTypeSection("kit"),
                    buildTypeSection("sleeve"),
                },
            },

            -- 底部固定区域
            UI.Panel {
                width = "100%",
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 12, paddingBottom = 16,
                backgroundColor = Theme.COLORS.BG_CARD,
                borderTopWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = {
                    totalLabel,
                    confirmBtn,
                },
            },
        },
    }

    return page
end

return SponsorSelect
