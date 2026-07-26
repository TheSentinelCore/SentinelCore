# lx-debug — live game debugging bridge

Two halves that talk over HTTP on `127.0.0.1:7778`:

| Path | Runs | Role |
| --- | --- | --- |
| `lx-debug-server/` | Node, outside the game | MCP server (stdio) + HTTP bridge |
| `ext_plugin_lx_debug/` | LuaJIT, inside Project Sylvannas | Polls the bridge, executes, returns results |

The MCP client issues a command → the server queues it → the plugin polls, resolves it
against the Sylvannas SDK on the game thread, and POSTs the JSON result back.

## Design: no per-function wrappers

The plugin resolves **any** SDK path by table traversal (`resolve_and_call` in `main.lua`),
so all ~750 documented API entries are reachable through `game_eval` without a line of
wrapper code:

```
core.get_ping()
core.quests.get_num_quest_log_entries()
core.spell_book.get_spell_cooldown(12345)
player:get_position():dist_to(target:get_position())
```

Helpers under `dbg.*` exist **only** where one call cannot answer the question — walking the
quest log, correlating objectives to a quest id, or assembling a nav report. Everything else
is called directly. Hand-wrapping the full SDK would add ~750 things that can silently drift
out of sync, which is exactly the failure mode v3 fixed.

Discovery is solved by `game_api_docs`, which searches `docs/SylvannasAPI/` for exact
signatures. **Use it before calling anything you are not certain exists** — the SDK returns
`nil` for unknown methods rather than erroring, so a guessed name yields empty data, not a
failure.

## The docs are not authoritative — the live client is

Verified against Project Sylvannas core **2.005**, TBC, on 2026-07-23. The published
reference in `docs/SylvannasAPI/` is both **incomplete** and, in places, **wrong**:

| Claim in docs | Reality on the client |
| --- | --- |
| `get_quest_log_leader_board(...) -> string` (`"Wolves slain: 3/10"`) | Returns a **table**: `{description, is_completed, objective_type}` |
| `get_quest_log_title(...)` includes `is_complete` | **No such field.** Completion must be derived from objectives |
| `game-object` has ~119 methods | **1102** enumerated live |
| `core.input` has ~40 functions | **76** |
| No mention of `core.game_ui`, `core.craft`, `core.skill`, `core.trade_skill` | All present (40 / 19 / 9 / 45 methods) |

`get_buffs()` and `get_debuffs()` exist but return **empty** on TBC; only `get_auras()` is
populated, and every aura reports `type = -1`, so buff/debuff polarity is not available on
this client. `dbg.auras()` falls back to `get_auras()` and labels entries `kind = "aura"`
rather than pretending to know.

**So: enumerate before you trust.** `dbg.inspect('core.quests')` and friends list what the
client actually exposes. Use `game_api_docs` for prose and signatures, but let the live
client settle any disagreement.

### High-value surfaces found only by enumeration

Discovered via `dbg.inspect`, absent from the docs, and directly relevant to a questing bot:

| Call | Why it matters |
| --- | --- |
| `core.game_ui.get_all_completed_quest_ids()` | Every completed quest in one call (308 on the test character) — beats probing per id when validating a guide |
| `core.game_ui.get_loot_*` | The loot window was completely invisible before; runners stall on it constantly |
| `core.game_ui.get_vendor_item_info/count` | `vendor_buy(index)` was blind without it |
| `core.game_ui.get_corpse_position`, `get_resurrect_corpse_delay` | Feeds the runtime's `ghost` state |
| `core.spell_book.is_player_in_control()` | False while stunned/feared/rooted — a stall no state machine of ours can see |
| `core.input.release_spirit`, `resurrect_corpse` | Ghost recovery |
| `core.reload_plugins()` | Reload the plugin without alt-tabbing |
| `core.read_lua_string/table/integer`, `read_cvar` | Read real WoW globals and cvars |
| `core.object_manager.get_all_missiles()` | Incoming projectiles |
| `core.input.look_at`, `set_pitch`, `move_*_start/stop`, `strafe_*` | Raw movement control for nav debugging |

## MCP tools

| Tool | Purpose |
| --- | --- |
| `game_eval` | Run one SDK call (or multi-statement Lua) in the game |
| `game_multi_eval` | Run several calls in a single game tick — one consistent snapshot |
| `game_api_docs` | Search the SDK reference for signatures |
| `game_bridge_status` | Is the plugin connected? Check this first when `game_eval` times out |
| `game_wait_reload` | Block until the plugin reloads, then report its version |
| `game_read_data` / `game_write_data` | Read/write under `scripts_data/` |
| `game_read_log` | Tail a file under `scripts_log/` |

## Debugging a stuck questing bot

Start here — one call, whole picture:

```
game_eval  dbg.why_stuck()
```

It returns player state, a full nav report, recent `UI_ERROR_MESSAGE` events, gossip frame
state, and a plain-language verdict. Follow up with:

| Question | Call |
| --- | --- |
| Why did the game reject my action? | `dbg.errors()` — the game's own messages |
| What just happened? | `dbg.events(50)` — recorded game events |
| Where is the runner in the quest? | `dbg.quest_status(<id>)` |
| Everything in the log | `dbg.quest_log()` |
| Is nav wedged? | `dbg.nav_report()` — hierarchical state, e.g. `navigating.recovering.strafing` |
| Why won't it cast? | `dbg.spell_report(<spell_id>)` — known/usable/range/LoS/castable |
| What is on this NPC? | `dbg.target_info()`, `dbg.auras("target")` |
| What is around me? | `dbg.nearby(40, "npc")` — `npc` means real creatures |
| Is the loot window blocking? | `dbg.loot()` |
| Where is my corpse? | `dbg.corpse()` |

`dbg.nearby` filters on `is_unit()`, not `npc_id`. Signposts, mailboxes and flight-master
roosts all carry a real `npc_id` (Cathedral Square is 2190) while reporting `is_unit=false`,
`level=-1` and `is_dead=true`. Filtering on `npc_id ~= 0` returned all of them as NPCs. Use
`npc` for creatures, `object` for scenery, `unit` for both creatures and players.

`dbg.help()` lists everything.

Quest events are **not** in the Sylvannas registered-event list, so quest state must be
polled — that is what the `dbg.quest_*` helpers are for. The event recorder deliberately
drops `COMBAT_LOG_EVENT_UNFILTERED`; it fires hundreds of times a second and would evict the
whole ring buffer.

## Configuration

| Env var | Default | Needed for |
| --- | --- | --- |
| `LX_DEBUG_PORT` | `7778` | Bridge port (plugin's `SERVER_URL` must match) |
| `SCRIPTS_DATA_PATH` | `F:\ProjectSylvanas\scripts_data` | `game_read_data` / `game_write_data` |
| `SCRIPTS_LOG_PATH` | `F:\ProjectSylvanas\scripts_log` | `game_read_log` |
| `SYLVANNAS_DOCS_PATH` | `<repo>/docs/SylvannasAPI` | `game_api_docs` |

Since v3 the plugin POSTs results back, so **`game_eval` no longer needs the server to see
the game's disk at all**. The `SCRIPTS_*` paths only matter for the file tools. If the server
and the game run on different machines (or across WSL), leave them unset and the rest of the
bridge still works.

## Install

**Plugin:** copy `ext_plugin_lx_debug/` into the Sylvannas `scripts/` directory and reload.
It pings `/startup` on load; confirm with `game_bridge_status`.

**Server:** `npm install` in `lx-debug-server/`, then register it as an MCP server (see
`.mcp.json` at the repo root).

## Tests

```bash
cd mcp/lx-debug-server && npm test          # parser units + MCP end-to-end
cd mcp/ext_plugin_lx_debug && luajit tests/run_tests.lua
```

The Lua suite mocks the injector in `tests/mock_sylvannas.lua`, mirroring the shapes in
`docs/SylvannasAPI/`. It deliberately does **not** define `is_enemy`, `get_facing`, or
`get_active_auras` — those never existed in the SDK, and v2 called all three. Because every
such call was wrapped in `pcall` or an `and` guard, they returned empty data instead of
failing, which is why the bugs survived so long. **Assert on values, never on "did not
error."**
