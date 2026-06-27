-- ui/screens/select_team.lua
-- 选择球队页面（按联赛分组展示）

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local TeamIcon = require("scripts/ui/components/team_icon")
local FinanceManager = require("scripts/systems/finance_manager")

local SelectTeam = {}

-- 当前选中的联赛筛选
local selectedLeagueKey = nil
-- 当前选中的球队（等待确认）
local pendingTeam = nil
-- UI 控件引用（避免整页重建）
local listRef = nil
local confirmBarRef = nil

function SelectTeam.create(params)
    local managerFirstName = params and params.firstName or "Alex"
    local managerLastName = params and params.lastName or "Manager"

    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "世界生成失败", fontSize = 18, color = Theme.COLORS.DANGER, marginBottom = 12 },
                UI.Label { text = "请检查日志获取详细信息", fontSize = 13, color = Theme.COLORS.TEXT_MUTED, marginBottom = 20 },
                Theme.PrimaryButton {
                    text = "返回主菜单",
                    width = 200,
                    onClick = function()
                        _G.gameState = nil
                        Router.clearHistory()
                        Router.navigate("main_menu")
                    end,
                },
            }
        }
    end

    -- 联赛顺序
    local RealDataLoader = require("scripts/data/real_data_loader")
    local leagueOrder = RealDataLoader.getLeagueDisplayOrder(gameState)

    -- 默认选中第一个有数据的联赛
    if not selectedLeagueKey then
        for _, key in ipairs(leagueOrder) do
            if gameState.leagues[key] then
                selectedLeagueKey = key
                break
            end
        end
    end

    -- 构建联赛切换按钮
    local leagueTabs = {}
    for _, key in ipairs(leagueOrder) do
        local lg = gameState.leagues[key]
        if lg then
            local isActive = key == selectedLeagueKey
            table.insert(leagueTabs, UI.Panel {
                height = 30,
                paddingLeft = 12, paddingRight = 12,
                backgroundColor = isActive and "rgba(212,175,55,0.15)" or Theme.COLORS.TRANSPARENT,
                borderRadius = 15,
                borderWidth = isActive and 1 or 0,
                borderColor = "rgba(212,175,55,0.4)",
                justifyContent = "center",
                alignItems = "center",
                marginRight = 6,
                onClick = function()
                    selectedLeagueKey = key
                    pendingTeam = nil
                    Router.replaceWith("select_team", params)
                end,
                children = {
                    UI.Label {
                        text = lg.name,
                        fontSize = 12,
                        color = isActive and Theme.COLORS.GOLD or Theme.COLORS.TEXT_MUTED,
                        fontWeight = isActive and "bold" or "normal",
                    },
                },
            })
        end
    end

    -- 中超 Tab：未加载时点击加载，已加载时再次点击卸载
    do
        local cslLoaded = gameState.leagues.CSL ~= nil
        local isActive = selectedLeagueKey == "CSL" and cslLoaded
        table.insert(leagueTabs, UI.Panel {
            height = 30,
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = isActive and "rgba(212,175,55,0.15)" or (cslLoaded and "rgba(255,75,75,0.08)" or "rgba(212,175,55,0.06)"),
            borderRadius = 15,
            borderWidth = 1,
            borderColor = isActive and "rgba(212,175,55,0.4)" or (cslLoaded and "rgba(255,75,75,0.3)" or "rgba(212,175,55,0.3)"),
            justifyContent = "center",
            alignItems = "center",
            marginRight = 6,
            onClick = function()
                if cslLoaded then
                    RealDataLoader.unloadOptionalLeague(gameState, "CSL")
                    if selectedLeagueKey == "CSL" then
                        selectedLeagueKey = "EPL"
                    end
                    pendingTeam = nil
                    Router.replaceWith("select_team", params)
                else
                    local success = RealDataLoader.loadOptionalLeague(gameState, "CSL")
                    if success then
                        local WorldGenerator = require("scripts/systems/world_generator")
                        WorldGenerator.bootstrapLeagueTeams(gameState, "CSL")
                        selectedLeagueKey = "CSL"
                        pendingTeam = nil
                        Router.replaceWith("select_team", params)
                    end
                end
            end,
            children = {
                UI.Label {
                    text = cslLoaded and "中超 ✕" or "+ 中超",
                    fontSize = 12,
                    color = isActive and Theme.COLORS.GOLD or (cslLoaded and "#FF6B6B" or Theme.COLORS.GOLD),
                    fontWeight = "bold",
                },
            },
        })
    end

    -- 次级联赛 Tab：批量加载/卸载五大次级联赛
    do
        local secondLoaded = RealDataLoader.areSecondDivisionsLoaded(gameState)
        local isSecondActive = secondLoaded and RealDataLoader.isSecondDivisionKey(selectedLeagueKey)
        table.insert(leagueTabs, UI.Panel {
            height = 30,
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = isSecondActive and "rgba(212,175,55,0.15)" or (secondLoaded and "rgba(255,75,75,0.08)" or "rgba(100,180,255,0.08)"),
            borderRadius = 15,
            borderWidth = 1,
            borderColor = isSecondActive and "rgba(212,175,55,0.4)" or (secondLoaded and "rgba(255,75,75,0.3)" or "rgba(100,180,255,0.3)"),
            justifyContent = "center",
            alignItems = "center",
            marginRight = 6,
            onClick = function()
                if secondLoaded then
                    RealDataLoader.unloadAllSecondDivisions(gameState)
                    if RealDataLoader.isSecondDivisionKey(selectedLeagueKey) then
                        selectedLeagueKey = "EPL"
                    end
                    pendingTeam = nil
                    Router.replaceWith("select_team", params)
                else
                    local success = RealDataLoader.loadAllSecondDivisions(gameState)
                    if success then
                        selectedLeagueKey = "Championship"
                        pendingTeam = nil
                        Router.replaceWith("select_team", params)
                    end
                end
            end,
            children = {
                UI.Label {
                    text = secondLoaded and "次级 ✕" or "+ 次级",
                    fontSize = 12,
                    color = isSecondActive and Theme.COLORS.GOLD or (secondLoaded and "#FF6B6B" or "#64B4FF"),
                    fontWeight = "bold",
                },
            },
        })
    end

    -- 获取当前选中联赛的球队列表
    local teamList = {}
    local selectedLeague = gameState.leagues[selectedLeagueKey]
    if selectedLeague then
        for _, teamId in ipairs(selectedLeague.teamIds) do
            local team = gameState.teams[teamId]
            if team then
                table.insert(teamList, team)
            end
        end
        table.sort(teamList, function(a, b) return a.reputation > b.reputation end)
    end

    local page = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "← 返回",
                        width = 80,
                        height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Router.back()
                        end,
                    },
                    UI.Label {
                        text = "选择球队",
                        fontSize = 17,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 80 },
                }
            },

            -- 提示
            UI.Panel {
                width = "100%",
                paddingLeft = 16, paddingRight = 16, paddingTop = 10, paddingBottom = 6,
                children = {
                    UI.Label {
                        text = "你好, " .. managerLastName .. managerFirstName .. "! 请选择你要执教的球队:",
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                    },
                }
            },

            -- 联赛切换标签栏（横向滑动）
            UI.ScrollView {
                width = "100%",
                height = 42,
                scrollX = true,
                scrollY = false,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 10,
                paddingRight = 10,
                paddingTop = 4,
                paddingBottom = 4,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = leagueTabs,
            },

            -- 球队列表
            UI.VirtualList {
                id = "team_list",
                data = teamList,
                itemHeight = 72,
                viewportHeight = 1200,
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                createItem = function()
                    return UI.Panel {
                        id = "row",
                        width = "100%",
                        height = 72,
                        flexDirection = "row",
                        alignItems = "center",
                        paddingLeft = 16,
                        paddingRight = 16,
                        borderBottomWidth = 1,
                        borderColor = Theme.COLORS.BORDER,
                        children = {
                            TeamIcon.listItem { size = 44, marginRight = 12 },
                            -- 左侧：队名+城市
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    UI.Label { id = "name", fontSize = 15, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold" },
                                    UI.Label { id = "info", fontSize = 12, color = Theme.COLORS.TEXT_MUTED, marginTop = 3 },
                                }
                            },
                            -- 右侧：声望+预算
                            UI.Panel {
                                alignItems = "flex-end",
                                children = {
                                    UI.Label { id = "rep", fontSize = 13, color = Theme.COLORS.ACCENT },
                                    UI.Label { id = "budget", fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2 },
                                }
                            },
                        }
                    }
                end,
                bindItem = function(widget, data, index)
                    TeamIcon.bindListItem(widget:FindById("icon"), data)
                    widget:FindById("name"):SetText(data.name)
                    widget:FindById("info"):SetText((data.city or "") .. " | " .. (Constants.PLAY_STYLE_NAMES[data.playStyle] or data.playStyle or ""))
                    widget:FindById("rep"):SetText("声望 " .. (data.reputation or 0))
                    local budgetStr = FinanceManager.formatMoney(data.transferBudget or 0)
                    widget:FindById("budget"):SetText("转会预算 " .. budgetStr)
                    -- 选中态高亮
                    local isSelected = pendingTeam and pendingTeam.id == data.id
                    local row = widget:FindById("row")
                    if row then
                        row:SetBackgroundColor(isSelected and {30, 60, 100, 255} or Theme.COLORS.TRANSPARENT)
                    end
                end,
                onItemClick = function(data, index, widget)
                    -- 选中球队（等待确认），不重建页面，仅刷新列表和确认栏
                    pendingTeam = data
                    if listRef then
                        listRef:Refresh()
                    end
                    SelectTeam._updateConfirmBar(params)
                end,
            },

            -- 底部确认栏容器（始终存在，内容动态更新）
            UI.Panel {
                id = "confirm_bar",
                width = "100%",
            },
        }
    }

    -- 保存引用用于后续刷新
    listRef = page:FindById("team_list")
    confirmBarRef = page:FindById("confirm_bar")

    -- 首次渲染确认栏（如果已有 pendingTeam）
    SelectTeam._updateConfirmBar(params)

    return page
end

--- 更新底部确认栏内容（不重建页面）
function SelectTeam._updateConfirmBar(params)
    if not confirmBarRef then return end
    local managerFirstName = params and params.firstName or "Alex"
    local managerLastName = params and params.lastName or "Manager"

    -- 清空旧内容
    confirmBarRef:RemoveAllChildren()

    if not pendingTeam then
        -- 没有选中球队，确认栏为空
        confirmBarRef:SetStyle({
            backgroundColor = Theme.COLORS.TRANSPARENT,
            borderTopWidth = 0,
            paddingTop = 0, paddingBottom = 0,
            paddingLeft = 0, paddingRight = 0,
        })
        return
    end

    -- 有选中球队，渲染确认栏
    confirmBarRef:SetStyle({
        backgroundColor = {20, 30, 50, 255},
        borderTopWidth = 1,
        borderColor = Theme.COLORS.PRIMARY,
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 12, paddingBottom = 12,
        flexDirection = "row",
        alignItems = "center",
    })

    local children = {
        TeamIcon.create { team = pendingTeam, size = 36, marginRight = 10 },
        UI.Panel {
            flexGrow = 1,
            children = {
                UI.Label {
                    text = pendingTeam.name,
                    fontSize = 14, color = Theme.COLORS.TEXT_PRIMARY, fontWeight = "bold",
                },
                UI.Label {
                    text = "声望 " .. (pendingTeam.reputation or 0) .. " | 预算 " .. FinanceManager.formatMoney(pendingTeam.transferBudget or 0),
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED, marginTop = 2,
                },
            }
        },
        UI.Button {
            text = "确认执教",
            width = 90, height = 38,
            backgroundColor = Theme.COLORS.GOLD,
            borderRadius = 8,
            fontSize = 14, fontWeight = "bold",
            color = "#1A1A1A",
            onClick = function()
                local team = pendingTeam
                pendingTeam = nil
                listRef = nil
                confirmBarRef = nil
                EventBus.emit("team_selected", {
                    teamId = team.id,
                    firstName = managerFirstName,
                    lastName = managerLastName,
                })
            end,
        },
    }
    for _, child in ipairs(children) do
        confirmBarRef:AddChild(child)
    end
end

return SelectTeam
