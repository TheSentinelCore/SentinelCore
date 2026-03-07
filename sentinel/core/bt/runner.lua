local Runner = {}
Runner.__index = Runner

function Runner:new(root)
    local o = setmetatable({}, Runner)
    o._root = root
    return o
end

function Runner:tick(blackboard)
    if not self._root then
        return "FAILURE"
    end
    return self._root:tick(blackboard)
end

function Runner:reset()
    if self._root and self._root.reset then
        self._root:reset()
    end
end

function Runner:get_root()
    return self._root
end

return Runner
