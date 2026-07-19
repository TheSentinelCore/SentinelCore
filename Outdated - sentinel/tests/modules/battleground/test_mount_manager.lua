local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local MountManager = require("modules/battleground/mount_manager")
local T = require("tests/test_util")

local M = {}

function M.run()
    local mounted = false
    local use_item_calls = 0
    local nav_stop_calls = 0
    core = {
        input = {
            use_item = function(item_id)
                use_item_calls = use_item_calls + 1
                return item_id == 184865
            end,
        },
    }

    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)
    bb:set("module.bg.enabled", true)
    bb:set("module.bg.auto_mount", true)
    bb:set("module.bg.preferred_mount_id", 184865)
    bb:set("module.bg.mount_distance_threshold", 45)
    bb:set("module.bg.mount_require_outdoors", true)
    bb:set("module.bg.mount_micro_stop_for_cast_s", 0.45)
    bb:set("module.bg.mount_settle_before_cast_s", 0.25)
    bb:set("module.bg.mount_no_cast_grace_s", 3.0)
    bb:set("module.bg.player_threat_scan_radius", 0)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.is_dead", false)
    bb:set("player.is_ghost", false)
    bb:set("player.in_combat", false)
    bb:set("player.is_outdoors", true)
    bb:set("player.object", {
        is_mounted = function() return mounted end,
    })

    local nav = {
        stop = function()
            nav_stop_calls = nav_stop_calls + 1
        end,
    }

    local manager = MountManager:new(EventBus:new(), bb, nav)
    manager:initialize()
    local state = manager:update({ x = 100, y = 0, z = 0 })
    T.assert_equal(state, "mount_pending")
    T.assert_equal(use_item_calls, 0)
    T.assert_equal(nav_stop_calls, 1)
    T.assert_equal(bb:get("bg.mount.last_attempt_method"), nil)

    bb:set("system.now_ms", 1500)
    state = manager:update({ x = 100, y = 0, z = 0 })
    T.assert_equal(state, "mount_requested")
    T.assert_equal(use_item_calls, 1)
    T.assert_equal(nav_stop_calls, 1)
    T.assert_equal(bb:get("bg.mount.last_attempt_method"), "use_item")
    T.assert_equal(bb:get("bg.mount.selected_mount_id"), 184865)

    mounted = true
    bb:set("system.now_ms", 2000)
    state = manager:update({ x = 100, y = 0, z = 0 })
    T.assert_equal(state, "mounted")
end

return M
