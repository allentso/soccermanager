# Feature Gap Plan: soccermanager → Lua 实现

> 基于 `/workspace/soccermanager` (TypeScript/Rust) 与当前 `/workspace/scripts/` (Lua) 的逐模块对比。
> 
> 创建日期: 2026-05-27

---

## 优先级分类

### P0 — 核心玩法缺失（严重影响游戏体验）

| # | 功能 | 参考实现 | 说明 |
|---|------|---------|------|
| 1 | **比赛中战术干预** | `match/MatchLive.tsx` + SubPanel | 换人、阵型调整、战术指示（进攻/防守/正常）|
| 2 | **赛前阵容确认** | `match/PreMatchSetup.tsx` | 比赛前确认首发11人+替补，调整阵型 |
| 3 | **半场休息调整** | `match/HalfTimeBreak.tsx` | 半场时可换人、改战术 |
| 4 | **转会谈判多轮博弈** | `transfersService.ts` | mood/tension/patience/round + 反报价 |
| 5 | **自由球员合同谈判状态机** | `freeAgentService.ts` | accepted/rejected/counter_offer + session FSM |
| 6 | **升降级系统** | 隐含在 Rust 后端 | 每赛季末升3降3，5联赛间流动 |

### P1 — 重要玩法补充（影响策略深度）

| # | 功能 | 参考实现 | 说明 |
|---|------|---------|------|
| 7 | **财务恢复手段** | `financeService.ts` | 董事注资（-满意度）、赞助推介、商业活动（28天CD）|
| 8 | **时间推进阻断器** | `advanceTimeService.checkBlockingActions` | 未处理事项阻止推进时间 |
| 9 | **跳到比赛日** | `advanceTimeService.skipToMatchDay` | 一键快进到下场比赛 |
| 10 | **阵容安全检查** | `SquadSafetyReportData` | 终止合同/出售前验证能否凑齐出场阵容 |
| 11 | **消息可操作选项** | `inboxService.resolveMessageAction` | 消息内嵌按钮做决策（影响游戏世界）|
| 12 | **球员个人士气** | `player.morale` + `morale_core` | 独立于球队士气，受上场时间/薪资/角色影响 |
| 13 | **球队阵容角色** | `PlayerSquadRole` | Key/Rotation/Squad/Youth，影响士气与谈判 |
| 14 | **赛季阶段与转会窗** | `SeasonContextData` | Preseason/InSeason/PostSeason + 窗口倒计时天数 |

### P2 — 体验优化（锦上添花）

| # | 功能 | 参考实现 | 说明 |
|---|------|---------|------|
| 15 | **合同终止+遣散费** | `contractService.previewContractTermination` | 主动终止合同，支付遣散费 |
| 16 | **合同退出意向** | `contractService.setContractExitIntent` | 标记"打算放走"，不立即终止 |
| 17 | **训练分组系统** | `trainingService.setTrainingGroups` | 命名分组，各组不同focus |
| 18 | **青训球探(区域/目标)** | `scoutingService.startYouthScouting` | 按区域/目标/位置的定向球探 |
| 19 | **财务健康等级** | `finance.ts` getTeamFinanceSnapshot | stable/watch/warning/critical 4层状态 |
| 20 | **设施升级** | `FacilitiesData` | training/medical/scouting设施等级可升级 |
| 21 | **球员职业历史** | `CareerEntry[]` | 每赛季记录团队+数据，非推断 |
| 22 | **赛后新闻发布会** | `match/PressConference` | 选择回应，影响士气/声望 |
| 23 | **货币系统** | `settingsStore` + `valueFormatting` | EUR/GBP/USD 可切换 + 汇率 |
| 24 | **4层财务健康状态** | `finance.ts` | 工资预算占比 + 现金跑道周数 |

---

## 实现顺序

按依赖关系和影响面排序：

```
Phase A: 比赛交互增强 (#1, #2, #3)
  → 赛前确认 → 比赛中换人/战术 → 半场调整
  → 这是"玩"的核心，直接提升参与感

Phase B: 谈判系统 (#4, #5, #15, #16)
  → 转会多轮谈判 → 自由球员谈判FSM → 合同终止
  → 这是"经营"的核心，增加策略深度

Phase C: 赛季结构 (#6, #14)
  → 升降级 → 赛季阶段/转会窗倒计时
  → 这是"长期目标"的核心，增加长期可玩性

Phase D: 经济系统增强 (#7, #8, #9, #10, #19, #24)
  → 财务恢复手段 → 阻断器 → 快进 → 阵容安全 → 财务健康
  → 使经济玩法更丰富

Phase E: 球员深度 (#11, #12, #13, #17, #21)
  → 消息决策 → 个人士气 → 阵容角色 → 训练分组 → 职业历史
  → 使球员管理更细腻

Phase F: 辅助系统 (#18, #20, #22, #23)
  → 青训球探 → 设施升级 → 新闻发布会 → 货币
  → 锦上添花
```

---

## 当前实现状态追踪

| Phase | 状态 | 完成日期 |
|-------|------|---------|
| A | ✅ 完成 | 2026-05-26 |
| B | ✅ 完成 | 2026-05-26 |
| C | ✅ 完成 | 2026-05-26 |
| D | ✅ 完成 | 2026-05-27 |
| E | ✅ 完成 | 2026-05-27 |
| F | 🔲 未开始 | — |
