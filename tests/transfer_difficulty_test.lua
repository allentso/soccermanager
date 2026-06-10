-- tests/transfer_difficulty_test.lua
-- 验证：保守档高薪低能报价阻断 + 声望拒绝年龄优化

package.path = package.path .. ";/workspace/?.lua;/workspace/?/init.lua"

-- Mock 基础全局
_G.Random = math.random
_G.RandomInt = function(a, b) return math.random(a, b) end

-- 加载被测模块
local DifficultySettings = require("scripts/systems/difficulty_settings")
local TransferManager = require("scripts/systems/transfer_manager")

local passed = 0
local failed = 0

local function assert_eq(desc, got, expected)
    if got == expected then
        passed = passed + 1
        print("  ✓ " .. desc)
    else
        failed = failed + 1
        print("  ✗ " .. desc .. " | 期望: " .. tostring(expected) .. " 实际: " .. tostring(got))
    end
end

local function assert_true(desc, val)
    assert_eq(desc, not not val, true)
end

local function assert_false(desc, val)
    assert_eq(desc, not not val, false)
end

---------------------------------------------------------------
-- 构造最小 gameState
---------------------------------------------------------------
local function makeGameState(transferTier)
    local gs = {
        date = { year = 2024, month = 7, day = 1 },
        playerTeamId = "team_player",
        teams = {
            team_player = { id = "team_player", name = "曼联", reputation = 680, balance = 50000000, transferBudget = 30000000 },
            team_ai1 = { id = "team_ai1", name = "AI球队A", reputation = 600, balance = 40000000, transferBudget = 20000000 },
            team_ai2 = { id = "team_ai2", name = "AI球队B", reputation = 550, balance = 30000000, transferBudget = 15000000 },
            team_ai3 = { id = "team_ai3", name = "AI球队C", reputation = 500, balance = 20000000, transferBudget = 10000000 },
        },
        players = {},
        settings = {
            difficulty = { transferTier = transferTier, matchTier = 2, youthTier = 2 }
        },
        messages = {},
        sendMessage = function(self, msg) table.insert(self.messages, msg) end,
    }
    _G.gameState = gs
    return gs
end

local function makePlayer(id, opts)
    return {
        id = id,
        displayName = opts.name or id,
        overall = opts.overall or 70,
        wage = opts.wage or 100000,
        value = opts.value or 5000000,
        age = opts.age or 27,
        position = opts.position or "CM",
        teamId = opts.teamId or "team_player",
        listedForSale = opts.listedForSale or false,
        retired = false,
        morale = opts.morale or 60,
        squadRole = opts.squadRole or "squad",
    }
end

---------------------------------------------------------------
print("\n========================================")
print("TEST 1: _findBuyerForPlayer 高薪低能阻断")
print("========================================")

-- 创建一个高薪低能球员（OVR 68, wage 408000）
-- fairWage = 25 * exp(0.117 * 68) ≈ 68000 → 408000/68000 ≈ 6x，远超1.5x
do
    -- 保守档
    local gs = makeGameState(1)
    local overpaidPlayer = makePlayer("p_varane", {
        name = "瓦拉内", overall = 68, wage = 408000,
        value = 8000000, teamId = "team_player", listedForSale = true
    })
    gs.players["p_varane"] = overpaidPlayer

    -- Mock _getTeamAverageOverall（避免遍历空阵容）
    local origGetAvg = TransferManager._getTeamAverageOverall
    TransferManager._getTeamAverageOverall = function() return 72 end

    local buyer = TransferManager._findBuyerForPlayer(gs, overpaidPlayer)
    assert_eq("保守档: 高薪低能球员无人问津", buyer, nil)

    -- 正常档（多次测试，应大概率返回 nil）
    gs.settings.difficulty.transferTier = 2
    local nilCount = 0
    for i = 1, 20 do
        local b = TransferManager._findBuyerForPlayer(gs, overpaidPlayer)
        if b == nil then nilCount = nilCount + 1 end
    end
    assert_true("正常档: 高薪低能球员大概率无人问津 (>=12/20)", nilCount >= 12)
    print("    (正常档 nil 次数: " .. nilCount .. "/20)")

    -- 宽松档
    gs.settings.difficulty.transferTier = 3
    local foundCount = 0
    for i = 1, 20 do
        local b = TransferManager._findBuyerForPlayer(gs, overpaidPlayer)
        if b ~= nil then foundCount = foundCount + 1 end
    end
    assert_true("宽松档: 高薪低能球员仍有机会找到买家 (>=5/20)", foundCount >= 5)
    print("    (宽松档 found 次数: " .. foundCount .. "/20)")

    -- 正常球员（OVR 79, wage 120000, fairWage≈25*exp(0.117*79)≈257k, 未超1.5x）
    local normalPlayer = makePlayer("p_normal", {
        name = "正常球员", overall = 79, wage = 120000,
        value = 15000000, teamId = "team_player", listedForSale = true
    })
    gs.players["p_normal"] = normalPlayer
    gs.settings.difficulty.transferTier = 1  -- 保守档

    local normalBuyer = TransferManager._findBuyerForPlayer(gs, normalPlayer)
    assert_true("保守档: 正常球员仍有人想买", normalBuyer ~= nil)

    TransferManager._getTeamAverageOverall = origGetAvg
end

---------------------------------------------------------------
print("\n========================================")
print("TEST 2: _checkPlayerWillingness 声望阈值优化")
print("========================================")

do
    local gs = makeGameState(2)

    -- 场景: 当前球队声望 680，目标球队声望 540 → 差距 140
    local targetTeam = gs.teams["team_ai2"]  -- rep 550
    -- 调整为差距刚好 140
    gs.teams["team_player"].reputation = 690
    targetTeam.reputation = 550  -- diff = 140

    -- 25岁正常球员 → 阈值120，差距140 > 120 → 拒绝
    local normalAgePlayer = makePlayer("p_mid", {
        name = "正常年龄", overall = 75, age = 25, teamId = "team_player"
    })
    gs.players["p_mid"] = normalAgePlayer
    local willing1, reason1 = TransferManager._checkPlayerWillingness(gs, normalAgePlayer, targetTeam)
    assert_false("25岁球员: 声望差140 → 拒绝", willing1)
    print("    原因: " .. (reason1 or ""))

    -- 35岁老将 → 阈值200，差距140 < 200 → 接受
    local oldPlayer = makePlayer("p_old", {
        name = "老将", overall = 72, age = 35, teamId = "team_player"
    })
    gs.players["p_old"] = oldPlayer
    local willing2, reason2 = TransferManager._checkPlayerWillingness(gs, oldPlayer, targetTeam)
    assert_true("35岁老将: 声望差140 → 接受(阈值200)", willing2)

    -- 20岁年轻人 → 阈值180，差距140 < 180 → 接受
    local youngPlayer = makePlayer("p_young", {
        name = "年轻人", overall = 65, age = 20, teamId = "team_player"
    })
    gs.players["p_young"] = youngPlayer
    local willing3, reason3 = TransferManager._checkPlayerWillingness(gs, youngPlayer, targetTeam)
    assert_true("20岁年轻人: 声望差140 → 接受(阈值180)", willing3)

    -- 极端差距测试: 差距 210 → 所有人都拒绝
    targetTeam.reputation = 480  -- diff = 690 - 480 = 210
    local willing4 = TransferManager._checkPlayerWillingness(gs, oldPlayer, targetTeam)
    assert_false("35岁老将: 声望差210 → 也拒绝(超过200)", willing4)

    local willing5 = TransferManager._checkPlayerWillingness(gs, youngPlayer, targetTeam)
    assert_false("20岁年轻人: 声望差210 → 也拒绝(超过180)", willing5)
end

---------------------------------------------------------------
print("\n========================================")
print("TEST 3: getPlayerTransferAttitude 年龄因子")
print("========================================")

do
    local gs = makeGameState(2)
    gs.teams["team_player"].reputation = 680
    gs.teams["team_ai3"].reputation = 500  -- diff = -180

    -- 25岁球员转去低声望球队 → 声望惩罚 -20
    local midPlayer = makePlayer("p_att_mid", {
        name = "中年球员", overall = 75, age = 25, teamId = "team_player", morale = 50
    })
    gs.players["p_att_mid"] = midPlayer

    -- 35岁老将 → 声望惩罚减半 = -10
    local oldPlayer = makePlayer("p_att_old", {
        name = "老将球员", overall = 72, age = 35, teamId = "team_player", morale = 50
    })
    gs.players["p_att_old"] = oldPlayer

    -- 19岁年轻人 → 声望惩罚减半 = -10
    local youngPlayer = makePlayer("p_att_young", {
        name = "年轻球员", overall = 65, age = 19, teamId = "team_player", morale = 50
    })
    gs.players["p_att_young"] = youngPlayer

    local att1 = TransferManager.getPlayerTransferAttitude(gs, "p_att_mid", "team_ai3")
    local att2 = TransferManager.getPlayerTransferAttitude(gs, "p_att_old", "team_ai3")
    local att3 = TransferManager.getPlayerTransferAttitude(gs, "p_att_young", "team_ai3")

    print("    25岁态度: " .. att1 .. " (声望差-180, 惩罚-20)")
    print("    35岁态度: " .. att2 .. " (声望差-180, 惩罚-10)")
    print("    19岁态度: " .. att3 .. " (声望差-180, 惩罚-10)")

    -- 25岁: base 50 + squadRole 10 - rep 20 = 40 → reluctant
    -- 35岁: base 50 + squadRole 10 - rep 10 = 50 → open
    -- 19岁: base 50 + squadRole 10 - rep 10 = 50 → open
    assert_eq("25岁球员态度更消极(reluctant)", att1, "reluctant")
    assert_eq("35岁老将态度更积极(open)", att2, "open")
    assert_eq("19岁年轻人态度更积极(open)", att3, "open")
end

---------------------------------------------------------------
print("\n========================================")
print(string.format("结果: %d 通过, %d 失败", passed, failed))
print("========================================\n")

if failed > 0 then
    os.exit(1)
end
