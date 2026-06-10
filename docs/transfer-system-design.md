# 转会系统设计文档

> 严格基于代码生成，版本对应 `scripts/systems/transfer_manager.lua` (3408行)

---

## 1. 架构概览

### 1.1 文件结构

```
scripts/
├── systems/
│   ├── transfer_manager.lua              # 主模块 (3408行, 70+ public / 34+ private 函数)
│   └── transfers/
│       └── transfer_completion.lua       # 注入模块: 转会完成相关 helper (6个函数)
├── core/
│   ├── game_state.lua                    # 数据层: transfers 数据结构定义
│   └── turn_processor.lua               # 调度层: 每日/每周/每月调用入口
└── ui/screens/
    ├── market.lua                        # UI: 转会市场主界面
    ├── squad.lua                         # UI: 阵容页(挂牌/接受报价)
    ├── player_detail.lua                 # UI: 球员详情页(接受/拒绝报价)
    └── scouting.lua                      # UI: 球探界面
```

### 1.2 依赖关系

```
TransferManager
  ├── require EventBus           (事件广播)
  ├── require FinanceManager     (转会费入账/出账)
  ├── inject transfer_completion (6个helper函数)
  ├── pcall require HistoryManager (历史记录，可选)
  └── 被调用方:
      ├── turn_processor.lua     (每日/每周/每月调度)
      ├── market.lua             (玩家UI操作)
      ├── squad.lua              (挂牌/报价处理)
      ├── player_detail.lua      (报价操作)
      └── scouting.lua           (球探发现→报价)
```

### 1.3 注入模式 (transfer_completion.lua)

```lua
-- 模块导出一个函数，接收 TransferManager 表，向其注入方法
return function(TransferManager)
    function TransferManager._getBidEffectiveValue(bid, player) ... end
    function TransferManager._requirePlayerConsentForTransfer(gameState, bid) ... end
    function TransferManager._removePlayerFromTeam(team, playerId) ... end
    function TransferManager._addTransferTransaction(team, amount, description, date) ... end
    function TransferManager._settleTransferFee(gameState, buyerTeam, sellerTeam, bid, player) ... end
    function TransferManager._attachFutureClauses(player, bid) ... end
end
```

---

## 2. 数据结构

### 2.1 GameState.transfers (game_state.lua)

```lua
self.transfers = {
    bids = {},           -- 所有活跃/历史报价 (bid对象数组)
    history = {},        -- 完成的转会记录
    nextBidId = 1,       -- 自增ID
    freeAgentNegos = {}, -- 自由球员谈判 (nego对象数组)
}
self.scoutReports = {}       -- 球探报告
self.scoutDiscoveries = {}   -- 球探发现的球员
self.shortlist = {}          -- 候选名单 {playerId = true}
self._activeLoans = {}       -- 活跃租借记录
```

### 2.2 Bid 对象结构 (普通买入)

```lua
bid = {
    id = number,                    -- 唯一ID (自增)
    playerId = number,              -- 目标球员ID
    buyerTeamId = number,           -- 买方球队ID
    sellerTeamId = number,          -- 卖方球队ID
    amount = number,                -- 当前报价金额
    playerValue = number,           -- 报价时球员身价快照
    status = string,                -- 状态机状态 (见§3)
    date = {year, month, day},      -- 创建日期
    responseDate = {year,month,day},-- AI最后响应日期
    wageOffer = number,             -- 周薪报价
    contractYears = number,         -- 合同年限

    -- 多轮谈判字段
    counterAmount = number|nil,     -- AI的还价金额
    currentRound = number,          -- 当前谈判回合 (0-based)
    maxRounds = number,             -- 耐心上限 (3-5, 随机生成)
    mood = number,                  -- AI心情 (0-100, 50=中立)
    rounds = {},                    -- 历史: {round, offer, counter, result}

    -- 买入流程扩展字段
    feeAgreedDate = {y,m,d}|nil,        -- 转会费达成日期
    playerConsiderDate = {y,m,d}|nil,    -- 球员考虑开始日期
    playerConsiderDays = number|nil,     -- 球员考虑天数 (1-3)
    personalTermsAttempts = number,      -- 个人条款协商次数 (最多3次)

    -- 条款相关
    installments = {}|nil,          -- 分期付款条款
    sellOnPercent = number|nil,     -- 转售分成百分比
    appearanceBonus = {}|nil,       -- 出场奖金条款
}
```

### 2.3 Bid 对象结构 (收到的卖出报价 / incoming)

```lua
bid = {
    -- ...同上基础字段...
    isIncomingBid = true,           -- 标记为收到的报价

    -- 还价延迟字段 (counter_pending状态)
    counterAskAmount = number|nil,  -- 玩家要价金额
    counterDate = {y,m,d}|nil,      -- 还价发出日期
    counterWaitDays = number|nil,   -- AI考虑天数 (1-3)

    -- 出售确认字段 (awaiting_sale_confirmation状态)
    saleConfirmDate = {y,m,d}|nil,  -- 进入确认状态日期
}
```

### 2.4 Bid 对象结构 (推销 / push sale)

```lua
bid = {
    -- ...同上基础字段...
    isPushSale = true,              -- 标记为主动推销
    isIncomingBid = false,
    mood = 40,                      -- 初始态度较保守
}
```

### 2.5 Bid 对象结构 (租借)

```lua
bid = {
    -- ...同上基础字段...
    type = "loan",
    loanDuration = number,          -- 周数 (默认26)
    wageShare = 0.5,                -- 租借方承担工资比例
}
```

### 2.6 FreeAgentNego 对象结构

```lua
nego = {
    id = number,
    playerId = number,
    teamId = number,                -- 发起球队ID
    status = string,                -- pending/negotiating/awaiting_confirmation/accepted/rejected/cancelled
    wageOffer = number,             -- 当前周薪报价
    yearsOffer = number,            -- 当前合同年限报价

    -- 球员期望
    expectedWage = number,
    expectedYears = number,

    -- AI谈判
    counterWage = number|nil,
    counterYears = number|nil,
    currentRound = number,
    maxRounds = number,             -- 2-4, 随机
    mood = number,                  -- 0-100
    rounds = {},

    date = {y,m,d},
    responseDate = {y,m,d}|nil,
    confirmDate = {y,m,d}|nil,      -- 进入awaiting_confirmation日期
    rejectedDate = {y,m,d}|nil,

    -- 预签约扩展
    isPreContract = boolean|nil,
    effectiveDate = {year, month}|nil,  -- 合同到期生效日期
}
```

### 2.7 ActiveLoan 对象结构

```lua
loan = {
    playerId = number,
    playerName = string,
    originTeamId = number,          -- 原属球队
    loanTeamId = number,            -- 租借球队
    remainingDays = number,         -- 剩余天数 (整数, 避免浮点)
    wageShare = number,             -- 工资分担比例
}
```

---

## 3. 状态机

### 3.1 买入报价状态机 (玩家作为买方)

```
                         ┌──────────────────────────────────────────┐
                         │          makeBid() 创建                   │
                         ▼                                          │
                    ┌─────────┐                                     │
                    │ pending  │ ← raiseBid() 加价后重回             │
                    └────┬────┘                                     │
                         │ (1-3天后 processDailyBids 调用)           │
                         ▼                                          │
              ┌────────────────────┐                                │
              │ _processAIResponse │                                │
              └──────┬─────────────┘                                │
          ┌──────────┼──────────────┐                               │
          ▼          ▼              ▼                               │
    ┌──────────┐ ┌──────────────┐ ┌──────────┐                     │
    │ rejected │ │ negotiating  │ │_acceptBid│                     │
    └──────────┘ └──────┬───────┘ └────┬─────┘                     │
                        │              ▼                            │
                        │    ┌───────────────────┐                  │
                        │    │player_considering  │ (1-3天)          │
                        │    └────────┬──────────┘                  │
                        │             ▼                             │
                        │    ┌──────────────┐                       │
                        │    │  fee_agreed   │ ← personalTerms被拒   │
                        │    └──────┬───────┘   可重试(最多3次)      │
                        │           ▼                               │
                        │  ┌─────────────────────────┐              │
                        │  │ awaiting_confirmation    │              │
                        │  └────────┬───────┬────────┘              │
                        │           │       │                       │
                        │    confirmTransfer  cancelTransferConfirmation
                        │           │       │                       │
                        │           ▼       ▼                       │
                        │    ┌───────────┐ ┌──────────┐             │
                        │    │ completed  │ │cancelled │             │
                        │    └───────────┘ └──────────┘             │
                        │                                           │
                        └── (玩家5天未回应 → rejected)                │
                            (轮次用尽 → rejected)                    │
                            (raiseBid → 回到 pending) ──────────────┘
```

**状态说明:**

| 状态 | 含义 | 超时规则 |
|------|------|---------|
| `pending` | 等待卖方AI回复 | 1-3天后AI回应 |
| `negotiating` | AI还价中，等待玩家加价 | 5天未操作→rejected |
| `player_considering` | 转会费已达成，球员考虑中 | 1-3天后自动进入fee_agreed |
| `fee_agreed` | 转会费达成，个人条款协商中 | 7天超时→rejected |
| `awaiting_confirmation` | 个人条款达成，等待玩家确认 | 12天超时→rejected |
| `completed` | 转会完成 | - |
| `rejected` | 被拒绝 | 触发7天冷却期 |
| `cancelled` | 玩家取消 | - |

### 3.2 卖出报价状态机 (玩家作为卖方, isIncomingBid=true)

```
         AI发起 _createIncomingBid()
                    │
                    ▼
              ┌──────────┐
              │  pending  │
              └─────┬─────┘
       ┌────────────┼─────────────┐
       ▼            ▼             ▼
 acceptIncomingBid  counterIncomingBid  rejectIncomingBid
       │            │                   │
       │            ▼                   ▼
       │    ┌────────────────┐    ┌──────────┐
       │    │counter_pending │    │ rejected │
       │    └───────┬────────┘    └──────────┘
       │            │ (1-3天后 _processCounterResponse)
       │     ┌──────┴──────┐
       │     ▼             ▼
       │  接受还价       拒绝还价
       │     │             │
       ▼     ▼             ▼
  ┌────────────────────────────┐   ┌──────────┐
  │ awaiting_sale_confirmation │   │ rejected │
  └──────────┬──────┬──────────┘   └──────────┘
             │      │
       confirmSale  cancelSale
             │      │
             ▼      ▼
       ┌──────────┐ ┌──────────┐
       │completed │ │ rejected │
       └──────────┘ └──────────┘

   (awaiting_sale_confirmation 5天超时 → rejected)
```

**状态说明:**

| 状态 | 含义 | 超时规则 |
|------|------|---------|
| `pending` | AI发起报价，等待玩家决策 | 无超时(等玩家操作) |
| `counter_pending` | 玩家还价已发出，AI考虑中 | 1-3天后AI回复 |
| `awaiting_sale_confirmation` | 价格达成，等待玩家最终确认 | 5天超时→rejected |
| `completed` | 出售完成 | - |
| `rejected` | 被拒绝/超时 | - |

### 3.3 推销报价状态机 (isPushSale=true)

```
       offerToClub() 创建
              │
              ▼
        ┌──────────┐
        │  pending  │
        └─────┬─────┘
              │ (1-3天后 _processPushSaleResponse)
     ┌────────┼────────┐
     ▼        ▼        ▼
  直接接受  还价     没兴趣
     │        │        │
     ▼        ▼        ▼
  _acceptPushSale  ┌────────────┐  ┌──────────┐
     │             │negotiating │  │ rejected │
     │             └──────┬─────┘  └──────────┘
     │          ┌─────────┴─────────┐
     │          ▼                   ▼
     │   acceptPushSaleCounter  rejectPushSaleCounter
     │          │                   │
     ▼          ▼                   ▼
  ┌──────────┐                  ┌──────────┐
  │completed │                  │cancelled │
  └──────────┘                  └──────────┘
```

### 3.4 自由球员谈判状态机

```
       offerFreeAgent() / offerPreContract()
                    │
                    ▼
              ┌──────────┐
              │  pending  │ ← reviseOffer() 修改后重回
              └─────┬─────┘
                    │ (1-2天后 _processFreeAgentResponse)
         ┌──────────┼──────────────┐
         ▼          ▼              ▼
    直接接受     还价           直接拒绝
         │          │              │
         ▼          ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌──────────┐
   │  (见下方)  │ │negotiating │ │ rejected │
   └────────────┘ └──────┬─────┘ └──────────┘
                         │   (4天未回复 → rejected)
                         │   (reviseOffer → pending)
                         ▼
              ┌─────────────────────────┐
              │ awaiting_confirmation   │  (玩家球队)
              └──────┬──────┬───────────┘
                     │      │
          confirmFreeAgent  cancelFreeAgentConfirmation
                     │      │
                     ▼      ▼
              ┌──────────┐ ┌──────────┐
              │ accepted  │ │cancelled │
              └──────────┘ └──────────┘

   (awaiting_confirmation 5天超时 → rejected)
   
   预签约(isPreContract=true)接受后:
     → status="accepted", player.preContractLockedBy=teamId
     → 由 processPreContracts() 在合同到期月份执行转移
```

### 3.5 租借状态机

```
       makeLoanBid()
            │
            ▼
      ┌──────────┐
      │  pending  │
      └─────┬─────┘
            │ (1-3天后 _processLoanBidResponse)
     ┌──────┴──────┐
     ▼             ▼
  _completeLoan  _rejectBid
     │             │
     ▼             ▼
  ┌──────────┐  ┌──────────┐
  │completed │  │ rejected │
  └──────────┘  └──────────┘
  
  到期后: processLoanExpiry() → _returnLoanPlayer()
```

---

## 4. 核心算法

### 4.1 AI报价回应 (_processAIResponse)

**接受阈值计算:**
```
acceptThreshold = 1.3 - (mood / 200) - round * 0.05 + ageFactor
ageFactor = (26 - age) * 0.02   (限制在 [-0.15, +0.15])
```

**决策逻辑:**
- `ratio >= max(acceptThreshold, 0.9)` → 接受 (→ player_considering)
- `ratio >= 0.6` → 还价 (→ negotiating)
- `ratio < 0.6` → 直接拒绝 (mood -15)

**还价金额计算:**
```
baseMultiplier = 1.35 - round * 0.07 - (mood - 50) / 200 + ageFactor ± random(0.05)
counter = floor(player.value * baseMultiplier / 1000) * 1000
```

### 4.2 卖出还价回应 (_processCounterResponse)

**接受概率 (基于 askAmount / playerValue):**

| ratio | acceptChance |
|-------|-------------|
| <= 1.0 | 90% |
| <= 1.1 | 70% |
| <= 1.2 | 50% |
| <= 1.3 | 30% |
| > 1.3 | 10% |

### 4.3 玩家心情(mood)影响

- 初始值: 50 (中立), 推销bid: 40
- 加价时: `improvement = (newAmount - counterAmount) / playerValue * 40 + 5`
- 影响AI接受阈值: mood=100时阈值降0.5, mood=0时不降
- 5天未回应: mood -20
- 直接低价报价被拒: mood -15

### 4.4 球员同意检查 (_requirePlayerConsentForTransfer)

```
1. 检查转会态度: attitude == "refusing" → 拒绝
2. 检查加盟意愿: _checkPlayerWillingness() → 俱乐部实力/声望等
3. 薪资满意度:
   - wageRatio < 0.8 → 85%概率拒绝
   - wageRatio < 0.95 → 30%概率拒绝
   - wageRatio >= 0.95 → 通过
```

### 4.5 AI间转会 (processAITransfers 中的 _attemptAITransfer)

**接受概率:**

| ratio (offer/value) | baseChance |
|---------------------|-----------|
| >= 1.3 | 95% |
| >= 1.1 | 80% |
| >= 1.0 | 60% |
| >= 0.85 | 35% |
| < 0.85 | 15% |

**修正因素:**
- 挂牌出售: +35%
- overall >= 80 且未挂牌: ×0.6
- overall >= 75 且未挂牌: ×0.75
- 卖方阵容 > 25人: +20%

**AI新工资计算:**
```
marketWage = max(player.wage, floor(player.value / 260))
newWage = floor(marketWage * (0.95 + random * 0.15))  -- 市场价 ±
newWage = max(player.wage, newWage)  -- 不低于原工资
```

---

## 5. 调度系统 (turn_processor.lua)

### 5.1 每日调用 (processDay)

| 调用 | 方法 | 说明 |
|------|------|------|
| 每天 | `processDailyBids()` | 处理所有bid状态推进 |
| 每天 | `processDailyFreeAgentNegos()` | 自由球员谈判状态推进 |
| 每天 | `processLoanExpiry()` | 租借到期检查/返还 |
| 每天 | `processPreContracts()` | 预签约到期生效 |
| 周四(窗口期) | `processAITransfers()` | AI球队间交易(额外增加流动性) |

### 5.2 每周调用 (周一)

| 调用 | 方法 | 说明 |
|------|------|------|
| 周一 | `processScoutReport()` | 球探发现球员 |
| 周一 | `processAITransfers()` | AI球队间常规交易 |

### 5.3 每月调用 (1号)

| 调用 | 方法 | 说明 |
|------|------|------|
| 每月1号 | `processInstallments()` | 分期付款到期处理 |

### 5.4 processDailyBids 内部处理顺序

```
1. pending bids:
   ├── isPushSale=true → _processPushSaleResponse (1-3天延迟)
   └── 普通bid:
       ├── 检查解约金 → _acceptBid
       ├── type="loan" → _processLoanBidResponse
       └── 其他 → _processAIResponse (1-3天延迟)
       
2. negotiating bids: 5天未回应 → rejected

3. player_considering: 考虑期结束 → fee_agreed + _attemptPersonalTerms

4. fee_agreed: 7天超时 → rejected

5. awaiting_confirmation: 12天超时 → rejected

6. counter_pending (isIncomingBid): AI延迟回复 → _processCounterResponse

7. awaiting_sale_confirmation (isIncomingBid): 5天超时 → rejected

8. processCompetitiveBids() (竞争性报价处理)
```

---

## 6. 子系统详解

### 6.1 买入系统 (玩家买入其他球队球员)

**公开API:**
- `makeBid(gameState, playerId, amount, wageOffer)` — 发起报价
- `raiseBid(gameState, bidId, newAmount, newWage)` — 加价
- `negotiatePersonalTerms(gameState, bidId, newWageOffer)` — 修改工资重试个人条款
- `confirmTransfer(gameState, bidId)` — 确认签入
- `cancelTransferConfirmation(gameState, bidId)` — 放弃签约
- `cancelBid(gameState, bidId)` — 取消报价

**前置检查:**
1. 转会窗口 (6-8月/1月)
2. 拒绝冷却期 (7天)
3. 预签约锁定
4. 球员存在性 + 非自由球员

### 6.2 卖出系统 (AI买玩家球员)

**公开API:**
- `acceptIncomingBid(gameState, bidId)` — 同意报价 → awaiting_sale_confirmation
- `rejectIncomingBid(gameState, bidId)` — 拒绝报价
- `counterIncomingBid(gameState, bidId, askAmount)` — 还价 → counter_pending
- `confirmSale(gameState, bidId)` — 确认出售
- `cancelSale(gameState, bidId)` — 取消出售

**触发机制:**
- AI通过 `processAITransfers` 寻找挂牌球员 → `_findBuyerForPlayer` → `_createIncomingBid`
- 生成报价金额: `player.value * (0.7 ~ 1.2)`

### 6.3 推销系统 (玩家主动向AI推销)

**公开API:**
- `offerToClub(gameState, playerId, targetTeamId, askingPrice)` — 发起推销
- `acceptPushSaleCounter(gameState, bidId)` — 接受AI还价
- `rejectPushSaleCounter(gameState, bidId)` — 拒绝AI还价

**前置检查:**
- 转会窗口 + 冷却期 + 只能推销自己球员
- 球员意愿检查 (`_checkPlayerWillingness`)
- 目标球队预算检查 (askingPrice <= budget * 0.6)
- 敌对关系检查 (`_isRivalry`)

### 6.4 租借系统

**公开API:**
- `makeLoanBid(gameState, playerId, duration)` — 发起租借请求
- `processLoanExpiry(gameState)` — 每日检查到期 (turn_processor调用)
- `getActiveLoans(gameState)` — 获取活跃租借列表

**费用计算:** `loanFee = player.wage × duration(周) × 0.5`

**生命周期:**
1. 创建租借bid → pending
2. AI审批 (接受率基于: 挂牌/角色/费用合理性)
3. 通过 → _completeLoan (球员标记squadRole="loaned", 加入买方阵容)
4. 每日计时 remainingDays - 1
5. 到期 → _returnLoanPlayer (回到原球队)

### 6.5 自由球员签约系统

**公开API:**
- `offerFreeAgent(gameState, playerId, wageOffer, yearsOffer)` — 发起谈判
- `reviseOffer(gameState, negoId, newWage, newYears)` — 修改条件(加薪/改年限)
- `cancelFreeAgentNego(gameState, negoId)` — 取消谈判
- `confirmFreeAgent(gameState, negoId)` — 确认签入
- `cancelFreeAgentConfirmation(gameState, negoId)` — 放弃签约
- `getFreeAgents(gameState, positionFilter)` — 获取自由球员列表
- `signFreeAgent(gameState, playerId, wage, years)` — 旧接口/直接签约(兼容)

**AI回应逻辑 (_processFreeAgentResponse):**
```
wageThreshold = 1.0 - (mood / 300) - round * 0.03  (最低0.7)
if wageRatio >= wageThreshold and yearsOk → 接受
if wageRatio >= 0.5 → 还价 (counter wage = expectedWage * multiplier)
else → 直接拒绝
```

### 6.6 预签约系统

**公开API:**
- `canPreContract(gameState, playerId)` — 检查是否可预签约 (合同≤6月)
- `offerPreContract(gameState, playerId, wageOffer, yearsOffer)` — 发起预签约

**特殊处理:**
- 复用自由球员谈判状态机 (freeAgentNegos数组)
- `isPreContract = true` 标记
- 接受后不立即转移，设 `player.preContractLockedBy = teamId`
- `processPreContracts()` 每日检查: 当日期 >= effectiveDate → 执行球员转移

### 6.7 球探系统

**公开API:**
- `processScoutReport(gameState)` — 每周执行球探发现
- `getScoutNetwork(gameState)` — 获取球探网络配置
- `addScoutRegion(gameState, region)` — 添加覆盖地区
- `removeScoutRegion(gameState, region)` — 移除覆盖地区

**球探网络:**
```lua
scoutNetwork = {
    regions = {},     -- 已覆盖地区列表
    maxRegions = 3,   -- 最大覆盖数
}
```

---

## 7. 金融处理

### 7.1 转会费结算 (_settleTransferFee)

**支持两种模式:**
1. **分期付款** (installments存在): 首期立即结算，后续记入 `_pendingPayables` / `_pendingReceivables`
2. **一次性付清** (默认): 全额从买方扣除，全额给卖方

**影响字段:**
- 买方: `balance -= amount`, `seasonExpense += amount`, `transferBudget -= amount`
- 卖方: `balance += amount`, `transferBudget += amount`, `seasonIncome += amount`
- 通过 `FinanceManager.processTransferIn/Out` 处理 (AI间交易)

### 7.2 附加条款 (_attachFutureClauses)

- **转售分成 (sellOnPercent)**: 写入 `player._sellOnClause`
- **出场奖金 (appearanceBonus)**: 写入 `player._appearanceBonusClause`

---

## 8. 约束与规则

### 8.1 转会窗口

```lua
-- 夏窗: 6月、7月、8月
-- 冬窗: 1月
function isInTransferWindow(gameState)
    local month = gameState.date.month
    return (month >= 6 and month <= 8) or month == 1
end
```

仅影响**俱乐部间交易**入口 (makeBid, makeLoanBid, offerToClub)。
自由球员签约、预签约不受窗口限制。

### 8.2 拒绝冷却期

```lua
REJECTION_COOLDOWN_DAYS = 7
```

检查范围: bids中status="rejected"的记录 + freeAgentNegos中status="rejected"的记录。

### 8.3 合同年限计算 (_calcExpectedYears)

| 年龄 | 期望年限 |
|------|---------|
| >= 33 | 1年 |
| >= 30 | 2年 |
| >= 27 | 3年 |
| < 27 | 2年 |

### 8.4 有效价值计算 (_getBidEffectiveValue)

```
effectiveValue = bid.amount
    + appearanceBonus.amount * 0.35
    + player.value * sellOnPercent / 100 * 0.25
```

---

## 9. 事件与消息

### 9.1 EventBus 事件

| 事件名 | 触发时机 | 数据 |
|--------|---------|------|
| `transfer_completed` | `_completeTransfer` / `confirmFreeAgent` | bid对象 或 {playerId, teamId, type} |

### 9.2 消息类别 (category="transfer")

| title 关键词 | 触发场景 |
|-------------|---------|
| "报价已提交" | makeBid 创建 |
| "加价报价已提交" | raiseBid |
| "转会还价" | AI还价 (negotiating) |
| "转会费已达成" | _acceptBid |
| "球员同意加盟!" | 个人条款通过 (awaiting_confirmation) |
| "个人条款被拒" | 协商失败但可重试 |
| "报价被拒绝" | _rejectBid |
| "转会完成!" | _completeTransfer |
| "收到报价" | _createIncomingBid |
| "待确认出售" | acceptIncomingBid |
| "还价已发出" | counterIncomingBid |
| "还价被接受/拒绝" | _processCounterResponse |
| "出售已取消" | cancelSale |
| "报价已过期" | 5天超时 |
| "推销报价已发出" | offerToClub |
| "推销还价" | AI还价推销 |
| "推销被拒" | AI没兴趣 |
| "租借请求已提交" | makeLoanBid |
| "租借完成!" | _completeLoan |
| "租借到期" / "球员归队" | _returnLoanPlayer |
| "合同谈判已发起" | offerFreeAgent |
| "合同还价" | AI还价工资/年限 |
| "球员同意签约!" | 自由球员awaiting_confirmation |
| "自由签约完成!" | confirmFreeAgent |
| "预签约谈判发起" | offerPreContract |
| "预签约达成!" | 预签约accepted |
| "预签约生效!" | processPreContracts 执行转移 |

---

## 10. 查询API

| 方法 | 返回 | 说明 |
|------|------|------|
| `getBidById(gs, bidId)` | bid\|nil | 按ID查找bid |
| `hasPendingBid(gs, playerId)` | bool | 是否有活跃买入报价 |
| `hasPendingIncomingBid(gs, playerId)` | bool | 是否有活跃卖出报价 |
| `getPlayerBids(gs)` | bid[] | 玩家发出的所有报价(倒序) |
| `getPendingSellBids(gs)` | bid[] | 待处理的卖出报价(pending/counter_pending/awaiting_sale_confirmation) |
| `getActiveBids(gs)` | bid[] | 所有活跃报价(pending/negotiating/counter_pending/awaiting_sale_confirmation) |
| `getFreeAgentNegos(gs)` | nego[] | 玩家的自由球员谈判列表 |
| `getFreeAgentNegoById(gs, negoId)` | nego\|nil | 按ID查找谈判 |
| `hasPendingFreeAgentNego(gs, playerId)` | bool | 是否有活跃自由球员谈判 |
| `getActiveLoans(gs)` | loan[] | 活跃租借列表 |
| `isInTransferWindow(gs)` | bool | 是否在转会窗口 |
| `canPreContract(gs, playerId)` | bool | 是否可预签约 |
| `checkWageBudget(gs, teamId, wage)` | bool, reason | 工资预算检查 |

---

## 11. 挂牌系统

```lua
TransferManager.listForSale(gameState, player)   -- 挂牌出售
TransferManager.delistPlayer(player)              -- 取消挂牌
```

挂牌后:
- `player.listedForSale = true`
- AI通过 `processAITransfers` → `_findBuyerForPlayer` 寻找买家
- 挂牌球员在AI接受概率中 +35%

---

## 12. 竞争性报价处理

`processCompetitiveBids(gameState)` — 在 processDailyBids 末尾调用，处理同一球员有多个bid时的竞争逻辑。

---

## 13. UI 交互入口 (market.lua)

### 13.1 卖出报价展示 (_showOfferSheet)

基于 `bid.status` 显示不同UI:

| 状态 | 显示内容 | 可用操作 |
|------|---------|---------|
| `pending` | 报价金额 + 球员身价对比 | 接受 / 还价 / 拒绝 |
| `counter_pending` | "等待回复中" + 要价金额 | 无操作(等待) |
| `awaiting_sale_confirmation` | 最终金额 + 确认提示 | 确认出售 / 取消 |

### 13.2 挂牌球员卡片状态标识

| 状态 | 颜色 | 按钮文字 |
|------|------|---------|
| `counter_pending` | 黄色/warning | "等待回复" |
| `awaiting_sale_confirmation` | 绿色/secondary | "待确认" |
| `pending` | 默认 | "查看报价" |
