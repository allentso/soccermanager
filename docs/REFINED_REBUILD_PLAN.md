# OpenFoot Manager — 精炼重建计划 (v2)

> 基于 2026-05-27 项目现状评估后更新。分为**后端逻辑**和 **UI 实现**两条线，可并行推进。

---

## 0. 当前状态摘要

### 已完成（可复用）

| 模块 | 文件 | 行数 | 状态 |
|------|------|------|------|
| 入口 & 路由 | main.lua, router.lua | ~300 | ✅ 可用 |
| GameState | core/game_state.lua | 354 | ✅ 可用 |
| 回合推进 | core/turn_processor.lua | 676 | ✅ 基本完整（日推进、比赛日/非比赛日、训练、伤病恢复、新闻生成） |
| 世界生成 | systems/world_generator.lua | 434 | ✅ 真实数据 + 随机生成 |
| 真实数据加载 | data/real_data_loader.lua | 346 | ✅ 五大联赛导入 |
| 联赛 | domain/league.lua | 259 | ✅ 双循环赛程、积分榜 |
| 锦标赛框架 | domain/tournament.lua | 480 | ✅ 小组赛 + 淘汰赛通用 |
| 欧冠 | systems/champions_league.lua | 439 | ✅ 完整（超出原计划） |
| 世界杯 | systems/world_cup.lua | 513 | ✅ 完整（超出原计划） |
| 占位比赛 | match/placeholder_engine.lua | 694 | ✅ 含进球者、统计 |
| 转会系统 | systems/transfer_manager.lua | 371 | ⚠️ 50%（报价/谈判有，租借/AI主动无） |
| 赛季管理 | systems/season_manager.lua | 424 | ⚠️ 60%（奖金/成长/退役有，奖项/UI无） |
| 存档 | persistence/save_manager.lua | ~120 | ⚠️ 单槽，需多槽 |
| 球员模型 | domain/player.lua | 224 | ✅ 核心字段完整 |
| 球队模型 | domain/team.lua | 152 | ✅ 基本可用 |
| 职员模型 | domain/staff.lua | 56 | ⚠️ 仅数据结构 |
| 经理模型 | domain/manager.lua | 59 | ⚠️ 仅数据结构 |
| 常量 | app/constants.lua | 149 | ✅ 完整 |
| 事件总线 | app/event_bus.lua | 39 | ✅ 可用 |
| UI 主题 | ui/theme.lua | 318 | ✅ 深色竖屏主题 |
| UI 页面 | ui/screens/ (15个) | ~4000 | ⚠️ 框架在，深度不够 |

### 代码总量

- 36 个 Lua 文件，约 10,590 行
- 对标 REBUILD_PLAN 完成度 **~35%**
- 对标 soccermanager 后端逻辑完成度 **~25%**

---

## 1. 后端逻辑实现计划

后端指**不涉及 UI 渲染**的纯数据/逻辑模块。产出为独立 `.lua` 模块，对外暴露函数接口供 UI 层调用。

### Phase B1：经营闭环基础（必须先完成）

> 目标：让"推进一天"时经济和合同有真实变化，而非静态数据。

| # | 模块 | 新建/改动文件 | 核心功能 | 预估行数 |
|---|------|-------------|---------|---------|
| B1.1 | **财务流转** | `systems/finance_manager.lua` | 每周工资扣除（球员+职员）、转会费入账/出账、赛季奖金发放、余额变化写入流水记录 | ~250 |
| B1.2 | **合同系统** | `systems/contract_manager.lua` | 合同到期检测、续约谈判（工资+年限）、工资预算校验、到期前 30 天消息提醒、自由球员释放 | ~300 |
| B1.3 | **训练完善** | 改动 `turn_processor.lua` + 新建 `systems/training_manager.lua` | 训练强度（低/中/高）影响属性增长倍率和体能消耗、职员加成公式（coaching×0.85~1.35）、专长加成（1.25×）、理疗师恢复加成、训练小组、个人训练覆盖、周计划（密集/均衡/轻量） | ~400 |
| B1.4 | **消息系统增强** | `systems/message_manager.lua` | 统一消息发送接口（分类/优先级/动作/去重）、合同到期消息、财务警告、训练体能警告、董事会消息模板 | ~300 |
| B1.5 | **多存档** | 改动 `persistence/save_manager.lua` | 3 槽 + autosave、存档索引 index.json、存档元数据（日期/球队/赛季） | ~150 |
| B1.6 | **设置持久化** | `persistence/settings_manager.lua` | 音量/字号/自动保存开关/货币单位，独立于存档持久化 | ~80 |

**验收标准**：推进 10 周后，玩家球队余额因工资减少；合同到期球员自动释放并收到消息；不同训练强度导致属性和体能差异可观测。

---

### Phase B2：世界动态性

> 目标：让 AI 球队和世界不是静态背景，而是有事件发生。

| # | 模块 | 新建/改动文件 | 核心功能 | 预估行数 |
|---|------|-------------|---------|---------|
| B2.1 | **董事会系统** | `systems/board_manager.lua` | 赛季目标生成（按声望）、阶段性满意度评价（按排名/成绩）、满意度低→警告消息、极低→触发解雇 | ~250 |
| B2.2 | **球员事件/士气** | `systems/morale_manager.lua` | 士气核心因素（出场时间、合同、球队成绩、训练）、每周士气更新、低士气→消息（出场不满/合同不满）、高士气→表现加成 | ~300 |
| B2.3 | **职员管理** | `systems/staff_manager.lua` | 雇佣/解约逻辑、工资入财务、自由职员池、职员影响训练/球探/恢复的加成计算 | ~200 |
| B2.4 | **球探系统** | `systems/scout_manager.lua` | 指派球探观察目标球员、天数倒计时→生成报告、球探属性影响报告准确度、能力可见度机制（未侦察球员只看到估算值） | ~250 |
| B2.5 | **青训系统** | `systems/youth_manager.lua` | 每月刷新青年候选（根据球队设施/球探）、签入青训、青训球员标记、提拔到一线队 | ~200 |
| B2.6 | **解雇/求职** | `systems/job_manager.lua` | 玩家被解雇→进入失业状态、职位空缺列表、申请→董事会回复（按声望）、AI 空缺延迟补位 | ~200 |
| B2.7 | **随机事件** | `systems/random_event_manager.lua` | 事件池（训练场/财务/球员状态/媒体）、每周概率触发、消息附选项→选择影响士气/财务/状态 | ~200 |
| B2.8 | **声望动态** | `systems/reputation_manager.lua` | 比赛胜负→声望变化、赛季排名→声望修正、奖项加成、用于转会意愿和求职成功率 | ~150 |

**验收标准**：跑完一个赛季后，AI 教练有变动、球员有士气波动、球探能生成报告、青训有新人可提拔、玩家若排名垫底会收到董事会警告。

---

### Phase B3：赛季完整性

> 目标：一个赛季结束后能顺利进入下一赛季，历史数据完整保存。

| # | 模块 | 新建/改动文件 | 核心功能 | 预估行数 |
|---|------|-------------|---------|---------|
| B3.1 | **赛季奖项** | `systems/awards_manager.lua` | 最佳球员（综合评分）、金靴（进球）、最佳助攻、最佳年轻球员、最佳经理 | ~150 |
| B3.2 | **名人堂/历史** | `systems/history_manager.lua` | 记录每赛季冠军/奖项/重要转会/经理变动、写入 gameState.worldHistory | ~150 |
| B3.3 | **球员特性** | 改动 `domain/player.lua` | 20 个特性按属性自动计算、UI 标签展示、后续比赛引擎使用 | ~200 |
| B3.4 | **转会增强** | 改动 `systems/transfer_manager.lua` | AI 主动出价/挂牌、租借系统（状态+工资分摊）、合同到期自由签约 | ~250 |
| B3.5 | **新闻增强** | 改动 `turn_processor.lua` 新闻生成部分 | 联赛综述、经理变动新闻、伤病新闻、赛季前瞻、社论模板 | ~200 |
| B3.6 | **AI 管理增强** | 改动 `systems/season_manager.lua` | AI 球队自动调阵容/训练/转会、赛季前 AI 补充阵容不足 | ~200 |

**验收标准**：跑完 3 个赛季，历史记录完整、奖项正确、AI 球队阵容有合理变化、新闻丰富度明显提升。

---

### Phase B4：比赛引擎（后置）

> 目标：替换占位比赛为逐分钟模拟。

| # | 模块 | 文件 | 核心功能 | 预估行数 |
|---|------|------|---------|---------|
| B4.1 | 比赛引擎 | `match/match_engine.lua` | 逐分钟事件模拟、5 区域球场模型、球员属性/特性/战术影响 | ~1500 |
| B4.2 | 战术效果 | `match/tactics_resolver.lua` | 阵型→位置优劣、打法→事件概率修正、定位球角色 | ~500 |
| B4.3 | 比赛报告 | `match/match_report.lua` | 详细技术统计、球员评分、关键事件时间线 | ~300 |

**验收标准**：替换 placeholder_engine 后，其他所有经营系统无需修改、积分榜/新闻/统计正常运作。

---

## 2. UI 实现计划

UI 指 **urhox-libs/UI 组件树构建和交互逻辑**。每个页面对外暴露 `create(params)` / `destroy()` 接口供 Router 调用。

### Phase U1：核心交互循环（配合 B1）

> 目标：玩家能执行"查看阵容→调整→推进→看结果"的完整操作循环。

| # | 页面 | 文件 | 改动内容 | 备注 |
|---|------|------|---------|------|
| U1.1 | **阵容** | `ui/screens/squad.lua` | 球员卡列表（姓名/位置/能力/状态/士气/合同）、筛选（位置/状态）、排序（能力/年龄/工资）、长按→操作菜单（设首发/续约/挂牌）| 当前 159 行，需扩到 ~400 |
| U1.2 | **球员详情** | `ui/screens/player_detail.lua` | 多标签页：概览(属性雷达)、合同、赛季统计、生涯、训练 | 当前 174 行，需扩到 ~500 |
| U1.3 | **训练** | `ui/screens/training.lua` | 训练重点选择、强度选择、周计划选择、训练小组分配、个人训练覆盖 | 当前 258 行，需扩到 ~400 |
| U1.4 | **财务** | `ui/screens/finance.lua` | 余额/工资预算/转会预算卡、收支趋势（近 10 周）、工资结构饼图、流水列表 | 当前 311 行，需改善数据绑定 |
| U1.5 | **设置** | `ui/screens/settings.lua` (新建) | 音量滑块、字号选择、自动保存开关、货币单位、清除存档 | ~200 |
| U1.6 | **存档管理** | 改动 `ui/screens/load_game.lua` | 3 槽展示（日期/球队/赛季）、存入/读取/删除、自动存档标识 | 当前 104 行，需扩到 ~250 |

**验收标准**：玩家可完整执行"开始游戏→调整阵容→设训练→推进若干周→查看财务变化→保存"流程。

---

### Phase U2：信息反馈层（配合 B2）

> 目标：玩家能感知世界变化，收到有意义的反馈。

| # | 页面 | 文件 | 改动内容 | 备注 |
|---|------|------|---------|------|
| U2.1 | **收件箱** | `ui/screens/inbox.lua` | 分类筛选标签、优先级标识（图标/颜色）、未读计数、消息详情→动作按钮（确认/跳转/选择）、上下文跳转 | 当前 272 行，需扩到 ~450 |
| U2.2 | **新闻** | `ui/screens/news.lua` | 新闻流卡片列表、分类筛选、点击关联球队/球员跳转、已读状态 | 当前 233 行，需扩到 ~350 |
| U2.3 | **职员** | `ui/screens/staff.lua` (新建) | 当前职员列表（角色/属性/工资/专长）、可雇佣职员列表、雇佣/解约操作、加成展示 | ~350 |
| U2.4 | **球探** | `ui/screens/scouting.lua` (新建) | 球探总览、球员搜索（位置/年龄/能力筛选）、指派任务、报告列表、能力可见度展示 | ~400 |
| U2.5 | **青训** | `ui/screens/youth.lua` (新建) | 青训球员列表、候选招募、提拔操作、青训训练重点 | ~300 |
| U2.6 | **Dashboard 增强** | 改动 `ui/screens/dashboard.lua` | 新增：消息未读提示卡、合同即将到期卡、董事会满意度卡、下一场比赛卡增加对手实力对比 | 当前 372 行，需扩到 ~500 |
| U2.7 | **底部导航** | 改动路由/主界面 | 五入口底部导航栏（主页/球队/赛事/市场/消息）+ 顶部状态栏（日期/球队/资金/继续按钮） | ~150 新增组件代码 |

**验收标准**：推进一周后，收件箱有新消息、新闻有更新、Dashboard 卡片数据实时刷新、可以管理职员/球探/青训。

---

### Phase U3：完整经营界面（配合 B3）

> 目标：所有主要经营页面达到可交付质量。

| # | 页面 | 文件 | 改动内容 | 备注 |
|---|------|------|---------|------|
| U3.1 | **球队详情** | `ui/screens/team_detail.lua` (新建) | 概览/阵容/历史/统计标签页、可查看任意球队 | ~400 |
| U3.2 | **经理** | `ui/screens/manager_view.lua` (新建) | 玩家经理资料、AI 经理库、履历、声望 | ~250 |
| U3.3 | **赛季结算** | `ui/screens/season_end.lua` (新建) | 最终排名、奖项、奖金、董事会评价、球员老化/退役/合同到期摘要、"进入新赛季"按钮 | ~400 |
| U3.4 | **名人堂** | `ui/screens/hall_of_fame.lua` (新建) | 历史冠军列表、赛季奖项记录、传奇球员 | ~250 |
| U3.5 | **转会增强** | 改动 `ui/screens/market.lua` | 新增：租借市场 tab、报价详情底部抽屉、AI 报价响应展示、自由球员签约 | 当前 558 行，需扩到 ~700 |
| U3.6 | **战术增强** | 改动 `ui/screens/tactics.lua` | 竖屏球场视图（位置点）、首发 11 人点选替换、定位球角色分配、打法详细说明 | 当前 264 行，需扩到 ~500 |
| U3.7 | **全球转会中心** | `ui/screens/transfer_hub.lua` (新建) | 世界重要转会动态、传闻、合同到期球员列表 | ~250 |

**验收标准**：能完整跑过一个赛季并进入新赛季，赛季结算页面展示完整信息，名人堂有记录，所有页面数据正确。

---

### Phase U4：比赛 UI（配合 B4）

| # | 页面 | 文件 | 改动内容 | 备注 |
|---|------|------|---------|------|
| U4.1 | **实时比赛** | `ui/screens/live_match.lua` (新建) | 比分面板、事件时间线滚动、控球/射门实时数据、战术调整按钮、换人界面 | ~600 |
| U4.2 | **赛后报告** | 改动 `ui/screens/match_result.lua` | 详细技术统计对比、球员评分列表、关键事件回放、最佳球员高亮 | 当前 330 行，需扩到 ~500 |

---

## 3. 集成关系图

```
Phase B1 ──────┐
               ├──→ Phase U1（核心交互循环）
Phase B2 ──────┤
               ├──→ Phase U2（信息反馈层）
Phase B3 ──────┤
               ├──→ Phase U3（完整经营界面）
Phase B4 ──────┘
               └──→ Phase U4（比赛 UI）
```

后端和 UI 可在同一 Phase 内并行：
- 先实现后端逻辑并验证数据正确性（print / assert）
- 再实现 UI 绑定展示数据
- 或两人并行：一人写后端、一人用 mock 数据写 UI

**严禁**：UI 直接写业务逻辑。所有数据变更必须通过 systems/ 模块。

---

## 4. 文件组织最终结构

```
scripts/
├── main.lua                        # 入口
├── app/
│   ├── constants.lua               # ✅ 已有
│   ├── event_bus.lua               # ✅ 已有
│   └── router.lua                  # ✅ 已有（需增加底部导航支持）
├── core/
│   ├── game_state.lua              # ✅ 已有
│   └── turn_processor.lua          # ✅ 已有（B1/B2 阶段持续增强）
├── domain/
│   ├── player.lua                  # ✅ 已有（B3 增加特性）
│   ├── team.lua                    # ✅ 已有
│   ├── staff.lua                   # ✅ 已有（B2 扩展）
│   ├── manager.lua                 # ✅ 已有
│   ├── league.lua                  # ✅ 已有
│   └── tournament.lua              # ✅ 已有
├── systems/
│   ├── world_generator.lua         # ✅ 已有
│   ├── season_manager.lua          # ✅ 已有（B3 增强）
│   ├── transfer_manager.lua        # ✅ 已有（B3 增强）
│   ├── champions_league.lua        # ✅ 已有
│   ├── world_cup.lua               # ✅ 已有
│   ├── finance_manager.lua         # 🆕 B1.1
│   ├── contract_manager.lua        # 🆕 B1.2
│   ├── training_manager.lua        # 🆕 B1.3
│   ├── message_manager.lua         # 🆕 B1.4
│   ├── board_manager.lua           # 🆕 B2.1
│   ├── morale_manager.lua          # 🆕 B2.2
│   ├── staff_manager.lua           # 🆕 B2.3
│   ├── scout_manager.lua           # 🆕 B2.4
│   ├── youth_manager.lua           # 🆕 B2.5
│   ├── job_manager.lua             # 🆕 B2.6
│   ├── random_event_manager.lua    # 🆕 B2.7
│   ├── reputation_manager.lua      # 🆕 B2.8
│   ├── awards_manager.lua          # 🆕 B3.1
│   └── history_manager.lua         # 🆕 B3.2
├── match/
│   ├── placeholder_engine.lua      # ✅ 已有（B4 后替换）
│   ├── match_engine.lua            # 🆕 B4.1
│   ├── tactics_resolver.lua        # 🆕 B4.2
│   └── match_report.lua            # 🆕 B4.3
├── persistence/
│   ├── save_manager.lua            # ✅ 已有（B1.5 改多槽）
│   └── settings_manager.lua        # 🆕 B1.6
├── data/
│   ├── json_loader.lua             # ✅ 已有
│   └── real_data_loader.lua        # ✅ 已有
└── ui/
    ├── theme.lua                   # ✅ 已有
    ├── components/                 # 🆕 可复用 UI 组件（后续按需提取）
    │   ├── player_card.lua
    │   ├── stat_pill.lua
    │   ├── bottom_nav.lua
    │   └── confirm_dialog.lua
    └── screens/
        ├── main_menu.lua           # ✅ 已有
        ├── create_manager.lua      # ✅ 已有
        ├── select_team.lua         # ✅ 已有
        ├── load_game.lua           # ✅ 已有（U1.6 改多槽）
        ├── dashboard.lua           # ✅ 已有（U2.6 增强）
        ├── squad.lua               # ✅ 已有（U1.1 增强）
        ├── player_detail.lua       # ✅ 已有（U1.2 增强）
        ├── tactics.lua             # ✅ 已有（U3.6 增强）
        ├── training.lua            # ✅ 已有（U1.3 增强）
        ├── finance.lua             # ✅ 已有（U1.4 增强）
        ├── league_view.lua         # ✅ 已有
        ├── match_result.lua        # ✅ 已有（U4.2 增强）
        ├── market.lua              # ✅ 已有（U3.5 增强）
        ├── inbox.lua               # ✅ 已有（U2.1 增强）
        ├── news.lua                # ✅ 已有（U2.2 增强）
        ├── settings.lua            # 🆕 U1.5
        ├── staff.lua               # 🆕 U2.3
        ├── scouting.lua            # 🆕 U2.4
        ├── youth.lua               # 🆕 U2.5
        ├── team_detail.lua         # 🆕 U3.1
        ├── manager_view.lua        # 🆕 U3.2
        ├── season_end.lua          # 🆕 U3.3
        ├── hall_of_fame.lua        # 🆕 U3.4
        ├── transfer_hub.lua        # 🆕 U3.7
        └── live_match.lua          # 🆕 U4.1
```

---

## 5. 每个 Phase 的验收检查清单

### Phase 1 (B1 + U1) 验收

- [ ] 新游戏→选队→进入 Dashboard，全流程无崩溃
- [ ] 推进 10 天，球队余额因工资减少（finance_manager 生效）
- [ ] 合同剩余 ≤ 30 天的球员，收件箱有续约提醒
- [ ] 训练设为"高强度"，球员体能下降更快、属性增长更快
- [ ] 存档到 slot 2，退出，从 slot 2 读取，数据一致
- [ ] 设置页可调字号，保存后重启仍生效
- [ ] 阵容页可筛选位置、按能力排序、查看详情多标签

### Phase 2 (B2 + U2) 验收

- [ ] 董事会赛季初发送目标消息（如"保级"或"争冠"）
- [ ] 板凳球员连续 5 场未上场，收到士气下降消息
- [ ] 可雇佣/解约职员，职员工资反映在财务流水
- [ ] 指派球探→等待若干天→球探报告出现在球探页
- [ ] 青训每月刷新候选，可签入、可提拔
- [ ] Dashboard 显示未读消息数、合同到期预警
- [ ] 底部导航栏工作正常（5 个 tab 切换无卡顿）

### Phase 3 (B3 + U3) 验收

- [ ] 完整跑完一个赛季，触发赛季结算页
- [ ] 奖项正确（金靴 = 联赛进球最多的球员）
- [ ] 名人堂页可查看上赛季冠军和奖项
- [ ] AI 球队有转会动作（买入/卖出球员），全球转会中心有记录
- [ ] 租借系统可用：租出球员、租入球员
- [ ] 新赛季赛程正确生成，积分榜重置
- [ ] 连续跑 3 个赛季无崩溃，历史记录完整

### Phase 4 (B4 + U4) 验收

- [ ] 替换 placeholder_engine 后，所有 Phase 1-3 验收仍通过
- [ ] 实时比赛页可观看逐分钟事件
- [ ] 战术调整在比赛中可感知效果
- [ ] 赛后报告包含球员评分和关键事件

---

## 6. 技术约束与规范

### 模块交互规则

```lua
-- ✅ 正确：UI 通过 system 接口读写数据
local ContractManager = require("scripts/systems/contract_manager")
ContractManager.renewContract(gameState, playerId, newWage, newYears)

-- ❌ 错误：UI 直接修改 GameState
gameState.players[playerId].contractEnd = 3
```

### 新增 system 模块模板

```lua
-- systems/xxx_manager.lua
local EventBus = require("scripts/app/event_bus")
local Constants = require("scripts/app/constants")

local XxxManager = {}

--- 每日处理（由 turn_processor 调用）
function XxxManager.processDaily(gameState)
end

--- 每周处理（由 turn_processor 调用）
function XxxManager.processWeekly(gameState)
end

--- 玩家主动操作接口（由 UI 调用）
function XxxManager.doSomething(gameState, params)
end

return XxxManager
```

### turn_processor 集成点

所有新系统通过 `turn_processor.lua` 中的 `processNonMatchDay` 和 `processWeekly` 钩子接入：

```lua
function TurnProcessor.processNonMatchDay(gameState)
    -- 已有
    TurnProcessor.processTraining(gameState)
    TurnProcessor.processInjuryRecovery(gameState)
    TurnProcessor.processFitnessRecovery(gameState)
    
    -- B1 新增
    FinanceManager.processDaily(gameState)
    ContractManager.processDaily(gameState)
    
    -- B2 新增
    MoraleManager.processDaily(gameState)
    ScoutManager.processDaily(gameState)
    BoardManager.processDaily(gameState)
end

function TurnProcessor.processWeekly(gameState)
    -- 已有
    TransferManager.processDailyBids(gameState)
    
    -- B1 新增
    FinanceManager.processWeeklyWages(gameState)
    
    -- B2 新增
    MoraleManager.processWeekly(gameState)
    YouthManager.processMonthly(gameState)  -- 每月首周
    RandomEventManager.processWeekly(gameState)
    ReputationManager.processWeekly(gameState)
end
```

---

## 7. 与原始 REBUILD_PLAN 的差异说明

| 变化点 | 原计划 | 精炼后 | 原因 |
|--------|-------|--------|------|
| 联赛数量 | 单联赛 | 五大联赛 + UCL + WC | 当前已实现多联赛，保留 |
| 日推进粒度 | 每天 | 每天 | 已实现，保持 |
| 存档格式 | JSON 多槽 | JSON 3 槽 + autosave | 与计划一致，当前需补齐 |
| 比赛引擎 | 后置 | 后置 (Phase B4) | 一致 |
| 杯赛 | 未提及 | 已有 UCL + WC | 超出计划，保留 |
| 真实数据 | 提到可复用 JSON | 已有 real_data_loader | 保留 |
| UI 范式 | 竖屏卡片 | 竖屏卡片 (urhox-libs/UI) | 一致 |
| 后端/UI 分离 | 隐含 | 显式划分 Phase B/U | 新增，便于并行 |

---

## 8. 优先实施顺序（推荐）

```
Week 1-2:  B1.1 + B1.2 + B1.5 → 经济和合同跑通
Week 2-3:  B1.3 + B1.4 + B1.6 → 训练和消息完善
Week 3-4:  U1.1~U1.6           → 核心 UI 可交互
Week 4-5:  B2.1 + B2.2 + B2.3 → 世界动态基础
Week 5-6:  B2.4~B2.8           → 完整世界动态
Week 6-7:  U2.1~U2.7           → 反馈层 UI
Week 7-9:  B3 + U3             → 赛季完整性
Week 10+:  B4 + U4             → 比赛引擎（可选）
```

> 以上仅为实施顺序建议，不包含时间承诺。按优先级逐步推进即可。

---

*文档版本: v2.0*  
*更新日期: 2026-05-27*  
*基于: 项目现状评估 + URHOX_REBUILD_PLAN.md + soccermanager 参考*
