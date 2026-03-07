local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local LeaveManager = require("modules/battleground/leave_manager")
local T = require("tests/test_util")

local M = {}

local function seed_leave_settings(bb)
    bb:set("module.bg.enabled", true)
    bb:set("module.bg.post_game_auto_leave", true)
    bb:set("module.bg.post_game_state5_streak_required", 1)
    bb:set("module.bg.post_game_leave_initial_delay_s", 0)
    bb:set("module.bg.post_game_leave_retry_interval_s", 0)
    bb:set("module.bg.post_game_leave_max_attempts", 2)
end

local function seed_sensor(bb, opts)
    opts = opts or {}
    bb:set("system.now_ms", opts.now_ms or 0)
    bb:set("system.map_id", opts.map_id or 489)
    bb:set("bg.sensor.in_bg", opts.in_bg == true)
    bb:set("bg.sensor.battlefield_state", opts.battlefield_state)
    bb:set("bg.sensor.battlefield_state_streak_5", opts.battlefield_state_streak_5 or 0)
    bb:set("bg.sensor.queue_status_summary", opts.queue_status_summary or "unknown|unknown|unknown")
end

function M.run()
    local leave_calls = 0
    core = {
        input = {
            leave_battlefield = function()
                leave_calls = leave_calls + 1
                return true
            end,
        },
    }

    local bb = Blackboard:new()
    seed_leave_settings(bb)
    seed_sensor(bb, {
        now_ms = 1000,
        in_bg = true,
        battlefield_state = 5,
        battlefield_state_streak_5 = 1,
        queue_status_summary = "active|none|none",
    })

    local manager = LeaveManager:new(EventBus:new(), bb)
    manager:update()
    T.assert_true(bb:get("bg.leave.gate_open", false))
    T.assert_equal(bb:get("bg.leave.attempts"), 1)
    T.assert_equal(leave_calls, 1)
    T.assert_true(bb:get("bg.leave.api_present", false))

    seed_sensor(bb, {
        now_ms = 1200,
        in_bg = false,
        map_id = 0,
        battlefield_state = nil,
        battlefield_state_streak_5 = 0,
        queue_status_summary = "none|none|none",
    })
    manager:update()
    T.assert_true(bb:get("bg.leave.confirmed", false))
    T.assert_equal(bb:get("bg.leave.confirm_reason"), "sensor_in_bg_false")

    local missing_bb = Blackboard:new()
    seed_leave_settings(missing_bb)
    seed_sensor(missing_bb, {
        now_ms = 2000,
        in_bg = true,
        battlefield_state = 5,
        battlefield_state_streak_5 = 1,
        queue_status_summary = "active|none|none",
    })

    core = {
        input = {},
    }

    local missing_manager = LeaveManager:new(EventBus:new(), missing_bb)
    missing_manager:update()
    T.assert_false(missing_bb:get("bg.leave.api_present", true))
    T.assert_equal(missing_bb:get("bg.leave.wait_reason"), "api_missing")

    local failed_bb = Blackboard:new()
    seed_leave_settings(failed_bb)
    seed_sensor(failed_bb, {
        now_ms = 3000,
        in_bg = true,
        battlefield_state = 5,
        battlefield_state_streak_5 = 1,
        queue_status_summary = "active|none|none",
    })
    core = {
        input = {
            leave_battlefield = function()
                return false
            end,
        },
    }
    local failed_manager = LeaveManager:new(EventBus:new(), failed_bb)
    failed_manager:update()
    T.assert_false(failed_bb:get("bg.leave.last_attempt_ok", true))
end

return M
