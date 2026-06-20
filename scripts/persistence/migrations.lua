-- persistence/migrations.lua
-- 存档版本迁移：在不破坏玩家进度的前提下，修正旧存档的数据偏差

local JsonLoader = require("scripts/data/json_loader")

local Migrations = {}

-- 联赛文件配置（与 real_data_loader 保持一致）
local LEAGUE_FILES = {
    "fm2024_premier_league.json",
    "fm2024_la_liga.json",
    "fm2024_serie_a.json",
    "fm2024_bundesliga.json",
    "fm2024_ligue_1.json",
    "fm2024_csl.json",
}

--- 从 wage_budget 计算 reputation（与 RealDataLoader._calcReputation 相同）
local function calcReputation(wageBudget)
    local wb = wageBudget or 200000
    local logWb = math.log(wb)
    local logMin = math.log(200000)
    local logMax = math.log(6500000)
    local ratio = (logWb - logMin) / (logMax - logMin)
    ratio = math.max(0, math.min(1, ratio))
    return math.floor(500 + ratio * 450)
end

--- 构建 jsonTeamId → {wage_budget, stadium_capacity} 查找表
local function buildTeamLookup()
    local lookup = {}
    for _, filename in ipairs(LEAGUE_FILES) do
        local data = JsonLoader.loadFromResource("Data/" .. filename)
        if data and data.teams then
            for _, tData in ipairs(data.teams) do
                if tData.id then
                    lookup[tData.id] = {
                        wage_budget = tData.wage_budget,
                        stadium_capacity = tData.stadium_capacity,
                    }
                end
            end
        end
    end
    return lookup
end

--- v1 → v2: 用 JSON 数据源刷新球队 reputation 和 stadiumCapacity
--- 只修正影响未来收入的参数，不碰余额/历史收入/阵容等玩家进度
function Migrations.v1_to_v2(gameStateData)
    local teams = gameStateData.teams
    if not teams then return end

    local lookup = buildTeamLookup()
    local migrated = 0

    for _, teamData in pairs(teams) do
        local jsonId = teamData.jsonTeamId
        if jsonId and lookup[jsonId] then
            local source = lookup[jsonId]
            -- 刷新 reputation（收入公式核心变量）
            local newRep = calcReputation(source.wage_budget)
            if teamData.reputation ~= newRep then
                teamData.reputation = newRep
                migrated = migrated + 1
            end
            -- 刷新 stadiumCapacity（赞助公式依赖）
            if source.stadium_capacity and teamData.stadiumCapacity ~= source.stadium_capacity then
                teamData.stadiumCapacity = source.stadium_capacity
            end
            -- 刷新 wageBudget（wageScale 计算依赖）
            if source.wage_budget and teamData.wageBudget ~= source.wage_budget then
                teamData.wageBudget = source.wage_budget
            end
        end
    end

    print("[SaveMigration] v1→v2: 已刷新 " .. migrated .. " 支球队的 reputation 数据")
end

--- v2 → v3: 为旧存档中已签入的传奇球员补发专属特质
--- 同时确保 LEGEND_ATTR_MAX / LEGEND_OVERALL_MAX 常量可以生效（无需修改数据，运行时判断）
function Migrations.v2_to_v3(gameStateData)
    local players = gameStateData.players
    if not players then return end

    -- 加载传奇球员 JSON 数据，构建名字→traits 查找表
    local legendLookup = {}
    local LegendsLoader = require("scripts/data/legends_loader")
    for _, lData in ipairs(LegendsLoader.loadAllPlayers()) do
        local name = lData.full_name_cn or lData.match_name
        if name and lData.traits then
            legendLookup[name] = lData.traits
        end
    end

    local migrated = 0
    for _, pData in pairs(players) do
        if pData.isLegend then
            -- 补发特质：如果传奇球员没有特质或为空表，从 JSON 补充
            local needTraits = not pData.traits or #pData.traits == 0
            if needTraits then
                local legendName = pData.legendName or pData.displayName
                local jsonTraits = legendLookup[legendName]
                if jsonTraits then
                    pData.traits = jsonTraits
                    migrated = migrated + 1
                end
            end
        end
    end

    print("[SaveMigration] v2→v3: 已为 " .. migrated .. " 名传奇球员补发专属特质")
end

--- 从联赛 fixtures 重建积分榜（不含杯赛/欧冠等）
--- @return number 修正的联赛数量
local function rebuildLeagueStandingsFromFixtures(gameStateData)
    local leagues = gameStateData.leagues
    if not leagues then return 0 end

    local totalFixed = 0

    for _, leagueData in pairs(leagues) do
        local fixtures = leagueData.fixtures
        local teamIds = leagueData.teamIds
        if not fixtures or not teamIds then goto continue end

        local newStandings = {}
        for _, tid in ipairs(teamIds) do
            newStandings[tid] = {
                teamId = tid,
                played = 0,
                wins = 0,
                draws = 0,
                losses = 0,
                goalsFor = 0,
                goalsAgainst = 0,
                goalDifference = 0,
                points = 0,
            }
        end

        for _, f in ipairs(fixtures) do
            if f.status == "finished" then
                local home = newStandings[f.homeTeamId]
                local away = newStandings[f.awayTeamId]
                if home and away then
                    home.played = home.played + 1
                    away.played = away.played + 1
                    home.goalsFor = home.goalsFor + (f.homeGoals or 0)
                    home.goalsAgainst = home.goalsAgainst + (f.awayGoals or 0)
                    away.goalsFor = away.goalsFor + (f.awayGoals or 0)
                    away.goalsAgainst = away.goalsAgainst + (f.homeGoals or 0)

                    if f.homeGoals > f.awayGoals then
                        home.wins = home.wins + 1
                        home.points = home.points + 3
                        away.losses = away.losses + 1
                    elseif f.homeGoals < f.awayGoals then
                        away.wins = away.wins + 1
                        away.points = away.points + 3
                        home.losses = home.losses + 1
                    else
                        home.draws = home.draws + 1
                        home.points = home.points + 1
                        away.draws = away.draws + 1
                        away.points = away.points + 1
                    end

                    home.goalDifference = home.goalsFor - home.goalsAgainst
                    away.goalDifference = away.goalsFor - away.goalsAgainst
                end
            end
        end

        local oldStandings = leagueData.standings or {}
        local leagueFixed = false
        for tid, newS in pairs(newStandings) do
            local oldKey = oldStandings[tid] or oldStandings[tostring(tid)]
            if oldKey and oldKey.played ~= newS.played then
                leagueFixed = true
                break
            end
        end

        leagueData.standings = newStandings
        if leagueFixed then
            totalFixed = totalFixed + 1
        end

        ::continue::
    end

    return totalFixed
end

--- v3 → v4: 从已完成比赛重算联赛积分榜（修复重复计分导致的 played 偏高）
--- 原因：旧版 match_live 的两个按钮均调用 finishMatch，缺乏幂等保护导致同一比赛被计入两次
function Migrations.v3_to_v4(gameStateData)
    local totalFixed = rebuildLeagueStandingsFromFixtures(gameStateData)
    print("[SaveMigration] v3→v4: 重算了 " .. totalFixed .. " 个联赛的积分榜（从比赛记录重建）")
end

--- v4 → v5: 修正传奇球员因位置映射BUG被错误设为"CM"的问题
--- 原因：settings.lua 补偿抽卡的 posMap 用缩写 key 匹配全称 value，导致所有传奇 fallback 为 "CM"
--- 同时 real_data_loader 缺少 CentreBack 映射，导致中后卫传奇也变成 "CM"
function Migrations.v4_to_v5(gameStateData)
    local players = gameStateData.players
    if not players then return end

    -- 加载传奇球员 JSON 数据，构建名字→正确位置查找表
    local POSITION_MAP = {
        Goalkeeper = "GK",
        CentreBack = "CB", CenterBack = "CB",
        LeftBack = "LB", RightBack = "RB",
        LeftWingBack = "LB", RightWingBack = "RB",
        DefensiveMidfielder = "CDM",
        CentralMidfielder = "CM",
        AttackingMidfielder = "CAM",
        LeftMidfielder = "LM", RightMidfielder = "RM",
        LeftWinger = "LW", RightWinger = "RW",
        LeftWing = "LW", RightWing = "RW",
        Striker = "ST",
        CentreForward = "CF", CenterForward = "CF",
    }

    local legendPositions = {}  -- legendName → 正确的缩写位置
    local LegendsLoader = require("scripts/data/legends_loader")
    for _, lData in ipairs(LegendsLoader.loadAllPlayers()) do
        local name = lData.full_name_cn or lData.match_name
        if name and lData.position then
            legendPositions[name] = POSITION_MAP[lData.position] or "ST"
        end
    end

    local migrated = 0
    for _, pData in pairs(players) do
        if pData.isLegend and pData.legendName then
            local correctPos = legendPositions[pData.legendName]
            if correctPos and pData.position ~= correctPos then
                pData.position = correctPos
                -- 同时修正 naturalPositions 列表中的主位置
                if type(pData.naturalPositions) == "table" then
                    pData.naturalPositions[1] = correctPos
                end
                migrated = migrated + 1
            end
        end
    end

    print("[SaveMigration] v4→v5: 修正了 " .. migrated .. " 名传奇球员的位置映射")
end

--- v5 → v6: 修正非传奇球员OVR超过99的问题
--- 原因：旧版世界生成器random球员潜力过高(可达99)，触发巨星机制(PA>=95 → OVR上限101)
--- 修正后：只有传奇球员(isLegend=true)可突破99，普通球员一律封顶99
--- 同时降低随机生成球员的潜力上限至92，避免后续赛季持续产出过强球员
function Migrations.v5_to_v6(gameStateData)
    local players = gameStateData.players
    if not players then return end

    local Constants = require("scripts/app/constants")
    local GENERATED_POTENTIAL_CAP = 92  -- 与 world_generator 保持一致
    local OVR_CAP = Constants.ABILITY_MAX  -- 99

    local ovrFixed = 0
    local potentialFixed = 0

    for _, pData in pairs(players) do
        -- 跳过传奇球员（他们保留突破99的能力）
        if pData.isLegend then goto continue end

        -- 修正OVR超过99的非传奇球员
        if pData.overall and pData.overall > OVR_CAP then
            pData.overall = OVR_CAP
            ovrFixed = ovrFixed + 1
        end

        -- 对于随机生成的球员（无jsonPlayerId），降低过高的潜力
        -- 真实球员（有jsonPlayerId）保留原始潜力
        if not pData.jsonPlayerId then
            if pData.potential and pData.potential > GENERATED_POTENTIAL_CAP then
                pData.potential = GENERATED_POTENTIAL_CAP
                potentialFixed = potentialFixed + 1
            end
            if pData.actualPotential and pData.actualPotential > GENERATED_POTENTIAL_CAP then
                pData.actualPotential = GENERATED_POTENTIAL_CAP
            end
        end

        ::continue::
    end

    print("[SaveMigration] v5→v6: 修正了 " .. ovrFixed .. " 名非传奇球员的OVR(封顶99), "
        .. potentialFixed .. " 名随机球员的潜力(封顶" .. GENERATED_POTENTIAL_CAP .. ")")
end

--- 检测 displayName 是否含中文（真实 FM/传奇球员通常有中文名）
local function _hasChineseName(text)
    if not text or text == "" then return false end
    if text:find("·", 1, true) then return true end
    return text:match("[\228-\233][\128-\191][\128-\191]") ~= nil
end

--- 判断是否为旧版 _fillAISquads 静默补入的程序化球员
local function _isSeasonRegenFillPlayer(pData, teamData)
    if not pData or pData.isLegend or pData.isYouth or pData.retired then return false end
    if not pData.teamId or not teamData then return false end

    local wage = pData.wage or 0
    if wage < 500 or wage > 3000 then return false end

    local displayName = pData.displayName or ""
    if _hasChineseName(displayName) then return false end

    local firstName = pData.firstName or ""
    local lastName = pData.lastName or ""
    if displayName ~= (lastName .. " " .. firstName)
        and not displayName:match("^" .. lastName:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0")
            .. " " .. firstName:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0") .. " ") then
        return false
    end

    local SeasonManager = require("scripts/systems/season_manager")
    local country = teamData.country or pData.nationality or "ENG"
    local lastPool = SeasonManager._getLastNamePool(country)
    local firstPool = SeasonManager._getFirstNamePool(country)

    local lastMatch, firstMatch = false, false
    for _, n in ipairs(lastPool) do
        if n == lastName then lastMatch = true; break end
    end
    for _, n in ipairs(firstPool) do
        if n == firstName then firstMatch = true; break end
    end
    return lastMatch and firstMatch
end

--- 球队是否为「真实阵容」队（有 jsonTeamId / 传奇 / 中文名球员），而非纯程序化升降级队
local function _teamHasRealRoster(teamData, players)
    if teamData.jsonTeamId then return true end
    for _, pid in ipairs(teamData.playerIds or {}) do
        local p = players[tostring(pid)] or players[pid]
        if p then
            if p.isLegend then return true end
            if _hasChineseName(p.displayName) then return true end
        end
    end
    return false
end

local function _removePlayerIdFromArray(arr, playerId)
    if type(arr) ~= "table" then return end
    for i = #arr, 1, -1 do
        if arr[i] == playerId then
            table.remove(arr, i)
        end
    end
end

local function _removePlayerFromTeamData(teamData, playerId)
    _removePlayerIdFromArray(teamData.playerIds, playerId)
    _removePlayerIdFromArray(teamData._youthPlayerIds, playerId)
    _removePlayerIdFromArray(teamData.benchIds, playerId)
    _removePlayerIdFromArray(teamData.transferList, playerId)

    if teamData.startingXI then
        for slot, pid in pairs(teamData.startingXI) do
            if pid == playerId then teamData.startingXI[slot] = nil end
        end
    end

    local roleFields = {"captain", "penaltyTaker", "freeKickTaker", "cornerTaker"}
    for _, field in ipairs(roleFields) do
        if teamData[field] == playerId then teamData[field] = nil end
    end

    if teamData.lineupPresets then
        for _, preset in pairs(teamData.lineupPresets) do
            if type(preset) == "table" then
                if preset.startingXI then
                    for slot, pid in pairs(preset.startingXI) do
                        if pid == playerId then preset.startingXI[slot] = nil end
                    end
                end
                _removePlayerIdFromArray(preset.benchIds, playerId)
            end
        end
    end
end

--- v6 → v7: 移除旧版赛季初 _fillAISquads 静默补入的程序化球员
--- 只清理混入真实球队 roster 的假人；纯程序化升降级球队（无 jsonTeamId、全员假名）保留
function Migrations.v6_to_v7(gameStateData)
    local players = gameStateData.players
    local teams = gameStateData.teams
    if not players or not teams then return end

    local teamById = {}
    for _, teamData in pairs(teams) do
        if teamData.id then teamById[teamData.id] = teamData end
    end

    local toRemove = {}
    for idStr, pData in pairs(players) do
        local teamData = teamById[pData.teamId]
        if teamData and _teamHasRealRoster(teamData, players)
            and _isSeasonRegenFillPlayer(pData, teamData) then
            toRemove[#toRemove + 1] = pData.id or tonumber(idStr)
        end
    end

    if #toRemove == 0 then
        print("[SaveMigration] v6→v7: 未发现需清理的赛季补员假人")
        return
    end

    local removeSet = {}
    for _, pid in ipairs(toRemove) do removeSet[pid] = true end

    for _, pid in ipairs(toRemove) do
        local pData = players[tostring(pid)] or players[pid]
        local teamData = pData and teamById[pData.teamId]
        if teamData then
            _removePlayerFromTeamData(teamData, pid)
        end
        players[tostring(pid)] = nil
        players[pid] = nil
    end

    if gameStateData.transfers and gameStateData.transfers.bids then
        for i = #gameStateData.transfers.bids, 1, -1 do
            local bid = gameStateData.transfers.bids[i]
            if bid and bid.playerId and removeSet[bid.playerId] then
                table.remove(gameStateData.transfers.bids, i)
            end
        end
    end

    if gameStateData.shortlist then
        for pid in pairs(gameStateData.shortlist) do
            local key = tonumber(pid) or pid
            if removeSet[key] or removeSet[pid] then
                gameStateData.shortlist[pid] = nil
            end
        end
    end

    print("[SaveMigration] v6→v7: 已移除 " .. #toRemove .. " 名赛季补员假人")
end

--- v7 → v8: 从联赛赛程重算积分榜（剔除误计入的国内杯赛场次）
--- 原因：玩家手动踢/跳过杯赛时走 PlaceholderEngine.applyResult，杯赛结果被计入联赛积分榜
function Migrations.v7_to_v8(gameStateData)
    local totalFixed = rebuildLeagueStandingsFromFixtures(gameStateData)
    print("[SaveMigration] v7→v8: 重算了 " .. totalFixed .. " 个联赛的积分榜（剔除杯赛误计分）")
end

--- 非门将 traits 迁移：shot_stopper 移除，sweeper_keeper → libero（仅传奇保留 libero）
local function migrateOutfieldTraitList(traits, position, isLegend)
    if type(traits) ~= "table" or #traits == 0 then return traits, false end

    local Player = require("scripts/domain/player")
    local filtered, seen, changed = {}, {}, false

    for _, raw in ipairs(traits) do
        local resolved = Player.resolveTraitId(raw, position)
        if resolved == "libero" and not isLegend then
            changed = true
        elseif not resolved then
            changed = true
        elseif not seen[resolved] then
            seen[resolved] = true
            filtered[#filtered + 1] = resolved
            local normalized = Player.normalizeTraitId(raw)
            if normalized ~= resolved or raw ~= resolved then
                changed = true
            end
        else
            changed = true
        end
    end

    return filtered, changed
end

--- v8 → v9: 移除非门将球员身上的门将专属特质
--- 原因：旧版 calculateTraits 仅按 reflexes/handling 等属性判定，FM 数据中 outfield 球员也有门将属性值
function Migrations.v8_to_v9(gameStateData)
    local players = gameStateData.players
    if not players then return end

    local migrated = 0

    for _, pData in pairs(players) do
        if pData.position ~= "GK" then
            local changed = false

            if pData.traits then
                local filtered, traitsChanged = migrateOutfieldTraitList(
                    pData.traits, pData.position, pData.isLegend)
                if traitsChanged then
                    pData.traits = filtered
                    changed = true
                end
            end

            if pData.innateTraits then
                local filtered, innateChanged = migrateOutfieldTraitList(
                    pData.innateTraits, pData.position, pData.isLegend)
                if innateChanged then
                    pData.innateTraits = filtered
                    changed = true
                end
            end

            if changed then migrated = migrated + 1 end
        end
    end

    print("[SaveMigration] v8→v9: 已修正 " .. migrated .. " 名非门将球员的门将专属特质")
end

--- 非门将且 JSON traits 含 Sweeper 的传奇（清道夫）；loader 不可用时的兜底
local LEGEND_LIBERO_NAME_FALLBACK = {
    ["贝肯鲍尔"] = true, ["Beckenbauer"] = true,
    ["巴雷西"] = true, ["Baresi"] = true,
    ["博比·摩尔"] = true, ["Moore"] = true,
    ["劳伦特·布兰科"] = true, ["Blanc"] = true,
    ["马蒂亚斯·萨默尔"] = true, ["Sammer"] = true,
    ["里奥·费迪南德"] = true, ["Ferdinand"] = true,
}

--- 构建 JSON 中应持有清道夫特质的传奇球员名字集合（非门将且 traits 含 Sweeper）
local function buildLegendLiberoNameSet()
    local names = {}
    for key in pairs(LEGEND_LIBERO_NAME_FALLBACK) do
        names[key] = true
    end

    local ok, err = pcall(function()
        local LegendsLoader = require("scripts/data/legends_loader")
        for _, lData in ipairs(LegendsLoader.loadAllPlayers()) do
            if lData.position ~= "Goalkeeper" and type(lData.traits) == "table" then
                for _, t in ipairs(lData.traits) do
                    if t == "Sweeper" or t == "sweeper" then
                        local cn = lData.full_name_cn
                        local en = lData.match_name
                        if cn then names[cn] = true end
                        if en then names[en] = true end
                        break
                    end
                end
            end
        end
    end)
    if not ok then
        print("[SaveMigration] buildLegendLiberoNameSet: loader 失败，使用兜底名单 - " .. tostring(err))
    end
    return names
end

local function legendShouldHaveLibero(pData, liberoNames)
    if liberoNames[pData.legendName] then return true end
    if liberoNames[pData.displayName] then return true end
    return false
end

local function traitListHasId(traits, wantId)
    if type(traits) ~= "table" then return false end
    local Player = require("scripts/domain/player")
    for _, raw in ipairs(traits) do
        if Player.normalizeTraitId(raw) == wantId then return true end
    end
    return false
end

--- v9 → v10: 为非门将传奇补回清道夫特质（Sweeper 误映射为出击型门将后被移除的存档）
function Migrations.v9_to_v10(gameStateData)
    local players = gameStateData.players
    if not players then return end

    local liberoNames = buildLegendLiberoNameSet()
    local migrated = 0

    for _, pData in pairs(players) do
        if not pData.isLegend or pData.position == "GK" then goto continue end

        local legendName = pData.legendName or pData.displayName
        if not legendShouldHaveLibero(pData, liberoNames) then goto continue end
        if traitListHasId(pData.traits, "libero") then goto continue end

        pData.traits = pData.traits or {}
        table.insert(pData.traits, "libero")
        migrated = migrated + 1

        ::continue::
    end

    print("[SaveMigration] v9→v10: 已为 " .. migrated .. " 名传奇后卫补回清道夫特质")
end

--- v10 → v11: 统一球员 nationality 为标准代码（青训 FIFA 三字码如 ITA→IT）
function Migrations.v10_to_v11(gameStateData)
    local Nationality = require("scripts/domain/nationality")
    local players = gameStateData.players
    if not players then return end

    local migrated = 0
    for _, pData in pairs(players) do
        if pData.nationality then
            local normalized = Nationality.normalize(pData.nationality)
            if normalized ~= pData.nationality then
                pData.nationality = normalized
                migrated = migrated + 1
            end
        end
    end

    -- 候选池中的青训球员（尚未签入）
    local candidates = gameStateData._youthCandidates
    if candidates then
        for _, cData in ipairs(candidates) do
            if cData.nationality then
                local normalized = Nationality.normalize(cData.nationality)
                if normalized ~= cData.nationality then
                    cData.nationality = normalized
                    migrated = migrated + 1
                end
            end
        end
    end

    print("[SaveMigration] v10→v11: 已规范化 " .. migrated .. " 条球员 nationality 记录")
end

--- v11 → v12: 为球队补全财务底盘（_baseWageBudget / _financialScale）
function Migrations.v11_to_v12(gameStateData)
    local teams = gameStateData.teams or {}
    local count = 0
    for _, teamData in pairs(teams) do
        local wb = teamData.wageBudget or teamData._baseWageBudget or 200000
        if not teamData._baseWageBudget or teamData._baseWageBudget <= 0 then
            teamData._baseWageBudget = wb
            count = count + 1
        end
        if not teamData._financialScale or teamData._financialScale <= 0 then
            teamData._financialScale = math.sqrt(wb / 2000000)
            count = count + 1
        end
    end
    print("[SaveMigration] v11→v12: 已补全 " .. count .. " 条球队财务底盘记录")
end

--- v12 → v13: 修正 CentreForward 球员位置映射（之前 POSITION_MAP 缺少该条目导致 fallback 到 CM）
function Migrations.v12_to_v13(gameStateData)
    local players = gameStateData.players
    if not players then return end

    local LegendsLoader = require("scripts/data/legends_loader")

    -- 从 JSON 数据构建 CentreForward 传奇球员名单
    local cfLegends = {}  -- legendName → true
    for _, lData in ipairs(LegendsLoader.loadAllPlayers()) do
        if lData.position == "CentreForward" then
            local name = lData.full_name_cn or lData.match_name
            if name then cfLegends[name] = true end
        end
    end

    local migrated = 0
    for _, pData in pairs(players) do
        if pData.isLegend and pData.legendName and cfLegends[pData.legendName] then
            if pData.position ~= "CF" then
                local oldPos = pData.position
                pData.position = "CF"
                -- 修正 naturalPositions 列表中的主位置
                if type(pData.naturalPositions) == "table" then
                    pData.naturalPositions[1] = "CF"
                end
                migrated = migrated + 1
            end
        end
    end

    print("[SaveMigration] v12→v13: 修正了 " .. migrated .. " 名 CentreForward 传奇球员的位置映射(CM→CF)")
end

--- 迁移路由：根据存档版本逐级升级
--- @param saveData table 完整的存档顶层数据 {version, game_state, saved_at}
--- @return number 迁移后的最终版本号
function Migrations.run(saveData)
    local version = saveData.version or 1

    if version < 2 then
        Migrations.v1_to_v2(saveData.game_state)
        version = 2
    end

    if version < 3 then
        Migrations.v2_to_v3(saveData.game_state)
        version = 3
    end

    if version < 4 then
        Migrations.v3_to_v4(saveData.game_state)
        version = 4
    end

    if version < 5 then
        Migrations.v4_to_v5(saveData.game_state)
        version = 5
    end

    if version < 6 then
        Migrations.v5_to_v6(saveData.game_state)
        version = 6
    end

    if version < 7 then
        Migrations.v6_to_v7(saveData.game_state)
        version = 7
    end

    if version < 8 then
        Migrations.v7_to_v8(saveData.game_state)
        version = 8
    end

    if version < 9 then
        Migrations.v8_to_v9(saveData.game_state)
        version = 9
    end

    if version < 10 then
        Migrations.v9_to_v10(saveData.game_state)
        version = 10
    end

    if version < 11 then
        Migrations.v10_to_v11(saveData.game_state)
        version = 11
    end

    if version < 12 then
        Migrations.v11_to_v12(saveData.game_state)
        version = 12
    end

    if version < 13 then
        Migrations.v12_to_v13(saveData.game_state)
        version = 13
    end

    saveData.version = version
    return version
end

return Migrations
