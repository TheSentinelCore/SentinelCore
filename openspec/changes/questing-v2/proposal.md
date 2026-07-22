# Proposal: Questing v2 — Import Fidelity, Real Compilation, Runtime Repair

**Change**: questing-v2 | **Date**: 2026-07-22 | **Store**: hybrid (openspec + engram)

## Intent

The compile-before-execute architecture is sound; the product is broken by **import fidelity**, not design. The importer discards `.goto` coordinates and downgrades completion/gating commands to inert Comments; the compiler shortcuts all conditions to `AlwaysTrue`; sample projects were imported against an empty offline client (Elwynn: 777 Comments, 0 AcceptQuest); and the Lua runtime has payload/wiring bugs that mean the module never actually runs a compiled profile. No executable RuntimeProfile exists anywhere. This change makes guides import faithfully, compile into real typed conditions, and execute in-game per action type.

## Scope

### In Scope
- **P0 Import fidelity** (`importer/`): preserve `.goto` coordinates (fix project_builder.rs:327-345); lower leveling-core gating/completion commands (`.complete`, `.collect`, `.itemcount`, `.isOnQuest`, `.isQuestComplete`, `.isQuestTurnedIn`, `.isQuestAvailable`) into typed conditions; parse per-line `<< Class` suffixes; honor `#sticky`/`#loop`; typo-tolerant directive parsing (`#compltewith`, `#requries`, `#lable`); multi-guide bundle splitting. **Policy**: leveling-core commands get semantic lowering; every other command/directive MUST be parsed, typed, and preserved inert with a diagnostic — never silently dropped as a bare Comment.
- **P0 Compiler** (`compiler/src/lib.rs`): remove the `AlwaysTrue` shortcut (157-161), lower conditions for real; fix `LootObject` `object_entry:0`.
- **P0 Re-import**: run the pipeline against a live QueryServer so NPC/quest libraries resolve.
- **P1 Runtime repair** (`sentinel/modules/questing/`): fix 4 payload field mismatches vs `runtime/action.rs` (reward_choice/choose_reward; flight destination string-vs-table; vendor buy_items Vec<u32>-vs-objects; nonexistent kill.destination); wire ModuleRegistry → `QuestingModule:initialize`; use shared EventBus/Blackboard; kill per-tick `create_context` allocation; bound `_execution_log` in saves; fix ghost-recovery throttle no-op; make the test-harness JSON mock round-trippable.

### Out of Scope (named follow-ups)
In-game loader/HUD UI; QueryServer item/spell + taxi endpoints (flight destinations stay empty); `browser-editor-ui` (separate change); **full unattended zone-run milestone**; combat module test failures.

## Fidelity Spec (locked)

Coverage bar is `sentinel/docs/adr/restedxp guides/The Burning Crusade.lua` — a 154k-line bundle of ~250 sub-guides, ~70 distinct `.commands`, ~45 `#directives`, including source typos (`#compltewith`, `#requries`, `#lable`) the importer MUST tolerate. NOT just Human 1-11.

## Capabilities

### New Capabilities
- `import-fidelity`: faithful RestedXP command/directive coverage — coordinate preservation, typed condition lowering, class suffixes, sticky/loop, typo tolerance, bundle splitting, never-drop policy.
- `compiler-condition-lowering`: real Project→RuntimeProfile condition lowering (no `AlwaysTrue`), reference resolution, `LootObject` entry fix.
- `questing-runtime-execution`: per-action-type in-game execution and recovery FSM over a compiled profile.

### Modified Capabilities
None — `openspec/specs/` is empty; no existing requirement text changes.

## Approach

Reference resolution stays in the compiler; the Lua runtime consumes only resolved entry IDs and coordinates. Import → typed conditions → real compile → runtime repair, verified against a **startable Human starting zone on the tbcmangos DB** even though the fidelity spec is the TBC bundle. Sylvannas constraints hold: `core.*` only, async callback HTTP (GET+POST exist), no first-party JSON lib, file IO via `core.read/write_data_file`; Rust never calls the game, Lua never compiles/validates.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `SentinelQuesting/importer/src/project_builder.rs` | Modified | preserve `.goto` coords; lower gating commands |
| `SentinelQuesting/importer/src/` (lexer, splitter, builders) | Modified | class suffix, sticky/loop, typo tolerance, bundle split, never-drop |
| `SentinelQuesting/compiler/src/lib.rs` | Modified | remove `AlwaysTrue`; real conditions; LootObject fix |
| `sentinel/modules/questing/*` (module, runtime_profile, runtime_action) | Modified | payload fixes, registry init, shared bus, perf, save bounding |
| `SentinelQuesting/.questing/projects/` | Regenerated | re-import against live QueryServer |
| test harnesses (Rust + `run_offline.lua`) | Modified | round-trippable JSON mock |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Unknown-condition semantics undecided (fail-open vs fail-closed) | High | Carried as OPEN DECISION into spec; recommend fail-open on optional gates, never stall main line |
| Live QueryServer resolution still incomplete (items/taxi absent) | High | Preserve inert with diagnostics; those actions are named follow-ups |
| Import never-drop policy inflates diagnostics noise | Med | Type + preserve, don't spam; diagnostics grouped by command |
| Runtime repair regresses persistence test | Med | Fix JSON mock round-trip first; strict TDD |
| 400-line review budget exceeded | High | Chain PRs by P0-import / P0-compiler / re-import / P1-runtime slices |

## Open Decision (do not resolve here)

Unknown-condition semantics: ticket 017 made it fail-closed; compliance audit L01 demands fail-open. Recommendation to carry into spec: **fail-open on optional gates, never allow the main line to stall.** Record; resolve in spec/design.

## Rollback Plan

Importer/compiler changes are additive to the pipeline — revert per slice via git; regenerate project JSONs by re-running `import-guides`. Runtime repair reverts independently; on-disk profiles are untouched by rollback. No schema migration.

## Dependencies

- Live SentinelQueryServer (`SENTINEL_DB=tbcmangos.sqlite` on :3030) for re-import resolution.
- `import-guides` toolchain; shared `runtime/action.rs` payload contract as the field-name source of truth.

## Success Criteria (Definition of Done — option (b), per-action capability)

- [ ] **Every runtime action type the compiler emits is demonstrated working in-game** in short targeted scenarios.
- [ ] Recovery FSM verified: **forced death, forced stuck, reload mid-run.**
- [ ] A full unattended zone run is explicitly a **named follow-up milestone**, NOT a gate for this change.
- [ ] `The Burning Crusade.lua` imports with typed/preserved coverage of ~70 commands / ~45 directives (typos tolerated), zero silent Comment drops of leveling-core commands.
- [ ] Compiler emits real conditions (no `AlwaysTrue`), resolved coordinates and entries; re-import against live QueryServer resolves NPC/quest libraries.
- [ ] `luajit sentinel/tests/run_offline.lua` green for questing suites (round-trippable JSON mock).

## Delivery Strategy (chained PRs — 400-line budget risk: High)

1. **PR1 — Import fidelity** (coords, typed conditions, suffixes, sticky/loop, typo tolerance, never-drop, bundle split).
2. **PR2 — Compiler lowering** (remove AlwaysTrue, real conditions, LootObject fix).
3. **PR3 — Re-import** against live QueryServer (regenerated project JSONs + verification).
4. **PR4 — Runtime repair** (payload fixes, registry init, shared bus, perf, save bounding, JSON mock).

## Proposal Question Round (resolved 2026-07-22)

1. **Never-drop policy**: diagnostics only — the ~25 non-leveling-core commands are parsed, typed, and preserved inert with per-command diagnostics; no additional semantic lowering in this change.
2. **Re-import scope**: regenerate ALL sample projects against the live QueryServer; regenerated JSON is treated as golden artifacts and provides corpus-wide coverage statistics against the fidelity bar.
3. **Runtime verification breadth**: per-action-type scenarios PLUS one short chained sequence (accept → travel → kill → collect → turnin) to catch transition bugs.
