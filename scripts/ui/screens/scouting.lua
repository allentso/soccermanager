-- ui/screens/scouting.lua
-- 球探页面：活跃任务、报告列表、指派新任务

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local ScoutManager = require("scripts/systems/scout_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local BottomSheet = require("scripts/ui/components/bottom_sheet")

local ScoutingPage = {}

-- 推荐颜色
local REC_COLORS = {
    ["强烈推荐签入"] = {0, 230, 118, 255},
    ["实力强劲，可即战"] = {102, 255, 128, 255},
    ["潜力新星，值得培养"] = {102, 178, 255, 255},
    ["水平尚可，可作补充"] = {255, 204, 0, 255},
    ["不建议签入"] = {255, 100, 100, 255},
}

------------------------------------------------------
-- 主界面
------------------------------------------------------
function ScoutingPage.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local team = gameState:getPlayerTeam()
    if not team then return UI.Panel { width = "100%", height = "100%" } end

    local activeTasks = ScoutManager.getActiveTasks(gameState)
    local reports = ScoutManager.getReports(gameState)

    -- 内容区
    local contentChildren = {}

    -- 活跃任务区
    table.insert(contentChildren, ScoutingPage._buildActiveSection(activeTasks, gameState))

    -- 分隔
    table.insert(contentChildren, UI.Panel { height = 12 })

    -- 报告区
    table.insert(contentChildren, ScoutingPage._buildReportsSection(reports, gameState))

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "球探",
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    -- 新任务按钮
                    UI.Button {
                        text = "+ 观察",
                        height = 30, paddingLeft = 8, paddingRight = 8,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 6,
                        fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        onClick = function()
                            ScoutingPage._showAssignMenu(gameState)
                        end,
                    },
                }
            },

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 10,
                children = contentChildren,
            },

            -- 底部导航
            Theme.MainNav("market"),
        }
    }
end

------------------------------------------------------
-- 活跃任务区
------------------------------------------------------
function ScoutingPage._buildActiveSection(tasks, gameState)
    local children = {
        UI.Label {
            text = string.format("进行中 (%d/3)", #tasks),
            fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY,
            fontWeight = "bold", marginBottom = 8,
        },
    }

    if #tasks == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 60,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "暂无进行中的球探任务", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, task in ipairs(tasks) do
            table.insert(children, ScoutingPage._buildTaskCard(task, gameState))
        end
    end

    return UI.Panel {
        width = "100%",
        children = children,
    }
end

function ScoutingPage._buildTaskCard(task, gameState)
    local progressPct = task.progress or 0

    -- 进度条颜色
    local barColor = Theme.COLORS.PRIMARY
    if progressPct >= 80 then barColor = Theme.COLORS.SECONDARY end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8,
        padding = 12,
        marginBottom = 6,
        children = {
            -- 第一行：球员名 + 剩余天数
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 6,
                children = {
                    UI.Label {
                        text = task.playerName,
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1,
                    },
                    UI.Label {
                        text = string.format("剩余 %d 天", task.daysRemaining),
                        fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                    },
                    -- 取消按钮
                    UI.Button {
                        text = "×",
                        width = 26, height = 26,
                        backgroundColor = {60, 30, 30, 150},
                        borderRadius = 13,
                        fontSize = 14, color = Theme.COLORS.DANGER,
                        marginLeft = 8,
                        onClick = function()
                            ConfirmDialog.show({
                                title = "取消球探任务",
                                message = "确定取消对 " .. task.playerName .. " 的观察？",
                                confirmText = "取消任务",
                                danger = true,
                                onConfirm = function()
                                    ScoutManager.cancelTask(gameState, task.id)
                                    Router.replaceWith("scouting")
                                end,
                            })
                        end,
                    },
                }
            },
            -- 进度条
            UI.Panel {
                width = "100%", height = 6,
                backgroundColor = {38, 46, 71, 255},
                borderRadius = 3,
                children = {
                    UI.Panel {
                        width = tostring(progressPct) .. "%",
                        height = 6,
                        backgroundColor = barColor,
                        borderRadius = 3,
                    }
                }
            },
        }
    }
end

------------------------------------------------------
-- 报告区
------------------------------------------------------
function ScoutingPage._buildReportsSection(reports, gameState)
    local children = {
        UI.Label {
            text = string.format("球探报告 (%d)", #reports),
            fontSize = 13, color = Theme.COLORS.TEXT_SECONDARY,
            fontWeight = "bold", marginBottom = 8,
        },
    }

    if #reports == 0 then
        table.insert(children, UI.Panel {
            width = "100%", height = 60,
            backgroundColor = Theme.COLORS.BG_CARD,
            borderRadius = 8,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "暂无球探报告", fontSize = 12, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    else
        for _, report in ipairs(reports) do
            table.insert(children, ScoutingPage._buildReportCard(report, gameState))
        end
    end

    return UI.Panel {
        width = "100%",
        children = children,
    }
end

function ScoutingPage._buildReportCard(report, gameState)
    local recColor = REC_COLORS[report.recommendation] or Theme.COLORS.TEXT_SECONDARY

    -- 潜力差值
    local potDiff = (report.potential or 0) - (report.overall or 0)
    local potLabel = ""
    local potColor = Theme.COLORS.TEXT_MUTED
    if potDiff >= 15 then
        potLabel = "↑↑"
        potColor = {0, 230, 118, 255}
    elseif potDiff >= 8 then
        potLabel = "↑"
        potColor = Theme.COLORS.SECONDARY
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 8,
        padding = 12,
        marginBottom = 6,
        onClick = function()
            ScoutingPage._showReportDetail(report, gameState)
        end,
        children = {
            -- 第一行：球员 + 位置 + 年龄 + 球队
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 4,
                children = {
                    UI.Label {
                        text = report.playerPosition or "?",
                        fontSize = 11, color = Theme.COLORS.ACCENT,
                        fontWeight = "bold", width = 32,
                    },
                    UI.Label {
                        text = report.playerName,
                        fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1,
                    },
                    -- 能力/潜力
                    UI.Label {
                        text = tostring(report.overall),
                        fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = potLabel,
                        fontSize = 12, color = potColor,
                        marginLeft = 2, width = 18,
                    },
                }
            },
            -- 第二行：推荐 + 球队 + 年龄
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                children = {
                    UI.Label {
                        text = report.recommendation,
                        fontSize = 11, color = recColor, fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = string.format("%s · %d岁", report.teamName or "?", report.playerAge or 0),
                        fontSize = 10, color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
        }
    }
end

------------------------------------------------------
-- 报告详情
------------------------------------------------------
function ScoutingPage._showReportDetail(report, gameState)
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
                        UI.Label { text = tostring(report.potential), fontSize = 28, color = Theme.COLORS.SECONDARY, fontWeight = "bold" },
                    }
                },
            }
        },

        -- 推荐评级
        UI.Panel {
            width = "100%", height = 32,
            backgroundColor = {recColor[1], recColor[2], recColor[3], 30},
            borderRadius = 6,
            justifyContent = "center", alignItems = "center",
            marginBottom = 12,
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

------------------------------------------------------
-- 指派球探任务
------------------------------------------------------
function ScoutingPage._showAssignMenu(gameState)
    -- 获取其他球队的球员列表（供选择观察目标）
    local candidates = ScoutingPage._getScoutCandidates(gameState)

    if #candidates == 0 then
        ConfirmDialog.show({
            title = "无可观察球员",
            message = "当前没有可观察的目标球员",
            confirmText = "知道了",
            onConfirm = function() end,
        })
        return
    end

    -- 构建选择列表
    local listItems = {}
    for _, c in ipairs(candidates) do
        table.insert(listItems, UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingTop = 8, paddingBottom = 8,
            borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
            children = {
                -- 位置
                UI.Label {
                    text = c.position, fontSize = 11, color = Theme.COLORS.ACCENT,
                    fontWeight = "bold", width = 32,
                },
                -- 名字 + 球队
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    children = {
                        UI.Label { text = c.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                        UI.Label {
                            text = string.format("%s · %d岁 · OVR %d", c.teamName, c.age, c.overall),
                            fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 1,
                        },
                    }
                },
                -- 观察按钮
                UI.Button {
                    text = "观察",
                    height = 28, paddingLeft = 10, paddingRight = 10,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 6,
                    fontSize = 11, color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        UI.CloseOverlay()
                        local ok, err = ScoutManager.assignScout(gameState, c.id)
                        if ok then
                            Router.replaceWith("scouting")
                        else
                            ConfirmDialog.show({
                                title = "无法指派",
                                message = err or "操作失败",
                                confirmText = "知道了",
                                onConfirm = function() end,
                            })
                        end
                    end,
                },
            }
        })
    end

    BottomSheet.showCustom({
        title = "选择观察目标",
        children = listItems,
        showCancel = true,
    })
end

--- 获取可被球探观察的候选球员（其他球队 + 自由球员中的优质选手）
function ScoutingPage._getScoutCandidates(gameState)
    local candidates = {}
    local myTeamId = gameState.playerTeamId

    for pid, player in pairs(gameState.players) do
        -- 排除自己球队的球员
        if player.teamId ~= myTeamId then
            -- 只展示一定能力的球员
            if (player.overall or 0) >= 55 then
                local teamName = "自由球员"
                if player.teamId then
                    local t = gameState.teams[player.teamId]
                    if t then teamName = t.name end
                end

                table.insert(candidates, {
                    id = player.id,
                    displayName = player.displayName,
                    position = player.position,
                    overall = player.overall or 50,
                    age = player:getAge(gameState.date.year),
                    teamName = teamName,
                })
            end
        end
    end

    -- 按能力排序
    table.sort(candidates, function(a, b) return a.overall > b.overall end)

    -- 只取前20个
    local result = {}
    for i = 1, math.min(20, #candidates) do
        table.insert(result, candidates[i])
    end
    return result
end

return ScoutingPage
