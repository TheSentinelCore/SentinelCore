# Tasks: Sentinel Lua Audit Remediation

> Chained-PR delivery. Forward `~/.claude/skills/chained-pr/SKILL.md` to apply/verify.
> Test command: `cd /home/levi/Projects/SentinelCore && luajit sentinel/tests/run_offline.lua`
> (no `lua` binary exists — D6). In-game verification uses `mcp__lx-debug__game_eval`.

## Review Workload Forecast

| Slice | Findings | Est. changed lines | Budget risk | Notes |
|---|---|---|---|---|
| PR1 | B1,F2,F8(order) | 40-60 | Low | pcall isolation + sort fix + order-pin test |
| PR2a | A2,A3,A6,A8 + D1,D2 | 150-200 | Medium | coupled test un-encoding, within budget |
| PR2b | A5 | 150-250 | Medium | 3 new handlers, additive, within budget |
| PR3 | A1,A4,A7,A9,A10,A11,B5 | 220-300 | Medium-High | 7 findings, 2 files + tests; watch closely |
| PR4 | B2,B3,B6,B7,B8,B9 | 200-280 | Medium | B8/B9 folded in (see below) |
| PR5 | B4 | 150-220 | Medium | adapter collapse + owner arbitration + test |
| PR6 | C1,C2,C3 | 100-160 | Low-Medium | + spell-mock coupling (D3 subset) |
| PR7 | C4,C5,E6 | 120-170 | Low-Medium | diagnostics sink + quest-log wiring |
| PR8a | D3 | 150-250 | Medium-High | 714-line mock file, 4 namespaces removed; **sub-split from PR8** |
| PR8b | D4,D5,D6 | 60-100 | Low | unit_helper mock, doc/config fixes |
| PR9a | E1,E2,E5 | 150-350 | **High — unknown file sizes** | whole-file deletions count full diff lines; **sub-split from PR9** |
| PR9b | E3,E4,A12 | 100-160 | Medium | grind-era removal + A12 dead code |
| PR10a | F8(schema),F12,C7 | 100-160 | Low-Medium | |
| PR10b | F1,F3,F4,F6 | 150-250 | Medium | hot-path, needs instrumentation in tests |
| PR10c | F5,F7,F9-F11,C6,C8,C9 | 220-320 | Medium-High | 8 distance sites + 6 more findings |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium (two slices — PR8a, PR9a — flagged High/uncertain; sub-split already applied; re-forecast against real diffs before those two land)

Overall: 15 stacked slices, each independently landable/revertible, sequenced P0 first per the design's PR table. PR8 and PR9 are sub-split beyond the design's 13-slice table because whole-file deletions (E1/E2/E5) and a 714-line mock rewrite (D3) risk exceeding 400 lines undetected until diff time.

## Phase 0: Pre-tasks (must resolve before dependent slices)

- [ ] 0.1 [in-game] `game_eval` check whether `get_ally_list_around` includes the player; resolves B6's outnumbered trigger (2 vs 3 mobs) before finalizing PR4 task 4.6. Design: does not change the fix, only the threshold.
- [ ] 0.2 [in-game or codegraph] Confirm no other consumer depends on the blackboard `questing` top-level root before PR10a narrows the schema (F8 full fix).
- [ ] 0.3 Flag to the human: `openspec/config.yaml` declares `tdd: false` (characterization harness) while the session's Strict-TDD flag is enabled. Unresolved conflict — get explicit human resolution before `sdd-apply` starts PR2b/PR3 (the slices with real new logic where TDD ordering matters most).

## Phase PR1: Tick isolation + registry order (B1, F2, F8-order)

- [ ] 1.1 `runtime/module_registry.lua` `tick_all`: wrap each module's `instance.tick` call in `pcall`; on failure publish `module:fault` with `{module, error}` and continue the loop (B1).
- [ ] 1.2 `runtime/module_registry.lua` `register_all` sort comparator (:150-152): change from descending (`>`) to ascending (`<`) so lower priority number ticks first (F2).
- [ ] 1.3 [offline] `run_offline.lua`: add repro asserting tick order is `combat(10) → questing(50)`, and that combat still ticks when questing's tick throws (B1, F2, F8-order verify).

## Phase PR2a: Questing contract fixes + coupled tests (A2, A3, A6, A8, D1, D2)

- [ ] 2a.1 `modules/questing/runtime_profile.lua:716`: drop the erroneous `core.inventory` self-arg from `get_items_in_bag(bag_id)` call (A2).
- [ ] 2a.2 `tests/run_offline.lua:60`: make the `get_items_in_bag` mock arity-sensitive (bag id selects contents) instead of returning `{}` for any arg — same PR as 2a.1 (D2, coupled).
- [ ] 2a.3 [offline] Assert bag counts reflect the mocked bag id in `run_offline.lua` (A2 verify).
- [ ] 2a.4 `modules/questing/runtime_action.lua:1241`: pass the resolved game object to `core.input.loot_object`, not the raw entry id (A3).
- [ ] 2a.5 `tests/modules/questing/test_runtime_nav.lua:389,396`: un-encode — assert the game object was passed, not entry `1234` — same PR as 2a.4 (D1, coupled).
- [ ] 2a.6 [in-game] `game_eval{ code = "return _G.Sentinel:get_module('questing'):get_view().progress" }` after a loot step; assert progress advanced only after a real loot, not a bare `"success"` (A3 verify).
- [ ] 2a.7 `modules/questing/runtime_action.lua:851-885`: move `attempted = true` inside the actual sell-success guard, not outside it (A6).
- [ ] 2a.8 [in-game] `game_eval` verify vendor stop reports failure when no sell API call succeeded (A6 verify).
- [ ] 2a.9 `modules/questing/module.lua:220-224`: replace non-existent `core.write_file` with documented `write_data_file`; make load failure diagnosable (A8).
- [ ] 2a.10 [in-game] `game_eval{ code = "_G.Sentinel.reload(); return _G.Sentinel:get_module('questing'):get_view().blocked_reason" }` — must be nil after reload (A8 verify).

## Phase PR2b: Real Grind/Escort/Patrol handlers (A5)

- [ ] 2b.1 `modules/questing/runtime_action.lua:1246`: implement `execute_grind` against `RuntimeGrind.targets/polygon/minimum_kills`.
- [ ] 2b.2 `modules/questing/runtime_action.lua:1251`: implement `execute_escort`.
- [ ] 2b.3 `modules/questing/runtime_action.lua:1256`: implement `execute_patrol`.
- [ ] 2b.4 [in-game] `game_eval` verify progress reflects real objective work (kill count / area coverage), not instant success, for grind/escort/patrol (A5 verify).

## Phase PR3: Retry/completion/nav accounting (A1, A4, A7, A9, A10, A11, B5)

- [ ] 3.1 `modules/questing/runtime_profile.lua`: add `_advance_action()` — increments `_current_action_idx`, rolls the operation, resets `_current_action_retries = 0`.
- [ ] 3.2 Replace the three raw advances (:1179, :1202, :1362) with calls to `_advance_action()` (A1).
- [ ] 3.3 [offline] Repro against the proven 4-action case: assert each action gets its own full retry budget after the previous one exhausts (A1 verify).
- [ ] 3.4 `modules/questing/runtime_action.lua:558-559` `execute_kill`: read `RuntimeKill.loot`/`ignore_elites`; skip elites from sticky-target when `ignore_elites=true`, skip post-kill loot when `loot=false` (A4).
- [ ] 3.5 [in-game] `game_eval` verify elite is not selected as sticky target with `ignore_elites=true`, and no loot attempt with `loot=false` (A4 verify).
- [ ] 3.6 `modules/questing/runtime_action.lua:918-923`: use a documented taxi API and resolve `RuntimeFlight.destination` (string) to the matching flight node instead of `destination.index or destination.id or 1` (A7).
- [ ] 3.7 [in-game] `game_eval` verify the correct flight node is selected for a named destination string (A7 verify).
- [ ] 3.8 `modules/questing/runtime_action.lua:815-827`: remove the navigate-to-spawn-area branch gated on `payload.destination`, a field `RuntimeKill` never sets (A9).
- [ ] 3.9 [offline] Assert no reachable branch references a nonexistent `RuntimeKill` field (A9 verify).
- [ ] 3.10 `modules/questing/runtime_profile.lua:464` `is_at_npc`: return `false` when player position is unreadable, not `true` (A10).
- [ ] 3.11 [offline] Assert unreadable-position case routes to `false`/navigation, not "at NPC" (A10 verify).
- [ ] 3.12 `modules/questing/runtime_profile.lua:780` `_get_file_mtime`: use a mechanism that can return non-nil inside the Sylvannas sandbox (A11).
- [ ] 3.13 [offline] Assert the mtime comparison path can produce non-nil (A11 verify).
- [ ] 3.14 `modules/questing/runtime_profile.lua:1248` `_execute_navigating`: require position confirmation before treating client `"idle"` as arrival; re-navigate or time out via `NAV_TIMEOUT` otherwise (B5).
- [ ] 3.15 [offline] Assert idle-without-position-match is not treated as arrival (B5 verify).

## Phase PR4: Combat lifecycle (B2, B3, B6, B7) + folded B8, B9

- [ ] 4.1 `modules/combat/module.lua:61-69`: remove the `tonumber(raw_class) or 8` Mage default; add `_class_confirmed` flag; `initialize()` attempts detection without finalizing on a nil player (B2).
- [ ] 4.2 `modules/combat/module.lua` `update()`: call `_ensure_class()` each tick until a real numeric `class_id` is read, then build the profile once and latch (B2).
- [ ] 4.3 [in-game] `game_eval{ code = "return _G.Sentinel:get_module('combat'):get_combat()._class_name" }` on a non-Mage — must match the real class (B2 verify).
- [ ] 4.4 `modules/questing/runtime_action.lua:799-805` `execute_kill`: publish `combat:engage_requested` only on transition (new target or not-yet-engaged), not every tick (B3).
- [ ] 4.5 `modules/combat/module.lua:404` `engage`: set `combat.leash_center` only on entry from a non-engaged state (B3).
- [ ] 4.6 [in-game] `game_eval` verify `leash_dist` grows with real displacement across two reads, and `disengage("leash_exceeded")` is reachable. Threshold per Phase 0.1 finding (B3 verify).
- [ ] 4.7 `modules/combat/module.lua:369-377`: add backoff/state-change guard so an outnumbered disengage does not re-trigger engage/disengage every frame (B6).
- [ ] 4.8 [in-game] `game_eval` observe no engage/disengage oscillation across multiple frames after an outnumbered pull (B6 verify).
- [ ] 4.9 `runtime/app.lua:47-54` / `modules/combat/module.lua:177-183`: guard `shutdown()` so disengage/nav-stop/`DISENGAGED` publish run exactly once even when called both directly and via `registry:shutdown_all()` (B7).
- [ ] 4.10 [in-game] `game_eval` observe no double-disengage on `_G.Sentinel.reload()` (B7 verify).
- [ ] 4.11 Consolidate the duplicate class-id maps: keep the Title-Case map (`runtime_profile.lua:78-89`, required by `ClassIs`/RestedXP tails) as the single source; have `modules/combat/module.lua:74-79` consume it instead of a second hardcoded copy. **Folded into PR4** (B8).
- [ ] 4.12 [offline] Assert both consumers (combat's `player.class_name` publish and questing's `ClassIs`) resolve from the one map (B8 verify).
- [ ] 4.13 `runtime/sensors/proximity_sensor.lua:52-58`: fix `_frame_count` increment ordering so the first published pass is frame 1, not frame 3 (constructor zeros no longer leak for 2 frames). **Folded into PR4** (B9).
- [ ] 4.14 [offline] Assert the frame-count gate fires on the first tick pass using an injected counter/mock, independent of the real `_unit_helper` value (D4 keeps proximity counts at 0 offline regardless — this test targets only the frame-ordering logic) (B9 verify).

## Phase PR5: Nav ownership (B4)

- [ ] 5.1 `runtime/app.lua:26`, `modules/combat/init.lua:16`, `modules/questing/runtime_profile.lua:108`: collapse the three `NavAdapter:new()` instances into one, constructed in `SentinelApp:new` and threaded into both the combat wrapper and the questing profile.
- [ ] 5.2 `integrations/nav_client/adapter.lua:49-52`: add `_owner`; `move_to(target, opts)` honors `opts.owner` — reject with `false, "owned_by_other"` unless `opts.preempt`.
- [ ] 5.3 Combat chase preempts (`opts.preempt=true`) and calls `release(owner)` on disengage; questing re-issues Travel next tick after release.
- [ ] 5.4 Update `test_nav_adapter.lua` for the single-adapter + ownership contract.
- [ ] 5.5 [in-game] `game_eval` verify combat does not override an in-flight questing Travel; ownership transfers explicitly once questing releases (B4 verify — Exclusive Ownership).
- [ ] 5.6 [in-game] `game_eval` verify a non-owner does not call `stop()` on another owner's motion (B4 verify — Owner-Scoped Stop).

## Phase PR6: Spell-helper convention (C1, C2, C3) + spell-mock coupling (D3 subset)

- [ ] 6.1 `shared/spell_helper.lua:54-67` `call_method`: colon-only — `return pcall(fn, owner, ...)`, drop the plain-call-first branch (C1).
- [ ] 6.2 `tests/harness/mocks/sylvannas_api.lua`: update spell-helper-relevant mocks to accept `self` as the first parameter — same PR as 6.1 (D3 subset, coupled; broader fictional-namespace removal stays in PR8a).
- [ ] 6.3 [offline] Run the full suite; confirm it stays green after the mock convention change (C1 coupling verify).
- [ ] 6.4 [in-game] `game_eval` verify the colon convention is used against the real Sylvannas spellbook API (C1 verify).
- [ ] 6.5 `shared/spell_helper.lua:79-82` `is_spell_castable`: pass `false, false` for `skip_facing, skips_range` (was `true, true`) (C2).
- [ ] 6.6 [in-game] `game_eval` cast a spell out of range/facing away — verify `is_spell_castable` returns false, not fail-open true (C2 verify).
- [ ] 6.7 `shared/spell_helper.lua:77,94`: replace unconditional `return true` fail-open with a result that distinguishes "unknown" from "confirmed castable/in-LOS" (C3).
- [ ] 6.8 [in-game] `game_eval` verify an indeterminate SDK result is not silently treated as castable (C3 verify).

## Phase PR7: EventBus observability (C4, C5, E6)

- [ ] 7.1 `main.lua`: add a diagnostics subscriber for `module:fault` (B1), `questing:profile_load_failed`/`questing:error` (A8), and module shutdown events; log each (C4).
- [ ] 7.2 [offline] Assert a questing tick fault under the isolation guarantee publishes and is observed by the subscriber (C4 verify).
- [ ] 7.3 [offline] Assert a profile reload failure reaches the subscriber and the runner does not stay silently disabled (C4/A8 verify).
- [ ] 7.4 `modules/questing/module.lua:198-199` / `runner_state.lua:195-207`: wire `questing.tracked_quests`/`questing.quest_log` from the data already built in `ctx:_refresh_quest_log` (`runtime_profile.lua:547-567`) (C5).
- [ ] 7.5 [offline] Assert a real tracked-vs-log mismatch reports `ok=false` with the actual missing/mismatched quests (C5 verify).
- [ ] 7.6 `runner_state.lua:33`: remove the dead `EVENT_SEVERITY.operation_advance` (E6).
- [ ] 7.7 [offline] Assert every defined `EVENT_SEVERITY` has at least one `_log_event` call site (E6 verify).

## Phase PR8a: Remove fictional-namespace mocks (D3) — sub-split, budget risk

- [ ] 8a.1 `tests/harness/mocks/sylvannas_api.lua` (714 lines): remove the `core.player.*`, `core.unit.*`, `core.spell.*`, `core.spell_queue.*` mock namespaces that do not exist in Sylvannas (spell-helper subset already handled in PR6).
- [ ] 8a.2 `tests/modules/questing/test_runtime_profile.lua`: update any consumers of the removed fictional namespaces to use real API mocks or documented equivalents.
- [ ] 8a.3 [offline] Run full suite; confirm no test depends on a removed fictional namespace and the suite stays green (D3 verify). If this diff exceeds 400 lines, split further by namespace (e.g., 8a-i `core.player`/`core.unit`, 8a-ii `core.spell`/`core.spell_queue`).

## Phase PR8b: Harness/doc integrity (D4, D5, D6)

- [ ] 8b.1 Add/fix an offline `unit_helper` mock (`common/utility/unit_helper`) so proximity-count-dependent branches are exercisable where feasible offline (D4).
- [ ] 8b.2 [offline] Assert previously-untestable branches (`_check_safety` outnumbered path, `condition_library.lua:49`, `frost_conditions.lua:50,342`, `retribution_conditions.lua:117,155`, `frost_combat_state.lua:182`, `frost_tbc.lua:186`, `context_builder.lua:112`) are now reachable via the mock (D4 verify).
- [ ] 8b.3 `CLAUDE.md` "Known state": correct the stale "31 passed" claim to the actual current count (D5).
- [ ] 8b.4 `openspec/config.yaml` `apply.test_command`/`verify.test_command`: change `"lua sentinel/tests/run_offline.lua"` to `"luajit sentinel/tests/run_offline.lua"` (D6).
- [ ] 8b.5 [offline] Run `luajit sentinel/tests/run_offline.lua` from repo root and confirm it executes and passes (D6 verify).

## Phase PR9a: Delete unused whole files (E1, E2, E5) — sub-split, budget risk

- [ ] 9a.1 Delete `modules/questing/runtime_context.lua` — parallel unused application root, referenced only by tests which use `runtime/runtime_context` (E1).
- [ ] 9a.2 Delete `modules/combat/profile_interface.lua` — required by `registry.lua:1` but never used; registry only checks `.build` (E2).
- [ ] 9a.3 Delete `modules/combat/target_selector.lua` (v1, 179 lines) — unused; `module.lua:7` requires `target_selector_v2` (E5).
- [ ] 9a.4 [offline] Run full suite; confirm no broken `require` after the three deletions (E1,E2,E5 verify). If the combined diff exceeds 400 lines, land each file deletion as its own micro-slice.

## Phase PR9b: Remove grind-era dead code + A12 (E3, E4, A12)

- [ ] 9b.1 Remove `tick_pull`, `get_pull_strategy`, `prepare_rest` and the unused `_aoe_tree` build in `frost_tbc.lua` (E3).
- [ ] 9b.2 `modules/combat/module.lua:104-115`: remove the 12 `module.grind.*` blackboard defaults and the ~60 lines of grind branches behind `enabled == false` in `update()` (E4).
- [ ] 9b.3 `modules/questing/runtime_action.lua:413`: remove the dead `RuntimeAction.is_at_destination_2d` — logic already inlined into `execute_travel:485-487`. **Folded per unscheduled-finding routing** (A12).
- [ ] 9b.4 [offline] Run full suite; confirm green after removals (E3,E4,A12 verify).

## Phase PR10a: Dead-config + schema (F8-schema, F12, C7)

- [ ] 10a.1 `blackboard_schema.lua:12`: narrow the schema to remove the top-level `questing` root, migrating writes to the `module.questing.*` convention (F8 full fix; depends on Phase 0.2 confirmation).
- [ ] 10a.2 [offline] Assert the schema rejects a top-level `questing` write and accepts `module.questing.*` (F8 verify).
- [ ] 10a.3 `modules/combat/module.lua:58-115`: remove/clarify the ~30 inline blackboard defaults, including the 12 already deleted in PR9b for the grind subsystem (F12).
- [ ] 10a.4 `modules/combat/state_machine.lua:19-33` `transition()`: add a legal-transition state table; reject unlisted states (C7).
- [ ] 10a.5 [offline] Assert `transition()` rejects an illegal/typo'd state string (C7 verify).

## Phase PR10b: Hot-path reduction (F1, F3, F4, F6)

- [ ] 10b.1 `main.lua:69-97` `ensure_initialized`: move `clear_module_cache()` so a failed init does not re-require ~50 files every frame (F1).
- [ ] 10b.2 [offline] Assert cache-clear does not repeat on every frame after a single init failure (F1 verify).
- [ ] 10b.3 `modules/questing/runtime_profile.lua:405-771,1431`: reduce `create_context()` per-tick closure rebuilding; avoid the second `_resolve_nav_target` call re-invoking it in the same tick (F3).
- [ ] 10b.4 `runtime_action.lua:57-140,146-209`, `modules/combat/module.lua:246-269`: reduce redundant full `get_all_objects` scans per Kill tick / combat frame (F4).
- [ ] 10b.5 `runtime/callback_bridge.lua:38-47` `publish_engine`: skip building the payload/table allocation when the event has zero subscribers (F6).
- [ ] 10b.6 [offline] Add instrumentation counters in tests asserting reduced scan/publish call counts per tick versus the pre-fix baseline (F1,F3,F4,F6 verify).

## Phase PR10c: Consolidation (F5, F7, F9-F11, C6, C8, C9)

- [ ] 10c.1 Replace the eight hand-rolled 3D distance functions (`runtime_action.lua` ×2, `chase_controller.lua:8`, `context_builder.lua:17`, `combat_helpers.lua`, `pvp_target_selector.lua`, `grind_target_strategy.lua`, `default_target_strategy.lua`) with `Geometry.distance` (`math.huge` sentinel) (F5).
- [ ] 10c.2 [offline] Assert distance calls route through `Geometry.distance` and unmeasurable cases return `math.huge` consistently (F5 verify).
- [ ] 10c.3 Unify the two clocks (`system.now_ms`/`core.game_time()` vs `core.time()`) behind one documented time source used by both combat and `runner_state` (F7).
- [ ] 10c.4 `modules/combat/context_builder.lua:63` vs `chase_controller.lua:51`: fix the dual-writer `combat.target_distance` fallback mismatch (99999 vs no-write) so an acquisition tick doesn't suppress `burst_context` (C6).
- [ ] 10c.5 `core/bt/composites.lua:17-24` `Sequence:tick`: guard or document that `children[1]` must be a condition before re-ticking it as a guard (C8).
- [ ] 10c.6 `shared/aoe_helper.lua:87`: add a `type()` check and `pcall` guard around `core.input.cast_position_spell`, matching comparable call sites (C9).
- [ ] 10c.7 `core/bt/composites.lua:56`: document (and align if warranted) the `Selector`-has-memory vs `PrioritySelector`-no-memory asymmetry so a defensive cooldown under `PrioritySelector` can still fire (F11).
- [ ] 10c.8 [offline] Run full suite; assert consolidated distance/clock/guard behavior across combat and questing call sites (F5,F6,F7,C6,C8,C9,F11 verify).

## Offline vs in-game closability

- **Offline-closable end-to-end** (apply + verify can self-close without a live client): PR1, PR2a (A2/A8 halves; A3/A6 need in-game), PR3, PR7, PR8a, PR8b, PR9a, PR9b, PR10a, PR10b, PR10c.
- **Requires a live client for full closure** (apply lands the fix; verify needs `game_eval`): PR2a (A3, A6, A8 confirmation), PR2b (A5), PR4, PR5, PR6.
- Findings offline-verifiable per design: A1, A2, A9, A10, A11, B1, B5, C4, C5, E*, D2, D5, D6, F2, F8. In-game only: A3, A4, A5, A6, A7, A8, B2, B3, B4, B6, B7, C1, C2, C3, D4.
