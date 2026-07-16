local TransactionAdapter = require("modules/grind/vendor_adapters")

local DefaultTransactionAdapter = {}
DefaultTransactionAdapter.__index = DefaultTransactionAdapter

function DefaultTransactionAdapter:new()
    return setmetatable({}, DefaultTransactionAdapter)
end

function DefaultTransactionAdapter:get_vendor_item_count()
    if not core or not core.game_ui then return nil end
    local ok, count = pcall(core.game_ui.get_vendor_item_count)
    return ok and count or nil
end

function DefaultTransactionAdapter:get_vendor_item_info(index)
    if not core or not core.game_ui then return nil end
    local ok, info = pcall(core.game_ui.get_vendor_item_info, index)
    return ok and info or nil
end

function DefaultTransactionAdapter:find_vendor_slot(item_id)
    local count = self:get_vendor_item_count()
    if not count or count == 0 then return nil end
    for i = 1, count do
        local info = self:get_vendor_item_info(i)
        if info and info.item_id == item_id then
            return i
        end
    end
    return nil
end

function DefaultTransactionAdapter:buy_item(slot, count)
    if not core or not core.input then return false end
    if core.input.buy_item then
        pcall(core.input.buy_item, slot, count or 1)
        return true
    end
    return false
end

function DefaultTransactionAdapter:repair_all_items(guild_bank)
    if not core or not core.input then return false end
    if core.input.repair_all then
        pcall(core.input.repair_all, guild_bank or false)
        return true
    end
    return false
end

function DefaultTransactionAdapter:sell_item(bag, slot)
    if not core or not core.input then return false end
    if core.input.use_container_item then
        pcall(core.input.use_container_item, bag, slot)
        return true
    end
    return false
end

function DefaultTransactionAdapter:use_container_item(bag, slot)
    if not core or not core.input then return false end
    if core.input.use_container_item then
        pcall(core.input.use_container_item, bag, slot)
        return true
    end
    return false
end

return DefaultTransactionAdapter