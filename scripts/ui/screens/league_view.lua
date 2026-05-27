-- ui/screens/league_view.lua
-- 联赛积分榜和赛程页面（支持切换查看五大联赛 + 欧冠 + 世界杯）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")

local LeagueView = {}

-- 当前查看的联赛key（模块级状态），"UCL" 表示欧冠，"WC" 表示世界杯
local currentLeagueKey = nil

function LeagueView.create(params)
    local gameState = _G.gameState
    if not gameState or not gameState.leagues then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    -- 如果传入了 tab 参数，切换到对应标签
    if params and params.tab then
        currentLeagueKey = params.tab
    end

    -- 如果没有选过联赛，默认显示玩家所在联赛
    if not currentLeagueKey or (currentLeagueKey ~= "UCL" and currentLeagueKey ~= "WC" and not gameState.leagues[currentLeagueKey]) then
        currentLeagueKey = gameState.playerLeagueId
        -- 兜底：取第一个联赛
        if not currentLeagueKey then
            for key, _ in pairs(gameState.leagues) do
                currentLeagueKey = key
                break
            end
        end
    end

    -- 构建联赛切换按钮（含欧冠 + 世界杯）
    local leagueTabs = {}
    local leagueOrder = {"EPL", "LaLiga", "SerieA", "Bundesliga", "Ligue1", "UCL", "WC"}
    for _, key in ipairs(leagueOrder) do
        local hasData = false
        local tabName = key
        if key == "UCL" then
            hasData = gameState.championsLeague ~= nil
            tabName = "欧冠"
        elseif key == "WC" then
            hasData = gameState.worldCup ~= nil
            tabName = "世界杯"
        else
            hasData = gameState.leagues[key] ~= nil
            local lg = gameState.leagues[key]
            if lg then tabName = lg.name end
        end
        if hasData then
            local isActive = key == currentLeagueKey
            table.insert(leagueTabs, UI.Button {
                text = tabName,
                height = 30,
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_HEADER,
                fontSize = 12,
                color = isActive and {255, 255, 255, 255} or Theme.COLORS.TEXT_MUTED,
                borderRadius = 4,
                marginRight = 4,
                onClick = function()
                    currentLeagueKey = key
                    Router.replaceWith("league")
                end,
            })
        end
    end

    -- 如果当前选中欧冠，显示欧冠专用视图
    if currentLeagueKey == "UCL" then
        return LeagueView._createUCLView(gameState, leagueTabs)
    end

    -- 如果当前选中世界杯，显示世界杯专用视图
    if currentLeagueKey == "WC" then
        return LeagueView._createWCView(gameState, leagueTabs)
    end

    -- 联赛视图
    local league = gameState.leagues[currentLeagueKey]
    if not league then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    local sorted = league:getSortedStandings()

    -- 构建积分榜行
    local standingRows = {}
    for i, s in ipairs(sorted) do
        local team = gameState.teams[s.teamId]
        local isPlayer = s.teamId == gameState.playerTeamId
        table.insert(standingRows, UI.Panel {
            width = "100%",
            height = 40,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isPlayer and {26, 51, 89, 255} or {0, 0, 0, 0},
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label { text = tostring(i), fontSize = 13, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                UI.Label { text = team and team.shortName or "???", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 44 },
                UI.Label { text = team and team.name or "", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
                UI.Label { text = tostring(s.played), fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                UI.Label { text = tostring(s.wins), fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                UI.Label { text = tostring(s.draws), fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                UI.Label { text = tostring(s.losses), fontSize = 12, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                UI.Label { text = tostring(s.goalDifference), fontSize = 12, color = s.goalDifference >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER, width = 28 },
                UI.Label { text = tostring(s.points), fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 28 },
            },
        })
    end

    -- 最近比赛结果（当前查看联赛的）
    local recentResults = {}
    local resultCount = 0
    for i = #league.fixtures, 1, -1 do
        local f = league.fixtures[i]
        if f.status == "finished" then
            local home = gameState.teams[f.homeTeamId]
            local away = gameState.teams[f.awayTeamId]
            if home and away then
                local isPlayer = f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId
                table.insert(recentResults, UI.Panel {
                    width = "100%", height = 36,
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = 10, paddingRight = 10,
                    backgroundColor = isPlayer and {26, 51, 89, 255} or {0, 0, 0, 0},
                    borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                    children = {
                        UI.Label { text = home.shortName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, width = 40 },
                        UI.Label {
                            text = f.homeGoals .. " - " .. f.awayGoals,
                            fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold", width = 50, textAlign = "center",
                        },
                        UI.Label { text = away.shortName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, width = 40 },
                        UI.Label { text = string.format("%d/%d", f.date.month, f.date.day), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1, textAlign = "right" },
                    },
                })
                resultCount = resultCount + 1
                if resultCount >= 10 then break end
            end
        end
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.navigate("dashboard") end,
                    },
                    UI.Label {
                        text = league.name .. " " .. league.season,
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Panel { width = 50 },
                }
            },

            -- 联赛切换标签栏
            UI.Panel {
                width = "100%",
                height = 42,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 10,
                paddingRight = 10,
                paddingTop = 4,
                paddingBottom = 4,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = leagueTabs,
            },

            -- 积分榜表头
            UI.Panel {
                width = "100%", height = 28,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Label { text = "#", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                    UI.Label { text = "", width = 44, fontSize = 10 },
                    UI.Label { text = "球队", flexGrow = 1, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "场", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                    UI.Label { text = "胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "平", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "负", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "净胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                    UI.Label { text = "积分", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                }
            },

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = {
                    -- 积分榜
                    UI.Panel { width = "100%", children = standingRows },

                    -- 分隔
                    UI.Panel {
                        width = "100%", paddingLeft = 14, paddingTop = 14, paddingBottom = 6,
                        children = {
                            Theme.Title { text = "最近比赛结果", fontSize = 15 },
                        }
                    },

                    -- 最近结果
                    UI.Panel { width = "100%", children = recentResults },
                }
            },

            -- 底部导航
            Theme.MainNav("league"),
        }
    }
end

------------------------------------------------------
-- 欧冠专用视图
------------------------------------------------------

function LeagueView._createUCLView(gameState, leagueTabs)
    local ucl = gameState.championsLeague
    if not ucl then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    -- 阶段显示文字
    local phaseNames = {
        not_started = "未开始",
        group = "小组赛",
        r16 = "1/8 决赛",
        qf = "1/4 决赛",
        sf = "半决赛",
        final = "决赛",
        completed = "已结束",
    }
    local phaseText = phaseNames[ucl.phase] or ucl.phase

    -- 构建内容
    local contentChildren = {}

    -- 小组赛积分榜
    if ucl.groups and next(ucl.groups) then
        local groupNames = {}
        for name, _ in pairs(ucl.groups) do
            table.insert(groupNames, name)
        end
        table.sort(groupNames)

        for _, groupName in ipairs(groupNames) do
            local sorted = ucl:getGroupSortedStandings(groupName)

            -- 组名标题
            table.insert(contentChildren, UI.Panel {
                width = "100%", paddingLeft = 10, paddingTop = 10, paddingBottom = 4,
                children = {
                    UI.Label { text = groupName .. " 组", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                }
            })

            -- 表头
            table.insert(contentChildren, UI.Panel {
                width = "100%", height = 24,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Label { text = "球队", flexGrow = 1, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "场", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                    UI.Label { text = "胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "平", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "负", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "净胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                    UI.Label { text = "积分", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                }
            })

            -- 积分行
            for i, s in ipairs(sorted) do
                local team = gameState.teams[s.teamId]
                local isPlayer = s.teamId == gameState.playerTeamId
                local isQualified = i <= 2  -- 前2名出线

                table.insert(contentChildren, UI.Panel {
                    width = "100%", height = 34,
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = 10, paddingRight = 10,
                    backgroundColor = isPlayer and {26, 51, 89, 255}
                                     or (isQualified and {20, 60, 20, 255} or {0, 0, 0, 0}),
                    borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                    children = {
                        UI.Label { text = team and team.shortName or "???", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1 },
                        UI.Label { text = tostring(s.played), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                        UI.Label { text = tostring(s.wins), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.draws), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.losses), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.goalDifference), fontSize = 11, color = s.goalDifference >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER, width = 28 },
                        UI.Label { text = tostring(s.points), fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 28 },
                    },
                })
            end
        end
    end

    -- 淘汰赛结果
    local knockoutPhases = {
        {key = "r16", name = "1/8 决赛"},
        {key = "qf", name = "1/4 决赛"},
        {key = "sf", name = "半决赛"},
        {key = "final", name = "决赛"},
    }

    for _, kp in ipairs(knockoutPhases) do
        local fixtures = ucl.knockout[kp.key]
        if fixtures and #fixtures > 0 then
            -- 标题
            table.insert(contentChildren, UI.Panel {
                width = "100%", paddingLeft = 10, paddingTop = 14, paddingBottom = 4,
                children = {
                    UI.Label { text = kp.name, fontSize = 14, color = Theme.COLORS.PRIMARY, fontWeight = "bold" },
                }
            })

            if kp.key == "final" then
                -- 决赛单场
                local f = fixtures[1]
                if f then
                    local home = gameState.teams[f.homeTeamId]
                    local away = gameState.teams[f.awayTeamId]
                    local scoreText = f.status == "finished"
                        and (f.homeGoals .. " - " .. f.awayGoals)
                        or "vs"
                    local isPlayer = f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId
                    table.insert(contentChildren, UI.Panel {
                        width = "100%", height = 40,
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = isPlayer and {26, 51, 89, 255} or {0, 0, 0, 0},
                        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                        children = {
                            UI.Label { text = home and home.shortName or "?", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 50 },
                            UI.Label { text = scoreText, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1, textAlign = "center" },
                            UI.Label { text = away and away.shortName or "?", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 50, textAlign = "right" },
                        },
                    })
                end
            else
                -- 两回合制：按 matchIndex 分组展示
                local pairings = {}
                for _, f in ipairs(fixtures) do
                    if not pairings[f.matchIndex] then
                        pairings[f.matchIndex] = {}
                    end
                    table.insert(pairings[f.matchIndex], f)
                end

                local pairKeys = {}
                for k, _ in pairs(pairings) do table.insert(pairKeys, k) end
                table.sort(pairKeys)

                for _, pairIdx in ipairs(pairKeys) do
                    local pair = pairings[pairIdx]
                    local leg1, leg2
                    for _, f in ipairs(pair) do
                        if f.leg == 1 then leg1 = f else leg2 = f end
                    end

                    if leg1 then
                        local team1 = gameState.teams[leg1.homeTeamId]
                        local team2 = gameState.teams[leg1.awayTeamId]
                        local isPlayer = leg1.homeTeamId == gameState.playerTeamId or leg1.awayTeamId == gameState.playerTeamId

                        -- 比分文字
                        local leg1Score = leg1.status == "finished" and (leg1.homeGoals .. "-" .. leg1.awayGoals) or "-"
                        local leg2Score = leg2 and leg2.status == "finished" and (leg2.homeGoals .. "-" .. leg2.awayGoals) or "-"

                        -- 总比分
                        local aggText = ""
                        if leg1.status == "finished" and leg2 and leg2.status == "finished" then
                            local agg1 = leg1.homeGoals + leg2.awayGoals
                            local agg2 = leg1.awayGoals + leg2.homeGoals
                            aggText = string.format("(%d-%d)", agg1, agg2)
                        end

                        table.insert(contentChildren, UI.Panel {
                            width = "100%", height = 38,
                            flexDirection = "row", alignItems = "center",
                            paddingLeft = 10, paddingRight = 10,
                            backgroundColor = isPlayer and {26, 51, 89, 255} or {0, 0, 0, 0},
                            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                            children = {
                                UI.Label { text = team1 and team1.shortName or "?", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 44 },
                                UI.Label { text = leg1Score, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 30, textAlign = "center" },
                                UI.Label { text = leg2Score, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 30, textAlign = "center" },
                                UI.Label { text = aggText, fontSize = 11, color = Theme.COLORS.SECONDARY, width = 40, textAlign = "center" },
                                UI.Label { text = team2 and team2.shortName or "?", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1, textAlign = "right" },
                            },
                        })
                    end
                end
            end
        end
    end

    -- 冠军显示
    if ucl.champion then
        local champion = gameState.teams[ucl.champion]
        table.insert(contentChildren, UI.Panel {
            width = "100%", paddingTop = 16, paddingBottom = 16,
            alignItems = "center",
            children = {
                UI.Label { text = "冠军", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = champion and champion.name or "?", fontSize = 18, color = {255, 215, 0, 255}, fontWeight = "bold" },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.navigate("dashboard") end,
                    },
                    UI.Label {
                        text = "欧冠 " .. ucl.season .. "-" .. (ucl.season + 1) .. " (" .. phaseText .. ")",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Panel { width = 50 },
                }
            },

            -- 联赛切换标签栏
            UI.Panel {
                width = "100%", height = 42,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = leagueTabs,
            },

            -- 内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = contentChildren,
            },

            -- 底部导航
            Theme.MainNav("league"),
        }
    }
end

------------------------------------------------------
-- 世界杯专用视图
------------------------------------------------------

function LeagueView._createWCView(gameState, leagueTabs)
    local WorldCupSystem = require("scripts/systems/world_cup")
    local wc = gameState.worldCup
    if not wc then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK }
    end

    -- 阶段显示文字
    local phaseNames = {
        not_started = "未开始",
        group = "小组赛",
        r16 = "1/8 决赛",
        qf = "1/4 决赛",
        sf = "半决赛",
        final = "决赛",
        completed = "已结束",
    }
    local phaseText = phaseNames[wc.phase] or wc.phase

    local contentChildren = {}

    -- 小组赛积分榜
    if wc.groups and next(wc.groups) then
        local groupNames = {}
        for name, _ in pairs(wc.groups) do
            table.insert(groupNames, name)
        end
        table.sort(groupNames)

        for _, groupName in ipairs(groupNames) do
            local sorted = wc:getGroupSortedStandings(groupName)

            table.insert(contentChildren, UI.Panel {
                width = "100%", paddingLeft = 10, paddingTop = 10, paddingBottom = 4,
                children = {
                    UI.Label { text = groupName .. " 组", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                }
            })

            -- 表头
            table.insert(contentChildren, UI.Panel {
                width = "100%", height = 24,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Label { text = "国家", flexGrow = 1, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "场", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                    UI.Label { text = "胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "平", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "负", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                    UI.Label { text = "净胜", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                    UI.Label { text = "积分", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 28 },
                }
            })

            for i, s in ipairs(sorted) do
                local nationName = WorldCupSystem._getNationName(s.teamId)
                local isQualified = i <= 2

                table.insert(contentChildren, UI.Panel {
                    width = "100%", height = 34,
                    flexDirection = "row", alignItems = "center",
                    paddingLeft = 10, paddingRight = 10,
                    backgroundColor = isQualified and {20, 60, 20, 255} or {0, 0, 0, 0},
                    borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                    children = {
                        UI.Label { text = nationName, fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1 },
                        UI.Label { text = tostring(s.played), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 24 },
                        UI.Label { text = tostring(s.wins), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.draws), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.losses), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
                        UI.Label { text = tostring(s.goalDifference), fontSize = 11, color = s.goalDifference >= 0 and Theme.COLORS.SECONDARY or Theme.COLORS.DANGER, width = 28 },
                        UI.Label { text = tostring(s.points), fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 28 },
                    },
                })
            end
        end
    end

    -- 淘汰赛对阵
    local knockoutPhases = {
        {key = "r16", name = "1/8 决赛"},
        {key = "qf", name = "1/4 决赛"},
        {key = "sf", name = "半决赛"},
        {key = "final", name = "决赛"},
    }

    for _, kp in ipairs(knockoutPhases) do
        local fixtures = wc.knockout[kp.key]
        if fixtures and #fixtures > 0 then
            table.insert(contentChildren, UI.Panel {
                width = "100%", paddingLeft = 10, paddingTop = 14, paddingBottom = 4,
                children = {
                    UI.Label { text = kp.name, fontSize = 14, color = {255, 200, 50, 255}, fontWeight = "bold" },
                }
            })

            -- 世界杯淘汰赛为单场制，只显示 leg==1 的比赛
            for _, f in ipairs(fixtures) do
                if f.leg == 1 then
                    local homeName = WorldCupSystem._getNationName(f.homeTeamId)
                    local awayName = WorldCupSystem._getNationName(f.awayTeamId)
                    local scoreText = f.status == "finished"
                        and (f.homeGoals .. " - " .. f.awayGoals)
                        or "vs"

                    table.insert(contentChildren, UI.Panel {
                        width = "100%", height = 38,
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 10, paddingRight = 10,
                        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
                        children = {
                            UI.Label { text = homeName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 70 },
                            UI.Label { text = scoreText, fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1, textAlign = "center" },
                            UI.Label { text = awayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 70, textAlign = "right" },
                        },
                    })
                end
            end
        end
    end

    -- 冠军显示
    if wc.champion then
        local championName = WorldCupSystem._getNationName(wc.champion)
        table.insert(contentChildren, UI.Panel {
            width = "100%", paddingTop = 16, paddingBottom = 16,
            alignItems = "center",
            children = {
                UI.Label { text = "世界杯冠军", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                UI.Label { text = championName, fontSize = 20, color = {255, 215, 0, 255}, fontWeight = "bold" },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.navigate("dashboard") end,
                    },
                    UI.Label {
                        text = "世界杯 " .. wc.season .. " (" .. phaseText .. ")",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    UI.Panel { width = 50 },
                }
            },

            -- 联赛切换标签栏
            UI.Panel {
                width = "100%", height = 42,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 10, paddingRight = 10,
                paddingTop = 4, paddingBottom = 4,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = leagueTabs,
            },

            -- 内容区
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                children = contentChildren,
            },

            -- 底部导航
            Theme.MainNav("league"),
        }
    }
end

return LeagueView
