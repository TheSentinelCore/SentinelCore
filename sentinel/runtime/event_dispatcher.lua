-- sentinel/runtime/event_dispatcher.lua
-- Consumes Bridge semantic events, implements no-polling subscriber model - ADR 002 §10
-- Game → Sylvanas API → EventBridge → EventDispatcher → Subscribers

local EventBridge = require("integrations/sentinel_bridge/event_bridge")

local EventDispatcher = {}
EventDispatcher.__index = EventDispatcher

-- Semantic event types from EventBridge - ADR 009 §6
local SEMANTIC_EVENTS = {
    QUEST_ACCEPTED = "quest_accepted",
    QUEST_COMPLETED = "quest_completed",
    QUEST_ABANDONED = "quest_abandoned",
    INVENTORY_CHANGED = "inventory_changed",
    PLAYER_MOVED = "player_moved",
    PLAYER_STARTED_MOVING = "player_started_moving",
    PLAYER_STOPPED_MOVING = "player_stopped_moving",
    FLIGHT_LEARNED = "flight_learned",
}

---Create a new EventDispatcher
---@param event_bus table The SentinelCore internal event bus
---@param blackboard table The SentinelCore blackboard
---@return table EventDispatcher instance
function EventDispatcher:new(event_bus, blackboard)
    local o = setmetatable({}, EventDispatcher)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._runtime_subs = {}
    o._next_token = 0
    o._last_quest_log = {}
    o._subscription_tokens = {}
    o._sylvannas_tokens = {}
    o._started = false
    return o
end

---Start the dispatcher: subscribe to Bridge semantic events
---@param sentinel_bridge table Optional SentinelBridge for quest log polling
function EventDispatcher:start(sentinel_bridge)
    if self._started then
        return
    end
    self._started = true

    -- Subscribe to Bridge semantic events (no polling model) - ADR 002 §10
    self._subscription_tokens = {}

    -- Subscribe to all semantic events from EventBridge
    for _, event_name in pairs({
        "quest_accepted",
        "quest_completed",
        "quest_abandoned",
        "inventory_changed",
        "player_moved",
        "player_started_moving",
        "player_stopped_moving",
        "flight_learned",
    }) do
        local token = self._event_bus:subscribe(event_name, function(payload)
            self:_dispatch_to_subscribers(event_name, payload)
        end)
        table.insert(self._subscription_tokens, token)
    end

    -- Subscribe to quest log updates for diffing (if sentinel_bridge available)
    if sentinel_bridge and sentinel_bridge._addons then
        local addons = sentinel_bridge._addons
        if addons.on_quest_log_update then
            addons:on_quest_log_update(function(old, new)
                self:_handle_quest_log_diff(old, new)
            end)
        end
    end

    -- Also support legacy Sylvannas event bus subscription for backward compatibility
    self:_subscribe_to_sylvannas_events()
end

---Subscribe to Sylvannas events (legacy backward compatibility)
function EventDispatcher:_subscribe_to_sylvannas_events()
    local core_eb = _G.core and _G.core.event_bus
    if not core_eb then
        return
    end

    -- QUEST_LOG_UPDATE → quest events
    local ok, token = pcall(core_eb.on, core_eb, "QUEST_LOG_UPDATE", function()
        self:_handle_quest_log_update()
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end

    -- UNIT_HEALTH → health_changed
    ok, token = pcall(core_eb.on, core_eb, "UNIT_HEALTH", function(guid, health, max_health)
        self:_dispatch_to_subscribers("health_changed", {
            guid = guid,
            health = health,
            max_health = max_health,
        })
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end

    -- BAG_UPDATE → inventory_changed
    ok, token = pcall(core_eb.on, core_eb, "BAG_UPDATE", function(bag_id)
        self:_dispatch_to_subscribers("inventory_changed", { bag_id = bag_id })
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end

    -- PLAYER_ENTERING_WORLD → zone_entered
    ok, token = pcall(core_eb.on, core_eb, "PLAYER_ENTERING_WORLD", function()
        local zone_name = nil
        local map_id = nil
        if _G.core and _G.core.player then
            local ok2, zone = pcall(_G.core.player.get_zone_name)
            if ok2 then zone_name = zone end
            ok2, map_id = pcall(_G.core.player.get_map_id)
            if not ok2 then map_id = nil end
        end
        self:_dispatch_to_subscribers("zone_entered", { zone_name = zone_name, map_id = map_id })
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end

    -- PLAYER_DEATH → death_event
    ok, token = pcall(core_eb.on, core_eb, "PLAYER_DEATH", function()
        local position = nil
        if _G.core and _G.core.player then
            local ok2, pos = pcall(_G.core.player.get_position)
            if ok2 then position = pos end
        end
        self:_dispatch_to_subscribers("death_event", { position = position, killer_guid = nil })
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end

    -- UNIT_COMBAT → kill_event
    ok, token = pcall(core_eb.on, core_eb, "UNIT_COMBAT", function(creature_entry, x, y, z)
        self:_dispatch_to_subscribers("kill_event", {
            creature_entry = creature_entry,
            position = { x = x, y = y, z = z },
        })
    end)
    if ok then
        table.insert(self._sylvannas_tokens, token)
    end
end

---Stop the dispatcher: unsubscribe all events
function EventDispatcher:stop()
    if not self._started then
        return
    end
    self._started = false

    for _, token in ipairs(self._subscription_tokens) do
        self._event_bus:unsubscribe(token)
    end
    self._subscription_tokens = {}

    local core_eb = _G.core and _G.core.event_bus
    if core_eb then
        for _, token in ipairs(self._sylvannas_tokens) do
            pcall(core_eb.off, core_eb, token)
        end
    end
    self._sylvannas_tokens = {}
end

---Subscribe to a runtime semantic event (primary API)
---@param event_name string The semantic event name
---@param handler function Payload receiver
---@return string token Subscription token for removal
function EventDispatcher:on(event_name, handler, priority)
    self._next_token = self._next_token + 1
    local token = "runtime_sub:" .. tostring(self._next_token)

    if not self._runtime_subs[event_name] then
        self._runtime_subs[event_name] = {}
    end

    table.insert(self._runtime_subs[event_name], {
        token = token,
        handler = handler,
        priority = tonumber(priority) or 50,
    })

    return token
end

---Remove a runtime event subscription by token
---@param token string The token returned from on
---@return boolean success
function EventDispatcher:off(token)
    for event_name, subs in pairs(self._runtime_subs) do
        for i = #subs, 1, -1 do
            if subs[i].token == token then
                table.remove(subs, i)
                if #subs == 0 then
                    self._runtime_subs[event_name] = nil
                end
                return true
            end
        end
    end
    return false
end

---Subscribe to runtime event (legacy API - delegates to on)
---@param event_name string
---@param handler function
---@return string
function EventDispatcher:on_runtime_event(event_name, handler)
    return self:on(event_name, handler)
end

---Remove runtime event subscription by token (legacy API - delegates to off)
---@param token string
---@return boolean
function EventDispatcher:off_runtime_event(token)
    return self:off(token)
end

---Dispatch a semantic event to all subscribers (no-polling model)
---@param event_name string The semantic event name
---@param payload table Event payload
function EventDispatcher:_dispatch_to_subscribers(event_name, payload)
    local subs = self._runtime_subs[event_name]
    if not subs then
        return
    end

    -- Sort by priority, then by token order for deterministic dispatch
    table.sort(subs, function(a, b)
        if a.priority == b.priority then
            return a.token < b.token
        end
        return a.priority < b.priority
    end)

    -- Dispatch to all subscribers
    for _, sub in ipairs(subs) do
        local ok, err = pcall(sub.handler, payload)
        if not ok then
            self:_publish_error(event_name, err)
        end
    end
end

---Handle QUEST_LOG_UPDATE (legacy backward compatibility)
function EventDispatcher:_handle_quest_log_update()
    self:_dispatch_to_subscribers("quest_accepted", { quest_id = nil })
    self:_dispatch_to_subscribers("quest_completed", { quest_id = nil })
    self:_dispatch_to_subscribers("quest_failed", { quest_id = nil })
end

---Handle UNIT_HEALTH (legacy backward compatibility)
---@param guid string|nil Unit GUID
---@param health number|nil Current health
---@param max_health number|nil Maximum health
function EventDispatcher:_handle_unit_health(guid, health, max_health)
    self:_dispatch_to_subscribers("health_changed", {
        guid = guid,
        health = health,
        max_health = max_health,
    })
end

---Handle BAG_UPDATE (legacy backward compatibility)
---@param bag_id number|nil Bag slot ID
function EventDispatcher:_handle_bag_update(bag_id)
    self:_dispatch_to_subscribers("inventory_changed", { bag_id = bag_id })
end

---Handle PLAYER_ENTERING_WORLD (legacy backward compatibility)
function EventDispatcher:_handle_player_entering_world()
    local zone_name = nil
    local map_id = nil

    if _G.core and _G.core.player then
        local ok, zone = pcall(_G.core.player.get_zone_name)
        if ok then zone_name = zone end
        ok, map_id = pcall(_G.core.player.get_map_id)
        if not ok then map_id = nil end
    end

    self:_dispatch_to_subscribers("zone_entered", {
        zone_name = zone_name,
        map_id = map_id,
    })
end

---Handle PLAYER_DEATH (legacy backward compatibility)
function EventDispatcher:_handle_player_death()
    local position = nil
    local killer_guid = nil

    if _G.core and _G.core.player then
        local ok, pos = pcall(_G.core.player.get_position)
        if ok then position = pos end
    end

    self:_dispatch_to_subscribers("death_event", {
        position = position,
        killer_guid = killer_guid,
    })
end

---Handle UNIT_COMBAT (legacy backward compatibility)
---@param creature_entry number|nil Creature template entry ID
---@param x number|nil Position X
---@param y number|nil Position Y
---@param z number|nil Position Z
function EventDispatcher:_handle_unit_combat(creature_entry, x, y, z)
    self:_dispatch_to_subscribers("kill_event", {
        creature_entry = creature_entry,
        position = { x = x, y = y, z = z },
    })
end

---Publish error to system error channel
---@param operation string Operation name
---@param error_str string Error message
function EventDispatcher:_publish_error(operation, error_str)
    if self._event_bus then
        self._event_bus:publish("system:error", {
            module = "event_dispatcher",
            operation = operation,
            error = tostring(error_str),
        })
    end
end

---Subscribe to quest accepted events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_quest_accepted(handler, priority)
    return self:on(SEMANTIC_EVENTS.QUEST_ACCEPTED, handler, priority)
end

---Subscribe to quest completed events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_quest_completed(handler, priority)
    return self:on(SEMANTIC_EVENTS.QUEST_COMPLETED, handler, priority)
end

---Subscribe to quest abandoned events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_quest_abandoned(handler, priority)
    return self:on(SEMANTIC_EVENTS.QUEST_ABANDONED, handler, priority)
end

---Subscribe to inventory changed events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_inventory_changed(handler, priority)
    return self:on(SEMANTIC_EVENTS.INVENTORY_CHANGED, handler, priority)
end

---Subscribe to player moved events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_player_moved(handler, priority)
    return self:on(SEMANTIC_EVENTS.PLAYER_MOVED, handler, priority)
end

---Subscribe to flight learned events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_flight_learned(handler, priority)
    return self:on(SEMANTIC_EVENTS.FLIGHT_LEARNED, handler, priority)
end

---Subscribe to death events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_death_event(handler, priority)
    return self:on("death_event", handler, priority)
end

---Subscribe to kill events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_kill_event(handler, priority)
    return self:on("kill_event", handler, priority)
end

---Subscribe to NPC reached events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_npc_reached(handler, priority)
    return self:on("npc_reached", handler, priority)
end

---Subscribe to vendor visited events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_vendor_visited(handler, priority)
    return self:on("vendor_visited", handler, priority)
end

---Subscribe to action completed events
---@param handler function Payload receiver
---@return string token
function EventDispatcher:on_action_completed(handler, priority)
    return self:on("action_completed", handler, priority)
end

---Get list of active subscriptions
---@return table List of event names with subscriber counts
function EventDispatcher:get_subscription_summary()
    local summary = {}
    for event_name, subs in pairs(self._runtime_subs) do
        summary[event_name] = #subs
    end
    return summary
end

return EventDispatcher