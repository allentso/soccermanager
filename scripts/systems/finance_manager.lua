-- systems/finance_manager.lua
-- 财务流转系统：工资扣除、转会费入账/出账、奖金发放、流水记录

local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local FinanceManager = {}

------------------------------------------------------
-- 每周处理：扣除所有球队的周薪
------------------------------------------------------
function FinanceManager.processWeeklyWages(gameState)
    for teamId, team in pairs(gameState.teams) do
        local totalPlayerWage = 0
        local totalStaffWage = 0

        -- 球员薪资
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p then
                totalPlayerWage = totalPlayerWage + (p.wage or 0)
            end
        end

        -- 职员薪资
        for _, sid in ipairs(team.staffIds or {}) do
            local s = gameState.staff[sid]
            if s then
                totalStaffWage = totalStaffWage + (s.wage or 0)
            end
        end

        local totalWage = totalPlayerWage + totalStaffWage

        if totalWage > 0 then
            -- 扣除工资
            team.balance = team.balance - totalWage
            team.seasonExpense = (team.seasonExpense or 0) + totalWage

            -- 记录流水
            FinanceManager.addTransaction(team, {
                amount = -totalWage,
                description = "周薪支出",
                category = "wage",
                season = gameState.season,
                week = FinanceManager._getWeekNumber(gameState),
            })

            -- 玩家球队：检查财务告警
            if teamId == gameState.playerTeamId then
                -- 余额不足4周工资警告
                if team.balance < totalWage * 4 and team.balance > 0 then
                    gameState:sendMessage({
                        category = "finance",
                        title = "财务警告",
                        body = string.format(
                            "球队资金紧张！当前余额 %s，仅够支付约 %d 周薪资。请考虑出售球员或削减开支。",
                            FinanceManager.formatMoney(team.balance),
                            math.floor(team.balance / totalWage)
                        ),
                        priority = "high",
                    })
                end
                -- 余额为负
                if team.balance < 0 then
                    gameState:sendMessage({
                        category = "finance",
                        title = "财务危机",
                        body = string.format(
                            "球队已经入不敷出！当前负债 %s。董事会要求立即采取措施削减开支。",
                            FinanceManager.formatMoney(math.abs(team.balance))
                        ),
                        priority = "high",
                    })
                end
            end
        end
    end
end

------------------------------------------------------
-- 转会费入账
------------------------------------------------------
function FinanceManager.processTransferIn(gameState, teamId, amount, playerName)
    local team = gameState.teams[teamId]
    if not team then return end

    team.balance = team.balance + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount

    FinanceManager.addTransaction(team, {
        amount = amount,
        description = "出售球员: " .. (playerName or "未知"),
        category = "transfer",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })
end

------------------------------------------------------
-- 转会费出账
------------------------------------------------------
function FinanceManager.processTransferOut(gameState, teamId, amount, playerName)
    local team = gameState.teams[teamId]
    if not team then return end

    team.balance = team.balance - amount
    team.seasonExpense = (team.seasonExpense or 0) + amount
    team.transferBudget = math.max(0, (team.transferBudget or 0) - amount)

    FinanceManager.addTransaction(team, {
        amount = -amount,
        description = "购入球员: " .. (playerName or "未知"),
        category = "transfer",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })
end

------------------------------------------------------
-- 比赛日收入（票房）
------------------------------------------------------
function FinanceManager.processMatchDayRevenue(gameState, teamId, isHome)
    local team = gameState.teams[teamId]
    if not team then return end
    if not isHome then return end  -- 只有主场有票房

    -- 票房收入 = 球场容量 × 票价(简化) × 上座率
    local capacity = team.stadiumCapacity or 30000
    local ticketPrice = 25  -- 平均票价 25
    local attendance = math.floor(capacity * (0.7 + Random() * 0.25))  -- 70-95%上座率
    local revenue = attendance * ticketPrice

    team.balance = team.balance + revenue
    team.seasonIncome = (team.seasonIncome or 0) + revenue

    FinanceManager.addTransaction(team, {
        amount = revenue,
        description = string.format("主场比赛票房 (入场 %d)", attendance),
        category = "ticket",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })
end

------------------------------------------------------
-- 赛季奖金发放
------------------------------------------------------
function FinanceManager.awardSeasonPrize(gameState, teamId, position)
    local team = gameState.teams[teamId]
    if not team then return end

    local prizeTable = Constants.SEASON_END_PRIZE or {}
    local prize = prizeTable[position] or 0
    if prize <= 0 then return end

    team.balance = team.balance + prize
    team.seasonIncome = (team.seasonIncome or 0) + prize

    FinanceManager.addTransaction(team, {
        amount = prize,
        description = string.format("赛季排名奖金 (第%d名)", position),
        category = "prize",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    if teamId == gameState.playerTeamId then
        gameState:sendMessage({
            category = "finance",
            title = "赛季奖金",
            body = string.format("恭喜！球队以第%d名完赛，获得奖金 %s。",
                position, FinanceManager.formatMoney(prize)),
            priority = "normal",
        })
    end
end

------------------------------------------------------
-- 赞助收入（每月1号）
------------------------------------------------------
function FinanceManager.processMonthlySponsorship(gameState)
    for teamId, team in pairs(gameState.teams) do
        -- 赞助收入与球队声望相关
        local rep = team.reputation or 50
        local sponsorRevenue = math.floor(rep * 1000 + Random() * rep * 200)

        team.balance = team.balance + sponsorRevenue
        team.seasonIncome = (team.seasonIncome or 0) + sponsorRevenue

        FinanceManager.addTransaction(team, {
            amount = sponsorRevenue,
            description = "月度赞助收入",
            category = "sponsor",
            season = gameState.season,
            week = FinanceManager._getWeekNumber(gameState),
        })
    end
end

------------------------------------------------------
-- 赛季重置财务统计
------------------------------------------------------
function FinanceManager.resetSeasonFinance(gameState)
    for _, team in pairs(gameState.teams) do
        team.seasonIncome = 0
        team.seasonExpense = 0
        -- 保留最近20条流水，清理历史
        local txs = team.transactions or {}
        if #txs > 20 then
            local recent = {}
            for i = #txs - 19, #txs do
                table.insert(recent, txs[i])
            end
            team.transactions = recent
        end
    end
end

------------------------------------------------------
-- 工具函数
------------------------------------------------------

-- 添加流水记录
function FinanceManager.addTransaction(team, tx)
    if not team.transactions then team.transactions = {} end
    table.insert(team.transactions, tx)
    -- 限制最多保留100条
    if #team.transactions > 100 then
        table.remove(team.transactions, 1)
    end
end

-- 获取周数
function FinanceManager._getWeekNumber(gameState)
    -- 简化计算：从赛季开始算周数
    local startMonth = Constants.SEASON_START_MONTH or 8
    local monthsElapsed = gameState.date.month - startMonth
    if monthsElapsed < 0 then monthsElapsed = monthsElapsed + 12 end
    return math.floor(monthsElapsed * 4.3) + math.ceil(gameState.date.day / 7)
end

-- 格式化金额
function FinanceManager.formatMoney(amount)
    if not amount then return "0" end
    local abs = math.abs(amount)
    local sign = amount < 0 and "-" or ""
    if abs >= 1000000 then
        return sign .. string.format("%.1fM", abs / 1000000)
    elseif abs >= 1000 then
        return sign .. string.format("%.0fK", abs / 1000)
    else
        return sign .. tostring(math.floor(abs))
    end
end

-- 检查球队是否能负担某笔支出
function FinanceManager.canAfford(team, amount)
    return team.balance >= amount
end

-- 检查是否在转会预算内
function FinanceManager.withinTransferBudget(team, amount)
    return (team.transferBudget or 0) >= amount
end

-- 检查是否在工资预算内
function FinanceManager.withinWageBudget(gameState, teamId, additionalWage)
    local team = gameState.teams[teamId]
    if not team then return false end

    local currentWage = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then currentWage = currentWage + (p.wage or 0) end
    end
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then currentWage = currentWage + (s.wage or 0) end
    end

    return (currentWage + additionalWage) <= (team.wageBudget or 999999)
end

------------------------------------------------------
-- 财务健康等级系统（4层）
-- stable / watch / warning / critical
------------------------------------------------------

-- 获取球队当前周薪总额
function FinanceManager.getWeeklyWageTotal(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return 0 end
    local total = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then total = total + (p.wage or 0) end
    end
    for _, sid in ipairs(team.staffIds or {}) do
        local s = gameState.staff[sid]
        if s then total = total + (s.wage or 0) end
    end
    return total
end

--- 计算财务健康等级
--- @return string status "stable"|"watch"|"warning"|"critical"
--- @return table details { wagePct, runwayWeeks, wageTotal, wageBudget }
function FinanceManager.getFinanceHealth(gameState, teamId)
    local team = gameState.teams[teamId]
    if not team then return "stable", {} end

    local wageTotal = FinanceManager.getWeeklyWageTotal(gameState, teamId)
    local wageBudget = team.wageBudget or 999999
    local balance = team.balance or 0

    -- 维度1: 工资预算占比
    local wagePct = wageBudget > 0 and (wageTotal / wageBudget * 100) or 0

    -- 维度2: 现金跑道周数（balance / weeklyWage）
    local runwayWeeks = wageTotal > 0 and math.floor(balance / wageTotal) or 999

    -- 综合判断
    local status = "stable"
    if balance < 0 or runwayWeeks < 2 or wagePct > 110 then
        status = "critical"
    elseif runwayWeeks < 6 or wagePct > 95 then
        status = "warning"
    elseif runwayWeeks < 12 or wagePct > 80 then
        status = "watch"
    end

    return status, {
        wagePct = wagePct,
        runwayWeeks = runwayWeeks,
        wageTotal = wageTotal,
        wageBudget = wageBudget,
        balance = balance,
    }
end

--- 获取健康等级中文描述
function FinanceManager.getHealthLabel(status)
    local labels = {
        stable = "稳健",
        watch = "关注",
        warning = "警告",
        critical = "危机",
    }
    return labels[status] or "未知"
end

------------------------------------------------------
-- 设施升级系统
------------------------------------------------------

FinanceManager.FACILITY_TYPES = {
    training = { name = "训练设施", baseCost = 10000000, maxLevel = 5 },  -- 10M base
    medical = { name = "医疗设施", baseCost = 8000000, maxLevel = 5 },   -- 8M base
    scouting = { name = "球探设施", baseCost = 6000000, maxLevel = 5 },  -- 6M base
}

function FinanceManager.ensureFacilities(team)
    if not team.facilities then
        team.facilities = {
            training = 1,
            medical = 1,
            scouting = 1,
        }
    end
    return team.facilities
end

function FinanceManager.getFacilityUpgradeCost(team, facilityType)
    local config = FinanceManager.FACILITY_TYPES[facilityType]
    if not config then return nil end
    local facilities = FinanceManager.ensureFacilities(team)
    local level = facilities[facilityType] or 1
    if level >= config.maxLevel then return nil end
    return math.floor(config.baseCost * (1.65 ^ (level - 1)) / 1000) * 1000
end

function FinanceManager.getFacilityBonuses(team)
    local facilities = FinanceManager.ensureFacilities(team)
    return {
        trainingGain = 1.0 + ((facilities.training or 1) - 1) * 0.08,
        injuryRecovery = 1.0 + ((facilities.medical or 1) - 1) * 0.1,
        scoutingAccuracy = 1.0 + ((facilities.scouting or 1) - 1) * 0.08,
    }
end

function FinanceManager.upgradeFacility(gameState, facilityType)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队" end
    local config = FinanceManager.FACILITY_TYPES[facilityType]
    if not config then return false, "未知设施类型" end

    local facilities = FinanceManager.ensureFacilities(team)
    local currentLevel = facilities[facilityType] or 1
    if currentLevel >= config.maxLevel then
        return false, config.name .. "已达到最高等级"
    end

    local cost = FinanceManager.getFacilityUpgradeCost(team, facilityType)
    if not cost or team.balance < cost then
        return false, "资金不足，升级需要 " .. FinanceManager.formatMoney(cost or 0)
    end

    team.balance = team.balance - cost
    team.seasonExpense = (team.seasonExpense or 0) + cost
    facilities[facilityType] = currentLevel + 1

    FinanceManager.addTransaction(team, {
        amount = -cost,
        description = config.name .. "升级至 Lv." .. facilities[facilityType],
        category = "facility",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    gameState:sendMessage({
        category = "finance",
        title = "设施升级完成",
        body = string.format("%s 已升级至 Lv.%d，长期经营加成已生效。",
            config.name, facilities[facilityType]),
        priority = "normal",
    })

    return true, string.format("%s 已升级至 Lv.%d", config.name, facilities[facilityType])
end

------------------------------------------------------
-- 财务恢复手段
------------------------------------------------------

--- 董事注资 — 代价是降低董事会满意度
--- @return boolean success
--- @return string message
function FinanceManager.requestBoardInjection(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队信息" end

    -- 注资额度 = 转会预算的30%~50%（与球队财力匹配）
    local rep = team.reputation or 50
    local baseAmount = (team.transferBudget or 25000000) * 0.35
    local amount = math.floor(baseAmount / 1000000) * 1000000  -- 取整到百万

    -- 冷却检查：每赛季最多2次
    if not team.finance then team.finance = {} end
    local injectCount = team.finance.boardInjectionsThisSeason or 0
    if injectCount >= 2 then
        return false, "本赛季已经申请过2次注资，董事会拒绝了你的请求"
    end

    -- 执行注资
    team.balance = team.balance + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.finance.boardInjectionsThisSeason = injectCount + 1

    -- 降低董事会满意度
    local satLoss = 15 + injectCount * 10  -- 第一次-15, 第二次-25
    team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - satLoss)

    FinanceManager.addTransaction(team, {
        amount = amount,
        description = "董事会紧急注资",
        category = "injection",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    gameState:sendMessage({
        category = "finance",
        title = "董事会注资",
        body = string.format(
            "董事会同意注资 %s，但对你的财务管理能力表示不满（满意度 -%d）。",
            FinanceManager.formatMoney(amount), satLoss
        ),
        priority = "normal",
    })

    return true, string.format("获得注资 %s（满意度 -%d）", FinanceManager.formatMoney(amount), satLoss)
end

--- 赞助推介 — 主动拉一笔赞助
--- @return boolean success
--- @return string message
function FinanceManager.seekSponsorship(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队信息" end

    if not team.finance then team.finance = {} end

    -- 冷却检查：每赛季最多3次
    local seekCount = team.finance.sponsorSeeksThisSeason or 0
    if seekCount >= 3 then
        return false, "本赛季赞助推介次数已用完（3/3）"
    end

    -- 赞助金额 = 声望 * 随机系数（有可能失败）
    local rep = team.reputation or 50
    local successChance = 0.5 + rep / 200  -- 50 rep=75%, 80 rep=90%

    if Random() > successChance then
        team.finance.sponsorSeeksThisSeason = seekCount + 1
        return false, "赞助商对当前球队表现不感兴趣，推介失败"
    end

    local amount = math.floor(rep * 50000 + 2000000 + Random() * 3000000)  -- 5M~10M级

    team.balance = team.balance + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.finance.sponsorSeeksThisSeason = seekCount + 1

    FinanceManager.addTransaction(team, {
        amount = amount,
        description = "赞助推介收入",
        category = "sponsor",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    gameState:sendMessage({
        category = "finance",
        title = "赞助推介成功",
        body = string.format("成功签下一笔赞助合同，获得 %s。", FinanceManager.formatMoney(amount)),
        priority = "normal",
    })

    return true, string.format("获得赞助 %s", FinanceManager.formatMoney(amount))
end

--- 商业活动 — 有28天冷却时间
--- @return boolean success
--- @return string message
function FinanceManager.hostCommercialEvent(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队信息" end

    if not team.finance then team.finance = {} end

    -- 冷却检查: 28天
    local lastEvent = team.finance.lastCommercialEventDate
    if lastEvent then
        local daysSince = FinanceManager._daysBetween(lastEvent, gameState.date)
        if daysSince < 28 then
            local daysLeft = 28 - daysSince
            return false, string.format("商业活动冷却中，还需等待 %d 天", daysLeft)
        end
    end

    -- 收入 = 声望 + 球场容量影响
    local rep = team.reputation or 50
    local capacity = team.stadiumCapacity or 30000
    local amount = math.floor(capacity * 30 + rep * 30000 + Random() * 2000000)  -- 2M~5M级

    team.balance = team.balance + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.finance.lastCommercialEventDate = {
        year = gameState.date.year,
        month = gameState.date.month,
        day = gameState.date.day,
    }

    FinanceManager.addTransaction(team, {
        amount = amount,
        description = "商业活动收入",
        category = "commercial",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    gameState:sendMessage({
        category = "finance",
        title = "商业活动成功",
        body = string.format("举办商业活动获得 %s 收入。下次可用时间: 28天后。", FinanceManager.formatMoney(amount)),
        priority = "normal",
    })

    return true, string.format("获得 %s", FinanceManager.formatMoney(amount))
end

--- 获取商业活动冷却剩余天数 (0=可用)
function FinanceManager.getCommercialCooldown(gameState)
    local team = gameState:getPlayerTeam()
    if not team or not team.finance then return 0 end
    local lastEvent = team.finance.lastCommercialEventDate
    if not lastEvent then return 0 end
    local daysSince = FinanceManager._daysBetween(lastEvent, gameState.date)
    return math.max(0, 28 - daysSince)
end

--- 计算两个日期间的天数差
function FinanceManager._daysBetween(date1, date2)
    -- 简化计算（假设30天/月）
    local d1 = date1.year * 360 + date1.month * 30 + date1.day
    local d2 = date2.year * 360 + date2.month * 30 + date2.day
    return d2 - d1
end

------------------------------------------------------
-- 阵容安全检查
------------------------------------------------------

--- 检查移除某球员后阵容是否安全
--- @return boolean safe
--- @return string reason 不安全时的原因
function FinanceManager.checkSquadSafety(gameState, playerId)
    local team = gameState:getPlayerTeam()
    if not team then return true, "" end

    local player = gameState.players[playerId]
    if not player then return true, "" end

    -- 移除后的阵容统计
    local gkCount, defCount, midCount, fwdCount = 0, 0, 0, 0
    local totalCount = 0

    for _, pid in ipairs(team.playerIds) do
        if pid ~= playerId then
            local p = gameState.players[pid]
            if p and not p.retired then
                totalCount = totalCount + 1
                local pos = p.position
                if pos == "GK" then
                    gkCount = gkCount + 1
                elseif pos == "CB" or pos == "LB" or pos == "RB" then
                    defCount = defCount + 1
                elseif pos == "CM" or pos == "LM" or pos == "RM" or pos == "CDM" or pos == "CAM" then
                    midCount = midCount + 1
                else
                    fwdCount = fwdCount + 1
                end
            end
        end
    end

    -- 最低安全标准：至少16人，至少1GK，至少3DEF，至少3MID，至少2FWD
    if totalCount < 16 then
        return false, string.format("阵容人数不足（剩余%d人，最少需要16人）", totalCount)
    end
    if gkCount < 1 then
        return false, "球队将没有门将"
    end
    if defCount < 3 then
        return false, string.format("后防线人数不足（剩余%d人，最少需要3人）", defCount)
    end
    if midCount < 3 then
        return false, string.format("中场人数不足（剩余%d人，最少需要3人）", midCount)
    end
    if fwdCount < 2 then
        return false, string.format("前锋人数不足（剩余%d人，最少需要2人）", fwdCount)
    end

    return true, ""
end

------------------------------------------------------
-- 赛季重置恢复手段次数
------------------------------------------------------
function FinanceManager.resetRecoveryCounters(team)
    if not team.finance then team.finance = {} end
    team.finance.boardInjectionsThisSeason = 0
    team.finance.sponsorSeeksThisSeason = 0
    -- 商业活动CD跨赛季保留
end

return FinanceManager
