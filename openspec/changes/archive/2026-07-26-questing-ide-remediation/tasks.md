# Tasks: Questing IDE Remediation — Fix + Finish to Spec

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~11,000 baseline (exempt, P0) + ~4,900 remediation across PR1–PR12 |
| PR count | 1 baseline landing (7 commits B1–B7) + 12 remediation PRs |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | P0 (baseline, exempt) → PR1 → PR2 → … → PR12, stacked-to-main |
| Delivery strategy | force-chained |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

**Granted exceptions** (maintainer decision, 2026-07-26):
- `size:exception` for PR5 — 1,595 authored lines across 4 commits on 2 stacked branches.
  `a66e20e` (603) is one generator + one derivation + its test, with no meaningful split.
  `eb37b83` (792) interleaves three endpoints in `db.rs`/`handlers.rs`; re-slicing risked a
  non-compiling intermediate. Generated catalog data excluded from authored counts.
- PR2 was split retroactively into `qir/pr2a-async-slot` (435) and `qir/pr2b-panel-rearm` (307).

Std = `luajit sentinel/tests/run_offline.lua` (run from repo root). Every task below names its PR slice; budget is per PR, not per phase.

### Suggested Work Units

| Unit | Goal | PR | Focused test | Runtime harness | Rollback |
|---|---|---|---|---|---|
| 0 | Land uncommitted work as 7 labeled `baseline:` commits | P0 | Std | N/A — baseline commit, no logic change | Reset to `99bb8d7` + snapshot restore |
| 1 | Wire `query_client`/`editor_client` at install, unify contract, unavailable state | PR1 | Std | Manual: launch IDE w/o client, confirm "unavailable" state | Revert PR1 |
| 2 | `async_slot.lua` primitive + pending-mock harness + per-panel re-arm | PR2 | Std | N/A — offline pending-mock reproduces runtime fetch model | Revert PR2 |
| 3 | Selection bus + `ctx.player_position` + mock-data removal | PR3 | Std | Manual: select in Database, confirm Properties follows in-game | Revert PR3 |
| 4 | Rust type extensions (`NpcDetail`/`QuestSummary`/`VendorInfo`) + ripple | PR4 | `cargo test` (SentinelQueryServer + SentinelQuesting) | N/A — Rust unit tests | Revert PR4 |
| 5 | Zone/spawn ETL catalogs + `/spawns/nearby` + `/zone/{id}/spawns` + `/travel/route` | PR5 | `cargo test -p sentinel-queryserver` | `curl` each new endpoint against live QueryServer + DB | Revert PR5 |
| 6 | `text_input` widget + Explorer search/add_to_profile/add_chain | PR6 | Std | Manual: type/backspace/enter/escape in-game; confirm undocumented VK APIs | Revert PR6 |
| 7 | `editor_client.lua` + Graph campaign lifecycle + validate/compile + escort verify | PR7 | Std | `curl -X POST 127.0.0.1:3031/editor/campaigns/stw` round-trip | Revert PR7 |
| 8 | Wire remaining stub dispatch branches (condition/inventory/add_as_kill) | PR8 | Std | Manual: editor down → `state.error`, no phantom node | Revert PR8 |
| 9 | Properties 5 context views | PR9 | Std | N/A — server-shaped fixtures cover it | Revert PR9 |
| 10 | Database measured text + pending-detail fix + spawn scanner + grind on real data | PR10 | Std | Manual: scan 3 spawned wolves in-game | Revert PR10 |
| 11 | Travel/stats wiring + stub sweep | PR11 | Std | Manual: add waypoint in-game, verify segment times | Revert PR11 |
| 12 | Fixture-shape test + smoke script | PR12 | `scripts/smoke_questing_ide.sh` | This unit IS the runtime harness (live :3030/:3031) — required gate before archive | Revert PR12 |

## Phase 0: Baseline [P0]

- [x] 0.1 [P0] Snapshot working tree — written to the session scratchpad (`scratchpad/qir/pre-baseline.diff` + `untracked.tar.gz`), NOT `.scratch/` in-repo: snapshots must never enter the tree
- [x] 0.2 [P0] Commit B1 `baseline: editor rust` — `c4e99ab`
- [x] 0.3 [P0] Commit B2 `baseline: query layer` — `b61ef8d`
- [x] 0.4 [P0] Commit B3 `baseline: explorer panel` — `d6ea39d`
- [x] 0.5 [P0] Commit B4 `baseline: graph panel` — `b2f9a77`
- [x] 0.6 [P0] Commit B5 `baseline: properties panel` — `5e6ab47`
- [x] 0.7 [P0] Commit B6 `baseline: database panel` — `48a396d`
- [x] 0.8 [P0] Commit B7 `baseline: shell extensions` — `b20c2f0`
- [x] 0.9 [P0] Verify Std stays green after each of B1–B7 — run per commit in a detached worktree: `99bb8d7`…`48a396d` all `1574 passed, 0 failed` (+21 opaque suites ok), `b20c2f0` `1864 passed, 0 failed`. B3–B6 hold flat because `run_offline.lua` only registers the new suites in B7 (+290 cases), so their per-commit greenness is loadability evidence, not coverage evidence

## Phase 1: Foundations [PR1–PR3]

- [x] 1.1 [PR1] `sentinel/main.lua`: construct `QueryClient:new()` (:3030), pass via `deps.query_client` to `IdePanels.install` — **`editor_client` half DEFERRED to PR7**: `sentinel/shared/editor_client.lua` does not exist until task 3.8, and constructing a `deps.editor_client` that resolves to nil (or to a raw `QueryClient` at :3031 with none of the campaign verbs) would reintroduce exactly the silent-nil contract this change removes. Tasks 1.1 and 3.8 are ordered inconsistently; PR7 owns the main.lua line. **CLOSED IN PR7**: `main.lua` now constructs a second `EditorClient:new("127.0.0.1", 3031)` and passes `deps.editor_client`; `test_main_diagnostics` asserts it is a distinct table answering all eight campaign verbs
- [x] 1.2 [PR1] `ide_panels.lua`: doc comments on `new_explorer`/`new_properties`/`new_database` now say `table|nil`, not `function():table|nil`; nil client → `state.error = "query server unavailable"` via a single shared `mark_query_client_unavailable`, no fetch attempted. Database scan is exempt (object manager, not the query server); its detail/grind pendings are dropped so the state's mock-data branches are unreachable from the installed panel
- [x] 1.3 [PR1] Tests: `test_ide_panels.lua` gains 5 cases (unavailable on tick per data panel, unavailable actually painted, identity of the passed table, Explorer/Properties selection reaching the client on the tick and never in render); `test_main_diagnostics.lua` gains the host-side guard that loads real `main.lua` behind a spy on `IdePanels.install` and asserts the captured deps
- [x] 1.4 [PR2] Create `sentinel/ui/async_slot.lua`: `AsyncSlot.new({label, max_ticks=120})`, `slot:poll(fn)` — pending re-arms owner `_dirty`; data stores+clears; failure/exhaustion sets `state.error` and clears. `owner` is passed in `new`'s options table so `poll(fn)` keeps the single-argument shape the design pins; `poll` answers `(status, data)` with status `ok|pending|failed|timeout`, and `slot:reset()` abandons a request whose selection was replaced
- [x] 1.5 [PR2] Route the three QUERY-SERVER data bindings (Explorer detail/chain/objectives/search, Properties detail, Database scan/detail/grind) through named `state._slots.*`, replacing the hand-rolled pending code at `ide_panels.lua:337-338` and `database_state.lua:161-162`. **Graph is DEFERRED to PR7**: it has no fetch — its `_dirty` branch is a comment reading "in a real deployment this would refresh from /editor/campaigns/{name}" — and a slot with nothing behind it is dead code that no test can hold honest. **CLOSED IN PR7**: `graph_state._slots` now holds `list`/`campaign`/`create`/`validate`/`compile`, all driven by the editor client
- [x] 1.6 [PR2] Add `core.http_get(url, cb)` to `sentinel/tests/harness/mocks/sylvannas_api.lua`, holding the callback for `Mock.http.pending_ticks` (default 2) harness ticks before invoking; `Mock.http_advance()` is that tick and `Mock.advance_time` drives it. The one-argument form RAISES, as the live SDK does. Routes registered with `Mock.set_http_response(fragment, body)`; an unrouted url resolves 404 rather than hanging
- [x] 1.7 [PR2] Test: one re-arm test per data panel in `test_ide_panels.lua` (tick 1 pending → `_dirty` re-armed + loading, tick 2 stores) plus `tests/ui/test_async_slot.lua` — 10 cases covering the slot contract and the real `QueryClient` over the new mock
- [x] 1.8 [PR3] `shell_state.lua` owns the channel (`publish_selection`/`on_selection`/`selection`/`last_selection_error`); `shell.lua` forwards and adds the one thing the view-model cannot know — a **render-frame refusal**, since every subscriber does real work and `set_context` inside a render callback is the rule the shell exists to enforce. `install()` subscribes once: Properties `set_context` + focus-follow `activate` when origin ≠ properties. The channel is content-free so `shell.lua` still never names a panel (ADR 09b §6)
- [x] 1.9 [PR3] `select_quest`→`kind="quest"` (Explorer), `select_node`→`kind="node"` (Graph), `select_entry` AND `view_detail`→`kind="npc"` (Database — "View NPC Detail" IS the spec's "Open in NPC Inspector"; two action ids, one selection). All published from `dispatch`, which the shell calls in tick context
- [x] 1.10 [PR3] `shell.lua`: `_poll_player_position()` reads the object manager on the **TICK** (next to `_poll_combat`, per ADR 09b §2.4 — see Deviations) and both `_draw_body`'s ctx and `_tick_context()` carry it. nil-safe through two pcalls; a raising object manager is still just no position
- [x] 1.11 [PR3] `test_shell_extensions.lua` +8 cases: Database selection drives Properties `set_context`, focus-follow activates properties, Explorer/Graph publish their own kinds, mid-frame publish refused without latching, incomplete selection refused, render ctx carries the position, tick ctx carries it, absent/raising player reads nil and still paints
- [x] 1.12 [PR3] `_mock_scan` and `_mock_grind_result` DELETED (not flagged — a fixture reachable from `execute_*` reaches the injector). Absent scan source → `state.error` naming it, `scan_results` empty; absent query client → `grind estimate unavailable: no query server`. The 3 scan tests that asserted six invented rows were the defect verbatim and are replaced by real-source tests

## Phase 2: Rust Contracts + Zone Data Pipeline [PR4–PR5]

- [x] 2.1 [PR4] `SentinelQuesting/query-types/src/lib.rs`: add `QuestSummary.zone: String`; `NpcDetail` += `level: u8, classification: String, loot: Vec<LootEntry>, quests: Vec<NpcQuestRef>`; `VendorInfo.sells: Vec<VendorItem>` (replaces `Vec<u32>`) — all new fields `#[serde(default)]`
- [x] 2.2 [PR4] `SentinelQueryServer/src/db.rs`: extend `get_npc` (MinLevel/MaxLevel/Rank, loot via `creature_loot_template ⋈ item_template`, quests via `creature_questrelation`+`creature_involvedrelation` ⋈ `quest_template`); extend `get_vendor` (`npc_vendor ⋈ item_template`, `ExtendedCost≠0` → price 0); extend `search_quests` (`ZoneOrSort` → new `zone_names.rs` static TBC area map)
- [x] 2.3 [PR4] Update ripple call sites for new required struct fields: `compiler/tests/{kernel_combat_policy,kernel_worked_example}.rs`, `importer/src/project_builder.rs`, `importer/tests/{mapper,importer}.rs`, `queryclient/tests/queryclient.rs`, `queryclient/src/memory.rs`
- [x] 2.4 [PR4] Test: `cargo test` green in `SentinelQueryServer/` and `SentinelQuesting/` (both workspaces, run from inside each)
- [x] 2.5 [PR5] Create `sentinel/tools/regen_zone_catalog.py` mirroring `regen_taxi_paths_catalog.py`: parse `Emulators/Mangos - Classic TBC/extracted/dbc/AreaTable.dbc` for zone names/hierarchy, parse `maps/*.map` area-ID grids to compute zoneId for all 109,352 creature spawns
- [x] 2.6 [PR5] Commit generated catalogs: `sentinel/kernel/catalogs/zones.json`, `zones.lua`, spawn-zone index
- [x] 2.7 [PR5] Test mirroring `sentinel/tests/kernel/test_taxi_paths.lua` pattern: catalog regen produces non-empty, structurally valid zone + spawn-zone catalogs
- [x] 2.8 [PR5] `SentinelQueryServer/src/handlers.rs`+`main.rs`: add `GET /spawns/nearby?map={id}&x={x}&y={y}&radius={r}` — F13's primary position-filtered creature data source
- [x] 2.9 [PR5] `handlers.rs`+`main.rs`: add `GET /zone/{id}/spawns` joining the spawn-zone index with `creature`+`creature_template`, returns `{zone_id, zone_name, creatures[], objects[]}`; unknown zone → 404 naming the id
- [x] 2.10 [PR5] `handlers.rs`+`main.rs`: add `POST /travel/route` (`{segments:[...]}` → `{segments:[{type,distance_m?,estimated_s}], total_s}`); extends the existing `/travel/estimate`, does not replace it
- [x] 2.11 [PR5] Test `cargo test -p sentinel-queryserver`: all three new endpoints, including the 404 unknown-zone case

## Phase 3: Panel Remediation [PR6–PR10]

- [x] 3.1 [PR6] Split in two, because a widget that decides anything decides it inside a render callback where no test can reach it: `sentinel/ui/text_input_state.lua` (NEW) owns the buffer, caret, `apply_key`/`apply_keys` and `collect(input)`; `widgets.lua::text_input` draws the projection and forwards keys. Offline injects `opts.events`, the injector polls `opts.input`/`core.input` — both land in the same `apply_keys`
- [ ] 3.2 [PR6] **BLOCKED ON THE INJECTOR — cannot be closed offline.** `window:block_input_capture()` and `is_key_down(16)` are reached through a type check + pcall, so the focus-gated fallback is what runs when they are absent; BOTH paths are asserted (`test_text_input_widget.lua`), and `fake_window` was deliberately NOT given `block_input_capture` so the fallback is the offline default. Live confirmation still owed
- [x] 3.3 [PR6] Test: `tests/ui/test_text_input.lua` (21 cases) + `test_text_input_widget.lua` (13) — both spec scenarios verbatim, caret movement, max length, undocumented calls present AND absent
- [x] 3.4 [PR6] `explorer_state.lua`: `search_input` buffer + `sync_search_input(now)` (read BEFORE the dirty gate — typing cannot mark the panel dirty from render) + `search_due(now)`/`mark_search_served` at `SEARCH_DEBOUNCE_S = 0.30`; rows carry `ExplorerState.result_meta` = level/zone/faction. **Gap: `QuestSummary` has NO `faction` field** (verified on `qir/pr4-rust-types`) — it is read, not fabricated, and renders "—" until the Rust side carries it. Empty `zone` likewise renders "—", never a guess
- [x] 3.5 [PR6] Test: `test_rapid_typing_then_300ms_fires_exactly_one_search` + `test_a_second_query_searches_again_even_with_results_on_screen` (the old `#results == 0` gate allowed exactly one search per panel, ever)
- [x] 3.6 [PR6] `add_to_profile`/`add_chain` build the subgraph in `explorer_state` and write it through `editor_client:add_nodes(campaign, nodes)`. Five distinct failures are reported and return **false**: no editor client, no open campaign, objectives still in flight, a live editor refusing, a client that raises. The client itself is PR7 (task 3.8); the binding takes it as a dependency
- [x] 3.7 [PR6] Test: the spec's subgraph exactly — AcceptQuest(1234)/Kill(567,10)/Loot(789,5)/TurnInQuest(1234). `collect` lowers to `questing.Loot` carrying `source_creatures`, since **`questing.Loot` is absent from `graph_state.NODE_TYPES`** (19 types, no Loot) while `runtime_action.lua:329` executes it — a Graph-palette gap for PR7/PR8
- [x] 3.8 [PR7] Created `sentinel/shared/editor_client.lua`. TWO verb families, because the SDK has only `http_get`/`http_post` and both are async: POLLED (`list_campaigns`/`load_campaign`/`create_campaign`/`validate`/`compile`) answer `data | (nil,true) | (nil,nil)` and drive straight through `AsyncSlot`; DISPATCHED (`add_nodes`/`update_node`/`save_graph`) answer only that the request LEFT, with the server's refusal queued for `take_error()`. `QueryClient:invalidate(prefix)` added and called on every write. **`create_campaign` is polled, not dispatched** — opening a campaign before the editor answered caches a 404
- [x] 3.9 [PR7] `IdePanels.new_graph({editor_client})`: chooser with a `text_input` for the name, `action_label = "New Campaign"`, a `list_campaigns` list, `load_campaign` on open, and PR2's deferred slots (`list`/`campaign`/`create`/`validate`/`compile`). `show_add_node_menu` now WRITES through the editor and re-reads instead of inserting locally
- [x] 3.10 [PR7] Test: create→list→open round-trip at both levels — `test_editor_client.lua` against the wire (POST body, cache drop, re-read) and `test_ide_panels.lua` against the binding (create resolves → open → the editor's own graph on screen)
- [x] 3.11 [PR7] `edit_intent` opens an inline `text_input` seeded with the current value and Enter writes the WHOLE node through `update_node`; the typed string is coerced back to the field's existing type and refused if it will not coerce. `validate_graph`/`compile_graph` POST through slots; diagnostics render in a validation bar and clicking one selects the node. **Route note: the SDK has no PUT**, so `POST /editor/campaigns/{name}/nodes/{node_id}` was added as an alias in `campaign_handlers.rs` — a PUT-only route is unreachable from in-game Lua
- [x] 3.12 [PR7] Test: `MISSING_ACCEPT` end to end. The Rust handler returned an empty Vec unconditionally, so the rule was IMPLEMENTED (`campaign_handlers.rs::validate_campaign`, 5 Rust tests) as well as rendered; the Lua test asserts the bar row and that clicking it selects the node. **V2–V11 remain unimplemented and are not reported as clean**
- [x] 3.13 [PR7] F15 round-trip verified in a standalone suite (`tests/ui/test_escort_round_trip.lua`, 6 cases). It was BROKEN: render-callback sampling ran once per frame, `EscortRecorder:generate_nodes` had no caller, and `GraphState:generate_escort_nodes` inserted locally. Now sampled on the tick from `ctx.player_position`, written through the editor, and re-read — the test walks a path, stops, and edits one of the nodes that came back
- [x] 3.13b [PR7] `questing.Loot` added to `graph_state.NODE_TYPES` (obs #237) with the fields `execute_loot` actually reads. **Still not executable when lowered from a `collect` objective** — that node carries the item id in `object_entry` and a `source_creatures` list the runtime ignores; the compiler's collect→`Kill(loot=true)` lowering is still owed
- [x] 3.14 [PR8] Wire remaining stub dispatch branches in `ide_panels.lua` through the editor client (obs #225 line refs): `add_condition:506`, `add_condition_group:508`, `delete_condition:510`, `add_inventory_rule:512`, `add_as_kill:724`; each surfaces editor errors in `state.error`, never a phantom success string
- [x] 3.15 [PR8] Test: editor down for `add_as_kill` produces `state.error` naming the failed write, no phantom node appears
- [x] 3.16 [PR9] `properties_state.lua`+render: 5 context views — npc (level/classification/loot buckets/starter+finisher quests/spawns), vendor (`sells` as `{item_entry,name,price}` + repairs/rule toggles), object (type/spawns/loot), node (payload fields per kind, validated edits), condition/inventory (add/group/delete; add/clear). **Object loot is NOT served** by `/object/{entry}` (`ObjectInfo` is `{entry,name,kind,position}`); the view states the absence rather than inventing it, and the `respawn`/`skill` lines that had no wire source were deleted. **Node supply** is a separate door in `install`'s subscriber — the bus stays content-free — because there is no `/node/{id}` endpoint
- [x] 3.17 [PR9] Test: NPC inspector renders level/classification/≥1 loot bucket/starter+finisher quests from extended `NpcDetail`; vendor rows show item name+price from object `sells` (price 0 → "special cost", never "free"); condition-tree add/group/delete round-trips **through the state** — the editor-client half is DEFERRED to PR8 (task 3.14 owns those dispatch branches) because `sentinel/shared/editor_client.lua` does not exist until PR7
- [x] 3.18 [PR10] `database_state.lua`: remove `CHAR_W=7` px/char approximation (line 346), use `window:get_text_size`/shell equivalent for all label-sized layout (chip widths, button widths)
- [x] 3.19 [PR10] `database_state.lua`: `view_detail`/`select_entry` route through `AsyncSlot`; pending fetch shows loading, never falls through to "Entry N not found" (reserved for resolved 404s)
- [x] 3.20 [PR10] Spawn scanner: `core.object_manager.get_all_objects()` + `is_unit()`/`get_npc_id()`/`get_name()`/`get_level()`/`get_creature_type()`/`get_position()`, distance via `core/geometry.lua::Geometry.distance`; group by entry (count/name/level/nearest distance); replaces phantom `dbg.nearby`
- [x] 3.21 [PR10] Grind generator: `generate_grind`/`execute_grind` query `GET /spawns/nearby` via query client, compute XP/kill + XP/hour from server fields, output waypoints + Kill nodes + SellJunk/RepairEquipment via editor client; failures surface in `state.error`, never mock data; implement `edit_grind_entry:729`/`edit_grind_zone:731`
- [x] 3.22 [PR10] Test: long NPC name renders full width via measured text; pending detail shows loading not "not found"; 3 simulated spawns group into one row with count 3

## Phase 4: Wiring & Verification [PR11–PR12]

- [x] 4.1 [PR11] `travel_add_waypoint` captures `ctx.player_position` (+ `core.get_map_id()`, read in the same tick context — `get_position()` answers a bare `{x,y,z}` and the same coordinates name different places on different maps); estimate via `POST /travel/route` through `AsyncSlot`, per-segment + total times rendered from the server's answer only. **Two documented refusals**: a waypoint with no map is refused, not filed on map 0; a flight leg is only sent as `type="taxi"` once its destination resolves to exactly one node in `kernel/catalogs/taxi_nodes.lua`, because the server has no taxi tables and refuses a positionless hop rather than inventing a per-hop constant
- [x] 4.2 [PR11] `stats_dashboard.lua`: quest/waypoint/NPC/object/vendor/flight counts as distinct sets over fields the graph already carries, rendered as header badge chips. **`compute` and `load_from_campaign` had NO CALLER** — both now hang off the Graph state's `_dirty`, which covers "on save" and every edit before one without needing the campaign lifecycle PR7 owns
- [x] 4.3 [PR11] Sweep: the two PR11 owned (`travel_add_waypoint`, `add_route`'s note) are closed. **Ten remain and zero is not reachable from PR11** — `add_condition`/`add_condition_group`/`delete_condition`/`add_inventory_rule`/`add_as_kill` are task 3.14 [PR8], `edit_intent`/`validate_graph`/`compile_graph` are task 3.11 [PR7], `edit_grind_entry`/`edit_grind_zone` are task 3.21 [PR10]. The inventory is now PINNED by a source audit, so a new placeholder fails the suite and each closure is a deleted line a reviewer sees
- [x] 4.4 [PR11] Test: `tests/ui/test_travel_stats.lua` (48 cases) registered in `run_offline.lua`; harness gains `core.http_post` with the same pending model as `http_get`. Std: 1958 → **2006 passed, 0 failed**
- [x] 4.5 [PR12] Fixture-shape test: assert Lua fixture keys match Rust serde field names (snake_case) for `NpcDetail`/`QuestSummary`/`VendorInfo`
- [x] 4.6 [PR12] Create `scripts/smoke_questing_ide.sh`: health check; `GET /quests/search` zoned summaries; `GET /npc/{entry}` extended fields; `GET /zone/{id}/spawns` aggregation; `GET /spawns/nearby` position-filtered results; `POST /travel/route` totals; editor create/list/open/validate round-trip — fails loudly per check
- [ ] 4.7 [PR12] Run the smoke script against live QueryServer (:3030) and Editor (:3031); required gate before archive
