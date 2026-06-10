-- ui/components/player_card.lua
-- 通用球员卡片/行组件
-- 用法：
--   local PlayerCard = require("scripts/ui/components/player_card")
--   PlayerCard.Row { player = p, gameState = gs, showStarter = true, onClick = fn, onLongPress = fn }
--   PlayerCard.CompactRow { player = p, onClick = fn }
--   PlayerCard.DetailCard { player = p, gameState = gs }

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Constants = require("scripts/app/constants")

local PlayerCard = {}

-- 位置分类映射
local POS_GROUP_MAP = {
    GK = "GK",
    CB = "DEF", LB = "DEF", RB = "DEF",
    CDM = "MID", CM = "MID", LM = "MID", RM = "MID", CAM = "MID",
    LW = "FWD", RW = "FWD", ST = "FWD", CF = "FWD",
}

-- 位置颜色（统一使用 Theme.posColor）
local function getPosColor(position)
    return Theme.posColor(position)
end

-- 能力颜色
local function getOverallColor(overall)
    if overall >= 75 then return Theme.COLORS.SECONDARY
    elseif overall >= 65 then return Theme.COLORS.TEXT_PRIMARY
    end
    return Theme.COLORS.TEXT_SECONDARY
end

-- 体能颜色
local function getFitnessColor(fitness)
    if fitness >= 75 then return Theme.COLORS.SECONDARY
    elseif fitness >= 60 then return Theme.COLORS.WARNING
    end
    return Theme.COLORS.DANGER
end

-- 获取状态文本和颜色
local function getStatus(player)
    if player.injured then
        return "伤", Theme.COLORS.DANGER
    elseif player.fitness and player.fitness < 60 then
        return "疲", Theme.COLORS.DANGER
    elseif player.fitness and player.fitness < 75 then
        return "疲", Theme.COLORS.WARNING
    elseif player.morale and player.morale < 40 then
        return "低", Theme.COLORS.WARNING
    end
    return "", Theme.COLORS.TEXT_MUTED
end

-- 计算合同剩余月数
local function getContractMonths(player, gameState)
    if not player.contractEnd or not gameState then return nil end
    return (player.contractEnd.year - gameState.date.year) * 12
        + (player.contractEnd.month - gameState.date.month)
end

--- 完整球员行（阵容页使用）
--- @param props table
---   player: Player - 球员对象
---   gameState?: GameState - 游戏状态（用于计算年龄、合同）
---   isStarter?: boolean - 是否首发
---   showFitness?: boolean - 是否显示体能（默认 true）
---   showWage?: boolean - 是否显示工资（默认 true）
---   showContract?: boolean - 是否显示合同到期警告（默认 true）
---   onClick?: function
---   onLongPress?: function
function PlayerCard.Row(props)
    local player = props.player
    if not player then return UI.Panel { height = 0 } end

    local gameState = props.gameState
    local isStarter = props.isStarter or false
    local showFitness = props.showFitness ~= false
    local showWage = props.showWage ~= false
    local showContract = props.showContract ~= false

    local age = gameState and player.getAge and player:getAge(gameState.date.year) or 0
    local posColor = getPosColor(player.position)
    local statusText, statusColor = getStatus(player)

    -- 合同到期提示
    local contractWarn = ""
    if showContract then
        local monthsLeft = getContractMonths(player, gameState)
        if monthsLeft and monthsLeft <= 6 then
            contractWarn = " ⚠"
        end
    end

    -- 工资文本
    local wageText = ""
    if showWage and player.wage then
        wageText = player.wage >= 1000
            and string.format("%.0fK", player.wage / 1000)
            or tostring(player.wage)
        wageText = wageText .. "/周"
    end

    -- 次要信息
    local subText = ""
    if age > 0 then
        subText = age .. "岁"
        if wageText ~= "" then subText = subText .. " | " .. wageText end
    end

    return UI.Panel {
        width = "100%",
        height = 54,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 10,
        paddingRight = 10,
        backgroundColor = isStarter and {31, 46, 71, 255} or {0, 0, 0, 0},
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 首发标记
            UI.Label {
                text = isStarter and "★" or "  ",
                fontSize = 11,
                color = Theme.COLORS.ACCENT,
                width = 18,
            },
            -- 位置
            UI.Label {
                text = player.position,
                fontSize = 12,
                color = posColor,
                width = 36,
                fontWeight = "bold",
            },
            -- 姓名 + 合同到期提示
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = player.displayName .. contractWarn,
                        fontSize = 13,
                        color = Theme.COLORS.TEXT_PRIMARY,
                    },
                    subText ~= "" and UI.Label {
                        text = subText,
                        fontSize = 10,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 1,
                    } or UI.Panel { height = 0 },
                }
            },
            -- 体能
            showFitness and UI.Panel {
                width = 30, height = 30,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(player.fitness or 0),
                        fontSize = 10,
                        color = getFitnessColor(player.fitness or 80),
                    },
                }
            } or UI.Panel { width = 0 },
            -- 能力（UI显示上限99）
            UI.Label {
                text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                fontSize = 14,
                color = getOverallColor(player.overall),
                width = 28,
                fontWeight = "bold",
                textAlign = "center",
            },
            -- 状态
            UI.Label {
                text = statusText,
                fontSize = 11,
                color = statusColor,
                width = 18,
                textAlign = "center",
            },
        },
        onClick = props.onClick,
        onLongPress = props.onLongPress,
    }
end

--- 紧凑球员行（列表/搜索结果使用）
--- @param props table
---   player: Player
---   rightLabel?: string - 右侧标签（如价格/身价）
---   rightColor?: table - 右侧颜色
---   onClick?: function
function PlayerCard.CompactRow(props)
    local player = props.player
    if not player then return UI.Panel { height = 0 } end

    local posColor = getPosColor(player.position)

    return UI.Panel {
        width = "100%",
        height = 46,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 12,
        paddingRight = 12,
        borderBottomWidth = 1,
        borderColor = Theme.COLORS.BORDER,
        children = {
            -- 位置
            UI.Label {
                text = player.position,
                fontSize = 11,
                color = posColor,
                width = 32,
                fontWeight = "bold",
            },
            -- 姓名
            UI.Label {
                text = player.displayName,
                fontSize = 13,
                color = Theme.COLORS.TEXT_PRIMARY,
                flexGrow = 1,
                flexShrink = 1,
            },
            -- 能力（UI显示上限99）
            UI.Label {
                text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                fontSize = 13,
                color = getOverallColor(player.overall),
                width = 28,
                fontWeight = "bold",
            },
            -- 右侧自定义标签
            props.rightLabel and UI.Label {
                text = props.rightLabel,
                fontSize = 12,
                color = props.rightColor or Theme.COLORS.TEXT_MUTED,
                width = 60,
                textAlign = "right",
            } or UI.Panel { width = 0 },
        },
        onClick = props.onClick,
    }
end

--- 球员信息卡片（详情弹窗/概览使用）
--- @param props table
---   player: Player
---   gameState?: GameState
---   showContract?: boolean - 显示合同信息（默认 true）
function PlayerCard.DetailCard(props)
    local player = props.player
    if not player then return UI.Panel { height = 0 } end

    local gameState = props.gameState
    local showContract = props.showContract ~= false
    local age = gameState and player.getAge and player:getAge(gameState.date.year) or 0
    local posColor = getPosColor(player.position)

    local infoRows = {}

    -- 基本信息
    table.insert(infoRows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 10,
        children = {
            -- 位置标签
            UI.Panel {
                width = 40, height = 40,
                borderRadius = 20,
                backgroundColor = {posColor[1], posColor[2], posColor[3], 50},
                justifyContent = "center",
                alignItems = "center",
                marginRight = 12,
                children = {
                    UI.Label {
                        text = player.position,
                        fontSize = 13,
                        color = posColor,
                        fontWeight = "bold",
                    },
                }
            },
            -- 姓名 + 年龄
            UI.Panel {
                flexGrow = 1,
                children = {
                    UI.Label {
                        text = player.displayName,
                        fontSize = 16,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                    },
                    age > 0 and UI.Label {
                        text = age .. "岁",
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_MUTED,
                        marginTop = 2,
                    } or UI.Panel { height = 0 },
                }
            },
            -- 能力值（UI显示上限99）
            UI.Panel {
                width = 48, height = 48,
                borderRadius = 24,
                backgroundColor = {getOverallColor(player.overall)[1], getOverallColor(player.overall)[2], getOverallColor(player.overall)[3], 40},
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = tostring(math.min(Constants.ABILITY_MAX, player.overall or 0)),
                        fontSize = 18,
                        color = getOverallColor(player.overall),
                        fontWeight = "bold",
                    },
                }
            },
        }
    })

    -- 状态行
    local statusText, statusColor = getStatus(player)
    local fitness = player.fitness or 80
    table.insert(infoRows, UI.Panel {
        width = "100%",
        flexDirection = "row",
        marginBottom = 8,
        children = {
            Theme.StatPill { label = "体能", value = fitness .. "%", valueColor = getFitnessColor(fitness) },
            Theme.StatPill { label = "士气", value = (player.morale or 60), valueColor = (player.morale or 60) >= 60 and Theme.COLORS.SECONDARY or Theme.COLORS.WARNING },
            statusText ~= "" and Theme.StatPill { label = "状态", value = statusText, valueColor = statusColor } or UI.Panel { width = 0 },
        }
    })

    -- 合同信息
    if showContract and player.contractEnd then
        local monthsLeft = getContractMonths(player, gameState)
        local contractColor = Theme.COLORS.TEXT_SECONDARY
        if monthsLeft and monthsLeft <= 6 then contractColor = Theme.COLORS.DANGER
        elseif monthsLeft and monthsLeft <= 12 then contractColor = Theme.COLORS.WARNING end

        local wageText = player.wage and (player.wage >= 1000 and string.format("%.0fK/周", player.wage / 1000) or player.wage .. "/周") or "未知"

        table.insert(infoRows, UI.Panel {
            width = "100%",
            flexDirection = "row",
            children = {
                Theme.StatPill { label = "合同", value = player.contractEnd.year .. "/" .. player.contractEnd.month, valueColor = contractColor },
                Theme.StatPill { label = "工资", value = wageText },
            }
        })
    end

    return Theme.Card {
        children = infoRows,
    }
end

--- 辅助：获取位置颜色（供外部使用）
PlayerCard.getPosColor = getPosColor
PlayerCard.getOverallColor = getOverallColor
PlayerCard.getFitnessColor = getFitnessColor
PlayerCard.getStatus = getStatus
PlayerCard.getContractMonths = getContractMonths
PlayerCard.POS_GROUP_MAP = POS_GROUP_MAP

return PlayerCard
