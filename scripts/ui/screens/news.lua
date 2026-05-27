-- ui/screens/news.lua
-- 新闻页面 - 联赛动态、比赛报道、转会传闻、伤病、人事变动

local UI = require("urhox-libs/UI")
local Theme = require("scripts/ui/theme")
local Router = require("scripts/app/router")

local News = {}

-- 新闻分类标签（扩展：增加伤病、人事、里程碑）
local NEWS_CATEGORIES = {
    { key = "all",       label = "全部" },
    { key = "match",     label = "比赛" },
    { key = "transfer",  label = "转会" },
    { key = "league",    label = "联赛" },
    { key = "injury",    label = "伤病" },
    { key = "personnel", label = "人事" },
}

-- 分类颜色
local CAT_COLORS = {
    match_report  = {33, 150, 243, 255},
    transfer_news = {255, 153, 0, 255},
    league_news   = {76, 175, 80, 255},
    weekly_report = {156, 39, 176, 255},
    season_news   = {0, 188, 212, 255},
    injury_news   = {244, 67, 54, 255},
    manager_news  = {121, 85, 72, 255},
    milestone     = {255, 215, 0, 255},
}

-- 分类到tab映射
local CAT_TAB_MAP = {
    match_report  = "match",
    transfer_news = "transfer",
    league_news   = "league",
    weekly_report = "league",
    season_news   = "league",
    injury_news   = "injury",
    manager_news  = "personnel",
    milestone     = "match",
}

-- 分类中文名
local CAT_DISPLAY_NAMES = {
    match_report  = "比赛报道",
    transfer_news = "转会消息",
    league_news   = "联赛动态",
    weekly_report = "每周总结",
    season_news   = "赛季动态",
    injury_news   = "伤病报告",
    manager_news  = "教练变动",
    milestone     = "里程碑",
}

------------------------------------------------------
-- 统计各 tab 的未读数
------------------------------------------------------
local function countUnreadByTab(newsList)
    local counts = { all = 0, match = 0, transfer = 0, league = 0, injury = 0, personnel = 0 }
    for _, article in ipairs(newsList) do
        if not article.read then
            counts.all = counts.all + 1
            local tab = CAT_TAB_MAP[article.category] or "league"
            if counts[tab] then
                counts[tab] = counts[tab] + 1
            end
        end
    end
    return counts
end

------------------------------------------------------
-- 新闻排序：未读优先 → 日期新优先
------------------------------------------------------
local function sortNews(list, gameState)
    table.sort(list, function(a, b)
        -- 未读优先
        if (not a.read) ~= (not b.read) then
            return not a.read
        end
        -- 日期新的在前（比较日期 table）
        if a.date and b.date then
            if a.date.year ~= b.date.year then return a.date.year > b.date.year end
            if a.date.month ~= b.date.month then return a.date.month > b.date.month end
            if a.date.day ~= b.date.day then return a.date.day > b.date.day end
        end
        return false
    end)
end

------------------------------------------------------
-- 根据新闻内容确定跳转目标
------------------------------------------------------
local function getNavigationTarget(article)
    if article.category == "match_report" then
        if article.matchId then
            return "match_result", { matchId = article.matchId }
        elseif article.relatedTeams and #article.relatedTeams > 0 then
            return "team_detail", { teamId = article.relatedTeams[1] }
        end
    elseif article.category == "transfer_news" then
        if article.playerId then
            return "player_detail", { playerId = article.playerId }
        elseif article.relatedTeams and #article.relatedTeams > 0 then
            return "team_detail", { teamId = article.relatedTeams[#article.relatedTeams] }
        end
    elseif article.category == "injury_news" then
        if article.playerId then
            return "player_detail", { playerId = article.playerId }
        elseif article.relatedTeams and #article.relatedTeams > 0 then
            return "team_detail", { teamId = article.relatedTeams[1] }
        end
    elseif article.category == "manager_news" then
        if article.relatedTeams and #article.relatedTeams > 0 then
            return "team_detail", { teamId = article.relatedTeams[1] }
        end
    elseif article.category == "milestone" then
        if article.playerId then
            return "player_detail", { playerId = article.playerId }
        elseif article.relatedTeams and #article.relatedTeams > 0 then
            return "team_detail", { teamId = article.relatedTeams[1] }
        end
    elseif article.category == "league_news" or article.category == "season_news" then
        return "league", {}
    end
    return nil, nil
end

------------------------------------------------------
-- 创建页面
------------------------------------------------------
function News.create(params)
    local gameState = _G.gameState
    if not gameState then return UI.Panel { width = "100%", height = "100%" } end

    local currentTab = (params and params.tab) or "all"

    -- 统计未读数
    local unreadCounts = countUnreadByTab(gameState.news or {})

    -- 过滤新闻
    local filteredNews = {}
    for _, article in ipairs(gameState.news or {}) do
        local artTab = CAT_TAB_MAP[article.category] or "league"
        if currentTab == "all" or artTab == currentTab then
            table.insert(filteredNews, article)
        end
    end

    -- 排序：未读在前，日期新的在前
    sortNews(filteredNews, gameState)

    -- 构建标签按钮（带未读计数徽章）
    local tabButtons = {}
    for _, cat in ipairs(NEWS_CATEGORIES) do
        local isActive = cat.key == currentTab
        local unreadN = unreadCounts[cat.key] or 0

        -- 标签文本（有未读数时显示）
        local labelText = cat.label
        if unreadN > 0 and cat.key ~= "all" then
            labelText = cat.label .. "(" .. unreadN .. ")"
        end

        table.insert(tabButtons, UI.Button {
            text = labelText,
            height = 34,
            paddingLeft = 10,
            paddingRight = 10,
            backgroundColor = isActive and Theme.COLORS.PRIMARY or {38, 46, 71, 255},
            borderRadius = 17,
            fontSize = 12,
            color = isActive and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
            marginRight = 6,
            onClick = function()
                Router.replaceWith("news", { tab = cat.key })
            end,
        })
    end

    -- 构建新闻卡片
    local newsCards = {}
    local maxShow = math.min(80, #filteredNews)

    for i = 1, maxShow do
        local article = filteredNews[i]
        local catColor = CAT_COLORS[article.category] or Theme.COLORS.TEXT_MUTED
        local isUnread = not article.read

        -- 格式化日期
        local dateStr = ""
        if article.date then
            dateStr = string.format("%d年%d月%d日", article.date.year, article.date.month, article.date.day)
        end

        -- 判断是否涉及玩家球队
        local isRelevant = false
        if article.relatedTeams and gameState.playerTeamId then
            for _, tid in ipairs(article.relatedTeams) do
                if tid == gameState.playerTeamId then
                    isRelevant = true
                    break
                end
            end
        end

        table.insert(newsCards, UI.Panel {
            width = "100%",
            backgroundColor = isRelevant and {30, 40, 70, 255} or Theme.COLORS.BG_CARD,
            borderRadius = 10,
            padding = 12,
            marginBottom = 8,
            borderLeftWidth = 3,
            borderColor = catColor,
            children = {
                -- 头部：分类+日期+标记
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    marginBottom = 6,
                    children = {
                        -- 分类标签
                        UI.Panel {
                            backgroundColor = {catColor[1], catColor[2], catColor[3], 40},
                            borderRadius = 4,
                            paddingLeft = 6,
                            paddingRight = 6,
                            paddingTop = 2,
                            paddingBottom = 2,
                            marginRight = 8,
                            children = {
                                UI.Label {
                                    text = CAT_DISPLAY_NAMES[article.category] or "新闻",
                                    fontSize = 10,
                                    color = catColor,
                                }
                            }
                        },
                        -- 涉及我的球队标记
                        isRelevant and UI.Panel {
                            backgroundColor = {255, 215, 0, 40},
                            borderRadius = 4,
                            paddingLeft = 4, paddingRight = 4,
                            paddingTop = 1, paddingBottom = 1,
                            marginRight = 6,
                            children = {
                                UI.Label { text = "我的球队", fontSize = 9, color = {255, 215, 0, 255} }
                            }
                        } or UI.Panel { width = 0, height = 0 },
                        -- 日期
                        UI.Label {
                            text = dateStr,
                            fontSize = 11,
                            color = Theme.COLORS.TEXT_MUTED,
                            flexGrow = 1,
                        },
                        -- 未读标记
                        isUnread and UI.Panel {
                            width = 8, height = 8,
                            borderRadius = 4,
                            backgroundColor = Theme.COLORS.ACCENT,
                        } or UI.Panel { width = 0, height = 0 },
                    }
                },
                -- 标题
                UI.Label {
                    text = article.title or "新闻",
                    fontSize = 15,
                    color = isUnread and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_SECONDARY,
                    fontWeight = isUnread and "bold" or "normal",
                    marginBottom = 4,
                },
                -- 正文（最多显示前 100 字符）
                UI.Label {
                    text = News._truncateBody(article.body or "", 100),
                    fontSize = 13,
                    color = Theme.COLORS.TEXT_MUTED,
                },
            },
            onClick = function()
                -- 标记已读
                article.read = true
                -- 导航到关联页面
                local target, targetParams = getNavigationTarget(article)
                if target then
                    Router.navigate(target, targetParams)
                else
                    -- 无具体目标则刷新当前列表（已标记已读）
                    Router.replaceWith("news", { tab = currentTab })
                end
            end,
        })
    end

    -- 空状态
    if #newsCards == 0 then
        table.insert(newsCards, UI.Panel {
            width = "100%", height = 120,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "暂无此类新闻", fontSize = 14, color = Theme.COLORS.TEXT_MUTED },
            }
        })
    end

    -- 总未读提示
    local totalUnread = unreadCounts.all or 0
    local headerHint = totalUnread > 0 and string.format("(%d条未读)", totalUnread) or ""

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = Theme.COLORS.BG_DARK,
        children = {
            -- 标题栏
            Theme.TopBar {
                children = {
                    UI.Button {
                        text = "返回", width = 50, height = 36,
                        backgroundColor = Theme.COLORS.TRANSPARENT,
                        fontSize = 14, color = Theme.COLORS.TEXT_SECONDARY,
                        onClick = function() Router.navigate("dashboard") end,
                    },
                    UI.Label {
                        text = "新闻中心 " .. headerHint,
                        fontSize = 17, color = Theme.COLORS.TEXT_PRIMARY,
                        fontWeight = "bold", flexGrow = 1, textAlign = "center",
                    },
                    -- 全部已读按钮放在标题栏右侧
                    UI.Button {
                        text = "全部已读",
                        width = 64, height = 30,
                        backgroundColor = totalUnread > 0 and {60, 70, 100, 255} or {38, 46, 71, 255},
                        borderRadius = 15, fontSize = 11,
                        color = totalUnread > 0 and Theme.COLORS.TEXT_PRIMARY or Theme.COLORS.TEXT_MUTED,
                        onClick = function()
                            for _, article in ipairs(gameState.news or {}) do
                                local artTab = CAT_TAB_MAP[article.category] or "league"
                                if currentTab == "all" or artTab == currentTab then
                                    article.read = true
                                end
                            end
                            Router.replaceWith("news", { tab = currentTab })
                        end,
                    },
                }
            },

            -- 二级导航
            Theme.MoreSubNav("news"),

            -- 分类标签栏（横向滚动）
            UI.ScrollView {
                width = "100%",
                height = 50,
                scrollX = true,
                scrollY = false,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 12,
                paddingRight = 12,
                backgroundColor = Theme.COLORS.BG_HEADER,
                borderBottomWidth = 1,
                borderColor = Theme.COLORS.BORDER,
                children = tabButtons,
            },

            -- 新闻列表
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                padding = 12,
                children = newsCards,
            },

            -- 底部导航
            Theme.MainNav("more"),
        }
    }
end

------------------------------------------------------
-- 辅助函数
------------------------------------------------------

--- 截断正文（保留完整中文字符）
function News._truncateBody(text, maxLen)
    if not text or text == "" then return "" end
    -- 移除换行，合并成一行预览
    local oneLine = text:gsub("\n", " "):gsub("%s+", " ")
    if #oneLine <= maxLen then return oneLine end
    -- UTF-8 安全截断（简单方式）
    local result = oneLine:sub(1, maxLen)
    -- 避免截断在 UTF-8 多字节中间
    while #result > 0 and result:byte(#result) >= 128 and result:byte(#result) < 192 do
        result = result:sub(1, -2)
    end
    return result .. "..."
end

return News
