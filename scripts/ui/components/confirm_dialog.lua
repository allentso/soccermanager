-- ui/components/confirm_dialog.lua
-- 通用确认对话框组件
-- 用法：
--   local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
--   ConfirmDialog.show({
--       title = "确认续约",
--       message = "续约费用 50K/周，确认吗？",
--       confirmText = "确认续约",
--       confirmColor = Theme.COLORS.PRIMARY,
--       onConfirm = function() ... end,
--   })

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")

local ConfirmDialog = {}

--- 关闭 overlay 并在下一帧执行回调，避免同一次点击穿透到底层按钮再次触发
local function _closeAndDefer(fn)
    UI.CloseOverlay()
    if not fn then return end
    SubscribeToEvent("PostUpdate", function()
        UnsubscribeFromEvent("PostUpdate")
        fn()
    end)
end

--- 显示确认对话框
--- @param opts table
---   title: string - 标题
---   message?: string - 描述文本
---   confirmText?: string - 确认按钮文字（默认"确认"）
---   cancelText?: string - 取消按钮文字（默认"取消"）
---   confirmColor?: table - 确认按钮颜色（默认 PRIMARY）
---   danger?: boolean - 是否为危险操作（true 时确认按钮为红色）
---   onConfirm: function - 确认回调
---   onCancel?: function - 取消回调
function ConfirmDialog.show(opts)
    local title = opts.title or "确认"
    local message = opts.message
    local confirmText = opts.confirmText or "确认"
    local cancelText = opts.cancelText or "取消"
    local confirmColor = opts.confirmColor
    local onConfirm = opts.onConfirm
    local onCancel = opts.onCancel

    -- 危险操作使用红色
    if opts.danger then
        confirmColor = confirmColor or Theme.COLORS.DANGER
    else
        confirmColor = confirmColor or Theme.COLORS.PRIMARY
    end

    local dialogContent = {}

    -- 标题
    table.insert(dialogContent, UI.Label {
        text = title,
        fontSize = 16,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        textAlign = "center",
        marginBottom = 8,
    })

    -- 消息
    if message then
        table.insert(dialogContent, UI.Label {
            text = message,
            fontSize = 13,
            color = Theme.COLORS.TEXT_SECONDARY,
            textAlign = "center",
            marginBottom = 20,
        })
    end

    -- 按钮区
    table.insert(dialogContent, UI.Panel {
        width = "100%",
        flexDirection = "row",
        children = {
            -- 取消按钮
            UI.Button {
                text = cancelText,
                flexGrow = 1,
                height = 42,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 8,
                fontSize = 14,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginRight = 8,
                onClick = function()
                    _closeAndDefer(onCancel)
                end,
            },
            -- 确认按钮
            UI.Button {
                text = confirmText,
                flexGrow = 1,
                height = 42,
                backgroundColor = confirmColor,
                borderRadius = 8,
                fontSize = 14,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                onClick = function()
                    _closeAndDefer(onConfirm)
                end,
            },
        }
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 150},
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 16,
                padding = 24,
                children = dialogContent,
            },
        },
    })
end

--- 显示带详情列表的确认对话框（如续约条款确认）
--- @param opts table
---   title: string
---   details: table[] - 详情行数组，每项 { label, value, valueColor? }
---   confirmText?: string
---   danger?: boolean
---   onConfirm: function
---   onCancel?: function
function ConfirmDialog.showWithDetails(opts)
    local title = opts.title or "确认"
    local details = opts.details or {}
    local confirmText = opts.confirmText or "确认"
    local cancelText = opts.cancelText or "取消"
    local confirmColor = opts.danger and Theme.COLORS.DANGER or (opts.confirmColor or Theme.COLORS.PRIMARY)
    local onConfirm = opts.onConfirm
    local onCancel = opts.onCancel

    local dialogContent = {}

    -- 标题
    table.insert(dialogContent, UI.Label {
        text = title,
        fontSize = 16,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        textAlign = "center",
        marginBottom = 12,
    })

    -- 详情列表
    for _, row in ipairs(details) do
        table.insert(dialogContent, UI.Panel {
            width = "100%",
            height = 32,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            borderBottomWidth = 1,
            borderColor = {51, 61, 89, 100},
            children = {
                UI.Label {
                    text = row.label or "",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                },
                UI.Label {
                    text = tostring(row.value or ""),
                    fontSize = 13,
                    color = row.valueColor or Theme.COLORS.TEXT_PRIMARY,
                    fontWeight = "bold",
                },
            }
        })
    end

    -- 间距
    table.insert(dialogContent, UI.Panel { height = 16 })

    -- 按钮
    table.insert(dialogContent, UI.Panel {
        width = "100%",
        flexDirection = "row",
        children = {
            UI.Button {
                text = cancelText,
                flexGrow = 1,
                height = 42,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 8,
                fontSize = 14,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginRight = 8,
                onClick = function()
                    _closeAndDefer(onCancel)
                end,
            },
            UI.Button {
                text = confirmText,
                flexGrow = 1,
                height = 42,
                backgroundColor = confirmColor,
                borderRadius = 8,
                fontSize = 14,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                onClick = function()
                    _closeAndDefer(onConfirm)
                end,
            },
        }
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 150},
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 16,
                padding = 24,
                children = dialogContent,
            },
        },
    })
end

return ConfirmDialog
