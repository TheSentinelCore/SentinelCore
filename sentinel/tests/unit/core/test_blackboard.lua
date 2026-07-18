-- sentinel/tests/unit/core/test_blackboard.lua
-- Tests for core/blackboard.lua

local Helpers = require("tests.harness.test_helpers")

local function run_tests()
    print("=== Testing core/blackboard.lua ===\n")

    package.loaded["core/blackboard"] = nil
    local Blackboard = require("core/blackboard")

    -- Test 1: Basic set/get (must use valid schema roots)
    print("Test 1: Basic set/get")
    local bb = Blackboard:new()
    bb:set("system.test_key", "value")
    local val = bb:get("system.test_key")
    Helpers.assert_equal(val, "value")
    print("  PASS")

    -- Test 2: Nested keys
    print("Test 2: Nested keys")
    bb:set("player.health", 100)
    bb:set("player.mana", 50)
    Helpers.assert_equal(bb:get("player.health"), 100)
    Helpers.assert_equal(bb:get("player.mana"), 50)
    print("  PASS")

    -- Test 3: Default values
    print("Test 3: Default values")
    local val = bb:get("system.nonexistent", "default")
    Helpers.assert_equal(val, "default")
    val = bb:get("system.nonexistent")
    Helpers.assert_nil(val)
    print("  PASS")

    -- Test 4: Overwrite
    print("Test 4: Overwrite")
    bb:set("system.key", "first")
    bb:set("system.key", "second")
    Helpers.assert_equal(bb:get("system.key"), "second")
    print("  PASS")

    -- Test 5: Numeric operations
    print("Test 5: Numeric operations")
    bb:set("system.counter", 0)
    bb:set("system.counter", bb:get("system.counter") + 1)
    bb:set("system.counter", bb:get("system.counter") + 1)
    Helpers.assert_equal(bb:get("system.counter"), 2)
    print("  PASS")

    -- Test 6: Table values
    print("Test 6: Table values")
    local pos = { x = 10, y = 20, z = 30 }
    bb:set("player.position", pos)
    local retrieved = bb:get("player.position")
    Helpers.assert_equal(retrieved.x, 10)
    Helpers.assert_equal(retrieved.y, 20)
    Helpers.assert_equal(retrieved.z, 30)
    -- Ensure it's the same reference (or deep equal)
    retrieved.x = 999
    Helpers.assert_equal(bb:get("player.position").x, 999)
    print("  PASS")

    -- Test 7: Boolean values
    print("Test 7: Boolean values")
    bb:set("combat.enabled", true)
    Helpers.assert_true(bb:get("combat.enabled"))
    bb:set("combat.enabled", false)
    Helpers.assert_false(bb:get("combat.enabled"))
    print("  PASS")

    -- Test 8: Multiple blackboards isolated
    print("Test 8: Multiple blackboards isolated")
    local bb2 = Blackboard:new()
    bb:set("system.shared", "bb1")
    bb2:set("system.shared", "bb2")
    Helpers.assert_equal(bb:get("system.shared"), "bb1")
    Helpers.assert_equal(bb2:get("system.shared"), "bb2")
    print("  PASS")

    -- Test 9: has_key / remove
    print("Test 9: has_key / remove")
    bb:set("system.temp", "data")
    Helpers.assert_true(bb:has("system.temp"))
    bb:clear("system.temp")
    Helpers.assert_false(bb:has("system.temp"))
    Helpers.assert_nil(bb:get("system.temp"))
    print("  PASS")

    -- Test 10: clear
    print("Test 10: clear")
    bb:set("system.a", 1)
    bb:set("system.b", 2)
    bb:clear("system.a")
    bb:clear("system.b")
    Helpers.assert_false(bb:has("system.a"))
    Helpers.assert_false(bb:has("system.b"))
    print("  PASS")

    print("=== All Blackboard Tests PASSED ===\n")
end

run_tests()