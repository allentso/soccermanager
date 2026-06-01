-- main.lua
-- OpenFoot Manager - UrhoX 足球经理游戏入口

local UI = require("urhox-libs/UI")
local Router = require("scripts/app/router")
local EventBus = require("scripts/app/event_bus")
local GameState = require("scripts/core/game_state")
local WorldGenerator = require("scripts/systems/world_generator")
local SaveManager = require("scripts/persistence/save_manager")
local Constants = require("scripts/app/constants")
local SeasonManager = require("scripts/systems/season_manager")

-- 页面模块
local MainMenu = require("scripts/ui/screens/main_menu")
local CreateManager = require("scripts/ui/screens/create_manager")
local SelectTeam = require("scripts/ui/screens/select_team")
local Dashboard = require("scripts/ui/screens/dashboard")
local SquadPage = require("scripts/ui/screens/squad")
local LeagueView = require("scripts/ui/screens/league_view")
local InboxPage = require("scripts/ui/screens/inbox")
local MarketPage = require("scripts/ui/screens/market")
local PlayerDetail = require("scripts/ui/screens/player_detail")
local LoadGame = require("scripts/ui/screens/load_game")
local TrainingPage = require("scripts/ui/screens/training")
local TacticsPage = require("scripts/ui/screens/tactics")
local FinancePage = require("scripts/ui/screens/finance")
local NewsPage = require("scripts/ui/screens/news")
local MatchResult = require("scripts/ui/screens/match_result")
local SettingsPage = require("scripts/ui/screens/settings")
local StaffPage = require("scripts/ui/screens/staff")
local ScoutingPage = require("scripts/ui/screens/scouting")
local YouthPage = require("scripts/ui/screens/youth")
local TeamDetail = require("scripts/ui/screens/team_detail")
local ManagerView = require("scripts/ui/screens/manager_view")
local SeasonEnd = require("scripts/ui/screens/season_end")
local HallOfFame = require("scripts/ui/screens/hall_of_fame")
local TransferHub = require("scripts/ui/screens/transfer_hub")
local PreMatch = require("scripts/ui/screens/pre_match")
local MatchLive = require("scripts/ui/screens/match_live")
local PressConference = require("scripts/ui/screens/press_conference")
local TeamTalk = require("scripts/ui/screens/team_talk")
local SponsorSelect = require("scripts/ui/screens/sponsor_select")
local NationalSquadSelect = require("scripts/ui/screens/national_squad_select")
local TrophyCabinet = require("scripts/ui/screens/trophy_cabinet")
local ChampionshipPopup = require("scripts/ui/components/championship_popup")

-- 全局覆盖层管理（注入 UI.ShowOverlay / UI.CloseOverlay）
require("scripts/ui/components/overlay_manager")

-- 全局游戏状态
_G.gameState = nil

------------------------------------------------------
-- Start 入口
------------------------------------------------------
function Start()
    graphics.windowTitle = "OpenFoot Manager"

    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            }}
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 注册页面路由
    RegisterScreens()

    -- 绑定事件
    BindEvents()

    -- 显示主菜单
    NavigateTo("main_menu")

    -- 订阅引擎事件
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    log:Write(LOG_INFO, "OpenFoot Manager 启动完成 v" .. Constants.VERSION)
end

function Stop()
    -- 自动保存
    if _G.gameState then
        SaveManager.save(_G.gameState, "auto")
        log:Write(LOG_INFO, "退出时自动保存")
    end
    UI.Shutdown()
end

------------------------------------------------------
-- 页面注册
------------------------------------------------------
function RegisterScreens()
    Router.register("main_menu", function(params) return MainMenu.create() end)
    Router.register("create_manager", function(params) return CreateManager.create() end)
    Router.register("select_team", function(params) return SelectTeam.create(params) end)
    Router.register("dashboard", function(params) return Dashboard.create(params) end)
    Router.register("squad", function(params) return SquadPage.create(params) end)
    Router.register("league", function(params) return LeagueView.create(params) end)
    Router.register("inbox", function(params) return InboxPage.create(params) end)
    Router.register("market", function(params) return MarketPage.create(params) end)
    Router.register("player_detail", function(params) return PlayerDetail.create(params) end)
    Router.register("load_game", function(params) return LoadGame.create(params) end)
    Router.register("training", function(params) return TrainingPage.create(params) end)
    Router.register("tactics", function(params) return TacticsPage.create(params) end)
    Router.register("finance", function(params) return FinancePage.create(params) end)
    Router.register("news", function(params) return NewsPage.create(params) end)
    Router.register("match_result", function(params) return MatchResult.create(params) end)
    Router.register("settings", function(params) return SettingsPage.create(params) end)
    Router.register("staff", function(params) return StaffPage.create(params) end)
    Router.register("scouting", function(params) return ScoutingPage.create(params) end)
    Router.register("youth", function(params) return YouthPage.create(params) end)
    Router.register("team_detail", function(params) return TeamDetail.create(params) end)
    Router.register("manager_view", function(params) return ManagerView.create(params) end)
    Router.register("season_end", function(params) return SeasonEnd.create(params) end)
    Router.register("hall_of_fame", function(params) return HallOfFame.create(params) end)
    Router.register("transfer_hub", function(params) return TransferHub.create(params) end)
    Router.register("pre_match", function(params) return PreMatch.create(params) end)
    Router.register("match_live", function(params) return MatchLive.create(params) end)
    Router.register("press_conference", function(params) return PressConference.create(params) end)
    Router.register("team_talk", function(params) return TeamTalk.create(params) end)
    Router.register("sponsor_select", function(params) return SponsorSelect.create(params) end)
    Router.register("national_squad_select", function(params) return NationalSquadSelect.create(params) end)
    Router.register("trophy_cabinet", function(params) return TrophyCabinet.create(params) end)
end

------------------------------------------------------
-- 事件绑定
------------------------------------------------------
function BindEvents()
    -- 导航事件：切换页面
    EventBus.on("navigate", function(screenId, params)
        local factory = Router.getFactory(screenId)
        if factory then
            local page = factory(params)
            if page then
                UI.SetRoot(page, true)
            end
        else
            log:Write(LOG_WARNING, "未注册的页面: " .. tostring(screenId))
        end
    end)

    -- 选择球队事件：完成新游戏设置
    EventBus.on("team_selected", function(data)
        local teamId = data.teamId
        local firstName = data.firstName
        local lastName = data.lastName

        if not _G.gameState then return end

        local gs = _G.gameState
        local team = gs.teams[teamId]
        if not team then return end

        -- 创建玩家经理
        local manager = gs:addManager({
            firstName = firstName,
            lastName = lastName,
            displayName = firstName .. " " .. lastName,
            birthYear = 1985,
            nationality = "ENG",
            teamId = teamId,
            isPlayer = true,
            reputation = 300,
        })

        -- 解除原AI经理
        if team.managerId and gs.managers[team.managerId] then
            local oldManager = gs.managers[team.managerId]
            oldManager.teamId = nil
        end

        -- 绑定关系
        team.managerId = manager.id
        gs.playerManagerId = manager.id
        gs.playerTeamId = teamId

        -- 设置玩家所在联赛
        local playerLeague, playerLeagueKey = gs:getTeamLeague(teamId)
        if playerLeague then
            gs.league = playerLeague
            gs.playerLeagueId = playerLeagueKey
        end

        -- 发送欢迎消息
        gs:sendMessage({
            category = "welcome",
            title = "欢迎加入 " .. team.name,
            body = "恭喜你成为 " .. team.name .. " 的新任主教练！带领球队走向辉煌吧。",
            priority = "high",
        })

        local leagueName = playerLeague and playerLeague.name or "联赛"
        local leagueTeamCount = playerLeague and #playerLeague.teamIds or 0
        gs:sendMessage({
            category = "league",
            title = "联赛即将开始",
            body = leagueName .. " " .. gs.season .. " 赛季即将开始，共 " ..
                leagueTeamCount .. " 支球队参赛。准备好了吗？",
            priority = "normal",
        })

        -- 自动保存
        SaveManager.save(gs, "auto")

        -- 进入主页
        Router.clearHistory()
        Router.navigate("dashboard")

        log:Write(LOG_INFO, "新游戏开始: 经理=" .. manager.displayName .. " 球队=" .. team.name)
    end)

    -- 赛季结束事件
    EventBus.on("season_end", function()
        if _G.gameState then
            log:Write(LOG_INFO, "赛季结束，执行赛季结算...")
            local prevSeason = _G.gameState.season
            SeasonManager.endSeason(_G.gameState)
            -- 自动保存
            SaveManager.save(_G.gameState, "auto")
            log:Write(LOG_INFO, "赛季结算完成，新赛季: " .. tostring(_G.gameState.season))
            -- 作弊快进时不跳转页面
            if _G.gameState._cheatAutoPlay then return end
            -- 导航到赛季总结页面
            Router.navigate("season_end", { season = prevSeason })
        end
    end)

    -- 读取存档事件
    EventBus.on("load_save", function(slot)
        _G.gameState = GameState.new()
        local success = SaveManager.load(_G.gameState, slot)
        if success then
            Router.clearHistory()
            Router.navigate("dashboard")
            log:Write(LOG_INFO, "存档加载成功: slot=" .. tostring(slot))
        else
            log:Write(LOG_ERROR, "存档加载失败: slot=" .. tostring(slot))
            Router.navigate("main_menu")
        end
    end)

    -- 夺冠庆祝弹窗
    EventBus.on("championship_won", function(data)
        ChampionshipPopup.show(data)
    end)
end

------------------------------------------------------
-- 页面导航辅助
------------------------------------------------------
function NavigateTo(screenId, params)
    -- 新游戏流程：在进入 create_manager 或 select_team 前确保世界已生成
    if (screenId == "create_manager" or screenId == "select_team") and not _G.gameState then
        log:Write(LOG_INFO, "NavigateTo: 开始世界生成...")
        local gs = GameState.new()
        local ok, err = pcall(function()
            local success = WorldGenerator.generate(gs)
            if not success then
                error("WorldGenerator.generate 返回 false")
            end
        end)
        if ok then
            _G.gameState = gs
            log:Write(LOG_INFO, "NavigateTo: 世界生成成功")
        else
            log:Write(LOG_ERROR, "NavigateTo: 世界生成失败 - " .. tostring(err))
            -- 仍然继续导航，让用户看到错误而非卡住
        end
    end

    Router.navigate(screenId, params)
end

------------------------------------------------------
-- 键盘处理
------------------------------------------------------
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- ESC返回
    if key == KEY_ESCAPE then
        if not Router.back() then
            -- 如果无法返回，回到主菜单
            if _G.gameState then
                SaveManager.save(_G.gameState, "auto")
            end
        end
    end
end
