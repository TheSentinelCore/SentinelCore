local Runner = require("core/bt/runner")
local GrindTree = require("modules/grind/grind_tree")

local SentinelGrind = {}
SentinelGrind.__index = SentinelGrind

function SentinelGrind:new(event_bus, blackboard, nav_adapter)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _nav_adapter = nav_adapter,
        _subscriptions = {},
        _runner = nil,
    }, self)
end

function SentinelGrind:initialize()
    local bb = self._blackboard
    -- Set defaults
    bb:set("module.grind.enabled", false)
    bb:set("module.grind.health_flee_pct", 0.20)
    bb:set("module.grind.max_hostiles", 3)
    bb:set("module.grind.health_eat_pct", 0.50)
    bb:set("module.grind.mana_drink_pct", 0.40)
    bb:set("module.grind.needs_food", true)
    bb:set("module.grind.needs_water", true)

    self._runner = Runner:new(GrindTree.build(self._blackboard, self._event_bus, self._nav_adapter))
end

function SentinelGrind:update(blackboard)
    if not blackboard:get("module.grind.enabled") then return end
    if not self._runner then return end
    self._runner:tick(blackboard)
end

function SentinelGrind:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
end

return SentinelGrind
