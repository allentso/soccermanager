-- tests/bootstrap.lua

local root = (... and debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]tests[/\\]bootstrap%.lua$")) or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local seed = 12345

local function nextRandom()
    seed = (1103515245 * seed + 12345) % 2147483648
    return seed / 2147483648
end

function SetTestRandomSeed(value)
    seed = value or 12345
end

function Random()
    return nextRandom()
end

function RandomInt(minValue, maxValue)
    if maxValue == nil then
        maxValue = minValue
        minValue = 1
    end
    return minValue + math.floor(Random() * (maxValue - minValue + 1))
end

log = log or { Write = function() end }
cache = cache or { GetFile = function() return nil end }

return {
    root = root,
    setSeed = SetTestRandomSeed,
}
