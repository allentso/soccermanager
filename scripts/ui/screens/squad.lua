-- ui/screens/squad.lua
-- 阵容页面 - 增强版：筛选/排序/操作菜单

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local SaveManager = require("scripts/persistence/save_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local ContractManager = require("scripts/systems/contract_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local TransferManager = require("scripts/systems/transfer_manager")

local Squad = {}

-- 筛选和排序状态（在路由切换间保留）
local _filterPos = "ALL"  -- ALL / GK / DEF / MID / FWD
local _sortBy = "position" -- position / overall / age / wage / fitness

-- 位置筛选选项
local FILTER_OPTIONS = {
    { key = "ALL", label = "全部" },
    { key = "GK",  label = "门将" },
    { key = "DEF", label = "后卫" },
    { key = "MID", label = "中场" },
    { key = "FWD", label = "前锋" },
}

-- 排序选项
local SORT_OPTIONS = {
    { key = "position", label = "位置" },
    { key = "overall",  label = "能力" },
    { key = "age",      label = "年龄" },
    { key = "wage",     label = "工资" },
    { key = "fitness",  label = "体能" },
}

-- 位置分类映射
local POS_GROUP_MAP = {
    GK = "GK",
    CB = "DEF", LB = "DEF", RB = "DEF",
    CDM = "MID", CM = "MID", LM = "MID", RM = "MID", CAM = "MID",
    LW = "FWD", RW = "FWD", ST = "FWD", CF = "FWD",
}

function Squad.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local team = gameState:getPlayerTeam()
    if not team then return UI.Panel { width = "100%", height = "100%" } end

    -- 获取球员列表
    local allPlayers = gameState:getTeamPlayers(gameState.playerTeamId)

    -- 筛选
    local players = {}
    for _, p in ipairs(allPlayers) do
        if _filterPos == "ALL" or POS_GROUP_MAP[p.position] == _filterPos then
            table.insert(players, p)
        end
    end

    -- 排序
    local posOrder = {GK=1, CB=2, LB=3, RB=4, CDM=5, CM=6, LM=7, RM=8, CAM=9, LW=10, RW=11, CF=12, ST=13}
    table.sort(players, function(a, b)
        if _sortBy == "position" then
            local oa = posOrder[a.position] or 99
            local ob = posOrder[b.position] or 99
            if oa ~= ob then return oa < ob end
            return a.overall > b.overall
        elseif _sortBy == "overall" then
            return a.overall > b.overall
        elseif _sortBy == "age" then
            return a.birthYear > b.birthYear  -- 年轻在前
        elseif _sortBy == "wage" then
            return (a.wage or 0) > (b.wage or 0)
        elseif _sortBy == "fitness" then
            return (a.fitness or 0) < (b.fitness or 0)  -- 低体能在前（关注）
        end
        return a.overall > b.overall
    end)

    -- 标记首发
    local startingSet = {}
    for _, pid in ipairs(team.startingXI) do
        startingSet[pid] = true
    end

    -- 统计
    local starterCount = #team.startingXI
    local injuredCount = 0
    local lowFitnessCount = 0
    for _, p in ipairs(allPlayers) do
        if p.injured then injuredCount = injuredCount + 1 end
        if p.fitness and p.fitness < 70 then lowFitnessCount = lowFitnessCount + 1 end
    end

    -- 构建筛选标签
    local filterTabs = {}
    for _, opt in ipairs(FILTER_OPTIONS) do
        local isActive = opt.key == _filterPos
        table.insert(filterTabs, UI.Button {
            text = opt.label,
            height = 28,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 14,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 4,
            onClick = function()
                _filterPos = opt.key
                Router.replaceWith("squad")
            end,
        })
    end

    -- 构建排序标签
    local sortTabs = {}
    for _, opt in ipairs(SORT_OPTIONS) do
        local isActive = opt.key == _sortBy
        table.insert(sortTabs, UI.Button {
            text = isActive and (opt.label .. "▼") or opt.label,
            height = 26,
            paddingLeft = 8, paddingRight = 8,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            fontSize = 11,
            color = isActive and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 2,
            onClick = function()
                _sortBy = opt.key
                Router.replaceWith("squad")
            end,
        })
    end

    -- 预计算有报价的球员集合（避免在循环中频繁调用）
    local pendingBidSet = {}
    do
        local ok, bids = pcall(TransferManager.getPendingSellBids, gameState)
        if ok and bids then
            for _, bid in ipairs(bids) do
                if bid.isIncomingBid and bid.status == "pending" then
                    pendingBidSet[bid.playerId] = true
                end
            end
        end
    end

    -- 构建球员行
    local playerRows = {}
    for _, p in ipairs(players) do
        local isStarter = startingSet[p.id] or false
        local age = p:getAge(gameState.date.year)

        -- 位置颜色
        local posColor = Theme.COLORS.TEXT_SECONDARY
        local group = POS_GROUP_MAP[p.position]
        if group == "GK" then posColor = {255, 204, 0, 255}
        elseif group == "DEF" then posColor = {77, 179, 255, 255}
        elseif group == "MID" then posColor = {102, 255, 128, 255}
        elseif group == "FWD" then posColor = {255, 102, 102, 255}
        end

        -- 状态图标
        local statusText = ""
        local statusColor = Theme.COLORS.TEXT_MUTED
        if p.injured then
            statusText = "伤"
            statusColor = Theme.COLORS.DANGER
        elseif pendingBidSet[p.id] then
            statusText = "报价"
            statusColor = Theme.COLORS.ACCENT
        elseif p.listedForSale then
            statusText = "售"
            statusColor = Theme.COLORS.WARNING
        elseif p.fitness and p.fitness < 60 then
            statusText = "疲"
            statusColor = Theme.COLORS.DANGER
        elseif p.fitness and p.fitness < 75 then
            statusText = "疲"
            statusColor = Theme.COLORS.WARNING
        elseif p.morale and p.morale < 40 then
            statusText = "低"
            statusColor = Theme.COLORS.WARNING
        end

        -- 合同到期提示
        local contractWarn = ""
        if p.contractEnd then
            local monthsLeft = (p.contractEnd.year - gameState.date.year) * 12
                + (p.contractEnd.month - gameState.date.month)
            if monthsLeft <= 6 then
                contractWarn = "!"
            end
        end

        table.insert(playerRows, UI.Panel {
            width = "100%",
            height = 54,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isStarter and {31, 46, 71, 255} or {0, 0, 0, 0},
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                -- 首发标记
                UI.Label {
                    text = isStarter and "★" or "  ",
                    fontSize = 11,
                    color = Theme.COLORS.ACCENT,
                    width = 18,
                },
                -- 位置
                UI.Label {
                    text = p.position,
                    fontSize = 12,
                    color = posColor,
                    width = 36,
                    fontWeight = "bold",
                },
                -- 姓名 + 角色 + 合同到期提示
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = p.displayName .. (contractWarn ~= "" and " ⚠" or ""),
                                    fontSize = 13,
                                    color = Theme.COLORS.TEXT_PRIMARY,
                                },
                                (p.squadRole == "key") and UI.Label {
                                    text = " ★",
                                    fontSize = 11,
                                    color = {255, 200, 50, 255},
                                } or UI.Panel { width = 0 },
                            },
                        },
                        -- 次要信息行
                        UI.Label {
                            text = string.format("%d岁 | %s%s/周",
                                age,
                                p.wage >= 1000 and string.format("%.0fK", p.wage/1000) or tostring(p.wage),
                                ""
                            ),
                            fontSize = 10,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 1,
                        },
                    }
                },
                -- 体能柱
                UI.Panel {
                    width = 30, height = 30,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label {
                            text = tostring(p.fitness or 0),
                            fontSize = 10,
                            color = (p.fitness or 80) >= 75 and Theme.COLORS.SECONDARY
                                or ((p.fitness or 80) >= 60 and Theme.COLORS.WARNING or Theme.COLORS.DANGER),
                        },
                    }
                },
                -- 能力
                UI.Label {
                    text = tostring(p.overall),
                    fontSize = 14,
                    color = p.overall >= 75 and Theme.COLORS.SECONDARY
                        or (p.overall >= 65 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY),
                    width = 28,
                    fontWeight = "bold",
                    textAlign = "center",
                },
                -- 状态
                UI.Label {
                    text = statusText,
                    fontSize = 11,
                    color = statusColor,
                    width = 30,
                    textAlign = "center",
                },
            },
            onClick = function()
                Router.navigate("player_detail", { playerId = p.id })
            end,
            onLongPress = function()
                Squad._showActionMenu(p, isStarter, team, gameState)
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
                        text = "阵容",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    -- 球队概要
                    UI.Label {
                        text = string.format("%d人", #allPlayers),
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 50, textAlign = "right",
                    },
                }
            },

            -- 二级导航
            Theme.SquadSubNav("squad"),

            -- 状态统计栏
            UI.Panel {
                width = "100%", height = 36,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = {
                    Theme.StatPill { label = "首发", value = starterCount },
                    Theme.StatPill { label = "伤病", value = injuredCount, valueColor = injuredCount > 0 and Theme.COLORS.DANGER or nil },
                    Theme.StatPill { label = "低体能", value = lowFitnessCount, valueColor = lowFitnessCount > 0 and Theme.COLORS.WARNING or nil },
                    UI.Panel { flexGrow = 1 },
                    UI.Label {
                        text = team.formation,
                        fontSize = 12, color = Theme.COLORS.ACCENT,
                        fontWeight = "bold",
                    },
                }
            },

            -- 位置筛选栏
            UI.Panel {
                width = "100%", height = 38,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                children = filterTabs,
            },

            -- 排序栏
            UI.Panel {
                width = "100%", height = 30,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label { text = "排序:", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginRight = 4 },
                    table.unpack(sortTabs),
                },
            },

            -- 球员列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = playerRows,
            },

            -- 操作提示
            UI.Panel {
                width = "100%", height = 28,
                alignItems = "center", justifyContent = "center",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderTopWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label {
                        text = "长按球员 → 挂牌出售/设首发 | 点击 → 查看详情",
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },

            -- 底部导航
            Theme.MainNav("squad"),
        }
    }
end

-- 长按操作菜单
function Squad._showActionMenu(player, isStarter, team, gameState)
    local actions = {}

    -- 设为/取消首发
    if isStarter then
        table.insert(actions, {
            label = "取消首发",
            color = Theme.COLORS.WARNING,
            action = function()
                for i, pid in ipairs(team.startingXI) do
                    if pid == player.id then
                        table.remove(team.startingXI, i)
                        break
                    end
                end
                Router.replaceWith("squad")
            end,
        })
    else
        if #team.startingXI < 11 then
            table.insert(actions, {
                label = "设为首发",
                color = Theme.COLORS.SECONDARY,
                action = function()
                    table.insert(team.startingXI, player.id)
                    Router.replaceWith("squad")
                end,
            })
        else
            -- 首发已满11人，提供替换功能
            table.insert(actions, {
                label = "替换首发",
                color = Theme.COLORS.SECONDARY,
                action = function()
                    Squad._showSwapStarter(player, team, gameState)
                end,
            })
        end
    end

    -- 挂牌出售（含阵容安全检查）
    if not player.listedForSale then
        local isSafe, safetyReason = FinanceManager.checkSquadSafety(gameState, player.id)
        if isSafe then
            table.insert(actions, {
                label = "挂牌出售",
                color = Theme.COLORS.ACCENT,
                action = function()
                    player.listedForSale = true
                    gameState:sendMessage({
                        category = "transfer",
                        title = player.displayName .. " 已挂牌",
                        body = player.displayName .. " 已被挂牌出售，等待买家报价。",
                        priority = "normal",
                    })
                    Router.replaceWith("squad")
                end,
            })
        else
            table.insert(actions, {
                label = "挂牌出售 (阵容不足)",
                color = Theme.COLORS.TEXT_MUTED,
                action = function()
                    gameState:sendMessage({
                        category = "squad",
                        title = "无法挂牌出售",
                        body = "无法挂牌 " .. player.displayName .. "：" .. (safetyReason or "阵容深度不足"),
                        priority = "normal",
                    })
                    Router.replaceWith("squad")
                end,
            })
        end
    else
        table.insert(actions, {
            label = "取消挂牌",
            color = Theme.COLORS.TEXT_MUTED,
            action = function()
                player.listedForSale = false
                Router.replaceWith("squad")
            end,
        })
    end

    -- 处理收到的报价
    local incomingBids = TransferManager.getPendingSellBids(gameState)
    for _, bid in ipairs(incomingBids) do
        if bid.playerId == player.id and bid.isIncomingBid then
            local buyerTeam = gameState.teams[bid.buyerTeamId]
            local buyerName = buyerTeam and buyerTeam.name or "未知球队"
            table.insert(actions, {
                label = string.format("接受报价 %s (%.0fK)", buyerName, bid.amount / 1000),
                color = Theme.COLORS.SECONDARY,
                action = function()
                    ConfirmDialog.show({
                        title = "确认出售",
                        message = string.format("确认以 %.0fK 将 %s 出售给 %s？",
                            bid.amount / 1000, player.displayName, buyerName),
                        confirmText = "确认出售",
                        danger = false,
                        onConfirm = function()
                            TransferManager.acceptIncomingBid(gameState, bid.id)
                            Router.replaceWith("squad")
                        end,
                    })
                end,
            })
            table.insert(actions, {
                label = string.format("拒绝报价 %s", buyerName),
                color = Theme.COLORS.DANGER,
                action = function()
                    TransferManager.rejectIncomingBid(gameState, bid.id)
                    Router.replaceWith("squad")
                end,
            })
        end
    end

    -- 续约（合同剩余≤12个月时显示）
    local monthsLeft = ContractManager._monthsUntilExpiry(gameState, player)
    if monthsLeft <= 12 then
        table.insert(actions, {
            label = "续约 (" .. monthsLeft .. "个月到期)",
            color = Theme.COLORS.SECONDARY,
            action = function()
                Squad._showRenewDialog(player, gameState)
            end,
        })
    end

    -- 查看详情
    table.insert(actions, {
        label = "查看详情",
        color = Theme.COLORS.PRIMARY,
        action = function()
            Router.navigate("player_detail", { playerId = player.id })
        end,
    })

    -- 构建菜单 UI
    local menuItems = {}
    -- 球员名
    table.insert(menuItems, UI.Label {
        text = player.displayName .. " (" .. player.position .. " " .. tostring(player.overall) .. ")",
        fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold", marginBottom = 12,
        textAlign = "center",
    })

    for _, act in ipairs(actions) do
        table.insert(menuItems, UI.Button {
            text = act.label,
            width = "100%", height = 44,
            backgroundColor = {38, 46, 71, 255},
            borderRadius = 8,
            fontSize = 14, color = act.color,
            marginBottom = 6,
            onClick = function()
                UI.CloseOverlay()
                act.action()
            end,
        })
    end

    -- 取消按钮
    table.insert(menuItems, UI.Button {
        text = "取消",
        width = "100%", height = 44,
        backgroundColor = Theme.COLORS.TRANSPARENT,
        borderRadius = 8, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
        fontSize = 14, color = Theme.COLORS.TEXT_MUTED,
        marginTop = 4,
        onClick = function() UI.CloseOverlay() end,
    })

    UI.ShowOverlay(UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "flex-end",
        backgroundColor = {0, 0, 0, 150},
        onClick = function() UI.CloseOverlay() end,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderTopLeftRadius = 16, borderTopRightRadius = 16,
                padding = 20,
                paddingBottom = 30,
                children = menuItems,
            },
        },
    })
end

-- 替换首发：选择要被替换的首发球员
function Squad._showSwapStarter(player, team, gameState)
    local allPlayers = gameState:getTeamPlayers(team.id)
    local starterItems = {}

    for _, pid in ipairs(team.startingXI) do
        local sp = nil
        for _, p in ipairs(allPlayers) do
            if p.id == pid then sp = p; break end
        end
        if sp then
            table.insert(starterItems, {
                label = sp.displayName .. " (" .. sp.position .. " " .. tostring(sp.overall) .. ")",
                color = Theme.COLORS.TEXT_PRIMARY,
                action = function()
                    -- 移除旧首发，加入新首发
                    for i, id in ipairs(team.startingXI) do
                        if id == pid then
                            table.remove(team.startingXI, i)
                            break
                        end
                    end
                    table.insert(team.startingXI, player.id)
                    Router.replaceWith("squad")
                end,
            })
        end
    end

    BottomSheet.show({
        title = "选择要替换的首发球员",
        subtitle = player.displayName .. " 将替换被选中的球员",
        items = starterItems,
    })
end

-- 续约对话框
function Squad._showRenewDialog(player, gameState)
    local team = gameState:getPlayerTeam()
    local terms = ContractManager.getSuggestedTerms(player, team)
    local age = player:getAge(gameState.date.year)
    local monthsLeft = ContractManager._monthsUntilExpiry(gameState, player)

    -- 新合同结束日期
    local newEndYear = gameState.date.year + terms.years
    local newEndMonth = gameState.date.month

    ConfirmDialog.showWithDetails({
        title = "续约 - " .. player.displayName,
        details = {
            { label = "位置/能力", value = player.position .. " " .. tostring(player.overall) },
            { label = "年龄", value = tostring(age) .. "岁" },
            { label = "当前周薪", value = FinanceManager.formatMoney(player.wage or 0) },
            { label = "新周薪", value = FinanceManager.formatMoney(terms.wage), valueColor = Theme.COLORS.ACCENT },
            { label = "合同年限", value = tostring(terms.years) .. "年（至" .. newEndYear .. "年）" },
            { label = "当前剩余", value = tostring(monthsLeft) .. "个月",
              valueColor = monthsLeft <= 3 and Theme.COLORS.DANGER or Theme.COLORS.WARNING },
        },
        confirmText = "确认续约",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            local ok, errMsg = ContractManager.renewContract(gameState, player.id, terms.wage, terms.years)
            if ok then
                -- 续约成功 - 刷新页面
                Router.replaceWith("squad")
            else
                -- 续约失败 - 显示原因
                ConfirmDialog.show({
                    title = "续约失败",
                    message = errMsg or "球员拒绝了续约提议",
                    confirmText = "知道了",
                    confirmColor = Theme.COLORS.TEXT_MUTED,
                    onConfirm = function()
                        Router.replaceWith("squad")
                    end,
                })
            end
        end,
    })
end

return Squad
