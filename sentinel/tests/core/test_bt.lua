local Blackboard = require("core/blackboard")
local BT = require("core/bt/factory")
local Runner = require("core/bt/runner")
local T = require("tests/test_util")

local M = {}

function M.run()
    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)

    local seq = Runner:new(BT.sequence("seq", {
        BT.condition("true", function() return true end),
        BT.action("ok", function() return true end),
    }))
    T.assert_equal(seq:tick(bb), "SUCCESS")

    local sel = Runner:new(BT.selector("sel", {
        BT.condition("false", function() return false end),
        BT.action("fallback", function() return true end),
    }))
    T.assert_equal(sel:tick(bb), "SUCCESS")

    local cooldown = Runner:new(BT.cooldown("cd", 500, BT.action("once", function() return true end), { key = "test_cd" }))
    T.assert_equal(cooldown:tick(bb), "SUCCESS")
    T.assert_equal(cooldown:tick(bb), "FAILURE")
    bb:set("system.now_ms", 1600)
    T.assert_equal(cooldown:tick(bb), "SUCCESS")

    local attempts = Runner:new(BT.max_attempts("tries", 2, BT.action("fail", function() return false end), { key = "tries" }))
    T.assert_equal(attempts:tick(bb), "FAILURE")
    T.assert_equal(attempts:tick(bb), "FAILURE")
    T.assert_equal(attempts:tick(bb), "FAILURE")
end

return M
