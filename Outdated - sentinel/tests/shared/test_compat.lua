local Compat = require("shared/compat")
local T = require("tests/test_util")

local M = {}

function M.run()
    -- safe_call: returns value on success
    local obj = { greet = function(self) return "hello" end }
    T.assert_equal(Compat.safe_call(obj, "greet"), "hello", "safe_call returns value on success")

    -- safe_call: returns nil on error
    local bad_obj = { fail = function(self) error("oops") end }
    T.assert_true(Compat.safe_call(bad_obj, "fail") == nil, "safe_call returns nil on error")

    -- safe_call: returns nil for missing method
    T.assert_true(Compat.safe_call(obj, "nonexistent") == nil, "safe_call returns nil for missing method")

    -- safe_call0: returns value from function
    T.assert_equal(Compat.safe_call0(function() return 42 end), 42, "safe_call0 returns value")

    -- safe_call0: returns nil on error
    T.assert_true(Compat.safe_call0(function() error("fail") end) == nil, "safe_call0 returns nil on error")

    -- safe_call2: returns value
    T.assert_equal(Compat.safe_call2(function(x) return x * 2 end, nil, 5), 10, "safe_call2 returns value")

    -- same_guid: matching guids
    local a = { get_guid = function() return 123 end }
    local b = { get_guid = function() return 123 end }
    T.assert_true(Compat.same_guid(a, b), "same_guid matches equal guids")

    -- same_guid: different guids
    local c = { get_guid = function() return 456 end }
    T.assert_false(Compat.same_guid(a, c), "same_guid rejects different guids")

    -- same_guid: nil safety
    T.assert_false(Compat.same_guid(nil, a), "same_guid handles nil first arg")
    T.assert_false(Compat.same_guid(a, nil), "same_guid handles nil second arg")

    -- dist: basic distance
    local p1 = { x = 0, y = 0, z = 0 }
    local p2 = { x = 3, y = 4, z = 0 }
    T.assert_equal(Compat.dist(p1, p2), 5, "dist computes correct distance")

    -- dist: zero distance
    T.assert_equal(Compat.dist(p1, p1), 0, "dist returns 0 for same point")

    -- dist: nil safety
    T.assert_equal(Compat.dist(nil, p1), math.huge, "dist returns huge for nil first arg")
    T.assert_equal(Compat.dist(p1, nil), math.huge, "dist returns huge for nil second arg")

    -- dist_sq: squared distance
    T.assert_equal(Compat.dist_sq(p1, p2), 25, "dist_sq computes correct squared distance")

    -- dist_in_range: within range
    T.assert_true(Compat.dist_in_range(p1, p2, 5), "dist_in_range returns true when within range")

    -- dist_in_range: out of range
    T.assert_false(Compat.dist_in_range(p1, p2, 4), "dist_in_range returns false when out of range")

    -- dist_in_range: nil safety
    T.assert_false(Compat.dist_in_range(nil, p1, 5), "dist_in_range handles nil args")

    -- num: converts strings
    T.assert_equal(Compat.num("42"), 42, "num converts string to number")
    T.assert_equal(Compat.num("abc"), 0, "num returns 0 for non-numeric string")
    T.assert_equal(Compat.num(nil), 0, "num returns 0 for nil")

    -- is_trueish: various inputs
    T.assert_true(Compat.is_trueish(true), "is_trueish handles true")
    T.assert_true(Compat.is_trueish(1), "is_trueish handles 1")
    T.assert_true(Compat.is_trueish("true"), "is_trueish handles 'true'")
    T.assert_true(Compat.is_trueish("1"), "is_trueish handles '1'")
    T.assert_false(Compat.is_trueish(false), "is_trueish handles false")
    T.assert_false(Compat.is_trueish(0), "is_trueish handles 0")
    T.assert_false(Compat.is_trueish("false"), "is_trueish handles 'false'")
end

return M
