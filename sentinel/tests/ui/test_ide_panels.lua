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
local GraphState = require("ui/panels/graph_state")
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

-- ---------------------------------------------------------------------------
-- The QueryClient seam (spec: QueryClient Wiring at Install)
-- ---------------------------------------------------------------------------
--
-- The same class of defect as the Runner seam above, one layer down. `main.lua` registered the
-- panels and never passed a client, so every data binding answered its own `if not qc then return`
-- and drew an idle view. Both halves were green: the panels' suites supplied a client, and
-- `main.lua` has no suite. Only a test that installs the way the host installs can see it.

--- A QueryClient stand-in that records every call and resolves nothing.
---
--- A TABLE, not a resolver returning one. That is the whole contract under test: the doc comments
--- promised `function():table|nil` while every call site already wrote `qc:get_quest(id)`, so a host
--- that believed the docs would have passed something no binding could call.
local function fake_query_client()
    local qc = { calls = {} }
    local function record(name, arg)
        qc.calls[#qc.calls + 1] = { name = name, arg = arg }
        return nil
    end
    function qc.get_quest(_, id) return record("get_quest", id) end
    function qc.get_quest_chain(_, id) return record("get_quest_chain", id) end
    function qc.get_quest_objectives(_, id) return record("get_quest_objectives", id) end
    function qc.search_quests(_, q) return record("search_quests", q) end
    function qc.get_npc(_, entry) return record("get_npc", entry) end
    function qc.get_vendor(_, entry) return record("get_vendor", entry) end
    function qc.get_object(_, entry) return record("get_object", entry) end
    return qc
end

local function qc_called(qc, name)
    for _, entry in ipairs(qc.calls) do
        if entry.name == name then return entry end
    end
    return nil
end

--- Every panel that talks to the QueryServer. The Graph panel is absent on purpose: it is backed by
--- the editor crate on :3031, not the query server, and gets its client in a later slice.
local DATA_PANELS = { "explorer", "properties", "database" }

function M.test_installing_without_a_query_client_says_so_instead_of_idling()
    local shell = Shell.new({ window = FakeWindow.new(), elements = nil })
    local bindings, reason = IdePanels.install(shell, { questing = function() return nil end })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))
    shell:show()

    for _, id in ipairs(DATA_PANELS) do
        local state = bindings[id]:state()
        T.assert_nil(state.error, id .. " must start with a clean error field")

        shell:activate(id)
        shell:on_tick()

        T.assert_equal(state.error, IdePanels.QUERY_SERVER_UNAVAILABLE,
            id .. " must name the missing query server rather than draw an empty panel; an idle "
            .. "view is indistinguishable from a panel with nothing to show")
        T.assert_true(state.loading ~= true,
            id .. " must not be left spinning on a fetch that was never issued")
    end
end

function M.test_the_unavailable_state_reaches_the_rendered_view()
    -- `state.error` is only worth setting if the panel actually paints it. Asserting the field and
    -- not the frame is how the last cycle shipped panels that "handled" failures invisibly.
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = nil })
    local bindings = IdePanels.install(shell, { questing = function() return nil end })
    shell:show()

    for _, id in ipairs(DATA_PANELS) do
        shell:activate(id)
        shell:on_tick()
        fake:reset()
        shell:_on_render_window()
        T.assert_true(fake:drew_text("query server unavailable"),
            id .. " must paint the unavailable message, not merely record it on the state")
    end
end

function M.test_installing_with_a_query_client_hands_every_binding_that_exact_table()
    local qc = fake_query_client()
    local shell = Shell.new({ window = FakeWindow.new(), elements = nil })
    local bindings, reason = IdePanels.install(shell, {
        questing = function() return nil end,
        query_client = qc,
    })
    T.assert_not_nil(bindings, "install must succeed: " .. tostring(reason))

    for _, id in ipairs(DATA_PANELS) do
        T.assert_true(bindings[id]._query_client == qc,
            id .. " must hold the very table install was given, not a copy or a wrapper")
        T.assert_nil(bindings[id]:state().error,
            id .. " must not report the server unavailable when a client was supplied")
    end
end

function M.test_an_explorer_selection_reaches_the_client_on_the_next_tick()
    -- The end-to-end claim of this slice: selecting in a panel becomes a real request. It must
    -- happen on the TICK and not in the frame -- Sylvannas forbids the reverse, and the previous
    -- cockpit died of exactly that.
    local qc = fake_query_client()
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = nil })
    local bindings = IdePanels.install(shell, {
        questing = function() return nil end,
        query_client = qc,
    })
    shell:show()
    shell:activate("explorer")
    shell:on_tick()

    local before = #qc.calls
    bindings.explorer:spec().dispatch({ kind = "select_quest", id = 1234 })
    shell:_on_render_window()
    T.assert_equal(#qc.calls, before,
        "no request may be issued from inside a render callback")

    shell:on_tick()
    local call = qc_called(qc, "get_quest")
    T.assert_not_nil(call, "the selection must reach get_quest on the following tick")
    T.assert_equal(call.arg, 1234, "and it must carry the id that was selected")
end

-- ---------------------------------------------------------------------------
-- Async pending re-arm (spec: Async Pending Re-Arm)
-- ---------------------------------------------------------------------------
--
-- The regression: `on_tick` cleared `_dirty` (and the database's `_pending_*`) at the TOP, before
-- the fetch had answered. In the injector the first answer is always `(nil, true)` -- pending -- so
-- the tick that would have collected the real answer never ran and the panel froze on its idle
-- view. Offline the mocks resolved in the same call, so every suite stayed green.
--
-- Each test below is that exact shape: tick 1 answers pending, tick 2 answers data.

--- A QueryClient stand-in that answers `(nil, true)` for the first `pending_for` calls of each verb
--- and the fixture afterwards -- the live `_get` contract, per path.
local function pending_query_client(rows, pending_for)
    pending_for = pending_for or 1
    local qc = { calls = {}, _seen = {} }
    local function answer(name, key)
        local slot = name .. ":" .. tostring(key)
        qc.calls[#qc.calls + 1] = { name = name, arg = key }
        qc._seen[slot] = (qc._seen[slot] or 0) + 1
        if qc._seen[slot] <= pending_for then return nil, true end
        return rows[name]
    end
    function qc.get_quest(_, id) return answer("get_quest", id) end
    function qc.get_quest_chain(_, id) return answer("get_quest_chain", id) end
    function qc.get_quest_objectives(_, id) return answer("get_quest_objectives", id) end
    function qc.search_quests(_, q) return answer("search_quests", q) end
    function qc.get_npc(_, entry) return answer("get_npc", entry) end
    function qc.get_vendor(_, entry) return answer("get_vendor", entry) end
    function qc.get_object(_, entry) return answer("get_object", entry) end
    return qc
end

local function installed_with(qc)
    local fake = FakeWindow.new()
    local shell = Shell.new({ window = fake, elements = nil })
    local bindings = IdePanels.install(shell, {
        questing = function() return nil end,
        query_client = qc,
    })
    shell:show()
    return shell, bindings, fake
end

function M.test_the_explorer_polls_a_pending_quest_lookup_instead_of_freezing_on_it()
    local qc = pending_query_client({ get_quest = { id = 1234, title = "The Missing Diplomat" } })
    local shell, bindings = installed_with(qc)
    shell:activate("explorer")
    shell:on_tick()

    local state = bindings.explorer:state()
    bindings.explorer:spec().dispatch({ kind = "select_quest", id = 1234 })

    shell:on_tick()
    T.assert_nil(state.selected_detail, "tick 1 answered pending, so there is nothing to show yet")
    T.assert_true(state._dirty,
        "and the flag must be RE-ARMED -- cleared here, the answer is never collected and the "
        .. "panel shows its idle view forever")
    T.assert_true(state.loading, "the panel says it is waiting")
    T.assert_nil(state.error, "a request in flight is not a failed request")

    shell:on_tick()
    T.assert_not_nil(state.selected_detail, "tick 2 must store the answer")
    T.assert_equal(state.selected_detail.title, "The Missing Diplomat", "the one that was asked for")
end

function M.test_the_properties_inspector_polls_a_pending_npc_lookup()
    local qc = pending_query_client({ get_npc = { entry = 567, name = "Hogger" } })
    local shell, bindings = installed_with(qc)
    shell:activate("properties")

    local state = bindings.properties:state()
    state:set_context({ selection_type = "npc", selection_id = 567 })

    shell:on_tick()
    T.assert_nil(state.npc_detail, "tick 1 is pending")
    T.assert_true(state._dirty, "so the inspector must re-arm rather than clear")
    T.assert_true(state.loading, "and keep saying it is waiting")

    shell:on_tick()
    T.assert_not_nil(state.npc_detail, "tick 2 stores the NPC")
    T.assert_equal(state.npc_detail.name, "Hogger", "with the row the server answered")
    T.assert_false(state.loading, "and stops waiting once it has it")
end

function M.test_the_database_detail_polls_instead_of_reporting_not_found()
    -- `Entry N not found` is reserved for a lookup that RESOLVED to nothing. Reaching it while the
    -- request is still in flight tells the operator their entry does not exist when it does.
    local qc = pending_query_client({ get_npc = { entry = 567, name = "Wolf", positions = {} } })
    local shell, bindings = installed_with(qc)
    shell:activate("database")

    local state = bindings.database:state()
    bindings.database:spec().dispatch({ kind = "select_entry", entry = 567 })

    shell:on_tick()
    T.assert_nil(state.selected_detail, "tick 1 is pending")
    T.assert_nil(state.error, "and a pending fetch must never read as 'not found'")
    T.assert_true(state._pending_detail, "the pending flag survives the tick that answered nothing")
    T.assert_true(state._dirty, "and the slot re-armed the panel for the next tick")

    shell:on_tick()
    T.assert_not_nil(state.selected_detail, "tick 2 stores the detail")
    T.assert_equal(state.selected_detail.name, "Wolf", "the entry that was selected")
    T.assert_false(state._pending_detail, "and only NOW does the flag clear")
end

function M.test_a_properties_selection_reaches_the_client_on_the_next_tick()
    local qc = fake_query_client()
    local shell = Shell.new({ window = FakeWindow.new(), elements = nil })
    local bindings = IdePanels.install(shell, {
        questing = function() return nil end,
        query_client = qc,
    })
    shell:show()
    shell:activate("properties")

    bindings.properties:state():set_context({ selection_type = "npc", selection_id = 567 })
    shell:on_tick()

    local call = qc_called(qc, "get_npc")
    T.assert_not_nil(call, "an NPC context must reach get_npc")
    T.assert_equal(call.arg, 567, "and it must carry the selected entry")
end

-- ---------------------------------------------------------------------------
-- The Explorer's search seam and its authoring commands
-- ---------------------------------------------------------------------------
--
-- Typing happens inside a render callback. The binding's `on_tick` returns early unless `_dirty` is
-- set, and the widget has no way to set it — so unless the tick reads the buffer BEFORE that gate,
-- the search bar is typeable and still completely inert. These tests hold that seam.

---A clock the test drives by hand, so a 300ms debounce takes no wall-clock time.
local function fake_clock()
    local clock = { t = 0 }
    function clock.read() return clock.t end
    function clock.advance(seconds) clock.t = clock.t + seconds end
    return clock
end

---A query client that counts searches and answers a fixed, server-shaped result set.
local function searching_client(results)
    local qc = { searches = {} }
    function qc.search_quests(_, q)
        qc.searches[#qc.searches + 1] = q
        return results
    end
    function qc.get_quest() return nil end
    function qc.get_quest_chain() return nil end
    function qc.get_quest_objectives() return nil end
    return qc
end

local function explorer_with(opts)
    local binding = IdePanels.new_explorer(opts)
    return binding, binding:spec(), binding:state()
end

function M.test_rapid_typing_then_300ms_fires_exactly_one_search()
    local clock = fake_clock()
    local qc = searching_client({ { id = 783, title = "A Threat Within", level = 10,
                                   zone = "Elwynn Forest" } })
    local _, spec, state = explorer_with({ query_client = qc, now = clock.read })

    -- Four keystrokes inside one debounce window, the way a person types "wolf".
    for _, typed in ipairs({ "w", "wo", "wol", "wolf" }) do
        state.search_input:focus()
        state.search_input.buffer = typed
        spec.on_tick()
        clock.advance(0.05)
    end
    T.assert_equal(#qc.searches, 0, "nothing may go out while the operator is still typing")

    clock.advance(0.30)
    spec.on_tick()
    T.assert_equal(#qc.searches, 1, "exactly one search after the wait, not one per keystroke")
    T.assert_equal(qc.searches[1], "wolf", "and it carries the FINAL buffer, not an early prefix")
    T.assert_equal(#state.results, 1, "the results land on the state")

    spec.on_tick()
    spec.on_tick()
    T.assert_equal(#qc.searches, 1, "and the gate closes; a served query must not re-fire forever")
end

function M.test_a_second_query_searches_again_even_with_results_on_screen()
    -- The old gate was `search_query ~= "" and #results == 0`, so a panel could only ever run one
    -- search: with rows on screen, the next query was silently dropped.
    local clock = fake_clock()
    local qc = searching_client({ { id = 1, title = "Something", level = 1 } })
    local _, spec, state = explorer_with({ query_client = qc, now = clock.read })

    -- The tick that NOTICES the typing stamps the debounce, so the wait is measured from there.
    state.search_input:set_value("wolf")
    spec.on_tick()
    clock.advance(0.40)
    spec.on_tick()
    T.assert_equal(#qc.searches, 1)

    state.search_input:set_value("bear")
    spec.on_tick()
    clock.advance(0.40)
    spec.on_tick()
    T.assert_equal(#qc.searches, 2, "a second query must reach the server")
    T.assert_equal(qc.searches[2], "bear")
end

function M.test_the_tick_reads_the_buffer_before_the_dirty_gate()
    local clock = fake_clock()
    local qc = searching_client({})
    local _, spec, state = explorer_with({ query_client = qc, now = clock.read })

    spec.on_tick()          -- consume the initial dirty flag
    state._dirty = false
    state.search_input:focus()
    state.search_input.buffer = "wolf"

    spec.on_tick()
    T.assert_equal(state.search_query, "wolf",
        "a keystroke must be noticed even though nothing marked the panel dirty")
end

function M.test_escape_never_sends_the_discarded_edit()
    local clock = fake_clock()
    local qc = searching_client({})
    local _, spec, state = explorer_with({ query_client = qc, now = clock.read })

    state.search_input:set_value("wolf")
    clock.advance(0.40); spec.on_tick(); spec.on_tick()

    state.search_input:focus()
    state.search_input.buffer = "wolfsbane"
    state.search_input:apply_key({ vk = require("ui/text_input_state").VK.ESCAPE })
    spec.dispatch({ kind = "cancel_search" }, nil)
    clock.advance(1.00)
    spec.on_tick()

    T.assert_equal(#qc.searches, 1, "the cancelled edit must not reach the server")
    T.assert_equal(qc.searches[1], "wolf", "and what did go out was the committed value")
    T.assert_equal(state.search_query, "wolf", "the query stays on the committed value")
end

-- ---- Add to Profile / Add Chain ------------------------------------------

local function recording_editor()
    local editor = { writes = {} }
    function editor.add_nodes(_, campaign, nodes)
        editor.writes[#editor.writes + 1] = { campaign = campaign, nodes = nodes }
        return true
    end
    return editor
end

local function loaded_explorer(editor)
    local binding, spec, state = explorer_with({
        query_client = searching_client({}),
        editor_client = editor,
        campaign = function() return "stw" end,
        now = function() return 0 end,
    })
    state.selected_id = 1234
    state.selected_detail = { id = 1234, giver_entry = 823, finisher_entry = 197 }
    state.objectives = { quest_id = 1234, objectives = {
        { index = 1, kind = "kill", entry = 567, name = "Wolf", count = 10 },
        { index = 2, kind = "collect", entry = 789, name = "Pelt", count = 5,
          source_creatures = { 567 } },
    } }
    state.chain_data = { quest_id = 1234, title = "A Quest", prerequisites = {}, follow_ups = {} }
    return binding, spec, state
end

function M.test_add_to_profile_writes_the_objective_subgraph_to_the_editor()
    -- SPEC: quest 1234 with kill(567x10) and loot(789x5) yields AcceptQuest(1234), Kill(567,10),
    -- Loot(789,5), TurnInQuest(1234). Previously this returned ok with "(not yet implemented)".
    local editor = recording_editor()
    local _, spec = loaded_explorer(editor)

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_true(ok, "the write must succeed: " .. tostring(reason))
    T.assert_equal(#editor.writes, 1, "exactly one write")
    T.assert_equal(editor.writes[1].campaign, "stw", "into the open campaign")

    local kinds = {}
    for i, node in ipairs(editor.writes[1].nodes) do kinds[i] = node.type end
    T.assert_equal(table.concat(kinds, ","),
        "questing.AcceptQuest,questing.Kill,questing.Loot,questing.TurnInQuest",
        "the exact subgraph the spec names, in order")
end

function M.test_add_chain_writes_the_chain_to_the_editor()
    local editor = recording_editor()
    local _, spec, state = loaded_explorer(editor)
    state.chain_data = { quest_id = 1234, title = "A Quest",
                         prerequisites = { { quest_id = 1, title = "First" } }, follow_ups = {} }

    local ok = spec.dispatch({ kind = "add_chain", quest_id = 1234 }, nil)
    T.assert_true(ok)
    T.assert_equal(#editor.writes[1].nodes, 4, "two quests, accept and turn-in each")
end

function M.test_no_editor_client_is_reported_and_never_reported_as_done()
    -- obs #225: both commands answered "(not yet implemented)" AND returned ok, so the operator
    -- was told the write happened.
    local _, spec, state = loaded_explorer(nil)

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_false(ok, "a write with nowhere to go must not report success")
    T.assert_true(tostring(reason):find("editor unavailable", 1, true) ~= nil,
        "and must name the missing editor: " .. tostring(reason))
    T.assert_equal(state.error, reason, "the panel paints the same fact it returned")
end

function M.test_no_open_campaign_is_reported()
    local binding, spec, state = loaded_explorer(recording_editor())
    binding._campaign = function() return nil end

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_false(ok)
    T.assert_true(tostring(reason):find("no campaign is open", 1, true) ~= nil, tostring(reason))
    T.assert_equal(state.error, reason)
end

function M.test_unloaded_objectives_refuse_rather_than_write_a_hollow_quest()
    -- Accept→TurnIn with the middle missing is a quest the bot accepts and then stands still in.
    local editor = recording_editor()
    local _, spec, state = loaded_explorer(editor)
    state.objectives = nil

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_false(ok)
    T.assert_equal(#editor.writes, 0, "nothing may be written while the objectives are in flight")
    T.assert_true(tostring(reason):find("have not loaded yet", 1, true) ~= nil, tostring(reason))
end

function M.test_an_editor_that_refuses_the_write_is_not_a_success()
    local editor = recording_editor()
    function editor.add_nodes() return false, "campaign is locked" end
    local _, spec, state = loaded_explorer(editor)

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_false(ok, "a live editor saying no is not the same as a write that landed")
    T.assert_true(tostring(reason):find("campaign is locked", 1, true) ~= nil, tostring(reason))
    T.assert_equal(state.error, reason)
end

function M.test_an_editor_that_raises_is_a_failed_write_not_a_dead_tick()
    local editor = recording_editor()
    function editor.add_nodes() error("connection reset") end
    local _, spec = loaded_explorer(editor)

    local ok, reason = spec.dispatch({ kind = "add_to_profile", quest_id = 1234 }, nil)
    T.assert_false(ok)
    T.assert_true(tostring(reason):find("connection reset", 1, true) ~= nil, tostring(reason))
end

-- ---- Graph campaign lifecycle (spec: Graph Campaign Lifecycle) ------------

--- An editor client that answers from a script, records every call, and can be made to say no.
---@param opts table { campaigns, campaign, create_answer, add_result }
local function fake_editor(opts)
    opts = opts or {}
    local editor = { calls = {}, writes = {}, errors = {}, forgotten = {} }
    local function record(name, arg)
        editor.calls[#editor.calls + 1] = { name = name, arg = arg }
    end
    function editor.list_campaigns() record("list_campaigns") return opts.campaigns end
    function editor.load_campaign(_, name) record("load_campaign", name) return opts.campaign end
    function editor.create_campaign(_, name)
        record("create_campaign", name)
        if opts.create_answer == nil then return nil, true end
        return opts.create_answer
    end
    function editor.add_nodes(_, campaign, nodes)
        editor.writes[#editor.writes + 1] = { campaign = campaign, nodes = nodes }
        if opts.add_result ~= nil then return opts.add_result, opts.add_reason end
        return true
    end
    function editor.take_error() return table.remove(editor.errors, 1) end
    function editor.forget_create(_, name) editor.forgotten[#editor.forgotten + 1] = name end
    return editor
end

local function editor_campaign_doc(name, graph_id, nodes)
    return {
        schema_version = 1, id = "11111111-1111-4111-8111-111111111111", name = name,
        imports = {}, variables = {}, conditions = {},
        graphs = { { id = graph_id, name = "main",
                     entry_node = "00000000-0000-0000-0000-000000000000",
                     nodes = nodes or {}, edges = {} } },
    }
end

local function graph_with(editor)
    local binding = IdePanels.new_graph({ editor_client = editor })
    return binding, binding:spec(), binding:state()
end

function M.test_the_graph_tick_asks_the_editor_for_its_campaign_list()
    local editor = fake_editor({ campaigns = { { name = "a", node_count = 0 } } })
    local _, spec, state = graph_with(editor)

    spec.on_tick()
    T.assert_equal(editor.calls[1].name, "list_campaigns",
        "the chooser has to be populated from the editor, not from nothing")
    T.assert_equal(#state.campaigns, 1, "and the answer lands on the state")

    spec.on_tick()
    T.assert_equal(#editor.calls, 1,
        "and it is asked ONCE -- a tick that re-armed itself on its own answer would re-list "
        .. "every frame for the life of the session")
end

function M.test_create_list_open_round_trip()
    -- SPEC: create "stw" from the empty state, then the panel shows an editable graph for it.
    local editor = fake_editor({
        campaigns = {},
        create_answer = { name = "stw", id = "z", node_count = 0, edge_count = 0 },
        campaign = editor_campaign_doc("stw", "graph-1", {
            { id = "aaaaaaaa-0000-4000-8000-000000000001", type = "questing.Kill",
              intent = { creature_entry = 567 } },
        }),
    })
    local _, spec, state = graph_with(editor)
    state.name_input:set_value("stw")

    local ok, reason = spec.dispatch({ kind = "create_campaign" }, nil)
    T.assert_true(ok, "the create is accepted: " .. tostring(reason))
    T.assert_equal(state:pending_campaign_name(), "",
        "and the field is cleared, so a second click cannot re-create the same campaign")

    spec.on_tick()   -- the create resolves
    T.assert_equal(editor.calls[1].name, "create_campaign", "POST /editor/campaigns went out")
    T.assert_equal(editor.calls[1].arg, "stw", "naming the campaign")
    T.assert_equal(state.campaign_name, "stw", "which the panel then opens")

    spec.on_tick()   -- the open resolves
    T.assert_equal(editor.calls[2].name, "load_campaign", "by reading it back from the editor")
    T.assert_equal(#state.nodes, 1, "and the graph on screen is the one the editor returned")
    T.assert_equal(state.graph_id, "graph-1", "with the graph id every later write must name")
end

function M.test_a_create_still_in_flight_does_not_open_anything()
    local editor = fake_editor({ campaigns = {} })   -- create_answer nil: pending forever
    local _, spec, state = graph_with(editor)
    state.name_input:set_value("stw")
    spec.dispatch({ kind = "create_campaign" }, nil)

    spec.on_tick()
    T.assert_nil(state.campaign_name,
        "opening before the editor answered would ask for a campaign that does not exist yet, "
        .. "and QueryClient caches the 404 that comes back")
    T.assert_true(state.loading, "the panel says it is waiting")
    T.assert_true(state._dirty, "and the slot re-armed the tick that will collect the answer")
end

function M.test_creating_without_a_name_is_refused_and_never_reaches_the_editor()
    local editor = fake_editor({ campaigns = {} })
    local _, spec, state = graph_with(editor)

    spec.dispatch({ kind = "create_campaign" }, nil)
    spec.on_tick()
    for _, call in ipairs(editor.calls) do
        T.assert_true(call.name ~= "create_campaign", "an unnamed campaign is not created")
    end
    T.assert_true(tostring(state.error):find("name the campaign", 1, true) ~= nil,
        "and the panel says why, got " .. tostring(state.error))
end

function M.test_opening_a_campaign_reads_it_from_the_editor()
    local editor = fake_editor({
        campaigns = { { name = "b", node_count = 3 } },
        campaign = editor_campaign_doc("b", "graph-b", {
            { id = "n1", type = "questing.Travel", intent = { destination = "Goldshire" } },
            { id = "n2", type = "questing.Kill", intent = { creature_entry = 567 } },
        }),
    })
    local _, spec, state = graph_with(editor)

    spec.dispatch({ kind = "open_campaign", name = "b" }, nil)
    spec.on_tick()
    T.assert_equal(state.campaign_name, "b", "b is open")
    T.assert_equal(#state.nodes, 2, "showing b's nodes and edges")
    T.assert_equal(state.nodes[1].id, "n1", "with the editor's ids")
end

function M.test_with_no_editor_client_the_panel_says_so_and_fetches_nothing()
    local _, spec, state = graph_with(nil)

    spec.on_tick()
    T.assert_true(tostring(state.error):find("editor unavailable", 1, true) ~= nil,
        "an absent client is a state the panel PAINTS, never a silent idle: " .. tostring(state.error))
    T.assert_false(state.loading, "and it is not pretending to load")
end

-- ---- Database add_as_kill ------------------------------------------------

---A Database binding wired with the given opts.
local function database_with(opts)
    local binding = IdePanels.new_database(opts)
    return binding, binding:spec(), binding:state()
end

function M.test_add_as_kill_with_no_editor_reports_the_missing_client()
    -- 3.15: editor down for add_as_kill produces state.error naming the failed write,
    -- no phantom node appears.
    local editor = recording_editor()
    local _, spec, state = database_with({
        query_client = fake_query_client(),
        editor_client = nil,
        campaign = function() return "stw" end,
    })

    local ok, reason = spec.dispatch({ kind = "add_as_kill", entry = 567 }, nil)
    T.assert_false(ok, "a kill node with nowhere to write must not report success")
    T.assert_true(tostring(reason):find("editor unavailable", 1, true) ~= nil,
        "and must name the missing editor: " .. tostring(reason))
    T.assert_equal(state.error, reason, "the panel paints the same fact it returned")
    T.assert_equal(#editor.writes, 0, "no phantom node was written anywhere")
end

function M.test_add_as_kill_with_no_campaign_is_reported()
    local _, spec, state = database_with({
        query_client = fake_query_client(),
        editor_client = recording_editor(),
        campaign = function() return nil end,
    })

    local ok, reason = spec.dispatch({ kind = "add_as_kill", entry = 567 }, nil)
    T.assert_false(ok)
    T.assert_true(tostring(reason):find("no campaign is open", 1, true) ~= nil,
        tostring(reason))
    T.assert_equal(state.error, reason)
end

function M.test_add_as_kill_writes_the_kill_node_to_the_open_campaign()
    local editor = recording_editor()
    local _, spec, state = database_with({
        query_client = fake_query_client(),
        editor_client = editor,
        campaign = function() return "stw" end,
    })

    local ok, reason = spec.dispatch({ kind = "add_as_kill", entry = 567 }, nil)
    T.assert_true(ok, "the write must succeed: " .. tostring(reason))
    T.assert_equal(#editor.writes, 1, "exactly one write")
    T.assert_equal(editor.writes[1].campaign, "stw", "into the open campaign")
    T.assert_equal(editor.writes[1].nodes[1].type, "questing.Kill", "a Kill node")
    T.assert_equal(editor.writes[1].nodes[1].intent.creature_entry, 567,
        "carrying the NPC entry")
    T.assert_nil(state.error, "no error was set on the state")
end

-- ---- The guard: editor down means an error, never a phantom node ----------

function M.test_a_refused_node_write_leaves_an_error_and_no_node()
    local editor = fake_editor({
        campaign = editor_campaign_doc("stw", "graph-1", {}),
        add_result = false, add_reason = "campaign is locked",
    })
    local _, spec, state = graph_with(editor)
    state:apply_campaign(editor_campaign_doc("stw", "graph-1", {}))

    local ok, reason = spec.dispatch({ kind = "show_add_node_menu" }, nil)
    T.assert_true(ok, "the command was handled")
    T.assert_true(tostring(reason):find("campaign is locked", 1, true) ~= nil,
        "and the editor's refusal is the reason, got " .. tostring(reason))
    T.assert_equal(state.error, reason, "which the panel paints")
    T.assert_equal(#state.nodes, 0,
        "AND NO NODE APPEARS. A node inserted locally on a failed write is indistinguishable on "
        .. "screen from one the editor stored -- that is the defect, not the error message")
end

function M.test_an_editor_that_raises_on_a_node_write_is_a_failed_write()
    local editor = fake_editor({ campaign = editor_campaign_doc("stw", "graph-1", {}) })
    function editor.add_nodes() error("connection reset") end
    local _, spec, state = graph_with(editor)
    state:apply_campaign(editor_campaign_doc("stw", "graph-1", {}))

    spec.dispatch({ kind = "show_add_node_menu" }, nil)
    T.assert_true(tostring(state.error):find("connection reset", 1, true) ~= nil,
        tostring(state.error))
    T.assert_equal(#state.nodes, 0, "and still no node")
end

function M.test_adding_a_node_with_no_campaign_open_writes_nowhere()
    local editor = fake_editor({ campaigns = {} })
    local _, spec, state = graph_with(editor)

    spec.dispatch({ kind = "show_add_node_menu" }, nil)
    T.assert_equal(#editor.writes, 0, "there is nowhere to write it")
    T.assert_true(tostring(state.error):find("no campaign is open", 1, true) ~= nil,
        tostring(state.error))
    T.assert_equal(#state.nodes, 0, "and no floating node is invented to hold the intent")
end

function M.test_an_accepted_node_write_re_reads_the_graph_instead_of_patching_it()
    local editor = fake_editor({ campaign = editor_campaign_doc("stw", "graph-1", {
        { id = "n1", type = "questing.Kill", intent = { creature_entry = 0, count = 1 } },
    }) })
    local _, spec, state = graph_with(editor)
    state:apply_campaign(editor_campaign_doc("stw", "graph-1", {}))
    T.assert_equal(#state.nodes, 0, "nothing on screen yet")

    local ok = spec.dispatch({ kind = "show_add_node_menu" }, nil)
    T.assert_true(ok)
    T.assert_equal(#editor.writes, 1, "one write")
    T.assert_equal(editor.writes[1].nodes[1].type, "questing.Kill", "of the template node")
    T.assert_equal(#state.nodes, 0, "and the panel has NOT drawn it yet")

    spec.on_tick()
    T.assert_equal(#state.nodes, 1,
        "it appears only once the editor's own graph comes back, so what is on screen is what was "
        .. "stored")
end

function M.test_an_editor_refusal_that_arrives_late_still_reaches_the_panel()
    local editor = fake_editor({ campaigns = {} })
    local _, spec, state = graph_with(editor)

    -- A write dispatched some ticks ago; the editor's answer has only just landed.
    editor.errors[1] = "add 1 node(s) to 'stw' failed: HTTP 409: campaign is locked"
    spec.on_tick()
    T.assert_true(tostring(state.error):find("409", 1, true) ~= nil,
        "a mutation can only report that its request LEFT, so the server's verdict has to surface "
        .. "on a later tick or it never surfaces at all: " .. tostring(state.error))
end

-- ---- Validate / compile (spec: Validate and Compile as Invoked from Graph) --

local TURNIN_ID = "bbbbbbbb-0000-4000-8000-000000000009"

--- The campaign the spec's scenario names: TurnInQuest(9) with no AcceptQuest(9).
local function unmatched_turnin_campaign()
    return editor_campaign_doc("stw", "graph-1", {
        { id = TURNIN_ID, type = "questing.TurnInQuest", intent = { quest_id = 9 } },
    })
end

local function validating_graph(diagnostics, compile_answer)
    local editor = fake_editor({ campaign = unmatched_turnin_campaign() })
    editor.validated, editor.compiled, editor.forgotten_keys = 0, 0, {}
    function editor.validate(_, name)
        editor.validated = editor.validated + 1
        editor.validated_name = name
        return diagnostics
    end
    function editor.compile(_, name)
        editor.compiled = editor.compiled + 1
        return compile_answer
    end
    function editor.forget(_, key) editor.forgotten_keys[#editor.forgotten_keys + 1] = key end

    local binding, spec, state = graph_with(editor)
    spec.dispatch({ kind = "open_campaign", name = "stw" }, nil)
    spec.on_tick()
    return binding, spec, state, editor
end

function M.test_validate_surfaces_the_diagnostic_and_clicking_it_selects_the_node()
    -- SPEC: TurnInQuest(9) with no AcceptQuest(9) shows MISSING_ACCEPT naming the node, and
    -- clicking it selects that node. Both verbs used to answer "(not yet implemented)".
    local _, spec, state, editor = validating_graph({
        { severity = "error", code = "MISSING_ACCEPT",
          message = "TurnInQuest(9) has no AcceptQuest(9) in graph 'main'", node_id = TURNIN_ID },
    })

    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    T.assert_equal(editor.validated, 1, "POST .../validate went out")
    T.assert_equal(editor.validated_name, "stw", "for the open campaign")
    T.assert_equal(#state.diagnostics, 1, "and its answer is on the state")
    T.assert_equal(state.diagnostics[1].code, "MISSING_ACCEPT", "with the code")

    -- It renders as a row an operator can hit.
    local plan = GraphState.build_plan(state:build(), { x = 0, y = 0, w = 900, h = 600 })
    local row = nil
    for _, item in ipairs(plan.items) do
        if item.id == "diagnostic:1" then row = item end
    end
    T.assert_not_nil(row, "the diagnostic must be in the validation bar, not only on the state")
    T.assert_true(row.label:find("MISSING_ACCEPT", 1, true) ~= nil, row.label)

    local command = GraphState.reduce("diagnostic:1")
    T.assert_equal(command.kind, "select_diagnostic", "clicking it is a command")
    spec.dispatch(command, nil)
    T.assert_equal(state.selected_node, TURNIN_ID,
        "which selects the node the editor blamed -- a diagnostic that names a node and does not "
        .. "go to it is a label, not a link")
end

function M.test_a_clean_validate_is_a_different_answer_from_never_having_validated()
    local _, spec, state = validating_graph({})
    T.assert_nil(state.diagnostics, "nothing has been validated yet")

    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    T.assert_not_nil(state.diagnostics, "now it has")
    T.assert_equal(#state.diagnostics, 0, "and the editor found nothing wrong")

    local plan = GraphState.build_plan(state:build(), { x = 0, y = 0, w = 900, h = 600 })
    local said = false
    for _, item in ipairs(plan.items) do
        if item.kind == "text" and tostring(item.text):find("Validation passed", 1, true) then
            said = true
        end
    end
    T.assert_true(said, "and it says so, rather than looking identical to not having asked")
end

function M.test_validating_twice_asks_twice()
    local _, spec, _, editor = validating_graph({})

    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    T.assert_equal(editor.validated, 2,
        "validate is an ACTION: after an edit, the second click must reach the server rather than "
        .. "replay the verdict from before it")
    T.assert_true(#editor.forgotten_keys >= 2, "which means the remembered answer is dropped first")
end

function M.test_compile_reports_what_the_editor_actually_said()
    local _, spec, state, editor = validating_graph({}, {
        campaign_name = "stw", node_count = 1,
        message = "Campaign compile — full pipeline available in a later phase",
    })

    spec.dispatch({ kind = "compile_graph" }, nil)
    spec.on_tick()
    T.assert_equal(editor.compiled, 1, "POST .../compile went out")
    T.assert_true(tostring(state.compile_message):find("later phase", 1, true) ~= nil,
        "and the panel repeats the editor's own words rather than claiming a build happened: "
        .. tostring(state.compile_message))
end

function M.test_a_write_clears_the_previous_verdict_and_re_validates()
    -- F19-R1: validate runs on every save. The old verdict must go FIRST -- a clean bill left over
    -- a graph that has changed since is worse than no verdict, because it is believed.
    local _, spec, state, editor = validating_graph({
        { severity = "error", code = "MISSING_ACCEPT", message = "x", node_id = TURNIN_ID },
    })
    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    T.assert_equal(#state.diagnostics, 1, "a verdict is on screen")

    spec.dispatch({ kind = "show_add_node_menu" }, nil)
    T.assert_nil(state.diagnostics, "the write drops it immediately")

    spec.on_tick()   -- the graph comes back
    spec.on_tick()   -- and the re-validate armed by the write resolves
    T.assert_equal(editor.validated, 2, "the save re-validated without being asked")
end

function M.test_validate_with_no_campaign_open_is_refused_not_sent()
    local editor = fake_editor({ campaigns = {} })
    editor.validated = 0
    function editor.validate() editor.validated = editor.validated + 1 return {} end
    local _, spec, state = graph_with(editor)

    spec.dispatch({ kind = "validate_graph" }, nil)
    spec.on_tick()
    T.assert_equal(editor.validated, 0, "there is nothing to validate")
    T.assert_true(tostring(state.error):find("nothing to validate", 1, true) ~= nil,
        tostring(state.error))
end

-- ---- edit_intent (spec: Graph Node Editing) -------------------------------

local KILL_ID = "cccccccc-0000-4000-8000-00000000000c"

local function editing_graph()
    local editor = fake_editor({
        campaign = editor_campaign_doc("stw", "graph-1", {
            { id = KILL_ID, type = "questing.Kill",
              intent = { creature_entry = 567, count = 10, loot = false } },
        }),
    })
    editor.updates = {}
    function editor.update_node(_, campaign, node_id, node, graph_id)
        editor.updates[#editor.updates + 1] =
            { campaign = campaign, node_id = node_id, node = node, graph_id = graph_id }
        if editor.update_result ~= nil then return editor.update_result, editor.update_reason end
        return true
    end
    function editor.validate() return {} end
    function editor.forget() end

    local binding, spec, state = graph_with(editor)
    spec.dispatch({ kind = "open_campaign", name = "stw" }, nil)
    spec.on_tick()
    return binding, spec, state, editor
end

function M.test_editing_a_field_opens_a_real_box_and_writes_through_the_editor()
    -- obs #225: edit_intent answered "(open editor)" and returned ok, opening nothing.
    local _, spec, state, editor = editing_graph()
    state:select_node(KILL_ID)
    state:toggle_expand_node(KILL_ID)

    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "count" }, nil)
    T.assert_not_nil(state.editing, "the edit actually opens something")
    T.assert_equal(state.edit_input.value, "10", "seeded with what is there now")

    local plan = GraphState.build_plan(state:build(), { x = 0, y = 0, w = 900, h = 600 })
    local box = nil
    for _, item in ipairs(plan.items) do
        if item.kind == "text_input" and item.id == "edit_value" then box = item end
    end
    T.assert_not_nil(box, "and it is a typeable box on screen, not a state flag nobody can reach")
    T.assert_equal(box.model, state.edit_input, "carrying the state's buffer")

    state.edit_input.buffer = "12"
    spec.dispatch(GraphState.reduce("edit_value_submit"), nil)
    T.assert_equal(#editor.updates, 1, "Enter writes it")
    T.assert_equal(editor.updates[1].node_id, KILL_ID, "to the node being edited")
    T.assert_equal(editor.updates[1].graph_id, "graph-1", "in the graph the campaign has")
    T.assert_equal(editor.updates[1].node.intent.count, 12, "with the new value")
    T.assert_equal(editor.updates[1].node.intent.creature_entry, 567,
        "and every other field intact -- the route REPLACES the node, so a partial intent deletes "
        .. "the fields it omits")
end

function M.test_a_number_field_stays_a_number()
    local _, spec, state, editor = editing_graph()
    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "count" }, nil)
    state.edit_input.buffer = "12"
    spec.dispatch({ kind = "commit_intent" }, nil)

    T.assert_equal(type(editor.updates[1].node.intent.count), "number",
        "IntentValue is deserialized from the JSON type: a count sent as \"12\" arrives as Text "
        .. "rather than Int, and the resolver then reads a field of the wrong shape in silence")
end

function M.test_a_boolean_field_stays_a_boolean()
    local _, spec, state, editor = editing_graph()
    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "loot" }, nil)
    state.edit_input.buffer = "true"
    spec.dispatch({ kind = "commit_intent" }, nil)
    T.assert_equal(editor.updates[1].node.intent.loot, true, "and it is a boolean, not the string")
end

function M.test_a_value_of_the_wrong_type_is_refused_before_it_reaches_the_editor()
    local _, spec, state, editor = editing_graph()
    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "count" }, nil)
    state.edit_input.buffer = "twelve"

    local _, reason = spec.dispatch({ kind = "commit_intent" }, nil)
    T.assert_equal(#editor.updates, 0, "nothing was written")
    T.assert_true(tostring(reason):find("not a number", 1, true) ~= nil, tostring(reason))
    T.assert_not_nil(state.editing, "and the box stays open on the value that was rejected")
end

function M.test_escape_closes_the_editor_without_writing()
    local _, spec, state, editor = editing_graph()
    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "count" }, nil)
    state.edit_input.buffer = "99"

    spec.dispatch(GraphState.reduce("edit_value_cancel"), nil)
    T.assert_nil(state.editing, "the editor closed")
    T.assert_equal(#editor.updates, 0, "and nothing was written")
    T.assert_equal(state:node_by_id(KILL_ID).intent.count, 10, "the field is untouched")
end

function M.test_a_refused_edit_leaves_the_old_value_on_screen()
    local _, spec, state, editor = editing_graph()
    editor.update_result, editor.update_reason = false, "campaign is locked"
    spec.dispatch({ kind = "edit_intent", node_id = KILL_ID, field = "count" }, nil)
    state.edit_input.buffer = "12"

    spec.dispatch({ kind = "commit_intent" }, nil)
    T.assert_true(tostring(state.error):find("campaign is locked", 1, true) ~= nil,
        tostring(state.error))
    T.assert_equal(state:node_by_id(KILL_ID).intent.count, 10,
        "the local node is never patched: the copy worth believing is the one the editor answers "
        .. "with, and it refused")
end

function M.test_a_list_valued_field_refuses_to_open_a_one_line_editor()
    local editor = fake_editor({
        campaign = editor_campaign_doc("stw", "graph-1", {
            { id = "p1", type = "questing.Patrol", intent = { waypoints = {}, loop = false } },
        }),
    })
    local _, spec, state = graph_with(editor)
    spec.dispatch({ kind = "open_campaign", name = "stw" }, nil)
    spec.on_tick()

    spec.dispatch({ kind = "edit_intent", node_id = "p1", field = "waypoints" }, nil)
    T.assert_nil(state.editing,
        "typing over a list replaces a structure with a string the resolver cannot read")
    T.assert_true(tostring(state.error):find("cannot edit", 1, true) ~= nil, tostring(state.error))
end

function M.test_no_authoring_command_still_answers_not_yet_implemented()
    -- The placeholder strings from obs #225, gone from this panel for good.
    local handle = assert(io.open("sentinel/ui/ide_panels.lua", "r"))
    local source = handle:read("*a")
    handle:close()
    local explorer_half = source:match("function IdePanels%.new_explorer.-function IdePanels%.new_properties")
    T.assert_not_nil(explorer_half, "the Explorer binding must still be locatable in the source")
    -- Comments stripped first. The comment explaining WHY the placeholders are gone quotes the very
    -- string being banned, and an audit that fired on its own rationale would be untrue.
    explorer_half = explorer_half:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\n]*", " ")
    T.assert_nil(explorer_half:find("not yet implemented", 1, true),
        "the Explorer binding still carries a placeholder that reports success")

    -- The Graph binding's four: edit_intent, validate_graph, compile_graph, and the Add Node that
    -- inserted locally instead of writing.
    local graph_half = source:match("function IdePanels%.new_graph.-function IdePanels%.new_database")
    T.assert_not_nil(graph_half, "the Graph binding must still be locatable in the source")
    graph_half = graph_half:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\n]*", " ")
    T.assert_nil(graph_half:find("not yet implemented", 1, true),
        "the Graph binding still carries a placeholder that reports success")
    T.assert_nil(graph_half:find("(open editor)", 1, true),
        "edit_intent must open an editor rather than announce that it would")
end

return M
