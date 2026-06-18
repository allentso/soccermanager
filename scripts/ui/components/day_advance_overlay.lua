-- ui/components/day_advance_overlay.lua
-- 多天时间推进时的进度遮罩：分帧执行 advanceDay，避免界面假死

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")

local DayAdvanceOverlay = {}

local _running = false

function DayAdvanceOverlay.isRunning()
    return _running
end

--- 分帧推进若干天，并显示进度遮罩
--- @param opts table
---   totalSteps: number 最多推进天数
---   stepFn: fun(stepIndex: number): string, ... 返回非 "continue" 时提前结束
---   onComplete: fun(reason: string, ...) 全部完成或提前结束时回调
---   gameState?: table 用于显示当前日期、设置 turnState
---   title?: string
---   message?: string
---   minStepsForOverlay?: number 至少多少天才显示遮罩（默认 2）
---   warmupFrames?: number 显示遮罩后先空转几帧再开始干活（默认：有遮罩时 2，否则 0）
--- @return boolean 是否成功启动（已在运行时返回 false）
function DayAdvanceOverlay.run(opts)
    if _running then return false end

    local totalSteps = math.max(tonumber(opts.totalSteps) or 1, 1)
    local minStepsForOverlay = opts.minStepsForOverlay or 2
    local showOverlay = totalSteps >= minStepsForOverlay
    local stepFn = opts.stepFn
    local onComplete = opts.onComplete
    local gameState = opts.gameState
    local title = opts.title or "正在推进时间"
    local message = opts.message or "AI 球队正在训练、转会和模拟比赛，游戏没有卡死，请稍候…"
    local singleStep = (totalSteps == 1)
    local warmupFrames = opts.warmupFrames
    if warmupFrames == nil then
        warmupFrames = showOverlay and 2 or 0
    end
    local warmupRemaining = warmupFrames

    if not stepFn then return false end

    local currentStep = 0
    local progressBar
    local progressLabel
    local dateLabel

    local function updateUI()
        if not showOverlay then return end
        if singleStep then
            if progressLabel then
                progressLabel:SetText("处理中，请稍候…")
            end
            if progressBar then
                progressBar:SetStyle({ width = "60%" })
            end
        else
            local pct = math.floor(currentStep / totalSteps * 100)
            if progressBar then
                progressBar:SetStyle({ width = pct .. "%" })
            end
            if progressLabel then
                progressLabel:SetText(string.format("已推进 %d / %d 天", currentStep, totalSteps))
            end
        end
        if dateLabel and gameState and gameState.getDateString then
            dateLabel:SetText("当前日期：" .. gameState:getDateString())
        end
    end

    local function finish(reason, ...)
        _running = false
        if gameState then
            gameState.turnState = "idle"
        end
        if showOverlay then
            UI.CloseOverlay()
        end
        if onComplete then
            onComplete(reason, ...)
        end
    end

    local scheduleNext

    local function runStep()
        currentStep = currentStep + 1
        updateUI()

        local reason, extra = stepFn(currentStep)
        if reason and reason ~= "continue" then
            finish(reason, extra)
            return
        end

        if currentStep >= totalSteps then
            finish("done")
            return
        end

        scheduleNext(runStep)
    end

    -- 等若干帧让遮罩先绘制，再执行重活（避免 ShowOverlay 同帧被 advanceDay 阻塞导致看不见）
    scheduleNext = function(fn)
        SubscribeToEvent("PostUpdate", function()
            UnsubscribeFromEvent("PostUpdate")
            if warmupRemaining > 0 then
                warmupRemaining = warmupRemaining - 1
                updateUI()
                scheduleNext(fn)
                return
            end
            fn()
        end)
    end

    _running = true
    if gameState then
        gameState.turnState = "processing"
    end

    if showOverlay then
        progressBar = UI.Panel {
            height = 8,
            width = singleStep and "60%" or "0%",
            backgroundColor = Theme.COLORS.MATCH_ORANGE,
            borderRadius = 4,
        }
        progressLabel = UI.Label {
            text = singleStep and "处理中，请稍候…" or string.format("已推进 0 / %d 天", totalSteps),
            fontSize = 13,
            color = Theme.COLORS.TEXT_PRIMARY,
            fontWeight = "bold",
            marginBottom = 6,
        }
        dateLabel = UI.Label {
            text = gameState and gameState.getDateString and ("当前日期：" .. gameState:getDateString()) or "",
            fontSize = 12,
            color = Theme.COLORS.TEXT_SECONDARY,
            marginBottom = 14,
        }

        UI.ShowOverlay(UI.Panel {
            width = "100%",
            height = "100%",
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = {0, 0, 0, 170},
            children = {
                UI.Panel {
                    width = 300,
                    backgroundColor = Theme.COLORS.BG_CARD,
                    borderRadius = 12,
                    padding = 20,
                    alignItems = "center",
                    onClick = function() end,
                    children = {
                        UI.Label {
                            text = title,
                            fontSize = 16,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                            marginBottom = 8,
                        },
                        UI.Label {
                            text = message,
                            fontSize = 12,
                            color = Theme.COLORS.TEXT_SECONDARY,
                            textAlign = "center",
                            marginBottom = 16,
                        },
                        progressLabel,
                        dateLabel,
                        UI.Panel {
                            width = "100%",
                            height = 8,
                            backgroundColor = {38, 46, 71, 255},
                            borderRadius = 4,
                            overflow = "hidden",
                            marginBottom = 10,
                            children = { progressBar },
                        },
                        UI.Label {
                            text = "请勿关闭游戏",
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                        },
                    },
                },
            },
        })
    end

    scheduleNext(runStep)

    return true
end

return DayAdvanceOverlay
