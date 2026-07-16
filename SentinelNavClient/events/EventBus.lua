-- EventBus.lua
-- Priority-based event system with pattern matching, owner cleanup, and pause/resume.
-- Lua 5.1 compatible.

---@class EventBusSub
---@field id       number   Unique subscription ID
---@field callback function Handler function
---@field priority number   Lower = runs first (default 50)
---@field once     boolean  Auto-remove after first fire
---@field owner    any      Optional owner for bulk cleanup
---@field pattern  string|nil Lua pattern (for wildcard subscriptions)

---@class EventBus
---@field _subs       table<string, EventBusSub[]>  Event name -> sorted subscriber list
---@field _patterns   EventBusSub[]                 Pattern-based subscribers
---@field _next_id    number                        Auto-incrementing subscription ID
---@field _paused     boolean                       Whether emits are queued
---@field _queue      table[]                       Queued {event, data} while paused
---@field _id_index   table<number, EventBusSub>    Fast lookup by subscription ID
local EventBus = {}
EventBus.__index = EventBus

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a new EventBus instance.
---@return EventBus
function EventBus:new()
    local o = setmetatable({}, EventBus)
    o._subs     = {}
    o._patterns = {}
    o._next_id  = 0
    o._paused   = false
    o._queue    = {}
    o._id_index = {}
    return o
end

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

---Allocate the next unique subscription ID.
---@return number
function EventBus:_alloc_id()
    self._next_id = self._next_id + 1
    return self._next_id
end

---Convert a glob pattern (e.g. "nav.*") to a Lua pattern.
---Anchors with ^ and $. Escapes Lua magic characters, then replaces
---glob wildcards: "*" -> ".*" and "?" -> ".".
---@param glob string
---@return string
local function glob_to_pattern(glob)
    -- Escape Lua magic chars (except * and ? which we handle specially)
    local escaped = glob:gsub("([%^%$%(%)%%%.%[%]%+%-])", "%%%1")
    -- Convert glob wildcards
    escaped = escaped:gsub("%*", ".*")
    escaped = escaped:gsub("%?", ".")
    return "^" .. escaped .. "$"
end

---Insert a subscriber into a sorted list (by priority ascending).
---Uses binary search for O(log n) insertion.
---@param list EventBusSub[]
---@param sub  EventBusSub
local function insert_sorted(list, sub)
    local lo, hi = 1, #list
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if list[mid].priority <= sub.priority then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    table.insert(list, lo, sub)
end

--------------------------------------------------------------------------------
-- Subscribe
--------------------------------------------------------------------------------

---Subscribe to an event.
---@param event    string   Event name
---@param callback function Handler: fn(data, event_name)
---@param opts?    table    { priority=50, once=false, owner=nil }
---@return number  Subscription ID
function EventBus:on(event, callback, opts)
    opts = opts or {}
    local sub = {
        id       = self:_alloc_id(),
        callback = callback,
        priority = opts.priority or 50,
        once     = opts.once or false,
        owner    = opts.owner,
        pattern  = nil,
        event    = event,
    }

    if not self._subs[event] then
        self._subs[event] = {}
    end
    insert_sorted(self._subs[event], sub)
    self._id_index[sub.id] = sub
    return sub.id
end

---Subscribe to an event, auto-removed after the first fire.
---@param event    string   Event name
---@param callback function Handler: fn(data, event_name)
---@param opts?    table    { priority=50, owner=nil }
---@return number  Subscription ID
function EventBus:once(event, callback, opts)
    opts = opts or {}
    opts.once = true
    return self:on(event, callback, opts)
end

---Subscribe to events matching a glob pattern.
---Pattern is tested against the event name on each emit.
---@param pattern  string   Glob pattern (e.g. "nav.*")
---@param callback function Handler: fn(data, event_name)
---@param opts?    table    { priority=50, once=false, owner=nil }
---@return number  Subscription ID
function EventBus:on_pattern(pattern, callback, opts)
    opts = opts or {}
    local sub = {
        id       = self:_alloc_id(),
        callback = callback,
        priority = opts.priority or 50,
        once     = opts.once or false,
        owner    = opts.owner,
        pattern  = glob_to_pattern(pattern),
        event    = nil,
    }
    insert_sorted(self._patterns, sub)
    self._id_index[sub.id] = sub
    return sub.id
end

--------------------------------------------------------------------------------
-- Unsubscribe
--------------------------------------------------------------------------------

---Remove a subscription by ID, or by event+callback.
---When called with a number, removes that subscription ID.
---When called with (event_name, callback_fn), removes matching entries.
---@param event_or_id string|number Event name or subscription ID
---@param callback?   function      Required when event_or_id is a string
---@return boolean True if at least one subscription was removed
function EventBus:off(event_or_id, callback)
    if type(event_or_id) == "number" then
        return self:_off_by_id(event_or_id)
    end

    -- Remove by event + callback
    local event = event_or_id
    local list = self._subs[event]
    if not list then return false end

    local removed = false
    for i = #list, 1, -1 do
        if list[i].callback == callback then
            self._id_index[list[i].id] = nil
            table.remove(list, i)
            removed = true
        end
    end
    return removed
end

---Remove a subscription by its unique ID.
---@param id number
---@return boolean
function EventBus:_off_by_id(id)
    local sub = self._id_index[id]
    if not sub then return false end
    self._id_index[id] = nil

    -- Check pattern list
    if sub.pattern then
        for i = #self._patterns, 1, -1 do
            if self._patterns[i].id == id then
                table.remove(self._patterns, i)
                return true
            end
        end
        return false
    end

    -- Check event list
    local list = self._subs[sub.event]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i].id == id then
            table.remove(list, i)
            return true
        end
    end
    return false
end

---Remove all subscriptions belonging to a given owner.
---@param owner any
---@return number Count of subscriptions removed
function EventBus:off_owner(owner)
    local count = 0

    -- Scan event subscriptions
    for _, list in pairs(self._subs) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                self._id_index[list[i].id] = nil
                table.remove(list, i)
                count = count + 1
            end
        end
    end

    -- Scan pattern subscriptions
    for i = #self._patterns, 1, -1 do
        if self._patterns[i].owner == owner then
            self._id_index[self._patterns[i].id] = nil
            table.remove(self._patterns, i)
            count = count + 1
        end
    end

    return count
end

--------------------------------------------------------------------------------
-- Emit
--------------------------------------------------------------------------------

---Emit an event. Fires all direct subscribers and matching pattern subscribers,
---sorted by priority (lower first). Errors in handlers are isolated via pcall.
---When paused, events are queued for later delivery.
---@param event string Event name
---@param data  any    Payload passed to handlers
function EventBus:emit(event, data)
    if self._paused then
        self._queue[#self._queue + 1] = { event = event, data = data }
        return
    end

    -- Collect all matching subscribers into a single list for unified priority sort
    local handlers = {}

    -- Direct subscribers
    local list = self._subs[event]
    if list then
        for i = 1, #list do
            handlers[#handlers + 1] = list[i]
        end
    end

    -- Pattern subscribers
    for i = 1, #self._patterns do
        local psub = self._patterns[i]
        if event:match(psub.pattern) then
            handlers[#handlers + 1] = psub
        end
    end

    -- Sort merged list by priority (stable-ish: same priority preserves insertion order
    -- from each source, but interleaving between direct and pattern is by priority)
    table.sort(handlers, function(a, b)
        if a.priority == b.priority then
            return a.id < b.id
        end
        return a.priority < b.priority
    end)

    -- Fire
    local to_remove = {}
    for i = 1, #handlers do
        local sub = handlers[i]
        local ok, err = pcall(sub.callback, data, event)
        if not ok then
            -- Guard: core.log_error may not exist (e.g. in test context)
            if core and core.log_error then
                core.log_error("[EventBus] Handler error on '" .. event .. "': " .. tostring(err))
            end
        end
        if sub.once then
            to_remove[#to_remove + 1] = sub.id
        end
    end

    -- Cleanup once subscribers
    for i = 1, #to_remove do
        self:_off_by_id(to_remove[i])
    end
end

--------------------------------------------------------------------------------
-- Pause / Resume
--------------------------------------------------------------------------------

---Pause event delivery. Subsequent emits are queued.
function EventBus:pause()
    self._paused = true
end

---Resume event delivery. Drains the queued events in order.
function EventBus:resume()
    self._paused = false
    -- Drain queue (take a snapshot in case handlers emit more events)
    while #self._queue > 0 do
        local queued = self._queue
        self._queue = {}
        for i = 1, #queued do
            self:emit(queued[i].event, queued[i].data)
        end
    end
end

---Check whether the bus is paused.
---@return boolean
function EventBus:is_paused()
    return self._paused
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

---Count subscribers for a specific event (direct only, not patterns).
---@param event string
---@return number
function EventBus:subscriber_count(event)
    local list = self._subs[event]
    if not list then return 0 end
    return #list
end

---Reset the bus: remove all subscriptions, clear queue, unpause.
function EventBus:clear()
    self._subs     = {}
    self._patterns = {}
    self._queue    = {}
    self._paused   = false
    self._id_index = {}
    -- Note: _next_id is NOT reset so IDs remain globally unique within lifetime
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

---Run comprehensive unit tests.
---@return table<string, boolean> Test results keyed by name
function EventBus._test()
    local results = {}

    --------------------------------------------------------------------------
    -- 1. Basic emit/on
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local received = nil
        bus:on("ping", function(data) received = data end)
        bus:emit("ping", "hello")
        results.basic_emit = (received == "hello")
    end

    do
        local bus = EventBus:new()
        local count = 0
        bus:on("tick", function() count = count + 1 end)
        bus:emit("tick")
        bus:emit("tick")
        bus:emit("tick")
        results.basic_multi_emit = (count == 3)
    end

    do
        local bus = EventBus:new()
        local a_val, b_val = nil, nil
        bus:on("x", function(d) a_val = d end)
        bus:on("x", function(d) b_val = d end)
        bus:emit("x", 42)
        results.basic_multi_sub = (a_val == 42 and b_val == 42)
    end

    --------------------------------------------------------------------------
    -- 2. Priority ordering
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local order = {}
        bus:on("evt", function() order[#order + 1] = "c" end, { priority = 99 })
        bus:on("evt", function() order[#order + 1] = "a" end, { priority = 1 })
        bus:on("evt", function() order[#order + 1] = "b" end, { priority = 50 })
        bus:emit("evt")
        results.priority_order = (order[1] == "a" and order[2] == "b" and order[3] == "c")
    end

    do
        local bus = EventBus:new()
        local order = {}
        bus:on("evt", function() order[#order + 1] = "first" end, { priority = 10 })
        bus:on("evt", function() order[#order + 1] = "second" end, { priority = 10 })
        bus:emit("evt")
        results.priority_stable = (order[1] == "first" and order[2] == "second")
    end

    --------------------------------------------------------------------------
    -- 3. Once fires once
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local count = 0
        bus:once("flash", function() count = count + 1 end)
        bus:emit("flash")
        bus:emit("flash")
        bus:emit("flash")
        results.once_fires_once = (count == 1)
    end

    do
        local bus = EventBus:new()
        local count = 0
        bus:once("flash", function() count = count + 1 end)
        bus:emit("flash")
        results.once_removes_sub = (bus:subscriber_count("flash") == 0)
    end

    --------------------------------------------------------------------------
    -- 4. Owner cleanup
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local owner_a = { name = "moduleA" }
        local owner_b = { name = "moduleB" }
        local count_a, count_b = 0, 0

        bus:on("evt", function() count_a = count_a + 1 end, { owner = owner_a })
        bus:on("evt", function() count_a = count_a + 1 end, { owner = owner_a })
        bus:on("evt", function() count_b = count_b + 1 end, { owner = owner_b })

        local removed = bus:off_owner(owner_a)
        bus:emit("evt")
        results.owner_cleanup_count = (removed == 2)
        results.owner_cleanup_fires = (count_a == 0 and count_b == 1)
    end

    do
        local bus = EventBus:new()
        local owner = {}
        bus:on("a", function() end, { owner = owner })
        bus:on_pattern("b.*", function() end, { owner = owner })
        local removed = bus:off_owner(owner)
        results.owner_cleanup_patterns = (removed == 2)
    end

    --------------------------------------------------------------------------
    -- 5. Pattern matching
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local received = {}
        bus:on_pattern("nav.*", function(data, event)
            received[#received + 1] = event
        end)
        bus:emit("nav.arrived")
        bus:emit("nav.failed")
        bus:emit("combat.start")
        results.pattern_match = (#received == 2
            and received[1] == "nav.arrived"
            and received[2] == "nav.failed")
    end

    do
        local bus = EventBus:new()
        local count = 0
        bus:on_pattern("*", function() count = count + 1 end)
        bus:emit("anything")
        bus:emit("something.else")
        results.pattern_wildcard_all = (count == 2)
    end

    do
        local bus = EventBus:new()
        local order = {}
        bus:on("nav.arrived", function() order[#order + 1] = "direct" end, { priority = 10 })
        bus:on_pattern("nav.*", function() order[#order + 1] = "pattern" end, { priority = 20 })
        bus:emit("nav.arrived")
        results.pattern_priority_with_direct = (order[1] == "direct" and order[2] == "pattern")
    end

    --------------------------------------------------------------------------
    -- 6. Error isolation
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local after_error = false
        bus:on("boom", function() error("kaboom!") end, { priority = 1 })
        bus:on("boom", function() after_error = true end, { priority = 2 })
        bus:emit("boom")
        results.error_isolation = (after_error == true)
    end

    --------------------------------------------------------------------------
    -- 7. Pause/resume queuing
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local received = {}

        bus:on("msg", function(data) received[#received + 1] = data end)

        results.pause_not_paused_initially = (bus:is_paused() == false)

        bus:pause()
        results.pause_is_paused = (bus:is_paused() == true)

        bus:emit("msg", "a")
        bus:emit("msg", "b")
        results.pause_no_delivery = (#received == 0)

        bus:resume()
        results.pause_resume_delivers = (#received == 2
            and received[1] == "a"
            and received[2] == "b")
        results.pause_resume_unpauses = (bus:is_paused() == false)
    end

    do
        local bus = EventBus:new()
        local received = {}
        bus:on("a", function()
            received[#received + 1] = "a"
            bus:emit("b", nil)
        end)
        bus:on("b", function()
            received[#received + 1] = "b"
        end)
        bus:pause()
        bus:emit("a")
        bus:resume()
        results.pause_cascading = (#received == 2
            and received[1] == "a"
            and received[2] == "b")
    end

    --------------------------------------------------------------------------
    -- 8. Off by ID
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local count = 0
        local id = bus:on("evt", function() count = count + 1 end)
        bus:emit("evt")
        local removed = bus:off(id)
        bus:emit("evt")
        results.off_by_id = (count == 1 and removed == true)
    end

    do
        local bus = EventBus:new()
        local removed = bus:off(99999)
        results.off_by_id_missing = (removed == false)
    end

    do
        local bus = EventBus:new()
        local count = 0
        local id = bus:on_pattern("x.*", function() count = count + 1 end)
        bus:emit("x.y")
        bus:off(id)
        bus:emit("x.y")
        results.off_by_id_pattern = (count == 1)
    end

    --------------------------------------------------------------------------
    -- Off by event + callback
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local count = 0
        local function handler() count = count + 1 end
        bus:on("evt", handler)
        bus:emit("evt")
        local removed = bus:off("evt", handler)
        bus:emit("evt")
        results.off_by_event_cb = (count == 1 and removed == true)
    end

    --------------------------------------------------------------------------
    -- subscriber_count
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        results.sub_count_empty = (bus:subscriber_count("nope") == 0)
        bus:on("evt", function() end)
        bus:on("evt", function() end)
        results.sub_count = (bus:subscriber_count("evt") == 2)
    end

    --------------------------------------------------------------------------
    -- clear
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        bus:on("a", function() end)
        bus:on("b", function() end)
        bus:on_pattern("c.*", function() end)
        bus:pause()
        bus:emit("a", 1)
        bus:clear()
        results.clear_subs = (bus:subscriber_count("a") == 0 and bus:subscriber_count("b") == 0)
        results.clear_unpauses = (bus:is_paused() == false)
    end

    --------------------------------------------------------------------------
    -- Event data passed correctly
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local got_data, got_event = nil, nil
        bus:on("test", function(data, event)
            got_data = data
            got_event = event
        end)
        bus:emit("test", { value = 123 })
        results.data_and_event_name = (got_data.value == 123 and got_event == "test")
    end

    --------------------------------------------------------------------------
    -- Pattern receives event name
    --------------------------------------------------------------------------
    do
        local bus = EventBus:new()
        local got_event = nil
        bus:on_pattern("ns.*", function(_, event) got_event = event end)
        bus:emit("ns.foo")
        results.pattern_receives_event = (got_event == "ns.foo")
    end

    return results
end

return EventBus
