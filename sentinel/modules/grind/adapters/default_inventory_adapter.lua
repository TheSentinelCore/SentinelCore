local InventoryAdapter = require("modules/grind/vendor_adapters")
local bag_scanner = require("modules/grind/bag_scanner")

local DefaultInventoryAdapter = {}
DefaultInventoryAdapter.__index = DefaultInventoryAdapter

function DefaultInventoryAdapter:new()
    return setmetatable({}, DefaultInventoryAdapter)
end

function DefaultInventoryAdapter:get_free_bag_slots()
    return bag_scanner.count_free_slots()
end

function DefaultInventoryAdapter:get_item_count(item_id)
    local count = 0
    bag_scanner.for_each_item(function(obj)
        local ok_id, raw_id = pcall(obj.get_item_id, obj)
        if ok_id and raw_id then
            local id = tonumber(raw_id) or raw_id
            if id == item_id then
                local stack = 1
                if obj.get_item_stack_count then
                    local ok_sc, sc = pcall(obj.get_item_stack_count, obj)
                    if ok_sc and sc then stack = sc end
                end
                count = count + stack
            end
        end
    end)
    return count
end

function DefaultInventoryAdapter:for_each_item(callback)
    bag_scanner.for_each_item(callback)
end

function DefaultInventoryAdapter:get_item_quality(item_id)
    -- Quality is fetched via QualityServiceAdapter, not directly from inventory
    return nil
end

return DefaultInventoryAdapter