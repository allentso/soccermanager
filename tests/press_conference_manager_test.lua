-- tests/press_conference_manager_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local MatchEngine = require("scripts/match/match_engine")
local PressConferenceManager = require("scripts/systems/press_conference_manager")

SetTestRandomSeed(700)

local gameState, home, _, fixture = Fixtures.twoTeams()
local player = gameState.players[home.playerIds[1]]
local oldMorale = player.morale
local oldReputation = home.reputation

local report = MatchEngine.simulate(gameState, fixture)
local ok = PressConferenceManager.applyResponse(gameState, report, "balanced")

assert(ok == true, "press conference response should apply")
assert(player.morale >= oldMorale, "balanced response should not reduce morale")
assert(home.reputation > oldReputation, "press conference should affect reputation")
assert(report._pressConferenceDone == true, "report should record conference completion")
assert(#gameState.inbox > 0, "press conference should create inbox feedback")

return true
