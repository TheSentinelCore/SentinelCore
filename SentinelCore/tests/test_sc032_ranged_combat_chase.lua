local T = require("tests/TestUtil")

local M = {}

function M.run()
    local env = T.install_core_stub()
    local CombatService = require("services/CombatService")

    -- Build a minimal CombatService to test _apply_combat_chase
    -- We need to access _resolve_movement_profile and _apply_combat_chase
    -- through the combat service's internal methods.

    -- Instead, test the movement profile resolution and the behavior
    -- by constructing a CombatService and observing nav commands.

    local Blackboard = require("core/Blackboard")

    -- Helper: create a mock navigation adapter that records movement commands
    local function make_mock_nav()
        local nav = {}
        nav._moving = false
        nav._last_dest = nil
        nav._stopped = false

        function nav:is_moving() return self._moving end
        function nav:move_to(dest, cb, opts)
            self._last_dest = dest
            self._moving = true
            self._stopped = false
        end
        function nav:soft_repath(dest, cb, opts)
            self._last_dest = dest
        end
        function nav:stop()
            self._moving = false
            self._stopped = true
        end
        function nav:awaiting_path() return false end
        return nav
    end

    -- Helper: build a minimal CombatService with controlled movement profile
    local function make_combat_service(chase_range, min_range)
        local bb = Blackboard:new()
        local nav = make_mock_nav()

        -- Create a mock rotation that returns our test movement profile
        local rotation = {
            get_movement_profile = function()
                return {
                    combat_chase_range = chase_range,
                    min_combat_range = min_range or 0,
                }
            end,
            tick_once = function() return true end,
        }

        local cs = CombatService:new(bb, nil, nil, nil, nil, nav, {})
        cs._rotation = rotation
        cs._nav = nav

        return cs, bb, nav
    end

    -- Helper: make a mock target at a given position
    local function mock_target(x, y, z)
        return T.mock_object({
            health = 1000, max_health = 1000,
            position = { x = x, y = y, z = z },
        })
    end

    -- 1. Melee class (min_combat_range=0): no backing away at close range
    do
        local cs, bb, nav = make_combat_service(5.5, 0)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 102, y = 200, z = 0 })  -- 2yd away
        bb:set("player.object", T.mock_object({ health = 1000, max_health = 1000 }))

        cs:_apply_combat_chase(target, 0, 2.0)

        -- At 2yd with chase_range=5.5, should STOP (in range), not back away
        T.assert_true(nav._last_dest == nil or nav._stopped,
            "melee: no movement issued at 2yd (in range)")
    end

    -- 2. Ranged class: back away when target is too close
    do
        local cs, bb, nav = make_combat_service(30, 20)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 105, y = 200, z = 0 })  -- 5yd away
        bb:set("player.object", T.mock_object({ health = 1000, max_health = 1000 }))

        cs:_apply_combat_chase(target, 0, 5.0)

        -- At 5yd with min_combat_range=20, should issue move-away
        T.assert_true(nav._last_dest ~= nil, "ranged: movement issued to back away")
        -- Away position should be further from target than player currently is
        local away_dist = math.sqrt(
            (nav._last_dest.x - 100)^2 + (nav._last_dest.y - 200)^2
        )
        T.assert_true(math.abs(away_dist - 20) < 1.0,
            "ranged: away destination ~20yd from target, got " .. away_dist)
        -- Should be in the same direction as player (away from target = +x)
        T.assert_true(nav._last_dest.x > 100,
            "ranged: away position is in +x direction (away from target)")
    end

    -- 3. Ranged class: comfort zone (no movement needed)
    do
        local cs, bb, nav = make_combat_service(30, 20)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 125, y = 200, z = 0 })  -- 25yd away
        bb:set("player.object", T.mock_object({ health = 1000, max_health = 1000 }))

        cs:_apply_combat_chase(target, 0, 25.0)

        -- At 25yd: within [20, 30] comfort zone, no movement
        T.assert_true(nav._last_dest == nil,
            "ranged: no movement in comfort zone (25yd)")
    end

    -- 4. Ranged class: chase when too far
    do
        local cs, bb, nav = make_combat_service(30, 20)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 140, y = 200, z = 0 })  -- 40yd away
        bb:set("player.object", T.mock_object({ health = 1000, max_health = 1000 }))

        cs:_apply_combat_chase(target, 0, 40.0)

        -- At 40yd with chase_range=30, should chase toward target
        T.assert_true(nav._last_dest ~= nil, "ranged: chase issued at 40yd")
        -- Destination should be near the target
        local chase_dist = math.sqrt(
            (nav._last_dest.x - 100)^2 + (nav._last_dest.y - 200)^2
        )
        T.assert_true(chase_dist < 5.0,
            "ranged: chase destination is near target, got " .. chase_dist)
    end

    -- 5. Don't back away while casting
    do
        local cs, bb, nav = make_combat_service(30, 20)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 105, y = 200, z = 0 })  -- 5yd (too close)
        local casting_player = T.mock_object({
            health = 1000, max_health = 1000,
            is_casting_spell = true,
        })
        bb:set("player.object", casting_player)

        cs:_apply_combat_chase(target, 0, 5.0)

        -- Casting: should NOT move even though too close
        T.assert_true(nav._last_dest == nil,
            "ranged: no movement while casting (even at 5yd)")
    end

    env.restore()
    return true
end

return M
