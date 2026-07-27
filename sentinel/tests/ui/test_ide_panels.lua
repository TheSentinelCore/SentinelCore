-- tests/ui/test_ide_panels.lua
-- ADR 09b U2b: the seam between the shell (U2) and the Runner panel (U5).
--
-- WHAT WAS BROKEN, AND WHY NEITHER UNIT'S SUITE SAW IT
-- ---------------------------------------------------
-- U2 and U5 were built concurrently and were each individually green. Nothing registered the
-- panel, the two render signatures did not match, and the shell discarded the command the panel
-- returned -- so every control on the Runner was inert while both suites passed. A defect that
-- lives strictly between two units is invisible to both units' tests; this file is the one that
-- can see it, and it drives the real shell, the real panel and the real command vocabulary end to
-- end rather than any of them in isolation.
--
-- The two rules that must survive the wiring are the ones that fail in the injector and nowhere
-- else: nothing is dispatched inside a render callback (ADR 09b §2.1), nothing is constructed
-- there (§2.2), and the per-frame path performs no directory read (§2.4).

local Shell = require("ui/shell")
local IdePanels = require("ui/ide_panels")
local RunnerPanelState = require("ui/panels/runner_panel_state")
local RunnerState = require("modules/questing/runner_state")
local FakeWindow = require("tests/harness/fake_window")
local T = require("tests/test_util")

local M = {}

local PROFILE_DIR = "sentinel/data/profiles/quests"

--- A stand-in for the inner `QuestingModule`, implementing exactly the verbs a Runner command maps
--- to and counting the two that are not free: `get_view` rebuilds the whole operator snapshot and
--- `list_profiles` reads a directory.
local function fake_questing(opts)
    opts = opts or {}
    local q = {
        calls = {},
        views = 0,
        scans = 0,
        started = nil,
        _paused = false,
        _profile_dir = PROFILE_DIR,
        profiles = opts.profiles or { "elwynn_1_12", "westfall_12_18" },
    }

    local function record(name, arg)
        q.calls[#q.calls + 1] = { name = name, arg = arg }
    end

    function q:get_view()
        self.views = self.views + 1
        return RunnerState.build({})
    end

    function q:is_paused() return self._paused end

    function q:list_profiles()
        self.scans = self.scans + 1
        return self.profiles
    end

    function q:start(path)
        record("start", path)
        self.started = path
        return opts.start_ok ~= false
    end

    function q:pause() record("pause"); self._paused = true end
    function q:resume() record("resume"); self._paused = false end
    function q:stop() record("stop") end

    function q:skip_current_step()
        record("skip_current_step")
        return opts.skip_ok ~= false
    end

    function q:set_guardrails(cfg) record("set_guardrails", cfg) end

    function q:start_recording(name)
        record("start_recording", name)
        if opts.record_ok == false then return { ok = false, reason = "already recording" } end
        return { ok = true, name = name or "auto" }
    end

    return q
end

local function called(questing, name)
    for _, entry in ipairs(questing.calls) do
        if entry.name == name then return entry end
    end
    return nil
end

--- A manually advanced clock. The refresh cadence is the whole point of the model-supply design,
--- and a test driven by a real clock could only assert it by sleeping.
local function fake_clock()
    local clock = { t = 1000.0 }
    function clock:now() return self.t end
    function clock:advance(seconds) self.t = self.t + seconds end
    return clock
end

--- A visible shell with the Runner wired into it, over a fake window.
---
--- The panel's render is wrapped only to capture the bounds the SHELL handed it. A test that
--- recomputed the content rect would pass while the shell drew somewhere else, so control bounds
--- below are rebuilt from the same model and the same rect the panel was actually given.
local function wired_shell(opts)
    opts = opts or {}
    local questing = opts.questing
    local clock = opts.clock or fake_clock()
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = nil })

    local binding = IdePanels.new_runner({
        questing = function() return questing end,
        now = function() return clock:now() end,
    })

    local capture = {}
    local spec = binding:spec()
    local inner = spec.render
    spec.render = function(window, bounds, ctx)
        capture.bounds = bounds
        return inner(window, bounds, ctx)
    end

    local ok, reason = shell:register_panel(spec)
    T.assert_true(ok, "the runner spec must be registrable: " .. tostring(reason))
    shell:show()
    return shell, fake, binding, capture, clock
end

--- The bounds of control `id`, taken from the same builder, model and rect the panel drew with.
local function control_bounds(binding, capture, id)
    T.assert_not_nil(capture.bounds, "the panel must have been given a rect to draw in")
    local plan = RunnerPanelState.build(binding:model(), capture.bounds)
    for _, control in ipairs(plan.controls) do
        if control.id == id then return control.bounds end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

function M.test_the_runner_panel_is_registered_and_appears_in_the_switcher()
    local shell, fake = wired_shell({ questing = fake_questing() })
    shell:_on_render_window()

    T.assert_equal(shell:active_id(), "runner",
        "the Runner leads the tab order (ADR 09b §4) and is what the IDE opens on")
    T.assert_true(fake:drew_text("Runner"), "and it must actually be in the switcher")
end

function M.test_installing_registers_the_runner_without_the_shell_naming_it()
    -- `install` is the registration site, and it is neither the shell nor the panel. The shell's
    -- own suite greps `shell.lua` for `ui/panels`; this asserts the other half -- that going
    -- through the host is enough to make the panel reachable.
    local shell = Shell.new({ window = FakeWindow.new(), elements = nil })
    local bindings, reason = IdePanels.install(shell, { questing = function() return nil end })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))
    T.assert_not_nil(shell:state():panel("runner"), "and leave the runner registered on the shell")
    T.assert_not_nil(shell:state():panel("explorer"), "and the explorer must be registered too")
    T.assert_not_nil(bindings.explorer, "the explorer binding must be returned")
end

-- ---------------------------------------------------------------------------
-- A control reaching the module
-- ---------------------------------------------------------------------------

function M.test_a_start_click_reaches_the_questing_module_with_the_selected_profile()
    -- The end-to-end claim of this unit: a pointer on the Start button becomes `module:start(path)`.
    local questing = fake_questing()
    local shell, fake, binding, capture = wired_shell({ questing = questing })

    shell:on_tick()                     -- the tick that fills the model
    shell:_on_render_window()           -- the frame that lays the transport bar out

    local start = control_bounds(binding, capture, "start")
    T.assert_not_nil(start, "the transport bar must offer a Start control")

    fake:click(start)
    shell:_on_render_window()
    T.assert_nil(questing.started,
        "nothing may reach the module from inside the render callback")

    shell:on_tick()
    T.assert_equal(questing.started, PROFILE_DIR .. "/elwynn_1_12.json",
        "the click must reach start() with a path the profile loader can actually open")
end

function M.test_start_is_given_a_path_and_never_a_bare_stem()
    -- `list_profiles` yields stems; `initialize` hands its argument straight to the profile loader
    -- as a file name. A bare stem loads nothing and publishes questing:error -- a Start button that
    -- reports success and runs no route.
    local questing = fake_questing()
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:refresh(true)
    binding:dispatch({ kind = "start", profile = "westfall_12_18" })

    T.assert_equal(questing.started, PROFILE_DIR .. "/westfall_12_18.json",
        "the stem must be resolved against the module's profile directory")
end

function M.test_a_profile_path_supplied_whole_is_passed_through_untouched()
    local questing = fake_questing()
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:dispatch({ kind = "start", profile = "sentinel/data/profiles/quests/custom.json" })
    T.assert_equal(questing.started, "sentinel/data/profiles/quests/custom.json",
        "a caller that already knows the path must not have the directory pasted on twice")
end

-- ---------------------------------------------------------------------------
-- The command vocabulary
-- ---------------------------------------------------------------------------

function M.test_every_command_the_panel_can_emit_reaches_its_verb()
    local questing = fake_questing()
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:refresh(true)

    local expected = {
        { command = { kind = "start" },          verb = "start" },
        { command = { kind = "pause" },          verb = "pause" },
        { command = { kind = "resume" },         verb = "resume" },
        { command = { kind = "stop" },           verb = "stop" },
        { command = { kind = "skip_step" },      verb = "skip_current_step" },
        { command = { kind = "set_guardrails", guardrails = { stop_after_deaths = 3 } },
          verb = "set_guardrails" },
        { command = { kind = "record" },         verb = "start_recording" },
    }

    for _, case in ipairs(expected) do
        local ok, reason = binding:dispatch(case.command)
        T.assert_true(ok, case.command.kind .. " must be accepted: " .. tostring(reason))
        T.assert_not_nil(called(questing, case.verb),
            case.command.kind .. " must reach " .. case.verb .. "()")
    end
end

function M.test_set_guardrails_carries_the_limits_the_panel_computed()
    local questing = fake_questing()
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:dispatch({ kind = "set_guardrails",
        guardrails = { stop_after_deaths = 5, stop_if_stuck_s = 600 } })

    local entry = called(questing, "set_guardrails")
    T.assert_not_nil(entry, "the guardrail chip must reach the module")
    T.assert_equal(entry.arg.stop_after_deaths, 5, "with the deaths limit the panel cycled to")
    T.assert_equal(entry.arg.stop_if_stuck_s, 600, "and the stuck limit")
end

function M.test_an_unknown_command_is_refused_rather_than_silently_ignored()
    -- A dropped command is a control that looks live and is not. That is the exact defect this
    -- unit exists to close, so a new command kind must fail loudly rather than join the inert ones.
    local _shell, _fake, binding = wired_shell({ questing = fake_questing() })
    local ok, reason = binding:dispatch({ kind = "teleport_to_ironforge" })

    T.assert_false(ok, "an unknown command must be refused")
    T.assert_true(type(reason) == "string" and reason:find("teleport_to_ironforge", 1, true) ~= nil,
        "and the refusal must name the command nobody implemented")
end

function M.test_a_malformed_command_is_refused()
    local _shell, _fake, binding = wired_shell({ questing = fake_questing() })
    for _, bad in ipairs({ "start", 7, {}, { kind = 3 } }) do
        local ok, reason = binding:dispatch(bad)
        T.assert_false(ok, "a command without a string kind must be refused")
        T.assert_true(type(reason) == "string" and reason ~= "", "with a reason")
    end
end

function M.test_a_command_is_refused_with_a_reason_when_the_questing_module_is_absent()
    local _shell, _fake, binding = wired_shell({ questing = nil })
    local ok, reason = binding:dispatch({ kind = "pause" })
    T.assert_false(ok, "there is nothing to pause")
    T.assert_true(type(reason) == "string" and reason ~= "",
        "and a failed boot must be answered, not thrown -- the IDE opens precisely then")
end

function M.test_start_is_refused_when_no_profile_is_selected()
    local questing = fake_questing({ profiles = {} })
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:refresh(true)

    local ok, reason = binding:dispatch({ kind = "start" })
    T.assert_false(ok, "there is no compiled profile to run")
    T.assert_true(type(reason) == "string" and reason ~= "", "and the panel is told why")
    T.assert_nil(questing.started, "the module must not be asked to load nothing")
end

function M.test_a_profile_that_fails_to_load_is_reported_as_a_failed_start()
    local questing = fake_questing({ start_ok = false })
    local _shell, _fake, binding = wired_shell({ questing = questing })
    binding:refresh(true)

    local ok, reason = binding:dispatch({ kind = "start" })
    T.assert_false(ok, "a profile that did not load is not a run that started")
    T.assert_true(type(reason) == "string" and reason ~= "", "and the failure names the profile")
end

-- ---------------------------------------------------------------------------
-- The frame budget (ADR 09b §2.4)
-- ---------------------------------------------------------------------------

function M.test_the_view_and_the_profile_list_are_not_read_once_per_frame()
    -- `get_view` rebuilds the entire operator snapshot and `list_profiles` reads a directory.
    -- Either on the per-frame path is exactly what §2.4 forbids.
    local questing = fake_questing()
    local clock = fake_clock()
    local shell = select(1, wired_shell({ questing = questing, clock = clock }))

    for _ = 1, 60 do
        shell:on_tick()
        shell:_on_render_window()
        clock:advance(1 / 60)           -- one second of frames
    end

    T.assert_true(questing.views <= 8,
        "the view must be cached across frames; it was rebuilt " .. questing.views .. " times in "
        .. "one second of rendering")
    T.assert_equal(questing.scans, 1,
        "and the profile directory must be read once, not once per frame")
end

function M.test_the_view_does_refresh_as_the_clock_advances()
    -- The other half of the same rule: a cache with no expiry is a panel that stops telling the
    -- truth, which is worse than one that costs a little.
    local questing = fake_questing()
    local clock = fake_clock()
    local shell = select(1, wired_shell({ questing = questing, clock = clock }))

    shell:on_tick()
    local first = questing.views
    clock:advance(5.0)
    shell:on_tick()
    T.assert_true(questing.views > first, "the panel must not freeze on its first reading")
end

function M.test_rescan_re_reads_the_profile_directory_at_once()
    -- The operator just compiled a route in another window. Waiting out the refresh interval to
    -- see it is what the Rescan button exists to avoid.
    local questing = fake_questing()
    local clock = fake_clock()
    local shell, _fake, binding = wired_shell({ questing = questing, clock = clock })

    shell:on_tick()
    T.assert_equal(questing.scans, 1, "one scan so far")
    questing.profiles = { "elwynn_1_12", "westfall_12_18", "redridge_18_24" }

    binding:dispatch({ kind = "rescan" })
    shell:on_tick()
    T.assert_equal(questing.scans, 2, "rescan must force the directory read")
    T.assert_equal(#binding:model().profiles, 3, "and the new route must appear")
end

function M.test_a_control_that_changed_the_run_refreshes_the_view_at_once()
    -- A Pause that left the panel reading RUNNING for a quarter of a second reads as a Pause that
    -- did nothing, which is indistinguishable from the inert controls this unit is fixing.
    local questing = fake_questing()
    local clock = fake_clock()
    local shell, _fake, binding = wired_shell({ questing = questing, clock = clock })

    shell:on_tick()
    local before = questing.views
    binding:dispatch({ kind = "pause" })
    shell:on_tick()
    T.assert_true(questing.views > before, "the view must be re-read after a control changed it")
    T.assert_true(binding:model().paused, "and the panel must now show Resume, not Pause")
end

function M.test_no_menu_element_is_constructed_while_the_wired_panel_renders()
    -- Sylvannas forbids it, it fails in the injector alone, and the panel is now reached through a
    -- host closure -- a new indirection that could have hidden a construction.
    local saved_menu = _G.core and _G.core.menu or nil
    local created = 0
    local counting = {}
    for _, name in ipairs({ "slider_int", "keybind", "window", "button", "checkbox", "tree_node" }) do
        counting[name] = function() created = created + 1; return {} end
    end
    if _G.core then _G.core.menu = counting end

    local shell = select(1, wired_shell({ questing = fake_questing() }))
    shell:on_tick()
    created = 0
    local ok, err = pcall(function()
        for _ = 1, 5 do shell:_on_render_window() end
    end)

    if _G.core then _G.core.menu = saved_menu end
    T.assert_true(ok, "the wired panel must render: " .. tostring(err))
    T.assert_equal(created, 0,
        "Sylvannas forbids creating menu elements inside a render callback; " .. created
        .. " were created there")
end

-- ---------------------------------------------------------------------------
-- Degrading when questing is not there (the state `toggle_ide` exists for)
-- ---------------------------------------------------------------------------

function M.test_the_panel_renders_its_empty_state_when_the_questing_module_is_absent()
    -- `toggle_ide` deliberately bypasses `ensure_initialized`, because a failed boot is exactly
    -- when an operator opens the IDE. The Runner must then instruct, not error and not blank.
    local shell, fake = wired_shell({ questing = nil })
    local ok, err = pcall(function()
        shell:on_tick()
        shell:_on_render_window()
    end)

    T.assert_true(ok, "a missing questing module must not throw on the render path: " .. tostring(err))
    T.assert_true(fake:drew_text("No profile running"),
        "the panel must draw its empty state rather than a blank pane (ADR 09b §5.5)")
end

function M.test_the_model_carries_the_four_fields_the_panel_needs_every_frame()
    local questing = fake_questing()
    local shell, _fake, binding = wired_shell({ questing = questing })
    shell:on_tick()

    local model = binding:model()
    T.assert_not_nil(model.view, "view -- the operator snapshot the panel projects")
    T.assert_equal(type(model.profiles), "table", "profiles -- what Start can choose between")
    T.assert_equal(model.selected_profile, "elwynn_1_12", "selected_profile -- what Start will load")
    T.assert_false(model.paused, "paused -- which of Pause/Resume the transport bar shows")
end

function M.test_the_selection_falls_back_to_a_profile_that_still_exists()
    -- Without this the Start button is permanently disabled: the panel disables it when
    -- `selected_profile` is nil and there is no profile picker on it yet.
    local questing = fake_questing()
    local shell, _fake, binding = wired_shell({ questing = questing })
    shell:on_tick()
    T.assert_equal(binding:model().selected_profile, "elwynn_1_12", "a default is chosen")

    questing.profiles = { "westfall_12_18" }
    binding:dispatch({ kind = "rescan" })
    shell:on_tick()
    T.assert_equal(binding:model().selected_profile, "westfall_12_18",
        "a selection that no longer exists must not leave Start pointing at a deleted route")
end

function M.test_the_panel_keeps_drawing_when_the_module_disappears_mid_session()
    -- A reload tears the app down and stands a new one up; the shell survives both.
    local questing = fake_questing()
    local present = true
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = nil })
    local binding = IdePanels.new_runner({
        questing = function() return present and questing or nil end,
        now = function() return 0 end,
    })
    shell:register_panel(binding:spec())
    shell:show()

    shell:on_tick()
    shell:_on_render_window()
    present = false
    fake:reset()

    local ok = pcall(function()
        shell:on_tick()
        shell:_on_render_window()
    end)
    T.assert_true(ok, "losing the module mid-session must not break the frame")
    T.assert_nil(binding:model().view, "and the stale snapshot must be dropped, not kept")
end

return M
