-- systems/news_generator.lua
-- 增强新闻生成系统 - 联赛综述/经理变动/伤病/赛季前瞻/转会完成

local Constants = require("scripts/app/constants")
local FinanceManager = require("scripts/systems/finance_manager")
local MessageManager = require("scripts/systems/message_manager")

local NewsGenerator = {}

------------------------------------------------------
-- 去重（持久化到 gameState._messageDedupeCache）
------------------------------------------------------

local function isDeduped(gameState, key)
    return MessageManager._isDuplicate(gameState, key, true)
end

local function markDeduped(gameState, key)
    MessageManager._markSent(gameState, key, true)
end

local function formatAmount(amount)
    return FinanceManager.formatMoney(amount or 0)
end

------------------------------------------------------
-- 转会分级
------------------------------------------------------

---@return string tier "S"|"A"|"B"|"C"
function NewsGenerator.classifyTransferTier(amount, overall, transferType)
    overall = overall or 0
    amount = amount or 0
    transferType = transferType or "permanent"

    if transferType == "loan" then
        if overall >= 76 then return "A" end
        if overall >= 70 then return "B" end
        return "C"
    end

    if transferType == "free" or transferType == "precontract" or transferType == "precontract_active" then
        if overall >= 82 then return "S" end
        if overall >= 76 then return "A" end
        if overall >= 70 then return "B" end
        return "C"
    end

    if amount >= 8000000 or overall >= 82 then return "S" end
    if amount >= 2000000 or overall >= 76 then return "A" end
    if amount >= 500000 or overall >= 70 then return "B" end
    return "C"
end

function NewsGenerator.teamsShareLeague(gameState, teamIdA, teamIdB)
    if not teamIdA or not teamIdB then return false end
    local function leagueHasBoth(lg)
        if not lg or not lg.teamIds then return false end
        local hasA, hasB = false, false
        for _, tid in ipairs(lg.teamIds) do
            if tid == teamIdA then hasA = true end
            if tid == teamIdB then hasB = true end
        end
        return hasA and hasB
    end
    for _, lg in pairs(gameState.leagues or {}) do
        if leagueHasBoth(lg) then return true end
    end
    return leagueHasBoth(gameState.league)
end

local TIER_CONTEXT = {
    S = {
        "这笔转会有望改变联赛争冠格局。",
        "转会市场为之震动，球迷热议不断。",
        "这是本赛季迄今为止最受瞩目的引援之一。",
    },
    A = {
        "新援将显著增强球队竞争力。",
        "各方普遍认为这是一笔高质量签约。",
    },
}

local function pickContext(tier)
    local pool = TIER_CONTEXT[tier]
    if not pool or #pool == 0 then return nil end
    return pool[RandomInt(1, #pool)]
end

local function buildTransferTitle(tier, playerName, toName, transferType)
    if transferType == "precontract" then
        return string.format("预签约: %s → %s", playerName, toName)
    end
    if transferType == "precontract_active" then
        return string.format("预签约生效: %s 加盟 %s", playerName, toName)
    end
    if transferType == "free" then
        if tier == "S" then return string.format("🔥 重磅免签: %s 加盟 %s", playerName, toName) end
        if tier == "A" then return string.format("官宣免签: %s → %s", playerName, toName) end
        return string.format("自由签约: %s → %s", playerName, toName)
    end
    if transferType == "loan" then
        if tier == "A" then return string.format("重磅租借: %s 加盟 %s", playerName, toName) end
        return string.format("租借: %s → %s", playerName, toName)
    end
    if tier == "S" then return string.format("🔥 重磅官宣: %s 加盟 %s", playerName, toName) end
    if tier == "A" then return string.format("官宣: %s 转会 %s", playerName, toName) end
    return string.format("转会: %s → %s", playerName, toName)
end

local function buildTransferBody(tier, playerName, fromName, toName, amount, overall, positionName, transferType)
    local posPart = positionName and string.format("（%s，能力 %d）", positionName, overall) or ""
    local body

    if transferType == "loan" then
        body = string.format("%s 从 %s 租借加盟 %s%s。", playerName, fromName, toName, posPart)
    elseif transferType == "free" or transferType == "precontract_active" then
        body = string.format("%s 以自由身从 %s 正式加盟 %s%s。",
            playerName, fromName, toName, posPart)
    elseif transferType == "precontract" then
        body = string.format("%s 与 %s 达成预签约协议，将在合同到期后正式加盟%s。",
            playerName, toName, posPart ~= "" and (" " .. posPart) or "")
    elseif amount == 0 then
        body = string.format("%s 从 %s 转会至 %s%s。", playerName, fromName, toName, posPart)
    else
        local templates = {
            string.format("官宣！%s 以 %s 的身价从 %s 正式转会至 %s%s。",
                playerName, formatAmount(amount), fromName, toName, posPart),
            string.format("%s 完成重要签约，以 %s 从 %s 引进 %s%s。",
                toName, formatAmount(amount), fromName, playerName, posPart),
            string.format("转会确认：%s 离开 %s，以 %s 加盟 %s%s。",
                playerName, fromName, formatAmount(amount), toName, posPart),
        }
        body = templates[RandomInt(1, #templates)]
    end

    local ctx = pickContext(tier)
    if ctx then body = body .. "\n" .. ctx end
    if tier == "S" and amount >= 5000000 and transferType == "permanent" then
        body = body .. "\n这是本赛季转会窗口的大手笔之一。"
    end
    return body
end

--- 同联赛对手重磅引援 → 玩家 inbox
local function notifyLeagueTransferInbox(gameState, opts, tier, playerName, fromName, toName, amount, overall)
    if tier ~= "S" and tier ~= "A" then return end
    if not gameState.playerTeamId then return end

    local toTeamId = opts.toTeamId
    local fromTeamId = opts.fromTeamId
    if toTeamId == gameState.playerTeamId or fromTeamId == gameState.playerTeamId then return end
    if not NewsGenerator.teamsShareLeague(gameState, gameState.playerTeamId, toTeamId) then return end

    local dedupeKey = "league_transfer_inbox_" .. opts.playerId .. "_" .. (gameState.season or 0)
    if isDeduped(gameState, dedupeKey) then return end
    markDeduped(gameState, dedupeKey)

    local title, body
    if tier == "S" then
        title = string.format("联赛重磅：%s 加盟 %s", playerName, toName)
        body = string.format("同联赛球队 %s 以 %s 签下 %s（能力 %d）。争冠形势可能生变，请留意。",
            toName, amount > 0 and formatAmount(amount) or "自由身", playerName, overall or 0)
    else
        title = string.format("联赛动态：%s 加盟 %s", playerName, toName)
        body = string.format("%s 从 %s 转会至 %s（%s）。",
            playerName, fromName, toName, amount > 0 and formatAmount(amount) or "自由身")
    end

    gameState:sendMessage({
        category = "transfer",
        title = title,
        body = body,
        priority = tier == "S" and "high" or "normal",
    })
end

--- 统一发布转会/租借/免签新闻（C 档静默不发）
---@param gameState table
---@param opts table { playerId, fromTeamId?, toTeamId, amount?, type? }
---@return table|nil article
function NewsGenerator.publishTransferNews(gameState, opts)
    if not gameState or not opts or not opts.playerId or not opts.toTeamId then return nil end

    local player = gameState.players[opts.playerId]
    local fromTeam = opts.fromTeamId and gameState.teams[opts.fromTeamId]
    local toTeam = gameState.teams[opts.toTeamId]
    local amount = opts.amount or 0
    local transferType = opts.type or "permanent"

    local playerName = opts.playerName or (player and player.displayName) or "?"
    local fromName = fromTeam and fromTeam.name or "自由球员市场"
    local toName = toTeam and toTeam.name or "?"
    local overall = player and player.overall or 0
    local positionName = player and (Constants.POSITION_NAMES[player.position] or player.position) or nil

    local tier = NewsGenerator.classifyTransferTier(amount, overall, transferType)
    if tier == "C" then return nil end

    local dedupeKey = "transfer_news_" .. opts.playerId .. "_" .. (gameState.season or 0)
        .. "_" .. transferType .. "_" .. tostring(opts.toTeamId)
    if isDeduped(gameState, dedupeKey) then return nil end
    markDeduped(gameState, dedupeKey)

    local title = buildTransferTitle(tier, playerName, toName, transferType)
    local body = buildTransferBody(tier, playerName, fromName, toName, amount, overall, positionName, transferType)

    local relatedTeams = {}
    if opts.fromTeamId then table.insert(relatedTeams, opts.fromTeamId) end
    if opts.toTeamId then table.insert(relatedTeams, opts.toTeamId) end

    local article = gameState:addNews({
        category = "transfer_news",
        title = title,
        body = body,
        tier = tier,
        playerId = opts.playerId,
        relatedTeams = relatedTeams,
    })

    notifyLeagueTransferInbox(gameState, opts, tier, playerName, fromName, toName, amount, overall)
    return article
end

-- 向后兼容旧函数名
function NewsGenerator.generateTransferCompleteNews(gameState, transferData)
    return NewsGenerator.publishTransferNews(gameState, {
        playerId = transferData.playerId,
        fromTeamId = transferData.fromTeamId,
        toTeamId = transferData.toTeamId,
        amount = transferData.amount,
        type = transferData.type or "permanent",
        playerName = transferData.playerName,
    })
end

------------------------------------------------------
-- 联赛综述（每周一生成）
------------------------------------------------------

function NewsGenerator.generateWeeklyReview(gameState)
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        local sorted = lg:getSortedStandings()
        if #sorted < 3 then goto continue end

        local hotTeams = {}
        local coldTeams = {}

        for _, entry in ipairs(sorted) do
            local team = gameState.teams[entry.teamId]
            if team and team.recentForm and #team.recentForm >= 3 then
                local recent3 = {}
                for i = math.max(1, #team.recentForm - 2), #team.recentForm do
                    table.insert(recent3, team.recentForm[i])
                end
                local wins = 0
                local losses = 0
                for _, r in ipairs(recent3) do
                    if r == "W" then wins = wins + 1 end
                    if r == "L" then losses = losses + 1 end
                end
                if wins == 3 then
                    table.insert(hotTeams, team.name)
                end
                if losses == 3 then
                    table.insert(coldTeams, team.name)
                end
            end
        end

        local leader = gameState.teams[sorted[1].teamId]
        local leaderName = leader and leader.name or "?"
        local leaderPts = sorted[1].points

        local lines = {}
        table.insert(lines, string.format("%s 以 %d 分领跑积分榜。", leaderName, leaderPts))

        if #sorted >= 2 then
            local gap = sorted[1].points - sorted[2].points
            local second = gameState.teams[sorted[2].teamId]
            if gap == 0 then
                table.insert(lines, string.format("%s 同分紧随其后，争冠白热化！", second and second.name or "?"))
            elseif gap <= 3 then
                table.insert(lines, string.format("第二名 %s 仅落后 %d 分。", second and second.name or "?", gap))
            elseif gap >= 10 then
                table.insert(lines, string.format("领先优势已扩大至 %d 分，冠军在望。", gap))
            end
        end

        if #hotTeams > 0 then
            table.insert(lines, string.format("近期状态火热: %s（三连胜）。", table.concat(hotTeams, "、")))
        end
        if #coldTeams > 0 then
            table.insert(lines, string.format("陷入低迷: %s（三连败）。", table.concat(coldTeams, "、")))
        end

        local totalTeams = #sorted
        if totalTeams >= 6 then
            local relegationLine = math.max(1, totalTeams - 2)
            local dangered = {}
            for i = relegationLine, totalTeams do
                local team = gameState.teams[sorted[i].teamId]
                if team then
                    table.insert(dangered, team.name)
                end
            end
            if #dangered > 0 then
                table.insert(lines, string.format("保级区: %s 形势不妙。", table.concat(dangered, "、")))
            end
        end

        gameState:addNews({
            category = "league_news",
            title = string.format("%s 周报", lg.name),
            body = table.concat(lines, "\n"),
        })

        ::continue::
    end
end

------------------------------------------------------
-- 伤病新闻（重伤球员上新闻，7天以上）
------------------------------------------------------

function NewsGenerator.tryInjuryNews(gameState, player, injuryDays)
    if not gameState or not player or injuryDays < 7 then return end

    local dedupeKey = string.format("injury_news_%d_%d_%d_%d",
        player.id, gameState.date.year, gameState.date.month, gameState.date.day)
    if isDeduped(gameState, dedupeKey) then return end

    local team = gameState.teams[player.teamId]
    local teamName = team and team.name or "?"

    local severity
    if injuryDays >= 30 then
        severity = "重伤"
    elseif injuryDays >= 14 then
        severity = "较重伤病"
    else
        severity = "伤病"
    end

    local templates = {
        string.format("%s 核心球员 %s 因%s将缺阵 %d 天，这对球队是不小的打击。",
            teamName, player.displayName, severity, injuryDays),
        string.format("坏消息！%s 的 %s 遭遇%s，预计需要 %d 天恢复。",
            teamName, player.displayName, severity, injuryDays),
        string.format("%s 确认 %s 将因伤缺席至少 %d 天的比赛。",
            teamName, player.displayName, injuryDays),
    }

    local body = templates[RandomInt(1, #templates)]

    if team then
        local avgOverall = 0
        local count = 0
        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p then avgOverall = avgOverall + p.overall; count = count + 1 end
        end
        if count > 0 then avgOverall = avgOverall / count end
        if player.overall > avgOverall + 5 then
            body = body .. "\n这位关键球员的缺阵可能严重影响球队的竞争力。"
        else
            return
        end
    end

    markDeduped(gameState, dedupeKey)

    gameState:addNews({
        category = "injury_news",
        title = string.format("伤病: %s (%s)", player.displayName, teamName),
        body = body,
        relatedTeams = player.teamId and { player.teamId } or nil,
    })
end

function NewsGenerator.generateInjuryNews(gameState, player, injuryDays)
    NewsGenerator.tryInjuryNews(gameState, player, injuryDays)
end

------------------------------------------------------
-- 经理变动新闻
------------------------------------------------------

function NewsGenerator.generateManagerChangeNews(gameState, data)
    local team = gameState.teams[data.teamId]
    local teamName = team and team.name or data.teamName or "?"

    local body
    if data.type == "sacked" then
        local templates = {
            string.format("%s 宣布解雇主教练 %s，原因是近期成绩不佳。", teamName, data.managerName),
            string.format("由于战绩持续低迷，%s 决定与主帅 %s 分道扬镳。", teamName, data.managerName),
            string.format("%s 主帅 %s 被董事会解职。球队将寻找新的继任者。", teamName, data.managerName),
        }
        body = templates[RandomInt(1, #templates)]
        if data.reason then
            body = body .. "\n原因: " .. data.reason
        end
    elseif data.type == "resigned" then
        body = string.format("%s 主教练 %s 宣布辞职。%s",
            teamName, data.managerName, data.reason or "具体原因尚未公布。")
    elseif data.type == "appointed" then
        local templates = {
            string.format("%s 正式宣布 %s 出任新一任主教练。", teamName, data.managerName),
            string.format("官宣！%s 成为 %s 新帅，将带领球队走出困境。", data.managerName, teamName),
        }
        body = templates[RandomInt(1, #templates)]
    else
        body = string.format("%s: %s - %s", teamName, data.type or "变动", data.managerName)
    end

    gameState:addNews({
        category = "manager_news",
        title = string.format("教练变动: %s", teamName),
        body = body,
        relatedTeams = { data.teamId },
    })
end

------------------------------------------------------
-- 赛季前瞻（新赛季开始时生成）
------------------------------------------------------

function NewsGenerator.generateSeasonPreview(gameState)
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        local teamIds = lg.teamIds or {}
        if #teamIds < 4 then goto continue end

        local teamRatings = {}
        for _, teamId in ipairs(teamIds) do
            local team = gameState.teams[teamId]
            if team then
                local avgOverall = 0
                local count = 0
                for _, pid in ipairs(team.playerIds) do
                    local p = gameState.players[pid]
                    if p and not p.retired then
                        avgOverall = avgOverall + p.overall
                        count = count + 1
                    end
                end
                if count > 0 then avgOverall = avgOverall / count end
                local rating = avgOverall * 0.7 + (team.reputation or 50) * 0.3
                table.insert(teamRatings, { teamId = teamId, name = team.name, rating = rating })
            end
        end

        table.sort(teamRatings, function(a, b) return a.rating > b.rating end)

        local lines = {}
        table.insert(lines, string.format("新赛季 %s 即将拉开帷幕！以下是各方预测：", lg.name))
        table.insert(lines, "")

        table.insert(lines, "夺冠热门:")
        for i = 1, math.min(3, #teamRatings) do
            table.insert(lines, string.format("  %d. %s", i, teamRatings[i].name))
        end

        if #teamRatings >= 8 then
            local darkHorseIdx = RandomInt(4, math.min(8, #teamRatings))
            table.insert(lines, string.format("\n黑马预测: %s", teamRatings[darkHorseIdx].name))
        end

        table.insert(lines, "\n保级形势严峻:")
        for i = math.max(1, #teamRatings - 2), #teamRatings do
            table.insert(lines, string.format("  %s", teamRatings[i].name))
        end

        local playerTeamId = gameState.playerTeamId
        if playerTeamId then
            for i, tr in ipairs(teamRatings) do
                if tr.teamId == playerTeamId then
                    table.insert(lines, string.format("\n你的球队 %s 被预测排名第 %d 位。", tr.name, i))
                    break
                end
            end
        end

        gameState:addNews({
            category = "season_news",
            title = string.format("%d-%d 赛季前瞻: %s", gameState.season, gameState.season + 1, lg.name),
            body = table.concat(lines, "\n"),
        })

        ::continue::
    end
end

------------------------------------------------------
-- 里程碑新闻（球员达成特殊成就）
------------------------------------------------------

local function tryMilestone(gameState, player, milestoneKey, title, body)
    if isDeduped(gameState, milestoneKey) then return false end
    markDeduped(gameState, milestoneKey)
    local team = gameState.teams[player.teamId]
    gameState:addNews({
        category = "milestone",
        title = title,
        body = body,
        relatedTeams = player.teamId and { player.teamId } or nil,
    })
    return true
end

function NewsGenerator.checkMilestones(gameState, player, _matchReport)
    if not player or not player.seasonStats then return end

    local stats = player.seasonStats
    local team = gameState.teams[player.teamId]
    local teamName = team and team.name or "?"
    local season = gameState.season or 0

    local goals = stats.goals or 0
    for _, milestone in ipairs({ 10, 20, 30 }) do
        if goals == milestone then
            local key = string.format("milestone_%d_%d_goals_%d", player.id, season, milestone)
            tryMilestone(gameState, player, key,
                string.format("%s 赛季第 %d 球!", player.displayName, goals),
                string.format("%s (%s) 本赛季已攻入 %d 球，表现极为出色。",
                    player.displayName, teamName, goals))
        end
    end

    local apps = stats.appearances or 0
    for _, milestone in ipairs({ 50, 100, 200 }) do
        if apps == milestone then
            local key = string.format("milestone_%d_%d_apps_%d", player.id, season, milestone)
            tryMilestone(gameState, player, key,
                string.format("%s 达成 %d 场出场里程碑", player.displayName, apps),
                string.format("%s 为 %s 出场达到 %d 次，祝贺这位忠诚的球员！",
                    player.displayName, teamName, apps))
        end
    end
end

--- 比赛结束后批量检查里程碑
function NewsGenerator.checkMilestonesForPlayers(gameState, players)
    if not players then return end
    local seen = {}
    for _, p in ipairs(players) do
        if p and p.id and not seen[p.id] then
            seen[p.id] = true
            NewsGenerator.checkMilestones(gameState, p)
        end
    end
end

------------------------------------------------------
-- 大比分/爆冷新闻
------------------------------------------------------

function NewsGenerator.generateUpsetNews(gameState, fixture)
    if not fixture or fixture.status ~= "finished" then return end

    local dedupeKey = "match_news_" .. tostring(fixture.id or 0)
    if isDeduped(gameState, dedupeKey) then return false end

    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    if not homeTeam or not awayTeam then return end

    local homeGoals = fixture.homeGoals or 0
    local awayGoals = fixture.awayGoals or 0
    local goalDiff = math.abs(homeGoals - awayGoals)

    if goalDiff >= 4 then
        local winner = homeGoals > awayGoals and homeTeam or awayTeam
        local loser = homeGoals > awayGoals and awayTeam or homeTeam

        gameState:addNews({
            category = "match_report",
            title = string.format("大胜! %s %d-%d %s", homeTeam.name, homeGoals, awayGoals, awayTeam.name),
            body = string.format("%s 以 %d-%d 横扫 %s，展现出强大的统治力。",
                winner.name, math.max(homeGoals, awayGoals), math.min(homeGoals, awayGoals), loser.name),
            relatedTeams = { fixture.homeTeamId, fixture.awayTeamId },
            fixtureId = fixture.id,
        })
        markDeduped(gameState, dedupeKey)
        return true
    end

    local homePos, awayPos = 999, 999
    for _, lg in pairs(gameState.leagues or {}) do
        local hp = lg:getTeamPosition(fixture.homeTeamId)
        local ap = lg:getTeamPosition(fixture.awayTeamId)
        if hp and hp < 999 then homePos = hp end
        if ap and ap < 999 then awayPos = ap end
    end

    local winner, winnerPos, loser, loserPos
    if homeGoals > awayGoals then
        winner, winnerPos = homeTeam, homePos
        loser, loserPos = awayTeam, awayPos
    elseif awayGoals > homeGoals then
        winner, winnerPos = awayTeam, awayPos
        loser, loserPos = homeTeam, homePos
    else
        return false
    end

    if winnerPos - loserPos >= 5 then
        gameState:addNews({
            category = "match_report",
            title = string.format("爆冷! %s 击败 %s", winner.name, loser.name),
            body = string.format("排名第%d的 %s 在比赛中击败了第%d位的 %s（%d-%d），爆出一大冷门！",
                winnerPos, winner.name, loserPos, loser.name, homeGoals, awayGoals),
            relatedTeams = { fixture.homeTeamId, fixture.awayTeamId },
            fixtureId = fixture.id,
        })
        markDeduped(gameState, dedupeKey)
        return true
    end

    return false
end

return NewsGenerator
