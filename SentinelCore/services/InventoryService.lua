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

local EQUIP_SLOT_MIN = 0
local EQUIP_SLOT_MAX = 23
local _inventory_helper_loaded = false
local _inventory_helper = nil

---@private
---@return table|nil
local function get_inventory_helper()
    if _inventory_helper_loaded then
        return _inventory_helper
    end
    _inventory_helper_loaded = true

    local ok, mod = pcall(require, "common/utility/inventory_helper")
    if ok and mod then
        _inventory_helper = mod
    end
    return _inventory_helper
end

---@private
---@return game_object|nil
local function get_local_player()
    if not core or not core.object_manager or not core.object_manager.get_local_player then
        return nil
    end

    local player = core.object_manager.get_local_player()
    local wrapped = player and player.object or nil
    if wrapped then
        player = wrapped
    end

    if not player or not player.is_valid or not player:is_valid() then
        return nil
    end
    return player
end

---@private
---@param player game_object
---@return table
local function build_equipped_item_set(player)
    local set = {}
    if not player or not player.get_item_at_inventory_slot then
        return set
    end

    for slot_id = EQUIP_SLOT_MIN, EQUIP_SLOT_MAX do
        local info = player:get_item_at_inventory_slot(slot_id)
        local obj = info and info.object or nil
        if obj and obj.is_valid and obj:is_valid() then
            set[obj] = true
        end
    end
    return set
end

---@private
---@return number|nil  Count of items in character bags (excluding equipped gear)
local function count_bag_items()
    local inventory_helper = get_inventory_helper()
    if not inventory_helper or type(inventory_helper.get_character_bag_slots) ~= "function" then
        return nil
    end

    local player = get_local_player()
    if not player then
        return nil
    end

    local slots = inventory_helper:get_character_bag_slots()
    if type(slots) ~= "table" then
        return nil
    end

    local equipped_set = build_equipped_item_set(player)
    local count = 0
    for i = 1, #slots do
        local slot = slots[i]
        local obj = (slot and slot.item) or (slot and slot.object) or nil
        if obj and obj.is_valid and obj:is_valid() and not equipped_set[obj] then
            count = count + 1
        end
    end
    return count
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
            local obj = slot and slot.object or nil
            if obj and obj.is_valid and obj:is_valid() then
                items[#items + 1] = {
                    object = obj,
                    item_id = tonumber(obj:get_item_id()) or 0,
                    stack_count = tonumber(obj.get_item_stack_count and obj:get_item_stack_count() or 1) or 1,
                    quality = tonumber(obj.get_quality and obj:get_quality() or 0) or 0,
                    bag_id = bag_id,
                    slot_id = tonumber(slot.slot_id) or -1,
                }
            end
        end
    end

    return items
end

---@return number  Free slots, or -1 if unknown/unconfigured
function InventoryService:get_free_slots()
    local total = tonumber(self._cfg.total_bag_slots) or 0
    if total <= 0 then
        self._blackboard:set("inventory.free_slots", -1)
        return -1
    end

    local used = count_bag_items()
    if used == nil then
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
function InventoryService:needs_vendor_trip()
    local free = self:get_free_slots()
    if free < 0 then
        return false
    end
    local min_free_slots = tonumber(self._policy.min_free_slots) or 2
    return free <= min_free_slots
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
