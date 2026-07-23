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

--- Build an app instance WITHOUT SentinelApp:new().
--- new() constructs IziBridge, which requires the injector-only `common/izi_sdk`
--- (and that pulls common/modules/health_prediction), none of which exist offline.
--- Only the tick plumbing is under test, so every collaborator is a recording stub.
local function make_app(registry)
    local app = setmetatable({}, SentinelApp)
    app._blackboard = require("core/blackboard"):new()
    app._registry = registry
    app._sensor_hub = { refresh = function() end, shutdown = function() end }
    app._callback_bridge = { on_update = function() end, on_pre_tick = function() end }
    app._nav_adapter = { poll = function() end }
    -- Mirrors ErrorBoundary:wrap — runs the thunk, swallows and reports errors.
    app._error_boundary = {
        wrap = function(_self, _scope, _op, fn)
            local ok, err = pcall(fn)
            if not ok then
                _self.last_error = err
            end
            return ok
        end,
    }
    return app
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
