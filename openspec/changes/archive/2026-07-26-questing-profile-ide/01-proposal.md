# Proposal: Questing Profile IDE

**Change**: questing-profile-ide | **Date**: 2026-07-26 | **Store**: openspec

## Problem Statement

The in-game IDE has five declared tab slots (`runner`, `explorer`, `graph`, `properties`, `database`) but only `runner` is implemented — it shows quest execution status. Creating or editing quest profiles requires either hand-writing JSON in the old `.profile.json` format or importing RestedXP guides. Profile authors cannot browse quests, visualize chains, inspect NPCs, edit behaviors visually, or auto-generate objectives from database data. The editor's Rust HTTP API (:3031) persists projects and compiles profiles, but the entire authoring surface is missing.

## Vision

Turn the in-game IDE into a WoW questing IDE. The authoring workflow is:

**Discover** quests and NPCs via the QueryServer database → **Record** gameplay via W12 (existing) → **Auto-fill** objectives from `quest_template` + `creature_loot_template` → **Adjust** behavior with visual editors (waypoints, conditions, combat areas) → **Save** with automatic validation.

The IDE becomes the primary authoring tool — RestedXP import remains for bulk conversion, but day-to-day profile creation and tweaking happens in-game.

## Scope

### In Scope

17 features across 4 panels + shell extensions, matching the existing but-empty IDE tab slots:

| Panel | Tab Slot | Features |
|-------|----------|----------|
| Explorer | `explorer` | Quest Browser (F1), Quest Chain Visualization (F2), Objective Generator (F3) |
| Graph | `graph` | Smart Waypoint Editor (F6), Behavior Nodes (F7), Escort Quest Recorder (F15), Combat Area Editor (F18) |
| Properties | `properties` | NPC Inspector (F10), Vendor Editor (F11), Condition Editor (F16), Inventory Rules (F17), Loot Object Editor (F14) |
| Database | `database` | Spawn Scanner (F9), Grinding Area Generator (F13) |
| Shell | (cross-cutting) | Spawn Overlay (F4), Travel Editor (F12), Auto Validation (F19), Profile Statistics (F20) |

### Not In Scope (Explicitly Deferred)

- **F5 Live Recording** — already exists as W12 (record → resolve → run pipeline). No new work needed.
- **F8 Visual Route Editor** — deferred. The first version of the Graph panel is node-list based, not a full canvas map overlay. A visual route on the world map would require Sylvannas render callback capabilities that need separate investigation.
- **F21 Profile Simulator** — partially exists (resolver validates, runtime can dry-run, validator catches issues). A full TPS/simulator that estimates DPS, HPS, and kill times is deferred to a separate change.
- **Docking layouts, multi-select, copy/paste, drag-drop graph canvas** — all v2 candidates. First version uses list-based interaction.

## Features Detail

### Explorer Panel (`explorer`)

**F1 Quest Browser**: Browse and search quests from `tbcmangos.sqlite` via existing QueryServer endpoints (`/quests/search`, `/quest/{id}`). Display quest level, faction (alliance/horde/both), zone, rewards (item/XP/gold/reputation), objectives, prerequisites, follow-up chains. Filter by zone, level range, faction, quest type (elite/dungeon/raid/pvp). Results in a scrollable list with search-as-you-type.

**F2 Quest Chain Visualization**: For a selected quest, render prerequisite and follow-up trees as an indented tree in the panel. Show breadcrumbs (chain depth), branching paths, exclusive group members (quests that share the same `ExclusiveGroup`), and quest flags (auto-accept, daily, repeatable). Allow "Add entire chain to profile" as a single action.

**F3 Objective Generator**: Given a quest ID, read `quest_template` objectives and cross-reference `creature_loot_template` + `gameobject_loot_template` to auto-generate Kill/Loot/Interact/Collect objective nodes. Example: quest "Kill 10 wolves and loot 5 pelts" → generates questing.Kill (creature entry for wolf, count=10) + questing.Loot (item entry for pelt, count=5) + implicit AcceptQuest + TurnInQuest nodes. User can review and edit before committing.

### Graph Panel (`graph`)

**F6 Smart Waypoint Editor**: Waypoint list with behavior properties per waypoint: position (copied from player location or typed), radius tolerance, wait time, facing direction, movement type (walk/run/swim/fly/dismount), stop conditions (OnAggro/OnInteract/OnTimer/Always). Drag to reorder. Waypoints are rendered as the `questing.Waypoint` node type in the Campaign graph.

**F7 Behavior Nodes**: Visual editor for the behavior tree portion of a Campaign graph. Supported node types: Move (waypoint list or coordinates), AcceptQuest, TurnInQuest, Kill (creature entry + count + optional tag), Loot (item entry + count), Interact (object entry), UseItem, RepairEquipment (vendor + threshold), SellJunk (vendor + filter), BuyItem (vendor + item + count), TrainSkill (trainer NPC), LearnSpell, SetTaxiPath (from/to flight master), SetHearthstone, UseHearthstone, Wait (duration or condition). Each node shows its key parameters inline. Clicking a node opens deep edit in the Properties panel.

**F15 Escort Quest Recorder**: Special recording mode for escort quests. Activated from the Graph panel toolbar. While recording, every NPC pause, combat engagement, and failure condition is logged with a timestamp and position. After recording, the mode generates waypoints + Wait nodes + trigger conditions that reproduce the escort path. The recorded timeline is editable like any other waypoint sequence.

**F18 Combat Area Editor**: Define combat zones per node or waypoint. Properties: preferred pull position (single coordinate), safe spot (where to stand while ranged), LOS positions (where to break line of sight if needed), max pull count (stop pulling after N adds), leash radius (don't chase beyond this), blacklisted areas (regions to never enter during this fight). Rendered as a tooltip on the Graph panel's node entry with quick-edit chips.

### Properties Panel (`properties`)

*Context-sensitive: shows details of whatever is selected in the active panel (Explorer, Graph, or Database).*

**F10 NPC Inspector**: For a selected NPC entry: display name, level, faction, classification (elite/rare/boss/normal), health, mana, armor, damage, flags, position data (spawn points from `spawns/{type}/{entry}`), loot table (grouped by drop chance), quests that involve this NPC, vendor inventory if vendor, trainer spells if trainer. All data sourced from QueryServer.

**F11 Vendor Editor**: For vendor NPCs: auto-import vendor inventory from `creature_vendor` table. Then define per-item rules: buy (qty threshold at which to buy restock), sell (always sell this), repair (threshold %), ignore (never interact). Rules are stored as inventory rule nodes in the profile.

**F16 Condition Editor**: Every node and edge in the Campaign graph supports condition guards. Supported condition types: QuestComplete (id), QuestNotComplete, HasItem (id + min count), LevelAtLeast, LevelAtMost, GoldAtLeast, Reputation (faction + min standing), ClassIs, RaceIs, KnowsSpell, SkillAtLeast, InZone, HasBuff, HasProfession, IsOutdoor, IsDungeon, IsRaid, PartySize, PartyHasClass, DailyQuestDone. Conditions compose as AND/OR/NOT trees in the Condition Editor.

**F17 Inventory Rules**: Per-item or per-category rules: Destroy (auto-destroy on loot), Keep (reserve bag space), Sell (vendor trash), Mail (send to alt), Auction (post at AH), Equip (auto-equip if upgrade), Use (use on loot), Ignore (leave on corpse). Each rule has optional filters: item quality, item level range, slot, class mask.

**F14 Loot Object Editor**: For game objects (herbs, mining veins, treasure chests, quest objects): display object type, map/position of known spawns, respawn timer, interaction radius, required skill (for mining/herbalism), loot table if any. Edit these as part of a questing.Interact node in the profile.

### Database Panel (`database`)

**F9 Spawn Scanner**: Scan nearby creatures and objects using `dbg.nearby(range, filter)` from the running game instance. Results grouped by entry ID with counts. Each entry shows name, level, distance, count. Actions: "Add to profile as Kill node", "Add to profile as Interact node", "Open in NPC Inspector", "Pin to Spawn Overlay". Additionally, manual scan modes: scan herbs, scan mining, scan treasure, scan flight masters, scan innkeepers — each filtering by game object type or creature flags.

**F13 Grinding Area Generator**: Select a zone or area. The generator queries spawn densities from `creature` + `spawns` endpoints, computes expected XP per kill and per hour, identifies safe spots (low-spawn density areas), computes pull radius for efficient loops, estimates gold from vendor loot. Output: a grinding route with waypoints + Kill nodes + SellJunk nodes + RepairEquipment nodes.

### Shell Extensions (Cross-Cutting)

**F4 Spawn Overlay**: Draw spawn points on the 3D game world using the Sylvannas world overlay renderer (if available). Color scheme: green = creatures, blue = game objects, red = quest bosses, purple = escort NPCs. Optional density heatmap overlay in zones with high spawn concentration. Filter by entry ID, level range, faction, or type. Toggle per category. *Risk: dependent on Sylvannas render callback capabilities — may reduce to a list view if overlay rendering is unavailable.*

**F12 Travel Editor**: Detect known travel routes from the profile's node sequence: taxi routes (from flight path to flight path), zeppelin/boat crossings, portal usage, hearthstone, meeting stones, dungeon/raid entrances. Display estimated travel time for each segment using `travel/estimate` QueryServer endpoint. Allow editing travel segments (add wait, change route, insert waypoint).

**F19 Auto Validation**: Runs automatically on every profile save via the existing `POST /validate` endpoint. Checks: missing quest accept/turn-in pairs, invalid NPC/item/object IDs (against QueryServer), broken quest chains (missing prerequisites), unreachable waypoints (no path between sequential waypoints), circular paths (infinite loops in graph edges), quest impossibility (quest requires level 70 but profile only 1-60). Validation results appear as a toast notification with clickable diagnostics that navigate to the offending node.

**F20 Profile Statistics**: At-a-glance stats computed on save and displayed in a panel header bar: quest count, waypoint count, unique NPCs referenced, unique objects, vendors used, flight masters, estimated total completion time (from travel estimates + kill counts × expected kill time), estimated total XP, estimated total gold. Rendered as badge chips in the shell header.

## Technical Approach

### Implementation Pattern

Every panel follows the existing Runner panel pattern:

1. **panel_state.lua** — Pure view-model module. Owns selection, filtering, pagination, and query state. No rendering logic. Exports `create()`, `destroy()`, `update()`, and accessors.
2. **panel.lua** — Render layer. Imports the Widgets library (`section_header`, `list_row`, `search_field`, `button`, `chip`, `empty_state`, etc.). Receives state, returns command objects. No direct API calls.
3. **ide_panels.lua** binding — Wires state + render + dispatch + `on_tick`. Pattern: `state → render → dispatch(commands)`. The dispatch layer calls QueryServer HTTP endpoints and updates state.
4. One-line registration in `IdePanels.install()` using `register_panel{ id, render, title, dispatch, on_tick, ... }`.

### Data Sources

All read data comes from the existing **QueryServer** (:3030) via `QueryClient.lua` — which already provides:
- HTTP GET with response caching (5s TTL per endpoint)
- Inflight request deduplication
- Negative caching (404s remembered for 30s)
- Error logging without crash

New QueryServer endpoints required (add to `SentinelQueryServer/`):
- `/quest/{id}/chain` — returns prerequisites, follow-ups, exclusive groups for F2
- `/quest/{id}/objectives` — returns parsed objectives with loot template links for F3
- `/zone/{id}/spawns` — aggregated spawn data per zone for F13
- `/spawns/density/{zone}` — density computation endpoint for F13
- `/travel/route` — multi-segment travel estimation for F12

### Mutations

All write operations go through the **Editor crate** (:3031). Current editor only knows the old "Project" model (operations → actions). For the new graph-based Campaign format:

**Recommendation**: Extend the editor crate with new endpoint groups under `/editor/campaigns/`:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/editor/campaigns/` | GET | List campaigns |
| `/editor/campaigns/{name}` | GET | Load campaign graph |
| `/editor/campaigns/{name}` | POST | Create/save campaign |
| `/editor/campaigns/{name}/nodes` | POST | Add node |
| `/editor/campaigns/{name}/nodes/{id}` | PUT | Update node |
| `/editor/campaigns/{name}/nodes/{id}` | DELETE | Remove node |
| `/editor/campaigns/{name}/edges` | POST | Add edge |
| `/editor/campaigns/{name}/edges/{id}` | DELETE | Remove edge |
| `/editor/campaigns/{name}/validate` | POST | Validate (wraps existing `/validate`) |
| `/editor/campaigns/{name}/compile` | POST | Compile to ExecutionPlan |

Each write endpoint wraps in the existing `CommandHistory` pattern for undo/redo support (50-command depth). The old Project endpoints remain for backward compatibility with the ~hundreds of existing profiles in `.questing/profiles/` and `.questing/projects/`.

### Existing Capabilities Leveraged

| Feature | Existing Work | Remaining |
|---------|--------------|-----------|
| F5 Live Recording | W12 recording → resolve → run pipeline | None |
| F19 Auto Validation | `sentinel-validator` crate + `POST /validate` endpoint | Wire into save flow + UI diagnostics |
| F20 Profile Statistics | Editor `list`/`load` already computes operation_count | Full stats aggregation |
| F21 Profile Simulator | Resolver validates, runtime dry-runs, validator catches issues | Full TPS simulator deferred |
| QueryServer | 18 endpoints on `tbcmangos.sqlite` | 5 new endpoints for quest chains, zones, density |

## User Experience Flow

1. User opens IDE → **Runner** tab (default) shows current execution state
2. Switches to **Explorer** tab → quest list by zone with search
3. Clicks a quest → detail pane: objectives, rewards, prerequisites, chain info
4. Clicks "Add to Profile" → auto-generates AcceptQuest + Kill/Loot objectives + TurnInQuest wired as a Campaign subgraph
5. Switches to **Graph** tab → sees auto-generated nodes as an editable linear sequence
6. Refines: adds waypoints (copies current position), adds conditions, inserts vendor stops, defines combat areas
7. Clicks a node → **Properties** tab opens with context-sensitive deep editor for that node type
8. Clicks **Save** → Auto Validation runs → toast with pass/fail + clickable diagnostics
9. Switches to **Runner** tab → loads and runs the saved profile

## Key Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Spawn overlay (F4) constrained by Sylvannas render callback capabilities | High | Investigate render API early; fallback to list-only overlay view if 3D overlay unsupported |
| Visual graph editing (F6, F7) complexity in constrained UI canvas | High | v1 uses list-based node editor, not full canvas rendering. Canvas is v2. |
| Editor crate Campaign CRUD is non-trivial Rust work on a new model | Med | Option (a) — extend editor crate with new `/editor/campaigns/*` endpoint group; existing CommandHistory reuse simplifies undo/redo |
| 400-line review budget exceeded per PR | High | Auto-chain PR splitting at ~400 lines; each phase maps to 1-2 chained PRs |
| QueryServer DB schema inconsistencies across Mangos versions | Low | Validate endpoints against actual `tbcmangos.sqlite` at each release; `validate` endpoint catches bad IDs |
| Concurrent edits (two in-game IDE sessions) | Low | Last-writer-wins on save; documented single-user assumption |
| New QueryServer endpoints create drift from `sentinel-queryclient` | Low | All new endpoints added to both server and client in same PR |

## Phasing and Scale

| Phase | Focus | Files | Est. Lines | PRs |
|-------|-------|-------|------------|-----|
| 0 | Editor crate: Campaign CRUD endpoints + CommandHistory reuse | 4-6 Rust files | ~500 | 1 PR (must precede UI) |
| 1 | Explorer panel: quest browser, chain viz, objective generator | 8-10 Lua files | ~800 | 2 PRs (1a: QueryServer endpoints, 1b: panel) |
| 2 | Properties panel: NPC/Vendor/Condition/Inventory/Loot editors | 10-12 Lua files | ~1200 | 2 PRs |
| 3 | Graph panel: waypoint/behavior/escort/combat editors | 10-12 Lua files | ~1500 | 3 PRs |
| 4 | Database panel: spawn scanner, grinding area generator | 6-8 Lua files | ~600 | 1-2 PRs |
| 5 | Shell extensions: validation, stats, overlays, travel editor | 8-10 Lua files | ~900 | 2 PRs |

**Total**: ~5500 lines across ~50 files, delivered as 10-12 chained PRs.

## Delivery Strategy (Chained PRs)

```
Phase 0: Editor Campaign CRUD (must land first)
  PR-0a: /editor/campaigns/* endpoints + old model backward compat

Phase 1: Explorer Panel
  PR-1a: QueryServer new endpoints (/quest/{id}/chain, /objectives, /zone/spawns, /density)
  PR-1b: Explorer panel (browser, chain viz, objective generator)

Phase 2: Properties Panel
  PR-2a: NPC Inspector + Loot Object Editor (shared QueryServer endpoints)
  PR-2b: Vendor Editor + Condition Editor + Inventory Rules

Phase 3: Graph Panel
  PR-3a: Smart Waypoint Editor
  PR-3b: Behavior Nodes (node list + property editing)
  PR-3c: Escort Recorder + Combat Area Editor

Phase 4: Database Panel
  PR-4a: Spawn Scanner
  PR-4b: Grinding Area Generator

Phase 5: Shell Extensions
  PR-5a: Auto Validation wiring + Profile Statistics
  PR-5b: Spawn Overlay + Travel Editor
```

Each PR targets ~400 lines. Phases can overlap if the hard ordering (Phase 0 before Phase 1-5, Phase 1 before Phase 3) is respected.

## Dependencies

- Existing QueryServer (:3030) with 18 endpoints — **must be running** for panels to function
- Existing Editor crate (:3031) with command undo/redo — **must extend, not replace**
- Existing `QueryClient.lua` — used by all panels for data fetching
- Existing Widgets library (`sentinel/ui/widgets/`) — theme system, spacing grid, semantic colors
- Existing panel registration system (`register_panel`, `IdePanels.install`)
- W12 recording system — used by F15 Escort Recorder
- `sentinel-validator` crate + `POST /validate` — used by F19 Auto Validation
- Sylvannas render callback API — required by F4 Spawn Overlay (needs investigation)

## Success Criteria

- [ ] Author a complete quest profile from scratch: discover a quest in Explorer → auto-generate objectives → refine in Graph → add conditions in Properties → Save with validation passing → Run in Runner panel — **no JSON hand-editing, no RestedXP import required**.
- [ ] Import an existing `.profile.json`, open in the IDE, inspect nodes, modify a condition, save, recompile — output byte-identical to hand-edited equivalent (modulo authored changes).
- [ ] Spawn Scanner shows nearby creatures from game state, allows adding as Kill nodes.
- [ ] Auto Validation catches at least: missing TurnInQuest, invalid NPC ID, broken chain, circular path.
- [ ] Profile Statistics shows: quest count, waypoint count, estimated time/XP/gold.
- [ ] `luajit sentinel/tests/run_offline.lua` green after every phase.
- [ ] 400-line PR budget respected with auto-chained PRs.

## Rollback Plan

Each phase is additive — revert any PR independently. Phase 0 (editor crate extension) is the only hard dependency; reverting it breaks campaign editing but leaves project editing intact. Existing profiles on disk are untouched by any phase. No data migration exists.

## Open Questions

1. **Spawn Overlay (F4) feasibility**: Does the Sylvannas injector expose a render callback that supports world-space drawing? Needs investigation before committing to the 3D overlay approach. Fallback: text list with distance, direction arrow, and minimap pin.
2. **Campaign CRUD location**: Option (a) extend editor crate vs (b) new `campaign-editor` crate. Recommendation is (a), but the decision affects Rust workspace structure — finalize in design phase.
3. **Combat Area Editor (F18) integration**: Is the combat area data consumed by the BT's combat module directly, or stored as metadata on the Campaign node? Current runtime doesn't read combat areas from the profile. May need a runtime change to consume this data — or it's pure authoring metadata for now.
4. **Escort Recorder (F15) recording API**: The W12 system records quest-log diffs, not NPC movement/combat events. Escort recording may need a new publisher in `world_observer.lua` for NPC-relative events. Confirm during design.
5. **Grinding Area Generator (F13) performance**: Computing expected XP/gold per hour across a zone requires iterating spawns × loot tables. May need a dedicated `/zone/stats` aggregation endpoint with server-side caching. For v1, a simplified estimate using creature_template base XP + average drop is acceptable.

## v2 Candidates (Future Change, Outline Only)

- Full canvas-based graph editor (drag nodes, edge drawing, zoom/pan)
- Visual route on world map overlay (post-F4 investigation)
- Profile Simulator with TPS/DPS/HPS estimates
- Copy/paste nodes and subgraphs
- Multi-select operations (batch edit, batch delete)
- Undo/redo UI buttons in toolbar (API exists, no UI)
- Blueprint library (sharable profile templates)
- Auto-load last-used profile on IDE open
