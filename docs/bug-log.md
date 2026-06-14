# OpenFoot Manager - Bug 记录

**版本**: v1.1  
**维护说明**: 按日期记录发现、修复与验证的 Bug 及功能需求，最新日期在上  
**最后更新**: 2026-06-13

---

## 总表

> 全部 Bug / 需求一览；详情见下方 [Bug 记录](#bug-记录)。状态/优先级以正文为准，本表随条目更新。

### 已修复

| 编号 | 类型 | 严重程度 | 标题 | 要点 |
|------|------|----------|------|------|
| [BUG-20260613-02](#bug-20260613-02--中超联赛数据财务声望能力档位错误) | Bug | P1 | 中超数据档位错误 | 周薪≈预算×9、声望/能力偏高；初始 rep550+财务对齐+OVR≤73 |
| [REQ-20260613-01](#req-20260613-01--传奇球员补充名单防守向25人) | 需求 | P2 | 传奇补充名单 | Top50 偏进攻；defenders_30.json 25 人 + legends_loader 合并抽卡池 75 人 |
| [BUG-20260613-01](#bug-20260613-01--传奇球员转世名字匹配失效) | Bug | P1 | 转世名字匹配失效 | 中文名对不上导致永不触发；_reincarnationsDone 存档；reincarnation_test |
| [BUG-20260611-01](#bug-20260611-01--董事会月度目标不生效) | Bug | P1 | 董事会月度目标不生效 | 真实月度统计替代随机判定；达成/失败联动 boardSatisfaction ±5/-3；废弃死字段 boardConfidence |
| [BUG-20260611-02](#bug-20260611-02--赛季董事会目标颗粒度太粗) | Bug | P2 | 赛季董事会目标颗粒度太粗 | effective tier 取声望/联赛分位更保守档；升班马上限 weak；双系统目标同步 |
| [REQ-20260612-05](#req-20260612-05--比赛直播替补席显示体力) | 需求 | P2 | 替补席显示体力 | 换人/选人面板替补与场上统一体力条；读 gameState.players fitness |
| [REQ-20260612-04](#req-20260612-04--阵容页两套阵容保存) | 需求 | P2 | 两套阵容保存 | lineupPresets A/B + 阵容页切换/保存/脏提示；纳入 Team 存档 |
| [REQ-20260612-03](#req-20260612-03--时间推进决策类阻断统一p0p1) | 需求 | P1 | 决策类阻断统一 | 7 类 warn 基于业务状态；移除 inbox 扫信；市场/大名单深链 |
| [REQ-20260612-01](#req-20260612-01--定位球系统-fm-风格重构) | 需求 | P2 | 定位球 FM 风格重构 | 三阶段链、主罚推断/战术 UI、特质接入、0.29 球/队/场 |
| [REQ-20260612-02](#req-20260612-02--比赛事件风味与伤病种类统一) | 需求 | P2 | 事件风味/伤病统一 | EventFlavors 9 种伤病+卡牌原因；训练/随机事件复用 |
| [BUG-20260612-02](#bug-20260612-02--赛季总结页奖金排名与金额不符) | Bug | P1 | 赛季总结奖金不对 | 奖金/财务改读赛季历史；recordSeasonEnd 写入财务快照 |
| [BUG-20260612-01](#bug-20260612-01--淘汰赛加时点球缺失世界杯引擎未统一) | Bug | P1 | 淘汰赛加时/点球缺失 | 欧冠决赛无 isKnockout；WC 独立泊松引擎；已统一 MatchEngine + 点球 winner |
| [BUG-20260611-03](#bug-20260611-03--阵容阵型设定存档后丢失) | Bug | P1 | 阵容阵型设定存档后丢失 | 补全 serialize；startingXI 槽位表不再被 compactArray 压实 |
| [BUG-20260611-04](#bug-20260611-04--联赛模拟随机性过强强弱队排名倒挂) | Bug | P1 | 联赛模拟随机性过强 | 保级队夺冠、豪门降级；引擎归一化 + strengthFactor 已修，待长期验证 |
| [BUG-20260611-06](#bug-20260611-06--青训妖人转会后合同被原球队覆盖还原) | Bug | P1 | 妖人转会合同被还原 | 转会后月初 AI 青训提拔覆盖工资/归属；四层修复已合入 |
| [REQ-20260611-07](#req-20260611-07--比赛中换人后赛后仍显示赛前阵容) | 需求 | P1 | 换人后赛后阵容不对 | shadowLineup/ratingLineup 分离；赛后还原 startingXI；出场统计对齐终局名单 |
| [REQ-20260611-05](#req-20260611-05--成长与训练体系优化含正式比赛成长因子) | 需求 | P2 | 成长/训练/出场挂钩 | 22+ quota12→25；AI/玩家同逻辑；训练 UI；micro-growth 不做 |
| [REQ-20260611-02](#req-20260611-02--球队降级时强制玩家经理辞职) | 需求 | P2 | 降级强制辞职 | 顶级联赛降级 → 失业 + 履历 relegated + AI 立即接管；**已验证** |
| [REQ-20260611-03](#req-20260611-03--审查一线队训练成长过慢疑似-bug) | 需求 | P2 | 审查一线队训练过慢 | 非 Bug；`training_pace_test` 量化；设计如此 |
| [REQ-20260611-04](#req-20260611-04--扩展伤病种类含赛季报销极低概率) | 需求 | P3 | 扩展伤病种类 | 9 种+赛季报销+概率微调+系统联动+专项测试 |
| [BUG-20260611-05](#bug-20260611-05--低潜力球员能力可成长至-90-总评) | Bug | P2 | 低潜力 OVR 上限 | getPotentialOverallCap + 钳制 + 赛季末 getAttrCap |
| [BUG-20260611-07](#bug-20260611-07--死敌关系未初始化机制全程不生效) | Bug | P2 | 死敌关系未生效 | team_rivalries 18 对 + 开档/读档初始化；转会/UI/德比上座率 |
| [REQ-20260611-09](#req-20260611-09--青训队球员可转会不含候选) | 需求 | P2 | 青训队可转会 | 青训挂牌/出售/UI；候选不可转；复用 BUG-06 |

### 待处理

| 编号 | 类型 | 状态 | 严重程度 | 标题 | 要点 |
|------|------|------|----------|------|------|
| [REQ-20260611-01](#req-20260611-01--完善租借系统并新增中超第六联赛) | 需求 | 部分完成 | P2 | 完善租借 + 中超 | 租借已闭环；中超 16 队数据+开档可选+欧冠名额；**待开档验证** |
| [REQ-20260611-06](#req-20260611-06--球员场上职责与位置分离) | 需求 | 待排期 | P2 | 球员场上职责 | 进攻/策应/防守职责独立于自然位置；补 UI + 存档；与已有 slotRoles 分层 |
| [REQ-20260611-08](#req-20260611-08--增加可玩次级联赛) | 需求 | 待排期 | P2 | 增加次级联赛 | 英冠/西乙等完整二级联赛：真实数据、赛程、UI、可执教；替代现有抽象储备池 |

---

## 目录

- [总表](#总表)
  - [已修复](#已修复)
  - [待处理](#待处理)
- [使用说明](#使用说明)
- [标签说明](#标签说明)
- [状态说明](#状态说明)
- [Bug 记录](#bug-记录)
  - [2026-06-13](#2026-06-13)
    - [BUG-20260613-02 中超数据校准](#bug-20260613-02--中超联赛数据财务声望能力档位错误)
    - [BUG-20260613-01 传奇转世名字匹配](#bug-20260613-01--传奇球员转世名字匹配失效)
    - [REQ-20260613-01 传奇补充名单](#req-20260613-01--传奇球员补充名单防守向25人)
  - [2026-06-12](#2026-06-12)
  - [2026-06-11](#2026-06-11)
- [记录模板](#记录模板)
- [关联文档](#关联文档)

---

## 使用说明

1. **新增记录**：在 [Bug 记录](#bug-记录) 最上方添加当日日期标题（若当日尚无章节），按 [记录模板](#记录模板) 填写；同步更新文首 [总表](#总表)。
2. **更新状态**：修复或验证后，更新对应条目的「状态」「修复说明」「关联提交」等字段，并同步 [总表](#总表)（已修复移入 [已修复](#已修复) 组，待处理保留 [待处理](#待处理) 组），不要删除历史记录。
3. **编号规则**：
   - Bug：`BUG-YYYYMMDD-NN`（例：`BUG-20260611-01`）
   - 功能需求：`REQ-YYYYMMDD-NN`（例：`REQ-20260611-01`）
   - 同一自然日内从 `01` 递增
4. **严重程度**：
   - **P0** — 崩溃、存档损坏、核心流程不可用
   - **P1** — 主要功能异常，有明确 workaround
   - **P2** — 次要功能或 UI 问题
   - **P3** — 文案、样式、边缘场景

---

## 标签说明

每条记录可打多个标签，用 `标签` 字段标注（逗号分隔）。

| 标签 | 适用范围 |
|------|----------|
| `机制` | 系统逻辑错误、流程断裂、规则未生效 |
| `数值` | 平衡性、成长曲线、随机波动、经济参数 |
| `存档` | 序列化/反序列化、读档丢数据、存档损坏 |
| `UI` | 界面展示、交互、文案显示 |
| `内容` | 数据缺失、联赛/球队/球员覆盖不足 |
| `性能` | 卡顿、内存、加载耗时 |
| `测试` | 测试用例过时、覆盖不足 |

类型字段区分 **Bug**（现有功能异常）与 **需求**（新功能或内容扩展）。

---

## 状态说明

| 状态 | 含义 |
|------|------|
| 待确认 | 已报告，尚未复现或定性 |
| 已确认 | 可稳定复现，待修复 |
| 修复中 | 已有负责人或 PR 在处理 |
| 已修复 | 代码已合入，待验证 |
| 已验证 | 修复经测试或人工确认 |
| 非 Bug | 预期行为、测试过时或误报 |
| 暂缓 | 已知但暂不处理，需注明原因 |
| 待排期 | 功能需求，尚未纳入开发计划 |
| 方案已定 | 需求/优化方案已确认，待开发 |

---

## Bug 记录

> 以下按日期倒序排列（最新在前）。

### 2026-06-13

#### BUG-20260613-02 · 中超联赛数据财务/声望/能力档位错误

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 数值, 内容, 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/data/real_data_loader.lua`、`assets/Data/fm2024_csl.json`、`docs/fm2024_csl.json` |
| 发现人 | 玩家反馈 / 数据审查 |
| 修复人 | AI |

**现象**

勾选「中超联赛」开档后，财务与能力档位与第六联赛定位严重不符：

1. **周薪爆表**：16 队全队实际周薪均为工资预算的 **7~12 倍**（如山东泰山预算 84 万/周、全队约 997 万/周）；个别外援周薪（UI **104 万/周**）高于英超顶薪（约 **40.8 万/周**）
2. **声望偏高**：按 `wage_budget` 对数映射约 **610~685**，高于英超保级队下限（约 **653**）；JSON `reputation`（118~210）被 `_assignPlayStyle` 误用，导致 AI 战术偏保守
3. **能力偏高**：属性经 `calculateOverall` 重算后最高 **91**，78 人 OVR ≥ 75，整体接近五大联赛中上游

**复现步骤**

1. 新游戏勾选「中超联赛」，选任意中超球队开档
2. 财务页查看工资预算利用率（>100%）或尝试免签（`checkWageBudget` 失败）
3. 对比同一存档内英超保级队与山东泰山的球队声望、顶薪球员 OVR

**期望行为**

- 中超作为可选 **第六联赛**：初始球队声望顶级约 **550**（低于五大联赛），赛季内仍可通过 `ReputationManager` 升降（500~950）
- 工资预算、转会预算、余额与初始声望同档；全队周薪约为预算的 **~80%**
- 联赛内球员 OVR **最高低于 75**，相对实力保留、整体弱于五大联赛

**实际行为**

- 球员 `wage` 约为 `market_value × 7%` 量级（五大联赛约 **0.2%**），开档即超预算
- 财务仍按 JSON `wage_budget`（47~84 万/周）导入，与失真周薪不匹配
- OVR 与五大联赛主力同档，转会市场议价失真

**根因分析**

1. 中超 JSON 为独立生成，球员周薪公式与 FM 五大联赛导出尺度不一致（约 **50×** 的 wage/market_value 比）
2. 球队 `wage_budget` 虽低于英超，但仍映射出 **610+** 声望；未做联赛层级封顶
3. 球员属性未按第六联赛上限裁剪；导入时 `calculateOverall()` 覆盖 JSON `ovr`，原字段不可信

**修复说明**

1. **`real_data_loader.lua`（中超专用）**
   - `_buildCSLReputationMap`：按 JSON 球队档次排名，**初始**声望顶级 **550**，每降一名 **-3**（505~550）；赛季中仍可变动，`_baseReputation` 仅作开档基准
   - `_reputationToWageBudget`：由初始声望反推 `wageBudget` / `balance`（×80）/ `transferBudget`（×25）
   - `_normalizeCSLPlayerWages`：导入时将各队球员周薪缩放至工资预算 **80%** 利用率
   - `_assignPlayStyle` 改用计算后的声望，不再读 JSON 无效 `reputation`
2. **`fm2024_csl.json`（`assets/Data/` + `docs/`）**
   - 同步写入校准后的 `reputation`、`wage_budget`、`transfer_budget`、球员 `wage`
   - 全库属性统一缩放（系数 **≈0.833**），使 `calculateOverall` 后 **最高 OVR 73**（<75）；`potential` 同步封顶并保留与原 OVR 的潜差

**校准后参照（山东泰山）**

| 项目 | 修复前 | 修复后 |
|------|--------|--------|
| 初始球队声望 | ~685 | **550** |
| 工资预算/周 | 84 万 | **29.4 万** |
| 转会预算 | （JSON 无效） | **736 万** |
| 全队周薪/预算 | ~1190% | **~80%** |
| 最高球员 OVR | 91 | **73** |

**验证方式**

- [x] 数据审查：16 队声望 505~550；无 OVR ≥ 75；全队周薪/预算 ≈ 80%
- [ ] 手动：勾选中超开档，财务页预算利用率正常，可完成免签/续约
- [ ] 手动：完整赛季 + 转会窗 AI/玩家引援无工资预算全面锁死
- [ ] 手动：赛季末声望可因排名上升（`ReputationManager.seasonEndUpdate`）

**关联**

- 提交/PR：
- 相关记录：[REQ-20260611-01](#req-20260611-01--完善租借系统并新增中超第六联赛)
- 备注：身价 `market_value` 进档后由 `Player:calculateValue` 重算；JSON 内旧身价字段可能滞后

---

#### BUG-20260613-01 · 传奇球员转世名字匹配失效

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制, 存档, 内容 |
| 状态 | 已验证 |
| 严重程度 | P1 |
| 模块 | `scripts/systems/reincarnation_manager.lua`、`scripts/core/game_state.lua`、`scripts/systems/season_manager.lua` |
| 发现人 | 代码审查 |
| 修复人 | AI |

**现象**

梅西/C罗等传奇退役后，赛季结算的转世逻辑 **从不触发**。设计文档称「构建通过」，但运行时名字对不上：`nameMatches` 仅比对英文 `displayName`，而 `real_data_loader` 加载的传奇球员为中文名（如「莱昂内尔·梅西」），且未使用 `legendName`（如 `L. Messi`）。

**复现步骤**

1. 开档加载含梅西/C罗的传奇数据，将其效力至退役
2. 赛季结算完成 `_processRetirements` 后观察是否生成 16 岁青训转世球员
3. 检查 inbox 与 `gameState._reincarnationsDone`

**期望行为**

- 名单内传奇 **本赛季退役** 后，在有空余青训名额的随机球队生成 16 岁同名新星（潜力梅西 99 / C罗 96，能力 70–78）
- 每名传奇全局仅转世一次；读档不重复
- **不发送**「天才新星出现」类全局消息（按设计决议）

**实际行为**

- 名字匹配恒为 `false`，转世分支永不执行
- `_reincarnationsDone` 仅内存存在，未写入 `GameState:serialize`，同赛季读档可能重复转世
- 转世未检查 `MAX_YOUTH_SQUAD`，满员球队仍可能被塞人

**根因分析**

1. `nameMatches` 与真实 `displayName` / `legendName` 数据源不一致
2. 存档序列化遗漏 `_reincarnationsDone`
3. 初版使用假名（里奥·梅西尼等）与后续产品决议不符

**修复说明**

1. **`reincarnation_manager.lua`**：`matchAltNames` 补中文全名；`nameMatches` 增加 `legendName`、`lastName`；继承退役球员原名/国籍/位置；潜力梅西 99、C罗 96；能力 `RandomInt(70,78)`；`pickRandomTeam` 仅选 `#_youthPlayerIds < 18` 的球队；移除转世全局消息
2. **`game_state.lua`**：`_reincarnationsDone` 纳入 serialize / deserialize
3. **`tests/reincarnation_test.lua`**：名字匹配、触发、防重复、存档往返

**验证方式**

- [x] `tests/reincarnation_test.lua` 22 项通过（中文名匹配、潜力、原名、无 inbox、满员跳过、存档往返）
- [ ] 手动：梅西/C罗退役后下赛季在随机球队青训可见同名 16 岁球员

**关联**

- 提交/PR：
- 相关记录：无
- 备注：转世名单仍硬编码 2 人（梅西、C罗）；扩展名单需改 `REINCARNATION_LIST`

---

#### REQ-20260613-01 · 传奇球员补充名单（防守向25人）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 内容, 机制 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `assets/Data/legends_alltime_defenders_30.json`、`scripts/data/legends_loader.lua`、`scripts/systems/youth_manager.lua` |
| 发现人 | 玩家反馈 / 数据审查 |
| 修复人 | AI |

**现象**

`legends_alltime_top50.json` 传奇池进攻向占比过高（ST/CAM/LW/RW 约 62%），门将仅 2 人、后腰 CDM 主位置为 0，防守球员抽卡体验失衡。

**需求说明**

1. 新增补充传奇数据，以 **门将 / 后卫 / 后腰** 为主
2. 与 Top50 合并进入青训传奇抽卡池，去重键为 `full_name_cn`
3. 仅保留游戏运行时资产与 Lua 加载器，不引入代码生成脚本进仓库

**最终名单（25 人）**

| 位置 | 人数 | 代表球员 |
|------|------|----------|
| GK | 4 | 卡西利亚斯、舒梅切尔、佐夫、卡恩 |
| CB | 10 | 内斯塔、普约尔、耶罗、德塞利、科曼、萨默尔、卢西奥、费迪南德、布兰科、斯塔姆 |
| LB/RB | 4 | 拉姆、阿尔维斯、马塞洛、阿什利·科尔 |
| CDM | 6 | 里杰卡尔德、维埃拉、马克莱莱、基恩、雷东多、加图索 |
| ST | 1 | 费尔南多·托雷斯 |

合并后传奇池 **75 人**（50 + 25）。迭代中曾加入又移除：布斯克茨、邓加、西雷阿、帕萨雷拉、布莱特纳、诺伊尔、拉莫斯、席尔瓦、阿隆索、卡塞米罗、卡洛斯·阿尔贝托等。

**修复说明**

1. **`assets/Data/legends_alltime_defenders_30.json`**：25 人数据（文件名保留 `_30` 历史命名，实际 25 人）
2. **`scripts/data/legends_loader.lua`**：`loadAllPlayers()` 合并 Top50 + 补充 JSON；cache 不可用时回退 `assets/` 直读（开发/测试）
3. **`youth_manager.lua`**、`settings.lua`、`migrations.lua`：传奇池加载改走 `LegendsLoader`

**验证方式**

- [x] 与 Top50 无重名；合计 75 人
- [ ] 手动：青训抽卡可抽到补充名单球员（如托雷斯、维埃拉）
- [ ] 手动：设置页补偿传奇可选补充池球员

**关联**

- 提交/PR：
- 相关记录：无
- 备注：补充球员暂无 `legend_image_registry` 卡面图；开发用 `generate_*.py` / `validate_*.py` 已删除，后续直接改 JSON

---

#### REQ-20260611-02 · 审查确认（降级强制辞职）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/season_manager.lua`、`scripts/systems/job_manager.lua` |
| 发现人 | — |
| 修复人 | —（文档同步） |

**说明**

排期表曾标「待排期」；代码审查确认 **2026-06-12 已合入**，非待开发项。实现入口：`SeasonManager._processPromotionRelegation` → `JobManager.handleRelegation`。

**设计决议（已落地）**

- 仅 **顶级联赛** 降级触发强制解约；二级储备池降级不触发（当前无玩家执教次级路径）
- 玩家降级后 **不可** 继续执教原球队；需重新求职
- `_cheatAutoPlay` 跳过玩家降级与强制辞职

**验证补充（2026-06-13）**

- [x] 代码路径：`handleRelegation` 写 `reason = "relegated"`、清 `playerTeamId`、`_isUnemployed`、立即 `_aiHireManager`
- [x] `tests/rivalry_relegation_test.lua` 覆盖单元 + 升降级集成 + 读档 + 作弊保护
- [ ] 手动端到端：完整赛季故意降级，经理页「自由身」+ 求职中心可用

**关联**

- 正文：[REQ-20260611-02 · 球队降级时强制玩家经理辞职](#req-20260611-02--球队降级时强制玩家经理辞职)
- 相关记录：REQ-20260611-08（次级联赛可玩 — 落地后需再评估降级后是否允许自愿留队或次级开档）

---

### 2026-06-12

#### REQ-20260612-04 · 阵容页两套阵容保存

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | UI, 机制, 存档 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/ui/screens/squad.lua`、`scripts/domain/team.lua`、`scripts/persistence/save_manager.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

当前阵容页仅维护一套首发 XI（`startingXI`）、替补（`benchIds`）与阵型；面对不同对手或主客场策略时，玩家需每次手动调整，无法快速切换预设。

**需求说明**

1. 阵容页支持 **两套** 阵容方案（建议命名「方案 A / 方案 B」，或「主场 / 客场」）
2. 每套方案独立保存：阵型（`formation` / `formationVariant`）、首发槽位（`startingXI`）、替补名单（`benchIds`）、可选职责/主罚等战术附属字段（与现有 `slotRoles` / 定位球主罚字段对齐）
3. UI：保存当前方案、一键切换方案、切换时提示未保存变更（若有）
4. 两套方案随球队 **存档持久化**；读档后方案内容不丢失
5. 赛前/战术页可引用当前激活方案，或允许指定本场使用 A/B（实现时可二选一，优先阵容页切换即可）

**期望行为**

玩家可在阵容页配置并保存两套完整阵容，一键切换后立即反映到 `team.startingXI` 等字段，无需重复拖拽排阵。

**根因分析**

非 Bug。`Team` 模型与 `squad.lua` 仅支持单套阵容状态，无 preset / lineup slot 抽象。

**修复说明**

（2026-06-12 已合入）

1. **`team.lua`**：新增 `lineupPresets`（`A` / `B`）与 `activeLineupPreset`；`captureLineupSnapshot` / `applyLineupSnapshot` / `saveActiveLineupPreset` / `switchLineupPreset` / `isLineupPresetDirty`；每套含 `formation`、`formationVariant`、`startingXI`、`benchIds`、`slotRoles`、`playerDuties`、队长/定位球主罚；随 `Team:serialize` 持久化
2. **`squad.lua`**（俱乐部模式）：阵容页顶部「方案 A / 方案 B / 保存方案」；未保存变更显示 `*`；切换时 BottomSheet 提供「保存并切换 / 放弃并切换」；切换后立即写入 `team.*` 活跃字段
3. **范围**：国家队模式不展示 A/B（仍用 `WorldCup.saveNationalTeamSettings`）；战术页编辑后回阵容页保存即可，无需赛前单独指定方案

**验证方式**

- [x] 分别保存 A/B 两套不同阵型+首发+替补，切换后 UI 与 `team.*` 字段一致（`Team.switchLineupPreset`）
- [x] 存档读档后两套方案均保留（`GameState` 往返）
- [x] 单元测试：`tests/squad_save_test.lua` §4–§5（preset 切换 + 存档往返）
- [ ] 手动：战术页改阵后回阵容页，脏标记与切换提示

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-03（单套阵容存档丢失，已修；本需求为 **多套** 扩展）
- 备注：旧存档首次打开时 `ensureLineupPresets` 以当前阵容初始化 A/B（内容相同）；与 AI 自动选阵无冲突（仅玩家球队 preset）

---

#### REQ-20260612-05 · 比赛直播/换人界面替补席显示体力

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | UI, 机制 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/ui/screens/match_live.lua`、`scripts/match/match_session.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

比赛直播换人时，场上球员列表已显示体力条与百分比（`fitness`），但 **替补席列表** 仅展示位置、姓名、总评，无体力信息。玩家无法判断替补谁状态更好，容易换上已消耗体力的球员（尤其先前被换下又可能再次上场，或模拟过程中替补体能已变化）。

**复现步骤**

1. 进入玩家比赛直播，打开换人面板
2. 对比「场上球员」与「替补席」行 UI
3. 观察替补是否显示 `fitness` / 体力条

**期望行为**

- 换人界面的替补席与场上球员采用 **一致的体力展示**（体力条 + 百分比，颜色分级：绿/黄/红）
- 若比赛引擎在模拟过程中更新替补球员 `fitness`，UI 应读取 **实时** 值（与 `session.bench` 中球员对象同步）
- 常规直播替补列表（非换人模式）可选同步展示，至少换人决策场景必须可见

**实际行为**

`match_live.lua` 替补行（约 L821–842）仅渲染位置、姓名、OVR；无 `fitness` 字段展示。

**根因分析**

非 Bug。换人 UI 初版只给场上球员做了体力条，替补区为简化预览，未接入 `player.fitness`。

**修复说明**

（2026-06-12 已合入）

1. **`match_live.lua`**：抽取 `_playerFitness` / `_buildFitnessNameColumn` / `_buildFitnessLabelColumn`，场上与替补共用
2. **换人面板**（`subs`）：替补席预览行改为与场上相同布局（体力条 + 百分比，绿/黄/红）
3. **选人面板**（`sub_pick`）：替补候选行替换原 OVR 列，同样展示体力；优先读 `gameState.players[id].fitness` 以保证比赛中实时值
4. **`match_session.lua`**：无改动（替补名单仍为 `gameState.players` 引用，引擎更新 fitness 后 UI 自动同步）

**验证方式**

- [ ] 手动：换人面板替补显示体力；低体力球员呈红色警示
- [ ] 手动：比赛中换入替补后，该球员体力随比赛推进下降，再次打开换人面板数值已更新
- [x] 回归：场上球员体力展示逻辑复用同一组件，布局一致
- [ ] 常规直播非换人模式替补列表（当前无独立替补区，换人场景已覆盖）

**关联**

- 提交/PR：
- 相关记录：REQ-20260611-07（换人后终局阵容/统计，已修；本需求为 **换人决策 UI**）
- 备注：被换下球员当前不回到 `session.bench` 列表（既有行为，非本项范围）

---

#### REQ-20260612-01 · 定位球系统 FM 风格重构

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, 数值, UI, 测试 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/match/set_piece_resolver.lua`、`scripts/match/match_engine.lua`、`scripts/match/trait_effects.lua`、`scripts/ui/screens/tactics.lua`、`scripts/ui/screens/match_live.lua`、`scripts/ui/screens/match_result.lua` |
| 发现人 | 设计审查 / 玩家体验 |
| 修复人 | AI |

**现象**

旧版定位球通道为「每分钟 0.4% 触发即进球」，不区分主罚人、发球质量与终结检定；`dead_ball` 仅影响球队触发倍率，点球子类型与点球大战逻辑割裂；`team.penaltyTaker` 等字段存在但从未被引擎读取。

**需求说明**

参考 FM「专人主罚 + 分阶段检定」，在保留逐分钟抽象模拟的前提下：

1. 运行时合成 FK/CR/PK 能力（不新增存档属性）
2. 战术屏指定点球/任意球/角球主罚（首发+替补），未指定则按合成能力自动推断
3. 定位球机会 → 发球质量 → 终结检定 → 进球/扑救/中柱/射偏
4. 场内点球与点球大战共用 `SetPieceResolver.takePenalty`
5. 全场定位球进球期望锚定 ~0.28–0.42/队/场

**修复说明**

（2026-06-12 已合入）

1. **新增 `set_piece_resolver.lua`**：`synthSkill`（FK/CR/PK）、`resolveTaker` / `autoAssign`、`pickAerialFinisher`、`aerialDefense`（防空取最佳 3 人均值；**空霸/力量怪兽/铜墙铁壁**防守端加成）
2. **`match_engine.lua`**：替换旧 `setPieceChance` 触发即进；机会率 0.012/分钟/队；类型 角球 52% / 任意球 33% / 点球 9% / 乌龙 6%；三阶段链 + `modifyGoalChance(isSetPiece)` 接入；事件字段 `isSetPiece` / `setPieceKind` / `takerId`
3. **`trait_effects.lua`**：`setPieceMult` 上限 1.45→1.25，避免与合成能力双重叠乘
4. **`tactics.lua`**：定位球主罚卡片 + 选人弹窗 + 自动分配（复用 `penaltyTaker` / `freeKickTaker` / `cornerTaker`）
5. **UI**：`match_live` / `match_result` 区分角球/任意球/点球/乌龙解说与标签

**验证方式**

- [x] `tests/set_piece_test.lua`：1200 场蒙特卡洛，定位球 **0.290/队/场**（目标 0.28–0.42）；`dead_ball` 回归 +1.26×
- [x] `tests/match_engine_test.lua`、`ovr_gap_calibration_test.lua`、`comprehensive_balance_sim_test.lua` 回归通过
- [ ] 手动：战术页指定主罚后，直播/赛后进球事件显示对应主罚/开球者

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-04（定位球与实力无关保底进球，阶段 B 已做 OVR 缩放；本项为架构级重构）
- 备注：FM 导入 `penalty_taker` 等 JSON 字段当前全为 null，主罚来源为自动推断；将来数据补全可覆盖

---

#### REQ-20260612-02 · 比赛事件风味与伤病种类统一

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, UI, 内容, 测试 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/match/event_flavors.lua`、`scripts/match/match_engine.lua`、`scripts/systems/training_manager.lua`、`scripts/core/turn_processor.lua`、`scripts/systems/random_event_manager.lua`、`scripts/match/placeholder_engine.lua`、`scripts/ui/screens/match_live.lua`、`scripts/ui/screens/match_result.lua` |
| 发现人 | 玩家体验 / 设计审查 |
| 修复人 | AI |

**现象**

比赛解说模板偏少（每种 3–4 条）；伤病仅有「受伤 + N 天」；黄红牌无原因；训练伤病、随机事件伤病、比赛伤病各自独立抽样，种类与天数可能矛盾（如「脚趾骨裂 3 天」）。

**需求说明**

1. 统一伤病风味库：9 种类型 × 3 档严重程度（轻伤/中度/重伤），天数由类型区间决定
2. 黄/红牌附带原因（鲁莽铲球、战术犯规、破坏得分机会等）
3. 扩展各事件解说模板（定位球进球、点球扑出/射失、带原因卡牌、带伤情伤病等）
4. 全工程伤病生成复用 `EventFlavors.rollInjury(maxDays?)`

**修复说明**

（2026-06-12 已合入）

1. **新增 `event_flavors.lua`**：`rollInjury(maxDays)`（可选上限排除最短恢复期超限的重伤类型并截断天数）、`rollCardReason`、`severityForDays`
2. **比赛引擎**：伤病/卡牌事件写入 `injuryKind`/`injurySeverity`/`cardReason` 等字段；点球未进区分 `save`+`isPenalty` 与射失
3. **统一调用方**：
   - 比赛：`match_engine` → `rollInjury()`（无上限，可出 60 天重伤）
   - 日常训练：`training_manager` → `rollInjury(14)`
   - 回合训练：`turn_processor` → `rollInjury(trainingMods.injuryDaysMax)`
   - 随机事件：`random_event_manager` → `rollInjury(21)`（删除 `_randomInjury` 硬编码名单）
   - legacy：`placeholder_engine._generateInjuryEvents` 同步（当前无调用方）
4. **UI/消息**：`match_live` 解说 60+ 条；`match_result` 伤病行显示种类；赛后消息带「（肌肉拉伤 · 中度）」

**验证方式**

- [x] `tests/event_flavors_test.lua`：500 次伤病区间/严重度、300 次 `rollInjury(14)` 排除重伤类、卡牌原因合法性、引擎事件字段、防空特质
- [x] `training_pace_test.lua`、`training_participation_test.lua` 回归通过

**关联**

- 提交/PR：
- 相关记录：[REQ-20260611-04](#req-20260611-04--扩展伤病种类含赛季报销极低概率)（种类+严重度+UI 主体；赛季报销与存档字段已于 2026-06-12 收尾合入）
- 备注：球员 `injuryKind` / `injurySeverity` / `injurySeasonEnding` 已随 `Player:serialize` 持久化；赛季报销类型与极低概率见 [REQ-20260611-04](#req-20260611-04--扩展伤病种类含赛季报销极低概率) 收尾说明

---

#### REQ-20260612-03 · 时间推进决策类阻断统一（P0/P1）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, UI |
| 状态 | 已验证 |
| 严重程度 | P1 |
| 模块 | `scripts/systems/time_blocker_manager.lua`、`scripts/systems/transfer_manager.lua`、`scripts/systems/world_cup.lua`、`scripts/systems/job_manager.lua`、`scripts/ui/screens/market.lua`、`scripts/ui/components/blocker_dialog.lua`、`scripts/ui/screens/inbox.lua`、`scripts/core/game_state.lua` |
| 发现人 | 设计审查 / 消息体系审计 |
| 修复人 | AI |

**现象**

推进时间（「继续」/「下一天」）时，多项**必须玩家决策**的业务状态未触发 warn 阻断，玩家可在未确认转会、未回复主帅邀约等情况下跳过；旧逻辑 `_checkUrgentMessages` 扫描收件箱 ≥3 条 high 优先级 info 消息即阻断，与真实待办不一致，且与 inbox 模板重复。

**需求说明**

1. 阻断条件一律基于 **`gameState` 业务状态**，不扫描 inbox
2. **`severity = warn`** 的决策类阻断不可「忽略并继续」
3. 同类多条 pending **合并为一条**阻断文案
4. 每条 warn 提供 **`target` + `targetParams` 深链**至对应操作页
5. 出售/买入/自由球员：**5 天未确认则交易作废**，阻断自然消失（非允许跳过）

**修复说明**

（2026-06-12 已合入，分 P0 / P1 两批）

**P0 — 决策 warn 阻断**

| id | 条件 | 跳转 |
|----|------|------|
| `manager_renewal_pending` | `gameState._managerRenewalOffer` 存在 | `manager_view` |
| `job_offer_pending` | 失业且 `_pendingOffers` 非空 | `manager_view`（`focus=jobs`） |
| `sale_confirmation_pending` | 我方出售 bid `awaiting_sale_confirmation` | `market`（`tab=listed`, `highlightBidId`） |
| `nt_coach_invite_pending` | `_pendingNTCoachOffers.nations` 非空 | `inbox`（`openMessageId`） |

- **移除** `_checkUrgentMessages`（inbox 扫信阻断）
- 失业/国家队类检查置于 `getPlayerTeam()` **之前**，避免无俱乐部时漏检
- **`BlockerDialog`** 支持 `targetParams` 路由

**P1 — 扩展 warn 阻断**

| id | 条件 | 跳转 |
|----|------|------|
| `transfer_sign_pending` | 我方买入 bid `awaiting_confirmation` | `market`（`tab=my_bids`, `highlightBidId`） |
| `free_agent_sign_pending` | 我方 `freeAgentNegos` 中 `awaiting_confirmation` | `market`（`tab=free`, `highlightNegoId`） |
| `nt_squad_unconfirmed` | 已任国家队教练 + `squadConfirmed ~= true` + 距世界杯小组赛开幕 ≤7 天 | `national_squad_select`（`nation`） |

**新增 / 扩展 API**

- `TransferManager.getPendingSaleConfirmations` / `getPendingTransferSignConfirmations` / `getPendingFreeAgentSignConfirmations`
- `JobManager.hasPendingOffers` / `getPendingOfferCount`
- `WorldCup.hasPendingCoachInvite` / `clearPendingCoachInvite` / `daysUntilGroupStageKickoff` / `needsSquadConfirmationBlock`
- 存档：`_pendingNTCoachOffers`、`_managerRenewalOffer*`、`_messageDedupeCache`、`team.boardObjective`、`gameState.objectives`

**UI 深链**

- `market.lua`：出售/买入确认弹窗（`_showOfferSheet` / `_showTransferSignConfirmSheet`）；自由球员 `_showFreeAgentConfirmSheet`
- `inbox.lua`：国家队邀请 accept/decline 后 `clearPendingCoachInvite`
- `blocker_dialog.lua`：补 `manager_view`→「资料」、`national_squad_select`→「大名单」

**验证方式**

- [x] `tests/time_blocker_decisions_test.lua`：P0 三项 + 失业漏检回归 + P1 买入/自由球员/大名单（开幕前 7 天内 / 超 7 天不阻断）
- [ ] 手动：出售/买入待确认 → 阻断 → 深链打开确认面板 → 确认或 5 天超时后阻断消失
- [ ] 手动：世界杯年前 7 天内未锁大名单 → 阻断 → 跳转大名单页

**关联**

- 提交/PR：
- 相关记录：消息模板审计（inbox / MessageManager）；P2 消息注册表重构仍待排期
- 备注：董事会续约提议走 `_managerRenewalOffer` 状态 + warn 阻断，与 inbox 动作 `accept_renewal` / `decline_renewal` 联动；`_messageDedupeCache` 防止读档后董事会目标等消息重复弹出

---

#### BUG-20260612-03 · 读档后荣誉与冠军记录丢失

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 存档, UI, 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/core/game_state.lua`、`scripts/systems/records_manager.lua`、`scripts/ui/screens/trophy_cabinet.lua`、`scripts/ui/screens/manager_view.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

个人资料页、荣誉陈列室中展示的联赛冠军、欧冠、世界杯等冠军与荣誉信息，存档再读档后大量丢失或归零；荣誉室奖杯列表为空，经理生涯统计（联赛/欧冠/世界杯冠军数、最佳排名等）恢复默认。

**复现步骤**

1. 进行若干赛季，取得联赛冠军、欧冠或世界杯等荣誉（运行时荣誉室可正常显示）
2. 保存游戏并退出（或自动存档后重新加载）
3. 打开「我的资料」或「荣誉陈列室」，查看冠军数与奖杯列表

**期望行为**

读档后 `gameState.records` 完整恢复，荣誉陈列室奖杯列表、经理记录（`managerRecords`）、联赛/球员纪录与存档前一致；个人资料页冠军相关展示与运行时一致。

**实际行为**

- `GameState:serialize()` / `deserialize()` **未包含** `gameState.records`（奖杯列表、`managerRecords`、`leagueRecords`、`playerRecords` 等运行时数据）
- 读档后 `RecordsManager._ensureData()` 重建空结构，此前夺冠、破纪录等写入全部丢失
- `RecordsManager.migrateFromHistory()` 虽可从 `worldHistory` 回溯**联赛**冠军，但**从未在读档流程中调用**，且无法恢复欧冠/世界杯等非联赛荣誉
- 个人资料页「冠军」仅显示 `manager.stats.trophies`（且运行时仅联赛夺冠在 `SeasonManager.endSeason` 中 +1），与荣誉室 `records.trophies` 数据源分裂；欧冠/世界杯等荣誉主要依赖 `records`，读档后荣誉室全空

**根因分析**

记录系统数据仅存于内存 `gameState.records`，存档管线遗漏该字段；迁移逻辑未接入 `SaveManager.load` / `GameState:deserialize`；经理 `stats.trophies` 与 `records` 双轨统计未统一，加剧「部分冠军看似还在、荣誉室已空」的体感。

**修复说明**

1. **`GameState:serialize/deserialize`**：持久化 `records`、`_transferHistory`、`_managerHistory`、`_worldCupHistory`、`lastPromotionRelegation`、`_teamRelations`
2. **读档后**：调用 `RecordsManager.migrateFromHistory()`（从 `worldHistory` / `_uclCompletedSeasons` / `_worldCupHistory` 补全缺失奖杯）与 `syncManagerProfile()`（对齐 `manager.stats.trophies`、回填胜场统计）
3. **世界杯夺冠**：`onWorldCupChampionship` 改为比对国家队代码（非俱乐部 `playerTeamId`）；UCL/WC 夺冠同步 +1 `manager.stats.trophies`

**验证方式**

- [x] 单元测试：`tests/records_save_test.lua`（records 往返 + 旧档迁移 + 财务快照）
- [ ] 夺冠后手动存档再读档，荣誉室奖杯数量与类型不变
- [ ] 欧冠/世界杯夺冠后读档，对应奖杯与 `uclTitles` / `worldCupTitles` 保留
- [ ] 旧存档（无 `records` 字段）首次读档可经迁移恢复联赛/欧冠部分荣誉

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-03（同类存档遗漏问题）
- 备注：`worldHistory` 已持久化，可作为旧档迁移数据源之一

---

#### BUG-20260612-02 · 赛季总结页奖金排名与金额不符

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | UI, 机制, 数值 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/ui/screens/season_end.lua`、`scripts/systems/season_manager.lua`、`scripts/systems/finance_manager.lua`、`scripts/systems/history_manager.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

赛季末总结页「联赛奖金分配」区域显示的排名、高亮行与文案金额，与上方「联赛排名」及实际到账奖金不一致。

**复现步骤**

1. 完成一个完整赛季，触发赛季结算（`SeasonManager.endSeason`）并进入赛季总结页
2. 对比 §1 联赛排名卡与 §5 联赛奖金分配卡中「你的球队第 N 名」及奖金数额
3. （可选）查看 §6 财务总结中的赛季总收入是否包含刚发放的联赛奖金

**期望行为**

总结页各区块均展示**刚结束赛季**的数据：排名与 `HistoryManager.getSeasonHistory(targetSeason)` 一致，奖金金额与 `SeasonManager._distributeSeasonPrizes` / `FinanceManager.awardSeasonPrize` 按该排名实发金额一致，财务总结反映该赛季收支（含奖金）。

**实际行为**

- §1 联赛排名：正确使用 `HistoryManager.getSeasonHistory(targetSeason)` 的历史积分榜 ✓
- §5 联赛奖金：使用 **`gameState.league:getTeamPosition(teamId)`**（当前联赛、当前积分榜）。`endSeason` 在展示总结页**之前**已执行 `_startNewSeason`，积分榜已清零重排，导致排名错误（常见为第 1 名或并列乱序），进而 **`Constants.SEASON_END_PRIZE[position]` 金额错误**
- §6 财务总结：读取 `team.seasonIncome` / `team.seasonExpense`，但 `endSeason` 在写入历史前已调用 `FinanceManager.resetSeasonFinance`，赛季收支已归零，与实发奖金不符
- 实发奖金在结算时按**正确**排名发放；问题为 **UI 数据源与结算时机错位**，非发奖逻辑本身

**根因分析**

`season_end.lua` 奖金区与财务区依赖「当前」`gameState` 快照，而赛季总结页在 `SeasonManager.endSeason` 完成（新赛季初始化 + 财务重置）之后才展示；历史排名已在 `HistoryManager.recordSeasonEnd` 中持久化，但 UI 未复用。

**修复说明**

1. **`season_end.lua`**：§5 奖金排名/金额改从 `record.leagues` 历史积分榜读取；冠军展示含 20M 额外冠军奖；§6 财务改读 `record.playerFinance` 快照
2. **`season_manager.lua`**：`HistoryManager.recordSeasonEnd` 提前至 `resetSeasonFinance` 之前执行
3. **`history_manager.lua`**：`recordSeasonEnd` 写入 `playerFinance` 与 `promotionRelegation` 快照

**验证方式**

- [x] 单元测试：`tests/records_save_test.lua`（`playerFinance` 快照）
- [ ] 非冠军排名完成赛季，总结页 §1 与 §5 排名、金额一致
- [ ] 冠军球队：总结页奖金含排名奖 + 冠军额外奖金
- [ ] §6 财务总结显示该赛季总收入（含联赛奖金），非 0

**关联**

- 提交/PR：
- 相关记录：
- 备注：`main.lua` 中 `season_end` 导航发生在 `endSeason` 之后，`params.season = prevSeason`

---

#### BUG-20260612-01 · 淘汰赛加时/点球缺失，世界杯引擎未统一

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/match/match_engine.lua`、`scripts/core/turn_processor.lua`、`scripts/domain/tournament.lua`、`scripts/match/match_session.lua`、`scripts/ui/screens/pre_match.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

欧冠、世界杯等杯赛淘汰赛在 AI 自动模拟（及跳过比赛）中，90 分钟或加时打平后未正确进入点球大战，或点球结果无法决定晋级；欧冠决赛平局时甚至无加时/点球路径。世界杯 AI 模拟使用与联赛/现场比赛不同的简化泊松引擎，体验与质量不一致。

**复现步骤**

1. 推进至欧冠决赛或世界杯淘汰赛（32 强及以后）
2. 让 AI 自动模拟或跳过比赛，制造 90 分钟平局（或欧冠两回合总比分平局）
3. 查看赛果、晋级对阵与 `fixture._penaltyWinner`

**期望行为**

单场淘汰赛：`90 分钟平 → 加时(91–120) → 仍平 → 点球大战`，点球胜者晋级（点球不计入常规比分）。  
欧冠两回合：次回合总比分平 → 加时 + 点球决胜。  
世界杯 AI 模拟与联赛/玩家现场比赛共用同一套 `MatchEngine`。  
未来国内杯单场淘汰 fixture 设 `isKnockout` 即可复用同一逻辑。

**实际行为**

- 欧冠 `Tournament.generateFinal` 未设 `isKnockout`，决赛 90 分钟平局时 `MatchEngine` 不触发加时/点球，晋级逻辑依赖兜底随机
- 欧冠两回合总比分平仅做简化随机点球，无加时，且不走 `MatchEngine._simulatePenaltyShootout`
- 世界杯 AI 路径使用 `TurnProcessor._simulateWCMatch` 独立泊松引擎，与 `MatchSession.newWC` / 联赛引擎分裂
- 点球 `winner` 曾返回 `"home"/"away"` 字符串，与 `_penaltyWinner` 所需的 `teamId` 不一致

**根因分析**

1. 淘汰赛决胜依赖 `fixture.isKnockout` 标志，但欧冠决赛及两回合单场 fixture 未统一标记
2. 世界杯因 `teamId` 为国家代码不在 `gameState.teams`，早期单独实现简化模拟，未复用 `MatchEngine`
3. 点球结果写入路径分散，字段名与 winner 语义不统一

**修复说明**

1. **`MatchEngine`**：`._resolveTeams()` 支持世界杯虚拟国家队；新增 `simulateExtraTimeAndPenalties()`；点球 `winner` 改为真实 `teamId`
2. **世界杯**：删除泊松简化引擎，AI/跳过/自动模拟统一走 `MatchEngine.simulate`（`fixture._isWC`）
3. **欧冠决赛**：`Tournament.generateFinal` + `Tournament.markSingleLegKnockout()` 标记 `isKnockout`（供未来国内杯复用）
4. **欧冠两回合**：次回合总比分平 → `MatchEngine.simulateExtraTimeAndPenalties` + `_storeKnockoutExtras`
5. **`MatchSession` / `pre_match`**：点球大战传入 `fixture` 以解析正确 winner

**验证方式**

- [x] `tests/match_engine_test.lua`：淘汰赛 ET/点球路径 + 点球 winner 必须为 teamId
- [ ] 手动：欧冠决赛 90 分钟平局 → 加时/点球 → 正确晋级
- [ ] 手动：世界杯淘汰赛 AI 模拟平局 → 点球胜者写入 `_penaltyWinner`
- [ ] 手动：玩家现场世界杯淘汰平局 → 点球 UI → 赛后报告显示点球比分

**关联**

- 提交/PR：
- 相关记录：未来国内杯实现时使用 `Tournament.markSingleLegKnockout(fixture)`
- 备注：两回合制单场仍不设 `isKnockout`（允许单回合平局），总比分决胜在次回合 `_applyUCLResult` 处理

---

### 2026-06-11

#### BUG-20260611-01 · 董事会月度目标不生效

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/systems/objectives_manager.lua`、`scripts/core/turn_processor.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

董事会月度目标设置后，达成/失败判定无实际效果，玩家感知为「月度目标形同虚设」。

**复现步骤**

1. 进入新赛季，确认董事会已生成月度目标
2. 推进游戏至月末，刻意达成或失败该目标
3. 观察董事会满意度、预算奖励、消息通知等是否有对应反馈

**期望行为**

月末应正确评估月度目标完成度，并影响董事会满意度、消息提示或相关奖励/惩罚。

**实际行为**

月度目标评估逻辑存在但效果薄弱或未正确挂钩后续系统；`_checkMonthlyCompletion` 仅基于 `recentForm` 做简化检查，与目标文案（如「本月攻入 8+ 球」「本月 2 场零封」）不匹配，导致多数目标无法被正确判定。

**根因分析**

代码审查确认 `onMonthEnd` 调用链完整（`turn_processor` 每月 1 号触发），问题在判定与联动：

1. `_checkMonthlyCompletion` 仅基于 `recentForm`（最多 5 场，非自然月窗口）判定 3 种 form 类目标；零封/进球/射手 3 种目标直接用 **40% 随机数** 占位判定
2. 月度目标达成仅发一条消息，失败完全静默；两者均不影响 `team.boardSatisfaction`
3. 赛季总结读写的 `gameState.boardConfidence` 全代码库从未初始化，是死字段；实际生效的满意度字段是 `team.boardSatisfaction`（`BoardManager` / UI / 解雇链路使用）

**修复说明**

1. **真实月度统计**：新增 `team.monthlyStats`（胜/平/负、进球、失球、零封、逐场结果、球员进球），由 `ObjectivesManager.recordMatchResult` 在每场比赛后累计——联赛走 `PlaceholderEngine.applyResult`，欧冠走 `TurnProcessor._applyUCLResult`。跨月时自动归档为 `_lastMonthlyStats` 供月初评估，赛季重置时清空。`Team` 序列化同步新增两字段
2. **重写 `_checkMonthlyCompletion`**：6 种 `MONTHLY_TEMPLATES` 全部按真实统计判定（连续不败看逐场序列、零封/进球/射手按当月累计），删除随机数占位
3. **满意度联动**：月度达成 `boardSatisfaction +5`、失败 `-3`，均发董事会消息（失败不再静默）
4. **废弃死字段**：`onSeasonEnd` 满意度调整由 `boardConfidence` 改为读写 `team.boardSatisfaction`，赛季总结消息显示真实满意度

**验证方式**

- [x] 单元测试：`tests/objectives_board_test.lua` 覆盖 6 种 `MONTHLY_TEMPLATES` 判定、月度统计累计、月末满意度 +5 联动（14 项全过）
- [ ] 手动：月末达成「本月赢得 3 场比赛」后收到董事会正向反馈
- [ ] 回归：赛季目标与月度目标互不干扰

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-02（赛季目标颗粒度问题，同批修复）
- 备注：根因之一是 `ObjectivesManager` 与 `BoardManager` 两套董事会系统并行不联通，本次通过满意度统一到 `team.boardSatisfaction` + 目标同步（见 02）打通

---

#### BUG-20260611-02 · 赛季董事会目标颗粒度太粗

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制, 数值 |
| 状态 | 已修复 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/board_manager.lua`、`scripts/systems/objectives_manager.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

赛季董事会目标仅按球队声望分档（elite / strong / mid / weak），弱队与中游队也可能被分配「夺冠」等不合理目标。例如诺丁汉森林（英超中下游）仍可能出现联赛冠军级别目标。

**复现步骤**

1. 选择声望处于 mid / weak 档的英超球队（如诺丁汉森林）开档
2. 查看赛季初董事会目标提案或 `team.boardObjective`
3. 对比球队实际实力与联赛竞争格局

**期望行为**

赛季目标应综合声望、上赛季排名、预算、阵容实力等多维因素，为弱旅设定保级/中游等可达目标，避免「森林也要联赛冠军」的违和感。

**实际行为**

`OBJECTIVES` 分档仅依赖 `team.reputation` 阈值（900/800/700/620），`elite` 档包含「夺冠」「前 2 名」「前 3 名」；声望边缘球队可能被划入高档位，或提案 UI 提供了与实力不符的高难度选项。

**根因分析**

目标生成逻辑为粗粒度分档 + 固定候选列表，未参考联赛内相对实力。运行时声望由 `wage_budget` 对数映射（`real_data_loader._calcReputation`，500-950），英超工资整体偏高导致中游队声望膨胀：实测诺丁汉森林 rep≈803 落入 `strong` 档（≥800），默认/随机目标为「前 3 名」「前 4 名」，提案 UI 还因相邻档开放可选「夺冠」。此外 `BoardManager` 与 `ObjectivesManager` 分别生成赛季目标互不同步，玩家看到的目标与解雇评估用的 `team.boardObjective` 可能不一致。

**修复说明**

1. **多维分档**：新增 `BoardManager.computeEffectiveTier(gameState, teamId)`——取「全局声望分档」与「联赛内声望排名分位分档」（前 15% elite / 30% strong / 55% mid / 80% weak / 其余 lowest）中**更保守**的一档；升班马（`team._promotedThisSeason`，由升降级流程标记、新赛季目标生成后清除）首赛季上限 `weak`
2. **统一分档入口**：`BoardManager.generateSeasonObjectives`（AI 球队）、`ObjectivesManager._getTier`（玩家提案/自动目标）、`JobManager` 上任目标生成均改用 effective tier
3. **双系统同步**：新增 `BoardManager.syncFromObjectives`，玩家确认赛季目标后将联赛目标映射写入 `team.boardObjective`（如 `league_survive` →「保级」），评估/解雇链路与玩家所见文案一致
4. **提案 UI 收紧**：`generateProposals` 候选限制在 effective tier ±1 档，弱队提案不再出现「赢得联赛冠军」

**验证方式**

- [x] 单元测试：`tests/objectives_board_test.lua` 模拟英超声望分布，rep=803 中游队 effective tier 为 mid，提案不含联赛冠军；`boardObjective` 与玩家所选目标同步
- [ ] 手动：诺丁汉森林开档，赛季目标为保级或中游
- [ ] 手动：曼城/皇马等 elite 球队仍可拿到争冠级目标

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-01（同批修复）
- 备注：涉及文件 `board_manager.lua`、`objectives_manager.lua`、`season_manager.lua`（升班马标记/月度统计重置）、`job_manager.lua`、`team.lua`、`placeholder_engine.lua`、`turn_processor.lua`

---

#### BUG-20260611-03 · 阵容阵型设定存档后丢失

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 存档, 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/persistence/save_manager.lua`、`scripts/domain/team.lua`、阵容 UI `scripts/ui/screens/squad.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

玩家手动安排的阵型、首发 XI（`startingXI`）、替补（`benchIds`）等阵容设定，存档再读档后恢复为默认或未保存状态。

**复现步骤**

1. 在阵容页面调整阵型（如改为 4-3-3）、手动指定首发 11 人
2. 保存游戏并退出
3. 重新加载该存档，打开阵容页面

**期望行为**

读档后阵型、阵型变体、首发顺序、替补名单、球员场上位置分配应与存档前一致。

**实际行为**

阵容设定未完整持久化，或反序列化时未写回 `team.formation` / `team.formationVariant` / `team.startingXI` / `team.benchIds` 等字段。

**根因分析**

1. `team:serialize()` 遗漏 `formationVariant`、`slotRoles`、`playerDuties`，读档后战术页恢复默认
2. `startingXI` 按阵型槽位 1..11 索引，**允许空洞**；`SaveManager.forEachKnownArray` 将其当作普通数组检测空洞并 `compactArray` 压实，导致槽位与球员错位、存档前后阵容不一致

**修复说明**

1. **`team.lua`**：`serialize/deserialize` 补全 `formationVariant`、`slotRoles`、`playerDuties`；`normalizeIntegerKeyTable` 修复 JSON 字符串键
2. **`save_manager.lua`**：从数组压实白名单移除 `startingXI` / `benchIds`（槽位语义，不可压实）

**验证方式**

- [x] 单元测试：`tests/squad_save_test.lua`（战术字段往返 + 槽位空洞保留）
- [ ] 调整阵型 + 首发 + 球员角色后存档读档，字段完全一致
- [ ] 单元测试：`tests/save_roundtrip_test.lua` 增加阵容字段断言
- [ ] 自动存档与手动槽位均验证

**关联**

- 提交/PR：
- 备注：直接影响比赛日首发阵容，属于核心体验问题

---

#### BUG-20260611-04 · 联赛模拟随机性过强，强弱队排名倒挂

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 数值, 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/match/match_engine.lua`、`scripts/match/tactics_resolver.lua`、`scripts/match/match_session.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | |

**现象**

多赛季模拟中出现极端排名倒挂：保级队变为联赛领头羊，皇马等传统豪门反而降级，整体随机性过强，破坏长期经营的真实感。

**复现步骤**

1. 开档后模拟多个赛季（或使用 `tests/five_season_simulation_test.lua`）
2. 观察各联赛最终排名与球队实力（声望/OVR）的相关性
3. 记录保级队夺冠、豪门降级的频次

**期望行为**

比赛结果应体现球队实力差距，强队长期胜率更高，弱队偶有爆冷但不应成为常态；多赛季后排名分布与实力分布大体一致。

**实际行为**

随机波动权重过大，实力修正不足以锚定强队地位，导致联赛格局失真。

**根因分析**

已研究，详见 [optimization-plan.md § BUG-04](./optimization-plan.md#bug-20260611-04--联赛模拟随机性过强)。核心结论：

1. `tactics_resolver.matchupModifiers` 将实力比 50% 压缩，且 `chanceCreation` 钳制在 [0.55, 1.70]，强队优势被截断、弱队有保底
2. `match_engine` 定位球进球（`setPieceChance=0.004`/分钟）与战术实力无关
3. **攻防量纲失衡**（深挖发现的主因）：`buildTeamContext` 防守权重总和≈进攻的 1.4 倍，OVR 92 队的 attack 低于 OVR 72 队的 defense，20 分实力差在 attack/defense 比值中几乎消失；90 vs 70 强队主场胜率仅 65%、可被弱队 0:5
4. formFactor 在分钟循环内重掷，±18% 单场波动被平均成 ±2%，语义失效

**修复说明**

两批修复均已合入（2026-06-11）：

1. **阶段 A**：chanceCreation 上限 1.70→2.40，撞顶率 100%→约 8%
2. **阶段 B（引擎真实化）**：攻防量纲归一（`DEF_TO_ATK_SCALE=1.40`）、新增 `avgPlayerOverall` 实力差直通项（`strengthFactor`）、formFactor 单场采样、定位球/goalChance 按实力缩放、弱侧大比分护栏（OVR 差≥12 领先 2 球后进球概率指数递减）；二次调参后校准为「差 20 强队主场 ~75%、弱队 ~10%」

效果：90 vs 70 强队主场胜率 65.6%→**77.1%**，弱队 16.5%→**9.0%**，0:5 惨败 0.07%→**0.00%**（3000 场）。详见 [optimization-plan.md § 阶段 B](./optimization-plan.md)。

3. **阶段 C（2026-06-12）**：定位球架构级重构见 [REQ-20260612-01](#req-20260612-01--定位球系统-fm-风格重构)——由「触发即进 + OVR 缩放」改为三阶段链 + 主罚人/特质接入，蒙特卡洛校准 **0.29 定位球进球/队/场**。

**验证方式**

- [x] `balance_diag_test.lua` 验收通过
- [x] `ovr_gap_calibration_test.lua`：OVR 差 0/10/20 强队胜率 39.4% / 65.0% / 76.2%，弱队（差 20）9.0%
- [x] `blowout_upset_test.lua`：弱队 0:5 强队归零，强队净负 3+ 球 0.50%
- [x] 回归：`match_engine_test` / `tactics_resolver_test` / `match_report_test` / `comprehensive_balance_sim_test` / `five_season_simulation_test` 全部通过
- [ ] 用真实 FM 数据跑 20 赛季验证豪门降级率（待做）

**关联**

- 提交/PR：
- 备注：

---

#### BUG-20260611-05 · 低潜力球员能力可成长至 90+ 总评

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 数值 |
| 状态 | 已修复 |
| 严重程度 | P2 |
| 模块 | `scripts/domain/player.lua`、`scripts/systems/potential_system.lua`、`scripts/systems/season_manager.lua`、`scripts/persistence/housekeeping.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

潜力值（PA）约 70 的球员，经训练/比赛成长后总评（OVR）可达到 90 以上，与「潜力决定上限」的设计预期不符。

**复现步骤**

1. 找到 PA ≈ 70 的年轻球员（非传奇）
2. 连续多赛季高强度训练并出场比赛
3. 观察 `player.overall` 及属性变化

**期望行为**

PA 70 的球员应有明确的能力天花板。按当前 `getAttrCap` 设计：`ceil(70/5) = 14` 单项上限，折算总评应显著低于 90（约 75–82 区间）。

**实际行为**

球员 OVR 可突破 90+，疑似总评上限未与潜力挂钩，或成长/训练逻辑绕过了 `getAttrCap` 约束。

**根因分析**

已研究，详见 [optimization-plan.md § BUG-05](./optimization-plan.md#bug-20260611-05--低潜力球员-ovr-可破-90)。核心结论：

1. `getOverallCap()` 固定 99，与潜力脱钩；真正约束来自 `getAttrCap()`（PA70 → 单项 14 → 理论 OVR ≈ 72–79）
2. `actualPotential` 波动可使 PA70 的 attrCap 升至 16（理论 OVR ≈ 90），1/100 种子可触发
3. FM 导入数据不做属性钳制；赛季末 U21 成长 60%/属性/年，与日常训练叠加
4. 隔离测试：300 天训练后 PA70 球员 OVR=67，正常路径不到 90；玩家个例来自波动 + 高起始属性

**修复说明**

与 REQ-20260611-05 A 期合入：

1. `getPotentialOverallCap()` + `getOverallCap()` 委托潜力总评上限
2. `clampToPotentialCaps()`：初始化 / Housekeeping 例行钳制
3. 赛季末成长统一 `getAttrCap()`；U21 爆发降至 40%

**验证方式**

- [x] `tests/training_participation_test.lua`（OVR cap）
- [x] `tests/balance_diag_test.lua` 回归
- [ ] PA 70 球员 5 赛季后 OVR < 85（长期 sim 待补）

**关联**

- 提交/PR：
- 备注：设计文档与代码注释对「潜力上限」口径需统一

---

#### BUG-20260611-06 · 青训妖人转会后合同被原球队覆盖还原

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制 |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/systems/transfers/transfer_completion.lua`、`scripts/systems/transfer_manager.lua`、`scripts/systems/youth_manager.lua`、`scripts/persistence/housekeeping.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

埃斯特旺等非五大联赛潜力小妖（来自 `wonderkids_outside_top5_2025.json`），转会签署新合同并踢了几场比赛后，合同（工资/年限）变回转会之前的样子，且球员归属可能被改回原球队。

**复现步骤**

1. 开新档，找到任一 wonderkid 青训妖人（开局随机分配到某队青训名单 `_youthPlayerIds`）
2. 报价并完成转会，确认新合同（工资/年限）已生效
3. 推进至下个月 1 号（`YouthManager.processMonthly` 触发）
4. 查看球员合同与归属

**期望行为**

转会完成后球员完全脱离原球队（含青训名单），新合同长期有效。

**实际行为**

球员的 `teamId`、`wage`、`contractEnd` 在月初被覆盖为「青训提拔模板合同」（周薪 `max(1000, OVR×80)`、3 年、归属原球队）。

**根因分析**

三层缺陷叠加：

1. **转会清理不完整**：`_removePlayerFromTeam` 只从 `playerIds` / `startingXI` 移除，不清 `_youthPlayerIds`；妖人转会后在原队青训名单中残留引用
2. **AI 青训月度提拔无归属校验**：`YouthManager._processAITeamsMonthly` 对青训名单中年满 18 且 OVR≥55 的球员无条件执行提拔，直接覆盖 `teamId` / `wage` / `contractEnd`，把已转会球员「抢回」原队
3. 转会完成路径未清除 `isYouth` / 未重置 `squadRole`，残留青训身份标记

wonderkids 开局只进 `_youthPlayerIds` 不进 `playerIds`，因此五大联赛一线队球员不受影响，精准命中「非五大联赛小妖」这一玩家观察。

**修复说明**

四层修复（防御纵深）：

1. `_removePlayerFromTeam`（transfer_completion.lua）：同步从 `_youthPlayerIds` 移除
2. 所有永久转会完成路径（`_completeTransfer` / AI 转会 / `_completeIncomingSale` / 推销 / 预签约生效）：统一设置 `isYouth=false`、`squadRole="first_team"`；AI 转会与预签约的内联移除循环改用 `_removePlayerFromTeam`
3. `_processAITeamsMonthly`：先清除「球员已删除或 `teamId` 不属于本队」的残留引用（租借在外 `_loanOriginTeamId` 指回本队的保留），提拔/释放仅处理归属本队的球员
4. `Housekeeping.purgeStaleYouthRefs`：每周例行 + 读档后清理全部球队（含玩家队）的残留青训引用，**已损坏的旧存档读档后自愈**

**验证方式**

- [x] 新增 `tests/youth_transfer_contract_test.lua`：6 组断言全部通过（转会清理 / 月度不覆盖 / 残留自愈 / Housekeeping 修复旧档 / 正常提拔不受影响 / 租借在外保护）
- [x] 回归：`save_roundtrip_test`、`contract_manager_test` 通过；`transfer_manager_test` / `youth_manager_fixes_test` / `transfer_system_flow_test` 的失败项经无改动对照确认为预先存在，与本修复无关

**关联**

- 提交/PR：
- 备注：`transfer_manager_test`（loan expiry）、`youth_manager_fixes_test`（释放语义 3 项）、`transfer_system_flow_test`（出售异步流 4 项）存在预先存在的失败，建议另行立项排查

---

#### BUG-20260611-07 · 死敌关系未初始化，机制全程不生效

| 字段 | 内容 |
|------|------|
| 类型 | Bug |
| 标签 | 机制, 内容 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/data/team_rivalries.lua`、`scripts/systems/transfer_manager.lua`、`scripts/data/real_data_loader.lua`、`scripts/core/game_state.lua`、`scripts/systems/finance_manager.lua`、`scripts/ui/screens/team_detail.lua`、`scripts/ui/screens/market.lua`、`scripts/ui/screens/pre_match.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

死敌（球队敌对关系）相关内容在游戏中完全无感知：球员可正常转会至死敌球队、向死敌推销球员不会被拒、球队详情/转会 UI 无死敌标识，德比战亦无额外效果。

**复现步骤**

1. 选择存在经典死敌关系的球队开档（如曼联 vs 曼城、皇马 vs 巴萨、米兰 vs 国米）
2. 尝试从死敌球队挖角核心球员，或向死敌推销本队球员
3. 观察球员意愿判定、AI 俱乐部回应及 UI 提示
4. （可选）死敌德比主场作战，对比上座率/票房是否与普通比赛有差异

**期望行为**

- 开档时根据联赛数据初始化死敌关系（关系值 ≤ -50 视为敌对）
- 球员 80% 概率拒绝加盟死敌（「不愿去死敌球队」）
- 向死敌推销时俱乐部直接拒绝（「对方与你的球队关系敌对，拒绝交易」）
- UI 可展示死敌标识；德比战可触发上座率加成等（见设计文档）

**实际行为**

`_isRivalry` 始终返回 `false`：`gameState._teamRelations` 从未被写入，转会流程中的死敌检查形同虚设。

**根因分析**

1. **关系表从未初始化**：`TransferManager.setTeamRelation` 已实现，但全项目无任何调用点；开档/读档后 `_teamRelations` 为 `nil` 或空表
2. **数据未导入**：五大联赛 JSON 的 `world_history.rivalries` 均为空数组 `[]`，且 `RealDataLoader.importLeague` / `loadAllLeagues` 未读取该字段
3. **存档缺口**：`GameState:serialize()` / `deserialize()` 未包含 `_teamRelations`，即便运行时手动设置也会在存读档后丢失
4. **UI 缺失**：`team_detail`、转会中心等页面无死敌展示；`getPlayerTransferAttitude` 也未纳入敌对关系，与 `_checkPlayerWillingness` 逻辑不一致
5. **关联设计未落地**：`game_design_report.md` 提及「德比战自动提升上座率」，但 `FinanceManager.processMatchDayRevenue` 仅按对手声望计算，未调用 `_isRivalry`

**修复说明**

（2026-06-12 已合入）

1. **`scripts/data/team_rivalries.lua`**：硬编码 18 对经典死敌（`jsonTeamId` 与 FM JSON 一致，关系值 -80）；含中文德比说明列；`initialize` / `initializeIfNeeded`
2. **`real_data_loader.loadAllLeagues`** 末尾初始化；**`game_state.deserialize`** 对旧存档补全
3. **`game_state` 序列化** `_teamRelations`
4. **转会**：`_checkPlayerWillingness` / `getPlayerTransferAttitude` / `offerToClub` 死敌拦截
5. **UI**：`team_detail` 死敌列表；`market` 死敌标签 + 「不愿去死敌球队」文案；`pre_match` 德比战标识
6. **德比上座率**：`FinanceManager.processMatchDayRevenue` 死敌 +8% 上座率加成

**验证方式**

- [x] 开档后 `_teamRelations` 含曼联-曼城等键且值 ≤ -50
- [x] 挖角/态度：「不愿去死敌球队」
- [x] 向死敌推销：「关系敌对，拒绝交易」
- [x] 存档读档后死敌关系保留
- [x] `tests/rivalry_relegation_test.lua`（初始化/存档/意愿/推销/集成）
- [ ] 手动：德比主场票房明细可见上座率提升

**关联**

- 提交/PR：
- 相关记录：`docs/transfer-system-design.md` §6.3
- 备注：JSON `world_history.rivalries` 仍为空，死敌数据维护在 `team_rivalries.lua`；审阅清单见该文件 `PAIRS` 第三列

---

#### REQ-20260611-01 · 完善租借系统并新增中超（第六联赛）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 内容, 机制 |
| 状态 | 部分完成 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/transfer_manager.lua`（租借）、`scripts/ui/screens/market/loans_tab.lua`、`scripts/ui/screens/player_detail.lua`、`scripts/ui/screens/squad.lua`、`scripts/ui/screens/training.lua`；**中超**：`scripts/data/real_data_loader.lua`、`assets/Data/fm2024_csl.json`、`scripts/systems/world_generator.lua`、`scripts/systems/champions_league.lua`、`scripts/ui/screens/create_manager.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI（租借 2026-06-12；中超数据 2026-06-13） |

**现象**

玩家希望有更完整的租借玩法，并将中国超级联赛作为第六大联赛纳入游戏世界。

**需求说明**

**租借系统**

- 当前代码已有基础租借流程（`TransferManager` 发起租借、`_activeLoans` 到期处理），但玩家感知为功能不完整
- 需明确：租借挂牌、租借报价、租期续租、强制召回、租借方/出租方 UI、AI 租借行为、财务工资分摊等

**第六联赛 — 中超**

- 新增中超联赛数据（球队、球员、赛程）
- 纳入 `world_generator` 世界生成与赛事体系
- 考虑与现有五大联赛的数据规模、声望体系、转会市场联动

**期望行为**

玩家可在转会市场完成完整租借循环；开档或世界生成时可选择/包含中超作为可玩联赛。

**根因分析**

非 Bug，属于内容扩展与机制补全需求。租借为部分实现状态；中超 JSON 已导入但初版数值档位错误（见 [BUG-20260613-02](#bug-20260613-02--中超联赛数据财务声望能力档位错误)）。

**修复说明**

**已完成（租借子集，2026-06-12）**

- `TransferManager`：`listForLoan` / `delistLoan` / `recallLoan` / `extendLoan` / `formatLoanRemainingWeeks`；`_activeLoans` 纳入存档
- 玩家 `listForLoan`、`makeLoanBid` 均走 `_checkTransferWindow`（夏窗 6–8 月 / 冬窗 1 月，与俱乐部间交易一致）
- UI：阵容长按「挂牌外租」、球员详情合同区（挂牌/召回/续租）、转会市场租借页（剩余周数/召回/续租/出场效率）
- 训练页与球员详情展示 22+ 出场配额与训练效率（REQ-05 联动，非本 REQ 核心但已落地）
- **AI 外租挂牌**（2026-06-12 修订）：由 `processAITransfers` 在转会窗内每周触发（不再每月随机）
  - `_scoreLoanListingCandidate` 画像评分：年轻有潜力 / 青训定位 / 缺乏出场（非 XI、出场低于角色预期）
  - 排除核心、≥27 岁、高 OVR；每队每周最多 1 人、全局最多 5 人；U21 默认 52 周租期，其余 26 周
- 测试：`tests/loan_ops_test.lua`、`tests/ai_loan_listing_test.lua`
- **窗期结束自动下架**：`clearLoanListingsOutsideWindow`（`processDailyBids` 每日窗外执行，玩家球队有挂牌时通知；读档 `Housekeeping.run` 静默自愈）

**已完成（中超子集，2026-06-13）**

- `assets/Data/fm2024_csl.json`：16 队、384 人、赛程/积分榜快照
- `RealDataLoader.OPTIONAL_LEAGUES.CSL` + 新游戏 `create_manager`「中超联赛」开关（`includeCSL`）
- `world_generator` / `main.lua` 按选项加载；`ChampionsLeague` 加载中超时英超欧冠名额 8→7、中超冠军占原额外 1 席（`csl_ucl_qualification_test`）
- 数据档位校准（[BUG-20260613-02](#bug-20260613-02--中超联赛数据财务声望能力档位错误)）：初始声望 550 封顶、财务与声望对齐、OVR 最高 73

**未做 / 待验证**

- 中超开档 → 完整赛季 → 转会 → 欧冠路径 **端到端人工验证**
- micro-growth（明确不做，见 REQ-05）

**验证方式**

- [x] 租借流程端到端可玩（租入、租出、召回、续租、到期回归）
- [x] AI 仅在转会窗挂牌，且候选符合年轻/潜力/缺勤画像（`ai_loan_listing_test`）
- [x] 窗期结束后外租挂牌自动下架（`loan_ops_test`）
- [x] 中超数据文件存在且导入逻辑已接线（`getActiveLeagueConfigs({ includeCSL=true })`）
- [x] 欧冠名额分配逻辑（`csl_ucl_qualification_test`）
- [ ] 中超球队可执教、完成赛季、参与转会（**待人工开档验证**）
- [x] 存档读档保留租借合同（`_activeLoans` + `listedForLoan` / `loanListDuration`）

**关联**

- 提交/PR：
- 相关记录：[BUG-20260613-02](#bug-20260613-02--中超联赛数据财务声望能力档位错误)
- 备注：中超为可选顶级第六联赛；次级联赛见 [REQ-20260611-08](#req-20260611-08--增加可玩次级联赛)

---

#### REQ-20260611-02 · 球队降级时强制玩家经理辞职

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制 |
| 状态 | 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/season_manager.lua`、`scripts/systems/job_manager.lua`、`scripts/ui/screens/manager_view.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

玩家球队降级后仍可继续担任该队主教练，与「降级即下课」的 FM 式体验不符。

**需求说明**

- 赛季末升降级处理中，若 `playerTeamId` 落入降级区，除现有「球队降级!」邮件外，**自动触发经理离职**
- 行为应对齐主动辞职：`playerTeamId = nil`、`_isUnemployed = true`、写入 `career` 履历（`reason = "relegated"` 或类似）
- 需弹出/收件箱通知：「球队降级，董事会与你解约」类文案
- 新赛季该队由 AI 经理接管（`team.managerId` 重新分配）
- **已确认**：仅顶级联赛降级触发；二级储备池降级不触发（2026-06-12 合入）

**期望行为**

顶级联赛垫底降级 → 玩家自动失业 → 需重新求职；不能继续执教已降级的原球队。

**根因分析**

非 Bug。`SeasonManager._processPromotionRelegation` 原先仅发消息并交换联赛 `teamIds`，未调用 `JobManager` 离职流程。

**修复说明**

（2026-06-12 已合入）

1. **`JobManager.handleRelegation`**：顶级联赛玩家球队降级时调用；清除 `playerTeamId` / `league` / `playerLeagueId`；`_isUnemployed = true`；履历 `reason = "relegated"`；收件箱「降级解约」+ 新闻「教练离任」；`_firedFromTeamId` 阻止当季回聘
2. **`season_manager.lua`**：降级循环内对 `playerTeamId` 调用 `handleRelegation`；`_cheatAutoPlay` 时跳过玩家降级与强制辞职
3. **AI 接管**：`handleRelegation` 末尾立即 `_aiHireManager`（不等待 21 天）；修复 AI 池雇佣时未写 `team.managerId` 的问题
4. **`manager_view.lua`**：履历已支持「降级解约」标签（`relegated`）

**验证方式**

- [x] `tests/rivalry_relegation_test.lua`：`handleRelegation` 单元 + `_processPromotionRelegation` 集成 + 读档失业保留 + 作弊保护
- [x] 代码审查（2026-06-13）：失业态字段、`manager_view`「降级解约」标签、AI 立即接管路径与需求一致
- [ ] 手动端到端：完整赛季故意降级，经理页「自由身」+ 求职中心可用
- [x] `career` 末条含 `relegated` 与本段胜平负
- [x] 作弊跳赛季（`_cheatAutoPlay`）不降级、不强制辞职

**关联**

- 提交/PR：
- 相关记录：`REQ-20260611-08`（次级联赛可玩 — 当前顶级降级即失业；REQ-08 落地后需再评估次级开档/自愿留队）
- 备注：非「待排期」；总表已列入 [已修复](#已修复)

---

#### REQ-20260611-03 · 审查一线队训练成长过慢（疑似 Bug）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, 数值, 测试 |
| 状态 | 非 Bug / 已验证 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/training_manager.lua`、`scripts/systems/difficulty_settings.lua`、`scripts/domain/player.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | —（审查结论；上限失真见 BUG-05 已修） |

**现象**

玩家反馈一线队日常训练成长体感极慢，长期几乎看不到属性/OVR 变化，怀疑训练逻辑存在 Bug。

**需求说明**

需系统性审查并给出结论：**设计如此** 还是 **实现缺陷**，必要时修复或调参。

**当前实现要点（待验证）**

| 因素 | 现状 |
|------|------|
| 训练频率 | 默认周计划 `balanced` 仅 **周一/三/五** 训练（`WEEKLY_PLAN.trainDays`） |
| 基础概率 | 难度 tier3 下 `baseChance = 0.10`/训练日/人/属性池 |
| 强度 | `medium` ×1.0，`high` ×1.8；非训练日只恢复体能 |
| 潜力差 | `gapFactor = max(gapFloor, (potential - overall) / gapDivisor)`，接近潜力上限时概率趋近 0.4× |
| 年龄 | ≥30 岁 ×0.6，≥33 岁 ×0.3 |
| 上限 | `getAttrCap()` / `getOverallCap()` 达顶后停止增长 |
| 覆盖范围 | `processDaily` **仅处理玩家球队**；AI 走简化 3% 逻辑 |
| 对比 | 青训 `_trainTeamYouth` 每日执行且年轻加成更高，体感差异大 |

**期望行为**

- 若属设计：UI 或训练页应解释成长速度（周计划、潜力接近上限等），避免「坏了」的错觉
- 若属 Bug：定位并修复（如 cap 计算错误、周计划未生效、职员加成未乘入、FM 导入球员起始即贴顶等）
- 产出：`tests/training_pace_test.lua` 或诊断脚本，量化「300 训练日 OVR 期望增量」

**根因分析**

**结论：非实现缺陷，属多因素叠加的设计体感。** `tests/training_pace_test.lua`（seed 20260612，2 赛季≈560 日、240 训练日、`balanced`+`high`、含赛季末 `_processPlayerDevelopment`）量化如下：

| 场景 | OVR 变化 | attrΔ | OVR/训练日 |
|------|----------|-------|------------|
| 传奇·19·一线 | 78→97 (+19) | 32 | 0.079 |
| PA9·19·一线 | 62→75 (+13) | 18 | 0.054 |
| PA7·19·一线 | 58→65 (+7) | 12 | 0.029 |
| PA9·19·青训 | 62→76 (+14) | 24 | 0.058 |
| PA7·19·青训 | 58→67 (+9) | 16 | 0.037 |
| PA9·22·无出场 | 72→75 (+3) | 5 | 0.013 |
| PA9·22·满出场 | 72→85 (+13) | 17 | 0.054 |
| PA7·22·无/满出场 | +2 / +7 | 5 / 12 | 0.008 / 0.029 |

主要因素：

1. **训练频率**：默认 `balanced` 每周仅 3 训练日（约 43% 日历日）。
2. **gapFactor 衰减**：`(potential - overall) / gapDivisor`，PA 低或 OVR 已高时概率接近 `gapFloor`（0.4×）。
3. **22+ 出场挂钩**（REQ-05）：无出场训练效率 25%，与满出场差约 4× OVR 增速。
4. **青训更快**：`useYouthGap`（除数 25 vs 45）+ `YOUTH_TRAINING_BONUS` 1.08 + 青训路径跳过训练伤病 RNG。
5. **曾误判为 Bug 的上限失真**（BUG-05）已修；本测试全部场景未突破 `getOverallCap`。
6. **早期 PA7 一线 +0 假象**：测试若走完整 `processDaily` 且未跑 `turn_processor` 伤病恢复，高 `high` 强度 RNG 受伤后永久停训；测试已改为 `skipInjuryAndFitness` 隔离成长公式。

**修复说明**

- 无需改训练公式；审查目标已达成。
- 训练页「接近潜力上限」贴顶提示为**可选体验优化**，不纳入本 REQ 验收范围（若需可另开 UI 小项）。

**验证方式**

- [x] `tests/training_pace_test.lua`：传奇 / PA9 / PA7 × 一线/青训/U22 出场，量化 240 训练日成长
- [x] 全部场景 `endOvr ≤ getOverallCap()`（BUG-05 回归）
- [x] PA7 各场景 2 赛季后 OVR < 90
- [x] U22 无出场 25% vs 满出场 100% 效率与成长差异
- [x] 文档结论：**正常偏慢的设计**，非逻辑未执行
- [—] 贴顶球员训练页 UI 提示（可选，未做，不阻塞结案）

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-05、REQ-20260611-05
- 备注：审查结论区分「概率低 + 频率低」与「逻辑未执行」；前者为本项结论

---

#### REQ-20260611-04 · 扩展伤病种类（含赛季报销，极低概率）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, 内容, 存档, 测试 |
| 状态 | 已验证 |
| 严重程度 | P3 |
| 模块 | `scripts/match/event_flavors.lua`、`scripts/domain/player.lua`、`scripts/match/match_engine.lua`、`scripts/systems/training_manager.lua`、`scripts/core/turn_processor.lua`、`scripts/systems/transfer_manager.lua`、`scripts/ui/screens/national_squad_select.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

当前伤病仅有「受伤 + 预计 N 天恢复」单一形态，缺少严重程度分级，无赛季报销等长期伤病，比赛/训练体验偏扁平。

**需求说明**

引入伤病 **类型/严重程度** 体系，例如：

| 类型 | 说明 | 恢复 | 概率倾向 |
|------|------|------|----------|
| 轻微 | 肌肉疲劳、擦伤 | 3–7 天 | 常见 |
| 中等 | 扭伤、拉伤 | 2–6 周 | 较少 |
| 严重 | 韧带/骨折 | 2–4 月 |  rare |
| **赛季报销** | ACL、重大手术等 | 赛季剩余天数或固定 180+ 天 | **极低**（如比赛 0.1%–0.3%，高强度训练略高） |

**期望行为**

- 球员模型增加 `injuryType` / `injurySeverity`（或等价字段），UI 展示具体伤病名称
- 比赛引擎（`placeholder_engine` / `match_engine`）与训练伤病按类型抽样天数
- 赛季报销触发时收件箱高优先级通知，球员详情页标注「赛季报销」
- 极低概率，不应频繁打断赛季；可受年龄、体能、战术 `injuryRisk` 微调
- 存档序列化新字段；读档后倒计时正确续算

**根因分析**

非 Bug。现有实现：`player.injured` + `player.injuryDays`，比赛 `RandomInt(3, 21)`，训练 `RandomInt(3, 14)`，无分级枚举。

**修复说明**

（2026-06-12 部分合入，见 [REQ-20260612-02](#req-20260612-02--比赛事件风味与伤病种类统一)）

**已完成：**

1. **`event_flavors.lua`**：9 种伤病（轻微撞伤、肌肉拉伤、脚踝扭伤、腿筋拉伤、腹股沟、背部、脑震荡、膝韧带、跖骨骨折），按权重抽样；严重程度由天数推导（≤7 轻伤 / ≤18 中度 / 以上重伤）
2. **全链路复用**：比赛、训练、随机事件、legacy 引擎均走 `rollInjury(maxDays?)`；训练上限 14 天自动排除膝韧带/跖骨骨折
3. **UI**：直播/赛后/消息展示种类与严重度文案
4. **（2026-06-12 追加）赛季报销**：`rollMatchInjury` 极低概率（默认 0.2%）抽样 ACL/跟腱/重大手术；恢复天数 `max(180, 赛季剩余)`；高优先级收件箱 `injury_season_ending`
5. **（2026-06-12 追加）存档字段**：`injuryKind` / `injuryKindName` / `injurySeverity` / `injurySeverityName` / `injurySeasonEnding` 写入 `Player:serialize`；伤愈 `clearInjuryFromPlayer` 清零
6. **（2026-06-12 收尾）概率微调**：`computeSeasonEndingChance(player, { injuryRisk, year, intensityMult })` — 年龄/体能/injuryRisk/训练强度联动；比赛子概率基准 1.2%，高强度训练 0.9%×1.25
7. **（2026-06-12 收尾）训练赛季报销**：`rollTrainingInjury` — 中低强度 `rollInjury(14)`；高强度可走赛季报销
8. **（2026-06-12 收尾）系统联动**：`Player:isMatchAvailable` / `getInjuryBlockReason`；转会挂牌/外租拒绝伤员；国家队大名单禁止新选伤员（🚫赛季报销）
9. **接入**：`match_engine` / `match_session` / `training_manager` / `turn_processor` / `placeholder_engine` 统一走新 API

**仍待做（可选）：**

- 合同续约 UI 对赛季报销球员的特别说明（机制上已无法出场/挂牌，非必须）

**验证方式**

- [x] `tests/event_flavors_test.lua`：种类区间、严重度、`rollInjury(14)`、强制赛季报销、apply/clear/serialize、概率微调、训练高强度、每场报销率蒙特卡洛、`Player` 辅助方法
- [x] `tests/save_roundtrip_test.lua` §8：伤病字段 GameState 往返
- [ ] 手动：1000 场实赛统计赛季报销触发率

**关联**

- 提交/PR：
- 相关记录：[REQ-20260612-02](#req-20260612-02--比赛事件风味与伤病种类统一)
- 备注：随机事件 `injuryType` 现为中文种类名（`kindName`），非稳定 id；赛季报销天数取 `max(180, 赛季剩余天数)`

---

#### REQ-20260611-05 · 成长与训练体系优化（含正式比赛成长因子）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, 数值 |
| 状态 | 已修复 |
| 严重程度 | P2 |
| 模块 | `scripts/app/constants.lua`、`scripts/domain/player.lua`、`scripts/systems/training_manager.lua`、`scripts/systems/youth_manager.lua`、`scripts/systems/season_manager.lua`、`scripts/systems/potential_system.lua`、`scripts/persistence/housekeeping.lua`、`scripts/ui/screens/training.lua`、`scripts/ui/screens/player_detail.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

成长/训练/租借三条线各自部分实现，缺少统一设计；尤其 **正式比赛对球员成长无独立影响因子**，出租球员成长路径不完整。

**需求说明（v2，2026-06-12 设计确认）**

详见 [optimization-plan.md § REQ-20260611-05 v2](./optimization-plan.md#req-20260611-05--成长与训练体系-v2出场挂钩)。

**1. 成长体系（BUG-05 合并）**

- 统一 `getAttrCap` / 潜力总评上限 / 赛季末结算口径
- 青年期边界：**21 岁及以下**（`YOUTH_PHASE_MAX_AGE`）

**2. 成年期：训练与俱乐部出场挂钩**

- **22 岁起**（按 **赛季初年龄** `seasonStartYear` 判定，整季不变）
- **每个训练日**读当季累计 `seasonStats.appearances`（非按月、非每场涨点）
- **练满配额**：22 岁 **12 场** 起，每长一岁 **+2**，27 岁起 **25 场** 封顶
- `participationFactor = clamp(apps / quota, 0.25, 1.0)`
- **仅俱乐部**正式赛计入；国家队/世界杯 **不计**；外租俱乐部出场计入；**赛季内换队累计**

**3. 赛季末成长**

- **≤21 岁**（赛季初）：**40%/属性**（原 60% 下调），**不**乘出场系数
- **≥22 岁**：原年龄档 baseChance × participationFactor（用赛季最终俱乐部出场）

**4. 青训**

- 训练日跟随一线队 `weeklyPlan`；age≤21 额外 ×1.08
- **22+ 仍在 `_youthPlayerIds`**：自动解约并删库（高潜→自由球员，低潜移除）；每月例行 + Housekeeping

**5. 21 岁一线队**

- 无出场要求、无 1.08 青训加成 — **符合预期**

**6. AI**

- 同方案；性能评估见 optimization-plan（建议 B 玩家队 → B′ AI）

**7. 租借 / micro-growth**

- 外租 **俱乐部**正式赛出场计入 `seasonStats.appearances`（与一线队相同口径，REQ-01 子集已可外租）
- **micro-growth（阶段 E）明确不做**

**期望行为**

- 22+ 球员：**坐板凳纯训练练不满**；捞到一线队（或外租）出场才能满效成长
- 21 及以下：靠训练 + 青训略加成即可，无需出场门槛
- 青训与一线队 **同训同休**；青年期体感略快、成年期必须用比赛锻炼

**根因分析**

非 Bug，属机制补全。当前青训每日训练、一线队每周 3 日、比赛不写成长、22+ 与 18 岁同规则，导致 REQ-03「太慢」与 BUG-05「上限失真」并存。

**修复说明**

（2026-06-12 已合入）A 期 BUG-05 + B 期 REQ-05 v2（含 AI 同逻辑）+ C 期 UI：

1. `player.lua`：`getPotentialOverallCap`、`clampToPotentialCaps`；`getOverallCap` 委托潜力上限
2. `potential_system` / `housekeeping`：初始化与例行钳制
3. `training_manager`：`getParticipationFactor` / `getParticipationSummary`（赛季初年龄、quota 12→25）；玩家/AI 共用 `_processTeamDaily`
4. `youth_manager`：跟 `weeklyPlan`、×1.08；`purgeOverageYouth`（22+ 删库）
5. `season_manager`：U21 赛季末 40%；22+ 乘出场系数；`getAttrCap` 统一
6. UI：`scripts/ui/screens/training.lua`（全队说明 + 个人 tab 出场/效率）；`player_detail.lua` 训练/生涯 tab 成长效率卡片

**验证方式**

- [x] `tests/training_participation_test.lua`
- [x] `tests/youth_schedule_sync_test.lua`
- [x] `tests/balance_diag_test.lua` 回归
- [x] 训练页 / 球员详情 UI：出场 X/quota、效率 Y%
- [x] 外租俱乐部出场计入成长（`seasonStats.appearances` 换队累计，机制已合入）
- [ ] 22 岁 0 场 vs ≥12 场一赛季（live 体感）

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-05、REQ-20260611-01（租借 UI/外租路径）、REQ-20260611-03
- 备注：**micro-growth 不做**；REQ-03 已用 `training_pace_test.lua` 定案为设计如此（非 Bug）

---

#### REQ-20260611-06 · 球员场上职责（与位置/角色分层）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, UI |
| 状态 | 待排期 |
| 严重程度 | P2 |
| 模块 | `scripts/app/constants.lua`、`scripts/ui/screens/tactics.lua`、`scripts/domain/team.lua`、`scripts/match/tactics_resolver.lua`、`scripts/systems/ai_manager.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | |

**现象**

当前战术体系里「球员踢什么位置」与「球员在场上承担什么任务」概念混在一起，玩家无法像 FM 那样单独设定 **场上职责**（进攻 / 策应 / 防守），且与球员档案里的 **自然位置**（`player.position`）边界不清。

**需求说明**

引入与 **位置**、**角色** 独立的三层战术模型：

| 层级 | 含义 | 示例 | 当前状态 |
|------|------|------|----------|
| **自然位置** | 球员本身擅长/惯踢位置 | ST、LW、CDM（`player.position` / `naturalPositions`） | ✅ 已有，用于选人适配、OVR 权重 |
| **战术角色** | 该槽位怎么踢法 | 内切射手、B2B 中场、出球中卫（`team.slotRoles[slotIdx]` → `Constants.POSITION_ROLES`） | ⚠️ 战术页可选，绑 **槽位** 非球员；**未进 `team:serialize()`** |
| **场上职责** | 该球员本场攻守倾向 | 进攻 / 策应 / 防守（FM 式 Duty） | ⚠️ 引擎有 `team.playerDuties[playerId]` + `DUTIES` 攻防系数，**无 UI、默认全为策应、未存档** |

**期望行为**

1. **职责 UI**：战术/阵型页每个首发槽位（或球员）可设 **进攻 / 策应 / 防守**，与「换位置」「选角色」分开展示，文案避免与 `player.position` 混淆
2. **引擎生效**：`tactics_resolver.buildTeamContext` 已读 `playerDuties`（attack ×1.18 / defend ×1.18）；需保证 UI 写入、换人/换阵型后职责合理继承或重置策略明确
3. **视觉反馈**：球场视图用箭头/颜色区分职责（进攻更前、防守更后），可与 `POSITION_ROLES.posOffset` 叠加
4. **AI 适配**：`AIManager` 选首发时按阵型+职责分配，非全默认 `support`
5. **存档**：`slotRoles`、`playerDuties`、`formationVariant` 纳入 `team:serialize()`（与 BUG-20260611-03 联动）
6. **概念边界**：球员详情页继续展示 **自然位置**；战术页展示 **本场槽位 + 角色 + 职责**，三者术语在 UI 中文案固定（例：位置=ST，角色=抢点型前锋，职责=进攻）

**可选扩展（非 MVP）**

- 职责影响体能消耗、站位偏移、比赛事件权重（不仅攻防 aggregate）
- 预设战术模板（如 4-3-3 高位逼抢）一键分配职责
- 球员「熟练职责」或偏好（某些球员更适合进攻职责）

**根因分析**

非 Bug，属战术深度补全。职责层代码已存在于 `tactics_resolver.lua`（`DUTIES` 表），但未产品化；角色层（`slotRoles`）有 UI 但未持久化；自然位置与槽位位置在阵容 UI 中均称「位置」，玩家感知为同一概念。

**修复说明**

（未开始）

建议 MVP：

1. 战术页槽位弹窗增加职责三选一（与现有「球员角色」并列）
2. `team:serialize()` / `Team.new` 持久化 `slotRoles`、`playerDuties`、`formationVariant`
3. 赛前/读档校验：无职责则默认 `support`

**验证方式**

- [ ] 将 ST 设为「防守职责」后，该球员对 team defense 贡献上升、attack 下降（可测 `buildTeamContext`）
- [ ] 存档读档后职责与角色均保留
- [ ] 球员详情「位置」仍为自然位置，与战术页职责无冲突展示
- [ ] AI 球队比赛上下文含非全 `support` 的职责分布

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-03（阵容/战术存档）、`Constants.POSITION_ROLES`、`scripts/ui/screens/tactics.lua`
- 备注：现有 UI 标签「球员角色」实为 Role；新增 Duty 建议中文用 **「场上职责」**，Role 可改称 **「战术角色」** 以减少歧义

---

#### REQ-20260611-07 · 比赛中换人后，赛后仍显示赛前阵容

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, UI |
| 状态 | 已修复 |
| 严重程度 | P1 |
| 模块 | `scripts/match/match_session.lua`、`scripts/match/match_report.lua`、`scripts/match/match_engine.lua`、`scripts/match/placeholder_engine.lua`、`scripts/ui/screens/match_result.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

实时比赛（`match_live`）中途完成换人后，比赛结束页（`match_result`）的 **我方球员评分 / 出场名单** 仍显示 **赛前首发 11 人**，被换下的球员仍在列表中，替补上场的球员未出现或缺少评分/统计。

**复现步骤**

1. 进入一场可换人的 live 比赛（联赛/杯赛）
2. 比赛中执行 1～3 次换人（换下 A，换上 B）
3. 比赛结束后查看「我方球员评分」及相关统计
4. 对比赛前首发名单与终场名单

**期望行为**

- 终场页展示 **实际参与比赛的球员**（含替补上场者），被换下且未再登场的球员不应占据首发评分位
- 替补上场球员应有本场评分、进球/助攻/牌等事件统计（若参与事件）
- 出场数、体能消耗、赛季 `appearances` 等应对齐 **实际出场人员**，而非赛前 `startingXI` 快照
- 换人记录（`session.substitutions`）可在赛后摘要或时间线中展示

**实际行为**

赛后数据与 UI 仍绑定赛前阵容；玩家感知为「换了人但赛报没换」。

**根因分析（代码审查，待修复验证）**

链路断裂点可能在以下几处叠加：

| 环节 | 现状 | 风险 |
|------|------|------|
| 换人执行 | `MatchSession:_applySubstitution` 会改 `context.players` 与 `team.startingXI[slot]` | 世界杯虚拟队 `buildNationalTeam` 与俱乐部 `team` 可能不同步 |
| 终场报告 | `buildReport` → `MatchReport.calculatePlayerRatings` 读 **终局** `homeContext/awayContext.players` | 若 context 未持久换人则评分仍按赛前 11 人 |
| 赛后落盘 | `PlaceholderEngine.applyResult` / `applyPlayerMatchStats` 通过 `_getMatchPlayers` 再读 `team.startingXI` | 与 session 终局名单可能不一致；未使用 `session.substitutions` / `removedPlayerIds` |
| 报告结构 | `report` 无 `finalLineup` / `participants` 字段 | UI 与统计层各自猜阵容来源，易回退到赛前 XI |
| 副作用 | 换人直接改 `team.startingXI` | 赛果统计与 **存档阵容** 混用同一字段，边界不清 |

**修复说明**

1. **`match_session.lua`**：维护 `kickoffStartingXI`（赛前快照）、`shadowLineup`（临场阵容）、`appearanceIds`（出场集合）；换人只改 shadow，不再写永久 `team.startingXI`；`buildReport` 输出 `ratingLineup`、`appearanceIds`、`substitutions`；新增 `restoreKickoffLineups()` 赛后还原存档阵容
2. **`match_report.lua`**：`calculatePlayerRatings` 按 `ratingLineup` 终局 11 人评分；被换下球员不出现在评分表
3. **`match_engine.lua`**：`finishMatch` 在 `buildReport` 后、`applyResult` 前调用 `restoreKickoffLineups()`
4. **`placeholder_engine.lua`**：`applyResult` / `applyPlayerMatchStats` 以 `report.appearanceIds` 计出场，不再仅读 `team.startingXI`
5. **`match_result.lua`**：评分区按 `report.ratingLineup` 过滤，只展示终场 11 人

**验证方式**

- [x] 换下主力、换上替补后，终场评分列表含替补、不含被换下者
- [ ] 替补进球/助攻出现在其名下而非被换下球员（需 live 事件联调）
- [x] 替补 `seasonStats.appearances +1`；被换下者仍计出场（踢过球）
- [x] 赛后 `team.startingXI` 与赛前 kickoff 一致
- [x] 单元测试：`tests/match_substitution_report_test.lua`

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-03（`startingXI` 存档）、REQ-20260611-06（换人后职责继承）
- 备注：实质为 Bug；`report.substitutions` 已写入报告，赛后摘要 UI 展示待后续

---

#### REQ-20260611-08 · 增加可玩次级联赛

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 内容, 机制, UI |
| 状态 | 待排期 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/season_manager.lua`、`scripts/data/real_data_loader.lua`、`scripts/core/game_state.lua`、`scripts/core/turn_processor.lua`、联赛 UI |
| 发现人 | 玩家反馈 |
| 修复人 | |

**现象**

五大顶级联赛可完整执教，但次级联赛（英冠、西乙、意乙、德乙、法乙）不存在可玩体验：降级后无真实赛程与积分榜，无法从次级联赛开档或长期经营低级别球队。

**需求说明**

将现有 **抽象升降级储备池** 升级为 **完整可玩次级联赛体系**：

| 能力 | 当前 | 目标 |
|------|------|------|
| 联赛实体 | `gameState.secondDivision[leagueKey]` 仅 `teamIds` + 抽象 `standings` | 完整 `League` 对象（赛程、积分榜、轮次） |
| 球队/球员 | 赛季末程序化生成 6 支假队（`_generatePromotionTeam`） | 导入真实或半真实次级联赛数据（球队名、阵容、声望档） |
| 赛季模拟 | `_simulateSecondDivision` 按实力随机积分，无对阵 | 与顶级联赛同引擎逐场模拟或独立赛程表 |
| 玩家可玩 | 降级后球队进储备池，**无次级赛程/UI** | 可执教次级球队：打比赛、看积分榜、参与转会 |
| 升降级 | 顶级 ↔ 储备池交换 3 队 | 顶级末 3 ↔ 次级前 3，双向联赛归属切换 |
| 开档 | 仅五大顶级可选 | 可选次级联赛球队开档（低声望档） |
| 存档 | `secondDivision` 已序列化 | 扩展为完整联赛存档或合并进 `gameState.leagues` |

**命名映射（已有常量，可沿用）**

- EPL → 英冠、LaLiga → 西乙、SerieA → 意乙、Bundesliga → 德乙、Ligue1 → 法乙

**期望行为**

- 玩家球队降级后进入对应次级联赛，下一赛季有完整 fixture、可踢每场/模拟
- 次级联赛冠军升级回顶级；顶级保级队降级下来
- 联赛页可切换查看「顶级 / 次级」或自动跟随 `playerLeagueId`
- 转会市场、董事会目标、财务按联赛级别分档（次级预算/声望低于顶级）
- AI 次级球队正常参与赛季，非仅赛季末抽积分

**根因分析**

非 Bug。`SeasonManager._processPromotionRelegation` 已实现升降级 **逻辑骨架**，但二级联赛被设计为 **后台抽象模拟**（`docs/game_design_report.md` 标注「可扩展」），未接入 `League`、赛程生成、`turn_processor` 比赛日与 UI。

**修复说明**

（未开始）

建议分期：

1. **A 期**：数据 — 每国 1 个次级联赛 JSON（可缩小规模，如 24 队）+ `RealDataLoader` 导入为 `leagues.EPL_Championship` 等
2. **B 期**：机制 — 升降级改绑真实次级 `League.teamIds`；`playerLeagueId` / 赛程归属正确切换
3. **C 期**：UI — 联赛视图、开档选队、赛季结束升降级动画；董事会目标按级别分档
4. **D 期**（可选）：杯赛、次级↔顶级转会声望门槛、求职系统含次级空缺

**验证方式**

- [ ] 开档选择英冠球队，完成完整赛季并升级至英超
- [ ] 顶级球队降级后次赛季在英冠有赛程且可踢玩家比赛
- [ ] 次级积分榜、转会、存档读档正确
- [ ] 五大联赛各有一对顶级↔次级联动

**关联**

- 提交/PR：
- 相关记录：REQ-20260611-02（降级强制辞职 — **已实施**：顶级降级玩家失业、不可继续执教原队；REQ-08 落地后需再评估次级路径）、REQ-20260611-01（中超为 **顶级** 第六联赛，与本需求层级不同）
- 备注：现有 `secondDivision` 储备池可在迁移后废弃或作降级过渡兼容层

---

#### REQ-20260611-09 · 青训队球员可转会（不含候选池）

| 字段 | 内容 |
|------|------|
| 类型 | 需求 |
| 标签 | 机制, UI |
| 状态 | 已修复 |
| 严重程度 | P2 |
| 模块 | `scripts/systems/youth_manager.lua`、`scripts/systems/transfer_manager.lua`、`scripts/systems/finance_manager.lua`、`scripts/ui/screens/youth.lua`、`scripts/ui/screens/player_detail.lua`、`scripts/ui/screens/market.lua` |
| 发现人 | 玩家反馈 |
| 修复人 | AI |

**现象**

已签入青训队的球员（青训学院列表中的妖人/青训）只能 **提拔** 或 **释放**，无法像一线队球员一样 **挂牌出售、接受报价、主动推销**；高潜力青训只能留队或释放，缺少 FM 式「青训套现」玩法。

**范围界定**

| 对象 | 存储 | 是否纳入本需求 |
|------|------|----------------|
| **青训队球员** | `team._youthPlayerIds`，已 `addPlayer`，`isYouth=true` | ✅ 应可转会 |
| **青训候选** | `gameState._youthCandidates`，尚未签入、无正式归属 | ❌ **不可**转会（仅招募/抽卡签入） |
| **已提拔一线队** | `team.playerIds`，`isYouth=false` | 已有转会流程，不在本需求范围 |

**需求说明**

1. **出售**：青训队球员可挂牌（`listedForSale`），出现在转会市场「待售」；可接收 AI/玩家报价并完成出售
2. **UI**：青训页操作菜单增加「挂牌出售」；球员详情合同页对 `isYouth` 且归属本队青训者展示转会操作（或跳转市场）
3. **转会完成**：出售后从 `_youthPlayerIds` 移除（复用 `_removePlayerFromTeam` / BUG-06 路径），清除 `isYouth` 或按买方球队规则重置
4. **买入**：其他球队青训球员（含 AI 队 `_youthPlayerIds` / wonderkids）应对买家可见、可报价（受年龄/潜力/保护条款等规则约束，可后续迭代）
5. **AI 行为**（可选）：AI 可对过剩或高报价青训挂牌；不应出售 `_youthCandidates` 虚拟条目
6. **保护**（可选）：U18 国内保护、最低报价、需董事会批准等 — MVP 可先无，文档预留

**期望行为**

- 玩家将青训妖人挂牌 → AI 报价 → 成交 → 球员离队、资金入账、青训名额空出
- 候选列表中的未签入球员 **无** 转会入口
- 与「释放」（变自由球员）区分：释放无转会费，出售有报价流程

**根因分析**

非 Bug。青训球员仅在 `_youthPlayerIds`，不在 `team.playerIds`；`youth.lua` 操作菜单仅含提拔/释放/详情；转会 UI 主要面向一线队 roster。`TransferManager._completeTransfer` 已支持买走后清 `isYouth`（BUG-06），但 **入口与挂牌路径未对青训开放**。

**修复说明**

（2026-06-12 已合入）

1. `YouthManager.isOnTeamYouthSquad` / `isYouthSquadPlayer`；提拔/释放与挂牌互斥
2. `TransferManager.listForSale`：支持青训已签入球员；转会窗校验；与外租挂牌互斥
3. `FinanceManager.checkSquadSafety`：仅 `_youthPlayerIds` 的球员不计一线最低人数
4. UI：青训页长按「挂牌出售/取消」；球员详情「青训转会」卡片；市场「待售」含 `_youthPlayerIds`；浏览页「青训」标签
5. 成交仍走 `_completeTransfer` + BUG-06 清理路径；**不新增**球员记录

**验证方式**

- [x] 青训球员挂牌后在市场「待售」可见
- [x] 完成出售后从 `_youthPlayerIds` 移除，买方 `playerIds` 正确
- [x] 挂牌中不可提拔；释放会清除挂牌状态
- [x] `tests/youth_transfer_list_test.lua` + `youth_transfer_contract_test.lua` 回归
- [x] 转会前后 `players` 总数不变（无重复建档）

**关联**

- 提交/PR：
- 相关记录：BUG-20260611-06、REQ-20260611-01（青训外租可后续扩展）
- 备注：候选池仍仅可签入；「释放」与「出售」UI 已区分

---

## 记录模板

复制以下模板到对应日期章节下填写：

```markdown
#### BUG-YYYYMMDD-NN · [简短标题]

| 字段 | 内容 |
|------|------|
| 类型 | Bug / 需求 |
| 标签 | 机制, 数值, 存档, UI, 内容, 性能, 测试（逗号分隔） |
| 状态 | 待确认 / 已确认 / 修复中 / 已修复 / 已验证 / 非 Bug / 暂缓 / 待排期 |
| 严重程度 | P0 / P1 / P2 / P3 |
| 模块 | 例：`scripts/domain/player.lua`、转会系统、存档 |
| 发现人 | |
| 修复人 | |

**现象**

（用户可见的错误表现、报错信息、异常数据等）

**复现步骤**

1.
2.
3.

**期望行为**

（正确情况下应发生什么）

**实际行为**

（当前实际发生什么）

**根因分析**

（定位结论；未查明可写「待分析」）

**修复说明**

（改动摘要、涉及文件；未修复可留空）

**验证方式**

- [ ] 单元测试：`tests/xxx_test.lua`
- [ ] 手动复现步骤通过
- [ ] 回归相关场景

**关联**

- 提交/PR：
- 相关 Issue / 讨论：
- 备注：
```

---

## 关联文档

- [optimization-plan.md](./optimization-plan.md) — 对应 Bug 的优化方案与研究记录
