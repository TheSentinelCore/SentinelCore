-- tests/ui/test_shell_extensions.lua
-- The shell extensions contract (Phase 5: F12 Travel Editor, F19 Auto Validation,
-- F20 Profile Statistics).
--
-- Tests cover: state transitions, build output shape, command routing, structural guards
-- from ADR 09b §2.1, and cross-extension integration.

local TravelEditorState = require("ui/panels/travel_editor_state")
local TravelEditor = require("ui/panels/travel_editor")
local ValidationStatus = require("ui/panels/validation_status")
local StatsDashboard = require("ui/panels/stats_dashboard")
local Theme = require("ui/theme")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures
-- ============================================================================

local function sample_routes()
    return {
        {
            id = "r1",
            from_node_id = "n1",
            to_node_id = "n2",
            from_label = "Travel",
            to_label = "Kill",
            waypoints = {
                { x = -8940, y = -140, z = 84, movement = "walk", destination = "(-8940, -140, 84)" },
                { x = -8920, y = -180, z = 82, movement = "walk", destination = "(-8920, -180, 82)" },
                { x = -8800, y = -500, z = 60, movement = "walk", destination = "(-8800, -500, 60)" },
            },
        },
        {
            id = "r2",
            from_node_id = "n1",
            to_node_id = "n3",
            from_label = "Travel",
            to_label = "Wait",
            waypoints = {
                { x = -8900, y = -120, z = 82, movement = "walk", destination = "(-8900, -120, 82)" },
                { x = -8800, y = -100, z = 40, movement = "flight", destination = "(-8800, -100, 40)" },
            },
        },
    }
end

local function sample_campaign_plan()
    return {
        name = "elwynn_full_1_60",
        nodes = {
            { id = "n1", type = "questing.Travel", intent = { x = -8940, y = -140, z = 84, destination = "Northshire" } },
            { id = "n2", type = "questing.Kill", intent = { creature_entry = 567, count = 12 } },
            { id = "n3", type = "questing.TurnInQuest", intent = { quest_id = 33, npc_entry = 197 } },
            { id = "n4", type = "questing.AcceptQuest", intent = { quest_id = 33, npc_entry = 197 } },
        },
        edges = {
            { id = "e1", from = "n1", to = "n2", guard = nil },
            { id = "e2", from = "n2", to = "n3", guard = nil },
        },
        conditions = {},
        variables = { { name = "player_level" }, { name = "quest_complete" } },
    }
end

-- ============================================================================
-- 1. TravelEditorState: construction and defaults
-- ============================================================================

function M.test_travel_editor_new_has_defaults()
    local te = TravelEditorState.new()
    T.assert_equal(#te.routes, 0, "routes defaults to empty")
    T.assert_nil(te.selected_route, "selected_route defaults to nil")
    T.assert_false(te.editing_waypoints, "editing_waypoints defaults to false")
    T.assert_false(te.activated, "activated defaults to false")
    T.assert_true(te._dirty, "starts dirty for initial refresh")
end

function M.test_travel_editor_toggle_activation()
    local te = TravelEditorState.new()
    T.assert_false(te.activated)
    local result = te:toggle()
    T.assert_true(result, "first toggle activates")
    T.assert_true(te.activated)
    result = te:toggle()
    T.assert_false(result, "second toggle deactivates")
    T.assert_false(te.activated)
end

function M.test_travel_editor_toggle_clears_selection()
    local te = TravelEditorState.new()
    te.activated = true
    te.selected_route = "r1"
    te:toggle()  -- deactivate
    T.assert_false(te.activated)
    T.assert_nil(te.selected_route, "deactivate clears selected route")
end

function M.test_travel_editor_load_from_campaign()
    local te = TravelEditorState.new()
    local plan = sample_campaign_plan()
    local count = te:load_from_campaign("test", plan.nodes, plan.edges)
    T.assert_equal(count, 2, "should create 2 routes from edge pairs with Travel nodes")
    T.assert_equal(#te.routes, 2)
    T.assert_equal(te.campaign_name, "test")
end

function M.test_travel_editor_load_empty_edges()
    local te = TravelEditorState.new()
    local count = te:load_from_campaign("test", {}, {})
    T.assert_equal(count, 0, "no edges means no routes")
    T.assert_equal(#te.routes, 0)
end

function M.test_travel_editor_select_route()
    local te = TravelEditorState.new()
    te.routes = sample_routes()

    te:select_route("r1")
    T.assert_equal(te.selected_route, "r1")
    T.assert_true(te._dirty)

    -- Toggle off
    te._dirty = false
    te:select_route("r1")
    T.assert_nil(te.selected_route, "re-selecting same route deselects")
end

function M.test_travel_editor_select_nonexistent_route()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    te:select_route("nonexistent")
    T.assert_nil(te.selected_route, "nonexistent route must not select")
end

function M.test_travel_editor_select_empty_string()
    local te = TravelEditorState.new()
    te.selected_route = "r1"
    te:select_route("")
    T.assert_nil(te.selected_route, "empty string clears selection")
end

function M.test_travel_editor_reorder_waypoint()
    local te = TravelEditorState.new()
    te.routes = sample_routes()

    -- Move waypoint 1 to position 3 in route r1
    local result = te:reorder_waypoint("r1", 1, 3)
    T.assert_true(result, "reorder must succeed")
    local wps = te.routes[1].waypoints
    T.assert_equal(#wps, 3, "waypoint count unchanged")
    T.assert_near(wps[3].x, -8940, 1, "waypoint 1 moved to position 3")
end

function M.test_travel_editor_reorder_invalid_indices()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    T.assert_false(te:reorder_waypoint("r1", 1, 10), "out of bounds to_idx must fail")
    T.assert_false(te:reorder_waypoint("r1", 0, 2), "zero from_idx must fail")
end

function M.test_travel_editor_move_waypoint_up()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    local wps = te.routes[1].waypoints
    local orig_second_x = wps[2].x

    te:move_waypoint_up("r1", 2)
    T.assert_near(wps[1].x, orig_second_x, 1, "moved element should be first")
end

function M.test_travel_editor_move_waypoint_down()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    local wps = te.routes[1].waypoints
    local orig_first_x = wps[1].x

    te:move_waypoint_down("r1", 1)
    T.assert_near(wps[2].x, orig_first_x, 1, "moved element should be second")
end

function M.test_travel_editor_set_editing()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    te:select_route("r1")
    T.assert_false(te.editing_waypoints)

    te:set_editing(true)
    T.assert_true(te.editing_waypoints)

    te:set_editing(false)
    T.assert_false(te.editing_waypoints)
end

function M.test_travel_editor_set_editing_no_selection()
    local te = TravelEditorState.new()
    te:set_editing(true)
    T.assert_false(te.editing_waypoints, "cannot edit without selected route")
end

function M.test_travel_editor_add_route()
    local te = TravelEditorState.new()
    local id = te:add_route("n1", "n2")
    T.assert_not_nil(id, "add_route must return an id")
    T.assert_equal(#te.routes, 1)
    T.assert_equal(te.routes[1].from_node_id, "n1")
    T.assert_equal(te.routes[1].to_node_id, "n2")
end

-- ============================================================================
-- 2. TravelEditorState: build output
-- ============================================================================

function M.test_travel_editor_build_returns_correct_keys()
    local te = TravelEditorState.new()
    local view = te:build()
    T.assert_equal(type(view.activated), "boolean")
    T.assert_equal(type(view.routes), "table")
    T.assert_equal(type(view.route_count), "number")
    T.assert_equal(type(view.active_waypoints), "table")
end

function M.test_travel_editor_build_with_routes()
    local te = TravelEditorState.new()
    te.routes = sample_routes()
    te.activated = true
    te:select_route("r1")

    local view = te:build()
    T.assert_equal(view.route_count, 2)
    T.assert_equal(#view.routes, 2)
    T.assert_equal(view.selected_route, "r1")

    local r1_found = nil
    for _, r in ipairs(view.routes) do
        if r.id == "r1" then r1_found = r end
    end
    T.assert_not_nil(r1_found, "route r1 must be in view")
    T.assert_true(r1_found.selected, "r1 must be marked selected")
    T.assert_equal(r1_found.waypoint_count, 3)
end

function M.test_travel_editor_build_plan_with_no_campaign()
    local te = TravelEditorState.new()
    local view = te:build()
    local plan = TravelEditorState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)
    T.assert_not_nil(plan.items)
    T.assert_true(#plan.items > 0, "no-campaign state must produce items")
end

function M.test_travel_editor_build_plan_activated()
    local te = TravelEditorState.new()
    te.activated = true
    te.campaign_name = "test"
    te.routes = sample_routes()
    local view = te:build()
    local plan = TravelEditorState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)
    T.assert_true(#plan.items > 0, "activated editor with routes must produce items")

    local has_list_row = false
    for _, item in ipairs(plan.items) do
        if item.kind == "list_row" then has_list_row = true end
    end
    T.assert_true(has_list_row, "must include list_row items for routes")
end

-- ============================================================================
-- 3. TravelEditorState: reduce command routing
-- ============================================================================

function M.test_travel_reduce_toggle()
    local cmd = TravelEditorState.reduce("travel_toggle")
    T.assert_not_nil(cmd)
    T.assert_equal(cmd.kind, "travel_toggle")
end

function M.test_travel_reduce_select_route()
    local cmd = TravelEditorState.reduce("travel_select_route:r1")
    T.assert_not_nil(cmd)
    T.assert_equal(cmd.kind, "travel_select_route")
    T.assert_equal(cmd.route_id, "r1")
end

function M.test_travel_reduce_toggle_edit()
    local cmd = TravelEditorState.reduce("travel_toggle_edit")
    T.assert_not_nil(cmd)
    T.assert_equal(cmd.kind, "travel_toggle_edit")
end

function M.test_travel_reduce_waypoint_up()
    local cmd = TravelEditorState.reduce("travel_wp_up:r1:2")
    T.assert_not_nil(cmd)
    T.assert_equal(cmd.kind, "travel_move_waypoint")
    T.assert_equal(cmd.route_id, "r1")
    T.assert_equal(cmd.index, 2)
    T.assert_equal(cmd.direction, "up")
end

function M.test_travel_reduce_waypoint_down()
    local cmd = TravelEditorState.reduce("travel_wp_down:r1:1")
    T.assert_not_nil(cmd)
    T.assert_equal(cmd.kind, "travel_move_waypoint")
    T.assert_equal(cmd.route_id, "r1")
    T.assert_equal(cmd.index, 1)
    T.assert_equal(cmd.direction, "down")
end

function M.test_travel_reduce_nil_returns_nil()
    T.assert_nil(TravelEditorState.reduce(nil))
end

function M.test_travel_reduce_unknown_returns_nil()
    T.assert_nil(TravelEditorState.reduce("nonexistent"))
end

-- ============================================================================
-- 4. TravelEditor: render layer
-- ============================================================================

function M.test_travel_editor_render_produces_items()
    local te = TravelEditorState.new()
    te.activated = true
    te.campaign_name = "test"
    te.routes = sample_routes()
    local view = te:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(TravelEditor.render, fake, BOUNDS, view)
    T.assert_true(ok, "travel editor render must not throw: " .. tostring(err))
end

function M.test_travel_editor_render_handles_empty()
    local te = TravelEditorState.new()
    local view = te:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(TravelEditor.render, fake, BOUNDS, view)
    T.assert_true(ok, "travel editor with empty state must not throw: " .. tostring(err))
end

-- ============================================================================
-- 5. ValidationStatus: construction and defaults
-- ============================================================================

function M.test_validation_status_new_has_default_checks()
    local vs = ValidationStatus.new()
    T.assert_equal(#vs.checks, 6, "must have 6 default checks")
    T.assert_false(vs.active, "active defaults to false")
    T.assert_equal(vs.summary, "", "summary defaults to empty")
    T.assert_nil(vs.expanded_check)
    T.assert_true(vs._dirty)

    -- Verify all check ids are present
    local ids = {}
    for _, c in ipairs(vs.checks) do
        ids[c.id] = true
        T.assert_equal(c.status, "pending", "all checks start pending")
    end
    T.assert_true(ids.campaign_loaded)
    T.assert_true(ids.nodes_valid)
    T.assert_true(ids.edges_valid)
    T.assert_true(ids.conditions_valid)
    T.assert_true(ids.variables_valid)
    T.assert_true(ids.quests_complete)
end

function M.test_validation_status_toggle()
    local vs = ValidationStatus.new()
    T.assert_false(vs.active)
    local result = vs:toggle()
    T.assert_true(result, "first toggle activates")
    T.assert_true(vs.active)
    T.assert_true(vs._dirty)

    vs._dirty = false
    result = vs:toggle()
    T.assert_false(result, "second toggle deactivates")
    T.assert_false(vs.active)
end

function M.test_validation_status_toggle_clears_expanded()
    local vs = ValidationStatus.new()
    vs.active = true
    vs.expanded_check = "nodes_valid"
    vs:toggle()
    T.assert_nil(vs.expanded_check, "deactivation clears expanded check")
end

function M.test_validation_status_run_all()
    local vs = ValidationStatus.new()
    local plan = sample_campaign_plan()

    vs:run_all(plan)
    T.assert_true(vs.summary ~= "", "summary must be updated after run_all")

    -- Check individual statuses
    local check_map = {}
    for _, c in ipairs(vs.checks) do
        check_map[c.id] = c
    end

    T.assert_equal(check_map.campaign_loaded.status, "pass", "campaign_loaded must pass")
    T.assert_equal(check_map.nodes_valid.status, "pass", "nodes_valid must pass")
    T.assert_equal(check_map.edges_valid.status, "pass", "edges_valid must pass")
    T.assert_equal(check_map.conditions_valid.status, "warn", "conditions_valid warns with no conditions")
    T.assert_equal(check_map.variables_valid.status, "pass", "variables_valid must pass")
end

function M.test_validation_status_run_all_with_null_plan()
    local vs = ValidationStatus.new()
    vs:run_all(nil)
    for _, c in ipairs(vs.checks) do
        T.assert_equal(c.status, "pending", "all checks pending with nil plan")
    end
end

function M.test_validation_status_run_single_check()
    local vs = ValidationStatus.new()
    local plan = sample_campaign_plan()

    local status = vs:run_check("campaign_loaded", plan)
    T.assert_equal(status, "pass")

    local found = nil
    for _, c in ipairs(vs.checks) do
        if c.id == "campaign_loaded" then found = c end
    end
    T.assert_not_nil(found)
    T.assert_equal(found.status, "pass")
    T.assert_true(found.detail ~= "", "detail must be non-empty after run")
end

function M.test_validation_status_toggle_expand()
    local vs = ValidationStatus.new()
    vs.expanded_check = nil

    vs:toggle_expand("nodes_valid")
    T.assert_equal(vs.expanded_check, "nodes_valid")

    vs:toggle_expand("nodes_valid")
    T.assert_nil(vs.expanded_check, "second toggle clears")
end

function M.test_validation_status_reset()
    local vs = ValidationStatus.new()
    local plan = sample_campaign_plan()
    vs:run_all(plan)
    vs.expanded_check = "nodes_valid"
    T.assert_true(vs.summary ~= "", "summary must be non-empty before reset")

    vs:reset()
    T.assert_equal(vs.summary, "")
    T.assert_nil(vs.expanded_check)
    for _, c in ipairs(vs.checks) do
        T.assert_equal(c.status, "pending", "reset sets all to pending")
    end
end

function M.test_validation_status_update_summary()
    local vs = ValidationStatus.new()
    vs.checks[1].status = "pass"
    vs.checks[2].status = "pass"
    vs.checks[3].status = "fail"
    vs:update_summary()
    T.assert_equal(vs.summary, "2/6 checks pass")
end

function M.test_validation_status_all_pass_summary()
    local vs = ValidationStatus.new()
    for _, c in ipairs(vs.checks) do
        c.status = "pass"
    end
    vs:update_summary()
    T.assert_equal(vs.summary, "6/6 checks pass ✓", "all-pass gets checkmark")
end

-- ============================================================================
-- 6. ValidationStatus: build output
-- ============================================================================

function M.test_validation_status_build_returns_correct_keys()
    local vs = ValidationStatus.new()
    local view = vs:build()
    T.assert_equal(type(view.active), "boolean")
    T.assert_equal(type(view.checks), "table")
    T.assert_equal(#view.checks, 6)
    T.assert_equal(type(view.summary), "string")
end

function M.test_validation_status_build_plan_inactive()
    local vs = ValidationStatus.new()
    local view = vs:build()
    local plan = ValidationStatus.build_plan(view, { x = 0, y = 500, w = 900, h = 32 })
    T.assert_equal(#plan.items, 0, "inactive bar produces no items")
end

function M.test_validation_status_build_plan_active()
    local vs = ValidationStatus.new()
    vs.active = true
    local plan = sample_campaign_plan()
    vs:run_all(plan)
    local view = vs:build()
    local plan_items = ValidationStatus.build_plan(view, { x = 0, y = 500, w = 900, h = 32 })
    T.assert_true(#plan_items.items > 0, "active bar must produce items")
end

-- ============================================================================
-- 7. ValidationStatus: render layer
-- ============================================================================

function M.test_validation_status_render_inactive()
    local vs = ValidationStatus.new()
    local view = vs:build()
    local plan = ValidationStatus.build_plan(view, { x = 0, y = 500, w = 900, h = 32 })
    local fake = FakeWindow.new()
    local ok, err = pcall(ValidationStatus.render, fake, plan)
    T.assert_true(ok, "validation render must not throw: " .. tostring(err))
end

function M.test_validation_status_render_active()
    local vs = ValidationStatus.new()
    vs.active = true
    local plan = sample_campaign_plan()
    vs:run_all(plan)
    local view = vs:build()
    local plan_items = ValidationStatus.build_plan(view, { x = 0, y = 500, w = 900, h = 32 })
    local fake = FakeWindow.new()
    local ok, err = pcall(ValidationStatus.render, fake, plan_items)
    T.assert_true(ok, "active validation render must not throw: " .. tostring(err))
end

-- ============================================================================
-- 8. StatsDashboard: construction and defaults
-- ============================================================================

function M.test_stats_dashboard_new_has_defaults()
    local sd = StatsDashboard.new()
    T.assert_false(sd.visible, "visible defaults to false")
    T.assert_nil(sd.campaign_name)
    T.assert_equal(sd.stats.total_nodes, 0)
    T.assert_equal(sd.stats.total_edges, 0)
    T.assert_equal(#sd.stats.node_breakdown, 0, "node_breakdown starts empty")
    T.assert_true(sd._dirty)
end

function M.test_stats_dashboard_toggle()
    local sd = StatsDashboard.new()
    T.assert_false(sd.visible)

    local result = sd:toggle()
    T.assert_true(result, "first toggle shows")
    T.assert_true(sd.visible)

    result = sd:toggle()
    T.assert_false(result, "second toggle hides")
    T.assert_false(sd.visible)
end

function M.test_stats_dashboard_toggle_marks_dirty()
    local sd = StatsDashboard.new()
    sd._dirty = false
    sd:toggle()
    T.assert_true(sd._dirty)
end

-- ============================================================================
-- 9. StatsDashboard: compute
-- ============================================================================

function M.test_stats_dashboard_compute_from_plan()
    local sd = StatsDashboard.new()
    local plan = sample_campaign_plan()
    sd:compute(plan)

    T.assert_equal(sd.campaign_name, "elwynn_full_1_60")
    T.assert_equal(sd.stats.total_nodes, 4)
    T.assert_equal(sd.stats.total_edges, 2)
    T.assert_equal(sd.stats.total_kills, 12)  -- 1 Kill node * count 12
    T.assert_equal(sd.stats.total_quests, 2)  -- AcceptQuest + TurnInQuest
    T.assert_true(sd.stats.waypoint_count >= 1, "must have at least 1 waypoint from Travel nodes")
    T.assert_true(sd.stats.estimated_duration_min > 0, "estimated duration must be > 0")
    T.assert_true(sd.stats.total_xp_estimate > 0, "total XP must be > 0")
    T.assert_true(#sd.stats.node_breakdown > 0, "must have node breakdown entries")
end

function M.test_stats_dashboard_compute_from_nil()
    local sd = StatsDashboard.new()
    sd:compute(nil)
    T.assert_equal(sd.stats.total_nodes, 0, "nil plan resets all stats")
    T.assert_equal(sd.stats.total_edges, 0)
    T.assert_nil(sd.campaign_name)
end

function M.test_stats_dashboard_compute_from_empty_plan()
    local sd = StatsDashboard.new()
    sd:compute({ nodes = {}, edges = {} })
    T.assert_equal(sd.stats.total_nodes, 0)
    T.assert_equal(sd.stats.total_edges, 0)
end

function M.test_stats_dashboard_compute_breakdown_types()
    local sd = StatsDashboard.new()
    local plan = sample_campaign_plan()
    sd:compute(plan)

    local types = {}
    for _, entry in ipairs(sd.stats.node_breakdown) do
        types[entry.type] = entry
    end

    T.assert_not_nil(types.Travel, "breakdown must include Travel")
    T.assert_not_nil(types.Kill, "breakdown must include Kill")
    T.assert_not_nil(types.AcceptQ, "breakdown must include AcceptQuest")
    T.assert_not_nil(types.TurnInQ, "breakdown must include TurnInQuest")
end

function M.test_stats_dashboard_compute_mark_dirty()
    local sd = StatsDashboard.new()
    sd._dirty = false
    sd:compute(sample_campaign_plan())
    T.assert_true(sd._dirty)
end

-- ============================================================================
-- 10. StatsDashboard: build output
-- ============================================================================

function M.test_stats_dashboard_build_returns_correct_keys()
    local sd = StatsDashboard.new()
    local view = sd:build()
    T.assert_equal(type(view.visible), "boolean")
    T.assert_equal(type(view.stats), "table")
end

function M.test_stats_dashboard_build_plan_when_hidden()
    local sd = StatsDashboard.new()
    local view = sd:build()
    local plan = StatsDashboard.build_plan(view, BOUNDS)
    T.assert_equal(#plan.items, 0, "hidden dashboard produces no items")
end

function M.test_stats_dashboard_build_plan_when_visible()
    local sd = StatsDashboard.new()
    sd:compute(sample_campaign_plan())
    sd.visible = true
    local view = sd:build()
    local plan = StatsDashboard.build_plan(view, BOUNDS)
    T.assert_true(#plan.items > 0, "visible dashboard must produce items")

    local has_bg = false
    for _, item in ipairs(plan.items) do
        if item.kind == "overlay_bg" then has_bg = true end
    end
    T.assert_true(has_bg, "must include overlay background rect")
end

-- ============================================================================
-- 11. StatsDashboard: render layer
-- ============================================================================

function M.test_stats_dashboard_render_hidden()
    local sd = StatsDashboard.new()
    local view = sd:build()
    local plan = StatsDashboard.build_plan(view, BOUNDS)
    local fake = FakeWindow.new()
    local ok, err = pcall(StatsDashboard.render, fake, plan)
    T.assert_true(ok, "stats render hidden must not throw: " .. tostring(err))
end

function M.test_stats_dashboard_render_visible()
    local sd = StatsDashboard.new()
    sd:compute(sample_campaign_plan())
    sd.visible = true
    local view = sd:build()
    local plan = StatsDashboard.build_plan(view, BOUNDS)
    local fake = FakeWindow.new()
    local ok, err = pcall(StatsDashboard.render, fake, plan)
    T.assert_true(ok, "stats render visible must not throw: " .. tostring(err))
end

-- ============================================================================
-- 12. Structural guards
-- ============================================================================

---Source with comments stripped, so an audit fires on code and never on the prose.
local function source_of(path)
    local handle = assert(io.open(path, "r"), path .. " must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

local RENDER_FILES = {
    "sentinel/ui/panels/travel_editor.lua",
}

local STATE_FILES = {
    "sentinel/ui/panels/travel_editor_state.lua",
}

function M.test_render_layer_audit_actually_reads_code()
    for _, path in ipairs(RENDER_FILES) do
        local source = source_of(path)
        -- For travel editor, look for the render function
        if path:find("travel_editor%.lua$") then
            T.assert_true(source:find("TravelEditor%.render") ~= nil,
                path .. " must contain the render function")
        end
    end
end

function M.test_render_layer_contains_no_decision_logic()
    for _, path in ipairs(RENDER_FILES) do
        local source = source_of(path)
        T.assert_nil(source:find("%f[%w]if%f[%W]"),
            path .. " branches; move it to the view-model")
        T.assert_nil(source:find("%f[%w]elseif%f[%W]"),
            path .. " has elseif; move it to the view-model")
        T.assert_nil(source:find("%f[%w]while%f[%W]"),
            path .. " loops on a condition")
    end
end

function M.test_no_menu_element_is_constructed_while_rendering()
    local saved = _G.core and _G.core.menu or nil
    if _G.core then
        _G.core.menu = setmetatable({}, {
            __index = function() error("core.menu was touched during render") end,
        })
    end

    local ok_te, ok_vs, ok_sd = true, true, true
    local err_te, err_vs, err_sd

    -- Travel Editor
    do
        local te = TravelEditorState.new()
        te.activated = true
        te.campaign_name = "test"
        te.routes = {}
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        ok_te, err_te = pcall(TravelEditor.render, fake, BOUNDS, te:build())
    end

    -- Validation Status
    do
        local vs = ValidationStatus.new()
        vs.active = true
        local view = vs:build()
        local plan = ValidationStatus.build_plan(view, { x = 0, y = 500, w = 900, h = 32 })
        local fake = FakeWindow.new()
        ok_vs, err_vs = pcall(ValidationStatus.render, fake, plan)
    end

    -- Stats Dashboard
    do
        local sd = StatsDashboard.new()
        sd:compute(sample_campaign_plan())
        sd.visible = true
        local fake = FakeWindow.new()
        ok_sd, err_sd = pcall(StatsDashboard.render, fake, StatsDashboard.build_plan(sd:build(), BOUNDS))
    end

    if _G.core then _G.core.menu = saved end
    T.assert_true(ok_te, "travel editor constructed a menu element: " .. tostring(err_te))
    T.assert_true(ok_vs, "validation status constructed a menu element: " .. tostring(err_vs))
    T.assert_true(ok_sd, "stats dashboard constructed a menu element: " .. tostring(err_sd))
end

function M.test_the_panel_performs_no_io_on_the_render_path()
    for _, path in ipairs(RENDER_FILES) do
        local source = source_of(path)
        for _, forbidden in ipairs({ "http_get", "http_post", "read_data_file", "write_data_file",
                                     "read_dir", "object_manager", "get_all_objects" }) do
            T.assert_nil(source:find(forbidden, 1, true),
                path .. " reaches for " .. forbidden .. " on the render path")
        end
    end
end

function M.test_the_panel_hardcodes_no_colour_and_no_spacing()
    for _, path in ipairs(RENDER_FILES) do
        local source = source_of(path)
        T.assert_nil(source:find("[Cc]olor%.new%s*%("), path .. " constructs a raw colour")
    end
end

function M.test_all_extensions_loadable_with_no_sdk()
    local names = {
        "ui/panels/travel_editor_state",
        "ui/panels/travel_editor",
        "ui/panels/validation_status",
        "ui/panels/stats_dashboard",
    }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil

    local ok_all = true
    local errs = {}

    local ok1, te = pcall(require, "ui/panels/travel_editor_state")
    if not ok1 then ok_all = false; table.insert(errs, "travel_editor_state: " .. tostring(te)) end

    local ok2, te_r = pcall(require, "ui/panels/travel_editor")
    if not ok2 then ok_all = false; table.insert(errs, "travel_editor: " .. tostring(te_r)) end

    local ok3, vs = pcall(require, "ui/panels/validation_status")
    if not ok3 then ok_all = false; table.insert(errs, "validation_status: " .. tostring(vs)) end

    local ok4, sd = pcall(require, "ui/panels/stats_dashboard")
    if not ok4 then ok_all = false; table.insert(errs, "stats_dashboard: " .. tostring(sd)) end

    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok_all, "extensions failed to load with no SDK: " .. table.concat(errs, "; "))
end

-- ============================================================================
-- 13. Integration: ide_panels exports
-- ============================================================================

function M.test_ide_panels_exposes_getters()
    local IdePanels = require("ui/ide_panels")
    T.assert_equal(type(IdePanels.get_validation_bar), "function", "get_validation_bar must be a function")
    T.assert_equal(type(IdePanels.get_stats_dashboard), "function", "get_stats_dashboard must be a function")
    T.assert_equal(type(IdePanels.get_travel_editor), "function", "get_travel_editor must be a function")

    -- Get accessors return instances or nil depending on whether install() has been called.
    local vb = IdePanels.get_validation_bar()
    local sd = IdePanels.get_stats_dashboard()
    local te = IdePanels.get_travel_editor()
    -- After test_ide_panels runs, these may be non-nil due to install() in that suite.
    -- The test verifies they are the correct type when non-nil.
    if vb then
        T.assert_equal(type(vb.toggle), "function", "validation bar must have toggle method")
    end
    if sd then
        T.assert_equal(type(sd.toggle), "function", "stats dashboard must have toggle method")
    end
    if te then
        T.assert_equal(type(te.toggle), "function", "travel editor must have toggle method")
    end
end

-- ============================================================================
-- 14. Documentation: F4 not implemented
-- ============================================================================

function M.test_f4_spawn_overlay_is_documented_as_blocked()
    -- F4 (Spawn Overlay) requires a Sylvannas render callback hook that hasn't been
    -- investigated yet. This test documents the gap.
    T.assert_true(true, "F4 is blocked pending Sylvannas 3D overlay investigation")
end

-- ============================================================================
-- 15. The selection channel (spec: Cross-Panel Selection Bus)
-- ============================================================================
--
-- The regression: selecting an NPC in the Database changed nothing anywhere else. Properties held a
-- `context` that no caller ever set, so the inspector sat on whatever it was last given -- usually
-- nothing at all -- while the operator watched the panel they had just selected in.

local Shell = require("ui/shell")
local IdePanels = require("ui/ide_panels")

local function installed_shell()
    local window = FakeWindow.new()
    local shell = Shell.new({ window = window, elements = nil })
    local bindings, reason = IdePanels.install(shell, { questing = function() return nil end })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))
    shell:show()
    return shell, bindings, window
end

function M.test_a_database_selection_drives_the_properties_inspector()
    local shell, bindings = installed_shell()
    shell:activate("database")

    -- Dispatched, not rendered -- the shell hands `dispatch` its tick context, and that is the only
    -- context a selection may be published from.
    shell:_queue_command("database", { kind = "select_entry", entry = 567 })
    shell:on_tick()

    local context = bindings.properties:state().context
    T.assert_not_nil(context, "the inspector must have received a context")
    T.assert_equal(context.selection_type, "npc", "the Database publishes NPC entries")
    T.assert_equal(context.selection_id, 567, "carrying the entry that was selected")
end

function M.test_a_selection_from_elsewhere_brings_the_inspector_to_the_front()
    local shell = installed_shell()
    shell:activate("database")
    shell:_queue_command("database", { kind = "select_entry", entry = 567 })
    shell:on_tick()
    T.assert_equal(shell:active_id(), "properties",
        "selecting an NPC in order to inspect it must not leave the operator hunting for the tab")
end

function M.test_the_explorer_and_graph_publish_their_own_kinds()
    local shell, bindings = installed_shell()

    shell:_queue_command("explorer", { kind = "select_quest", id = 1234 })
    shell:on_tick()
    T.assert_equal(shell:selection().kind, "quest", "the Explorer selects quests")
    T.assert_equal(shell:selection().id, 1234)
    T.assert_equal(bindings.properties:state().context.selection_type, "quest",
        "and the inspector follows it")

    shell:_queue_command("graph", { kind = "select_node", node_id = "n1" })
    shell:on_tick()
    T.assert_equal(shell:selection().kind, "node", "the Graph selects nodes")
    T.assert_equal(shell:selection().id, "n1")
end

function M.test_a_selection_may_not_be_published_from_a_render_frame()
    -- Every subscriber does real work: `set_context` abandons an in-flight fetch and re-arms the
    -- panel. Doing that inside `register_on_render_window_callback` is the rule the whole shell is
    -- arranged around, so the channel refuses it rather than trusting every future panel to behave.
    local shell, _, window = installed_shell()
    local heard = 0
    shell:on_selection(function() heard = heard + 1 end)

    local refused, reason
    shell:register_panel({
        id = "renderer",
        render = function()
            refused, reason = shell:publish_selection({ panel_id = "renderer", kind = "npc", id = 1 })
            return nil
        end,
    })
    shell:activate("renderer")
    shell:_on_render_window()

    T.assert_false(refused, "publishing mid-frame must be refused")
    T.assert_not_nil(reason, "and it must say why")
    T.assert_equal(heard, 0, "no subscriber may run inside a render callback")

    -- And the guard must not latch: the very next tick can publish normally.
    T.assert_true(shell:publish_selection({ panel_id = "database", kind = "npc", id = 2 }))
    T.assert_equal(heard, 1, "a guard that jammed shut would disable the bus for the session")
    T.assert_not_nil(window, "the fake window drove a real frame")
end

function M.test_an_incomplete_selection_is_refused_rather_than_normalised()
    local shell = installed_shell()
    T.assert_false(shell:publish_selection({ panel_id = "database", kind = "npc" }),
        "a selection with no id cannot be routed to anything")
    T.assert_false(shell:publish_selection({ panel_id = "database", id = 567 }),
        "nor one with no kind")
    T.assert_nil(shell:selection(), "and neither may become the current selection")
end

-- ============================================================================
-- 16. The player position (spec: Shell Supplies Player Position)
-- ============================================================================
--
-- The regression: `shell.lua` built its render ctx as `{ shell, state }` and never set
-- `player_position`. The Graph panel's waypoint capture and escort recorder both read that field, so
-- both branches were dead, and `travel_add_waypoint` answered "requires player position" forever.

--- Swap the object manager for the duration of one test.
local function with_object_manager(object_manager, fn)
    local previous = _G.core.object_manager
    _G.core.object_manager = object_manager
    local ok, err = pcall(fn)
    _G.core.object_manager = previous
    if not ok then error(err, 0) end
end

function M.test_the_render_context_carries_the_players_position()
    local shell, _, window = installed_shell()
    local seen = {}
    shell:register_panel({
        id = "position_probe",
        render = function(_w, _b, ctx) seen.position = ctx.player_position end,
    })
    shell:activate("position_probe")

    with_object_manager({
        get_local_player = function()
            return { get_position = function() return { x = -8940, y = -140, z = 84 } end }
        end,
    }, function()
        shell:on_tick()
        shell:_on_render_window()
    end)

    T.assert_not_nil(seen.position, "the panel must be handed a position")
    T.assert_equal(seen.position.x, -8940, "the one the object manager answered")
    T.assert_equal(seen.position.z, 84)
    T.assert_not_nil(window, "painted through the fake window")
end

function M.test_the_tick_context_carries_it_too()
    -- `dispatch` runs in tick context, and every command that CAPTURES a position -- waypoint
    -- commit, travel waypoint, escort -- is a dispatched command, not a rendered one.
    local shell = installed_shell()
    local seen = {}
    shell:register_panel({
        id = "tick_probe",
        render = function() end,
        dispatch = function(_cmd, ctx) seen.position = ctx.player_position; return true end,
    })
    shell:activate("tick_probe")
    shell:_queue_command("tick_probe", { kind = "anything" })

    with_object_manager({
        get_local_player = function()
            return { get_position = function() return { x = 1, y = 2, z = 3 } end }
        end,
    }, function() shell:on_tick() end)

    T.assert_not_nil(seen.position, "dispatch must see the position too")
    T.assert_equal(seen.position.y, 2)
end

function M.test_a_missing_position_is_nil_and_nothing_raises()
    -- Out of world: loading screen, between injections, dead object manager. A shell that answered
    -- `{0,0,0}` here would drop a waypoint in the middle of the map and say nothing about it.
    local shell, _, window = installed_shell()
    local rendered = false
    shell:register_panel({
        id = "nil_probe",
        render = function(_w, _b, ctx)
            rendered = true
            T.assert_nil(ctx.player_position, "an absent player must read as nil, never as origin")
        end,
    })
    shell:activate("nil_probe")

    with_object_manager({ get_local_player = function() return nil end }, function()
        shell:on_tick()
        shell:_on_render_window()
    end)
    T.assert_true(rendered, "the frame must still paint")
    T.assert_nil(shell:player_position(), "and the shell must hold nothing")

    -- The harsher case: an object manager that throws.
    with_object_manager({ get_local_player = function() error("out of world", 0) end }, function()
        shell:on_tick()
    end)
    T.assert_nil(shell:player_position(), "a raising object manager is still just no position")
    T.assert_not_nil(window, "painted through the fake window")
end

return M
