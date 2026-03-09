local Runner = require("core/bt/runner")
local GrindTree = require("modules/grind/grind_tree")
local ProfileManager = require("modules/grind/profile_manager")
local ProfileVisualizer = require("modules/grind/profile_visualizer")
local StuckDetector = require("modules/grind/stuck_detector")
local Telemetry = require("modules/grind/telemetry")
local bag_scanner = require("modules/grind/bag_scanner")
local ConsumableIds = require("modules/grind/consumable_ids")
local DurabilityTracker = require("modules/grind/durability_tracker")
local MountController = require("modules/grind/mount_controller")
local ThreatMap = require("modules/grind/threat_map")

local SentinelGrind = {}
SentinelGrind.__index = SentinelGrind

local MAX_CONSUMABLE_STACKS = 40

local function count_free_bag_slots()
    return bag_scanner.count_free_slots()
end

---Count total stacks of food and water in bags.
---@return number food_stacks
---@return number water_stacks
local function count_consumables()
    local food_count = 0
    local water_count = 0
    bag_scanner.for_each_item(function(obj)
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id)
            if item_id then
                local stack = 1
                if obj.get_item_stack_count then
                    local ok_sc, sc = pcall(obj.get_item_stack_count, obj)
                    if ok_sc and sc then stack = sc end
                end
                if ConsumableIds.FOOD_ITEMS[item_id] then
                    food_count = food_count + stack
                elseif ConsumableIds.WATER_ITEMS[item_id] then
                    water_count = water_count + stack
                end
            end
        end
    end)
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

    self._durability_tracker = DurabilityTracker:new()
    self._mount_controller = MountController:new()
    self._threat_map = ThreatMap:new()

    bb:set("module.grind.durability_tracker", self._durability_tracker)
    bb:set("module.grind.mount_controller", self._mount_controller)
    bb:set("module.grind.threat_map", self._threat_map)

    local subs = self._subscriptions
    subs[#subs + 1] = self._event_bus:subscribe("grind:death", function(payload)
        if payload and payload.position then
            self._threat_map:record("DEATH", payload.position, 10, bb:get("system.now_ms", 0))
        end
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:stuck_recovery", function(payload)
        local pos = bb:get("player.position")
        if pos then
            self._threat_map:record("STUCK", pos, 2, bb:get("system.now_ms", 0))
        end
    end)
end

function SentinelGrind:update(blackboard)
    if not blackboard:get("module.grind.enabled") then
        -- Reset telemetry session so death loop can be recovered from on re-enable
        if self._telemetry_initialized then
            self._telemetry_initialized = false
        end
        -- Clear phase flags so Safety/Combat aren't blocked on re-enable
        if blackboard:get("module.grind.is_resting") then
            blackboard:set("module.grind.is_resting", false)
        end
        if blackboard:get("module.grind.is_looting") then
            blackboard:set("module.grind.is_looting", false)
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
            blackboard:clear("module.grind.corpse_position")
        end
    end

    -- Clear grind target on death/ghost so we don't re-pull the mob that killed us.
    -- Without this, Pull phase finds the stale target after rez and skips Rest.
    if is_dead or is_ghost then
        if blackboard:get("module.grind.current_target") then
            blackboard:set("module.grind.current_target", nil)
        end
        -- Clear is_looting so combat module isn't permanently blocked after
        -- dying mid-loot (loot_corpse action can't run to clean up as ghost).
        if blackboard:get("module.grind.is_looting") then
            blackboard:set("module.grind.is_looting", false)
        end
    end

    -- Initialize telemetry on first enabled tick
    if self._telemetry and not self._telemetry_initialized then
        self._telemetry:initialize(now_ms)
        self._telemetry_initialized = true
    end

    -- Kill detection: check if current grind target died or became stale.
    -- pcall failure means the object was deallocated (mob despawned/evaded).
    local grind_target = blackboard:get("module.grind.current_target")
    if grind_target ~= self._last_grind_target then
        self._kill_published = false
    end
    if grind_target and self._last_grind_target == grind_target and not self._kill_published then
        local ok_alive, alive = pcall(grind_target.is_alive, grind_target)
        if not ok_alive or not alive then
            if ok_alive then
                -- Confirmed dead — publish kill event for telemetry
                self._event_bus:publish("grind:kill", { target = grind_target })
            end
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

    -- Durability polling
    self._durability_tracker:sample(blackboard, now_ms)

    -- Sync repair threshold from UI (copper)
    local repair_threshold_copper = blackboard:get("module.grind.repair_threshold_copper")
    if repair_threshold_copper then
        self._durability_tracker:set_threshold_copper(repair_threshold_copper)
    end

    -- Potion scanning
    local hp_pot, mp_pot = bag_scanner.find_potions(ConsumableIds.HEALTH_POTION_IDS, ConsumableIds.MANA_POTION_IDS)
    blackboard:set("combat.has_health_potion", hp_pot ~= nil)
    blackboard:set("combat.health_potion_id", hp_pot)
    blackboard:set("combat.has_mana_potion", mp_pot ~= nil)
    blackboard:set("combat.mana_potion_id", mp_pot)

    -- Threat map GC (throttled to every 60s)
    if not self._last_threat_gc_ms or (now_ms - self._last_threat_gc_ms) >= 60000 then
        self._threat_map:gc(now_ms)
        self._last_threat_gc_ms = now_ms
    end

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
