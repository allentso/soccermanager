-- ui/screens/pre_match.lua
-- 赛前阵容确认与战术设置

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TeamIcon = require("scripts/ui/components/team_icon")
local AIManager = require("scripts/systems/ai_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local SaveManager = require("scripts/persistence/save_manager")
local TransferManager = require("scripts/systems/transfer_manager")
local FormationShape = require("scripts/match/formation_shape")

local PreMatch = {}

--- 体力权重因子（与 tactics.lua 一致）
local function _fitnessFactor(fitness)
    fitness = fitness or 80
    if fitness >= 80 then return 1.0
    elseif fitness >= 70 then return 0.85 + (fitness - 70) * 0.015
    elseif fitness >= 60 then return 0.65 + (fitness - 60) * 0.02
    elseif fitness >= 50 then return 0.4 + (fitness - 50) * 0.025
    else return 0.2 + (fitness / 50) * 0.2
    end
end

--- 获取球员所属位置组
local function _positionGroup(pos)
    for group, positions in pairs(Constants.POSITION_GROUPS) do
        for _, p in ipairs(positions) do
            if p == pos then return group end
        end
    end
    return "MID"
end

--- 一键配置全阵容（首发+替补），综合位置适配和体力
local function _autoFullSquad(gameState, team)
    local formation = team.formation or "4-4-2"
    local slots = AIManager._getFormationSlots(formation, team.formationVariant)

    -- 收集全队可用球员
    local allAvailable = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured then
            table.insert(allAvailable, p)
        end
    end

    -- 贪心分配首发：每个槽位选位置适配×体力最优的球员
    local newXI = {}
    local usedIds = {}

    for _, slot in ipairs(slots) do
        local bestPlayer = nil
        local bestScore = -1

        for _, p in ipairs(allAvailable) do
            if not usedIds[p.id] then
                local score = AIManager._playerPositionScore(p, slot) * _fitnessFactor(p.fitness)
                if score > bestScore then
                    bestScore = score
                    bestPlayer = p
                end
            end
        end

        if bestPlayer then
            table.insert(newXI, bestPlayer.id)
            usedIds[bestPlayer.id] = true
        end
    end

    team.startingXI = newXI

    -- 替补：从剩余球员中选7人（确保位置覆盖）
    local remaining = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not usedIds[p.id] then
            table.insert(remaining, p)
        end
    end
    table.sort(remaining, function(a, b)
        return (a.overall * _fitnessFactor(a.fitness)) > (b.overall * _fitnessFactor(b.fitness))
    end)

    -- 确保位置覆盖
    local benchIds = {}
    local benchSet = {}
    local needGK, needDEF, needATK = true, true, true

    for _, p in ipairs(remaining) do
        if #benchIds >= 7 then break end
        local g = _positionGroup(p.position)
        local picked = false
        if needGK and g == "GK" and (p.fitness or 80) >= 50 then
            needGK = false; picked = true
        elseif needDEF and g == "DEF" and (p.fitness or 80) >= 50 then
            needDEF = false; picked = true
        elseif needATK and (g == "FWD" or g == "MID") and (p.fitness or 80) >= 50 then
            needATK = false; picked = true
        end
        if picked then
            table.insert(benchIds, p.id)
            benchSet[p.id] = true
        end
    end
    for _, p in ipairs(remaining) do
        if #benchIds >= 7 then break end
        if not benchSet[p.id] then
            table.insert(benchIds, p.id)
        end
    end

    team.benchIds = benchIds
end

-- 阵型变体位置坐标映射 (x%, y% 从球场左下角计算, y=0底部 y=100顶部)
-- 键: "阵型:变体key"，与 tactics.lua 保持一致
local FORMATION_POSITIONS = {
    -- 4-4-2
    ["4-4-2:flat"] = {
        {50, 5},   -- GK
        {15, 25}, {38, 28}, {62, 28}, {85, 25}, -- DEF
        {15, 52}, {38, 55}, {62, 55}, {85, 52}, -- MID
        {35, 80}, {65, 80},                      -- FWD
    },
    ["4-4-2:diamond"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 52}, {50, 45}, {50, 65}, {85, 52},
        {35, 80}, {65, 80},
    },

    -- 4-3-3
    ["4-3-3:hold"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {50, 42}, {65, 50},
        {20, 80}, {50, 82}, {80, 80},
    },
    ["4-3-3:attack"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 50}, {65, 50}, {50, 62},
        {20, 80}, {50, 82}, {80, 80},
    },

    -- 3-5-2
    ["3-5-2:default"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {33, 55}, {50, 48}, {67, 55}, {90, 50},
        {35, 80}, {65, 80},
    },
    ["3-5-2:attack"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {38, 52}, {62, 52}, {50, 64}, {90, 50},
        {35, 80}, {65, 80},
    },

    -- 3-4-3
    ["3-4-3:flat"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 50}, {38, 52}, {62, 52}, {90, 50},
        {20, 80}, {50, 84}, {80, 80},
    },
    ["3-4-3:stagger"] = {
        {50, 5},
        {25, 25}, {50, 28}, {75, 25},
        {10, 52}, {45, 46}, {55, 62}, {90, 52},
        {20, 80}, {50, 84}, {80, 80},
    },

    -- 4-2-3-1
    ["4-2-3-1:wide"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {80, 68}, {20, 68},
        {50, 85},
    },
    ["4-2-3-1:narrow"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {35, 45}, {65, 45},
        {50, 65}, {68, 63}, {32, 63},
        {50, 85},
    },

    -- 5-3-2
    ["5-3-2:flat"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {30, 52}, {50, 55}, {70, 52},
        {35, 80}, {65, 80},
    },
    ["5-3-2:hold"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {35, 52}, {50, 45}, {65, 52},
        {35, 80}, {65, 80},
    },

    -- 4-2-4
    ["4-2-4:flat"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {38, 52}, {62, 52},
        {18, 78}, {40, 84}, {60, 84}, {82, 78},
    },

    -- 4-5-1
    ["4-5-1:default"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {33, 55}, {50, 48}, {67, 55}, {85, 50},
        {50, 82},
    },
    ["4-5-1:diamond"] = {
        {50, 5},
        {15, 25}, {38, 28}, {62, 28}, {85, 25},
        {15, 50}, {50, 42}, {50, 62}, {67, 55}, {85, 50},
        {50, 82},
    },

    -- 5-4-1
    ["5-4-1:flat"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {15, 52}, {38, 55}, {62, 55}, {85, 52},
        {50, 82},
    },
    ["5-4-1:stagger"] = {
        {50, 5},
        {10, 25}, {30, 28}, {50, 30}, {70, 28}, {90, 25},
        {15, 52}, {42, 47}, {58, 62}, {85, 52},
        {50, 82},
    },
}

--- 获取当前阵型+布局的球场坐标（兼容 layoutKey / 旧 storageKey）
local function getFormationPositions(formation, variantKey)
    return FormationShape.getBasePositions(formation, variantKey or Constants.getDefaultVariant(formation))
end

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

    local isDerby = team and opponent and TransferManager.isRivalry(gameState, team.id, opponent.id)

    if not team then
        return UI.Panel { width = "100%", height = "100%", backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无比赛安排", color = Theme.COLORS.TEXT_SECONDARY } }
        }
    end

    -- 构建首发+替补列表
    local startingXI = {}
    local bench = {}
    local startingPidSet = {}  -- 用于替补过滤
    if team.startingXI and #team.startingXI > 0 then
        for i, pid in ipairs(team.startingXI) do
            local p = gameState.players[pid]
            if p and not p.injured then
                startingXI[i] = p
                startingPidSet[pid] = true
            else
                startingXI[i] = nil  -- 保留位置占位（受伤/不存在）
            end
        end
    end
    -- 自动填补空位：用替补中能力最高的健康球员填入
    local availableSubs = {}
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not startingPidSet[pid] then
            table.insert(availableSubs, p)
        end
    end
    table.sort(availableSubs, function(a, b) return a.overall > b.overall end)

    -- 填充空位
    local subIdx = 1
    for i = 1, #(team.startingXI or {}) do
        if not startingXI[i] and subIdx <= #availableSubs then
            startingXI[i] = availableSubs[subIdx]
            startingPidSet[availableSubs[subIdx].id] = true
            -- 同步更新 team.startingXI
            team.startingXI[i] = availableSubs[subIdx].id
            subIdx = subIdx + 1
        end
    end

    -- 替补：球队中非首发的健康球员
    for _, pid in ipairs(team.playerIds or {}) do
        local p = gameState.players[pid]
        if p and not p.injured and not startingPidSet[pid] then
            table.insert(bench, p)
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
                        text = (isDerby and "德比战 · " or "")
                            .. (isHome and "主场" or "客场") .. " · " .. tacticsInfo,
                        fontSize = 11, color = isDerby and Theme.COLORS.DANGER or Theme.COLORS.TEXT_MUTED,
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
                            UI.Panel {
                                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                                children = {
                                    Theme.Subtitle { text = string.format("首发阵容 (%d/11)", #startingXI) },
                                    UI.Button {
                                        text = "一键配置",
                                        height = 26,
                                        paddingLeft = 10, paddingRight = 10,
                                        backgroundColor = {Theme.COLORS.ACCENT[1], Theme.COLORS.ACCENT[2], Theme.COLORS.ACCENT[3], 40},
                                        borderRadius = 13,
                                        fontSize = 11,
                                        color = Theme.COLORS.ACCENT,
                                        onClick = function()
                                            _autoFullSquad(gameState, team)
                                            Router.replaceWith("pre_match", { fixture = fixture })
                                        end,
                                    },
                                },
                            },
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
                            local TurnProcessor = require("scripts/core/turn_processor")
                            local report
                            if fixture._isWC then
                                fixture._isWC = true
                            end
                            report = MatchEngine.simulate(gameState, fixture)
                            if report then
                                if fixture._isWC then
                                    TurnProcessor._applyWCResult(gameState, fixture, report)
                                elseif fixture._isUCL then
                                    TurnProcessor._applyUCLResult(gameState, fixture, report)
                                else
                                    MatchEngine.applyResult(gameState, fixture, report)
                                end
                                -- 发送比赛结果消息
                                local homeName, awayName
                                if fixture._isWC then
                                    local WorldCupMod = require("scripts/systems/world_cup")
                                    homeName = WorldCupMod._getNationName(fixture.homeTeamId)
                                    awayName = WorldCupMod._getNationName(fixture.awayTeamId)
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
                                -- 跳过后显示结果画面
                                SaveManager.save(gameState, "auto")
                                Router.replaceWith("match_result", {
                                    fixture = fixture,
                                    report = report,
                                    skipped = true,
                                })
                                return
                            end
                            SaveManager.save(gameState, "auto")
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
    local variantKey = team and team.formationVariant or nil
    local positions = getFormationPositions(formation, variantKey)
    local slots = AIManager._getFormationSlots(formation, variantKey)
    local pitchW = 320
    local pitchH = 400

    -- 位置颜色映射（统一使用 Theme.posColor）

    local dots = {}
    for i, pos in ipairs(positions) do
        local px = pos[1]
        local py = pos[2]
        -- 与 tactics.lua 一致: X 轴镜像，Y 轴翻转
        local left = math.floor((100 - px) / 100 * pitchW) - 16
        local top = math.floor((100 - py) / 100 * pitchH) - 16

        local player = startingXI[i]
        local label = "?"
        if player then
            -- 优先使用 shortName（中文姓氏，如"热苏斯"），次选 lastName
            local displayLabel = player.shortName or player.lastName or ""
            if displayLabel == "" or displayLabel == player.displayName then
                -- fallback: 从 displayName 取中文姓氏部分（·分隔）
                local dn = player.displayName or ""
                displayLabel = dn:match("·(.+)$") or dn
                -- 如果还是全名，从match_name取姓
                if displayLabel == dn and player.match_name and player.match_name ~= "" then
                    displayLabel = player.match_name:match("%s(.+)$") or player.match_name
                end
            end
            -- UTF-8 安全截取：最多取5个UTF-8字符
            local lastName = displayLabel
            local chars = 0
            local byteIdx = 1
            while byteIdx <= #lastName and chars < 5 do
                local b = lastName:byte(byteIdx)
                if b < 128 then byteIdx = byteIdx + 1
                elseif b < 224 then byteIdx = byteIdx + 2
                elseif b < 240 then byteIdx = byteIdx + 3
                else byteIdx = byteIdx + 4 end
                chars = chars + 1
            end
            label = lastName:sub(1, byteIdx - 1)
        end
        local slotPos = slots[i] or "CM"
        local dotColor = Theme.posColor(slotPos)
        -- 低体能警告
        if player and player.fitness < 70 then
            dotColor = Theme.COLORS.WARNING
        end

        local slotIdx = i
        table.insert(dots, UI.Panel {
            position = "absolute", left = left, top = top,
            width = 40, alignItems = "center",
            onClick = function()
                PreMatch._showSlotSwapSheet(gameState, team, slotIdx, slots, fixture)
            end,
            children = {
                UI.Panel {
                    width = 20, height = 20, borderRadius = 10,
                    backgroundColor = dotColor,
                },
                UI.Label { text = label, fontSize = 9, color = {255, 255, 255, 230}, textAlign = "center", marginTop = 2 },
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
    local fitness = player.fitness or 100
    local fitnessColor = {80, 200, 120, 255}  -- 绿色：体力充沛
    if fitness < 70 then fitnessColor = {255, 180, 50, 255} end  -- 橙色：体力一般
    if fitness < 50 then fitnessColor = {220, 60, 60, 255} end   -- 红色：体力不足

    local posLabel = Constants.POSITION_NAMES[player.position] or player.position or "?"
    local posClr = Theme.posColor(player.position)

    return UI.Panel {
        width = "100%", height = 40, flexDirection = "row",
        alignItems = "center", paddingLeft = 8, paddingRight = 8,
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            -- 序号
            UI.Label { text = tostring(idx), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 20 },
            -- 位置徽章
            UI.Panel {
                backgroundColor = {posClr[1], posClr[2], posClr[3], 50},
                borderRadius = 3,
                paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                marginRight = 6, minWidth = 42,
                children = {
                    UI.Label { text = posLabel, fontSize = 10, color = posClr, fontWeight = "bold" },
                },
            },
            -- 名字
            UI.Label { text = player.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, flexGrow = 1, flexShrink = 1 },
            -- 体能条（可视化）
            UI.Panel {
                width = 50, height = 14, borderRadius = 7,
                backgroundColor = {40, 40, 50, 255},
                marginRight = 8, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(fitness) .. "%", height = "100%",
                        backgroundColor = fitnessColor,
                        borderRadius = 7,
                    },
                },
            },
            -- OVR 评分
            UI.Panel {
                width = 30, height = 22, borderRadius = 4,
                backgroundColor = player.overall >= 80 and {40, 120, 60, 255}
                    or (player.overall >= 70 and {50, 90, 130, 255} or {80, 80, 80, 255}),
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)), fontSize = 11, fontWeight = "bold",
                        color = {255, 255, 255, 255},
                    },
                },
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
                    team.formationVariant = Constants.getDefaultVariant(fmt)
                    team.customSlots = nil
                    team.slotOffsets = nil
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
