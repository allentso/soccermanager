-- ui/message_action_handlers.lua
-- 收件箱 / Dashboard 弹窗共用的消息动作处理器（不含路由跳转）

local Constants = require("scripts/app/constants")
local FinanceManager = require("scripts/systems/finance_manager")

local MessageActionHandlers = {}

---@return boolean handled
---@return string|nil route
---@return table|nil params
function MessageActionHandlers.run(gameState, actionId, data)
    local handler = MessageActionHandlers.HANDLERS[actionId]
    if not handler then return false end
    return handler(gameState, data or {})
end

--- 执行动作（仅返回是否成功）
function MessageActionHandlers.execute(gameState, actionId, data)
    local ok = MessageActionHandlers.run(gameState, actionId, data)
    return ok == true
end

MessageActionHandlers.HANDLERS = {
    view_player = function(_gameState, data)
        return true, "player_detail", { playerId = data.playerId }
    end,
    renew_contract = function(_gameState, data)
        return true, "player_detail", { playerId = data.playerId, tab = "contract" }
    end,
    view_squad = function()
        return true, "squad", nil
    end,
    view_finance = function()
        return true, "finance", nil
    end,
    view_transfer = function()
        return true, "market", nil
    end,
    view_match = function(_gameState, data)
        return true, "match_result", data
    end,
    view_training = function()
        return true, "training", nil
    end,
    view_league = function()
        return true, "league", nil
    end,
    grant_raise = function(gameState, data)
        local player = gameState.players[data.playerId]
        if not player then return false end
        local raisePercent = data.raisePercent or 20
        local newWage = math.floor(player.wage * (1 + raisePercent / 100))
        local wageIncrease = newWage - player.wage
        if wageIncrease > 0 and not FinanceManager.withinWageBudget(gameState, player.teamId, wageIncrease) then
            gameState:sendMessage({
                category = "contract",
                title = "加薪失败",
                body = string.format("无法批准 %s 的加薪请求：超出工资预算。", player.displayName),
                priority = "normal",
            })
            return true
        end
        player.wage = newWage
        player.morale = Constants.clampMorale((player.morale or 60) + 12)
        gameState:sendMessage({
            category = "contract",
            title = "加薪批准",
            body = string.format("已批准 %s 加薪 %d%%，新周薪 %s。",
                player.displayName, raisePercent, FinanceManager.formatMoney(newWage)),
            priority = "normal",
        })
        return true
    end,
    deny_raise = function(gameState, data)
        local player = gameState.players[data.playerId]
        if not player then return false end
        player.morale = Constants.clampMorale((player.morale or 60) - 10)
        gameState:sendMessage({
            category = "contract",
            title = "加薪拒绝",
            body = string.format("已拒绝 %s 的加薪请求。球员士气下降。", player.displayName),
            priority = "normal",
        })
        return true
    end,
    promote_role = function(gameState, data)
        local player = gameState.players[data.playerId]
        if not player then return false end
        local MoraleManager = require("scripts/systems/morale_manager")
        local oldRole = player.squadRole
        player.squadRole = data.newRole or "rotation"
        MoraleManager.onSquadRoleChange(player, oldRole, player.squadRole)
        gameState:sendMessage({
            category = "squad",
            title = "角色调整",
            body = string.format("已将 %s 的阵容角色调整为「%s」。",
                player.displayName, data.roleLabel or player.squadRole),
            priority = "normal",
        })
        return true
    end,
    deny_promotion = function(gameState, data)
        local player = gameState.players[data.playerId]
        if not player then return false end
        player.morale = Constants.clampMorale((player.morale or 60) - 8)
        return true
    end,
    accept_loan_offer = function(gameState, data)
        local player = gameState.players[data.playerId]
        if not player then return false end
        player.squadRole = "loaned"
        player._loanedTo = data.targetTeamId
        player.morale = Constants.clampMorale((player.morale or 60) + 5)
        gameState:sendMessage({
            category = "transfer",
            title = "租借达成",
            body = string.format("%s 已租借至 %s。", player.displayName, data.targetTeamName or "对方球队"),
            priority = "normal",
        })
        return true
    end,
    reject_loan_offer = function(gameState, data)
        local player = gameState.players[data.playerId]
        if player then
            player.morale = Constants.clampMorale((player.morale or 60) - 5)
        end
        return true
    end,
    accept_nt_coach = function(gameState, data)
        if not data.nation then return false end
        local WorldCup = require("scripts/systems/world_cup")
        local EuroCup = require("scripts/systems/euro_cup")
        local isEuro = data.competition == "euro" or EuroCup.isEuroYear(gameState.season)
        local NT = isEuro and EuroCup or WorldCup
        gameState.nationalTeamCoach = { nation = data.nation, squad = nil, competition = isEuro and "euro" or "world_cup" }
        NT.clearPendingCoachInvite(gameState)
        gameState.ntCoachGuidancePending = true
        local compLabel = isEuro and "欧洲杯" or "世界杯"
        gameState:sendMessage({
            category = isEuro and "euro_cup" or "world_cup",
            title = "正式上任",
            body = string.format("你已正式出任%s国家队主教练！请前往选择%s大名单。",
                NT._getNationName(data.nation), compLabel),
            priority = "high",
        })
        return true, "national_squad_select", { nation = data.nation }
    end,
    decline_nt_coach = function(gameState, data)
        local WorldCup = require("scripts/systems/world_cup")
        local EuroCup = require("scripts/systems/euro_cup")
        local isEuro = (data and data.competition == "euro") or EuroCup.isEuroYear(gameState.season)
        local NT = isEuro and EuroCup or WorldCup
        gameState.nationalTeamCoach = nil
        NT.clearPendingCoachInvite(gameState)
        local compLabel = isEuro and "欧洲杯" or "世界杯"
        gameState:sendMessage({
            category = isEuro and "euro_cup" or "world_cup",
            title = "婉拒邀请",
            body = string.format("你婉拒了所有国家队的邀请。%s比赛将自动模拟。", compLabel),
            priority = "normal",
        })
        return true
    end,
    accept_job_offer = function(gameState, data)
        local JobManager = require("scripts/systems/job_manager")
        local success = JobManager.acceptOffer(gameState, data.teamId)
        if success then
            return true, "dashboard", nil
        end
        gameState:sendMessage({
            category = "job",
            title = "邀约已失效",
            body = "该职位已被其他教练填补，邀约已失效。",
            priority = "normal",
        })
        return true
    end,
    decline_job_offer = function(gameState, data)
        local JobManager = require("scripts/systems/job_manager")
        JobManager.declineOffer(gameState, data.teamId)
        return true
    end,
    accept_manager_renewal = function(gameState, _data)
        local JobManager = require("scripts/systems/job_manager")
        local success, err = JobManager.acceptManagerRenewal(gameState)
        if not success then
            gameState:sendMessage({
                category = "contract",
                title = "续约失败",
                body = err or "没有待处理的续约提议",
                priority = "normal",
            })
        end
        return true
    end,
    decline_manager_renewal = function(gameState, _data)
        local JobManager = require("scripts/systems/job_manager")
        JobManager.declineManagerRenewal(gameState)
        return true
    end,
    confirm_transfer = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.confirmTransfer(gameState, data.bidId)
        return true
    end,
    cancel_transfer = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.cancelTransferConfirmation(gameState, data.bidId)
        return true
    end,
    confirm_loan = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.confirmLoan(gameState, data.bidId)
        return true
    end,
    cancel_loan = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.cancelLoanConfirmation(gameState, data.bidId)
        return true
    end,
    confirm_free_agent = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.confirmFreeAgent(gameState, data.negoId)
        return true
    end,
    cancel_free_agent = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        TransferManager.cancelFreeAgentConfirmation(gameState, data.negoId)
        return true
    end,
    confirm_sale = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        return TransferManager.confirmSale(gameState, data.bidId) == true
    end,
    cancel_sale = function(gameState, data)
        local TransferManager = require("scripts/systems/transfer_manager")
        return TransferManager.cancelSale(gameState, data.bidId) == true
    end,
}

--- 执行动作并返回是否需要自动存档
function MessageActionHandlers.needsSave(actionId)
    return actionId == "confirm_sale" or actionId == "cancel_sale"
        or actionId == "confirm_transfer" or actionId == "cancel_transfer"
        or actionId == "confirm_loan" or actionId == "cancel_loan"
        or actionId == "confirm_free_agent" or actionId == "cancel_free_agent"
        or actionId == "accept_job_offer"
end

return MessageActionHandlers
