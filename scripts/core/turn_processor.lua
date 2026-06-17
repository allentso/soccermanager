-- core/turn_processor.lua
-- 回合推进处理器

local MatchEngine = require("scripts/match/match_engine")
local PlaceholderEngine = require("scripts/match/placeholder_engine")
local MatchReport = require("scripts/match/match_report")
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")
local League = require("scripts/domain/league")
local TransferManager = require("scripts/systems/transfer_manager")
local ChampionsLeague = require("scripts/systems/champions_league")
local WorldCup = require("scripts/systems/world_cup")
local EuroCup = require("scripts/systems/euro_cup")
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
local DifficultySettings = require("scripts/systems/difficulty_settings")
local NewsGenerator = require("scripts/systems/news_generator")
local AIManager = require("scripts/systems/ai_manager")
local ObjectivesManager = require("scripts/systems/objectives_manager")
local Housekeeping = require("scripts/persistence/housekeeping")
local DomesticCup = require("scripts/systems/domestic_cup")

local TurnProcessor = {}

-- 推进一天
function TurnProcessor.advanceDay(gameState)
    -- 读档后 date/month 等可能为字符串，先规范化避免 string.format 崩溃
    if gameState.normalizeRuntimeScalars then
        gameState:normalizeRuntimeScalars()
    end

    -- 存档迁移：旧格式欧冠 → 新瑞士制（仅首次触发）
    ChampionsLeague.migrateIfNeeded(gameState)

    -- 存档迁移：旧存档无国内杯赛数据时，延迟初始化
    DomesticCup.migrateIfNeeded(gameState)

    -- 存档修复：旧存档赛程早于 8 月赛季起点（旧版中超 3 月 JSON 等）
    local RealDataLoader = require("scripts/data/real_data_loader")
    RealDataLoader.fixMisalignedLeagueFixtures(gameState)

    -- 推进日期
    local newDate = League._addDays(gameState.date, 1)
    gameState.date = newDate
    gameState.dayOfWeek = (gameState.dayOfWeek % 7) + 1

    -- 检查所有联赛当天是否有比赛
    local todayFixtures = TurnProcessor.getFixturesForDate(gameState, newDate)

    -- 补救：模拟已过期但未完成的联赛比赛（防止赛季被漏赛永久卡住）
    local overduePlayerLeague = TurnProcessor._catchUpOverdueLeagueFixtures(gameState, newDate)
    for _, f in ipairs(overduePlayerLeague) do
        table.insert(todayFixtures, f)
    end

    -- 补救：模拟已过期但未完成的欧冠比赛（防止因赛程分配bug导致比赛被跳过）
    local overduePlayerUCL = TurnProcessor._catchUpOverdueUCLFixtures(gameState, newDate)
    for _, f in ipairs(overduePlayerUCL) do
        table.insert(todayFixtures, f)
    end

    -- 检查欧冠当天是否有比赛
    local uclFixtures = TurnProcessor.getUCLFixturesForDate(gameState, newDate)
    for _, f in ipairs(uclFixtures) do
        table.insert(todayFixtures, f)
    end

    -- 补救：模拟已过期但未完成的欧洲杯比赛
    local overduePlayerEuro = TurnProcessor._catchUpOverdueEuroFixtures(gameState, newDate)
    for _, f in ipairs(overduePlayerEuro) do
        table.insert(todayFixtures, f)
    end

    -- 检查欧洲杯当天是否有比赛
    local euroFixtures = TurnProcessor.getEuroFixturesForDate(gameState, newDate)
    for _, f in ipairs(euroFixtures) do
        table.insert(todayFixtures, f)
    end

    -- 补救：模拟已过期但未完成的世界杯比赛（防止因前次错误导致比赛被跳过）
    local overduePlayerWC = TurnProcessor._catchUpOverdueWCFixtures(gameState, newDate)
    for _, f in ipairs(overduePlayerWC) do
        table.insert(todayFixtures, f)
    end

    -- 检查世界杯当天是否有比赛
    local wcFixtures = TurnProcessor.getWCFixturesForDate(gameState, newDate)
    for _, f in ipairs(wcFixtures) do
        table.insert(todayFixtures, f)
    end

    -- 补救：模拟已过期但未完成的杯赛比赛
    local overduePlayerCup = DomesticCup.catchUpOverdueFixtures(gameState, newDate)
    for _, f in ipairs(overduePlayerCup) do
        table.insert(todayFixtures, f)
    end

    -- 检查国内杯赛当天是否有比赛
    local cupFixtures = DomesticCup.getFixturesForDate(gameState, newDate)
    for _, f in ipairs(cupFixtures) do
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

    -- 每日体能恢复（全球比赛日也会执行，轮空/未出场球员不再被跳过）
    TurnProcessor.processDailyFitnessRecovery(gameState)

    -- 周期性处理（无论比赛日/非比赛日都必须执行，防止月初有比赛时跳过收入）
    TurnProcessor._processPeriodicEvents(gameState)

    -- 检查欧冠阶段推进
    ChampionsLeague.checkPhaseAdvance(gameState)

    -- 检查世界杯/欧洲杯阶段推进
    EuroCup.checkPhaseAdvance(gameState)
    WorldCup.checkPhaseAdvance(gameState)

    -- 检查国内杯赛阶段推进
    DomesticCup.checkPhaseAdvance(gameState)

    -- 检查玩家所在联赛是否赛季结束（加 guard 防止重复触发）
    -- 必须同时满足：联赛完成 + 欧冠完成（或不存在）+ 杯赛完成 + 国际大赛已结束（或不存在）
    -- 否则 _startNewSeason 会覆盖进行中的欧洲杯/世界杯（异常存档或快进时可能联赛已完但大赛未完）
    local uclDone = (not gameState.championsLeague)
        or (gameState.championsLeague.phase == "completed")
    local cupsDone = DomesticCup.allCompleted(gameState)
    local euroDone = (not gameState.euroCup)
        or (gameState.euroCup.phase == "completed")
    local wcDone = (not gameState.worldCup)
        or (gameState.worldCup.phase == "completed")
    if gameState.league and gameState.league:isSeasonComplete()
        and uclDone and cupsDone and euroDone and wcDone
        and not gameState._seasonEndProcessing then
        gameState._seasonEndProcessing = true
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

-- 获取当天欧洲杯比赛
function TurnProcessor.getEuroFixturesForDate(gameState, date)
    local euro = gameState.euroCup
    if not euro or euro.phase == "not_started" or euro.phase == "completed" then return {} end
    local fixtures = euro:getFixturesForDate(date)
    for _, f in ipairs(fixtures) do
        f._isWC = true
        f._isEuro = true
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

-- 补救过期联赛比赛：非玩家比赛自动模拟，玩家比赛交给赛前页面处理
function TurnProcessor._catchUpOverdueLeagueFixtures(gameState, currentDate)
    local playerTeamId = gameState.playerTeamId
    local playerOverdue = {}

    for _, lg in pairs(gameState.leagues or {}) do
        for _, fixture in ipairs(lg.fixtures or {}) do
            if fixture.status == "scheduled" and fixture.date and TurnProcessor._isDateBefore(fixture.date, currentDate) then
                local isPlayerMatch = playerTeamId and
                    (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)

                if isPlayerMatch and not gameState._cheatAutoPlay then
                    fixture._pendingPlayerMatch = true
                    table.insert(playerOverdue, fixture)
                    goto continue_fixture
                end

                local report = MatchEngine.simulate(gameState, fixture)
                if report then
                    MatchEngine.applyResult(gameState, fixture, report)
                end
            end

            ::continue_fixture::
        end
    end

    return playerOverdue
end

--- 读档/继续前：清理无效待赛指针，并补模拟非玩家逾期联赛比赛
--- 典型老档：8 月赛程正确，但日历停在 8 月且玩家场次未踢 → 其他队也不动
function TurnProcessor.repairStuckProgressOnLoad(gameState)
    local pf = gameState.pendingPlayerFixture
    if pf and pf.status ~= "scheduled" then
        gameState.pendingPlayerFixture = nil
    end
    TurnProcessor.simulateNonPlayerOverdueLeagueFixtures(gameState)
    TurnProcessor.simulateNonPlayerOverdueUCLFixtures(gameState)
    ChampionsLeague.repairStuckProgress(gameState)
end

--- 在不推进日期的情况下，补模拟所有逾期的非玩家联赛比赛
--- 用于玩家有逾期比赛时仍让其他球队继续踢、积分榜更新
function TurnProcessor.simulateNonPlayerOverdueLeagueFixtures(gameState)
    local currentDate = gameState.date
    local playerTeamId = gameState.playerTeamId

    for _, lg in pairs(gameState.leagues or {}) do
        for _, fixture in ipairs(lg.fixtures or {}) do
            if fixture.status == "scheduled" and fixture.date
                and TurnProcessor._isDateBefore(fixture.date, currentDate) then
                local isPlayerMatch = playerTeamId and
                    (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)
                if not isPlayerMatch or gameState._cheatAutoPlay then
                    local report = MatchEngine.simulate(gameState, fixture)
                    if report then
                        MatchEngine.applyResult(gameState, fixture, report)
                    end
                end
            end
        end
    end
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
        local isPlayerEuroMatch = fixture._isEuro and EuroCup.isPlayerNationMatch(gameState, fixture)
        if isPlayerWCMatch or isPlayerEuroMatch then isPlayerMatch = true end

        if isPlayerMatch and not gameState._cheatAutoPlay then
            fixture._pendingPlayerMatch = true
            goto continue_fixture
        end

        local report = MatchEngine.simulate(gameState, fixture)

        if report then
            if fixture._isEuro then
                TurnProcessor._applyEuroResult(gameState, fixture, report)
            elseif fixture._isWC then
                TurnProcessor._applyWCResult(gameState, fixture, report)
            elseif fixture._isUCL then
                TurnProcessor._applyUCLResult(gameState, fixture, report)
            elseif fixture._isDomesticCup then
                DomesticCup.applyResult(gameState, fixture, report)
            else
                MatchEngine.applyResult(gameState, fixture, report)
            end

            -- 生成比赛消息
            if fixture._isWC or fixture._isEuro or isPlayerMatch then
                local homeName, awayName
                if fixture._isWC or fixture._isEuro then
                    local NT = fixture._isEuro and EuroCup or WorldCup
                    homeName = NT._getNationName(fixture.homeTeamId)
                    awayName = NT._getNationName(fixture.awayTeamId)
                else
                    local homeTeam = gameState.teams[fixture.homeTeamId]
                    local awayTeam = gameState.teams[fixture.awayTeamId]
                    homeName = homeTeam and homeTeam.name or "主队"
                    awayName = awayTeam and awayTeam.name or "客队"
                end
                local prefix = fixture._isUCL and "[欧冠] "
                    or (fixture._isEuro and "[欧洲杯] ")
                    or (fixture._isWC and "[世界杯] ")
                    or ""

                if isPlayerMatch or fixture._isWC or fixture._isEuro then
                    if isPlayerMatch then
                        playerMatchReport = MatchReport.enrichFromFixture(report, fixture, gameState)
                    end
                    local richBody = MatchReport.formatRichMatchBody(gameState, fixture, report, {
                        homeName = homeName,
                        awayName = awayName,
                        prefix = prefix,
                        perspectiveTeamId = isPlayerMatch and gameState.playerTeamId or nil,
                    })
                    gameState:sendMessage({
                        category = "match_result",
                        title = prefix .. "比赛结果",
                        body = richBody,
                        priority = "normal",
                        extra = { fixtureId = fixture.id },
                    })
                    if isPlayerMatch then
                        MatchReport.publishPlayerMatchNews(gameState, fixture, report, {
                            homeName = homeName,
                            awayName = awayName,
                        })
                    end
                end
            end
        end
        ::continue_fixture::
    end

    -- B2: 赛后士气、声望、票房（AI 自动模拟路径；玩家比赛由 finishMatch / 跳过模拟补调）
    for _, fixture in ipairs(fixtures) do
        if fixture.status == "finished" then
            MatchEngine.applyPostMatchEffects(gameState, fixture, fixture)
        end
    end

    -- 生成新闻
    if #fixtures > 0 then
        TurnProcessor.generateMatchNews(gameState, fixtures)
        -- B3: 大比分/爆冷新闻
        for _, fixture in ipairs(fixtures) do
            if not fixture._isWC and not fixture._isEuro then
                NewsGenerator.generateUpsetNews(gameState, fixture)
            end
        end
    end

    -- 同步各联赛球队排名到 team.leaguePosition（转播分成等公式依赖此字段）
    for _, lg in pairs(gameState.leagues or {}) do
        lg:syncTeamPositions(gameState)
    end

    return playerMatchReport
end

--- 在不推进日期的情况下，补模拟所有逾期的非玩家欧冠比赛
function TurnProcessor.simulateNonPlayerOverdueUCLFixtures(gameState)
    local ucl = gameState.championsLeague
    if not ucl or ucl.phase == "completed" then return end

    local currentDate = gameState.date
    local playerTeamId = gameState.playerTeamId
    local simulated = false

    local function maybeSimulate(fixture, isKnockout)
        if fixture.status ~= "scheduled" or not fixture.date then return end
        if not TurnProcessor._isDateBefore(fixture.date, currentDate) then return end
        if playerTeamId and not gameState._cheatAutoPlay
            and (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId) then
            return
        end

        fixture._isUCL = true
        local report = MatchEngine.simulate(gameState, fixture)
        if not report then return end

        if isKnockout then
            TurnProcessor._applyUCLResult(gameState, fixture, report)
        else
            fixture.status = "finished"
            fixture.homeGoals = report.homeGoals or 0
            fixture.awayGoals = report.awayGoals or 0
            fixture.events = report.events
            ucl:updateLeagueStanding(fixture)
        end
        simulated = true
    end

    if ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            maybeSimulate(f, false)
        end
    end

    if ucl.knockout then
        for _, phase in ipairs({"playoff", "r16", "qf", "sf", "final"}) do
            local fixtures = ucl.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    f.tournamentPhase = phase
                    maybeSimulate(f, true)
                end
            end
        end
    end

    if simulated then
        ChampionsLeague.checkPhaseAdvance(gameState)
    end
end

--- 补救过期UCL比赛：模拟非玩家的过期比赛，返回需要玩家处理的过期fixture列表
--- @return table playerOverdueFixtures
function TurnProcessor._catchUpOverdueUCLFixtures(gameState, currentDate)
    local ucl = gameState.championsLeague
    if not ucl then return {} end
    if ucl.phase == "completed" then return {} end

    local playerTeamId = gameState.playerTeamId
    local overdueFixtures = {}

    -- 联赛阶段过期比赛
    if ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            if f.status == "scheduled" and f.date then
                if TurnProcessor._isDateBefore(f.date, currentDate) then
                    table.insert(overdueFixtures, f)
                end
            end
        end
    end

    -- 淘汰赛阶段过期比赛（附加赛、R16、QF、SF、决赛）
    if ucl.knockout then
        local knockoutPhases = {"playoff", "r16", "qf", "sf", "final"}
        for _, phase in ipairs(knockoutPhases) do
            local fixtures = ucl.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    if f.status == "scheduled" and f.date then
                        if TurnProcessor._isDateBefore(f.date, currentDate) then
                            f.tournamentPhase = phase
                            table.insert(overdueFixtures, f)
                        end
                    end
                end
            end
        end
    end

    if #overdueFixtures == 0 then return {} end

    local playerOverdue = {}
    for _, fixture in ipairs(overdueFixtures) do
        fixture._isUCL = true
        local isPlayerMatch = (fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId)

        if isPlayerMatch then
            -- 玩家的过期比赛：标记为待处理，让玩家可以打
            fixture._pendingPlayerMatch = true
            table.insert(playerOverdue, fixture)
            goto continue_ucl_overdue
        end

        -- 非玩家比赛：自动模拟
        local report = MatchEngine.simulate(gameState, fixture)
        if report then
            if fixture.tournamentPhase then
                -- 淘汰赛：用 _applyUCLResult 处理（含两回合制逻辑）
                TurnProcessor._applyUCLResult(gameState, fixture, report)
            else
                -- 联赛阶段：直接更新积分
                fixture.status = "finished"
                fixture.homeGoals = report.homeGoals or 0
                fixture.awayGoals = report.awayGoals or 0
                fixture.events = report.events
                ucl:updateLeagueStanding(fixture)
            end
        end
        ::continue_ucl_overdue::
    end

    -- 补救模拟后检查阶段推进（可能有整轮比赛被补齐）
    if #overdueFixtures > 0 then
        ChampionsLeague.checkPhaseAdvance(gameState)
    end

    return playerOverdue
end

function TurnProcessor._catchUpOverdueEuroFixtures(gameState, currentDate)
    local euro = gameState.euroCup
    if not euro or euro.phase == "not_started" or euro.phase == "completed" then return {} end

    local overdueFixtures = {}

    if euro.phase == "group" then
        for _, group in pairs(euro.groups) do
            for _, f in ipairs(group.fixtures) do
                if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                    table.insert(overdueFixtures, f)
                end
            end
        end
    end

    local knockoutPhases = {"r16", "qf", "sf", "final"}
    for _, phase in ipairs(knockoutPhases) do
        local fixtures = euro.knockout and euro.knockout[phase]
        if fixtures then
            for _, f in ipairs(fixtures) do
                if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                    table.insert(overdueFixtures, f)
                end
            end
        end
    end

    if #overdueFixtures == 0 then return {} end

    local playerOverdue = {}
    for _, fixture in ipairs(overdueFixtures) do
        fixture._isWC = true
        fixture._isEuro = true
        if EuroCup.isPlayerNationMatch(gameState, fixture) then
            fixture._pendingPlayerMatch = true
            table.insert(playerOverdue, fixture)
            goto continue_euro_overdue
        end

        local report = MatchEngine.simulate(gameState, fixture)
        if report then
            TurnProcessor._applyEuroResult(gameState, fixture, report)
        end
        ::continue_euro_overdue::
    end
    return playerOverdue
end

-- 补救机制：模拟已过期但未完成的世界杯比赛
-- 当之前的 advanceDay 因错误中断时，日期推进了但比赛未处理
-- 此函数在每次 advanceDay 时检查并补模拟这些遗漏的比赛
function TurnProcessor._catchUpOverdueWCFixtures(gameState, currentDate)
    local wc = gameState.worldCup
    if not wc or wc.phase == "not_started" or wc.phase == "completed" then return {} end

    local overdueFixtures = {}

    -- 检查小组赛
    if wc.phase == "group" then
        for _, group in pairs(wc.groups) do
            for _, f in ipairs(group.fixtures) do
                if f.status == "scheduled" and f.date then
                    if TurnProcessor._isDateBefore(f.date, currentDate) then
                        table.insert(overdueFixtures, f)
                    end
                end
            end
        end
    end

    -- 检查淘汰赛
    local knockoutPhases = {"r32", "r16", "qf", "sf", "third", "final"}
    for _, phase in ipairs(knockoutPhases) do
        local fixtures = wc.knockout and wc.knockout[phase]
        if fixtures then
            for _, f in ipairs(fixtures) do
                if f.status == "scheduled" and f.date then
                    if TurnProcessor._isDateBefore(f.date, currentDate) then
                        table.insert(overdueFixtures, f)
                    end
                end
            end
        end
    end

    if #overdueFixtures == 0 then return {} end

    -- 模拟所有过期比赛
    local playerOverdue = {}
    for _, fixture in ipairs(overdueFixtures) do
        fixture._isWC = true
        -- 跳过玩家国家队的比赛（不应自动模拟）
        if WorldCup.isPlayerNationMatch(gameState, fixture) then
            fixture._pendingPlayerMatch = true
            table.insert(playerOverdue, fixture)
            goto continue_overdue
        end

        local report = MatchEngine.simulate(gameState, fixture)
        if report then
            TurnProcessor._applyWCResult(gameState, fixture, report)
        end
        ::continue_overdue::
    end
    return playerOverdue
end

--- 仅检测（不模拟、不推进日期）是否存在逾期的玩家比赛
--- 返回第一个逾期的玩家 fixture，或 nil
--- 用于 dashboard 在 advanceDay 之前判断是否应先处理逾期比赛而不消耗日历天数
function TurnProcessor.peekOverduePlayerFixture(gameState)
    local currentDate = gameState.date
    local playerTeamId = gameState.playerTeamId
    if not playerTeamId then return nil end

    -- 检查联赛逾期比赛
    for _, lg in pairs(gameState.leagues or {}) do
        for _, fixture in ipairs(lg.fixtures or {}) do
            if fixture.status == "scheduled" and fixture.date and TurnProcessor._isDateBefore(fixture.date, currentDate) then
                if fixture.homeTeamId == playerTeamId or fixture.awayTeamId == playerTeamId then
                    return fixture
                end
            end
        end
    end

    -- 检查欧冠逾期比赛
    local ucl = gameState.championsLeague
    if ucl and ucl.phase ~= "completed" then
        if ucl.leaguePhase and ucl.leaguePhase.fixtures then
            for _, f in ipairs(ucl.leaguePhase.fixtures) do
                if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                    if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                        f._isUCL = true
                        return f
                    end
                end
            end
        end
        if ucl.knockout then
            local knockoutPhases = {"playoff", "r16", "qf", "sf", "final"}
            for _, phase in ipairs(knockoutPhases) do
                local fixtures = ucl.knockout[phase]
                if fixtures then
                    for _, f in ipairs(fixtures) do
                        if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                                f._isUCL = true
                                return f
                            end
                        end
                    end
                end
            end
        end
    end

    -- 检查欧洲杯逾期比赛
    local euro = gameState.euroCup
    if euro and euro.phase ~= "not_started" and euro.phase ~= "completed" then
        if euro.phase == "group" then
            for _, group in pairs(euro.groups) do
                for _, f in ipairs(group.fixtures) do
                    if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                        if EuroCup.isPlayerNationMatch(gameState, f) then
                            f._isWC = true
                            f._isEuro = true
                            return f
                        end
                    end
                end
            end
        end
        local euroKnockoutPhases = {"r16", "qf", "sf", "final"}
        for _, phase in ipairs(euroKnockoutPhases) do
            local fixtures = euro.knockout and euro.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                        if EuroCup.isPlayerNationMatch(gameState, f) then
                            f._isWC = true
                            f._isEuro = true
                            return f
                        end
                    end
                end
            end
        end
    end

    -- 检查世界杯逾期比赛
    local wc = gameState.worldCup
    if wc and wc.phase ~= "not_started" and wc.phase ~= "completed" then
        local WorldCupMod = require("scripts/systems/world_cup")
        -- 小组赛
        if wc.phase == "group" then
            for _, group in pairs(wc.groups) do
                for _, f in ipairs(group.fixtures) do
                    if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                        if WorldCupMod.isPlayerNationMatch(gameState, f) then
                            f._isWC = true
                            return f
                        end
                    end
                end
            end
        end
        -- 淘汰赛
        local knockoutPhases = {"r32", "r16", "qf", "sf", "third", "final"}
        for _, phase in ipairs(knockoutPhases) do
            local fixtures = wc.knockout and wc.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                        if WorldCupMod.isPlayerNationMatch(gameState, f) then
                            f._isWC = true
                            return f
                        end
                    end
                end
            end
        end
    end

    -- 检查国内杯赛逾期比赛
    local cups = gameState.domesticCups
    if cups then
        for _, cup in pairs(cups) do
            if cup.phase ~= "completed" then
                for _, roundFixtures in ipairs(cup.rounds) do
                    for _, f in ipairs(roundFixtures) do
                        if f.status == "scheduled" and f.date and TurnProcessor._isDateBefore(f.date, currentDate) then
                            if f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId then
                                f._isDomesticCup = true
                                f._cupLeague = cup.leagueKey
                                return f
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- 日期比较辅助：a 是否严格早于 b
function TurnProcessor._isDateBefore(a, b)
    if a.year ~= b.year then return a.year < b.year end
    if a.month ~= b.month then return a.month < b.month end
    return a.day < b.day
end

function TurnProcessor._isDateBeforeOrEqual(a, b)
    if a.year ~= b.year then return a.year < b.year end
    if a.month ~= b.month then return a.month < b.month end
    return a.day <= b.day
end

-- 世界杯比赛模拟（复用 MatchEngine + 虚拟国家队；保留此入口供旧测试/脚本调用）
function TurnProcessor._simulateWCMatch(gameState, fixture)
    fixture._isWC = true
    return MatchEngine.simulate(gameState, fixture)
end

local function _storeKnockoutExtras(fixture, extraTime)
    if not extraTime then return end
    fixture.extraTime = extraTime
    local pen = extraTime.penalties
    if not pen then return end
    fixture.penalties = {
        homeScore = pen.homeScore or pen.homeScored,
        awayScore = pen.awayScore or pen.awayScored,
        winner = pen.winner,
        rounds = pen.rounds,
    }
    fixture._penaltyWinner = pen.winner
end

function TurnProcessor._applyEuroResult(gameState, fixture, report)
    local euro = gameState.euroCup
    if not euro then return end

    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"
    _storeKnockoutExtras(fixture, report.extraTime)

    if euro.phase == "group" and fixture.groupName then
        euro:updateGroupStanding(fixture.groupName, fixture)
    end

    local PlaceholderEngine = require("scripts/match/placeholder_engine")
    PlaceholderEngine.applyPlayerMatchStats(gameState, fixture, report)
end

-- 应用世界杯比赛结果
function TurnProcessor._applyWCResult(gameState, fixture, report)
    local wc = gameState.worldCup
    if not wc then return end

    -- 更新比分和状态
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"

    -- 存储加时赛/点球数据到fixture
    _storeKnockoutExtras(fixture, report.extraTime)

    -- 如果是小组赛，更新小组积分
    if wc.phase == "group" and fixture.groupName then
        wc:updateGroupStanding(fixture.groupName, fixture)
    end

    -- 更新球员出场/进球/助攻/红黄牌/评分/体能
    local PlaceholderEngine = require("scripts/match/placeholder_engine")
    PlaceholderEngine.applyPlayerMatchStats(gameState, fixture, report)
end

-- 应用欧冠比赛结果
function TurnProcessor._applyUCLResult(gameState, fixture, report)
    local ucl = gameState.championsLeague
    if not ucl then return end

    -- 更新比分和状态
    fixture.homeGoals = report.homeGoals
    fixture.awayGoals = report.awayGoals
    fixture.status = "finished"

    -- 存储加时赛/点球数据（来自 MatchEngine 单场淘汰逻辑，如决赛）
    _storeKnockoutExtras(fixture, report.extraTime)

    -- 两回合制第二回合：总比分平局 → 加时 + 点球
    -- 如果 report 已包含 extraTime（玩家亲自踢了加时），直接使用其结果，不再重复模拟
    if fixture.leg == 2 and not fixture._penaltyWinner then
        local knockoutPhases = {playoff = true, r16 = true, qf = true, sf = true}
        local currentPhase = ucl.phase
        if knockoutPhases[currentPhase] then
            local fixtures = ucl.knockout[currentPhase]
            local leg1 = nil
            if fixtures then
                for _, f in ipairs(fixtures) do
                    if f.matchIndex == fixture.matchIndex and f.leg == 1 and f.status == "finished" then
                        leg1 = f
                        break
                    end
                end
            end
            if leg1 then
                local agg1 = leg1.homeGoals + fixture.awayGoals
                local agg2 = leg1.awayGoals + fixture.homeGoals
                if agg1 == agg2 then
                    if report.extraTime then
                        -- 玩家已经踢了加时+点球，直接使用 report 中的结果
                        _storeKnockoutExtras(fixture, report.extraTime)
                    else
                        -- AI 模拟的比赛，需要外部模拟加时+点球
                        local homeTeam = gameState.teams[fixture.homeTeamId]
                        local awayTeam = gameState.teams[fixture.awayTeamId]
                        if homeTeam and awayTeam then
                            local TacticsResolver = require("scripts/match/tactics_resolver")
                            local homeContext = TacticsResolver.buildTeamContext(gameState, homeTeam)
                            local awayContext = TacticsResolver.buildTeamContext(gameState, awayTeam)
                            if #homeContext.players > 0 and #awayContext.players > 0 then
                                local extraTime = MatchEngine.simulateExtraTimeAndPenalties(
                                    fixture, homeContext, awayContext)
                                _storeKnockoutExtras(fixture, extraTime)
                            end
                        end
                    end
                end
            end
        end
    end

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

    local ObjectivesManager = require("scripts/systems/objectives_manager")
    ObjectivesManager.recordMatchResult(gameState, fixture.homeTeamId, report.homeGoals or 0, report.awayGoals or 0, report.events)
    ObjectivesManager.recordMatchResult(gameState, fixture.awayTeamId, report.awayGoals or 0, report.homeGoals or 0, report.events)

    -- 更新球员出场/进球/助攻/红黄牌/评分（UCL专用，联赛由applyResult处理）
    PlaceholderEngine.applyPlayerMatchStats(gameState, fixture, report)
end

-- 处理非比赛日
function TurnProcessor.processNonMatchDay(gameState)
    -- 每日训练（新系统：强度/职员/个人训练）
    TrainingManager.processDaily(gameState)
    -- AI球队训练
    TrainingManager.processAITeams(gameState)

    -- 伤病恢复
    TurnProcessor.processInjuryRecovery(gameState)

    -- 合同系统每日检测（月初触发到期检查）
    ContractManager.processDaily(gameState)

    -- 赛前预告（比赛前一天）
    TurnProcessor.generatePreMatchPreview(gameState)

    -- 转会报价处理（每天）
    TransferManager.processDailyBids(gameState)
    TransferManager.processDailyFreeAgentNegos(gameState)

    -- 转会窗口期间，周四额外执行一次AI转会（增加流动性）
    -- pcall 保护：防止转会系统异常导致整天处理中断（如跳过当天WC比赛）
    local month = gameState.date.month
    local inTransferWindow = (month >= 6 and month <= 8) or month == 1
    if inTransferWindow and gameState.dayOfWeek == 4 then
        local ok, err = pcall(TransferManager.processAITransfers, gameState)
        if not ok then
            print("[TurnProcessor] WARNING: processAITransfers error: " .. tostring(err))
        end
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

end

------------------------------------------------------
-- 周期性事件处理（每周/每月），独立于比赛日/非比赛日
-- 由 advanceDay 在 match/nonMatch 处理后统一调用
------------------------------------------------------
function TurnProcessor._processPeriodicEvents(gameState)
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

-- 训练处理（所有球队统一执行）
function TurnProcessor.processTraining(gameState)
    for _, team in pairs(gameState.teams) do
        if not team.playerIds then goto nextTeam end

        -- AI 球队使用默认训练参数
        local focusAttrs = TurnProcessor._getTrainingAttrs(team.trainingFocus)
        local trainChance = 0.05
        local fitnessLoss = 2
        if team.trainingIntensity == "low" then
            trainChance = 0.025
            fitnessLoss = 1
        elseif team.trainingIntensity == "high" then
            trainChance = 0.075
            fitnessLoss = 3
        end

        for _, pid in ipairs(team.playerIds) do
            local p = gameState.players[pid]
            if p and not p.injured then
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

        ::nextTeam::
    end
end

-- 伤病恢复
function TurnProcessor.processInjuryRecovery(gameState)
    local EventFlavors = require("scripts/match/event_flavors")
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
                EventFlavors.clearInjury(p)
                -- 如果是玩家球队球员，发消息
                if p.teamId == gameState.playerTeamId then
                    MessageManager.send(gameState, "injury_recovered", { p.displayName })
                end
            end
        end
    end
end

-- 体能恢复（旧接口，保留供测试/外部调用）
function TurnProcessor.processFitnessRecovery(gameState)
    TurnProcessor.processDailyFitnessRecovery(gameState)
end

local function _datesEqual(a, b)
    return a and b and a.year == b.year and a.month == b.month and a.day == b.day
end

local UCL_KNOCKOUT_PHASES = { "playoff", "r16", "qf", "sf", "final" }
local WC_KNOCKOUT_PHASES = { "r32", "r16", "qf", "sf", "third", "final" }
local EURO_KNOCKOUT_PHASES = { "r16", "qf", "sf", "final" }

--- 收集指定日期已完成比赛的出场球员
function TurnProcessor._getPlayersWhoPlayedOnDate(gameState, date)
    local played = {}
    local PlaceholderEngine = require("scripts/match/placeholder_engine")

    local function markFixture(f)
        if not f or f.status ~= "finished" or not _datesEqual(f.date, date) then return end
        local report = {
            appearanceIds = f.appearanceIds,
            events = f.events,
            playerRatings = f.playerRatings,
            homeGoals = f.homeGoals,
            awayGoals = f.awayGoals,
        }
        for _, p in ipairs(PlaceholderEngine._collectMatchPlayers(gameState, f, report)) do
            played[p.id] = true
        end
    end

    for _, lg in pairs(gameState.leagues or {}) do
        for _, f in ipairs(lg.fixtures or {}) do
            markFixture(f)
        end
    end

    local ucl = gameState.championsLeague
    if ucl and ucl.leaguePhase and ucl.leaguePhase.fixtures then
        for _, f in ipairs(ucl.leaguePhase.fixtures) do
            markFixture(f)
        end
    end
    if ucl and ucl.knockout then
        for _, phase in ipairs(UCL_KNOCKOUT_PHASES) do
            local fixtures = ucl.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    markFixture(f)
                end
            end
        end
    end

    local euro = gameState.euroCup
    if euro and euro.groups then
        for _, group in pairs(euro.groups) do
            if group.fixtures then
                for _, f in ipairs(group.fixtures) do
                    markFixture(f)
                end
            end
        end
    end
    if euro and euro.knockout then
        for _, phase in ipairs(EURO_KNOCKOUT_PHASES) do
            local fixtures = euro.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    markFixture(f)
                end
            end
        end
    end

    local wc = gameState.worldCup
    if wc and wc.groups then
        for _, group in pairs(wc.groups) do
            if group.fixtures then
                for _, f in ipairs(group.fixtures) do
                    markFixture(f)
                end
            end
        end
    end
    if wc and wc.knockout then
        for _, phase in ipairs(WC_KNOCKOUT_PHASES) do
            local fixtures = wc.knockout[phase]
            if fixtures then
                for _, f in ipairs(fixtures) do
                    markFixture(f)
                end
            end
        end
    end

    return played
end

--- 每日体能恢复：比赛日也执行，按昨日是否出场区分恢复量
function TurnProcessor.processDailyFitnessRecovery(gameState)
    local yesterday = League._addDays(gameState.date, -1)
    local playedYesterday = TurnProcessor._getPlayersWhoPlayedOnDate(gameState, yesterday)

    for _, p in pairs(gameState.players) do
        if not p.injured and p.fitness < 100 then
            local fitnessMods = DifficultySettings.getFitnessModifiers()
            local minRecover, maxRecover
            if playedYesterday[p.id] then
                minRecover, maxRecover = fitnessMods.recoveryPostMatch[1], fitnessMods.recoveryPostMatch[2]
            else
                minRecover, maxRecover = fitnessMods.recoveryRest[1], fitnessMods.recoveryRest[2]
            end
            p.fitness = math.min(100, p.fitness + RandomInt(minRecover, maxRecover))
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
            local trainingMods = DifficultySettings.getTrainingModifiers()
            local weeklyInjury = trainingMods.weeklyInjury
            local intensity = team.trainingIntensity or "medium"
            local injuryChance = weeklyInjury[intensity] or weeklyInjury.medium
                injuryChance = injuryChance / FinanceManager.getFacilityBonuses(team).injuryRecovery

            for _, pid in ipairs(team.playerIds) do
                local p = gameState.players[pid]
                if p and not p.injured and Random() < injuryChance then
                    local EventFlavors = require("scripts/match/event_flavors")
                    local injury = EventFlavors.rollTrainingInjury(gameState, p, {
                        intensity = intensity,
                        maxDays = trainingMods.injuryDaysMax,
                        injuryRisk = 1.0,
                    })
                    injury.days = math.max(trainingMods.injuryDaysMin, injury.days)
                    EventFlavors.applyToPlayer(p, injury)
                    EventFlavors.onInjuryApplied(gameState, p, injury, "training")
                end
            end
        end
    end

    -- 消息清理（保留最近100条）
    MessageManager.cleanup(gameState, 100)

    -- 存档/内存瘦身：清理退役球员、超额自由球员、旧赛果明细、流水上限等（幂等）
    local okHk, hkErr = pcall(Housekeeping.run, gameState)
    if not okHk and log then
        log:Write(LOG_ERROR, "TurnProcessor: Housekeeping 失败: " .. tostring(hkErr))
    end
end

-- 生成比赛新闻（按优先级选取，最多 8 条/日）
function TurnProcessor.generateMatchNews(gameState, fixtures)
    local MAX_DAILY = 8
    local playerTeamId = gameState.playerTeamId

    local function fixturePriority(f)
        if f.status ~= "finished" then return -1 end
        if f._isWC or f._isEuro then return -1 end

        local score = 0
        if playerTeamId and (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId) then
            score = score + 1000
        end

        if playerTeamId and gameState.getTeamLeague then
            local lg = gameState:getTeamLeague(playerTeamId)
            if lg and lg.teamIds then
                for _, tid in ipairs(lg.teamIds) do
                    if tid == f.homeTeamId or tid == f.awayTeamId then
                        score = score + 120
                        break
                    end
                end
            end
        end

        if f._isUCL then score = score + 90 end
        if f._isDomesticCup then score = score + 70 end

        local homeGoals = f.homeGoals or 0
        local awayGoals = f.awayGoals or 0
        local diff = math.abs(homeGoals - awayGoals)
        local total = homeGoals + awayGoals
        if diff >= 4 then score = score + 80
        elseif diff >= 3 then score = score + 40 end
        if total >= 5 then score = score + 25 end

        for _, lg in pairs(gameState.leagues or {}) do
            local hp = lg.getTeamPosition and lg:getTeamPosition(f.homeTeamId)
            local ap = lg.getTeamPosition and lg:getTeamPosition(f.awayTeamId)
            if hp and ap and math.abs(hp - ap) >= 5 and homeGoals ~= awayGoals then
                score = score + 60
                break
            end
        end

        return score
    end

    local candidates = {}
    for _, f in ipairs(fixtures) do
        local pri = fixturePriority(f)
        if pri >= 0 then
            table.insert(candidates, { fixture = f, priority = pri })
        end
    end

    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        local diffA = math.abs((a.fixture.homeGoals or 0) - (a.fixture.awayGoals or 0))
        local diffB = math.abs((b.fixture.homeGoals or 0) - (b.fixture.awayGoals or 0))
        return diffA > diffB
    end)

    local published = 0
    for _, entry in ipairs(candidates) do
        if published >= MAX_DAILY then break end
        local f = entry.fixture

        local dedupeKey = "match_news_" .. tostring(f.id or 0)
        if MessageManager._isDuplicate(gameState, dedupeKey, true) then
            goto continue_news
        end

        -- 玩家比赛已由 publishPlayerMatchNews 发稿
        if playerTeamId and (f.homeTeamId == playerTeamId or f.awayTeamId == playerTeamId) then
            goto continue_news
        end

        local homeTeam = gameState.teams[f.homeTeamId]
        local awayTeam = gameState.teams[f.awayTeamId]
        if not homeTeam or not awayTeam then goto continue_news end

        local title = string.format("%s %d-%d %s", homeTeam.name, f.homeGoals, f.awayGoals, awayTeam.name)
        local body = MatchReport.formatRichMatchBody(gameState, f, f, {
            homeName = homeTeam.name,
            awayName = awayTeam.name,
        })

        gameState:addNews({
            category = "match_report",
            title = title,
            body = body,
            relatedTeams = { f.homeTeamId, f.awayTeamId },
            fixtureId = f.id,
        })
        MessageManager._markSent(gameState, dedupeKey, true)
        published = published + 1

        ::continue_news::
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
