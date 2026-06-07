-- domain/manager.lua
-- 经理数据模型

local Manager = {}
Manager.__index = Manager

function Manager.new(data)
    local self = setmetatable({}, Manager)
    self.id = data.id or 0
    self.firstName = data.firstName or ""
    self.lastName = data.lastName or ""
    self.displayName = data.displayName or (self.firstName .. " " .. self.lastName)
    self.birthYear = data.birthYear or 1985
    self.nationality = data.nationality or "ENG"
    self.teamId = data.teamId or nil
    self.isPlayer = data.isPlayer or false  -- 是否为玩家控制
    self.reputation = data.reputation or 30

    -- 执教统计
    self.stats = data.stats or {
        wins = 0,
        draws = 0,
        losses = 0,
        trophies = 0,
    }

    -- 执教履历
    self.career = data.career or {}

    return self
end

function Manager:addCareerEntry(teamId, teamName, startYear, endYear, stats)
    table.insert(self.career, {
        teamId = teamId,
        teamName = teamName,
        startYear = startYear,
        endYear = endYear,
        stats = stats or {}
    })
end

function Manager:serialize()
    return {
        id = self.id,
        firstName = self.firstName,
        lastName = self.lastName,
        displayName = self.displayName,
        birthYear = self.birthYear,
        nationality = self.nationality,
        teamId = self.teamId,
        isPlayer = self.isPlayer,
        reputation = self.reputation,
        stats = self.stats,
        career = self.career,
    }
end

return Manager
