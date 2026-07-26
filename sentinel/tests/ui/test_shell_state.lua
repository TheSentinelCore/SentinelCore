-- tests/ui/test_shell_state.lua
-- The IDE shell's view-model (ADR 09b §2.1, §4, §5).
--
-- Everything the shell DECIDES is decided here, so everything the shell decides is asserted here.
-- The render module is a projection with no branches of its own to test; if a rule about tab
-- order, activation, emptiness, clamping or motion is not pinned in this file, it is not pinned
-- anywhere, because `register_on_render_window_callback` cannot be entered outside the injector.
--
-- Not one line below touches `core.*`. That is the property that makes the split real rather than
-- aspirational: a decision that needed the SDK would have had to be written in the render layer.

local ShellState = require("ui/shell_state")
local T = require("tests/test_util")

local M = {}

--- A panel spec whose render function records that it was asked to draw.
--- U3-U7 hand the shell exactly this shape; nothing here knows what any of them contain.
local function panel(id, extra)
    local spec = { id = id, render = function() end }
    for key, value in pairs(extra or {}) do spec[key] = value end
    return spec
end

local function ids_of(tabs)
    local out = {}
    for i, tab in ipairs(tabs) do out[i] = tab.id end
    return out
end

local function joined(tabs)
    return table.concat(ids_of(tabs), ",")
end

local function active_id_of(tabs)
    local found = nil
    for _, tab in ipairs(tabs) do
        if tab.active then
            T.assert_nil(found, "two tabs claimed to be active at once")
            found = tab.id
        end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

function M.test_a_panel_registered_after_construction_appears_in_the_switcher()
    -- The whole reason registration exists (ADR 09b §6): U3-U7 must be able to add a panel
    -- WITHOUT editing the shell, or every later unit collides in one file.
    local state = ShellState.new()
    T.assert_equal(#state:tabs(), 0, "a shell with no panels registered offers no tabs")

    T.assert_true(state:register_panel(panel("graph")), "registration must succeed")
    T.assert_equal(joined(state:tabs()), "graph", "the newly registered panel must be offered")
end

function M.test_the_runner_panel_leads_the_tab_order_whatever_order_panels_register_in()
    -- ADR 09b §4: "the bot running correctly matters more often than authoring does". Load order
    -- is an accident of require order, so it must not decide what the operator sees first.
    local state = ShellState.new()
    for _, id in ipairs({ "database", "properties", "graph", "explorer", "runner" }) do
        state:register_panel(panel(id))
    end
    T.assert_equal(joined(state:tabs()), "runner,explorer,graph,properties,database",
        "the declared topology, not registration order, sets the tab order")
end

function M.test_a_panel_outside_the_declared_order_appends_rather_than_being_dropped()
    -- The declared order is a SLOT MAP, not an allow-list. A shell that silently dropped an
    -- unrecognised panel would make a future unit's panel invisible with no error to follow.
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    state:register_panel(panel("simulator"))
    state:register_panel(panel("database"))
    T.assert_equal(joined(state:tabs()), "runner,database,simulator",
        "an unlisted panel takes a place after every declared slot")
end

function M.test_an_explicit_order_overrides_the_declared_slot()
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    state:register_panel(panel("database", { order = -1 }))
    T.assert_equal(joined(state:tabs()), "database,runner",
        "an explicit order must win, or a panel can never be repositioned without a shell edit")
end

function M.test_registration_without_a_render_function_is_refused_with_a_reason()
    -- Accepting it would defer the failure to the first frame the panel is selected, inside a
    -- render callback, where the only symptom is a blank pane.
    local state = ShellState.new()
    local ok, reason = state:register_panel({ id = "graph" })
    T.assert_false(ok, "a panel with no render function cannot be registered")
    T.assert_true(type(reason) == "string" and reason ~= "", "and the refusal must say why")

    local ok2, reason2 = state:register_panel({ render = function() end })
    T.assert_false(ok2, "a panel with no id cannot be registered")
    T.assert_true(type(reason2) == "string" and reason2 ~= "", "and the refusal must say why")
    T.assert_equal(#state:tabs(), 0, "neither refusal may leave a half-registered panel behind")
end

function M.test_re_registering_an_id_replaces_it_rather_than_duplicating_it()
    -- A plugin reload re-runs registration. Appending would grow the switcher one tab per reload.
    local state = ShellState.new()
    state:register_panel(panel("runner", { title = "Old" }))
    state:register_panel(panel("runner", { title = "New" }))
    local tabs = state:tabs()
    T.assert_equal(#tabs, 1, "re-registration must replace, not duplicate")
    T.assert_equal(tabs[1].title, "New", "and the later registration must win")
end

function M.test_a_panel_title_defaults_to_its_id()
    local state = ShellState.new()
    state:register_panel(panel("properties"))
    T.assert_equal(state:tabs()[1].title, "Properties",
        "a panel that supplies no title must still be nameable in the switcher")
end

function M.test_a_badge_reaches_the_tab_view()
    -- Diagnostic counts are the reason badges exist (ADR 09b §5.3): an author must see that a
    -- panel has something to say without opening it.
    local state = ShellState.new()
    state:register_panel(panel("properties", { badge = "3" }))
    T.assert_equal(state:tabs()[1].badge, "3", "the badge must reach the switcher projection")
end

-- ---------------------------------------------------------------------------
-- Activation
-- ---------------------------------------------------------------------------

function M.test_the_first_registered_panel_becomes_active()
    local state = ShellState.new()
    T.assert_nil(state:active_panel(), "nothing is active before anything is registered")
    state:register_panel(panel("explorer"))
    T.assert_equal(state:active_id(), "explorer",
        "the shell must never sit on no panel at all once one exists")
end

function M.test_exactly_one_tab_is_active_at_a_time()
    local state = ShellState.new()
    for _, id in ipairs({ "runner", "graph", "database" }) do state:register_panel(panel(id)) end
    T.assert_equal(active_id_of(state:tabs()), "runner", "exactly one tab starts active")

    T.assert_true(state:activate("graph"), "activation reports that it changed something")
    T.assert_equal(active_id_of(state:tabs()), "graph", "and exactly one tab is active after")
end

function M.test_activating_a_panel_changes_only_which_panel_is_active()
    -- The switcher is not allowed to be a side-effect surface: an operator switching tabs to look
    -- at something must not disturb the run.
    local state = ShellState.new()
    for _, id in ipairs({ "runner", "graph" }) do state:register_panel(panel(id)) end
    state:set_campaign("Northshire")
    state:set_split_ratio("primary", 0.4)
    state:show()

    state:activate("graph")

    T.assert_equal(state:campaign(), "Northshire", "switching tabs must not close the campaign")
    T.assert_near(state:split_ratio("primary"), 0.4, 1e-9, "nor move a divider")
    T.assert_true(state:is_visible(), "nor change visibility")
    T.assert_equal(joined(state:tabs()), "runner,graph", "nor reorder the switcher")
end

function M.test_activating_an_unregistered_panel_changes_nothing()
    -- Persisted layout can name a panel whose unit has not shipped yet. Clearing the active panel
    -- there would open the IDE on a blank pane after an upgrade.
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    T.assert_false(state:activate("map"), "an unknown id cannot be activated")
    T.assert_equal(state:active_id(), "runner", "and must leave the active panel alone")
end

function M.test_reactivating_the_active_panel_reports_no_change()
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    T.assert_false(state:activate("runner"),
        "a no-op activation must report false, or the layout is marked dirty every frame")
end

-- ---------------------------------------------------------------------------
-- Layout persistence
-- ---------------------------------------------------------------------------

function M.test_a_layout_snapshot_round_trips()
    local state = ShellState.new()
    for _, id in ipairs({ "runner", "graph" }) do state:register_panel(panel(id)) end
    state:set_window_geometry({ x = 310, y = 220 }, { x = 1024, y = 700 })
    state:activate("graph")
    state:set_split_ratio("primary", 0.42)

    local snapshot = state:layout()

    local restored = ShellState.new()
    restored:restore(snapshot)
    for _, id in ipairs({ "runner", "graph" }) do restored:register_panel(panel(id)) end

    T.assert_equal(restored:active_id(), "graph", "the active panel must survive the round trip")
    T.assert_near(restored:split_ratio("primary"), 0.42, 1e-9, "and so must the divider")
    T.assert_equal(restored:layout().position.x, 310, "and the window position")
    T.assert_equal(restored:layout().size.y, 700, "and the window size")
end

function M.test_a_restored_active_panel_beats_the_first_registration()
    -- Restore happens at load; panels register afterwards, one require at a time. If the first
    -- registration always won, the persisted choice would be overwritten before it was ever used.
    local state = ShellState.new()
    state:restore({ active_slot = ShellState.slot_index("graph") })
    state:register_panel(panel("runner"))
    T.assert_equal(state:active_id(), "runner",
        "until it registers, the restored panel cannot be shown -- something must be")
    state:register_panel(panel("graph"))
    T.assert_equal(state:active_id(), "graph",
        "the restored panel must claim the switcher as soon as it exists")
end

function M.test_a_restored_panel_that_never_registers_is_forgotten_after_one_activation()
    -- Otherwise a panel whose unit was removed would keep stealing the operator's tab choice.
    local state = ShellState.new()
    state:restore({ active_slot = ShellState.slot_index("graph") })
    state:register_panel(panel("runner"))
    state:activate("runner")
    state:register_panel(panel("graph"))
    T.assert_equal(state:active_id(), "runner",
        "an explicit choice must retire the pending restore")
end

function M.test_layout_differences_are_detected_so_persistence_is_not_written_every_frame()
    local a = { position = { x = 1, y = 2 }, size = { x = 3, y = 4 }, active_slot = 1,
                splits = { primary = 0.5 } }
    local b = { position = { x = 1, y = 2 }, size = { x = 3, y = 4 }, active_slot = 1,
                splits = { primary = 0.5 } }
    T.assert_false(ShellState.layout_differs(a, b), "identical layouts must compare equal")
    b.active_slot = 2
    T.assert_true(ShellState.layout_differs(a, b), "a changed tab must be detected")
    b.active_slot = 1
    b.splits.primary = 0.51
    T.assert_true(ShellState.layout_differs(a, b), "a moved divider must be detected")
    T.assert_true(ShellState.layout_differs(a, nil), "an absent baseline is always a difference")
end

-- ---------------------------------------------------------------------------
-- Splits
-- ---------------------------------------------------------------------------

function M.test_split_ratios_are_clamped_to_a_usable_range()
    -- A divider dragged to the edge leaves a pane too narrow to click, and nothing in the UI can
    -- then reach the divider to drag it back. The clamp is the only way out of that.
    local state = ShellState.new()
    T.assert_near(state:set_split_ratio("primary", -3), ShellState.MIN_SPLIT_RATIO, 1e-9,
        "a ratio below the floor is clamped")
    T.assert_near(state:set_split_ratio("primary", 42), ShellState.MAX_SPLIT_RATIO, 1e-9,
        "a ratio above the ceiling is clamped")
    T.assert_near(state:set_split_ratio("primary", 0.5), 0.5, 1e-9, "a usable ratio is kept")
end

function M.test_an_unset_split_has_a_default_rather_than_nil()
    local state = ShellState.new()
    T.assert_near(state:split_ratio("primary"), ShellState.DEFAULT_SPLIT_RATIO, 1e-9,
        "a panel asking for a divider before one was ever dragged must still get geometry")
end

function M.test_a_pointer_drag_maps_to_a_clamped_ratio()
    local bounds = { x = 100, y = 50, w = 400, h = 300 }
    T.assert_near(ShellState.ratio_from_pointer(bounds, { x = 300, y = 100 }, "x"), 0.5, 1e-9,
        "the pointer's offset along the axis is the ratio")
    T.assert_near(ShellState.ratio_from_pointer(bounds, { x = 50, y = 100 }, "x"),
        ShellState.MIN_SPLIT_RATIO, 1e-9, "a drag past the edge is clamped, not negative")
    T.assert_near(ShellState.ratio_from_pointer(bounds, { x = 200, y = 200 }, "y"), 0.5, 1e-9,
        "the vertical axis measures against height")
    T.assert_nil(ShellState.ratio_from_pointer(bounds, nil, "x"),
        "no pointer means no ratio, not a ratio of zero")
end

-- ---------------------------------------------------------------------------
-- Empty states (ADR 09b §5.5)
-- ---------------------------------------------------------------------------

function M.test_the_empty_state_instructs_when_no_panel_is_registered()
    -- This is what a user meets today: U3-U7 have not shipped. A blank window here reads as a
    -- broken plugin rather than an incomplete one.
    local state = ShellState.new()
    local empty = state:empty_state()
    T.assert_not_nil(empty, "a shell with no panels must explain itself")
    T.assert_true(type(empty.message) == "string" and empty.message ~= "",
        "and the explanation must be a sentence, not a title alone")
end

function M.test_the_empty_state_instructs_when_the_active_panel_needs_a_campaign()
    local state = ShellState.new()
    state:register_panel(panel("explorer", { requires_campaign = true }))
    local empty = state:empty_state()
    T.assert_not_nil(empty, "a campaign-backed panel with no campaign must instruct")
    T.assert_true(empty.title:find("campaign", 1, true) ~= nil,
        "the copy must name what is missing: " .. tostring(empty.title))
    T.assert_true(type(empty.action_id) == "string" and empty.action_id ~= "",
        "an empty state that only complains leaves the user with nowhere to go")

    state:set_campaign("Northshire")
    T.assert_nil(state:empty_state(), "once a campaign is open the panel body takes over")
end

function M.test_a_panel_that_needs_no_campaign_is_never_replaced_by_an_empty_state()
    -- The Runner is useful with no campaign at all -- it runs compiled profiles. Blanking it
    -- would hide the run behind an authoring prompt.
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    T.assert_nil(state:empty_state(), "the runner must render even with no campaign open")
end

-- ---------------------------------------------------------------------------
-- Visibility, input edges, motion
-- ---------------------------------------------------------------------------

function M.test_visibility_starts_closed_and_toggles()
    -- An IDE that opens itself on injection covers the game for a user who only wanted the bot.
    local state = ShellState.new()
    T.assert_false(state:is_visible(), "the shell starts closed")
    T.assert_true(state:toggle(), "toggle reports the new visibility")
    T.assert_true(state:is_visible(), "and opens it")
    state:hide()
    T.assert_false(state:is_visible(), "hide closes it")
end

function M.test_an_input_edge_fires_once_per_press()
    -- `is_key_pressed` and `keybind:get_state` are LEVEL signals polled every tick. Acting on the
    -- level would toggle the window sixty times a second for as long as the key is held.
    local state = ShellState.new()
    T.assert_false(state:edge("escape", false), "no edge while the key is up")
    T.assert_true(state:edge("escape", true), "the press is the edge")
    T.assert_false(state:edge("escape", true), "holding is not another edge")
    T.assert_false(state:edge("escape", false), "release is not an edge either")
    T.assert_true(state:edge("escape", true), "the next press is")
end

function M.test_edges_are_tracked_per_key()
    local state = ShellState.new()
    T.assert_true(state:edge("escape", true), "escape fires")
    T.assert_true(state:edge("toggle", true), "and the keybind fires independently")
end

function M.test_motion_is_suppressed_in_combat()
    -- ADR 09b §5.7: "Anything animating during combat is a bug."
    local state = ShellState.new()
    for _, id in ipairs({ "runner", "graph" }) do state:register_panel(panel(id)) end

    -- The first frame ever drawn establishes where the marker IS; it cannot slide in from
    -- nowhere, so animation only becomes possible from the second frame on.
    T.assert_false(state:marker_transition(40).animate,
        "the first frame places the marker rather than animating it")

    state:activate("graph")
    local moving = state:marker_transition(220)
    T.assert_true(moving.animate, "a tab change out of combat is worth explaining with motion")
    T.assert_equal(moving.to, 220, "and it targets the new tab")

    state:set_in_combat(true)
    state:activate("runner")
    local fought = state:marker_transition(40)
    T.assert_false(fought.animate, "nothing may animate during combat")
    T.assert_equal(fought.to, 40, "the marker still lands on the right tab, it just jumps")
end

function M.test_a_marker_that_has_not_moved_does_not_animate()
    local state = ShellState.new()
    state:register_panel(panel("runner"))
    state:marker_transition(120)
    T.assert_false(state:marker_transition(120).animate,
        "a stationary marker must not re-run its animation every frame")
end

-- ---------------------------------------------------------------------------
-- The split that keeps this file honest
-- ---------------------------------------------------------------------------

function M.test_the_view_model_never_reaches_for_the_sdk()
    -- If a decision needed `core.*` it would have had to live in the render callback, where no
    -- test can reach it. Scanning the source is the only way to keep that from happening quietly.
    local handle = io.open("sentinel/ui/shell_state.lua", "r")
    T.assert_not_nil(handle, "shell_state.lua must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    T.assert_nil(source:find("core%."), "shell_state.lua must not touch the Sylvannas API")
    T.assert_nil(source:find("require%s*%(%s*[\"']ui/widgets"), "the view-model must not draw")
end

return M
