local Defaults = require("core/Defaults")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@class InventoryService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _policy table
---@field private _threshold_emitted boolean
local InventoryService = {}
InventoryService.__index = InventoryService

local BACKPACK_SLOTS = 16
local BAG_EQUIP_SLOT_BASE = 30  -- inventory slots 31-34 = bags 1-4
-- get_items_in_bag(0) returns ALL occupied inventory slots including equipment (1-18),
-- bag equip slots (31-34), backpack storage (36-51), and bank/keyring/other (60+).
-- Only slots 36-51 are actual backpack storage.
local BACKPACK_FIRST_SLOT = 36
local BACKPACK_LAST_SLOT = 51

-- All TBC non-special bags: item_id → slot_count
-- Source: tbcmangos.item_template WHERE class=1 AND subclass=0
local BAG_SIZES = {
    [20474]=4,[22976]=4,[23389]=4,
    [805]=6,[828]=6,[2082]=6,[4238]=6,[4496]=6,[4930]=6,
    [4957]=6,[5081]=6,[5571]=6,[5572]=6,[5762]=6,[6756]=6,[22571]=6,
    [856]=8,[1537]=8,[2657]=8,[3233]=8,[3343]=8,[4240]=8,
    [4241]=8,[4498]=8,[5573]=8,[5574]=8,[5603]=8,[5763]=8,
    [6754]=8,[11845]=8,[23852]=8,
    [804]=10,[857]=10,[918]=10,[932]=10,[933]=10,[1470]=10,
    [1729]=10,[3352]=10,[4245]=10,[4497]=10,[5575]=10,[5576]=10,
    [5764]=10,[5765]=10,[6446]=10,
    [1652]=12,[1725]=12,[3762]=12,[4499]=12,[4981]=12,
    [10050]=12,[10051]=12,[16057]=12,
    [1685]=14,[3914]=14,[9587]=14,[11324]=14,[14046]=14,
    [19291]=14,[30744]=14,
    [4500]=16,[10683]=16,[10959]=16,[11742]=16,[14155]=16,
    [20400]=16,[21841]=16,
    [14156]=18,[17966]=18,[19914]=18,[21843]=18,[22679]=18,
    [27680]=18,[33117]=18,
    [21876]=20,[34067]=20,[34845]=20,[35516]=20,
    [38082]=22,
    [23162]=36,
}

---@private
---@return number total_capacity
---@return number used_count
---@private
---@param obj any
---@return boolean
local function is_valid_object(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj:is_valid() end)
    return ok and valid == true
end

---@private
---@param obj any
---@return number
local function safe_item_id(obj)
    if obj == nil then return 0 end
    local ok, id = pcall(function() return obj:get_item_id() end)
    return ok and tonumber(id) or 0
end

local function compute_bag_counts()
    if not core or not core.inventory or not core.inventory.get_items_in_bag then
        return -1, -1
    end

    local total = BACKPACK_SLOTS
    local used = 0

    -- Bag 0 (backpack): only count actual backpack storage (slots 36-51).
    local bag0_items = core.inventory.get_items_in_bag(0)
    if bag0_items then
        for i = 1, #bag0_items do
            local slot = bag0_items[i]
            if slot and slot.slot_id and slot.slot_id >= BACKPACK_FIRST_SLOT and slot.slot_id <= BACKPACK_LAST_SLOT then
                if is_valid_object(slot.object) and safe_item_id(slot.object) > 0 then
                    used = used + 1
                end
            end
        end
    end

    -- Bags 1-4: detect equipped bags and count their contents.
    local player = core.object_manager and core.object_manager.get_local_player
        and core.object_manager.get_local_player() or nil
    if player and is_valid_object(player) then
        for bag_id = 1, 4 do
            local ok, result = pcall(function()
                return player:get_item_at_inventory_slot(BAG_EQUIP_SLOT_BASE + bag_id)
            end)
            if ok and result and result.object and is_valid_object(result.object) then
                local bag_item_id = safe_item_id(result.object)
                if bag_item_id > 0 then
                    local capacity = 0
                    local dyn_ok, dyn_size = pcall(function()
                        return result.object:get_bag_num_slots()
                    end)
                    if dyn_ok and tonumber(dyn_size) and tonumber(dyn_size) > 0 then
                        capacity = tonumber(dyn_size) or 0
                    else
                        capacity = BAG_SIZES[bag_item_id] or 0
                    end
                    if capacity > 0 then
                        total = total + capacity
                        local items = core.inventory.get_items_in_bag(bag_id)
                        if items then
                            for i = 1, #items do
                                local slot = items[i]
                                if slot and is_valid_object(slot.object) and safe_item_id(slot.object) > 0 then
                                    used = used + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return total, used
end

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@param policy table
---@return InventoryService
function InventoryService:new(event_bus, blackboard, cfg, policy)
    local o = setmetatable({}, InventoryService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._policy = policy and Defaults.copy(policy) or Defaults.copy(Defaults.policy)
    o._threshold_emitted = false
    return o
end

---@param policy table
function InventoryService:set_policy(policy)
    self._policy = Defaults.copy(policy)
end

---@return table
function InventoryService:get_policy()
    return Defaults.copy(self._policy)
end

---@private
---@param list table
---@return table
local function to_set(list)
    local set = {}
    if type(list) == "table" then
        for i = 1, #list do
            set[tonumber(list[i]) or -1] = true
        end
    end
    return set
end

---@private
---@param rule table
---@param item table
---@return boolean
local function rule_matches_item(rule, item)
    if type(rule) ~= "table" or type(rule.match) ~= "table" then
        return false
    end

    local match = rule.match
    local item_id = tonumber(item.item_id) or 0
    local quality = tonumber(item.quality) or 0
    local stack_count = tonumber(item.stack_count) or 0

    if type(match.item_ids) == "table" and #match.item_ids > 0 then
        local found = false
        for i = 1, #match.item_ids do
            if tonumber(match.item_ids[i]) == item_id then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    local quality_min = tonumber(match.quality_min)
    if quality_min and quality < quality_min then
        return false
    end

    local quality_max = tonumber(match.quality_max)
    if quality_max and quality > quality_max then
        return false
    end

    local stack_min = tonumber(match.stack_min)
    if stack_min and stack_count < stack_min then
        return false
    end

    local stack_max = tonumber(match.stack_max)
    if stack_max and stack_count > stack_max then
        return false
    end

    return true
end

---@return table[]
function InventoryService:collect_items()
    local items = {}
    if not core or not core.inventory or not core.inventory.get_items_in_bag then
        return items
    end

    for bag_id = 0, 4 do
        local bag_items = core.inventory.get_items_in_bag(bag_id) or {}
        for i = 1, #bag_items do
            local slot = bag_items[i]
            -- Bag 0: only include actual backpack storage (slots 36-51)
            if bag_id ~= 0 or (slot and slot.slot_id and slot.slot_id >= BACKPACK_FIRST_SLOT and slot.slot_id <= BACKPACK_LAST_SLOT) then
                local obj = slot and slot.object or nil
                if is_valid_object(obj) then
                    local item_id = safe_item_id(obj)
                    if item_id > 0 then
                        local ok_stack, stack = pcall(function() return obj:get_item_stack_count() end)
                        local ok_quality, quality = pcall(function() return obj:get_quality() end)
                        items[#items + 1] = {
                            object = obj,
                            item_id = item_id,
                            stack_count = tonumber(ok_stack and stack or 1) or 1,
                            quality = tonumber(ok_quality and quality or 0) or 0,
                            bag_id = bag_id,
                            slot_id = tonumber(slot.slot_id) or -1,
                        }
                    end
                end
            end
        end
    end

    return items
end

---@return number  Free slots, or -1 if unknown/unavailable
function InventoryService:get_free_slots()
    local total, used = compute_bag_counts()
    if total < 0 then
        self._blackboard:set("inventory.free_slots", -1)
        return -1
    end
    local free = math.max(0, total - used)
    self._blackboard:set("inventory.free_slots", free)
    return free
end

---@param item table
---@return boolean
function InventoryService:should_sell_item(item)
    local policy = self._policy or Defaults.policy
    local item_id = tonumber(item.item_id) or 0
    local never = to_set(policy.never_sell)
    local always = to_set(policy.always_sell)

    if never[item_id] then
        return false
    end

    -- Special rule support (keep only for explicit item ids).
    if type(policy.special_rules) == "table" then
        for i = 1, #policy.special_rules do
            local rule = policy.special_rules[i]
            if rule_matches_item(rule, item) then
                if rule.action == "keep" then
                    return false
                end
                if rule.action == "sell" then
                    local keep_floor = tonumber(rule.keep_stack_min) or 0
                    if keep_floor > 0 and (tonumber(item.stack_count) or 0) <= keep_floor then
                        return false
                    end
                    return true
                end
            end
        end
    end

    if always[item_id] then
        return true
    end

    local keep_min = tonumber(policy.keep_stack_min and policy.keep_stack_min[tostring(item_id)] or 0) or 0
    if keep_min > 0 and (tonumber(item.stack_count) or 0) <= keep_min then
        return false
    end

    local quality = tonumber(item.quality) or 0
    local quality_toggles = {
        [0] = policy.sell_gray,
        [1] = policy.sell_white,
        [2] = policy.sell_green,
        [3] = policy.sell_blue,
        [4] = policy.sell_epic,
    }
    local toggle_value = quality_toggles[quality]
    if toggle_value ~= nil then
        return toggle_value == true
    end

    -- Backward compatibility fallback for profiles that rely on sell_quality_max.
    local sell_quality_max = tonumber(policy.sell_quality_max)
    if sell_quality_max and quality <= sell_quality_max then
        return true
    end

    return false
end

---@return table[]
function InventoryService:get_sell_candidates()
    local items = self:collect_items()
    local out = {}
    for i = 1, #items do
        if self:should_sell_item(items[i]) then
            out[#out + 1] = items[i]
        end
    end
    return out
end

---@return boolean
function InventoryService:is_vendor_enabled()
    -- Check blackboard override first (survives profile reloads).
    local bb_override = self._blackboard:get("inventory.vendor_enabled", nil)
    if bb_override ~= nil then
        return bb_override == true
    end
    return self._policy.vendor_enabled ~= false
end

---@param enabled boolean
function InventoryService:set_vendor_enabled(enabled)
    self._blackboard:set("inventory.vendor_enabled", enabled)
end

---@return boolean
function InventoryService:needs_repair_trip()
    if not self._policy.repair_enabled then
        return false
    end
    local dur = self._blackboard:get("player.durability_pct", 1.0)
    local threshold = tonumber(self._cfg.repair_threshold) or 0.25
    return dur < threshold
end

---@return boolean
function InventoryService:needs_vendor_trip()
    if not self:is_vendor_enabled() then
        return false
    end
    local free = self:get_free_slots()
    local min_free_slots = tonumber(self._policy.min_free_slots) or 2
    local bags_full = free >= 0 and free <= min_free_slots
    local repair_needed = self:needs_repair_trip()
    return bags_full or repair_needed
end

---@return boolean
---@return string|nil
function InventoryService:validate_policy()
    if type(self._policy.min_free_slots) ~= "number" then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end

    if type(self._policy.never_sell) ~= "table" or type(self._policy.always_sell) ~= "table" then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end

    if type(self._policy.keep_stack_min) ~= "table" or type(self._policy.special_rules) ~= "table" then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end

    return true, nil
end

function InventoryService:update()
    local needs_vendor = self:needs_vendor_trip()
    self._blackboard:set("inventory.needs_vendor", needs_vendor)

    if needs_vendor and not self._threshold_emitted then
        self._threshold_emitted = true
        self._event_bus:emit(Events.INVENTORY_THRESHOLD_REACHED, {
            timestamp = (core and core.time and core.time()) or 0,
            free_slots = self._blackboard:get("inventory.free_slots", 0),
            min_free_slots = tonumber(self._policy.min_free_slots) or 2,
            error_code = ErrorCodes.INVENTORY_THRESHOLD_REACHED,
        })
    elseif not needs_vendor then
        self._threshold_emitted = false
    end
end

return InventoryService
