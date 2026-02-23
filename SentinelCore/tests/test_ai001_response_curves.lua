local RC = require("ai/ResponseCurves")

local M = {}

local function assert_near(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.4f, got %.4f", msg or "assert_near", expected, actual))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "assert_eq", tostring(b), tostring(a))) end
end

function M.run()
    -- linear: maps [min,max] → [0,1]
    assert_near(RC.evaluate("linear", 5, { min = 0, max = 10 }), 0.5, 0.001, "linear_mid")
    assert_near(RC.evaluate("linear", 0, { min = 0, max = 10 }), 0.0, 0.001, "linear_min")
    assert_near(RC.evaluate("linear", 10, { min = 0, max = 10 }), 1.0, 0.001, "linear_max")
    assert_near(RC.evaluate("linear", -5, { min = 0, max = 10 }), 0.0, 0.001, "linear_clamp_low")
    assert_near(RC.evaluate("linear", 15, { min = 0, max = 10 }), 1.0, 0.001, "linear_clamp_high")

    -- inverse_linear
    assert_near(RC.evaluate("inverse_linear", 5, { min = 0, max = 10 }), 0.5, 0.001, "inv_linear_mid")
    assert_near(RC.evaluate("inverse_linear", 0, { min = 0, max = 10 }), 1.0, 0.001, "inv_linear_min")
    assert_near(RC.evaluate("inverse_linear", 10, { min = 0, max = 10 }), 0.0, 0.001, "inv_linear_max")

    -- quadratic
    assert_near(RC.evaluate("quadratic", 5, { min = 0, max = 10 }), 0.25, 0.001, "quad_mid")

    -- inverse_quadratic
    assert_near(RC.evaluate("inverse_quadratic", 5, { min = 0, max = 10 }), 0.75, 0.001, "inv_quad_mid")

    -- step_above / step_below
    assert_eq(RC.evaluate("step_above", 5, { threshold = 3 }), 1, "step_above_pass")
    assert_eq(RC.evaluate("step_above", 2, { threshold = 3 }), 0, "step_above_fail")
    assert_eq(RC.evaluate("step_below", 2, { threshold = 3 }), 1, "step_below_pass")
    assert_eq(RC.evaluate("step_below", 5, { threshold = 3 }), 0, "step_below_fail")

    -- bell curve
    assert_near(RC.evaluate("bell", 5, { center = 5, width = 2 }), 1.0, 0.001, "bell_center")
    assert(RC.evaluate("bell", 10, { center = 5, width = 2 }) < 0.1, "bell_tail")

    -- logistic (S-curve)
    assert_near(RC.evaluate("logistic", 5, { midpoint = 5, steepness = 10 }), 0.5, 0.01, "logistic_mid")
    assert(RC.evaluate("logistic", 10, { midpoint = 5, steepness = 10 }) > 0.99, "logistic_high")
    assert(RC.evaluate("logistic", 0, { midpoint = 5, steepness = 10 }) < 0.01, "logistic_low")

    -- constant
    assert_near(RC.evaluate("constant", 999, { value = 0.7 }), 0.7, 0.001, "constant")

    -- unknown curve type returns 0
    assert_eq(RC.evaluate("nonexistent", 5, {}), 0, "unknown_curve")

    return true
end

return M
