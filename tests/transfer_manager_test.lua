-- tests/transfer_manager_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local TransferManager = require("scripts/systems/transfer_manager")

SetTestRandomSeed(600)

local gameState, home, away = Fixtures.twoTeams()
local player = gameState.players[away.playerIds[10]]
player.morale = 55
player.releaseClause = math.floor(player.value * 1.05)

local releaseBid = TransferManager.triggerReleaseClause(gameState, player.id)
assert(releaseBid ~= nil and releaseBid.status == "completed", "release clause should complete with player consent")
assert(player.teamId == home.id, "release clause should move player to buyer")

SetTestRandomSeed(601)
gameState, home, away = Fixtures.twoTeams()
player = gameState.players[away.playerIds[10]]
local startingBuyerBalance = home.balance
local startingSellerBalance = away.balance
local bid = TransferManager.makeBidWithClauses(gameState, player.id, player.value, player.wage, {
    installments = 3,
    appearanceBonus = { count = 20, amount = 50000 },
    sellOnPercent = 15,
})
assert(bid.installments and #bid.installments == 3, "installments should be attached")
assert(bid._effectiveValue > bid.amount, "clauses should increase effective value")

TransferManager._acceptBid(gameState, bid)
assert(bid.status == "completed", "clause bid should complete")
assert(home.balance > startingBuyerBalance - bid.amount, "buyer should only pay first installment immediately")
assert(away.balance < startingSellerBalance + bid.amount, "seller should only receive first installment immediately")
assert(home._pendingPayables and #home._pendingPayables == 2, "remaining installments should be payable")
assert(player._sellOnClause and player._sellOnClause.percent == 15, "sell-on clause should persist on player")

local beforeInstallment = home.balance
gameState.date = { year = bid.installments[2].dueDate.year, month = bid.installments[2].dueDate.month, day = 1 }
TransferManager.processInstallments(gameState)
assert(home.balance < beforeInstallment, "due installment should be paid")
assert(#home._pendingPayables == 1, "paid installment should be removed")

SetTestRandomSeed(602)
gameState, home, away = Fixtures.twoTeams()
local third = gameState:addTeam({
    name = "Rival Buyers",
    shortName = "RIV",
    balance = 1000000,
    transferBudget = 1000000,
    reputation = 600,
})
player = gameState.players[away.playerIds[9]]
TransferManager._ensureData(gameState)
local playerBid = TransferManager.makeBid(gameState, player.id, math.floor(player.value * 0.9), player.wage)
local rivalBid = {
    id = gameState.transfers.nextBidId,
    playerId = player.id,
    buyerTeamId = third.id,
    sellerTeamId = away.id,
    amount = math.floor(player.value * 1.25),
    playerValue = player.value,
    status = "pending",
    date = { year = gameState.date.year, month = gameState.date.month, day = gameState.date.day },
    wageOffer = player.wage,
    currentRound = 0,
    maxRounds = 3,
    mood = 50,
    rounds = {},
}
gameState.transfers.nextBidId = gameState.transfers.nextBidId + 1
table.insert(gameState.transfers.bids, rivalBid)

TransferManager.processCompetitiveBids(gameState)
assert(playerBid.status == "rejected", "lower competing bid should be rejected")
assert(rivalBid.status == "completed", "highest competing bid should complete")
assert(player.teamId == third.id, "player should join highest bidder")

SetTestRandomSeed(603)
gameState, home, away = Fixtures.twoTeams()
player = gameState.players[away.playerIds[8]]
player.listedForLoan = true
player.squadRole = "youth"
local loanBid = TransferManager.makeLoanBid(gameState, player.id, 1)
assert(loanBid ~= nil and loanBid.type == "loan", "loan bid should be created")
TransferManager._processLoanBidResponse(gameState, loanBid)
assert(loanBid.status == "completed", "listed loan player should accept deterministic loan")
assert(player.teamId == home.id and player.squadRole == "loaned", "loan should move player temporarily")
gameState._activeLoans[1].remainingWeeks = 0
TransferManager.processLoanExpiry(gameState)
assert(player.teamId == away.id, "loan expiry should return player")

return true
