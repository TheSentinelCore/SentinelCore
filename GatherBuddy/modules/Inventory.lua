---@class Inventory
---@field private _event_bus EventBus
---@field private _log Logger|nil
local Inventory = {}
Inventory.__index = Inventory

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local Helpers = require("utils/Helpers")
local Constants = require("core/Constants")

local EVENTS = Constants.EVENTS
local DEFAULT_SETTINGS = Constants.DEFAULT_SETTINGS

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "utils/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("Inventory")
    end
    return nil
end

---Create a new Inventory instance
---@param event_bus EventBus
---@param config? table Optional configuration
---@return Inventory
function Inventory:new(event_bus, config)
    local instance = setmetatable({}, Inventory)

    instance._event_bus = event_bus
    instance._log = get_logger()

    -- Configuration
    config = config or {}
    instance._min_free_slots = config.min_free_slots or DEFAULT_SETTINGS.inventory.min_free_slots
    instance._scan_interval = config.scan_interval or 5.0  -- seconds

    -- State tracking
    instance._last_scan_time = 0
    instance._cached_free_slots = nil
    instance._cached_total_slots = nil
    instance._was_bags_full = false

    -- Subscribe to events
    instance:_subscribe_events()

    return instance
end

---Subscribe to relevant events
function Inventory:_subscribe_events()
    -- Scan after looting
    self._event_bus:subscribe(EVENTS.LOOT_WINDOW_CLOSED, function()
        self:_refresh_inventory()
    end, 50, false, "Inventory")

    -- Track looted items
    self._event_bus:subscribe(EVENTS.ITEM_LOOTED, function(data)
        if self._log then
            self._log:debug("Item looted: %s", data.item_name or "Unknown")
        end
        -- Invalidate cache to force rescan
        self._cached_free_slots = nil
    end, 50, false, "Inventory")

    -- Bot stop
    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        self:_reset_state()
    end, 50, false, "Inventory")
end

---Update inventory state (call each tick)
function Inventory:update()
    local now = core.time()

    -- Periodic scan
    if now - self._last_scan_time >= self._scan_interval then
        self:_refresh_inventory()
        self._last_scan_time = now
    end
end

---Refresh inventory counts
function Inventory:_refresh_inventory()
    local free_slots = 0
    local total_slots = 0

    -- Scan bags 0-4 (backpack + 4 bags)
    for bag_id = 0, 4 do
        local bag_slots = self:_get_bag_slot_count(bag_id)
        local bag_items = self:_get_bag_item_count(bag_id)

        if bag_slots > 0 then
            total_slots = total_slots + bag_slots
            free_slots = free_slots + (bag_slots - bag_items)
        end
    end

    local previous_free = self._cached_free_slots or free_slots

    self._cached_free_slots = free_slots
    self._cached_total_slots = total_slots

    -- Check for bags full
    local is_full = free_slots < self._min_free_slots

    if is_full and not self._was_bags_full then
        -- Just became full
        self._was_bags_full = true

        if self._log then
            self._log:warn("Bags nearly full! %d free slots", free_slots)
        end

        self._event_bus:publish(EVENTS.BAGS_FULL, {
            free_slots = free_slots,
            total_slots = total_slots,
            timestamp = core.time()
        })
    elseif not is_full and self._was_bags_full then
        -- No longer full
        self._was_bags_full = false

        if self._log then
            self._log:info("Bags have space again: %d free slots", free_slots)
        end
    end

    -- Log if significant change
    if previous_free ~= free_slots and self._log then
        self._log:debug("Inventory: %d/%d slots free", free_slots, total_slots)
    end
end

---Get slot count for a bag
---@param bag_id number Bag index (0-4)
---@return number slot_count
function Inventory:_get_bag_slot_count(bag_id)
    -- Backpack is always 16 slots
    if bag_id == 0 then
        return 16
    end

    -- Use inventory_helper to get actual slot data if available
    if self._inventory_helper == nil then
        local ok, helper = pcall(require, "common/utility/inventory_helper")
        self._inventory_helper = ok and helper or false
    end

    if self._inventory_helper then
        local slots = self._inventory_helper:get_character_bag_slots()
        if slots then
            local max_slot = 0
            for _, slot_data in ipairs(slots) do
                if slot_data.bag_id == bag_id and slot_data.bag_slot > max_slot then
                    max_slot = slot_data.bag_slot
                end
            end
            if max_slot > 0 then
                return max_slot
            end
        end
    end

    -- Fallback: check if bag has any items (exists)
    local items = core.inventory.get_items_in_bag(bag_id)
    if items and #items > 0 then
        return #items  -- Best guess: use items array length
    end

    return 0
end

---Get item count in a bag
---@param bag_id number Bag index (0-4)
---@return number item_count
function Inventory:_get_bag_item_count(bag_id)
    local items = core.inventory.get_items_in_bag(bag_id)
    if items then
        local count = 0
        for _, item in ipairs(items) do
            if item and item.id and item.id > 0 then
                count = count + 1
            end
        end
        return count
    end
    return 0
end

---Get number of free bag slots
---@return number
function Inventory:get_free_slots()
    if self._cached_free_slots == nil then
        self:_refresh_inventory()
    end
    return self._cached_free_slots or 0
end

---Get total bag slots
---@return number
function Inventory:get_total_slots()
    if self._cached_total_slots == nil then
        self:_refresh_inventory()
    end
    return self._cached_total_slots or 0
end

---Check if bags are (nearly) full
---@return boolean
function Inventory:is_bags_full()
    return self:get_free_slots() < self._min_free_slots
end

---Check if should go to vendor
---@return boolean
function Inventory:should_vendor()
    return self:is_bags_full()
end

---Count specific item across all bags
---@param item_id number Item ID to count
---@return number count
function Inventory:get_item_count(item_id)
    if not item_id then
        return 0
    end

    local count = 0

    for bag_id = 0, 4 do
        local items = core.inventory.get_items_in_bag(bag_id)
        if items then
            for _, item in ipairs(items) do
                if item and item.id == item_id then
                    count = count + (item.count or 1)
                end
            end
        end
    end

    return count
end

---Get all items of a specific name pattern
---@param name_pattern string Name to search for (case-insensitive partial match)
---@return table[] items Array of matching items
function Inventory:find_items_by_name(name_pattern)
    local found = {}
    local pattern_lower = name_pattern:lower()

    for bag_id = 0, 4 do
        local items = core.inventory.get_items_in_bag(bag_id)
        if items then
            for slot, item in ipairs(items) do
                if item and item.name then
                    if item.name:lower():find(pattern_lower, 1, true) then
                        table.insert(found, {
                            id = item.id,
                            name = item.name,
                            count = item.count or 1,
                            bag = bag_id,
                            slot = slot
                        })
                    end
                end
            end
        end
    end

    return found
end

---Get summary of gathered items (herbs and ores)
---@return table summary {herbs={}, ores={}, total_count=n}
function Inventory:get_gathered_summary()
    local Nodes = require("data/Nodes")

    local summary = {
        herbs = {},
        ores = {},
        total_count = 0
    }

    for bag_id = 0, 4 do
        local items = core.inventory.get_items_in_bag(bag_id)
        if items then
            for _, item in ipairs(items) do
                if item and item.name then
                    local count = item.count or 1

                    -- Check if it's a herb
                    if Nodes.is_herb(item.name) then
                        summary.herbs[item.name] = (summary.herbs[item.name] or 0) + count
                        summary.total_count = summary.total_count + count
                    -- Check if it's an ore
                    elseif Nodes.is_ore(item.name) then
                        summary.ores[item.name] = (summary.ores[item.name] or 0) + count
                        summary.total_count = summary.total_count + count
                    end
                end
            end
        end
    end

    return summary
end

---Set minimum free slots threshold
---@param slots number Minimum free slots before "full"
function Inventory:set_min_free_slots(slots)
    self._min_free_slots = Helpers.clamp(slots, 0, 100)
end

---Get minimum free slots threshold
---@return number
function Inventory:get_min_free_slots()
    return self._min_free_slots
end

---Force refresh inventory cache
function Inventory:refresh()
    self:_refresh_inventory()
end

---Reset internal state
function Inventory:_reset_state()
    self._cached_free_slots = nil
    self._cached_total_slots = nil
    self._was_bags_full = false
end

---Clean up module
function Inventory:destroy()
    self:_reset_state()
    self._event_bus:unsubscribe_owner("Inventory")
end

---Run unit tests
---@return table<string, boolean> Test results
function Inventory:_test()
    local results = {}

    -- Create mock dependencies
    local mock_bus = {
        events = {},
        subscriptions = {},
        publish = function(self, event, data)
            table.insert(self.events, { event = event, data = data })
        end,
        subscribe = function(self, event, callback, priority, once, owner)
            table.insert(self.subscriptions, { event = event, owner = owner })
            return #self.subscriptions
        end,
        unsubscribe_owner = function() end
    }

    -- Test 1: Create module
    local module = Inventory:new(mock_bus)
    results.create = (module ~= nil)

    -- Test 2: Initial state
    results.initial_min_slots = (module:get_min_free_slots() == DEFAULT_SETTINGS.inventory.min_free_slots)

    -- Test 3: Set min free slots
    module:set_min_free_slots(5)
    results.set_min_slots = (module:get_min_free_slots() == 5)

    -- Test 4: Clamp min slots
    module:set_min_free_slots(200)
    results.clamp_min_slots = (module:get_min_free_slots() == 100)

    -- Test 5: Reset state
    module._cached_free_slots = 10
    module._was_bags_full = true
    module:_reset_state()
    results.reset_cache = (module._cached_free_slots == nil)
    results.reset_full = not module._was_bags_full

    -- Test 6: Methods exist
    results.has_get_free = (type(module.get_free_slots) == "function")
    results.has_is_full = (type(module.is_bags_full) == "function")
    results.has_find_items = (type(module.find_items_by_name) == "function")
    results.has_get_summary = (type(module.get_gathered_summary) == "function")

    -- Test 7: Events subscribed
    results.events_subscribed = (#mock_bus.subscriptions >= 2)

    return results
end

return Inventory
