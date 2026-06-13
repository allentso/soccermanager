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

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local Youth = {}

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
                    text = string.format("%d/%d人", #youthSquad, YouthManager.MAX_YOUTH_SQUAD),
                    fontSize = 12, color = Theme.COLORS.TEXT_MUTED, minWidth = 60, textAlign = "right",
                },
            }
        },
        Theme.SquadSubNav("youth"),
        UI.Panel {
            width = "100%", flexGrow = 1,
            padding = 12,
            overflow = "scroll",
            children = {
                -- 青训概览卡片
                Youth._buildSummaryCard(youthSquad),
                -- 传奇球星池入口
                Youth._buildLegendGachaSection(gameState),
                -- 候选招募区
                Youth._buildCandidatesSection(candidates, gameState),
                -- 青训球员列表
                Youth._buildSquadSection(youthSquad, gameState),
            },
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
-- 概览卡片
------------------------------------------------------
function Youth._buildSummaryCard(youthSquad)
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
                        text = string.format("%d / %d 名额", count, YouthManager.MAX_YOUTH_SQUAD),
                        fontSize = 12,
                        color = count >= YouthManager.MAX_YOUTH_SQUAD and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED,
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
                TransferManager.delistPlayer(player)
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
                    text = "观看广告解锁传奇球星池，集齐历史巨星！",
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
    local tenPullCount = gachaState.tenPullCount
    local pityCounter = gachaState.pityCounter
    local pityTotal = 10
    local adProgress, adTotal = YouthManager.getPullAdProgress(gameState)

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
                        text = "已解锁",
                        fontSize = 11,
                        color = Theme.COLORS.SECONDARY,
                        fontWeight = "bold",
                    },
                },
            },
            -- 状态信息
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                marginBottom = 8,
                children = {
                    Theme.StatPill { label = "可用次数", value = tostring(pulls), valueColor = Theme.COLORS.ACCENT },
                    Theme.StatPill { label = "已十连", value = tostring(tenPullCount) .. "次" },
                    Theme.StatPill { label = "保底计数", value = pityCounter .. "/" .. pityTotal },
                },
            },
            -- 规则说明
            UI.Label {
                text = "十连抽刷新候选池 | " .. pityTotal .. "次保底",
                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 8,
            },
            -- 按钮区域
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    -- 观看广告获取次数（打开弹窗，逐次观看）
                    UI.Button {
                        text = adProgress > 0
                            and string.format("看广告赚次数 (%d/%d)", adProgress, adTotal)
                            or "看广告赚次数",
                        height = 36, flexGrow = 1,
                        backgroundColor = Theme.COLORS.BG_ELEVATED,
                        borderRadius = 8,
                        borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        marginRight = 8,
                        onClick = function()
                            Youth._showAdForPullsModal(gameState)
                        end,
                    },
                    -- 单抽按钮
                    UI.Button {
                        text = "单抽",
                        height = 36, flexGrow = 0.6,
                        backgroundColor = pulls >= 1 and Theme.COLORS.PRIMARY or Theme.COLORS.BG_ELEVATED,
                        borderRadius = 8,
                        fontSize = 12,
                        color = pulls >= 1 and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                        marginRight = 8,
                        disabled = pulls < 1,
                        onClick = function()
                            if pulls >= 1 then
                                Youth._doSinglePull(gameState)
                            end
                        end,
                    },
                    -- 十连抽按钮
                    UI.Button {
                        text = pulls >= 10 and "十连抽!" or ("十连抽 (" .. pulls .. "/10)"),
                        height = 36, flexGrow = 1,
                        backgroundColor = pulls >= 10 and Theme.COLORS.ACCENT or Theme.COLORS.BG_ELEVATED,
                        borderRadius = 8,
                        fontSize = 13,
                        color = pulls >= 10 and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                        disabled = pulls < 10,
                        onClick = function()
                            if pulls >= 10 then
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
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local unlocked, _progress = YouthManager.watchAdForUnlock(gameState)
            if unlocked then
                ConfirmDialog.show({
                    title = "传奇球星池已解锁!",
                    message = "恭喜！传奇球星池已解锁，赠送首次十连抽机会！\n首次十连保底获得一名传奇球星！",
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
                        text = "每看1次广告获得2次抽取机会",
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginBottom = 4,
                    },
                    UI.Label {
                        text = "看满3次自动补满至10次（十连）",
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
                        text = "观看广告 (+2次)",
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
    sdk:ShowRewardVideoAd(function(result)
        if result.success then
            local newPulls = YouthManager.watchAdForPulls(gameState)
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
    local subtitle = isFirstPull and "首次十连保底！" or "欧皇附体！"

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
