-- ui/screens/match_live.lua
-- 实时比赛页 - 自动推进模拟，遇关键事件暂停，换人/战术指令实时影响结果

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local MatchSession = require("scripts/match/match_session")
local AudioManager = require("scripts/systems/audio_manager")
local TeamIcon = require("scripts/ui/components/team_icon")

local MatchLive = {}

-- 自动推进状态（模块级，跨页面刷新保持）
local autoPlay = {
    running = false,       -- 是否在自动推进
    speed = 1,             -- 速度倍率：1=1秒/分钟, 2=0.5秒/分钟, 3=0.33秒/分钟
    accumulator = 0,       -- 时间累积器
    pauseReason = nil,     -- 暂停原因文字（事件暂停时显示）
}

-- 自动推进间隔（秒/分钟），根据速度倍率
local SPEED_INTERVALS = { [1] = 1.0, [2] = 0.5, [3] = 0.25 }
local SPEED_LABELS = { [1] = "▶", [2] = "▶▶", [3] = "▶▶▶" }

-- 需要暂停的事件类型
local PAUSE_EVENTS = {
    goal = true,
    red_card = true,
    injury = true,
}

-- 比赛解说文本模板
local COMMENTARY = {
    goal = {
        "%s 进球了！比分改写！",
        "漂亮！%s 攻入一球！",
        "不可思议的进球！%s！",
        "%s 抓住机会将球送入球门！",
        "%s 冷静推射，皮球应声入网！",
        "禁区内一片混乱，%s 补射得手！",
        "%s 转身抽射，球进了！！",
    },
    goal_assist = {
        "%s 助攻，%s 完成破门！",
        "%s 妙传，%s 一蹴而就！",
        "精彩配合！%s 助攻 %s 得分！",
        "%s 送出致命直塞，%s 单刀破门！",
        "%s 横传门前，%s 轻松推射入网！",
    },
    goal_corner = {
        "角球开出，%s 高高跃起头球破门！",
        "%s 在前点抢到落点，头槌入网！",
        "角球造成杀伤！%s 乱战中捅射得手！",
        "战术角球配合，%s 后点包抄得分！",
    },
    goal_free_kick = {
        "任意球机会！%s 直接攻破球门！世界波！",
        "%s 的任意球绕过人墙直挂死角！",
        "任意球开入禁区，%s 抢点破门！",
        "%s 主罚的任意球造成混乱，皮球滚入网窝！",
    },
    goal_penalty = {
        "点球！%s 一蹴而就，骗过门将！",
        "%s 站上十二码点……稳稳命中！",
        "点球破门！%s 把球打进死角，门将方向判断错误！",
    },
    goal_own = {
        "不幸的乌龙球！%s 将球送入自家球门！",
        "防守失误！%s 解围不慎自摆乌龙！",
        "门前混乱中 %s 蹭入自家大门，太遗憾了！",
    },
    yellow_card = {
        "%s 因犯规领到黄牌。",
        "裁判向 %s 出示黄牌。",
        "%s 拿到一张黄牌，需要注意了。",
    },
    yellow_card_reason = {
        "%s 因%s被出示黄牌。",
        "裁判毫不犹豫，%s 因%s吃到黄牌。",
        "%s 因%s被记名，接下来要小心了。",
    },
    red_card = {
        "%s 被红牌罚下！",
        "裁判出示红牌！%s 必须离场！",
    },
    red_card_reason = {
        "红牌！%s 因%s被直接罚下！",
        "%s 因%s染红离场，球队只剩十人应战！",
    },
    injury = {
        "%s 受伤倒地，队医入场。",
        "不幸的消息，%s 因伤离场。",
    },
    injury_detail = {
        "%s 受伤倒地——初步诊断为%s（%s，预计缺阵约%d天）。",
        "队医示意需要换人，%s 遭遇%s（%s，约%d天恢复）。",
        "%s 无法坚持比赛，%s让他提前离场（%s，预计%d天）。",
    },
    substitution = {
        "%s 换下 %s。",
        "换人！%s 替换 %s 出场。",
        "教练变阵：%s 登场，换下 %s。",
    },
    tactical_change = {
        "教练做出战术调整：%s。",
    },
    save = {
        "门将做出精彩扑救！化解 %s 的射门威胁。",
        "%s 的射门被门将稳稳没收。",
        "好球！门将飞身扑出 %s 的射门！",
        "%s 大力抽射，门将神勇将球挡出！",
        "%s 近距离头球，被门将神速反应扑出！",
        "单刀！%s 挑射被门将用腿挡出！",
    },
    save_penalty = {
        "点球被扑出！门将判断对了方向，%s 的点球没能转化为进球！",
        "神扑！%s 主罚的点球被门将拒之门外！",
    },
    miss_penalty = {
        "%s 的点球打飞了！不可思议！",
        "点球射失！%s 把球打在横梁上弹出！",
    },
    hit_post = {
        "%s 的射门击中门柱弹出！差一点！",
        "门框救险！%s 的射门打在立柱上！",
        "%s 一脚怒射击中横梁！太可惜了！",
        "%s 的弧线球擦着门柱滑出，门将已经没有反应！",
    },
    shot_off_target = {
        "%s 射门偏出球门。",
        "%s 的远射高出横梁。",
        "%s 起脚射门，皮球稍稍偏出立柱。",
        "%s 射门滑门而出，错失良机！",
        "%s 仓促起脚，皮球飞向看台。",
    },
}

--- 根据事件的 templateIdx 确定性地选择模板
local function pickTemplate(templates, templateIdx)
    local idx = ((templateIdx or 1) - 1) % #templates + 1
    return templates[idx]
end

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
                    onClick = function() MatchLive.cleanup(); Router.navigate("dashboard") end
                }
            }
        }
    end

    local homeName, awayName, playerTeamId, homeTeam, awayTeam
    if session._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        homeName = session._wcHomeTeam and session._wcHomeTeam.name or WorldCup._getNationName(session.fixture.homeTeamId)
        awayName = session._wcAwayTeam and session._wcAwayTeam.name or WorldCup._getNationName(session.fixture.awayTeamId)
        playerTeamId = WorldCup._getPlayerNation(gameState)
        homeTeam = session._wcHomeTeam
        awayTeam = session._wcAwayTeam
    else
        homeTeam = gameState.teams[session.fixture.homeTeamId]
        awayTeam = gameState.teams[session.fixture.awayTeamId]
        homeName = homeTeam and homeTeam.name or "主队"
        awayName = awayTeam and awayTeam.name or "客队"
        playerTeamId = gameState.playerTeamId
    end

    -- 自动推进：注册/更新 Update 事件处理（每次页面刷新绑定最新 session 引用）
    MatchLive._currentSession = session
    MatchLive._currentFixture = fixture
    MatchLive._currentParams = params
    if not MatchLive._updateSubscribed then
        MatchLive._updateSubscribed = true
        SubscribeToEvent("Update", "HandleMatchAutoAdvance")
    end

    -- 启动球场氛围音（持续循环）
    if not AudioManager.isCrowdAmbientPlaying() then
        AudioManager.startCrowdAmbient()
    end

    -- 比赛结束或进入特殊模式时停止自动推进
    if session:isFinished() or session:isHalfTime() or session:needsPenalties() then
        autoPlay.running = false
    end

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

    -- 解说事件列表（全部事件，最新在前，最多显示20条）
    local commentaryChildren = {}
    if matchEnded then
        table.insert(commentaryChildren, MatchLive._commentaryRow(currentMinute, "全场比赛结束！", Theme.COLORS.PRIMARY))
    end

    local commentaryCount = 0
    local maxCommentary = 20
    for i = #session.events, 1, -1 do
        if commentaryCount >= maxCommentary then break end
        local evt = session.events[i]
        local text, color = MatchLive._getCommentaryText(evt, gameState)
        if text then
            table.insert(commentaryChildren, MatchLive._commentaryRow(evt.minute, text, color))
            commentaryCount = commentaryCount + 1
        end
    end

    if currentMinute >= 45 then
        table.insert(commentaryChildren, MatchLive._commentaryRow(45, "── 中场休息 ──", Theme.COLORS.TEXT_MUTED))
    end
    if currentMinute > 0 then
        table.insert(commentaryChildren, MatchLive._commentaryRow(0, "比赛开始！裁判吹响了开场哨。", Theme.COLORS.SECONDARY))
    end

    -- 实时统计（比赛进行中和结束后都显示）
    local homePoss = session.totalPossessionTicks > 0
        and math.floor(session.homePossessionTicks / session.totalPossessionTicks * 100) or 50
    local statsSection = Theme.Card {
        children = {
            Theme.Subtitle { text = "比赛统计" },
            MatchLive._statBar("控球", homePoss, 100 - homePoss, "%"),
            MatchLive._statBar("射门", session.homeShots, session.awayShots, ""),
            MatchLive._statBar("射正", session.homeShotsOnTarget, session.awayShotsOnTarget, ""),
            MatchLive._statBar("犯规", session.homeFouls, session.awayFouls, ""),
        }
    }

    -- 进球者列表（显示在比分板下方）
    local goalEvents = {}
    for _, evt in ipairs(session.events) do
        if evt.type == "goal" then
            table.insert(goalEvents, evt)
        end
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
        -- 正常比赛流 - 统计 + 动态
        local normalChildren = {}

        -- 实时统计（比赛进行中始终显示）
        if currentMinute > 0 then
            table.insert(normalChildren, statsSection)
        end

        -- 关键事件卡片（只显示进球、红牌等重要事件）
        local keyEvents = {}
        for _, evt in ipairs(session.events) do
            if evt.type == "goal" or evt.type == "red_card" then
                table.insert(keyEvents, evt)
            end
        end
        if #keyEvents > 0 then
            local keyRows = {}
            for i = #keyEvents, 1, -1 do
                local evt = keyEvents[i]
                local player = evt.playerId and gameState.players[evt.playerId]
                local pName = player and player.displayName or "球员"
                local teamName = evt.teamId == session.fixture.homeTeamId and homeName or awayName
                local icon = evt.type == "goal" and "⚽" or "🟥"
                local text
                if evt.type == "goal" then
                    if evt.isOwnGoal then
                        text = string.format("%s 乌龙球 (%s)", pName, teamName)
                    else
                        text = string.format("%s (%s)", pName, teamName)
                    end
                else
                    text = string.format("%s 红牌 (%s)", pName, teamName)
                end
                table.insert(keyRows, UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center",
                    marginBottom = 6, paddingLeft = 4,
                    children = {
                        UI.Label { text = icon, fontSize = 14, width = 22 },
                        UI.Label {
                            text = tostring(evt.minute) .. "'",
                            fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 30,
                        },
                        UI.Label {
                            text = text, fontSize = 12,
                            color = evt.type == "goal" and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER,
                            flexGrow = 1, flexShrink = 1,
                        },
                    }
                })
            end
            table.insert(normalChildren, Theme.Card {
                children = {
                    Theme.Subtitle { text = "关键事件" },
                    UI.Panel { width = "100%", marginTop = 4, children = keyRows },
                }
            })
        end

        -- 比赛动态解说
        if #commentaryChildren > 0 then
            table.insert(normalChildren, Theme.Card {
                children = {
                    Theme.Subtitle { text = "比赛动态" },
                    UI.Panel { width = "100%", marginTop = 6, children = commentaryChildren },
                }
            })
        elseif currentMinute == 0 then
            table.insert(normalChildren, Theme.Card {
                children = {
                    UI.Panel {
                        width = "100%", alignItems = "center", paddingTop = 20, paddingBottom = 20,
                        children = {
                            UI.Label { text = "⚽", fontSize = 32 },
                            UI.Label { text = "比赛即将开始", fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY, marginTop = 8 },
                            UI.Label { text = "点击「开始」按钮开球", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
                        }
                    },
                }
            })
        end

        mainContent = UI.ScrollView {
            flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
            children = normalChildren,
        }
    end

    -- 操作按钮区域
    local actionButton
    if matchEnded then
        actionButton = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", marginTop = 8,
            children = {
                UI.Button {
                    text = "📊 查看报告", width = "48%", height = 46,
                    backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 10,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                    onClick = function()
                        -- 完成比赛：生成报告 + 应用结果
                        MatchLive.cleanup()
                        local MatchEngine = require("scripts/match/match_engine")
                        local report = MatchEngine.finishMatch(session, gameState, fixture)
                        Router.navigate("match_result", { report = report, fixture = fixture })
                    end,
                },
                UI.Button {
                    text = "返回主页", width = "48%", height = 46,
                    backgroundColor = {40, 48, 70, 255}, borderRadius = 10,
                    borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                    fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                    onClick = function()
                        -- 完成比赛：生成报告 + 应用结果
                        MatchLive.cleanup()
                        local MatchEngine = require("scripts/match/match_engine")
                        MatchEngine.finishMatch(session, gameState, fixture)
                        Router.navigate("dashboard")
                    end,
                },
            }
        }
    elseif displayMode == "normal" then
        local subsRemaining = session.subsRemaining
        local isPlaying = autoPlay.running
        local speedIdx = autoPlay.speed

        actionButton = UI.Panel {
            width = "100%", children = {
                -- 播放控制行
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between", marginTop = 4,
                    children = {
                        -- 播放/暂停按钮
                        UI.Button {
                            text = isPlaying and "⏸ 暂停" or "▶ 开始",
                            width = "30%", height = 42,
                            backgroundColor = isPlaying and {140, 60, 40, 255} or {46, 125, 50, 255},
                            borderRadius = 10,
                            fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            onClick = function()
                                if isPlaying then
                                    autoPlay.running = false
                                    autoPlay.pauseReason = nil
                                else
                                    autoPlay.running = true
                                    autoPlay.pauseReason = nil
                                    autoPlay.accumulator = 0
                                end
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                        -- 速度切换按钮
                        UI.Button {
                            text = SPEED_LABELS[speedIdx] or "▶",
                            width = "20%", height = 42,
                            backgroundColor = {35, 45, 70, 255}, borderRadius = 10,
                            borderWidth = 1, borderColor = {60, 75, 110, 255},
                            fontSize = 14, color = Theme.COLORS.ACCENT, fontWeight = "bold",
                            onClick = function()
                                autoPlay.speed = (autoPlay.speed % 3) + 1
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                        -- 模拟全场按钮
                        UI.Button {
                            text = "跳过全场", width = "28%", height = 42,
                            backgroundColor = {80, 60, 20, 255}, borderRadius = 10,
                            borderWidth = 1, borderColor = {120, 95, 40, 255},
                            fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            onClick = function()
                                autoPlay.running = false
                                local safety = 0
                                while not session:isFinished() and not session:needsPenalties() and safety < 30 do
                                    if session:isHalfTime() then
                                        session:stepMinutes(1)
                                    else
                                        session:stepMinutes(15)
                                    end
                                    safety = safety + 1
                                end
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "normal" })
                            end,
                        },
                    }
                },
                -- 暂停原因或常态提示
                UI.Panel {
                    width = "100%", marginTop = 6, alignItems = "center",
                    children = {
                        UI.Label {
                            text = autoPlay.pauseReason and ("⚡ " .. autoPlay.pauseReason) or (currentMinute > 0 and "随时可进行战术调整" or ""),
                            fontSize = 12,
                            color = autoPlay.pauseReason and Theme.COLORS.WARNING or Theme.COLORS.TEXT_MUTED,
                        },
                    }
                },
                -- 战术干预按钮行（常驻）
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", marginTop = 8,
                    children = {
                        UI.Button {
                            text = "换人(" .. tostring(subsRemaining) .. ")",
                            width = "31%", height = 40,
                            backgroundColor = subsRemaining > 0 and {55, 35, 110, 255} or {35, 40, 55, 255},
                            borderRadius = 10, fontSize = 12, fontWeight = "bold",
                            color = subsRemaining > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                            onClick = function()
                                autoPlay.running = false
                                if subsRemaining > 0 then
                                    Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "subs" })
                                end
                            end,
                        },
                        UI.Button {
                            text = "战术指示",
                            width = "31%", height = 40,
                            backgroundColor = {30, 70, 110, 255},
                            borderRadius = 10, fontSize = 12, fontWeight = "bold",
                            color = Theme.COLORS.TEXT_PRIMARY,
                            onClick = function()
                                autoPlay.running = false
                                Router.replaceWith("match_live", { session = session, fixture = fixture, mode = "tactics" })
                            end,
                        },
                        (function()
                            local lastTalk = session.lastTalkMinute or -15
                            local canTalk = (currentMinute - lastTalk) >= 15
                            return UI.Button {
                                text = canTalk and "喊话" or ("喊话(" .. tostring(15 - (currentMinute - lastTalk)) .. ")"),
                                width = "31%", height = 40,
                                backgroundColor = canTalk and {100, 60, 30, 255} or {35, 40, 55, 255},
                                borderRadius = 10, fontSize = 12, fontWeight = "bold",
                                color = canTalk and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                                onClick = function()
                                    if not canTalk then return end
                                    autoPlay.running = false
                                    session.lastTalkMinute = currentMinute
                                    -- 根据比分决定 context
                                    local pId
                                    if session._isWC then
                                        local WC = require("scripts/systems/world_cup")
                                        pId = WC._getPlayerNation(_G.gameState)
                                    else
                                        pId = _G.gameState and _G.gameState.playerTeamId
                                    end
                                    local isHome = pId == session.fixture.homeTeamId
                                    local myGoals = isHome and session.homeGoals or session.awayGoals
                                    local oppGoals = isHome and session.awayGoals or session.homeGoals
                                    local talkCtx = myGoals > oppGoals and "winning"
                                        or (myGoals < oppGoals and "losing" or "drawing")
                                    Router.navigate("team_talk", {
                                        context = talkCtx,
                                        returnTo = "match_live",
                                        returnParams = { session = session, fixture = fixture, mode = "normal" },
                                    })
                                end,
                            }
                        end)(),
                    }
                },
            }
        }
    end

    -- 构建页面
    local pageChildren = {}

    -- 进球者文字（按队伍分列）
    local homeGoalScorers = {}
    local awayGoalScorers = {}
    for _, evt in ipairs(goalEvents) do
        local player = evt.playerId and gameState.players[evt.playerId]
        local pName = player and player.lastName or player and player.displayName or ""
        local ogSuffix = evt.isOwnGoal and " (乌龙球)" or ""
        local entry = pName .. " " .. tostring(evt.minute) .. "'" .. ogSuffix
        if evt.teamId == session.fixture.homeTeamId then
            table.insert(homeGoalScorers, entry)
        else
            table.insert(awayGoalScorers, entry)
        end
    end

    -- 顶部比分板
    local scoreboardItems = {
        -- 状态指示（上半场/下半场/已结束）
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "center", alignItems = "center", marginBottom = 4,
            children = {
                (not matchEnded) and UI.Panel {
                    width = 8, height = 8, borderRadius = 4,
                    backgroundColor = Theme.COLORS.SECONDARY, marginRight = 6,
                } or nil,
                UI.Label {
                    text = statusText, fontSize = 12,
                    color = matchEnded and Theme.COLORS.TEXT_MUTED or Theme.COLORS.SECONDARY,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "  " .. tostring(currentMinute) .. "'", fontSize = 12,
                    color = Theme.COLORS.TEXT_SECONDARY,
                },
            }
        },
        -- 比分主区
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
            paddingTop = 8, paddingBottom = 8,
            children = {
                -- 主队
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, height = 70, alignItems = "flex-end", justifyContent = "center", paddingRight = 14,
                    children = {
                        homeTeam and UI.Panel {
                            width = 44, height = 44, marginBottom = 4,
                            children = { TeamIcon.create { team = homeTeam, size = 44 } },
                        } or nil,
                        UI.Label { text = homeName, fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", textAlign = "right", width = "100%", whiteSpace = "normal" },
                    }
                },
                -- 比分
                UI.Panel {
                    minWidth = 120, alignItems = "center", justifyContent = "center",
                    backgroundColor = {15, 19, 32, 200}, borderRadius = 10,
                    paddingTop = 8, paddingBottom = 8, paddingLeft = 14, paddingRight = 14,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", justifyContent = "center",
                            children = {
                                UI.Label {
                                    text = tostring(session.homeGoals),
                                    fontSize = 36, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                },
                                UI.Label {
                                    text = " - ",
                                    fontSize = 24, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold",
                                },
                                UI.Label {
                                    text = tostring(session.awayGoals),
                                    fontSize = 36, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                },
                            }
                        },
                    }
                },
                -- 客队
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, height = 70, alignItems = "flex-start", justifyContent = "center", paddingLeft = 14,
                    children = {
                        awayTeam and UI.Panel {
                            width = 44, height = 44, marginBottom = 4,
                            children = { TeamIcon.create { team = awayTeam, size = 44 } },
                        } or nil,
                        UI.Label { text = awayName, fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = "100%", whiteSpace = "normal" },
                    }
                },
            }
        },
        -- 进度条（始终显示，不要放在条件 nil 后面）
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
    -- 进球者（条件插入，避免 nil 空洞导致后续元素丢失）
    if #homeGoalScorers > 0 or #awayGoalScorers > 0 then
        -- 插在进度条之前（倒数第1个是进度条）
        table.insert(scoreboardItems, #scoreboardItems, UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "center", marginTop = 4,
            children = {
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, alignItems = "flex-end", paddingRight = 14,
                    children = {
                        UI.Label {
                            text = table.concat(homeGoalScorers, ", "),
                            fontSize = 10, color = Theme.COLORS.TEXT_SECONDARY, textAlign = "right",
                        },
                    }
                },
                UI.Panel { width = 110 },
                UI.Panel {
                    flexGrow = 1, flexBasis = 0, alignItems = "flex-start", paddingLeft = 14,
                    children = {
                        UI.Label {
                            text = table.concat(awayGoalScorers, ", "),
                            fontSize = 10, color = Theme.COLORS.TEXT_SECONDARY,
                        },
                    }
                },
            }
        })
    end
    table.insert(scoreboardItems, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "center", marginTop = 4,
        children = {
            UI.Label {
                text = "📋 ", fontSize = 10, width = 16,
            },
            UI.Label {
                text = "战术：" .. MatchLive._getInstructionLabel(session.tacticalInstruction),
                fontSize = 11, color = Theme.COLORS.ACCENT,
            },
        }
    })

    table.insert(pageChildren, UI.Panel {
        width = "100%",
        backgroundImage = "image/bg_match_scoreboard_v2_20260603083211.png",
        backgroundFit = "cover",
        imageTint = {50, 50, 70, 255},  -- 压暗，保证比分清晰
        paddingTop = 18, paddingBottom = 16, paddingLeft = 18, paddingRight = 18,
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
        width = "100%", height = "100%",
        backgroundImage = "image/bg_grass_texture_20260529082522.png",
        backgroundFit = "cover",
        imageTint = {30, 30, 38, 255},  -- 极度压暗，仅隐约可见纹理
        children = pageChildren,
    }
end

---------------------------------------------------------------------------
-- 换人面板 - 选择换下球员
---------------------------------------------------------------------------
local function _playerFitness(gameState, p)
    local gsPlayer = gameState and gameState.players[p.id]
    return (gsPlayer and gsPlayer.fitness) or p.fitness or 80
end

local function _fitnessColor(fitness)
    if fitness >= 80 then return Theme.COLORS.SECONDARY
    elseif fitness >= 60 then return Theme.COLORS.WARNING
    else return Theme.COLORS.DANGER end
end

local function _buildFitnessNameColumn(displayName, fitness)
    local fitnessColor = _fitnessColor(fitness)
    local barWidthPct = math.max(5, math.min(100, math.floor(fitness)))
    return UI.Panel {
        flexGrow = 1, flexShrink = 1,
        children = {
            UI.Label { text = displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
            UI.Panel {
                width = "100%", height = 4, backgroundColor = {40, 45, 60, 255},
                borderRadius = 2, marginTop = 3,
                children = {
                    UI.Panel {
                        width = tostring(barWidthPct) .. "%", height = 4,
                        backgroundColor = fitnessColor, borderRadius = 2,
                    },
                }
            },
        }
    }
end

local function _buildFitnessLabelColumn(fitness)
    local fitnessColor = _fitnessColor(fitness)
    return UI.Panel {
        width = 52, alignItems = "flex-end",
        children = {
            UI.Label {
                text = string.format("%.0f%%", fitness),
                fontSize = 11, color = fitnessColor, fontWeight = "bold",
            },
            UI.Label {
                text = "体力", fontSize = 9, color = Theme.COLORS.TEXT_MUTED,
            },
        }
    }
end

function MatchLive._buildSubstitutionPanel(gameState, session, fixture)
    -- 获取玩家球队的场上球员
    local playerTeamId
    if session._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        playerTeamId = WorldCup._getPlayerNation(gameState)
    else
        playerTeamId = gameState.playerTeamId
    end
    local isHome = playerTeamId == session.fixture.homeTeamId
    local context = isHome and session.homeContext or session.awayContext

    local onPitchRows = {}
    for _, p in ipairs(context.players) do
        if p.position ~= "GK" or #context.players > 1 then -- 不能换下唯一门将
            local fitness = _playerFitness(gameState, p)
            local posClr = Theme.posColor(p.position)
            table.insert(onPitchRows, UI.Panel {
                width = "100%", height = 44, flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                children = {
                    UI.Panel {
                        backgroundColor = {posClr[1], posClr[2], posClr[3], 50},
                        borderRadius = 3,
                        paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                        marginRight = 6, minWidth = 42,
                        children = {
                            UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = posClr, fontWeight = "bold" },
                        },
                    },
                    _buildFitnessNameColumn(p.displayName, fitness),
                    _buildFitnessLabelColumn(fitness),
                    UI.Button {
                        text = "换下", width = 48, height = 28, borderRadius = 6,
                        backgroundColor = Theme.COLORS.DANGER, fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                        marginLeft = 6,
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
        local bPosClr = Theme.posColor(p.position)
        local fitness = _playerFitness(gameState, p)
        table.insert(benchRows, UI.Panel {
            width = "100%", height = 44, flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Panel {
                    backgroundColor = {bPosClr[1], bPosClr[2], bPosClr[3], 50},
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                    marginRight = 6, minWidth = 42,
                    children = {
                        UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = bPosClr, fontWeight = "bold" },
                    },
                },
                _buildFitnessNameColumn(p.displayName, fitness),
                _buildFitnessLabelColumn(fitness),
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
        local spPosClr = Theme.posColor(p.position)
        local fitness = _playerFitness(gameState, p)
        table.insert(rows, UI.Panel {
            width = "100%", height = 44, flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Panel {
                    backgroundColor = {spPosClr[1], spPosClr[2], spPosClr[3], 50},
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                    marginRight = 6, minWidth = 42,
                    children = {
                        UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position, fontSize = 10, color = spPosClr, fontWeight = "bold" },
                    },
                },
                _buildFitnessNameColumn(p.displayName, fitness),
                _buildFitnessLabelColumn(fitness),
                UI.Button {
                    text = "换上", width = 48, height = 30, borderRadius = 6,
                    backgroundColor = Theme.COLORS.SECONDARY, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        -- 执行真实换人（影响后续模拟）
                        local subTeamId
                        if session._isWC then
                            local WC = require("scripts/systems/world_cup")
                            subTeamId = WC._getPlayerNation(gameState)
                        else
                            subTeamId = gameState.playerTeamId
                        end
                        session:applyCommand({
                            type = MatchSession.COMMAND.SUBSTITUTE,
                            offPlayerId = offId,
                            onPlayerId = p.id,
                            teamId = subTeamId,
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
                local tactTeamId
                if session._isWC then
                    local WC = require("scripts/systems/world_cup")
                    tactTeamId = WC._getPlayerNation(_G.gameState)
                else
                    tactTeamId = _G.gameState and _G.gameState.playerTeamId
                end
                session:applyCommand({
                    type = MatchSession.COMMAND.CHANGE_INSTRUCTION,
                    instruction = inst.key,
                    teamId = tactTeamId,
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
    local tIdx = evt.templateIdx

    if evt.type == "goal" then
        if evt.isOwnGoal then
            return string.format(pickTemplate(COMMENTARY.goal_own, tIdx), pName), Theme.COLORS.DANGER
        elseif evt.isPenalty then
            return string.format(pickTemplate(COMMENTARY.goal_penalty, tIdx), pName), Theme.COLORS.SECONDARY
        elseif evt.setPieceKind == "corner" then
            local text = string.format(pickTemplate(COMMENTARY.goal_corner, tIdx), pName)
            if evt.assistPlayerId and evt.assistPlayerId ~= evt.playerId then
                local assister = gameState.players[evt.assistPlayerId]
                if assister then text = text .. string.format("（%s 开出角球）", assister.displayName) end
            end
            return text, Theme.COLORS.SECONDARY
        elseif evt.setPieceKind == "free_kick" then
            local text = string.format(pickTemplate(COMMENTARY.goal_free_kick, tIdx), pName)
            if evt.assistPlayerId and evt.assistPlayerId ~= evt.playerId then
                local assister = gameState.players[evt.assistPlayerId]
                if assister then text = text .. string.format("（%s 主罚）", assister.displayName) end
            end
            return text, Theme.COLORS.SECONDARY
        elseif evt.assistPlayerId then
            local assister = gameState.players[evt.assistPlayerId]
            local aName = assister and assister.displayName or "队友"
            return string.format(pickTemplate(COMMENTARY.goal_assist, tIdx), aName, pName), Theme.COLORS.SECONDARY
        else
            return string.format(pickTemplate(COMMENTARY.goal, tIdx), pName), Theme.COLORS.SECONDARY
        end
    elseif evt.type == "yellow_card" then
        if evt.cardReasonName then
            return string.format(pickTemplate(COMMENTARY.yellow_card_reason, tIdx), pName, evt.cardReasonName), Theme.COLORS.WARNING
        end
        return string.format(pickTemplate(COMMENTARY.yellow_card, tIdx), pName), Theme.COLORS.WARNING
    elseif evt.type == "red_card" then
        if evt.cardReasonName then
            return string.format(pickTemplate(COMMENTARY.red_card_reason, tIdx), pName, evt.cardReasonName), Theme.COLORS.DANGER
        end
        return string.format(pickTemplate(COMMENTARY.red_card, tIdx), pName), Theme.COLORS.DANGER
    elseif evt.type == "injury" then
        if evt.injuryKindName then
            return string.format(pickTemplate(COMMENTARY.injury_detail, tIdx),
                pName, evt.injuryKindName, evt.injurySeverityName or "伤情待定",
                evt.injuryDays or 7), Theme.COLORS.DANGER
        end
        return string.format(pickTemplate(COMMENTARY.injury, tIdx), pName), Theme.COLORS.DANGER
    elseif evt.type == "save" then
        if evt.isPenalty then
            return string.format(pickTemplate(COMMENTARY.save_penalty, tIdx), pName), {100, 200, 180, 255}
        end
        return string.format(pickTemplate(COMMENTARY.save, tIdx), pName), {100, 200, 180, 255}
    elseif evt.type == "hit_post" then
        return string.format(pickTemplate(COMMENTARY.hit_post, tIdx), pName), {255, 180, 80, 255}
    elseif evt.type == "shot_off_target" then
        if evt.isPenalty then
            return string.format(pickTemplate(COMMENTARY.miss_penalty, tIdx), pName), {255, 180, 80, 255}
        end
        return string.format(pickTemplate(COMMENTARY.shot_off_target, tIdx), pName), Theme.COLORS.TEXT_SECONDARY
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
    if string.find(text, "进球") or string.find(text, "破门") or string.find(text, "得分") or string.find(text, "攻入") or string.find(text, "送入球门") then icon = "⚽"
    elseif string.find(text, "黄牌") then icon = "🟨"
    elseif string.find(text, "红牌") then icon = "🟥"
    elseif string.find(text, "受伤") or string.find(text, "离场") then icon = "🏥"
    elseif string.find(text, "扑救") or string.find(text, "没收") or string.find(text, "挡出") then icon = "🧤"
    elseif string.find(text, "门柱") or string.find(text, "立柱") or string.find(text, "横梁") then icon = "🥅"
    elseif string.find(text, "偏出") or string.find(text, "高出") or string.find(text, "滑门而出") then icon = "💨"
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
    local awayPct = 100 - homePct
    return UI.Panel {
        width = "100%", marginBottom = 10,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
                children = {
                    UI.Label {
                        text = tostring(homeVal) .. suffix, fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 40,
                    },
                    UI.Label {
                        text = label, fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        flexGrow = 1, textAlign = "center",
                    },
                    UI.Label {
                        text = tostring(awayVal) .. suffix, fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 40, textAlign = "right",
                    },
                }
            },
            UI.Panel {
                width = "100%", height = 6, flexDirection = "row", borderRadius = 3,
                backgroundColor = {20, 25, 40, 255},
                children = {
                    UI.Panel {
                        width = tostring(homePct) .. "%", height = 6,
                        backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 3,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Panel {
                        width = tostring(awayPct) .. "%", height = 6,
                        backgroundColor = {200, 80, 60, 255}, borderRadius = 3,
                    },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 自动推进 Update 回调（全局函数，由引擎事件调用）
---------------------------------------------------------------------------
function HandleMatchAutoAdvance(eventType, eventData)
    if not autoPlay.running then return end

    local session = MatchLive._currentSession
    local fixture = MatchLive._currentFixture
    local params = MatchLive._currentParams
    if not session or session:isFinished() or session:isHalfTime() or session:needsPenalties() then
        autoPlay.running = false
        return
    end

    local dt = eventData["TimeStep"]:GetFloat()
    local interval = SPEED_INTERVALS[autoPlay.speed] or 1.0
    autoPlay.accumulator = autoPlay.accumulator + dt

    if autoPlay.accumulator >= interval then
        autoPlay.accumulator = autoPlay.accumulator - interval

        -- 步进 1 分钟
        local newEvents = session:stepMinutes(1)

        -- 检查是否有关键事件需要暂停
        local pauseEvent = nil
        for _, evt in ipairs(newEvents) do
            if PAUSE_EVENTS[evt.type] then
                pauseEvent = evt
                break
            end
        end

        -- 检查半场/结束/点球
        if session:isFinished() or session:isHalfTime() or session:needsPenalties() then
            autoPlay.running = false
            AudioManager.whistle()
        elseif pauseEvent then
            autoPlay.running = false
            if pauseEvent.type == "goal" then
                AudioManager.cheer()
                autoPlay.pauseReason = "进球！比赛暂停，可进行战术调整"
            elseif pauseEvent.type == "red_card" then
                AudioManager.whistle()
                autoPlay.pauseReason = "红牌！比赛暂停，可进行换人调整"
            elseif pauseEvent.type == "injury" then
                autoPlay.pauseReason = "球员受伤！可进行换人"
            end
        end

        -- 刷新页面
        Router.replaceWith("match_live", { session = session, fixture = fixture, mode = params and params.mode or "normal" })
    end
end

--- 清理自动推进状态（离开比赛页面时调用）
function MatchLive.cleanup()
    autoPlay.running = false
    autoPlay.accumulator = 0
    autoPlay.pauseReason = nil
    autoPlay.speed = 1
    MatchLive._currentSession = nil
    MatchLive._currentFixture = nil
    MatchLive._currentParams = nil
    if MatchLive._updateSubscribed then
        UnsubscribeFromEvent("Update")
        MatchLive._updateSubscribed = false
    end
    -- 停止球场氛围音
    AudioManager.stopCrowdAmbient()
end

return MatchLive
