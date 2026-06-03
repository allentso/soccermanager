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
local TeamIcon = require("scripts/ui/components/team_icon")
local WorldCup = require("scripts/systems/world_cup")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

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

    -- 判断当前身份
    local isNTMode = gameState.currentRole == "national_team" and gameState.nationalTeamCoach ~= nil
    -- 如果国家队已不存在（世界杯结束），自动切回俱乐部
    if isNTMode and not gameState.worldCup then
        gameState.currentRole = "club"
        isNTMode = false
    end

    -- 滚动内容（根据身份切换）
    local scrollChildren
    if isNTMode then
        scrollChildren = {
            Dashboard._buildNTMatchHero(gameState),
            Dashboard._buildNTSnapshot(gameState),
            Dashboard._buildNTActivityFeed(gameState),
            UI.Panel { height = 12 },
        }
    else
        scrollChildren = {
            Dashboard._buildMatchHero(gameState, team),
            Dashboard._buildUrgentSection(gameState, team),
            Dashboard._buildClubSnapshot(gameState, team),
            Dashboard._buildActivityFeed(gameState),
            UI.Panel { height = 12 },
        }
    end

    -- 构建页面
    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部状态栏：日期 + 推进按钮
            Dashboard._buildTopBar(gameState, team, isBlocked, hasAnyBlockers, blockers, daysToMatch, doAdvanceDay, doSkipToMatchDay),

            -- 滚动内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 12,
                children = scrollChildren,
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }

    -- 如果从阻断器跳转过来，自动触发对应操作
    if params and params.action == "set_objectives" then
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            Dashboard._showObjectivesDetail(gameState)
        end)
    end

    return page
end

------------------------------------------------------
-- 潜力修改器弹窗（看5次广告解锁精确潜力值）
------------------------------------------------------
function Dashboard._showPotentialModifierDialog(gameState)
    local progress = gameState.potentialRevealProgress or 0
    local total = 5
    local revealed = gameState.potentialRevealed or false

    -- 已解锁：显示状态
    if revealed then
        UI.ShowOverlay(UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            backgroundColor = {0, 0, 0, 160},
            onClick = function() UI.CloseOverlay() end,
            children = {
                UI.Panel {
                    width = 280,
                    backgroundColor = Theme.COLORS.BG_CARD,
                    borderRadius = 12,
                    padding = 20,
                    alignItems = "center",
                    onClick = function() end,
                    children = {
                        UI.Label { text = "🔓 潜力透视已激活", fontSize = 16, color = Theme.COLORS.ACCENT, fontWeight = "bold", marginBottom = 10 },
                        UI.Label { text = "球员潜力值已精确显示", fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY, marginBottom = 16 },
                        UI.Button {
                            text = "确定",
                            width = "100%", height = 36,
                            backgroundColor = Theme.COLORS.ACCENT, borderRadius = 8,
                            fontSize = 14, color = {255, 255, 255, 255},
                            onClick = function() UI.CloseOverlay() end,
                        },
                    },
                },
            },
        })
        return
    end

    -- 构建进度点
    local dots = {}
    for i = 1, total do
        table.insert(dots, UI.Panel {
            width = 20, height = 20,
            borderRadius = 10,
            backgroundColor = i <= progress and Theme.COLORS.ACCENT or {60, 70, 100, 255},
            marginRight = i < total and 6 or 0,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = i <= progress and "✓" or tostring(i),
                    fontSize = 10,
                    color = i <= progress and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                },
            },
        })
    end

    local remaining = total - progress

    UI.ShowOverlay(UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = {0, 0, 0, 160},
        onClick = function() UI.CloseOverlay() end,
        children = {
            UI.Panel {
                width = 280,
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12,
                padding = 20,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label { text = "🔮 潜力透视", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", marginBottom = 6 },
                    UI.Label { text = "观看广告解锁精确潜力值显示，\n替代模糊的星级评估", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, textAlign = "center", marginBottom = 14 },
                    UI.Panel { flexDirection = "row", alignItems = "center", marginBottom = 10, children = dots },
                    UI.Label { text = string.format("已观看 %d/%d 次", progress, total), fontSize = 13, color = Theme.COLORS.ACCENT, fontWeight = "bold", marginBottom = 16 },
                    UI.Button {
                        text = remaining <= 1 and "观看最后一次并解锁" or string.format("观看广告（还需%d次）", remaining),
                        width = "100%", height = 40,
                        backgroundColor = Theme.COLORS.ACCENT, borderRadius = 8,
                        fontSize = 14, color = {255, 255, 255, 255}, fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                            sdk:ShowRewardVideoAd(function(result)
                                if result.success then
                                    local newProgress = (gameState.potentialRevealProgress or 0) + 1
                                    gameState.potentialRevealProgress = newProgress
                                    if newProgress >= total then
                                        gameState.potentialRevealed = true
                                        UI.Toast.Show({ message = "潜力透视已解锁！现在可查看精确潜力值", variant = "success" })
                                    else
                                        UI.Toast.Show({ message = string.format("观看进度 %d/%d", newProgress, total), variant = "info" })
                                    end
                                    Router.replaceWith("dashboard")
                                else
                                    UI.Toast.Show({ message = "需完整观看广告才能获得奖励", variant = "warning" })
                                end
                            end)
                        end,
                    },
                    UI.Button { text = "取消", width = "100%", height = 34, backgroundColor = {0, 0, 0, 0}, borderRadius = 8, fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginTop = 6, onClick = function() UI.CloseOverlay() end },
                },
            },
        },
    })
end

------------------------------------------------------
-- 顶部操作栏
------------------------------------------------------
function Dashboard._buildTopBar(gameState, team, isBlocked, hasAnyBlockers, blockers, daysToMatch, doAdvanceDay, doSkipToMatchDay)
    -- 继续按钮颜色和文本
    local continueColor = isBlocked and Theme.COLORS.DANGER
        or (hasAnyBlockers and Theme.COLORS.WARNING or Theme.COLORS.FINANCE_GREEN)
    local continueText = isBlocked and "! 阻断"
        or (hasAnyBlockers and "! 继续" or "继续 >")

    local children = {
        -- 日期（点击弹出赛事日历）
        UI.Button {
            text = gameState:getDateString(),
            height = 30,
            backgroundColor = Theme.COLORS.TRANSPARENT,
            fontSize = 13,
            color = Theme.COLORS.TEXT_SECONDARY,
            paddingLeft = 0, paddingRight = 4,
            onClick = function()
                Dashboard._showFixtureCalendar(gameState)
            end,
        },
        -- 球队/国家队图标（点击查看经理档案）
        UI.Panel {
            width = 26, height = 26,
            marginLeft = 6, marginRight = 2,
            onClick = function()
                Router.navigate("manager_view")
            end,
            children = {
                TeamIcon.create { team = team, size = 26 },
            },
        },
        -- 身份切换按钮（仅在有国家队身份时显示）
        Dashboard._buildRoleSwitcher(gameState),
        UI.Panel { flexGrow = 1 },
        -- 潜力透视按钮
        UI.Button {
            text = gameState.potentialRevealed and "🔓" or "🔮",
            width = 30,
            height = 30,
            backgroundColor = gameState.potentialRevealed and {30, 60, 50, 255} or Theme.COLORS.TRANSPARENT,
            borderRadius = 15,
            fontSize = 16,
            color = gameState.potentialRevealed and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
            marginRight = 4,
            onClick = function()
                Dashboard._showPotentialModifierDialog(gameState)
            end,
        },
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
-- [赛事日历弹窗] 横向时间线
------------------------------------------------------
function Dashboard._showFixtureCalendar(gameState)
    local League = require("scripts/domain/league")
    local playerTeamId = gameState.playerTeamId

    -- 收集未来60天内玩家球队的所有比赛
    local upcomingFixtures = {}
    for daysAhead = 0, 60 do
        local futureDate = League._addDays(gameState.date, daysAhead)

        -- 联赛比赛
        for _, lg in pairs(gameState.leagues or {}) do
            for _, f in ipairs(lg.fixtures) do
                if f.status == "scheduled" and
                   f.date.year == futureDate.year and
                   f.date.month == futureDate.month and
                   f.date.day == futureDate.day then
                    if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                        table.insert(upcomingFixtures, {
                            fixture = f,
                            date = futureDate,
                            daysAhead = daysAhead,
                            competition = lg.name or "联赛",
                            competitionShort = Dashboard._getLeagueShort(lg.name),
                        })
                    end
                end
            end
        end

        -- 欧冠比赛
        if gameState.championsLeague then
            local uclFixtures = gameState.championsLeague:getFixturesForDate(futureDate)
            for _, f in ipairs(uclFixtures) do
                if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                    table.insert(upcomingFixtures, {
                        fixture = f,
                        date = futureDate,
                        daysAhead = daysAhead,
                        competition = "欧冠",
                        competitionShort = "UCL",
                    })
                end
            end
        end

        -- 世界杯比赛（国家队层面，可能不适用但保留）
        if gameState.worldCup and gameState.worldCup.phase ~= "not_started" and gameState.worldCup.phase ~= "completed" then
            local wcFixtures = gameState.worldCup:getFixturesForDate(futureDate)
            for _, f in ipairs(wcFixtures) do
                if WorldCup.isPlayerNationMatch(gameState, f) then
                    table.insert(upcomingFixtures, {
                        fixture = f,
                        date = futureDate,
                        daysAhead = daysAhead,
                        competition = "世界杯",
                        competitionShort = "WC",
                    })
                end
            end
        end
    end

    -- 构建横向日历卡片
    local fixtureCards = {}
    for i, entry in ipairs(upcomingFixtures) do
        local f = entry.fixture
        local opponentId = (f.homeTeamId == playerTeamId) and f.awayTeamId or f.homeTeamId
        local opponent = gameState.teams[opponentId]
        local isHome = f.homeTeamId == playerTeamId
        local dateStr = string.format("%d/%d", entry.date.month, entry.date.day)

        -- 赛事标签颜色
        local compColor = Theme.COLORS.ACCENT
        if entry.competitionShort == "UCL" then
            compColor = {30, 120, 220, 255}
        elseif entry.competitionShort == "WC" then
            compColor = {200, 160, 30, 255}
        end

        table.insert(fixtureCards, UI.Panel {
            width = 100, minWidth = 100,
            marginRight = 10,
            padding = 10,
            backgroundColor = (i == 1) and {40, 55, 80, 255} or Theme.COLORS.BG_CARD,
            borderRadius = 10,
            borderWidth = (i == 1) and 1 or 0,
            borderColor = Theme.COLORS.PRIMARY,
            alignItems = "center",
            children = {
                -- 赛事名称标签
                UI.Panel {
                    backgroundColor = {compColor[1], compColor[2], compColor[3], 40},
                    borderRadius = 4, paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                    marginBottom = 8,
                    children = {
                        UI.Label { text = entry.competition, fontSize = 10, color = compColor },
                    },
                },
                -- 对手图标
                TeamIcon.create { team = opponent, size = 40 },
                -- 主客场 + 日期
                UI.Label {
                    text = (isHome and "主场" or "客场") .. " · " .. dateStr,
                    fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 4,
                },
                -- 天数
                UI.Label {
                    text = entry.daysAhead == 0 and "今天" or (entry.daysAhead .. "天后"),
                    fontSize = 10, color = (entry.daysAhead <= 3) and Theme.COLORS.MATCH_ORANGE or Theme.COLORS.TEXT_MUTED,
                    marginTop = 2,
                },
            },
        })
    end

    if #fixtureCards == 0 then
        table.insert(fixtureCards, UI.Panel {
            width = "100%", height = 80,
            alignItems = "center", justifyContent = "center",
            children = { UI.Label { text = "暂无已排赛程", fontSize = 14, color = Theme.COLORS.TEXT_MUTED } },
        })
    end

    BottomSheet.showCustom({
        title = "赛程日历",
        height = 280,
        showCancel = true,
        children = {
            UI.ScrollView {
                width = "100%", height = 200,
                scrollX = true, scrollY = false,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                children = fixtureCards,
            },
        },
    })
end

-- 联赛名缩写
function Dashboard._getLeagueShort(name)
    if not name then return "LG" end
    if name:find("Premier") or name:find("英超") then return "PL" end
    if name:find("Liga") and not name:find("Ligue") then return "LL" end
    if name:find("Bundesliga") or name:find("德甲") then return "BL" end
    if name:find("Serie") or name:find("意甲") then return "SA" end
    if name:find("Ligue") or name:find("法甲") then return "L1" end
    return "LG"
end

------------------------------------------------------
-- [Hero区] 下一场比赛大卡
------------------------------------------------------
function Dashboard._buildMatchHero(gameState, team)
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

    -- 底部留白，避免被关闭按钮遮挡
    table.insert(children, UI.Panel { width = "100%", height = 60 })

    BottomSheet.showCustom({
        title = "设定赛季目标",
        showCancel = true,
        height = 620,
        children = children,
    })
end

------------------------------------------------------
-- [国家队模式] 身份切换按钮
------------------------------------------------------
function Dashboard._buildRoleSwitcher(gameState)
    -- 只有在拥有国家队身份且世界杯存在时才显示
    if not gameState.nationalTeamCoach or not gameState.worldCup then
        return UI.Panel { width = 0, height = 0 }
    end

    local isNT = gameState.currentRole == "national_team"
    local nationCode = gameState.nationalTeamCoach.nation
    local nationName = WorldCup._getNationName(nationCode)

    local label = isNT and ("🏴 " .. nationName) or "🏠 俱乐部"
    local bgColor = isNT and {25, 60, 90, 255} or {50, 50, 55, 255}

    return UI.Button {
        text = label,
        height = 26,
        backgroundColor = bgColor,
        borderRadius = 13,
        fontSize = 10,
        color = isNT and {130, 200, 255, 255} or Theme.COLORS.TEXT_SECONDARY,
        paddingLeft = 8, paddingRight = 8,
        marginLeft = 6,
        onClick = function()
            if gameState.currentRole == "national_team" then
                gameState.currentRole = "club"
            else
                gameState.currentRole = "national_team"
            end
            Router.replaceWith("dashboard")
        end,
    }
end

------------------------------------------------------
-- [国家队模式] 下一场世界杯比赛 Hero
------------------------------------------------------
function Dashboard._buildNTMatchHero(gameState)
    local wc = gameState.worldCup
    local ntCoach = gameState.nationalTeamCoach
    if not wc or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local playerNation = ntCoach.nation
    local nationName = WorldCup._getNationName(playerNation)

    -- 查找下一场国家队比赛
    local nextFixture = nil
    local League = require("scripts/domain/league")
    for daysAhead = 0, 60 do
        local futureDate = League._addDays(gameState.date, daysAhead)
        local wcFixtures = TurnProcessor.getWCFixturesForDate(gameState, futureDate)
        for _, f in ipairs(wcFixtures) do
            if f.homeTeamId == playerNation or f.awayTeamId == playerNation then
                if f.status == "scheduled" then
                    nextFixture = f
                    break
                end
            end
        end
        if nextFixture then break end
    end

    -- 世界杯阶段名
    local phaseNames = {
        group = "小组赛",
        r16 = "十六强",
        qf = "四分之一决赛",
        sf = "半决赛",
        final = "决赛",
        completed = "已结束",
    }
    local phaseName = phaseNames[wc.phase] or "世界杯"

    if not nextFixture then
        -- 可能已被淘汰或赛事结束
        local statusText = wc.phase == "completed" and "世界杯已结束" or "暂无比赛安排"
        if wc.champion then
            local champName = WorldCup._getNationName(wc.champion)
            statusText = "🏆 冠军: " .. champName
        end
        return UI.Panel {
            width = "100%",
            backgroundColor = {20, 35, 60, 255},
            borderRadius = 14,
            paddingTop = 16, paddingBottom = 16, paddingLeft = 16, paddingRight = 16,
            marginBottom = 12,
            children = {
                Theme.SectionHeader { text = "🏆 世界杯 · " .. phaseName, color = {255, 215, 0, 255} },
                UI.Label {
                    text = statusText,
                    fontSize = 14, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                },
            }
        }
    end

    -- 对手信息
    local opponentCode = nextFixture.homeTeamId == playerNation
        and nextFixture.awayTeamId or nextFixture.homeTeamId
    local opponentName = WorldCup._getNationName(opponentCode)
    local isHome = nextFixture.homeTeamId == playerNation

    -- 日期和倒计时
    local matchDateStr = string.format("%d月%d日", nextFixture.date.month, nextFixture.date.day)
    local daysTo = 0
    for d = 1, 60 do
        local fd = League._addDays(gameState.date, d)
        if fd.year == nextFixture.date.year and fd.month == nextFixture.date.month and fd.day == nextFixture.date.day then
            daysTo = d
            break
        end
    end
    local countdownText = daysTo <= 0 and "今天" or (daysTo == 1 and "明天" or (daysTo .. "天后"))

    -- 大名单状态
    local squadCount = ntCoach.squad and #ntCoach.squad or 0
    local squadStatus = squadCount > 0 and (squadCount .. "人") or "未选"
    local squadColor = squadCount >= 20 and Theme.COLORS.FINANCE_GREEN
        or (squadCount > 0 and Theme.COLORS.WARNING or Theme.COLORS.DANGER)

    return UI.Panel {
        width = "100%",
        backgroundColor = {15, 30, 55, 255},
        borderRadius = 14,
        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
        marginBottom = 12,
        overflow = "hidden",
        children = {
            -- 顶部：世界杯 + 阶段 + 倒计时
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
                marginBottom = 6,
                children = {
                    UI.Label { text = "🏆 世界杯 · " .. phaseName, fontSize = 13, color = {255, 215, 0, 255} },
                    UI.Panel {
                        backgroundColor = {255, 215, 0, 40},
                        borderRadius = 10,
                        paddingLeft = 8, paddingRight = 8, paddingTop = 2, paddingBottom = 2,
                        marginLeft = 8,
                        children = {
                            UI.Label { text = countdownText, fontSize = 10, color = {255, 215, 0, 255}, fontWeight = "bold" },
                        }
                    },
                }
            },

            -- 日期
            UI.Panel {
                width = "100%", alignItems = "center", marginBottom = 16,
                children = {
                    UI.Label { text = matchDateStr, fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                }
            },

            -- 对阵区：国旗emoji + 国名 + VS
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                marginBottom = 16,
                children = {
                    -- 我方国家
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 52, height = 52, borderRadius = 26,
                                backgroundColor = {40, 70, 120, 255},
                                justifyContent = "center", alignItems = "center",
                                children = {
                                    UI.Label { text = "🏴", fontSize = 28 },
                                }
                            },
                            UI.Label {
                                text = nationName,
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
                                fontSize = 18, color = {255, 215, 0, 255}, fontWeight = "bold",
                            },
                        }
                    },
                    -- 对手国家
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 52, height = 52, borderRadius = 26,
                                backgroundColor = {60, 50, 50, 255},
                                justifyContent = "center", alignItems = "center",
                                children = {
                                    UI.Label { text = "🏴", fontSize = 28 },
                                }
                            },
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
                    UI.Label { text = isHome and "主场" or "客场", fontSize = 11, color = {255, 215, 0, 200}, fontWeight = "bold" },
                }
            },

            -- 分隔线
            UI.Panel { width = "100%", height = 1, backgroundColor = {255, 255, 255, 15}, marginBottom = 12 },

            -- 底部状态：确认前显示大名单，确认后显示战术
            (ntCoach.squadConfirmed and UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "阵型: ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = (gameState:getPlayerTeam() and gameState:getPlayerTeam().formation) or "4-4-2",
                                fontSize = 13, color = {255, 215, 0, 255}, fontWeight = "bold",
                            },
                        }
                    },
                    UI.Button {
                        text = "战术 →",
                        height = 26,
                        backgroundColor = {255, 215, 0, 30},
                        borderRadius = 6,
                        fontSize = 11, fontWeight = "bold",
                        color = {255, 215, 0, 255},
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function()
                            Router.navigate("tactics")
                        end,
                    },
                }
            } or UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "大名单: ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = squadStatus, fontSize = 12, color = squadColor, fontWeight = "bold" },
                        }
                    },
                    UI.Button {
                        text = "选人 →",
                        height = 26,
                        backgroundColor = {255, 215, 0, 30},
                        borderRadius = 6,
                        fontSize = 11, fontWeight = "bold",
                        color = {255, 215, 0, 255},
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function()
                            Router.navigate("national_squad_select", { nation = ntCoach.nation })
                        end,
                    },
                }
            }),
        }
    }
end

------------------------------------------------------
-- [国家队模式] 状态概览（小组积分 + 球队信息）
------------------------------------------------------
function Dashboard._buildNTSnapshot(gameState)
    local wc = gameState.worldCup
    local ntCoach = gameState.nationalTeamCoach
    if not wc or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local playerNation = ntCoach.nation
    local nationName = WorldCup._getNationName(playerNation)

    -- 找到所在小组
    local myGroup = nil
    local myGroupName = ""
    for gName, group in pairs(wc.groups or {}) do
        for _, tid in ipairs(group.teamIds) do
            if tid == playerNation then
                myGroup = group
                myGroupName = gName
                break
            end
        end
        if myGroup then break end
    end

    -- 小组积分表
    local standingsRows = {}
    if myGroup and wc.phase == "group" then
        -- 排序积分榜
        local sorted = {}
        for tid, s in pairs(myGroup.standings) do
            table.insert(sorted, s)
        end
        table.sort(sorted, function(a, b)
            if a.points ~= b.points then return a.points > b.points end
            if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
            return a.goalsFor > b.goalsFor
        end)

        for rank, s in ipairs(sorted) do
            local name = WorldCup._getNationName(s.teamId)
            local isPlayer = s.teamId == playerNation
            local rowBg = isPlayer and {255, 215, 0, 20} or {0, 0, 0, 0}
            local nameColor = isPlayer and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY

            table.insert(standingsRows, UI.Panel {
                width = "100%", height = 30,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                backgroundColor = rowBg,
                borderRadius = 4,
                children = {
                    UI.Label { text = tostring(rank), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 18 },
                    UI.Label { text = name, fontSize = 12, color = nameColor, fontWeight = isPlayer and "bold" or "normal", flexGrow = 1 },
                    UI.Label { text = tostring(s.played), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
                    UI.Label { text = tostring(s.goalDifference), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "center" },
                    UI.Label { text = tostring(s.points), fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 22, textAlign = "center" },
                }
            })
        end
    end

    -- 淘汰赛阶段信息
    local knockoutInfo = nil
    if wc.phase ~= "group" and wc.phase ~= "not_started" and wc.phase ~= "completed" then
        knockoutInfo = "进入淘汰赛阶段"
    end

    local children = {}

    -- 小组表头
    if #standingsRows > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
            children = {
                UI.Label { text = "🏆", fontSize = 14, marginRight = 6 },
                UI.Label { text = myGroupName .. " 组积分榜", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
            }
        })
        -- 表头行
        table.insert(children, UI.Panel {
            width = "100%", height = 24,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            children = {
                UI.Label { text = "#", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 18 },
                UI.Label { text = "球队", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = "赛", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
                UI.Label { text = "净", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "center" },
                UI.Label { text = "分", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
            }
        })
        for _, row in ipairs(standingsRows) do
            table.insert(children, row)
        end
    elseif knockoutInfo then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
            children = {
                UI.Label { text = "⚔️", fontSize = 14, marginRight = 6 },
                UI.Label { text = knockoutInfo, fontSize = 13, color = {255, 215, 0, 255}, fontWeight = "bold" },
            }
        })
    end

    -- 快捷操作
    table.insert(children, UI.Panel {
        width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 10, marginBottom = 10,
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-around",
        children = {
            UI.Button {
                text = ntCoach.squadConfirmed and "⚙️ 战术" or "📋 大名单",
                height = 32,
                backgroundColor = ntCoach.squadConfirmed and {40, 50, 80, 255} or {40, 60, 90, 255},
                borderRadius = 6,
                fontSize = 11,
                color = ntCoach.squadConfirmed and {255, 215, 0, 255} or {130, 200, 255, 255},
                paddingLeft = 12, paddingRight = 12,
                onClick = function()
                    if ntCoach.squadConfirmed then
                        Router.navigate("tactics")
                    else
                        Router.navigate("national_squad_select", { nation = playerNation })
                    end
                end,
            },
            UI.Button {
                text = "📊 赛程",
                height = 32,
                backgroundColor = {40, 60, 90, 255},
                borderRadius = 6,
                fontSize = 11, color = {130, 200, 255, 255},
                paddingLeft = 12, paddingRight = 12,
                onClick = function()
                    Router.navigate("league", { tab = "WC" })
                end,
            },
        }
    })

    return Theme.Card {
        backgroundColor = {20, 30, 50, 255},
        borderColor = {40, 70, 120, 100},
        children = children,
    }
end

------------------------------------------------------
-- [国家队模式] 世界杯相关新闻/活动流
------------------------------------------------------
function Dashboard._buildNTActivityFeed(gameState)
    -- 筛选世界杯相关消息（inbox 存放 world_cup/national_team，news 存放 world_cup_news）
    local wcMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        if msg.category == "world_cup" or msg.category == "national_team" then
            table.insert(wcMsgs, msg)
            if #wcMsgs >= 4 then break end
        end
    end
    if #wcMsgs < 4 then
        for _, article in ipairs(gameState.news or {}) do
            if article.category == "world_cup_news" then
                table.insert(wcMsgs, article)
                if #wcMsgs >= 4 then break end
            end
        end
    end

    local msgRows = {}
    if #wcMsgs > 0 then
        for _, msg in ipairs(wcMsgs) do
            local dotColor = {255, 215, 0, 255}  -- 金色标识世界杯
            if msg.priority == "high" then dotColor = Theme.COLORS.DANGER end

            table.insert(msgRows, UI.Panel {
                width = "100%", height = 38,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = {255, 255, 255, 10},
                children = {
                    UI.Panel { width = 5, height = 5, borderRadius = 3, backgroundColor = dotColor, marginRight = 8 },
                    UI.Label {
                        text = msg.title or "世界杯动态",
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
            text = "暂无世界杯动态",
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            marginTop = 4, marginBottom = 4,
        })
    end

    return Theme.Card {
        backgroundColor = {20, 30, 50, 255},
        borderColor = {40, 70, 120, 100},
        children = {
            -- 标题
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                marginBottom = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "📰", fontSize = 14, marginRight = 6 },
                            UI.Label { text = "世界杯动态", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        }
                    },
                    UI.Button {
                        text = "全部 →",
                        height = 24,
                        backgroundColor = {0, 0, 0, 0},
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        onClick = function()
                            Router.navigate("inbox")
                        end,
                    },
                }
            },
            -- 消息列表
            table.unpack(msgRows),
        }
    }
end

return Dashboard
