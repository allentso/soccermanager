--- 经理页 - 资料/履历/声望/求职/合同
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")
local JobManager = require("scripts/systems/job_manager")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")

local COLORS = Theme.COLORS

local ManagerView = {}

------------------------------------------------------------
-- 辅助
------------------------------------------------------------

local function repBar(reputation, maxRep)
    maxRep = maxRep or 99
    local pct = math.min(100, math.floor(reputation / maxRep * 100))
    local color
    if pct >= 75 then color = COLORS.SECONDARY
    elseif pct >= 50 then color = COLORS.PRIMARY
    elseif pct >= 25 then color = COLORS.WARNING
    else color = COLORS.DANGER end
    return UI.Panel {
        width = "100%", height = 16, borderRadius = 4, backgroundColor = COLORS.BG_HEADER, marginTop = 6,
        children = {
            UI.Panel { width = tostring(pct) .. "%", height = 16, borderRadius = 4, backgroundColor = color }
        }
    }
end

local function statRow(label, value, color)
    return UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        paddingVertical = 5,
        children = {
            UI.Label { text = label, fontSize = 12, color = COLORS.TEXT_SECONDARY },
            UI.Label { text = tostring(value), fontSize = 12, fontWeight = "bold", color = color or COLORS.TEXT_PRIMARY },
        }
    }
end

--- 安全取整供 string.format("%d") 使用（避免 NaN/浮点导致崩溃）
local function safeDisplayInt(value, default)
    local n = tonumber(value)
    if not n or n ~= n then return default or 0 end
    return math.max(0, math.floor(n))
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

function ManagerView.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel { width = "100%", height = "100%", children = {} }
    end

    -- 支持查看任意经理（默认为玩家自己）
    local managerId = params and params.managerId or gameState.playerManagerId
    local manager = managerId and gameState.managers[managerId]
    if not manager then
        return UI.Panel { width = "100%", height = "100%", children = {
            Theme.TopBar { children = {
                UI.Panel { width = 60, height = 32, justifyContent = "center", onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } } },
                UI.Label { text = "经理", fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
                UI.Panel { width = 60 },
            }},
            UI.Panel { width = "100%", padding = 20, children = {
                UI.Label { text = "经理数据不存在", fontSize = 14, color = COLORS.TEXT_MUTED }
            }}
        }}
    end

    -- 当前执教球队
    local currentTeam = manager.teamId and gameState.teams[manager.teamId]
    local currentTeamName = currentTeam and currentTeam.name or "自由身"

    -- 计算总比赛场次
    local totalMatches = (manager.stats.wins or 0) + (manager.stats.draws or 0) + (manager.stats.losses or 0)
    local winRate = totalMatches > 0 and math.floor(manager.stats.wins / totalMatches * 100) or 0

    -- 估算年龄
    local currentYear = gameState.date and gameState.date.year or 2024
    local age = currentYear - (manager.birthYear or 1985)

    local content = {}

    -- 1. 个人资料卡
    table.insert(content, Theme.Card { children = {
        Theme.Subtitle { text = "个人资料" },
        UI.Panel {
            width = "100%", alignItems = "center", marginTop = 8, marginBottom = 8,
            children = {
                -- 头像占位
                UI.Panel {
                    width = 64, height = 64, borderRadius = 32,
                    backgroundColor = COLORS.PRIMARY,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = string.sub(manager.displayName, 1, 1), fontSize = 24, fontWeight = "bold", color = COLORS.TEXT_PRIMARY }
                    }
                },
                UI.Label { text = manager.displayName, fontSize = 16, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, marginTop = 8 },
                UI.Label { text = currentTeamName, fontSize = 12, color = COLORS.TEXT_SECONDARY, marginTop = 2 },
            }
        },
        Theme.Divider(),
        statRow("年龄", tostring(age) .. " 岁"),
        statRow("国籍", manager.nationality),
        statRow("身份", manager.isPlayer and "玩家经理" or "AI经理"),
    }})

    -- 2. 声望卡
    table.insert(content, Theme.Card { children = {
        Theme.Subtitle { text = "声望" },
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 4,
            children = {
                UI.Label { text = ManagerView._formatRep(manager.reputation) .. " / 99", fontSize = 13, color = COLORS.TEXT_PRIMARY },
                UI.Label { text = ManagerView._repLevel(manager.reputation), fontSize = 11, color = COLORS.ACCENT, fontWeight = "bold" },
            }
        },
        repBar(manager.reputation),
    }})

    -- 3. 执教数据卡
    table.insert(content, Theme.Card { children = {
        Theme.Subtitle { text = "执教数据" },
        UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-around", marginTop = 8, children = {
            Theme.StatPill { label = "总场次", value = tostring(totalMatches) },
            Theme.StatPill { label = "胜率", value = tostring(winRate) .. "%", valueColor = COLORS.SECONDARY },
            Theme.StatPill { label = "冠军", value = tostring(manager.stats.trophies or 0), valueColor = COLORS.WARNING },
        }},
        Theme.Divider(),
        statRow("胜", tostring(manager.stats.wins or 0), COLORS.SECONDARY),
        statRow("平", tostring(manager.stats.draws or 0), COLORS.WARNING),
        statRow("负", tostring(manager.stats.losses or 0), COLORS.DANGER),
    }})

    -- 4. 执教履历卡
    local career = manager.career or {}
    if #career > 0 then
        local careerRows = {}
        for i = #career, math.max(1, #career - 9), -1 do
            local c = career[i]
            local period = tostring(c.startYear or "?") .. " - " .. (c.endYear and tostring(c.endYear) or "至今")
            local statsText = ""
            if c.stats then
                local cW = c.stats.wins or 0
                local cD = c.stats.draws or 0
                local cL = c.stats.losses or 0
                statsText = tostring(cW) .. "胜 " .. tostring(cD) .. "平 " .. tostring(cL) .. "负"
                local reasonLabels = {
                    sacked = "解雇",
                    resigned = "辞职",
                    relegated = "降级解约",
                    contract_expired = "合同到期",
                }
                if c.stats.reason then
                    statsText = statsText .. " · " .. (reasonLabels[c.stats.reason] or c.stats.reason)
                end
            end
            table.insert(careerRows, UI.Panel {
                width = "100%", paddingVertical = 8,
                borderBottomWidth = 1, borderColor = COLORS.BORDER,
                onClick = c.teamId and function()
                    Router.navigate("team_detail", { teamId = c.teamId })
                end or nil,
                children = {
                    UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", children = {
                        UI.Label { text = c.teamName or "未知球队", fontSize = 13, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
                        UI.Label { text = period, fontSize = 11, color = COLORS.TEXT_MUTED },
                    }},
                    statsText ~= "" and UI.Label { text = statsText, fontSize = 11, color = COLORS.TEXT_SECONDARY, marginTop = 2 } or nil,
                }
            })
        end
        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "执教履历" },
            table.unpack(careerRows)
        }})
    else
        table.insert(content, Theme.Card { children = {
            Theme.Subtitle { text = "执教履历" },
            UI.Label { text = "暂无执教记录", fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 4 },
        }})
    end

    -- 5. 合同信息卡（仅玩家自己在职时显示）
    if managerId == gameState.playerManagerId and manager.teamId then
        table.insert(content, ManagerView._buildContractCard(gameState, manager))
    end

    -- 6. 求职中心（仅玩家自己的资料页显示）
    if managerId == gameState.playerManagerId then
        table.insert(content, ManagerView._buildJobCenter(gameState, manager))
    end

    -- 页面布局
    local isOwnManager = (managerId == gameState.playerManagerId)
    local title = isOwnManager and "我的资料" or manager.displayName

    return UI.Panel {
        width = "100%", height = "100%", backgroundColor = COLORS.BG_DARK,
        children = {
            Theme.TopBar { children = {
                UI.Panel { width = 60, height = 32, justifyContent = "center", onClick = function() Router.back() end,
                    children = { UI.Label { text = "← 返回", fontSize = 12, color = COLORS.TEXT_SECONDARY } } },
                UI.Label { text = title, fontSize = 15, fontWeight = "bold", color = COLORS.TEXT_PRIMARY, flex = 1, textAlign = "center" },
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

-- 声望等级文本（1-99量纲）
function ManagerView._formatRep(rep)
    rep = rep or 0
    if math.abs(rep - math.floor(rep + 0.001)) < 0.05 then
        return tostring(math.floor(rep + 0.001))
    end
    return string.format("%.1f", rep)
end

function ManagerView._repLevel(rep)
    if rep >= 85 then return "传奇"
    elseif rep >= 70 then return "世界级"
    elseif rep >= 55 then return "洲际级"
    elseif rep >= 40 then return "国内级"
    elseif rep >= 25 then return "地区级"
    else return "新人" end
end

------------------------------------------------------------
-- 合同信息卡
------------------------------------------------------------

function ManagerView._buildContractCard(gameState, manager)
    local children = {}
    table.insert(children, Theme.Subtitle { text = "我的合同" })

    local team = gameState.teams[manager.teamId]
    local teamName = team and team.name or "未知"

    -- 合同状态
    local monthsLeft = JobManager.getManagerContractMonths(gameState, manager)
    local contractStatus
    local statusColor
    if not manager.contractEnd then
        contractStatus = "无固定期限"
        statusColor = COLORS.TEXT_MUTED
    elseif monthsLeft <= 6 then
        contractStatus = string.format("剩余 %d 个月（即将到期）", monthsLeft)
        statusColor = COLORS.DANGER
    elseif monthsLeft <= 12 then
        contractStatus = string.format("剩余 %d 个月", monthsLeft)
        statusColor = COLORS.WARNING
    else
        contractStatus = string.format("剩余 %d 个月", monthsLeft)
        statusColor = COLORS.SECONDARY
    end

    table.insert(children, statRow("执教球队", teamName))
    table.insert(children, statRow("周薪", JobManager._formatMoney(manager.wage or 0)))
    if manager.contractEnd then
        table.insert(children, statRow("合同到期",
            string.format("%d年%d月", manager.contractEnd.year, manager.contractEnd.month)))
    end
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        paddingVertical = 5,
        children = {
            UI.Label { text = "合同状态", fontSize = 12, color = COLORS.TEXT_SECONDARY },
            UI.Label { text = contractStatus, fontSize = 12, fontWeight = "bold", color = statusColor },
        }
    })

    -- 续约提议处理
    local offer = gameState._managerRenewalOffer
    if offer then
        table.insert(children, Theme.Divider())
        table.insert(children, UI.Panel {
            width = "100%", padding = 10, borderRadius = 8,
            backgroundColor = {60, 120, 180, 30}, marginTop = 8,
            children = {
                UI.Label { text = "俱乐部续约提议", fontSize = 13, fontWeight = "bold", color = COLORS.PRIMARY, marginBottom = 6 },
                UI.Label {
                    text = string.format("新周薪: %s  |  年限: %d年", JobManager._formatMoney(offer.wage), offer.years),
                    fontSize = 12, color = COLORS.TEXT_PRIMARY, marginBottom = 8,
                },
                UI.Panel { flexDirection = "row", children = {
                    UI.Button {
                        text = "接受续约", variant = "primary", size = "sm",
                        flex = 1, marginRight = 6,
                        onClick = function()
                            JobManager.acceptManagerRenewal(gameState)
                            Router.replaceWith("manager_view")
                        end,
                    },
                    UI.Button {
                        text = "拒绝", variant = "outline", size = "sm",
                        flex = 1, marginLeft = 6,
                        onClick = function()
                            JobManager.declineManagerRenewal(gameState)
                            Router.replaceWith("manager_view")
                        end,
                    },
                }},
            }
        })
    end

    -- 辞职按钮
    table.insert(children, Theme.Divider())
    table.insert(children, UI.Button {
        text = "辞职",
        width = "100%", height = 40, marginTop = 8,
        backgroundColor = COLORS.DANGER,
        borderRadius = 8, fontSize = 13,
        color = {255, 255, 255, 255},
        onClick = function()
            ConfirmDialog.show({
                title = "确认辞职",
                message = string.format(
                    "你确定要辞去 %s 的主教练职务吗？\n\n辞职后你将成为自由身，需要重新找工作。",
                    teamName
                ),
                confirmText = "确认辞职",
                danger = true,
                onConfirm = function()
                    local success, err = JobManager.handleResign(gameState)
                    if success then
                        Router.replaceWith("manager_view")
                    end
                end,
            })
        end,
    })

    return Theme.Card { children = children }
end

------------------------------------------------------------
-- 求职中心
------------------------------------------------------------

--- 获取所有球队的职位信息，按状态分类
---@param gameState table
---@return table vacancies, table dangerJobs, table safeJobs
local function _classifyJobs(gameState)
    local vacancies = {}   -- 空缺（无主教练）
    local dangerJobs = {}  -- 危险（主教练即将被解雇）
    local safeJobs = {}    -- 安全（正常）

    for teamId, team in pairs(gameState.teams) do
        if teamId == gameState.playerTeamId then goto continue end

        local leagueName = nil
        for _, lg in pairs(gameState.leagues or {}) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == teamId then
                    leagueName = lg.name or lg.key
                    break
                end
            end
            if leagueName then break end
        end
        if not leagueName then goto continue end

        local entry = {
            teamId = teamId,
            teamName = team.name or team.shortName or "未知",
            leagueName = leagueName,
            reputation = team.reputation or 50,
            boardSatisfaction = team.boardSatisfaction,
            boardWarnings = team.boardWarnings or 0,
        }

        if team.managerVacant then
            entry.status = "vacant"
            entry.statusText = "空缺"
            entry.statusColor = COLORS.DANGER
            table.insert(vacancies, entry)
        elseif (team.boardSatisfaction or 50) < 30 or (team.boardWarnings or 0) >= 2 then
            entry.status = "danger"
            entry.statusText = "危险"
            entry.statusColor = COLORS.WARNING
            table.insert(dangerJobs, entry)
        else
            entry.status = "safe"
            entry.statusText = "稳定"
            entry.statusColor = COLORS.SECONDARY
            table.insert(safeJobs, entry)
        end

        ::continue::
    end

    -- 排序：空缺和危险按声望降序，安全只取前几个
    table.sort(vacancies, function(a, b) return a.reputation > b.reputation end)
    table.sort(dangerJobs, function(a, b) return a.reputation > b.reputation end)
    table.sort(safeJobs, function(a, b) return a.reputation > b.reputation end)

    return vacancies, dangerJobs, safeJobs
end

--- 检查某球队是否已在审核中
local function _isApplicationPending(gameState, teamId)
    local apps = gameState._pendingApplications or {}
    for _, app in ipairs(apps) do
        if app.teamId == teamId then
            return true, app.daysLeft
        end
    end
    return false, 0
end

--- 构建单个职位行
local function _jobRow(entry, gameState, manager, isUnemployed)
    local isPending, pendingDays = _isApplicationPending(gameState, entry.teamId)
    local canApply = isUnemployed and entry.status == "vacant" and not isPending
    local repDiff = (entry.reputation or 50) - (manager.reputation or 30)
    local diffLabel = ""
    local diffColor = COLORS.TEXT_MUTED
    if repDiff > 20 then
        diffLabel = " (很难)"
        diffColor = COLORS.DANGER
    elseif repDiff > 10 then
        diffLabel = " (较难)"
        diffColor = COLORS.WARNING
    elseif repDiff > 0 then
        diffLabel = " (一般)"
        diffColor = COLORS.TEXT_SECONDARY
    else
        diffLabel = " (容易)"
        diffColor = COLORS.SECONDARY
    end

    local rightChildren = {
        UI.Panel { flexDirection = "row", alignItems = "center", children = {
            UI.Panel {
                width = 8, height = 8, borderRadius = 4,
                backgroundColor = entry.statusColor, marginRight = 4,
            },
            UI.Label { text = entry.statusText, fontSize = 10, color = entry.statusColor },
        }},
    }

    if isPending then
        -- 已申请，审核中
        table.insert(rightChildren, UI.Label {
            text = string.format("审核中(%d天)", pendingDays),
            fontSize = 10, color = COLORS.PRIMARY, marginTop = 4,
        })
    elseif canApply then
        table.insert(rightChildren, UI.Button {
            text = "申请", variant = "primary", size = "sm",
            marginTop = 4,
            onClick = function()
                JobManager.applyForJob(gameState, entry.teamId)
                local SaveManager = require("scripts/persistence/save_manager")
                SaveManager.save(gameState, "auto")
                Router.replaceWith("manager_view")
            end,
        })
    end

    return UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between",
        alignItems = "center", paddingVertical = 8,
        borderBottomWidth = 1, borderColor = COLORS.BORDER,
        children = {
            UI.Panel { flex = 1, children = {
                UI.Panel { flexDirection = "row", alignItems = "center", children = {
                    UI.Label { text = entry.teamName, fontSize = 13, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
                    UI.Label { text = diffLabel, fontSize = 10, color = diffColor },
                }},
                UI.Label { text = entry.leagueName, fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 2 },
            }},
            UI.Panel { alignItems = "flex-end", children = rightChildren },
        }
    }
end

--- 构建求职中心卡片
function ManagerView._buildJobCenter(gameState, manager)
    local JobManager = require("scripts/systems/job_manager")
    JobManager.syncJobSeekingState(gameState)
    local isUnemployed = JobManager.isJobSeeking(gameState)
    local vacancies, dangerJobs, safeJobs = _classifyJobs(gameState)

    local children = {}
    table.insert(children, Theme.Subtitle { text = "求职中心" })

    -- 状态提示
    if isUnemployed then
        local days = JobManager.getUnemployedDays(gameState)
        table.insert(children, UI.Panel {
            width = "100%", padding = 8, borderRadius = 6,
            backgroundColor = {180, 60, 60, 40}, marginBottom = 8,
            children = {
                UI.Label {
                    text = string.format("当前状态: 自由身（已失业 %d 天）", days),
                    fontSize = 11, color = COLORS.WARNING,
                },
            }
        })

        -- 待确认 Offer 列表（含主动邀约和申请通过的）
        local offers = JobManager.getPendingOffers(gameState)
        if #offers > 0 then
            table.insert(children, UI.Panel {
                width = "100%", padding = 10, borderRadius = 8,
                backgroundColor = {60, 120, 180, 30}, marginBottom = 10,
                children = (function()
                    local offerChildren = {
                        UI.Label {
                            text = string.format("待确认 Offer (%d)", #offers),
                            fontSize = 13, fontWeight = "bold", color = COLORS.PRIMARY, marginBottom = 6,
                        },
                    }
                    for _, offer in ipairs(offers) do
                        local sourceLabel = offer.source == "application" and "申请通过" or "主动邀约"
                        local sourceColor = offer.source == "application" and COLORS.SECONDARY or COLORS.PRIMARY
                        table.insert(offerChildren, UI.Panel {
                            width = "100%", flexDirection = "row", justifyContent = "space-between",
                            alignItems = "center", paddingVertical = 8,
                            borderBottomWidth = 1, borderColor = COLORS.BORDER,
                            children = {
                                UI.Panel { flex = 1, children = {
                                    UI.Panel { flexDirection = "row", alignItems = "center", children = {
                                        UI.Label { text = offer.teamName or "球队", fontSize = 13, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
                                        UI.Panel {
                                            marginLeft = 6, paddingHorizontal = 4, paddingVertical = 1,
                                            borderRadius = 3, backgroundColor = sourceColor,
                                            children = {
                                                UI.Label { text = sourceLabel, fontSize = 9, color = {255,255,255,255} },
                                            }
                                        },
                                    }},
                                    UI.Label {
                                        text = string.format("%s | 声望 %s | %d天后过期",
                                            offer.leagueName or "联赛",
                                            ManagerView._formatRep(offer.teamRep or 50),
                                            safeDisplayInt(offer.expireDays, 0)),
                                        fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 2,
                                    },
                                }},
                                UI.Panel { flexDirection = "row", alignItems = "center", children = {
                                    UI.Button {
                                        text = "接受", variant = "primary", size = "sm",
                                        onClick = function()
                                            JobManager.acceptOffer(gameState, offer.teamId)
                                            local SaveManager = require("scripts/persistence/save_manager")
                                            SaveManager.save(gameState, "auto")
                                            Router.replaceWith("dashboard")
                                        end,
                                    },
                                    UI.Button {
                                        text = "拒绝", variant = "ghost", size = "sm", marginLeft = 4,
                                        onClick = function()
                                            JobManager.declineOffer(gameState, offer.teamId)
                                            local SaveManager = require("scripts/persistence/save_manager")
                                            SaveManager.save(gameState, "auto")
                                            Router.replaceWith("manager_view")
                                        end,
                                    },
                                }},
                            }
                        })
                    end
                    return offerChildren
                end)(),
            })
        end

        -- 待审核申请提示
        local pendingApps = gameState._pendingApplications or {}
        if #pendingApps > 0 then
            table.insert(children, UI.Panel {
                width = "100%", padding = 8, borderRadius = 6,
                backgroundColor = {60, 160, 120, 40}, marginBottom = 8,
                children = {
                    UI.Label {
                        text = string.format("已投递 %d 份申请，等待球队审核回复中...", #pendingApps),
                        fontSize = 11, color = COLORS.SECONDARY,
                    },
                }
            })
        end
    else
        table.insert(children, UI.Panel {
            width = "100%", padding = 8, borderRadius = 6,
            backgroundColor = {60, 120, 60, 40}, marginBottom = 8,
            children = {
                UI.Label {
                    text = "当前状态: 在职（辞职后可申请空缺职位）",
                    fontSize = 11, color = COLORS.TEXT_SECONDARY,
                },
            }
        })
    end

    -- 空缺职位
    if #vacancies > 0 then
        table.insert(children, UI.Label {
            text = string.format("空缺职位 (%d)", #vacancies),
            fontSize = 12, fontWeight = "bold", color = COLORS.DANGER, marginTop = 8, marginBottom = 4,
        })
        for i = 1, math.min(5, #vacancies) do
            table.insert(children, _jobRow(vacancies[i], gameState, manager, isUnemployed))
        end
        if #vacancies > 5 then
            table.insert(children, UI.Label {
                text = string.format("... 还有 %d 个空缺", #vacancies - 5),
                fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 4,
            })
        end
    end

    -- 危险职位
    if #dangerJobs > 0 then
        table.insert(children, UI.Label {
            text = string.format("主教练危险 (%d)", #dangerJobs),
            fontSize = 12, fontWeight = "bold", color = COLORS.WARNING, marginTop = 12, marginBottom = 4,
        })
        for i = 1, math.min(5, #dangerJobs) do
            table.insert(children, _jobRow(dangerJobs[i], gameState, manager, isUnemployed))
        end
        if #dangerJobs > 5 then
            table.insert(children, UI.Label {
                text = string.format("... 还有 %d 个", #dangerJobs - 5),
                fontSize = 10, color = COLORS.TEXT_MUTED, marginTop = 4,
            })
        end
    end

    -- 安全职位（只显示前3个高声望的作为参考）
    if #safeJobs > 0 then
        table.insert(children, UI.Label {
            text = "稳定球队（参考）",
            fontSize = 12, fontWeight = "bold", color = COLORS.SECONDARY, marginTop = 12, marginBottom = 4,
        })
        for i = 1, math.min(3, #safeJobs) do
            table.insert(children, _jobRow(safeJobs[i], gameState, manager, isUnemployed))
        end
    end

    -- 没有任何职位
    if #vacancies == 0 and #dangerJobs == 0 then
        table.insert(children, UI.Label {
            text = "目前没有空缺职位，请等待机会...",
            fontSize = 12, color = COLORS.TEXT_MUTED, marginTop = 8,
        })
    end

    return Theme.Card { children = children }
end

return ManagerView
