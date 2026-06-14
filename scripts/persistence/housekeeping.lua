-- persistence/housekeeping.lua
-- 存档瘦身/内存治理：清理只增不减的数据结构
--
-- 背景（实测，5联赛x20队跑15个月）：存档从 2.3MB 膨胀到 8MB，其中
--   * players 占 62%（退役球员永不删除 + 青训释放的自由球员泄漏，15个月翻 2.2 倍）
--   * 已完赛 fixtures 的 events/playerRatings/stats 明细约 1MB/赛季
--   * news 无上限只增不减；transfers.history 跨赛季累积；worldHistory 每赛季被写两次
--
-- 入口：
--   * Housekeeping.run(gameState)     —— 每周例行 + 读档后执行（幂等）
--   * 各子函数可单独调用
--
-- 安全原则：
--   * 永不删除：玩家球队球员、有球队的球员、传奇球员、关注列表/活跃报价引用的球员
--   * 退役球员延迟一个赛季删除（保证赛季总结页/退役消息正常展示）
--   * 玩家自己的比赛永远保留完整赛果明细（赛后回看）

local Tournament = require("scripts/domain/tournament")

local Housekeeping = {}

-- 可调参数
Housekeeping.NEWS_CAP = 300              -- 新闻保留条数（最新优先）
Housekeeping.TRANSFER_HISTORY_CAP = 500  -- 转会历史保留条数（最新优先）
Housekeeping.FREE_AGENT_CAP = 150        -- 无球队自由球员池上限（按能力保留最强）
Housekeeping.FIXTURE_DETAIL_KEEP_DAYS = 14 -- 非玩家比赛赛果明细保留天数
Housekeeping.CAREER_HISTORY_CAP = 5      -- 每名球员保留的职业生涯明细赛季数（更早的折叠进 careerTotals）

------------------------------------------------------
-- 工具
------------------------------------------------------

-- 日期转序号（够用即可：月按31天算，仅用于"过了多少天"的粗略比较）
local function dateSerial(d)
    if not d or not d.year then return 0 end
    return d.year * 372 + (d.month or 1) * 31 + (d.day or 1)
end

------------------------------------------------------
-- 1. 退役球员清理（最大收益）
--
-- _processRetirements 只设 retired=true，对象永远留在 players 表里。
-- 这里删除"上赛季或更早退役"的球员：retiredSeason < 当前赛季。
-- 旧存档中 retired=true 但没有 retiredSeason 的，视为早已退役，直接清。
------------------------------------------------------
function Housekeeping.purgeRetiredPlayers(gameState)
    local season = gameState.season or 0
    local removed = 0
    local toRemove = {}
    for id, p in pairs(gameState.players) do
        if p.retired and not p._isVirtual then
            local retiredSeason = p.retiredSeason
            if retiredSeason == nil or retiredSeason < season then
                toRemove[#toRemove + 1] = id
            end
        end
    end
    for _, id in ipairs(toRemove) do
        gameState.players[id] = nil
        removed = removed + 1
    end
    if removed > 0 then
        Housekeeping._cleanDanglingRefs(gameState)
    end
    return removed
end

------------------------------------------------------
-- 2. 自由球员池上限
--
-- 青训释放/合同到期产生的无主球员只进不出。
-- 保留能力最强的 FREE_AGENT_CAP 名，其余删除。
-- 保护：玩家关注列表、活跃报价、传奇球员、虚拟球员（WC另行处理）。
------------------------------------------------------
function Housekeeping.purgeExcessFreeAgents(gameState)
    local shortlist = gameState.shortlist or {}

    -- 活跃报价涉及的球员
    local biddedIds = {}
    if gameState.transfers and gameState.transfers.bids then
        for _, bid in pairs(gameState.transfers.bids) do
            if type(bid) == "table" and bid.playerId then
                biddedIds[bid.playerId] = true
            end
        end
    end

    local freeAgents = {}
    for id, p in pairs(gameState.players) do
        if not p.teamId and not p.retired and not p._isVirtual
            and not p.isLegend
            and not shortlist[id] and not shortlist[tostring(id)]
            and not biddedIds[id] then
            freeAgents[#freeAgents + 1] = { id = id, overall = p.overall or 0 }
        end
    end

    local excess = #freeAgents - Housekeeping.FREE_AGENT_CAP
    if excess <= 0 then return 0 end

    -- 能力低的先删
    table.sort(freeAgents, function(a, b) return a.overall < b.overall end)
    for i = 1, excess do
        gameState.players[freeAgents[i].id] = nil
    end
    Housekeeping._cleanDanglingRefs(gameState)
    return excess
end

-- 清理指向已删除球员的引用（球探报告/发现、关注列表）
function Housekeeping._cleanDanglingRefs(gameState)
    local players = gameState.players

    local function filterByPlayerId(arr)
        if type(arr) ~= "table" then return end
        for i = #arr, 1, -1 do
            local entry = arr[i]
            if type(entry) == "table" and entry.playerId and not players[entry.playerId] then
                table.remove(arr, i)
            end
        end
    end
    filterByPlayerId(gameState.scoutReports)
    filterByPlayerId(gameState.scoutDiscoveries)

    if gameState.shortlist then
        for pid in pairs(gameState.shortlist) do
            local key = tonumber(pid) or pid
            if not players[key] and not players[pid] then
                gameState.shortlist[pid] = nil
            end
        end
    end
end

------------------------------------------------------
-- 3. 世界杯虚拟球员清理（纯内存收益，不进存档但占运行内存）
------------------------------------------------------
function Housekeeping.purgeVirtualPlayers(gameState)
    local wc = gameState.worldCup
    local wcActive = wc and wc.phase
        and wc.phase ~= Tournament.PHASE_COMPLETED
        and wc.phase ~= Tournament.PHASE_NOT_STARTED
    if wcActive then return 0 end

    local removed = 0
    local toRemove = {}
    for id, p in pairs(gameState.players) do
        if p._isVirtual then
            toRemove[#toRemove + 1] = id
        end
    end
    for _, id in ipairs(toRemove) do
        gameState.players[id] = nil
        removed = removed + 1
    end
    gameState._wcVirtualPlayers = nil
    return removed
end

------------------------------------------------------
-- 4. 职业生涯明细折叠
--
-- careerHistory 每球员每赛季 1 条、随赛季线性增长。
-- 仅保留最近 CAREER_HISTORY_CAP 季明细，更早的累加进 careerTotals，
-- 生涯总数据（出场/进球/助攻等）不丢失。
------------------------------------------------------
function Housekeeping.foldCareerHistory(gameState)
    local cap = Housekeeping.CAREER_HISTORY_CAP
    local folded = 0
    for _, p in pairs(gameState.players) do
        local hist = p.careerHistory
        if type(hist) == "table" and #hist > cap then
            local totals = p.careerTotals or {
                seasons = 0, appearances = 0, goals = 0, assists = 0,
                yellowCards = 0, redCards = 0, cleanSheets = 0,
            }
            -- careerHistory 按时间顺序追加（旧在前），从头折叠
            while #hist > cap do
                local rec = table.remove(hist, 1)
                totals.seasons = totals.seasons + 1
                totals.appearances = totals.appearances + (rec.appearances or 0)
                totals.goals = totals.goals + (rec.goals or 0)
                totals.assists = totals.assists + (rec.assists or 0)
                totals.yellowCards = totals.yellowCards + (rec.yellowCards or 0)
                totals.redCards = totals.redCards + (rec.redCards or 0)
                totals.cleanSheets = totals.cleanSheets + (rec.cleanSheets or 0)
                folded = folded + 1
            end
            p.careerTotals = totals
        end
    end
    return folded
end

------------------------------------------------------
-- 5. 旧赛果明细剥离
--
-- 完赛超过 FIXTURE_DETAIL_KEEP_DAYS 天的"非玩家"比赛，
-- 删除 events/playerRatings/stats，只留比分等基本信息。
------------------------------------------------------
function Housekeeping.stripOldFixtureDetails(gameState)
    local cutoff = dateSerial(gameState.date) - Housekeeping.FIXTURE_DETAIL_KEEP_DAYS
    local stripped = 0

    -- protectedIds: 涉及这些队伍的比赛保留完整明细
    local function stripFixtures(fixtures, protectedIds)
        if type(fixtures) ~= "table" then return end
        for _, f in ipairs(fixtures) do
            if type(f) == "table" and f.status == "finished"
                and not protectedIds[f.homeTeamId] and not protectedIds[f.awayTeamId]
                and dateSerial(f.date) < cutoff
                and (f.events or f.playerRatings or f.stats) then
                f.events = nil
                f.playerRatings = nil
                f.stats = nil
                stripped = stripped + 1
            end
        end
    end

    -- 俱乐部赛事：保护玩家球队
    local clubProtected = {}
    if gameState.playerTeamId then clubProtected[gameState.playerTeamId] = true end

    for _, lg in pairs(gameState.leagues or {}) do
        stripFixtures(lg.fixtures, clubProtected)
    end

    local ucl = gameState.championsLeague
    if ucl then
        if ucl.leaguePhase then stripFixtures(ucl.leaguePhase.fixtures, clubProtected) end
        if type(ucl.knockout) == "table" then
            for _, arr in pairs(ucl.knockout) do
                stripFixtures(arr, clubProtected)
            end
        end
    end

    -- 世界杯：teamId 是国家代码，保护玩家执教的国家队
    local wc = gameState.worldCup
    if wc then
        local wcProtected = {}
        local ntc = gameState.nationalTeamCoach
        if ntc and ntc.nation then wcProtected[ntc.nation] = true end

        if type(wc.groups) == "table" then
            for _, group in pairs(wc.groups) do
                if type(group) == "table" then stripFixtures(group.fixtures, wcProtected) end
            end
        end
        if type(wc.knockout) == "table" then
            for _, arr in pairs(wc.knockout) do
                stripFixtures(arr, wcProtected)
            end
        end
    end

    return stripped
end

------------------------------------------------------
-- 6. 流水类裁剪
------------------------------------------------------

-- news 按"新的在前"插入（addNews 用 table.insert(news, 1, ...)），裁掉尾部
function Housekeeping.trimNews(gameState)
    local news = gameState.news
    if type(news) ~= "table" then return 0 end
    local removed = 0
    while #news > Housekeeping.NEWS_CAP do
        table.remove(news)
        removed = removed + 1
    end
    return removed
end

------------------------------------------------------
-- 收入对比链压平（关键修复）
--
-- 历史 bug：FinanceManager.processMatchRevenue 把上一场的完整
-- revenueDetails 表存进 lastRevenue 字段，形成每个主场加深一层的
-- 嵌套链，约 30 个主场后超过 cjson 编码的 64 层深度上限
-- → "encode: nesting depth exceeded 64" → 保存全部静默失败。
-- 源头已改为只存数字；这里把老存档/老运行态中已形成的链压平。
------------------------------------------------------
function Housekeeping.flattenRevenueChains(gameState)
    local flattened = 0
    for _, team in pairs(gameState.teams or {}) do
        local lr = team._lastMatchRevenue
        if type(lr) == "table" and type(lr.lastRevenue) == "table" then
            -- 只保留上一场的收入数字，深层链整体丢弃（交给 GC）
            lr.lastRevenue = lr.lastRevenue.revenue
            flattened = flattened + 1
        end
    end
    return flattened
end

-- AI 球队财务流水裁剪
-- 流水只在玩家球队的财务页展示；AI 球队每队囤 100 条纯属存档负担
-- （实测 99 支 AI 队 × 100 条 ≈ 1MB+）。AI 队只留最近几条。
Housekeeping.AI_TRANSACTION_CAP = 5

function Housekeeping.trimAITransactions(gameState)
    local removed = 0
    for teamId, team in pairs(gameState.teams or {}) do
        if teamId ~= gameState.playerTeamId and type(team.transactions) == "table" then
            local txs = team.transactions
            while #txs > Housekeeping.AI_TRANSACTION_CAP do
                table.remove(txs, 1)
                removed = removed + 1
            end
        end
    end
    return removed
end

-- transfers.history 按时间顺序追加（旧在前），裁掉头部
function Housekeeping.trimTransferHistory(gameState)
    local transfers = gameState.transfers
    if not transfers or type(transfers.history) ~= "table" then return 0 end
    local hist = transfers.history
    local removed = 0
    while #hist > Housekeeping.TRANSFER_HISTORY_CAP do
        table.remove(hist, 1)
        removed = removed + 1
    end
    return removed
end

------------------------------------------------------
-- 7. worldHistory 去重
--
-- 历史 bug：HistoryManager.recordSeasonEnd 和 SeasonManager._recordSeasonHistory
-- 每赛季各写一条。保留信息更全的那条（带 year/awards 字段），合并 uclChampion。
------------------------------------------------------
function Housekeeping.dedupeWorldHistory(gameState)
    local history = gameState.worldHistory
    if type(history) ~= "table" or #history < 2 then return 0 end

    local bySeason = {}   -- season -> 保留的 record
    local order = {}      -- 保持赛季出现顺序
    for _, record in ipairs(history) do
        local season = record.season
        if season == nil then
            -- 无赛季标记的记录原样保留（挂在伪键下不参与去重）
            order[#order + 1] = record
        else
            local kept = bySeason[season]
            if not kept then
                bySeason[season] = record
                order[#order + 1] = season
            else
                -- 选信息更全的：带 year（HistoryManager 版本）优先
                local preferNew = (record.year ~= nil and kept.year == nil)
                local winner = preferNew and record or kept
                local loser = preferNew and kept or record
                -- 合并补充字段（如 UCL 冠军回填可能写在任意一条上）
                if loser.uclChampion and not winner.uclChampion then
                    winner.uclChampion = loser.uclChampion
                end
                if loser.awards and not winner.awards then
                    winner.awards = loser.awards
                end
                bySeason[season] = winner
            end
        end
    end

    local removed = #history
    local result = {}
    for _, key in ipairs(order) do
        if type(key) == "table" then
            result[#result + 1] = key          -- 无 season 的原始记录
        else
            result[#result + 1] = bySeason[key]
        end
    end
    removed = removed - #result
    if removed > 0 then
        gameState.worldHistory = result
    end
    return removed
end

------------------------------------------------------
-- 8. 声望基准线修复（旧存档兼容）
--
-- 旧版本 _baseReputation 锚定初始薪资，声望会被 monthlyDecay 强制拉回。
-- 新版本已移除薪资回归，但旧存档的 _baseReputation 仍是旧值。
-- 修复：将 _baseReputation 刷新为当前声望（幂等：已修复的不会再改）。
------------------------------------------------------
function Housekeeping.fixReputationBaseline(gameState)
    -- v2: 从 wageBudget 重新计算初始声望并重置（覆盖 v1 错误迁移）
    -- 只执行一次，用 _repBaselineV2 标记
    if gameState._repBaselineV2 then return 0 end

    local fixed = 0
    for _, team in pairs(gameState.teams or {}) do
        local wb = team.wageBudget
        if wb and wb > 0 then
            -- 与 RealDataLoader._calcReputation 相同的对数映射公式
            local logWb = math.log(wb)
            local logMin = math.log(200000)
            local logMax = math.log(6500000)
            local ratio = (logWb - logMin) / (logMax - logMin)
            ratio = math.max(0, math.min(1, ratio))
            local initRep = math.floor(500 + ratio * 450)

            team.reputation = initRep
            team._baseReputation = initRep
            fixed = fixed + 1
        end
    end
    gameState._repBaselineV2 = true
    return fixed
end

------------------------------------------------------
-- 主入口（幂等，可重复执行）
------------------------------------------------------
------------------------------------------------------
-- 残留青训引用清理
--
-- 历史 bug（BUG-20260611-06）：转会完成时未从卖方 _youthPlayerIds 移除球员，
-- 残留引用会被 AI 青训月度提拔覆盖球员的 teamId/wage/contractEnd。
-- 此处清理所有球队（含玩家队）中"球员已删除或已不属于本队"的青训引用，
-- 让已损坏的旧存档读档后自愈。租借在外（_loanOriginTeamId 指回本队）的保留。
------------------------------------------------------
function Housekeeping.purgeStaleYouthRefs(gameState)
    local removed = 0
    for teamId, team in pairs(gameState.teams or {}) do
        local list = team._youthPlayerIds
        if list then
            for i = #list, 1, -1 do
                local pid = list[i]
                local p = gameState.players[pid]
                local stillOurs = p and
                    (p.teamId == teamId or p._loanOriginTeamId == teamId)
                local alreadyFirstTeam = false
                if stillOurs and p and not p.isYouth then
                    for _, fpid in ipairs(team.playerIds or {}) do
                        if fpid == pid then
                            alreadyFirstTeam = true
                            break
                        end
                    end
                end
                if not stillOurs or alreadyFirstTeam then
                    table.remove(list, i)
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

------------------------------------------------------
-- 阵容一致性修复
--
-- 历史 bug：转会/租借完成后球员仍残留在原队 playerIds，
-- 导致同一球员在多个俱乐部出现且共用 seasonStats（射手榜重复统计）。
-- 规则：球员只应出现在 player.teamId 对应球队的 playerIds 中。
------------------------------------------------------
function Housekeeping.reconcileRosters(gameState)
    local removed = 0
    for _, team in pairs(gameState.teams or {}) do
        local seen = {}
        for i = #(team.playerIds or {}), 1, -1 do
            local pid = team.playerIds[i]
            local player = gameState.players[pid]
            if seen[pid] or not player or player.teamId ~= team.id then
                table.remove(team.playerIds, i)
                removed = removed + 1
            else
                seen[pid] = true
            end
        end
    end

    for _, player in pairs(gameState.players) do
        if player.teamId and not player.retired then
            local team = gameState.teams[player.teamId]
            if team then
                team:addPlayer(player.id)
            end
        end
    end
    return removed
end

function Housekeeping.clampPlayerPotentialCaps(gameState)
    if not gameState or not gameState.players then return 0 end
    for _, player in pairs(gameState.players) do
        if player.clampToPotentialCaps then
            player:clampToPotentialCaps()
        end
    end
    return 0
end

function Housekeeping.run(gameState)
    if not gameState or not gameState.players then return end

    Housekeeping.clampPlayerPotentialCaps(gameState)

    local TransferManager = require("scripts/systems/transfer_manager")
    local _, loanDelisted = TransferManager.clearLoanListingsOutsideWindow(gameState, { silent = true })

    local stats = {
        repBaseline = Housekeeping.fixReputationBaseline(gameState),
        revenueChains = Housekeeping.flattenRevenueChains(gameState),
        retired = Housekeeping.purgeRetiredPlayers(gameState),
        freeAgents = Housekeeping.purgeExcessFreeAgents(gameState),
        virtual = Housekeeping.purgeVirtualPlayers(gameState),
        career = Housekeeping.foldCareerHistory(gameState),
        fixtures = Housekeeping.stripOldFixtureDetails(gameState),
        news = Housekeeping.trimNews(gameState),
        transfers = Housekeeping.trimTransferHistory(gameState),
        aiTx = Housekeeping.trimAITransactions(gameState),
        worldHistory = Housekeeping.dedupeWorldHistory(gameState),
        youthRefs = Housekeeping.purgeStaleYouthRefs(gameState),
        rosters = Housekeeping.reconcileRosters(gameState),
        loanListings = loanDelisted or 0,
    }

    local YouthManager = require("scripts/systems/youth_manager")
    stats.overageYouth = YouthManager.purgeOverageYouth(gameState) or 0

    if log then
        local total = 0
        for _, v in pairs(stats) do total = total + v end
        if total > 0 then
            log:Write(LOG_INFO, string.format(
                "Housekeeping: 清理完成 声望修复=%d 收入链=%d 退役=%d 自由球员=%d 虚拟=%d 生涯折叠=%d 赛果明细=%d 新闻=%d 转会=%d AI流水=%d 历史去重=%d 青训残留=%d 阵容修复=%d",
                stats.repBaseline, stats.revenueChains, stats.retired, stats.freeAgents, stats.virtual, stats.career,
                stats.fixtures, stats.news, stats.transfers, stats.aiTx, stats.worldHistory, stats.youthRefs, stats.rosters))
        end
    end

    return stats
end

return Housekeeping
