# Sentinel Grinder & Combat Engine — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the fixed Client update pipeline with a Behavior Tree grind loop, replace PlanComposer priority lists with a Utility AI combat engine using response curves, and implement a TBC Retribution Paladin rotation with seal twisting and human-like anti-detection timing.

**Architecture:** Bottom-up build — pure libraries first (curves, BT nodes, evaluator), then rotation providers, then BT subtrees, then root tree + Client integration. Each task is independently testable. Existing Blackboard and EventBus are reused. The `ai/` directory holds reusable AI libraries; `bt/` holds grind-specific subtrees.

**Tech Stack:** Lua 5.1, Sylvannas runtime API, existing SentinelCore test framework (`TestUtil.lua`), `core.time()` for timing, `core.spell_book` for spell queries, `common/modules/spell_queue` for cast execution.

**Design Doc:** `docs/plans/2026-02-23-sentinel-grinder-combat-engine-design.md`

---

## Block 1: Foundation Libraries

### Task 1: Response Curves Library

**Files:**
- Create: `SentinelCore/ai/ResponseCurves.lua`
- Create: `SentinelCore/tests/test_ai001_response_curves.lua`

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai001_response_curves.lua
local RC = require("ai/ResponseCurves")

local M = {}

local function assert_near(actual, expected, tolerance, msg)
    tolerance = tolerance or 0.001
    if math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.4f, got %.4f", msg or "assert_near", expected, actual))
    end
end

local function assert_eq(a, b, msg)
    if a ~= b then error(string.format("%s: expected %s, got %s", msg or "assert_eq", tostring(b), tostring(a))) end
end

function M.run()
    -- linear: maps [min,max] → [0,1]
    assert_near(RC.evaluate("linear", 5, { min = 0, max = 10 }), 0.5, 0.001, "linear_mid")
    assert_near(RC.evaluate("linear", 0, { min = 0, max = 10 }), 0.0, 0.001, "linear_min")
    assert_near(RC.evaluate("linear", 10, { min = 0, max = 10 }), 1.0, 0.001, "linear_max")
    assert_near(RC.evaluate("linear", -5, { min = 0, max = 10 }), 0.0, 0.001, "linear_clamp_low")
    assert_near(RC.evaluate("linear", 15, { min = 0, max = 10 }), 1.0, 0.001, "linear_clamp_high")

    -- inverse_linear
    assert_near(RC.evaluate("inverse_linear", 5, { min = 0, max = 10 }), 0.5, 0.001, "inv_linear_mid")
    assert_near(RC.evaluate("inverse_linear", 0, { min = 0, max = 10 }), 1.0, 0.001, "inv_linear_min")
    assert_near(RC.evaluate("inverse_linear", 10, { min = 0, max = 10 }), 0.0, 0.001, "inv_linear_max")

    -- quadratic
    assert_near(RC.evaluate("quadratic", 5, { min = 0, max = 10 }), 0.25, 0.001, "quad_mid")

    -- inverse_quadratic
    assert_near(RC.evaluate("inverse_quadratic", 5, { min = 0, max = 10 }), 0.75, 0.001, "inv_quad_mid")

    -- step_above / step_below
    assert_eq(RC.evaluate("step_above", 5, { threshold = 3 }), 1, "step_above_pass")
    assert_eq(RC.evaluate("step_above", 2, { threshold = 3 }), 0, "step_above_fail")
    assert_eq(RC.evaluate("step_below", 2, { threshold = 3 }), 1, "step_below_pass")
    assert_eq(RC.evaluate("step_below", 5, { threshold = 3 }), 0, "step_below_fail")

    -- bell curve
    assert_near(RC.evaluate("bell", 5, { center = 5, width = 2 }), 1.0, 0.001, "bell_center")
    assert(RC.evaluate("bell", 10, { center = 5, width = 2 }) < 0.1, "bell_tail")

    -- logistic (S-curve)
    assert_near(RC.evaluate("logistic", 5, { midpoint = 5, steepness = 10 }), 0.5, 0.01, "logistic_mid")
    assert(RC.evaluate("logistic", 10, { midpoint = 5, steepness = 10 }) > 0.99, "logistic_high")
    assert(RC.evaluate("logistic", 0, { midpoint = 5, steepness = 10 }) < 0.01, "logistic_low")

    -- constant
    assert_near(RC.evaluate("constant", 999, { value = 0.7 }), 0.7, 0.001, "constant")

    -- unknown curve type returns 0
    assert_eq(RC.evaluate("nonexistent", 5, {}), 0, "unknown_curve")

    return true
end

return M
```

**Step 2: Run test to verify it fails**

Run: `lua SentinelCore/tests/test_ai001_response_curves.lua` (or via run_all)
Expected: FAIL — `ai/ResponseCurves` module not found

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/ResponseCurves.lua
local RC = {}

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

local function linear(x, p)
    local min, max = p.min or 0, p.max or 1
    if max == min then return x >= min and 1 or 0 end
    return clamp((x - min) / (max - min), 0, 1)
end

local curves = {
    linear = linear,

    inverse_linear = function(x, p)
        return 1 - linear(x, p)
    end,

    quadratic = function(x, p)
        local t = linear(x, p)
        return t * t
    end,

    inverse_quadratic = function(x, p)
        local t = 1 - linear(x, p)
        return 1 - t * t
    end,

    logistic = function(x, p)
        local k = p.steepness or 10
        local m = p.midpoint or 0.5
        return 1 / (1 + math.exp(-k * (x - m)))
    end,

    step_above = function(x, p)
        return x >= (p.threshold or 0.5) and 1 or 0
    end,

    step_below = function(x, p)
        return x < (p.threshold or 0.5) and 1 or 0
    end,

    bell = function(x, p)
        local center = p.center or 0.5
        local width = p.width or 0.2
        local d = x - center
        return math.exp(-(d * d) / (2 * width * width))
    end,

    constant = function(_, p)
        return p.value or 1
    end,
}

---Evaluate a named response curve.
---@param curve_name string
---@param input number
---@param params table
---@return number  Score in [0,1]
function RC.evaluate(curve_name, input, params)
    local fn = curves[curve_name]
    if not fn then return 0 end
    return fn(input, params or {})
end

---Check if a curve name is valid.
---@param name string
---@return boolean
function RC.is_valid(name)
    return curves[name] ~= nil
end

return RC
```

**Step 4: Run test to verify it passes**

**Step 5: Register test in `run_all.lua`**

Add to the test registry list: `"tests/test_ai001_response_curves"`

**Step 6: Commit**

```bash
git add SentinelCore/ai/ResponseCurves.lua SentinelCore/tests/test_ai001_response_curves.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add ResponseCurves library with 9 curve types"
```

---

### Task 2: Utility Evaluator

**Files:**
- Create: `SentinelCore/ai/UtilityEvaluator.lua`
- Create: `SentinelCore/tests/test_ai002_utility_evaluator.lua`

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai002_utility_evaluator.lua
local UE = require("ai/UtilityEvaluator")

local M = {}

function M.run()
    -- Test 1: register and evaluate a single action
    local eval = UE:new()
    eval:register({
        id = "test_action",
        action_type = "cast_spell_target",
        spell_id = 100,
        weight = 1.0,
        considerations = {
            { input = "health_pct", curve = "linear", params = { min = 0, max = 1 } },
        },
    })
    local ctx = { health_pct = 0.5 }
    local result = eval:evaluate(ctx)
    assert(result ~= nil, "evaluate should return a result")
    assert(result.action.id == "test_action", "should select the only action")
    assert(math.abs(result.utility - 0.5) < 0.01, "utility should be ~0.5")

    -- Test 2: higher utility wins
    eval:clear()
    eval:register({
        id = "low",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } },
    })
    eval:register({
        id = "high",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.9 } } },
    })
    result = eval:evaluate({ x = 0 })
    assert(result.action.id == "high", "higher utility should win")

    -- Test 3: weight multiplier
    eval:clear()
    eval:register({
        id = "heavy",
        weight = 3.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    eval:register({
        id = "light",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    result = eval:evaluate({ x = 0 })
    assert(result.action.id == "heavy", "weight should boost utility")

    -- Test 4: zero consideration kills action (geometric mean)
    eval:clear()
    eval:register({
        id = "blocked",
        weight = 10.0,
        considerations = {
            { input = "x", curve = "constant", params = { value = 1.0 } },
            { input = "y", curve = "step_above", params = { threshold = 0.5 } },
        },
    })
    eval:register({
        id = "fallback",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } },
    })
    result = eval:evaluate({ x = 1, y = 0.2 })
    assert(result.action.id == "fallback", "zero consideration should eliminate action")

    -- Test 5: no actions returns nil
    eval:clear()
    result = eval:evaluate({ x = 0 })
    assert(result == nil, "no actions should return nil")

    -- Test 6: hard_gates filter (function check)
    eval:clear()
    eval:register({
        id = "gated",
        weight = 5.0,
        hard_gate = function(ctx) return ctx.can_cast == true end,
        considerations = { { input = "x", curve = "constant", params = { value = 1.0 } } },
    })
    eval:register({
        id = "ungated",
        weight = 1.0,
        considerations = { { input = "x", curve = "constant", params = { value = 0.5 } } },
    })
    result = eval:evaluate({ x = 0, can_cast = false })
    assert(result.action.id == "ungated", "hard gate should filter action")
    result = eval:evaluate({ x = 0, can_cast = true })
    assert(result.action.id == "gated", "hard gate should pass when true")

    -- Test 7: get_top_k returns sorted list
    eval:clear()
    eval:register({ id = "a", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.3 } } } })
    eval:register({ id = "b", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.9 } } } })
    eval:register({ id = "c", weight = 1.0, considerations = { { input = "x", curve = "constant", params = { value = 0.6 } } } })
    local top = eval:get_top_k({ x = 0 }, 2)
    assert(#top == 2, "top_k should return 2")
    assert(top[1].action.id == "b", "top_k[1] should be highest")
    assert(top[2].action.id == "c", "top_k[2] should be second")

    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/UtilityEvaluator.lua
local RC = require("ai/ResponseCurves")

---@class UtilityEvaluator
local UE = {}
UE.__index = UE

function UE:new()
    local o = setmetatable({}, UE)
    o._actions = {}
    return o
end

---Register an action with utility considerations.
---@param action table { id, weight, considerations[], hard_gate?, action_type?, spell_id?, ... }
function UE:register(action)
    self._actions[#self._actions + 1] = action
end

---Remove all registered actions.
function UE:clear()
    self._actions = {}
end

---Score a single action against the current context.
---@param action table
---@param ctx table
---@return number utility (0 if any consideration is 0)
function UE:_score(action, ctx)
    local considerations = action.considerations
    if not considerations or #considerations == 0 then
        return action.weight or 1.0
    end

    local product = 1
    local n = #considerations
    for i = 1, n do
        local c = considerations[i]
        local input_val = ctx[c.input] or 0
        local score = RC.evaluate(c.curve, input_val, c.params)
        if score <= 0 then
            return 0
        end
        product = product * score
    end

    -- Geometric mean * weight
    local geo_mean = product ^ (1 / n)
    return geo_mean * (action.weight or 1.0)
end

---Evaluate all actions and return the best one.
---@param ctx table  Context keys mapping to numeric values
---@return table|nil  { action, utility } or nil if no valid actions
function UE:evaluate(ctx)
    local best_action = nil
    local best_utility = -1

    for i = 1, #self._actions do
        local action = self._actions[i]

        -- Hard gate check
        if action.hard_gate then
            if not action.hard_gate(ctx) then
                goto continue
            end
        end

        local utility = self:_score(action, ctx)
        if utility > best_utility then
            best_utility = utility
            best_action = action
        end

        ::continue::
    end

    if not best_action then return nil end
    return { action = best_action, utility = best_utility }
end

---Return top K actions sorted by utility (descending).
---@param ctx table
---@param k number
---@return table[]  Array of { action, utility }
function UE:get_top_k(ctx, k)
    local scored = {}
    for i = 1, #self._actions do
        local action = self._actions[i]
        if not action.hard_gate or action.hard_gate(ctx) then
            local utility = self:_score(action, ctx)
            if utility > 0 then
                scored[#scored + 1] = { action = action, utility = utility }
            end
        end
    end

    table.sort(scored, function(a, b) return a.utility > b.utility end)

    local result = {}
    for i = 1, math.min(k, #scored) do
        result[i] = scored[i]
    end
    return result
end

return UE
```

**Step 4: Run test to verify it passes**

**Step 5: Register test in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/ai/UtilityEvaluator.lua SentinelCore/tests/test_ai002_utility_evaluator.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add UtilityEvaluator with response curve scoring"
```

---

### Task 3: Behavior Tree Node Library

**Files:**
- Create: `SentinelCore/ai/BehaviorTree.lua`
- Create: `SentinelCore/tests/test_ai003_behavior_tree.lua`

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai003_behavior_tree.lua
local BT = require("ai/BehaviorTree")

local M = {}

function M.run()
    local S = BT.Status

    -- Test 1: Sequence runs all children, returns SUCCESS
    local log = {}
    local seq = BT.Sequence:new("test_seq", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.SUCCESS end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.SUCCESS end),
    })
    assert(seq:tick() == S.SUCCESS, "sequence all success")
    assert(#log == 2 and log[1] == "a" and log[2] == "b", "sequence order")

    -- Test 2: Sequence fails on first failure
    log = {}
    seq = BT.Sequence:new("test_seq2", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.SUCCESS end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.FAILURE end),
        BT.Action:new("c", function() log[#log + 1] = "c"; return S.SUCCESS end),
    })
    assert(seq:tick() == S.FAILURE, "sequence fail on b")
    assert(#log == 2, "sequence should stop at failure")

    -- Test 3: Sequence returns RUNNING and resumes
    local call_count = 0
    seq = BT.Sequence:new("test_seq3", {
        BT.Action:new("a", function() return S.SUCCESS end),
        BT.Action:new("b", function()
            call_count = call_count + 1
            if call_count < 3 then return S.RUNNING end
            return S.SUCCESS
        end),
        BT.Action:new("c", function() return S.SUCCESS end),
    })
    assert(seq:tick() == S.RUNNING, "seq running tick 1")
    assert(seq:tick() == S.RUNNING, "seq running tick 2")
    assert(seq:tick() == S.SUCCESS, "seq success tick 3")

    -- Test 4: Selector returns on first SUCCESS
    log = {}
    local sel = BT.Selector:new("test_sel", {
        BT.Action:new("a", function() log[#log + 1] = "a"; return S.FAILURE end),
        BT.Action:new("b", function() log[#log + 1] = "b"; return S.SUCCESS end),
        BT.Action:new("c", function() log[#log + 1] = "c"; return S.SUCCESS end),
    })
    assert(sel:tick() == S.SUCCESS, "selector first success")
    assert(#log == 2, "selector should stop at first success")

    -- Test 5: Selector returns FAILURE when all fail
    sel = BT.Selector:new("test_sel2", {
        BT.Action:new("a", function() return S.FAILURE end),
        BT.Action:new("b", function() return S.FAILURE end),
    })
    assert(sel:tick() == S.FAILURE, "selector all fail")

    -- Test 6: Condition node
    local flag = false
    local cond = BT.Condition:new("test_cond", function() return flag end)
    assert(cond:tick() == S.FAILURE, "condition false")
    flag = true
    assert(cond:tick() == S.SUCCESS, "condition true")

    -- Test 7: Decorator - Inverter
    local inv = BT.Inverter:new("inv",
        BT.Action:new("a", function() return S.SUCCESS end)
    )
    assert(inv:tick() == S.FAILURE, "inverter success->failure")

    inv = BT.Inverter:new("inv2",
        BT.Action:new("a", function() return S.FAILURE end)
    )
    assert(inv:tick() == S.SUCCESS, "inverter failure->success")

    -- Test 8: Decorator - RepeatUntilSuccess
    local attempts = 0
    local rep = BT.RepeatUntilSuccess:new("rep",
        BT.Action:new("a", function()
            attempts = attempts + 1
            if attempts >= 3 then return S.SUCCESS end
            return S.FAILURE
        end)
    )
    assert(rep:tick() == S.RUNNING, "repeat tick 1")
    assert(rep:tick() == S.RUNNING, "repeat tick 2")
    assert(rep:tick() == S.SUCCESS, "repeat tick 3")

    -- Test 9: Decorator - Timeout
    local time_now = 0
    local timeout = BT.Timeout:new("timeout", 5.0,
        BT.Action:new("slow", function() return S.RUNNING end),
        function() return time_now end
    )
    time_now = 0
    assert(timeout:tick() == S.RUNNING, "timeout not expired")
    time_now = 6
    assert(timeout:tick() == S.FAILURE, "timeout expired")

    -- Test 10: reset propagates
    call_count = 0
    local child = BT.Action:new("resettable", function()
        call_count = call_count + 1
        if call_count == 1 then return S.RUNNING end
        return S.SUCCESS
    end)
    seq = BT.Sequence:new("reset_test", {
        BT.Action:new("first", function() return S.SUCCESS end),
        child,
    })
    assert(seq:tick() == S.RUNNING, "pre-reset running")
    seq:reset()
    call_count = 0
    assert(seq:tick() == S.RUNNING, "post-reset restarts from child 1")

    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/BehaviorTree.lua
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

-- Inverter: flips SUCCESS ↔ FAILURE, passes RUNNING through
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

return BT
```

**Step 4: Run test to verify it passes**

**Step 5: Register test in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/ai/BehaviorTree.lua SentinelCore/tests/test_ai003_behavior_tree.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add BehaviorTree library with Selector, Sequence, Action, Condition, decorators"
```

---

### Task 4: SwingTimer Module

**Files:**
- Create: `SentinelCore/ai/SwingTimer.lua`
- Create: `SentinelCore/tests/test_ai004_swing_timer.lua`

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai004_swing_timer.lua
local SwingTimer = require("ai/SwingTimer")

local M = {}

function M.run()
    local time = 0
    local timer = SwingTimer:new(function() return time end)

    -- Configure for a 3.5s weapon
    timer:set_weapon_speed(3.5)
    timer:set_haste_modifier(1.0)

    -- Record a swing at t=0
    timer:record_swing()
    assert(math.abs(timer:time_until_swing() - 3.5) < 0.01, "full swing remaining at t=0")

    -- At t=1.0, 2.5s remaining
    time = 1.0
    assert(math.abs(timer:time_until_swing() - 2.5) < 0.01, "2.5s remaining at t=1")

    -- Prep window: >0.8s remaining
    time = 0.5
    assert(timer:in_prep_window() == true, "in prep window at t=0.5")
    time = 3.0
    assert(timer:in_prep_window() == false, "not in prep at t=3.0 (only 0.5s left)")

    -- Twist window: ≤0.4s remaining
    time = 3.0
    assert(timer:in_twist_window() == false, "not in twist at t=3.0 (0.5s left)")
    time = 3.2
    assert(timer:in_twist_window() == true, "in twist at t=3.2 (0.3s left)")

    -- Haste modifier: 1.4x haste → 3.5/1.4 = 2.5s swing
    timer:set_haste_modifier(1.4)
    timer:record_swing()
    time = time + 2.0
    assert(math.abs(timer:time_until_swing() - 0.5) < 0.01, "hasted swing")

    -- Swing elapsed (negative remaining → clamped to 0)
    time = time + 2.0
    assert(timer:time_until_swing() == 0, "clamped to 0 after swing window")

    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/SwingTimer.lua
---@class SwingTimer
local SwingTimer = {}
SwingTimer.__index = SwingTimer

---@param time_fn fun(): number  Returns current time in seconds
function SwingTimer:new(time_fn)
    local o = setmetatable({}, SwingTimer)
    o._time_fn = time_fn or function() return core and core.time() or 0 end
    o._last_swing = 0
    o._weapon_speed = 3.5
    o._haste_modifier = 1.0
    o._prep_threshold = 0.80   -- seconds remaining to start prep
    o._twist_threshold = 0.40  -- seconds remaining to start twist
    return o
end

function SwingTimer:set_weapon_speed(speed)
    self._weapon_speed = speed
end

function SwingTimer:set_haste_modifier(mod)
    self._haste_modifier = mod
end

function SwingTimer:record_swing()
    self._last_swing = self._time_fn()
end

---@return number seconds  Time interval between swings (haste-adjusted)
function SwingTimer:get_swing_interval()
    return self._weapon_speed / self._haste_modifier
end

---@return number seconds  Time until next auto-attack (clamped ≥0)
function SwingTimer:time_until_swing()
    local interval = self:get_swing_interval()
    local elapsed = self._time_fn() - self._last_swing
    local remaining = interval - elapsed
    return remaining > 0 and remaining or 0
end

---True when early in swing cycle (good time to apply SoC R1)
function SwingTimer:in_prep_window()
    local remaining = self:time_until_swing()
    return remaining > self._prep_threshold
end

---True when in last 0.4s before swing (twist to SoB)
function SwingTimer:in_twist_window()
    local remaining = self:time_until_swing()
    return remaining > 0 and remaining <= self._twist_threshold
end

return SwingTimer
```

**Step 4: Run test, verify it passes**

**Step 5: Register in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/ai/SwingTimer.lua SentinelCore/tests/test_ai004_swing_timer.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add SwingTimer for auto-attack tracking and seal twist windows"
```

---

### Task 5: HumanTiming Module

**Files:**
- Create: `SentinelCore/ai/HumanTiming.lua`
- Create: `SentinelCore/tests/test_ai005_human_timing.lua`

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai005_human_timing.lua
local HumanTiming = require("ai/HumanTiming")

local M = {}

function M.run()
    -- Use a fixed seed for deterministic tests
    math.randomseed(42)

    local ht = HumanTiming:new()

    -- Test 1: delays are in reasonable range
    local delays = {}
    for i = 1, 100 do
        delays[i] = ht:get_action_delay("rotation")
    end

    local min_d, max_d = math.huge, -math.huge
    for i = 1, 100 do
        if delays[i] < min_d then min_d = delays[i] end
        if delays[i] > max_d then max_d = delays[i] end
    end

    assert(min_d >= 0.030, "min delay should be at least 30ms: " .. min_d)
    assert(max_d < 1.0, "max delay should be under 1s: " .. max_d)

    -- Test 2: interrupt delays are longer than rotation delays (on average)
    local int_sum, rot_sum = 0, 0
    for i = 1, 200 do
        int_sum = int_sum + ht:get_action_delay("interrupt")
        rot_sum = rot_sum + ht:get_action_delay("rotation")
    end
    assert(int_sum / 200 > rot_sum / 200, "interrupts should be slower on average")

    -- Test 3: fatigue increases delay
    ht:set_fatigue(0.30)  -- 30% slower
    local fatigued_sum = 0
    for i = 1, 200 do
        fatigued_sum = fatigued_sum + ht:get_action_delay("rotation")
    end
    assert(fatigued_sum / 200 > rot_sum / 200, "fatigue should increase delays")

    -- Test 4: should_fumble returns boolean
    local fumbles = 0
    for i = 1, 1000 do
        if ht:should_fumble(0.05) then fumbles = fumbles + 1 end
    end
    -- With 5% rate, expect ~50 fumbles (allow wide tolerance)
    assert(fumbles > 10 and fumbles < 150, "fumble rate should be near 5%: " .. fumbles)

    -- Test 5: stochastic_select occasionally picks non-best
    local picks = { best = 0, other = 0 }
    for i = 1, 1000 do
        local candidates = {
            { id = "best", utility = 1.0 },
            { id = "second", utility = 0.95 },
            { id = "third", utility = 0.80 },
        }
        local pick = ht:stochastic_select(candidates, 0.05)
        if pick.id == "best" then picks.best = picks.best + 1
        else picks.other = picks.other + 1 end
    end
    assert(picks.other > 10, "stochastic should sometimes pick non-best: " .. picks.other)
    assert(picks.best > 700, "best should still win most of the time: " .. picks.best)

    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/HumanTiming.lua
---@class HumanTiming
local HumanTiming = {}
HumanTiming.__index = HumanTiming

function HumanTiming:new()
    local o = setmetatable({}, HumanTiming)
    o._base_reaction_sec = 0.180    -- 180ms baseline
    o._stddev_sec = 0.060           -- 60ms std dev
    o._fatigue = 0.0                -- 0-0.35 multiplier
    o._type_multipliers = {
        interrupt = 1.4,
        defensive = 1.2,
        rotation = 0.9,
        seal_twist = 0.7,
        movement = 1.0,
        loot = 1.1,
    }
    return o
end

---Approximate Gaussian using Box-Muller
local function gaussian_random(mean, stddev)
    local u1 = math.random()
    local u2 = math.random()
    if u1 < 1e-10 then u1 = 1e-10 end
    local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return mean + z * stddev
end

---Get a human-like delay for an action type.
---@param action_type string  "rotation"|"interrupt"|"defensive"|"seal_twist"|"movement"|"loot"
---@return number  Delay in seconds (minimum 0.030)
function HumanTiming:get_action_delay(action_type)
    local mult = self._type_multipliers[action_type] or 1.0
    local base = self._base_reaction_sec * (1 + self._fatigue) * mult
    local jitter = gaussian_random(0, self._stddev_sec)
    return math.max(0.030, base + jitter)
end

---Set fatigue factor (0.0 = fresh, 0.35 = max tired).
---@param factor number
function HumanTiming:set_fatigue(factor)
    self._fatigue = math.min(factor, 0.35)
end

---Should this action "fumble" (intentionally fail for anti-detection)?
---@param rate number  Probability 0-1 (e.g., 0.05 for 5%)
---@return boolean
function HumanTiming:should_fumble(rate)
    return math.random() < rate
end

---Select from candidates with Gaussian noise on utility scores.
---@param candidates table[]  Array of { id, utility, ... }
---@param jitter_factor number  Noise as fraction of score (e.g., 0.05 = 5%)
---@return table  Selected candidate
function HumanTiming:stochastic_select(candidates, jitter_factor)
    if #candidates == 0 then return nil end
    if #candidates == 1 then return candidates[1] end

    local best = nil
    local best_noisy = -math.huge

    for i = 1, #candidates do
        local c = candidates[i]
        local noise = gaussian_random(0, c.utility * jitter_factor)
        local noisy = c.utility + noise
        if noisy > best_noisy then
            best_noisy = noisy
            best = c
        end
    end

    return best
end

return HumanTiming
```

**Step 4: Run test, verify it passes**

**Step 5: Register in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/ai/HumanTiming.lua SentinelCore/tests/test_ai005_human_timing.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add HumanTiming with Gaussian jitter, fatigue, stochastic selection"
```

---

## Block 2: Rotation Framework

### Task 6: RotationProvider Interface + Context Builder

**Files:**
- Create: `SentinelCore/ai/CombatContext.lua`
- Create: `SentinelCore/tests/test_ai006_combat_context.lua`

The CombatContext reads from the Blackboard and produces a flat key-value table for the UtilityEvaluator. It replaces the old `rotations/framework/CombatContext.lua`.

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai006_combat_context.lua
local TU = require("tests/TestUtil")
local CombatContext = require("ai/CombatContext")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    local EventBus = require("events/EventBus")
    local Blackboard = require("core/Blackboard")

    local eb = EventBus:new()
    local bb = Blackboard:new(eb)

    -- Populate blackboard like Sensors would
    local player = TU.mock_object({
        health = 500, max_health = 1000,
        mana = 300, max_mana = 1000,
        dead = false, ghost = false,
        in_combat = true, moving = false, casting = false,
        position = { x = 100, y = 200, z = 0 },
    })
    local target = TU.mock_object({
        health = 200, max_health = 800,
        dead = false,
        in_combat = true, casting = true,
        position = { x = 105, y = 200, z = 0 },
    })

    bb:set("player.object", player)
    bb:set("player.health", 500)
    bb:set("player.max_health", 1000)
    bb:set("player.in_combat", true)
    bb:set("player.is_casting", false)
    bb:set("player.position", { x = 100, y = 200, z = 0 })
    bb:set("combat.target", target)
    bb:set("combat.enemy_count", 2)

    local ctx = CombatContext.build(bb)

    -- Verify key fields
    assert(ctx.player_health_pct == 0.5, "health_pct: " .. tostring(ctx.player_health_pct))
    assert(ctx.player_mana_pct == 0.3, "mana_pct: " .. tostring(ctx.player_mana_pct))
    assert(ctx.player_is_moving == 0, "is_moving")
    assert(ctx.player_is_casting == 0, "is_casting")
    assert(ctx.target_is_casting == 1, "target casting")
    assert(ctx.enemy_count == 2, "enemy_count")
    assert(ctx.in_combat == 1, "in_combat")

    -- Distance should be ~5 yards
    assert(ctx.target_distance ~= nil, "distance should exist")
    assert(math.abs(ctx.target_distance - 5) < 1, "distance ~5: " .. tostring(ctx.target_distance))

    env.restore()
    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

```lua
-- SentinelCore/ai/CombatContext.lua
---@class CombatContext
local CombatContext = {}

---Build a flat context table from Blackboard for UtilityEvaluator.
---All values are numbers (0/1 for booleans) so response curves work directly.
---@param bb Blackboard
---@param swing_timer? SwingTimer
---@return table<string, number>
function CombatContext.build(bb, swing_timer)
    local player = bb:get("player.object")
    local target = bb:get("combat.target")

    local p_health = bb:get("player.health", 0)
    local p_max_health = bb:get("player.max_health", 1)
    local p_mana = 0
    local p_max_mana = 1
    if player then
        local ok1, m = pcall(function() return player:get_power(0) end)
        local ok2, mm = pcall(function() return player:get_max_power(0) end)
        if ok1 and ok2 and mm and mm > 0 then
            p_mana = m or 0
            p_max_mana = mm
        end
    end

    local t_health = 0
    local t_max_health = 1
    local t_distance = 99
    local t_casting = false
    local t_cast_pct = 0

    if target then
        local ok1, h = pcall(function() return target:get_health() end)
        local ok2, mh = pcall(function() return target:get_max_health() end)
        if ok1 and ok2 then
            t_health = h or 0
            t_max_health = (mh and mh > 0) and mh or 1
        end

        local pp = bb:get("player.position")
        if pp then
            local ok3, tp = pcall(function() return target:get_position() end)
            if ok3 and tp then
                local dx = (tp.x or 0) - (pp.x or 0)
                local dy = (tp.y or 0) - (pp.y or 0)
                local dz = (tp.z or 0) - (pp.z or 0)
                t_distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            end
        end

        local ok4, casting = pcall(function() return target:is_casting_spell() end)
        t_casting = ok4 and casting or false
        local ok5, cst = pcall(function()
            local st = target:get_active_spell_cast_start_time()
            local et = target:get_active_spell_cast_end_time()
            if st and et and et > st and core then
                return (core.time() - st) / (et - st)
            end
            return 0
        end)
        t_cast_pct = ok5 and cst or 0
    end

    local ctx = {
        -- Player
        player_health_pct = p_max_health > 0 and (p_health / p_max_health) or 0,
        player_mana_pct = p_max_mana > 0 and (p_mana / p_max_mana) or 0,
        player_is_moving = (bb:get("player.is_moving") or false) and 1 or 0,
        player_is_casting = (bb:get("player.is_casting") or false) and 1 or 0,
        player_is_cc = 0,  -- TODO: detect CC auras
        in_combat = (bb:get("player.in_combat") or false) and 1 or 0,

        -- Target
        target_health_pct = t_max_health > 0 and (t_health / t_max_health) or 0,
        target_distance = t_distance,
        target_is_casting = t_casting and 1 or 0,
        target_cast_progress = t_cast_pct,
        target_time_to_die = bb:get("combat.target_ttd", 30),
        target_is_fleeing = 0,  -- TODO: detect flee behavior
        target_is_undead_demon = 0,  -- TODO: check creature type

        -- Combat
        enemy_count = bb:get("combat.enemy_count", 0),
        time_in_combat = bb:get("combat.time_in_combat", 0),
        nearest_enemy_distance = bb:get("combat.nearest_enemy_dist", 99),

        -- Spell state (populated per-action by evaluator)
        spell_cooldown_remaining = 0,
        gcd_remaining = 0,

        -- Swing timer
        swing_time_remaining = 0,
        swing_in_prep_window = 0,
        swing_in_twist_window = 0,

        -- Buff state (populated by rotation before evaluation)
        has_seal_of_blood = 0,
        has_seal_of_command = 0,
        has_avenging_wrath = 0,
        has_blessing_of_might = 0,
        vengeance_stacks = 0,

        -- Config
        seal_twist_enabled = bb:get("config.seal_twist_enabled", 0),
        aoe_threshold = bb:get("config.aoe_threshold", 3),
    }

    -- Swing timer integration
    if swing_timer then
        ctx.swing_time_remaining = swing_timer:time_until_swing()
        ctx.swing_in_prep_window = swing_timer:in_prep_window() and 1 or 0
        ctx.swing_in_twist_window = swing_timer:in_twist_window() and 1 or 0
    end

    return ctx
end

return CombatContext
```

**Step 4: Run test, verify it passes**

**Step 5: Register in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/ai/CombatContext.lua SentinelCore/tests/test_ai006_combat_context.lua SentinelCore/tests/run_all.lua
git commit -m "feat(ai): add CombatContext builder (Blackboard → flat context for UtilityEvaluator)"
```

---

### Task 7: Retribution Paladin Rotation (Utility Curves)

**Files:**
- Create: `SentinelCore/rotations/paladin/RetributionUtility.lua`
- Create: `SentinelCore/tests/test_ai007_retribution_utility.lua`

This is the largest task. The rotation registers all actions with utility curves as defined in the design doc (Section 5.3).

**Step 1: Write the failing test**

```lua
-- SentinelCore/tests/test_ai007_retribution_utility.lua
local TU = require("tests/TestUtil")
local UE = require("ai/UtilityEvaluator")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    -- Stub spell book: all spells are "learned"
    env.core.spell_book.has_spell = function() return true end
    env.core.spell_book.is_spell_learned = function() return true end
    env.core.spell_book.get_spell_cooldown = function() return 0 end
    env.core.spell_book.get_global_cooldown = function() return 0 end

    local RetUtil = require("rotations/paladin/RetributionUtility")

    -- Test 1: Register actions and evaluate in normal combat
    local eval = UE:new()
    RetUtil.register_actions(eval)

    local ctx = {
        player_health_pct = 0.80,
        player_mana_pct = 0.60,
        player_is_moving = 0,
        player_is_casting = 0,
        player_is_cc = 0,
        in_combat = 1,
        target_health_pct = 0.70,
        target_distance = 4.0,
        target_is_casting = 0,
        target_cast_progress = 0,
        target_time_to_die = 20,
        target_is_fleeing = 0,
        target_is_undead_demon = 0,
        enemy_count = 1,
        time_in_combat = 5,
        nearest_enemy_distance = 4.0,
        spell_cooldown_remaining = 0,
        gcd_remaining = 0,
        swing_time_remaining = 2.0,
        swing_in_prep_window = 1,
        swing_in_twist_window = 0,
        has_seal_of_blood = 1,
        has_seal_of_command = 0,
        has_avenging_wrath = 0,
        has_blessing_of_might = 1,
        vengeance_stacks = 0,
        seal_twist_enabled = 0,
        aoe_threshold = 3,
    }

    local result = eval:evaluate(ctx)
    assert(result ~= nil, "should find an action")
    -- In normal combat, Judgement or Crusader Strike should be top
    assert(result.action.id ~= nil, "action should have an id")

    -- Test 2: Execute phase — Hammer of Wrath should score high
    ctx.target_health_pct = 0.10
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find execute action")
    assert(result.action.id == "hammer_of_wrath", "HoW should win in execute: " .. tostring(result.action.id))

    -- Test 3: Emergency — Divine Shield at very low health
    ctx.player_health_pct = 0.08
    ctx.target_health_pct = 0.50
    local top = eval:get_top_k(ctx, 3)
    local found_ds = false
    for _, entry in ipairs(top) do
        if entry.action.id == "divine_shield" then found_ds = true end
    end
    assert(found_ds, "Divine Shield should be in top 3 at 8% HP")

    -- Test 4: Seal twist — SoC R1 in prep window
    ctx.player_health_pct = 0.80
    ctx.seal_twist_enabled = 1
    ctx.swing_in_prep_window = 1
    ctx.swing_in_twist_window = 0
    ctx.has_seal_of_command = 0
    ctx.has_seal_of_blood = 1
    ctx.player_mana_pct = 0.50
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find twist prep action")
    assert(result.action.id == "seal_twist_prep", "SoC R1 prep should win: " .. tostring(result.action.id))

    -- Test 5: Seal twist — SoB in twist window
    ctx.swing_in_prep_window = 0
    ctx.swing_in_twist_window = 1
    ctx.has_seal_of_command = 1
    ctx.has_seal_of_blood = 0
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find twist action")
    assert(result.action.id == "seal_twist_execute", "SoB twist should win: " .. tostring(result.action.id))

    -- Test 6: Interrupt — HoJ when target casting
    ctx.swing_in_twist_window = 0
    ctx.swing_in_prep_window = 0
    ctx.seal_twist_enabled = 0
    ctx.has_seal_of_blood = 1
    ctx.has_seal_of_command = 0
    ctx.target_is_casting = 1
    ctx.target_cast_progress = 0.70
    ctx.target_distance = 5.0
    ctx.player_health_pct = 0.80
    result = eval:evaluate(ctx)
    assert(result ~= nil, "should find interrupt")
    assert(result.action.id == "hammer_of_justice", "HoJ should win on casting target: " .. tostring(result.action.id))

    env.restore()
    return true
end

return M
```

**Step 2: Run test to verify it fails**

**Step 3: Write implementation**

Create `SentinelCore/rotations/paladin/RetributionUtility.lua` with all action registrations from the design doc Section 5.3. Each action has:
- Unique `id` string
- `action_type` matching existing execution types
- `spell_id` (numeric constant)
- `weight` and `considerations` array
- Optional `hard_gate` function for cooldown/range checks
- Optional `bypasses_gcd` flag

The file should define spell ID constants at the top, then export a `register_actions(evaluator)` function. See design doc Section 5.1 for complete spell IDs and Section 5.3 for all action definitions.

Key structure:

```lua
-- SentinelCore/rotations/paladin/RetributionUtility.lua
local RetUtil = {}

-- Spell IDs (from mangos DB)
local SPELLS = {
    SEAL_OF_BLOOD = 31892,
    SEAL_OF_COMMAND_R1 = 20375,
    JUDGEMENT = 20271,
    CRUSADER_STRIKE = 35395,
    HAMMER_OF_WRATH_R4 = 27180,
    EXORCISM_R7 = 27138,
    CONSECRATION_R6 = 27173,
    HOLY_WRATH_R3 = 27139,
    AVENGING_WRATH = 31884,
    DIVINE_SHIELD_R2 = 1020,
    LAY_ON_HANDS_R4 = 27154,
    HAMMER_OF_JUSTICE_R4 = 10308,
    REPENTANCE = 20066,
    FLASH_OF_LIGHT_R7 = 27137,
    HOLY_LIGHT_R11 = 27136,
    BLESSING_OF_MIGHT_R8 = 27140,
    SANCTITY_AURA = 20218,
    BLESSING_OF_FREEDOM = 1044,
}
RetUtil.SPELLS = SPELLS

function RetUtil.register_actions(evaluator)
    -- Register all actions per design doc Section 5.3
    -- (defensives, interrupts, seal twisting, cooldowns, core rotation)
    -- ... [complete action definitions as in design doc]
end

return RetUtil
```

**Step 4: Run test, verify it passes**

**Step 5: Register in `run_all.lua`**

**Step 6: Commit**

```bash
git add SentinelCore/rotations/paladin/RetributionUtility.lua SentinelCore/tests/test_ai007_retribution_utility.lua SentinelCore/tests/run_all.lua
git commit -m "feat(rotation): add Retribution Paladin utility-based rotation with seal twisting"
```

---

## Block 3: BT Subtrees

### Task 8: Combat SubTree

**Files:**
- Create: `SentinelCore/bt/CombatSubTree.lua`
- Create: `SentinelCore/tests/test_ai008_combat_subtree.lua`

The combat subtree wraps the UtilityEvaluator inside a BT Sequence that handles target acquisition, facing, chase movement, and spell execution.

**Step 1: Write the failing test**

Test that:
1. Combat subtree returns FAILURE when not in combat
2. Returns RUNNING when in combat and executing rotation
3. Returns SUCCESS when target dies
4. Properly calls `core.input.look_at()` for facing
5. Integrates with UtilityEvaluator to select actions

**Step 2: Write implementation**

```lua
-- SentinelCore/bt/CombatSubTree.lua
local BT = require("ai/BehaviorTree")
local UE = require("ai/UtilityEvaluator")
local CombatContext = require("ai/CombatContext")
local HumanTiming = require("ai/HumanTiming")
local S = BT.Status

local CombatSubTree = {}

function CombatSubTree.build(bb, evaluator, swing_timer, human_timing, spell_executor)
    local pending_action = nil
    local pending_delay_until = nil
    local combat_start_time = nil

    return BT.Sequence:new("combat", {
        -- Gate: must be in combat
        BT.Condition:new("in_combat", function()
            return bb:get("player.in_combat", false)
                or bb:get("combat.has_aggro", false)
        end),

        -- Track combat start
        BT.Action:new("track_combat_time", function()
            if not combat_start_time then
                combat_start_time = core.time()
            end
            bb:set("combat.time_in_combat", core.time() - combat_start_time)
            return S.SUCCESS
        end),

        -- Facing
        BT.Action:new("face_target", function()
            local target = bb:get("combat.target")
            if not target then return S.SUCCESS end
            local ok, pos = pcall(function() return target:get_position() end)
            if ok and pos then
                pcall(function() core.input.look_at(pos) end)
            end
            return S.SUCCESS
        end),

        -- Evaluate + execute
        BT.Action:new("evaluate_and_execute", function()
            local now = core.time()

            -- If we have a pending action with human delay, wait
            if pending_action and pending_delay_until and now < pending_delay_until then
                return S.RUNNING
            end

            -- Execute pending action if delay expired
            if pending_action then
                local action = pending_action
                pending_action = nil
                pending_delay_until = nil
                if spell_executor then
                    spell_executor(action)
                end
                return S.RUNNING
            end

            -- Build context and evaluate
            local ctx = CombatContext.build(bb, swing_timer)
            local result = evaluator:evaluate(ctx)

            if not result then
                return S.RUNNING  -- nothing to do, wait
            end

            -- Apply human timing delay
            local delay = human_timing:get_action_delay(result.action.intent or "rotation")
            pending_action = result.action
            pending_delay_until = now + delay
            return S.RUNNING
        end),
    })
end

return CombatSubTree
```

**Step 3-6:** Test, verify, register, commit.

```bash
git commit -m "feat(bt): add CombatSubTree wrapping UtilityEvaluator with human timing"
```

---

### Task 9: Death Recovery SubTree

**Files:**
- Create: `SentinelCore/bt/DeathRecoverySubTree.lua`
- Create: `SentinelCore/tests/test_ai009_death_recovery_subtree.lua`

Adapts the existing DeathRecoveryService logic into BT nodes. Reads `player.is_dead`, `player.is_ghost` from blackboard.

**Step 1-6:** Write test → implement → verify → commit.

Key structure: Sequence with Condition(is_dead_or_ghost) → Action(release_spirit) → Action(corpse_run) → Action(resurrect).

```bash
git commit -m "feat(bt): add DeathRecoverySubTree"
```

---

### Task 10: Loot SubTree

**Files:**
- Create: `SentinelCore/bt/LootSubTree.lua`
- Create: `SentinelCore/tests/test_ai010_loot_subtree.lua`

Sequence: Condition(has_lootable) → Timeout(8s, Action(navigate_and_loot)).

```bash
git commit -m "feat(bt): add LootSubTree"
```

---

### Task 11: Rest & Maintenance SubTree

**Files:**
- Create: `SentinelCore/bt/RestSubTree.lua`
- Create: `SentinelCore/bt/MaintenanceSubTree.lua`
- Create: `SentinelCore/tests/test_ai011_rest_maintenance.lua`

Rest: Condition(needs_recovery AND NOT in_combat) → Action(eat_drink) → WaitUntil(recovered).
Maintenance: Condition(NOT in_combat) → Action(ensure_aura) → Action(ensure_blessing) → Action(ensure_seal).

```bash
git commit -m "feat(bt): add RestSubTree and MaintenanceSubTree"
```

---

### Task 12: Vendor SubTree

**Files:**
- Create: `SentinelCore/bt/VendorSubTree.lua`
- Create: `SentinelCore/tests/test_ai012_vendor_subtree.lua`

Wraps existing VendorService: Condition(bags_near_full OR durability_low) → Timeout(120s, SubTree(vendor_trip)).

```bash
git commit -m "feat(bt): add VendorSubTree wrapping VendorService"
```

---

### Task 13: Flee SubTree + CombatInterrupt SubTree

**Files:**
- Create: `SentinelCore/bt/FleeSubTree.lua`
- Create: `SentinelCore/bt/CombatInterruptSubTree.lua`
- Create: `SentinelCore/tests/test_ai013_flee_interrupt.lua`

Flee: Condition(should_flee) → Action(disengage) → WaitUntil(out_of_combat).
CombatInterrupt: Condition(in_combat AND was_resting) → Action(cancel_current_action).

```bash
git commit -m "feat(bt): add FleeSubTree and CombatInterruptSubTree"
```

---

### Task 14: Pull + FindTarget + Explore SubTrees

**Files:**
- Create: `SentinelCore/bt/PullSubTree.lua`
- Create: `SentinelCore/bt/FindTargetSubTree.lua`
- Create: `SentinelCore/bt/ExploreSubTree.lua`
- Create: `SentinelCore/tests/test_ai014_pull_find_explore.lua`

Pull: Condition(has_valid_target) → Timeout(12s, Sequence(navigate, pull)).
FindTarget: Condition(NOT has_target) → Action(scan_score_select).
Explore: Condition(nothing_to_do) → Action(navigate_waypoint) with PathEntropy.

```bash
git commit -m "feat(bt): add PullSubTree, FindTargetSubTree, ExploreSubTree"
```

---

## Block 4: Root Tree + Client Integration

### Task 15: GrindTree (Root BT)

**Files:**
- Create: `SentinelCore/bt/GrindTree.lua`
- Create: `SentinelCore/tests/test_ai015_grind_tree.lua`

Assembles all subtrees into the root Selector from the design doc Section 2.1.

```lua
-- SentinelCore/bt/GrindTree.lua
local BT = require("ai/BehaviorTree")
local DeathRecoverySubTree = require("bt/DeathRecoverySubTree")
local CombatInterruptSubTree = require("bt/CombatInterruptSubTree")
local CombatSubTree = require("bt/CombatSubTree")
local FleeSubTree = require("bt/FleeSubTree")
local LootSubTree = require("bt/LootSubTree")
local RestSubTree = require("bt/RestSubTree")
local VendorSubTree = require("bt/VendorSubTree")
local MaintenanceSubTree = require("bt/MaintenanceSubTree")
local PullSubTree = require("bt/PullSubTree")
local FindTargetSubTree = require("bt/FindTargetSubTree")
local ExploreSubTree = require("bt/ExploreSubTree")

local GrindTree = {}

function GrindTree.build(deps)
    -- deps: { bb, evaluator, swing_timer, human_timing, spell_executor,
    --         navigation, targeting, inventory, vendor_service, ... }

    return BT.Selector:new("grind_root", {
        DeathRecoverySubTree.build(deps.bb, deps.navigation),
        -- EmergencyDefense handled inside CombatSubTree (high-weight defensive actions)
        CombatInterruptSubTree.build(deps.bb),
        CombatSubTree.build(deps.bb, deps.evaluator, deps.swing_timer, deps.human_timing, deps.spell_executor),
        FleeSubTree.build(deps.bb, deps.navigation),
        LootSubTree.build(deps.bb, deps.navigation),
        RestSubTree.build(deps.bb),
        VendorSubTree.build(deps.bb, deps.vendor_service),
        MaintenanceSubTree.build(deps.bb),
        PullSubTree.build(deps.bb, deps.navigation, deps.targeting),
        FindTargetSubTree.build(deps.bb, deps.targeting),
        ExploreSubTree.build(deps.bb, deps.navigation),
    })
end

return GrindTree
```

**Test:** Verify tree ticks correctly with mocked subtrees. Test priority ordering (death > combat > loot > rest > vendor > pull > explore).

```bash
git commit -m "feat(bt): add GrindTree root assembling all subtrees"
```

---

### Task 16: Client Integration

**Files:**
- Modify: `SentinelCore/core/Client.lua`
- Modify: `SentinelCore/core/Sensors.lua`
- Modify: `SentinelCore/events/Events.lua`

**This is the key integration task.** Replace the fixed `_service_updates()` loop with a single `_grind_tree:tick()` call.

**Changes to Client.lua:**

1. **New requires** (top of file):
```lua
local GrindTree = require("bt/GrindTree")
local UtilityEvaluator = require("ai/UtilityEvaluator")
local SwingTimer = require("ai/SwingTimer")
local HumanTiming = require("ai/HumanTiming")
local CombatContext = require("ai/CombatContext")
local RetUtil = require("rotations/paladin/RetributionUtility")
```

2. **In `Client:new()`** — instantiate AI components:
```lua
self._utility_evaluator = UtilityEvaluator:new()
self._swing_timer = SwingTimer:new()
self._human_timing = HumanTiming:new()

-- Register rotation based on class
-- (For now: always Ret Paladin. Later: dispatch by class_id)
RetUtil.register_actions(self._utility_evaluator)
```

3. **In `Client:start()`** — build the grind tree:
```lua
self._grind_tree = GrindTree.build({
    bb = self._blackboard,
    evaluator = self._utility_evaluator,
    swing_timer = self._swing_timer,
    human_timing = self._human_timing,
    spell_executor = function(action) self:_execute_action(action) end,
    navigation = self._services.navigation,
    targeting = self._services.targeting,
    inventory = self._services.inventory,
    vendor_service = self._services.vendor,
})
```

4. **In `Client:update()`** — replace the pipeline:
```lua
-- OLD (lines 757-776):
-- mode tick → service updates in order → recovery

-- NEW:
if self._grind_tree then
    self._grind_tree:tick()
end
```

5. **Add `_execute_action()`** — bridges UtilityEvaluator actions to spell_queue/core.input:
```lua
function Client:_execute_action(action)
    -- Route to spell_queue or core.input based on action_type
    -- Similar to existing RotationEngine:execute_action()
end
```

**Changes to Sensors.lua:**

Add new blackboard keys:
- `player.is_moving` — from `player:is_moving()`
- `combat.has_aggro` — scan nearby enemies targeting player
- `combat.target` — current combat target
- `combat.nearest_enemy_dist` — min distance to hostile unit

**Changes to Events.lua:**

Add new event constants:
```lua
-- Behavior Tree
BT_TICK = "bt.tick",
BT_SUBTREE_ENTERED = "bt.subtree_entered",
BT_SUBTREE_EXITED = "bt.subtree_exited",

-- Utility AI
UTILITY_EVALUATED = "utility.evaluated",
UTILITY_ACTION_SELECTED = "utility.action_selected",
```

```bash
git commit -m "feat(core): integrate BT + UtilityAI into Client, replace fixed pipeline"
```

---

### Task 17: Anti-Detection Wiring

**Files:**
- Create: `SentinelCore/ai/PathEntropy.lua`
- Create: `SentinelCore/ai/SessionBehavior.lua`

Wire anti-detection into BT decorators:
- PathEntropy applies waypoint jitter to all navigation actions
- SessionBehavior adds micro-pauses and idle checks to the root tree
- HumanTiming already wired in CombatSubTree (Task 8)

```bash
git commit -m "feat(ai): add PathEntropy and SessionBehavior anti-detection"
```

---

### Task 18: Integration Smoke Tests

**Files:**
- Create: `SentinelCore/tests/test_ai018_integration_smoke.lua`

Test the full grind loop with mocked game state:
1. **Grind cycle**: idle → find target → pull → combat → kill → loot → rest → repeat
2. **Death cycle**: die → release → corpse run → resurrect → continue grinding
3. **Vendor cycle**: bags full → vendor trip → return → continue
4. **Flee cycle**: overwhelmed → flee → recover → continue
5. **Seal twist cycle**: verify SoC/SoB timing during combat

Each scenario advances the mock clock and verifies BT transitions via blackboard state.

```bash
git commit -m "test: add integration smoke tests for full grind loop"
```

---

### Task 19: Final Verification + Cleanup

**Step 1:** Run all tests

```bash
# From SentinelCore directory (or however the test runner is invoked)
lua tests/run_all.lua
```

Expected: All tests pass (both new ai* tests and existing sc* tests).

**Step 2:** Review for unused code

Remove any PlanComposer references that are no longer needed. The old RotationEngine cannot be kept, but all rotation logic should flow through UtilityEvaluator.

**Step 3:** Final commit

```bash
git add -A
git commit -m "chore: cleanup unused PlanComposer references, verify all tests pass"
```

---

## Summary

| Block | Tasks | New Files | Key Deliverable |
|-------|-------|-----------|-----------------|
| **1: Foundation** | 1-5 | 5 libs + 5 tests | ResponseCurves, UtilityEvaluator, BehaviorTree, SwingTimer, HumanTiming |
| **2: Rotation** | 6-7 | 2 files + 2 tests | CombatContext builder, Ret Paladin utility rotation |
| **3: BT Subtrees** | 8-14 | ~12 files + 7 tests | Combat, Death, Loot, Rest, Vendor, Flee, Pull, Find, Explore subtrees |
| **4: Integration** | 15-19 | GrindTree + Client mods | Root BT, Client rewrite, anti-detection, smoke tests |

**Total: ~19 tasks, ~30 new files, ~4000-5000 lines of new code.**
