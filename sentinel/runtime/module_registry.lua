-- sentinel/runtime/module_registry.lua
-- Runtime Module Registry - SENT-8.1 per ADR 008 §16-17
-- Manages module lifecycle with states: UNLOADED, LOADED, INITIALIZING, ACTIVE, SHUTDOWN

local ModuleRegistry = {}
ModuleRegistry.__index = ModuleRegistry

-- Module lifecycle states
local MODULE_STATES = {
	UNLOADED = "unloaded",
	LOADED = "loaded",
	INITIALIZING = "initializing",
	ACTIVE = "active",
	SHUTDOWN = "shutdown",
}

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
		return (a.config.configuration.priority or 0) > (b.config.configuration.priority or 0)
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
					instance:tick(delta)
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