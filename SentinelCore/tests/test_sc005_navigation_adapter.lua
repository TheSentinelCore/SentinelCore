local T = require("tests/TestUtil")

local function run()
    T.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local NavigationAdapter = require("services/NavigationAdapter")
    local ErrorCodes = require("events/ErrorCodes")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local nav_bb_store = {
        ["player.position"] = { x = 0, y = 0, z = 0 },
    }
    local nav_bb = {
        get = function(_, key)
            return nav_bb_store[key]
        end,
        set = function(_, key, value)
            nav_bb_store[key] = value
        end,
    }
    local navigate_calls = 0

    _G.SentinelNavClient = {
        client = {
            move_to = function(_, _, cb) cb(true, nil, { code = "ok" }) end,
            validate_destination = function(_, _, cb) cb(true, nil, 12.5) end,
            is_server_available = function() return true end,
            is_moving = function() return true end,
            get_full_state = function() return "navigating.following_path" end,
            get_blackboard = function() return nav_bb end,
            get_path_opts = function()
                return {
                    smoothing = true,
                }
            end,
            movement = {
                navigate = function(_, waypoints)
                    navigate_calls = navigate_calls + 1
                    return type(waypoints) == "table" and #waypoints > 0
                end,
            },
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

    local moving_state = nav:is_moving()
    local full_state = nav:get_full_state()
    T.assert_true(moving_state == true, "is_moving should pass through nav client moving state")
    T.assert_eq(full_state, "navigating.following_path", "get_full_state should pass through nav client full state")

    local soft_ok = false
    local soft_started = nav:soft_repath({ x = 5, y = 5, z = 0 }, function(ok)
        soft_ok = ok == true
    end)
    T.assert_true(soft_started == true, "soft_repath should start when nav client internals are available")
    T.assert_true(soft_ok == true, "soft_repath should return success on valid path response")
    T.assert_eq(navigate_calls, 1, "soft_repath should push refreshed waypoints to movement:navigate")
    T.assert_true(type(nav_bb_store["path.waypoints"]) == "table", "soft_repath should update nav blackboard waypoints")

    _G.SentinelNavClient = nil
    local available2, err2 = nav:is_available()
    T.assert_true(available2 == false and err2 == ErrorCodes.DEP_NAVCLIENT_MISSING, "missing nav should fail closed")

    return {
        sc005_navigation_adapter = true,
    }
end

return { run = run }
