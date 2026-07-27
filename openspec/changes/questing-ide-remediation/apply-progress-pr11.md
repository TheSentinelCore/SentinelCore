# Apply progress — PR11 (Travel editor + stats wiring + stub sweep)

**Change**: `questing-ide-remediation`
**Mode**: Standard (`strict_tdd: false`)
**Store**: hybrid — this file plus Engram `sdd/questing-ide-remediation/apply-progress-pr11`
**Delivery**: force-chained, stacked-to-main, 400 changed lines per commit
**Worktree**: `/home/levi/Projects/SentinelCore-worktrees/qir-rust-track`
**Branch**: `qir/pr11-travel-stats`, off `qir/pr6-text-input-explorer` (`d5c7991`)
**Pushed**: no. **PR opened**: no.

Tasks 4.1–4.4 complete. 4.5–4.7 are PR12 and untouched.

## Commits

| SHA | Subject | Budget (add+del) |
|---|---|---|
| `1dd5c4a` | `feat(ui): capture the player's real position as a travel waypoint` | 377 |
| `1a22816` | `feat(ui): build the travel route request from what the campaign actually carries` | 335 |
| `c6a124c` | `feat(ui): ask the query server for the route times instead of guessing them` | 331 |
| `e2975a1` | `feat(ui): show the route's segment times, and give the operator a way to ask` | 221 |
| `7d2069a` | `feat(ui): count the loaded campaign into the stats badges` | 304 |
| `f8ca92d` | `test(ui): pin the remaining placeholder inventory to the tasks that own it` | 86 |

All six under the 400-line guard. Two splits were made mid-flight rather than
retroactively: commit 1 was measured at 464 and the campaign-map read was moved
out into commit 2; commit 3 was measured at 550 and split at the
transport/render seam into `c6a124c` + `e2975a1`. Each staged tree was verified
in isolation before committing.

## Files

| File | Action |
|---|---|
| `sentinel/ui/panels/travel_editor_state.lua` | Modified — capture, segment builder, estimate transport, estimate rendering |
| `sentinel/ui/panels/stats_dashboard.lua` | Modified — badge counts, chip row, `Geometry.distance` |
| `sentinel/ui/ide_panels.lua` | Modified — `current_map_id`, `player_faction`, travel dispatch + tick, graph tick wrap |
| `sentinel/tests/ui/test_travel_stats.lua` | Created — 48 cases |
| `sentinel/tests/harness/mocks/sylvannas_api.lua` | Modified — `core.http_post` + posted-body recording |
| `sentinel/tests/run_offline.lua` | Modified — one registration line |

`graph*.lua`, `properties*.lua`, `editor_client.lua`, `explorer_state.lua` and
`widgets.lua` were deliberately NOT touched: PR7 and PR9 own them and PR7 is
running concurrently in the primary checkout, which was never written to.

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command / result | `luajit sentinel/tests/run_offline.lua` from the worktree root — **2006 passed, 0 failed** (+21 opaque suites, 21 ok). Baseline on `qir/pr6-text-input-explorer` was 1958/0, so **+48**, exactly the 48 `function M.test` in the new suite (the PR6 test-slicing trap did not recur) |
| Runtime harness | Offline only. The harness reproduces the injector's async `core.http_get`/`core.http_post` (callback lands N ticks later, never inside the call), which is the runtime boundary this unit crosses. Live in-game confirmation of the capture and of `/travel/route` against a running QueryServer is PR12's smoke script (tasks 4.6–4.7) |
| Rollback boundary | Revert the six commits above. Nothing outside the six files listed changes; `sentinel/ui/panels/validation_status.lua` and every other panel are untouched |

## Mutations proven

1. **`travel:add_waypoint(nil, ...)`** — the capture no longer reads
   `ctx.player_position`. → 1 red:
   `test_the_installed_capture_button_reaches_the_live_position` (`expected 1, got 0`).
   Reverted, re-verified green.
2. **`add_entry` accepting 0** — an unfilled `default_intent` field counts as an
   entity. → 1 red: `test_an_unfilled_intent_field_is_not_an_entity`
   (`expected 0, got 1`). Reverted, re-verified green.

## The taxi-segment 400, and how it was handled

PR5 documented that `/travel/route` **refuses a taxi segment carrying only node
ids** — the QueryServer has no taxi tables and `TaxiPathNode.dbc` is in no
catalog, so it returns 400 rather than fabricating a per-hop constant. The
spec's literal request shape (`{type, from_node, to_node}` alone) therefore
cannot produce a time.

PR11 does **not** work around this and does **not** invent a hop estimate.
Instead:

- The runtime already owns taxi positions in `sentinel/kernel/catalogs/taxi_nodes.lua`.
  A flight leg is sent as `type = "taxi"` **with `from`/`to` positions taken from
  that catalog**, which is precisely the shape the server accepts. The node ids
  travel alongside so the server's refusal can still name them.
- The leg only becomes a taxi segment once `TaxiNodes.resolve` answers exactly
  one node. `unknown_destination`, `ambiguous_destination` and `needs_faction`
  are all reported in `state.error` naming the destination, and the request never
  leaves. A faction-complement pair ("arathi" = Refuge Pointe vs Hammerfall)
  resolves once the faction is known; the faction is derived from the character's
  race via `shared/race_faction.lua`, because there is no faction API — and when
  it cannot be read the refusal stands rather than defaulting to a side.
- If the server refuses anyway, its own message reaches `state.error` verbatim
  (`"/travel/route refused the route (HTTP 400): segment 1: ..."`). `AsyncSlot`'s
  generic "failed" text is deliberately overwritten, because a documented refusal
  rendered as "estimate failed" reads like a network glitch.

Covered by `test_a_resolved_flight_destination_becomes_a_taxi_segment_at_the_nodes_position`,
`test_an_unresolvable_flight_destination_is_reported_not_guessed`,
`test_a_faction_ambiguous_destination_is_refused_until_a_faction_is_given` and
`test_a_server_refusal_is_reported_in_the_servers_own_words`.

## Deviations from design

1. **`questing.Travel` carries no map, so campaign-derived routes cannot be
   estimated.** `default_intent` is `{destination, x, y, z, tolerance,
   allow_flight, wait_time}` — no map — and the same coordinates name different
   places on different maps. The waypoint reads `intent.map` when present (so the
   field is honoured the moment the graph carries it) and `build_segments`
   refuses to measure it otherwise. **CAPTURED** waypoints do carry a map
   (`core.get_map_id()` at capture time), so the spec's scenario — add a waypoint,
   then request estimates — works end to end today. Adding `map` to the Travel
   intent belongs to whoever owns `graph_state.lua` (PR7).
2. **"on save" is implemented as "on any graph mutation".** There is no
   `save_graph` yet — task 3.8/3.11 [PR7] creates it. The recompute hangs off
   `graph_state._dirty`, which every mutation sets, so it is strictly stronger
   than "on save" and needs nothing PR7 has not landed.
3. **"header badge chips" renders as a chip row at the top of the stats
   overlay**, not in the shell's window header. `shell.lua` has no header-chip
   slot (only `set_validation_bar` and per-tab badges), and adding one would put
   PR11 inside the file every later unit shares. The counts — the substance of
   F20-R1 — are unaffected.
4. **Task 4.3 cannot reach "zero remain" from PR11.** Ten placeholders are owned
   by PR7/PR8/PR10. Pinned by audit instead; see the tasks file.

## Issues found

1. **`StatsDashboard:compute` and `TravelEditorState:load_from_campaign` had no
   caller at all.** `IdePanels.install` created both objects, stored them, and
   never fed either one a campaign. The dashboard reported zero nodes whatever
   was loaded; the travel editor listed no routes for a campaign full of Travel
   nodes. Every test that "proved" they worked called them directly — the same
   shape as obs #239's unreachable controls, one level up.
2. **`questing.Loot` is still absent from `graph_state.NODE_TYPES`** (obs #237).
   The badge counter reads `object_entry` anyway, so a campaign containing a Loot
   node the palette cannot draw is still counted correctly.
3. **A captured waypoint is lost when the graph changes**, because
   `load_from_campaign` rebuilds the route list from the graph. Routes have always
   been derived; persisting one is `POST /editor/campaigns/{name}` and belongs to
   PR7. Flagged rather than papered over.
4. **The XP / duration / distance figures in the stats overlay are fixed-constant
   heuristics** (200 XP per kill, 800 per quest, 30s per kill…) with no server
   source. They predate PR11 and are out of its task scope; the honest source is
   `/spawns/nearby`'s `xp_reward` (PR5), which PR10's grind generator consumes.
   Worth a follow-up: they are numbers that look measured and are not.
5. **`tests/modules/questing/test_recorder.test_generated_ids_are_uuid_shaped_and_unique`
   flaked once** during this work (`recorder.lua` seeds its private random stream
   from `os.time()`, one-second resolution). Known, pre-existing, out of scope.
   Re-run was green.

## Concurrency

- The primary checkout `/home/levi/Projects/SentinelCore` was never written to.
- `sentinel/ui/ide_panels.lua` edits are confined to travel/stats/graph-tick
  lines and are additive; no reordering or reformatting.
- `tasks.md` — only the four `[PR11]` checkboxes ticked.
- Progress kept in this file, never in `apply-progress.md` (PR7 owns that
  concurrently).
