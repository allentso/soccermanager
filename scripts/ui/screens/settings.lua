-- ui/screens/settings.lua
-- 设置页面 - 音量、自动保存、货币单位、游戏速度等

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local Constants = require("scripts/app/constants")
local SaveManager = require("scripts/persistence/save_manager")
local SettingsManager = require("scripts/persistence/settings_manager")
local EventBus = require("scripts/app/event_bus")
local League = require("scripts/domain/league")
local DifficultySettings = require("scripts/systems/difficulty_settings")

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
                            SettingsManager.resetToDefaults()
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
                                SettingsManager.set("masterVolume", v)
                            end),
                            Settings._sliderRow("音乐音量", _settings.musicVolume, function(v)
                                _settings.musicVolume = v
                                SettingsManager.set("musicVolume", v)
                            end),
                            Settings._sliderRow("音效音量", _settings.sfxVolume, function(v)
                                _settings.sfxVolume = v
                                SettingsManager.set("sfxVolume", v)
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
                            -- 赛程修复工具（面向玩家）
                            UI.Panel {
                                width = "100%",
                                marginTop = 14,
                                paddingTop = 14,
                                borderTopWidth = 1,
                                borderTopColor = Theme.COLORS.DIVIDER,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        justifyContent = "spaceBetween",
                                        alignItems = "center",
                                        children = {
                                            UI.Label {
                                                text = "赛程修复",
                                                fontSize = 14,
                                                color = Theme.COLORS.TEXT_PRIMARY,
                                            },
                                            UI.Button {
                                                text = "一键修复",
                                                height = 32,
                                                paddingLeft = 16, paddingRight = 16,
                                                backgroundColor = Theme.COLORS.SECONDARY,
                                                borderRadius = 6,
                                                fontSize = 13,
                                                color = "#FFFFFF",
                                                onClick = function()
                                                    Settings._repairOverdueFixtures()
                                                end,
                                            },
                                        }
                                    },
                                    UI.Label {
                                        text = "如遇比赛积压卡顿，点击可自动补齐逾期比赛",
                                        fontSize = 11,
                                        color = Theme.COLORS.TEXT_MUTED,
                                        marginTop = 6,
                                    },
                                }
                            },
                        }
                    },

                    -- 难度调节 + 存档设置（合并双栏）
                    Settings._buildDifficultyAndSaveCard(),

                    -- 开始新游戏
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("新游戏"),
                            UI.Label {
                                text = "放弃当前存档，重新选择球队开始新赛季",
                                fontSize = 12,
                                color = Theme.COLORS.TEXT_MUTED,
                                marginBottom = 10,
                            },
                            UI.Button {
                                text = "开始新游戏",
                                width = "100%",
                                height = 44,
                                backgroundColor = Theme.COLORS.DANGER,
                                borderRadius = 8,
                                fontSize = 14,
                                fontWeight = "bold",
                                color = "#FFFFFF",
                                onClick = function()
                                    Settings._confirmNewGame()
                                end,
                            },
                        }
                    },

                    -- 帮助与指引
                    Theme.Card {
                        children = {
                            Settings._sectionTitle("帮助"),
                            UI.Button {
                                text = "📖 重看新手指引",
                                width = "100%",
                                height = 42,
                                backgroundColor = {38, 46, 71, 255},
                                borderRadius = 8,
                                fontSize = 13,
                                color = Theme.COLORS.GOLD,
                                marginBottom = 8,
                                onClick = function()
                                    local TutorialGuide = require("scripts/ui/components/tutorial_guide")
                                    Router.replaceWith("dashboard")
                                    TutorialGuide.start()
                                end,
                            },
                        }
                    },

                    -- 关于
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
    local valLabel = UI.Label {
        text = tostring(math.floor(value)) .. "%",
        fontSize = 12,
        color = Theme.COLORS.TEXT_MUTED,
        width = 40,
        textAlign = "right",
    }
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
                    local intVal = math.floor(v)
                    valLabel:SetText(tostring(intVal) .. "%")
                    if onChange then onChange(intVal) end
                end,
            },
            valLabel,
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
        height = 750,
        children = {
            UI.Button {
                text = "👑 三冠王（联赛+欧冠+世界杯）",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.MATCH_ORANGE,
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatTripleCrown()
                end,
            },

            UI.Button {
                text = "⏭️ 跳到赛季末",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSkipToSeasonEnd()
                end,
            },
            UI.Button {
                text = "📊 预算分配测试（结算+报告）",
                width = "100%", height = 44,
                backgroundColor = "#1A5276",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatBudgetAllocationTest()
                end,
            },
            UI.Button {
                text = "⏩ 跳到世界杯",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSkipToWorldCup()
                end,
            },

            UI.Button {
                text = "⭐ 声望 MAX（99）",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatMaxReputation()
                end,
            },

            UI.Button {
                text = "🏆 查看荣誉室",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Router.navigate("trophy_cabinet")
                end,
            },
            -- 传奇抽卡相关
            UI.Button {
                text = "🎰 解锁传奇池",
                width = "100%", height = 44,
                backgroundColor = "#6C3483",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatUnlockLegendPool()
                end,
            },
            UI.Button {
                text = "🎫 +100 抽取次数",
                width = "100%", height = 44,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatAddPulls()
                end,
            },


            -- 修复工具
            UI.Button {
                text = "🔧 修复赛程（自动模拟逾期比赛）",
                width = "100%", height = 44,
                backgroundColor = "#1E8449",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._repairOverdueFixtures()
                end,
            },
            -- 模拟解雇
            UI.Button {
                text = "🚪 模拟被解雇",
                width = "100%", height = 44,
                backgroundColor = "#922B21",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSimulateSacked()
                end,
            },
            -- UCL迁移测试
            UI.Button {
                text = "🐛 模拟UCL覆盖存档（测试迁移）",
                width = "100%", height = 44,
                backgroundColor = "#922B21",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSimulateUCLOverwrite()
                end,
            },
            -- 坏存档模拟（测试 sanitize + healInPlace）
            UI.Button {
                text = "💀 模拟坏存档（NaN/Inf/稀疏）",
                width = "100%", height = 44,
                backgroundColor = "#6C3483",
                color = "#FFFFFF",
                fontSize = 14, borderRadius = 8, marginTop = 10,
                onClick = function()
                    BottomSheet.close()
                    Settings._cheatSimulateCorruptSave()
                end,
            },
        },
    })
end

------------------------------------------------------
-- 作弊：声望 MAX
------------------------------------------------------
function Settings._cheatMaxReputation()
    local gameState = _G.gameState
    if not gameState then return end

    local manager = gameState:getPlayerManager()
    if not manager then return end

    manager.reputation = 99

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "career",
        title = "声望已满",
        body = "开发者工具：声望已设为 99（传奇）。",
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：声望重置
------------------------------------------------------
function Settings._cheatResetReputation()
    local gameState = _G.gameState
    if not gameState then return end

    local manager = gameState:getPlayerManager()
    if not manager then return end

    manager.reputation = 30

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "career",
        title = "声望已重置",
        body = "开发者工具：声望已重置为 30（新人）。",
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：资金注入 +5000万
------------------------------------------------------
function Settings._cheatAddFunds()
    local gameState = _G.gameState
    if not gameState then return end

    local FinanceManager = require("scripts/systems/finance_manager")
    local team = gameState.teams[gameState.playerTeamId]
    if not team then return end

    local amount = 50000000  -- 5000万
    team.balance = (team.balance or 0) + amount
    team.transferBudget = (team.transferBudget or 0) + amount
    team.seasonIncome = (team.seasonIncome or 0) + amount
    FinanceManager.addTransaction(team, {
        amount = amount,
        description = "开发者资金注入",
        category = "injection",
        season = gameState.season,
    })

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "finance",
        title = "资金到账",
        body = "开发者工具：已注入 5000万 资金到转会预算。",
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：跳到赛季末（快速完成剩余比赛）
------------------------------------------------------
function Settings._cheatSkipToSeasonEnd()
    local gameState = _G.gameState
    if not gameState then return end

    local SeasonManager = require("scripts/systems/season_manager")
    gameState._cheatAutoPlay = true

    -- 完成所有联赛和欧冠
    Settings._completeAllLeagues(gameState)

    -- 执行赛季结算
    pcall(SeasonManager.endSeason, gameState)

    gameState._cheatAutoPlay = nil

    -- 安全检查：确保玩家球队仍在联赛中且 standings 正确
    Settings._ensurePlayerLeagueIntegrity(gameState)

    SaveManager.save(gameState, "auto")
    Router.replaceWith("season_end", { season = gameState.season - 1 })
end

------------------------------------------------------
-- 作弊：模拟被解雇
------------------------------------------------------
function Settings._cheatSimulateSacked()
    local gameState = _G.gameState
    if not gameState then return end

    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then
        gameState:sendMessage({
            category = "career",
            title = "无法解雇",
            body = "你当前没有执教任何球队（已经失业了）。",
            priority = "normal",
        })
        Router.replaceWith("dashboard")
        return
    end

    local team = gameState.teams[playerTeamId]
    local teamName = team and team.name or "未知球队"

    -- 调用正式解雇流程
    local JobManager = require("scripts/systems/job_manager")
    JobManager.handleSacked(gameState)

    -- 发送解雇消息
    gameState:sendMessage({
        category = "career",
        title = "你被解雇了！",
        body = string.format("开发者工具：模拟被 %s 解雇。你现在处于失业状态，可以查看空缺职位或等待邀约。", teamName),
        priority = "critical",
    })

    SaveManager.save(gameState, "auto")
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：青训神童（生成一个高潜力年轻球员）
------------------------------------------------------
function Settings._cheatYouthProdigy()
    local gameState = _G.gameState
    if not gameState then return end

    local team = gameState.teams[gameState.playerTeamId]
    if not team then return end

    -- 生成一个高潜力青训球员
    local positions = {"GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST"}
    local pos = positions[RandomInt(1, #positions)]
    local age = RandomInt(16, 17)

    local playerData = {
        name = "Youth Prodigy",
        firstName = "天才",
        lastName = "小将",
        age = age,
        birthYear = gameState.date.year - age,
        position = pos,
        nationality = "中国",
        potential = RandomInt(85, 95),
        overall = RandomInt(55, 65),
        teamId = gameState.playerTeamId,
        wage = 1000,
        contractYears = 4,
        isYouth = true,
    }

    local player = gameState:addPlayer(playerData)
    player.potential = playerData.potential

    -- 加入球队
    if not team.playerIds then team.playerIds = {} end
    table.insert(team.playerIds, player.id)

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "youth",
        title = "青训惊喜！",
        body = string.format("开发者工具：%s（%s，%d岁，潜力%d）已加入一线队。",
            player.name or "天才小将", pos, age, playerData.potential),
        priority = "high",
    })
    Router.replaceWith("dashboard")
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
                    f.homeGoals = RandomInt(2, 4)
                    f.awayGoals = 0
                elseif f.awayTeamId == playerTeamId then
                    f.homeGoals = 0
                    f.awayGoals = RandomInt(2, 4)
                else
                    f.homeGoals = RandomInt(0, 2)
                    f.awayGoals = RandomInt(0, 2)
                end
                pcall(function() playerLeague:updateStanding(f) end)
                -- 写入个人履历和声望
                Settings._recordPlayerFixture(gameState, f)
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
                    f.homeGoals = RandomInt(0, 3)
                    f.awayGoals = RandomInt(0, 3)
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
                    f.homeGoals = RandomInt(0, 3)
                    f.awayGoals = RandomInt(0, 3)
                    pcall(function() lg:updateStanding(f) end)
                    -- 写入个人履历和声望（以防玩家球队出现在其他联赛）
                    Settings._recordPlayerFixture(gameState, f)
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

    -- 世界杯在 wcYear 年6-7月举行（赛季 wcYear-1 结束后的夏天）
    -- endSeason 会调用 _startNewSeason → season+1 → WorldCup.initialize
    -- 所以需要让 endSeason 将 season 推进到 wcYear（WC 在此时初始化）
    -- 循环：完成所有赛季直到 season 达到 wcYear
    while gameState.season < wcYear do
        -- 完成当前联赛（给所有比赛设置假结果）
        Settings._completeAllLeagues(gameState)
        -- 执行赛季结算（包含新赛季初始化、欧冠、世界杯等）
        pcall(SeasonManager.endSeason, gameState)
    end

    -- 设置日期到世界杯前一天（赛季已经是 wcYear，WC 已初始化）
    gameState.date = { year = wcYear, month = 6, day = 13 }
    gameState.dayOfWeek = League._dayOfWeek(gameState.date)

    gameState._cheatAutoPlay = nil

    -- 保存并刷新
    SaveManager.save(gameState, "auto")
    Router.replaceWith("dashboard")
end

-- 快速完成所有联赛（给未完赛的比赛随机赋分）
------------------------------------------------------
-- 辅助：将比赛结果写入个人履历和声望（作弊模式用）
------------------------------------------------------
function Settings._recordPlayerFixture(gameState, fixture)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    local isHome = fixture.homeTeamId == playerTeamId
    local isAway = fixture.awayTeamId == playerTeamId
    if not isHome and not isAway then return end

    -- 写入个人履历（wins/draws/losses/streaks）
    local RecordsManager = require("scripts/systems/records_manager")
    pcall(RecordsManager.onMatchEnd, gameState, fixture)

    -- 更新声望
    local ReputationManager = require("scripts/systems/reputation_manager")
    local homeGoals = fixture.homeGoals or 0
    local awayGoals = fixture.awayGoals or 0
    local opponentId, result, goalDiff

    if isHome then
        opponentId = fixture.awayTeamId
        goalDiff = homeGoals - awayGoals
    else
        opponentId = fixture.homeTeamId
        goalDiff = awayGoals - homeGoals
    end

    if goalDiff > 0 then
        result = "W"
    elseif goalDiff == 0 then
        result = "D"
    else
        result = "L"
    end

    pcall(ReputationManager.postMatchUpdate, gameState, playerTeamId, opponentId, result, goalDiff)
end

------------------------------------------------------
-- 安全网：确保赛季结算后玩家球队仍在联赛中且数据完整
------------------------------------------------------
function Settings._ensurePlayerLeagueIntegrity(gameState)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end

    -- 1. 确认 gameState.league 正确指向包含玩家球队的联赛
    local foundLeague = nil
    local foundLeagueKey = nil
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds or {}) do
            if tid == playerTeamId then
                foundLeague = lg
                foundLeagueKey = leagueKey
                break
            end
        end
        if foundLeague then break end
    end

    if not foundLeague then
        -- 玩家球队不在任何顶级联赛中（可能被降级了）
        -- 强制恢复：将玩家球队重新加回原联赛
        local targetLeague = gameState.league
        if not targetLeague then
            -- 用 playerLeagueId 找联赛
            targetLeague = gameState.leagues[gameState.playerLeagueId]
        end
        if not targetLeague then
            -- 取第一个联赛
            for _, lg in pairs(gameState.leagues) do
                targetLeague = lg
                break
            end
        end
        if targetLeague then
            table.insert(targetLeague.teamIds, playerTeamId)
            foundLeague = targetLeague
            -- 从二级联赛储备池中移除（如果在的话）
            if gameState.secondDivision then
                for _, sd in pairs(gameState.secondDivision) do
                    for i, tid in ipairs(sd.teamIds or {}) do
                        if tid == playerTeamId then
                            table.remove(sd.teamIds, i)
                            break
                        end
                    end
                end
            end
        end
    end

    if foundLeague then
        gameState.league = foundLeague
        if foundLeagueKey then
            gameState.playerLeagueId = foundLeagueKey
        end

        -- 2. 确保 standings 中有玩家球队
        if not foundLeague.standings[playerTeamId] then
            foundLeague.standings[playerTeamId] = {
                teamId = playerTeamId,
                played = 0, won = 0, drawn = 0, lost = 0,
                goalsFor = 0, goalsAgainst = 0, goalDifference = 0, points = 0,
            }
        end

        -- 3. 确保 fixtures 中有玩家球队的比赛
        local hasFixture = false
        for _, f in ipairs(foundLeague.fixtures or {}) do
            if (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId)
                and f.status == "scheduled" then
                hasFixture = true
                break
            end
        end
        if not hasFixture then
            -- 重新生成赛程
            local Constants = require("scripts/app/constants")
            local leagueStartDate = {
                year = gameState.season,
                month = Constants.SEASON_START_MONTH,
                day = Constants.SEASON_START_DAY,
            }
            pcall(function()
                foundLeague:initStandings()
                foundLeague:generateFixtures(leagueStartDate)
            end)
        end
    end
end

function Settings._completeAllLeagues(gameState)
    if not gameState.leagues then return end
    local playerTeamId = gameState.playerTeamId

    for _, lg in pairs(gameState.leagues) do
        if lg.fixtures then
            for _, f in ipairs(lg.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    -- 玩家球队比赛结果偏向赢球，防止随机降级
                    local isPlayerHome = (f.homeTeamId == playerTeamId)
                    local isPlayerAway = (f.awayTeamId == playerTeamId)
                    if isPlayerHome then
                        f.homeGoals = RandomInt(1, 3)
                        f.awayGoals = RandomInt(0, 1)
                    elseif isPlayerAway then
                        f.homeGoals = RandomInt(0, 1)
                        f.awayGoals = RandomInt(1, 3)
                    else
                        f.homeGoals = RandomInt(0, 3)
                        f.awayGoals = RandomInt(0, 3)
                    end
                    -- 更新积分榜
                    pcall(function() lg:updateStanding(f) end)
                    -- 写入个人履历和声望
                    Settings._recordPlayerFixture(gameState, f)
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
                    local isPlayerHome = (f.homeTeamId == playerTeamId)
                    local isPlayerAway = (f.awayTeamId == playerTeamId)
                    if isPlayerHome then
                        f.homeGoals = RandomInt(1, 3)
                        f.awayGoals = RandomInt(0, 1)
                    elseif isPlayerAway then
                        f.homeGoals = RandomInt(0, 1)
                        f.awayGoals = RandomInt(1, 3)
                    else
                        f.homeGoals = RandomInt(0, 3)
                        f.awayGoals = RandomInt(0, 3)
                    end
                    pcall(function() ucl:updateLeagueStanding(f) end)
                    -- 写入个人履历和声望
                    Settings._recordPlayerFixture(gameState, f)
                end
            end
        end
        -- 标记完成
        ucl.phase = "completed"
    end
end

------------------------------------------------------
-- 开始新游戏确认
------------------------------------------------------
function Settings._confirmNewGame()
    local BottomSheet = require("scripts/ui/components/bottom_sheet")
    local GameState = require("scripts/core/game_state")
    local WorldGenerator = require("scripts/systems/world_generator")

    BottomSheet.showCustom({
        title = "确认开始新游戏",
        height = 220,
        children = {
            UI.Label {
                text = "当前存档进度将丢失，确定要开始新游戏吗？",
                fontSize = 14,
                color = Theme.COLORS.TEXT_SECONDARY,
                marginBottom = 20,
                textAlign = "center",
                width = "100%",
            },
            UI.Button {
                text = "确认，重新开始",
                width = "100%",
                height = 44,
                backgroundColor = Theme.COLORS.DANGER,
                borderRadius = 8,
                fontSize = 14,
                fontWeight = "bold",
                color = "#FFFFFF",
                marginBottom = 10,
                onClick = function()
                    BottomSheet.close()
                    -- 重置游戏状态并生成新世界
                    local gs = GameState.new()
                    local ok, err = pcall(function()
                        local success = WorldGenerator.generate(gs)
                        if not success then
                            error("WorldGenerator.generate 返回 false")
                        end
                    end)
                    if ok then
                        _G.gameState = gs
                        -- 直接跳到选择球队（跳过输入名字）
                        Router.clearHistory()
                        Router.navigate("select_team", {
                            firstName = "Alex",
                            lastName = "Manager",
                        })
                    else
                        log:Write(LOG_ERROR, "新游戏世界生成失败: " .. tostring(err))
                    end
                end,
            },
            UI.Button {
                text = "取消",
                width = "100%",
                height = 40,
                backgroundColor = Theme.COLORS.BG_CARD_ELEVATED,
                borderRadius = 8,
                fontSize = 13,
                color = Theme.COLORS.TEXT_SECONDARY,
                onClick = function()
                    BottomSheet.close()
                end,
            },
        },
    })
end

------------------------------------------------------
-- 保存设置到 gameState
------------------------------------------------------
function Settings._saveSettings()
    if _G.gameState then
        -- 保留 difficulty 等非 UI 设置字段，只合并 _settings 中的内容
        _G.gameState.settings = _G.gameState.settings or {}
        for k, v in pairs(_settings) do
            _G.gameState.settings[k] = v
        end
        -- 持久化到磁盘
        SaveManager.save(_G.gameState, "auto")
    end
end

------------------------------------------------------
-- 作弊：解锁传奇池
------------------------------------------------------
function Settings._cheatUnlockLegendPool()
    local gameState = _G.gameState
    if not gameState then return end

    local YouthManager = require("scripts/systems/youth_manager")
    local state = YouthManager.getLegendGachaState(gameState)

    state.unlocked = true
    state.adsWatched = YouthManager.getUnlockAdsRequired()
    -- 赠送10次抽取
    state.pulls = math.max(state.pulls, 10)

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "youth",
        title = "传奇池已解锁",
        body = "开发者工具：传奇池已直接解锁，当前可用抽取次数：" .. state.pulls,
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：+100 抽取次数
------------------------------------------------------
function Settings._cheatAddPulls()
    local gameState = _G.gameState
    if not gameState then return end

    local YouthManager = require("scripts/systems/youth_manager")
    local state = YouthManager.getLegendGachaState(gameState)

    -- 如果未解锁，先自动解锁
    if not state.unlocked then
        state.unlocked = true
        state.adsWatched = YouthManager.getUnlockAdsRequired()
    end

    state.pulls = (state.pulls or 0) + 100

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "youth",
        title = "抽取次数增加",
        body = "开发者工具：+100 抽取次数，当前可用：" .. state.pulls,
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：下次十连必出传奇（设置保底计数到极限）
------------------------------------------------------
function Settings._cheatForceLegend()
    local gameState = _G.gameState
    if not gameState then return end

    local YouthManager = require("scripts/systems/youth_manager")
    local state = YouthManager.getLegendGachaState(gameState)

    -- 如果未解锁，先自动解锁
    if not state.unlocked then
        state.unlocked = true
        state.adsWatched = YouthManager.getUnlockAdsRequired()
        state.pulls = math.max(state.pulls or 0, 10)
    end

    -- 设置保底计数为9，下次十连必触发保底
    state.pityCounter = 9
    -- 确保有足够抽取次数
    if (state.pulls or 0) < 10 then
        state.pulls = 10
    end

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "youth",
        title = "保底已就绪",
        body = "开发者工具：下次十连抽必定出传奇球员！当前可用抽取次数：" .. state.pulls,
        priority = "high",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：重置传奇池（清空已抽取记录，可重复抽）
------------------------------------------------------
function Settings._cheatResetLegendPool()
    local gameState = _G.gameState
    if not gameState then return end

    local YouthManager = require("scripts/systems/youth_manager")
    local state = YouthManager.getLegendGachaState(gameState)

    local previousCount = state.pulledLegends and #state.pulledLegends or 0
    state.pulledLegends = {}
    state.pityCounter = 0
    state.firstTenPull = true

    SaveManager.save(gameState, "auto")
    gameState:sendMessage({
        category = "youth",
        title = "传奇池已重置",
        body = string.format("开发者工具：已清空 %d 条抽取记录，所有传奇球员可重新抽取。", previousCount),
        priority = "normal",
    })
    Router.replaceWith("dashboard")
end

------------------------------------------------------
-- 作弊：预算分配测试（完成赛季 + 结算 + 展示财务报告）
------------------------------------------------------
function Settings._cheatBudgetAllocationTest()
    local gameState = _G.gameState
    if not gameState then return end

    local SeasonManager = require("scripts/systems/season_manager")
    local FinanceManager = require("scripts/systems/finance_manager")
    local BottomSheet = require("scripts/ui/components/bottom_sheet")

    local team = gameState.teams[gameState.playerTeamId]
    if not team then return end

    -- 快照：结算前数据
    local preSeason = gameState.season
    local preBalance = team.balance or 0
    local preSeasonIncome = team.seasonIncome or 0
    local preSeasonExpense = team.seasonExpense or 0
    local preBreakdown = {}
    if team.incomeBreakdown then
        for k, v in pairs(team.incomeBreakdown) do preBreakdown[k] = v end
    end

    -- 1. 快速完成所有联赛/欧冠比赛（会产生票房收入）
    gameState._cheatAutoPlay = true
    Settings._completeAllLeagues(gameState)

    -- 快照更新（完成比赛后票房等收入已入账）
    local postMatchIncome = team.seasonIncome or 0
    local postMatchBreakdown = {}
    if team.incomeBreakdown then
        for k, v in pairs(team.incomeBreakdown) do postMatchBreakdown[k] = v end
    end

    -- 2. 执行赛季结算（奖金发放、赞助条款、预算分配）
    pcall(SeasonManager.endSeason, gameState)
    gameState._cheatAutoPlay = nil

    -- 3. 结算后数据
    local postBalance = team.balance or 0
    local postTransferBudget = team.transferBudget or 0
    local postWageBudget = team.wageBudget or 0

    -- 计算实际周薪
    local actualWeeklyWage = 0
    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p then actualWeeklyWage = actualWeeklyWage + (p.wage or 0) end
    end

    -- 联赛排名
    local position = "N/A"
    if gameState.leagues then
        for _, lg in pairs(gameState.leagues) do
            for _, tid in ipairs(lg.teamIds) do
                if tid == gameState.playerTeamId then
                    local pos = lg:getTeamPosition(gameState.playerTeamId)
                    if pos then position = tostring(pos) end
                    break
                end
            end
        end
    end

    -- 4. 格式化展示
    local fmtM = function(v) return string.format("%.1fM", (v or 0) / 1000000) end
    local fmtK = function(v) return string.format("%.0fK", (v or 0) / 1000) end

    local lines = {}
    table.insert(lines, string.format("赛季 %d → %d 结算完成", preSeason, gameState.season))
    table.insert(lines, string.format("联赛排名: 第 %s 名", position))
    table.insert(lines, "")
    table.insert(lines, "── 赛季收支 ──")
    table.insert(lines, string.format("总收入: %s  总支出: %s", fmtM(postMatchIncome), fmtM(preSeasonExpense)))
    table.insert(lines, string.format("净利润: %s", fmtM(postMatchIncome - preSeasonExpense)))
    table.insert(lines, "")
    table.insert(lines, "── 收入明细 ──")
    local bd = postMatchBreakdown
    if (bd.ticket or 0) > 0 then table.insert(lines, "  票房: " .. fmtM(bd.ticket)) end
    if (bd.sponsor or 0) > 0 then table.insert(lines, "  赞助: " .. fmtM(bd.sponsor)) end
    if (bd.broadcast or 0) > 0 then table.insert(lines, "  转播: " .. fmtM(bd.broadcast)) end
    if (bd.merchandise or 0) > 0 then table.insert(lines, "  商品: " .. fmtM(bd.merchandise)) end
    if (bd.prize or 0) > 0 then table.insert(lines, "  奖金: " .. fmtM(bd.prize)) end
    if (bd.transfer or 0) > 0 then table.insert(lines, "  转会: " .. fmtM(bd.transfer)) end
    table.insert(lines, "")
    table.insert(lines, "── 预算分配结果 ──")
    table.insert(lines, string.format("余额: %s → %s", fmtM(preBalance), fmtM(postBalance)))
    table.insert(lines, string.format("转会预算: %s", fmtM(postTransferBudget)))
    table.insert(lines, string.format("工资预算: %s/周", fmtK(postWageBudget)))
    table.insert(lines, string.format("实际周薪: %s/周", fmtK(actualWeeklyWage)))
    table.insert(lines, "")
    table.insert(lines, "── 公式参数 ──")
    table.insert(lines, string.format("声望: %d  repFactor: %.2f", team.reputation or 0, 0.5 + ((team.reputation or 50) / 99)))
    table.insert(lines, string.format("余额×25%%×repFactor = %s", fmtM(math.floor((postBalance) * 0.25 * (0.5 + ((team.reputation or 50) / 99))))))
    table.insert(lines, string.format("球场容量: %d 人", team.stadiumCapacity or 0))

    -- 展示报告面板
    local reportChildren = {}
    for _, line in ipairs(lines) do
        table.insert(reportChildren, UI.Label {
            text = line,
            fontSize = 13,
            color = (line:find("──") or line == "") and Theme.COLORS.TEXT_HINT or Theme.COLORS.TEXT_PRIMARY,
            width = "100%",
            marginBottom = line == "" and 6 or 2,
        })
    end

    BottomSheet.showCustom({
        title = "📊 预算分配测试报告",
        height = 680,
        children = {
            UI.ScrollView {
                width = "100%", height = 580,
                children = reportChildren,
            },
        },
    })

    SaveManager.save(gameState, "auto")
end

------------------------------------------------------
-- 难度调节 + 存档设置（双栏合并）
------------------------------------------------------
function Settings._buildDifficultyAndSaveCard()
    local diff = DifficultySettings.get()
    local params = DifficultySettings.PARAMS

    -- 左栏：难度调节
    ---@type table[]
    local diffChildren = {
        Settings._sectionTitle("难度调节"),
    }
    for _, param in ipairs(params) do
        local currentTier = diff[param.key] or 2
        diffChildren[#diffChildren + 1] = Settings._difficultyTierRow(param, currentTier)
    end

    -- 右栏：存档设置
    ---@type table[]
    local saveChildren = {
        Settings._sectionTitle("存档设置"),
        Settings._toggleRow("自动保存", _settings.autoSave, function(v)
            _settings.autoSave = v
            Settings._saveSettings()
            Router.replaceWith("settings")
        end),
        _settings.autoSave and Settings._selectRow("保存频率", {
            { key = 3, label = "3回合" },
            { key = 5, label = "5回合" },
            { key = 10, label = "10回合" },
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

    return Theme.Card {
        children = {
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                alignItems = "stretch",
                children = {
                    -- 左栏：难度
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        paddingRight = 8,
                        children = diffChildren,
                    },
                    -- 分隔线
                    UI.Panel {
                        width = 1,
                        alignSelf = "stretch",
                        backgroundColor = Theme.COLORS.BORDER,
                    },
                    -- 右栏：存档
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        paddingLeft = 12,
                        children = saveChildren,
                    },
                },
            },
        }
    }
end

--- 难度档位行：标题 + 3个按钮 + 当前档位描述
function Settings._difficultyTierRow(param, currentTier)
    local hintLabel = UI.Label {
        text = param.tierHints[currentTier] or "",
        fontSize = 10,
        color = Theme.COLORS.TEXT_MUTED,
        marginTop = 2,
    }

    local tierButtons = {}
    for i, tierName in ipairs(DifficultySettings.TIER_LABELS) do
        local isActive = (i == currentTier)
        tierButtons[#tierButtons + 1] = UI.Button {
            text = tierName,
            fontSize = 11,
            width = 50,
            height = 26,
            marginRight = (i < 3) and 4 or 0,
            variant = isActive and "primary" or "ghost",
            onClick = function(self)
                DifficultySettings.set(param.key, i)
                Settings._saveSettings()
                Router.replaceWith("settings")
            end,
        }
    end

    return UI.Panel {
        width = "100%",
        marginBottom = 10,
        children = {
            UI.Label {
                text = param.name,
                fontSize = 12,
                color = Theme.COLORS.TEXT_PRIMARY,
                fontWeight = "bold",
                marginBottom = 3,
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                children = tierButtons,
            },
            hintLabel,
        }
    }
end

------------------------------------------------------
-- 作弊：模拟UCL覆盖bug存档（用于测试迁移方案）
-- 模拟旧版本中联赛结束后 _startNewSeason 直接覆盖进行中UCL的状态
------------------------------------------------------
function Settings._cheatSimulateUCLOverwrite()
    local gameState = _G.gameState
    if not gameState then return end

    local ChampionsLeague = require("scripts/systems/champions_league")
    local SeasonManager = require("scripts/systems/season_manager")

    local prevSeason = gameState.season
    print("[CHEAT] 模拟UCL覆盖bug：当前赛季=" .. prevSeason)

    -- 1. 快速完成联赛（但不触发赛季结算，模拟联赛结束的状态）
    for _, lg in pairs(gameState.leagues) do
        if lg.fixtures then
            for _, f in ipairs(lg.fixtures) do
                if f.status ~= "finished" then
                    f.status = "finished"
                    f.homeGoals = RandomInt(0, 3)
                    f.awayGoals = RandomInt(0, 3)
                    -- 更新积分榜
                    lg:updateStanding(f)
                end
            end
        end
        lg._seasonComplete = true
    end

    -- 2. 记录赛季历史（模拟 _recordSeasonHistory 正常执行）
    local seasonRecord = {
        season = prevSeason,
        leagues = {},
    }
    for key, lg in pairs(gameState.leagues) do
        local sorted = lg:getSortedStandings()
        local championEntry = sorted[1]
        local championTeam = championEntry and gameState.teams[championEntry.teamId]
        seasonRecord.leagues[key] = {
            name = lg.name,
            champion = championEntry and {
                teamId = championEntry.teamId,
                teamName = championTeam and championTeam.name or "?",
                points = championEntry.points or 0,
            } or nil,
        }
    end
    table.insert(gameState.worldHistory, seasonRecord)

    -- 3. 模拟 _startNewSeason 的核心操作：递增赛季 + 重建联赛 + 覆盖UCL
    gameState.season = prevSeason + 1
    gameState.date = {
        year = gameState.season,
        month = 8,
        day = 10,
    }
    gameState.dayOfWeek = 1

    -- 重置联赛
    local Constants = require("scripts/app/constants")
    local leagueStartDate = {
        year = gameState.season,
        month = Constants.SEASON_START_MONTH,
        day = Constants.SEASON_START_DAY,
    }
    for _, lg in pairs(gameState.leagues) do
        lg:initStandings()
        lg.season = gameState.season
        lg.currentRound = 1
        lg:generateFixtures(leagueStartDate)
    end

    -- 4. 关键：用 ChampionsLeague.initialize 覆盖UCL（模拟bug行为）
    ChampionsLeague.initialize(gameState)

    -- 5. 清除迁移标记（模拟老存档没有这些字段）
    gameState._uclCompletedSeasons = nil
    gameState._uclOverwritePatched = nil
    gameState._seasonEndProcessing = nil
    gameState.pendingPlayerFixture = nil

    -- 6. 通知用户
    gameState:sendMessage({
        category = "system",
        title = "🐛 测试存档已生成",
        body = string.format(
            "已模拟UCL覆盖bug状态：\n" ..
            "- 从第%d赛季跳到第%d赛季\n" ..
            "- 上赛季UCL数据已被覆盖（无完成记录）\n" ..
            "- 联赛已重置为新赛季\n\n" ..
            "请前往欧冠页面触发迁移检测。",
            prevSeason, gameState.season
        ),
        priority = "high",
    })

    print("[CHEAT] 模拟完成：season=" .. gameState.season ..
        ", UCL phase=" .. (gameState.championsLeague and gameState.championsLeague.phase or "nil") ..
        ", _uclCompletedSeasons=nil, _uclOverwritePatched=nil")
    print("[CHEAT] 请前往欧冠页面（联赛视图→欧冠tab）触发 migrateIfNeeded 检测")

    -- 刷新当前页面
    Router.navigate("settings")
end

------------------------------------------------------
-- 修复工具：自动模拟所有逾期的玩家比赛
------------------------------------------------------
function Settings._repairOverdueFixtures()
    local gameState = _G.gameState
    if not gameState then return end

    local MatchEngine = require("scripts/match/match_engine")
    local TurnProcessor = require("scripts/core/turn_processor")
    local ChampionsLeague = require("scripts/systems/champions_league")
    local SaveManager = require("scripts/persistence/save_manager")
    local currentDate = gameState.date
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then
        UI.Toast.Show({ message = "无玩家球队", variant = "error" })
        return
    end

    local repaired = 0
    local results = {}

    -- 1. 修复逾期联赛比赛（包含当天未打的比赛，避免卡住）
    for _, lg in pairs(gameState.leagues or {}) do
        for _, fixture in ipairs(lg.fixtures or {}) do
            if fixture.status == "scheduled" and fixture.date
                and TurnProcessor._isDateBeforeOrEqual(fixture.date, currentDate) then
                local isPlayerMatch = (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)
                if isPlayerMatch then
                    -- 自动模拟
                    local report = MatchEngine.simulate(gameState, fixture)
                    if report then
                        MatchEngine.applyResult(gameState, fixture, report)
                        repaired = repaired + 1
                        local homeTeam = gameState.teams[fixture.homeTeamId]
                        local awayTeam = gameState.teams[fixture.awayTeamId]
                        table.insert(results, string.format(
                            "[联赛] %s %d-%d %s",
                            homeTeam and homeTeam.shortName or "?",
                            report.homeGoals, report.awayGoals,
                            awayTeam and awayTeam.shortName or "?"
                        ))
                    end
                    -- 清除 pending 标记
                    fixture._pendingPlayerMatch = nil
                end
            end
        end
    end

    -- 2. 修复逾期欧冠比赛（包含当天未打的比赛）
    local ucl = gameState.championsLeague
    if ucl and ucl.phase ~= "completed" then
        -- 联赛阶段
        if ucl.leaguePhase and ucl.leaguePhase.fixtures then
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f.status == "scheduled" and f.date
                    and TurnProcessor._isDateBeforeOrEqual(f.date, currentDate) then
                    local isPlayerMatch = (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId)
                    if isPlayerMatch then
                        local report = MatchEngine.simulate(gameState, f)
                        if report then
                            f.status = "finished"
                            f.homeGoals = report.homeGoals or 0
                            f.awayGoals = report.awayGoals or 0
                            f.events = report.events
                            ucl:updateLeagueStanding(f)
                            repaired = repaired + 1
                            local homeTeam = gameState.teams[f.homeTeamId]
                            local awayTeam = gameState.teams[f.awayTeamId]
                            table.insert(results, string.format(
                                "[欧冠] %s %d-%d %s",
                                homeTeam and homeTeam.shortName or "?",
                                report.homeGoals, report.awayGoals,
                                awayTeam and awayTeam.shortName or "?"
                            ))
                        end
                        f._pendingPlayerMatch = nil
                    end
                end
            end
        end
        -- 淘汰赛阶段
        if ucl.knockout then
            local phases = {"playoff", "r16", "qf", "sf", "final"}
            for _, phase in ipairs(phases) do
                local fixtures = ucl.knockout[phase]
                if fixtures then
                    for _, f in ipairs(fixtures) do
                        if f.status == "scheduled" and f.date
                            and TurnProcessor._isDateBeforeOrEqual(f.date, currentDate) then
                            local isPlayerMatch = (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId)
                            if isPlayerMatch then
                                f._isUCL = true
                                f.tournamentPhase = phase
                                local report = MatchEngine.simulate(gameState, f)
                                if report then
                                    TurnProcessor._applyUCLResult(gameState, f, report)
                                    repaired = repaired + 1
                                    local homeTeam = gameState.teams[f.homeTeamId]
                                    local awayTeam = gameState.teams[f.awayTeamId]
                                    table.insert(results, string.format(
                                        "[欧冠%s] %s %d-%d %s",
                                        phase,
                                        homeTeam and homeTeam.shortName or "?",
                                        report.homeGoals, report.awayGoals,
                                        awayTeam and awayTeam.shortName or "?"
                                    ))
                                end
                                f._pendingPlayerMatch = nil
                            end
                        end
                    end
                end
            end
        end
        -- 修复后检查阶段推进
        ChampionsLeague.checkPhaseAdvance(gameState)
    end

    -- 3. 清除 pendingPlayerFixture（如果有）
    gameState.pendingPlayerFixture = nil

    -- 4. 保存
    SaveManager.save(gameState, "auto")

    -- 5. 反馈
    if repaired == 0 then
        UI.Toast.Show({ message = "没有逾期比赛，赛程正常", variant = "info" })
    else
        local summary = string.format("已自动模拟 %d 场逾期比赛:\n%s", repaired, table.concat(results, "\n"))
        gameState:sendMessage({
            category = "system",
            title = "🔧 赛程修复完成",
            body = summary,
            priority = "high",
        })
        UI.Toast.Show({ message = string.format("已修复 %d 场逾期比赛", repaired), variant = "success" })
        print("[REPAIR] " .. summary)
    end

    -- 刷新页面
    Router.navigate("settings")
end

------------------------------------------------------
-- 作弊：模拟坏存档（NaN / Infinity / 稀疏数组）
-- 用途：验证 save_manager 的 sanitize + healInPlace 机制
-- 注入后下次保存会触发慢路径（编码失败→诊断→治疗→重试），
-- 治疗成功后再次保存应恢复快路径（单次编码直通）。
------------------------------------------------------
function Settings._cheatSimulateCorruptSave()
    local gameState = _G.gameState
    if not gameState then
        UI.Toast.Show({ message = "gameState 不存在", variant = "error" })
        return
    end

    local nanCount = 0
    local infCount = 0
    local sparseCount = 0

    -- ======================================================
    -- 1. 批量注入 NaN：模拟比赛引擎除零累积（~30% 球员）
    -- ======================================================
    local NaN = 0 / 0
    local playerIds = {}
    for id in pairs(gameState.players) do
        playerIds[#playerIds + 1] = id
    end

    -- 污染约 30% 的球员（至少 20 个，最多 80 个）
    local nanTarget = math.max(20, math.min(80, math.floor(#playerIds * 0.3)))
    -- 打乱顺序，随机选取
    for i = #playerIds, 2, -1 do
        local j = math.random(1, i)
        playerIds[i], playerIds[j] = playerIds[j], playerIds[i]
    end

    for i = 1, math.min(nanTarget, #playerIds) do
        local p = gameState.players[playerIds[i]]
        if p then
            if p.stats then
                -- 每个球员污染 2~4 个 stat 字段
                local statKeys = {}
                for k, v in pairs(p.stats) do
                    if type(v) == "number" then
                        statKeys[#statKeys + 1] = k
                    end
                end
                local count = math.min(#statKeys, math.random(2, 4))
                for j = 1, count do
                    p.stats[statKeys[j]] = NaN
                    nanCount = nanCount + 1
                end
            end
            -- 球员顶层数值也可能坏（value、morale、form）
            if type(p.value) == "number" then
                p.value = NaN; nanCount = nanCount + 1
            end
            if type(p.morale) == "number" and math.random() > 0.5 then
                p.morale = NaN; nanCount = nanCount + 1
            end
        end
    end

    -- ======================================================
    -- 2. 批量注入 Infinity：模拟财务计算溢出（所有球队）
    -- ======================================================
    for _, team in pairs(gameState.teams) do
        if team.finance then
            -- 往 finance 子表中随机写几个 Infinity
            team.finance._wageOverflow = math.huge
            team.finance._debtUnderflow = -math.huge
            infCount = infCount + 2
            if type(team.finance.balance) == "number" and math.random() > 0.6 then
                team.finance.balance = math.huge
                infCount = infCount + 1
            end
        else
            team._budgetOverflow = math.huge
            infCount = infCount + 1
        end
    end

    -- 联赛积分表也注入一些 NaN（模拟 GD 除零）
    for _, lg in pairs(gameState.leagues) do
        if lg.standings then
            for _, entry in pairs(lg.standings) do
                if type(entry) == "table" and type(entry.goalDifference) == "number" then
                    if math.random() > 0.7 then
                        entry.goalDifference = NaN
                        nanCount = nanCount + 1
                    end
                end
            end
        end
    end

    -- ======================================================
    -- 3. 批量制造稀疏数组：inbox、news、各联赛 fixtures
    -- ======================================================
    local function pokeHoles(arr, name, holeCount)
        local len = #arr
        if len < 5 then return 0 end
        local poked = 0
        local maxHoles = math.min(holeCount, math.floor(len * 0.3))
        for _ = 1, maxHoles do
            local idx = math.random(2, len - 1)  -- 避免首尾
            if rawget(arr, idx) ~= nil then
                rawset(arr, idx, nil)
                poked = poked + 1
            end
        end
        if poked > 0 then
            print("[CHEAT-CORRUPT] 稀疏数组: " .. name .. " 挖了 " .. poked .. " 个洞 (原长 " .. len .. ")")
        end
        return poked
    end

    if gameState.inbox then
        sparseCount = sparseCount + pokeHoles(gameState.inbox, "inbox", 8)
    end
    if gameState.news then
        sparseCount = sparseCount + pokeHoles(gameState.news, "news", 5)
    end

    -- fixtures 数组也可能有空洞
    for lgKey, lg in pairs(gameState.leagues) do
        if lg.fixtures and #lg.fixtures >= 10 then
            sparseCount = sparseCount + pokeHoles(lg.fixtures, "leagues." .. lgKey .. ".fixtures", 6)
        end
    end

    -- transfers.history 也挖几个
    if gameState.transfers and gameState.transfers.history and #gameState.transfers.history >= 5 then
        sparseCount = sparseCount + pokeHoles(gameState.transfers.history, "transfers.history", 4)
    end

    -- ======================================================
    -- 汇总
    -- ======================================================
    local total = nanCount + infCount + sparseCount
    local msg = string.format(
        "注入完成: %d 处 NaN, %d 处 Inf, %d 处稀疏空洞 (共 %d)",
        nanCount, infCount, sparseCount, total
    )
    print("[CHEAT-CORRUPT] === " .. msg .. " ===")
    print("[CHEAT-CORRUPT] 下次保存将触发慢路径 → sanitize + healInPlace")
    print("[CHEAT-CORRUPT] 治疗成功后再次保存应恢复快路径")

    UI.Toast.Show({
        message = msg,
        variant = "warning",
        duration = 5000,
    })
end

return Settings
