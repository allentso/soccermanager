# OpenFoot Manager - 开发进度文档

> 最后更新: 2026-05-27
> 当前口径: UrhoX + Lua 重构版 `new`

---

## 项目概要

| 指标 | 当前状态 |
|------|----------|
| 项目名称 | OpenFoot Manager |
| 技术栈 | UrhoX + Lua 5.4 + urhox-libs/UI |
| 游戏模式 | 单机经营模拟 |
| 屏幕方向 | 横屏 |
| 当前阶段 | 核心经营闭环已完成，进入体验打磨与测试补强阶段 |
| 自动化测试 | 已建立最小 Lua assert 测试框架 |

---

## 模块分布

| 目录 | 说明 |
|------|------|
| `scripts/app/` | 路由、事件总线、全局常量 |
| `scripts/core/` | `GameState` 与日推进 `TurnProcessor` |
| `scripts/domain/` | 球员、球队、联赛、锦标赛、职员、经理等领域模型 |
| `scripts/systems/` | 经营系统：转会、财务、合同、训练、董事会、士气、AI、奖项、历史等 |
| `scripts/systems/transfers/` | 转会系统子模块，当前拆出转会完成/付款/条款 helper |
| `scripts/match/` | 比赛引擎、战术解析、比赛报告、旧占位引擎 |
| `scripts/ui/screens/` | 主 UI 页面 |
| `scripts/ui/screens/market/` | 转会市场子页面模块 |
| `scripts/ui/screens/player_detail/` | 球员详情子页面模块 |
| `scripts/ui/components/` | 可复用 UI 组件 |
| `scripts/persistence/` | 存档与设置 |
| `scripts/data/` | 真实数据加载 |
| `tests/` | Lua 断言测试框架与核心测试 |

---

## 后端系统完成状态

### 已完成

| 模块 | 主要文件 | 当前状态 |
|------|----------|----------|
| 游戏状态 | `core/game_state.lua` | 全局状态容器、实体注册、序列化入口 |
| 回合推进 | `core/turn_processor.lua` | 日推进、比赛日/非比赛日分流、训练、转会、球探、青训、新闻、月度/周度钩子 |
| 世界生成 | `systems/world_generator.lua`, `data/real_data_loader.lua` | 五大联赛真实数据导入与随机补充 |
| 联赛 | `domain/league.lua` | 双循环赛程、积分榜、赛季完成检测 |
| 锦标赛 | `domain/tournament.lua` | 小组赛与淘汰赛通用框架 |
| 欧冠 | `systems/champions_league.lua` | 资格赛、小组赛、淘汰赛流程 |
| 世界杯 | `systems/world_cup.lua` | 分组抽签、小组赛、淘汰赛流程 |
| 比赛引擎 v2 | `match/match_engine.lua` | 逐分钟模拟、控球/射门/进球/犯规/牌/伤病、加时与点球 |
| 战术解析 | `match/tactics_resolver.lua` | 阵型、打法、球员属性、体能、士气、职责、特性转为比赛修正 |
| 比赛报告 | `match/match_report.lua` | 兼容 UI 的 report，含事件、统计、评分、MOTM |
| 旧占位引擎 | `match/placeholder_engine.lua` | 保留作为历史实现和部分兼容 helper |
| 转会系统 | `systems/transfer_manager.lua`, `systems/transfers/transfer_completion.lua` | 多轮谈判、AI 买卖、挂牌、租借、自由球员 FSM、预签约、解约金、分期/附加条款、竞争报价、球员意愿 |
| 财务系统 | `systems/finance_manager.lua` | 工资、转会收支、比赛日收入、奖金、财务健康、董事注资、赞助、商业活动、设施升级 |
| 设施系统 | `systems/finance_manager.lua` | 训练/医疗/球探设施等级，影响训练收益、伤病恢复、球探准确度 |
| 合同系统 | `systems/contract_manager.lua` | 合同到期提醒、续约、赛季末释放、终止合同 |
| 训练系统 | `systems/training_manager.lua` | 强度、专项、周计划、训练分组、个人训练、职员与设施加成 |
| 消息系统 | `systems/message_manager.lua` | 分类、优先级、动作、去重、清理 |
| 赛季管理 | `systems/season_manager.lua` | 赛季结算、升降级、奖金、成长、退役、新赛季初始化 |
| 董事会 | `systems/board_manager.lua` | 目标、满意度、警告、解雇 |
| 士气系统 | `systems/morale_manager.lua` | 个人士气、出场时间、合同、成绩、角色影响 |
| 职员管理 | `systems/staff_manager.lua` | 雇佣/解约、工资、训练/球探/恢复加成 |
| 球探系统 | `systems/scout_manager.lua` | 球探任务、报告、准确度、过期清理、设施加成 |
| 青训系统 | `systems/youth_manager.lua` | 月度候选、招募、提拔、青训训练 |
| 求职系统 | `systems/job_manager.lua` | 失业、申请职位、AI 空缺补位 |
| 随机事件 | `systems/random_event_manager.lua` | 事件池、概率触发、消息选项影响 |
| 声望系统 | `systems/reputation_manager.lua` | 比赛、排名、奖项、自然回归 |
| 奖项系统 | `systems/awards_manager.lua` | 金靴、最佳球员、最佳年轻球员、最佳经理 |
| 历史记录 | `systems/history_manager.lua` | 冠军、奖项、转会、经理变动 |
| AI 管理 | `systems/ai_manager.lua` | AI 阵容、训练、转会、薪资管理 |
| 新闻生成 | `systems/news_generator.lua` | 联赛综述、转会新闻、伤病新闻、赛季前瞻 |
| 赛后发布会 | `systems/press_conference_manager.lua` | 赛后回应影响士气、声望、董事会满意度，并生成消息/新闻 |
| 存档系统 | `persistence/save_manager.lua` | 多槽存档与 autosave |
| 设置管理 | `persistence/settings_manager.lua` | 音量、字号、货币、自动保存 |

### 当前未做或后置

| 模块 | 状态 | 说明 |
|------|------|------|
| 经纪人系统 | 不计划实现 | 已明确排除，不纳入转会深度扩展 |
| 真正实时比赛重算 | 后置 | 当前仍是赛前一次性模拟，`match_live` 回放事件；赛中换人/战术主要是体验层 |
| 更完整的转会条款结算 | 部分完成 | 分期已接入；出场奖金/二转分成已记录，后续可继续做触发结算 |
| 更多联赛 | 后置 | 当前五大联赛足够验证核心循环 |
| 新手教程 | 后置 | 等核心 UI 稳定后再做 |

---

## UI 页面完成状态

### 已完成

| 页面 | 文件 | 功能 |
|------|------|------|
| 主菜单 | `main_menu.lua` | 新游戏、继续、加载 |
| 创建经理 | `create_manager.lua` | 输入姓名、选择国籍 |
| 选择球队 | `select_team.lua` | 联赛筛选、球队列表 |
| 加载存档 | `load_game.lua` | 多槽展示、读取、保存、删除 |
| 仪表盘 | `dashboard.lua` | 下场比赛、排名、未读消息、合同预警、财务、董事会 |
| 阵容 | `squad.lua` | 球员列表、筛选、排序、操作菜单 |
| 球员详情 | `player_detail.lua` + `player_detail/stats_tab.lua` | 概览、属性、合同、统计、生涯、训练 |
| 战术 | `tactics.lua` | 阵型、首发/替补、打法 |
| 训练 | `training.lua` | 强度、专项、分组、个人训练、周计划 |
| 财务 | `finance.lua` | 余额、预算、趋势、流水、设施升级 |
| 联赛 | `league_view.lua` | 积分榜、赛程、射手榜 |
| 赛前 | `pre_match.lua` | 阵容确认、战术调整、启动比赛 |
| 比赛实况 | `match_live.lua` | 事件回放、统计、换人/战术干预体验 |
| 赛后结果 | `match_result.lua` | 技术统计、评分、事件回放、进入发布会 |
| 赛后发布会 | `press_conference.lua` | 三类回应，影响士气/声望/董事会 |
| 收件箱 | `inbox.lua` | 分类筛选、优先级、动作按钮、上下文跳转 |
| 新闻 | `news.lua` | 新闻列表、分类、关联跳转 |
| 转会市场 | `market.lua` + `market/loans_tab.lua` | 浏览、出价、条款报价、解约金、租借、自由签、挂牌 |
| 全球转会中心 | `transfer_hub.lua` | 最新转会、重磅交易、自由球员、活跃传闻 |
| 职员 | `staff.lua` | 当前职员、可雇佣、雇佣/解约、加成 |
| 球探 | `scouting.lua` | 任务、搜索、报告 |
| 青训 | `youth.lua` | 青训名单、候选、提拔 |
| 球队详情 | `team_detail.lua` | 任意球队概览、阵容、历史、统计 |
| 经理 | `manager_view.lua` | 经理资料、履历、声望 |
| 赛季结算 | `season_end.lua` | 排名、奖项、奖金、评价、升降级 |
| 名人堂 | `hall_of_fame.lua` | 历史冠军、奖项、传奇球员 |
| 设置 | `settings.lua` | 音量、字号、货币、自动保存 |

### 可复用组件

| 组件 | 文件 | 说明 |
|------|------|------|
| 底部抽屉 | `ui/components/bottom_sheet.lua` | 通用底部滑出面板 |
| 确认对话框 | `ui/components/confirm_dialog.lua` | 是/否确认弹窗 |
| 覆盖层管理 | `ui/components/overlay_manager.lua` | 全局覆盖层队列 |
| 球员卡片 | `ui/components/player_card.lua` | 球员信息复用卡 |

---

## 测试状态

已建立无第三方依赖的 Lua assert 测试框架：

| 文件 | 覆盖内容 |
|------|----------|
| `tests/bootstrap.lua` | `package.path`、确定性 `Random/RandomInt`、基础全局 stub |
| `tests/run.lua` | 顺序执行测试文件 |
| `tests/fixtures/minimal_game_state.lua` | 两队、球员、联赛、fixture 的最小状态 |
| `tests/tactics_resolver_test.lua` | 战术修正、控球、压迫、强弱队上下文 |
| `tests/match_report_test.lua` | report 字段、事件排序、统计与评分 |
| `tests/match_engine_test.lua` | 比赛模拟、结算、积分榜、体能、淘汰赛边界 |
| `tests/finance_manager_test.lua` | 工资、比赛日收入、财务健康、设施升级 |
| `tests/contract_manager_test.lua` | 合同提醒、续约、到期释放 |
| `tests/transfer_manager_test.lua` | 解约金、条款报价、分期、竞争报价、租借 |
| `tests/press_conference_manager_test.lua` | 发布会选择对士气/声望/消息的影响 |

运行方式：

```powershell
lua tests/run.lua
```

说明：本地 Windows 环境如果没有 `lua` 命令，需要在云端或安装 Lua 5.4 后运行。

---

## 对照计划完成度

### FEATURE_GAP_PLAN 进度

| Phase | 内容 | 状态 |
|-------|------|------|
| A | 比赛交互增强（赛前确认/换人/战术/半场调整） | 已完成 |
| B | 谈判系统（多轮转会/自由球员 FSM/合同终止） | 已完成 |
| C | 赛季结构（升降级/赛季阶段/转会窗） | 已完成 |
| D | 经济系统增强（财务恢复/阻断器/快进/阵容安全/财务健康） | 已完成 |
| E | 球员深度（消息决策/个人士气/阵容角色/训练分组/职业历史） | 已完成 |
| F | 辅助系统（青训球探/设施升级/新闻发布会/货币） | 已完成 |

### REFINED_REBUILD_PLAN 进度

| Phase | 内容 | 状态 |
|-------|------|------|
| B1 | 经营闭环基础 | 已完成 |
| B2 | 世界动态性 | 已完成 |
| B3 | 赛季完整性 | 已完成 |
| B4 | 比赛引擎 v2（逐分钟/战术/报告） | 已完成第一版 |
| U1 | 核心交互循环 UI | 已完成 |
| U2 | 信息反馈层 UI | 已完成 |
| U3 | 完整经营界面 UI | 已完成 |
| U4 | 比赛 UI | 已完成 |

---

## 总体完成度评估

| 维度 | 完成度 | 说明 |
|------|--------|------|
| 后端经营系统 | 约 95% | 主经营闭环完整，经纪人系统明确不做 |
| UI 页面覆盖 | 约 92% | 核心页面齐全，部分页面仍可继续拆分和打磨 |
| 比赛引擎 | 约 70% | 已有逐分钟模拟、战术解析、报告；真正实时赛中影响仍后置 |
| 转会深度 | 约 85% | 已有条款、解约金、竞争报价、球员意愿；出场奖金/二转分成触发结算可继续补 |
| 自动化测试 | 约 45% | 已覆盖核心新模块，仍需补赛季、AI、更多转会边界 |
| 整体可玩性 | 约 90% | 可完整进行多赛季经营，核心反馈链已闭合 |

---

## 已验证的核心玩法循环

```text
新游戏 -> 创建经理 -> 选择球队 -> 进入仪表盘
  -> 查看阵容 / 球员详情 / 战术 / 训练 / 财务 / 职员 / 球探 / 青训
  -> 管理转会：报价 / 条款 / 租借 / 自由签 / 挂牌 / 续约
  -> 推进日期
     -> 比赛日：赛前确认 -> 实况回放 -> 赛后报告 -> 新闻发布会
     -> 非比赛日：训练、恢复、合同、球探、青训、转会、随机事件
  -> 赛季结束：排名、奖项、奖金、升降级、历史记录
  -> 新赛季 / 存档 / 读档
```

---

## 下一步建议

### 高优先级

1. **补更多测试**：`season_manager`、AI 转会、自由球员 FSM、转会窗口、预签约、设施边界。
2. **比赛平衡跑批**：统计多场模拟后的平均进球、射门、红黄牌、伤病率、强弱队胜率。
3. **完善条款触发结算**：出场奖金、二次转会分成的实际付款触发。

### 中优先级

1. **继续拆大文件**：`transfer_manager.lua` 仍可拆出谈判、租借、自由球员、预签约等子模块。
2. **UI 体验打磨**：动画、过渡、空状态、错误提示、操作确认。
3. **新闻模板扩展**：增强比赛、转会、发布会、董事会相关叙事。

### 低优先级

1. 更多联赛。
2. 更多国际/洲际赛事。
3. 新手教程。

---

## 技术债务

| 问题 | 严重度 | 当前状态 |
|------|--------|----------|
| `transfer_manager.lua` 仍偏大 | 中 | 已拆出 `systems/transfers/transfer_completion.lua`，还可继续拆谈判/租借/自由球员 |
| `player_detail.lua` 偏大 | 中 | 已拆出 `player_detail/stats_tab.lua`，可继续拆 overview/contract/training |
| `market.lua` 偏大 | 中 | 已拆出 `market/loans_tab.lua`，可继续拆 browse/free/listed/my_bids |
| `placeholder_engine.lua` 仍保留 | 低 | 当前作为历史实现和兼容 helper，后续可逐步清理 |
| 测试覆盖仍不完整 | 中 | 已有最小测试框架，但还需要覆盖更多赛季和 AI 边界 |

---

*文档版本: v2.0*
*创建日期: 2026-05-27*
*更新日期: 2026-05-27*
# OpenFoot Manager — 开发进度文档

> 最后更新: 2026-05-27

---

## 项目概要

| 指标 | 数值 |
|------|------|
| 项目名称 | OpenFoot Manager (足球经理) |
| 技术栈 | UrhoX + Lua 5.4 + urhox-libs/UI |
| 文件总数 | 69 个 .lua 文件 |
| 代码总行数 | ~14,000 行 |
| 模式 | 单机（multiplayer.enabled = false） |
| 屏幕方向 | 横屏 (landscape) |

---

## 模块分布

| 目录 | 文件数 | 行数 | 说明 |
|------|--------|------|------|
| `scripts/systems/` | 21 | 9,229 | 后端逻辑系统 |
| `scripts/ui/screens/` | 26 | 14,732 | UI 页面 |
| `scripts/ui/components/` | 4 | ~400 | 可复用 UI 组件 |
| `scripts/core/` | 2 | ~1,030 | 核心引擎（GameState + TurnProcessor） |
| `scripts/domain/` | 6 | ~1,230 | 领域模型 |
| `scripts/match/` | 1 | 694 | 比赛引擎（占位） |
| `scripts/persistence/` | 2 | ~460 | 存档/设置 |
| `scripts/data/` | 2 | ~500 | 数据加载 |
| `scripts/app/` | 3 | ~490 | 路由/常量/事件总线 |
| `scripts/ui/theme.lua` | 1 | 329 | UI 主题 |
| `scripts/main.lua` | 1 | 272 | 入口 |

---

## 后端系统完成状态

### 已完成 ✅

| 模块 | 文件 | 行数 | 功能说明 |
|------|------|------|---------|
| 回合推进 | `core/turn_processor.lua` | 676 | 日推进、比赛日/非比赛日分流、各系统钩子集成 |
| 游戏状态 | `core/game_state.lua` | 354 | 全局状态容器、初始化、序列化 |
| 世界生成 | `systems/world_generator.lua` | 464 | 五大联赛真实数据 + 随机填充 |
| 联赛 | `domain/league.lua` | 259 | 双循环赛程生成、积分榜排序 |
| 锦标赛 | `domain/tournament.lua` | 480 | 小组赛 + 淘汰赛通用框架 |
| 欧冠 | `systems/champions_league.lua` | 439 | 资格赛→小组赛→淘汰赛完整流程 |
| 世界杯 | `systems/world_cup.lua` | 513 | 分组抽签→小组赛→淘汰赛 |
| 占位比赛引擎 | `match/placeholder_engine.lua` | 694 | 随机模拟含进球者/助攻/统计 |
| 转会系统 | `systems/transfer_manager.lua` | 1,477 | 多轮谈判、自由球员FSM、租借、AI主动买卖、反报价 |
| 财务系统 | `systems/finance_manager.lua` | 588 | 周工资扣除、转会费入账/出账、奖金发放、财务健康等级、董事注资、赞助推介 |
| 合同系统 | `systems/contract_manager.lua` | 259 | 合同到期检测、续约谈判、终止+遣散费、退出意向 |
| 训练系统 | `systems/training_manager.lua` | 284 | 强度(低/中/高)、专项训练、职员加成、训练分组、个人训练 |
| 消息系统 | `systems/message_manager.lua` | 373 | 统一消息接口、分类/优先级/动作/去重、可操作选项 |
| 赛季管理 | `systems/season_manager.lua` | 920 | 赛季结算、升降级(3升3降)、奖金分配、球员成长/退役、新赛季初始化 |
| 董事会 | `systems/board_manager.lua` | 207 | 赛季目标、满意度评价、警告/解雇 |
| 士气系统 | `systems/morale_manager.lua` | 342 | 球员个人士气、出场时间/合同/成绩影响、低士气消息 |
| 职员管理 | `systems/staff_manager.lua` | 371 | 雇佣/解约、工资入财务、加成计算 |
| 球探系统 | `systems/scout_manager.lua` | 286 | 指派观察、天数倒计时、报告生成、准确度机制 |
| 青训系统 | `systems/youth_manager.lua` | 321 | 月度刷新候选、签入/提拔、区域球探 |
| 求职系统 | `systems/job_manager.lua` | 299 | 玩家被解雇/辞职→失业→求职、AI空缺补位 |
| 随机事件 | `systems/random_event_manager.lua` | 329 | 事件池、概率触发、消息附选项→影响 |
| 声望系统 | `systems/reputation_manager.lua` | 209 | 比赛胜负/排名/奖项→声望变化 |
| 奖项系统 | `systems/awards_manager.lua` | 436 | 金靴、最佳球员、最佳年轻球员、最佳经理 |
| 历史记录 | `systems/history_manager.lua` | 308 | 赛季冠军、奖项、重要转会、经理变动 |
| AI 管理 | `systems/ai_manager.lua` | 388 | AI球队自动阵容/训练/转会 |
| 新闻生成 | `systems/news_generator.lua` | 416 | 联赛综述、转会新闻、伤病新闻、赛季前瞻 |
| 真实数据 | `data/real_data_loader.lua` | 346 | 五大联赛JSON导入 |
| 存档系统 | `persistence/save_manager.lua` | ~120 | 多槽存档+autosave |
| 设置管理 | `persistence/settings_manager.lua` | ~340 | 音量/字号/货币/自动保存 |

### 未完成 🔲

| 模块 | 状态 | 说明 |
|------|------|------|
| 比赛引擎 v2 | 🔲 未开始 | 逐分钟模拟、战术影响、球员属性权重（Phase B4） |
| 战术解析器 | 🔲 未开始 | 阵型→位置优劣、打法→概率修正 |
| 比赛报告 | 🔲 未开始 | 详细统计、球员评分、关键事件 |
| 设施升级 | 🔲 未开始 | 训练/医疗/球探设施等级 |
| 赛后新闻发布会 | 🔲 未开始 | 选择回应，影响士气/声望 |

---

## UI 页面完成状态

### 已完成 ✅

| 页面 | 文件 | 行数 | 功能 |
|------|------|------|------|
| 主菜单 | `main_menu.lua` | 78 | 新游戏/继续/加载 |
| 创建经理 | `create_manager.lua` | 129 | 输入姓名、选择国籍 |
| 选择球队 | `select_team.lua` | 206 | 联赛筛选、球队列表 |
| 加载存档 | `load_game.lua` | 467 | 多槽展示、存入/读取/删除 |
| 仪表盘 | `dashboard.lua` | 870 | 综合卡片(下场比赛/排名/未读消息/合同预警/财务/董事会) |
| 阵容 | `squad.lua` | 676 | 球员列表/筛选/排序/操作菜单 |
| 球员详情 | `player_detail.lua` | 1,208 | 多标签(概览/属性/合同/统计/生涯/训练) |
| 战术 | `tactics.lua` | 552 | 阵型选择、首发/替补安排、打法设置 |
| 训练 | `training.lua` | 884 | 强度/专项/分组/个人训练/周计划 |
| 财务 | `finance.lua` | 941 | 余额/预算/趋势/工资结构/流水 |
| 联赛 | `league_view.lua` | 672 | 积分榜、赛程、射手榜 |
| 赛前 | `pre_match.lua` | 461 | 阵容确认、战术调整 |
| 比赛实况 | `match_live.lua` | 858 | 逐事件播放、实时统计、换人/战术干预 |
| 赛后结果 | `match_result.lua` | 679 | 技术统计对比、评分、事件回放 |
| 收件箱 | `inbox.lua` | 705 | 分类筛选、优先级、动作按钮、上下文跳转 |
| 新闻 | `news.lua` | 404 | 新闻卡片列表、分类、关联跳转 |
| 转会市场 | `market.lua` | 1,073 | 搜索/筛选/出价/租借/自由签约 |
| 全球转会中心 | `transfer_hub.lua` | 545 | 世界转会动态、传闻、到期球员 |
| 职员 | `staff.lua` | 493 | 当前职员/可雇佣/雇佣/解约/加成展示 |
| 球探 | `scouting.lua` | 534 | 球探总览/球员搜索/指派/报告 |
| 青训 | `youth.lua` | 516 | 青训列表/候选招募/提拔 |
| 球队详情 | `team_detail.lua` | 514 | 概览/阵容/历史/统计(查看任意球队) |
| 经理 | `manager_view.lua` | 207 | 经理资料/履历/声望 |
| 赛季结算 | `season_end.lua` | 479 | 排名/奖项/奖金/评价/升降级/进入新赛季 |
| 名人堂 | `hall_of_fame.lua` | 238 | 历史冠军/奖项/传奇球员 |
| 设置 | `settings.lua` | 343 | 音量/字号/货币/自动保存 |

### UI 可复用组件

| 组件 | 文件 | 说明 |
|------|------|------|
| 底部抽屉 | `ui/components/bottom_sheet.lua` | 通用底部滑出面板 |
| 确认对话框 | `ui/components/confirm_dialog.lua` | 是/否确认弹窗 |
| 覆盖层管理 | `ui/components/overlay_manager.lua` | 全局覆盖层队列 |
| 球员卡片 | `ui/components/player_card.lua` | 球员信息复用卡 |

---

## 对照计划完成度

### FEATURE_GAP_PLAN 进度（对标 soccermanager TypeScript 实现）

| Phase | 内容 | 状态 | 完成日期 |
|-------|------|------|---------|
| A | 比赛交互增强（赛前确认/换人/战术/半场调整） | ✅ 完成 | 2026-05-26 |
| B | 谈判系统（多轮转会/自由球员FSM/合同终止） | ✅ 完成 | 2026-05-26 |
| C | 赛季结构（升降级/赛季阶段/转会窗） | ✅ 完成 | 2026-05-26 |
| D | 经济系统增强（财务恢复/阻断器/快进/阵容安全/财务健康） | ✅ 完成 | 2026-05-27 |
| E | 球员深度（消息决策/个人士气/阵容角色/训练分组/职业历史） | ✅ 完成 | 2026-05-27 |
| F | 辅助系统（青训球探/设施升级/新闻发布会/货币） | ⚠️ 部分完成 | — |

**Phase F 细项**:
- ✅ 青训球探（区域/目标）— 已实现
- ✅ 货币系统（EUR/GBP/USD 切换）— 已实现
- 🔲 设施升级 — 未实现
- 🔲 赛后新闻发布会 — 未实现

### REFINED_REBUILD_PLAN 进度

| Phase | 内容 | 状态 | 说明 |
|-------|------|------|------|
| B1 | 经营闭环基础（财务/合同/训练/消息/多存档/设置） | ✅ 完成 | 全部 6 项已实现 |
| B2 | 世界动态性（董事会/士气/职员/球探/青训/求职/随机事件/声望） | ✅ 完成 | 全部 8 项已实现 |
| B3 | 赛季完整性（奖项/历史/球员特性/转会增强/新闻增强/AI增强） | ✅ 完成 | 全部 6 项已实现 |
| B4 | 比赛引擎 v2（逐分钟/战术/报告） | 🔲 未开始 | 当前使用占位引擎 |
| U1 | 核心交互循环（阵容/球员/训练/财务/设置/存档 UI） | ✅ 完成 | 全部 6 项已实现 |
| U2 | 信息反馈层（收件箱/新闻/职员/球探/青训/Dashboard/导航 UI） | ✅ 完成 | 全部 7 项已实现 |
| U3 | 完整经营界面（球队/经理/赛季结算/名人堂/转会/战术/转会中心 UI） | ✅ 完成 | 全部 7 项已实现 |
| U4 | 比赛 UI（实时比赛/赛后报告） | ✅ 完成 | 基于占位引擎的完整 UI |

---

## 总体完成度评估

| 维度 | 完成度 | 说明 |
|------|--------|------|
| 后端逻辑（不含比赛引擎v2） | **~95%** | 所有经营系统已实现，仅缺设施升级和赛后发布会 |
| UI 页面 | **~90%** | 26 个页面全部实现，深度和交互完整 |
| 比赛引擎 | **~40%** | 占位引擎可用但缺乏战术深度 |
| 整体游戏可玩性 | **~85%** | 可完整玩多个赛季，核心循环完整 |

---

## 已验证的核心玩法循环

```
新游戏 → 创建经理 → 选择球队 → 进入仪表盘
  ↓
查看阵容 → 调整战术 → 设置训练 → 管理转会
  ↓
推进日期 → [比赛日] → 赛前确认 → 观看比赛 → 赛后结果
         → [非比赛日] → 训练/球探/青训/谈判/随机事件
  ↓
赛季结束 → 结算(奖项/升降级/奖金) → 进入新赛季
  ↓
存档 / 读档 / 继续
```

---

## 下一步待做

### 优先级高（提升核心体验）

1. **比赛引擎 v2** — 逐分钟事件模拟，战术/阵型/球员属性真正影响结果
2. **设施升级** — 训练/医疗/球探设施等级影响各系统加成
3. **赛后新闻发布会** — 选择回应，影响士气/声望

### 优先级中（体验打磨）

4. UI 动画和过渡效果优化
5. 更丰富的新闻模板和叙事深度
6. 球员特性对比赛引擎的影响（需 B4 支撑）

### 优先级低（锦上添花）

7. 更多联赛（葡超、荷甲等）
8. 国际比赛扩展（洲际赛事）
9. 教程/新手引导

---

## 技术债务

| 问题 | 严重度 | 说明 |
|------|--------|------|
| `transfer_manager.lua` 1477行 | ⚠️ 中 | 接近拆分阈值，可考虑分离谈判状态机 |
| `player_detail.lua` 1208行 | ⚠️ 中 | 多标签页可拆为独立子模块 |
| `market.lua` 1073行 | ⚠️ 低 | 功能集中，暂可接受 |
| 占位比赛引擎 | ⚠️ 高 | 是下一阶段的核心改进点 |

---

*文档版本: v1.0*
*创建日期: 2026-05-27*
