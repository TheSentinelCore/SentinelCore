---
id: 16
title: "Capture Panels — NPC + Quest Browser + World Map"
state: open
labels: ["enhancement", "ready-for-agent", "size:large"]
created: "2026-07-18T00:00:00Z"
updated: "2026-07-18T00:00:00Z"
---

# 16 — Capture Panels: NPC + Quest Browser + World Map

**What to build:** Three panels that let the author capture in-game entities (NPCs, quests, map positions) and browse the QueryServer database for reference data. These panels bridge the game world and the profile data model.

**Blocked by:** #11 (Query Client — panels query the QueryServer), #15 (Panel System — panels register with the IDE)

**Acceptance criteria:**

**Target Capture Panel:**
- [ ] Reads current target via `core.object_manager.GetTarget()`
- [ ] Displays: name, entry ID, GUID, faction, position (x, y, zone), health, level
- [ ] Role assignment buttons (toggle): QuestGiver, Vendor, Trainer, Innkeeper, FlightMaster, Repair, Mailbox, Bank
- [ ] QueryServer enrichment: when target is captured, query `/api/v1/npcs/{entry_id}` to verify NPC exists in database and auto-fill roles from DB data
- [ ] "Add to Library" button: saves captured NPC with assigned roles to the NPC Library
- [ ] Visual feedback: panel background turns green on successful capture, red if NPC not in QueryServer DB
- [ ] Refreshes on target change event

**NPC Library Panel:**
- [ ] Searchable/filterable list of all captured NPCs
- [ ] Each entry shows: name, entry ID, roles (icons), position, zone
- [ ] Click to select → highlight on World Map (if open), show in Inspector
- [ ] Right-click context menu: Edit Roles, Edit Position, Delete (with dependency check — warn if NPC is referenced by an Operation)
- [ ] Role filter: show only vendors, only quest givers, etc.
- [ ] Stored in profile data at `profile.npcs: Vec<NpcReference>`
- [ ] Empty state: "No NPCs captured yet. Target an NPC in-game and use Capture (Ctrl+N)."

**Quest Browser Panel:**
- [ ] Search input: queries QueryServer `/api/v1/quests/search?query=<term>`
- [ ] Results list: title, level, zone, giver NPC name
- [ ] Click to select quest → expanded view shows: objectives, rewards, chain (prerequisite quests, follow-up quests), required level, required items
- [ ] Action buttons: "Add Pickup" (adds PickupQuest action to current Operation), "Add TurnIn" (adds TurnInQuest action), "Preview Chain" (highlights the full quest chain on the map)
- [ ] Chain visualization: linear or branching tree of quests, with status indicators
- [ ] Empty search state: "Type to search quests..."

**World Map Panel:**
- [ ] Render overlay on the game minimap or full-screen map (Sylvannas map API)
- [ ] Pins for: NPCs (colored by role — green=quest giver, yellow=vendor, blue=trainer, purple=flight master), Operations (numbered markers), Waypoints (small dots)
- [ ] Polygon rendering: draw GrindArea polygons from Operations with vertex dots and fill
- [ ] Route rendering: draw RecordPath polylines with directional arrows
- [ ] Click pin → select associated entity (NPC or Operation) → Explorer + Inspector update
- [ ] Right-click on map → context menu: "Create Waypoint Here", "Create GoTo Action Here"
- [ ] Drag to create new waypoints (constrained to current zone)
- [ ] Zoom in/out, pan (drag map)
- [ ] Legend: small key showing pin colors and shapes
