-- ui/components/blocker_dialog.lua
-- 时间阻断对话框：展示所有阻断项，提供导航或强制跳过

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")

local BlockerDialog = {}

-- 当前活跃的 Drawer
local _activeDrawer = nil

------------------------------------------------------
-- 关闭
------------------------------------------------------
function BlockerDialog.close()
    if _activeDrawer then
        _activeDrawer:Close()
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(_activeDrawer)
        end
        _activeDrawer = nil
    end
end

------------------------------------------------------
-- 展示阻断对话框
-- @param blockers Blocker[] 来自 TimeBlockerManager.check()
-- @param opts { onDismiss?: function, onForceAdvance?: function }
------------------------------------------------------
function BlockerDialog.show(blockers, opts)
    opts = opts or {}
    BlockerDialog.close()

    local hasWarn = false
    for _, b in ipairs(blockers) do
        if b.severity == "warn" then hasWarn = true; break end
    end

    -- 构建阻断项列表
    local rows = {}
    for _, b in ipairs(blockers) do
        local isWarn = b.severity == "warn"
        local iconColor = isWarn and Theme.COLORS.DANGER or Theme.COLORS.WARNING
        local icon = isWarn and "!" or "i"

        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 8,
            paddingBottom = 8,
            paddingLeft = 10,
            paddingRight = 10,
            marginBottom = 4,
            backgroundColor = {iconColor[1], iconColor[2], iconColor[3], 20},
            borderRadius = 6,
            children = {
                -- 严重度图标
                UI.Panel {
                    width = 22, height = 22,
                    borderRadius = 11,
                    backgroundColor = iconColor,
                    justifyContent = "center",
                    alignItems = "center",
                    marginRight = 10,
                    children = {
                        UI.Label {
                            text = icon,
                            fontSize = 12,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                    }
                },
                -- 消息文本
                UI.Label {
                    text = b.message,
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                -- 导航按钮
                UI.Button {
                    text = BlockerDialog._getTargetLabel(b.target),
                    width = 56, height = 28,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 6,
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        BlockerDialog.close()
                        Router.navigate(b.target)
                    end,
                },
            }
        })
    end

    -- 底部操作按钮
    local actions = {}

    -- 如果只有 info 级别，允许强制跳过
    if not hasWarn and opts.onForceAdvance then
        table.insert(actions, UI.Button {
            text = "忽略并继续",
            height = 40,
            flexGrow = 1,
            backgroundColor = Theme.COLORS.WARNING,
            borderRadius = 8,
            fontSize = 14,
            color = Theme.COLORS.BG_DARK,
            fontWeight = "bold",
            marginRight = 6,
            onClick = function()
                BlockerDialog.close()
                opts.onForceAdvance()
            end,
        })
    end

    table.insert(actions, UI.Button {
        text = hasWarn and "知道了" or "返回",
        height = 40,
        flexGrow = 1,
        backgroundColor = hasWarn and Theme.COLORS.DANGER or Theme.COLORS.SECONDARY,
        borderRadius = 8,
        fontSize = 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginLeft = #actions > 0 and 6 or 0,
        onClick = function()
            BlockerDialog.close()
            if opts.onDismiss then opts.onDismiss() end
        end,
    })

    -- 内容面板
    local content = UI.Panel {
        width = "100%",
        children = {
            -- 标题
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                marginBottom = 12,
                children = {
                    UI.Label {
                        text = hasWarn and "无法推进时间" or "注意事项",
                        fontSize = 16,
                        color = hasWarn and Theme.COLORS.DANGER or Theme.COLORS.WARNING,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = string.format("%d 项", #blockers),
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 副标题
            UI.Label {
                text = hasWarn
                    and "以下问题必须先处理才能继续:"
                    or "以下事项建议先处理:",
                fontSize = 12,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 10,
            },
            -- 阻断列表
            UI.ScrollView {
                width = "100%",
                maxHeight = 240,
                scrollY = true,
                children = rows,
            },
            -- 操作按钮
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginTop = 14,
                children = actions,
            },
        },
    }

    -- 计算高度
    local drawerHeight = math.min(400, 160 + #blockers * 52)

    local drawer = UI.Drawer {
        position = "bottom",
        size = drawerHeight,
        variant = "temporary",
        showOverlay = true,
        overlayOpacity = 0.6,
        backgroundColor = {Theme.COLORS.BG_CARD[1], Theme.COLORS.BG_CARD[2], Theme.COLORS.BG_CARD[3], 255},
        contentPadding = 16,
        animationDuration = 0.2,
        content = content,
        onClose = function()
            local root = UI.GetRoot()
            if root and _activeDrawer then
                root:RemoveChild(_activeDrawer)
            end
            _activeDrawer = nil
            if opts.onDismiss then opts.onDismiss() end
        end,
    }

    _activeDrawer = drawer
    local root = UI.GetRoot()
    if root then
        root:AddChild(drawer)
        drawer:Open()
    end
end

------------------------------------------------------
-- 工具
------------------------------------------------------
function BlockerDialog._getTargetLabel(target)
    local labels = {
        squad = "阵容",
        finance = "财务",
        inbox = "消息",
        market = "市场",
    }
    return labels[target] or "查看"
end

return BlockerDialog
