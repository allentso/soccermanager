-- ui/components/bottom_sheet.lua
-- 通用底部弹出面板组件（基于 UI.Drawer position="bottom"）
-- 用法：
--   local BottomSheet = require("scripts/ui/components/bottom_sheet")
--   BottomSheet.show({ title = "标题", items = {...} })
--   BottomSheet.showCustom({ title = "标题", children = {...} })

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")

local BottomSheet = {}

-- 当前活跃的 Drawer 实例（同一时间只能有一个）
local _activeDrawer = nil

------------------------------------------------------
-- 内部：关闭当前活跃的 Drawer
------------------------------------------------------
local function _closeActive()
    if _activeDrawer then
        _activeDrawer:Close()
        -- 从 UI 树中移除
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(_activeDrawer)
        end
        _activeDrawer = nil
    end
end

------------------------------------------------------
-- 内部：创建并打开底部 Drawer
-- contentWidget: 要放入 Drawer 内部的 Widget
-- height: Drawer 高度
------------------------------------------------------
local function _openDrawer(contentWidget, height, onClose)
    _closeActive()

    local drawer = UI.Drawer {
        position = "bottom",
        size = height or 360,
        variant = "temporary",
        showOverlay = true,
        overlayOpacity = 0.6,
        backgroundColor = {Theme.COLORS.BG_CARD[1], Theme.COLORS.BG_CARD[2], Theme.COLORS.BG_CARD[3], 255},
        contentPadding = 0,
        animationDuration = 0.2,
        content = contentWidget,
        onClose = function()
            -- Drawer 自身关闭时（如点击遮罩），也需要从 UI 树移除
            local root = UI.GetRoot()
            if root and _activeDrawer then
                root:RemoveChild(_activeDrawer)
            end
            _activeDrawer = nil
            if onClose then onClose() end
        end,
    }

    _activeDrawer = drawer

    -- 将 Drawer 添加到 UI 树中，使其能被渲染和更新
    local root = UI.GetRoot()
    if root then
        root:AddChild(drawer)
    end

    drawer:Open()
end

------------------------------------------------------
-- 显示操作菜单式底部弹窗
------------------------------------------------------
--- @param opts table
---   title: string - 标题文本
---   subtitle?: string - 副标题
---   items: table[] - 菜单项数组，每项 { label, color?, icon?, action }
---   onClose?: function - 关闭回调
function BottomSheet.show(opts)
    local title = opts.title or ""
    local subtitle = opts.subtitle
    local items = opts.items or {}
    local onClose = opts.onClose

    local menuItems = {}

    -- 标题
    if title ~= "" then
        table.insert(menuItems, UI.Label {
            text = title,
            fontSize = 15,
            color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold",
            marginBottom = subtitle and 2 or 12,
            textAlign = "center",
        })
    end

    -- 副标题
    if subtitle then
        table.insert(menuItems, UI.Label {
            text = subtitle,
            fontSize = 12,
            color = Theme.COLORS.TEXT_MUTED,
            marginBottom = 12,
            textAlign = "center",
        })
    end

    -- 菜单项
    for _, item in ipairs(items) do
        local labelText = item.label or ""
        if item.icon then
            labelText = item.icon .. " " .. labelText
        end
        table.insert(menuItems, UI.Button {
            text = labelText,
            width = "100%",
            height = 44,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 8,
            fontSize = 14,
            color = item.color or Theme.COLORS.TEXT_PRIMARY,
            marginBottom = 6,
            onClick = function()
                _closeActive()
                if item.action then item.action() end
            end,
        })
    end

    -- 取消按钮
    table.insert(menuItems, UI.Button {
        text = "取消",
        width = "100%",
        height = 44,
        backgroundColor = Theme.COLORS.TRANSPARENT,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        fontSize = 14,
        color = Theme.COLORS.TEXT_MUTED,
        marginTop = 4,
        onClick = function()
            _closeActive()
            if onClose then onClose() end
        end,
    })

    -- 计算高度：标题 + 项目数 × 50 + 取消 + padding
    local estimatedHeight = 40 + (#items * 50) + 60 + 32
    if subtitle then estimatedHeight = estimatedHeight + 20 end
    estimatedHeight = math.min(estimatedHeight, 500)

    local content = UI.Panel {
        width = "100%",
        padding = 16,
        children = menuItems,
    }

    _openDrawer(content, estimatedHeight, onClose)
end

------------------------------------------------------
-- 显示自定义内容的底部弹窗
------------------------------------------------------
--- @param opts table
---   title?: string - 标题
---   children: table[] - 自定义 UI 子元素
---   footer?: Widget - 固定在底部的 widget（如提交按钮），不参与滚动
---   showCancel?: boolean - 是否显示取消按钮（默认 true）
---   height?: number - 自定义高度（默认 400）
---   onClose?: function - 关闭回调
function BottomSheet.showCustom(opts)
    local children = opts.children or {}
    local showCancel = opts.showCancel ~= false
    local footer = opts.footer
    local onClose = opts.onClose
    local drawerHeight = opts.height or 400

    local padV = 16   -- 上下内边距
    local padH = 16   -- 左右内边距

    local contentItems = {}

    -- 标题（固定在顶部，不参与滚动）
    if opts.title then
        table.insert(contentItems, UI.Label {
            text = opts.title,
            fontSize = 15,
            color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold",
            marginBottom = 12,
            textAlign = "center",
        })
    end

    -- 自定义内容区域（可滚动）
    -- 使用 flexGrow=1 / flexBasis=0 让 ScrollView 自动占满标题与底部按钮之间的剩余空间，
    -- 避免手动估算高度不准导致内容滚不到底。
    local scrollChildren = {}
    for _, child in ipairs(children) do
        table.insert(scrollChildren, child)
    end

    table.insert(contentItems, UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        scrollY = true,
        showScrollbar = true,
        bounceEnabled = false,
        padding = 0,
        children = scrollChildren,
    })

    -- footer（固定在底部，不参与滚动）
    if footer then
        table.insert(contentItems, footer)
    end

    -- 取消按钮（固定在最底部，不参与滚动）
    if showCancel then
        table.insert(contentItems, UI.Button {
            text = "关闭",
            width = "100%",
            height = 44,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            fontSize = 14,
            color = Theme.COLORS.TEXT_MUTED,
            marginTop = 10,
            onClick = function()
                _closeActive()
                if onClose then onClose() end
            end,
        })
    end

    local content = UI.Panel {
        width = "100%",
        height = "100%",
        paddingTop = padV,
        paddingBottom = padV,
        paddingLeft = padH,
        paddingRight = padH,
        children = contentItems,
    }

    _openDrawer(content, drawerHeight, onClose)
end

------------------------------------------------------
-- 显示单选列表式底部弹窗
------------------------------------------------------
--- @param opts table
---   title: string - 标题
---   options: table[] - 选项数组，每项 { key, label, desc? }
---   currentKey: any - 当前选中的 key
---   onSelect: function(key) - 选中回调
function BottomSheet.showSelect(opts)
    local title = opts.title or "选择"
    local options = opts.options or {}
    local currentKey = opts.currentKey
    local onSelect = opts.onSelect

    local menuItems = {
        UI.Label {
            text = title,
            fontSize = 15,
            color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold",
            marginBottom = 12,
            textAlign = "center",
        },
    }

    for _, opt in ipairs(options) do
        local isActive = opt.key == currentKey
        local labelText = (isActive and "● " or "  ") .. opt.label
        table.insert(menuItems, UI.Button {
            text = labelText,
            width = "100%",
            height = 40,
            backgroundColor = isActive and Theme.COLORS.GOLD or {38, 46, 71, 255},
            borderRadius = 8,
            fontSize = 14,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_SECONDARY,
            marginBottom = 4,
            onClick = function()
                _closeActive()
                if onSelect then onSelect(opt.key) end
            end,
        })
    end

    table.insert(menuItems, UI.Button {
        text = "取消",
        width = "100%",
        height = 40,
        backgroundColor = Theme.COLORS.TRANSPARENT,
        borderWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        borderRadius = 8,
        fontSize = 14,
        color = Theme.COLORS.TEXT_MUTED,
        marginTop = 6,
        onClick = function() _closeActive() end,
    })

    local estimatedHeight = 40 + (#options * 44) + 60 + 40
    estimatedHeight = math.min(estimatedHeight, 500)

    local content = UI.Panel {
        width = "100%",
        padding = 16,
        children = menuItems,
    }

    _openDrawer(content, estimatedHeight)
end

------------------------------------------------------
-- 手动关闭当前弹窗（供外部调用）
------------------------------------------------------
function BottomSheet.close()
    _closeActive()
end

return BottomSheet
