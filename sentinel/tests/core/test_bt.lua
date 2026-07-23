local Blackboard = require("core/blackboard")
local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)

    local seq = Runner:new(BT.sequence("seq", {
        BT.condition("true", function() return true end),
        BT.action("ok", function() return true end),
    }))
    T.assert_equal(seq:tick(bb), "SUCCESS")

    local sel = Runner:new(BT.selector("sel", {
        BT.condition("false", function() return false end),
        BT.action("fallback", function() return true end),
    }))
    T.assert_equal(sel:tick(bb), "SUCCESS")

    local cooldown = Runner:new(BT.cooldown("cd", 500, BT.action("once", function() return true end), { key = "test_cd" }))
    T.assert_equal(cooldown:tick(bb), "SUCCESS")
    T.assert_equal(cooldown:tick(bb), "FAILURE")
    bb:set("system.now_ms", 1600)
    T.assert_equal(cooldown:tick(bb), "SUCCESS")

    local attempts = Runner:new(BT.max_attempts("tries", 2, BT.action("fail", function() return false end), { key = "tries" }))
    T.assert_equal(attempts:tick(bb), "FAILURE")
    T.assert_equal(attempts:tick(bb), "FAILURE")
    T.assert_equal(attempts:tick(bb), "FAILURE")

    -- PrioritySelector: always evaluates from child 1
    local ps_call_log = {}
    local ps = Runner:new(BT.priority_selector("ps", {
        BT.action("high", function()
            ps_call_log[#ps_call_log + 1] = "high"
            return "FAILURE"
        end),
        BT.action("mid", function()
            ps_call_log[#ps_call_log + 1] = "mid"
            return "RUNNING"
        end),
        BT.action("low", function()
            ps_call_log[#ps_call_log + 1] = "low"
            return "FAILURE"
        end),
    }))

    -- First tick: high fails, mid returns RUNNING
    T.assert_equal(ps:tick(bb), "RUNNING")
    T.assert_equal(#ps_call_log, 2, "ps tick 1: evaluated high and mid")
    T.assert_equal(ps_call_log[1], "high")
    T.assert_equal(ps_call_log[2], "mid")

    -- Second tick: should re-evaluate from child 1 (high), not resume at mid
    ps_call_log = {}
    T.assert_equal(ps:tick(bb), "RUNNING")
    T.assert_equal(#ps_call_log, 2, "ps tick 2: re-evaluated from child 1")
    T.assert_equal(ps_call_log[1], "high")
    T.assert_equal(ps_call_log[2], "mid")

    -- PrioritySelector: high-priority preemption
    local preempt_state = { high_active = false }
    local ps2 = Runner:new(BT.priority_selector("ps2", {
        BT.action("urgent", function()
            if preempt_state.high_active then return "SUCCESS" end
            return "FAILURE"
        end),
        BT.action("normal", function()
            return "RUNNING"
        end),
    }))

    -- Tick 1: urgent fails, normal runs
    T.assert_equal(ps2:tick(bb), "RUNNING")

    -- Tick 2: urgent becomes active, preempts normal
    preempt_state.high_active = true
    T.assert_equal(ps2:tick(bb), "SUCCESS")

    -- C8: Sequence:new's construction-time contract check.
    -- Condition-first sequence (the shipped pattern) — no violation.
    local guarded = BT.sequence("guarded", {
        BT.condition("cond", function() return true end),
        BT.action("act", function() return "SUCCESS" end),
    })
    T.assert_false(guarded._contract_violation, "condition-first sequence: no contract violation")

    -- Nested-sequence-of-conditions guard (priority_builder.lua's compound-AND
    -- pattern) is also accepted — it never returns RUNNING.
    local compound_guard = BT.sequence("guarded_compound", {
        BT.sequence("conds", {
            BT.condition("c1", function() return true end),
            BT.condition("c2", function() return true end),
        }),
        BT.action("act", function() return "SUCCESS" end),
    })
    T.assert_false(compound_guard._contract_violation, "compound-AND condition guard: no contract violation")

    -- Action-first sequence with 2+ children violates the contract (flagged,
    -- not thrown — see composites.lua's Sequence:new doc comment).
    local unguarded = BT.sequence("unguarded", {
        BT.action("act1", function() return "RUNNING" end),
        BT.action("act2", function() return "SUCCESS" end),
    })
    T.assert_true(unguarded._contract_violation, "action-first sequence: contract violation flagged")

    -- A single-child sequence never re-ticks a guard, so the contract doesn't apply.
    local single_child = BT.sequence("single", {
        BT.action("act", function() return "SUCCESS" end),
    })
    T.assert_false(single_child._contract_violation, "single-child sequence: contract does not apply")
end

return M
