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
local _activeTab = "yearbook"
local _selectedYearbookSeason = nil
local _selectedChampionsSeason = nil
local _selectedAwardsSeason = nil

--- 赛季列表：最新在前
local function getSortedSeasonsFromHistory(gameState)
    local history = HistoryManager.getWorldHistory(gameState)
    local seasons = {}
    for _, record in ipairs(history or {}) do
        if record.season then
            seasons[#seasons + 1] = record.season
        end
    end
    table.sort(seasons, function(a, b) return a > b end)
    return seasons
end

local function resolveSelectedSeason(seasons, current)
    if #seasons == 0 then return nil end
    if current then
        for _, s in ipairs(seasons) do
            if s == current then return current end
        end
    end
    return seasons[1]
end

--- 横向赛季选择条（年鉴 / 冠军榜 / 奖项榜共用）
local function buildSeasonSelector(tabKey, seasons, selectedSeason)
    selectedSeason = resolveSelectedSeason(seasons, selectedSeason)
    if not selectedSeason then return nil, nil end

    local seasonButtons = {}
    for _, season in ipairs(seasons) do
        local isActive = season == selectedSeason
        table.insert(seasonButtons, UI.Button {
            text = "第" .. tostring(season) .. "季",
            height = 30,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and COLORS.PRIMARY or COLORS.BG_SURFACE,
            borderRadius = 15,
            fontSize = 11,
            color = isActive and COLORS.TEXT_PRIMARY or COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 6,
            flexShrink = 0,
            onClick = function()
                Router.replaceWith("hall_of_fame", { tab = tabKey, season = season })
            end,
        })
    end

    return UI.ScrollView {
        width = "100%",
        height = 42,
        scrollX = true,
        scrollY = false,
        flexDirection = "row",
        children = seasonButtons,
    }, selectedSeason
end

local function applyRouteSeason(params)
    if not params or not params.tab or not params.season then return end
    if params.tab == "yearbook" then
        _selectedYearbookSeason = params.season
    elseif params.tab == "champions" then
        _selectedChampionsSeason = params.season
    elseif params.tab == "awards" then
        _selectedAwardsSeason = params.season
    end
end

------------------------------------------------------------
-- 赛季年鉴（按 worldHistory 浏览）
------------------------------------------------------------

local function buildYearbookTab(gameState)
    local history = HistoryManager.getWorldHistory(gameState)
    if not history or #history == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无赛季年鉴（完成第一个赛季后解锁）", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local seasons = getSortedSeasonsFromHistory(gameState)
    _selectedYearbookSeason = resolveSelectedSeason(seasons, _selectedYearbookSeason)

    local selected = HistoryManager.getSeasonHistory(gameState, _selectedYearbookSeason)
    if not selected then
        selected = HistoryManager.getSeasonHistory(gameState, seasons[1])
        _selectedYearbookSeason = selected and selected.season or seasons[1]
    end
    if not selected then
        return { Theme.Card { children = { UI.Label { text = "暂无赛季年鉴", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local seasonBar, _ = buildSeasonSelector("yearbook", seasons, _selectedYearbookSeason)
    local cards = { seasonBar }

    local leagueCount, cupCount, continentalCount = 0, 0, 0
    for _, leagueRecord in pairs(selected.leagues or {}) do
        if leagueRecord.champion then leagueCount = leagueCount + 1 end
    end
    for _, cupData in pairs(selected.domesticCups or {}) do
        if cupData.winnerId then cupCount = cupCount + 1 end
    end
    if selected.uclChampion then continentalCount = continentalCount + 1 end
    if selected.uelChampion then continentalCount = continentalCount + 1 end

    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = "第 " .. tostring(selected.season or "?") .. " 赛季年鉴" },
        UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
            Theme.StatPill { label = "联赛冠军", value = tostring(leagueCount) },
            Theme.StatPill { label = "杯赛冠军", value = tostring(cupCount) },
            Theme.StatPill { label = "欧战冠军", value = tostring(continentalCount) },
            Theme.StatPill { label = "年份", value = tostring(selected.year or selected.season or "?") },
        }},
    }})

    local championRows = {}
    for leagueKey, leagueRecord in pairs(selected.leagues or {}) do
        if leagueRecord.champion then
            local info = leagueRecord.champion
            table.insert(championRows, UI.Panel {
                width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = info.teamId and function() Router.navigate("team_detail", { teamId = info.teamId }) end or nil,
                children = {
                    UI.Label { text = leagueRecord.name or leagueKey, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = info.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                    UI.Label { text = tostring(info.points or 0) .. "分", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
                }
            })
        end
    end
    if selected.uclChampion then
        table.insert(championRows, UI.Panel {
            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = selected.uclChampion.teamId and function() Router.navigate("team_detail", { teamId = selected.uclChampion.teamId }) end or nil,
            children = {
                UI.Label { text = "欧洲冠军联赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = selected.uclChampion.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.PRIMARY },
                UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
            }
        })
    end
    if selected.uelChampion then
        table.insert(championRows, UI.Panel {
            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = selected.uelChampion.teamId and function() Router.navigate("team_detail", { teamId = selected.uelChampion.teamId }) end or nil,
            children = {
                UI.Label { text = "欧洲联赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = selected.uelChampion.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.PRIMARY },
                UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
            }
        })
    end
    for _, cupData in pairs(selected.domesticCups or {}) do
        if cupData.winnerId then
            table.insert(championRows, UI.Panel {
                width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = function() Router.navigate("team_detail", { teamId = cupData.winnerId }) end,
                children = {
                    UI.Label { text = cupData.name or "国内杯赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = cupData.winnerName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                    UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
                }
            })
        end
    end
    if #championRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "冠军归属" },
            table.unpack(championRows),
        }})
    end

    local awardRows = {}
    local awards = selected.awards
    if awards then
        if awards.ballonDor and awards.ballonDor[1] then
            local bd = awards.ballonDor[1]
            table.insert(awardRows, HallOfFame._awardRow("金球奖", bd.playerName, (bd.teamName or "?") .. " · " .. string.format("%.1f分", bd.score or 0)))
        end
        for _, la in pairs(awards.leagues or {}) do
            if la.goldenBoot then table.insert(awardRows, HallOfFame._awardRow("金靴", la.goldenBoot.playerName, tostring(la.goldenBoot.goals or 0) .. "球")) end
            if la.bestPlayer then table.insert(awardRows, HallOfFame._awardRow("MVP", la.bestPlayer.playerName, string.format("%.1f分", la.bestPlayer.score or 0))) end
            if la.topAssists then table.insert(awardRows, HallOfFame._awardRow("助攻王", la.topAssists.playerName, tostring(la.topAssists.assists or 0) .. "次")) end
            local goldenGlove = la.goldenGlove or la.bestGoalkeeper
            if goldenGlove then table.insert(awardRows, HallOfFame._awardRow("金手套", goldenGlove.playerName, tostring(goldenGlove.cleanSheets or 0) .. "零封")) end
        end
    end
    if #awardRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "年度奖项" },
            table.unpack(awardRows),
        }})
    end

    local transferRows = {}
    for i, t in ipairs(selected.topTransfers or {}) do
        table.insert(transferRows, UI.Panel {
            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = t.playerId and function() Router.navigate("player_detail", { playerId = t.playerId }) end or nil,
            children = {
                UI.Label { text = tostring(i), width = 20, fontSize = 10, color = COLORS.TEXT_MUTED },
                UI.Label { text = t.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                UI.Label { text = FinanceManager.formatMoney(t.amount or 0), width = 72, fontSize = 11, fontWeight = "bold", color = COLORS.ACCENT, textAlign = "right" },
            }
        })
    end
    if #transferRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "当季重磅转会" },
            table.unpack(transferRows),
        }})
    end

    local prRows = {}
    for _, item in ipairs(selected.promotionRelegation or {}) do
        table.insert(prRows, UI.Panel {
            width = "100%", height = 32, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = item.teamName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                UI.Label { text = item.type == "promoted" and "升级" or (item.type == "relegated" and "降级" or tostring(item.type or "")), width = 48, fontSize = 11, fontWeight = "bold", color = item.type == "promoted" and COLORS.SECONDARY or COLORS.DANGER, textAlign = "right" },
            }
        })
    end
    if #prRows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "升降级" },
            table.unpack(prRows),
        }})
    end

    if selected.playerFinance then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "我的球队财务快照" },
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
                Theme.StatPill { label = "收入", value = FinanceManager.formatMoney(selected.playerFinance.seasonIncome or 0) },
                Theme.StatPill { label = "支出", value = FinanceManager.formatMoney(selected.playerFinance.seasonExpense or 0) },
                Theme.StatPill { label = "余额", value = FinanceManager.formatMoney(selected.playerFinance.balance or 0) },
            }},
        }})
    end

    return cards
end

------------------------------------------------------------
-- 冠军榜
------------------------------------------------------------

local function buildChampionsTab(gameState)
    local champions = HistoryManager.getChampionsList(gameState)
    if #champions == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无冠军记录（完成第一个赛季后解锁）", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local bySeason = {}
    local seasons = {}
    for _, sc in ipairs(champions) do
        if sc.season then
            bySeason[sc.season] = sc
            seasons[#seasons + 1] = sc.season
        end
    end
    table.sort(seasons, function(a, b) return a > b end)

    _selectedChampionsSeason = resolveSelectedSeason(seasons, _selectedChampionsSeason)
    local sc = bySeason[_selectedChampionsSeason]
    if not sc then
        return { Theme.Card { children = { UI.Label { text = "暂无冠军记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local seasonBar, _ = buildSeasonSelector("champions", seasons, _selectedChampionsSeason)
    local cards = { seasonBar }

    local rows = {}
    for leagueKey, info in pairs(sc.leagues or {}) do
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
    for _, info in ipairs(sc.continental or {}) do
        table.insert(rows, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = info.teamId and function()
                Router.navigate("team_detail", { teamId = info.teamId })
            end or nil,
            children = {
                UI.Label { text = info.competitionName or "洲际赛事", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = info.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.PRIMARY },
                UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
            }
        })
    end
    for _, info in ipairs(sc.cups or {}) do
        table.insert(rows, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = info.teamId and function()
                Router.navigate("team_detail", { teamId = info.teamId })
            end or nil,
            children = {
                UI.Label { text = info.competitionName or "杯赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = info.teamName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
            }
        })
    end
    for _, info in ipairs(sc.international or {}) do
        table.insert(rows, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = info.competitionName or "国际赛事", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = info.championName or "?", fontSize = 12, fontWeight = "bold", color = COLORS.ACCENT },
                UI.Label { text = "冠军", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
            }
        })
    end

    if #rows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "第 " .. tostring(sc.season) .. " 赛季冠军 (" .. tostring(sc.year or "?") .. ")" },
            table.unpack(rows),
        }})
    else
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "第 " .. tostring(sc.season) .. " 赛季冠军" },
            UI.Label { text = "该赛季暂无冠军记录", fontSize = 12, color = COLORS.TEXT_MUTED },
        }})
    end

    return cards
end

------------------------------------------------------------
-- 奖项榜
------------------------------------------------------------

local function buildAwardsTab(gameState)
    local awardsBySeason = {}
    local seasons = {}
    for _, record in ipairs(gameState.worldHistory or {}) do
        if record.awards and record.season then
            awardsBySeason[record.season] = record.awards
            seasons[#seasons + 1] = record.season
        end
    end
    if #seasons == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无奖项记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end
    table.sort(seasons, function(a, b) return a > b end)

    _selectedAwardsSeason = resolveSelectedSeason(seasons, _selectedAwardsSeason)
    local seasonAward = awardsBySeason[_selectedAwardsSeason]
    if not seasonAward then
        return { Theme.Card { children = { UI.Label { text = "暂无奖项记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local seasonBar, _ = buildSeasonSelector("awards", seasons, _selectedAwardsSeason)
    local cards = { seasonBar }
    local rows = {}

    if seasonAward.ballonDor and seasonAward.ballonDor[1] then
        local bd = seasonAward.ballonDor[1]
        table.insert(rows, HallOfFame._awardRow("金球奖", bd.playerName, (bd.teamName or "?") .. " · " .. string.format("%.1f分", bd.score or 0)))
    end

    for _, la in pairs(seasonAward.leagues or {}) do
        if la.goldenBoot then
            table.insert(rows, HallOfFame._awardRow("金靴", la.goldenBoot.playerName, tostring(la.goldenBoot.goals or 0) .. "球"))
        end
        if la.bestPlayer then
            local score = la.bestPlayer.score or la.bestPlayer.rating or la.bestPlayer.overall or 0
            table.insert(rows, HallOfFame._awardRow("MVP", la.bestPlayer.playerName, string.format("%.1f分", score)))
        end
        if la.bestYoungPlayer then
            table.insert(rows, HallOfFame._awardRow("新秀", la.bestYoungPlayer.playerName, tostring(la.bestYoungPlayer.age or 0) .. "岁"))
        end
        local assistAward = la.topAssists or la.bestAssist
        if assistAward then
            table.insert(rows, HallOfFame._awardRow("助攻王", assistAward.playerName, tostring(assistAward.assists or 0) .. "次"))
        end
        local goldenGlove = la.goldenGlove or la.bestGoalkeeper
        if goldenGlove then
            table.insert(rows, HallOfFame._awardRow("金手套", goldenGlove.playerName, tostring(goldenGlove.cleanSheets or 0) .. "次零封"))
        end
    end
    if seasonAward.bestManager then
        table.insert(rows, HallOfFame._awardRow("最佳教练", seasonAward.bestManager.name or "?", ""))
    end

    if #rows > 0 then
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "第 " .. tostring(seasonAward.season or _selectedAwardsSeason) .. " 赛季奖项" },
            table.unpack(rows),
        }})
    else
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "第 " .. tostring(_selectedAwardsSeason) .. " 赛季奖项" },
            UI.Label { text = "该赛季暂无奖项记录", fontSize = 12, color = COLORS.TEXT_MUTED },
        }})
    end

    return cards
end

------------------------------------------------------------
-- 转会记录榜
------------------------------------------------------------

local function buildTransfersTab(gameState)
    local topTransfers = HistoryManager.getGlobalTopTransfers(gameState, 5)
    if not topTransfers or #topTransfers == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无转会记录", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    local rows = {}
    for i = 1, math.min(5, #topTransfers) do
        local t = topTransfers[i]
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
                    UI.Label { text = (t.fromTeamName or "?") .. " → " .. (t.toTeamName or "?") .. " · 第" .. tostring(t.season or "?") .. "季", fontSize = 10, color = COLORS.TEXT_SECONDARY },
                }},
            }
        })
    end

    return { Theme.Card { children = {
        Theme.Subtitle { text = "全球历史标王 Top5" },
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

    -- 历史总出场 Top5
    if pr.allTimeAppearances and #pr.allTimeAppearances > 0 then
        local appRows = {}
        for i = 1, math.min(5, #pr.allTimeAppearances) do
            local entry = pr.allTimeAppearances[i]
            table.insert(appRows, UI.Panel {
                width = "100%", height = 32, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(i), width = 20, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = entry.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = tostring(entry.value) .. "场", width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.PRIMARY, textAlign = "right" },
                }
            })
        end
        table.insert(cards, Theme.Card { children = {
            Theme.Subtitle { text = "历史总出场 Top5" },
            table.unpack(appRows)
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
    if params and params.tab then _activeTab = params.tab end
    applyRouteSeason(params)

    local tabs = {
        { key = "yearbook",  label = "年鉴" },
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
                Router.replaceWith("hall_of_fame", { tab = t.key })
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
    if _activeTab == "yearbook" then
        tabContent = buildYearbookTab(gameState)
    elseif _activeTab == "champions" then
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
