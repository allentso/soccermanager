-- ui/screens/match_live.lua
-- 实时比赛页 - 模拟比赛进程，支持换人/战术干预/半场调整

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")

local MatchLive = {}

-- 比赛解说文本模板
local COMMENTARY = {
    goal = {
        "%s 进球了！比分改写！",
        "漂亮！%s 攻入一球！",
        "不可思议的进球！%s！",
        "%s 抓住机会将球送入球门！",
    },
    goal_assist = {
        "%s 助攻，%s 完成破门！",
        "%s 妙传，%s 一蹴而就！",
        "精彩配合！%s 助攻 %s 得分！",
    },
    yellow_card = {
        "%s 因犯规领到黄牌。",
        "裁判向 %s 出示黄牌。",
        "%s 拿到一张黄牌，需要注意了。",
    },
    red_card = {
        "%s 被红牌罚下！",
        "裁判出示红牌！%s 必须离场！",
    },
    injury = {
        "%s 受伤倒地，队医入场。",
        "不幸的消息，%s 因伤离场。",
    },
    substitution = {
        "%s 换下 %s。",
        "换人！%s 替换 %s 出场。",
    },
    tactical_change = {
        "教练做出战术调整：%s。",
    },
}

-- 战术指示选项
local TACTICAL_INSTRUCTIONS = {
    { key = "all_out_attack",   label = "全力进攻",   desc = "+攻击力 -防守力" },
    { key = "attacking",        label = "偏向进攻",   desc = "+攻击力" },
    { key = "balanced",         label = "正常发挥",   desc = "平衡" },
    { key = "defensive",        label = "偏向防守",   desc = "+防守力" },
    { key = "park_the_bus",     label = "铁桶阵",     desc = "+防守力 -攻击力" },
    { key = "time_wasting",     label = "拖延时间",   desc = "减缓比赛节奏" },
}

function MatchLive.create(params)
    local gameState = _G.gameState
    local report = params and params.report
    local fixture = params and params.fixture
    if not gameState or not report then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "无比赛数据", color = Theme.COLORS.TEXT_SECONDARY },
                UI.Button {
                    text = "返回", marginTop = 16, width = 100, height = 36,
                    backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 8,
                    color = Theme.COLORS.TEXT_PRIMARY, fontSize = 14,
                    onClick = function() Router.navigate("dashboard") end
                }
            }
        }
    end

    local homeTeam = gameState.teams[report.homeTeamId]
    local awayTeam = gameState.teams[report.awayTeamId]
    local homeName = homeTeam and homeTeam.name or "主队"
    local awayName = awayTeam and awayTeam.name or "客队"
    local playerTeamId = gameState.playerTeamId

    -- 当前模拟分钟
    local currentMinute = (params and params.minute) or 0
    local matchEnded = currentMinute >= 90
    local isHalfTime = currentMinute == 45 and not matchEnded

    -- 换人与战术状态
    local subsRemaining = report._subsRemaining or 3
    local currentInstruction = report._tacticalChange or "balanced"
    local substitutions = report._substitutions or {}
    local bench = report._bench or {}

    -- 显示模式: normal | subs | tactics | halftime
    local displayMode = (params and params.mode) or "normal"
    -- 半场时自动进入半场模式
    if isHalfTime and displayMode == "normal" then
        displayMode = "halftime"
    end

    -- 计算当前比分
    local homeGoalsCurrent = 0
    local awayGoalsCurrent = 0
    local eventsShown = {}

    for _, evt in ipairs(report.events) do
        if evt.minute <= currentMinute then
            table.insert(eventsShown, evt)
            if evt.type == "goal" then
                if evt.teamId == report.homeTeamId then
                    homeGoalsCurrent = homeGoalsCurrent + 1
                else
                    awayGoalsCurrent = awayGoalsCurrent + 1
                end
            end
        end
    end

    -- 加入换人事件
    for _, sub in ipairs(substitutions) do
        if sub.minute <= currentMinute then
            table.insert(eventsShown, sub)
        end
    end
    table.sort(eventsShown, function(a, b) return a.minute < b.minute end)

    -- 生成解说
    local commentaryChildren = {}
    if matchEnded then
        table.insert(commentaryChildren, MatchLive._commentaryRow(90, "全场比赛结束！", Theme.COLORS.PRIMARY))
    end

    for i = #eventsShown, 1, -1 do
        local evt = eventsShown[i]
        local text, color = MatchLive._getCommentaryText(evt, gameState)
        if text then
            table.insert(commentaryChildren, MatchLive._commentaryRow(evt.minute, text, color))
        end
    end

    if currentMinute >= 45 then
        table.insert(commentaryChildren, MatchLive._commentaryRow(45, "── 中场休息 ──", Theme.COLORS.TEXT_MUTED))
    end
    table.insert(commentaryChildren, MatchLive._commentaryRow(0, "比赛开始！裁判吹响了开场哨。", Theme.COLORS.SECONDARY))

    -- 统计
    local statsSection = nil
    if matchEnded and report.stats then
        statsSection = Theme.Card {
            children = {
                Theme.Subtitle { text = "比赛统计" },
                MatchLive._statBar("控球", report.stats.homePossession or 50, report.stats.awayPossession or 50, "%"),
                MatchLive._statBar("射门", report.stats.homeShots or 0, report.stats.awayShots or 0, ""),
                MatchLive._statBar("射正", report.stats.homeShotsOnTarget or 0, report.stats.awayShotsOnTarget or 0, ""),
                MatchLive._statBar("犯规", report.stats.homeFouls or 0, report.stats.awayFouls or 0, ""),
                MatchLive._statBar("角球", report.stats.homeCorners or 0, report.stats.awayCorners or 0, ""),
            }
        }
    end

    -- 进度条
    local progressPct = math.min(100, math.floor(currentMinute / 90 * 100))

    -- 状态文字
    local statusText = "进行中"
    if matchEnded then statusText = "已结束"
    elseif currentMinute == 0 then statusText = "赛前"
    elseif isHalfTime then statusText = "中场休息"
    end

    -- 内容区域（根据 displayMode 切换）
    local mainContent
    if displayMode == "subs" then
        mainContent = MatchLive._buildSubstitutionPanel(
            gameState, report, fixture, bench, subsRemaining, currentMinute, substitutions, playerTeamId
        )
    elseif displayMode == "tactics" then
        mainContent = MatchLive._buildTacticsPanel(
            report, fixture, currentMinute, currentInstruction
        )
    elseif displayMode == "halftime" then
        mainContent = MatchLive._buildHalftimePanel(
            gameState, report, fixture, bench, subsRemaining, currentMinute, currentInstruction, substitutions, playerTeamId
        )
    else
        -- 正常比赛流
        mainContent = UI.ScrollView {
            flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
            children = {
                Theme.Card {
                    children = {
                        Theme.Subtitle { text = "比赛动态" },
                        UI.Panel { width = "100%", marginTop = 6, children = commentaryChildren },
                    }
                },
                statsSection,
            }
        }
    end

    -- 操作按钮区域
    local actionButton
    if matchEnded then
        actionButton = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginTop = 10,
            children = {
                UI.Button {
                    text = "查看报告", width = "48%", height = 44,
                    backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 8,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                    onClick = function()
                        Router.navigate("match_result", { report = report, fixture = fixture })
                    end,
                },
                UI.Button {
                    text = "返回主页", width = "48%", height = 44,
                    backgroundColor = {51, 59, 84, 255}, borderRadius = 8,
                    fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function() Router.navigate("dashboard") end,
                },
            }
        }
    elseif displayMode == "normal" then
        actionButton = UI.Panel {
            width = "100%", children = {
                -- 时间推进按钮行
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", marginTop = 6,
                    children = {
                        UI.Button {
                            text = "+5'", width = "18%", height = 38,
                            backgroundColor = Theme.COLORS.BG_CARD, borderRadius = 8,
                            borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                local next = math.min(90, currentMinute + 5)
                                if currentMinute < 45 and next > 45 then next = 45 end
                                Router.replaceWith("match_live", {
                                    report = report, fixture = fixture, minute = next, mode = "normal"
                                })
                            end,
                        },
                        UI.Button {
                            text = "+15'", width = "18%", height = 38,
                            backgroundColor = Theme.COLORS.BG_CARD, borderRadius = 8,
                            borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                local next = math.min(90, currentMinute + 15)
                                if currentMinute < 45 and next > 45 then next = 45 end
                                Router.replaceWith("match_live", {
                                    report = report, fixture = fixture, minute = next, mode = "normal"
                                })
                            end,
                        },
                        UI.Button {
                            text = currentMinute < 45 and "半场" or "全场",
                            width = "22%", height = 38,
                            backgroundColor = Theme.COLORS.ACCENT, borderRadius = 8,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                local next = currentMinute < 45 and 45 or 90
                                Router.replaceWith("match_live", {
                                    report = report, fixture = fixture, minute = next, mode = "normal"
                                })
                            end,
                        },
                        UI.Button {
                            text = "全场", width = "18%", height = 38,
                            backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 8,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            onClick = function()
                                Router.replaceWith("match_live", {
                                    report = report, fixture = fixture, minute = 90, mode = "normal"
                                })
                            end,
                        },
                    }
                },
                -- 战术干预按钮行
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", marginTop = 8,
                    children = {
                        UI.Button {
                            text = "换人 (" .. tostring(subsRemaining) .. ")",
                            width = "48%", height = 38,
                            backgroundColor = subsRemaining > 0 and {60, 40, 120, 255} or Theme.COLORS.BG_CARD,
                            borderRadius = 8, fontSize = 13,
                            color = subsRemaining > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                            onClick = function()
                                if subsRemaining > 0 then
                                    Router.replaceWith("match_live", {
                                        report = report, fixture = fixture, minute = currentMinute, mode = "subs"
                                    })
                                end
                            end,
                        },
                        UI.Button {
                            text = "战术指示",
                            width = "48%", height = 38,
                            backgroundColor = {40, 80, 120, 255},
                            borderRadius = 8, fontSize = 13,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                Router.replaceWith("match_live", {
                                    report = report, fixture = fixture, minute = currentMinute, mode = "tactics"
                                })
                            end,
                        },
                    }
                },
            }
        }
    end

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部比分板
            UI.Panel {
                width = "100%", backgroundColor = Theme.COLORS.BG_HEADER,
                paddingTop = 12, paddingBottom = 12, paddingLeft = 16, paddingRight = 16,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "center", marginBottom = 6,
                        children = {
                            UI.Label {
                                text = statusText, fontSize = 11,
                                color = matchEnded and Theme.COLORS.TEXT_MUTED or Theme.COLORS.SECONDARY,
                                fontWeight = "bold",
                            },
                            UI.Label { text = "  " .. tostring(currentMinute) .. "'", fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
                        children = {
                            UI.Label { text = homeName, fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 110, textAlign = "right" },
                            UI.Panel {
                                width = 80, alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = string.format("%d - %d", homeGoalsCurrent, awayGoalsCurrent),
                                        fontSize = 28, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                    },
                                }
                            },
                            UI.Label { text = awayName, fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 110 },
                        }
                    },
                    UI.Panel {
                        width = "100%", height = 4, backgroundColor = Theme.COLORS.BORDER,
                        borderRadius = 2, marginTop = 8,
                        children = {
                            UI.Panel {
                                width = tostring(progressPct) .. "%", height = 4,
                                backgroundColor = matchEnded and Theme.COLORS.TEXT_MUTED or Theme.COLORS.SECONDARY,
                                borderRadius = 2,
                            },
                        }
                    },
                    -- 当前战术指示
                    currentInstruction ~= "balanced" and UI.Label {
                        text = "战术：" .. MatchLive._getInstructionLabel(currentInstruction),
                        fontSize = 10, color = Theme.COLORS.ACCENT, textAlign = "center", marginTop = 4,
                    } or nil,
                }
            },

            -- 操作按钮
            (displayMode == "normal" or matchEnded) and UI.Panel {
                width = "100%", paddingLeft = 14, paddingRight = 14, paddingTop = 6, paddingBottom = 4,
                children = { actionButton },
            } or nil,

            -- 主内容区
            mainContent,
        }
    }
end

---------------------------------------------------------------------------
-- 换人面板
---------------------------------------------------------------------------
function MatchLive._buildSubstitutionPanel(gameState, report, fixture, bench, subsRemaining, minute, substitutions, playerTeamId)
    -- 当前场上球员（玩家球队）
    local team = gameState.teams[playerTeamId]
    local onPitch = {}
    if team and team.startingXI then
        for _, pid in ipairs(team.startingXI) do
            local p = gameState.players[pid]
            if p then
                -- 检查是否已被换下
                local subOff = false
                for _, sub in ipairs(substitutions) do
                    if sub.offPlayerId == p.id then subOff = true; break end
                end
                if not subOff then
                    table.insert(onPitch, p)
                end
            end
        end
    end
    -- 加入换上的球员
    for _, sub in ipairs(substitutions) do
        local p = gameState.players[sub.onPlayerId]
        if p then table.insert(onPitch, p) end
    end

    local onPitchRows = {}
    for _, p in ipairs(onPitch) do
        table.insert(onPitchRows, UI.Panel {
            width = "100%", height = 40, flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 11, color = Theme.COLORS.ACCENT, width = 40 },
                UI.Label { text = p.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                UI.Label { text = tostring(p.fitness) .. "%", fontSize = 11, color = p.fitness < 70 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_SECONDARY, width = 36 },
                UI.Button {
                    text = "换下", width = 48, height = 28, borderRadius = 6,
                    backgroundColor = Theme.COLORS.DANGER, fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        -- 存储选中的下场球员，切换到选替补面板
                        report._pendingSubOff = p.id
                        Router.replaceWith("match_live", {
                            report = report, fixture = fixture, minute = minute, mode = "subs_pick"
                        })
                    end,
                },
            }
        })
    end

    -- 替补列表
    local benchRows = {}
    for _, p in ipairs(bench) do
        -- 检查是否已经上场
        local alreadyOn = false
        for _, sub in ipairs(substitutions) do
            if sub.onPlayerId == p.id then alreadyOn = true; break end
        end
        if not alreadyOn then
            table.insert(benchRows, UI.Panel {
                width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 11, color = Theme.COLORS.ACCENT, width = 40 },
                    UI.Label { text = p.displayName, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, flexGrow = 1 },
                    UI.Label { text = tostring(p.overall), fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, width = 28 },
                }
            })
        end
    end

    -- 如果是选替补阶段（有待换下球员标记）
    if report._pendingSubOff then
        return MatchLive._buildSubPickPanel(gameState, report, fixture, bench, subsRemaining, minute, substitutions)
    end

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            -- 标题
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 10,
                children = {
                    UI.Label { text = "选择换下球员", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Button {
                        text = "取消", width = 60, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.BG_CARD, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Router.replaceWith("match_live", {
                                report = report, fixture = fixture, minute = minute, mode = "normal"
                            })
                        end,
                    },
                }
            },
            UI.Label {
                text = string.format("剩余换人次数：%d/3", subsRemaining),
                fontSize = 12, color = Theme.COLORS.ACCENT, marginBottom = 8,
            },
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "场上球员" },
                    UI.Panel { width = "100%", children = onPitchRows },
                }
            },
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "替补席" },
                    UI.Panel { width = "100%", children = benchRows },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 选择替补上场面板
---------------------------------------------------------------------------
function MatchLive._buildSubPickPanel(gameState, report, fixture, bench, subsRemaining, minute, substitutions)
    local offId = report._pendingSubOff
    local offPlayer = offId and gameState.players[offId]
    local offName = offPlayer and offPlayer.displayName or "?"

    local rows = {}
    for _, p in ipairs(bench) do
        local alreadyOn = false
        for _, sub in ipairs(substitutions) do
            if sub.onPlayerId == p.id then alreadyOn = true; break end
        end
        if not alreadyOn then
            table.insert(rows, UI.Panel {
                width = "100%", height = 44, flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 11, color = Theme.COLORS.ACCENT, width = 40 },
                    UI.Label { text = p.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                    UI.Label { text = tostring(p.overall), fontSize = 13, color = Theme.COLORS.SECONDARY, width = 28 },
                    UI.Button {
                        text = "换上", width = 48, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.SECONDARY, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            -- 执行换人
                            local newSub = {
                                type = "substitution",
                                minute = minute,
                                offPlayerId = offId,
                                onPlayerId = p.id,
                                teamId = gameState.playerTeamId,
                            }
                            report._substitutions = report._substitutions or {}
                            table.insert(report._substitutions, newSub)
                            report._subsRemaining = (report._subsRemaining or 3) - 1
                            report._pendingSubOff = nil
                            -- 也添加到事件列表
                            table.insert(report.events, newSub)
                            Router.replaceWith("match_live", {
                                report = report, fixture = fixture, minute = minute, mode = "normal"
                            })
                        end,
                    },
                }
            })
        end
    end

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 10,
                children = {
                    UI.Label { text = "选择替补上场", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Button {
                        text = "取消", width = 60, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.BG_CARD, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            report._pendingSubOff = nil
                            Router.replaceWith("match_live", {
                                report = report, fixture = fixture, minute = minute, mode = "subs"
                            })
                        end,
                    },
                }
            },
            UI.Label {
                text = "换下：" .. offName, fontSize = 13, color = Theme.COLORS.DANGER, marginBottom = 10,
            },
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "替补球员" },
                    UI.Panel { width = "100%", children = rows },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 战术指示面板
---------------------------------------------------------------------------
function MatchLive._buildTacticsPanel(report, fixture, minute, currentInstruction)
    local rows = {}
    for _, inst in ipairs(TACTICAL_INSTRUCTIONS) do
        local isActive = inst.key == currentInstruction
        table.insert(rows, UI.Button {
            width = "100%", height = 52,
            backgroundColor = isActive and {40, 100, 60, 255} or Theme.COLORS.BG_CARD,
            borderRadius = 8, borderWidth = isActive and 2 or 1,
            borderColor = isActive and Theme.COLORS.SECONDARY or Theme.COLORS.BORDER,
            marginBottom = 8, paddingLeft = 14, paddingRight = 14,
            flexDirection = "row", alignItems = "center",
            onClick = function()
                report._tacticalChange = inst.key
                -- 添加战术变更事件
                table.insert(report.events, {
                    type = "tactical_change",
                    minute = minute,
                    instruction = inst.key,
                    teamId = _G.gameState and _G.gameState.playerTeamId,
                })
                Router.replaceWith("match_live", {
                    report = report, fixture = fixture, minute = minute, mode = "normal"
                })
            end,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label { text = inst.label, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = isActive and "bold" or "normal" },
                        UI.Label { text = inst.desc, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                    }
                },
                isActive and UI.Label { text = "✓", fontSize = 18, color = Theme.COLORS.SECONDARY, width = 24 } or nil,
            },
        })
    end

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 10,
                children = {
                    UI.Label { text = "战术指示", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Button {
                        text = "确定", width = 60, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.SECONDARY, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            Router.replaceWith("match_live", {
                                report = report, fixture = fixture, minute = minute, mode = "normal"
                            })
                        end,
                    },
                }
            },
            UI.Label {
                text = "选择战术指示改变球队进攻/防守侧重", fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED, marginBottom = 10,
            },
            UI.Panel { width = "100%", children = rows },
        }
    }
end

---------------------------------------------------------------------------
-- 半场休息面板
---------------------------------------------------------------------------
function MatchLive._buildHalftimePanel(gameState, report, fixture, bench, subsRemaining, minute, currentInstruction, substitutions, playerTeamId)
    -- 半场统计摘要
    local homeGoals, awayGoals = 0, 0
    for _, evt in ipairs(report.events) do
        if evt.minute <= 45 and evt.type == "goal" then
            if evt.teamId == report.homeTeamId then homeGoals = homeGoals + 1
            else awayGoals = awayGoals + 1 end
        end
    end

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            -- 半场标题
            Theme.Card {
                children = {
                    UI.Panel {
                        width = "100%", alignItems = "center",
                        children = {
                            UI.Label { text = "中场休息", fontSize = 20, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            UI.Label { text = string.format("上半场比分 %d - %d", homeGoals, awayGoals), fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 6 },
                        }
                    },
                }
            },

            -- 操作按钮
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "半场调整" },
                    UI.Panel {
                        width = "100%", marginTop = 8,
                        children = {
                            -- 换人
                            UI.Button {
                                text = string.format("换人 (剩余%d次)", subsRemaining),
                                width = "100%", height = 44,
                                backgroundColor = subsRemaining > 0 and {60, 40, 120, 255} or Theme.COLORS.BG_CARD,
                                borderRadius = 8, fontSize = 14, marginBottom = 8,
                                color = subsRemaining > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                                onClick = function()
                                    if subsRemaining > 0 then
                                        Router.replaceWith("match_live", {
                                            report = report, fixture = fixture, minute = minute, mode = "subs"
                                        })
                                    end
                                end,
                            },
                            -- 战术调整
                            UI.Button {
                                text = "调整战术指示",
                                width = "100%", height = 44,
                                backgroundColor = {40, 80, 120, 255},
                                borderRadius = 8, fontSize = 14, marginBottom = 8,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                onClick = function()
                                    Router.replaceWith("match_live", {
                                        report = report, fixture = fixture, minute = minute, mode = "tactics"
                                    })
                                end,
                            },
                            -- 继续比赛
                            UI.Button {
                                text = "开始下半场 ▶",
                                width = "100%", height = 48,
                                backgroundColor = Theme.COLORS.SECONDARY,
                                borderRadius = 8, fontSize = 16, fontWeight = "bold",
                                color = Theme.COLORS.TEXT_PRIMARY,
                                onClick = function()
                                    Router.replaceWith("match_live", {
                                        report = report, fixture = fixture, minute = 46, mode = "normal"
                                    })
                                end,
                            },
                        }
                    },
                }
            },

            -- 上半场关键事件
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "上半场回顾" },
                    UI.Panel {
                        width = "100%", marginTop = 4,
                        children = MatchLive._getFirstHalfSummary(report, gameState),
                    },
                }
            },
        }
    }
end

-- 上半场事件摘要
function MatchLive._getFirstHalfSummary(report, gameState)
    local rows = {}
    for _, evt in ipairs(report.events) do
        if evt.minute <= 45 then
            local text, color = MatchLive._getCommentaryText(evt, gameState)
            if text then
                table.insert(rows, MatchLive._commentaryRow(evt.minute, text, color))
            end
        end
    end
    if #rows == 0 then
        table.insert(rows, UI.Label { text = "上半场平静，无关键事件。", fontSize = 12, color = Theme.COLORS.TEXT_MUTED })
    end
    return rows
end

---------------------------------------------------------------------------
-- 辅助函数
---------------------------------------------------------------------------

function MatchLive._getInstructionLabel(key)
    for _, inst in ipairs(TACTICAL_INSTRUCTIONS) do
        if inst.key == key then return inst.label end
    end
    return "正常"
end

function MatchLive._getCommentaryText(evt, gameState)
    local player = evt.playerId and gameState.players[evt.playerId]
    local pName = player and player.displayName or "球员"

    if evt.type == "goal" then
        if evt.assistPlayerId then
            local assister = gameState.players[evt.assistPlayerId]
            local aName = assister and assister.displayName or "队友"
            local templates = COMMENTARY.goal_assist
            return string.format(templates[math.random(1, #templates)], aName, pName), Theme.COLORS.SECONDARY
        else
            local templates = COMMENTARY.goal
            return string.format(templates[math.random(1, #templates)], pName), Theme.COLORS.SECONDARY
        end
    elseif evt.type == "yellow_card" then
        local templates = COMMENTARY.yellow_card
        return string.format(templates[math.random(1, #templates)], pName), Theme.COLORS.WARNING
    elseif evt.type == "red_card" then
        local templates = COMMENTARY.red_card
        return string.format(templates[math.random(1, #templates)], pName), Theme.COLORS.DANGER
    elseif evt.type == "injury" then
        local templates = COMMENTARY.injury
        return string.format(templates[math.random(1, #templates)], pName), Theme.COLORS.DANGER
    elseif evt.type == "substitution" then
        local offPlayer = evt.offPlayerId and gameState.players[evt.offPlayerId]
        local onPlayer = evt.onPlayerId and gameState.players[evt.onPlayerId]
        local offName = offPlayer and offPlayer.displayName or "球员"
        local onName = onPlayer and onPlayer.displayName or "替补"
        return string.format("换人：%s 换下 %s", onName, offName), {140, 180, 255, 255}
    elseif evt.type == "tactical_change" then
        local label = MatchLive._getInstructionLabel(evt.instruction)
        return string.format("战术调整：%s", label), Theme.COLORS.ACCENT
    end
    return nil, nil
end

function MatchLive._commentaryRow(minute, text, color)
    local icon = "•"
    if string.find(text, "进球") or string.find(text, "破门") or string.find(text, "得分") or string.find(text, "攻入") then icon = "⚽"
    elseif string.find(text, "黄牌") then icon = "🟨"
    elseif string.find(text, "红牌") then icon = "🟥"
    elseif string.find(text, "受伤") or string.find(text, "离场") then icon = "🏥"
    elseif string.find(text, "结束") then icon = "🏁"
    elseif string.find(text, "开始") then icon = "▶"
    elseif string.find(text, "中场") then icon = "⏸"
    elseif string.find(text, "换人") or string.find(text, "换下") then icon = "🔄"
    elseif string.find(text, "战术") then icon = "📋"
    end

    return UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "flex-start", marginBottom = 8,
        children = {
            UI.Label { text = string.format("%d'", minute), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 30 },
            UI.Label { text = icon, fontSize = 14, width = 22 },
            UI.Label { text = text, fontSize = 12, color = color or Theme.COLORS.TEXT_PRIMARY, flexGrow = 1, flexShrink = 1 },
        }
    }
end

function MatchLive._statBar(label, homeVal, awayVal, suffix)
    local total = homeVal + awayVal
    local homePct = total > 0 and math.floor(homeVal / total * 100) or 50
    return UI.Panel {
        width = "100%", marginBottom = 8,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", marginBottom = 3,
                children = {
                    UI.Label { text = tostring(homeVal) .. suffix, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, width = 40 },
                    UI.Label { text = label, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1, textAlign = "center" },
                    UI.Label { text = tostring(awayVal) .. suffix, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, width = 40, textAlign = "right" },
                }
            },
            UI.Panel {
                width = "100%", height = 6, flexDirection = "row", borderRadius = 3, backgroundColor = Theme.COLORS.BORDER,
                children = {
                    UI.Panel { width = tostring(homePct) .. "%", height = 6, backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 3 },
                }
            },
        }
    }
end

return MatchLive
