-- tests/ui/test_database_panel.lua
-- The Database panel's contract (Phase 4, PR-4a/4b).
--
-- Tests cover: state transitions (scan, select, grind), build output shape,
-- command routing, and the structural guards from ADR 09b §2.1.

local DatabaseState = require("ui/panels/database_state")
local Database = require("ui/panels/database")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures
-- ============================================================================

local function sample_mock_results()
    return {
        { entry = 567, name = "Wolf",          count = 6, min_level = 5, max_level = 7, avg_distance = 12, kind = "creature" },
        { entry = 568, name = "Boar",          count = 4, min_level = 4, max_level = 6, avg_distance = 18, kind = "creature" },
        { entry = 1735, name = "Peacebloom",   count = 5, min_level = 0, max_level = 0, avg_distance = 25, kind = "herb" },
        { entry = 1737, name = "Copper Vein",  count = 2, min_level = 0, max_level = 0, avg_distance = 30, kind = "mining" },
    }
end

local function sample_npc_detail()
    return {
        entry = 567,
        name = "Wolf",
        faction = "Wild",
        roles = { "Beast" },
        positions = {
            { map = 0, x = -8932, y = -137, z = 82 },
            { map = 0, x = -8940, y = -140, z = 83 },
            { map = 0, x = -8920, y = -130, z = 81 },
        },
    }
end

-- ============================================================================
-- 1. DatabaseState: construction and defaults
-- ============================================================================

function M.test_new_state_has_defaults()
    local state = DatabaseState.new()
    T.assert_equal(#state.scan_results, 0, "scan_results defaults to empty")
    T.assert_nil(state.selected_entry, "selected_entry defaults to nil")
    T.assert_nil(state.selected_detail, "selected_detail defaults to nil")
    T.assert_equal(#state.spawn_points, 0, "spawn_points defaults to empty")
    T.assert_equal(state.scan_range, 50, "scan_range defaults to 50")
    T.assert_nil(state.scan_filter, "scan_filter defaults to nil")
    T.assert_equal(state.scan_mode, "nearby", "scan_mode defaults to nearby")
    T.assert_equal(state.active_tab, "scanner", "active_tab defaults to scanner")
    T.assert_nil(state.grinding_npc_entry, "grinding_npc_entry defaults to nil")
    T.assert_nil(state.grinding_result, "grinding_result defaults to nil")
    T.assert_false(state.loading, "loading defaults to false")
    T.assert_nil(state.error, "error defaults to nil")
    T.assert_true(state._dirty, "starts dirty for initial refresh")
end

-- ============================================================================
-- 2. DatabaseState: mutators
-- ============================================================================

function M.test_set_tab_switches_tab()
    local state = DatabaseState.new()
    state._dirty = false
    state:set_tab("grinding")
    T.assert_equal(state.active_tab, "grinding")
    T.assert_true(state._dirty, "set_tab marks dirty")

    state._dirty = false
    state:set_tab("scanner")
    T.assert_equal(state.active_tab, "scanner")
end

function M.test_set_tab_ignores_same_tab()
    local state = DatabaseState.new()
    state._dirty = false
    state:set_tab("scanner")
    T.assert_false(state._dirty, "same tab must not mark dirty")
end

function M.test_set_scan_range_updates_range()
    local state = DatabaseState.new()
    state:set_scan_range(75)
    T.assert_equal(state.scan_range, 75)
    T.assert_true(state._dirty)
end

function M.test_set_scan_range_clamps_invalid()
    local state = DatabaseState.new()
    state:set_scan_range(0)
    T.assert_equal(state.scan_range, 50, "range 0 is rejected")
    state:set_scan_range(-5)
    T.assert_equal(state.scan_range, 50, "negative range is rejected")
end

function M.test_set_scan_range_ignores_same()
    local state = DatabaseState.new()
    state.scan_range = 75
    state._dirty = false
    state:set_scan_range(75)
    T.assert_false(state._dirty, "same range must not mark dirty")
end

function M.test_set_scan_filter_updates_filter()
    local state = DatabaseState.new()
    state:set_scan_filter("herb")
    T.assert_equal(state.scan_filter, "herb")
    T.assert_true(state._dirty)
end

function M.test_set_scan_filter_ignores_same()
    local state = DatabaseState.new()
    state.scan_filter = "herb"
    state._dirty = false
    state:set_scan_filter("herb")
    T.assert_false(state._dirty)
end

function M.test_set_scan_mode_updates_mode()
    local state = DatabaseState.new()
    state:set_scan_mode("manual")
    T.assert_equal(state.scan_mode, "manual")
    T.assert_true(state._dirty)
end

function M.test_request_scan_sets_pending_and_clears_previous()
    local state = DatabaseState.new()
    state.scan_results = sample_mock_results()
    state.selected_entry = 567
    state.request_scan(state)
    T.assert_equal(#state.scan_results, 0, "request_scan clears previous results")
    T.assert_nil(state.selected_entry, "request_scan clears selection")
    T.assert_true(state.loading, "request_scan sets loading")
    T.assert_true(state._pending_scan, "request_scan sets pending flag")
    T.assert_true(state._dirty, "request_scan marks dirty")
end

function M.test_select_entry_updates_selection_and_marks_pending()
    local state = DatabaseState.new()
    state:select_entry(567)
    T.assert_equal(state.selected_entry, 567)
    T.assert_true(state.loading, "select_entry sets loading")
    T.assert_true(state._pending_detail, "select_entry sets pending detail flag")
    T.assert_true(state._dirty)
end

function M.test_select_entry_clears_previous_detail()
    local state = DatabaseState.new()
    state.selected_detail = { name = "Old" }
    state:select_entry(568)
    T.assert_nil(state.selected_detail, "select_entry clears previous detail")
    T.assert_equal(state.selected_entry, 568)
end

function M.test_select_entry_ignores_same_entry()
    local state = DatabaseState.new()
    state.selected_entry = 567
    state._dirty = false
    state:select_entry(567)
    T.assert_false(state._dirty, "same entry must not mark dirty")
end

function M.test_set_grinding_npc_updates_entry()
    local state = DatabaseState.new()
    state:set_grinding_npc(567)
    T.assert_equal(state.grinding_npc_entry, 567)
    T.assert_true(state._dirty)
end

function M.test_set_grinding_zone_updates_zone()
    local state = DatabaseState.new()
    state:set_grinding_zone("Elwynn Forest")
    T.assert_equal(state.grinding_zone, "Elwynn Forest")
    T.assert_true(state._dirty)
end

function M.test_request_grind_sets_pending()
    local state = DatabaseState.new()
    state:set_grinding_npc(567)
    state._dirty = false
    state:request_grind()
    T.assert_true(state.loading, "request_grind sets loading")
    T.assert_true(state._pending_grind, "request_grind sets pending flag")
    T.assert_true(state._dirty)
end

function M.test_request_grind_refuses_without_entry()
    local state = DatabaseState.new()
    state:request_grind()
    T.assert_not_nil(state.error, "request_grind without entry sets error")
    T.assert_false(state._pending_grind, "request_grind without entry skips pending")
end

-- ============================================================================
-- 3. DatabaseState: execute_scan (spec: No Mock Data in Production Paths)
-- ============================================================================
--
-- These three used to assert that a scan with NO source produced six results. That was the defect
-- verbatim: `_mock_scan` ran in the injector too, so an operator with no scan source saw invented
-- wolves and had no way to tell them from real ones.

--- Install a scan source for the duration of one test. `dbg` is a global the debug plugin publishes;
--- the state reads it the same way in-game.
local function with_scan_source(entities, fn)
    local previous = _G.dbg
    local seen = {}
    _G.dbg = {
        nearby = function(range, filter)
            seen.range, seen.filter = range, filter
            return entities
        end,
    }
    local ok, err = pcall(fn, seen)
    _G.dbg = previous
    if not ok then error(err, 0) end
end

function M.test_execute_scan_without_a_source_errors_instead_of_inventing_results()
    local state = DatabaseState.new()
    state:request_scan()
    state:execute_scan(nil)
    T.assert_equal(#state.scan_results, 0,
        "a scan with nothing to scan with must produce NO results -- fabricated spawns are "
        .. "indistinguishable from real ones once they are on screen")
    T.assert_not_nil(state.error, "and it must say so")
    T.assert_true(tostring(state.error):find("spawn", 1, true) ~= nil,
        "the message must name the missing source, got: " .. tostring(state.error))
    T.assert_false(state.loading, "execute_scan clears loading")
    T.assert_false(state._pending_scan, "execute_scan clears pending scan")
end

function M.test_execute_scan_aggregates_what_the_source_returns()
    local state = DatabaseState.new()
    with_scan_source({
        { entry = 567, name = "Wolf", level = 5, distance = 10, type = "creature" },
        { entry = 567, name = "Wolf", level = 7, distance = 20, type = "creature" },
    }, function()
        state:request_scan()
        state:execute_scan(nil)
    end)
    T.assert_equal(#state.scan_results, 1, "two spawns of one entry group into one row")
    T.assert_equal(state.scan_results[1].count, 2, "with a real count")
    T.assert_nil(state.error, "a scan that answered is not an error")
end

function M.test_execute_scan_hands_the_filter_to_the_source()
    local state = DatabaseState.new()
    state:set_scan_filter("herb")
    with_scan_source({}, function(seen)
        state:request_scan()
        state:execute_scan(nil)
        T.assert_equal(seen.filter, "herb", "the filter must reach the scan source")
        T.assert_equal(seen.range, 50, "along with the range")
    end)
    T.assert_equal(#state.scan_results, 0, "an empty answer stays empty")
end

-- ============================================================================
-- 4. DatabaseState: execute_load_detail
-- ============================================================================

function M.test_execute_load_detail_uses_query_client()
    local state = DatabaseState.new()
    state:select_entry(567)

    local fake_qc = {
        get_npc = function(_, entry)
            if entry == 567 then return sample_npc_detail() end
            return nil
        end,
        get_object = function() return nil end,
    }

    state:execute_load_detail(fake_qc)
    T.assert_not_nil(state.selected_detail, "detail must be loaded")
    T.assert_equal(state.selected_detail.name, "Wolf")
    T.assert_equal(#state.spawn_points, 3, "spawn_points from detail positions")
end

function M.test_execute_load_detail_clears_loading()
    local state = DatabaseState.new()
    state:select_entry(567)
    state:execute_load_detail(nil)
    T.assert_false(state.loading, "execute_load_detail clears loading")
    T.assert_false(state._pending_detail, "clears pending detail flag")
end

function M.test_execute_load_detail_no_query_client()
    local state = DatabaseState.new()
    state:select_entry(567)
    state:execute_load_detail(nil)
    T.assert_nil(state.selected_detail, "no query client -> no detail")
end

-- ============================================================================
-- 5. DatabaseState: execute_grind (spec: No Mock Data in Production Paths)
-- ============================================================================

function M.test_execute_grind_without_a_query_client_errors_instead_of_inventing_an_estimate()
    local state = DatabaseState.new()
    state:set_grinding_npc(567)
    state:set_grinding_zone("Elwynn")
    state:request_grind()
    state:execute_grind(nil)

    T.assert_nil(state.grinding_result,
        "a grind estimate with no server behind it must not exist -- it used to read a flat "
        .. "12,450 XP/hour, which is a route the operator walks for an hour to disprove")
    T.assert_not_nil(state.error, "and the missing source must be named")
    T.assert_false(state.loading, "execute_grind clears loading")
    T.assert_false(state._pending_grind, "execute_grind clears pending grind")
end

function M.test_no_mock_fabricator_survives_on_the_state()
    -- The sweep, held by a test rather than by a comment: a fixture reachable from an installed
    -- panel is a fixture that reaches the injector, and both of these did.
    local state = DatabaseState.new()
    T.assert_nil(state._mock_scan, "_mock_scan must not exist on production state")
    T.assert_nil(state._mock_grind_result, "_mock_grind_result must not exist on production state")
end

function M.test_execute_grind_with_query_client()
    local state = DatabaseState.new()
    state:set_grinding_npc(567)
    state:set_grinding_zone("Elwynn")

    local fake_qc = {
        get_npc = function(_, entry)
            if entry == 567 then return sample_npc_detail() end
            return nil
        end,
    }

    state:request_grind()
    state:execute_grind(fake_qc)

    T.assert_not_nil(state.grinding_result, "grind with QC must produce result")
    T.assert_equal(state.grinding_result.spawn_density, 3, "3 positions in sample")
    T.assert_true(state.grinding_result.xp_per_hour > 0, "xp per hour estimated")
    T.assert_equal(state.grinding_result.route.zone, "Elwynn", "zone from input")
end

function M.test_execute_grind_without_entry()
    local state = DatabaseState.new()
    state:execute_grind(nil)
    T.assert_not_nil(state.error, "no entry -> error set")
end

function M.test_execute_grind_clears_loading()
    local state = DatabaseState.new()
    state:set_grinding_npc(567)
    state.loading = true
    state._pending_grind = true
    state:execute_grind(nil)
    T.assert_false(state.loading, "execute_grind clears loading")
    T.assert_false(state._pending_grind, "clears pending grind flag")
end

-- ============================================================================
-- 6. Build: view model shape
-- ============================================================================

function M.test_build_returns_correct_keys()
    local state = DatabaseState.new()
    local view = state:build()
    T.assert_equal(type(view.scan_results), "table", "scan_results must be a table")
    T.assert_equal(type(view.spawn_points), "table", "spawn_points must be a table")
    T.assert_equal(type(view.loading), "boolean", "loading must be a boolean")
    T.assert_equal(type(view.active_tab), "string", "active_tab must be a string")
    T.assert_equal(type(view.scan_range), "number", "scan_range must be a number")
    T.assert_true(view.selected_entry == nil or type(view.selected_entry) == "number",
        "selected_entry must be nil or number")
    T.assert_true(view.selected_detail == nil or type(view.selected_detail) == "table",
        "selected_detail must be nil or table")
    T.assert_true(view.grinding_result == nil or type(view.grinding_result) == "table",
        "grinding_result must be nil or table")
    T.assert_true(view.error == nil or type(view.error) == "string",
        "error must be nil or string")
end

function M.test_build_with_scan_results()
    local state = DatabaseState.new()
    state.scan_results = sample_mock_results()
    local view = state:build()
    T.assert_equal(#view.scan_results, 4, "all scan results in view")
    T.assert_equal(view.scan_results[1].name, "Wolf")
end

function M.test_build_with_grinding_result()
    local state = DatabaseState.new()
    state.active_tab = "grinding"
    state.grinding_npc_entry = 567
    state.grinding_zone = "Elwynn"
    state.grinding_result = {
        spawn_density = 24, xp_per_hour = 12450, gold_per_hour = 3.45,
        kills_per_min = 8.2, safe_spots = 3, pull_radius = 18,
        route = { zone = "Elwynn", waypoints = {} },
    }
    local view = state:build()
    T.assert_equal(view.active_tab, "grinding")
    T.assert_not_nil(view.grinding_result)
    T.assert_equal(view.grinding_result.xp_per_hour, 12450)
end

-- ============================================================================
-- 7. Build plan: items from view
-- ============================================================================

function M.test_build_plan_creates_items()
    local state = DatabaseState.new()
    local view = state:build()
    local plan = DatabaseState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan, "plan must exist")
    T.assert_not_nil(plan.items, "plan must have items")
    T.assert_true(#plan.items > 0, "plan must produce at least one item")
end

function M.test_build_plan_includes_tab_chips()
    local view = { active_tab = "scanner", scan_results = {}, scan_range = 50,
                   scan_filter = nil, scan_mode = "nearby", loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    local has_scanner_tab = false
    local has_grinding_tab = false
    for _, item in ipairs(plan.items) do
        if item.id == "tab_scanner" then has_scanner_tab = true end
        if item.id == "tab_grinding" then has_grinding_tab = true end
    end
    T.assert_true(has_scanner_tab, "plan must have scanner tab chip")
    T.assert_true(has_grinding_tab, "plan must have grinding tab chip")
end

function M.test_build_plan_with_scan_results_shows_results()
    local view = { active_tab = "scanner", scan_results = sample_mock_results(),
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    local has_list_row = false
    for _, item in ipairs(plan.items) do
        if item.kind == "list_row" then has_list_row = true end
    end
    T.assert_true(has_list_row, "scan results must include list_row items")
end

function M.test_build_plan_with_selected_entry_shows_action_buttons()
    local view = { active_tab = "scanner", scan_results = sample_mock_results(),
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = 567, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    local has_add_kill = false
    local has_view_detail = false
    for _, item in ipairs(plan.items) do
        if item.id and item.id:match("^add_as_kill:") then has_add_kill = true end
        if item.id and item.id:match("^view_detail:") then has_view_detail = true end
    end
    T.assert_true(has_add_kill, "selected entry must show Add as Kill button")
    T.assert_true(has_view_detail, "selected entry must show View Detail button")
end

function M.test_build_plan_with_grinding_tab_shows_grinding_controls()
    local view = { active_tab = "grinding", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = 567, grinding_zone = "Elwynn", grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    local has_generate = false
    for _, item in ipairs(plan.items) do
        if item.id == "generate_grind" then
            has_generate = true
            T.assert_false(item.disabled, "generate button must be enabled with entry")
        end
    end
    T.assert_true(has_generate, "grinding tab must show Generate button")
end

function M.test_build_plan_grinding_button_disabled_without_entry()
    local view = { active_tab = "grinding", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    for _, item in ipairs(plan.items) do
        if item.id == "generate_grind" then
            T.assert_true(item.disabled, "generate button must be disabled without entry")
        end
    end
end

function M.test_build_plan_shows_grinding_result()
    local view = { active_tab = "grinding", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = 567, grinding_zone = "Elwynn",
                   grinding_result = {
                       spawn_density = 24, xp_per_hour = 12450, gold_per_hour = 3.45,
                       kills_per_min = 8.2, safe_spots = 3, pull_radius = 18,
                       route = { zone = "Elwynn", waypoints = {} },
                   } }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    -- Should have section_header for grinding estimate
    local has_section = false
    for _, item in ipairs(plan.items) do
        if item.kind == "section_header" then has_section = true end
    end
    T.assert_true(has_section, "grinding result must show section header")
end

function M.test_build_plan_empty_scan_shows_empty_state()
    local view = { active_tab = "scanner", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    local has_empty = false
    for _, item in ipairs(plan.items) do
        if item.kind == "empty_state" then has_empty = true end
    end
    T.assert_true(has_empty, "empty scan must show empty_state")
end

function M.test_build_plan_loading_state()
    local view = { active_tab = "scanner", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = true, error = nil,
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "loading state must produce items")
end

function M.test_build_plan_error_state()
    local view = { active_tab = "scanner", scan_results = {},
                   scan_range = 50, scan_filter = nil, scan_mode = "nearby",
                   loading = false, error = "something broke",
                   selected_entry = nil, selected_detail = nil, spawn_points = {},
                   grinding_npc_entry = nil, grinding_zone = nil, grinding_result = nil }
    local plan = DatabaseState.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "error state must produce items")
end

-- ============================================================================
-- 8. Reduce: command routing
-- ============================================================================

function M.test_reduce_tab_switches()
    local cmd = DatabaseState.reduce("tab_scanner")
    T.assert_not_nil(cmd, "tab_scanner must produce a command")
    T.assert_equal(cmd.kind, "set_tab")
    T.assert_equal(cmd.tab, "scanner")

    cmd = DatabaseState.reduce("tab_grinding")
    T.assert_equal(cmd.kind, "set_tab")
    T.assert_equal(cmd.tab, "grinding")
end

function M.test_reduce_scan()
    local cmd = DatabaseState.reduce("scan")
    T.assert_not_nil(cmd, "scan must produce a command")
    T.assert_equal(cmd.kind, "scan")
end

function M.test_reduce_cycle_scan_mode()
    local cmd = DatabaseState.reduce("cycle_scan_mode")
    T.assert_not_nil(cmd, "cycle_scan_mode must produce a command")
    T.assert_equal(cmd.kind, "cycle_scan_mode")
end

function M.test_reduce_cycle_range()
    local cmd = DatabaseState.reduce("cycle_range")
    T.assert_not_nil(cmd, "cycle_range must produce a command")
    T.assert_equal(cmd.kind, "cycle_range")
end

function M.test_reduce_filter()
    local cmd = DatabaseState.reduce("filter:herb")
    T.assert_not_nil(cmd, "filter:herb must produce a command")
    T.assert_equal(cmd.kind, "set_filter")
    T.assert_equal(cmd.filter, "herb")

    cmd = DatabaseState.reduce("filter:all")
    T.assert_equal(cmd.kind, "set_filter")
    T.assert_nil(cmd.filter, "filter:all maps filter to nil")
end

function M.test_reduce_select_entry()
    local cmd = DatabaseState.reduce("select_entry:567")
    T.assert_not_nil(cmd, "select_entry must produce a command")
    T.assert_equal(cmd.kind, "select_entry")
    T.assert_equal(cmd.entry, 567)
end

function M.test_reduce_add_as_kill()
    local cmd = DatabaseState.reduce("add_as_kill:567")
    T.assert_not_nil(cmd, "add_as_kill must produce a command")
    T.assert_equal(cmd.kind, "add_as_kill")
    T.assert_equal(cmd.entry, 567)
end

function M.test_reduce_view_detail()
    local cmd = DatabaseState.reduce("view_detail:567")
    T.assert_not_nil(cmd, "view_detail must produce a command")
    T.assert_equal(cmd.kind, "view_detail")
    T.assert_equal(cmd.entry, 567)
end

function M.test_reduce_generate_grind()
    local cmd = DatabaseState.reduce("generate_grind")
    T.assert_not_nil(cmd, "generate_grind must produce a command")
    T.assert_equal(cmd.kind, "generate_grind")
end

function M.test_reduce_grind_entry()
    local cmd = DatabaseState.reduce("grind_entry")
    T.assert_not_nil(cmd, "grind_entry must produce a command")
    T.assert_equal(cmd.kind, "edit_grind_entry")
end

function M.test_reduce_grind_zone()
    local cmd = DatabaseState.reduce("grind_zone")
    T.assert_not_nil(cmd, "grind_zone must produce a command")
    T.assert_equal(cmd.kind, "edit_grind_zone")
end

function M.test_reduce_nil_returns_nil()
    T.assert_nil(DatabaseState.reduce(nil), "nil action must return nil")
end

function M.test_reduce_unknown_returns_nil()
    T.assert_nil(DatabaseState.reduce("nonexistent"), "unknown action must return nil")
end

-- ============================================================================
-- 9. Render: the panel draws and returns commands
-- ============================================================================

function M.test_render_creates_items_and_returns_plan()
    local state = DatabaseState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local command, plan = Database.render(fake, BOUNDS, view)
    T.assert_not_nil(plan, "render must return a plan")
    T.assert_not_nil(plan.items, "plan must have items")
    T.assert_true(#plan.items > 0, "plan must have at least one item")
end

function M.test_render_handles_empty_state_gracefully()
    local state = DatabaseState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Database.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with empty state must not throw: " .. tostring(err))
end

function M.test_render_with_scan_results()
    local state = DatabaseState.new()
    state.scan_results = sample_mock_results()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Database.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with scan results must not throw: " .. tostring(err))
end

function M.test_render_with_selection()
    local state = DatabaseState.new()
    state.scan_results = sample_mock_results()
    state:select_entry(567)
    state.selected_detail = sample_npc_detail()
    state.loading = false
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Database.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with selection must not throw: " .. tostring(err))
end

function M.test_render_with_grinding_tab()
    local state = DatabaseState.new()
    state.active_tab = "grinding"
    state.grinding_npc_entry = 567
    state.grinding_zone = "Elwynn"
    state.grinding_result = {
        spawn_density = 24, xp_per_hour = 12450, gold_per_hour = 3.45,
        kills_per_min = 8.2, safe_spots = 3, pull_radius = 18,
        route = { zone = "Elwynn", waypoints = {} },
    }
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Database.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with grinding result must not throw: " .. tostring(err))
end

-- ============================================================================
-- 10. Display helpers
-- ============================================================================

function M.test_fmt_num_formats_thousands()
    T.assert_equal(DatabaseState._fmt_num(0), "0")
    T.assert_equal(DatabaseState._fmt_num(100), "100")
    T.assert_equal(DatabaseState._fmt_num(1000), "1,000")
    T.assert_equal(DatabaseState._fmt_num(12450), "12,450")
    T.assert_equal(DatabaseState._fmt_num(1000000), "1,000,000")
    T.assert_equal(DatabaseState._fmt_num(nil), "0")
end

function M.test_fmt_gold_formats_currency()
    T.assert_equal(DatabaseState._fmt_gold(0), "0g 0s")
    T.assert_equal(DatabaseState._fmt_gold(3.45), "3g 45s")
    T.assert_equal(DatabaseState._fmt_gold(12), "12g 0s")
    T.assert_equal(DatabaseState._fmt_gold(0.5), "0g 50s")
    T.assert_equal(DatabaseState._fmt_gold(100.99), "100g 99s")
end

-- ============================================================================
-- 11. Structural guards — the failures that pass offline and break in the injector
-- ============================================================================

local function source_of(path)
    local handle = assert(io.open(path, "r"), path .. " must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

local RENDER_SOURCE = "sentinel/ui/panels/database.lua"
local STATE_SOURCE = "sentinel/ui/panels/database_state.lua"

function M.test_the_source_audit_actually_reads_code()
    local source = source_of(RENDER_SOURCE)
    T.assert_true(source:find("function Database.render", 1, true) ~= nil,
        "the stripped source must still contain the render function")
end

function M.test_the_render_layer_contains_no_decision_logic()
    -- ADR 09b §2.1. A branch inside a render callback cannot be reached by any offline test, so
    -- the rule is enforced structurally rather than by review.
    local source = source_of(RENDER_SOURCE)
    T.assert_nil(source:find("%f[%w]if%f[%W]"), "database.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]elseif%f[%W]"), "database.lua has elseif; move it to the view-model")
    T.assert_nil(source:find("%f[%w]while%f[%W]"), "database.lua loops on a condition")
end

function M.test_the_panel_never_constructs_a_menu_element()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        T.assert_nil(source_of(path):find("core%.menu%."),
            path .. " touches core.menu.*, which Sylvannas allows only in the tick callback")
    end
end

function M.test_no_menu_element_is_constructed_while_rendering()
    local saved = _G.core and _G.core.menu or nil
    if _G.core then
        _G.core.menu = setmetatable({}, {
            __index = function() error("core.menu was touched during render") end,
        })
    end
    local view = DatabaseState.new():build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Database.render, fake, BOUNDS, view)
    if _G.core then _G.core.menu = saved end
    T.assert_true(ok, "the panel constructed a menu element during render: " .. tostring(err))
end

function M.test_the_panel_performs_no_io_on_the_render_path()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        local source = source_of(path)
        for _, forbidden in ipairs({ "http_get", "http_post", "read_data_file", "write_data_file",
                                     "read_dir", "object_manager", "get_all_objects" }) do
            T.assert_nil(source:find(forbidden, 1, true),
                path .. " reaches for " .. forbidden .. " on the render path")
        end
    end
end

function M.test_the_panel_hardcodes_no_colour_and_no_spacing()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        local source = source_of(path)
        T.assert_nil(source:find("[Cc]olor%.new%s*%("), path .. " constructs a raw colour")
    end
end

function M.test_the_panel_loads_and_renders_with_no_sylvanns_api_present()
    local names = {
        "ui/panels/database", "ui/panels/database_state",
        "ui/theme", "ui/widgets",
    }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local ok, panel = pcall(require, "ui/panels/database")
    local rendered, err = true, nil
    if ok then
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        local state = DatabaseState.new()
        rendered, err = pcall(panel.render, fake, BOUNDS, state:build())
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok, "the panel failed to load with no SDK present: " .. tostring(panel))
    T.assert_true(rendered, "the panel failed to render with no SDK present: " .. tostring(err))
end

-- ============================================================================
-- 12. The panel exposes the shape the shell registers
-- ============================================================================

function M.test_panel_exposes_required_shape()
    T.assert_equal(Database.id, "database", "the shell keys panels by id")
    T.assert_equal(type(Database.title), "string", "the tab needs a label")
    T.assert_equal(Database.order, 5, "the database panel is order 5")
    T.assert_equal(type(Database.render), "function", "the shell calls render(window, bounds, view)")
end

-- ============================================================================
-- 13. Aggregate nearby: grouping logic
-- ============================================================================

function M.test_aggregate_nearby_groups_by_entry()
    local state = DatabaseState.new()
    local entities = {
        { entry = 567, name = "Wolf", level = 5, distance = 10, type = "creature" },
        { entry = 567, name = "Wolf", level = 7, distance = 15, type = "creature" },
        { entry = 568, name = "Boar", level = 4, distance = 20, type = "creature" },
    }
    local results = state:_aggregate_nearby(entities)
    T.assert_equal(#results, 2, "two unique entries")
    T.assert_equal(results[1].entry, 567, "Wolf first (closer)")
    T.assert_equal(results[1].count, 2, "two wolves")
    T.assert_equal(results[1].min_level, 5, "min level")
    T.assert_equal(results[1].max_level, 7, "max level")
    T.assert_equal(results[1].avg_distance, 13, "avg distance (10+15)/2")
end

function M.test_aggregate_nearby_empty_input()
    local state = DatabaseState.new()
    local results = state:_aggregate_nearby({})
    T.assert_equal(#results, 0, "empty input -> empty results")
end

function M.test_aggregate_nearby_nil_input()
    local state = DatabaseState.new()
    local results = state:_aggregate_nearby(nil)
    T.assert_equal(#results, 0, "nil input -> empty results")
end

return M
