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

        return true
    end

    function TransferManager._removePlayerFromTeam(team, playerId)
        if not team then return end
        for i, pid in ipairs(team.playerIds or {}) do
            if pid == playerId then
                table.remove(team.playerIds, i)
                break
            end
        end
        if team.startingXI then
            for i, pid in ipairs(team.startingXI) do
                if pid == playerId then
                    table.remove(team.startingXI, i)
                    break
                end
            end
        end
    end

    function TransferManager._addTransferTransaction(team, amount, description, date)
        if not team then return end
        if not team.transactions then team.transactions = {} end
        table.insert(team.transactions, 1, {
            type = amount < 0 and "transfer_out" or "transfer_in",
            amount = amount,
            description = description,
            date = date,
        })
    end

    function TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player)
        local date = {year = gameState.date.year, month = gameState.date.month, day = gameState.date.day}
        local installments = bid.installments

        if installments and #installments > 0 then
            local firstPay = installments[1].amount or 0
            buyerTeam.balance = buyerTeam.balance - firstPay
            if sellerTeam then sellerTeam.balance = sellerTeam.balance + firstPay end
            TransferManager._addTransferTransaction(buyerTeam, -firstPay, "引进 " .. player.displayName .. "（首期）", date)
            TransferManager._addTransferTransaction(sellerTeam, firstPay, "出售 " .. player.displayName .. "（首期）", date)

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
            if sellerTeam then sellerTeam.balance = sellerTeam.balance + bid.amount end
            TransferManager._addTransferTransaction(buyerTeam, -bid.amount, "引进 " .. player.displayName, date)
            TransferManager._addTransferTransaction(sellerTeam, bid.amount, "出售 " .. player.displayName, date)
        end

        if buyerTeam.transferBudget then
            buyerTeam.transferBudget = math.max(0, buyerTeam.transferBudget - (installments and installments[1] and installments[1].amount or bid.amount))
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
