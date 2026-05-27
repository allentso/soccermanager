-- tests/run.lua

require("tests/bootstrap")

local tests = {
    "tests/tactics_resolver_test",
    "tests/match_report_test",
    "tests/match_engine_test",
    "tests/finance_manager_test",
    "tests/contract_manager_test",
    "tests/transfer_manager_test",
    "tests/press_conference_manager_test",
}

local failed = 0

for _, moduleName in ipairs(tests) do
    io.write("Running " .. moduleName .. "... ")
    local ok, err = pcall(require, moduleName)
    if ok then
        print("OK")
    else
        failed = failed + 1
        print("FAILED")
        print(err)
    end
end

if failed > 0 then
    error(string.format("%d test file(s) failed", failed))
end

print("All tests passed")
