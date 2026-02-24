local BT = {}

BT.Status = {
    SUCCESS = "success",
    FAILURE = "failure",
    RUNNING = "running",
}

local S = BT.Status

--------------------------------------------------------------------------------
-- Base Node
--------------------------------------------------------------------------------

local Node = {}
Node.__index = Node

function Node:new(name)
    return setmetatable({ name = name or "node" }, self)
end

function Node:tick() return S.FAILURE end
function Node:reset() end

--------------------------------------------------------------------------------
-- Action: leaf node that runs a function
--------------------------------------------------------------------------------

BT.Action = setmetatable({}, { __index = Node })
BT.Action.__index = BT.Action

function BT.Action:new(name, fn)
    local o = Node.new(self, name)
    o._fn = fn
    return o
end

function BT.Action:tick()
    return self._fn()
end

--------------------------------------------------------------------------------
-- Condition: leaf that returns SUCCESS if predicate is true
--------------------------------------------------------------------------------

BT.Condition = setmetatable({}, { __index = Node })
BT.Condition.__index = BT.Condition

function BT.Condition:new(name, predicate)
    local o = Node.new(self, name)
    o._predicate = predicate
    return o
end

function BT.Condition:tick()
    return self._predicate() and S.SUCCESS or S.FAILURE
end

--------------------------------------------------------------------------------
-- Sequence: runs children in order, fails on first FAILURE
--------------------------------------------------------------------------------

BT.Sequence = setmetatable({}, { __index = Node })
BT.Sequence.__index = BT.Sequence

function BT.Sequence:new(name, children)
    local o = Node.new(self, name)
    o._children = children or {}
    o._running_idx = 1
    return o
end

function BT.Sequence:tick()
    for i = self._running_idx, #self._children do
        local status = self._children[i]:tick()
        if status == S.RUNNING then
            self._running_idx = i
            return S.RUNNING
        elseif status == S.FAILURE then
            self._running_idx = 1
            return S.FAILURE
        end
    end
    self._running_idx = 1
    return S.SUCCESS
end

function BT.Sequence:reset()
    self._running_idx = 1
    for i = 1, #self._children do
        self._children[i]:reset()
    end
end

--------------------------------------------------------------------------------
-- Selector: runs children in order, succeeds on first SUCCESS
--------------------------------------------------------------------------------

BT.Selector = setmetatable({}, { __index = Node })
BT.Selector.__index = BT.Selector

function BT.Selector:new(name, children)
    local o = Node.new(self, name)
    o._children = children or {}
    o._running_idx = 1
    return o
end

function BT.Selector:tick()
    for i = self._running_idx, #self._children do
        local status = self._children[i]:tick()
        if status == S.RUNNING then
            self._running_idx = i
            return S.RUNNING
        elseif status == S.SUCCESS then
            self._running_idx = 1
            return S.SUCCESS
        end
    end
    self._running_idx = 1
    return S.FAILURE
end

function BT.Selector:reset()
    self._running_idx = 1
    for i = 1, #self._children do
        self._children[i]:reset()
    end
end

--------------------------------------------------------------------------------
-- Decorators
--------------------------------------------------------------------------------

-- Inverter: flips SUCCESS <-> FAILURE, passes RUNNING through
BT.Inverter = setmetatable({}, { __index = Node })
BT.Inverter.__index = BT.Inverter

function BT.Inverter:new(name, child)
    local o = Node.new(self, name)
    o._child = child
    return o
end

function BT.Inverter:tick()
    local s = self._child:tick()
    if s == S.SUCCESS then return S.FAILURE end
    if s == S.FAILURE then return S.SUCCESS end
    return S.RUNNING
end

function BT.Inverter:reset() self._child:reset() end

-- RepeatUntilSuccess: re-ticks child each frame until SUCCESS
BT.RepeatUntilSuccess = setmetatable({}, { __index = Node })
BT.RepeatUntilSuccess.__index = BT.RepeatUntilSuccess

function BT.RepeatUntilSuccess:new(name, child)
    local o = Node.new(self, name)
    o._child = child
    return o
end

function BT.RepeatUntilSuccess:tick()
    local s = self._child:tick()
    if s == S.SUCCESS then return S.SUCCESS end
    return S.RUNNING
end

function BT.RepeatUntilSuccess:reset() self._child:reset() end

-- Timeout: fails if child runs longer than duration
BT.Timeout = setmetatable({}, { __index = Node })
BT.Timeout.__index = BT.Timeout

function BT.Timeout:new(name, duration_sec, child, time_fn)
    local o = Node.new(self, name)
    o._child = child
    o._duration = duration_sec
    o._time_fn = time_fn or function() return core and core.time() or 0 end
    o._start_time = nil
    return o
end

function BT.Timeout:tick()
    local now = self._time_fn()
    if not self._start_time then
        self._start_time = now
    end
    if now - self._start_time >= self._duration then
        self._start_time = nil
        return S.FAILURE
    end
    local s = self._child:tick()
    if s ~= S.RUNNING then
        self._start_time = nil
    end
    return s
end

function BT.Timeout:reset()
    self._start_time = nil
    self._child:reset()
end

-- Cooldown: after child succeeds, blocks re-execution for N seconds
BT.Cooldown = setmetatable({}, { __index = Node })
BT.Cooldown.__index = BT.Cooldown

function BT.Cooldown:new(name, cooldown_sec, child, time_fn)
    local o = Node.new(self, name)
    o._child = child
    o._cooldown = cooldown_sec
    o._time_fn = time_fn or function() return core and core.time() or 0 end
    o._last_success = -math.huge
    return o
end

function BT.Cooldown:tick()
    local now = self._time_fn()
    if now - self._last_success < self._cooldown then
        return S.FAILURE
    end
    local s = self._child:tick()
    if s == S.SUCCESS then
        self._last_success = now
    end
    return s
end

function BT.Cooldown:reset()
    self._last_success = -math.huge
    self._child:reset()
end

--------------------------------------------------------------------------------
-- Reactive composites: re-evaluate from child 1 every tick.
-- Use these when conditions can change between ticks (combat state, death, etc).
-- Standard Sequence/Selector with _running_idx "memory" should only be used
-- for multi-step procedures that must not restart (e.g. sequential actions).
--------------------------------------------------------------------------------

-- ReactiveSequence: re-evaluates ALL children from index 1 every tick.
-- If a previously-succeeded condition now fails, returns FAILURE immediately
-- and resets whatever child was previously RUNNING.
BT.ReactiveSequence = setmetatable({}, { __index = Node })
BT.ReactiveSequence.__index = BT.ReactiveSequence

function BT.ReactiveSequence:new(name, children)
    local o = Node.new(self, name)
    o._children = children or {}
    o._running_idx = nil
    return o
end

function BT.ReactiveSequence:tick()
    for i = 1, #self._children do
        local status = self._children[i]:tick()
        if status == S.FAILURE then
            if self._running_idx and self._running_idx ~= i then
                self._children[self._running_idx]:reset()
            end
            self._running_idx = nil
            return S.FAILURE
        elseif status == S.RUNNING then
            if self._running_idx and self._running_idx ~= i then
                self._children[self._running_idx]:reset()
            end
            self._running_idx = i
            return S.RUNNING
        end
    end
    self._running_idx = nil
    return S.SUCCESS
end

function BT.ReactiveSequence:reset()
    if self._running_idx then
        self._children[self._running_idx]:reset()
    end
    self._running_idx = nil
end

-- ReactiveSelector: re-evaluates ALL children from index 1 every tick.
-- Higher-priority children preempt lower ones. If child 1 was FAILURE last
-- tick but now returns SUCCESS, it preempts whatever lower child was RUNNING.
BT.ReactiveSelector = setmetatable({}, { __index = Node })
BT.ReactiveSelector.__index = BT.ReactiveSelector

function BT.ReactiveSelector:new(name, children)
    local o = Node.new(self, name)
    o._children = children or {}
    o._running_idx = nil
    return o
end

function BT.ReactiveSelector:tick()
    for i = 1, #self._children do
        local status = self._children[i]:tick()
        if status == S.SUCCESS then
            if self._running_idx and self._running_idx ~= i then
                self._children[self._running_idx]:reset()
            end
            self._running_idx = nil
            return S.SUCCESS
        elseif status == S.RUNNING then
            if self._running_idx and self._running_idx ~= i then
                self._children[self._running_idx]:reset()
            end
            self._running_idx = i
            return S.RUNNING
        end
    end
    self._running_idx = nil
    return S.FAILURE
end

function BT.ReactiveSelector:reset()
    if self._running_idx then
        self._children[self._running_idx]:reset()
    end
    self._running_idx = nil
end

return BT
