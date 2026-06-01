-- systems/random_event_manager.lua
-- 随机事件系统：事件池定义、概率触发、玩家交互响应

local MessageManager = require("scripts/systems/message_manager")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local RandomEventManager = {}

------------------------------------------------------
-- 事件池定义
------------------------------------------------------
local EVENT_POOL = {
    -- 伤病类
    {
        id = "training_injury",
        category = "injury",
        weight = 15,
        title = "训练伤病",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local eligible = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gs.players[pid]
                if p and not p.injured and not p.retired then
                    table.insert(eligible, p)
                end
            end
            if #eligible == 0 then return nil end
            local p = eligible[math.random(1, #eligible)]
            local days = math.random(3, 21)
            p.injured = true
            p.injuryDays = days
            p.injuryType = RandomEventManager._randomInjury()
            return {
                title = "训练伤病",
                body = string.format("%s 在训练中受伤(%s)，预计 %d 天恢复。",
                    p.displayName, p.injuryType, days),
                priority = "high",
            }
        end,
    },

    -- 财务类
    {
        id = "sponsor_bonus",
        category = "finance",
        weight = 8,
        title = "赞助商奖金",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local amount = math.random(5, 20) * 10000
            team.balance = team.balance + amount
            team.seasonIncome = (team.seasonIncome or 0) + amount
            return {
                title = "赞助商奖金",
                body = string.format("赞助商因球队良好表现额外奖励 %d万！", amount / 10000),
                priority = "normal",
            }
        end,
    },
    {
        id = "stadium_repair",
        category = "finance",
        weight = 6,
        title = "球场维修",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local cost = math.random(2, 8) * 10000
            team.balance = team.balance - cost
            team.seasonExpense = (team.seasonExpense or 0) + cost
            return {
                title = "球场维修",
                body = string.format("球场设施需要紧急维修，花费 %d万。", cost / 10000),
                priority = "normal",
            }
        end,
    },

    -- 士气类
    {
        id = "team_bonding",
        category = "morale",
        weight = 10,
        title = "团建活动",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            for _, pid in ipairs(team.playerIds) do
                local p = gs.players[pid]
                if p then
                    p.morale = Constants.clampMorale((p.morale or 60) + math.random(3, 8))
                end
            end
            return {
                title = "团建活动",
                body = "球队组织了一次团建活动，全队士气有所提升！",
                priority = "normal",
            }
        end,
    },
    {
        id = "dressing_room_conflict",
        category = "morale",
        weight = 7,
        title = "更衣室矛盾",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local eligible = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gs.players[pid]
                if p and not p.retired then table.insert(eligible, p) end
            end
            if #eligible < 2 then return nil end
            local p1 = eligible[math.random(1, #eligible)]
            local p2 = eligible[math.random(1, #eligible)]
            while p2.id == p1.id do
                p2 = eligible[math.random(1, #eligible)]
            end
            p1.morale = Constants.clampMorale((p1.morale or 60) - math.random(5, 12))
            p2.morale = Constants.clampMorale((p2.morale or 60) - math.random(5, 12))
            return {
                title = "更衣室矛盾",
                body = string.format("%s 和 %s 在更衣室发生了冲突，双方士气下降。",
                    p1.displayName, p2.displayName),
                priority = "normal",
            }
        end,
    },

    -- 球员发展类
    {
        id = "breakthrough_growth",
        category = "training",
        weight = 5,
        title = "突破成长",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local eligible = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gs.players[pid]
                if p and not p.retired then
                    local age = (p.birthYear and (gs.date.year - p.birthYear)) or 25
                    if age <= 23 and p.attributes then
                        table.insert(eligible, p)
                    end
                end
            end
            if #eligible == 0 then return nil end
            local p = eligible[math.random(1, #eligible)]
            -- 随机属性大幅提升
            local attrs = {}
            for k, _ in pairs(p.attributes) do table.insert(attrs, k) end
            if #attrs == 0 then return nil end
            local key = attrs[math.random(1, #attrs)]
            local boost = math.random(2, 3)
            p.attributes[key] = math.min(20, p.attributes[key] + boost)
            if p.calculateOverall then p:calculateOverall() end
            return {
                title = "突破成长",
                body = string.format("%s 在训练中表现突出，%s 属性显著提升！",
                    p.displayName, key),
                priority = "normal",
            }
        end,
    },

    -- 转会类
    {
        id = "transfer_interest",
        category = "transfer",
        weight = 8,
        title = "外部报价兴趣",
        condition = function(gs) return gs.playerTeamId ~= nil end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            local eligible = {}
            for _, pid in ipairs(team.playerIds) do
                local p = gs.players[pid]
                if p and not p.retired and (p.overall or 0) >= 65 then
                    table.insert(eligible, p)
                end
            end
            if #eligible == 0 then return nil end
            local p = eligible[math.random(1, #eligible)]
            return {
                title = "转会传闻",
                body = string.format("有球队对 %s 表示了兴趣，可能会收到正式报价。",
                    p.displayName),
                priority = "normal",
            }
        end,
    },

    -- 媒体/声望类
    {
        id = "media_praise",
        category = "media",
        weight = 6,
        title = "媒体赞誉",
        condition = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return false end
            local form = team.recentForm or {}
            local wins = 0
            for _, r in ipairs(form) do if r == "W" then wins = wins + 1 end end
            return wins >= 3
        end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            team.reputation = math.min(99, (team.reputation or 50) + 1)
            return {
                title = "媒体赞誉",
                body = "球队近期出色的表现引起了媒体关注，获得了积极的报道。声望小幅提升！",
                priority = "normal",
            }
        end,
    },
    {
        id = "media_criticism",
        category = "media",
        weight = 6,
        title = "媒体批评",
        condition = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return false end
            local form = team.recentForm or {}
            local losses = 0
            for _, r in ipairs(form) do if r == "L" then losses = losses + 1 end end
            return losses >= 3
        end,
        execute = function(gs)
            local team = gs:getPlayerTeam()
            if not team then return nil end
            team.reputation = math.max(1, (team.reputation or 50) - 1)
            return {
                title = "媒体批评",
                body = "球队近期糟糕的表现受到了媒体的猛烈批评。球队形象受损。",
                priority = "normal",
            }
        end,
    },
}

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 每日触发判定（建议每天调用一次）
---@param gameState table
function RandomEventManager.processDaily(gameState)
    -- 每天有约 8% 概率触发一个事件
    if math.random() > 0.08 then return end

    -- 筛选满足条件的事件
    local eligible = {}
    local totalWeight = 0
    for _, event in ipairs(EVENT_POOL) do
        if event.condition(gameState) then
            table.insert(eligible, event)
            totalWeight = totalWeight + event.weight
        end
    end
    if #eligible == 0 then return end

    -- 加权随机选择
    local roll = math.random() * totalWeight
    local accumulated = 0
    local selectedEvent = eligible[1]
    for _, event in ipairs(eligible) do
        accumulated = accumulated + event.weight
        if roll <= accumulated then
            selectedEvent = event
            break
        end
    end

    -- 防止同类事件短时间内重复
    gameState._lastEventIds = gameState._lastEventIds or {}
    for _, recentId in ipairs(gameState._lastEventIds) do
        if recentId == selectedEvent.id then return end
    end

    -- 执行事件
    local result = selectedEvent.execute(gameState)
    if result then
        -- 发送消息
        gameState:sendMessage({
            category = selectedEvent.category,
            title = result.title,
            body = result.body,
            priority = result.priority or "normal",
        })

        -- 记录最近事件（防重复，保留5个）
        table.insert(gameState._lastEventIds, selectedEvent.id)
        if #gameState._lastEventIds > 5 then
            table.remove(gameState._lastEventIds, 1)
        end

        EventBus.emit("random_event", {eventId = selectedEvent.id, category = selectedEvent.category})
    end
end

------------------------------------------------------
-- 辅助
------------------------------------------------------

function RandomEventManager._randomInjury()
    local injuries = {
        "肌肉拉伤", "膝盖扭伤", "脚踝受伤", "腿筋拉伤",
        "背部不适", "肩部脱臼", "脚趾骨裂", "小腿拉伤",
    }
    return injuries[math.random(1, #injuries)]
end

return RandomEventManager
