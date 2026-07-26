-- tests/test_main_resolve_verbs.lua
-- ADR 09a W13: the host surface for resolve-and-run.
--
-- The module owning `resolve_recording` is only half the link. `_G.Sentinel` is the only surface an
-- operator has from outside the client (the debug bridge evaluates against it), so a verb the host
-- never exposes is reachable by nobody -- exactly the dead end recorder.lua was in before W12.
--
-- The menu buttons these verbs once had are gone: the IDE is the only UI surface now, and its
-- editor panel will call the verbs directly. The verbs therefore matter MORE than they did, not
-- less, which is why what remains here is pinned harder.
--
-- The menu construction site is measured rather than reviewed: Sylvannas forbids creating windows
-- and menu elements inside a render callback, and that failure happens in the injector, at runtime,
-- with the offline suite green. So this counts `core.menu.*` constructions per phase.
--
-- main.lua is a Sylvannas entry point with top-level `core.menu.*` / `core.register_on_*` calls, so
-- this file patches just enough of the shared `_G.core` mock to let `require("main")` load, then
-- restores it -- the same technique as tests/test_main_recording_verbs.lua.

local T = require("tests/test_util")

local M = {}

local CORE_KEYS = {
    "menu",
    "register_on_pre_tick_callback",
    "register_on_update_callback",
    "register_on_spell_cast_callback",
    "register_on_legit_spell_cast_callback",
    "register_on_render_callback",
    "register_on_render_window_callback",
    "register_on_render_menu_callback",
    "log",
    "log_error",
}

--- Boot main.lua against an instrumented `core` and a stub app, hand the fixture to `fn`, restore.
---@param opts table `{ questing = <table|false>, clicks = { [button_id] = true } }`
local function with_main(opts, fn)
    opts = opts or {}
    local saved_core = {}
    for _, key in ipairs(CORE_KEYS) do saved_core[key] = _G.core[key] end
    local saved_app_mod = package.loaded["runtime/app"]

    local env = { created = {}, phase = "load", clicks = opts.clicks or {}, published = nil }

    _G.core.menu = {
        tree_node = function()
            env.created[#env.created + 1] = { kind = "tree_node", phase = env.phase }
            return {
                render = function(_, _label, body) if body then body() end end,
                is_open = function() return true end,
            }
        end,
        button = function(id)
            env.created[#env.created + 1] = { kind = "button", id = id, phase = env.phase }
            return { render = function() return env.clicks[id] == true end }
        end,
    }

    local function noop_register(_cb) end
    _G.core.register_on_pre_tick_callback = noop_register
    _G.core.register_on_update_callback = noop_register
    _G.core.register_on_spell_cast_callback = noop_register
    _G.core.register_on_legit_spell_cast_callback = noop_register
    _G.core.register_on_render_callback = noop_register
    _G.core.register_on_render_window_callback = noop_register
    _G.core.register_on_render_menu_callback = function(cb) env.render_menu = cb end
    _G.core.log = function() end
    _G.core.log_error = function() end

    -- The stub omits `get_event_bus` on purpose, which makes ensure_diagnostics_wired return
    -- early; it is not under test here.
    local questing_wrapper = nil
    if opts.questing ~= false then
        questing_wrapper = { _questing = opts.questing }
    end
    package.loaded["runtime/app"] = {
        new = function()
            return {
                initialize = function() end,
                publish_api = function(_, host) env.published = host end,
                get_module = function(_, name)
                    if name == "questing" then return questing_wrapper end
                    return nil
                end,
            }
        end,
    }
    package.loaded["main"] = nil

    local ok, err = pcall(function()
        local main_mod = require("main")
        -- `_G.Sentinel` appears on the first successful init, not at load (main.lua's
        -- publish_surface note), so the surface has to be forced into existence here.
        T.assert_true(main_mod._ensure_initialized_for_test(), "the stub app must initialise")
        T.assert_not_nil(env.published, "main.lua must publish its host verbs on a successful init")
        fn(env)
    end)

    package.loaded["main"] = nil
    package.loaded["runtime/app"] = saved_app_mod
    for _, key in ipairs(CORE_KEYS) do _G.core[key] = saved_core[key] end

    if not ok then error(err, 0) end
end

--- A questing module reduced to the verbs this surface forwards to, so the host wiring is what
--- fails here and never the module behind it (that is test_resolve_control.lua's job).
local function stub_questing()
    local stub = { calls = {} }
    function stub:resolve_recording(name)
        self.calls[#self.calls + 1] = { verb = "resolve_recording", name = name }
        return { ok = true, status = "resolved", plan_path = "sentinel/data/profiles/quests/x.json",
                 diagnostics = { count = 0, errors = 0, warnings = 0, messages = {} } }
    end
    function stub:run_plan(name)
        self.calls[#self.calls + 1] = { verb = "run_plan", name = name }
        return { ok = true, status = "running", plan_path = "sentinel/data/profiles/quests/x.json" }
    end
    function stub:resolve_status()
        self.calls[#self.calls + 1] = { verb = "resolve_status" }
        return { status = "idle" }
    end
    return stub
end

local function created_in(env, phase)
    local out = {}
    for _, entry in ipairs(env.created) do
        if entry.phase == phase then out[#out + 1] = entry end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The verbs
-- ---------------------------------------------------------------------------

function M.test_the_resolve_and_run_verbs_reach_the_published_surface()
    with_main({ questing = stub_questing() }, function(env)
        for _, verb in ipairs({ "resolve_recording", "resolve_status", "run_plan" }) do
            T.assert_true(type(env.published[verb]) == "function",
                "host verb '" .. verb .. "' must reach _G.Sentinel -- it is the only surface an "
                .. "operator has from outside the client")
        end
        -- The surface W12 and the kernel already published must survive the addition.
        for _, verb in ipairs({ "start_recording", "stop_recording", "save_recording",
                                "recording_status", "combat", "questing", "reload" }) do
            T.assert_true(type(env.published[verb]) == "function",
                "host verb '" .. verb .. "' must still be published")
        end
    end)
end

function M.test_the_verbs_forward_to_the_questing_module()
    local questing = stub_questing()
    with_main({ questing = questing }, function(env)
        local resolved = env.published.resolve_recording("Northshire")
        T.assert_true(resolved.ok, "the host verb must return the module's own answer")
        T.assert_equal(questing.calls[1].verb, "resolve_recording", "and actually call it")
        T.assert_equal(questing.calls[1].name, "Northshire", "with the operator's argument")

        local running = env.published.run_plan("northshire")
        T.assert_true(running.ok, "run must forward too")
        T.assert_equal(questing.calls[2].name, "northshire", "with its argument intact")

        T.assert_equal(env.published.resolve_status().status, "idle", "and status must be pollable")
    end)
end

--- A verb that throws inside a debug-bridge eval returns nothing at all to the operator, so an
--- absent questing module has to be an answer rather than an error.
function M.test_the_verbs_degrade_to_a_reason_when_the_questing_module_is_absent()
    with_main({ questing = false }, function(env)
        for _, verb in ipairs({ "resolve_recording", "run_plan" }) do
            local ok, result = pcall(function() return env.published[verb]("Northshire") end)
            T.assert_true(ok, verb .. " must answer instead of throwing")
            T.assert_false(result.ok, verb .. " cannot succeed without the questing module")
            T.assert_true(type(result.reason) == "string" and result.reason ~= "",
                verb .. " must name the reason instead of answering a bare false")
        end

        local ok, status = pcall(function() return env.published.resolve_status() end)
        T.assert_true(ok, "status must still answer, not throw")
        T.assert_true(type(status.status) == "string", "with a status a human can read")
    end)
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------

function M.test_no_menu_element_is_constructed_inside_the_render_callback()
    with_main({ questing = stub_questing() }, function(env)
        T.assert_true(#created_in(env, "load") > 0,
            "menu elements must be constructed at module scope")
        T.assert_not_nil(env.render_menu, "main.lua must register a render-menu callback")

        env.phase = "render"
        for _ = 1, 5 do env.render_menu() end

        local during_render = created_in(env, "render")
        T.assert_equal(#during_render, 0,
            "Sylvannas forbids creating menu elements inside a render callback; "
            .. tostring(#during_render) .. " were created there")
    end)
end

--- The complement of the menu-strip: not one menu click may reach the network. `resolve_recording`
--- is the only verb here that leaves the machine, and it now has no button at all -- so a frame of
--- menu rendering must call nothing on the questing module.
function M.test_rendering_the_menu_drives_no_questing_verb()
    local questing = stub_questing()
    with_main({ questing = questing }, function(env)
        env.phase = "render"
        for _ = 1, 5 do env.render_menu() end
        T.assert_equal(#questing.calls, 0,
            "the menu is one door to the IDE; nothing on it may resolve, run, or reach the "
            .. "network on a frame the operator did not ask for")
    end)
end

return M
