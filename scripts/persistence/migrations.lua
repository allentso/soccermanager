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
    local data = JsonLoader.loadFromResource("Data/legends_alltime_top50.json")
    if data and data.players then
        for _, lData in ipairs(data.players) do
            local name = lData.full_name_cn or lData.match_name
            if name and lData.traits then
                legendLookup[name] = lData.traits
            end
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

--- v3 → v4: 从已完成比赛重算联赛积分榜（修复重复计分导致的 played 偏高）
--- 原因：旧版 match_live 的两个按钮均调用 finishMatch，缺乏幂等保护导致同一比赛被计入两次
function Migrations.v3_to_v4(gameStateData)
    local leagues = gameStateData.leagues
    if not leagues then return end

    local totalFixed = 0

    for _, leagueData in pairs(leagues) do
        local fixtures = leagueData.fixtures
        local teamIds = leagueData.teamIds
        if not fixtures or not teamIds then goto continue end

        -- 从零重建 standings
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

        -- 遍历所有已完成比赛，累加统计
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

        -- 比较并替换
        local oldStandings = leagueData.standings or {}
        local leagueFixed = false
        for tid, newS in pairs(newStandings) do
            local oldKey = oldStandings[tid] or oldStandings[tostring(tid)]
            if oldKey and oldKey.played ~= newS.played then
                leagueFixed = true
                break
            end
        end

        -- 使用数字 key 写回（与 League.new 反序列化逻辑一致）
        leagueData.standings = newStandings
        if leagueFixed then
            totalFixed = totalFixed + 1
        end

        ::continue::
    end

    print("[SaveMigration] v3→v4: 重算了 " .. totalFixed .. " 个联赛的积分榜（从比赛记录重建）")
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

    saveData.version = version
    return version
end

return Migrations
