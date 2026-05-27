-- tests/match_report_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local TacticsResolver = require("scripts/match/tactics_resolver")
local MatchReport = require("scripts/match/match_report")

SetTestRandomSeed(200)

local gameState, home, away, fixture = Fixtures.twoTeams()
local homeContext = TacticsResolver.buildTeamContext(gameState, home)
local awayContext = TacticsResolver.buildTeamContext(gameState, away)
local scorer = homeContext.players[10]
local assister = homeContext.players[6]
local defender = awayContext.players[2]

local report = MatchReport.build(fixture, homeContext, awayContext, {
    { type = "yellow_card", minute = 44, playerId = defender.id, teamId = away.id },
    { type = "goal", minute = 12, playerId = scorer.id, assistPlayerId = assister.id, teamId = home.id },
}, {
    homeGoals = 1,
    awayGoals = 0,
    homeShots = 9,
    awayShots = 4,
    homeShotsOnTarget = 4,
    awayShotsOnTarget = 1,
    homePossession = 0.58,
    homeFouls = 8,
    awayFouls = 11,
})

assert(report.homeGoals == 1 and report.awayGoals == 0, "score should match sim state")
assert(report.events[1].minute == 12, "events should be sorted by minute")
assert(report.stats.homePossession == 58, "possession should be converted to percent")
assert(report.stats.homeShotsOnTarget <= report.stats.homeShots, "shots on target should not exceed shots")
assert(report.playerRatings[scorer.id] >= 7.0, "scorer rating should be boosted")

local motmId, motmRating = MatchReport.findMOTM(report)
assert(motmId ~= nil and motmRating >= 4.0, "MOTM should be available")

return true
