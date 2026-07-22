# Design: Questing v2 — Import Fidelity, Real Compilation, Runtime Repair

## Technical Approach

Keep the compile-before-execute pipeline; repair the three broken stages in place. The importer
lowers RestedXP commands into typed authoring data (coords, conditions, class suffixes, sticky/loop)
and never silently drops. The compiler parses condition expression strings into typed
`RuntimeCondition`, resolves object entries, and filters by target class. The Lua runtime conforms to
the `runtime::action.rs` contract and wires into the shared app. Reference resolution stays in the
compiler; Lua consumes only entry IDs + coordinates. Delivered as the proposal's 4-PR chain
(import / compiler / re-import / runtime). Grounded against the spec files and current source.

## Architecture Decisions

| # | Decision | Choice | Rejected alternative | Rationale |
|---|----------|--------|----------------------|-----------|
| 1 | Typed-gating authoring representation | Reuse existing `Action.condition: Option<String>` gate and `ActionPayload::Condition{expression}`; importer emits the canonical `02_DATA_MODEL.md §23` infix DSL string (e.g. `QuestCompleted(33) && Level >= 10`) | Add a typed authoring `Condition` enum | `02_DATA_MODEL.md §23` already defines this expression grammar; a new enum forces schema/serde churn and editor-history migration for no runtime gain (compiler parses either way) |
| 2 | Condition grammar → runtime mapping | New `compiler/src/condition.rs` parser: `§23` DSL → actual `RuntimeCondition` variants (`condition.rs:9-27`); unmappable → compiler diagnostic (never `AlwaysTrue` fallback) | Keep `AlwaysTrue` shortcut | Spec `compiler-condition-lowering` forbids blanket `AlwaysTrue`; diagnostic preserves the never-drop guarantee |
| 3 | Class filtering | **REVISED 2026-07-22 (maintainer decision): runtime-evaluated, not compile-time stripped.** The importer already captures `Action.class_restriction: Option<String>` (PR1b-ii). The compiler lowers a present `class_restriction` into a `RuntimeCondition::ClassIs(<class>)` combined (via `All`) with the action's existing condition; it does NOT strip actions or emit per-class profiles. One universal profile serves every class; the runtime gates each class-restricted action via the existing `ClassIs` condition handler (`runtime_action.lua` `ctx:get_n()`, backed by Sylvannas `get_local_player():n()`). No `--class` flag, no `<project>.<class>.profile.json`. | Compile-time `--class` stripping into per-class profiles | The runtime condition infrastructure already exists end-to-end (`RuntimeCondition::ClassIs` variant, Lua handler, Sylvannas class getter, combat module already reads class); compile-time stripping would duplicate it with a new pass + CLI flag + N-profile matrix. Leaner per-class profiles (the only benefit of stripping) are irrelevant at TBC scale and remain a future optional optimization. |
| 4 | Coordinate preservation | Importer populates existing `TravelAction.position` from `.goto` args; zone-name→map-id via a static importer table | Resolve zone→map via QueryServer | QueryServer has no zone/map table; compiler already passes `position` through (lib.rs:87-89) — only the importer at `project_builder.rs` needs fixing |
| 5 | Bundle split + typo tolerance | `guide_splitter` emits one `Project` per guide. Corpus correction (PR1b apply, 2026-07-22): `The Burning Crusade.lua` is 253 separate `RegisterGuide([[...]])` blocks in one file, NOT multiple `#name` headers inside one block — the splitter needs an outer `RegisterGuide`-block scan before per-guide header parsing. A canonicalization table (edit-distance-1) maps `#compltewith`→`#completewith` etc. with an info diagnostic (implemented in PR1b); unknown directive/command → typed inert annotation + per-command diagnostic | Silent tolerance / drop | Never-drop policy; typo diagnostics stay grouped by command to limit noise |
| 6 | Coverage report | `import-guides` emits a `CoverageReport` (JSON + summary): per-command typed / inert-preserved / unresolved counts vs the TBC fidelity bar | Ad-hoc log lines | Golden-artifact regeneration needs a machine-checkable coverage metric |
| 7 | Unknown-condition policy | Fail-open everywhere (audit L01 governs), log diagnostic | Fail-closed (ticket 017) | Runtime spec resolves this: main line must never stall |

## Data Flow

    live QueryServer ──resolve NPC/quest/object (async QueryClient, PR3 re-import)──┐
                                                                                    ▼
    RestedXP bundle ─→ importer(split, lex, typed lowering, resolution, coverage) ─→ Project JSON (+§23 DSL gates, class tags, coords, resolved npc_library)
                                                                                    │
              compiler(sync: §23 DSL→RuntimeCondition parse, class filter, HashMap entry lookup) ◄┘
                                                                                    │
                                            per-class RuntimeProfile JSON ─→ Lua runtime (FSM, shared bus)

Reference resolution against the live QueryServer happens in the **importer** at import time
(`project_builder.rs:72-142, 228-260, 654-661` — async QueryClient calls populate `npc_library`).
The compiler (`lib.rs:31-39`) is synchronous and only performs HashMap lookups over the
already-resolved maps. The spec `compiler-condition-lowering` requirement "Resolution Against a
Live QueryServer" is therefore fulfilled by the importer's existing resolution during the PR3
re-import — **no new compiler-side QueryClient work** is introduced.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `SentinelQuesting/importer/src/project_builder.rs` | Modify | populate `TravelAction.position` from `.goto` coords; lower gating cmds to DSL gate strings; attach `class_restriction`; never-drop typed inert + diagnostics |
| `SentinelQuesting/importer/src/{lexer,guide_splitter,step_builder,label_graph}.rs` | Modify | class-suffix token, sticky/loop metadata, typo canonicalization table, multi-header split |
| `SentinelQuesting/importer/src/coverage.rs` | Create | `CoverageReport` aggregation |
| `SentinelQuesting/shared/src/authoring/action.rs` (+ operation.rs) | Modify | add `Action.class_restriction`; `Operation.sticky/loop` flags |
| `SentinelQuesting/compiler/src/condition.rs` | Create | DSL → `RuntimeCondition` parser + diagnostics |
| `SentinelQuesting/compiler/src/lib.rs` | Modify | remove `AlwaysTrue` (157-161); resolve `LootObject.object_entry` (196-201); class-filter; `CompileReport`; `sentinel-compile --class` (CLI-only) |
| `sentinel/runtime/module_registry.lua` | Modify | init thunk (`:172-191`, `module_def.init(bb,eb)`) reaches `QuestingModule:initialize` in lifecycle |
| `sentinel/modules/questing/{module,runtime_profile,runtime_action}.lua` | Modify | payload fixes; inject shared bus/blackboard (drop `:new()` at runtime_profile.lua:41,46); cache `create_context`; bound `_execution_log`; ghost-throttle fix |
| `sentinel/tests/run_offline.lua` | Modify | round-trippable JSON mock |

## Interfaces / Contracts

**Condition DSL** — importer emits, compiler parses. Grammar is `02_DATA_MODEL.md §23` (qualified;
distinct from the unrelated ADR-03 §23 Undo/Redo): infix predicates combined with `&&` / `||` /
`NOT` and parentheses, comparison operators (`>=`) on level. Example: `QuestCompleted(33) && Level >= 10`.
Lowering targets are the actual `RuntimeCondition` variants (`shared/src/runtime/condition.rs:9-27`);
`&&`→`All`, `||`→`Any`, `NOT`→`Not`.

Command → §23 DSL → `RuntimeCondition` mapping (the seven gating commands):

| RestedXP command | §23 DSL | RuntimeCondition variant |
|------------------|---------|--------------------------|
| `.complete <q> <idx>` | `Objective(q,idx)` | `ObjectiveComplete(q, idx)` |
| `.collect <item> <n>` | `ItemCount(item,n)` | `ItemCountAtLeast(item, n)` |
| `.itemcount <item> <n>` | `ItemCount(item,n)` | `ItemCountAtLeast(item, n)` |
| `.isOnQuest <q>` | `QuestAccepted(q)` | `QuestAccepted(q)` — closest existing variant (quest present in log); documented caveat: "on quest" ≈ accepted-and-not-yet-rewarded, `QuestAccepted` does not exclude turned-in quests; acceptable under fail-open |
| `.isQuestComplete <q>` | `QuestCompleted(q)` | `QuestCompleted(q)` |
| `.isQuestTurnedIn <q>` | `QuestRewarded(q)` | `QuestRewarded(q)` |
| `.isQuestAvailable <q>` | `NOT QuestRewarded(q)` | `Not(QuestRewarded(q))` — closest; caveat: prerequisite/level availability not modeled, fail-open covers gaps |

Every target variant already exists in `condition.rs:9-27` (verified: `QuestAccepted`, `QuestCompleted`,
`QuestRewarded`, `ObjectiveComplete`, `ItemCountAtLeast`, `LevelAtLeast`, `Not`, `All`, `Any`) — **no
`RuntimeCondition` enum variant is added**, consistent with the "no schema migration" claim (the only
additive authoring field is `Action.class_restriction`, which loads via serde default).

**Lua payload alignment**: read `choose_reward` (not `reward_choice`, runtime_action.lua:275);
`Flight/Hearth.destination` as string (not table, :489); `Vendor.buy_items` `Vec<u32>`; `Kill` uses
`creature_entries`, no `destination`. `CompileReport { class_excluded, unresolved, unmapped_conditions }`.

## Runtime Mechanisms

- **Bounded execution log**: named module constant `MAX_EXECUTION_LOG = 200`; `_execution_log` becomes
  a drop-oldest ring (append then `table.remove(1)` when over cap) in `runtime_profile.lua`; saves
  (`:108`, `:887`) serialize at most `MAX_EXECUTION_LOG` entries.
- **Ghost throttle**: replace the no-op modulo check (runtime_profile.lua:1127-1141) with a
  `_last_ghost_attempt` timestamp; a new attempt is allowed only when
  `core.time() - _last_ghost_attempt >= GHOST_RETRY_INTERVAL`, then stamp `_last_ghost_attempt`.
- **Context cache**: build `create_context` once (in `RuntimeProfile:new`/first tick), stored on the
  instance and reused across ticks; invalidated only on hot-reload/profile swap (`:705`). Closures read
  live blackboard/object-manager state, so no per-tick rebuild is needed — no fields require per-tick
  refresh; only the current-action pointer advances, which the cached context reads by reference.
- **JSON mock (test harness)**: make `run_offline.lua`'s mock a real round-trippable pair — stringify
  emits JSON *and* parse decodes JSON via a small pure-Lua decoder in the harness, replacing the
  Lua-literal emission that broke `test_restore_state_from_save`. Production code keeps its existing
  JSON-then-Lua fallback order unchanged.
- **Shared bus/blackboard injection path**: `SentinelApp` owns the shared `EventBus`/`Blackboard` →
  passes them into `ModuleRegistry` → the init thunk (`module_registry.lua:172-191`,
  `module_def.init(blackboard, event_bus)` → `QuestingModule:new`) → new `QuestingModule:initialize`
  wiring forwards them as `RuntimeProfile` constructor parameters, replacing the private
  `Blackboard:new()`/`EventBus:new()` at `runtime_profile.lua:41,46`. `questing:log` then fires on the
  shared bus.

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Unit (Rust) | coord parse, DSL round-trip, typo canon, class filter, LootObject resolve | `cargo test -p sentinel-importer / -p sentinel-compiler`, RED-first per spec scenario |
| Integration (Rust) | bundle split → N projects; live-resolve; coverage vs fidelity bar | `sentinel-tests` E2E + fixture QueryServer |
| E2E / runtime (Lua) | payload handlers, registry init→ACTIVE, shared-bus event, bounded log, ghost throttle, save round-trip | `luajit sentinel/tests/run_offline.lua` offline suites |
| In-game harness | per-action-type scenarios + one chained accept→travel→kill→collect→turnin on startable Human path | compiled per-class profile loaded via a boot-time profile-path config (loader UI out of scope); evidence: FSM logs + forced death/stuck/reload |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, or executable-file classification. The
re-import's live-QueryServer dependency is an existing, read-only HTTP GET boundary (no new
process integration).

## Migration / Rollout

No schema migration. The single additive authoring field (`Action.class_restriction`) loads via
serde default, so old JSON still parses; no `RuntimeCondition` enum variant is added (the seven
gating commands map onto existing variants, see Interfaces). Project JSONs are regenerated via
`import-guides`; on-disk profiles untouched by rollback. Each PR reverts independently per the
proposal's rollback plan.

## Open Questions

- [ ] Startup profile selection until the loader UI ships: a fixed config path is assumed — confirm the boot-time hook location in `sentinel/main.lua`.
- [ ] `LootObject`/`.collect` entry resolution depends on a QueryServer object endpoint that may be absent — unresolved refs fall to diagnostics (named follow-up), not a gate.

## Spec Reconciliation Needed

None. All decisions are consistent with the three spec files; the class-restriction authoring field
(Decision 3) is additive and required to satisfy the post-gate "Compile-Time Class Restriction
Filtering" requirement.
