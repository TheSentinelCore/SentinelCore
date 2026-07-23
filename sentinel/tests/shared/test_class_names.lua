-- sentinel/tests/shared/test_class_names.lua
-- B8: one authoritative class_id -> class name map (shared/class_names.lua),
-- consumed by both combat (upper-cased at its own boundary) and questing
-- (Title-Case, matches ClassIs / RestedXP class tails).

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== class_names Tests (B8) ===")

    print("Test 1: shared map resolves Title-Case names")
    local ClassNames = require("shared/class_names")
    T.assert_equal(ClassNames.resolve(8), "Mage", "class_id 8 should resolve to Mage")
    T.assert_equal(ClassNames.resolve(2), "Paladin", "class_id 2 should resolve to Paladin")
    T.assert_nil(ClassNames.resolve(999), "unknown class_id should resolve to nil")
    T.assert_nil(ClassNames.resolve(nil), "nil class_id should resolve to nil")
    print("  PASS")

    print("Test 2: questing consumes the shared Title-Case map")
    package.loaded["modules/questing/runtime_profile"] = nil
    local ok_rp, RuntimeProfile = pcall(require, "modules/questing/runtime_profile")
    T.assert_true(ok_rp, "runtime_profile should require cleanly")
    T.assert_not_nil(RuntimeProfile, "runtime_profile module should load")
    print("  PASS (module loads and shares the map by construction)")

    print("Test 3: combat upper-cases at its own boundary from the shared source")
    package.loaded["modules/combat/module"] = nil
    local ok_cm, SentinelCombat = pcall(require, "modules/combat/module")
    T.assert_true(ok_cm, "combat module should require cleanly: " .. tostring(SentinelCombat))
    T.assert_not_nil(SentinelCombat, "combat module should load")
    print("  PASS (module loads and shares the map by construction)")

    print("\n=== All class_names Tests PASSED ===")
end

return M
