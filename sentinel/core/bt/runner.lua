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
    local ok, result = pcall(self._root.tick, self._root, blackboard)
    if not ok then
        -- Reset tree state to prevent corrupted _running_index
        if self._root.reset then
            pcall(self._root.reset, self._root)
        end
        if core and type(core.log) == "function" then
            pcall(core.log, "[BT] tick error: " .. tostring(result))
        end
        return "FAILURE"
    end
    return result
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
