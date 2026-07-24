# SentinelCore — continuation prompt

Copy the **`/goal`** below into the session first, then paste everything under the line as the
opening prompt in a fresh Claude Code session in `/home/levi/Projects/SentinelCore`.

## The /goal

```
/goal SentinelCore's questing bot is production-grade for 1-70 leveling: compiled profiles run
hands-off through full accept → travel → kill → loot → turn-in → vendor/repair cycles, verified
LIVE in-game via the lx-debug bridge (not just offline tests); deaths, stuck navigation, missed
steps, and relogs all self-recover through reconciliation; the cockpit UI is clean, modern, and
shows run health at a glance. Every fix must be proven in the running game before it counts.
```

---

You are continuing work on **SentinelCore**, a WoW TBC (2.4.3) automation stack running under the
Project Sylvannas injector. Lua runs in-game (`sentinel/`); Rust services run outside
(`SentinelQuesting/` importer→validator→compiler pipeline, `SentinelQueryServer/` game-DB API,
`SentinelNavServer/` pathfinding). Guides are compiled to Runtime Profile JSON and only that JSON
executes in-game (**compile-before-execute** — never add reference resolution to Lua).

## Mission

Make questing **fully functional for 1-70 leveling**: a user picks a profile in the cockpit,
presses start, and the bot quests indefinitely without intervention — accepting, traveling,
killing, looting, turning in, choosing rewards, vendoring/repairing, recovering from death and
stuck states, and surviving relogs and character switches. Combat and questing matter most;
UI/UX should be clean and modern but is a runner cockpit, not an editor.

**Definition of done for any change:** offline tests green AND the behavior observed working in
the live game. Code that "should work" does not count — every major bug this project hit was
invisible offline.

## Current verified state (2026-07-24, all live-proven on a Paladin "Nasina")

Working end-to-end, each stage observed in-game:
- **Route reconciliation** (ADR 06 §8.1 "reconcile, don't count"): position derived from
  per-character server quest flags; per-character save files are only a forward hint. Ready
  turn-ins, missed accepts, and unmet farm gates are *certain* verdicts that can rewind the route
  (one-shot per op). Class-guarded actions are excluded per-class.
- **Accept/turn-in**: gossip flow paced at 2s per real attempt ("waiting" between), rewards always
  claimed (guide `.turnin id,slot` choice wins, slot 1 fallback), unseen NPCs reached via static
  spawn positions (profile `npcs` table, then QueryServer `/npc/:entry`).
- **Kill loop**: sticky entry-filtered targets, chase with drift re-issue, corpse looting
  (bounded attempts), engage via forced-target GUID exemption — combat never self-selects
  replacements under `source="questing"` (that caused rabbit/vermin fights and a nav deadlock).
- **Death recovery**: `is_dead_or_ghost` detection, spirit release, real corpse run via
  `core.game_ui.get_corpse_position()`, in-range resurrect.
- **Vendor maintenance** (built + offline-tested, NOT yet live-triggered): bags-full via
  `UI_ERROR_MESSAGE` → detour to nearest visible vendor → sell greys via
  `use_container_item` + QueryServer item quality → `repair_all_items` → resume.
- Suites: `luajit sentinel/tests/run_offline.lua` = **119 passed / 0 failed** (run from repo
  root); Rust workspaces all green.

## Prioritized backlog (work top-down; re-verify live after each)

1. **Watch a full unattended multi-quest chain** (Elwynn profile, ops 15+): quest 15 kill →
   turn-in → follow-up accepts. Fix whatever wedges, using the live-debug workflow below.
2. **Recompile profiles** with the current toolchain (embeds NPC spawns, reward choices, radius→
   tolerance, purges the baked-Z bug bytes): `import-guides` → `sentinel-compile`; compare op
   counts vs deployed before replacing; back up `scripts_data` profiles first.
3. **Vendor maintenance live verification**: force `player.bags_full = true` near Goldshire via
   `game_eval` and watch the detour; verify grey-sell + repair.
4. **Opportunistic kills while traveling** (ADR 06 objective graph, §10 step 4): if a mob needed
   by an active quest crosses the path, kill it between waypoints.
5. **Cockpit UI/UX pass**: `runner_state.lua` (pure view-model, testable) + `runner_ui.lua`
   (thin Sylvannas projection). Health, progress+ETA, blocked reason, maintenance status, quest
   log sync, guardrails. No decision logic in the render layer.
6. **AbandonQuest live verification** and quest-log-full recovery (abandon a non-route quest when
   accepts fail with a full log).
7. **1-70 continuity**: profile chaining when one finishes (next zone), flight paths, hearth,
   Z-resolution at import time via NavServer `/api/v1/height`.

## The live-debug workflow (this is the project's core loop)

You have a **live game bridge** (`lx-debug` MCP). Verify in-game; never reason from code alone.

1. Edit → `luajit sentinel/tests/run_offline.lua` (repo root; expect 119/0).
2. Deploy: `cp -r sentinel/. "/mnt/c/Users/Levi/Desktop/8492710429180123131425564324/scripts/sentinel/"`
   then `rm -f .../scripts/sentinel/modules/questing/editor_ui.lua`.
3. Ask the user to reload the Sylvannas loader UI (a Lua-level `_G.Sentinel.reload()` does NOT
   re-read files). Detect it with `game_wait_reload` (arm it in the background and keep working).
4. Restart the profile via `game_eval` and read the executor's `_execution_log` events, kill
   trace (`_action_state._kill_trace`), nav state, and combat state to confirm behavior.
5. Commit each proven fix (conventional commits, no AI attribution), then `graphify update .`.

Restart snippet (avoids the string-literal truncation bug):
`local q = _G.Sentinel.questing() local p = q:list_profiles() q:start(q._profile_dir .. string.char(47) .. p[1] .. string.char(46,106,115,111,110))`

Services that must be running: QueryServer (`cd SentinelQueryServer && SENTINEL_DB=../tbcmangos.sqlite
cargo run --release`, port 3030 — the game reaches WSL via localhost forwarding) and NavServer
(port 47110, usually Windows-side).

## Tooling contract (use these, in this order)

- **engram MCP**: `mem_context` + `mem_search` at session start — this project's hard-won
  gotchas are stored there. Save every new discovery/bugfix/decision proactively (`mem_save`).
- **codegraph** (`codegraph_explore`): symbol questions — definitions, callers, blast radius.
  Always check blast radius before editing shared symbols.
- **graphify** (`graphify query/explain/path`): architecture/concept/docs questions; run
  `graphify update .` after code changes (no auto-update).
- **context7 MCP**: current docs for any external library/API before using it.
- **lx-debug MCP**: the live game — `game_eval`, `game_wait_reload`, `game_bridge_status`,
  `dbg.*` helpers (`dbg.quest_log()`, `dbg.gossip()`, `dbg.nearby()`).
- Filesystem/standard tools for everything else. Prefer MCP intelligence over raw grep/read.

## Expensive lessons — do not relearn these

- `game_eval` truncates everything after the last string literal's closing quote. Build strings
  with `string.char(...)` (e.g. `string.char(46,106,115,111,110)` == `".json"`).
- `core.http_get` is **async-only** `(url, callback)`; sync calls raise. QueryClient is
  request-and-cache — first call returns `(nil, pending)`, poll next tick.
- Quest-log flags are **numeric**: `is_complete = 1`, and `0` is truthy in Lua. Use
  `quest_flag()`-style normalization (`== true or == 1`).
- Ghost form reports `is_dead() == false` — always use `is_dead_or_ghost`.
- Rewarded quests leave the log — objective gates must first check `is_quest_flagged_completed`.
- RestedXP `.goto zone,x,y[,radius]` has **no Z**; the third numeric is a reach radius. Any
  implausible baked Z (>30yd off player) is re-resolved at runtime.
- The Sylvannas sandbox has no global `JSON`, no usable `load`, no `io`; use `core/JSON`,
  `core.read_data_file`/`write_data_file` (no self; `create_data_file` first).
- `unit:get_class()` returns a numeric class_id; map via `shared/class_names.lua`.
- Rust→Lua enums must be adjacently tagged `{type, payload}`.
- `_G.Sentinel.combat()` is the wrapper; the real module is `:get_combat()`.
- `get_num_bag_slots` returns 0 live; `UI_ERROR_MESSAGE` is the only bags-full signal.
- Gossip is asynchronous — pace interaction attempts on real time, never frame-count retries.
- The object manager only sees draw distance — navigation to NPCs needs static spawn fallbacks.

## Operating rules

- **TDD**: write the failing offline test with the real wire shapes (numeric flags, positional
  payloads) before the fix; mocks must pin live-client behavior, not idealized behavior.
- One fix per commit, message states the live symptom it cures.
- When the user reports a symptom, pull live state FIRST (`game_eval` the executor log, kill
  trace, nav full state, combat state) — diagnose from evidence, then fix, then re-verify.
- Reconciliation invariants: game state is truth; saves only move the route forward; certain
  verdicts (ready turn-in, missed accept, unmet farm gate) may rewind once per op.
- Never claim something works without having watched it work in-game this session.
