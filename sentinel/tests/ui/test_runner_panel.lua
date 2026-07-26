-- tests/ui/test_runner_panel.lua
-- The Runner panel's contract (ADR 09b §2.1, §5, §6 U5).
--
-- The panel is the surface an operator opens when something is wrong, so the cases below are
-- weighted towards the wrong cases: a blocked run has to shout, an ETA nobody can compute has to
-- say so instead of reading as "zero seconds left", and a control that cannot act has to stay put
-- and refuse rather than disappear from under the pointer.
--
-- Everything visual is driven through the fake window, because a render callback cannot be entered
-- outside the injector. Everything structural is asserted against `runner_panel_state.build`,
-- which is where every branch in this panel lives — `runner.lua` may not contain one.

local RunnerState = require("modules/questing/runner_state")
local Runner = require("ui/panels/runner")
local PanelState = require("ui/panels/runner_panel_state")
local Theme = require("ui/theme")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local BOUNDS = { x = 0, y = 0, w = 640, h = 540 }
local NOW = 10000

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

---An executor-shaped table — the same duck type `runner_state.lua` reads.
local function executor(opts)
    opts = opts or {}
    local operations = {}
    for i = 1, (opts.total or 10) do
        operations[i] = { actions = { { type = "Travel", payload = { destination = "Goldshire" } } } }
    end
    if opts.gate_condition then
        operations[opts.step or 3].actions[1] =
            { type = "Condition", payload = { condition = opts.gate_condition } }
    end
    return {
        _profile = { operations = operations },
        _state = opts.state or "running",
        _current_operation_idx = opts.step or 3,
        _current_action_idx = 1,
        _current_action_retries = 0,
        _consecutive_failures = opts.failures or 0,
        _ghost_start_time = opts.ghost_start,
        _wait_action_key = opts.wait_key,
        _wait_started_at = opts.wait_started_at,
        _execution_log = opts.log or {},
    }
end

---A cockpit snapshot. `started_at` defaults to a run old enough for the ETA maths to have samples.
local function view(opts)
    opts = opts or {}
    local build = {
        executor = opts.executor,
        now = NOW,
        started_at = opts.started_at or (NOW - 600),
        last_progress_at = opts.last_progress_at,
        deaths = opts.deaths,
        guardrails = opts.guardrails,
        tracked_quests = opts.tracked_quests,
        quest_log = opts.quest_log,
        nav_error = opts.nav_error,
        status_message = opts.status_message,
        module_faults = opts.module_faults,
        maintenance = opts.maintenance,
    }
    return RunnerState.build(build)
end

local function model(opts)
    opts = opts or {}
    local m = Runner.new_model()
    m.view = opts.view or view({ executor = executor() })
    m.profiles = opts.profiles or { "elwynn_1_12" }
    m.selected_profile = opts.selected_profile
    if opts.selected_profile == nil then m.selected_profile = m.profiles[1] end
    m.paused = opts.paused or false
    m.event_filter = opts.event_filter or m.event_filter
    m.show_details = opts.show_details or false
    return m
end

local function render(m)
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local command, plan = Runner.render(fake, BOUNDS, m)
    return fake, plan, command
end

local function control_named(plan, id)
    for _, control in ipairs(plan.controls) do
        if control.id == id then return control end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- 1. Is it stuck, and why — the panel's reason for existing
-- ---------------------------------------------------------------------------

function M.test_a_blocked_runner_renders_its_reason_prominently()
    local m = model({ view = view({
        executor = executor({ state = "failed", failures = 3 }),
        status_message = "vendor not found",
    }) })
    local fake, plan = render(m)

    T.assert_true(#plan.alerts >= 1, "a failed run must raise an alert")
    local reason = fake:find_text("profile failed after 3 consecutive failures")
    T.assert_not_nil(reason, "the view-model's human reason must be drawn verbatim")
    -- Prominence is carried by TYPE SIZE, not only by colour: the reason is the one string on the
    -- panel drawn above body size, so it still leads the page in greyscale.
    T.assert_equal(reason.font_id, Theme.font.heading,
        "the blocked reason must be set larger than body copy")
    -- ...and by a surface nothing else on the panel has. A row of equal-weight stats is exactly
    -- what this case exists to prevent.
    local alert = plan.alerts[1]
    T.assert_not_nil(fake:filled_rect_at(alert.bounds),
        "the alert must sit on its own filled surface")
end

function M.test_a_healthy_runner_renders_no_alert_treatment()
    local fake, plan = render(model())
    T.assert_equal(#plan.alerts, 0, "a healthy run must raise no alert")
    T.assert_false(fake:drew_text("BLOCKED"), "a healthy run must not draw the blocked banner")
    T.assert_false(fake:drew_text("profile failed"), "a healthy run must not draw a failure reason")
end

function M.test_a_gate_wait_names_the_condition_it_is_waiting_on()
    local m = model({ view = view({
        executor = executor({
            wait_key = "op3", wait_started_at = NOW - 40,
            gate_condition = { type = "QuestCompleted", payload = 1234 },
        }),
    }) })
    local fake = render(m)
    T.assert_true(fake:drew_text("quest 1234 not complete"),
        "a gate wait must name the condition rather than saying 'waiting'")
end

function M.test_the_worst_alert_leads_when_several_fire_at_once()
    -- A nav failure (alarm) and a tripped guardrail (warn) at the same moment: the alarm must be
    -- the one at the top, or the operator reads the milder problem first.
    local m = model({ view = view({
        executor = executor(),
        nav_error = { command = "move_to", reason = "no path", at = NOW - 2 },
        deaths = 5,
        guardrails = { stop_after_deaths = 3 },
    }) })
    local _, plan = render(m)
    T.assert_true(#plan.alerts >= 2, "both problems must be surfaced")
    T.assert_equal(plan.alerts[1].severity, "alarm", "the alarm must lead")
end

-- ---------------------------------------------------------------------------
-- 2. Progress and ETA — honest unknowns
-- ---------------------------------------------------------------------------

function M.test_an_uncomputable_eta_renders_as_unknown_not_zero()
    -- A run one step in with no elapsed time has no rate to extrapolate from. Rendering that as
    -- "ETA 00:00" tells the operator it is about to finish.
    local m = model({ view = view({
        executor = executor({ step = 1 }),
        started_at = NOW,
    }) })
    local fake, plan = render(m)

    T.assert_nil(plan.progress.eta_s, "the fixture must actually have no computable ETA")
    T.assert_true(fake:drew_text("ETA unknown"), "an unknown ETA must say so")
    T.assert_false(fake:drew_text("ETA 00:00"), "an unknown ETA must never render as zero")
end

function M.test_a_computable_eta_renders_as_a_duration()
    local m = model({ view = view({ executor = executor({ step = 3, total = 10 }) }) })
    local fake, plan = render(m)
    T.assert_not_nil(plan.progress.eta_s, "the fixture must have a computable ETA")
    T.assert_false(fake:drew_text("ETA unknown"), "a known ETA must not read as unknown")
    T.assert_true(fake:drew_text("ETA "), "the ETA must be drawn")
end

function M.test_the_progress_fill_never_leaves_its_track()
    local m = model({ view = view({ executor = executor({ step = 11, total = 10 }) }) })
    local _, plan = render(m)
    T.assert_true(plan.progress.fill_w <= plan.progress.track_w,
        "the progress fill must never overrun the track")
    T.assert_true(plan.progress.fill_w >= 0, "the progress fill must never be negative")
end

-- ---------------------------------------------------------------------------
-- 3. State is readable without colour
-- ---------------------------------------------------------------------------

local STATUS_FIXTURES = {
    { status = "IDLE",       executor = nil },
    { status = "RUNNING",    executor = { state = "running" } },
    { status = "NAVIGATING", executor = { state = "navigating" } },
    { status = "WAITING",    executor = { state = "running", wait_key = "k", wait_started_at = NOW - 10 } },
    { status = "STUCK",      executor = { state = "running", wait_key = "k", wait_started_at = NOW - 900 } },
    { status = "GHOST",      executor = { state = "ghost", ghost_start = NOW - 20 } },
    { status = "FAILED",     executor = { state = "failed", failures = 3 } },
    { status = "FINISHED",   executor = { state = "finished" } },
}

function M.test_every_run_state_carries_a_unique_non_colour_marker()
    -- Colour is never the only carrier: a state that reads as "the green one" is unusable to a
    -- colour-blind operator and illegible against a snowfield at noon.
    local seen_glyphs, seen_labels = {}, {}
    for _, fixture in ipairs(STATUS_FIXTURES) do
        local m = model({ view = view({
            executor = fixture.executor and executor(fixture.executor) or nil,
        }) })
        local fake, plan = render(m)

        T.assert_equal(plan.status.label, fixture.status,
            "the fixture must produce the status it claims")
        T.assert_true(plan.status.glyph ~= nil and plan.status.glyph ~= "",
            fixture.status .. " has no glyph")
        T.assert_nil(seen_glyphs[plan.status.glyph],
            "two run states share the glyph " .. tostring(plan.status.glyph))
        seen_glyphs[plan.status.glyph] = fixture.status
        T.assert_nil(seen_labels[plan.status.label], "two run states share a label")
        seen_labels[plan.status.label] = true

        T.assert_true(fake:drew_text(plan.status.glyph), fixture.status .. " never drew its glyph")
        T.assert_true(fake:drew_text(fixture.status), fixture.status .. " never drew its label")
    end
end

function M.test_two_run_states_never_differ_only_by_colour()
    -- The strongest form of the rule: strip every colour from the draw tape and the frames must
    -- still be distinguishable.
    local signatures = {}
    for _, fixture in ipairs(STATUS_FIXTURES) do
        local m = model({ view = view({
            executor = fixture.executor and executor(fixture.executor) or nil,
        }) })
        local fake = render(m)
        local parts = {}
        for _, entry in ipairs(fake:text_calls()) do
            parts[#parts + 1] = entry.text
        end
        local signature = table.concat(parts, "|")
        T.assert_nil(signatures[signature],
            fixture.status .. " is indistinguishable from " .. tostring(signatures[signature])
            .. " once colour is removed")
        signatures[signature] = fixture.status
    end
end

-- ---------------------------------------------------------------------------
-- 4. Quest-log desync — the "is it lying to me" signal
-- ---------------------------------------------------------------------------

function M.test_an_in_sync_quest_log_stays_calm()
    local m = model({ view = view({
        executor = executor(),
        tracked_quests = { 11, 22 },
        quest_log = { [11] = true, [22] = true },
    }) })
    local fake = render(m)
    T.assert_true(fake:drew_text("Quest log in sync"), "an in-sync log must still be confirmed")
    T.assert_false(fake:drew_text("MISMATCH"), "an in-sync log must not raise a mismatch")
end

function M.test_a_desynced_quest_log_names_the_missing_quests()
    local m = model({ view = view({
        executor = executor(),
        tracked_quests = { 11, 22, 33 },
        quest_log = { [11] = true },
    }) })
    local fake = render(m)
    T.assert_true(fake:drew_text("Quest log MISMATCH"), "a desync must be called out")
    T.assert_true(fake:drew_text("22"), "the missing quest ids must be named")
end

-- ---------------------------------------------------------------------------
-- 5. Recent events
-- ---------------------------------------------------------------------------

function M.test_events_render_newest_first()
    local m = model({ view = view({ executor = executor({ log = {
        { timestamp = 10, event = "action_success", msg = "oldest entry" },
        { timestamp = 20, event = "action_failed", msg = "newest entry" },
    } }) }) })
    local fake, plan = render(m)
    T.assert_true(plan.event_rows >= 2, "both events must have room")
    local newest = fake:find_text("newest entry")
    local oldest = fake:find_text("oldest entry")
    T.assert_not_nil(newest, "the newest event must be drawn")
    T.assert_not_nil(oldest, "the oldest event must be drawn")
    T.assert_true(newest.pos.y < oldest.pos.y, "the newest event must sit above the older one")
end

function M.test_an_empty_event_log_says_so()
    local fake = render(model())
    T.assert_true(fake:drew_text("No events yet"), "an empty timeline must say it is empty")
end

-- ---------------------------------------------------------------------------
-- 6. Controls
-- ---------------------------------------------------------------------------

function M.test_a_control_that_cannot_act_is_disabled_rather_than_absent()
    -- A pause button that vanishes while stopped makes the panel jump under the pointer.
    local idle = model({ view = view({}) })
    local running = model()

    local _, idle_plan = render(idle)
    local _, running_plan = render(running)

    for _, id in ipairs({ "start", "pause", "stop", "skip_step" }) do
        T.assert_not_nil(control_named(idle_plan, id), id .. " disappeared while idle")
        T.assert_not_nil(control_named(running_plan, id), id .. " disappeared while running")
    end
    T.assert_true(control_named(idle_plan, "stop").disabled, "stop cannot act with nothing loaded")
    T.assert_true(control_named(idle_plan, "skip_step").disabled, "skip cannot act with nothing loaded")
    T.assert_false(control_named(running_plan, "stop").disabled, "stop must act while running")
end

function M.test_a_disabled_control_never_reports_activation()
    local m = model({ view = view({}) })
    local _, plan = render(m)
    local stop = control_named(plan, "stop")

    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    fake:click(stop.bounds)
    local command = Runner.render(fake, BOUNDS, m)
    T.assert_nil(command, "clicking a disabled control must not issue a command")
end

function M.test_an_enabled_control_issues_its_command()
    local m = model()
    local _, plan = render(m)
    local pause = control_named(plan, "pause")

    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    fake:click(pause.bounds)
    local command = Runner.render(fake, BOUNDS, m)
    T.assert_not_nil(command, "clicking pause must issue a command")
    T.assert_equal(command.kind, "pause", "and it must be the pause command")
end

function M.test_a_paused_run_offers_resume_in_the_same_place()
    local running_plan = select(2, render(model()))
    local paused_plan = select(2, render(model({ paused = true })))
    local running_pause = control_named(running_plan, "pause")
    local paused_resume = control_named(paused_plan, "resume")

    T.assert_not_nil(paused_resume, "a paused run must offer resume")
    T.assert_equal(paused_resume.bounds.x, running_pause.bounds.x,
        "resume must occupy the same slot pause did, or the bar shifts under the pointer")
end

function M.test_every_control_reports_hover()
    -- Immediate-mode UIs feel dead without it (ADR 09b §5.4), disabled controls included.
    local _, plan = render(model())
    for _, control in ipairs(plan.controls) do
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        fake:hover(control.bounds)
        Runner.render(fake, BOUNDS, model())
        local hovered = false
        for _, call in ipairs(fake:hover_tests()) do
            local mn, mx = call.args[1], call.args[2]
            hovered = hovered or (mn.x <= control.bounds.x + 1
                and mx.x >= control.bounds.x + control.bounds.w - 1)
        end
        T.assert_true(hovered, control.id .. " never probed hover")
    end
end

function M.test_a_guardrail_chip_cycles_its_limit()
    local m = model({ view = view({ executor = executor(), guardrails = { stop_after_deaths = 3 } }) })
    local command = PanelState.reduce(m, "guard:deaths")
    T.assert_not_nil(command, "cycling a guardrail must issue a command")
    T.assert_equal(command.kind, "set_guardrails", "and it must be a guardrail command")
    T.assert_true(command.guardrails.stop_after_deaths ~= 3,
        "the limit must actually have moved")
end

function M.test_a_tripped_guardrail_is_surfaced()
    local m = model({ view = view({
        executor = executor(), deaths = 4, guardrails = { stop_after_deaths = 3 },
    }) })
    local fake = render(m)
    T.assert_true(fake:drew_text("death limit reached"), "a tripped guardrail must be named")
end

-- ---------------------------------------------------------------------------
-- 7. The empty state a new user meets first
-- ---------------------------------------------------------------------------

function M.test_the_empty_state_instructs_rather_than_showing_a_blank_pane()
    local m = model({ view = view({}), profiles = {}, selected_profile = false })
    local fake, plan = render(m)
    T.assert_true(plan.is_empty, "nothing loaded is the empty case")
    T.assert_true(fake:drew_text("No profile running"), "the empty state must name the situation")
    T.assert_true(fake:drew_text("Record a zone"), "the empty state must instruct")
end

function M.test_the_empty_state_offers_the_selected_profile()
    local m = model({ view = view({}), profiles = { "elwynn_1_12" } })
    local fake, plan = render(m)
    T.assert_true(plan.is_empty, "nothing loaded is still the empty case")
    T.assert_true(fake:drew_text("elwynn_1_12"), "the profile that would start must be named")
end

function M.test_the_empty_state_keeps_the_control_bar()
    local _, plan = render(model({ view = view({}), profiles = {} }))
    T.assert_true(#plan.controls > 0, "the control bar must not vanish with the body")
end

-- ---------------------------------------------------------------------------
-- 8. Structural guards — the failures that pass offline and break in the injector
-- ---------------------------------------------------------------------------

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

local RENDER_SOURCE = "sentinel/ui/panels/runner.lua"
local STATE_SOURCE = "sentinel/ui/panels/runner_panel_state.lua"

function M.test_the_source_audit_actually_reads_code()
    local source = source_of(RENDER_SOURCE)
    T.assert_true(source:find("function Runner.render", 1, true) ~= nil,
        "the stripped source must still contain the render function")
    T.assert_nil(source:find("ADR 09b", 1, true), "the stripped source must not contain prose")
end

function M.test_the_render_layer_contains_no_decision_logic()
    -- ADR 09b §2.1. A branch inside a render callback cannot be reached by any offline test, so
    -- the rule is enforced structurally rather than by review.
    local source = source_of(RENDER_SOURCE)
    T.assert_nil(source:find("%f[%w]if%f[%W]"), "runner.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]elseif%f[%W]"), "runner.lua branches; move it to the view-model")
    T.assert_nil(source:find("%f[%w]while%f[%W]"), "runner.lua loops on a condition")
end

function M.test_the_panel_never_constructs_a_menu_element()
    for _, path in ipairs({ RENDER_SOURCE, STATE_SOURCE }) do
        T.assert_nil(source_of(path):find("core%.menu%."),
            path .. " touches core.menu.*, which Sylvannas allows only in the tick callback")
    end
end

function M.test_no_menu_element_is_constructed_while_rendering()
    -- The structural scan above cannot see an indirect call. This one makes the whole SDK menu
    -- surface explode on contact for the duration of one frame.
    local saved = _G.core and _G.core.menu or nil
    if _G.core then
        _G.core.menu = setmetatable({}, {
            __index = function() error("core.menu was touched during render") end,
        })
    end
    local ok, err = pcall(render, model())
    if _G.core then _G.core.menu = saved end
    T.assert_true(ok, "the panel constructed a menu element during render: " .. tostring(err))
end

function M.test_the_panel_performs_no_io_on_the_render_path()
    -- `register_on_render_window_callback` runs every frame (ADR 09b §2.4).
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
        T.assert_nil(source:find("[Cc]olor%.white%s*%("), path .. " uses an SDK preset colour")
    end
end

function M.test_the_panel_loads_and_renders_with_no_sylvannas_api_present()
    -- `common/color` and `common/geometry/vector_2` only exist inside the injector. An unguarded
    -- require here makes every suite that touches the panel fail on load instead.
    local names = { "ui/panels/runner", "ui/panels/runner_panel_state", "ui/theme", "ui/widgets" }
    local saved_core, saved_loaded = _G.core, {}
    for _, name in ipairs(names) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end
    _G.core = nil
    local ok, panel = pcall(require, "ui/panels/runner")
    local rendered, err = true, nil
    if ok then
        local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
        rendered, err = pcall(panel.render, fake, BOUNDS, panel.new_model())
    end
    _G.core = saved_core
    for _, name in ipairs(names) do package.loaded[name] = saved_loaded[name] end

    T.assert_true(ok, "the panel failed to load with no SDK present: " .. tostring(panel))
    T.assert_true(rendered, "the panel failed to render with no SDK present: " .. tostring(err))
end

-- ---------------------------------------------------------------------------
-- 9. The view-model is pure and complete
-- ---------------------------------------------------------------------------

function M.test_the_plan_is_deterministic()
    -- Two builds of the same snapshot must agree, or the panel flickers between frames.
    local m = model()
    local a = PanelState.build(m, BOUNDS)
    local b = PanelState.build(m, BOUNDS)
    T.assert_equal(#a.items, #b.items, "the item count must be stable")
    T.assert_equal(a.status.line, b.status.line, "the status line must be stable")
end

function M.test_ui_only_actions_never_reach_the_module()
    local m = model()
    T.assert_nil(PanelState.reduce(m, "filter:error"), "a filter change is panel-local")
    T.assert_equal(m.event_filter, "error", "and it must have been applied to the model")
    T.assert_nil(PanelState.reduce(m, "details"), "a disclosure toggle is panel-local")
    T.assert_true(m.show_details, "and it must have been applied to the model")
end

function M.test_the_panel_survives_a_model_with_nothing_in_it()
    -- The shell hands this panel a model before anything is loaded. A nil view must not be the
    -- difference between a panel and a stack trace.
    local fake = FakeWindow.new({ size = { x = BOUNDS.w, y = BOUNDS.h } })
    local ok, err = pcall(Runner.render, fake, BOUNDS, Runner.new_model())
    T.assert_true(ok, "an empty model must still render: " .. tostring(err))
end

function M.test_the_panel_exposes_the_shape_the_shell_registers()
    T.assert_equal(Runner.id, "runner", "the shell keys panels by id")
    T.assert_equal(type(Runner.title), "string", "the tab needs a label")
    T.assert_equal(type(Runner.render), "function", "the shell calls render(window, bounds, model)")
    T.assert_equal(type(Runner.new_model), "function", "the shell needs the panel's initial state")
end

return M
