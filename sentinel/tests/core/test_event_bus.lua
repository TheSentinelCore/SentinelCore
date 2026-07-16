local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

function M.run()
    local messages = {}
    local bus = EventBus:new(function(message)
        messages[#messages + 1] = message
    end)
    local order = {}

    bus:subscribe("evt", function()
        order[#order + 1] = 2
    end, 50)
    bus:subscribe("evt", function()
        order[#order + 1] = 1
    end, 10)

    bus:publish("evt")
    T.assert_equal(order[1], 1)
    T.assert_equal(order[2], 2)

    local err_seen = false
    bus:subscribe("system:error", function(payload)
        err_seen = payload and payload.operation == "boom"
    end, 1)
    bus:subscribe("boom", function()
        error("kaboom")
    end, 1)
    bus:publish("boom")
    T.assert_true(err_seen, "system:error should be emitted for handler failure")
end

return M
