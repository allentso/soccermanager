-- core/game_state.lua
-- 全局游戏状态根对象

local Player = require("scripts/domain/player")
local Team = require("scripts/domain/team")
local Staff = require("scripts/domain/staff")
local Manager = require("scripts/domain/manager")
local League = require("scripts/domain/league")
local Tournament = require("scripts/domain/tournament")

local GameState = {}
GameState.__index = GameState

function GameState.new()
    local self = setmetatable({}, GameState)

    -- 日期与赛季
    self.date = {year = 2025, month = 8, day = 10}
    self.season = 2025
    self.dayOfWeek = 1  -- 1=周一

    -- 玩家经理
    self.playerManagerId = nil
    self.playerTeamId = nil

    -- 实体数据（以ID为key的表）
    self.players = {}   -- [id] = Player实例
    self.teams = {}     -- [id] = Team实例
    self.staff = {}     -- [id] = Staff实例
    self.managers = {}  -- [id] = Manager实例

    -- 联赛（多联赛支持）
    self.leagues = {}       -- [shortName] = League实例（所有联赛）
    self.league = nil       -- 玩家所在联赛的快捷引用
    self.playerLeagueId = nil  -- 玩家所在联赛的key

    -- 锦标赛
    self.championsLeague = nil  -- 欧冠 Tournament 实例
    self.europaLeague = nil     -- 欧联杯 Tournament 实例
    self.worldCup = nil         -- 世界杯 Tournament 实例
    self.euroCup = nil          -- 欧洲杯 Tournament 实例

    -- 消息和新闻
    self.inbox = {}
    self.news = {}

    -- 世界历史
    self.worldHistory = {}

    -- 转会系统
    self.transfers = {
        bids = {},
        history = {},
        nextBidId = 1,
    }
    self.scoutReports = {}
    self.scoutDiscoveries = {}
    self.shortlist = {}  -- 候选名单：{playerId = true, ...}

    -- 下一个可用ID
    self.nextId = 1

    -- 回合状态
    self.turnState = "idle"  -- idle, processing, match_day

    -- 当前身份视角："club" 或 "national_team"
    self.currentRole = "club"

    return self
end

-- 生成唯一ID
function GameState:generateId()
    local id = self.nextId
    self.nextId = self.nextId + 1
    return id
end

-- 添加球员
function GameState:addPlayer(playerData)
    playerData.id = self:generateId()
    local player = Player.new(playerData)
    player:calculateOverall()
    player:calculateValue(self.date.year)
    self.players[player.id] = player
    return player
end

-- 添加球队
function GameState:addTeam(teamData)
    teamData.id = self:generateId()
    local team = Team.new(teamData)
    self.teams[team.id] = team
    return team
end

-- 添加职员
function GameState:addStaff(staffData)
    staffData.id = self:generateId()
    local s = Staff.new(staffData)
    self.staff[s.id] = s
    return s
end

-- 添加经理
function GameState:addManager(managerData)
    managerData.id = self:generateId()
    local m = Manager.new(managerData)
    self.managers[m.id] = m
    return m
end

-- 获取玩家球队
function GameState:getPlayerTeam()
    if self.playerTeamId then
        return self.teams[self.playerTeamId]
    end
    return nil
end

-- 获取玩家经理
function GameState:getPlayerManager()
    if self.playerManagerId then
        return self.managers[self.playerManagerId]
    end
    return nil
end

-- 获取球队的球员列表
function GameState:getTeamPlayers(teamId)
    local result = {}
    local team = self.teams[teamId]
    if not team then return result end
    for _, pid in ipairs(team.playerIds) do
        local p = self.players[pid]
        if p then table.insert(result, p) end
    end
    return result
end

-- 获取球队的职员列表
function GameState:getTeamStaff(teamId)
    local result = {}
    local team = self.teams[teamId]
    if not team then return result end
    for _, sid in ipairs(team.staffIds) do
        local s = self.staff[sid]
        if s then table.insert(result, s) end
    end
    return result
end

-- 发送收件箱消息
function GameState:sendMessage(msg)
    msg.id = self:generateId()
    msg.date = msg.date or {year = self.date.year, month = self.date.month, day = self.date.day}
    msg.read = false
    table.insert(self.inbox, 1, msg)  -- 新消息在前

    -- 需要弹窗的消息加入待弹窗队列（UI层消费后清除）
    if msg.popup then
        if not self._popupQueue then self._popupQueue = {} end
        table.insert(self._popupQueue, msg)
    end

    return msg
end

--- 获取并清空弹窗消息队列
function GameState:consumePopupQueue()
    local queue = self._popupQueue or {}
    self._popupQueue = {}
    return queue
end

-- 添加新闻
function GameState:addNews(article)
    article.id = self:generateId()
    article.date = article.date or {year = self.date.year, month = self.date.month, day = self.date.day}
    article.read = false
    table.insert(self.news, 1, article)
    return article
end

-- 获取未读消息数
function GameState:getUnreadCount()
    local count = 0
    for _, msg in ipairs(self.inbox) do
        if not msg.read then count = count + 1 end
    end
    return count
end

-- 日期格式化
--- 规范化日期表（JSON 反序列化后 year/month/day 可能变为字符串）
function GameState.normalizeDateTable(date)
    if type(date) ~= "table" then
        return { year = 2025, month = 8, day = 10 }
    end
    date.year = tonumber(date.year) or 2025
    date.month = tonumber(date.month) or 8
    date.day = tonumber(date.day) or 10
    return date
end

--- 读档/推进日前统一校正标量类型，避免 string.format(%d) 崩溃
function GameState:normalizeRuntimeScalars()
    self.date = GameState.normalizeDateTable(self.date)
    self.season = tonumber(self.season) or self.date.year
    self.dayOfWeek = tonumber(self.dayOfWeek) or 1

    if self.championsLeague and self.championsLeague.season then
        self.championsLeague.season = tonumber(self.championsLeague.season) or self.season
    end
    if self.europaLeague and self.europaLeague.season then
        self.europaLeague.season = tonumber(self.europaLeague.season) or self.season
    end
    if self.worldCup and self.worldCup.season then
        self.worldCup.season = tonumber(self.worldCup.season) or self.season
    end
    if self.euroCup and self.euroCup.season then
        self.euroCup.season = tonumber(self.euroCup.season) or self.season
    end
    if self.domesticCups then
        for _, cup in pairs(self.domesticCups) do
            if cup and cup.season then
                cup.season = tonumber(cup.season) or self.season
            end
        end
    end
end

function GameState:getDateString()
    return string.format("%d年%d月%d日", self.date.year, self.date.month, self.date.day)
end

-- 序列化整个状态
function GameState:serialize()
    -- 球员（跳过虚拟球员，它们是WC临时生成的）
    local players = {}
    for id, p in pairs(self.players) do
        if not p._isVirtual then
            players[tostring(id)] = p:serialize()
        end
    end
    -- 球队
    local teams = {}
    for id, t in pairs(self.teams) do
        teams[tostring(id)] = t:serialize()
    end
    -- 职员
    local staffData = {}
    for id, s in pairs(self.staff) do
        staffData[tostring(id)] = s:serialize()
    end
    -- 经理
    local managers = {}
    for id, m in pairs(self.managers) do
        managers[tostring(id)] = m:serialize()
    end

    -- 联赛序列化
    local leaguesData = {}
    for key, lg in pairs(self.leagues) do
        leaguesData[key] = lg:serialize()
    end

    -- 锦标赛序列化
    local uclData = self.championsLeague and self.championsLeague:serialize() or nil
    local uelData = self.europaLeague and self.europaLeague:serialize() or nil
    local wcData = self.worldCup and self.worldCup:serialize() or nil
    local euroData = self.euroCup and self.euroCup:serialize() or nil

    return {
        date = self.date,
        season = self.season,
        dayOfWeek = self.dayOfWeek,
        playerManagerId = self.playerManagerId,
        playerTeamId = self.playerTeamId,
        playerLeagueId = self.playerLeagueId,
        players = players,
        teams = teams,
        staff = staffData,
        managers = managers,
        leagues = leaguesData,
        championsLeague = uclData,
        europaLeague = uelData,
        worldCup = wcData,
        euroCup = euroData,
        inbox = self.inbox,
        news = self.news,
        worldHistory = self.worldHistory,
        records = self.records,
        _transferHistory = self._transferHistory,
        _managerHistory = self._managerHistory,
        _worldCupHistory = self._worldCupHistory,
        _euroHistory = self._euroHistory,
        lastPromotionRelegation = self.lastPromotionRelegation,
        transfers = require("scripts/systems/transfer_manager").copyTransfersForSave(self.transfers),
        scoutReports = self.scoutReports,
        scoutDiscoveries = self.scoutDiscoveries,
        shortlist = self.shortlist,
        nextId = self.nextId,
        turnState = self.turnState,
        currentRole = self.currentRole,
        nationalTeamCoach = self.nationalTeamCoach,
        _nationalTeamSettings = self._nationalTeamSettings,
        potentialRevealed = self.potentialRevealed or false,
        potentialRevealProgress = self.potentialRevealProgress or 0,
        -- 青训系统状态
        _youthCandidates = self._youthCandidates,
        _youthRefreshCounter = self._youthRefreshCounter,
        -- 传奇抽卡状态
        _legendGacha = self._legendGacha,
        -- 转生记录（防重复）
        _reincarnationsDone = self._reincarnationsDone,
        _reincarnationKnownSources = self._reincarnationKnownSources,
        _aiYouthRosterBootstrapped = self._aiYouthRosterBootstrapped,
        _gameStartSeason = self._gameStartSeason,
        _reincarnationFirstSeasonEnd = self._reincarnationFirstSeasonEnd,
        -- 二级联赛升降级数据
        secondDivision = self.secondDivision,
        -- UCL迁移追踪
        _uclCompletedSeasons = self._uclCompletedSeasons,
        _uclOverwritePatched = self._uclOverwritePatched,
        _uelCompletedSeasons = self._uelCompletedSeasons,
        -- 求职系统状态
        _isUnemployed = self._isUnemployed,
        _unemployedSince = self._unemployedSince,
        _pendingApplications = self._pendingApplications,
        _pendingOffers = self._pendingOffers,
        _offerCooldown = self._offerCooldown,
        _managerRenewalOffer = self._managerRenewalOffer,
        _managerRenewalOffered = self._managerRenewalOffered,
        objectives = self.objectives,
        _messageDedupeCache = self._messageDedupeCache,
        _pendingNTCoachOffers = self._pendingNTCoachOffers,
        _ntCoachHistory = self._ntCoachHistory,
        -- 存档数据消毒留痕（用于追根因：记录哪些字段曾出现非法值/稀疏数组）
        _sanitizeReports = self._sanitizeReports,
        -- 声望基准线迁移标记
        _repBaselineMigrated = self._repBaselineMigrated,
        _repBaselineV2 = self._repBaselineV2,
        _teamRelations = self._teamRelations,
        _activeLoans = self._activeLoans,
        newGameOptions = self.newGameOptions,
        settings = self.settings,
    }
end

-- 从存档恢复
function GameState:deserialize(data)
    self.date = data.date
    self.season = data.season
    self.dayOfWeek = data.dayOfWeek or 1
    self.playerManagerId = data.playerManagerId
    self.playerTeamId = data.playerTeamId
    self.playerLeagueId = data.playerLeagueId
    self.nextId = data.nextId or 1
    self.turnState = data.turnState or "idle"
    self.currentRole = data.currentRole or "club"
    self.nationalTeamCoach = data.nationalTeamCoach
    self._nationalTeamSettings = data._nationalTeamSettings
    self.inbox = data.inbox or {}
    self.news = data.news or {}
    self.worldHistory = data.worldHistory or {}
    self.records = data.records
    self._transferHistory = data._transferHistory
    self._managerHistory = data._managerHistory
    self._worldCupHistory = data._worldCupHistory
    self._euroHistory = data._euroHistory
    self.lastPromotionRelegation = data.lastPromotionRelegation
    self.transfers = data.transfers or { bids = {}, history = {}, nextBidId = 1 }
    self.scoutReports = data.scoutReports or {}
    self.scoutDiscoveries = data.scoutDiscoveries or {}

    -- 修复：shortlist 使用数字 playerId 做 key，JSON 反序列化后变字符串
    if data.shortlist then
        self.shortlist = {}
        for k, v in pairs(data.shortlist) do
            local numKey = tonumber(k)
            self.shortlist[numKey or k] = v
        end
    else
        self.shortlist = {}
    end

    -- 旧存档兼容：将 scoutReports 中混入的自动发现记录迁移到 scoutDiscoveries
    if #self.scoutReports > 0 then
        local manualReports = {}
        for _, r in ipairs(self.scoutReports) do
            if r.recommendation then
                -- 手动报告有 recommendation 字段
                table.insert(manualReports, r)
            else
                -- 自动发现记录（无 recommendation）迁移到 scoutDiscoveries
                table.insert(self.scoutDiscoveries, r)
            end
        end
        self.scoutReports = manualReports
    end

    self.potentialRevealed = data.potentialRevealed or false
    self.potentialRevealProgress = data.potentialRevealProgress or 0

    -- 青训系统状态
    self._youthCandidates = data._youthCandidates or {}
    self._youthRefreshCounter = data._youthRefreshCounter or 0
    -- 传奇抽卡状态
    self._legendGacha = data._legendGacha or nil
    -- 转生记录
    self._reincarnationsDone = data._reincarnationsDone or {}
    self._reincarnationKnownSources = data._reincarnationKnownSources or {}
    self._aiYouthRosterBootstrapped = data._aiYouthRosterBootstrapped or false
    self._gameStartSeason = data._gameStartSeason
    self._reincarnationFirstSeasonEnd = data._reincarnationFirstSeasonEnd

    -- UCL迁移追踪
    self._uclCompletedSeasons = data._uclCompletedSeasons or nil
    self._uclOverwritePatched = data._uclOverwritePatched or nil
    self._uelCompletedSeasons = data._uelCompletedSeasons or nil

    -- 求职系统状态恢复
    self._isUnemployed = data._isUnemployed or false
    self._unemployedSince = data._unemployedSince
    self._pendingApplications = data._pendingApplications or {}
    self._pendingOffers = data._pendingOffers or {}
    self._offerCooldown = data._offerCooldown or 0
    self._managerRenewalOffer = data._managerRenewalOffer
    self._managerRenewalOffered = data._managerRenewalOffered
    self.objectives = data.objectives
    self._messageDedupeCache = data._messageDedupeCache or {}
    self._pendingNTCoachOffers = data._pendingNTCoachOffers
    self._ntCoachHistory = data._ntCoachHistory or {}
    -- 存档消毒留痕（追根因用）
    self._sanitizeReports = data._sanitizeReports
    -- 声望基准线迁移标记
    self._repBaselineMigrated = data._repBaselineMigrated
    self._repBaselineV2 = data._repBaselineV2
    self._teamRelations = data._teamRelations
    self._activeLoans = data._activeLoans or {}
    self.newGameOptions = data.newGameOptions
    self.settings = data.settings

    -- 恢复二级联赛数据（升降级状态）
    if data.secondDivision then
        self.secondDivision = {}
        for leagueKey, divData in pairs(data.secondDivision) do
            self.secondDivision[leagueKey] = {
                teamIds = divData.teamIds or {},
                standings = {},
            }
            -- 归一化standings的key类型（字符串→数字）
            if divData.standings then
                for k, v in pairs(divData.standings) do
                    local numKey = tonumber(k)
                    self.secondDivision[leagueKey].standings[numKey or k] = v
                end
            end
        end
    end

    -- 恢复球员
    self.players = {}
    if data.players then
        for idStr, pData in pairs(data.players) do
            local p = Player.new(pData)
            self.players[p.id] = p
        end
    end

    -- 恢复球队
    self.teams = {}
    if data.teams then
        for idStr, tData in pairs(data.teams) do
            local t = Team.new(tData)
            self.teams[t.id] = t
        end
    end

    -- 恢复职员
    self.staff = {}
    if data.staff then
        for idStr, sData in pairs(data.staff) do
            local s = Staff.new(sData)
            self.staff[s.id] = s
        end
    end

    -- 恢复经理
    self.managers = {}
    if data.managers then
        for idStr, mData in pairs(data.managers) do
            local m = Manager.new(mData)
            self.managers[m.id] = m
        end
    end

    -- 旧存档兼容：如果 _isUnemployed 未显式保存但经理实际无球队，推断为失业状态
    if not data._isUnemployed and self.playerManagerId and self.managers[self.playerManagerId] then
        local mgr = self.managers[self.playerManagerId]
        if mgr.teamId == nil and self.playerTeamId == nil then
            self._isUnemployed = true
            self._unemployedSince = self._unemployedSince or {
                year = self.date.year, month = self.date.month, day = self.date.day
            }
            print("[SaveMigration] Inferred unemployment status for player manager")
        end
    end

    local JobManager = require("scripts/systems/job_manager")
    JobManager.syncJobSeekingState(self)

    -- 恢复联赛（多联赛）
    self.leagues = {}
    if data.leagues then
        for key, lgData in pairs(data.leagues) do
            self.leagues[key] = League.new(lgData)
        end
    elseif data.league then
        -- 兼容旧存档（单联赛）
        self.leagues["legacy"] = League.new(data.league)
        self.playerLeagueId = self.playerLeagueId or "legacy"
    end

    -- 恢复玩家联赛快捷引用
    if self.playerLeagueId and self.leagues[self.playerLeagueId] then
        self.league = self.leagues[self.playerLeagueId]
    else
        -- 尝试查找玩家球队所在联赛
        for key, lg in pairs(self.leagues) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == self.playerTeamId then
                    self.league = lg
                    self.playerLeagueId = key
                    break
                end
            end
            if self.league then break end
        end
    end

    -- 恢复欧冠
    self.championsLeague = nil
    if data.championsLeague then
        self.championsLeague = Tournament.new(data.championsLeague)
    end

    -- 恢复欧联杯
    self.europaLeague = nil
    if data.europaLeague then
        self.europaLeague = Tournament.new(data.europaLeague)
    end

    -- 恢复世界杯
    self.worldCup = nil
    if data.worldCup then
        self.worldCup = Tournament.new(data.worldCup)
    end

    -- 恢复欧洲杯
    self.euroCup = nil
    if data.euroCup then
        self.euroCup = Tournament.new(data.euroCup)
    end

    -- 迁移：验证并修复联赛积分榜一致性
    -- 旧版本存在 bug：读档后 standings 的 key 变为字符串，导致 updateStanding 静默失败
    -- 如果玩家在有 bug 的版本中继续游戏并存档，standings 会与 fixtures 不一致
    -- 此处从已完成的 fixtures 重建积分榜，确保数据正确
    for _, lg in pairs(self.leagues) do
        if lg.fixtures and #lg.fixtures > 0 then
            -- 统计 fixtures 中已完成比赛的实际总场次
            local finishedCount = 0
            for _, f in ipairs(lg.fixtures) do
                if f.status == "finished" then
                    finishedCount = finishedCount + 1
                end
            end

            -- 统计当前 standings 中记录的总场次
            local standingsPlayed = 0
            for _, s in pairs(lg.standings) do
                standingsPlayed = standingsPlayed + s.played
            end
            -- 每场比赛贡献 2 次 played（主+客各 +1）
            local expectedPlayed = finishedCount * 2

            -- 如果不一致，说明积分榜与联赛赛程不同步（含杯赛误计分、重复计分等），需要重建
            if standingsPlayed ~= expectedPlayed then
                -- 重建：先清零 standings，再从 fixtures 逐场重算
                for _, tid in ipairs(lg.teamIds) do
                    lg.standings[tid] = {
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
                for _, f in ipairs(lg.fixtures) do
                    if f.status == "finished" then
                        lg:updateStanding(f)
                    end
                end
                print("[SaveMigration] Rebuilt standings for league: " .. (lg.name or "unknown"))
            end
        end
    end

    -- 迁移：验证并修复欧冠/世界杯联赛阶段积分榜一致性
    local tournaments = {}
    if self.championsLeague then table.insert(tournaments, self.championsLeague) end
    if self.europaLeague then table.insert(tournaments, self.europaLeague) end
    if self.worldCup then table.insert(tournaments, self.worldCup) end
    if self.euroCup then table.insert(tournaments, self.euroCup) end
    for _, tourney in ipairs(tournaments) do
        -- 联赛阶段（瑞士制）
        local lp = tourney.leaguePhase
        if lp and lp.fixtures and #lp.fixtures > 0 and lp.standings then
            local finishedCount = 0
            for _, f in ipairs(lp.fixtures) do
                if f.status == "finished" then finishedCount = finishedCount + 1 end
            end
            local standingsPlayed = 0
            for _, s in pairs(lp.standings) do
                standingsPlayed = standingsPlayed + s.played
            end
            if finishedCount * 2 > 0 and standingsPlayed ~= finishedCount * 2 then
                for tid, s in pairs(lp.standings) do
                    s.played = 0; s.wins = 0; s.draws = 0; s.losses = 0
                    s.goalsFor = 0; s.goalsAgainst = 0; s.goalDifference = 0; s.points = 0
                end
                for _, f in ipairs(lp.fixtures) do
                    if f.status == "finished" then
                        tourney:updateLeagueStanding(f)
                    end
                end
                print("[SaveMigration] Rebuilt leaguePhase standings for: " .. (tourney.name or "unknown"))
            end
        end
        -- 小组赛
        if tourney.groups then
            for groupName, group in pairs(tourney.groups) do
                if group.fixtures and #group.fixtures > 0 and group.standings then
                    local finishedCount = 0
                    for _, f in ipairs(group.fixtures) do
                        if f.status == "finished" then finishedCount = finishedCount + 1 end
                    end
                    local standingsPlayed = 0
                    for _, s in pairs(group.standings) do
                        standingsPlayed = standingsPlayed + s.played
                    end
                    if finishedCount * 2 > 0 and standingsPlayed ~= finishedCount * 2 then
                        for tid, s in pairs(group.standings) do
                            s.played = 0; s.wins = 0; s.draws = 0; s.losses = 0
                            s.goalsFor = 0; s.goalsAgainst = 0; s.goalDifference = 0; s.points = 0
                        end
                        for _, f in ipairs(group.fixtures) do
                            if f.status == "finished" then
                                tourney:updateGroupStanding(groupName, f)
                            end
                        end
                        print("[SaveMigration] Rebuilt group " .. groupName .. " standings for: " .. (tourney.name or "unknown"))
                    end
                end
            end
        end
    end

    -- 从积分榜同步各球队的 leaguePosition（转播/赞助公式依赖此字段）
    for _, lg in pairs(self.leagues) do
        lg:syncTeamPositions(self)
    end
    self:rebuildTeamLeagueIndex()

    -- 记录系统：确保结构完整，旧存档从 worldHistory / UCL / 世界杯历史回溯
    local RecordsManager = require("scripts/systems/records_manager")
    RecordsManager._ensureData(self)
    RecordsManager.migrateFromHistory(self)
    RecordsManager.syncManagerProfile(self)

    -- 历史子系统缓冲结构
    local HistoryManager = require("scripts/systems/history_manager")
    HistoryManager._ensureData(self)

    -- 旧存档兼容：赛季进行中但 objectives 丢失时自动补全（须在联赛/球队恢复之后）
    if not self.objectives and self.league and (self.league.currentRound or 0) > 0 then
        local ObjectivesManager = require("scripts/systems/objectives_manager")
        ObjectivesManager.initSeason(self)
    end

    -- 已接受国家队邀请则不应再阻断
    if self.nationalTeamCoach and self._pendingNTCoachOffers then
        self._pendingNTCoachOffers = nil
    end

    -- 旧存档：死敌关系未初始化时补全
    local TeamRivalries = require("scripts/data/team_rivalries")
    TeamRivalries.initializeIfNeeded(self)

    self:normalizePlayerDynamicState()
    self:normalizeRuntimeScalars()
end

--- 读档后校正球员动态状态（体力/士气/长期体能），兼容旧档缺字段或 JSON 字符串数值
function GameState:normalizePlayerDynamicState()
    for _, p in pairs(self.players or {}) do
        Player.normalizeDynamicState(p)
    end
end

-- 获取玩家所在联赛
function GameState:getPlayerLeague()
    return self.league
end

-- 获取所有联赛列表 {key, league} 有序
function GameState:getAllLeagues()
    local result = {}
    for key, lg in pairs(self.leagues) do
        table.insert(result, {key = key, league = lg})
    end
    table.sort(result, function(a, b) return a.key < b.key end)
    return result
end

--- 重建 teamId -> { key, league } 运行时索引（不入档）
function GameState:rebuildTeamLeagueIndex()
    local index = {}
    for key, lg in pairs(self.leagues or {}) do
        for _, tid in ipairs(lg.teamIds or {}) do
            index[tid] = { key = key, league = lg }
        end
    end
    self._teamLeagueIndex = index
    return index
end

function GameState:invalidateTeamLeagueIndex()
    self._teamLeagueIndex = nil
end

--- 查找球队所在联赛（O(1) 索引，降级/动态加载后需 rebuildTeamLeagueIndex）
function GameState:getTeamLeague(teamId)
    if not teamId then return nil, nil end
    local index = self._teamLeagueIndex
    if not index then
        index = self:rebuildTeamLeagueIndex()
    end
    local entry = index[teamId]
    if entry then
        return entry.league, entry.key
    end
    return nil, nil
end

return GameState
