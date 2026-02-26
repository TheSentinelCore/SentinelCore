# Grinding Profile System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the full grinding profile system: JSON profiles with hotspot cycling, target filters, vendor definitions, blackspots, a ProfileCoordinator FSM, and service integrations — per the approved design at `docs/plans/2026-02-25-grinding-profiles-design.md`.

**Architecture:** Profiles are JSON files in `scripts_data/SentinelCore/profiles/`. A thin ProfileCoordinator FSM (at_hotspot / traveling / vendor_trip) orchestrates existing services by injecting config onto the blackboard. Services read blackboard keys and adapt behavior — no direct coupling.

**Tech Stack:** Lua (Sylvannas runtime), JSON profiles, SentinelCore service architecture, blackboard pub/sub pattern.

---

## Task 1: ProfileSchema — Defaults & Field Specs

**Files:**
- Create: `SentinelCore/profiles/ProfileSchema.lua`
- Test: `SentinelCore/tests/test_sc_profile_schema.lua`

### Step 1: Write the failing test

```lua
-- SentinelCore/tests/test_sc_profile_schema.lua
local T = require("tests/TestUtil")

local function run()
    T.install_core_stub({})

    local Schema = require("profiles/ProfileSchema")

    -- Test 1: SCHEMA_VERSION is defined
    T.assert_true(type(Schema.SCHEMA_VERSION) == "string", "SCHEMA_VERSION should be a string")

    -- Test 2: defaults() returns a full profile skeleton
    local d = Schema.defaults()
    T.assert_true(type(d) == "table", "defaults() should return a table")
    T.assert_eq(d.version, Schema.SCHEMA_VERSION, "version matches SCHEMA_VERSION")
    T.assert_true(type(d.metadata) == "table", "metadata present")
    T.assert_true(type(d.metadata.name) == "string", "metadata.name is string")
    T.assert_true(type(d.requirements) == "table", "requirements present")
    T.assert_true(type(d.target_defaults) == "table", "target_defaults present")
    T.assert_true(type(d.hotspots) == "table", "hotspots present")
    T.assert_true(type(d.blackspots) == "table", "blackspots present")
    T.assert_true(type(d.vendors) == "table", "vendors present")
    T.assert_true(type(d.rest_spots) == "table", "rest_spots present")
    T.assert_eq(d.loop, true, "loop defaults to true")
    T.assert_eq(d.dry_spell_secs, 15, "dry_spell_secs defaults to 15")
    T.assert_eq(d.travel_engage, true, "travel_engage defaults to true")

    -- Test 3: merge_target_filters merges hotspot overrides onto defaults
    local defaults = { level_min = 67, level_max = 70, creature_types = { "humanoid" }, npc_blacklist = { 100 }, npc_whitelist = {} }
    local overrides = { creature_types = { "humanoid", "demon" }, npc_blacklist = { 100, 200 } }
    local merged = Schema.merge_target_filters(defaults, overrides)
    T.assert_eq(merged.level_min, 67, "level_min inherited from defaults")
    T.assert_eq(merged.level_max, 70, "level_max inherited from defaults")
    T.assert_eq(#merged.creature_types, 2, "creature_types overridden")
    T.assert_eq(merged.creature_types[2], "demon", "creature_types[2] is demon")
    T.assert_eq(#merged.npc_blacklist, 2, "npc_blacklist overridden")

    -- Test 4: merge_target_filters with nil overrides returns copy of defaults
    local merged2 = Schema.merge_target_filters(defaults, nil)
    T.assert_eq(merged2.level_min, 67, "nil override inherits level_min")
    T.assert_eq(#merged2.creature_types, 1, "nil override inherits creature_types")

    return {
        sc_profile_schema_version = true,
        sc_profile_schema_defaults = true,
        sc_profile_schema_merge_filters = true,
        sc_profile_schema_merge_nil = true,
    }
end

return { run = run }
```

### Step 2: Run test to verify it fails

Run: `_G.SentinelCore.run_tests()` in-game
Expected: FAIL — `profiles/ProfileSchema` module not found

### Step 3: Write minimal implementation

```lua
-- SentinelCore/profiles/ProfileSchema.lua
local Schema = {}

Schema.SCHEMA_VERSION = "1.0"

--- Returns a full profile skeleton with all fields at default values.
---@return table
function Schema.defaults()
    return {
        version = Schema.SCHEMA_VERSION,
        metadata = {
            name = "New Profile",
            author = "",
            description = "",
            tags = {},
            created_at = 0,
            updated_at = 0,
        },
        requirements = {
            map_id = 0,
            min_level = 1,
            max_level = 80,
            class_restrictions = {},
        },
        target_defaults = {
            level_min = 1,
            level_max = 80,
            creature_types = {},
            npc_blacklist = {},
            npc_whitelist = {},
        },
        hotspots = {},
        blackspots = {},
        vendors = {},
        rest_spots = {},
        loop = true,
        dry_spell_secs = 15,
        travel_engage = true,
        overrides = {},
    }
end

--- Merge per-hotspot target overrides onto profile target_defaults.
--- If overrides is nil, returns a shallow copy of defaults.
---@param defaults table  profile.target_defaults
---@param overrides table|nil  hotspot.targets
---@return table  merged filter table
function Schema.merge_target_filters(defaults, overrides)
    defaults = defaults or {}
    local merged = {
        level_min = defaults.level_min,
        level_max = defaults.level_max,
        creature_types = {},
        npc_blacklist = {},
        npc_whitelist = {},
    }
    -- Copy default arrays
    local src_ct = defaults.creature_types or {}
    for i = 1, #src_ct do merged.creature_types[i] = src_ct[i] end
    local src_bl = defaults.npc_blacklist or {}
    for i = 1, #src_bl do merged.npc_blacklist[i] = src_bl[i] end
    local src_wl = defaults.npc_whitelist or {}
    for i = 1, #src_wl do merged.npc_whitelist[i] = src_wl[i] end

    if type(overrides) ~= "table" then
        return merged
    end

    -- Override individual fields if present
    if overrides.level_min ~= nil then merged.level_min = overrides.level_min end
    if overrides.level_max ~= nil then merged.level_max = overrides.level_max end
    if overrides.creature_types then
        merged.creature_types = {}
        for i = 1, #overrides.creature_types do
            merged.creature_types[i] = overrides.creature_types[i]
        end
    end
    if overrides.npc_blacklist then
        merged.npc_blacklist = {}
        for i = 1, #overrides.npc_blacklist do
            merged.npc_blacklist[i] = overrides.npc_blacklist[i]
        end
    end
    if overrides.npc_whitelist then
        merged.npc_whitelist = {}
        for i = 1, #overrides.npc_whitelist do
            merged.npc_whitelist[i] = overrides.npc_whitelist[i]
        end
    end

    return merged
end

return Schema
```

### Step 4: Run test to verify it passes

Run: `_G.SentinelCore.run_tests()` in-game
Expected: All 4 assertions pass

### Step 5: Commit

```bash
git add SentinelCore/profiles/ProfileSchema.lua SentinelCore/tests/test_sc_profile_schema.lua
git commit -m "feat(profiles): add ProfileSchema with defaults and filter merging"
```

---

## Task 2: ProfileValidator — Schema Validation

**Files:**
- Create: `SentinelCore/profiles/ProfileValidator.lua`
- Test: `SentinelCore/tests/test_sc_profile_validator.lua`

### Step 1: Write the failing test

```lua
-- SentinelCore/tests/test_sc_profile_validator.lua
local T = require("tests/TestUtil")

local function run()
    T.install_core_stub({})

    local Validator = require("profiles/ProfileValidator")
    local Schema = require("profiles/ProfileSchema")

    -- Test 1: Valid minimal profile passes
    local minimal = Schema.defaults()
    minimal.metadata.name = "Test Profile"
    minimal.requirements.map_id = 530
    minimal.hotspots = {
        { id = "hs1", x = 100, y = 200, z = 50, radius = 40, label = "Spot 1" },
    }
    local ok, errors = Validator.validate(minimal)
    T.assert_true(ok == true, "valid minimal profile should pass")
    T.assert_eq(#errors, 0, "no errors for valid profile")

    -- Test 2: Missing version fails
    local no_version = Schema.defaults()
    no_version.version = nil
    no_version.requirements.map_id = 530
    no_version.hotspots = { { id = "hs1", x = 1, y = 2, z = 3, radius = 10 } }
    local ok2, errors2 = Validator.validate(no_version)
    T.assert_true(ok2 == false, "missing version should fail")

    -- Test 3: Missing map_id fails
    local no_map = Schema.defaults()
    no_map.requirements.map_id = nil
    no_map.hotspots = { { id = "hs1", x = 1, y = 2, z = 3, radius = 10 } }
    local ok3, errors3 = Validator.validate(no_map)
    T.assert_true(ok3 == false, "missing map_id should fail")

    -- Test 4: Empty hotspots fails
    local no_hs = Schema.defaults()
    no_hs.requirements.map_id = 530
    no_hs.hotspots = {}
    local ok4, errors4 = Validator.validate(no_hs)
    T.assert_true(ok4 == false, "empty hotspots should fail")

    -- Test 5: Hotspot missing coordinates fails
    local bad_hs = Schema.defaults()
    bad_hs.requirements.map_id = 530
    bad_hs.hotspots = { { id = "hs1" } }
    local ok5, errors5 = Validator.validate(bad_hs)
    T.assert_true(ok5 == false, "hotspot missing coords should fail")

    -- Test 6: Duplicate hotspot IDs fail
    local dup_hs = Schema.defaults()
    dup_hs.requirements.map_id = 530
    dup_hs.hotspots = {
        { id = "same", x = 1, y = 2, z = 3, radius = 10 },
        { id = "same", x = 4, y = 5, z = 6, radius = 10 },
    }
    local ok6, errors6 = Validator.validate(dup_hs)
    T.assert_true(ok6 == false, "duplicate hotspot IDs should fail")

    return {
        sc_validator_valid = true,
        sc_validator_no_version = true,
        sc_validator_no_map = true,
        sc_validator_no_hotspots = true,
        sc_validator_bad_hotspot = true,
        sc_validator_dup_ids = true,
    }
end

return { run = run }
```

### Step 2: Run test to verify it fails

Run: `_G.SentinelCore.run_tests()` in-game
Expected: FAIL — `profiles/ProfileValidator` module not found

### Step 3: Write minimal implementation

```lua
-- SentinelCore/profiles/ProfileValidator.lua
local Validator = {}

--- Validate a profile table against the schema.
--- Returns (true, {}) on success, (false, {string...}) on failure.
---@param profile table
---@return boolean ok, string[] errors
function Validator.validate(profile)
    local errors = {}

    if type(profile) ~= "table" then
        return false, { "profile is not a table" }
    end

    -- Required: version
    if not profile.version or type(profile.version) ~= "string" or profile.version == "" then
        errors[#errors + 1] = "missing or empty 'version'"
    end

    -- Required: metadata.name
    local meta = profile.metadata
    if type(meta) ~= "table" then
        errors[#errors + 1] = "missing 'metadata' table"
    elseif not meta.name or type(meta.name) ~= "string" or meta.name == "" then
        errors[#errors + 1] = "missing or empty 'metadata.name'"
    end

    -- Required: requirements.map_id
    local req = profile.requirements
    if type(req) ~= "table" then
        errors[#errors + 1] = "missing 'requirements' table"
    elseif not req.map_id or type(req.map_id) ~= "number" or req.map_id <= 0 then
        errors[#errors + 1] = "missing or invalid 'requirements.map_id'"
    end

    -- Required: at least 1 hotspot
    local hotspots = profile.hotspots
    if type(hotspots) ~= "table" or #hotspots == 0 then
        errors[#errors + 1] = "at least one hotspot is required"
    else
        local seen_ids = {}
        for i = 1, #hotspots do
            local hs = hotspots[i]
            if type(hs) ~= "table" then
                errors[#errors + 1] = string.format("hotspot[%d] is not a table", i)
            else
                -- Check coordinates
                if type(hs.x) ~= "number" or type(hs.y) ~= "number" or type(hs.z) ~= "number" then
                    errors[#errors + 1] = string.format("hotspot[%d] missing x/y/z coordinates", i)
                end
                -- Check radius
                if hs.radius ~= nil and (type(hs.radius) ~= "number" or hs.radius <= 0) then
                    errors[#errors + 1] = string.format("hotspot[%d] invalid radius", i)
                end
                -- Check duplicate IDs
                local id = hs.id or tostring(i)
                if seen_ids[id] then
                    errors[#errors + 1] = string.format("duplicate hotspot id '%s'", tostring(id))
                end
                seen_ids[id] = true
            end
        end
    end

    -- Optional validation: vendors
    if profile.vendors and type(profile.vendors) == "table" then
        for i = 1, #profile.vendors do
            local v = profile.vendors[i]
            if type(v) == "table" then
                if type(v.npc_id) ~= "number" or v.npc_id <= 0 then
                    errors[#errors + 1] = string.format("vendor[%d] missing or invalid npc_id", i)
                end
                if type(v.x) ~= "number" or type(v.y) ~= "number" or type(v.z) ~= "number" then
                    errors[#errors + 1] = string.format("vendor[%d] missing x/y/z coordinates", i)
                end
            end
        end
    end

    -- Optional validation: blackspots
    if profile.blackspots and type(profile.blackspots) == "table" then
        for i = 1, #profile.blackspots do
            local bs = profile.blackspots[i]
            if type(bs) == "table" then
                if type(bs.x) ~= "number" or type(bs.y) ~= "number" or type(bs.z) ~= "number" then
                    errors[#errors + 1] = string.format("blackspot[%d] missing x/y/z coordinates", i)
                end
                if bs.severity and bs.severity ~= "hard" and bs.severity ~= "soft" then
                    errors[#errors + 1] = string.format("blackspot[%d] invalid severity (must be 'hard' or 'soft')", i)
                end
            end
        end
    end

    return #errors == 0, errors
end

return Validator
```

### Step 4: Run test to verify it passes

Run: `_G.SentinelCore.run_tests()` in-game
Expected: All 6 assertions pass

### Step 5: Commit

```bash
git add SentinelCore/profiles/ProfileValidator.lua SentinelCore/tests/test_sc_profile_validator.lua
git commit -m "feat(profiles): add ProfileValidator with schema validation"
```

---

## Task 3: Add Profile Events to Events.lua

**Files:**
- Modify: `SentinelCore/events/Events.lua:80-83` (add new events before BB_PREFIX)

### Step 1: Write the failing test

No separate test file needed — the ProfileCoordinator test (Task 5) will use these events. For now, add the events and verify the module loads.

Quick inline verification:

```lua
local Events = require("events/Events")
T.assert_true(Events.PROFILE_LOADED ~= nil, "PROFILE_LOADED event exists")
T.assert_true(Events.HOTSPOT_ENTERED ~= nil, "HOTSPOT_ENTERED event exists")
```

(Add these assertions to the ProfileCoordinator test in Task 5.)

### Step 2: Add events

Modify `SentinelCore/events/Events.lua` — insert between `ZONE_CHANGED` (line 80) and `BB_PREFIX` (line 83):

```lua
    -- World
    HOSTILE_PLAYER_DETECTED = "world.hostile_player_detected",
    ZONE_CHANGED = "world.zone_changed",

    -- Profile coordinator
    PROFILE_LOADED = "profile.loaded",
    PROFILE_UNLOADED = "profile.unloaded",
    PROFILE_LOAD_FAILED = "profile.load_failed",
    HOTSPOT_ENTERED = "profile.hotspot_entered",
    HOTSPOT_ADVANCED = "profile.hotspot_advanced",
    HOTSPOT_TRAVEL_START = "profile.hotspot_travel_start",
    VENDOR_TRIP_START = "profile.vendor_trip_start",
    VENDOR_TRIP_COMPLETE = "profile.vendor_trip_complete",
    PROFILE_LOOP_COMPLETE = "profile.loop_complete",

    -- Blackboard
    BB_PREFIX = "bb.",
```

### Step 3: Commit

```bash
git add SentinelCore/events/Events.lua
git commit -m "feat(profiles): add profile coordinator events"
```

---

## Task 4: Add Profile Defaults to Defaults.lua

**Files:**
- Modify: `SentinelCore/core/Defaults.lua:334-339` (replace the existing `Defaults.profiles` stub)

### Step 1: Replace profiles defaults

Replace `Defaults.profiles` (lines 334-339) with:

```lua
Defaults.profiles = {
    -- ProfileCoordinator FSM settings
    dry_spell_secs = 15,
    travel_engage = true,
    loop = true,
    hotspot_arrival_radius_mult = 1.0, -- multiplier on hotspot radius for arrival detection
    vendor_durability_threshold = 0.25, -- trigger vendor trip when below this
}
```

### Step 2: Commit

```bash
git add SentinelCore/core/Defaults.lua
git commit -m "feat(profiles): update Defaults.profiles with coordinator settings"
```

---

## Task 5: ProfileCoordinator — Core FSM

This is the largest task. It implements the 3-state FSM (at_hotspot / traveling / vendor_trip) that orchestrates hotspot cycling.

**Files:**
- Create: `SentinelCore/services/ProfileCoordinator.lua`
- Test: `SentinelCore/tests/test_sc_profile_coordinator.lua`

### Step 1: Write the failing test

```lua
-- SentinelCore/tests/test_sc_profile_coordinator.lua
local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub({})

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Events = require("events/Events")
    local Schema = require("profiles/ProfileSchema")
    local ProfileCoordinator = require("services/ProfileCoordinator")

    -- Verify events exist
    T.assert_true(Events.PROFILE_LOADED ~= nil, "PROFILE_LOADED event exists")
    T.assert_true(Events.HOTSPOT_ENTERED ~= nil, "HOTSPOT_ENTERED event exists")

    -- Mock navigation
    local nav_move_calls = {}
    local nav = {
        move_to = function(self, pos, cb)
            nav_move_calls[#nav_move_calls + 1] = pos
            if cb then cb(true) end
        end,
        stop = function() end,
        is_moving = function() return false end,
    }

    -- Mock targeting
    local targeting_candidates = {}
    local targeting = {
        get_visible_candidates = function()
            return targeting_candidates
        end,
    }

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)

    local cfg = {
        dry_spell_secs = 2,
        travel_engage = true,
        loop = true,
        hotspot_arrival_radius_mult = 1.0,
        vendor_durability_threshold = 0.25,
    }

    local coord = ProfileCoordinator:new(bus, bb, cfg, nav, targeting, { info = function() end, warn = function() end, error = function() end, debug = function() end })

    -- ─────────────────────────────────────────────
    -- Test 1: No profile loaded → idle, update is no-op
    -- ─────────────────────────────────────────────
    T.assert_eq(coord:get_state(), "idle", "initial state is idle")
    coord:update()
    T.assert_eq(coord:get_state(), "idle", "stays idle without profile")

    -- ─────────────────────────────────────────────
    -- Test 2: Load a valid profile
    -- ─────────────────────────────────────────────
    local profile = Schema.defaults()
    profile.metadata.name = "Test Route"
    profile.requirements.map_id = 530
    profile.target_defaults = {
        level_min = 67, level_max = 70,
        creature_types = { "humanoid" },
        npc_blacklist = {}, npc_whitelist = {},
    }
    profile.hotspots = {
        { id = "hs1", x = 100, y = 200, z = 50, radius = 40, label = "Spot 1" },
        { id = "hs2", x = 300, y = 400, z = 60, radius = 50, label = "Spot 2" },
    }
    profile.vendors = {
        { npc_id = 999, name = "Test Vendor", x = 150, y = 250, z = 55, sell = true, repair = true, food = false, water = false },
    }

    local loaded_event = nil
    bus:on(Events.PROFILE_LOADED, function(payload)
        loaded_event = payload
    end)

    local ok, err = coord:load_profile(profile)
    T.assert_true(ok == true, "load_profile succeeds")
    T.assert_true(loaded_event ~= nil, "PROFILE_LOADED event emitted")
    T.assert_eq(loaded_event.name, "Test Route", "event has profile name")

    -- ─────────────────────────────────────────────
    -- Test 3: After load, state is at_hotspot (first hotspot)
    -- ─────────────────────────────────────────────
    T.assert_eq(coord:get_state(), "at_hotspot", "state is at_hotspot after load")
    T.assert_eq(bb:get("profile.active"), true, "profile.active is true")
    T.assert_eq(bb:get("profile.state"), "at_hotspot", "profile.state on blackboard")

    local current = bb:get("profile.current_hotspot")
    T.assert_true(current ~= nil, "current hotspot set")
    T.assert_eq(current.id, "hs1", "current hotspot is hs1")

    local anchor = bb:get("grind.anchor")
    T.assert_eq(anchor.x, 100, "anchor.x set to hotspot")
    T.assert_eq(anchor.y, 200, "anchor.y set to hotspot")

    local filters = bb:get("profile.target_filters")
    T.assert_true(filters ~= nil, "target_filters set")
    T.assert_eq(filters.level_min, 67, "target_filters.level_min correct")

    T.assert_true(bb:get("profile.vendors") ~= nil, "vendors on blackboard")
    T.assert_eq(bb:get("exploration.max_grind_radius"), 40, "grind radius = hotspot radius")

    -- ─────────────────────────────────────────────
    -- Test 4: Dry spell → advance to traveling
    -- ─────────────────────────────────────────────
    -- Simulate: 0 candidates for dry_spell_secs
    targeting_candidates = {}
    bb:set("player.position", { x = 100, y = 200, z = 50 })

    -- First update: starts dry spell timer
    env.core._set_time(1000)
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "still at_hotspot (dry spell not elapsed)")

    -- Advance time past dry_spell_secs (2s)
    env.core._set_time(1003)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "transitioned to traveling after dry spell")
    T.assert_eq(bb:get("profile.state"), "traveling", "blackboard state updated")

    -- Should have issued move_to for hs2
    T.assert_true(#nav_move_calls > 0, "move_to called for next hotspot")
    local last_move = nav_move_calls[#nav_move_calls]
    T.assert_eq(last_move.x, 300, "move_to target is hs2.x")
    T.assert_eq(last_move.y, 400, "move_to target is hs2.y")

    -- ─────────────────────────────────────────────
    -- Test 5: Arrive at hotspot → back to at_hotspot
    -- ─────────────────────────────────────────────
    -- Simulate player within hs2 radius
    bb:set("player.position", { x = 305, y = 405, z = 60 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at hs2 → at_hotspot")
    local current2 = bb:get("profile.current_hotspot")
    T.assert_eq(current2.id, "hs2", "current hotspot is now hs2")

    -- ─────────────────────────────────────────────
    -- Test 6: Unload profile → idle, blackboard cleared
    -- ─────────────────────────────────────────────
    coord:unload_profile()
    T.assert_eq(coord:get_state(), "idle", "unload → idle")
    T.assert_true(bb:get("profile.active") ~= true, "profile.active cleared")
    T.assert_true(bb:get("profile.current_hotspot") == nil, "current_hotspot cleared")
    T.assert_true(bb:get("profile.target_filters") == nil, "target_filters cleared")

    return {
        sc_coord_idle = true,
        sc_coord_load = true,
        sc_coord_at_hotspot = true,
        sc_coord_dry_spell = true,
        sc_coord_arrive = true,
        sc_coord_unload = true,
    }
end

return { run = run }
```

### Step 2: Run test to verify it fails

Run: `_G.SentinelCore.run_tests()` in-game
Expected: FAIL — `services/ProfileCoordinator` module not found

### Step 3: Write minimal implementation

```lua
-- SentinelCore/services/ProfileCoordinator.lua
local Events = require("events/Events")
local Validator = require("profiles/ProfileValidator")
local Schema = require("profiles/ProfileSchema")

---@class ProfileCoordinator
local ProfileCoordinator = {}
ProfileCoordinator.__index = ProfileCoordinator

local function get_now()
    return tonumber(core.game_time()) or 0
end

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@param navigation NavigationAdapter
---@param targeting TargetingService
---@param logger Logger
function ProfileCoordinator:new(event_bus, blackboard, cfg, navigation, targeting, logger)
    local o = setmetatable({}, self)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._targeting = targeting
    o._log = logger

    o._state = "idle"          -- idle | at_hotspot | traveling | vendor_trip
    o._profile = nil           -- loaded profile table
    o._hotspot_index = 0       -- current hotspot (1-based)
    o._dry_spell_start = 0     -- when 0-candidate period began
    o._loop_count = 0          -- how many full loops completed
    o._loop_start_time = 0     -- timestamp when current loop started
    o._resume_hotspot_id = nil -- hotspot to return to after vendor trip
    o._move_issued = false     -- whether we've issued move_to for current travel
    return o
end

--- Get current FSM state.
---@return string
function ProfileCoordinator:get_state()
    return self._state
end

--- Load and activate a profile. Validates, injects onto blackboard,
--- enters at_hotspot for the first hotspot.
---@param profile table  parsed profile data
---@return boolean ok, string|nil error
function ProfileCoordinator:load_profile(profile)
    local ok, errors = Validator.validate(profile)
    if not ok then
        local msg = table.concat(errors, "; ")
        self._log:error("profile validation failed: %s", msg)
        self._event_bus:emit(Events.PROFILE_LOAD_FAILED, { errors = errors })
        return false, msg
    end

    self._profile = profile
    self._hotspot_index = 1
    self._loop_count = 0
    self._loop_start_time = get_now()
    self._dry_spell_start = 0

    -- Write profile data to blackboard
    self._blackboard:set("profile.active", true)
    self._blackboard:set("profile.blackspots", profile.blackspots or {})
    self._blackboard:set("profile.vendors", profile.vendors or {})
    self._blackboard:set("profile.rest_spots", profile.rest_spots or {})

    -- Enter first hotspot
    self:_enter_hotspot(self._hotspot_index)

    self._event_bus:emit(Events.PROFILE_LOADED, {
        name = profile.metadata and profile.metadata.name or "Unknown",
        hotspot_count = #profile.hotspots,
        map_id = profile.requirements and profile.requirements.map_id or 0,
    })

    self._log:info("profile loaded: %s (%d hotspots)",
        profile.metadata and profile.metadata.name or "?", #profile.hotspots)

    return true
end

--- Unload the active profile. Clears all blackboard keys.
function ProfileCoordinator:unload_profile()
    if not self._profile then return end

    local name = self._profile.metadata and self._profile.metadata.name or "?"
    self._profile = nil
    self._state = "idle"
    self._hotspot_index = 0

    self._blackboard:clear("profile.active")
    self._blackboard:clear("profile.state")
    self._blackboard:clear("profile.current_hotspot")
    self._blackboard:clear("profile.target_filters")
    self._blackboard:clear("profile.blackspots")
    self._blackboard:clear("profile.vendors")
    self._blackboard:clear("profile.rest_spots")
    self._blackboard:clear("grind.anchor")
    self._blackboard:clear("exploration.max_grind_radius")

    self._event_bus:emit(Events.PROFILE_UNLOADED, { name = name })
    self._log:info("profile unloaded: %s", name)
end

--- Main update tick. Call once per frame.
---@return boolean ok
function ProfileCoordinator:update()
    if not self._profile then return true end

    if self._state == "at_hotspot" then
        self:_tick_at_hotspot()
    elseif self._state == "traveling" then
        self:_tick_traveling()
    elseif self._state == "vendor_trip" then
        self:_tick_vendor_trip()
    end

    return true
end

-- ── Private: State entry ─────────────────────────────

---@private
function ProfileCoordinator:_enter_hotspot(index)
    local hs = self._profile.hotspots[index]
    if not hs then return end

    self._state = "at_hotspot"
    self._hotspot_index = index
    self._dry_spell_start = 0
    self._move_issued = false

    -- Merge target filters: hotspot overrides on top of profile defaults
    local filters = Schema.merge_target_filters(
        self._profile.target_defaults,
        hs.targets
    )

    -- Inject onto blackboard
    self._blackboard:set("profile.state", "at_hotspot")
    self._blackboard:set("profile.current_hotspot", hs)
    self._blackboard:set("profile.target_filters", filters)
    self._blackboard:set("grind.anchor", { x = hs.x, y = hs.y, z = hs.z })
    self._blackboard:set("exploration.max_grind_radius", tonumber(hs.radius) or 40)

    self._event_bus:emit(Events.HOTSPOT_ENTERED, {
        hotspot_id = hs.id,
        index = index,
        label = hs.label,
    })

    self._log:info("entered hotspot [%d] %s (r=%d)",
        index, tostring(hs.id), tonumber(hs.radius) or 40)
end

---@private
function ProfileCoordinator:_enter_traveling(next_index)
    local from_hs = self._profile.hotspots[self._hotspot_index]
    local to_hs = self._profile.hotspots[next_index]
    if not to_hs then return end

    self._state = "traveling"
    self._hotspot_index = next_index
    self._move_issued = false

    self._blackboard:set("profile.state", "traveling")

    -- Suppress exploration during travel
    self._blackboard:clear("grind.anchor")

    local dist = distance_3d(from_hs, to_hs)
    self._event_bus:emit(Events.HOTSPOT_TRAVEL_START, {
        from_id = from_hs and from_hs.id,
        to_id = to_hs.id,
        distance = dist,
    })

    self._log:info("traveling to hotspot [%d] %s (%.0f yd)",
        next_index, tostring(to_hs.id), dist)
end

---@private
function ProfileCoordinator:_enter_vendor_trip()
    local current_hs = self._profile.hotspots[self._hotspot_index]
    self._resume_hotspot_id = current_hs and current_hs.id or nil

    self._state = "vendor_trip"
    self._blackboard:set("profile.state", "vendor_trip")

    -- Suppress exploration during vendor trip
    self._blackboard:clear("grind.anchor")

    self._event_bus:emit(Events.VENDOR_TRIP_START, {
        resume_hotspot_id = self._resume_hotspot_id,
    })

    self._log:info("vendor trip started, will resume at %s", tostring(self._resume_hotspot_id))
end

-- ── Private: State ticks ─────────────────────────────

---@private
function ProfileCoordinator:_tick_at_hotspot()
    local now = get_now()

    -- Check vendor trigger (bags full or low durability)
    local free_slots = tonumber(self._blackboard:get("inventory.free_slots")) or 999
    local durability = tonumber(self._blackboard:get("player.durability_pct")) or 1.0
    local dur_threshold = tonumber(self._cfg.vendor_durability_threshold) or 0.25
    local has_vendors = self._profile.vendors and #self._profile.vendors > 0

    if has_vendors and (free_slots <= 0 or durability < dur_threshold) then
        self:_enter_vendor_trip()
        return
    end

    -- Check dry spell (0 candidates for N seconds)
    local candidates = self._targeting:get_visible_candidates()
    local count = type(candidates) == "table" and #candidates or 0

    if count > 0 then
        self._dry_spell_start = 0
        return
    end

    -- No candidates
    if self._dry_spell_start == 0 then
        self._dry_spell_start = now
        return
    end

    local dry_secs = tonumber(self._cfg.dry_spell_secs) or 15
    if (now - self._dry_spell_start) >= dry_secs then
        -- Advance to next hotspot
        local next_idx = self:_next_hotspot_index()
        if next_idx then
            local from_hs = self._profile.hotspots[self._hotspot_index]
            local to_hs = self._profile.hotspots[next_idx]
            self._event_bus:emit(Events.HOTSPOT_ADVANCED, {
                from_id = from_hs and from_hs.id,
                to_id = to_hs and to_hs.id,
                reason = "dry_spell",
            })
            self:_enter_traveling(next_idx)
        end
    end
end

---@private
function ProfileCoordinator:_tick_traveling()
    local hs = self._profile.hotspots[self._hotspot_index]
    if not hs then
        self._state = "idle"
        return
    end

    -- Issue move_to once
    if not self._move_issued then
        self._nav:move_to({ x = hs.x, y = hs.y, z = hs.z })
        self._move_issued = true
    end

    -- Check arrival: player within hotspot radius
    local player_pos = self._blackboard:get("player.position")
    local radius = (tonumber(hs.radius) or 40) * (tonumber(self._cfg.hotspot_arrival_radius_mult) or 1.0)
    local dist = distance_3d(player_pos, hs)

    if dist <= radius then
        self:_enter_hotspot(self._hotspot_index)
    end
end

---@private
function ProfileCoordinator:_tick_vendor_trip()
    -- VendorService drives the actual vendor interaction.
    -- We wait for VendorService to complete (state goes back to idle/not_started).
    local vendor_state = self._blackboard:get("vendor.state")

    -- VendorService writes vendor.state; when it's nil/"idle"/"completed", trip is done.
    if vendor_state == "completed" or vendor_state == "failed" or vendor_state == nil then
        -- Only transition back if we've been in vendor_trip long enough
        -- (to avoid immediate re-trigger on first tick)
        if self._resume_hotspot_id then
            local idx = self:_find_hotspot_index(self._resume_hotspot_id)
            if idx then
                self._event_bus:emit(Events.VENDOR_TRIP_COMPLETE, {
                    resume_hotspot_id = self._resume_hotspot_id,
                })
                self:_enter_traveling(idx)
                self._resume_hotspot_id = nil
                return
            end
        end
        -- Fallback: go to nearest hotspot
        self:_resume_nearest_hotspot()
    end
end

-- ── Private: Helpers ─────────────────────────────────

---@private
---@return number|nil  next hotspot index, or nil if at end and not looping
function ProfileCoordinator:_next_hotspot_index()
    local total = #self._profile.hotspots
    local next_idx = self._hotspot_index + 1

    if next_idx > total then
        if self._profile.loop ~= false and self._cfg.loop ~= false then
            self._loop_count = self._loop_count + 1
            local now = get_now()
            self._event_bus:emit(Events.PROFILE_LOOP_COMPLETE, {
                loop_count = self._loop_count,
                elapsed_secs = now - self._loop_start_time,
            })
            self._loop_start_time = now
            return 1
        end
        return nil
    end

    return next_idx
end

---@private
---@param hotspot_id string
---@return number|nil
function ProfileCoordinator:_find_hotspot_index(hotspot_id)
    if not self._profile or not self._profile.hotspots then return nil end
    for i = 1, #self._profile.hotspots do
        if self._profile.hotspots[i].id == hotspot_id then
            return i
        end
    end
    return nil
end

---@private
function ProfileCoordinator:_resume_nearest_hotspot()
    local player_pos = self._blackboard:get("player.position")
    if not player_pos or not self._profile then
        self._state = "idle"
        return
    end

    local best_idx = 1
    local best_dist = math.huge
    for i = 1, #self._profile.hotspots do
        local hs = self._profile.hotspots[i]
        local d = distance_3d(player_pos, hs)
        if d < best_dist then
            best_dist = d
            best_idx = i
        end
    end

    self:_enter_traveling(best_idx)
end

return ProfileCoordinator
```

### Step 4: Run test to verify it passes

Run: `_G.SentinelCore.run_tests()` in-game
Expected: All 6 test groups pass

### Step 5: Commit

```bash
git add SentinelCore/services/ProfileCoordinator.lua SentinelCore/tests/test_sc_profile_coordinator.lua
git commit -m "feat(profiles): add ProfileCoordinator FSM with hotspot cycling"
```

---

## Task 6: TargetingService Integration — Profile Target Filters

**Files:**
- Modify: `SentinelCore/services/TargetingService.lua:1056` (after candidate loop, before sort)

### Step 1: Write the failing test

Add to the existing coordinator test or create a focused one. The key behavior: when `profile.target_filters` is on the blackboard, `get_visible_candidates()` should filter by level, creature type, and NPC blacklist/whitelist.

```lua
-- Add to test_sc_profile_coordinator.lua or new test_sc_targeting_profile_filters.lua
-- Test: TargetingService filters candidates when profile.target_filters is set

-- Mock candidate objects
local function make_candidate(id, level, creature_type)
    return T.mock_object({
        id = id,
        level = level,
        creature_type_string = creature_type,
        npc_id = id,
        is_valid = true,
        is_unit = true,
        is_dead = false,
        is_ghost = false,
        is_basic_object = false,
        position = { x = 100, y = 200, z = 50 },
    })
end

bb:set("profile.target_filters", {
    level_min = 67,
    level_max = 70,
    creature_types = { "humanoid" },
    npc_blacklist = { 555 },
    npc_whitelist = {},
})

-- Verify _apply_profile_filters exists and works
local candidates = {
    { target = make_candidate(100, 68, "humanoid"), distance = 10, score = 1 },
    { target = make_candidate(200, 65, "humanoid"), distance = 15, score = 1 },  -- level too low
    { target = make_candidate(300, 69, "beast"), distance = 12, score = 1 },      -- wrong type
    { target = make_candidate(555, 68, "humanoid"), distance = 8, score = 1 },    -- blacklisted
}
local filtered = targeting:_apply_profile_filters(candidates)
T.assert_eq(#filtered, 1, "only 1 candidate passes all filters")
T.assert_eq(filtered[1].target:get_npc_id(), 100, "correct candidate passes")
```

### Step 2: Implement `_apply_profile_filters`

Add to `SentinelCore/services/TargetingService.lua` — new private method, and call it in `get_visible_candidates()` at line 1056 (after the for loop, before `table.sort`):

**New method** (add before `get_visible_candidates`):

```lua
---@private
--- Apply profile-defined target filters (level, creature type, NPC whitelist/blacklist).
---@param candidates table[]
---@return table[]
function TargetingService:_apply_profile_filters(candidates)
    local filters = self._blackboard:get("profile.target_filters")
    if not filters then return candidates end

    local level_min = tonumber(filters.level_min) or 0
    local level_max = tonumber(filters.level_max) or 999
    local creature_types = filters.creature_types
    local npc_blacklist = filters.npc_blacklist
    local npc_whitelist = filters.npc_whitelist
    local has_whitelist = type(npc_whitelist) == "table" and #npc_whitelist > 0
    local has_creature_filter = type(creature_types) == "table" and #creature_types > 0

    local result = {}
    for i = 1, #candidates do
        local entry = candidates[i]
        local target = entry.target
        local dominated = false

        -- Level filter
        local level = tonumber(safe_method(target, "get_level")) or 0
        if level < level_min or level > level_max then
            dominated = true
        end

        -- Creature type filter
        if not dominated and has_creature_filter then
            local ct = tostring(safe_method(target, "get_creature_type_string") or ""):lower()
            local match = false
            for j = 1, #creature_types do
                if ct == tostring(creature_types[j]):lower() then
                    match = true
                    break
                end
            end
            if not match then dominated = true end
        end

        -- NPC ID checks
        local npc_id = tonumber(safe_method(target, "get_npc_id")) or 0

        -- Whitelist (if non-empty, ONLY these NPCs)
        if not dominated and has_whitelist then
            local on_list = false
            for j = 1, #npc_whitelist do
                if npc_id == tonumber(npc_whitelist[j]) then
                    on_list = true
                    break
                end
            end
            if not on_list then dominated = true end
        end

        -- Blacklist
        if not dominated and type(npc_blacklist) == "table" then
            for j = 1, #npc_blacklist do
                if npc_id == tonumber(npc_blacklist[j]) then
                    dominated = true
                    break
                end
            end
        end

        if not dominated then
            result[#result + 1] = entry
        end
    end

    return result
end
```

**Hook into `get_visible_candidates()`** — add after line 1056 (after the for loop ends), before `table.sort`:

```lua
    -- Apply profile target filters if active
    candidates = self:_apply_profile_filters(candidates)
```

### Step 3: Run tests to verify

Run: `_G.SentinelCore.run_tests()` in-game
Expected: All existing tests still pass + new filter tests pass

### Step 4: Commit

```bash
git add SentinelCore/services/TargetingService.lua
git commit -m "feat(profiles): add profile target filter integration to TargetingService"
```

---

## Task 7: VendorService Integration — Profile Vendor Override

**Files:**
- Modify: `SentinelCore/services/VendorService.lua:380-420` (in `start()`, before HTTP fetch)

### Step 1: Design

When `profile.vendors` is set on the blackboard and non-empty, VendorService should use those vendors directly instead of fetching from SentinelQueryServer. The existing `_candidate_allowed()` faction check still applies.

### Step 2: Implement

In `VendorService:start()`, after setting up `request_opts` (line 415) but before calling `self._world:get_nearby_vendors()` (line 417), add:

```lua
    -- Profile vendor override: skip HTTP fetch, use profile-defined vendors
    local profile_vendors = self._blackboard:get("profile.vendors")
    if type(profile_vendors) == "table" and #profile_vendors > 0 then
        self._log:info("using %d profile-defined vendors (skip server fetch)", #profile_vendors)
        self:_on_vendors_received(true, profile_vendors, nil)
        return true
    end
```

This requires extracting the callback body from `self._world:get_nearby_vendors(...)` into a `_on_vendors_received` method. Alternatively, just inline the same callback logic. The simplest approach: call the existing callback directly.

Looking at the actual code structure, the callback at line 417 is an anonymous function. Refactor: extract it into a named method `_process_fetched_vendors(ok, vendors, error_code)`, then call it from both the HTTP callback and the profile-vendor shortcut.

### Step 3: Test

Add to `test_sc012_vendor_service.lua`:

```lua
-- Test: Profile vendors bypass HTTP fetch
bb:set("profile.vendors", {
    { npc_id = 777, name = "Profile Vendor", x = 50, y = 60, z = 70,
      sell = true, repair = true, food = false, water = false,
      vendor_id = 777, faction_mask = 3 },
})
local vs = VendorService:new(bus, bb, nav, world, inv, cfg, nil, log)
local started = vs:start({ map_id = 530 })
T.assert_true(started, "vendor trip starts with profile vendors")
-- world.get_nearby_vendors should NOT have been called
T.assert_true(world.captured_opts == nil, "no HTTP fetch when profile vendors set")
```

### Step 4: Commit

```bash
git add SentinelCore/services/VendorService.lua SentinelCore/tests/test_sc012_vendor_service.lua
git commit -m "feat(profiles): VendorService uses profile-defined vendors when available"
```

---

## Task 8: ExplorationService Suppression During Travel/Vendor

**Files:**
- Modify: `SentinelCore/services/ExplorationService.lua:85-107` (`_is_enabled()`)

### Step 1: Design

When profile is active and state is `traveling` or `vendor_trip`, ExplorationService should be suppressed. Simplest approach: check `profile.state` on the blackboard in `_is_enabled()`.

### Step 2: Implement

Add after the `enabled_modes` check in `_is_enabled()` (after line 104, before `return false`):

```lua
    -- Suppress during profile traveling/vendor states
    local profile_state = self._blackboard:get("profile.state")
    if profile_state == "traveling" or profile_state == "vendor_trip" then
        return false
    end
```

### Step 3: Test

Verify in the ProfileCoordinator test that when state is `traveling`, ExplorationService's `_is_enabled()` returns false:

```lua
-- In test_sc_profile_coordinator.lua
bb:set("profile.state", "traveling")
-- ExplorationService would check _is_enabled() and return false
T.assert_eq(bb:get("profile.state"), "traveling", "profile state set for suppression")
```

### Step 4: Commit

```bash
git add SentinelCore/services/ExplorationService.lua
git commit -m "feat(profiles): suppress ExplorationService during travel/vendor states"
```

---

## Task 9: Wire ProfileCoordinator into Client.lua

**Files:**
- Modify: `SentinelCore/core/Client.lua:157-208` (service instantiation + update order)

### Step 1: Add require

At the top of Client.lua with the other requires:

```lua
local ProfileCoordinator = require("services/ProfileCoordinator")
```

### Step 2: Instantiate in constructor

After `mount` (line 180), add:

```lua
    local profile_coordinator = config.profile_coordinator or ProfileCoordinator:new(
        o._event_bus, o._blackboard, runtime_cfg.profiles or {},
        navigation, targeting, Logger:new("ProfileCoord")
    )
```

### Step 3: Add to services table

In `o._services` (line 182-197), add:

```lua
        profile_coordinator = profile_coordinator,
```

### Step 4: Add to update order

In `o._service_update_order` (line 199-208), add `"profile_coordinator"` before `"exploration"` so the FSM injects blackboard state before ExplorationService reads it:

```lua
    o._service_update_order = {
        "objective",
        "targeting",
        "profile_coordinator",
        "exploration",
        "combat",
        "loot",
        "inventory",
        "vendor",
        "mount",
    }
```

### Step 5: Expose load/unload on Client

Add public methods to Client so the UI can call them:

```lua
function Client:load_grinding_profile(profile)
    return self._services.profile_coordinator:load_profile(profile)
end

function Client:unload_grinding_profile()
    self._services.profile_coordinator:unload_profile()
end

function Client:get_grinding_profile_state()
    return self._services.profile_coordinator:get_state()
end
```

### Step 6: Commit

```bash
git add SentinelCore/core/Client.lua
git commit -m "feat(profiles): wire ProfileCoordinator into Client service lifecycle"
```

---

## Task 10: Profile File I/O — Load from JSON

**Files:**
- Modify: `SentinelCore/services/ProfileCoordinator.lua` (add `load_profile_from_file` method)

### Step 1: Implement

Add to ProfileCoordinator:

```lua
--- Load a profile from a JSON file in scripts_data/SentinelCore/profiles/.
---@param filename string  e.g. "netherstorm_manaforge.json"
---@return boolean ok, string|nil error
function ProfileCoordinator:load_profile_from_file(filename)
    local path = "SentinelCore/profiles/" .. filename
    local content = core.read_file(path)
    if not content or content == "" then
        local msg = "file not found or empty: " .. path
        self._log:error(msg)
        return false, msg
    end

    -- Parse JSON
    local json = require("lib/json")
    local ok, profile = pcall(json.decode, content)
    if not ok or type(profile) ~= "table" then
        local msg = "JSON parse error: " .. tostring(profile)
        self._log:error(msg)
        return false, msg
    end

    return self:load_profile(profile)
end

--- Save the active profile to a JSON file.
---@param filename string
---@return boolean ok, string|nil error
function ProfileCoordinator:save_profile_to_file(filename)
    if not self._profile then
        return false, "no active profile"
    end

    local json = require("lib/json")
    self._profile.metadata.updated_at = math.floor(get_now())

    local content = json.encode(self._profile)
    local path = "SentinelCore/profiles/" .. filename
    local ok = core.write_file(path, content)
    if not ok then
        return false, "write failed: " .. path
    end

    self._log:info("profile saved to %s", path)
    return true
end

--- List profile files available in scripts_data/SentinelCore/profiles/.
---@return string[]
function ProfileCoordinator:list_profile_files()
    -- core.list_files may not exist; fallback to scanning known manifest
    local files = {}
    if core.list_files then
        local raw = core.list_files("SentinelCore/profiles/")
        if type(raw) == "table" then
            for i = 1, #raw do
                local f = raw[i]
                if type(f) == "string" and f:sub(-5) == ".json" then
                    files[#files + 1] = f
                end
            end
        end
    end
    return files
end
```

### Step 2: Commit

```bash
git add SentinelCore/services/ProfileCoordinator.lua
git commit -m "feat(profiles): add file I/O (load/save JSON profiles)"
```

---

## Task 11: Update Profiles UI Tab

**Files:**
- Modify: `SentinelCore/ui/window.lua:1498-1650` (profiles tab)

### Step 1: Design

The existing profiles tab (lines 1498-1650) manages runtime config profiles. The grinding profile system is separate — it loads JSON hotspot profiles. Update the tab to add a "Grinding Profiles" section with:
- Active grinding profile info
- FSM state display
- Load/Unload buttons
- File picker (list JSON files)

### Step 2: Implement

Add a new section **above** the existing Saved Profiles listbox. In the profiles tab callback (after line 1513, the Active Profile row_list):

```lua
        -- ── Grinding Profile section ──
        t:row_list({
            label = "Grinding Profile",
            elements = {
                {
                    type = "info",
                    label = "Status",
                    tooltip = "Current grinding profile state (idle / at_hotspot / traveling / vendor_trip)",
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
                        return hs and (tostring(hs.label or hs.id)) or "-"
                    end,
                },
            },
        })
```

### Step 3: Commit

```bash
git add SentinelCore/ui/window.lua
git commit -m "feat(profiles): add grinding profile status to UI profiles tab"
```

---

## Task 12: Integration Smoke Test

**Files:**
- Create: `SentinelCore/tests/test_sc_profile_integration.lua`

### Step 1: Write integration test

End-to-end test: load profile → FSM cycles through hotspots → dry spell advances → loop wraps.

```lua
-- SentinelCore/tests/test_sc_profile_integration.lua
local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub({})
    env.core._set_time(1000)

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Events = require("events/Events")
    local Schema = require("profiles/ProfileSchema")
    local ProfileCoordinator = require("services/ProfileCoordinator")

    local nav_destinations = {}
    local nav = {
        move_to = function(self, pos, cb)
            nav_destinations[#nav_destinations + 1] = pos
            if cb then cb(true) end
        end,
        stop = function() end,
        is_moving = function() return false end,
    }

    local candidate_count = 0
    local targeting = {
        get_visible_candidates = function()
            local t = {}
            for i = 1, candidate_count do t[i] = {} end
            return t
        end,
    }

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local log = { info = function() end, warn = function() end, error = function() end, debug = function() end }

    local coord = ProfileCoordinator:new(bus, bb, {
        dry_spell_secs = 2,
        loop = true,
        hotspot_arrival_radius_mult = 1.0,
        vendor_durability_threshold = 0.25,
    }, nav, targeting, log)

    -- Build a 3-hotspot looping profile
    local profile = Schema.defaults()
    profile.metadata.name = "Integration Test"
    profile.requirements.map_id = 1
    profile.hotspots = {
        { id = "a", x = 0, y = 0, z = 0, radius = 30 },
        { id = "b", x = 100, y = 0, z = 0, radius = 30 },
        { id = "c", x = 200, y = 0, z = 0, radius = 30 },
    }

    -- Track events
    local events_seen = {}
    bus:on(Events.HOTSPOT_ENTERED, function(p) events_seen[#events_seen + 1] = "enter:" .. p.hotspot_id end)
    bus:on(Events.HOTSPOT_ADVANCED, function(p) events_seen[#events_seen + 1] = "advance:" .. p.to_id end)
    bus:on(Events.PROFILE_LOOP_COMPLETE, function(p) events_seen[#events_seen + 1] = "loop:" .. p.loop_count end)

    -- Load
    local ok = coord:load_profile(profile)
    T.assert_true(ok, "profile loads")
    T.assert_eq(coord:get_state(), "at_hotspot", "starts at hotspot a")

    -- Simulate dry spell at hotspot a (0 candidates for 2+ sec)
    candidate_count = 0
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    coord:update()
    env.core._set_time(1003)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "dry spell → traveling to b")

    -- Arrive at b
    bb:set("player.position", { x = 102, y = 0, z = 0 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at b")
    T.assert_eq(bb:get("profile.current_hotspot").id, "b", "current hotspot is b")

    -- Mobs at b, then dry spell
    candidate_count = 3
    coord:update()
    candidate_count = 0
    env.core._set_time(1006)
    coord:update()
    env.core._set_time(1009)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "dry spell → traveling to c")

    -- Arrive at c
    bb:set("player.position", { x = 200, y = 0, z = 0 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at c")

    -- Dry spell at c → should loop back to a
    env.core._set_time(1012)
    coord:update()
    env.core._set_time(1015)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "dry spell → traveling to a (loop)")

    -- Arrive at a
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at a (loop complete)")

    -- Verify loop event was emitted
    local saw_loop = false
    for _, e in ipairs(events_seen) do
        if e:find("loop:") then saw_loop = true end
    end
    T.assert_true(saw_loop, "PROFILE_LOOP_COMPLETE event emitted")

    return {
        sc_integration_load = true,
        sc_integration_dry_spell = true,
        sc_integration_arrival = true,
        sc_integration_loop = true,
    }
end

return { run = run }
```

### Step 2: Run test

Run: `_G.SentinelCore.run_tests()` in-game
Expected: All assertions pass

### Step 3: Commit

```bash
git add SentinelCore/tests/test_sc_profile_integration.lua
git commit -m "test(profiles): add integration smoke test for full hotspot loop"
```

---

## Summary — Task Order & Dependencies

| Task | What | Depends On | Files |
|------|------|-----------|-------|
| 1 | ProfileSchema | — | `profiles/ProfileSchema.lua`, test |
| 2 | ProfileValidator | Task 1 | `profiles/ProfileValidator.lua`, test |
| 3 | Events | — | `events/Events.lua` |
| 4 | Defaults | — | `core/Defaults.lua` |
| 5 | ProfileCoordinator FSM | Tasks 1-4 | `services/ProfileCoordinator.lua`, test |
| 6 | TargetingService filters | Task 5 | `services/TargetingService.lua` |
| 7 | VendorService override | Task 5 | `services/VendorService.lua` |
| 8 | ExplorationService suppression | Task 5 | `services/ExplorationService.lua` |
| 9 | Client.lua wiring | Task 5 | `core/Client.lua` |
| 10 | File I/O | Task 5 | `services/ProfileCoordinator.lua` |
| 11 | UI tab update | Task 9 | `ui/window.lua` |
| 12 | Integration test | Tasks 5-9 | test file |

**Not in this plan** (future tasks per design doc):
- ProfileRecorder (recording mode + hotkey handlers)
- Recorder 3D overlay
- Profile detail editor UI (full CRUD for hotspots, vendors, etc.)
- Blackspot avoidance in NavigationAdapter

These are Phase 2 — the recorder and editor UI depend on a working FSM and service integrations first.
