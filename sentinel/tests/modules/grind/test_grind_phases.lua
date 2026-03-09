local Safety = require("modules/grind/phases/safety")
local CorpseRun = require("modules/grind/phases/corpse_run")
local Rest = require("modules/grind/phases/rest")
local Loot = require("modules/grind/phases/loot")
local Combat = require("modules/grind/phases/combat")
local Pull = require("modules/grind/phases/pull")
local Acquire = require("modules/grind/phases/acquire")
local Vendor = require("modules/grind/phases/vendor")
local Blackboard = require("core/blackboard")
local Status = require("core/bt/status")
local T = require("tests/test_util")

local M = {}

local function make_bus()
    return {
        publish = function() end,
        subscribe = function() return "sub:mock" end,
    }
end

local function make_nav()
    return {
        move_to = function() return true end,
        stop = function() end,
        is_active = function() return false end,
        get_state = function() return "idle" end,
    }
end

local function make_bb(overrides)
    local bb = Blackboard:new()
    if overrides then
        for k, v in pairs(overrides) do
            bb:set(k, v)
        end
    end
    return bb
end

function M.run()
    -- Save and install minimal core mock so bag_scanner/vendor/rest phases
    -- don't crash when accessing core.inventory / core.game_ui / core.input
    local saved_core = _G.core
    _G.core = {
        inventory = {
            get_items_in_bag = function() return {} end,
            get_num_bag_slots = function() return 0 end,
        },
        game_ui = {
            get_vendor_item_count = function() return 0 end,
            get_vendor_item_info = function() return nil end,
        },
        input = {
            repair_all_items = function() end,
            buy_item = function() end,
            use_container_item = function() end,
            set_target = function() end,
            interact_with_object = function() end,
            use_item = function() end,
        },
        object_manager = {
            get_all_objects = function() return {} end,
        },
        http_get = function(_, cb) if cb then cb(200, nil, '{"items":[]}') end end,
    }

    local bus = make_bus()
    local nav = make_nav()
    local bb = make_bb()

    -- -------------------------------------------------------
    -- Each phase builds without error and has correct name
    -- -------------------------------------------------------
    local safety = Safety.build(bus, nav)
    T.assert_not_nil(safety, "safety builds")
    T.assert_equal(safety.name, "safety", "safety name")

    local corpse = CorpseRun.build(bus, nav)
    T.assert_not_nil(corpse, "corpse_run builds")
    T.assert_equal(corpse.name, "corpse_run", "corpse_run name")

    local rest = Rest.build(bus, nav)
    T.assert_not_nil(rest, "rest builds")
    T.assert_equal(rest.name, "rest", "rest name")

    local loot = Loot.build(bus, nav)
    T.assert_not_nil(loot, "loot builds")
    T.assert_equal(loot.name, "loot_nearby", "loot name")

    local combat = Combat.build()
    T.assert_not_nil(combat, "combat builds")
    T.assert_equal(combat.name, "combat_active", "combat name")

    local pull = Pull.build(bb, bus, nav)
    T.assert_not_nil(pull, "pull builds")
    T.assert_equal(pull.name, "pull_target", "pull name")

    local acquire = Acquire.build(bb)
    T.assert_not_nil(acquire, "acquire builds")
    T.assert_equal(acquire.name, "acquire_target", "acquire name")

    -- -------------------------------------------------------
    -- Combat phase: SUCCESS when in combat, FAILURE when not
    -- -------------------------------------------------------
    local combat_node = Combat.build()
    local bb_combat = make_bb({ ["player.in_combat"] = true })
    T.assert_equal(combat_node:tick(bb_combat), Status.SUCCESS, "combat yields SUCCESS when in combat")

    local bb_no_combat = make_bb({ ["player.in_combat"] = false })
    T.assert_equal(combat_node:tick(bb_no_combat), Status.FAILURE, "combat FAILURE when not in combat")

    -- -------------------------------------------------------
    -- Rest phase: FAILURE when grind disabled
    -- -------------------------------------------------------
    local rest_node = Rest.build(bus, nav)
    local bb_disabled = make_bb({ ["module.grind.enabled"] = false })
    T.assert_equal(rest_node:tick(bb_disabled), Status.FAILURE, "rest FAILURE when grind disabled")

    -- -------------------------------------------------------
    -- Rest phase: FAILURE when engaged (combat.source set)
    -- -------------------------------------------------------
    local rest_node2 = Rest.build(bus, nav)
    local bb_in_combat = make_bb({
        ["module.grind.enabled"] = true,
        ["combat.source"] = "attacker",
    })
    T.assert_equal(rest_node2:tick(bb_in_combat), Status.FAILURE, "rest FAILURE when engaged")

    -- -------------------------------------------------------
    -- Rest phase: RUNNING when HP is low and needs recovery
    -- -------------------------------------------------------
    local rest_node3 = Rest.build(bus, nav)
    local bb_low_hp = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["player.health_pct"] = 0.30,
        ["player.mana_pct"] = 1.0,
        ["module.grind.health_eat_pct"] = 0.50,
        ["module.grind.mana_drink_pct"] = 0.40,
        ["module.grind.needs_food"] = true,
        ["module.grind.needs_water"] = true,
    })
    T.assert_equal(rest_node3:tick(bb_low_hp), Status.RUNNING, "rest RUNNING when HP low")

    -- -------------------------------------------------------
    -- Rest phase: SUCCESS when fully recovered
    -- -------------------------------------------------------
    local rest_node4 = Rest.build(bus, nav)
    local bb_recovered = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["player.health_pct"] = 0.30,
        ["player.mana_pct"] = 1.0,
        ["module.grind.health_eat_pct"] = 0.50,
        ["module.grind.mana_drink_pct"] = 0.40,
        ["module.grind.needs_food"] = true,
        ["module.grind.needs_water"] = true,
    })
    -- First tick enters rest (RUNNING because HP < 90%)
    T.assert_equal(rest_node4:tick(bb_recovered), Status.RUNNING, "rest RUNNING while recovering")
    -- Simulate recovery
    bb_recovered:set("player.health_pct", 0.95)
    T.assert_equal(rest_node4:tick(bb_recovered), Status.SUCCESS, "rest SUCCESS when recovered")

    -- -------------------------------------------------------
    -- Safety phase: FAILURE when player is dead
    -- -------------------------------------------------------
    local safety_node = Safety.build(bus, nav)
    local bb_dead = make_bb({
        ["module.grind.enabled"] = true,
        ["player.is_dead"] = true,
    })
    T.assert_equal(safety_node:tick(bb_dead), Status.FAILURE, "safety FAILURE when dead")

    -- -------------------------------------------------------
    -- Safety phase: FAILURE when grind disabled
    -- -------------------------------------------------------
    local safety_node2 = Safety.build(bus, nav)
    local bb_disabled2 = make_bb({ ["module.grind.enabled"] = false })
    T.assert_equal(safety_node2:tick(bb_disabled2), Status.FAILURE, "safety FAILURE when disabled")

    -- -------------------------------------------------------
    -- Corpse run phase: FAILURE when alive
    -- -------------------------------------------------------
    local corpse_node = CorpseRun.build(bus, nav)
    local bb_alive = make_bb({
        ["player.is_dead"] = false,
        ["player.is_ghost"] = false,
    })
    T.assert_equal(corpse_node:tick(bb_alive), Status.FAILURE, "corpse_run FAILURE when alive")

    -- -------------------------------------------------------
    -- Pull phase: FAILURE when no target
    -- -------------------------------------------------------
    local pull_node = Pull.build(bb, bus, nav)
    local bb_no_target = make_bb({
        ["module.grind.enabled"] = true,
        ["module.grind.current_target"] = nil,
    })
    T.assert_equal(pull_node:tick(bb_no_target), Status.FAILURE, "pull FAILURE when no target")

    -- -------------------------------------------------------
    -- Acquire phase: FAILURE when grind disabled
    -- -------------------------------------------------------
    local acquire_node = Acquire.build(bb)
    local bb_acq_disabled = make_bb({ ["module.grind.enabled"] = false })
    T.assert_equal(acquire_node:tick(bb_acq_disabled), Status.FAILURE, "acquire FAILURE when disabled")

    -- -------------------------------------------------------
    -- Acquire phase: FAILURE when already has target
    -- -------------------------------------------------------
    local acquire_node2 = Acquire.build(bb)
    local bb_has_target = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.current_target"] = { mock = true },
    })
    T.assert_equal(acquire_node2:tick(bb_has_target), Status.FAILURE, "acquire FAILURE when has target")

    -- -------------------------------------------------------
    -- Loot phase: FAILURE when in combat
    -- -------------------------------------------------------
    local loot_node = Loot.build(bus, nav)
    local bb_loot_combat = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = true,
    })
    T.assert_equal(loot_node:tick(bb_loot_combat), Status.FAILURE, "loot FAILURE when in combat")

    -- -------------------------------------------------------
    -- Vendor phase: builds without error
    -- -------------------------------------------------------
    local vendor_node = Vendor.build(bb, bus, nav)
    T.assert_not_nil(vendor_node, "vendor builds")
    T.assert_equal(vendor_node.name, "vendor_run", "vendor name")

    -- -------------------------------------------------------
    -- Vendor gate: triggers on needs_repair
    -- -------------------------------------------------------
    local vendor_repair = Vendor.build(bb, bus, nav)
    local bb_repair = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 10,
        ["module.grind.needs_repair"] = true,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = {
            get_nearest_vendor = function(_, _, svc)
                if svc == "repair" then
                    return { npc_id = 1, x = 0, y = 0, z = 0, name = "Smith", services = {"sell", "repair"} }
                end
                return nil
            end,
            get_active_profile = function() return nil end,
        },
    })
    -- Tick: gates pass (needs_repair=true), action enters init → traveling
    local r = vendor_repair:tick(bb_repair)
    T.assert_equal(r, Status.RUNNING, "vendor RUNNING when needs_repair triggers gate")
    T.assert_equal(bb_repair:get("module.grind.vendor_state"), "traveling", "vendor init → traveling on repair need")
    -- Clean up
    bb_repair:set("module.grind.vendor_state", nil)
    bb_repair:set("module.grind.vendor_data", nil)

    -- -------------------------------------------------------
    -- Vendor gate: triggers on needs_food when food vendor exists
    -- -------------------------------------------------------
    local vendor_food_gate = Vendor.build(bb, bus, nav)
    local bb_food_gate = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 10,
        ["module.grind.needs_food"] = true,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = {
            get_nearest_vendor = function(_, _, svc)
                if svc == "food" then
                    return { npc_id = 2, x = 0, y = 0, z = 0, name = "Cook", services = {"sell", "food"} }
                end
                if svc == "sell" then
                    return { npc_id = 2, x = 0, y = 0, z = 0, name = "Cook", services = {"sell", "food"} }
                end
                return nil
            end,
            get_active_profile = function() return nil end,
        },
    })
    local r2 = vendor_food_gate:tick(bb_food_gate)
    T.assert_equal(r2, Status.RUNNING, "vendor RUNNING when needs_food triggers gate")
    -- Clean up
    bb_food_gate:set("module.grind.vendor_state", nil)
    bb_food_gate:set("module.grind.vendor_data", nil)

    -- -------------------------------------------------------
    -- Vendor gate: FAILURE when bags not full and no repair/food/water need
    -- -------------------------------------------------------
    local vendor_no_need = Vendor.build(bb, bus, nav)
    local bb_no_need = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 10,
    })
    T.assert_equal(vendor_no_need:tick(bb_no_need), Status.FAILURE, "vendor FAILURE when no vendor need")

    -- -------------------------------------------------------
    -- Vendor state transitions:
    -- waiting_window → repairing → selling → selling_wait → buying_food → buying_water → done
    -- -------------------------------------------------------
    -- We test state transitions by directly manipulating vendor_state
    -- and ticking the full tree (gates must pass each tick)
    local mock_pm = {
        get_nearest_vendor = function(_, _, svc)
            if svc == "sell" then
                return { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell", "repair", "food"} }
            end
            return nil
        end,
        get_active_profile = function() return nil end,
    }

    -- Test: repairing state skips to selling when vendor has no repair service
    local vendor_st = Vendor.build(bb, bus, nav)
    local bb_st = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "repairing",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell"} },
        ["module.grind.needs_repair"] = false,
    })
    vendor_st:tick(bb_st)
    T.assert_equal(bb_st:get("module.grind.vendor_state"), "selling", "repairing → selling when no repair needed")

    -- Test: repairing state transitions to selling when repair IS needed and vendor has service
    local vendor_st2 = Vendor.build(bb, bus, nav)
    local repair_reset_called = false
    local bb_st2 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "repairing",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell", "repair", "food"} },
        ["module.grind.needs_repair"] = true,
        ["module.grind.durability_tracker"] = { reset = function() repair_reset_called = true end },
    })
    vendor_st2:tick(bb_st2)
    T.assert_equal(bb_st2:get("module.grind.vendor_state"), "selling", "repairing → selling after repair")
    T.assert_true(repair_reset_called, "durability tracker reset called after repair")

    -- Test: buying_food skips to buying_water when vendor has no food service
    local vendor_st3 = Vendor.build(bb, bus, nav)
    local bb_st3 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "buying_food",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell"} },
        ["module.grind.needs_food"] = true,
    })
    vendor_st3:tick(bb_st3)
    T.assert_equal(bb_st3:get("module.grind.vendor_state"), "buying_water", "buying_food → buying_water when no food service")

    -- Test: buying_food transitions to buying_water when food service exists (no core to actually buy)
    local vendor_st4 = Vendor.build(bb, bus, nav)
    local bb_st4 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "buying_food",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell", "repair", "food"} },
        ["module.grind.needs_food"] = true,
        ["module.grind.food_count"] = 5,
    })
    vendor_st4:tick(bb_st4)
    T.assert_equal(bb_st4:get("module.grind.vendor_state"), "buying_water", "buying_food → buying_water after food buy attempt")

    -- Test: buying_water skips to done when no food service
    local vendor_st5 = Vendor.build(bb, bus, nav)
    local bb_st5 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "buying_water",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell"} },
        ["module.grind.needs_water"] = true,
    })
    vendor_st5:tick(bb_st5)
    T.assert_equal(bb_st5:get("module.grind.vendor_state"), "done", "buying_water → done when no food service")

    -- Test: buying_water transitions to done when food service exists
    local vendor_st6 = Vendor.build(bb, bus, nav)
    local bb_st6 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "buying_water",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell", "repair", "food"} },
        ["module.grind.needs_water"] = true,
        ["module.grind.water_count"] = 10,
    })
    vendor_st6:tick(bb_st6)
    T.assert_equal(bb_st6:get("module.grind.vendor_state"), "done", "buying_water → done after water buy attempt")

    -- Test: done state cleans up and returns SUCCESS
    local vendor_st7 = Vendor.build(bb, bus, nav)
    local bb_st7 = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = false,
        ["module.grind.bag_free_slots"] = 0,
        ["player.position"] = { x = 0, y = 0, z = 0 },
        ["module.grind.profile_manager"] = mock_pm,
        ["module.grind.vendor_state"] = "done",
        ["module.grind.vendor_data"] = { npc_id = 3, x = 0, y = 0, z = 0, name = "Trader", services = {"sell"} },
    })
    local r7 = vendor_st7:tick(bb_st7)
    T.assert_equal(r7, Status.SUCCESS, "vendor done state returns SUCCESS")
    T.assert_equal(bb_st7:get("module.grind.vendor_state"), nil, "vendor_state cleaned up after done")
    T.assert_equal(bb_st7:get("module.grind.vendor_data"), nil, "vendor_data cleaned up after done")

    -- Restore original core global
    _G.core = saved_core
end

return M
