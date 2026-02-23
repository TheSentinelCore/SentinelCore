local BT = require("ai/BehaviorTree")

local M = {}

function M.run()
    local S = BT.Status

    -- Test 1: Sequence runs all children, returns SUCCESS
    local log = {}
    local seq = BT.Sequence:new("test_seq", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.SUCCESS end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.SUCCESS end),
    })
    assert(seq:tick() == S.SUCCESS, "sequence all success")
    assert(#log == 2 and log[1] == "a" and log[2] == "b", "sequence order")

    -- Test 2: Sequence fails on first failure
    log = {}
    seq = BT.Sequence:new("test_seq2", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.SUCCESS end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.FAILURE end),
        BT.Action:new("c", function() log[#log + 1] = "c"; return S.SUCCESS end),
    })
    assert(seq:tick() == S.FAILURE, "sequence fail on b")
    assert(#log == 2, "sequence should stop at failure")

    -- Test 3: Sequence returns RUNNING and resumes
    local call_count = 0
    seq = BT.Sequence:new("test_seq3", {
        BT.Action:new("a", function() return S.SUCCESS end),
        BT.Action:new("b", function()
            call_count = call_count + 1
            if call_count < 3 then return S.RUNNING end
            return S.SUCCESS
        end),
        BT.Action:new("c", function() return S.SUCCESS end),
    })
    assert(seq:tick() == S.RUNNING, "seq running tick 1")
    assert(seq:tick() == S.RUNNING, "seq running tick 2")
    assert(seq:tick() == S.SUCCESS, "seq success tick 3")

    -- Test 4: Selector returns on first SUCCESS
    log = {}
    local sel = BT.Selector:new("test_sel", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.FAILURE end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.SUCCESS end),
        BT.Action:new("c", function() log[#log + 1] = "c"; return S.SUCCESS end),
    })
    assert(sel:tick() == S.SUCCESS, "selector first success")
    assert(#log == 2, "selector should stop at first success")

    -- Test 5: Selector returns FAILURE when all fail
    sel = BT.Selector:new("test_sel2", {
        BT.Action:new("a", function() return S.FAILURE end),
        BT.Action:new("b", function() return S.FAILURE end),
    })
    assert(sel:tick() == S.FAILURE, "selector all fail")

    -- Test 6: Condition node
    local flag = false
    local cond = BT.Condition:new("test_cond", function() return flag end)
    assert(cond:tick() == S.FAILURE, "condition false")
    flag = true
    assert(cond:tick() == S.SUCCESS, "condition true")

    -- Test 7: Decorator - Inverter
    local inv = BT.Inverter:new("inv",
        BT.Action:new("a", function() return S.SUCCESS end)
    )
    assert(inv:tick() == S.FAILURE, "inverter success->failure")

    inv = BT.Inverter:new("inv2",
        BT.Action:new("a", function() return S.FAILURE end)
    )
    assert(inv:tick() == S.SUCCESS, "inverter failure->success")

    -- Test 8: Decorator - RepeatUntilSuccess
    local attempts = 0
    local rep = BT.RepeatUntilSuccess:new("rep",
        BT.Action:new("a", function()
            attempts = attempts + 1
            if attempts >= 3 then return S.SUCCESS end
            return S.FAILURE
        end)
    )
    assert(rep:tick() == S.RUNNING, "repeat tick 1")
    assert(rep:tick() == S.RUNNING, "repeat tick 2")
    assert(rep:tick() == S.SUCCESS, "repeat tick 3")

    -- Test 9: Decorator - Timeout
    local time_now = 0
    local timeout = BT.Timeout:new("timeout", 5.0,
        BT.Action:new("slow", function() return S.RUNNING end),
        function() return time_now end
    )
    time_now = 0
    assert(timeout:tick() == S.RUNNING, "timeout not expired")
    time_now = 6
    assert(timeout:tick() == S.FAILURE, "timeout expired")

    -- Test 10: reset propagates
    call_count = 0
    local child = BT.Action:new("resettable", function()
        call_count = call_count + 1
        if call_count == 1 then return S.RUNNING end
        return S.SUCCESS
    end)
    seq = BT.Sequence:new("reset_test", {
        BT.Action:new("first", function() return S.SUCCESS end),
        child,
    })
    assert(seq:tick() == S.RUNNING, "pre-reset running")
    seq:reset()
    call_count = 0
    assert(seq:tick() == S.RUNNING, "post-reset restarts from child 1")

    return true
end

return M
