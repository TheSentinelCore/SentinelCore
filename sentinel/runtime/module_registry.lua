-- sentinel/runtime/module_registry.lua
-- Runtime Module Registry - SENT-8.1 per ADR 008 §16-17
-- Manages module lifecycle with states: UNLOADED, LOADED, INITIALIZING, ACTIVE, SHUTDOWN

-- The 3-strike policy lives in ONE place (kernel/fault_tracker.lua). This file used to hold the
-- original inline copy -- the scheduler's header names it as the reason the rule was extracted at
-- all, and calls this "the last holdout" kept while it was the running path. Delegating to the
-- tracker retires that copy: a private streak counter maintained here is precisely the second
-- authority the extraction removed.
--
-- CORRECTED IN PHASE 4D. This comment used to justify the delegation by claiming "combat registers
-- through the plugin registry, so this drives questing alone". That was false when written and is
-- false now: `ModuleRegistry.modules` below registers combat (enabled, priority 10), `app.lua`
-- calls `register_all` on THIS registry, and combat is never registered on the PluginRegistry at
-- all. The delegation is still correct -- one policy, one owner -- but it is correct for BOTH
-- modules, and the degrade rule in `tick_all` reaches combat. A future reader deciding what that
-- policy may safely do must know its blast radius includes the rotation engine, not questing alone.
local FaultTracker = require("kernel/fault_tracker")

local ModuleRegistry = {}
ModuleRegistry.__index = ModuleRegistry

-- Module lifecycle states
local MODULE_STATES = {
	UNLOADED = "unloaded",
	LOADED = "loaded",
	INITIALIZING = "initializing",
	ACTIVE = "active",
	DEGRADED = "degraded", -- tick faulted repeatedly; its tick is skipped, other modules keep running
	SHUTDOWN = "shutdown",
}

-- The consecutive-fault threshold is FaultTracker.DEFAULT_MAX_CONSECUTIVE. It is deliberately not
-- restated here: below the threshold a fault is transient and the module keeps ticking; at it, the
-- module would re-fault every frame forever. Both halves of that rule belong to the tracker.

-- Module schema - defines required structure for registered modules
-- Each module must provide: namespace, capabilities, configuration, state, lifecycle hooks
local MODULE_SCHEMA = {
	namespace = { type = "string", required = true },
	capabilities = { type = "table", required = false },
	configuration = { type = "table", required = false },
	state = { type = "string", required = false, default = MODULE_STATES.UNLOADED },
}

-- Declarative module configuration registry (combat + questing)
ModuleRegistry.modules = {
	combat = {
		namespace = "combat",
		capabilities = { "target_selection", "spell_casting", "pvp_detection" },
		configuration = {
			enabled = true,
			priority = 10,
		},
		init = function(blackboard, event_bus)
			local CombatModule = require("modules/combat/init")
			return CombatModule:new(blackboard, event_bus)
		end,
	},
	questing = {
		namespace = "questing",
		capabilities = { "quest_execution", "route_navigation" },
		configuration = {
			enabled = true, -- Enabled for editor access (can run empty rotations)
			priority = 50,
		},
		init = function(blackboard, event_bus)
			local QuestingModule = require("modules/questing/init")
			return QuestingModule:new(blackboard, event_bus)
		end,
	},
}

---Create a new ModuleRegistry
---@return table ModuleRegistry instance
function ModuleRegistry:new()
	local o = setmetatable({}, ModuleRegistry)
	o._modules = {}
	o._module_states = {}
	o._enabled_names = {}
	o._blackboard = nil
	o._event_bus = nil
	-- Consecutive tick-fault streaks, counted by the shared tracker and mirrored to blackboard
	-- system.module_faults so the cockpit can surface a fault that would otherwise only spam the log.
	o._faults = FaultTracker:new()
	o._module_faults = {}
	return o
end

---Validate module schema
---@param module_def table Module definition
---@return boolean valid, string|nil error
function ModuleRegistry:_validate_schema(module_def)
	if not module_def.namespace then
		return false, "module missing required namespace"
	end
	if type(module_def.namespace) ~= "string" then
		return false, "module namespace must be a string"
	end
	if module_def.capabilities and type(module_def.capabilities) ~= "table" then
		return false, "module capabilities must be a table"
	end
	if module_def.configuration and type(module_def.configuration) ~= "table" then
		return false, "module configuration must be a table"
	end
	return true, nil
end

---Register a module by name with its definition
---@param name string Module name (will be used as key)
---@param module_def table Module definition with namespace, capabilities, init
---@return boolean success, string|nil error
function ModuleRegistry:register(name, module_def)
	local valid, err = self:_validate_schema(module_def)
	if not valid then
		return false, err
	end

	if self._modules[name] then
		return false, "module already registered: " .. tostring(name)
	end

	self._modules[name] = module_def
	self._module_states[name] = MODULE_STATES.LOADED
	return true, nil
end

---Unregister a module by name
---@param name string Module name
---@return boolean success
function ModuleRegistry:unregister(name)
	if self._module_states[name] == MODULE_STATES.ACTIVE then
		return false, "cannot unregister active module: use shutdown first"
	end
	self._modules[name] = nil
	self._module_states[name] = nil
	return true
end

---Get module state
---@param name string Module name
---@return string State from MODULE_STATES
function ModuleRegistry:get_state(name)
	return self._module_states[name] or MODULE_STATES.UNLOADED
end

---Set module state
---@param name string Module name
---@param state string Target state
function ModuleRegistry:_set_state(name, state)
	self._module_states[name] = state
	if self._blackboard and self._event_bus then
		self._event_bus:publish("module_state_changed", {
			module = name,
			state = state,
		})
	end
end

---Register all declared modules and create instances
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return table List of registered module names
function ModuleRegistry:register_all(blackboard, event_bus)
	self._blackboard = blackboard
	self._event_bus = event_bus

	local sorted = {}
	for name, config in pairs(ModuleRegistry.modules) do
		if config.configuration and config.configuration.enabled ~= false then
			table.insert(sorted, { name = name, config = config })
		end
	end
	table.sort(sorted, function(a, b)
		return (a.config.configuration.priority or 0) < (b.config.configuration.priority or 0)
	end)

	for _, entry in ipairs(sorted) do
		local config = entry.config
		local success, err = self:register(entry.name, config)
		if not success then
			self:_set_state(entry.name, MODULE_STATES.SHUTDOWN)
		else
			self:initialize_module(entry.name, blackboard, event_bus)
		end
	end

	return self._enabled_names
end

---Initialize a single module
---@param name string Module name
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return boolean success
function ModuleRegistry:initialize_module(name, blackboard, event_bus)
	local module_def = self._modules[name]
	if not module_def then
		return false
	end

	if self._module_states[name] == MODULE_STATES.SHUTDOWN then
		return false, "module is shut down, cannot reinitialize"
	end

	-- Retain the collaborators when `register_all` has not already supplied them. Fault reporting
	-- needs a blackboard and an event bus, and this entry point is HANDED both and used to discard
	-- them -- so a module initialised through here alone had no channel to report a failure on.
	-- Never overwrites: `register_all`'s pair is the app's, and a later caller passing a different
	-- one must not silently redirect where every module's faults are published.
	if self._blackboard == nil then self._blackboard = blackboard end
	if self._event_bus == nil then self._event_bus = event_bus end

	self:_set_state(name, MODULE_STATES.INITIALIZING)

	local instance = module_def.init(blackboard, event_bus)
	if not instance then
		self:_set_state(name, MODULE_STATES.LOADED)
		return false
	end

	self._modules[name]._instance = instance
	self:_set_state(name, MODULE_STATES.ACTIVE)

	if not self._enabled_names[name] then
		table.insert(self._enabled_names, name)
	end

	return true
end

---Initialize all registered modules
---@param app table The application context to pass to module:init()
---@return boolean success
function ModuleRegistry:initialize_all(app)
	local all_ok = true
	for _, name in ipairs(self._enabled_names) do
		local module_def = self._modules[name]
		if module_def and module_def._instance then
			local instance = module_def._instance
			if type(instance.init) == "function" then
				local ok, err = pcall(instance.init, instance, app)
				if not ok then
					self:_set_state(name, MODULE_STATES.SHUTDOWN)
					all_ok = false
				end
			end
		end
	end
	return all_ok
end

---Tick all active modules
---@param delta number Milliseconds since last tick
function ModuleRegistry:tick_all(delta)
	for _, name in ipairs(self._enabled_names) do
		local state = self:get_state(name)
		if state == MODULE_STATES.ACTIVE then
			local module_def = self._modules[name]
			if module_def and module_def._instance then
				local instance = module_def._instance
				if type(instance.tick) == "function" then
					local ok, err = pcall(instance.tick, instance, delta)
					if not ok then
						-- The tracker owns the streak AND the threshold; this owns what the
						-- registry does when the threshold is crossed. Degrading rather than
						-- quarantining is the registry's own policy: a degraded module's tick
						-- is skipped while every other module keeps running.
						local degrade_now, count = self._faults:fault(name, err)
						self._module_faults[name] = { count = count, last_error = tostring(err) }
						if self._blackboard then
							self._blackboard:set("system.module_faults", self._module_faults)
						end
						if self._event_bus then
							self._event_bus:publish("module:fault", {
								module = name,
								error = tostring(err),
								count = count,
							})
						end
						if degrade_now then
							self:_set_state(name, MODULE_STATES.DEGRADED)
						end
					elseif self._faults:streak(name) > 0 then
						-- Only CONSECUTIVE faults degrade: a clean tick resets the streak.
						self._faults:success(name)
						self._module_faults[name] = nil
						if self._blackboard then
							self._blackboard:set("system.module_faults", self._module_faults)
						end
					end
				end
			end
		end
	end
end

---Shutdown a single module
---@param name string Module name
---@return boolean success
function ModuleRegistry:shutdown_module(name)
	local module_def = self._modules[name]
	if not module_def then
		return false
	end

	local state = self:get_state(name)
	if state == MODULE_STATES.SHUTDOWN or state == MODULE_STATES.UNLOADED then
		return true
	end

	local instance = module_def._instance
	if instance and type(instance.shutdown) == "function" then
		instance:shutdown()
	end

	module_def._instance = nil
	self:_set_state(name, MODULE_STATES.SHUTDOWN)

	-- Remove from enabled list
	for i, n in ipairs(self._enabled_names) do
		if n == name then
			table.remove(self._enabled_names, i)
			break
		end
	end

	return true
end

---Shutdown all modules
function ModuleRegistry:shutdown_all()
	for i = #self._enabled_names, 1, -1 do
		local name = self._enabled_names[i]
		self:shutdown_module(name)
	end
end

---Get module instance by name
---@param name string Module name
---@return table|nil Module instance
function ModuleRegistry:get(name)
	local module_def = self._modules[name]
	if module_def then
		return module_def._instance
	end
	return nil
end

---Get all module instances
---@return table Modules table keyed by name
function ModuleRegistry:all()
	local result = {}
	for name, module_def in pairs(self._modules) do
		if module_def._instance then
			result[name] = module_def._instance
		end
	end
	return result
end

---Get enabled module names
---@return table List of enabled module names
function ModuleRegistry:enabled_names()
	return self._enabled_names
end

---Get module capabilities
---@param name string Module name
---@return table|nil Capabilities table
function ModuleRegistry:get_capabilities(name)
	local module_def = self._modules[name]
	if module_def then
		return module_def.capabilities
	end
	return nil
end

---Check if a module has a specific capability
---@param name string Module name
---@param capability string Capability to check
---@return boolean has_capability
function ModuleRegistry:has_capability(name, capability)
	local caps = self:get_capabilities(name)
	if not caps then
		return false
	end
	for _, cap in ipairs(caps) do
		if cap == capability then
			return true
		end
	end
	return false
end

---Get module configuration
---@param name string Module name
---@return table|nil Configuration table
function ModuleRegistry:get_configuration(name)
	local module_def = self._modules[name]
	if module_def then
		return module_def.configuration
	end
	return nil
end

return ModuleRegistry