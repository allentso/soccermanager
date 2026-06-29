-- ui/screens/staff.lua
-- 职员管理页面：展示当前职员、加成概览、雇佣/解约操作

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local StaffManager = require("scripts/systems/staff_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")


local StaffPage = {}

-- 职员角色颜色
local ROLE_COLORS = {
    assistant = {102, 178, 255, 255},  -- 蓝
    coach     = {102, 255, 128, 255},  -- 绿
    scout     = {255, 204, 0, 255},    -- 金
    physio    = {255, 128, 230, 255},  -- 粉
}

-- 属性展示映射
local ATTR_LABELS = {
    training = "训练",
    tactical = "战术",
    scouting = "球探",
    physiotherapy = "理疗",
    youthDev = "青训",
}

------------------------------------------------------
-- 主界面
------------------------------------------------------
function StaffPage.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local team = gameState:getPlayerTeam()
    if not team then return UI.Panel { width = "100%", height = "100%" } end

    -- 获取球队职员
    local staffDetails = StaffManager.getTeamStaffDetails(gameState, team.id)
    local effects = StaffManager.getTeamEffectSnapshot(gameState, team.id)
    local hints = StaffManager.getRoleMixHints(gameState, team.id)

    local bonusSummary = StaffPage._buildBonusSummary(effects, hints)

    local staffCards = {}
    for _, detail in ipairs(staffDetails) do
        table.insert(staffCards, StaffPage._buildStaffCard(detail.staff, detail.contribution, gameState))
    end

    -- 空位提示
    local maxStaff = StaffManager.MAX_STAFF_PER_TEAM
    local currentCount = #staffDetails
    if currentCount < maxStaff then
        table.insert(staffCards, UI.Button {
            text = string.format("+ 招聘职员 (%d/%d)", currentCount, maxStaff),
            width = "100%", height = 48,
            backgroundColor = {38, 46, 71, 200},
            borderRadius = 10,
            borderWidth = 1, borderColor = {160, 130, 40, 100},
            fontSize = 14,
            color = Theme.COLORS.GOLD,
            marginBottom = 8,
            onClick = function()
                Router.navigate("staff_hire")
            end,
        })
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
                        text = "返回",
                        width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "职员管理",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Label {
                        text = string.format("%d/%d人", currentCount, maxStaff),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 50, textAlign = "right",
                    },
                }
            },

            -- 二级导航
            Theme.SquadSubNav("staff"),

            -- 加成概览
            bonusSummary,

            -- 职员列表
            UI.ScrollView {
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                scrollY = true,
                bounceEnabled = false,
                padding = 10,
                children = staffCards,
            },

            -- 底部导航
            Theme.MainNav("squad"),
        }
    }
end

------------------------------------------------------
-- 加成概览栏
------------------------------------------------------
function StaffPage._buildBonusSummary(effects, hints)
    local hintChildren = {}
    for _, hint in ipairs(hints or {}) do
        table.insert(hintChildren, UI.Label {
            text = "· " .. hint,
            fontSize = 10, color = Theme.COLORS.WARNING,
            marginBottom = 2,
        })
    end

    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = Theme.COLORS.BG_CARD,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = "团队效果",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                marginBottom = 4,
            },
            UI.Panel {
                width = "100%",
                flexWrap = "wrap",
                children = {
                    StaffPage._effectPill(effects.trainingLabel),
                    StaffPage._effectPill(effects.scoutingLabel),
                    StaffPage._effectPill(effects.injuryLabel),
                    StaffPage._effectPill(effects.youthLabel),
                    StaffPage._effectPill(effects.tacticalLabel),
                },
            },
            #hintChildren > 0 and UI.Panel {
                width = "100%", marginTop = 6,
                children = hintChildren,
            } or UI.Panel { width = 0, height = 0 },
        }
    }
end

function StaffPage._effectPill(text)
    return UI.Label {
        text = text,
        fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
        marginRight = 10, marginBottom = 4,
    }
end

------------------------------------------------------
-- 职员卡片
------------------------------------------------------
function StaffPage._buildStaffCard(staff, contribution, gameState)
    local roleName = Constants.STAFF_ROLE_NAMES[staff.role] or staff.role
    local roleColor = ROLE_COLORS[staff.role] or Theme.COLORS.TEXT_SECONDARY

    -- 核心属性（只展示该角色相关的前3项）
    local attrItems = StaffPage._getRelevantAttrs(staff)

    local attrChildren = {}
    for _, item in ipairs(attrItems) do
        table.insert(attrChildren, UI.Panel {
            flexDirection = "row", alignItems = "center",
            marginRight = 10,
            children = {
                UI.Label { text = item.label, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginRight = 3 },
                UI.Label {
                    text = tostring(item.value),
                    fontSize = 11, fontWeight = "bold",
                    color = item.value >= 15 and Theme.COLORS.SECONDARY
                        or (item.value >= 10 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY),
                },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 10,
        padding = 12,
        marginBottom = 8,
        children = {
            -- 第一行：名字 + 角色 + 工资
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 6,
                children = {
                    -- 角色标签
                    UI.Panel {
                        backgroundColor = roleColor,
                        borderRadius = 4,
                        paddingLeft = 6, paddingRight = 6,
                        height = 18,
                        justifyContent = "center", alignItems = "center",
                        marginRight = 8,
                        children = {
                            UI.Label { text = roleName, fontSize = 10, color = {20, 20, 30, 255}, fontWeight = "bold" },
                        }
                    },
                    -- 名字
                    UI.Label {
                        text = staff.displayName,
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1,
                    },
                    -- 周薪
                    UI.Label {
                        text = FinanceManager.formatMoney(staff.wage) .. "/周",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
            -- 第二行：贡献描述
            UI.Label {
                text = contribution ~= "" and contribution or "无特殊加成",
                fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 6,
            },
            -- 第三行：属性值 + 操作按钮
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Panel { flexDirection = "row", flexGrow = 1, flexShrink = 1, children = attrChildren },
                    -- 解约按钮
                    UI.Button {
                        text = "解约",
                        height = 28, paddingLeft = 10, paddingRight = 10,
                        backgroundColor = {60, 30, 30, 200},
                        borderRadius = 6,
                        fontSize = 11, color = Theme.COLORS.DANGER,
                        onClick = function()
                            StaffPage._confirmFire(staff, gameState)
                        end,
                    },
                }
            },
        }
    }
end

--- 获取角色相关属性（前3-4项）
function StaffPage._getRelevantAttrs(staff)
    local attrs = staff.attributes or {}
    local items = {}

    if staff.role == "assistant" then
        table.insert(items, {label = "训练", value = attrs.training or 0})
        table.insert(items, {label = "战术", value = attrs.tactical or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
    elseif staff.role == "coach" then
        table.insert(items, {label = "训练", value = attrs.training or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
        table.insert(items, {label = "战术", value = attrs.tactical or 0})
    elseif staff.role == "scout" then
        table.insert(items, {label = "球探", value = attrs.scouting or 0})
        table.insert(items, {label = "战术", value = attrs.tactical or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
    elseif staff.role == "physio" then
        table.insert(items, {label = "理疗", value = attrs.physiotherapy or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
        table.insert(items, {label = "训练", value = attrs.training or 0})
    else
        table.insert(items, {label = "训练", value = attrs.training or 0})
        table.insert(items, {label = "球探", value = attrs.scouting or 0})
    end

    return items
end

------------------------------------------------------
-- 解约确认
------------------------------------------------------
function StaffPage._confirmFire(staff, gameState)
    local compensation = staff.wage * 4
    local team = gameState:getPlayerTeam()
    local balanceAfter = (team and team.balance or 0) - compensation

    ConfirmDialog.showWithDetails({
        title = "解约 - " .. staff.displayName,
        details = {
            { label = "职位", value = Constants.STAFF_ROLE_NAMES[staff.role] or staff.role },
            { label = "当前周薪", value = FinanceManager.formatMoney(staff.wage) },
            { label = "解约补偿", value = FinanceManager.formatMoney(compensation), valueColor = Theme.COLORS.DANGER },
            { label = "解约后余额", value = FinanceManager.formatMoney(balanceAfter),
              valueColor = balanceAfter < 0 and Theme.COLORS.DANGER or Theme.COLORS.TEXT_PRIMARY },
        },
        confirmText = "确认解约",
        danger = true,
        onConfirm = function()
            local ok, err = StaffManager.fire(gameState, gameState.playerTeamId, staff.id)
            if ok then
                Router.replaceWith("staff")
            else
                ConfirmDialog.show({
                    title = "解约失败",
                    message = err or "操作失败",
                    confirmText = "知道了",
                    onConfirm = function() end,
                })
            end
        end,
    })
end



return StaffPage
