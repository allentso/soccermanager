# Refactor Execution Backlog

This backlog turns the architecture audit into an execution plan. Each step is intended to be atomic, behavior-preserving, and committed independently.

## Principles

- Preserve behavior with focused regression coverage before and after each extraction.
- Prefer thin UI containers and thin Tauri command adapters.
- Extract pure logic before introducing new abstractions.
- Keep commits atomic and Conventional Commits compliant.

## Phase 1: Frontend Transport Boundary

- [x] Step 1.1: Extract `useAdvanceTime` transport calls into a frontend service.
- [x] Step 1.2: Extract `StaffTab` hire/release transport calls into a frontend service.
- [x] Step 1.3: Extract `TrainingTab` training/schedule/group transport calls into a frontend service.
- [x] Step 1.4: Extract `ScoutingTab` scout dispatch transport call into a frontend service.
- [x] Step 1.5: Extract `InboxTab` message action transport calls into a frontend service.
- [x] Step 1.6: Extract `TransfersTab` transport calls into a frontend service.

## Phase 2: Frontend Feature Decomposition

- [x] Step 2.1: Extract `TransfersTab` pure negotiation helpers into a dedicated module.
- [x] Step 2.2: Extract `TransfersTab` list derivation and filtering into query/model helpers.
- [x] Step 2.3: Extract `TransfersTab` bid negotiation action panel.
- [x] Step 2.4: Extract `TransfersTab` counter-offer action panel and finish the container split.
- [x] Step 2.5: Extract `TrainingTab` staff advice decision logic into a dedicated helper.
- [x] Step 2.6: Extract `TrainingTab` training-group mapping and sorting into model helpers.
- [x] Step 2.7: Extract `TrainingTab` training-groups card into a dedicated module.
- [x] Step 2.8: Finish `TrainingTab` container split with schedule/focus panels.
- [x] Step 2.9: Extract `ScoutingTab` scout capacity and availability helpers.
- [x] Step 2.10: Extract `ScoutingTab` player filtering, sorting, and pagination into model helpers.
- [x] Step 2.11: Extract `ScoutingTab` scout overview cards into a dedicated component.
- [x] Step 2.12: Extract `ScoutingTab` active assignments list into a dedicated component.
- [x] Step 2.13: Extract `ScoutingTab` scout details card into a dedicated component.
- [x] Step 2.14: Extract `ScoutingTab` player search module into a dedicated component.
- [x] Step 2.15: Extract `HomeTab` onboarding checklist card into a dedicated component.
- [x] Step 2.16: Extract `HomeTab` next-opponent and league-digest widgets into dedicated components.
- [x] Step 2.17: Extract `HomeTab` season-status and league-position widgets into dedicated components.
- [x] Step 2.18: Extract `HomeTab` squad availability and squad overview widgets into dedicated components.
- [x] Step 2.19: Extract `HomeTab` recent results and latest news widgets into dedicated components.
- [x] Step 2.20: Extract `HomeTab` player momentum and inbox summary widgets to finish the container split.
- [ ] Step 2.21: Refactor `TeamProfile` to reuse shared helper logic and remove duplicated formatting/domain calculations.

## Phase 3: Backend Command Boundary

- [ ] Step 3.1: Extract `advance_time_with_mode` orchestration from `src-tauri/src/commands/time.rs` into application services.
- [ ] Step 3.2: Extract blocker evaluation and lineup preflight from `src-tauri/src/commands/time.rs`.
- [ ] Step 3.3: Extract live match orchestration from `src-tauri/src/commands/live_match.rs`.
- [ ] Step 3.4: Extract team-talk response modelling from `src-tauri/src/commands/live_match.rs`.

## Phase 4: Backend Persistence And Contracts

- [ ] Step 4.1: Split `SaveManager` into index management and persistence orchestration.
- [ ] Step 4.2: Split `SaveManager` DB read/write responsibilities into dedicated collaborators.
- [ ] Step 4.3: Split contract wage-policy and financial projection logic from renewal negotiation logic.
- [ ] Step 4.4: Split delegated renewal/report generation from contract negotiation flow.

## Phase 5: Verification Sweep

- [ ] Step 5.1: Run broader frontend regression slices around dashboard/navigation flows.
- [ ] Step 5.2: Run broader backend Rust test slices for refactored command and domain modules.
- [ ] Step 5.3: Review remaining hotspots and close residual SOLID violations that still materially affect change risk.
