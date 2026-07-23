-- tests/harness/test_json_mock.lua
-- Round-trip unit test for the offline harness's _G.JSON mock (run_offline.lua).
-- Not part of production code — this proves the mock itself is round-trippable
-- (stringify -> parse reproduces the original data), which is what unblocked
-- test_runtime_persistence.lua's save/load tests (RE9).

local T = require("tests/test_util")

local M = {}

function M.test_round_trip_scalars()
    local decoded = JSON.parse(JSON.stringify({ a = 1, b = true, c = "hi", d = false }))
    T.assert_equal(decoded.a, 1, "number should round-trip")
    T.assert_equal(decoded.b, true, "boolean true should round-trip")
    T.assert_equal(decoded.c, "hi", "string should round-trip")
    T.assert_equal(decoded.d, false, "boolean false should round-trip")
end

function M.test_round_trip_nested_table_and_array()
    local original = {
        version = 2,
        variables = { quest_done = true, gold = 100 },
        tags = { "alpha", "beta", "gamma" },
        nested = { inner = { value = 42 } },
    }
    local decoded = JSON.parse(JSON.stringify(original))
    T.assert_equal(decoded.version, 2, "top-level number should round-trip")
    T.assert_equal(decoded.variables.quest_done, true, "nested boolean should round-trip")
    T.assert_equal(decoded.variables.gold, 100, "nested number should round-trip")
    T.assert_equal(decoded.tags[1], "alpha", "array element 1 should round-trip")
    T.assert_equal(decoded.tags[3], "gamma", "array element 3 should round-trip")
    T.assert_equal(decoded.nested.inner.value, 42, "doubly-nested number should round-trip")
end

function M.test_round_trip_special_characters_in_strings()
    local original = { text = 'quote:" backslash:\\ tab:\t newline:\n' }
    local decoded = JSON.parse(JSON.stringify(original))
    T.assert_equal(decoded.text, original.text, "escaped special characters should round-trip")
end

function M.test_stringify_output_is_stable_across_reparse()
    -- stringify(parse(stringify(x))) must equal stringify(x) — proves the
    -- decoded value carries no residual encoding artifacts.
    local original = { a = 1, b = { "x", "y" }, c = "z" }
    local once = JSON.stringify(original)
    local twice = JSON.stringify(JSON.parse(once))
    T.assert_equal(twice, once, "re-stringifying a parsed value should be stable")
end

local tests = {
    test_round_trip_scalars = M.test_round_trip_scalars,
    test_round_trip_nested_table_and_array = M.test_round_trip_nested_table_and_array,
    test_round_trip_special_characters_in_strings = M.test_round_trip_special_characters_in_strings,
    test_stringify_output_is_stable_across_reparse = M.test_stringify_output_is_stable_across_reparse,
}

function M.run()
    -- Deterministic order: `pairs` varies per run, turning cross-suite state leakage into an
    -- intermittent failure that reads as flaky.
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
