local Status = require("core/bt/status")
local Node = require("core/bt/node")

local Condition = setmetatable({}, { __index = Node })
Condition.__index = Condition

function Condition:new(name, fn)
    local o = Node.new(self, "condition", name, {})
    o._fn = fn
    return o
end

function Condition:tick(blackboard)
    local ok, result = pcall(self._fn, blackboard)
    if ok and result then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

local Action = setmetatable({}, { __index = Node })
Action.__index = Action

function Action:new(name, fn)
    local o = Node.new(self, "action", name, {})
    o._fn = fn
    return o
end

function Action:tick(blackboard)
    local ok, result = pcall(self._fn, blackboard)
    if not ok then
        if core and core.log then
            pcall(core.log, "[BT] Action '" .. (self.name or "?") .. "' error: " .. tostring(result))
        end
        return Status.FAILURE
    end
    if result == Status.SUCCESS or result == Status.FAILURE or result == Status.RUNNING then
        return result
    end
    if result == false or result == nil then
        return Status.FAILURE
    end
    return Status.SUCCESS
end

return {
    Condition = Condition,
    Action = Action,
}
