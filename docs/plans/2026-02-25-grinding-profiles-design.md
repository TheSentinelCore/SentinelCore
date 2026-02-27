# Grinding Profile System Design

**Date:** 2026-02-25
**Status:** Approved

## Overview

Full-featured grinding profiles for SentinelCore: waypoint-based routes with hotspots, target filters, vendor definitions, blackspots, and an in-game recorder. Profiles inject configuration into existing services (Approach B) with a thin ProfileCoordinator FSM for orchestration.

## Profile Schema (v2)

Profiles are JSON files stored in `scripts_data/SentinelCore/profiles/`.

```json
{
  "version": "1.0",
  "metadata": {
    "name": "Netherstorm - Manaforge B'naar",
    "author": "Levi",
    "description": "Farm Sunfury mobs for Arcane Tomes and Sunfury Signets",
    "tags": ["netherstorm", "humanoid", "reputation", "65-70"],
    "created_at": 1740500000,
    "updated_at": 1740500000
  },
  "requirements": {
    "map_id": 530,
    "min_level": 67,
    "max_level": 72,
    "class_restrictions": []
  },
  "target_defaults": {
    "level_min": 67,
    "level_max": 70,
    "creature_types": ["humanoid"],
    "npc_blacklist": [20990],
    "npc_whitelist": []
  },
  "hotspots": [
    {
      "id": "manaforge_east",
      "x": -3112.4, "y": 3684.1, "z": 142.5,
      "radius": 45,
      "label": "Manaforge east side",
      "targets": null,
      "overrides": null
    },
    {
      "id": "manaforge_north",
      "x": -2980.0, "y": 3820.3, "z": 139.7,
      "radius": 50,
      "label": "Manaforge north side",
      "targets": {
        "creature_types": ["humanoid", "demon"],
        "npc_blacklist": [20990, 20991]
      }
    }
  ],
  "blackspots": [
    {
      "x": -3050.0, "y": 3700.0, "z": 141.0,
      "radius": 15,
      "severity": "hard",
      "reason": "Elite patrol"
    }
  ],
  "vendors": [
    {
      "npc_id": 20916, "name": "Dealer Jadyan",
      "x": -3024.8, "y": 3557.2, "z": 143.5,
      "sell": true, "repair": true, "food": false, "water": false
    }
  ],
  "rest_spots": [
    { "x": -3030.0, "y": 3560.0, "z": 143.0, "label": "Near vendor - safe" }
  ],
  "loop": true,
  "dry_spell_secs": 15,
  "travel_engage": true,
  "overrides": {}
}
```

### Schema Design Decisions

- **Hotspots and paths are separate concerns.** Hotspots are the profile's primary content. Inter-hotspot routing is handled by NavServer (no explicit path waypoints needed).
- **Target filters inherit.** Per-hotspot `targets` override `target_defaults`. Null means inherit defaults.
- **Hotspot IDs are strings.** Stable across reordering, referenced by events and FSM state.
- **Vendor flags include food/water.** Bot needs to buy consumables, not just repair/sell.
- **Blackspot severity.** `hard` = never enter. `soft` = avoid but passable if needed.
- **Overrides are flat key-value.** Merge into runtime config. Allows per-profile tuning of any service parameter.
- **Minimal required fields.** `version`, `metadata.name`, `requirements.map_id`, `hotspots` (at least 1).

## Architecture: ProfileCoordinator with Thin FSM

### State Machine

```
                    +----------------+
         +---------|  at_hotspot     |<-----------+
         |         |                 |            |
         |         | ExplorationSvc  |  arrive at |
         |         | within radius   |  hotspot   |
         |         +--------+--------+            |
         |                  |                     |
         |         density dry spell              |
         |         (0 mobs for Ns)                |
         |                  |                     |
         |                  v                     |
         |         +----------------+             |
         |         |  traveling      |             |
         |         |                 |             |
         |         | NavAdapter      |-------------+
         |         | .move_to()      |
         |         +----------------+
         |
    bags full /
    need repair
         |
         v
  +----------------+
  | vendor_trip     |
  |                 |
  | VendorService   |---> return to last hotspot
  | handles it      |     (not advance)
  +----------------+
```

### Service Activity Per State

| State | ExplorationService | TargetingService | VendorService | NavigationAdapter |
|-------|-------------------|-----------------|--------------|------------------|
| `at_hotspot` | Active (anchor = hotspot, radius = hotspot radius) | Active (profile filters) | Monitors bags/durability | Stuck detection |
| `traveling` | Suppressed | Active if `travel_engage` | Monitors | `move_to(next hotspot)` |
| `vendor_trip` | Suppressed | Suppressed | Active (drives movement) | Via VendorService |

### Blackboard Keys

| Key | Type | Set When |
|-----|------|----------|
| `grind.anchor` | `{x,y,z}` | Hotspot entered (existing key) |
| `profile.active` | `boolean` | Profile loaded/unloaded |
| `profile.state` | `string` | FSM state |
| `profile.current_hotspot` | `table` | Current hotspot data |
| `profile.target_filters` | `table` | Merged target_defaults + hotspot overrides |
| `profile.blackspots` | `table[]` | Blackspot list |
| `profile.vendors` | `table[]` | Vendor list |
| `profile.rest_spots` | `table[]` | Rest spot list |
| `exploration.max_grind_radius` | `number` | Current hotspot radius |

### Transition Logic

- **at_hotspot -> traveling:** TargetingService finds 0 valid candidates for `dry_spell_secs` (default 15s). Advance hotspot index. If `loop` and at end, wrap to index 1.
- **traveling -> at_hotspot:** Player arrives within hotspot radius. Inject new anchor + filters.
- **at_hotspot -> vendor_trip:** VendorService gate triggers (bags full or durability low). Remember current hotspot ID.
- **vendor_trip -> at_hotspot:** VendorService completes. Resume remembered hotspot (navigate back if needed).
- **Death recovery:** On death recovery complete, resume nearest hotspot by distance (not necessarily the one died at).

### TargetingService Integration

Minimal change. In `get_visible_candidates()`, after building candidate list, apply profile filters (~30 lines):

```lua
local filters = self._blackboard:get("profile.target_filters")
if filters then
    candidates = self:_apply_profile_filters(candidates, filters)
end
```

Checks: level range, creature type match, NPC whitelist (if non-empty, only those), NPC blacklist (exclude).

### VendorService Integration

When `profile.vendors` is set on the blackboard, VendorService uses those vendors instead of querying SentinelQueryServer. The existing `_candidate_allowed()` faction check still applies.

## Profile Recorder

### Recording Flow

1. User presses "New Profile" in UI -> enters recording state
2. 3D overlay shows recorded points live
3. User walks route, pressing hotkeys at key locations
4. User presses "Finish" -> enters editing state
5. Editing UI shows recorded profile with editable fields
6. User presses "Save" -> writes JSON to `scripts_data/SentinelCore/profiles/`

### Hotkey Actions

| Hotkey | Action | Captured Data |
|--------|--------|---------------|
| Record Hotspot | Mark position as hotspot | `{x, y, z, type: "hotspot", radius: 40}` |
| Record Blackspot | Mark danger zone | `{x, y, z, radius: 15, severity: "hard"}` |
| Record Vendor | Target NPC + press | `{npc_id, name, x, y, z}` from object manager |
| Record Rest Spot | Mark safe area | `{x, y, z}` |
| Undo Last | Remove last recorded point | Pop from appropriate list |
| Finish Recording | End recording mode | Transition to editor |

### Auto-Populated Fields

- `requirements.map_id` from player's current map
- `metadata.created_at` from current timestamp
- `target_defaults.level_min/max` from player level +/- range
- Vendor `sell`/`repair`/`food`/`water` flags from NPC flags in object manager

### 3D Overlay

- Hotspots: colored circle_3d at position with radius visualization
- Current hotspot: highlighted green, others dimmed gray
- Blackspots: red circle_3d
- Vendors: yellow marker
- Travel path between hotspots: dotted line_3d connecting hotspot centers
- Recording breadcrumb: trail of dots showing the path walked during recording

## Profile Editor UI

New tab in SentinelCore window with two views:

### Profile List View
- Dropdown to select profile
- Load/Unload buttons
- "New Profile" button (enters recorder)
- "Import JSON" button
- Profile metadata display (name, author, hotspot count, map)

### Profile Detail View
- Editable metadata (name, author, description)
- Hotspot list with reorder (up/down), edit, delete
- Hotspot detail editor: label, radius stepper, target override toggle + filter fields
- Target defaults section: level range, creature types, NPC lists
- Vendor list with delete
- Settings: loop toggle, dry_spell_secs stepper, travel_engage toggle
- Save / Save As / Delete buttons

## File Structure

```
SentinelCore/
  services/
    ProfileCoordinator.lua       # FSM + hotspot cycling + profile loading
  profiles/
    ProfileRecorder.lua          # Recording mode + hotkey handlers
    ProfileValidator.lua         # Schema validation
    ProfileSchema.lua            # Defaults, field specs, version migration
  ui/tabs/
    profile_tab.lua              # Editor tab
    recorder_overlay.lua         # 3D overlay for recording + playback
  tests/
    test_sc_profile_coordinator.lua
    test_sc_profile_validator.lua
    test_sc_profile_recorder.lua
```

## Events

| Event | Payload | When |
|-------|---------|------|
| `PROFILE_LOADED` | `{name, path, hotspot_count, map_id}` | Profile parsed and validated |
| `PROFILE_UNLOADED` | `{name}` | Profile deactivated |
| `PROFILE_LOAD_FAILED` | `{path, errors}` | Validation failed |
| `HOTSPOT_ENTERED` | `{hotspot_id, index, label}` | FSM enters at_hotspot |
| `HOTSPOT_ADVANCED` | `{from_id, to_id, reason}` | Dry spell triggered |
| `HOTSPOT_TRAVEL_START` | `{from_id, to_id, distance}` | FSM enters traveling |
| `VENDOR_TRIP_START` | `{vendor_npc_id, resume_hotspot_id}` | FSM enters vendor_trip |
| `VENDOR_TRIP_COMPLETE` | `{resume_hotspot_id}` | Returning to hotspot |
| `PROFILE_LOOP_COMPLETE` | `{loop_count, elapsed_secs}` | All hotspots visited |
| `RECORDER_STARTED` | `{}` | Recording mode entered |
| `RECORDER_POINT_ADDED` | `{type, x, y, z}` | Point recorded |
| `RECORDER_FINISHED` | `{hotspot_count, vendor_count}` | Recording complete |

## No-Profile Fallback

When no profile is loaded, SentinelCore behaves exactly as it does today: ExplorationService uses frontier expansion from `grind.anchor` or player position, TargetingService has no NPC filters, VendorService uses auto-discovery. ProfileCoordinator is idle and writes nothing to the blackboard.
