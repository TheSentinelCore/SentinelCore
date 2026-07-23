-- tests/shared/test_aoe_helper.lua
-- C9: shared/aoe_helper.lua's cast_ground_optimal() called
-- core.input.cast_position_spell unguarded (no type() check, no pcall),
-- unlike every comparable core.input.* call site in the codebase. A throwing
-- or missing implementation would crash the whole combat tick instead of
-- degrading to "did not cast".

local AoeHelper = require("shared/aoe_helper")
local T = require("tests/test_util")

local M = {}

local function with_cast_position_spell(fn, impl)
    -- Defensive re-init: earlier suites (e.g. test_target_selector.lua)
    -- replace _G.core wholesale without restoring it, so core.input may be
    -- missing by the time this suite runs. Match the `_G.core = _G.core or {}`
    -- convention used elsewhere in this test tree for isolation.
    _G.core = _G.core or {}
    _G.core.input = _G.core.input or {}
    local previous = _G.core.input.cast_position_spell
    _G.core.input.cast_position_spell = impl
    local ok, err = pcall(fn)
    _G.core.input.cast_position_spell = previous
    if not ok then
        error(err)
    end
end

local function with_stub_position(fn)
    local previous = AoeHelper.find_optimal_position
    AoeHelper.find_optimal_position = function(_spell_id, _range, _min_targets, _radius)
        return { x = 1, y = 2, z = 3 }, 5
    end
    local ok, err = pcall(fn)
    AoeHelper.find_optimal_position = previous
    if not ok then
        error(err)
    end
end

--- A throwing core.input.cast_position_spell must not crash the caller --
--- the pcall guard degrades it to "not cast" instead.
function M.test_throwing_cast_does_not_crash()
    with_stub_position(function()
        with_cast_position_spell(function()
            local ok, hits = AoeHelper.cast_ground_optimal(1234, 30, 2)
            T.assert_false(ok, "throwing cast_position_spell must degrade to false, not propagate")
            T.assert_equal(hits, 5)
        end, function()
            error("simulated SDK failure")
        end)
    end)
end

--- A non-function value (e.g. hot-reload left it nil/stale) must not crash either.
function M.test_non_function_cast_does_not_crash()
    with_stub_position(function()
        with_cast_position_spell(function()
            local ok, hits = AoeHelper.cast_ground_optimal(1234, 30, 2)
            T.assert_false(ok, "non-function cast_position_spell must degrade to false")
            T.assert_equal(hits, 5)
        end, "not a function")
    end)
end

--- A normal successful cast still returns true and the hit count.
function M.test_successful_cast_returns_true()
    with_stub_position(function()
        with_cast_position_spell(function()
            local ok, hits = AoeHelper.cast_ground_optimal(1234, 30, 2)
            T.assert_true(ok, "successful cast_position_spell must return true")
            T.assert_equal(hits, 5)
        end, function(_spell_id, _position)
            return true
        end)
    end)
end

return M
