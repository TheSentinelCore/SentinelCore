local bag_scanner = {}

local BACKPACK_SLOT_MIN = 36
local BACKPACK_SLOT_MAX = 51
local BACKPACK_CAPACITY = 16

---Iterate all item slots across bags 0-4.
---Calls fn(obj, bag, bag_slot) for each valid item.
---bag_slot = container-relative slot for use_container_item.
function bag_scanner.for_each_item(fn)
    for bag = 0, 4 do
        local ok, items = pcall(core.inventory.get_items_in_bag, bag)
        if ok and type(items) == "table" then
            for _, slot in ipairs(items) do
                local obj = slot.object
                if obj then
                    local ok_v, valid = pcall(obj.is_valid, obj)
                    if ok_v and valid then
                        if bag == 0 then
                            if slot.slot_id >= BACKPACK_SLOT_MIN and slot.slot_id <= BACKPACK_SLOT_MAX then
                                fn(obj, bag, slot.slot_id - BACKPACK_SLOT_MIN)
                            end
                        else
                            fn(obj, bag, slot.slot_id - 1)
                        end
                    end
                end
            end
        end
    end
end

---Count total free bag slots across bags 0-4.
---@return number free_slots
function bag_scanner.count_free_slots()
    local total_capacity = BACKPACK_CAPACITY
    for bag = 1, 4 do
        local ok, cap = pcall(core.inventory.get_num_bag_slots, bag)
        if ok and type(cap) == "number" then
            total_capacity = total_capacity + cap
        end
    end
    local used = 0
    bag_scanner.for_each_item(function() used = used + 1 end)
    return math.max(0, total_capacity - used)
end

---Find the highest-tier health and mana potions in bags.
---Potion ID tables map item_id → min_level (higher = better tier).
function bag_scanner.find_potions(health_potion_ids, mana_potion_ids)
    local best_health = nil
    local best_health_tier = -1
    local best_mana = nil
    local best_mana_tier = -1
    bag_scanner.for_each_item(function(obj)
        local ok, item_id = pcall(obj.get_item_id, obj)
        if ok and item_id then
            local h_tier = health_potion_ids[item_id]
            if h_tier and h_tier > best_health_tier then
                best_health = item_id
                best_health_tier = h_tier
            end
            local m_tier = mana_potion_ids[item_id]
            if m_tier and m_tier > best_mana_tier then
                best_mana = item_id
                best_mana_tier = m_tier
            end
        end
    end)
    return best_health, best_mana
end

return bag_scanner
