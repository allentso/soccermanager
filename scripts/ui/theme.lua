-- ui/theme.lua
-- UI主题配置和通用组件工厂
-- 设计语言：视觉层级分明 / 语义色高亮 / 足球氛围

local Constants = require("scripts/app/constants")
local UI = require("urhox-libs/UI")
local AudioManager = require("scripts/systems/audio_manager")

local Theme = {}

Theme.COLORS = Constants.COLORS

------------------------------------------------------
-- 统一位置颜色（门将黄、后卫蓝、中场绿、前锋红）
------------------------------------------------------

--- 根据位置代码返回统一颜色
---@param pos string 位置代码如 "GK", "CB", "LB", "RB", "CM", "ST" 等
---@return table RGBA颜色
function Theme.posColor(pos)
    if pos == "GK" then
        return {255, 204, 0, 255}       -- 门将：黄色
    elseif pos == "CB" or pos == "LB" or pos == "RB" then
        return {77, 179, 255, 255}      -- 后卫：蓝色
    elseif pos == "ST" or pos == "LW" or pos == "RW" then
        return {255, 102, 102, 255}     -- 前锋：红色
    else
        return {102, 255, 128, 255}     -- 中场：绿色（CM, CDM, CAM）
    end
end

------------------------------------------------------
-- 卡片系统 - 三级视觉层级
------------------------------------------------------

-- 普通卡片（基础信息展示）
function Theme.Card(props)
    return UI.Panel {
        width = "100%",
        backgroundColor = props.backgroundColor or Theme.COLORS.BG_CARD,
        borderRadius = 14,
        padding = 14,
        marginBottom = props.marginBottom or 10,
        borderWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        onClick = props.onClick,
        children = props.children or {},
    }
end

-- 高亮卡片（重要信息，如下一场比赛、紧急通知）
function Theme.HeroCard(props)
    local accentColor = props.accentColor or Theme.COLORS.GOLD
    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
        borderRadius = 14,
        padding = 16,
        marginBottom = 12,
        borderLeftWidth = props.borderLeft ~= false and 3 or 0,
        borderColor = accentColor,
        children = props.children or {},
    }
end

-- 迷你卡片（用于 2 列布局中的简洁信息块）
function Theme.MiniCard(props)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = "45%",
        backgroundColor = Theme.COLORS.BG_CARD,
        borderRadius = 10,
        padding = 12,
        marginRight = props.marginRight or 0,
        marginBottom = 10,
        onClick = props.onClick or nil,
        children = props.children or {},
    }
end

------------------------------------------------------
-- 导航系统
------------------------------------------------------

-- 顶部状态栏
function Theme.TopBar(props)
    return UI.Panel {
        width = "100%",
        height = 52,
        backgroundColor = props.backgroundColor or Theme.COLORS.BG_HEADER,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 14,
        paddingRight = 14,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = props.children or {},
    }
end

-- 底部导航栏
function Theme.BottomNav(props)
    return UI.Panel {
        width = "100%",
        height = 58,
        backgroundColor = Theme.COLORS.BG_HEADER,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-around",
        borderTopWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = props.children or {},
    }
end

-- 导航按钮
function Theme.NavButton(props)
    local isActive = props.active or false
    return UI.Panel {
        width = 64,
        height = 42,
        justifyContent = "center",
        alignItems = "center",
        borderRadius = 10,
        backgroundColor = isActive and "rgba(212,175,55,0.15)" or Theme.COLORS.TRANSPARENT,
        onClick = props.onClick,
        children = {
            UI.Label {
                text = props.label or "",
                fontSize = 12,
                fontWeight = isActive and "bold" or "normal",
                color = isActive and Theme.COLORS.GOLD or Theme.COLORS.TEXT_MUTED,
            },
        },
    }
end

-- 二级导航标签栏
function Theme.SubNav(items, activeKey)
    local Router = require("scripts/app/router")
    local tabs = {}
    for _, item in ipairs(items) do
        local isActive = item.key == activeKey
        table.insert(tabs, UI.Panel {
            height = 32,
            paddingLeft = 14,
            paddingRight = 14,
            backgroundColor = isActive and "rgba(212,175,55,0.15)" or Theme.COLORS.TRANSPARENT,
            borderRadius = 16,
            borderWidth = isActive and 1 or 0,
            borderColor = "rgba(212,175,55,0.4)",
            justifyContent = "center",
            alignItems = "center",
            marginRight = 6,
            onClick = function()
                if not isActive then
                    Router.replaceWith(item.screen, item.params)
                end
            end,
            children = {
                UI.Label {
                    text = item.label,
                    fontSize = 13,
                    color = isActive and Theme.COLORS.GOLD or Theme.COLORS.TEXT_SECONDARY,
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        })
    end
    return UI.Panel {
        width = "100%",
        height = 44,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = Theme.COLORS.BG_HEADER,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = tabs,
    }
end

-- 球队组二级导航
function Theme.SquadSubNav(activeKey)
    return Theme.SubNav({
        { key = "squad",    label = "阵容", screen = "squad" },
        { key = "training", label = "训练", screen = "training" },
        { key = "tactics",  label = "战术", screen = "tactics" },
        { key = "youth",    label = "青训", screen = "youth" },
        { key = "staff",    label = "职员", screen = "staff" },
    }, activeKey)
end

-- 消息/新闻组二级导航
function Theme.MoreSubNav(activeKey)
    return Theme.SubNav({
        { key = "inbox",   label = "消息", screen = "inbox" },
        { key = "news",    label = "新闻", screen = "news" },
    }, activeKey)
end

-- 市场组二级导航
function Theme.MarketSubNav(activeKey)
    return Theme.SubNav({
        { key = "market",       label = "转会市场", screen = "market" },
        { key = "transfer_hub", label = "转会中心", screen = "transfer_hub" },
        { key = "scouting",     label = "球探", screen = "scouting" },
    }, activeKey)
end

-- 全局统一底部导航栏
function Theme.MainNav(activeTab)
    local Router = require("scripts/app/router")
    -- 国家队模式下"赛事"默认跳世界杯视图
    local isNTMode = _G.gameState and _G.gameState.currentRole == "national_team"
        and _G.gameState.nationalTeamCoach ~= nil and (_G.gameState.worldCup ~= nil or _G.gameState.euroCup ~= nil)
    return Theme.BottomNav {
        children = {
            Theme.NavButton {
                label = "赛事",
                active = (activeTab == "league"),
                onClick = function()
                    if activeTab ~= "league" then
                        if isNTMode then
                            Router.navigate("league", { tab = "WC" })
                        else
                            Router.navigate("league")
                        end
                    end
                end,
            },
            Theme.NavButton {
                label = "球队",
                active = (activeTab == "squad"),
                onClick = function()
                    if activeTab ~= "squad" then
                        if isNTMode then
                            local ntCoach = _G.gameState.nationalTeamCoach
                            if ntCoach.squadConfirmed then
                                Router.navigate("tactics")
                            else
                                Router.navigate("national_squad_select", { nation = ntCoach.nation })
                            end
                        else
                            Router.navigate("squad")
                        end
                    end
                end,
            },
            Theme.NavButton {
                label = "主页",
                active = (activeTab == "home"),
                onClick = function()
                    if activeTab ~= "home" then Router.navigate("dashboard") end
                end,
            },
            Theme.NavButton {
                label = "市场",
                active = (activeTab == "market"),
                onClick = function()
                    if activeTab ~= "market" then Router.navigate("market") end
                end,
            },
        }
    }
end

------------------------------------------------------
-- 文本组件
------------------------------------------------------

function Theme.Title(props)
    return UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 18,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginBottom = props.marginBottom or 8,
    }
end

function Theme.Subtitle(props)
    return UI.Label {
        text = props.text or "",
        fontSize = props.fontSize or 13,
        color = props.color or Theme.COLORS.TEXT_SECONDARY,
        marginBottom = props.marginBottom or 4,
    }
end

-- 带语义色的节标题（用于 Dashboard 各区块）
function Theme.SectionHeader(props)
    local color = props.color or Theme.COLORS.GOLD
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 10,
        children = {
            -- 左侧色条
            props.showBar ~= false and UI.Panel {
                width = 3, height = 16,
                backgroundColor = color,
                borderRadius = 2,
                marginRight = 8,
            } or UI.Panel { width = 0 },
            UI.Label {
                text = props.text or "",
                fontSize = 15,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                flexGrow = 1,
            },
            -- 右侧附加内容
            props.rightChild or UI.Panel { width = 0 },
        }
    }
end

------------------------------------------------------
-- 数据展示组件
------------------------------------------------------

function Theme.StatPill(props)
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = props.bgColor or Theme.COLORS.BG_SURFACE,
        borderRadius = 6,
        paddingLeft = 8,
        paddingRight = 8,
        paddingTop = 4,
        paddingBottom = 4,
        marginRight = 6,
        marginBottom = 4,
        children = {
            UI.Label {
                text = props.label or "",
                fontSize = 11,
                color = Theme.COLORS.TEXT_MUTED,
                marginRight = 4,
            },
            UI.Label {
                text = tostring(props.value or ""),
                fontSize = 12,
                color = props.valueColor or Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
            },
        }
    }
end

-- 大数字展示（用于关键指标如余额、排名）
function Theme.BigStat(props)
    return UI.Panel {
        alignItems = props.align or "flex-start",
        children = {
            UI.Label {
                text = props.label or "",
                fontSize = 11,
                color = Theme.COLORS.TEXT_MUTED,
                marginBottom = 2,
            },
            UI.Label {
                text = tostring(props.value or ""),
                fontSize = props.fontSize or 22,
                color = props.color or Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
            },
        }
    }
end

-- 进度条组件
function Theme.ProgressBar(props)
    local pct = math.max(0, math.min(100, props.value or 0))
    local barColor = props.color or Theme.COLORS.PRIMARY
    return UI.Panel {
        width = "100%",
        height = props.height or 8,
        backgroundColor = Theme.COLORS.BG_SURFACE,
        borderRadius = (props.height or 8) / 2,
        overflow = "hidden",
        children = {
            UI.Panel {
                width = pct .. "%",
                height = "100%",
                backgroundColor = barColor,
                borderRadius = (props.height or 8) / 2,
            },
        }
    }
end

------------------------------------------------------
-- 环形指标（圆弧百分比） - 用离散圆点排列成环形
-- props: value(0-100), size, thickness, color, label, sublabel, segments
------------------------------------------------------
function Theme.RingGauge(props)
    local pct = math.max(0, math.min(100, props.value or 0))
    local size = props.size or 56
    local thickness = props.thickness or 4
    local color = props.color or Theme.COLORS.PRIMARY
    local bgColor = props.bgColor or Theme.COLORS.BG_SURFACE

    -- 圆点数量根据尺寸自动计算（越大越多点）
    local numDots = props.segments or math.max(12, math.floor(size * 0.7))
    local dotSize = math.max(2, math.floor(thickness * 0.9))
    local radius = (size - dotSize) / 2  -- 圆点中心距容器中心的距离
    local filledCount = math.floor(numDots * pct / 100)

    -- 生成圆点 children（从顶部12点钟位置顺时针排列）
    local dots = {}
    for i = 1, numDots do
        -- 角度：从 -90°（顶部）开始，顺时针
        local angle = math.rad(-90 + (i - 1) * 360 / numDots)
        local cx = radius * math.cos(angle)
        local cy = radius * math.sin(angle)
        -- 转换为 left/top（相对于容器中心）
        local left = math.floor(size / 2 + cx - dotSize / 2)
        local top = math.floor(size / 2 + cy - dotSize / 2)

        local isFilled = (i <= filledCount)
        dots[#dots + 1] = UI.Panel {
            width = dotSize, height = dotSize,
            borderRadius = dotSize / 2,
            backgroundColor = isFilled and color or {color[1], color[2], color[3], 35},
            position = "absolute",
            left = left, top = top,
        }
    end

    -- 中心文字
    dots[#dots + 1] = UI.Panel {
        width = size, height = size,
        position = "absolute",
        alignItems = "center", justifyContent = "center",
        children = {
            UI.Label {
                text = props.label or (pct .. "%"),
                fontSize = props.labelSize or math.floor(size / 4),
                color = color, fontWeight = "bold",
            },
            props.sublabel and UI.Label {
                text = props.sublabel,
                fontSize = math.floor(size / 6.5),
                color = Theme.COLORS.TEXT_MUTED, marginTop = 1,
            } or nil,
        }
    }

    return UI.Panel {
        width = size, height = size,
        children = dots,
    }
end

------------------------------------------------------
-- 多段条形图（并排的小条）
-- props: segments = { {value, color, label}, ... }, height, showLabels
------------------------------------------------------
function Theme.SegmentBar(props)
    local segments = props.segments or {}
    local total = 0
    for _, seg in ipairs(segments) do total = total + (seg.value or 0) end
    if total == 0 then total = 1 end

    local barH = props.height or 8
    local bars = {}
    for i, seg in ipairs(segments) do
        local pct = math.floor(seg.value / total * 100)
        if pct > 0 then
            table.insert(bars, UI.Panel {
                width = pct .. "%",
                height = "100%",
                backgroundColor = seg.color or Theme.COLORS.PRIMARY,
                borderTopLeftRadius = i == 1 and barH / 2 or 0,
                borderBottomLeftRadius = i == 1 and barH / 2 or 0,
                borderTopRightRadius = i == #segments and barH / 2 or 0,
                borderBottomRightRadius = i == #segments and barH / 2 or 0,
            })
        end
    end

    local legendItems = {}
    if props.showLabels then
        for _, seg in ipairs(segments) do
            table.insert(legendItems, UI.Panel {
                flexDirection = "row", alignItems = "center", marginRight = 10,
                children = {
                    UI.Panel { width = 6, height = 6, borderRadius = 3, backgroundColor = seg.color, marginRight = 3 },
                    UI.Label { text = seg.label or "", fontSize = 9, color = Theme.COLORS.TEXT_MUTED },
                }
            })
        end
    end

    return UI.Panel {
        width = "100%",
        children = {
            UI.Panel {
                width = "100%", height = barH,
                flexDirection = "row",
                backgroundColor = Theme.COLORS.BG_SURFACE,
                borderRadius = barH / 2,
                overflow = "hidden",
                children = bars,
            },
            #legendItems > 0 and UI.Panel {
                width = "100%", flexDirection = "row", flexWrap = "wrap", marginTop = 4,
                children = legendItems,
            } or nil,
        }
    }
end

------------------------------------------------------
-- 迷你条形图（竖条柱状图）
-- props: data = {n1, n2, ...}, barCount, height, color, highlightLast
------------------------------------------------------
function Theme.MiniBarChart(props)
    local data = props.data or {}
    local barCount = props.barCount or #data
    local chartH = props.height or 32
    local color = props.color or Theme.COLORS.INFO_BLUE
    local highlightLast = props.highlightLast ~= false

    local maxVal = 0
    for _, v in ipairs(data) do if v > maxVal then maxVal = v end end
    if maxVal == 0 then maxVal = 1 end

    -- 取最后 barCount 个数据
    local startIdx = math.max(1, #data - barCount + 1)
    local bars = {}
    for i = startIdx, #data do
        local v = data[i]
        local h = math.max(2, math.floor(v / maxVal * chartH))
        local isLast = (i == #data)
        table.insert(bars, UI.Panel {
            flexGrow = 1,
            height = chartH,
            justifyContent = "flex-end",
            alignItems = "center",
            marginLeft = 1, marginRight = 1,
            children = {
                UI.Panel {
                    width = "100%",
                    height = h,
                    backgroundColor = (highlightLast and isLast) and color or {color[1], color[2], color[3], 120},
                    borderTopLeftRadius = 2,
                    borderTopRightRadius = 2,
                },
            }
        })
    end

    return UI.Panel {
        width = "100%", height = chartH,
        flexDirection = "row",
        alignItems = "flex-end",
        children = bars,
    }
end

------------------------------------------------------
-- 球员行组件
------------------------------------------------------
function Theme.PlayerRow(props)
    local player = props.player
    if not player then return UI.Panel{height=0} end

    local posColor = Theme.posColor(player.position)

    return UI.Panel {
        width = "100%",
        height = 52,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            UI.Panel {
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                borderRadius = 3,
                paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                marginRight = 6, minWidth = 42,
                children = {
                    UI.Label {
                        text = Constants.POSITION_NAMES[player.position] or player.position,
                        fontSize = 10,
                        color = posColor,
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = player.displayName or (player.firstName .. " " .. player.lastName),
                fontSize = 14,
                color = Theme.COLORS.TEXT_PRIMARY,
                flexGrow = 1,
            },
            UI.Label {
                text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                fontSize = 14,
                color = player.overall >= 70 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_SECONDARY,
                width = 30,
                fontWeight = "bold",
            },
            UI.Label {
                text = player.injured and "伤" or tostring(player.fitness),
                fontSize = 12,
                color = player.injured and Theme.COLORS.DANGER or Theme.COLORS.TEXT_MUTED,
                width = 30,
            },
        },
        onClick = props.onClick,
    }
end

------------------------------------------------------
-- 分隔线 & 按钮
------------------------------------------------------

function Theme.Divider()
    return UI.Panel {
        width = "100%",
        height = 1,
        backgroundColor = Theme.COLORS.BORDER,
        marginTop = 6,
        marginBottom = 6,
    }
end

function Theme.PrimaryButton(props)
    local originalOnClick = props.onClick
    return UI.Panel {
        width = props.width or "100%",
        height = props.height or 48,
        borderRadius = 24,
        backgroundColor = props.color or Theme.COLORS.GOLD,
        justifyContent = "center",
        alignItems = "center",
        shadowColor = "rgba(212,175,55,0.3)",
        shadowOffset = { x = 0, y = 3 },
        shadowRadius = 10,
        onClick = originalOnClick and function(self)
            AudioManager.tap()
            originalOnClick(self)
        end or nil,
        children = {
            ---@diagnostic disable-next-line: param-type-mismatch
            UI.Label {
                text = props.text or "确认",
                fontSize = 15,
                fontWeight = "bold",
                color = "#1A1A1A",
                letterSpacing = 1,
            },
        },
    }
end

function Theme.SecondaryButton(props)
    local originalOnClick = props.onClick
    return UI.Panel {
        width = props.width or "100%",
        height = props.height or 48,
        borderRadius = 24,
        backgroundColor = "rgba(255,255,255,0.06)",
        borderWidth = 1,
        borderColor = "rgba(255,255,255,0.2)",
        justifyContent = "center",
        alignItems = "center",
        onClick = originalOnClick and function(self)
            AudioManager.tap()
            originalOnClick(self)
        end or nil,
        children = {
            UI.Label {
                text = props.text or "取消",
                fontSize = 15,
                color = Theme.COLORS.TEXT_SECONDARY,
                letterSpacing = 1,
            },
        },
    }
end

return Theme
