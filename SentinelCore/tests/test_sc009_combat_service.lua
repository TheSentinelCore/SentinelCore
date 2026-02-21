local T = require("tests/TestUtil")
local ErrorCodes = require("events/ErrorCodes")

local function run()
    local player = T.mock_object({ position = { x = 0, y = 0, z = 0 } })
    local target = T.mock_object({
        name = "Target",
        position = { x = 5, y = 0, z = 0 },
        health = 100,
        max_health = 100,
    })

    local env = T.install_core_stub({
        object_manager = {
            get_local_player = function() return player end,
            get_visible_objects = function() return { target } end,
        },
    })

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatService = require("services/CombatService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    bb:set("player.position", player:get_position())

    local nav = { move_to = function(_, _, cb) if cb then cb(true, nil, nil) end end }
    local targeting = { get_target = function() return target end }
    local rotation = {
        get_pull_profile = function() return { pull_spell_id = 20271, max_pull_range = 30 } end,
        tick_once = function() return true, nil end,
    }

    local combat = CombatService:new(bus, bb, nav, targeting, rotation, {
        combat_timeout = 15,
        pull_timeout = 5,
    })

    local ok, err = combat:start(target)
    T.assert_true(ok == true, "combat start failed")

    local u1 = combat:update()
    T.assert_true(u1 == true, "combat update should run")
    T.assert_eq(combat:get_state(), "pull", "combat service should remain in pull state until pull actually engages combat")

    target._in_combat = true
    local u1b = combat:update()
    T.assert_true(u1b == true, "combat update should transition after pull engages")
    T.assert_eq(combat:get_state(), "combat", "combat service should switch to combat state once target enters combat")

    target._dead = true
    local u2 = combat:update()
    T.assert_true(u2 == true and combat:get_state() == "idle", "combat should exit on kill")
    T.assert_true(bb:get("loot.pending_target") == target, "combat kill should hand off loot target")

    local stale_target = {
        is_valid = function()
            error("Invalid game object!")
        end,
        is_dead = function()
            error("Invalid game object!")
        end,
    }
    combat._state = "combat"
    combat._active_target = stale_target
    combat._started_at = (core and core.time and core.time()) or 0
    local safe_ok, update_ok, update_err = pcall(function()
        return combat:update()
    end)
    T.assert_true(safe_ok == true, "combat update must not throw on stale object")
    T.assert_true(update_ok == false and update_err == ErrorCodes.TARGET_LOST,
        "stale object should fail closed with TARGET_LOST")

    return {
        sc009_combat_loop = true,
        sc009_combat_stale_target_guard = true,
    }
end

return { run = run }
