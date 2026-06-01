-- core/turn_processor.lua
-- 回合推进处理器

local MatchEngine = require("scripts/match/match_engine")
local EventBus = require("scripts/app/event_bus")
local League = require("scripts/domain/league")
local TransferManager = require("scripts/systems/transfer_manager")
local ChampionsLeague = require("scripts/systems/champions_league")
local WorldCup = require("scripts/systems/world_cup")
local FinanceManager = require("scripts/systems/finance_manager")
local ContractManager = require("scripts/systems/contract_manager")
local TrainingManager = require("scripts/systems/training_manager")
local MessageManager = require("scripts/systems/message_manager")
local SettingsManager = require("scripts/persistence/settings_manager")
local BoardManager = require("scripts/systems/board_manager")
local MoraleManager = require("scripts/systems/morale_manager")
local StaffManager = require("scripts/systems/staff_manager")
local ScoutManager = require("scripts/systems/scout_manager")
local YouthManager = require("scripts/systems/youth_manager")
local JobManager = require("scripts/systems/job_manager")
local RandomEventManager = require("scripts/systems/random_event_manager")
local ReputationManager = require("scripts/systems/reputation_manager")
local NewsGenerator = require("scripts/systems/news_generator")
local AIManager = require("scripts/systems/ai_manager")
local ObjectivesManager = require("scripts/systems/objectives_manager")

local TurnProcessor = {}

-- 推进一天
function TurnProcessor.advanceDay(gameState)
    -- 存档迁移：旧格式欧冠 → 新瑞士制（仅首次触发）
    ChampionsLeague.migrateIfNeeded(gameState)

    -- 推进日期
    local newDate = League._addDays(gameState.date, 1)
    gameState.date = newDate
    gameState.dayOfWeek = (gameState.dayOfWeek % 7) + 1

    -- 检查所有联赛当天是否有比赛
    local todayFixtures = TurnProcessor.getFixturesForDate(gameState, newDate)

    -- 检查欧冠当天是否有比赛
    local uclFixtures = TurnProcessor.getUCLFixturesForDate(gameState, newDate)
    for _, f in ipairs(uclFixtures) do
        table.insert(todayFixtures, f)
    end

    -- 检查世界杯当天是否有比赛
    local wcFixtures = TurnProcessor.getWCFixturesForDate(gameState, newDate)
    for _, f in ipairs(wcFixtures) do
        table.insert(todayFixtures, f)
    end

    if #todayFixtures > 0 then
        -- 比赛日
        gameState.turnState = "match_day"
        TurnProcessor.processMatchDay(gameState, todayFixtures)
    else
        -- 非比赛日
        gameState.turnState = "idle"
        TurnProcessor.processNonMatchDay(gameState)
    end

    -- 检查欧冠阶段推进
    ChampionsLeague.checkPhaseAdvance(gameState)

    -- 检查世界杯阶段推进
    WorldCup.checkPhaseAdvance(gameState)

    -- 检查玩家所在联赛是否赛季结束
    if gameState.league and gameState.league:isSeasonComplete() then
        EventBus.emit("season_end")
    end

    EventBus.emit("day_advanced", newDate)
    return todayFixtures
end

-- 获取当天所有联赛的比赛（合并所有联赛的fixture）
function TurnProcessor.getFixturesForDate(gameState, date)
    local result = {}
    for _, lg in pairs(gameState.leagues or {}) do
        for _, f in ipairs(lg.fixtures) do
            if f.status == "scheduled" and
               f.date.year == date.year and
               f.date.month == date.month and
               f.date.day == date.day then
                table.insert(result, f)
            end
        end
    end
    return result
end

-- 获取当天欧冠比赛
function TurnProcessor.getUCLFixturesForDate(gameState, date)
    local ucl = gameState.championsLeague
    if not ucl then return {} end
    local fixtures = ucl:getFixturesForDate(date)
    -- 标记为欧冠比赛
    for _, f in ipairs(fixtures) do
        f._isUCL = true
    end
    return fixtures
end

-- 获取当天世界杯比赛
function TurnProcessor.getWCFixturesForDate(gameState, date)
    local wc = gameState.worldCup
    if not wc or wc.phase == "not_started" or wc.phase == "completed" then return {} end
    local fixtures = wc:getFixturesForDate(date)
    -- 标记为世界杯比赛
    for _, f in ipairs(fixtures) do
        f._isWC = true
    end
    return fixtures
end

-- 处理比赛日
function TurnProcessor.processMatchDay(gameState, fixtures)
    local playerTeamId = gameState.playerTeamId
    local playerMatchReport = nil

    for _, fixture in ipairs(fixtures) do
        -- 玩家比赛跳过自动模拟，交由 pre_match 屏幕手动触发
        local isPlayerMatch = (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)
        -- 世界杯：检查是否是玩家国家队的比赛
        local isPlayerWCMatch = fixture._isWC and WorldCup.isPlayerNationMatch(gameState, fixture)
        if isPlayerWCMatch then isPlayerMatch = true end

        if isPlayerMatch and not gameState._cheatAutoPlay then
            fixture._pendingPlayerMatch = true
            goto continue_fixture
        end

        local report
        if fixture._isWC then
            -- 世界杯使用专用模拟引擎（国家代码而非球队ID）
            report = TurnProcessor._simulateWCMatch(gameState, fixture)
        else
            report = MatchEngine.simulate(gameState, fixture)
        end

        if report then
            if fixture._isWC then
                TurnProcessor._applyWCResult(gameState, fixture, report)
            elseif fixture._isUCL then
                TurnProcessor._applyUCLResult(gameState, fixture, report)
            else
                MatchEngine.applyResult(gameState, fixture, report)
            end

            -- 生成比赛消息
            if fixture._isWC or isPlayerMatch then
                local homeName, awayName
                if fixture._isWC then
                    homeName = WorldCup._getNationName(fixture.homeTeamId)
                    awayName = WorldCup._getNationName(fixture.awayTeamId)
                else
                    local homeTeam = gameState.teams[fixture.homeTeamId]
                    local awayTeam = gameState.teams[fixture.awayTeamId]
                    homeName = homeTeam and homeTeam.name or "主队"
                    awayName = awayTeam and awayTeam.name or "客队"
                end
                local prefix = fixture._isUCL and "[欧冠] " or (fixture._isWC and "[世界杯] " or "")

                if isPlayerMatch or fixture._isWC then
                    if isPlayerMatch then playerMatchReport = report end
                    gameState:sendMessage({
                        category = "match_result",
                        title = prefix .. "比赛结果",
                        body = string.format("%s%s %d - %d %s",
                            prefix, homeName, report.homeGoals, report.awayGoals, awayName),
                        priority = fixture._isWC and "normal" or "high",
                    })
                end
            end
        end
        ::continue_fixture::
    end

    -- 比赛日票房收入（主场球队）- 跳过待处理的玩家比赛（由 pre_match 负责）
    for _, fixture in ipairs(fixtures) do
        if not fixture._isWC and not fixture._pendingPlayerMatch then
            FinanceManager.processMatchDayRevenue(gameState, fixture.homeTeamId, true, fixture.awayTeamId)
        end
    end

    -- B2: 赛后士气和声望更新
    for _, fixture in ipairs(fixtures) do
        if not fixture._isWC and fixture.status == "finished" then
            local homeResult, awayResult
            local homeGoals = fixture.homeGoals or 0
            local awayGoals = fixture.awayGoals or 0
            if homeGoals > awayGoals then
                homeResult, awayResult = "W", "L"
            elseif homeGoals < awayGoals then
                homeResult, awayResult = "L", "W"
            else
                homeResult, awayResult = "D", "D"
            end
            local goalDiff = homeGoals - awayGoals

            -- 士气更新
            MoraleManager.postMatchUpdate(gameState, fixture.homeTeamId, homeResult, nil)
            MoraleManager.postMatchUpdate(gameState, fixture.awayTeamId, awayResult, nil)

            -- 声望更新
            ReputationManager.postMatchUpdate(gameState, fixture.homeTeamId, fixture.awayTeamId, homeResult, goalDiff)
            ReputationManager.postMatchUpdate(gameState, fixture.awayTeamId, fixture.homeTeamId, awayResult, -goalDiff)
        end
    end

    -- 生成新闻
    if #fixtures > 0 then
        TurnProcessor.generateMatchNews(gameState, fixtures)
        -- B3: 大比分/爆冷新闻
        for _, fixture in ipairs(fixtures) do
            if not fixture._isWC then
                NewsGenerator.generateUpsetNews(gameState, fixture)
            end
        end
    end

    return playerMatchReport
end

-- 模拟世界杯比赛（国家代码而非球队ID，使用简化引擎）
function TurnProcessor._simulateWCMatch(gameState, fixture)
    -- 世界杯使用国家代码作为 teamId，不在 gameState.teams 中
    -- 根据国籍球员的平均能力模拟
    local homeCode = fixture.homeTeamId
    local awayCode = fixture.awayTeamId

    -- 收集该国籍的所有球员，计算攻防实力
    local homeOverall, awayOverall = 50, 50
    local homeCount, awayCount = 0, 0

    for _, player in pairs(gameState.players) do
        if player.retired then goto continue end
        if player.nationality == homeCode then
            homeOverall = homeOverall + (player.overall or 50)
            homeCount = homeCount + 1
        elseif player.nationality == awayCode then
            awayOverall = awayOverall + (player.overall or 50)
            awayCount = awayCount + 1
        end
        ::continue::
    end

    if homeCount > 0 then homeOverall = homeOverall / (homeCount + 1) end
    if awayCount > 0 then awayOverall = awayOverall / (awayCount + 1) end

    -- 基于实力差计算期望进球
    local homeLambda = 1.2 + (homeOverall - awayOverall) * 0.03 + Random() * 0.3
    local awayLambda = 1.0 + (awayOverall - homeOverall) * 0.03 + Random() * 0.3
    homeLambda = math.max(0.3, homeLambda)
    awayLambda = math.max(0.3, awayLambda)

    -- 泊松采样
    local homeGoals = TurnProcessor._poissonRandom(homeLambda)
    local awayGoals = TurnProcessor._poissonRandom(awayLambda)
    homeGoals = math.min(homeGoals, 5)
    awayGoals = math.min(awayGoals, 5)

    return {
        homeGoals = homeGoals,
        awayGoals = awayGoals,
        homeTeamId = homeCode,
        awayTeamId = awayCode,
        events = {},
        playerRatings = {},
        stats = {},
    }
end

-- 泊松随机数
function TurnProcessor._poissonRandom(lambda)
    if lambda <= 0 then return 0 end
    local L = math.exp(-lambda)
    local k = 0
    local p = 1
    repeat
        k = k + 1
        p = p * Random()
    until p <= L
    return k - 1
end

-- 应用世界杯比赛结果
function TurnProcessor._applyWCResult(gameState, fixture, report)
    local wc = gameState.worldCup
    if not wc then return end

    -- 更新比分和状态
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"

    -- 如果是小组赛，更新小组积分
    if wc.phase == "group" and fixture.groupName then
        wc:updateGroupStanding(fixture.groupName, fixture)
    end
end

-- 应用欧冠比赛结果
function TurnProcessor._applyUCLResult(gameState, fixture, report)
    local ucl = gameState.championsLeague
    if not ucl then return end

    -- 更新比分和状态
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"

    -- 如果是联赛阶段（瑞士制），更新联赛积分
    if ucl.phase == "league" then
        ucl:updateLeagueStanding(fixture)
    end

    -- 如果是小组赛（传统模式），更新小组积分
    if ucl.phase == "group" and fixture.groupName then
        ucl:updateGroupStanding(fixture.groupName, fixture)
    end

    -- 更新球队近期状态（form）
    local homeTeam = gameState.teams[fixture.homeTeamId]
    local awayTeam = gameState.teams[fixture.awayTeamId]
    if homeTeam then
        if not homeTeam.recentForm then homeTeam.recentForm = {} end
        if report.homeGoals > report.awayGoals then
            table.insert(homeTeam.recentForm, "W")
        elseif report.homeGoals < report.awayGoals then
            table.insert(homeTeam.recentForm, "L")
        else
            table.insert(homeTeam.recentForm, "D")
        end
        if #homeTeam.recentForm > 5 then table.remove(homeTeam.recentForm, 1) end
    end
    if awayTeam then
        if not awayTeam.recentForm then awayTeam.recentForm = {} end
        if report.awayGoals > report.homeGoals then
            table.insert(awayTeam.recentForm, "W")
        elseif report.awayGoals < report.homeGoals then
            table.insert(awayTeam.recentForm, "L")
        else
            table.insert(awayTeam.recentForm, "D")
        end
        if #awayTeam.recentForm > 5 then table.remove(awayTeam.recentForm, 1) end
    end
end

-- 处理非比赛日
function TurnProcessor.processNonMatchDay(gameState)
    -- 每日训练（新系统：强度/职员/个人训练）
    TrainingManager.processDaily(gameState)
    -- AI球队训练
    TrainingManager.processAITeams(gameState)

    -- 伤病恢复
    TurnProcessor.processInjuryRecovery(gameState)

    -- 体能恢复
    TurnProcessor.processFitnessRecovery(gameState)

    -- 合同系统每日检测（月初触发到期检查）
    ContractManager.processDaily(gameState)

    -- 赛前预告（比赛前一天）
    TurnProcessor.generatePreMatchPreview(gameState)

    -- 转会报价处理（每天）
    TransferManager.processDailyBids(gameState)
    TransferManager.processDailyFreeAgentNegos(gameState)

    -- 转会窗口期间，周四额外执行一次AI转会（增加流动性）
    local month = gameState.date.month
    local inTransferWindow = (month >= 6 and month <= 8) or month == 1
    if inTransferWindow and gameState.dayOfWeek == 4 then
        TransferManager.processAITransfers(gameState)
    end

    -- B3: 租借到期检查（每天）
    TransferManager.processLoanExpiry(gameState)
    -- B3/P3: 预签约到期后自动生效
    TransferManager.processPreContracts(gameState)

    -- B2: 球探任务每日推进
    ScoutManager.processDaily(gameState)

    -- B2: 求职系统每日处理（空缺填补、冷却）
    JobManager.processDaily(gameState)

    -- B2: 随机事件（每天有小概率触发）
    RandomEventManager.processDaily(gameState)

    -- B2: 青训球员每日训练成长
    YouthManager.processDailyTraining(gameState)

    -- 每周处理（周一）
    if gameState.dayOfWeek == 1 then
        TurnProcessor.processWeekly(gameState)
        TurnProcessor.generateWeeklyReport(gameState)
        -- 球探每周发现球员
        TransferManager.processScoutReport(gameState)
        -- 清理过期去重缓存
        MessageManager.cleanupDedupeCache(gameState)
        -- B2: 士气每周更新
        MoraleManager.processWeekly(gameState)
        MoraleManager.processAITeams(gameState)
        -- B2: AI球队声望微调
        ReputationManager.processWeeklyAI(gameState)
        -- 球场扩建进度（每周推进）
        local playerTeam = gameState.teams[gameState.playerTeamId]
        if playerTeam then
            FinanceManager.processStadiumExpansion(playerTeam, gameState)
        end
        -- B3: AI球队管理（阵容/训练/转会名单）
        AIManager.processWeekly(gameState)
        -- B3: AI主动转会（转会窗口内）
        TransferManager.processAITransfers(gameState)
        -- B3: 联赛周报新闻
        NewsGenerator.generateWeeklyReview(gameState)
    end

    -- 每月处理（1号）
    if gameState.date.day == 1 then
        TurnProcessor.generateMonthlyNews(gameState)
        -- 月度收入：赞助 + 转播分成 + 商品销售
        FinanceManager.processMonthlySponsorship(gameState)
        FinanceManager.processMonthlyBroadcast(gameState)
        FinanceManager.processMonthlyMerchandise(gameState)
        -- 月度支出：设施+球场维护
        FinanceManager.processMonthlyMaintenance(gameState)
        -- P3: 转会分期付款/收款
        TransferManager.processInstallments(gameState)
        -- 月度财务报告（发送收入构成+环比消息）
        FinanceManager.generateMonthlyReport(gameState)
        -- B2: 董事会月度评估（15号改为1号简化）
        BoardManager.monthlyEvaluation(gameState)
        -- B2: 声望自然回归
        ReputationManager.monthlyDecay(gameState)
        -- B2: 青训候选刷新
        YouthManager.processMonthly(gameState)
        -- B2: 自由职员池补充
        StaffManager.refreshFreePool(gameState)
        -- B3: AI球队月度管理（阵型/薪资评估）
        AIManager.processMonthly(gameState)
        -- 目标系统：月度目标评估与刷新
        ObjectivesManager.onMonthEnd(gameState)
    end

    -- 随机转会传闻新闻（每天5%概率）
    if Random() < 0.05 then
        TurnProcessor.generateTransferRumor(gameState)
    end

    -- 自动保存检测
    if not gameState._turnCount then gameState._turnCount = 0 end
    gameState._turnCount = gameState._turnCount + 1
    if SettingsManager.shouldAutoSave(gameState._turnCount) then
        local SaveManager = require("scripts/persistence/save_manager")
        SaveManager.save(gameState, "auto")
    end
end

-- 训练处理
function TurnProcessor.processTraining(gameState)
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return end
    local team = gameState.teams[playerTeamId]
    if not team then return end

    for _, pid in ipairs(team.playerIds) do
        local p = gameState.players[pid]
        if p and not p.injured then
            -- 根据训练重点确定可提升属性
            local focusAttrs = TurnProcessor._getTrainingAttrs(team.trainingFocus)
            -- 训练强度影响概率
            local trainChance = 0.05
            local fitnessLoss = 2
            if team.trainingIntensity == "low" then
                trainChance = 0.025
                fitnessLoss = 1
            elseif team.trainingIntensity == "high" then
                trainChance = 0.075
                fitnessLoss = 3
            end

            if Random() < trainChance then
                local attr = focusAttrs[RandomInt(1, #focusAttrs)]
                if p.attributes[attr] and p.attributes[attr] < 20 then
                    p.attributes[attr] = p.attributes[attr] + 1
                    p:calculateOverall()
                end
            end
            -- 体能消耗
            p.fitness = math.max(50, p.fitness - RandomInt(0, fitnessLoss))
        end
    end
end

-- 伤病恢复
function TurnProcessor.processInjuryRecovery(gameState)
    for _, p in pairs(gameState.players) do
        if p.injured and p.injuryDays > 0 then
            local team = p.teamId and gameState.teams[p.teamId]
            local recovery = 1
            if team and p.teamId == gameState.playerTeamId then
                local bonuses = FinanceManager.getFacilityBonuses(team)
                recovery = bonuses.injuryRecovery >= 1.25 and 2 or 1
            end
            p.injuryDays = p.injuryDays - recovery
            if p.injuryDays <= 0 then
                p.injured = false
                p.injuryDays = 0
                -- 如果是玩家球队球员，发消息
                if p.teamId == gameState.playerTeamId then
                    MessageManager.send(gameState, "injury_recovered", { p.displayName })
                end
            end
        end
    end
end

-- 体能恢复
function TurnProcessor.processFitnessRecovery(gameState)
    for _, p in pairs(gameState.players) do
        if not p.injured and p.fitness < 100 then
            p.fitness = math.min(100, p.fitness + RandomInt(1, 3))
        end
    end
end

-- 根据训练重点获取对应属性列表
function TurnProcessor._getTrainingAttrs(focus)
    if focus == "attack" then
        return {"shooting", "dribbling", "passing", "vision", "composure"}
    elseif focus == "defense" then
        return {"tackling", "defending", "positioning", "aerial", "strength"}
    elseif focus == "fitness" then
        return {"speed", "stamina", "strength", "agility"}
    elseif focus == "technical" then
        return {"dribbling", "passing", "vision", "composure", "decisions"}
    elseif focus == "tactical" then
        return {"decisions", "positioning", "teamwork", "vision", "composure"}
    else -- balanced
        return {"speed", "stamina", "strength", "passing", "shooting",
            "tackling", "dribbling", "defending", "positioning", "vision", "decisions"}
    end
end

-- 每周处理
function TurnProcessor.processWeekly(gameState)
    -- 工资扣除（使用 FinanceManager 替代旧逻辑）
    FinanceManager.processWeeklyWages(gameState)

    -- 随机伤病（受训练强度影响）
    -- 注：TrainingManager.processDaily 内部已有伤病概率计算，这里保留额外的周伤病检测
    if gameState.playerTeamId then
        local team = gameState.teams[gameState.playerTeamId]
        if team then
            local injuryChance = 0.015
            if team.trainingIntensity == "low" then injuryChance = 0.005
            elseif team.trainingIntensity == "high" then injuryChance = 0.03
            end
                injuryChance = injuryChance / FinanceManager.getFacilityBonuses(team).injuryRecovery

            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p and not p.injured and Random() < injuryChance then
                    p.injured = true
                    p.injuryDays = RandomInt(3, 17)
                    MessageManager.send(gameState, "training_injury", {
                        p.displayName, p.injuryDays
                    })
                end
            end
        end
    end

    -- 消息清理（保留最近100条）
    MessageManager.cleanup(gameState, 100)
end

-- 生成比赛新闻
function TurnProcessor.generateMatchNews(gameState, fixtures)
    -- 只取前3场生成新闻
    for i = 1, math.min(3, #fixtures) do
        local f = fixtures[i]
        if f.status == "finished" then
            local homeTeam = gameState.teams[f.homeTeamId]
            local awayTeam = gameState.teams[f.awayTeamId]
            if homeTeam and awayTeam then
                local title = string.format("%s %d-%d %s", homeTeam.name, f.homeGoals, f.awayGoals, awayTeam.name)
                local body = ""
                if f.homeGoals > f.awayGoals then
                    body = homeTeam.name .. "在主场取得胜利。"
                elseif f.homeGoals < f.awayGoals then
                    body = awayTeam.name .. "客场凯旋。"
                else
                    body = "双方握手言和。"
                end
                gameState:addNews({
                    category = "match_report",
                    title = title,
                    body = body,
                    relatedTeams = {f.homeTeamId, f.awayTeamId},
                })
            end
        end
    end
end

-- 赛前预告（明天有比赛时发送）
function TurnProcessor.generatePreMatchPreview(gameState)
    if not gameState.league or not gameState.playerTeamId then return end

    -- 检查明天是否有比赛
    local tomorrow = League._addDays(gameState.date, 1)
    local fixtures = TurnProcessor.getFixturesForDate(gameState, tomorrow)

    for _, f in ipairs(fixtures) do
        if f.homeTeamId == gameState.playerTeamId or f.awayTeamId == gameState.playerTeamId then
            local opponent
            local venue
            if f.homeTeamId == gameState.playerTeamId then
                opponent = gameState.teams[f.awayTeamId]
                venue = "主场"
            else
                opponent = gameState.teams[f.homeTeamId]
                venue = "客场"
            end
            if not opponent then return end

            -- 对手排名
            local oppPosition = gameState.league:getTeamPosition(opponent.id)
            local myPosition = gameState.league:getTeamPosition(gameState.playerTeamId)

            -- 对手近期状态
            local oppForm = #opponent.recentForm > 0 and table.concat(opponent.recentForm, "") or "未知"

            local body = string.format(
                "明天将在%s迎战%s（联赛第%d位）。\n对手近期状态: %s\n我方当前排名: 第%d位",
                venue, opponent.name, oppPosition, oppForm, myPosition
            )

            -- 伤病警告
            local injuredCount = 0
            local team = gameState:getPlayerTeam()
            if team then
                for _, pid in ipairs(team.playerIds) do
                    local p = gameState.players[pid]
                    if p and p.injured then injuredCount = injuredCount + 1 end
                end
            end
            if injuredCount > 0 then
                body = body .. string.format("\n注意: 当前有%d名球员因伤缺阵", injuredCount)
            end

            gameState:sendMessage({
                category = "pre_match",
                title = "赛前预告: vs " .. opponent.name,
                body = body,
                priority = "normal",
            })
            return  -- 只发一条
        end
    end
end

-- 每周报告（周一发送）
function TurnProcessor.generateWeeklyReport(gameState)
    if not gameState.league or not gameState.playerTeamId then return end

    local team = gameState:getPlayerTeam()
    if not team then return end

    local position = gameState.league:getTeamPosition(gameState.playerTeamId)
    local standing = gameState.league.standings[gameState.playerTeamId]
    if not standing then return end

    -- 统计本周训练情况
    local players = gameState:getTeamPlayers(gameState.playerTeamId)
    local avgFitness = 0
    local injuredCount = 0
    local lowFitnessCount = 0
    for _, p in ipairs(players) do
        avgFitness = avgFitness + p.fitness
        if p.injured then injuredCount = injuredCount + 1 end
        if p.fitness < 70 then lowFitnessCount = lowFitnessCount + 1 end
    end
    if #players > 0 then avgFitness = math.floor(avgFitness / #players) end

    local body = string.format(
        "本周球队总结:\n" ..
        "联赛排名: 第%d位 (%d分)\n" ..
        "战绩: %d胜 %d平 %d负\n" ..
        "球队平均体能: %d%%\n" ..
        "伤病球员: %d人\n" ..
        "低体能球员: %d人",
        position, standing.points,
        standing.wins, standing.draws, standing.losses,
        avgFitness, injuredCount, lowFitnessCount
    )

    -- 根据排名给出董事会评价
    local totalTeams = #gameState.league.teamIds
    local expectation = ""
    if position <= math.ceil(totalTeams * 0.25) then
        expectation = "\n\n董事会评价: 表现出色，继续保持！"
    elseif position <= math.ceil(totalTeams * 0.5) then
        expectation = "\n\n董事会评价: 表现尚可，期待更进一步。"
    elseif position <= math.ceil(totalTeams * 0.75) then
        expectation = "\n\n董事会评价: 表现平平，需要提升。"
    else
        expectation = "\n\n董事会评价: 表现不佳，请尽快改善！"
    end
    body = body .. expectation

    gameState:sendMessage({
        category = "board",
        title = "每周球队报告",
        body = body,
        priority = "normal",
    })
end

-- 月度联赛新闻
function TurnProcessor.generateMonthlyNews(gameState)
    if not gameState.league then return end

    -- 排行榜前3名
    local sorted = gameState.league:getSortedStandings()
    if #sorted < 3 then return end

    local lines = {}
    for i = 1, math.min(5, #sorted) do
        local entry = sorted[i]
        local team = gameState.teams[entry.teamId]
        if team then
            table.insert(lines, string.format("%d. %s - %d分 (%d胜)",
                i, team.name, entry.points, entry.wins))
        end
    end

    -- 联赛射手榜（简化版：基于进球数最多的队）
    local topTeam = gameState.teams[sorted[1].teamId]
    local bottomTeam = gameState.teams[sorted[#sorted].teamId]

    local body = string.format(
        "%d月联赛形势:\n\n%s\n\n" ..
        "领头羊 %s 状态出色。\n%s 目前垫底，保级形势严峻。",
        gameState.date.month,
        table.concat(lines, "\n"),
        topTeam and topTeam.name or "未知",
        bottomTeam and bottomTeam.name or "未知"
    )

    gameState:addNews({
        category = "league_news",
        title = string.format("%d月联赛形势报告", gameState.date.month),
        body = body,
    })
end

-- 生成转会传闻（支持跨联赛）
function TurnProcessor.generateTransferRumor(gameState)
    -- 收集所有联赛的球队ID
    local allTeamIds = {}
    for _, lg in pairs(gameState.leagues or {}) do
        for _, tid in ipairs(lg.teamIds) do
            table.insert(allTeamIds, tid)
        end
    end
    if #allTeamIds < 2 then return end

    local fromTeamId = allTeamIds[RandomInt(1, #allTeamIds)]
    local toTeamId = allTeamIds[RandomInt(1, #allTeamIds)]
    -- 确保不是同一支球队
    local attempts = 0
    while toTeamId == fromTeamId and attempts < 5 do
        toTeamId = allTeamIds[RandomInt(1, #allTeamIds)]
        attempts = attempts + 1
    end
    if toTeamId == fromTeamId then return end

    local fromTeam = gameState.teams[fromTeamId]
    local toTeam = gameState.teams[toTeamId]
    if not fromTeam or not toTeam then return end

    -- 从源球队随机选一个球员
    if #fromTeam.playerIds == 0 then return end
    local playerId = fromTeam.playerIds[RandomInt(1, #fromTeam.playerIds)]
    local player = gameState.players[playerId]
    if not player then return end

    -- 生成传闻
    local rumorTemplates = {
        "据悉，%s 正在关注 %s 的 %s（%s，能力值%d）。转会费可能在 %.1fM 左右。",
        "%s 有意引进 %s 旗下的 %s，该球员本赛季表现抢眼。",
        "消息人士透露，%s 与 %s 的 %s 接触频繁，一笔交易可能在酝酿之中。",
        "转会窗口未开，但 %s 已经盯上了 %s 的核心球员 %s。",
    }

    local template = rumorTemplates[RandomInt(1, #rumorTemplates)]
    local posName = require("scripts/app/constants").POSITION_NAMES[player.position] or player.position
    local body = string.format(template,
        toTeam.name, fromTeam.name, player.displayName, posName, player.overall, player.value / 1000000)

    gameState:addNews({
        category = "transfer_news",
        title = "转会传闻: " .. player.displayName,
        body = body,
        playerId = player.id,
        relatedTeams = {fromTeamId, toTeamId},
    })
end

return TurnProcessor
