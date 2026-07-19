local VendorPipeline = {}
VendorPipeline.__index = VendorPipeline

local Status = require("core/bt/status")
local Geometry = require("core/geometry")
local ConsumableIds = require("modules/grind/consumable_ids")
local DefaultInventoryAdapter = require("modules/grind/adapters/default_inventory_adapter")

-- Never sell these items
local NEVER_SELL = {
    [6948] = true,  -- Hearthstone
    [6265] = true,  -- Soul Shard
    [5060] = true,  -- Thieves' Tools
    [15138] = true, -- Onyxia Scale Cloak
    [17031] = true, -- Rune of Teleportation
    [17032] = true, -- Rune of Portals
    [17020] = true, -- Arcane Powder
    [17021] = true, -- Symbol of Divinity
    [17028] = true, -- Holy Candle
    [17029] = true, -- Sacred Candle
    [17033] = true, -- Symbol of Kings
    [21177] = true, -- Symbol of Kings
    [5565] = true,  -- Infernal Stone
    [16583] = true, -- Demonic Figurine
    -- Mage conjured food/water
    [5349] = true, [1113] = true, [1114] = true, [1487] = true, [8075] = true, [8076] = true, [22895] = true,
    [5350] = true, [1445] = true, [1708] = true, [8074] = true, [8077] = true, [22019] = true, [22893] = true,
    [22044] = true, -- Mana Emerald
    [22018] = true, -- Conjured mana biscuit
    -- Health potions
    [118] = true, [858] = true, [929] = true, [1710] = true, [3928] = true, [13446] = true, [22829] = true,
    -- Mana potions
    [2455] = true, [3385] = true, [3827] = true, [6149] = true, [13443] = true, [13444] = true, [22832] = true,
}

local QUALITY_GREEN = 2
local DEFAULT_MIN_KEEP_QUALITY = QUALITY_GREEN
local SELL_BATCH_SIZE = 4
local QUALITY_TIMEOUT_MS = 5000

function VendorPipeline:new(adapters)
    adapters = adapters or {}
    return setmetatable({
        _nav_adapter = adapters.nav,
        _interaction_adapter = adapters.interaction,
        _transaction_adapter = adapters.transaction,
        _inventory_adapter = adapters.inventory or DefaultInventoryAdapter:new(),
        _quality_adapter = adapters.quality,
        _state = nil,
        _vendor_data = nil,
        _retries = 0,
        _interact_at_ms = 0,
        _quality_cache = nil,
        _quality_pending = false,
        _quality_request_ms = 0,
    }, self)
end

function VendorPipeline:reset()
    self._state = nil
    self._vendor_data = nil
    self._retries = 0
    self._interact_at_ms = 0
    self._quality_cache = nil
    self._quality_pending = false
    self._quality_request_ms = 0
end

function VendorPipeline:is_running()
    return self._state ~= nil
end

-- Main tick function - call this each frame
function VendorPipeline:tick(bb)
    -- Abort if combat module engaged
    if bb:get("combat.source") ~= nil then
        self:reset()
        if self._nav_adapter then
            self._nav_adapter:stop("vendor_abort_combat")
        end
        return Status.FAILURE
    end

    if not self._state then
        return self:_state_init(bb)
    elseif self._state == "traveling" then
        return self:_state_traveling(bb)
    elseif self._state == "interacting" then
        return self:_state_interacting(bb)
    elseif self._state == "waiting_window" then
        return self:_state_waiting_window(bb)
    elseif self._state == "repairing" then
        return self:_state_repairing(bb)
    elseif self._state == "selling" then
        return self:_state_selling(bb)
    elseif self._state == "selling_wait" then
        return self:_state_selling_wait(bb)
    elseif self._state == "buying_food" then
        return self:_state_buying_food(bb)
    elseif self._state == "buying_water" then
        return self:_state_buying_water(bb)
    elseif self._state == "done" then
        return self:_state_done(bb)
    end

    self:reset()
    return Status.FAILURE
end

-- State: Init - find vendor
function VendorPipeline:_state_init(bb)
    local player_pos = bb:get("player.position")
    local pm = bb:get("module.grind.profile_manager")
    if not pm or not player_pos then
        return Status.FAILURE
    end

    local sell_vendor = pm:get_nearest_vendor(player_pos, "sell")
    local repair_vendor = bb:get("module.grind.needs_repair") and pm:get_nearest_vendor(player_pos, "repair")
    local food_vendor = (bb:get("module.grind.needs_food") or bb:get("module.grind.needs_water"))
        and pm:get_nearest_vendor(player_pos, "food")

    local vendor = sell_vendor or repair_vendor or food_vendor
    if not vendor then
        return Status.FAILURE
    end

    self._vendor_data = vendor
    self._state = "traveling"
    return Status.RUNNING
end

-- State: Traveling to vendor
function VendorPipeline:_state_traveling(bb)
    if not self._vendor_data then
        self:reset()
        return Status.FAILURE
    end

    local vendor_pos = { x = self._vendor_data.x, y = self._vendor_data.y, z = self._vendor_data.z }
    local player_pos = bb:get("player.position")
    local dist = Geometry.distance(player_pos, vendor_pos)

    if dist <= 5 then
        if self._nav_adapter then
            self._nav_adapter:stop("vendor_arrived")
        end
        self._state = "interacting"
        return Status.RUNNING
    end

    -- Stuck detection
    local stuck = bb:get("module.grind.stuck_detector")
    if stuck and player_pos then
        local now = bb:get("system.now_ms", 0)
        stuck:sample(now, player_pos, "vendor_travel")
        if stuck:is_stuck() then
            if self._nav_adapter then
                self._nav_adapter:stop("vendor_travel_stuck")
            end
            stuck:reset()
            self:reset()
            return Status.FAILURE
        end
    end

    if self._nav_adapter and not self._nav_adapter:is_active() then
        self._nav_adapter:move_to(vendor_pos)
    end
    return Status.RUNNING
end

-- State: Interacting with vendor NPC
function VendorPipeline:_state_interacting(bb)
    if not self._vendor_data then
        self:reset()
        return Status.FAILURE
    end

    -- Check if vendor window is already open
    if self:_vendor_window_open() then
        self._state = "repairing"
        return Status.RUNNING
    end

    local npc = self:_find_npc(self._vendor_data.npc_id)
    if not npc then
        self:reset()
        return Status.FAILURE
    end

    if self._interaction_adapter then
        self._interaction_adapter:interact(npc)
    else
        if core and core.input then
            if core.input.set_target then
                pcall(core.input.set_target, npc)
            end
            if core.input.interact_with_object then
                pcall(core.input.interact_with_object, npc)
            end
        end
    end

    self._interact_at_ms = bb:get("system.now_ms", 0)
    self._state = "waiting_window"
    return Status.RUNNING
end

-- State: Waiting for vendor window to open
function VendorPipeline:_state_waiting_window(bb)
    if self:_vendor_window_open() then
        self._retries = 0
        self._state = "repairing"
        return Status.RUNNING
    end

    local now = bb:get("system.now_ms", 0)
    if now - self._interact_at_ms > 2000 then
        self._retries = self._retries + 1
        if self._retries >= 3 then
            self:reset()
            return Status.FAILURE
        end
        self._state = "interacting"
    end
    return Status.RUNNING
end

-- State: Repairing
function VendorPipeline:_state_repairing(bb)
    if self:_has_service("repair") and bb:get("module.grind.needs_repair") == true then
        if self._transaction_adapter then
            self._transaction_adapter:repair_all()
        else
            if core and core.input and type(core.input.repair_all_items) == "function" then
                pcall(core.input.repair_all_items, false)
            end
        end
        local dt = bb:get("module.grind.durability_tracker")
        if dt then dt:reset() end
    end

    local free = bb:get("module.grind.bag_free_slots", 999)
    self._state = (free <= 2) and "selling" or "buying_food"
    return Status.RUNNING
end

-- State: Selling items
function VendorPipeline:_state_selling(bb)
    self._quality_cache = nil
    self._quality_pending = false
    local item_ids = self:_collect_bag_item_ids()
    self._quality_request_ms = bb:get("system.now_ms", 0)
    self:_fetch_item_qualities(item_ids)
    self._state = "selling_wait"
    return Status.RUNNING
end

-- State: Waiting for quality data, then selling
function VendorPipeline:_state_selling_wait(bb)
    if self._quality_pending then
        local now = bb:get("system.now_ms", 0)
        if now - self._quality_request_ms > QUALITY_TIMEOUT_MS then
            self._quality_pending = false
            self._quality_cache = {}
        end
        return Status.RUNNING
    end

    local keep_set = self:_build_keep_set(bb)
    local min_quality = self:_get_min_keep_quality(bb)
    local _, has_more = self:_sell_filtered_items(keep_set, min_quality)
    if has_more then
        return Status.RUNNING
    end

    self._state = "buying_food"
    return Status.RUNNING
end

-- State: Buying food
function VendorPipeline:_state_buying_food(bb)
    if not self:_has_service("food") or not bb:get("module.grind.needs_food") then
        self._state = "buying_water"
        return Status.RUNNING
    end

    local player_level = self:_get_player_level(bb)
    local food_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_FOOD, player_level)
    if food_id then
        local buy_count = 40 - (bb:get("module.grind.food_count", 0))
        if buy_count > 0 then
            local slot = self:_find_vendor_slot(food_id)
            if slot and self._transaction_adapter then
                self._transaction_adapter:buy(slot, buy_count)
            elseif slot and core and core.input then
                pcall(core.input.buy_item, slot, buy_count)
            end
        end
    end
    self._state = "buying_water"
    return Status.RUNNING
end

-- State: Buying water
function VendorPipeline:_state_buying_water(bb)
    if not self:_has_service("food") or not bb:get("module.grind.needs_water") then
        self._state = "done"
        return Status.RUNNING
    end

    local player_level = self:_get_player_level(bb)
    local water_id = ConsumableIds.resolve_for_level(ConsumableIds.VENDOR_WATER, player_level)
    if water_id then
        local buy_count = 40 - (bb:get("module.grind.water_count", 0))
        if buy_count > 0 then
            local slot = self:_find_vendor_slot(water_id)
            if slot and self._transaction_adapter then
                self._transaction_adapter:buy(slot, buy_count)
            elseif slot and core and core.input then
                pcall(core.input.buy_item, slot, buy_count)
            end
        end
    end
    self._state = "done"
    return Status.RUNNING
end

-- State: Done
function VendorPipeline:_state_done(bb)
    self:reset()
    return Status.SUCCESS
end

-- Helper: Check if vendor window is open
function VendorPipeline:_vendor_window_open()
    if self._interaction_adapter then
        return self._interaction_adapter:is_vendor_window_open()
    end
    if core and core.input and type(core.input.is_vendor_window_open) == "function" then
        local ok, result = pcall(core.input.is_vendor_window_open)
        return ok and result == true
    end
    return false
end

-- Helper: Find vendor NPC
function VendorPipeline:_find_npc(npc_id)
    if self._interaction_adapter then
        return self._interaction_adapter:find_npc(npc_id)
    end
    if not core or not core.object_manager or not core.object_manager.get_all_objects then
        return nil
    end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end

    for _, obj in ipairs(objects) do
        local ok_id, raw_id = pcall(obj.get_npc_id, obj)
        if ok_id and raw_id and tonumber(raw_id) == npc_id then
            return obj
        end
    end
    return nil
end

-- Helper: Check if vendor has service
function VendorPipeline:_has_service(service)
    return self._vendor_data
        and self._vendor_data.services
        and self._vendor_data.services[service] == true
end

-- Helper: Collect bag item IDs
function VendorPipeline:_collect_bag_item_ids()
    local ids = {}
    self._inventory_adapter:for_each_item(function(obj)
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local item_id = tonumber(raw_id)
            if item_id then
                ids[#ids + 1] = item_id
            end
        end
    end)
    return ids
end

-- Helper: Fetch item qualities from quality service
function VendorPipeline:_fetch_item_qualities(item_ids)
    if not self._quality_adapter or #item_ids == 0 then
        self._quality_cache = {}
        return
    end
    self._quality_pending = true
    self._quality_adapter:fetch_qualities(item_ids, function(qualities)
        self._quality_cache = qualities or {}
        self._quality_pending = false
    end)
end

-- Helper: Build keep set
function VendorPipeline:_build_keep_set(bb)
    local keep_set = {}
    local profile = bb:get("module.combat.profile")
    if profile and type(profile.get_pull_strategy) == "function" then
        local strategy = profile:get_pull_strategy(bb)
        if strategy == "aoe" then
            -- Keep AOE consumables
        end
    end

    -- Keep consumables
    local food_count = bb:get("module.grind.food_count", 0)
    local water_count = bb:get("module.grind.water_count", 0)
    if food_count > 0 then
        for id in pairs(ConsumableIds.FOOD_ITEMS) do
            keep_set[id] = true
        end
    end
    if water_count > 0 then
        for id in pairs(ConsumableIds.WATER_ITEMS) do
            keep_set[id] = true
        end
    end

    -- Never sell items
    for id in pairs(NEVER_SELL) do
        keep_set[id] = true
    end

    return keep_set
end

-- Helper: Get minimum keep quality
function VendorPipeline:_get_min_keep_quality(bb)
    local quality = bb:get("module.grind.vendor_sell_quality")
    if type(quality) == "number" and quality >= 0 and quality <= 4 then
        return quality
    end
    return DEFAULT_MIN_KEEP_QUALITY
end

-- Helper: Sell filtered items
function VendorPipeline:_sell_filtered_items(keep_set, min_quality)
    local sold_count = 0
    local has_more = false

    self._inventory_adapter:for_each_item(function(obj)
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if not ok_id or not raw_id then return end
        local item_id = tonumber(raw_id)
        if not item_id then return end

        if keep_set[item_id] then return end
        if NEVER_SELL[item_id] then return end

        local quality = self._quality_cache and self._quality_cache[item_id]
        if quality ~= nil and quality >= min_quality then return end

        local slot = self:_find_bag_slot(item_id)
        if slot then
            if self._transaction_adapter then
                self._transaction_adapter:sell(slot)
            else
                if core and core.input and type(core.input.sell_item) == "function" then
                    pcall(core.input.sell_item, slot)
                end
            end
            sold_count = sold_count + 1
            if sold_count >= SELL_BATCH_SIZE then
                has_more = true
                return
            end
        end
    end)

    return sold_count, has_more
end

-- Helper: Find vendor item slot
function VendorPipeline:_find_vendor_slot(item_id)
    if self._transaction_adapter then
        return self._transaction_adapter:find_vendor_item(item_id)
    end
    -- Fallback: would need vendor window scanning
    return nil
end

-- Helper: Find bag slot for item
function VendorPipeline:_find_bag_slot(item_id)
    if self._transaction_adapter then
        return self._transaction_adapter:find_bag_item(item_id)
    end
    -- Fallback
    return nil
end

-- Helper: Get player level
function VendorPipeline:_get_player_level(bb)
    local player = bb:get("player.object")
    if player and type(player.get_level) == "function" then
        local ok, lv = pcall(player.get_level, player)
        if ok and type(lv) == "number" then return lv end
    end
    return 70
end

return VendorPipeline