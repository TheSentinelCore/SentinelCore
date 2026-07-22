# Tasks: Questing v2 — Import Fidelity, Real Compilation, Runtime Repair

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1a ~260, PR1b ~320, PR2a ~300, PR2b ~220, PR3 ~180 authored (+goldens excluded), PR4a ~260, PR4b ~260 |
| 400-line budget risk | High (PR1, PR2, PR4 each exceed 400 if kept as single PRs) |
| Chained PRs recommended | Yes |
| Suggested split | PR1a → PR1b → PR2a → PR2b → PR3 → PR4a → PR4b (7 units under the 4-PR umbrella) |
| Delivery strategy | auto-forecast (auto-chain when needed) |
| Chain strategy | pending — user must pick stacked-to-main vs feature-branch-chain before apply |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

Rationale: PR1 (7 reqs, 6 importer files + new `coverage.rs`) and PR2 (new DSL parser + class filter) each independently approach/exceed 400 authored lines; PR4's JSON-mock rewrite plus mechanical fixes are two separable concerns. PR3 is authored-light (~180 lines: live-resolve wiring + coverage assertions) but regenerates 8 golden project JSONs — call these out separately in the PR description, excluded from the 400-line authored count per guard rule.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| PR1a | Goto coords + gating/completion condition lowering (IF1, IF2) | PR1a | `cargo test -p sentinel-importer` | N/A — Rust unit/integration only | `project_builder.rs` coord/condition changes revert independently |
| PR1b | Class suffix, sticky/loop, typo tolerance, bundle split, never-drop, coverage report (IF3–IF7) | PR1b | `cargo test -p sentinel-importer` | N/A — Rust unit/integration only | `lexer.rs`/`guide_splitter.rs`/`step_builder.rs`/`label_graph.rs`/new `coverage.rs` revert independently of PR1a |
| PR2a | Condition DSL → `RuntimeCondition` parser (CL1) | PR2a | `cargo test -p sentinel-compiler` | N/A | New `condition.rs` + call site removable without touching CL2/CL4 |
| PR2b | LootObject resolution + class-restriction compile filter (CL2, CL4) | PR2b | `cargo test -p sentinel-compiler` | N/A | `lib.rs` LootObject/class-filter hunks revert independently |
| PR3 | Live re-import + golden regeneration + coverage stats (CL3, CL5) | PR3 | `cargo test -p sentinel-tests` | Manual: run `import-guides` against live `SentinelQueryServer` (`SENTINEL_DB=tbcmangos.sqlite`), inspect regenerated Elwynn JSON | Regenerated `.questing/projects/*.json` revert via `git checkout` of prior goldens |
| PR4a | Payload fixes, registry wiring, shared bus, perf, log bound, ghost throttle (RE1–RE6, RE10) | PR4a | `luajit sentinel/tests/run_offline.lua` | Manual: boot client, confirm `QuestingModule` reaches ACTIVE and ticks a loaded profile | Each Lua file's hunk revertable without affecting PR4b's JSON mock |
| PR4b | JSON mock round-trip + FSM/action-type/chained verification (RE7–RE9) | PR4b | `luajit sentinel/tests/run_offline.lua` | Manual: per-action-type scenarios + accept→travel→kill→collect→turnin + forced death/stuck/reload on startable Human path | `run_offline.lua` mock decoder revertable independently |

## Requirement Traceability

| Req ID | Requirement | Spec | Task IDs |
|--------|-------------|-------|----------|
| IF1 | Goto Coordinate Preservation | import-fidelity | 1.1–1.2 |
| IF2 | Typed Condition Lowering (gating/completion) | import-fidelity | 1.3–1.4 |
| IF3 | Per-Line Class Suffix Parsing | import-fidelity | 2.1–2.2 |
| IF4 | Sticky/Loop Directive Handling | import-fidelity | 2.3–2.4 |
| IF5 | Typo-Tolerant Directive Parsing | import-fidelity | 2.5–2.6 |
| IF6 | Multi-Guide Bundle Splitting | import-fidelity | 2.7–2.8 |
| IF7 | Never-Drop Policy | import-fidelity | 2.9–2.11 |
| CL1 | Condition Lowering Completeness | compiler-condition-lowering | 3.1–3.3 |
| CL2 | LootObject Entry Resolution | compiler-condition-lowering | 4.1–4.2 |
| CL4 | Compile-Time Class Restriction Filtering | compiler-condition-lowering | 4.3–4.5 |
| CL3 | Resolution Against a Live QueryServer | compiler-condition-lowering | 5.1–5.2 |
| CL5 | Golden Artifact Regeneration + Coverage Stats | compiler-condition-lowering | 5.3–5.5 |
| RE1 | Payload Field Contract Alignment | questing-runtime-execution | 6.1–6.2 |
| RE2 | ModuleRegistry Initialization Wiring | questing-runtime-execution | 6.3–6.4 |
| RE3 | Shared EventBus/Blackboard Usage | questing-runtime-execution | 6.5–6.6 |
| RE4 | Bounded Execution Log | questing-runtime-execution | 6.7–6.8 |
| RE5 | Cached Per-Tick Execution Context | questing-runtime-execution | 6.9–6.10 |
| RE6 | Functional Ghost-Recovery Throttle | questing-runtime-execution | 6.11–6.12 |
| RE10 | Unknown Condition Fail-Open Policy | questing-runtime-execution | 6.13–6.14 |
| RE9 | Round-Trippable Test Harness Mock | questing-runtime-execution | 7.1–7.2 |
| RE8 | Per-Action-Type + Chained-Sequence Verification | questing-runtime-execution | 7.3–7.10 (manual) |
| RE7 | Recovery FSM Verification | questing-runtime-execution | 7.11–7.13 (manual) |

## PR1a: Import Fidelity — Coordinates + Gating Conditions

- [x] 1.1 RED `SentinelQuesting/importer/tests/mapper.rs`: `.goto` with numeric coords → `TravelAction.position` non-null; zone-only `.goto` → `position` nil, no error (IF1)
- [x] 1.2 GREEN `SentinelQuesting/importer/src/project_builder.rs:327-345`: parse coord args, populate `position` (IF1)
- [x] 1.3 RED `SentinelQuesting/importer/tests/mapper.rs`: 7 gating commands (`.complete/.collect/.itemcount/.isOnQuest/.isQuestComplete/.isQuestTurnedIn/.isQuestAvailable`) → typed `§23` DSL condition, not `Comment`; malformed args → typed inert + diagnostic (IF2)
- [x] 1.4 GREEN `SentinelQuesting/importer/src/project_builder.rs`: lower gating commands per design mapping table into `ActionPayload::Condition` DSL strings (IF2)

## PR1b: Import Fidelity — Class/Metadata/Typo/Split/Never-Drop

- [ ] 2.1 RED `SentinelQuesting/importer/tests/importer.rs`: line ending `<< Warrior` → `class_restriction = "Warrior"` (IF3)
- [ ] 2.2 GREEN `SentinelQuesting/importer/src/lexer.rs` + `SentinelQuesting/shared/src/authoring/action.rs`: add `class_restriction: Option<String>` (serde default), parse suffix (IF3)
- [ ] 2.3 RED `SentinelQuesting/importer/tests/importer.rs`: `#sticky` step → `Operation.sticky = true` (IF4)
- [ ] 2.4 GREEN `SentinelQuesting/importer/src/step_builder.rs` + `SentinelQuesting/shared/src/authoring/operation.rs`: add `sticky`/`loop` flags, parse directives (IF4)
- [ ] 2.5 RED `SentinelQuesting/importer/tests/importer.rs`: `#compltewith` → canonical `#completewith` + info diagnostic (IF5)
- [ ] 2.6 GREEN `SentinelQuesting/importer/src/lexer.rs`: edit-distance-1 typo canonicalization table (IF5)
- [ ] 2.7 RED `SentinelQuesting/importer/tests/mapper.rs` w/ `fixtures/guide_basic.lua` variant: N-header bundle → N `Project` outputs (IF6)
- [ ] 2.8 GREEN `SentinelQuesting/importer/src/guide_splitter.rs`: split on multiple headers preserving per-guide metadata (IF6)
- [ ] 2.9 RED `SentinelQuesting/importer/tests/importer.rs`: `.equip`/`.skill` → typed inert action + diagnostic naming command/args (IF7)
- [ ] 2.10 GREEN `SentinelQuesting/importer/src/label_graph.rs` + `project_builder.rs`: never-drop fallback to typed inert annotation (IF7)
- [ ] 2.11 GREEN `SentinelQuesting/importer/src/coverage.rs` (new): `CoverageReport` — per-command typed/inert/unresolved tally (IF7, feeds CL5)

## PR2a: Compiler — Condition DSL Parser

- [ ] 3.1 RED `SentinelQuesting/compiler/tests/compiler.rs`: `QuestCompleted(1234)` DSL → `RuntimeCondition::QuestCompleted(1234)`; unmappable expr → diagnostic, no `AlwaysTrue` (CL1)
- [ ] 3.2 GREEN `SentinelQuesting/compiler/src/condition.rs` (new): parse `&&`/`||`/`NOT`/parens per design mapping table into `condition.rs:9-27` variants (CL1)
- [ ] 3.3 GREEN `SentinelQuesting/compiler/src/lib.rs:160`: remove `RuntimeCondition::AlwaysTrue` shortcut, call new parser, wire unmapped-expr diagnostics (CL1)

## PR2b: Compiler — LootObject Resolution + Class Filtering

- [ ] 4.1 RED `SentinelQuesting/compiler/tests/compiler.rs`: resolvable `LootObject` → real `object_entry`; unresolvable → diagnostic, not `0` (CL2)
- [ ] 4.2 GREEN `SentinelQuesting/compiler/src/lib.rs:198`: resolve via object library/entry ref instead of `object_entry: 0` (CL2)
- [ ] 4.3 RED `SentinelQuesting/compiler/tests/compiler.rs`: Paladin-restricted action + `--class Warrior` → excluded + counted class-excluded; `--class Paladin` → retained, no restriction metadata (CL4)
- [ ] 4.4 GREEN `SentinelQuesting/compiler/src/lib.rs`: class-filter pass over actions/operations, populate `CompileReport{class_excluded, unresolved, unmapped_conditions}` (CL4)
- [ ] 4.5 GREEN `SentinelQuesting/compiler/src/main.rs`: add `--class <C>` CLI flag, name output `<project>.<class>.profile.json` (CL4)

## PR3: Re-import Golden Artifacts

- [ ] 5.1 RED `SentinelQuesting/tests/src/lib.rs`: re-import of previously-broken Elwynn sample against live QueryServer → resolved `AcceptQuest`/`TurnInQuest`, not blanket `Comment` (CL3)
- [ ] 5.2 GREEN Run `SentinelQuesting/editor/src/bin/import-guides.rs` against live `SentinelQueryServer` (`SENTINEL_DB=tbcmangos.sqlite`); regenerate all 8 `.questing/projects/*.json` goldens (CL3) — excluded from authored-line budget, called out in PR body
- [ ] 5.3 RED `SentinelQuesting/tests/src/lib.rs`: full corpus re-import → `CoverageReport` percentages match/exceed fidelity bar; zero bare-`Comment` recognized commands (CL5)
- [ ] 5.4 GREEN `SentinelQuesting/editor/src/bin/import-guides.rs`: emit `CoverageReport` JSON + human summary alongside regenerated projects (CL5)
- [ ] 5.5 Verify: manually inspect coverage report vs `The Burning Crusade.lua` fidelity bar (~70 commands/~45 directives) (CL5)

## PR4a: Runtime — Wiring, Payload, Perf, Recovery Mechanics

- [ ] 6.1 RED `sentinel/tests/modules/questing/test_runtime_action.lua`: `TurnInQuest` reads `choose_reward`; `Kill` never reads `destination`; `Flight/Hearth.destination` string; `Vendor.buy_items` `Vec<u32>` (RE1)
- [ ] 6.2 GREEN `sentinel/modules/questing/runtime_action.lua`: fix 4 payload field mismatches vs `runtime/action.rs` (RE1)
- [ ] 6.3 RED `sentinel/tests/modules/questing/test_runtime_profile.lua`: registry init reaches `QuestingModule:initialize`, module hits ACTIVE (RE2)
- [ ] 6.4 GREEN `sentinel/runtime/module_registry.lua:172-191` + `sentinel/modules/questing/init.lua`: call `QuestingModule:initialize(blackboard, event_bus)` from the init thunk instead of only setting `_initialized` (RE2)
- [ ] 6.5 RED `sentinel/tests/modules/questing/test_runtime_profile.lua`: `questing:log` on shared `EventBus` observed by external subscriber (RE3)
- [ ] 6.6 GREEN `sentinel/modules/questing/module.lua:20-21` + `runtime_profile.lua:41,46`: drop private `Blackboard:new()`/`EventBus:new()`, thread shared instances from `SentinelApp` → registry → `QuestingModule` → `RuntimeProfile` ctor (RE3)
- [ ] 6.7 RED `sentinel/tests/modules/questing/test_runtime_persistence.lua`: execution log beyond cap saves at most `MAX_EXECUTION_LOG` entries (RE4)
- [ ] 6.8 GREEN `sentinel/modules/questing/runtime_profile.lua:108,887`: add `MAX_EXECUTION_LOG = 200` constant, drop-oldest ring on append (RE4)
- [ ] 6.9 RED `sentinel/tests/modules/questing/test_runtime_arch_polish.lua`: repeated ticks on one action reuse the same cached context instance (RE5)
- [ ] 6.10 GREEN `sentinel/modules/questing/runtime_profile.lua:705`: build `create_context` once, cache on instance, invalidate only on profile swap (RE5)
- [ ] 6.11 RED `sentinel/tests/modules/questing/test_runtime_nav.lua`: rapid re-detected ghosting before timeout suppresses 2nd recovery attempt (RE6)
- [ ] 6.12 GREEN `sentinel/modules/questing/runtime_profile.lua:1127-1141`: `_last_ghost_attempt` timestamp gate, replace no-op modulo (RE6)
- [ ] 6.13 RED `sentinel/tests/modules/questing/test_runtime_profile.lua`: unresolvable condition on optional gate AND on main line both proceed + log diagnostic (RE10)
- [ ] 6.14 GREEN `sentinel/modules/questing/runtime_profile.lua`: unknown-condition evaluator returns satisfied (fail-open), logs diagnostic unconditionally (RE10)

## PR4b: Runtime — JSON Mock + Action-Type/FSM Verification

- [ ] 7.1 RED `sentinel/tests/modules/questing/test_runtime_persistence.lua::test_restore_state_from_save`: save→parse round-trip loses no state (RE9)
- [ ] 7.2 GREEN `sentinel/tests/run_offline.lua`: replace Lua-literal mock emission with real JSON stringify + pure-Lua JSON decoder, keep production JSON-then-Lua fallback unchanged (RE9)
- [ ] 7.3 Manual: verify `AcceptQuest` action on a startable Human quest (RE8)
- [ ] 7.4 Manual: verify `TravelAction` navigation to resolved coords (RE8)
- [ ] 7.5 Manual: verify `Kill` action targets via `creature_entries` (RE8)
- [ ] 7.6 Manual: verify `LootObject` with resolved `object_entry` (RE8)
- [ ] 7.7 Manual: verify `Vendor` buy via `buy_items` (RE8)
- [ ] 7.8 Manual: verify `TurnInQuest` with `choose_reward` (RE8)
- [ ] 7.9 Manual: verify `Condition`/gated action incl. one unresolvable-condition case (fail-open) (RE8, RE10)
- [ ] 7.10 Manual: chained sequence accept → travel → kill → collect → turnin on Human start zone, all transitions complete (RE8)
- [ ] 7.11 Manual: forced death mid-action → FSM recovers, resumes correct action (RE7)
- [ ] 7.12 Manual: forced stuck during nav → FSM enters ghost/recovery, resumes once unstuck (RE7)
- [ ] 7.13 Manual: mid-run client reload → state restored from `<profile>.save.json`, resumes at correct action (RE7)

## Threat Matrix

N/A — no routing/shell/subprocess/VCS classification per design; QueryServer calls are existing read-only HTTP GET.
