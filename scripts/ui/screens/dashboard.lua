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
local EuroCup = require("scripts/systems/euro_cup")
local TransferManager = require("scripts/systems/transfer_manager")
local DomesticCup = require("scripts/systems/domestic_cup")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local MessageActionHandlers = require("scripts/ui/message_action_handlers")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local Dashboard = {}

------------------------------------------------------
-- 时间推进阻断器
------------------------------------------------------
function Dashboard._checkBlockingActions(gameState)
    return TimeBlockerManager.check(gameState)
end

--- 统一查找下一场玩家比赛（联赛+欧冠+世界杯），返回天数和fixture
--- @return number daysAhead 距离下一场的天数（0=无比赛）
--- @return table|nil fixture 下一场比赛的fixture对象
--- @return boolean isUCL 是否欧冠
--- @return boolean isWC 是否世界杯
function Dashboard._findNextMatch(gameState)
    local League = require("scripts/domain/league")
    local playerTeamId = gameState.playerTeamId
    local ntCoach = gameState.nationalTeamCoach
    local playerNation = ntCoach and ntCoach.nation or nil

    -- 优先检测逾期比赛（日期已过但仍为 scheduled 的玩家比赛）
    -- 这些比赛因日期在过去，不会被后面的正向搜索找到
    local overdueFixture = TurnProcessor.peekOverduePlayerFixture(gameState)
    if overdueFixture then
        local isUCL = overdueFixture._isUCL or false
        local isWC = overdueFixture._isWC or false
        return 0, overdueFixture, isUCL, isWC
    end

    -- 从今天（daysAhead=0）开始搜索，不漏掉当天未打的比赛
    for daysAhead = 0, 90 do
        local futureDate = (daysAhead == 0) and gameState.date or League._addDays(gameState.date, daysAhead)
        -- 检查联赛比赛
        local fixtures = TurnProcessor.getFixturesForDate(gameState, futureDate)
        for _, f in ipairs(fixtures) do
            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                return daysAhead, f, false, false
            end
        end
        -- 检查欧冠比赛
        local uclFixtures = TurnProcessor.getUCLFixturesForDate(gameState, futureDate)
        for _, f in ipairs(uclFixtures) do
            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                return daysAhead, f, true, false
            end
        end
        -- 检查国内杯赛
        local cupFixtures = DomesticCup.getFixturesForDate(gameState, futureDate)
        for _, f in ipairs(cupFixtures) do
            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                return daysAhead, f, false, false
            end
        end
        -- 检查国际大赛（欧洲杯/世界杯）
        if playerNation then
            local euroFixtures = TurnProcessor.getEuroFixturesForDate(gameState, futureDate)
            for _, f in ipairs(euroFixtures) do
                if f.homeTeamId == playerNation or f.awayTeamId == playerNation then
                    return daysAhead, f, false, true
                end
            end
            local wcFixtures = TurnProcessor.getWCFixturesForDate(gameState, futureDate)
            for _, f in ipairs(wcFixtures) do
                if f.homeTeamId == playerNation or f.awayTeamId == playerNation then
                    return daysAhead, f, false, true
                end
            end
        end
    end
    return 0, nil, false, false
end

-- 兼容旧调用
function Dashboard._getDaysToNextMatch(gameState)
    local days = Dashboard._findNextMatch(gameState)
    return days
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

    -- 跳到比赛日（使用统一搜索）
    local daysToMatch, todayFixtureRef = Dashboard._findNextMatch(gameState)

    -- 弹窗消息处理：依次弹出 popup 消息，全部处理完后执行 onDone 回调
    local function runPopupAction(actionId, data)
        if not actionId then return end
        local ok, route, params = MessageActionHandlers.run(gameState, actionId, data)
        if MessageActionHandlers.needsSave(actionId) then
            SaveManager.save(gameState, "auto")
        end
        if ok and route == "national_squad_select" then
            Router.navigate(route, params)
        elseif ok and route == "dashboard" then
            -- 已在 dashboard，无需跳转
        end
    end

    local function showPopupMessages(onDone)
        local queue = gameState:consumePopupQueue()
        if #queue == 0 then
            if onDone then onDone() end
            return
        end

        local index = 0
        local function showNext()
            index = index + 1
            if index > #queue then
                if onDone then onDone() end
                return
            end
            local msg = queue[index]

            if msg.actions and #msg.actions > 2 then
                -- 多选项消息（如国家队邀请）：已有 time blocker 处理，跳过弹窗
                showNext()
            elseif msg.actions and #msg.actions > 0 then
                local firstAction = msg.actions[1]
                local secondAction = msg.actions[2]
                ConfirmDialog.show({
                    title = msg.title or "通知",
                    message = msg.body,
                    confirmText = firstAction and firstAction.label or "确认",
                    cancelText = secondAction and secondAction.label or "关闭",
                    confirmColor = Theme.COLORS.SECONDARY,
                    onConfirm = function()
                        if firstAction then
                            runPopupAction(firstAction.actionId, firstAction.data)
                        end
                        msg.read = true
                        showNext()
                    end,
                    onCancel = function()
                        if secondAction then
                            runPopupAction(secondAction.actionId, secondAction.data)
                        end
                        msg.read = true
                        showNext()
                    end,
                })
            else
                ConfirmDialog.show({
                    title = msg.title or "通知",
                    message = msg.body,
                    confirmText = "知道了",
                    cancelText = "关闭",
                    onConfirm = function()
                        msg.read = true
                        showNext()
                    end,
                    onCancel = function()
                        msg.read = true
                        showNext()
                    end,
                })
            end
        end
        showNext()
    end

    -- 通用推进回调
    local function doAdvanceDay()
        -- 如果有未完成的玩家比赛，先处理它（不推进日期）
        if gameState.pendingPlayerFixture then
            local pf = gameState.pendingPlayerFixture
            if pf.status == "scheduled" then
                Router.navigate("pre_match", { fixture = pf })
                return
            end
            gameState.pendingPlayerFixture = nil
        end

        -- 今天就有未打的比赛（daysToMatch==0），直接进入比赛，不推进日期
        if daysToMatch == 0 and todayFixtureRef then
            todayFixtureRef._pendingPlayerMatch = true
            Router.navigate("pre_match", { fixture = todayFixtureRef })
            return
        end

        -- [BUG FIX] 在推进日期之前，检测是否已有逾期的玩家比赛
        -- 如果有，直接展示给玩家而不消耗日历天数，避免雪球效应
        if not gameState._cheatAutoPlay then
            -- 读档后可能尚未 advanceDay：先修复错位赛程（旧档 3 月中超等）
            local RealDataLoader = require("scripts/data/real_data_loader")
            RealDataLoader.fixMisalignedLeagueFixtures(gameState)
            -- 先补模拟其他球队的逾期比赛（否则 advanceDay 被拦截时积分榜永远不更新）
            TurnProcessor.repairStuckProgressOnLoad(gameState)
            local overdueFixture = TurnProcessor.peekOverduePlayerFixture(gameState)
            if overdueFixture then
                overdueFixture._pendingPlayerMatch = true
                showPopupMessages(function()
                    Router.navigate("pre_match", { fixture = overdueFixture })
                end)
                return
            end
        end

        local prevSeason = gameState.season
        -- pcall 保护：即使推进过程中抛异常（日期已在 advanceDay 内自增），
        -- 也必须继续往下走刷新界面，否则会出现"日期已变但主页不动"的假卡死
        local ok, fixtures = pcall(TurnProcessor.advanceDay, gameState)
        if not ok then
            if log then log:Write(LOG_ERROR, "doAdvanceDay: advanceDay 异常已捕获: " .. tostring(fixtures)) end
            fixtures = nil
        end
        -- 注意：不再每天全量保存（大存档时每次点"继续"都序列化整个世界，
        -- 造成卡顿和内存峰值）。日常保存由 TurnProcessor 按 autoSaveInterval
        -- 周期执行；这里只在关键节点（赛季变更/进入玩家比赛）补充保存。

        -- 如果赛季发生了变更（season_end handler 已经导航到赛季总结页），不要覆盖导航
        if gameState.season ~= prevSeason then
            SaveManager.save(gameState, "auto")
            return
        end

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
            -- 比赛日：关键节点保存后，先弹窗再进入赛前
            SaveManager.save(gameState, "auto")
            showPopupMessages(function()
                Router.navigate("pre_match", { fixture = playerFixture })
            end)
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
            showPopupMessages(function()
                Router.navigate("match_live", {report = report, fixture = playerFixture, minute = 0})
            end)
        else
            -- 非比赛日：先弹窗再刷新主界面
            showPopupMessages(function()
                Router.replaceWith("dashboard")
            end)
        end
    end

    local function doSkipToMatchDay()
        -- [BUG FIX] 跳天前先检查是否有逾期玩家比赛，避免雪球效应
        if not gameState._cheatAutoPlay then
            local overdueFixture = TurnProcessor.peekOverduePlayerFixture(gameState)
            if overdueFixture then
                overdueFixture._pendingPlayerMatch = true
                showPopupMessages(function()
                    Router.navigate("pre_match", { fixture = overdueFixture })
                end)
                return
            end
        end

        -- 最多跳过 daysToMatch 天（安全上限，防止死循环）
        local maxSkip = math.max(daysToMatch, 1)
        local prevSeason = gameState.season
        for i = 1, maxSkip do
            local ok, fixtures = pcall(TurnProcessor.advanceDay, gameState)
            if not ok then
                if log then log:Write(LOG_ERROR, "doSkipToMatchDay: advanceDay 异常已捕获: " .. tostring(fixtures)) end
                fixtures = nil
            end

            -- 如果赛季发生了变更，停止跳天并让 season_end 页面显示
            if gameState.season ~= prevSeason then
                SaveManager.save(gameState, "auto")
                return
            end

            -- 检查是否有弹窗消息（如球员转会决定），停止跳天并弹窗
            local popupQueue = gameState._popupQueue or {}
            if #popupQueue > 0 then
                SaveManager.save(gameState, "auto")
                showPopupMessages(function()
                    Router.replaceWith("dashboard")
                end)
                return
            end

            if fixtures and #fixtures > 0 then
                -- 检查是否有玩家比赛（联赛/欧冠/世界杯）
                local playerFixture = nil
                for _, f in ipairs(fixtures) do
                    if f._pendingPlayerMatch then
                        playerFixture = f
                        break
                    end
                end
                if playerFixture then
                    SaveManager.save(gameState, "auto")
                    showPopupMessages(function()
                        Router.navigate("pre_match", { fixture = playerFixture })
                    end)
                    return
                end
            end
        end
        -- 到达目标日但没有玩家比赛（理论上不会发生），刷新页面
        SaveManager.save(gameState, "auto")
        showPopupMessages(function()
            Router.replaceWith("dashboard")
        end)
    end

    -- 判断当前身份
    local isNTMode = gameState.currentRole == "national_team" and gameState.nationalTeamCoach ~= nil
    -- 如果国家队已不存在（世界杯结束），自动切回俱乐部
    if isNTMode and not gameState.worldCup and not gameState.euroCup then
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

    -- 首次担任国家队主教练后的切换指引
    if gameState.ntCoachGuidancePending then
        gameState.ntCoachGuidancePending = nil
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            Dashboard._showNTCoachGuidance(gameState)
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
                            if not sdk then
                                UI.Toast.Show({ message = "广告暂不可用", variant = "warning" })
                                return
                            end
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
                                    -- 实时存档，防止闪退丢失广告进度
                                    SaveManager.save(gameState, "auto")
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
    local hasTodayMatch = (daysToMatch == 0)
    local continueColor = isBlocked and Theme.COLORS.DANGER
        or (hasTodayMatch and Theme.COLORS.MATCH_ORANGE)
        or (hasAnyBlockers and Theme.COLORS.WARNING or Theme.COLORS.FINANCE_GREEN)
    local continueText = isBlocked and "! 阻断"
        or (hasTodayMatch and "! 继续")
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
        UI.Panel { flexGrow = 1 },
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

    -- 失业状态：快进到邀约按钮
    if gameState._isUnemployed then
        table.insert(children, UI.Button {
            text = "快进到邀约",
            width = 84,
            height = 30,
            backgroundColor = Theme.COLORS.MATCH_ORANGE,
            borderRadius = 6,
            fontSize = 11,
            color = "#FFFFFF",
            marginRight = 6,
            onClick = function()
                Dashboard._skipToJobOffer(gameState)
            end,
        })
    elseif daysToMatch > 1 then
        -- 跳到比赛日按钮（2天以上显示）
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
        height = 44,
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

        -- 国内杯赛
        local cupFixturesForDay = DomesticCup.getFixturesForDate(gameState, futureDate)
        for _, f in ipairs(cupFixturesForDay) do
            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                local cupName = "杯赛"
                local cupShort = "CUP"
                local cups = gameState.domesticCups
                if cups and f._cupLeague and cups[f._cupLeague] then
                    cupName = cups[f._cupLeague].shortName or cups[f._cupLeague].name
                    cupShort = "CUP"
                end
                table.insert(upcomingFixtures, {
                    fixture = f,
                    date = futureDate,
                    daysAhead = daysAhead,
                    competition = cupName,
                    competitionShort = cupShort,
                })
            end
        end

        -- 欧洲杯比赛
        if gameState.euroCup and gameState.euroCup.phase ~= "not_started" and gameState.euroCup.phase ~= "completed" then
            local euroFixtures = gameState.euroCup:getFixturesForDate(futureDate)
            for _, f in ipairs(euroFixtures) do
                if EuroCup.isPlayerNationMatch(gameState, f) then
                    table.insert(upcomingFixtures, {
                        fixture = f,
                        date = futureDate,
                        daysAhead = daysAhead,
                        competition = "欧洲杯",
                        competitionShort = "EURO",
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
        elseif entry.competitionShort == "CUP" then
            compColor = {180, 80, 200, 255}
        elseif entry.competitionShort == "EURO" then
            compColor = {50, 180, 100, 255}
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

    -- 使用统一搜索：确保显示和跳过按钮找到的是同一场比赛
    local daysToMatch, nextFixture, isUCLMatch, isWCMatch = Dashboard._findNextMatch(gameState)

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

    local playerTeamId = gameState.playerTeamId
    local opponentId
    if isWCMatch then
        local playerNation = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation
        opponentId = nextFixture.homeTeamId == playerNation
            and nextFixture.awayTeamId or nextFixture.homeTeamId
    else
        opponentId = nextFixture.homeTeamId == playerTeamId
            and nextFixture.awayTeamId or nextFixture.homeTeamId
    end
    local opponent = gameState.teams[opponentId]
    local isHome = isWCMatch
        and (nextFixture.homeTeamId == (gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation))
        or (nextFixture.homeTeamId == playerTeamId)
    local venue = isHome and "主场" or "客场"
    local opponentName
    if isWCMatch then
        local WorldCup = require("scripts/systems/world_cup")
        opponentName = WorldCup._getNationName(opponentId) or opponentId
    else
        opponentName = opponent and opponent.name or "未知"
    end

    -- 日期和倒计时
    local matchDateStr = string.format("%d月%d日", nextFixture.date.month, nextFixture.date.day)
    local countdownText = daysToMatch == 0 and "今天" or (daysToMatch == 1 and "明天" or (daysToMatch .. "天后"))

    -- 赛事信息
    local competitionInfo
    if isWCMatch then
        competitionInfo = "世界杯"
    elseif isUCLMatch then
        local matchdayStr = nextFixture.matchday and ("第" .. nextFixture.matchday .. "比赛日") or ""
        competitionInfo = "欧冠 " .. matchdayStr
    elseif nextFixture._isDomesticCup then
        -- 国内杯赛
        local cupName = "杯赛"
        local cups = gameState.domesticCups
        if cups and nextFixture._cupLeague and cups[nextFixture._cupLeague] then
            cupName = cups[nextFixture._cupLeague].name or cups[nextFixture._cupLeague].shortName or "杯赛"
        end
        local roundNum = nextFixture.round or 1
        local roundLabel = (roundNum == (cups and nextFixture._cupLeague and cups[nextFixture._cupLeague] and cups[nextFixture._cupLeague].totalRounds or 99))
            and "决赛" or ("第" .. roundNum .. "轮")
        competitionInfo = cupName .. " " .. roundLabel
    else
        local leagueName = league and league.name or ""
        local roundNum = nextFixture.round or (league and league.currentRound or 1)
        competitionInfo = leagueName .. " 第" .. roundNum .. "轮"
    end

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
            -- 左上角俱乐部/国家队图标（叠在卡片上）
            UI.Panel {
                position = "absolute",
                top = 10, left = 10,
                zIndex = 10,
                children = {
                    Dashboard._buildTeamIconSwitcher(gameState, team),
                },
            },
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
                    UI.Label { text = competitionInfo, fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
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

    -- 转会窗口提醒
    local month = gameState.date.month
    local inWindow = TransferManager.isInTransferWindow(gameState)
    if inWindow then
        -- 窗口内：提示即将关闭
        local windowName, closingMonth
        if month >= 6 and month <= 8 then
            windowName = "夏季转会窗"
            closingMonth = 8
        else
            windowName = "冬季转会窗"
            closingMonth = 1
        end
        local isLastMonth = (month == closingMonth)
        if isLastMonth then
            table.insert(items, {
                icon = "⏰",
                text = windowName .. "本月底关闭，抓紧完成交易",
                color = Theme.COLORS.WARNING,
                action = function() Router.navigate("market") end,
            })
        else
            table.insert(items, {
                icon = "📋",
                text = windowName .. "开启中 (" .. closingMonth .. "月底关闭)",
                color = Theme.COLORS.ACCENT,
                action = function() Router.navigate("market") end,
            })
        end
    else
        -- 窗口外：提示下个窗口时间
        local nextWindow
        if month >= 2 and month <= 5 then
            nextWindow = "夏窗将于6月开启"
        elseif month >= 9 and month <= 12 then
            nextWindow = "冬窗将于1月开启"
        end
        if nextWindow then
            table.insert(items, {
                icon = "🔒",
                text = "转会窗口已关闭 · " .. nextWindow,
                color = Theme.COLORS.TEXT_MUTED,
                action = function() Router.navigate("market") end,
            })
        end
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
            local seasonTotal = math.max(1, summary.seasonTotalCount or 1)
            local seasonDone = summary.seasonCompletedCount or 0
            local milestones = {}
            for i = 1, seasonTotal do
                local done = i <= seasonDone
                local dotColor = done and objColor or {255, 255, 255, 40}
                table.insert(milestones, UI.Panel {
                    alignItems = "center",
                    marginRight = i < seasonTotal and 0 or 0,
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
                if i < seasonTotal then
                    local lineColor = i < seasonDone and objColor or {255, 255, 255, 20}
                    table.insert(milestones, UI.Panel {
                        flexGrow = 2, height = 2, borderRadius = 1,
                        backgroundColor = lineColor,
                        alignSelf = "center",
                    })
                end
            end

            local monthlyProg = summary.activeMonthlyProgress
            local monthlyPct = monthlyProg and monthlyProg.pct or 0
            local monthlyLabel = monthlyProg and monthlyProg.label or "—"
            local monthlyBarColor = monthlyPct >= 100 and Theme.COLORS.FINANCE_GREEN
                                 or monthlyPct >= 50 and Theme.COLORS.MATCH_ORANGE
                                 or Theme.COLORS.INFO_BLUE

            return UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 12,
                paddingLeft = 14, paddingRight = 14, paddingTop = 10, paddingBottom = 10,
                marginBottom = 8,
                flexDirection = "column",
                onClick = function() Dashboard._showObjectivesDetail(gameState) end,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Panel {
                                marginRight = 12,
                                children = {
                                    UI.Label { text = "赛季目标", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                                    UI.Label {
                                        text = seasonDone .. "/" .. seasonTotal,
                                        fontSize = 14, color = objColor, fontWeight = "bold", marginTop = 2,
                                    },
                                }
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                flexDirection = "row", alignItems = "center",
                                children = milestones,
                            },
                            UI.Panel {
                                marginLeft = 12, alignItems = "flex-end",
                                children = {
                                    UI.Label {
                                        text = summary.seasonText or "",
                                        fontSize = 10, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                    },
                                }
                            },
                        }
                    },
                    summary.monthlyText and UI.Panel {
                        width = "100%", marginTop = 8,
                        children = {
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                marginBottom = 4,
                                children = {
                                    UI.Label { text = "本月目标", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                                    UI.Label { text = monthlyLabel, fontSize = 10, color = monthlyBarColor, fontWeight = "bold" },
                                }
                            },
                            UI.Label {
                                text = summary.monthlyText,
                                fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 4,
                            },
                            Theme.ProgressBar { value = monthlyPct, color = monthlyBarColor, height = 5 },
                        }
                    } or UI.Panel { height = 0 },
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
            Theme.SectionHeader {
                text = "俱乐部状态",
                color = Theme.COLORS.INFO_BLUE,
                rightChild = UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    children = {
                        -- 潜力透视按钮（广告）
                        UI.Button {
                            text = gameState.potentialRevealed and "🔓" or "🔮",
                            width = 28,
                            height = 28,
                            backgroundColor = gameState.potentialRevealed and {30, 60, 50, 255} or Theme.COLORS.TRANSPARENT,
                            borderRadius = 14,
                            fontSize = 14,
                            color = gameState.potentialRevealed and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED,
                            marginRight = 6,
                            onClick = function()
                                Dashboard._showPotentialModifierDialog(gameState)
                            end,
                        },
                        -- 荣誉室按钮
                        UI.Button {
                            text = "🏆",
                            width = 28,
                            height = 28,
                            backgroundColor = Theme.COLORS.TRANSPARENT,
                            borderRadius = 14,
                            fontSize = 14,
                            color = Theme.COLORS.TEXT_MUTED,
                            onClick = function()
                                Router.navigate("trophy_cabinet")
                            end,
                        },
                    },
                },
            },

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
    -- 其次欧洲杯
    if gameState.euroCup then
        local euro = gameState.euroCup
        return {
            name = "欧洲杯",
            phase = phaseNames[euro.phase] or euro.phase,
            posText = "",
            color = {100, 180, 255, 255},
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
    local monthlies = ObjectivesManager._getMonthlies(gameState.objectives)
    if #monthlies > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 10, marginBottom = 10 })
        table.insert(children, UI.Label {
            text = "本月目标",
            fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
            marginBottom = 6,
        })
        for _, monthly in ipairs(monthlies) do
            local mColor = monthly.status == "completed" and Theme.COLORS.FINANCE_GREEN
                        or monthly.status == "failed" and Theme.COLORS.DANGER
                        or Theme.COLORS.INFO_BLUE
            local mIcon = monthly.status == "completed" and "✓ " or monthly.status == "failed" and "✗ " or "→ "
            local prog = ObjectivesManager.getMonthlyProgress(gameState, monthly, gameState:getPlayerTeam())
            table.insert(children, UI.Label {
                text = mIcon .. monthly.text .. "  (" .. (prog and prog.label or "—") .. ")",
                fontSize = 13, color = mColor, paddingLeft = 4, marginBottom = 4,
            })
        end
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
-- [顶栏] 队徽图标 + 身份切换（整合版）
------------------------------------------------------
function Dashboard._buildTeamIconSwitcher(gameState, team)
    local hasNT = gameState.nationalTeamCoach and (gameState.worldCup or gameState.euroCup)
    local isNT = gameState.currentRole == "national_team"

    -- 根据当前模式决定显示内容
    local iconChild
    if isNT and hasNT then
        -- 国家队模式：显示国家队图标
        local nationCode = gameState.nationalTeamCoach.nation
        local iconPath = WorldCup.getNationIconPath(nationCode)
        if iconPath then
            iconChild = UI.Panel {
                width = 26, height = 26,
                borderRadius = 13,
                backgroundImage = iconPath,
                backgroundSize = "contain",
            }
        else
            local nationName = WorldCup._getNationName(nationCode) or nationCode
            iconChild = UI.Panel {
                width = 26, height = 26,
                borderRadius = 13,
                backgroundColor = {25, 60, 90, 255},
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label { text = string.sub(nationName, 1, 3), fontSize = 9, color = {130, 200, 255, 255} },
                },
            }
        end
    else
        -- 俱乐部模式：显示俱乐部图标
        iconChild = TeamIcon.create { team = team, size = 26 }
    end

    -- 标签文字
    local label = ""
    if hasNT then
        if isNT then
            local nationName = WorldCup._getNationName(gameState.nationalTeamCoach.nation) or ""
            label = nationName
        else
            label = "俱乐部"
        end
    else
        label = "俱乐部"
    end

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        marginLeft = 6,
        height = 34,
        paddingLeft = 4, paddingRight = 8,
        backgroundColor = hasNT and (isNT and {25, 60, 90, 200} or {50, 50, 55, 200}) or Theme.COLORS.TRANSPARENT,
        borderRadius = 17,
        onClick = function()
            if hasNT then
                -- 有国家队身份：切换模式
                if gameState.currentRole == "national_team" then
                    gameState.currentRole = "club"
                else
                    gameState.currentRole = "national_team"
                end
                Router.replaceWith("dashboard")
            else
                -- 无国家队身份：查看经理档案
                Router.navigate("manager_view")
            end
        end,
        children = {
            iconChild,
            UI.Label {
                text = label,
                fontSize = 11,
                color = isNT and {130, 200, 255, 255} or Theme.COLORS.TEXT_SECONDARY,
                marginLeft = 5,
                fontWeight = "bold",
            },
        },
    }
end

------------------------------------------------------
-- [国家队模式] 首次上任指引弹窗
------------------------------------------------------
function Dashboard._showNTCoachGuidance(gameState)
    local nationName = ""
    if gameState.nationalTeamCoach then
        local WorldCupMod = require("scripts/systems/world_cup")
        nationName = WorldCupMod._getNationName(gameState.nationalTeamCoach.nation) or ""
    end

    -- 获取国旗图标
    local WorldCup = require("scripts/systems/world_cup")
    local nationCode = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation or ""
    local nationIconPath = WorldCup.getNationIconPath(nationCode)

    -- 国旗图标或 fallback emoji
    local flagIcon
    if nationIconPath then
        flagIcon = UI.Panel {
            width = 52, height = 52, marginBottom = 12,
            borderRadius = 26,
            backgroundColor = {255, 255, 255, 20},
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Panel {
                    width = 40, height = 40, borderRadius = 20,
                    backgroundImage = nationIconPath,
                    backgroundSize = "contain",
                },
            },
        }
    else
        flagIcon = UI.Label {
            text = "🏳️", fontSize = 42, marginBottom = 12,
        }
    end

    local overlay = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = {0, 0, 0, 180},
        justifyContent = "center",
        alignItems = "center",
        children = {
            -- 主卡片
            UI.Panel {
                width = 320,
                maxWidth = "88%",
                backgroundColor = {20, 22, 30, 252},
                borderRadius = 20,
                paddingTop = 32, paddingBottom = 28, paddingLeft = 24, paddingRight = 24,
                alignItems = "center",
                borderWidth = 1.5,
                borderColor = {200, 170, 80, 120},
                children = {
                    -- 旗帜图标
                    flagIcon,
                    -- 标题（金色）
                    UI.Label {
                        text = "国家队身份已激活",
                        fontSize = 20,
                        color = {240, 200, 80, 255},
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    -- 副标题
                    UI.Label {
                        text = string.format("恭喜！你已成为%s主教练。", nationName),
                        fontSize = 14,
                        color = {200, 200, 210, 255},
                        textAlign = "center",
                        marginBottom = 20,
                    },
                    -- 操作指引卡片
                    UI.Panel {
                        width = "100%",
                        backgroundColor = {255, 248, 220, 12},
                        borderRadius = 14,
                        borderWidth = 1,
                        borderColor = {200, 170, 80, 60},
                        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
                        alignItems = "center",
                        marginBottom = 16,
                        children = {
                            UI.Label {
                                text = "👆 点击顶部栏的队徽图标切换",
                                fontSize = 13,
                                color = {240, 210, 100, 255},
                                fontWeight = "bold",
                                textAlign = "center",
                                marginBottom = 10,
                            },
                            -- 切换按钮示意
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                justifyContent = "center",
                                backgroundColor = {30, 32, 40, 200},
                                borderRadius = 16,
                                paddingTop = 6, paddingBottom = 6, paddingLeft = 12, paddingRight = 12,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", marginRight = 8,
                                        backgroundColor = {50, 52, 60, 255},
                                        borderRadius = 10,
                                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                                        children = {
                                            UI.Label { text = "🏠 俱乐部", fontSize = 11, color = {180, 180, 190, 255} },
                                        },
                                    },
                                    UI.Label { text = "⇄", fontSize = 16, color = {200, 170, 80, 220}, marginRight = 8 },
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center",
                                        backgroundColor = {60, 50, 20, 255},
                                        borderRadius = 10,
                                        borderWidth = 1, borderColor = {200, 170, 80, 100},
                                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                                        children = {
                                            UI.Label { text = "🏴 " .. nationName, fontSize = 11, color = {240, 210, 100, 255} },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    -- 说明文字
                    UI.Label {
                        text = "你可以随时点击顶部栏的队徽\n切换「俱乐部」与「国家队」身份，\n分别管理两支球队的事务。",
                        fontSize = 13,
                        color = {150, 150, 160, 255},
                        textAlign = "center",
                        lineHeight = 1.6,
                        width = "100%",
                        whiteSpace = "normal",
                        marginBottom = 22,
                    },
                    -- 按钮（金色调）
                    UI.Button {
                        text = "知道了",
                        width = 140,
                        height = 40,
                        fontSize = 15,
                        color = {30, 25, 10, 255},
                        backgroundColor = {220, 185, 70, 255},
                        borderRadius = 20,
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                        end,
                    },
                },
            },
        },
    }

    UI.ShowOverlay(overlay)
end

------------------------------------------------------
-- [国家队模式] 下一场世界杯比赛 Hero
------------------------------------------------------
function Dashboard._buildNTMatchHero(gameState)
    local wc = gameState.worldCup
    local euro = gameState.euroCup
    local ntCoach = gameState.nationalTeamCoach
    if (not wc and not euro) or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local isEuro = euro ~= nil
    local NT = isEuro and EuroCup or WorldCup
    local compLabel = isEuro and "欧洲杯" or "世界杯"
    local tournament = isEuro and euro or wc

    local playerNation = ntCoach.nation
    local nationName = NT._getNationName(playerNation)

    -- 查找下一场国家队比赛
    local nextFixture = nil
    local League = require("scripts/domain/league")
    for daysAhead = 0, 60 do
        local futureDate = League._addDays(gameState.date, daysAhead)
        local ntFixtures = isEuro
            and TurnProcessor.getEuroFixturesForDate(gameState, futureDate)
            or TurnProcessor.getWCFixturesForDate(gameState, futureDate)
        for _, f in ipairs(ntFixtures) do
            if f.homeTeamId == playerNation or f.awayTeamId == playerNation then
                if f.status == "scheduled" then
                    nextFixture = f
                    break
                end
            end
        end
        if nextFixture then break end
    end

    local phaseNames = {
        group = "小组赛",
        r32 = "三十二强",
        r16 = "十六强",
        qf = "四分之一决赛",
        sf = "半决赛",
        final = "决赛",
        completed = "已结束",
    }
    local phaseName = phaseNames[tournament.phase] or compLabel

    if not nextFixture then
        local statusText = tournament.phase == "completed" and (compLabel .. "已结束") or "暂无比赛安排"
        if tournament.champion then
            local champName = NT._getNationName(tournament.champion)
            statusText = "🏆 冠军: " .. champName
        end
        return UI.Panel {
            width = "100%",
            backgroundColor = {20, 35, 60, 255},
            borderRadius = 14,
            paddingTop = 16, paddingBottom = 16, paddingLeft = 16, paddingRight = 16,
            marginBottom = 12,
            overflow = "hidden",
            children = {
                -- 左上角俱乐部/国家队切换图标
                UI.Panel {
                    position = "absolute",
                    top = 10, left = 10,
                    zIndex = 10,
                    children = {
                        Dashboard._buildTeamIconSwitcher(gameState, gameState:getPlayerTeam()),
                    },
                },
                Theme.SectionHeader { text = "🏆 " .. compLabel .. " · " .. phaseName, color = {255, 215, 0, 255} },
                UI.Label {
                    text = statusText,
                    fontSize = 14, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                },
            }
        }
    end

    local opponentCode = nextFixture.homeTeamId == playerNation
        and nextFixture.awayTeamId or nextFixture.homeTeamId
    local opponentName = NT._getNationName(opponentCode)
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
            -- 左上角俱乐部/国家队切换图标（叠在卡片上）
            UI.Panel {
                position = "absolute",
                top = 10, left = 10,
                zIndex = 10,
                children = {
                    Dashboard._buildTeamIconSwitcher(gameState, gameState:getPlayerTeam()),
                },
            },
            -- 顶部：世界杯 + 阶段 + 倒计时
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
                marginBottom = 6,
                children = {
                    UI.Label { text = "🏆 " .. compLabel .. " · " .. phaseName, fontSize = 13, color = {255, 215, 0, 255} },
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

            -- 对阵区：国家队徽 + 国名 + VS
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
                                overflow = "hidden",
                                backgroundImage = NT.getNationIconPath(playerNation) or "",
                                backgroundFit = "contain",
                                children = (not NT.getNationIconPath(playerNation)) and {
                                    UI.Label { text = playerNation or "?", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                } or {},
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
                                overflow = "hidden",
                                backgroundImage = NT.getNationIconPath(opponentCode) or "",
                                backgroundFit = "contain",
                                children = (not NT.getNationIconPath(opponentCode)) and {
                                    UI.Label { text = opponentCode or "?", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                } or {},
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
    local euro = gameState.euroCup
    local ntCoach = gameState.nationalTeamCoach
    if (not wc and not euro) or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local isEuro = euro ~= nil
    local NT = isEuro and EuroCup or WorldCup
    local tournament = isEuro and euro or wc

    local playerNation = ntCoach.nation
    local nationName = NT._getNationName(playerNation)

    local myGroup = nil
    local myGroupName = ""
    for gName, group in pairs(tournament.groups or {}) do
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
    if myGroup and tournament.phase == "group" then
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
            local name = NT._getNationName(s.teamId)
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

    -- 淘汰赛阶段信息（包括已完赛，仍显示bracket供回顾）
    local knockoutInfo = nil
    if tournament.phase ~= "group" and tournament.phase ~= "not_started" then
        knockoutInfo = tournament.phase == "completed" and "赛事已结束" or "进入淘汰赛阶段"
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
        -- 淘汰赛对阵图（compact bracket tree）
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8,
            children = {
                UI.Label { text = "⚔️", fontSize = 14, marginRight = 6 },
                UI.Label { text = "淘汰赛对阵", fontSize = 13, color = {255, 215, 0, 255}, fontWeight = "bold" },
            }
        })

        -- 构建紧凑型bracket
        local bracketPhases = {
            {key = "r32", name = "32强"},
            {key = "r16", name = "16强"},
            {key = "qf", name = "8强"},
            {key = "sf", name = "4强"},
            {key = "final", name = "决赛"},
        }

        local function buildMiniCard(f)
            if not f then
                return UI.Panel {
                    width = 100, height = 32,
                    backgroundColor = {30, 35, 50, 255},
                    borderRadius = 4, borderWidth = 1, borderColor = {50, 55, 70, 255},
                    justifyContent = "center", alignItems = "center",
                    marginTop = 1, marginBottom = 1,
                    children = {
                        UI.Label { text = "—", fontSize = 9, color = Theme.COLORS.TEXT_MUTED },
                    }
                }
            end

            local hName = WorldCup._getNationName(f.homeTeamId)
            local aName = WorldCup._getNationName(f.awayTeamId)
            if #hName > 4 then hName = string.sub(hName, 1, 6) end
            if #aName > 4 then aName = string.sub(aName, 1, 6) end

            local done = f.status == "finished"
            local hWin = done and (f.homeGoals > f.awayGoals or (f._penaltyWinner and f._penaltyWinner == f.homeTeamId))
            local aWin = done and (f.awayGoals > f.homeGoals or (f._penaltyWinner and f._penaltyWinner == f.awayTeamId))
            local hCol = hWin and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY
            local aCol = aWin and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY
            local bg = done and {20, 35, 55, 255} or {30, 35, 50, 255}
            local bd = done and {40, 80, 130, 255} or {50, 55, 70, 255}

            return UI.Panel {
                width = 100, height = 32,
                backgroundColor = bg,
                borderRadius = 4, borderWidth = 1, borderColor = bd,
                justifyContent = "center",
                paddingLeft = 4, paddingRight = 4,
                marginTop = 1, marginBottom = 1,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = hName, fontSize = 9, color = hCol, fontWeight = hWin and "bold" or "normal", flexShrink = 1 },
                            UI.Label { text = done and tostring(f.homeGoals) or "", fontSize = 9, color = {180, 200, 255, 255}, width = 10, textAlign = "right" },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = aName, fontSize = 9, color = aCol, fontWeight = aWin and "bold" or "normal", flexShrink = 1 },
                            UI.Label { text = done and tostring(f.awayGoals) or "", fontSize = 9, color = {180, 200, 255, 255}, width = 10, textAlign = "right" },
                        }
                    },
                }
            }
        end

        local bracketCols = {}
        for _, bp in ipairs(bracketPhases) do
            local fixtures = tournament.knockout[bp.key] or {}
            local realFixtures = {}
            for _, f in ipairs(fixtures) do
                if not f._isThirdPlace then table.insert(realFixtures, f) end
            end

            local colChildren = {}
            table.insert(colChildren, UI.Panel {
                width = "100%", alignItems = "center", marginBottom = 4,
                children = {
                    UI.Label { text = bp.name, fontSize = 9, color = {150, 180, 220, 255}, fontWeight = "bold" },
                }
            })

            if #realFixtures > 0 then
                for _, f in ipairs(realFixtures) do
                    table.insert(colChildren, buildMiniCard(f))
                end
            else
                local expectedCount = ({r32 = 16, r16 = 8, qf = 4, sf = 2, final = 1})[bp.key] or 0
                for _ = 1, expectedCount do
                    table.insert(colChildren, buildMiniCard(nil))
                end
            end

            table.insert(bracketCols, UI.Panel {
                alignItems = "center",
                justifyContent = "space-around",
                flexGrow = 1,
                children = colChildren,
            })
        end

        -- 冠军列（如果有）
        if tournament.champion then
            local champName = NT._getNationName(tournament.champion)
            table.insert(bracketCols, UI.Panel {
                alignItems = "center", justifyContent = "center", flexGrow = 1,
                children = {
                    UI.Label { text = "🏆", fontSize = 18 },
                    UI.Label { text = champName, fontSize = 10, color = {255, 215, 0, 255}, fontWeight = "bold", marginTop = 4 },
                }
            })
        end

        table.insert(children, UI.ScrollView {
            width = "100%",
            height = 360,
            scrollX = true,
            scrollY = false,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "stretch",
                    height = "100%",
                    children = bracketCols,
                }
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

------------------------------------------------------
-- [快进到邀约] 失业状态下快进到收到工作邀约
------------------------------------------------------
function Dashboard._skipToJobOffer(gameState)
    local MAX_SKIP_DAYS = 30
    local JobManager = require("scripts/systems/job_manager")

    for i = 1, MAX_SKIP_DAYS do
        local prevSeason = gameState.season
        TurnProcessor.advanceDay(gameState)

        -- 赛季变更则停止
        if gameState.season ~= prevSeason then
            SaveManager.save(gameState, "auto")
            return
        end

        -- 检查是否已收到邀约
        local offers = JobManager.getPendingOffers(gameState)
        if #offers > 0 then
            SaveManager.save(gameState, "auto")
            UI.Toast.Show({ message = string.format("快进了%d天，收到工作邀约！", i), variant = "success" })
            Router.replaceWith("dashboard")
            return
        end

        -- 不再失业（比如其他逻辑导致重新上岗）
        if not gameState._isUnemployed then
            SaveManager.save(gameState, "auto")
            Router.replaceWith("dashboard")
            return
        end
    end

    -- 达到上限仍无邀约
    SaveManager.save(gameState, "auto")
    UI.Toast.Show({ message = "快进30天仍未收到邀约，请继续等待或主动申请", variant = "warning" })
    Router.replaceWith("dashboard")
end

return Dashboard
