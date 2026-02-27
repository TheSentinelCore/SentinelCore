local T = require("tests/TestUtil")

return { run = function()
    local TargetingService = require("services/TargetingService")

    -- 1. Method exists on prototype
    T.assert_true(type(TargetingService.get_visible_hostiles) == "function", "get_visible_hostiles method exists")

    -- 2. Minimal instance call returns empty table (no player object in blackboard)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local bb = Blackboard:new()
    local eb = EventBus:new()
    local ts = TargetingService:new(eb, bb, {}, nil)
    local result = ts:get_visible_hostiles()
    T.assert_eq(type(result), "table", "returns a table")
    T.assert_eq(#result, 0, "empty when no player")

    return true
end }
