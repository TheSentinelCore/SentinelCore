local Runner = require("core/bt/runner")
local GrindTree = require("modules/grind/grind_tree")
local ProfileManager = require("modules/grind/profile_manager")
local ProfileVisualizer = require("modules/grind/profile_visualizer")
local StuckDetector = require("modules/grind/stuck_detector")
local Telemetry = require("modules/grind/telemetry")
local inventory_helper = require("common/utility/inventory_helper")
local ConsumableIds = require("modules/grind/consumable_ids")

local SentinelGrind = {}
SentinelGrind.__index = SentinelGrind

local MAX_CONSUMABLE_STACKS = 40

local function count_free_bag_slots()
    local ok, free = pcall(inventory_helper.get_total_free_slots, inventory_helper)
    if ok and type(free) == "number" then
        return free
    end
    return 0
end

---Count total stacks of food and water in bags.
---@return number food_stacks
---@return number water_stacks
local function count_consumables()
    local food_count = 0
    local water_count = 0
    local ok, slots = pcall(inventory_helper.get_character_bag_slots, inventory_helper)
    if not ok or type(slots) ~= "table" then
        return 0, 0
    end
    for _, slot in ipairs(slots) do
        if slot and slot.item then
            local ok_id, item_id = pcall(slot.item.get_item_id, slot.item)
            if ok_id and item_id then
                local stacks = slot.stack_count or 1
                if ConsumableIds.FOOD_ITEMS[item_id] then
                    food_count = food_count + stacks
                elseif ConsumableIds.WATER_ITEMS[item_id] then
                    water_count = water_count + stacks
                end
            end
        end
    end
    return food_count, water_count
end

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
    bb:set("module.grind.mode", "profile")
    bb:set("module.grind.patrol_radius", 60)

    self._stuck_detector = StuckDetector:new()
    bb:set("module.grind.stuck_detector", self._stuck_detector)

    self._telemetry = Telemetry:new(self._event_bus)
    bb:set("module.grind.telemetry", self._telemetry)

    self._runner = Runner:new(GrindTree.build(self._blackboard, self._event_bus, self._nav_adapter))

    self._profile_manager = ProfileManager:new(self._event_bus, self._blackboard)
    self._profile_manager:initialize()
    bb:set("module.grind.profile_manager", self._profile_manager)

    self._visualizer = ProfileVisualizer:new(self._blackboard, self._profile_manager)
    self._visualizer:initialize()
end

function SentinelGrind:update(blackboard)
    if not blackboard:get("module.grind.enabled") then
        -- Reset telemetry session so death loop can be recovered from on re-enable
        if self._telemetry_initialized then
            self._telemetry_initialized = false
        end
        return
    end
    if not self._runner then return end

    local now_ms = blackboard:get("system.now_ms", 0)

    -- Clear death-related state when player is alive (so next death starts fresh)
    local is_dead = blackboard:get("player.is_dead") == true
    local is_ghost = blackboard:get("player.is_ghost") == true
    if not is_dead and not is_ghost then
        if blackboard:get("module.grind.death_started_ms") then
            blackboard:clear("module.grind.death_started_ms")
            blackboard:clear("module.grind.last_release_ms")
            blackboard:clear("module.grind.last_resurrect_ms")
        end
    end

    -- Initialize telemetry on first enabled tick
    if self._telemetry and not self._telemetry_initialized then
        self._telemetry:initialize(now_ms)
        self._telemetry_initialized = true
    end

    -- Kill detection: check if current grind target died (fire once per target)
    local grind_target = blackboard:get("module.grind.current_target")
    if grind_target ~= self._last_grind_target then
        self._kill_published = false
    end
    if grind_target and self._last_grind_target == grind_target and not self._kill_published then
        local ok_alive, alive = pcall(grind_target.is_alive, grind_target)
        if ok_alive and not alive then
            self._event_bus:publish("grind:kill", { target = grind_target })
            self._kill_published = true
            blackboard:clear("module.grind.current_target")
        end
    end
    self._last_grind_target = grind_target

    -- Publish telemetry to blackboard
    if self._telemetry and self._telemetry_initialized then
        self._telemetry:publish_to_blackboard(blackboard, now_ms)
    end

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

    blackboard:set("module.grind.bag_free_slots", count_free_bag_slots())

    local food_count, water_count = count_consumables()
    blackboard:set("module.grind.food_count", food_count)
    blackboard:set("module.grind.water_count", water_count)
    blackboard:set("module.grind.needs_food", food_count < MAX_CONSUMABLE_STACKS)
    blackboard:set("module.grind.needs_water", water_count < MAX_CONSUMABLE_STACKS)

    self._runner:tick(blackboard)
end

function SentinelGrind:get_profile_manager()
    return self._profile_manager
end

function SentinelGrind:shutdown()
    if self._telemetry then
        self._telemetry:shutdown()
    end
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
