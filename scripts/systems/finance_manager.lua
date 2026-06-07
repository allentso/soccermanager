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
    team.transferBudget = (team.transferBudget or 0) + amount  -- 售球收入回补转会预算
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.incomeBreakdown = team.incomeBreakdown or {}
    team.incomeBreakdown.transfer = (team.incomeBreakdown.transfer or 0) + amount

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
-- 票价策略系统
------------------------------------------------------
FinanceManager.TICKET_STRATEGIES = {
    { key = "low",      label = "亲民票价", multiplier = 0.70, attendanceBonus = 0.12, desc = "低票价吸引更多球迷，提升上座率" },
    { key = "standard", label = "标准票价", multiplier = 1.00, attendanceBonus = 0.00, desc = "平衡票价与上座率" },
    { key = "high",     label = "高端票价", multiplier = 1.40, attendanceBonus = -0.08, desc = "高票价高收益，但可能降低上座率" },
    { key = "premium",  label = "豪华票价", multiplier = 1.80, attendanceBonus = -0.18, desc = "极高票价，仅适合顶级强队" },
}

--- 获取当前票价策略
function FinanceManager.getTicketStrategy(team)
    local key = team.ticketStrategy or "standard"
    for _, s in ipairs(FinanceManager.TICKET_STRATEGIES) do
        if s.key == key then return s end
    end
    return FinanceManager.TICKET_STRATEGIES[2]  -- fallback standard
end

------------------------------------------------------
-- 赞助合同选择系统（赛季初决策事件）
------------------------------------------------------

-- 赞助商模板（根据球队声望随机生成具体参数）
FinanceManager.SPONSOR_TEMPLATES = {
    {
        type = "primary",       -- 主赞助
        label = "主赞助商",
        brands = { "龙腾体育", "星际科技", "鸿运地产", "云海金融", "极速汽车", "天元饮料" },
    },
    {
        type = "kit",           -- 球衣赞助
        label = "球衣赞助",
        brands = { "峰芒运动", "铁翼装备", "雷霆体育", "翔宇服饰", "猎鹰科技" },
    },
    {
        type = "sleeve",        -- 袖标赞助
        label = "袖标赞助",
        brands = { "闪电能量", "蓝鲸保险", "旭日银行", "星辰通讯", "碧波啤酒" },
    },
}

--- 生成赛季赞助合同选项（每种类型生成3个选项供选择）
function FinanceManager.generateSponsorOffers(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    -- 基础赞助金额跟球队声望挂钩（reputation 值域 500-900，归一化到 0-100）
    local reputation = (team.reputation or 500) / 10
    local baseFactor = 0.5 + (reputation / 100) * 1.5  -- 0.5x ~ 2.0x

    local offers = {}
    for _, tmpl in ipairs(FinanceManager.SPONSOR_TEMPLATES) do
        local typeOffers = {}
        -- 根据类型设定基础金额范围（月薪）
        local baseAmount
        if tmpl.type == "primary" then
            baseAmount = math.floor(200000 * baseFactor)
        elseif tmpl.type == "kit" then
            baseAmount = math.floor(120000 * baseFactor)
        else
            baseAmount = math.floor(60000 * baseFactor)
        end

        -- 生成 3 个方案：保守/均衡/激进
        local profiles = {
            { tag = "stable",    label = "稳定型", monthlyMult = 1.0, bonusMult = 0.3, penalty = 0, desc = "稳定月付，低绩效奖金，无罚款" },
            { tag = "balanced",  label = "均衡型", monthlyMult = 0.85, bonusMult = 0.8, penalty = 0.5, desc = "较低月付+中等奖金，降级有轻微罚款" },
            { tag = "aggressive",label = "激进型", monthlyMult = 0.6, bonusMult = 1.5, penalty = 1.5, desc = "低月付+高绩效奖金，降级有重大罚款" },
        }

        for i, profile in ipairs(profiles) do
            -- 随机选品牌
            local brandIdx = ((gameState.season or 1) + i) % #tmpl.brands + 1
            local brand = tmpl.brands[brandIdx]

            local monthly = math.floor(baseAmount * profile.monthlyMult / 10000) * 10000
            local topFinishBonus = math.floor(baseAmount * profile.bonusMult * 6 / 100000) * 100000
            local relegationPenalty = math.floor(baseAmount * profile.penalty * 12 / 100000) * 100000

            table.insert(typeOffers, {
                brand = brand,
                type = tmpl.type,
                typeLabel = tmpl.label,
                tag = profile.tag,
                profileLabel = profile.label,
                desc = profile.desc,
                monthlyAmount = monthly,
                topFinishBonus = topFinishBonus,       -- 前3名奖金
                relegationPenalty = relegationPenalty, -- 降级罚款
            })
        end

        offers[tmpl.type] = typeOffers
    end

    -- 存储待选择的合同
    team.pendingSponsorOffers = offers
    team.sponsorContractChosen = false
end

--- 玩家选择赞助合同
function FinanceManager.acceptSponsorContract(gameState, selections)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队" end

    -- selections 是一个 { primary = index, kit = index, sleeve = index } 表
    local chosen = {}
    local totalMonthly = 0

    for sType, idx in pairs(selections) do
        local offers = team.pendingSponsorOffers and team.pendingSponsorOffers[sType]
        if offers and offers[idx] then
            local offer = offers[idx]
            chosen[sType] = offer
            totalMonthly = totalMonthly + offer.monthlyAmount
        end
    end

    -- 应用合同
    team.sponsorContracts = chosen
    team.sponsorMonthlyTotal = totalMonthly
    team.pendingSponsorOffers = nil
    team.sponsorContractChosen = true

    -- 发送确认消息
    local lines = { "新赛季赞助合同已签署：" }
    for _, contract in pairs(chosen) do
        table.insert(lines, string.format("· %s(%s): %s/月",
            contract.brand, contract.typeLabel,
            FinanceManager.formatMoney(contract.monthlyAmount)))
    end
    table.insert(lines, string.format("\n合计月收入: %s", FinanceManager.formatMoney(totalMonthly)))

    gameState:sendMessage({
        category = "finance",
        title = "赞助合同签署完毕",
        body = table.concat(lines, "\n"),
        priority = "normal",
    })

    return true
end

--- 检查是否有待处理的赞助合同选择
function FinanceManager.hasPendingSponsorChoice(team)
    return team.pendingSponsorOffers ~= nil and not team.sponsorContractChosen
end

--- 设置票价策略
function FinanceManager.setTicketStrategy(team, strategyKey)
    for _, s in ipairs(FinanceManager.TICKET_STRATEGIES) do
        if s.key == strategyKey then
            team.ticketStrategy = strategyKey
            return true
        end
    end
    return false
end

------------------------------------------------------
-- 比赛日收入（票房）— 动态票价+智能上座率
-- 返回 revenueDetails 表（用于赛后展示）
------------------------------------------------------
function FinanceManager.processMatchDayRevenue(gameState, teamId, isHome, opponentTeamId)
    local team = gameState.teams[teamId]
    if not team then return nil end
    if not isHome then return nil end  -- 只有主场有票房

    local capacity = team.stadiumCapacity or 30000
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
    local opponentRep = 50
    local opponentName = "对手"
    if opponentTeamId and gameState.teams[opponentTeamId] then
        opponentRep = (gameState.teams[opponentTeamId].reputation or 500) / 10  -- 归一化到 0-100
        opponentName = gameState.teams[opponentTeamId].name or "对手"
    end

    -- 票价策略
    local strategy = FinanceManager.getTicketStrategy(team)

    -- 动态票价 = 基础票价 × 对手热度加成 × 策略系数
    local basePrice = 20 + math.floor(rep / 10)  -- rep50=25, rep80=28
    local opponentHype = math.min(2.0, 1.0 + opponentRep / 100)  -- 强队来访加价
    local ticketPrice = math.floor(basePrice * opponentHype * strategy.multiplier)

    -- 智能上座率 = 基础率 + 对手吸引力 + 连胜奖励 + 策略调整
    local baseAttendance = 0.65 + rep / 500  -- rep50=0.75, rep80=0.81
    local hypeBonus = math.min(0.15, opponentRep / 500)  -- 强队来访+观众
    local formBonus = math.min(0.10, (team.winStreak or 0) * 0.02)  -- 连胜吸引球迷
    local formPenalty = math.min(0.10, (team.loseStreak or 0) * 0.02)  -- 连败掉人
    local strategyBonus = strategy.attendanceBonus
    local attendanceRate = math.min(0.98, math.max(0.50, baseAttendance + hypeBonus + formBonus - formPenalty + strategyBonus))
    -- 小幅随机 ±5%
    attendanceRate = math.min(0.99, math.max(0.45, attendanceRate + (Random() - 0.5) * 0.10))

    local attendance = math.floor(capacity * attendanceRate)
    local revenue = attendance * ticketPrice

    team.balance = team.balance + revenue
    team.seasonIncome = (team.seasonIncome or 0) + revenue
    -- 分类细计
    team.incomeBreakdown = team.incomeBreakdown or {}
    team.incomeBreakdown.ticket = (team.incomeBreakdown.ticket or 0) + revenue

    FinanceManager.addTransaction(team, {
        amount = revenue,
        description = string.format("主场票房 (入场%d 票价%d)", attendance, ticketPrice),
        category = "ticket",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    -- 返回明细数据（用于赛后弹窗）
    local revenueDetails = {
        revenue = revenue,
        attendance = attendance,
        capacity = capacity,
        attendanceRate = attendanceRate,
        ticketPrice = ticketPrice,
        strategy = strategy.label,
        opponentName = opponentName,
        opponentRep = opponentRep,
        -- 对比上一场
        lastRevenue = team._lastMatchRevenue,
    }
    team._lastMatchRevenue = revenue
    return revenueDetails
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
    team.transferBudget = (team.transferBudget or 0) + prize  -- 奖金充入转会预算
    team.seasonIncome = (team.seasonIncome or 0) + prize
    team.incomeBreakdown = team.incomeBreakdown or {}
    team.incomeBreakdown.prize = (team.incomeBreakdown.prize or 0) + prize

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
-- 赞助收入（每月1号）— 基于声望+排名+球场容量
------------------------------------------------------
function FinanceManager.processMonthlySponsorship(gameState)
    for teamId, team in pairs(gameState.teams) do
        local sponsorRevenue

        -- 玩家球队：使用合同选择的金额（如果已签约）
        if team.sponsorMonthlyTotal and team.sponsorMonthlyTotal > 0 then
            -- 合同固定月付 + 小幅随机浮动 ±5%
            sponsorRevenue = math.floor(team.sponsorMonthlyTotal * (0.95 + Random() * 0.10))
        else
            -- AI球队 / 尚未签约：自动计算（reputation 值域 500-900，归一化到 0-100）
            local rep = (team.reputation or 500) / 10
            local capacity = team.stadiumCapacity or 30000
            local position = team.leaguePosition or 10

            local baseSponsor = rep * 15000 + (capacity / 30000) * 500000
            local posBonus = math.max(0, (11 - position) * rep * 1000)
            -- 顶级俱乐部品牌溢价：rep>=80 时有额外商业收入（模拟全球品牌效应）
            local prestigeBonus = math.max(0, (rep - 80) * 500000)
            sponsorRevenue = math.floor((baseSponsor + posBonus + prestigeBonus) * (0.85 + Random() * 0.30))
        end

        team.balance = team.balance + sponsorRevenue
        team.seasonIncome = (team.seasonIncome or 0) + sponsorRevenue
        -- 分类细计
        team.incomeBreakdown = team.incomeBreakdown or {}
        team.incomeBreakdown.sponsor = (team.incomeBreakdown.sponsor or 0) + sponsorRevenue

        FinanceManager.addTransaction(team, {
            amount = sponsorRevenue,
            description = team.sponsorMonthlyTotal and "赞助合同月付" or "月度赞助收入",
            category = "sponsor",
            season = gameState.season,
            week = FinanceManager._getWeekNumber(gameState),
        })
    end
end

------------------------------------------------------
-- 转播分成收入（每月1号）— 联赛排名越高份额越大
------------------------------------------------------
function FinanceManager.processMonthlyBroadcast(gameState)
    for teamId, team in pairs(gameState.teams) do
        local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
        local position = team.leaguePosition or 10

        -- 转播池按排名分配（第1名拿最大份额，第20名最小）
        local shareRatio = 1.0 + (20 - position) * 0.05  -- 第1=1.95x, 第10=1.50x, 第20=1.00x
        local baseAmount = rep * 26000 + 200000
        local amount = math.floor(baseAmount * shareRatio)

        team.balance = team.balance + amount
        team.seasonIncome = (team.seasonIncome or 0) + amount
        team.incomeBreakdown = team.incomeBreakdown or {}
        team.incomeBreakdown.broadcast = (team.incomeBreakdown.broadcast or 0) + amount

        FinanceManager.addTransaction(team, {
            amount = amount,
            description = string.format("转播分成 (排名%d)", position),
            category = "broadcast",
            season = gameState.season,
            week = FinanceManager._getWeekNumber(gameState),
        })
    end
end

------------------------------------------------------
-- 商品销售收入（每月1号）— 球星效应加成
------------------------------------------------------
function FinanceManager.processMonthlyMerchandise(gameState)
    for teamId, team in pairs(gameState.teams) do
        local rep = (team.reputation or 500) / 10  -- 归一化到 0-100

        -- 球星效应：OVR > 80 的球员每人+15%加成（上限60%）
        local starCount = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and (p.overall or 0) > 80 then starCount = starCount + 1 end
        end
        local starBonus = 1.0 + math.min(0.6, starCount * 0.15)

        local baseAmount = rep * 8000 + 100000
        -- 顶级俱乐部全球商品溢价
        local prestigeMerch = math.max(0, (rep - 80) * 200000)
        local amount = math.floor((baseAmount + prestigeMerch) * starBonus * (0.90 + Random() * 0.20))

        team.balance = team.balance + amount
        team.seasonIncome = (team.seasonIncome or 0) + amount
        team.incomeBreakdown = team.incomeBreakdown or {}
        team.incomeBreakdown.merchandise = (team.incomeBreakdown.merchandise or 0) + amount

        FinanceManager.addTransaction(team, {
            amount = amount,
            description = starCount > 0
                and string.format("商品销售 (球星%d人加成)", starCount)
                or "商品销售",
            category = "merchandise",
            season = gameState.season,
            week = FinanceManager._getWeekNumber(gameState),
        })
    end
end

------------------------------------------------------
-- 月度运营开支：设施维护 + 球场维护
------------------------------------------------------
FinanceManager.FACILITY_MAINTENANCE = {
    -- [level] = 月维护费（Lv.1免费）
    [1] = 0,
    [2] = 50000,
    [3] = 120000,
    [4] = 250000,
    [5] = 500000,
}

function FinanceManager.processMonthlyMaintenance(gameState)
    for teamId, team in pairs(gameState.teams) do
        local totalMaintenance = 0

        -- 设施维护费
        local facilities = team.facilities or { training = 1, medical = 1, scouting = 1 }
        for _, level in pairs(facilities) do
            totalMaintenance = totalMaintenance + (FinanceManager.FACILITY_MAINTENANCE[level] or 0)
        end

        -- 球场维护费 = 容量 × 10（30K容量 = 300K/月）
        local capacity = team.stadiumCapacity or 30000
        local stadiumCost = math.floor(capacity * 10)
        totalMaintenance = totalMaintenance + stadiumCost

        if totalMaintenance > 0 then
            team.balance = team.balance - totalMaintenance
            team.seasonExpense = (team.seasonExpense or 0) + totalMaintenance

            FinanceManager.addTransaction(team, {
                amount = -totalMaintenance,
                description = string.format("运营维护 (设施+球场)", totalMaintenance),
                category = "maintenance",
                season = gameState.season,
                week = FinanceManager._getWeekNumber(gameState),
            })
        end
    end
end

------------------------------------------------------
-- 月度财报消息（每月1号发送给玩家，展示各收入源+环比）
------------------------------------------------------
function FinanceManager.generateMonthlyReport(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return end

    local breakdown = team.incomeBreakdown or {}
    local seasonIncome = team.seasonIncome or 0
    local seasonExpense = team.seasonExpense or 0

    -- 记录每月快照用于环比
    if not team.monthlySnapshots then team.monthlySnapshots = {} end
    local monthKey = string.format("%d-%02d", gameState.date.year, gameState.date.month)
    local prevMonth = team.monthlySnapshots[#team.monthlySnapshots]

    -- 本月各项收入（从上次快照到现在的增量）
    local prevBreakdown = prevMonth and prevMonth.breakdown or {}
    local monthlyIncome = {
        ticket = (breakdown.ticket or 0) - (prevBreakdown.ticket or 0),
        sponsor = (breakdown.sponsor or 0) - (prevBreakdown.sponsor or 0),
        broadcast = (breakdown.broadcast or 0) - (prevBreakdown.broadcast or 0),
        merchandise = (breakdown.merchandise or 0) - (prevBreakdown.merchandise or 0),
        transfer = (breakdown.transfer or 0) - (prevBreakdown.transfer or 0),
        prize = (breakdown.prize or 0) - (prevBreakdown.prize or 0),
    }
    local prevMonthlyIncome = prevMonth and prevMonth.monthlyIncome or nil

    local totalMonthIncome = 0
    for _, v in pairs(monthlyIncome) do totalMonthIncome = totalMonthIncome + v end

    local totalMonthExpense = (seasonExpense - (prevMonth and prevMonth.expense or 0))

    -- 保存快照
    table.insert(team.monthlySnapshots, {
        key = monthKey,
        breakdown = { ticket = breakdown.ticket or 0, sponsor = breakdown.sponsor or 0,
                      broadcast = breakdown.broadcast or 0, merchandise = breakdown.merchandise or 0,
                      transfer = breakdown.transfer or 0, prize = breakdown.prize or 0 },
        income = seasonIncome,
        expense = seasonExpense,
        monthlyIncome = monthlyIncome,
    })
    -- 最多保留12个月快照
    if #team.monthlySnapshots > 12 then table.remove(team.monthlySnapshots, 1) end

    -- 构建消息正文
    local labels = { ticket = "票房", sponsor = "赞助", broadcast = "转播", merchandise = "商品", transfer = "转会", prize = "奖金" }
    local lines = {}
    table.insert(lines, string.format("本月总收入: %s | 总支出: %s",
        FinanceManager.formatMoney(totalMonthIncome), FinanceManager.formatMoney(totalMonthExpense)))
    table.insert(lines, "")

    -- 各项明细 + 环比
    local order = { "sponsor", "broadcast", "merchandise", "ticket", "transfer", "prize" }
    for _, key in ipairs(order) do
        local val = monthlyIncome[key] or 0
        if val > 0 then
            local line = string.format("  %s: %s", labels[key], FinanceManager.formatMoney(val))
            if prevMonthlyIncome and prevMonthlyIncome[key] and prevMonthlyIncome[key] > 0 then
                local diff = val - prevMonthlyIncome[key]
                local pct = math.floor(diff / prevMonthlyIncome[key] * 100)
                if pct ~= 0 then
                    line = line .. (pct > 0 and string.format(" (+%d%%)", pct) or string.format(" (%d%%)", pct))
                end
            end
            table.insert(lines, line)
        end
    end

    -- 净利润
    local net = totalMonthIncome - totalMonthExpense
    table.insert(lines, "")
    table.insert(lines, string.format("净利润: %s%s", net >= 0 and "+" or "", FinanceManager.formatMoney(net)))

    gameState:sendMessage({
        category = "finance",
        title = "月度财务报告",
        body = table.concat(lines, "\n"),
        priority = "normal",
    })
end

------------------------------------------------------
-- 球场扩建系统
------------------------------------------------------
FinanceManager.STADIUM_EXPANSION = {
    baseCostPerSeat = 800,       -- 每座位基础造价
    maxCapacity = 80000,         -- 最大容量上限
    expansionStep = 5000,        -- 每次扩建增加座位数
    buildWeeks = 8,              -- 建造周期（周）
}

--- 获取球场扩建费用
function FinanceManager.getStadiumExpansionCost(team)
    local capacity = team.stadiumCapacity or 30000
    local cfg = FinanceManager.STADIUM_EXPANSION
    if capacity >= cfg.maxCapacity then return nil, "已达最大容量" end

    local newCapacity = math.min(cfg.maxCapacity, capacity + cfg.expansionStep)
    local addedSeats = newCapacity - capacity
    -- 越大越贵（非线性增长）
    local scaleFactor = 1.0 + (capacity / cfg.maxCapacity) * 0.8
    local cost = math.floor(addedSeats * cfg.baseCostPerSeat * scaleFactor / 1000000) * 1000000  -- 取整到百万

    return cost, nil, addedSeats, newCapacity
end

--- 执行球场扩建
function FinanceManager.expandStadium(gameState)
    local team = gameState:getPlayerTeam()
    if not team then return false, "无法获取球队" end

    -- 检查是否正在建设中
    if team.stadiumExpanding then
        local remaining = (team.stadiumExpandWeeksLeft or 0)
        return false, string.format("球场正在扩建中，还需 %d 周完工", remaining)
    end

    local cost, err, addedSeats, newCapacity = FinanceManager.getStadiumExpansionCost(team)
    if not cost then return false, err end

    if team.balance < cost then
        return false, "资金不足，扩建需要 " .. FinanceManager.formatMoney(cost)
    end

    -- 扣费
    team.balance = team.balance - cost
    team.seasonExpense = (team.seasonExpense or 0) + cost

    -- 设置建设状态
    team.stadiumExpanding = true
    team.stadiumExpandWeeksLeft = FinanceManager.STADIUM_EXPANSION.buildWeeks
    team.stadiumExpandTarget = newCapacity

    FinanceManager.addTransaction(team, {
        amount = -cost,
        description = string.format("球场扩建 (%d→%d座)", team.stadiumCapacity, newCapacity),
        category = "facility",
        season = gameState.season,
        week = FinanceManager._getWeekNumber(gameState),
    })

    gameState:sendMessage({
        category = "finance",
        title = "球场扩建开工",
        body = string.format("球场扩建已启动！将从 %d 座扩建至 %d 座（+%d），预计 %d 周完工。投入: %s",
            team.stadiumCapacity, newCapacity, addedSeats,
            FinanceManager.STADIUM_EXPANSION.buildWeeks,
            FinanceManager.formatMoney(cost)),
        priority = "normal",
    })

    return true, string.format("球场扩建已启动 (+%d座，%d周完工)", addedSeats, FinanceManager.STADIUM_EXPANSION.buildWeeks)
end

--- 每周检查球场扩建进度
function FinanceManager.processStadiumExpansion(team, gameState)
    if not team.stadiumExpanding then return end

    team.stadiumExpandWeeksLeft = (team.stadiumExpandWeeksLeft or 0) - 1

    if team.stadiumExpandWeeksLeft <= 0 then
        local oldCapacity = team.stadiumCapacity or 30000
        team.stadiumCapacity = team.stadiumExpandTarget or (oldCapacity + 5000)
        team.stadiumExpanding = nil
        team.stadiumExpandWeeksLeft = nil
        team.stadiumExpandTarget = nil

        if gameState and team == gameState:getPlayerTeam() then
            gameState:sendMessage({
                category = "finance",
                title = "球场扩建完工!",
                body = string.format("球场扩建已完成！容量从 %d 提升至 %d 座。更多座位意味着更高的比赛日收入！",
                    oldCapacity, team.stadiumCapacity),
                priority = "high",
            })
        end
    end
end

------------------------------------------------------
-- 赛季重置财务统计
------------------------------------------------------
function FinanceManager.resetSeasonFinance(gameState)
    for _, team in pairs(gameState.teams) do
        team.seasonIncome = 0
        team.seasonExpense = 0
        team.incomeBreakdown = nil  -- 重置收入分类统计
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

-- 格式化金额（根据设置选择 万 或 K/M 格式）
function FinanceManager.formatMoney(amount)
    if not amount then return "0" end
    local abs = math.abs(amount)
    local sign = amount < 0 and "-" or ""

    -- 读取货币显示设置，默认"万"
    local unit = "wan"
    if _G.gameState and _G.gameState.settings then
        unit = _G.gameState.settings.currencyUnit or "wan"
    end

    if unit == "wan" then
        -- 万 模式：>=10000 用万，<10000 直接显示
        if abs >= 100000000 then
            return sign .. string.format("%.1f亿", abs / 100000000)
        elseif abs >= 10000 then
            local wan = abs / 10000
            if wan >= 1000 then
                return sign .. string.format("%.0f万", wan)
            elseif wan >= 100 then
                return sign .. string.format("%.0f万", wan)
            elseif wan >= 10 then
                return sign .. string.format("%.1f万", wan)
            else
                return sign .. string.format("%.1f万", wan)
            end
        else
            return sign .. tostring(math.floor(abs))
        end
    else
        -- K/M 模式
        if abs >= 1000000 then
            return sign .. string.format("%.1fM", abs / 1000000)
        elseif abs >= 1000 then
            return sign .. string.format("%.0fK", abs / 1000)
        else
            return sign .. tostring(math.floor(abs))
        end
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

--- 计算财务健康等级（6级：excellent/stable/fair/watch/warning/critical）
--- @return string status
--- @return table details { wagePct, runwayWeeks, wageTotal, wageBudget, netIncome }
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

    -- 维度3: 赛季净收入趋势
    local netIncome = (team.seasonIncome or 0) - (team.seasonExpense or 0)

    -- 6级综合判断（从优到差）
    local status = "stable"
    if balance < 0 or runwayWeeks < 2 or wagePct > 110 then
        status = "critical"       -- F: 破产边缘
    elseif runwayWeeks < 6 or wagePct > 95 then
        status = "warning"        -- D: 财务紧张
    elseif runwayWeeks < 10 or wagePct > 85 then
        status = "watch"          -- C: 需要关注
    elseif runwayWeeks < 16 or wagePct > 70 then
        status = "fair"           -- B: 财务尚可
    elseif runwayWeeks >= 24 and wagePct < 60 and netIncome > 0 then
        status = "excellent"      -- A+: 财务卓越
    end
    -- 其余情况保持 "stable" = A

    return status, {
        wagePct = wagePct,
        runwayWeeks = runwayWeeks,
        wageTotal = wageTotal,
        wageBudget = wageBudget,
        balance = balance,
        netIncome = netIncome,
    }
end

--- 获取健康等级中文描述
function FinanceManager.getHealthLabel(status)
    local labels = {
        excellent = "卓越",
        stable = "稳健",
        fair = "尚可",
        watch = "关注",
        warning = "紧张",
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
    youth = { name = "青训设施", baseCost = 7000000, maxLevel = 5 },     -- 7M base
}

function FinanceManager.ensureFacilities(team)
    if not team.facilities then
        team.facilities = {
            training = 1,
            medical = 1,
            scouting = 1,
            youth = 1,
        }
    end
    -- 向后兼容：旧存档补充新字段
    if not team.facilities.youth then
        team.facilities.youth = 1
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
        youthQuality = 1.0 + ((facilities.youth or 1) - 1) * 0.10,
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

    -- 注资额度：基于声望和初始转会预算级别（不受当前余额影响）
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
    -- 用声望推算球队级别，保底 10M，高声望球队更多
    local budgetBase = math.max(team.transferBudget or 0, rep * 300000 + 10000000)
    local baseAmount = budgetBase * 0.18
    local amount = math.min(20000000, math.max(3000000, math.floor(baseAmount / 1000000) * 1000000))  -- 3M~20M，取整到百万

    -- 冷却检查：每赛季最多2次
    if not team.finance then team.finance = {} end
    local injectCount = team.finance.boardInjectionsThisSeason or 0
    if injectCount >= 2 then
        return false, "本赛季已经申请过2次注资，董事会拒绝了你的请求"
    end

    -- 执行注资（同时补充转会预算）
    team.balance = team.balance + amount
    team.transferBudget = (team.transferBudget or 0) + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.finance.boardInjectionsThisSeason = injectCount + 1

    -- 降低董事会满意度
    local satLoss = 20 + injectCount * 15  -- 第一次-20, 第二次-35
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
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
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
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
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
