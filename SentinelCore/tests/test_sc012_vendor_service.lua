local T = require("tests/TestUtil")

local function run()
    local player = T.mock_object({ faction_id = 1, position = { x = 0, y = 0, z = 0 } })

    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return {} end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorService = require("services/VendorService")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.faction_id", 1)

    local nav = {
        estimate_path_cost = function(_, _, _, cb) cb(true, 10, nil) end,
        move_to = function(_, _, cb) cb(true, nil, nil) end,
    }

    local world = { captured_opts = nil }
    world.get_nearby_vendors = function(self, _, opts, cb)
        self.captured_opts = opts
        cb(true, {
            { vendor_id = 1, npc_id = 1, map_id = 571, x = 1, y = 1, z = 1, can_sell = true, can_repair = true, faction_mask = 0 },
        }, nil)
    end

    local inv = {
        needs_vendor_trip = function() return true end,
    }

    local vendor = VendorService:new(bus, bb, nav, world, inv, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 1,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })

    local ok = vendor:start({ map_id = 530, zone_id = 1, area_id = 2 })
    T.assert_true(ok == true, "vendor start should initiate")
    T.assert_true(world.captured_opts ~= nil, "world_data request options should be captured")
    T.assert_eq(world.captured_opts.faction, "alliance", "faction template id should normalize to alliance")
    T.assert_eq(vendor:get_state(), "failed", "mismatched map candidate should fail closed")
    T.assert_eq(vendor:get_last_error(), ErrorCodes.VENDOR_NONE_VIABLE, "expected explicit no viable vendor reason")

    -- Return-to-anchor flow should travel to vendor, interact, and return.
    local nav_calls = {}
    local nav2 = {
        estimate_path_cost = function(_, _, _, cb) cb(true, 12, nil) end,
        move_to = function(_, destination, cb)
            nav_calls[#nav_calls + 1] = { x = destination.x, y = destination.y, z = destination.z }
            cb(true, nil, nil)
        end,
    }

    local visible_vendor = T.mock_object({
        npc_id = 1234,
        position = { x = 10, y = 10, z = 10 },
    })
    T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { visible_vendor } end,
        },
    })

    local bb2 = Blackboard:new(bus)
    bb2:set("player.position", { x = 0, y = 0, z = 0 })
    bb2:set("player.faction_id", 1)
    bb2:set("grind.anchor", { x = 25, y = 30, z = 5 })

    local world2 = {
        get_nearby_vendors = function(_, _, _, cb)
            cb(true, {
                { vendor_id = 7, npc_id = 1234, map_id = 530, x = 10, y = 10, z = 10, can_sell = true, can_repair = true, faction_mask = 0 },
            }, nil)
        end,
    }

    local vendor2 = VendorService:new(bus, bb2, nav2, world2, inv, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 1,
        return_to_anchor = true,
        return_timeout = 10,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })

    local ok2 = vendor2:start({ map_id = 530, zone_id = 1, area_id = 2 })
    T.assert_true(ok2 == true, "same-map vendor start should initiate")
    vendor2:update() -- interact -> wait_window
    core._set_time(1001) -- advance past vendor_interact_delay (default 0.75s)
    local update_ok, update_err = vendor2:update() -- wait_window -> selling -> repairing -> done -> returning -> completed
    T.assert_true(update_ok == true, "vendor update should complete without failure: " .. tostring(update_err))
    T.assert_eq(vendor2:get_state(), "completed", "vendor flow should complete")
    T.assert_eq(#nav_calls, 2, "expected move_to vendor and move_to anchor")
    T.assert_eq(nav_calls[2].x, 25, "return destination x should match grind anchor")
    T.assert_eq(nav_calls[2].y, 30, "return destination y should match grind anchor")
    T.assert_eq(nav_calls[2].z, 5, "return destination z should match grind anchor")

    -- Faction mask filtering should use team semantics, not raw faction template ids.
    local bb3 = Blackboard:new(bus)
    bb3:set("player.position", { x = 0, y = 0, z = 0 })
    bb3:set("player.faction_id", 55) -- Alliance faction template id.
    local world3 = {
        get_nearby_vendors = function(_, _, _, cb)
            cb(true, {
                { vendor_id = 8, npc_id = 1111, map_id = 530, x = 1, y = 1, z = 1, can_sell = true, can_repair = true, faction_mask = 2 }, -- Horde only.
            }, nil)
        end,
    }
    local vendor3 = VendorService:new(bus, bb3, nav, world3, inv, {
        search_radius = 100,
        require_sell = true,
        require_repair = false,
        interaction_timeout = 1,
    }, { schema_version = "vendor_runtime_cache.v1", entries = {}, updated_at_unix = 0 })
    local ok3 = vendor3:start({ map_id = 530, zone_id = 1, area_id = 2 })
    T.assert_true(ok3 == true, "faction-mismatch vendor start should initiate")
    T.assert_eq(vendor3:get_state(), "failed", "horde-only vendor should be rejected for alliance player")
    T.assert_eq(vendor3:get_last_error(), ErrorCodes.VENDOR_NONE_VIABLE, "faction mismatch should result in no viable vendor")

    return {
        sc012_same_map_vendor = true,
        sc012_return_to_anchor = true,
        sc012_faction_resolution = true,
    }
end

return { run = run }
