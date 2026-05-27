--- 赛季结算页 - 展示赛季总结（排名/奖项/财务/董事会评价/球员变动）
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local Constants = require("scripts/app/constants")
local HistoryManager = require("scripts/systems/history_manager")

local COLORS = Theme.COLORS

local SeasonEnd = {}

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
    if not amount then return "0" end
    if amount >= 1000000 then return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then return string.format("%.0fK", amount / 1000)
    else return tostring(amount) end
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

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
        -- ====== 1. 联赛排名卡 ======
        for leagueKey, leagueRecord in pairs(record.leagues or {}) do
            local standingRows = {}
            local playerPosition = nil

            for i, entry in ipairs(leagueRecord.standings or {}) do
                if i > 5 and entry.teamId ~= teamId then goto continue end

                local isPlayer = (entry.teamId == teamId)
                if isPlayer then playerPosition = i end
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
            table.insert(content, Theme.Card { children = {
                Theme.Subtitle { text = (leagueRecord.name or leagueKey) .. " 最终排名" },
                UI.Label { text = champText, fontSize = 12, fontWeight = "bold", color = COLORS.WARNING, marginTop = 2, marginBottom = 6 },
                table.unpack(standingRows)
            }})

            -- 排名评价
            if playerPosition then
                local posText
                if playerPosition == 1 then posText = "恭喜！你获得了联赛冠军！🏆"
                elseif playerPosition <= 3 then posText = "出色！球队获得第" .. tostring(playerPosition) .. "名，进入欧冠区域。"
                elseif playerPosition <= 6 then posText = "中规中矩，第" .. tostring(playerPosition) .. "名。"
                elseif playerPosition <= 10 then posText = "赛季排名第" .. tostring(playerPosition) .. "，还有提升空间。"
                else posText = "第" .. tostring(playerPosition) .. "名，下赛季需要努力了。" end

                table.insert(content, Theme.Card { children = {
                    UI.Label { text = posText, fontSize = 13, color = playerPosition <= 3 and COLORS.WARNING or COLORS.TEXT_PRIMARY },
                }})
            end
        end

        -- ====== 2. 赛季奖项卡 ======
        local awards = record.awards
        if awards and awards.leagues then
            local awardRows = {}
            for _, la in pairs(awards.leagues) do
                if la.goldenBoot then
                    table.insert(awardRows, SeasonEnd._awardRow("金靴奖", la.goldenBoot.playerName, tostring(la.goldenBoot.goals or 0) .. " 球", la.goldenBoot.playerId))
                end
                if la.bestPlayer then
                    table.insert(awardRows, SeasonEnd._awardRow("最佳球员", la.bestPlayer.playerName, "评分 " .. string.format("%.1f", la.bestPlayer.rating or 0), la.bestPlayer.playerId))
                end
                if la.bestYoungPlayer then
                    table.insert(awardRows, SeasonEnd._awardRow("最佳新秀", la.bestYoungPlayer.playerName, tostring(la.bestYoungPlayer.age or 0) .. " 岁", la.bestYoungPlayer.playerId))
                end
                if la.bestAssist then
                    table.insert(awardRows, SeasonEnd._awardRow("助攻王", la.bestAssist.playerName, tostring(la.bestAssist.assists or 0) .. " 助攻", la.bestAssist.playerId))
                end
                if la.bestGK then
                    table.insert(awardRows, SeasonEnd._awardRow("金手套", la.bestGK.playerName, tostring(la.bestGK.cleanSheets or 0) .. " 零封", la.bestGK.playerId))
                end
            end
            if awards.bestManager then
                table.insert(awardRows, SeasonEnd._awardRow("最佳经理", awards.bestManager.name or "?", "", nil))
            end
            if #awardRows > 0 then
                table.insert(content, Theme.Card { children = {
                    Theme.Subtitle { text = "赛季奖项 🏅" },
                    table.unpack(awardRows)
                }})
            end
        end

        -- ====== 3. 关键转会卡 ======
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
    end

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
        local playerLeague = gameState.league
        local playerPosition = playerLeague and playerLeague:getTeamPosition(teamId)
        local playerPrize = playerPosition and (prizes[playerPosition] or 100000) or 0

        local prizeRows = {}
        -- 显示前5名奖金
        for i = 1, math.min(5, #prizes) do
            local isPlayer = (i == playerPosition)
            table.insert(prizeRows, UI.Panel {
                width = "100%", height = 30, flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8,
                backgroundColor = isPlayer and {33, 150, 243, 30} or COLORS.TRANSPARENT,
                children = {
                    UI.Label { text = "第" .. tostring(i) .. "名", width = 50, fontSize = 11, color = COLORS.TEXT_MUTED },
                    UI.Label { text = formatMoney(prizes[i]), flex = 1, fontSize = 12,
                        color = isPlayer and COLORS.PRIMARY or COLORS.TEXT_PRIMARY,
                        fontWeight = isPlayer and "bold" or "normal" },
                }
            })
        end

        if playerPosition then
            table.insert(prizeRows, UI.Panel {
                width = "100%", marginTop = 6, paddingHorizontal = 8, children = {
                    UI.Label {
                        text = string.format("你的球队第%d名，获得奖金 %s", playerPosition, formatMoney(playerPrize)),
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
        local income = team.seasonIncome or 0
        local expense = team.seasonExpense or 0
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
                Theme.StatPill { label = "余额", value = formatMoney(team.balance or 0) },
                Theme.StatPill { label = "工资预算", value = formatMoney(team.wageBudget or 0) },
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

return SeasonEnd
