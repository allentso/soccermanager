# 转会系统分析文档

## 文件概览

| 文件 | 行数 | 职责 |
|------|------|------|
| `scripts/systems/transfer_manager.lua` | 2641 | 核心后端：所有转会逻辑 |
| `scripts/systems/transfers/transfer_completion.lua` | ~80 | 辅助模块（注入到 TransferManager） |
| `scripts/systems/contract_manager.lua` | ~280 | 合同续约、到期、解约 |
| `scripts/ui/screens/market.lua` | ~1350 | 玩家市场 UI（浏览、报价、出售、球探、自由球员、租借） |
| `scripts/ui/screens/transfer_hub.lua` | ~330 | 全局转会新闻中心（只读） |
| `scripts/ui/screens/market/loans_tab.lua` | ~120 | 租借市场子标签 |

---

## 核心数据结构

### Bid 对象 (`gameState.transfers.bids[]`)

```lua
{
    id                -- 自增整数
    playerId          -- 目标球员 ID
    buyerTeamId       -- 买方球队 ID
    sellerTeamId      -- 卖方球队 ID
    amount            -- 当前报价金额
    playerValue       -- 报价时球员市场价值
    status            -- "pending"|"accepted"|"rejected"|"negotiating"|"cancelled"|"completed"
    date              -- {year, month, day}
    responseDate      -- AI 最后回复日期
    wageOffer         -- 提供的周薪
    counterAmount     -- AI 的还价金额
    currentRound      -- 当前谈判轮次
    maxRounds         -- AI 耐心上限 (3-5，随机)
    mood              -- AI 情绪 0-100（影响接受阈值）
    rounds[]          -- [{round, offer, counter, result}]
    type              -- nil=永久转会, "loan"=租借
    isIncomingBid     -- true: AI 购买玩家球队的球员
    isPushSale        -- true: 玩家主动推销给目标俱乐部
    isReleaseClause   -- true: 通过解约金触发
    installments[]    -- [{amount, dueDate}] 分期付款
    appearanceBonus   -- {count, amount} 出场奖金
    sellOnPercent     -- 未来转售分成百分比
    _effectiveValue   -- 计算后总价值（含条款折扣）
}
```

### 自由球员谈判对象 (`gameState.transfers.freeAgentNegos[]`)

```lua
{
    id, playerId, teamId
    status            -- "pending"|"negotiating"|"accepted"|"rejected"|"cancelled"
    wageOffer, yearsOffer     -- 提供的周薪和合同年数
    expectedWage, expectedYears  -- 球员期望
    counterWage, counterYears    -- AI 还价
    currentRound, maxRounds, mood
    rounds[]
    isPreContract     -- true: 预签合同谈判
    effectiveDate     -- {year, month} 预签生效日期
}
```

### 活跃租借 (`gameState._activeLoans[]`)

```lua
{
    playerId, playerName
    originTeamId, loanTeamId
    remainingWeeks    -- 剩余周数
    wageShare         -- 工资分担比例
}
```

---

## 核心逻辑流程

### 1. 永久转会报价流程

```
玩家点击"报价" (market.lua)
    │
    ├── TransferManager.makeBidWithClauses(gameState, playerId, amount, wage, clauses)
    │       └── 创建 bid 对象 (status="pending", mood=50, maxRounds=3~5)
    │       └── 附加条款计算 _effectiveValue
    │
    ├── [等待每日处理] processDailyBids(gameState)
    │       └── _processAIResponse(bid)
    │           ├── ratio = effectiveValue / playerValue
    │           ├── acceptThreshold = 1.3 - (mood/200) - round*0.05
    │           ├── ratio >= max(threshold, 0.9) → 接受
    │           ├── ratio >= 0.6 → 还价 (status="negotiating")
    │           └── ratio < 0.6 → 拒绝
    │
    ├── [玩家加价] TransferManager.raiseBid(gameState, bidId, newAmount)
    │       └── 更新 amount，重新进入 processDailyBids 循环
    │
    └── [接受后] _acceptBid(gameState, bid)
            └── _requirePlayerConsentForTransfer() → 检查球员意愿
            └── _completeTransfer(gameState, bid)
                ├── 从卖方移除球员
                ├── 加入买方
                ├── 结算转会费 (_settleTransferFee)
                ├── 附加未来条款 (_attachFutureClauses)
                ├── 记录历史
                └── 发送通知
```

### 2. AI 接受/拒绝算法

```lua
acceptThreshold = 1.3 - (mood / 200) - currentRound * 0.05
-- mood=50, round=1 → threshold = 1.3 - 0.25 - 0.05 = 1.0
-- mood=50, round=3 → threshold = 1.3 - 0.25 - 0.15 = 0.9 (最低)

if ratio >= max(acceptThreshold, 0.9) then → 接受
if ratio >= 0.6 then → 还价（counter = playerValue * (1.35 - round*0.07 ± mood调整)）
if ratio < 0.6 then → 直接拒绝
```

### 3. AI 自动转会（每周一处理）

```
processAITransfers(gameState)  -- 仅在转会窗口期（6-8月 和 1月）
    │
    ├── _aiListPlayersForSale()  -- AI 自动挂牌老化/多余球员
    │
    ├── 每支 AI 球队 40% 概率尝试签人（每周上限 6 笔）
    │   ├── _assessTeamNeed() → 评估需求位置
    │   ├── _findTransferTarget() → 匹配目标球员
    │   └── _executeAITransfer() → 即时成交（不走 bid 管线）
    │
    └── 玩家挂牌球员 30% 概率吸引买家
        └── _createIncomingBid() → 创建 isIncomingBid 的 bid
```

### 4. 自由球员签约流程

```
offerFreeAgent(gameState, playerId, wageOffer, yearsOffer)
    │
    ├── [每日处理] _processFreeAgentResponse(nego)
    │       └── wageRatio = wageOffer / expectedWage
    │       └── acceptThreshold = 1.0 - (mood/300) - round*0.03 (最低 0.7)
    │       └── 接受/还价/拒绝
    │
    └── _completeFreeAgentSigning()
            ├── 设置 player.wage, player.contractEnd, player.teamId
            └── 加入球队 playerIds
```

### 5. 租借流程

```
makeLoanBid(gameState, playerId, weeks=26)
    │
    ├── [每日处理] _processLoanBidResponse()
    │       └── 类似永久转会的接受逻辑（更宽松）
    │
    ├── [接受] 创建 _activeLoans 条目
    │
    └── [每日] processLoanExpiry()
            └── remainingWeeks -= 1/7
            └── 到期: _returnLoanPlayer() → 球员回归原队
```

### 6. 竞争性报价处理

```
processCompetitiveBids(gameState)
    └── 按 playerId 分组所有 pending/negotiating 的非推销 bid
    └── 若 ≥2 个 bid 竞争同一球员（且不属于玩家球队）
        └── 最高 _effectiveValue 的 bid 自动接受
        └── 其余全部拒绝
```

---

## 系统交互图

```
turn_processor.lua (每日/每周触发器)
    │
    ├── TransferManager.processDailyBids()           (每天)
    ├── TransferManager.processDailyFreeAgentNegos() (每天)
    ├── TransferManager.processLoanExpiry()          (每天)
    ├── TransferManager.processPreContracts()        (每天)
    ├── TransferManager.processAITransfers()         (每周一 + 转会窗口期)
    └── TransferManager.processInstallments()        (每月)

market.lua (玩家 UI 操作)
    ├── makeBid / makeBidWithClauses    — 发起报价
    ├── raiseBid                        — 加价
    ├── cancelBid                       — 撤回
    ├── acceptIncomingBid               — 接受来报
    ├── rejectIncomingBid               — 拒绝来报
    ├── offerFreeAgent / reviseOffer    — 自由球员签约
    ├── makeLoanBid                     — 租借报价
    ├── triggerReleaseClause            — 触发解约金
    └── offerToClub                     — 推销球员

contract_manager.lua (平行系统)
    └── 共享字段: player.contractEnd, player.wage, player.teamId
    └── _releasePlayer() → player.teamId = nil → 变为自由球员

transfer_completion.lua (注入辅助函数)
    ├── _settleTransferFee       — 结算转会费（一次性/分期）
    ├── _removePlayerFromTeam    — 从球队移除球员
    ├── _attachFutureClauses     — 附加卖方条款
    └── _requirePlayerConsentForTransfer — 球员意愿检查
```

---

## 发现的 Bug 和问题

### 严重 (High)

| # | 问题 | 位置 |
|---|------|------|
| 1 | **永久转会缺少球员个人条款谈判**：与俱乐部谈妥转会费后直接完成转会，不需要和球员谈薪资/合同年限。`bid.wageOffer` 存在但从未使用，`_completeTransfer` 不更新 `player.wage` 和 `player.contractEnd`，球员保留原合同条件 | `transfer_manager.lua:_completeTransfer` |
| 2 | **`cancelBid` 对 `"negotiating"` 状态无效**：`cancelBid` 只处理 `status == "pending"`，但 UI 在 `"negotiating"` 时也显示"撤回"按钮，点击后静默失败 | `transfer_manager.lua:162`, `market.lua` |
| 3 | **`offerFreeAgent` 和 `reviseOffer` 格式化错误**：`fmtMoney()` 返回字符串如 `"10.0K"`，但用在 `%.1fK` 格式符中，会导致运行时错误 `bad argument to 'format'` | `transfer_manager.lua` |
| 4 | **`processDailyBids` 被猴子补丁覆盖**：原始定义（~第210行）是死代码，实际执行的是第~2510行的重写版本，但原始版本仍然存在，造成维护混乱 | `transfer_manager.lua:210 vs ~2510` |

### 中等 (Medium)

| # | 问题 | 位置 |
|---|------|------|
| 4 | **`triggerReleaseClause` 发送两条通知**：`_completeTransfer` 已发送一条"转会完成"消息，`triggerReleaseClause` 又发一条"解约金触发"消息 | `transfer_manager.lua` |
| 5 | **`_acceptBid` 在检查意愿前就设置了 `"accepted"` 状态**：如果意愿检查失败会改为 `"rejected"`，但中间状态逻辑不正确 | `transfer_manager.lua` |
| 6 | **`ContractManager` 使用硬编码年份 2024**：`getSuggestedTerms` 和 `_calcAcceptChance` 中年龄计算用了 `2024 - player.birthYear`，应使用 `gameState.date.year` | `contract_manager.lua` |
| 7 | **`_showBidSheet` 和 `_showBidSheet_render` 重复实现**：~200行几乎相同的代码，任何 UI 修改需要改两处 | `market.lua` |

### 低 (Low)

| # | 问题 | 位置 |
|---|------|------|
| 8 | **租借到期使用浮点数倒计时**：`remainingWeeks -= 1/7` 每天累积浮点误差，应改用目标日期 | `transfer_manager.lua` |
| 9 | **租借标签只显示 `listedForLoan` 球员**：无法对未挂牌球员发起租借，但后端 `makeLoanBid` 无此限制 | `loans_tab.lua` |

---

## 转会费决策参数

| 参数 | 影响 | 范围 |
|------|------|------|
| `mood` | AI 情绪，影响接受和还价阈值 | 0-100 |
| `maxRounds` | 最大谈判轮次 | 3-5 (随机) |
| `acceptThreshold` | 接受报价的最低 ratio | 0.9-1.3（逐轮递减） |
| `counterMultiplier` | AI 还价的倍率 | 从 1.35 起逐轮递减 0.07 |
| `_effectiveValue` | 含条款折扣的总价值 | base + 条款部分折现 |
| 挂牌加成 | 已挂牌球员接受概率 +35% | `_executeAITransfer` |

---

## 转会窗口规则

- **夏窗**：6月、7月、8月
- **冬窗**：1月
- 窗口外：AI 不主动发起转会（`processAITransfers` 直接 return）
- 玩家报价不受窗口限制（代码中无校验）

---

## 建议优化方向

1. **修复 cancelBid**：扩展为支持 `"negotiating"` 状态的取消
2. **修复格式化 bug**：`fmtMoney` 返回值直接用于拼接，不要套 `%.1f`
3. **删除死代码**：移除被覆盖的原始 `processDailyBids`
4. **提取年份**：统一使用 `gameState.date.year` 替代硬编码 2024
5. **拆分 transfer_manager.lua**：2641 行过长，建议按功能拆分为：
   - `transfers/bid_processor.lua` — 报价处理和 AI 响应
   - `transfers/ai_transfers.lua` — AI 自动转会
   - `transfers/free_agents.lua` — 自由球员签约
   - `transfers/loans.lua` — 租借系统
   - `transfers/completion.lua` — 完成转会（已拆出）
6. **租借到期改用日期**：存储 `expiryDate` 而非浮点倒计时
7. **合并重复 UI 代码**：`_showBidSheet` 和 `_showBidSheet_render` 合为一个函数
