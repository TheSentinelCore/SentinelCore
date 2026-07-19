local InteractionAdapter = require("modules/grind/vendor_adapters")

local DefaultInteractionAdapter = {}
DefaultInteractionAdapter.__index = DefaultInteractionAdapter

function DefaultInteractionAdapter:new()
    return setmetatable({}, DefaultInteractionAdapter)
end

function DefaultInteractionAdapter:find_npc(npc_id)
    if not core or not core.object_manager then return nil end
    local ok, objects = pcall(core.object_manager.get_all_objects)
    if not ok or type(objects) ~= "table" then return nil end
    for _, obj in ipairs(objects) do
        local ok_npc, id = pcall(obj.get_npc_id, obj)
        if ok_npc and id == npc_id then
            local ok_alive, alive = pcall(obj.is_alive, obj)
            if ok_alive and alive then
                return obj
            end
        end
    end
    return nil
end

function DefaultInteractionAdapter:target_npc(npc)
    if not core or not core.input then return false end
    if core.input.set_target then
        pcall(core.input.set_target, npc)
    end
    return true
end

function DefaultInteractionAdapter:interact_with_npc(npc)
    if not core or not core.input then return false end
    if core.input.interact_with_object then
        pcall(core.input.interact_with_object, npc)
    end
    return true
end

function DefaultInteractionAdapter:is_vendor_window_open()
    if not core or not core.game_ui then return false end
    local ok, count = pcall(core.game_ui.get_vendor_item_count)
    return ok and (count or 0) > 0
end

function DefaultInteractionAdapter:close_vendor()
    if not core or not core.input then return false end
    if core.input.close_vendor then
        pcall(core.input.close_vendor)
    end
    return true
end

return DefaultInteractionAdapter