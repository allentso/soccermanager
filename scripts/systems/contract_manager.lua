-- systems/contract_manager.lua
-- 合同系统：到期检测、续约谈判、工资预算校验、提醒、自由球员释放

local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local ContractManager = {}

------------------------------------------------------
-- 每日处理：检查合同到期警告 + 处理续约谈判结果
------------------------------------------------------
function ContractManager.processDaily(gameState)
    -- 1) 处理待审核的续约谈判
    ContractManager._processRenewals(gameState)

    -- 2) 每月1号检查合同到期情况
    if gameState.date.day ~= 1 then return end

    local team = gameState:getPlayerTeam()
    if not team then return end

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and p.contractEnd and not p._loanOriginTeamId and p.squadRole ~= "loaned" then
            local monthsLeft = ContractManager._monthsUntilExpiry(gameState, p)

            -- 6个月内到期：提醒
            if monthsLeft <= 6 and monthsLeft > 3 then
                if not p._contractWarned6 then
                    p._contractWarned6 = true
                    gameState:sendMessage({
                        category = "contract",
                        title = "合同即将到期",
                        body = string.format("%s 的合同将在 %d 个月后到期。请考虑续约。",
                            p.displayName, monthsLeft),
                        priority = "normal",
                    })
                end
            -- 3个月内到期：紧急提醒
            elseif monthsLeft <= 3 and monthsLeft > 0 then
                if not p._contractWarned3 then
                    p._contractWarned3 = true
                    gameState:sendMessage({
                        category = "contract",
                        title = "合同紧急警告",
                        body = string.format(
                            "%s 的合同仅剩 %d 个月！如不续约，球员将成为自由球员离队。",
                            p.displayName, monthsLeft),
                        priority = "high",
                    })
                end
            end
        end
    end
end

------------------------------------------------------
-- 赛季结束：处理所有到期合同
------------------------------------------------------
function ContractManager.processSeasonEnd(gameState)
    -- 释放所有合同到期球员
    for teamId, team in pairs(gameState.teams) do
        local toRemove = {}
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and p.contractEnd then
                if ContractManager._isExpired(gameState, p) then
                    table.insert(toRemove, pid)
                end
            end
        end

        -- 释放球员
        for _, pid in ipairs(toRemove) do
            local p = gameState.players[pid]
            ContractManager._releasePlayer(gameState, team, p)
        end
    end
end

------------------------------------------------------
-- 续约接口（UI 调用）— 异步：球员考虑1-3天后回复
------------------------------------------------------
function ContractManager.renewContract(gameState, playerId, newWage, newYears)
    local player = gameState.players[playerId]
    if not player then return false, "球员不存在" end

    -- 租借球员不能续约（合同归属原俱乐部）
    if player._loanOriginTeamId or player.squadRole == "loaned" then
        return false, "租借球员无法续约，合同归属原俱乐部"
    end

    local team = gameState.teams[player.teamId]
    if not team then return false, "球员无所属球队" end

    -- 校验工资预算
    local FinanceManager = require("scripts/systems/finance_manager")
    local wageIncrease = newWage - (player.wage or 0)
    if wageIncrease > 0 and not FinanceManager.withinWageBudget(gameState, team.id, wageIncrease) then
        return false, "超出工资预算"
    end

    -- 检查是否已有待处理的续约谈判
    gameState._pendingRenewals = gameState._pendingRenewals or {}
    if gameState._pendingRenewals[playerId] then
        return false, "该球员正在考虑续约提议中"
    end

    -- 提交续约提议（球员考虑1-3天）
    local thinkDays = 1 + math.floor(Random() * 3)  -- 1~3天
    gameState._pendingRenewals[playerId] = {
        playerId = playerId,
        newWage = newWage,
        newYears = newYears,
        daysLeft = thinkDays,
    }

    gameState:sendMessage({
        category = "contract",
        title = "续约提议已提出",
        body = string.format("已向 %s 提出续约提议（周薪 %s，%d年）。球员需要时间考虑，预计 %d 天内答复。",
            player.displayName,
            FinanceManager.formatMoney(newWage),
            newYears,
            thinkDays),
        priority = "normal",
    })

    return true
end

------------------------------------------------------
-- 内部：处理续约谈判结果
------------------------------------------------------
function ContractManager._processRenewals(gameState)
    if not gameState._pendingRenewals then return end

    local FinanceManager = require("scripts/systems/finance_manager")
    local completed = {}

    for playerId, renewal in pairs(gameState._pendingRenewals) do
        renewal.daysLeft = renewal.daysLeft - 1
        if renewal.daysLeft <= 0 then
            table.insert(completed, playerId)

            local player = gameState.players[playerId]
            if not player then goto continue end

            local team = gameState.teams[player.teamId]
            if not team then goto continue end

            -- 球员接受意愿判定
            local acceptChance = ContractManager._calcAcceptChance(player, team, renewal.newWage, renewal.newYears, gameState)
            if Random() > acceptChance then
                -- 拒绝续约
                gameState:sendMessage({
                    category = "contract",
                    title = "续约被拒",
                    body = string.format("%s 经过考虑后拒绝了续约提议（周薪 %s，%d年）。球员希望获得更高薪水或寻求新挑战。",
                        player.displayName,
                        FinanceManager.formatMoney(renewal.newWage),
                        renewal.newYears),
                    priority = "normal",
                })
            else
                -- 续约成功
                local currentYear = gameState.date.year
                local currentMonth = gameState.date.month
                player.contractEnd = {
                    year = currentYear + renewal.newYears,
                    month = currentMonth,
                }
                player.wage = renewal.newWage

                -- 清除警告标记
                player._contractWarned6 = nil
                player._contractWarned3 = nil

                gameState:sendMessage({
                    category = "contract",
                    title = "续约成功",
                    body = string.format("%s 同意续约！新合同: 周薪 %s，%d 年（至 %d年%d月）。",
                        player.displayName,
                        FinanceManager.formatMoney(renewal.newWage),
                        renewal.newYears,
                        player.contractEnd.year,
                        player.contractEnd.month),
                    priority = "high",
                })
            end

            ::continue::
        end
    end

    for _, playerId in ipairs(completed) do
        gameState._pendingRenewals[playerId] = nil
    end
end

------------------------------------------------------
-- 获取续约建议参数
------------------------------------------------------
function ContractManager.getSuggestedTerms(player, team, gameState)
    local FinanceManager = require("scripts/systems/finance_manager")
    local marketWage = FinanceManager.estimateMarketWage(player, team, gameState)
    local currentWage = player.wage or 5000

    -- 建议工资：市场公平价，略高于当前合同以体现涨薪诉求
    local suggestedWage = math.max(marketWage, math.floor(currentWage * 1.05))
    suggestedWage = math.floor(suggestedWage / 100) * 100

    local currentYear = (gameState and gameState.date and gameState.date.year) or 2024
    local age = (player.birthYear and (currentYear - player.birthYear)) or 25
    local suggestedYears = 3
    if age >= 33 then suggestedYears = 1
    elseif age >= 30 then suggestedYears = 2
    elseif age <= 22 then suggestedYears = 4
    end

    return {
        wage = suggestedWage,
        years = suggestedYears,
        minWage = math.max(1000, math.floor(marketWage * 0.85)),
        maxWage = math.floor(marketWage * 1.35),
        marketWage = marketWage,
    }
end

------------------------------------------------------
-- 内部函数
------------------------------------------------------

-- 计算合同剩余月数
function ContractManager._monthsUntilExpiry(gameState, player)
    if not player.contractEnd then return 99 end
    local endYear = player.contractEnd.year or 2025
    local endMonth = player.contractEnd.month or 6

    local currentYear = gameState.date.year
    local currentMonth = gameState.date.month

    return (endYear - currentYear) * 12 + (endMonth - currentMonth)
end

-- 是否已过期
function ContractManager._isExpired(gameState, player)
    return ContractManager._monthsUntilExpiry(gameState, player) <= 0
end

-- 释放球员
function ContractManager._releasePlayer(gameState, team, player)
    -- 从球队中移除
    local newPlayerIds = {}
    for _, pid in ipairs(team.playerIds) do
        if pid ~= player.id then
            table.insert(newPlayerIds, pid)
        end
    end
    team.playerIds = newPlayerIds

    -- 从首发中移除：startingXI 是槽位表，清空对应槽位，不压缩索引
    if team.startingXI then
        for slot, pid in pairs(team.startingXI or {}) do
            if pid == player.id then
                team.startingXI[slot] = nil
            end
        end
    end

    -- 标记球员无队
    player.teamId = nil

    -- 消息通知（仅玩家球队）
    if team.id == gameState.playerTeamId then
        gameState:sendMessage({
            category = "contract",
            title = "球员离队",
            body = string.format("%s 合同到期，已成为自由球员离开球队。",
                player.displayName),
            priority = "high",
        })
    end
end

-- 计算球员接受续约的概率
function ContractManager._calcAcceptChance(player, team, offeredWage, offeredYears, gameState)
    local chance = 0.5

    -- 薪资涨幅影响
    local currentWage = player.wage or 5000
    local wageRatio = offeredWage / currentWage
    if wageRatio >= 1.5 then chance = chance + 0.3
    elseif wageRatio >= 1.2 then chance = chance + 0.2
    elseif wageRatio >= 1.0 then chance = chance + 0.1
    elseif wageRatio >= 0.8 then chance = chance - 0.1
    else chance = chance - 0.3
    end

    -- 球队声望影响
    local rep = team.reputation or 50
    if rep >= 80 then chance = chance + 0.15
    elseif rep >= 60 then chance = chance + 0.05
    elseif rep < 40 then chance = chance - 0.1
    end

    -- 球员年龄影响（老球员更愿意续约）
    local currentYear = (gameState and gameState.date and gameState.date.year) or 2024
    local age = (player.birthYear and (currentYear - player.birthYear)) or 25
    if age >= 32 then chance = chance + 0.15
    elseif age >= 28 then chance = chance + 0.05
    elseif age <= 22 then chance = chance - 0.05  -- 年轻人想去大俱乐部
    end

    -- 合同年限合理性
    if offeredYears >= 3 and age < 30 then chance = chance + 0.05
    elseif offeredYears <= 1 and age < 28 then chance = chance - 0.1
    end

    return math.max(0.1, math.min(0.95, chance))
end

------------------------------------------------------
-- 赛季末薪资审查（成长后重估合同工资）
------------------------------------------------------
function ContractManager.processSeasonWageReview(gameState)
    local FinanceManager = require("scripts/systems/finance_manager")

    for teamId, team in pairs(gameState.teams or {}) do
        local playerIds = {}
        for _, pid in ipairs(team.playerIds or {}) do table.insert(playerIds, pid) end
        for _, pid in ipairs(team._youthPlayerIds or {}) do table.insert(playerIds, pid) end

        for _, pid in ipairs(playerIds) do
            local player = gameState.players[pid]
            if not player or player.retired then goto continueReview end
            if player._loanOriginTeamId or player.squadRole == "loaned" then goto continueReview end

            local ratio = FinanceManager.getWageMarketRatio(player, team, gameState)
            local marketWage = FinanceManager.estimateMarketWage(player, team, gameState, { noFloor = true })

            if teamId == gameState.playerTeamId then
                -- 球员工资明显低于市场：发起加薪诉求（每赛季每球员最多一次）
                if ratio < 0.55 and not player._wageDemandSent then
                    player._wageDemandSent = true
                    player._wageDemandAmount = math.floor(marketWage * 0.92 / 100) * 100
                    gameState:sendMessage({
                        category = "contract",
                        title = "球员要求加薪",
                        body = string.format(
                            "%s 认为当前周薪 %s 低于其市场价值，希望涨至至少 %s。",
                            player.displayName,
                            FinanceManager.formatMoney(player.wage or 0),
                            FinanceManager.formatMoney(player._wageDemandAmount)),
                        priority = "normal",
                    })
                elseif ratio < 0.40 then
                    player.morale = math.max(30, (player.morale or 70) - 8)
                end
            else
                -- AI：低于市场 70% 则自动调整到 85% 市场工资
                if ratio < 0.70 then
                    player.wage = math.max(player.wage or 0, math.floor(marketWage * 0.85 / 100) * 100)
                end
            end

            ::continueReview::
        end
    end
end

--- 清除赛季加薪诉求标记（新赛季）
function ContractManager.resetSeasonWageFlags(gameState)
    for _, player in pairs(gameState.players or {}) do
        player._wageDemandSent = nil
        player._wageDemandAmount = nil
    end
end

------------------------------------------------------
-- 公共 API
------------------------------------------------------

--- 获取球员合同剩余月数
---@param gameState table
---@param player table
---@return number
function ContractManager.getMonthsRemaining(gameState, player)
    return ContractManager._monthsUntilExpiry(gameState, player)
end

--- 终止合同并支付赔偿金（玩家主动解约）
---@param gameState table
---@param playerId number
---@return boolean success
---@return number compensation 赔偿金额
function ContractManager.terminateContract(gameState, playerId)
    local player = gameState.players[playerId]
    if not player then return false, 0 end

    local team = gameState.teams[player.teamId]
    if not team then return false, 0 end

    -- 计算赔偿金（剩余合同薪资的50%）
    local monthsLeft = ContractManager._monthsUntilExpiry(gameState, player)
    local compensation = math.floor((player.wage or 0) * 4 * math.max(0, monthsLeft) * 0.5)

    -- 释放球员
    ContractManager._releasePlayer(gameState, team, player)
    player.listedForSale = false

    -- 扣除赔偿金
    team.balance = team.balance - compensation
    team.seasonExpense = (team.seasonExpense or 0) + compensation

    -- 交易记录
    local FinanceManager = require("scripts/systems/finance_manager")
    FinanceManager.addTransaction(team, {
        amount = -compensation,
        description = "终止合同: " .. player.displayName,
        category = "transfer",
        season = gameState.season,
    })

    gameState:sendMessage({
        category = "transfer",
        title = "合同已终止",
        body = string.format("%s 的合同已终止，支付赔偿金 %s。",
            player.displayName, FinanceManager.formatMoney(compensation)),
        priority = "normal",
    })

    return true, compensation
end

return ContractManager
