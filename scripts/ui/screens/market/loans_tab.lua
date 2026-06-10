-- ui/screens/market/loans_tab.lua
-- 租借市场标签页，从 market.lua 拆分出来。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local TransferManager = require("scripts/systems/transfer_manager")

local LoansTab = {}

function LoansTab.build(gameState)
    local children = {}

    local loans = TransferManager.getActiveLoans(gameState)
    local myLoansIn = {}
    local myLoansOut = {}
    local teamId = gameState.playerTeamId

    for _, loan in ipairs(loans) do
        if loan.loanTeamId == teamId then
            table.insert(myLoansIn, loan)
        elseif loan.originTeamId == teamId then
            table.insert(myLoansOut, loan)
        end
    end

    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 10,
        children = { UI.Label { text = "租入球员 (" .. tostring(#myLoansIn) .. ")", fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY } }
    })

    if #myLoansIn == 0 then
        table.insert(children, LoansTab._emptyRow("暂无租入球员"))
    else
        for _, loan in ipairs(myLoansIn) do
            local player = gameState.players[loan.playerId]
            local fromTeam = gameState.teams[loan.originTeamId]
            table.insert(children, LoansTab._loanRow(player, "来自 " .. (fromTeam and fromTeam.name or "?") .. " | 剩余 " .. tostring(loan.remainingWeeks or "?") .. " 周", Theme.COLORS.SECONDARY))
        end
    end

    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingTop = 14,
        children = { UI.Label { text = "租出球员 (" .. tostring(#myLoansOut) .. ")", fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY } }
    })

    if #myLoansOut == 0 then
        table.insert(children, LoansTab._emptyRow("暂无租出球员"))
    else
        for _, loan in ipairs(myLoansOut) do
            local player = gameState.players[loan.playerId]
            local toTeam = gameState.teams[loan.loanTeamId]
            table.insert(children, LoansTab._loanRow(player, "租借到 " .. (toTeam and toTeam.name or "?") .. " | 剩余 " .. tostring(loan.remainingWeeks or "?") .. " 周", Theme.COLORS.ACCENT))
        end
    end

    table.insert(children, UI.Panel { width = "100%", height = 16 })
    table.insert(children, UI.Panel {
        width = "100%", paddingLeft = 12, paddingRight = 12, paddingBottom = 6,
        children = {
            UI.Label { text = "发起租借", fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY },
            UI.Label { text = "优先展示被挂牌外租的球员", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 4 },
        }
    })

    local loanCandidates = {}
    for _, player in pairs(gameState.players) do
        if player.teamId and player.teamId ~= teamId and not player.injured and not player.retired and player.listedForLoan then
            table.insert(loanCandidates, player)
        end
    end

    table.sort(loanCandidates, function(a, b) return (a.overall or 0) > (b.overall or 0) end)
    for i = 1, math.min(20, #loanCandidates) do
        local player = loanCandidates[i]
        local sourceTeam = gameState.teams[player.teamId]
        table.insert(children, LoansTab._candidateRow(gameState, player, sourceTeam))
    end

    return children
end

function LoansTab._emptyRow(text)
    return UI.Panel {
        width = "100%", height = 50, alignItems = "center", justifyContent = "center",
        children = { UI.Label { text = text, fontSize = 12, color = Theme.COLORS.TEXT_MUTED } }
    }
end

function LoansTab._loanRow(player, subtitle, ratingColor)
    return UI.Panel {
        width = "100%", height = 52, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label { text = player and (Constants.POSITION_NAMES[player.position] or player.position) or "?", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36 },
            UI.Panel { flexGrow = 1,
                children = {
                    UI.Label { text = player and player.displayName or "?", fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
                    UI.Label { text = subtitle, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                }
            },
            UI.Label { text = tostring(player and math.min(Constants.ABILITY_MAX, player.overall or 0) or "?"), fontSize = 13, color = ratingColor, width = 28, fontWeight = "bold" },
        }
    }
end

function LoansTab._candidateRow(gameState, player, sourceTeam)
    return UI.Panel {
        width = "100%", height = 54, flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        borderBottomWidth = 1, borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Label { text = Constants.POSITION_NAMES[player.position] or player.position, fontSize = 11, color = Theme.COLORS.TEXT_MUTED, width = 36 },
            UI.Panel { flexGrow = 1,
                children = {
                    UI.Label { text = player.displayName, fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY },
                    UI.Label { text = (sourceTeam and sourceTeam.name or "?") .. " | 半赛季租借", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                }
            },
            UI.Label { text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)), fontSize = 13, color = Theme.COLORS.SECONDARY, width = 28, fontWeight = "bold" },
            UI.Button {
                text = "租借", width = 50, height = 26,
                backgroundColor = Theme.COLORS.PRIMARY, borderRadius = 4, fontSize = 11,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    TransferManager.makeLoanBid(gameState, player.id, 26)
                    Router.replaceWith("market", { tab = "loans" })
                end,
            },
        }
    }
end

return LoansTab
