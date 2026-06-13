# OpenFoot Manager - 优化方案

**版本**: v1.0  
**对应文档**: [bug-log.md](./bug-log.md)  
**维护说明**: 每条 Bug/需求在此有对应优化条目；研究结论与改动方案记录于此  
**最后更新**: 2026-06-12

---

## 目录

- [总览](#总览)
- [BUG-20260611-04 · 联赛模拟随机性过强](#bug-20260611-04--联赛模拟随机性过强)
- [BUG-20260611-05 · 低潜力球员 OVR 可破 90](#bug-20260611-05--低潜力球员-ovr-可破-90)
- [REQ-20260611-05 · 成长与训练体系 v2（出场挂钩）](#req-20260611-05--成长与训练体系-v2出场挂钩)
- [其他条目（待研究）](#其他条目待研究)
- [诊断工具](#诊断工具)

---

## 总览

| Bug/需求 ID | 标题 | 标签 | 优化状态 | 优先级 |
|-------------|------|------|----------|--------|
| BUG-20260611-01 | 董事会月度目标不生效 | 机制 | 待研究 | P1 |
| BUG-20260611-02 | 赛季董事会目标颗粒度太粗 | 机制, 数值 | 待研究 | P2 |
| BUG-20260611-03 | 阵容阵型存档丢失 | 存档, 机制 | 待研究 | P1 |
| **BUG-20260611-04** | **联赛模拟随机性过强** | **数值, 机制** | **已研究** | **P1** |
| **BUG-20260611-05** | **低潜力球员 OVR 可破 90** | **数值** | **已研究** | **P2** |
| REQ-20260611-01 | 租借系统 + 中超 | 内容, 机制 | 待排期 | P2 |
| **REQ-20260611-05** | **成长与训练体系（出场挂钩）** | **机制, 数值** | **方案已定** | **P2** |

---

## BUG-20260611-04 · 联赛模拟随机性过强

**标签**: `数值`, `机制`  
**关联模块**: `scripts/match/match_engine.lua`、`scripts/match/tactics_resolver.lua`、`scripts/systems/difficulty_settings.lua`

### 问题复述

玩家反馈：保级队可长期占据榜首，皇马级豪门反而降级；联赛格局与真实实力严重脱节。

### 研究结论（2026-06-11）

#### 1. 隔离测试结果

使用 `tests/balance_diag_test.lua` 在**可控环境**（10 队、声望 30–95 分层、固定随机种子）下跑完单赛季：

| 指标 | 结果 |
|------|------|
| 排名-声望 Spearman 相关系数 | **0.952**（理想接近 1.0） |
| 冠军 | rep=95 的 Team 1（48 分） |
| 垫底 | rep=30 的 Team 10（8 分） |

说明：**在阵容实力与声望严格挂钩的实验环境下，引擎能产出合理排名**。玩家遇到的极端倒挂，更可能来自真实存档中的多重叠加因素，而非单一「随机掷骰」。

#### 2. 代码层根因（按影响度排序）

**① 实力差距被人为压缩（主因）**

`tactics_resolver.lua` 的 `matchupModifiers`：

```lua
-- 比赛日状态波动 ±18%
local formFactor = 0.82 + Random() * 0.36  -- [0.82, 1.18]

-- 50% 压缩：原始比 3.17 → 压缩后 2.08
local dampedRatio = 1.0 + (attackVsDefense - 1.0) * 0.50

local chanceCreation = dampedRatio * homeBonus * ... * formFactor + moraleBonus
-- 最终 clamp 到 [0.55, 1.70]
```

诊断数据（强队 rep=95 vs 弱队 rep=30）：

| 参数 | 值 |
|------|-----|
| 原始 attack/def 比 | 3.17 |
| 50% 压缩后 | 2.08 |
| 叠加 formFactor 后 chanceCreation **均值** | **1.70（撞上上限）** |

强队优势被 **clamp 上限 1.70** 截断；弱队则有 **下限 0.55** 保底。双向钳制使「一场比赛的实力差」最多体现约 ±70%，长期累积后中游队可频繁逆袭。

**② 与战术无关的随机进球**

`match_engine.lua` 每分钟有 `setPieceChance = 0.004`（定位球/点球/乌龙），90 分钟期望约 **0.36 球/队/场**，不参考球队实力。弱队每场白捡约 1/3 球的期望，38 轮联赛累计可观。

**③ 射门链路高底线**

```lua
local shotChance   = clamp(0.28 + attackMod.chanceCreation * 0.16, 0.22, 0.52)
local goalChance   = clamp(0.20 + finishing * 0.08 * shotQuality - ..., 0.13, 0.33)
```

即使 chanceCreation 偏低，射正后仍有 **最低 13%** 进球率，弱队射门转化率不会趋近于零。

**④ 难度档位「比赛波动」**

`difficulty_settings.lua` 中 `matchTier=3`（戏剧性强）时：`varianceFactor=1.4`、`underdogBoost=0.2`（弱队加成，主要作用于 `placeholder_engine`）。默认 `matchTier=2`，但若玩家调高戏剧性，爆冷频率会进一步上升。

**⑤ 真实数据与长期经营叠加（推测，待实测）**

- FM 导入球员的 `overall` 与 `team.reputation`（由 wage_budget 推算）可能不完全同步
- 多赛季后转会、财务、伤病、士气、AI 换帅等会改变阵容，使「开档豪门」不再是赛场强队
- 中游队（如 bug-log 实验中 rep=75 排第 6、rep=68 排第 4）已有局部倒挂，说明 **中游区域对随机更敏感**

### 优化方案

#### 阶段 A — 快速调参（已迭代）

> **2026-06-11 修订**：反馈认为调参前的 chanceCreation 公式（50% 压缩、±18% 状态波动、下限 0.55）更合理，问题集中在**上限 1.70 导致 100% 撞顶**。现改为**仅抬高上限**，其余比赛参数恢复调参前。

| 改动点 | 调参前 | 全量阶段 A（已废弃） | **当前方案** |
|--------|--------|---------------------|-------------|
| 实力压缩比例 | 50% | 30% | **50%（保持）** |
| formFactor 波动 | [0.82, 1.18] | [0.92, 1.08] | **[0.82, 1.18]（保持）** |
| chanceCreation 下限 | 0.55 | 0.42 | **0.55（保持）** |
| chanceCreation 上限 | 1.70 | 2.20 | **2.40（仅改此项）** |
| setPieceChance | 0.004/min | 0.002/min | **0.004/min（保持）** |
| goalChance 下限 | 0.13 | 0.08 | **0.13（保持）** |

**上限 2.40 的选取依据**：强打弱时 `dampedRatio≈2.08`；旧上限 1.70 使 100% 样本撞顶、均值锁死 1.70；升至 2.40 后撞顶约 **8%**（状态极好时才触顶），均值约 **2.09**，既保留原公式手感，又让强队优势能传导进场。

#### 阶段 A 测试结果（2026-06-11，修订版）

| 指标 | 调参前（上限 1.70） | 全量阶段 A | **当前（仅抬高上限）** |
|------|---------------------|-----------|----------------------|
| 单场 Spearman（seed=42） | 0.976 | 0.879 | **0.976** |
| 20 种子平均 Spearman | 0.908 | 0.901 | **0.908** |
| 弱队夺冠 / 20 种子 | 0 | 0 | **0** |
| 强队垫底 / 20 种子 | 0 | 0 | **0** |
| 强弱对话强队胜率 | 85.0% | 90.5% | **85.5%** |
| chanceCreation 撞顶率 | **100%** | 0% | **7.7%** |
| chanceCreation 均值（强 vs 弱） | 1.70（锁死） | 1.65 | **2.09** |

**结论**：当前方案在保留调参前联赛相关性与强弱胜率的前提下，将撞顶率从 100% 降至约 8%，解决「强队优势无法传导」的核心问题，且避免全量收紧随机性带来的 Spearman 下滑。

#### 全面模拟报告（2026-06-11）

测试脚本：`tests/comprehensive_balance_sim_test.lua`（10 种子 × 5 赛季 × 10 队联赛，另含五联赛并行与伤病压力测试）

| 维度 | 结果 |
|------|------|
| chanceCreation 均值 / 撞顶率 | 2.083 / **8.0%** |
| 50 赛季样本 Spearman | 均值 **0.909**（min 0.758, max 1.000） |
| 弱队夺冠 (rep≤45) | **0 / 50** (0%) |
| 强队垫底 (rep≥82) | **0 / 50** (0%) |
| 豪门夺冠 (rep≥88) | **43 / 50** (86%) |
| 冠军分布 | elite 43 / strong 6 / mid 1 / weak 0 |
| 场均进球 | **3.19** |
| 主场胜率 / 平局率 | 43.7% / 20.0% |
| 大冷门率 (rep 差≥30 弱胜强) | **3.71%** |
| 豪门 vs 保级直接对话强队胜率 | **81.3%** (732/900) |
| 强弱对话 2000 场强队胜率 | **86.6%**，场均 4.16 球 |
| 伤病累积 5 赛季 Spearman | 0.903 → 0.830，强队垫底 0 次 |
| 五联赛单赛季 Spearman | EPL 0.903 / 西甲 0.964 / 意甲 0.842 / 德甲 0.976 / 法甲 0.903 |

**综合判断**：当前参数在隔离环境下表现稳定，排名与声望高度相关，极端倒挂（弱队夺冠、强队垫底）未出现；仍有约 3.7% 大冷门和 14% 非豪门夺冠，保留一定戏剧性。

#### 老参数 vs 当前参数 对比（同脚本双跑，2026-06-11）

测试脚本已支持 `legacy(1.70)` 与 `current(2.40)` 双配置对比（`comprehensive_balance_sim_test.lua`）。

| 指标 | 老参数 (上限 1.70) | 当前 (上限 2.40) | 差异 |
|------|-------------------|-----------------|------|
| chanceCreation 均值 | **1.700**（锁死） | **2.083** | 撞顶修复 |
| 撞顶率 | **100%** | **8%** | 显著 |
| Spearman 均值 | 0.909 | 0.909 | 无实质差异 |
| 弱队夺冠 / 强队垫底 | 0/50 / 0/50 | 0/50 / 0/50 | 相同 |
| 豪门夺冠 | 44/50 | 43/50 | 近似 |
| 场均进球 | 3.19 | 3.19 | 相同 |
| 大冷门率 | 3.73% | 3.71% | 近似 |
| 强弱对话强队胜率 | 87.3% | 86.6% | 近似 |
| 五联赛平均 Spearman | 0.920 | 0.918 | 近似 |

**结论**：在相同公式（50% 压缩、±18% 波动）下，**仅抬高上限不改变隔离模拟的联赛格局**；老参数的问题主要体现在 chanceCreation 统计量失真（100% 撞顶、均值锁死 1.70），而非积分榜或胜率的大幅偏移。抬高上限是「统计修正」，对当前测试口径下的平衡影响极小。

#### 阶段 B — 引擎真实化改造（已实施，2026-06-11）

> 起因：玩家反馈「OVR 90+ 输 70+ 还被打 0:5」。诊断发现 90 vs 70 的强队主场胜率仅 ~65%、弱队 17%，0:5 概率 ~0.1%/场 — 核心是 **OVR 差没有有效传导进比赛引擎**。

**四个失真点与修复**（文件：`tactics_resolver.lua`、`match_engine.lua`、`match_session.lua`）：

| # | 失真点 | 修复 |
|---|--------|------|
| 1 | 攻防量纲失衡：`buildTeamContext` 防守权重总和≈进攻的 1.4 倍，92 队 attack(36.8) < 72 队 defense(40.5)，实力差在比值中消失 | `DEF_TO_ATK_SCALE=1.40` 归一；同时修正 `defensePressure`（修复前同实力恒撞 1.40 上限） |
| 2 | 实力差被属性聚合稀释 | context 新增 `avgPlayerOverall`（首发 OVR 均值）；`matchupModifiers` 新增 `strengthFactor = 1 + ovrGap × 0.008`，clamp [0.78, 1.22] |
| 3 | formFactor 每分钟重掷，±18% 被 90 次平均成 ±2%，「今日状态」语义丢失 | 单场一次采样存入 `state._homeFormFactor/_awayFormFactor`，分段模拟（session）兼容 |
| 4 | 与实力无关的保底进球：定位球 0.004/min 不看实力；goalChance 下限 0.13 | 定位球按 OVR 差缩放 `clamp(1+gap×0.025, 0.60, 1.25)`；goalChance 下限降至 0.08、defensePressure 系数 0.03→0.05 |
| 5 | 无大比分护栏，弱队可堆 0:5 | 弱侧护栏：OVR 差 ≥12 且弱队领先 ≥2 球后，后续进球概率 ×0.6^(lead-1)；不限制强队大胜 |

> 2026-06-11 二次调参：按「差 20 强队主场 ~75%、弱队 ~10%」目标，将 slope 0.018→0.008、比值压缩 50%→60%（×0.40）、phaseChance attackBoost 上限 0.08→0.04、shotChance 上限 0.52→0.50、定位球缩放收窄。

**校准结果**（`tests/ovr_gap_calibration_test.lua`，每档 2000 场，强队主场）：

| OVR 差 | 强队胜% | 平局% | 弱队胜% | 场均球 | 弱队净胜4+ |
|--------|---------|-------|---------|--------|-----------|
| 0 | 39.4 | 25.2 | 35.4 | 3.07 | 2.20% |
| 10 | 65.0 | 18.8 | 16.3 | 3.36 | 0.10% |
| 20 | **76.2** | 14.7 | **9.0** | 3.82 | **0.10%** |
| 20（客场） | 67.9 | 18.1 | 14.0 | 3.62 | 0.15% |

**改造前后对比**（`blowout_upset_test.lua`，90 vs 70 主场 3000 场）：

| 指标 | 改造前 | 改造后 | 目标 |
|------|--------|--------|------|
| 强队胜率 | 65.6% | **77.1%** | ~75%（<80%） |
| 弱队胜率 | 16.5% | **9.0%** | ~10% |
| 0:5 惨败 | 0.07% | **0.00%**（0/3000） | ≈0 |
| 强队净负3+ | 1.90% | **0.50%** | 极罕见 |

**回归**：`match_engine_test` / `tactics_resolver_test` / `match_report_test` / `balance_diag_test` / `comprehensive_balance_sim_test`（Spearman 0.934，大冷门 2.38%）/ `five_season_simulation_test` 全部通过。

#### 阶段 C — 验证指标（达成情况）

| 指标 | 目标 | 现状 |
|------|------|------|
| 单赛季排名-声望 Spearman | ≥ 0.85 | **0.93+** |
| 弱队夺冠 / 强队垫底（50 赛季） | 0 | **0 / 0** |
| OVR 差 20 强队主场胜率 | ~75%（70–82%） | **76.2%** |
| OVR 差 20 弱队胜率 | ~10%（5–13%） | **9.0%** |
| 弱队 0:5 强队（差 20） | ≈0 | **0.00%** |
| 后续 | 用真实 FM 数据跑 20 赛季验证豪门降级率 | 待做 |

---

## BUG-20260611-05 · 低潜力球员 OVR 可破 90

**标签**: `数值`  
**关联模块**: `scripts/domain/player.lua`、`scripts/systems/potential_system.lua`、`scripts/systems/training_manager.lua`、`scripts/systems/season_manager.lua`

### 问题复述

玩家反馈 PA ≈ 70 的球员经培养后 OVR 可达 90+，与「潜力决定上限」设计不符。

### 研究结论（2026-06-11）

#### 1. 设计意图 vs 实现缺口

当前存在**两套上限机制**，彼此不一致：

| 机制 | 函数 | PA=70 时行为 | 问题 |
|------|------|-------------|------|
| 单项属性上限 | `getAttrCap()` | `ceil(70/5) = 14` | ✓ 合理 |
| 总评上限 | `getOverallCap()` | 固定返回 **99** | ✗ 与潜力脱钩 |

`calculateOverall()` 仅在最后一步 `min(overallCap, overall)`，而 `overallCap=99` 形同虚设；**真正约束成长的是 attrCap**，理论上 PA70 → 全属性 14 → OVR ≈ **72–79**（依位置加权）。

#### 2. 隔离测试结果

`tests/balance_diag_test.lua`，默认训练档位 tier=3（宽松）、高强度训练 300 天：

| 指标 | 结果 |
|------|------|
| 原始 PA | 70 |
| 局内 actualPotential（seed=42） | 65 |
| attrCap | 13 |
| 300 天训练后 OVR | **67** |
| 理论 OVR 上限（全属性=attrCap） | **≈72** |

**100 种子扫描**（仅换 `potentialSeed`，不训练）：

| 指标 | 结果 |
|------|------|
| 理论 OVR ≥ 90 的种子数 | **1 / 100** |
| 最高理论 OVR | **90** |

结论：在**从零培养**的路径下，PA70 绝大多数情况到不了 90；玩家个例可能来自以下例外路径。

#### 3. 代码层根因（按可能性排序）

**① `actualPotential` 波动可抬高上限（主因之一）**

`potential_system.lua` 将 PA70 映射为 rating 5.5，中心区间 65–71，波动 ±5：

```
actualPotential 范围 ≈ [60, 76]
attrCap = ceil(76/5) = 16 → 理论 OVR ≈ 90
```

玩家看到的「PA 70」是原始值，但局内上限由 **`actualPotential`** 决定，最高可比显示值高 6 点。

**② FM 导入数据未做属性钳制**

`real_data_loader.lua` 直接写入 `attributes` 和 `overall`，不调用 `getAttrCap()` 校验。若源数据中 PA70 球员已有 OVR 82、部分属性 16+，则**存量高属性不会被削回**。

**③ 赛季末成长爆发**

`season_manager.lua` 对 ≤21 岁球员：**每个属性 60% 概率 +1**（19 项属性独立掷骰），一年可涨十余点；且使用 `floor(pot/5)` 而非 `ceil(pot/5)`（与 `getAttrCap` 不一致），上限判定有 1 点偏差。

**④ 成长来源叠加**

日常训练（`training_manager`，默认 tier=3 宽松 baseChance=0.10）+ 赛季末成长 + 青训训练，三路并行，Young PA70 球员成长速度远超玩家直觉。

**⑤ `getOverallCap()` 误导训练终止条件**

```lua
if (player.overall or 0) >= overallCap then  -- overallCap=99，几乎永不触发
```

训练系统在 OVR 到达潜力真实上限**之前不会停止**，只靠 attrCap 单项阻塞；当多项属性触顶后，训练效率骤降但赛季末爆发仍可推高 OVR。

#### 4. PA → 理论 OVR 对照表（建议口径）

| 原始 PA | actualPotential 典型范围 | attrCap 范围 | 理论 OVR 上限 |
|---------|--------------------------|-------------|--------------|
| 70 | 60–76 | 12–16 | 72–90 |
| 80 | 75–84 | 15–17 | 84–93 |
| 90 | 88–94 | 18–19 | 93–96 |
| 95+ | 93–99 | 19–21 | 96–99+ |

玩家反馈的「PA70 → 90+」在 **actualPotential 偏高 + 导入高起始属性** 时是可复现的，不完全是随机 bug，而是**上限体系不完整**。

### 优化方案

#### 阶段 A — 统一上限口径（推荐优先）

**1. 新增潜力总评上限函数**（`player.lua`）

```lua
function Player:getPotentialOverallCap()
    if self.isLegend then return Constants.LEGEND_OVERALL_MAX end
    local pot = self.actualPotential or self.potential or 60
    if pot >= Constants.SUPERSTAR_POTENTIAL_THRESHOLD then
        return Constants.SUPERSTAR_OVERALL_MAX  -- 101
    end
    -- 分段映射：PA70→78, PA80→86, PA90→94（待精调）
    return math.min(Constants.ABILITY_MAX, math.floor(pot * 1.1 + 1))
end
```

**2. `getOverallCap()` 改为调用 `getPotentialOverallCap()`**（非传奇不再固定 99）

**3. 数据加载后钳制**（`real_data_loader.lua` 或 `PotentialSystem.initializeAllPlayers` 之后）

```lua
-- 伪代码：对每个球员
for attr, val in pairs(player.attributes) do
    player.attributes[attr] = math.min(val, player:getAttrCap())
end
player:calculateOverall()
player.overall = math.min(player.overall, player:getPotentialOverallCap())
```

**4. 统一赛季成长上限**：`season_manager` 改用 `player:getAttrCap()`，去掉硬编码 `< 20`。

#### 阶段 B — 收紧波动与成长速率

| 改动点 | 现状 | 建议 |
|--------|------|------|
| PA70 actualPotential 波动 | ±5 | ±3 |
| U21 赛季末 growthChance | 60%/属性 | **40%/属性**（≤21 且不乘出场系数） |
| 训练终止条件 | overall >= 99 | overall >= getPotentialOverallCap() |

#### 阶段 C — 体验与透明度

- UI 显示「预估上限 OVR」（基于 actualPotential 或球探报告揭示）
- 球探报告逐步揭示真实潜力区间，而非只显示原始 PA

#### 验证指标

| 指标 | 目标 |
|------|------|
| PA70 球员 5 赛季高强度培养后 OVR | ≤ 82（99% 分位） |
| PA70 理论 OVR ≥ 90 的种子占比 | 0%（调参后） |
| FM 导入后属性超过 attrCap 的球员数 | 0 |
| `getAttrCap` 与赛季成长上限一致性 | 100% 走同一函数 |

### 改动预估

- 阶段 A：3 个文件，约 **1 天**
- 阶段 B：难度参数 + 1 个测试，约 **0.5 天**
- 阶段 C：UI 文案，约 **0.5 天**（可后置）

---

## REQ-20260611-05 · 成长与训练体系 v2（出场挂钩）

**标签**: `机制`, `数值`  
**关联模块**: `scripts/app/constants.lua`、`scripts/systems/training_manager.lua`、`scripts/systems/youth_manager.lua`、`scripts/systems/season_manager.lua`、`scripts/match/placeholder_engine.lua`、`scripts/systems/transfer_manager.lua`（租借出场统计）  
**设计输入**: 2026-06-12 玩家方向 — 成年期训练与一线队出场挂钩；青训训练日跟随一线队；青年期青训加成略高于一线队。  
**设计确认**: 2026-06-12 第二轮审阅（见 [§ 设计确认清单](#设计确认清单2026-06-12)）。

### 设计确认清单（2026-06-12）

| # | 开项 | 决定 |
|---|------|------|
| 1 | 赛季中过生日：quota / 挂钩按何时年龄 | **B — 按赛季初年龄**，整季规则不变 |
| 2 | 赛季末爆发 vs 出场挂钩 | **22 岁起**赛季末才乘 `participationFactor`；**≤21 岁**赛季末概率 **40%/属性**（原 60% 下调） |
| 3 | 效率下限 | **25%** 维持 |
| 4 | AI 是否同方案 | **要**，实施前先评估（见 [§ AI 同方案压力评估](#ai-同方案压力评估)）；建议玩家队验证后再合 AI |
| 5 | 21 岁一线队、无出场要求 | **符合预期** |
| 6 | 出场计数范围 | **仅俱乐部**正式赛；国家队 / 世界杯 **不计** |
| 7 | 练满配额 | **22 岁 12 场** 起，每岁 **+2**，**27 岁起封顶 25 场** |
| 8 | 冬窗转会 | **赛季内累计**（换队不清零） |
| 9 | 22+ 仍在 `_youthPlayerIds` | **自动解约并删库**（低潜释放逻辑：有潜转自由球员 / 无潜 `gameState.players` 移除）；每月青训例行 + Housekeeping 兜底 |

**配额表（最终）**

| 年龄 | 满效所需出场/季 |
|------|----------------|
| ≤21 | 不挂钩 |
| 22 | 12 |
| 23 | 14 |
| 24 | 16 |
| 25 | 18 |
| 26 | 20 |
| 27+ | 25 |

### 与旧方案的变化

| 维度 | 旧方案（2026-06-11） | **v2（当前）** |
|------|---------------------|----------------|
| 比赛与成长 | 赛后 micro-growth（分钟×评分）为主 | **训练效率 × 赛季出场系数** 为主；比赛 micro-growth 降为可选增强 |
| 22+ 球员 | 只训练也能满速成长 | **无足够一线队出场 → 无法「练满」** |
| 青训训练频率 | 每日 7 天/周 | **与一线队 `weeklyPlan` 同步**（仅训练日成长） |
| 青年期加成 | 青训每日 + 更高 ageFactor | **同 schedule 下青训 `×1.08` 微调加成**（微微高于一线队） |
| 实施顺序 | A 比赛成长 → B 上限 → C 租借 | **A 上限（BUG-05）→ B 出场挂钩 + schedule → C 租借/UI** |

### 年龄口径（与现有代码对齐）

代码里 **21 岁** 已是多处隐式青年期边界，建议收拢为常量：

| 常量（建议） | 值 | 代码现状 |
|--------------|-----|----------|
| `Constants.YOUTH_PHASE_MAX_AGE` | **21** | `season_manager` U21 赛季末 40%；`training_manager` age≤21 ×1.4 |
| 成年训练挂钩起点 | **22 岁**（`age > YOUTH_PHASE_MAX_AGE`） | **已确认**（2026-06-12） |

**GDD** 写成成长期 &lt; 24 岁，与本方案不冲突：22–23 仍可有 ageFactor 加成，只是训练 **效率** 受出场约束。

### 核心机制 1：成年期训练 × 出场系数

**原则**：22 岁及以上，日常训练与赛季末成长的 **有效速率** 乘以 `participationFactor ∈ [floor, 1.0]`；系数由 **当季累计正式比赛出场** 与 **按年龄递增的练满配额** 决定。

#### 结算时机：不是「每场涨点」，也不是「按月结算」

| 方案 | 做法 | 结论 |
|------|------|------|
| 每场 micro-growth | 赛后直接 +1 属性 | ❌ v2 不采用（难与训练叠加平衡） |
| **按月档位** | 每月 1 号根据上月/累计出场定档，整月固定效率 | ⚠️ 可选简化版；响应慢，赛季初长期低效 |
| **按训练日实时系数（推荐）** | 每个 **训练日** 掷骰前，读当前 `seasonStats.appearances`，算 `apps / quota(age)` | ✅ **v2 采用** |

**推荐方案的工作方式**：

1. **比赛完赛**：`placeholder_engine.applyResult` 给登场球员 `seasonStats.appearances += 1`（**已有**，无需新周期任务）
2. **训练日**（周一/三/五等）：`TrainingManager._trainPlayer` 在计算 `baseChance` 后乘 `getParticipationFactor(player)`
3. **系数随赛季推进动态变化** — 不是月初定档、也不是赛季末才算一次：
   - 8 月 0 场 → 效率 25%（floor）
   - 10 月累计 3 场 → 效率 `max(0.25, 3/quota)`
   - 1 月累计 6 场 → 效率 6/quota
   - 达标后 → 100%，**剩余训练日全部满效**
4. **赛季末成长**（`SeasonManager._processPlayerDevelopment`）：
   - **≤21 岁**（赛季初年龄）：`growthChance = 0.40`/属性，**不**乘 participationFactor
   - **≥22 岁**：沿用年龄档 baseChance（22–24: 0.35 等）× participationFactor（**赛季最终**俱乐部出场）

```text
时间轴（22 岁、赛季初年龄、quota=12，balanced 约 3 训/周）：

  8月        10月         1月          4月
  0场×25% → 4场×33% →  8场×67% →  12场×100%
```

**为何不用按月**：出场是连续发生的，实时系数让「刚踢完一场」在 **下一次训练日** 立刻体现，比「等到下月 1 号改档」更直觉；实现上也只需读已有 `seasonStats`，不新增定时器。

**出场计数**（复用现有字段）：

- 来源：`player.seasonStats.appearances`（`placeholder_engine.applyResult` 已在写入）
- 计入：**俱乐部** 联赛 / 国内杯 / 欧战等正式赛
- **不计**：国家队 / 世界杯、友谊赛（若有）
- 外租：租用方 **俱乐部** 出场计入
- 冬窗转会：**赛季内跨队累计**，不清零
- 仅坐板凳未登场：不计

**挂钩年龄**：`seasonAge = player:getAge(seasonStartYear)`（赛季初年龄，整季固定 quota 与是否挂钩）

#### 练满配额（见文首确认表）

规律：`quota = min(25, 12 + (seasonAge - 22) × 2)`（仅 `seasonAge ≥ 22`）

```lua
Constants.ADULT_TRAINING_APPS_START = 12
Constants.ADULT_TRAINING_APPS_MAX = 25
Constants.ADULT_TRAINING_APPS_STEP = 2
Constants.ADULT_TRAINING_APPS_AGE_FLOOR = 22
Constants.ADULT_TRAINING_APPS_AGE_CAP = 27
Constants.ADULT_TRAINING_APPS_FLOOR = 0.25
Constants.U21_SEASON_END_GROWTH_CHANCE = 0.40  -- 原 0.60

function TrainingManager.getSeasonAge(player, seasonStartYear)
    return player:getAge(seasonStartYear)
end

function TrainingManager.getAppsQuotaForSeasonAge(seasonAge)
    if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then return 0 end
    if seasonAge >= Constants.ADULT_TRAINING_APPS_AGE_CAP then
        return Constants.ADULT_TRAINING_APPS_MAX
    end
    return Constants.ADULT_TRAINING_APPS_START
        + (seasonAge - Constants.ADULT_TRAINING_APPS_AGE_FLOOR) * Constants.ADULT_TRAINING_APPS_STEP
end

function TrainingManager.getParticipationFactor(player, seasonStartYear)
    local seasonAge = TrainingManager.getSeasonAge(player, seasonStartYear)
    if seasonAge <= Constants.YOUTH_PHASE_MAX_AGE then return 1.0 end
    local apps = (player.seasonStats and player.seasonStats.appearances) or 0
    local quota = TrainingManager.getAppsQuotaForSeasonAge(seasonAge)
    return math.max(Constants.ADULT_TRAINING_APPS_FLOOR,
                    math.min(1.0, apps / quota))
end
```

**接入点**：

1. `TrainingManager._trainPlayer`：`baseChance *= getParticipationFactor(player, seasonStartYear)`
2. `SeasonManager._processPlayerDevelopment`：≤21 → `growthChance=0.40` 且不乘系数；≥22 → 原年龄档 × participationFactor
3. `YouthManager._trainTeamYouth`：仅 `_youthPlayerIds` 且 seasonAge ≤ 21
4. **`YouthManager` 每月 / `Housekeeping`**：`seasonAge ≥ 22` 仍在 `_youthPlayerIds` → 自动解约删库（复用 `release` 低潜删除 / 高潜自由球员逻辑，**全队含 AI**）

**玩家体感**：

- 22 岁（赛季初）：需 **12 场/季** 俱乐部比赛练满
- 27 岁（赛季初）及以上：需 **25 场/季**
- 0 出场：整季 floor 25%

**UI（阶段 C）**：

- 训练页 / 球员详情：22+ 显示「本季出场 X / quota(age) · 训练效率 Y%」
- 未达门槛时 Tooltip：「成年球员需比赛锻炼；每增加出场，后续训练日效率提升」

### 核心机制 2：青训训练日跟随一线队

**现状问题**：`YouthManager.processDailyTraining` **每日**执行，一线队 `balanced` 仅 **3 天/周** → 青训体感远快于一线队（REQ-03 根因之一）。

**改动**：

```lua
-- youth_manager.lua _trainTeamYouth 入口
local weeklyPlan = team.weeklyPlan or "balanced"
local planConfig = TrainingManager.WEEKLY_PLAN[weeklyPlan]
if not planConfig.trainDays[gameState.dayOfWeek] then
    return  -- 非训练日：与一线队一致，不成长
end
```

- 非训练日：青训球员 **不获得训练成长**（与一线队 `_restDay` 对齐；体能恢复是否同步可选，建议青训非训练日也 +fitness，与一线队一致）
- AI 球队青训同样遵守该队 `weeklyPlan`（AI 可默认 `balanced`）

### 核心机制 3：青年期青训微调加成

**原则**：在 **同一训练日、同一 baseChance 公式** 下，`_youthPlayerIds` 中 age ≤ 21 的球员额外乘以 **`Constants.YOUTH_TRAINING_BONUS = 1.08`**（+8%，「微微微」高于一线队；可配置 1.05–1.12）。

**与现有 ageFactor 的关系**：

| 因子 | 一线队 | 青训（v2） |
|------|--------|------------|
| 训练日 | weeklyPlan | **同左** |
| baseChance / gap / 设施 | 同公式 | 同公式 |
| ageFactor（≤21 ×1.4） | ✓ | ✓ |
| 青训教练 staffMult | — | ✓（保留） |
| **YOUTH_TRAINING_BONUS** | 1.0 | **1.08** |

去掉「每日训练」后，青年期仍比一线队 **略快**，但不会快 2–3 倍。

### 与 BUG-20260611-05 的合并顺序

| 阶段 | 内容 | 预估 |
|------|------|------|
| **A** | BUG-05：`getPotentialOverallCap`、数据钳制、赛季末与 `getAttrCap` 统一 | 1 天 |
| **B** | REQ-05 v2：出场系数、seasonStartYear、青训 schedule、+8%、22+ 青训删库 | 1–1.5 天 |
| **B′** | AI 训练对齐（见下节评估） | 0.5–1 天 |
| **C** | REQ-03 UI + U21 赛季末 40% 确认 | 0.5 天 |
| **D** | 租借出场计入 + 训练页效率展示 | 0.5–1 天 |
| **E**（可选） | 赛后 micro-growth（小幅度，且受每日/每周上限约束） | 1 天 |

**不建议** 先做 micro-growth 再做出场系数 — 两条线叠加难平衡；v2 以 **出场 → 训练效率** 为主杠杆，逻辑更清晰。

### 验证指标

| 场景 | 期望 |
|------|------|
| PA85、21 岁、0 出场、一赛季 | 训练效率 100%（青年期） |
| PA85、22 岁 seasonAge、0 出场、一赛季 | OVR 增量 &lt; ≥12 场组 **40%** |
| PA85、22 岁、≥12 场 | 训练效率 100% |
| PA85、27 岁 seasonAge、≥25 场 | 满效；18 场 factor=0.72 |
| 22+ 滞留青训 | 下月例行清理后球员从 `_youthPlayerIds` 移除并删库/自由球员 |
| 青训 vs 一线队同 age≤21、同 plan | 青训 OVR 增量约高 **5–10%**（非 2×） |
| 外租 22 岁主力 | 租用方出场计入，留队替补外租者成长 &gt; 留队 0 出场 |
| PA70 五赛季 | 仍满足 BUG-05 上限约束 |

### 建议测试

- `tests/training_participation_test.lua`：22 岁 0 场 vs 15 场，固定种子比 OVR 增量
- `tests/youth_schedule_sync_test.lua`：balanced 计划下 7 日仅 3 日青训成长
- 扩展 `balance_diag_test.lua`：PA70 五赛季 + 出场分组

### 改动文件清单

| 文件 | 改动 |
|------|------|
| `constants.lua` | `YOUTH_PHASE_MAX_AGE`、`ADULT_TRAINING_APPS_*`、`YOUTH_TRAINING_BONUS` |
| `training_manager.lua` | `getParticipationFactor`；`_trainPlayer` 乘系数 |
| `youth_manager.lua` | 训练日检查；`× YOUTH_TRAINING_BONUS` |
| `season_manager.lua` | U22+ 赛季末成长乘系数；BUG-05 attrCap 统一 |
| `player.lua` | BUG-05 上限函数 |
| `player_detail.lua` / 训练 UI | 训练效率与出场进度（阶段 D） |

### AI 同方案压力评估

**结论：性能压力低，逻辑一致性收益高；建议 B 期只上玩家队，B′ 单独 PR 对齐 AI。**

| 维度 | 现状 | 对齐后 | 压力 |
|------|------|--------|------|
| 调用频率 | 每日 `processAITeams` 遍历全部 AI 队 `playerIds` | 同频率；训练日可改为与 `weeklyPlan` 一致（实际 **更少** 掷骰） | **低** |
| 单次开销 | 每人 `Random()<0.03`，硬编码 attr&lt;20 | 每人多一次 `getParticipationFactor`（读 seasonStats + 算术） | **可忽略** |
| 出场数据 | AI 比赛走 `MatchEngine`/`placeholder_engine`，已写 `seasonStats.appearances` | 可直接复用 | **无额外 sim** |
| 人数规模 | 约百队 × ~25 人 ≈ 数千人/日 | 与现循环相同 | **O(球队×球员)**，无新增嵌套 |
| 风险 1 | AI 训练 **不**走 `getAttrCap`（&lt;20 写死） | BUG-05 一并修后 AI/玩家共用 cap | 需测试 |
| 风险 2 | AI 替补出场不足 → 22+ 成长过慢 | 与玩家替补体验一致；AI 赛程 sim 应能覆盖部分出场 | 可观察 5 赛季 sim |
| 风险 3 | 22+ 青训删库 | 每月批量，人数极少 | **低** |

**B′ 实施建议**：复用 `TrainingManager._trainPlayer` 或抽 `_applyDailyGrowth(player, team, …)` 共用；AI 仍可用 `balanced` + `medium` 默认，不必接 UI 焦点。

---

## 其他条目（待研究）

| ID | 下一步 |
|----|--------|
| BUG-20260611-01 | 审查 `ObjectivesManager._checkMonthlyCompletion` 与董事会满意度挂钩 |
| BUG-20260611-02 | 引入上赛季排名 / 阵容 OVR 分档，替代纯声望阈值 |
| BUG-20260611-03 | 排查 `team:serialize()` 遗漏字段，补 save roundtrip 测试 |
| REQ-20260611-01 | 租借补全 UI + 中超数据导入排期 |

---

## 诊断工具

| 文件 | 用途 |
|------|------|
| `tests/balance_diag_test.lua` | 联赛排名相关性、PA70 成长、实力压缩效应 |
| `tests/five_season_simulation_test.lua` | 长期赛季推进回归（待扩展排名断言） |

运行方式：

```bash
python tests/_run_test_local.py tests/balance_diag_test.lua
```

后续可将阶段 A 调参前后的 Spearman 系数、PA70 上限分布写入 CI 报告，防止回退。
