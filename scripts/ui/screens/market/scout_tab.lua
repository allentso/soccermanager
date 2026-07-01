-- ui/screens/market/scout_tab.lua
-- 球探标签页，从 market.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TransferManager = require("scripts/systems/transfer_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local PotentialSystem = require("scripts/systems/potential_system")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferLimitDialog = require("scripts/ui/components/transfer_limit_dialog")
local AudioManager = require("scripts/systems/audio_manager")
local YouthManager = require("scripts/systems/youth_manager")
local SaleListingPriceSheet = require("scripts/ui/components/sale_listing_price_sheet")

local Tab = {}

function Tab.build(gameState, scoutFilters, subTab)
    scoutFilters = scoutFilters or {}
    subTab = subTab or "explore"
    local children = {}
    local team = gameState:getPlayerTeam()
    if not team then return children end

    -- 获取球探
    local scouts = {}
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == "scout" then
            table.insert(scouts, s)
        end
    end

    if #scouts == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            padding = 20,
            children = {
                UI.Label { text = "没有球探", fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                UI.Label {
                    text = "球队没有球探，无法探索球员。\n请在职员页面雇佣球探。",
                    fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginTop = 8,
                    textAlign = "center",
                },
            }
        })
        return children
    end

    -- ====== 子标签栏 ======
    local reports = ScoutManager.getReports(gameState)
    local subTabs = {
        { key = "explore", label = "探索" },
        { key = "reports", label = string.format("报告 (%d)", #reports) },
    }
    local subTabButtons = {}
    for _, st in ipairs(subTabs) do
        local isActive = st.key == subTab
        table.insert(subTabButtons, UI.Button {
            text = st.label,
            height = 30,
            paddingLeft = 14, paddingRight = 14,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 15,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 8,
            onClick = function()
                Router.replaceWith("market", { tab = "scout", scoutSubTab = st.key,
                    scoutLeague = scoutFilters.league, scoutPos = scoutFilters.position,
                    scoutNat = scoutFilters.nationality, scoutAge = scoutFilters.ageKey })
            end,
        })
    end
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12, paddingTop = 8, paddingBottom = 8,
        children = subTabButtons,
    })

    -- ====== 根据子标签显示内容 ======
    if subTab == "explore" then
        Tab._buildScoutExploreContent(children, gameState, scoutFilters, scouts)
    else
        Tab._buildScoutReportsContent(children, gameState)
    end

    return children
end

-- 球探子页面：探索条件 + 球探团队 + 进行中的任务
-- 模块级状态：球探筛选（避免 Router.replaceWith 重建页面）
Tab._exploreFilterState = { league = nil, position = nil, nationality = nil, ageKey = "any" }
Tab._exploreContainerRef = nil
Tab._exploreGameState = nil
Tab._exploreScouts = nil

local SCOUT_POSITIONS = {"GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"}
local AGE_RANGES = {
    { key = "any",   label = "不限",       min = nil, max = nil },
    { key = "u21",   label = "U21",        min = 16,  max = 21 },
    { key = "young", label = "22-27",      min = 22,  max = 27 },
    { key = "peak",  label = "28-32",      min = 28,  max = 32 },
    { key = "vet",   label = "33+",        min = 33,  max = 40 },
}

-- 就地刷新探索区域（不重建页面）
function Tab._refreshExploreContainer()
    if Tab._exploreContainerRef then
        Tab._exploreContainerRef:ClearChildren()
        local innerChildren = Tab._buildExploreInner()
        for _, child in ipairs(innerChildren) do
            Tab._exploreContainerRef:AddChild(child)
        end
    end
end

-- 生成探索区域的 children 数组
function Tab._buildExploreInner()
    local gameState = Tab._exploreGameState
    local scouts = Tab._exploreScouts or {}
    local fs = Tab._exploreFilterState
    local activeTasks = ScoutManager.getActiveTasks(gameState)

    local selLeague = fs.league
    local selPos = fs.position
    local selNat = fs.nationality
    local selAgeKey = fs.ageKey or "any"

    -- 帮助函数：更新筛选并刷新
    local function applyFilter(overrides)
        for k, v in pairs(overrides) do
            if v == "__nil" then
                fs[k] = nil
            else
                fs[k] = v
            end
        end
        Tab._refreshExploreContainer()
    end

    local items = {}

    -- 球探团队信息
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8, padding = 12, marginBottom = 10,
        children = {
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label { text = "球探团队", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    UI.Label {
                        text = string.format("%d 名球探 · 准确度 %d%% · 任务 %d/3", #scouts, math.floor(ScoutManager.getAccuracy(gameState) * 100), #activeTasks),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                    },
                }
            },
        }
    })

    -- ====== 内嵌筛选区域 ======
    local leagues = ScoutManager.getAvailableLeagues(gameState)

    -- 联赛筛选
    local leagueItems = {}
    local allLeagueActive = (selLeague == nil)
    table.insert(leagueItems, UI.Button {
        text = "全部", height = 28, paddingLeft = 8, paddingRight = 8,
        backgroundColor = allLeagueActive and Theme.COLORS.PRIMARY or Theme.COLORS.BG_HEADER,
        borderRadius = 14, marginRight = 6, marginBottom = 4,
        fontSize = 10, color = allLeagueActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ league = "__nil" }) end,
    })
    for _, lg in ipairs(leagues) do
        local active = (selLeague == lg.id)
        table.insert(leagueItems, UI.Button {
            text = lg.name, height = 28, paddingLeft = 8, paddingRight = 8,
            backgroundColor = active and Theme.COLORS.PRIMARY or Theme.COLORS.BG_HEADER,
            borderRadius = 14, marginRight = 6, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ league = lg.id }) end,
        })
    end

    -- 位置筛选
    local posItems = {}
    local allPosActive = (selPos == nil)
    table.insert(posItems, UI.Button {
        text = "全部", height = 26, paddingLeft = 6, paddingRight = 6,
        backgroundColor = allPosActive and Theme.COLORS.ACCENT or Theme.COLORS.BG_HEADER,
        borderRadius = 12, marginRight = 4, marginBottom = 4,
        fontSize = 10, color = allPosActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ position = "__nil" }) end,
    })
    for _, pos in ipairs(SCOUT_POSITIONS) do
        local posName = Constants.POSITION_NAMES[pos] or pos
        local active = (selPos == pos)
        table.insert(posItems, UI.Button {
            text = posName, height = 26, paddingLeft = 6, paddingRight = 6,
            backgroundColor = active and Theme.COLORS.ACCENT or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 4, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ position = pos }) end,
        })
    end

    -- 国籍筛选
    local nationalities = ScoutManager.getAvailableNationalities(gameState)
    local natItems = {}
    local allNatActive = (selNat == nil)
    table.insert(natItems, UI.Button {
        text = "全部", height = 26, paddingLeft = 6, paddingRight = 6,
        backgroundColor = allNatActive and {180, 100, 220, 255} or Theme.COLORS.BG_HEADER,
        borderRadius = 12, marginRight = 4, marginBottom = 4,
        fontSize = 10, color = allNatActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
        onClick = function() applyFilter({ nationality = "__nil" }) end,
    })
    for _, nat in ipairs(nationalities) do
        local active = (selNat == nat.code)
        table.insert(natItems, UI.Button {
            text = nat.name, height = 26, paddingLeft = 6, paddingRight = 6,
            backgroundColor = active and {180, 100, 220, 255} or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 4, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ nationality = nat.code }) end,
        })
    end

    -- 年龄筛选
    local ageItems = {}
    for _, range in ipairs(AGE_RANGES) do
        local active = (selAgeKey == range.key)
        table.insert(ageItems, UI.Button {
            text = range.label, height = 26, paddingLeft = 8, paddingRight = 8,
            backgroundColor = active and Theme.COLORS.SECONDARY or Theme.COLORS.BG_HEADER,
            borderRadius = 12, marginRight = 6, marginBottom = 4,
            fontSize = 10, color = active and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            onClick = function() applyFilter({ ageKey = range.key }) end,
        })
    end

    -- 筛选面板
    table.insert(items, UI.Panel {
        width = "100%", backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8, padding = 10, marginBottom = 10,
        children = {
            UI.Label { text = "探索条件", fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", marginBottom = 6 },
            -- 联赛
            UI.Label { text = "联赛", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = leagueItems },
            -- 位置
            UI.Label { text = "位置", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = posItems },
            -- 国籍
            UI.Label { text = "国籍", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 8, children = natItems },
            -- 年龄
            UI.Label { text = "年龄", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4 },
            UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap", marginBottom = 10, children = ageItems },
            -- 派出按钮
            UI.Button {
                text = #activeTasks >= 3 and "任务已满 (3/3)" or "派出球探探索",
                width = "100%", height = 36,
                backgroundColor = #activeTasks >= 3 and Theme.COLORS.BG_HEADER or Theme.COLORS.PRIMARY,
                borderRadius = 8,
                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                onClick = function()
                    if #activeTasks >= 3 then
                        UI.Toast.Show({ message = "已达最大任务数 (3/3)", variant = "warning" })
                        return
                    end
                    -- 构造 filters
                    local filters = {}
                    if selLeague then filters.leagueId = selLeague end
                    if selPos then filters.position = selPos end
                    if selNat then filters.nationality = selNat end
                    for _, r in ipairs(AGE_RANGES) do
                        if r.key == selAgeKey and r.min then
                            filters.minAge = r.min
                            filters.maxAge = r.max
                            break
                        end
                    end
                    local ok, err = ScoutManager.createSearchTask(gameState, filters)
                    if ok then
                        UI.Toast.Show({ message = "探索任务已创建", variant = "success" })
                        Tab._refreshExploreContainer()
                    else
                        UI.Toast.Show({ message = err or "操作失败", variant = "error" })
                    end
                end,
            },
        }
    })

    -- ====== 进行中的任务 ======
    if #activeTasks > 0 then
        table.insert(items, UI.Label {
            text = string.format("进行中 (%d/3)", #activeTasks),
            fontSize = 12, color = Theme.COLORS.TEXT_SECONDARY,
            fontWeight = "bold", marginBottom = 6, marginTop = 4,
        })
        for _, task in ipairs(activeTasks) do
            local progressPct = task.progress or 0
            table.insert(items, UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 8, padding = 10, marginBottom = 6,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 4,
                        children = {
                            UI.Label {
                                text = task.description,
                                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1, flexShrink = 1,
                            },
                            UI.Label {
                                text = string.format("剩余 %d 天", task.daysRemaining),
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginLeft = 6,
                            },
                            UI.Button {
                                text = "×", width = 24, height = 24,
                                backgroundColor = {60, 30, 30, 150}, borderRadius = 12,
                                fontSize = 13, color = Theme.COLORS.DANGER, marginLeft = 6,
                                onClick = function()
                                    ConfirmDialog.show({
                                        title = "取消探索任务",
                                        message = "确定取消「" .. task.description .. "」？",
                                        confirmText = "取消任务", danger = true,
                                        onConfirm = function()
                                            ScoutManager.cancelTask(gameState, task.id)
                                            Tab._refreshExploreContainer()
                                        end,
                                    })
                                end,
                            },
                        }
                    },
                    -- 进度条
                    UI.Panel {
                        width = "100%", height = 5,
                        backgroundColor = {38, 46, 71, 255}, borderRadius = 3,
                        children = {
                            UI.Panel {
                                width = tostring(progressPct) .. "%", height = 5,
                                backgroundColor = progressPct >= 80 and Theme.COLORS.SECONDARY or Theme.COLORS.PRIMARY,
                                borderRadius = 3,
                            }
                        }
                    },
                }
            })
        end
    end

    return items
end

function Tab._buildScoutExploreContent(children, gameState, scoutFilters, scouts)
    -- 初始化模块级状态
    Tab._exploreGameState = gameState
    Tab._exploreScouts = scouts
    Tab._exploreFilterState.league = scoutFilters.league
    Tab._exploreFilterState.position = scoutFilters.position
    Tab._exploreFilterState.nationality = scoutFilters.nationality
    Tab._exploreFilterState.ageKey = scoutFilters.ageKey or "any"

    -- 创建容器并保存引用，筛选变更时通过 SetChildren 就地更新
    local container = UI.Panel {
        width = "100%",
        children = Tab._buildExploreInner(),
    }
    Tab._exploreContainerRef = container
    table.insert(children, container)
end

-- 球探子页面：球探报告列表
function Tab._buildScoutReportsContent(children, gameState)
    local reports = ScoutManager.getReports(gameState)

    if #reports == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 100,
            backgroundColor = Theme.COLORS.BG_CARD, borderRadius = 8,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无球探报告", fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                UI.Label { text = "派出球探探索后，报告将在此显示", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 6 },
            }
        })
    else
        local REC_COLORS = {
            ["强烈推荐签入"] = {0, 230, 118, 255},
            ["实力强劲，可即战"] = {102, 255, 128, 255},
            ["潜力新星，值得培养"] = {102, 178, 255, 255},
            ["水平尚可，可作补充"] = {255, 204, 0, 255},
            ["不建议签入"] = {255, 100, 100, 255},
        }
        table.insert(children, UI.Label {
            text = string.format("共 %d 份报告", #reports),
            fontSize = 12, color = Theme.COLORS.TEXT_MUTED,
            marginBottom = 8,
        })
        for _, report in ipairs(reports) do
            local recColor = REC_COLORS[report.recommendation] or Theme.COLORS.TEXT_SECONDARY
            table.insert(children, UI.Panel {
                width = "100%",
                backgroundColor = Theme.COLORS.BG_CARD,
                borderRadius = 8, padding = 10, marginBottom = 6,
                onClick = function()
                    Router.navigate("player_detail", { playerId = report.playerId })
                end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 3,
                        children = {
                            UI.Label {
                                text = report.playerPosition or "?",
                                fontSize = 10, color = Theme.COLORS.ACCENT, fontWeight = "bold", width = 30,
                            },
                            UI.Label {
                                text = report.playerName,
                                fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold", flexGrow = 1,
                            },
                            UI.Label {
                                text = tostring(report.overall),
                                fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                            },
                        }
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", alignItems = "center",
                        children = {
                            UI.Label {
                                text = report.recommendation,
                                fontSize = 10, color = recColor, fontWeight = "bold", flexGrow = 1,
                            },
                            UI.Label {
                                text = string.format("%s · %d岁", report.teamName or "?", report.playerAge or 0),
                                fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                            },
                        }
                    },
                }
            })
        end
    end
end

------------------------------------------------------
-- 球探：报告详情
------------------------------------------------------
function Tab._showReportDetail(report, gameState)
    local REC_COLORS = {
        ["强烈推荐签入"] = {0, 230, 118, 255},
        ["实力强劲，可即战"] = {102, 255, 128, 255},
        ["潜力新星，值得培养"] = {102, 178, 255, 255},
        ["水平尚可，可作补充"] = {255, 204, 0, 255},
        ["不建议签入"] = {255, 100, 100, 255},
    }
    local recColor = REC_COLORS[report.recommendation] or Theme.COLORS.TEXT_SECONDARY

    -- 属性列表
    local attrChildren = {}
    local attrLabels = {
        pace = "速度", shooting = "射门", passing = "传球",
        dribbling = "盘带", defending = "防守", physical = "身体",
    }
    local attrs = report.attributes or {}
    for key, label in pairs(attrLabels) do
        if attrs[key] then
            table.insert(attrChildren, UI.Panel {
                width = "48%", height = 28,
                flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Label { text = label, fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label {
                        text = tostring(attrs[key]),
                        fontSize = 12, fontWeight = "bold",
                        color = attrs[key] >= 15 and Theme.COLORS.SECONDARY
                            or (attrs[key] >= 10 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY),
                    },
                }
            })
        end
    end

    -- 合同信息
    local contractText = "未知"
    if report.contractEnd then
        contractText = string.format("%d年%d月到期", report.contractEnd.year or 0, report.contractEnd.month or 0)
    end

    local detailContent = {
        -- 头部：总评 + 潜力
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "center", marginBottom = 12,
            children = {
                UI.Panel {
                    alignItems = "center", marginRight = 24,
                    children = {
                        UI.Label { text = "总评", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label { text = tostring(report.overall), fontSize = 28, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                    }
                },
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = "潜力", fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                        UI.Label {
                            text = tostring(report.potential or "?"),
                            fontSize = 20, color = Theme.COLORS.SECONDARY, fontWeight = "bold",
                        },
                    }
                },
            }
        },
        -- 推荐评级
        UI.Panel {
            width = "100%", height = 32,
            backgroundColor = {recColor[1], recColor[2], recColor[3], 30},
            borderRadius = 6,
            justifyContent = "center", alignItems = "center", marginBottom = 12,
            children = {
                UI.Label { text = report.recommendation, fontSize = 13, color = recColor, fontWeight = "bold" },
            }
        },
        -- 基本信息
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between", marginBottom = 8,
            children = {
                UI.Label { text = "位置: " .. (report.playerPosition or "?"), fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                UI.Label { text = "年龄: " .. tostring(report.playerAge or 0), fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
                UI.Label { text = "准确度: " .. tostring(report.accuracy or 0) .. "%", fontSize = 11, color = Theme.COLORS.TEXT_MUTED },
            }
        },
        -- 合同/工资
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            justifyContent = "space-between", marginBottom = 12,
            children = {
                UI.Label {
                    text = "工资: " .. FinanceManager.formatMoney(report.wage or 0) .. "/周",
                    fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY,
                },
                UI.Label { text = contractText, fontSize = 11, color = Theme.COLORS.TEXT_SECONDARY },
            }
        },
        -- 属性
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap",
            justifyContent = "space-between",
            children = attrChildren,
        },
    }

    BottomSheet.showCustom({
        title = report.playerName .. " - 球探报告",
        children = detailContent,
        showCancel = true,
    })
end

return Tab
