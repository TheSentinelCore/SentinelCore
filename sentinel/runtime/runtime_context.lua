-- sentinel/runtime/runtime_context.lua
-- RuntimeContext - aggregates blackboard, event bus, and module registry for SENT-8.1
-- Provides lifecycle management (initialize/destroy) for the application runtime.

local ModuleRegistry = require("runtime/module_registry")

local RuntimeContext = {}
RuntimeContext.__index = RuntimeContext

function RuntimeContext:new(blackboard, event_bus)
	local o = setmetatable({}, RuntimeContext)
	o._blackboard = blackboard
	o._event_bus = event_bus
	o._module_registry = ModuleRegistry:new()
	o._initialized = false
	return o
end

function RuntimeContext:get_module_registry()
	return self._module_registry
end

function RuntimeContext:initialize(app)
	if self._initialized then
		return
	end
	self._module_registry:register_all(self._blackboard, self._event_bus)
	self._module_registry:initialize_all(app)
	self._initialized = true
end

function RuntimeContext:destroy()
	self._module_registry:shutdown_all()
	self._initialized = false
end

function RuntimeContext:tick(delta)
	if not self._initialized then
		return
	end
	self._module_registry:tick_all(delta)
end

return RuntimeContext
