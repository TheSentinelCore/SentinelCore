-- tests/test_main_recording_verbs.lua
-- ADR 09a W12: the host surface for Recording Mode.
--
-- Two separate things are pinned here, and they fail in two different places.
--
--   1. THE VERBS. `_G.Sentinel` is the only surface an operator has from outside the client (the
--      debug bridge evaluates against it). A recorder the module owns but the host never exposes is
--      reachable by nobody, which is the same dead end recorder.lua was already in.
--   2. THE MENU CONSTRUCTION SITE. Sylvannas forbids creating windows and menu elements inside a
--      render callback -- it fails in the injector, at runtime, with the offline suite green. So the
--      test does not read the source: it counts `core.menu.*` constructions and asserts that
--      invoking the registered render-menu callback performs ZERO of them.
--
-- The menu itself is now ONE entry -- "Open IDE" -- and that count is pinned here too. The
-- Recording buttons that used to live beside it were deleted; the verbs behind them were not.
--
-- main.lua is a Sylvannas entry point with top-level `core.menu.*` / `core.register_on_*` calls, so
-- this file patches just enough of the shared `_G.core` mock to let `require("main")` load, then
-- restores it -- the same technique as tests/test_main_diagnostics.lua, no shared harness edited.

local EventBus = require("core/event_bus")
local Blackboard = require("core/blackboard")
local QuestingModule = require("modules/questing/module")
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

--- Boot main.lua against an instrumented `core` and a stub app, hand the fixture to `fn`, restore
--- everything afterwards.
---
--- `env.created` is the whole point of the fixture: every `core.menu.*` construction is recorded
--- together with the PHASE it happened in, so "constructed at module scope, only rendered in the
--- callback" becomes an assertion rather than a code-review promise.
---@param opts table `{ questing = <QuestingModule|false>, clicks = { [button_id] = true } }`
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

    -- The stub deliberately omits `get_event_bus`, which makes ensure_diagnostics_wired return
    -- early. It is not under test here (tests/test_main_diagnostics.lua owns it).
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

local function new_questing()
    return QuestingModule:new(Blackboard:new(), EventBus:new())
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

function M.test_the_recording_verbs_reach_the_published_surface()
    with_main({ questing = new_questing() }, function(env)
        for _, verb in ipairs({ "start_recording", "stop_recording", "recording_status", "save_recording" }) do
            T.assert_true(type(env.published[verb]) == "function",
                "host verb '" .. verb .. "' must reach _G.Sentinel -- it is the only surface an "
                .. "operator has from outside the client")
        end
        -- The pre-existing surface must survive the addition.
        for _, verb in ipairs({ "combat", "questing", "reload", "toggle_ide", "ide" }) do
            T.assert_true(type(env.published[verb]) == "function",
                "host verb '" .. verb .. "' must still be published")
        end
    end)
end

--- Stripping the menu down to the IDE deleted the BUTTONS, never the verbs. These are the
--- programmatic surface the IDE's editor panel will call and, today, the only way to drive
--- recording from the debug bridge -- a verb removed alongside its button would put Recording Mode
--- straight back in the dead end it was in before W12.
function M.test_stripping_the_menu_left_every_verb_reachable()
    with_main({ questing = new_questing() }, function(env)
        for _, verb in ipairs({
            "start_recording", "stop_recording", "recording_status", "save_recording",
            "resolve_recording", "resolve_status", "run_plan", "toggle_ide", "ide",
        }) do
            T.assert_true(type(env.published[verb]) == "function",
                "host verb '" .. verb .. "' must survive the menu strip; the buttons went, the "
                .. "programmatic surface did not")
        end
    end)
end

--- Everything an operator can do before they have started anything. None of it may throw, and none
--- of it may answer a bare `false` where a reason is what makes the failure actionable over a
--- one-shot debug-bridge eval.
function M.test_the_verbs_answer_with_a_reason_when_no_recording_is_in_progress()
    with_main({ questing = new_questing() }, function(env)
        local status = env.published.recording_status()
        T.assert_false(status.recording, "nothing is recording yet")

        local stopped = env.published.stop_recording()
        T.assert_false(stopped.ok, "there is nothing to stop")
        T.assert_true(type(stopped.reason) == "string" and stopped.reason ~= "",
            "stop must say why it did nothing")

        local saved = env.published.save_recording()
        T.assert_false(saved.ok, "there is nothing to save")
        T.assert_true(type(saved.reason) == "string" and saved.reason ~= "",
            "save must say why it did nothing")
    end)
end

function M.test_starting_and_stopping_through_the_host_verbs_drives_the_module()
    with_main({ questing = new_questing() }, function(env)
        local started = env.published.start_recording("Northshire")
        T.assert_true(started.ok, "the host verb must actually start the recording")
        T.assert_equal(started.name, "Northshire", "under the name the operator supplied")
        T.assert_true(env.published.recording_status().recording, "and status must agree")

        local stopped = env.published.stop_recording()
        T.assert_true(stopped.ok, "and stop it again")
        T.assert_false(env.published.recording_status().recording, "leaving the observer idle")
    end)
end

--- A verb that throws inside a debug-bridge eval returns nothing at all to the operator, so an
--- absent questing module has to be an answer rather than an error.
function M.test_the_verbs_degrade_to_a_reason_when_the_questing_module_is_absent()
    with_main({ questing = false }, function(env)
        for _, verb in ipairs({ "start_recording", "stop_recording", "save_recording" }) do
            local result = env.published[verb]("Northshire")
            T.assert_false(result.ok, verb .. " cannot succeed without the questing module")
            T.assert_true(type(result.reason) == "string" and result.reason ~= "",
                verb .. " must name the reason instead of throwing")
        end
        T.assert_false(env.published.recording_status().recording,
            "status must still answer, not throw")
    end)
end

-- ---------------------------------------------------------------------------
-- The menu
-- ---------------------------------------------------------------------------

--- The Sylvannas constraint, as a measurement. A `core.menu.button` created inside the render
--- callback fails in the injector and nowhere else -- there is no offline signal for it unless the
--- construction site is counted.
function M.test_no_menu_element_is_constructed_inside_the_render_callback()
    with_main({ questing = new_questing() }, function(env)
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

local function menu_button_ids(env)
    local ids = {}
    for _, entry in ipairs(env.created) do
        if entry.kind == "button" then ids[#ids + 1] = entry.id end
    end
    return ids
end

--- The IDE is the only UI surface now, so the menu carries exactly one door and nothing else.
--- Counted rather than reviewed: a stray button left behind is a control that looks supported,
--- competes with the IDE for the same job, and drifts out of step with it.
function M.test_the_menu_offers_exactly_one_entry()
    with_main({ questing = new_questing() }, function(env)
        local ids = menu_button_ids(env)
        T.assert_equal(#ids, 1,
            "the menu must carry one entry; found: " .. table.concat(ids, ", "))
        T.assert_true(ids[1]:find("ide", 1, true) ~= nil,
            "and it must be the IDE's, not a leftover")
    end)
end

--- Present is not wired, and here that distinction is the whole safety net: the IDE keybind ships
--- deliberately UNBOUND so it cannot steal a movement key, so this button is the only way into the
--- IDE. A menu entry whose click path called nothing would orphan the entire UI -- exactly how
--- Recording Mode became dead code before W12 wired it.
function M.test_the_menu_entry_actually_opens_the_ide()
    local ide_id = nil
    with_main({ questing = new_questing() }, function(env)
        ide_id = menu_button_ids(env)[1]
    end)
    T.assert_not_nil(ide_id, "there must be a button to press")

    with_main({ questing = new_questing(), clicks = { [ide_id] = true } }, function(env)
        T.assert_false(env.published.ide():is_visible(), "the IDE starts closed")
        env.phase = "render"
        env.render_menu()
        T.assert_true(env.published.ide():is_visible(),
            "pressing the only menu entry must open the IDE; the keybind is unbound, so nothing "
            .. "else can")
    end)
end

return M
