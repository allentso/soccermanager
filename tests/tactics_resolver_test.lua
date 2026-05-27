-- tests/tactics_resolver_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local TacticsResolver = require("scripts/match/tactics_resolver")

SetTestRandomSeed(100)

local gameState, home, away = Fixtures.twoTeams()
local homeContext = TacticsResolver.buildTeamContext(gameState, home)
local awayContext = TacticsResolver.buildTeamContext(gameState, away)

assert(#homeContext.players == 11, "home context should include starting XI")
assert(homeContext.attack > awayContext.attack, "strong team should have stronger attack")
assert(homeContext.chemistry >= 0.94 and homeContext.chemistry <= 1.08, "chemistry should be clamped")

home.playStyle = "Possession"
local possessionContext = TacticsResolver.buildTeamContext(gameState, home)
home.playStyle = "HighPress"
local highPressContext = TacticsResolver.buildTeamContext(gameState, home)

assert(possessionContext.possession > highPressContext.possession * 0.95, "possession style should support possession")
assert(highPressContext.press > possessionContext.press, "high press should increase press modifier")

local matchup = TacticsResolver.matchupModifiers(homeContext, awayContext, true)
assert(matchup.possessionShare >= 0.28 and matchup.possessionShare <= 0.72, "possession share should be bounded")
assert(matchup.chanceCreation > 1.0, "strong home team should create above-average chances")

return true
