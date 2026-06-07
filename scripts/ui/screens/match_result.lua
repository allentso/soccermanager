-- ui/screens/match_result.lua
-- 赛后报告页面（增强版）- MOTM/进球回顾/统计对比/球员评分

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local FinanceManager = require("scripts/systems/finance_manager")

local MatchResult = {}

function MatchResult.create(params)
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

    local homeName, awayName, isPlayerHome
    if fixture and fixture._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        homeName = WorldCup._getNationName(report.homeTeamId)
        awayName = WorldCup._getNationName(report.awayTeamId)
        local playerNation = WorldCup._getPlayerNation(gameState)
        isPlayerHome = report.homeTeamId == playerNation
    else
        local homeTeam = gameState.teams[report.homeTeamId]
        local awayTeam = gameState.teams[report.awayTeamId]
        homeName = homeTeam and homeTeam.name or "主队"
        awayName = awayTeam and awayTeam.name or "客队"
        isPlayerHome = report.homeTeamId == gameState.playerTeamId
    end
    local playerWon = (isPlayerHome and report.homeGoals > report.awayGoals) or
                      (not isPlayerHome and report.awayGoals > report.homeGoals)
    local isDraw = report.homeGoals == report.awayGoals

    -- 淘汰赛点球胜负判定（点球不计入总比分，但决定晋级）
    local extraTime = report.extraTime
    local penaltyWinner = nil
    if extraTime and extraTime.penalties then
        penaltyWinner = extraTime.penalties.winner
    end

    -- 判断胜负（含点球结果）
    if penaltyWinner then
        local playerNationOrTeam = nil
        if fixture and fixture._isWC then
            local WorldCup = require("scripts/systems/world_cup")
            playerNationOrTeam = WorldCup._getPlayerNation(gameState)
        else
            playerNationOrTeam = gameState.playerTeamId
        end
        local playerSide = isPlayerHome and report.homeTeamId or report.awayTeamId
        playerWon = (penaltyWinner == playerSide)
        isDraw = false
    end

    -- 结果
    local resultColor = isDraw and Theme.COLORS.WARNING or (playerWon and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER)
    local resultText = isDraw and "平局" or (playerWon and "胜利!" or "失败")

    -- MOTM（全场最佳）
    local motmSection = MatchResult._buildMOTM(report, gameState, fixture)

    -- 进球回顾
    local goalsSection = MatchResult._buildGoalsReview(report, gameState, homeName, awayName)

    -- 比赛事件时间线
    local eventsSection = MatchResult._buildEventsTimeline(report, gameState)

    -- 统计对比
    local statsSection = MatchResult._buildStatsComparison(report, homeName, awayName)

    -- 球员评分
    local ratingsSection = MatchResult._buildPlayerRatings(report, gameState, fixture)

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%",
                height = 44,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 14,
                paddingRight = 14,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Button {
                        text = "返回",
                        width = 50, height = 30,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "赛后报告",
                        fontSize = 16,
                        fontWeight = "bold",
                        color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Button {
                        text = "继续",
                        width = 50, height = 30,
                        backgroundColor = Theme.COLORS.SECONDARY,
                        borderRadius = 6,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            local isPlayerMatch = false
                            if fixture and fixture._isWC then
                                local WorldCup = require("scripts/systems/world_cup")
                                local pn = WorldCup._getPlayerNation(gameState)
                                isPlayerMatch = (report.homeTeamId == pn or report.awayTeamId == pn)
                            else
                                isPlayerMatch = (report.homeTeamId == gameState.playerTeamId or report.awayTeamId == gameState.playerTeamId)
                            end
                            if not report._pressConferenceDone and isPlayerMatch then
                                Router.navigate("press_conference", { report = report, fixture = fixture })
                            else
                                Router.navigate("dashboard")
                            end
                        end,
                    },
                }
            },

            -- 比分卡
            UI.Panel {
                width = "100%",
                paddingTop = 14,
                paddingBottom = 14,
                backgroundColor = Theme.COLORS.BG_CARD,
                alignItems = "center",
                children = (function()
                    local scoreChildren = {
                        UI.Label {
                            text = resultText,
                            fontSize = 13,
                            fontWeight = "bold",
                            color = resultColor,
                            marginBottom = 6,
                        },
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = homeName,
                                    fontSize = 14,
                                    color = isPlayerHome and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_PRIMARY,
                                    width = 100,
                                    textAlign = "right",
                                    fontWeight = isPlayerHome and "bold" or "normal",
                                },
                                UI.Label {
                                    text = string.format("  %d - %d  ", report.homeGoals, report.awayGoals),
                                    fontSize = 28,
                                    fontWeight = "bold",
                                    color = Theme.COLORS.TEXT_PRIMARY,
                                },
                                UI.Label {
                                    text = awayName,
                                    fontSize = 14,
                                    color = (not isPlayerHome) and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_PRIMARY,
                                    width = 100,
                                    fontWeight = (not isPlayerHome) and "bold" or "normal",
                                },
                            }
                        },
                    }

                    -- 加时赛/点球标注
                    if extraTime then
                        local etGoals = (extraTime.homeExtraGoals or 0) + (extraTime.awayExtraGoals or 0)
                        local etText = "加时赛"
                        if etGoals > 0 then
                            etText = string.format("加时赛 (含加时进球 %d)", etGoals)
                        end

                        if extraTime.penalties then
                            local pen = extraTime.penalties
                            etText = string.format("加时 %d-%d 点球 %d-%d",
                                report.homeGoals, report.awayGoals,
                                pen.homeScored or 0, pen.awayScored or 0)
                            -- 如果加时也是平局，比分就是常规90分钟的比分
                            local regularHome = report.homeGoals - (extraTime.homeExtraGoals or 0)
                            local regularAway = report.awayGoals - (extraTime.awayExtraGoals or 0)
                            if extraTime.homeExtraGoals and extraTime.homeExtraGoals > 0 or
                               extraTime.awayExtraGoals and extraTime.awayExtraGoals > 0 then
                                etText = string.format("常规 %d-%d · 加时 %d-%d · 点球 %d-%d",
                                    regularHome, regularAway,
                                    report.homeGoals, report.awayGoals,
                                    pen.homeScored or 0, pen.awayScored or 0)
                            else
                                etText = string.format("常规/加时 %d-%d · 点球 %d-%d",
                                    report.homeGoals, report.awayGoals,
                                    pen.homeScored or 0, pen.awayScored or 0)
                            end
                        end

                        table.insert(scoreChildren, UI.Label {
                            text = etText,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 6,
                        })
                    end

                    return scoreChildren
                end)(),
            },

            -- 可滚动内容区（过滤nil避免ipairs中断）
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = (function()
                    local sections = {}
                    local revenueCard = MatchResult._buildRevenueCard(report)
                    if revenueCard then table.insert(sections, revenueCard) end
                    if motmSection then table.insert(sections, motmSection) end
                    if goalsSection then table.insert(sections, goalsSection) end
                    if statsSection then table.insert(sections, statsSection) end
                    if eventsSection then table.insert(sections, eventsSection) end
                    if ratingsSection then table.insert(sections, ratingsSection) end
                    return sections
                end)(),
            },
        }
    }
end

---------------------------------------------------------------------------
-- MOTM（全场最佳）
---------------------------------------------------------------------------
function MatchResult._buildMOTM(report, gameState, fixture)
    if not report.playerRatings then return nil end

    -- 找评分最高的球员
    local bestId = nil
    local bestRating = 0
    for pid, rating in pairs(report.playerRatings) do
        if rating > bestRating then
            bestRating = rating
            bestId = pid
        end
    end

    if not bestId then return nil end
    local player = gameState.players[bestId]
    if not player then return nil end

    -- 统计该球员本场数据
    local goals, assists = 0, 0
    for _, evt in ipairs(report.events) do
        if evt.type == "goal" then
            if evt.playerId == bestId then goals = goals + 1 end
            if evt.assistPlayerId == bestId then assists = assists + 1 end
        end
    end

    local teamName = ""
    if fixture and fixture._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        -- MOTM 球员属于哪一方国家队
        if player.teamId then
            teamName = WorldCup._getNationName(report.homeTeamId)
            -- 检查球员是否属于客队国家
            local awayTeam = WorldCup.buildNationalTeam(gameState, report.awayTeamId)
            if awayTeam then
                for _, pid in ipairs(awayTeam.playerIds or {}) do
                    if pid == bestId then teamName = WorldCup._getNationName(report.awayTeamId); break end
                end
            end
        end
    else
        local team = gameState.teams[player.teamId]
        teamName = team and team.name or ""
    end

    local perfText = ""
    if goals > 0 and assists > 0 then
        perfText = string.format("%d 球 %d 助攻", goals, assists)
    elseif goals > 0 then
        perfText = string.format("%d 球", goals)
    elseif assists > 0 then
        perfText = string.format("%d 助攻", assists)
    else
        perfText = "出色表现"
    end

    return Theme.Card {
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                children = {
                    -- 星标
                    UI.Panel {
                        width = 44,
                        height = 44,
                        borderRadius = 22,
                        backgroundColor = {255, 215, 0, 40},
                        justifyContent = "center",
                        alignItems = "center",
                        marginRight = 12,
                        children = {
                            UI.Label {
                                text = "★",
                                fontSize = 22,
                                color = {255, 215, 0, 255},
                            },
                        }
                    },
                    -- 信息
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            UI.Label {
                                text = "全场最佳",
                                fontSize = 11,
                                color = {255, 215, 0, 255},
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = player.displayName,
                                fontSize = 15,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = teamName .. " · " .. (Constants.POSITION_NAMES[player.position] or player.position) .. " · " .. perfText,
                                fontSize = 11,
                                color = Theme.COLORS.TEXT_SECONDARY,
                            },
                        }
                    },
                    -- 评分
                    UI.Panel {
                        width = 40,
                        height = 40,
                        borderRadius = 8,
                        backgroundColor = Theme.COLORS.SECONDARY,
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = string.format("%.1f", bestRating),
                                fontSize = 14,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                fontWeight = "bold",
                            },
                        }
                    },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 进球回顾
---------------------------------------------------------------------------
function MatchResult._buildGoalsReview(report, gameState, homeName, awayName)
    if not report.events or #report.events == 0 then return nil end
    local goalEvents = {}
    for _, evt in ipairs(report.events) do
        if evt.type == "goal" then
            table.insert(goalEvents, evt)
        end
    end

    if #goalEvents == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "进球回顾" },
                UI.Label {
                    text = "本场比赛没有进球 (0-0)",
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_MUTED,
                },
            }
        }
    end

    -- 按时间排序
    table.sort(goalEvents, function(a, b) return a.minute < b.minute end)

    local rows = {}
    for _, evt in ipairs(goalEvents) do
        local scorer = gameState.players[evt.playerId]
        local scorerName = scorer and scorer.displayName or "?"
        local isHome = evt.teamId == report.homeTeamId
        local teamLabel = isHome and homeName or awayName

        -- 进球类型标记
        local goalIcon = "⚽"
        local goalTag = ""
        if evt.isOwnGoal then
            goalTag = " (乌龙球)"
            goalIcon = "⚽"
        elseif evt.isPenalty then
            goalTag = " (点球)"
        end

        local assistText = ""
        if evt.isOwnGoal then
            assistText = "乌龙球 · " .. teamLabel
        elseif evt.assistPlayerId then
            local assister = gameState.players[evt.assistPlayerId]
            assistText = assister and ("助攻: " .. assister.displayName) or ""
        elseif evt.isPenalty then
            assistText = "点球 · " .. teamLabel
        else
            assistText = teamLabel
        end

        table.insert(rows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingTop = 6,
            paddingBottom = 6,
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label {
                    text = string.format("%d'", evt.minute),
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_MUTED,
                    width = 32,
                },
                UI.Label {
                    text = goalIcon,
                    fontSize = 14,
                    width = 22,
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label {
                            text = scorerName .. goalTag,
                            fontSize = 13,
                            color = evt.isOwnGoal and Theme.COLORS.DANGER or Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = assistText,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                        },
                    }
                },
                UI.Label {
                    text = isHome and "主" or "客",
                    fontSize = 10,
                    color = isHome and Theme.COLORS.PRIMARY or Theme.COLORS.ACCENT,
                    backgroundColor = isHome and {33, 150, 243, 30} or {255, 153, 0, 30},
                    borderRadius = 4,
                    paddingLeft = 6,
                    paddingRight = 6,
                    paddingTop = 2,
                    paddingBottom = 2,
                },
            }
        })
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "进球回顾 (" .. #goalEvents .. ")" },
            UI.Panel { width = "100%", marginTop = 4, children = rows },
        }
    }
end

---------------------------------------------------------------------------
-- 统计对比（带可视化条）
---------------------------------------------------------------------------
function MatchResult._buildStatsComparison(report, homeName, awayName)
    local stats = report.stats or {}
    local items = {
        { "控球率", stats.homePossession or 50, stats.awayPossession or 50, "%" },
        { "射门",   stats.homeShots or 0,       stats.awayShots or 0,       "" },
        { "射正",   stats.homeShotsOnTarget or 0, stats.awayShotsOnTarget or 0, "" },
        { "犯规",   stats.homeFouls or 0,       stats.awayFouls or 0,       "" },
        { "角球",   stats.homeCorners or 0,     stats.awayCorners or 0,     "" },
    }

    local rows = {}
    for _, item in ipairs(items) do
        local label, hVal, aVal, suffix = item[1], item[2], item[3], item[4]
        local total = hVal + aVal
        local hPct = total > 0 and math.floor(hVal / total * 100) or 50

        table.insert(rows, UI.Panel {
            width = "100%",
            marginBottom = 10,
            children = {
                -- 数值行
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    marginBottom = 3,
                    children = {
                        UI.Label {
                            text = tostring(hVal) .. suffix,
                            fontSize = 13,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                            width = 44,
                        },
                        UI.Label {
                            text = label,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            flexGrow = 1,
                            textAlign = "center",
                        },
                        UI.Label {
                            text = tostring(aVal) .. suffix,
                            fontSize = 13,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                            width = 44,
                            textAlign = "right",
                        },
                    }
                },
                -- 对比条
                UI.Panel {
                    width = "100%",
                    height = 6,
                    flexDirection = "row",
                    borderRadius = 3,
                    children = {
                        UI.Panel {
                            width = tostring(hPct) .. "%",
                            height = 6,
                            backgroundColor = Theme.COLORS.PRIMARY,
                            borderTopLeftRadius = 3,
                            borderBottomLeftRadius = 3,
                        },
                        UI.Panel {
                            width = tostring(100 - hPct) .. "%",
                            height = 6,
                            backgroundColor = Theme.COLORS.ACCENT,
                            borderTopRightRadius = 3,
                            borderBottomRightRadius = 3,
                        },
                    }
                },
            }
        })
    end

    return Theme.Card {
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginBottom = 8,
                children = {
                    UI.Label { text = homeName, fontSize = 11, color = Theme.COLORS.PRIMARY, width = 60 },
                    UI.Label { text = "比赛统计", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1, textAlign = "center", fontWeight = "bold" },
                    UI.Label { text = awayName, fontSize = 11, color = Theme.COLORS.ACCENT, width = 60, textAlign = "right" },
                },
            },
            UI.Panel { width = "100%", children = rows },
        }
    }
end

---------------------------------------------------------------------------
-- 事件时间线
---------------------------------------------------------------------------
function MatchResult._buildEventsTimeline(report, gameState)
    local events = report.events or {}
    if #events == 0 then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "比赛事件" },
                UI.Label { text = "本场比赛风平浪静", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        }
    end

    local rows = {}
    for _, evt in ipairs(events) do
        local player = gameState.players[evt.playerId]
        local pName = player and player.displayName or "未知"
        local icon, text, evtColor = "", "", Theme.COLORS.TEXT_PRIMARY
        local isHome = evt.teamId == report.homeTeamId

        if evt.type == "goal" then
            icon = "⚽"
            local assistText = ""
            if evt.assistPlayerId then
                local assister = gameState.players[evt.assistPlayerId]
                assistText = assister and (" (" .. assister.displayName .. ")") or ""
            end
            text = pName .. assistText
            evtColor = Theme.COLORS.SECONDARY
        elseif evt.type == "yellow_card" then
            icon = "🟨"
            text = pName
            evtColor = Theme.COLORS.WARNING
        elseif evt.type == "red_card" then
            icon = "🟥"
            text = pName
            evtColor = Theme.COLORS.DANGER
        elseif evt.type == "injury" then
            icon = "🏥"
            text = pName .. string.format(" (伤%d天)", evt.injuryDays or 0)
            evtColor = Theme.COLORS.DANGER
        end

        if icon ~= "" then
            table.insert(rows, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingTop = 4,
                paddingBottom = 4,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Label {
                        text = string.format("%d'", evt.minute),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        width = 30,
                    },
                    UI.Label {
                        text = icon,
                        fontSize = 13,
                        width = 20,
                    },
                    UI.Label {
                        text = text,
                        fontSize = 12,
                        color = evtColor,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = isHome and "主" or "客",
                        fontSize = 10,
                        color = Theme.COLORS.TEXT_MUTED,
                        width = 20,
                    },
                }
            })
        end
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "比赛事件 (" .. #rows .. ")" },
            UI.Panel { width = "100%", marginTop = 4, children = rows },
        }
    }
end

---------------------------------------------------------------------------
-- 球员评分
---------------------------------------------------------------------------
function MatchResult._buildPlayerRatings(report, gameState, fixture)
    if not report.playerRatings then return nil end

    -- 确定玩家方的球员ID集合
    local playerPidSet = nil
    if fixture and fixture._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        local playerNation = WorldCup._getPlayerNation(gameState)
        local natTeam = WorldCup.buildNationalTeam(gameState, playerNation)
        if not natTeam then return nil end
        playerPidSet = {}
        for _, pid in ipairs(natTeam.playerIds or {}) do playerPidSet[pid] = true end
    else
        local playerTeam = gameState:getPlayerTeam()
        if not playerTeam then return nil end
    end

    local ratedPlayers = {}
    -- 收集玩家球队出场球员的评分
    for pid, rating in pairs(report.playerRatings) do
        local p = gameState.players[pid]
        local belongs = false
        if playerPidSet then
            belongs = playerPidSet[pid] ~= nil
        else
            belongs = p and p.teamId == gameState.playerTeamId
        end
        if p and belongs then
            table.insert(ratedPlayers, { player = p, rating = rating })
        end
    end

    if #ratedPlayers == 0 then return nil end

    -- 按评分排序
    table.sort(ratedPlayers, function(a, b) return a.rating > b.rating end)

    local rows = {}
    for _, entry in ipairs(ratedPlayers) do
        local p = entry.player
        local rating = entry.rating

        local ratingColor = Theme.COLORS.TEXT_SECONDARY
        if rating >= 8.0 then ratingColor = Theme.COLORS.SECONDARY
        elseif rating >= 7.0 then ratingColor = Theme.COLORS.ACCENT
        elseif rating < 5.5 then ratingColor = Theme.COLORS.DANGER
        elseif rating < 6.5 then ratingColor = Theme.COLORS.WARNING
        end

        -- 获取该球员本场数据
        local goals, assists, cards = 0, 0, ""
        for _, evt in ipairs(report.events) do
            if evt.type == "goal" then
                if evt.playerId == p.id then goals = goals + 1 end
                if evt.assistPlayerId == p.id then assists = assists + 1 end
            elseif evt.type == "yellow_card" and evt.playerId == p.id then
                cards = "🟨"
            elseif evt.type == "red_card" and evt.playerId == p.id then
                cards = "🟥"
            end
        end

        local perfText = ""
        if goals > 0 then perfText = perfText .. "⚽×" .. goals .. " " end
        if assists > 0 then perfText = perfText .. "🅰×" .. assists .. " " end
        perfText = perfText .. cards

        local posColor = Theme.posColor(p.position)
        local posName = Constants.POSITION_NAMES[p.position] or p.position

        table.insert(rows, UI.Panel {
            width = "100%",
            height = 42,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 6,
            paddingRight = 6,
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                -- 位置徽章（与战术页面统一样式）
                UI.Panel {
                    backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 2, paddingBottom = 2,
                    marginRight = 6,
                    minWidth = 36,
                    alignItems = "center",
                    children = {
                        UI.Label { text = posName, fontSize = 10, color = posColor, fontWeight = "bold", maxLines = 1 },
                    },
                },
                -- 姓名
                UI.Label {
                    text = p.displayName,
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                -- 表现标签（增加宽度防止截断）
                UI.Label {
                    text = perfText,
                    fontSize = 11,
                    width = 80,
                    textAlign = "right",
                },
                -- 评分
                UI.Panel {
                    width = 34,
                    height = 24,
                    borderRadius = 4,
                    marginLeft = 4,
                    backgroundColor = ratingColor,
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = string.format("%.1f", rating),
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                    }
                },
            }
        })
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "我方球员评分" },
            UI.Panel { width = "100%", marginTop = 4, children = rows },
        }
    }
end

---------------------------------------------------------------------------
-- 比赛日收入卡片（主场时显示票房明细）
---------------------------------------------------------------------------
function MatchResult._buildRevenueCard(report)
    local rev = report.matchDayRevenue
    if not rev then return nil end

    -- 格式化金额
    local function fmtMoney(amount)
        return FinanceManager.formatMoney(amount)
    end

    -- 上座率颜色
    local attPct = math.floor(rev.attendanceRate * 100)
    local attColor = attPct >= 85 and Theme.COLORS.SECONDARY
        or (attPct >= 70 and Theme.COLORS.WARNING or Theme.COLORS.DANGER)

    -- 对比上场
    local compareSection = nil
    if rev.lastRevenue and rev.lastRevenue > 0 then
        local diff = rev.revenue - rev.lastRevenue
        local diffPct = math.floor(diff / rev.lastRevenue * 100)
        local isUp = diff >= 0
        compareSection = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            marginTop = 6,
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 4, paddingBottom = 4,
            backgroundColor = isUp and {60, 180, 100, 20} or {220, 80, 60, 20},
            borderRadius = 6,
            children = {
                UI.Label {
                    text = isUp and "+" .. diffPct .. "%" or diffPct .. "%",
                    fontSize = 12,
                    fontWeight = "bold",
                    color = isUp and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER,
                },
                UI.Label {
                    text = "  vs 上一主场",
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                },
            }
        }
    end

    return Theme.Card {
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "比赛日收入",
                        fontSize = 15,
                        fontWeight = "bold",
                        color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1,
                    },
                    UI.Panel {
                        paddingLeft = 8, paddingRight = 8,
                        paddingTop = 3, paddingBottom = 3,
                        backgroundColor = {72, 160, 220, 30},
                        borderRadius = 10,
                        children = {
                            UI.Label {
                                text = rev.strategy,
                                fontSize = 10,
                                color = {72, 160, 220, 255},
                            },
                        }
                    },
                }
            },
            -- 大字金额
            UI.Label {
                text = fmtMoney(rev.revenue),
                fontSize = 26,
                fontWeight = "bold",
                color = Theme.COLORS.SECONDARY,
                marginTop = 4,
            },
            -- 对比上一场
            compareSection,
            -- 分隔
            UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.BORDER, marginTop = 10, marginBottom = 10 },
            -- 详情行
            UI.Panel {
                width = "100%",
                children = {
                    -- 上座率
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8,
                        children = {
                            UI.Label { text = "上座率", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 60 },
                            UI.Panel {
                                flexGrow = 1, height = 14, backgroundColor = {38, 46, 71, 255},
                                borderRadius = 7, overflow = "hidden", marginLeft = 8, marginRight = 8,
                                children = {
                                    UI.Panel {
                                        width = attPct .. "%", height = "100%",
                                        backgroundColor = attColor, borderRadius = 7,
                                    },
                                }
                            },
                            UI.Label {
                                text = attPct .. "%",
                                fontSize = 12, fontWeight = "bold", color = attColor, width = 36,
                            },
                        }
                    },
                    -- 入场人数
                    UI.Panel {
                        width = "100%", flexDirection = "row", marginBottom = 4,
                        children = {
                            UI.Label { text = "入场人数", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                            UI.Label {
                                text = string.format("%d / %d", rev.attendance, rev.capacity),
                                fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            },
                        }
                    },
                    -- 票价
                    UI.Panel {
                        width = "100%", flexDirection = "row", marginBottom = 4,
                        children = {
                            UI.Label { text = "票价", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                            UI.Label {
                                text = string.format("%d/张", rev.ticketPrice),
                                fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                            },
                        }
                    },
                    -- 对手热度
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        children = {
                            UI.Label { text = "对手热度", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                            UI.Label {
                                text = rev.opponentName .. " (声望" .. rev.opponentRep .. ")",
                                fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                            },
                        }
                    },
                }
            },
        }
    }
end

return MatchResult
