-- ui/screens/match_live.lua
-- 实时比赛页 - 步进式模拟，换人/战术指令实时影响结果

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local MatchSession = require("scripts/match/match_session")

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
    ---@type MatchSession
    local session = params and params.session
    local fixture = params and params.fixture
    if not gameState or not session then
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

    local homeTeam = gameState.teams[session.fixture.homeTeamId]
    local awayTeam = gameState.teams[session.fixture.awayTeamId]
    local homeName = homeTeam and homeTeam.name or "主队"
    local awayName = awayTeam and awayTeam.name or "客队"
    local playerTeamId = gameState.playerTeamId

    -- 获取 session 状态
    local status = session:getStatus()
    local currentMinute = status.minute
    local matchEnded = session:isFinished()
    local isHalfTime = session:isHalfTime()
    local needsPenalties = session:needsPenalties()

    -- 显示模式: normal | subs | sub_pick | tactics | halftime | penalties
    local displayMode = (params and params.mode) or "normal"
    -- 半场时自动进入半场模式
    if isHalfTime and displayMode == "normal" then
        displayMode = "halftime"
    end
    -- 点球时自动进入点球模式
    if needsPenalties and displayMode == "normal" then
        displayMode = "penalties"
    end

    -- 解说事件列表（全部事件，最新在前）
    local commentaryChildren = {}
    if matchEnded then
        table.insert(commentaryChildren, MatchLive._commentaryRow(currentMinute, "全场比赛结束！", Theme.COLORS.PRIMARY))
    end

    for i = #session.events, 1, -1 do
        local evt = session.events[i]
        local text, color = MatchLive._getCommentaryText(evt, gameState)
        if text then
            table.insert(commentaryChildren, MatchLive._commentaryRow(evt.minute, text, color))
        end
    end

    if currentMinute >= 45 then
        table.insert(commentaryChildren, MatchLive._commentaryRow(45, "── 中场休息 ──", Theme.COLORS.TEXT_MUTED))
    end
    if currentMinute > 0 then
        table.insert(commentaryChildren, MatchLive._commentaryRow(0, "比赛开始！裁判吹响了开场哨。", Theme.COLORS.SECONDARY))
    end

    -- 最终报告（比赛结束后用于统计显示）
    local statsSection = nil
    if matchEnded then
        local homePoss = session.totalPossessionTicks > 0
            and math.floor(session.homePossessionTicks / session.totalPossessionTicks * 100) or 50
        statsSection = Theme.Card {
            children = {
                Theme.Subtitle { text = "比赛统计" },
                MatchLive._statBar("控球", homePoss, 100 - homePoss, "%"),
                MatchLive._statBar("射门", session.homeShots, session.awayShots, ""),
                MatchLive._statBar("射正", session.homeShotsOnTarget, session.awayShotsOnTarget, ""),
                MatchLive._statBar("犯规", session.homeFouls, session.awayFouls, ""),
            }
        }
    end

    -- 进度条
    local maxMinute = 90
    if session.phase == MatchSession.PHASE.EXTRA_FIRST or session.phase == MatchSession.PHASE.EXTRA_SECOND
       or session.phase == MatchSession.PHASE.EXTRA_HALF_TIME then
        maxMinute = 120
    end
    local progressPct = math.min(100, math.floor(currentMinute / maxMinute * 100))

    -- 状态文字
    local statusText = status.phaseName

    -- 内容区域（根据 displayMode 切换）
    local mainContent
    if displayMode == "subs" then
        mainContent = MatchLive._buildSubstitutionPanel(gameState, session, fixture)
    elseif displayMode == "sub_pick" then
        mainContent = MatchLive._buildSubPickPanel(gameState, session, fixture)
    elseif displayMode == "tactics" then
        mainContent = MatchLive._buildTacticsPanel(session, fixture)
    elseif displayMode == "halftime" then
        mainContent = MatchLive._buildHalftimePanel(gameState, session, fixture)
    elseif displayMode == "penalties" then
        mainContent = MatchLive._buildPenaltiesPanel(session, fixture)
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
                        -- 完成比赛：生成报告 + 应用结果
                        local MatchEngine = require("scripts/match/match_engine")
                        local report = MatchEngine.finishMatch(session, gameState, fixture)
                        Router.navigate("match_result", { report = report, fixture = fixture })
                    end,
                },
                UI.Button {
                    text = "返回主页", width = "48%", height = 44,
                    backgroundColor = {51, 59, 84, 255}, borderRadius = 8,
                    fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        -- 完成比赛：生成报告 + 应用结果
                        local MatchEngine = require("scripts/match/match_engine")
                        MatchEngine.finishMatch(session, gameState, fixture)
                        Router.navigate("dashboard")
                    end,
                },
            }
        }
    elseif displayMode == "normal" then
        local subsRemaining = session.subsRemaining
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
                                session:stepMinutes(5)
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                        UI.Button {
                            text = "+15'", width = "18%", height = 38,
                            backgroundColor = Theme.COLORS.BG_CARD, borderRadius = 8,
                            borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                session:stepMinutes(15)
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                        UI.Button {
                            text = currentMinute < 45 and "至中场" or "至终场",
                            width = "22%", height = 38,
                            backgroundColor = {180, 120, 30, 255}, borderRadius = 8,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                -- 步进到当前半场结束
                                local target = currentMinute < 45 and (45 - currentMinute) or (90 - currentMinute)
                                if target > 0 then
                                    session:stepMinutes(target)
                                end
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                        UI.Button {
                            text = "模拟全场", width = "24%", height = 38,
                            backgroundColor = Theme.COLORS.SECONDARY, borderRadius = 8,
                            fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            onClick = function()
                                -- 步进直到比赛结束（中场/点球时暂停让用户干预）
                                local safety = 0
                                while not session:isFinished() and not session:isHalfTime()
                                      and not session:needsPenalties() and safety < 20 do
                                    session:stepMinutes(15)
                                    safety = safety + 1
                                end
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
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
                                    Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "subs" })
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
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "tactics" })
                            end,
                        },
                    }
                },
            }
        }
    end

    -- 构建页面
    local pageChildren = {}

    -- 顶部比分板
    local scoreboardItems = {
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
                            text = string.format("%d - %d", session.homeGoals, session.awayGoals),
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
    }
    if session.tacticalInstruction ~= "balanced" then
        table.insert(scoreboardItems, UI.Label {
            text = "战术：" .. MatchLive._getInstructionLabel(session.tacticalInstruction),
            fontSize = 10, color = Theme.COLORS.ACCENT, textAlign = "center", marginTop = 4,
        })
    end

    table.insert(pageChildren, UI.Panel {
        width = "100%", backgroundColor = Theme.COLORS.BG_HEADER,
        paddingTop = 12, paddingBottom = 12, paddingLeft = 16, paddingRight = 16,
        children = scoreboardItems,
    })

    -- 操作按钮（仅正常模式和结束时显示）
    if (displayMode == "normal" or matchEnded) and actionButton then
        table.insert(pageChildren, UI.Panel {
            width = "100%", paddingLeft = 14, paddingRight = 14, paddingTop = 6, paddingBottom = 4,
            children = { actionButton },
        })
    end

    -- 主内容区
    table.insert(pageChildren, mainContent)

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
        children = pageChildren,
    }
end

---------------------------------------------------------------------------
-- 换人面板 - 选择换下球员
---------------------------------------------------------------------------
function MatchLive._buildSubstitutionPanel(gameState, session, fixture)
    -- 获取玩家球队的场上球员
    local playerTeamId = gameState.playerTeamId
    local isHome = playerTeamId == session.fixture.homeTeamId
    local context = isHome and session.homeContext or session.awayContext

    local onPitchRows = {}
    for _, p in ipairs(context.players) do
        if p.position ~= "GK" or #context.players > 1 then -- 不能换下唯一门将
            table.insert(onPitchRows, UI.Panel {
                width = "100%", height = 40, flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 11, color = Theme.COLORS.ACCENT, width = 40 },
                    UI.Label { text = p.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                    UI.Label { text = tostring(p.fitness or 80) .. "%", fontSize = 11, color = (p.fitness or 80) < 70 and Theme.COLORS.WARNING or Theme.COLORS.TEXT_SECONDARY, width = 36 },
                    UI.Button {
                        text = "换下", width = 48, height = 28, borderRadius = 6,
                        backgroundColor = Theme.COLORS.DANGER, fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            session._pendingSubOff = p.id
                            Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "sub_pick" })
                        end,
                    },
                }
            })
        end
    end

    -- 替补列表（预览）
    local benchRows = {}
    for _, p in ipairs(session.bench) do
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

    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", marginBottom = 10,
                children = {
                    UI.Label { text = "选择换下球员", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Button {
                        text = "取消", width = 60, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.BG_CARD, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                        end,
                    },
                }
            },
            UI.Label {
                text = string.format("剩余换人次数：%d/3", session.subsRemaining),
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
function MatchLive._buildSubPickPanel(gameState, session, fixture)
    local offId = session._pendingSubOff
    local offPlayer = offId and gameState.players[offId]
    local offName = offPlayer and offPlayer.displayName or "?"

    local rows = {}
    for _, p in ipairs(session.bench) do
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
                        -- 执行真实换人（影响后续模拟）
                        session:applyCommand({
                            type = MatchSession.COMMAND.SUBSTITUTE,
                            offPlayerId = offId,
                            onPlayerId = p.id,
                            teamId = gameState.playerTeamId,
                        })
                        session._pendingSubOff = nil
                        Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                    end,
                },
            }
        })
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
                            session._pendingSubOff = nil
                            Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "subs" })
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
function MatchLive._buildTacticsPanel(session, fixture)
    local currentInstruction = session.tacticalInstruction
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
                -- 应用真实战术指令（影响后续模拟）
                session:applyCommand({
                    type = MatchSession.COMMAND.CHANGE_INSTRUCTION,
                    instruction = inst.key,
                    teamId = _G.gameState and _G.gameState.playerTeamId,
                })
                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
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
                        text = "返回", width = 60, height = 30, borderRadius = 6,
                        backgroundColor = Theme.COLORS.BG_CARD, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
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
function MatchLive._buildHalftimePanel(gameState, session, fixture)
    -- 上半场统计
    local homeGoals, awayGoals = 0, 0
    for _, evt in ipairs(session.events) do
        if evt.minute <= 45 and evt.type == "goal" then
            if evt.teamId == session.fixture.homeTeamId then homeGoals = homeGoals + 1
            else awayGoals = awayGoals + 1 end
        end
    end

    local subsRemaining = session.subsRemaining

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
                                        Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "subs" })
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
                                    Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "tactics" })
                                end,
                            },
                            -- 半场训话
                            UI.Button {
                                text = "半场训话",
                                width = "100%", height = 44,
                                backgroundColor = {100, 60, 30, 255},
                                borderRadius = 8, fontSize = 14, marginBottom = 8,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                onClick = function()
                                    Router.navigate("team_talk", {
                                        context = "halftime",
                                        returnTo = "match_live",
                                        returnParams = { session = session, fixture = fixture, mode = "halftime" },
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
                                    -- 步进1分钟进入下半场
                                    session:stepMinutes(1)
                                    Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
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
                        children = MatchLive._getFirstHalfSummary(session, gameState),
                    },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 点球大战面板
---------------------------------------------------------------------------
function MatchLive._buildPenaltiesPanel(session, fixture)
    return UI.ScrollView {
        flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
        children = {
            Theme.Card {
                children = {
                    UI.Panel {
                        width = "100%", alignItems = "center",
                        children = {
                            UI.Label { text = "点球大战", fontSize = 20, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            UI.Label { text = "加时赛后两队战平，进入点球决胜", fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 6 },
                        }
                    },
                }
            },
            Theme.Card {
                children = {
                    UI.Button {
                        text = "开始点球 ▶",
                        width = "100%", height = 48,
                        backgroundColor = Theme.COLORS.SECONDARY,
                        borderRadius = 8, fontSize = 16, fontWeight = "bold",
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            local result = session:simulatePenalties()
                            session._penaltyResult = result
                            Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                        end,
                    },
                }
            },
        }
    }
end

-- 上半场事件摘要
function MatchLive._getFirstHalfSummary(session, gameState)
    local rows = {}
    for _, evt in ipairs(session.events) do
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
