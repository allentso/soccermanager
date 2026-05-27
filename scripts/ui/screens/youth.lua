-- ui/screens/youth.lua
-- 青训学院页面：青训球员列表、候选招募、提拔/释放

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local YouthManager = require("scripts/systems/youth_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")

local Youth = {}

------------------------------------------------------
-- 主页面
------------------------------------------------------
function Youth.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel{} end

    local youthSquad = YouthManager.getYouthSquad(gameState)
    local candidates = YouthManager.getCandidates(gameState)

    local children = {
        Theme.SquadSubNav("youth"),
        UI.Panel {
            width = "100%", flexGrow = 1,
            padding = 12,
            overflow = "scroll",
            children = {
                -- 青训概览卡片
                Youth._buildSummaryCard(youthSquad),
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
                        text = string.format("%d / 8 名额", count),
                        fontSize = 12,
                        color = count >= 8 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED,
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
                    Theme.StatPill { label = "平均潜力", value = count > 0 and tostring(avgPot) or "-",
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
        marginBottom = 8,
        children = {
            Theme.Subtitle { text = "候选球员", marginBottom = 0 },
            UI.Label {
                text = tostring(#candidates) .. "人可签入",
                fontSize = 11,
                color = Theme.COLORS.ACCENT,
            },
        },
    })

    for i, candidate in ipairs(candidates) do
        table.insert(rows, Youth._buildCandidateCard(candidate, i, gameState))
    end

    return Theme.Card { children = rows }
end

function Youth._buildCandidateCard(candidate, index, gameState)
    local posColor = Theme.COLORS.TEXT_SECONDARY
    if candidate.position == "GK" then posColor = {255, 204, 0, 255}
    elseif candidate.position == "CB" or candidate.position == "LB" or candidate.position == "RB" then posColor = {77, 179, 255, 255}
    elseif candidate.position == "ST" or candidate.position == "CF" or candidate.position == "LW" or candidate.position == "RW" then posColor = {255, 102, 102, 255}
    else posColor = {102, 255, 128, 255}
    end

    -- 潜力评级颜色
    local potColor = Theme.COLORS.TEXT_MUTED
    if candidate.potential >= 75 then potColor = Theme.COLORS.ACCENT
    elseif candidate.potential >= 60 then potColor = Theme.COLORS.SECONDARY
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
            -- 位置
            UI.Label {
                text = Constants.POSITION_NAMES[candidate.position] or candidate.position,
                fontSize = 12,
                color = posColor,
                width = 40,
                fontWeight = "bold",
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
                            candidate.age, candidate.nationality or "?", candidate.overall),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 潜力
            UI.Panel {
                alignItems = "center",
                marginRight = 10,
                children = {
                    UI.Label {
                        text = tostring(candidate.potential),
                        fontSize = 14,
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
    ConfirmDialog.showWithDetails({
        title = "签入青训球员",
        details = {
            { label = "姓名", value = candidate.displayName },
            { label = "位置", value = Constants.POSITION_NAMES[candidate.position] or candidate.position },
            { label = "年龄", value = tostring(candidate.age) .. "岁" },
            { label = "能力", value = tostring(candidate.overall) },
            { label = "潜力", value = tostring(candidate.potential), valueColor = Theme.COLORS.ACCENT },
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
    local posColor = Theme.COLORS.TEXT_SECONDARY
    if player.position == "GK" then posColor = {255, 204, 0, 255}
    elseif player.position == "CB" or player.position == "LB" or player.position == "RB" then posColor = {77, 179, 255, 255}
    elseif player.position == "ST" or player.position == "CF" or player.position == "LW" or player.position == "RW" then posColor = {255, 102, 102, 255}
    else posColor = {102, 255, 128, 255}
    end

    local potColor = Theme.COLORS.TEXT_MUTED
    if (player.potential or 0) >= 75 then potColor = Theme.COLORS.ACCENT
    elseif (player.potential or 0) >= 60 then potColor = Theme.COLORS.SECONDARY
    end

    local age = player.birthYear and (gameState.date.year - player.birthYear) or "?"

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
            -- 位置
            UI.Label {
                text = Constants.POSITION_NAMES[player.position] or player.position,
                fontSize = 12,
                color = posColor,
                width = 40,
                fontWeight = "bold",
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
                        text = string.format("%s岁 | 能力%d | 潜力%d",
                            tostring(age), player.overall or 0, player.potential or 0),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                },
            },
            -- 能力/潜力
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(player.overall or 0),
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
                        text = tostring(player.potential or 0),
                        fontSize = 14,
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
    local age = player.birthYear and (gameState.date.year - player.birthYear) or 0
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
            Router.navigate("player_detail", { playerId = player.id })
        end,
    })

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
        padding = 16,
        children = {
            UI.Label {
                text = player.displayName or "",
                fontSize = 16,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                marginBottom = 12,
            },
            table.unpack(items),
        },
    })
end

------------------------------------------------------
-- 提拔确认
------------------------------------------------------
function Youth._confirmPromote(player, gameState)
    local age = player.birthYear and (gameState.date.year - player.birthYear) or 0
    local newWage = math.max(1000, math.floor((player.overall or 0) * 80))

    ConfirmDialog.showWithDetails({
        title = "提拔至一线队",
        details = {
            { label = "姓名", value = player.displayName or "" },
            { label = "位置", value = Constants.POSITION_NAMES[player.position] or player.position },
            { label = "年龄", value = tostring(age) .. "岁" },
            { label = "能力", value = tostring(player.overall or 0) },
            { label = "潜力", value = tostring(player.potential or 0), valueColor = Theme.COLORS.ACCENT },
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

return Youth
