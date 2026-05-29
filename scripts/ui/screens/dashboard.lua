-- ui/screens/dashboard.lua
-- 主页 Dashboard

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local TurnProcessor = require("scripts/core/turn_processor")
local SaveManager = require("scripts/persistence/save_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local TimeBlockerManager = require("scripts/systems/time_blocker_manager")
local BlockerDialog = require("scripts/ui/components/blocker_dialog")

local Dashboard = {}

------------------------------------------------------
-- 时间推进阻断器：委托给 TimeBlockerManager
------------------------------------------------------
function Dashboard._checkBlockingActions(gameState)
    return TimeBlockerManager.check(gameState)
end

------------------------------------------------------
-- 跳到比赛日：计算距离下一场比赛的天数
------------------------------------------------------
function Dashboard._getDaysToNextMatch(gameState)
    if not gameState.league then return 0 end
    local League = require("scripts/domain/league")
    for daysAhead = 1, 30 do
        local futureDate = League._addDays(gameState.date, daysAhead)
        local fixtures = TurnProcessor.getFixturesForDate(gameState, futureDate)
        for _, f in ipairs(fixtures) do
            if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
                return daysAhead
            end
        end
    end
    return 0  -- 未找到30天内的比赛
end

function Dashboard.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "加载中..." } }
        }
    end

    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "未知"
    local league = gameState.league

    -- 下一场比赛信息
    local nextFixture = league and league:getNextFixture(gameState.playerTeamId) or nil
    local nextMatchText = "暂无比赛安排"
    if nextFixture then
        local opponent = nextFixture.homeTeamId == gameState.playerTeamId
            and gameState.teams[nextFixture.awayTeamId]
            or gameState.teams[nextFixture.homeTeamId]
        local venue = nextFixture.homeTeamId == gameState.playerTeamId and "主场" or "客场"
        if opponent then
            nextMatchText = string.format("%s vs %s (%s) | %d月%d日",
                teamName, opponent.name, venue,
                nextFixture.date.month, nextFixture.date.day)
        end
    end

    -- 排名信息
    local position = league and league:getTeamPosition(gameState.playerTeamId) or 0
    local standing = league and league.standings[gameState.playerTeamId]
    local standingText = position > 0 and string.format("第%d名 | %d分 | %d胜%d平%d负",
        position,
        standing and standing.points or 0,
        standing and standing.wins or 0,
        standing and standing.draws or 0,
        standing and standing.losses or 0
    ) or "暂无数据"

    -- 资金
    local balanceText = team and string.format("%.1fM", team.balance / 1000000) or "0"

    -- 阻断器检查
    local blockers = Dashboard._checkBlockingActions(gameState)
    local isBlocked = TimeBlockerManager.hasBlockingItems(blockers)
    local hasAnyBlockers = #blockers > 0

    -- 跳到比赛日
    local daysToMatch = Dashboard._getDaysToNextMatch(gameState)

    -- 通用推进回调
    local function doAdvanceDay()
        local fixtures = TurnProcessor.advanceDay(gameState)
        SaveManager.save(gameState, "auto")
        local playerFixture = nil
        if fixtures and #fixtures > 0 then
            for _, f in ipairs(fixtures) do
                if f.homeTeamId == gameState.playerTeamId or
                   f.awayTeamId == gameState.playerTeamId then
                    playerFixture = f
                    break
                end
            end
        end
        if playerFixture and playerFixture._pendingPlayerMatch then
            Router.navigate("pre_match", { fixture = playerFixture })
        elseif playerFixture and playerFixture.status == "finished" then
            local report = {
                homeTeamId = playerFixture.homeTeamId,
                awayTeamId = playerFixture.awayTeamId,
                homeGoals = playerFixture.homeGoals,
                awayGoals = playerFixture.awayGoals,
                events = playerFixture.events or {},
                playerRatings = playerFixture.playerRatings,
                stats = playerFixture.stats,
            }
            Router.navigate("match_live", {report = report, fixture = playerFixture, minute = 0})
        else
            Router.replaceWith("dashboard")
        end
    end

    -- 构建页面
    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部状态栏
            UI.Panel {
                width = "100%",
                height = 48,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 14,
                paddingRight = 14,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Label {
                        text = gameState:getDateString(),
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = teamName,
                        fontSize = 13,
                        color = Theme.COLORS.ACCENT,
                        marginRight = 8,
                    },
                    -- 跳到比赛日按钮（2天以上才显示）
                    daysToMatch > 1 and UI.Button {
                        text = "比赛日 >>" .. daysToMatch .. "天",
                        width = 100,
                        height = 32,
                        backgroundColor = hasAnyBlockers and {60, 60, 60, 255} or Theme.COLORS.ACCENT,
                        borderRadius = 6,
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        marginRight = 6,
                        onClick = function()
                            if isBlocked then
                                BlockerDialog.show(blockers)
                                return
                            end
                            if hasAnyBlockers then
                                -- 仅 info 级别：允许强制跳过
                                BlockerDialog.show(blockers, {
                                    onForceAdvance = function()
                                        local skipDays = daysToMatch - 1
                                        for i = 1, skipDays do
                                            local fixtures = TurnProcessor.advanceDay(gameState)
                                            if fixtures and #fixtures > 0 then
                                                for _, f in ipairs(fixtures) do
                                                    if f.homeTeamId == gameState.playerTeamId or
                                                       f.awayTeamId == gameState.playerTeamId then
                                                        if f._pendingPlayerMatch then
                                                            SaveManager.save(gameState, "auto")
                                                            Router.navigate("pre_match", { fixture = f })
                                                            return
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        SaveManager.save(gameState, "auto")
                                        doAdvanceDay()
                                    end,
                                })
                                return
                            end
                            -- 无阻断，直接快进
                            local skipDays = daysToMatch - 1
                            for i = 1, skipDays do
                                local fixtures = TurnProcessor.advanceDay(gameState)
                                if fixtures and #fixtures > 0 then
                                    for _, f in ipairs(fixtures) do
                                        if f.homeTeamId == gameState.playerTeamId or
                                           f.awayTeamId == gameState.playerTeamId then
                                            if f._pendingPlayerMatch then
                                                SaveManager.save(gameState, "auto")
                                                Router.navigate("pre_match", { fixture = f })
                                                return
                                            end
                                        end
                                    end
                                end
                            end
                            SaveManager.save(gameState, "auto")
                            doAdvanceDay()
                        end,
                    } or UI.Panel { width = 0 },
                    UI.Button {
                        text = isBlocked and "! 阻断" or (hasAnyBlockers and "! 继续" or "继续 >"),
                        width = 70,
                        height = 32,
                        backgroundColor = isBlocked and Theme.COLORS.DANGER
                            or (hasAnyBlockers and Theme.COLORS.WARNING or Theme.COLORS.SECONDARY),
                        borderRadius = 6,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        onClick = function()
                            if isBlocked then
                                BlockerDialog.show(blockers)
                                return
                            end
                            if hasAnyBlockers then
                                BlockerDialog.show(blockers, {
                                    onForceAdvance = function()
                                        doAdvanceDay()
                                    end,
                                })
                                return
                            end
                            doAdvanceDay()
                        end,
                    },
                }
            },

            -- 滚动内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = {
                    -- 紧急消息提醒卡（有未读高优先级消息时显示）
                    Dashboard._buildUrgentCard(gameState),

                    -- 合同到期预警卡
                    Dashboard._buildContractExpiryCard(gameState),

                    -- 董事会满意度卡
                    Dashboard._buildBoardCard(gameState, team),

                    -- 下一场比赛卡（含对手实力对比）
                    Dashboard._buildNextMatchCard(gameState, team, nextFixture, nextMatchText),

                    -- 联赛排名卡
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = "联赛排名" },
                            UI.Label {
                                text = standingText,
                                fontSize = 14,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginTop = 4,
                            },
                        }
                    },

                    -- 财务概览卡
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = "财务概览" },
                            UI.Panel {
                                flexDirection = "row",
                                marginTop = 6,
                                children = {
                                    Theme.StatPill { label = "资金", value = balanceText },
                                    Theme.StatPill { label = "工资预算", value = team and string.format("%.0fK", team.wageBudget/1000) or "0" },
                                }
                            },
                        }
                    },

                    -- 阵容状态卡
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = "阵容状态" },
                            UI.Panel {
                                flexDirection = "row",
                                marginTop = 6,
                                flexWrap = "wrap",
                                children = {
                                    Theme.StatPill { label = "球员", value = team and #team.playerIds or 0 },
                                    Theme.StatPill { label = "首发", value = team and #team.startingXI or 0 },
                                    Theme.StatPill {
                                        label = "伤病",
                                        value = Dashboard._countInjured(gameState),
                                        valueColor = Theme.COLORS.DANGER,
                                    },
                                }
                            },
                        }
                    },

                    -- 近期状态卡
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = "近期状态" },
                            UI.Label {
                                text = team and #team.recentForm > 0 and table.concat(team.recentForm, " ") or "暂无比赛",
                                fontSize = 16,
                                color = Theme.COLORS.TEXT_PRIMARY,
                                marginTop = 4,
                            },
                        }
                    },

                    -- 欧冠状态卡（有欧冠时显示）
                    Dashboard._buildUCLCard(gameState),

                    -- 世界杯状态卡（有世界杯时显示）
                    Dashboard._buildWCCard(gameState),

                    -- 收件箱快捷卡
                    Dashboard._buildInboxCard(gameState),
                }
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }

    return page
end

function Dashboard._countInjured(gameState)
    local count = 0
    local team = gameState:getPlayerTeam()
    if not team then return 0 end
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and p.injured then count = count + 1 end
    end
    return count
end

-- 欧冠状态卡
function Dashboard._buildUCLCard(gameState)
    local ucl = gameState.championsLeague
    if not ucl then return UI.Panel { height = 0 } end

    local phaseNames = {
        not_started = "未开始", group = "小组赛",
        r16 = "1/8 决赛", qf = "1/4 决赛",
        sf = "半决赛", final = "决赛", completed = "已结束",
    }
    local phaseText = phaseNames[ucl.phase] or ucl.phase

    -- 玩家在欧冠中的状态
    local playerStatus = "未参赛"
    if ucl.qualifiedTeams then
        for _, tid in ipairs(ucl.qualifiedTeams) do
            if tid == gameState.playerTeamId then
                playerStatus = "参赛中"
                break
            end
        end
    end
    if ucl.champion then
        if ucl.champion == gameState.playerTeamId then
            playerStatus = "冠军!"
        else
            local champTeam = gameState.teams[ucl.champion]
            playerStatus = "冠军: " .. (champTeam and champTeam.name or "?")
        end
    end

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                children = {
                    Theme.Subtitle { text = "欧冠" },
                    UI.Label {
                        text = " | " .. phaseText,
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1,
                    },
                    UI.Button {
                        text = "查看", width = 50, height = 28,
                        backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 6,
                        fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function() Router.navigate("league", {tab = "UCL"}) end,
                    },
                }
            },
            UI.Label {
                text = playerStatus,
                fontSize = 14, color = Theme.COLORS.ACCENT, marginTop = 4,
            },
        }
    }
end

-- 世界杯状态卡
function Dashboard._buildWCCard(gameState)
    local wc = gameState.worldCup
    if not wc then return UI.Panel { height = 0 } end

    local phaseNames = {
        not_started = "未开始", group = "小组赛",
        r16 = "1/8 决赛", qf = "1/4 决赛",
        sf = "半决赛", final = "决赛", completed = "已结束",
    }
    local phaseText = phaseNames[wc.phase] or wc.phase

    local statusText = string.format("%d 世界杯 | %s", wc.season, phaseText)
    if wc.champion then
        local WorldCupSystem = require("scripts/systems/world_cup")
        statusText = statusText .. " | 冠军: " .. WorldCupSystem._getNationName(wc.champion)
    end

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                children = {
                    Theme.Subtitle { text = "世界杯" },
                    UI.Label {
                        text = " | " .. phaseText,
                        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1,
                    },
                    UI.Button {
                        text = "查看", width = 50, height = 28,
                        backgroundColor = {180, 140, 20, 255}, borderRadius = 6,
                        fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function() Router.navigate("league", {tab = "WC"}) end,
                    },
                }
            },
            UI.Label {
                text = statusText,
                fontSize = 14, color = {255, 200, 50, 255}, marginTop = 4,
            },
        }
    }
end

------------------------------------------------------
-- 紧急消息提醒卡
------------------------------------------------------
function Dashboard._buildUrgentCard(gameState)
    -- 统计高优先级未读消息
    local urgentMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read and msg.priority == "high" then
            table.insert(urgentMsgs, msg)
            if #urgentMsgs >= 3 then break end
        end
    end

    if #urgentMsgs == 0 then
        return UI.Panel { height = 0 }
    end

    local msgLines = {}
    for _, msg in ipairs(urgentMsgs) do
        table.insert(msgLines, UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Panel {
                    width = 6, height = 6,
                    borderRadius = 3,
                    backgroundColor = Theme.COLORS.DANGER,
                    marginRight = 8,
                },
                UI.Label {
                    text = msg.title or "消息",
                    fontSize = 12,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1, flexShrink = 1,
                },
            }
        })
    end

    local totalUnread = gameState:getUnreadCount()

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 8,
                children = {
                    UI.Label {
                        text = "⚠ 紧急通知",
                        fontSize = 13,
                        color = Theme.COLORS.DANGER,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = totalUnread .. "条未读",
                        fontSize = 11,
                        color = Theme.COLORS.ACCENT,
                    },
                }
            },
            UI.Panel { width = "100%", children = msgLines },
            UI.Button {
                text = "查看收件箱",
                width = "100%", height = 34,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.PRIMARY,
                marginTop = 6,
                onClick = function() Router.navigate("inbox") end,
            },
        }
    }
end

------------------------------------------------------
-- 合同到期预警卡
------------------------------------------------------
function Dashboard._buildContractExpiryCard(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return UI.Panel { height = 0 } end

    local expiringPlayers = {}
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and p.contractEnd then
            local monthsLeft = (p.contractEnd.year - gameState.date.year) * 12
                + (p.contractEnd.month - gameState.date.month)
            if monthsLeft <= 6 then
                table.insert(expiringPlayers, { player = p, months = monthsLeft })
            end
        end
    end

    if #expiringPlayers == 0 then
        return UI.Panel { height = 0 }
    end

    -- 按紧急度排序
    table.sort(expiringPlayers, function(a, b) return a.months < b.months end)

    local rows = {}
    local showCount = math.min(3, #expiringPlayers)
    for i = 1, showCount do
        local item = expiringPlayers[i]
        local p = item.player
        local urgencyColor = item.months <= 2 and Theme.COLORS.DANGER or Theme.COLORS.WARNING
        table.insert(rows, UI.Panel {
            width = "100%", height = 28,
            flexDirection = "row", alignItems = "center",
            children = {
                UI.Label {
                    text = p.position,
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 30,
                },
                UI.Label {
                    text = p.displayName,
                    fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1, flexShrink = 1,
                },
                UI.Label {
                    text = item.months <= 0 and "已到期" or (item.months .. "个月"),
                    fontSize = 11, color = urgencyColor,
                    width = 50, textAlign = "right",
                },
            }
        })
    end

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Label {
                        text = "合同到期预警",
                        fontSize = 13, color = Theme.COLORS.WARNING,
                        fontWeight = "bold", flexGrow = 1,
                    },
                    UI.Label {
                        text = #expiringPlayers .. "人",
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
            UI.Panel { width = "100%", children = rows },
            #expiringPlayers > showCount and UI.Label {
                text = string.format("...还有 %d 名球员合同即将到期", #expiringPlayers - showCount),
                fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
            } or UI.Panel { height = 0 },
            UI.Button {
                text = "管理阵容",
                width = "100%", height = 32,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.WARNING,
                marginTop = 6,
                onClick = function() Router.navigate("squad") end,
            },
        }
    }
end

------------------------------------------------------
-- 董事会满意度卡
------------------------------------------------------
function Dashboard._buildBoardCard(gameState, team)
    if not team then return UI.Panel { height = 0 } end

    local satisfaction = team.boardSatisfaction or 50
    local objective = team.boardObjective or "未设定"
    local warnings = team.boardWarnings or 0

    -- 满意度颜色
    local satColor = Theme.COLORS.SECONDARY
    if satisfaction < 30 then satColor = Theme.COLORS.DANGER
    elseif satisfaction < 50 then satColor = Theme.COLORS.WARNING
    elseif satisfaction < 70 then satColor = Theme.COLORS.ACCENT end

    -- 满意度文本
    local satText = "非常满意"
    if satisfaction < 20 then satText = "极度不满"
    elseif satisfaction < 35 then satText = "不满"
    elseif satisfaction < 50 then satText = "一般"
    elseif satisfaction < 70 then satText = "满意"
    end

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 8,
                children = {
                    Theme.Subtitle { text = "董事会" },
                    UI.Panel { flexGrow = 1 },
                    -- 警告标记
                    warnings > 0 and UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 2, paddingBottom = 2,
                        borderRadius = 4,
                        backgroundColor = {Theme.COLORS.DANGER[1], Theme.COLORS.DANGER[2], Theme.COLORS.DANGER[3], 40},
                        children = {
                            UI.Label {
                                text = warnings .. "次警告",
                                fontSize = 10, color = Theme.COLORS.DANGER,
                            }
                        }
                    } or UI.Panel { width = 0 },
                }
            },
            -- 目标
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Label { text = "赛季目标:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginRight = 6 },
                    UI.Label { text = objective, fontSize = 12, color = Theme.COLORS.ACCENT, fontWeight = "bold" },
                }
            },
            -- 满意度条
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                children = {
                    UI.Label { text = "满意度:", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginRight = 6 },
                    UI.Panel {
                        flexGrow = 1, height = 14,
                        backgroundColor = {38, 46, 71, 255}, borderRadius = 7,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = satisfaction .. "%",
                                height = "100%",
                                backgroundColor = satColor,
                                borderRadius = 7,
                            },
                        }
                    },
                    UI.Label {
                        text = " " .. satText,
                        fontSize = 11, color = satColor, width = 65,
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- 信息中心卡（消息/新闻/财务快捷入口 + 最近消息摘要）
------------------------------------------------------
function Dashboard._buildInboxCard(gameState)
    local unreadCount = gameState:getUnreadCount()

    -- 最近2条未读消息
    local recentMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read then
            table.insert(recentMsgs, msg)
            if #recentMsgs >= 2 then break end
        end
    end

    local children = {
        -- 标题行
        UI.Panel {
            flexDirection = "row", alignItems = "center", marginBottom = 8,
            children = {
                Theme.Subtitle { text = "收件箱" },
                unreadCount > 0 and UI.Panel {
                    marginLeft = 6,
                    paddingLeft = 6, paddingRight = 6,
                    paddingTop = 1, paddingBottom = 1,
                    borderRadius = 8,
                    backgroundColor = Theme.COLORS.DANGER,
                    children = {
                        UI.Label {
                            text = tostring(unreadCount),
                            fontSize = 10, color = Theme.COLORS.TEXT_PRIMARY,
                        }
                    }
                } or UI.Panel { width = 0 },
                UI.Panel { flexGrow = 1 },
                UI.Button {
                    text = "查看全部",
                    width = 60, height = 28,
                    backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 6,
                    fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function() Router.navigate("inbox") end,
                },
            }
        },
    }

    -- 显示最近消息摘要
    if #recentMsgs > 0 then
        for _, msg in ipairs(recentMsgs) do
            table.insert(children, UI.Panel {
                width = "100%", height = 28,
                flexDirection = "row", alignItems = "center",
                marginTop = 4,
                children = {
                    UI.Label {
                        text = "· " .. (msg.title or "消息"),
                        fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        flexGrow = 1, flexShrink = 1,
                    },
                    UI.Label {
                        text = msg.date and string.format("%d/%d", msg.date.month, msg.date.day) or "",
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            })
        end
    elseif unreadCount == 0 then
        table.insert(children, UI.Label {
            text = "没有新消息",
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
        })
    end

    -- 快捷入口按钮行（新闻 / 财务）
    table.insert(children, UI.Panel {
        width = "100%",
        flexDirection = "row",
        marginTop = 10,
        children = {
            UI.Button {
                text = "新闻动态",
                flexGrow = 1, height = 32,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.ACCENT,
                marginRight = 8,
                onClick = function() Router.navigate("news") end,
            },
            UI.Button {
                text = "财务详情",
                flexGrow = 1, height = 32,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 6, fontSize = 12,
                color = Theme.COLORS.ACCENT,
                onClick = function() Router.navigate("finance") end,
            },
        }
    })

    return Theme.Card { children = children }
end

------------------------------------------------------
-- 下一场比赛卡（含对手实力对比）
------------------------------------------------------
function Dashboard._buildNextMatchCard(gameState, team, nextFixture, nextMatchText)
    if not nextFixture or not team then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "下一场比赛" },
                UI.Label { text = nextMatchText, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, marginTop = 4 },
            }
        }
    end

    local opponentId = nextFixture.homeTeamId == gameState.playerTeamId
        and nextFixture.awayTeamId or nextFixture.homeTeamId
    local opponent = gameState.teams[opponentId]
    if not opponent then
        return Theme.Card {
            children = {
                Theme.Subtitle { text = "下一场比赛" },
                UI.Label { text = nextMatchText, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, marginTop = 4 },
            }
        }
    end

    -- 计算平均能力
    local function calcAvgAbility(t)
        local total, count = 0, 0
        for _, pid in ipairs(t.playerIds or {}) do
            local p = gameState.players[pid]
            if p then total = total + (p.overall or 50); count = count + 1 end
        end
        return count > 0 and math.floor(total / count) or 50
    end

    local myAvg = calcAvgAbility(team)
    local oppAvg = calcAvgAbility(opponent)
    local isHome = nextFixture.homeTeamId == gameState.playerTeamId
    local venue = isHome and "主场" or "客场"

    -- 实力对比条宽度
    local totalAbility = myAvg + oppAvg
    local myPct = totalAbility > 0 and math.floor(myAvg / totalAbility * 100) or 50

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "下一场比赛" },
            UI.Label {
                text = nextMatchText,
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, marginTop = 4,
            },
            -- 实力对比
            UI.Panel {
                width = "100%", marginTop = 10,
                children = {
                    UI.Panel {
                        flexDirection = "row", marginBottom = 4,
                        children = {
                            UI.Label { text = team.name, fontSize = 11, color = Theme.COLORS.ACCENT, flexGrow = 1 },
                            UI.Label { text = "实力对比", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Panel { flexGrow = 1 },
                            UI.Label { text = opponent.name, fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                        }
                    },
                    -- 对比条
                    UI.Panel {
                        width = "100%", height = 12, borderRadius = 6,
                        backgroundColor = Theme.COLORS.DANGER,
                        overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = myPct .. "%", height = "100%",
                                backgroundColor = Theme.COLORS.PRIMARY,
                                borderRadius = 6,
                            },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", marginTop = 4,
                        children = {
                            UI.Label { text = tostring(myAvg), fontSize = 12, color = Theme.COLORS.ACCENT, fontWeight = "bold", flexGrow = 1 },
                            UI.Label { text = "(" .. venue .. ")", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Panel { flexGrow = 1 },
                            UI.Label { text = tostring(oppAvg), fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold" },
                        }
                    },
                }
            },
        }
    }
end

return Dashboard
