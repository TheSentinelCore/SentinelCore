local composites = require("core/bt/composites")
local decorators = require("core/bt/decorators")
local leaves = require("core/bt/leaves")

local BT = {}

function BT.sequence(name, children)
    return composites.Sequence:new(name, children)
end

function BT.selector(name, children)
    return composites.Selector:new(name, children)
end

function BT.priority_selector(name, children)
    return composites.PrioritySelector:new(name, children)
end

function BT.parallel(name, children, opts)
    return composites.Parallel:new(name, children, opts)
end

function BT.inverter(name, child)
    return decorators.Inverter:new(name, child)
end

function BT.cooldown(name, interval_ms, child, opts)
    return decorators.Cooldown:new(name, interval_ms, child, opts)
end

function BT.max_attempts(name, max_attempts, child, opts)
    return decorators.MaxAttempts:new(name, max_attempts, child, opts)
end

function BT.condition(name, fn)
    return leaves.Condition:new(name, fn)
end

function BT.action(name, fn)
    return leaves.Action:new(name, fn)
end

return BT
