-- systems/press_conference_manager.lua
-- Lightweight post-match press conference effects.

local PressConferenceManager = {}

PressConferenceManager.RESPONSES = {
    praise = {
        label = "表扬球队",
        description = "强调球员执行力和团队精神。",
        morale = 4,
        reputation = 1,
        board = 0,
    },
    balanced = {
        label = "保持冷静",
        description = "认可结果，但提醒球队继续改进。",
        morale = 1,
        reputation = 2,
        board = 1,
    },
    demanding = {
        label = "提出更高要求",
        description = "公开表示球队还可以做得更好。",
        morale = -2,
        reputation = 3,
        board = 2,
    },
}

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function PressConferenceManager.applyResponse(gameState, report, responseKey)
    local response = PressConferenceManager.RESPONSES[responseKey] or PressConferenceManager.RESPONSES.balanced
    local team = gameState:getPlayerTeam()
    if not team or not report then return false, "缺少发布会数据" end

    local isHome = report.homeTeamId == team.id
    local playerGoals = isHome and report.homeGoals or report.awayGoals
    local opponentGoals = isHome and report.awayGoals or report.homeGoals
    local result = playerGoals > opponentGoals and "win" or (playerGoals < opponentGoals and "loss" or "draw")
    local moraleDelta = response.morale

    if result == "loss" and responseKey == "praise" then moraleDelta = moraleDelta - 2 end
    if result == "win" and responseKey == "demanding" then moraleDelta = moraleDelta - 1 end

    for _, pid in ipairs(team.playerIds or {}) do
        local player = gameState.players[pid]
        if player then
            player.morale = clamp((player.morale or 60) + moraleDelta, 0, 100)
        end
    end

    team.reputation = (team.reputation or 500) + response.reputation
    team.boardSatisfaction = clamp((team.boardSatisfaction or 50) + response.board, 0, 100)

    gameState:sendMessage({
        category = "media",
        title = "赛后发布会",
        body = string.format("你选择了「%s」。球队士气 %+d，声望 %+d，董事会满意度 %+d。",
            response.label, moraleDelta, response.reputation, response.board),
        priority = "normal",
    })

    gameState:addNews({
        category = "media",
        title = "赛后发布会: " .. response.label,
        body = response.description,
        relatedTeams = { team.id },
    })

    report._pressConferenceDone = true
    return true
end

return PressConferenceManager
