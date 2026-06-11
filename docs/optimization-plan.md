# OpenFoot Manager - 优化方案

**版本**: v1.0  
**对应文档**: [bug-log.md](./bug-log.md)  
**维护说明**: 每条 Bug/需求在此有对应优化条目；研究结论与改动方案记录于此  
**最后更新**: 2026-06-11

---

## 目录

- [总览](#总览)
- [BUG-20260611-04 · 联赛模拟随机性过强](#bug-20260611-04--联赛模拟随机性过强)
- [BUG-20260611-05 · 低潜力球员 OVR 可破 90](#bug-20260611-05--低潜力球员-ovr-可破-90)
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
| U21 赛季末 growthChance | 60%/属性 | **25%/属性** |
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
