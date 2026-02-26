-- SentinelCore/tests/test_sc_profile_recorder.lua
local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub({})

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local Events = require("events/Events")
    local Schema = require("profiles/ProfileSchema")
    local ProfileRecorder = require("services/ProfileRecorder")

    local log = { info = function() end, warn = function() end, error = function() end, debug = function() end }

    -- ── Test 1: Initial state is idle, no blackboard keys ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        T.assert_eq(rec:get_state(), "idle", "initial state is idle")
        T.assert_true(rec:get_working_profile() == nil, "no working profile initially")
        T.assert_true(bb:get("recorder.state") == nil, "no recorder.state on bb")
        T.assert_true(bb:get("recorder.working_profile") == nil, "no recorder.working_profile on bb")
        T.assert_true(bb:get("recorder.hotspot_count") == nil, "no recorder.hotspot_count on bb")
    end

    -- ── Test 2: start_recording() sets state, writes blackboard, auto-fills map_id ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 530)

        local started_event = nil
        bus:on(Events.RECORDER_STARTED, function(payload)
            started_event = payload
        end)

        local ok = rec:start_recording()
        T.assert_true(ok, "start_recording returns true")
        T.assert_eq(rec:get_state(), "recording", "state is recording after start")
        T.assert_eq(bb:get("recorder.state"), "recording", "bb recorder.state is recording")
        T.assert_true(bb:get("recorder.working_profile") ~= nil, "bb has working_profile")
        T.assert_eq(bb:get("recorder.hotspot_count"), 0, "bb hotspot_count is 0")
        T.assert_true(started_event ~= nil, "RECORDER_STARTED emitted")

        local wp = rec:get_working_profile()
        T.assert_eq(wp.requirements.map_id, 530, "map_id auto-filled from blackboard")
        T.assert_eq(wp.version, Schema.SCHEMA_VERSION, "version from Schema.defaults")
    end

    -- ── Test 3: add_hotspot() reads player position, appends with auto-ID and default radius ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        bb:set("player.position", { x = 100, y = 200, z = 50 })
        rec:start_recording()

        local hs_event = nil
        bus:on(Events.RECORDER_HOTSPOT_ADDED, function(payload)
            hs_event = payload
        end)

        local ok = rec:add_hotspot("Spot A")
        T.assert_true(ok, "add_hotspot returns true")
        T.assert_true(hs_event ~= nil, "RECORDER_HOTSPOT_ADDED emitted")
        T.assert_eq(hs_event.hotspot.id, "hs_1", "hotspot id is hs_1")
        T.assert_eq(hs_event.hotspot.x, 100, "hotspot x from player pos")
        T.assert_eq(hs_event.hotspot.y, 200, "hotspot y from player pos")
        T.assert_eq(hs_event.hotspot.z, 50, "hotspot z from player pos")
        T.assert_eq(hs_event.hotspot.radius, 40, "default radius is 40")
        T.assert_eq(hs_event.hotspot.label, "Spot A", "label passed through")

        local wp = rec:get_working_profile()
        T.assert_eq(#wp.hotspots, 1, "1 hotspot in working profile")
        T.assert_eq(bb:get("recorder.hotspot_count"), 1, "bb hotspot_count is 1")
    end

    -- ── Test 4: Multiple hotspots work correctly, hotspot_count updates ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        rec:start_recording()

        bb:set("player.position", { x = 10, y = 20, z = 30 })
        rec:add_hotspot("A")

        bb:set("player.position", { x = 40, y = 50, z = 60 })
        rec:add_hotspot("B")

        bb:set("player.position", { x = 70, y = 80, z = 90 })
        rec:add_hotspot("C")

        local wp = rec:get_working_profile()
        T.assert_eq(#wp.hotspots, 3, "3 hotspots after 3 adds")
        T.assert_eq(wp.hotspots[1].id, "hs_1", "first hotspot id")
        T.assert_eq(wp.hotspots[2].id, "hs_2", "second hotspot id")
        T.assert_eq(wp.hotspots[3].id, "hs_3", "third hotspot id")
        T.assert_eq(wp.hotspots[1].x, 10, "first hotspot x")
        T.assert_eq(wp.hotspots[3].x, 70, "third hotspot x")
        T.assert_eq(bb:get("recorder.hotspot_count"), 3, "bb hotspot_count is 3")
    end

    -- ── Test 5: add_vendor() appends with sell=true, repair=true ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        bb:set("player.position", { x = 500, y = 600, z = 700 })
        rec:start_recording()

        local ok = rec:add_vendor()
        T.assert_true(ok, "add_vendor returns true")

        local wp = rec:get_working_profile()
        T.assert_eq(#wp.vendors, 1, "1 vendor added")
        T.assert_eq(wp.vendors[1].x, 500, "vendor x")
        T.assert_eq(wp.vendors[1].y, 600, "vendor y")
        T.assert_eq(wp.vendors[1].z, 700, "vendor z")
        T.assert_eq(wp.vendors[1].sell, true, "vendor sell=true")
        T.assert_eq(wp.vendors[1].repair, true, "vendor repair=true")
        T.assert_eq(wp.vendors[1].food, false, "vendor food=false")
        T.assert_eq(wp.vendors[1].water, false, "vendor water=false")
        T.assert_eq(wp.vendors[1].npc_id, 0, "vendor npc_id=0")
        T.assert_eq(wp.vendors[1].name, "", "vendor name empty")
    end

    -- ── Test 6: add_blackspot() appends with default radius ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        bb:set("player.position", { x = 111, y = 222, z = 333 })
        rec:start_recording()

        local ok = rec:add_blackspot()
        T.assert_true(ok, "add_blackspot returns true")

        local wp = rec:get_working_profile()
        T.assert_eq(#wp.blackspots, 1, "1 blackspot added")
        T.assert_eq(wp.blackspots[1].x, 111, "blackspot x")
        T.assert_eq(wp.blackspots[1].y, 222, "blackspot y")
        T.assert_eq(wp.blackspots[1].z, 333, "blackspot z")
        T.assert_eq(wp.blackspots[1].radius, 20, "blackspot default radius=20")

        -- Custom radius
        bb:set("player.position", { x = 444, y = 555, z = 666 })
        rec:add_blackspot(50)
        T.assert_eq(wp.blackspots[2].radius, 50, "blackspot custom radius=50")
    end

    -- ── Test 7: remove_last() removes in reverse chronological order ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        rec:start_recording()

        bb:set("player.position", { x = 1, y = 2, z = 3 })
        rec:add_hotspot("H1")
        bb:set("player.position", { x = 4, y = 5, z = 6 })
        rec:add_vendor()
        bb:set("player.position", { x = 7, y = 8, z = 9 })
        rec:add_blackspot()

        local wp = rec:get_working_profile()
        T.assert_eq(#wp.hotspots, 1, "1 hotspot before remove")
        T.assert_eq(#wp.vendors, 1, "1 vendor before remove")
        T.assert_eq(#wp.blackspots, 1, "1 blackspot before remove")

        -- Remove blackspot (last added)
        local removed_event = nil
        bus:on(Events.RECORDER_HOTSPOT_REMOVED, function() removed_event = true end)

        local ok1 = rec:remove_last()
        T.assert_true(ok1, "remove_last returns true")
        T.assert_eq(#wp.blackspots, 0, "blackspot removed (last added)")
        T.assert_eq(#wp.vendors, 1, "vendor still present")
        T.assert_true(removed_event == nil, "no HOTSPOT_REMOVED for blackspot")

        -- Remove vendor (second-to-last)
        local ok2 = rec:remove_last()
        T.assert_true(ok2, "remove_last returns true again")
        T.assert_eq(#wp.vendors, 0, "vendor removed")
        T.assert_eq(#wp.hotspots, 1, "hotspot still present")

        -- Remove hotspot (first added)
        rec:remove_last()
        T.assert_eq(#wp.hotspots, 0, "hotspot removed")
        T.assert_eq(bb:get("recorder.hotspot_count"), 0, "bb hotspot_count is 0 after remove")
        T.assert_true(removed_event == true, "RECORDER_HOTSPOT_REMOVED emitted for hotspot")

        -- Nothing left to remove
        local ok3 = rec:remove_last()
        T.assert_true(ok3 == false, "remove_last returns false when history empty")
    end

    -- ── Test 8: finish_recording() validates, returns profile, clears state ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 530)
        rec:start_recording()

        bb:set("player.position", { x = 100, y = 200, z = 50 })
        rec:add_hotspot("Grind Spot")

        local stopped_event = nil
        bus:on(Events.RECORDER_STOPPED, function(payload)
            stopped_event = payload
        end)

        local profile, err = rec:finish_recording()
        T.assert_true(profile ~= nil, "finish returns profile")
        T.assert_true(err == nil, "finish returns no error")
        T.assert_eq(profile.requirements.map_id, 530, "profile has map_id")
        T.assert_eq(#profile.hotspots, 1, "profile has 1 hotspot")
        T.assert_eq(rec:get_state(), "idle", "state is idle after finish")
        T.assert_true(rec:get_working_profile() == nil, "working profile cleared")
        T.assert_true(bb:get("recorder.state") == nil, "bb recorder.state cleared")
        T.assert_true(bb:get("recorder.working_profile") == nil, "bb working_profile cleared")
        T.assert_true(bb:get("recorder.hotspot_count") == nil, "bb hotspot_count cleared")
        T.assert_true(stopped_event ~= nil, "RECORDER_STOPPED emitted")
        T.assert_true(stopped_event.profile ~= nil, "stopped event has profile")
    end

    -- ── Test 8b: finish_recording() with invalid profile returns nil + error ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 530)
        rec:start_recording()
        -- No hotspots added → validation fails

        local profile, err = rec:finish_recording()
        T.assert_true(profile == nil, "finish returns nil for invalid profile")
        T.assert_true(type(err) == "string", "finish returns error string")
        T.assert_eq(rec:get_state(), "recording", "state stays recording on validation failure")
    end

    -- ── Test 9: cancel_recording() discards working copy, clears blackboard ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.map_id", 1)
        rec:start_recording()

        bb:set("player.position", { x = 10, y = 20, z = 30 })
        rec:add_hotspot()

        local stopped_event = nil
        bus:on(Events.RECORDER_STOPPED, function(payload)
            stopped_event = payload
        end)

        rec:cancel_recording()
        T.assert_eq(rec:get_state(), "idle", "state is idle after cancel")
        T.assert_true(rec:get_working_profile() == nil, "working profile discarded")
        T.assert_true(bb:get("recorder.state") == nil, "bb recorder.state cleared")
        T.assert_true(bb:get("recorder.working_profile") == nil, "bb working_profile cleared")
        T.assert_true(stopped_event ~= nil, "RECORDER_STOPPED emitted on cancel")
        T.assert_eq(stopped_event.cancelled, true, "stopped event has cancelled=true")
    end

    -- ── Test 10: Edit mode — deep-copies existing, doesn't mutate original ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        local original = Schema.defaults()
        original.metadata.name = "My Route"
        original.requirements.map_id = 530
        original.hotspots = {
            { id = "hs_orig", x = 10, y = 20, z = 30, radius = 40, label = "Original" },
        }

        bb:set("player.map_id", 530)
        rec:start_recording(original)

        local wp = rec:get_working_profile()
        T.assert_eq(wp.metadata.name, "My Route", "edit preserves metadata.name")
        T.assert_eq(wp.requirements.map_id, 530, "edit preserves map_id")
        T.assert_eq(#wp.hotspots, 1, "edit preserves existing hotspots")
        T.assert_eq(wp.hotspots[1].id, "hs_orig", "edit preserves hotspot id")

        -- Add a new hotspot to the working copy
        bb:set("player.position", { x = 99, y = 88, z = 77 })
        rec:add_hotspot("New Spot")

        T.assert_eq(#wp.hotspots, 2, "working copy has 2 hotspots")
        T.assert_eq(#original.hotspots, 1, "original still has 1 hotspot (not mutated)")
        T.assert_eq(original.hotspots[1].id, "hs_orig", "original hotspot unchanged")
    end

    -- ── Test 11: Guards — add_hotspot returns false when idle ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        bb:set("player.position", { x = 1, y = 2, z = 3 })

        T.assert_true(rec:add_hotspot() == false, "add_hotspot returns false when idle")
        T.assert_true(rec:add_vendor() == false, "add_vendor returns false when idle")
        T.assert_true(rec:add_blackspot() == false, "add_blackspot returns false when idle")
        T.assert_true(rec:remove_last() == false, "remove_last returns false when idle")

        -- start_recording while already recording returns false
        bb:set("player.map_id", 1)
        rec:start_recording()
        T.assert_true(rec:start_recording() == false, "start_recording returns false when already recording")
    end

    -- ── Test 12: set_hotspot_radius(60) — next add_hotspot uses radius=60 ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)
        local rec = ProfileRecorder:new(bus, bb, log, nil)

        T.assert_eq(rec:get_hotspot_radius(), 40, "default hotspot radius is 40")
        rec:set_hotspot_radius(60)
        T.assert_eq(rec:get_hotspot_radius(), 60, "hotspot radius updated to 60")

        bb:set("player.map_id", 1)
        bb:set("player.position", { x = 10, y = 20, z = 30 })
        rec:start_recording()
        rec:add_hotspot()

        local wp = rec:get_working_profile()
        T.assert_eq(wp.hotspots[1].radius, 60, "hotspot created with radius=60")
    end

    -- ── Test 13: update() with keybind triggers add_hotspot ──
    do
        local bus = EventBus:new()
        local bb = Blackboard:new(bus)

        local keybind_pressed = false
        local mock_keybind = {
            get_keybind_state = function()
                return keybind_pressed
            end,
        }

        local rec = ProfileRecorder:new(bus, bb, log, mock_keybind)
        bb:set("player.map_id", 1)
        bb:set("player.position", { x = 50, y = 60, z = 70 })
        rec:start_recording()

        -- Not pressed → no hotspot
        rec:update()
        T.assert_eq(#rec:get_working_profile().hotspots, 0, "no hotspot when keybind not pressed")

        -- Pressed → hotspot added
        keybind_pressed = true
        rec:update()
        T.assert_eq(#rec:get_working_profile().hotspots, 1, "hotspot added when keybind pressed")

        -- update() when idle does nothing
        rec:cancel_recording()
        keybind_pressed = true
        rec:update() -- should not error
    end

    return {
        sc_recorder_idle = true,
        sc_recorder_start = true,
        sc_recorder_add_hotspot = true,
        sc_recorder_multi_hotspots = true,
        sc_recorder_add_vendor = true,
        sc_recorder_add_blackspot = true,
        sc_recorder_remove_last = true,
        sc_recorder_finish = true,
        sc_recorder_finish_invalid = true,
        sc_recorder_cancel = true,
        sc_recorder_edit_mode = true,
        sc_recorder_guards = true,
        sc_recorder_set_radius = true,
        sc_recorder_keybind_update = true,
    }
end

return { run = run }
