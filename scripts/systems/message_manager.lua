-- systems/message_manager.lua
-- 统一消息系统：模板化消息生成、去重、优先级管理、动作按钮

local EventBus = require("scripts/app/event_bus")

local MessageManager = {}

------------------------------------------------------
-- 优先级工具（inbox / dashboard 共用）
------------------------------------------------------

local PRIORITY_RANK = { critical = 4, high = 3, normal = 2, low = 1 }

function MessageManager.priorityRank(priority)
    return PRIORITY_RANK[priority] or 2
end

function MessageManager.isUrgent(priority)
    return priority == "high" or priority == "critical"
end

------------------------------------------------------
-- 消息模板定义
------------------------------------------------------
local TEMPLATES = {
    -- 财务类
    finance_warning = {
        category = "finance",
        title = "财务警告",
        priority = "high",
        format = "球队资金紧张！当前余额 %s，仅够支付约 %d 周薪资。请考虑出售球员或削减开支。",
    },
    finance_crisis = {
        category = "finance",
        title = "财务危机",
        priority = "high",
        format = "球队已经入不敷出！当前负债 %s。董事会要求立即采取措施削减开支。",
    },
    finance_prize = {
        category = "finance",
        title = "赛季奖金",
        priority = "normal",
        format = "恭喜！球队以第%d名完赛，获得奖金 %s。",
    },

    -- 合同类
    contract_expiring_6m = {
        category = "contract",
        title = "合同到期提醒",
        priority = "normal",
        format = "%s 的合同将在6个月内到期，请考虑续约事宜。",
    },
    contract_expiring_3m = {
        category = "contract",
        title = "合同即将到期",
        priority = "high",
        format = "%s 的合同将在3个月内到期！若不续约，球员将自由离队。",
    },
    contract_expired = {
        category = "contract",
        title = "球员离队",
        priority = "normal",
        format = "%s 合同到期后未续约，已自由离队。",
    },
    contract_renewed = {
        category = "contract",
        title = "续约成功",
        priority = "normal",
        format = "%s 已同意续约 %d 年，新周薪 %s。",
    },
    contract_rejected = {
        category = "contract",
        title = "续约失败",
        priority = "high",
        format = "%s 拒绝了续约邀请。原因：%s",
    },

    -- 训练类
    training_growth = {
        category = "training",
        title = "训练提升",
        priority = "low",
        format = "%s 在训练中 %s 能力提升了 %d 点。",
    },
    training_injury = {
        category = "injury",
        title = "训练伤病",
        priority = "high",
        format = "%s 在训练中受伤（%s · %s），预计 %d 天恢复。",
    },

    -- 伤病类
    injury_recovered = {
        category = "injury",
        title = "伤愈复出",
        priority = "normal",
        format = "%s 已经伤愈，可以参加比赛。",
    },
    injury_season_ending = {
        category = "injury",
        title = "赛季报销",
        priority = "high",
        format = "%s 遭遇严重伤病（%s），本赛季无法复出，预计 %d 天后恢复。",
    },

    -- 转会类
    transfer_bid_received = {
        category = "transfer",
        title = "收到报价",
        priority = "high",
        format = "%s 对 %s 提出了 %s 的报价。",
    },
    transfer_completed = {
        category = "transfer",
        title = "转会完成",
        priority = "normal",
        format = "%s 已正式加盟 %s，转会费 %s。",
    },

    -- 比赛类
    match_result = {
        category = "match_result",
        title = "比赛结果",
        priority = "normal",
        format = "%s %d - %d %s",
    },
    match_preview = {
        category = "match_preview",
        title = "赛前预告",
        priority = "normal",
        format = "明天将%s对阵 %s (联赛第%d)。",
    },

    -- 球探类
    scout_report = {
        category = "scout",
        title = "球探报告",
        priority = "normal",
        format = "球探发现了 %s (%s, %d岁)，综合能力 %d，建议关注。",
    },
    scout_report_ready = {
        category = "scout",
        title = "球探报告完成",
        priority = "normal",
        format = "%s · %s",
    },

    -- 青训类
    youth_signed = {
        category = "youth",
        title = "青训签约",
        priority = "normal",
        format = "青训球员 %s (%s) 已签约加入青训队。",
    },
    youth_promoted = {
        category = "youth",
        title = "青训提拔",
        priority = "normal",
        format = "%s 已从青训队提拔至一线队。",
    },
    youth_demoted = {
        category = "youth",
        title = "下放青训",
        priority = "normal",
        format = "%s 已从一线队下放至青训队。",
    },

    -- 董事会类
    board_objective = {
        category = "board",
        title = "董事会目标",
        priority = "normal",
        format = "董事会设定了新赛季目标：%s。",
    },
    board_warning = {
        category = "board",
        title = "董事会警告",
        priority = "high",
        format = "董事会对球队近期表现不满：%s。",
    },
}

------------------------------------------------------
-- 去重缓存（持久化到 gameState._messageDedupeCache，防止读档后重复发消息）
------------------------------------------------------
local DEDUPE_WINDOW_DAYS = 7  -- 7天内同模板+key不重复

local function getDedupeCache(gameState)
    gameState._messageDedupeCache = gameState._messageDedupeCache or {}
    return gameState._messageDedupeCache
end

------------------------------------------------------
-- 核心API
------------------------------------------------------

--- 使用模板发送消息
---@param gameState table
---@param templateId string 模板ID
---@param args table 格式化参数数组
---@param opts? table 额外选项 {dedupeKey?, permanent?, actions?, extra?}
---@return table|nil 发送的消息，若被去重则返回nil
function MessageManager.send(gameState, templateId, args, opts)
    local tmpl = TEMPLATES[templateId]
    if not tmpl then
        -- 回退：无模板时直接发送
        return MessageManager.sendRaw(gameState, {
            category = "system",
            title = templateId,
            body = tostring(args[1] or ""),
            priority = "normal",
        })
    end

    opts = opts or {}

    -- 去重检查
    local dedupeKey = opts.dedupeKey or (templateId .. "_" .. tostring(args[1] or ""))
    if MessageManager._isDuplicate(gameState, dedupeKey, opts.permanent) then
        return nil
    end

    -- 格式化消息体（读档后数值字段偶发为字符串，先尝试原样再 coerce）
    local body
    local okFmt = pcall(function()
        body = string.format(tmpl.format, table.unpack(args))
    end)
    if not okFmt then
        local coerced = {}
        for i, v in ipairs(args) do
            if type(v) == "string" then
                coerced[i] = tonumber(v) or v
            else
                coerced[i] = v
            end
        end
        body = string.format(tmpl.format, table.unpack(coerced))
    end

    local msg = {
        category = tmpl.category,
        title = opts.title or tmpl.title,
        body = body,
        priority = opts.priority or tmpl.priority,
        templateId = templateId,
        actions = opts.actions,  -- 动作按钮列表
        extra = opts.extra,      -- 额外数据
    }

    -- 记录去重
    MessageManager._markSent(gameState, dedupeKey, opts.permanent)

    return gameState:sendMessage(msg)
end

--- 发送原始消息（不使用模板）
---@param gameState table
---@param msg table {category, title, body, priority, actions?, extra?}
---@return table
function MessageManager.sendRaw(gameState, msg)
    return gameState:sendMessage(msg)
end

--- 发送带动作按钮的消息
---@param gameState table
---@param templateId string
---@param args table
---@param actions table[] 动作列表 {{label, actionId, data?}, ...}
---@return table|nil
function MessageManager.sendWithActions(gameState, templateId, args, actions)
    return MessageManager.send(gameState, templateId, args, { actions = actions })
end

------------------------------------------------------
-- 批量消息（汇总）
------------------------------------------------------

--- 生成训练周报（汇总多个小提升为一条消息）
---@param gameState table
---@param growthList table[] {{playerName, attr, amount}, ...}
function MessageManager.sendTrainingWeeklySummary(gameState, growthList)
    if #growthList == 0 then return end

    local lines = {}
    for i, g in ipairs(growthList) do
        if i <= 5 then  -- 最多显示5条
            table.insert(lines, string.format("  · %s: %s +%d", g.playerName, g.attr, g.amount))
        end
    end
    if #growthList > 5 then
        table.insert(lines, string.format("  ... 以及其他 %d 名球员有所提升", #growthList - 5))
    end

    gameState:sendMessage({
        category = "training",
        title = "本周训练报告",
        body = "本周训练成果：\n" .. table.concat(lines, "\n"),
        priority = "low",
    })
end

--- 生成合同到期汇总
---@param gameState table
---@param expiringPlayers table[] {{name, monthsLeft}, ...}
function MessageManager.sendContractExpirySummary(gameState, expiringPlayers)
    if #expiringPlayers == 0 then return end

    local lines = {}
    for _, p in ipairs(expiringPlayers) do
        table.insert(lines, string.format("  · %s (%d个月后到期)", p.name, p.monthsLeft))
    end

    gameState:sendMessage({
        category = "contract",
        title = "合同到期概览",
        body = "以下球员合同即将到期：\n" .. table.concat(lines, "\n"),
        priority = "normal",
    })
end

------------------------------------------------------
-- 消息管理
------------------------------------------------------

--- 标记消息已读
function MessageManager.markRead(gameState, messageId)
    for _, msg in ipairs(gameState.inbox) do
        if msg.id == messageId then
            msg.read = true
            return true
        end
    end
    return false
end

--- 标记所有消息已读
function MessageManager.markAllRead(gameState)
    for _, msg in ipairs(gameState.inbox) do
        msg.read = true
    end
end

--- 删除与消息绑定的待办状态（避免删信后时间推进仍被阻断）
local function clearLinkedPendingState(gameState, msg)
    local pending = gameState._pendingNTCoachOffers
    if pending and pending.inviteMessageId == msg.id then
        gameState.nationalTeamCoach = nil
        local WorldCup = require("scripts/systems/world_cup")
        WorldCup.clearPendingCoachInvite(gameState)
        return
    end
    if msg.actions then
        for _, act in ipairs(msg.actions) do
            if act.actionId == "accept_nt_coach" or act.actionId == "decline_nt_coach" then
                gameState.nationalTeamCoach = nil
                local WorldCup = require("scripts/systems/world_cup")
                WorldCup.clearPendingCoachInvite(gameState)
                return
            end
        end
    end
end

--- 删除消息
function MessageManager.deleteMessage(gameState, messageId)
    for i, msg in ipairs(gameState.inbox) do
        if msg.id == messageId then
            clearLinkedPendingState(gameState, msg)
            table.remove(gameState.inbox, i)
            return true
        end
    end
    return false
end

--- 按分类获取消息
function MessageManager.getByCategory(gameState, category, limit)
    limit = limit or 20
    local result = {}
    for _, msg in ipairs(gameState.inbox) do
        if msg.category == category then
            table.insert(result, msg)
            if #result >= limit then break end
        end
    end
    return result
end

--- 获取未读数量（按分类）
function MessageManager.getUnreadByCategory(gameState)
    local counts = {}
    for _, msg in ipairs(gameState.inbox) do
        if not msg.read then
            local cat = msg.category or "other"
            counts[cat] = (counts[cat] or 0) + 1
        end
    end
    return counts
end

--- 清理旧消息（保留最近N条）
function MessageManager.cleanup(gameState, maxCount)
    maxCount = maxCount or 100
    local inbox = gameState.inbox
    if #inbox > maxCount then
        local trimmed = {}
        for i = 1, maxCount do
            trimmed[i] = inbox[i]
        end
        gameState.inbox = trimmed
    end
end

------------------------------------------------------
-- 去重内部实现
------------------------------------------------------

function MessageManager._isDuplicate(gameState, key, permanent)
    local cache = getDedupeCache(gameState)
    local entry = cache[key]
    if not entry then return false end
    if permanent or entry.permanent then return true end
    -- 检查是否在窗口期内
    local daysDiff = MessageManager._daysBetween(entry.date, gameState.date)
    return daysDiff < DEDUPE_WINDOW_DAYS
end

function MessageManager._markSent(gameState, key, permanent)
    local cache = getDedupeCache(gameState)
    cache[key] = {
        date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day},
        permanent = permanent or false,
    }
end

--- 清理过期的去重缓存
function MessageManager.cleanupDedupeCache(gameState)
    local cache = getDedupeCache(gameState)
    local toRemove = {}
    for key, entry in pairs(cache) do
        if MessageManager._daysBetween(entry.date, gameState.date) >= DEDUPE_WINDOW_DAYS then
            table.insert(toRemove, key)
        end
    end
    for _, key in ipairs(toRemove) do
        cache[key] = nil
    end
end

--- 简化的日期差计算（粗略）
function MessageManager._daysBetween(date1, date2)
    local d1 = date1.year * 365 + date1.month * 30 + date1.day
    local d2 = date2.year * 365 + date2.month * 30 + date2.day
    return math.abs(d2 - d1)
end

------------------------------------------------------
-- 重置（新赛季时清理内存中的旧引用；实际缓存随 gameState 存档）
------------------------------------------------------
function MessageManager.reset(gameState)
    if gameState then
        gameState._messageDedupeCache = {}
    end
end

return MessageManager
