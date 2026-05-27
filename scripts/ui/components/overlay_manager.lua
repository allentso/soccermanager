-- ui/components/overlay_manager.lua
-- 全局覆盖层管理器
-- 为 UI 注入 ShowOverlay / CloseOverlay 全局函数
-- 用法：在 UI.Init 后、页面加载前 require 一次即可
--   require("scripts/ui/components/overlay_manager")

local UI = require("urhox-libs/UI")

-- 当前活跃的 overlay widget
local _activeOverlay = nil

--- 显示一个全屏覆盖层（用于确认对话框等居中弹窗）
--- @param widget any 全屏 Panel widget
function UI.ShowOverlay(widget)
    -- 先关闭已有的
    if _activeOverlay then
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(_activeOverlay)
        end
        _activeOverlay = nil
    end

    if widget then
        -- 设为绝对定位，不影响 flex 布局
        widget:SetStyle({ position = "absolute", top = 0, left = 0 })
        _activeOverlay = widget
        local root = UI.GetRoot()
        if root then
            root:AddChild(widget)
        end
    end
end

--- 关闭当前活跃的覆盖层
function UI.CloseOverlay()
    if _activeOverlay then
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(_activeOverlay)
        end
        _activeOverlay = nil
    end
end

return true
