# Design: Sentinel Lua Audit Remediation

## Technical Approach

Remediate the findings register (A1..F12) as 10 chained PRs, P0 first, each independently
landable and revertible. Every change is the **smallest correct edit** at the register's
`file:line`, made against the current on-disk source (verified via CodeGraph). Behavior fixes
that a green test currently contradicts ship **with** the test un-encoding in the same PR
(D1↔A3, D2↔A2). Findings that only the injector can exercise (helpers nil offline) carry an
explicit in-game `game_eval` verification shape instead of an offline assertion.

Scope guard: no edits to `Emulators/`, the Rust trees, REFUTED items, or the 34 unaudited files.
Lua consumes Rust contract fields but is fixed Lua-side only (A4, A7).

## Architecture Decisions

### D-B1: Per-module tick isolation + ascending priority (PR1 — B1, F2, F8)

**Choice**: Wrap each module's `tick` in its own `pcall` inside
`ModuleRegistry:tick_all` (module_registry.lua:223-236); on failure publish `module:fault`
and continue the loop. Fix the comparator at :150-152 from descending (`>`) to ascending
(`<`) so **lower priority number ticks first** — combat(10) before questing(50).

```lua
-- register_all sort (corrected)
table.sort(sorted, function(a, b)
  return (a.config.configuration.priority or 0) < (b.config.configuration.priority or 0)
end)
-- tick_all body (isolated)
local ok, err = pcall(instance.tick, instance, delta)
if not ok then self._event_bus:publish("module:fault", { module = name, error = err }) end
```

**Alternatives**: (a) rely on the single `ErrorBoundary:wrap` around the whole loop
(app.lua:86) — rejected: it catches and returns, aborting the rest of the loop, which is the
proven B1 defect. (b) narrow `blackboard_schema.lua` to forbid the `questing` root (F8) as the
primary fix — rejected for PR1: a wide cross-cutting move of `questing.*` → `module.questing.*`
touches many files; deferred to PR10. The per-module pcall neutralizes the schema-throw lethality
regardless.

**Rationale**: Survival (combat) must tick even when questing throws; isolation makes the throw
local, ascending order guarantees combat runs first. F8 here is limited to a test that **pins tick
order** (`combat` before `questing`) so the ordering can never silently regress.

Faulting-frame sequence:

```
on_update ──> registry:tick_all(delta)
                 │  sorted ascending: [combat(10), questing(50)]
                 ├─ pcall(combat.tick)   ──> OK      (survival runs)
                 └─ pcall(questing.tick) ──> THROW   (Blackboard:set on bad root)
                        │
                        └─ caught → publish "module:fault" → loop continues → next frame
   Result: combat ticked; questing fault surfaced; run survives.
```

### D-B2: Deferred class latch (PR4 — B2)

**Choice**: Remove the `tonumber(raw_class) or 8` Mage default at module.lua:61-69. Add a
`_class_confirmed` flag; `initialize()` attempts detection but does **not** finalize on a nil
player. `update()` calls `_ensure_class()` each tick until a real `get_local_player()` yields a
numeric class_id, then builds the profile once and latches.

**Alternatives**: keep one-shot init but retry the whole `initialize()` — rejected: `initialize`
has other one-time side effects (blackboard seeding) that must not re-run.

**Rationale**: An unready player object during a loading screen must never latch a wrong class for
the session. Offline harness supplies a player mock, so `_ensure_class` confirms on frame 1 — no
regression. Until confirmed, the rotation tree is skipped (no cast), not defaulted.

### D-B4: Single shared NavAdapter with owner arbitration (PR5 — B4; interacts with PR4 B3)

**Choice**: Collapse the three `NavAdapter:new()` instances (app.lua:26, combat/init.lua:16,
runtime_profile.lua:108) to **one** adapter constructed in `SentinelApp:new` and threaded into
both the combat wrapper and the questing profile. Add `_owner` to the adapter; `move_to(target,
opts)` honors `opts.owner`: if owned by another and active, reject with `false, "owned_by_other"`
unless `opts.preempt`. Combat chase preempts (survival > travel) and `release(owner)` on
disengage; questing re-issues Travel next tick.

**Alternatives**: (a) enforce `nav.owner` in each of three adapters via a blackboard key —
rejected: three private `_active` beliefs still desync (a `poll` on one never updates the others),
which is B4's actual defect; only chase_controller ever writes `nav.owner` today. (b) leave three
adapters, add owner reads to questing — rejected: same divergent-state hazard remains.

**Rationale**: One adapter = one `_active` source of truth and one `_owner` arbiter, replacing a
fragile convention only one caller respected. Cost: thread the instance through two constructors +
update `test_nav_adapter.lua`. Blast radius (CodeGraph): 6 `move_to` callers across
chase_controller, runtime_profile, runtime_action — all reachable and covered.

Nav-ownership handoff:

```
questing Travel: nav:move_to(dest,{owner="questing"})   ── _owner="questing", moving
   │
combat engages (mob in range)
   └─ chase: nav:move_to(mob,{owner="combat",preempt=true})
             _owner="combat" (survival preempts); questing Travel yields
   ... combat kills, disengages
        └─ nav:release("combat")  ─> _owner=nil
questing next tick: nav:move_to(dest,{owner="questing"})  ── resumes Travel
```

### D-B3: Engage dedup + anchored leash (PR4 — B3)

**Choice**: In `execute_kill` (runtime_action.lua:799-805) publish `combat:engage_requested`
only on transition (new target or not-yet-engaged), not every tick. In `engage`
(combat/module.lua:404) set `combat.leash_center` **only on entry** from a non-engaged state
(`if state ~= ENGAGED`), not unconditionally.

**Rationale**: Anchoring the leash center at engage start lets `leash_dist` accumulate as the
player chases, making `disengage("leash_exceeded")` reachable — the only runaway-chase boundary.
Dedup stops the per-frame re-engage that also drives B6 oscillation.

### D-A1: Centralized action advancement resets retries (PR3 — A1)

**Choice**: Introduce `RuntimeProfile:_advance_action()` that increments
`_current_action_idx`, rolls over the operation, **and sets `_current_action_retries = 0`**.
Replace the three raw advances (runtime_profile.lua:1179, :1202, :1362) with calls to it. Reset
already occurs on success (:1103) and operation change (:1053); this closes the retry-exhausted,
failed, and no-nav-target branches.

Retry-budget flow (against the PROVEN 4-action repro):

```
action1: retry×5 → exhausted → _advance_action() → idx=2, retries:=0   (was: retries kept)
action2: retry×5 → exhausted → _advance_action() → idx=3, retries:=0   (was: 1 attempt→fail)
action3: retry×5 → ... each action gets its own full MAX_RETRIES budget
   _consecutive_failures no longer hits 3 by tick 7; one flaky action ≠ dead operation
```

### D-C1/C2: Colon-only call convention + real castability params (PR6 — C1, C2, C3)

**Choice**: `SpellHelper.call_method` (spell_helper.lua:54-67) becomes colon-only:
`return pcall(fn, owner, ...)` — drop the plain-call-first branch. `is_spell_castable`
(:79-82) passes `false, false` for `skip_facing, skips_range` (was `true, true`).

**Coupling (mandatory, same PR)**: colon-only calls break any mock that omits `self`. PR6 MUST
update the spell-helper mocks in `tests/harness/mocks/sylvannas_api.lua` to accept `self` as the
first parameter, or the offline suite breaks. Only the spell-helper-relevant mock edits move into
PR6; the broader fictional-namespace removal (D3) and unit_helper (D4) stay in PR8.

**Rationale**: Every Sylvannas source uses the colon form; plain-first shifts args and returns a
wrong-but-`pcall`-succeeded answer as authoritative (fail-closed correctness). C3's fail-open
returns are unchanged in code but now honestly documented as offline-only paths.

### D-C4/C5: Diagnostics sink + quest-log producers (PR7 — C4, C5, E6)

**Choice**: Add a diagnostics subscriber in `main.lua` that listens to the orphaned events the
P0 fixes now emit — `module:fault` (B1), `questing:profile_load_failed` (A8), module shutdown —
and logs them. Wire `questing.tracked_quests` / `questing.quest_log` producers
(module.lua:198-199 → runner_state.lua:195-207) from the data already built in
`ctx:_refresh_quest_log` (runtime_profile.lua:547-567). Remove the dead
`EVENT_SEVERITY.operation_advance` (E6).

**Rationale**: Three P0s currently publish diagnostics into the void; a single sink makes silent
failures observable. The desync panel gets real data instead of unconditional `ok=true`.

## Coupled test↔behavior edits (must ship together)

| Behavior fix | Test that encodes the bug | Same-PR edit |
|---|---|---|
| A3 `loot_object` passes object (PR2) | D1 `test_runtime_nav.lua:389,396` asserts entry `1234` | Assert the game object was passed, not the entry id |
| A2 drop `self` from `get_items_in_bag` (PR2) | D2 `run_offline.lua:60` returns `{}` for any arg | Make the mock arity-sensitive so bag id selects contents |
| C1/C2 colon-only (PR6) | spell mocks omit `self` (D3 subset) | Update spell-helper mocks to colon convention |

## Per-PR structure, findings, and verification

| PR | Findings | Smallest change (symbol/file) | Verify |
|----|----------|-------------------------------|--------|
| 1 | B1,F2,F8 | `tick_all` per-module pcall; `register_all` sort `<`; order-pinning test | offline repro: `tick order combat→questing`, fault isolates |
| 2 | A2,A3,A5,A6,A8 + D1,D2 | drop self (`:716`); `loot_object`/`sell_greys`/`write_data_file` object+API fixes; implement grind/escort/patrol (`:1246-1256`); +D1,D2 | offline (A2,D1,D2) + in-game (A3,A5,A6,A8) |
| 3 | A1,A4,A7,A9,A10,A11,B5 | `_advance_action()` helper; read `loot`/`ignore_elites`; `RuntimeFlight.destination` string; `is_at_npc` pos-check; nav idle pos-check | offline repro (A1,B5) + in-game (A4,A7) |
| 4 | B2,B3,B6,B7 | deferred class latch; engage dedup + anchored leash; B6 backoff; B7 double-shutdown guard | in-game |
| 5 | B4 | single shared NavAdapter + owner arbitration; +`test_nav_adapter` | in-game |
| 6 | C1,C2,C3 | colon-only `call_method`; `false,false`; spell mock coupling | in-game + offline (mocks) |
| 7 | C4,C5,E6 | diagnostics sink; quest-log producers; drop dead severity | offline |
| 8 | D3,D4,D5,D6 | remove fictional namespaces; unit_helper mock; fix count/`luajit` cmd | offline |
| 9 | E1-E5 | delete dead roots/interfaces/selectors | offline (suite still green) |
| 10 | C6-C9,F1,F3-F7,F9-F12 | schema narrow (F8 root), clock unify, distance consolidation, scan reduction, state-table guard | offline |

### In-game `game_eval` verification shapes (helpers nil offline)

- **A3/A4/A5/A6/A7**: after a step runs,
  `mcp__lx-debug__game_eval{ code = "return _G.Sentinel:get_module('questing'):get_view().progress" }`
  and assert the objective advanced only after real work (loot count / kill count changed), not on a bare `"success"`.
- **A8**: `game_eval{ code = "_G.Sentinel.reload(); return _G.Sentinel:get_module('questing'):get_view().blocked_reason" }` — must be nil (profile reloaded), not "profile load failed".
- **B2**: `game_eval{ code = "return _G.Sentinel:get_module('combat'):get_combat()._class_name" }` on a non-Mage — must match the real class, never "Mage" from a loading-screen init.
- **B3**: `game_eval{ code = "return _G.Sentinel:get_blackboard():get('combat.leash_center')" }` twice while chasing — center must stay fixed, `leash_dist` must grow.
- **B4**: `game_eval` reading `nav.owner`/adapter `_owner` during a Travel+chase overlap — combat must preempt then release; questing must resume.
- **B6/B7**: observe no engage/disengage oscillation and no double-disengage on `reload()`.
- **C1/C2/C3**: `game_eval` casting a spell out of range/facing away — `is_spell_castable` must return false (not fail-open true).
- **D4**: `game_eval` reading proximity counts (`_unit_helper` present) to confirm `_check_safety` outnumbered path fires.

Offline-verifiable (assert in `run_offline.lua`): A1, A2, A9, A10, A11, B1, B5, C4, C5, E*, D2, D5, D6, F2, F8.

## Review budget (400 lines/PR)

- **PR2** and **PR10** are the two at risk of exceeding 400.
  - **PR2**: A5 implements three real handlers (grind/escort/patrol) = new logic. Sub-split
    proposed: **PR2a** = A2,A3,A6,A8 contract fixes + D1,D2 (small, coupled); **PR2b** = A5
    handler implementations (larger, additive).
  - **PR10**: architecture debt spans ~12 findings. Sub-split by theme: **10a** dead-config +
    schema (F8,F12,C7), **10b** hot-path (F1,F3,F4,F6), **10c** consolidation (F5,F7,F9-F11,C6,C8,C9).
- PR1, 3, 4, 5, 6, 7, 8, 9 each fit within budget.

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary. All changes are in-process Lua behavior; nav "ownership" is an
in-memory arbiter, not OS process integration.

## Migration / Rollout

No migration. Each PR is one revertible slice targeting the prior slice's branch. Coupled
behavior+test PRs (PR2, PR6) revert as a unit so the suite stays internally consistent.

## Open Questions

- [ ] B6: whether `get_ally_list_around` includes the player (shifts the outnumbered trigger from
  2→3 mobs). Does not change the design — backoff still required; confirm in-game (PR4).
- [ ] F8 final placement: schema narrowing lands in PR10; PR1 relies on pcall isolation to
  neutralize the throw. Confirm no other consumer depends on the `questing` root before narrowing.
