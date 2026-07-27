# Questing Profile IDE — Delta Spec

**Change**: questing-profile-ide | **Phase**: 2 — Spec | **Date**: 2026-07-26
**Inherits**: Every requirement from proposal §Features Detail, tightened and completed here.
**Delivery**: 12 chained PRs (Phases 0–5), 400-line budget each.

## 1. Data Contracts — New QueryServer Endpoints

### 1.1 GET /quest/{id}/chain (PR-1a)

Returns prerequisite + follow-up chains for a quest. Used by F2.

```json
// Response
{
  "quest_id": 1234,
  "prerequisites": [{"quest_id": 567, "name": "Preceding Quest", "exclusive_group": 0}],
  "follow_ups": [{"quest_id": 890, "name": "Follow-up Quest", "exclusive_group": 0}],
  "chain_depth": 3,
  "branches": [{"quest_id": 891, "name": "Branch Quest", "exclusive_group": 1}]
}
```

`exclusive_group` > 0 means quests sharing that group are mutually exclusive. Implementation: SQL JOIN on `quest_template.PrevQuestId`, `quest_template.NextQuestId`, `quest_template.ExclusiveGroup`.

### 1.2 GET /quest/{id}/objectives (PR-1a)

Returns parsed objectives with loot template cross-references. Used by F3.

```json
// Response
{
  "quest_id": 1234,
  "objectives": [
    {"type": "kill", "entry": 567, "name": "Wolf", "count": 10, "loot_items": [{"item": 123, "name": "Pelt", "drop_chance": 0.35}]},
    {"type": "loot", "entry": 789, "name": "Pelt", "count": 5, "source_creatures": [567]},
    {"type": "interact", "entry": 901, "name": "Quest Object"},
    {"type": "collect", "entry": 234, "name": "Herb", "count": 6}
  ],
  "objective_text": "Kill 10 wolves, loot 5 pelts"
}
```

Implementation: Read `quest_template.ObjectiveText1-4`, `quest_template.RequiredNpcOrGo1-4`, `quest_template.RequiredNpcOrGoCount1-4`, cross-reference `creature_loot_template` / `gameobject_loot_template`.

### 1.3 GET /zone/{id}/spawns (PR-1a)

Aggregated spawn data per zone. Used by F13.

```json
// Response
{
  "zone_id": 100,
  "zone_name": "Elwynn Forest",
  "creatures": [
    {"entry": 567, "name": "Wolf", "spawn_count": 45, "avg_level": 5, "classification": "normal", "xp_reward": 70}
  ],
  "objects": [
    {"entry": 234, "name": "Peacebloom", "spawn_count": 30, "type": "herb"}
  ]
}
```

Implementation: SQL JOIN `creature` + `spawns_creature` + `creature_template` grouped by `zone_id`.

### 1.4 GET /spawns/density/{zone} (PR-1a)

Density map for a zone. Used by F13 route generation.

```json
// Response
{
  "zone_id": 100,
  "density_regions": [
    {"min_level": 1, "max_level": 5, "density_per_km2": 12.5, "avg_xp_per_hour": 8400}
  ],
  "safe_spots": [{"x": -8945.0, "y": 520.0, "z": 29.0, "distance_from_spawns": 80.0}]
}
```

### 1.5 POST /travel/route (PR-5b)

Multi-segment travel estimation. Enhanced from existing `/travel/estimate`.

```json
// Request
{
  "segments": [
    {"from": {"map": 0, "x": -8945, "y": 520, "z": 29}, "to": {"map": 0, "x": -9130, "y": 420, "z": 75}},
    {"type": "taxi", "from_node": 10, "to_node": 42}
  ]
}
// Response
{
  "segments": [
    {"type": "walk", "distance_m": 250, "estimated_s": 120},
    {"type": "taxi", "estimated_s": 45}
  ],
  "total_s": 165
}
```

PR phase: PR-1a for GET endpoints, PR-5b for POST /travel/route.

## 2. Data Contracts — Editor Crate Campaign CRUD (Phase 0)

All endpoints under `/editor/campaigns/`. Each wraps in `CommandHistory` (50-depth, existing pattern). New Campaign model mirrors the graph-based format from `sentinel_models::campaign::CampaignGraph`.

### 2.1 Campaign CRUD

| Method | Path | Purpose | Request Body | Response |
|--------|------|---------|-------------|----------|
| GET | `/editor/campaigns/` | List campaigns | — | `Vec<CampaignSummary>` |
| GET | `/editor/campaigns/{name}` | Load campaign graph | — | `CampaignGraph` |
| POST | `/editor/campaigns/{name}` | Create/save campaign | `CampaignGraph` | `{ success: bool }` |
| GET | `/editor/campaigns/{name}/history` | History status | — | `{ can_undo, can_redo, ... }` |
| POST | `/editor/campaigns/{name}/undo` | Undo | — | `{ description }` |
| POST | `/editor/campaigns/{name}/redo` | Redo | — | `{ description }` |

### 2.2 Node CRUD

| Method | Path | Request | Response |
|--------|------|---------|----------|
| POST | `/editor/campaigns/{name}/nodes` | `CampaignNode` | `CampaignGraph` (updated) |
| PUT | `/editor/campaigns/{name}/nodes/{id}` | `CampaignNode` | `CampaignGraph` |
| DELETE | `/editor/campaigns/{name}/nodes/{id}` | — | `CampaignGraph` |

### 2.3 Edge CRUD

| Method | Path | Request | Response |
|--------|------|---------|----------|
| POST | `/editor/campaigns/{name}/edges` | `{ source_id, target_id, condition? }` | `CampaignGraph` |
| DELETE | `/editor/campaigns/{name}/edges/{id}` | — | `CampaignGraph` |

### 2.4 Compile / Validate

| Method | Path | Response |
|--------|------|----------|
| POST | `/editor/campaigns/{name}/validate` | `Vec<Diagnostic>` (wraps existing `sentinel_validator`) |
| POST | `/editor/campaigns/{name}/compile` | `CompileResult` (wraps existing `sentinel_compiler`) |

### 2.5 CampaignNode Payload Types

Each node has a `kind` discriminator and a type-specific `payload`:

| kind | payload fields | PR |
|------|---------------|----|
| `AcceptQuest` | `quest_id: u32` | 1b |
| `TurnInQuest` | `quest_id: u32, npc_entry: u32` | 1b |
| `Kill` | `creature_entry: u32, count: u32, tag: Option<String>` | 1b |
| `Loot` | `item_entry: u32, count: u32` | 1b |
| `Interact` | `object_entry: u32` | 1b |
| `Waypoint` | `position, radius: f32, wait_s: f32, facing: Option<f32>, move_type: Walk\|Run\|Swim\|Fly\|Dismount, stop_condition: OnAggro\|OnInteract\|OnTimer(f32)\|Always` | 3a |
| `UseItem` | `item_entry: u32, target: Option<NpcEntry\|ObjectEntry>` | 3b |
| `RepairEquipment` | `vendor_entry: u32, threshold: f32` | 3b |
| `SellJunk` | `vendor_entry: u32, filter: Option<Quality\|ItemSubclass>` | 2b |
| `BuyItem` | `vendor_entry: u32, item_entry: u32, count: u32` | 2b |
| `TrainSkill` | `trainer_entry: u32` | 2b |
| `SetHearthstone` | — | 3b |
| `UseHearthstone` | — | 3b |
| `SetTaxiPath` | `from_node: u32, to_node: u32` | 5b |
| `Wait` | `duration_s: Option<f32>, condition: Option<Condition>` | 3b |
| `CombatArea` | `pull_position, safe_spot: Option<Position>, los_positions: Vec<Position>, max_pull_count: u32, leash_radius: f32, blacklisted_areas: Vec<Polygon>` | 3c |
| `Condition` | `expression: String, role: Entry\|Completion\|Sticky` | 2b |
| `InventoryRule` | `item_entry: u32, rule: Destroy\|Keep\|Sell\|Mail\|Auction\|Equip\|Use\|Ignore, quality_filter: Option<u32>, ilvl_min: Option<u32>, ilvl_max: Option<u32>, class_mask: Option<u32>` | 2b |
| `VendorRule` | `item_entry: u32, rule: BuyRestock\|AutoSell\|Repair\|Ignore, threshold: Option<u32>` | 2b |

## 3. Requirements by Feature

### F1 — Quest Browser (PR-1b, Explorer panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F1-R1 | Search quests by name substring via existing `/quests/search?q={query}` | MUST |
| F1-R2 | Debounce search input by 300ms before sending request | MUST |
| F1-R3 | Filter results by zone, level range, faction, quest type (elite/dungeon/raid/pvp/daily) | SHOULD |
| F1-R4 | Display a scrollable list of matching quests with name, level, zone, faction | MUST |
| F1-R5 | Show QuestDetail on select: objectives, rewards (XP/gold/items), prerequisites, giver/finisher NPC names, chain info | MUST |
| F1-R6 | "Add to Profile" generates a Campaign subgraph: AcceptQuest → Kill/Loot (from objectives) → TurnInQuest nodes | MUST |
| F1-R7 | Giver/finisher NPC names resolved from `creature_template` via QueryServer | MUST |
| F1-R8 | Quest type filter values mapped from `quest_template.QuestFlags` + `ZoneOrSort > 0` | SHOULD |

**Scenario**: User searches "wolves" → debounce fires after 300ms → results show quests with "wolf" in title → user selects one → detail pane loads with objectives, NPC names, chain info → user clicks "Add to Profile" → subgraph created in active campaign.

### F2 — Quest Chain Visualization (PR-1b, Explorer panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F2-R1 | Render prerequisite tree as indented list with depth badges | MUST |
| F2-R2 | Render follow-up branches indented below current quest | MUST |
| F2-R3 | Show `ExclusiveGroup` markers for mutually exclusive branches | SHOULD |
| F2-R4 | Show quest flags: auto-accept, daily, repeatable, raid | SHOULD |
| F2-R5 | "Add entire chain to profile" inserts all connected nodes | MAY |
| F2-R6 | Chain data sourced from new GET /quest/{id}/chain endpoint | MUST |

**Scenario**: User selects quest 1234 → chain panel shows depth-3 prerequisite tree → "Add entire chain" button enabled → user clicks → 4 quests added as subgraph nodes.

### F3 — Objective Generator (PR-1b, Explorer panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F3-R1 | Read quest_template objectives via GET /quest/{id}/objectives | MUST |
| F3-R2 | Cross-reference creature_loot_template + gameobject_loot_template for each objective | MUST |
| F3-R3 | Auto-generate Kill/Loot/Interact/Collect nodes matching each objective | MUST |
| F3-R4 | Show generated nodes for user review before committing to campaign | MUST |
| F3-R5 | Wire implicit AcceptQuest + TurnInQuest at start and end of generated sequence | MUST |
| F3-R6 | User can edit counts, entries, or remove individual generated nodes before save | SHOULD |

**Scenario**: Quest "Kill 10 wolves, loot 5 pelts" → objectives endpoint returns kill(wolf, entry=567, count=10) + loot(pelt, 789, 5) → generator shows 4 nodes: AcceptQuest, Kill(567,10), Loot(789,5), TurnInQuest → user reviews and confirms → nodes added to campaign.

### F4 — Spawn Overlay (PR-5b, Shell — FALLBACK RISK)

| ID | Requirement | Strength |
|----|-----------|----------|
| F4-R1 | If Sylvannas render callback supports world-space drawing, render spawn points as 3D markers | SHOULD |
| F4-R2 | Fallback: list view with distance, direction arrow, minimap pin if no render callback | MUST |
| F4-R3 | Color scheme: green=creatures, blue=objects, red=quest bosses, purple=escort NPCs | SHOULD |
| F4-R4 | Filter overlay by entry ID, level range, faction, type | SHOULD |
| F4-R5 | Toggle overlay categories on/off independently | SHOULD |

**Risk marker**: F4 depends on Sylvannas render callback investigation. If unavailable, reduce to list-only view. **Do not implement 3D overlay until render callback capability confirmed** — validate in PR-5a before PR-5b work begins.

### F6 — Smart Waypoint Editor (PR-3a, Graph panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F6-R1 | Display waypoint list with position, radius, wait time, facing direction, movement type | MUST |
| F6-R2 | "Copy current position" button copies player location from `player:get_position()` | MUST |
| F6-R3 | Per-waypoint properties: radius tolerance (default 3), wait time (default 0), facing, movement type | MUST |
| F6-R4 | Movement type options: Walk / Run / Swim / Fly / Dismount | MUST |
| F6-R5 | Stop condition options: OnAggro / OnInteract / OnTimer(duration) / Always | MUST |
| F6-R6 | Drag-to-reorder waypoints in the list | SHOULD |
| F6-R7 | Waypoints rendered as `questing.Waypoint` node type in Campaign graph | MUST |

### F7 — Behavior Nodes (PR-3b, Graph panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F7-R1 | Visual editor for Campaign graph node types (see §2.5 payload table) | MUST |
| F7-R2 | Each node shows key parameters inline (e.g. Kill shows creature entry + count) | MUST |
| F7-R3 | Clicking a node opens deep edit in the Properties panel | MUST |
| F7-R4 | Supported node types: Move, AcceptQuest, TurnInQuest, Kill, Loot, Interact, UseItem, RepairEquipment, SellJunk, BuyItem, TrainSkill, LearnSpell, SetTaxiPath, SetHearthstone, UseHearthstone, Wait | MUST |
| F7-R5 | Node parameters validated on save: required fields non-empty, numeric fields non-negative | MUST |

### F9 — Spawn Scanner (PR-4a, Database panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F9-R1 | Call `dbg.nearby(range, filter)` to scan creatures and objects in-game | MUST |
| F9-R2 | Group results by entry ID with count, name, level, distance | MUST |
| F9-R3 | Actions: "Add to profile as Kill node", "Add as Interact node", "Open in NPC Inspector", "Pin to Spawn Overlay" | MUST |
| F9-R4 | Manual scan modes: scan herbs, mining, treasure, flight masters, innkeepers | SHOULD |
| F9-R5 | Each scan mode filters by game object type or creature flags | SHOULD |

### F10 — NPC Inspector (PR-2a, Properties panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F10-R1 | Display NPC name, level, faction, classification (elite/rare/boss/normal) | MUST |
| F10-R2 | Show health, mana, armor, damage from creature_template | MUST |
| F10-R3 | Show spawn positions from `spawns/{type}/{entry}` | MUST |
| F10-R4 | Show loot table grouped by drop chance bucket (>50%, >10%, >1%, <1%) | MUST |
| F10-R5 | Show quests that involve this NPC (QuestStarter, QuestFinisher) | MUST |
| F10-R6 | Show vendor inventory if NPC is vendor, trainer spells if trainer | MUST |

### F11 — Vendor Editor (PR-2b, Properties panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F11-R1 | Auto-import vendor inventory from `creature_vendor` table via QueryServer | MUST |
| F11-R2 | Per-item rules: BuyRestock (qty threshold), AutoSell, Repair (threshold %), Ignore | MUST |
| F11-R3 | Rules stored as `InventoryRule` / `VendorRule` nodes in campaign | MUST |

### F12 — Travel Editor (PR-5b, Shell)

| ID | Requirement | Strength |
|----|-----------|----------|
| F12-R1 | Detect known travel routes from node sequence: taxi paths, zeppelin/crossings, portals, hearthstone, meeting stones, dungeon/raid entrances | MUST |
| F12-R2 | Display estimated travel time per segment using POST /travel/route | MUST |
| F12-R3 | Allow editing segments: add wait, change route, insert waypoint | SHOULD |

### F13 — Grinding Area Generator (PR-4b, Database panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F13-R1 | User selects zone → generator queries GET /zone/{id}/spawns + /spawns/density/{zone} | MUST |
| F13-R2 | Compute expected XP per kill and per hour using creature_template base XP × spawn count | MUST |
| F13-R3 | Identify safe spots (low-spawn density coordinates from density endpoint) | SHOULD |
| F13-R4 | Compute pull radius for efficient looping | SHOULD |
| F13-R5 | Estimate gold from vendor loot using npc_vendor × item_sell_price | SHOULD |
| F13-R6 | Output: grinding route with waypoints + Kill nodes + SellJunk + RepairEquipment | MUST |

### F14 — Loot Object Editor (PR-2a, Properties panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F14-R1 | Display game object type, map/position of known spawns, respawn timer, interaction radius, required skill | MUST |
| F14-R2 | Show loot table if game object is lootable (herbs, mining veins, chests) | MUST |
| F14-R3 | Edit as part of `questing.Interact` node via Properties panel | MUST |

### F15 — Escort Quest Recorder (PR-3c, Graph panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F15-R1 | Recording mode activated from Graph panel toolbar | MUST |
| F15-R2 | Log NPC position, pauses, combat engagements, failure conditions with timestamp during recording | MUST |
| F15-R3 | After stopping, generate waypoints + Wait nodes + trigger conditions reproducing the escort path | MUST |
| F15-R4 | Recorded timeline editable like any other waypoint sequence | MUST |
| F15-R5 | Recording uses in-game position polling (not W12 system) | MUST |

### F16 — Condition Editor (PR-2b, Properties panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F16-R1 | Every node/edge supports condition guards | MUST |
| F16-R2 | Supported conditions: QuestComplete, QuestNotComplete, HasItem, LevelAtLeast, LevelAtMost, GoldAtLeast, Reputation, ClassIs, RaceIs, KnowsSpell, SkillAtLeast, InZone, HasBuff, HasProfession, IsOutdoor, IsDungeon, IsRaid, PartySize, PartyHasClass, DailyQuestDone | MUST |
| F16-R3 | Conditions compose as AND/OR/NOT trees | MUST |
| F16-R4 | Condition editor shows tree with add/remove/group operations | MUST |

### F17 — Inventory Rules (PR-2b, Properties panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F17-R1 | Per-item or per-category rules: Destroy, Keep, Sell, Mail, Auction, Equip, Use, Ignore | MUST |
| F17-R2 | Optional filters: item quality, item level range, slot, class mask | SHOULD |
| F17-R3 | Rules stored as `InventoryRule` nodes in campaign | MUST |

### F18 — Combat Area Editor (PR-3c, Graph panel)

| ID | Requirement | Strength |
|----|-----------|----------|
| F18-R1 | Define combat zone per node/waypoint with: pull position, safe spot, LOS positions, max pull count, leash radius, blacklisted areas | MUST |
| F18-R2 | Rendered as tooltip on Graph node entry with quick-edit chips | MUST |
| F18-R3 | Combat area data stored as node metadata (runtime consumption deferred to future change) | MUST |

### F19 — Auto Validation (PR-5a, Shell)

| ID | Requirement | Strength |
|----|-----------|----------|
| F19-R1 | Runs automatically on every save via POST /editor/campaigns/{name}/validate | MUST |
| F19-R2 | Validation results appear as toast with pass/fail + clickable diagnostics | MUST |
| F19-R3 | Clickable diagnostic navigates to offending node in Graph panel | MUST |

Validation rules (all MUST):

| Rule | Check | Error Code |
|------|-------|-----------|
| V1 | For every TurnInQuest, corresponding AcceptQuest must exist in campaign | MISSING_ACCEPT |
| V2 | For every accepted quest, corresponding TurnInQuest must exist | MISSING_TURNIN |
| V3 | NPC entry referenced by AcceptQuest/TurnInQuest must exist in `creature_template` | INVALID_NPC |
| V4 | Item entry in Loot/UseItem nodes must exist in `item_template` | INVALID_ITEM |
| V5 | Object entry in Interact nodes must exist in `gameobject_template` | INVALID_OBJECT |
| V6 | Quest prerequisite from PrevQuestId not present as AcceptQuest in profile | BROKEN_CHAIN |
| V7 | Sequential waypoints with no path between them (distance > leash but no travel segment) | UNREACHABLE_WP |
| V8 | Graph edges forming a cycle (DFS cycle detection on node graph) | CIRCULAR_PATH |
| V9 | Quest level requirement > profile max_level or < profile min_level | LEVEL_MISMATCH |
| V10 | Duplicate node IDs in campaign | DUPLICATE_NODE |
| V11 | Action payload missing required fields per node kind (§2.5) | MISSING_FIELD |

### F20 — Profile Statistics (PR-5a, Shell)

| ID | Requirement | Strength |
|----|-----------|----------|
| F20-R1 | Compute on save and display as badge chips in shell header bar | MUST |
| F20-R2 | Stats shown: quest count, waypoint count, unique NPCs, unique objects, vendors, flight masters | MUST |
| F20-R3 | Estimated total completion time (travel estimates + kill count × expected kill time) | SHOULD |
| F20-R4 | Estimated total XP (sum of quest rewards + kill XP) | SHOULD |
| F20-R5 | Estimated total gold (quest rewards + vendor loot) | SHOULD |

## 4. Non-Goals (Explicitly Deferred)

| Item | Reason | Target |
|------|--------|--------|
| Canvas-based graph editor (drag nodes, edge drawing, zoom/pan) | Complexity too high for constrained UI canvas | v2 |
| Visual route on world map overlay | Depends on Sylvannas render callback (F4 investigation needed) | v2 |
| Profile Simulator (TPS/DPS/HPS estimates) | Partial exists; full simulation out of scope | v2 |
| Copy/paste nodes and subgraphs | v2 feature | v2 |
| Multi-select operations | v2 feature | v2 |
| Undo/redo UI buttons | API exists (CommandHistory), no UI needed yet | v2 |
| Blueprint library / profile templates | v2 feature | v2 |
| Auto-load last-used profile | UX polish, not functional | v2 |
| Concurrent editing (two IDE sessions) | Last-writer-wins, documented single-user assumption | v2 |
| Combat area runtime consumption (F18) | Authoring metadata only; runtime integration deferred | v2 |

## 5. PR Phase Mapping Summary

| PR | Features | Dependencies | New Endpoints |
|----|----------|-------------|---------------|
| **0a** | Editor Campaign CRUD | None | `/editor/campaigns/*` endpoints |
| **1a** | QueryServer endpoints | None | GET /quest/{id}/chain, /quest/{id}/objectives, /zone/{id}/spawns, /spawns/density/{zone} |
| **1b** | F1 Quest Browser, F2 Chain Viz, F3 Objective Generator | 0a, 1a | — |
| **2a** | F10 NPC Inspector, F14 Loot Object Editor | 0a | — |
| **2b** | F11 Vendor Editor, F16 Condition Editor, F17 Inventory Rules | 0a, 2a | — |
| **3a** | F6 Smart Waypoint Editor | 0a | — |
| **3b** | F7 Behavior Nodes | 3a | — |
| **3c** | F15 Escort Recorder, F18 Combat Area Editor | 3a | — |
| **4a** | F9 Spawn Scanner | 0a | — |
| **4b** | F13 Grinding Area Generator | 1a, 4a | — |
| **5a** | F19 Auto Validation, F20 Profile Statistics | 0a | POST /editor/campaigns/{name}/validate |
| **5b** | F4 Spawn Overlay (fallback), F12 Travel Editor | 1a | POST /travel/route |

## 6. Key Constraints

1. **Empty slots pattern**: Explorer, Graph, Properties, Database panels follow `panel_state.lua` → `panel.lua` → `ide_panels.lua` → `register_panel()` exactly as Runner does.
2. **No branches in render layer**: `panel.lua` files contain no `if`/`else`/`while` branches (enforced by test scan).
3. **Reads from QueryClient**: All read data via existing Lua HTTP QueryClient with caching.
4. **Writes via editor crate**: All mutations through HTTP to editor crate port 3031.
5. **400-line PR budget**: Each PR targets ~400 lines. Use auto-chain when exceeding.
6. **Backward compat**: Old Project API endpoints remain untouched.
