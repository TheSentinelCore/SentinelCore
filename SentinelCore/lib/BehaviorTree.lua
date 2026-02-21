-- BehaviorTree.lua
-- Full-featured Behavior Tree engine for SentinelNavClient.
-- Lua 5.1 compatible. All node types use metatables inheriting from base Node.

local BT = {}

--------------------------------------------------------------------------------
-- Status constants
--------------------------------------------------------------------------------

BT.SUCCESS = "success"
BT.FAILURE = "failure"
BT.RUNNING = "running"

--------------------------------------------------------------------------------
-- Node (base class)
--------------------------------------------------------------------------------

local Node = {}
Node.__index = Node

---Create a new base node.
---@param name? string  Human-readable label for debugging
---@return Node
function Node:new(name)
    local o    = setmetatable({}, self)
    o.name     = name or "Node"
    o.children = {}
    return o
end

---Add a child node. Returns self for fluent chaining.
---@param child Node
---@return Node self
function Node:add(child)
    self.children[#self.children + 1] = child
    return self
end

---Tick the node. Override in subclasses.
---@param bb Blackboard
---@param dt number  Delta time in seconds
---@return string status  BT.SUCCESS, BT.FAILURE, or BT.RUNNING
function Node:tick(bb, dt)
    return BT.FAILURE
end

---Reset the node and all children to their initial state.
function Node:reset()
    for i = 1, #self.children do
        self.children[i]:reset()
    end
end

BT.Node = Node

--------------------------------------------------------------------------------
-- Sequence
-- Runs children left-to-right. Fails on first FAILURE. Returns RUNNING if any
-- child returns RUNNING (remembers index to resume). Succeeds when all succeed.
--------------------------------------------------------------------------------

local Sequence = setmetatable({}, { __index = Node })
Sequence.__index = Sequence

function Sequence:new(name)
    local o = Node.new(self, name or "Sequence")
    o._running_index = 1
    return o
end

function Sequence:tick(bb, dt)
    local start = self._running_index
    for i = start, #self.children do
        local status = self.children[i]:tick(bb, dt)
        if status == BT.FAILURE then
            self._running_index = 1
            return BT.FAILURE
        elseif status == BT.RUNNING then
            self._running_index = i
            return BT.RUNNING
        end
        -- BT.SUCCESS: continue to next child
    end
    self._running_index = 1
    return BT.SUCCESS
end

function Sequence:reset()
    self._running_index = 1
    Node.reset(self)
end

BT.Sequence = Sequence

--------------------------------------------------------------------------------
-- ReactiveSequence
-- Like Sequence but always re-evaluates from child 1 every tick. If a guard
-- (early child) fails, resets any previously RUNNING later child.
-- Use this when guard conditions must be checked every frame.
--------------------------------------------------------------------------------

local ReactiveSequence = setmetatable({}, { __index = Node })
ReactiveSequence.__index = ReactiveSequence

function ReactiveSequence:new(name)
    local o = Node.new(self, name or "ReactiveSequence")
    o._running_index = nil
    return o
end

function ReactiveSequence:tick(bb, dt)
    for i = 1, #self.children do
        local status = self.children[i]:tick(bb, dt)
        if status == BT.RUNNING then
            -- Preempt previously running child if a different one is now running
            if self._running_index and self._running_index ~= i then
                self.children[self._running_index]:reset()
            end
            self._running_index = i
            return BT.RUNNING
        elseif status == BT.FAILURE then
            -- Reset previously running child
            if self._running_index then
                self.children[self._running_index]:reset()
                self._running_index = nil
            end
            return BT.FAILURE
        end
        -- BT.SUCCESS: continue to next child
    end
    self._running_index = nil
    return BT.SUCCESS
end

function ReactiveSequence:reset()
    self._running_index = nil
    Node.reset(self)
end

BT.ReactiveSequence = ReactiveSequence

--------------------------------------------------------------------------------
-- Selector
-- Runs children left-to-right. Succeeds on first SUCCESS. Returns RUNNING if
-- any child returns RUNNING (remembers index). Fails when all fail.
--------------------------------------------------------------------------------

local Selector = setmetatable({}, { __index = Node })
Selector.__index = Selector

function Selector:new(name)
    local o = Node.new(self, name or "Selector")
    o._running_index = 1
    return o
end

function Selector:tick(bb, dt)
    local start = self._running_index
    for i = start, #self.children do
        local status = self.children[i]:tick(bb, dt)
        if status == BT.SUCCESS then
            self._running_index = 1
            return BT.SUCCESS
        elseif status == BT.RUNNING then
            self._running_index = i
            return BT.RUNNING
        end
        -- BT.FAILURE: continue to next child
    end
    self._running_index = 1
    return BT.FAILURE
end

function Selector:reset()
    self._running_index = 1
    Node.reset(self)
end

BT.Selector = Selector

--------------------------------------------------------------------------------
-- Parallel
-- Runs ALL children each tick.
-- Policy "require_one": succeed if any child returns SUCCESS.
-- Policy "require_all": succeed only if all children return SUCCESS.
--------------------------------------------------------------------------------

local Parallel = setmetatable({}, { __index = Node })
Parallel.__index = Parallel

---@param policy? string  "require_one" (default) or "require_all"
---@param name? string
function Parallel:new(policy, name)
    local o = Node.new(self, name or "Parallel")
    o.policy = policy or "require_one"
    return o
end

function Parallel:tick(bb, dt)
    local success_count = 0
    local failure_count = 0
    local total = #self.children

    for i = 1, total do
        local status = self.children[i]:tick(bb, dt)
        if status == BT.SUCCESS then
            success_count = success_count + 1
        elseif status == BT.FAILURE then
            failure_count = failure_count + 1
        end
        -- BT.RUNNING: neither success nor failure
    end

    if self.policy == "require_one" then
        if success_count > 0 then
            return BT.SUCCESS
        elseif failure_count == total then
            return BT.FAILURE
        else
            return BT.RUNNING
        end
    else -- "require_all"
        if success_count == total then
            return BT.SUCCESS
        elseif failure_count > 0 then
            return BT.FAILURE
        else
            return BT.RUNNING
        end
    end
end

BT.Parallel = Parallel

--------------------------------------------------------------------------------
-- Inverter (decorator)
-- Wraps one child. Flips SUCCESS <-> FAILURE, passes RUNNING through.
--------------------------------------------------------------------------------

local Inverter = setmetatable({}, { __index = Node })
Inverter.__index = Inverter

function Inverter:new(child, name)
    local o = Node.new(self, name or "Inverter")
    if child then
        o:add(child)
    end
    return o
end

function Inverter:tick(bb, dt)
    local child = self.children[1]
    if not child then return BT.FAILURE end

    local status = child:tick(bb, dt)
    if status == BT.SUCCESS then
        return BT.FAILURE
    elseif status == BT.FAILURE then
        return BT.SUCCESS
    end
    return BT.RUNNING
end

BT.Inverter = Inverter

--------------------------------------------------------------------------------
-- Repeater (decorator)
-- Wraps one child. Re-runs up to max_count times. Returns FAILURE immediately
-- if child fails. Returns RUNNING if more iterations needed.
--------------------------------------------------------------------------------

local Repeater = setmetatable({}, { __index = Node })
Repeater.__index = Repeater

---@param child Node
---@param max_count number  Maximum iterations
---@param name? string
function Repeater:new(child, max_count, name)
    local o     = Node.new(self, name or "Repeater")
    o.max_count = max_count or 1
    o._count    = 0
    if child then
        o:add(child)
    end
    return o
end

function Repeater:tick(bb, dt)
    local child = self.children[1]
    if not child then return BT.FAILURE end

    local status = child:tick(bb, dt)
    if status == BT.FAILURE then
        self._count = 0
        return BT.FAILURE
    end

    if status == BT.SUCCESS then
        self._count = self._count + 1
        if self._count >= self.max_count then
            self._count = 0
            return BT.SUCCESS
        end
        return BT.RUNNING
    end

    -- BT.RUNNING from child
    return BT.RUNNING
end

function Repeater:reset()
    self._count = 0
    Node.reset(self)
end

BT.Repeater = Repeater

--------------------------------------------------------------------------------
-- Condition (leaf)
-- Takes check_fn(blackboard) -> boolean. Returns SUCCESS if true, FAILURE if
-- false. Uses pcall for safety.
--------------------------------------------------------------------------------

local Condition = setmetatable({}, { __index = Node })
Condition.__index = Condition

---@param check_fn fun(bb: Blackboard): boolean
---@param name? string
function Condition:new(check_fn, name)
    local o = Node.new(self, name or "Condition")
    o._check_fn = check_fn
    return o
end

function Condition:tick(bb, dt)
    local ok, result = pcall(self._check_fn, bb)
    if not ok then
        core.log_error("[BT] Condition '" .. self.name .. "' error: " .. tostring(result))
        return BT.FAILURE
    end
    if result then return BT.SUCCESS end
    return BT.FAILURE
end

BT.Condition = Condition

--------------------------------------------------------------------------------
-- Action (leaf)
-- Takes execute_fn(blackboard, dt) -> BT.SUCCESS|FAILURE|RUNNING.
-- Uses pcall for safety; returns FAILURE on error.
--------------------------------------------------------------------------------

local Action = setmetatable({}, { __index = Node })
Action.__index = Action

---@param execute_fn fun(bb: Blackboard, dt: number): string
---@param name? string
function Action:new(execute_fn, name)
    local o = Node.new(self, name or "Action")
    o._execute_fn = execute_fn
    return o
end

function Action:tick(bb, dt)
    local ok, result = pcall(self._execute_fn, bb, dt)
    if not ok then
        core.log_error("[BT] Action '" .. self.name .. "' error: " .. tostring(result))
        return BT.FAILURE
    end
    return result
end

BT.Action = Action

--------------------------------------------------------------------------------
-- Throttle (decorator)
-- Wraps one child. Only ticks child if interval_sec has elapsed since last tick.
-- Reads _time from blackboard. Returns RUNNING if skipping (not time yet).
-- IMPORTANT: Always re-ticks a RUNNING child regardless of interval.
--------------------------------------------------------------------------------

local Throttle = setmetatable({}, { __index = Node })
Throttle.__index = Throttle

---@param child Node
---@param interval_sec number  Minimum seconds between ticks
---@param name? string
---@param bb_key? string  Optional bb key to read dynamic interval
function Throttle:new(child, interval_sec, name, bb_key)
    local o         = Node.new(self, name or "Throttle")
    o.interval_sec  = interval_sec or 1.0
    o._bb_key       = bb_key
    o._last_tick_at = nil
    o._child_running = false
    if child then
        o:add(child)
    end
    return o
end

function Throttle:tick(bb, dt)
    local child = self.children[1]
    if not child then return BT.FAILURE end

    -- Always re-tick a RUNNING child regardless of interval
    if self._child_running then
        local status = child:tick(bb, dt)
        if status ~= BT.RUNNING then
            self._child_running = false
        end
        return status
    end

    local interval = self._bb_key and bb:get(self._bb_key, self.interval_sec) or self.interval_sec
    local now = bb:get("_time", 0)

    if self._last_tick_at ~= nil then
        local elapsed = now - self._last_tick_at
        if elapsed < interval then
            return BT.RUNNING
        end
    end

    self._last_tick_at = now
    local status = child:tick(bb, dt)
    if status == BT.RUNNING then
        self._child_running = true
    end
    return status
end

function Throttle:reset()
    self._last_tick_at = nil
    self._child_running = false
    Node.reset(self)
end

BT.Throttle = Throttle

--------------------------------------------------------------------------------
-- Cooldown (decorator)
-- Wraps one child. Blocks re-execution for cooldown_sec after last run.
-- Returns FAILURE if on cooldown. Reads _time from blackboard.
-- IMPORTANT: Always re-ticks a RUNNING child regardless of cooldown.
--------------------------------------------------------------------------------

local Cooldown = setmetatable({}, { __index = Node })
Cooldown.__index = Cooldown

---@param child Node
---@param cooldown_sec number  Seconds to block after last execution
---@param name? string
---@param bb_key? string Optional bb key to read dynamic cooldown
function Cooldown:new(child, cooldown_sec, name, bb_key)
    local o        = Node.new(self, name or "Cooldown")
    o.cooldown_sec = cooldown_sec or 1.0
    o._bb_key      = bb_key
    o._last_run_at = nil
    o._child_running = false
    if child then
        o:add(child)
    end
    return o
end

function Cooldown:tick(bb, dt)
    local child = self.children[1]
    if not child then return BT.FAILURE end

    -- Always re-tick a RUNNING child regardless of cooldown
    if self._child_running then
        local status = child:tick(bb, dt)
        if status ~= BT.RUNNING then
            self._child_running = false
        end
        return status
    end

    local cooldown = self._bb_key and bb:get(self._bb_key, self.cooldown_sec) or self.cooldown_sec
    local now = bb:get("_time", 0)

    if self._last_run_at ~= nil then
        local elapsed = now - self._last_run_at
        if elapsed < cooldown then
            return BT.FAILURE
        end
    end

    self._last_run_at = now
    local status = child:tick(bb, dt)
    if status == BT.RUNNING then
        self._child_running = true
    end
    return status
end

function Cooldown:reset()
    self._last_run_at = nil
    self._child_running = false
    Node.reset(self)
end

BT.Cooldown = Cooldown

--------------------------------------------------------------------------------
-- GuardState (decorator)
-- Wraps one child. Only ticks if bb:get("hsm.state") matches required_state.
-- required_state can be a string or a table of strings. Returns FAILURE if
-- the current state does not match.
--------------------------------------------------------------------------------

local GuardState = setmetatable({}, { __index = Node })
GuardState.__index = GuardState

---@param child Node
---@param required_state string|string[]  State(s) that allow execution
---@param name? string
function GuardState:new(child, required_state, name)
    local o = Node.new(self, name or "GuardState")
    o.required_state = required_state
    if child then
        o:add(child)
    end
    return o
end

function GuardState:tick(bb, dt)
    local child = self.children[1]
    if not child then return BT.FAILURE end

    local current = bb:get("hsm.state")
    if current == nil then return BT.FAILURE end

    local allowed = false
    if type(self.required_state) == "table" then
        for i = 1, #self.required_state do
            if self.required_state[i] == current then
                allowed = true
                break
            end
        end
    else
        allowed = (self.required_state == current)
    end

    if not allowed then
        return BT.FAILURE
    end

    return child:tick(bb, dt)
end

BT.GuardState = GuardState

--------------------------------------------------------------------------------
-- Tree (runner)
-- Wraps a root node. Provides tick(), get_last_status(), reset().
--------------------------------------------------------------------------------

local Tree = {}
Tree.__index = Tree

---@param root Node       The root node of the behavior tree
---@param name? string    Human-readable tree name
---@return Tree
function Tree:new(root, name)
    local o        = setmetatable({}, Tree)
    o.root         = root
    o.name         = name or "Tree"
    o._last_status = nil
    return o
end

---Tick the tree.
---@param blackboard Blackboard
---@param dt number  Delta time in seconds
---@return string status
function Tree:tick(blackboard, dt)
    if not self.root then
        self._last_status = BT.FAILURE
        return BT.FAILURE
    end
    self._last_status = self.root:tick(blackboard, dt)
    return self._last_status
end

---Return the status from the last tick, or nil if never ticked.
---@return string|nil
function Tree:get_last_status()
    return self._last_status
end

---Reset the tree and its entire subtree.
function Tree:reset()
    self._last_status = nil
    if self.root then
        self.root:reset()
    end
end

BT.Tree = Tree

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function BT._test()
    local Blackboard = require("core/Blackboard")

    local pass, fail = 0, 0
    local function check(name, condition)
        if condition then
            pass = pass + 1
        else
            fail = fail + 1
            local msg = "[BehaviorTree._test] FAIL: " .. name
            if core and core.log_error then
                core.log_error(msg)
            else
                print(msg)
            end
        end
    end

    local log = (core and core.log) or print

    --------------------------------------------------------------------------
    -- 1. Sequence all success -> SUCCESS
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local seq = Sequence:new("seq_all_ok")
        seq:add(Action:new(function() return BT.SUCCESS end, "a1"))
        seq:add(Action:new(function() return BT.SUCCESS end, "a2"))
        seq:add(Action:new(function() return BT.SUCCESS end, "a3"))

        local result = seq:tick(bb, 0.016)
        check("1. Sequence all success -> SUCCESS", result == BT.SUCCESS)
    end

    --------------------------------------------------------------------------
    -- 2. Sequence fails on first failure
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local call_count = 0
        local seq = Sequence:new("seq_fail")
        seq:add(Action:new(function()
            call_count = call_count + 1
            return BT.SUCCESS
        end, "a1"))
        seq:add(Action:new(function()
            call_count = call_count + 1
            return BT.FAILURE
        end, "a2_fails"))
        seq:add(Action:new(function()
            call_count = call_count + 1
            return BT.SUCCESS
        end, "a3_never"))

        local result = seq:tick(bb, 0.016)
        check("2. Sequence fails on first failure", result == BT.FAILURE)
        check("2b. Sequence stops after failure (ran 2, not 3)", call_count == 2)
    end

    --------------------------------------------------------------------------
    -- 3. Selector succeeds on first success
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local call_count = 0
        local sel = Selector:new("sel_ok")
        sel:add(Action:new(function()
            call_count = call_count + 1
            return BT.FAILURE
        end, "a1_fails"))
        sel:add(Action:new(function()
            call_count = call_count + 1
            return BT.SUCCESS
        end, "a2_ok"))
        sel:add(Action:new(function()
            call_count = call_count + 1
            return BT.SUCCESS
        end, "a3_never"))

        local result = sel:tick(bb, 0.016)
        check("3. Selector succeeds on first success", result == BT.SUCCESS)
        check("3b. Selector stops after success (ran 2, not 3)", call_count == 2)
    end

    --------------------------------------------------------------------------
    -- 4. Inverter flips SUCCESS to FAILURE
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local inv_to_fail = Inverter:new(
            Action:new(function() return BT.SUCCESS end, "ok"),
            "inv_s2f"
        )
        local inv_to_ok = Inverter:new(
            Action:new(function() return BT.FAILURE end, "fail"),
            "inv_f2s"
        )
        local inv_running = Inverter:new(
            Action:new(function() return BT.RUNNING end, "run"),
            "inv_run"
        )

        check("4a. Inverter SUCCESS -> FAILURE",
            inv_to_fail:tick(bb, 0.016) == BT.FAILURE)
        check("4b. Inverter FAILURE -> SUCCESS",
            inv_to_ok:tick(bb, 0.016) == BT.SUCCESS)
        check("4c. Inverter RUNNING passes through",
            inv_running:tick(bb, 0.016) == BT.RUNNING)
    end

    --------------------------------------------------------------------------
    -- 5. Condition reads blackboard (health check)
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        bb:set("health", 80)

        local is_healthy = Condition:new(function(b)
            return b:get("health", 0) > 50
        end, "is_healthy")

        local is_critical = Condition:new(function(b)
            return b:get("health", 0) < 20
        end, "is_critical")

        check("5a. Condition true -> SUCCESS",
            is_healthy:tick(bb, 0.016) == BT.SUCCESS)
        check("5b. Condition false -> FAILURE",
            is_critical:tick(bb, 0.016) == BT.FAILURE)

        -- Test pcall safety: function that throws
        local bad_cond = Condition:new(function()
            error("intentional test error")
        end, "bad_cond")
        check("5c. Condition error -> FAILURE (pcall safety)",
            bad_cond:tick(bb, 0.016) == BT.FAILURE)
    end

    --------------------------------------------------------------------------
    -- 6. Throttle skips before interval elapsed
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local tick_count = 0
        local child_action = Action:new(function()
            tick_count = tick_count + 1
            return BT.SUCCESS
        end, "throttled_action")

        local throttled = Throttle:new(child_action, 1.0, "throttle_1s")

        -- First tick at time 0: should execute
        bb:set("_time", 0)
        local r1 = throttled:tick(bb, 0.016)
        check("6a. Throttle first tick executes child", tick_count == 1)
        check("6b. Throttle first tick returns child result", r1 == BT.SUCCESS)

        -- Second tick at time 0.5: should skip (returns RUNNING)
        bb:set("_time", 0.5)
        local r2 = throttled:tick(bb, 0.016)
        check("6c. Throttle skips before interval", tick_count == 1)
        check("6d. Throttle returns RUNNING when skipping", r2 == BT.RUNNING)

        -- Third tick at time 1.5: should execute again
        bb:set("_time", 1.5)
        local r3 = throttled:tick(bb, 0.016)
        check("6e. Throttle executes after interval", tick_count == 2)
        check("6f. Throttle returns child result after interval", r3 == BT.SUCCESS)
    end

    --------------------------------------------------------------------------
    -- 6b. Throttle continues ticking RUNNING child
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local tick_count = 0
        local child_returns = BT.RUNNING

        local child = Action:new(function()
            tick_count = tick_count + 1
            return child_returns
        end, "running_action")

        local throttled = Throttle:new(child, 2.0, "throttle_running")

        -- Tick 1 at t=0: interval elapsed, tick child -> RUNNING
        bb:set("_time", 0)
        local r1 = throttled:tick(bb, 0.016)
        check("6b1. Throttle ticks child on first tick", tick_count == 1)
        check("6b2. Throttle returns RUNNING from child", r1 == BT.RUNNING)

        -- Tick 2 at t=0.1: interval NOT elapsed, but child was RUNNING -> must re-tick
        bb:set("_time", 0.1)
        local r2 = throttled:tick(bb, 0.016)
        check("6b3. Throttle re-ticks RUNNING child despite interval", tick_count == 2)
        check("6b4. Throttle still returns RUNNING", r2 == BT.RUNNING)

        -- Tick 3 at t=0.2: child completes
        child_returns = BT.SUCCESS
        bb:set("_time", 0.2)
        local r3 = throttled:tick(bb, 0.016)
        check("6b5. Throttle ticks child to completion", tick_count == 3)
        check("6b6. Throttle returns SUCCESS when child completes", r3 == BT.SUCCESS)

        -- Tick 4 at t=0.3: child done, interval not elapsed -> skip
        tick_count = 0
        bb:set("_time", 0.3)
        local r4 = throttled:tick(bb, 0.016)
        check("6b7. Throttle skips after RUNNING child completes", tick_count == 0)
        check("6b8. Throttle returns RUNNING when skipping", r4 == BT.RUNNING)
    end

    --------------------------------------------------------------------------
    -- 6c. Cooldown continues ticking RUNNING child
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local tick_count = 0
        local child_returns = BT.RUNNING

        local child = Action:new(function()
            tick_count = tick_count + 1
            return child_returns
        end, "cd_running_action")

        local cooled = Cooldown:new(child, 2.0, "cooldown_running")

        -- Tick 1 at t=0: not on cooldown, tick child -> RUNNING
        bb:set("_time", 0)
        local r1 = cooled:tick(bb, 0.016)
        check("6c1. Cooldown ticks child when not on cooldown", tick_count == 1)
        check("6c2. Cooldown returns RUNNING from child", r1 == BT.RUNNING)

        -- Tick 2 at t=0.1: on cooldown, but child was RUNNING -> must re-tick
        bb:set("_time", 0.1)
        local r2 = cooled:tick(bb, 0.016)
        check("6c3. Cooldown re-ticks RUNNING child despite cooldown", tick_count == 2)
        check("6c4. Cooldown still returns RUNNING", r2 == BT.RUNNING)

        -- Tick 3 at t=0.2: child completes
        child_returns = BT.SUCCESS
        bb:set("_time", 0.2)
        local r3 = cooled:tick(bb, 0.016)
        check("6c5. Cooldown ticks child to completion", tick_count == 3)
        check("6c6. Cooldown returns SUCCESS when child completes", r3 == BT.SUCCESS)

        -- Tick 4 at t=0.3: cooldown active, child done -> block
        tick_count = 0
        bb:set("_time", 0.3)
        local r4 = cooled:tick(bb, 0.016)
        check("6c7. Cooldown blocks after child completes", tick_count == 0)
        check("6c8. Cooldown returns FAILURE when on cooldown", r4 == BT.FAILURE)
    end

    --------------------------------------------------------------------------
    -- 7. Sequence with RUNNING resumes at correct child
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local a1_count, a2_count, a3_count = 0, 0, 0
        local a2_returns = BT.RUNNING -- will change between ticks

        local seq = Sequence:new("seq_running")
        seq:add(Action:new(function()
            a1_count = a1_count + 1
            return BT.SUCCESS
        end, "a1"))
        seq:add(Action:new(function()
            a2_count = a2_count + 1
            return a2_returns
        end, "a2_may_run"))
        seq:add(Action:new(function()
            a3_count = a3_count + 1
            return BT.SUCCESS
        end, "a3"))

        -- Tick 1: a1 succeeds, a2 returns RUNNING -> sequence RUNNING
        local r1 = seq:tick(bb, 0.016)
        check("7a. Sequence returns RUNNING when child RUNNING", r1 == BT.RUNNING)
        check("7b. Child 1 ran once", a1_count == 1)
        check("7c. Child 2 ran once", a2_count == 1)
        check("7d. Child 3 not reached yet", a3_count == 0)

        -- Tick 2: resume at a2 (a1 should NOT run again), a2 now succeeds
        a2_returns = BT.SUCCESS
        local r2 = seq:tick(bb, 0.016)
        check("7e. Sequence completes after resume", r2 == BT.SUCCESS)
        check("7f. Child 1 NOT re-run (still 1)", a1_count == 1)
        check("7g. Child 2 ran again (now 2)", a2_count == 2)
        check("7h. Child 3 ran once after resume", a3_count == 1)
    end

    --------------------------------------------------------------------------
    -- 8. Parallel require_one succeeds if any child succeeds
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()

        -- require_one: one SUCCESS among others
        local par_one = Parallel:new("require_one", "par_req_one")
        par_one:add(Action:new(function() return BT.FAILURE end, "p1"))
        par_one:add(Action:new(function() return BT.SUCCESS end, "p2"))
        par_one:add(Action:new(function() return BT.RUNNING end, "p3"))

        check("8a. Parallel require_one -> SUCCESS when any succeeds",
            par_one:tick(bb, 0.016) == BT.SUCCESS)

        -- require_all: need all SUCCESS
        local par_all_ok = Parallel:new("require_all", "par_req_all_ok")
        par_all_ok:add(Action:new(function() return BT.SUCCESS end, "p1"))
        par_all_ok:add(Action:new(function() return BT.SUCCESS end, "p2"))

        check("8b. Parallel require_all -> SUCCESS when all succeed",
            par_all_ok:tick(bb, 0.016) == BT.SUCCESS)

        -- require_all with a failure
        local par_all_fail = Parallel:new("require_all", "par_req_all_fail")
        par_all_fail:add(Action:new(function() return BT.SUCCESS end, "p1"))
        par_all_fail:add(Action:new(function() return BT.FAILURE end, "p2"))

        check("8c. Parallel require_all -> FAILURE when any fails",
            par_all_fail:tick(bb, 0.016) == BT.FAILURE)

        -- require_one with all failures
        local par_one_all_fail = Parallel:new("require_one", "par_one_all_fail")
        par_one_all_fail:add(Action:new(function() return BT.FAILURE end, "p1"))
        par_one_all_fail:add(Action:new(function() return BT.FAILURE end, "p2"))

        check("8d. Parallel require_one -> FAILURE when all fail",
            par_one_all_fail:tick(bb, 0.016) == BT.FAILURE)
    end

    --------------------------------------------------------------------------
    -- 9. Tree wrapper tracks last status
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local returns = BT.SUCCESS

        local root = Action:new(function() return returns end, "root_action")
        local tree = Tree:new(root, "test_tree")

        check("9a. Tree last_status nil before first tick",
            tree:get_last_status() == nil)

        tree:tick(bb, 0.016)
        check("9b. Tree last_status SUCCESS after tick",
            tree:get_last_status() == BT.SUCCESS)

        returns = BT.FAILURE
        tree:tick(bb, 0.016)
        check("9c. Tree last_status FAILURE after second tick",
            tree:get_last_status() == BT.FAILURE)

        tree:reset()
        check("9d. Tree last_status nil after reset",
            tree:get_last_status() == nil)
    end

    --------------------------------------------------------------------------
    -- 10. GuardState blocks wrong state, allows correct state
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local action_ran = false

        local guarded = GuardState:new(
            Action:new(function()
                action_ran = true
                return BT.SUCCESS
            end, "guarded_action"),
            "combat",
            "guard_combat"
        )

        -- Wrong state: should block
        bb:set("hsm.state", "idle")
        local r1 = guarded:tick(bb, 0.016)
        check("10a. GuardState blocks wrong state -> FAILURE",
            r1 == BT.FAILURE)
        check("10b. GuardState child not run in wrong state",
            action_ran == false)

        -- Correct state: should allow
        bb:set("hsm.state", "combat")
        local r2 = guarded:tick(bb, 0.016)
        check("10c. GuardState allows correct state -> SUCCESS",
            r2 == BT.SUCCESS)
        check("10d. GuardState child ran in correct state",
            action_ran == true)

        -- Table of states
        action_ran = false
        local multi_guard = GuardState:new(
            Action:new(function()
                action_ran = true
                return BT.SUCCESS
            end, "multi_action"),
            { "combat", "fleeing" },
            "guard_multi"
        )

        bb:set("hsm.state", "fleeing")
        local r3 = multi_guard:tick(bb, 0.016)
        check("10e. GuardState table match -> SUCCESS",
            r3 == BT.SUCCESS)
        check("10f. GuardState child ran with table match",
            action_ran == true)

        -- No state set at all
        local bb_empty = Blackboard:new()
        local r4 = guarded:tick(bb_empty, 0.016)
        check("10g. GuardState nil state -> FAILURE",
            r4 == BT.FAILURE)
    end

    --------------------------------------------------------------------------
    -- 11. ReactiveSequence re-evaluates guards every tick
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local guard_count = 0
        local action_count = 0
        local guard_pass = true
        local action_returns = BT.RUNNING

        local rseq = ReactiveSequence:new("rseq_test")
        rseq:add(Action:new(function()
            guard_count = guard_count + 1
            return guard_pass and BT.SUCCESS or BT.FAILURE
        end, "guard"))
        rseq:add(Action:new(function()
            action_count = action_count + 1
            return action_returns
        end, "action"))

        -- Tick 1: guard passes, action RUNNING
        local r1 = rseq:tick(bb, 0.016)
        check("11a. ReactiveSequence returns RUNNING", r1 == BT.RUNNING)
        check("11b. Guard ran once", guard_count == 1)
        check("11c. Action ran once", action_count == 1)

        -- Tick 2: guard STILL re-evaluated (unlike Sequence), action re-ticked
        local r2 = rseq:tick(bb, 0.016)
        check("11d. ReactiveSequence still RUNNING", r2 == BT.RUNNING)
        check("11e. Guard ran AGAIN (re-evaluated)", guard_count == 2)
        check("11f. Action ran again", action_count == 2)

        -- Tick 3: guard fails -> action should be reset, sequence fails
        guard_pass = false
        local old_action_count = action_count
        local r3 = rseq:tick(bb, 0.016)
        check("11g. ReactiveSequence FAILURE when guard fails", r3 == BT.FAILURE)
        check("11h. Guard checked (count increased)", guard_count == 3)
        check("11i. Action NOT ticked after guard fails", action_count == old_action_count)
    end

    --------------------------------------------------------------------------
    -- 11b. ReactiveSequence resets preempted RUNNING child
    --------------------------------------------------------------------------
    do
        local bb = Blackboard:new()
        local guard_pass = true
        local child_was_reset = false

        -- Custom action that tracks reset
        local trackable = Action:new(function()
            return BT.RUNNING
        end, "trackable")
        local orig_reset = trackable.reset
        trackable.reset = function(self)
            child_was_reset = true
            orig_reset(self)
        end

        local rseq = ReactiveSequence:new("rseq_reset_test")
        rseq:add(Action:new(function()
            return guard_pass and BT.SUCCESS or BT.FAILURE
        end, "guard"))
        rseq:add(trackable)

        -- Tick 1: guard passes, action RUNNING
        rseq:tick(bb, 0.016)
        check("11b1. Child not reset while running", child_was_reset == false)

        -- Tick 2: guard fails -> should reset the RUNNING child
        guard_pass = false
        rseq:tick(bb, 0.016)
        check("11b2. RUNNING child reset when guard fails", child_was_reset == true)
    end

    --------------------------------------------------------------------------
    -- Summary
    --------------------------------------------------------------------------
    local total = pass + fail
    local summary = string.format("[BehaviorTree._test] %d/%d passed", pass, total)
    if fail > 0 then
        summary = summary .. string.format(" (%d FAILED)", fail)
    end
    log(summary)

    return fail == 0
end

return BT
