local T = require("tests/TestUtil")
local JSON = require("lib/JSON")
local Defaults = require("core/Defaults")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

local SmokeSuite = {}

---@param env table
---@param now number
local function set_time(env, now)
    if env and env.core and env.core._set_time then
        env.core._set_time(now)
    end
end

---@return table
local function build_nav_stub()
    return {
        update = function() end,
        is_available = function() return true, nil end,
        is_server_available = function() return true end,
        stop = function() end,
        move_to = function(_, _, cb) if cb then cb(true, nil, nil) end end,
        estimate_path_cost = function(_, _, to_pos, cb)
            local cost = math.abs((to_pos and to_pos.x) or 0) + 1
            cb(true, cost, nil)
        end,
    }
end

---@param canonical table
---@return table
local function build_world_stub(canonical)
    return {
        update = function() end,
        resolve_context = function(_, _, cb)
            cb(true, canonical, nil)
        end,
    }
end

---@param name string
---@param fn fun(env: table)
---@return boolean
local function run_isolated(name, fn)
    local player = T.mock_object({
        class_id = 2,
        spec_id = 0,
        level = 20,
        xp = 500,
        max_xp = 1000,
        faction_id = 1,
        position = { x = 0, y = 0, z = 0 },
    })

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return {} end,
        },
    })

    local ok, err = pcall(fn, env)
    if env and env.restore then
        env.restore()
    end

    if not ok then
        error(string.format("%s failed: %s", name, tostring(err)))
    end

    return true
end

local function scenario_start_here_grind_loop_stability(env)
    local Client = require("core/Client")
    local client = Client:new({
        navigation_adapter = build_nav_stub(),
        world_data_adapter = build_world_stub({ map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 }),
        runtime_overrides = {
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
            telemetry = { flush_interval = 0.25 },
        },
    })

    local ok = client:start("grind")
    T.assert_true(ok == true, "start_here: client start failed")

    for i = 1, 120 do
        set_time(env, 1000 + (i * 0.1))
        client:update()
        T.assert_true(client:get_state() ~= "failed", "start_here: hard failure detected")
    end

    client:stop("smoke_end")
    client:destroy()
end

local function scenario_kill_loot_cycle_repeats(env)
    local Client = require("core/Client")
    local client = Client:new({
        navigation_adapter = build_nav_stub(),
        world_data_adapter = build_world_stub({ map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 }),
        runtime_overrides = {
            telemetry = { flush_interval = 0.1 },
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
        },
    })

    local ok = client:start("grind")
    T.assert_true(ok == true, "kill_loot: client start failed")

    local bus = client:get_event_bus()
    for i = 1, 5 do
        bus:emit(Events.KILL_CONFIRMED, { seq = i })
        bus:emit(Events.LOOT_COMPLETED, { seq = i })
    end

    set_time(env, 1001)
    client:update()

    local snap = client:get_snapshot()
    T.assert_eq(snap.telemetry.counters.kills, 5, "kill_loot: kills counter mismatch")
    T.assert_eq(snap.telemetry.counters.loot_events, 5, "kill_loot: loot counter mismatch")
    T.assert_true((tonumber(snap.telemetry.rates.kills_per_hour) or 0) > 0, "kill_loot: kills/hr not populated")

    client:stop("smoke_end")
    client:destroy()
end

local function scenario_inventory_threshold_triggers_vendor(env)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")

    local service_key = "services/InventoryService"
    local prev_service = package.loaded[service_key]

    -- 21841 = Netherweave Bag (16 slots each) in BAG_SIZES lookup.
    local bag_obj = T.mock_object({ item_id = 21841 })

    -- Player with 4 Netherweave Bags equipped at slots 31-34.
    env.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            get_item_at_inventory_slot = function(_, slot_id)
                if slot_id >= 31 and slot_id <= 34 then
                    return { object = bag_obj }
                end
                return nil
            end,
        }
    end

    -- Fill bags nearly full: bag 0 = 16 items, bags 1-3 = 16 each, bag 4 = 15.
    -- Total capacity = 16 + 4*16 = 80, used = 79, free = 1.
    -- Bag 0 items need slot_id in 36-51 (backpack storage range).
    env.core.inventory.get_items_in_bag = function(bag_id)
        local count = 16
        if bag_id == 4 then count = 15 end
        local out = {}
        for i = 1, count do
            local slot = { object = T.mock_object({ item_id = 9000 + (bag_id * 16) + i }) }
            if bag_id == 0 then
                slot.slot_id = 35 + i  -- 36..51 = backpack storage
            end
            out[#out + 1] = slot
        end
        return out
    end

    package.loaded[service_key] = nil
    local InventoryService = require(service_key)

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local emitted = false

    bus:on(Events.INVENTORY_THRESHOLD_REACHED, function()
        emitted = true
    end, { owner = "smoke_inventory" })

    local inventory = InventoryService:new(bus, bb, {}, {
        min_free_slots = 2,
        never_sell = {},
        always_sell = {},
        keep_stack_min = {},
        special_rules = {},
    })

    inventory:update()
    T.assert_true(bb:get("inventory.needs_vendor", false) == true, "inventory_threshold: vendor trigger missing")
    T.assert_true(emitted == true, "inventory_threshold: threshold event missing")

    package.loaded[service_key] = prev_service
end

local function scenario_same_map_vendor_selected(env)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorService = require("services/VendorService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.faction_id", 1)

    local completed_vendor_id = nil
    bus:on(Events.VENDOR_COMPLETED, function(data)
        completed_vendor_id = data and data.vendor_id or nil
    end, { owner = "smoke_vendor_success" })

    env.core.object_manager.get_visible_objects = function()
        return {
            T.mock_object({ npc_id = 1001, position = { x = 8, y = 0, z = 0 } }),
            T.mock_object({ npc_id = 1002, position = { x = 2, y = 0, z = 0 } }),
        }
    end

    local nav = {
        estimate_path_cost = function(_, _, to_pos, cb)
            if (to_pos and to_pos.x or 0) < 5 then
                cb(true, 5, nil)
            else
                cb(true, 20, nil)
            end
        end,
        move_to = function(_, _, cb) cb(true, nil, nil) end,
    }

    local world = {
        get_nearby_vendors = function(_, _, _, cb)
            cb(true, {
                { vendor_id = 1, npc_id = 1001, map_id = 530, x = 8, y = 0, z = 0, can_sell = true, can_repair = true, faction_mask = 0 },
                { vendor_id = 2, npc_id = 1002, map_id = 530, x = 2, y = 0, z = 0, can_sell = true, can_repair = true, faction_mask = 0 },
                { vendor_id = 3, npc_id = 2003, map_id = 571, x = 1, y = 1, z = 1, can_sell = true, can_repair = true, faction_mask = 0 },
            }, nil)
        end,
    }

    local inv = { needs_vendor_trip = function() return true end }
    local vendor = VendorService:new(bus, bb, nav, world, inv, Defaults.copy(Defaults.vendor), Defaults.copy(Defaults.vendor_cache))
    local ok = vendor:start({ map_id = 530, zone_id = 3518, area_id = 3520 })
    T.assert_true(ok == true, "same_map_vendor: start failed")

    local update_ok = vendor:update()
    T.assert_true(update_ok == true, "same_map_vendor: update failed")
    T.assert_eq(vendor:get_state(), "completed", "same_map_vendor: expected completed state")
    T.assert_eq(completed_vendor_id, 2, "same_map_vendor: non-optimal candidate selected")
end

local function scenario_vendor_unavailable_fails_closed(env)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local VendorService = require("services/VendorService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.faction_id", 1)

    local nav = {
        estimate_path_cost = function(_, _, _, cb) cb(false, nil, ErrorCodes.VENDOR_UNREACHABLE) end,
        move_to = function(_, _, cb) cb(false, ErrorCodes.VENDOR_UNREACHABLE, nil) end,
    }
    local world = {
        get_nearby_vendors = function(_, _, _, cb)
            cb(true, {
                { vendor_id = 99, npc_id = 9099, map_id = 571, x = 1, y = 1, z = 1, can_sell = true, can_repair = true, faction_mask = 0 },
            }, nil)
        end,
    }

    local inv = { needs_vendor_trip = function() return true end }
    local vendor = VendorService:new(bus, bb, nav, world, inv, Defaults.copy(Defaults.vendor), Defaults.copy(Defaults.vendor_cache))
    local ok = vendor:start({ map_id = 530, zone_id = 3518, area_id = 3520 })
    T.assert_true(ok == true, "vendor_unavailable: start failed")
    T.assert_eq(vendor:get_state(), "failed", "vendor_unavailable: expected failed state")
    T.assert_eq(vendor:get_last_error(), ErrorCodes.VENDOR_NONE_VIABLE, "vendor_unavailable: wrong fail-closed reason")
end

local function scenario_dependency_outage_escalation(env)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local RecoveryService = require("services/RecoveryService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local recovery = RecoveryService:new(bus, bb, {
        auto_restart_max_attempts = 3,
        auto_restart_backoff_secs = { 2, 5, 10 },
    })

    recovery:report_critical(ErrorCodes.DEP_WORLDDATA_UNAVAILABLE)

    local cmd1 = recovery:update(1000)
    T.assert_eq(cmd1.action, "pause", "dependency_outage: first action must pause")

    local cmd2 = recovery:update(1002)
    T.assert_eq(cmd2.action, "restart", "dependency_outage: second action must restart")
    recovery:complete_restart_attempt(false)

    local cmd3 = recovery:update(1007)
    T.assert_eq(cmd3.action, "restart", "dependency_outage: third action must restart")
    recovery:complete_restart_attempt(false)

    local cmd4 = recovery:update(1017)
    T.assert_eq(cmd4.action, "restart", "dependency_outage: fourth action must restart")
    recovery:complete_restart_attempt(false)

    local cmd5 = recovery:update(1018)
    T.assert_eq(cmd5.action, "fail", "dependency_outage: final action must fail")
    T.assert_eq(cmd5.error_code, ErrorCodes.RECOVERY_ATTEMPTS_EXHAUSTED, "dependency_outage: wrong failure code")
end

local function scenario_lifecycle_idempotency_under_load(env)
    local Client = require("core/Client")
    local client = Client:new({
        navigation_adapter = build_nav_stub(),
        world_data_adapter = build_world_stub({ map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 }),
        runtime_overrides = {
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
        },
    })

    local ok1 = client:start("grind")
    local ok2 = client:start("grind")
    T.assert_true(ok1 == true and ok2 == true, "lifecycle: start should be idempotent")

    for i = 1, 30 do
        set_time(env, 2000 + (i * 0.1))
        client:update()
    end

    T.assert_true(client:pause("smoke_pause") == true, "lifecycle: pause failed")
    T.assert_true(client:pause("smoke_pause") == true, "lifecycle: second pause should be idempotent")
    T.assert_true(client:resume() == true, "lifecycle: resume failed")
    T.assert_true(client:resume() == true, "lifecycle: second resume should be idempotent")
    T.assert_true(client:stop("smoke_stop") == true, "lifecycle: stop failed")
    T.assert_true(client:stop("smoke_stop") == true, "lifecycle: second stop should be idempotent")
    T.assert_eq(client:get_state(), "idle", "lifecycle: expected idle terminal state")

    client:destroy()
end

local function scenario_restart_restores_runtime_state(env)
    local Client = require("core/Client")

    local failing_world = {
        update = function() end,
        resolve_context = function(_, _, cb)
            cb(false, nil, ErrorCodes.CTX_UNRESOLVED)
        end,
    }

    local nav = build_nav_stub()
    local client1 = Client:new({
        navigation_adapter = nav,
        world_data_adapter = failing_world,
        runtime_overrides = {
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
        },
    })

    local ok = client1:start("grind")
    T.assert_true(ok == true, "restart_restore: first start failed")
    set_time(env, 3001)
    client1:update()
    client1:stop("smoke_stop")
    client1:destroy()

    local raw_state = env.fs["SentinelCore/state/runtime_state.v1.json"]
    T.assert_true(type(raw_state) == "string" and raw_state ~= "", "restart_restore: runtime state was not persisted")
    local parsed_state = JSON.decode(raw_state)
    T.assert_true(type(parsed_state) == "table", "restart_restore: persisted runtime state malformed")
    T.assert_eq(parsed_state.schema_version, "runtime_state.v1", "restart_restore: schema mismatch")
    T.assert_eq(parsed_state.last_error_code, ErrorCodes.CTX_UNRESOLVED, "restart_restore: last error not restored")

    local healthy_world = build_world_stub({ map_id = 530, zone_id = 3518, area_id = 3520, confidence = 1.0 })
    local client2 = Client:new({
        navigation_adapter = build_nav_stub(),
        world_data_adapter = healthy_world,
        runtime_overrides = {
            runtime = { context_resolve_interval = 0.1, dependency_health_interval = 0.1 },
        },
    })

    local ok2 = client2:start("grind")
    T.assert_true(ok2 == true, "restart_restore: second start failed")
    set_time(env, 3002)
    client2:update()
    T.assert_true(client2:get_state() ~= "failed", "restart_restore: restart entered failed state unexpectedly")
    client2:stop("smoke_stop")
    client2:destroy()
end

local scenario_handlers = {
    start_here_grind_loop_stability = scenario_start_here_grind_loop_stability,
    kill_loot_cycle_repeats = scenario_kill_loot_cycle_repeats,
    inventory_threshold_triggers_vendor = scenario_inventory_threshold_triggers_vendor,
    same_map_vendor_selected = scenario_same_map_vendor_selected,
    vendor_unavailable_fails_closed = scenario_vendor_unavailable_fails_closed,
    dependency_outage_escalation = scenario_dependency_outage_escalation,
    lifecycle_idempotency_under_load = scenario_lifecycle_idempotency_under_load,
    restart_restores_runtime_state = scenario_restart_restores_runtime_state,
}

local scenarios = {
    "start_here_grind_loop_stability",
    "kill_loot_cycle_repeats",
    "inventory_threshold_triggers_vendor",
    "same_map_vendor_selected",
    "vendor_unavailable_fails_closed",
    "dependency_outage_escalation",
    "lifecycle_idempotency_under_load",
    "restart_restores_runtime_state",
}

---@return table<string, boolean>
function SmokeSuite.run()
    local results = {}
    for i = 1, #scenarios do
        local name = scenarios[i]
        local handler = scenario_handlers[name]
        local ok, err = pcall(run_isolated, name, handler)
        results[name] = ok == true
        if not ok and core and core.log_error then
            core.log_error("[SentinelCore Smoke] " .. tostring(err))
        end
    end
    return results
end

return SmokeSuite
