# Release 0.2.0 Roadmap

**Status:** Draft planning document

**Purpose:** Define the implementation roadmap for `0.2.0`, focused on:
- deeper financial gameplay
- more human and less deterministic morale behavior
- a more immersive and reactive living world
- contract management and transfer AI foundations

**Repository note:** This document is to be saved in the repository for planning purposes, but it must **not** be committed until explicitly approved.

---

# 1. Release Goals

Release `0.2.0` should move Openfoot Manager from a functional manager-game skeleton to a more systemic football management experience.

The release should make the player feel that:
- money creates meaningful tradeoffs
- players are human, contextual, and unpredictable
- the club exists inside a wider ecosystem that keeps moving
- long-term planning matters as much as the next match

## Primary outcomes

- **[financial stakes]**
  - budgets and cash flow affect training, recovery, scouting, contracts, and transfers

- **[human player behavior]**
  - morale no longer behaves like a simple reward button system

- **[living world feedback]**
  - matchdays and league progress feel connected to an active football world

- **[squad planning pressure]**
  - expiring contracts, bids, and financial limits force medium- and long-term decisions

## Non-goals for `0.2.0`

- **[full multi-league simulation]**
  - do not attempt to build a complete global football pyramid in this release

- **[overly complex agent simulations]**
  - do not add heavyweight systems that cannot be well-tested and explained

- **[UI-first implementation]**
  - do not build shells with fake interactions before domain behavior is tested

- **[premature generalization]**
  - do not introduce abstractions for hypothetical future features unless the current release requires them

---

# 2. Mandatory Engineering Protocol

The implementation agent must follow these rules for every task in this roadmap.

## 2.1 Red-Green-Refactor TDD protocol

Every task must be executed through strict TDD.

- **[red]**
  - write a failing test first
  - the test must describe behavior, not implementation details
  - confirm the test fails for the correct reason

- **[green]**
  - write the minimum code necessary to make the test pass
  - avoid speculative implementation
  - keep the change small and local

- **[refactor]**
  - only refactor once the test suite is green
  - improve naming, extraction, composition, and duplication safely
  - keep behavior unchanged during refactor

- **[repeat]**
  - proceed in many small cycles instead of large batches
  - every new rule, branch, or edge case starts with a failing test

## 2.2 Testing order

When implementing a feature, tests should be added in this order whenever applicable:

- **[domain tests first]**
  - `src-tauri/crates/ofm_core/tests/*`
  - validate business rules and simulation behavior

- **[persistence / migration tests second]**
  - `src-tauri/crates/db/*`
  - verify new fields and save compatibility

- **[adapter / command tests third]**
  - `src-tauri/src/commands/*`
  - keep these thin, but test exposed command behavior where useful

- **[frontend hook/component tests fourth]**
  - `src/**/*.test.tsx` and `src/**/*.test.ts`
  - validate rendering, user interactions, orchestration, and i18n wiring

## 2.3 Clean Architecture rules

The implementation agent must preserve a clear separation of concerns.

- **[domain in `ofm_core`]**
  - all gameplay rules belong in `src-tauri/crates/ofm_core`
  - no business logic should live in React components
  - no significant business rules should live in Tauri command handlers

- **[commands stay thin]**
  - `src-tauri/src/commands/*` should validate inputs, call domain services, and return DTOs/state
  - avoid branching logic there unless it is adapter-specific

- **[frontend stays orchestration-focused]**
  - React components should present data and coordinate interactions
  - extract hooks/helpers when components become orchestration-heavy

- **[persistence stays isolated]**
  - schema and save migration concerns belong in the `db` crate
  - avoid leaking persistence formats into domain rules

- **[randomness must be testable]**
  - probabilistic systems must use injectable or controllable randomness
  - tests must not rely on flaky random outcomes

- **[messages and presentation decoupled]**
  - state mutation and message generation should be separable where practical
  - i18n keys and message payloads must remain consistent and testable

## 2.4 Design principles

The implementation agent must explicitly follow:

- **[SOLID]**
  - single-purpose modules
  - dependency direction toward stable business rules

- **[KISS]**
  - simple rules over simulation bloat

- **[DRY]**
  - shared calculation helpers where behavior repeats
  - avoid duplicate constants and duplicated rule tables

- **[YAGNI]**
  - do not build for hypothetical leagues/features that are not required by `0.2.0`

## 2.5 Definition of done for any roadmap task

A task is only complete when all of the following are true:

- **[tests]**
  - failing tests were written first
  - new and existing tests pass
  - edge cases relevant to the task are covered

- **[architecture]**
  - business rules live in the correct layer
  - no unnecessary coupling was introduced

- **[i18n]**
  - all user-facing strings are localized according to project standards

- **[save compatibility]**
  - new state persists correctly
  - migrations and defaults are covered

- **[usability]**
  - the UI communicates the new rule clearly
  - the player can understand why a system outcome happened

---

# 3. High-Level Delivery Sequence

The implementation should proceed in these phases:

- **[phase 1]** Living World and Matchday Ecosystem
- **[phase 2]** Financial Foundation and Club Investment
- **[phase 3]** Contracts and Squad Commitments
- **[phase 4]** Morale and Human Behavior Overhaul
- **[phase 5]** Transfer AI and Market Ecosystem
- **[phase 6]** Hardening, Balancing, Migration, and UX Polish

## Dependency flow

- **[phase 1 before phase 4]**
  - living-world presentation can ship early and increases immersion quickly

- **[phase 2 before phase 3 and 5]**
  - prize pools, sponsorships, and budgets provide the financial context for contracts and transfers

- **[phase 3 before phase 5]**
  - contract status should influence transfer AI decisions

- **[phase 4 parallel with late phase 3]**
  - morale overhaul needs contract issues, player talks, and press logic to connect properly

---

# 4. Phase 1: Living World and Matchday Ecosystem

## Phase objective

Make the player feel part of an active competition without requiring a full multi-league expansion.

## Player-facing outcomes

- post-match screens show the wider round, not only the user match
- the league tells stories across the season
- weekly and matchday summaries make other clubs feel active
- table movement, rival form, and context are visible more often

## Backend scope

### Task 1.1: Round-up domain model

- **[goal]**
  - create a domain representation for a matchday or round summary

- **[backend implementation points]**
  - add a small domain model in `ofm_core` for:
    - round results
    - standings delta
    - notable result / upset
    - golden boot / scorer context
    - next-opponent recent form snapshot
  - derive data from existing league fixtures and standings rather than inventing a parallel system
  - keep calculations deterministic and isolated in pure functions where possible

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/turn/mod.rs`
  - `src-tauri/crates/ofm_core/src/news.rs` or extracted helper modules
  - `src-tauri/crates/ofm_core/src/end_of_season.rs`
  - domain types shared to frontend via serialized DTOs

- **[tests first]**
  - round with completed fixtures builds correct result list
  - standings delta is correct before/after the user matchday
  - notable upset logic chooses the biggest expected mismatch outcome
  - empty or incomplete rounds degrade gracefully

### Task 1.2: Post-match round-up generation

- **[goal]**
  - generate post-match context immediately after live/delegate/simulated matches

- **[backend implementation points]**
  - extend live match finishing flow to return or make available:
    - user match result
    - other results from the same round
    - updated standings slice
    - scorer race snapshot
    - next opponent summary
  - ensure delegated and instant/simulated match paths expose the same data shape
  - avoid duplicating logic between `finish_live_match` and `advance_time_with_mode`

- **[likely touchpoints]**
  - `src-tauri/src/commands/live_match.rs`
  - `src-tauri/src/commands/time.rs`
  - `src-tauri/crates/ofm_core/src/turn/mod.rs`

- **[tests first]**
  - live match finishing exposes round-up payload
  - delegated matches expose equivalent round-up payload
  - no crash when some fixtures in round are still pending

### Task 1.3: Weekly digest and league storylines

- **[goal]**
  - create recurring league-level summaries and storylines

- **[backend implementation points]**
  - generate digest data from fixtures, standings, streaks, and scorer tables
  - add storyline categories such as:
    - title race
    - relegation battle
    - unbeaten streak
    - slump / pressure
    - breakout scorer
  - create news/inbox items at a controlled cadence, likely weekly
  - throttle message generation to avoid spam

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/news/`
  - `src-tauri/crates/ofm_core/src/messages.rs`
  - `src-tauri/crates/ofm_core/src/turn/mod.rs`

- **[tests first]**
  - weekly digest is created only on configured cadence
  - storylines are generated from actual standings/form, not random copy
  - duplicate digest generation is prevented on same date

## Frontend scope

### Task 1.4: Post-match round-up UI

- **[goal]**
  - extend post-match flow so the player sees the wider round

- **[frontend implementation points]**
  - update `PostMatchScreen` or create a dedicated sub-panel for:
    - rest-of-round results
    - mini table
    - table movement indicator
    - top scorers snapshot
    - next opponent form block
  - ensure consistent behavior for live, spectator, and delegated matches
  - keep the current match report readable; do not overload one screen

- **[likely touchpoints]**
  - `src/pages/MatchSimulation.tsx`
  - `src/components/match/PostMatchScreen.tsx`
  - `src/components/match/types.ts`
  - `src/store/gameStore.ts`

- **[tests first]**
  - round-up renders when payload is available
  - graceful empty state renders when round-up is partial
  - navigation after match still works

### Task 1.5: Home and News immersion widgets

- **[goal]**
  - surface living-world context outside the match screen

- **[frontend implementation points]**
  - add small sections/widgets for:
    - league digest highlights
    - title/relegation storylines
    - next opponent form
    - rival watch / recent key result
  - ensure Home remains the central “what matters now” tab
  - keep News richer but avoid duplicating the exact same content blocks

- **[likely touchpoints]**
  - `src/components/HomeTab.tsx`
  - `src/components/NewsTab.tsx`
  - translation files under `src/i18n/locales/*.json`

- **[tests first]**
  - widgets render correct data from state
  - empty-state handling is localized
  - duplicate headlines are not rendered in conflicting sections

## Acceptance criteria for phase 1

- **[round context]**
  - after a user match, the player can see what else happened that round

- **[storylines]**
  - league progress is surfaced through digest/storyline content

- **[consistency]**
  - live and simulated match flows expose equivalent ecosystem context

---

# 5. Phase 2: Financial Foundation and Club Investment

## Phase objective

Turn finances into a decision-making system rather than a passive summary screen.

## Player-facing outcomes

- league performance affects money through prize pools
- sponsorships create tradeoffs and objectives
- club investments improve training, recovery, scouting, and youth development
- money shortages directly constrain club planning

## Backend scope

### Task 2.1: Financial model audit and extraction

- **[goal]**
  - stabilize and isolate finance calculations before adding new systems

- **[backend implementation points]**
  - review existing `process_weekly_finances`
  - extract helpers/services for:
    - wage processing
    - matchday revenue
    - sponsorship income
    - facility upkeep
    - prize money
  - remove placeholder logic and make calculations explicit and testable

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/finances.rs`
  - optional focused finance submodules if extraction improves clarity

- **[tests first]**
  - weekly wages deducted correctly
  - home match revenue is calculated consistently
  - no double-counting across consecutive weeks

### Task 2.2: Prize pools and season payouts

- **[goal]**
  - reward performance with money at season boundaries

- **[backend implementation points]**
  - define league position payout table
  - apply payout during season rollover
  - create board/news/inbox messaging for payouts
  - keep payout rules data-driven enough to rebalance later

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/end_of_season.rs`
  - `src-tauri/crates/ofm_core/src/messages.rs`
  - `src-tauri/src/commands/season.rs`

- **[tests first]**
  - champion payout, top-half payout, and lower-table payout are correct
  - season income and club balance update correctly
  - payout messages are generated once per season

### Task 2.3: Sponsorship deals

- **[goal]**
  - introduce recurring and performance-based sponsorship revenue

- **[backend implementation points]**
  - add a sponsorship domain model with:
    - base value
    - duration
    - objective type
    - bonus criteria
    - active / expired status
  - start simple with a small set of contract types:
    - stable guaranteed sponsor
    - high-risk performance sponsor
    - youth-development sponsor
    - reputation / star-driven sponsor later if needed
  - generate preseason sponsor offers and track current deal
  - apply weekly or monthly payments plus conditional bonuses

- **[likely touchpoints]**
  - new finance-related domain types in `ofm_core`
  - state persistence in `db` repositories and migrations
  - `turn/mod.rs` cadence hooks

- **[tests first]**
  - preseason offers are generated for valid teams
  - selecting a sponsor stores correct deal data
  - periodic payments are applied correctly
  - conditional bonuses pay only when objectives are met

### Task 2.4: Facility investments

- **[goal]**
  - let the player convert money into long-term footballing advantages

- **[backend implementation points]**
  - add upgradeable club facilities, initially:
    - training facilities
    - medical / recovery facilities
    - scouting department
    - youth facilities
  - define for each facility:
    - current level
    - next upgrade cost
    - upkeep impact if any
    - gameplay modifiers
  - connect modifiers into existing systems:
    - `training.rs` for development and fatigue handling
    - recovery calculations for condition/injury recovery
    - `scouting.rs` for assignment speed/quality/capacity
    - youth systems in later phases

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/training.rs`
  - `src-tauri/crates/ofm_core/src/scouting.rs`
  - injury/recovery-related modules
  - state and persistence layers

- **[tests first]**
  - facility upgrade cost and level changes persist correctly
  - training facility level changes affect growth/recovery as specified
  - medical facility level improves recovery metrics within safe bounds
  - scouting facility changes affect report timing or confidence deterministically in tests

### Task 2.5: Financial warnings and decision pressure

- **[goal]**
  - make bad financial decisions visible and consequential

- **[backend implementation points]**
  - expand warnings for:
    - shrinking cash runway
    - overdue contract risk due to wage bill
    - unsustainable facility spending
    - sponsor objective failure risk
  - connect warnings to actionable UI routes
  - keep warning cadence under control to prevent spam

- **[tests first]**
  - warnings trigger at correct thresholds
  - duplicate warnings are throttled
  - warnings include actionable context

## Frontend scope

### Task 2.6: Finances tab redesign

- **[goal]**
  - turn the finances screen into a decision screen, not just a dashboard

- **[frontend implementation points]**
  - redesign `FinancesTab` around sections such as:
    - overview
    - cash flow
    - sponsorships
    - facilities and investments
    - wage pressure and contract risk
  - surface future impact, not just current values
  - show projected weekly or monthly cash movement where possible

- **[likely touchpoints]**
  - `src/components/FinancesTab.tsx`
  - shared UI components
  - locale files

- **[tests first]**
  - sponsor selection UI behaves correctly
  - facility upgrade controls render only when valid
  - budget and projection panels reflect state accurately

### Task 2.7: Sponsor and facility flows

- **[goal]**
  - give the player clear workflows for financial choices

- **[frontend implementation points]**
  - sponsor offer selection screen or panel
  - facility upgrade cards with cost, effect, and level
  - warnings and lock states when funds are insufficient
  - clear explanation of downstream effects on training, recovery, scouting, and youth

- **[tests first]**
  - insufficient-funds behavior is clear and localized
  - accepted sponsor updates state and UI immediately
  - facility upgrade effects are described consistently

## Acceptance criteria for phase 2

- **[money matters]**
  - finances change available strategic options

- **[investments matter]**
  - players can trade short-term balance for long-term club improvement

- **[performance matters financially]**
  - league finish and sponsor objectives affect club income

---

# 6. Phase 3: Contracts and Squad Commitments

## Phase objective

Make player contracts a real planning system with financial and morale consequences.

## Player-facing outcomes

- contract renewals become an active responsibility
- expiring deals create real pressure
- wage decisions shape squad building
- losing players for free becomes a genuine risk

## Backend scope

### Task 3.1: Contract domain rules

- **[goal]**
  - formalize contract behavior beyond a stored end date

- **[backend implementation points]**
  - define contract decision rules using factors such as:
    - wage expectations
    - age
    - squad status / perceived importance
    - morale
    - club performance
    - remaining contract length
  - create evaluation helpers for renewal acceptance likelihood
  - keep initial version simple and data-driven enough to tune later

- **[likely touchpoints]**
  - player domain models
  - `src-tauri/crates/ofm_core/src/player_events/*`
  - finance modules

- **[tests first]**
  - high-performing star expects more than fringe reserve
  - low-morale player becomes harder to renew
  - short remaining term increases urgency

### Task 3.2: Renewal negotiation flow

- **[goal]**
  - allow managers to offer contract renewals

- **[backend implementation points]**
  - add command/service to propose a renewal with:
    - wage
    - length
    - optional role/promise only if required by current scope
  - evaluate offer as accepted, rejected, or asking for improved terms
  - avoid building a giant negotiation tree in `0.2.0`; keep the first version clean and understandable

- **[likely touchpoints]**
  - new contract service in `ofm_core`
  - `src-tauri/src/commands/*` for contract actions
  - state persistence for contract changes

- **[tests first]**
  - accepted offer updates wage and term correctly
  - rejected offer leaves state unchanged
  - counter-expectation path returns understandable feedback

### Task 3.3: Expiry pressure and free agency risk

- **[goal]**
  - make neglect costly

- **[backend implementation points]**
  - escalate urgency windows, for example:
    - 12 months
    - 6 months
    - 3 months
    - final weeks
  - integrate with morale and inbox messages
  - support eventual free departure at contract expiry if not renewed
  - connect to board and finance warnings where relevant

- **[tests first]**
  - warning cadence changes by contract horizon
  - expired contract path is handled cleanly
  - morale pressure intensifies appropriately as expiry approaches

### Task 3.4: Contract pressure in squad planning

- **[goal]**
  - make contract state visible to other systems

- **[backend implementation points]**
  - contract status should influence:
    - morale issue generation
    - transfer AI interest in later phase
    - board pressure for key players
    - wage bill projections in finances

- **[tests first]**
  - contract risk data is exposed to dependent systems
  - key-player contract risk appears in finance and squad summaries

## Frontend scope

### Task 3.5: Contract UI surfaces

- **[goal]**
  - make contracts easy to inspect and act upon

- **[frontend implementation points]**
  - add contract data and actions in:
    - `PlayerProfile`
    - `SquadTab`
    - `FinancesTab`
  - show:
    - years remaining / expiry date
    - current wage
    - contract risk indicator
    - renewal action entry point

- **[likely touchpoints]**
  - `src/components/PlayerProfile.tsx`
  - `src/components/SquadTab.tsx`
  - `src/components/FinancesTab.tsx`
  - store types and backend DTO alignment

- **[tests first]**
  - risk labels render correctly for expiry thresholds
  - renewal modal/form validates input and shows result states
  - i18n coverage for all new labels and messages

### Task 3.6: Renewal workflow UI

- **[goal]**
  - provide a clear manager workflow for making an offer

- **[frontend implementation points]**
  - renewal form/modal with wage and duration fields
  - response states:
    - accepted
    - rejected
    - wants more
  - immediate state refresh and visible impact on payroll/risk

- **[tests first]**
  - valid submission calls backend correctly
  - error and rejection states are displayed clearly
  - payroll projection updates after renewal

## Acceptance criteria for phase 3

- **[real contract loop]**
  - players can be renewed, rejected, or lost through neglect

- **[financial integration]**
  - contract decisions visibly affect wage commitments

- **[system integration]**
  - contract state influences morale and future transfer behavior

---

# 7. Phase 4: Morale and Human Behavior Overhaul

## Phase objective

Replace deterministic morale gains with contextual, personality-driven, and imperfect human responses.

## Player-facing outcomes

- player talks are meaningful but not guaranteed
- the same choice can work for one player and fail for another
- unresolved issues cap easy morale recovery
- trust, context, and personality matter over time

## Backend scope

### Task 4.1: Morale architecture redesign

- **[goal]**
  - separate visible morale from underlying relationship state

- **[backend implementation points]**
  - keep visible morale, but add hidden or semi-hidden state such as:
    - manager trust
    - issue severity
    - recent treatment memory
    - optionally personality traits if not already represented elsewhere
  - do not expose more hidden state to the frontend than necessary
  - make state evolution explainable and testable

- **[likely touchpoints]**
  - player models / state
  - `src-tauri/crates/ofm_core/src/player_events/*`
  - live match morale-affecting flows

- **[tests first]**
  - unresolved issue can cap morale growth
  - trust changes independently from visible morale when appropriate
  - recent-treatment memory affects future interactions

### Task 4.2: Probabilistic response engine

- **[goal]**
  - move from fixed morale outcomes to weighted outcomes

- **[backend implementation points]**
  - introduce a response evaluation service that returns weighted results such as:
    - strong positive
    - mild positive
    - neutral
    - mild negative
    - strong negative
  - weights should depend on:
    - player context
    - personality / profile
    - manager trust
    - issue type
    - recent results and role status
  - randomness must be injectable or seedable for tests

- **[tests first]**
  - deterministic tests prove weight selection using stubbed RNG
  - same talk produces different weighted outcomes based on player context
  - repeated identical talks show diminishing effectiveness

### Task 4.3: Player talks and inbox responses

- **[goal]**
  - apply the new morale engine to direct player interactions

- **[backend implementation points]**
  - update player-event response resolution so actions influence probabilities, not fixed values
  - track promises or assurances if a specific action implies them
  - add cooldowns / spam protection for repeated interventions
  - preserve clear feedback text for the player

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/player_events/`
  - message action resolution flows
  - `src-tauri/src/commands/messages.rs` if adapter changes are needed

- **[tests first]**
  - reassure can help, delay, or backfire depending on context
  - cooldown prevents repeated exploitation
  - broken promise leads to stronger future reactions

### Task 4.4: Team talks and press conferences

- **[goal]**
  - stop universal morale buttons from trivially maxing squad morale

- **[backend implementation points]**
  - update `apply_team_talk` and `submit_press_conference` so outcomes depend on:
    - result context
    - squad personalities
    - trust / leadership / current form
  - group reactions should not be identical across all players
  - leadership or status players may amplify dressing-room effects

- **[likely touchpoints]**
  - `src-tauri/src/commands/live_match.rs`
  - match morale helpers in domain modules

- **[tests first]**
  - same talk produces differentiated player responses
  - repeated or badly timed talks lose effectiveness
  - severe unresolved issues block easy morale inflation

### Task 4.5: Morale caps and recovery pacing

- **[goal]**
  - make morale recovery realistic over time

- **[backend implementation points]**
  - add soft caps based on unresolved issue severity
  - reduce instant large swings except in major events
  - ensure long-term improvement requires root-cause resolution, not constant talking

- **[tests first]**
  - player with unresolved contract issue cannot be trivially pushed to 100 morale
  - long positive run improves morale gradually within expected bounds
  - severe conflict persists until addressed

## Frontend scope

### Task 4.6: Feedback clarity in UI

- **[goal]**
  - help the player understand outcomes without exposing raw hidden math

- **[frontend implementation points]**
  - improve response feedback in inbox, match, and player contexts with messaging such as:
    - encouraged
    - unconvinced
    - frustrated by answer
    - issue partially eased
  - indicate unresolved issue categories and risk levels without revealing internal formulas
  - avoid UI that suggests guaranteed results from action labels

- **[likely touchpoints]**
  - `src/components/InboxTab.tsx`
  - player/event-related frontend i18n resolver paths
  - match talk/press conference components

- **[tests first]**
  - effect feedback remains localized and understandable
  - actions do not promise deterministic outcomes in the UI copy
  - unresolved issue indicators render consistently

## Acceptance criteria for phase 4

- **[no morale exploit]**
  - there is no simple repeatable path to trivial 100 morale across the squad

- **[context matters]**
  - player reactions vary by player, timing, and issue type

- **[communication matters]**
  - the UI explains outcomes without exposing implementation detail noise

---

# 8. Phase 5: Transfer AI and Market Ecosystem

## Phase objective

Make the transfer market active, reactive, and financially meaningful.

## Player-facing outcomes

- clubs bid for user players
- transfer outcomes depend on price, wages, contract situation, and player intent
- loan and sale decisions become strategic
- transfer news contributes to a living football world

## Backend scope

### Task 5.1: Market evaluation model

- **[goal]**
  - replace one-threshold transfer logic with a richer evaluation model

- **[backend implementation points]**
  - factor in:
    - listed vs unlisted status
    - contract length
    - player importance
    - buying club budget
    - selling club willingness
    - player interest and morale
  - keep the first version rule-based and testable rather than over-simulated

- **[likely touchpoints]**
  - `src-tauri/crates/ofm_core/src/transfers.rs`
  - finance modules
  - contract data

- **[tests first]**
  - expiring contract lowers resistance appropriately
  - key player is harder to buy than fringe player
  - low-budget club cannot behave unrealistically

### Task 5.2: AI incoming bids for user players

- **[goal]**
  - make the market move without waiting for user action

- **[backend implementation points]**
  - periodic bid generation based on:
    - player performance
    - market value
    - contract risk
    - club strength / demand
  - generate inbox offers for the user to accept/reject
  - throttle frequency to avoid spam and nonsense offers

- **[tests first]**
  - attractive players receive plausible bids under the right conditions
  - bid generation respects cooldowns and avoids duplicates
  - contract-risk players draw more interest when appropriate

### Task 5.3: Negotiation flow

- **[goal]**
  - allow multi-step transfer decisions without overcomplicating `0.2.0`

- **[backend implementation points]**
  - allow user actions such as:
    - accept
    - reject
    - negotiate higher fee
  - model simple counter behavior from AI clubs
  - extend offer state transitions cleanly
  - keep negotiation logic in domain services, not command handlers

- **[tests first]**
  - counter-offer flow updates offer state correctly
  - rejecting closes the negotiation cleanly
  - accepted offer updates finances and squad state correctly

### Task 5.4: Player willingness and squad consequences

- **[goal]**
  - make transfers about people, not only fees

- **[backend implementation points]**
  - player openness to moving should depend on:
    - morale
    - club ambition mismatch
    - contract situation
    - playing time
    - club reputation if available
  - sold or blocked moves should influence morale and dressing-room effects where appropriate

- **[tests first]**
  - unhappy or ambitious player is more open to moving
  - blocking a move can reduce morale depending on context
  - sale of influential player can affect teammates in some cases

### Task 5.5: Market news and ecosystem visibility

- **[goal]**
  - use transfer activity to reinforce the living world

- **[backend implementation points]**
  - generate headlines for:
    - major moves
    - rumors
    - contract extensions
    - failed bids
  - integrate with phase 1 digest/news where possible

- **[tests first]**
  - major transfer events generate appropriate news once
  - rumor/news frequency is controlled and relevant

## Frontend scope

### Task 5.6: Transfers tab redesign

- **[goal]**
  - support negotiation, incoming bids, and richer market context

- **[frontend implementation points]**
  - reorganize `TransfersTab` into clear sections for:
    - market targets
    - incoming offers
    - negotiations
    - listed players
    - loans
  - surface contract/wage context where relevant
  - clearly distinguish offer state transitions

- **[likely touchpoints]**
  - `src/components/TransfersTab.tsx`
  - inbox/action integrations
  - locale files

- **[tests first]**
  - negotiation actions update UI state correctly
  - incoming offers render with correct actions
  - accepted sales/purchases update budgets and lists consistently

## Acceptance criteria for phase 5

- **[market activity]**
  - the user receives plausible incoming bids

- **[negotiation depth]**
  - transfer decisions are more than one-click accept/reject

- **[world immersion]**
  - transfer activity contributes to league/news atmosphere

---

# 9. Phase 6: Hardening, Balancing, Migration, and UX Polish

## Phase objective

Ensure the release is stable, understandable, balanced, and maintainable.

## Cross-cutting tasks

### Task 6.1: Save migration and persistence hardening

- **[goal]**
  - preserve compatibility with existing saves where possible

- **[backend implementation points]**
  - add migration coverage for:
    - sponsorship state
    - facility levels
    - contract metadata additions
    - morale hidden-state additions
    - transfer negotiation state additions
  - define safe defaults for legacy saves

- **[tests first]**
  - old save loads without panic
  - missing fields default correctly
  - new fields round-trip correctly

### Task 6.2: Balance tuning pass

- **[goal]**
  - ensure systems feel fair and readable

- **[implementation points]**
  - tune payout tables, sponsor values, facility costs, morale caps, and offer frequency
  - prefer centralized constants/configuration over scattered magic numbers
  - only rebalance after behavior is covered by tests

### Task 6.3: UX and explanation pass

- **[goal]**
  - ensure players can understand why outcomes happen

- **[frontend implementation points]**
  - improve microcopy and state explanations for:
    - rejected renewals
    - sponsor objectives
    - facility effects
    - morale responses
    - transfer negotiations
  - keep user-facing phrasing localized and consistent

### Task 6.4: Coverage and regression audit

- **[goal]**
  - protect the release from regressions

- **[implementation points]**
  - add targeted tests for:
    - Tauri command adapters that expose new features
    - high-risk frontend flows
    - edge cases in finance, morale, and transfer logic
  - ensure key orchestration flows are covered, not only pure helpers

## Acceptance criteria for phase 6

- **[stability]**
  - legacy and new saves behave safely

- **[clarity]**
  - the player can understand new systems without hidden confusion

- **[maintainability]**
  - extracted modules remain small and purpose-driven

---

# 10. Suggested Task Order Inside Each Phase

Each individual task should be split into small TDD-friendly slices.

## Example slice pattern

- **[slice 1]**
  - add one failing domain test for a single business rule

- **[slice 2]**
  - implement the minimum domain logic to satisfy that rule

- **[slice 3]**
  - add persistence test only if new state exists

- **[slice 4]**
  - add thin adapter/command test if command contract changed

- **[slice 5]**
  - add frontend rendering/interaction test for the exposed behavior

- **[slice 6]**
  - refactor safely once all tests are green

## Explicit rule for the implementation agent

The implementation agent must **not** do the following:

- **[no giant feature branches in one jump]**
  - do not implement an entire phase before getting feedback from tests and the current codebase shape

- **[no adapter-led design]**
  - do not start from the Tauri command or React UI and push logic downward afterward

- **[no untested randomness]**
  - do not rely on uncontrolled RNG in morale or transfer behavior

- **[no speculative abstractions]**
  - do not create a generic system for every possible future competition or sponsor category if only a few are required now

---

# 11. Proposed Test Inventory by Area

## Backend domain tests

- **[finance tests]**
  - payouts
  - sponsorship income
  - facility modifiers
  - warning thresholds

- **[contract tests]**
  - renewal acceptance/rejection
  - expiry behavior
  - wage expectation rules

- **[morale tests]**
  - probabilistic weighted outcomes with deterministic RNG
  - trust changes
  - morale caps
  - repeated-action diminishing returns

- **[transfer tests]**
  - AI bid generation
  - negotiation state transitions
  - willingness logic

- **[living-world tests]**
  - round-up generation
  - storyline selection
  - digest cadence

## Persistence and migration tests

- **[db tests]**
  - new fields serialize and deserialize correctly
  - old save compatibility defaults
  - no data loss for contract and finance state

## Frontend tests

- **[match flow tests]**
  - post-match round-up rendering and navigation

- **[finance flow tests]**
  - sponsor selection, facility upgrade states, insufficient funds handling

- **[contract flow tests]**
  - renewal form, risk indicators, payroll update

- **[morale feedback tests]**
  - localized feedback messaging, unresolved issue indicators

- **[transfer flow tests]**
  - offer lists, negotiation actions, updated market state

---

# 12. Suggested Module Boundaries

These are suggested boundaries, not mandatory file names.

## Backend suggestions

- **[finance modules]**
  - separate payout, sponsorship, investment, and warning responsibilities when needed

- **[contract modules]**
  - isolate contract evaluation and renewal decision logic from UI/adapters

- **[morale modules]**
  - isolate response weighting, trust updates, and issue severity tracking

- **[market modules]**
  - isolate offer evaluation, AI bid generation, and negotiation state transitions

- **[world summary modules]**
  - isolate round-up and storyline generation from rendering concerns

## Frontend suggestions

- **[hooks]**
  - extract orchestration-heavy flows into hooks where appropriate

- **[presentational components]**
  - keep display panels for finances, contracts, and round-up separate from orchestration logic

- **[typed DTO mappers]**
  - keep backend payload interpretation explicit and testable

---

# 13. Release Exit Checklist

The release should not be considered complete unless all items below are satisfied.

- **[living world]**
  - matchdays show broader round context
  - weekly/storyline content exists and feels relevant

- **[finance]**
  - prize pools and sponsorships are live
  - facility investments affect gameplay meaningfully

- **[contracts]**
  - renewal flow exists
  - expiry pressure and free-loss risk are real

- **[morale]**
  - morale is no longer trivially maxed through repeatable actions
  - player reactions vary by context

- **[transfers]**
  - AI clubs can bid for user players
  - negotiation exists at a meaningful but controlled depth

- **[quality]**
  - tests were written first for each implemented behavior
  - migrations are covered
  - new UI is localized
  - domain logic remains decoupled from adapter and UI layers

---

# 14. Recommended Initial Execution Order

If work begins immediately, start with this sequence:

1. **[phase 1 task 1.1 and 1.2]**
   - round-up domain model and post-match payload
2. **[phase 1 task 1.4]**
   - post-match round-up UI
3. **[phase 2 task 2.1 and 2.2]**
   - finance extraction and prize pools
4. **[phase 2 task 2.3 and 2.4]**
   - sponsorships and facilities
5. **[phase 3 task 3.1 to 3.3]**
   - contract rules and renewal flow
6. **[phase 4 task 4.1 to 4.5]**
   - morale architecture and probabilistic interactions
7. **[phase 5 task 5.1 to 5.4]**
   - transfer AI and negotiation
8. **[phase 6]**
   - balancing, migration hardening, and polish

This order maximizes visible progress early while still building on sound domain foundations.

---

# 15. Final Instruction to the Implementation Agent

The implementation agent must treat this roadmap as a **behavior-first engineering plan**, not a loose ideas list.

For every task in this document:

- **[write a failing test first]**
- **[implement the smallest passing change]**
- **[refactor only after green]**
- **[keep business logic in the domain layer]**
- **[keep adapter and UI layers thin]**
- **[preserve i18n and persistence integrity]**
- **[prefer simple, explicit, testable code]**

The release should favor depth, clarity, and system interaction over raw feature count.
