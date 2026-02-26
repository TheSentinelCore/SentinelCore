# Profile Editor & Recorder UI — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add in-game profile creation, editing, and recording so users can build grinding profiles without writing JSON.

**Architecture:** Three new modules — ProfileRecorder (service with FSM), ProfileOverlay (3D world rendering), profile_tab.lua (extracted/expanded UI tab). Follows existing SentinelCore patterns: services own logic, UI reads blackboard, EventBus for decoupling.

**Tech Stack:** Lua (Sylvannas API), core.menu elements (text_input, slider_int, key_checkbox, button), core.graphics (circle_3d, line_3d), AstroUI custom_render, EventBus/Blackboard.

**Design doc:** `docs/plans/2026-02-25-profile-editor-design.md`

---

## Context for Implementers

### Key Patterns

**Service constructor:** `Service:new(event_bus, blackboard, cfg, logger)` — see `ProfileCoordinator:new()` at `Client.lua:182`.

**Blackboard API:** `bb:get(key, default?)`, `bb:set(key, value)`, `bb:clear(key)`, `bb:has(key)`.

**EventBus API:** `bus:on(event, callback)`, `bus:emit(event, payload)`.

**Schema:** `require("profiles/ProfileSchema")` — `Schema.defaults()` returns a complete empty profile table.

**Validator:** `require("profiles/ProfileValidator")` — `Validator.validate(profile)` returns `(bool, errors_array)`.

**File I/O:** `core.read_data_file(path)`, `core.write_data_file(path, content)`, `core.create_data_folder(path)`. Paths relative to `scripts_data/`.

**JSON:** `require("lib/JSON")` — `JSON.encode(tbl, pretty?)`, `JSON.decode(str)`.

**3D Graphics:** `core.graphics.circle_3d(pos, radius, color, thickness, z_priority)`, `core.graphics.line_3d(start, end, color, thickness, z_priority)`.

**Render callback:** `core.register_on_render_callback(function() ... end)` — called every frame during render phase.

**Menu keybind:** `core.menu.key_checkbox(default_key, initial_toggle, default_state, show_in_binds, mode, id)` — `element:get_keybind_state()` returns true when key activated.

**Test harness:** `TestUtil.install_core_stub({})` returns `{ core, fs, restore }`. Call `env.core._set_time(seconds)` to advance time. Stubs include `core.menu.key_checkbox` (returns stub with `:get_keybind_state()` → false).

**require() uses forward slashes:** `require("services/ProfileRecorder")` NOT dots.

### Key File Locations

| File | Purpose |
|------|---------|
| `SentinelCore/core/Client.lua` | Service wiring — instantiation at ~L182, services table ~L187, update order ~L205, public API ~L1179 |
| `SentinelCore/ui/window.lua` | Main UI — profiles tab at L1498-1686, Window.init at ~L1902 |
| `SentinelCore/events/Events.lua` | Event constants — profile section at L82-91 |
| `SentinelCore/profiles/ProfileSchema.lua` | Schema.defaults(), Schema.merge_target_filters() |
| `SentinelCore/profiles/ProfileValidator.lua` | Validator.validate(profile) |
| `SentinelCore/services/ProfileCoordinator.lua` | File I/O methods at L348-424, PROFILE_DIR = "SentinelCore/profiles/" |
| `SentinelCore/tests/TestUtil.lua` | install_core_stub with menu stubs at L128-138 |
| `SentinelGather/modules/PathVisualizer.lua` | Reference pattern for 3D overlay |

---

## Task 1: Add Recorder Events

**Files:**
- Modify: `SentinelCore/events/Events.lua:91` (after PROFILE_LOOP_COMPLETE)

**Step 1: Add 4 recorder events**

Insert after line 91 (`PROFILE_LOOP_COMPLETE`), before the Blackboard section:

```lua
    -- Profile recorder
    RECORDER_STARTED = "recorder.started",
    RECORDER_STOPPED = "recorder.stopped",
    RECORDER_HOTSPOT_ADDED = "recorder.hotspot_added",
    RECORDER_HOTSPOT_REMOVED = "recorder.hotspot_removed",
```

**Step 2: Commit**

```bash
git add SentinelCore/events/Events.lua
git commit -m "feat(profiles): add recorder events"
```

---

## Task 2: ProfileRecorder Service — Tests

**Files:**
- Create: `SentinelCore/tests/test_sc_profile_recorder.lua`

**Step 1: Write full test file**

```lua
-- SentinelCore/tests/test_sc_profile_recorder.lua
local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub({})
    env.core._set_time(1000)

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Events = require("events/Events")
    local ProfileRecorder = require("services/ProfileRecorder")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local log = { info = function() end, warn = function() end, error = function() end, debug = function() end }

    local recorder = ProfileRecorder:new(bus, bb, log)

    -- ── Test 1: Initial state is idle ──
    T.assert_eq(recorder:get_state(), "idle", "initial state is idle")
    T.assert_eq(bb:get("recorder.state"), nil, "no blackboard key before start")

    -- ── Test 2: Start recording (new profile) ──
    bb:set("player.map_id", 530)
    local ok = recorder:start_recording()
    T.assert_true(ok, "start_recording returns true")
    T.assert_eq(recorder:get_state(), "recording", "state is recording")
    T.assert_eq(bb:get("recorder.state"), "recording", "blackboard state is recording")

    local wp = bb:get("recorder.working_profile")
    T.assert_true(wp ~= nil, "working_profile on blackboard")
    T.assert_eq(wp.requirements.map_id, 530, "map_id auto-filled from blackboard")
    T.assert_eq(wp.version, "1.0", "schema version set")
    T.assert_eq(#wp.hotspots, 0, "no hotspots yet")

    -- ── Test 3: Add hotspot ──
    bb:set("player.position", { x = 100, y = 200, z = 50 })
    local events_seen = {}
    bus:on(Events.RECORDER_HOTSPOT_ADDED, function(p) events_seen[#events_seen + 1] = p end)

    recorder:add_hotspot()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.hotspots, 1, "one hotspot added")
    T.assert_eq(wp.hotspots[1].x, 100, "hotspot x from player position")
    T.assert_eq(wp.hotspots[1].y, 200, "hotspot y from player position")
    T.assert_eq(wp.hotspots[1].z, 50, "hotspot z from player position")
    T.assert_true(wp.hotspots[1].id ~= nil, "auto-generated ID")
    T.assert_eq(wp.hotspots[1].radius, 40, "default radius")
    T.assert_eq(bb:get("recorder.hotspot_count"), 1, "hotspot count updated")
    T.assert_eq(#events_seen, 1, "RECORDER_HOTSPOT_ADDED emitted")

    -- ── Test 4: Add second hotspot ──
    bb:set("player.position", { x = 300, y = 400, z = 60 })
    recorder:add_hotspot()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.hotspots, 2, "two hotspots")
    T.assert_eq(wp.hotspots[2].x, 300, "second hotspot x")
    T.assert_eq(bb:get("recorder.hotspot_count"), 2, "hotspot count is 2")

    -- ── Test 5: Add vendor ──
    bb:set("player.position", { x = 500, y = 600, z = 70 })
    recorder:add_vendor()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.vendors, 1, "one vendor added")
    T.assert_eq(wp.vendors[1].x, 500, "vendor x")
    T.assert_true(wp.vendors[1].sell, "vendor sell=true")
    T.assert_true(wp.vendors[1].repair, "vendor repair=true")

    -- ── Test 6: Add blackspot ──
    bb:set("player.position", { x = 700, y = 800, z = 80 })
    recorder:add_blackspot()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.blackspots, 1, "one blackspot added")
    T.assert_eq(wp.blackspots[1].x, 700, "blackspot x")

    -- ── Test 7: Remove last (blackspot) ──
    recorder:remove_last()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.blackspots, 0, "blackspot removed")
    T.assert_eq(#wp.vendors, 1, "vendor still present")
    T.assert_eq(#wp.hotspots, 2, "hotspots still present")

    -- ── Test 8: Remove last (vendor) ──
    recorder:remove_last()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.vendors, 0, "vendor removed")

    -- ── Test 9: Finish recording ──
    local stopped_events = {}
    bus:on(Events.RECORDER_STOPPED, function(p) stopped_events[#stopped_events + 1] = p end)

    local profile, err = recorder:finish_recording()
    T.assert_true(profile ~= nil, "finish returns profile")
    T.assert_eq(err, nil, "no error")
    T.assert_eq(recorder:get_state(), "idle", "state back to idle")
    T.assert_eq(bb:get("recorder.state"), nil, "blackboard recorder.state cleared")
    T.assert_eq(bb:get("recorder.working_profile"), nil, "blackboard working_profile cleared")
    T.assert_eq(#stopped_events, 1, "RECORDER_STOPPED emitted")
    T.assert_eq(#profile.hotspots, 2, "profile has 2 hotspots")

    -- ── Test 10: Cancel recording ──
    recorder:start_recording()
    bb:set("player.position", { x = 10, y = 20, z = 30 })
    recorder:add_hotspot()
    recorder:cancel_recording()
    T.assert_eq(recorder:get_state(), "idle", "cancelled back to idle")
    T.assert_eq(bb:get("recorder.state"), nil, "blackboard cleared after cancel")

    -- ── Test 11: Start recording with existing profile (edit mode) ──
    local existing = {
        version = "1.0",
        metadata = { name = "Test", author = "", description = "", tags = {}, created_at = 0, updated_at = 0 },
        requirements = { map_id = 1, min_level = 1, max_level = 80, class_restrictions = {} },
        target_defaults = { level_min = 60, level_max = 70, creature_types = {}, npc_blacklist = {}, npc_whitelist = {} },
        hotspots = {
            { id = "a", x = 1, y = 2, z = 3, radius = 30, label = "Spot A" },
        },
        blackspots = {},
        vendors = {},
        rest_spots = {},
        loop = true,
        dry_spell_secs = 15,
        travel_engage = true,
        overrides = {},
    }
    recorder:start_recording(existing)
    wp = bb:get("recorder.working_profile")
    T.assert_eq(#wp.hotspots, 1, "edit mode starts with existing hotspots")
    T.assert_eq(wp.hotspots[1].label, "Spot A", "existing labels preserved")
    T.assert_eq(wp.target_defaults.level_min, 60, "existing target defaults preserved")

    -- Verify deep copy (mutating working copy doesn't affect original)
    wp.metadata.name = "Modified"
    T.assert_eq(existing.metadata.name, "Test", "original not mutated")
    recorder:cancel_recording()

    -- ── Test 12: Cannot add hotspot when idle ──
    local idle_ok = recorder:add_hotspot()
    T.assert_true(not idle_ok, "add_hotspot returns false when idle")

    -- ── Test 13: Set hotspot radius ──
    recorder:start_recording()
    recorder:set_hotspot_radius(60)
    bb:set("player.position", { x = 1, y = 2, z = 3 })
    recorder:add_hotspot()
    wp = bb:get("recorder.working_profile")
    T.assert_eq(wp.hotspots[1].radius, 60, "custom radius applied")
    recorder:cancel_recording()

    return {
        sc_recorder_idle = true,
        sc_recorder_start = true,
        sc_recorder_add_hotspot = true,
        sc_recorder_add_vendor = true,
        sc_recorder_add_blackspot = true,
        sc_recorder_remove_last = true,
        sc_recorder_finish = true,
        sc_recorder_cancel = true,
        sc_recorder_edit_mode = true,
        sc_recorder_guards = true,
        sc_recorder_radius = true,
    }
end

return { run = run }
```

**Step 2: Commit test file**

```bash
git add SentinelCore/tests/test_sc_profile_recorder.lua
git commit -m "test(profiles): add ProfileRecorder unit tests (red)"
```

---

## Task 3: ProfileRecorder Service — Implementation

**Files:**
- Create: `SentinelCore/services/ProfileRecorder.lua`

**Step 1: Implement ProfileRecorder**

```lua
-- SentinelCore/services/ProfileRecorder.lua
local Events = require("events/Events")
local Schema = require("profiles/ProfileSchema")
local Validator = require("profiles/ProfileValidator")

local ProfileRecorder = {}
ProfileRecorder.__index = ProfileRecorder

local DEFAULT_HOTSPOT_RADIUS = 40

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[deep_copy(k)] = deep_copy(v) end
    return out
end

function ProfileRecorder:new(event_bus, blackboard, logger)
    local o = setmetatable({}, self)
    o._bus = event_bus
    o._bb = blackboard
    o._log = logger
    o._state = "idle"
    o._working_profile = nil
    o._history = {}          -- ordered list of { type = "hotspot"|"vendor"|"blackspot" }
    o._hotspot_radius = DEFAULT_HOTSPOT_RADIUS
    o._hotspot_counter = 0
    return o
end

function ProfileRecorder:get_state()
    return self._state
end

function ProfileRecorder:get_working_profile()
    return self._working_profile
end

function ProfileRecorder:set_hotspot_radius(radius)
    self._hotspot_radius = tonumber(radius) or DEFAULT_HOTSPOT_RADIUS
end

function ProfileRecorder:get_hotspot_radius()
    return self._hotspot_radius
end

function ProfileRecorder:start_recording(existing_profile)
    if self._state == "recording" then
        return false, "already recording"
    end

    if existing_profile then
        self._working_profile = deep_copy(existing_profile)
        self._hotspot_counter = #self._working_profile.hotspots
    else
        self._working_profile = Schema.defaults()
        self._hotspot_counter = 0
    end

    -- Auto-fill map_id from player's current map
    local map_id = self._bb:get("player.map_id")
    if map_id and (self._working_profile.requirements.map_id == 0 or not existing_profile) then
        self._working_profile.requirements.map_id = tonumber(map_id) or 0
    end

    self._history = {}
    self._state = "recording"
    self._bb:set("recorder.state", "recording")
    self._bb:set("recorder.working_profile", self._working_profile)
    self._bb:set("recorder.hotspot_count", #self._working_profile.hotspots)

    self._log:info("recording started (hotspots: %d)", #self._working_profile.hotspots)
    self._bus:emit(Events.RECORDER_STARTED, {
        editing = existing_profile ~= nil,
        hotspot_count = #self._working_profile.hotspots,
    })

    return true
end

function ProfileRecorder:add_hotspot(label)
    if self._state ~= "recording" then return false end

    local pos = self._bb:get("player.position")
    if not pos then
        self._log:warn("cannot add hotspot: no player position")
        return false
    end

    self._hotspot_counter = self._hotspot_counter + 1
    local hs = {
        id = "hs_" .. self._hotspot_counter,
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = self._hotspot_radius,
        label = label or "",
    }

    local hotspots = self._working_profile.hotspots
    hotspots[#hotspots + 1] = hs
    self._history[#self._history + 1] = { type = "hotspot" }

    self._bb:set("recorder.working_profile", self._working_profile)
    self._bb:set("recorder.hotspot_count", #hotspots)

    self._log:info("hotspot #%d added at (%.0f, %.0f, %.0f) r=%d",
        #hotspots, pos.x, pos.y, pos.z, self._hotspot_radius)
    self._bus:emit(Events.RECORDER_HOTSPOT_ADDED, {
        index = #hotspots,
        hotspot = hs,
    })

    return true
end

function ProfileRecorder:add_vendor()
    if self._state ~= "recording" then return false end

    local pos = self._bb:get("player.position")
    if not pos then return false end

    local vendor = {
        x = pos.x, y = pos.y, z = pos.z,
        name = "", npc_id = 0,
        sell = true, repair = true, food = false, water = false,
    }

    local vendors = self._working_profile.vendors
    vendors[#vendors + 1] = vendor
    self._history[#self._history + 1] = { type = "vendor" }

    self._bb:set("recorder.working_profile", self._working_profile)
    self._log:info("vendor marker added at (%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z)

    return true
end

function ProfileRecorder:add_blackspot(radius)
    if self._state ~= "recording" then return false end

    local pos = self._bb:get("player.position")
    if not pos then return false end

    local bs = {
        x = pos.x, y = pos.y, z = pos.z,
        radius = tonumber(radius) or 20,
    }

    local blackspots = self._working_profile.blackspots
    blackspots[#blackspots + 1] = bs
    self._history[#self._history + 1] = { type = "blackspot" }

    self._bb:set("recorder.working_profile", self._working_profile)
    self._log:info("blackspot added at (%.0f, %.0f, %.0f)", pos.x, pos.y, pos.z)

    return true
end

function ProfileRecorder:remove_last()
    if self._state ~= "recording" then return false end
    if #self._history == 0 then return false end

    local last = self._history[#self._history]
    self._history[#self._history] = nil

    if last.type == "hotspot" then
        local hs = self._working_profile.hotspots
        hs[#hs] = nil
        self._bb:set("recorder.hotspot_count", #hs)
        self._bus:emit(Events.RECORDER_HOTSPOT_REMOVED, { index = #hs + 1 })
    elseif last.type == "vendor" then
        local v = self._working_profile.vendors
        v[#v] = nil
    elseif last.type == "blackspot" then
        local bs = self._working_profile.blackspots
        bs[#bs] = nil
    end

    self._bb:set("recorder.working_profile", self._working_profile)
    self._log:info("removed last %s", last.type)

    return true
end

function ProfileRecorder:finish_recording()
    if self._state ~= "recording" then
        return nil, "not recording"
    end

    local profile = self._working_profile

    -- Validate before returning
    local ok, errors = Validator.validate(profile)
    if not ok then
        local msg = table.concat(errors, "; ")
        self._log:warn("profile validation failed: %s", msg)
        return nil, msg
    end

    -- Clean up
    self._working_profile = nil
    self._history = {}
    self._state = "idle"
    self._bb:clear("recorder.state")
    self._bb:clear("recorder.working_profile")
    self._bb:clear("recorder.hotspot_count")

    self._log:info("recording finished (%d hotspots)", #profile.hotspots)
    self._bus:emit(Events.RECORDER_STOPPED, { profile = profile })

    return profile, nil
end

function ProfileRecorder:cancel_recording()
    if self._state ~= "recording" then return false end

    self._working_profile = nil
    self._history = {}
    self._state = "idle"
    self._bb:clear("recorder.state")
    self._bb:clear("recorder.working_profile")
    self._bb:clear("recorder.hotspot_count")

    self._log:info("recording cancelled")
    self._bus:emit(Events.RECORDER_STOPPED, { cancelled = true })

    return true
end

--- Called from service update loop. Checks keybind for hotspot recording.
---@param keybind_element any  key_checkbox menu element (or nil)
function ProfileRecorder:update(keybind_element)
    if self._state ~= "recording" then return end
    if not keybind_element then return end

    if keybind_element:get_keybind_state() then
        self:add_hotspot()
    end
end

return ProfileRecorder
```

**Step 2: Run tests in-game**

Call `_G.SentinelCore.run_tests()` — all `sc_recorder_*` tests must pass.

**Step 3: Commit**

```bash
git add SentinelCore/services/ProfileRecorder.lua
git commit -m "feat(profiles): add ProfileRecorder service with FSM"
```

---

## Task 4: ProfileOverlay (3D World Rendering)

**Files:**
- Create: `SentinelCore/ui/ProfileOverlay.lua`

**Step 1: Implement overlay**

```lua
-- SentinelCore/ui/ProfileOverlay.lua
local color = require("common/color")

local ProfileOverlay = {}
ProfileOverlay.__index = ProfileOverlay

local COLORS = {
    hotspot = color.new(48, 209, 88, 180),         -- green
    hotspot_selected = color.new(255, 255, 255, 220), -- white
    route_line = color.new(50, 173, 230, 150),      -- cyan
    loop_line = color.new(50, 173, 230, 80),        -- cyan dimmer
    blackspot = color.new(255, 69, 58, 150),        -- red
    vendor = color.new(255, 159, 10, 180),          -- orange
    recording_pulse = color.new(48, 209, 88, 120),  -- green translucent
}

function ProfileOverlay:new(blackboard)
    local o = setmetatable({}, self)
    o._bb = blackboard
    o._enabled = true
    o._selected_index = 0
    o._pulse_phase = 0

    core.register_on_render_callback(function()
        if o._enabled then
            o:_render()
        end
    end)

    return o
end

function ProfileOverlay:set_selected_index(idx)
    self._selected_index = idx or 0
end

function ProfileOverlay:set_enabled(enabled)
    self._enabled = enabled
end

function ProfileOverlay:_render()
    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then return end

    -- Determine which profile to render
    local profile = nil
    local recorder_state = self._bb:get("recorder.state")

    if recorder_state == "recording" then
        profile = self._bb:get("recorder.working_profile")
    else
        -- Show active grinding profile if loaded
        local active = self._bb:get("profile.active")
        if active then
            profile = active
        end
    end

    if not profile then return end

    local player_pos = player:get_position()
    self._pulse_phase = self._pulse_phase + 0.05
    if self._pulse_phase > 6.28 then self._pulse_phase = 0 end

    self:_render_hotspots(profile, player_pos)
    self:_render_route_lines(profile)
    self:_render_blackspots(profile)
    self:_render_vendors(profile)

    if recorder_state == "recording" then
        self:_render_recording_indicator(player_pos)
    end
end

function ProfileOverlay:_render_hotspots(profile, player_pos)
    local hotspots = profile.hotspots
    if not hotspots then return end

    for i = 1, #hotspots do
        local hs = hotspots[i]
        local pos = { x = hs.x, y = hs.y, z = hs.z }
        local radius = hs.radius or 40
        local is_selected = (i == self._selected_index)
        local c = is_selected and COLORS.hotspot_selected or COLORS.hotspot
        local thickness = is_selected and 3 or 2

        core.graphics.circle_3d(pos, radius, c, thickness, 2.5)
        core.graphics.circle_3d(pos, 1.0, c, 2, 2.5)
    end
end

function ProfileOverlay:_render_route_lines(profile)
    local hotspots = profile.hotspots
    if not hotspots or #hotspots < 2 then return end

    for i = 1, #hotspots - 1 do
        local a = hotspots[i]
        local b = hotspots[i + 1]
        core.graphics.line_3d(
            { x = a.x, y = a.y, z = a.z },
            { x = b.x, y = b.y, z = b.z },
            COLORS.route_line, 2, 2.0
        )
    end

    -- Loop-back line
    if profile.loop and #hotspots >= 2 then
        local first = hotspots[1]
        local last = hotspots[#hotspots]
        core.graphics.line_3d(
            { x = last.x, y = last.y, z = last.z },
            { x = first.x, y = first.y, z = first.z },
            COLORS.loop_line, 1, 2.0
        )
    end
end

function ProfileOverlay:_render_blackspots(profile)
    local blackspots = profile.blackspots
    if not blackspots then return end

    for i = 1, #blackspots do
        local bs = blackspots[i]
        local pos = { x = bs.x, y = bs.y, z = bs.z }
        core.graphics.circle_3d(pos, bs.radius or 20, COLORS.blackspot, 2, 2.0)
    end
end

function ProfileOverlay:_render_vendors(profile)
    local vendors = profile.vendors
    if not vendors then return end

    for i = 1, #vendors do
        local v = vendors[i]
        local pos = { x = v.x, y = v.y, z = v.z }
        core.graphics.circle_3d(pos, 3, COLORS.vendor, 2, 2.5)
    end
end

function ProfileOverlay:_render_recording_indicator(player_pos)
    local pulse = 2.0 + math.sin(self._pulse_phase) * 1.0
    core.graphics.circle_3d(player_pos, pulse, COLORS.recording_pulse, 2, 3.0)
end

return ProfileOverlay
```

**Step 2: Commit**

```bash
git add SentinelCore/ui/ProfileOverlay.lua
git commit -m "feat(profiles): add ProfileOverlay 3D world rendering"
```

---

## Task 5: Wire ProfileRecorder + Overlay into Client

**Files:**
- Modify: `SentinelCore/core/Client.lua`

**Step 1: Add require at top**

Add near other service requires (around line 28, after ProfileCoordinator require):

```lua
local ProfileRecorder = require("services/ProfileRecorder")
local ProfileOverlay = require("ui/ProfileOverlay")
```

**Step 2: Instantiate recorder and overlay**

After ProfileCoordinator instantiation (~line 185), add:

```lua
local profile_recorder = config.profile_recorder or ProfileRecorder:new(
    o._event_bus, o._blackboard, Logger:new("ProfileRec")
)

local profile_overlay = ProfileOverlay:new(o._blackboard)
```

**Step 3: Add to services table**

In `o._services = {` (around line 187), add entries:

```lua
profile_recorder = profile_recorder,
profile_overlay = profile_overlay,
```

**Step 4: Add to update order**

In `o._service_update_order` (around line 205), add after "profile_coordinator":

```lua
"profile_recorder",
```

(ProfileOverlay does NOT go in update order — it renders via `core.register_on_render_callback`.)

**Step 5: Add keybind menu element**

In the Client constructor, after service instantiation, create the keybind:

```lua
-- Record hotspot keybind (Insert key = 0x2D = 45)
o._record_hotspot_keybind = core.menu.key_checkbox(45, false, false, true, 0, "sc_record_hotspot")
```

**Step 6: Update the service update dispatch**

Find where services are updated (look for the update loop that iterates `_service_update_order`). For `profile_recorder`, pass the keybind:

In the update dispatch, the recorder needs its keybind. The simplest approach: override the recorder's update call in the main update loop. Find the service update loop and add a special case, OR modify the ProfileRecorder to hold the keybind reference.

**Simpler approach:** Pass keybind to recorder constructor and let it store internally:

Revise ProfileRecorder constructor to accept optional keybind:
```lua
function ProfileRecorder:new(event_bus, blackboard, logger, keybind_element)
    ...
    o._keybind = keybind_element
    ...
end
```

And update() reads from `self._keybind` instead of parameter.

Update Client instantiation:
```lua
-- Create keybind first
local record_hotspot_keybind = core.menu.key_checkbox(45, false, false, true, 0, "sc_record_hotspot")

local profile_recorder = config.profile_recorder or ProfileRecorder:new(
    o._event_bus, o._blackboard, Logger:new("ProfileRec"), record_hotspot_keybind
)
```

**Step 7: Add public API methods**

After the existing grinding profile methods (~line 1201), add:

```lua
function Client:start_recording(existing_profile)
    return self._services.profile_recorder:start_recording(existing_profile)
end

function Client:stop_recording()
    return self._services.profile_recorder:finish_recording()
end

function Client:cancel_recording()
    return self._services.profile_recorder:cancel_recording()
end

function Client:get_recorder_state()
    return self._services.profile_recorder:get_state()
end

function Client:get_profile_overlay()
    return self._services.profile_overlay
end
```

**Step 8: Commit**

```bash
git add SentinelCore/core/Client.lua SentinelCore/services/ProfileRecorder.lua
git commit -m "feat(profiles): wire ProfileRecorder + Overlay into Client"
```

---

## Task 6: Extract profile_tab.lua — Browse Mode

**Files:**
- Create: `SentinelCore/ui/tabs/profile_tab.lua`
- Modify: `SentinelCore/ui/window.lua`

**Step 1: Create the tabs directory and extract existing profiles tab code**

Create `SentinelCore/ui/tabs/profile_tab.lua`. This file exports a function that receives the tab builder, client reference, and shared state, then renders the profiles tab content.

```lua
-- SentinelCore/ui/tabs/profile_tab.lua
local vec2 = require("common/geometry/vector_2")
local enums = require("common/enums")
local color = require("common/color")
local AstroUI = require("lib/AstroUI")
local get_now = require("lib/TimeHelper").get_now
local Schema = require("profiles/ProfileSchema")
local Validator = require("profiles/ProfileValidator")

local LAYOUT = AstroUI.LAYOUT

local profile_tab = {}

-- Persistent state across frames
local _selected_profile_index = 1
local _last_profile_result = nil
local _editor_mode = "browse" -- "browse" | "edit"
local _editor_profile = nil   -- working copy being edited

-- Menu elements (created once)
local _menu_elements = nil

local function lighten_color(base_color, amount)
    local r, g, b, a = base_color:get()
    return color.new(
        math.min(255, r + amount),
        math.min(255, g + amount),
        math.min(255, b + amount),
        a
    )
end

local function make_btn(window, colors, bx, bw, y_offset, button_h, label, enabled)
    local s = vec2.new(bx, y_offset)
    local e = vec2.new(bx + bw, y_offset + button_h)
    local hov = enabled and window:is_mouse_hovering_rect(s, e) or false
    if hov then window:is_mouse_hovering_rect_block_movement(s, e) end
    local bg = enabled
        and (hov and lighten_color(colors.primary_accent, 15) or colors.primary_accent)
        or colors.checkbox_inactive
    window:render_rect_filled(s, e, bg, 8)
    local ts = window:get_text_size(label)
    window:render_text(enums.window_enums.font_id.FONT_SMALL,
        vec2.new(bx + (bw - ts.x) / 2, y_offset + (button_h - ts.y) / 2),
        enabled and colors.text_primary or colors.text_disabled, label)
    return enabled and hov and window:is_rect_clicked(s, e)
end

local function ensure_menu_elements()
    if _menu_elements then return end
    _menu_elements = {
        name = core.menu.text_input("New Profile", "sc_pe_name"),
        min_level = core.menu.slider_int(1, 80, 1, "sc_pe_min_level"),
        max_level = core.menu.slider_int(1, 80, 80, "sc_pe_max_level"),
        target_min = core.menu.slider_int(1, 80, 1, "sc_pe_target_min"),
        target_max = core.menu.slider_int(1, 80, 80, "sc_pe_target_max"),
        npc_blacklist = core.menu.text_input("", "sc_pe_npc_bl"),
        npc_whitelist = core.menu.text_input("", "sc_pe_npc_wl"),
        hotspot_radius = core.menu.slider_int(10, 100, 40, "sc_pe_hs_radius"),
        filename = core.menu.text_input("my_profile.json", "sc_pe_filename"),
        loop = core.menu.checkbox(true, "sc_pe_loop"),
        dry_spell = core.menu.slider_int(5, 60, 15, "sc_pe_dry_spell"),
    }
end

--- Enter edit mode with a new or existing profile
local function enter_edit_mode(client, existing_profile)
    ensure_menu_elements()
    _editor_mode = "edit"

    if existing_profile then
        client:start_recording(existing_profile)
    else
        client:start_recording()
    end

    -- Sync menu elements to working profile
    local wp = client._services.blackboard:get("recorder.working_profile")
    if wp then
        _menu_elements.name:set(wp.metadata.name or "New Profile")
        _menu_elements.min_level:set(wp.requirements.min_level or 1)
        _menu_elements.max_level:set(wp.requirements.max_level or 80)
        _menu_elements.target_min:set(wp.target_defaults.level_min or 1)
        _menu_elements.target_max:set(wp.target_defaults.level_max or 80)
        _menu_elements.loop:set(wp.loop ~= false)
        _menu_elements.dry_spell:set(wp.dry_spell_secs or 15)
    end
end

local function exit_edit_mode(client)
    _editor_mode = "browse"
    local recorder_state = client:get_recorder_state()
    if recorder_state == "recording" then
        client:cancel_recording()
    end
end

--- Sync menu element values back into the working profile
local function sync_form_to_profile(client)
    local bb = client._services.blackboard
    local wp = bb:get("recorder.working_profile")
    if not wp then return end

    wp.metadata.name = _menu_elements.name:get_text() or "New Profile"
    wp.requirements.min_level = _menu_elements.min_level:get()
    wp.requirements.max_level = _menu_elements.max_level:get()
    wp.target_defaults.level_min = _menu_elements.target_min:get()
    wp.target_defaults.level_max = _menu_elements.target_max:get()
    wp.loop = _menu_elements.loop:get_state()
    wp.dry_spell_secs = _menu_elements.dry_spell:get()

    -- Parse comma-separated NPC lists
    local function parse_ids(text)
        local ids = {}
        for id in (text or ""):gmatch("(%d+)") do
            ids[#ids + 1] = tonumber(id)
        end
        return ids
    end
    wp.target_defaults.npc_blacklist = parse_ids(_menu_elements.npc_blacklist:get_text())
    wp.target_defaults.npc_whitelist = parse_ids(_menu_elements.npc_whitelist:get_text())

    -- Update hotspot radius for next recording
    local recorder = client._services.profile_recorder
    if recorder then
        recorder:set_hotspot_radius(_menu_elements.hotspot_radius:get())
    end

    bb:set("recorder.working_profile", wp)
end

function profile_tab.render_browse(t, client)
    -- 1. Active Profile status
    t:row_list({
        label = "Active Profile",
        elements = {
            {
                type = "info",
                label = "Profile ID",
                value_fn = function()
                    return client and client.get_active_profile_id and client:get_active_profile_id() or "default"
                end,
            },
        },
    })

    -- 1b. Grinding Profile status
    t:row_list({
        label = "Grinding Profile",
        elements = {
            {
                type = "info",
                label = "Status",
                tooltip = "Grinding profile FSM state (idle / at_hotspot / traveling / vendor_trip)",
                value_fn = function()
                    if not client then return "N/A" end
                    return client.get_grinding_profile_state
                        and client:get_grinding_profile_state() or "idle"
                end,
                color_fn = function()
                    if not client then return nil end
                    local state = client.get_grinding_profile_state
                        and client:get_grinding_profile_state() or "idle"
                    if state == "at_hotspot" then return color.new(48, 209, 88, 255) end
                    if state == "traveling" then return color.new(255, 214, 10, 255) end
                    if state == "vendor_trip" then return color.new(255, 159, 10, 255) end
                    return nil
                end,
            },
            {
                type = "info",
                label = "Current Hotspot",
                value_fn = function()
                    if not client then return "-" end
                    local bb = client._services and client._services.blackboard
                    local hs = bb and bb:get("profile.current_hotspot")
                    return hs and tostring(hs.label or hs.id) or "-"
                end,
            },
        },
    })

    -- 2. Saved Profiles listbox
    t:listbox({
        label = "Saved Profiles",
        id = "profiles_list",
        elements = {
            {
                id = "profile_listbox",
                visible_rows = 6,
                entries_fn = function()
                    local coord = client._services and client._services.profile_coordinator
                    local profiles = coord and coord:list_profile_files() or {}
                    local entries = {}
                    for i = 1, #profiles do
                        entries[#entries + 1] = {
                            label = profiles[i].name or profiles[i].filename,
                            sublabel = profiles[i].filename,
                        }
                    end
                    return entries
                end,
                on_select = function(idx) _selected_profile_index = idx end,
            },
        },
    })

    -- 3. Browse action buttons
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local coord = client._services and client._services.profile_coordinator
            local profiles = coord and coord:list_profile_files() or {}
            local button_h = 28
            local gap = 8
            local btn_count = 5
            local btn_w = math.floor((width - gap * (btn_count - 1)) / btn_count)

            local bx = x

            -- Load from file
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Load", #profiles > 0) then
                if _selected_profile_index >= 1 and _selected_profile_index <= #profiles then
                    local entry = profiles[_selected_profile_index]
                    local ok, err = coord:load_profile_from_file(entry.filename)
                    if ok then
                        client:load_grinding_profile(coord._profile)
                        _last_profile_result = "Loaded " .. entry.name
                    else
                        _last_profile_result = "Load failed: " .. tostring(err)
                    end
                end
            end

            bx = bx + btn_w + gap
            -- Unload
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Unload",
                    client.get_grinding_profile_state and client:get_grinding_profile_state() ~= "idle") then
                client:unload_grinding_profile()
                _last_profile_result = "Profile unloaded"
            end

            bx = bx + btn_w + gap
            -- Delete
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Delete", #profiles > 0) then
                if _selected_profile_index >= 1 and _selected_profile_index <= #profiles then
                    local entry = profiles[_selected_profile_index]
                    -- Delete by removing from manifest (simplified)
                    _last_profile_result = "Delete: " .. entry.filename .. " (remove file manually)"
                end
            end

            bx = bx + btn_w + gap
            -- New Profile → enter editor
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "New", true) then
                enter_edit_mode(client, nil)
            end

            bx = bx + btn_w + gap
            -- Edit existing → load selected into editor
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Edit", #profiles > 0) then
                if _selected_profile_index >= 1 and _selected_profile_index <= #profiles then
                    local entry = profiles[_selected_profile_index]
                    local ok = coord:load_profile_from_file(entry.filename)
                    if ok then
                        enter_edit_mode(client, coord._profile)
                    else
                        _last_profile_result = "Cannot edit: load failed"
                    end
                end
            end

            y_offset = y_offset + button_h + 8

            -- Status feedback
            if _last_profile_result then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), colors.text_secondary,
                    "Status: " .. tostring(_last_profile_result))
                y_offset = y_offset + 18
            end

            return y_offset
        end,
    })
end

function profile_tab.render_edit(t, client)
    ensure_menu_elements()

    local bb = client._services and client._services.blackboard
    local recorder = client._services and client._services.profile_recorder
    local wp = bb and bb:get("recorder.working_profile")

    -- Sync form values to profile each frame
    sync_form_to_profile(client)

    -- 1. Metadata form
    t:row_list({
        label = "Profile Metadata",
        elements = {
            { type = "info", label = "Map ID",
              value_fn = function() return wp and tostring(wp.requirements.map_id) or "?" end },
        },
    })

    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            -- Name input
            _menu_elements.name:render("Profile Name", "Name for this grinding profile")
            y_offset = y_offset + LAYOUT.element_height + 4

            -- Level range
            _menu_elements.min_level:render("Min Level", "Minimum player level requirement")
            y_offset = y_offset + LAYOUT.element_height + 4
            _menu_elements.max_level:render("Max Level", "Maximum player level requirement")
            y_offset = y_offset + LAYOUT.element_height + 4

            return y_offset
        end,
    })

    -- 2. Target filters
    t:custom_render({
        render_fn = function(self, y_offset)
            _menu_elements.target_min:render("Target Level Min", "Minimum mob level to engage")
            y_offset = y_offset + LAYOUT.element_height + 4
            _menu_elements.target_max:render("Target Level Max", "Maximum mob level to engage")
            y_offset = y_offset + LAYOUT.element_height + 4
            _menu_elements.npc_blacklist:render("NPC Blacklist (IDs)", "Comma-separated NPC IDs to avoid")
            y_offset = y_offset + LAYOUT.element_height + 4
            _menu_elements.npc_whitelist:render("NPC Whitelist (IDs)", "Comma-separated NPC IDs to target exclusively")
            y_offset = y_offset + LAYOUT.element_height + 4
            return y_offset
        end,
    })

    -- 3. Behavior settings
    t:custom_render({
        render_fn = function(self, y_offset)
            _menu_elements.loop:render("Loop Profile", "Restart from first hotspot after completing the route")
            y_offset = y_offset + LAYOUT.element_height + 4
            _menu_elements.dry_spell:render("Dry Spell (sec)", "Seconds without targets before advancing to next hotspot")
            y_offset = y_offset + LAYOUT.element_height + 4
            return y_offset
        end,
    })

    -- 4. Hotspot list
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            -- Section header
            local hotspots = wp and wp.hotspots or {}
            local header = string.format("Hotspots (%d)", #hotspots)
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y_offset), colors.text_primary, header)
            y_offset = y_offset + 20

            -- List each hotspot
            local item_h = 22
            local overlay = client._services and client._services.profile_overlay
            for i = 1, #hotspots do
                local hs = hotspots[i]
                local label = string.format("#%d: (%.0f, %.0f, %.0f) r=%d %s",
                    i, hs.x or 0, hs.y or 0, hs.z or 0, hs.radius or 40, hs.label or "")

                -- Clickable row
                local row_s = vec2.new(x, y_offset)
                local row_e = vec2.new(x + width - 60, y_offset + item_h)
                local hov = window:is_mouse_hovering_rect(row_s, row_e)
                if hov then window:is_mouse_hovering_rect_block_movement(row_s, row_e) end

                if hov then
                    window:render_rect_filled(row_s, row_e, colors.slider_bg, 4)
                end
                if hov and window:is_rect_clicked(row_s, row_e) and overlay then
                    overlay:set_selected_index(i)
                end

                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + 4, y_offset + 2), colors.text_secondary, label)

                -- Remove button
                local rm_x = x + width - 50
                if make_btn(window, colors, rm_x, 45, y_offset, item_h, "Del", true) then
                    table.remove(hotspots, i)
                    bb:set("recorder.working_profile", wp)
                    bb:set("recorder.hotspot_count", #hotspots)
                    break -- list changed, re-render next frame
                end

                y_offset = y_offset + item_h + 2
            end

            if #hotspots == 0 then
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x + 4, y_offset), colors.text_disabled,
                    "No hotspots. Press record keybind or Start Recording.")
                y_offset = y_offset + 20
            end

            return y_offset + 8
        end,
    })

    -- 5. Recording controls
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)

            local is_recording = recorder and recorder:get_state() == "recording"
            local button_h = 28
            local gap = 8
            local btn_w = math.floor((width - gap * 3) / 4)

            -- Recording status
            local rec_label = is_recording and "Recording... (press keybind to add hotspot)" or "Not recording"
            local rec_color = is_recording and color.new(255, 69, 58, 255) or colors.text_disabled
            window:render_text(enums.window_enums.font_id.FONT_SMALL,
                vec2.new(x, y_offset), rec_color, rec_label)
            y_offset = y_offset + 20

            local bx = x

            -- Add Vendor
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Vendor", is_recording) then
                recorder:add_vendor()
            end

            bx = bx + btn_w + gap
            -- Add Blackspot
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Add Blackspot", is_recording) then
                recorder:add_blackspot()
            end

            bx = bx + btn_w + gap
            -- Undo Last
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Undo Last", is_recording) then
                recorder:remove_last()
            end

            bx = bx + btn_w + gap
            -- Hotspot radius
            _menu_elements.hotspot_radius:render("Radius", "Radius for next recorded hotspot")

            y_offset = y_offset + button_h + 12
            return y_offset
        end,
    })

    -- 6. Save / Cancel buttons
    t:custom_render({
        render_fn = function(self, y_offset)
            local window = self.window
            local colors = self.colors
            local x = LAYOUT.padding_side
            local width = window:get_size().x - (2 * LAYOUT.padding_side)
            local button_h = 28
            local gap = 8

            -- Filename input
            _menu_elements.filename:render("Filename", "Save as (e.g. netherstorm.json)")
            y_offset = y_offset + LAYOUT.element_height + 8

            local btn_w = math.floor((width - gap * 2) / 3)
            local bx = x

            -- Save
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save", true) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = _menu_elements.filename:get_text() or "profile.json"
                    if not fname:find("%.json$") then fname = fname .. ".json" end

                    local coord = client._services.profile_coordinator
                    -- Temporarily load to save via coordinator
                    local load_ok = coord:load_profile(profile)
                    if load_ok then
                        local save_ok, save_err = coord:save_profile_to_file(fname)
                        _last_profile_result = save_ok and ("Saved: " .. fname)
                            or ("Save failed: " .. tostring(save_err))
                        coord:unload_profile()
                    else
                        _last_profile_result = "Validation failed"
                    end
                else
                    _last_profile_result = "Cannot save: " .. tostring(err)
                    -- Re-start recording so user can fix issues
                    recorder:start_recording(wp)
                end
                if not recorder or recorder:get_state() == "idle" then
                    _editor_mode = "browse"
                end
            end

            bx = bx + btn_w + gap
            -- Save & Load
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Save & Load", true) then
                sync_form_to_profile(client)
                local profile, err = recorder:finish_recording()
                if profile then
                    local fname = _menu_elements.filename:get_text() or "profile.json"
                    if not fname:find("%.json$") then fname = fname .. ".json" end

                    local coord = client._services.profile_coordinator
                    local load_ok = coord:load_profile(profile)
                    if load_ok then
                        coord:save_profile_to_file(fname)
                        client:load_grinding_profile(profile)
                        _last_profile_result = "Saved & loaded: " .. fname
                    else
                        _last_profile_result = "Validation failed"
                    end
                else
                    _last_profile_result = "Cannot save: " .. tostring(err)
                    recorder:start_recording(wp)
                end
                _editor_mode = "browse"
            end

            bx = bx + btn_w + gap
            -- Cancel
            if make_btn(window, colors, bx, btn_w, y_offset, button_h, "Cancel", true) then
                exit_edit_mode(client)
            end

            y_offset = y_offset + button_h + 8

            -- Validation feedback
            if _last_profile_result then
                local is_err = _last_profile_result:find("fail") or _last_profile_result:find("Cannot")
                local fb_color = is_err and color.new(255, 69, 58, 255) or colors.text_secondary
                window:render_text(enums.window_enums.font_id.FONT_SMALL,
                    vec2.new(x, y_offset), fb_color,
                    "Status: " .. tostring(_last_profile_result))
                y_offset = y_offset + 18
            end

            return y_offset
        end,
    })
end

--- Main render entry point called from window.lua
function profile_tab.render(t, client)
    if _editor_mode == "edit" then
        profile_tab.render_edit(t, client)
    else
        profile_tab.render_browse(t, client)
    end
end

--- Get editor mode for external queries
function profile_tab.get_editor_mode()
    return _editor_mode
end

return profile_tab
```

**Step 2: Replace inline profiles tab in window.lua**

At the top of window.lua, add require (after other requires around line 12):

```lua
local profile_tab = require("ui/tabs/profile_tab")
```

Replace lines 1498-1686 (the entire `ui:add_tab({ id = "profiles" ...` block) with:

```lua
    ui:add_tab({ id = "profiles", label = "Profiles" }, function(t)
        profile_tab.render(t, _client)
    end)
```

This removes ~190 lines from window.lua and delegates to the extracted module.

**Step 3: Commit**

```bash
git add SentinelCore/ui/tabs/profile_tab.lua SentinelCore/ui/window.lua
git commit -m "feat(profiles): extract profile tab with browse + edit modes"
```

---

## Task 7: Render Keybind in UI + Manual Integration Test

**Files:**
- Modify: `SentinelCore/ui/tabs/profile_tab.lua` (add keybind render)

**Step 1: Add keybind rendering**

In `render_edit`, in the recording controls section, render the keybind element so the user can see/change the bound key. After the recording status text, before the action buttons:

```lua
-- Render the record keybind for user configuration
local keybind = recorder and recorder._keybind
if keybind then
    keybind:render("Record Hotspot Key", "Press this key while recording to drop a hotspot at your position")
    y_offset = y_offset + LAYOUT.element_height + 4
end
```

**Step 2: Commit**

```bash
git add SentinelCore/ui/tabs/profile_tab.lua
git commit -m "feat(profiles): render record keybind in editor controls"
```

---

## Task 8: Update Manifest on Save

**Files:**
- Modify: `SentinelCore/services/ProfileCoordinator.lua`

**Step 1: Add manifest update helper**

After `save_profile_to_file`, add a method that updates `manifest.json` to include the newly saved profile:

```lua
function ProfileCoordinator:_update_manifest(filename, profile_name)
    local manifest_path = PROFILE_DIR .. "manifest.json"
    local JSON = require("lib/JSON")

    local content = core.read_data_file(manifest_path)
    local manifest = { profiles = {} }
    if content and content ~= "" then
        local parsed = JSON.decode(content)
        if type(parsed) == "table" then
            manifest = parsed
            if not manifest.profiles then manifest.profiles = manifest end
        end
    end

    -- Check if filename already in manifest
    local found = false
    local profiles = manifest.profiles or manifest
    if type(profiles) ~= "table" then profiles = {} end
    for i = 1, #profiles do
        local entry = profiles[i]
        if type(entry) == "table" and entry.filename == filename then
            entry.name = profile_name or filename
            found = true
            break
        end
    end

    if not found then
        profiles[#profiles + 1] = {
            filename = filename,
            name = profile_name or filename,
        }
    end

    local out = JSON.encode({ profiles = profiles }, true)
    if out then
        core.write_data_file(manifest_path, out)
    end
end
```

**Step 2: Call manifest update in save_profile_to_file**

In `save_profile_to_file`, after `core.write_data_file(path, content)`, add:

```lua
self:_update_manifest(filename, self._profile.metadata.name)
```

**Step 3: Commit**

```bash
git add SentinelCore/services/ProfileCoordinator.lua
git commit -m "feat(profiles): auto-update manifest.json on profile save"
```

---

## Task 9: Final Review and Cleanup

**Step 1: Run all tests**

In-game: `_G.SentinelCore.run_tests()` — verify all existing tests still pass plus new recorder tests.

**Step 2: Manual smoke test**

1. Open SentinelCore UI → Profiles tab
2. Click "New" → verify editor mode with form fields
3. Set profile name, level range
4. Press Insert at 3 locations → verify hotspots appear in list and 3D overlay shows circles + route lines
5. Click "Add Vendor" → verify vendor marker (orange) in overlay
6. Click "Undo Last" → verify vendor removed
7. Click "Save & Load" → verify profile saves to file and grinding FSM starts
8. Close and reopen UI → verify profile appears in saved list
9. Click "Load" on saved profile → verify it loads

**Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix(profiles): editor smoke test fixes"
```

---

## File Summary

| File | Action | Task |
|------|--------|------|
| `SentinelCore/events/Events.lua` | Modify | 1 |
| `SentinelCore/tests/test_sc_profile_recorder.lua` | Create | 2 |
| `SentinelCore/services/ProfileRecorder.lua` | Create | 3, 5 |
| `SentinelCore/ui/ProfileOverlay.lua` | Create | 4 |
| `SentinelCore/core/Client.lua` | Modify | 5 |
| `SentinelCore/ui/tabs/profile_tab.lua` | Create | 6, 7 |
| `SentinelCore/ui/window.lua` | Modify | 6 |
| `SentinelCore/services/ProfileCoordinator.lua` | Modify | 8 |
