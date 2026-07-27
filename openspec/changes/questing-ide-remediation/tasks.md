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

- [ ] 1.1 [PR1] `sentinel/main.lua`: construct `QueryClient:new()` (:3030) + `EditorClient` (:3031), pass both via `deps.query_client`/`deps.editor_client` to `IdePanels.install`
- [ ] 1.2 [PR1] `ide_panels.lua`: fix doc comments at lines 312/426/647 (`function():table|nil` → `table|nil`); nil client → explicit "query server unavailable" render, no fetch attempted
- [ ] 1.3 [PR1] Test `sentinel/tests/ui/test_ide_panels.lua`: install without `query_client` renders unavailable state, never idles
- [ ] 1.4 [PR2] Create `sentinel/ui/async_slot.lua`: `AsyncSlot.new({label, max_ticks=120})`, `slot:poll(fn)` — pending re-arms owner `_dirty`; data stores+clears; failure/exhaustion sets `state.error` and clears
- [ ] 1.5 [PR2] Route all four data bindings (Explorer/Graph/Properties/Database: detail+scan+grind+search) through named slots (`state._slots.detail/scan/grind/search`), replacing the divergent hand-rolled pending code at `ide_panels.lua:337-338` and `database_state.lua:161-162`
- [ ] 1.6 [PR2] Add `core.http_get(url, cb)` to `sentinel/tests/harness/mocks/sylvannas_api.lua`, holding the callback for `mock.pending_ticks` (default 2) before invoking (obs #225: mock currently has no `http_get` at all — the mechanical cause of last cycle's false-green suite)
- [ ] 1.7 [PR2] Test: one re-arm test per data panel — tick 1 shows loading + flag re-armed, tick 2 stores/renders data
- [ ] 1.8 [PR3] `shell.lua`/`shell_state.lua`: add `shell:publish_selection({panel_id, kind, id})` + `shell:on_selection(fn)`; `install()` subscribes once, routes to Properties `set_context` + focus-follow tab activation when origin ≠ properties
- [ ] 1.9 [PR3] Wire `select_quest` (Explorer), `select_node` (Graph), `select_entry`/"Open in NPC Inspector" (Database) to publish on the bus
- [ ] 1.10 [PR3] `shell.lua:531`: supply `ctx.player_position` each frame, nil-safe from `core.object_manager.get_local_player():get_position()`
- [ ] 1.11 [PR3] Test `test_shell_extensions.lua`: Database selection drives Properties `set_context`; render ctx carries `player_position` or nil without error
- [ ] 1.12 [PR3] Remove mock-data fallbacks from production paths (`_mock_scan` and equivalents); unavailable source → `state.error`, never fabricated data

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

- [ ] 3.1 [PR6] `sentinel/ui/widgets.lua`: add `text_input` widget — `core.input.is_key_pressed(vk)` for printable/Backspace/Enter/Escape, `core.input.is_key_down(16)` for shift, focus via `window:is_rect_clicked`; offline handler accepts injected `{vk}` events on the same code path
- [ ] 3.2 [PR6] In-game confirmation: `window:block_input_capture()` and `is_key_down(16)` are undocumented-but-real (proven in `SentinelNavClient/lib/AstroUI.lua:2286-2454`) — verify live during this PR; fallback to focus-gated capture only if unconfirmed
- [ ] 3.3 [PR6] Test: typed sequence builds the buffer, Enter submits, Escape reverts to the prior value
- [ ] 3.4 [PR6] `explorer_state.lua`: `set_query` marks dirty; binding tick debounces 300ms before `GET /quests/search?q=`; results render name/level/zone (`QuestSummary.zone`)/faction
- [ ] 3.5 [PR6] Test: rapid typing followed by 300ms elapsed fires exactly one search call
- [ ] 3.6 [PR6] `explorer_state.lua`: implement `add_to_profile` (AcceptQuest→objective nodes from `GET /quest/{id}/objectives`→TurnInQuest, POST via editor client) and `add_chain` (`GET /quest/{id}/chain`); editor unreachable → `state.error`
- [ ] 3.7 [PR6] Test: quest with kill+loot objectives produces the exact AcceptQuest/Kill/Loot/TurnInQuest subgraph on `add_to_profile`
- [ ] 3.8 [PR7] Create `sentinel/shared/editor_client.lua` wrapping `QueryClient:new(host, 3031)`: `list_campaigns`, `create_campaign`, `load_campaign`, `save_graph`, `add_nodes`, `update_node`, `validate`, `compile`; mutations call `QueryClient:invalidate(prefix)`
- [ ] 3.9 [PR7] `IdePanels.new_graph(client)`: accept the editor client (currently takes none per obs #225 — the Rust CRUD at :3031 has zero Lua callers); empty state gains `action_label = "New Campaign"` → `create_campaign`; list/open wired to `list_campaigns`/`load_campaign`
- [ ] 3.10 [PR7] Test: create→list→open round-trip against the editor client contract
- [ ] 3.11 [PR7] `graph_state.lua`: `edit_intent` (`ide_panels.lua:~610`) routes through `update_node` (`PUT /editor/campaigns/{name}/nodes/{id}`); `validate_graph` (`:631`) → `POST .../validate`, diagnostics render in validation bar, click navigates to node; `compile_graph` (`:633`) → `POST .../compile`
- [ ] 3.12 [PR7] Test: campaign with `TurnInQuest(9)` and no `AcceptQuest(9)` — validate shows `MISSING_ACCEPT` naming the node, click selects it
- [ ] 3.13 [PR7] Verify F15 escort recorder round-trip end-to-end: recorded path (live `ctx.player_position` stream) reproduces as editable Waypoint/Wait nodes — standalone verification, not folded into lifecycle work
- [ ] 3.14 [PR8] Wire remaining stub dispatch branches in `ide_panels.lua` through the editor client (obs #225 line refs): `add_condition:506`, `add_condition_group:508`, `delete_condition:510`, `add_inventory_rule:512`, `add_as_kill:724`; each surfaces editor errors in `state.error`, never a phantom success string
- [ ] 3.15 [PR8] Test: editor down for `add_as_kill` produces `state.error` naming the failed write, no phantom node appears
- [ ] 3.16 [PR9] `properties_state.lua`+render: 5 context views — npc (level/classification/loot buckets/starter+finisher quests/spawns), vendor (`sells` as `{item_entry,name,price}` + repairs/rule toggles), object (type/spawns/loot), node (payload fields per kind, validated edits), condition/inventory (add/group/delete; add/clear)
- [ ] 3.17 [PR9] Test: NPC inspector renders level/classification/≥1 loot bucket/starter quests from extended `NpcDetail`; vendor rows show item name+price from object `sells`; condition-tree add round-trips through the editor client
- [ ] 3.18 [PR10] `database_state.lua`: remove `CHAR_W=7` px/char approximation (line 346), use `window:get_text_size`/shell equivalent for all label-sized layout (chip widths, button widths)
- [ ] 3.19 [PR10] `database_state.lua`: `view_detail`/`select_entry` route through `AsyncSlot`; pending fetch shows loading, never falls through to "Entry N not found" (reserved for resolved 404s)
- [ ] 3.20 [PR10] Spawn scanner: `core.object_manager.get_all_objects()` + `is_unit()`/`get_npc_id()`/`get_name()`/`get_level()`/`get_creature_type()`/`get_position()`, distance via `core/geometry.lua::Geometry.distance`; group by entry (count/name/level/nearest distance); replaces phantom `dbg.nearby`
- [ ] 3.21 [PR10] Grind generator: `generate_grind`/`execute_grind` query `GET /spawns/nearby` via query client, compute XP/kill + XP/hour from server fields, output waypoints + Kill nodes + SellJunk/RepairEquipment via editor client; failures surface in `state.error`, never mock data; implement `edit_grind_entry:729`/`edit_grind_zone:731`
- [ ] 3.22 [PR10] Test: long NPC name renders full width via measured text; pending detail shows loading not "not found"; 3 simulated spawns group into one row with count 3

## Phase 4: Wiring & Verification [PR11–PR12]

- [ ] 4.1 [PR11] `travel_editor.lua`: `travel_add_waypoint` (`ide_panels.lua:845`) captures `ctx.player_position`; estimate via `POST /travel/route`, render per-segment + total times
- [ ] 4.2 [PR11] `stats_dashboard.lua`: compute quest/waypoint/NPC/object/vendor/flight counts from the loaded campaign graph on save, render as header badge chips
- [ ] 4.3 [PR11] Sweep for any remaining placeholder strings from the obs #225 inventory not closed by earlier PRs; confirm zero remain
- [ ] 4.4 [PR11] Test: Std full suite green; travel estimate + stats badge coverage in `sentinel/tests/ui/`
- [ ] 4.5 [PR12] Fixture-shape test: assert Lua fixture keys match Rust serde field names (snake_case) for `NpcDetail`/`QuestSummary`/`VendorInfo`
- [ ] 4.6 [PR12] Create `scripts/smoke_questing_ide.sh`: health check; `GET /quests/search` zoned summaries; `GET /npc/{entry}` extended fields; `GET /zone/{id}/spawns` aggregation; `GET /spawns/nearby` position-filtered results; `POST /travel/route` totals; editor create/list/open/validate round-trip — fails loudly per check
- [ ] 4.7 [PR12] Run the smoke script against live QueryServer (:3030) and Editor (:3031); required gate before archive
