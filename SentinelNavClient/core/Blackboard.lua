-- Blackboard.lua
-- Centralized key-value data store with local watchers and optional EventBus integration.
-- Fires "bb.<key>" events on the EventBus when values change.

local BB_PREFIX = "bb."

---@class Blackboard
---@field private _data table         Key-value store
---@field private _watchers table     Per-key callback lists
---@field private _event_bus table?   Optional EventBus for broadcasting changes
local Blackboard = {}
Blackboard.__index = Blackboard

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

---Create a new Blackboard instance.
---@param event_bus? table  EventBus with :emit(event, data) method; optional
---@return Blackboard
function Blackboard:new(event_bus)
    local o = setmetatable({}, Blackboard)
    o._data      = {}
    o._watchers  = {}
    o._event_bus = event_bus or nil
    return o
end

--------------------------------------------------------------------------------
-- Core API
--------------------------------------------------------------------------------

---Get a value by key, returning `default` if not present.
---@param key string
---@param default? any
---@return any
function Blackboard:get(key, default)
    local v = self._data[key]
    if v == nil then
        return default
    end
    return v
end

---Set a value. No-ops if the value is identical (avoids infinite loops).
---Fires local watchers and EventBus event when the value actually changes.
---@param key string
---@param value any
function Blackboard:set(key, value)
    local old = self._data[key]
    if old == value and type(value) ~= "table" then return end

    self._data[key] = value

    -- Fire local watchers
    local list = self._watchers[key]
    if list then
        for i = 1, #list do
            local ok, err = pcall(list[i], key, value, old)
            if not ok and core and core.log_error then
                core.log_error("[SentinelNavClient] Blackboard watcher error for '"
                    .. tostring(key) .. "': " .. tostring(err))
            end
        end
    end

    -- Fire EventBus event
    if self._event_bus then
        self._event_bus:emit(BB_PREFIX .. key, {
            key = key,
            new_value = value,
            old_value = old,
        })
    end
end

---Check whether a key exists in the store.
---@param key string
---@return boolean
function Blackboard:has(key)
    return self._data[key] ~= nil
end

---Clear a single key, or all keys if `key` is nil.
---Fires change events for each cleared key that had a value.
---@param key? string  Key to clear; omit to clear everything
function Blackboard:clear(key)
    if key ~= nil then
        -- Single key
        if self._data[key] ~= nil then
            local old = self._data[key]
            self._data[key] = nil

            -- Fire local watchers
            local list = self._watchers[key]
            if list then
                for i = 1, #list do
                    local ok, err = pcall(list[i], key, nil, old)
                    if not ok and core and core.log_error then
                        core.log_error("[SentinelNavClient] Blackboard watcher error for '"
                            .. tostring(key) .. "': " .. tostring(err))
                    end
                end
            end

            -- Fire EventBus event
            if self._event_bus then
                self._event_bus:emit(BB_PREFIX .. key, {
                    key = key,
                    new_value = nil,
                    old_value = old,
                })
            end
        end
    else
        -- Clear all: collect keys first to avoid mutation during iteration
        local all_keys = {}
        for k in pairs(self._data) do
            all_keys[#all_keys + 1] = k
        end
        for _, k in ipairs(all_keys) do
            self:clear(k)
        end
    end
end

---Subscribe a local watcher for a specific key.
---Callback signature: `function(key, new_value, old_value)`
---@param key string
---@param callback fun(key: string, new_value: any, old_value: any)
function Blackboard:subscribe(key, callback)
    if not self._watchers[key] then
        self._watchers[key] = {}
    end
    local list = self._watchers[key]
    list[#list + 1] = callback
end

---Remove a local watcher for a specific key.
---@param key string
---@param callback function
function Blackboard:unsubscribe(key, callback)
    local list = self._watchers[key]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

---Return an array of all keys currently stored.
---@return string[]
function Blackboard:keys()
    local result = {}
    for k in pairs(self._data) do
        result[#result + 1] = k
    end
    return result
end

---Return a shallow copy of all stored data.
---@return table
function Blackboard:snapshot()
    local copy = {}
    for k, v in pairs(self._data) do
        copy[k] = v
    end
    return copy
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function Blackboard._test()
    local pass, fail = 0, 0
    local function check(name, condition)
        if condition then
            pass = pass + 1
        else
            fail = fail + 1
            local msg = "[Blackboard._test] FAIL: " .. name
            if core and core.log_error then
                core.log_error(msg)
            else
                print(msg)
            end
        end
    end

    local log = (core and core.log) or print

    --------------------------------------------------------------------------
    -- 1. Basic get/set
    --------------------------------------------------------------------------
    local bb = Blackboard:new()
    bb:set("hp", 100)
    check("set/get returns value", bb:get("hp") == 100)

    --------------------------------------------------------------------------
    -- 2. Default value for missing keys
    --------------------------------------------------------------------------
    check("get missing returns default", bb:get("mana", 50) == 50)
    check("get missing returns nil without default", bb:get("mana") == nil)

    --------------------------------------------------------------------------
    -- 3. has() true/false
    --------------------------------------------------------------------------
    check("has() true for existing key", bb:has("hp") == true)
    check("has() false for missing key", bb:has("mana") == false)

    --------------------------------------------------------------------------
    -- 4. Clear single key
    --------------------------------------------------------------------------
    bb:set("armor", 200)
    check("pre-clear has armor", bb:has("armor") == true)
    bb:clear("armor")
    check("clear single key removes it", bb:has("armor") == false)
    check("clear single key get returns nil", bb:get("armor") == nil)

    --------------------------------------------------------------------------
    -- 5. Subscribe fires on change
    --------------------------------------------------------------------------
    local watch_calls = 0
    local watch_key, watch_new, watch_old
    local function watcher(k, nv, ov)
        watch_calls = watch_calls + 1
        watch_key = k
        watch_new = nv
        watch_old = ov
    end
    bb:subscribe("hp", watcher)
    bb:set("hp", 80)
    check("subscribe fires on change", watch_calls == 1)
    check("watcher receives correct key", watch_key == "hp")
    check("watcher receives new value", watch_new == 80)
    check("watcher receives old value", watch_old == 100)

    --------------------------------------------------------------------------
    -- 6. No-op on same value (watcher should NOT fire twice)
    --------------------------------------------------------------------------
    bb:set("hp", 80) -- same value again
    check("no-op on same value, watcher not fired again", watch_calls == 1)

    --------------------------------------------------------------------------
    -- 7. EventBus integration
    --------------------------------------------------------------------------
    -- Minimal EventBus from require
    local EventBus = require("events/EventBus")
    local eb = EventBus:new()
    local bb2 = Blackboard:new(eb)

    local bus_calls = 0
    local bus_key, bus_new, bus_old
    eb:on("bb.score", function(data)
        bus_calls = bus_calls + 1
        bus_key = data and data.key
        bus_new = data and data.new_value
        bus_old = data and data.old_value
    end)

    bb2:set("score", 42)
    check("EventBus fires on set", bus_calls == 1)
    check("EventBus receives correct key", bus_key == "score")
    check("EventBus receives new value", bus_new == 42)
    check("EventBus receives old value", bus_old == nil)

    bb2:set("score", 42) -- no-op
    check("EventBus not fired on same value", bus_calls == 1)

    --------------------------------------------------------------------------
    -- 8. Snapshot returns copy
    --------------------------------------------------------------------------
    local bb3 = Blackboard:new()
    bb3:set("a", 1)
    bb3:set("b", 2)
    local snap = bb3:snapshot()
    check("snapshot has key a", snap.a == 1)
    check("snapshot has key b", snap.b == 2)
    snap.a = 999
    check("snapshot is a copy, original unchanged", bb3:get("a") == 1)

    --------------------------------------------------------------------------
    -- Unsubscribe verification
    --------------------------------------------------------------------------
    bb:unsubscribe("hp", watcher)
    bb:set("hp", 50)
    check("unsubscribe prevents further calls", watch_calls == 1)

    --------------------------------------------------------------------------
    -- keys() verification
    --------------------------------------------------------------------------
    local bb4 = Blackboard:new()
    bb4:set("x", 10)
    bb4:set("y", 20)
    bb4:set("z", 30)
    local k = bb4:keys()
    check("keys() returns correct count", #k == 3)

    --------------------------------------------------------------------------
    -- Clear all
    --------------------------------------------------------------------------
    bb4:clear()
    check("clear() all removes everything", #bb4:keys() == 0)

    --------------------------------------------------------------------------
    -- Summary
    --------------------------------------------------------------------------
    local total = pass + fail
    local summary = string.format("[Blackboard._test] %d/%d passed", pass, total)
    if fail > 0 then
        summary = summary .. string.format(" (%d FAILED)", fail)
    end
    log(summary)

    return fail == 0
end

return Blackboard
