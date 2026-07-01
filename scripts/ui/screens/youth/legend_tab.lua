-- ui/screens/youth/legend_tab.lua
-- 传奇抽卡标签页，从 youth.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local Nationality = require("scripts/domain/nationality")
local YouthManager = require("scripts/systems/youth_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")
local LegendImageRegistry = require("scripts/data/legend_image_registry")
local SaveManager = require("scripts/persistence/save_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")
---@diagnostic disable-next-line: undefined-global
local sdk = sdk
local function _youth() return require("scripts/ui/screens/youth") end

local Tab = {}

function Tab._buildLegendPoolSelector(gameState)
    local selectedId = YouthManager.getSelectedLegendPoolId(gameState)
    local pools = YouthManager.getLegendTagPools()
    local chips = {}

    for _, pool in ipairs(pools) do
        local ui = _youth()._getLegendPoolUi()[pool.id] or { icon = "⭐", short = pool.name_cn }
        local progress = YouthManager.getLegendPoolProgress(gameState, pool.id)
        local isSelected = (pool.id == selectedId)
        local exhausted = progress.remaining == 0

        local chipBg, chipBorder, labelColor
        if isSelected then
            chipBg = Theme.COLORS.ACCENT
            chipBorder = Theme.COLORS.GOLD_LIGHT
            labelColor = {255, 255, 255, 255}
        else
            chipBg = Theme.COLORS.BG_SURFACE
            chipBorder = Theme.COLORS.BORDER
            labelColor = exhausted and Theme.COLORS.TEXT_MUTED or Theme.COLORS.TEXT_SECONDARY
        end

        table.insert(chips, UI.Button {
            text = string.format(
                "%s %s\n%s",
                ui.icon,
                ui.short,
                exhausted and "已集齐" or (progress.remaining .. "/" .. progress.total)
            ),
            flexGrow = 1,
            flexBasis = "30%",
            minWidth = 78,
            height = 54,
            marginRight = 6,
            marginBottom = 6,
            backgroundColor = chipBg,
            borderRadius = 10,
            borderWidth = isSelected and 2 or 1,
            borderColor = chipBorder,
            fontSize = 11,
            color = labelColor,
            fontWeight = isSelected and "bold" or "normal",
            onClick = function()
                if _youth()._legendCloudMutateBlocked() then
                    _youth()._showLegendCloudSyncingToast()
                    return
                end
                if pool.id ~= selectedId then
                    YouthManager.setSelectedLegendPool(gameState, pool.id)
                    SaveManager.save(gameState, "auto")
                    Router.replaceWith("youth", { tab = "legend" })
                end
            end,
        })
    end

    local selectedPool = YouthManager.getSelectedLegendPool(gameState)

    return UI.Panel {
        width = "100%",
        marginBottom = 10,
        children = {
            -- 标题行：左标题 + 右"查看名单"
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginBottom = 6,
                children = {
                    UI.Label {
                        text = "选择抽卡池（可随时切换）",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_SECONDARY,
                    },
                    UI.Button {
                        text = "查看名单 ›",
                        height = 24,
                        paddingLeft = 8, paddingRight = 8,
                        backgroundColor = Theme.COLORS.BG_SURFACE,
                        borderRadius = 6,
                        borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                        fontSize = 10,
                        color = Theme.COLORS.GOLD,
                        onClick = function()
                            _youth()._showLegendPoolListModal(gameState, selectedId)
                        end,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                children = chips,
            },
            UI.Label {
                text = selectedPool and (selectedPool.desc or "") or "",
                fontSize = 10,
                color = Theme.COLORS.TEXT_MUTED,
                marginTop = 4,
            },
        },
    }
end

------------------------------------------------------
-- 传奇池名单弹窗（查看某标签池内全部传奇及收集状态）
------------------------------------------------------
function Tab._showLegendPoolListModal(gameState, poolId)
    local pools = YouthManager.getLegendTagPools()
    local poolMeta
    for _, p in ipairs(pools) do
        if p.id == poolId then poolMeta = p; break end
    end
    local poolUi = _youth()._getLegendPoolUi()[poolId] or { icon = "⭐" }
    local members = YouthManager.getLegendPoolMembers(gameState, poolId)
    local progress = YouthManager.getLegendPoolProgress(gameState, poolId)

    -- 球员卡片网格
    local cards = {}
    for _, m in ipairs(members) do
        local data = m.data
        local collected = m.collected
        local name = data.full_name_cn or data.match_name or "传奇"
        local pos = Constants.POSITION_NAMES[data.position] or data.position or ""
        local imgPath = LegendImageRegistry.getPath(data.id) or ""

        table.insert(cards, UI.Panel {
            flexBasis = "30%",
            flexGrow = 1,
            minWidth = 88,
            marginRight = 6,
            marginBottom = 8,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 10,
            borderWidth = 1,
            borderColor = collected and Theme.COLORS.GOLD or Theme.COLORS.BORDER,
            overflow = "hidden",
            children = {
                -- 立绘
                UI.Panel {
                    width = "100%",
                    aspectRatio = 3 / 4,
                    backgroundImage = collected and imgPath or "",
                    backgroundSize = "cover",
                    backgroundColor = Theme.COLORS.BG_DARK,
                    children = {
                        -- 未收集遮罩标记
                        (not collected) and UI.Panel {
                            width = "100%", height = "100%",
                            justifyContent = "center", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = "未获得",
                                    fontSize = 11,
                                    color = Theme.COLORS.TEXT_SECONDARY,
                                    fontWeight = "bold",
                                },
                            },
                        } or UI.Panel {
                            -- 已收集角标
                            position = "absolute",
                            top = 4, right = 4,
                            backgroundColor = Theme.COLORS.GOLD,
                            borderRadius = 8,
                            paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                            children = {
                                UI.Label { text = "✓", fontSize = 10, color = {20, 16, 36, 255}, fontWeight = "bold" },
                            },
                        },
                    },
                },
                -- 名字 + 位置
                UI.Panel {
                    width = "100%",
                    padding = 5,
                    children = {
                        UI.Label {
                            text = name,
                            fontSize = 11,
                            color = collected and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = pos,
                            fontSize = 9,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 1,
                        },
                    },
                },
            },
        })
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 210},
        children = {
            UI.Panel {
                width = "94%",
                maxHeight = "86%",
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                borderRadius = 18,
                borderWidth = 1,
                borderColor = Theme.COLORS.BORDER_LIGHT,
                paddingTop = 16, paddingBottom = 16,
                paddingLeft = 14, paddingRight = 14,
                children = {
                    -- 标题行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center",
                                children = {
                                    UI.Label { text = poolUi.icon, fontSize = 18, marginRight = 6 },
                                    UI.Label {
                                        text = poolMeta and poolMeta.name_cn or "传奇名单",
                                        fontSize = 16, color = Theme.COLORS.GOLD, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                text = string.format("已集 %d/%d", progress.collected, progress.total),
                                fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold",
                            },
                        },
                    },
                    -- 池描述
                    UI.Label {
                        text = poolMeta and (poolMeta.desc or "") or "",
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
                    },
                    -- 球员网格（可滚动）
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        marginBottom = 12,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                flexWrap = "wrap",
                                children = cards,
                            },
                        },
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%", height = 40,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 10,
                        fontSize = 14, color = {255, 255, 255, 255}, fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                        end,
                    },
                },
            },
        },
    })
end

------------------------------------------------------
-- 漏签传奇补领
------------------------------------------------------
function Tab._buildOrphanReclaimBanner(gameState)
    local orphans = YouthManager.getOrphanedPulledLegends(gameState)
    if #orphans == 0 then
        return UI.Panel { height = 0 }
    end

    return UI.Panel {
        width = "100%",
        marginBottom = 10,
        children = {
            UI.Panel {
                width = "100%",
                padding = 10,
                backgroundColor = {45, 35, 20, 255},
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Theme.COLORS.GOLD,
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "⚠",
                        fontSize = 16,
                        marginRight = 8,
                    },
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = string.format("您有 %d 名传奇尚未签入", #orphans),
                                fontSize = 13,
                                color = Theme.COLORS.GOLD,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = "抽卡记录已消耗，可从下方补领签入青训",
                                fontSize = 10,
                                color = Theme.COLORS.TEXT_MUTED,
                                marginTop = 2,
                            },
                        },
                    },
                    UI.Button {
                        text = "查看补领",
                        height = 32,
                        paddingLeft = 12,
                        paddingRight = 12,
                        backgroundColor = Theme.COLORS.GOLD,
                        borderRadius = 8,
                        fontSize = 12,
                        fontWeight = "bold",
                        color = "#000000",
                        onClick = function()
                            _youth()._showOrphanReclaimModal(gameState)
                        end,
                    },
                },
            },
        },
    }
end

function Tab._showOrphanReclaimModal(gameState)
    local orphans = YouthManager.getOrphanedPulledLegends(gameState)
    if #orphans == 0 then
        UI.Toast.Show({ message = "暂无待补签传奇", variant = "info" })
        return
    end

    local rows = {}
    for _, lData in ipairs(orphans) do
        local entry = lData
        local name = entry.full_name_cn or entry.match_name or "传奇"
        local pos = Constants.POSITION_NAMES[entry.position] or entry.position or ""
        local imgPath = LegendImageRegistry.getPath(entry.id) or ""

        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 10,
            borderWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            padding = 8,
            marginBottom = 8,
            children = {
                UI.Panel {
                    width = 44,
                    height = 58,
                    borderRadius = 6,
                    overflow = "hidden",
                    backgroundImage = imgPath,
                    backgroundSize = "cover",
                    backgroundColor = Theme.COLORS.BG_DARK,
                    marginRight = 10,
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label {
                            text = name,
                            fontSize = 14,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = pos,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 2,
                        },
                    },
                },
                UI.Button {
                    text = "签入青训",
                    height = 34,
                    paddingLeft = 10,
                    paddingRight = 10,
                    backgroundColor = Theme.COLORS.SECONDARY,
                    borderRadius = 8,
                    fontSize = 12,
                    fontWeight = "bold",
                    color = {255, 255, 255, 255},
                    onClick = function()
                        local ok, err = YouthManager.reclaimOrphanedLegend(gameState, entry)
                        if ok then
                            SaveManager.save(gameState, "auto")
                            UI.CloseOverlay()
                            UI.Toast.Show({
                                message = name .. " 已补签加入青训队",
                                variant = "success",
                            })
                            Router.replaceWith("youth", { tab = "legend" })
                        else
                            UI.Toast.Show({
                                message = err or "签入失败",
                                variant = "error",
                            })
                        end
                    end,
                },
            },
        })
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 210},
        children = {
            UI.Panel {
                width = "94%",
                maxHeight = "80%",
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                borderRadius = 18,
                borderWidth = 1,
                borderColor = Theme.COLORS.BORDER_LIGHT,
                paddingTop = 16,
                paddingBottom = 16,
                paddingLeft = 14,
                paddingRight = 14,
                children = {
                    UI.Label {
                        text = "漏签传奇补领",
                        fontSize = 16,
                        color = Theme.COLORS.GOLD,
                        fontWeight = "bold",
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = "以下传奇已抽中但未签入，可在此直接签入青训队",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 12,
                    },
                    UI.ScrollView {
                        width = "100%",
                        flexGrow = 1,
                        marginBottom = 12,
                        children = {
                            UI.Panel {
                                width = "100%",
                                children = rows,
                            },
                        },
                    },
                    UI.Button {
                        text = "关闭",
                        width = "100%",
                        height = 40,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 10,
                        fontSize = 14,
                        color = {255, 255, 255, 255},
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                        end,
                    },
                },
            },
        },
    })
end

function Tab.build(gameState)
    local gachaState = YouthManager.getLegendGachaState(gameState)
    local cloudBlocked = _youth()._legendCloudMutateBlocked()
    local syncBanner = _youth()._buildLegendCloudSyncBanner()

    -- 未解锁状态：显示进度条和观看广告按钮
    if not gachaState.unlocked then
        local progress = gachaState.adsWatched
        local total = YouthManager.getUnlockAdsRequired()
        local progressPct = math.floor(progress / total * 100)

        local children = {}
        if syncBanner then table.insert(children, syncBanner) end
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginBottom = 8,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Label {
                            text = "⭐",
                            fontSize = 16, marginRight = 4,
                        },
                        Theme.Subtitle { text = "传奇球星池", marginBottom = 0 },
                    },
                },
                UI.Label {
                    text = string.format("%d/%d 解锁", progress, total),
                    fontSize = 11,
                    color = Theme.COLORS.ACCENT,
                },
            },
        })
        table.insert(children, UI.Panel {
            width = "100%", height = 6,
            backgroundColor = Theme.COLORS.BG_DARK,
            borderRadius = 3,
            marginBottom = 10,
            children = {
                UI.Panel {
                    width = tostring(progressPct) .. "%",
                    height = "100%",
                    backgroundColor = Theme.COLORS.ACCENT,
                    borderRadius = 3,
                },
            },
        })
        table.insert(children, UI.Label {
            text = "观看广告解锁传奇抽卡，解锁后可在5个叙事标签池中自由选择！",
            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
        })
        table.insert(children, UI.Button {
            text = cloudBlocked and "云存档同步中..." or ("观看广告 (" .. progress .. "/" .. total .. ")"),
            width = "100%", height = 36,
            backgroundColor = cloudBlocked and Theme.COLORS.BG_SURFACE or Theme.COLORS.PRIMARY,
            borderRadius = 8,
            fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold",
            disabled = cloudBlocked,
            onClick = function()
                if cloudBlocked then
                    _youth()._showLegendCloudSyncingToast()
                    return
                end
                _youth()._watchAdForUnlock(gameState)
            end,
        })
        return Theme.Card { children = children }
    end

    -- 已解锁状态：显示抽取次数和十连抽按钮
    local pulls = gachaState.pulls
    local adProgress, adTotal = YouthManager.getPullAdProgress(gameState)

    local selectedPool = YouthManager.getSelectedLegendPool(gameState)
    local poolProgress = YouthManager.getLegendPoolProgress(gameState)
    local canSingle = pulls >= 1 and not cloudBlocked
    local canTen = pulls >= 10 and not cloudBlocked

    local unlockedChildren = {}
    if syncBanner then table.insert(unlockedChildren, syncBanner) end
    table.insert(unlockedChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 10,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                children = {
                    UI.Label {
                        text = "⭐",
                        fontSize = 18, marginRight = 6,
                    },
                    Theme.Subtitle { text = "传奇球星池", marginBottom = 0, color = Theme.COLORS.GOLD },
                },
            },
            UI.Panel {
                backgroundColor = Theme.COLORS.BG_SURFACE,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = Theme.COLORS.SECONDARY,
                paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                children = {
                    UI.Label {
                        text = "已解锁",
                        fontSize = 10,
                        color = Theme.COLORS.SECONDARY,
                        fontWeight = "bold",
                    },
                },
            },
        },
    })
    table.insert(unlockedChildren, _youth()._buildLegendPoolSelector(gameState))
    table.insert(unlockedChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = Theme.COLORS.BG_DARK,
        borderRadius = 10,
        padding = 10,
        marginBottom = 8,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "baseline",
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = "可用次数",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginRight = 6,
                    },
                    UI.Label {
                        text = tostring(pulls),
                        fontSize = 20,
                        color = pulls > 0 and Theme.COLORS.GOLD or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = string.format("池内剩余 %d/%d", poolProgress.remaining, poolProgress.total),
                fontSize = 11,
                color = Theme.COLORS.TEXT_SECONDARY,
            },
        },
    })
    table.insert(unlockedChildren, UI.Label {
        text = string.format(
            "仅在「%s」池内出传奇，十连抽刷新候选名单",
            selectedPool and selectedPool.name_cn or "标签"
        ),
        fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
    })
    table.insert(unlockedChildren, UI.Button {
        text = cloudBlocked and "云存档同步中..."
            or (adProgress > 0 and string.format("看广告赚次数 (%d/%d)", adProgress, adTotal) or "看广告赚次数"),
        width = "100%", height = 34,
        backgroundColor = Theme.COLORS.BG_SURFACE,
        borderRadius = 8,
        borderWidth = 1, borderColor = Theme.COLORS.BORDER,
        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
        marginBottom = 8,
        disabled = cloudBlocked,
        onClick = function()
            if cloudBlocked then
                _youth()._showLegendCloudSyncingToast()
                return
            end
            _youth()._showAdForPullsModal(gameState)
        end,
    })
    table.insert(unlockedChildren, UI.Panel {
        width = "100%",
        flexDirection = "row",
        children = {
            UI.Button {
                text = cloudBlocked and "同步中" or "单抽",
                height = 42, flexGrow = 1,
                backgroundColor = canSingle and Theme.COLORS.PRIMARY or Theme.COLORS.BG_SURFACE,
                borderRadius = 8,
                fontSize = 14,
                color = canSingle and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                fontWeight = "bold",
                marginRight = 8,
                disabled = not canSingle,
                onClick = function()
                    if cloudBlocked then
                        _youth()._showLegendCloudSyncingToast()
                        return
                    end
                    if canSingle then
                        _youth()._doSinglePull(gameState)
                    end
                end,
            },
            UI.Button {
                text = cloudBlocked and "同步中"
                    or (canTen and "十连抽" or ("十连抽 (" .. pulls .. "/10)")),
                height = 42, flexGrow = 1.6,
                backgroundColor = canTen and Theme.COLORS.ACCENT or Theme.COLORS.BG_SURFACE,
                borderRadius = 8,
                fontSize = 15,
                color = canTen and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                fontWeight = "bold",
                disabled = not canTen,
                onClick = function()
                    if cloudBlocked then
                        _youth()._showLegendCloudSyncingToast()
                        return
                    end
                    if canTen then
                        _youth()._doTenPull(gameState)
                    end
                end,
            },
        },
    })
    return Theme.Card { children = unlockedChildren }
end

--- 观看广告解锁
function Tab._watchAdForUnlock(gameState)
    if _youth()._legendCloudMutateBlocked() then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local unlocked, _progress, err = YouthManager.watchAdForUnlock(gameState)
            if err == YouthManager.LEGEND_CLOUD_SYNCING then
                _youth()._showLegendCloudSyncingToast()
                return
            end
            -- 实时存档，防止闪退丢失广告进度
            SaveManager.save(gameState, "auto")
            _youth()._refreshLegendTab()
            -- 广告视频释放后强制 GC，防止连续观看时内存峰值过高
            collectgarbage("collect")
            if unlocked then
                ConfirmDialog.show({
                    title = "传奇球星池已解锁!",
                    message = "恭喜！传奇球星池已解锁，赠送30次抽取机会！\n可在5个叙事标签池中自由切换目标。\n快来召集你心仪的传奇球星吧！",
                    confirmText = "太好了！",
                    confirmColor = Theme.COLORS.ACCENT,
                    onConfirm = function()
                        Router.replaceWith("youth", { tab = "legend" })
                    end,
                })
            else
                Router.replaceWith("youth", { tab = "legend" })
            end
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

--- 显示广告观看弹窗（类似潜力透视的对话框样式）
function Tab._showAdForPullsModal(gameState)
    if _youth()._legendCloudMutateBlocked() then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    local adProgress, adTotal = YouthManager.getPullAdProgress(gameState)
    local gachaState = YouthManager.getLegendGachaState(gameState)
    local currentPulls = gachaState.pulls

    -- 构建进度圆圈
    local circles = {}
    for i = 1, adTotal do
        local done = (i <= adProgress)
        table.insert(circles, UI.Panel {
            width = 36, height = 36,
            borderRadius = 18,
            backgroundColor = done and Theme.COLORS.ACCENT or {60, 65, 90, 255},
            borderWidth = done and 0 or 1,
            borderColor = Theme.COLORS.BORDER,
            justifyContent = "center",
            alignItems = "center",
            marginLeft = i > 1 and 12 or 0,
            children = {
                UI.Label {
                    text = done and "✓" or tostring(i),
                    fontSize = 14,
                    color = done and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                    fontWeight = "bold",
                },
            },
        })
    end

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 180},
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = Theme.COLORS.BG_CARD or {30, 34, 54, 255},
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                paddingTop = 20,
                paddingBottom = 20,
                paddingLeft = 20,
                paddingRight = 20,
                alignItems = "center",
                children = {
                    -- 标题
                    UI.Label {
                        text = "观看广告赚次数",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginBottom = 6,
                    },
                    -- 副标题说明
                    UI.Label {
                        text = "每看1次广告获得3次抽取机会",
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = "看满3次额外奖励6次（本轮共+15）",
                        fontSize = 12,
                        color = Theme.COLORS.ACCENT,
                        marginBottom = 16,
                    },
                    -- 进度圆圈行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        marginBottom = 16,
                        children = circles,
                    },
                    -- 当前状态
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 16,
                        paddingLeft = 8,
                        paddingRight = 8,
                        children = {
                            UI.Label {
                                text = string.format("已观看 %d/%d 次", adProgress, adTotal),
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_SECONDARY,
                            },
                            UI.Label {
                                text = string.format("当前次数: %d", currentPulls),
                                fontSize = 12,
                                color = Theme.COLORS.ACCENT,
                                fontWeight = "bold",
                            },
                        },
                    },
                    -- 观看广告按钮
                    UI.Button {
                        text = "观看广告 (+3次)",
                        width = "100%",
                        height = 42,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 10,
                        fontSize = 14,
                        color = {255, 255, 255, 255},
                        fontWeight = "bold",
                        marginBottom = 10,
                        onClick = function()
                            UI.CloseOverlay()
                            _youth()._doWatchAdInModal(gameState)
                        end,
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%",
                        height = 36,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 10,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            UI.CloseOverlay()
                        end,
                    },
                },
            },
        },
    })
end

--- 在弹窗流程中观看广告并弹出奖励反馈
function Tab._doWatchAdInModal(gameState)
    if _youth()._legendCloudMutateBlocked() then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local newPulls, err = YouthManager.watchAdForPulls(gameState)
            if err == YouthManager.LEGEND_CLOUD_SYNCING then
                _youth()._showLegendCloudSyncingToast()
                return
            end
            -- 实时存档，防止闪退丢失广告进度
            SaveManager.save(gameState, "auto")
            _youth()._refreshLegendTab()
            -- 广告视频释放后强制 GC，防止连续观看时内存峰值过高
            collectgarbage("collect")
            -- 显示奖励反馈弹窗
            _youth()._showAdRewardPopup(gameState, newPulls)
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

--- 广告观看后的奖励反馈弹窗
function Tab._showAdRewardPopup(gameState, newPulls)
    local gachaState = YouthManager.getLegendGachaState(gameState)
    local currentPulls = gachaState.pulls
    local adProgress, adTotal = YouthManager.getPullAdProgress(gameState)

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 180},
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = Theme.COLORS.BG_CARD or {30, 34, 54, 255},
                borderRadius = 16,
                borderWidth = 1,
                borderColor = Theme.COLORS.ACCENT,
                paddingTop = 24,
                paddingBottom = 20,
                paddingLeft = 20,
                paddingRight = 20,
                alignItems = "center",
                children = {
                    -- 奖励图标
                    UI.Label {
                        text = "🎉",
                        fontSize = 32,
                        marginBottom = 10,
                    },
                    -- 奖励标题
                    UI.Label {
                        text = "获得奖励！",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginBottom = 8,
                    },
                    -- 奖励内容
                    UI.Label {
                        text = string.format("+%d 次抽取机会", newPulls),
                        fontSize = 20,
                        color = Theme.COLORS.ACCENT,
                        fontWeight = "bold",
                        marginBottom = 6,
                    },
                    -- 当前总次数
                    UI.Label {
                        text = string.format("当前共 %d 次可用", currentPulls),
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 16,
                    },
                    -- 继续观看 / 返回按钮
                    UI.Button {
                        text = "继续观看",
                        width = "100%",
                        height = 40,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 10,
                        fontSize = 14,
                        color = {255, 255, 255, 255},
                        fontWeight = "bold",
                        marginBottom = 8,
                        onClick = function()
                            UI.CloseOverlay()
                            _youth()._showAdForPullsModal(gameState)
                        end,
                    },
                    UI.Button {
                        text = "返回",
                        width = "100%",
                        height = 36,
                        backgroundColor = {51, 59, 84, 255},
                        borderRadius = 10,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            UI.CloseOverlay()
                            Router.replaceWith("youth", { tab = "legend" })
                        end,
                    },
                },
            },
        },
    })
end

--- 执行单抽
function Tab._doSinglePull(gameState)
    if _youth()._legendCloudMutateBlocked() then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    local candidate, err = YouthManager.doSinglePull(gameState)
    if err == YouthManager.LEGEND_CLOUD_SYNCING then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    if not candidate then return end
    SaveManager.save(gameState, "auto")
    _youth()._refreshLegendTab()

    if candidate.isLegend then
        -- 单抽出传奇：弹出专属揭示弹窗
        _youth()._showLegendReveal(candidate, false)
    else
        UI.Toast.Show({ message = string.format("获得 %s（%s）", candidate.displayName, candidate.position), variant = "success" })
        Router.replaceWith("youth", { tab = "recruit" })
    end
end

--- 执行十连抽
function Tab._doTenPull(gameState)
    if _youth()._legendCloudMutateBlocked() then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    local results, err = YouthManager.doTenPull(gameState)
    if err == YouthManager.LEGEND_CLOUD_SYNCING then
        _youth()._showLegendCloudSyncingToast()
        return
    end
    if not results then return end
    SaveManager.save(gameState, "auto")
    _youth()._refreshLegendTab()

    local legendCount = results.legendCount
    if legendCount > 0 then
        -- 收集传奇球员信息
        local legendPlayer = nil
        for _, c in ipairs(results.candidates) do
            if c.isLegend then
                legendPlayer = c
                break
            end
        end
        _youth()._showLegendReveal(legendPlayer, results.isFirstTenPull)
    else
        ConfirmDialog.show({
            title = "十连抽结果",
            message = "候选池已刷新为10名新球员。\n继续积攒次数，传奇球星在等你！",
            confirmText = "查看候选",
            confirmColor = Theme.COLORS.PRIMARY,
            onConfirm = function()
                Router.replaceWith("youth", { tab = "recruit" })
            end,
        })
    end
end

------------------------------------------------------
-- 传奇球星专属揭示弹窗
------------------------------------------------------
function Tab._showLegendReveal(legendPlayer, isFirstPull)
    local name = legendPlayer.legendName or legendPlayer.displayName or "传奇球星"
    local pos = Constants.POSITION_NAMES[legendPlayer.position] or legendPlayer.position
    local nation = ScoutManager.getNationName(legendPlayer.nationality) or "?"
    local potential = legendPlayer.potential or 95

    -- 传奇标语
    local subtitle = isFirstPull and "传奇降临！" or "欧皇附体！"

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = {0, 0, 0, 220},
        children = {
            UI.Panel {
                width = "92%",
                backgroundColor = {12, 10, 28, 250},
                borderRadius = 24,
                borderWidth = 2,
                borderColor = {255, 215, 0, 180},
                alignItems = "center",
                paddingTop = 20,
                paddingBottom = 20,
                paddingLeft = 16,
                paddingRight = 16,
                children = {
                    -- 顶部标题行
                    UI.Label {
                        text = "★  传奇降临  ★",
                        fontSize = 16,
                        color = {255, 215, 0, 255},
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = subtitle,
                        fontSize = 11,
                        color = {255, 215, 0, 120},
                        textAlign = "center",
                        marginBottom = 12,
                    },
                    -- 传奇球星卡牌立绘
                    UI.Panel {
                        width = "80%",
                        aspectRatio = 3 / 4,
                        borderRadius = 16,
                        overflow = "hidden",
                        marginBottom = 14,
                        backgroundImage = LegendImageRegistry.getPath(legendPlayer.legendData and legendPlayer.legendData.id) or "",
                        backgroundSize = "cover",
                    },
                    -- 球星名字
                    UI.Label {
                        text = name,
                        fontSize = 22,
                        color = {255, 255, 255, 255},
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 10,
                    },
                    -- 信息行：位置 | 国籍 | 潜力 | 星级
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        marginBottom = 16,
                        children = {
                            -- 位置标签
                            UI.Panel {
                                backgroundColor = {255, 215, 0, 50},
                                borderRadius = 6,
                                paddingLeft = 10, paddingRight = 10,
                                paddingTop = 4, paddingBottom = 4,
                                marginRight = 10,
                                children = {
                                    UI.Label {
                                        text = pos,
                                        fontSize = 12,
                                        color = {255, 215, 0, 255},
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Label {
                                text = nation,
                                fontSize = 13,
                                color = {220, 220, 220, 255},
                                marginRight = 10,
                            },
                            UI.Label {
                                text = "潜力 " .. tostring(potential),
                                fontSize = 13,
                                color = {0, 255, 136, 255},
                                fontWeight = "bold",
                                marginRight = 10,
                            },
                            UI.Label {
                                text = "★★★★★",
                                fontSize = 13,
                                color = {255, 215, 0, 255},
                            },
                        },
                    },
                    -- 分割线
                    UI.Panel {
                        width = "70%",
                        height = 1,
                        backgroundColor = {255, 215, 0, 30},
                        marginBottom = 12,
                    },
                    -- 提示
                    UI.Label {
                        text = "候选池已刷新，快去签入吧！",
                        fontSize = 12,
                        color = {160, 160, 160, 255},
                        textAlign = "center",
                        marginBottom = 14,
                    },
                    -- 按钮
                    UI.Button {
                        text = "查看候选",
                        width = "75%",
                        height = 42,
                        backgroundColor = {255, 215, 0, 255},
                        borderRadius = 12,
                        fontSize = 15,
                        color = {20, 16, 36, 255},
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                            Router.replaceWith("youth", { tab = "recruit" })
                        end,
                    },
                },
            },
        },
    })
end

return Tab
