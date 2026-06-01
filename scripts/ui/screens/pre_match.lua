-- ui/screens/pre_match.lua
-- 赛前阵容确认与战术设置

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TeamIcon = require("scripts/ui/components/team_icon")
local AIManager = require("scripts/systems/ai_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local PreMatch = {}

-- 阵型位置映射 (x%, y% 从底到顶)
local FORMATION_POSITIONS = {
    ["4-4-2"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {38, 55}, {62, 55}, {85, 52}, {35, 80}, {65, 80},
    },
    ["4-3-3"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {30, 52}, {50, 55}, {70, 52}, {20, 80}, {50, 82}, {80, 80},
    },
    ["3-5-2"] = {
        {50, 5}, {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 58}, {67, 55}, {90, 50}, {35, 80}, {65, 80},
    },
    ["4-2-3-1"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 48}, {65, 48}, {20, 68}, {50, 70}, {80, 68}, {50, 85},
    },
    ["5-3-2"] = {
        {50, 5}, {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {50, 55}, {70, 52}, {35, 80}, {65, 80},
    },
    ["4-5-1"] = {
        {50, 5}, {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 55}, {50, 58}, {67, 55}, {85, 50}, {50, 82},
    },
}

function PreMatch.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无数据", color = Theme.COLORS.TEXT_SECONDARY } }
        }
    end

    local fixture = params and params.fixture
    if not fixture then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无比赛安排", color = Theme.COLORS.TEXT_SECONDARY } }
        }
    end

    -- 世界杯比赛：用虚拟国家队对象
    local team, opponent, isHome, oppName
    if fixture._isWC then
        local WorldCup = require("scripts/systems/world_cup")
        local playerNation = WorldCup._getPlayerNation(gameState)
        team = WorldCup.buildNationalTeam(gameState, playerNation)
        local oppCode = (fixture.homeTeamId == playerNation) and fixture.awayTeamId or fixture.homeTeamId
        opponent = WorldCup.buildNationalTeam(gameState, oppCode)
        isHome = fixture.homeTeamId == playerNation
        oppName = opponent and opponent.name or WorldCup._getNationName(oppCode)
    else
        team = gameState:getPlayerTeam()
        local oppId = fixture.homeTeamId == team.id and fixture.awayTeamId or fixture.homeTeamId
        opponent = gameState.teams[oppId]
        isHome = fixture.homeTeamId == team.id
        oppName = opponent and opponent.name or "对手"
    end

    if not team then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无比赛安排", color = Theme.COLORS.TEXT_SECONDARY } }
        }
    end

    -- 构建首发+替补列表
    local startingXI = {}
    local bench = {}
    if team.startingXI and #team.startingXI > 0 then
        for _, pid in ipairs(team.startingXI) do
            local p = gameState.players[pid]
            if p and not p.injured then
                table.insert(startingXI, p)
            end
        end
    end
    -- 替补：球队中非首发的健康球员
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured then
            local inStarting = false
            for _, sp in ipairs(startingXI) do
                if sp.id == p.id then inStarting = true; break end
            end
            if not inStarting then
                table.insert(bench, p)
            end
        end
    end
    -- 按 overall 排序替补
    table.sort(bench, function(a, b) return a.overall > b.overall end)

    -- 不可用球员（伤病）
    local unavailable = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and p.injured then
            table.insert(unavailable, p)
        end
    end

    -- 球场视图（点击球员可换人）
    local formation = team.formation or "4-4-2"
    local pitchView = PreMatch._buildPitchView(startingXI, formation, gameState, team, fixture)

    -- 首发列表
    local startingRows = {}
    for i, p in ipairs(startingXI) do
        table.insert(startingRows, PreMatch._playerRow(i, p, true, team, gameState, fixture))
    end

    -- 替补列表（最多7人）
    local benchRows = {}
    local benchMax = math.min(#bench, 7)
    for i = 1, benchMax do
        table.insert(benchRows, PreMatch._playerRow(i, bench[i], false, team, gameState, fixture))
    end

    -- 不可用列表
    local unavailRows = {}
    for _, p in ipairs(unavailable) do
        table.insert(unavailRows, UI.Panel {
            width = "100%", height = 32, flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            children = {
                UI.Label { text = "🏥", fontSize = 12, width = 22 },
                UI.Label { text = p.displayName, fontSize = 12, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = tostring(p.injuryDays or "?") .. "天", fontSize = 11, color = Theme.COLORS.DANGER, width = 40 },
            }
        })
    end

    -- 战术提示
    local tacticsInfo = string.format("阵型 %s · %s",
        formation, Constants.PLAY_STYLE_NAMES[team.playStyle] or team.playStyle or "平衡")

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            -- 保持比赛待处理状态，记录到 gameState 方便 dashboard 识别
                            gameState.pendingPlayerFixture = fixture
                            Router.replaceWith("dashboard")
                        end,
                    },
                    UI.Label {
                        text = "赛前准备", fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                        flexGrow = 1, textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- 赛事信息
            UI.Panel {
                width = "100%", paddingLeft = 16, paddingRight = 16,
                paddingTop = 10, paddingBottom = 10,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 110, flexDirection = "row",
                                justifyContent = "flex-end", alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = isHome and team.name or oppName,
                                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                        textAlign = "right", flexShrink = 1,
                                    },
                                    TeamIcon {
                                        team = isHome and team or opponent,
                                        size = 28, marginLeft = 6,
                                    },
                                },
                            },
                            UI.Label {
                                text = " vs ",
                                fontSize = 14, color = Theme.COLORS.TEXT_MUTED,
                                width = 40, textAlign = "center",
                            },
                            UI.Panel {
                                width = 110, flexDirection = "row",
                                alignItems = "center",
                                children = {
                                    TeamIcon {
                                        team = isHome and opponent or team,
                                        size = 28, marginRight = 6,
                                    },
                                    UI.Label {
                                        text = isHome and oppName or team.name,
                                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                        flexShrink = 1,
                                    },
                                },
                            },
                        }
                    },
                    UI.Label {
                        text = (isHome and "主场" or "客场") .. " · " .. tacticsInfo,
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        textAlign = "center", marginTop = 4,
                    },
                }
            },

            -- 主内容
            UI.ScrollView {
                flexGrow = 1, flexBasis = 0, scrollY = true, padding = 14,
                children = {
                    -- 球场视图
                    pitchView,

                    -- 首发11人
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = string.format("首发阵容 (%d/11)", #startingXI) },
                            UI.Panel { width = "100%", marginTop = 4, children = startingRows },
                        }
                    },

                    -- 替补
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = string.format("替补席 (%d)", benchMax) },
                            UI.Panel { width = "100%", marginTop = 4, children = benchRows },
                        }
                    },

                    -- 不可用
                    (#unavailable > 0) and Theme.Card {
                        children = {
                            Theme.Subtitle { text = string.format("不可用 (%d)", #unavailable) },
                            UI.Panel { width = "100%", marginTop = 4, children = unavailRows },
                        }
                    } or nil,

                    -- 阵型切换（快捷）
                    PreMatch._formationQuickSwitch(team, fixture),
                }
            },

            -- 底部操作按钮
            UI.Panel {
                width = "100%", paddingLeft = 16, paddingRight = 16,
                paddingTop = 10, paddingBottom = 14,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    -- 赛前训话按钮
                    UI.Button {
                        text = "赛前训话",
                        width = "100%", height = 40,
                        backgroundColor = {100, 60, 30, 255},
                        borderRadius = 8, marginBottom = 8,
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            Router.navigate("team_talk", {
                                context = "pre_match",
                                returnTo = "pre_match",
                                returnParams = { fixture = fixture },
                            })
                        end,
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Button {
                                text = "战术",
                                width = "22%", height = 44,
                                backgroundColor = Theme.COLORS.BG_CARD,
                                borderRadius = 8, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                                fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY,
                                onClick = function()
                                    Router.navigate("tactics", { returnTo = "pre_match", fixture = fixture })
                                end,
                            },
                            UI.Button {
                                text = "模拟跳过",
                                width = "26%", height = 44,
                                backgroundColor = {60, 40, 40, 255},
                                borderRadius = 8, borderWidth = 1, borderColor = Theme.COLORS.DANGER,
                                fontSize = 13, color = Theme.COLORS.DANGER,
                                onClick = function()
                                    PreMatch._confirmLeave(gameState, team, fixture)
                                end,
                            },
                            UI.Button {
                                text = "确认出战 ▶",
                                width = "48%", height = 44,
                                backgroundColor = Theme.COLORS.SECONDARY,
                                borderRadius = 8,
                                fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                onClick = function()
                                    -- 清除待处理标记
                                    gameState.pendingPlayerFixture = nil
                                    -- 创建步进式比赛会话
                                    local MatchEngine = require("scripts/match/match_engine")
                                    local session = MatchEngine.startMatch(gameState, fixture)
                                    if session then
                                        Router.replaceWith("match_live", { session = session, fixture = fixture })
                                    else
                                        Router.navigate("dashboard")
                                    end
                                end,
                            },
                        }
                    },
                }
            },
        }
    }
end

---------------------------------------------------------------------------
-- 返回确认：自动模拟比赛
---------------------------------------------------------------------------
function PreMatch._confirmLeave(gameState, team, fixture)
    BottomSheet.showCustom({
        title = "离开赛前准备",
        height = 200,
        showCancel = true,
        children = {
            UI.Label {
                text = "离开后比赛将自动模拟（AI托管），确定要跳过吗？",
                fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 16,
            },
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between",
                children = {
                    UI.Button {
                        text = "取消", width = "45%", height = 40,
                        backgroundColor = Theme.COLORS.BG_CARD,
                        borderRadius = 8, borderWidth = 1, borderColor = Theme.COLORS.BORDER,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() BottomSheet.close() end,
                    },
                    UI.Button {
                        text = "跳过比赛", width = "45%", height = 40,
                        backgroundColor = Theme.COLORS.DANGER,
                        borderRadius = 8,
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                        onClick = function()
                            BottomSheet.close()
                            -- 清除待处理标记
                            gameState.pendingPlayerFixture = nil
                            -- 自动模拟比赛
                            local MatchEngine = require("scripts/match/match_engine")
                            local report = MatchEngine.simulate(gameState, fixture)
                            if report then
                                if fixture._isWC then
                                    local TurnProcessor = require("scripts/core/turn_processor")
                                    TurnProcessor._applyWCResult(gameState, fixture, report)
                                else
                                    MatchEngine.applyResult(gameState, fixture, report)
                                end
                                -- 发送比赛结果消息
                                local homeName, awayName
                                if fixture._isWC then
                                    local WorldCup = require("scripts/systems/world_cup")
                                    homeName = WorldCup._getNationName(fixture.homeTeamId)
                                    awayName = WorldCup._getNationName(fixture.awayTeamId)
                                else
                                    local homeTeam = gameState.teams[fixture.homeTeamId]
                                    local awayTeam = gameState.teams[fixture.awayTeamId]
                                    homeName = homeTeam and homeTeam.name or "主队"
                                    awayName = awayTeam and awayTeam.name or "客队"
                                end
                                gameState:sendMessage({
                                    category = "match_result",
                                    title = "比赛结果（模拟）",
                                    body = string.format("%s %d - %d %s",
                                        homeName, report.homeGoals, report.awayGoals, awayName),
                                    priority = "high",
                                })
                            end
                            Router.replaceWith("dashboard")
                        end,
                    },
                }
            },
        },
    })
end

---------------------------------------------------------------------------
-- 球场视图（缩略版）
---------------------------------------------------------------------------
function PreMatch._buildPitchView(startingXI, formation, gameState, team, fixture)
    local positions = FORMATION_POSITIONS[formation] or FORMATION_POSITIONS["4-4-2"]
    local slots = AIManager._getFormationSlots(formation, team and team.formationVariant or nil)
    local pitchW = 260
    local pitchH = 340

    local dots = {}
    for i, pos in ipairs(positions) do
        local px = pos[1]
        local py = pos[2]
        local left = math.floor(px / 100 * pitchW) - 14
        local top = math.floor((100 - py) / 100 * pitchH) - 14

        local player = startingXI[i]
        local label = player and string.sub(player.displayName, 1, 4) or "?"
        local ovr = player and tostring(player.overall) or ""
        local dotColor = i == 1 and {255, 204, 0, 255} or Theme.COLORS.PRIMARY
        -- 低体能警告
        if player and player.fitness < 70 then
            dotColor = Theme.COLORS.WARNING
        end

        local slotIdx = i
        table.insert(dots, UI.Panel {
            position = "absolute", left = left, top = top,
            width = 28, height = 28, borderRadius = 14,
            backgroundColor = dotColor,
            justifyContent = "center", alignItems = "center",
            onClick = function()
                PreMatch._showSlotSwapSheet(gameState, team, slotIdx, slots, fixture)
            end,
            children = {
                UI.Label { text = label, fontSize = 7, color = {255, 255, 255, 255}, textAlign = "center" },
            },
        })
    end

    -- 球场线条
    local fieldLines = {
        UI.Panel {
            position = "absolute", left = 0, top = math.floor(pitchH / 2) - 1,
            width = pitchW, height = 1, backgroundColor = {255, 255, 255, 40},
        },
        UI.Panel {
            position = "absolute",
            left = math.floor(pitchW / 2) - 25, top = math.floor(pitchH / 2) - 25,
            width = 50, height = 50, borderRadius = 25,
            borderWidth = 1, borderColor = {255, 255, 255, 40},
            backgroundColor = Theme.COLORS.TRANSPARENT,
        },
    }

    local pitchChildren = {}
    for _, l in ipairs(fieldLines) do table.insert(pitchChildren, l) end
    for _, d in ipairs(dots) do table.insert(pitchChildren, d) end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "阵型预览 · " .. formation },
            UI.Panel {
                width = pitchW, height = pitchH,
                backgroundColor = {20, 80, 40, 255},
                borderRadius = 8, borderWidth = 2, borderColor = {255, 255, 255, 60},
                alignSelf = "center", marginTop = 6,
                children = pitchChildren,
            },
        }
    }
end

---------------------------------------------------------------------------
-- 球场点击换人：点击某个位置弹出候选列表（复用战术页逻辑）
---------------------------------------------------------------------------
function PreMatch._showSlotSwapSheet(gameState, team, slotIdx, slots, fixture)
    local startingXI = team.startingXI or {}
    local currentPid = startingXI[slotIdx]
    local currentPlayer = currentPid and gameState.players[currentPid]
    local slotPos = slots[slotIdx] or "MID"

    -- 收集候选球员
    local benchCandidates = {}
    local swapCandidates = {}

    local startingSet = {}
    for _, pid in ipairs(startingXI) do
        startingSet[pid] = true
    end

    -- 板凳球员（不在首发中，未伤停）
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not startingSet[pid] and not p.injured and not p.suspended then
            local score = AIManager._playerPositionScore(p, slotPos)
            table.insert(benchCandidates, { player = p, score = score, source = "bench" })
        end
    end

    -- 其他首发（位置互换）
    for i, pid in ipairs(startingXI) do
        if i ~= slotIdx then
            local p = gameState.players[pid]
            if p then
                local score = AIManager._playerPositionScore(p, slotPos)
                table.insert(swapCandidates, { player = p, score = score, index = i, source = "swap" })
            end
        end
    end

    table.sort(benchCandidates, function(a, b) return a.score > b.score end)
    table.sort(swapCandidates, function(a, b) return a.score > b.score end)

    -- 构建弹窗内容
    local children = {}

    local posLabel = Constants.POSITION_NAMES[slotPos] or slotPos
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 10,
        children = {
            UI.Label {
                text = string.format("位置 #%d: %s", slotIdx, posLabel),
                fontSize = 14, fontWeight = "bold", color = Theme.COLORS.ACCENT, flexGrow = 1,
            },
            currentPlayer and UI.Label {
                text = "当前: " .. currentPlayer.displayName .. " (" .. currentPlayer.overall .. ")",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            } or nil,
        }
    })

    -- 板凳球员列表
    if #benchCandidates > 0 then
        table.insert(children, UI.Label {
            text = "替补球员", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginTop = 6, marginBottom = 4,
        })
        local maxBench = math.min(8, #benchCandidates)
        for i = 1, maxBench do
            local c = benchCandidates[i]
            local p = c.player
            local scoreColor = c.score >= 80 and Theme.COLORS.SECONDARY
                or (c.score >= 60 and Theme.COLORS.ACCENT or Theme.COLORS.TEXT_MUTED)
            table.insert(children, UI.Button {
                text = string.format("%s  %s  能力%d  适配%d",
                    Constants.POSITION_NAMES[p.position] or p.position,
                    p.displayName, p.overall, math.floor(c.score)),
                width = "100%", height = 36, marginBottom = 2,
                backgroundColor = {38, 46, 71, 255}, borderRadius = 6,
                fontSize = 12, textAlign = "left", paddingLeft = 10,
                color = scoreColor,
                onClick = function()
                    team.startingXI[slotIdx] = p.id
                    BottomSheet.close()
                    Router.replaceWith("pre_match", { fixture = fixture })
                end,
            })
        end
    end

    -- 位置互换
    if #swapCandidates > 0 then
        table.insert(children, UI.Label {
            text = "位置互换（与其他首发交换）", fontSize = 12, fontWeight = "bold",
            color = Theme.COLORS.TEXT_SECONDARY, marginTop = 10, marginBottom = 4,
        })
        local maxSwap = math.min(5, #swapCandidates)
        for i = 1, maxSwap do
            local c = swapCandidates[i]
            local p = c.player
            local otherSlotPos = slots[c.index] or "?"
            table.insert(children, UI.Button {
                text = string.format("↔ %s (%s #%d, 能力%d)",
                    p.displayName,
                    Constants.POSITION_NAMES[otherSlotPos] or otherSlotPos,
                    c.index, p.overall),
                width = "100%", height = 36, marginBottom = 2,
                backgroundColor = {50, 40, 60, 255}, borderRadius = 6,
                fontSize = 12, textAlign = "left", paddingLeft = 10,
                color = {180, 160, 220, 255},
                onClick = function()
                    local tmp = team.startingXI[slotIdx]
                    team.startingXI[slotIdx] = team.startingXI[c.index]
                    team.startingXI[c.index] = tmp
                    BottomSheet.close()
                    Router.replaceWith("pre_match", { fixture = fixture })
                end,
            })
        end
    end

    local sheetHeight = 120 + math.min(8, #benchCandidates) * 38 + math.min(5, #swapCandidates) * 38 + 60
    sheetHeight = math.min(sheetHeight, 600)

    BottomSheet.showCustom({
        title = "更换球员 — " .. posLabel,
        height = sheetHeight,
        showCancel = true,
        children = children,
    })
end

---------------------------------------------------------------------------
-- 球员行（支持拖入/移出首发）
---------------------------------------------------------------------------
function PreMatch._playerRow(idx, player, isStarter, team, gameState, fixture)
    local fitnessColor = Theme.COLORS.SECONDARY
    if player.fitness < 70 then fitnessColor = Theme.COLORS.WARNING end
    if player.fitness < 50 then fitnessColor = Theme.COLORS.DANGER end

    local posLabel = Constants.POSITION_NAMES[player.position] or player.position or "?"

    return UI.Panel {
        width = "100%", height = 40, flexDirection = "row",
        alignItems = "center", paddingLeft = 8, paddingRight = 8,
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            -- 序号
            UI.Label { text = tostring(idx), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
            -- 位置
            UI.Label { text = posLabel, fontSize = 11, color = Theme.COLORS.ACCENT, width = 40 },
            -- 名字
            UI.Label { text = player.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1 },
            -- 体能
            UI.Label { text = tostring(player.fitness) .. "%", fontSize = 11, color = fitnessColor, width = 36 },
            -- OVR
            UI.Label {
                text = tostring(player.overall), fontSize = 13, fontWeight = "bold",
                color = player.overall >= 70 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_SECONDARY,
                width = 28,
            },
            -- 操作：调换到替补/调入首发
            UI.Button {
                text = isStarter and "↓" or "↑",
                width = 28, height = 28, borderRadius = 14,
                backgroundColor = isStarter and {80, 40, 40, 255} or {40, 80, 40, 255},
                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    if isStarter then
                        -- 从首发移除
                        local xi = team.startingXI or {}
                        for i, pid in ipairs(xi) do
                            if pid == player.id then
                                table.remove(xi, i)
                                break
                            end
                        end
                    else
                        -- 加入首发（限制11人）
                        local xi = team.startingXI or {}
                        if #xi < 11 then
                            table.insert(xi, player.id)
                        end
                    end
                    Router.replaceWith("pre_match", { fixture = fixture })
                end,
            },
        }
    }
end

---------------------------------------------------------------------------
-- 阵型快捷切换
---------------------------------------------------------------------------
function PreMatch._formationQuickSwitch(team, fixture)
    local currentFormation = team.formation or "4-4-2"
    local buttons = {}
    for _, fmt in ipairs(Constants.FORMATIONS) do
        local isActive = fmt == currentFormation
        table.insert(buttons, UI.Button {
            text = fmt,
            width = "30%", height = 36,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_CARD,
            borderRadius = 8, borderWidth = isActive and 0 or 1, borderColor = Theme.COLORS.BORDER,
            fontSize = 13, color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal", marginBottom = 6,
            onClick = function()
                if not isActive then
                    team.formation = fmt
                    Router.replaceWith("pre_match", { fixture = fixture })
                end
            end,
        })
    end

    return Theme.Card {
        children = {
            Theme.Subtitle { text = "快捷阵型切换" },
            UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap",
                justifyContent = "space-between", marginTop = 4,
                children = buttons,
            },
        }
    }
end

return PreMatch
