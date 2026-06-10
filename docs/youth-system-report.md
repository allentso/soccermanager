# 青训系统完整报告

> 以下内容全部基于代码实际实现，无任何编造。涉及文件：`youth_manager.lua`、`scout_manager.lua`、`potential_system.lua`、`staff_manager.lua`、`finance_manager.lua`、`world_generator.lua`、`turn_processor.lua`

---

## 一、系统初始化流程

游戏世界生成时（`world_generator.lua`），青训系统按以下顺序初始化：

1. **`RealDataLoader.loadWonderkids(gameState)`** — 加载真实妖人数据（JSON），随机分配到各俱乐部的 `team._youthPlayerIds`
2. **`YouthManager.fillAllTeamsYouth(gameState)`** — 为所有球队补齐青训至 10 人（常量 `INITIAL_YOUTH_COUNT = 10`），已有 wonderkids 的球队只补差额
3. **`PotentialSystem.initializeAllPlayers(gameState)`** — 为**所有球员**（包括青训）生成 PA Rating 和局内实际潜力
4. **`YouthManager._refreshCandidates(gameState)`** — 生成玩家球队的首批 10 名候选球员

---

## 二、候选球员发掘（新人发现）

### 2.1 触发机制

- **调用入口**：`turn_processor.lua` 每月调用一次 `YouthManager.processMonthly(gameState)`（第 939 行）
- **刷新周期**：内部计数器 `_youthRefreshCounter` 每月 +1，达到 **3**（`YOUTH_REFRESH_INTERVAL = 3`）时触发刷新
- 即：**每 3 个月刷新一批新候选**

### 2.2 候选生成算法（`_generateYouthPlayer`）

每次刷新生成 **10 名**候选（`YOUTH_POOL_SIZE = 10`），完全替换旧候选池：

| 属性 | 生成逻辑 |
|------|----------|
| **位置** | 从 10 个位置（GK/CB/LB/RB/CM/CDM/CAM/LW/RW/ST）中等概率随机 |
| **年龄** | `RandomInt(15, 18)`（`YOUTH_MIN_AGE`~`YOUTH_MAX_AGE`） |
| **birthYear** | `gameState.date.year - age` |
| **国籍** | 从 50 个条目的权重池中随机（巴西 18%、阿根廷 10%、法国 10%...中国 2%） |
| **姓名** | 根据国籍从对应名字池随机选取（共 12 个国籍池，每池 20~30 个名字） |
| **潜力(raw)** | `min(99, RandomInt(potentialFloor, 85) + floor(youthDevBonus * 30))` |
| **潜力下限** | `floor(45 * facilityYouthBonus)` — 青训设施越高，下限越高 |
| **overall 上限** | `max(25, floor(potential * 0.5))` |
| **overall 下限** | `floor(25 * facilityYouthBonus)` |
| **overall** | `RandomInt(overallFloor, overallCap)` → 再通过 `calculateOverallFromAttrs` 预计算真实值 |

### 2.3 属性生成（`_generateAttributes`）

- **基础值**：`max(1, floor(overall / 7))`
- **每项属性**：基础值 + `RandomInt(-2, 3)` 的噪声
- **位置加成**：按位置给对应属性额外 +`RandomInt(1~5)`（如 ST 加射门/沉着/速度）
- **硬限制**：所有属性 clamp 到 [1, 20]
- **GK 特殊处理**：`handling` 和 `reflexes` 获得专属加成（其他位置默认为 1）

### 2.4 候选池中的 overall 预计算

候选的 `overall` 使用 `Player.calculateOverallFromAttrs(position, attributes)` 预计算，确保候选列表显示值与签入后一致（避免"签入后数值变化"的体验问题）。

---

## 三、球探准确度与 UI 显示

### 3.1 准确度计算公式（`ScoutManager.getAccuracy`）

```
accuracy = min(0.97, (0.50 + bestScoutAbility * 0.02 + scoutingBonus) * facilityBonus)
```

- `bestScoutAbility`：球队最强球探的 `scouting` 属性值（1-20）
- `scoutingBonus`：`StaffManager.getScoutingBonus` → `min(0.20, bonuses.scouting / 50)`
- `facilityBonus`：`1.0 + scoutFacility * 0.05`（球探设施等级 0-5）
- **范围**：0.50（无球探时）~ 0.97（极限）

### 3.2 对候选球员潜力显示的影响

青训 UI 显示潜力星级时，并不直接呈现真实值。球探准确度引入确定性伪随机偏差，使玩家看到的是估算值，签入后才揭示真实潜力。

---

## 四、签入流程（`signCandidate`）

1. **名额检查**：`team._youthPlayerIds` 长度 ≤ 18（`MAX_YOUTH_SQUAD`）
2. **创建 Player 实体**：
   - `birthYear` 强制 `math.floor()` 确保整数
   - `wage` 固定为 500（`YOUTH_WAGE`）
   - `isYouth = true`
   - `contractEnd` 设为当前年份 + 3 年
3. **设置球队归属**：`player.teamId = team.id`
4. **初始化潜力系统**：
   - `player.paRating = PotentialSystem.rawToRating(player.potential)` — 将原始潜力映射为 1.0~10.0 评级
   - `player.actualPotential = PotentialSystem.generateActualPotential(paRating, seed)` — 使用确定性 PRNG 生成局内实际潜力
5. **加入青训队**：`table.insert(team._youthPlayerIds, player.id)`
6. **从候选池移除**：`table.remove(gameState._youthCandidates, candidateIndex)`
7. **发送消息 + 事件通知**

---

## 五、潜力系统详解（`PotentialSystem`）

### 5.1 原始潜力 → PA Rating

通过分段映射表将 raw potential (37-99) 转为 PA Rating (1.0-10.0, 步进 0.5)：

| Raw Potential | PA Rating | 描述 |
|:---:|:---:|:---|
| 96-99 | 10.0 | 传奇巨星 |
| 93-95 | 9.5 | 绝对巨星 |
| 90-92 | 9.0 | 世界顶级 |
| 87-89 | 8.5 | 世界级 |
| 84-86 | 8.0 | 顶级球员 |
| 81-83 | 7.5 | 一线球员 |
| 78-80 | 7.0 | 优秀球员 |
| 75-77 | 6.5 | 可靠球员 |
| 72-74 | 6.0 | 中上球员 |
| 69-71 | 5.5 | 中游球员 |
| 66-68 | 5.0 | 联赛中游 |
| 63-65 | 4.5 | 联赛替补 |
| 60-62 | 4.0 | 轮换球员 |
| 56-59 | 3.5 | 板凳末端 |
| 52-55 | 3.0 | 低级联赛 |
| 47-51 | 2.5 | 业余水平 |
| 42-46 | 2.0 | 业余球员 |
| 37-41 | 1.5 | 初学者 |
| <37 | 1.0 | 无潜力 |

### 5.2 局内实际潜力（`generateActualPotential`）

- 每个评级有 `centerMin`/`centerMax`/`variance` 三个参数
- 使用 **xorshift32 PRNG**（独立于全局随机状态）+ **Box-Muller 高斯分布**
- 步骤：
  1. 在 `[centerMin, centerMax]` 内均匀选基准点
  2. 施加高斯噪声 × `variance * 0.6`（1σ ≈ variance 的 60%）
  3. 硬限制 clamp 到 `[centerMin - variance, centerMax + variance]`，最终 [30, 99]
- **种子**：`baseSeed + playerId * 7919`（质数偏移，确保每人不同但可复现）

**设计哲学**：高评级（9.0+）波动小（variance 1-2），低评级（3.0 以下）波动大（variance 7-8），模拟"潜力越高越确定"的真实足球规律。

---

## 六、每日训练成长（`processDailyTraining`）

- **调用频率**：每个游戏日一次（`turn_processor.lua` 第 893 行）
- **作用对象**：玩家球队所有青训球员（`team._youthPlayerIds`）

### 6.1 成长逻辑

```lua
growthChance = 0.03 + youthDevBonus  -- 基础3% + 教练加成(最高15%)
```

- 每天每人以 `growthChance` 概率触发一次属性提升
- 随机选取一项属性
- 该属性上限：`min(20, floor(actualPotential / 5))`
- 若当前值 < 上限，则 +1
- 提升后重新计算 `player:calculateOverall()`

### 6.2 成长上限分析

| actualPotential | 单项属性上限 |
|:---:|:---:|
| 50 | 10 |
| 60 | 12 |
| 70 | 14 |
| 80 | 16 |
| 90 | 18 |
| 99 | 19 |

---

## 七、影响青训质量的加成系统

### 7.1 青训教练加成（`StaffManager.getYouthDevBonus`）

```lua
-- 所有职员贡献（不限角色）：
bonuses.youthDev += staff.attributes.youthDev * 0.15
-- 最终加成：
return min(0.15, bonuses.youthDev / 60)
```

- 影响：
  - **候选质量**：潜力 = `basePotential + floor(youthDevBonus * 30)`（最高 +4.5 点）
  - **每日成长**：growthChance 从基础 3% 提升至最高 **18%**（3% + 15%）

### 7.2 青训设施加成（`FinanceManager.getFacilityBonuses`）

```lua
youthQuality = 1.0 + ((facilities.youth or 1) - 1) * 0.10
```

- 设施等级 1~5，对应 `youthQuality` = 1.0 ~ 1.4
- 影响：
  - **候选潜力下限**：`floor(45 * youthQuality)` → Lv1: 45, Lv5: 63
  - **候选 overall 下限**：`floor(25 * youthQuality)` → Lv1: 25, Lv5: 35

| 青训设施等级 | youthQuality | 潜力下限 | Overall 下限 |
|:---:|:---:|:---:|:---:|
| 1 | 1.0 | 45 | 25 |
| 2 | 1.1 | 49 | 27 |
| 3 | 1.2 | 54 | 30 |
| 4 | 1.3 | 58 | 32 |
| 5 | 1.4 | 63 | 35 |

---

## 八、提拔到一线队（`promote`）

1. 从 `team._youthPlayerIds` 移除该球员
2. 加入 `team.playerIds`（一线队）
3. 修改球员属性：
   - `isYouth = false`
   - 新合同 3 年
   - 工资：`max(YOUTH_WAGE * 2, floor(overall * 80))`（即最低 1000，按能力最高可达数千）
4. 发送消息 + 事件

---

## 九、释放球员（`release`）

1. 从 `team._youthPlayerIds` 移除
2. 标记 `player.retired = true`，`player.isYouth = false`
3. **不从 `gameState.players` 删除**（保留历史记录）

---

## 十、传奇球星抽卡系统

### 10.1 解锁流程

- 观看 **10 次广告**（`LEGEND_UNLOCK_ADS = 10`）解锁传奇池
- 解锁时赠送 10 次抽取机会

### 10.2 获取抽取次数

- 每次观看广告获得 **2 次**抽取（`LEGEND_PULL_PER_AD = 2`）
- 连续看满 **3 次**广告（`LEGEND_TEN_PULL_ADS = 3`）后补满至 10 次

### 10.3 十连抽机制

- 消耗 10 次抽取
- 刷新整个候选池为 10 人（普通 + 传奇混合）
- 每次十连**最多出 1 个传奇**（`LEGEND_MAX_PER_PULL = 1`）

### 10.4 概率系统

| 机制 | 数值 |
|------|------|
| 基础传奇概率 | 5%（`LEGEND_BASE_RATE`） |
| 每次未出传奇十连 +增量 | 0.5%（`LEGEND_RATE_INCREMENT`） |
| 概率上限 | 10%（`LEGEND_RATE_CAP`） |
| 保底 | 10 次十连必出（`LEGEND_PITY_COUNT = 10`） |
| 首次十连 | 保底一个传奇（`LEGEND_FIRST_GUARANTEED = true`） |

### 10.5 传奇球员属性

- 来源：`Data/legends_alltime_top50.json`（历史传奇球员数据）
- 呈现为年轻体：年龄 17~19 岁
- 潜力直接使用 JSON 中的值（通常 95）
- 能力值：`RandomInt(55, 70)` 为基础生成属性 → `calculateOverallFromAttrs` 预计算
- 有去重机制：已抽到的传奇不会再出现（`state.pulledLegends` 持久化记录）

### 10.6 单抽

- 消耗 1 次抽取
- 在当前候选池**追加** 1 名普通候选（不替换池）
- 不触发传奇概率

---

## 十一、完整数据流总结

```
世界生成
  ├─ loadWonderkids → 真实妖人随机分配到各队青训
  ├─ fillAllTeamsYouth → 每队补齐至10人（普通生成）
  ├─ initializeAllPlayers → 所有球员生成 paRating + actualPotential
  └─ _refreshCandidates → 玩家队首批候选10人

每日循环（turn_processor）
  └─ processDailyTraining → 3%+bonus概率提升1项属性（受actualPotential上限约束）

每月循环（turn_processor）
  └─ processMonthly → 计数器+1，每3月 _refreshCandidates 刷新候选池

玩家操作
  ├─ signCandidate → 候选→正式青训球员，初始化潜力
  ├─ promote → 青训→一线队，调整合同和工资
  ├─ release → 标记退役
  ├─ doTenPull → 刷新候选池（含传奇概率）
  └─ doSinglePull → 追加1名候选
```

---

## 十二、关键常量速查表

| 常量 | 值 | 含义 |
|------|:---:|------|
| `YOUTH_REFRESH_INTERVAL` | 3 | 每3个月刷新候选 |
| `YOUTH_POOL_SIZE` | 10 | 每批候选数量 |
| `MAX_YOUTH_SQUAD` | 18 | 青训队最大容量 |
| `INITIAL_YOUTH_COUNT` | 10 | 初始每队青训人数 |
| `YOUTH_MIN_AGE` | 15 | 候选最小年龄 |
| `YOUTH_MAX_AGE` | 18 | 候选最大年龄 |
| `YOUTH_WAGE` | 500 | 固定周薪 |
| 每日成长基础概率 | 3% | `growthChance` 基线 |
| 最大成长概率 | 18% | 3% + 15%教练上限 |
| 球探准确度范围 | 0.50~0.97 | 受球探属性+设施影响 |
