-- domain/staff.lua
-- 职员数据模型

local Constants = require("scripts/app/constants")

local Staff = {}
Staff.__index = Staff

function Staff.new(data)
    local self = setmetatable({}, Staff)
    self.id = data.id or 0
    self.firstName = data.firstName or ""
    self.lastName = data.lastName or ""
    self.displayName = data.displayName or (self.firstName .. " " .. self.lastName)
    self.nationality = data.nationality or "ENG"
    self.birthYear = data.birthYear or 1975
    self.role = data.role or Constants.STAFF_ROLES.COACH
    self.teamId = data.teamId or nil
    self.wage = data.wage or 5000

    -- 属性 (1-20)
    local attrs = data.attributes or {}
    self.attributes = {
        training = attrs.training or 10,
        tactical = attrs.tactical or 10,
        scouting = attrs.scouting or 10,
        physiotherapy = attrs.physiotherapy or 10,
        youthDev = attrs.youthDev or 10,
    }

    return self
end

function Staff:getRoleName()
    return Constants.STAFF_ROLE_NAMES[self.role] or self.role
end

function Staff:serialize()
    return {
        id = self.id,
        firstName = self.firstName,
        lastName = self.lastName,
        displayName = self.displayName,
        nationality = self.nationality,
        birthYear = self.birthYear,
        role = self.role,
        teamId = self.teamId,
        wage = self.wage,
        attributes = self.attributes,
    }
end

return Staff
