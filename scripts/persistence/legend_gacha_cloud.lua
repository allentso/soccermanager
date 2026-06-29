-- persistence/legend_gacha_cloud.lua
-- 传奇抽卡账号级云存档灰度模块
-- 仅由开发者作弊入口开启；默认不影响现有本地存档逻辑。

local LegendTagPools = require("scripts/data/legend_tag_pools")

local LegendGachaCloud = {}

local CACHE_PATH = "Saves/legend_gacha_cloud_cache.json"
local CLOUD_KEY = "legend_gacha_global_v1"
local CACHE_VERSION = 1

local cache_ = nil
local syncInFlight_ = false
local bootstrapped_ = false

local function nowSeconds()
    return math.floor(os.time and os.time() or os.clock())
end

local function logInfo(message)
    if log then log:Write(LOG_INFO, "LegendGachaCloud: " .. tostring(message)) end
end

local function logWarn(message)
    if log then log:Write(LOG_WARNING, "LegendGachaCloud: " .. tostring(message)) end
end

local function readAllString(file)
    local parts = {}
    local guard = 0
    while guard < 100000 do
        guard = guard + 1
        local okEof, eof = pcall(function() return file:IsEof() end)
        if okEof and eof then break end
        local okRead, s = pcall(function() return file:ReadString() end)
        if not okRead or s == nil then break end
        parts[#parts + 1] = s
        if not okEof and s == "" then break end
    end
    return table.concat(parts)
end

local function copyArray(src)
    local out = {}
    if type(src) == "table" then
        for _, v in ipairs(src) do
            out[#out + 1] = v
        end
    end
    return out
end

local function containsId(set, id)
    return id ~= nil and set[id] == true
end

local function removeIdFromArray(arr, removeSet)
    if type(arr) ~= "table" then return 0 end
    local removed = 0
    for i = #arr, 1, -1 do
        if containsId(removeSet, arr[i]) then
            table.remove(arr, i)
            removed = removed + 1
        end
    end
    return removed
end

local function clearIdFromSlotTable(t, removeSet)
    if type(t) ~= "table" then return 0 end
    local removed = 0
    for k, v in pairs(t) do
        if containsId(removeSet, v) then
            t[k] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function cleanState()
    return {
        version = CACHE_VERSION,
        unlocked = false,
        adsWatched = 0,
        pulls = 0,
        tenPullCount = 0,
        pityCounter = 0,
        firstTenPull = true,
        singlePullCounter = 0,
        pullAdProgress = 0,
        selectedPoolId = LegendTagPools.getDefaultPoolId(),
        pulledLegendIds = {},
        pulledLegends = {},
        compensationClaimedRound = nil,
        updatedAt = nowSeconds(),
    }
end

local function normalizeState(state)
    if type(state) ~= "table" then state = cleanState() end
    if state.version == nil then state.version = CACHE_VERSION end
    if state.adsWatched == nil then state.adsWatched = 0 end
    if state.unlocked == nil then state.unlocked = false end
    if state.pulls == nil then state.pulls = 0 end
    if state.tenPullCount == nil then state.tenPullCount = 0 end
    if state.pityCounter == nil then state.pityCounter = 0 end
    if state.firstTenPull == nil then state.firstTenPull = true end
    if state.singlePullCounter == nil then state.singlePullCounter = 0 end
    if state.pullAdProgress == nil then state.pullAdProgress = 0 end
    if not state.selectedPoolId or not LegendTagPools.isValidPoolId(state.selectedPoolId) then
        state.selectedPoolId = LegendTagPools.getDefaultPoolId()
    end
    state.pulledLegendIds = copyArray(state.pulledLegendIds)
    state.pulledLegends = copyArray(state.pulledLegends)
    return state
end

local function newCache(enabled)
    return {
        version = CACHE_VERSION,
        enabled = enabled == true,
        dirty = false,
        lastSyncAt = 0,
        state = cleanState(),
    }
end

local function normalizeCache(raw)
    if type(raw) ~= "table" then raw = newCache(false) end
    raw.version = raw.version or CACHE_VERSION
    raw.enabled = raw.enabled == true
    raw.dirty = raw.dirty == true
    raw.lastSyncAt = raw.lastSyncAt or 0
    raw.state = normalizeState(raw.state)
    return raw
end

local function ensureLoaded()
    if cache_ then return cache_ end
    if fileSystem and fileSystem:FileExists(CACHE_PATH) then
        local f = File(CACHE_PATH, FILE_READ)
        if f and f:IsOpen() then
            local content = readAllString(f)
            f:Close()
            if content and content ~= "" then
                local ok, data = pcall(cjson.decode, content)
                if ok and type(data) == "table" then
                    cache_ = normalizeCache(data)
                    return cache_
                end
                logWarn("读取本地缓存失败，使用默认缓存")
            end
        end
    end
    cache_ = newCache(false)
    return cache_
end

function LegendGachaCloud.getCloudKey()
    return CLOUD_KEY
end

function LegendGachaCloud.isEnabled()
    return ensureLoaded().enabled == true
end

function LegendGachaCloud.saveLocal()
    local cache = ensureLoaded()
    if fileSystem then fileSystem:CreateDir("Saves") end
    local ok, json = pcall(cjson.encode, cache)
    if not ok or not json then
        logWarn("编码本地缓存失败: " .. tostring(json))
        return false, tostring(json)
    end
    local f = File(CACHE_PATH, FILE_WRITE)
    if not f or not f:IsOpen() then
        return false, "无法打开本地缓存文件"
    end
    local okWrite, err = pcall(function() f:WriteString(json) end)
    f:Close()
    if not okWrite then
        return false, tostring(err)
    end
    return true
end

local function canUseClientCloud()
    return type(clientCloud) == "userdata" or type(clientCloud) == "table"
end

function LegendGachaCloud.syncToCloud(events)
    local cache = ensureLoaded()
    if not cache.enabled then return false, "disabled" end
    if not canUseClientCloud() then
        cache.dirty = true
        LegendGachaCloud.saveLocal()
        return false, "clientCloud unavailable"
    end
    if syncInFlight_ then return false, "sync in flight" end

    syncInFlight_ = true
    local payload = normalizeState(cache.state)
    payload.updatedAt = nowSeconds()
    cache.state = payload

    clientCloud:Set(CLOUD_KEY, payload, {
        ok = function()
            syncInFlight_ = false
            cache.dirty = false
            cache.lastSyncAt = nowSeconds()
            LegendGachaCloud.saveLocal()
            logInfo("云端写入成功")
            if events and events.ok then events.ok() end
        end,
        error = function(code, reason)
            syncInFlight_ = false
            cache.dirty = true
            LegendGachaCloud.saveLocal()
            logWarn("云端写入失败: " .. tostring(code) .. " " .. tostring(reason))
            if events and events.error then events.error(code, reason) end
        end,
        timeout = function()
            syncInFlight_ = false
            cache.dirty = true
            LegendGachaCloud.saveLocal()
            logWarn("云端写入超时")
            if events and events.timeout then events.timeout() end
        end,
    })
    return true
end

function LegendGachaCloud.syncFromCloud(events)
    local cache = ensureLoaded()
    if not cache.enabled then return false, "disabled" end
    if cache.dirty then
        return LegendGachaCloud.syncToCloud(events)
    end
    if not canUseClientCloud() then
        return false, "clientCloud unavailable"
    end
    if syncInFlight_ then return false, "sync in flight" end

    syncInFlight_ = true
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            syncInFlight_ = false
            local remote = values and values[CLOUD_KEY]
            if type(remote) == "table" then
                cache.state = normalizeState(remote)
                cache.dirty = false
                cache.lastSyncAt = nowSeconds()
                LegendGachaCloud.saveLocal()
                logInfo("云端读取成功")
            else
                cache.dirty = true
                LegendGachaCloud.saveLocal()
                LegendGachaCloud.syncToCloud()
            end
            if events and events.ok then events.ok(cache.state) end
        end,
        error = function(code, reason)
            syncInFlight_ = false
            logWarn("云端读取失败: " .. tostring(code) .. " " .. tostring(reason))
            if events and events.error then events.error(code, reason) end
        end,
        timeout = function()
            syncInFlight_ = false
            logWarn("云端读取超时")
            if events and events.timeout then events.timeout() end
        end,
    })
    return true
end

function LegendGachaCloud.bootstrap()
    local cache = ensureLoaded()
    if not cache.enabled then return false, "disabled" end
    bootstrapped_ = true
    if cache.dirty then
        return LegendGachaCloud.syncToCloud()
    end
    return LegendGachaCloud.syncFromCloud()
end

function LegendGachaCloud.tryGetState()
    local cache = ensureLoaded()
    if not cache.enabled then return nil end
    cache.state = normalizeState(cache.state)
    if not bootstrapped_ then
        LegendGachaCloud.bootstrap()
    end
    return cache.state
end

function LegendGachaCloud.markDirty()
    local cache = ensureLoaded()
    if not cache.enabled then return false end
    cache.state = normalizeState(cache.state)
    cache.state.updatedAt = nowSeconds()
    cache.dirty = true
    LegendGachaCloud.saveLocal()
    LegendGachaCloud.syncToCloud()
    return true
end

function LegendGachaCloud.disableForDeveloper()
    local cache = ensureLoaded()
    cache.enabled = false
    cache.dirty = false
    return LegendGachaCloud.saveLocal()
end

local function purgeLegendCandidates(gameState)
    local removed = 0
    if type(gameState._youthCandidates) == "table" then
        for i = #gameState._youthCandidates, 1, -1 do
            local c = gameState._youthCandidates[i]
            if type(c) == "table" and c.isLegend then
                table.remove(gameState._youthCandidates, i)
                removed = removed + 1
            end
        end
    end
    return removed
end

local function purgeLooseReferences(gameState, removeSet)
    if type(gameState.shortlist) == "table" then
        for id in pairs(removeSet) do
            gameState.shortlist[id] = nil
            gameState.shortlist[tostring(id)] = nil
        end
    end

    local removed = 0
    removed = removed + removeIdFromArray(gameState.scoutDiscoveries, removeSet)
    removed = removed + removeIdFromArray(gameState.scoutReports, removeSet)
    return removed
end

local function purgeTransfers(gameState, removeSet)
    local transfers = gameState.transfers
    if type(transfers) ~= "table" then return 0 end
    local removed = 0
    removed = removed + removeIdFromArray(transfers.history, removeSet)
    removed = removed + removeIdFromArray(transfers.bids, removeSet)
    removed = removed + removeIdFromArray(transfers.closedBids, removeSet)
    return removed
end

local function purgeFromAllTeams(gameState, removeSet)
    local TransferManager = require("scripts/systems/transfer_manager")
    local removedRefs = 0
    for _, team in pairs(gameState.teams or {}) do
        for id in pairs(removeSet) do
            TransferManager._removePlayerFromTeam(team, id)
        end
        if team.playerIds then removedRefs = removedRefs + removeIdFromArray(team.playerIds, removeSet) end
        if team.benchIds then removedRefs = removedRefs + removeIdFromArray(team.benchIds, removeSet) end
        if team._youthPlayerIds then removedRefs = removedRefs + removeIdFromArray(team._youthPlayerIds, removeSet) end
        removedRefs = removedRefs + clearIdFromSlotTable(team.startingXI, removeSet)
    end
    return removedRefs
end

function LegendGachaCloud.purgeLegendEntitiesForDeveloperTest(gameState)
    if not gameState then return { players = 0, candidates = 0, refs = 0 } end

    local removeSet = {}
    local playerCount = 0
    for id, player in pairs(gameState.players or {}) do
        if type(player) == "table" and player.isLegend then
            removeSet[id] = true
            removeSet[player.id] = true
            removeSet[tostring(id)] = true
            if player.id then removeSet[tostring(player.id)] = true end
            playerCount = playerCount + 1
        end
    end

    local refs = 0
    refs = refs + purgeFromAllTeams(gameState, removeSet)
    refs = refs + purgeLooseReferences(gameState, removeSet)
    refs = refs + purgeTransfers(gameState, removeSet)

    for id, shouldRemove in pairs(removeSet) do
        if shouldRemove then
            gameState.players[id] = nil
            local numId = tonumber(id)
            if numId then gameState.players[numId] = nil end
        end
    end

    local candidateCount = purgeLegendCandidates(gameState)
    return { players = playerCount, candidates = candidateCount, refs = refs }
end

function LegendGachaCloud.enableAndResetForDeveloper(gameState, events)
    local cache = ensureLoaded()
    cache.enabled = true
    cache.dirty = true
    cache.lastSyncAt = 0
    cache.state = cleanState()
    if gameState then
        gameState._legendGacha = nil
    end
    LegendGachaCloud.saveLocal()
    return LegendGachaCloud.syncToCloud(events)
end

function LegendGachaCloud.getDebugSummary()
    local cache = ensureLoaded()
    local state = normalizeState(cache.state)
    return string.format("enabled=%s dirty=%s pulls=%d legends=%d lastSync=%s",
        tostring(cache.enabled), tostring(cache.dirty), tonumber(state.pulls) or 0,
        #(state.pulledLegendIds or {}), tostring(cache.lastSyncAt or 0))
end

return LegendGachaCloud
