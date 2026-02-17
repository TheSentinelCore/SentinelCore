---@class Subscription
---@field id number Unique subscription ID
---@field event string Event name
---@field callback function Callback function
---@field priority number Execution priority (lower = first)
---@field once boolean If true, unsubscribe after first call
---@field owner string|nil Module name that owns this subscription

---@class EventBus
---@field private _subscriptions table<string, Subscription[]>
---@field private _next_id number
---@field private _paused boolean
---@field private _queued_events table[]
local EventBus = {}
EventBus.__index = EventBus

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("EventBus")
    end
    return nil
end

---Create a new EventBus instance
---@return EventBus
function EventBus:new()
    local instance = setmetatable({}, EventBus)
    instance._subscriptions = {}
    instance._next_id = 1
    instance._paused = false
    instance._queued_events = {}
    instance._log = get_logger()
    return instance
end

---Subscribe to an event
---@param event string Event name
---@param callback function Callback function(data)
---@param priority? number Lower values execute first (default 100)
---@param once? boolean If true, unsubscribe after first call (default false)
---@param owner? string Optional owner identifier for bulk unsubscribe
---@return number subscription_id Unique ID for this subscription
function EventBus:subscribe(event, callback, priority, once, owner)
    if type(event) ~= "string" then
        if self._log then self._log:error("Event name must be a string") end
        return 0
    end

    if type(callback) ~= "function" then
        if self._log then self._log:error("Callback must be a function") end
        return 0
    end

    -- Initialize subscription list for this event if needed
    if not self._subscriptions[event] then
        self._subscriptions[event] = {}
    end

    local id = self._next_id
    self._next_id = self._next_id + 1

    ---@type Subscription
    local subscription = {
        id = id,
        event = event,
        callback = callback,
        priority = priority or 100,
        once = once or false,
        owner = owner
    }

    table.insert(self._subscriptions[event], subscription)

    -- Sort by priority (lower = earlier)
    table.sort(self._subscriptions[event], function(a, b)
        return a.priority < b.priority
    end)

    if self._log then
        self._log:debug("Subscribed to '%s' (id=%d, priority=%d)", event, id, subscription.priority)
    end

    return id
end

---Subscribe to an event for one-time execution
---@param event string Event name
---@param callback function Callback function(data)
---@param priority? number Lower values execute first (default 100)
---@return number subscription_id
function EventBus:once(event, callback, priority)
    return self:subscribe(event, callback, priority, true)
end

---Unsubscribe from an event by subscription ID
---@param subscription_id number The subscription ID to remove
---@return boolean success True if subscription was found and removed
function EventBus:unsubscribe(subscription_id)
    if type(subscription_id) ~= "number" or subscription_id <= 0 then
        return false
    end

    for event, subs in pairs(self._subscriptions) do
        for i, sub in ipairs(subs) do
            if sub.id == subscription_id then
                table.remove(subs, i)
                if self._log then
                    self._log:debug("Unsubscribed from '%s' (id=%d)", event, subscription_id)
                end
                return true
            end
        end
    end

    return false
end

---Unsubscribe all subscriptions by owner
---@param owner string The owner identifier
---@return number count Number of subscriptions removed
function EventBus:unsubscribe_by_owner(owner)
    if type(owner) ~= "string" then
        return 0
    end

    local count = 0
    for event, subs in pairs(self._subscriptions) do
        for i = #subs, 1, -1 do
            if subs[i].owner == owner then
                table.remove(subs, i)
                count = count + 1
            end
        end
    end

    if self._log and count > 0 then
        self._log:debug("Unsubscribed %d subscriptions for owner '%s'", count, owner)
    end

    return count
end

---Unsubscribe all subscriptions for an event
---@param event string The event name
---@return number count Number of subscriptions removed
function EventBus:unsubscribe_all(event)
    if type(event) ~= "string" then
        return 0
    end

    local subs = self._subscriptions[event]
    if not subs then
        return 0
    end

    local count = #subs
    self._subscriptions[event] = {}

    if self._log and count > 0 then
        self._log:debug("Unsubscribed all %d subscriptions for '%s'", count, event)
    end

    return count
end

---Publish an event to all subscribers
---@param event string Event name
---@param data? table Event data passed to callbacks
function EventBus:publish(event, data)
    if type(event) ~= "string" then
        if self._log then self._log:error("Event name must be a string") end
        return
    end

    -- Queue events if paused
    if self._paused then
        table.insert(self._queued_events, { event = event, data = data })
        return
    end

    local subs = self._subscriptions[event]
    if not subs or #subs == 0 then
        return
    end

    -- Collect indices to remove (for once subscriptions)
    local to_remove = {}

    -- Call all subscribers
    for i, sub in ipairs(subs) do
        local success, err = pcall(sub.callback, data)

        if not success then
            if self._log then
                self._log:error("Error in callback for '%s': %s", event, tostring(err))
            else
                core.log_error("[EventBus] Error in " .. event .. ": " .. tostring(err))
            end
        end

        if sub.once then
            table.insert(to_remove, i)
        end
    end

    -- Remove one-time subscriptions (reverse order to maintain indices)
    for i = #to_remove, 1, -1 do
        table.remove(subs, to_remove[i])
    end
end

---Pause event delivery (queue events instead)
function EventBus:pause()
    self._paused = true
    if self._log then
        self._log:debug("Event delivery paused")
    end
end

---Resume event delivery and process queued events
function EventBus:resume()
    self._paused = false

    -- Process queued events
    local queued = self._queued_events
    self._queued_events = {}

    for _, evt in ipairs(queued) do
        self:publish(evt.event, evt.data)
    end

    if self._log then
        self._log:debug("Event delivery resumed, processed %d queued events", #queued)
    end
end

---Check if the event bus is paused
---@return boolean
function EventBus:is_paused()
    return self._paused
end

---Get number of subscribers for an event
---@param event string Event name
---@return number count
function EventBus:subscriber_count(event)
    local subs = self._subscriptions[event]
    return subs and #subs or 0
end

---Get all subscribed event names
---@return string[]
function EventBus:get_events()
    local events = {}
    for event in pairs(self._subscriptions) do
        if #self._subscriptions[event] > 0 then
            table.insert(events, event)
        end
    end
    return events
end

---Clear all subscriptions
function EventBus:clear()
    self._subscriptions = {}
    self._queued_events = {}
    self._paused = false
    if self._log then
        self._log:debug("Cleared all subscriptions")
    end
end

---Run unit tests
---@return table<string, boolean> Test results
function EventBus:_test()
    local results = {}
    local bus = EventBus:new()

    -- Test 1: Basic subscribe/publish
    local received = nil
    local id = bus:subscribe("test:event", function(data)
        received = data.value
    end)
    bus:publish("test:event", { value = 42 })
    results.basic_pubsub = (received == 42)

    -- Test 2: Unsubscribe
    bus:unsubscribe(id)
    received = nil
    bus:publish("test:event", { value = 99 })
    results.unsubscribe = (received == nil)

    -- Test 3: Priority ordering
    local order = {}
    bus:subscribe("test:priority", function() table.insert(order, "B") end, 200)
    bus:subscribe("test:priority", function() table.insert(order, "A") end, 100)
    bus:subscribe("test:priority", function() table.insert(order, "C") end, 300)
    bus:publish("test:priority", {})
    results.priority = (order[1] == "A" and order[2] == "B" and order[3] == "C")

    -- Test 4: Once
    local once_count = 0
    bus:once("test:once", function() once_count = once_count + 1 end)
    bus:publish("test:once", {})
    bus:publish("test:once", {})
    results.once = (once_count == 1)

    -- Test 5: Multiple subscribers
    local multi_count = 0
    bus:subscribe("test:multi", function() multi_count = multi_count + 1 end)
    bus:subscribe("test:multi", function() multi_count = multi_count + 1 end)
    bus:publish("test:multi", {})
    results.multiple_subscribers = (multi_count == 2)

    -- Test 6: Error isolation
    local error_test_ran = false
    bus:subscribe("test:error", function()
        error("Intentional test error")
    end)
    bus:subscribe("test:error", function()
        error_test_ran = true
    end)
    bus:publish("test:error", {})
    results.error_isolation = error_test_ran

    -- Test 7: Subscriber count
    results.subscriber_count = (bus:subscriber_count("test:multi") == 2)

    -- Test 8: Unsubscribe by owner
    bus:subscribe("test:owner", function() end, 100, false, "module_a")
    bus:subscribe("test:owner", function() end, 100, false, "module_a")
    bus:subscribe("test:owner", function() end, 100, false, "module_b")
    local removed = bus:unsubscribe_by_owner("module_a")
    results.unsubscribe_by_owner = (removed == 2 and bus:subscriber_count("test:owner") == 1)

    -- Test 9: Pause/Resume
    local pause_received = false
    bus:subscribe("test:pause", function() pause_received = true end)
    bus:pause()
    bus:publish("test:pause", {})
    local paused_correct = (pause_received == false)
    bus:resume()
    local resumed_correct = (pause_received == true)
    results.pause_resume = (paused_correct and resumed_correct)

    -- Test 10: Clear
    bus:subscribe("test:clear", function() end)
    bus:clear()
    results.clear = (bus:subscriber_count("test:clear") == 0)

    return results
end

return EventBus
