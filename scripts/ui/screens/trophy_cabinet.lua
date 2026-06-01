--- 荣誉陈列室 - 展示玩家球队获得的所有奖杯和经理生涯统计
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local RecordsManager = require("scripts/systems/records_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ChampionshipPopup = require("scripts/ui/components/championship_popup")

local COLORS = Theme.COLORS

local TrophyCabinet = {}

-- 模块级状态
local _activeTab = "trophies"

------------------------------------------------------
-- 奖杯图标
------------------------------------------------------

local TROPHY_ICONS = {
    league = "🏆",
    ucl = "⭐",
    worldcup = "🌍",
}

local TROPHY_COLORS = {
    league = {212, 175, 55, 255},   -- 金色
    ucl = {0, 82, 155, 255},        -- UCL 蓝
    worldcup = {139, 69, 19, 255},  -- 棕金
}

------------------------------------------------------
-- Tab 1: 奖杯展示
------------------------------------------------------

local function buildTrophiesTab(gameState)
    local trophies = RecordsManager.getTrophies(gameState)
    local counts = RecordsManager.getTrophyCount(gameState)

    if counts.total == 0 then
        return { Theme.Card { children = {
            UI.Panel {
                width = "100%", alignItems = "center", paddingVertical = 30,
                children = {
                    UI.Label { text = "🏆", fontSize = 48, marginBottom = 10 },
                    UI.Label { text = "暂无奖杯", fontSize = 14, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = "带领球队赢得冠军后将在此展示", fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 4 },
                }
            }
        }}}
    end

    local cards = {}

    -- 汇总横幅
    local summaryItems = {}
    if counts.league > 0 then
        table.insert(summaryItems, UI.Panel {
            alignItems = "center", marginRight = 20,
            children = {
                UI.Label { text = "🏆", fontSize = 28 },
                UI.Label { text = tostring(counts.league), fontSize = 18, fontWeight = "bold", color = TROPHY_COLORS.league, marginTop = 2 },
                UI.Label { text = "联赛冠军", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginTop = 1 },
            }
        })
    end
    if counts.ucl > 0 then
        table.insert(summaryItems, UI.Panel {
            alignItems = "center", marginRight = 20,
            children = {
                UI.Label { text = "⭐", fontSize = 28 },
                UI.Label { text = tostring(counts.ucl), fontSize = 18, fontWeight = "bold", color = TROPHY_COLORS.ucl, marginTop = 2 },
                UI.Label { text = "欧冠冠军", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginTop = 1 },
            }
        })
    end
    if counts.worldcup > 0 then
        table.insert(summaryItems, UI.Panel {
            alignItems = "center",
            children = {
                UI.Label { text = "🌍", fontSize = 28 },
                UI.Label { text = tostring(counts.worldcup), fontSize = 18, fontWeight = "bold", color = TROPHY_COLORS.worldcup, marginTop = 2 },
                UI.Label { text = "世界杯", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginTop = 1 },
            }
        })
    end

    table.insert(cards, Theme.HeroCard {
        accentColor = {212, 175, 55, 255},
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "center", alignItems = "center",
                paddingVertical = 10,
                children = summaryItems,
            }
        }
    })

    -- 奖杯列表（按赛季倒序）
    local rows = {}
    for i = #trophies, 1, -1 do
        local t = trophies[i]
        local icon = TROPHY_ICONS[t.competition] or "🏆"
        local color = TROPHY_COLORS[t.competition] or COLORS.WARNING

        local detailText = ""
        if t.points then
            detailText = tostring(t.points) .. "分"
        end

        local trophyData = t
        table.insert(rows, UI.Panel {
            width = "100%", height = 50, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 10,
            borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = function()
                ChampionshipPopup.show({
                    competition = trophyData.competition,
                    competitionName = trophyData.competitionName,
                    teamId = trophyData.teamId,
                    teamName = trophyData.teamName,
                    season = trophyData.season,
                    stats = trophyData,
                })
            end,
            children = {
                UI.Label { text = icon, fontSize = 22, width = 36 },
                UI.Panel { flex = 1, children = {
                    UI.Label {
                        text = (t.competitionName or "冠军"),
                        fontSize = 13, fontWeight = "bold", color = color,
                    },
                    UI.Label {
                        text = string.format("第%d赛季 (%d-%d)", t.season or 0, t.year or 0, (t.year or 0) + 1),
                        fontSize = 10, color = COLORS.TEXT_SECONDARY, marginTop = 1,
                    },
                }},
                detailText ~= "" and UI.Label { text = detailText, fontSize = 11, color = COLORS.TEXT_MUTED } or nil,
            }
        })
    end

    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = string.format("全部奖杯 (%d)", counts.total) },
        table.unpack(rows),
    }})

    return cards
end

------------------------------------------------------
-- Tab 2: 经理生涯统计
------------------------------------------------------

local function buildManagerTab(gameState)
    local mr = RecordsManager.getManagerRecords(gameState)
    local cards = {}

    -- 核心数据
    local function infoRow(label, value, valueColor)
        return UI.Panel {
            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 10, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = label, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = tostring(value), fontSize = 13, fontWeight = "bold", color = valueColor or COLORS.TEXT_PRIMARY },
            }
        }
    end

    -- 执教概览
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "执教概览" },
        infoRow("执教赛季", mr.totalSeasons),
        infoRow("联赛冠军", mr.leagueTitles, TROPHY_COLORS.league),
        infoRow("欧冠冠军", mr.uclTitles, TROPHY_COLORS.ucl),
        infoRow("世界杯冠军", mr.worldCupTitles, TROPHY_COLORS.worldcup),
        infoRow("最佳联赛排名", mr.bestLeagueFinish < 999 and ("第" .. mr.bestLeagueFinish .. "名") or "-"),
    }})

    -- 比赛数据
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "比赛数据" },
        infoRow("总比赛", mr.totalMatches),
        infoRow("胜/平/负", string.format("%d / %d / %d", mr.totalWins, mr.totalDraws, mr.totalLosses)),
        infoRow("胜率", string.format("%.1f%%", mr.winRate)),
        infoRow("最长连胜", mr.longestWinStreak .. "场"),
        infoRow("最长不败", mr.longestUnbeatenStreak .. "场"),
    }})

    -- 经营数据
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "经营数据" },
        infoRow("转会投入", FinanceManager.formatMoney(mr.totalSpent)),
        infoRow("转会收入", FinanceManager.formatMoney(mr.totalEarned)),
        infoRow("净投入", FinanceManager.formatMoney(mr.totalSpent - mr.totalEarned)),
        infoRow("青训提拔", tostring(mr.youthPromoted) .. "人"),
    }})

    return cards
end

------------------------------------------------------
-- Tab 3: 联赛 & 球员记录
------------------------------------------------------

local function buildRecordsTab(gameState)
    local lr = RecordsManager.getLeagueRecords(gameState)
    local pr = RecordsManager.getPlayerRecords(gameState)
    local cards = {}

    local function recordRow(label, data, formatFn)
        if not data then
            return UI.Panel {
                width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 10, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = label, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = "-", fontSize = 12, color = COLORS.TEXT_MUTED },
                }
            }
        end
        return UI.Panel {
            width = "100%", minHeight = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 10, paddingVertical = 4,
            borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = label, width = 90, fontSize = 11, color = COLORS.TEXT_SECONDARY },
                UI.Panel { flex = 1, children = {
                    UI.Label { text = formatFn(data), fontSize = 12, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
                }},
            }
        }
    end

    -- 联赛记录
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "联赛记录" },
        recordRow("最高积分", lr.highestPoints, function(d)
            return string.format("%s - %d分 (第%d赛季)", d.teamName, d.points, d.season)
        end),
        recordRow("最多胜场", lr.mostWins, function(d)
            return string.format("%s - %d胜 (第%d赛季)", d.teamName, d.wins, d.season)
        end),
        recordRow("最少失球", lr.fewestGoalsConceded, function(d)
            return string.format("%s - %d球 (第%d赛季)", d.teamName, d.goalsAgainst, d.season)
        end),
        recordRow("连续冠军", lr.consecutiveChampionships, function(d)
            return string.format("%s - %d连冠 (第%d-%d赛季)", d.teamName, d.count, d.startSeason, d.endSeason)
        end),
    }})

    -- 球员单赛季记录
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "球员单赛季记录" },
        recordRow("最多进球", pr.singleSeasonGoals, function(d)
            return string.format("%s - %d球 (%s, 第%d赛季)", d.playerName, d.goals, d.teamName, d.season)
        end),
        recordRow("最多助攻", pr.singleSeasonAssists, function(d)
            return string.format("%s - %d次 (%s, 第%d赛季)", d.playerName, d.assists, d.teamName, d.season)
        end),
        recordRow("最高评分", pr.singleSeasonRating, function(d)
            return string.format("%s - %.1f分 (%s, 第%d赛季)", d.playerName, d.rating, d.teamName, d.season)
        end),
    }})

    -- 球员历史累计 Top5
    if pr.allTimeGoals and #pr.allTimeGoals > 0 then
        local goalRows = {}
        for i = 1, math.min(5, #pr.allTimeGoals) do
            local entry = pr.allTimeGoals[i]
            table.insert(goalRows, UI.Panel {
                width = "100%", height = 30, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 10, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 11, color = COLORS.TEXT_MUTED },
                    UI.Label { text = entry.playerName, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = tostring(entry.value) .. "球", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                }
            })
        end
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "历史总射手榜 Top5" },
            table.unpack(goalRows),
        }})
    end

    if pr.allTimeAssists and #pr.allTimeAssists > 0 then
        local assistRows = {}
        for i = 1, math.min(5, #pr.allTimeAssists) do
            local entry = pr.allTimeAssists[i]
            table.insert(assistRows, UI.Panel {
                width = "100%", height = 30, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 10, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 11, color = COLORS.TEXT_MUTED },
                    UI.Label { text = entry.playerName, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = tostring(entry.value) .. "次", fontSize = 12, fontWeight = "bold", color = COLORS.ACCENT },
                }
            })
        end
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "历史总助攻榜 Top5" },
            table.unpack(assistRows),
        }})
    end

    return cards
end

------------------------------------------------------
-- 主入口
------------------------------------------------------

function TrophyCabinet.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", children = {} }
    end

    RecordsManager._ensureData(gameState)

    local tabs = {
        { key = "trophies", label = "奖杯" },
        { key = "manager",  label = "生涯统计" },
        { key = "records",  label = "历史记录" },
    }

    -- 标签栏
    local tabButtons = {}
    for _, t in ipairs(tabs) do
        local isActive = (_activeTab == t.key)
        table.insert(tabButtons, UI.Panel {
            flex = 1, height = 38, justifyContent = "center", alignItems = "center",
            borderBottomWidth = isActive and 2 or 0,
            borderColor = isActive and COLORS.PRIMARY or COLORS.TRANSPARENT,
            onClick = function()
                _activeTab = t.key
                Router.replaceWith("trophy_cabinet", params)
            end,
            children = {
                UI.Label {
                    text = t.label, fontSize = 13,
                    fontWeight = isActive and "bold" or "normal",
                    color = isActive and COLORS.PRIMARY or COLORS.TEXT_SECONDARY,
                }
            }
        })
    end

    -- 标签内容
    local tabContent
    if _activeTab == "trophies" then
        tabContent = buildTrophiesTab(gameState)
    elseif _activeTab == "manager" then
        tabContent = buildManagerTab(gameState)
    elseif _activeTab == "records" then
        tabContent = buildRecordsTab(gameState)
    else
        tabContent = buildTrophiesTab(gameState)
    end

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = COLORS.BG_DARK,
        children = {
            Theme.TopBar { children = {
                UI.Panel { width = 60, height = 32, justifyContent = "center", onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } } },
                UI.Label { text = "荣誉陈列室", fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
                UI.Panel { width = 60 },
            }},
            -- 标签栏
            UI.Panel {
                width = "100%", height = 38, flexDirection = "row",
                backgroundColor = COLORS.BG_HEADER,
                borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = tabButtons,
            },
            -- 内容
            UI.ScrollView {
                width = "100%", flex = 1,
                children = {
                    UI.Panel { width = "100%", padding = 12, children = tabContent }
                }
            },
        }
    }
end

return TrophyCabinet
