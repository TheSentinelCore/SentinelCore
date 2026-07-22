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
| PR2b | LootObject resolution (CL2 only) | PR2b | `cargo test -p sentinel-compiler` | N/A | `lib.rs` LootObject hunk reverts independently |
| PR5 | Class restriction as an action-GUARD field (CL4, REVISED 2026-07-22) | PR5 | `cargo test -p sentinel-compiler` (+ `luajit sentinel/tests/run_offline.lua` if a Lua dispatch change is needed) | TBD — depends on design pass | Not yet designed; placeholder section |
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
| CL4 | Class Restriction Filtering (REVISED 2026-07-22: action-GUARD field, moved to PR5) | compiler-condition-lowering | 8.1–8.4 |
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

- [x] 2.1 RED `SentinelQuesting/importer/tests/importer.rs` + `tests/mapper.rs` + `src/lexer.rs` unit tests: line ending `<< Warrior` (and `Class1/Class2`, `!Class` forms) → `class_restriction = "Warrior"` (IF3) — done in PR1b-ii
- [x] 2.2 GREEN `SentinelQuesting/importer/src/lexer.rs` + `step_builder.rs` + `project_builder.rs` + `SentinelQuesting/shared/src/authoring/action.rs`: add `class_restriction: Option<String>` (serde default), parse `<<` suffix off note/args tail, propagate to actions per-command (IF3) — done in PR1b-ii
- [x] 2.3 RED `SentinelQuesting/importer/tests/mapper.rs`: `#sticky` step → `Operation.sticky = true` (IF4)
- [x] 2.4 GREEN `SentinelQuesting/importer/src/project_builder.rs` + `SentinelQuesting/shared/src/authoring/operation.rs`: add `sticky`/`looping` flags, parse directives (IF4)
- [x] 2.5 RED `SentinelQuesting/importer/tests/mapper.rs`: `#compltewith` → canonical `#completewith` + info diagnostic (IF5)
- [x] 2.6 GREEN `SentinelQuesting/importer/src/lexer.rs`: typo canonicalization table (IF5)
- [x] 2.7 RED `SentinelQuesting/importer/tests/importer.rs` w/ `fixtures/guide_bundle_tbc_slice.lua` (real 2-block excerpt of `The Burning Crusade.lua`) + `src/guide_splitter.rs` unit test: N-header bundle → N `ParsedGuide` outputs (IF6) — done in PR1b-ii; the same test was extended in PR1b-iii to also assert N `Project` outputs end-to-end, closing the IF6 contract fully
- [x] 2.8 GREEN `SentinelQuesting/importer/src/guide_splitter.rs` (`extract_guide_blocks`) + `lib.rs` (`parse_guide_bundle`): outer scan for `RegisterGuide([[...]])` blocks, split before per-guide parsing, one `Project` per guide (IF6) — done in PR1b-ii. Wired into the `import-guides` bin (multi-guide files now produce one `Project` JSON per guide, not one per file) in PR1b-iii, including the bundle line-offset fix (`GuideBlock.line_offset` makes `Header.line`/`Command.line`/etc. bundle-file-absolute, previously block-relative and dormant) and block-boundary hardening (`GuideBlockError::{UnterminatedBlock,NestedOpenBeforeClose}` — a missing `]])` close or a block-merge no longer silently drops/merges content, the scan recovers and reports instead)
- [x] 2.9 RED `SentinelQuesting/importer/tests/mapper.rs`: `.equip`/`.skill` → typed inert action + diagnostic naming command/args (IF7) — done in PR1b-ii
- [x] 2.10 GREEN `SentinelQuesting/importer/src/project_builder.rs` (`inert_preserved_action` helper, wired into `waypoint`/`skill`/`equip`/catch-all arms): never-drop fallback to typed inert annotation with `COMMAND_PRESERVED_INERT` diagnostic (IF7) — done in PR1b-ii. `label_graph.rs` needed no change (already per-guide, unaffected by never-drop). `abandon`/`fp` malformed-arg edge cases still silently drop (pre-existing gap, out of this slice's RED scope)
- [x] 2.11 GREEN `SentinelQuesting/importer/src/coverage.rs` (new): `CoverageReport`/`CommandTally` — per-command typed/inert-preserved/unresolved tally, JSON + `text_summary()` (design Decision 6), unit-tested with hand-built fixture Projects (IF7, feeds CL5) — done in PR1b-iii. Not yet wired into the `import-guides` bin's own output (emitting the report alongside regenerated projects is PR3 task 5.4, over the live-QueryServer corpus)

### PR1b-iii Follow-ups (F9 review-debt cleanup unit — closed before PR2a)

- [x] F9.1 `abandon` malformed-arg branch in `project_builder.rs` (`build_step_actions`) no longer drops the action silently: missing/unparseable quest id now falls back to a diagnostic-carrying inert Comment (`MALFORMED_ABANDON_ARGS`), matching the `MALFORMED_GATING_ARGS` convention. `fp` was re-audited and confirmed already never-drop-safe (no args to malform; pinning regression test added, no production change needed).
- [x] F9.2 `coverage.rs` `from_projects` aggregation test gap closed: new test asserts the SAME command name (`accept`) appearing in two different projects of a corpus accumulates its tally (1 + 2 = 3) rather than being overwritten by the later project — regression net for the `entry(name).or_default()` accumulation path.
- [x] F9.3 `coverage.rs` `typed_command_name` catch-all killed: all 22 `ActionPayload` variants (everything but `Comment`, handled separately by `classify`) now map to a distinct, compile-checked exhaustive match arm — a new variant fails the build until it's given its own bucket name, instead of silently landing in a shared `"typed"` bucket.
- [x] F9.4 Path traversal sanitization in `import-guides.rs`: a candidate filename stem (from a guide's `#name` header) is now sanitized (`sanitize_filename_stem`) before being joined to `output_dir` — path separators and `..` sequences are replaced, leading dots stripped — so a malicious/malformed header can never write outside `output_dir`.
- [x] F9.5 File-level read isolation in `import-guides.rs`: the per-file import loop was extracted into `run_import`, which now catches a file-level failure (missing/unreadable guide file) as a recorded failure instead of propagating via `?` and aborting the whole run — later files in the batch are still processed and the final summary still prints.
- [x] F9.6 Cross-invocation overwrite guard in `import-guides.rs`: `run_import` now seeds `used_filenames` from every `.json` stem already present in `output_dir` (`seed_used_filenames_from_existing_output`) at startup, so re-running the importer against the same output directory disambiguates (`Foo-2.json`) instead of silently overwriting a prior run's output.

### PR1a Review Follow-ups (all completed in PR1b)

- [x] F1 Lexer root cause: strip inline `--` dev comments at lex time (`lexer.rs::lex_command`); removed the redundant defensive `strip_inline_comment` layers in `project_builder.rs`
- [x] F2 `UNMAPPED_GOTO_ZONE` diagnostic when `zone_to_map_id` returns `None` instead of a silent map-0 default, + test
- [x] F3 `MALFORMED_GATING_ARGS` diagnostics now populate `entity`/`action` locators (step index + action id), matching the `UNRESOLVED_NPC`/`UNRESOLVED_QUEST` convention, + test
- [x] F4 Fixed `item_count_dsl` doc comment: only `>` and `<=` use arithmetic (`checked_add`); `>=` and `<` are direct mappings
- [x] F5 Single source of truth for the seven gating command names (`GATING_COMMANDS` const, shared by `build_step_actions`'s routing and `gating_condition_dsl`'s dispatch)
- [x] F6 Removed the double `strip_inline_comment` (dead defensive layer) — subsumed by F1
- [x] F7 Operator-whitespace tolerance: `.itemcount 100,< 5` (space between operator and digits) now parses correctly, + test
- [x] F8 (PR1b-ii) Regression test pinning current early mid-line `--` behavior (`.goto Zone--Name,1.0,2.0 -- note` truncates at the first `--`, dropping subsequent comma args too) — zero corpus matches for this shape; test documents intent explicitly so a future corpus hit is a conscious decision

## PR2a: Compiler — Condition DSL Parser

- [x] 3.1 RED `SentinelQuesting/compiler/tests/compiler.rs`: `QuestCompleted(1234)` DSL → `RuntimeCondition::QuestCompleted(1234)`; unmappable expr → diagnostic, no `AlwaysTrue` (CL1)
- [x] 3.2 GREEN `SentinelQuesting/compiler/src/condition.rs` (new): parse `&&`/`||`/`NOT`/parens per design mapping table into `condition.rs:9-27` variants (CL1)
- [x] 3.3 GREEN `SentinelQuesting/compiler/src/lib.rs:160`: remove `RuntimeCondition::AlwaysTrue` shortcut, call new parser, wire unmapped-expr diagnostics (CL1) — `Compiler::compile` now returns `(RuntimeProfile, CompileReport)`; `CompileReport.unmapped_conditions: Vec<Diagnostic>` is the diagnostics vehicle PR2b (task 4.4) extends with `class_excluded`/`unresolved`. Post-4R-review CRITICAL fixes (size:exception approved): (1) `condition.rs` recursive descent had no depth bound (network-reachable stack-overflow DoS via editor `/compile`) — added `MAX_CONDITION_DEPTH`/`MAX_CONDITION_TOKENS` guards; (2) `editor/src/lib.rs::compile_project_inner` now merges `CompileReport.unmapped_conditions` into `CompileResult.diagnostics` (appended to `project.diagnostics`, not replacing it) so `UNMAPPED_CONDITION` reaches the editor `/compile` response — this task's editor-side plumbing is now genuinely complete

## PR2b: Compiler — LootObject Resolution (CL2 only; REVISED 2026-07-22 — class filtering split out to PR5, see below)

- [x] 4.1 RED `SentinelQuesting/compiler/tests/compiler.rs`: resolvable `LootObject` → real `object_entry`; unresolvable → diagnostic, not `0` (CL2)
- [x] 4.2 GREEN `SentinelQuesting/compiler/src/lib.rs`: resolve via `project.object_library` (uuid→entry map, mirrors the NPC-resolution path) instead of `object_entry: 0`; unresolved → `UNRESOLVED_OBJECT` diagnostic + `CompileReport.unresolved` tally, falls back to `0` (never a guessed entry) (CL2)
- [ ] 4.3–4.5 MOVED to PR5 (see below) — do not implement here.

## PR5: Compiler — Class Restriction as an Action-GUARD Field (CL4, maintainer decision 2026-07-22)

Maintainer decision (2026-07-22, superseding the ClassIs-into-Condition-payload approach explored during PR2b apply): class gating is represented as a dedicated action-level GUARD field, not lowered into the `Condition` action's `RuntimeCondition` payload. `Action.class_restriction` remains UNCONSUMED by the compiler until this slice. Design/task details (guard field shape on `RuntimeAction`/`RuntimeOperation`, and any required `sentinel/modules/questing/runtime_action.lua` dispatch change) TBD — this section is a placeholder pending a design pass; do not start implementation from the bullets below without a fresh design review.

- [ ] 8.1 Design: action-GUARD field representation for `class_restriction` (where it lives on `RuntimeAction`/`RuntimeOperation`, how the Lua runtime evaluates it) (CL4)
- [ ] 8.2 RED tests for the guard representation (CL4)
- [ ] 8.3 GREEN compiler lowering (CL4)
- [ ] 8.4 If required: `sentinel/modules/questing/runtime_action.lua` dispatch change to honor the guard (CL4) — out of scope for any Lua-frozen batch; needs explicit unblocking.

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
