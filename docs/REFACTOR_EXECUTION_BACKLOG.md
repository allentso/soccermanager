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
- [ ] Step 2.5: Split `TrainingTab` into container, schedule/focus panels, and training-group module.
- [ ] Step 2.6: Split `ScoutingTab` into container, scout overview, assignment list, and player search modules.
- [ ] Step 2.7: Split `HomeTab` into smaller dashboard widgets and view-model helpers.
- [ ] Step 2.8: Refactor `TeamProfile` to reuse shared helper logic and remove duplicated formatting/domain calculations.

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
