-- tests/runtime/test_app_tick.lua
-- SentinelApp:on_update must drive every registered module.
--
-- Proven live 2026-07-23: no module had ever been ticked.
--
--   app._combat == _G.Sentinel.combat()  -- the registry's CombatModule WRAPPER
--   type(app._combat.update)     -> nil       (the wrapper exposes tick/init)
--   type(app._combat.tick)       -> function
--   type(app._combat.initialize) -> nil       (the wrapper exposes init)
--
-- on_update guarded on `self._combat.update`, which is nil on the wrapper, so the
-- combat block never ran; and registry:tick_all was never called at all, so the
-- questing module never ran either. Symptom: questing engages combat, the state
-- machine sits at ENGAGING forever, and nothing is ever cast. system.now_ms kept
-- advancing (SensorHub refreshes directly in on_update), which made the loop look
-- alive while every module was frozen.

local SentinelApp = require("runtime/app")
local T = require("tests/test_util")

local M = {}

--- Build an app instance THROUGH the real SentinelApp:new().
---
--- This used to hand-build the app with `setmetatable({}, SentinelApp)` because new()
--- constructed an IziBridge, which did an unguarded `require("common/izi_sdk")` — an
--- injector-only module — so the composition root could not be constructed offline at all.
--- ADR 08 §11.6 called that out as testability debt: "the file that encodes the kernel's
--- boot contract is asserted by nobody." Phase 1 guarded the require
--- (integrations/izi_bridge.lua), so the real thing is now reachable from a test and this
--- helper exercises the ACTUAL wiring — scheduler included — rather than a replica of it.
---
--- Collaborators are still swapped for recording stubs, which works because every kernel
--- stage handler reads its collaborator off `self` at CALL time rather than capturing it
--- at registration (see SentinelApp:_register_kernel_stages).
local function make_app(registry)
    local app = SentinelApp:new()
    app._registry = registry
    app._sensor_hub = { refresh = function() end, shutdown = function() end }
    app._callback_bridge = { on_update = function() end, on_pre_tick = function() end }
    app._nav_adapter = { poll = function() end }
    return app
end

-- ---------------------------------------------------------------------------
-- Which unit does "target" mean? (ADR 08 §13.1 item 19)
-- ---------------------------------------------------------------------------
-- The ADR recorded this as a hazard for Phase 1b's snapshot work. Converting the frost cast path
-- onto intents (Phase 4c D4) made it LIVE, because the executor resolves the symbolic reference
-- `"target"` and the rotation does not.
--
-- The rotation acts on `combat.target`, falling back to `player.target` -- that is what
-- `frost_support.player_and_target` returns and what every action in the profile aims at. The
-- executor's fallback, with `unit_target` unwired, is `player:get_target()` -- the CLIENT's target.
-- They usually agree. They are not guaranteed to: the combat module selects a target before it has
-- been set on the client, and it holds the selection across a tick where the client's is cleared.
--
-- With `unit_target` unset in production, every converted cast would have silently aimed at the
-- client's target instead of the rotation's. Nothing would fail; the character would just fight the
-- wrong mob. So the composition root wires the SAME resolution the rotation uses.

function M.test_the_app_resolves_target_the_way_the_rotation_does()
    local app = SentinelApp:new()
    local bb = app:get_blackboard()
    local combat_target = { id = "the-mob-the-rotation-chose" }
    local client_target = { id = "the-mob-the-client-has" }

    bb:set("player.target", client_target)
    bb:set("combat.target", combat_target)
    T.assert_true(app:selected_target() == combat_target,
        "combat.target is the rotation's selection and must win")

    bb:set("combat.target", nil)
    T.assert_true(app:selected_target() == client_target,
        "and player.target is the documented fallback, not a second authority")
end

function M.test_the_app_resolves_no_target_to_nil_rather_than_guessing()
    local app = SentinelApp:new()
    T.assert_nil(app:selected_target(),
        "no selection must resolve to nil so the gate refuses, never to a guessed unit")
end

--- THE CALLABLE, AND ONLY THE CALLABLE. Renamed in Phase 4d D4, because the old name --
--- `test_the_cast_executor_is_wired_to_the_apps_target_resolution` -- claimed something this test
--- has never been able to observe.
---
--- What it checks is that `unit_target_resolver()` returns a callable that ignores the argument the
--- executor passes it (the player) and answers with the app's own selection. That is a real
--- property and worth pinning: the executor calls `deps.unit_target(player)`, so a resolver that
--- read its argument instead of the blackboard would aim every symbolic cast at the client again.
---
--- WHAT IT CANNOT SEE, MEASURED RATHER THAN ASSUMED: whether the resolver is HANDED TO
--- `Executors.install` at all. Comment out `unit_target = o:unit_target_resolver()` in
--- `runtime/app.lua` and this test still passes -- it never touches the installed deps. The wiring
--- itself is pinned at the SDK boundary, one packet at a time, by
--- `tests/integration/test_kernel_end_to_end.lua`'s
--- `test_a_symbolic_cast_commits_at_the_rotations_unit_not_the_clients`, which goes red under
--- exactly that edit. A correct `selected_target` the executors never receive is the same bug with
--- an extra step, and this file is not where that gets caught.
---
--- The dead `add_gate("probe", ...)` block that used to sit here went with the rename. It captured
--- an intent into a local nothing ever read, which made the test LOOK as though it observed a
--- commit; it observed nothing.
function M.test_the_target_resolver_answers_with_the_apps_own_selection()
    local app = SentinelApp:new()
    local bb = app:get_blackboard()
    local chosen = { id = "chosen" }
    local a_different_unit = { id = "the-argument-the-executor-passes" }
    bb:set("combat.target", chosen)

    T.assert_true(app:unit_target_resolver()(nil) == chosen,
        "the resolver handed to Executors.install must read the app's own selection")
    T.assert_true(app:unit_target_resolver()(a_different_unit) == chosen,
        "and must ignore the player handle the executor passes it, rather than resolving through it")
end

local function make_app_with_stub_registry()
    local ticks = {}
    local app = make_app({
        tick_all = function(_self, delta)
            ticks[#ticks + 1] = delta
        end,
        all = function() return {} end,
    })
    return app, ticks
end

function M.test_on_update_ticks_the_registry()
    local app, ticks = make_app_with_stub_registry()
    app:on_update()
    T.assert_equal(#ticks, 1, "on_update must tick all registered modules exactly once")
end

function M.test_repeated_updates_keep_ticking()
    local app, ticks = make_app_with_stub_registry()
    app:on_update()
    app:on_update()
    app:on_update()
    T.assert_equal(#ticks, 3, "every frame must tick the registry")
end

--- The delta handed to modules must be a usable number of milliseconds, not nil.
function M.test_tick_receives_numeric_delta()
    local app, ticks = make_app_with_stub_registry()
    app:on_update()
    app:on_update()
    T.assert_true(type(ticks[1]) == "number", "delta must be a number, got " .. type(ticks[1]))
    T.assert_true(ticks[2] >= 0, "delta must not be negative")
end

--- A module that throws must not take the whole tick loop down with it -- the
--- error boundary exists precisely so one bad module cannot freeze the bot.
function M.test_module_error_does_not_break_the_loop()
    local sensor_refreshes = 0
    local app = make_app({
        tick_all = function() error("module blew up") end,
        all = function() return {} end,
    })
    app._sensor_hub = {
        refresh = function() sensor_refreshes = sensor_refreshes + 1 end,
        shutdown = function() end,
    }

    local ok = pcall(app.on_update, app)
    T.assert_true(ok, "a throwing module must not propagate out of on_update")
    T.assert_equal(sensor_refreshes, 1)
end

--- B7: SentinelApp:shutdown() used to call module:shutdown() once via a manual
--- loop over registry:all(), THEN call registry:shutdown_all() which shuts
--- every module down again -- e.g. combat's shutdown would re-run a full
--- disengage a second time on every reload. shutdown_all() must be the SINGLE
--- shutdown path.
function M.test_shutdown_shuts_down_each_module_exactly_once()
    local shutdown_counts = {}
    local app = make_app({
        all = function()
            return {
                combat = { shutdown = function() shutdown_counts.combat = (shutdown_counts.combat or 0) + 1 end },
                questing = { shutdown = function() shutdown_counts.questing = (shutdown_counts.questing or 0) + 1 end },
            }
        end,
        shutdown_all = function(_self)
            shutdown_counts.combat = (shutdown_counts.combat or 0) + 1
            shutdown_counts.questing = (shutdown_counts.questing or 0) + 1
        end,
    })

    app:shutdown()

    T.assert_equal(shutdown_counts.combat, 1, "combat:shutdown must run exactly once")
    T.assert_equal(shutdown_counts.questing, 1, "questing:shutdown must run exactly once")
end

return M
