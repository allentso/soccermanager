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
    self.worldCup = nil         -- 世界杯 Tournament 实例

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

    -- 下一个可用ID
    self.nextId = 1

    -- 回合状态
    self.turnState = "idle"  -- idle, processing, match_day

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
    return msg
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
function GameState:getDateString()
    return string.format("%d年%d月%d日", self.date.year, self.date.month, self.date.day)
end

-- 序列化整个状态
function GameState:serialize()
    -- 球员
    local players = {}
    for id, p in pairs(self.players) do
        players[tostring(id)] = p:serialize()
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
    local wcData = self.worldCup and self.worldCup:serialize() or nil

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
        worldCup = wcData,
        inbox = self.inbox,
        news = self.news,
        worldHistory = self.worldHistory,
        transfers = self.transfers,
        scoutReports = self.scoutReports,
        nextId = self.nextId,
        turnState = self.turnState,
        potentialRevealed = self.potentialRevealed or false,
        potentialRevealProgress = self.potentialRevealProgress or 0,
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
    self.inbox = data.inbox or {}
    self.news = data.news or {}
    self.worldHistory = data.worldHistory or {}
    self.transfers = data.transfers or { bids = {}, history = {}, nextBidId = 1 }
    self.scoutReports = data.scoutReports or {}
    self.potentialRevealed = data.potentialRevealed or false
    self.potentialRevealProgress = data.potentialRevealProgress or 0

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

    -- 恢复世界杯
    self.worldCup = nil
    if data.worldCup then
        self.worldCup = Tournament.new(data.worldCup)
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

-- 查找球队所在联赛
function GameState:getTeamLeague(teamId)
    for key, lg in pairs(self.leagues) do
        for _, tid in ipairs(lg.teamIds) do
            if tid == teamId then return lg, key end
        end
    end
    return nil, nil
end

return GameState
