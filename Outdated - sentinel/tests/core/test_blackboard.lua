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
end

return M
