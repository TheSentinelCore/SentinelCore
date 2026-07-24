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

## State (2026-07-24)

Suites: `luajit sentinel/tests/run_offline.lua` = **127 passed / 0 failed** (repo root); all Rust
workspaces green. **Read the discipline line at the top of "Mission" before trusting anything
below as done** — offline-green ≠ working.

### Live-proven earlier this session (Paladin "Nasina", observed in-game)
- **Route reconciliation** (ADR 06 §8.1 "reconcile, don't count"): position from per-character
  server quest flags; saves are only a forward hint; ready turn-ins / missed accepts / unmet farm
  gates are *certain* verdicts that rewind once per op. Class-guarded actions excluded per-class.
- **Accept/turn-in** (gossip paced 2s/attempt, rewards claimed, unseen NPCs via static spawns),
  **kill loop** (sticky entry-filtered targets, forced-target GUID exemption — combat never
  self-selects under `source="questing"`), **death recovery** (`is_dead_or_ghost`, corpse run).
- **Mid-farm completion-gate skip**: re-checked every tick, so a cold `is_quest_flagged_completed`
  at op entry can't commit the bot to re-farming a rewarded quest (was live-caught re-killing 40
  wolves).

### Built + offline-green + DEPLOYED, but NOT LIVE-VERIFIED (this session's big push)
Everything here is committed and deployed to `scripts_data` but has **never run in-game** — the
next session's entire job is to live-verify it. The game client was down at end of session (bridge
frozen), so zero live verification happened.
- **1-70 profile chain**: `build_chain_manifest.py` derives `chain.json` from RestedXP `#next`;
  `profile_chain.lua` resolves the next profile per class; `module.lua` `_advance_to_next_profile`
  starts it on `finished`. Deployed: **36-profile Paladin chain 1-11-Elwynn-Forest →
  69-70-Shadowmoon**, all hop files present, 17 level gates live. Build chain from **per-guide
  imports** (each dir `rm -rf`'d first) — a full batch import into a dirty dir leaves stale base
  files (see below).
- **`.xp` level gates**: importer lowers `.xp N` / `N+M` → `LevelAtLeast(N)` Completion condition
  (wire `{"condition":{"type":"LevelAtLeast","payload":N},"role":"Completion"}`); runtime holds the
  gate for hours (resets the 300s wait clock while level rises) and sets
  `module.combat.auto_engage_world=true` to grind while waiting.
- **Quest-log-full recovery** (`quest_log_space.lua` picks a non-route sacrificial quest to
  abandon) + **train/hearth/loot effect verification** (spell-book delta / >500yd position jump /
  item-count increase).
- **Combat survival** (two rounds): low-HP fight-back + recovery latch, forced-target release on
  despawn/immunity/20s no-progress, adds-defense, loss-of-control suspend
  (`unit:get_loss_of_control_info`), mage `emergency_flee` consumer, warlock drain-life recovery,
  cancel-cast on target death.
- **Cockpit**: blocked-reason union (gate|nav|ghost|failed) with human text + nav
  `get_last_error()` reason; severity ok|warn|alarm in the pure view-model; module-fault visibility
  (degrade after 3 tick faults); maintenance panel; pause-corrected clocks; windowed ETA.
- **Vendor maintenance** (bags-full detour, sell greys, repair) — still not live-triggered.

## Prioritized backlog (work top-down; LIVE-VERIFY each — nothing above the line counts yet)

1. **RELOAD + live-verify the whole deployed push** (task 5 in the tracker has the ordered batch):
   start `1-11-Elwynn-Forest`, watch reconciliation, then the items below.
2. **Flight-path travel is the #1 blocker for 1-70 continuity** (`runtime_action.lua`
   `execute_flight`): `RuntimeFlight.destination` is a STRING node name but the handler does
   `tonumber(destination)` → nil → returns `"failed"`, so every named `.fp`/taxi step strands the
   bot. No documented name→node API — **discover the taxi surface live** (`core.input.take_taxi`
   signature, any taxi-map query) then wire name resolution. Also confirm the importer emits Flight
   actions and whether the Paladin chain's transitions actually need flights vs overland.
3. **`.xp` level gate live**: reach a gate op, confirm it holds (no force-advance) AND grinds
   (`module.combat.auto_engage_world`), level rises, gate releases.
4. **Chain advance live**: confirm `questing:chain_advance` fires at a profile's end and the next
   profile starts (hard to reach naturally — may need to force the executor near the end).
5. **Combat survival live**, **vendor maintenance live** (force `player.bags_full`), **effect
   verification live** (train/hearth/loot), **quest-log-full recovery** if reachable.
6. **Eat/drink economy** (task 10, not started): importer `buy_items` for class food/water; combat
   consumes food/drink out of combat instead of passive regen only.
7. **Hearth + import-time Z-resolution** via NavServer `/api/v1/height` (backlog item 7 remainder).

## The live-debug workflow (this is the project's core loop)

You have a **live game bridge** (`lx-debug` MCP). Verify in-game; never reason from code alone.

1. Edit → `luajit sentinel/tests/run_offline.lua` (repo root; expect 127/0).
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
- **`ripgrep` respects `.gitignore`** — `.questing/projects/*.json` is ignored, so `rg pattern
  .questing/projects/` silently returns nothing. Use `rg -u` (or a non-rg tool) on build-artifact
  dirs; a bare `rg` there nearly caused a false "importer is broken" conclusion.
- **Batch `import-guides` into a non-clean output dir leaves stale files**: it seeds "used"
  filenames from existing output (intentional, so it won't clobber prior runs), so a re-import
  writes NEW content to `name-2.json` and leaves the STALE `name.json`. For a full re-import,
  `rm -rf` the output dir first, OR import per-guide into fresh dirs (what the chain build does).
- `find_guide_files` is now sorted so batch imports are order-deterministic (was `fs::read_dir`).

## Operating rules

- **TDD**: write the failing offline test with the real wire shapes (numeric flags, positional
  payloads) before the fix; mocks must pin live-client behavior, not idealized behavior.
- One fix per commit, message states the live symptom it cures.
- When the user reports a symptom, pull live state FIRST (`game_eval` the executor log, kill
  trace, nav full state, combat state) — diagnose from evidence, then fix, then re-verify.
- Reconciliation invariants: game state is truth; saves only move the route forward; certain
  verdicts (ready turn-in, missed accept, unmet farm gate) may rewind once per op.
- Never claim something works without having watched it work in-game this session.
