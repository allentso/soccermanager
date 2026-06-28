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
local AIManager = require("scripts/systems/ai_manager")
local YouthManager = require("scripts/systems/youth_manager")
local Team = require("scripts/domain/team")

local WorldCup = require("scripts/systems/world_cup")

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
    CDM = "MID", CM = "MID", CAM = "MID", LM = "MID", RM = "MID",
    LW = "FWD", RW = "FWD", ST = "FWD",
}

function Squad.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    -- 判断当前身份：国家队模式 vs 俱乐部模式
    local isNTMode = gameState.currentRole == "national_team"
        and gameState.nationalTeamCoach ~= nil
        and (gameState.worldCup ~= nil or gameState.euroCup ~= nil)

    local team
    if isNTMode then
        local nationCode = gameState.nationalTeamCoach.nation
        team = WorldCup.buildNationalTeam(gameState, nationCode)
    else
        team = gameState:getPlayerTeam()
    end
    if not team then return UI.Panel { width = "100%", height = "100%" } end

    -- 获取球员列表
    local allPlayers
    if isNTMode then
        allPlayers = {}
        for _, pid in ipairs(team.playerIds or {}) do
            local p = gameState.players[pid]
            if p then table.insert(allPlayers, p) end
        end
    else
        allPlayers = gameState:getTeamPlayers(gameState.playerTeamId)
    end

    -- 构建"球员ID → 战术位置"映射（首发球员按阵型中的战术位置分类）
    local playerTacticalPos = {}
    local slots = AIManager._getFormationSlots(team)
    local startingXI = team.startingXI or {}
    for i = 1, 11 do
        local pid = startingXI[i]
        if pid and slots[i] then
            playerTacticalPos[pid] = slots[i]
        end
    end

    -- 获取球员的有效位置（首发用战术位置，替补用自然位置）
    local function getEffectivePos(p)
        return playerTacticalPos[p.id] or p.position
    end

    -- 筛选
    local players = {}
    for _, p in ipairs(allPlayers) do
        local effPos = getEffectivePos(p)
        if _filterPos == "ALL" or POS_GROUP_MAP[effPos] == _filterPos then
            table.insert(players, p)
        end
    end

    -- 排序
    local posOrder = {GK=1, CB=2, LB=3, RB=4, CDM=5, CM=6, CAM=7, LW=8, RW=9, ST=10}
    table.sort(players, function(a, b)
        if _sortBy == "position" then
            local oa = posOrder[getEffectivePos(a)] or 99
            local ob = posOrder[getEffectivePos(b)] or 99
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
    for _, pid in pairs(team.startingXI or {}) do
        startingSet[pid] = true
    end

    -- 统计
    local starterCount = 0
    for i = 1, 11 do
        if team.startingXI and team.startingXI[i] then starterCount = starterCount + 1 end
    end
    local injuredCount = 0
    local lowFitnessCount = 0
    for _, p in ipairs(allPlayers) do
        if p.injured then injuredCount = injuredCount + 1 end
        if p.fitness and p.fitness < 70 then lowFitnessCount = lowFitnessCount + 1 end
    end

    -- 统计可续约球员数量（与一键续约逻辑一致）
    local expiringCount = 0
    for _, p in ipairs(allPlayers) do
        if ContractManager.canOfferRenewal(gameState, p) then
            expiringCount = expiringCount + 1
        end
    end

    -- 阵容方案 A/B（俱乐部模式）
    local presetBar = nil
    if not isNTMode then
        Team.ensureLineupPresets(team)
        local activePreset = team.activeLineupPreset or "A"
        local isDirty = Team.isLineupPresetDirty(team)

        local function performPresetSwitch(targetKey, saveFirst)
            if saveFirst then
                Team.saveActiveLineupPreset(team)
            end
            Team.switchLineupPreset(team, targetKey)
            UI.Toast.Show({ message = "已切换到方案 " .. targetKey, variant = "success" })
            Router.replaceWith("squad")
        end

        local function onSelectPreset(targetKey)
            if targetKey == activePreset then return end
            if Team.isLineupPresetDirty(team) then
                BottomSheet.show({
                    title = "未保存的修改",
                    subtitle = "当前方案有未保存的阵容变更",
                    items = {
                        {
                            label = "保存并切换",
                            color = Theme.COLORS.SECONDARY,
                            action = function() performPresetSwitch(targetKey, true) end,
                        },
                        {
                            label = "放弃并切换",
                            color = Theme.COLORS.WARNING,
                            action = function() performPresetSwitch(targetKey, false) end,
                        },
                    },
                })
            else
                performPresetSwitch(targetKey, false)
            end
        end

        local function makePresetBtn(key, label)
            local isActive = activePreset == key
            local btnLabel = label
            if isActive and isDirty then
                btnLabel = label .. " *"
            end
            return UI.Button {
                text = btnLabel,
                height = 28,
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = isActive and Theme.COLORS.SECONDARY or Theme.COLORS.BG_CARD,
                borderRadius = 14,
                fontSize = 12,
                color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                fontWeight = isActive and "bold" or "normal",
                marginRight = 6,
                onClick = function() onSelectPreset(key) end,
            }
        end

        presetBar = UI.Panel {
            width = "100%", height = 40,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = Theme.COLORS.BG_DARK,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label { text = "阵容方案", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginRight = 8 },
                makePresetBtn("A", "方案 A"),
                makePresetBtn("B", "方案 B"),
                UI.Panel { flexGrow = 1 },
                UI.Button {
                    text = isDirty and "保存方案 *" or "保存方案",
                    height = 28,
                    paddingLeft = 12, paddingRight = 12,
                    backgroundColor = isDirty and {46, 125, 50, 255} or Theme.COLORS.BG_CARD,
                    borderRadius = 14,
                    fontSize = 11,
                    color = isDirty and "#FFFFFF" or Theme.COLORS.TEXT_SECONDARY,
                    fontWeight = isDirty and "bold" or "normal",
                    onClick = function()
                        Team.saveActiveLineupPreset(team)
                        UI.Toast.Show({ message = "方案 " .. activePreset .. " 已保存", variant = "success" })
                        Router.replaceWith("squad")
                    end,
                },
            },
        }
    end

    -- 构建筛选标签
    local filterTabs = {}
    for _, opt in ipairs(FILTER_OPTIONS) do
        local isActive = opt.key == _filterPos
        table.insert(filterTabs, UI.Button {
            text = opt.label,
            height = 28,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.GOLD or Theme.COLORS.TRANSPARENT,
            borderRadius = 14,
            fontSize = 12,
            color = isActive and "#1A1A1A" or Theme.COLORS.TEXT_MUTED,
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

    -- 构建球员行（卡片风格，与转会市场统一）
    local playerRows = {}
    for _, p in ipairs(players) do
        local isStarter = startingSet[p.id] or false
        local age = p:getAge(gameState.date.year)

        -- 位置颜色（首发球员用战术位置）
        local displayPos = getEffectivePos(p)
        local posColor = Theme.posColor(displayPos)

        -- 状态标签
        local statusText = ""
        local statusColor = Theme.COLORS.TEXT_MUTED
        if p.injured then
            statusText = "伤病"
            statusColor = Theme.COLORS.DANGER
        elseif pendingBidSet[p.id] then
            statusText = "报价中"
            statusColor = Theme.COLORS.ACCENT
        elseif p.squadRole == "loaned" and p.teamId == gameState.playerTeamId then
            statusText = "租入"
            statusColor = Theme.COLORS.SECONDARY
        elseif p.listedForSale then
            statusText = "挂牌中"
            statusColor = Theme.COLORS.WARNING
        elseif p.listedForLoan then
            statusText = "外租挂牌"
            statusColor = Theme.COLORS.ACCENT
        elseif p.fitness and p.fitness < 60 then
            statusText = "疲劳"
            statusColor = Theme.COLORS.DANGER
        elseif p.fitness and p.fitness < 75 then
            statusText = "疲劳"
            statusColor = Theme.COLORS.WARNING
        elseif p.morale and p.morale < 40 then
            statusText = "低迷"
            statusColor = Theme.COLORS.WARNING
        end

        -- 合同到期提示
        local contractWarn = ""
        if p.contractEnd then
            local monthsLeft = (p.contractEnd.year - gameState.date.year) * 12
                + (p.contractEnd.month - gameState.date.month)
            if monthsLeft <= 6 then
                contractWarn = " ⚠"
            end
        end

        -- 体能颜色
        local fitnessVal = p.fitness or 80
        local fitnessColor = fitnessVal >= 75 and Theme.COLORS.SECONDARY
            or (fitnessVal >= 60 and Theme.COLORS.WARNING or Theme.COLORS.DANGER)

        -- 工资格式化
        local wageText = p.wage >= 1000 and string.format("%.0fK/周", p.wage / 1000) or (tostring(p.wage) .. "/周")

        -- 位置全称（首发球员显示战术位置）
        local posFullName = Constants.POSITION_NAMES[displayPos] or displayPos

        -- Row 2: metadata items
        local metaItems = {}
        table.insert(metaItems, UI.Label { text = tostring(age) .. "岁", fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
        table.insert(metaItems, UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
        table.insert(metaItems, UI.Label { text = wageText, fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
        table.insert(metaItems, UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
        table.insert(metaItems, UI.Label { text = "体能 ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
        table.insert(metaItems, UI.Label { text = tostring(math.floor(fitnessVal)), fontSize = 11, color = fitnessColor, fontWeight = "bold" })
        if contractWarn ~= "" then
            table.insert(metaItems, UI.Label { text = " · ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED })
            table.insert(metaItems, UI.Label { text = "合同到期", fontSize = 11, color = Theme.COLORS.WARNING })
        end

        -- 状态标签（放在 Row 1 右侧）
        local statusBadge = nil
        if statusText ~= "" then
            statusBadge = UI.Panel {
                backgroundColor = {statusColor[1], statusColor[2], statusColor[3], 40},
                borderRadius = 3,
                paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
                marginLeft = 8,
                children = {
                    UI.Label { text = statusText, fontSize = 10, color = statusColor, fontWeight = "bold" },
                },
            }
        end

        table.insert(playerRows, UI.Panel {
            width = "100%",
            paddingLeft = 12, paddingRight = 12, paddingTop = 9, paddingBottom = 9,
            backgroundColor = isStarter and {31, 46, 71, 255} or {0, 0, 0, 0},
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            onClick = function()
                Router.navigate("player_detail", { playerId = p.id })
            end,
            onLongPress = function()
                Squad._showActionMenu(p, isStarter, team, gameState)
            end,
            children = {
                -- Row 1: Position badge + Name + Status + Rating
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    children = {
                        -- 首发标记
                        isStarter and UI.Label {
                            text = "★",
                            fontSize = 11,
                            color = Theme.COLORS.ACCENT,
                            marginRight = 5,
                        } or UI.Panel { width = 0 },
                        -- 位置徽章
                        UI.Panel {
                            backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                            borderRadius = 3,
                            paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                            marginRight = 6, minWidth = 42,
                            children = {
                                UI.Label { text = posFullName, fontSize = 10, color = posColor, fontWeight = "bold" },
                            },
                        },
                        -- 球员姓名
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1,
                            flexDirection = "row", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = p.displayName .. contractWarn,
                                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                },
                                (p.squadRole == "key") and UI.Label {
                                    text = " ★", fontSize = 11, color = {255, 200, 50, 255},
                                } or UI.Panel { width = 0 },
                            },
                        },
                        -- 状态徽章
                        statusBadge or UI.Panel { width = 0 },
                        -- 能力值
                        UI.Label {
                            text = tostring(p.overall),
                            fontSize = 16, color = Theme.COLORS.SECONDARY,
                            fontWeight = "bold", marginLeft = 8,
                        },
                    },
                },
                -- Row 2: metadata line
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
                    children = metaItems,
                },
            },
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
                        onClick = function() Router.back() end,
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

            presetBar or UI.Panel { height = 0 },

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
                children = {
                    UI.Panel {
                        flexGrow = 1, flexDirection = "row", alignItems = "center",
                        children = filterTabs,
                    },
                    UI.Button {
                        text = expiringCount > 0 and ("一键续约(" .. expiringCount .. ")") or "一键续约",
                        height = 28,
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = expiringCount > 0 and {46, 125, 50, 255} or {60, 60, 60, 255},
                        borderRadius = 14,
                        fontSize = 11,
                        color = expiringCount > 0 and "#FFFFFF" or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                        onClick = function()
                            if expiringCount == 0 then
                                UI.Toast.Show({ message = "没有需要续约的球员", variant = "info" })
                                return
                            end
                            Squad._showBatchRenewConfirm(allPlayers, gameState)
                        end,
                    },
                },
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
                        text = "长按球员 → 挂牌出售/外租/设首发 | 点击 → 查看详情",
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
                -- 找到该球员在首发中的槽位索引
                local slotIdx = nil
                for i = 1, 11 do
                    local pid = team.startingXI and team.startingXI[i]
                    if pid == player.id then
                        slotIdx = i
                        break
                    end
                end
                if slotIdx then
                    -- 找同槽位最佳替补自动填充
                    local slots = AIManager._getFormationSlots(team)
                    local slotPos = slots[slotIdx] or player.position

                    local starterSet = {}
                    for _, pid in pairs(team.startingXI or {}) do starterSet[pid] = true end

                    local bestSub = nil
                    local bestScore = -1
                    for _, pid in ipairs(team.playerIds or {}) do
                        local p = gameState.players[pid]
                        if p and not starterSet[p.id] and not p.retired and not p.injured then
                            local score = AIManager._playerPositionScore(p, slotPos)
                            if score > bestScore then
                                bestScore = score
                                bestSub = p
                            end
                        end
                    end

                    if bestSub then
                        -- 原位替换
                        team.startingXI[slotIdx] = bestSub.id
                    else
                        -- 无可用替补，清空该槽位但不压缩阵型槽位
                        team.startingXI[slotIdx] = nil
                    end
                    Team.saveActiveLineupPreset(team)
                end
                Router.replaceWith("squad")
            end,
        })
    else
        -- 非首发球员 → 替换首发（按位置推荐最适合替换的人）
        table.insert(actions, {
            label = (function()
                local count = 0
                for i = 1, 11 do
                    if team.startingXI and team.startingXI[i] then count = count + 1 end
                end
                return count < 11 and "设为首发" or "替换首发"
            end)(),
            color = Theme.COLORS.SECONDARY,
            action = function()
                local starterCount = 0
                for i = 1, 11 do
                    if team.startingXI and team.startingXI[i] then starterCount = starterCount + 1 end
                end
                if starterCount < 11 then
                    -- 首发未满：找最匹配的空缺槽位赋值，不压缩/挤动现有槽位
                    local slots = AIManager._getFormationSlots(team)
                    local bestSlotIdx = nil
                    local bestScore = -1
                    for i = 1, 11 do
                        if not (team.startingXI and team.startingXI[i]) then
                            local score = AIManager._playerPositionScore(player, slots[i] or player.position)
                            if score > bestScore then
                                bestScore = score
                                bestSlotIdx = i
                            end
                        end
                    end
                    if bestSlotIdx then
                        team.startingXI = team.startingXI or {}
                        team.startingXI[bestSlotIdx] = player.id
                        Team.saveActiveLineupPreset(team)
                    end
                    Router.replaceWith("squad")
                else
                    -- 首发已满：显示替换选择界面
                    Squad._showSwapStarter(player, team, gameState)
                end
            end,
        })
    end

    -- 挂牌出售（含阵容安全检查）
    if not player.listedForSale then
        local isSafe, safetyReason = FinanceManager.checkSquadSafety(gameState, player.id)
        if isSafe then
            table.insert(actions, {
                label = "挂牌出售",
                color = Theme.COLORS.ACCENT,
                action = function()
                    local ok, err = TransferManager.listForSale(gameState, player)
                    if ok then
                        UI.Toast.Show({
                            message = player.displayName .. " 已挂牌，等待买家报价",
                            variant = "success",
                        })
                        Router.replaceWith("squad")
                    else
                        local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                        if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                            UI.Toast.Show({ message = err or "无法挂牌", variant = "warning" })
                        end
                    end
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
                TransferManager.delistPlayer(player)
                Router.replaceWith("squad")
            end,
        })
    end

    -- 挂牌外租（与出售互斥）
    if player.squadRole ~= "loaned" and not player.listedForSale then
        if player.listedForLoan then
            table.insert(actions, {
                label = "取消外租挂牌",
                color = Theme.COLORS.TEXT_MUTED,
                action = function()
                    TransferManager.delistLoan(player)
                    Router.replaceWith("squad")
                end,
            })
        else
            local isSafe, safetyReason = FinanceManager.checkSquadSafety(gameState, player.id)
            if isSafe then
                table.insert(actions, {
                    label = "挂牌外租",
                    color = Theme.COLORS.SECONDARY,
                    action = function()
                        local ok, err = TransferManager.listForLoan(gameState, player, 26)
                        if ok then
                            Router.replaceWith("squad")
                        else
                            local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
                            if not TransferLimitDialog.handleError(err, player.displayName, gameState) then
                                UI.Toast.Show({ message = err or "无法挂牌外租", variant = "warning" })
                            end
                        end
                    end,
                })
            else
                table.insert(actions, {
                    label = "挂牌外租 (阵容不足)",
                    color = Theme.COLORS.TEXT_MUTED,
                    action = function()
                        gameState:sendMessage({
                            category = "squad",
                            title = "无法挂牌外租",
                            body = "无法挂牌 " .. player.displayName .. "：" .. (safetyReason or "阵容深度不足"),
                            priority = "normal",
                        })
                        Router.replaceWith("squad")
                    end,
                })
            end
        end
    end

    -- 下放至青训队（21岁及以下年轻球员）
    local canDemote = YouthManager.canDemoteToYouth(gameState, player.id)
    if canDemote then
        table.insert(actions, {
            label = "下放至青训队",
            color = {120, 220, 150, 255},
            action = function()
                UI.CloseOverlay()
                ConfirmDialog.show({
                    title = "下放至青训队",
                    message = string.format(
                        "确定将 %s 下放至青训队吗？\n球员将移出一线队名单，周薪调整为青训标准（%s/周），仍可在青训页挂牌出售。",
                        player.displayName or "",
                        FinanceManager.formatMoney(500)),
                    confirmText = "确认下放",
                    confirmColor = {120, 220, 150, 255},
                    onConfirm = function()
                        local ok, err = YouthManager.demoteToYouth(gameState, player.id)
                        if ok then
                            UI.Toast.Show({
                                message = (player.displayName or "球员") .. " 已下放至青训队",
                                variant = "success",
                            })
                            Router.replaceWith("squad")
                        else
                            UI.Toast.Show({ message = err or "下放失败", variant = "warning" })
                        end
                    end,
                })
            end,
        })
    end

    -- 处理收到的报价（仅 pending 可接受/拒绝；其余状态走市场）
    local bid = TransferManager.pickPrimaryIncomingSaleBid(gameState, player.id)
    if bid and bid.status == "pending" then
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local buyerName = buyerTeam and buyerTeam.name or "未知球队"
        table.insert(actions, {
            label = string.format("接受报价 %s (%.0fK)", buyerName, bid.amount / 1000),
            color = Theme.COLORS.SECONDARY,
            action = function()
                local ok = TransferManager.acceptIncomingBid(gameState, bid.id)
                if ok then
                    UI.Toast.Show({ message = "已同意报价，请前往转会市场确认出售", variant = "success" })
                else
                    UI.Toast.Show({ message = "无法接受该报价", variant = "warning" })
                end
                Router.replaceWith("market", { tab = "listed", listedSubTab = "status" })
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
    elseif bid and bid.status == "awaiting_sale_confirmation" then
        local buyerTeam = gameState.teams[bid.buyerTeamId]
        local buyerName = buyerTeam and buyerTeam.name or "未知球队"
        table.insert(actions, {
            label = string.format("确认出售给 %s", buyerName),
            color = Theme.COLORS.SECONDARY,
            action = function()
                Router.replaceWith("market", { tab = "listed", listedSubTab = "status", highlightBidId = bid.id })
            end,
        })
    end

    -- 续约（可发起续约时显示）
    local monthsLeft = ContractManager.getMonthsRemaining(gameState, player)
    if ContractManager.canOfferRenewal(gameState, player) then
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
        color = Theme.COLORS.GOLD,
        action = function()
            Router.navigate("player_detail", { playerId = player.id })
        end,
    })

    -- 构建菜单 UI
    local menuItems = {}
    -- 球员名
    table.insert(menuItems, UI.Label {
        text = player.displayName .. " (" .. player.position .. " " .. tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)) .. ")",
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

-- 替换首发：选择要被替换的首发球员（按位置适配度排序，推荐最适合被替换的）
function Squad._showSwapStarter(player, team, gameState)
    local slots = AIManager._getFormationSlots(team)
    local starterItems = {}

    -- 按新球员对各槽位的适配度排序（适配度高的排前面=更推荐替换该位置）
    local candidates = {}
    for i = 1, 11 do
        local pid = team.startingXI and team.startingXI[i]
        local sp = pid and gameState.players[pid]
        if sp then
            local slotPos = slots[i] or sp.position
            local newScore = AIManager._playerPositionScore(player, slotPos)
            local oldScore = AIManager._playerPositionScore(sp, slotPos)
            table.insert(candidates, {
                index = i,
                player = sp,
                slotPos = slotPos,
                advantage = newScore - oldScore, -- 正值=新球员比老球员更适合该位置
            })
        end
    end
    -- 按优势排序：新球员更适合的位置排前面
    table.sort(candidates, function(a, b) return a.advantage > b.advantage end)

    for _, c in ipairs(candidates) do
        local sp = c.player
        local posLabel = Constants.POSITION_NAMES[c.slotPos] or c.slotPos
        local hint = c.advantage > 0 and " ✓推荐" or ""
        table.insert(starterItems, {
            label = string.format("%s %s (%s %d)%s", posLabel, sp.displayName, sp.position, sp.overall, hint),
            color = c.advantage > 0 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_PRIMARY,
            action = function()
                -- 原位替换：直接赋值到该槽位索引
                team.startingXI[c.index] = player.id
                Team.saveActiveLineupPreset(team)
                Router.replaceWith("squad")
            end,
        })
    end

    BottomSheet.show({
        title = "选择要替换的首发球员",
        subtitle = player.displayName .. " (" .. player.position .. ") 将接替被选中球员的位置",
        items = starterItems,
    })
end

-- 续约对话框
function Squad._showRenewDialog(player, gameState)
    local team = gameState:getPlayerTeam()
    local terms = ContractManager.getSuggestedTerms(player, team, gameState)
    local age = player:getAge(gameState.date.year)
    local monthsLeft = ContractManager.getMonthsRemaining(gameState, player)

    -- 新合同结束日期
    local newEndYear = gameState.date.year + terms.years
    local newEndMonth = gameState.date.month

    ConfirmDialog.showWithDetails({
        title = "续约 - " .. player.displayName,
        details = {
            { label = "位置/能力", value = player.position .. " " .. tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)) },
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
                -- 提议已提交，球员考虑中
                ConfirmDialog.show({
                    title = "续约提议已发出",
                    message = string.format("已向 %s 提出续约，球员需要时间考虑。结果将通过消息通知。", player.displayName),
                    confirmText = "好的",
                    confirmColor = Theme.COLORS.SECONDARY,
                    onConfirm = function()
                        Router.replaceWith("squad")
                    end,
                })
            else
                -- 提议失败（预算超支或已在谈判中）
                ConfirmDialog.show({
                    title = "无法发起续约",
                    message = errMsg or "条件不满足",
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

-- 一键续约确认弹窗
function Squad._showBatchRenewConfirm(allPlayers, gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    -- 收集所有可续约球员及建议条款
    local renewList = {}
    local totalWageIncrease = 0
    for _, p in ipairs(allPlayers) do
        if not ContractManager.canOfferRenewal(gameState, p) then goto continueRenew end
        local ml = ContractManager.getMonthsRemaining(gameState, p)
        local terms = ContractManager.getSuggestedTerms(p, team, gameState)
        local wageIncrease = terms.wage - (p.wage or 0)
        table.insert(renewList, {
            player = p,
            terms = terms,
            monthsLeft = ml,
            wageIncrease = wageIncrease,
        })
        if wageIncrease > 0 then
            totalWageIncrease = totalWageIncrease + wageIncrease
        end
        ::continueRenew::
    end

    if #renewList == 0 then
        UI.Toast.Show({ message = "没有需要续约的球员", variant = "info" })
        return
    end

    -- 按紧急程度排序（剩余月数少的在前）
    table.sort(renewList, function(a, b) return a.monthsLeft < b.monthsLeft end)

    -- 构建详情列表
    local detailItems = {}
    for _, item in ipairs(renewList) do
        local p = item.player
        local urgency = item.monthsLeft <= 3 and " 🔴" or (item.monthsLeft <= 6 and " 🟡" or "")
        table.insert(detailItems, {
            label = p.displayName .. " (" .. p.position .. " " .. tostring(p.overall) .. ")" .. urgency,
            value = string.format("%s → %s, %d年",
                FinanceManager.formatMoney(p.wage or 0),
                FinanceManager.formatMoney(item.terms.wage),
                item.terms.years),
        })
    end

    table.insert(detailItems, { label = "———————————", value = "" })
    table.insert(detailItems, {
        label = "总周薪增加",
        value = totalWageIncrease > 0 and ("+" .. FinanceManager.formatMoney(totalWageIncrease)) or "无增加",
        valueColor = totalWageIncrease > 0 and Theme.COLORS.WARNING or Theme.COLORS.SECONDARY,
    })

    ConfirmDialog.showWithDetails({
        title = "一键续约 - " .. tostring(#renewList) .. "名球员",
        details = detailItems,
        confirmText = "全部续约",
        confirmColor = {46, 125, 50, 255},
        onConfirm = function()
            Squad._executeBatchRenew(renewList, gameState)
        end,
    })
end

-- 执行批量续约
function Squad._executeBatchRenew(renewList, gameState)
    local successCount = 0
    local failCount = 0
    local failReasons = {}

    for _, item in ipairs(renewList) do
        local ok, errMsg = ContractManager.renewContract(gameState, item.player.id, item.terms.wage, item.terms.years)
        if ok then
            successCount = successCount + 1
        else
            failCount = failCount + 1
            table.insert(failReasons, item.player.displayName .. ": " .. (errMsg or "未知原因"))
        end
    end

    local msg
    if failCount == 0 then
        msg = string.format("已向 %d 名球员发出续约提议，等待球员回复。", successCount)
    else
        msg = string.format("成功发出 %d 份续约提议，%d 份失败。", successCount, failCount)
        if #failReasons > 0 then
            msg = msg .. "\n失败原因: " .. table.concat(failReasons, "; ")
        end
    end

    ConfirmDialog.show({
        title = "续约提议已发出",
        message = msg,
        confirmText = "好的",
        confirmColor = Theme.COLORS.SECONDARY,
        onConfirm = function()
            Router.replaceWith("squad")
        end,
    })
end

return Squad
