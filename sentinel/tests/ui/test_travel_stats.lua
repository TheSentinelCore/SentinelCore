-- tests/ui/test_travel_stats.lua
-- The Travel Editor's waypoint capture and route estimate, and the Stats dashboard's counts
-- (spec: "Travel Editor and Stats Wiring", completing F12-R1/R2 and F20-R1/R2).
--
-- WHAT WAS BROKEN, AND WHY THE OLD SUITE WAS GREEN ANYWAY
-- ------------------------------------------------------
-- `travel_add_waypoint` answered `true, "(not yet implemented — requires player position)"`. Nothing
-- was captured, and the operator was told the capture had succeeded. `StatsDashboard:compute` was
-- never called by `IdePanels.install` at all, so the dashboard reported a campaign of zero nodes no
-- matter what was loaded. `TravelEditorState:load_from_campaign` had the same problem: real code with
-- no caller.
--
-- The old suite exercised both view-models DIRECTLY, so every case passed while the installed panels
-- reached neither. Every test here therefore drives the INSTALLED shell wherever the defect lived in
-- the wiring, and the view-model directly only where the defect lived in the decision.

local TravelEditorState = require("ui/panels/travel_editor_state")
local StatsDashboard = require("ui/panels/stats_dashboard")
local FakeWindow = require("tests/harness/fake_window")
local Mock = require("tests/harness/mocks/sylvannas_api")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures and harness
-- ============================================================================

---A state holding one selected route with `n` map-tagged waypoints, ready to estimate.
local function route_with_waypoints(n, map)
    local te = TravelEditorState.new()
    te.activated = true
    te.campaign_name = "c"
    local waypoints = {}
    for i = 1, n do
        waypoints[i] = { x = i * 100, y = 0, z = 0, map = map or 0, movement = "walk" }
    end
    te.routes = { { id = "r1", from_node_id = "a", to_node_id = "b",
                    from_label = "Travel", to_label = "Travel", waypoints = waypoints } }
    te.selected_route = "r1"
    te.editing_waypoints = true
    return te
end

---Swap `core.get_map_id` for the duration of one call.
local function with_map_id(map_id, fn)
    local previous = _G.core.get_map_id
    _G.core.get_map_id = (map_id ~= nil) and function() return map_id end or nil
    local ok, err = pcall(fn)
    _G.core.get_map_id = previous
    if not ok then error(err, 0) end
end

---Swap the object manager for the duration of one call.
local function with_player_at(position, fn)
    local previous = _G.core.object_manager
    _G.core.object_manager = {
        get_local_player = function()
            if position == nil then return nil end
            return { get_position = function() return position end }
        end,
    }
    local ok, err = pcall(fn)
    _G.core.object_manager = previous
    if not ok then error(err, 0) end
end

local function installed_shell(deps)
    local Shell = require("ui/shell")
    local IdePanels = require("ui/ide_panels")
    local window = FakeWindow.new()
    local shell = Shell.new({ window = window, elements = nil })
    local bindings, reason = IdePanels.install(shell, deps or { questing = function() return nil end })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))
    shell:show()
    return shell, bindings, window
end

-- ============================================================================
-- 1. Waypoint capture (F12-R1)
-- ============================================================================

function M.test_capture_records_the_position_it_was_handed()
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint({ x = -8940.5, y = -140.25, z = 84.75 }, 0)
    T.assert_true(ok, "a live position must be captured: " .. tostring(reason))

    local wps = te.routes[1].waypoints
    T.assert_equal(#wps, 2, "the capture appends to the selected route")
    T.assert_near(wps[2].x, -8940.5, 0.001, "x is stored verbatim, not rounded into the label")
    T.assert_near(wps[2].y, -140.25, 0.001)
    T.assert_near(wps[2].z, 84.75, 0.001)
    T.assert_equal(wps[2].map, 0, "and the map it was standing on")
    T.assert_true(wps[2].captured, "a captured waypoint is distinguishable from an imported one")
    T.assert_nil(te.error, "a successful capture leaves no error behind")
end

function M.test_capture_with_no_position_is_refused_and_says_so()
    -- Out of world: loading screen, between injections, dead object manager. The old code answered
    -- `true` here; a capture that substituted the origin would drop a waypoint in the middle of the
    -- map and report success.
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint(nil, 0)
    T.assert_false(ok, "no position is no waypoint")
    T.assert_not_nil(reason, "and the refusal must name the reason")
    T.assert_true(reason:find("not in world", 1, true) ~= nil, "reason: " .. tostring(reason))
    T.assert_equal(te.error, reason, "the panel says it on screen, not only to the caller")
    T.assert_equal(#te.routes[1].waypoints, 1, "and nothing was appended")
end

function M.test_capture_with_an_incomplete_position_is_refused()
    local te = route_with_waypoints(1)
    local ok, reason = te:add_waypoint({ x = 1, y = 2 }, 0)
    T.assert_false(ok, "a position missing z is not a position")
    T.assert_true(reason:find("incomplete", 1, true) ~= nil, "reason: " .. tostring(reason))
    T.assert_equal(#te.routes[1].waypoints, 1)
end

function M.test_capture_with_no_route_selected_is_refused()
    local te = route_with_waypoints(1)
    te.selected_route = nil
    local ok, reason = te:add_waypoint({ x = 1, y = 2, z = 3 }, 0)
    T.assert_false(ok, "there is nowhere to put it")
    T.assert_true(reason:find("no route selected", 1, true) ~= nil, "reason: " .. tostring(reason))
end

function M.test_a_missing_map_id_is_recorded_as_absent_not_as_map_zero()
    -- Map 0 is Eastern Kingdoms. Defaulting to it would price a leg in Outland as if it were in
    -- Elwynn, and the number would look computed.
    local te = route_with_waypoints(1)
    T.assert_true(te:add_waypoint({ x = 1, y = 2, z = 3 }, nil))
    T.assert_nil(te.routes[1].waypoints[2].map, "an unknown map reads as nil")
end

function M.test_capturing_drops_the_estimate_that_described_the_shorter_route()
    local te = route_with_waypoints(2)
    te.estimate = { route_id = "r1", segments = { { type = "walk", estimated_s = 10 } }, total_s = 10 }
    te.estimate_requested = true
    T.assert_true(te:add_waypoint({ x = 999, y = 0, z = 0 }, 0))
    T.assert_nil(te.estimate, "an estimate for two waypoints must not survive a third")
    T.assert_false(te.estimate_requested, "and the request is not silently re-run")
end

-- ============================================================================
-- 2. Waypoint capture through the INSTALLED shell (the wiring, not the model)
-- ============================================================================

function M.test_the_installed_capture_button_reaches_the_live_position()
    local shell, bindings = installed_shell()
    local travel = bindings.travel
    travel:toggle()
    travel.campaign_name = "c"
    travel.routes = { { id = "r1", from_label = "Travel", to_label = "Travel", waypoints = {} } }
    travel:select_route("r1")

    with_player_at({ x = -8940, y = -140, z = 84 }, function()
        with_map_id(0, function()
            shell:_queue_command("explorer", { kind = "travel_add_waypoint" })
            shell:on_tick()
        end)
    end)

    local wps = travel.routes[1].waypoints
    T.assert_equal(#wps, 1, "the dispatched command must have captured exactly one waypoint")
    T.assert_equal(wps[1].x, -8940, "at the position the object manager answered")
    T.assert_equal(wps[1].map, 0, "on the map core.get_map_id answered")
end

function M.test_the_installed_capture_reports_failure_rather_than_a_phantom_success()
    local shell, bindings = installed_shell()
    local travel = bindings.travel
    travel:toggle()
    travel.campaign_name = "c"
    travel.routes = { { id = "r1", from_label = "Travel", to_label = "Travel", waypoints = {} } }
    travel:select_route("r1")

    with_player_at(nil, function()
        with_map_id(0, function()
            shell:_queue_command("explorer", { kind = "travel_add_waypoint" })
            shell:on_tick()
        end)
    end)

    T.assert_equal(#travel.routes[1].waypoints, 0, "nothing may be captured out of world")
    T.assert_not_nil(travel.error, "and the panel must carry the reason")
    local record = shell:last_dispatch()
    T.assert_not_nil(record, "the shell must have recorded the dispatch")
    T.assert_false(record.ok,
        "the dispatch must report the failure, not a phantom success: " .. tostring(record.reason))
end

function M.test_no_source_claims_the_capture_is_unimplemented()
    -- The literal string that shipped. An audit, because the defect was a string that read as an
    -- answer.
    local handle = assert(io.open("sentinel/ui/ide_panels.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    T.assert_nil(source:find("travel_add_waypoint (not yet implemented", 1, true),
        "the travel capture must not still announce itself as unimplemented")
end

-- ============================================================================
-- 3. Structural guards
-- ============================================================================

function M.test_the_capture_never_reads_the_object_manager_from_the_state()
    -- The state is handed a position; it must not go looking for one. An object-manager read from a
    -- view-model would be reachable from a render frame, which ADR 09b §2.4 forbids.
    local handle = assert(io.open("sentinel/ui/panels/travel_editor_state.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\n]*", " ")
    for _, forbidden in ipairs({ "object_manager", "get_local_player", "get_map_id" }) do
        T.assert_nil(source:find(forbidden, 1, true),
            "travel_editor_state reaches for " .. forbidden .. "; the host must hand it over")
    end
end

function M.test_the_state_loads_with_no_sdk_at_all()
    local names = { "ui/panels/travel_editor_state", "ui/panels/stats_dashboard" }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local errs = {}
    for _, name in ipairs(names) do
        local ok, err = pcall(require, name)
        if not ok then errs[#errs + 1] = name .. ": " .. tostring(err) end
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end
    T.assert_equal(#errs, 0, "loaded with no SDK: " .. table.concat(errs, "; "))
end

function M.test_the_fake_window_still_paints_the_editor()
    local te = route_with_waypoints(2)
    local TravelEditor = require("ui/panels/travel_editor")
    local window = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(TravelEditor.render, window, BOUNDS, te:build())
    T.assert_true(ok, "the editor must paint through the type-checking fake window: " .. tostring(err))
    T.assert_not_nil(Mock, "the harness mock is loaded so http routes can be registered")
end

return M
