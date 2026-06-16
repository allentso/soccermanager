-- ui/components/transfer_limit_dialog.lua
-- 本转会窗重复转会/租借/签约限制 — 统一弹窗

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local TransferManager = require("scripts/systems/transfer_manager")

local TransferLimitDialog = {}

local function _windowHint(gameState)
    if not gameState or not gameState.date then
        return "下一转会窗开放后再试。"
    end
    local month = gameState.date.month
    if month >= 6 and month <= 8 then
        return "当前为夏窗（6–8 月），冬窗（1 月）开放后可再次操作。"
    elseif month == 1 then
        return "当前为冬窗（1 月），夏窗（6–8 月）开放后可再次操作。"
    end
    return "下一转会窗（夏窗 6–8 月 / 冬窗 1 月）开放后再试。"
end

--- 显示「本窗已转会」说明弹窗
--- @param playerName string|nil
--- @param gameState table|nil 用于生成窗期提示
function TransferLimitDialog.show(playerName, gameState)
    local name = playerName or "该球员"
    local ok, AudioManager = pcall(require, "scripts/systems/audio_manager")
    if ok and AudioManager.deny then AudioManager.deny() end

    ConfirmDialog.show({
        title = "重复转会限制",
        message = string.format(
            "%s 在本转会窗已参与过转会、租借或签约。\n\n同一球员每个转会窗只能完成一次流动，本次操作无法继续。\n\n%s",
            name, _windowHint(gameState)),
        confirmText = "知道了",
        cancelText = "关闭",
        confirmColor = Theme.COLORS.WARNING,
        onConfirm = function() end,
        onCancel = function() end,
    })
end

--- 若 err 为窗期限制错误则弹窗并返回 true
function TransferLimitDialog.handleError(err, playerName, gameState)
    if TransferManager.isWindowMoveLimitError(err) then
        TransferLimitDialog.show(playerName, gameState)
        return true
    end
    return false
end

--- 若球员本窗已流动则弹窗并返回 true（主动拦截入口）
function TransferLimitDialog.guardPlayer(gameState, playerId)
    if TransferManager.hasMovedInCurrentWindow(gameState, playerId) then
        local player = gameState.players[playerId]
        TransferLimitDialog.show(player and player.displayName, gameState)
        return true
    end
    return false
end

return TransferLimitDialog
