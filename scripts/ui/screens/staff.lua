-- ui/screens/staff.lua
-- 职员管理页面：展示当前职员、加成概览、雇佣/解约操作

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local StaffManager = require("scripts/systems/staff_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

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
    motivation = "激励",
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
    local bonuses = StaffManager.getTeamBonuses(gameState, team.id)

    -- 总加成栏
    local bonusSummary = StaffPage._buildBonusSummary(bonuses)

    -- 职员卡片列表
    local staffCards = {}
    for _, detail in ipairs(staffDetails) do
        table.insert(staffCards, StaffPage._buildStaffCard(detail.staff, detail.contribution, gameState))
    end

    -- 空位提示
    local maxStaff = 6
    local currentCount = #staffDetails
    if currentCount < maxStaff then
        table.insert(staffCards, UI.Button {
            text = string.format("+ 招聘职员 (%d/%d)", currentCount, maxStaff),
            width = "100%", height = 48,
            backgroundColor = {38, 46, 71, 200},
            borderRadius = 10,
            borderWidth = 1, borderColor = {77, 140, 255, 100},
            fontSize = 14,
            color = Theme.COLORS.PRIMARY,
            marginBottom = 8,
            onClick = function()
                StaffPage._showHireMenu(gameState, team)
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
                        onClick = function() Router.navigate("dashboard") end,
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
                flexBasis = 0,
                scrollY = true,
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
function StaffPage._buildBonusSummary(bonuses)
    return UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = Theme.COLORS.BG_CARD,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = "团队加成",
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                marginBottom = 4,
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                children = {
                    StaffPage._bonusPill("训练", bonuses.training, 30),
                    StaffPage._bonusPill("球探", bonuses.scouting, 10),
                    StaffPage._bonusPill("康复", bonuses.physio, 10),
                    StaffPage._bonusPill("青训", bonuses.youthDev, 9),
                    StaffPage._bonusPill("激励", bonuses.motivation, 12),
                },
            },
        }
    }
end

function StaffPage._bonusPill(label, value, maxVal)
    local pct = math.min(100, math.floor(value / math.max(1, maxVal) * 100))
    local color = Theme.COLORS.TEXT_MUTED
    if pct >= 70 then color = Theme.COLORS.SECONDARY
    elseif pct >= 40 then color = Theme.COLORS.ACCENT
    end

    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        marginRight = 12, marginBottom = 4,
        children = {
            UI.Label { text = label, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginRight = 4 },
            UI.Label { text = string.format("+%d", math.floor(value)), fontSize = 12, color = color, fontWeight = "bold" },
        }
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
        table.insert(items, {label = "激励", value = attrs.motivation or 0})
        table.insert(items, {label = "战术", value = attrs.tactical or 0})
    elseif staff.role == "coach" then
        table.insert(items, {label = "训练", value = attrs.training or 0})
        table.insert(items, {label = "激励", value = attrs.motivation or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
    elseif staff.role == "scout" then
        table.insert(items, {label = "球探", value = attrs.scouting or 0})
        table.insert(items, {label = "战术", value = attrs.tactical or 0})
        table.insert(items, {label = "激励", value = attrs.motivation or 0})
    elseif staff.role == "physio" then
        table.insert(items, {label = "理疗", value = attrs.physiotherapy or 0})
        table.insert(items, {label = "青训", value = attrs.youthDev or 0})
        table.insert(items, {label = "激励", value = attrs.motivation or 0})
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

    ConfirmDialog.showWithDetails({
        title = "解约 - " .. staff.displayName,
        details = {
            { label = "职位", value = Constants.STAFF_ROLE_NAMES[staff.role] or staff.role },
            { label = "当前周薪", value = FinanceManager.formatMoney(staff.wage) },
            { label = "解约补偿", value = FinanceManager.formatMoney(compensation), valueColor = Theme.COLORS.DANGER },
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

------------------------------------------------------
-- 招聘菜单
------------------------------------------------------
function StaffPage._showHireMenu(gameState, team)
    -- 按角色筛选的招聘列表
    local items = {
        { label = "全部可用职员", action = function() StaffPage._showHireList(gameState, team, nil) end },
        { label = "助理教练", color = ROLE_COLORS.assistant, action = function() StaffPage._showHireList(gameState, team, "assistant") end },
        { label = "教练", color = ROLE_COLORS.coach, action = function() StaffPage._showHireList(gameState, team, "coach") end },
        { label = "球探", color = ROLE_COLORS.scout, action = function() StaffPage._showHireList(gameState, team, "scout") end },
        { label = "理疗师", color = ROLE_COLORS.physio, action = function() StaffPage._showHireList(gameState, team, "physio") end },
    }

    BottomSheet.show({
        title = "招聘职员",
        subtitle = "选择类型查看可用人选",
        items = items,
    })
end

------------------------------------------------------
-- 招聘列表（自由职员市场）
------------------------------------------------------
function StaffPage._showHireList(gameState, team, roleFilter)
    local freeStaff = StaffManager.getFreeStaff(gameState, roleFilter)

    -- 按综合属性排序
    table.sort(freeStaff, function(a, b)
        local avgA = StaffPage._avgAttr(a)
        local avgB = StaffPage._avgAttr(b)
        return avgA > avgB
    end)

    if #freeStaff == 0 then
        ConfirmDialog.show({
            title = "暂无可用职员",
            message = roleFilter and ("当前没有可签约的" .. (Constants.STAFF_ROLE_NAMES[roleFilter] or "")) or "当前没有可签约的职员",
            confirmText = "知道了",
            onConfirm = function() end,
        })
        return
    end

    -- 构建列表内容
    local listItems = {}
    for _, s in ipairs(freeStaff) do
        local roleName = Constants.STAFF_ROLE_NAMES[s.role] or s.role
        local roleColor = ROLE_COLORS[s.role] or Theme.COLORS.TEXT_SECONDARY
        local avgAttr = StaffPage._avgAttr(s)
        local fee = s.wage * 4

        local attrItems = StaffPage._getRelevantAttrs(s)
        local attrText = {}
        for _, a in ipairs(attrItems) do
            table.insert(attrText, a.label .. a.value)
        end

        table.insert(listItems, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 10, paddingBottom = 10,
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                -- 左侧信息
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", marginBottom = 2,
                            children = {
                                UI.Panel {
                                    backgroundColor = roleColor, borderRadius = 3,
                                    paddingLeft = 4, paddingRight = 4, height = 16,
                                    justifyContent = "center", alignItems = "center",
                                    marginRight = 6,
                                    children = {
                                        UI.Label { text = roleName, fontSize = 9, color = {20, 20, 30, 255}, fontWeight = "bold" },
                                    }
                                },
                                UI.Label {
                                    text = s.displayName,
                                    fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                },
                            }
                        },
                        UI.Label {
                            text = table.concat(attrText, " | "),
                            fontSize = 10, color = Theme.COLORS.TEXT_SECONDARY,
                            marginTop = 2,
                        },
                        UI.Label {
                            text = string.format("周薪 %s · 签约费 %s",
                                FinanceManager.formatMoney(s.wage), FinanceManager.formatMoney(fee)),
                            fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 1,
                        },
                    }
                },
                -- 右侧雇佣按钮
                UI.Button {
                    text = "签约",
                    height = 30, paddingLeft = 12, paddingRight = 12,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 6,
                    fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                    fontWeight = "bold",
                    onClick = function()
                        UI.CloseOverlay()
                        StaffPage._confirmHire(s, gameState, team)
                    end,
                },
            }
        })
    end

    BottomSheet.showCustom({
        title = roleFilter and ("可签约 - " .. (Constants.STAFF_ROLE_NAMES[roleFilter] or ""))
            or "自由职员市场",
        children = listItems,
        showCancel = true,
    })
end

------------------------------------------------------
-- 签约确认
------------------------------------------------------
function StaffPage._confirmHire(staff, gameState, team)
    local fee = staff.wage * 4

    ConfirmDialog.showWithDetails({
        title = "签约 - " .. staff.displayName,
        details = {
            { label = "职位", value = Constants.STAFF_ROLE_NAMES[staff.role] or staff.role },
            { label = "周薪", value = FinanceManager.formatMoney(staff.wage) },
            { label = "签约费", value = FinanceManager.formatMoney(fee), valueColor = Theme.COLORS.WARNING },
            { label = "当前余额", value = FinanceManager.formatMoney(team.balance or 0) },
        },
        confirmText = "确认签约",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, err = StaffManager.hire(gameState, team.id, staff.id)
            if ok then
                Router.replaceWith("staff")
            else
                ConfirmDialog.show({
                    title = "签约失败",
                    message = err or "操作失败",
                    confirmText = "知道了",
                    onConfirm = function() end,
                })
            end
        end,
    })
end

------------------------------------------------------
-- 辅助
------------------------------------------------------
function StaffPage._avgAttr(staff)
    local attrs = staff.attributes or {}
    local sum = (attrs.training or 0) + (attrs.scouting or 0)
        + (attrs.physiotherapy or 0) + (attrs.motivation or 0)
        + (attrs.youthDev or 0) + (attrs.tactical or 0)
    return sum / 6
end

return StaffPage
