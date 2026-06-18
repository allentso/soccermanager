-- systems/transfers/transfer_completion.lua
-- 完成转会所需的通用 helper，从 transfer_manager.lua 拆分。

return function(TransferManager)
    function TransferManager._getBidEffectiveValue(bid, player)
        local value = bid._effectiveValue or bid.amount or 0
        if bid.appearanceBonus then
            value = value + (bid.appearanceBonus.amount or 0) * 0.35
        end
        if bid.sellOnPercent and player then
            value = value + (player.value or 0) * bid.sellOnPercent / 100 * 0.25
        end
        return value
    end

    function TransferManager._requirePlayerConsentForTransfer(gameState, bid)
        local player = gameState.players[bid.playerId]
        local targetTeam = gameState.teams[bid.buyerTeamId]
        if not player or not targetTeam then return false, "转会信息不完整。" end

        local attitude = TransferManager.getPlayerTransferAttitude(gameState, player.id, targetTeam.id)
        if attitude == "refusing" then
            return false, string.format("%s 拒绝加盟 %s。", player.displayName, targetTeam.name)
        end

        local willing, reason = TransferManager._checkPlayerWillingness(gameState, player, targetTeam)
        if not willing then
            return false, string.format("%s 拒绝加盟 %s（%s）。", player.displayName, targetTeam.name, reason or "个人意愿不足")
        end

        -- 薪资满意度检查：如果报价薪资低于当前薪资的80%，球员可能拒绝
        if bid.wageOffer and player.wage then
            local wageRatio = bid.wageOffer / player.wage
            if wageRatio < 0.8 then
                -- 薪资降幅过大，大概率拒绝
                if Random() < 0.85 then
                    return false, string.format("%s 拒绝降薪加盟（当前周薪远高于报价）。", player.displayName)
                end
            elseif wageRatio < 0.95 then
                -- 略微降薪，有小概率拒绝
                if Random() < 0.3 then
                    return false, string.format("%s 对薪资条件不满意。", player.displayName)
                end
            end
        end

        return true
    end

    --- 租借：球员是否愿意外租（不永久转会，关注出场机会与承担工资比例）
    function TransferManager._requirePlayerConsentForLoan(gameState, bid)
        local player = gameState.players[bid.playerId]
        local targetTeam = gameState.teams[bid.buyerTeamId]
        local originTeam = gameState.teams[bid.sellerTeamId]
        if not player or not targetTeam then return false, "租借信息不完整。" end

        local attitude = TransferManager.getPlayerTransferAttitude(gameState, player.id, targetTeam.id)
        if attitude == "refusing" then
            return false, string.format("%s 拒绝外租至 %s。", player.displayName, targetTeam.name)
        end

        local willing, reason = TransferManager._checkPlayerWillingness(gameState, player, targetTeam)
        if not willing then
            return false, string.format("%s 不愿外租至 %s（%s）。", player.displayName, targetTeam.name, reason or "个人意愿不足")
        end

        local wageShare = bid.wageShare or 0.5
        if wageShare < 0.4 then
            if Random() < 0.7 then
                return false, string.format("%s 认为租借方承担的工资比例过低（%.0f%%）。", player.displayName, wageShare * 100)
            end
        elseif wageShare < 0.5 then
            if Random() < 0.25 then
                return false, string.format("%s 希望租借方承担更多工资。", player.displayName)
            end
        end

        -- 年轻球员 / 边缘球员更愿外租寻找出场
        if player.squadRole == "key" and originTeam then
            if (targetTeam.reputation or 0) < (originTeam.reputation or 0) * 0.85 then
                if Random() < 0.55 then
                    return false, string.format("%s 作为主力不愿降级外租。", player.displayName)
                end
            end
        end

        return true
    end

    function TransferManager._removePlayerFromTeam(team, playerId)
        if not team then return end
        for i = #(team.playerIds or {}), 1, -1 do
            if team.playerIds[i] == playerId then
                table.remove(team.playerIds, i)
            end
        end
        -- startingXI 是槽位表（稀疏 table，键为 1..11），用 pairs 遍历置 nil
        -- 不可用 # + table.remove：稀疏表 # 不可靠，且 table.remove 会错位移槽位
        if team.startingXI then
            for slot, pid in pairs(team.startingXI) do
                if pid == playerId then
                    team.startingXI[slot] = nil
                end
            end
        end
        -- 替补席同步移除：租借/转会后残留在 benchIds 会导致比赛中仍可上场
        if team.benchIds then
            for i = #(team.benchIds or {}), 1, -1 do
                if team.benchIds[i] == playerId then
                    table.remove(team.benchIds, i)
                end
            end
        end
        -- 青训名单同步移除：妖人转会后若残留在原队 _youthPlayerIds，
        -- 会被 YouthManager 的 AI 月度提拔覆盖 teamId/合同（BUG-20260611-06）
        if team._youthPlayerIds then
            for i = #(team._youthPlayerIds or {}), 1, -1 do
                if team._youthPlayerIds[i] == playerId then
                    table.remove(team._youthPlayerIds, i)
                end
            end
        end
        -- 挂牌列表同步移除
        if team.transferList then
            for i = #team.transferList, 1, -1 do
                if team.transferList[i] == playerId then
                    table.remove(team.transferList, i)
                end
            end
        end
        -- 角色字段清空：队长、点球手、任意球手、角球手
        if team.captain == playerId then team.captain = nil end
        if team.penaltyTaker == playerId then team.penaltyTaker = nil end
        if team.freeKickTaker == playerId then team.freeKickTaker = nil end
        if team.cornerTaker == playerId then team.cornerTaker = nil end
        -- 阵容方案 A/B 同步清理（防止切换方案时已售球员"复活"）
        if team.lineupPresets then
            for _, preset in pairs(team.lineupPresets) do
                if type(preset) == "table" then
                    if preset.startingXI then
                        for slot, pid in pairs(preset.startingXI) do
                            if pid == playerId then
                                preset.startingXI[slot] = nil
                            end
                        end
                    end
                    if preset.benchIds then
                        for i = #preset.benchIds, 1, -1 do
                            if preset.benchIds[i] == playerId then
                                table.remove(preset.benchIds, i)
                            end
                        end
                    end
                    -- 方案内角色字段
                    if preset.captain == playerId then preset.captain = nil end
                    if preset.penaltyTaker == playerId then preset.penaltyTaker = nil end
                    if preset.freeKickTaker == playerId then preset.freeKickTaker = nil end
                    if preset.cornerTaker == playerId then preset.cornerTaker = nil end
                end
            end
        end
        -- 训练分组同步移除
        if team.trainingGroups then
            for _, group in pairs(team.trainingGroups) do
                if group.playerIds then
                    for i = #group.playerIds, 1, -1 do
                        if group.playerIds[i] == playerId then
                            table.remove(group.playerIds, i)
                        end
                    end
                end
            end
        end
    end

    --- 从全部球队阵容移除球员（keepTeamId 可选：保留该队引用，用于即将加入的目标队）
    function TransferManager._removePlayerFromAllTeams(gameState, playerId, keepTeamId)
        for teamId, team in pairs(gameState.teams or {}) do
            if keepTeamId == nil or teamId ~= keepTeamId then
                TransferManager._removePlayerFromTeam(team, playerId)
            end
        end
    end

    --- 将球员归属到指定球队：先清全局残留引用，再加入目标队并更新 teamId
    --- @param opts table|nil { allowOverCap = boolean }
    --- @return boolean success
    function TransferManager._assignPlayerToTeam(gameState, player, teamId, opts)
        opts = opts or {}
        if not player or not teamId then return false end
        local team = gameState.teams[teamId]
        if not team then return false end

        local alreadyListed = false
        for _, pid in ipairs(team.playerIds or {}) do
            if pid == player.id then alreadyListed = true; break end
        end
        -- 有效上限：玩家转会窗内放宽到软顶（33），其余仍为常规上限（30）
        if not alreadyListed and not opts.allowOverCap and team:isSquadFullFor(gameState) then
            return false
        end

        -- 移除残留引用（替代原先对全部球队执行完整 _removePlayerFromTeam 的 O(球队×结构) 全扫描，
        -- 该全扫描是转会日卡顿主因之一）：
        --   1) 对球员「当前所属球队」做完整清理（含 startingXI/bench/战术方案等结构，球员确实离队）；
        --   2) 对其余球队仅做廉价的 playerIds 去重——运行时唯一会出现的多队污染就是 playerIds 重复
        --      （历史 bug / 损坏存档，见 roster_dup 回归）；纯战术结构 stale 引用由读档 Housekeeping 兜底。
        local fromTeamId = player.teamId
        if fromTeamId and fromTeamId ~= teamId then
            local fromTeam = gameState.teams[fromTeamId]
            if fromTeam then TransferManager._removePlayerFromTeam(fromTeam, player.id) end
        end
        for tid, otherTeam in pairs(gameState.teams or {}) do
            if tid ~= teamId and tid ~= fromTeamId then
                local pids = otherTeam.playerIds
                if pids then
                    for i = #pids, 1, -1 do
                        if pids[i] == player.id then table.remove(pids, i) end
                    end
                end
            end
        end
        -- 玩家窗内处于 30<人数<33 缓冲区时，需绕过 addPlayer 的 30 人硬顶
        local addOpts = opts
        if not opts.allowOverCap and team:isFirstTeamFull() and not team:isSquadFullFor(gameState) then
            addOpts = { allowOverCap = true }
        end
        if not team:addPlayer(player.id, addOpts) then
            return false
        end
        player.teamId = teamId
        -- 阵容已变更，使队均 OVR 缓存失效（同 pass 内后续撮合读到最新队均）
        if TransferManager._bumpTeamOvrGen then TransferManager._bumpTeamOvrGen() end
        return true
    end

    function TransferManager._addTransferTransaction(team, amount, description, date, gameState)
        if not team then return end
        local FinanceManager = require("scripts/systems/finance_manager")
        local tx = {
            amount = amount,
            description = description,
            category = "transfer",
            type = amount < 0 and "transfer_out" or "transfer_in",
            date = date,
        }
        if gameState then
            tx.season = gameState.season
            tx.week = FinanceManager._getWeekNumber(gameState)
        end
        FinanceManager.addTransaction(team, tx)
    end

    function TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)
        local date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        local installments = bid.installments

        if installments and #installments > 0 then
            local firstPay = installments[1].amount or 0
            buyerTeam.balance = buyerTeam.balance - firstPay
            buyerTeam.seasonExpense = (buyerTeam.seasonExpense or 0) + firstPay
            if sellerTeam then
                sellerTeam.balance = sellerTeam.balance + firstPay
                sellerTeam.transferBudget = (sellerTeam.transferBudget or 0) + firstPay
                sellerTeam.seasonIncome = (sellerTeam.seasonIncome or 0) + firstPay
            end
            TransferManager._addTransferTransaction(buyerTeam, -firstPay, "引进 " .. player.displayName .. "（首期）", date, gameState)
            TransferManager._addTransferTransaction(sellerTeam, firstPay, "出售 " .. player.displayName .. "（首期）", date, gameState)

            if not buyerTeam._pendingPayables then buyerTeam._pendingPayables = {} end
            if sellerTeam and not sellerTeam._pendingReceivables then sellerTeam._pendingReceivables = {} end
            for i = 2, #installments do
                local inst = installments[i]
                table.insert(buyerTeam._pendingPayables, {
                    amount = inst.amount,
                    dueDate = inst.dueDate,
                    toTeamId = sellerTeam and sellerTeam.id or nil,
                    playerId = player.id,
                })
                if sellerTeam then
                    table.insert(sellerTeam._pendingReceivables, {
                        amount = inst.amount,
                        dueDate = inst.dueDate,
                        fromTeamId = buyerTeam.id,
                        playerId = player.id,
                    })
                end
            end
        else
            buyerTeam.balance = buyerTeam.balance - bid.amount
            buyerTeam.seasonExpense = (buyerTeam.seasonExpense or 0) + bid.amount
            if sellerTeam then
                sellerTeam.balance = sellerTeam.balance + bid.amount
                sellerTeam.transferBudget = (sellerTeam.transferBudget or 0) + bid.amount
                sellerTeam.seasonIncome = (sellerTeam.seasonIncome or 0) + bid.amount
            end
            TransferManager._addTransferTransaction(buyerTeam, -bid.amount, "引进 " .. player.displayName, date, gameState)
            TransferManager._addTransferTransaction(sellerTeam, bid.amount, "出售 " .. player.displayName, date, gameState)
        end

        if buyerTeam.transferBudget then
            -- 委托额度模型：无论是否分期，转会预算一次性扣全额。
            -- 未付分期 = 已承诺负债，仍占用「可承诺额度」，避免分期凭空放大可买总额；
            -- 现金（balance）仍按分期逐期支付（见上方），只缓解现金流、不放大购买力。
            buyerTeam.transferBudget = math.max(0, buyerTeam.transferBudget - (bid.amount or 0))
        end
    end

    function TransferManager._attachFutureClauses(player, bid)
        if bid.sellOnPercent and bid.sellOnPercent > 0 then
            player._sellOnClause = {
                percent = bid.sellOnPercent,
                owedToTeamId = bid.sellerTeamId,
            }
        else
            player._sellOnClause = nil
        end
        if bid.appearanceBonus then
            player._appearanceBonusClause = {
                count = bid.appearanceBonus.count,
                amount = bid.appearanceBonus.amount,
                owedToTeamId = bid.sellerTeamId,
                startingAppearances = (player.seasonStats and player.seasonStats.appearances) or 0,
                paid = false,
            }
        else
            player._appearanceBonusClause = nil
        end
    end
end
