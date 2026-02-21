local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local NavigationAdapter = require("services/NavigationAdapter")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)

    _G.SentinelNavClient = {
        client = {
            move_to = function(_, _, cb) cb(true, nil, { code = "ok" }) end,
            validate_destination = function(_, _, cb) cb(true, nil, 12.5) end,
            is_server_available = function() return true end,
            stop = function() end,
            nav_client = {
                find_path = function(_, _, _, cb)
                    cb(true, { waypoints = { {x=1,y=1,z=1} }, distance = 22.2 }, nil)
                end,
            },
        },
    }

    local nav = NavigationAdapter:new(bus, bb)
    local available, err = nav:is_available()
    T.assert_true(available, "nav should be available")

    local move_ok = false
    nav:move_to({ x = 1, y = 1, z = 1 }, function(ok) move_ok = ok end)
    T.assert_true(move_ok, "move_to should succeed")

    local cost_ok, cost = false, nil
    nav:estimate_path_cost({x=0,y=0,z=0}, {x=1,y=1,z=1}, function(ok, c)
        cost_ok = ok
        cost = c
    end)
    T.assert_true(cost_ok and cost == 22.2, "path cost should be returned")

    _G.SentinelNavClient = nil
    local available2, err2 = nav:is_available()
    T.assert_true(available2 == false and err2 == ErrorCodes.DEP_NAVCLIENT_MISSING, "missing nav should fail closed")

    return {
        sc005_navigation_adapter = true,
    }
end

return { run = run }
