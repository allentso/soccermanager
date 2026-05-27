-- tests/fixtures/minimal_game_state.lua

local GameState = require("scripts/core/game_state")
local League = require("scripts/domain/league")

local Fixture = {}

local function attributes(value)
    return {
        speed = value,
        stamina = value,
        strength = value,
        agility = value,
        passing = value,
        shooting = value,
        tackling = value,
        dribbling = value,
        defending = value,
        positioning = value,
        vision = value,
        decisions = value,
        composure = value,
        aggression = 10,
        teamwork = value,
        leadership = value,
        handling = value,
        reflexes = value,
        aerial = value,
    }
end

local function addPlayer(gameState, team, position, ability, suffix)
    local player = gameState:addPlayer({
        firstName = position,
        lastName = suffix,
        displayName = position .. " " .. suffix,
        birthYear = 1998,
        nationality = "ENG",
        position = position,
        attributes = attributes(ability),
        fitness = 88,
        morale = 70,
        wage = 1000,
        teamId = team.id,
    })
    team:addPlayer(player.id)
    return player
end

local function populateTeam(gameState, team, ability, suffix)
    local positions = { "GK", "LB", "CB", "CB", "RB", "CM", "CM", "LM", "RM", "ST", "ST" }
    for _, position in ipairs(positions) do
        local player = addPlayer(gameState, team, position, ability, suffix)
        table.insert(team.startingXI, player.id)
    end
end

function Fixture.twoTeams()
    local gameState = GameState.new()
    gameState.date = { year = 2024, month = 8, day = 10 }
    gameState.season = 2024

    local home = gameState:addTeam({
        name = "Strong FC",
        shortName = "SFC",
        formation = "4-4-2",
        playStyle = "Attacking",
        balance = 1000000,
        wageBudget = 20000,
        stadiumCapacity = 30000,
    })
    local away = gameState:addTeam({
        name = "Weak FC",
        shortName = "WFC",
        formation = "4-5-1",
        playStyle = "Defensive",
        balance = 500000,
        wageBudget = 20000,
        stadiumCapacity = 20000,
    })

    populateTeam(gameState, home, 17, "Home")
    populateTeam(gameState, away, 10, "Away")

    gameState.playerTeamId = home.id

    local league = League.new({
        id = 1,
        name = "Test League",
        teamIds = { home.id, away.id },
        fixtures = {},
    })
    league:initStandings()
    gameState.league = league
    gameState.leagues = { test = league }

    local fixture = {
        id = 1,
        homeTeamId = home.id,
        awayTeamId = away.id,
        date = { year = 2024, month = 8, day = 10 },
        status = "scheduled",
        homeGoals = 0,
        awayGoals = 0,
        events = {},
    }
    table.insert(league.fixtures, fixture)

    return gameState, home, away, fixture
end

function Fixture.expiringContractState()
    local gameState, home, _, _ = Fixture.twoTeams()
    local player = gameState.players[home.playerIds[1]]
    player.contractEnd = { year = 2024, month = 11 }
    return gameState, home, player
end

return Fixture
