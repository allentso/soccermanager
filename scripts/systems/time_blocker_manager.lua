-- systems/time_blocker_manager.lua
-- 时间推进阻断管理器：检查是否有阻止推进时间的条件
-- warn=必须处理 info=提示可跳过

local Constants = require("scripts/app/constants")

local TimeBlockerManager = {}

---@class Blocker
---@field id string 阻断器标识
---@field severity "warn"|"info" warn=阻断 info=提示可跳过
---@field message string 显示文本
---@field target string 导航目标
---@field targetParams table|nil 路由参数

------------------------------------------------------
-- 核心接口：计算当前所有阻断项
------------------------------------------------------
---@param gameState table
---@return Blocker[]
function TimeBlockerManager.check(gameState)
    local blockers = {}

    -- 不依赖球队的决策类阻断（失业 / 国家队邀请等）
    TimeBlockerManager._checkJobOfferPending(gameState, blockers)
    TimeBlockerManager._checkNTCoachInvitePending(gameState, blockers)
    TimeBlockerManager._checkNTSquadUnconfirmed(gameState, blockers)
    TimeBlockerManager._checkManagerRenewalPending(gameState, blockers)

    local team = gameState:getPlayerTeam()
    if not team then return blockers end

    -- 1. 首发伤病：首发 XI 中有伤员
    TimeBlockerManager._checkInjuredXI(gameState, team, blockers)

    -- 2. 首发不足：健康球员填不满 11 人首发
    TimeBlockerManager._checkIncompleteXI(gameState, team, blockers)

    -- 3. 阵容规模危机：总球员不足 14 人（无法凑首发+替补）
    TimeBlockerManager._checkSquadSizeCrisis(gameState, team, blockers)

    -- 4. 计划离队危机：已确认离队将导致阵容 < 11 可用
    TimeBlockerManager._checkPlannedExitCrisis(gameState, team, blockers)

    -- 5. 关键球员合同风险：首发 TOP3 球员合同 3 个月内到期
    TimeBlockerManager._checkKeyContractRisk(gameState, team, blockers)

    -- 6. 工资预算风险：总工资超出预算 120%
    TimeBlockerManager._checkWageBudgetRisk(gameState, team, blockers)

    -- 7. 赛季目标未设定
    TimeBlockerManager._checkObjectivesNotSet(gameState, team, blockers)

    -- 8. 赞助合同未选择（赛季初必须处理）
    TimeBlockerManager._checkSponsorContract(gameState, team, blockers)

    -- 9. 出售待最终确认
    TimeBlockerManager._checkSaleConfirmationPending(gameState, team, blockers)

    -- 10. 买入待最终确认
    TimeBlockerManager._checkTransferSignPending(gameState, team, blockers)

    -- 11. 自由球员待最终确认
    TimeBlockerManager._checkFreeAgentSignPending(gameState, team, blockers)

    return blockers
end

------------------------------------------------------
-- 便捷接口：是否存在阻断（warn 级别）
------------------------------------------------------
---@param blockers Blocker[]
---@return boolean
function TimeBlockerManager.hasBlockingItems(blockers)
    for _, b in ipairs(blockers) do
        if b.severity == "warn" then return true end
    end
    return false
end

------------------------------------------------------
-- 内部检查函数
------------------------------------------------------

--- 1. 首发阵容有伤员（比赛日前一天才阻断）
function TimeBlockerManager._checkInjuredXI(gameState, team, blockers)
    if not team.startingXI or #team.startingXI == 0 then return end

    local injuredNames = {}
    for _, pid in ipairs(team.startingXI or {}) do
        local p = gameState.players[pid]
        if p and p.injured then
            table.insert(injuredNames, p.displayName)
        end
    end

    if #injuredNames > 0 then
        if TimeBlockerManager._hasMatchTomorrow(gameState) then
            table.insert(blockers, {
                id = "injured_xi",
                severity = "info",
                message = string.format("首发有 %d 名伤员（%s），明天有比赛",
                    #injuredNames,
                    #injuredNames <= 2 and table.concat(injuredNames, "、") or injuredNames[1] .. " 等"),
                target = "squad",
            })
        end
    end
end

--- 2. 首发不足 11 人且明天有比赛
function TimeBlockerManager._checkIncompleteXI(gameState, team, blockers)
    local startCount = team.startingXI and #team.startingXI or 0
    if startCount >= 11 then return end

    local available = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.injured and not p.retired then
            available = available + 1
        end
    end

    if available < 11 then return end

    if TimeBlockerManager._hasMatchTomorrow(gameState) then
        table.insert(blockers, {
            id = "incomplete_xi",
            severity = "warn",
            message = string.format("首发仅 %d 人（需11人），明天有比赛", startCount),
            target = "squad",
        })
    end
end

--- 3. 阵容规模危机：可用球员 < 14（首发 + 最低替补）
function TimeBlockerManager._checkSquadSizeCrisis(gameState, team, blockers)
    local available = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.injured and not p.retired then
            available = available + 1
        end
    end

    if available < 14 then
        local injured = #team.playerIds - available
        table.insert(blockers, {
            id = "squad_size_crisis",
            severity = "warn",
            message = string.format("可用球员仅 %d 人（%d 人伤退），急需补充阵容",
                available, injured),
            target = "squad",
        })
    end
end

--- 4. 计划离队危机：已确认出售/租借且离开后阵容 < 11
function TimeBlockerManager._checkPlannedExitCrisis(gameState, team, blockers)
    local TransferManager = require("scripts/systems/transfer_manager")

    local pendingExits = 0
    if TransferManager.getAcceptedOutgoingDeals then
        local deals = TransferManager.getAcceptedOutgoingDeals(gameState, team.id)
        pendingExits = deals and #deals or 0
    end

    if pendingExits == 0 then return end

    local currentCount = #team.playerIds
    local afterExits = currentCount - pendingExits

    if afterExits < 11 then
        table.insert(blockers, {
            id = "planned_exit_crisis",
            severity = "warn",
            message = string.format("确认离队 %d 人后阵容将仅剩 %d 人", pendingExits, afterExits),
            target = "squad",
        })
    end
end

--- 5. 关键球员合同风险：首发中 OVR 前 3 的球员合同 3 个月内到期
function TimeBlockerManager._checkKeyContractRisk(gameState, team, blockers)
    if not team.startingXI or #team.startingXI == 0 then return end

    local starters = {}
    for _, pid in ipairs(team.startingXI or {}) do
        local p = gameState.players[pid]
        if p then table.insert(starters, p) end
    end
    table.sort(starters, function(a, b) return (a.overall or 0) > (b.overall or 0) end)

    local atRisk = {}
    local checkCount = math.min(3, #starters)
    for i = 1, checkCount do
        local p = starters[i]
        if p.contractEnd then
            local monthsLeft = (p.contractEnd.year - gameState.date.year) * 12
                + (p.contractEnd.month - gameState.date.month)
            if monthsLeft <= 3 then
                table.insert(atRisk, p.displayName)
            end
        end
    end

    if #atRisk > 0 then
        table.insert(blockers, {
            id = "key_contract_risk",
            severity = "info",
            message = string.format("核心球员合同即将到期: %s", table.concat(atRisk, "、")),
            target = "squad",
        })
    end
end

--- 6. 工资预算风险：总工资超出预算 120%
function TimeBlockerManager._checkWageBudgetRisk(gameState, team, blockers)
    local FinanceManager = require("scripts/systems/finance_manager")
    local health = FinanceManager.getFinanceHealth(gameState, team.id)

    if type(health) == "table" then
        if health.wagePct and health.wagePct > 120 then
            table.insert(blockers, {
                id = "contract_wage_risk",
                severity = "info",
                message = string.format("工资支出超预算 %.0f%%，财务压力大", health.wagePct),
                target = "finance",
            })
        end
    elseif health == "critical" then
        table.insert(blockers, {
            id = "contract_wage_risk",
            severity = "warn",
            message = "财务处于危机状态，请采取紧急措施",
            target = "finance",
        })
    end
end

--- 7. 赛季目标未设定
function TimeBlockerManager._checkObjectivesNotSet(gameState, team, blockers)
    if not gameState.league or not gameState.league.standings then return end
    if gameState.objectives then return end

    table.insert(blockers, {
        id = "objectives_not_set",
        severity = "warn",
        message = "赛季目标未设定，请先与董事会确认本赛季目标",
        target = "dashboard",
        targetParams = { action = "set_objectives" },
    })
end

--- 8. 赞助合同未选择
function TimeBlockerManager._checkSponsorContract(gameState, team, blockers)
    local FinanceManager = require("scripts/systems/finance_manager")
    if FinanceManager.hasPendingSponsorChoice(team) then
        table.insert(blockers, {
            id = "sponsor_contract",
            severity = "warn",
            message = "新赛季赞助合同待签署，请选择赞助商方案",
            target = "sponsor_select",
        })
    end
end

--- 9. 董事会续约提议待回复
function TimeBlockerManager._checkManagerRenewalPending(gameState, blockers)
    if gameState._isUnemployed then return end
    if not gameState._managerRenewalOffer then return end

    table.insert(blockers, {
        id = "manager_renewal_pending",
        severity = "warn",
        message = "董事会向你发出了续约提议，请前往我的资料回复",
        target = "manager_view",
    })
end

--- 10. 失业状态下主教练邀约待回复
function TimeBlockerManager._checkJobOfferPending(gameState, blockers)
    local JobManager = require("scripts/systems/job_manager")
    JobManager.syncJobSeekingState(gameState)
    local count = JobManager.getPendingOfferCount(gameState)
    if count <= 0 then return end

    table.insert(blockers, {
        id = "job_offer_pending",
        severity = "warn",
        message = count == 1
            and "有 1 份主教练邀约待回复，请前往我的资料处理"
            or string.format("有 %d 份主教练邀约待回复，请前往我的资料处理", count),
        target = "manager_view",
        targetParams = { focus = "jobs" },
    })
end

--- 11. 出售待最终确认
function TimeBlockerManager._checkSaleConfirmationPending(gameState, team, blockers)
    local TransferManager = require("scripts/systems/transfer_manager")
    local pending = TransferManager.getPendingSaleConfirmations(gameState, team.id)
    if #pending == 0 then return end

    local first = pending[1]
    local message
    if #pending == 1 then
        message = string.format("出售 %s 的报价（%s）待你最终确认",
            first.playerName, first.buyerName or "买方")
    else
        message = string.format("%s 等 %d 笔出售待最终确认", first.playerName, #pending)
    end

    table.insert(blockers, {
        id = "sale_confirmation_pending",
        severity = "warn",
        message = message,
        target = "market",
        targetParams = { tab = "listed", highlightBidId = first.bidId },
    })
end

--- 12. 买入待最终确认
function TimeBlockerManager._checkTransferSignPending(gameState, team, blockers)
    local TransferManager = require("scripts/systems/transfer_manager")
    local pending = TransferManager.getPendingTransferSignConfirmations(gameState, team.id)
    if #pending == 0 then return end

    local first = pending[1]
    local message
    if #pending == 1 then
        message = string.format("签入 %s 的转会待你最终确认", first.playerName)
    else
        message = string.format("%s 等 %d 笔签入待最终确认", first.playerName, #pending)
    end

    table.insert(blockers, {
        id = "transfer_sign_pending",
        severity = "warn",
        message = message,
        target = "market",
        targetParams = { tab = "my_bids", highlightBidId = first.bidId },
    })
end

--- 13. 自由球员待最终确认
function TimeBlockerManager._checkFreeAgentSignPending(gameState, team, blockers)
    local TransferManager = require("scripts/systems/transfer_manager")
    local pending = TransferManager.getPendingFreeAgentSignConfirmations(gameState, team.id)
    if #pending == 0 then return end

    local first = pending[1]
    local message
    if #pending == 1 then
        message = string.format("自由球员 %s 待你最终确认签入", first.playerName)
    else
        message = string.format("%s 等 %d 名自由球员待最终确认", first.playerName, #pending)
    end

    table.insert(blockers, {
        id = "free_agent_sign_pending",
        severity = "warn",
        message = message,
        target = "market",
        targetParams = { tab = "free", highlightNegoId = first.negoId },
    })
end

--- 14. 国家队主教练邀请待回复
function TimeBlockerManager._checkNTCoachInvitePending(gameState, blockers)
    local WorldCup = require("scripts/systems/world_cup")
    if not WorldCup.hasPendingCoachInvite(gameState) then return end

    local pending = gameState._pendingNTCoachOffers
    local count = pending and pending.nations and #pending.nations or 0
    local targetParams = { tab = "all" }
    if pending and pending.inviteMessageId then
        targetParams.openMessageId = pending.inviteMessageId
    end

    table.insert(blockers, {
        id = "nt_coach_invite_pending",
        severity = "warn",
        message = count <= 1
            and "国家队向你发出主教练邀请，请回复是否接受"
            or string.format("%d 支国家队向你发出执教邀请，请回复是否接受", count),
        target = "inbox",
        targetParams = targetParams,
    })
end

--- 15. 国际大赛大名单未确认（开幕前 7 天内）
function TimeBlockerManager._checkNTSquadUnconfirmed(gameState, blockers)
    local WorldCup = require("scripts/systems/world_cup")
    local EuroCup = require("scripts/systems/euro_cup")

    local needs, nation, daysLeft
    if EuroCup.isEuroYear(gameState.season) then
        needs, nation, daysLeft = EuroCup.needsSquadConfirmationBlock(gameState)
        if needs then
            table.insert(blockers, {
                id = "nt_squad_unconfirmed",
                severity = "warn",
                message = string.format("欧洲杯 %d 天后开幕，国家队大名单尚未确认", daysLeft or 0),
                target = "national_squad_select",
                targetParams = { nation = nation },
            })
        end
        return
    end

    needs, nation, daysLeft = WorldCup.needsSquadConfirmationBlock(gameState)
    if not needs then return end

    table.insert(blockers, {
        id = "nt_squad_unconfirmed",
        severity = "warn",
        message = string.format("世界杯 %d 天后开幕，国家队大名单尚未确认", daysLeft or 0),
        target = "national_squad_select",
        targetParams = { nation = nation },
    })
end

------------------------------------------------------
-- 工具函数
------------------------------------------------------

--- 检查明天是否有比赛
function TimeBlockerManager._hasMatchTomorrow(gameState)
    if not gameState.league then return false end
    local League = require("scripts/domain/league")
    local TurnProcessor = require("scripts/core/turn_processor")
    local tomorrow = League._addDays(gameState.date, 1)
    local fixtures = TurnProcessor.getFixturesForDate(gameState, tomorrow)
    for _, f in ipairs(fixtures) do
        if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
            return true
        end
    end
    return false
end

return TimeBlockerManager
