-- modules/combat/init.lua
-- Combat module entry point for ModuleRegistry
-- Wraps SentinelCombat with the registry interface: init(blackboard, event_bus) -> module
--
-- ================================================================================
-- WHY THE ENGINE IS BUILT IN `init`, NOT IN `new`
-- ================================================================================
-- This file used to call `IziBridge:new()` itself, which made TWO live bridges in every session:
-- one owned by `SentinelApp:new()` (app.lua) and this one. They kept independent IZI state, and the
-- app's was reachable by nothing -- ADR 08 §7 recorded `_izi_bridge` as constructed-and-never-read
-- and was right, because the only consumers had their own. ADR §5.1 is explicit that shared
-- reference data belongs to the kernel because "duplicating it costs memory and drifts".
--
-- The registry's two entry points hand over different things, and that is the whole seam:
--
--   `ModuleRegistry:register_all` -> `module_def.init(blackboard, event_bus)`   -- CONSTRUCTS this
--   `ModuleRegistry:initialize_all(app)` -> `instance:init(app)`                -- STARTS it
--
-- The app only exists at the second one. So the engine is constructed there, with the app's bridge,
-- and the registry's declarative `init(blackboard, event_bus)` thunk signature is untouched --
-- widening it would have reached the questing entry and several registry tests for no gain.
--
-- CONSEQUENCE, stated because it is observable: `get_combat()` returns nil until `init` has run.
-- Nothing in the tree calls it before then (`SentinelApp:initialize()` runs `register_all` and
-- `initialize_all` back to back, and `tick` guards on `_initialized`), but a future caller that
-- does will get nil rather than a half-built engine, which fails where the cause is.

local SentinelCombat = require("modules/combat/module")
local NavAdapter = require("integrations/nav_client/adapter")

local CombatModule = {}
CombatModule.__index = CombatModule

function CombatModule:new(blackboard, event_bus)
    local o = setmetatable({}, CombatModule)
    o._blackboard = blackboard
    o._event_bus = event_bus
    -- B4: shared adapter keyed by event_bus -- same instance SentinelApp holds when
    -- this event_bus is the shared app bus (see integrations/nav_client/adapter.lua).
    o._nav_adapter = NavAdapter.get_shared(event_bus)
    return o
end

---@param app table|nil the SentinelApp, handed over by `ModuleRegistry:initialize_all`
function CombatModule:init(app)
    -- No app, no bridge -- deliberately, and NOT a private fallback instance. A module initialised
    -- outside a real app (a test driving `initialize_module` alone) runs with the forecast absent,
    -- which is the same state the injector produces when the IZI SDK is not loaded: every consumer
    -- already guards for it. Building one here to fill the hole is exactly how the second instance
    -- appeared in the first place.
    local izi_bridge = nil
    if app ~= nil and type(app.get_izi_bridge) == "function" then
        izi_bridge = app:get_izi_bridge()
    end
    self._izi_bridge = izi_bridge
    self._combat = SentinelCombat:new(self._event_bus, self._blackboard, self._nav_adapter, izi_bridge)
    self._combat:initialize()
    self._initialized = true
end

function CombatModule:tick(delta)
    if not self._initialized then return end
    self._combat:update(self._blackboard)
end

function CombatModule:shutdown()
    if self._combat then
        self._combat:shutdown()
    end
end

function CombatModule:get_combat()
    return self._combat
end

return CombatModule
