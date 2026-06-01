-- ui/screens/dashboard.lua
-- 主页 Dashboard - "驾驶舱"设计
-- 视觉层级：Hero比赛区 > 行动区 > 俱乐部状态 > 信息流

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
local ObjectivesManager = require("scripts/systems/objectives_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local Dashboard = {}

------------------------------------------------------
-- 时间推进阻断器
------------------------------------------------------
function Dashboard._checkBlockingActions(gameState)
    return TimeBlockerManager.check(gameState)
end

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
    return 0
end

------------------------------------------------------
-- 主入口
------------------------------------------------------
function Dashboard.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            justifyContent = "center", alignItems = "center",
            children = { UI.Label { text = "加载中...", color = Theme.COLORS.TEXT_MUTED } }
        }
    end

    local team = gameState:getPlayerTeam()
    local teamName = team and team.name or "未知"
    local league = gameState.league

    -- 阻断器检查
    local blockers = Dashboard._checkBlockingActions(gameState)
    local isBlocked = TimeBlockerManager.hasBlockingItems(blockers)
    local hasAnyBlockers = #blockers > 0

    -- 跳到比赛日
    local daysToMatch = Dashboard._getDaysToNextMatch(gameState)

    -- 通用推进回调
    local function doAdvanceDay()
        -- 如果有未完成的玩家比赛，先处理它（不推进日期）
        if gameState.pendingPlayerFixture then
            local pf = gameState.pendingPlayerFixture
            Router.navigate("pre_match", { fixture = pf })
            return
        end

        local fixtures = TurnProcessor.advanceDay(gameState)
        SaveManager.save(gameState, "auto")
        local playerFixture = nil
        if fixtures and #fixtures > 0 then
            for _, f in ipairs(fixtures) do
                if f._pendingPlayerMatch then
                    playerFixture = f
                    break
                end
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

    local function doSkipToMatchDay()
        local skipDays = daysToMatch - 1
        for i = 1, skipDays do
            local fixtures = TurnProcessor.advanceDay(gameState)
            if fixtures and #fixtures > 0 then
                for _, f in ipairs(fixtures) do
                    if f._pendingPlayerMatch then
                        SaveManager.save(gameState, "auto")
                        Router.navigate("pre_match", { fixture = f })
                        return
                    end
                end
            end
        end
        SaveManager.save(gameState, "auto")
        doAdvanceDay()
    end

    -- 构建页面
    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部状态栏：日期 + 推进按钮
            Dashboard._buildTopBar(gameState, teamName, isBlocked, hasAnyBlockers, blockers, daysToMatch, doAdvanceDay, doSkipToMatchDay),

            -- 滚动内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 12,
                children = {
                    -- [Hero区] 下一场比赛大卡
                    Dashboard._buildMatchHero(gameState, team),

                    -- [紧急事项] 仅在有紧急消息/合同到期时显示
                    Dashboard._buildUrgentSection(gameState, team),

                    -- [俱乐部快照] 合并后的完整状态面板
                    Dashboard._buildClubSnapshot(gameState, team),

                    -- [动态流] 近期新闻/收件箱入口
                    Dashboard._buildActivityFeed(gameState),

                    -- 底部留白
                    UI.Panel { height = 12 },
                }
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }
end

------------------------------------------------------
-- 顶部操作栏
------------------------------------------------------
function Dashboard._buildTopBar(gameState, teamName, isBlocked, hasAnyBlockers, blockers, daysToMatch, doAdvanceDay, doSkipToMatchDay)
    -- 继续按钮颜色和文本
    local continueColor = isBlocked and Theme.COLORS.DANGER
        or (hasAnyBlockers and Theme.COLORS.WARNING or Theme.COLORS.FINANCE_GREEN)
    local continueText = isBlocked and "! 阻断"
        or (hasAnyBlockers and "! 继续" or "继续 >")

    local children = {
        -- 日期
        UI.Label {
            text = gameState:getDateString(),
            fontSize = 13,
            color = Theme.COLORS.TEXT_SECONDARY,
        },
        -- 球队名（点击查看经理档案）
        UI.Button {
            text = " | " .. teamName,
            height = 30,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            fontSize = 13,
            color = Theme.COLORS.MATCH_ORANGE,
            onClick = function()
                Router.navigate("manager_view")
            end,
        },
        UI.Panel { flexGrow = 1 },
        -- 荣誉室按钮
        UI.Button {
            text = "🏆",
            width = 30,
            height = 30,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            borderRadius = 15,
            fontSize = 16,
            color = Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Router.navigate("trophy_cabinet")
            end,
        },
        -- 设置按钮
        UI.Button {
            text = "⚙",
            width = 30,
            height = 30,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            borderRadius = 15,
            fontSize = 16,
            color = Theme.COLORS.TEXT_MUTED,
            marginRight = 6,
            onClick = function()
                Router.navigate("settings")
            end,
        },
    }

    -- 跳到比赛日按钮（2天以上显示）
    if daysToMatch > 1 then
        table.insert(children, UI.Button {
            text = ">>" .. daysToMatch .. "天",
            width = 64,
            height = 30,
            backgroundColor = hasAnyBlockers and Theme.COLORS.BG_SURFACE or Theme.COLORS.BG_CARD_ELEVATED,
            borderRadius = 6,
            fontSize = 11,
            color = hasAnyBlockers and Theme.COLORS.TEXT_MUTED or Theme.COLORS.MATCH_ORANGE,
            marginRight = 6,
            onClick = function()
                if isBlocked then
                    BlockerDialog.show(blockers)
                    return
                end
                if hasAnyBlockers then
                    BlockerDialog.show(blockers, { onForceAdvance = doSkipToMatchDay })
                    return
                end
                doSkipToMatchDay()
            end,
        })
    end

    -- 继续按钮（核心 CTA）
    table.insert(children, UI.Button {
        text = continueText,
        width = 80,
        height = 34,
        backgroundColor = continueColor,
        borderRadius = 8,
        fontSize = 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        onClick = function()
            if isBlocked then
                BlockerDialog.show(blockers)
                return
            end
            if hasAnyBlockers then
                BlockerDialog.show(blockers, { onForceAdvance = doAdvanceDay })
                return
            end
            doAdvanceDay()
        end,
    })

    return UI.Panel {
        width = "100%",
        height = 50,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14,
        paddingRight = 14,
        backgroundColor = Theme.COLORS.BG_HEADER,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = children,
    }
end

------------------------------------------------------
-- [Hero区] 下一场比赛大卡
------------------------------------------------------
function Dashboard._buildMatchHero(gameState, team)
    local TeamIcon = require("scripts/ui/components/team_icon")

    if not team then return UI.Panel { height = 0 } end

    local league = gameState.league
    local nextFixture = league and league:getNextFixture(gameState.playerTeamId) or nil

    if not nextFixture then
        return Theme.HeroCard {
            accentColor = Theme.COLORS.MATCH_ORANGE,
            children = {
                Theme.SectionHeader { text = "下一场比赛", color = Theme.COLORS.MATCH_ORANGE },
                UI.Label {
                    text = "暂无比赛安排",
                    fontSize = 14, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                },
            }
        }
    end

    local opponentId = nextFixture.homeTeamId == gameState.playerTeamId
        and nextFixture.awayTeamId or nextFixture.homeTeamId
    local opponent = gameState.teams[opponentId]
    local isHome = nextFixture.homeTeamId == gameState.playerTeamId
    local venue = isHome and "主场" or "客场"
    local opponentName = opponent and opponent.name or "未知"

    -- 日期和倒计时
    local matchDateStr = string.format("%d月%d日", nextFixture.date.month, nextFixture.date.day)
    local daysToMatch = Dashboard._getDaysToNextMatch(gameState)
    local countdownText = daysToMatch <= 1 and "明天" or (daysToMatch .. "天后")

    -- 联赛信息
    local leagueName = league and league.name or ""
    local roundNum = league and league.currentRound or 1

    -- 球队状态数据（真实数据）
    local injuredCount = 0
    local lowFitnessCount = 0
    local totalFitness = 0
    local playerCount = 0
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p then
            playerCount = playerCount + 1
            totalFitness = totalFitness + (p.fitness or 100)
            if p.injured then injuredCount = injuredCount + 1 end
            if p.fitness and p.fitness < 70 then lowFitnessCount = lowFitnessCount + 1 end
        end
    end
    local avgFitness = playerCount > 0 and math.floor(totalFitness / playerCount) or 100
    local formation = team.formation or "4-4-2"

    -- 球队状态描述
    local fitnessDesc
    if avgFitness >= 85 then fitnessDesc = "良好"
    elseif avgFitness >= 70 then fitnessDesc = "一般"
    else fitnessDesc = "疲劳" end

    local fitnessColor
    if avgFitness >= 85 then fitnessColor = Theme.COLORS.FINANCE_GREEN
    elseif avgFitness >= 70 then fitnessColor = Theme.COLORS.MATCH_ORANGE
    else fitnessColor = Theme.COLORS.DANGER end

    return UI.Panel {
        width = "100%",
        backgroundImage = "image/bg_dashboard_hero_v2_20260529085135.png",
        backgroundFit = "cover",
        imageTint = {70, 70, 90, 255},
        borderRadius = 14,
        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
        marginBottom = 12,
        overflow = "hidden",
        children = {
            -- 顶部标题：下一场比赛 + 倒计时标签
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
                marginBottom = 6,
                children = {
                    UI.Label { text = "下一场比赛", fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY },
                    UI.Panel {
                        backgroundColor = {Theme.COLORS.FINANCE_GREEN[1], Theme.COLORS.FINANCE_GREEN[2], Theme.COLORS.FINANCE_GREEN[3], 200},
                        borderRadius = 10,
                        paddingLeft = 8, paddingRight = 8, paddingTop = 2, paddingBottom = 2,
                        marginLeft = 8,
                        children = {
                            UI.Label { text = countdownText, fontSize = 10, color = {255, 255, 255, 255}, fontWeight = "bold" },
                        }
                    },
                }
            },

            -- 日期行
            UI.Panel {
                width = "100%", alignItems = "center", marginBottom = 16,
                children = {
                    UI.Label { text = matchDateStr, fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                }
            },

            -- 中心对阵区：队徽 + 名字 + VS
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                marginBottom = 16,
                children = {
                    -- 我方：队徽 + 名字
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            TeamIcon { team = team, size = 52 },
                            UI.Label {
                                text = team.name,
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                textAlign = "center", marginTop = 8,
                            },
                        }
                    },
                    -- VS
                    UI.Panel {
                        width = 50, alignItems = "center",
                        children = {
                            UI.Label {
                                text = "VS",
                                fontSize = 18, color = Theme.COLORS.MATCH_ORANGE, fontWeight = "bold",
                            },
                        }
                    },
                    -- 对手：队徽 + 名字
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            TeamIcon { team = opponent, size = 52 },
                            UI.Label {
                                text = opponentName,
                                fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold",
                                textAlign = "center", marginTop = 8,
                            },
                        }
                    },
                }
            },

            -- 赛事信息行
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "center", alignItems = "center",
                marginBottom = 14,
                children = {
                    UI.Label { text = leagueName .. " 第" .. roundNum .. "轮", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "  ·  ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = venue, fontSize = 11, color = Theme.COLORS.MATCH_ORANGE, fontWeight = "bold" },
                }
            },

            -- 分隔线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = {255, 255, 255, 20},
                marginBottom = 12,
            },

            -- 底部状态条：球队状态 / 伤病 / 阵型
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-around", alignItems = "center",
                children = {
                    -- 球队状态（表情图标）
                    UI.Panel {
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = avgFitness >= 85 and "😊" or (avgFitness >= 70 and "😐" or "😟"),
                                fontSize = 20, marginBottom = 2,
                            },
                            UI.Label { text = "球队状态", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 2 },
                            UI.Label { text = fitnessDesc, fontSize = 12, color = fitnessColor, fontWeight = "bold" },
                        }
                    },
                    -- 伤病（医疗图标）
                    UI.Panel {
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 26, height = 26, borderRadius = 13,
                                backgroundColor = injuredCount > 0 and {80, 30, 30, 255} or {30, 70, 40, 255},
                                justifyContent = "center", alignItems = "center", marginBottom = 2,
                                children = {
                                    UI.Label {
                                        text = injuredCount > 0 and "+" or "+",
                                        fontSize = 16, fontWeight = "bold",
                                        color = injuredCount > 0 and Theme.COLORS.DANGER or Theme.COLORS.FINANCE_GREEN,
                                    },
                                }
                            },
                            UI.Label { text = "伤病情况", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 2 },
                            UI.Label {
                                text = injuredCount > 0 and (injuredCount .. "名球员") or "无伤病",
                                fontSize = 12,
                                color = injuredCount > 0 and Theme.COLORS.DANGER or Theme.COLORS.FINANCE_GREEN,
                                fontWeight = "bold",
                            },
                        }
                    },
                    -- 阵型
                    UI.Panel {
                        alignItems = "center",
                        children = {
                            UI.Label { text = "⚽", fontSize = 20, marginBottom = 2 },
                            UI.Label { text = "预计阵容", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 2 },
                            UI.Label { text = formation, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        }
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- [紧急事项] 合同到期 + 高优先级消息
------------------------------------------------------
function Dashboard._buildUrgentSection(gameState, team)
    local items = {}

    -- 合同到期预警
    if team then
        local expiringCount = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and p.contractEnd then
                local monthsLeft = (p.contractEnd.year - gameState.date.year) * 12
                    + (p.contractEnd.month - gameState.date.month)
                if monthsLeft <= 6 then expiringCount = expiringCount + 1 end
            end
        end
        if expiringCount > 0 then
            table.insert(items, {
                icon = "!",
                text = expiringCount .. "名球员合同即将到期",
                color = Theme.COLORS.WARNING,
                action = function() Router.navigate("squad") end,
            })
        end
    end

    -- 高优先级未读消息
    local urgentCount = 0
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read and msg.priority == "high" then
            urgentCount = urgentCount + 1
        end
    end
    if urgentCount > 0 then
        table.insert(items, {
            icon = "!",
            text = urgentCount .. "条紧急消息待处理",
            color = Theme.COLORS.DANGER,
            action = function() Router.navigate("inbox") end,
        })
    end

    -- 董事会警告
    if team and (team.boardWarnings or 0) > 0 then
        table.insert(items, {
            icon = "!",
            text = "董事会发出" .. team.boardWarnings .. "次警告",
            color = Theme.COLORS.DANGER,
            action = function() Router.navigate("inbox") end,
        })
    end

    if #items == 0 then return UI.Panel { height = 0 } end

    local rows = {}
    for _, item in ipairs(items) do
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 36,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = {item.color[1], item.color[2], item.color[3], 20},
            borderRadius = 8,
            marginBottom = 6,
            children = {
                UI.Panel {
                    width = 6, height = 6, borderRadius = 3,
                    backgroundColor = item.color, marginRight = 8,
                },
                UI.Label {
                    text = item.text,
                    fontSize = 12, color = item.color,
                    flexGrow = 1, flexShrink = 1,
                },
                UI.Label {
                    text = ">", fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
                },
            },
            onClick = item.action,
        })
    end

    return UI.Panel {
        width = "100%",
        marginBottom = 12,
        children = rows,
    }
end

------------------------------------------------------
-- [俱乐部快照] 指挥中心式混合布局
-- 联赛=全宽记分牌 | 财务+阵容=异构双栏 | 目标=里程碑条
------------------------------------------------------
function Dashboard._buildClubSnapshot(gameState, team)
    if not team then return UI.Panel { height = 0 } end

    local league = gameState.league
    local position = league and league:getTeamPosition(gameState.playerTeamId) or 0
    local standing = league and league.standings[gameState.playerTeamId]

    -- 财务数据
    local balanceText = FinanceManager.formatMoney(team.balance or 0)
    local netIncome = (team.seasonIncome or 0) - (team.seasonExpense or 0)
    local netColor = netIncome >= 0 and Theme.COLORS.FINANCE_GREEN or Theme.COLORS.DANGER
    local netText = (netIncome >= 0 and "+" or "") .. FinanceManager.formatMoney(netIncome)

    -- 工资预算使用率
    local totalWage = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then totalWage = totalWage + (p.wage or 0) end
    end
    local wagePct = team.wageBudget > 0 and math.floor(totalWage / team.wageBudget * 100) or 0
    local wageColor = wagePct > 90 and Theme.COLORS.DANGER
        or (wagePct > 70 and Theme.COLORS.WARNING or Theme.COLORS.FINANCE_GREEN)

    -- 伤病统计
    local injuredCount = Dashboard._countInjured(gameState)

    -- 赛事信息
    local uclInfo = Dashboard._getUCLInfo(gameState)

    -- 最近比赛战绩
    local recentForm = Dashboard._getRecentForm(gameState)

    -- 战绩符号（W/D/L 圆点）
    local formDots = {}
    if standing then
        local results = gameState.recentResults or {}
        if #results == 0 and #recentForm > 0 then
            for _, pts in ipairs(recentForm) do
                if pts == 3 then table.insert(formDots, "W")
                elseif pts == 1 then table.insert(formDots, "D")
                else table.insert(formDots, "L") end
            end
        else
            for i = math.max(1, #results - 4), #results do
                local r = results[i]
                if r then table.insert(formDots, r) end
            end
        end
    end

    -- ═══════════════════════════════════════════════
    -- [1] 赛事概览 - 联赛 + 欧冠对称双栏
    -- ═══════════════════════════════════════════════

    -- 构建战绩圆点
    local formDotsChildren = (function()
        local dots = {}
        if #formDots > 0 then
            for _, r in ipairs(formDots) do
                local c = r == "W" and Theme.COLORS.FINANCE_GREEN
                    or (r == "D" and Theme.COLORS.WARNING or Theme.COLORS.DANGER)
                table.insert(dots, UI.Panel {
                    width = 16, height = 16, borderRadius = 8,
                    backgroundColor = {c[1], c[2], c[3], 30},
                    alignItems = "center", justifyContent = "center",
                    marginRight = 3,
                    children = {
                        UI.Label { text = r, fontSize = 8, color = c, fontWeight = "bold" },
                    }
                })
            end
        elseif standing then
            table.insert(dots, UI.Label {
                text = (standing.wins or 0) .. "W " .. (standing.draws or 0) .. "D " .. (standing.losses or 0) .. "L",
                fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
            })
        else
            table.insert(dots, UI.Label { text = "赛季未开始", fontSize = 9, color = Theme.COLORS.TEXT_MUTED })
        end
        return dots
    end)()

    -- 联赛半块
    local leagueHalf = UI.Panel {
        flexGrow = 1, flexBasis = "48%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 12,
        padding = 12, marginRight = 4,
        onClick = function() Router.navigate("league") end,
        children = {
            -- 排名行
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                children = {
                    UI.Panel {
                        alignItems = "center", justifyContent = "center",
                        width = 36, height = 36,
                        backgroundColor = {Theme.COLORS.INFO_BLUE[1], Theme.COLORS.INFO_BLUE[2], Theme.COLORS.INFO_BLUE[3], 20},
                        borderRadius = 10,
                        children = {
                            UI.Label {
                                text = position > 0 and tostring(position) or "-",
                                fontSize = (position >= 10) and 14 or 18,
                                color = Theme.COLORS.INFO_BLUE, fontWeight = "bold",
                            },
                        }
                    },
                    UI.Panel {
                        marginLeft = 8, flexShrink = 1,
                        children = {
                            UI.Label { text = "联赛", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            standing and UI.Label {
                                text = (standing.points or 0) .. " 分",
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                            } or UI.Label { text = "—", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                }
            },
            -- 战绩圆点
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginTop = 8,
                children = formDotsChildren,
            },
        }
    }

    -- 欧冠/杯赛半块（与联赛对称）
    local cupHalf
    if uclInfo then
        -- 排名数字：去掉 # 前缀只显示数字，方便在小方块里展示
        local posNum = uclInfo.posText:gsub("^#", "")
        local hasPos = uclInfo.posText ~= ""
        -- 根据数字位数调整字号：1-2位用18px，3位用14px
        local posFontSize = hasPos and (string.len(posNum) <= 2 and 18 or 14) or 14

        cupHalf = UI.Panel {
            flexGrow = 1, flexBasis = "48%",
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 12,
            padding = 12, marginLeft = 4,
            onClick = function() Router.navigate("league", { tab = "UCL" }) end,
            children = {
                -- 排名行（与联赛对称）
                UI.Panel {
                    flexDirection = "row", alignItems = "center",
                    children = {
                        UI.Panel {
                            alignItems = "center", justifyContent = "center",
                            width = 36, height = 36,
                            backgroundColor = {uclInfo.color[1], uclInfo.color[2], uclInfo.color[3], 20},
                            borderRadius = 10,
                            children = {
                                -- 有排名时显示纯数字（不带#），无排名时显示短横
                                UI.Label {
                                    text = hasPos and posNum or "—",
                                    fontSize = posFontSize,
                                    color = uclInfo.color, fontWeight = "bold",
                                },
                            }
                        },
                        UI.Panel {
                            marginLeft = 8, flexShrink = 1,
                            children = {
                                UI.Label { text = uclInfo.name, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                UI.Label {
                                    text = uclInfo.phase,
                                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                                },
                            }
                        },
                    }
                },
                -- 状态标签：显示完整排名信息或阶段
                UI.Panel {
                    marginTop = 8,
                    paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    backgroundColor = {uclInfo.color[1], uclInfo.color[2], uclInfo.color[3], 12},
                    borderRadius = 6, alignSelf = "flex-start",
                    children = {
                        UI.Label {
                            text = hasPos and ("排名 " .. uclInfo.posText) or uclInfo.phase,
                            fontSize = 9, color = uclInfo.color,
                        },
                    }
                },
            }
        }
    else
        -- 无欧冠时：占位卡片
        cupHalf = UI.Panel {
            flexGrow = 1, flexBasis = "48%",
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 12,
            padding = 12, marginLeft = 4,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无杯赛", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
            }
        }
    end

    local leagueStrip = UI.Panel {
        width = "100%", flexDirection = "row", marginBottom = 8,
        children = { leagueHalf, cupHalf }
    }

    -- ═══════════════════════════════════════════════
    -- [2] 财务 + 阵容 = 全宽双列卡片（重构内容）
    -- ═══════════════════════════════════════════════
    local injuryColor = injuredCount > 0 and Theme.COLORS.DANGER or Theme.COLORS.FINANCE_GREEN
    local injuryText = injuredCount > 0 and (injuredCount .. " 伤病") or "全员健康"

    -- 转会费使用百分比：已花费 / (已花费 + 剩余预算)
    local transferBudget = team.transferBudget or 0
    local transferSpent = 0
    for _, tx in ipairs(team.transactions or {}) do
        if tx.category == "transfer" and (tx.amount or 0) < 0 then
            transferSpent = transferSpent + math.abs(tx.amount)
        end
    end
    local transferTotal = transferSpent + transferBudget  -- 初始总额 ≈ 已花 + 剩余
    local transferPct = transferTotal > 0
        and math.min(100, math.floor(transferSpent / transferTotal * 100)) or 0
    local transferColor = transferPct <= 60 and Theme.COLORS.FINANCE_GREEN
        or (transferPct <= 85 and Theme.COLORS.MATCH_ORANGE or Theme.COLORS.DANGER)

    -- 可用球员数（非伤病）
    local availableCount = #team.playerIds - injuredCount

    -- 财务卡：核心 = 转会预算环形图 + 资产/净收入
    local financeCard = UI.Panel {
        flexGrow = 1, flexBasis = "48%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 12,
        padding = 12,
        marginRight = 4, marginBottom = 8,
        onClick = function() Router.navigate("finance") end,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Panel {
                        width = 4, height = 12, borderRadius = 2,
                        backgroundColor = Theme.COLORS.FINANCE_GREEN, marginRight = 6,
                    },
                    UI.Label { text = "财务", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                }
            },
            -- 中心：大环形图（转会费使用率）
            UI.Panel {
                width = "100%", alignItems = "center", justifyContent = "center",
                marginTop = 4, marginBottom = 8,
                children = {
                    Theme.RingGauge {
                        value = transferPct,
                        size = 56, thickness = 4,
                        color = transferColor,
                        label = transferPct .. "%",
                        labelSize = 12,
                        sublabel = "已用",
                    },
                }
            },
            -- 底部双指标
            UI.Panel {
                width = "100%", flexDirection = "row",
                children = {
                    -- 资产
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Label { text = balanceText, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            UI.Label { text = "资产", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                    -- 分隔线
                    UI.Panel { width = 1, height = 24, backgroundColor = Theme.COLORS.BORDER, alignSelf = "center" },
                    -- 赛季净收入
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Label { text = netText, fontSize = 13, color = netColor, fontWeight = "bold" },
                            UI.Label { text = "赛季净收入", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                }
            },
        }
    }

    -- 阵容卡：核心 = 环形可用率（大） + 人数/伤病
    local squadCard = UI.Panel {
        flexGrow = 1, flexBasis = "48%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 12,
        padding = 12,
        marginLeft = 4, marginBottom = 8,
        onClick = function() Router.navigate("squad") end,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row", alignItems = "center", marginBottom = 6,
                children = {
                    UI.Panel {
                        width = 4, height = 12, borderRadius = 2,
                        backgroundColor = Theme.COLORS.INFO_BLUE, marginRight = 6,
                    },
                    UI.Label { text = "阵容", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    UI.Panel { flexGrow = 1 },
                    -- 伤病状态小标签
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
                        backgroundColor = {injuryColor[1], injuryColor[2], injuryColor[3], 15},
                        borderRadius = 4,
                        children = {
                            UI.Panel {
                                width = 5, height = 5, borderRadius = 3,
                                backgroundColor = injuryColor, marginRight = 4,
                            },
                            UI.Label { text = injuryText, fontSize = 9, color = injuryColor },
                        }
                    },
                }
            },
            -- 中心：大环形图（薪资使用率）
            UI.Panel {
                width = "100%", alignItems = "center", justifyContent = "center",
                marginTop = 4, marginBottom = 8,
                children = {
                    Theme.RingGauge {
                        value = wagePct,
                        size = 56, thickness = 4,
                        color = wageColor,
                        label = wagePct .. "%",
                        labelSize = 13,
                        sublabel = "薪资",
                    },
                }
            },
            -- 底部双指标
            UI.Panel {
                width = "100%", flexDirection = "row",
                children = {
                    -- 总人数
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Label { text = tostring(#team.playerIds), fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            UI.Label { text = "球员", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                    -- 分隔线
                    UI.Panel { width = 1, height = 24, backgroundColor = Theme.COLORS.BORDER, alignSelf = "center" },
                    -- 可用人数
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Label {
                                text = availableCount .. "/" .. #team.playerIds,
                                fontSize = 13, color = injuryColor, fontWeight = "bold",
                            },
                            UI.Label { text = "可用", fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                }
            },
        }
    }

    -- ═══════════════════════════════════════════════
    -- [4] 赛季目标 - 全宽里程碑横条
    -- ═══════════════════════════════════════════════
    local objectiveCard = (function()
        local summary = ObjectivesManager.getSummary(gameState)
        local objColor = summary.progressPct >= 60 and Theme.COLORS.FINANCE_GREEN
                      or summary.progressPct >= 30 and Theme.COLORS.MATCH_ORANGE
                      or Theme.COLORS.DANGER

        if summary.hasObjectives then
            -- 有目标：横向里程碑进度
            local milestones = {}
            local totalCount = math.max(1, summary.totalCount)
            for i = 1, totalCount do
                local done = i <= summary.completedCount
                local dotColor = done and objColor or {255, 255, 255, 40}
                table.insert(milestones, UI.Panel {
                    alignItems = "center",
                    marginRight = i < totalCount and 0 or 0,
                    flexGrow = 1,
                    children = {
                        UI.Panel {
                            width = done and 10 or 8,
                            height = done and 10 or 8,
                            borderRadius = done and 5 or 4,
                            backgroundColor = dotColor,
                        },
                    }
                })
                -- 连接线（除最后一个）
                if i < totalCount then
                    local lineColor = i < summary.completedCount and objColor or {255, 255, 255, 20}
                    table.insert(milestones, UI.Panel {
                        flexGrow = 2, height = 2, borderRadius = 1,
                        backgroundColor = lineColor,
                        alignSelf = "center",
                    })
                end
            end

            return UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12,
                paddingLeft = 14, paddingRight = 14, paddingTop = 10, paddingBottom = 10,
                marginBottom = 8,
                flexDirection = "row", alignItems = "center",
                onClick = function() Dashboard._showObjectivesDetail(gameState) end,
                children = {
                    -- 左侧标签
                    UI.Panel {
                        marginRight = 12,
                        children = {
                            UI.Label { text = "赛季目标", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = summary.completedCount .. "/" .. summary.totalCount,
                                fontSize = 14, color = objColor, fontWeight = "bold", marginTop = 2,
                            },
                        }
                    },
                    -- 里程碑进度条
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        flexDirection = "row", alignItems = "center",
                        children = milestones,
                    },
                    -- 右侧文字
                    UI.Panel {
                        marginLeft = 12, alignItems = "flex-end",
                        children = {
                            UI.Label {
                                text = summary.seasonText or "",
                                fontSize = 10, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            },
                            summary.monthlyText and UI.Label {
                                text = summary.monthlyText,
                                fontSize = 9, color = Theme.COLORS.TEXT_MUTED, marginTop = 1,
                            } or UI.Panel { height = 0 },
                        }
                    },
                }
            }
        else
            -- 无目标：引导设定
            return UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12,
                paddingLeft = 14, paddingRight = 14, paddingTop = 12, paddingBottom = 12,
                marginBottom = 8,
                flexDirection = "row", alignItems = "center",
                onClick = function() Dashboard._showObjectivesDetail(gameState) end,
                children = {
                    UI.Panel {
                        width = 32, height = 32, borderRadius = 16,
                        backgroundColor = {Theme.COLORS.WARNING[1], Theme.COLORS.WARNING[2], Theme.COLORS.WARNING[3], 20},
                        alignItems = "center", justifyContent = "center",
                        marginRight = 12,
                        children = {
                            UI.Label { text = "!", fontSize = 16, color = Theme.COLORS.WARNING, fontWeight = "bold" },
                        }
                    },
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Label { text = "赛季目标未设定", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                            UI.Label { text = "设定目标以获得董事会支持", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                        }
                    },
                    UI.Label { text = "设定 >", fontSize = 11, color = Theme.COLORS.INFO_BLUE, fontWeight = "bold" },
                }
            }
        end
    end)()

    return UI.Panel {
        width = "100%",
        marginBottom = 12,
        children = {
            Theme.SectionHeader { text = "俱乐部状态", color = Theme.COLORS.INFO_BLUE },

            -- [1] 联赛 - 全宽横向记分牌
            leagueStrip,

            -- [2+3] 财务 + 阵容 - 异构双栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    financeCard,
                    squadCard,
                }
            },

            -- [4] 赛季目标 - 全宽里程碑
            objectiveCard,
        }
    }
end

------------------------------------------------------
-- [动态流] 近期消息 + 快捷入口
------------------------------------------------------
function Dashboard._buildActivityFeed(gameState)
    local unreadCount = gameState:getUnreadCount()

    -- 最近3条未读消息
    local recentMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read then
            table.insert(recentMsgs, msg)
            if #recentMsgs >= 3 then break end
        end
    end

    local msgRows = {}
    if #recentMsgs > 0 then
        -- 消息分类颜色
        local CAT_COLORS = {
            match_result = Theme.COLORS.INFO_BLUE,
            injury = Theme.COLORS.DANGER,
            transfer = Theme.COLORS.MATCH_ORANGE,
            contract = Theme.COLORS.WARNING,
            finance = Theme.COLORS.FINANCE_GREEN,
        }

        for _, msg in ipairs(recentMsgs) do
            local dotColor = CAT_COLORS[msg.category] or Theme.COLORS.TEXT_MUTED
            if msg.priority == "high" then dotColor = Theme.COLORS.DANGER end

            table.insert(msgRows, UI.Panel {
                width = "100%", height = 38,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Panel { width = 5, height = 5, borderRadius = 3, backgroundColor = dotColor, marginRight = 8 },
                    UI.Label {
                        text = msg.title or "消息",
                        fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1, flexShrink = 1,
                    },
                    msg.date and UI.Label {
                        text = string.format("%d/%d", msg.date.month, msg.date.day),
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    } or UI.Panel { width = 0 },
                },
                onClick = function()
                    Router.navigate("inbox")
                end,
            })
        end
    else
        table.insert(msgRows, UI.Label {
            text = "没有新消息",
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            marginTop = 4, marginBottom = 4,
        })
    end

    return Theme.Card {
        children = {
            -- 标题行
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8,
                children = {
                    Theme.SectionHeader {
                        text = "动态",
                        color = Theme.COLORS.TEXT_PRIMARY,
                        showBar = true,
                        rightChild = UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            children = {
                                unreadCount > 0 and UI.Panel {
                                    paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                                    borderRadius = 8, backgroundColor = Theme.COLORS.DANGER, marginRight = 8,
                                    children = {
                                        UI.Label { text = tostring(unreadCount), fontSize = 10, color = Theme.COLORS.TEXT_PRIMARY },
                                    }
                                } or UI.Panel { width = 0 },
                                UI.Button {
                                    text = "全部 >",
                                    width = 52, height = 26,
                                    backgroundColor = Theme.COLORS.TRANSPARENT,
                                    fontSize = 11, color = Theme.COLORS.INFO_BLUE,
                                    onClick = function() Router.navigate("inbox") end,
                                },
                            }
                        },
                    },
                }
            },

            -- 消息列表
            UI.Panel { width = "100%", children = msgRows },

            -- 快捷入口
            UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 10,
                children = {
                    UI.Button {
                        text = "查看全部新闻",
                        flexGrow = 1, height = 32,
                        backgroundColor = Theme.COLORS.BG_SURFACE,
                        borderRadius = 6, fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.navigate("news") end,
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- 工具函数
------------------------------------------------------
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

-- 获取上座率百分比（有数据用实际，无数据计算预期）
function Dashboard._getAttendancePct(team, gameState)
    -- 优先用最近比赛的实际数据
    local lastRevenue = team._lastMatchRevenue
    if lastRevenue and lastRevenue.attendanceRate then
        return math.floor(lastRevenue.attendanceRate * 100)
    end
    -- 无实际数据：基于声望和策略计算预期
    local rep = team.reputation or 50
    local strategy = FinanceManager.getTicketStrategy(team)
    local baseRate = 0.65 + rep / 500
    local strategyBonus = strategy.attendanceBonus or 0
    local expectedRate = math.min(0.95, math.max(0.50, baseRate + strategyBonus))
    return math.floor(expectedRate * 100)
end

-- 获取欧冠/世界杯赛事摘要信息
function Dashboard._getUCLInfo(gameState)
    local phaseNames = {
        not_started = "未开始", league = "联赛阶段", playoff = "附加赛",
        group = "小组赛", r16 = "1/8决赛", qf = "1/4决赛",
        sf = "半决赛", final = "决赛", completed = "已结束",
    }
    -- 优先欧冠
    if gameState.championsLeague then
        local ucl = gameState.championsLeague
        local playerIn = false
        if ucl.qualifiedTeams then
            for _, tid in ipairs(ucl.qualifiedTeams) do
                if tid == gameState.playerTeamId then playerIn = true; break end
            end
        end
        if not playerIn then return nil end
        local posText = ""
        if ucl.phase == "league" and ucl.getLeaguePhasePosition then
            local pos = ucl:getLeaguePhasePosition(gameState.playerTeamId)
            if pos > 0 then posText = "#" .. pos end
        end
        return {
            name = "欧冠",
            phase = phaseNames[ucl.phase] or ucl.phase,
            posText = posText,
            color = Theme.COLORS.INFO_BLUE,
        }
    end
    -- 其次世界杯
    if gameState.worldCup then
        local wc = gameState.worldCup
        return {
            name = "世界杯",
            phase = phaseNames[wc.phase] or wc.phase,
            posText = "",
            color = {255, 200, 50, 255},
        }
    end
    return nil
end

-- 获取近期比赛得分（3分/1分/0分）
function Dashboard._getRecentForm(gameState)
    local league = gameState.league
    if not league then return {} end
    local results = {}
    -- 从联赛赛程中获取已完赛的玩家比赛
    if league.fixtures then
        for _, f in ipairs(league.fixtures) do
            if f.status == "finished" then
                if f.homeTeamId == gameState.playerTeamId then
                    if f.homeGoals > f.awayGoals then table.insert(results, 3)
                    elseif f.homeGoals == f.awayGoals then table.insert(results, 1)
                    else table.insert(results, 0) end
                elseif f.awayTeamId == gameState.playerTeamId then
                    if f.awayGoals > f.homeGoals then table.insert(results, 3)
                    elseif f.awayGoals == f.homeGoals then table.insert(results, 1)
                    else table.insert(results, 0) end
                end
            end
        end
    end
    -- 取最近5场
    local n = #results
    if n <= 5 then return results end
    local recent = {}
    for i = n - 4, n do
        table.insert(recent, results[i])
    end
    return recent
end

------------------------------------------------------
-- 赛季目标详情 BottomSheet
------------------------------------------------------
function Dashboard._showObjectivesDetail(gameState)
    local summary = ObjectivesManager.getSummary(gameState)

    -- 未设定目标 → 弹出选择界面
    if not summary.hasObjectives then
        Dashboard._showObjectiveSelection(gameState)
        return
    end

    -- 已有目标 → 展示详情
    local children = {}

    -- 赛季目标列表
    table.insert(children, UI.Label {
        text = "赛季目标",
        fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
        marginBottom = 8,
    })

    local seasonObjs = summary.allSeasonObjectives or {}
    for _, obj in ipairs(seasonObjs) do
        local statusIcon = obj.status == "completed" and "✓ " or obj.status == "failed" and "✗ " or "• "
        local statusColor = obj.status == "completed" and Theme.COLORS.FINANCE_GREEN
                         or obj.status == "failed" and Theme.COLORS.DANGER
                         or Theme.COLORS.TEXT_PRIMARY
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            marginBottom = 6, paddingLeft = 4,
            children = {
                UI.Label { text = statusIcon .. obj.text, fontSize = 13, color = statusColor },
            }
        })
    end

    -- 月度目标
    local monthly = gameState.objectives and gameState.objectives.monthly
    if monthly then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 10, marginBottom = 10 })
        table.insert(children, UI.Label {
            text = "本月目标",
            fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
            marginBottom = 6,
        })
        local mColor = monthly.status == "completed" and Theme.COLORS.FINANCE_GREEN
                    or monthly.status == "failed" and Theme.COLORS.DANGER
                    or Theme.COLORS.INFO_BLUE
        local mIcon = monthly.status == "completed" and "✓ " or monthly.status == "failed" and "✗ " or "→ "
        table.insert(children, UI.Label {
            text = mIcon .. monthly.text,
            fontSize = 13, color = mColor, paddingLeft = 4,
        })
    end

    -- 进度条
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 12, marginBottom = 10 })
    local pct = summary.progressPct
    local pctColor = pct >= 60 and Theme.COLORS.FINANCE_GREEN
                  or pct >= 30 and Theme.COLORS.MATCH_ORANGE
                  or Theme.COLORS.DANGER
    table.insert(children, UI.Panel {
        width = "100%",
        children = {
            UI.Label {
                text = "总进度: " .. summary.completedCount .. "/" .. summary.totalCount .. " 完成 (" .. pct .. "%)",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4,
            },
            Theme.ProgressBar { value = pct, color = pctColor, height = 6 },
        }
    })

    BottomSheet.showCustom({
        title = "赛季目标",
        showCancel = true,
        children = children,
    })
end

------------------------------------------------------
-- 赛季目标选择界面
------------------------------------------------------
function Dashboard._showObjectiveSelection(gameState, initSelected)
    local proposals = ObjectivesManager.generateProposals(gameState)

    -- 跟踪选中状态
    local selected = initSelected or { league = nil, ucl = nil, finance = nil }

    if not initSelected then
        for _, opt in ipairs(proposals.league) do
            if opt.recommended then selected.league = opt.id; break end
        end
        for _, opt in ipairs(proposals.ucl) do
            if opt.recommended then selected.ucl = opt.id; break end
        end
        for _, opt in ipairs(proposals.finance) do
            if opt.recommended then selected.finance = opt.id; break end
        end
    end

    -- 存储按钮引用，用于原地更新
    local leagueButtons = {}   -- { {btn=widget, id=optId, text=baseText}, ... }
    local uclButtons = {}
    local financeButtons = {}
    local hintContainer = nil  -- 预算提示容器
    local hintLabel = nil      -- 预算提示文本

    -- 计算预算提示内容（联赛+欧冠两项累计）
    local function calcBudgetHint()
        local team = gameState:getPlayerTeam()
        if not team then return nil end
        local tierOrder = { elite = 4, strong = 3, mid = 2, weak = 1 }
        local teamTier = ObjectivesManager._getTier(gameState)
        local teamW = tierOrder[teamTier] or 2

        -- 累计各类目标的档次偏移
        local totalDiff = 0
        local count = 0

        -- 联赛
        if selected.league then
            for _, obj in ipairs(proposals.league) do
                if obj.id == selected.league then
                    totalDiff = totalDiff + ((tierOrder[obj.tier] or teamW) - teamW)
                    count = count + 1
                    break
                end
            end
        end

        -- 欧冠
        if selected.ucl and proposals.inUCL then
            for _, obj in ipairs(proposals.ucl) do
                if obj.id == selected.ucl then
                    totalDiff = totalDiff + ((tierOrder[obj.tier] or teamW) - teamW)
                    count = count + 1
                    break
                end
            end
        end

        if totalDiff == 0 or count == 0 then return nil end

        -- 根据累计偏移计算预算影响百分比
        if totalDiff < 0 then
            local cutPct
            if totalDiff == -1 then cutPct = 15
            elseif totalDiff == -2 then cutPct = 30
            elseif totalDiff == -3 then cutPct = 45
            else cutPct = 60 end
            return { text = string.format("⚠️ 降低目标：董事会将削减 %d%% 预算", cutPct), color = Theme.COLORS.WARNING }
        else
            local boostPct
            if totalDiff == 1 then boostPct = 8
            elseif totalDiff == 2 then boostPct = 15
            else boostPct = 20 end
            return { text = string.format("📈 挑战更高目标：董事会将追加 %d%% 预算", boostPct), color = Theme.COLORS.SECONDARY }
        end
    end

    -- 刷新所有按钮外观（原地更新，无需重建）
    local function refreshButtons()
        local selColor = Theme.COLORS.INFO_BLUE
        local normalColor = Theme.COLORS.TEXT_SECONDARY
        local selBg = {30, 60, 90, 255}
        local normalBg = Theme.COLORS.BG_SURFACE

        for _, item in ipairs(leagueButtons) do
            local isSel = (selected.league == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end
        for _, item in ipairs(uclButtons) do
            local isSel = (selected.ucl == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end
        for _, item in ipairs(financeButtons) do
            local isSel = (selected.finance == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end

        -- 更新预算提示
        local hint = calcBudgetHint()
        if hint and hintContainer and hintLabel then
            hintLabel:SetText(hint.text)
            hintLabel:SetStyle({ color = hint.color })
            hintContainer:SetStyle({
                backgroundColor = {hint.color[1], hint.color[2], hint.color[3], 25},
                height = 32,
                overflow = "visible",
            })
        elseif not hint and hintContainer then
            hintContainer:SetStyle({ height = 0, overflow = "hidden" })
        end
    end

    -- 构建内容
    local children = {}

    table.insert(children, UI.Label {
        text = "董事会希望你确定本赛季目标，请从以下选项中选择：",
        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 12,
    })

    -- 联赛目标
    table.insert(children, UI.Label {
        text = "联赛目标", fontSize = 13, fontWeight = "bold",
        color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
    })
    for _, opt in ipairs(proposals.league) do
        local isSelected = (selected.league == opt.id)
        local optId = opt.id
        local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
        local btn = UI.Button {
            text = (isSelected and "● " or "○ ") .. baseText,
            width = "100%", height = 36, marginBottom = 4,
            backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
            borderRadius = 6, fontSize = 12,
            color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
            textAlign = "left", paddingLeft = 12,
            onClick = function()
                selected.league = optId
                refreshButtons()
            end,
        }
        table.insert(leagueButtons, { btn = btn, id = optId, text = baseText })
        table.insert(children, btn)
    end

    -- 欧冠目标
    if proposals.inUCL and #proposals.ucl > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 8, marginBottom = 8 })
        table.insert(children, UI.Label {
            text = "欧冠目标", fontSize = 13, fontWeight = "bold",
            color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
        })
        for _, opt in ipairs(proposals.ucl) do
            local isSelected = (selected.ucl == opt.id)
            local optId = opt.id
            local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
            local btn = UI.Button {
                text = (isSelected and "● " or "○ ") .. baseText,
                width = "100%", height = 36, marginBottom = 4,
                backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
                borderRadius = 6, fontSize = 12,
                color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
                textAlign = "left", paddingLeft = 12,
                onClick = function()
                    selected.ucl = optId
                    refreshButtons()
                end,
            }
            table.insert(uclButtons, { btn = btn, id = optId, text = baseText })
            table.insert(children, btn)
        end
    end

    -- 财务目标
    if #proposals.finance > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 8, marginBottom = 8 })
        table.insert(children, UI.Label {
            text = "财务目标", fontSize = 13, fontWeight = "bold",
            color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
        })
        for _, opt in ipairs(proposals.finance) do
            local isSelected = (selected.finance == opt.id)
            local optId = opt.id
            local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
            local btn = UI.Button {
                text = (isSelected and "● " or "○ ") .. baseText,
                width = "100%", height = 36, marginBottom = 4,
                backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
                borderRadius = 6, fontSize = 12,
                color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
                textAlign = "left", paddingLeft = 12,
                onClick = function()
                    selected.finance = optId
                    refreshButtons()
                end,
            }
            table.insert(financeButtons, { btn = btn, id = optId, text = baseText })
            table.insert(children, btn)
        end
    end

    -- 预算影响提示（始终存在，初始根据状态显示/隐藏）
    local initHint = calcBudgetHint()
    hintLabel = UI.Label {
        text = initHint and initHint.text or "",
        fontSize = 11,
        color = initHint and initHint.color or Theme.COLORS.TEXT_MUTED,
    }
    hintContainer = UI.Panel {
        width = "100%", marginTop = 10, marginBottom = 4,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 10, paddingRight = 10, paddingTop = 6, paddingBottom = 6,
        backgroundColor = initHint and {initHint.color[1], initHint.color[2], initHint.color[3], 25} or {0,0,0,0},
        borderRadius = 6,
        height = initHint and 32 or 0,
        overflow = initHint and "visible" or "hidden",
        children = { hintLabel },
    }
    table.insert(children, hintContainer)

    -- 确认按钮
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 12, marginBottom = 12 })
    table.insert(children, UI.Button {
        text = "确认目标",
        width = "100%", height = 44,
        backgroundColor = Theme.COLORS.PRIMARY,
        borderRadius = 8, fontSize = 14, fontWeight = "bold",
        color = {255, 255, 255, 255},
        onClick = function()
            local ids = {}
            if selected.league then table.insert(ids, selected.league) end
            if selected.ucl then table.insert(ids, selected.ucl) end
            if selected.finance then table.insert(ids, selected.finance) end
            ObjectivesManager.confirmObjectives(gameState, ids)
            BottomSheet.close()
            Router.replaceWith("dashboard")
        end,
    })

    BottomSheet.showCustom({
        title = "设定赛季目标",
        showCancel = true,
        height = 560,
        children = children,
    })
end

return Dashboard
