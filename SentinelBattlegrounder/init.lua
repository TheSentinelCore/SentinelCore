local BgBuddy = {}
BgBuddy.__index = BgBuddy

BgBuddy.VERSION = require("version")
BgBuddy.NAME = "BgBuddy"

local _instance = nil

function BgBuddy:get_instance()
    if not _instance then
        local instance = setmetatable({}, BgBuddy)
        local ok, QueueManager = pcall(require, "modules/QueueManager")
        if ok and QueueManager then
            instance._queue = QueueManager:new()
        else
            instance._queue = nil
            core.log_error("[BgBuddy] Failed to load QueueManager: " .. tostring(QueueManager))
        end
        _instance = instance
    end
    return _instance
end

function BgBuddy:initialize()
    local inst = self:get_instance()
    if not inst._queue then
        return false
    end
    return true
end

function BgBuddy:start()
    local inst = self:get_instance()
    if inst._queue then
        inst._queue:start()
    end
end

function BgBuddy:stop()
    local inst = self:get_instance()
    if inst._queue then
        inst._queue:stop()
    end
end

function BgBuddy:update()
    local inst = self:get_instance()
    if inst._queue then
        inst._queue:update()
    end
end

function BgBuddy:set_city(city)
    local inst = self:get_instance()
    if inst._queue then
        inst._queue:set_city(city)
    end
end

function BgBuddy:get_city()
    local inst = self:get_instance()
    if inst._queue then
        return inst._queue:get_city()
    end
    return "stormwind"
end

function BgBuddy:set_anchor_from_player(city)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_anchor_from_player then
        return inst._queue:set_anchor_from_player(city)
    end
    return false
end

function BgBuddy:set_bg_anchor_from_player(city, bg_key)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_bg_anchor_from_player then
        return inst._queue:set_bg_anchor_from_player(city, bg_key)
    end
    return false
end

function BgBuddy:set_bg_role(role)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_bg_role then
        inst._queue:set_bg_role(role)
    end
end

function BgBuddy:get_bg_role()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_bg_role then
        return inst._queue:get_bg_role()
    end
    return "normal"
end

function BgBuddy:set_combat_enabled(enabled)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_combat_enabled then
        inst._queue:set_combat_enabled(enabled)
    end
end

function BgBuddy:get_combat_enabled()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_combat_enabled then
        return inst._queue:get_combat_enabled()
    end
    return false
end

function BgBuddy:set_rotation_class(class_key)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_rotation_class then
        inst._queue:set_rotation_class(class_key)
    end
end

function BgBuddy:get_rotation_class()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_rotation_class then
        return inst._queue:get_rotation_class()
    end
    return "warlock"
end

function BgBuddy:get_rotation_class_options()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_rotation_class_options then
        return inst._queue:get_rotation_class_options()
    end
    return { "Warlock (Demo)" }
end

function BgBuddy:set_selected_bg(bg_key)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_selected_bg then
        inst._queue:set_selected_bg(bg_key)
    end
end

function BgBuddy:get_selected_bg()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_selected_bg then
        return inst._queue:get_selected_bg()
    end
    return "alterac"
end

function BgBuddy:get_bg_options()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_bg_options then
        return inst._queue:get_bg_options()
    end
    return { "Alterac Valley", "Warsong Gulch", "Arathi Basin", "Eye of the Storm (Cyclone)" }
end

function BgBuddy:set_multi_queue_enabled(enabled)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_multi_queue_enabled then
        inst._queue:set_multi_queue_enabled(enabled)
    end
end

function BgBuddy:get_multi_queue_enabled()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_multi_queue_enabled then
        return inst._queue:get_multi_queue_enabled()
    end
    return false
end

function BgBuddy:set_multi_queue_bg_enabled(bg_key, enabled)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_multi_queue_bg_enabled then
        inst._queue:set_multi_queue_bg_enabled(bg_key, enabled)
    end
end

function BgBuddy:get_multi_queue_bg_enabled(bg_key)
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_multi_queue_bg_enabled then
        return inst._queue:get_multi_queue_bg_enabled(bg_key)
    end
    return false
end

function BgBuddy:set_auto_faction(enabled)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_auto_faction then
        inst._queue:set_auto_faction(enabled)
    end
end

function BgBuddy:get_auto_faction()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_auto_faction then
        return inst._queue:get_auto_faction()
    end
    return true
end

function BgBuddy:get_detected_faction()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_detected_faction then
        return inst._queue:get_detected_faction()
    end
    return "unknown"
end

function BgBuddy:get_debug_snapshot()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_debug_snapshot then
        return inst._queue:get_debug_snapshot()
    end
    return {}
end

function BgBuddy:set_debug_enabled(enabled)
    local inst = self:get_instance()
    if inst._queue and inst._queue.set_debug_enabled then
        inst._queue:set_debug_enabled(enabled)
    end
end

function BgBuddy:get_debug_enabled()
    local inst = self:get_instance()
    if inst._queue and inst._queue.get_debug_enabled then
        return inst._queue:get_debug_enabled()
    end
    return true
end

function BgBuddy:is_running()
    local inst = self:get_instance()
    if inst._queue then
        return inst._queue:is_running()
    end
    return false
end

function BgBuddy:get_status_text()
    local inst = self:get_instance()
    if inst._queue then
        return inst._queue:get_status_text()
    end
    return "Queue manager unavailable"
end

function BgBuddy:destroy()
    local inst = self:get_instance()
    if inst._queue and inst._queue.destroy then
        inst._queue:destroy()
    end
    _instance = nil
end

return BgBuddy
