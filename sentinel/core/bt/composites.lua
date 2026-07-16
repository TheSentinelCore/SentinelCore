local Status = require("core/bt/status")
local Node = require("core/bt/node")

local Sequence = setmetatable({}, { __index = Node })
Sequence.__index = Sequence

function Sequence:new(name, children)
    local o = Node.new(self, "sequence", name, children)
    o._running_index = 1
    return o
end

function Sequence:tick(blackboard)
    -- If we were running a child beyond the first, re-evaluate the first child (guard condition)
    -- to ensure it still passes. This fixes the common pattern where Sequence is used as
    -- "condition + action" and the condition must be re-checked each tick.
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
