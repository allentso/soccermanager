-- ui/screens/dashboard/nt_view.lua
-- 国家队模式视图，从 dashboard.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local TurnProcessor = require("scripts/core/turn_processor")
local SaveManager = require("scripts/persistence/save_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local TimeBlockerManager = require("scripts/systems/time_blocker_manager")
local BlockerDialog = require("scripts/ui/components/blocker_dialog")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local TeamIcon = require("scripts/ui/components/team_icon")
local WorldCup = require("scripts/systems/world_cup")
local EuroCup = require("scripts/systems/euro_cup")
local TransferManager = require("scripts/systems/transfer_manager")
local MessageManager = require("scripts/systems/message_manager")
local DomesticCup = require("scripts/systems/domestic_cup")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local DayAdvanceOverlay = require("scripts/ui/components/day_advance_overlay")
local MessageActionHandlers = require("scripts/ui/message_action_handlers")
local Market = require("scripts/ui/screens/market")
local sdk = sdk
local function _dashboard() return require("scripts/ui/screens/dashboard") end

local Mod = {}

function Mod.showCoachGuidance(gameState)
    local nationName = ""
    if gameState.nationalTeamCoach then
        local WorldCupMod = require("scripts/systems/world_cup")
        nationName = WorldCupMod._getNationName(gameState.nationalTeamCoach.nation) or ""
    end

    -- 获取国旗图标
    local WorldCup = require("scripts/systems/world_cup")
    local nationCode = gameState.nationalTeamCoach and gameState.nationalTeamCoach.nation or ""
    local nationIconPath = WorldCup.getNationIconPath(nationCode)

    -- 国旗图标或 fallback emoji
    local flagIcon
    if nationIconPath then
        flagIcon = UI.Panel {
            width = 52, height = 52, marginBottom = 12,
            borderRadius = 26,
            backgroundColor = {255, 255, 255, 20},
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Panel {
                    width = 40, height = 40, borderRadius = 20,
                    backgroundImage = nationIconPath,
                    backgroundSize = "contain",
                },
            },
        }
    else
        flagIcon = UI.Label {
            text = "🏳️", fontSize = 42, marginBottom = 12,
        }
    end

    local overlay = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = {0, 0, 0, 180},
        justifyContent = "center",
        alignItems = "center",
        children = {
            -- 主卡片
            UI.Panel {
                width = 320,
                maxWidth = "88%",
                backgroundColor = {20, 22, 30, 252},
                borderRadius = 20,
                paddingTop = 32, paddingBottom = 28, paddingLeft = 24, paddingRight = 24,
                alignItems = "center",
                borderWidth = 1.5,
                borderColor = {200, 170, 80, 120},
                children = {
                    -- 旗帜图标
                    flagIcon,
                    -- 标题（金色）
                    UI.Label {
                        text = "国家队身份已激活",
                        fontSize = 20,
                        color = {240, 200, 80, 255},
                        fontWeight = "bold",
                        textAlign = "center",
                        marginBottom = 8,
                    },
                    -- 副标题
                    UI.Label {
                        text = string.format("恭喜！你已成为%s主教练。", nationName),
                        fontSize = 14,
                        color = {200, 200, 210, 255},
                        textAlign = "center",
                        marginBottom = 20,
                    },
                    -- 操作指引卡片
                    UI.Panel {
                        width = "100%",
                        backgroundColor = {255, 248, 220, 12},
                        borderRadius = 14,
                        borderWidth = 1,
                        borderColor = {200, 170, 80, 60},
                        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
                        alignItems = "center",
                        marginBottom = 16,
                        children = {
                            UI.Label {
                                text = "👆 点击顶部栏的队徽图标切换",
                                fontSize = 13,
                                color = {240, 210, 100, 255},
                                fontWeight = "bold",
                                textAlign = "center",
                                marginBottom = 10,
                            },
                            -- 切换按钮示意
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                justifyContent = "center",
                                backgroundColor = {30, 32, 40, 200},
                                borderRadius = 16,
                                paddingTop = 6, paddingBottom = 6, paddingLeft = 12, paddingRight = 12,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center", marginRight = 8,
                                        backgroundColor = {50, 52, 60, 255},
                                        borderRadius = 10,
                                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                                        children = {
                                            UI.Label { text = "🏠 俱乐部", fontSize = 11, color = {180, 180, 190, 255} },
                                        },
                                    },
                                    UI.Label { text = "⇄", fontSize = 16, color = {200, 170, 80, 220}, marginRight = 8 },
                                    UI.Panel {
                                        flexDirection = "row", alignItems = "center",
                                        backgroundColor = {60, 50, 20, 255},
                                        borderRadius = 10,
                                        borderWidth = 1, borderColor = {200, 170, 80, 100},
                                        paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                                        children = {
                                            UI.Label { text = "🏴 " .. nationName, fontSize = 11, color = {240, 210, 100, 255} },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    -- 说明文字
                    UI.Label {
                        text = "你可以随时点击顶部栏的队徽\n切换「俱乐部」与「国家队」身份，\n分别管理两支球队的事务。",
                        fontSize = 13,
                        color = {150, 150, 160, 255},
                        textAlign = "center",
                        lineHeight = 1.6,
                        width = "100%",
                        whiteSpace = "normal",
                        marginBottom = 22,
                    },
                    -- 按钮（金色调）
                    UI.Button {
                        text = "知道了",
                        width = 140,
                        height = 40,
                        fontSize = 15,
                        color = {30, 25, 10, 255},
                        backgroundColor = {220, 185, 70, 255},
                        borderRadius = 20,
                        fontWeight = "bold",
                        onClick = function()
                            UI.CloseOverlay()
                        end,
                    },
                },
            },
        },
    }

    UI.ShowOverlay(overlay)
end

------------------------------------------------------
-- [国家队模式] 下一场世界杯比赛 Hero
------------------------------------------------------
function Mod.buildMatchHero(gameState)
    local wc = gameState.worldCup
    local euro = gameState.euroCup
    local ntCoach = gameState.nationalTeamCoach
    if (not wc and not euro) or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local isEuro = euro ~= nil
    local NT = isEuro and EuroCup or WorldCup
    local compLabel = isEuro and "欧洲杯" or "世界杯"
    local tournament = isEuro and euro or wc

    local playerNation = ntCoach.nation
    local nationName = NT._getNationName(playerNation)

    -- 查找下一场国家队比赛
    local nextFixture = nil
    local League = require("scripts/domain/league")
    for daysAhead = 0, 60 do
        local futureDate = League._addDays(gameState.date, daysAhead)
        local ntFixtures = isEuro
            and TurnProcessor.getEuroFixturesForDate(gameState, futureDate)
            or TurnProcessor.getWCFixturesForDate(gameState, futureDate)
        for _, f in ipairs(ntFixtures) do
            if f.homeTeamId == playerNation or f.awayTeamId == playerNation then
                if f.status == "scheduled" then
                    nextFixture = f
                    break
                end
            end
        end
        if nextFixture then break end
    end

    local phaseNames = {
        group = "小组赛",
        r32 = "三十二强",
        r16 = "十六强",
        qf = "四分之一决赛",
        sf = "半决赛",
        final = "决赛",
        completed = "已结束",
    }
    local phaseName = phaseNames[tournament.phase] or compLabel

    if not nextFixture then
        local statusText = tournament.phase == "completed" and (compLabel .. "已结束") or "暂无比赛安排"
        if tournament.champion then
            local champName = NT._getNationName(tournament.champion)
            statusText = "🏆 冠军: " .. champName
        end
        return UI.Panel {
            width = "100%",
            backgroundColor = {20, 35, 60, 255},
            borderRadius = 14,
            paddingTop = 16, paddingBottom = 16, paddingLeft = 16, paddingRight = 16,
            marginBottom = 12,
            overflow = "hidden",
            children = {
                -- 左上角俱乐部/国家队切换图标
                UI.Panel {
                    position = "absolute",
                    top = 10, left = 10,
                    zIndex = 10,
                    children = {
                        Dashboard._buildTeamIconSwitcher(gameState, gameState:getPlayerTeam()),
                    },
                },
                UI.Panel {
                    position = "absolute",
                    top = 10, right = 10,
                    zIndex = 10,
                    children = {
                        Dashboard._buildSettingsChip(),
                    },
                },
                Theme.SectionHeader { text = "🏆 " .. compLabel .. " · " .. phaseName, color = {255, 215, 0, 255} },
                UI.Label {
                    text = statusText,
                    fontSize = 14, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                },
            }
        }
    end

    local opponentCode = nextFixture.homeTeamId == playerNation
        and nextFixture.awayTeamId or nextFixture.homeTeamId
    local opponentName = NT._getNationName(opponentCode)
    local isHome = nextFixture.homeTeamId == playerNation

    -- 日期和倒计时
    local matchDateStr = string.format("%d月%d日", nextFixture.date.month, nextFixture.date.day)
    local daysTo = 0
    for d = 1, 60 do
        local fd = League._addDays(gameState.date, d)
        if fd.year == nextFixture.date.year and fd.month == nextFixture.date.month and fd.day == nextFixture.date.day then
            daysTo = d
            break
        end
    end
    local countdownText = daysTo <= 0 and "今天" or (daysTo == 1 and "明天" or (daysTo .. "天后"))

    -- 大名单状态
    local squadCount = ntCoach.squad and #ntCoach.squad or 0
    local squadStatus = squadCount > 0 and (squadCount .. "人") or "未选"
    local squadColor = squadCount >= 20 and Theme.COLORS.FINANCE_GREEN
        or (squadCount > 0 and Theme.COLORS.WARNING or Theme.COLORS.DANGER)

    return UI.Panel {
        width = "100%",
        backgroundColor = {15, 30, 55, 255},
        borderRadius = 14,
        paddingTop = 14, paddingBottom = 14, paddingLeft = 16, paddingRight = 16,
        marginBottom = 12,
        overflow = "hidden",
        children = {
            -- 左上角俱乐部/国家队切换图标（叠在卡片上）
            UI.Panel {
                position = "absolute",
                top = 10, left = 10,
                zIndex = 10,
                children = {
                    Dashboard._buildTeamIconSwitcher(gameState, gameState:getPlayerTeam()),
                },
            },
            UI.Panel {
                position = "absolute",
                top = 10, right = 10,
                zIndex = 10,
                children = {
                    Dashboard._buildSettingsChip(),
                },
            },
            -- 顶部：世界杯 + 阶段 + 倒计时
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "center",
                marginBottom = 6,
                children = {
                    UI.Label { text = "🏆 " .. compLabel .. " · " .. phaseName, fontSize = 13, color = {255, 215, 0, 255} },
                    UI.Panel {
                        backgroundColor = {255, 215, 0, 40},
                        borderRadius = 10,
                        paddingLeft = 8, paddingRight = 8, paddingTop = 2, paddingBottom = 2,
                        marginLeft = 8,
                        children = {
                            UI.Label { text = countdownText, fontSize = 10, color = {255, 215, 0, 255}, fontWeight = "bold" },
                        }
                    },
                }
            },

            -- 日期
            UI.Panel {
                width = "100%", alignItems = "center", marginBottom = 16,
                children = {
                    UI.Label { text = matchDateStr, fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
                }
            },

            -- 对阵区：国家队徽 + 国名 + VS
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                marginBottom = 16,
                children = {
                    -- 我方国家
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 52, height = 52, borderRadius = 26,
                                backgroundColor = {40, 70, 120, 255},
                                justifyContent = "center", alignItems = "center",
                                overflow = "hidden",
                                backgroundImage = NT.getNationIconPath(playerNation) or "",
                                backgroundFit = "contain",
                                children = (not NT.getNationIconPath(playerNation)) and {
                                    UI.Label { text = playerNation or "?", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                } or {},
                            },
                            UI.Label {
                                text = nationName,
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                                textAlign = "center", marginTop = 8,
                            },
                        }
                    },
                    -- VS
                    UI.Panel {
                        width = 50, alignItems = "center",
                        children = {
                            UI.Label {
                                text = "VS",
                                fontSize = 18, color = {255, 215, 0, 255}, fontWeight = "bold",
                            },
                        }
                    },
                    -- 对手国家
                    UI.Panel {
                        flexGrow = 1, alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 52, height = 52, borderRadius = 26,
                                backgroundColor = {60, 50, 50, 255},
                                justifyContent = "center", alignItems = "center",
                                overflow = "hidden",
                                backgroundImage = NT.getNationIconPath(opponentCode) or "",
                                backgroundFit = "contain",
                                children = (not NT.getNationIconPath(opponentCode)) and {
                                    UI.Label { text = opponentCode or "?", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                } or {},
                            },
                            UI.Label {
                                text = opponentName,
                                fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY, fontWeight = "bold",
                                textAlign = "center", marginTop = 8,
                            },
                        }
                    },
                }
            },

            -- 赛事信息行
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "center", alignItems = "center",
                marginBottom = 14,
                children = {
                    UI.Label { text = isHome and "主场" or "客场", fontSize = 11, color = {255, 215, 0, 200}, fontWeight = "bold" },
                }
            },

            -- 分隔线
            UI.Panel { width = "100%", height = 1, backgroundColor = {255, 255, 255, 15}, marginBottom = 12 },

            -- 底部状态：确认前显示大名单，确认后显示战术
            (ntCoach.squadConfirmed and UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "阵型: ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label {
                                text = (gameState:getPlayerTeam() and gameState:getPlayerTeam().formation) or "4-4-2",
                                fontSize = 13, color = {255, 215, 0, 255}, fontWeight = "bold",
                            },
                        }
                    },
                    UI.Button {
                        text = "战术 →",
                        height = 26,
                        backgroundColor = {255, 215, 0, 30},
                        borderRadius = 6,
                        fontSize = 11, fontWeight = "bold",
                        color = {255, 215, 0, 255},
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function()
                            Router.navigate("tactics")
                        end,
                    },
                }
            } or UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "大名单: ", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                            UI.Label { text = squadStatus, fontSize = 12, color = squadColor, fontWeight = "bold" },
                        }
                    },
                    UI.Button {
                        text = "选人 →",
                        height = 26,
                        backgroundColor = {255, 215, 0, 30},
                        borderRadius = 6,
                        fontSize = 11, fontWeight = "bold",
                        color = {255, 215, 0, 255},
                        paddingLeft = 10, paddingRight = 10,
                        onClick = function()
                            Router.navigate("national_squad_select", { nation = ntCoach.nation })
                        end,
                    },
                }
            }),
        }
    }
end

------------------------------------------------------
-- [国家队模式] 状态概览（小组积分 + 球队信息）
------------------------------------------------------
function Mod.buildSnapshot(gameState)
    local wc = gameState.worldCup
    local euro = gameState.euroCup
    local ntCoach = gameState.nationalTeamCoach
    if (not wc and not euro) or not ntCoach then
        return UI.Panel { height = 0 }
    end

    local isEuro = euro ~= nil
    local NT = isEuro and EuroCup or WorldCup
    local tournament = isEuro and euro or wc

    local playerNation = ntCoach.nation
    local nationName = NT._getNationName(playerNation)

    local myGroup = nil
    local myGroupName = ""
    for gName, group in pairs(tournament.groups or {}) do
        for _, tid in ipairs(group.teamIds) do
            if tid == playerNation then
                myGroup = group
                myGroupName = gName
                break
            end
        end
        if myGroup then break end
    end

    -- 小组积分表
    local standingsRows = {}
    if myGroup and tournament.phase == "group" then
        -- 排序积分榜
        local sorted = {}
        for tid, s in pairs(myGroup.standings) do
            table.insert(sorted, s)
        end
        table.sort(sorted, function(a, b)
            if a.points ~= b.points then return a.points > b.points end
            if a.goalDifference ~= b.goalDifference then return a.goalDifference > b.goalDifference end
            return a.goalsFor > b.goalsFor
        end)

        for rank, s in ipairs(sorted) do
            local name = NT._getNationName(s.teamId)
            local isPlayer = s.teamId == playerNation
            local rowBg = isPlayer and {255, 215, 0, 20} or {0, 0, 0, 0}
            local nameColor = isPlayer and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY

            table.insert(standingsRows, UI.Panel {
                width = "100%", height = 30,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                backgroundColor = rowBg,
                borderRadius = 4,
                children = {
                    UI.Label { text = tostring(rank), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 18 },
                    UI.Label { text = name, fontSize = 12, color = nameColor, fontWeight = isPlayer and "bold" or "normal", flexGrow = 1 },
                    UI.Label { text = tostring(s.played), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
                    UI.Label { text = tostring(s.goalDifference), fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "center" },
                    UI.Label { text = tostring(s.points), fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", width = 22, textAlign = "center" },
                }
            })
        end
    end

    -- 淘汰赛阶段信息（包括已完赛，仍显示bracket供回顾）
    local knockoutInfo = nil
    if tournament.phase ~= "group" and tournament.phase ~= "not_started" then
        knockoutInfo = tournament.phase == "completed" and "赛事已结束" or "进入淘汰赛阶段"
    end

    local children = {}

    -- 小组表头
    if #standingsRows > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
            children = {
                UI.Label { text = "🏆", fontSize = 14, marginRight = 6 },
                UI.Label { text = myGroupName .. " 组积分榜", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
            }
        })
        -- 表头行
        table.insert(children, UI.Panel {
            width = "100%", height = 24,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 8, paddingRight = 8,
            children = {
                UI.Label { text = "#", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 18 },
                UI.Label { text = "球队", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                UI.Label { text = "赛", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
                UI.Label { text = "净", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 26, textAlign = "center" },
                UI.Label { text = "分", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 22, textAlign = "center" },
            }
        })
        for _, row in ipairs(standingsRows) do
            table.insert(children, row)
        end
    elseif knockoutInfo then
        -- 淘汰赛对阵图（compact bracket tree）
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 8,
            children = {
                UI.Label { text = "⚔️", fontSize = 14, marginRight = 6 },
                UI.Label { text = "淘汰赛对阵", fontSize = 13, color = {255, 215, 0, 255}, fontWeight = "bold" },
            }
        })

        -- 构建紧凑型bracket
        local bracketPhases = {
            {key = "r32", name = "32强"},
            {key = "r16", name = "16强"},
            {key = "qf", name = "8强"},
            {key = "sf", name = "4强"},
            {key = "final", name = "决赛"},
        }

        local function buildMiniCard(f)
            if not f then
                return UI.Panel {
                    width = 100, height = 32,
                    backgroundColor = {30, 35, 50, 255},
                    borderRadius = 4, borderWidth = 1, borderColor = {50, 55, 70, 255},
                    justifyContent = "center", alignItems = "center",
                    marginTop = 1, marginBottom = 1,
                    children = {
                        UI.Label { text = "—", fontSize = 9, color = Theme.COLORS.TEXT_MUTED },
                    }
                }
            end

            local hName = WorldCup._getNationName(f.homeTeamId)
            local aName = WorldCup._getNationName(f.awayTeamId)
            if #hName > 4 then hName = string.sub(hName, 1, 6) end
            if #aName > 4 then aName = string.sub(aName, 1, 6) end

            local done = f.status == "finished"
            local hWin = done and (f.homeGoals > f.awayGoals or (f._penaltyWinner and f._penaltyWinner == f.homeTeamId))
            local aWin = done and (f.awayGoals > f.homeGoals or (f._penaltyWinner and f._penaltyWinner == f.awayTeamId))
            local hCol = hWin and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY
            local aCol = aWin and {255, 215, 0, 255} or Theme.COLORS.TEXT_PRIMARY
            local bg = done and {20, 35, 55, 255} or {30, 35, 50, 255}
            local bd = done and {40, 80, 130, 255} or {50, 55, 70, 255}

            return UI.Panel {
                width = 100, height = 32,
                backgroundColor = bg,
                borderRadius = 4, borderWidth = 1, borderColor = bd,
                justifyContent = "center",
                paddingLeft = 4, paddingRight = 4,
                marginTop = 1, marginBottom = 1,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = hName, fontSize = 9, color = hCol, fontWeight = hWin and "bold" or "normal", flexShrink = 1 },
                            UI.Label { text = done and tostring(f.homeGoals) or "", fontSize = 9, color = {180, 200, 255, 255}, width = 10, textAlign = "right" },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label { text = aName, fontSize = 9, color = aCol, fontWeight = aWin and "bold" or "normal", flexShrink = 1 },
                            UI.Label { text = done and tostring(f.awayGoals) or "", fontSize = 9, color = {180, 200, 255, 255}, width = 10, textAlign = "right" },
                        }
                    },
                }
            }
        end

        local bracketCols = {}
        for _, bp in ipairs(bracketPhases) do
            local fixtures = tournament.knockout[bp.key] or {}
            local realFixtures = {}
            for _, f in ipairs(fixtures) do
                if not f._isThirdPlace then table.insert(realFixtures, f) end
            end

            local colChildren = {}
            table.insert(colChildren, UI.Panel {
                width = "100%", alignItems = "center", marginBottom = 4,
                children = {
                    UI.Label { text = bp.name, fontSize = 9, color = {150, 180, 220, 255}, fontWeight = "bold" },
                }
            })

            if #realFixtures > 0 then
                for _, f in ipairs(realFixtures) do
                    table.insert(colChildren, buildMiniCard(f))
                end
            else
                local expectedCount = ({r32 = 16, r16 = 8, qf = 4, sf = 2, final = 1})[bp.key] or 0
                for _ = 1, expectedCount do
                    table.insert(colChildren, buildMiniCard(nil))
                end
            end

            table.insert(bracketCols, UI.Panel {
                alignItems = "center",
                justifyContent = "space-around",
                flexGrow = 1,
                children = colChildren,
            })
        end

        -- 冠军列（如果有）
        if tournament.champion then
            local champName = NT._getNationName(tournament.champion)
            table.insert(bracketCols, UI.Panel {
                alignItems = "center", justifyContent = "center", flexGrow = 1,
                children = {
                    UI.Label { text = "🏆", fontSize = 18 },
                    UI.Label { text = champName, fontSize = 10, color = {255, 215, 0, 255}, fontWeight = "bold", marginTop = 4 },
                }
            })
        end

        table.insert(children, UI.ScrollView {
            width = "100%",
            height = 360,
            scrollX = true,
            scrollY = false,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "stretch",
                    height = "100%",
                    children = bracketCols,
                }
            }
        })
    end

    -- 快捷操作
    table.insert(children, UI.Panel {
        width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 10, marginBottom = 10,
    })
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-around",
        children = {
            UI.Button {
                text = ntCoach.squadConfirmed and "⚙️ 战术" or "📋 大名单",
                height = 32,
                backgroundColor = ntCoach.squadConfirmed and {40, 50, 80, 255} or {40, 60, 90, 255},
                borderRadius = 6,
                fontSize = 11,
                color = ntCoach.squadConfirmed and {255, 215, 0, 255} or {130, 200, 255, 255},
                paddingLeft = 12, paddingRight = 12,
                onClick = function()
                    if ntCoach.squadConfirmed then
                        Router.navigate("tactics")
                    else
                        Router.navigate("national_squad_select", { nation = playerNation })
                    end
                end,
            },
            UI.Button {
                text = "📊 赛程",
                height = 32,
                backgroundColor = {40, 60, 90, 255},
                borderRadius = 6,
                fontSize = 11, color = {130, 200, 255, 255},
                paddingLeft = 12, paddingRight = 12,
                onClick = function()
                    Router.navigate("league", { tab = "WC" })
                end,
            },
        }
    })

    return Theme.Card {
        backgroundColor = {20, 30, 50, 255},
        borderColor = {40, 70, 120, 100},
        children = children,
    }
end

------------------------------------------------------
-- [国家队模式] 世界杯相关新闻/活动流
------------------------------------------------------
function Mod.buildActivityFeed(gameState)
    -- 筛选世界杯相关消息（inbox 存放 world_cup/national_team，news 存放 world_cup_news）
    local wcMsgs = {}
    for _, msg in ipairs(gameState.inbox) do
        if msg.category == "world_cup" or msg.category == "national_team" then
            table.insert(wcMsgs, msg)
            if #wcMsgs >= 4 then break end
        end
    end
    if #wcMsgs < 4 then
        for _, article in ipairs(gameState.news or {}) do
            if article.category == "world_cup_news" then
                table.insert(wcMsgs, article)
                if #wcMsgs >= 4 then break end
            end
        end
    end

    local msgRows = {}
    if #wcMsgs > 0 then
        for _, msg in ipairs(wcMsgs) do
            local dotColor = {255, 215, 0, 255}  -- 金色标识世界杯
            if MessageManager.isUrgent(msg.priority) then dotColor = Theme.COLORS.DANGER end

            table.insert(msgRows, UI.Panel {
                width = "100%", height = 38,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                borderBottomWidth = 1, borderColor = {255, 255, 255, 10},
                children = {
                    UI.Panel { width = 5, height = 5, borderRadius = 3, backgroundColor = dotColor, marginRight = 8 },
                    UI.Label {
                        text = msg.title or "世界杯动态",
                        fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1, flexShrink = 1,
                    },
                    msg.date and UI.Label {
                        text = string.format("%d/%d", msg.date.month, msg.date.day),
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    } or UI.Panel { width = 0 },
                },
                onClick = function()
                    Router.navigate("inbox")
                end,
            })
        end
    else
        table.insert(msgRows, UI.Label {
            text = "暂无世界杯动态",
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            marginTop = 4, marginBottom = 4,
        })
    end

    return Theme.Card {
        backgroundColor = {20, 30, 50, 255},
        borderColor = {40, 70, 120, 100},
        children = {
            -- 标题
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                marginBottom = 8,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label { text = "📰", fontSize = 14, marginRight = 6 },
                            UI.Label { text = "世界杯动态", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        }
                    },
                    UI.Button {
                        text = "全部 →",
                        height = 24,
                        backgroundColor = {0, 0, 0, 0},
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                        onClick = function()
                            Router.navigate("inbox")
                        end,
                    },
                }
            },
            -- 消息列表
            table.unpack(msgRows),
        }
    }
end

------------------------------------------------------
-- [快进到邀约] 失业状态下快进到收到工作邀约

return Mod
