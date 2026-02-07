---@class ModuleFactory
---Module instantiation registry — decouples BotManager from module constructors.
local ModuleFactory = {}
ModuleFactory.__index = ModuleFactory

local _registry = {}

---Register a module factory function
---@param name string Module name (must match module_order entry)
---@param factory_fn fun(module_class: table, deps: table): table|nil
function ModuleFactory.register(name, factory_fn)
    _registry[name] = factory_fn
end

---Create a module instance via its registered factory
---@param name string
---@param module_class table
---@param deps table { event_bus, state_machine, config, modules }
---@return table|nil
function ModuleFactory.create(name, module_class, deps)
    local factory = _registry[name]
    if factory then
        return factory(module_class, deps)
    end
    -- Generic fallback: pass event_bus
    if module_class.new then
        return module_class:new(deps.event_bus)
    end
    return nil
end

-- Register all GatherBuddy modules

ModuleFactory.register("Settings", function(cls, _deps)
    cls.init()
    return cls
end)

ModuleFactory.register("ProfileManager", function(cls, deps)
    return cls:new(deps.event_bus)
end)

ModuleFactory.register("NodeScanner", function(cls, deps)
    local profile_mgr = deps.modules.ProfileManager
    return cls:new(deps.event_bus, deps.state_machine, profile_mgr, deps.config.gathering)
end)

ModuleFactory.register("GatherModule", function(cls, deps)
    local node_scanner = deps.modules.NodeScanner
    return cls:new(deps.event_bus, deps.state_machine, node_scanner, deps.config.gathering)
end)

ModuleFactory.register("MountModule", function(cls, deps)
    return cls:new(deps.event_bus, deps.state_machine, deps.config.movement)
end)

ModuleFactory.register("SafetyModule", function(cls, deps)
    return cls:new(deps.event_bus, deps.state_machine, deps.config.safety)
end)

ModuleFactory.register("InventoryModule", function(cls, deps)
    return cls:new(deps.event_bus, deps.config.inventory)
end)

ModuleFactory.register("StatisticsModule", function(cls, deps)
    return cls:new(deps.event_bus)
end)

ModuleFactory.register("PathVisualizer", function(cls, deps)
    local movement = deps.modules.MovementModule
    local profile_mgr = deps.modules.ProfileManager
    return cls:new(movement, profile_mgr)
end)

return ModuleFactory
