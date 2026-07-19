local Node = {}
Node.__index = Node

function Node:new(kind, name, children)
    local o = setmetatable({}, self)
    o.kind = kind or "node"
    o.name = name or kind or "node"
    o.children = children or {}
    return o
end

function Node:tick(_blackboard)
    return "FAILURE"
end

function Node:reset()
    for _, child in ipairs(self.children or {}) do
        if child.reset then
            child:reset()
        end
    end
end

return Node
