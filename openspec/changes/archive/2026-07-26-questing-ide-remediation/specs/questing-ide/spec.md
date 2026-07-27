# Questing IDE Remediation — Delta Spec

**Change**: questing-ide-remediation | **Phase**: 2 — Spec | **Date**: 2026-07-26
**Baseline**: archived `2026-07-26-questing-profile-ide/02-spec.md` (F1–F20). Each requirement cites the F-number it completes, or `NEW` when diagnosis-driven. Scenarios marked **(RG)** are regression guards that would have FAILED with last cycle's bugs.
**Delta semantics**: no `openspec/specs/` exists, so all requirements are ADDED; they carry forward every still-unmet archived requirement. F5/F8/F21 remain deferred; F4 stays list-fallback.

---

## Capability: questing-ide

### ADDED Requirements — Foundations

### Requirement: QueryClient Wiring at Install (NEW)

`IdePanels.install(shell, deps)` MUST receive a QueryClient **table** (method-call contract: `qc:get_quest(id)`, `qc:get_npc(entry)`, …) in `deps.query_client`, supplied by `main.lua`. Binding docs MUST describe a table, not a resolver function. When `query_client` is absent, panels MUST render an explicit unavailable state — never silently idle.

#### Scenario: Install passes a live client (RG — main.lua:266 never passed one)
- GIVEN the IDE shell and a QueryClient bound to 127.0.0.1:3030
- WHEN `main.lua` installs the IDE panels
- THEN each data-driven binding's `_query_client` is that table
- AND an Explorer selection triggers a real `get_quest` call on the next tick

#### Scenario: Missing client is explicit
- GIVEN install deps without `query_client`
- WHEN a data panel ticks
- THEN its view shows "query server unavailable" (or equivalent) and no fetch is attempted

### Requirement: Async Pending Re-Arm (NEW)

When `QueryClient:_get` returns `(nil, true)` (request in flight), the calling state MUST keep or re-arm its dirty/pending flag so the next `on_tick` polls again. Flags clear ONLY on resolution: data stored, or error recorded in `state.error`. Clearing before the fetch completes is prohibited (today: `ide_panels.lua:337-338`, `database_state.lua:161-162`).

#### Scenario: Poll until resolved (RG — flags were cleared pre-fetch, panel froze on first pending)
- GIVEN an async client whose first call returns pending and second returns data
- WHEN a panel selects an entity and ticks twice
- THEN the first tick leaves the panel in a loading state and re-arms the flag
- AND the second tick stores the data and renders it

#### Scenario: Resolution with error
- GIVEN a fetch that resolves to nil with no pending flag after retries
- WHEN the tick observes the failed resolution
- THEN `state.error` names the failed lookup and the flag clears (no infinite pending)

### Requirement: Cross-Panel Selection Bus (NEW)

Selecting an entity in Explorer, Graph, or Database MUST publish a selection event `{kind, id}` on the shell's event channel. The Properties binding MUST subscribe and call `set_context(kind, id)` so the inspector view follows the selection. Selection MUST NOT remain panel-local.

#### Scenario: Database selection drives Properties (RG — inspector never updated)
- GIVEN both panels installed on one shell
- WHEN the user selects NPC entry 567 in the Database panel
- THEN Properties receives `{kind="npc", id=567}` and its view switches to the NPC Inspector context

### Requirement: Shell Supplies Player Position (NEW — completes F6-R2)

The shell's render `ctx` MUST include `ctx.player_position`, read nil-safely from `core.object_manager.get_local_player():get_position()` each frame. Panels consuming position (Graph waypoint capture, escort recorder, travel editor) MUST tolerate nil (position temporarily unavailable) without error.

#### Scenario: Waypoint capture gets a live position (RG — shell.lua:531 never set the field; travel_add_waypoint stubbed "requires player position")
- GIVEN the player is in-world at position P
- WHEN the Graph panel commits a waypoint
- THEN the captured waypoint position equals P (within float tolerance)

### Requirement: No Mock Data in Production Paths (NEW — completes F9)

Production code paths MUST NOT fabricate scan/detail/grind data. When a data source is unavailable in-game, the panel MUST set `state.error` describing the missing source. Mock fixtures MAY exist only behind an explicit test-harness flag unreachable from the installed client.

#### Scenario: Scan with no object manager (RG — `_mock_scan` ran in-game and showed fake wolves)
- GIVEN the IDE running in-game with `core.object_manager` unavailable
- WHEN the user triggers a spawn scan
- THEN `state.error` reports the unavailable source and `scan_results` stays empty

### ADDED Requirements — Explorer Panel (F1, F2, F3)

### Requirement: Key-Capture Text Input Widget (NEW — completes F1-R1/R2)

The widget set MUST provide a text input that, while focused, captures key events via `core.input` (no SDK widget exists): printable chars append at the caret, Backspace deletes, Enter submits, Escape cancels and restores the prior value, and focus loss releases key capture. Offline, the widget MUST accept injected key events through the same handler path.

#### Scenario: Typing edits the buffer (RG — no text entry existed; search was untypeable in-game)
- GIVEN a focused search input bound to Explorer state
- WHEN the sequence `w`, `o`, `l`, `f` is delivered, then Enter
- THEN the buffer equals "wolf" and a submit command fires with "wolf"

#### Scenario: Escape cancels
- GIVEN a focused input with original value "abc", buffer edited to "abcd"
- WHEN Escape is pressed
- THEN the buffer reverts to "abc" and no submit fires

### Requirement: Explorer Search-as-You-Type (completes F1-R1..R5, R8)

Typing MUST mark state dirty via `set_query`; the binding tick MUST debounce 300ms, then issue `GET /quests/search?q=`. Results MUST render a scrollable list with name, level, zone (from `QuestSummary.zone`), and faction. Selecting a result loads detail (objectives, giver/finisher names, chain refs) pending-aware per the async requirement.

#### Scenario: End-to-end search (RG — offline mocks resolved synchronously, hiding the pending path)
- GIVEN an async-pending harness client and server-shaped quest fixtures including `zone`
- WHEN the user types "wolf" and 300ms elapse
- THEN results list each quest's name, level, zone, faction
- AND selecting one populates the detail pane after the pending poll completes

### Requirement: Explorer Add-to-Profile and Add-Chain (completes F1-R6, F2-R6, F3)

`add_to_profile` MUST generate the subgraph AcceptQuest → objective nodes (Kill/Loot/Interact/Collect from `GET /quest/{id}/objectives`) → TurnInQuest and POST it to the editor client; `add_chain` MUST insert all quests from `GET /quest/{id}/chain`. Editor unreachable MUST surface in `state.error`. Generated nodes MUST be reviewable before commit (F3-R4/R6).

#### Scenario: Objective subgraph lands in campaign (RG — both commands returned "(not yet implemented)")
- GIVEN quest 1234 with kill(567×10) and loot(789×5) objectives and a live editor client
- WHEN the user confirms Add to Profile
- THEN the campaign contains AcceptQuest(1234), Kill(567,10), Loot(789,5), TurnInQuest(1234)

### ADDED Requirements — Graph Panel (F6, F7, F15, F18, F19, campaign lifecycle)

### Requirement: Graph Campaign Lifecycle (NEW)

`IdePanels.new_graph` MUST accept an editor client. The Graph empty state MUST expose an `action_label` (e.g. "New Campaign") that creates a campaign via `POST /editor/campaigns/{name}`; the panel MUST list campaigns (`GET /editor/campaigns/`) for open, and load one (`GET /editor/campaigns/{name}`) into graph state. All three operations MUST work from the empty state with no hand-edited files.

#### Scenario: Create from empty state (RG — zero Lua callers existed for :3031)
- GIVEN the Graph panel with no campaign loaded and the editor at :3031 up
- WHEN the user activates the empty-state action and names the campaign "stw"
- THEN a campaign "stw" exists on the editor and the panel shows an empty editable graph for it

#### Scenario: Open existing campaign
- GIVEN campaigns "a" and "b" on the editor
- WHEN the user opens the campaign list and picks "b"
- THEN the panel renders b's nodes and edges

### Requirement: Graph Node Editing and Validation (completes F7-R1..R5, F18, F19)

`edit_intent` MUST route the field edit through the editor client (`PUT /editor/campaigns/{name}/nodes/{id}`) and update local state from the returned graph. `validate_graph` MUST POST to `/editor/campaigns/{name}/validate` and render diagnostics in the validation bar; clicking a diagnostic navigates to the offending node (F19-R3). `compile_graph` MUST POST to `/editor/campaigns/{name}/compile` and surface the result. Combat-area metadata MUST persist on its node (F18-R3).

#### Scenario: Validate surfaces a diagnostic (RG — validate/compile were stubs)
- GIVEN a campaign with TurnInQuest(9) and no AcceptQuest(9)
- WHEN the user runs validate
- THEN the validation bar shows MISSING_ACCEPT naming node TurnInQuest(9)
- AND clicking it selects that node in the Graph panel

#### Scenario: Escort recording round-trip (F15)
- GIVEN escort mode active and a live player position stream
- WHEN the user walks a path and stops recording
- THEN generated Waypoint/Wait nodes reproduce the path and are editable like any other sequence

### ADDED Requirements — Properties Panel (F10, F11, F14, F16, F17)

### Requirement: Properties Context Views (completes F10, F11-R1/R2, F14, F16-R1/R4, F17-R1)

The panel MUST render five context views selected by the selection bus: **npc** (name, level, faction, classification, loot grouped by drop-chance bucket, starter/finisher quests, spawns), **vendor** (sells list as `{item_entry, name, price}` objects, repairs flag, per-item rule toggles), **object** (type, spawns, loot if lootable), **node** (payload fields per kind with validated edits), **condition/inventory** (condition tree with add/group/delete; inventory rules with add/clear). Fields absent from server types MUST NOT be rendered from fixtures.

#### Scenario: NPC Inspector shows server-shaped detail (RG — level/classification/loot/quests didn't exist in `NpcDetail`; panel rendered blanks)
- GIVEN an NPC selection and an extended `NpcDetail` from the server
- WHEN the inspector builds its view
- THEN level, classification, ≥1 loot bucket, and starter quests render with real values

#### Scenario: Vendor items show names and prices (RG — `VendorInfo.sells` was `Vec<u32>`; panel expected objects)
- GIVEN a vendor selection whose sells entries are `{item_entry, name, price}`
- WHEN the vendor view renders
- THEN each row shows the item name and price, and toggling a rule dispatches an editor update

#### Scenario: Condition tree mutation (RG — add_condition/group/delete were stubs)
- GIVEN a node context and the condition view
- WHEN the user adds a QuestComplete condition inside an AND group
- THEN the editor client receives the node update and the tree re-renders with the new leaf

### ADDED Requirements — Database Panel (F9, F13, render fixes)

### Requirement: Measured Text Rendering (NEW)

All panel layout that sizes to label text MUST use real measurement via `window:get_text_size` (or shell equivalent). The `CHAR_W = 7` px/char approximation (`database_state.lua:346`) MUST be removed. Entity names MUST render in full; button/chip widths MUST derive from measured text plus padding.

#### Scenario: Long NPC name fits its button (RG — names truncated, chips clipped)
- GIVEN a scan result named "Mangy Silvermane Patriarch"
- WHEN the database list renders
- THEN the full name is visible and its row width equals measured text width plus padding

### Requirement: Pending-Aware Detail View (NEW)

`view_detail`/`select_entry` MUST trigger the async load path. While a detail fetch is pending, the panel MUST show a loading state. It MUST NOT render "Entry N not found" for an entry whose fetch is in flight; that message is reserved for resolved 404s.

#### Scenario: Pending is not "not found" (RG — pending resolution fell through to the not-found branch)
- GIVEN a client whose detail fetch stays pending for two ticks
- WHEN the user views entry 567 detail
- THEN ticks 1–2 show loading, and the fetched detail renders on resolution

### Requirement: Spawn Scanner via Object Manager (completes F9-R1..R3)

Scans MUST enumerate creatures/objects via `core.object_manager` within the chosen range and filter (creature flags / object type per scan mode, F9-R4/R5). Results MUST group by entry with count, name, level, distance. Actions: `add_as_kill` posts a Kill node via the editor client; "Open in NPC Inspector" publishes to the selection bus; "Pin" feeds the F4 list-fallback overlay.

#### Scenario: In-game scan groups real units (RG — phantom `dbg.nearby` returned nothing in-game)
- GIVEN three spawned wolves (entry 567) within 50m
- WHEN the user runs a nearby scan
- THEN one grouped row shows entry 567, count 3, real name/level, nearest distance

### Requirement: Grinding Generator on Real Data (completes F13-R1/R2/R6)

`generate_grind`/`execute_grind` MUST query spawns by **map + position + radius** (`GET /spawns/nearby?map={id}&x={x}&y={y}&radius={r}` — user decision 2026-07-26: `creature` has map/position columns but no zoneId) through the query client, compute XP/kill and XP/hour from server fields, and output waypoints + Kill nodes + SellJunk/RepairEquipment via the editor client. Failures (server down, empty result set) MUST surface in `state.error`. `edit_grind_entry`/`edit_grind_zone` MUST open their respective editors.

#### Scenario: Position-anchored grind route generated (RG — grind data was silently mocked; edit_grind_* were placeholders)
- GIVEN the player position with wolf spawns within 100m from the server
- WHEN the user generates a grind route
- THEN the campaign gains a waypoint loop with Kill(567) nodes sourced from the response
- AND a server failure produces an error in `state.error`, never mock data

### ADDED Requirements — Shell Extensions (F12, F20)

### Requirement: Travel Editor and Stats Wiring (completes F12-R1/R2, F20-R1/R2)

`travel_add_waypoint` MUST capture `ctx.player_position`. The travel editor MUST estimate segments via `POST /travel/route` and display per-segment and total times. The stats dashboard MUST compute quest/waypoint/NPC/object/vendor/flight counts from the loaded campaign graph on save and render them as header badge chips.

#### Scenario: Travel estimate from live position (RG — travel_add_waypoint stubbed on missing position)
- GIVEN a campaign with waypoints in two zones and the player in-world
- WHEN the user adds a waypoint and requests estimates
- THEN the segment list shows walk/taxi times summing to the route total

---

## Capability: query-server

### ADDED Requirements

### Requirement: Extended Response Types (NEW — completes F1-R4, F10, F11-R1)

`query-types` MUST extend, with serde defaults for backward compatibility:

| Type | Added fields |
|------|-------------|
| `QuestSummary` | `zone: String` (zone name from `quest_template.ZoneOrSort`) |
| `NpcDetail` | `level: u8`, `classification: String` (normal/elite/rare/boss), `loot: Vec<LootEntry{item,name,drop_chance}>`, `quests: Vec<NpcQuestRef{quest_id,title,role:starter\|finisher}>` |
| `VendorInfo` | `sells: Vec<VendorItem{item_entry,name,price}>` (replaces `Vec<u32>`) |

#### Scenario: Panels consume extended NPC (RG — fields were absent; inspector blank)
- GIVEN creature 567 has level, elite classification, 3 loot rows, and starts quest 1234
- WHEN `GET /npc/567` is served
- THEN the JSON contains all four extended fields populated from `creature_template` + loot/quest joins

#### Scenario: Vendor sells objects
- GIVEN vendor 89 selling 2 items
- WHEN `GET /vendor/89` is served
- THEN `sells` is an array of objects each carrying `item_entry`, `name`, and `price` — never bare ids

### Requirement: GET /zone/{id}/spawns via spawn-zone index (completes F13-R1; archived §1.3 — AMENDED 2026-07-26)

`creature` has no zoneId and `creature_zone` is empty; zoneIds are derived from the extracted client data (`Emulators/Mangos - Classic TBC/extracted/`): a Python ETL (`sentinel/tools/regen_zone_catalog.py`, mirroring the regen_taxi_paths_catalog.py pattern) parses `maps/*.map` area-ID grids + `dbc/AreaTable.dbc` and emits committed catalogs — zone names/hierarchy AND a spawn→zone index covering all ~109k creature spawns. The endpoint MUST return `{zone_id, zone_name, creatures:[{entry,name,spawn_count,avg_level,classification,xp_reward}], objects:[{entry,name,spawn_count,type}]}` by joining the spawn-zone index with `creature` + `creature_template`. Unknown zone MUST return 404 with a body naming the id. `GET /spawns/density/{zone}` (archived §1.4) remains deferred — F13 grind uses position+radius (`/spawns/nearby`) instead.

#### Scenario: Zone aggregation (RG — endpoint missing; F13 had no data source)
- GIVEN zone 12 has 45 wolf (567) spawns averaging level 5
- WHEN `GET /zone/12/spawns` is called
- THEN the creatures array includes `{entry:567, spawn_count:45, avg_level:5}` and objects are grouped separately

### Requirement: POST /travel/route (completes F12-R2; archived §1.5)

MUST accept `{segments:[{from:{map,x,y,z}, to:{map,x,y,z}} | {type:"taxi", from_node, to_node}]}` and return `{segments:[{type, distance_m?, estimated_s}], total_s}`. It extends, not replaces, `/travel/estimate`.

#### Scenario: Mixed walk+taxi route
- GIVEN a two-segment request (walk then taxi)
- WHEN the route is posted
- THEN each segment reports `estimated_s` and `total_s` equals their sum

---

## Capability: questing-editor

### ADDED Requirements

### Requirement: Campaign Lifecycle Contract for the Lua Client (NEW)

The mounted `/editor/campaigns/` surface MUST serve the shapes the Lua client consumes: `GET /` → `Vec<CampaignSummary{name, node_count}>`; `GET /{name}` → `CampaignGraph`; `POST /{name}` with a `CampaignGraph` body → `{success:bool}` (create-or-save); load of an unknown name → 404. The Lua editor client MUST speak exactly these shapes.

#### Scenario: Create → list → open round-trip (RG — Rust CRUD complete but never exercised by a caller)
- GIVEN no campaign "stw"
- WHEN the Lua client creates "stw" with one Kill node, lists campaigns, then opens "stw"
- THEN the list contains "stw" with node_count 1 and the open returns that exact graph

### Requirement: Placeholder Commands Wired End-to-End (NEW — completes F2, F3, F7, F9, F16, F17)

The six Lua placeholder command families MUST route through the editor client and update local state from returned graphs: `add_to_profile` (subgraph insert), `add_chain` (chain insert), `edit_intent` (node field update), `add_as_kill` (Kill node insert), `add_condition`/`add_condition_group`/`delete_condition` (condition tree mutations), `add_inventory_rule` (rule insert). Each MUST surface editor errors in the issuing panel's `state.error` rather than returning a success string.

#### Scenario: Editor error surfaces (RG — stubs returned success text)
- GIVEN the editor at :3031 is down
- WHEN the user issues `add_as_kill` for entry 567
- THEN the Database panel's `state.error` names the failed write and no phantom node appears

### Requirement: Validate and Compile as Invoked from Graph (completes F19-R1)

`POST /editor/campaigns/{name}/validate` MUST return `Vec<Diagnostic{code, message, node_id?}>` covering archived rules V1–V11; `POST .../compile` MUST return a `CompileResult`. The Graph panel MUST trigger validate automatically on every save (F19-R1) and render diagnostics as a toast + bar with node navigation.

#### Scenario: Save triggers validation toast (RG — auto-validate never ran)
- GIVEN a campaign saved with a BROKEN_CHAIN violation
- WHEN the save completes
- THEN a toast reports failure and the validation bar lists the diagnostic with its node id

---

## Verification Requirements (cross-cutting, NEW)

### Requirement: Async-Pending Mock Mode in Offline Harness

The Sylvannas API mock MUST provide an `http_get` whose default mode returns `(nil, true)` pending for N ticks before resolving, configurable per test. The offline suite MUST include at least one test per data panel that asserts re-arm behavior: flag survives the pending tick, data lands on resolution tick.

#### Scenario: Harness reproduces the runtime fetch model (RG — old harness had no `http_get`; pending path never executed offline)
- GIVEN the mock configured to resolve after 2 ticks
- WHEN an Explorer selection test ticks 3 times
- THEN tick 1 shows loading, tick 3 shows data — and the same test fails against clear-before-fetch code

### Requirement: Server-Shaped Fixtures

Lua fixtures MUST mirror query-types JSON exactly (extended `NpcDetail`/`QuestSummary`/`VendorInfo` included). A fixture-shape test MUST assert fixture keys match the Rust field names (snake_case serde), so panel expectations cannot drift from server types again.

#### Scenario: Drift detected
- GIVEN a fixture for `VendorInfo` using bare-id `sells`
- WHEN the fixture-shape test runs
- THEN it fails, naming `sells` and the expected object shape

### Requirement: Real-Server Smoke Test

A smoke script MUST run against live QueryServer (:3030) and Editor (:3031), checking: health; `GET /quests/search` returns zoned summaries; `GET /npc/{entry}` returns extended fields; `GET /zone/{id}/spawns` aggregates via the spawn-zone index; `GET /spawns/nearby` returns position-filtered results; `POST /travel/route` totals; editor create/list/open/validate round-trip. It MUST fail loudly per check and be a required gate before archive.

#### Scenario: Smoke catches a dead backend (RG — the check the previous cycle never ran)
- GIVEN QueryServer down
- WHEN the smoke script runs
- THEN it exits non-zero naming :3030 before any panel claim is made
