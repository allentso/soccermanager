--- 经理页 - 资料/履历/声望
local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local Theme = require("scripts/ui/theme")

local COLORS = Theme.COLORS

local ManagerView = {}

------------------------------------------------------------
-- 辅助
------------------------------------------------------------

local function repBar(reputation, maxRep)
    maxRep = maxRep or 1000
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
                UI.Label { text = tostring(manager.reputation) .. " / 1000", fontSize = 13, color = COLORS.TEXT_PRIMARY },
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

-- 声望等级文本
function ManagerView._repLevel(rep)
    if rep >= 900 then return "传奇"
    elseif rep >= 700 then return "世界级"
    elseif rep >= 500 then return "洲际级"
    elseif rep >= 300 then return "国内级"
    elseif rep >= 150 then return "地区级"
    else return "新人" end
end

return ManagerView
