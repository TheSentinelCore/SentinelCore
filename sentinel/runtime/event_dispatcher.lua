-- sentinel/runtime/event_dispatcher.lua
-- Maps Sylvannas game events to runtime events.
-- Listens on the Sylvannas core.event_bus and re-dispatches as runtime events
-- on the internal event_bus with structured payloads.

local EventDispatcher = {}
EventDispatcher.__index = EventDispatcher

---Create a new EventDispatcher
---@param event_bus table The SentinelCore internal event bus
---@param blackboard table The SentinelCore blackboard
---@return table EventDispatcher instance
function EventDispatcher:new(event_bus, blackboard)
    local o = setmetatable({}, EventDispatcher)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._sylvannas_tokens = {}  -- tokens from Sylvannas core.event_bus subscriptions
    o._runtime_subs = {}      -- { token = handler } for runtime event subscriptions
    o._next_token = 0
    o._started = false
    return o
end

---Start the dispatcher: subscribe to Sylvannas events
---Uses pcall to gracefully skip missing Sylvannas events
function EventDispatcher:start()
    if self._started then
        return
    end

    local core_eb = _G.core and _G.core.event_bus
    if not core_eb then
        -- No Sylvannas event bus available; silently skip
        self._started = true
        return
    end

    local tokens = {}

    -- QUEST_LOG_UPDATE → "quest_accepted" / "quest_completed" / "quest_failed"
    local ok, token = pcall(core_eb.on, core_eb, "QUEST_LOG_UPDATE", function()
        self:_handle_quest_log_update()
    end)
    if ok then
        table.insert(tokens, token)
    end

    -- UNIT_HEALTH → "health_changed"
    ok, token = pcall(core_eb.on, core_eb, "UNIT_HEALTH", function(guid, health, max_health)
        self:_handle_unit_health(guid, health, max_health)
    end)
    if ok then
        table.insert(tokens, token)
    end

    -- BAG_UPDATE → "inventory_changed"
    ok, token = pcall(core_eb.on, core_eb, "BAG_UPDATE", function(bag_id)
        self:_handle_bag_update(bag_id)
    end)
    if ok then
        table.insert(tokens, token)
    end

    -- PLAYER_ENTERING_WORLD → "zone_entered"
    ok, token = pcall(core_eb.on, core_eb, "PLAYER_ENTERING_WORLD", function()
        self:_handle_player_entering_world()
    end)
    if ok then
        table.insert(tokens, token)
    end

    -- PLAYER_DEATH → "death_event"
    ok, token = pcall(core_eb.on, core_eb, "PLAYER_DEATH", function()
        self:_handle_player_death()
    end)
    if ok then
        table.insert(tokens, token)
    end

    -- UNIT_COMBAT → "kill_event"
    ok, token = pcall(core_eb.on, core_eb, "UNIT_COMBAT", function(creature_entry, x, y, z)
        self:_handle_unit_combat(creature_entry, x, y, z)
    end)
    if ok then
        table.insert(tokens, token)
    end

    self._sylvannas_tokens = tokens
    self._started = true
end

---Stop the dispatcher: unsubscribe all Sylvannas events
function EventDispatcher:stop()
    if not self._started then
        return
    end

    local core_eb = _G.core and _G.core.event_bus
    if core_eb then
        for _, token in ipairs(self._sylvannas_tokens) do
            pcall(core_eb.off, core_eb, token)
        end
    end

    self._sylvannas_tokens = {}
    self._started = false
end

---Subscribe to a runtime event
---@param event_name string The runtime event name
---@param handler function Payload receiver
---@return string token Subscription token for removal
function EventDispatcher:on_runtime_event(event_name, handler)
    self._next_token = self._next_token + 1
    local token = "runtime_sub:" .. tostring(self._next_token)

    if not self._runtime_subs[event_name] then
        self._runtime_subs[event_name] = {}
    end

    table.insert(self._runtime_subs[event_name], {
        token = token,
        handler = handler,
    })

    return token
end

---Remove a runtime event subscription by token
---@param token string The token returned from on_runtime_event
---@return boolean success
function EventDispatcher:off_runtime_event(token)
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

---Publish a runtime event to subscribers
---@param event_name string
---@param payload table
function EventDispatcher:_publish_runtime(event_name, payload)
    local subs = self._runtime_subs[event_name]
    if not subs then
        return
    end

    -- Snapshot to avoid mutation during iteration
    local snapshot = {}
    for i, sub in ipairs(subs) do
        snapshot[i] = sub
    end

    for _, sub in ipairs(snapshot) do
        local ok, err = pcall(sub.handler, payload)
        if not ok and self._event_bus then
            self._event_bus:publish("system:error", {
                module = "event_dispatcher",
                operation = event_name,
                error = tostring(err),
            })
        end
    end
end

---Handle QUEST_LOG_UPDATE: determine what changed
function EventDispatcher:_handle_quest_log_update()
    -- Sylvannas doesn't always tell us WHAT changed,
    -- so we publish all three events and let logic sort it out
    -- with a best-guess: publish "quest_accepted" as the primary signal.
    -- In practice, the subscriber checks quest log state.
    self:_publish_runtime("quest_accepted", { quest_id = nil })
    self:_publish_runtime("quest_completed", { quest_id = nil })
    self:_publish_runtime("quest_failed", { quest_id = nil })
end

---Handle UNIT_HEALTH
---@param guid string|nil Unit GUID
---@param health number|nil Current health
---@param max_health number|nil Maximum health
function EventDispatcher:_handle_unit_health(guid, health, max_health)
    self:_publish_runtime("health_changed", {
        guid = guid,
        health = health,
        max_health = max_health,
    })
end

---Handle BAG_UPDATE
---@param bag_id number|nil Bag slot ID
function EventDispatcher:_handle_bag_update(bag_id)
    self:_publish_runtime("inventory_changed", {
        bag_id = bag_id,
    })
end

---Handle PLAYER_ENTERING_WORLD
function EventDispatcher:_handle_player_entering_world()
    local zone_name = nil
    local map_id = nil

    if _G.core and _G.core.player then
        -- Try to get zone info from player state
        local ok, zone = pcall(_G.core.player.get_zone_name)
        if ok then
            zone_name = zone
        end
        ok, map_id = pcall(_G.core.player.get_map_id)
        if not ok then
            map_id = nil
        end
    end

    self:_publish_runtime("zone_entered", {
        zone_name = zone_name,
        map_id = map_id,
    })
end

---Handle PLAYER_DEATH
function EventDispatcher:_handle_player_death()
    local position = nil
    local killer_guid = nil

    if _G.core and _G.core.player then
        local ok, pos = pcall(_G.core.player.get_position)
        if ok then
            position = pos
        end
    end

    self:_publish_runtime("death_event", {
        position = position,
        killer_guid = killer_guid,
    })
end

---Handle UNIT_COMBAT
---@param creature_entry number|nil Creature template entry ID
---@param x number|nil Position X
---@param y number|nil Position Y
---@param z number|nil Position Z
function EventDispatcher:_handle_unit_combat(creature_entry, x, y, z)
    self:_publish_runtime("kill_event", {
        creature_entry = creature_entry,
        position = { x = x, y = y, z = z },
    })
end

return EventDispatcher
