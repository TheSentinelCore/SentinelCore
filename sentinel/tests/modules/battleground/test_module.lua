local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local BattlegroundModule = require("modules/battleground/module")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local nav_calls = {}
    local handoff_requests = 0
    local nav = {
        move_to = function(_self, target, opts)
            nav_calls[#nav_calls + 1] = { command = "move_to", target = target, opts = opts }
        end,
        follow_path = function(_self, nodes, opts)
            nav_calls[#nav_calls + 1] = { command = "follow_path", nodes = nodes, opts = opts }
        end,
        plan_route = function(_self, nodes, opts)
            nav_calls[#nav_calls + 1] = { command = "plan_route", nodes = nodes, opts = opts }
        end,
        stop = function() end,
        poll = function()
            return "idle", { state = "idle" }
        end,
    }
    bus:subscribe("bg:combat_handoff_requested", function()
        handoff_requests = handoff_requests + 1
    end)

    bb:set("system.now_ms", 1000)
    bb:set("system.map_id", 1459)
    bb:set("system.map_name", "Alterac Valley")
    bb:set("system.instance_id", 0)
    bb:set("system.instance_name", "")
    bb:set("bg.sensor.in_bg", true)
    bb:set("player.position", { x = 873.00, y = -491.28, z = 96.54 })
    bb:set("player.health_pct", 1.0)
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.ally_count_30yd", 2)
    bb:set("nav.owner", nil)
    bb:set("nav.command", nil)

    local bg = BattlegroundModule:new(bus, bb, nav)
    bg:initialize()
    bb:set("module.bg.auto_queue", false)
    bb:set("module.bg.post_game_auto_leave", false)
    bb:set("module.bg.auto_mount", false)
    bg:update(bb)

    T.assert_true(bg:is_active())
    T.assert_equal(bg:get_current_bg_key(), "AV")
    T.assert_equal(bb:get("bg.detect_reason"), "map_name")
    T.assert_equal(bb:get("bg.state"), "BOOTSTRAP")
    T.assert_equal(bb:get("bg.nav_authority"), "spawn_bootstrap_route")
    T.assert_equal(bb:get("nav.command"), "follow_path")
    T.assert_equal(bb:get("bg.nav_map_id"), 30)
    T.assert_equal(bb:get("bg.strategy_id"), "balanced")
    T.assert_not_nil(bb:get("bg.selected_objective_id"))
    T.assert_equal(nav_calls[1].command, "follow_path")
    T.assert_equal(nav_calls[1].opts.map_id, 30)
    T.assert_equal(handoff_requests, 1)

    bb:set("system.now_ms", 1400)
    bg:update(bb)
    T.assert_false(bg._combat_paused)
    T.assert_equal(bb:get("nav.command"), "follow_path")

    local old_core = _G.core
    local eots_nav_calls = {}
    local eots_nav = {
        move_to = function(_self, target, opts)
            eots_nav_calls[#eots_nav_calls + 1] = { command = "move_to", target = target, opts = opts }
        end,
        follow_path = function(_self, nodes, opts)
            eots_nav_calls[#eots_nav_calls + 1] = { command = "follow_path", nodes = nodes, opts = opts }
        end,
        plan_route = function() end,
        stop = function() end,
        poll = function()
            return "idle", { state = "idle" }
        end,
    }

    local bb2 = Blackboard:new()
    local bus2 = EventBus:new()
    _G.core = {
        object_manager = {
            get_visible_objects = function()
                return {
                    {
                        get_name = function()
                            return "Forcefield 000"
                        end,
                        get_position = function()
                            return { x = 2527.60, y = 1596.91, z = 1262.13 }
                        end,
                    },
                }
            end,
        },
    }

    bb2:set("system.now_ms", 1000)
    bb2:set("system.map_id", 1956)
    bb2:set("system.map_name", "Eye of the Storm")
    bb2:set("system.instance_id", 566)
    bb2:set("system.instance_name", "Eye of the Storm")
    bb2:set("bg.sensor.in_bg", true)
    bb2:set("bg.sensor.in_prep", true)
    bb2:set("bg.sensor.battlefield_state", 2)
    bb2:set("player.position", { x = 2523.69, y = 1596.60, z = 1269.35 })
    bb2:set("player.health_pct", 1.0)
    bb2:set("combat.enemy_count_10yd", 0)
    bb2:set("combat.ally_count_30yd", 0)
    bb2:set("bg.retreat_requested", true)
    bb2:set("player.object", {
        is_mounted = function()
            return false
        end,
    })

    local eots_bg = BattlegroundModule:new(bus2, bb2, eots_nav)
    eots_bg:initialize()
    bb2:set("module.bg.auto_mount", false)
    bb2:set("module.bg.auto_queue", false)
    bb2:set("module.bg.post_game_auto_leave", false)
    eots_bg:update(bb2)
    T.assert_equal(bb2:get("bg.prep_gate_reason"), "eots_spawn_barrier_seen")
    T.assert_equal(bb2:get("bg.state"), "PRE_GAME")
    T.assert_false(bb2:get("bg.retreat_requested", false) == true)
    T.assert_equal(bb2:get("nav.command"), nil)
    T.assert_equal(#eots_nav_calls, 0)

    bb2:set("system.now_ms", 1200)
    bb2:set("bg.sensor.in_prep", false)
    bb2:set("bg.sensor.battlefield_state", 3)
    eots_bg:update(bb2)
    T.assert_equal(bb2:get("bg.prep_gate_reason"), "eots_spawn_barrier_seen")
    T.assert_false(bb2:get("bg.prep_gate_released", false) == true)
    T.assert_equal(#eots_nav_calls, 0)

    bb2:set("system.now_ms", 1500)
    bb2:set("player.position", { x = 2498.90, y = 1580.60, z = 1255.10 })
    _G.core.object_manager.get_visible_objects = function()
        return {}
    end
    eots_bg:update(bb2)
    T.assert_equal(bb2:get("bg.prep_gate_reason"), "release_grace")
    T.assert_true(bb2:get("bg.prep_gate_released", false) == true)
    T.assert_equal(#eots_nav_calls, 0)

    bb2:set("system.now_ms", 1900)
    eots_bg:update(bb2)
    T.assert_equal(bb2:get("bg.nav_map_id"), 566)
    T.assert_equal(bb2:get("bg.prep_gate_reason"), "none")
    T.assert_true(bb2:get("bg.selected_objective_id") ~= "CENTER_FLAG")
    T.assert_true(
        math.abs(bb2:get("bg.objective_anchor").x - 2282.12) < 0.01
        or math.abs(bb2:get("bg.objective_anchor").x - 2301.01) < 0.01
    )
    T.assert_not_nil(bb2:get("nav.command"))
    T.assert_equal(eots_nav_calls[1].opts.map_id, 566)
    T.assert_equal(eots_nav_calls[1].command, "follow_path")
    T.assert_true(math.abs(eots_nav_calls[1].nodes[1].x - 2523.69) > 0.1)

    _G.core = old_core
end

return M
