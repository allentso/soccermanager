-- tests/finance_manager_test.lua

local Fixtures = require("tests/fixtures/minimal_game_state")
local FinanceManager = require("scripts/systems/finance_manager")

SetTestRandomSeed(400)

local gameState, home = Fixtures.twoTeams()
local startingBalance = home.balance
local wageTotal = FinanceManager.getWeeklyWageTotal(gameState, home.id)

FinanceManager.processWeeklyWages(gameState)
assert(home.balance == startingBalance - wageTotal, "weekly wages should reduce balance")
assert(#home.transactions > 0, "wage transaction should be recorded")

local afterWages = home.balance
FinanceManager.processMatchDayRevenue(gameState, home.id, true)
assert(home.balance > afterWages, "home match revenue should increase balance")

home.balance = wageTotal * 20
home.wageBudget = wageTotal * 2
local status = FinanceManager.getFinanceHealth(gameState, home.id)
assert(status == "stable", "healthy budget and runway should be stable")

home.balance = wageTotal
status = FinanceManager.getFinanceHealth(gameState, home.id)
assert(status == "critical", "short runway should be critical")

home.balance = 1000000
local oldLevel = FinanceManager.ensureFacilities(home).training
local ok = FinanceManager.upgradeFacility(gameState, "training")
assert(ok == true, "facility upgrade should succeed with enough balance")
assert(FinanceManager.ensureFacilities(home).training == oldLevel + 1, "training facility should level up")
assert(FinanceManager.getFacilityBonuses(home).trainingGain > 1.0, "facility should improve training gain")

return true
