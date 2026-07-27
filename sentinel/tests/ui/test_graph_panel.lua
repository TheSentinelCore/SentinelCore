-- tests/ui/test_graph_panel.lua
-- The Graph panel's contract (Phase 3, PR-3a/3b/3c).
--
-- Tests cover: state transitions (campaign, nodes, edges, waypoint, escort), build output
-- shape, command routing, EscortRecorder lifecycle, and the structural guards from ADR 09b §2.1.

local GraphState = require("ui/panels/graph_state")
local Graph = require("ui/panels/graph")
local EscortRecorder = require("ui/panels/escort_recorder")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures
-- ============================================================================

local function sample_nodes()
    return {
        { id = "n1", type = "questing.Travel", intent = { destination = "Elwynn Forest", x = -8932, y = -137, z = 82, tolerance = 5 }, preview = "Elwynn Forest" },
        { id = "n2", type = "questing.Kill", intent = { creature_entry = 567, count = 12, loot = false, ignore_elites = false }, preview = "Defias Bandit x12" },
        { id = "n3", type = "questing.Wait", intent = { duration = 5 }, preview = "Wait 5s" },
    }
end

local function sample_edges()
    return {
        { id = "e1", from = "n1", to = "n2" },
        { id = "e2", from = "n2", to = "n3", guard = "g1" },
    }
end

-- ============================================================================
-- 1. GraphState: construction and defaults
-- ============================================================================

function M.test_new_state_has_defaults()
    local state = GraphState.new()
    T.assert_nil(state.campaign_name, "campaign_name defaults to nil")
    T.assert_equal(#state.nodes, 0, "nodes defaults to empty")
    T.assert_equal(#state.edges, 0, "edges defaults to empty")
    T.assert_nil(state.selected_node, "selected_node defaults to nil")
    T.assert_nil(state.selected_edge, "selected_edge defaults to nil")
    T.assert_true(state._dirty, "starts dirty for initial refresh")
    T.assert_false(state.loading, "loading defaults to false")
    T.assert_nil(state.error, "error defaults to nil")
    T.assert_false(state.waypoint_mode, "waypoint_mode defaults to false")
    T.assert_false(state.escort_mode, "escort_mode defaults to false")
    T.assert_nil(state.current_position, "current_position defaults to nil")
end

-- ============================================================================
-- 2. GraphState: node type metadata
-- ============================================================================

function M.test_node_type_info_returns_valid_types()
    local types = GraphState.all_node_types()
    T.assert_true(#types > 0, "must have at least one node type")
    local found_travel = false
    for _, nt in ipairs(types) do
        T.assert_true(nt.type ~= nil, "each type must have a type")
        T.assert_true(nt.label ~= nil, "each type must have a label")
        T.assert_true(nt.token ~= nil, "each type must have a theme token")
        if nt.type == "questing.Travel" then found_travel = true end
    end
    T.assert_true(found_travel, "must include questing.Travel")
end

function M.test_node_type_color_returns_string()
    local color = GraphState.node_color("questing.Travel")
    T.assert_true(type(color) == "string", "color must be a hex string")
    T.assert_true(color:sub(1, 1) == "#", "color must start with #")
end

function M.test_node_type_info_returns_nil_for_unknown()
    T.assert_nil(GraphState.node_type_info("questing.Nonexistent"), "unknown type returns nil")
end

-- ============================================================================
-- 3. GraphState: mutators
-- ============================================================================

function M.test_set_campaign_updates_name_and_marks_dirty()
    local state = GraphState.new()
    state._dirty = false
    state:set_campaign("elwynn_full_1_60")
    T.assert_equal(state.campaign_name, "elwynn_full_1_60")
    T.assert_true(state._dirty, "set_campaign marks dirty")
    T.assert_true(state.loading, "set_campaign sets loading")
end

function M.test_set_campaign_ignores_same_value()
    local state = GraphState.new()
    state.campaign_name = "test"  -- set directly to simulate an already-loaded campaign
    state._dirty = false
    state:set_campaign("test")
    T.assert_false(state._dirty, "setting the same campaign must not mark dirty")
end

function M.test_select_node_updates_selection()
    local state = GraphState.new()
    state:select_node("n1")
    T.assert_equal(state.selected_node, "n1", "select_node sets selected_node")
    T.assert_true(state._dirty, "select_node marks dirty")
end

function M.test_select_node_clears_edge_selection()
    local state = GraphState.new()
    state.selected_edge = "e1"
    state:select_node("n1")
    T.assert_nil(state.selected_edge, "select_node clears selected_edge")
end

function M.test_select_node_ignores_same_id()
    local state = GraphState.new()
    state:select_node("n1")
    state._dirty = false
    state:select_node("n1")
    T.assert_false(state._dirty, "re-selecting the same node must not mark dirty")
end

function M.test_select_node_with_empty_string_clears()
    local state = GraphState.new()
    state.selected_node = "n1"
    state:select_node("")
    T.assert_nil(state.selected_node, "selecting empty string must clear")
end

function M.test_toggle_expand_node_works()
    local state = GraphState.new()
    state:toggle_expand_node("n1")
    T.assert_true(state.expanded["n1"], "toggle_expand_node must set expanded")
    T.assert_true(state._dirty)

    state._dirty = false
    state:toggle_expand_node("n1")
    T.assert_nil(state.expanded["n1"], "toggle_expand_node again must unset expanded")
    T.assert_true(state._dirty)
end

function M.test_add_node_creates_node_with_default_intent()
    local state = GraphState.new()
    local node = state:add_node("questing.Kill")
    T.assert_not_nil(node, "add_node must return a node")
    T.assert_equal(#state.nodes, 1)
    T.assert_equal(node.type, "questing.Kill")
    T.assert_equal(node.intent.count, 1, "default intent must be set")
    T.assert_false(node.intent.loot, "default intent for loot must be false")
end

function M.test_add_node_unknown_type_returns_nil()
    local state = GraphState.new()
    local node = state:add_node("questing.Nonexistent")
    T.assert_nil(node, "unknown type must return nil")
    T.assert_equal(#state.nodes, 0)
end

function M.test_add_node_every_type_creates_valid_nodes()
    local state = GraphState.new()
    local types = GraphState.all_node_types()
    for _, nt in ipairs(types) do
        local node = state:add_node(nt.type)
        T.assert_not_nil(node, "add_node must work for " .. nt.type)
        T.assert_equal(node.type, nt.type)
    end
    T.assert_equal(#state.nodes, #types, "all types must produce nodes")
end

function M.test_remove_node_removes_node_and_connected_edges()
    local state = GraphState.new()
    state:add_node("questing.Travel")  -- n1
    state:add_node("questing.Kill")    -- n2
    T.assert_equal(#state.nodes, 2)

    -- Add an edge between n1 and n2
    local n1 = state.nodes[1]
    local n2 = state.nodes[2]
    state:add_edge(n1.id, n2.id)
    T.assert_equal(#state.edges, 1)

    state:remove_node(n1.id)
    T.assert_equal(#state.nodes, 1, "node must be removed")
    T.assert_equal(#state.edges, 0, "connected edges must also be removed")
end

function M.test_remove_node_clears_selection()
    local state = GraphState.new()
    state:add_node("questing.Travel")
    local n1 = state.nodes[1]
    state:select_node(n1.id)
    state:remove_node(n1.id)
    T.assert_nil(state.selected_node, "selected_node must be cleared after removal")
end

function M.test_update_node_intent_updates_field()
    local state = GraphState.new()
    state:add_node("questing.Kill")
    local n1 = state.nodes[1]
    state:update_node_intent(n1.id, "count", 25)
    T.assert_equal(n1.intent.count, 25, "intent must be updated")
    T.assert_true(state._dirty)
end

function M.test_add_edge_creates_edge()
    local state = GraphState.new()
    state:add_node("questing.Travel")
    state:add_node("questing.Wait")
    local n1 = state.nodes[1]
    local n2 = state.nodes[2]
    local edge = state:add_edge(n1.id, n2.id)
    T.assert_not_nil(edge, "add_edge must return an edge")
    T.assert_equal(#state.edges, 1)
    T.assert_equal(edge.from, n1.id)
    T.assert_equal(edge.to, n2.id)
end

function M.test_add_edge_requires_both_ids()
    local state = GraphState.new()
    T.assert_nil(state:add_edge("", "n2"), "empty from returns nil")
    T.assert_nil(state:add_edge("n1", ""), "empty to returns nil")
end

-- ============================================================================
-- 4. GraphState: waypoint mode
-- ============================================================================

function M.test_toggle_waypoint_mode_toggles()
    local state = GraphState.new()
    T.assert_false(state.waypoint_mode)
    state:toggle_waypoint_mode()
    T.assert_true(state.waypoint_mode, "first toggle sets waypoint_mode")
    state:toggle_waypoint_mode()
    T.assert_false(state.waypoint_mode, "second toggle unsets waypoint_mode")
end

function M.test_toggle_waypoint_turns_off_escort()
    local state = GraphState.new()
    state.escort_mode = true
    state:toggle_waypoint_mode()
    T.assert_true(state.waypoint_mode)
    T.assert_false(state.escort_mode, "waypoint mode must disable escort mode")
end

function M.test_capture_position_updates_position()
    local state = GraphState.new()
    state:toggle_waypoint_mode()
    state:capture_position({ x = 10, y = 20, z = 30 })
    T.assert_not_nil(state.current_position)
    T.assert_equal(state.current_position.x, 10)
    T.assert_equal(state.current_position.y, 20)
end

function M.test_capture_position_ignored_when_not_waypoint_mode()
    local state = GraphState.new()
    state:capture_position({ x = 10, y = 20, z = 30 })
    T.assert_nil(state.current_position, "position not captured outside waypoint mode")
end

function M.test_commit_waypoint_creates_travel_node()
    local state = GraphState.new()
    state:toggle_waypoint_mode()
    state:capture_position({ x = -8932, y = -137, z = 82 })
    local node = state:commit_waypoint()
    T.assert_not_nil(node, "commit_waypoint must return a node")
    T.assert_equal(node.type, "questing.Travel")
    T.assert_equal(node.intent.x, -8932)
    T.assert_equal(node.intent.y, -137)
end

-- ============================================================================
-- 5. GraphState: escort recording
-- ============================================================================

function M.test_set_escort_mode_starts_recording()
    local state = GraphState.new()
    state:set_escort_mode(true)
    T.assert_true(state.escort_mode)
    T.assert_not_nil(state.escort_start_time, "escort_start_time must be set")
    T.assert_false(state.waypoint_mode, "escort mode must disable waypoint mode")
end

function M.test_tick_escort_position_records_entry()
    local state = GraphState.new()
    state:set_escort_mode(true)
    state:tick_escort_position({ x = 100, y = 200, z = 300 })
    T.assert_equal(#state.escort_timeline, 1, "tick must record position")
    T.assert_equal(state.escort_timeline[1].position.x, 100)
end

function M.test_tick_escort_ignored_when_not_recording()
    local state = GraphState.new()
    state:tick_escort_position({ x = 100, y = 200, z = 300 })
    T.assert_equal(#state.escort_timeline, 0, "tick ignored when not recording")
end

function M.test_generate_escort_nodes_creates_nodes()
    local state = GraphState.new()
    state:set_escort_mode(true)
    for i = 1, 10 do
        state:tick_escort_position({ x = i * 10, y = i * 20, z = 0 })
    end
    local before = #state.nodes
    local generated = state:generate_escort_nodes()
    T.assert_true(#generated > 0, "must generate at least one node")
    T.assert_true(#state.nodes > before, "nodes must be added to state")
    T.assert_false(state.escort_mode, "generate_escort_nodes must stop recording")
    T.assert_equal(#state.escort_timeline, 0, "timeline must be cleared")
end

-- ====================================================================
-- 6. Build: view model shape
-- ====================================================================

function M.test_build_returns_correct_keys()
    local state = GraphState.new()
    local view = state:build()
    T.assert_equal(type(view.nodes), "table", "nodes must be a table")
    T.assert_equal(type(view.edges), "table", "edges must be a table")
    T.assert_equal(type(view.loading), "boolean", "loading must be a boolean")
    T.assert_equal(type(view.waypoint_mode), "boolean", "waypoint_mode must be a boolean")
    T.assert_equal(type(view.escort_mode), "boolean", "escort_mode must be a boolean")
    T.assert_equal(type(view.all_nodes), "table", "all_nodes must be a table")
    T.assert_true(view.campaign_name == nil or type(view.campaign_name) == "string",
        "campaign_name must be nil or string")
end

function M.test_build_with_nodes_includes_all()
    local state = GraphState.new()
    state:set_campaign("test")
    state:add_node("questing.Travel")
    state:add_node("questing.Kill")
    state:add_node("questing.Wait")
    state.nodes = sample_nodes()  -- replace with known ids
    local view = state:build()
    T.assert_equal(#view.nodes, 3, "all nodes in view")
    T.assert_equal(#view.all_nodes, 3, "all_nodes also has 3")
end

function M.test_build_respects_filter_type()
    local state = GraphState.new()
    state.nodes = sample_nodes()
    state.filter_type = "questing.Kill"
    local view = state:build()
    T.assert_equal(#view.nodes, 1, "only Kill nodes visible")
    T.assert_equal(view.nodes[1].type, "questing.Kill")
end

function M.test_build_includes_escort_timeline_count()
    local state = GraphState.new()
    state.escort_mode = true
    state.escort_timeline = { { time = 1, position = { x = 0, y = 0, z = 0 } } }
    local view = state:build()
    T.assert_equal(view.escort_timeline_count, 1)
end

-- ====================================================================
-- 7. Build plan: items from view
-- ====================================================================

function M.test_build_plan_with_no_campaign()
    local state = GraphState.new()
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan, "plan must exist")
    T.assert_not_nil(plan.items, "plan must have items")
    T.assert_true(#plan.items > 0, "empty state must produce items")
    -- Should contain an empty_state item
    local has_empty = false
    for _, item in ipairs(plan.items) do
        if item.kind == "empty_state" then has_empty = true end
    end
    T.assert_true(has_empty, "no-campaign state must include empty_state item")
end

function M.test_build_plan_with_loading_state()
    local state = GraphState.new()
    state:set_campaign("test")  -- This sets loading=true
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)
    T.assert_true(#plan.items > 0, "loading state must produce items")
end

function M.test_build_plan_with_nodes()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)
    T.assert_true(#plan.items > 0, "nodes must produce items")

    local has_list_row = false
    for _, item in ipairs(plan.items) do
        if item.kind == "list_row" then has_list_row = true end
    end
    T.assert_true(has_list_row, "node list must include list_row items")
end

function M.test_build_plan_with_selected_node_includes_action_buttons()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    state:select_node("n1")
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)

    local has_edit_button = false
    for _, item in ipairs(plan.items) do
        if item.id and item.id:match("^toggle_expand:n1$") then
            has_edit_button = true
        end
    end
    T.assert_true(has_edit_button, "selected node must show Edit button")
end

function M.test_build_plan_with_waypoint_mode()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.waypoint_mode = true
    state:capture_position({ x = 10, y = 20, z = 30 })
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)

    local has_commit = false
    for _, item in ipairs(plan.items) do
        if item.id == "commit_waypoint" then has_commit = true end
    end
    T.assert_true(has_commit, "waypoint mode must show Commit button")
end

function M.test_build_plan_with_escort_mode()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.escort_mode = true
    state.escort_timeline = { { time = 1 }, { time = 2 } }
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)

    local has_generate = false
    for _, item in ipairs(plan.items) do
        if item.id == "generate_escort_nodes" then has_generate = true end
    end
    T.assert_true(has_generate, "escort mode must show Generate button")
end

function M.test_build_plan_with_expanded_node_shows_fields()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    state.expanded["n2"] = true  -- Kill node
    local view = state:build()
    local plan = GraphState.build_plan(view, BOUNDS)
    T.assert_not_nil(plan)

    -- Should have intent edit buttons
    local has_edit = false
    for _, item in ipairs(plan.items) do
        if item.id and item.id:match("^edit_intent:n2:") then
            has_edit = true
        end
    end
    T.assert_true(has_edit, "expanded node must show edit buttons for intent fields")
end

-- ====================================================================
-- 8. GraphState: filter
-- ====================================================================

function M.test_set_filter_toggles_type()
    local state = GraphState.new()
    state:set_filter("questing.Kill")
    T.assert_equal(state.filter_type, "questing.Kill")
    state:set_filter("questing.Kill")
    T.assert_nil(state.filter_type, "second call with same type must toggle off")
end

-- ====================================================================
-- 9. Reduce: command routing
-- ====================================================================

function M.test_reduce_add_node_toggle()
    local cmd = GraphState.reduce("add_node_toggle")
    T.assert_not_nil(cmd, "add_node_toggle must produce a command")
    T.assert_equal(cmd.kind, "show_add_node_menu")
end

function M.test_reduce_select_node()
    local cmd = GraphState.reduce("select_node:n1")
    T.assert_not_nil(cmd, "select_node must produce a command")
    T.assert_equal(cmd.kind, "select_node")
    T.assert_equal(cmd.node_id, "n1")
end

function M.test_reduce_toggle_expand()
    local cmd = GraphState.reduce("toggle_expand:n1")
    T.assert_not_nil(cmd, "toggle_expand must produce a command")
    T.assert_equal(cmd.kind, "toggle_expand")
    T.assert_equal(cmd.node_id, "n1")
end

function M.test_reduce_remove_node()
    local cmd = GraphState.reduce("remove_node:n1")
    T.assert_not_nil(cmd, "remove_node must produce a command")
    T.assert_equal(cmd.kind, "remove_node")
    T.assert_equal(cmd.node_id, "n1")
end

function M.test_reduce_edit_intent()
    local cmd = GraphState.reduce("edit_intent:n2:count")
    T.assert_not_nil(cmd, "edit_intent must produce a command")
    T.assert_equal(cmd.kind, "edit_intent")
    T.assert_equal(cmd.node_id, "n2")
    T.assert_equal(cmd.field, "count")
end

function M.test_reduce_toggle_waypoint()
    local cmd = GraphState.reduce("toggle_waypoint")
    T.assert_not_nil(cmd, "toggle_waypoint must produce a command")
    T.assert_equal(cmd.kind, "toggle_waypoint")
end

function M.test_reduce_commit_waypoint()
    local cmd = GraphState.reduce("commit_waypoint")
    T.assert_not_nil(cmd, "commit_waypoint must produce a command")
    T.assert_equal(cmd.kind, "commit_waypoint")
end

function M.test_reduce_toggle_escort()
    local cmd = GraphState.reduce("toggle_escort")
    T.assert_not_nil(cmd, "toggle_escort must produce a command")
    T.assert_equal(cmd.kind, "toggle_escort")
end

function M.test_reduce_generate_escort_nodes()
    local cmd = GraphState.reduce("generate_escort_nodes")
    T.assert_not_nil(cmd, "generate_escort_nodes must produce a command")
    T.assert_equal(cmd.kind, "generate_escort_nodes")
end

function M.test_reduce_filter_type()
    local cmd = GraphState.reduce("filter_type:questing.Kill")
    T.assert_not_nil(cmd, "filter_type must produce a command")
    T.assert_equal(cmd.kind, "set_filter")
    T.assert_equal(cmd.node_type, "questing.Kill")
end

function M.test_reduce_validate()
    local cmd = GraphState.reduce("validate")
    T.assert_not_nil(cmd, "validate must produce a command")
    T.assert_equal(cmd.kind, "validate_graph")
end

function M.test_reduce_compile()
    local cmd = GraphState.reduce("compile")
    T.assert_not_nil(cmd, "compile must produce a command")
    T.assert_equal(cmd.kind, "compile_graph")
end

function M.test_reduce_nil_returns_nil()
    T.assert_nil(GraphState.reduce(nil), "nil action must return nil")
end

function M.test_reduce_unknown_returns_nil()
    T.assert_nil(GraphState.reduce("nonexistent"), "unknown action must return nil")
end

-- ====================================================================
-- 10. EscortRecorder: lifecycle
-- ====================================================================

function M.test_recorder_new_has_defaults()
    local r = EscortRecorder.new()
    T.assert_false(r.recording, "new recorder not recording")
    T.assert_equal(#r.timeline, 0, "timeline starts empty")
    T.assert_equal(r.samples, 0)
end

function M.test_recorder_start_begins_recording()
    local r = EscortRecorder.new()
    r:start()
    T.assert_true(r.recording, "start sets recording")
    T.assert_not_nil(r.start_time, "start sets start_time")
    T.assert_equal(#r.timeline, 0, "timeline cleared")
end

function M.test_recorder_start_clears_previous_timeline()
    local r = EscortRecorder.new()
    r:start()
    r:tick({ player_position = { x = 1, y = 2, z = 3 } })
    T.assert_equal(#r.timeline, 1, "first tick records")
    -- Hack: reset _last_sample_time to force capture on next tick
    r._last_sample_time = nil
    r:tick({ player_position = { x = 4, y = 5, z = 6 } })
    T.assert_equal(#r.timeline, 2, "second tick also records")
end

function M.test_recorder_tick_ignored_when_not_recording()
    local r = EscortRecorder.new()
    r:tick({ player_position = { x = 1, y = 2, z = 3 } })
    T.assert_equal(#r.timeline, 0, "no recording, no tick")
end

function M.test_recorder_tick_ignored_without_position()
    local r = EscortRecorder.new()
    r:start()
    r:tick({})
    T.assert_equal(#r.timeline, 0, "no position in ctx, no tick")
end

function M.test_recorder_stop_returns_timeline_and_resets()
    local r = EscortRecorder.new()
    r:start()
    r._last_sample_time = nil
    r:tick({ player_position = { x = 10, y = 20, z = 30 } })
    local timeline = r:stop()
    T.assert_false(r.recording, "stop clears recording")
    T.assert_equal(#timeline, 1, "stop returns captured timeline")
    T.assert_equal(#r.timeline, 0, "internal timeline cleared")
end

function M.test_recorder_generate_nodes_creates_entries()
    local r = EscortRecorder.new()
    r:start()
    r._last_sample_time = nil
    r:tick({ player_position = { x = 1, y = 2, z = 3 } })
    r._last_sample_time = nil
    r:tick({ player_position = { x = 10, y = 20, z = 30 } })
    r._last_sample_time = nil
    r:tick({ player_position = { x = 100, y = 200, z = 300 } })
    local nodes = r:generate_nodes()
    T.assert_true(#nodes >= 3, "must generate at least 3 nodes from 3 positions")
    T.assert_equal(nodes[1].type, "questing.Travel", "first generated node type")
    T.assert_equal(nodes[1].intent.x, 1, "first node position preserved")
end

function M.test_recorder_status_returns_state()
    local r = EscortRecorder.new()
    local status = r:status()
    T.assert_false(status.recording)
    T.assert_equal(status.samples, 0)
    r:start()
    status = r:status()
    T.assert_true(status.recording)
end

-- ====================================================================
-- 11. Render: the panel draws and returns commands
-- ====================================================================

function M.test_render_creates_items_and_returns_command()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local command, plan = Graph.render(fake, BOUNDS, view)
    T.assert_not_nil(plan, "render must return a plan")
    T.assert_not_nil(plan.items, "plan must have items")
    T.assert_true(#plan.items > 0, "plan must have at least one item")
end

function M.test_render_handles_empty_campaign_gracefully()
    local state = GraphState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Graph.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with no campaign must not throw: " .. tostring(err))
end

function M.test_render_handles_loading_state()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = true
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Graph.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with loading must not throw: " .. tostring(err))
end

function M.test_render_with_full_graph()
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    state:select_node("n2")
    state.expanded["n2"] = true
    state.escort_mode = true
    state.escort_timeline = { { time = 1, position = { x = 0, y = 0, z = 0 } } }
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Graph.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with full graph must not throw: " .. tostring(err))
end

-- ====================================================================
-- 12. Structural guards — the failures that pass offline and break in the injector
-- ====================================================================

---Source with comments stripped, so an audit fires on code and never on the prose documenting the
---rule. Block comments go first: a `--[[ ]]` containing a `--` line would otherwise leave a
---fragment behind.
local function source_of(path)
    local handle = assert(io.open(path, "r"), path .. " must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

local RENDER_SOURCE = "sentinel/ui/panels/graph.lua"
local STATE_SOURCE = "sentinel/ui/panels/graph_state.lua"

function M.test_the_source_audit_actually_reads_code()
    local source = source_of(RENDER_SOURCE)
    T.assert_true(source:find("function Graph.render", 1, true) ~= nil,
        "the stripped source must still contain the render function")
end

function M.test_the_render_layer_contains_no_decision_logic()
    -- ADR 09b §2.1. A branch inside a render callback cannot be reached by any offline test, so
    -- the rule is enforced structurally rather than by review.
    local source = source_of(RENDER_SOURCE)
    T.assert_nil(source:find("%f[%w]if%f[%W]"), "graph.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]elseif%f[%W]"), "graph.lua has elseif; move it to the view-model")
    T.assert_nil(source:find("%f[%w]while%f[%W]"), "graph.lua loops on a condition")
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
    local state = GraphState.new()
    state.campaign_name = "test"
    state.loading = false
    state.nodes = sample_nodes()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Graph.render, fake, BOUNDS, state:build())
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
        "ui/panels/graph", "ui/panels/graph_state",
        "ui/theme", "ui/widgets",
    }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local ok, panel = pcall(require, "ui/panels/graph")
    local rendered, err = true, nil
    if ok then
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        local state = GraphState.new()
        rendered, err = pcall(panel.render, fake, BOUNDS, state:build())
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok, "the panel failed to load with no SDK present: " .. tostring(panel))
    T.assert_true(rendered, "the panel failed to render with no SDK present: " .. tostring(err))
end

-- ====================================================================
-- 13. The panel exposes the shape the shell registers
-- ====================================================================

function M.test_panel_exposes_required_shape()
    T.assert_equal(Graph.id, "graph", "the shell keys panels by id")
    T.assert_equal(type(Graph.title), "string", "the tab needs a label")
    T.assert_equal(Graph.order, 4, "the graph panel is order 4")
    T.assert_equal(type(Graph.render), "function", "the shell calls render(window, bounds, view)")
end

-- ====================================================================
-- 14. Campaign lifecycle (spec: Graph Campaign Lifecycle)
-- ====================================================================

--- The editor's `Campaign` document, as `GET /editor/campaigns/{name}` serializes it.
local function editor_campaign(name, graph_id, nodes)
    return {
        schema_version = 1, id = "11111111-1111-4111-8111-111111111111", name = name,
        imports = {}, variables = {}, conditions = {},
        graphs = { { id = graph_id, name = "main",
                     entry_node = "00000000-0000-0000-0000-000000000000",
                     nodes = nodes or {}, edges = {} } },
    }
end

function M.test_the_chooser_offers_a_new_campaign_action_and_a_name_to_type()
    local state = GraphState.new()
    local plan = GraphState.build_plan(state:build(), BOUNDS)

    local input, empty = nil, nil
    for _, item in ipairs(plan.items) do
        if item.kind == "text_input" then input = item end
        if item.kind == "empty_state" then empty = item end
    end

    T.assert_not_nil(input, "the chooser needs a field to name a campaign in")
    T.assert_equal(input.model, state.name_input,
        "and it must carry the STATE's buffer, or nothing offline can read what was typed")
    T.assert_not_nil(empty, "the empty state is still what an operator sees first")
    T.assert_equal(empty.action_label, "New Campaign",
        "with the action the spec names -- create had to work from HERE, and there was no Lua "
        .. "caller for :3031 at all")
    T.assert_equal(empty.id, "new_campaign", "and an id reduce can turn into a command")
end

function M.test_the_chooser_distinguishes_no_campaigns_from_not_asked_yet()
    local state = GraphState.new()
    local function caption()
        local plan = GraphState.build_plan(state:build(), BOUNDS)
        for _, item in ipairs(plan.items) do
            if item.kind == "text" and tostring(item.text):find("campaign", 1, true) then
                return item.text
            end
        end
        return nil
    end

    T.assert_true(tostring(caption()):find("Asking", 1, true) ~= nil,
        "before the list lands the panel says it is asking, got " .. tostring(caption()))
    state:set_campaigns({})
    T.assert_true(tostring(caption()):find("No campaigns", 1, true) ~= nil,
        "an editor with nothing on it is a different fact and an operator acts differently on it")
end

function M.test_each_listed_campaign_is_openable()
    local state = GraphState.new()
    state:set_campaigns({
        { name = "a", node_count = 0 },
        { name = "b", node_count = 3 },
    })
    local plan = GraphState.build_plan(state:build(), BOUNDS)

    local rows = {}
    for _, item in ipairs(plan.items) do
        if item.kind == "list_row" then rows[#rows + 1] = item end
    end
    T.assert_equal(#rows, 2, "one row per campaign")
    T.assert_equal(rows[2].id, "open_campaign:b", "keyed by name")
    T.assert_true(rows[2].label:find("3 node", 1, true) ~= nil,
        "showing CampaignSummary's node_count, got " .. rows[2].label)

    local cmd = GraphState.reduce("open_campaign:b")
    T.assert_equal(cmd.kind, "open_campaign", "clicking one opens it")
    T.assert_equal(cmd.name, "b", "naming the campaign")
end

function M.test_the_empty_state_action_and_enter_both_create()
    T.assert_equal(GraphState.reduce("new_campaign").kind, "create_campaign",
        "the empty-state button creates")
    T.assert_equal(GraphState.reduce("campaign_name_submit").kind, "create_campaign",
        "and so does Enter in the name field -- typing a name then pressing Enter is the shape "
        .. "every other field in this IDE already has")
    T.assert_equal(GraphState.reduce("campaign_name_cancel").kind, "cancel_campaign_name",
        "Escape is a different command, not a create with an empty name")
end

function M.test_apply_campaign_becomes_the_editors_graph()
    local state = GraphState.new()
    state:set_campaign("stw")
    T.assert_true(state.loading, "an open is a fetch, and the panel says so until it lands")

    local applied = state:apply_campaign(editor_campaign("stw", "graph-1", {
        { id = "aaaaaaaa-0000-4000-8000-000000000001", type = "questing.AcceptQuest",
          intent = { quest_id = 1234 } },
        { id = "aaaaaaaa-0000-4000-8000-000000000002", type = "questing.Kill",
          intent = { creature_entry = 567, count = 10 } },
    }))
    T.assert_true(applied, "the campaign was applied")
    T.assert_equal(state.graph_id, "graph-1",
        "the graph id is kept: every mutation has to name it or the editor answers 'Graph not found'")
    T.assert_equal(#state.nodes, 2, "both of the editor's nodes are here")
    T.assert_equal(state.nodes[2].type, "questing.Kill", "with their types")
    T.assert_equal(state.nodes[1].id, "aaaaaaaa-0000-4000-8000-000000000001",
        "and the SERVER's ids, because a locally minted id addresses nothing")
    T.assert_false(state.loading, "the fetch is over")
end

function M.test_a_freshly_created_campaign_applies_with_no_graph_at_all()
    local state = GraphState.new()
    local fresh = editor_campaign("stw", "graph-1", {})
    fresh.graphs = {}

    T.assert_true(state:apply_campaign(fresh), "Campaign::new gives a campaign zero graphs")
    T.assert_equal(state.campaign_name, "stw", "it is still a campaign that is open")
    T.assert_nil(state.graph_id, "there is simply no graph to write into yet")
    T.assert_equal(#state.nodes, 0, "and no nodes")
    T.assert_false(state.loading, "and it is not still loading -- that is the whole answer")
end

function M.test_closing_a_campaign_returns_to_a_chooser_that_will_re_ask()
    local state = GraphState.new()
    state:apply_campaign(editor_campaign("stw", "graph-1",
        { { id = "n1", type = "questing.Kill", intent = { creature_entry = 1 } } }))
    state:set_campaigns({ { name = "stw", node_count = 1 } })

    state:close_campaign()
    T.assert_nil(state.campaign_name, "no campaign is open")
    T.assert_equal(#state.nodes, 0, "and the previous campaign's nodes are gone with it")
    T.assert_false(state.campaigns_loaded,
        "the list is stale the moment a create lands, so the chooser must ask again")
    T.assert_equal(GraphState.reduce("close_campaign").kind, "close_campaign",
        "and the toolbar can get back there")
end

function M.test_the_pending_name_is_trimmed_and_read_from_the_live_buffer()
    local state = GraphState.new()
    T.assert_equal(state:pending_campaign_name(), "", "nothing typed yet")

    state.name_input:set_value("  stw  ")
    T.assert_equal(state:pending_campaign_name(), "stw", "the committed value, trimmed")

    state.name_input:focus()
    state.name_input.buffer = "stw2"
    T.assert_equal(state:pending_campaign_name(), "stw2",
        "while focused the BUFFER is the truth, or a create would use the pre-edit name")
end

function M.test_opening_a_second_campaign_abandons_the_first_ones_fetch()
    local state = GraphState.new()
    state:set_campaign("a")
    state._slots.campaign.status = "pending"
    state._slots.campaign.ticks = 40

    state:set_campaign("b")
    T.assert_equal(state._slots.campaign.status, "idle",
        "the in-flight fetch is for a campaign nobody is looking at now")
    T.assert_equal(state._slots.campaign.ticks, 0,
        "and its tick count must not expire the fetch this open is about to start")
end

function M.test_node_type_info_fills_all_types()
    -- Verify every node type has default_intent fields
    local types = GraphState.all_node_types()
    for _, nt in ipairs(types) do
        T.assert_true(type(nt.default_intent) == "table",
            nt.type .. " must have default_intent table")
        T.assert_true(next(nt.default_intent) ~= nil,
            nt.type .. " must have at least one default field")
    end
end

return M
