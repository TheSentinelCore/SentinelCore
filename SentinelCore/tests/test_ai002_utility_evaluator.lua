local UE = require("ai/UtilityEvaluator")

local M = {}

function M.run()
    -- Test 1: register and evaluate a single action
    local eval = UE:new()
    eval:register({
        id = "test_action",
        action_type = "cast_spell_target",
        spell_id = 100,
        weight = 1.0,
        considerations = {
            { input = "health_pct", curve = "linear", params = { min = 0, max = 1 } },
        },
    })
    local ctx = { health_pct = 0.5 }
    local result = eval:evaluate(ctx)
    assert(result ~= nil, "evaluate should return a result")
    assert(result.action.id == "test_action", "should select the only action")
    assert(math.abs(result.utility - 0.5) < 0.01, "utility should be ~0.5")

    -- Test 2: higher utility wins
    eval:clear()
    eval:register({
        id = "low",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } },
    })
    eval:register({
        id = "high",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.9 } } },
    })
    result = eval:evaluate({ x = 0 })
    assert(result.action.id == "high", "higher utility should win")

    -- Test 3: weight multiplier
    eval:clear()
    eval:register({
        id = "heavy",
        weight = 3.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    eval:register({
        id = "light",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    result = eval:evaluate({ x = 0 })
    assert(result.action.id == "heavy", "weight should boost utility")

    -- Test 4: zero consideration kills action (geometric mean)
    eval:clear()
    eval:register({
        id = "blocked",
        weight = 10.0,
        considerations = {
            { input = "x", curve = "constant", params = { value = 1.0 } },
            { input = "y", curve = "step_above", params = { threshold = 0.5 } },
        },
    })
    eval:register({
        id = "fallback",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } },
    })
    result = eval:evaluate({ x = 1, y = 0.2 })
    assert(result.action.id == "fallback", "zero consideration should eliminate action")

    -- Test 5: no actions returns nil
    eval:clear()
    result = eval:evaluate({ x = 0 })
    assert(result == nil, "no actions should return nil")

    -- Test 6: hard_gates filter (function check)
    eval:clear()
    eval:register({
        id = "gated",
        weight = 5.0,
        hard_gate = function(ctx) return ctx.can_cast == true end,
        considerations = { { input = "x", curve = "constant", params = { value = 1.0 } } },
    })
    eval:register({
        id = "ungated",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    result = eval:evaluate({ x = 0, can_cast = false })
    assert(result.action.id == "ungated", "hard gate should filter action")
    result = eval:evaluate({ x = 0, can_cast = true })
    assert(result.action.id == "gated", "hard gate should pass when true")

    -- Test 7: get_top_k returns sorted list
    eval:clear()
    eval:register({ id = "a", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } } })
    eval:register({ id = "b", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.9 } } } })
    eval:register({ id = "c", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.6 } } } })
    local top = eval:get_top_k({ x = 0 }, 2)
    assert(#top == 2, "top_k should return 2")
    assert(top[1].action.id == "b", "top_k[1] should be highest")
    assert(top[2].action.id == "c", "top_k[2] should be second")

    return true
end

return M
