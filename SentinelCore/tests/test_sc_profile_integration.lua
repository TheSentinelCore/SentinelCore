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
    profile.vendors = {
        { npc_id = 111, name = "Vendor", x = 50, y = 50, z = 0, sell = true, repair = true, food = false, water = false },
    }

    -- Track events
    local events_seen = {}
    bus:on(Events.HOTSPOT_ENTERED, function(p) events_seen[#events_seen + 1] = "enter:" .. p.hotspot_id end)
    bus:on(Events.HOTSPOT_ADVANCED, function(p) events_seen[#events_seen + 1] = "advance:" .. p.to_id end)
    bus:on(Events.PROFILE_LOOP_COMPLETE, function(p) events_seen[#events_seen + 1] = "loop:" .. p.loop_count end)
    bus:on(Events.VENDOR_TRIP_START, function() events_seen[#events_seen + 1] = "vendor_start" end)
    bus:on(Events.VENDOR_TRIP_COMPLETE, function() events_seen[#events_seen + 1] = "vendor_complete" end)

    -- Load
    local ok = coord:load_profile(profile)
    T.assert_true(ok, "profile loads")
    T.assert_eq(coord:get_state(), "at_hotspot", "starts at hotspot a")

    -- ── Cycle through all 3 hotspots ──

    -- Dry spell at a → traveling to b
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

    -- Dry spell at c → loop back to a
    env.core._set_time(1012)
    coord:update()
    env.core._set_time(1015)
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "dry spell → traveling to a (loop)")

    -- Arrive at a
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "arrived at a (loop complete)")

    -- Verify loop event
    local saw_loop = false
    for _, e in ipairs(events_seen) do
        if e:find("loop:") then saw_loop = true end
    end
    T.assert_true(saw_loop, "PROFILE_LOOP_COMPLETE event emitted")

    -- ── Vendor trip interruption ──
    bb:set("inventory.free_slots", 0)
    env.core._set_time(2000)
    coord:update()
    T.assert_eq(coord:get_state(), "vendor_trip", "vendor trip triggered")

    -- vendor.state nil → stay in vendor_trip
    coord:update()
    T.assert_eq(coord:get_state(), "vendor_trip", "stays in vendor_trip while nil")

    -- Complete vendor trip (VendorService emits VENDOR_COMPLETED)
    bus:emit(Events.VENDOR_COMPLETED, {})
    coord:update()
    T.assert_eq(coord:get_state(), "traveling", "vendor done → traveling back")

    -- Arrive back at a
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("inventory.free_slots", 10)
    coord:update()
    T.assert_eq(coord:get_state(), "at_hotspot", "back at a after vendor trip")

    -- Verify vendor events
    local saw_vendor_start = false
    local saw_vendor_complete = false
    for _, e in ipairs(events_seen) do
        if e == "vendor_start" then saw_vendor_start = true end
        if e == "vendor_complete" then saw_vendor_complete = true end
    end
    T.assert_true(saw_vendor_start, "VENDOR_TRIP_START emitted")
    T.assert_true(saw_vendor_complete, "VENDOR_TRIP_COMPLETE emitted")

    return {
        sc_integration_load = true,
        sc_integration_cycle = true,
        sc_integration_loop = true,
        sc_integration_vendor = true,
    }
end

return { run = run }
