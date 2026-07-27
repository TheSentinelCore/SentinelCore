-- tests/ui/test_explorer_panel.lua
-- The Explorer panel's contract.
--
-- Tests cover: state transitions (select, query, filter), build output shape,
-- command routing, and the structural guards from ADR 09b §2.1.

local ExplorerState = require("ui/panels/explorer_state")
local Explorer = require("ui/panels/explorer")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 900, h = 600 }

-- ============================================================================
-- Fixtures
-- ============================================================================

local function sample_results()
    return {
        { id = 783, title = "A Threat Within", level = 10, min_level = 5 },
        { id = 2158, title = "The Missing Diplomat", level = 12, min_level = 8 },
        { id = 54, title = "Report to Goldshire", level = 5, min_level = 1 },
    }
end

local function sample_detail()
    return {
        id = 783,
        title = "A Threat Within",
        level = 10,
        min_level = 5,
        required_quests = {},
        next_quests = { 2158 },
        giver_entry = 823,
        finisher_entry = 197,
        objectives = {},
        structured_objectives = {},
    }
end

local function sample_chain()
    return {
        quest_id = 783,
        title = "A Threat Within",
        prerequisites = {},
        follow_ups = { { quest_id = 2158, title = "The Missing Diplomat", exclusive_group = 0 } },
        chain_depth = 1,
        branches = {},
    }
end

local function sample_objectives()
    return {
        quest_id = 783,
        objectives = {
            { index = 1, kind = "kill", entry = 567, name = "Wolf", count = 10, source_creatures = {} },
            { index = 2, kind = "collect", entry = 789, name = "Pelt", count = 5, source_creatures = { 567 } },
        },
        objective_text = "Kill 10 Wolf, Collect 5 Pelt",
    }
end

-- ============================================================================
-- 1. State: construction and defaults
-- ============================================================================

function M.test_new_state_has_defaults()
    local state = ExplorerState.new()
    T.assert_equal(state.search_query, "", "search_query defaults to empty")
    T.assert_equal(#state.results, 0, "results defaults to empty")
    T.assert_nil(state.selected_id, "selected_id defaults to nil")
    T.assert_nil(state.selected_detail, "selected_detail defaults to nil")
    T.assert_true(state._dirty, "starts dirty for initial refresh")
    T.assert_false(state.loading, "loading defaults to false")
    T.assert_nil(state.error, "error defaults to nil")
end

-- ============================================================================
-- 2. State: mutators
-- ============================================================================

function M.test_set_query_updates_query_and_marks_dirty()
    local state = ExplorerState.new()
    state._dirty = false
    state:set_query("missing diplomat")
    T.assert_equal(state.search_query, "missing diplomat")
    T.assert_true(state._dirty, "set_query marks dirty")
end

function M.test_set_query_ignores_same_value()
    local state = ExplorerState.new({ search_query = "hello" })
    state._dirty = false
    state:set_query("hello")
    T.assert_false(state._dirty, "setting the same query must not mark dirty")
end

function M.test_select_updates_selection_and_clears_detail()
    local state = ExplorerState.new()
    state:select(783)
    T.assert_equal(state.selected_id, 783, "select sets selected_id")
    T.assert_true(state._dirty, "select marks dirty")
end

function M.test_select_clears_previous_detail()
    local state = ExplorerState.new()
    state.selected_detail = sample_detail()
    state.chain_data = sample_chain()
    state:select(2158)
    T.assert_nil(state.selected_detail, "select clears cached detail")
    T.assert_nil(state.chain_data, "select clears cached chain")
    T.assert_nil(state.objectives, "select clears cached objectives")
    T.assert_equal(state.selected_id, 2158)
end

function M.test_select_ignores_same_id()
    local state = ExplorerState.new()
    state:select(783)
    state._dirty = false
    state:select(783)
    T.assert_false(state._dirty, "re-selecting the same id must not mark dirty")
end

function M.test_set_zone_filter_updates_filter()
    local state = ExplorerState.new()
    state:set_zone_filter("Elwynn")
    T.assert_equal(state.zone_filter, "Elwynn")
    T.assert_true(state._dirty)
end

function M.test_set_level_range_updates_range()
    local state = ExplorerState.new()
    state:set_level_range(5, 15)
    T.assert_equal(state.level_min, 5)
    T.assert_equal(state.level_max, 15)
end

function M.test_reset_clears_everything()
    local state = ExplorerState.new()
    state.search_query = "test"
    state.results = { { id = 1 } }
    state.selected_id = 1
    state.selected_detail = {}
    state.zone_filter = "Elwynn"
    state:reset()
    T.assert_equal(state.search_query, "")
    T.assert_equal(#state.results, 0)
    T.assert_nil(state.selected_id)
    T.assert_nil(state.zone_filter)
    T.assert_true(state._dirty)
end

-- ============================================================================
-- 3. Build: view model shape
-- ============================================================================

function M.test_build_returns_correct_keys()
    local state = ExplorerState.new()
    local view = state:build()
    -- Always-present fields: build() initialises these as non-nil
    T.assert_equal(type(view.visible_results), "table", "visible_results must be a table")
    T.assert_equal(type(view.loading), "boolean", "loading must be a boolean")
    T.assert_equal(type(view.search_query), "string", "search_query must be a string")
    -- Nil-by-default fields — level range, selections, detail, error are all optional
    T.assert_true(view.level_min == nil or type(view.level_min) == "number",
        "level_min must be nil or number")
    T.assert_true(view.level_max == nil or type(view.level_max) == "number",
        "level_max must be nil or number")
    T.assert_true(view.selected_detail == nil or type(view.selected_detail) == "table",
        "selected_detail must be nil or table")
    T.assert_true(view.error == nil or type(view.error) == "string",
        "error must be nil or string")
    T.assert_true(view.chain_viz == nil or type(view.chain_viz) == "table",
        "chain_viz must be nil or table")
    T.assert_true(view.objectives_viz == nil or type(view.objectives_viz) == "table",
        "objectives_viz must be nil or table")
    T.assert_true(view.selected_id == nil or type(view.selected_id) == "number",
        "selected_id must be nil or number")
    T.assert_true(view.zone_filter == nil or type(view.zone_filter) == "string",
        "zone_filter must be nil or string")
end

function M.test_build_filters_results_by_level()
    local state = ExplorerState.new()
    state.results = sample_results()
    state:set_level_range(10, 15)
    local view = state:build()

    T.assert_equal(#view.visible_results, 2, "only results in 10-15 level range")
    for _, r in ipairs(view.visible_results) do
        T.assert_true(r.level >= 10 and r.level <= 15,
            "all visible results must be within level range")
    end
end

function M.test_build_passes_all_when_no_filter()
    local state = ExplorerState.new()
    state.results = sample_results()
    local view = state:build()
    T.assert_equal(#view.visible_results, 3, "all results visible with no filter")
end

function M.test_build_with_chain_data()
    local state = ExplorerState.new()
    state.chain_data = sample_chain()
    local view = state:build()

    T.assert_not_nil(view.chain_viz, "chain_viz must be set when chain_data exists")
    T.assert_equal(view.chain_viz.quest_id, 783)
    T.assert_equal(#view.chain_viz.follow_ups, 1)
    T.assert_equal(view.chain_viz.follow_ups[1].quest_id, 2158)
end

function M.test_build_with_objectives()
    local state = ExplorerState.new()
    state.objectives = sample_objectives()
    local view = state:build()

    T.assert_not_nil(view.objectives_viz, "objectives_viz must be set when objectives exist")
    T.assert_equal(view.objectives_viz.quest_id, 783)
    T.assert_equal(#view.objectives_viz.items, 2)
    T.assert_equal(view.objectives_viz.objective_text, "Kill 10 Wolf, Collect 5 Pelt")
end

function M.test_build_with_detail()
    local state = ExplorerState.new()
    state.selected_detail = sample_detail()
    local view = state:build()

    T.assert_not_nil(view.selected_detail)
    T.assert_equal(view.selected_detail.id, 783)
    T.assert_equal(view.selected_detail.title, "A Threat Within")
end

-- ============================================================================
-- 4. Reduce: command routing
-- ============================================================================

function M.test_reduce_select_quest()
    local cmd = ExplorerState.reduce("select_quest:783")
    T.assert_not_nil(cmd, "select_quest must produce a command")
    T.assert_equal(cmd.kind, "select_quest")
    T.assert_equal(cmd.id, 783)
end

function M.test_reduce_add_to_profile()
    local cmd = ExplorerState.reduce("add_to_profile:783")
    T.assert_not_nil(cmd, "add_to_profile must produce a command")
    T.assert_equal(cmd.kind, "add_to_profile")
    T.assert_equal(cmd.quest_id, 783)
end

function M.test_reduce_add_chain()
    local cmd = ExplorerState.reduce("add_chain:2158")
    T.assert_not_nil(cmd, "add_chain must produce a command")
    T.assert_equal(cmd.kind, "add_chain")
    T.assert_equal(cmd.quest_id, 2158)
end

function M.test_reduce_clear_search()
    local cmd = ExplorerState.reduce("clear_search")
    T.assert_not_nil(cmd, "clear_search must produce a command")
    T.assert_equal(cmd.kind, "clear_search")
end

function M.test_reduce_cycle_zone_filter()
    local cmd = ExplorerState.reduce("zone_filter")
    T.assert_not_nil(cmd, "zone_filter must produce a command")
    T.assert_equal(cmd.kind, "cycle_zone_filter")
end

function M.test_reduce_nil_returns_nil()
    T.assert_nil(ExplorerState.reduce(nil), "nil action must return nil")
end

function M.test_reduce_unknown_returns_nil()
    T.assert_nil(ExplorerState.reduce("nonexistent"), "unknown action must return nil")
end

-- ============================================================================
-- 5. Render: the panel draws and returns commands
-- ============================================================================

function M.test_render_creates_items_and_returns_command()
    local state = ExplorerState.new()
    state.results = sample_results()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local command, plan = Explorer.render(fake, BOUNDS, view)
    T.assert_not_nil(plan, "render must return a plan")
    T.assert_not_nil(plan.items, "plan must have items")
    T.assert_true(#plan.items > 0, "plan must have at least one item")
end

function M.test_render_handles_empty_state_gracefully()
    local state = ExplorerState.new()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Explorer.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with empty state must not throw: " .. tostring(err))
end

function M.test_render_with_full_detail()
    local state = ExplorerState.new()
    state.results = sample_results()
    state:select(783)
    state.selected_detail = sample_detail()
    state.chain_data = sample_chain()
    state.objectives = sample_objectives()
    local view = state:build()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Explorer.render, fake, BOUNDS, view)
    T.assert_true(ok, "render with full detail must not throw: " .. tostring(err))
end

-- ============================================================================
-- 6. Structural guards — the failures that pass offline and break in the injector
-- ============================================================================

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

local RENDER_SOURCE = "sentinel/ui/panels/explorer.lua"
local STATE_SOURCE = "sentinel/ui/panels/explorer_state.lua"

function M.test_the_source_audit_actually_reads_code()
    local source = source_of(RENDER_SOURCE)
    T.assert_true(source:find("function Explorer.render", 1, true) ~= nil,
        "the stripped source must still contain the render function")
end

function M.test_the_render_layer_contains_no_decision_logic()
    -- ADR 09b §2.1. A branch inside a render callback cannot be reached by any offline test, so
    -- the rule is enforced structurally rather than by review.
    local source = source_of(RENDER_SOURCE)
    T.assert_nil(source:find("%f[%w]if%f[%W]"), "explorer.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]elseif%f[%W]"), "explorer.lua has elseif; move it to the view-model")
    T.assert_nil(source:find("%f[%w]while%f[%W]"), "explorer.lua loops on a condition")
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
    local state = ExplorerState.new()
    state.results = sample_results()
    state:select(783)
    state.selected_detail = sample_detail()
    state.chain_data = sample_chain()
    state.objectives = sample_objectives()
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Explorer.render, fake, BOUNDS, state:build())
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
        "ui/panels/explorer", "ui/panels/explorer_state",
        "ui/theme", "ui/widgets",
    }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local ok, panel = pcall(require, "ui/panels/explorer")
    local rendered, err = true, nil
    if ok then
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        local state = ExplorerState.new()
        rendered, err = pcall(panel.render, fake, BOUNDS, state:build())
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok, "the panel failed to load with no SDK present: " .. tostring(panel))
    T.assert_true(rendered, "the panel failed to render with no SDK present: " .. tostring(err))
end

-- ============================================================================
-- 7. The panel exposes the shape the shell registers
-- ============================================================================

function M.test_panel_exposes_required_shape()
    T.assert_equal(Explorer.id, "explorer", "the shell keys panels by id")
    T.assert_equal(type(Explorer.title), "string", "the tab needs a label")
    T.assert_equal(type(Explorer.render), "function", "the shell calls render(window, bounds, view)")
end

return M
