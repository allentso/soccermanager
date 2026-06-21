-- ui/layout_adapter.lua
-- 全局 UI 安全边距适配：用于避让手机刘海、状态栏、底部手势条

local UI = require("urhox-libs/UI")
local SettingsManager = require("scripts/persistence/settings_manager")

local LayoutAdapter = {}

local SAFE_AREA_PRESETS = {
    default = { top = 0, bottom = 0, label = "默认" },
    light = { top = 16, bottom = 18, label = "轻微" },
    medium = { top = 28, bottom = 32, label = "加强" },
    large = { top = 40, bottom = 46, label = "最大" },
}

function LayoutAdapter.getSafeAreaPresets()
    return SAFE_AREA_PRESETS
end

function LayoutAdapter.getSafeAreaMode()
    local mode = SettingsManager.get("uiSafeAreaMode") or "default"
    if SAFE_AREA_PRESETS[mode] then
        return mode
    end
    return "default"
end

function LayoutAdapter.wrapPage(page)
    local mode = LayoutAdapter.getSafeAreaMode()
    local preset = SAFE_AREA_PRESETS[mode] or SAFE_AREA_PRESETS.default
    if preset.top == 0 and preset.bottom == 0 then
        return page
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = "#050914",
        paddingTop = preset.top,
        paddingBottom = preset.bottom,
        children = {
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                overflow = "hidden",
                children = { page },
            },
        },
    }
end

return LayoutAdapter
