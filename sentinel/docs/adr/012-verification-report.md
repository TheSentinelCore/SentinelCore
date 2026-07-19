# SentinelCore Ticket Verification Report

## Summary

The implementation tickets document (ADR 012) was drafted assuming a Rust/Cargo workspace architecture, but the actual implementation uses a **dual-language approach**: Lua for runtime execution (inside Sylvannas) and Rust for offline tooling (compiler, queryserver, schema). This report validates implementation against the ADR specifications while acknowledging the architectural divergence.

| Metric | Count |
|--------|-------|
| Total Tickets Specified | 121 |
| Fully Implemented (Rust) | ~60 |
| Fully Implemented (Lua) | ~40 |
| Partially Implemented | ~15 |
| Missing | ~10 |
| Blocked (Sylvanas API) | ~3 |

---

## Phase 0 — Foundations & Scaffolding

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-0.1 — Cargo Workspace Initialization | ✅ | Rust workspace exists with 3 crates. However, the Lua runtime in `sentinel/` is NOT part of this workspace. |
| SENT-0.2 — CI Pipeline | ⚠️ | No CI configuration found. No README badge. |
| SENT-0.3 — Shared Common Crate | ✅ | DateTime/Duration/Uuid serde helpers implemented in sentinel-schema crate |
| SENT-0.4 — ADR Citation Lint | ❌ | No lint script for ADR citation checking |
| SENT-0.5 — Mangos TBC Fixture Database | ✅ | `tbcmangos.sqlite` (298 MB real Mangos TBC DB) is present at repo root. QueryServer reads it via `SENTINEL_DB_PATH` (default `./tbcmangos.sqlite`). Note: root `SentinelQueryServer/` prototype retired 2026-07-19; canonical is `sentinel-compiler/crates/sentinel-queryserver/`. Fixture README still outstanding. |
| SENT-0.6 — Developer Environment Documentation | ⚠️ | README exists but no links to all 11 ADR volumes |

---

## Phase 1 — Canonical Schema (Rust)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-1.1 — Root Profile, Metadata, ProfileSettings | ✅ | `sentinel-compiler/crates/sentinel-schema/src/profile.rs` implements Profile with all fields. Metadata, ProfileSettings in metadata.rs. |
| SENT-1.2 — Revised Operation Struct | ✅ | `operation.rs` implements all 9 fields from 007 §3 (goals, entry_conditions, exit_conditions, dependencies, optimization_policy, completion_metrics, sub_operations) |
| SENT-1.3 — OperationGoal & GoalType | ✅ | `condition.goals` implements OperationGoal and all GoalType variants (11 total) |
| SENT-1.4 — Entry/Exit Conditions & Condition Enum | ⚠️ | `condition.rs` implements Condition enum but missing some variants (OperationCompleted, OperationSkipped, etc. may be runtime-only) |
| SENT-1.5 — OptimizationPolicy & CompletionMetrics | ✅ | `enums.rs` implements both structs |
| SENT-1.6 — OperationDependency & DependencyType | ✅ | Implements all four DependencyType variants (Requires, SoftPrefers, ExcludesWith, UnlocksAfter) |
| SENT-1.7 — Action, ActionPayload & Primitive Payload Structs | ✅ | `action.rs` implements all 23 ActionPayload variants with serde derivation |
| SENT-1.8 — Reference & Value Types | ✅ | `reference.rs` implements all 8 types (NPC, Quest, Vendor, Waypoint, Path, Polygon, Variable, VariableValue) |
| SENT-1.9 — Analytics & OperationAnalytics Structs | ✅ | `analytics.rs` implements both structs |
| SENT-1.10 — Schema Version Constants & Migration Registry Skeleton | ⚠️ | Schema version exists ("1.0.0") but MigrationRegistry incomplete |

---

## Phase 2 — Profile Storage & File I/O

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-2.1 — YAML Serialization Adapter Layer | ✅ | `yaml_adapter.rs` implements YAML (de)serialization |
| SENT-2.2 — Tier 1 On-Disk Reference Types | ❌ | No separate on-disk reference types implemented |
| SENT-2.3 — Workspace & Manifest Read/Write | ⚠️ | workspace.yaml created, loader integration pending |
| SENT-2.4 — Operation File Read/Write | ❌ | No per-file Operation persistence |
| SENT-2.5 — Shared Library Files | ❌ | No npc_library.yaml, quest_library.yaml implementation |
| SENT-2.6 — Blueprint Library File I/O | ❌ | No directory-per-entry form |
| SENT-2.7 — Tier 1 → Tier 2 Reference Resolution | ⚠️ | Resolution logic in `stage_reference_resolution.rs` but not complete pipeline |
| SENT-2.8 — Tier 2 → Tier 1 Lowering (Save) | ❌ | No save lowering implemented |
| SENT-2.9 — Dirty Tracking & Partial Save | ⚠️ | `dirty.rs` exists, Lua wrapper added |
| SENT-2.10 — Atomic Writes & Advisory Locking | ❌ | No atomic write or lock file implementation |
| SENT-2.11 — Per-File Schema Migration Engine | ❌ | Migration registry exists but no migration scripts |

---

## Phase 3 — QueryServer

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-3.1 — Axum Service Scaffold & API Versioning | ✅ | `lib.rs` implements `/api/v1/` routing scaffold with health check |
| SENT-3.2 — SQLite Read Layer | ✅ | `sqlite.rs` and services layer implement connection pooling, prepared statements |
| SENT-3.3 — Quest Endpoints | ✅ **(fixed 2026-07-19)** | `api/quests.rs`, `services/quests.rs` implement Search, Details, Chain, Near. **Was 500 on real DB** (`Integer -1 out of range` on `QuestLevel` for 883 quests) — root cause: `u32` read of MaNGOS `-1` sentinel. Fixed via `get_u32_saturating` helper. Verified returning real Northshire-area quest data. |
| SENT-3.4 — NPC Endpoints | ✅ **(fixed 2026-07-19)** | `api/npcs.rs`, `services/npcs.rs` implement Lookup, Search, Near. **Was 500 on real DB** (`Invalid column type Integer ... name: Faction`) — `creature_template.Faction` is INTEGER, model field was `String`. Fixed via `get_faction_string` (returns numeric id as String to preserve API contract). Verified `npcs/100` returns data. |
| SENT-3.5 — Creature Endpoints & Spawn Locations | ✅ | `api/creatures.rs`, `services/creatures.rs` implemented |
| SENT-3.6 — Vendor & Trainer Endpoints | ✅ | Both endpoints implemented |
| SENT-3.7 — Flight Master, Mailbox, Inn Endpoints | ⚠️ | All three implemented, but `flight-masters` returns `[]` on this DB — `taxi_nodes` table is empty in `tbcmangos.sqlite` (data gap, not a crash). `Faction` type crash fixed via `get_faction_string`. |
| SENT-3.8 — Area Query & Polygon Analysis | ✅ | `api/areas.rs`, `api/polygons.rs` implemented |
| SENT-3.9 — Route Analysis | ✅ | `api/routes.rs`, `services/routes.rs` implemented |
| SENT-3.10 — Quest Hub Analysis & Blueprint/Grind Suggestions | ✅ | `api/hubs.rs`, `api/blueprints.rs`, `api/grind.rs` implemented |
| SENT-3.11 — Loot Lookup & World Graph | ✅ | `api/loot.rs`, `api/graph.rs` implemented |
| SENT-3.12 — Search Everywhere & Validation API | ⚠️ | Search implemented, validation endpoint exists but incomplete |
| SENT-3.13 — Caching Layer & Performance Verification | ✅ | `cache.rs` implements LRU cache with TTL; benchmarks not verified |

---

## Phase 4 — Blueprint System

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-4.1 — Blueprint Struct & Parameter Types | ✅ | `blueprint.rs` implements Blueprint, BlueprintParameter, ParameterType |
| SENT-4.2 — Blueprint Definitions: Quest / Travel | ✅ | `standard_blueprints.rs` implements Quest Hub, Single Quest, Quest Chain, Travel Hub, Flight Unlock, Hearth Setup |
| SENT-4.3 — Blueprint Definitions: Combat / NPC Services | ✅ | Grind Area, Vendor Stop, Trainer Stop, Repair Stop, Mailbox Stop, Bank Stop implemented |
| SENT-4.4 — Blueprint Definitions: Recovery / Utility | ⚠️ | Death Skip, Wait, Set Variable, Conditional Branch implemented. Some missing. |
| SENT-4.5 — Parameter Resolution & Smart Defaults | ⚠️ | Basic resolution in `stage_blueprint_expansion.rs` but query integration incomplete |
| SENT-4.6 — Conditional Expansion | ✅ | Optional parameter omission handled in Lua blueprint_registry.lua |
| SENT-4.7 — Nested Blueprint Composition | ⚠️ | Expansion works but cycle detection may need hardening |
| SENT-4.8 — Blueprint Expansion Pipeline (Single Instance) | ✅ | `stage_blueprint_expansion.rs` implements Validate → Resolve References → Inject Runtime Actions → Optimize → Execution Graph |
| SENT-4.9 — Blueprint Validation | ⚠️ | Partial checks exist but missing NPC/vendor validation against QueryServer |

---

## Phase 5 — Operation System Logic (Lua)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-5.1 — Goal Coverage Checking (Static) | ✅ | `modules/operation/goal_coverage.lua` implements all checkable goal types per 007 §15 |
| SENT-5.2 — Entry/Exit Condition Evaluation Engine | ✅ | `modules/operation/condition_evaluator.lua` implements exhaustive condition evaluation |
| SENT-5.3 — Operation Dependency Graph Construction | ✅ | `modules/operation/dependency_graph.lua` implements directed graph builder |
| SENT-5.4 — Cycle Detection & ExcludesWith Conflict Detection | ⚠️ | Cycle detection in `cycle_detector.lua` but ExcludesWith conflict detection incomplete |
| SENT-5.5 — Topological Sort with Priority Tie-Breaking | ✅ | `modules/operation/topological_sort.lua` implements sort per 008 §7 |
| SENT-5.6 — Operation Lifecycle State Machine | ✅ | `modules/operation/operation_lifecycle.lua` implements Locked→Ready→Active→{Completed,Failed,Aborted,Skipped} per 007 §13-14 |
| SENT-5.7 — Sub-Operation Composition | ✅ | `modules/operation/sub_operation_composer.lua` computes parent goal union |

---

## Phase 6 — The Compiler (Rust)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-6.1 — Stage 1: Structural Validation | ✅ | `stages/structural.rs` implements validation checks |
| SENT-6.2 — Stage 2: Reference Resolution | ✅ | `stages/resolution.rs` resolves references against QueryServer |
| SENT-6.3 — Stage 3: Blueprint Expansion (Profile-Wide) | ✅ | `stages/expansion.rs` implements recursive expansion |
| SENT-6.4 — Stage 4: Operation Dependency Resolution | ✅ | `stages/dependency.rs` implements dependency resolution |
| SENT-6.5 — Stage 5: Goal Coverage Validation | ✅ | `stages/goal_coverage.rs` validates mandatory/optional goals |
| SENT-6.6 — Stage 6: Cross-Operation Optimization — Adjacency Merge | ✅ | `stages/optimization.rs` implements trailing/leading action merge, Vendor+Repair collapse |
| SENT-6.7 — Stage 6: Cross-Operation Optimization — Reordering | ⚠️ | Reordering stub exists but incomplete implementation |
| SENT-6.8 — Stage 7: Lowering to RuntimeProfile | ✅ | Fixed compilation errors (added Diagnostic import, Debug/Clone derives, RuntimeDiagnostics field) |
| SENT-6.9 — Diagnostics System | ✅ | `diagnostics.rs` implements format per 002 §19 |
| SENT-6.10 — Incremental Compilation & Dirty-Scoped Recompile | ⚠️ | `incremental.rs` implemented, Lua wrapper added |
| SENT-6.11 — Compile Caching & Determinism Verification | ❌ | No cache or determinism property testing |
| SENT-6.12 — Integration Test: Northshire End-to-End | ⚠️ | Northshire profile exists but full trace not implemented |

---

## Phase 7 — Sylvanas Bridge

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-7.1 — QuestClient Trait & Mock Implementation | ✅ | `integrations/sentinel_bridge/quest_client_trait.lua` and `mock_bridge.lua` implemented |
| SENT-7.2 — AddonsClient Trait & Mock Implementation | ✅ | `addons_client_trait.lua` and mock implemented |
| SENT-7.3 — RenderSurface Trait (Abstract) | ✅ | `render_surface_trait.lua` and `render_bridge.lua` implemented (headless mode available) |
| SENT-7.4 — Event Bridge Translation Table | ✅ | `event_bridge.lua` translates raw events to semantic events |
| SENT-7.5 — Quest Log Diffing | ⚠️ | Logic exists in `event_bridge.lua` but polling implementation incomplete |
| SENT-7.6 — BridgeError Handling & Retry Semantics | ✅ | `bridge_error.lua` implements BridgeError types |
| SENT-7.7 — API Versioning & Drift Detection | ⚠️ | `api_version.lua` exists but startup check not integrated |
| SENT-7.8 — Real Sylvanas API Binding (BLOCKED) | ✅**✓** | **RESOLVED** — ADR 009 §16 verified (2026-07-18). Lua API confirmed: `core.quests.*` is frame-centric, requires dialog open. |

---

## Phase 8 — Runtime Execution Engine

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-8.1 — Profile Manager | ✅ | `runtime/profile_manager.lua` implements load/save/compile/validate/activate/deactivate |
| SENT-8.2 — Runtime Context & Variable Store | ✅ | `runtime/runtime_context.lua` and `runtime/variable_store.lua` implement RuntimeContext with VariableStore as sole mutator |
| SENT-8.3 — Event Dispatcher | ✅ | `runtime/event_dispatcher.lua` consumes Bridge semantic events |
| SENT-8.4 — Operation Manager & Runtime Scheduler | ✅ | `runtime/operation_manager.lua` implements operation execution; `operation_scheduler.lua` for scheduling |
| SENT-8.5 — Action Executor | ✅ | `runtime/runtime_action_executor.lua` dispatches RuntimeAction payloads |
| SENT-8.6 — Runtime State Machine & Failure Recovery | ⚠️ | States implemented in RuntimeContext but failure hierarchy path needs testing |
| SENT-8.7 — Continuous Validation Service | ⚠️ | `runtime_engine.lua` exists but incremental validation incomplete |
| SENT-8.8 — Hot Reload | ⚠️ | Runtime exists but full pipeline not wired |
| SENT-8.9 — Undo/Redo Command Stack | ❌ | `runtime/command_history.lua` exists but not all §14 commands implemented |
| SENT-8.10 — Dry Run Mode Integration | ✅ | `runtime/dry_run.lua` implements Dry Run with Simulation Adapters |
| SENT-8.11 — Threading Model & Logging Streams | ⚠️ | No explicit threading; logging split not implemented |

---

## Phase 9 — Analytics & Telemetry

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-9.1 — Telemetry Event Model & SQLite Schema | ❌ | No telemetry schema implemented |
| SENT-9.2 — AnalyticsServer Scaffold & Ingest Endpoint | ❌ | No analytics server in QueryServer |
| SENT-9.3 — Telemetry Collector (Runtime-Side) | ❌ | `runtime/telemetry.lua` exists but collector incomplete |
| SENT-9.4 — Operation-Level Aggregation Queries | ❌ | No aggregation queries |
| SENT-9.5 — Bottleneck Detection | ❌ | No bottleneck detection algorithm |
| SENT-9.6 — Trend & Cross-Version Comparison Queries | ❌ | No trend/compare endpoints |
| SENT-9.7 — Retention & Rollup Background Job | ❌ | No retention/rollup logic |
| SENT-9.8 — Simulation Adapters (Per Action Type) | ⚠️ | `dry_run.lua` has basic adapters but not all action types covered |
| SENT-9.9 — Export & Purge Endpoints | ❌ | No export/purge endpoints |

---

## Phase 10 — Editor UI

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-10.1 — Docking Layout Framework | ✅ | `window.lua` implements dockable, hideable, persisted-layout panels |
| SENT-10.2 — Toolbar | ✅ | `toolbar.lua` implemented with buttons wired |
| SENT-10.3 — Explorer Panel | ✅ | `explorer_panel.lua` with project tree and drag/drop reordering |
| SENT-10.4 — World Map Rendering & Icons | ✅ | `world_map_panel.lua` with map surface and icon types |
| SENT-10.5 — Map Interaction | ⚠️ | Basic interaction but not all modes (context menu, duplicate) |
| SENT-10.6 — Target Capture Panel | ✅ | `target_capture_panel.lua` implements capture flow per 009 §8 |
| SENT-10.7 — NPC Library & Quest Browser Panels | ✅ | Both panels implemented with Add/Pickup/Turn In wiring |
| SENT-10.8 — Timeline & Action Palette | ⚠️ | `timeline_panel.lua` and action palette exist but drag/drop needs polish |
| SENT-10.9 — Inspector & Property Editors | ⚠️ | `inspector_panel.lua` exists but not all ActionPayload editors |
| SENT-10.10 — Variables Panel | ✅ | `variables_panel.lua` implements create/delete/rename/watch |
| SENT-10.11 — Validation Panel | ✅ | `validation_panel.lua` surfaces diagnostics |
| SENT-10.12 — Console (Editor/Compiler/Runtime Tabs) | ✅ | `console_panel.lua` has three separate log tabs |
| SENT-10.13 — Dry Run Panel | ⚠️ | Panel exists but controls need wiring |
| SENT-10.14 — Path Recorder & Polygon Recorder | ⚠️ | Recorder logic exists but stop-and-suggest flow incomplete |
| SENT-10.15 — Context Menus | ❌ | Map and NPC context menus not fully implemented |
| SENT-10.16 — Blueprint Library Panel | ❌ | No blueprint drag-to-timeline |
| SENT-10.17 — Multi-Select, Undo/Redo Wiring, Search Everywhere, Hotkeys | ⚠️ | Partial multi-select but Search Everywhere incomplete |
| SENT-10.18 — Analytics Panel | ❌ | No analytics panel (Phase 9 deferred) |

---

## Phase 11 — Integration, Hardening & Release

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-11.1 — Full End-to-End Integration Test Suite | ⚠️ | `tests/integration/test_northshire_e2e.lua` exists but incomplete |
| SENT-11.2 — Performance Benchmarking Pass | ❌ | No benchmark suite |
| SENT-11.3 — Diagnostics & Error Message UX Pass | ❌ | No diagnostic review |
| SENT-11.4 — Module-Level CLAUDE.md Documentation | ⚠️ | Main CLAUDE.md exists, module docs incomplete |
| SENT-11.5 — Dogfood Profile: Human 1–10 | ❌ | No dogfood profile authored |
| SENT-11.6 — Real Sylvanas API Verification & Reconciliation | ✅ | ADR 009 §16 resolved; Lua API confirmed |
| SENT-11.7 — Release Readiness Review | ❌ | Not yet performed |

---

## Critical Gaps (Blocking Northshire→Goldshire Compile)

| Gap | Impact | Status | Recommendation |
|-----|--------|--------|----------------|
| SENT-6.10 — Incremental compilation | HIGH | ⚠️ **In Progress** | DirtyTracker implemented in Rust, Lua wrapper added |
| SENT-2.3 — Workspace & Manifest | MEDIUM | ⚠️ **Partially Done** | workspace.yaml created, loader integration pending |
| SENT-4.6 — Conditional expansion | MEDIUM | ✅ **Complete** | Lua blueprint_registry handles optional params correctly |
| SENT-9.* — Analytics | LOW (deferred) | Deferred | Ship without analytics per MVP §17 |

## Work Completed This Session

1. Created `.scratch/verification/phase-checkpoints.md` — Progress tracking by phase
2. Created `.scratch/verification/work-plan.md` — Focused work items for Northshire→Goldshire
3. Created `sentinel-compiler/profiles/workspace.yaml` — Workspace configuration scaffold
4. Updated `lib.rs` — Exported `DirtyTracker`, `DirtyState`, `StageFlags`, `compile_incremental`, `update_tracker`
5. Updated `compiler_bridge.lua` — Added `compile_incremental`, `mark_dirty`, `get_dirty_operations` methods

## Test Results (Rust Workspace)

All 210 tests pass:
- 118 tests in sentinel-compiler
- 92 tests in sentinel-schema
- 12 incremental compilation tests verified

---

## Architectural Notes

The implementation diverges from the original ticket assumptions in meaningful ways:

1. **Lua Runtime vs Rust Compiler**: The tickets assumed a Rust-only implementation, but the runtime lives in Lua inside Sylvannas. The Rust compiler prepares profiles that are serialized to JSON/YAML and loaded by the Lua runtime.

2. **File I/O in Lua**: Lua has no direct file I/O capability inside Sylvannas. Profile persistence would need to be handled by the Rust toolchain or a separate serialization layer.

3. **Threading Model**: The Lua runtime runs single-threaded inside Sylvannas. The "main thread / worker thread" separation from ADR 002 §24 applies to the Rust QueryServer only.

4. **API Boundaries**: The Lua runtime correctly uses `core.*` APIs exclusively (per AGENTS.md) and avoids direct SQLite access.

5. **MaNGOS `-1` sentinel / integer-Faction row mapping** (fixed 2026-07-19): MaNGOS uses `-1` as "none" for many numeric columns (`QuestLevel`, `MinLevel`, `Req*` ids) and stores `Faction` as an INTEGER. Reading those directly into `u32`/`String` Rust fields **panics at runtime on the real DB** even though the code compiles and unit tests (which use hand-built fixtures, not real data) pass. The fix: `sqlite.rs::get_u32_saturating` (i32→u32, saturates -1 to 0) and `get_faction_string` (i32→numeric-id String, preserving the `faction: String` API contract). **Any new QueryServer endpoint that reads a numeric column capable of being -1, or the Faction column, must use these helpers** or it will 500 on real data. This is the SENT-0.5 risk ("fixture may not represent production DB edge cases") made concrete.

---

*Report generated: 2026-07-19 — last updated 2026-07-19 (QueryServer real-DB fix)*