-- sentinel/tests/runtime/test_variable_store.lua
-- Tests for runtime/variable_store.lua

local Blackboard = require("core/blackboard")
local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== Variable Store Tests ===")

    -- =====================================================================
    -- Test 1: Construction
    -- =====================================================================
    print("Test 1: Construction")
    local bb = Blackboard:new()
    local VariableStore = require("runtime/variable_store")
    local vs = VariableStore:new(bb)
    T.assert_not_nil(vs, "VariableStore instance should not be nil")
    print("  PASS")

    -- =====================================================================
    -- Test 2: Set and get a boolean value
    -- =====================================================================
    print("Test 2: Set and get boolean")
    local bb2 = Blackboard:new()
    local vs2 = VariableStore:new(bb2)
    local ok, err = vs2:set("global", "is_ready", true)
    T.assert_true(ok, "set global boolean should succeed")
    T.assert_nil(err, "error should be nil")
    local val = vs2:get("global", "is_ready")
    T.assert_equal(val, true, "should retrieve true")
    print("  PASS")

    -- =====================================================================
    -- Test 3: Set and get integer value
    -- =====================================================================
    print("Test 3: Set and get integer")
    local bb3 = Blackboard:new()
    local vs3 = VariableStore:new(bb3)
    vs3:set("global", "count", 42)
    local val = vs3:get("global", "count")
    T.assert_equal(val, 42, "should retrieve integer 42")
    T.assert_equal(type(val), "number", "should be a number")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Set and get float value
    -- =====================================================================
    print("Test 4: Set and get float")
    local bb4 = Blackboard:new()
    local vs4 = VariableStore:new(bb4)
    vs4:set("global", "distance", 3.14)
    local val = vs4:get("global", "distance")
    T.assert_equal(val, 3.14, "should retrieve 3.14")
    print("  PASS")

    -- =====================================================================
    -- Test 5: Set and get string value
    -- =====================================================================
    print("Test 5: Set and get string")
    local bb5 = Blackboard:new()
    local vs5 = VariableStore:new(bb5)
    vs5:set("global", "name", "TestChar")
    local val = vs5:get("global", "name")
    T.assert_equal(val, "TestChar", "should retrieve string")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Set and get position value
    -- =====================================================================
    print("Test 6: Set and get position")
    local bb6 = Blackboard:new()
    local vs6 = VariableStore:new(bb6)
    local pos = { x = 100.5, y = 200.3, z = 30.0, zone = "Elwynn" }
    local ok, err = vs6:set("global", "home", pos)
    T.assert_true(ok, "set position should succeed")
    T.assert_nil(err, "error should be nil")
    local val = vs6:get("global", "home")
    T.assert_equal(val.x, 100.5, "x coordinate should match")
    T.assert_equal(val.y, 200.3, "y coordinate should match")
    T.assert_equal(val.zone, "Elwynn", "zone should match")
    print("  PASS")

    -- =====================================================================
    -- Test 7: Invalid type (table without x/y/zone) should be rejected
    -- =====================================================================
    print("Test 7: Invalid type rejection")
    local bb7 = Blackboard:new()
    local vs7 = VariableStore:new(bb7)
    local ok, err = vs7:set("global", "bad", { a = 1, b = 2 })
    T.assert_false(ok, "set invalid table should fail")
    T.assert_not_nil(err, "should return an error")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Global fallthrough when scope is not "global"
    -- =====================================================================
    print("Test 8: Global fallthrough")
    local bb8 = Blackboard:new()
    local vs8 = VariableStore:new(bb8)
    vs8:set("global", "theme", "dark")
    -- Read from operation scope without setting it there
    local val = vs8:get("operation_1", "theme")
    T.assert_equal(val, "dark", "should fall through to global scope")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Operation scope overrides global
    -- =====================================================================
    print("Test 9: Operation scope overrides global")
    local bb9 = Blackboard:new()
    local vs9 = VariableStore:new(bb9)
    vs9:set("global", "speed", "normal")
    vs9:set("op_123", "speed", "fast")
    local global_val = vs9:get("global", "speed")
    local op_val = vs9:get("op_123", "speed")
    T.assert_equal(global_val, "normal", "global should be 'normal'")
    T.assert_equal(op_val, "fast", "operation scope should override with 'fast'")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Has, Delete, and List
    -- =====================================================================
    print("Test 10: Has, Delete, and List")
    local bb10 = Blackboard:new()
    local vs10 = VariableStore:new(bb10)
    vs10:set("global", "alpha", 1)
    vs10:set("global", "beta", 2)
    vs10:set("op_x", "gamma", 3)

    -- Has
    T.assert_true(vs10:has("global", "alpha"), "should have alpha")
    T.assert_false(vs10:has("global", "nonexistent"), "should not have nonexistent")

    -- List
    local global_keys = vs10:list("global")
    T.assert_equal(#global_keys, 2, "should have 2 global keys")
    T.assert_equal(global_keys[1], "alpha", "sorted: alpha first")
    T.assert_equal(global_keys[2], "beta", "sorted: beta second")

    local op_keys = vs10:list("op_x")
    T.assert_equal(#op_keys, 1, "should have 1 op_x key")
    T.assert_equal(op_keys[1], "gamma", "op_x key should be gamma")

    -- Delete
    local deleted = vs10:delete("global", "alpha")
    T.assert_true(deleted, "delete should return true")
    T.assert_false(vs10:has("global", "alpha"), "alpha should be gone")
    T.assert_equal(#vs10:list("global"), 1, "only beta should remain")

    -- Delete nonexistent
    local deleted2 = vs10:delete("global", "nonexistent")
    T.assert_false(deleted2, "delete nonexistent should return false")

    print("  PASS")

    -- =====================================================================
    -- Test 11: Clear scope
    -- =====================================================================
    print("Test 11: Clear scope")
    local bb11 = Blackboard:new()
    local vs11 = VariableStore:new(bb11)
    vs11:set("global", "a", 1)
    vs11:set("global", "b", 2)
    vs11:set("op_y", "c", 3)

    vs11:clear_scope("global")
    T.assert_equal(#vs11:list("global"), 0, "global scope should be empty")
    T.assert_equal(#vs11:list("op_y"), 1, "op_y scope should be untouched")
    print("  PASS")

    -- =====================================================================
    -- Test 12: Get type
    -- =====================================================================
    print("Test 12: Get type")
    local bb12 = Blackboard:new()
    local vs12 = VariableStore:new(bb12)
    vs12:set("global", "flag", false)
    vs12:set("global", "age", 25)
    vs12:set("global", "ratio", 1.5)
    vs12:set("global", "msg", "hello")
    vs12:set("global", "loc", { x = 0, y = 0, z = 0, zone = "Test" })

    T.assert_equal(vs12:get_type("global", "flag"), "bool", "flag should be bool")
    T.assert_equal(vs12:get_type("global", "age"), "integer", "age should be integer")
    T.assert_equal(vs12:get_type("global", "ratio"), "float", "ratio should be float")
    T.assert_equal(vs12:get_type("global", "msg"), "string", "msg should be string")
    T.assert_equal(vs12:get_type("global", "loc"), "position", "loc should be position")

    -- Nonexistent
    T.assert_nil(vs12:get_type("global", "void"), "void should be nil")
    print("  PASS")

    -- =====================================================================
    -- Test 13: Scope/key validation edge cases
    -- =====================================================================
    print("Test 13: Edge cases")
    local bb13 = Blackboard:new()
    local vs13 = VariableStore:new(bb13)

    -- Empty scope
    local ok, err = vs13:set("", "key", "val")
    T.assert_false(ok, "empty scope should fail")

    -- Empty key
    ok, err = vs13:set("global", "", "val")
    T.assert_false(ok, "empty key should fail")

    -- Nil scope
    local val = vs13:get(nil, "key")
    T.assert_nil(val, "nil scope should return nil")

    -- Nil key
    val = vs13:get("global", nil)
    T.assert_nil(val, "nil key should return nil")

    -- has with invalid params
    T.assert_false(vs13:has("", "key"), "empty scope has should be false")
    T.assert_false(vs13:has("global", ""), "empty key has should be false")

    -- list with invalid scope
    local keys = vs13:list("")
    T.assert_equal(#keys, 0, "empty scope list should be empty")

    -- clear_scope with invalid scope
    local cleared = vs13:clear_scope("")
    T.assert_false(cleared, "empty scope clear should be false")

    print("  PASS")

    print("\n=== All VariableStore Tests PASSED ===")
end

return M
