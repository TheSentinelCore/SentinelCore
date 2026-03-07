local Runner = require("core/bt/runner")
local GrindTree = require("modules/grind/grind_tree")
local ProfileManager = require("modules/grind/profile_manager")
local ProfileVisualizer = require("modules/grind/profile_visualizer")

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

    self._profile_manager = ProfileManager:new(self._event_bus, self._blackboard)
    self._profile_manager:initialize()

    self._visualizer = ProfileVisualizer:new(self._blackboard, self._profile_manager)
    self._visualizer:initialize()
end

function SentinelGrind:update(blackboard)
    if not blackboard:get("module.grind.enabled") then return end
    if not self._runner then return end

    -- Profile management
    if self._profile_manager then
        local player = blackboard:get("player.object")
        local player_level = 70
        if player and type(player.get_level) == "function" then
            local ok, lv = pcall(player.get_level, player)
            if ok and type(lv) == "number" then player_level = lv end
        end
        local map_id = blackboard:get("system.map_id", 0) or 0

        -- Try autoload on first tick if no profile loaded
        if not self._profile_manager:is_profile_loaded() and not self._autoload_attempted then
            self._autoload_attempted = true
            self._profile_manager:try_autoload(player_level, map_id)
        end

        self._profile_manager:update(player_level, map_id)
    end

    self._runner:tick(blackboard)
end

function SentinelGrind:get_profile_manager()
    return self._profile_manager
end

function SentinelGrind:shutdown()
    if self._profile_manager then
        self._profile_manager:shutdown()
    end
    if self._visualizer then
        self._visualizer:shutdown()
    end
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
end

return SentinelGrind
