-- data/legends_loader.lua
-- 统一加载全部传奇球员数据（Top50 + 防守补充 + 综合补充）

local JsonLoader = require("scripts/data/json_loader")

local LegendsLoader = {}

local LEGEND_FILES = {
    "Data/legends_alltime_top50.json",
    "Data/legends_alltime_defenders_30.json",
    "Data/legends_alltime_misc_25.json",
}

--- 从 assets 目录直接读取（cache 不可用时的开发/测试回退）
---@param path string
---@return table|nil
local function loadFromAssets(path)
    local f = io.open("assets/" .. path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return JsonLoader.decode(content)
end

---@param path string
---@return table|nil
local function loadLegendFile(path)
    local data = JsonLoader.loadFromResource(path)
    if data then return data end
    return loadFromAssets(path)
end

--- 加载并合并所有传奇球员列表
---@return table[] players
function LegendsLoader.loadAllPlayers()
    local all = {}
    for _, path in ipairs(LEGEND_FILES) do
        local data = loadLegendFile(path)
        if data and data.players then
            for _, p in ipairs(data.players) do
                table.insert(all, p)
            end
        end
    end
    return all
end

return LegendsLoader
