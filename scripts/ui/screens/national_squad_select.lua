-- ui/screens/national_squad_select.lua
-- 世界杯国家队大名单选择页面（金色主题）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local WorldCup = require("scripts/systems/world_cup")
local SaveManager = require("scripts/persistence/save_manager")

local NationalSquadSelect = {}

local SQUAD_SIZE = 23
local POS_GROUPS = {
    { key = "GK",  label = "门将" },
    { key = "DEF", label = "后卫" },
    { key = "MID", label = "中场" },
    { key = "FWD", label = "前锋" },
}

-- 金色世界杯主题色
local WC = {
    GOLD         = {255, 215, 0, 255},
    GOLD_DIM     = {255, 215, 0, 200},
    GOLD_BG      = {255, 215, 0, 30},
    GOLD_BG_HI   = {255, 215, 0, 50},
    DARK_BG      = {10, 20, 40, 255},
    CARD_BG      = {15, 30, 55, 255},
    SURFACE_BG   = {20, 35, 60, 255},
    BTN_BG       = {40, 60, 90, 255},
    TEXT_PRIMARY  = {240, 245, 255, 255},
    TEXT_SECONDARY = {130, 200, 255, 255},
    TEXT_MUTED    = {100, 140, 180, 255},
    SELECTED_ROW  = {40, 70, 50, 255},
    CHECK_GREEN   = {80, 220, 120, 255},
}

local function getPosGroup(pos)
    if pos == "GK" then return "GK"
    elseif pos == "CB" or pos == "LB" or pos == "RB" then return "DEF"
    elseif pos == "ST" or pos == "CF" or pos == "LW" or pos == "RW" then return "FWD"
    else return "MID"
    end
end

local function getPosColor(pos)
    local group = getPosGroup(pos)
    if group == "GK" then return {255, 180, 0, 255}
    elseif group == "DEF" then return {80, 160, 255, 255}
    elseif group == "FWD" then return {255, 90, 90, 255}
    else return {80, 220, 160, 255}
    end
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

    local MIN_GK = 3  -- 大名单必须包含3个门将

    -- 已选中的球员ID集合
    local selectedIds = {}
    local ntCoach = gameState.nationalTeamCoach
    if ntCoach and ntCoach.squad then
        for _, pid in ipairs(ntCoach.squad) do
            selectedIds[pid] = true
        end
    else
        -- 默认选中：先确保至少3个门将，再按overall填满23人
        -- 1) 分出门将和其他球员
        local gkPlayers = {}
        local outfieldPlayers = {}
        for _, p in ipairs(allPlayers) do
            if p.position == "GK" then
                table.insert(gkPlayers, p)
            else
                table.insert(outfieldPlayers, p)
            end
        end

        -- 2) 选入至少3个门将
        for i = 1, math.min(MIN_GK, #gkPlayers) do
            selectedIds[gkPlayers[i].id] = true
        end

        -- 3) 剩余名额从全体球员中按overall排名填充（已选的跳过）
        local remaining = SQUAD_SIZE - MIN_GK
        for _, p in ipairs(allPlayers) do
            if remaining <= 0 then break end
            if not selectedIds[p.id] then
                selectedIds[p.id] = true
                remaining = remaining - 1
            end
        end

        local defaultSquad = {}
        for pid in pairs(selectedIds) do
            table.insert(defaultSquad, pid)
        end
        gameState.nationalTeamCoach.squad = defaultSquad
    end

    -- 统计已选数量
    local function countSelected()
        local n = 0
        for _ in pairs(selectedIds) do n = n + 1 end
        return n
    end

    -- 统计已选门将数量
    local function countSelectedGK()
        local n = 0
        for pid in pairs(selectedIds) do
            local p = gameState.players[pid]
            if p and p.position == "GK" then n = n + 1 end
        end
        return n
    end

    -- 是否已确认锁定大名单
    local isLocked = ntCoach and ntCoach.squadConfirmed == true

    -- 当前筛选位置（从params获取，实现按钮状态同步）
    local filterPos = (params and params.filterPos) or "GK"

    -- 引用容器
    ---@type UIElement
    local listContainer = nil
    ---@type UIElement
    local headerLabel = nil
    ---@type UIElement
    local confirmBtn = nil

    local function updateHeader()
        if headerLabel then
            local gkCount = countSelectedGK()
            local gkHint = gkCount < MIN_GK and string.format(" (门将%d/%d)", gkCount, MIN_GK) or ""
            headerLabel:SetText(string.format("%s 大名单 (%d/%d)%s", nationName, countSelected(), SQUAD_SIZE, gkHint))
        end
        if confirmBtn then
            local count = countSelected()
            local gkCount = countSelectedGK()
            local canConfirm = count >= 11 and gkCount >= MIN_GK
            confirmBtn:SetDisabled(not canConfirm)
            if gkCount < MIN_GK then
                confirmBtn:SetText(string.format("需要%d门将(已选%d)", MIN_GK, gkCount))
            elseif count < 11 then
                confirmBtn:SetText("至少选11人")
            else
                confirmBtn:SetText("确认大名单")
            end
        end
    end

    local function buildPlayerRow(p, isSelected)
        local bgColor = isSelected and WC.SELECTED_ROW or WC.CARD_BG
        local checkText = isSelected and "✓" or "○"
        local checkColor = isSelected and WC.CHECK_GREEN or WC.TEXT_MUTED

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
                if isLocked then return end  -- 已确认，不允许修改
                if isSelected then
                    -- 取消选中门将时检查：如果当前门将已经<=3，不允许取消
                    if p.position == "GK" and countSelectedGK() <= MIN_GK then
                        -- 不允许取消，需要保持至少3个门将
                        return
                    end
                    selectedIds[p.id] = nil
                else
                    if countSelected() >= SQUAD_SIZE then return end
                    selectedIds[p.id] = true
                end
                -- 实时同步选中状态到 gameState（切换筛选时不丢失）
                local squad = {}
                for pid in pairs(selectedIds) do
                    table.insert(squad, pid)
                end
                gameState.nationalTeamCoach.squad = squad
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
                        return {c[1], c[2], c[3], 40}
                    end)(),
                    borderRadius = 4,
                    paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
                    marginRight = 6, minWidth = 36,
                    justifyContent = "center", alignItems = "center",
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
                    color = isSelected and WC.GOLD or WC.TEXT_PRIMARY,
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
                    color = WC.TEXT_MUTED,
                    width = 40,
                    textAlign = "center",
                },
                -- Overall
                UI.Label {
                    text = tostring(p.overall or 0),
                    fontSize = 14,
                    fontWeight = "bold",
                    color = (p.overall or 0) >= 80 and WC.GOLD or ((p.overall or 0) >= 70 and WC.TEXT_SECONDARY or WC.TEXT_PRIMARY),
                    width = 30,
                    textAlign = "right",
                },
                -- 年龄
                UI.Label {
                    text = tostring(p.age or 0),
                    fontSize = 11,
                    color = WC.TEXT_MUTED,
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

    -- 筛选按钮（根据 filterPos 决定高亮）
    local filterBtns = {}
    for _, opt in ipairs(POS_GROUPS) do
        local isActive = (filterPos == opt.key)
        table.insert(filterBtns, UI.Button {
            text = opt.label,
            height = 30,
            paddingLeft = 14, paddingRight = 14,
            borderRadius = 15,
            fontSize = 12,
            fontWeight = isActive and "bold" or "normal",
            backgroundColor = isActive and WC.GOLD or WC.BTN_BG,
            color = isActive and {20, 20, 40, 255} or WC.TEXT_SECONDARY,
            onClick = function()
                -- 通过 replaceWith 重建整页，实现按钮高亮同步
                Router.replaceWith("national_squad_select", { nation = nation, filterPos = opt.key })
            end,
        })
    end

    headerLabel = UI.Label {
        text = string.format("%s 大名单 (%d/%d)", nationName, countSelected(), SQUAD_SIZE),
        fontSize = 15,
        fontWeight = "bold",
        color = WC.GOLD,
        flexGrow = 1,
        textAlign = "center",
    }

    if isLocked then
        confirmBtn = UI.Panel {
            height = 30,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = {40, 80, 60, 255},
            borderRadius = 6,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "已确认 ✓", fontSize = 12, fontWeight = "bold", color = WC.CHECK_GREEN },
            },
        }
    else
        local initCount = countSelected()
        local initGK = countSelectedGK()
        local initCanConfirm = initCount >= 11 and initGK >= MIN_GK
        local initBtnText
        if initGK < MIN_GK then
            initBtnText = string.format("需要%d门将(已选%d)", MIN_GK, initGK)
        elseif initCount < 11 then
            initBtnText = "至少选11人"
        else
            initBtnText = "确认大名单"
        end

        confirmBtn = UI.Button {
            text = initBtnText,
            height = 30,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = initCanConfirm and WC.GOLD or WC.BTN_BG,
            borderRadius = 6,
            fontSize = 12,
            fontWeight = "bold",
            color = initCanConfirm and {20, 20, 40, 255} or WC.TEXT_MUTED,
            disabled = not initCanConfirm,
            onClick = function()
                -- 再次检查门将数量
                local gkCount = countSelectedGK()
                if gkCount < MIN_GK then
                    -- 理论上按钮disabled不会触发，但做防御
                    return
                end
                -- 保存大名单并锁定
                local squad = {}
                for pid in pairs(selectedIds) do
                    table.insert(squad, pid)
                end
                gameState.nationalTeamCoach.squad = squad
                gameState.nationalTeamCoach.squadConfirmed = true
                SaveManager.save(gameState, "auto")
                gameState:sendMessage({
                    category = "world_cup",
                    title = "大名单确认",
                    body = string.format("%s世界杯大名单已确认！共%d人入选（含%d名门将）。准备迎接世界杯吧！",
                        nationName, #squad, gkCount),
                    priority = "high",
                })
                Router.navigate("dashboard")
            end,
        }
    end

    -- 构建列表容器
    listContainer = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        overflow = "scroll",
        paddingLeft = 6, paddingRight = 6, paddingTop = 4,
    }

    -- 初始填充列表 —— 按 filterPos 过滤！
    for _, p in ipairs(allPlayers) do
        if getPosGroup(p.position) == filterPos then
            listContainer:AddChild(buildPlayerRow(p, selectedIds[p.id] == true))
        end
    end

    -- 保存 buildPlayerRow 引用给 rebuild 用
    NationalSquadSelect._buildPlayerRow = buildPlayerRow

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = WC.DARK_BG,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%",
                height = 48,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = WC.CARD_BG,
                children = {
                    UI.Button {
                        text = "←",
                        width = 36, height = 32,
                        backgroundColor = {0, 0, 0, 0},
                        fontSize = 18,
                        color = WC.GOLD_DIM,
                        onClick = function()
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
                height = 44,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                paddingLeft = 8, paddingRight = 8,
                gap = 8,
                backgroundColor = WC.SURFACE_BG,
                children = filterBtns,
            },

            -- 列表表头
            UI.Panel {
                width = "100%",
                height = 28,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 18, paddingRight = 18,
                backgroundColor = WC.CARD_BG,
                children = {
                    UI.Label { text = "", width = 24, fontSize = 10 },
                    UI.Label { text = "位置", width = 36, fontSize = 10, color = WC.TEXT_MUTED },
                    UI.Label { text = "球员", flexGrow = 1, fontSize = 10, color = WC.TEXT_MUTED },
                    UI.Label { text = "俱乐部", width = 40, fontSize = 10, color = WC.TEXT_MUTED, textAlign = "center" },
                    UI.Label { text = "能力", width = 30, fontSize = 10, color = WC.TEXT_MUTED, textAlign = "right" },
                    UI.Label { text = "年龄", width = 26, fontSize = 10, color = WC.TEXT_MUTED, textAlign = "right" },
                    UI.Label { text = "", width = 20 },
                },
            },

            -- 球员列表
            listContainer,
        }
    }
end

--- 重建列表（选中/取消后刷新）
function NationalSquadSelect._rebuildList(container, allPlayers, selectedIds, filterPos)
    if not container then return end
    local buildRow = NationalSquadSelect._buildPlayerRow
    container:RemoveAllChildren()
    for _, p in ipairs(allPlayers) do
        if getPosGroup(p.position) == filterPos then
            container:AddChild(buildRow(p, selectedIds[p.id] == true))
        end
    end
end

return NationalSquadSelect
