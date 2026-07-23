local Status = require("core/bt/status")
local Node = require("core/bt/node")

local Sequence = setmetatable({}, { __index = Node })
Sequence.__index = Sequence

--- C8 CONTRACT: when a Sequence has 2+ children, `children[1]` MUST be a
--- side-effect-free guard: either a `leaves.Condition` node (kind ==
--- "condition") or a nested `Sequence` built entirely from conditions (the
--- `priority.name .. "_conditions"` compound-AND pattern in
--- `priority_builder.lua`, which itself never returns RUNNING). `Sequence:tick`
--- re-ticks `children[1]` every frame as a guard once `_running_index > 1`
--- (see below) — this is only correct if child 1 is cheap and side-effect-free.
--- An action-first sequence would re-run that action's side effects every tick
--- while a later child is RUNNING, which is very likely not what the tree
--- author intended.
---
--- This is validated at construction time (non-fatal: logged via core.log
--- when available, and recorded on `_contract_violation` for tests/tooling)
--- rather than a hard `error()`, because leaves.Condition is defined in a
--- sibling module composites.lua does not require (to avoid a require cycle)
--- and because some legitimate trees may have exactly one child (no guard
--- re-tick ever happens, so the contract doesn't apply).
function Sequence:new(name, children)
    local o = Node.new(self, "sequence", name, children)
    o._running_index = 1
    o._contract_violation = false
    if children and #children > 1 then
        local guard = children[1]
        local guard_kind = type(guard) == "table" and guard.kind or nil
        local guard_is_condition_like = guard_kind == "condition" or guard_kind == "sequence"
        if not guard_is_condition_like then
            o._contract_violation = true
            local msg = "[BT] Sequence '" .. tostring(name or "?")
                .. "' has " .. tostring(#children)
                .. " children but children[1] is not a condition node (kind="
                .. tostring(guard_kind or "nil")
                .. "). The guard re-tick on _running_index > 1 will re-run it every frame."
            if core and core.log then
                pcall(core.log, msg)
            end
        end
    end
    return o
end

function Sequence:tick(blackboard)
    -- If we were running a child beyond the first, re-evaluate the first child (guard condition)
    -- to ensure it still passes. This fixes the common pattern where Sequence is used as
    -- "condition + action" and the condition must be re-checked each tick.
    -- CONTRACT (see Sequence:new): children[1] must be a condition node for this to be safe.
    if self._running_index > 1 then
        local guard_status = self.children[1]:tick(blackboard)
        if guard_status == Status.FAILURE then
            self._running_index = 1
            return Status.FAILURE
        end
        -- Guard passed, continue with the running child
    end

    for index = self._running_index, #self.children do
        local status = self.children[index]:tick(blackboard)
        if status == Status.RUNNING then
            self._running_index = index
            return Status.RUNNING
        end
        if status == Status.FAILURE then
            self._running_index = 1
            return Status.FAILURE
        end
    end
    self._running_index = 1
    return Status.SUCCESS
end

function Sequence:reset()
    self._running_index = 1
    Node.reset(self)
end

--- F11: `Selector` has memory (`_running_index`) — once a child returns RUNNING,
--- the next tick resumes AT that child, skipping re-evaluation of every
--- higher-priority sibling before it. `PrioritySelector` below has no such
--- memory: it always re-evaluates from child 1 every tick. This asymmetry is
--- load-bearing and easy to get backwards when picking a composite:
---
---   - Use `Selector` for "stay committed to whatever succeeded/is running
---     until it fails" fallback chains.
---   - Use `PrioritySelector` when a higher-priority child (e.g. a defensive
---     cooldown, an interrupt) must be able to preempt a lower-priority child
---     that is currently RUNNING — `test_bt.lua`'s "PrioritySelector:
---     high-priority preemption" case exercises exactly this.
---
--- Putting a defensive check below a RUNNING node under a memoized `Selector`
--- would silently never be re-evaluated until the RUNNING node fails on its
--- own. No shipped profile currently does this (both combat profiles gate
--- their defensive/interrupt checks through `PrioritySelector`), so this is
--- documentation of a real footgun rather than a fix to live code.
local Selector = setmetatable({}, { __index = Node })
Selector.__index = Selector

function Selector:new(name, children)
    local o = Node.new(self, "selector", name, children)
    o._running_index = 1
    return o
end

function Selector:tick(blackboard)
    for index = self._running_index, #self.children do
        local status = self.children[index]:tick(blackboard)
        if status == Status.RUNNING then
            self._running_index = index
            return Status.RUNNING
        end
        if status == Status.SUCCESS then
            self._running_index = 1
            return Status.SUCCESS
        end
    end
    self._running_index = 1
    return Status.FAILURE
end

function Selector:reset()
    self._running_index = 1
    Node.reset(self)
end

local PrioritySelector = setmetatable({}, { __index = Node })
PrioritySelector.__index = PrioritySelector

function PrioritySelector:new(name, children)
    return Node.new(self, "priority_selector", name, children)
end

function PrioritySelector:tick(blackboard)
    for _, child in ipairs(self.children) do
        local status = child:tick(blackboard)
        if status == Status.RUNNING or status == Status.SUCCESS then
            return status
        end
    end
    return Status.FAILURE
end

local Parallel = setmetatable({}, { __index = Node })
Parallel.__index = Parallel

function Parallel:new(name, children, opts)
    local o = Node.new(self, "parallel", name, children)
    opts = opts or {}
    o.success_policy = opts.success_policy or "all"
    o.failure_policy = opts.failure_policy or "one"
    return o
end

function Parallel:tick(blackboard)
    local success_count = 0
    local failure_count = 0
    local total = #self.children
    for _, child in ipairs(self.children) do
        local status = child:tick(blackboard)
        if status == Status.SUCCESS then
            success_count = success_count + 1
        elseif status == Status.FAILURE then
            failure_count = failure_count + 1
        end
    end
    if self.success_policy == "one" and success_count > 0 then
        return Status.SUCCESS
    end
    if self.success_policy == "all" and success_count == total then
        return Status.SUCCESS
    end
    if self.failure_policy == "one" and failure_count > 0 then
        return Status.FAILURE
    end
    if self.failure_policy == "all" and failure_count == total then
        return Status.FAILURE
    end
    return Status.RUNNING
end

return {
    Sequence = Sequence,
    Selector = Selector,
    PrioritySelector = PrioritySelector,
    Parallel = Parallel,
}
