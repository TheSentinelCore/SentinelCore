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
            for _, verb in ipairs({ "combat", "questing", "reload", "toggle_quest_editor" }) do
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

local tests = {
    test_successful_init_publishes_the_surface_with_host_verbs = M.test_successful_init_publishes_the_surface_with_host_verbs,
    test_module_fault_is_observed_by_the_diagnostics_sink = M.test_module_fault_is_observed_by_the_diagnostics_sink,
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
