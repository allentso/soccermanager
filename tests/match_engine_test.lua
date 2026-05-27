-- tests/match_engine_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local MatchEngine = require("scripts/match/match_engine")

SetTestRandomSeed(300)

local gameState, home, away, fixture = Fixtures.twoTeams()
local report = MatchEngine.simulate(gameState, fixture)

assert(report ~= nil, "match engine should produce a report")
assert(report.homeGoals >= 0 and report.awayGoals >= 0, "goals should be non-negative")
assert(report.stats.homeShots >= report.homeGoals, "home shots should cover goals")
assert(report.stats.awayShots >= report.awayGoals, "away shots should cover goals")
assert(report.stats.homePossession + report.stats.awayPossession == 100, "possession should sum to 100")
assert(next(report.playerRatings) ~= nil, "ratings should be generated")

local beforeFitness = gameState.players[home.playerIds[1]].fitness
MatchEngine.applyResult(gameState, fixture, report)
assert(fixture.status == "finished", "applyResult should finish fixture")
assert(gameState.league.standings[home.id].played == 1, "league standing should update")
assert(gameState.players[home.playerIds[1]].fitness < beforeFitness, "players should spend fitness")

SetTestRandomSeed(301)
local knockoutState, _, _, knockoutFixture = Fixtures.twoTeams()
knockoutFixture.isKnockout = true
local knockoutReport = MatchEngine.simulate(knockoutState, knockoutFixture)
assert(knockoutReport.events ~= nil, "knockout report should include events")
if knockoutReport.homeGoals == knockoutReport.awayGoals then
    assert(knockoutReport.extraTime and knockoutReport.extraTime.played, "drawn knockout match should play extra time")
end

return true
