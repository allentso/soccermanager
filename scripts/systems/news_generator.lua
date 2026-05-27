-- systems/news_generator.lua
-- 增强新闻生成系统 - 联赛综述/经理变动/伤病/赛季前瞻/转会完成

local Constants = require("scripts/app/constants")

local NewsGenerator = {}

------------------------------------------------------
-- 联赛综述（每周一生成）
------------------------------------------------------

function NewsGenerator.generateWeeklyReview(gameState)
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        local sorted = lg:getSortedStandings()
        if #sorted < 3 then goto continue end

        -- 分析本周变化（通过 recentForm 判断）
        local hotTeams = {}   -- 连胜队伍
        local coldTeams = {}  -- 连败队伍

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

        -- 构建综述
        local leader = gameState.teams[sorted[1].teamId]
        local leaderName = leader and leader.name or "?"
        local leaderPts = sorted[1].points

        local lines = {}
        table.insert(lines, string.format("%s 以 %d 分领跑积分榜。", leaderName, leaderPts))

        -- 积分差距
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

        -- 连胜/连败提及
        if #hotTeams > 0 then
            table.insert(lines, string.format("近期状态火热: %s（三连胜）。", table.concat(hotTeams, "、")))
        end
        if #coldTeams > 0 then
            table.insert(lines, string.format("陷入低迷: %s（三连败）。", table.concat(coldTeams, "、")))
        end

        -- 保级区情况
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

function NewsGenerator.generateInjuryNews(gameState, player, injuryDays)
    if injuryDays < 7 then return end  -- 轻伤不上新闻

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

    -- 如果是核心球员（能力值高于球队平均）
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
        end
    end

    gameState:addNews({
        category = "injury_news",
        title = string.format("伤病: %s (%s)", player.displayName, teamName),
        body = body,
        relatedTeams = {player.teamId},
    })
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
        relatedTeams = {data.teamId},
    })
end

------------------------------------------------------
-- 赛季前瞻（新赛季开始时生成）
------------------------------------------------------

function NewsGenerator.generateSeasonPreview(gameState)
    for leagueKey, lg in pairs(gameState.leagues or {}) do
        local teamIds = lg.teamIds or {}
        if #teamIds < 4 then goto continue end

        -- 收集各队实力（基于球员平均能力和声望）
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
                table.insert(teamRatings, {teamId = teamId, name = team.name, rating = rating})
            end
        end

        -- 按评分排序
        table.sort(teamRatings, function(a, b) return a.rating > b.rating end)

        local lines = {}
        table.insert(lines, string.format("新赛季 %s 即将拉开帷幕！以下是各方预测：", lg.name))
        table.insert(lines, "")

        -- 夺冠热门
        table.insert(lines, "夺冠热门:")
        for i = 1, math.min(3, #teamRatings) do
            table.insert(lines, string.format("  %d. %s", i, teamRatings[i].name))
        end

        -- 黑马预测（中间队伍随机选一个）
        if #teamRatings >= 8 then
            local darkHorseIdx = RandomInt(4, math.min(8, #teamRatings))
            table.insert(lines, string.format("\n黑马预测: %s", teamRatings[darkHorseIdx].name))
        end

        -- 保级热门
        table.insert(lines, "\n保级形势严峻:")
        for i = math.max(1, #teamRatings - 2), #teamRatings do
            table.insert(lines, string.format("  %s", teamRatings[i].name))
        end

        -- 玩家球队预测
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
-- 转会完成新闻（大额转会上新闻）
------------------------------------------------------

function NewsGenerator.generateTransferCompleteNews(gameState, transferData)
    local player = gameState.players[transferData.playerId]
    local fromTeam = gameState.teams[transferData.fromTeamId]
    local toTeam = gameState.teams[transferData.toTeamId]
    local amount = transferData.amount or 0

    -- 只为大额转会生成新闻（超过 500K）
    if amount < 500000 and transferData.type ~= "loan" then return end

    local playerName = transferData.playerName or (player and player.displayName or "?")
    local fromName = fromTeam and fromTeam.name or "自由球员"
    local toName = toTeam and toTeam.name or "?"

    local body
    if transferData.type == "loan" then
        body = string.format("%s 从 %s 租借加盟 %s。", playerName, fromName, toName)
    elseif amount == 0 then
        body = string.format("%s 以自由身从 %s 转会至 %s。", playerName, fromName, toName)
    else
        local amountStr
        if amount >= 1000000 then
            amountStr = string.format("%.1fM", amount / 1000000)
        else
            amountStr = string.format("%.0fK", amount / 1000)
        end

        local templates = {
            string.format("官宣！%s 以 %s 的身价从 %s 正式转会至 %s。", playerName, amountStr, fromName, toName),
            string.format("%s 完成重磅签约，以 %s 引进 %s 球星 %s。", toName, amountStr, fromName, playerName),
            string.format("转会确认：%s 离开 %s，%s 身价加盟 %s。", playerName, fromName, amountStr, toName),
        }
        body = templates[RandomInt(1, #templates)]

        -- 如果是高价转会
        if amount >= 5000000 then
            body = body .. "\n这笔转会是本赛季迄今为止的最大手笔之一。"
        end
    end

    gameState:addNews({
        category = "transfer_news",
        title = string.format("转会: %s → %s", playerName, toName),
        body = body,
        relatedTeams = {transferData.fromTeamId, transferData.toTeamId},
    })
end

------------------------------------------------------
-- 里程碑新闻（球员达成特殊成就）
------------------------------------------------------

function NewsGenerator.checkMilestones(gameState, player, matchReport)
    if not player or not player.seasonStats then return end

    local stats = player.seasonStats
    local team = gameState.teams[player.teamId]
    local teamName = team and team.name or "?"

    -- 进球里程碑: 10, 20, 30
    local goals = stats.goals or 0
    if goals == 10 or goals == 20 or goals == 30 then
        gameState:addNews({
            category = "milestone",
            title = string.format("%s 赛季第 %d 球!", player.displayName, goals),
            body = string.format("%s (%s) 本赛季已攻入 %d 球，表现极为出色。",
                player.displayName, teamName, goals),
            relatedTeams = {player.teamId},
        })
    end

    -- 出场里程碑: 50, 100, 200
    local apps = stats.appearances or 0
    if apps == 50 or apps == 100 or apps == 200 then
        gameState:addNews({
            category = "milestone",
            title = string.format("%s 达成 %d 场出场里程碑", player.displayName, apps),
            body = string.format("%s 为 %s 出场达到 %d 次，祝贺这位忠诚的球员！",
                player.displayName, teamName, apps),
            relatedTeams = {player.teamId},
        })
    end
end

------------------------------------------------------
-- 大比分/爆冷新闻
------------------------------------------------------

function NewsGenerator.generateUpsetNews(gameState, fixture)
    if not fixture or fixture.status ~= "finished" then return end

    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    if not homeTeam or not awayTeam then return end

    local homeGoals = fixture.homeGoals or 0
    local awayGoals = fixture.awayGoals or 0
    local goalDiff = math.abs(homeGoals - awayGoals)

    -- 大比分（净胜4球以上）
    if goalDiff >= 4 then
        local winner = homeGoals > awayGoals and homeTeam or awayTeam
        local loser = homeGoals > awayGoals and awayTeam or homeTeam

        gameState:addNews({
            category = "match_report",
            title = string.format("大胜! %s %d-%d %s", homeTeam.name, homeGoals, awayGoals, awayTeam.name),
            body = string.format("%s 以 %d-%d 横扫 %s，展现出强大的统治力。",
                winner.name, math.max(homeGoals, awayGoals), math.min(homeGoals, awayGoals), loser.name),
            relatedTeams = {fixture.homeTeamId, fixture.awayTeamId},
        })
        return true
    end

    -- 爆冷（低排名队伍击败高排名队伍，排名差5位以上）
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
        return false  -- 平局不算爆冷
    end

    if winnerPos - loserPos >= 5 then
        gameState:addNews({
            category = "match_report",
            title = string.format("爆冷! %s 击败 %s", winner.name, loser.name),
            body = string.format("排名第%d的 %s 在比赛中击败了第%d位的 %s（%d-%d），爆出一大冷门！",
                winnerPos, winner.name, loserPos, loser.name, homeGoals, awayGoals),
            relatedTeams = {fixture.homeTeamId, fixture.awayTeamId},
        })
        return true
    end

    return false
end

return NewsGenerator
