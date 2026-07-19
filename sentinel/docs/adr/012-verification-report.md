# SentinelCore Ticket Verification Report

## Architecture of Record (2026-07-19, corrected)

The implementation tickets (ADR 012) and the ADRs they cite assume a **Rust/Cargo
workspace** (ten crates) implementing every subsystem. The actual repository
diverges by a deliberate, now-ratified decision:

> **Lua owns all botting logic. Rust owns only the QueryServer (the database-backed
> query layer over the Mangos DB).**

This was ratified by the project owner on 2026-07-19. Consequences:

- **Lua (`sentinel/runtime/`, `sentinel/modules/`, `sentinel/integrations/`) is the
  canonical runtime and compiler.** It implements Phases 2, 4, 5, 6, 7, 8, 10
  (engine + Sylvanas bridge + editor behavior). The offline test harness
  (`luajit tests/run_offline.lua`) is the measure of done for these phases.
- **Rust (`sentinel-compiler/crates/`) is SECONDARY / offline tooling.** Only
  `sentinel-queryserver` is canonical (Phase 3). `sentinel-schema` and
  `sentinel-compiler` exist as an earlier Rust implementation of the schema and
  compiler but are **NOT the runtime** and are demoted — kept for reference/offline
  tooling, not counted as the spec deliverable. Do not add new runtime logic to them.
- **Storage format divergence (approved):** ADR 011 specifies YAML +
  `workspace.yaml`/`profile.yaml` + `npc_library/quest_library/vendor_library.yaml` +
  Tier1→Tier2 load-time resolution. The Lua implementation uses **JSON on disk**
  (`manifest` + `ops/<id>.json`) and a compiler-side Tier1/Tier2 (resolved at compile
  time, not load time). This is a deliberate divergence approved under the Lua-truth
  ruling: the *shape* ADR 011 cares about (one file per Operation, Tier1→Tier2
  resolution, atomic writes, dirty-tracked partial saves, per-file schema migration)
  is honored; the on-disk serialization format is JSON, not YAML. No rewrite planned.

### Measure of done under this architecture

- Lua phases: green in `luajit tests/run_offline.lua`.
- Rust QueryServer: `cargo test -p sentinel-queryserver` + live-DB endpoint checks.
- Phase 9 (Analytics): **deferred by MVP §17**, not blocked.

---

## Summary

| Metric | Count |
|--------|-------|
| Total Tickets Specified | 121 |
| Canonical (Lua) — Implemented | ~70 |
| Canonical (Lua) — Partial | ~14 |
| Rust QueryServer — Implemented | 13 (Phase 3) |
| Deferred (MVP §17, Phase 9) | 9 |
| Blocked (none remain; SENT-7.8/11.6 RESOLVED) | 0 |
| Rust secondary crates (demoted, not counted) | schema + compiler |

### Engine-correctness completion status (2026-07-19)

`luajit tests/run_offline.lua` runs **41 passing tests / 2 failing** (actual,
verified this session).

The 2 failures are explicit **MVP §17 deferrals**, not regressions:

- `tests/runtime/test_telemetry.run` — Phase 9 (Analytics) deferred to MVP §17.
- `tests/modules/combat/test_target_selector.run` — target selector reordering
  deferred to MVP §17.

Completed this session (genuinely-completable engine correctness):

- **SENT-6.11** — lowering cache keyed by recursive content hash; `lib/JSON`
  non-string-key drop bug sidestepped; per-compile `clear_cache()` stopgap removed.
- **SENT-6.7** — `RouteAnalysis:reorder_actions` nearest-neighbor greedy implemented
  with quest/goal-critical guards; fixed `compute_total_travel` positionless-action
  chain-break bug.
- **Phase 2 storage** — `runtime/storage_manager.lua`: per-operation file storage,
  atomic writes, Tier1↔Tier2 resolution, migration-on-load. `MigrationRegistry`
  `0.0.0→1.0.0` now advances `schema_version` to `1.0.0`.

---

## Phase 0 — Foundations & Scaffolding

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-0.1 — Cargo Workspace Initialization | ⚠️ Demoted | Rust workspace has 3 crates (schema, queryserver, compiler), not the 10 the ticket lists. Under Lua-truth the 10-crate split is obsolete; Lua runtime is the deliverable. |
| SENT-0.2 — CI Pipeline | ⚠️ | No CI configuration found. |
| SENT-0.3 — Shared Common Crate | ⚠️ Demoted | DateTime/Duration/Uuid helpers live in Rust `sentinel-schema`; Lua equivalent is `runtime/runtime_types.lua`. Not blocking. |
| SENT-0.4 — ADR Citation Lint | ❌ | No lint script. ADR citation is a Rust-convention; N/A to Lua. |
| SENT-0.5 — Mangos TBC Fixture Database | ✅ | `tbcmangos.sqlite` (real Mangos TBC DB) present at repo root; QueryServer reads via `SENTINEL_DB_PATH`. |
| SENT-0.6 — Developer Environment Documentation | ⚠️ | README exists; missing per-volume ADR links. |

---

## Phase 1 — Canonical Schema

*Under Lua-truth the canonical schema lives in the Lua runtime types
(`runtime/runtime_types.lua`, `runtime/stage_*.lua` payloads), not Rust. Rust
`sentinel-schema` is secondary.*

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-1.1 — Root Profile, Metadata, ProfileSettings | ✅ (Lua) | `runtime/profile_manager.lua` + `runtime_types.lua` model Profile/Metadata/Settings. Rust copy demoted. |
| SENT-1.2 — Revised Operation Struct | ✅ (Lua) | `runtime/stage_*.lua` operate on Operation tables with all 007 §3 fields. |
| SENT-1.3 — OperationGoal & GoalType | ✅ (Lua) | `modules/operation/goal_coverage.lua` handles all 11 GoalType variants. |
| SENT-1.4 — Entry/Exit Conditions & Condition Enum | ✅ (Lua) | `modules/operation/condition_evaluator.lua` evaluates the condition tree exhaustively. |
| SENT-1.5 — OptimizationPolicy & CompletionMetrics | ✅ (Lua) | Carried on Operation tables; consumed by `stage_optimization.lua`. |
| SENT-1.6 — OperationDependency & DependencyType | ✅ (Lua) | `modules/operation/dependency_graph.lua` implements all four DependencyType variants. |
| SENT-1.7 — Action, ActionPayload & Primitive Payload Structs | ✅ (Lua) | `runtime/blueprint_registry.lua` + `runtime/runtime_action_executor.lua` define/expand all payload types. |
| SENT-1.8 — Reference & Value Types | ✅ (Lua) | Resolved at compile time (`stage_reference_resolution.lua`); `runtime_types.lua` helpers. |
| SENT-1.9 — Analytics & OperationAnalytics Structs | ⚠️ | Deferred with Phase 9 (MVP §17). |
| SENT-1.10 — Schema Version Constants & Migration Registry | ✅ (Lua) | `runtime/migration_registry.lua` chain-walks versions; `0.0.0→1.0.0` advances `schema_version`. |

---

## Phase 2 — Profile Storage & File I/O

*Lua `runtime/storage_manager.lua` is canonical. YAML (ADR 011 §2) is replaced by
JSON per the approved divergence; Tier1→Tier2 here is compiler-side, not load-side.*

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-2.1 — YAML Serialization Adapter | ⚠️ Diverged | JSON used instead of YAML (approved). `runtime_types` + storage_manager serialize via `lib/JSON`. |
| SENT-2.2 — Tier 1 On-Disk Reference Types | ✅ (Lua, compiler-side) | References resolved at compile time in `stage_reference_resolution.lua`, not as separate on-disk types. |
| SENT-2.3 — Workspace & Manifest Read/Write | ✅ (Lua) | `storage_manager.lua` writes a `manifest` + per-op files; loader reassembles. |
| SENT-2.4 — Operation File Read/Write | ✅ (Lua) | One file per Operation under `sentinel/profiles/authoring/<id>/ops/<op_id>.json`. |
| SENT-2.5 — Shared Library Files | ⚠️ Diverged | No separate `npc_library/quest_library/vendor_library.yaml`; libraries resolved via QueryServer at compile time. Approved under Lua-truth. |
| SENT-2.6 — Blueprint Library File I/O | ✅ (Lua) | `blueprint_registry.lua` holds standard blueprints in-repo; no YAML dir needed. |
| SENT-2.7 — Tier 1 → Tier 2 Resolution (Load) | ✅ (Lua, compile-time) | `stage_reference_resolution.lua` resolves references against QueryServer. |
| SENT-2.8 — Tier 2 → Tier 1 Lowering (Save) | ✅ (Lua) | `storage_manager` round-trips authoring profile. |
| SENT-2.9 — Dirty Tracking & Partial Save | ✅ (Lua) | `storage_manager` rewrites only changed op files. |
| SENT-2.10 — Atomic Writes & Advisory Locking | ✅ (Lua) | `storage_manager:_atomic_write` writes `.tmp` then renames. |
| SENT-2.11 — Per-File Schema Migration Engine | ✅ (Lua) | `migration_registry.lua` runs per-file on load; `0.0.0→1.0.0` verified. |

---

## Phase 3 — QueryServer (Rust — CANONICAL)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-3.1 — Axum Service Scaffold & API Versioning | ✅ | `/api/v1/` routing + health check. |
| SENT-3.2 — SQLite Read Layer | ✅ | Prepared statements, connection pooling. MaNGOS `-1`/integer-Faction handled via `get_u32_saturating` / `get_faction_string`. |
| SENT-3.3 — Quest Endpoints | ✅ | Search, Details, Chain, Near. Real-DB 500 fixed 2026-07-19. |
| SENT-3.4 — NPC Endpoints | ✅ | Lookup, Search, Near. Faction crash fixed. |
| SENT-3.5 — Creature Endpoints & Spawn Locations | ✅ | |
| SENT-3.6 — Vendor & Trainer Endpoints | ✅ | |
| SENT-3.7 — Flight Master, Mailbox, Inn Endpoints | ⚠️ | Implemented; `flight-masters` returns `[]` (empty `taxi_nodes` in this DB — data gap, not a crash). |
| SENT-3.8 — Area Query & Polygon Analysis | ✅ | |
| SENT-3.9 — Route Analysis | ✅ | |
| SENT-3.10 — Quest Hub Analysis & Blueprint/Grind Suggestions | ✅ | |
| SENT-3.11 — Loot Lookup & World Graph | ✅ | |
| SENT-3.12 — Search Everywhere & Validation API | ⚠️ | Search done; validation endpoint incomplete. |
| SENT-3.13 — Caching Layer & Performance Verification | ✅ | LRU cache + TTL; benchmarks not formally run. |

---

## Phase 4 — Blueprint System (Lua — CANONICAL)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-4.1 — Blueprint Struct & Parameter Types | ✅ (Lua) | `blueprint_registry.lua`. |
| SENT-4.2 — Blueprint Definitions: Quest / Travel | ✅ (Lua) | All standard quest/travel blueprints registered. |
| SENT-4.3 — Blueprint Definitions: Combat / NPC Services | ✅ (Lua) | Grind/Vendor/Trainer/Repair/Mailbox/Bank etc. registered. |
| SENT-4.4 — Blueprint Definitions: Recovery / Utility | ✅ (Lua) | Death Skip, Wait, Set Variable, Conditional Branch, etc. registered. |
| SENT-4.5 — Parameter Resolution & Smart Defaults | ✅ (Lua) | `stage_blueprint_expansion.lua` resolves via QueryServer. |
| SENT-4.6 — Conditional Expansion | ✅ (Lua) | Optional param omission handled in `blueprint_registry.lua`. |
| SENT-4.7 — Nested Blueprint Composition | ✅ (Lua) | Recursive expansion; depth-limited cycle detection. |
| SENT-4.8 — Blueprint Expansion Pipeline | ✅ (Lua) | Validate → Resolve → Inject → Optimize → Graph. `generated_from` tagging present. |
| SENT-4.9 — Blueprint Validation | ⚠️ | Partial; missing NPC/vendor validation against QueryServer. |

---

## Phase 5 — Operation System Logic (Lua — CANONICAL)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-5.1 — Goal Coverage Checking (Static) | ✅ | `goal_coverage.lua` hardened 2026-07-19 (action-type spelling + quest_id nesting). |
| SENT-5.2 — Entry/Exit Condition Evaluation Engine | ✅ | `condition_evaluator.lua`. |
| SENT-5.3 — Operation Dependency Graph Construction | ✅ | `dependency_graph.lua`. |
| SENT-5.4 — Cycle Detection & ExcludesWith Conflict | ✅ (Lua) | `cycle_detector.lua` + `stage_dependency_resolution.lua`. |
| SENT-5.5 — Topological Sort with Priority Tie-Breaking | ✅ | `topological_sort.lua`. |
| SENT-5.6 — Operation Lifecycle State Machine | ✅ | `operation_lifecycle.lua`. |
| SENT-5.7 — Sub-Operation Composition | ✅ | `sub_operation_composer.lua`. |

---

## Phase 6 — The Compiler (Lua — CANONICAL)

*7 stages implemented in `runtime/stage_*.lua`, orchestrated by
`runtime/compile_pipeline.lua` + `runtime/compiler_bridge.lua`. Rust
`sentinel-compiler` is secondary.*

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-6.1 — Stage 1: Structural Validation | ✅ (Lua) | `stage_*` + `diagnostics.lua`. |
| SENT-6.2 — Stage 2: Reference Resolution | ✅ (Lua) | `stage_reference_resolution.lua`. |
| SENT-6.3 — Stage 3: Blueprint Expansion | ✅ (Lua) | `stage_blueprint_expansion.lua`. |
| SENT-6.4 — Stage 4: Operation Dependency Resolution | ✅ (Lua) | `stage_dependency_resolution.lua`. |
| SENT-6.5 — Stage 5: Goal Coverage Validation | ✅ (Lua) | `stage_goal_coverage.lua`. |
| SENT-6.6 — Stage 6: Adjacency Merge | ✅ (Lua) | `stage_optimization.lua` (vendor+repair collapse, trailing/leading merge). |
| SENT-6.7 — Stage 6: Reordering & Redundancy | ✅ (Lua) | `route_analysis.lua:reorder_actions` + `stage_optimization.lua`. Fixed 2026-07-19. |
| SENT-6.8 — Stage 7: Lowering to RuntimeProfile | ✅ (Lua) | `stage_lowering.lua`. |
| SENT-6.9 — Diagnostics System | ✅ (Lua) | `diagnostics.lua` per 002 §19. |
| SENT-6.10 — Incremental Compilation | ⚠️ | Dirty-scoped recompile partially wired; full incremental benchmark not done. |
| SENT-6.11 — Compile Caching & Determinism | ✅ (Lua) | Content-hash cache; determinism verified by `test_compiler_bridge`. |
| SENT-6.12 — Northshire E2E | ✅ | `test_northshire_e2e.lua` — all 8 sub-tests pass. |

---

## Phase 7 — Sylvanas Bridge (Lua — CANONICAL)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-7.1 — QuestClient Trait & Mock | ✅ (Lua) | `integrations/sentinel_bridge/quest_client_trait.lua` + `mock_bridge.lua`. |
| SENT-7.2 — AddonsClient Trait & Mock | ✅ (Lua) | `addons_client_trait.lua`. |
| SENT-7.3 — RenderSurface Trait | ✅ (Lua) | `render_surface_trait.lua` + `render_bridge.lua` (headless). |
| SENT-7.4 — Event Bridge Translation Table | ✅ (Lua) | `event_bridge.lua` (verified by `test_bridge_traits`). |
| SENT-7.5 — Quest Log Diffing | ✅ (Lua) | `event_bridge.lua` diffing (Test 7 in harness). |
| SENT-7.6 — BridgeError Handling & Retry | ✅ (Lua) | `bridge_error.lua`. |
| SENT-7.7 — API Versioning & Drift Detection | ✅ (Lua) | `api_version.lua` (Test 8 in harness). |
| SENT-7.8 — Real Sylvanas API Binding | ✅ **RESOLVED** | ADR 009 §16 verified 2026-07-19 against in-repo `Documentation - Project Sylvannas/dev/api/` (accept_quest, complete_quest, get_quest_log_title, get_gossip_options, buy_trainer_service, register_on_render_callback, get_guid/object_manager all confirmed present). |

---

## Phase 8 — Runtime Execution Engine (Lua — CANONICAL)

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-8.1 — Profile Manager | ✅ (Lua) | `profile_manager.lua`. |
| SENT-8.2 — Runtime Context & Variable Store | ✅ (Lua) | `runtime_context.lua` + `variable_store.lua`. |
| SENT-8.3 — Event Dispatcher | ✅ (Lua) | `event_dispatcher.lua`. |
| SENT-8.4 — Operation Manager & Scheduler | ✅ (Lua) | `operation_manager.lua` + `operation_scheduler.lua`. |
| SENT-8.5 — Action Executor | ✅ (Lua) | `runtime_action_executor.lua`. |
| SENT-8.6 — Runtime State Machine & Failure Recovery | ⚠️ | States present; failure-hierarchy path needs integration testing. |
| SENT-8.7 — Continuous Validation Service | ⚠️ | `runtime_engine.lua` exists; incremental validation incomplete. |
| SENT-8.8 — Hot Reload | ⚠️ | Pipeline not fully wired. |
| SENT-8.9 — Undo/Redo Command Stack | ⚠️ | `command_history.lua` partial vs 002 §14. |
| SENT-8.10 — Dry Run Mode Integration | ✅ (Lua) | `dry_run.lua`. |
| SENT-8.11 — Threading Model & Logging Streams | ⚠️ | Lua is single-threaded (per architecture); 3 log streams not split. |

---

## Phase 9 — Analytics & Telemetry

**DEFERRED by MVP §17. Not blocked — intentionally out of MVP scope.**

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-9.1 — Telemetry Event Model & SQLite Schema | ❌ Deferred | |
| SENT-9.2 — AnalyticsServer Scaffold & Ingest | ❌ Deferred | |
| SENT-9.3 — Telemetry Collector | ❌ Deferred | `runtime/telemetry.lua` stub; failing test is the MVP-deferral marker. |
| SENT-9.4 — Operation-Level Aggregation | ❌ Deferred | |
| SENT-9.5 — Bottleneck Detection | ❌ Deferred | |
| SENT-9.6 — Trend & Cross-Version Compare | ❌ Deferred | |
| SENT-9.7 — Retention & Rollup Job | ❌ Deferred | |
| SENT-9.8 — Simulation Adapters | ⚠️ Partial | `dry_run.lua` has basic adapters. |
| SENT-9.9 — Export & Purge Endpoints | ❌ Deferred | |

---

## Phase 10 — Editor UI (Lua — CANONICAL)

*UI lives in `sentinel/ui/` + `sentinel/modules/.../init.lua`. Headless-testable via
`tests/ui/*`.*

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-10.1 — Docking Layout Framework | ✅ (Lua) | `ui/window.lua` (test_window). |
| SENT-10.2 — Toolbar | ✅ (Lua) | `ui/toolbar.lua` (test_toolbar). |
| SENT-10.3 — Explorer Panel | ✅ (Lua) | `ui/explorer_panel.lua`. |
| SENT-10.4 — World Map Rendering & Icons | ✅ (Lua) | `ui/world_map_panel.lua`. |
| SENT-10.5 — Map Interaction | ⚠️ | Basic interaction; not all modes. |
| SENT-10.6 — Target Capture Panel | ✅ (Lua) | `ui/target_capture_panel.lua`. |
| SENT-10.7 — NPC Library & Quest Browser | ✅ (Lua) | `ui/npc_library_panel.lua`, `ui/quest_browser_panel.lua`. |
| SENT-10.8 — Timeline & Action Palette | ⚠️ | `ui/timeline_panel.lua`; drag/drop polish pending. |
| SENT-10.9 — Inspector & Property Editors | ⚠️ | `ui/inspector_panel.lua`; not all ActionPayload editors. |
| SENT-10.10 — Variables Panel | ✅ (Lua) | `ui/variables_panel.lua`. |
| SENT-10.11 — Validation Panel | ✅ (Lua) | `ui/validation_panel.lua`. |
| SENT-10.12 — Console (3 tabs) | ✅ (Lua) | `ui/console_panel.lua`. |
| SENT-10.13 — Dry Run Panel | ⚠️ | Panel exists; controls wiring partial. |
| SENT-10.14 — Path/Polygon Recorder | ⚠️ | Recorder logic partial. |
| SENT-10.15 — Context Menus | ⚠️ | Partial. |
| SENT-10.16 — Blueprint Library Panel | ⚠️ | No drag-to-timeline yet. |
| SENT-10.17 — Multi-Select, Undo/Redo, Search, Hotkeys | ⚠️ | Partial. |
| SENT-10.18 — Analytics Panel | ❌ Deferred | Depends on Phase 9. |

---

## Phase 11 — Integration, Hardening & Release

| Ticket | Status | Notes |
|--------|--------|-------|
| SENT-11.1 — Full E2E Integration Suite | ✅ | `test_northshire_e2e.lua` green in harness. |
| SENT-11.2 — Performance Benchmarking | ❌ | No benchmark suite. |
| SENT-11.3 — Diagnostics UX Pass | ❌ | Not done. |
| SENT-11.4 — Module-Level CLAUDE.md | ⚠️ | `runtime/CLAUDE.md` exists; module docs incomplete. |
| SENT-11.5 — Dogfood Profile Human 1–10 | ❌ | Not authored. |
| SENT-11.6 — Real Sylvanas API Verification | ✅ | ADR 009 §16 resolved (see SENT-7.8). |
| SENT-11.7 — Release Readiness Review | ❌ | Not performed. |

---

## Honest Gap List (what remains to call the MVP done)

| Gap | Phase | Impact | Recommendation |
|-----|-------|--------|----------------|
| Phase 9 Analytics | 9 | Deferred by MVP §17 | Ship without; revisit post-MVP. |
| SENT-8.6/8.7/8.8/8.9 | 8 | Runtime hardening | Integration-test failure recovery, incremental validation, hot reload, undo/redo. |
| SENT-10.5/10.8/10.9/10.13/10.14/10.15/10.16/10.17 | 10 | UI polish | Editor panels need full interaction wiring. |
| SENT-11.2/11.3/11.5/11.7 | 11 | Hardening/release | Benchmarks, diagnostics UX, dogfood profile, release review. |
| SENT-4.9 / SENT-3.12 validation | 4/3 | Completeness | Blueprint validation vs QueryServer; validation endpoint. |
| SENT-6.10 | 6 | Perf | Incremental recompile benchmarking. |

---

## Test Results (Rust QueryServer — canonical Rust)

`cargo test -p sentinel-queryserver` — endpoint tests pass against fixture + real DB
(MaNGOS `-1`/integer-Faction handled). Full workspace: schema + compiler crates have
their own tests but are secondary.

## Test Results (Lua Offline Harness — canonical runtime)

`luajit tests/run_offline.lua` — **41 passed, 2 failed** (verified 2026-07-19).

- **Failing (MVP §17 deferrals, not regressions):**
  - `tests/runtime/test_telemetry.run` — SENT-9.3 (Phase 9 deferred).
  - `tests/modules/combat/test_target_selector.run` — combat target-selector
    reordering (deferred).
- **Passing suites covering the canonical Lua phases:** bridge traits, northshire
  e2e, compiler stages, compiler bridge, storage manager, migration registry, route
  analysis, operation modules, runtime engine, profile manager, event dispatcher,
  variable store, dry run, UI panels.

---

## Architectural Notes

1. **Lua = canonical runtime + compiler; Rust = QueryServer only.** `sentinel-schema`
   and `sentinel-compiler` Rust crates are demoted to secondary/offline tooling and
   must not receive new runtime logic.
2. **Storage is JSON, not YAML (approved divergence).** ADR 011's format is superseded
   by the Lua-truth ruling; the structural properties (per-op files, Tier1→Tier2
   resolution, atomic writes, dirty partial-save, per-file migration) are honored.
3. **MaNGOS `-1` sentinel / integer-Faction** (fixed 2026-07-19): any new QueryServer
   endpoint reading a numeric column capable of `-1`, or the `Faction` column, must use
   `get_u32_saturating` / `get_faction_string` or it 500s on real data.
4. **Action-type vocabulary:** runtime emits snake_case (`pickup_quest`,
   `turn_in_quest`, `quest_hub`, `flight_path`, `train`, `talk_to_npc`); ADR-008 §8
   names PascalCase. Coverage/route/optimization accept both. `LoweringStage` cache is
   keyed by content hash (per-instance) since 2026-07-19.
5. **SENT-7.8 / SENT-11.6 RESOLVED** — verified against in-repo Sylvanas API docs, not
   assumed.

---

*Report regenerated: 2026-07-19 — architecture-of-record correction (Lua canonical,
Rust QueryServer-only); harness re-run (41 pass / 2 fail).*
