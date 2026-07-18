local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local QueueManager = require("modules/battleground/queue_manager")
local T = require("tests/test_util")

local M = {}

local function seed_queue_settings(bb)
    bb:set("module.bg.enabled", true)
    bb:set("module.bg.auto_queue", true)
    bb:set("module.bg.queue_selection", "WSG")
    bb:set("module.bg.queue_join_interval_s", 0)
    bb:set("module.bg.queue_accept_delay_min_s", 0)
    bb:set("module.bg.queue_accept_delay_max_s", 0)
    bb:set("module.bg.queue_accept_mode", "strict_pvp")
    bb:set("module.bg.queue_dependencies_policy", "accept_anyway")
    bb:set("module.bg.queue_accept_retry_interval_s", 0)
    bb:set("module.bg.queue_accept_max_attempts", 3)
    bb:set("module.bg.queue_accept_confirm_timeout_s", 1)
    bb:set("module.bg.queue_join_confirm_timeout_s", 1)
    bb:set("module.bg.queue_active_without_bg_timeout_s", 1)
end

local function seed_sensor(bb, opts)
    opts = opts or {}
    bb:set("system.now_ms", opts.now_ms or 0)
    bb:set("bg.sensor.in_bg", opts.in_bg == true)
    bb:set("bg.sensor.queue_popup", opts.queue_popup == true)
    bb:set("bg.sensor.queue_popup_kind", opts.queue_popup_kind or "unknown")
    bb:set("bg.sensor.queue_popup_source", opts.queue_popup_source or "none")
    bb:set("bg.sensor.queue_popup_confidence", opts.queue_popup_confidence or "none")
    bb:set("bg.sensor.queue_popup_seq", opts.queue_popup_seq or 0)
    bb:set("bg.sensor.queue_popup_age_ms", opts.queue_popup_age_ms or 0)
    bb:set("bg.sensor.queue_popup_slot_idx", opts.queue_popup_slot_idx)
    bb:set("bg.sensor.queue_status_slots", opts.queue_status_slots or { "none", "none", "none" })
    bb:set("bg.sensor.queue_status_summary", opts.queue_status_summary or "none|none|none")
end

function M.run()
    local join_calls = 0
    local join_args = {}
    core = {
        input = {
            join_battlefield = function(...)
                join_calls = join_calls + 1
                join_args[#join_args + 1] = { ... }
                return true
            end,
            accept_battlefield_port = function()
                return true
            end,
        },
    }

    local bb = Blackboard:new()
    seed_queue_settings(bb)
    seed_sensor(bb, {
        now_ms = 1000,
    })

    local manager = QueueManager:new(EventBus:new(), bb)
    manager._random = function() return 0 end
    manager._izi = {
        queue_accept = function()
            return true
        end,
    }
    manager._izi_resolved = true

    manager:update()
    T.assert_equal(join_calls, 1)
    T.assert_true(bb:get("bg.queue.join_dispatched", false))
    T.assert_equal(bb:get("bg.queue.last_join_bg_id"), 2)
    T.assert_equal(join_args[1][1], 2)

    seed_sensor(bb, {
        now_ms = 1200,
        queue_popup = true,
        queue_popup_kind = "pvp",
        queue_popup_source = "queue_popup_info",
        queue_popup_confidence = "high",
        queue_popup_seq = 1,
        queue_popup_slot_idx = 2,
        queue_status_slots = { "queued", "confirm", "none" },
        queue_status_summary = "queued|confirm|none",
    })
    manager:update()
    T.assert_true(bb:get("bg.queue.join_confirmed", false))
    T.assert_true(bb:get("bg.queue.accept_dispatched", false))

    seed_sensor(bb, {
        now_ms = 1400,
        queue_popup = false,
        queue_status_slots = { "none", "none", "none" },
        queue_status_summary = "none|none|none",
    })
    manager:update()
    T.assert_true(bb:get("bg.queue.accept_confirmed", false))

    local infer_bb = Blackboard:new()
    seed_queue_settings(infer_bb)
    seed_sensor(infer_bb, {
        now_ms = 3000,
        queue_popup = false,
        queue_status_slots = { "confirm", "none", "none" },
        queue_status_summary = "confirm|none|none",
    })

    local infer_manager = QueueManager:new(EventBus:new(), infer_bb)
    infer_manager._random = function() return 0 end
    infer_manager._izi = {
        queue_accept = function()
            return true
        end,
    }
    infer_manager._izi_resolved = true

    infer_manager:update()
    T.assert_true(infer_bb:get("bg.queue.accept_dispatched", false))

    seed_sensor(infer_bb, {
        now_ms = 3200,
        queue_popup = false,
        queue_status_slots = { "none", "none", "none" },
        queue_status_summary = "none|none|none",
    })
    infer_manager:update()
    T.assert_equal(infer_bb:get("bg.queue.accept_confirm_reason"), "status_not_confirm")

    local failed_join_bb = Blackboard:new()
    seed_queue_settings(failed_join_bb)
    seed_sensor(failed_join_bb, {
        now_ms = 5000,
    })
    core = {
        input = {
            join_battlefield = function()
                return false
            end,
        },
    }
    local failed_join_manager = QueueManager:new(EventBus:new(), failed_join_bb)
    failed_join_manager:update()
    T.assert_false(failed_join_bb:get("bg.queue.join_dispatched", false))
end

return M
