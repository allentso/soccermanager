--- 球队详情页 - 可查看任意球队（概览/阵容/历史/统计）
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local Constants = require("scripts/app/constants")
local TeamIcon = require("scripts/ui/components/team_icon")
local FinanceManager = require("scripts/systems/finance_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local HistoryManager = require("scripts/systems/history_manager")

local COLORS = Theme.COLORS

local TeamDetail = {}

-- 模块级状态：当前标签页
local _activeTab = "overview"

------------------------------------------------------------
-- 辅助函数
------------------------------------------------------------

local function posColor(pos)
    return Theme.posColor(pos)
end

local function posGroup(pos)
    for grp, positions in pairs(Constants.POSITION_GROUPS) do
        for _, p in ipairs(positions) do
            if p == pos then return grp end
        end
    end
    return "MID"
end

local function formBadge(result)
    local color
    if result == "W" then color = COLORS.SECONDARY
    elseif result == "D" then color = COLORS.WARNING
    else color = COLORS.DANGER end
    return UI.Panel {
        width = 22, height = 22, borderRadius = 11,
        backgroundColor = color,
        justifyContent = "center", alignItems = "center",
        marginRight = 4,
        children = { UI.Label { text = result, fontSize = 11, fontWeight = "bold", color = COLORS.TEXT_PRIMARY } }
    }
end

------------------------------------------------------------
-- 概览标签
------------------------------------------------------------

local function buildOverviewTab(team, gameState, teamId)
    local children = {}

    -- 身份卡
    local identityRows = {
        { "城市", team.city or "未知" },
        { "国家", team.country or "未知" },
        { "成立", team.foundedYear and tostring(team.foundedYear) or "未知" },
        { "球场", (team.stadiumName or "未知") .. " (" .. tostring(team.stadiumCapacity or 0) .. "人)" },
        { "声望", tostring(team.reputation or 0) .. " / 1000" },
        { "阵型", team.formation or "4-4-2" },
        { "风格", team:getPlayStyleName() },
    }

    local rivalNames = {}
    for _, rivalId in ipairs(TransferManager.getRivalTeams(gameState, teamId)) do
        local rivalTeam = gameState.teams[rivalId]
        if rivalTeam then
            table.insert(rivalNames, rivalTeam.name or rivalTeam.shortName)
        end
    end
    if #rivalNames > 0 then
        table.insert(identityRows, { "死敌", table.concat(rivalNames, "、") })
    end
    local identityChildren = {}
    for _, row in ipairs(identityRows) do
        table.insert(identityChildren, UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between",
            paddingVertical = 4,
            children = {
                UI.Label { text = row[1], fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = row[2], fontSize = 12, color = COLORS.TEXT_PRIMARY, fontWeight = "bold" },
            }
        })
    end
    table.insert(children, Theme.Card { children = {
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 10,
            children = {
                TeamIcon { team = team, size = 52, marginRight = 14 },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label {
                            text = team.name or "未知球队",
                            fontSize = 17, color = COLORS.TEXT_PRIMARY, fontWeight = "bold",
                        },
                        UI.Label {
                            text = (team.city or "") .. " · " .. (team.country or ""),
                            fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 3,
                        },
                    },
                },
            },
        },
        Theme.Subtitle { text = "俱乐部信息" },
        table.unpack(identityChildren)
    }})

    -- 联赛排名
    local league, leagueKey = gameState:getTeamLeague(teamId)
    if league then
        local pos = league:getTeamPosition(teamId)
        local standing = league.standings[teamId]
        if standing then
            -- 排名突出显示 + 关键数据紧凑排列
            local function statItem(label, value, valueColor)
                return UI.Panel {
                    alignItems = "center", flex = 1,
                    children = {
                        UI.Label { text = value, fontSize = 15, fontWeight = "bold", color = valueColor or COLORS.TEXT_PRIMARY },
                        UI.Label { text = label, fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 2 },
                    }
                }
            end
            table.insert(children, Theme.Card { children = {
                Theme.Subtitle { text = "联赛排名 — " .. (league.name or leagueKey) },
                -- 主指标行：排名 / 积分 / 场次
                UI.Panel { width = "100%", flexDirection = "row", marginTop = 8, paddingVertical = 6, children = {
                    statItem("排名", "#" .. tostring(pos), COLORS.PRIMARY),
                    statItem("积分", tostring(standing.points), COLORS.PRIMARY),
                    statItem("场次", tostring(standing.played)),
                    statItem("净胜球", tostring(standing.goalDifference)),
                }},
                -- 胜/平/负 紧凑行
                UI.Panel { width = "100%", flexDirection = "row", marginTop = 6, paddingVertical = 4, children = {
                    statItem("胜", tostring(standing.wins), COLORS.SECONDARY),
                    statItem("平", tostring(standing.draws), COLORS.WARNING),
                    statItem("负", tostring(standing.losses), COLORS.DANGER),
                }},
            }})
        end
    end

    -- 近期状态
    local form = team.recentForm
    if form and #form > 0 then
        local badges = {}
        local start = math.max(1, #form - 7)
        for i = start, #form do
            table.insert(badges, formBadge(form[i]))
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "近期状态" },
            UI.Panel { width = "100%", flexDirection = "row", marginTop = 6, children = badges },
        }})
    end

    -- 财务概览
    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "财务概况" },
        UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
            Theme.StatPill { label = "余额", value = FinanceManager.formatMoney(team.balance or 0) },
            Theme.StatPill { label = "工资预算", value = FinanceManager.formatMoney(team.wageBudget or 0) .. "/周" },
            Theme.StatPill { label = "转会预算", value = FinanceManager.formatMoney(team.transferBudget or 0) },
        }},
    }})

    return children
end

------------------------------------------------------------
-- 阵容标签
------------------------------------------------------------

local function buildSquadTab(team, gameState, teamId)
    local players = gameState:getTeamPlayers(teamId)
    if #players == 0 then
        return { Theme.Card { children = { UI.Label { text = "暂无球员数据", fontSize = 13, color = COLORS.TEXT_MUTED } } } }
    end

    -- 按位置分组排序
    local groupOrder = { GK = 1, DEF = 2, MID = 3, FWD = 4 }
    table.sort(players, function(a, b)
        local ga = groupOrder[posGroup(a.position)] or 5
        local gb = groupOrder[posGroup(b.position)] or 5
        if ga ~= gb then return ga < gb end
        return (a.overall or 0) > (b.overall or 0)
    end)

    local rows = {}

    -- 表头
    table.insert(rows, UI.Panel {
        width = "100%", height = 32, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 10, backgroundColor = COLORS.BG_HEADER,
        children = {
            UI.Label { text = "位置", width = 36, fontSize = 10, color = COLORS.TEXT_MUTED },
            UI.Label { text = "姓名", flexGrow = 1, flexShrink = 1, fontSize = 10, color = COLORS.TEXT_MUTED },
            UI.Label { text = "出场", width = 32, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 4 },
            UI.Label { text = "进球", width = 32, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 2 },
            UI.Label { text = "助攻", width = 32, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 2 },
            UI.Label { text = "评分", width = 34, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 2 },
            UI.Label { text = "能力", width = 32, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 2 },
        }
    })

    for _, p in ipairs(players) do
        local pColor = posColor(p.position)
        local stats = p.seasonStats or {}
        local apps = stats.appearances or 0
        local goals = stats.goals or 0
        local assists = stats.assists or 0
        local avgRating = stats.avgRating or 0
        local ratingStr = avgRating > 0 and string.format("%.1f", avgRating) or "-"
        local cards = (stats.yellowCards or 0) + (stats.redCards or 0)

        table.insert(rows, UI.Panel {
            width = "100%", height = 44, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 10,
            borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = function()
                Router.navigate("player_detail", { playerId = p.id })
            end,
            children = {
                UI.Panel {
                    height = 20, borderRadius = 3,
                    paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                    backgroundColor = {pColor[1], pColor[2], pColor[3], 50},
                    justifyContent = "center", alignItems = "center",
                    children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position or "?", fontSize = 10, fontWeight = "bold", color = pColor } }
                },
                UI.Label { text = p.displayName or "未知", flexGrow = 1, flexShrink = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY, marginLeft = 8 },
                UI.Label { text = apps > 0 and tostring(apps) or "-", width = 32, fontSize = 11, color = COLORS.TEXT_SECONDARY, textAlign = "center", marginLeft = 4 },
                UI.Label { text = goals > 0 and tostring(goals) or "-", width = 32, fontSize = 11, color = goals > 0 and COLORS.SECONDARY or COLORS.TEXT_MUTED, fontWeight = goals >= 5 and "bold" or "normal", textAlign = "center", marginLeft = 2 },
                UI.Label { text = assists > 0 and tostring(assists) or "-", width = 32, fontSize = 11, color = assists > 0 and COLORS.ACCENT or COLORS.TEXT_MUTED, textAlign = "center", marginLeft = 2 },
                UI.Label { text = ratingStr, width = 34, fontSize = 11, color = avgRating >= 7.5 and COLORS.SECONDARY or (avgRating >= 6.5 and COLORS.TEXT_PRIMARY or COLORS.DANGER), textAlign = "center", marginLeft = 2 },
                UI.Label { text = tostring(p.overall or "?"), width = 32, fontSize = 12, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, textAlign = "center", marginLeft = 2 },
            }
        })
    end

    -- 统计栏
    local gkCount, defCount, midCount, fwdCount = 0, 0, 0, 0
    for _, p in ipairs(players) do
        local g = posGroup(p.position)
        if g == "GK" then gkCount = gkCount + 1
        elseif g == "DEF" then defCount = defCount + 1
        elseif g == "MID" then midCount = midCount + 1
        else fwdCount = fwdCount + 1 end
    end

    local summary = UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-around",
        paddingVertical = 8, marginBottom = 4,
        children = {
            Theme.StatPill { label = "总人数", value = tostring(#players) },
            Theme.StatPill { label = "门将", value = tostring(gkCount) },
            Theme.StatPill { label = "后卫", value = tostring(defCount) },
            Theme.StatPill { label = "中场", value = tostring(midCount) },
            Theme.StatPill { label = "前锋", value = tostring(fwdCount) },
        }
    }

    return { summary, Theme.Card { children = rows } }
end

------------------------------------------------------------
-- 权威历史标签（基于 worldHistory / HistoryManager）
------------------------------------------------------------

local function buildWorldHistoryTab(team, gameState, teamId)
    local children = {}
    local teamHistory = HistoryManager.getTeamHistory(gameState, teamId)

    local function infoRow(label, value, valueColor)
        return UI.Panel {
            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = label, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = tostring(value), fontSize = 12, fontWeight = "bold", color = valueColor or COLORS.TEXT_PRIMARY },
            }
        }
    end

    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "历史概览" },
        infoRow("联赛冠军", tostring(teamHistory.championships or 0) .. " 次", COLORS.WARNING),
        infoRow("最佳排名", (teamHistory.bestPosition and teamHistory.bestPosition < 999) and ("第" .. tostring(teamHistory.bestPosition) .. "名") or "-", COLORS.PRIMARY),
        infoRow("历史赛季", tostring(#(teamHistory.positions or {})) .. " 季"),
    }})

    -- 统一走 HistoryManager.getTeamHonors，避免在这里重复实现一遍聚合逻辑
    -- （联赛/国内杯/欧冠/欧联的权威聚合口径见 history_manager.lua）
    local HONOR_COLORS = {
        league = COLORS.WARNING,
        ucl = COLORS.PRIMARY,
        uel = {80, 140, 220, 255},
        cup = {180, 80, 200, 255},
    }
    local honors = HistoryManager.getTeamHonors(gameState, teamId)

    if #honors > 0 then
        local honorRows = {}
        for i = 1, math.min(12, #honors) do
            local h = honors[i]
            table.insert(honorRows, UI.Panel {
                width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = "第" .. tostring(h.season or "?") .. "季", width = 70, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = tostring(h.title or "?"), flexGrow = 1, flexShrink = 1, fontSize = 12, color = HONOR_COLORS[h.competition] or COLORS.WARNING },
                    UI.Label { text = tostring(h.detail or ""), fontSize = 11, color = COLORS.TEXT_SECONDARY },
                }
            })
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "荣誉记录（近12项）" },
            table.unpack(honorRows)
        }})
    end

    if teamHistory.positions and #teamHistory.positions > 0 then
        local posRows = {}
        for i = #teamHistory.positions, math.max(1, #teamHistory.positions - 9), -1 do
            local h = teamHistory.positions[i]
            table.insert(posRows, UI.Panel {
                width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = "第" .. tostring(h.season or "?") .. "季", width = 70, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = h.leagueName or "联赛", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = "第" .. tostring(h.position or "?") .. "名", width = 50, fontSize = 11, fontWeight = "bold", color = (h.position == 1) and COLORS.WARNING or COLORS.TEXT_SECONDARY, textAlign = "right" },
                    UI.Label { text = tostring(h.points or 0) .. "分", width = 42, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "right" },
                }
            })
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "联赛历史（近10季）" },
            table.unpack(posRows)
        }})
    end

    local awardRows = {}
    for i = #(gameState.worldHistory or {}), 1, -1 do
        local record = gameState.worldHistory[i]
        local awards = record.awards
        if awards then
            if awards.ballonDor and awards.ballonDor[1] and awards.ballonDor[1].teamId == teamId then
                local bd = awards.ballonDor[1]
                table.insert(awardRows, UI.Panel {
                    width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                    paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                    onClick = bd.playerId and function() Router.navigate("player_detail", { playerId = bd.playerId }) end or nil,
                    children = {
                        UI.Label { text = "第" .. tostring(record.season or "?") .. "季", width = 70, fontSize = 10, color = COLORS.TEXT_MUTED },
                        UI.Label { text = "金球奖", width = 54, fontSize = 10, fontWeight = "bold", color = COLORS.WARNING },
                        UI.Label { text = bd.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                        UI.Label { text = string.format("%.1f分", bd.score or 0), fontSize = 10, color = COLORS.TEXT_SECONDARY },
                    }
                })
            end
            for _, la in pairs(awards.leagues or {}) do
                local awardItems = {
                    { label = "金靴", data = la.goldenBoot, detailKey = "goals", suffix = "球" },
                    { label = "MVP", data = la.bestPlayer, detailKey = "score", suffix = "分" },
                    { label = "新秀", data = la.bestYoungPlayer, detailKey = "age", suffix = "岁" },
                    { label = "助攻王", data = la.topAssists or la.bestAssist, detailKey = "assists", suffix = "次" },
                    { label = "金手套", data = la.goldenGlove or la.bestGoalkeeper, detailKey = "cleanSheets", suffix = "零封" },
                }
                for _, item in ipairs(awardItems) do
                    local data = item.data
                    if data and data.teamId == teamId then
                        local value = data[item.detailKey] or data.rating or data.overall or 0
                        table.insert(awardRows, UI.Panel {
                            width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                            onClick = data.playerId and function() Router.navigate("player_detail", { playerId = data.playerId }) end or nil,
                            children = {
                                UI.Label { text = "第" .. tostring(record.season or "?") .. "季", width = 70, fontSize = 10, color = COLORS.TEXT_MUTED },
                                UI.Label { text = item.label, width = 54, fontSize = 10, fontWeight = "bold", color = COLORS.ACCENT },
                                UI.Label { text = data.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                                UI.Label { text = tostring(value) .. item.suffix, fontSize = 10, color = COLORS.TEXT_SECONDARY },
                            }
                        })
                    end
                end
            end
        end
        if #awardRows >= 10 then break end
    end
    if #awardRows > 0 then
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "获奖球员（近10项）" },
            table.unpack(awardRows)
        }})
    end

    local managerHistory = HistoryManager.getManagerHistory(gameState, teamId)
    if managerHistory and #managerHistory > 0 then
        local managerRows = {}
        for i = #managerHistory, math.max(1, #managerHistory - 9), -1 do
            local h = managerHistory[i]
            table.insert(managerRows, UI.Panel {
                width = "100%", minHeight = 34, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, paddingVertical = 4, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = tostring(h.date and h.date.year or h.season or "?"), width = 42, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = h.managerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = h.reason or h.type or "", fontSize = 10, color = COLORS.TEXT_SECONDARY },
                }
            })
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "经理变动（近10条）" },
            table.unpack(managerRows)
        }})
    end

    local league, _ = gameState:getTeamLeague(teamId)
    if league and league.fixtures then
        local finishedMatches = {}
        for _, fixture in ipairs(league.fixtures) do
            if fixture.status == "finished" and (fixture.homeTeamId == teamId or fixture.awayTeamId == teamId) then
                table.insert(finishedMatches, fixture)
            end
        end
        local startIdx = math.max(1, #finishedMatches - 9)
        local matchRows = {}
        for i = #finishedMatches, startIdx, -1 do
            local f = finishedMatches[i]
            local isHome = (f.homeTeamId == teamId)
            local oppId = isHome and f.awayTeamId or f.homeTeamId
            local oppTeam = gameState.teams[oppId]
            local oppName = oppTeam and oppTeam.name or "???"
            local myGoals = isHome and f.homeGoals or f.awayGoals
            local theirGoals = isHome and f.awayGoals or f.homeGoals
            local score = tostring(myGoals) .. " - " .. tostring(theirGoals)
            local venue = isHome and "主" or "客"
            local resultColor = COLORS.WARNING
            if myGoals > theirGoals then resultColor = COLORS.SECONDARY
            elseif myGoals < theirGoals then resultColor = COLORS.DANGER end

            table.insert(matchRows, UI.Panel {
                width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = "R" .. tostring(f.round or "?"), width = 30, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = venue, width = 20, fontSize = 10, color = COLORS.TEXT_MUTED, textAlign = "center" },
                    UI.Label { text = oppName, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY, marginLeft = 6 },
                    UI.Label { text = score, width = 50, fontSize = 12, fontWeight = "bold", color = resultColor, textAlign = "center" },
                }
            })
        end
        if #matchRows > 0 then
            table.insert(children, Theme.Card { children = {
                Theme.Subtitle { text = "本赛季比赛（近10场）" },
                table.unpack(matchRows)
            }})
        end
    end

    return children
end

------------------------------------------------------------
-- 传奇殿堂标签（团队荣誉墙 + 队史球星 Top10）
------------------------------------------------------------

local function buildLegendsTab(team, gameState, teamId)
    local children = {}

    -- 荣誉墙：全部冠军荣誉，按赛季倒序（口径与"历史"Tab 一致，见 HistoryManager.getTeamHonors）
    local HONOR_COLORS = {
        league = COLORS.WARNING,
        ucl = COLORS.PRIMARY,
        uel = {80, 140, 220, 255},
        cup = {180, 80, 200, 255},
    }
    local honors = HistoryManager.getTeamHonors(gameState, teamId)
    if #honors > 0 then
        local honorRows = {}
        for i = 1, math.min(20, #honors) do
            local h = honors[i]
            table.insert(honorRows, UI.Panel {
                width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                children = {
                    UI.Label { text = "第" .. tostring(h.season or "?") .. "季", width = 70, fontSize = 10, color = COLORS.TEXT_MUTED },
                    UI.Label { text = tostring(h.title or "?"), flexGrow = 1, flexShrink = 1, fontSize = 12, color = HONOR_COLORS[h.competition] or COLORS.WARNING },
                    UI.Label { text = tostring(h.detail or ""), fontSize = 11, color = COLORS.TEXT_SECONDARY },
                }
            })
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "荣誉墙（共 " .. tostring(#honors) .. " 项冠军）" },
            table.unpack(honorRows)
        }})
    else
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "荣誉墙" },
            UI.Label { text = "球队暂未获得冠军荣誉，加油！", fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 6 },
        }})
    end

    -- 队史功勋 Top10：综合贡献分排序，数据来自 HistoryManager._teamLegendStats
    -- （赛季末增量累加；离队/退役球员仍保留，UI 以灰色「已离队」标注）
    local legends = HistoryManager.getTeamLegendStats(gameState, teamId, 10)
    if #legends == 0 then
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "队史功勋榜" },
            UI.Label { text = "完成多个赛季后，这里会记录球队功勋球员。", fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 6 },
        }})
        return children
    end

    local legendRows = {}
    for i, entry in ipairs(legends) do
        local isActive = HistoryManager.isLegendActiveAtTeam(gameState, teamId, entry.playerId)
        local rankColor = COLORS.TEXT_MUTED
        if i == 1 then rankColor = COLORS.WARNING
        elseif i <= 3 then rankColor = COLORS.PRIMARY end

        local yearsLabel
        if entry.firstSeason == entry.lastSeason then
            yearsLabel = "第" .. tostring(entry.firstSeason) .. "季"
        else
            yearsLabel = "第" .. tostring(entry.firstSeason) .. "-" .. tostring(entry.lastSeason) .. "季"
        end

        local nameRowChildren = {
            UI.Label {
                text = entry.playerName or "?", fontSize = 13, fontWeight = "bold",
                color = isActive and COLORS.TEXT_PRIMARY or COLORS.TEXT_MUTED,
            },
        }
        if not isActive then
            table.insert(nameRowChildren, UI.Label {
                text = "已离队",
                fontSize = 10, marginLeft = 6, color = COLORS.TEXT_MUTED,
            })
        end
        for _, meta in ipairs(HistoryManager.LEGEND_AWARD_META) do
            local count = entry.individualAwards and entry.individualAwards[meta.key]
            if count and count > 0 then
                table.insert(nameRowChildren, UI.Label {
                    text = meta.icon .. (count > 1 and ("x" .. tostring(count)) or ""),
                    fontSize = 12, marginLeft = 5, color = COLORS.WARNING,
                })
            end
        end

        local canNavigate = gameState.players[entry.playerId] ~= nil
        table.insert(legendRows, UI.Panel {
            width = "100%", minHeight = 54, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, paddingVertical = 6, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = canNavigate and function() Router.navigate("player_detail", { playerId = entry.playerId }) end or nil,
            children = {
                UI.Label { text = tostring(i), width = 22, fontSize = 13, fontWeight = "bold", color = rankColor },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1, marginLeft = 6,
                    children = {
                        UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", children = nameRowChildren },
                        UI.Label {
                            text = yearsLabel .. " · " .. (Constants.POSITION_NAMES[entry.position] or entry.position or "?"),
                            fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 2,
                        },
                    }
                },
                UI.Panel {
                    alignItems = "flex-end",
                    children = {
                        UI.Label {
                            text = HistoryManager.formatLegendPrimaryStat(entry),
                            fontSize = 12, fontWeight = "bold", color = COLORS.SECONDARY,
                        },
                        UI.Label {
                            text = HistoryManager.formatLegendSecondaryStat(entry),
                            fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 2,
                        },
                    }
                },
            }
        })
    end

    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "队史功勋榜 Top10" },
        UI.Label {
            text = "综合出场、数据、随队夺冠与个人奖项；已离队球员仍计入队史。",
            fontSize = 11, color = COLORS.TEXT_MUTED, marginTop = 4, marginBottom = 8,
        },
        table.unpack(legendRows)
    }})

    -- 队史单项纪录墙
    local records = HistoryManager.getTeamLegendRecords(gameState, teamId)
    if #records > 0 then
        local recordRows = {}
        for _, rec in ipairs(records) do
            local isActive = HistoryManager.isLegendActiveAtTeam(gameState, teamId, rec.playerId)
            table.insert(recordRows, UI.Panel {
                width = "100%", height = 40, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = gameState.players[rec.playerId] and function()
                    Router.navigate("player_detail", { playerId = rec.playerId })
                end or nil,
                children = {
                    UI.Label { text = rec.icon, width = 24, fontSize = 14 },
                    UI.Label { text = rec.label, width = 88, fontSize = 11, color = COLORS.TEXT_SECONDARY },
                    UI.Label {
                        text = rec.playerName or "?",
                        flexGrow = 1, flexShrink = 1, fontSize = 12, fontWeight = "bold",
                        color = isActive and COLORS.TEXT_PRIMARY or COLORS.TEXT_MUTED,
                    },
                    UI.Label {
                        text = tostring(rec.value) .. rec.suffix,
                        width = 56, fontSize = 12, fontWeight = "bold",
                        color = COLORS.ACCENT, textAlign = "right",
                    },
                }
            })
        end
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "队史纪录" },
            UI.Label {
                text = "单项数据之王（进球 / 助攻 / 出场 / 零封）。",
                fontSize = 11, color = COLORS.TEXT_MUTED, marginTop = 4, marginBottom = 6,
            },
            table.unpack(recordRows)
        }})
    end

    return children
end

------------------------------------------------------------
-- 统计标签
------------------------------------------------------------

local function buildStatsTab(team, gameState, teamId)
    local players = gameState:getTeamPlayers(teamId)
    local children = {}

    -- 球队平均能力
    local totalOvr, totalAge = 0, 0
    for _, p in ipairs(players) do
        totalOvr = totalOvr + (p.overall or 0)
        totalAge = totalAge + p:getAge(gameState.date.year)
    end
    local n = math.max(1, #players)
    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "球队概况" },
        UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
            Theme.StatPill { label = "平均能力", value = string.format("%.1f", totalOvr / n), valueColor = COLORS.PRIMARY },
            Theme.StatPill { label = "平均年龄", value = string.format("%.1f", totalAge / n) },
            Theme.StatPill { label = "阵容人数", value = tostring(#players) },
        }},
    }})

    -- Top 5 球员
    local sorted = {}
    for _, p in ipairs(players) do table.insert(sorted, p) end
    table.sort(sorted, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
    local topRows = {}
    for i = 1, math.min(5, #sorted) do
        local p = sorted[i]
        local pColor = posColor(p.position)
        table.insert(topRows, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = {
                UI.Label { text = tostring(i), width = 20, fontSize = 11, color = COLORS.TEXT_MUTED },
                UI.Panel {
                    height = 18, borderRadius = 3,
                    paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                    backgroundColor = {pColor[1], pColor[2], pColor[3], 50},
                    justifyContent = "center", alignItems = "center",
                    children = { UI.Label { text = Constants.POSITION_NAMES[p.position] or p.position or "?", fontSize = 9, fontWeight = "bold", color = pColor } }
                },
                ---@diagnostic disable-next-line: param-type-mismatch
                UI.Label { text = p.displayName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY, marginLeft = 6 },
                UI.Label { text = tostring(p.overall or "?"), width = 34, fontSize = 12, fontWeight = "bold", color = COLORS.PRIMARY, textAlign = "center" },
            }
        })
    end
    if #topRows > 0 then
        table.insert(children, Theme.Card { children = {
            Theme.Subtitle { text = "最强阵容 Top5" },
            table.unpack(topRows)
        }})
    end

    -- 位置分布图（简单条形）
    local groupCounts = { GK = 0, DEF = 0, MID = 0, FWD = 0 }
    for _, p in ipairs(players) do
        local g = posGroup(p.position)
        groupCounts[g] = (groupCounts[g] or 0) + 1
    end
    local maxCount = math.max(groupCounts.GK, groupCounts.DEF, groupCounts.MID, groupCounts.FWD, 1)
    local distRows = {}
    local groupNames = { { "GK", "门将", {255,204,0,255} }, { "DEF", "后卫", {77,179,255,255} }, { "MID", "中场", {102,255,128,255} }, { "FWD", "前锋", {255,102,102,255} } }
    for _, gd in ipairs(groupNames) do
        local count = groupCounts[gd[1]] or 0
        local pct = math.floor(count / maxCount * 100)
        table.insert(distRows, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginTop = 4,
            children = {
                UI.Label { text = gd[2], width = 36, fontSize = 11, color = COLORS.TEXT_SECONDARY },
                UI.Panel { flex = 1, height = 14, borderRadius = 3, backgroundColor = COLORS.BG_HEADER, children = {
                    UI.Panel { width = tostring(pct) .. "%", height = 14, borderRadius = 3, backgroundColor = gd[3] }
                }},
                UI.Label { text = tostring(count), width = 24, fontSize = 11, color = COLORS.TEXT_PRIMARY, textAlign = "right", marginLeft = 6 },
            }
        })
    end
    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "位置分布" },
        table.unpack(distRows)
    }})

    -- 年龄分布
    local ageBuckets = { young = 0, prime = 0, senior = 0 }
    for _, p in ipairs(players) do
        local age = p:getAge(gameState.date.year)
        if age <= 22 then ageBuckets.young = ageBuckets.young + 1
        elseif age <= 29 then ageBuckets.prime = ageBuckets.prime + 1
        else ageBuckets.senior = ageBuckets.senior + 1 end
    end
    table.insert(children, Theme.Card { children = {
        Theme.Subtitle { text = "年龄结构" },
        UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
            Theme.StatPill { label = "青年(≤22)", value = tostring(ageBuckets.young), valueColor = COLORS.SECONDARY },
            Theme.StatPill { label = "当打(23-29)", value = tostring(ageBuckets.prime), valueColor = COLORS.PRIMARY },
            Theme.StatPill { label = "老将(30+)", value = tostring(ageBuckets.senior), valueColor = COLORS.DANGER },
        }},
    }})

    return children
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

function TeamDetail.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", children = {} }
    end

    local teamId = params and params.teamId
    if not teamId then
        return UI.Panel { width = "100%", height = "100%", children = {
            UI.Label { text = "缺少球队ID", fontSize = 14, color = COLORS.DANGER }
        }}
    end

    local team = gameState.teams[teamId]
    if not team then
        return UI.Panel { width = "100%", height = "100%", children = {
            UI.Label { text = "球队不存在", fontSize = 14, color = COLORS.DANGER }
        }}
    end

    -- 标签页定义
    local tabs = {
        { key = "overview", label = "概览" },
        { key = "squad",    label = "阵容" },
        { key = "history",  label = "历史" },
        { key = "legends",  label = "传奇" },
        { key = "stats",    label = "统计" },
    }

    -- 构建标签页内容
    local tabContent
    if _activeTab == "overview" then
        tabContent = buildOverviewTab(team, gameState, teamId)
    elseif _activeTab == "squad" then
        tabContent = buildSquadTab(team, gameState, teamId)
    elseif _activeTab == "history" then
        tabContent = buildWorldHistoryTab(team, gameState, teamId)
    elseif _activeTab == "legends" then
        tabContent = buildLegendsTab(team, gameState, teamId)
    elseif _activeTab == "stats" then
        tabContent = buildStatsTab(team, gameState, teamId)
    else
        tabContent = buildOverviewTab(team, gameState, teamId)
    end

    -- 标签栏
    local tabItems = {}
    for _, t in ipairs(tabs) do
        table.insert(tabItems, { key = t.key, label = t.label })
    end

    -- 使用 Theme.SubNav 风格的自定义标签栏
    local tabButtons = {}
    for _, t in ipairs(tabs) do
        local isActive = (_activeTab == t.key)
        table.insert(tabButtons, UI.Panel {
            flex = 1, height = 38, justifyContent = "center", alignItems = "center",
            borderBottomWidth = isActive and 2 or 0,
            borderColor = isActive and COLORS.PRIMARY or COLORS.TRANSPARENT,
            onClick = function()
                _activeTab = t.key
                Router.replaceWith("team_detail", params)
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

    local tabBar = UI.Panel {
        width = "100%", height = 38, flexDirection = "row",
        backgroundColor = COLORS.BG_HEADER,
        borderBottomWidth = 1, borderColor = COLORS.BORDER,
        children = tabButtons,
    }

    -- 判断是否是玩家自己的球队
    local isOwnTeam = (teamId == gameState.playerTeamId)
    local teamLabel = team.name or "球队"
    if isOwnTeam then teamLabel = teamLabel .. " (我的球队)" end

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar { children = {
                UI.Panel {
                    width = 60, height = 32, justifyContent = "center",
                    onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } }
                },
                UI.Label { text = teamLabel, fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
                UI.Panel { width = 60 },  -- spacer for centering
            }},
            -- 标签栏
            tabBar,
            -- 内容区
            UI.ScrollView {
                width = "100%", flex = 1,
                children = {
                    UI.Panel {
                        width = "100%", padding = 12, children = tabContent,
                    }
                }
            },
        }
    }
end

return TeamDetail
