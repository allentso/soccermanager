-- ui/screens/load_game.lua
-- 存档管理页面 - 增强版：多槽保存、删除确认、详细元数据

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local SaveManager = require("scripts/persistence/save_manager")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local LoadGame = {}

------------------------------------------------------
-- 主入口
------------------------------------------------------
function LoadGame.create(params)
    local slots = SaveManager.getAllSlots()
    local hasGameState = _G.gameState ~= nil

    local slotCards = {}

    -- 自动存档
    table.insert(slotCards, LoadGame._slotCard({
        label = "自动存档",
        icon = "A",
        slot = "auto",
        info = slots.auto,
        canSave = false,  -- 自动存档不可手动保存
        canDelete = false,
    }))

    -- 手动存档槽
    for i = 1, Constants.MAX_SAVE_SLOTS do
        local info = slots[i]
        table.insert(slotCards, LoadGame._slotCard({
            label = "存档 " .. i,
            icon = tostring(i),
            slot = i,
            info = info,
            canSave = hasGameState,
            canDelete = info ~= nil,
        }))
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "存档管理",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- 提示
            hasGameState and UI.Panel {
                width = "100%",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 8, paddingBottom = 8,
                backgroundColor = {25, 32, 52, 255},
                children = {
                    UI.Label {
                        text = "点击[保存]将当前进度写入该槽位，点击[加载]读取存档",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            } or UI.Panel { height = 0 },

            -- 存档列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = slotCards,
            },
        }
    }
end

------------------------------------------------------
-- 存档卡片
------------------------------------------------------
function LoadGame._slotCard(opts)
    local label = opts.label
    local icon = opts.icon
    local slot = opts.slot
    local info = opts.info
    local canSave = opts.canSave
    local canDelete = opts.canDelete
    local isEmpty = info == nil

    -- 元数据
    local teamName = ""
    local seasonStr = ""
    local savedAt = ""
    local balanceStr = ""
    if info then
        teamName = info.team_name or info.teamName or ""
        if info.season then seasonStr = "赛季 " .. info.season end
        savedAt = info.saved_at or info.savedAt or "未知时间"
        if info.balance then balanceStr = "资金 " .. LoadGame._formatMoney(info.balance) end
    end

    -- 操作按钮
    local actionBtns = {}

    -- 加载按钮（有存档才能加载）
    if not isEmpty then
        table.insert(actionBtns, UI.Button {
            text = "加载",
            width = 56, height = 32,
            backgroundColor = Theme.COLORS.PRIMARY,
            borderRadius = 6,
            fontSize = 12,
            color = Theme.COLORS.TEXT_PRIMARY,
            marginRight = 6,
            onClick = function()
                LoadGame._confirmLoad(slot, label)
            end,
        })
    end

    -- 保存按钮（有游戏状态且允许保存才显示）
    if canSave then
        table.insert(actionBtns, UI.Button {
            text = isEmpty and "保存" or "覆盖",
            width = 56, height = 32,
            backgroundColor = isEmpty and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING,
            borderRadius = 6,
            fontSize = 12,
            color = Theme.COLORS.TEXT_PRIMARY,
            marginRight = 6,
            onClick = function()
                if isEmpty then
                    LoadGame._doSave(slot)
                else
                    LoadGame._confirmOverwrite(slot, label)
                end
            end,
        })
    end

    -- 删除按钮
    if canDelete then
        table.insert(actionBtns, UI.Button {
            text = "删除",
            width = 50, height = 32,
            backgroundColor = {60, 40, 40, 255},
            borderRadius = 6,
            fontSize = 12,
            color = Theme.COLORS.DANGER,
            onClick = function()
                LoadGame._confirmDelete(slot, label)
            end,
        })
    end

    -- 图标颜色
    local iconBg = isEmpty and {50, 58, 80, 255} or Theme.COLORS.PRIMARY

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 12,
        padding = 14,
        marginBottom = 10,
        children = {
            -- 头部：图标 + 名称 + 状态
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                children = {
                    -- 图标
                    UI.Panel {
                        width = 38, height = 38,
                        backgroundColor = iconBg,
                        borderRadius = 19,
                        justifyContent = "center",
                        alignItems = "center",
                        marginRight = 12,
                        children = {
                            UI.Label {
                                text = icon,
                                fontSize = 16,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                            },
                        }
                    },
                    -- 信息
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = label,
                                fontSize = 15,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                            },
                            isEmpty and UI.Label {
                                text = "空槽位",
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_MUTED,
                                marginTop = 2,
                            } or UI.Label {
                                text = teamName .. (seasonStr ~= "" and (" · " .. seasonStr) or ""),
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                marginTop = 2,
                            },
                        }
                    },
                }
            },

            -- 详细元数据（非空时显示）
            not isEmpty and UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                marginTop = 8,
                paddingLeft = 50,  -- 对齐图标右侧
                children = {
                    savedAt ~= "" and UI.Label {
                        text = "保存: " .. savedAt,
                        fontSize = 10,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginRight = 12,
                    } or UI.Panel { width = 0 },
                    balanceStr ~= "" and UI.Label {
                        text = balanceStr,
                        fontSize = 10,
                        color = Theme.COLORS.TEXT_MUTED,
                    } or UI.Panel { width = 0 },
                }
            } or UI.Panel { height = 0 },

            -- 操作按钮区域
            (#actionBtns > 0) and UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "flex-end",
                marginTop = 10,
                children = actionBtns,
            } or UI.Panel { height = 0 },
        }
    }
end

------------------------------------------------------
-- 确认对话框
------------------------------------------------------
function LoadGame._confirmLoad(slot, label)
    UI.ShowOverlay(UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderTopLeftRadius = 16,
        borderTopRightRadius = 16,
        padding = 20,
        children = {
            UI.Label {
                text = "加载存档",
                fontSize = 16,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                marginBottom = 8,
            },
            UI.Label {
                text = "确定要加载「" .. label .. "」吗？当前未保存的进度将丢失。",
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row",
                children = {
                    UI.Button {
                        text = "取消",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        marginRight = 8,
                        onClick = function() UI.CloseOverlay() end,
                    },
                    UI.Button {
                        text = "确认加载",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                            EventBus.emit("load_save", slot)
                        end,
                    },
                }
            },
        }
    })
end

function LoadGame._confirmOverwrite(slot, label)
    UI.ShowOverlay(UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderTopLeftRadius = 16,
        borderTopRightRadius = 16,
        padding = 20,
        children = {
            UI.Label {
                text = "覆盖存档",
                fontSize = 16,
                color = Theme.COLORS.WARNING,
                fontWeight = "bold",
                marginBottom = 8,
            },
            UI.Label {
                text = "「" .. label .. "」已有数据，覆盖后无法恢复。确定要覆盖吗？",
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row",
                children = {
                    UI.Button {
                        text = "取消",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        marginRight = 8,
                        onClick = function() UI.CloseOverlay() end,
                    },
                    UI.Button {
                        text = "覆盖保存",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = Theme.COLORS.WARNING,
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                            LoadGame._doSave(slot)
                        end,
                    },
                }
            },
        }
    })
end

function LoadGame._confirmDelete(slot, label)
    UI.ShowOverlay(UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderTopLeftRadius = 16,
        borderTopRightRadius = 16,
        padding = 20,
        children = {
            UI.Label {
                text = "删除存档",
                fontSize = 16,
                color = Theme.COLORS.DANGER,
                fontWeight = "bold",
                marginBottom = 8,
            },
            UI.Label {
                text = "确定要永久删除「" .. label .. "」吗？此操作不可撤销。",
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 16,
            },
            UI.Panel {
                flexDirection = "row",
                children = {
                    UI.Button {
                        text = "取消",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        marginRight = 8,
                        onClick = function() UI.CloseOverlay() end,
                    },
                    UI.Button {
                        text = "确认删除",
                        flexGrow = 1,
                        height = 40,
                        backgroundColor = Theme.COLORS.DANGER,
                        borderRadius = 8,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                            SaveManager.delete(slot)
                            Router.replaceWith("load_game")
                        end,
                    },
                }
            },
        }
    })
end

------------------------------------------------------
-- 保存操作
------------------------------------------------------
function LoadGame._doSave(slot)
    if _G.gameState then
        SaveManager.save(_G.gameState, slot)
        -- 刷新页面显示
        Router.replaceWith("load_game")
    end
end

------------------------------------------------------
-- 工具函数
------------------------------------------------------
function LoadGame._formatMoney(amount)
    if not amount then return "0" end
    local abs = math.abs(amount)
    if abs >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif abs >= 1000 then
        return string.format("%.0fK", amount / 1000)
    else
        return tostring(math.floor(amount))
    end
end

return LoadGame
