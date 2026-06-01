--- 名人堂页 - 历届冠军、金靴、最佳球员、联赛/球员记录
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local HistoryManager = require("scripts/systems/history_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local RecordsManager = require("scripts/systems/records_manager")

local COLORS = Theme.COLORS

local HallOfFame = {}

-- 模块级状态
local _activeTab = "champions"

------------------------------------------------------------
-- 冠军榜
------------------------------------------------------------

local function buildChampionsTab(gameState)
    local champions = HistoryManager.getChampionsList(gameState)
    if #champions == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无冠军记录（完成第一个赛季后解锁）", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local cards = {}
    -- 按赛季倒序
    for i = #champions, 1, -1 do
        local sc = champions[i]
        local rows = {}
        for leagueKey, info in pairs(sc.leagues) do
            table.insert(rows, UI.Panel {
                width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = info.teamId and function()
                    Router.navigate("team_detail", { teamId = info.teamId })
                end or nil,
                children = {
                    UI.Label { text = info.leagueName or leagueKey, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = info.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                    UI.Label { text = tostring(info.points or 0) .. "分", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
                }
            })
        end
        if #rows > 0 then
            table.insert(cards, Theme.Card { children = {
                Theme.Subtitle { text = "第 " .. tostring(sc.season) .. " 赛季 (" .. tostring(sc.year or "?") .. ")" },
                table.unpack(rows)
            }})
        end
    end

    return cards
end

------------------------------------------------------------
-- 奖项榜
------------------------------------------------------------

local function buildAwardsTab(gameState)
    local allAwards = gameState._seasonAwards
    if not allAwards or #allAwards == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无奖项记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local cards = {}
    for i = #allAwards, 1, -1 do
        local seasonAward = allAwards[i]
        local rows = {}

        for leagueKey, la in pairs(seasonAward.leagues or {}) do
            if la.goldenBoot then
                table.insert(rows, HallOfFame._awardRow("金靴", la.goldenBoot.playerName, tostring(la.goldenBoot.goals or 0) .. "球"))
            end
            if la.bestPlayer then
                table.insert(rows, HallOfFame._awardRow("MVP", la.bestPlayer.playerName, string.format("%.1f分", la.bestPlayer.rating or 0)))
            end
            if la.bestYoungPlayer then
                table.insert(rows, HallOfFame._awardRow("新秀", la.bestYoungPlayer.playerName, tostring(la.bestYoungPlayer.age or 0) .. "岁"))
            end
            if la.bestAssist then
                table.insert(rows, HallOfFame._awardRow("助攻王", la.bestAssist.playerName, tostring(la.bestAssist.assists or 0) .. "次"))
            end
        end
        if seasonAward.bestManager then
            table.insert(rows, HallOfFame._awardRow("最佳教练", seasonAward.bestManager.name or "?", ""))
        end

        if #rows > 0 then
            table.insert(cards, Theme.Card { children = {
                Theme.Subtitle { text = "第 " .. tostring(seasonAward.season) .. " 赛季奖项" },
                table.unpack(rows)
            }})
        end
    end

    return cards
end

------------------------------------------------------------
-- 转会记录榜
------------------------------------------------------------

local function buildTransfersTab(gameState)
    local allHistory = gameState._transferHistory
    if not allHistory or #allHistory == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无转会记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    -- 按金额排序取 Top20
    local sorted = {}
    for _, t in ipairs(allHistory) do table.insert(sorted, t) end
    table.sort(sorted, function(a, b) return (a.amount or 0) > (b.amount or 0) end)

    local rows = {}
    for i = 1, math.min(20, #sorted) do
        local t = sorted[i]
        local amountText = FinanceManager.formatMoney(t.amount or 0)

        local typeLabel = ""
        if t.type == "loan" then typeLabel = "[租]"
        elseif t.type == "free" then typeLabel = "[自由]" end

        table.insert(rows, UI.Panel {
            width = "100%", paddingVertical = 6, paddingHorizontal = 8,
            borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = (t.playerName or "?") .. " " .. typeLabel, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = amountText, width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.ACCENT, textAlign = "right" },
                }},
                UI.Panel { width = "100%", flexDirection = "row", marginTop = 2, paddingLeft = 20, children = {
                    UI.Label { text = (t.fromTeamName or "?") .. " → " .. (t.toTeamName or "?"), fontSize = 10, color = COLORS.TEXT_SECONDARY },
                }},
            }
        })
    end

    return { Theme.Card { children = {
        Theme.Subtitle { text = "历史转会金额 Top20" },
        table.unpack(rows)
    }}}
end

------------------------------------------------------------
-- 记录榜（联赛记录 + 球员记录）
------------------------------------------------------------

local function buildRecordsTab(gameState)
    RecordsManager._ensureData(gameState)
    local lr = RecordsManager.getLeagueRecords(gameState)
    local pr = RecordsManager.getPlayerRecords(gameState)
    local cards = {}

    -- 联赛记录
    local leagueRows = {}
    if lr.highestPoints then
        table.insert(leagueRows, HallOfFame._recordRow("最高积分", lr.highestPoints.teamName, tostring(lr.highestPoints.points) .. "分", "第" .. tostring(lr.highestPoints.season) .. "赛季"))
    end
    if lr.mostWins then
        table.insert(leagueRows, HallOfFame._recordRow("最多胜场", lr.mostWins.teamName, tostring(lr.mostWins.wins) .. "胜", "第" .. tostring(lr.mostWins.season) .. "赛季"))
    end
    if lr.fewestGoalsConceded then
        table.insert(leagueRows, HallOfFame._recordRow("最少失球", lr.fewestGoalsConceded.teamName, tostring(lr.fewestGoalsConceded.goalsAgainst) .. "球", "第" .. tostring(lr.fewestGoalsConceded.season) .. "赛季"))
    end
    if lr.consecutiveChampionships then
        table.insert(leagueRows, HallOfFame._recordRow("连续夺冠", lr.consecutiveChampionships.teamName, tostring(lr.consecutiveChampionships.count) .. "连冠", "第" .. tostring(lr.consecutiveChampionships.startSeason) .. "-" .. tostring(lr.consecutiveChampionships.endSeason) .. "赛季"))
    end

    if #leagueRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "联赛记录" },
            table.unpack(leagueRows)
        }})
    else
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "联赛记录" },
            UI.Label { text = "暂无记录（完成赛季后解锁）", fontSize = 12, color = COLORS.TEXT_MUTED },
        }})
    end

    -- 球员单赛季记录
    local playerRows = {}
    if pr.singleSeasonGoals then
        table.insert(playerRows, HallOfFame._recordRow("单赛季进球", pr.singleSeasonGoals.playerName, tostring(pr.singleSeasonGoals.goals) .. "球", pr.singleSeasonGoals.teamName))
    end
    if pr.singleSeasonAssists then
        table.insert(playerRows, HallOfFame._recordRow("单赛季助攻", pr.singleSeasonAssists.playerName, tostring(pr.singleSeasonAssists.assists) .. "次", pr.singleSeasonAssists.teamName))
    end
    if pr.singleSeasonRating then
        table.insert(playerRows, HallOfFame._recordRow("单赛季评分", pr.singleSeasonRating.playerName, string.format("%.1f", pr.singleSeasonRating.rating), pr.singleSeasonRating.teamName))
    end

    if #playerRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "球员单赛季记录" },
            table.unpack(playerRows)
        }})
    end

    -- 历史总进球 Top5
    if pr.allTimeGoals and #pr.allTimeGoals > 0 then
        local goalRows = {}
        for i = 1, math.min(5, #pr.allTimeGoals) do
            local entry = pr.allTimeGoals[i]
            table.insert(goalRows, UI.Panel {
                width = "100%", height = 32, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = entry.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = tostring(entry.value) .. "球", width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.ACCENT, textAlign = "right" },
                }
            })
        end
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "历史总进球 Top5" },
            table.unpack(goalRows)
        }})
    end

    -- 历史总助攻 Top5
    if pr.allTimeAssists and #pr.allTimeAssists > 0 then
        local assistRows = {}
        for i = 1, math.min(5, #pr.allTimeAssists) do
            local entry = pr.allTimeAssists[i]
            table.insert(assistRows, UI.Panel {
                width = "100%", height = 32, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = entry.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = tostring(entry.value) .. "次", width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.ACCENT, textAlign = "right" },
                }
            })
        end
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "历史总助攻 Top5" },
            table.unpack(assistRows)
        }})
    end

    return cards
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

function HallOfFame.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", children = {} }
    end

    HistoryManager._ensureData(gameState)

    local tabs = {
        { key = "champions", label = "冠军榜" },
        { key = "awards",    label = "奖项榜" },
        { key = "transfers", label = "转会记录" },
        { key = "records",   label = "记录" },
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
                Router.replaceWith("hall_of_fame", params)
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
    if _activeTab == "champions" then
        tabContent = buildChampionsTab(gameState)
    elseif _activeTab == "awards" then
        tabContent = buildAwardsTab(gameState)
    elseif _activeTab == "transfers" then
        tabContent = buildTransfersTab(gameState)
    elseif _activeTab == "records" then
        tabContent = buildRecordsTab(gameState)
    else
        tabContent = buildChampionsTab(gameState)
    end

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = COLORS.BG_DARK,
        children = {
            Theme.TopBar { children = {
                UI.Panel { width = 60, height = 32, justifyContent = "center", onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } } },
                UI.Label { text = "名人堂", fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
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

function HallOfFame._awardRow(label, name, detail)
    return UI.Panel {
        width = "100%", height = 34, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
        children = {
            UI.Label { text = label, width = 56, fontSize = 10, color = COLORS.WARNING, fontWeight = "bold" },
            UI.Label { text = name or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
            UI.Label { text = detail, fontSize = 10, color = COLORS.TEXT_SECONDARY },
        }
    }
end

function HallOfFame._recordRow(label, holder, value, context)
    return UI.Panel {
        width = "100%", height = 38, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
        children = {
            UI.Label { text = label, width = 72, fontSize = 10, color = COLORS.ACCENT, fontWeight = "bold" },
            UI.Panel { flex = 1, children = {
                UI.Label { text = holder or "?", fontSize = 12, color = COLORS.TEXT_PRIMARY },
                UI.Label { text = context or "", fontSize = 9, color = COLORS.TEXT_MUTED, marginTop = 1 },
            }},
            UI.Label { text = value or "", width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.WARNING, textAlign = "right" },
        }
    }
end

return HallOfFame
