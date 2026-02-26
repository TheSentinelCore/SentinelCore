# Profile Editor & Recorder UI — Design Document

## Goal

Add a complete in-game profile creation, editing, and recording workflow to SentinelCore so users can build grinding profiles without manually writing JSON.

## Architecture

Three new modules, each following existing codebase patterns:

| Module | Role | Pattern |
|--------|------|---------|
| `services/ProfileRecorder.lua` | Recording service — owns recorder FSM, keybind handling, working profile copy | Like VendorService |
| `ui/ProfileOverlay.lua` | 3D world overlay — hotspot circles, route lines, blackspot/vendor markers | Like SentinelGather/PathVisualizer |
| `ui/tabs/profile_tab.lua` | Extracted + expanded profiles tab — browse, edit, record controls | Like SentinelGather/ui/tabs/ |

**window.lua changes:** Replace inline profiles tab (~190 lines) with `require("ui/tabs/profile_tab")`.

---

## ProfileRecorder Service

### State Machine

```
idle ──[start_recording(profile?)]──→ recording
recording ──[add_hotspot()]──→ recording    (appends player pos)
recording ──[add_vendor()]──→ recording     (appends player pos as vendor)
recording ──[add_blackspot()]──→ recording  (appends player pos as blackspot)
recording ──[remove_last()]──→ recording    (undo last addition)
recording ──[finish_recording()]──→ idle    (returns completed profile)
recording ──[cancel_recording()]──→ idle    (discards working copy)
```

### Constructor

```lua
ProfileRecorder:new(event_bus, blackboard, logger)
```

### Keybind

One `core.menu.key_checkbox` element — press to drop a hotspot at player position.

- ID: `"sc_record_hotspot"`
- Default key: `Insert`
- Only active when `recorder.state == "recording"`

### Blackboard Keys (written)

| Key | Type | Description |
|-----|------|-------------|
| `recorder.state` | string | `"idle"` or `"recording"` |
| `recorder.working_profile` | table | The in-progress profile being built |
| `recorder.hotspot_count` | number | Quick count for display |

### Blackboard Keys (read)

| Key | Description |
|-----|-------------|
| `player.position` | Current player world position |
| `player.map_id` | Auto-fills `requirements.map_id` on recording start |

### Events (new additions to Events.lua)

```lua
RECORDER_STARTED      = "recorder.started"
RECORDER_STOPPED      = "recorder.stopped"
RECORDER_HOTSPOT_ADDED   = "recorder.hotspot_added"
RECORDER_HOTSPOT_REMOVED = "recorder.hotspot_removed"
```

### Behavior

- `start_recording(existing_profile?)` — Creates a working copy from `Schema.defaults()` (new) or deep-copies an existing profile (edit mode). Auto-fills `requirements.map_id` from blackboard `player.map_id`. Sets `recorder.state = "recording"`.
- `add_hotspot()` — Reads `player.position` from blackboard, generates an auto-ID (`"hs_" .. index`), appends to `working_profile.hotspots`. Default radius comes from a configurable value (default 40).
- `add_vendor()` — Same as add_hotspot but appends to `working_profile.vendors` with `sell = true, repair = true`.
- `add_blackspot()` — Appends to `working_profile.blackspots`.
- `remove_last()` — Pops the most recently added item (tracks an ordered history of additions across hotspots/vendors/blackspots).
- `finish_recording()` — Validates via `ProfileValidator.validate()`, returns the completed profile. Clears blackboard recorder keys.
- `cancel_recording()` — Discards working copy, clears blackboard recorder keys.
- `update()` — Checks keybind state each tick. If keybind fires and state is "recording", calls `add_hotspot()`.

---

## ProfileOverlay (3D World Rendering)

### Registration

```lua
core.register_on_render_callback(function()
    overlay:render()
end)
```

### Data Source

Reads `recorder.working_profile` from blackboard (during recording) or `profile.current_hotspot` + active profile hotspots (during execution).

### Visual Elements

| Element | API Call | Color | When |
|---------|----------|-------|------|
| Hotspot circles | `core.graphics.circle_3d(pos, radius, color, thickness)` | Green | Always when profile visible |
| Selected hotspot | `core.graphics.circle_3d(pos, radius, color, thickness)` | Bright white | When hotspot selected in tab |
| Route lines | `core.graphics.line_3d(from, to, color, thickness)` | Cyan | Always when profile visible |
| Loop-back line | `core.graphics.line_3d(last, first, color, thickness)` | Cyan (dimmer) | When `profile.loop == true` |
| Blackspot circles | `core.graphics.circle_3d(pos, radius, color, thickness)` | Red | Always when profile visible |
| Vendor markers | `core.graphics.circle_3d(pos, 3, color, thickness)` | Orange | Always when profile visible |
| Recording indicator | `core.graphics.circle_3d(player_pos, pulse_radius, color)` | Pulsing green | When recording |

### Visibility

Renders when:
- `recorder.state == "recording"` (shows working profile), OR
- A grinding profile is actively loaded (shows active route from ProfileCoordinator)

---

## profile_tab.lua (UI Tab)

### Structure

Two modes within one tab, controlled by a local `_editor_mode` variable:

### Browse Mode (default)

Preserves existing functionality from window.lua:
- Active Profile info row (profile ID)
- Grinding Profile status row (FSM state, color-coded, current hotspot)
- Saved Profiles listbox (from `list_profile_files()`)
- Action buttons: **Load**, **Save**, **Delete**
- New buttons: **New Profile**, **Edit** (loads selected into recorder)

### Edit Mode

Entered via "New Profile" or "Edit" button. Sections rendered vertically:

**Section 1 — Metadata** (row_list with menu elements):

| Widget | Type | ID | Description |
|--------|------|----|-------------|
| Name | `text_input` | `"sc_profile_name"` | Profile name |
| Min Level | `slider_int` | `"sc_profile_min_level"` | Range 1–80 |
| Max Level | `slider_int` | `"sc_profile_max_level"` | Range 1–80 |
| Map ID | `info` | — | Auto-filled, display only |

**Section 2 — Target Filters** (row_list):

| Widget | Type | ID | Description |
|--------|------|----|-------------|
| Target Level Min | `slider_int` | `"sc_profile_target_min"` | Range 1–80 |
| Target Level Max | `slider_int` | `"sc_profile_target_max"` | Range 1–80 |
| NPC Blacklist | `text_input` | `"sc_profile_npc_bl"` | Comma-separated NPC IDs |
| NPC Whitelist | `text_input` | `"sc_profile_npc_wl"` | Comma-separated NPC IDs |

**Section 3 — Hotspot List** (custom_render):

- Numbered list of hotspots: `#1: (x, y, z) r=40 [label]`
- Click to select (highlights in overlay via blackboard key `recorder.selected_index`)
- Per-hotspot buttons: **Remove**, **Move Up**, **Move Down**
- Label edit: `text_input` for selected hotspot's label

**Section 4 — Recording Controls** (custom_render):

| Button | Action |
|--------|--------|
| Start/Stop Recording | Toggle `ProfileRecorder` state |
| Add Vendor | `recorder:add_vendor()` |
| Add Blackspot | `recorder:add_blackspot()` |
| Undo Last | `recorder:remove_last()` |
| Hotspot Radius | `slider_int` (10–100, default 40) |

**Section 5 — Save/Cancel** (custom_render):

| Button | Action |
|--------|--------|
| Filename | `text_input` for save filename |
| Save Profile | Validate → `save_profile_to_file(filename)` → optionally load |
| Save & Load | Save + `client:load_grinding_profile(profile)` |
| Cancel | Discard working copy → return to browse mode |

Validation errors displayed as red text below the Save button.

---

## Client.lua Integration

### New Public API

```lua
client:start_recording(existing_profile?)  -- starts ProfileRecorder
client:stop_recording()                     -- stops recorder, returns profile
client:get_recorder_state()                 -- "idle" | "recording"
```

### Service Registration

ProfileRecorder added to:
- `require("services/ProfileRecorder")` at top
- Service instantiation (after profile_coordinator)
- `o._services.profile_recorder` entry
- `o._service_update_order` (after "profile_coordinator")

### ProfileOverlay Registration

Created in Client constructor. Registered via `core.register_on_render_callback`. Reads from blackboard — no direct service coupling.

---

## Data Flow

```
User presses Insert keybind
    → ProfileRecorder.update() detects keypress
    → ProfileRecorder:add_hotspot()
        → reads bb("player.position")
        → appends to working_profile.hotspots
        → bb:set("recorder.working_profile", profile)
        → emit RECORDER_HOTSPOT_ADDED

ProfileOverlay (render callback)
    → reads bb("recorder.working_profile")
    → draws circle_3d at each hotspot, line_3d between them

profile_tab.lua (UI render)
    → reads bb("recorder.working_profile")
    → renders hotspot list, metadata form
    → user clicks Save → ProfileValidator.validate()
        → ProfileCoordinator:save_profile_to_file(filename)
    → user clicks Save & Load
        → save + client:load_grinding_profile(profile)
```

---

## File Changes Summary

| File | Action |
|------|--------|
| `services/ProfileRecorder.lua` | **Create** — recorder service |
| `ui/ProfileOverlay.lua` | **Create** — 3D overlay |
| `ui/tabs/profile_tab.lua` | **Create** — extracted + expanded tab |
| `ui/window.lua` | **Modify** — replace inline profiles tab with require |
| `events/Events.lua` | **Modify** — add 4 recorder events |
| `core/Client.lua` | **Modify** — add recorder service + overlay + public API |
| `tests/test_sc_profile_recorder.lua` | **Create** — recorder unit tests |

---

## Testing

### Unit Tests (test_sc_profile_recorder.lua)

- Recorder FSM: idle → recording → idle transitions
- `add_hotspot()` reads player position, generates auto-ID, appends correctly
- `add_vendor()` / `add_blackspot()` append to correct arrays
- `remove_last()` pops in reverse chronological order across types
- `finish_recording()` validates and returns complete profile
- `cancel_recording()` discards working copy
- Auto-fills `map_id` from blackboard on start
- Edit mode: starts with deep copy of existing profile, doesn't mutate original

### Manual In-Game Verification

1. Open Profiles tab → click "New Profile" → enters edit mode
2. Set name, level range via form fields
3. Click "Start Recording" → walk to locations → press Insert at each spot
4. Verify 3D overlay shows circles and route lines
5. Click "Stop Recording" → verify hotspot list populated
6. Reorder hotspots, remove one, verify overlay updates
7. Click "Save & Load" → verify profile saves to file and FSM starts
8. Reload UI → verify profile appears in saved list
