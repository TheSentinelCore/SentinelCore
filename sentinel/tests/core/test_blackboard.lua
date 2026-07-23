local Blackboard = require("core/blackboard")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    bb:set("system.now_ms", 123)
    T.assert_equal(bb:get("system.now_ms"), 123)

    local ok = pcall(function()
        bb:set("bad.root", true)
    end)
    T.assert_false(ok, "invalid namespace should fail")

    bb:set("module.test.flag", true)
    T.assert_true(bb:get("module.test.flag"))

    -- F8: the `questing` root was removed from the schema (it contradicted the
    -- `module.<name>.*` convention). A bare `questing.*` write must now be rejected,
    -- and the migrated `module.questing.*` shape must be accepted.
    local questing_root_ok = pcall(function()
        bb:set("questing.enabled", true)
    end)
    T.assert_false(questing_root_ok, "bare questing.* root should be rejected (F8)")

    bb:set("module.questing.enabled", true)
    T.assert_true(bb:get("module.questing.enabled"))
end

return M
