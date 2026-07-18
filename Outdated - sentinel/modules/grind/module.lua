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
local ThreatTypes = require("modules/grind/threat_types")
local GrindStateManager = require("modules/grind/grind_state_manager")
local GrindTelemetry = require("modules/grind/grind_telemetry")
local GrindPvPWatcher = require("modules/grind/grind_pvp_watcher")

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
                end
                if ConsumableIds.WATER_ITEMS[item_id] then
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

    -- Sub-modules for coordination concerns
    self._state_manager = GrindStateManager:new()
    self._grind_telemetry = GrindTelemetry:new(self._event_bus)
    self._grind_telemetry:set_telemetry(self._telemetry)
    self._pvp_watcher = GrindPvPWatcher:new()

    local subs = self._subscriptions
    subs[#subs + 1] = self._event_bus:subscribe("grind:death", function(payload)
        if payload and payload.position then
            self._threat_map:record(ThreatTypes.DEATH, payload.position, nil, bb:get("system.now_ms", 0))
        end
    end)

    subs[#subs + 1] = self._event_bus:subscribe("grind:stuck_recovery", function(payload)
        local pos = bb:get("player.position")
        if pos then
            self._threat_map:record(ThreatTypes.STUCK, pos, nil, bb:get("system.now_ms", 0))
        end
    end)
end

function SentinelGrind:update(blackboard)
    local now_ms = blackboard:get("system.now_ms", 0)
    local enabled = blackboard:get("module.grind.enabled") == true

    -- State manager handles all state cleanup on disable/death/ghost
    local skip = self._state_manager:tick(blackboard, enabled)
    if skip or not self._runner then return end

    -- Kill tracking: detect target death by GUID
    self._state_manager:track_kills(blackboard, self._event_bus)

    -- Telemetry tick: init + throttled publish
    self._grind_telemetry:tick(blackboard, now_ms)

    -- Profile management
    if self._profile_manager then
        local player = blackboard:get("player.object")
        local player_level = 70
        if player and type(player.get_level) == "function" then
            local ok, lv = pcall(player.get_level, player)
            if ok and type(lv) == "number" then player_level = lv end
        end
        local map_id = blackboard:get("system.map_id", 0) or 0

        if not self._profile_manager:is_profile_loaded() and not self._autoload_attempted then
            self._autoload_attempted = true
            self._profile_manager:try_autoload(player_level, map_id)
        end

        self._profile_manager:update(player_level, map_id)
    end

    -- Bag consumable tracking
    blackboard:set("module.grind.bag_free_slots", count_free_bag_slots())
    local food_count, water_count = count_consumables()
    blackboard:set("module.grind.food_count", food_count)
    blackboard:set("module.grind.water_count", water_count)
    blackboard:set("module.grind.needs_food", food_count < MAX_CONSUMABLE_STACKS)
    blackboard:set("module.grind.needs_water", water_count < MAX_CONSUMABLE_STACKS)

    -- Durability polling
    self._durability_tracker:sample(blackboard, now_ms)
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

    -- PvP scanning + threat map GC
    self._pvp_watcher:tick(blackboard, now_ms, self._threat_map)

    -- Death loop response
    if self._grind_telemetry:is_death_loop(now_ms) then
        if not self._state_manager:get_death_loop_responding() then
            self._state_manager:set_death_loop_responding(true)
            self:_handle_death_loop(blackboard, now_ms)
        end
    else
        self._state_manager:set_death_loop_responding(false)
    end

    -- Pause gate
    local paused_until = blackboard:get("module.grind.paused_until_ms", 0)
    if now_ms < paused_until then
        return
    end

    -- DIAGNOSTIC: detect combat.source transitions (one-shot on change)
    local current_src = blackboard:get("combat.source")
    if current_src ~= self._diag_prev_src then
        if core and core.log then
            pcall(core.log, string.format(
                "[Grind] TRANSITION: combat.source %s→%s  hp=%.2f mp=%.2f inCombat=%s cast=%s tgt=%s",
                tostring(self._diag_prev_src), tostring(current_src),
                tonumber(blackboard:get("player.health_pct", 1)) or 1,
                tonumber(blackboard:get("player.mana_pct", 1)) or 1,
                tostring(blackboard:get("player.in_combat", false)),
                tostring(blackboard:get("player.is_casting", false)),
                tostring(blackboard:get("module.grind.current_target") ~= nil)))
        end
        self._diag_prev_src = current_src
    end

    -- DIAGNOSTIC: dump state every 1s
    if not self._diag_last_ms or (now_ms - self._diag_last_ms) >= 1000 then
        self._diag_last_ms = now_ms
        if core and core.log then
            pcall(core.log, string.format(
                "[Grind] DIAG: src=%s tgt=%s resting=%s looting=%s hp=%.2f mp=%.2f inCombat=%s casting=%s food=%d water=%d eat@%.0f%% drink@%.0f%%",
                tostring(current_src),
                tostring(blackboard:get("module.grind.current_target") ~= nil),
                tostring(blackboard:get("module.grind.is_resting")),
                tostring(blackboard:get("module.grind.is_looting")),
                tonumber(blackboard:get("player.health_pct", 1)) or 1,
                tonumber(blackboard:get("player.mana_pct", 1)) or 1,
                tostring(blackboard:get("player.in_combat", false)),
                tostring(blackboard:get("player.is_casting", false)),
                tonumber(blackboard:get("module.grind.food_count", 0)) or 0,
                tonumber(blackboard:get("module.grind.water_count", 0)) or 0,
                (tonumber(blackboard:get("module.grind.health_eat_pct", 0.50)) or 0.50) * 100,
                (tonumber(blackboard:get("module.grind.mana_drink_pct", 0.40)) or 0.40) * 100))
        end
    end

    self._runner:tick(blackboard)
end

-- ---------------------------------------------------------------------------
-- Death loop handler: relocate to safest hotspot or pause
-- ---------------------------------------------------------------------------
function SentinelGrind:_handle_death_loop(bb, now_ms)
    if self._profile_manager and self._profile_manager:is_profile_loaded() then
        local _, best_heat = self._profile_manager:advance_to_safest_hotspot(self._threat_map, now_ms)
        if best_heat and best_heat >= 8 then
            bb:set("module.grind.paused_until_ms", now_ms + 300000)
            self._event_bus:publish("grind:paused", {
                reason = "death_loop",
                duration_ms = 300000,
                resume_at_ms = now_ms + 300000,
            })
        end
    end
end

function SentinelGrind:get_profile_manager()
    return self._profile_manager
end

function SentinelGrind:shutdown()
    self._grind_telemetry:shutdown()
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