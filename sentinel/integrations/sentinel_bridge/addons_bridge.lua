-- sentinel/integrations/sentinel_bridge/addons_bridge.lua
-- Unit query and position bridge to Sylvanas core API
-- Implements AddonsClientTrait - ADR 009 §5

local BridgeError = require("integrations/sentinel_bridge/bridge_error")
local AddonsClientTrait = require("integrations/sentinel_bridge/addons_client_trait")

local AddonsBridge = {}
AddonsBridge.__index = AddonsBridge

setmetatable(AddonsBridge, { __index = AddonsClientTrait })

---Create a new AddonsBridge
---@param event_bus table SentinelCore event bus
---@return table AddonsBridge instance
function AddonsBridge:new(event_bus)
    local o = setmetatable({}, AddonsBridge)
    o._event_bus = event_bus
    o._event_bridge = nil
    o._subscriptions = {}
    return o
end

---Set the EventBridge for event translation
---@param event_bridge table EventBridge instance
function AddonsBridge:set_event_bridge(event_bridge)
    self._event_bridge = event_bridge
end

---Subscribe to game events
---@param event_name string Event name
---@param handler function Handler function
---@return string subscription_id
function AddonsBridge:subscribe(event_name, handler)
    if not core or not core.register_on_game_event_callback then
        return ""
    end

    local id = tostring(event_name) .. "_" .. tostring(os.time())

    self._subscriptions[id] = {
        event = event_name,
        handler = handler,
    }

    if not self._event_router_registered then
        self._event_router_registered = true
        core.register_on_game_event_callback(function(eventName, args)
            self:_route_event(eventName, args)
        end)
    end

    return id
end

---Unsubscribe from a game event
---@param subscription_id string Subscription to remove
function AddonsBridge:unsubscribe(subscription_id)
    self._subscriptions[subscription_id] = nil
end

---Get the currently targeted unit
---@return table|nil unit
function AddonsBridge:current_target()
    local ok, unit = pcall(function()
        if core and core.object_manager then
            return core.object_manager.get_target()
        end
        return nil
    end)
    return ok and unit or nil
end

---Get the local player position
---@return table position Waypoint
function AddonsBridge:player_position()
    local ok, pos = pcall(function()
        if core and core.object_manager then
            local player = core.object_manager.get_local_player()
            if player and player.get_position then
                return player:get_position()
            end
        end
        return nil
    end)

    if ok and pos then
        return {
            x = pos.x or 0,
            y = pos.y or 0,
            z = pos.z or 0,
        }
    end
    return { x = 0, y = 0, z = 0 }
end

---Get nearby units within radius
---@param radius number Search radius in yards
---@return table units Array of units
function AddonsBridge:nearby_units(radius)
    local units = {}
    radius = tonumber(radius) or 40

    if core and core.object_manager then
        local ok, list = pcall(function()
            return core.object_manager.get_units_around_player(radius)
        end)
        if ok and type(list) == "table" then
            units = list
        end
    end

    return units
end

---Get nearby game objects within radius
---@param radius number Search radius in yards
---@return table objects Array of game objects
function AddonsBridge:nearby_game_objects(radius)
    local objects = {}
    radius = tonumber(radius) or 40

    if core and core.object_manager then
        local ok, list = pcall(function()
            return core.object_manager.get_game_objects_around_player(radius)
        end)
        if ok and type(list) == "table" then
            objects = list
        end
    end

    return objects
end

---Get detailed info about a unit
---@param unit table Unit handle
---@return table info UnitInfo
function AddonsBridge:unit_info(unit)
    local info = {
        guid = "",
        npc_id = 0,
        name = "",
        level = 0,
        position = { x = 0, y = 0, z = 0 },
        is_dead = false,
        is_vendor = false,
        is_quest_giver = false,
    }

    if not unit or type(unit) ~= "table" then
        return info
    end

    local function safe_call(method, obj)
        local ok, result = pcall(method, obj)
        return ok and result
    end

    info.guid = safe_call(function(u) return u:get_guid() end, unit) or ""
    info.npc_id = safe_call(function(u) return u:get_npc_id() end, unit) or 0
    info.name = safe_call(function(u) return u:get_name() end, unit) or ""
    info.level = safe_call(function(u) return u:get_level() end, unit) or 0
    info.position = safe_call(function(u) return u:get_position() end, unit) or { x = 0, y = 0, z = 0 }
    info.is_dead = safe_call(function(u) return u:is_dead() end, unit) or false
    info.is_vendor = safe_call(function(u) return u:is_vendor() end, unit) or false
    info.is_quest_giver = safe_call(function(u) return u:is_quest_unit() end, unit) or false

    return info
end

---Internal event router - forwards raw events to EventBridge for translation
---@param event_name string Raw event name
---@param args table Event arguments
function AddonsBridge:_route_event(event_name, args)
    for id, sub in pairs(self._subscriptions or {}) do
        if sub.event == event_name then
            sub.handler(args)
        end
    end

    local EventBridge = require("integrations/sentinel_bridge/event_bridge")
    local semantic, _ = EventBridge.translate_event(event_name, args)
    if semantic and self._event_bridge then
        self._event_bridge:handle_event(event_name, args)
    end
end

---Poll for quest log state - returns current state for EventBridge to diff
---@return table current_quests { [quest_id] = is_complete }
function AddonsBridge:poll_quest_log()
    if not core or not core.quests then
        return {}
    end

    local current_quests = {}
    if core.game_ui.get_quest_log_count then
        local ok, count = pcall(core.game_ui.get_quest_log_count)
        if ok and type(count) == "number" then
            for i = 1, math.min(count, 50) do
                local ok2, info = pcall(function()
                    return core.quests.get_quest_log_title(i)
                end)
                if ok2 and info and not info.is_header then
                    current_quests[info.quest_id] = info.is_complete == 1
                end
            end
        end
    end

    return current_quests
end

---Get all completed quest IDs
---@return table quest_ids
function AddonsBridge:get_completed_quest_ids()
    local ids = {}

    if core and core.game_ui and type(core.game_ui.get_all_completed_quest_ids) == "function" then
        local ok, list = pcall(core.game_ui.get_all_completed_quest_ids)
        if ok and type(list) == "table" then
            ids = list
        end
    end

    return ids
end

return AddonsBridge