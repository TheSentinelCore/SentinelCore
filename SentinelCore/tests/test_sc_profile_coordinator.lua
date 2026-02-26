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

    local log = { info = function() end, warn = function() end, error = function() end, debug = function() end }
    local coord = ProfileCoordinator:new(bus, bb, cfg, nav, targeting, log)

    -- ── Test 1: No profile loaded → idle ──
    T.assert_eq(coord:get_state(), "idle", "initial state is idle")
    coord:update()
    T.assert_eq(coord:get_state(), "idle", "stays idle without profile")

    -- ── Test 2: Load a valid profile ──
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

    -- ── Test 3: After load, state is at_hotspot ──
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

    -- ── Test 4: Dry spell → traveling ──
    targeting_candidates = {}
    bb:set("player.position", { x = 100, y = 200, z = 50 })

    env.core._set_time(1000)
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "still at_hotspot (dry spell not elapsed)")

    env.core._set_time(1003)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "transitioned to traveling after dry spell")
    T.assert_eq(bb:get("profile.state"), "traveling", "blackboard state updated")

    T.assert_true(#nav_move_calls > 0, "move_to called for next hotspot")
    local last_move = nav_move_calls[#nav_move_calls]
    T.assert_eq(last_move.x, 300, "move_to target is hs2.x")
    T.assert_eq(last_move.y, 400, "move_to target is hs2.y")

    -- ── Test 5: Arrive at hotspot → at_hotspot ──
    bb:set("player.position", { x = 305, y = 405, z = 60 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at hs2 → at_hotspot")
    local current2 = bb:get("profile.current_hotspot")
    T.assert_eq(current2.id, "hs2", "current hotspot is now hs2")

    -- ── Test 6: Unload profile → idle ──
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
