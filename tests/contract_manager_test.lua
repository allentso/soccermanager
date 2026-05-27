-- tests/contract_manager_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local ContractManager = require("scripts/systems/contract_manager")

SetTestRandomSeed(500)

local gameState, home, player = Fixtures.expiringContractState()
gameState.date = { year = 2024, month = 5, day = 1 }

ContractManager.processDaily(gameState)
assert(player._contractWarned6 == true, "six-month contract warning should be marked")
assert(#gameState.inbox == 1, "contract warning should create inbox message")

local ok = ContractManager.renewContract(gameState, player.id, player.wage * 2, 3)
assert(ok == true, "generous renewal should be accepted with fixed seed")
assert(player.contractEnd.year == 2027 and player.contractEnd.month == 5, "renewal should update contract end")

player.contractEnd = { year = 2024, month = 5 }
local beforeCount = #home.playerIds
ContractManager.processSeasonEnd(gameState)
assert(#home.playerIds == beforeCount - 1, "expired player should be released")
assert(player.teamId == nil, "released player should become free agent")

return true
