local SentinelApp = require("runtime/app")

-- Set up package path for sentinel modules
package.path = table.concat({
    "sentinel/?.lua",
    "sentinel/?/?.lua",
    "sentinel/?/?/?.lua",
    "sentinel/?/?/?/?.lua",
    "sentinel/?/?/?/?/?.lua",
    package.path,
}, ";")

-- Load the bundled rotation packages so each can self-register (ADR 08 §2.4/§14). The inventory
-- lives in rotations/init.lua — the rotations layer owns its own contents; this host line only
-- says "this bundle ships rotations", and a rotation running as its own Sylvanas plugin needs
-- neither this line nor that inventory. AFTER the package.path block above, deliberately: in the
-- injector nothing has patched the path yet when this file loads, and a require above the block
-- fails on the very first line of a live boot while passing in every offline test.
require("rotations/init")

local app = nil
local initialized = false
local last_init_error = nil

-- Menu elements for main menu
local _menu_tree = core.menu.tree_node()
local _toggle_editor_btn = core.menu.button("sentinel_open_runner_cockpit")

-- Runner cockpit UI (deferred load until app is ready, to avoid Sylvannas API issues in tests).
-- Authoring lives OUTSIDE the game (the sentinel-editor HTTP API); the client is a cockpit for
-- running compiled profiles, not for editing them.
local RunnerUI = nil
local _questing_editor = nil
local _editor_subscribed = false

local function log_error(message)
    if core and type(core.log_error) == "function" then
        pcall(core.log_error, "[Sentinel] " .. tostring(message))
    end
end

local function log_info(message)
    if core and type(core.log) == "function" then
        pcall(core.log, "[Sentinel] " .. tostring(message))
    end
end

-- ======================================================================
-- Diagnostics sink (C4) — the EventBus is otherwise write-only for these events
-- (see audit finding C4): module:fault (Wave-1 per-module tick isolation),
-- questing:error (profile-load failure), and module lifecycle/shutdown state
-- changes all publish into the void with zero subscribers. This is a THIN sink:
-- it only logs what already happened, it makes no decisions and changes no state.
-- ======================================================================
--- Subscribe the diagnostics sink to a given bus. Split out from ensure_diagnostics_wired (which
--- binds it to the module-level `app`) so it is a pure, directly testable unit: pass any EventBus
--- in, get the same three subscriptions out, no SentinelApp/IziBridge boot required.
local function wire_diagnostics(bus)
    if not bus then return end

    -- `phase` is logged because ModuleRegistry tags every fault with it "so the two are
    -- distinguishable at the receiving end" -- and this sink IS the receiving end. Formatting
    -- module/count/error alone made that claim false: a module that DIED AT BOOT (SHUTDOWN,
    -- refused reinitialisation, dead until the operator reloads) and a module that hiccupped on
    -- one tick (streak cleared by the next clean tick) produced byte-identical log lines.
    --
    -- An absent phase reads `unknown`, NOT `tick`. Defaulting to `tick` would round every
    -- unlabelled fault towards the milder, self-healing reading -- the one direction a boot death
    -- must never be rounded in.
    --
    -- WHAT THIS SINK CANNOT SEE: it observes only what was PUBLISHED. A fault raised before the
    -- bus exists, or on a different bus (`ensure_diagnostics_wired` binds exactly one), is
    -- invisible here regardless of its phase. It also cannot distinguish a module that recovered
    -- from one that stayed dead -- there is no recovery event; the cockpit's `system.module_faults`
    -- map is the only channel that carries that.
    bus:subscribe("module:fault", function(payload)
        payload = payload or {}
        log_error(string.format(
            "module:fault module=%s phase=%s count=%s error=%s",
            tostring(payload.module), tostring(payload.phase or "unknown"),
            tostring(payload.count or 1), tostring(payload.error)))
    end)

    bus:subscribe("questing:error", function(payload)
        payload = payload or {}
        log_error("questing:error " .. tostring(payload.error))
    end)

    bus:subscribe("module_state_changed", function(payload)
        payload = payload or {}
        log_info(string.format(
            "module_state_changed module=%s state=%s",
            tostring(payload.module), tostring(payload.state)))
    end)
end

local _diagnostics_subscribed = false

local function ensure_diagnostics_wired()
    if _diagnostics_subscribed then return end
    if not app or not app.get_event_bus then return end
    local bus = app:get_event_bus()
    if not bus then return end
    wire_diagnostics(bus)
    _diagnostics_subscribed = true
end

-- Wire the runner cockpit to the toggle event once the app and its event bus are ready.
local function ensure_editor_wired()
    if _editor_subscribed then return end
    if not app or not app.get_event_bus then return end
    -- Lazy-load the UI only when needed (avoids issues in test contexts)
    RunnerUI = RunnerUI or require("modules/questing/runner_ui")
    local questing = app:get_module("questing")
    _questing_editor = RunnerUI:new(questing and questing._questing or nil)
    app:get_event_bus():subscribe("questing:toggle_editor", function()
        if _questing_editor then
            _questing_editor:toggle()
        end
    end)
    _editor_subscribed = true
end

local function clear_module_cache()
    if not package or not package.loaded then return end
    local prefixes = { "runtime/", "core/bt/", "modules/", "shared/" }
    for key in pairs(package.loaded) do
        for _, prefix in ipairs(prefixes) do
            if key:sub(1, #prefix) == prefix then
                package.loaded[key] = nil
                break
            end
        end
    end
end

-- F1: `clear_module_cache()` used to run unconditionally at the top of `ensure_initialized`,
-- BEFORE the pcall, with no state tracking beyond `initialized`. Since `initialized` only
-- flips true on SUCCESS, a single init failure meant every subsequent frame (this is called
-- from every registered callback, ~60/s) nil'd out ~50 entries in `package.loaded` and forced
-- a full re-`require` of the runtime tree before even attempting init again — indistinguishable
-- from a client hang. The cache only needs clearing ONCE per script load (to pick up a
-- hot-reloaded source tree), not once per failed retry. `_cache_cleared` tracks that; the
-- explicit `reload()` path below still clears unconditionally, since that is a deliberate
-- "pick up new code" request, not a retry loop.
local _cache_cleared = false
local _cache_clear_count = 0 -- exposed for offline testing only (F1 regression guard)

-- Forward declaration: publication needs the host verbs, which are defined below because `reload`
-- has to re-publish after it stands a new app up.
local publish_surface

local function ensure_initialized()
    if initialized and app then
        return true
    end

    if not _cache_cleared then
        clear_module_cache()
        _cache_cleared = true
        _cache_clear_count = _cache_clear_count + 1
    end

    local ok, result = pcall(function()
        local next_app = SentinelApp:new()
        -- Publish BEFORE initialize (ADR 08 §14): the publish drain registers whatever pushed
        -- itself onto `__SentinelPending`, and `rotation.kernel_pending` must be visible before
        -- the combat module initialises — after, the module has already built its profile through
        -- Registry.resolve and the plugin path idles behind the double-drive guard for the whole
        -- session. The kernel components the surface exposes are all constructed in new(), so
        -- publishing here exposes nothing half-built.
        publish_surface(next_app)
        next_app:initialize()
        return next_app
    end)

    if not ok then
        if result ~= last_init_error then
            last_init_error = result
            log_error("Initialization failed: " .. tostring(result))
        end
        return false
    end

    app = result
    initialized = true
    last_init_error = nil
    ensure_diagnostics_wired()
    ensure_editor_wired()
    log_info("SentinelCore loaded (Combat Engine)")
    return true
end

-- ---------------------------------------------------------------------------
-- Host verbs on `_G.Sentinel` (ADR 08 §10)
-- ---------------------------------------------------------------------------
-- The kernel owns COMPONENTS -- control, state, events, intents, plugins -- and publishes them
-- behind live getters. It cannot own the verbs below, because it does not build the app: this file
-- does, and it is the only thing that can tear one down and stand a new one up. So the host
-- contributes them and the kernel refuses any name that collides with one of its own fields.
--
-- `app` is no longer assigned here. It resolves through a live getter on the surface, which is what
-- makes the old `_G.Sentinel.app = app` unnecessary -- and necessary to remove, since the published
-- surface is read-only by design.
--
-- `get_event_bus` and `get_blackboard` used to sit here too. Both had zero callers and duplicated
-- `Sentinel.events` / `Sentinel.state`, so they are deleted rather than carried: two ways to reach
-- one object is exactly how the surfaces drift apart again.
local host_verbs = {}

function host_verbs.combat()
    if ensure_initialized() then return app:get_module("combat") end
    return nil
end

function host_verbs.questing()
    if ensure_initialized() then
        local q = app:get_module("questing")
        -- Return inner QuestingModule for direct access
        return q and q._questing or nil
    end
    return nil
end

function host_verbs.toggle_quest_editor()
    if ensure_initialized() then
        local q = app:get_module("questing")
        -- QuestingModuleInit wraps QuestingModule which has toggle_editor
        if q and q._questing and type(q._questing.toggle_editor) == "function" then
            q._questing:toggle_editor()
            return true
        end
    end
    return false
end

function host_verbs.reload()
    log_info("Forcing full reload...")
    if app and type(app.shutdown) == "function" then
        pcall(app.shutdown, app)
    end
    app = nil
    initialized = false
    last_init_error = nil
    clear_module_cache()
    _cache_cleared = true -- already cleared above; ensure_initialized must not clear again
    _cache_clear_count = _cache_clear_count + 1
    local ok, result = pcall(function()
        local next_app = SentinelApp:new()
        -- Publish BEFORE initialize (ADR 08 §14): the publish drain registers whatever pushed
        -- itself onto `__SentinelPending`, and `rotation.kernel_pending` must be visible before
        -- the combat module initialises — after, the module has already built its profile through
        -- Registry.resolve and the plugin path idles behind the double-drive guard for the whole
        -- session. The kernel components the surface exposes are all constructed in new(), so
        -- publishing here exposes nothing half-built.
        publish_surface(next_app)
        next_app:initialize()
        return next_app
    end)
    if ok then
        app = result
        initialized = true
        publish_surface(app)
        _editor_subscribed = false      -- re-subscribe with new event bus
        _diagnostics_subscribed = false -- re-subscribe with new event bus
        ensure_diagnostics_wired()
        ensure_editor_wired()
        log_info("Reloaded successfully")
        return true
    else
        log_error("Reload failed: " .. tostring(result))
        return false
    end
end

--- Assigns the forward-declared local. `_G.Sentinel` therefore appears on the first successful
--- init rather than at load: a plugin that loads before us registers through the
--- `__SentinelPending` queue, which exists for precisely that ordering (ADR 08 §2.4).
publish_surface = function(instance)
    return instance:publish_api(host_verbs)
end

core.register_on_pre_tick_callback(function()
    if ensure_initialized() then
        app:on_pre_tick()
    end
end)

local _last_editor_create_error = nil
core.register_on_update_callback(function()
    if ensure_initialized() then app:on_update() end
    -- Create quest editor frames in tick context: Sylvannas forbids creating
    -- windows/menu elements inside render callbacks.
    if _questing_editor then
        local ok, err = pcall(function() _questing_editor:ensure_frames_created() end)
        if not ok then
            local msg = "Quest editor frame creation failed: " .. tostring(err)
            if msg ~= _last_editor_create_error then
                _last_editor_create_error = msg
                log_error(msg)
            end
        else
            _last_editor_create_error = nil
        end
    end
end)

core.register_on_spell_cast_callback(function(data)
    if ensure_initialized() then app:on_spell_cast(data) end
end)

core.register_on_legit_spell_cast_callback(function(data)
    if ensure_initialized() then app:on_legit_spell_cast(data) end
end)

-- Optional render callbacks (no-op by default, registered for extensibility)
core.register_on_render_callback(function()
    if ensure_initialized() then app:on_render() end
end)

local _last_editor_render_error = nil
core.register_on_render_window_callback(function()
    if ensure_initialized() then app:on_render_window() end
    if _questing_editor then
        local ok, err = pcall(function() _questing_editor:_on_render_window() end)
        if not ok then
            local msg = "Quest editor render failed: " .. tostring(err)
            if msg ~= _last_editor_render_error then
                _last_editor_render_error = msg
                log_error(msg)
            end
        else
            _last_editor_render_error = nil
        end
    end
end)

-- Sentinel menu entry
core.register_on_render_menu_callback(function()
    if not ensure_initialized() then return end
    _menu_tree:render("SentinelCore", function()
        if _toggle_editor_btn:render("Open Runner Cockpit") then
            host_verbs.toggle_quest_editor()
        end
    end)
end)

local function on_unload()
    if _questing_editor and type(_questing_editor.destroy) == "function" then
        pcall(_questing_editor.destroy, _questing_editor)
    end
    if app and type(app.shutdown) == "function" then
        app:shutdown()
    end
    app = nil
    initialized = false
    _questing_editor = nil
    _editor_subscribed = false
    _diagnostics_subscribed = false
    _G.Sentinel = nil
end

return {
    name = "SentinelCore",
    version = "0.2.0",
    unload = on_unload,
    -- Exposed for offline tests only (tests/test_main_diagnostics.lua): lets the diagnostics
    -- sink be exercised against a real EventBus without booting the injector-only IziBridge.
    _wire_diagnostics_for_test = wire_diagnostics,
    -- Exposed for offline tests only (F1 regression guard, tests/test_main_diagnostics.lua):
    -- lets a test drive the real ensure_initialized() retry path and observe how many times
    -- the module cache actually got cleared.
    _ensure_initialized_for_test = ensure_initialized,
    _cache_clear_count_for_test = function() return _cache_clear_count end,
}
