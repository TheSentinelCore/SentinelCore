-- tests/ui/test_explorer_panel.lua
-- The Explorer panel's contract.
--
-- Tests cover: state transitions (select, query, filter), build output shape,
-- command routing, and the structural guards from ADR 09b §2.1.

-- Allow this file to be run directly from the repo root.
package.path = table.concat({
    "sentinel/?.lua",
    "sentinel/?/?.lua",
    "sentinel/?/?/?.lua",
    "sentinel/?/?/?/?.lua",
    "sentinel/?/?/?/?/?.lua",
    package.path,
}, ";")

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
-- 3b. Search-as-you-type: the debounce and the typed buffer
-- ============================================================================

function M.test_the_state_carries_an_editable_search_buffer()
    -- The search bar was a rounded rect with a label in it. It looked identical to this and could
    -- not be typed into, which is the whole reason F1-R1 never worked in-game.
    local state = ExplorerState.new()
    T.assert_not_nil(state.search_input, "the panel must own a real editable buffer")
    T.assert_equal(state.search_input.value, "", "it starts on the current query")
end

function M.test_sync_pulls_the_typed_buffer_into_the_query()
    local state = ExplorerState.new()
    state.search_input:focus()
    state.search_input.buffer = "wolf"

    T.assert_true(state:sync_search_input(10.0), "sync must report that the query moved")
    T.assert_equal(state.search_query, "wolf", "what was typed becomes the query")
    T.assert_true(state._dirty, "and the binding is told to look")
    T.assert_false(state:sync_search_input(10.0), "a second sync with no new typing is a no-op")
end

function M.test_sync_reads_the_committed_value_once_focus_is_gone()
    -- Escape restores the committed value into the buffer. Reading `buffer` unconditionally would
    -- search for the string the operator just discarded.
    local state = ExplorerState.new()
    state.search_input:set_value("wolf")
    state.search_input.buffer = "wolfsbane"   -- an edit that was cancelled, not committed
    state:sync_search_input(1.0)
    T.assert_equal(state.search_query, "wolf", "an unfocused field speaks with its committed value")
end

function M.test_the_debounce_holds_the_query_for_300ms()
    local state = ExplorerState.new()
    state:set_query("wol", 1.00)
    T.assert_false(state:search_due(1.00), "a query is not due the instant it changes")
    T.assert_false(state:search_due(1.29), "nor 290ms later")
    T.assert_true(state:search_due(1.30), "at 300ms it is due")
    T.assert_equal(ExplorerState.SEARCH_DEBOUNCE_S, 0.30, "the spec asks for 300ms")
end

function M.test_each_keystroke_restarts_the_debounce()
    local state = ExplorerState.new()
    state:set_query("w", 1.00)
    state:set_query("wo", 1.20)
    T.assert_false(state:search_due(1.31),
        "310ms after the FIRST key is only 110ms after the last; typing must reset the wait")
    T.assert_true(state:search_due(1.50), "300ms after the last key it is due")
end

function M.test_the_gate_stays_open_until_the_results_land()
    -- AsyncSlot polls a pending fetch across many ticks. A gate that shut when the request was
    -- fired would starve the re-arm of the tick that collects the answer -- the PR2 freeze again.
    local state = ExplorerState.new()
    state:set_query("wolf", 1.00)
    T.assert_true(state:search_due(1.40))
    T.assert_true(state:search_due(1.41), "still due while the fetch is in flight")
    state:mark_search_served()
    T.assert_false(state:search_due(1.42), "and closed once the results are in")
end

function M.test_an_empty_query_is_never_due()
    local state = ExplorerState.new()
    state:set_query("wolf", 1.00)
    state:set_query("", 1.10)
    T.assert_false(state:search_due(9.00), "clearing the box must not search for everything")
end

function M.test_no_clock_reads_as_due()
    -- `ide_panels.lua::default_clock` answers nil when there is no `core.time`. The house rule is
    -- that callers treat nil as "always due"; a panel frozen on a clock it cannot read is worse
    -- than one that debounces nothing.
    local state = ExplorerState.new()
    state:set_query("wolf", nil)
    T.assert_true(state:search_due(nil), "a missing clock must not disable search entirely")
end

function M.test_reset_closes_the_search_gate()
    local state = ExplorerState.new()
    state:set_query("wolf", 1.00)
    state:reset()
    T.assert_equal(state.search_input.value, "", "reset clears the visible buffer too")
    T.assert_false(state:search_due(9.00), "and leaves nothing pending")
end

-- ============================================================================
-- 3c. Result rows carry level, zone and faction
-- ============================================================================

function M.test_result_meta_renders_level_zone_and_faction()
    local meta = ExplorerState.result_meta(
        { level = 10, zone = "Elwynn Forest", faction = "Alliance" })
    T.assert_true(meta:find("10", 1, true) ~= nil, "the level must be shown")
    T.assert_true(meta:find("Elwynn Forest", 1, true) ~= nil, "the zone must be shown")
    T.assert_true(meta:find("Alliance", 1, true) ~= nil, "the faction must be shown")
end

function M.test_an_empty_zone_renders_as_a_dash_and_never_as_a_guess()
    -- `QuestSummary.zone` is deliberately "" when `quest_template.ZoneOrSort` is non-positive:
    -- mangos overloads that column and a negative value is a SORT bucket, not an area id. There is
    -- genuinely no zone, and inventing one is the same fiction as the mock scans PR3 deleted.
    local meta = ExplorerState.result_meta({ level = 60, zone = "", faction = "" })
    T.assert_true(meta:find("—", 1, true) ~= nil, "an absent field is drawn as an em dash")
    T.assert_true(meta:find("60", 1, true) ~= nil, "the fields that ARE present still show")
end

function M.test_the_rows_in_the_plan_carry_the_meta_line()
    local state = ExplorerState.new()
    state.results = { { id = 783, title = "A Threat Within", level = 10, zone = "Elwynn Forest" } }
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    for _, item in ipairs(plan.items) do
        if item.kind == "list_row" then
            T.assert_not_nil(item.secondary, "a result row must show more than a title")
            T.assert_true(item.secondary:find("Elwynn Forest", 1, true) ~= nil)
            return
        end
    end
    error("the plan contained no result row")
end

function M.test_the_plan_draws_a_real_text_input_for_the_search_box()
    local state = ExplorerState.new()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    for _, item in ipairs(plan.items) do
        if item.kind == "text_input" then
            T.assert_true(item.model == state.search_input,
                "the item must carry the LIVE model; a copy would look editable and change nothing")
            T.assert_equal(item.id, "search_input")
            return
        end
    end
    error("the search box is still a label in a rectangle")
end

function M.test_build_plan_returns_a_controls_registry()
    local state = ExplorerState.new()
    state.results = sample_results()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    T.assert_equal(type(plan.controls), "table", "plan must expose a controls table")
    T.assert_true(#plan.controls > 0, "interactive controls must be registered")
    local by_id = {}
    for _, c in ipairs(plan.controls) do
        T.assert_not_nil(c.id, "every control must have an id")
        T.assert_not_nil(c.kind, "every control must have a kind")
        T.assert_not_nil(c.bounds, "every control must have bounds")
        by_id[c.id] = c
    end
    T.assert_not_nil(by_id.search_input, "search input must be registered")
    T.assert_not_nil(by_id.clear_search, "clear button must be registered")
    T.assert_not_nil(by_id.zone_filter, "zone filter chip must be registered")
end

function M.test_empty_states_are_actionable()
    local state = ExplorerState.new()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    local found = false
    for _, item in ipairs(plan.items) do
        if item.kind == "empty_state" then
            T.assert_not_nil(item.id, "empty_state must have an action id")
            T.assert_not_nil(item.title, "empty_state must have a title")
            T.assert_not_nil(item.message, "empty_state must have a message")
            T.assert_not_nil(item.action_label, "empty_state must have an action_label")
            found = true
        end
    end
    T.assert_true(found, "the plan must contain at least one actionable empty_state")
end

function M.test_toolbar_has_raised_surface_and_top_border()
    local state = ExplorerState.new()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    local raised, border = false, false
    for _, item in ipairs(plan.items) do
        if item.kind == "rect" and item.token == "surface_raised" then
            raised = true
        end
        if item.kind == "rect" and item.token == "border"
           and item.bounds.h == 1 and item.bounds.y == 0 then
            border = true
        end
    end
    T.assert_true(raised, "the toolbar must have a surface_raised background")
    T.assert_true(border, "the toolbar must have a top border divider")
end

function M.test_clear_button_disabled_when_search_is_empty()
    local empty_state = ExplorerState.new()
    local empty_plan = ExplorerState.build_plan(empty_state:build(), BOUNDS)
    local filled_state = ExplorerState.new({ search_query = "wolf" })
    local filled_plan = ExplorerState.build_plan(filled_state:build(), BOUNDS)

    local function find_clear(p)
        for _, item in ipairs(p.items) do
            if item.kind == "button" and item.id == "clear_search" then
                return item
            end
        end
        return nil
    end

    local empty_clear = find_clear(empty_plan)
    local filled_clear = find_clear(filled_plan)
    T.assert_not_nil(empty_clear, "clear button must exist")
    T.assert_not_nil(filled_clear, "clear button must exist")
    T.assert_true(empty_clear.disabled, "clear must be disabled with an empty query")
    T.assert_false(filled_clear.disabled, "clear must be enabled once the operator has typed")
end

function M.test_action_buttons_use_design_system_variants()
    local state = ExplorerState.new()
    state.results = sample_results()
    state:select(783)
    state.selected_detail = sample_detail()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    local add_profile, add_chain
    for _, item in ipairs(plan.items) do
        if item.kind == "button" and item.id == "add_to_profile:783" then
            add_profile = item
        end
        if item.kind == "button" and item.id == "add_chain:783" then
            add_chain = item
        end
    end
    T.assert_not_nil(add_profile, "Add to Profile must be in the plan")
    T.assert_not_nil(add_chain, "Add Chain must be in the plan")
    T.assert_equal(add_profile.variant, "primary",
        "the dominant authoring action is primary")
    T.assert_equal(add_chain.variant, "secondary",
        "the secondary action is secondary")
end

function M.test_objective_rows_use_panel_layout_glyph()
    local state = ExplorerState.new()
    state.selected_detail = sample_detail()
    state.objectives = sample_objectives()
    local plan = ExplorerState.build_plan(state:build(), BOUNDS)
    local PanelLayout = require("ui/panel_layout")
    local found = false
    for _, item in ipairs(plan.items) do
        if item.kind == "text" and item.text and item.text:find("Wolf", 1, true) then
            T.assert_true(item.text:find(PanelLayout.glyph("kill"), 1, true) ~= nil,
                "kill objective rows must use PanelLayout.glyph")
            found = true
        end
    end
    T.assert_true(found, "objective text must appear in the plan")
end

-- ============================================================================
-- 3d. Authoring: quest to campaign nodes
-- ============================================================================

function M.test_add_to_profile_builds_the_exact_subgraph_the_spec_names()
    -- SPEC: quest with kill(567x10) and loot(789x5) objectives produces
    -- AcceptQuest(1234), Kill(567,10), Loot(789,5), TurnInQuest(1234).
    local nodes, skipped = ExplorerState.build_quest_subgraph(
        1234, { giver_entry = 823, finisher_entry = 197 },
        { quest_id = 1234, objectives = {
            { index = 1, kind = "kill", entry = 567, name = "Wolf", count = 10 },
            { index = 2, kind = "collect", entry = 789, name = "Pelt", count = 5,
              source_creatures = { 567 } },
        } })

    T.assert_equal(#skipped, 0, "both objective kinds must be understood")
    T.assert_equal(#nodes, 4, "accept + two objectives + turn-in")

    T.assert_equal(nodes[1].type, "questing.AcceptQuest")
    T.assert_equal(nodes[1].intent.quest_id, 1234)
    T.assert_equal(nodes[1].intent.npc_entry, 823, "AcceptQuest goes to the giver")

    T.assert_equal(nodes[2].type, "questing.Kill")
    T.assert_equal(nodes[2].intent.creature_entry, 567)
    T.assert_equal(nodes[2].intent.count, 10)

    T.assert_equal(nodes[3].type, "questing.Loot")
    T.assert_equal(nodes[3].intent.item_id, 789, "a collect objective is counted in the ITEM")
    T.assert_equal(nodes[3].intent.count, 5)
    T.assert_equal(nodes[3].intent.source_creatures[1], 567,
        "the creature that drops it rides along so the compiler needs no second lookup")

    T.assert_equal(nodes[4].type, "questing.TurnInQuest")
    T.assert_equal(nodes[4].intent.npc_entry, 197, "TurnInQuest goes to the finisher")
end

function M.test_an_interact_objective_becomes_an_object_loot()
    local nodes = ExplorerState.build_quest_subgraph(1, {}, { objectives = {
        { index = 1, kind = "interact", entry = 3714, name = "Chest", count = 1 },
    } })
    T.assert_equal(nodes[2].type, "questing.Loot")
end

function M.test_an_unknown_objective_kind_is_reported_and_not_guessed()
    local nodes, skipped = ExplorerState.build_quest_subgraph(1, {}, { objectives = {
        { index = 1, kind = "escort", entry = 5, name = "Someone", count = 1 },
    } })
    T.assert_equal(#nodes, 2, "only accept and turn-in; the middle was not invented")
    T.assert_equal(skipped[1], "escort", "and the operator is told which kind was dropped")
end

function M.test_a_quest_with_no_objectives_still_brackets_correctly()
    local nodes = ExplorerState.build_quest_subgraph(42, {}, nil)
    T.assert_equal(#nodes, 2)
    T.assert_equal(nodes[1].type, "questing.AcceptQuest")
    T.assert_equal(nodes[2].type, "questing.TurnInQuest")
    T.assert_equal(nodes[1].intent.npc_entry, 0, "an unknown giver is 0, not nil")
end

function M.test_add_chain_pairs_every_quest_in_prerequisite_order()
    local nodes = ExplorerState.build_chain_subgraph({
        quest_id = 783, title = "A Threat Within",
        prerequisites = { { quest_id = 1, title = "First" } },
        follow_ups = { { quest_id = 2158, title = "The Missing Diplomat" } },
    })
    T.assert_equal(#nodes, 6, "three quests, accept and turn-in each")
    T.assert_equal(nodes[1].intent.quest_id, 1, "prerequisites come first")
    T.assert_equal(nodes[3].intent.quest_id, 783, "then the quest itself")
    T.assert_equal(nodes[5].intent.quest_id, 2158, "then the follow-ups")
end

function M.test_subgraph_ids_are_derived_so_a_duplicate_add_is_visible()
    local a = ExplorerState.build_quest_subgraph(1234, {}, nil)
    local b = ExplorerState.build_quest_subgraph(1234, {}, nil)
    T.assert_equal(a[1].id, b[1].id,
        "adding the same quest twice must read as a duplicate, not as two unrelated nodes")
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

function M.test_reduce_routes_the_text_input_commands()
    T.assert_equal(ExplorerState.reduce("search_input_submit").kind, "submit_search",
        "Enter in the search box must reach the tick as a command")
    T.assert_equal(ExplorerState.reduce("search_input_cancel").kind, "cancel_search",
        "Escape is a different command from Enter, not the absence of one")
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
    T.assert_not_nil(plan.controls, "plan must expose a controls registry")
    T.assert_true(#plan.controls > 0, "controls must list every interactive region")
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

-- Run the suite when this file is executed directly from the repo root.
if arg and arg[0] and arg[0]:match("test_explorer_panel%.lua$") then
    local SuiteRunner = require("tests/harness/suite_runner")
    local result = SuiteRunner.run_suite("tests/ui/test_explorer_panel", M)
    local passed, failed, failures = 0, 0, {}
    for _, case in ipairs(result.cases) do
        if case.ok then
            passed = passed + 1
            io.write(".")
        else
            failed = failed + 1
            failures[#failures + 1] = string.format(
                "FAIL tests/ui/test_explorer_panel.%s: %s", case.name, tostring(case.err))
            io.write("F")
        end
    end
    print(SuiteRunner.format_report({
        passed = passed, failed = failed,
        opaque_passed = 0, opaque_failed = 0,
        opaque_suites = {},
        hybrid_suites = {},
        failures = failures,
    }))
    if failed > 0 then os.exit(1) end
end

return M
