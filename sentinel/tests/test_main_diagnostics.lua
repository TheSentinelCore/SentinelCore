-- tests/test_main_diagnostics.lua
-- C4: the EventBus was ~85% write-only -- module:fault (Wave-1 per-module tick isolation),
-- questing:error (profile-load failure), and module lifecycle/shutdown state changes all
-- published into the void with zero subscribers, so three separate P0/P1 failure modes had no
-- observable signal at all. main.lua now wires ONE thin diagnostics sink for exactly these
-- events (see wire_diagnostics in sentinel/main.lua). This test proves the sink actually
-- observes published events and logs them -- not just that the subscribe call compiles.
--
-- main.lua is a Sylvannas entry point with top-level `core.menu.*` / `core.register_on_*` calls
-- that no other offline suite exercises, so this file locally patches just enough of the shared
-- `_G.core` mock to let `require("main")` load, then restores it. No shared harness file is
-- modified. wire_diagnostics itself is exercised directly against a real EventBus (no
-- SentinelApp/IziBridge boot needed -- IziBridge requires the injector-only `common/izi_sdk`,
-- which does not exist offline).

local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

--- Install the minimal core.menu / core.register_on_* surface main.lua touches at load time,
--- run `fn()`, then restore whatever was there before.
local function with_main_loadable(fn)
    local saved = {
        menu = _G.core.menu,
        register_on_pre_tick_callback = _G.core.register_on_pre_tick_callback,
        register_on_update_callback = _G.core.register_on_update_callback,
        register_on_spell_cast_callback = _G.core.register_on_spell_cast_callback,
        register_on_legit_spell_cast_callback = _G.core.register_on_legit_spell_cast_callback,
        register_on_render_callback = _G.core.register_on_render_callback,
        register_on_render_window_callback = _G.core.register_on_render_window_callback,
        register_on_render_menu_callback = _G.core.register_on_render_menu_callback,
    }

    local noop_widget = { render = function() return false end }
    _G.core.menu = {
        tree_node = function() return { render = function(_, _label, body) if body then body() end end } end,
        button = function() return noop_widget end,
    }
    local function noop_register(_cb) end
    _G.core.register_on_pre_tick_callback = noop_register
    _G.core.register_on_update_callback = noop_register
    _G.core.register_on_spell_cast_callback = noop_register
    _G.core.register_on_legit_spell_cast_callback = noop_register
    _G.core.register_on_render_callback = noop_register
    _G.core.register_on_render_window_callback = noop_register
    _G.core.register_on_render_menu_callback = noop_register

    local ok, err = pcall(fn)

    _G.core.menu = saved.menu
    _G.core.register_on_pre_tick_callback = saved.register_on_pre_tick_callback
    _G.core.register_on_update_callback = saved.register_on_update_callback
    _G.core.register_on_spell_cast_callback = saved.register_on_spell_cast_callback
    _G.core.register_on_legit_spell_cast_callback = saved.register_on_legit_spell_cast_callback
    _G.core.register_on_render_callback = saved.register_on_render_callback
    _G.core.register_on_render_window_callback = saved.register_on_render_window_callback
    _G.core.register_on_render_menu_callback = saved.register_on_render_menu_callback

    if not ok then error(err, 0) end
end

--- Load main.lua (fresh each time so `_diagnostics_subscribed` state doesn't leak between
--- assertions) and return its exported `_wire_diagnostics_for_test` hook.
local function load_wire_diagnostics()
    package.loaded["main"] = nil
    local main_mod = require("main")
    T.assert_true(type(main_mod._wire_diagnostics_for_test) == "function",
        "main.lua must export wire_diagnostics for offline testing")
    return main_mod._wire_diagnostics_for_test
end

--- Capture core.log_error / core.log calls made during `fn()`.
local function capture_logs(fn)
    local errors, infos = {}, {}
    local saved_error, saved_log = _G.core.log_error, _G.core.log
    _G.core.log_error = function(msg) errors[#errors + 1] = msg end
    _G.core.log = function(msg) infos[#infos + 1] = msg end
    local ok, err = pcall(fn)
    _G.core.log_error = saved_error
    _G.core.log = saved_log
    if not ok then error(err, 0) end
    return errors, infos
end

local function any_contains(list, needle)
    for _, msg in ipairs(list) do
        if tostring(msg):find(needle, 1, true) then return true end
    end
    return false
end

function M.test_module_fault_is_observed_by_the_diagnostics_sink()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)

        local errors = capture_logs(function()
            bus:publish("module:fault", { module = "combat", error = "boom" })
        end)

        T.assert_true(any_contains(errors, "module:fault"), "module:fault must be logged")
        T.assert_true(any_contains(errors, "combat"), "the faulting module name must be in the log line")
        T.assert_true(any_contains(errors, "boom"), "the fault error must be in the log line")
    end)
end

--- `ModuleRegistry:_report_init_failure` tags its fault `phase = "init"` and states the reason in
--- so many words: "so the two are distinguishable at the receiving end". The sink WAS the
--- receiving end, and it formatted module/count/error only -- so a module that died at boot and a
--- module that faulted once on a tick produced byte-identical log lines, and the field's stated
--- purpose was false.
---
--- The distinction is not decoration. A boot death is terminal: the module is set SHUTDOWN and
--- `initialize_module` refuses to reinitialise it, so it stays dead for the life of the client and
--- the operator must reload. A tick fault is transient: the streak resets on the next clean tick.
--- "combat count=1" told the operator nothing about which of those two they were reading.
---
--- WHAT THIS CANNOT SEE: it proves the two lines DIFFER and each names its phase. It does not
--- prove an operator reading the log understands what to do about it, and it says nothing about
--- faults published by anything other than the registry.
function M.test_module_fault_log_line_distinguishes_a_boot_death_from_a_tick_fault()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)

        -- Identical in every field the sink used to read. Only `phase` differs.
        local init_errors = capture_logs(function()
            bus:publish("module:fault",
                { module = "combat", count = 1, error = "boom", phase = "init" })
        end)
        local tick_errors = capture_logs(function()
            bus:publish("module:fault",
                { module = "combat", count = 1, error = "boom", phase = "tick" })
        end)

        T.assert_equal(#init_errors, 1, "one fault, one line")
        T.assert_equal(#tick_errors, 1, "one fault, one line")
        T.assert_true(init_errors[1] ~= tick_errors[1],
            "a boot death and a tick fault must not log the same bytes: got " .. tostring(init_errors[1]))
        T.assert_true(any_contains(init_errors, "init"), "the boot line must name the init phase")
        T.assert_true(any_contains(tick_errors, "tick"), "the tick line must name the tick phase")
    end)
end

--- A publisher that omits `phase` must be reported as UNKNOWN, never silently folded into either
--- bucket. Defaulting an absent phase to "tick" would make the cheaper reading the default one --
--- exactly the direction a boot death must never be rounded towards.
function M.test_a_fault_without_a_phase_is_reported_as_unknown()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)

        local errors = capture_logs(function()
            bus:publish("module:fault", { module = "combat", error = "boom" })
        end)
        T.assert_true(any_contains(errors, "unknown"),
            "an unphased fault must read unknown, not be rounded to the milder phase: "
            .. tostring(errors[1]))
        T.assert_false(any_contains(errors, "phase=tick"), "and must not claim it was a tick")
        T.assert_false(any_contains(errors, "phase=init"), "nor claim it was an init")
    end)
end

function M.test_questing_error_is_observed_by_the_diagnostics_sink()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)

        local errors = capture_logs(function()
            bus:publish("questing:error", { error = "missing profile file" })
        end)

        T.assert_true(any_contains(errors, "questing:error"), "questing:error must be logged")
        T.assert_true(any_contains(errors, "missing profile file"), "the underlying error must be in the log line")
    end)
end

function M.test_module_state_changed_is_observed_by_the_diagnostics_sink()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)

        local errors, infos = capture_logs(function()
            bus:publish("module_state_changed", { module = "questing", state = "shutdown" })
        end)
        T.assert_equal(#errors, 0, "a state change is not itself an error")
        T.assert_true(any_contains(infos, "module_state_changed"), "module_state_changed must be logged")
        T.assert_true(any_contains(infos, "shutdown"), "the new state must be in the log line")
    end)
end

--- A subscriber with zero observers is exactly the C4 failure mode: prove the sink is
--- reachable through main.lua's normal wiring path, not just callable in isolation.
function M.test_wire_diagnostics_is_a_real_subscriber_not_a_noop()
    with_main_loadable(function()
        local wire_diagnostics = load_wire_diagnostics()
        local bus = EventBus:new()
        wire_diagnostics(bus)
        T.assert_true(bus._subs["module:fault"] ~= nil and #bus._subs["module:fault"] > 0,
            "wire_diagnostics must actually subscribe to module:fault")
        T.assert_true(bus._subs["questing:error"] ~= nil and #bus._subs["questing:error"] > 0,
            "wire_diagnostics must actually subscribe to questing:error")
    end)
end

--- F1: a failed `ensure_initialized()` used to `clear_module_cache()` (nil out ~50
--- `package.loaded` entries and force a full re-`require`) on EVERY call, since `initialized`
--- never flips true on failure. Prove that repeated calls after one failure clear the cache
--- at most once, not once per call.
function M.test_ensure_initialized_does_not_reclear_cache_every_frame_after_a_failure()
    with_main_loadable(function()
        -- Force SentinelApp:initialize() to throw so ensure_initialized() keeps failing,
        -- without needing the real (injector-only) module tree to boot successfully.
        local saved_app_mod = package.loaded["runtime/app"]
        package.loaded["runtime/app"] = {
            new = function()
                return {
                    initialize = function()
                        error("forced init failure for F1 regression test")
                    end,
                }
            end,
        }
        package.loaded["main"] = nil

        local ok, err = pcall(function()
            local main_mod = require("main")
            T.assert_true(type(main_mod._ensure_initialized_for_test) == "function",
                "main.lua must export ensure_initialized for offline testing")
            T.assert_true(type(main_mod._cache_clear_count_for_test) == "function",
                "main.lua must export the cache-clear counter for offline testing")

            capture_logs(function()
                for _ = 1, 10 do
                    local initialized_ok = main_mod._ensure_initialized_for_test()
                    T.assert_false(initialized_ok, "forced failure must keep reporting not-initialized")
                end
            end)

            T.assert_equal(main_mod._cache_clear_count_for_test(), 1,
                "the module cache must be cleared at most once across repeated failed retries (F1)")
        end)

        package.loaded["runtime/app"] = saved_app_mod
        package.loaded["main"] = nil

        if not ok then error(err, 0) end
    end)
end

--- The other init test drives the FAILURE path, so nothing here ever exercised publication. This
--- one drives the success path with the same stub technique and asserts the host seam: main.lua
--- must hand its verbs to `publish_api`, and must NOT hand over the two accessors that were deleted
--- for duplicating `Sentinel.events` / `Sentinel.state`.
---
--- The stub deliberately omits `get_event_bus`, which makes both wiring helpers return early --
--- this test is about publication, not about diagnostics wiring.
function M.test_successful_init_publishes_the_surface_with_host_verbs()
    with_main_loadable(function()
        local saved_app_mod = package.loaded["runtime/app"]
        local published_host = nil
        package.loaded["runtime/app"] = {
            new = function()
                return {
                    initialize = function() end,
                    publish_api = function(_, host) published_host = host end,
                }
            end,
        }
        package.loaded["main"] = nil

        local ok, err = pcall(function()
            local main_mod = require("main")
            capture_logs(function()
                T.assert_true(main_mod._ensure_initialized_for_test(), "init must succeed")
            end)

            T.assert_not_nil(published_host, "a successful init must publish the surface")
            for _, verb in ipairs({ "combat", "questing", "reload", "toggle_ide", "ide" }) do
                T.assert_true(type(published_host[verb]) == "function",
                    "host verb '" .. verb .. "' must reach the surface")
            end
            T.assert_nil(published_host.get_event_bus, "deleted: duplicated Sentinel.events")
            T.assert_nil(published_host.get_blackboard, "deleted: duplicated Sentinel.state")
            T.assert_nil(published_host.app,
                "app resolves through a kernel live getter, not a host verb")
        end)

        package.loaded["runtime/app"] = saved_app_mod
        package.loaded["main"] = nil

        if not ok then error(err, 0) end
    end)
end

--- The host half of the QueryClient seam (spec: QueryClient Wiring at Install).
---
--- `ide_panels.lua` can be exhaustively tested with a client handed to it and still ship an IDE
--- that never fetches anything, because the party that decides whether a client exists is main.lua
--- -- and main.lua installed the panels with `{ questing = ... }` and nothing else for the whole of
--- the last cycle. The only test that can see that is one that loads the real entry point and reads
--- what it actually passed.
function M.test_main_installs_the_ide_panels_with_a_live_query_client()
    with_main_loadable(function()
        local real_panels = require("ui/ide_panels")
        local saved = package.loaded["ui/ide_panels"]

        local captured = nil
        package.loaded["ui/ide_panels"] = setmetatable({
            install = function(shell, deps)
                captured = deps
                return real_panels.install(shell, deps)
            end,
        }, { __index = real_panels })

        package.loaded["main"] = nil
        local ok, err = pcall(require, "main")

        package.loaded["ui/ide_panels"] = saved
        package.loaded["main"] = nil
        if not ok then error(err, 0) end

        T.assert_not_nil(captured, "main.lua must install the IDE panels")

        local qc = captured.query_client
        T.assert_not_nil(qc,
            "main.lua must pass a query_client; without one every data panel is decorative")
        T.assert_equal(type(qc), "table",
            "the contract is a client TABLE, not a resolver function -- every binding call site "
            .. "already writes `qc:get_npc(entry)`")
        for _, verb in ipairs({ "get_quest", "get_npc", "get_vendor", "get_object",
                                "search_quests", "get_quest_chain", "get_quest_objectives" }) do
            T.assert_equal(type(qc[verb]), "function",
                "the client main.lua supplies must answer " .. verb)
        end

        -- PR1 deliberately left this half out rather than pass a dep that resolved to nil, because
        -- `shared/editor_client.lua` did not exist yet and a nil-valued dependency is the silent
        -- contract this change removes. It exists now, so the omission is the defect again.
        local ec = captured.editor_client
        T.assert_not_nil(ec,
            "main.lua must pass an editor_client; without one the Graph panel cannot create, open, "
            .. "validate or compile anything, which is where the last cycle left it")
        T.assert_equal(type(ec), "table", "a client TABLE, same contract as the query client")
        T.assert_true(ec ~= qc,
            "and a SEPARATE client: the QueryServer serves static game data that caches forever, "
            .. "while the editor's campaigns change because this client changes them")
        for _, verb in ipairs({ "list_campaigns", "create_campaign", "load_campaign", "save_graph",
                                "add_nodes", "update_node", "validate", "compile" }) do
            T.assert_equal(type(ec[verb]), "function",
                "the editor client main.lua supplies must answer " .. verb)
        end
    end)
end

local tests = {
    test_main_installs_the_ide_panels_with_a_live_query_client =
        M.test_main_installs_the_ide_panels_with_a_live_query_client,
    test_successful_init_publishes_the_surface_with_host_verbs = M.test_successful_init_publishes_the_surface_with_host_verbs,
    test_module_fault_is_observed_by_the_diagnostics_sink = M.test_module_fault_is_observed_by_the_diagnostics_sink,
    test_module_fault_log_line_distinguishes_a_boot_death_from_a_tick_fault =
        M.test_module_fault_log_line_distinguishes_a_boot_death_from_a_tick_fault,
    test_a_fault_without_a_phase_is_reported_as_unknown =
        M.test_a_fault_without_a_phase_is_reported_as_unknown,
    test_questing_error_is_observed_by_the_diagnostics_sink = M.test_questing_error_is_observed_by_the_diagnostics_sink,
    test_module_state_changed_is_observed_by_the_diagnostics_sink = M.test_module_state_changed_is_observed_by_the_diagnostics_sink,
    test_wire_diagnostics_is_a_real_subscriber_not_a_noop = M.test_wire_diagnostics_is_a_real_subscriber_not_a_noop,
    test_ensure_initialized_does_not_reclear_cache_every_frame_after_a_failure = M.test_ensure_initialized_does_not_reclear_cache_every_frame_after_a_failure,
}

function M.run()
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, err = pcall(tests[name])
        if not ok then
            error(name .. ": " .. tostring(err), 0)
        end
    end
end

M.tests = tests
return M
