local T = require("tests/TestUtil")

return { run = function()
    local TacticalPlanner = require("ai/TacticalPlanner")
    local Tactic = require("ai/Tactic")
    local BT = require("ai/BehaviorTree")

    -- Mock deps
    local deps = {}
    local phase_ticks = {}

    -- Tactic with 3 phases: gather → burst → cleanup
    local tactic = Tactic:new({
        name = "test",
        preconditions = function() return true end,
        utility = function() return 1.0 end,
        phases = {
            {
                name = "gather",
                enter_if = function(ctx) return ctx.pack_count < 3 end,
                tick = function(ctx, d)
                    phase_ticks.gather = (phase_ticks.gather or 0) + 1
                    return BT.Status.RUNNING
                end,
                exit_if = function(ctx) return ctx.pack_count >= 3 end,
            },
            {
                name = "burst",
                enter_if = function(ctx) return ctx.pack_count >= 3 and ctx.in_combat end,
                tick = function(ctx, d)
                    phase_ticks.burst = (phase_ticks.burst or 0) + 1
                    return BT.Status.RUNNING
                end,
                exit_if = function(ctx) return ctx.pack_count < 3 end,
            },
            {
                name = "cleanup",
                enter_if = function(ctx) return ctx.pack_count > 0 and ctx.pack_count < 3 end,
                tick = function(ctx, d)
                    phase_ticks.cleanup = (phase_ticks.cleanup or 0) + 1
                    return BT.Status.SUCCESS
                end,
                exit_if = function(ctx) return ctx.pack_count == 0 end,
            },
        },
    })

    local planner = TacticalPlanner:new()

    -- 1. Set tactic
    planner:set_tactic(tactic)
    T.assert_eq(planner:get_current_phase_name(), nil, "no phase before first tick")

    -- 2. Tick with pack_count=0 → should enter "gather"
    local ctx1 = { pack_count = 0, in_combat = false }
    local status1 = planner:tick(ctx1, deps)
    T.assert_eq(planner:get_current_phase_name(), "gather", "entered gather phase")
    T.assert_eq(status1, BT.Status.RUNNING, "gather returns RUNNING")
    T.assert_eq(phase_ticks.gather, 1, "gather ticked once")

    -- 3. Tick again with pack_count=3 → exit gather, enter burst
    local ctx2 = { pack_count = 3, in_combat = true }
    local status2 = planner:tick(ctx2, deps)
    T.assert_eq(planner:get_current_phase_name(), "burst", "transitioned to burst")
    T.assert_eq(phase_ticks.burst, 1, "burst ticked once")

    -- 4. Tick with pack_count=1 → exit burst (count dropped), enter cleanup
    local ctx3 = { pack_count = 1, in_combat = true }
    local status3 = planner:tick(ctx3, deps)
    T.assert_eq(planner:get_current_phase_name(), "cleanup", "transitioned to cleanup")
    T.assert_eq(status3, BT.Status.SUCCESS, "cleanup returns SUCCESS")

    -- 5. Reset clears phase
    planner:reset()
    T.assert_eq(planner:get_current_phase_name(), nil, "phase cleared after reset")

    -- 6. Re-entry after reset picks up eligible phase
    planner:set_tactic(tactic)
    local ctx4 = { pack_count = 0, in_combat = true }
    local status4 = planner:tick(ctx4, deps)
    T.assert_eq(planner:get_current_phase_name(), "gather", "gather re-entered")
    T.assert_eq(status4, BT.Status.RUNNING, "re-entered gather returns RUNNING")

    -- 7. Tactic with no phases → FAILURE
    local empty_tactic = Tactic:new({ name = "empty", phases = {} })
    planner:set_tactic(empty_tactic)
    local status5 = planner:tick({}, deps)
    T.assert_eq(status5, BT.Status.FAILURE, "no phases returns FAILURE")

    -- 8. No phase eligible (all enter_if false) → FAILURE
    planner:set_tactic(tactic)
    local ctx_none = { pack_count = 3, in_combat = false }
    local status_none = planner:tick(ctx_none, deps)
    T.assert_eq(status_none, BT.Status.FAILURE, "no eligible phase returns FAILURE")
    T.assert_eq(planner:get_current_phase_name(), nil, "no phase active when none eligible")

    -- 9. Erroring enter_if is skipped, next phase tried
    local err_tactic = Tactic:new({
        name = "erroring",
        phases = {
            {
                name = "broken",
                enter_if = function() error("boom") end,
                tick = function() return BT.Status.RUNNING end,
                exit_if = function() return false end,
            },
            {
                name = "fallback",
                enter_if = function() return true end,
                tick = function() return BT.Status.SUCCESS end,
                exit_if = function() return false end,
            },
        },
    })
    planner:set_tactic(err_tactic)
    local err_status = planner:tick({}, deps)
    T.assert_eq(planner:get_current_phase_name(), "fallback", "erroring phase skipped")
    T.assert_eq(err_status, BT.Status.SUCCESS, "fallback phase ticked")

    -- 10. Erroring tick returns FAILURE
    local crash_tactic = Tactic:new({
        name = "crash_tick",
        phases = {
            {
                name = "crasher",
                enter_if = function() return true end,
                tick = function() error("tick boom") end,
                exit_if = function() return false end,
            },
        },
    })
    planner:set_tactic(crash_tactic)
    T.assert_eq(planner:tick({}, deps), BT.Status.FAILURE, "erroring tick returns FAILURE")

    return true
end }
