-- tests/modules/questing/test_runtime_nav.lua
-- Unit tests for navigation integration in RuntimeProfile and RuntimeAction (Wave 3)
-- Tests: is_at_npc, is_at_object, is_at_destination, execute_travel, proximity checks

local RuntimeAction = require("modules/questing/runtime_action")
local Geometry = require("core/geometry")
local T = require("tests/test_util")

local M = {}

-- ============================================================================
-- Helpers
-- ============================================================================

--- Create a mock player at a given position (Sylvannas API compliant - get_local_player).
local function set_player_pos(x, y, z)
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.object_manager.get_local_player = function()
        return {
            is_valid = function() return true end,
            get_position = function()
                return { x = x or 0, y = y or 0, z = z or 0 }
            end,
        }
    end
    -- Also expose get_all_objects for UnitHelper to use
    _G.core.object_manager.get_all_objects = function()
        return {}
    end
end

--- Create a mock context with NavAdapter stubs and position overrides.
local function mock_context(overrides)
    overrides = overrides or {}

    -- Mock player position
    if overrides.player_pos then
        set_player_pos(overrides.player_pos.x, overrides.player_pos.y, overrides.player_pos.z)
    else
        set_player_pos(0, 0, 0)
    end

    -- Note: GetNearestCreature mock removed - UnitHelper now uses get_all_objects
    -- Tests that need creature/object mocking should set core.object_manager.get_all_objects

    -- Mock NavAdapter
    local nav_mock = {
        _active = false,
        _state = "idle",
        _moved_to = nil,
        _stopped = false,
        is_active = function(self)
            return self._active
        end,
        move_to = function(self, target, opts)
            self._moved_to = target
            self._active = true
            self._state = "requesting_path"
            self._opts = opts
            return true, nil
        end,
        poll = function(self)
            if self._state == "arrived" then
                self._active = false
                self._state = "idle"
            end
            return self._state, { state = self._state }
        end,
        stop = function(self, reason)
            self._stopped = true
            self._active = false
            self._state = "idle"
            self._stop_reason = reason
        end,
        get_state = function(self)
            return self._state
        end,
        -- Allow tests to simulate arrival
        _simulate_arrival = function(self)
            self._state = "arrived"
        end,
    }

    return {
        -- Override is_at_npc / is_at_object with test-controllable versions
        is_at_npc = overrides.is_at_npc or function() return false end,
        is_at_object = overrides.is_at_object or function() return false end,
        is_at_destination = overrides.is_at_destination or function() return false end,
        get_zone_waypoint = overrides.get_zone_waypoint or function() return nil end,

        -- NavAdapter mock
        nav = overrides.nav or nav_mock,

        -- Variables
        variables = overrides.variables or {},
        query = overrides.query or {},

        -- Player position helper
        _get_player_pos = overrides._get_player_pos or function()
            local player = _G.core and _G.core.object_manager and _G.core.object_manager.get_local_player
            if player then
                local obj = player()
                if obj and obj.get_position then
                    return obj.get_position()
                end
            end
            return nil
        end,
    }
end

-- ============================================================================
-- is_at_destination tests (W3.2)
-- ============================================================================

function M.test_is_at_destination_exact()
    set_player_pos(10, 20, 30)
    local dest = { x = 10, y = 20, z = 30 }
    -- is_at_destination: if dest is a table with x/y/z, use Geometry.distance
    local dist = Geometry.distance(dest, { x = 10, y = 20, z = 30 })
    T.assert_equal(dist, 0, "Same position should have distance 0")
    T.assert_true(dist <= 5.0, "Distance 0 should be within tolerance 5.0")
end

function M.test_is_at_destination_out_of_range()
    set_player_pos(0, 0, 0)
    local dest = { x = 100, y = 100, z = 0 }
    local dist = Geometry.distance(dest, { x = 0, y = 0, z = 0 })
    T.assert_true(dist > 5.0, "Far position should exceed tolerance")
end

function M.test_is_at_destination_nil_dest()
    set_player_pos(0, 0, 0)
    local dist = Geometry.distance(nil, { x = 0, y = 0, z = 0 })
    T.assert_equal(dist, math.huge, "Nil dest should return math.huge")
end

-- ============================================================================
-- execute_travel tests (W3.4)
-- ============================================================================

function M.test_travel_already_at_destination()
    local ctx = mock_context({
        is_at_destination = function() return true end,
    })
    local action = { type = "Travel", payload = {
        destination = "Elwynn Forest",
        position = { x = -8949.95, y = -132.49, z = 83.53 },
    } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "success", "Travel should succeed when already at destination")
end

function M.test_travel_starts_navigation()
    local nav_mock = nil
    local ctx = mock_context({
        is_at_destination = function() return false end,
        get_zone_waypoint = function() return { x = 1, y = 2, z = 3 } end,
        nav = nil,
    })
    -- Override with a nav we can inspect
    nav_mock = {
        _active = false,
        _moved_to = nil,
        _state = "idle",
        is_active = function(self) return self._active end,
        move_to = function(self, target, opts)
            self._moved_to = target
            self._active = true
            self._state = "requesting_path"
            return true
        end,
        poll = function(self) return self._state, {} end,
        stop = function(self) self._active = false self._state = "idle" end,
        get_state = function(self) return self._state end,
    }
    ctx.nav = nav_mock

    local action = { type = "Travel", payload = {
        destination = "Elwynn Forest",
        position = { x = 1, y = 2, z = 3 },
    } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Travel should return blocked after starting navigation")
    T.assert_not_nil(nav_mock._moved_to, "NavAdapter move_to should have been called")
    T.assert_equal(nav_mock._moved_to.x, 1)
    T.assert_equal(nav_mock._moved_to.y, 2)
    T.assert_equal(nav_mock._moved_to.z, 3)
end

function M.test_travel_zone_only_no_position()
    local nav_mock = nil
    local ctx = mock_context({
        is_at_destination = function() return false end,
        get_zone_waypoint = function() return nil end, -- Can't resolve zone
    })
    nav_mock = {
        _active = false, is_active = function() return false end,
        move_to = function() return true end, poll = function() return "idle", {} end,
        stop = function() end, get_state = function() return "idle" end,
    }
    ctx.nav = nav_mock

    local action = { type = "Travel", payload = { destination = "UnknownZone" } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Travel should return blocked when no position known")
end

function M.test_travel_polls_for_arrival()
    local nav_mock = nil
    local ctx = mock_context({
        is_at_destination = function()
            -- Return true only after nav arrives
            return nav_mock and nav_mock._state == "arrived"
        end,
        get_zone_waypoint = function() return { x = 10, y = 10, z = 10 } end,
    })
    local poll_count = 0
    nav_mock = {
        _active = true,
        _moved_to = nil,
        _state = "moving",
        _arrived = false,
        is_active = function(self) return self._active end,
        move_to = function(self, target, opts)
            self._moved_to = target
            self._state = "requesting_path"
            self._active = true
            return true
        end,
        poll = function(self)
            poll_count = poll_count + 1
            if poll_count >= 3 then
                self._state = "arrived"
            end
            return self._state, {}
        end,
        stop = function(self, reason)
            self._active = false
            self._state = "idle"
            self._stop_reason = reason
        end,
        get_state = function(self) return self._state end,
    }
    ctx.nav = nav_mock

    local action = { type = "Travel", payload = {
        destination = "TestZone",
        position = { x = 10, y = 10, z = 10 },
    } }

    -- First call: start navigation
    local result1 = RuntimeAction.execute(action, ctx)
    T.assert_equal(result1, "blocked", "First travel call should start navigating")

    -- Second call: still moving
    local result2 = RuntimeAction.execute(action, ctx)
    T.assert_equal(result2, "blocked", "Second travel call should report still moving")

    -- Third call: arrived
    local result3 = RuntimeAction.execute(action, ctx)
    T.assert_equal(result3, "success", "Third travel call should succeed after arrival")
end

-- ============================================================================
-- execute_kill proximity tests (W3.6)
-- ============================================================================

function M.test_kill_npc_in_range()
    local ctx = mock_context({
        is_at_npc = function() return true end,
    })
    -- Mock get_all_objects to return a valid non-dead target (Sylvannas API compliant)
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                is_dead = function() return false end,
                get_npc_id = function() return 1234 end,
            },
        }
    end
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    -- Kill action in range with non-dead target should return "blocked" (combat handles kill)
    T.assert_equal(result, "blocked", "Kill should return blocked when NPC in range and alive")
end

function M.test_kill_npc_dead_and_in_range()
    local ctx = mock_context({
        is_at_npc = function() return true end,
    })
    -- Mock get_all_objects to return a dead target
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                is_dead = function() return true end,
                get_npc_id = function() return 1234 end,
                get_position = function() return { x = 0, y = 0, z = 0 } end,
            },
        }
    end
    local action = { type = "Kill", payload = { creature_entries = { 1234 }, quantity = 1 } }

    -- A dead target is now LOOTED before it is counted -- kill objectives are
    -- often item drops, so counting without looting can never satisfy them. The
    -- first ticks return "waiting" while looting is attempted (bounded), then the
    -- corpse is tallied and the action succeeds.
    local result
    for _ = 1, 6 do
        result = RuntimeAction.execute(action, ctx)
        if result == "success" then break end
    end
    T.assert_equal(result, "success", "Kill should succeed once the dead NPC has been looted")
end

function M.test_kill_npc_out_of_range()
    local ctx = mock_context({
        is_at_npc = function() return false end, -- Out of range
    })
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                is_dead = function() return false end,
                get_npc_id = function() return 1234 end,
                get_position = function() return { x = 50, y = 50, z = 0 } end,
            },
        }
    end
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    -- "waiting", not "blocked": blocked hands control to the profile's NAVIGATING state, where the
    -- Kill action stops running and can no longer re-issue navigation as the mob wanders. Waiting
    -- keeps the action in control of its own pursuit each tick.
    T.assert_equal(result, "waiting", "Kill waits and keeps chasing when the NPC is out of range")
    -- NavAdapter should have been called to navigate to target
    T.assert_not_nil(ctx.nav and ctx.nav._moved_to, "NavAdapter move_to should have been called")
    if ctx.nav and ctx.nav._moved_to then
        T.assert_equal(ctx.nav._moved_to.x, 50)
        T.assert_equal(ctx.nav._moved_to.y, 50)
    end
end

function M.test_kill_no_targets_found()
    local ctx = mock_context({
        is_at_npc = function() return false end,
    })
    _G.core.object_manager.get_all_objects = function()
        return {} -- No targets
    end
    -- No destination in payload either
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Kill should return blocked when no targets and no destination")
end

function M.test_kill_no_targets_ignores_destination_field()
    -- A9: RuntimeKill has no `destination` field (SentinelQuesting/shared/src/runtime/
    -- action.rs never emits one for Kill payloads) — the old navigate-to-spawn-area branch
    -- keyed off payload.destination was permanently dead code and has been removed. A stray
    -- `destination` key on the payload must now be silently ignored: no navigation, just
    -- "blocked" like any other no-targets-found case.
    local ctx = mock_context({
        is_at_npc = function() return false end,
        get_zone_waypoint = function() return { x = -8000, y = -100, z = 80 } end,
    })
    _G.core.object_manager.GetNearestCreature = function()
        return nil -- No targets
    end
    local action = { type = "Kill", payload = {
        creature_entries = { 1234 },
        destination = "Elwynn Forest",
    } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Kill should return blocked when no targets found")
    T.assert_nil(ctx.nav and ctx.nav._moved_to,
        "Kill must not navigate on payload.destination — that field does not exist on RuntimeKill")
end

-- ============================================================================
-- execute_loot proximity tests (W3.6)
-- ============================================================================

function M.test_loot_object_in_range()
    local ctx = mock_context({
        is_at_object = function() return true end,
    })
    -- A3: execute_loot must resolve and pass the GAME OBJECT to core.input.loot_object, not the
    -- raw entry id (docs/SylvannasAPI/dev/api/input.md:200 documents loot_object(target)).
    -- Passing the entry id fails silently in Sylvannas (no error), so nothing was ever looted
    -- while this returned "success" and the executor advanced past the objective — this test
    -- used to assert on the entry id, encoding that broken contract as expected (D1).
    local mock_obj = {
        is_valid = function() return true end,
        is_game_object = function() return true end,
        get_entry_id = function() return 1234 end,
        get_position = function() return { x = 1, y = 1, z = 1 } end,
    }
    _G.core.object_manager.get_all_objects = function()
        return { mock_obj }
    end
    _G.core.input = {
        loot_object = function(target)
            _G._last_looted = target
        end,
    }
    local action = { type = "Loot", payload = { object_entry = 1234 } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "success", "Loot should succeed when object in range")
    T.assert_equal(_G._last_looted, mock_obj,
        "loot_object should be called with the resolved game object, not the raw entry id")
end

function M.test_loot_object_out_of_range()
    local ctx = mock_context({
        is_at_object = function() return false end, -- Out of range
    })
    -- Mock get_all_objects for UnitHelper (Sylvannas API compliant)
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_game_object = function() return true end,
                get_entry_id = function() return 1234 end,
                get_position = function() return { x = 30, y = 30, z = 0 } end,
            },
        }
    end
    local action = { type = "Loot", payload = { object_entry = 1234 } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Loot should return blocked when object out of range")
    T.assert_not_nil(ctx.nav and ctx.nav._moved_to, "NavAdapter should navigate to loot object")
end

-- ============================================================================
-- Grind / Escort / Patrol (A5 — PR2b) — none may report "success" for a no-op
-- ============================================================================

function M.test_grind_no_targets_fails()
    -- A5: execute_grind was `return "success" -- Placeholder`, instantly advancing past real
    -- compiler output having killed nothing. With no targets list at all there is nothing to
    -- delegate to execute_kill, so it must report "failed", never "success".
    local ctx = mock_context()
    local action = { type = "Grind", payload = { minimum_kills = 5 } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "failed", "Grind with no target list must fail, not silently succeed")
end

function M.test_escort_waits_until_arrival()
    -- A5: execute_escort must hold ("waiting") while the escortee is alive and the destination
    -- has not been reached — never "success" on the first tick.
    local ctx = mock_context({
        is_at_destination = function() return false end,
    })
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                get_npc_id = function() return 5000 end,
                is_dead = function() return false end,
                get_position = function() return { x = 5, y = 5, z = 0 } end,
            },
        }
    end
    local action = { type = "Escort", payload = {
        npc_entry = 5000,
        destination = { x = 100, y = 100, z = 0 },
    } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "waiting", "Escort should wait, not succeed, before the destination is reached")
end

function M.test_escort_fails_when_escortee_dead()
    local ctx = mock_context()
    _G.core.object_manager.get_all_objects = function()
        return {
            {
                is_valid = function() return true end,
                is_unit = function() return true end,
                get_npc_id = function() return 5000 end,
                is_dead = function() return true end,
                get_position = function() return { x = 5, y = 5, z = 0 } end,
            },
        }
    end
    local action = { type = "Escort", payload = { npc_entry = 5000, destination = { x = 100, y = 100, z = 0 } } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "failed", "Escort must fail, not succeed, when the escortee has died")
end

function M.test_patrol_no_waypoints_fails()
    local ctx = mock_context()
    local action = { type = "Patrol", payload = {} }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "failed", "Patrol with no waypoint list must fail, not silently succeed")
end

function M.test_patrol_succeeds_when_already_at_all_waypoints()
    -- With is_at_destination always true, each waypoint is satisfied immediately; the action
    -- must still walk its own internal index across every waypoint before reporting success.
    local ctx = mock_context({
        is_at_destination = function() return true end,
    })
    local action = { type = "Patrol", payload = {
        waypoints = { { x = 1, y = 1, z = 0 }, { x = 2, y = 2, z = 0 } },
    } }
    local result
    for _ = 1, 5 do
        result = RuntimeAction.execute(action, ctx)
        if result == "success" then break end
    end
    T.assert_equal(result, "success", "Patrol should succeed once every waypoint has been visited")
end

-- ============================================================================
-- NavAdapter wiring in context (W3.3)
-- ============================================================================

function M.test_context_has_nav()
    -- RuntimeProfile.create_context should expose ctx.nav
    -- This is tested at the integration level; here we verify the interface
    local ctx = mock_context()
    T.assert_not_nil(ctx.nav, "Context should have a nav adapter")
    T.assert_true(type(ctx.nav.is_active) == "function", "nav:is_active should be a function")
    T.assert_true(type(ctx.nav.move_to) == "function", "nav:move_to should be a function")
    T.assert_true(type(ctx.nav.poll) == "function", "nav:poll should be a function")
    T.assert_true(type(ctx.nav.stop) == "function", "nav:stop should be a function")
end

-- ============================================================================
-- Run all tests
-- ============================================================================

local tests = {
    test_is_at_destination_exact = M.test_is_at_destination_exact,
    test_is_at_destination_out_of_range = M.test_is_at_destination_out_of_range,
    test_is_at_destination_nil_dest = M.test_is_at_destination_nil_dest,

    test_travel_already_at_destination = M.test_travel_already_at_destination,
    test_travel_starts_navigation = M.test_travel_starts_navigation,
    test_travel_zone_only_no_position = M.test_travel_zone_only_no_position,
    test_travel_polls_for_arrival = M.test_travel_polls_for_arrival,

    test_kill_npc_in_range = M.test_kill_npc_in_range,
    test_kill_npc_dead_and_in_range = M.test_kill_npc_dead_and_in_range,
    test_kill_npc_out_of_range = M.test_kill_npc_out_of_range,
    test_kill_no_targets_found = M.test_kill_no_targets_found,
    test_kill_no_targets_ignores_destination_field = M.test_kill_no_targets_ignores_destination_field,

    test_loot_object_in_range = M.test_loot_object_in_range,
    test_loot_object_out_of_range = M.test_loot_object_out_of_range,

    test_grind_no_targets_fails = M.test_grind_no_targets_fails,
    test_escort_waits_until_arrival = M.test_escort_waits_until_arrival,
    test_escort_fails_when_escortee_dead = M.test_escort_fails_when_escortee_dead,
    test_patrol_no_waypoints_fails = M.test_patrol_no_waypoints_fails,
    test_patrol_succeeds_when_already_at_all_waypoints = M.test_patrol_succeeds_when_already_at_all_waypoints,

    test_context_has_nav = M.test_context_has_nav,
}

function M.run()
    -- Deterministic order: `pairs` varies per run, turning cross-suite state leakage into an
    -- intermittent failure that reads as flaky.
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
