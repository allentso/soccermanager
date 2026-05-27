-- ui/screens/press_conference.lua

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local PressConferenceManager = require("scripts/systems/press_conference_manager")

local PressConference = {}

function PressConference.create(params)
    local gameState = _G.gameState
    local report = params and params.report
    if not gameState or not report then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            justifyContent = "center", alignItems = "center",
            children = { UI.Label { text = "无发布会数据", color = Theme.COLORS.TEXT_MUTED } },
        }
    end

    local team = gameState:getPlayerTeam()
    local homeTeam = gameState.teams[report.homeTeamId]
    local awayTeam = gameState.teams[report.awayTeamId]
    local title = string.format("%s %d-%d %s",
        homeTeam and homeTeam.name or "主队", report.homeGoals or 0,
        report.awayGoals or 0, awayTeam and awayTeam.name or "客队")

    local buttons = {}
    for key, response in pairs(PressConferenceManager.RESPONSES) do
        table.insert(buttons, Theme.Card {
            children = {
                UI.Label { text = response.label, fontSize = 16, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                UI.Label { text = response.description, fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
                UI.Label {
                    text = string.format("士气 %+d / 声望 %+d / 董事会 %+d", response.morale, response.reputation, response.board),
                    fontSize = 11,
                    color = Theme.COLORS.ACCENT,
                    marginTop = 6,
                },
                UI.Button {
                    text = "选择回应",
                    width = "100%",
                    height = 36,
                    marginTop = 10,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    borderRadius = 8,
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    onClick = function()
                        PressConferenceManager.applyResponse(gameState, report, key)
                        Router.navigate("dashboard")
                    end,
                },
            }
        })
    end

    return UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            Theme.TopBar {
                children = {
                    UI.Label {
                        text = "赛后新闻发布会",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                }
            },
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = {
                    Theme.Card {
                        children = {
                            Theme.Subtitle { text = title },
                            UI.Label {
                                text = team and ("媒体正在等待 " .. team.name .. " 主帅的赛后回应。") or "媒体正在等待你的回应。",
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_MUTED,
                                marginTop = 6,
                            },
                        }
                    },
                    UI.Panel { width = "100%", children = buttons },
                }
            },
        }
    }
end

return PressConference
