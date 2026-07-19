local ModuleRegistry = {}
ModuleRegistry.__index = ModuleRegistry

-- Declarative module configuration
ModuleRegistry.modules = {
    combat = {
        enabled = true,
        priority = 10,
        dependencies = { "core", "shared" },
        init = function(blackboard, event_bus)
            local CombatModule = require("modules.combat.init")
            return CombatModule:new(blackboard, event_bus)
        end,
    },
    ui = {
        enabled = true,
        priority = 5,
        dependencies = { "core", "shared" },
        init = function(blackboard, event_bus)
            local UI = require("ui.window")
            return UI:new(blackboard, event_bus)
        end,
    },
}

function ModuleRegistry:new()
    local o = setmetatable({}, ModuleRegistry)
    o._modules = {}
    o._enabled_names = {}
    return o
end

function ModuleRegistry:register_all(blackboard, event_bus)
    -- Sort by priority (highest first)
    local sorted = {}
    for name, config in pairs(ModuleRegistry.modules) do
        if config.enabled then
            table.insert(sorted, { name = name, config = config })
        end
    end
    table.sort(sorted, function(a, b) return a.config.priority > b.config.priority end)

    for _, entry in ipairs(sorted) do
        local config = entry.config
        local module = config.init(blackboard, event_bus)
        self._modules[entry.name] = module
        table.insert(self._enabled_names, entry.name)
    end
end

function ModuleRegistry:initialize_all(app)
    for _, name in ipairs(self._enabled_names) do
        local module = self._modules[name]
        if module and module.init then
            module:init(app)
        end
    end
end

function ModuleRegistry:tick_all(delta)
    for _, name in ipairs(self._enabled_names) do
        local module = self._modules[name]
        if module and module.tick then
            module:tick(delta)
        end
    end
end

function ModuleRegistry:get(name)
    return self._modules[name]
end

function ModuleRegistry:all()
    return self._modules
end

function ModuleRegistry:enabled_names()
    return self._enabled_names
end

return ModuleRegistry