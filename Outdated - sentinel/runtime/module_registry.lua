local ModuleRegistry = {}
ModuleRegistry.__index = ModuleRegistry

function ModuleRegistry:new()
    local o = setmetatable({}, ModuleRegistry)
    o._modules = {}
    return o
end

function ModuleRegistry:register(name, module)
    self._modules[name] = module
end

function ModuleRegistry:get(name)
    return self._modules[name]
end

function ModuleRegistry:all()
    return self._modules
end

return ModuleRegistry
