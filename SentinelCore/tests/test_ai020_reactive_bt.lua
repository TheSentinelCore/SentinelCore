local M = {}

function M.run()
    local BT = require("ai/BehaviorTree")
    local S = BT.Status

    -- Helper: action that returns a configurable status
    local function make_action(name, status_ref)
        return BT.Action:new(name, function() return status_ref[1] end)
    end

    local function make_condition(name, result_ref)
        return BT.Condition:new(name, function() return result_ref[1] end)
    end

    -- Track resets
    local function make_resettable_action(name, status_ref, reset_count)
        local node = BT.Action:new(name, function() return status_ref[1] end)
        local orig_reset = node.reset
        node.reset = function(self)
            reset_count[1] = reset_count[1] + 1
            if orig_reset then orig_reset(self) end
        end
        return node
    end

    ----------------------------------------------------------------
    -- ReactiveSequence tests
    ----------------------------------------------------------------

    -- Test 1: Gate re-evaluation. Condition passes tick 1, action RUNNING.
    -- Tick 2: condition fails → sequence returns FAILURE (not RUNNING).
    local gate = { true }
    local action_status = { S.RUNNING }
    local rs = BT.ReactiveSequence:new("test_rs", {
        make_condition("gate", gate),
        make_action("act", action_status),
    })

    local r1 = rs:tick()
    assert(r1 == S.RUNNING, "RS tick 1: should be RUNNING, got " .. tostring(r1))

    gate[1] = false
    local r2 = rs:tick()
    assert(r2 == S.FAILURE, "RS tick 2: gate fails, should be FAILURE, got " .. tostring(r2))

    -- Test 2: ReactiveSequence resets previously-RUNNING child on preemption
    gate[1] = true
    action_status[1] = S.RUNNING
    local reset_ct = { 0 }
    local rs2 = BT.ReactiveSequence:new("test_rs2", {
        make_condition("gate2", gate),
        make_resettable_action("act2", action_status, reset_ct),
    })

    rs2:tick()  -- RUNNING on child 2
    assert(reset_ct[1] == 0, "RS2: no reset yet")

    gate[1] = false
    rs2:tick()  -- gate fails, child 2 should be reset
    assert(reset_ct[1] == 1, "RS2: child 2 reset on gate failure, count=" .. tostring(reset_ct[1]))

    -- Test 3: ReactiveSequence all SUCCESS
    gate[1] = true
    action_status[1] = S.SUCCESS
    local rs3 = BT.ReactiveSequence:new("test_rs3", {
        make_condition("g3", gate),
        make_action("a3", action_status),
    })
    assert(rs3:tick() == S.SUCCESS, "RS3: all success")

    ----------------------------------------------------------------
    -- ReactiveSelector tests
    ----------------------------------------------------------------

    -- Test 4: Higher-priority child preempts lower RUNNING child
    local child1_status = { S.FAILURE }
    local child2_status = { S.RUNNING }
    local child2_resets = { 0 }

    local rsel = BT.ReactiveSelector:new("test_rsel", {
        make_action("c1", child1_status),
        make_resettable_action("c2", child2_status, child2_resets),
    })

    local r3 = rsel:tick()
    assert(r3 == S.RUNNING, "RSel tick 1: child1 FAIL, child2 RUNNING → RUNNING, got " .. tostring(r3))

    -- Now child 1 succeeds → should preempt child 2
    child1_status[1] = S.SUCCESS
    local r4 = rsel:tick()
    assert(r4 == S.SUCCESS, "RSel tick 2: child1 SUCCESS → SUCCESS, got " .. tostring(r4))
    assert(child2_resets[1] == 1, "RSel: child2 reset on preemption, count=" .. tostring(child2_resets[1]))

    -- Test 5: ReactiveSelector all FAILURE
    child1_status[1] = S.FAILURE
    child2_status[1] = S.FAILURE
    local rsel2 = BT.ReactiveSelector:new("test_rsel2", {
        make_action("c1b", child1_status),
        make_action("c2b", child2_status),
    })
    assert(rsel2:tick() == S.FAILURE, "RSel2: all fail → FAILURE")

    -- Test 6: ReactiveSelector stays on RUNNING child if no preemption
    child1_status[1] = S.FAILURE
    child2_status[1] = S.RUNNING
    child2_resets[1] = 0
    local rsel3 = BT.ReactiveSelector:new("test_rsel3", {
        make_action("c1c", child1_status),
        make_resettable_action("c2c", child2_status, child2_resets),
    })
    rsel3:tick()  -- RUNNING on child 2
    rsel3:tick()  -- child1 still FAIL, child2 still RUNNING — no reset
    assert(child2_resets[1] == 0, "RSel3: no spurious reset, count=" .. tostring(child2_resets[1]))

    return true
end

return M
