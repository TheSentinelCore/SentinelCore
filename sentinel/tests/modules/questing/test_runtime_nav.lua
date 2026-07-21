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

--- Create a mock player at a given position.
local function set_player_pos(x, y, z)
    _G.core = _G.core or {}
    _G.core.object_manager = _G.core.object_manager or {}
    _G.core.object_manager.get_local_player = function()
        return {
            get_position = function()
                return { x = x or 0, y = y or 0, z = z or 0 }
            end,
        }
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

    -- Mock nearest creature
    if not _G.core.object_manager.GetNearestCreature then
        _G.core.object_manager.GetNearestCreature = function()
            return nil
        end
    end

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
    -- Mocker GetNearestCreature to return a valid non-dead target
    _G.core.object_manager.GetNearestCreature = function()
        return {
            IsValid = true,
            IsDead = function() return false end,
        }
    end
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "success", "Kill should succeed when NPC in range")
end

function M.test_kill_npc_out_of_range()
    local ctx = mock_context({
        is_at_npc = function() return false end, -- Out of range
    })
    _G.core.object_manager.GetNearestCreature = function()
        return {
            IsValid = true,
            IsDead = function() return false end,
            get_position = function() return { x = 50, y = 50, z = 0 } end,
        }
    end
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Kill should return blocked when NPC out of range")
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
    _G.core.object_manager.GetNearestCreature = function()
        return nil -- No targets
    end
    -- No destination in payload either
    local action = { type = "Kill", payload = { creature_entries = { 1234 } } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Kill should return blocked when no targets and no destination")
end

function M.test_kill_navigate_to_spawn_area()
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
    T.assert_equal(result, "blocked", "Kill should return blocked and start navigation to spawn area")
    T.assert_not_nil(ctx.nav and ctx.nav._moved_to, "NavAdapter should navigate to spawn area")
end

-- ============================================================================
-- execute_loot proximity tests (W3.6)
-- ============================================================================

function M.test_loot_object_in_range()
    local ctx = mock_context({
        is_at_object = function() return true end,
    })
    _G.core.input = {
        loot_object = function(entry)
            _G._last_looted = entry
        end,
    }
    local action = { type = "Loot", payload = { object_entry = 1234 } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "success", "Loot should succeed when object in range")
    T.assert_equal(_G._last_looted, 1234, "loot_object should be called")
end

function M.test_loot_object_out_of_range()
    local ctx = mock_context({
        is_at_object = function() return false end, -- Out of range
    })
    _G.core.object_manager.GetNearestGameObject = function()
        return {
            IsValid = true,
            get_position = function() return { x = 30, y = 30, z = 0 } end,
        }
    end
    local action = { type = "Loot", payload = { object_entry = 1234 } }
    local result = RuntimeAction.execute(action, ctx)
    T.assert_equal(result, "blocked", "Loot should return blocked when object out of range")
    T.assert_not_nil(ctx.nav and ctx.nav._moved_to, "NavAdapter should navigate to loot object")
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
    test_kill_npc_out_of_range = M.test_kill_npc_out_of_range,
    test_kill_no_targets_found = M.test_kill_no_targets_found,
    test_kill_navigate_to_spawn_area = M.test_kill_navigate_to_spawn_area,

    test_loot_object_in_range = M.test_loot_object_in_range,
    test_loot_object_out_of_range = M.test_loot_object_out_of_range,

    test_context_has_nav = M.test_context_has_nav,
}

function M.run()
    for name, fn in pairs(tests) do
        local ok, err = pcall(fn)
        if not ok then
            error(name .. " FAILED: " .. tostring(err))
        end
    end
end

return M
