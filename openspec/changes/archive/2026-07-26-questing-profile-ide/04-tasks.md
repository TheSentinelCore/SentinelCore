# Tasks: Questing Profile IDE

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Total estimated lines | ~5,500 |
| 400-line budget risk | HIGH |
| Chained PRs recommended | Yes |
| Suggested split | 12 stacked PRs (Phase 0 first, then 1-5 in any order) |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Editor Campaign CRUD | PR-0a | `cargo test -p sentinel-editor` | `POST /editor/campaigns/{n}` add/list round-trip | Revert editor crate changes only |
| 2 | QueryServer quest/zone endpoints | PR-1a | `cargo test -p SentinelQueryServer` | `GET /quest/1234/chain` integration test | Revert new handler files |
| 3 | Explorer panel | PR-1b | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert explorer panel files |
| 4 | NPC Inspector + Loot Object | PR-2a | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert properties panel files |
| 5 | Vendor/Condition/Inventory | PR-2b | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert properties + state files |
| 6 | Smart Waypoint Editor | PR-3a | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert graph panel files |
| 7 | Behavior Nodes | PR-3b | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert graph.lua + state |
| 8 | Escort Recorder + Combat | PR-3c | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert recorder + combat files |
| 9 | Spawn Scanner | PR-4a | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert database panel files |
| 10 | Grinding Area Generator | PR-4b | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert database panel + state |
| 11 | Auto Validation + Stats | PR-5a | `cargo test` + `luajit run_offline.lua` | N/A -- offline Lua tests | Revert shell.lua changes |
| 12 | Spawn Overlay + Travel | PR-5b | `luajit sentinel/tests/run_offline.lua` | N/A -- offline Lua tests | Revert overlay + travel files |

## Phase 0: Editor Crate Campaign CRUD (PR-0a)

- [x] 0.1 Create `campaign_store.rs` -- CampaignApi with list/load/save/delete under `.questing/campaigns/{slug}.json`
- [x] 0.2 Create `campaign_history.rs` -- CampaignCommand trait + 9 commands with apply()+inverse()
- [x] 0.3 Create `campaign_handlers.rs` -- Axum routes: campaign CRUD + node/edge CRUD + validate/compile/undo/redo
- [x] 0.4 Wire into `server.rs` -- add campaign_store to AppState, mount campaign route group
- [x] 0.5 Export in `lib.rs` -- pub mod campaign_store, campaign_history, campaign_handlers
- [x] 0.6 Write tests: tempfile store round-trips, undo/redo cycle, handler integration tests

## Phase 1: Explorer Panel (PR-1a + PR-1b)

- [x] 1.1 Add `GET /quest/{id}/chain` handler in `quest_chain.rs` -- prereqs, follow-ups, exclusive groups
- [x] 1.2 Add `GET /quest/{id}/objectives` handler -- parsed objectives with loot cross-refs
- [x] 1.3 Add `GET /zone/{id}/spawns` + `GET /spawns/density/{zone}` handlers
- [x] 1.4 Create `explorer_state.lua` -- view-model: search_query, results, selected, chain_data, filters, loading
- [x] 1.5 Create `explorer.lua` -- render: search bar, filter chips, split pane (list + detail)
- [x] 1.6 Register ExplorerBinding in `ide_panels.lua` with dispatch add-to-profile/add-chain/search/select
- [x] 1.7 Write Lua tests: panel build/reduce for search, select, chain viz, objective gen

## Phase 2: Properties Panel (PR-2a + PR-2b)

- [x] 2.1 Create `properties_state.lua` -- context-sensitive view-model tracking selected node type
- [x] 2.2 Add NPC Inspector (F10) view -- name, level, faction, loot, spawns, quests, vendor/trainer data
- [x] 2.3 Add Loot Object Editor (F14) view -- object type, spawns, respawn timer, skill req, loot table
- [x] 2.4 Add Vendor Editor (F11) view -- auto-import vendor items, per-item BuyRestock/AutoSell/Repair/Ignore
- [x] 2.5 Add Condition Editor (F16) view -- AND/OR/NOT tree with 20 condition types, add/remove/group
- [x] 2.6 Add Inventory Rules (F17) view -- per-item/category Destroy/Keep/Sell/Mail/Auction/Equip/Use/Ignore
- [x] 2.7 Register PropertiesBinding in `ide_panels.lua` -- dispatch for all property edits
- [x] 2.8 Write Lua tests: build/reduce for each view, no branches in render layer

## Phase 3: Graph Panel (PR-3a + PR-3b + PR-3c)

- [x] 3.1 Create `graph_state.lua` -- graph view-model with node list, selection, add/delete state
- [x] 3.2 Create `graph.lua` -- node list with inline params, add-node dropdown, delete, click to edit
- [x] 3.3 Add Waypoint Editor (F6) -- position copy, radius/wait/facing/move_type/stop_condition per waypoint
- [x] 3.4 Add Behavior Nodes (F7) -- 16 node types with inline display + Properties deep-edit link
- [x] 3.5 Create `escort_recorder.lua` (F15) -- recording mode toolbar, position polling, timeline gen
- [x] 3.6 Add Combat Area Editor (F18) -- pull_pos, safe_spot, LOS, max_pull, leash, blacklist chips
- [x] 3.7 Register GraphBinding in `ide_panels.lua` -- dispatch for graph operations
- [x] 3.8 Write Lua tests: build/reduce for waypoint reorder, node CRUD, escort timeline

## Phase 4: Database Panel (PR-4a + PR-4b)

- [x] 4.1 Create `database_state.lua` -- spawn scanner + grinding zone view-model
- [x] 4.2 Create `database.lua` -- nearby results grouped by entry, counts, distance, action buttons
- [x] 4.3 Add Spawn Scanner (F9) -- dbg.nearby() call, manual scan modes (herbs/mining/treasure/flight)
- [x] 4.4 Add Grinding Area Generator (F13) -- zone picker, spawn/density fetch, XP/gold estimate, route output
- [x] 4.5 Register DatabaseBinding in `ide_panels.lua` -- dispatch add-to-profile, open-inspector
- [x] 4.6 Write Lua tests: build/reduce for scan results, zone selection, route gen

## Phase 5: Shell Extensions (PR-5a + PR-5b)

- [x] 5.1 Create `spawn_overlay.lua` (F4) -- list-with-distance fallback, color-coded, toggle filters
- [x] 5.2 Extend `shell.lua` with F19 Auto Validation -- validate-on-save hook + toast with clickable diagnostics
- [x] 5.3 Extend `shell.lua` with F20 Profile Statistics -- badge chips: quest/wp/NPC counts, time/XP/gold estimates
- [x] 5.4 Add `POST /travel/route` handler in `travel_route.rs` -- multi-segment travel estimation
- [x] 5.5 Create Travel Editor (F12) -- route detection from node seq, segment display, edit controls
- [x] 5.6 Write tests: Rust integration for travel route, Lua tests for validation/stats/overlay
