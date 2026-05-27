-- ui/screens/player_detail/stats_tab.lua
-- 球员详情的统计标签页。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")

local StatsTab = {}

local function infoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%", height = 34,
        flexDirection = "row", alignItems = "center",
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label { text = label, fontSize = 13, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
            UI.Label { text = value, fontSize = 13, color = valueColor or Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
        }
    }
end

function StatsTab.build(player, gameState)
    local stats = player.seasonStats or {}
    local apps = stats.appearances or 0
    local goalsPerGame = apps > 0 and string.format("%.2f", (stats.goals or 0) / apps) or "0"
    local assistsPerGame = apps > 0 and string.format("%.2f", (stats.assists or 0) / apps) or "0"

    return UI.Panel {
        width = "100%",
        children = {
            Theme.Card {
                children = {
                    Theme.Subtitle { text = "本赛季数据 (" .. tostring(gameState.season) .. ")" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 8,
                        children = {
                            Theme.StatPill { label = "出场", value = stats.appearances or 0 },
                            Theme.StatPill { label = "进球", value = stats.goals or 0,
                                valueColor = (stats.goals or 0) > 0 and Theme.COLORS.SECONDARY or nil },
                            Theme.StatPill { label = "助攻", value = stats.assists or 0,
                                valueColor = (stats.assists or 0) > 0 and Theme.COLORS.ACCENT or nil },
                            Theme.StatPill { label = "黄牌", value = stats.yellowCards or 0,
                                valueColor = (stats.yellowCards or 0) > 0 and Theme.COLORS.WARNING or nil },
                            Theme.StatPill { label = "红牌", value = stats.redCards or 0,
                                valueColor = (stats.redCards or 0) > 0 and Theme.COLORS.DANGER or nil },
                            Theme.StatPill { label = "零封", value = stats.cleanSheets or 0 },
                        }
                    },
                }
            },

            Theme.Card {
                children = {
                    Theme.Subtitle { text = "场均数据" },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", marginTop = 8,
                        children = {
                            Theme.StatPill { label = "场均进球", value = goalsPerGame },
                            Theme.StatPill { label = "场均助攻", value = assistsPerGame },
                            Theme.StatPill { label = "场均评分", value = stats.avgRating and string.format("%.1f", stats.avgRating) or "-" },
                        }
                    },
                }
            },

            Theme.Card {
                children = {
                    Theme.Subtitle { text = "身体状态" },
                    UI.Panel {
                        marginTop = 6,
                        children = {
                            infoRow("当前体能", tostring(player.fitness) .. "%",
                                player.fitness >= 75 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING),
                            infoRow("当前士气", tostring(player.morale),
                                player.morale >= 60 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING),
                            infoRow("受伤状态", player.injured and ("受伤 - " .. (player.injuryDays or 0) .. "天") or "健康",
                                player.injured and Theme.COLORS.DANGER or Theme.COLORS.SECONDARY),
                            infoRow("训练重点", player.trainingFocus or "跟随全队", Theme.COLORS.TEXT_MUTED),
                        }
                    },
                }
            },
        }
    }
end

return StatsTab
