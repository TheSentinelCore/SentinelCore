-- sentinel/tests/runtime/test_validation_service.lua
-- Tests for SENT-8.7 Continuous Validation Service (ADR 002 §11)

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== ValidationService Tests ===")

    local Service = require("runtime/validation_service")

    -- =====================================================================
    -- Test 1: validate_operation flags uncovered required goal
    -- =====================================================================
    print("Test 1: uncovered required goal is an error")
    local svc = Service:new()
    local op = {
        id = "op-1",
        name = "Kill Boars",
        goals = {
            { type = "KillCount", required = true, count = 5, creature_entry = 305 },
        },
        actions = {}, -- no action covers it
    }
    local res = svc:validate_operation(op)
    T.assert_equal(res.all_covered, false, "uncovered required goal should fail")
    T.assert_equal(#res.errors > 0, true, "should produce at least one error")
    print("  PASS")

    -- =====================================================================
    -- Test 2: validate_operation passes when goal is covered
    -- =====================================================================
    print("Test 2: covered goal passes")
    local op2 = {
        id = "op-2",
        name = "Kill Boars",
        goals = {
            { type = "KillCount", required = true, count = 5, creature_entry = 305 },
        },
        actions = {
            { id = "a1", action_type = "grind_area", creature_entry = 305 },
        },
    }
    local res2 = svc:validate_operation(op2)
    T.assert_equal(res2.all_covered, true, "covered goal should pass")
    T.assert_equal(#res2.errors, 0, "should have no errors")
    print("  PASS")

    -- =====================================================================
    -- Test 3: validate_profile scopes to dirty operations only
    -- =====================================================================
    print("Test 3: incremental validation scopes to dirty ops")
    local svc3 = Service:new()
    local profile = {
        operations = {
            {
                id = "clean-op",
                name = "Clean",
                goals = { { type = "KillCount", required = true, count = 5, creature_entry = 305 } },
                actions = { { id = "a", action_type = "grind_area", creature_entry = 305 } },
            },
            {
                id = "dirty-op",
                name = "Dirty",
                goals = { { type = "KillCount", required = true, count = 5, creature_entry = 306 } },
                actions = {}, -- uncovered
            },
        },
    }
    -- Validate only the dirty op -> should report the dirty-op error, not touch clean-op.
    local res3 = svc3:validate_profile(profile, { "dirty-op" })
    T.assert_equal(#res3.errors, 1, "should report exactly the dirty op's error")
    T.assert_equal(res3.errors[1].entity, "Dirty", "error should be for the dirty op")
    print("  PASS")

    -- =====================================================================
    -- Test 4: validate_profile with nil dirty set validates everything
    -- =====================================================================
    print("Test 4: full validation when dirty set is nil")
    local res4 = svc3:validate_profile(profile, nil)
    T.assert_equal(#res4.errors, 1, "full validation finds the uncovered op")
    print("  PASS")

    print("\n=== All ValidationService Tests PASSED ===")
end

return M
