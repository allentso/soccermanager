-- ui/screens/team_talk.lua
-- Team Talk 界面：选择语气 → 查看球员反应结果
-- params: { context = "winning"|"drawing"|"losing", returnTo = "match_live"|"pre_match", returnParams = {} }

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")
local TeamTalkManager = require("scripts/systems/team_talk_manager")

local TeamTalk = {}

-- 界面状态
local _mode = "select"  -- "select" | "result"
local _results = nil
local _selectedTone = nil

function TeamTalk.create(params)
    local gameState = _G.gameState
    if not gameState then
        return UI.Panel {
            width = "100%", height = "100%",
            backgroundColor = Theme.COLORS.BG_DARK,
            children = { UI.Label { text = "加载中..." } }
        }
    end

    local context = params and params.context or "drawing"
    local returnTo = params and params.returnTo or "dashboard"
    local returnParams = params and params.returnParams or {}

    -- 仅在非结果模式时重置状态（从onClick跳转回来时保留结果）
    if not (params and params._showResult) then
        _mode = "select"
        _results = nil
        _selectedTone = nil
    end

    local contextName = TeamTalkManager.getContextName(context)

    -- 构建语气选择卡片
    local toneCards = {}
    local toneDescs = {
        calm = "保持冷静，告诉球员不要紧张",
        motivational = "激励球员，告诉他们有能力做得更好",
        assertive = "明确要求，强调战术执行力",
        aggressive = "强硬施压，告诉球员这不可接受",
        praise = "表扬球员的表现，肯定他们的努力",
        disappointed = "表达失望，告诉球员你的期望更高",
    }

    for _, tone in ipairs(TeamTalkManager.TONES) do
        local toneName = TeamTalkManager.getToneName(tone)
        local toneDesc = toneDescs[tone] or ""

        -- 根据上下文推荐语气
        local isRecommended = false
        if context == "pre_match" and (tone == "motivational" or tone == "calm") then
            isRecommended = true
        elseif context == "winning" and (tone == "calm" or tone == "praise") then
            isRecommended = true
        elseif context == "drawing" and (tone == "motivational" or tone == "assertive") then
            isRecommended = true
        elseif context == "losing" and (tone == "motivational" or tone == "aggressive") then
            isRecommended = true
        end

        table.insert(toneCards, UI.Button {
            width = "100%",
            height = 64,
            backgroundColor = isRecommended
                and {Theme.COLORS.PRIMARY[1], Theme.COLORS.PRIMARY[2], Theme.COLORS.PRIMARY[3], 40}
                or Theme.COLORS.BG_CARD,
            borderRadius = 8,
            marginBottom = 8,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 14, paddingRight = 14,
            pointerEvents = "box-only",
            onClick = function()
                _selectedTone = tone
                _results = TeamTalkManager.deliverTeamTalk(gameState, tone, context)
                _mode = "result"
                local navParams = {}
                for k, v in pairs(params or {}) do navParams[k] = v end
                navParams._showResult = true
                Router.replaceWith("team_talk", navParams)
            end,
            children = {
                UI.Panel {
                    width = 36, height = 36,
                    borderRadius = 18,
                    backgroundColor = Theme.COLORS.PRIMARY,
                    justifyContent = "center",
                    alignItems = "center",
                    marginRight = 12,
                    children = {
                        UI.Label {
                            text = string.sub(toneName, 1, 3),
                            fontSize = 13,
                            color = Theme.COLORS.TEXT_PRIMARY,
                            fontWeight = "bold",
                        },
                    }
                },
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center",
                            children = {
                                UI.Label {
                                    text = toneName,
                                    fontSize = 14,
                                    color = Theme.COLORS.TEXT_PRIMARY,
                                    fontWeight = "bold",
                                },
                                isRecommended and UI.Label {
                                    text = " 推荐",
                                    fontSize = 10,
                                    color = Theme.COLORS.ACCENT,
                                    marginLeft = 6,
                                } or UI.Panel { width = 0 },
                            }
                        },
                        UI.Label {
                            text = toneDesc,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            marginTop = 2,
                        },
                    }
                },
            }
        })
    end

    -- 判断显示哪个界面
    if _mode == "result" and _results then
        return TeamTalk._buildResultPage(params, returnTo, returnParams)
    end

    -- 选择语气界面
    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%", height = 48,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Button {
                        text = "< 返回",
                        width = 60, height = 32,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 13, color = Theme.COLORS.ACCENT,
                        onClick = function()
                            Router.navigate(returnTo, returnParams)
                        end,
                    },
                    UI.Label {
                        text = "赛前训话",
                        fontSize = 15,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                        textAlign = "center",
                    },
                    UI.Panel { width = 60 },  -- 平衡
                }
            },

            -- 上下文提示
            UI.Panel {
                width = "100%",
                paddingLeft = 14, paddingRight = 14, paddingTop = 12, paddingBottom = 8,
                children = {
                    UI.Label {
                        text = string.format("当前局面：%s", contextName),
                        fontSize = 13,
                        color = Theme.COLORS.ACCENT,
                    },
                    UI.Label {
                        text = "选择你对球员们说话的语气：",
                        fontSize = 12,
                        color = Theme.COLORS.TEXT_SECONDARY,
                        marginTop = 4,
                    },
                }
            },

            -- 语气列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 14,
                children = toneCards,
            },
        }
    }
end

------------------------------------------------------
-- 结果页
------------------------------------------------------
function TeamTalk._buildResultPage(params, returnTo, returnParams)
    local toneName = _selectedTone and TeamTalkManager.getToneName(_selectedTone) or "?"

    -- 统计反应
    local posCount, neuCount, negCount = 0, 0, 0
    for _, r in ipairs(_results) do
        if r.band == "strong_pos" or r.band == "mild_pos" then
            posCount = posCount + 1
        elseif r.band == "mild_neg" or r.band == "strong_neg" then
            negCount = negCount + 1
        else
            neuCount = neuCount + 1
        end
    end

    -- 构建球员反应列表
    local playerRows = {}
    -- 按 delta 绝对值排序（反应最强的在前）
    local sorted = {}
    for _, r in ipairs(_results) do table.insert(sorted, r) end
    table.sort(sorted, function(a, b) return math.abs(a.delta) > math.abs(b.delta) end)

    for i, r in ipairs(sorted) do
        local display = TeamTalkManager.getBandDisplay(r.band)
        local deltaStr = r.delta >= 0 and string.format("+%d", r.delta) or tostring(r.delta)
        local deltaColor = r.delta > 0 and Theme.COLORS.SECONDARY
            or (r.delta < 0 and Theme.COLORS.DANGER or Theme.COLORS.TEXT_MUTED)

        table.insert(playerRows, UI.Panel {
            width = "100%", height = 36,
            flexDirection = "row",
            alignItems = "center",
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = i % 2 == 0 and {255, 255, 255, 5} or Theme.COLORS.TRANSPARENT,
            children = {
                UI.Label {
                    text = r.position or "?",
                    fontSize = 11, color = Theme.COLORS.TEXT_MUTED,
                    width = 32,
                },
                UI.Label {
                    text = r.name,
                    fontSize = 12, color = Theme.COLORS.TEXT_PRIMARY,
                    flexGrow = 1, flexShrink = 1,
                },
                UI.Label {
                    text = display.text,
                    fontSize = 11, color = display.color,
                    width = 65, textAlign = "right",
                },
                UI.Label {
                    text = deltaStr,
                    fontSize = 12, color = deltaColor,
                    width = 35, textAlign = "right",
                    fontWeight = "bold",
                },
            }
        })
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%", height = 48,
                flexDirection = "row", alignItems = "center",
                paddingLeft = 14, paddingRight = 14,
                backgroundColor = Theme.COLORS.BG_HEADER,
                children = {
                    UI.Label {
                        text = "训话结果",
                        fontSize = 15,
                        color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Button {
                        text = "继续",
                        width = 60, height = 32,
                        backgroundColor = Theme.COLORS.PRIMARY,
                        borderRadius = 6,
                        fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                        onClick = function()
                            _mode = "select"
                            _results = nil
                            Router.navigate(returnTo, returnParams)
                        end,
                    },
                }
            },

            -- 训话摘要
            UI.Panel {
                width = "100%",
                paddingLeft = 14, paddingRight = 14,
                paddingTop = 12, paddingBottom = 12,
                backgroundColor = Theme.COLORS.BG_CARD,
                children = {
                    UI.Label {
                        text = string.format("你以「%s」的语气对球员们讲话", toneName),
                        fontSize = 13, color = Theme.COLORS.TEXT_PRIMARY,
                    },
                    UI.Panel {
                        flexDirection = "row", marginTop = 8,
                        children = {
                            TeamTalk._statBadge("积极", posCount, Theme.COLORS.SECONDARY),
                            TeamTalk._statBadge("中立", neuCount, Theme.COLORS.TEXT_MUTED),
                            TeamTalk._statBadge("消极", negCount, Theme.COLORS.DANGER),
                        }
                    },
                }
            },

            -- 球员反应列表
            UI.Panel {
                width = "100%", paddingLeft = 14, paddingRight = 14, paddingTop = 8,
                children = {
                    UI.Panel {
                        width = "100%", height = 28,
                        flexDirection = "row", alignItems = "center",
                        paddingLeft = 10, paddingRight = 10,
                        children = {
                            UI.Label { text = "位置", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 32 },
                            UI.Label { text = "球员", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, flexGrow = 1 },
                            UI.Label { text = "反应", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 65, textAlign = "right" },
                            UI.Label { text = "士气", fontSize = 10, color = Theme.COLORS.TEXT_MUTED, width = 35, textAlign = "right" },
                        }
                    },
                }
            },
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                paddingLeft = 14, paddingRight = 14,
                children = playerRows,
            },
        }
    }
end

function TeamTalk._statBadge(label, count, color)
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        marginRight = 14,
        children = {
            UI.Panel {
                width = 8, height = 8, borderRadius = 4,
                backgroundColor = color, marginRight = 4,
            },
            UI.Label {
                text = string.format("%s %d", label, count),
                fontSize = 11, color = color,
            },
        }
    }
end

return TeamTalk
