--- 赛季结算页 - 展示赛季总结（排名/奖项/财务/董事会评价/球员变动）
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local Constants = require("scripts/app/constants")
local HistoryManager = require("scripts/systems/history_manager")
local FinanceManager = require("scripts/systems/finance_manager")

local COLORS = Theme.COLORS

local SeasonEnd = {}

-- 模块级状态：Tab 切换（"summary"=本队总结, "others"=其他联赛）
local _activeTab = "summary"

------------------------------------------------------------
-- 辅助
------------------------------------------------------------

local function medal(position)
    if position == 1 then return "🥇"
    elseif position == 2 then return "🥈"
    elseif position == 3 then return "🥉"
    else return "#" .. tostring(position) end
end

local function formatMoney(amount)
    return FinanceManager.formatMoney(amount)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local CHAMPION_BONUS = 20000000

local function findPlayerLeaguePosition(record, teamId)
    if not record or not teamId then return nil end
    for _, leagueRecord in pairs(record.leagues or {}) do
        for _, entry in ipairs(leagueRecord.standings or {}) do
            if entry.teamId == teamId then
                return entry.position
            end
        end
    end
    return nil
end

--- 反查玩家球队在该历史赛季实际参赛的联赛 key。
--- 不能直接用 gameState.playerLeagueId：赛季结束时若发生升降级，
--- 该字段已经指向"新赛季"的联赛，与本 record（刚结束的赛季）对不上。
local function findPlayerLeagueKey(record, teamId)
    if not record or not teamId then return nil end
    for leagueKey, leagueRecord in pairs(record.leagues or {}) do
        for _, entry in ipairs(leagueRecord.standings or {}) do
            if entry.teamId == teamId then
                return leagueKey
            end
        end
    end
    return nil
end

local function calcSeasonPrize(position)
    if not position then return 0 end
    local prizes = Constants.SEASON_END_PRIZE or {}
    local prize = prizes[position] or 100000
    if position == 1 then
        prize = prize + CHAMPION_BONUS
    end
    return prize
end

------------------------------------------------------------
-- 奖项行（支持点击跳转球员详情）
------------------------------------------------------------

function SeasonEnd._awardRow(awardName, playerName, detail, playerId)
    return UI.Panel {
        width = "100%", height = 38, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
        onClick = playerId and function()
            Router.navigate("player_detail", { playerId = playerId })
        end or nil,
        children = {
            UI.Label { text = awardName, width = 70, fontSize = 11, color = COLORS.WARNING, fontWeight = "bold" },
            UI.Label { text = playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
            UI.Label { text = detail, fontSize = 10, color = COLORS.TEXT_SECONDARY },
        }
    }
end

--- 单个联赛的奖项行（用于"本队总结"/"其他联赛"分组展示）
local function buildLeagueAwardRows(la)
    local rows = {}
    if la.goldenBoot then
        table.insert(rows, SeasonEnd._awardRow("金靴奖", la.goldenBoot.playerName, tostring(la.goldenBoot.goals or 0) .. " 球", la.goldenBoot.playerId))
    end
    if la.bestPlayer then
        table.insert(rows, SeasonEnd._awardRow("最佳球员", la.bestPlayer.playerName, "OVR " .. tostring(la.bestPlayer.overall or 0), la.bestPlayer.playerId))
    end
    if la.bestYoungPlayer then
        table.insert(rows, SeasonEnd._awardRow("最佳新秀", la.bestYoungPlayer.playerName, tostring(la.bestYoungPlayer.age or 0) .. " 岁", la.bestYoungPlayer.playerId))
    end
    if la.topAssists then
        table.insert(rows, SeasonEnd._awardRow("助攻王", la.topAssists.playerName, tostring(la.topAssists.assists or 0) .. " 助攻", la.topAssists.playerId))
    end
    local goldenGlove = la.goldenGlove or la.bestGoalkeeper -- bestGoalkeeper 仅兼容旧存档
    if goldenGlove then
        table.insert(rows, SeasonEnd._awardRow("金手套", goldenGlove.playerName, tostring(goldenGlove.cleanSheets or 0) .. " 零封", goldenGlove.playerId))
    end
    return rows
end

--- 单个联赛的排名卡 + 评价卡（完整 Top5 + 玩家所在行）
local function buildLeagueStandingsCards(gameState, leagueKey, leagueRecord, teamId)
    local cards = {}
    local standingRows = {}
    local playerPosition = nil

    for i, entry in ipairs(leagueRecord.standings or {}) do
        if i > 5 and entry.teamId ~= teamId then goto continue end

        local isPlayer = (entry.teamId == teamId)
        if isPlayer then playerPosition = entry.position or i end
        local bgColor = isPlayer and {33, 150, 243, 40} or COLORS.TRANSPARENT

        table.insert(standingRows, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, backgroundColor = bgColor,
            borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = function()
                Router.navigate("team_detail", { teamId = entry.teamId })
            end,
            children = {
                UI.Label { text = medal(entry.position), width = 30, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                UI.Label { text = entry.teamName or "?", flex = 1, fontSize = 12,
                    color = isPlayer and COLORS.PRIMARY or COLORS.TEXT_PRIMARY,
                    fontWeight = isPlayer and "bold" or "normal" },
                UI.Label { text = tostring(entry.points) .. "分", width = 40, fontSize = 11, color = COLORS.TEXT_SECONDARY, textAlign = "right" },
                UI.Label { text = tostring(entry.wins or 0) .. "W", width = 28, fontSize = 10, color = COLORS.SECONDARY, textAlign = "right" },
            }
        })
        ::continue::
    end

    local champText = leagueRecord.champion and ("冠军: " .. leagueRecord.champion.teamName) or ""
    table.insert(cards, Theme.Card { children = {
        Theme.Subtitle { text = (leagueRecord.name or leagueKey) .. " 最终排名" },
        UI.Label { text = champText, fontSize = 12, fontWeight = "bold", color = COLORS.WARNING, marginTop = 2, marginBottom = 6 },
        table.unpack(standingRows)
    }})

    if playerPosition then
        local posText
        if playerPosition == 1 then posText = "恭喜！你获得了联赛冠军！🏆"
        elseif playerPosition <= 3 then posText = "出色！球队获得第" .. tostring(playerPosition) .. "名，进入欧冠区域。"
        elseif playerPosition <= 6 then posText = "中规中矩，第" .. tostring(playerPosition) .. "名。"
        elseif playerPosition <= 10 then posText = "赛季排名第" .. tostring(playerPosition) .. "，还有提升空间。"
        else posText = "第" .. tostring(playerPosition) .. "名，下赛季需要努力了。" end

        table.insert(cards, Theme.Card { children = {
            UI.Label { text = posText, fontSize = 13, color = playerPosition <= 3 and COLORS.WARNING or COLORS.TEXT_PRIMARY },
        }})
    end

    return cards
end

------------------------------------------------------------
-- "本队总结" Tab：只展示玩家所在联赛相关内容
------------------------------------------------------------

local function buildSummaryLeagueSection(gameState, record, teamId, playerLeagueKey)
    local content = {}

    -- 1. 玩家所在联赛：完整排名 + 评价
    local leagueRecord = playerLeagueKey and record.leagues[playerLeagueKey]
    if leagueRecord then
        for _, card in ipairs(buildLeagueStandingsCards(gameState, playerLeagueKey, leagueRecord, teamId)) do
            table.insert(content, card)
        end
    end

    -- 1.5 升降级信息卡（只看玩家所在联赛这一组）
    local proRelData = record.promotionRelegation or gameState.lastPromotionRelegation
    if proRelData and #proRelData > 0 and playerLeagueKey then
        local proRelRows = {}
        for _, info in ipairs(proRelData) do
            if info.leagueKey == playerLeagueKey then
                local isPlayer = (info.teamId == teamId)
                local icon = info.type == "promoted" and "⬆️" or "⬇️"
                local label = info.type == "promoted" and "升级" or "降级"
                local labelColor = info.type == "promoted" and COLORS.SECONDARY or COLORS.DANGER
                table.insert(proRelRows, UI.Panel {
                    width = "100%", height = 34, flexDirection = "row", alignItems = "center",
                    paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                    backgroundColor = isPlayer and {33, 150, 243, 40} or COLORS.TRANSPARENT,
                    children = {
                        UI.Label { text = icon, width = 24, fontSize = 12 },
                        UI.Label { text = info.teamName or "?", flex = 1, fontSize = 12,
                            color = isPlayer and COLORS.PRIMARY or COLORS.TEXT_PRIMARY,
                            fontWeight = isPlayer and "bold" or "normal" },
                        UI.Label { text = label, width = 40, fontSize = 11, fontWeight = "bold", color = labelColor, textAlign = "right" },
                    }
                })
            end
        end
        if #proRelRows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "升降级变动" },
                table.unpack(proRelRows)
            }})
        end
    end

    -- 1.8 杯赛结果卡（只看玩家所在联赛/国家的杯赛）
    if record.domesticCups and playerLeagueKey then
        local cupData = record.domesticCups[playerLeagueKey]
        if cupData then
            local isPlayer = (cupData.winnerId == teamId)
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "杯赛冠军 🏅" },
                UI.Panel {
                    width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                    paddingHorizontal = 8,
                    backgroundColor = isPlayer and {180, 80, 200, 30} or COLORS.TRANSPARENT,
                    children = {
                        UI.Label { text = "🏅", width = 28, fontSize = 14 },
                        UI.Label { text = cupData.name or "杯赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                        UI.Label { text = cupData.winnerName or "?", fontSize = 12,
                            fontWeight = isPlayer and "bold" or "normal",
                            color = isPlayer and {180, 80, 200, 255} or COLORS.TEXT_PRIMARY },
                    }
                }
            }})
        end
    end

    -- 2. 赛季奖项卡（金球奖/最佳经理为全局奖项 + 玩家所在联赛的奖项）
    local awards = record.awards
    if awards and awards.leagues then
        local awardRows = {}
        if awards.ballonDor and awards.ballonDor[1] then
            local bd = awards.ballonDor[1]
            table.insert(awardRows, SeasonEnd._awardRow("金球奖", bd.playerName, (bd.teamName or "?") .. " · " .. string.format("%.1f分", bd.score or 0), bd.playerId))
        end
        local ownLeagueAwards = playerLeagueKey and awards.leagues[playerLeagueKey]
        if ownLeagueAwards then
            for _, row in ipairs(buildLeagueAwardRows(ownLeagueAwards)) do
                table.insert(awardRows, row)
            end
        end
        if awards.bestManager then
            local managerDetail = awards.bestManager.teamName and (awards.bestManager.teamName .. " · 第" .. tostring(awards.bestManager.actualPosition or "?") .. "名") or ""
            table.insert(awardRows, SeasonEnd._awardRow("最佳经理", awards.bestManager.name or awards.bestManager.managerName or awards.bestManager.teamName or "?", managerDetail, nil))
        end
        if #awardRows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "赛季奖项 🏅" },
                table.unpack(awardRows)
            }})
        end
    end

    -- 3. 关键转会卡
    local transfers = record.topTransfers
    if transfers and #transfers > 0 then
        local transferRows = {}
        for i = 1, math.min(5, #transfers) do
            local t = transfers[i]
            table.insert(transferRows, UI.Panel {
                width = "100%", height = 40, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = function()
                    if t.playerId then Router.navigate("player_detail", { playerId = t.playerId }) end
                end,
                children = {
                    UI.Label { text = t.playerName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = (t.fromTeamName or "?") .. " → " .. (t.toTeamName or "?"), flex = 1, fontSize = 10, color = COLORS.TEXT_SECONDARY },
                    UI.Label { text = formatMoney(t.amount), width = 50, fontSize = 11, fontWeight = "bold", color = COLORS.ACCENT, textAlign = "right" },
                }
            })
        end
        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "赛季重磅转会 Top5" },
            table.unpack(transferRows)
        }})
    end

    return content
end

------------------------------------------------------------
-- "其他联赛" Tab：精简冠军行 + 按联赛分组的升降级/杯赛/奖项
------------------------------------------------------------

local function buildOtherLeaguesSection(gameState, record, teamId, playerLeagueKey)
    local content = {}

    -- 排序：让展示顺序稳定（按联赛 key 字母序），而不是 pairs() 的随机顺序
    local otherLeagueKeys = {}
    for leagueKey in pairs(record.leagues or {}) do
        if leagueKey ~= playerLeagueKey then
            table.insert(otherLeagueKeys, leagueKey)
        end
    end
    table.sort(otherLeagueKeys)

    if #otherLeagueKeys == 0 then
        table.insert(content, Theme.Card { children = {
            UI.Label { text = "暂无其他联赛数据", fontSize = 13, color = COLORS.TEXT_MUTED }
        }})
        return content
    end

    -- 冠军/亚军精简卡（一个联赛一行，避免铺开完整排名）
    local champRows = {}
    for _, leagueKey in ipairs(otherLeagueKeys) do
        local leagueRecord = record.leagues[leagueKey]
        local champion = leagueRecord.champion
        local runnerUp = leagueRecord.runnerUp
        table.insert(champRows, UI.Panel {
            width = "100%", height = 40, flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            onClick = champion and champion.teamId and function()
                Router.navigate("team_detail", { teamId = champion.teamId })
            end or nil,
            children = {
                UI.Label { text = leagueRecord.name or leagueKey, width = 70, fontSize = 11, color = COLORS.TEXT_SECONDARY },
                UI.Label { text = champion and ("🏆 " .. (champion.teamName or "?")) or "-", flex = 1, fontSize = 12, fontWeight = "bold", color = COLORS.WARNING },
                UI.Label { text = runnerUp and ("亚军 " .. (runnerUp.teamName or "?")) or "", fontSize = 10, color = COLORS.TEXT_MUTED },
            }
        })
    end
    table.insert(content, Theme.Card { children = {
        Theme.Subtitle { text = "各联赛冠军" },
        table.unpack(champRows)
    }})

    -- 升降级变动（按联赛分组）
    local proRelData = record.promotionRelegation or gameState.lastPromotionRelegation
    if proRelData and #proRelData > 0 then
        local grouped = {}
        for _, info in ipairs(proRelData) do
            if info.leagueKey and info.leagueKey ~= playerLeagueKey then
                grouped[info.leagueKey] = grouped[info.leagueKey] or {}
                table.insert(grouped[info.leagueKey], info)
            end
        end
        local rows = {}
        for _, leagueKey in ipairs(otherLeagueKeys) do
            local infos = grouped[leagueKey]
            if infos and #infos > 0 then
                local leagueRecord = record.leagues[leagueKey]
                table.insert(rows, UI.Label { text = leagueRecord and leagueRecord.name or leagueKey,
                    fontSize = 12, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, marginTop = 6, marginBottom = 2 })
                for _, info in ipairs(infos) do
                    local icon = info.type == "promoted" and "⬆️" or "⬇️"
                    local label = info.type == "promoted" and "升级" or "降级"
                    local labelColor = info.type == "promoted" and COLORS.SECONDARY or COLORS.DANGER
                    table.insert(rows, UI.Panel {
                        width = "100%", height = 30, flexDirection = "row", alignItems = "center",
                        paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                        children = {
                            UI.Label { text = icon, width = 24, fontSize = 11 },
                            UI.Label { text = info.teamName or "?", flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                            ---@diagnostic disable-next-line: param-type-mismatch
                            UI.Label { text = label, width = 40, fontSize = 10, fontWeight = "bold", color = labelColor, textAlign = "right" },
                        }
                    })
                end
            end
        end
        if #rows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "其他联赛升降级" },
                table.unpack(rows)
            }})
        end
    end

    -- 杯赛冠军（其他联赛/国家）
    if record.domesticCups then
        local cupRows = {}
        for _, leagueKey in ipairs(otherLeagueKeys) do
            local cupData = record.domesticCups[leagueKey]
            if cupData then
                table.insert(cupRows, UI.Panel {
                    width = "100%", height = 36, flexDirection = "row", alignItems = "center",
                    paddingHorizontal = 8, borderBottomWidth = 1, borderColor = COLORS.BORDER,
                    children = {
                        UI.Label { text = "🏅", width = 28, fontSize = 14 },
                        UI.Label { text = cupData.name or "杯赛", flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                        UI.Label { text = cupData.winnerName or "?", fontSize = 12, color = COLORS.TEXT_PRIMARY },
                    }
                })
            end
        end
        if #cupRows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "其他联赛杯赛冠军" },
                table.unpack(cupRows)
            }})
        end
    end

    -- 奖项（按联赛分组，带联赛标题）
    local awards = record.awards
    if awards and awards.leagues then
        local rows = {}
        for _, leagueKey in ipairs(otherLeagueKeys) do
            local la = awards.leagues[leagueKey]
            if la then
                local leagueAwardRows = buildLeagueAwardRows(la)
                if #leagueAwardRows > 0 then
                    local leagueRecord = record.leagues[leagueKey]
                    table.insert(rows, UI.Label { text = leagueRecord and leagueRecord.name or leagueKey,
                        fontSize = 12, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, marginTop = 6, marginBottom = 2 })
                    for _, row in ipairs(leagueAwardRows) do
                        table.insert(rows, row)
                    end
                end
            end
        end
        if #rows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "其他联赛奖项 🏅" },
                table.unpack(rows)
            }})
        end
    end

    return content
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

function SeasonEnd.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", children = {} }
    end

    -- 可指定查看哪个赛季，默认为上一赛季
    local targetSeason = params and params.season or (gameState.season - 1)
    local record = HistoryManager.getSeasonHistory(gameState, targetSeason)

    local team = gameState:getPlayerTeam()
    local teamId = gameState.playerTeamId
    local playerLeagueKey = record and findPlayerLeagueKey(record, teamId)

    local content = {}

    -- ====== 标题 ======
    table.insert(content, UI.Panel {
        width = "100%", alignItems = "center", marginBottom = 12,
        children = {
            UI.Label { text = "赛季总结", fontSize = 20, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
            UI.Label { text = tostring(targetSeason) .. " - " .. tostring(targetSeason + 1) .. " 赛季",
                fontSize = 13, color = COLORS.TEXT_SECONDARY, marginTop = 2 },
        }
    })

    if not record then
        table.insert(content, Theme.Card { children = {
            UI.Label { text = "暂无此赛季的历史数据", fontSize = 13, color = COLORS.TEXT_MUTED }
        }})
    else
        -- ====== Tab 栏：本队总结 / 其他联赛 ======
        local tabs = {
            { key = "summary", label = "本队总结" },
            { key = "others",  label = "其他联赛" },
        }
        local tabButtons = {}
        for _, t in ipairs(tabs) do
            local isActive = (_activeTab == t.key)
            table.insert(tabButtons, UI.Panel {
                flex = 1, height = 36, justifyContent = "center", alignItems = "center",
                borderBottomWidth = isActive and 2 or 0,
                borderColor = isActive and COLORS.PRIMARY or COLORS.TRANSPARENT,
                onClick = function()
                    _activeTab = t.key
                    Router.replaceWith("season_end", params)
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
        table.insert(content, UI.Panel {
            width = "100%", height = 36, flexDirection = "row", marginBottom = 8,
            backgroundColor = COLORS.BG_HEADER, borderBottomWidth = 1, borderColor = COLORS.BORDER,
            children = tabButtons,
        })

        if _activeTab == "others" then
            for _, card in ipairs(buildOtherLeaguesSection(gameState, record, teamId, playerLeagueKey)) do
                table.insert(content, card)
            end
        else
            for _, card in ipairs(buildSummaryLeagueSection(gameState, record, teamId, playerLeagueKey)) do
                table.insert(content, card)
            end
        end
    end

    -- 以下卡片（董事会评价/奖金/财务/球员变动/球队数据）只与玩家球队自身相关，
    -- 与"多联赛铺开"问题无关，因此只在"本队总结" Tab 显示，避免"其他联赛" Tab 重复展示。
    if _activeTab == "summary" or not record then

    -- ====== 4. 董事会评价卡 ======
    if team then
        local satisfaction = team.boardSatisfaction or 50
        local objective = team.boardObjective or "未设定"

        -- 满意度颜色和评价
        local satColor, satLabel
        if satisfaction >= 75 then
            satColor = COLORS.SECONDARY
            satLabel = "非常满意"
        elseif satisfaction >= 50 then
            satColor = COLORS.WARNING
            satLabel = "基本满意"
        elseif satisfaction >= 25 then
            satColor = {255, 153, 0, 255}
            satLabel = "不太满意"
        else
            satColor = COLORS.DANGER
            satLabel = "极度不满"
        end

        -- 满意度进度条
        local barWidth = clamp(satisfaction, 0, 100)
        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "董事会评价" },
            UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", marginTop = 6, children = {
                UI.Label { text = "赛季目标:", fontSize = 12, color = COLORS.TEXT_MUTED, width = 70 },
                UI.Label { text = objective, fontSize = 13, color = COLORS.TEXT_PRIMARY, fontWeight = "bold" },
            }},
            UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", marginTop = 8, children = {
                UI.Label { text = "满意度:", fontSize = 12, color = COLORS.TEXT_MUTED, width = 70 },
                -- 进度条背景
                UI.Panel { flex = 1, height = 16, backgroundColor = {30, 36, 55, 255}, borderRadius = 8, overflow = "hidden", children = {
                    UI.Panel { width = tostring(barWidth) .. "%", height = "100%", backgroundColor = satColor, borderRadius = 8 },
                }},
                UI.Label { text = tostring(satisfaction) .. "%", fontSize = 12, color = satColor, fontWeight = "bold", marginLeft = 8, width = 40 },
            }},
            UI.Panel { width = "100%", marginTop = 6, children = {
                UI.Label { text = satLabel, fontSize = 12, color = satColor, fontWeight = "bold" },
                UI.Label {
                    text = satisfaction >= 75 and "董事会对你的工作非常认可，续约讨论已提上日程。" or
                           satisfaction >= 50 and "董事会认为你达成了基本预期，期待下赛季更进一步。" or
                           satisfaction >= 25 and "董事会对赛季成绩表示失望，下赛季需要改善。" or
                           "警告：如果下赛季初成绩没有起色，可能面临解雇。",
                    fontSize = 11, color = COLORS.TEXT_MUTED, marginTop = 2,
                },
            }},
        }})
    end

    -- ====== 5. 奖金明细卡 ======
    if team then
        local prizes = Constants.SEASON_END_PRIZE or {}
        local playerPosition = record and findPlayerLeaguePosition(record, teamId)
            or (gameState.league and gameState.league:getTeamPosition(teamId))
        local playerPrize = calcSeasonPrize(playerPosition)

        local prizeRows = {}
        -- 显示前5名奖金
        for i = 1, math.min(5, #prizes) do
            local isPlayer = (i == playerPosition)
            local rowPrize = prizes[i] or 0
            if i == 1 then rowPrize = rowPrize + CHAMPION_BONUS end
            table.insert(prizeRows, UI.Panel {
                width = "100%", height = 30, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8,
                backgroundColor = isPlayer and {33, 150, 243, 30} or COLORS.TRANSPARENT,
                children = {
                    UI.Label { text = "第" .. tostring(i) .. "名", width = 50, fontSize = 11, color = COLORS.TEXT_MUTED },
                    UI.Label { text = formatMoney(rowPrize), flex = 1, fontSize = 12,
                        color = isPlayer and COLORS.PRIMARY or COLORS.TEXT_PRIMARY,
                        fontWeight = isPlayer and "bold" or "normal" },
                }
            })
        end

        if playerPosition then
            local prizeDetail = playerPosition == 1
                and string.format("（含排名奖 %s + 冠军奖 %s）",
                    formatMoney(prizes[playerPosition] or 100000), formatMoney(CHAMPION_BONUS))
                or ""
            table.insert(prizeRows, UI.Panel {
                width = "100%", marginTop = 6, paddingHorizontal = 8, children = {
                    UI.Label {
                        text = string.format("你的球队第%d名，获得奖金 %s%s",
                            playerPosition, formatMoney(playerPrize), prizeDetail),
                        fontSize = 12, color = COLORS.SECONDARY, fontWeight = "bold",
                    }
                }
            })
        end

        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "联赛奖金分配 💰" },
            table.unpack(prizeRows)
        }})
    end

    -- ====== 6. 财务总结卡 ======
    if team then
        local finance = record and record.playerFinance
        local income = finance and finance.seasonIncome or team.seasonIncome or 0
        local expense = finance and finance.seasonExpense or team.seasonExpense or 0
        local balance = finance and finance.balance or team.balance or 0
        local wageBudget = finance and finance.wageBudget or team.wageBudget or 0
        local net = income - expense
        local netColor = net >= 0 and COLORS.SECONDARY or COLORS.DANGER
        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "财务总结" },
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
                Theme.StatPill { label = "总收入", value = formatMoney(income), valueColor = COLORS.SECONDARY },
                Theme.StatPill { label = "总支出", value = formatMoney(expense), valueColor = COLORS.DANGER },
                Theme.StatPill { label = "净收支", value = (net >= 0 and "+" or "-") .. formatMoney(math.abs(net)), valueColor = netColor },
            }},
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 6, children = {
                Theme.StatPill { label = "余额", value = formatMoney(balance) },
                Theme.StatPill { label = "工资预算", value = formatMoney(wageBudget) },
            }},
        }})
    end

    -- ====== 7. 球员变动摘要卡 (退役/合同到期/老化) ======
    if team then
        local retiredPlayers = {}
        local agedPlayers = {}    -- 30岁以上且下降的
        local expiredPlayers = {} -- 合同即将到期（下赛季结束）

        for _, pid in ipairs(team.playerIds or {}) do
            local p = gameState.players[pid]
            if not p then goto nextPlayer end

            local age = p:getAge(gameState.date.year)

            -- 记录老将（32岁+）
            if age >= 32 then
                table.insert(agedPlayers, { player = p, age = age })
            end

            -- 合同在下赛季结束的球员
            if p.contractEnd then
                local endYear = p.contractEnd.year or 9999
                if endYear <= gameState.date.year + 1 then
                    table.insert(expiredPlayers, p)
                end
            end

            ::nextPlayer::
        end

        -- 记录本赛季退役的球员（通过消息记录或 history）
        local retiredThisSeason = {}
        if record and record.retiredPlayers then
            retiredThisSeason = record.retiredPlayers
        else
            -- 从 gameState 中寻找退役球员
            for _, p in pairs(gameState.players) do
                if p.retired and p.teamId == nil then
                    -- 简单判断：最近退役的
                    local age = p:getAge(gameState.date.year)
                    if age >= (Constants.RETIREMENT_MIN_AGE or 33) then
                        table.insert(retiredThisSeason, { name = p.displayName, age = age, position = p.position })
                        if #retiredThisSeason >= 5 then break end
                    end
                end
            end
        end

        local changeRows = {}

        -- 退役球员
        if #retiredThisSeason > 0 then
            table.insert(changeRows, UI.Label { text = "退役球员", fontSize = 12, fontWeight = "bold", color = COLORS.DANGER, marginTop = 4, marginBottom = 4 })
            for _, info in ipairs(retiredThisSeason) do
                local name = type(info) == "table" and (info.name or info.playerName or "?") or tostring(info)
                local ageStr = type(info) == "table" and info.age and (" (" .. tostring(info.age) .. "岁)") or ""
                table.insert(changeRows, UI.Panel {
                    width = "100%", height = 28, flexDirection = "row", alignItems = "center", paddingHorizontal = 8,
                    children = {
                        UI.Label { text = "🔴", width = 20, fontSize = 10 },
                        UI.Label { text = name .. ageStr, flex = 1, fontSize = 12, color = COLORS.TEXT_SECONDARY },
                    }
                })
            end
        end

        -- 老将预警
        if #agedPlayers > 0 then
            table.insert(changeRows, UI.Label { text = "老将预警 (32岁+)", fontSize = 12, fontWeight = "bold", color = COLORS.WARNING, marginTop = 8, marginBottom = 4 })
            -- 按年龄降序
            table.sort(agedPlayers, function(a, b) return a.age > b.age end)
            for i = 1, math.min(5, #agedPlayers) do
                local info = agedPlayers[i]
                local p = info.player
                table.insert(changeRows, UI.Panel {
                    width = "100%", height = 28, flexDirection = "row", alignItems = "center", paddingHorizontal = 8,
                    onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                    children = {
                        UI.Label { text = "⚠️", width = 20, fontSize = 10 },
                        UI.Label { text = p.displayName, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                        UI.Label { text = tostring(info.age) .. "岁", width = 40, fontSize = 11, color = COLORS.WARNING },
                        UI.Label { text = "OVR " .. tostring(p.overall or 0), width = 50, fontSize = 11, color = COLORS.TEXT_MUTED },
                    }
                })
            end
            if #agedPlayers > 5 then
                table.insert(changeRows, UI.Label { text = string.format("... 共%d名老将", #agedPlayers), fontSize = 11, color = COLORS.TEXT_MUTED, paddingLeft = 28, marginTop = 2 })
            end
        end

        -- 合同即将到期
        if #expiredPlayers > 0 then
            table.insert(changeRows, UI.Label { text = "合同即将到期 (下赛季末)", fontSize = 12, fontWeight = "bold", color = {255, 153, 0, 255}, marginTop = 8, marginBottom = 4 })
            for i = 1, math.min(5, #expiredPlayers) do
                local p = expiredPlayers[i]
                table.insert(changeRows, UI.Panel {
                    width = "100%", height = 28, flexDirection = "row", alignItems = "center", paddingHorizontal = 8,
                    onClick = function() Router.navigate("player_detail", { playerId = p.id }) end,
                    children = {
                        UI.Label { text = "📋", width = 20, fontSize = 10 },
                        ---@diagnostic disable-next-line: param-type-mismatch
                        UI.Label { text = p.displayName, flex = 1, fontSize = 12, color = COLORS.TEXT_PRIMARY },
                        UI.Label { text = "OVR " .. tostring(p.overall or 0), width = 50, fontSize = 11, color = COLORS.TEXT_MUTED },
                        UI.Label { text = formatMoney(p.wage) .. "/周", width = 60, fontSize = 10, color = COLORS.TEXT_SECONDARY },
                    }
                })
            end
            if #expiredPlayers > 5 then
                table.insert(changeRows, UI.Label { text = string.format("... 共%d人合同将到期", #expiredPlayers), fontSize = 11, color = COLORS.TEXT_MUTED, paddingLeft = 28, marginTop = 2 })
            end
        end

        if #changeRows > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "球员变动摘要" },
                table.unpack(changeRows)
            }})
        end
    end

    -- ====== 8. 球队赛季数据卡 ======
    if team then
        local stats = team.seasonStats or {}
        local played = (stats.wins or 0) + (stats.draws or 0) + (stats.losses or 0)
        if played > 0 then
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = "球队赛季数据" },
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 6, children = {
                    Theme.StatPill { label = "场次", value = tostring(played) },
                    Theme.StatPill { label = "胜", value = tostring(stats.wins or 0), valueColor = COLORS.SECONDARY },
                    Theme.StatPill { label = "平", value = tostring(stats.draws or 0) },
                    Theme.StatPill { label = "负", value = tostring(stats.losses or 0), valueColor = COLORS.DANGER },
                }},
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 6, children = {
                    Theme.StatPill { label = "进球", value = tostring(stats.goalsFor or 0), valueColor = COLORS.SECONDARY },
                    Theme.StatPill { label = "失球", value = tostring(stats.goalsAgainst or 0), valueColor = COLORS.DANGER },
                    Theme.StatPill { label = "净胜", value = tostring((stats.goalsFor or 0) - (stats.goalsAgainst or 0)) },
                }},
            }})
        end
    end

    end -- if _activeTab == "summary" or not record

    -- ====== 继续按钮 ======
    table.insert(content, UI.Panel {
        width = "100%", marginTop = 16, marginBottom = 20,
        children = {
            Theme.PrimaryButton { text = "进入新赛季 →", onClick = function()
                Router.navigate("dashboard")
            end},
            UI.Panel { height = 8 },
            Theme.SecondaryButton { text = "查看名人堂", onClick = function()
                Router.navigate("hall_of_fame")
            end},
        }
    })

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = COLORS.BG_DARK,
        children = {
            Theme.TopBar { children = {
                UI.Panel { width = 60, height = 32, justifyContent = "center", onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } } },
                UI.Label { text = "赛季结算", fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
                UI.Panel { width = 60 },
            }},
            UI.ScrollView {
                width = "100%", flex = 1,
                children = {
                    UI.Panel { width = "100%", padding = 12, children = content }
                }
            },
        }
    }
end

return SeasonEnd
