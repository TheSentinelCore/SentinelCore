local T = require("tests/TestUtil")

local M = {}

---@return table
local function make_mock_nav()
    local nav = {
        _moving = false,
        _last_dest = nil,
        _move_to_calls = 0,
        _stop_calls = 0,
    }

    function nav:is_moving()
        return self._moving
    end

    function nav:get_full_state()
        if self._moving then
            return "navigating.following_path"
        end
        return "idle"
    end

    function nav:move_to(dest, _cb, _opts)
        self._last_dest = dest
        self._move_to_calls = self._move_to_calls + 1
        self._moving = true
    end

    function nav:soft_repath(dest, _cb, _opts)
        self._last_dest = dest
        return true
    end

    function nav:stop()
        self._moving = false
        self._stop_calls = self._stop_calls + 1
    end

    return nav
end

---@param chase_range number
---@param min_range number
---@return table
---@return table
---@return table
local function make_combat_service(chase_range, min_range)
    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")
    local CombatService = require("services/CombatService")

    local bus = EventBus:new()
    local bb = Blackboard:new(bus)
    local nav = make_mock_nav()
    local rotation = {
        get_movement_profile = function()
            return {
                combat_chase_range = chase_range,
                min_combat_range = min_range,
            }
        end,
    }

    local cs = CombatService:new(bus, bb, nav, {}, rotation, {
        combat_chase_move_to_cooldown = 0.0,
        combat_chase_repath_cooldown = 0.0,
        combat_chase_refresh_cooldown = 0.01,
        combat_chase_repath_distance = 0.5,
    })

    bb:set("player.object", T.mock_object({
        health = 1000,
        max_health = 1000,
        mana = 1000,
        max_mana = 1000,
    }))
    bb:set("player.position", { x = 0, y = 0, z = 0 })

    return cs, bb, nav
end

---@param x number
---@param y number
---@param z number
---@return table
local function mock_target(x, y, z)
    return T.mock_object({
        health = 1000,
        max_health = 1000,
        position = { x = x, y = y, z = z },
    })
end

function M.run()
    local env = T.install_core_stub()

    -- 1) Melee profile should not back away when inside chase range.
    do
        local cs, bb, nav = make_combat_service(5.5, 0)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 102, y = 200, z = 0 }) -- 2 yd away

        cs:_apply_combat_chase(target, 0.0, 2.0)
        T.assert_true(nav._move_to_calls == 0,
            "melee: should not issue movement while already in range")
    end

    -- 2) Ranged retreat uses hysteresis so we don't instantly flip back to hold.
    do
        local cs, bb, nav = make_combat_service(30.0, 20.0)
        local target = mock_target(100, 200, 0)

        bb:set("player.position", { x = 119.8, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 0.0, 19.8)
        T.assert_true(nav._move_to_calls >= 1, "ranged: retreat should issue movement when too close")
        T.assert_eq(cs._combat_range_state, "retreat", "ranged: should enter retreat state when too close")

        bb:set("player.position", { x = 120.3, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 0.5, 20.3)
        T.assert_eq(cs._combat_range_state, "retreat",
            "ranged: retreat state should persist until retreat-exit threshold is crossed")

        bb:set("player.position", { x = 121.2, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 1.0, 21.2)
        T.assert_eq(cs._combat_range_state, "hold",
            "ranged: retreat should clear once comfortably above min range")
        T.assert_true(nav._stop_calls >= 1,
            "ranged: returning to hold should stop active chase navigation")
    end

    -- 3) Chase also uses hysteresis to avoid jitter around max range.
    do
        local cs, bb, nav = make_combat_service(30.0, 20.0)
        local target = mock_target(100, 200, 0)

        bb:set("player.position", { x = 130.4, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 0.0, 30.4)
        T.assert_true(nav._move_to_calls == 0,
            "ranged: should not chase for tiny max-range overshoot")
        T.assert_eq(cs._combat_range_state, "hold",
            "ranged: tiny overshoot should stay in hold state")

        bb:set("player.position", { x = 132.0, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 0.5, 32.0)
        T.assert_true(nav._move_to_calls >= 1,
            "ranged: should chase when clearly outside range band")
        T.assert_eq(cs._combat_range_state, "chase",
            "ranged: should enter chase state when beyond chase-enter threshold")

        bb:set("player.position", { x = 129.8, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 1.0, 29.8)
        T.assert_eq(cs._combat_range_state, "chase",
            "ranged: chase state should persist until chase-exit threshold is crossed")

        bb:set("player.position", { x = 128.8, y = 200, z = 0 })
        cs:_apply_combat_chase(target, 1.5, 28.8)
        T.assert_eq(cs._combat_range_state, "hold",
            "ranged: chase state should clear after re-entering comfort zone")
    end

    -- 4) Invalid profile bands are sanitized so min range never exceeds chase range.
    do
        local cs = make_combat_service(10.0, 12.0)
        local profile = cs:_resolve_movement_profile()
        T.assert_true((tonumber(profile.min_combat_range) or 0) < (tonumber(profile.combat_chase_range) or 0),
            "movement profile: min_combat_range must be clamped below combat_chase_range")
    end

    -- 5) Movement should never be issued while casting.
    do
        local cs, bb, nav = make_combat_service(30.0, 20.0)
        local target = mock_target(100, 200, 0)
        bb:set("player.position", { x = 105, y = 200, z = 0 })
        bb:set("player.object", T.mock_object({
            health = 1000,
            max_health = 1000,
            mana = 1000,
            max_mana = 1000,
            casting = true,
        }))

        cs:_apply_combat_chase(target, 0.0, 5.0)
        T.assert_true(nav._move_to_calls == 0,
            "ranged: should not issue movement while casting")
    end

    env.restore()
    return true
end

return M
