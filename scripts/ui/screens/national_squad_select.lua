-- ui/screens/national_squad_select.lua
-- 世界杯国家队大名单选择页面

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local WorldCup = require("scripts/systems/world_cup")
local SaveManager = require("scripts/persistence/save_manager")

local NationalSquadSelect = {}

local SQUAD_SIZE = 23
local POS_GROUPS = {
    { key = "ALL", label = "全部" },
    { key = "GK",  label = "门将" },
    { key = "DEF", label = "后卫" },
    { key = "MID", label = "中场" },
    { key = "FWD", label = "前锋" },
}

local function getPosGroup(pos)
    if pos == "GK" then return "GK"
    elseif pos == "CB" or pos == "LB" or pos == "RB" then return "DEF"
    elseif pos == "ST" or pos == "CF" or pos == "LW" or pos == "RW" then return "FWD"
    else return "MID"
    end
end

local function getPosColor(pos)
    return Theme.posColor(pos)
end

function NationalSquadSelect.create(params)
    local gameState = _G.gameState
    local nation = params and params.nation
    if not nation then
        Router.back()
        return UI.Panel { width = "100%", height = "100%" }
    end

    local nationName = WorldCup._getNationName(nation)
    local allPlayers = WorldCup.getAvailablePlayers(gameState, nation)

    -- 已选中的球员ID集合
    local selectedIds = {}
    -- 如果已有保存的大名单，预选
    local ntCoach = gameState.nationalTeamCoach
    if ntCoach and ntCoach.squad then
        for _, pid in ipairs(ntCoach.squad) do
            selectedIds[pid] = true
        end
    else
        -- 默认选中前23名（按overall排序）
        for i = 1, math.min(SQUAD_SIZE, #allPlayers) do
            selectedIds[allPlayers[i].id] = true
        end
    end

    -- 统计已选数量
    local function countSelected()
        local n = 0
        for _ in pairs(selectedIds) do n = n + 1 end
        return n
    end

    -- 当前筛选
    local filterPos = "ALL"

    -- 引用容器
    ---@type UIElement
    local listContainer = nil
    ---@type UIElement
    local headerLabel = nil
    ---@type UIElement
    local confirmBtn = nil

    local function updateHeader()
        if headerLabel then
            headerLabel:SetText(string.format("%s 大名单 (%d/%d)", nationName, countSelected(), SQUAD_SIZE))
        end
        if confirmBtn then
            local count = countSelected()
            confirmBtn:SetDisabled(count < 11)
            confirmBtn:SetText(count >= 11 and "确认大名单" or "至少选11人")
        end
    end

    local function buildPlayerRow(p, isSelected)
        local bgColor = isSelected and "#1a3a2a" or Theme.COLORS.BG_CARD
        local checkText = isSelected and "✓" or ""
        local checkColor = isSelected and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_MUTED

        return UI.Button {
            width = "100%",
            height = 52,
            backgroundColor = bgColor,
            borderRadius = 8,
            marginBottom = 4,
            paddingLeft = 12, paddingRight = 12,
            flexDirection = "row",
            alignItems = "center",
            onClick = function()
                if isSelected then
                    selectedIds[p.id] = nil
                else
                    if countSelected() >= SQUAD_SIZE then return end
                    selectedIds[p.id] = true
                end
                updateHeader()
                NationalSquadSelect._rebuildList(listContainer, allPlayers, selectedIds, filterPos)
            end,
            children = {
                -- 选中标记
                UI.Label {
                    text = checkText,
                    width = 24,
                    fontSize = 16,
                    fontWeight = "bold",
                    color = checkColor,
                },
                -- 位置
                UI.Panel {
                    backgroundColor = (function()
                        local c = getPosColor(p.position)
                        return {c[1], c[2], c[3], 50}
                    end)(),
                    borderRadius = 3,
                    paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                    marginRight = 4, minWidth = 36,
                    children = {
                        UI.Label {
                            text = Constants.POSITION_NAMES[p.position] or p.position or "?",
                            fontSize = 10, fontWeight = "bold",
                            color = getPosColor(p.position),
                        },
                    },
                },
                -- 名字
                UI.Label {
                    text = p.displayName or p.lastName or "?",
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                -- 俱乐部
                UI.Label {
                    text = (function()
                        local team = gameState.teams[p.teamId]
                        return team and team.shortName or ""
                    end)(),
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_MUTED,
                    width = 40,
                    textAlign = "center",
                },
                -- Overall
                UI.Label {
                    text = tostring(p.overall or 0),
                    fontSize = 14,
                    fontWeight = "bold",
                    color = (p.overall or 0) >= 75 and Theme.COLORS.SECONDARY or Theme.COLORS.TEXT_PRIMARY,
                    width = 30,
                    textAlign = "right",
                },
                -- 年龄
                UI.Label {
                    text = tostring(p.age or 0),
                    fontSize = 11,
                    color = Theme.COLORS.TEXT_SECONDARY,
                    width = 26,
                    textAlign = "right",
                },
                -- 伤病标记
                UI.Label {
                    text = p.injured and "🤕" or "",
                    fontSize = 12,
                    width = 20,
                    textAlign = "center",
                },
            }
        }
    end

    -- 筛选按钮
    local filterBtns = {}
    for _, opt in ipairs(POS_GROUPS) do
        table.insert(filterBtns, UI.Button {
            id = "filter_" .. opt.key,
            text = opt.label,
            height = 28,
            paddingLeft = 10, paddingRight = 10,
            borderRadius = 14,
            fontSize = 12,
            backgroundColor = filterPos == opt.key and Theme.COLORS.PRIMARY or Theme.COLORS.BG_SURFACE,
            color = filterPos == opt.key and "#FFFFFF" or Theme.COLORS.TEXT_SECONDARY,
            onClick = function()
                filterPos = opt.key
                NationalSquadSelect._rebuildList(listContainer, allPlayers, selectedIds, filterPos)
                -- 更新筛选按钮样式（简化：重建整页）
            end,
        })
    end

    headerLabel = UI.Label {
        id = "header_label",
        text = string.format("%s 大名单 (%d/%d)", nationName, countSelected(), SQUAD_SIZE),
        fontSize = 16,
        fontWeight = "bold",
        color = Theme.COLORS.TEXT_PRIMARY,
        flexGrow = 1,
        textAlign = "center",
    }

    confirmBtn = UI.Button {
        id = "confirm_btn",
        text = "确认大名单",
        width = 80, height = 32,
        backgroundColor = Theme.COLORS.SECONDARY,
        borderRadius = 8,
        fontSize = 13,
        fontWeight = "bold",
        color = "#FFFFFF",
        disabled = countSelected() < 11,
        onClick = function()
            -- 保存大名单
            local squad = {}
            for pid in pairs(selectedIds) do
                table.insert(squad, pid)
            end
            gameState.nationalTeamCoach.squad = squad
            SaveManager.save(gameState, "auto")
            gameState:sendMessage({
                category = "world_cup",
                title = "大名单确认",
                body = string.format("%s世界杯大名单已确认！共%d人入选。准备迎接世界杯吧！",
                    nationName, #squad),
                priority = "high",
            })
            Router.navigate("dashboard")
        end,
    }

    -- 构建列表内容
    listContainer = UI.Panel {
        id = "player_list",
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        overflow = "scroll",
    }

    -- 初始填充列表
    local rows = {}
    for _, p in ipairs(allPlayers) do
        table.insert(rows, buildPlayerRow(p, selectedIds[p.id] == true))
    end
    listContainer:SetChildren(rows)

    -- 保存 buildPlayerRow 引用到模块内给 rebuild 用
    NationalSquadSelect._buildPlayerRow = buildPlayerRow

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%",
                height = 48,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = {
                    UI.Button {
                        text = "←",
                        width = 36, height = 32,
                        backgroundColor = "transparent",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            -- 如果还没确认，提醒（简化处理：直接返回）
                            Router.navigate("dashboard")
                        end,
                    },
                    headerLabel,
                    confirmBtn,
                }
            },

            -- 筛选栏
            UI.Panel {
                width = "100%",
                height = 40,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 8, paddingRight = 8,
                gap = 6,
                children = filterBtns,
            },

            -- 列表表头
            UI.Panel {
                width = "100%",
                height = 28,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_SURFACE,
                children = {
                    UI.Label { text = "", width = 24, fontSize = 10 },
                    UI.Label { text = "位置", width = 32, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "球员", flexGrow = 1, fontSize = 10, color = Theme.COLORS.TEXT_MUTED },
                    UI.Label { text = "俱乐部", width = 40, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, textAlign = "center" },
                    UI.Label { text = "能力", width = 30, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, textAlign = "right" },
                    UI.Label { text = "年龄", width = 26, fontSize = 10, color = Theme.COLORS.TEXT_MUTED, textAlign = "right" },
                    UI.Label { text = "", width = 20 },
                },
            },

            -- 球员列表
            listContainer,
        }
    }
end

--- 重建列表（筛选后）
function NationalSquadSelect._rebuildList(container, allPlayers, selectedIds, filterPos)
    if not container then return end
    local buildRow = NationalSquadSelect._buildPlayerRow
    local rows = {}
    for _, p in ipairs(allPlayers) do
        local show = (filterPos == "ALL") or (getPosGroup(p.position) == filterPos)
        if show then
            table.insert(rows, buildRow(p, selectedIds[p.id] == true))
        end
    end
    container:SetChildren(rows)
end

return NationalSquadSelect
