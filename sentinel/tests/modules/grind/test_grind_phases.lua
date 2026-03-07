local Safety = require("modules/grind/phases/safety")
local CorpseRun = require("modules/grind/phases/corpse_run")
local Rest = require("modules/grind/phases/rest")
local Loot = require("modules/grind/phases/loot")
local Combat = require("modules/grind/phases/combat")
local Pull = require("modules/grind/phases/pull")
local Acquire = require("modules/grind/phases/acquire")
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
    local bus = make_bus()
    local nav = make_nav()
    local bb = make_bb()

    -- -------------------------------------------------------
    -- Each phase builds without error and has correct name
    -- -------------------------------------------------------
    local safety = Safety.build(bus, nav)
    T.assert_not_nil(safety, "safety builds")
    T.assert_equal(safety.name, "safety_flee", "safety name")

    local corpse = CorpseRun.build(bus, nav)
    T.assert_not_nil(corpse, "corpse_run builds")
    T.assert_equal(corpse.name, "corpse_run", "corpse_run name")

    local rest = Rest.build(bus)
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

    local acquire = Acquire.build(bb, nav)
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
    local rest_node = Rest.build(bus)
    local bb_disabled = make_bb({ ["module.grind.enabled"] = false })
    T.assert_equal(rest_node:tick(bb_disabled), Status.FAILURE, "rest FAILURE when grind disabled")

    -- -------------------------------------------------------
    -- Rest phase: FAILURE when in combat
    -- -------------------------------------------------------
    local rest_node2 = Rest.build(bus)
    local bb_in_combat = make_bb({
        ["module.grind.enabled"] = true,
        ["player.in_combat"] = true,
    })
    T.assert_equal(rest_node2:tick(bb_in_combat), Status.FAILURE, "rest FAILURE when in combat")

    -- -------------------------------------------------------
    -- Rest phase: RUNNING when HP is low and needs recovery
    -- -------------------------------------------------------
    local rest_node3 = Rest.build(bus)
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
    local rest_node4 = Rest.build(bus)
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
    local acquire_node = Acquire.build(bb, nav)
    local bb_acq_disabled = make_bb({ ["module.grind.enabled"] = false })
    T.assert_equal(acquire_node:tick(bb_acq_disabled), Status.FAILURE, "acquire FAILURE when disabled")

    -- -------------------------------------------------------
    -- Acquire phase: FAILURE when already has target
    -- -------------------------------------------------------
    local acquire_node2 = Acquire.build(bb, nav)
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
end

return M
