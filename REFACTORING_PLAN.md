# OFM Refactoring Plan

## Current State

- **Rust workspace coverage**: 71.60% line / 63.47% function
- **Total workspace tests**: 335 passing
- **TypeScript tests**: 19 (helpers only)

---

## 1. Rust Files Exceeding 400-Line Limit

| File | Lines | Action |
|------|-------|--------|
| `engine/src/live_match/mod.rs` | 679 | Split: extract penalty resolution, phase transitions, snapshot into submodules |
| `ofm_core/src/generator/mod.rs` | 604 | Split: extract player/staff generation helpers into `generation.rs` |
| `ofm_core/src/random_events/message_builders.rs` | 574 | Split: group builders by event category into 2–3 subfiles |
| `ofm_core/src/generator/data.rs` | 533 | Data-only file — acceptable, but review for extraction of constants |
| `ofm_core/src/training.rs` | 527 | Split: extract `check_squad_fitness_warnings` + helpers into `training/warnings.rs` |
| `ofm_core/src/random_events/mod.rs` | 517 | Split: extract `apply_event_response` into `responses.rs` |
| `ofm_core/src/messages.rs` | 463 | Split: group message builders by category (welcome/season, match, staff/board, transfer) |
| `ofm_core/src/news.rs` | 429 | Split: extract article builders into `news/articles.rs` |
| `ofm_core/src/live_match_manager.rs` | 421 | Split: extract `LiveMatchSession` impl methods into `session.rs` |

## 2. TypeScript Files Exceeding 300-Line Limit

| File | Lines | Action |
|------|-------|--------|
| `match/MatchLive.tsx` | 864 | Split: extract MatchControls, MatchTimeline, MatchStats sub-components |
| `pages/Dashboard.tsx` | 830 | Split: extract sidebar nav, tab router, advance-time logic into sub-components/hooks |
| `match/PreMatchSetup.tsx` | 730 | Split: extract LineupSelector, TacticsPanel, MatchPreview sub-components |
| `SquadTab.tsx` | 686 | Split: extract PlayerRow, SquadFilters, StartingXIPanel sub-components |
| `pages/MainMenu.tsx` | 680 | Split: extract SavesList, NewGameForm, SettingsPanel sub-components |
| `HomeTab.tsx` | 557 | Split: extract UpcomingMatch, RecentResults, LeagueSnapshot sub-components |
| `match/PostMatchScreen.tsx` | 461 | Split: extract StatsPanel, RatingsTable, MatchSummary sub-components |
| `PlayerProfile.tsx` | 404 | Split: extract AttributesRadar, CareerHistory, StatsTable sub-components |
| `pages/Settings.tsx` | 395 | Split: extract SettingsSection components for each category |
| `InboxTab.tsx` | 376 | Split: extract MessageCard, MessageDetail sub-components |
| `match/HalfTimeBreak.tsx` | 372 | Split: extract TeamTalkPanel, HalfTimeStats sub-components |
| `TransfersTab.tsx` | 368 | Split: extract TransferList, OfferPanel sub-components |
| `NewsTab.tsx` | 368 | Split: extract ArticleCard, ArticleDetail sub-components |
| `TournamentsTab.tsx` | 367 | Split: extract StandingsTable, FixtureList sub-components |
| `TrainingTab.tsx` | 352 | Split: extract TrainingSchedule, FocusSelector sub-components |
| `ScoutingTab.tsx` | 347 | Split: extract ScoutList, AssignmentPanel sub-components |
| `match/PressConference.tsx` | 337 | Split: extract QuestionCard, ResponseSelector sub-components |
| `TeamProfile.tsx` | 333 | Split: extract TeamHeader, TeamStats sub-components |
| `store/gameStore.ts` | 327 | Split: extract type definitions into `types.ts`, keep store logic lean |

## 3. Modules with 0% or Near-0% Test Coverage

### Priority 1 — Core logic with 0% coverage
| Module | Coverage | Action |
|--------|----------|--------|
| `ofm_core/src/scouting.rs` | 5.26% | Add tests: scout_max_assignments, send_scout validation, process_scouting |
| `ofm_core/src/transfers.rs` | 0% | Add tests: transfer offer flow, validation, acceptance/rejection |
| `ofm_core/src/board_objectives.rs` | — | Add tests: generate_objectives, update_objective_progress, evaluate_objectives |
| `ofm_core/src/season_awards.rs` | 84.97% | Add edge-case tests for remaining 15% |

### Priority 2 — Engine modules with 0% coverage
| Module | Coverage | Action |
|--------|----------|--------|
| `engine/src/ai.rs` | 0% | Add tests: ai_decide, substitution logic, tactic changes |
| `engine/src/report.rs` | 0% | Add tests: from_events stat aggregation, possession calc |
| `engine/src/shared.rs` | 0% | Add tests: trait_bonus, play_style_modifier, home_mod |

### Priority 3 — Tauri command modules (0% coverage, harder to unit-test)
| Module | Coverage | Action |
|--------|----------|--------|
| `commands/game.rs` | 0% | Extract testable logic from commands; test extracted functions |
| `commands/live_match.rs` | 0% | Extract `apply_team_talk` morale logic and `submit_press_conference` logic |
| `commands/time.rs` | 0% | Extract `compute_blocking_actions` (already a pure fn — add tests) |
| `commands/squad.rs` | 0% | Extract validation logic into testable helpers |
| `commands/transfers.rs` | 0% | Thin wrappers — test via ofm_core |
| `commands/staff.rs` | 0% | Thin wrappers — test via ofm_core |
| `commands/messages.rs` | 0% | Thin wrappers — test via ofm_core |
| Other command modules | 0% | Thin wrappers — low priority |

### TypeScript
| Module | Tests | Action |
|--------|-------|--------|
| `lib/helpers.ts` | 19 tests | Already tested |
| `store/gameStore.ts` | 0 | Add tests for store actions |
| All components | 0 | Add smoke tests for key components after splitting |

## 4. Duplicated Logic to Consolidate

| Pattern | Locations | Action |
|---------|-----------|--------|
| `params()` helper | `messages.rs`, `scouting.rs` | Extract to shared utility in `ofm_core/src/utils.rs` |
| Team name lookup by ID | 10+ files across turn/, news.rs, commands/ | Add `Game::team_name(&self, id) -> &str` helper |
| DB path resolution | `commands/game.rs` (6 functions) | Extract `resolve_db_manager(app_handle) -> Result<DbManager>` helper |
| Morale clamping `((base as i16) + delta).clamp(10, 100) as u8` | training.rs, turn/post_match.rs, commands/live_match.rs | Extract `clamp_morale(base: u8, delta: i16) -> u8` utility |
| Side-specific goal extraction from report | turn/post_match.rs, turn/news.rs | Extract `goals_for_side(report, side) -> Vec<GoalEvent>` |
| Save/update pattern | `save_game`, `exit_to_menu` in game.rs | Extract `persist_game(db: &DbManager, game: &Game)` |

## 5. SOLID Violations

### Single Responsibility Principle (SRP)
| Location | Violation | Fix |
|----------|-----------|-----|
| `live_match/mod.rs` | LiveMatchState: phases + simulation + snapshots + penalties + stoppage | Split into submodules: `phases.rs`, `penalties.rs`, `snapshot.rs` |
| `commands/live_match.rs` `submit_press_conference` | Morale calc + news generation + player effects | Extract `process_press_morale()` and press article generation |
| `commands/time.rs` `advance_time_with_mode` | 3 different match-mode code paths | Extract per-mode handler functions |
| `turn/post_match.rs` `apply_match_report` | Fixture + standings + stats + morale + form + board + fan + messages + news | Already uses helpers — just verify each is ≤40 lines |

### Open/Closed Principle (OCP)
| Location | Violation | Fix |
|----------|-----------|-----|
| `random_events/mod.rs` `check_random_events` | Large if-chain for event types | Consider event registry pattern (array of event generators) |
| `shared.rs` `trait_bonus` | Hardcoded match arms per TraitContext | Data-driven trait bonus table |
| `report.rs` `from_events` | Large match on EventType | Acceptable for now (exhaustive match is idiomatic Rust) |

### Dependency Inversion Principle (DIP)
| Location | Violation | Fix |
|----------|-----------|-----|
| `messages.rs`, `scouting.rs`, `news.rs` | Direct `rand::thread_rng()` usage | Accept `&mut impl Rng` parameter for testability |
| `commands/game.rs` | Direct filesystem/DB access | Extract DB helper; testable via mock in future |

---

## 6. Execution Phases

### Phase 2: Rust Splits & Deduplication
1. Extract shared utilities (`utils.rs`: `params`, `clamp_morale`, `team_name` helper)
2. Split `live_match/mod.rs` → submodules (phases, penalties, snapshot)
3. Split `training.rs` → `training/mod.rs` + `training/warnings.rs`
4. Split `messages.rs` → `messages/mod.rs` + category subfiles
5. Split `news.rs` → `news/mod.rs` + `news/articles.rs`
6. Split `random_events/message_builders.rs` → grouped subfiles
7. Split `live_match_manager.rs` → `live_match_manager/mod.rs` + `session.rs`
8. Extract `commands/game.rs` DB helper
9. Extract `commands/live_match.rs` press conference & team talk logic
10. Run `cargo test --workspace` after each split — all 335 tests must pass

### Phase 3: Rust Test Coverage
1. Add tests for `engine/src/ai.rs` (target: 70%+)
2. Add tests for `engine/src/report.rs` (target: 70%+)
3. Add tests for `engine/src/shared.rs` (target: 85%+)
4. Add tests for `ofm_core/src/scouting.rs` (target: 80%+)
5. Add tests for `ofm_core/src/transfers.rs` (target: 70%+)
6. Add tests for `ofm_core/src/board_objectives.rs` (target: 85%+)
7. Add tests for `commands/time.rs::compute_blocking_actions` (pure fn)
8. Extract & test morale logic from `commands/live_match.rs`
9. Target: overall workspace coverage ≥ 80%

### Phase 4: TypeScript Splits
1. Extract `store/gameStore.ts` types → `store/types.ts`
2. Split `Dashboard.tsx` → sidebar, tab-router, advance-time hook
3. Split `MatchLive.tsx` → controls, timeline, stats
4. Split `PreMatchSetup.tsx` → lineup, tactics, preview
5. Split `SquadTab.tsx` → player-row, filters, xi-panel
6. Split `MainMenu.tsx` → saves-list, new-game-form
7. Split remaining >300-line components
8. All splits must preserve exact same rendered output

### Phase 5: TypeScript Test Coverage
1. Add store tests for `gameStore.ts`
2. Add smoke/render tests for key split components
3. Target: 70%+ coverage for utility/store code

---

## 7. Internationalization (i18n) Gaps

### Current Architecture

The backend uses a **dual-output system**:
- Every `InboxMessage` and `NewsArticle` carries **hardcoded English** text (subject, body) as fallback
- Optionally, `.with_i18n(subject_key, body_key, params)` attaches translation keys + interpolation params
- Frontend `src/utils/backendI18n.ts` resolves `be.*` keys via i18next, falling back to raw English if key is missing
- `en.json` contains a `be` section (~70 keys) for backend messages/news
- 6 locales exist: en, es, pt, fr, de, pt-BR

### Modules WITH i18n keys (already wired)

| Module | Coverage |
|--------|----------|
| `messages.rs` (6 of 7 functions) | welcome, schedule, pre-match, match result, staff advice, board expectations |
| `random_events/message_builders.rs` | All 9 builders |
| `player_events/message_builders.rs` | All 4 builders |
| `news.rs` | All 4 article types (match report, roundup, standings, season preview) |
| `training.rs` | Fitness warnings (critical + warning) |
| `scouting.rs` | Scout report (keys only — body text still hardcoded English) |

### Modules with NO i18n keys (hardcoded English only)

| Module | Hardcoded content | Priority |
|--------|-------------------|----------|
| `board_objectives.rs` | Objective descriptions ("Finish in the top X"), board message subject/body | High |
| `end_of_season.rs` | Season review message (4 variants by position), new schedule message, ordinal suffixes ("1st"/"2nd"/"3rd"/"th") | High |
| `messages.rs::transfer_complete_message()` | Subject, body, currency formatting ("€") | Medium |
| `commands/live_match.rs::submit_press_conference()` | News article headline + body | Medium |
| `commands/live_match.rs::apply_team_talk()` | Returns raw JSON with no i18n | Low |

### Partial / Ineffective i18n

| Module | Issue |
|--------|-------|
| `scouting.rs::build_scout_report()` | Has `with_i18n()` but body is a massive English-only formatted string with attribute tables, rating words ("Excellent", "Very Good", "Average", "Below Average"), confidence levels ("High", "Moderate", "Low"), potential descriptions. i18n params only pass `player` and `scout` — the actual report content is untranslatable. |
| `board_objectives.rs` | Objective `description` field is hardcoded English ("Finish in the top X", "Win at least X matches", "Score at least X goals") — these are stored in game state and displayed in UI. |
| `end_of_season.rs` | English ordinal logic (`pos_suffix`) is language-specific. |
| Multiple modules | Sender names like "Board of Directors", "League Office", "Assistant Manager" are hardcoded as fallback strings. Most have `.with_sender_i18n()` but `board_objectives.rs` and `end_of_season.rs` do not. |

### Structural i18n Issues

1. **Duplication**: Same English text exists in Rust (fallback) AND en.json (translation). Any copy change requires updating both.
2. **Dynamic descriptions not translatable**: Board objective descriptions are generated with English templates and stored in `Game` state. The UI displays them directly — no key-based resolution path.
3. **Ordinals are English-specific**: "1st", "2nd", "3rd" logic in `end_of_season.rs` doesn't work for other languages.
4. **Currency symbol hardcoded**: `transfer_complete_message` uses `€` — should use a locale-aware formatter or i18n param.
5. **Complex body text**: Scout reports and press conference articles contain structured English paragraphs that would need decomposition into translatable segments.
6. **Locale file completeness unknown**: `be.*` keys likely missing or incomplete in non-English locale files (es, pt, fr, de, pt-BR).

### Remediation Plan (Phase 6: i18n Hardening)

#### Step 1 — Add missing `with_i18n()` calls to all backend messages

| File | Action |
|------|--------|
| `board_objectives.rs` | Add `with_i18n()` + `with_sender_i18n()` to objectives message |
| `end_of_season.rs` | Add `with_i18n()` + `with_sender_i18n()` to season review + new schedule messages |
| `messages.rs` | Add `with_i18n()` to `transfer_complete_message()` |
| `commands/live_match.rs` | Add `with_i18n()` to press conference news article |

#### Step 2 — Make dynamic descriptions translatable

- Change `BoardObjective.description` from a pre-formatted English string to an i18n key + params pattern (e.g. key `"be.obj.leaguePosition"`, params `{target: "4"}`)
- Frontend resolves description via `t(key, params)` instead of displaying raw string
- Scout report body: replace monolithic English string with structured i18n keys for each section (header, attributes, assessment, potential, confidence)

#### Step 3 — Fix language-specific patterns

- Replace ordinal suffix logic with an i18n key pattern: `t("be.ordinal", {position: N})` — each locale defines its own ordinal rules
- Replace hardcoded `€` with an i18n-aware currency param or locale setting

#### Step 4 — Add missing `be.*` keys to en.json

- Add keys for: board objectives, end-of-season messages, transfer complete, press conference, scout report sections
- Ensure every `with_i18n()` call in Rust has a corresponding entry in en.json

#### Step 5 — Audit & populate non-English locale files

- Generate a diff of `be.*` keys between en.json and each other locale
- Add placeholder/translated entries for es, pt, fr, de, pt-BR

---

## Constraints (Sacred Rules)
- **No behavior changes** — algorithms, domain logic, APIs, return types, edge cases, business rules stay identical
- **All 335 Rust tests must pass** after every change
- **All 19 TS tests must pass** after every change
- **cargo fmt + cargo clippy** clean after every Rust change
- **One module at a time** — commit after each successful split/test addition
