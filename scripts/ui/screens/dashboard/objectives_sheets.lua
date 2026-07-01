-- ui/screens/dashboard/objectives_sheets.lua
-- 赛季目标弹窗，从 dashboard.lua 拆分。

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local TurnProcessor = require("scripts/core/turn_processor")
local SaveManager = require("scripts/persistence/save_manager")
local FinanceManager = require("scripts/systems/finance_manager")
local TimeBlockerManager = require("scripts/systems/time_blocker_manager")
local BlockerDialog = require("scripts/ui/components/blocker_dialog")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local BottomSheet = require("scripts/ui/components/bottom_sheet")
local TeamIcon = require("scripts/ui/components/team_icon")
local WorldCup = require("scripts/systems/world_cup")
local EuroCup = require("scripts/systems/euro_cup")
local TransferManager = require("scripts/systems/transfer_manager")
local MessageManager = require("scripts/systems/message_manager")
local DomesticCup = require("scripts/systems/domestic_cup")
local ConfirmDialog = require("scripts/ui/components/confirm_dialog")
local DayAdvanceOverlay = require("scripts/ui/components/day_advance_overlay")
local MessageActionHandlers = require("scripts/ui/message_action_handlers")
local Market = require("scripts/ui/screens/market")
local sdk = sdk
local function _dashboard() return require("scripts/ui/screens/dashboard") end

local Mod = {}

function Mod.showDetail(gameState)
    local summary = ObjectivesManager.getSummary(gameState)

    -- 未设定目标 → 弹出选择界面
    if not summary.hasObjectives then
        Dashboard._showObjectiveSelection(gameState)
        return
    end

    -- 已有目标 → 展示详情
    local children = {}

    -- 赛季目标列表
    table.insert(children, UI.Label {
        text = "赛季目标",
        fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
        marginBottom = 8,
    })

    local seasonObjs = summary.allSeasonObjectives or {}
    for _, obj in ipairs(seasonObjs) do
        local statusIcon = obj.status == "completed" and "✓ " or obj.status == "failed" and "✗ " or "• "
        local statusColor = obj.status == "completed" and Theme.COLORS.FINANCE_GREEN
                         or obj.status == "failed" and Theme.COLORS.DANGER
                         or Theme.COLORS.TEXT_PRIMARY
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            marginBottom = 6, paddingLeft = 4,
            children = {
                UI.Label { text = statusIcon .. obj.text, fontSize = 13, color = statusColor },
            }
        })
    end

    -- 月度目标
    local monthlies = ObjectivesManager._getMonthlies(gameState.objectives)
    if #monthlies > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 10, marginBottom = 10 })
        table.insert(children, UI.Label {
            text = "本月目标",
            fontSize = 14, fontWeight = "bold", color = Theme.COLORS.TEXT_PRIMARY,
            marginBottom = 6,
        })
        for _, monthly in ipairs(monthlies) do
            local mColor = monthly.status == "completed" and Theme.COLORS.FINANCE_GREEN
                        or monthly.status == "failed" and Theme.COLORS.DANGER
                        or Theme.COLORS.INFO_BLUE
            local mIcon = monthly.status == "completed" and "✓ " or monthly.status == "failed" and "✗ " or "→ "
            local prog = ObjectivesManager.getMonthlyProgress(gameState, monthly, gameState:getPlayerTeam())
            table.insert(children, UI.Label {
                text = mIcon .. monthly.text .. "  (" .. (prog and prog.label or "—") .. ")",
                fontSize = 13, color = mColor, paddingLeft = 4, marginBottom = 4,
            })
        end
    end

    -- 进度条
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 12, marginBottom = 10 })
    local pct = summary.progressPct
    local pctColor = pct >= 60 and Theme.COLORS.FINANCE_GREEN
                  or pct >= 30 and Theme.COLORS.MATCH_ORANGE
                  or Theme.COLORS.DANGER
    table.insert(children, UI.Panel {
        width = "100%",
        children = {
            UI.Label {
                text = "总进度: " .. summary.completedCount .. "/" .. summary.totalCount .. " 完成 (" .. pct .. "%)",
                fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 4,
            },
            Theme.ProgressBar { value = pct, color = pctColor, height = 6 },
        }
    })

    BottomSheet.showCustom({
        title = "赛季目标",
        showCancel = true,
        children = children,
    })
end

------------------------------------------------------
-- 赛季目标选择界面
------------------------------------------------------
function Mod.showSelection(gameState, initSelected)
    local proposals = ObjectivesManager.generateProposals(gameState)

    -- 跟踪选中状态
    local selected = initSelected or { league = nil, ucl = nil, finance = nil }

    if not initSelected then
        for _, opt in ipairs(proposals.league) do
            if opt.recommended then selected.league = opt.id; break end
        end
        for _, opt in ipairs(proposals.ucl) do
            if opt.recommended then selected.ucl = opt.id; break end
        end
        for _, opt in ipairs(proposals.finance) do
            if opt.recommended then selected.finance = opt.id; break end
        end
    end

    -- 存储按钮引用，用于原地更新
    local leagueButtons = {}   -- { {btn=widget, id=optId, text=baseText}, ... }
    local uclButtons = {}
    local financeButtons = {}
    local hintContainer = nil  -- 预算提示容器
    local hintLabel = nil      -- 预算提示文本

    -- 计算预算提示内容（联赛+欧冠两项累计）
    local function calcBudgetHint()
        local team = gameState:getPlayerTeam()
        if not team then return nil end
        local tierOrder = { elite = 4, strong = 3, mid = 2, weak = 1 }
        local teamTier = ObjectivesManager._getTier(gameState)
        local teamW = tierOrder[teamTier] or 2

        -- 累计各类目标的档次偏移
        local totalDiff = 0
        local count = 0

        -- 联赛
        if selected.league then
            for _, obj in ipairs(proposals.league) do
                if obj.id == selected.league then
                    totalDiff = totalDiff + ((tierOrder[obj.tier] or teamW) - teamW)
                    count = count + 1
                    break
                end
            end
        end

        -- 欧冠
        if selected.ucl and proposals.inUCL then
            for _, obj in ipairs(proposals.ucl) do
                if obj.id == selected.ucl then
                    totalDiff = totalDiff + ((tierOrder[obj.tier] or teamW) - teamW)
                    count = count + 1
                    break
                end
            end
        end

        if totalDiff == 0 or count == 0 then return nil end

        -- 根据累计偏移计算预算影响百分比
        if totalDiff < 0 then
            local cutPct
            if totalDiff == -1 then cutPct = 15
            elseif totalDiff == -2 then cutPct = 30
            elseif totalDiff == -3 then cutPct = 45
            else cutPct = 60 end
            return { text = string.format("⚠️ 降低目标：董事会将削减 %d%% 预算", cutPct), color = Theme.COLORS.WARNING }
        else
            local boostPct
            if totalDiff == 1 then boostPct = 8
            elseif totalDiff == 2 then boostPct = 15
            else boostPct = 20 end
            return { text = string.format("📈 挑战更高目标：董事会将追加 %d%% 预算", boostPct), color = Theme.COLORS.SECONDARY }
        end
    end

    -- 刷新所有按钮外观（原地更新，无需重建）
    local function refreshButtons()
        local selColor = Theme.COLORS.INFO_BLUE
        local normalColor = Theme.COLORS.TEXT_SECONDARY
        local selBg = {30, 60, 90, 255}
        local normalBg = Theme.COLORS.BG_SURFACE

        for _, item in ipairs(leagueButtons) do
            local isSel = (selected.league == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end
        for _, item in ipairs(uclButtons) do
            local isSel = (selected.ucl == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end
        for _, item in ipairs(financeButtons) do
            local isSel = (selected.finance == item.id)
            item.btn:SetText((isSel and "● " or "○ ") .. item.text)
            item.btn:SetStyle({ width = "100%", backgroundColor = isSel and selBg or normalBg, color = isSel and selColor or normalColor })
        end

        -- 更新预算提示
        local hint = calcBudgetHint()
        if hint and hintContainer and hintLabel then
            hintLabel:SetText(hint.text)
            hintLabel:SetStyle({ color = hint.color })
            hintContainer:SetStyle({
                backgroundColor = {hint.color[1], hint.color[2], hint.color[3], 25},
                height = 32,
                overflow = "visible",
            })
        elseif not hint and hintContainer then
            hintContainer:SetStyle({ height = 0, overflow = "hidden" })
        end
    end

    -- 构建内容
    local children = {}

    table.insert(children, UI.Label {
        text = "董事会希望你确定本赛季目标，请从以下选项中选择：",
        fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginBottom = 12,
    })

    -- 联赛目标
    table.insert(children, UI.Label {
        text = "联赛目标", fontSize = 13, fontWeight = "bold",
        color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
    })
    for _, opt in ipairs(proposals.league) do
        local isSelected = (selected.league == opt.id)
        local optId = opt.id
        local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
        local btn = UI.Button {
            text = (isSelected and "● " or "○ ") .. baseText,
            width = "100%", height = 36, marginBottom = 4,
            backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
            borderRadius = 6, fontSize = 12,
            color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
            textAlign = "left", paddingLeft = 12,
            onClick = function()
                selected.league = optId
                refreshButtons()
            end,
        }
        table.insert(leagueButtons, { btn = btn, id = optId, text = baseText })
        table.insert(children, btn)
    end

    -- 欧冠目标
    if proposals.inUCL and #proposals.ucl > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 8, marginBottom = 8 })
        table.insert(children, UI.Label {
            text = "欧冠目标", fontSize = 13, fontWeight = "bold",
            color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
        })
        for _, opt in ipairs(proposals.ucl) do
            local isSelected = (selected.ucl == opt.id)
            local optId = opt.id
            local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
            local btn = UI.Button {
                text = (isSelected and "● " or "○ ") .. baseText,
                width = "100%", height = 36, marginBottom = 4,
                backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
                borderRadius = 6, fontSize = 12,
                color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
                textAlign = "left", paddingLeft = 12,
                onClick = function()
                    selected.ucl = optId
                    refreshButtons()
                end,
            }
            table.insert(uclButtons, { btn = btn, id = optId, text = baseText })
            table.insert(children, btn)
        end
    end

    -- 财务目标
    if #proposals.finance > 0 then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 8, marginBottom = 8 })
        table.insert(children, UI.Label {
            text = "财务目标", fontSize = 13, fontWeight = "bold",
            color = Theme.COLORS.TEXT_PRIMARY, marginBottom = 6,
        })
        for _, opt in ipairs(proposals.finance) do
            local isSelected = (selected.finance == opt.id)
            local optId = opt.id
            local baseText = opt.text .. (opt.recommended and " (推荐)" or "")
            local btn = UI.Button {
                text = (isSelected and "● " or "○ ") .. baseText,
                width = "100%", height = 36, marginBottom = 4,
                backgroundColor = isSelected and {30, 60, 90, 255} or Theme.COLORS.BG_SURFACE,
                borderRadius = 6, fontSize = 12,
                color = isSelected and Theme.COLORS.INFO_BLUE or Theme.COLORS.TEXT_SECONDARY,
                textAlign = "left", paddingLeft = 12,
                onClick = function()
                    selected.finance = optId
                    refreshButtons()
                end,
            }
            table.insert(financeButtons, { btn = btn, id = optId, text = baseText })
            table.insert(children, btn)
        end
    end

    -- 预算影响提示（始终存在，初始根据状态显示/隐藏）
    local initHint = calcBudgetHint()
    hintLabel = UI.Label {
        text = initHint and initHint.text or "",
        fontSize = 11,
        color = initHint and initHint.color or Theme.COLORS.TEXT_MUTED,
    }
    hintContainer = UI.Panel {
        width = "100%", marginTop = 10, marginBottom = 4,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 10, paddingRight = 10, paddingTop = 6, paddingBottom = 6,
        backgroundColor = initHint and {initHint.color[1], initHint.color[2], initHint.color[3], 25} or {0,0,0,0},
        borderRadius = 6,
        height = initHint and 32 or 0,
        overflow = initHint and "visible" or "hidden",
        children = { hintLabel },
    }
    table.insert(children, hintContainer)

    -- 确认按钮
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = Theme.COLORS.DIVIDER, marginTop = 12, marginBottom = 12 })
    table.insert(children, UI.Button {
        text = "确认目标",
        width = "100%", height = 44,
        backgroundColor = Theme.COLORS.PRIMARY,
        borderRadius = 8, fontSize = 14, fontWeight = "bold",
        color = {255, 255, 255, 255},
        onClick = function()
            local ids = {}
            if selected.league then table.insert(ids, selected.league) end
            if selected.ucl then table.insert(ids, selected.ucl) end
            if selected.finance then table.insert(ids, selected.finance) end
            ObjectivesManager.confirmObjectives(gameState, ids)
            BottomSheet.close()
            Router.replaceWith("dashboard")
        end,
    })

    -- 底部留白，避免被关闭按钮遮挡
    table.insert(children, UI.Panel { width = "100%", height = 60 })

    BottomSheet.showCustom({
        title = "设定赛季目标",
        showCancel = true,
        height = 620,
        children = children,
    })
end

------------------------------------------------------
-- [顶栏] 队徽图标 + 身份切换（整合版）

return Mod
