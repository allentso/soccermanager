-- ui/components/tutorial_guide.lua
-- 新手指引系统
-- 步骤式引导覆盖层，通过高亮区域 + 说明文字介绍游戏各模块
-- 用法：
--   local TutorialGuide = require("scripts/ui/components/tutorial_guide")
--   TutorialGuide.start()  -- 显示指引
--   TutorialGuide.isCompleted()  -- 查询是否已完成

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")

local TutorialGuide = {}

------------------------------------------------------
-- 指引步骤定义
------------------------------------------------------
local STEPS = {
    {
        id = "welcome",
        icon = "⚽",
        title = "欢迎来到冠军之路！",
        desc = "作为新任主教练，你将管理俱乐部的方方面面——从球员阵容到战术部署，从转会市场到青训培养。让我们快速了解各个功能模块。",
        highlight = "center",  -- center = 居中展示，无特定高亮区
        navigateTo = nil,
    },
    {
        id = "dashboard",
        icon = "🏠",
        title = "主页 - 指挥中心",
        desc = "主页是你的「驾驶舱」，在这里你可以：\n• 查看下一场比赛信息\n• 点击「推进一天」推动时间流逝\n• 一键跳转到比赛日\n• 总览俱乐部财务和球队状态",
        highlight = "top",  -- 高亮顶部区域
        navigateTo = nil,
    },
    {
        id = "advance_day",
        icon = "⏩",
        title = "时间推进",
        desc = "足球经理是回合制游戏。每次点击顶栏的「▶ 推进」按钮，时间前进一天。\n\n当有重要事项（如未设阵容、合同谈判）未处理时，推进会被阻断并提示你。",
        highlight = "top",
        navigateTo = nil,
    },
    {
        id = "squad",
        icon = "👥",
        title = "球队 - 阵容管理",
        desc = "在球队页面，你可以：\n• 查看所有球员的能力、体能、士气\n• 设置首发11人和替补\n• 管理球员合同和薪资\n• 查看球员详细属性（点击球员）",
        highlight = "bottom",
        navigateTo = "squad",
    },
    {
        id = "tactics",
        icon = "📋",
        title = "战术 - 排兵布阵",
        desc = "战术页面让你选择：\n• 阵型（4-4-2、4-3-3、3-5-2 等）\n• 比赛风格（进攻/防守/控球/反击）\n• 每个位置的角色定义\n\n合理的战术搭配能大幅提升比赛表现！",
        highlight = "bottom",
        navigateTo = "tactics",
    },
    {
        id = "league",
        icon = "🏆",
        title = "赛事 - 联赛与杯赛",
        desc = "赛事页面展示：\n• 联赛积分榜和排名\n• 赛程和比赛结果\n• 欧冠（如果你的球队有资格）\n\n目标：带领球队夺得联赛冠军！",
        highlight = "bottom",
        navigateTo = "league",
    },
    {
        id = "market",
        icon = "💰",
        title = "市场 - 转会交易",
        desc = "在转会市场中你可以：\n• 浏览和搜索可用球员\n• 发起转会报价或租借\n• 管理转会预算\n• 签下自由球员\n\n球探系统可以帮你发掘潜力新星！",
        highlight = "bottom",
        navigateTo = "market",
    },
    {
        id = "training",
        icon = "🏋️",
        title = "训练 - 球员发展",
        desc = "训练系统影响球员的成长：\n• 设置训练强度（低/中/高）\n• 高强度提升更快但增加伤病风险\n• 年轻球员训练收益更大\n• 关注球员体能变化",
        highlight = "bottom",
        navigateTo = "training",
    },
    {
        id = "finance",
        icon = "📊",
        title = "财务 - 俱乐部经营",
        desc = "作为主教练你也需要关注预算：\n• 工资占比不宜过高\n• 转会支出需在预算内\n• 赛季奖金是重要收入来源\n• 注意董事会的财务目标",
        highlight = "center",
        navigateTo = "finance",
    },
    {
        id = "youth",
        icon = "🌱",
        title = "青训 - 未来之星",
        desc = "青训学院是俱乐部的未来：\n• 定期出现青训候选人\n• 签入潜力值高的年轻人\n• 通过训练培养他们\n• 年轻球员可能比昂贵的转会更值得",
        highlight = "center",
        navigateTo = "youth",
    },
    {
        id = "complete",
        icon = "🎉",
        title = "准备就绪！",
        desc = "你已经了解了所有核心功能。现在开始你的执教生涯吧！\n\n小贴士：\n• 随时在设置中重新查看本指引\n• 关注收件箱中的重要消息\n• 赛季目标是你的优先事项\n\n祝你早日夺冠！",
        highlight = "center",
        navigateTo = nil,
    },
}

------------------------------------------------------
-- 状态管理
------------------------------------------------------
local currentStep = 1
local isRunning = false  -- 防止指引运行期间重复触发

--- 检查是否已完成新手指引
function TutorialGuide.isCompleted()
    if not _G.gameState then return true end
    return _G.gameState.tutorialCompleted == true
end

--- 标记指引完成
local function markCompleted()
    if _G.gameState then
        _G.gameState.tutorialCompleted = true
    end
    isRunning = false
end

------------------------------------------------------
-- UI 构建
------------------------------------------------------

--- 构建进度指示器（小圆点）
local function buildProgressDots(current, total)
    local dots = {}
    for i = 1, total do
        table.insert(dots, UI.Panel {
            width = i == current and 18 or 8,
            height = 8,
            borderRadius = 4,
            backgroundColor = i == current and Theme.COLORS.GOLD or
                (i < current and {212, 175, 55, 120} or {255, 255, 255, 40}),
            marginRight = i < total and 4 or 0,
        })
    end
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        marginBottom = 20,
        children = dots,
    }
end

--- 构建步骤编号标签
local function buildStepBadge(current, total)
    return UI.Label {
        text = current .. "/" .. total,
        fontSize = 11,
        color = Theme.COLORS.TEXT_MUTED,
        marginBottom = 6,
    }
end

--- 构建指引卡片内容
local function buildStepCard(step, stepIndex, totalSteps, onNext, onPrev, onSkip)
    local isFirst = stepIndex == 1
    local isLast = stepIndex == totalSteps

    -- 图标
    local iconWidget = UI.Label {
        text = step.icon,
        fontSize = 40,
        textAlign = "center",
        marginBottom = 12,
    }

    -- 标题
    local titleWidget = UI.Label {
        text = step.title,
        fontSize = 18,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        textAlign = "center",
        marginBottom = 10,
    }

    -- 描述文字
    local descWidget = UI.Label {
        text = step.desc,
        fontSize = 13,
        color = Theme.COLORS.TEXT_SECONDARY,
        lineHeight = 1.5,
        textAlign = "left",
        marginBottom = 20,
    }

    -- 按钮行
    local buttons = {}

    -- 跳过按钮（非最后一步）
    if not isLast then
        table.insert(buttons, UI.Button {
            text = "跳过指引",
            width = 80,
            height = 34,
            fontSize = 12,
            color = Theme.COLORS.TEXT_MUTED,
            backgroundColor = {0, 0, 0, 0},
            onClick = onSkip,
        })
    end

    -- 弹性占位
    table.insert(buttons, UI.Panel { flexGrow = 1 })

    -- 上一步按钮（非第一步）
    if not isFirst then
        table.insert(buttons, UI.Button {
            text = "上一步",
            width = 72,
            height = 34,
            fontSize = 13,
            color = Theme.COLORS.TEXT_SECONDARY,
            backgroundColor = {255, 255, 255, 15},
            borderRadius = 8,
            marginRight = 8,
            onClick = onPrev,
        })
    end

    -- 下一步 / 完成按钮
    local nextText = isLast and "开始游戏" or "下一步"
    table.insert(buttons, UI.Button {
        text = nextText,
        width = isLast and 100 or 80,
        height = 34,
        fontSize = 13,
        color = {255, 255, 255, 255},
        backgroundColor = Theme.COLORS.GOLD,
        borderRadius = 8,
        fontWeight = "bold",
        onClick = onNext,
    })

    local buttonRow = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        children = buttons,
    }

    return UI.Panel {
        width = 310,
        maxWidth = "90%",
        backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
        borderRadius = 16,
        padding = 24,
        alignItems = "center",
        borderWidth = 1,
        borderColor = {212, 175, 55, 60},
        children = {
            buildStepBadge(stepIndex, totalSteps),
            iconWidget,
            titleWidget,
            buildProgressDots(stepIndex, totalSteps),
            descWidget,
            buttonRow,
        },
    }
end

--- 构建高亮提示箭头（指示高亮区域的视觉引导）
local function buildHighlightHint(highlight)
    if highlight == "top" then
        return UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 60,  -- 留出顶部状态栏高度(52) + 间距
            marginBottom = 8,
            children = {
                UI.Panel {
                    width = 200,
                    height = 44,
                    borderRadius = 22,
                    borderWidth = 2,
                    borderColor = {212, 175, 55, 180},
                    backgroundColor = {212, 175, 55, 20},
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "▲ 关注此区域",
                            fontSize = 12,
                            color = Theme.COLORS.GOLD,
                        },
                    },
                },
            },
        }
    elseif highlight == "bottom" then
        return UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 8,
            marginBottom = 68,  -- 留出底部导航栏高度(58) + 间距
            children = {
                UI.Panel {
                    width = 200,
                    height = 44,
                    borderRadius = 22,
                    borderWidth = 2,
                    borderColor = {212, 175, 55, 180},
                    backgroundColor = {212, 175, 55, 20},
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "▼ 关注底部导航",
                            fontSize = 12,
                            color = Theme.COLORS.GOLD,
                        },
                    },
                },
            },
        }
    end
    return nil
end

------------------------------------------------------
-- 核心流程
------------------------------------------------------

--- 显示当前步骤的 overlay
local function showStep()
    local step = STEPS[currentStep]
    if not step then return end

    local totalSteps = #STEPS

    local function onNext()
        if currentStep >= totalSteps then
            -- 完成指引
            markCompleted()
            UI.CloseOverlay()
            -- 回到 dashboard
            Router.replaceWith("dashboard")
            return
        end
        currentStep = currentStep + 1
        local nextStep = STEPS[currentStep]
        -- 如果步骤要求导航到特定页面，先导航
        if nextStep.navigateTo then
            Router.replaceWith(nextStep.navigateTo)
        elseif currentStep > 1 and STEPS[currentStep - 1].navigateTo then
            -- 如果从某个页面回到无导航步骤，回到 dashboard
            Router.replaceWith("dashboard")
        end
        showStep()
    end

    local function onPrev()
        if currentStep <= 1 then return end
        currentStep = currentStep - 1
        local prevStep = STEPS[currentStep]
        if prevStep.navigateTo then
            Router.replaceWith(prevStep.navigateTo)
        else
            Router.replaceWith("dashboard")
        end
        showStep()
    end

    local function onSkip()
        markCompleted()
        UI.CloseOverlay()
        Router.replaceWith("dashboard")
    end

    -- 布局容器内容
    local children = {}

    -- 高亮提示（顶部）
    if step.highlight == "top" then
        table.insert(children, buildHighlightHint("top"))
    end

    -- 弹性居中占位（上部）
    table.insert(children, UI.Panel { flexGrow = 1 })

    -- 指引卡片
    table.insert(children, buildStepCard(step, currentStep, totalSteps, onNext, onPrev, onSkip))

    -- 弹性居中占位（下部）
    table.insert(children, UI.Panel { flexGrow = 1 })

    -- 高亮提示（底部）
    if step.highlight == "bottom" then
        table.insert(children, buildHighlightHint("bottom"))
    end

    -- 构建全屏 overlay
    local overlay = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = {5, 8, 16, 210},
        justifyContent = "center",
        alignItems = "center",
        children = children,
    }

    UI.ShowOverlay(overlay)
end

------------------------------------------------------
-- 公开 API
------------------------------------------------------

--- 启动新手指引（从第一步开始）
function TutorialGuide.start()
    if isRunning then return end
    isRunning = true
    currentStep = 1
    showStep()
end

--- 从指定步骤开始（用于设置页面重看）
---@param stepId string 步骤 ID
function TutorialGuide.startFrom(stepId)
    if isRunning then return end
    isRunning = true
    for i, step in ipairs(STEPS) do
        if step.id == stepId then
            currentStep = i
            showStep()
            return
        end
    end
    -- fallback
    currentStep = 1
    showStep()
end

--- 获取所有步骤列表（用于设置页显示目录）
function TutorialGuide.getSteps()
    local result = {}
    for i, step in ipairs(STEPS) do
        table.insert(result, {
            id = step.id,
            icon = step.icon,
            title = step.title,
            index = i,
        })
    end
    return result
end

--- 获取步骤总数
function TutorialGuide.getStepCount()
    return #STEPS
end

return TutorialGuide
