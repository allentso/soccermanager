-- systems/finance_manager.lua
-- 财务流转系统：工资扣除、转会费入账/出账、奖金发放、流水记录

local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local MessageManager = require("scripts/systems/message_manager")
local DifficultySettings = require("scripts/systems/difficulty_settings")

local FinanceManager = {}

-- 联赛级别经济倍率。次级联赛已经通过 wageBudget/reputation 被压低，这里只补足
-- 转播、赞助、奖金等「联赛平台收入」的额外差距。
FinanceManager.LEAGUE_TIER_ECONOMY = {
    [1] = {
        sponsor = 1.0,
        sponsorContract = 1.0,
        broadcast = 1.0,
        merchandise = 1.0,
        matchday = 1.0,
        prize = 1.0,
    },
    [2] = {
        sponsor = 0.65,
        sponsorContract = 0.65,
        broadcast = 0.38,
        merchandise = 0.60,
        matchday = 0.78,
        prize = 0.25,
    },
}

function FinanceManager.getLeagueTier(gameState, teamId)
    if not gameState or not teamId then return 1 end
    if gameState.getTeamLeague then
        local lg = gameState:getTeamLeague(teamId)
        if lg then return lg.tier or 1 end
    end
    return 1
end

function FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, key)
    local tier = FinanceManager.getLeagueTier(gameState, teamId)
    local cfg = FinanceManager.LEAGUE_TIER_ECONOMY[tier]
        or (tier >= 2 and FinanceManager.LEAGUE_TIER_ECONOMY[2])
        or FinanceManager.LEAGUE_TIER_ECONOMY[1]
    return cfg[key] or 1.0
end

function FinanceManager.getFinanceDifficultyMultiplier(key)
    local mods = DifficultySettings.getFinanceModifiers()
    return mods[key] or 1.0
end

------------------------------------------------------
-- 每周处理：扣除所有球队的周薪
------------------------------------------------------
--- 按球员 ID 查找活跃租借记录
function FinanceManager._getActiveLoanForPlayer(gameState, playerId)
    for _, loan in ipairs(gameState._activeLoans or {}) do
        if loan.playerId == playerId then return loan end
    end
    return nil
end

function FinanceManager.processWeeklyWages(gameState)
    for teamId, team in pairs(gameState.teams) do
        local totalPlayerWage = 0
        local totalStaffWage = 0

        -- 球员薪资（含租借工资分摊）
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p then
                local wage = p.wage or 0
                local loan = FinanceManager._getActiveLoanForPlayer(gameState, pid)
                if loan and loan.loanTeamId == teamId then
                    local share = loan.wageShare or 0.5
                    totalPlayerWage = totalPlayerWage + math.floor(wage * share)
                elseif not loan or loan.originTeamId ~= teamId then
                    totalPlayerWage = totalPlayerWage + wage
                end
            end
        end

        -- 外租出去的球员：出租方承担剩余工资份额
        for _, loan in ipairs(gameState._activeLoans or {}) do
            if loan.originTeamId == teamId then
                local p = gameState.players[loan.playerId]
                if p then
                    local share = loan.wageShare or 0.5
                    local originShare = math.max(0, 1.0 - share)
                    totalPlayerWage = totalPlayerWage + math.floor((p.wage or 0) * originShare)
                end
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

            -- 玩家球队：检查财务告警（每周最多各一条）
            if teamId == gameState.playerTeamId then
                local weekNum = FinanceManager._getWeekNumber(gameState)
                if team.balance < totalWage * 4 and team.balance > 0 then
                    local dedupeKey = "finance_warning_w" .. weekNum
                    if not MessageManager._isDuplicate(gameState, dedupeKey) then
                        MessageManager._markSent(gameState, dedupeKey)
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
                end
                if team.balance < 0 then
                    local dedupeKey = "finance_crisis_w" .. weekNum
                    if not MessageManager._isDuplicate(gameState, dedupeKey) then
                        MessageManager._markSent(gameState, dedupeKey)
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

        FinanceManager._trackDebtConsequences(gameState, team)
    end
end

------------------------------------------------------
-- 转会费入账
------------------------------------------------------
function FinanceManager.processTransferIn(gameState, teamId, amount, playerName)
    local team = gameState.teams[teamId]
    if not team then return end

    team.balance = team.balance + amount
    -- 售球收入仅部分回补转会预算，避免卖人循环放大购买力
    team.transferBudget = (team.transferBudget or 0) + math.floor(amount * 0.65)
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
    -- 英超顶级队年赞助 2-3 亿，月约 2000 万；中游约 5000-8000 万/年
    local reputation = (team.reputation or 500) / 10
    local baseFactor = 0.65 + (reputation / 100) * 1.6  -- 0.65x ~ 2.25x
    local offerScale = FinanceManager._getWageScale(team)
        * FinanceManager.getLeagueEconomyMultiplier(gameState, team.id, "sponsorContract")
        * FinanceManager.getFinanceDifficultyMultiplier("sponsorContract")

    local offers = {}
    for _, tmpl in ipairs(FinanceManager.SPONSOR_TEMPLATES) do
        local typeOffers = {}
        -- 根据类型设定基础金额范围（月薪）
        local baseAmount
        if tmpl.type == "primary" then
            baseAmount = math.floor(1400000 * baseFactor)
        elseif tmpl.type == "kit" then
            baseAmount = math.floor(850000 * baseFactor)
        else
            baseAmount = math.floor(350000 * baseFactor)
        end
        baseAmount = math.floor(baseAmount * offerScale)

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

    local TransferManager = require("scripts/systems/transfer_manager")
    local isDerby = opponentTeamId and TransferManager._isRivalry(gameState, teamId, opponentTeamId)

    -- 票价策略
    local strategy = FinanceManager.getTicketStrategy(team)

    -- 动态票价 = 基础票价 × 对手热度加成 × 策略系数
    -- 英超票价通常 40-100 镑，rep68(曼联级)基础应约 48-50
    local basePrice = 32 + math.floor(rep / 5)  -- rep50=42, rep68=45, rep80=48
    local opponentHype = math.min(1.75, 1.0 + opponentRep / 130)
    local matchdayScale = FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, "matchday")
        * FinanceManager.getFinanceDifficultyMultiplier("matchday")
    local ticketPrice = math.floor(basePrice * opponentHype * strategy.multiplier * matchdayScale)

    -- 智能上座率 = 基础率 + 对手吸引力 + 连胜奖励 + 策略调整
    local baseAttendance = 0.60 + rep / 520  -- 略低于旧版，贴近现实票房占比
    local hypeBonus = math.min(0.15, opponentRep / 500)  -- 强队来访+观众
    if isDerby then
        hypeBonus = hypeBonus + 0.08  -- 德比战额外上座率
    end
    local formBonus = math.min(0.10, (team.winStreak or 0) * 0.02)  -- 连胜吸引球迷
    local formPenalty = math.min(0.10, (team.loseStreak or 0) * 0.02)  -- 连败掉人
    local strategyBonus = strategy.attendanceBonus
    local attendanceRate = math.min(0.98, math.max(0.50, baseAttendance + hypeBonus + formBonus - formPenalty + strategyBonus))
    -- 小幅随机 ±5%
    attendanceRate = math.min(0.99, math.max(0.45, attendanceRate + (Random() - 0.5) * 0.10))

    local attendance = math.floor(capacity * attendanceRate)
    local grossRevenue = attendance * ticketPrice
    -- 赛事运营成本（安保、转播布置、球童等）：约 15% 票房 + 按容量固定成本
    local matchOpsCost = math.floor(grossRevenue * 0.15 + capacity * 12)
    local revenue = math.max(0, grossRevenue - matchOpsCost)

    team.balance = team.balance + revenue
    if matchOpsCost > 0 then
        team.seasonExpense = (team.seasonExpense or 0) + matchOpsCost
    end
    -- 赛季财报按毛票房入账，再用赛日成本冲减；现金余额只增加净票房。
    team.seasonIncome = (team.seasonIncome or 0) + grossRevenue
    -- 分类细计
    team.incomeBreakdown = team.incomeBreakdown or {}
    team.incomeBreakdown.ticket = (team.incomeBreakdown.ticket or 0) + grossRevenue

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
        grossRevenue = grossRevenue,
        matchOpsCost = matchOpsCost,
        attendance = attendance,
        capacity = capacity,
        attendanceRate = attendanceRate,
        ticketPrice = ticketPrice,
        strategy = strategy.label,
        opponentName = opponentName,
        opponentRep = opponentRep,
        -- 对比上一场：只存数字！
        -- [BUG FIX] 此前存整个上一场的 revenueDetails 表，而那个表里又嵌着
        -- 上上场的表……每个主场加深一层，约 30 个主场后超过 cjson 的
        -- 64 层嵌套上限，导致"2027年10月起自动/手动保存全部静默失败"。
        lastRevenue = type(team._lastMatchRevenue) == "table"
            and team._lastMatchRevenue.revenue or team._lastMatchRevenue,
    }
    team._lastMatchRevenue = revenueDetails
    return revenueDetails
end

------------------------------------------------------
-- 通用收入入账（杯赛/赛事奖金等）
------------------------------------------------------
function FinanceManager.addIncome(gameState, teamId, amount, description, category)
    local team = gameState.teams[teamId]
    if not team or not amount or amount <= 0 then return end

    category = category or "prize"
    team.balance = team.balance + amount
    team.transferBudget = (team.transferBudget or 0) + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.incomeBreakdown = team.incomeBreakdown or {}
    team.incomeBreakdown[category] = (team.incomeBreakdown[category] or 0) + amount

    FinanceManager.addTransaction(team, {
        amount = amount,
        description = description or "奖金收入",
        category = category,
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
    local prizeScale = FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, "prize")
        * FinanceManager.getFinanceDifficultyMultiplier("prize")
    prize = math.floor(prize * prizeScale / 100000) * 100000
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

            -- 经济规模系数：让小型俱乐部收入与其体量匹配
            local wageScale = FinanceManager._getWageScale(team)

            local baseSponsor = rep * 10000 + (capacity / 30000) * 320000
            local posBonus = math.max(0, (11 - position) * rep * 700)
            local prestigeBonus = math.max(0, (rep - 80) * 280000)
            local leagueScale = FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, "sponsor")
                * FinanceManager.getFinanceDifficultyMultiplier("sponsor")
            sponsorRevenue = math.floor(
                ((baseSponsor + posBonus) * wageScale + prestigeBonus)
                * leagueScale
                * (0.85 + Random() * 0.25))
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

        -- 经济规模系数
        local wageScale = FinanceManager._getWageScale(team)

        -- 转播池按排名分配（第1名拿最大份额，第20名最小）
        -- 英超中游年转播约 1.0-1.3 亿（校准 Brighton/Wolves 2023/24）
        local shareRatio = 1.0 + (20 - position) * 0.04  -- 第1=1.76x, 第10=1.40x, 第20=1.00x
        local baseAmount = rep * 105000 + 750000
        local leagueScale = FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, "broadcast")
            * FinanceManager.getFinanceDifficultyMultiplier("broadcast")
        local amount = math.floor(baseAmount * shareRatio * wageScale * leagueScale)

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

        -- 经济规模系数
        local wageScale = FinanceManager._getWageScale(team)

        -- 球星效应：OVR > 80 的球员每人+15%加成（上限60%）
        -- 传奇球员商业价值更高：每位传奇额外+15%（相当于2倍权重）
        local starCount = 0
        local legendCount = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and (p.overall or 0) > 80 then starCount = starCount + 1 end
            if p and p.isLegend then legendCount = legendCount + 1 end
        end
        -- 青训队的传奇也算入商业价值
        for _, pid in ipairs(team._youthPlayerIds or {}) do
            local p = gameState.players[pid]
            if p and p.isLegend then legendCount = legendCount + 1 end
        end
        local starBonus = 1.0 + math.min(0.9, starCount * 0.15 + legendCount * 0.15)

        local baseAmount = rep * 14000 + 150000
        local prestigeMerch = math.max(0, (rep - 80) * 200000)
        local leagueScale = FinanceManager.getLeagueEconomyMultiplier(gameState, teamId, "merchandise")
            * FinanceManager.getFinanceDifficultyMultiplier("merchandise")
        local amount = math.floor(
            (baseAmount * wageScale + prestigeMerch)
            * leagueScale
            * starBonus
            * (0.88 + Random() * 0.18))

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
    [2] = 80000,
    [3] = 180000,
    [4] = 380000,
    [5] = 750000,
}

function FinanceManager.processMonthlyMaintenance(gameState)
    for teamId, team in pairs(gameState.teams) do
        local totalMaintenance = 0

        -- 设施维护费
        local facilities = team.facilities or { training = 1, medical = 1, scouting = 1 }
        for _, level in pairs(facilities) do
            totalMaintenance = totalMaintenance + (FinanceManager.FACILITY_MAINTENANCE[level] or 0)
        end

        -- 球场维护费 = 容量 × 18（30K容量 ≈ 540K/月）
        local capacity = team.stadiumCapacity or 30000
        local stadiumCost = math.floor(capacity * 18)
        totalMaintenance = totalMaintenance + stadiumCost

        -- 俱乐部行政/运营（按声望与职员规模）
        local rep = (team.reputation or 500) / 10
        local staffCount = #(team.staffIds or {})
        local adminCost = math.floor(rep * 12000 + staffCount * 45000 + 80000)
        totalMaintenance = totalMaintenance + adminCost

        -- 青训学院运营费
        local youthCount = #(team._youthPlayerIds or {})
        local youthLevel = (facilities.youth or 1)
        if youthCount > 0 then
            totalMaintenance = totalMaintenance + math.floor(youthCount * (25000 + youthLevel * 12000))
        end

        -- 球探部门运营费（设施等级 + 活跃报告数）
        local scoutLevel = facilities.scouting or 1
        local activeReports = 0
        if gameState.scoutReports then
            for _, report in ipairs(gameState.scoutReports) do
                if report.teamId == teamId and (report.status == "active" or report.status == "in_progress") then
                    activeReports = activeReports + 1
                end
            end
        end
        totalMaintenance = totalMaintenance + math.floor(scoutLevel * 60000 + activeReports * 15000)
        totalMaintenance = math.floor(totalMaintenance * FinanceManager.getFinanceDifficultyMultiplier("maintenance"))

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
    local monthKey = string.format("%d-%02d",
        tonumber(gameState.date.year) or 2025,
        tonumber(gameState.date.month) or 8)
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
    if FinanceManager.isSpendingFrozen(team) then
        return false, "财务管制中，无法启动球场扩建"
    end

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
                priority = "normal",
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
-- 市场工资模型（能力/身价/年龄/角色统一估算）
------------------------------------------------------

local function isSpecialMarketPlayer(player)
    return player and (
        player.isLegend
        or player.isReincarnation
        or player.reincarnationMatchName ~= nil
        or player.reincarnationTier == "rebirth"
    )
end

--- 基于 OVR 的分段公平周薪（校准：70≈20K, 80≈70K, 90≈240K）
function FinanceManager._ovrBaseWage(ovr)
    ovr = ovr or 50
    if ovr < 65 then
        return math.floor(ovr * 220)
    elseif ovr < 75 then
        return math.floor(8000 + (ovr - 65) * 2500)
    elseif ovr < 85 then
        return math.floor(33000 + (ovr - 75) * 7500)
    else
        return math.floor(120000 + (ovr - 85) * 24000)
    end
end

--- 估算球员市场公平周薪
--- @param player table
--- @param team table|nil
--- @param gameState table|nil
--- @param opts table|nil { contractType = "youth"|"promote"|"first_team", noFloor }
function FinanceManager.estimateMarketWage(player, team, gameState, opts)
    if not player then return 1000 end
    opts = opts or {}

    local ovr = player.overall or 50
    local wage = FinanceManager._ovrBaseWage(ovr)

    -- 身价只提供有限溢价，避免 100+ OVR 特殊球员的超高身价继续传导成百万周薪。
    local value = player.value or 0
    if value > 0 then
        local valueWage = math.floor(value / 520)
        if valueWage > wage then
            local maxLiftRatio = isSpecialMarketPlayer(player) and 0.35 or 0.60
            if ovr >= 98 then
                maxLiftRatio = math.min(maxLiftRatio, 0.45)
            end
            local maxLift = math.floor(wage * maxLiftRatio)
            wage = wage + math.min(valueWage - wage, maxLift)
        end
    end

    -- 年龄：黄金期略高，老将略低
    local currentYear = (gameState and gameState.date and gameState.date.year) or 2025
    local age = player.getAge and player:getAge(currentYear) or (currentYear - (player.birthYear or 2000))
    if age <= 21 then
        wage = math.floor(wage * 0.88)
    elseif age <= 24 then
        wage = math.floor(wage * 0.95)
    elseif age >= 33 then
        wage = math.floor(wage * 0.72)
    elseif age >= 30 then
        wage = math.floor(wage * 0.85)
    end

    -- 潜力溢价（仅年轻球员）
    local pot = player.actualPotential or player.potential or ovr
    if age <= 23 and pot > ovr then
        local gap = math.min(15, pot - ovr)
        wage = math.floor(wage * (1.0 + gap * 0.025))
    end

    -- 球员名气 / 角色
    if player.isLegend then
        wage = math.floor(wage * 1.35)
    end
    if player.squadRole == "key" then
        wage = math.floor(wage * 1.12)
    elseif player.squadRole == "rotation" then
        wage = math.floor(wage * 1.04)
    end
    local rep = player.reputation or 30
    if rep >= 80 then wage = math.floor(wage * 1.15)
    elseif rep >= 60 then wage = math.floor(wage * 1.06)
    end

    -- 俱乐部声望加成（豪门球员要求更高）
    if team and (team.reputation or 0) >= 780 then
        wage = math.floor(wage * 1.08)
    end

    -- 合同类型折扣
    if opts.contractType == "youth" then
        wage = math.max(500, math.floor(wage * 0.18))
    elseif opts.contractType == "promote" then
        wage = math.max(1000, math.floor(wage * 0.55))
    end

    if opts.contractType ~= "youth" and opts.contractType ~= "promote"
        and isSpecialMarketPlayer(player) then
        local softCap = ovr >= 100 and 950000 or 850000
        if wage > softCap then
            wage = softCap + math.floor((wage - softCap) * 0.15)
        end
    end

    wage = math.floor(wage / 100) * 100
    wage = math.max(500, wage)

    if not opts.noFloor and player.wage and player.wage > 0 then
        wage = math.max(wage, player.wage)
    end

    return wage
end

--- 青训学院在训周薪（随能力缓慢上调，仍低于一线队）
function FinanceManager.estimateYouthAcademyWage(player, team, gameState)
    local market = FinanceManager.estimateMarketWage(player, team, gameState, { noFloor = true })
    return math.max(500, math.min(market, math.floor(market * 0.15 + (player.overall or 50) * 120)))
end

--- 提拔至一线队的建议周薪
function FinanceManager.estimateYouthPromoteWage(player, team, gameState)
    return FinanceManager.estimateMarketWage(player, team, gameState, { contractType = "promote" })
end

--- 球员当前工资相对市场的比例（<1 表示被低估）
function FinanceManager.getWageMarketRatio(player, team, gameState)
    local market = FinanceManager.estimateMarketWage(player, team, gameState, { noFloor = true })
    if market <= 0 then return 1.0 end
    return (player.wage or 0) / market
end

--- 更新负债周数并施加轻量财务惩罚
function FinanceManager._trackDebtConsequences(gameState, team)
    if not team.finance then team.finance = {} end
    if (team.balance or 0) < 0 then
        team.finance.debtWeeks = (team.finance.debtWeeks or 0) + 1
    else
        team.finance.debtWeeks = 0
    end

    local debtWeeks = team.finance.debtWeeks or 0
    team.finance.spendingFrozen = debtWeeks >= 4
    team.finance.transferRestricted = debtWeeks >= 8

    if debtWeeks == 4 and team.id == gameState.playerTeamId then
        gameState:sendMessage({
            category = "finance",
            title = "财务管制",
            body = "连续负债已触发董事会管制：设施升级与商业活动暂停，直至现金回正。",
            priority = "high",
        })
    elseif debtWeeks == 8 and team.id == gameState.playerTeamId then
        team.transferBudget = math.max(0, math.floor((team.transferBudget or 0) * 0.6))
        team.boardSatisfaction = math.max(0, (team.boardSatisfaction or 50) - 15)
        gameState:sendMessage({
            category = "finance",
            title = "严重财务危机",
            body = "董事会削减转会预算并下调满意度。请尽快出售高薪球员或降低开支。",
            priority = "high",
        })
    end
end

function FinanceManager.isSpendingFrozen(team)
    return team and team.finance and team.finance.spendingFrozen
end

function FinanceManager.isTransferRestricted(team)
    return team and team.finance and team.finance.transferRestricted
end

------------------------------------------------------
-- 经济规模系数（基于wageBudget，控制不同级别俱乐部收入比例）
------------------------------------------------------

--- 计算俱乐部经济规模系数
--- wageBudget 200K → 0.316, 1M → 0.707, 2M → 1.0, 4M → 1.414, 6M → 1.5(cap)
--- 使用 sqrt 映射避免线性差距过大，同时限制顶级球队收入不无限膨胀
function FinanceManager._getWageScale(team)
    if team._financialScale and team._financialScale > 0 then
        return math.max(0.25, math.min(1.5, team._financialScale))
    end
    local wb = team.wageBudget or team._baseWageBudget or 200000
    local scale = math.sqrt(wb / 2000000)
    return math.max(0.25, math.min(1.5, scale))
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
    if FinanceManager.isSpendingFrozen(team) then
        return false, "财务管制中，无法升级设施"
    end
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
    if facilityType == "youth" then
        team._youthFacilityFromRep = true  -- 手动升级后不再被声望初始化覆盖
    end

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
    local baseAmount = budgetBase * 0.15
    local amount = math.min(15000000, math.max(3000000, math.floor(baseAmount / 1000000) * 1000000))  -- 3M~15M，取整到百万

    -- 冷却检查：每赛季最多1次（应急救命，而非常规增收手段）
    if not team.finance then team.finance = {} end
    local injectCount = team.finance.boardInjectionsThisSeason or 0
    if injectCount >= 1 then
        return false, "本赛季已申请过注资，董事会拒绝了你的请求"
    end

    -- 执行注资（同时补充转会预算）
    team.balance = team.balance + amount
    team.transferBudget = (team.transferBudget or 0) + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.finance.boardInjectionsThisSeason = injectCount + 1

    -- 降低董事会满意度（一次性救命，代价显著）
    local satLoss = 35
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
    if FinanceManager.isSpendingFrozen(team) then
        return false, "财务管制中，无法开展赞助推介"
    end

    if not team.finance then team.finance = {} end

    -- 冷却检查：每赛季最多2次
    local seekCount = team.finance.sponsorSeeksThisSeason or 0
    if seekCount >= 2 then
        return false, "本赛季赞助推介次数已用完（2/2）"
    end

    -- 赞助金额 = 声望 * 随机系数（有可能失败）
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
    local successChance = 0.5 + rep / 200  -- 50 rep=75%, 80 rep=90%

    if Random() > successChance then
        team.finance.sponsorSeeksThisSeason = seekCount + 1
        return false, "赞助商对当前球队表现不感兴趣，推介失败"
    end

    local amount = math.floor(rep * 35000 + 1200000 + Random() * 1800000)  -- 约 1.2M~3M

    team.balance = team.balance + amount
    team.transferBudget = (team.transferBudget or 0) + math.floor(amount * 0.5)
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
    if FinanceManager.isSpendingFrozen(team) then
        return false, "财务管制中，无法举办商业活动"
    end

    if not team.finance then team.finance = {} end

    -- 冷却检查: 45天（避免沦为稳定增收手段）
    local COMMERCIAL_COOLDOWN_DAYS = 45
    local lastEvent = team.finance.lastCommercialEventDate
    if lastEvent then
        local daysSince = FinanceManager._daysBetween(lastEvent, gameState.date)
        if daysSince < COMMERCIAL_COOLDOWN_DAYS then
            local daysLeft = COMMERCIAL_COOLDOWN_DAYS - daysSince
            return false, string.format("商业活动冷却中，还需等待 %d 天", daysLeft)
        end
    end

    -- 收入 = 声望 + 球场容量影响
    local rep = (team.reputation or 500) / 10  -- 归一化到 0-100
    local capacity = team.stadiumCapacity or 30000
    local amount = math.floor(capacity * 18 + rep * 18000 + Random() * 900000)  -- 约 1M~2.5M

    team.balance = team.balance + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    team.transferBudget = (team.transferBudget or 0) + math.floor(amount * 0.3)
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
        body = string.format("举办商业活动获得 %s 收入。下次可用时间: %d天后。", FinanceManager.formatMoney(amount), COMMERCIAL_COOLDOWN_DAYS),
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
    return math.max(0, 45 - daysSince)
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

    -- 仅存在于青训名单、不在一线队 roster 的球员：不计入一线最低人数
    local inFirstTeam = false
    for _, pid in ipairs(team.playerIds or {}) do
        if pid == playerId then inFirstTeam = true break end
    end
    if not inFirstTeam then
        local YouthManager = require("scripts/systems/youth_manager")
        if YouthManager.isOnTeamYouthSquad(gameState, playerId, team.id) then
            return true, ""
        end
    end

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
                elseif pos == "CM" or pos == "CDM" or pos == "CAM" or pos == "LM" or pos == "RM" then
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
    team.finance.debtWeeks = 0
    team.finance.spendingFrozen = nil
    team.finance.transferRestricted = nil
    -- 商业活动CD跨赛季保留
end

------------------------------------------------------
-- 赛季末赞助合同绩效条款结算
-- position: 玩家球队最终排名, totalTeams: 联赛总球队数
------------------------------------------------------
function FinanceManager.settleSponsorPerformanceClauses(gameState, position, totalTeams)
    local team = gameState:getPlayerTeam()
    if not team or not team.sponsorContracts then return end

    local relegationZone = totalTeams - 2  -- 倒数3名为降级区

    for _, contract in pairs(team.sponsorContracts) do
        -- 前3名绩效奖金
        if position <= 3 and (contract.topFinishBonus or 0) > 0 then
            local bonus = contract.topFinishBonus
            team.balance = team.balance + bonus
            team.transferBudget = (team.transferBudget or 0) + bonus
            team.seasonIncome = (team.seasonIncome or 0) + bonus
            team.incomeBreakdown = team.incomeBreakdown or {}
            team.incomeBreakdown.sponsor = (team.incomeBreakdown.sponsor or 0) + bonus

            FinanceManager.addTransaction(team, {
                amount = bonus,
                description = string.format("%s 绩效奖金(第%d名)", contract.brand or "赞助商", position),
                category = "sponsor",
                season = gameState.season,
                week = FinanceManager._getWeekNumber(gameState),
            })
        end

        -- 降级罚款
        if position >= relegationZone and (contract.relegationPenalty or 0) > 0 then
            local penalty = contract.relegationPenalty
            team.balance = team.balance - penalty
            team.seasonExpense = (team.seasonExpense or 0) + penalty

            FinanceManager.addTransaction(team, {
                amount = -penalty,
                description = string.format("%s 降级违约金", contract.brand or "赞助商"),
                category = "sponsor",
                season = gameState.season,
                week = FinanceManager._getWeekNumber(gameState),
            })
        end
    end

    -- 汇总并通知玩家
    local totalBonus = 0
    local totalPenalty = 0
    if position <= 3 then
        for _, contract in pairs(team.sponsorContracts) do
            totalBonus = totalBonus + (contract.topFinishBonus or 0)
        end
    end
    if position >= relegationZone then
        for _, contract in pairs(team.sponsorContracts) do
            totalPenalty = totalPenalty + (contract.relegationPenalty or 0)
        end
    end

    if totalBonus > 0 then
        gameState:sendMessage({
            category = "finance",
            title = "赞助商绩效奖金",
            body = string.format("恭喜！球队以第%d名完赛，触发赞助合同绩效条款。\n绩效奖金总计: %s",
                position, FinanceManager.formatMoney(totalBonus)),
            priority = "normal",
        })
    end
    if totalPenalty > 0 then
        gameState:sendMessage({
            category = "finance",
            title = "赞助商降级罚款",
            body = string.format("球队不幸降级，触发赞助合同降级条款。\n违约金总计: %s",
                FinanceManager.formatMoney(totalPenalty)),
            priority = "high",
        })
    end
end

return FinanceManager
