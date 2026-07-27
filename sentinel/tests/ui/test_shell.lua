-- tests/ui/test_shell.lua
-- The IDE shell's chrome (ADR 09b §2.2, §2.3, §4, §5).
--
-- Everything here drives the real render path through the fake window, because the two rules this
-- unit can break are both invisible any other way:
--
--   1. A `core.menu.*` object constructed inside a render callback fails in the injector and
--      NOWHERE else. So the constructions are counted per phase rather than reviewed.
--   2. Layout that does not survive an injection is layout the operator re-arranges every time
--      they reload. Ghost sliders are the only resource that survives, so the round trip is
--      exercised against slider stand-ins rather than trusted.
--
-- The shell is constructed with an injected window and injected elements throughout. That is not
-- a testing seam bolted on: it is the same indirection that lets `main.lua` own construction in
-- the tick callback while this file owns none of it.

local Shell = require("ui/shell")
local ShellState = require("ui/shell_state")
local Theme = require("ui/theme")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

--- A stand-in for `core.menu.slider_int`: the two accessors documented in `api/ui-menu.md`, and
--- nothing else. Anything the shell calls that a real slider does not have raises here.
local function fake_slider(value)
    local s = { _value = value or 0 }
    function s:get() return self._value end
    function s:set(new_value) self._value = new_value end
    return s
end

--- The complete ghost-slider set, standing in for what survives an injection.
local function fake_elements()
    return {
        position_x = fake_slider(240), position_y = fake_slider(180),
        size_x = fake_slider(980), size_y = fake_slider(640),
        active_slot = fake_slider(1),
        split_primary = fake_slider(32), split_secondary = fake_slider(50),
    }
end

--- A panel that records every frame it was asked to draw, and what it was given.
local function recording_panel(id, extra)
    local spec = { id = id, renders = 0, bounds = nil, ctx = nil }
    spec.render = function(window, bounds, ctx)
        spec.renders = spec.renders + 1
        spec.bounds = bounds
        spec.ctx = ctx
        window:render_text(Theme.font.body, { x = bounds.x, y = bounds.y },
            Theme.color.text_primary(), "body:" .. id)
    end
    for key, value in pairs(extra or {}) do spec[key] = value end
    return spec
end

--- A visible shell over a fake window, with the panels registered in the given order.
local function open_shell(panels, elements)
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = elements })
    for _, spec in ipairs(panels or {}) do shell:register_panel(spec) end
    shell:show()
    return shell, fake
end

--- The switcher tab bounds for `id`, taken from the shell's own last layout rather than
--- recomputed here. A test that recomputed the geometry would pass while the shell drew elsewhere.
local function tab_bounds(shell, id)
    for _, entry in ipairs(shell:tab_layout()) do
        if entry.id == id then return entry.bounds end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The switcher
-- ---------------------------------------------------------------------------

function M.test_the_switcher_offers_one_tab_per_registered_panel()
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    shell:_on_render_window()

    T.assert_true(fake:drew_text("Runner"), "the Runner tab must be drawn")
    T.assert_true(fake:drew_text("Graph"), "the Graph tab must be drawn")
    T.assert_equal(#shell:tab_layout(), 2, "and no tab may be drawn for a panel nobody registered")
end

function M.test_a_panel_registered_after_construction_appears_without_a_shell_edit()
    -- The contract U3-U7 depend on (ADR 09b §6): the shell must never learn a panel's name from
    -- its own source. Registration is the only channel.
    local shell, fake = open_shell({ recording_panel("runner") })
    shell:_on_render_window()
    T.assert_false(fake:drew_text("Database"), "the panel does not exist yet")

    shell:register_panel(recording_panel("database"))
    fake:reset()
    shell:_on_render_window()
    T.assert_true(fake:drew_text("Database"), "registering it is enough to put it in the switcher")
end

function M.test_the_runner_tab_comes_first()
    -- ADR 09b §4. Registration order here is deliberately the reverse of the intended tab order.
    local shell = open_shell({
        recording_panel("database"), recording_panel("properties"),
        recording_panel("graph"), recording_panel("explorer"), recording_panel("runner"),
    })
    shell:_on_render_window()
    T.assert_equal(shell:tab_layout()[1].id, "runner",
        "the run must be the first thing the operator can reach")
end

function M.test_every_switcher_tab_reports_hover()
    -- ADR 09b §5.4. A tab that does not light up under the pointer reads as a label, and the user
    -- never discovers the switcher is a switcher.
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    shell:_on_render_window()

    local graph_tab = tab_bounds(shell, "graph")
    T.assert_not_nil(graph_tab, "the graph tab must have bounds")

    fake:reset()
    fake:hover(graph_tab)
    shell:_on_render_window()

    local hovered = false
    for _, call in ipairs(fake:hover_tests()) do
        local mn, mx = call.args[1], call.args[2]
        if mn.x <= graph_tab.x + 1 and mx.x >= graph_tab.x + graph_tab.w - 1 then hovered = true end
    end
    T.assert_true(hovered, "the tab under the pointer must have been hover-tested")
end

function M.test_clicking_a_tab_activates_its_panel()
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    shell:_on_render_window()
    T.assert_equal(shell:active_id(), "runner", "the runner leads")

    fake:click(tab_bounds(shell, "graph"))
    shell:_on_render_window()
    T.assert_equal(shell:active_id(), "graph", "clicking the tab must switch panels")
end

function M.test_the_active_tab_is_marked_in_the_accent()
    -- Hover alone cannot say which panel you are on, because the pointer is somewhere else the
    -- moment you start reading the body.
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    shell:_on_render_window()

    local found = false
    for _, call in ipairs(fake.calls) do
        if call.name == "render_rect_filled" then
            local color = call.args[3]
            if color and color.r == Theme.rgba.accent[1] and color.g == Theme.rgba.accent[2] then
                found = true
            end
        end
    end
    T.assert_true(found, "the active tab must carry an accent marker")
end

--- Drive the shell to the frame on which the marker is travelling: one frame to place it, a click
--- to move the active tab, one frame for the switch to land, then the frame under test.
local function frame_with_a_moving_marker(shell, fake)
    shell:_on_render_window()
    fake:click(tab_bounds(shell, "graph"))
    shell:_on_render_window()
    fake:clear_click()
    fake:reset()
    shell:_on_render_window()
end

function M.test_the_travelling_marker_animates_through_the_documented_signature()
    -- The bug: `animate_widget` was handed the string "sentinel_ide_tab_marker" and two bare
    -- coordinates. Sylvannas takes an integer id and two vec2, so the injector threw
    -- `bad argument #1 to 'animate_widget' (number expected, got string)` on every frame the marker
    -- moved -- inside the render callback, BEFORE the body drew. The frame aborted between the tab
    -- strip and the panel, which is why the operator saw chrome over a stale body.
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    frame_with_a_moving_marker(shell, fake)

    local anim = fake:calls_of("animate_widget")[1]
    T.assert_not_nil(anim, "a tab switch must animate the marker; ADR 09b §5.7, motion to explain")
    T.assert_equal(type(anim.args[1]), "number", "the animation id must be a number")
    T.assert_equal(anim.args[1], math.floor(anim.args[1]), "and an integer, per api/ui-custom.md")
    T.assert_equal(type(anim.args[2].x), "number", "the start position is a vec2")
    T.assert_equal(type(anim.args[3].x), "number", "and so is the end position")
end

function M.test_the_marker_animation_id_is_the_same_integer_on_every_frame()
    -- Sylvannas carries an animation's progress under its id. An id allocated per frame would hand
    -- the SDK a brand-new animation each time, so the marker would restart at `from` forever and
    -- never arrive at the tab the operator clicked.
    local shell, fake = open_shell({ recording_panel("runner"), recording_panel("graph") })
    frame_with_a_moving_marker(shell, fake)
    local first = fake:calls_of("animate_widget")[1].args[1]

    for _ = 1, 5 do
        fake:reset()
        -- Re-arm the transition: a stationary marker legitimately stops animating.
        shell:activate("runner"); shell:_on_render_window()
        fake:reset()
        shell:activate("graph"); shell:_on_render_window()
        local call = fake:calls_of("animate_widget")[1]
        T.assert_not_nil(call, "the marker must still be animating")
        T.assert_equal(call.args[1], first, "the animation id must be stable across frames")
    end
end

function M.test_a_frame_that_animates_the_marker_still_draws_the_body()
    -- The symptom the crash produced. The whole shell render is pcall-wrapped by `main.lua`, so a
    -- throw in the tab strip silently skipped `_draw_body` and left the previous frame's content
    -- on screen -- which reads as a layout bug rather than an exception.
    local runner, graph = recording_panel("runner"), recording_panel("graph")
    local shell, fake = open_shell({ runner, graph })
    frame_with_a_moving_marker(shell, fake)

    T.assert_true(#fake:calls_of("animate_widget") > 0, "the frame under test is an animating one")
    T.assert_true(fake:drew_text("body:graph"), "and the body must still have been painted")
end

-- ---------------------------------------------------------------------------
-- Bodies
-- ---------------------------------------------------------------------------

function M.test_exactly_one_panel_body_is_rendered_per_frame()
    -- ADR 09b §2.4 and the frame budget behind it: a panel nobody is looking at must cost
    -- nothing. Rendering all five would multiply the per-frame work by the number of units built.
    local runner, graph = recording_panel("runner"), recording_panel("graph")
    local shell = open_shell({ runner, graph })
    shell:_on_render_window()

    T.assert_equal(runner.renders, 1, "the active panel draws exactly once")
    T.assert_equal(graph.renders, 0, "an inactive panel must never be asked to draw")
end

function M.test_switching_panels_hands_the_pane_over_and_never_draws_two_bodies()
    -- A click is read after the frame's view is taken, so the switch lands on the NEXT frame (see
    -- the note in `_on_render_window`). What must hold on every frame either side of it is that
    -- exactly one body drew.
    local runner, graph = recording_panel("runner"), recording_panel("graph")
    local shell, fake = open_shell({ runner, graph })

    local frames = 0
    local function frame()
        local before = runner.renders + graph.renders
        shell:_on_render_window()
        frames = frames + 1
        T.assert_equal(runner.renders + graph.renders, before + 1,
            "exactly one panel body may draw per frame")
    end

    frame()
    fake:click(tab_bounds(shell, "graph"))
    frame()
    fake:clear_click()

    local runner_at_switch = runner.renders
    for _ = 1, 3 do frame() end

    T.assert_equal(runner.renders, runner_at_switch,
        "the old body stops drawing once the switch has settled")
    T.assert_equal(graph.renders, 3, "and the new body draws every frame after it")
end

function M.test_the_body_is_given_the_content_rect_below_the_switcher()
    local runner = recording_panel("runner")
    local shell, fake = open_shell({ runner })
    shell:_on_render_window()

    T.assert_not_nil(runner.bounds, "the panel must be told where it may draw")
    T.assert_true(runner.bounds.y >= Theme.metrics.toolbar_height,
        "the body must start below the switcher, not under it")
    T.assert_true(runner.bounds.w > 0 and runner.bounds.h > 0,
        "and it must be a rect a panel can actually use")
    T.assert_true(runner.bounds.x + runner.bounds.w <= fake:get_size().x,
        "and it must not extend past the window")
end

function M.test_the_body_receives_the_shell_so_it_can_reach_shared_state()
    local runner = recording_panel("runner")
    local shell = open_shell({ runner })
    shell:_on_render_window()
    T.assert_equal(runner.ctx.shell, shell, "the panel is handed the shell it belongs to")
    T.assert_not_nil(runner.ctx.state, "and the view-model it renders from")
end

function M.test_a_panel_that_declares_a_split_is_handed_both_panes()
    local explorer = recording_panel("explorer", { split = "primary" })
    local shell = open_shell({ explorer })
    shell:_on_render_window()

    T.assert_not_nil(explorer.ctx.split, "a panel that asked for a divider must be given one")
    T.assert_true(explorer.ctx.split.first.w > 0, "with a usable first pane")
    T.assert_true(explorer.ctx.split.second.w > 0, "and a usable second pane")
    T.assert_true(explorer.ctx.split.second.x > explorer.ctx.split.first.x,
        "laid out in reading order")
end

function M.test_a_panel_without_a_split_is_handed_the_whole_rect()
    local runner = recording_panel("runner")
    local shell = open_shell({ runner })
    shell:_on_render_window()
    T.assert_nil(runner.ctx.split, "a panel that asked for no divider must not be given one")
end

-- ---------------------------------------------------------------------------
-- Empty state (ADR 09b §5.5)
-- ---------------------------------------------------------------------------

function M.test_the_shell_renders_its_empty_state_when_no_campaign_is_open()
    local explorer = recording_panel("explorer", { requires_campaign = true })
    local shell, fake = open_shell({ explorer })
    shell:_on_render_window()

    T.assert_equal(explorer.renders, 0, "the body must not draw over a missing campaign")
    T.assert_true(fake:drew_text("campaign"),
        "the empty pane must say what is missing, not be blank")

    shell:set_campaign("Northshire")
    fake:reset()
    shell:_on_render_window()
    T.assert_equal(explorer.renders, 1, "and hand the pane back the moment a campaign exists")
end

function M.test_the_empty_state_action_reaches_the_host()
    -- ADR 09b §5.5: an empty state that instructs and then cannot be acted on is still a dead end.
    local fired = nil
    local fake = FakeWindow.new()
    local shell = Shell.new({
        window = fake, elements = fake_elements(),
        on_action = function(action_id) fired = action_id end,
    })
    shell:register_panel(recording_panel("explorer", { requires_campaign = true }))
    shell:show()
    shell:_on_render_window()

    local action = shell:empty_action_bounds()
    T.assert_not_nil(action, "the empty state must offer an action")
    fake:click(action)
    shell:_on_render_window()
    T.assert_true(type(fired) == "string" and fired ~= "",
        "pressing it must reach the host verb, not stop inside the shell")
end

function M.test_a_shell_with_no_panels_still_explains_itself()
    -- Today's actual first-run state: U3-U7 have not shipped.
    local shell, fake = open_shell({})
    shell:_on_render_window()
    T.assert_true(#fake:text_calls() > 0, "an empty shell must not be a blank rectangle")
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

function M.test_a_hidden_shell_draws_nothing()
    local runner = recording_panel("runner")
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = fake_elements() })
    shell:register_panel(runner)

    shell:_on_render_window()
    T.assert_equal(#fake.calls, 0, "a closed IDE must cost nothing per frame")
    T.assert_equal(runner.renders, 0, "and must not run its panels")
end

function M.test_closing_the_window_with_its_cross_closes_the_shell()
    -- Sylvannas draws the close cross itself; the only signal is `is_being_shown` going false.
    -- Without this the state and the window disagree and the toggle appears to do nothing.
    local shell, fake = open_shell({ recording_panel("runner") })
    shell:_on_render_window()
    T.assert_true(shell:is_visible(), "open to begin with")

    fake.visible = false
    shell:_on_render_window()
    T.assert_false(shell:is_visible(), "the cross must close the shell, not just the window")
end

-- ---------------------------------------------------------------------------
-- Persistence (ADR 09b §2.3)
-- ---------------------------------------------------------------------------

function M.test_layout_values_round_trip_through_the_ghost_sliders()
    local elements = fake_elements()
    local snapshot = {
        position = { x = 415, y = 260 }, size = { x = 1100, y = 720 },
        active_slot = 3, splits = { primary = 0.44, secondary = 0.61 },
    }
    Shell.save_layout(elements, snapshot)
    local restored = Shell.load_layout(elements)

    T.assert_equal(restored.position.x, 415, "position x survives")
    T.assert_equal(restored.position.y, 260, "position y survives")
    T.assert_equal(restored.size.x, 1100, "size x survives")
    T.assert_equal(restored.size.y, 720, "size y survives")
    T.assert_equal(restored.active_slot, 3, "the active panel survives")
    -- Sliders carry integers, so ratios are persisted as whole percent. Anything finer is lost,
    -- which is why the tolerance here is one percent rather than an epsilon.
    T.assert_near(restored.splits.primary, 0.44, 0.005, "the primary divider survives")
    T.assert_near(restored.splits.secondary, 0.61, 0.005, "the secondary divider survives")
end

function M.test_the_active_panel_survives_a_simulated_reinjection()
    -- Menu elements are the only thing that outlives an injection, so the elements table is the
    -- only thing carried from the first shell to the second. Everything else is built fresh, the
    -- way it is on a reload.
    local elements = fake_elements()

    local first, first_window = open_shell({
        recording_panel("runner"), recording_panel("graph"),
    }, elements)
    first:_on_render_window()                      -- the frame that lays the switcher out
    first_window:click(tab_bounds(first, "graph"))
    first:_on_render_window()
    T.assert_equal(first:active_id(), "graph", "the operator switched to the graph")
    first:on_tick()

    local second = open_shell({ recording_panel("runner"), recording_panel("graph") }, elements)
    T.assert_equal(second:active_id(), "graph",
        "the shell must reopen on the panel the operator left it on")
end

function M.test_a_moved_divider_survives_a_simulated_reinjection()
    local elements = fake_elements()
    local first = open_shell({ recording_panel("explorer", { split = "primary" }) }, elements)
    first:set_split_ratio("primary", 0.66)
    first:on_tick()

    local second = open_shell({ recording_panel("explorer", { split = "primary" }) }, elements)
    T.assert_near(second:split_ratio("primary"), 0.66, 0.005,
        "a divider the operator moved must not snap back on reload")
end

function M.test_persistence_is_not_written_on_an_unchanged_tick()
    -- Writing every tick is harmless but hides a real bug: if nothing ever compares, nothing ever
    -- notices that the geometry it is writing is stale.
    local elements = fake_elements()
    local writes = 0
    for _, slider in pairs(elements) do
        local inner = slider.set
        slider.set = function(self, value) writes = writes + 1; inner(self, value) end
    end

    local shell = open_shell({ recording_panel("runner") }, elements)
    shell:on_tick()
    local after_first = writes
    shell:on_tick()
    shell:on_tick()
    T.assert_equal(writes, after_first, "an unchanged layout must not be rewritten")
end

function M.test_a_shell_with_no_ghost_sliders_still_works()
    -- `core.menu` does not exist offline, and a panel author running the suite must not have to
    -- care. Persistence degrades; nothing else may.
    local shell, fake = open_shell({ recording_panel("runner") }, nil)
    shell:_on_render_window()
    shell:on_tick()
    T.assert_true(fake:drew_text("Runner"), "the shell renders with no persistence available")
end

-- ---------------------------------------------------------------------------
-- Panel commands and panel tick time (ADR 09b §2.1, §2.2, §2.4)
-- ---------------------------------------------------------------------------
-- A panel answers a frame with a COMMAND rather than performing the effect, because a side effect
-- inside `register_on_render_window_callback` is a side effect no test can reach and one Sylvannas
-- re-enters at arbitrary times. The shell is what carries that command out of the render callback,
-- and it does so without knowing what any command means: the panel supplies its own dispatcher.
--
-- Before this existed both halves were individually green and the product was broken -- the panel
-- returned commands and the shell discarded the return value, so every control on it was inert.

--- A panel that answers each frame with `spec.next_command`, and records what it is later handed
--- back on the tick. `dispatched` is the observable that distinguishes "the command was carried
--- out of the render callback" from "the command was acted on inside it".
local function commanding_panel(id, opts)
    opts = opts or {}
    local spec = recording_panel(id)
    spec.next_command = opts.command
    spec.dispatched = {}
    spec.ticks = 0
    spec.dispatch_result = opts.dispatch_result

    local draw = spec.render
    spec.render = function(window, bounds, ctx)
        draw(window, bounds, ctx)
        return spec.next_command
    end
    if opts.no_dispatcher ~= true then
        spec.dispatch = function(command, ctx)
            spec.dispatched[#spec.dispatched + 1] = { command = command, ctx = ctx }
            if opts.dispatch_throws then error("dispatcher exploded", 0) end
            if spec.dispatch_result ~= nil then return spec.dispatch_result, opts.dispatch_reason end
            return true
        end
    end
    spec.on_tick = function(ctx)
        spec.ticks = spec.ticks + 1
        spec.tick_ctx = ctx
    end
    return spec
end

function M.test_a_command_a_panel_returns_is_not_dispatched_inside_the_render_callback()
    local runner = commanding_panel("runner", { command = { kind = "stop" } })
    local shell = open_shell({ runner })

    shell:_on_render_window()
    T.assert_equal(#runner.dispatched, 0,
        "a side effect inside a render callback is one no test can reach and one Sylvannas "
        .. "re-enters at arbitrary times")
    T.assert_equal(#shell:pending_commands(), 1, "it must be queued instead")

    shell:on_tick()
    T.assert_equal(#runner.dispatched, 1, "and dispatched in tick context")
    T.assert_equal(runner.dispatched[1].command.kind, "stop", "with the command the panel returned")
    T.assert_equal(#shell:pending_commands(), 0, "the queue drains")
end

function M.test_a_dispatched_command_is_given_the_same_context_shape_the_body_gets()
    local runner = commanding_panel("runner", { command = { kind = "pause" } })
    local shell = open_shell({ runner })
    shell:_on_render_window()
    shell:on_tick()

    local ctx = runner.dispatched[1].ctx
    T.assert_equal(ctx.shell, shell, "a dispatcher is handed the shell it belongs to")
    T.assert_not_nil(ctx.state, "and the view-model")
    T.assert_nil(ctx.split, "but no split geometry -- panes only exist while a frame is being drawn")
end

function M.test_a_panel_that_returns_no_command_queues_nothing()
    local runner = commanding_panel("runner", { command = nil })
    local shell = open_shell({ runner })
    for _ = 1, 5 do shell:_on_render_window() end
    T.assert_equal(#shell:pending_commands(), 0, "a quiet frame must cost nothing on the tick")
end

function M.test_a_command_from_a_panel_with_no_dispatcher_is_refused_not_swallowed()
    -- The failure this whole unit exists to answer: a control that looks live, is pressed, and
    -- does nothing at all. A shell that dropped the command silently would recreate it exactly.
    local runner = commanding_panel("runner", { command = { kind = "start" }, no_dispatcher = true })
    local shell = open_shell({ runner })
    shell:_on_render_window()
    shell:on_tick()

    local last = shell:last_dispatch()
    T.assert_not_nil(last, "the attempt must be recorded")
    T.assert_false(last.ok, "a command nobody consumes is a failure, not a no-op")
    T.assert_true(type(last.reason) == "string" and last.reason ~= "",
        "and it must name why, or nobody can tell an inert control from a quiet one")
end

function M.test_a_dispatcher_that_refuses_reports_its_reason()
    local runner = commanding_panel("runner", {
        command = { kind = "wat" }, dispatch_result = false, dispatch_reason = "unknown command",
    })
    local shell = open_shell({ runner })
    shell:_on_render_window()
    shell:on_tick()

    local last = shell:last_dispatch()
    T.assert_false(last.ok, "the dispatcher's refusal must survive the trip back")
    T.assert_equal(last.reason, "unknown command", "with the reason it gave")
end

function M.test_a_dispatcher_that_throws_does_not_take_the_shell_tick_down()
    -- `main.lua` pcalls `on_tick` as a whole, so an uncaught throw here would silently skip the
    -- Escape edge, the combat read and the ghost-slider write for that tick.
    local elements = fake_elements()
    local runner = commanding_panel("runner", {
        command = { kind = "stop" }, dispatch_throws = true,
    })
    local shell = open_shell({ runner }, elements)
    shell:_on_render_window()

    local ok = pcall(function() shell:on_tick() end)
    T.assert_true(ok, "a panel's dispatcher must not be able to break the shell's tick")
    T.assert_false(shell:last_dispatch().ok, "and the throw is reported as a failed dispatch")
end

function M.test_only_the_active_panel_is_given_tick_time()
    -- Same reason exactly one body draws: a panel nobody is looking at must cost nothing, and a
    -- model refresh is the most expensive thing a panel does off the render path.
    local runner, graph = commanding_panel("runner"), commanding_panel("graph")
    local shell = open_shell({ runner, graph })
    shell:on_tick()

    T.assert_equal(runner.ticks, 1, "the active panel gets the tick")
    T.assert_equal(graph.ticks, 0, "an inactive panel must never be refreshed")
end

function M.test_a_closed_shell_gives_no_panel_tick_time()
    local runner = commanding_panel("runner")
    local shell = Shell.new({ window = FakeWindow.new(), elements = fake_elements() })
    shell:register_panel(runner)

    for _ = 1, 10 do shell:on_tick() end
    T.assert_equal(runner.ticks, 0, "a closed IDE must not refresh a model nobody can see")
end

function M.test_a_queued_command_survives_the_shell_being_closed()
    -- Stop, then Escape. The stop must still land, or the one control an operator reaches for in a
    -- hurry is the one that loses the race with the window closing.
    local runner = commanding_panel("runner", { command = { kind = "stop" } })
    local shell = open_shell({ runner })
    shell:_on_render_window()
    shell:hide()
    shell:on_tick()
    T.assert_equal(#runner.dispatched, 1, "a command already issued must not be lost on close")
end

function M.test_the_command_queue_cannot_grow_without_bound()
    -- The tick is what drains this, so a render callback that appended with no ceiling would leak
    -- for exactly as long as the tick is starved -- the one situation in which it matters.
    local runner = commanding_panel("runner", { command = { kind = "stop" } })
    local shell = open_shell({ runner })
    for _ = 1, 200 do shell:_on_render_window() end
    T.assert_true(#shell:pending_commands() <= 32,
        "the pending queue must be bounded, not one entry per unserviced frame")
end

function M.test_a_panel_may_declare_no_dispatcher_or_tick_hook_at_all()
    -- Both are optional: U3-U7 include panels that only paint.
    local runner = recording_panel("runner")
    local shell = open_shell({ runner })
    shell:_on_render_window()
    shell:on_tick()
    T.assert_equal(runner.renders, 1, "a plain panel still draws")
end

function M.test_a_non_function_dispatcher_is_refused_at_registration()
    -- Refused now rather than at the first command, for the same reason a missing render function
    -- is: inside a render callback the only symptom is a control that does nothing.
    local shell = open_shell({})
    local ok, reason = shell:register_panel({
        id = "runner", render = function() end, dispatch = "nope",
    })
    T.assert_false(ok, "a dispatcher that is not callable must be rejected")
    T.assert_true(type(reason) == "string" and reason ~= "", "with a reason")
end

-- ---------------------------------------------------------------------------
-- Keyboard events: collected once per tick, consumed by exactly one frame
-- ---------------------------------------------------------------------------
-- `_poll_input` collects the tick's rising-edge key events into `_input_events`, and the next
-- frame hands them to the active panel as `ctx.input_events`. The render rate can outrun the
-- tick, so the frame must CONSUME them: a second frame painted before the next tick has to see
-- an empty list, or one keypress types twice — the "type t, get tt" bug at the shell layer.

function M.test_keyboard_events_reach_the_frame_after_the_tick_that_collected_them()
    local TextInputState = require("ui/text_input_state")
    TextInputState.reset_collect_state()
    local runner = recording_panel("runner")
    local shell = open_shell({ runner })

    local saved = _G.core
    local t_down = true
    _G.core = { input = {
        is_key_pressed = function(vk) return t_down and vk == string.byte("T") end,
        is_key_down = function() return false end,
    } }
    local ok, err = pcall(function()
        shell:on_tick()
        T.assert_equal(#shell._input_events, 1, "the tick collects the keypress once")

        shell:_on_render_window()
        T.assert_not_nil(runner.ctx.input_events, "the frame is handed the tick's events")
        T.assert_equal(#runner.ctx.input_events, 1)
        T.assert_equal(runner.ctx.input_events[1].vk, string.byte("T"))

        shell:_on_render_window()
        T.assert_equal(#runner.ctx.input_events, 0,
            "a second frame before the next tick must not apply one keypress twice")
    end)
    _G.core = saved
    TextInputState.reset_collect_state()
    if not ok then error(err, 0) end
end

function M.test_keyboard_events_are_refreshed_by_the_next_tick_not_accumulated()
    local TextInputState = require("ui/text_input_state")
    TextInputState.reset_collect_state()
    local shell = open_shell({ recording_panel("runner") })

    local saved = _G.core
    _G.core = { input = {
        is_key_pressed = function() return false end,
        is_key_down = function() return false end,
    } }
    local ok, err = pcall(function()
        shell._input_events = { { vk = 84, shift = false } }  -- stale, never rendered
        shell:on_tick()
        T.assert_equal(#shell._input_events, 0,
            "the tick OVERWRITES the buffer; an unrendered keypress must not linger")
    end)
    _G.core = saved
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The Sylvannas construction rule (ADR 09b §2.2)
-- ---------------------------------------------------------------------------

--- Re-require `ui/shell` against an instrumented `core.menu` that records the PHASE of every
--- construction. This is the only way the rule is observable: nothing about a `core.menu.window`
--- built in a render callback looks wrong offline.
local function with_instrumented_menu(fn)
    local saved_menu = _G.core and _G.core.menu or nil
    local saved_core = _G.core
    local saved_shell = package.loaded["ui/shell"]

    local env = { created = {}, phase = "load" }
    _G.core = _G.core or {}
    _G.core.menu = {
        slider_int = function(_min, _max, default, id)
            env.created[#env.created + 1] = { kind = "slider_int", id = id, phase = env.phase }
            return fake_slider(default)
        end,
        keybind = function(_default, _toggle, id)
            env.created[#env.created + 1] = { kind = "keybind", id = id, phase = env.phase }
            return { render = function() end, get_state = function() return false end }
        end,
        window = function(id)
            env.created[#env.created + 1] = { kind = "window", id = id, phase = env.phase }
            return FakeWindow.new()
        end,
    }

    package.loaded["ui/shell"] = nil
    local ok, err = pcall(function()
        local FreshShell = require("ui/shell")
        fn(FreshShell, env)
    end)

    package.loaded["ui/shell"] = saved_shell
    _G.core = saved_core
    if saved_core then _G.core.menu = saved_menu end
    if not ok then error(err, 0) end
end

function M.test_the_ghost_sliders_are_constructed_at_module_scope()
    with_instrumented_menu(function(_FreshShell, env)
        local at_load = 0
        for _, entry in ipairs(env.created) do
            if entry.phase == "load" and entry.kind == "slider_int" then at_load = at_load + 1 end
        end
        T.assert_true(at_load > 0,
            "ghost sliders must exist before anything can read a saved layout from them")
    end)
end

function M.test_no_menu_element_is_constructed_during_the_render_callback()
    with_instrumented_menu(function(FreshShell, env)
        local shell = FreshShell.new()
        shell:register_panel(recording_panel("runner"))
        shell:show()

        env.phase = "tick"
        shell:ensure_frames_created()
        shell:on_tick()

        env.phase = "render"
        for _ = 1, 5 do shell:_on_render_window() end

        local during_render = {}
        for _, entry in ipairs(env.created) do
            if entry.phase == "render" then during_render[#during_render + 1] = entry.kind end
        end
        T.assert_equal(#during_render, 0,
            "Sylvannas forbids creating windows or menu elements inside a render callback; "
            .. table.concat(during_render, ", ") .. " were created there")
    end)
end

function M.test_no_window_is_created_until_the_shell_is_opened()
    -- `main.lua` ticks this shell from load. A user who only wants the bot running must not pay
    -- for an authoring window they never opened.
    with_instrumented_menu(function(FreshShell, env)
        local shell = FreshShell.new()
        env.phase = "tick"
        for _ = 1, 10 do shell:on_tick() end

        for _, entry in ipairs(env.created) do
            T.assert_true(entry.kind ~= "window", "a closed shell must not construct a window")
        end

        shell:show()
        shell:on_tick()
        local windows = 0
        for _, entry in ipairs(env.created) do
            if entry.kind == "window" then windows = windows + 1 end
        end
        T.assert_equal(windows, 1, "opening it builds exactly one")
    end)
end

function M.test_the_window_is_constructed_in_the_tick_callback()
    with_instrumented_menu(function(FreshShell, env)
        local shell = FreshShell.new()
        shell:show()

        env.phase = "tick"
        shell:ensure_frames_created()
        shell:ensure_frames_created()

        local windows = 0
        for _, entry in ipairs(env.created) do
            if entry.kind == "window" then
                windows = windows + 1
                T.assert_equal(entry.phase, "tick", "the window is a tick-context construction")
            end
        end
        T.assert_equal(windows, 1, "and it is built once, not once per tick")
    end)
end

-- ---------------------------------------------------------------------------
-- Frame budget and design system (ADR 09b §2.4, §3)
-- ---------------------------------------------------------------------------

local function shell_source()
    local handle = io.open("sentinel/ui/shell.lua", "r")
    T.assert_not_nil(handle, "shell.lua must be readable from the repo root")
    local source = handle:read("*a")
    handle:close()
    return source
end

function M.test_the_shell_performs_no_io_or_network_work()
    local source = shell_source()
    for _, forbidden in ipairs({ "http_get", "http_post", "read_data_file", "write_data_file" }) do
        T.assert_nil(source:find(forbidden, 1, true),
            "shell.lua reaches for " .. forbidden .. "; this runs every frame")
    end
end

function M.test_the_shell_hardcodes_no_colour_or_spacing()
    -- ADR 09b §3: five panels built by five hands only look like one product if the vocabulary is
    -- the theme's. The shell is the frame around all of them, so it goes first.
    local source = shell_source()
    T.assert_nil(source:find("[Cc]olor%.new%s*%("), "shell.lua constructs a raw colour")
    T.assert_nil(source:find("[Cc]olor%.white%s*%("), "shell.lua uses an SDK preset colour")
end

function M.test_the_shell_does_not_name_a_single_panel_implementation()
    -- The registration contract, enforced. A `require("ui/panels/...")` here would put every
    -- later unit back in this file.
    local source = shell_source()
    T.assert_nil(source:find("ui/panels"), "shell.lua must not require a panel implementation")
end

return M
