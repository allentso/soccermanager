-- ui/screens/youth.lua
-- 青训学院页面：青训球员列表、候选招募、提拔/释放

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local YouthManager = require("scripts/systems/youth_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local LegendImageRegistry = require("scripts/data/legend_image_registry")
local SaveManager = require("scripts/persistence/save_manager")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local Youth = {}

--- 子目录标签（在路由切换间保留）：recruit=招募(候选+传奇) / squad=青训球员
local _activeTab = "recruit"

--- 叙事标签池 UI 配置
local LEGEND_POOL_UI = {
    prince = { icon = "👑", short = "王子旗帜" },
    nation = { icon = "🏆", short = "国家英雄" },
    club = { icon = "🏟", short = "俱乐部" },
    wanderer = { icon = "🌍", short = "流浪大师" },
    myth = { icon = "✨", short = "神话远方" },
}

------------------------------------------------------
-- 潜力星级显示（1-5星，球探能力影响准确度）
------------------------------------------------------
--- 将潜力转换为星级显示（基于球探能力的准确度）
--- @param potential number 球员潜力值
--- @param scoutAccuracy number 球探准确度 (0.0-1.0)
--- @return number stars 星数 (1-5)
--- @return string display 星级显示字符串
local function getPotentialStars(potential, scoutAccuracy)
    -- 若已解锁潜力透视，直接显示精确值
    local gs = _G.gameState
    if gs and gs.potentialRevealed then
        local paRating = PotentialSystem.rawToRating(potential)
        local text = string.format("%.1f", paRating)
        return 5, text
    end

    -- 基于 paRating (1.0-10.0) 映射到 1-5 星
    local paRating = PotentialSystem.rawToRating(potential)
    -- paRating 1.0-10.0 → 星数 1-5
    local exactStars = (paRating - 1.0) / 9.0 * 4.0 + 1.0  -- 1.0→1星, 10.0→5星

    -- 球探能力引入误差：准确度越低，随机偏移越大
    local accuracy = scoutAccuracy or 0.6
    local maxError = (1.0 - accuracy) * 1.5  -- 准确度0.6 → 最大偏差0.6星，准确度1.0 → 0偏差
    -- 使用确定性偏移（基于潜力值本身作为种子，保证同一球员显示稳定）
    local seed = potential * 7 + 13
    local pseudoRandom = (math.sin(seed) * 10000) % 1.0  -- 0~1 伪随机
    local errorOffset = (pseudoRandom - 0.5) * 2 * maxError  -- -maxError ~ +maxError

    local displayStars = math.floor(exactStars + errorOffset + 0.5)
    displayStars = math.max(1, math.min(5, displayStars))

    -- 生成星号文本
    local starText = string.rep("★", displayStars) .. string.rep("☆", 5 - displayStars)
    return displayStars, starText
end

--- 获取当前球队的球探准确度
local function getTeamScoutAccuracy(gameState)
    return ScoutManager.getAccuracy(gameState)
end

------------------------------------------------------
-- 主页面
------------------------------------------------------
function Youth.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel{} end

    local youthSquad = YouthManager.getYouthSquad(gameState)
    local candidates = YouthManager.getCandidates(gameState)
    local playerTeam = gameState:getPlayerTeam()
    local maxYouthSquad = playerTeam
        and YouthManager.getMaxYouthSquad(gameState, playerTeam)
        or YouthManager.MAX_YOUTH_SQUAD

    -- 支持通过路由参数指定初始子目录
    if params and params.tab then
        _activeTab = params.tab
    end

    -- 子目录内容：招募(候选+传奇) / 青训球员
    local tabContent
    if _activeTab == "squad" then
        tabContent = {
            Youth._buildSquadSection(youthSquad, gameState),
        }
    else
        tabContent = {
            Youth._buildOrphanReclaimBanner(gameState),
            Youth._buildLegendGachaSection(gameState),
            Youth._buildCandidatesSection(candidates, gameState),
        }
    end

    local children = {
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
                    text = "青训学院",
                    fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                    fontWeight = "bold", flexGrow = 1, textAlign = "center",
                },
                UI.Label {
                    text = string.format("%d/%d人", #youthSquad, maxYouthSquad),
                    fontSize = 12, color = Theme.COLORS.TEXT_MUTED, minWidth = 60, textAlign = "right",
                },
            }
        },
        Theme.SquadSubNav("youth"),
        -- 三级子目录：招募 / 青训球员
        Youth._buildTabBar(#candidates, #youthSquad),
        UI.Panel {
            width = "100%", flexGrow = 1,
            padding = 12,
            overflow = "scroll",
            children = (function()
                -- 青训概览卡片始终置顶，下方按子目录切换内容
                local items = { Youth._buildSummaryCard(youthSquad, maxYouthSquad) }
                for _, node in ipairs(tabContent) do
                    table.insert(items, node)
                end
                return items
            end)(),
        },
        Theme.MainNav("squad"),
    }

    return UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = Theme.COLORS.BG_MAIN,
        children = children,
    }
end

------------------------------------------------------
-- 三级子目录标签栏（招募 / 青训球员）
------------------------------------------------------
function Youth._buildTabBar(candidateCount, youthCount)
    local tabs = {
        { key = "recruit", label = "招募", count = candidateCount },
        { key = "squad",   label = "青训球员", count = youthCount },
    }

    local buttons = {}
    for _, tab in ipairs(tabs) do
        local isActive = (tab.key == _activeTab)
        local labelText = tab.label
        if tab.count and tab.count > 0 then
            labelText = labelText .. " " .. tostring(tab.count)
        end
        table.insert(buttons, UI.Button {
            text = labelText,
            height = 30,
            paddingLeft = 14, paddingRight = 14,
            backgroundColor = isActive and Theme.COLORS.GOLD or Theme.COLORS.TRANSPARENT,
            borderRadius = 15,
            fontSize = 13,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 8,
            onClick = function()
                if not isActive then
                    _activeTab = tab.key
                    Router.replaceWith("youth")
                end
            end,
        })
    end

    return UI.Panel {
        width = "100%", height = 40,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = Theme.COLORS.BG_CARD,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = buttons,
    }
end

------------------------------------------------------
-- 概览卡片
------------------------------------------------------
function Youth._buildSummaryCard(youthSquad, maxYouthSquad)
    maxYouthSquad = maxYouthSquad or YouthManager.MAX_YOUTH_SQUAD
    local count = #youthSquad
    local avgOvr = 0
    local avgPot = 0
    if count > 0 then
        local totalOvr, totalPot = 0, 0
        for _, p in ipairs(youthSquad) do
            totalOvr = totalOvr + (p.overall or 0)
            totalPot = totalPot + (p.potential or 0)
        end
        avgOvr = math.floor(totalOvr / count)
        avgPot = math.floor(totalPot / count)
    end

    return Theme.Card {
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginBottom = 8,
                children = {
                    Theme.Title { text = "青训学院", marginBottom = 0 },
                    UI.Label {
                        text = string.format("%d / %d 名额", count, maxYouthSquad),
                        fontSize = 12,
                        color = count >= maxYouthSquad and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                children = {
                    Theme.StatPill { label = "人数", value = tostring(count) },
                    Theme.StatPill { label = "平均能力", value = count > 0 and tostring(avgOvr) or "-" },
                    Theme.StatPill { label = "平均潜力", value = count > 0 and "★" .. string.format("%.1f", avgPot > 0 and ((PotentialSystem.rawToRating(avgPot) - 1.0) / 9.0 * 4.0 + 1.0) or 0) or "-",
                        valueColor = Theme.COLORS.ACCENT },
                },
            },
        }
    }
end

------------------------------------------------------
-- 候选招募区域
------------------------------------------------------
function Youth._buildCandidatesSection(candidates, gameState)
    if #candidates == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "候选球员" },
                UI.Label {
                    text = "暂无候选球员，球探每月会发现新的青年球员。",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 8,
                },
            },
        }
    end

    local rows = {}
    table.insert(rows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        marginBottom = 4,
        children = {
            Theme.Subtitle { text = "候选球员", marginBottom = 0 },
            UI.Label {
                text = tostring(#candidates) .. "人可签入",
                fontSize = 11,
                color = Theme.COLORS.ACCENT,
            },
        },
    })
    -- 球探偏差提示
    table.insert(rows, UI.Label {
        text = "* 数据为球探预估，签入后实际能力可能略有偏差",
        fontSize = 10,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 8,
    })

    for i, candidate in ipairs(candidates) do
        table.insert(rows, Youth._buildCandidateCard(candidate, i, gameState))
    end

    return Theme.Card { children = rows }
end

function Youth._buildCandidateCard(candidate, index, gameState)
    local posColor = Theme.posColor(candidate.position)

    -- 潜力星级
    local scoutAccuracy = getTeamScoutAccuracy(gameState)
    local potStars, potStarText = getPotentialStars(candidate.potential, scoutAccuracy)
    local potColor = Theme.COLORS.TEXT_MUTED
    if potStars >= 4 then potColor = Theme.COLORS.ACCENT
    elseif potStars >= 3 then potColor = Theme.COLORS.SECONDARY
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 位置徽章（与阵容页统一样式）
            UI.Panel {
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[candidate.position] or candidate.position,
                        fontSize = 10, color = posColor, fontWeight = "bold",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = candidate.displayName,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("%d岁 | %s | 能力%d",
                            candidate.age,
                            ScoutManager.getNationName(candidate.nationality) or "?",
                            candidate.overall),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 潜力星级
            UI.Panel {
                alignItems = "center",
                marginRight = 10,
                children = {
                    UI.Label {
                        text = potStarText,
                        fontSize = 12,
                        color = potColor,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "潜力",
                        fontSize = 9,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 签入按钮
            UI.Button {
                text = "签入",
                width = 52,
                height = 28,
                backgroundColor = Theme.COLORS.SECONDARY,
                borderRadius = 6,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                onClick = function()
                    Youth._confirmSign(candidate, index, gameState)
                end,
            },
        },
    }
end

------------------------------------------------------
-- 签入确认
------------------------------------------------------
function Youth._confirmSign(candidate, index, gameState)
    local scoutAccuracy = getTeamScoutAccuracy(gameState)
    local _, potStarText = getPotentialStars(candidate.potential, scoutAccuracy)
    ConfirmDialog.showWithDetails({
        title = "签入青训球员",
        details = {
            { label = "姓名", value = candidate.displayName },
            { label = "位置", value = Constants.POSITION_NAMES[candidate.position] or candidate.position },
            { label = "年龄", value = tostring(candidate.age) .. "岁" },
            { label = "能力", value = tostring(candidate.overall) },
            { label = "潜力", value = potStarText, valueColor = Theme.COLORS.ACCENT },
            { label = "周薪", value = FinanceManager.formatMoney(500) },
            { label = "合同", value = "3年" },
        },
        confirmText = "确认签入",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, err = YouthManager.signCandidate(gameState, index)
            if ok then
                SaveManager.save(gameState, "auto")
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "签入失败",
                    message = err or "无法签入该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end

------------------------------------------------------
-- 青训球员列表
------------------------------------------------------
function Youth._buildSquadSection(youthSquad, gameState)
    if #youthSquad == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "青训球员" },
                UI.Label {
                    text = "还没有青训球员，从候选列表中签入球员开始培养吧。",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                    marginTop = 8,
                },
            },
        }
    end

    local rows = {}
    table.insert(rows, Theme.Subtitle { text = string.format("青训球员 (%d人)", #youthSquad) })

    for _, player in ipairs(youthSquad) do
        table.insert(rows, Youth._buildYouthPlayerRow(player, gameState))
    end

    return Theme.Card { children = rows }
end

function Youth._buildYouthPlayerRow(player, gameState)
    local posColor = Theme.posColor(player.position)

    local effectivePot = player.actualPotential or player.potential or 0
    local scoutAccuracy = getTeamScoutAccuracy(gameState)
    local potStars, potStarText = getPotentialStars(effectivePot, scoutAccuracy)
    local potColor = Theme.COLORS.TEXT_MUTED
    if potStars >= 4 then potColor = Theme.COLORS.ACCENT
    elseif potStars >= 3 then potColor = Theme.COLORS.SECONDARY
    end

    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8,
        paddingBottom = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        onClick = function()
            Youth._showYouthActions(player, gameState)
        end,
        children = {
            -- 位置徽章（与阵容页统一样式）
            UI.Panel {
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                marginRight = 8,
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[player.position] or player.position,
                        fontSize = 10, color = posColor, fontWeight = "bold",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = player.displayName or (player.firstName .. " " .. player.lastName),
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = string.format("%d岁 | 能力%d | 潜力%s%s",
                            age, math.min(Constants.ABILITY_MAX, player.overall or 0), potStarText,
                            player.listedForSale and " | 挂牌中" or ""),
                        fontSize = 11,
                        color = player.listedForSale and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 能力/潜力星级
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        marginRight = 6,
                    },
                    UI.Label {
                        text = "→",
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginRight = 6,
                    },
                    UI.Label {
                        text = potStarText,
                        fontSize = 12,
                        color = potColor,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

------------------------------------------------------
-- 球员操作菜单
------------------------------------------------------
function Youth._showYouthActions(player, gameState)
    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0
    local actions = {}

    -- 提拔
    table.insert(actions, {
        label = "提拔至一线队",
        color = Theme.COLORS.SECONDARY,
        action = function()
            Youth._confirmPromote(player, gameState)
        end,
    })

    -- 查看详情
    table.insert(actions, {
        label = "查看详情",
        color = Theme.COLORS.TEXT_PRIMARY,
        action = function()
            UI.CloseOverlay()
            Router.navigate("player_detail", { playerId = player.id, tab = "contract" })
        end,
    })

    -- 挂牌出售 / 取消挂牌
    if player.listedForSale then
        table.insert(actions, {
            label = "取消挂牌出售",
            color = Theme.COLORS.TEXT_MUTED,
            action = function()
                TransferManager.delistPlayer(gameState, player)
                Router.replaceWith("youth")
            end,
        })
    else
        table.insert(actions, {
            label = "挂牌出售",
            color = Theme.COLORS.ACCENT,
            action = function()
                local ok, err = TransferManager.listForSale(gameState, player)
                if not ok then
                    local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                    if TransferLimitDialog.handleError(err, player.displayName, gameState) then
                        return
                    end
                    ConfirmDialog.show({
                        title = "无法挂牌",
                        message = err or "条件不满足",
                        confirmText = "知道了",
                        confirmColor = Theme.COLORS.TEXT_MUTED,
                        onConfirm = function() end,
                    })
                else
                    Router.replaceWith("youth")
                end
            end,
        })
    end

    -- 处理收到的出售报价（与详情页/市场一致，取主报价）
    local bid = TransferManager.pickPrimaryIncomingSaleBid(gameState, player.id)
    if bid then
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local buyerName = buyerTeam and buyerTeam.name or "未知球队"
        if bid.status == "pending" then
            table.insert(actions, {
                label = string.format("接受报价 %s", buyerName),
                color = Theme.COLORS.SECONDARY,
                action = function()
                    local ok = TransferManager.acceptIncomingBid(gameState, bid.id)
                    if ok then
                        UI.Toast.Show({ message = "已同意报价，等待球员考虑是否接受转会", variant = "success" })
                    else
                        UI.Toast.Show({ message = "无法接受该报价", variant = "warning" })
                    end
                    Router.replaceWith("market", { tab = "listed" })
                end,
            })
            table.insert(actions, {
                label = string.format("拒绝报价 %s", buyerName),
                color = Theme.COLORS.DANGER,
                action = function()
                    TransferManager.rejectIncomingBid(gameState, bid.id)
                    Router.replaceWith("youth")
                end,
            })
        elseif bid.status == "awaiting_sale_confirmation" then
            table.insert(actions, {
                label = string.format("确认出售给 %s", buyerName),
                color = Theme.COLORS.SECONDARY,
                action = function()
                    Router.replaceWith("market", { tab = "listed", highlightBidId = bid.id })
                end,
            })
            table.insert(actions, {
                label = string.format("取消出售（%s）", buyerName),
                color = Theme.COLORS.DANGER,
                action = function()
                    TransferManager.cancelSale(gameState, bid.id)
                    Router.replaceWith("youth")
                end,
            })
        elseif bid.status == "player_considering_sale" or bid.status == "counter_pending" then
            table.insert(actions, {
                label = string.format("查看报价进度（%s）", buyerName),
                color = Theme.COLORS.ACCENT,
                action = function()
                    Router.replaceWith("market", { tab = "listed", highlightBidId = bid.id })
                end,
            })
        end
    end

    -- 释放
    table.insert(actions, {
        label = "释放球员",
        color = Theme.COLORS.DANGER,
        action = function()
            Youth._confirmRelease(player, gameState)
        end,
    })

    -- 构建 overlay
    local items = {}
    for _, act in ipairs(actions) do
        table.insert(items, UI.Button {
            text = act.label,
            width = "100%",
            height = 44,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            fontSize = 14,
            color = act.color,
            marginBottom = 6,
            onClick = function()
                UI.CloseOverlay()
                act.action()
            end,
        })
    end

    table.insert(items, UI.Button {
        text = "取消",
        width = "100%",
        height = 44,
        backgroundColor = {51, 59, 84, 255},
        borderRadius = 8,
        fontSize = 14,
        color = Theme.COLORS.TEXT_SECONDARY,
        marginTop = 4,
        onClick = function() UI.CloseOverlay() end,
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%",
        height = "100%",
        justifyContent = "flex-end",
        backgroundColor = {0, 0, 0, 150},
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_SECONDARY or {24, 28, 44, 255},
                borderRadius = 16,
                paddingTop = 20,
                paddingBottom = 24,
                paddingLeft = 16,
                paddingRight = 16,
                children = {
                    -- 顶部把手
                    UI.Panel {
                        width = 36,
                        height = 4,
                        backgroundColor = {100, 100, 120, 255},
                        borderRadius = 2,
                        alignSelf = "center",
                        marginBottom = 14,
                    },
                    UI.Label {
                        text = player.displayName or "",
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 16,
                    },
                    table.unpack(items),
                },
            },
        },
    })
end

------------------------------------------------------
-- 提拔确认
------------------------------------------------------
function Youth._confirmPromote(player, gameState)
    local age = player.birthYear and math.floor(gameState.date.year - player.birthYear) or 0
    local newWage = math.max(1000, math.floor((player.overall or 0) * 80))
    local scoutAccuracy = getTeamScoutAccuracy(gameState)
    local _, potStarText = getPotentialStars(player.actualPotential or player.potential or 0, scoutAccuracy)

    ConfirmDialog.showWithDetails({
        title = "提拔至一线队",
        details = {
            { label = "姓名", value = player.displayName or "" },
            { label = "位置", value = Constants.POSITION_NAMES[player.position] or player.position },
            { label = "年龄", value = tostring(age) .. "岁" },
            { label = "能力", value = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)) },
            { label = "潜力", value = potStarText, valueColor = Theme.COLORS.ACCENT },
            { label = "新周薪", value = FinanceManager.formatMoney(newWage), valueColor = Theme.COLORS.WARNING },
            { label = "合同", value = "3年" },
        },
        confirmText = "确认提拔",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, err = YouthManager.promote(gameState, player.id)
            if ok then
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "提拔失败",
                    message = err or "无法提拔该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end

------------------------------------------------------
-- 释放确认
------------------------------------------------------
function Youth._confirmRelease(player, gameState)
    ConfirmDialog.show({
        title = "释放青训球员",
        message = string.format("确定要释放 %s 吗？\n该操作不可撤销。",
            player.displayName or ""),
        confirmText = "确认释放",
        confirmColor = Theme.COLORS.DANGER,
        onConfirm = function()
            local ok, err = YouthManager.release(gameState, player.id)
            if ok then
                Router.replaceWith("youth")
            else
                ConfirmDialog.show({
                    title = "释放失败",
                    message = err or "无法释放该球员",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function() end,
                })
            end
        end,
    })
end

------------------------------------------------------
-- 传奇球星池抽卡入口
------------------------------------------------------

--- 构建标签池选择器（解锁后可随时切换）
function Youth._buildLegendPoolSelector(gameState)
    local selectedId = YouthManager.getSelectedLegendPoolId(gameState)
    local pools = YouthManager.getLegendTagPools()
    local chips = {}

    for _, pool in ipairs(pools) do
        local ui = LEGEND_POOL_UI[pool.id] or { icon = "⭐", short = pool.name_cn }
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
                if pool.id ~= selectedId then
                    YouthManager.setSelectedLegendPool(gameState, pool.id)
                    SaveManager.save(gameState, "auto")
                    Router.replaceWith("youth")
                end
            end,
        })
    end

    local selectedPool = YouthManager.getSelectedLegendPool(gameState)
    local selectedProgress = YouthManager.getLegendPoolProgress(gameState, selectedId)
    local statusText
    if selectedProgress.exhausted then
        statusText = "该标签池已全部收集，切换其他池继续抽传奇，或仍可抽普通青训。"
    else
        statusText = string.format(
            "当前：%s · 还可抽 %d 名传奇",
            selectedPool and selectedPool.name_cn or "",
            selectedProgress.remaining
        )
    end

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
                            Youth._showLegendPoolListModal(gameState, selectedId)
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
                marginBottom = 4,
            },
            UI.Label {
                text = statusText,
                fontSize = 10,
                color = selectedProgress.exhausted and Theme.COLORS.GOLD or Theme.COLORS.ACCENT,
            },
        },
    }
end

------------------------------------------------------
-- 传奇池名单弹窗（查看某标签池内全部传奇及收集状态）
------------------------------------------------------
function Youth._showLegendPoolListModal(gameState, poolId)
    local pools = YouthManager.getLegendTagPools()
    local poolMeta
    for _, p in ipairs(pools) do
        if p.id == poolId then poolMeta = p; break end
    end
    local poolUi = LEGEND_POOL_UI[poolId] or { icon = "⭐" }
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
function Youth._buildOrphanReclaimBanner(gameState)
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
                            Youth._showOrphanReclaimModal(gameState)
                        end,
                    },
                },
            },
        },
    }
end

function Youth._showOrphanReclaimModal(gameState)
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
                            Router.replaceWith("youth", { tab = "recruit" })
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

function Youth._buildLegendGachaSection(gameState)
    local gachaState = YouthManager.getLegendGachaState(gameState)

    -- 未解锁状态：显示进度条和观看广告按钮
    if not gachaState.unlocked then
        local progress = gachaState.adsWatched
        local total = YouthManager.getUnlockAdsRequired()
        local progressPct = math.floor(progress / total * 100)

        return Theme.Card {
            children = {
                UI.Panel {
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
                },
                -- 进度条
                UI.Panel {
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
                },
                UI.Label {
                    text = "观看广告解锁传奇抽卡，解锁后可在5个叙事标签池中自由选择！",
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
                },
                UI.Button {
                    text = "观看广告 (" .. progress .. "/" .. total .. ")",
                    width = "100%", height = 36,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 8,
                    fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                    fontWeight = "bold",
                    onClick = function()
                        Youth._watchAdForUnlock(gameState)
                    end,
                },
            },
        }
    end

    -- 已解锁状态：显示抽取次数和十连抽按钮
    local pulls = gachaState.pulls
    local adProgress, adTotal = YouthManager.getPullAdProgress(gameState)

    local selectedPool = YouthManager.getSelectedLegendPool(gameState)
    local poolProgress = YouthManager.getLegendPoolProgress(gameState)
    local canSingle = pulls >= 1
    local canTen = pulls >= 10

    return Theme.Card {
        children = {
            -- 标题行
            UI.Panel {
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
                    -- 已解锁徽章
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
            },
            -- 池选择器
            Youth._buildLegendPoolSelector(gameState),
            -- 资源条：可用次数（突出）+ 池内剩余
            UI.Panel {
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
            },
            -- 规则说明
            UI.Label {
                text = string.format(
                    "仅在「%s」池内出传奇，十连抽刷新候选名单",
                    selectedPool and selectedPool.name_cn or "标签"
                ),
                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
            },
            -- 看广告赚次数（整行）
            UI.Button {
                text = adProgress > 0
                    and string.format("看广告赚次数 (%d/%d)", adProgress, adTotal)
                    or "看广告赚次数",
                width = "100%", height = 34,
                backgroundColor = Theme.COLORS.BG_SURFACE,
                borderRadius = 8,
                borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 8,
                onClick = function()
                    Youth._showAdForPullsModal(gameState)
                end,
            },
            -- 抽卡按钮行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    -- 单抽按钮
                    UI.Button {
                        text = "单抽",
                        height = 42, flexGrow = 1,
                        backgroundColor = canSingle and Theme.COLORS.PRIMARY or Theme.COLORS.BG_SURFACE,
                        borderRadius = 8,
                        fontSize = 14,
                        color = canSingle and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                        marginRight = 8,
                        disabled = not canSingle,
                        onClick = function()
                            if canSingle then
                                Youth._doSinglePull(gameState)
                            end
                        end,
                    },
                    -- 十连抽按钮
                    UI.Button {
                        text = canTen and "十连抽" or ("十连抽 (" .. pulls .. "/10)"),
                        height = 42, flexGrow = 1.6,
                        backgroundColor = canTen and Theme.COLORS.ACCENT or Theme.COLORS.BG_SURFACE,
                        borderRadius = 8,
                        fontSize = 15,
                        color = canTen and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                        disabled = not canTen,
                        onClick = function()
                            if canTen then
                                Youth._doTenPull(gameState)
                            end
                        end,
                    },
                },
            },
        },
    }
end

--- 观看广告解锁
function Youth._watchAdForUnlock(gameState)
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local unlocked, _progress = YouthManager.watchAdForUnlock(gameState)
            -- 实时存档，防止闪退丢失广告进度
            SaveManager.save(gameState, "auto")
            -- 广告视频释放后强制 GC，防止连续观看时内存峰值过高
            collectgarbage("collect")
            if unlocked then
                ConfirmDialog.show({
                    title = "传奇球星池已解锁!",
                    message = "恭喜！传奇球星池已解锁，赠送30次抽取机会！\n可在5个叙事标签池中自由切换目标。\n快来召集你心仪的传奇球星吧！",
                    confirmText = "太好了！",
                    confirmColor = Theme.COLORS.ACCENT,
                    onConfirm = function()
                        Router.replaceWith("youth")
                    end,
                })
            else
                Router.replaceWith("youth")
            end
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

--- 显示广告观看弹窗（类似潜力透视的对话框样式）
function Youth._showAdForPullsModal(gameState)
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
                            Youth._doWatchAdInModal(gameState)
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
function Youth._doWatchAdInModal(gameState)
    if not sdk then
        UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local newPulls = YouthManager.watchAdForPulls(gameState)
            -- 实时存档，防止闪退丢失广告进度
            SaveManager.save(gameState, "auto")
            -- 广告视频释放后强制 GC，防止连续观看时内存峰值过高
            collectgarbage("collect")
            -- 显示奖励反馈弹窗
            Youth._showAdRewardPopup(gameState, newPulls)
        else
            UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
        end
    end)
end

--- 广告观看后的奖励反馈弹窗
function Youth._showAdRewardPopup(gameState, newPulls)
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
                            Youth._showAdForPullsModal(gameState)
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
                            Router.replaceWith("youth")
                        end,
                    },
                },
            },
        },
    })
end

--- 执行单抽
function Youth._doSinglePull(gameState)
    local candidate = YouthManager.doSinglePull(gameState)
    if not candidate then return end
    SaveManager.save(gameState, "auto")

    if candidate.isLegend then
        -- 单抽出传奇：弹出专属揭示弹窗
        Youth._showLegendReveal(candidate, false)
    else
        UI.Toast.Show({ message = string.format("获得 %s（%s）", candidate.displayName, candidate.position), variant = "success" })
        Router.replaceWith("youth")
    end
end

--- 执行十连抽
function Youth._doTenPull(gameState)
    local results = YouthManager.doTenPull(gameState)
    if not results then return end
    SaveManager.save(gameState, "auto")

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
        Youth._showLegendReveal(legendPlayer, results.isFirstTenPull)
    else
        ConfirmDialog.show({
            title = "十连抽结果",
            message = "候选池已刷新为10名新球员。\n继续积攒次数，传奇球星在等你！",
            confirmText = "查看候选",
            confirmColor = Theme.COLORS.PRIMARY,
            onConfirm = function()
                Router.replaceWith("youth")
            end,
        })
    end
end

------------------------------------------------------
-- 传奇球星专属揭示弹窗
------------------------------------------------------
function Youth._showLegendReveal(legendPlayer, isFirstPull)
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
                            Router.replaceWith("youth")
                        end,
                    },
                },
            },
        },
    })
end

return Youth
