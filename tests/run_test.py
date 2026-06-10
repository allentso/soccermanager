#!/usr/bin/env python3
"""Run Lua tests using lupa with proper path setup and engine mocks."""
import sys
import os

os.chdir('/workspace')

from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

# Setup package.path to find all project modules
lua.execute('''
package.path = "./?.lua;./?/init.lua;" .. package.path
''')

# Setup engine global mocks (RandomInt, Random, log, cache, etc.)
lua.execute('''
local seed = 42

local function nextRandom()
    seed = (1103515245 * seed + 12345) % 2147483648
    return seed / 2147483648
end

function SetTestRandomSeed(value)
    seed = value or 12345
end

function Random(minVal, maxVal)
    if minVal == nil then
        return nextRandom()
    elseif maxVal == nil then
        return nextRandom() * minVal
    else
        return minVal + nextRandom() * (maxVal - minVal)
    end
end

function RandomInt(minValue, maxValue)
    if maxValue == nil then
        maxValue = minValue
        minValue = 1
    end
    local r = nextRandom()
    return minValue + math.floor(r * (maxValue - minValue + 1))
end

-- Mock engine globals
log = { Write = function() end }
cache = { GetFile = function() return nil end, GetResource = function() return nil end }
input = { mouseMode = 0 }
renderer = { SetViewport = function() end }
graphics = {
    GetWidth = function() return 1920 end,
    GetHeight = function() return 1080 end,
    GetDPR = function() return 1.0 end,
}
ui = { root = { AddChild = function() end, RemoveChild = function() end } }

-- Mock SubscribeToEvent / UnsubscribeFromEvent
function SubscribeToEvent(...) end
function UnsubscribeFromEvent(...) end

-- Mock for require calls that might reference UI/rendering (not needed for simulation)
package.preload["urhox-libs/UI"] = function()
    return {
        Init = function() end,
        SetRoot = function() end,
        Panel = function() return {} end,
        Label = function() return {} end,
        Button = function() return {} end,
    }
end

-- File/FileSystem mock
FILE_READ = 1
FILE_WRITE = 2
FILE_READWRITE = 3

fileSystem = {
    FileExists = function(self, path) return false end,
    DirExists = function(self, path) return false end,
    CreateDir = function(self, path) return true end,
    GetProgramDir = function(self) return "/workspace/" end,
}

local FileMT = {}
FileMT.__index = FileMT
function FileMT:IsOpen() return false end
function FileMT:ReadString() return "" end
function FileMT:WriteString(s) end
function FileMT:Close() end

File = setmetatable({}, {
    __call = function(cls, path, mode)
        return setmetatable({}, FileMT)
    end,
})

-- SaveManager mock (avoid actual save operations)
package.preload["scripts/persistence/save_manager"] = function()
    return {
        save = function() end,
        load = function() return nil end,
        autoSave = function() end,
    }
end

-- Router/Navigation mock
package.preload["scripts/app/router"] = function()
    return {
        navigate = function() end,
        replaceWith = function() end,
        back = function() end,
        getCurrentScreen = function() return "dashboard" end,
    }
end
''')

# Now run the test
script_path = sys.argv[1] if len(sys.argv) > 1 else 'tests/five_season_simulation_test.lua'

with open(script_path) as f:
    code = f.read()

try:
    lua.execute(code)
    print("\n\nTest completed successfully!")
except Exception as e:
    print(f"\n\nTest FAILED with error:\n{e}", file=sys.stderr)
    sys.exit(1)
