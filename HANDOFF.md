# SentinelCore — continuation prompt

Copy everything below the line into a fresh Claude Code session in `/home/levi/Projects/SentinelCore`.

---

You are continuing work on **SentinelCore**, a WoW TBC (2.4.3) questing bot running under the
Project Sylvannas injector. Read `CLAUDE.md` and `sentinel/docs/adr/06_QUESTING_SCHEMA_V2.md`
first — ADR 06 is the agreed architecture and its §10 is the build order.

## Your immediate objective

**Get the bot to kill a single mob.** Everything upstream of the kill is verified working in-game;
the kill loop has never once executed. Do not start new features until a mob dies.

## How to work on this

You have a **live game bridge** (`lx-debug` MCP). The game is running with a level-70 Paladin in
Elwynn Forest. This is the single most important tool available — **verify in-game, do not reason
from the code alone.** Every significant bug this project has hit was invisible offline and only
appeared when run against the real client.

Loop: edit → `luajit sentinel/tests/run_offline.lua` → deploy → ask the user to reload → verify via
`game_eval`.

- Deploy: `cp -r sentinel/. "/mnt/c/Users/Levi/Desktop/8492710429180123131425564324/scripts/sentinel/"`
  then `rm -f .../scripts/sentinel/modules/questing/editor_ui.lua`
- **A Lua-level `_G.Sentinel.reload()` does NOT pick up file changes.** The loader caches its
  script set; the user must reload from the Sylvannas UI. Use `game_wait_reload` to detect it.
- Data (profiles/saves) lives in `scripts_data/`, NOT `scripts/`.

### Bridge gotchas that will waste your time

- `game_eval` **truncates everything after the final closing quote of the last string literal**.
  `return f("x.json")` loses its `)`. Build strings without quotes instead:
  `string.char(101,46,106,115,111,110)` == `"e.json"`.
- Plain tables work where docs show `vec2`/`vec3`: `{x=..,y=..}`.
- `_G.Sentinel.combat()` returns the module **wrapper**; the real `SentinelCombat` is
  `:get_combat()`. Reading `_source`/`_current_target` off the wrapper gives nil and will send you
  down a false trail — this already cost an hour.
- `dbg.quest_log()` can report 0 while quests are genuinely in the log. Truth is
  `core.quests.is_on_quest(id)` and `dbg.quest_status(id)`.

### Session bootstrap (in-game)

```
local q=_G.Sentinel.questing() _G.Q=q return 1
return _G.Q:start(string.char(101,46,106,115,111,110))     -- loads e.json
local ex=_G.Q._executor for i=1,300 do ex:execute() end return ex._current_operation_idx
```

`execute()` polls instantly but the character walks in real time — insert real waits (60–120s)
between batches or you will conclude it is stuck when it is merely walking.

## THE EXACT NEXT BUG (start here)

The Kill action now reaches its target. Verified live, all in one run:

```
operation 16 / action 18 (Kill)
kill trace:      engaging   dist=2.6
target:          Young Wolf (299), 2.6 yd, TARGETED
combat state:    ENGAGING  →  COOLDOWN   (after ticking)
combat _source:  "questing"          ← the questing engage event reaches combat
_current_target: set
_forced_target:  set                 ← neutral-mob override holds
combat enabled:  true
player:          is_auto_attacking = false, is_in_combat = false
```

So: questing finds the mob, targets it, requests engagement, combat accepts the target and runs —
then goes to COOLDOWN having **queued no spell**. Nothing ever swings.

The remaining gate is almost certainly that the rotation/target-strategy path refuses a
**non-hostile** unit. Elwynn's Young Wolves report `enemy = false` and never aggro. Note
`sentinel/tests/modules/combat/test_module.lua` explicitly asserts "combat should not queue spells
for non-hostile direct targets" — that rule is correct for AUTO engagement and wrong for an
explicitly requested quest target. `SentinelCombat:engage` and `_ensure_target` were already taught
to honour `_forced_target`; the spell/rotation path was not.

**A hook already exists — try it before writing new plumbing.**
`grind_target_strategy.lua::is_valid_enemy` (line ~60) reads:

```lua
local attack_neutral = self._blackboard:get("module.grind.attack_neutral") == true
if attack_neutral then return true end   -- players already filtered out above
return is_hostile(player, unit)
```

So setting `module.grind.attack_neutral = true` on the blackboard should make neutral quest mobs
valid targets everywhere the strategy is consulted. Cheapest experiment: set that flag in-game and
re-run the Kill — if the wolf dies, the fix is to set it (scoped to questing engagement, not
globally, so auto-engage behaviour is unchanged) rather than to add a new exemption path.

If that is not sufficient, trace where the rotation validates a target before queueing a spell and
thread the forced-target exemption through. Either way keep the auto-engage guarantee intact —
`sentinel/tests/modules/combat/test_module.lua` asserts combat must not queue spells for
non-hostile *auto*-selected targets, and that test must keep passing.

Secondary, same area: the bot does not close the last few yards as the mob wanders (observed
drifting 2.6 → 6.5 yd). The chase re-issues `move_to` only when the target moves >3 yd from the
last commanded destination; consider tightening that, and note the Kill action owns pursuit —
combat must NOT be made to chase.

## Where the kill loop stands

The route reaches operation 16 (`label:WolfMeatEnd`), whose action 18 is
`Kill{creature_entries=[299,69,704,705], quantity=40}` (wolves for *Wolves Across the Border*).

Just fixed, **not yet verified in-game** — reload and re-test first:
travel was looping `navigated, retry` because the profile re-verified nav's arrival with a 3D
distance check while the inferred destination Z was 8.4 yards wrong. It now trusts nav's own
`arrived`. This was blocking action 2, so the Kill at action 18 was never reached.

`execute_kill` records its branch each tick — read it back with:

```
local ex=_G.Q._executor local t=ex._action_state and ex._action_state._kill_trace
return t and (tostring(t.branch)..[[ dist=]]..tostring(t.dist)) or [[kill not reached]]
```

Branches: `success_count`, `success_killed`, `next_target`, `chasing`, `engaging`.
If you see `engaging` and the mob still does not die, the problem is downstream in the combat
module's rotation, not in questing.

Verified working, do not re-litigate: the shared event bus reaches combat
(`ctx.event_bus == combat._event_bus`), `engage(target,{force=true})` sets `_current_target` and
state `ENGAGING` on a neutral wolf, and `_forced_target` survives `_ensure_target`.

**Architecture:** questing owns movement (it holds the route), combat owns the rotation. Do not
make combat chase — the Kill action's own chase logic does that.

## The Z problem — proper fix, not yet implemented

RestedXP guides carry no Z, so the compiler emits `world_z = 0` and the runtime infers a height.
That inference is the root of several bugs: travel timing out short of its goal, nav pathing to a
point underground, and arrival checks failing on an 8-yard vertical error. The current mitigations
(infer via `core.get_height_for_position`, fall back to the player's Z, and trust nav's `arrived`)
are workarounds.

**SentinelNavServer already answers this authoritatively** — verified live this session:

```
NavigationService:get_height(pos, callback, opts)   →  GET /api/v1/height?map_id&x&y&z  → { height }
NavigationService:get_all_heights(pos, cb, opts)    →  GET /api/v1/heights (multi-layer, z_extent)
```

Reached from Lua as `_G.SentinelNavClient.client.nav_client:get_height(...)`. Measured:
`(x=-8932.539, y=-137.525, z=83.0, map_id=0)` returned **83.29**, against the DB's 83.4 for Deputy
Willem — accurate to ~0.1 yd, and it works for ANY coordinate because the navmesh covers the whole
map, unlike `core.get_height_for_position` which only answers for *loaded* terrain.

Caveat: `z` is a **search hint**. The same query with `z = 0` FAILED. Guide waypoints have
`world_z = 0`, so either pass a plausible hint or use `/api/v1/heights` with a wide `z_extent`.

Recommended: resolve Z **at import time**, not at runtime. NavServer is plain HTTP, so the Rust
importer can batch-resolve all 522 travel waypoints once and bake correct world_z into the profile.
That deletes the entire class of runtime Z bugs and costs nothing per tick. (NavServer runs on the
Windows host; WSL cannot reach its localhost — query it from the game, or use the host IP.)

## Design principles that are settled

- **Reconcile, never count.** Objective progress is derived from observed game state
  (`is_on_quest`, `is_quest_flagged_completed`), never accumulated locally. ADR 06 §8.1.
- **Never claim success without verification.** A handler that returns `"success"` for a no-op is
  the worst failure mode — the bot advances past work it never did. This bug shipped once already
  (`AcceptQuest` reported success while the quest log stayed empty).
- **Refuse to guess.** Enrichment deliberately declines two cases rather than inventing an action:
  `NOT ItemCount(...)` (asserts you hold FEWER than n) and items with no loot row (script-driven).
- **Any enum crossing Rust→Lua must be adjacently tagged** `{type,payload}`; the Lua dispatches on
  `.type`. An externally-tagged `RuntimeCondition` silently made every condition fail open.
- **A mock that agrees with the bug proves nothing.** Several bugs hid behind fixtures written to
  match broken code (JSON parser, `write_data_file` arity, Lua-literal fixtures). When a test
  passes but the game fails, suspect the mock.

## After the kill works

ADR 06 §10 build order. Steps 1–3 are done (coordinates, structured objectives, Level-1
enrichment). Next is **step 4: replace the linear executor with guide-ordered graph traversal**,
then the scheduler phases.

The user's own design request, which is correct and is the graph model's whole point:
*if we are on quest X and travelling, and we pass mobs needed for quest X, kill them en route.*
Caveat: RestedXP routes are hand-tuned to pass through the right camps, so this should be
opportunistic **on the way**, never a detour planner, or it will thrash between camps.

## Known-open issues

- 40 unsatisfiable gates remain (19 `NOT ItemCount`, ~21 script-driven) — deliberate refusals.
- `.train` still has 227 unresolved NPCs corpus-wide; needs trainer-by-class/zone lookup rather
  than name hints.
- `VariableValue` has the same externally-tagged serde issue that broke `RuntimeCondition`. Dormant
  (the importer never emits `SetVariable`), but a trap if variables are ever used.
- Spawn `locations` use the mean of spawn rows; a centroid can land on a cliff. Clustering unproven.
- Recompiling a profile changes its `content_hash` and correctly invalidates saved progress — that
  is a safety property, not a bug.

## Working agreements

- Verify claims before stating them; say you will verify, then check.
- Do not claim something works without running it. Report failures with the actual output.
- Push back with evidence when the user is wrong, and say plainly when they are right.
- Commit with conventional commits, no AI attribution. Explain *why*, with measured numbers.
- Prefer `graphify query` / `codegraph_explore` over raw grep for structural questions.
- Note: raw `rg` output in this repo redacts some identifiers to the literal `n` — confirm ground
  truth by reading files.
