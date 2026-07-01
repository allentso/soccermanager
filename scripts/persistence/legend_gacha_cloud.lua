-- persistence/legend_gacha_cloud.lua
-- 传奇抽卡账号级云存档灰度模块
-- 仅由开发者作弊入口开启；默认不影响现有本地存档逻辑。

local LegendTagPools = require("scripts/data/legend_tag_pools")

local LegendGachaCloud = {}

local CACHE_PATH = "Saves/legend_gacha_cloud_cache.json"
local CLOUD_KEY = "legend_gacha_global_v1"
local CACHE_VERSION = 1
local ENVELOPE_SCHEMA_VERSION = 2

local cache_ = nil
local syncInFlight_ = false
local bootstrapped_ = false
local ready_ = false
local bootstrapping_ = false
local pendingSync_ = false
local syncSeq_ = 0
local inflightSeq_ = nil
local pendingRemoteEnvelope_ = nil

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

--- 将远端/快照状态 in-place 写入目标表，保持引用稳定
local function applyStateInPlace(target, source)
    if type(target) ~= "table" then return target end
    local normalized = normalizeState(source)
    for k in pairs(target) do
        target[k] = nil
    end
    for k, v in pairs(normalized) do
        if type(v) == "table" then
            target[k] = copyArray(v)
        else
            target[k] = v
        end
    end
    return target
end

local function generateLedgerId()
    return string.format("ledger-%d-%d", nowSeconds(), math.random(10000, 99999))
end

local function ensureDeviceId(cache)
    if cache.deviceId and cache.deviceId ~= "" then return cache.deviceId end
    cache.deviceId = string.format("dev-%d-%d", nowSeconds(), math.random(1000, 9999))
    return cache.deviceId
end

--- 解析云端 payload：v2 envelope 或 v1 裸 state
local function parseRemoteEnvelope(remote)
    if type(remote) ~= "table" then return nil end
    if type(remote.state) == "table" then
        return {
            schemaVersion = remote.schemaVersion or ENVELOPE_SCHEMA_VERSION,
            cloudEnabled = remote.cloudEnabled ~= false,
            seedLocked = remote.seedLocked == true,
            ledgerId = remote.ledgerId,
            revision = tonumber(remote.revision) or 0,
            updatedAt = tonumber(remote.updatedAt) or 0,
            lastWriterId = remote.lastWriterId,
            state = normalizeState(remote.state),
        }
    end
    -- v1 裸 state 兼容
    return {
        schemaVersion = 1,
        cloudEnabled = true,
        seedLocked = false,
        ledgerId = remote.ledgerId,
        revision = tonumber(remote.revision) or 0,
        updatedAt = tonumber(remote.updatedAt) or 0,
        lastWriterId = remote.lastWriterId,
        state = normalizeState(remote),
    }
end

local function buildEnvelopeFromCache(cache, nextRevision)
    if not cache.ledgerId or cache.ledgerId == "" then
        cache.ledgerId = generateLedgerId()
    end
    local rev = nextRevision or ((cache.revision or 0) + 1)
    local ts = nowSeconds()
    local env = {
        schemaVersion = ENVELOPE_SCHEMA_VERSION,
        cloudEnabled = true,
        seedLocked = cache.seedFromSaveUsed == true,
        ledgerId = cache.ledgerId,
        revision = rev,
        updatedAt = ts,
        lastWriterId = ensureDeviceId(cache),
        state = {},
    }
    applyStateInPlace(env.state, cache.state)
    env.state.updatedAt = ts
    return env
end

local function applyEnvelopeToCache(cache, envelope)
    if not envelope then return end
    applyStateInPlace(cache.state, envelope.state)
    if envelope.ledgerId and envelope.ledgerId ~= "" then
        cache.ledgerId = envelope.ledgerId
    end
    cache.revision = tonumber(envelope.revision) or cache.revision or 0
    if envelope.seedLocked then
        cache.seedFromSaveUsed = true
    end
end

local function newCache(enabled)
    return {
        version = CACHE_VERSION,
        enabled = enabled == true,
        dirty = false,
        lastSyncAt = 0,
        ledgerId = nil,
        revision = 0,
        baselineRevision = 0,
        deviceId = nil,
        pendingAccountAttach = false,
        pendingConflict = false,
        state = cleanState(),
    }
end

local function normalizeCache(raw)
    if type(raw) ~= "table" then raw = newCache(false) end
    raw.version = raw.version or CACHE_VERSION
    raw.enabled = raw.enabled == true
    raw.dirty = raw.dirty == true
    raw.lastSyncAt = raw.lastSyncAt or 0
    raw.seedFromSaveUsed = raw.seedFromSaveUsed == true
    raw.ledgerId = raw.ledgerId
    raw.revision = tonumber(raw.revision) or 0
    raw.baselineRevision = tonumber(raw.baselineRevision) or raw.revision or 0
    raw.deviceId = raw.deviceId
    raw.pendingAccountAttach = raw.pendingAccountAttach == true
    raw.pendingConflict = raw.pendingConflict == true
    raw.state = normalizeState(raw.state)
    return raw
end

local GACHA_SCALAR_KEYS = {
    "unlocked", "adsWatched", "pulls", "tenPullCount", "pityCounter",
    "firstTenPull", "singlePullCounter", "pullAdProgress", "selectedPoolId",
    "compensationClaimedRound", "compensationClaimed", "compensation300PullClaimed",
    "rulesTapBonusClaimed",
}

local function addUniqueValue(arr, seen, value)
    if value == nil or value == "" or seen[value] then return end
    seen[value] = true
    arr[#arr + 1] = value
end

local function buildStateFromSaveGacha(localGacha)
    local seed = cleanState()
    if type(localGacha) ~= "table" then return seed end
    for _, key in ipairs(GACHA_SCALAR_KEYS) do
        if localGacha[key] ~= nil then seed[key] = localGacha[key] end
    end
    seed.pulledLegendIds = copyArray(localGacha.pulledLegendIds)
    seed.pulledLegends = copyArray(localGacha.pulledLegends)
    return seed
end

local function mergeLegendRosterFromSave(gameState, state)
    if not gameState or type(state) ~= "table" then return end

    local idSeen, nameSeen = {}, {}
    local ids, names = {}, {}

    local function addId(id) addUniqueValue(ids, idSeen, id) end
    local function addName(name) addUniqueValue(names, nameSeen, name) end

    for _, id in ipairs(state.pulledLegendIds or {}) do addId(id) end
    for _, name in ipairs(state.pulledLegends or {}) do addName(name) end

    for _, p in pairs(gameState.players or {}) do
        if type(p) == "table" and p.isLegend then
            if type(p.legendData) == "table" and p.legendData.id then addId(p.legendData.id) end
            if p.legendName then addName(p.legendName) end
        end
    end

    for _, c in ipairs(gameState._youthCandidates or {}) do
        if type(c) == "table" and c.isLegend then
            if type(c.legendData) == "table" and c.legendData.id then addId(c.legendData.id) end
            if c.legendName then addName(c.legendName) end
        end
    end

    state.pulledLegendIds = ids
    state.pulledLegends = names
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

local function canUseClientCloud()
    return type(clientCloud) == "userdata" or type(clientCloud) == "table"
end

local function markReady()
    ready_ = true
    bootstrapping_ = false
end

local function resetBootstrapAfterReadFailure()
    ready_ = false
    bootstrapped_ = false
    bootstrapping_ = false
end

local function scheduleSyncIfNeeded()
    if pendingSync_ and not syncInFlight_ then
        LegendGachaCloud.syncToCloud()
    end
end

local function envelopeStateField(payload)
    if type(payload) ~= "table" then return nil end
    if type(payload.state) == "table" then return payload.state end
    return payload
end

local function handleRemoteEnvelope(cache, envelope, gameState)
    if not envelope then
        cache.dirty = true
        LegendGachaCloud.saveLocal()
        markReady()
        LegendGachaCloud.syncToCloud()
        return
    end

    pendingRemoteEnvelope_ = envelope

    if not cache.enabled then
        cache.pendingAccountAttach = true
        LegendGachaCloud.saveLocal()
        markReady()
        return
    end

    local remoteRev = envelope.revision or 0
    local localRev = cache.revision or 0

    if cache.ledgerId and envelope.ledgerId and cache.ledgerId ~= envelope.ledgerId then
        cache.pendingConflict = true
        LegendGachaCloud.saveLocal()
        markReady()
        return
    end

    if cache.dirty then
        local baseline = cache.baselineRevision or localRev
        if remoteRev ~= baseline then
            cache.pendingConflict = true
            LegendGachaCloud.saveLocal()
            markReady()
            return
        end
        normalizeState(cache.state)
        cache.state.updatedAt = nowSeconds()
        markReady()
        LegendGachaCloud.syncToCloud()
        return
    end

    local shouldApplyRemote = false
    if remoteRev > localRev then
        shouldApplyRemote = true
    elseif remoteRev == localRev then
        local remoteTs = envelope.updatedAt or envelope.state.updatedAt or 0
        local localTs = cache.state.updatedAt or 0
        if remoteTs > localTs then
            shouldApplyRemote = true
        elseif remoteTs == localTs and (envelope.state.pulls or 0) ~= (cache.state.pulls or 0) then
            shouldApplyRemote = true
        end
    end

    if shouldApplyRemote then
        applyEnvelopeToCache(cache, envelope)
        cache.dirty = false
        cache.baselineRevision = cache.revision
        cache.pendingConflict = false
        pendingRemoteEnvelope_ = nil
    else
        cache.pendingConflict = false
        pendingRemoteEnvelope_ = nil
    end

    cache.lastSyncAt = nowSeconds()
    LegendGachaCloud.saveLocal()
    markReady()
    if cache.dirty then
        LegendGachaCloud.syncToCloud()
    end
    if gameState then
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    end
end

function LegendGachaCloud.getCloudKey()
    return CLOUD_KEY
end

function LegendGachaCloud.isEnabled()
    return ensureLoaded().enabled == true
end

function LegendGachaCloud.isReady()
    local cache = ensureLoaded()
    if not cache.enabled then return true end
    return ready_
end

function LegendGachaCloud.hasPendingAccountAttach()
    local cache = ensureLoaded()
    return cache.pendingAccountAttach == true and not cache.enabled
end

function LegendGachaCloud.hasPendingConflict()
    local cache = ensureLoaded()
    return cache.pendingConflict == true
end

---@return table|nil
function LegendGachaCloud.getPendingAccountAttach()
    local cache = ensureLoaded()
    if not cache.pendingAccountAttach or cache.enabled then return nil end
    local env = pendingRemoteEnvelope_
    if not env then return { pending = true } end
    return {
        pending = true,
        ledgerId = env.ledgerId,
        revision = env.revision or 0,
        pulls = env.state.pulls or 0,
        legendCount = #(env.state.pulledLegendIds or {}) + #(env.state.pulledLegends or {}),
        seedLocked = env.seedLocked == true,
    }
end

---@return table|nil
function LegendGachaCloud.getPendingConflict()
    local cache = ensureLoaded()
    if not cache.pendingConflict then return nil end
    local env = pendingRemoteEnvelope_
    local info = {
        pending = true,
        localRevision = cache.baselineRevision or cache.revision or 0,
        remoteRevision = env and env.revision or 0,
        localPulls = cache.state.pulls or 0,
        remotePulls = env and env.state.pulls or 0,
    }
    return info
end

function LegendGachaCloud.canMutate()
    local cache = ensureLoaded()
    if not cache.enabled then return true end
    if cache.pendingConflict then return false end
    if ready_ and not bootstrapping_ then return true end
    -- 云同步未完成时，允许写入本地存档镜像作为离线兜底
    local gs = _G and _G.gameState
    if gs and type(gs._legendGacha) == "table" then return true end
    return false
end

--- 将账本元数据写入存档镜像
function LegendGachaCloud.syncSaveCloudMeta(gameState, cache)
    if not gameState or not cache then return end
    gameState._legendGachaCloudMeta = {
        ledgerId = cache.ledgerId,
        revision = cache.revision or 0,
    }
end

--- 将云/权威状态镜像到当前存档（随 save 持久化，云失效时可恢复）
function LegendGachaCloud.syncMirrorToSave(gameState, sourceState)
    if not gameState or type(sourceState) ~= "table" then return end
    gameState._legendGacha = gameState._legendGacha or {}
    applyStateInPlace(gameState._legendGacha, sourceState)
    local cache = ensureLoaded()
    if cache.enabled then
        LegendGachaCloud.syncSaveCloudMeta(gameState, cache)
    end
end

--- 读取并补全当前存档内的传奇抽卡镜像
function LegendGachaCloud.getSaveMirror(gameState)
    if not gameState then return cleanState() end
    gameState._legendGacha = gameState._legendGacha or {}
    return normalizeState(gameState._legendGacha)
end

function LegendGachaCloud.getStatus()
    local cache = ensureLoaded()
    return {
        enabled = cache.enabled == true,
        ready = ready_,
        bootstrapping = bootstrapping_,
        dirty = cache.dirty == true,
        syncInFlight = syncInFlight_,
        pendingSync = pendingSync_,
        lastSyncAt = cache.lastSyncAt or 0,
        pendingAccountAttach = cache.pendingAccountAttach == true,
        pendingConflict = cache.pendingConflict == true,
        revision = cache.revision or 0,
        ledgerId = cache.ledgerId,
    }
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

function LegendGachaCloud.syncToCloud(events)
    local cache = ensureLoaded()
    if not cache.enabled then return false, "disabled" end
    if cache.pendingConflict then return false, "legend_cloud_conflict" end
    if not canUseClientCloud() then
        cache.dirty = true
        pendingSync_ = true
        LegendGachaCloud.saveLocal()
        return false, "clientCloud unavailable"
    end
    if syncInFlight_ then
        pendingSync_ = true
        return false, "sync in flight"
    end

    syncInFlight_ = true
    pendingSync_ = false
    syncSeq_ = syncSeq_ + 1
    local thisSeq = syncSeq_
    inflightSeq_ = thisSeq

    local nextRev = (cache.revision or 0) + 1
    local payload = buildEnvelopeFromCache(cache, nextRev)

    clientCloud:Set(CLOUD_KEY, payload, {
        ok = function()
            syncInFlight_ = false
            if inflightSeq_ == thisSeq then
                inflightSeq_ = nil
                if syncSeq_ == thisSeq then
                    cache.dirty = false
                    cache.revision = payload.revision
                    cache.ledgerId = payload.ledgerId
                    cache.baselineRevision = cache.revision
                    applyStateInPlace(cache.state, payload.state)
                end
                cache.lastSyncAt = nowSeconds()
                LegendGachaCloud.saveLocal()
                logInfo("云端写入成功")
            end
            if events and events.ok then events.ok() end
            scheduleSyncIfNeeded()
        end,
        error = function(code, reason)
            syncInFlight_ = false
            if inflightSeq_ == thisSeq then
                inflightSeq_ = nil
            end
            cache.dirty = true
            pendingSync_ = true
            LegendGachaCloud.saveLocal()
            logWarn("云端写入失败: " .. tostring(code) .. " " .. tostring(reason))
            if events and events.error then events.error(code, reason) end
        end,
        timeout = function()
            syncInFlight_ = false
            if inflightSeq_ == thisSeq then
                inflightSeq_ = nil
            end
            cache.dirty = true
            pendingSync_ = true
            LegendGachaCloud.saveLocal()
            logWarn("云端写入超时")
            if events and events.timeout then events.timeout() end
        end,
    })
    return true
end

function LegendGachaCloud.syncFromCloud(events)
    local cache = ensureLoaded()
    if not canUseClientCloud() then
        return false, "clientCloud unavailable"
    end
    if syncInFlight_ then return false, "sync in flight" end

    syncInFlight_ = true
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            syncInFlight_ = false
            local remote = values and values[CLOUD_KEY]
            local envelope = parseRemoteEnvelope(remote)
            local gs = _G and _G.gameState
            if envelope then
                handleRemoteEnvelope(cache, envelope, gs)
            else
                if cache.enabled then
                    cache.dirty = true
                    LegendGachaCloud.saveLocal()
                    markReady()
                    LegendGachaCloud.syncToCloud()
                else
                    markReady()
                end
            end
            if events and events.ok then events.ok(cache.state) end
        end,
        error = function(code, reason)
            syncInFlight_ = false
            if cache.enabled then
                resetBootstrapAfterReadFailure()
            end
            logWarn("云端读取失败: " .. tostring(code) .. " " .. tostring(reason))
            if events and events.error then events.error(code, reason) end
        end,
        timeout = function()
            syncInFlight_ = false
            if cache.enabled then
                resetBootstrapAfterReadFailure()
            end
            logWarn("云端读取超时")
            if events and events.timeout then events.timeout() end
        end,
    })
    return true
end

--- 探测账号级云账本（本地未开启时也可调用）
function LegendGachaCloud.probeAccountLedger(events)
    return LegendGachaCloud.syncFromCloud(events)
end

function LegendGachaCloud.bootstrap()
    local cache = ensureLoaded()
    if not cache.enabled then return false, "disabled" end
    if bootstrapped_ then return true end
    bootstrapped_ = true
    bootstrapping_ = true
    ready_ = false
    local ok, err = LegendGachaCloud.syncFromCloud()
    if not ok then
        resetBootstrapAfterReadFailure()
    end
    return ok, err
end

function LegendGachaCloud.tryGetState()
    local cache = ensureLoaded()
    if not cache.enabled then return nil end
    normalizeState(cache.state)
    if not bootstrapped_ then
        LegendGachaCloud.bootstrap()
    end
    return cache.state
end

function LegendGachaCloud.markDirty(gameState)
    local cache = ensureLoaded()
    if not cache.enabled then return false end
    if cache.pendingConflict then
        return false, "legend_cloud_conflict"
    end
    if not LegendGachaCloud.canMutate() then
        return false, "legend_cloud_syncing"
    end

    gameState = gameState or (_G and _G.gameState)
    local cloudReady = ready_ and not bootstrapping_

    if not cache.dirty then
        cache.baselineRevision = cache.revision or 0
    end

    if cloudReady then
        normalizeState(cache.state)
        cache.state.updatedAt = nowSeconds()
        cache.dirty = true
        if gameState then
            LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
        end
    elseif gameState and gameState._legendGacha then
        applyStateInPlace(cache.state, gameState._legendGacha)
        normalizeState(cache.state)
        cache.state.updatedAt = nowSeconds()
        cache.dirty = true
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    else
        normalizeState(cache.state)
        cache.state.updatedAt = nowSeconds()
        cache.dirty = true
    end

    LegendGachaCloud.saveLocal()
    if not cloudReady then
        return true
    end

    local ok, err = LegendGachaCloud.syncToCloud()
    if not ok then
        pendingSync_ = true
        if err == "sync in flight" then
            syncSeq_ = syncSeq_ + 1
        end
        return false, err
    end
    return true
end

--- 确认接入账号级云账本，用云端覆盖当前存档镜像
function LegendGachaCloud.acceptRemoteAccountLedger(gameState)
    local cache = ensureLoaded()
    local envelope = pendingRemoteEnvelope_
    if not envelope then return false, "no_pending_attach" end

    cache.enabled = true
    cache.pendingAccountAttach = false
    applyEnvelopeToCache(cache, envelope)
    if envelope.seedLocked then
        cache.seedFromSaveUsed = true
    end
    cache.dirty = false
    cache.baselineRevision = cache.revision or 0
    bootstrapped_ = true
    bootstrapping_ = false
    ready_ = true
    pendingRemoteEnvelope_ = nil

    if gameState then
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    end
    cache.lastSyncAt = nowSeconds()
    LegendGachaCloud.saveLocal()
    return true
end

--- 冲突时选择使用云端账本覆盖本地
function LegendGachaCloud.resolveConflictUseCloud(gameState)
    local cache = ensureLoaded()
    local envelope = pendingRemoteEnvelope_
    if not cache.pendingConflict or not envelope then
        return false, "no_conflict"
    end

    applyEnvelopeToCache(cache, envelope)
    cache.dirty = false
    cache.pendingConflict = false
    cache.baselineRevision = cache.revision or 0
    pendingRemoteEnvelope_ = nil

    if gameState then
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    end
    cache.lastSyncAt = nowSeconds()
    LegendGachaCloud.saveLocal()
    return true
end

function LegendGachaCloud.disableForDeveloper()
    local cache = ensureLoaded()
    cache.enabled = false
    cache.dirty = false
    cache.pendingAccountAttach = false
    cache.pendingConflict = false
    ready_ = false
    bootstrapped_ = false
    bootstrapping_ = false
    pendingSync_ = false
    pendingRemoteEnvelope_ = nil
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

--- 是否仍可使用「复制当前存档名单上云」的一次性入口
---@return boolean ok
---@return string|nil reason already_used|already_enabled|cloud_ledger_exists|cloud_seed_locked
function LegendGachaCloud.canSeedFromCurrentSave()
    local cache = ensureLoaded()
    if cache.seedFromSaveUsed then return false, "already_used" end
    if cache.enabled then return false, "already_enabled" end
    if cache.pendingAccountAttach then return false, "cloud_ledger_exists" end
    if pendingRemoteEnvelope_ and pendingRemoteEnvelope_.seedLocked then
        return false, "cloud_seed_locked"
    end
    return true
end

--- 开启云存档，并将当前存档的传奇抽卡状态与名单复制上云（一次性）
function LegendGachaCloud.enableAndSeedFromCurrentSave(gameState, events)
    local canSeed, reason = LegendGachaCloud.canSeedFromCurrentSave()
    if not canSeed then return false, reason end

    local seedState = buildStateFromSaveGacha(gameState and gameState._legendGacha)
    mergeLegendRosterFromSave(gameState, seedState)
    seedState.updatedAt = nowSeconds()

    local cache = ensureLoaded()
    cache.enabled = true
    cache.dirty = true
    cache.lastSyncAt = 0
    cache.seedFromSaveUsed = true
    cache.ledgerId = generateLedgerId()
    cache.revision = 0
    cache.baselineRevision = 0
    applyStateInPlace(cache.state, seedState)
    bootstrapped_ = true
    bootstrapping_ = false
    ready_ = true
    if gameState then
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    end
    LegendGachaCloud.saveLocal()
    return LegendGachaCloud.syncToCloud(events)
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
    if not cache.ledgerId then cache.ledgerId = generateLedgerId() end
    applyStateInPlace(cache.state, cleanState())
    bootstrapped_ = true
    bootstrapping_ = false
    ready_ = true
    if gameState then
        LegendGachaCloud.syncMirrorToSave(gameState, cache.state)
    end
    LegendGachaCloud.saveLocal()
    return LegendGachaCloud.syncToCloud(events)
end

function LegendGachaCloud.getDebugSummary()
    local cache = ensureLoaded()
    local state = normalizeState(cache.state)
    return string.format(
        "enabled=%s ready=%s dirty=%s seedUsed=%s rev=%d pulls=%d legends=%d attach=%s conflict=%s",
        tostring(cache.enabled), tostring(ready_), tostring(cache.dirty), tostring(cache.seedFromSaveUsed),
        tonumber(cache.revision) or 0, tonumber(state.pulls) or 0, #(state.pulledLegendIds or {}),
        tostring(cache.pendingAccountAttach), tostring(cache.pendingConflict))
end

--- 测试专用：重置模块内存状态
function LegendGachaCloud._resetForTests(opts)
    opts = opts or {}
    cache_ = nil
    syncInFlight_ = false
    bootstrapped_ = false
    ready_ = false
    bootstrapping_ = false
    pendingSync_ = false
    syncSeq_ = 0
    inflightSeq_ = nil
    pendingRemoteEnvelope_ = nil
    if opts.cache then
        cache_ = normalizeCache(opts.cache)
    end
    if opts.ready ~= nil then ready_ = opts.ready end
    if opts.bootstrapped ~= nil then bootstrapped_ = opts.bootstrapped end
    if opts.pendingRemoteEnvelope then
        pendingRemoteEnvelope_ = opts.pendingRemoteEnvelope
    end
end

--- 测试专用：读取 envelope state 字段
function LegendGachaCloud._envelopeState(payload)
    return envelopeStateField(payload)
end

return LegendGachaCloud
