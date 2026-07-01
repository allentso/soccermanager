-- systems/scout_manager.lua
-- 球探系统：按条件探索球员、生成报告、准确度与职员加成

local Constants = require("scripts/app/constants")
local StaffManager = require("scripts/systems/staff_manager")
local MessageManager = require("scripts/systems/message_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local Nationality = require("scripts/domain/nationality")

local ScoutManager = {}

------------------------------------------------------
-- 常量
------------------------------------------------------
local SCOUT_DAYS_BASE = 7       -- 基础球探时间（天）
local MAX_ACTIVE_TASKS = 3      -- 最多同时进行的球探任务
local REPORT_EXPIRY_DAYS = 60   -- 报告60天后过期
local RESULTS_PER_TASK = 5      -- 每次探索返回球员数

--- 国籍名称映射（匹配数据中实际使用的国籍代码）
local NATION_NAMES = {
    -- 欧洲
    ENG = "英格兰", ES = "西班牙", DE = "德国", IT = "意大利",
    FR = "法国", PT = "葡萄牙", NL = "荷兰", BE = "比利时",
    HR = "克罗地亚", AT = "奥地利", CH = "瑞士", SE = "瑞典",
    DK = "丹麦", NO = "挪威", FI = "芬兰", PL = "波兰",
    CZ = "捷克", SK = "斯洛伐克", HU = "匈牙利", RO = "罗马尼亚",
    BG = "保加利亚", RS = "塞尔维亚", BA = "波黑", ME = "黑山",
    MK = "北马其顿", SI = "斯洛文尼亚", AL = "阿尔巴尼亚",
    GR = "希腊", GRE = "希腊", TR = "土耳其", CY = "塞浦路斯",
    IS = "冰岛", IE = "爱尔兰", SCO = "苏格兰", WAL = "威尔士",
    NIR = "北爱尔兰", LU = "卢森堡", EE = "爱沙尼亚",
    MD = "摩尔多瓦", GE = "格鲁吉亚", AM = "亚美尼亚",
    XK = "科索沃", AND = "安道尔", RU = "俄罗斯", UA = "乌克兰",
    IL = "以色列",
    -- 南美洲
    BR = "巴西", AR = "阿根廷", UY = "乌拉圭", CO = "哥伦比亚",
    CL = "智利", PE = "秘鲁", EC = "厄瓜多尔", PY = "巴拉圭",
    VE = "委内瑞拉", SUR = "苏里南",
    -- 北中美及加勒比
    MX = "墨西哥", US = "美国", CA = "加拿大", JM = "牙买加",
    HN = "洪都拉斯", PA = "巴拿马", GUA = "危地马拉",
    DOM = "多米尼加", FRE = "法属圭亚那",
    -- 非洲
    NG = "尼日利亚", GH = "加纳", CM = "喀麦隆", SN = "塞内加尔",
    CI = "科特迪瓦", MA = "摩洛哥", DZ = "阿尔及利亚", EG = "埃及",
    TN = "突尼斯", ML = "马里", BF = "布基纳法索", BUR = "布基纳法索",
    GN = "几内亚", GUI = "几内亚比绍", GA = "加蓬", CD = "刚果(金)",
    CON = "刚果(布)", TOG = "多哥", BEN = "贝宁", KE = "肯尼亚",
    ZA = "南非", ZM = "赞比亚", ZW = "津巴布韦", AO = "安哥拉",
    MOZ = "莫桑比克", CEN = "中非", CAP = "佛得角", COM = "科摩罗",
    EQU = "赤道几内亚", THE = "冈比亚", MAL = "马耳他",
    -- 亚洲及大洋洲
    CN = "中国", CHN = "中国", JP = "日本", KR = "韩国", AU = "澳大利亚", NZ = "新西兰",
    IR = "伊朗", JOR = "约旦", UZB = "乌兹别克斯坦",
    PHI = "菲律宾",
    -- FIFA 三字母码别名（青训系统使用）
    BRA = "巴西", ARG = "阿根廷", FRA = "法国", GER = "德国",
    ESP = "西班牙", ENG = "英格兰", NED = "荷兰", POR = "葡萄牙",
    ITA = "意大利", BEL = "比利时", COL = "哥伦比亚", URU = "乌拉圭",
    CRO = "克罗地亚", SRB = "塞尔维亚", MEX = "墨西哥", NGA = "尼日利亚",
}

--- 获取国籍中文名
function ScoutManager.getNationName(code)
    return NATION_NAMES[code] or code
end

--- 获取全部可选国籍（去重、按中文名排序）
---@return table[] { code: string, name: string }
function ScoutManager.getNationOptionList()
    local seen = {}
    local list = {}
    for code, name in pairs(NATION_NAMES) do
        local norm = Nationality.normalize(code)
        if not seen[norm] then
            seen[norm] = true
            table.insert(list, { code = norm, name = name })
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.code < b.code
        end
        return a.name < b.name
    end)
    return list
end

local function textMatchesSearch(text, lowerQuery)
    if not text or text == "" or not lowerQuery or lowerQuery == "" then
        return false
    end
    return text:lower():find(lowerQuery, 1, true) ~= nil
end

--- 判断球队名称是否匹配搜索关键词（全称 + 简称）
function ScoutManager.teamMatchesSearch(team, lowerQuery)
    if not team or lowerQuery == "" then return false end
    return textMatchesSearch(team.name, lowerQuery)
        or textMatchesSearch(team.shortName, lowerQuery)
end

--- 判断球员姓名相关字段是否匹配搜索关键词
function ScoutManager.playerNameMatchesSearch(player, lowerQuery)
    if not player or lowerQuery == "" then return false end
    if textMatchesSearch(player.displayName, lowerQuery) then return true end
    if textMatchesSearch(player.firstName, lowerQuery) then return true end
    if textMatchesSearch(player.lastName, lowerQuery) then return true end
    if textMatchesSearch(player.matchName, lowerQuery) then return true end
    if textMatchesSearch(player.shortName, lowerQuery) then return true end
    if textMatchesSearch(player.legendName, lowerQuery) then return true end
    if textMatchesSearch(player.reincarnationMatchName, lowerQuery) then return true end
    local combined = (player.firstName or "") .. (player.lastName or "")
    return textMatchesSearch(combined, lowerQuery)
end

--- 转会市场搜索上下文：国籍命中集 + 租借索引（循环外构建一次）
---@param gameState table
---@param lowerQuery string
---@return table|nil
function ScoutManager.buildMarketSearchContext(gameState, lowerQuery)
    if not lowerQuery or lowerQuery == "" then return nil end

    local matchingNationNorms = {}
    for code, name in pairs(NATION_NAMES) do
        if name:lower():find(lowerQuery, 1, true)
            or code:lower():find(lowerQuery, 1, true) then
            matchingNationNorms[Nationality.normalize(code)] = true
        end
    end

    local loanByPlayer = {}
    for _, loan in ipairs(gameState._activeLoans or {}) do
        loanByPlayer[loan.playerId] = loan
    end

    return {
        matchingNationNorms = matchingNationNorms,
        loanByPlayer = loanByPlayer,
    }
end

local function nationalityMatchesSearchWithContext(natCode, lowerQuery, ctx)
    if not natCode or lowerQuery == "" then return false end
    if natCode:lower():find(lowerQuery, 1, true) then return true end
    local norm = Nationality.normalize(natCode)
    if norm:lower():find(lowerQuery, 1, true) then return true end
    if ctx and ctx.matchingNationNorms then
        return ctx.matchingNationNorms[norm] == true
    end
    return ScoutManager.nationalityMatchesSearch(natCode, lowerQuery)
end

--- 转会市场浏览：球员名/所属队/租借队/国籍综合匹配
---@param ctx table|nil ScoutManager.buildMarketSearchContext 的返回值
function ScoutManager.playerMatchesMarketSearch(gameState, player, lowerQuery, ctx)
    if lowerQuery == "" then return true end
    if ScoutManager.playerNameMatchesSearch(player, lowerQuery) then return true end
    local team = player.teamId and gameState.teams[player.teamId]
    if team and ScoutManager.teamMatchesSearch(team, lowerQuery) then return true end
    if nationalityMatchesSearchWithContext(player.nationality, lowerQuery, ctx) then return true end
    local loan = ctx and ctx.loanByPlayer and ctx.loanByPlayer[player.id]
    if not loan and not ctx then
        local TransferManager = require("scripts/systems/transfer_manager")
        loan = TransferManager.getLoanForPlayer(gameState, player.id)
    end
    if loan then
        local loanTeam = gameState.teams[loan.loanTeamId]
        if loanTeam and ScoutManager.teamMatchesSearch(loanTeam, lowerQuery) then
            return true
        end
    end
    return false
end

--- 搜索匹配优先级（越高越靠前）：全名 > 前缀 > 子串
function ScoutManager.getPlayerSearchRank(player, lowerQuery)
    if not player or lowerQuery == "" then return 0 end
    local fields = {
        player.displayName, player.firstName, player.lastName,
        player.matchName, player.shortName, player.legendName,
        player.reincarnationMatchName,
    }
    local best = 0
    for _, field in ipairs(fields) do
        if field and field ~= "" then
            local lower = field:lower()
            if lower == lowerQuery then
                best = math.max(best, 100)
            elseif #lowerQuery <= #lower and lower:sub(1, #lowerQuery) == lowerQuery then
                best = math.max(best, 80)
            elseif lower:find(lowerQuery, 1, true) then
                best = math.max(best, 50)
            end
        end
    end
    return best
end

--- 判断球员国籍是否匹配搜索关键词（支持中文名、代码及别名）
function ScoutManager.nationalityMatchesSearch(natCode, lowerQuery)
    if not natCode or lowerQuery == "" then return false end
    local lowerCode = natCode:lower()
    if lowerCode:find(lowerQuery, 1, true) then return true end
    local norm = Nationality.normalize(natCode)
    if norm:lower():find(lowerQuery, 1, true) then return true end
    for code, name in pairs(NATION_NAMES) do
        if Nationality.matches(code, natCode) and name:lower():find(lowerQuery, 1, true) then
            return true
        end
    end
    return false
end

--- 获取可用国籍列表（从当前球员数据中统计，返回全部国籍）
function ScoutManager.getAvailableNationalities(gameState)
    local countMap = {}
    for _, player in pairs(gameState.players) do
        local nat = player.nationality
        if nat then
            countMap[nat] = (countMap[nat] or 0) + 1
        end
    end
    -- 按数量排序，返回全部国籍
    local list = {}
    for code, count in pairs(countMap) do
        table.insert(list, { code = code, name = NATION_NAMES[code] or code, count = count })
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

------------------------------------------------------
-- 准确度计算（统一公式，UI层也使用此方法）
------------------------------------------------------

--- 获取球探系统的当前准确度
---@param gameState table
---@return number accuracy 0~1
function ScoutManager.getAccuracy(gameState)
    local teamId = gameState.playerTeamId
    local team = gameState:getPlayerTeam()
    if not team then return 0.5 end

    local bestAbility = 0
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == Constants.STAFF_ROLES.SCOUT then
            local ability = s.attributes and s.attributes.scouting or (s.ability or 10)
            if ability > bestAbility then bestAbility = ability end
        end
    end

    local scoutBonus = StaffManager.getScoutingBonus(gameState, teamId)
    local facilityBonus = FinanceManager.getFacilityBonuses(team).scoutingAccuracy

    return math.min(0.97, (0.50 + bestAbility * 0.02 + scoutBonus) * facilityBonus)
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 创建球探探索任务（按条件搜索）
--- filters: { leagueId?, position?, minAge?, maxAge?, minOvr?, maxOvr? }
---@param gameState table
---@param filters table 搜索条件
---@return boolean success, string? error
function ScoutManager.createSearchTask(gameState, filters)
    filters = filters or {}
    if filters.position and filters.position ~= "" then
        filters.position = Constants.normalizePosition(filters.position)
    end
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    local scouts = ScoutManager._getTeamScouts(gameState, team)
    if #scouts == 0 then
        return false, "球队没有球探，请先雇佣一名球探"
    end

    gameState._scoutTasks = gameState._scoutTasks or {}
    local activeCount = 0
    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then activeCount = activeCount + 1 end
    end
    if activeCount >= MAX_ACTIVE_TASKS then
        return false, string.format("同时最多进行 %d 项球探任务", MAX_ACTIVE_TASKS)
    end

    -- 选出最佳球探
    local bestScout = scouts[1]
    for _, s in ipairs(scouts) do
        if (s.attributes.scouting or 0) > (bestScout.attributes.scouting or 0) then
            bestScout = s
        end
    end
    local scoutAbility = bestScout.attributes.scouting or 10
    local daysNeeded = math.max(3, SCOUT_DAYS_BASE - math.floor(scoutAbility / 5))

    -- 生成任务描述
    local desc = ScoutManager._buildTaskDescription(filters, gameState)

    local task = {
        id = gameState:generateId(),
        type = "search",
        filters = filters,
        description = desc,
        scoutId = bestScout.id,
        startDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        daysRemaining = daysNeeded,
        totalDays = daysNeeded,
        completed = false,
    }
    table.insert(gameState._scoutTasks, task)

    return true
end

--- 保留：指派球探观察某球员（从报告中深入调查）
---@param gameState table
---@param playerId number 被观察球员ID
---@return boolean success, string? error
function ScoutManager.assignScout(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return false, "没有球队" end

    local scouts = ScoutManager._getTeamScouts(gameState, team)
    if #scouts == 0 then
        return false, "球队没有球探，请先雇佣一名球探"
    end

    gameState._scoutTasks = gameState._scoutTasks or {}
    local activeCount = 0
    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then activeCount = activeCount + 1 end
    end
    if activeCount >= MAX_ACTIVE_TASKS then
        return false, string.format("同时最多进行 %d 项球探任务", MAX_ACTIVE_TASKS)
    end

    local targetPlayer = gameState.players[playerId]
    if not targetPlayer then return false, "目标球员不存在" end

    -- 已有进行中的同一目标
    for _, task in ipairs(gameState._scoutTasks) do
        if task.playerId == playerId and not task.completed then
            return false, "已在观察该球员"
        end
    end

    local bestScout = scouts[1]
    for _, s in ipairs(scouts) do
        if (s.attributes.scouting or 0) > (bestScout.attributes.scouting or 0) then
            bestScout = s
        end
    end
    local scoutAbility = bestScout.attributes.scouting or 10
    local daysNeeded = math.max(3, SCOUT_DAYS_BASE - math.floor(scoutAbility / 5))

    local task = {
        id = gameState:generateId(),
        type = "observe",
        playerId = playerId,
        description = "深入观察: " .. (targetPlayer.displayName or "未知"),
        scoutId = bestScout.id,
        startDate = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        daysRemaining = daysNeeded,
        totalDays = daysNeeded,
        completed = false,
    }
    table.insert(gameState._scoutTasks, task)

    return true
end

--- 取消球探任务
---@param gameState table
---@param taskId number
---@return boolean
function ScoutManager.cancelTask(gameState, taskId)
    gameState._scoutTasks = gameState._scoutTasks or {}
    for i, task in ipairs(gameState._scoutTasks) do
        if task.id == taskId and not task.completed then
            table.remove(gameState._scoutTasks, i)
            return true
        end
    end
    return false
end

--- 每日处理（推进球探任务倒计时）
---@param gameState table
function ScoutManager.processDaily(gameState)
    gameState._scoutTasks = gameState._scoutTasks or {}

    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then
            task.daysRemaining = task.daysRemaining - 1
            if task.daysRemaining <= 0 then
                task.completed = true
                if task.type == "search" then
                    ScoutManager._generateSearchReport(gameState, task)
                else
                    ScoutManager._generateReport(gameState, task)
                end
            end
        end
    end

    -- 清理过期报告
    ScoutManager._cleanupExpiredReports(gameState)
end

--- 获取当前活跃的球探任务
---@param gameState table
---@return table[]
function ScoutManager.getActiveTasks(gameState)
    gameState._scoutTasks = gameState._scoutTasks or {}
    local result = {}
    for _, task in ipairs(gameState._scoutTasks) do
        if not task.completed then
            table.insert(result, {
                id = task.id,
                type = task.type or "observe",
                description = task.description or "球探任务",
                daysRemaining = task.daysRemaining,
                totalDays = task.totalDays,
                progress = math.floor((1 - task.daysRemaining / task.totalDays) * 100),
            })
        end
    end
    return result
end

--- 获取已完成的球探报告列表
---@param gameState table
---@return table[]
function ScoutManager.getReports(gameState)
    gameState.scoutReports = gameState.scoutReports or {}
    local result = {}
    for _, report in ipairs(gameState.scoutReports) do
        table.insert(result, report)
    end
    table.sort(result, function(a, b) return a.id > b.id end)
    return result
end

--- 获取某球员最新的球探报告
---@param gameState table
---@param playerId number
---@return table|nil
function ScoutManager.getPlayerReport(gameState, playerId)
    gameState.scoutReports = gameState.scoutReports or {}
    for i = #gameState.scoutReports, 1, -1 do
        if gameState.scoutReports[i].playerId == playerId then
            return gameState.scoutReports[i]
        end
    end
    return nil
end

--- 获取可用的联赛列表（用于筛选 UI）
---@param gameState table
---@return table[] { id, name }
function ScoutManager.getAvailableLeagues(gameState)
    local result = {}
    for key, league in pairs(gameState.leagues or {}) do
        table.insert(result, { id = key, name = league.name })
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

--- 探索任务完成：根据筛选条件匹配球员，生成批量简报
function ScoutManager._generateSearchReport(gameState, task)
    local filters = task.filters or {}
    local candidates = ScoutManager._findCandidates(gameState, filters)

    -- 随机选取最多 RESULTS_PER_TASK 名
    ScoutManager._shuffle(candidates)
    local selectedCount = math.min(RESULTS_PER_TASK, #candidates)

    if selectedCount == 0 then
        MessageManager.send(gameState, "scout_report_ready", {
            task.description, "未找到符合条件的球员"
        })
        return
    end

    local accuracy = ScoutManager.getAccuracy(gameState)

    for i = 1, selectedCount do
        local player = candidates[i]
        ScoutManager._generatePlayerReport(gameState, player, accuracy, task.id)
    end

    MessageManager.send(gameState, "scout_report_ready", {
        task.description, string.format("发现 %d 名球员", selectedCount)
    })
end

--- 单人观察任务完成：生成详细报告
function ScoutManager._generateReport(gameState, task)
    local player = gameState.players[task.playerId]
    if not player then return end

    local accuracy = ScoutManager.getAccuracy(gameState)
    ScoutManager._generatePlayerReport(gameState, player, accuracy, task.id)

    MessageManager.send(gameState, "scout_report_ready", {
        player.displayName, "观察报告已完成"
    })
end

--- 生成单个球员的报告条目
function ScoutManager._generatePlayerReport(gameState, player, accuracy, taskId)
    -- 生成带误差的属性评估
    local reportedAttrs = {}
    local attrs = player.attributes or {}
    for key, val in pairs(attrs) do
        local errorRange = math.floor((1 - accuracy) * 6)
        local noise = RandomInt(-errorRange, errorRange)
        reportedAttrs[key] = math.max(1, math.min(20, val + noise))
    end

    -- 估算总评（带误差）
    local reportedOverall = player.overall or 50
    local overallNoise = RandomInt(-math.floor((1 - accuracy) * 10), math.floor((1 - accuracy) * 10))
    reportedOverall = math.max(20, math.min(99, reportedOverall + overallNoise))

    -- 潜力评估
    local reportedPotential = player.actualPotential or player.potential or 50
    local age = (player.birthYear and (gameState.date.year - player.birthYear)) or 25
    if age <= 23 then
        local potNoise = RandomInt(-math.floor((1 - accuracy) * 8), math.floor((1 - accuracy) * 8))
        reportedPotential = math.max(20, math.min(99, reportedPotential + potNoise))
    end

    local recommendation = ScoutManager._getRecommendation(reportedOverall, reportedPotential, age)

    local report = {
        id = gameState:generateId(),
        taskId = taskId,
        playerId = player.id,
        playerName = player.displayName,
        playerPosition = player.position,
        playerAge = age,
        teamName = ScoutManager._getPlayerTeamName(gameState, player),
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        accuracy = math.floor(accuracy * 100),
        overall = reportedOverall,
        potential = reportedPotential,
        attributes = reportedAttrs,
        recommendation = recommendation,
        wage = player.wage,
        value = player.value,
        contractEnd = player.contractEnd,
    }

    gameState.scoutReports = gameState.scoutReports or {}
    table.insert(gameState.scoutReports, report)
end

--- 根据筛选条件在数据库中查找候选球员
function ScoutManager._findCandidates(gameState, filters)
    local myTeamId = gameState.playerTeamId
    local candidates = {}

    -- 如果指定了联赛，找出该联赛下的所有球队
    local leagueTeamIds = nil
    if filters.leagueId and gameState.leagues[filters.leagueId] then
        leagueTeamIds = {}
        local league = gameState.leagues[filters.leagueId]
        for _, tid in ipairs(league.teamIds or {}) do
            leagueTeamIds[tid] = true
        end
    end

    for _, player in pairs(gameState.players) do
        if player.teamId ~= myTeamId then
            local pass = true

            -- 联赛筛选
            if leagueTeamIds then
                if not player.teamId or not leagueTeamIds[player.teamId] then
                    pass = false
                end
            end

            -- 位置筛选
            if pass and filters.position and filters.position ~= "" then
                if player.position ~= filters.position then
                    pass = false
                end
            end

            -- 国籍筛选
            if pass and filters.nationality and filters.nationality ~= "" then
                if not Nationality.matches(player.nationality, filters.nationality) then
                    pass = false
                end
            end

            -- 年龄筛选
            if pass then
                local age = player:getAge(gameState.date.year)
                if filters.minAge and age < filters.minAge then pass = false end
                if filters.maxAge and age > filters.maxAge then pass = false end
            end

            -- OVR 筛选
            if pass then
                local ovr = player.overall or 0
                if filters.minOvr and ovr < filters.minOvr then pass = false end
                if filters.maxOvr and ovr > filters.maxOvr then pass = false end
            end

            if pass then
                table.insert(candidates, player)
            end
        end
    end

    return candidates
end

--- 生成任务描述文本
function ScoutManager._buildTaskDescription(filters, gameState)
    local parts = {}

    if filters.leagueId and gameState.leagues[filters.leagueId] then
        table.insert(parts, gameState.leagues[filters.leagueId].name)
    end
    if filters.nationality and filters.nationality ~= "" then
        table.insert(parts, NATION_NAMES[filters.nationality] or filters.nationality)
    end
    if filters.position and filters.position ~= "" then
        local posName = Constants.POSITION_NAMES[filters.position] or filters.position
        table.insert(parts, posName)
    end
    if filters.minAge or filters.maxAge then
        local minA = filters.minAge or 16
        local maxA = filters.maxAge or 40
        table.insert(parts, minA .. "-" .. maxA .. "岁")
    end

    if #parts == 0 then
        return "全范围探索"
    end
    return table.concat(parts, " · ")
end

function ScoutManager._getRecommendation(overall, potential, age)
    if potential >= 80 and age <= 21 then
        return "强烈推荐签入"
    elseif overall >= 75 then
        return "实力强劲，可即战"
    elseif potential >= 70 and age <= 23 then
        return "潜力新星，值得培养"
    elseif overall >= 60 then
        return "水平尚可，可作补充"
    else
        return "不建议签入"
    end
end

function ScoutManager._getPlayerTeamName(gameState, player)
    if player.teamId then
        local team = gameState.teams[player.teamId]
        if team then return team.shortName or team.name end
    end
    return "自由球员"
end

function ScoutManager._getTeamScouts(gameState, team)
    local scouts = {}
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s and s.role == Constants.STAFF_ROLES.SCOUT then
            table.insert(scouts, s)
        end
    end
    return scouts
end

function ScoutManager._cleanupExpiredReports(gameState)
    gameState.scoutReports = gameState.scoutReports or {}
    local valid = {}
    local currentDays = ScoutManager._dateToDays(gameState.date)
    for _, report in ipairs(gameState.scoutReports) do
        local reportDays = ScoutManager._dateToDays(report.date)
        local elapsed = currentDays - reportDays
        if elapsed <= REPORT_EXPIRY_DAYS then
            table.insert(valid, report)
        end
    end
    gameState.scoutReports = valid
end

function ScoutManager._dateToDays(date)
    if not date then return 0 end
    local y = date.year or 0
    local m = date.month or 1
    local d = date.day or 1
    return y * 360 + (m - 1) * 30 + d
end

--- Fisher-Yates 随机洗牌
function ScoutManager._shuffle(t)
    for i = #t, 2, -1 do
        local j = RandomInt(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

return ScoutManager
