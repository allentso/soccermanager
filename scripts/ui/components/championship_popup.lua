-- ui/components/championship_popup.lua
-- 夺冠庆祝弹窗 - 赢得联赛/UCL/世界杯时展示

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local TeamIconRegistry = require("scripts/data/team_icon_registry")

local COLORS = Theme.COLORS

local ChampionshipPopup = {}

-- 当前活跃弹窗
local _activeOverlay = nil

------------------------------------------------------
-- 关闭弹窗
------------------------------------------------------

function ChampionshipPopup.close()
    if _activeOverlay then
        _activeOverlay:Close()
        local root = UI.GetRoot()
        if root then
            root:RemoveChild(_activeOverlay)
        end
        _activeOverlay = nil
    end
end

------------------------------------------------------
-- 获取比赛类型展示信息
------------------------------------------------------

local function getCompetitionStyle(competition)
    if competition == "ucl" then
        return {
            title = "欧冠之巅",
            image = "image/trophy_ucl.png",
            accentColor = {80, 150, 255, 255},
            gradientTop = {5, 15, 50, 250},
            gradientBottom = {0, 30, 80, 250},
        }
    elseif competition == "worldcup" then
        return {
            title = "世界之巅",
            image = "image/trophy_worldcup.png",
            accentColor = {255, 200, 80, 255},
            gradientTop = {40, 20, 5, 250},
            gradientBottom = {60, 35, 10, 250},
        }
    else
        return {
            title = "联赛冠军",
            image = "image/trophy_league.png",
            accentColor = {255, 215, 80, 255},
            gradientTop = {15, 18, 35, 250},
            gradientBottom = {25, 30, 50, 250},
        }
    end
end

------------------------------------------------------
-- 展示夺冠弹窗
-- @param data { competition, competitionName, teamName, teamId, season, stats? }
------------------------------------------------------

function ChampionshipPopup.show(data)
    ChampionshipPopup.close()

    local style = getCompetitionStyle(data.competition)
    local stats = data.stats or {}
    local season = data.season or 0
    local gameState = _G.gameState

    -- 获取俱乐部图标路径
    local clubIconPath = nil
    if gameState and data.teamId and gameState.teams then
        local team = gameState.teams[data.teamId]
        if team then
            clubIconPath = TeamIconRegistry.getPathForTeam(team)
        end
    end

    -- 构建统计标签（底部小条）
    local statChips = {}
    if stats.points then
        table.insert(statChips, UI.Panel {
            flexDirection = "row", alignItems = "center",
            backgroundColor = {0, 0, 0, 140},
            borderRadius = 12, paddingHorizontal = 10, paddingVertical = 5,
            marginRight = 8,
            children = {
                UI.Label { text = "积分", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginRight = 4 },
                UI.Label { text = tostring(stats.points), fontSize = 14, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
            }
        })
    end
    if stats.wins then
        table.insert(statChips, UI.Panel {
            flexDirection = "row", alignItems = "center",
            backgroundColor = {0, 0, 0, 140},
            borderRadius = 12, paddingHorizontal = 10, paddingVertical = 5,
            marginRight = 8,
            children = {
                UI.Label { text = "胜场", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginRight = 4 },
                UI.Label { text = tostring(stats.wins), fontSize = 14, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
            }
        })
    end
    if stats.goalsFor then
        table.insert(statChips, UI.Panel {
            flexDirection = "row", alignItems = "center",
            backgroundColor = {0, 0, 0, 140},
            borderRadius = 12, paddingHorizontal = 10, paddingVertical = 5,
            children = {
                UI.Label { text = "进球", fontSize = 10, color = COLORS.TEXT_SECONDARY, marginRight = 4 },
                UI.Label { text = tostring(stats.goalsFor), fontSize = 14, fontWeight = "bold", color = COLORS.TEXT_PRIMARY },
            }
        })
    end

    -- ====== 主弹窗内容 ======
    local content = UI.Panel {
        width = "100%",
        children = {
            -- ====== 立绘大图区域（1:1） ======
            UI.Panel {
                width = "100%",
                aspectRatio = 1,
                borderRadius = 16,
                overflow = "hidden",
                backgroundImage = style.image,
                backgroundSize = "cover",
                justifyContent = "flex-end",
                children = {
                    -- 底部渐变遮罩 + 信息区
                    UI.Panel {
                        width = "100%",
                        paddingTop = 60,
                        paddingBottom = 16,
                        paddingHorizontal = 16,
                        backgroundColor = {0, 0, 0, 0},  -- 由子元素自己处理
                        children = {
                            -- 深色渐变底（模拟渐变效果）
                            UI.Panel {
                                position = "absolute",
                                left = 0, right = 0, bottom = 0, top = 0,
                                backgroundColor = {0, 0, 0, 160},
                            },
                            -- 标题行：俱乐部图标 + 文字
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                alignItems = "center",
                                marginBottom = 6,
                                children = {
                                    -- 俱乐部图标
                                    clubIconPath and UI.Panel {
                                        width = 36, height = 36,
                                        borderRadius = 18,
                                        marginRight = 10,
                                        backgroundImage = clubIconPath,
                                        backgroundSize = "cover",
                                        borderWidth = 2,
                                        borderColor = {255, 255, 255, 100},
                                    } or nil,
                                    -- 文字信息
                                    UI.Panel {
                                        flex = 1,
                                        children = {
                                            UI.Label {
                                                text = style.title,
                                                fontSize = 20, fontWeight = "bold",
                                                color = style.accentColor,
                                            },
                                            UI.Label {
                                                text = (data.teamName or "?") .. " · " ..
                                                    (data.competitionName or "联赛") .. " " ..
                                                    tostring(season) .. "-" .. tostring(season + 1),
                                                fontSize = 11, color = {220, 220, 220, 255},
                                                marginTop = 2,
                                            },
                                        }
                                    },
                                }
                            },
                            -- 统计标签行
                            #statChips > 0 and UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                marginTop = 8,
                                children = statChips,
                            } or nil,
                        }
                    },
                }
            },

            -- ====== 操作按钮 ======
            UI.Panel {
                width = "100%", flexDirection = "row", marginTop = 14,
                children = {
                    UI.Button {
                        text = "荣誉室",
                        height = 40, flexGrow = 1,
                        backgroundColor = style.accentColor,
                        borderRadius = 8,
                        fontSize = 13, fontWeight = "bold",
                        color = {20, 20, 30, 255},
                        marginRight = 8,
                        onClick = function()
                            ChampionshipPopup.close()
                            Router.navigate("trophy_cabinet")
                        end,
                    },
                    UI.Button {
                        text = "继续",
                        height = 40, flexGrow = 1,
                        backgroundColor = COLORS.SECONDARY,
                        borderRadius = 8,
                        fontSize = 13, fontWeight = "bold",
                        color = COLORS.TEXT_PRIMARY,
                        onClick = function()
                            ChampionshipPopup.close()
                        end,
                    },
                }
            },
        }
    }

    -- 使用 Drawer 底部弹出
    local drawer = UI.Drawer {
        position = "bottom",
        size = 580,
        variant = "temporary",
        showOverlay = true,
        overlayOpacity = 0.8,
        backgroundColor = style.gradientTop,
        contentPadding = 16,
        animationDuration = 0.3,
        content = content,
        onClose = function()
            local root = UI.GetRoot()
            if root and _activeOverlay then
                root:RemoveChild(_activeOverlay)
            end
            _activeOverlay = nil
        end,
    }

    _activeOverlay = drawer
    local root = UI.GetRoot()
    if root then
        root:AddChild(drawer)
        drawer:Open()
    end
end

return ChampionshipPopup
