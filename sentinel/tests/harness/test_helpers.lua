-- sentinel/tests/harness/test_helpers.lua
-- Shared test utilities

local Helpers = {}

function Helpers.setup()
    -- Clear any global state
    if package.loaded["core/event_bus"] then
        package.loaded["core/event_bus"] = nil
    end
    if package.loaded["core/blackboard"] then
        package.loaded["core/blackboard"] = nil
    end
    if package.loaded["core/geometry"] then
        package.loaded["core/geometry"] = nil
    end
end

function Helpers.teardown()
    Helpers.setup()
end

function Helpers.assert_equal(actual, expected, message)
    message = message or string.format("Expected %s, got %s", tostring(expected), tostring(actual))
    assert(actual == expected, message)
end

function Helpers.assert_nil(value, message)
    message = message or "Expected nil, got " .. tostring(value)
    assert(value == nil, message)
end

function Helpers.assert_not_nil(value, message)
    message = message or "Expected non-nil value"
    assert(value ~= nil, message)
end

function Helpers.assert_true(value, message)
    message = message or "Expected true"
    assert(value == true, message)
end

function Helpers.assert_false(value, message)
    message = message or "Expected false"
    assert(value == false, message)
end

function Helpers.assert_near(actual, expected, tolerance, message)
    tolerance = tolerance or 0.001
    local diff = math.abs(actual - expected)
    message = message or string.format("Expected ~%f, got %f (diff=%f)", expected, actual, diff)
    assert(diff <= tolerance, message)
end

function Helpers.create_mock_player()
    return {
        get_guid = function() return "Player-12345" end,
        get_position = function() return { x = 0, y = 0, z = 0 } end,
        get_health = function() return 100 end,
        get_max_health = function() return 100 end,
        get_power = function() return 100 end,
        get_max_power = function() return 100 end,
        get_power_type = function() return 0 end,
        get_class = function() return 8 end,
        get_level = function() return 60 end,
        is_moving = function() return false end,
        is_dead = function() return false end,
        is_ghost = function() return false end,
        is_mounted = function() return false end,
        in_combat = function() return false end,
    }
end

function Helpers.create_mock_target(health, distance)
    health = health or 100
    distance = distance or 5
    return {
        get_guid = function() return "Target-67890" end,
        get_position = function() return { x = distance, y = 0, z = 0 } end,
        get_health = function() return health end,
        get_max_health = function() return 100 end,
        get_power = function() return 0 end,
        get_max_power = function() return 0 end,
        get_power_type = function() return 0 end,
        get_class = function() return 0 end,
        get_level = function() return 60 end,
        is_enemy = function() return true end,
        is_dead = function() return false end,
        get_name = function() return "Target Dummy" end,
        get_distance = function() return distance end,
    }
end

return Helpers