local T = require("tests/TestUtil")

local function run()
    -- ---------------------------------------------------------------
    -- Test 1: Sell loop iterates all candidates with throttle
    -- ---------------------------------------------------------------
    local sell_calls = {}
    local interact_calls = {}
    local player = T.mock_object({ faction_id = 1, position = { x = 0, y = 0, z = 0 } })
    local visible_vendor = T.mock_object({ npc_id = 42, position = { x = 1, y = 0, z = 0 } })

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { visible_vendor } end,
        },
        input = {
            interact_with_object = function(obj) interact_calls[#interact_calls + 1] = obj end,
            use_container_item = function(bag, slot)
                sell_calls[#sell_calls + 1] = { bag = bag, slot = slot }
            end,
            is_key_pressed = function() return false end,
            cursor_has_spell = function() return false end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorService = require("services/VendorService")
    local Events = require("events/Events")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.faction_id", 1)
    bb:set("grind.anchor", { x = 50, y = 50, z = 0 })

    -- Mock nav: immediate success
    local nav = {
        estimate_path_cost = function(_, _, _, cb) cb(true, 5, nil) end,
        move_to = function(_, _, cb) cb(true, nil, nil) end,
    }

    -- Mock world: return a single vendor on map 530
    local world = {
        get_nearby_vendors = function(_, _, _, cb)
            cb(true, {
                { vendor_id = 1, npc_id = 42, map_id = 530, x = 1, y = 0, z = 0,
                  can_sell = true, can_repair = false, faction_mask = 0 },
            }, nil)
        end,
    }

    -- Mock inventory: 3 items to sell
    local sell_candidates = {
        { item_id = 100, bag_id = 0, slot_id = 38, quality = 0, stack_count = 5 },
        { item_id = 200, bag_id = 1, slot_id = 2,  quality = 0, stack_count = 1 },
        { item_id = 300, bag_id = 0, slot_id = 42, quality = 1, stack_count = 3 },
    }
    local inv = {
        needs_vendor_trip = function() return true end,
        get_sell_candidates = function() return T.deep_copy(sell_candidates) end,
    }

    local events_received = {}
    bus:on(Events.VENDOR_SELL_STARTED, function(e) events_received.sell_started = e end)
    bus:on(Events.VENDOR_SELL_COMPLETED, function(e) events_received.sell_completed = e end)
    bus:on(Events.VENDOR_COMPLETED, function(e) events_received.completed = e end)

    local vendor = VendorService:new(bus, bb, nav, world, inv, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 5,
        return_to_anchor = true,
        return_timeout = 10,
        vendor_interact_delay = 0.5,
        vendor_sell_delay = 0.2,
        vendor_sell_timeout = 30,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })

    -- Start the vendor flow (fetching -> ranking -> travel -> interact all resolve immediately)
    local ok = vendor:start({ map_id = 530, zone_id = 1, area_id = 2 })
    T.assert_true(ok == true, "vendor should start successfully")
    T.assert_eq(vendor:get_state(), "interact", "should reach interact state")

    -- First update: interact with vendor, enter wait_window
    vendor:update()
    T.assert_true(#interact_calls == 1, "should call interact_with_object once")
    T.assert_eq(vendor:get_sub_state(), "wait_window", "should be in wait_window sub-state")
    T.assert_eq(#sell_calls, 0, "should not sell yet during wait_window")

    -- Advance time past vendor_interact_delay (0.5s)
    core._set_time(1000.6)
    vendor:update()
    T.assert_eq(vendor:get_sub_state(), "selling", "should transition to selling")
    T.assert_true(events_received.sell_started ~= nil, "VENDOR_SELL_STARTED should fire")
    T.assert_eq(events_received.sell_started.item_count, 3, "sell_started should report 3 items")

    -- First sell call happens immediately on entering selling
    T.assert_eq(#sell_calls, 1, "first item should be sold immediately")

    -- Sell calls should be in reverse sort order (highest bag first, highest slot first)
    -- Expected order: bag 1 slot 2, bag 0 slot 42, bag 0 slot 38
    T.assert_eq(sell_calls[1].bag, 1, "first sell should be from highest bag")
    T.assert_eq(sell_calls[1].slot, 2, "first sell bag 1 slot 2")

    -- Advance past sell_delay, next tick sells second item
    core._set_time(1000.9)
    vendor:update()
    T.assert_eq(#sell_calls, 2, "second item should be sold after delay")
    T.assert_eq(sell_calls[2].bag, 0, "second sell from bag 0")
    T.assert_eq(sell_calls[2].slot, 42, "second sell slot 42")

    -- Third item
    core._set_time(1001.2)
    vendor:update()
    T.assert_eq(#sell_calls, 3, "third item should be sold")
    T.assert_eq(sell_calls[3].bag, 0, "third sell from bag 0")
    T.assert_eq(sell_calls[3].slot, 38, "third sell slot 38")

    -- Next update: queue empty, transition to repairing then returning then completed
    core._set_time(1001.5)
    vendor:update()
    T.assert_true(events_received.sell_completed ~= nil, "VENDOR_SELL_COMPLETED should fire")
    T.assert_eq(events_received.sell_completed.items_sold, 3, "should report 3 items sold")
    T.assert_eq(vendor:get_state(), "completed", "vendor should complete after sell + return")

    -- ---------------------------------------------------------------
    -- Test 2: No sell candidates skips straight to completed
    -- ---------------------------------------------------------------
    sell_calls = {}
    interact_calls = {}
    events_received = {}

    local bb2 = Blackboard:new(bus)
    bb2:set("player.position", { x = 0, y = 0, z = 0 })
    bb2:set("player.faction_id", 1)

    local inv_empty = {
        needs_vendor_trip = function() return true end,
        get_sell_candidates = function() return {} end,
    }

    local vendor2 = VendorService:new(bus, bb2, nav, world, inv_empty, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 5,
        return_to_anchor = false,
        vendor_interact_delay = 0.5,
        vendor_sell_delay = 0.2,
        vendor_sell_timeout = 30,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })

    core._set_time(2000)
    vendor2:start({ map_id = 530, zone_id = 1, area_id = 2 })
    T.assert_eq(vendor2:get_state(), "interact", "should reach interact")

    vendor2:update() -- interact -> wait_window
    core._set_time(2000.6)
    vendor2:update() -- wait_window -> selling -> repairing -> done -> completed
    T.assert_eq(#sell_calls, 0, "no sell calls with empty candidates")
    T.assert_eq(vendor2:get_state(), "completed", "should complete without selling")

    -- ---------------------------------------------------------------
    -- Test 3: Sell timeout triggers failure
    -- ---------------------------------------------------------------
    local bb3 = Blackboard:new(bus)
    bb3:set("player.position", { x = 0, y = 0, z = 0 })
    bb3:set("player.faction_id", 1)

    -- Inventory that always returns items (infinite queue)
    local inv_infinite = {
        needs_vendor_trip = function() return true end,
        get_sell_candidates = function()
            local items = {}
            for i = 1, 200 do
                items[i] = { item_id = i, bag_id = 0, slot_id = 36 + (i % 16), quality = 0, stack_count = 1 }
            end
            return items
        end,
    }

    local vendor3 = VendorService:new(bus, bb3, nav, world, inv_infinite, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 5,
        return_to_anchor = false,
        vendor_interact_delay = 0.1,
        vendor_sell_delay = 0.2,
        vendor_sell_timeout = 2.0,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })

    core._set_time(3000)
    vendor3:start({ map_id = 530, zone_id = 1, area_id = 2 })
    vendor3:update() -- interact -> wait_window
    core._set_time(3000.2)
    vendor3:update() -- wait_window -> selling

    -- Advance past sell timeout
    core._set_time(3002.3)
    vendor3:update()
    T.assert_eq(vendor3:get_state(), "failed", "should fail on sell timeout")

    return {
        sc023_sell_loop_with_throttle = true,
        sc023_empty_candidates_skip = true,
        sc023_sell_timeout = true,
    }
end

return { run = run }
