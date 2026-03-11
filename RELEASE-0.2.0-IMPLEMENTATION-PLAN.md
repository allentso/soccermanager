# AI IMPLEMENTATION BLUEPRINT: OPENFOOT MANAGER v0.2.0

**Target Entity:** AI Coding Agent
**Objective:** Execute Phase 1 through 6 of Openfoot Manager v0.2.0.
**Execution Paradigm:** Strict Red-Green-Refactor TDD. Domain isolation in Rust. Orchestration in React/TypeScript.

## 0. GLOBAL CONSTRAINTS & DEFINITION OF DONE (DoD)

The agent MUST adhere to the following constraints for every story:

1. **TDD Mandate:** Write a failing test BEFORE modifying any implementation file.
2. **Domain Isolation:** No game logic in Tauri commands (`src-tauri/src/commands/`). Commands are strictly for I/O, validation, and calling services. No game logic in React components.
3. **Deterministic Tests:** Any logic requiring randomness (Morale, Transfers) MUST use an injectable seeded RNG interface for testing.
4. **Save Compatibility:** Any modification to state structs MUST be accompanied by a database migration test ensuring legacy `v0.1.0` saves load cleanly with safe default values.
5. **No Speculative Code:** YAGNI. Implement exactly what is required to pass the test and fulfill the user story.

---

## EPIC 1: Living World and Matchday Ecosystem

**Objective:** Contextualize matchdays within the broader league without a full multi-league simulation.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **SYS-1.1** | Round-Up Domain Model | **Story:** Implement purely functional data structures to represent matchday summaries.<br>

<br>**AC:** Create `RoundSummary` struct. Must calculate: standings delta, notable upset (highest ELO diff), top scorer delta. Function must be pure (takes current standings + round results -> outputs summary). | `ofm_core::turn`<br>

<br>`ofm_core::news` |
| **SYS-1.2** | Match Resolution Integration | **Story:** Wire `RoundSummary` generation into existing match loops.<br>

<br>**AC:** Modify `finish_live_match` and `advance_time_with_mode` commands to return a `RoundSummaryDTO`. Ensure graceful handling of incomplete rounds (e.g., pending fixtures). | `commands::live_match`<br>

<br>`commands::time` |
| **SYS-1.3** | Weekly Digest Cadence | **Story:** Implement chronological event triggers for storylines.<br>

<br>**AC:** Add logic to check `turn` cadence. Generate localized keys for storylines (e.g., `news.storyline.title_race`) based on point differentials. Prevent duplicate generation in the same in-game week. | `ofm_core::messages`<br>

<br>`ofm_core::turn` |
| **UI-1.4** | Post-Match UI Orchestration | **Story:** Render the DTO in the frontend match summary.<br>

<br>**AC:** Update `PostMatchScreen.tsx`. Map `RoundSummaryDTO` to UI components (Mini Table, Scorer List). Include empty-state fallbacks if data is `null`. | `src/components/match/*` |
| **UI-1.5** | Dashboard Immersion Widgets | **Story:** Surface living world data on the main hub.<br>

<br>**AC:** Create `NextOpponentWidget` and `LeagueDigestWidget` in `HomeTab.tsx`. Connect to game store state. | `src/components/HomeTab.tsx` |

---

## EPIC 2: Financial Foundation and Club Investment

**Objective:** Transform passive financial stats into active constraints and progression mechanics.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **SYS-2.1** | Finance Module Refactor | **Story:** Isolate current financial math into testable services.<br>

<br>**AC:** Extract `process_weekly_finances` into atomic functions: `calc_wages`, `calc_matchday`, `calc_upkeep`. All tests must pass with zero behavioral changes. | `ofm_core::finances` |
| **SYS-2.2** | Season Rollover Payouts | **Story:** Implement end-of-season financial rewards.<br>

<br>**AC:** Define a static payout matrix in `ofm_core`. Apply payout during `end_of_season` execution. Append transaction to club ledger and generate inbox DTO. | `ofm_core::end_of_season`<br>

<br>`commands::season` |
| **SYS-2.3** | Sponsorship State Machine | **Story:** Implement sponsor generation and lifecycle.<br>

<br>**AC:** Create `Sponsorship` struct (base value, duration, bonus criteria). Implement weekly payout tick. Implement bonus evaluation pure functions. Ensure state serializes to DB. | `ofm_core::finances`<br>

<br>`db::schema` |
| **SYS-2.4** | Facility Upgrade Mechanics | **Story:** Implement permanent club modifiers.<br>

<br>**AC:** Create `Facilities` struct (Training, Medical, Scouting). Implement `upgrade_facility` command (deducts funds, increments level). Apply Medical level to existing stamina recovery functions. | `ofm_core::training`<br>

<br>`ofm_core::club` |
| **UI-2.5** | Financial Decision Hub UI | **Story:** Overhaul UI to expose new financial vectors.<br>

<br>**AC:** Update `FinancesTab.tsx`. Add "Sponsors" section (offer selection). Add "Facilities" section (upgrade buttons with fund validation/disabling). Map localized keys. | `src/components/FinancesTab.tsx` |

---

## EPIC 3: Contracts and Squad Commitments

**Objective:** Introduce wage pressure and player retention mechanics.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **SYS-3.1** | Contract Evaluation Engine | **Story:** Create the logic for player renewal demands.<br>

<br>**AC:** Implement `evaluate_renewal_offer(player, offer)`. Return Enum: `Accepted`, `Rejected`, `CounterOffer`. Logic relies on player age, morale, and club reputation. | `ofm_core::player_events` |
| **SYS-3.2** | Renewal Command Handler | **Story:** Expose contract actions to the UI adapter.<br>

<br>**AC:** Create Tauri command `propose_renewal`. If `Accepted`, mutate player state (wage, expiry). Return outcome DTO to UI. Ensure state commits to DB. | `commands::contracts` |
| **SYS-3.3** | Contract Expiry Lifecycle | **Story:** Automate degradation of expiring deals.<br>

<br>**AC:** On season advance, trigger warnings at 12/6/3 months. At 0 months, trigger `execute_free_agency` (remove player from squad, adjust wage bill). | `ofm_core::turn`<br>

<br>`ofm_core::messages` |
| **UI-3.4** | Contract UI Surfacing | **Story:** Build the workflow for managers to renew contracts.<br>

<br>**AC:** Update `PlayerProfile.tsx` with Contract Status. Create `RenewalModal.tsx` with wage/duration sliders. Display real-time validation (e.g., "Exceeds wage budget"). | `src/components/PlayerProfile.tsx` |

---

## EPIC 4: Morale and Human Behavior Overhaul

**Objective:** Move from deterministic "reward buttons" to probabilistic, contextual outcomes.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **SYS-4.1** | Hidden State Architecture | **Story:** Separate visible morale from backend truth.<br>

<br>**AC:** Add `manager_trust` (float) and `unresolved_issues` (Vec) to Player state. Ensure these serialize but are NOT exposed in raw form via DTOs to the UI. | `ofm_core::player` |
| **SYS-4.2** | Probabilistic Response Matrix | **Story:** Replace fixed morale gains with weighted RNG.<br>

<br>**AC:** Create `resolve_interaction(action, player, rng)`. Weights must shift based on `manager_trust` and issue severity. Return `InteractionResult` (StrongPos to StrongNeg). | `ofm_core::player_events` |
| **SYS-4.3** | Diminishing Returns & Caps | **Story:** Prevent morale manipulation loops.<br>

<br>**AC:** Implement an action cooldown registry. Implement a hard cap on morale recovery if `unresolved_issues` is not empty. | `ofm_core::player_events` |
| **UI-4.4** | Obfuscated Feedback UI | **Story:** Display humanized feedback instead of math.<br>

<br>**AC:** Map `InteractionResult` enums to localized strings (e.g., "Player seems unconvinced"). Render warning icons if a player has an unresolved issue, without showing the raw severity float. | `src/components/InboxTab.tsx` |

---

## EPIC 5: Transfer AI and Market Ecosystem

**Objective:** Simulate a reactive transfer market driven by AI agents.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **SYS-5.1** | Market Valuation Algorithm | **Story:** Define how the AI values human-controlled players.<br>

<br>**AC:** Create a pure function calculating a player's base market value modified by contract length and recent form. | `ofm_core::transfers` |
| **SYS-5.2** | AI Bid Generation Loop | **Story:** Allow the system to generate unsolicited offers.<br>

<br>**AC:** Implement a weekly cron/hook. Select a random subset of highly-valued or transfer-listed user players. Generate a `TransferOffer` struct and push to user inbox. | `ofm_core::transfers` |
| **SYS-5.3** | Transfer State Machine | **Story:** Manage the negotiation lifecycle.<br>

<br>**AC:** Implement state transitions for offers: `Pending -> Countered -> Accepted/Rejected`. Ensure accepted offers correctly move the player ID and transfer funds in a single DB transaction. | `ofm_core::transfers`<br>

<br>`commands::transfers` |
| **UI-5.4** | Market Command Center | **Story:** Redesign the transfer UI to handle complex states.<br>

<br>**AC:** Overhaul `TransfersTab.tsx`. Add "Incoming Offers" queue. Build a `NegotiationPanel.tsx` that triggers the counter-offer Tauri commands. | `src/components/TransfersTab.tsx` |

---

## EPIC 6: Hardening, Balancing, and Migration

**Objective:** System stability and backward compatibility.

| ID | Title | Technical User Story & Acceptance Criteria | Target Modules |
| --- | --- | --- | --- |
| **DB-6.1** | State Migration Schema | **Story:** Ensure `v0.1.0` saves do not crash.<br>

<br>**AC:** Write a `migration_v0_1_to_v0_2` script. Provide safe defaults: `manager_trust = 0.5`, `facilities_level = 1`, `sponsorships = null`. Write a test loading a mock `v0.1.0` JSON save. | `db::migrations` |
| **SYS-6.2** | Config Centralization | **Story:** Remove magic numbers from domain logic.<br>

<br>**AC:** Extract all economy, morale, and transfer thresholds into a single `balance_config.rs` file or loadable JSON/TOML, ensuring the designer can tune them safely. | `ofm_core::config` |

---

## EXECUTION DIRECTIVE FOR THE AI AGENT

When instructed to begin, you will execute strictly in this order:

1. Initialize Phase 1. Complete **SYS-1.1**. Do not proceed to SYS-1.2 until SYS-1.1 tests are written, passed, and refactored.
2. Provide a summary of the implemented code and test output upon completion of each story block.
3. If an architectural ambiguity arises, you MUST halt and request clarification rather than guessing an implementation path.
4. Run all the tests in the repository to avoid regressions. If regressions are found, you must fix the tests, and write new regression tests to avoid future regressions.
5. Commit your changes to the repository using git. Use atomic commits, and follow the Conventional Commits 1.0.0 specification to write commit messages.
6. You ARE NOT allowed to commit the `RELEASE-0.2.0-IMPLEMENTATION-PLAN.md` and the `RELEASE-0.2.0-ROADMAP.md` files.
7. After completing a phase, halt and ask for permission to proceed.
