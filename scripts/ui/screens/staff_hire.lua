-- ui/screens/staff_hire.lua
-- 职员招聘页面（全屏列表，复用转会市场模式）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local StaffManager = require("scripts/systems/staff_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")

local StaffHire = {}

-- 职员角色颜色
local ROLE_COLORS = {
    assistant = {102, 178, 255, 255},  -- 蓝
    coach     = {102, 255, 128, 255},  -- 绿
    scout     = {255, 204, 0, 255},    -- 金
    physio    = {255, 128, 230, 255},  -- 粉
}

-- 筛选Tab
local ROLE_FILTERS = {
    { key = "all",       label = "全部" },
    { key = "assistant", label = "助理" },
    { key = "coach",     label = "教练" },
    { key = "scout",     label = "球探" },
    { key = "physio",    label = "理疗" },
}

--- 获取角色相关属性
local function getRelevantAttrs(staff)
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

--- 计算平均属性
local function avgAttr(staff)
    local attrs = staff.attributes or {}
    local sum = (attrs.training or 0) + (attrs.scouting or 0)
        + (attrs.physiotherapy or 0) + (attrs.motivation or 0)
        + (attrs.youthDev or 0) + (attrs.tactical or 0)
    return sum / 6
end

------------------------------------------------------
-- 签约确认
------------------------------------------------------
local function confirmHire(staff, gameState, team)
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
-- 主页面
------------------------------------------------------
function StaffHire.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local team = gameState:getPlayerTeam()
    if not team then return UI.Panel { width = "100%", height = "100%" } end

    local roleFilter = (params and params.roleFilter) or "all"

    -- 获取自由职员
    local filterRole = roleFilter ~= "all" and roleFilter or nil
    local freeStaff = StaffManager.getFreeStaff(gameState, filterRole)

    -- 按综合属性排序
    table.sort(freeStaff, function(a, b)
        return avgAttr(a) > avgAttr(b)
    end)

    -- 筛选按钮
    local filterBtns = {}
    for _, f in ipairs(ROLE_FILTERS) do
        local isActive = f.key == roleFilter
        table.insert(filterBtns, UI.Button {
            text = f.label,
            height = 30,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 15,
            fontSize = 12,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            onClick = function()
                Router.replaceWith("staff_hire", { roleFilter = f.key })
            end,
        })
    end

    -- 构建列表内容
    local listChildren = {}

    if #freeStaff == 0 then
        table.insert(listChildren, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无可签约的职员", fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, s in ipairs(freeStaff) do
            local roleName = Constants.STAFF_ROLE_NAMES[s.role] or s.role
            local roleColor = ROLE_COLORS[s.role] or Theme.COLORS.TEXT_SECONDARY
            local fee = s.wage * 4

            local attrItems = getRelevantAttrs(s)
            local attrText = {}
            for _, a in ipairs(attrItems) do
                table.insert(attrText, a.label .. a.value)
            end

            table.insert(listChildren, UI.Panel {
                width = "100%",
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 10, paddingBottom = 10,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = {
                    -- 第一行：角色标签 + 名字 + 签约按钮
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Panel {
                                backgroundColor = roleColor, borderRadius = 3,
                                paddingLeft = 5, paddingRight = 5, height = 18,
                                justifyContent = "center", alignItems = "center",
                                marginRight = 8,
                                children = {
                                    UI.Label { text = roleName, fontSize = 9, color = {20, 20, 30, 255}, fontWeight = "bold" },
                                }
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                children = {
                                    UI.Label {
                                        text = s.displayName,
                                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Button {
                                text = "签约",
                                height = 30, paddingLeft = 14, paddingRight = 14,
                                backgroundColor = Theme.COLORS.GOLD,
                                borderRadius = 6,
                                fontSize = 12, color = "#1A1A1A",
                                fontWeight = "bold",
                                onClick = function()
                                    confirmHire(s, gameState, team)
                                end,
                            },
                        }
                    },
                    -- 第二行：属性
                    UI.Label {
                        text = table.concat(attrText, " | "),
                        fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                        marginTop = 4,
                    },
                    -- 第三行：薪资
                    UI.Label {
                        text = string.format("周薪 %s · 签约费 %s",
                            FinanceManager.formatMoney(s.wage), FinanceManager.formatMoney(fee)),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 2,
                    },
                }
            })
        end
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
                        text = "自由职员市场",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Label {
                        text = string.format("%d人", #freeStaff),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 50, textAlign = "right",
                    },
                }
            },

            -- 筛选栏
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
                children = filterBtns,
            },

            -- 列表区
            UI.ScrollView {
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                scrollY = true,
                bounceEnabled = false,
                children = listChildren,
            },
        }
    }
end

return StaffHire
