-- data/legend_tag_pools.lua
-- 传奇球员叙事标签分池，供青训抽卡选池使用

local JsonLoader = require("scripts/data/json_loader")
local LegendsLoader = require("scripts/data/legends_loader")

local LegendTagPools = {}

local TAG_POOL_FILE = "Data/legend_tag_pools.json"
local DEFAULT_POOL_ID = "prince"

local _pools = nil       -- poolId -> { id, name_cn, desc, playerIds, players }
local _poolOrder = nil   -- ordered pool ids
local _playerById = nil

local function loadTagPoolJson()
    local data = JsonLoader.loadFromResource(TAG_POOL_FILE)
    if data then return data end
    local f = io.open("assets/" .. TAG_POOL_FILE, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return JsonLoader.decode(content)
end

local function ensureLoaded()
    if _pools then return end

    local data = loadTagPoolJson()
    if not data or not data.pools then
        error("legend_tag_pools.json missing or invalid")
    end

    _playerById = {}
    for _, p in ipairs(LegendsLoader.loadAllPlayers()) do
        if p.id then
            _playerById[p.id] = p
        end
    end

    _pools = {}
    _poolOrder = {}
    for _, pool in ipairs(data.pools) do
        local id = pool.id
        if not id then
            error("legend tag pool missing id")
        end
        table.insert(_poolOrder, id)

        local playerIds = {}
        local players = {}
        for _, entry in ipairs(pool.players or {}) do
            local pid = entry.id or entry
            table.insert(playerIds, pid)
            local full = _playerById[pid]
            if full then
                full = {}
                for k, v in pairs(_playerById[pid]) do
                    full[k] = v
                end
                full.legendTag = id
                table.insert(players, full)
            end
        end

        _pools[id] = {
            id = id,
            name_cn = pool.name_cn or id,
            desc = pool.desc or "",
            playerIds = playerIds,
            players = players,
        }
    end
end

---@return string
function LegendTagPools.getDefaultPoolId()
    ensureLoaded()
    return _poolOrder[1] or DEFAULT_POOL_ID
end

---@return table[] pools meta { id, name_cn, desc, size }
function LegendTagPools.getAllPools()
    ensureLoaded()
    local out = {}
    for _, id in ipairs(_poolOrder) do
        local p = _pools[id]
        table.insert(out, {
            id = p.id,
            name_cn = p.name_cn,
            desc = p.desc,
            size = #p.players,
        })
    end
    return out
end

---@param poolId string
---@return table|nil
function LegendTagPools.getPool(poolId)
    ensureLoaded()
    return _pools[poolId]
end

---@param poolId string
---@return boolean
function LegendTagPools.isValidPoolId(poolId)
    ensureLoaded()
    return _pools[poolId] ~= nil
end

---@param poolId string
---@return table[] full legend player data for pool
function LegendTagPools.getPoolPlayers(poolId)
    ensureLoaded()
    local pool = _pools[poolId]
    if not pool then return {} end
    return pool.players
end

---@param legendId string
---@return string|nil poolId
function LegendTagPools.getPoolIdForLegend(legendId)
    ensureLoaded()
    for _, id in ipairs(_poolOrder) do
        for _, pid in ipairs(_pools[id].playerIds) do
            if pid == legendId then
                return id
            end
        end
    end
    return nil
end

return LegendTagPools
