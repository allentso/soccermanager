# 荣誉系统、记录系统与存档记录范围审计报告

> 审计范围：`scripts/` 用户代码目录。  
> 目标：全面检查当前项目中的荣誉系统、记录系统，以及存档系统对玩家、球员、球队、赛事、历史等数据的记录范围。

## 1. 总体结论

当前项目已经形成了三层互补的历史与荣誉体系：

1. **运行时荣誉/纪录层**：`RecordsManager`
   - 负责奖杯、联赛纪录、球员纪录、经理生涯纪录。
   - 核心数据挂在 `gameState.records`。
   - 初始化入口见 `scripts/systems/records_manager.lua:19`。

2. **长期历史档案层**：`HistoryManager`
   - 负责每赛季世界历史、转会历史、经理变动、世界杯/欧洲杯冠军、国家队执教历史。
   - 核心数据挂在 `gameState.worldHistory`、`gameState._transferHistory`、`gameState._managerHistory` 等字段。
   - 初始化入口见 `scripts/systems/history_manager.lua:12`。

3. **赛季奖项层**：`AwardsManager`
   - 负责金靴、助攻王、最佳球员、最佳年轻球员、最佳门将、最佳经理。
   - 赛季末计算并写入 `gameState._seasonAwards`，同时返回给 `HistoryManager.recordSeasonEnd()` 写进 `worldHistory.awards`。
   - 入口见 `scripts/systems/awards_manager.lua:13`。

整体上，项目已覆盖：

- 玩家经理奖杯与执教战绩。
- 球员单赛季纪录与历史累计 Top10。
- 球队联赛历史、积分榜历史、赛季财务快照。
- 联赛、国内杯、欧冠、世界杯、欧洲杯冠军记录。
- 转会历史、经理变动历史、国家队执教历史。
- 青训提拔次数、青训候选池、转生防重复记录等。

但也存在几个重要问题：

- `_seasonAwards` 没有直接进入 `GameState.serialize()`，读档后依赖 `_seasonAwards` 的 UI 可能丢失奖项页数据。
- `HallOfFame` 与 `AwardsManager` 的奖项字段存在命名错配。
- `uclSingleSeasonGoals` 是预留字段，未发现实际写入逻辑。
- 历史回填对旧档案不完整，国内杯、欧洲杯、赛季奖项等缺少完整回填。
- 部分历史列表有容量上限，不是无限完整历史。

---

## 2. 相关文件清单

### 2.1 核心状态与存档

| 文件 | 作用 |
| --- | --- |
| `scripts/core/game_state.lua` | 全局状态对象；保存实体、赛事、历史、记录、青训、转生、求职等状态。 |
| `scripts/persistence/save_manager.lua` | 存档写入、读取、消毒、备份、meta 管理。 |
| `scripts/persistence/housekeeping.lua` | 存档瘦身、历史去重、球员职业历史折叠。 |
| `scripts/persistence/migrations.lua` | 存档迁移与旧数据修复。 |

### 2.2 荣誉、记录、历史

| 文件 | 作用 |
| --- | --- |
| `scripts/systems/records_manager.lua` | 奖杯、联赛纪录、球员纪录、经理纪录的核心管理器。 |
| `scripts/systems/history_manager.lua` | 每赛季世界历史、转会历史、经理变动、国家队历史。 |
| `scripts/systems/awards_manager.lua` | 赛季奖项计算与通知。 |

### 2.3 赛事生产端

| 文件 | 作用 |
| --- | --- |
| `scripts/systems/season_manager.lua` | 赛季结束时串联奖项、纪录、历史写入。 |
| `scripts/systems/champions_league.lua` | 欧冠冠军写入 RecordsManager。 |
| `scripts/systems/domestic_cup.lua` | 国内杯冠军写入 RecordsManager。 |
| `scripts/systems/world_cup.lua` | 世界杯冠军、国家队执教历史写入 HistoryManager。 |
| `scripts/systems/euro_cup.lua` | 欧洲杯冠军、国家队执教历史写入 HistoryManager。 |
| `scripts/match/placeholder_engine.lua` | 比赛结束时调用 RecordsManager 统计玩家经理战绩。 |

### 2.4 实体模型

| 文件 | 作用 |
| --- | --- |
| `scripts/domain/player.lua` | 球员基础信息、属性、赛季统计、职业历史、传奇/转生标记。 |
| `scripts/domain/team.lua` | 球队基础信息、阵容、财务、赛季统计、历史、董事会状态。 |
| `scripts/domain/manager.lua` | 经理基础信息、合同、战绩、奖杯、履历。 |
| `scripts/domain/league.lua` | 联赛赛程、积分榜、当前轮次。 |
| `scripts/domain/tournament.lua` | 欧冠/世界杯等锦标赛阶段、分组、淘汰赛、冠军。 |

### 2.5 展示层

| 文件 | 作用 |
| --- | --- |
| `scripts/ui/screens/hall_of_fame.lua` | 名人堂：冠军、奖项、纪录展示。 |
| `scripts/ui/screens/trophy_cabinet.lua` | 奖杯柜：读取 RecordsManager 奖杯/纪录。 |
| `scripts/ui/screens/season_end.lua` | 赛季结算页：展示奖项、历史和总结。 |
| `scripts/ui/screens/team_detail.lua` | 球队详情与历史相关展示。 |
| `scripts/ui/screens/player_detail.lua` | 球员详情展示。 |
| `scripts/ui/screens/player_detail/stats_tab.lua` | 球员统计/职业历史展示。 |
| `scripts/ui/screens/manager_view.lua` | 经理视图展示战绩、奖杯等。 |

---

## 3. 荣誉系统检查

## 3.1 奖杯账本：`records.trophies`

`RecordsManager._ensureData()` 会保证 `gameState.records.trophies` 存在，见 `scripts/systems/records_manager.lua:19`。

当前进入奖杯账本的赛事包括：

| 奖杯类型 | competition | 写入函数 | 来源 |
| --- | --- | --- | --- |
| 联赛冠军 | `league` | `_checkLeagueChampionship()` | 赛季结束时检查玩家球队是否联赛第一。 |
| 欧冠冠军 | `ucl` | `onUCLChampionship()` | 欧冠完成时由 `champions_league.lua` 调用。 |
| 国内杯冠军 | `cup` | `onDomesticCupChampionship()` | 国内杯完成时由 `domestic_cup.lua` 调用。 |
| 世界杯冠军 | `worldcup` | `onWorldCupChampionship()` | 玩家执教国家队夺冠时写入。 |
| 欧洲杯冠军 | `euro` | `onEuroChampionship()` | 玩家执教国家队夺冠时写入。 |

奖杯记录的典型字段：

```lua
{
    season = season,
    year = gameState.date.year,
    competition = "league" | "ucl" | "cup" | "worldcup" | "euro",
    competitionName = "赛事名",
    teamId = playerTeamId,
    teamName = teamName,
    points = ...,
    wins = ...,
}
```

其中联赛冠军写入点见 `scripts/systems/records_manager.lua:453`，实际插入奖杯见 `scripts/systems/records_manager.lua:465`。欧冠、国内杯、世界杯、欧洲杯奖杯分别见 `scripts/systems/records_manager.lua:495`、`scripts/systems/records_manager.lua:530`、`scripts/systems/records_manager.lua:565`、`scripts/systems/records_manager.lua:597`。

### 3.2 经理荣誉同步

经理荣誉分成两套数据：

1. `gameState.records.managerRecords`
   - 细分冠军数：联赛、欧冠、国内杯、世界杯、欧洲杯。
   - 战绩：总比赛、胜平负、胜率、连胜、不败。
   - 经营：转会投入、收入、青训提拔。

2. `manager.stats`
   - `wins`、`draws`、`losses`、`trophies`。
   - 用于经理实体自身展示。

比赛结束时，`RecordsManager.onMatchEnd()` 会只统计玩家球队参与的比赛，并同步写回玩家经理实体的胜平负，见 `scripts/systems/records_manager.lua:77`。

奖杯方面，欧冠、国内杯、世界杯、欧洲杯会调用 `_incrementManagerTrophyStat()` 增加 `manager.stats.trophies`。联赛冠军目前增加了 `managerRecords.leagueTitles`，但没有在同一函数中调用 `_incrementManagerTrophyStat()`，这点需要注意。

### 3.3 赛季奖项

`AwardsManager.processSeasonAwards()` 在赛季末生成奖项，见 `scripts/systems/awards_manager.lua:13`。

每个联赛计算：

| 奖项 | 字段 | 计算逻辑 |
| --- | --- | --- |
| 金靴 | `goldenBoot` | 进球最多；同进球时少出场优先。 |
| 助攻王 | `topAssists` | 助攻最多。 |
| 最佳球员 | `bestPlayer` | 进球、助攻、场均评分、出场数综合评分。 |
| 最佳年轻球员 | `bestYoungPlayer` | 23 岁及以下，至少 5 场，综合评分。 |
| 最佳门将 | `bestGoalkeeper` | 门将零封最多，至少 10 场。 |
| 最佳经理 | `bestManager` | 基于球队表现与预期排名差距。 |

字段生成位置见 `scripts/systems/awards_manager.lua:69` 到 `scripts/systems/awards_manager.lua:81`，最佳经理见 `scripts/systems/awards_manager.lua:274`。

奖项会被插入 `gameState._seasonAwards`，见 `scripts/systems/awards_manager.lua:37`。同时，`SeasonManager` 会把返回的 `awards` 传给 `HistoryManager.recordSeasonEnd()`，使其进入 `worldHistory.awards`。

---

## 4. 记录系统检查

## 4.1 联赛记录

`records.leagueRecords` 初始化见 `scripts/systems/records_manager.lua:27`。

当前包含：

| 字段 | 含义 | 记录内容 |
| --- | --- | --- |
| `highestPoints` | 单赛季最高积分 | 球队、积分、赛季、联赛名。 |
| `mostWins` | 单赛季最多胜场 | 球队、胜场、赛季、联赛名。 |
| `fewestGoalsConceded` | 单赛季最少失球 | 球队、失球、赛季、联赛名。 |
| `consecutiveChampionships` | 连续冠军 | 球队、次数、起止赛季。 |

`_checkLeagueRecords()` 会遍历所有联赛积分榜，检查最高积分、最多胜场、最少失球，见 `scripts/systems/records_manager.lua:184`。

连续冠军只检查玩家所在联赛，逻辑见 `scripts/systems/records_manager.lua:264`，它依赖 `worldHistory` 向前回溯。

## 4.2 球员记录

`records.playerRecords` 初始化见 `scripts/systems/records_manager.lua:36`。

当前包含：

| 字段 | 含义 | 记录方式 |
| --- | --- | --- |
| `singleSeasonGoals` | 单赛季最多进球 | 至少 5 次出场，按 `seasonStats.goals`。 |
| `singleSeasonAssists` | 单赛季最多助攻 | 至少 5 次出场，按 `seasonStats.assists`。 |
| `singleSeasonRating` | 单赛季最高评分 | 至少 10 次出场，按 `seasonStats.avgRating`。 |
| `allTimeGoals` | 历史总进球 Top10 | 当前赛季 + `careerHistory` + `careerTotals`。 |
| `allTimeAssists` | 历史总助攻 Top10 | 当前赛季 + `careerHistory` + `careerTotals`。 |
| `allTimeAppearances` | 历史总出场 Top10 | 当前赛季 + `careerHistory` + `careerTotals`。 |
| `uclSingleSeasonGoals` | 欧冠单季进球 | 已定义但未发现生产端写入。 |

单赛季纪录检查见 `scripts/systems/records_manager.lua:312`。历史累计 Top10 更新见 `scripts/systems/records_manager.lua:387`。

球员自身保存的赛季与职业统计包括：

- `careerHistory`：每赛季明细。
- `careerTotals`：被 Housekeeping 折叠后的早期总计。
- `seasonStats`：当前赛季出场、进球、助攻、黄牌、红牌、均分、零封。

字段定义见 `scripts/domain/player.lua:129`、`scripts/domain/player.lua:131`、`scripts/domain/player.lua:134`。序列化见 `scripts/domain/player.lua:966`，其中 `attributes` 和 `seasonStats` 会压缩成数组以减小存档体积，见 `scripts/domain/player.lua:978` 与 `scripts/domain/player.lua:1003`。

## 4.3 经理记录

`records.managerRecords` 初始化见 `scripts/systems/records_manager.lua:48`。

包含：

| 类别 | 字段 |
| --- | --- |
| 执教周期 | `totalSeasons` |
| 冠军 | `leagueTitles`, `uclTitles`, `cupTitles`, `worldCupTitles`, `euroTitles` |
| 联赛表现 | `bestLeagueFinish` |
| 战绩 | `totalWins`, `totalDraws`, `totalLosses`, `totalMatches`, `winRate` |
| 连续表现 | `longestWinStreak`, `currentWinStreak`, `longestUnbeatenStreak`, `currentUnbeatenStreak` |
| 经营 | `totalSpent`, `totalEarned`, `youthPromoted` |

比赛维度更新入口是 `RecordsManager.onMatchEnd()`，见 `scripts/systems/records_manager.lua:77`。赛季维度更新入口是 `RecordsManager.onSeasonEnd()`，见 `scripts/systems/records_manager.lua:149`。

经理实体本身保存 `stats` 和 `career`，见 `scripts/domain/manager.lua:25`、`scripts/domain/manager.lua:33`，序列化见 `scripts/domain/manager.lua:48`。

## 4.4 青训记录

青训相关记录分两类：

1. 荣誉/成就型：
   - `records.managerRecords.youthPromoted`。
   - 更新入口：`RecordsManager.onYouthPromoted()`，见 `scripts/systems/records_manager.lua:654`。

2. 状态型：
   - `gameState._youthCandidates`：青训候选池。
   - `gameState._youthRefreshCounter`：刷新计数。
   - 球队侧 `_youthPlayerIds`：球队青训球员 ID 列表。

存档字段见 `scripts/core/game_state.lua:305`、`scripts/domain/team.lua:258`、`scripts/domain/team.lua:477`。

## 4.5 转会与经理变动记录

`HistoryManager.recordTransfer()` 会记录转会历史，见 `scripts/systems/history_manager.lua:127`。

转会记录字段：

- `season`
- `date`
- `playerId`
- `playerName`
- `fromTeamId`
- `toTeamId`
- `amount`
- `type`
- `fromTeamName`
- `toTeamName`

转会历史最多保留最近 200 条，见 `scripts/systems/history_manager.lua:150`。

`HistoryManager.recordManagerChange()` 会记录经理变动，见 `scripts/systems/history_manager.lua:159`。

经理变动字段：

- `season`
- `date`
- `teamId`
- `teamName`
- `type`
- `managerName`
- `reason`

经理变动最多保留最近 100 条，见 `scripts/systems/history_manager.lua:175`。

---

## 5. 世界历史系统检查

## 5.1 `worldHistory` 结构

`HistoryManager.recordSeasonEnd()` 是每赛季历史写入入口，见 `scripts/systems/history_manager.lua:28`。

每个赛季记录包含：

```lua
{
    season = season,
    year = gameState.date.year,
    leagues = {},
    awards = awards,
    topTransfers = ...,
    managerChanges = ...,
    playerFinance = ...,
    domesticCups = ...,
    promotionRelegation = ...,
}
```

### 联赛历史

每个联赛记录：

- 联赛名。
- 冠军。
- 亚军。
- 完整积分榜。
- 每队排名、积分、胜平负、进失球。

写入逻辑见 `scripts/systems/history_manager.lua:28` 到 `scripts/systems/history_manager.lua:88`。

### 玩家球队财务快照

如果有玩家球队，赛季结束时记录：

- `seasonIncome`
- `seasonExpense`
- `balance`
- `wageBudget`

写入见 `scripts/systems/history_manager.lua:91` 到 `scripts/systems/history_manager.lua:96`。

### 国内杯冠军

如果 `gameState.domesticCups` 存在，会记录每个联赛杯赛的冠军，见 `scripts/systems/history_manager.lua:98`。

### 升降级

如果存在 `gameState.lastPromotionRelegation`，会写入 `promotionRelegation`，见 `scripts/systems/history_manager.lua:113`。

## 5.2 世界杯、欧洲杯与国家队历史

世界杯冠军记录入口见 `scripts/systems/history_manager.lua:227`。

欧洲杯冠军记录入口见 `scripts/systems/history_manager.lua:255`。

国家队执教历史入口见 `scripts/systems/history_manager.lua:283`，字段包括：

- `season`
- `competition`
- `nationId`
- `nationName`
- `result`
- `matchesPlayed`
- `wins`
- `draws`
- `losses`

世界杯系统调用点见 `scripts/systems/world_cup.lua:993` 与 `scripts/systems/world_cup.lua:1012`。欧洲杯系统调用点见 `scripts/systems/euro_cup.lua:590` 与 `scripts/systems/euro_cup.lua:608`。

## 5.3 球队历史查询口径

`HistoryManager.getTeamHistory()` 只基于 `worldHistory.leagues[].standings` 统计球队历史，见 `scripts/systems/history_manager.lua:354`。

因此当前“球队历史”查询主要覆盖：

- 联赛排名。
- 联赛积分。
- 最佳排名。
- 联赛冠军次数。

它不直接统计：

- 国内杯冠军。
- 欧冠冠军。
- 世界杯/欧洲杯国家队冠军。
- 奖项获奖球员。

这不是 bug，但需要明确：球队历史查询口径偏联赛，不是全荣誉口径。

---

## 6. 存档系统记录范围

## 6.1 存档主流程

`SaveManager` 在写档前会：

1. 规范化运行时标量。
2. 调用 `gameState:serialize()`。
3. 检查坏数值、稀疏数组。
4. 必要时治疗并重新序列化。
5. `sanitize()` 丢弃不可序列化类型并修复非法数值。
6. 写主存档、备份、meta 文件。

消毒逻辑见 `scripts/persistence/save_manager.lua:51`。存档时调用 `sanitize(gameState:serialize(), {})` 的位置见 `scripts/persistence/save_manager.lua:409` 与 `scripts/persistence/save_manager.lua:433`。

## 6.2 `GameState.serialize()` 保存范围

`GameState:serialize()` 入口见 `scripts/core/game_state.lua:234`。

与荣誉/记录/历史直接相关的字段包括：

| 字段 | 是否保存 | 说明 |
| --- | --- | --- |
| `worldHistory` | 是 | 每赛季世界历史。见 `scripts/core/game_state.lua:286`。 |
| `records` | 是 | 奖杯、联赛纪录、球员纪录、经理纪录。见 `scripts/core/game_state.lua:287`。 |
| `_transferHistory` | 是 | 转会历史。见 `scripts/core/game_state.lua:288`。 |
| `_managerHistory` | 是 | 经理变动历史。见 `scripts/core/game_state.lua:289`。 |
| `_worldCupHistory` | 是 | 世界杯冠军历史。见 `scripts/core/game_state.lua:290`。 |
| `_euroHistory` | 是 | 欧洲杯冠军历史。见 `scripts/core/game_state.lua:291`。 |
| `lastPromotionRelegation` | 是 | 最近一次升降级结果。见 `scripts/core/game_state.lua:292`。 |
| `_ntCoachHistory` | 是 | 国家队执教历史。见 `scripts/core/game_state.lua:331`。 |
| `_seasonAwards` | 否 | 未看到直接保存。 |

其他与记录相关的状态：

| 字段 | 说明 |
| --- | --- |
| `inbox`, `news` | 消息和新闻。 |
| `transfers` | 当前转会状态、报价历史等。 |
| `scoutReports`, `scoutDiscoveries`, `shortlist` | 球探与候选名单。 |
| `_youthCandidates`, `_youthRefreshCounter` | 青训候选与刷新状态。 |
| `_legendGacha` | 传奇抽卡状态。 |
| `_reincarnationsDone`, `_reincarnationKnownSources` | 转生防重复记录。 |
| `_gameStartSeason`, `_reincarnationFirstSeasonEnd` | 转生相关赛季状态。 |
| `secondDivision` | 二级联赛/升降级状态。 |
| `_uclCompletedSeasons`, `_uclOverwritePatched` | 欧冠迁移与赛季完成追踪。 |
| `_pendingApplications`, `_pendingOffers`, `_offerCooldown` | 求职系统状态。 |
| `_managerRenewalOffer`, `_managerRenewalOffered` | 经理续约状态。 |
| `objectives` | 赛季目标。 |
| `_pendingNTCoachOffers` | 国家队执教邀请。 |
| `_teamRelations` | 球队关系。 |
| `_activeLoans` | 当前租借状态。 |
| `settings` | 设置。 |

读档恢复入口是 `GameState:deserialize()`，见 `scripts/core/game_state.lua:345`。其中历史/记录字段恢复见 `scripts/core/game_state.lua:359` 到 `scripts/core/game_state.lua:364`，国家队执教历史恢复见 `scripts/core/game_state.lua:426`。

## 6.3 球员存档记录范围

球员序列化入口见 `scripts/domain/player.lua:966`。

保存内容包括：

### 身份与基础

- `id`
- `firstName`
- `lastName`
- `displayName`
- `birthYear`
- `nationality`
- `position`
- `naturalPositions`
- `preferredFoot`
- `weakFoot`

### 属性与能力

- `attributes`：压缩数组保存，见 `scripts/domain/player.lua:978`。
- `overall`
- `potential`
- `paRating`
- `actualPotential`
- `reputation`

### 状态

- `fitness`
- `morale`
- `condition`
- `injured`
- `injuryDays`
- `injuryKind`
- `injuryKindName`
- `injurySeverity`
- `injurySeverityName`
- `injurySeasonEnding`
- `retired`
- `retiredSeason`
- `morale_core`

### 合同与归属

- `contractEnd`
- `wage`
- `value`
- `releaseClause`
- `teamId`
- `squadRole`
- `isYouth`

### 统计与历史

- `careerHistory`：见 `scripts/domain/player.lua:1001`。
- `careerTotals`：见 `scripts/domain/player.lua:1002`。
- `seasonStats`：压缩数组保存，见 `scripts/domain/player.lua:1003`。

### 特殊身份

- `isLegend`
- `legendName`
- `legendData`
- `isReincarnation`
- `reincarnationMatchName`
- `innateTraits`
- `traits`

结论：球员维度的统计保存比较完整，既有当前赛季，也有职业历史和被压缩折叠的总计。

## 6.4 球队存档记录范围

球队序列化入口见 `scripts/domain/team.lua:415`。

保存内容包括：

### 基础信息

- `id`, `name`, `shortName`, `city`, `country`, `colors`
- `jsonTeamId`, `iconPath`
- `stadiumName`, `stadiumCapacity`, `foundedYear`

### 战术与阵容

- `formation`, `formationVariant`, `playStyle`
- `startingXI`, `benchIds`
- `slotRoles`, `slotOffsets`, `customSlots`, `playerDuties`
- `captain`, `penaltyTaker`, `freeKickTaker`, `cornerTaker`
- `activeLineupPreset`, `lineupPresets`

### 财务

- `balance`
- `wageBudget`
- `transferBudget`
- `_baseWageBudget`
- `_financialScale`
- `seasonIncome`
- `seasonExpense`
- `incomeBreakdown`
- `transactions`
- `facilities`
- `ticketStrategy`
- `_lastMatchRevenue`
- `transferList`

### 赞助

- `sponsorContracts`
- `sponsorMonthlyTotal`
- `sponsorContractChosen`
- `pendingSponsorOffers`

### 联赛与人员

- `leaguePosition`
- `managerId`
- `playerIds`
- `staffIds`
- `_youthPlayerIds`

### 训练与赛季统计

- `trainingFocus`
- `trainingIntensity`
- `trainingGroups`
- `seasonStats`
- `history`
- `recentForm`
- `monthlyStats`
- `_lastMonthlyStats`

### 董事会与空缺

- `boardObjective`
- `boardSatisfaction`
- `boardWarnings`
- `managerVacant`
- `vacantSince`
- `_vacantDays`

球队的赛季统计字段定义见 `scripts/domain/team.lua:267`，历史字段见 `scripts/domain/team.lua:273` 到 `scripts/domain/team.lua:275`，序列化相关字段见 `scripts/domain/team.lua:447` 到 `scripts/domain/team.lua:478`。

## 6.5 经理存档记录范围

经理序列化入口见 `scripts/domain/manager.lua:48`。

保存内容：

- 身份：`id`, `firstName`, `lastName`, `displayName`, `birthYear`, `nationality`。
- 归属：`teamId`, `isPlayer`。
- 声望：`reputation`。
- 合同：`wage`, `contractEnd`, `contractYears`。
- 统计：`stats`，含胜平负与奖杯数，见 `scripts/domain/manager.lua:25`。
- 履历：`career`，见 `scripts/domain/manager.lua:33`。

## 6.6 联赛与锦标赛存档记录范围

### 联赛

`League:serialize()` 入口见 `scripts/domain/league.lua:316`。

保存：

- `id`
- `name`
- `country`
- `season`
- `teamIds`
- `currentRound`
- `totalRounds`
- `fixtures`
- `standings`

关键字段见 `scripts/domain/league.lua:323` 到 `scripts/domain/league.lua:326`。

### 锦标赛

`Tournament:serialize()` 入口见 `scripts/domain/tournament.lua:870`。

保存：

- `id`
- `name`
- `shortName`
- `type`
- `season`
- `phase`
- `qualifiedTeams`
- `groups`
- `leaguePhase`
- `knockout`
- `champion`
- `_directR16`

关键字段见 `scripts/domain/tournament.lua:878` 到 `scripts/domain/tournament.lua:883`。

---

## 7. 系统流程

## 7.1 比赛结束

调用链：

1. 比赛引擎完成比赛。
2. `RecordsManager.onMatchEnd(gameState, fixture)` 被调用。
3. 如果玩家球队参与比赛：
   - 增加经理总比赛。
   - 更新胜平负。
   - 更新连胜、不败。
   - 更新胜率。
   - 同步 `manager.stats.wins/draws/losses`。

调用点见 `scripts/match/placeholder_engine.lua:1312`。

## 7.2 赛季结束

调用链见 `scripts/systems/season_manager.lua:211`、`scripts/systems/season_manager.lua:232`、`scripts/systems/season_manager.lua:239`：

1. `AwardsManager.processSeasonAwards(gameState)`
   - 计算赛季奖项。
   - 插入 `_seasonAwards`。
   - 发送新闻与消息。

2. `RecordsManager.onSeasonEnd(gameState)`
   - 增加经理执教赛季。
   - 检查联赛纪录。
   - 检查球员单赛季纪录。
   - 更新球员历史累计 Top10。
   - 检查玩家球队联赛冠军。
   - 更新最佳联赛排名。

3. `HistoryManager.recordSeasonEnd(gameState, awards)`
   - 写入 `worldHistory`。
   - 记录联赛冠军、亚军、完整积分榜。
   - 写入赛季奖项。
   - 写入本季重磅转会、经理变动。
   - 写入玩家球队财务快照。
   - 写入国内杯冠军与升降级结果。

## 7.3 杯赛/洲际赛/国家队赛事完成

- 欧冠完成后调用 `RecordsManager.onUCLChampionship()`，见 `scripts/systems/champions_league.lua:1053`。
- 国内杯完成后调用 `RecordsManager.onDomesticCupChampionship()`，见 `scripts/systems/domestic_cup.lua:482`。
- 世界杯完成后调用 `HistoryManager.recordWorldCupChampion()` 与 `recordNTCoachResult()`，见 `scripts/systems/world_cup.lua:993`、`scripts/systems/world_cup.lua:1012`。
- 欧洲杯完成后调用 `HistoryManager.recordEuroChampion()` 与 `recordNTCoachResult()`，见 `scripts/systems/euro_cup.lua:590`、`scripts/systems/euro_cup.lua:608`。

---

## 8. 展示层检查

## 8.1 奖杯柜

`trophy_cabinet.lua` 读取 `RecordsManager.getTrophies(gameState)` 展示奖杯，见 `scripts/ui/screens/trophy_cabinet.lua:43`。

它主要依赖 `records.trophies`，因此只要 `records` 正确保存，奖杯柜通常可以读档后恢复。

## 8.2 名人堂

`hall_of_fame.lua` 使用两类数据：

- 奖项页读取 `gameState._seasonAwards`，见 `scripts/ui/screens/hall_of_fame.lua:61`。
- 记录页读取 `RecordsManager` 的记录数据。

这带来一个风险：`_seasonAwards` 没有直接进入 `GameState.serialize()`，所以读档后奖项页可能为空或不完整。

另外发现字段命名错配：

| UI 读取 | AwardsManager 实际输出 | 影响 |
| --- | --- | --- |
| `la.bestAssist` | `la.topAssists` | 助攻王可能不显示。 |
| `la.bestPlayer.rating` | `la.bestPlayer.overall` / `score` | MVP 分值可能显示 0。 |
| `seasonAward.bestManager.name` | `bestManager.teamName` 等字段 | 最佳教练名称可能显示 `?`。 |

相关 UI 读取见 `scripts/ui/screens/hall_of_fame.lua:75`、`scripts/ui/screens/hall_of_fame.lua:81`、`scripts/ui/screens/hall_of_fame.lua:85`。AwardsManager 输出见 `scripts/systems/awards_manager.lua:72`、`scripts/systems/awards_manager.lua:75`、`scripts/systems/awards_manager.lua:274`。

---

## 9. 已覆盖内容总结

## 9.1 玩家经理

已记录：

- 当前执教球队。
- 胜平负、胜率。
- 总比赛。
- 连胜、不败纪录。
- 最佳联赛排名。
- 联赛、欧冠、国内杯、世界杯、欧洲杯冠军数。
- 奖杯总数。
- 转会投入/收入。
- 青训提拔数量。
- 经理履历。
- 国家队执教成绩。

## 9.2 球员

已记录：

- 当前赛季统计：出场、进球、助攻、黄牌、红牌、均分、零封。
- 职业历史：`careerHistory`。
- 早期职业总计：`careerTotals`。
- 单赛季纪录：进球、助攻、评分。
- 历史累计 Top10：进球、助攻、出场。
- 年龄、国籍、位置、能力、潜力、声望。
- 传奇、转生、青训等身份标记。

未充分覆盖：

- 欧冠单赛季进球虽然有字段，但没有找到实际写入。
- 杯赛/欧冠/国家队分赛事球员统计不完整。
- 球员个人奖项没有落入球员实体历史，只在奖项记录中体现。

## 9.3 球队

已记录：

- 基础信息、球场、声望。
- 阵容、战术、定位球人选、阵容方案。
- 财务、流水、预算、赞助。
- 联赛排名、赛季战绩、近期状态。
- 球队历史字段。
- 董事会目标与满意度。
- 青训球员列表。
- `worldHistory` 中的联赛排名历史。

未充分覆盖：

- `HistoryManager.getTeamHistory()` 只按联赛积分榜统计，不统计所有奖杯。
- 球队奖杯没有直接挂在 Team 实体上，而是集中在 `records.trophies` 与 `worldHistory`。

## 9.4 联赛、杯赛、国际赛

已记录：

- 联赛赛程、轮次、积分榜。
- 每赛季联赛冠军、亚军、完整排名。
- 国内杯冠军进入 `worldHistory.domesticCups`。
- 欧冠冠军进入 `records.trophies`，锦标赛对象保存 champion。
- 世界杯/欧洲杯冠军进入专门历史表。
- 国家队执教成绩进入 `_ntCoachHistory`。

## 9.5 青训/转生/传奇

已记录：

- 青训候选池。
- 青训刷新计数。
- 球队青训球员 ID。
- 经理青训提拔数量。
- 传奇抽卡状态。
- 转生已完成记录和已知来源，防止重复生成。
- 球员级传奇/转生身份标记。

---

## 10. 主要风险与问题清单

## 10.1 高优先级

### 问题 1：`_seasonAwards` 未直接存档

现象：

- `AwardsManager` 写入 `gameState._seasonAwards`，见 `scripts/systems/awards_manager.lua:37`。
- `GameState.serialize()` 没有看到 `_seasonAwards` 字段。
- `hall_of_fame.lua` 奖项页直接读取 `gameState._seasonAwards`，见 `scripts/ui/screens/hall_of_fame.lua:61`。

影响：

- 读档后名人堂奖项页可能为空。
- 如果只依赖 `worldHistory.awards`，展示层未统一读取，会产生断层。

建议：

- 方案 A：把 `_seasonAwards` 纳入 `GameState.serialize()` / `deserialize()`。
- 方案 B：弃用 `_seasonAwards` 作为持久数据源，名人堂改为从 `worldHistory[].awards` 重建奖项列表。
- 推荐方案 B，避免同一数据维护两份长期来源。

### 问题 2：奖项字段命名错配

现象：

- UI 读取 `bestAssist`，实际输出 `topAssists`。
- UI 读取 `bestPlayer.rating`，实际输出 `overall` 和 `score`。
- UI 读取 `bestManager.name`，实际输出字段并非该名称。

影响：

- 助攻王可能不显示。
- MVP 分值可能显示为 0。
- 最佳教练可能显示 `?`。

建议：

- 统一字段契约。
- 优先修改 UI 读取字段，避免改动数据结构造成旧档兼容成本。
- 同时为旧字段提供一次性兼容读取，例如 `la.topAssists or la.bestAssist`。

### 问题 3：联赛冠军未同步 `manager.stats.trophies`

现象：

- 欧冠、国内杯、世界杯、欧洲杯夺冠后会调用 `_incrementManagerTrophyStat()`。
- 联赛冠军只增加 `managerRecords.leagueTitles`，未见同步增加 `manager.stats.trophies`。

影响：

- 经理实体 `stats.trophies` 与 `records.managerRecords` 可能不一致。
- 经理页如果读取 `manager.stats.trophies`，会少算联赛冠军。

建议：

- 在 `_checkLeagueChampionship()` 中也调用 `_incrementManagerTrophyStat()`。
- 或统一用 `RecordsManager.syncManagerProfile()` 从 `records.trophies` 回算经理奖杯数。

## 10.2 中优先级

### 问题 4：`uclSingleSeasonGoals` 未落地

`records.playerRecords.uclSingleSeasonGoals` 在初始化中存在，见 `scripts/systems/records_manager.lua:44`，但未发现实际更新逻辑。

建议：

- 如果短期不用，移除展示或标记为未启用。
- 如果要启用，需要在欧冠比赛统计中记录分赛事球员进球。

### 问题 5：球队历史查询口径偏窄

`HistoryManager.getTeamHistory()` 只统计联赛排名，见 `scripts/systems/history_manager.lua:354`。

建议：

- 增加 `getTeamHonors()`，从 `records.trophies`、`worldHistory.domesticCups`、锦标赛冠军中汇总。
- UI 上区分“联赛历史”和“全部荣誉”。

### 问题 6：旧存档迁移回填不完整

`RecordsManager.migrateFromHistory()` 存在历史回填入口，见 `scripts/systems/records_manager.lua:748`，但当前回填重点偏联赛、欧冠、世界杯。

建议：

- 增加国内杯、欧洲杯、奖项历史的回填。
- 回填时增加去重 key，避免重复奖杯。

## 10.3 低优先级/设计注意

### 问题 7：转会/经理变动历史是滚动窗口

- 转会历史最多 200 条。
- 经理变动历史最多 100 条。

这有利于存档大小，但不适合“完整历史博物馆”。如果未来要做完整历史，需要另设长期摘要表。

### 问题 8：存档消毒会静默丢弃不支持类型

`sanitize()` 会丢弃 function/userdata/thread 以及非法 key，见 `scripts/persistence/save_manager.lua:51`。

建议：

- 荣誉、历史、记录结构保持纯数据。
- 新增字段不要存函数、对象实例、userdata。

### 问题 9：历史重复问题曾出现过

`housekeeping.lua` 注释指出过去 `worldHistory` 曾重复写入，当前通过去重修复，见 `scripts/persistence/housekeeping.lua:354`。

建议：

- 继续保持赛季历史唯一写入点为 `HistoryManager.recordSeasonEnd()`。
- 避免 UI 或调试入口直接写 `worldHistory`。

---

## 11. 建议修复顺序

1. **修复奖项展示数据源**
   - 名人堂奖项页改为读取 `worldHistory[].awards`，或把 `_seasonAwards` 纳入存档。

2. **修复奖项字段错配**
   - `bestAssist` → `topAssists`。
   - `bestPlayer.rating` → `bestPlayer.score` 或 `overall`。
   - `bestManager.name` → 实际经理名字段，或调整 AwardsManager 输出。

3. **统一经理奖杯统计**
   - 联赛冠军同步 `manager.stats.trophies`。
   - 加强 `syncManagerProfile()` 的调用时机。

4. **完善球队荣誉查询**
   - 新增全荣誉口径，不只看联赛历史。

5. **决定 `uclSingleSeasonGoals` 去留**
   - 不做就移除展示/字段。
   - 要做则补充欧冠分赛事球员统计。

6. **补充迁移回填**
   - 国内杯、欧洲杯、奖项历史补回填。

---

## 12. 最终评价

当前荣誉与记录系统的基础已经比较完整，核心优势是：

- `records.trophies` 作为奖杯账本，结构清晰。
- `worldHistory` 作为赛季历史，覆盖联赛、奖项、转会、经理变动、财务、杯赛、升降级。
- 球员记录兼顾单赛季与职业累计，并能使用 `careerTotals` 支持存档瘦身后的长期统计。
- 经理记录覆盖战绩、冠军和经营成果。

主要短板集中在：

- 奖项数据的持久化与展示源不统一。
- 展示层字段契约与生成层不一致。
- 个别预留字段没有生产端。
- 球队历史查询尚未覆盖全部荣誉。

如果优先修复第 10.1 节的三个高优先级问题，当前系统就可以达到较稳定、可持续扩展的状态。
