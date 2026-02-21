---@module BGBOT.tests.test_action_arbiter

local Arbiter = require("core/action_arbiter")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(tostring(msg) .. " | Expected: " .. tostring(b) .. ", Got: " .. tostring(a))
    end
end

local function fake_world(x, y, z)
    return {
        get_self = function()
            return {
                position = { x = x, y = y, z = z },
            }
        end,
    }
end

local function run_tests()
    local arbiter = Arbiter.new()
    
    print("Testing Arbiter movement override precedence...")

    -- 1. Intent has nav_goal, no combat command
    local out1 = arbiter:resolve({ nav_goal = {x=1,y=2,z=3} }, nil, nil)
    assert_eq(out1.nav_goal.x, 1, "Intent nav_goal preserved")

    -- 2. Combat command halt_movement 
    local out2 = arbiter:resolve({ nav_goal = {x=1,y=2,z=3} }, { halt_movement = true }, nil)
    assert_eq(out2.nav_goal, nil, "halt_movement clears nav_goal")

    -- 3. Combat command movement_override
    local out3 = arbiter:resolve({ nav_goal = {x=1,y=2,z=3} }, { movement_override = {x=9,y=8,z=7} }, nil)
    assert_eq(out3.nav_goal.x, 9, "movement_override overwrites nav_goal x")
    assert_eq(out3.nav_goal.y, 8, "movement_override overwrites nav_goal y")

    -- 4. Objective interaction ignores combat movement overwrite
    local out4 = arbiter:resolve({ interact_target = "flag1", nav_goal = {x=1,y=2,z=3} }, { movement_override = {x=9,y=9,z=9} }, nil)
    assert_eq(out4.nav_goal.x, 1, "Objective interaction preserves original intent nav_goal")
    assert_eq(out4.interact_target, "flag1", "Objective interaction preserves interact target")

    -- 5. Invalid movement_override is ignored (keeps intent nav_goal)
    local out5 = arbiter:resolve({ nav_goal = {x=1,y=2,z=3} }, { movement_override = {x="bad",y=8,z=7} }, nil)
    assert_eq(out5.nav_goal.x, 1, "Invalid movement_override keeps intent nav_goal")

    -- 6. Out-of-bounds movement_override is ignored when self position is known
    local world = fake_world(0, 0, 0)
    local out6 = arbiter:resolve({ nav_goal = {x=1,y=2,z=3} }, { movement_override = {x=200,y=0,z=0} }, world)
    assert_eq(out6.nav_goal.x, 1, "Out-of-bounds movement_override keeps intent nav_goal")

    print("All Arbiter tests passed.")
end

run_tests()
