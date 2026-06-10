# 收支模型分析报告

## 一、收支全景图

### 收入来源

| # | 收入类型 | 触发频率 | 入口函数 | 是否计入 seasonIncome | 是否计入 incomeBreakdown |
|---|---------|---------|---------|:---:|:---:|
| 1 | 赞助收入 | 每月1号 | `FinanceManager.processMonthlySponsorship` | ✅ | ✅ sponsor |
| 2 | 转播分成 | 每月1号 | `FinanceManager.processMonthlyBroadcast` | ✅ | ✅ broadcast |
| 3 | 商品销售 | 每月1号 | `FinanceManager.processMonthlyMerchandise` | ✅ | ✅ merchandise |
| 4 | 比赛日票房 | 比赛日(主场) | `FinanceManager.processMatchDayRevenue` | ✅ | ✅ ticket |
| 5 | 赛季排名奖金 | 赛季结束 | `FinanceManager.awardSeasonPrize` | ✅ | ✅ prize |
| 6 | 转会卖人收入 | 事件触发 | `FinanceManager.processTransferIn` | ✅ | ✅ transfer |
| 7 | 租借费收入 | 事件触发 | `TransferManager._completeLoan` | ✅ | ❌ 未分类 |
| 8 | 分期收款 | 每月1号 | `TransferManager.processInstallments` | ✅ | ❌ 未分类 |
| 9 | 董事注资 | 主动触发 | `FinanceManager.requestBoardInjection` | ✅ | ❌ 未分类 |
| 10 | 赞助推介 | 主动触发 | `FinanceManager.seekSponsorship` | ✅ | ❌ 未分类 |
| 11 | 商业活动 | 主动触发(28天CD) | `FinanceManager.hostCommercialEvent` | ✅ | ❌ 未分类 |
| **12** | **联赛冠军奖金** | **赛季结束** | **`SeasonManager._distributeSeasonPrizes`** | **❌ BUG** | **❌ BUG** |
| **13** | **欧冠冠军奖金(5M)** | **赛季结束** | **`ChampionsLeague` line 622** | **❌ BUG** | **❌ BUG** |
| **14** | **欧冠亚军奖金(3M)** | **赛季结束** | **`ChampionsLeague` line 655** | **❌ BUG** | **❌ BUG** |
| **15** | **赞助合同-前3名奖金** | **从未触发** | **无实现** | **❌ 缺失** | **❌ 缺失** |

### 支出来源

| # | 支出类型 | 触发频率 | 入口函数 | 是否计入 seasonExpense |
|---|---------|---------|---------|:---:|
| 1 | 周薪(球员+职员) | 每周一 | `FinanceManager.processWeeklyWages` | ✅ |
| 2 | 设施+球场维护 | 每月1号 | `FinanceManager.processMonthlyMaintenance` | ✅ |
| 3 | 转会买人支出 | 事件触发 | `FinanceManager.processTransferOut` | ✅ |
| 4 | 租借费支出 | 事件触发 | `TransferManager._completeLoan` | ✅ |
| 5 | 分期付款 | 每月1号 | `TransferManager.processInstallments` | ✅ |
| 6 | 球场扩建 | 主动触发 | `FinanceManager.expandStadium` | ✅ |
| 7 | 设施升级 | 主动触发 | `FinanceManager.upgradeFacility` | ✅ |
| **8** | **赞助合同-降级罚款** | **从未触发** | **无实现** | **❌ 缺失** |

---

## 二、发现的问题

### BUG 1：联赛冠军额外奖金 20M 未纳入收入统计 🔴 严重

**位置**: `season_manager.lua:146-148`

```lua
local championBonus = 20000000
team.balance = team.balance + championBonus  -- ✅ 余额增加了
-- ❌ 缺少以下：
-- team.seasonIncome 未更新
-- team.incomeBreakdown.prize 未更新
-- team.transferBudget 未更新
```

**影响**: 
- 玩家夺冠后余额确实增加 20M，但月度财报不会体现这笔收入
- 转会预算不会增加（奖金无法用于转会市场）
- 而普通的排名奖金（通过 `FinanceManager.awardSeasonPrize` 处理）会正确更新所有字段

**严重度**: 高 — 20M 是一笔巨额收入（排名第1的基础奖金 80M + 这额外的 20M），缺失统计影响财务决策。

---

### BUG 2：欧冠奖金未纳入收入统计 🔴 严重

**位置**: `champions_league.lua:622, 655`

```lua
-- 冠军 5M
champion.balance = champion.balance + prize
-- ❌ 缺少 seasonIncome/incomeBreakdown/transferBudget 更新

-- 亚军 3M
finalist.balance = finalist.balance + runnerUpPrize
-- ❌ 同上
```

**影响**: 同 BUG 1，金额虽小但财务统计不完整。

---

### BUG 3：赞助合同的绩效条款从未兑现 🟡 功能缺失

**位置**: `finance_manager.lua:200-212` (定义), 全局搜索无触发逻辑

赞助合同中定义了两个条款：
- `topFinishBonus`: 前3名额外奖金（激进型可达数百万）
- `relegationPenalty`: 降级时的罚款（激进型可达数百万）

这些数据在赞助选择 UI 中展示给玩家参考，但**赛季结算时从未检查和执行**。

**影响**: 
- 玩家选择"激进型"赞助合同（低月付+高奖金）永远不会收到绩效奖金
- 玩家降级也不会被扣罚款
- 这实际上让"稳定型"变成了唯一正确选择

---

### BUG 4：欧冠奖金金额不合理 🟡 平衡性

- 欧冠冠军奖金: **5M** 
- 联赛第 20 名奖金: **3M**
- 联赛第 1 名奖金: **80M**

现实中欧冠冠军总收入（转播+奖金）约 100-130M 欧元，远高于联赛末名的分成。当前 5M 的设定让欧冠几乎没有经济激励。

---

### 潜在问题 5：月度维护费与收入计时不对称

**月度收入**（赞助/转播/商品）在 `day == 1` 时处理，但：
- 工资是每周扣的（~4.3次/月）
- 比赛票房在比赛日发生（不定期）

这不是 BUG，但可能导致月初余额突然跳涨（3项收入同时到账），视觉上给玩家"忽然有钱"的错觉。

---

## 三、数值模型估算（rep=700 的中上游球队，赛季10个月）

### 月度收入（以 reputation=700 / rep归一化=70 为例）

| 收入项 | 公式简述 | 估算月收入 |
|--------|---------|-----------|
| 赞助 | `rep*15000 + capacity/30000*500000 + posBonus` | ~1.8M - 3.0M |
| 转播 | `(rep*26000 + 200000) * shareRatio` × 排名 | ~2.5M - 3.5M |
| 商品 | `(rep*8000 + 100000) * starBonus` | ~0.8M - 1.5M |
| **月度小计** | | **~5.1M - 8.0M** |
| **赛季月度总计（×10月）** | | **~51M - 80M** |

### 比赛日收入（主场约 19 场/赛季，20队联赛）

| 参数 | 估算 |
|------|------|
| 球场容量 | 40,000 |
| 上座率 | ~78% = 31,200人 |
| 票价 | ~27-40（取决于对手） |
| 单场收入 | ~1.0M - 1.2M |
| **赛季票房总计（×19主场）** | **~19M - 23M** |

### 支出（赛季总计）

| 支出项 | 公式 | 估算赛季支出 |
|--------|------|-------------|
| 周薪 | `所有球员+职员工资 × 约44周` | 若均薪 20K/人 × 20人 × 44周 = **17.6M** |
| 月度维护 | `设施费 + 容量×10` × 10月 | (0 + 400K) × 10 = **4.0M** |
| **赛季支出总计** | | **~21.6M** |

### 赛季总收支

| 项目 | 金额 |
|------|------|
| 月度收入合计 | ~51M - 80M |
| 票房收入合计 | ~19M - 23M |
| 赛季排名奖金（第5名） | 38M |
| **总收入** | **~108M - 141M** |
| 总支出 | ~21.6M |
| **净利润** | **~86M - 119M** |

### 结论：收入远大于支出，经济膨胀严重

当前模型中，中上游球队一个赛季净赚 **80-120M**，这意味着：
- 2-3个赛季后余额可达数亿
- 转会预算（新赛季重算时 balance × 25% × repFactor）会持续膨胀
- 玩家很快失去财务压力

---

## 四、修复建议优先级

| 优先级 | 问题 | 修复方案 |
|--------|------|---------|
| P0 | 赞助绩效条款未兑现 | 在 `SeasonManager.endSeason` 中添加赞助合同结算逻辑 |
| P0 | 联赛冠军奖金未计入统计 | 改用 `FinanceManager.awardSeasonPrize` 统一入口，或手动补充 seasonIncome/transferBudget |
| P1 | 欧冠奖金未计入统计 | 同上，使用 FinanceManager 统一记账 |
| P1 | 欧冠奖金数值太低 | 提高至 30-50M（冠军）/ 15-25M（亚军），匹配联赛奖金量级 |
| P2 | 整体收支失衡 | 增加支出（球员薪资膨胀、设施维护递增）或降低月度收入系数 |
| P2 | 租借/注资/商业活动收入未归入 breakdown | 补充 `incomeBreakdown` 分类 |

---

## 五、赛季结算时序（当前实现）

```
endSeason()
  ├── 1. ObjectivesManager.onSeasonEnd       # 赛季目标评估
  ├── 2. BoardManager.seasonEndEvaluation    # 董事会评估
  ├── 3. _distributeSeasonPrizes             # 联赛奖金（含冠军20M BUG）
  ├── 4. _processPromotionRelegation         # 升降级
  ├── 5. AwardsManager.processSeasonAwards   # 奖项
  ├── 6. _processPlayerDevelopment           # 球员成长
  ├── 7. _recalculateTraits                  # 特性重算
  ├── 8. _processContractExpiry              # 合同到期
  ├── 9. _processRetirements                 # 退役
  ├── 10. _recordPlayerCareerHistory         # 职业历史
  ├── 11. RecordsManager.onSeasonEnd         # 纪录检查
  ├── 12. _resetSeasonStats                  # 重置赛季数据统计
  ├── 13. FinanceManager.resetSeasonFinance  # ⚠️ 清零 seasonIncome/seasonExpense
  ├── 14. HistoryManager.recordSeasonEnd     # 记录历史（此时财务已清零）
  └── 15. _recordSeasonHistory               # 旧格式历史
  
  _startNewSeason()
  ├── 更新赛季年份/日期
  ├── 联赛初始化赛程
  ├── 清理转会/球探数据
  ├── ⭐ _allocateSeasonBudgets              # 重新分配预算（新增修复）
  ├── _fillAISquads                          # 补充AI阵容
  ├── ChampionsLeague.initialize             # 初始化欧冠
  ├── ObjectivesManager.initSeason           # 目标初始化
  ├── BoardManager.generateSeasonObjectives  # 董事会目标
  └── FinanceManager.generateSponsorOffers   # 生成赞助选项
```

**注意**: 步骤 13-14 的顺序意味着 `HistoryManager.recordSeasonEnd` 无法记录到赛季财务数据（已被清零）。当前 HistoryManager 实际上也不读取 seasonIncome，所以暂不造成数据丢失，但如果未来需要财务回顾功能则需要调整顺序。
