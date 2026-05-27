-- ui/screens/transfer_hub.lua
-- 全球转会中心 - 查看整个联赛/世界的转会动态

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local HistoryManager = require("scripts/systems/history_manager")
local TransferManager = require("scripts/systems/transfer_manager")

local TransferHub = {}

---@type string
local _activeTab = "recent" -- recent | top | free | rumours

function TransferHub.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "无数据" } }
        }
    end

    if params and params.tab then
        _activeTab = params.tab
    end

    local content
    if _activeTab == "top" then
        content = TransferHub._buildTopDeals(gameState)
    elseif _activeTab == "free" then
        content = TransferHub._buildFreeAgents(gameState)
    elseif _activeTab == "rumours" then
        content = TransferHub._buildRumours(gameState)
    else
        content = TransferHub._buildRecent(gameState)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.back() end,
                    },
                    UI.Label {
                        text = "全球转会中心",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 60 },
                }
            },

            -- Tab 切换
            TransferHub._buildTabBar(),

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = content,
            },

            Theme.MainNav("market"),
        }
    }
end

function TransferHub._buildTabBar()
    local tabs = {
        { key = "recent",  label = "最新动态" },
        { key = "top",     label = "重磅交易" },
        { key = "free",    label = "自由球员" },
        { key = "rumours", label = "转会传闻" },
    }
    local children = {}
    for _, t in ipairs(tabs) do
        local isActive = t.key == _activeTab
        table.insert(children, UI.Button {
            text = t.label,
            height = 32,
            paddingLeft = 12,
            paddingRight = 12,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            fontWeight = isActive and "bold" or "normal",
            marginRight = 4,
            onClick = function()
                if not isActive then
                    _activeTab = t.key
                    Router.replaceWith("transfer_hub", { tab = t.key })
                end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        backgroundColor = Theme.COLORS.BG_HEADER,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = children,
    }
end

---------------------------------------------------------------------------
-- 最新转会动态（按时间倒序）
---------------------------------------------------------------------------
function TransferHub._buildRecent(gameState)
    local allHistory = HistoryManager.getTransferHistory(gameState)
    -- 倒序取最近30条
    local recent = {}
    local count = math.min(30, #allHistory)
    for i = #allHistory, math.max(1, #allHistory - count + 1), -1 do
        table.insert(recent, allHistory[i])
    end

    if #recent == 0 then
        return {
            Theme.Card {
                children = {
                    UI.Label {
                        text = "暂无转会记录",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_MUTED,
                        textAlign = "center",
                    },
                }
            }
        }
    end

    local rows = {}
    for _, t in ipairs(recent) do
        table.insert(rows, TransferHub._transferRow(t, gameState))
    end

    return {
        Theme.Card {
            children = {
                Theme.Subtitle { text = "最近 " .. #recent .. " 笔转会" },
                UI.Panel { width = "100%", children = rows },
            }
        },
    }
end

---------------------------------------------------------------------------
-- 重磅交易（按金额排序 Top 15）
---------------------------------------------------------------------------
function TransferHub._buildTopDeals(gameState)
    local allHistory = HistoryManager.getTransferHistory(gameState)
    -- 按金额排序
    local sorted = {}
    for _, t in ipairs(allHistory) do
        if (t.amount or 0) > 0 then
            table.insert(sorted, t)
        end
    end
    table.sort(sorted, function(a, b) return (a.amount or 0) > (b.amount or 0) end)

    local top = {}
    for i = 1, math.min(15, #sorted) do
        table.insert(top, sorted[i])
    end

    if #top == 0 then
        return {
            Theme.Card {
                children = {
                    UI.Label {
                        text = "暂无付费转会",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_MUTED,
                        textAlign = "center",
                    },
                }
            }
        }
    end

    local rows = {}
    for idx, t in ipairs(top) do
        table.insert(rows, TransferHub._topDealRow(t, idx, gameState))
    end

    return {
        Theme.Card {
            children = {
                Theme.Subtitle { text = "赛季最贵签约 Top " .. #top },
                UI.Panel { width = "100%", children = rows },
            }
        },
    }
end

---------------------------------------------------------------------------
-- 自由球员市场（所有可签约球员）
---------------------------------------------------------------------------
function TransferHub._buildFreeAgents(gameState)
    local freeAgents = TransferManager.getFreeAgents(gameState)
    -- 按能力排序
    table.sort(freeAgents, function(a, b) return a.overall > b.overall end)

    if #freeAgents == 0 then
        return {
            Theme.Card {
                children = {
                    UI.Label {
                        text = "暂无自由球员",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_MUTED,
                        textAlign = "center",
                    },
                }
            }
        }
    end

    local rows = {}
    for i = 1, math.min(25, #freeAgents) do
        local p = freeAgents[i]
        table.insert(rows, UI.Panel {
            width = "100%",
            height = 44,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 8,
            paddingRight = 8,
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                UI.Label {
                    text = Constants.POSITION_NAMES[p.position] or p.position,
                    fontSize = 11,
                    color = Theme.COLORS.ACCENT,
                    width = 44,
                },
                UI.Label {
                    text = p.displayName,
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1,
                },
                UI.Label {
                    text = tostring(p.overall),
                    fontSize = 13,
                    color = p.overall >= 70 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_SECONDARY,
                    width = 30,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = tostring(p.age or "?"),
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                    width = 28,
                },
                UI.Button {
                    text = "签约",
                    width = 50,
                    height = 28,
                    backgroundColor = Theme.COLORS.SECONDARY,
                    borderRadius = 6,
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        Router.navigate("market", { tab = "free" })
                    end,
                },
            }
        })
    end

    return {
        Theme.Card {
            children = {
                Theme.Subtitle { text = "自由球员 (" .. #freeAgents .. "人)" },
                UI.Panel { width = "100%", children = rows },
            }
        },
    }
end

---------------------------------------------------------------------------
-- 转会传闻（显示当前活跃的AI/玩家报价）
---------------------------------------------------------------------------
function TransferHub._buildRumours(gameState)
    -- 收集所有活跃报价
    TransferManager._ensureData(gameState)
    local bids = gameState.transfers.bids or {}
    local activeBids = {}
    for _, bid in ipairs(bids) do
        if bid.status == "pending" or bid.status == "negotiating" then
            table.insert(activeBids, bid)
        end
    end

    if #activeBids == 0 then
        return {
            Theme.Card {
                children = {
                    UI.Label {
                        text = "目前没有活跃的转会谈判",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_MUTED,
                        textAlign = "center",
                    },
                }
            }
        }
    end

    local rows = {}
    for _, bid in ipairs(activeBids) do
        local player = gameState.players[bid.playerId]
        local fromTeam = gameState.teams[bid.sellerTeamId or bid.fromTeamId]
        local toTeam = gameState.teams[bid.buyerTeamId or bid.toTeamId]
        local playerName = player and player.displayName or "未知球员"
        local fromName = fromTeam and fromTeam.name or "?"
        local toName = toTeam and toTeam.name or "?"

        local typeLabel = "永久"
        if bid.type == "loan" then typeLabel = "租借" end

        table.insert(rows, UI.Panel {
            width = "100%",
            paddingTop = 8,
            paddingBottom = 8,
            paddingLeft = 8,
            paddingRight = 8,
            borderBottomWidth = 1,
            borderColor = Theme.COLORS.BORDER,
            children = {
                -- 球员名 + 类型
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    marginBottom = 4,
                    children = {
                        UI.Label {
                            text = playerName,
                            fontSize = 13,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = typeLabel,
                            fontSize = 10,
                            color = Theme.COLORS.ACCENT,
                            backgroundColor = {51, 41, 10, 255},
                            borderRadius = 4,
                            paddingLeft = 6,
                            paddingRight = 6,
                            paddingTop = 2,
                            paddingBottom = 2,
                        },
                    }
                },
                -- 从 -> 到
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    children = {
                        UI.Label {
                            text = fromName .. " → " .. toName,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_SECONDARY,
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = TransferHub._formatAmount(bid.amount or 0),
                            fontSize = 11,
                            color = Theme.COLORS.SECONDARY,
                        },
                    }
                },
            }
        })
    end

    return {
        Theme.Card {
            children = {
                Theme.Subtitle { text = "活跃谈判 (" .. #activeBids .. ")" },
                UI.Panel { width = "100%", children = rows },
            }
        },
    }
end

---------------------------------------------------------------------------
-- 通用组件
---------------------------------------------------------------------------
function TransferHub._transferRow(t, gameState)
    local typeLabel = "转会"
    local typeColor = Theme.COLORS.PRIMARY
    if t.type == "loan" then
        typeLabel = "租借"
        typeColor = Theme.COLORS.ACCENT
    elseif t.type == "free" then
        typeLabel = "免签"
        typeColor = Theme.COLORS.SECONDARY
    end

    local amountText = (t.amount and t.amount > 0) and TransferHub._formatAmount(t.amount) or "免费"

    return UI.Panel {
        width = "100%",
        paddingTop = 6,
        paddingBottom = 6,
        paddingLeft = 6,
        paddingRight = 6,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = typeLabel,
                        fontSize = 10,
                        color = typeColor,
                        width = 36,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = t.playerName or "?",
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = amountText,
                        fontSize = 12,
                        color = (t.amount and t.amount > 0) and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_MUTED,
                        fontWeight = "bold",
                    },
                }
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                marginTop = 2,
                children = {
                    UI.Label {
                        text = (t.fromTeamName or "?") .. " → " .. (t.toTeamName or "?"),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                        flexGrow = 1,
                    },
                    UI.Label {
                        text = t.date and string.format("S%d", t.season or 1) or "",
                        fontSize = 10,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
        }
    }
end

function TransferHub._topDealRow(t, rank, gameState)
    local medalColor = Theme.COLORS.TEXT_MUTED
    if rank == 1 then medalColor = {255, 215, 0, 255}
    elseif rank == 2 then medalColor = {192, 192, 192, 255}
    elseif rank == 3 then medalColor = {205, 127, 50, 255}
    end

    return UI.Panel {
        width = "100%",
        height = 48,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 6,
        paddingRight = 8,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label {
                text = "#" .. tostring(rank),
                fontSize = 12,
                color = medalColor,
                width = 30,
                fontWeight = "bold",
            },
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = t.playerName or "?",
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                    },
                    UI.Label {
                        text = (t.fromTeamName or "?") .. " → " .. (t.toTeamName or "?"),
                        fontSize = 11,
                        color = Theme.COLORS.TEXT_MUTED,
                    },
                }
            },
            UI.Label {
                text = TransferHub._formatAmount(t.amount or 0),
                fontSize = 13,
                color = Theme.COLORS.SECONDARY,
                fontWeight = "bold",
            },
        }
    }
end

function TransferHub._formatAmount(amount)
    if amount >= 1000000 then
        return string.format("%.1fM", amount / 1000000)
    elseif amount >= 1000 then
        return string.format("%dK", math.floor(amount / 1000))
    else
        return tostring(amount)
    end
end

return TransferHub
