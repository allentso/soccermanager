-- ui/screens/settings.lua
-- 设置页面 - 音量、自动保存、货币单位、游戏速度等

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local SaveManager = require("scripts/persistence/save_manager")
local EventBus = require("scripts/app/event_bus")
local League = require("scripts/domain/league")

local Settings = {}

-- 作弊：连点版本号计数
local _cheatTapCount = 0
local _cheatLastTap = 0
local CHEAT_TAP_THRESHOLD = 7
local CHEAT_TAP_TIMEOUT = 3.0  -- 3秒内连续点击

-- 默认设置
local _defaults = {
    masterVolume = 80,
    musicVolume = 60,
    sfxVolume = 80,
    autoSave = true,
    autoSaveInterval = 5,   -- 每5个回合自动保存
    currencyUnit = "wan",   -- "km"(K/M) | "wan"(万)

    confirmActions = true,  -- 重要操作前确认
    showTutorials = true,
}

-- 持久化设置（初始化为默认值）
local _settings = {}
for k, v in pairs(_defaults) do _settings[k] = v end

------------------------------------------------------
-- 主入口
------------------------------------------------------
function Settings.create(params)
    -- 从 gameState 读取设置
    if _G.gameState and _G.gameState.settings then
        for k, v in pairs(_G.gameState.settings) do
            _settings[k] = v
        end
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function()
                            Settings._saveSettings()
                            Router.back()
                        end,
                    },
                    UI.Label {
                        text = "设置",
                        fontSize = 18,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Button {
                        text = "重置",
                        width = 60, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 13,
                        color = Theme.COLORS.DANGER,
                        onClick = function()
                            for k, v in pairs(_defaults) do _settings[k] = v end
                            Settings._saveSettings()
                            Router.replaceWith("settings")
                        end,
                    },
                }
            },

            -- 内容
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = {
                    -- 音频设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("音频设置"),
                            Settings._sliderRow("主音量", _settings.masterVolume, function(v)
                                _settings.masterVolume = v
                                Settings._saveSettings()
                            end),
                            Settings._sliderRow("音乐音量", _settings.musicVolume, function(v)
                                _settings.musicVolume = v
                                Settings._saveSettings()
                            end),
                            Settings._sliderRow("音效音量", _settings.sfxVolume, function(v)
                                _settings.sfxVolume = v
                                Settings._saveSettings()
                            end),
                        }
                    },

                    -- 游戏设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("游戏设置"),
                            Settings._selectRow("货币显示", {
                                { key = "wan", label = "万 (w)" },
                                { key = "km", label = "K/M" },
                            }, _settings.currencyUnit, function(v)
                                _settings.currencyUnit = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                        }
                    },

                    -- 自动保存设置
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("存档设置"),
                            Settings._toggleRow("自动保存", _settings.autoSave, function(v)
                                _settings.autoSave = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                            _settings.autoSave and Settings._selectRow("保存频率", {
                                { key = 3, label = "每3回合" },
                                { key = 5, label = "每5回合" },
                                { key = 10, label = "每10回合" },
                            }, _settings.autoSaveInterval, function(v)
                                _settings.autoSaveInterval = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end) or UI.Panel { height = 0 },
                            Settings._toggleRow("操作确认提示", _settings.confirmActions, function(v)
                                _settings.confirmActions = v
                                Settings._saveSettings()
                                Router.replaceWith("settings")
                            end),
                        }
                    },

                    -- 帮助
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("关于"),
                            Settings._versionRow(),
                            Settings._infoRow("存档版本", "v" .. Constants.SAVE_VERSION),
                            Theme.Divider(),
                            UI.Button {
                                text = "查看存档管理",
                                width = "100%",
                                height = 40,
                                backgroundColor = {38, 46, 71, 255},
                                borderRadius = 8,
                                fontSize = 13,
                                color = Theme.COLORS.TEXT_SECONDARY,
                                marginTop = 6,
                                onClick = function()
                                    Settings._saveSettings()
                                    Router.navigate("load_game")
                                end,
                            },
                        }
                    },

                    -- 底部间距
                    UI.Panel { height = 20 },
                }
            },

            -- 底部导航
            Theme.MainNav("home"),
        }
    }
end

------------------------------------------------------
-- 组件工厂
------------------------------------------------------
function Settings._sectionTitle(text)
    return UI.Label {
        text = text,
        fontSize = 14,
        color = Theme.COLORS.TEXT_PRIMARY,
        fontWeight = "bold",
        marginBottom = 10,
    }
end

function Settings._sliderRow(label, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 44,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                width = 70,
            },
            UI.Slider {
                flexGrow = 1,
                value = value,
                min = 0,
                max = 100,
                height = 30,
                onChange = function(self, v)
                    if onChange then onChange(math.floor(v)) end
                end,
            },
            UI.Label {
                text = tostring(math.floor(value)) .. "%",
                fontSize = 12,
                color = Theme.COLORS.TEXT_MUTED,
                width = 40,
                textAlign = "right",
            },
        }
    }
end

function Settings._toggleRow(label, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 44,
        marginBottom = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexGrow = 1,
            },
            UI.Button {
                text = value and "开启" or "关闭",
                width = 60, height = 30,
                backgroundColor = value and Theme.COLORS.SECONDARY or {60, 60, 80, 255},
                borderRadius = 15,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                onClick = function()
                    if onChange then onChange(not value) end
                end,
            },
        }
    }
end

function Settings._selectRow(label, options, currentValue, onChange)
    local btns = {}
    for _, opt in ipairs(options) do
        local isActive = opt.key == currentValue
        table.insert(btns, UI.Button {
            text = opt.label,
            height = 28,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 14,
            fontSize = 11,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 4,
            onClick = function()
                if onChange then onChange(opt.key) end
            end,
        })
    end
    return UI.Panel {
        width = "100%",
        marginBottom = 8,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 6,
            },
            UI.Panel {
                flexDirection = "row",
                flexWrap = "wrap",
                children = btns,
            },
        }
    }
end

function Settings._infoRow(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 36,
        children = {
            UI.Label {
                text = label,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexGrow = 1,
            },
            UI.Label {
                text = value,
                fontSize = 13,
                color = Theme.COLORS.TEXT_MUTED,
            },
        }
    }
end

------------------------------------------------------
-- 版本号行（连点7次触发作弊）
------------------------------------------------------
function Settings._versionRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 36,
        onClick = function()
            Settings._handleCheatTap()
        end,
        children = {
            UI.Label {
                text = "版本",
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                flexGrow = 1,
            },
            UI.Label {
                text = "v" .. Constants.VERSION,
                fontSize = 13,
                color = Theme.COLORS.TEXT_MUTED,
            },
        }
    }
end

function Settings._handleCheatTap()
    local now = os.clock()
    if now - _cheatLastTap > CHEAT_TAP_TIMEOUT then
        _cheatTapCount = 0
    end
    _cheatLastTap = now
    _cheatTapCount = _cheatTapCount + 1

    if _cheatTapCount >= CHEAT_TAP_THRESHOLD then
        _cheatTapCount = 0
        Settings._showCheatMenu()
    end
end

function Settings._showCheatMenu()
    local BottomSheet = require("scripts/ui/components/bottom_sheet")
    BottomSheet.showCustom({
        title = "开发者工具",
        height = 300,
        children = {
            UI.Button {
                text = "👑 三冠王（联赛+欧冠+世界杯）",
                width = "100%",
                height = 44,
                backgroundColor = Theme.COLORS.MATCH_ORANGE,
                color = "#FFFFFF",
                fontSize = 14,
                borderRadius = 8,
                marginBottom = 12,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatTripleCrown()
                end,
            },
            UI.Button {
                text = "⏩ 跳到世界杯",
                width = "100%",
                height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14,
                borderRadius = 8,
                marginBottom = 12,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSkipToWorldCup()
                end,
            },
            UI.Button {
                text = "🏆 查看荣誉室",
                width = "100%",
                height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14,
                borderRadius = 8,
                onClick = function()
                    BottomSheet.close()
                    Router.navigate("trophy_cabinet")
                end,
            },
        },
    })
end

------------------------------------------------------
-- 作弊：三冠王（联赛+欧冠+世界杯）
------------------------------------------------------
function Settings._cheatTripleCrown()
    local gameState = _G.gameState
    if not gameState then return end

    local SeasonManager = require("scripts/systems/season_manager")
    local RecordsManager = require("scripts/systems/records_manager")
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    local playerLeague = gameState.league
    if not playerLeague then return end

    gameState._cheatAutoPlay = true

    -- 1. 完成玩家联赛，确保玩家夺冠（全胜）
    if playerLeague.fixtures then
        for _, f in ipairs(playerLeague.fixtures) do
            if f.status ~= "finished" then
                f.status = "finished"
                if f.homeTeamId == playerTeamId then
                    f.homeGoals = math.random(2, 4)
                    f.awayGoals = 0
                elseif f.awayTeamId == playerTeamId then
                    f.homeGoals = 0
                    f.awayGoals = math.random(2, 4)
                else
                    f.homeGoals = math.random(0, 2)
                    f.awayGoals = math.random(0, 2)
                end
                pcall(function() playerLeague:updateStanding(f) end)
            end
        end
    end

    -- 2. 完成其他联赛
    Settings._completeOtherLeagues(gameState, playerLeague)

    -- 3. 完成欧冠并让玩家夺冠
    if gameState.championsLeague then
        local ucl = gameState.championsLeague
        if ucl.leaguePhase and ucl.leaguePhase.fixtures then
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    f.homeGoals = math.random(0, 3)
                    f.awayGoals = math.random(0, 3)
                    pcall(function() ucl:updateLeagueStanding(f) end)
                end
            end
        end
        ucl.phase = "completed"
        ucl.winner = playerTeamId
    end
    -- 触发欧冠夺冠记录
    RecordsManager.onUCLChampionship(gameState, playerTeamId)

    -- 4. 触发世界杯夺冠记录（模拟玩家国家队夺冠）
    RecordsManager.onWorldCupChampionship(gameState, playerTeamId)

    -- 5. 执行赛季结算（会触发联赛夺冠记录 RecordsManager.onSeasonEnd）
    pcall(SeasonManager.endSeason, gameState)

    gameState._cheatAutoPlay = nil

    -- 保存并跳转赛季总结
    SaveManager.save(gameState, "auto")
    Router.replaceWith("season_end", { season = gameState.season - 1 })
end

-- 完成除玩家联赛外的其他联赛
function Settings._completeOtherLeagues(gameState, excludeLeague)
    if not gameState.leagues then return end
    for _, lg in pairs(gameState.leagues) do
        if lg ~= excludeLeague and lg.fixtures then
            for _, f in ipairs(lg.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    f.homeGoals = math.random(0, 3)
                    f.awayGoals = math.random(0, 3)
                    pcall(function() lg:updateStanding(f) end)
                end
            end
        end
    end
end



function Settings._cheatSkipToWorldCup()
    local gameState = _G.gameState
    if not gameState then return end

    local SeasonManager = require("scripts/systems/season_manager")

    -- 计算下一个世界杯年份（首届2026，每4年一届）
    local FIRST_WC = 2026
    local CYCLE = 4
    local currentYear = gameState.date.year
    local wcYear = FIRST_WC
    while wcYear < currentYear do
        wcYear = wcYear + CYCLE
    end
    -- 如果当前年份已经是世界杯年且已过6月13日，取下一届
    if wcYear == currentYear then
        local pastTarget = (gameState.date.month > 6) or
            (gameState.date.month == 6 and gameState.date.day >= 13)
        if pastTarget then
            wcYear = wcYear + CYCLE
        end
    end

    -- 快速跳转：直接做赛季结算，不逐天模拟
    gameState._cheatAutoPlay = true

    -- 需要跨越的赛季数（赛季从8月开始，6月属于上个赛季周期末尾）
    -- 目标：到达 wcYear 年 6月13日
    -- 赛季 N 覆盖 N年8月 → N+1年5月，然后6-7月是休赛期/世界杯
    -- 当前赛季 = gameState.season (对应 season/season+1)
    local targetSeason = wcYear - 1  -- 世界杯在 targetSeason 赛季的赛季末举办

    while gameState.season < targetSeason do
        -- 完成当前联赛（给所有比赛设置假结果）
        Settings._completeAllLeagues(gameState)
        -- 执行赛季结算（包含新赛季初始化、欧冠、世界杯等）
        pcall(SeasonManager.endSeason, gameState)
    end

    -- 设置日期到世界杯前一天
    gameState.date = { year = wcYear, month = 6, day = 13 }
    gameState.dayOfWeek = League._dayOfWeek(gameState.date)

    gameState._cheatAutoPlay = nil

    -- 保存并刷新
    SaveManager.save(gameState, "auto")
    Router.replaceWith("dashboard")
end

-- 快速完成所有联赛（给未完赛的比赛随机赋分）
function Settings._completeAllLeagues(gameState)
    if not gameState.leagues then return end
    for _, lg in pairs(gameState.leagues) do
        if lg.fixtures then
            for _, f in ipairs(lg.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    f.homeGoals = math.random(0, 3)
                    f.awayGoals = math.random(0, 3)
                    -- 更新积分榜
                    pcall(function() lg:updateStanding(f) end)
                end
            end
        end
    end
    -- 也完成欧冠
    if gameState.championsLeague then
        local ucl = gameState.championsLeague
        if ucl.leaguePhase and ucl.leaguePhase.fixtures then
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    f.homeGoals = math.random(0, 3)
                    f.awayGoals = math.random(0, 3)
                    pcall(function() ucl:updateLeagueStanding(f) end)
                end
            end
        end
        -- 标记完成
        ucl.phase = "completed"
    end
end

------------------------------------------------------
-- 保存设置到 gameState
------------------------------------------------------
function Settings._saveSettings()
    if _G.gameState then
        _G.gameState.settings = {}
        for k, v in pairs(_settings) do
            _G.gameState.settings[k] = v
        end
        -- 持久化到磁盘
        SaveManager.save(_G.gameState, "auto")
    end
end

return Settings
