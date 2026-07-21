-- Runtime Profile Executor
-- Loads compiled Sentinel Questing profiles and executes them

local RuntimeAction = require("runtime/lua/runtime_action")

local RuntimeProfileExecutor = {}
RuntimeProfileExecutor.__index = RuntimeProfileExecutor

function RuntimeProfileExecutor:new(json_path)
    local o = setmetatable({}, RuntimeProfileExecutor)
    o._json_path = json_path
    o._profile = nil
    o._current_operation = 1
    o._completed_operations = {}
    o._variables = {}
    o._wait_start = nil
    o._initialized = false
    return o
end

function RuntimeProfileExecutor:load()
    local file = io.open(self._json_path, "r")
    if not file then
        return false, "Could not open profile: " .. self._json_path
    end

    local content = file:read("*a")
    file:close()

    -- Parse JSON using Sylvanas JSON utilities
    local success, decoded = pcall(function()
        return _G.JSON or require("JSON").decode(content)
    end)

    if not success then
        return false, "JSON parse error: " .. tostring(decoded)
    end

    self._profile = decoded
    self._initialized = true
    return true
end

function RuntimeProfileExecutor:current_operation()
    if not self._initialized or not self._profile then
        return nil
    end

    local ops = self._profile.operations
    if not ops or self._current_operation > #ops then
        return nil
    end

    return ops[self._current_operation]
end

function RuntimeProfileExecutor:execute()
    if not self._initialized or not self._profile then
        return "error", "Not initialized"
    end

    local op = self:current_operation()
    if not op then
        return "finished", "No more operations"
    end

    -- Check operation conditions
    if op.conditions and #op.conditions > 0 then
        for _, cond in ipairs(op.conditions) do
            if not self:evaluate_condition(cond) then
                -- Skip this operation
                self._current_operation = self._current_operation + 1
                return self:execute()
            end
        end
    end

    -- Execute each action in the operation
    for _, action in ipairs(op.actions) do
        local result = RuntimeAction.execute(action, self)
        if result ~= "success" then
            return "running", op.name .. ": " .. result
        end
    end

    -- Operation complete
    table.insert(self._completed_operations, self._current_operation)
    self._current_operation = self._current_operation + 1

    return self:execute()
end

function RuntimeProfileExecutor:evaluate_condition(condition)
    -- Placeholder - real implementation would use condition parsing
    -- Supports: QuestCompleted, LevelAtLeast, HasItem, etc.
    return true
end

function RuntimeProfileExecutor:is_at_npc(npc_entry)
    return _G.SentinelCore.IsAtNpc(npc_entry) or
           (_G.ObjectManager and _G.ObjectManager:GetDistanceToNpc(npc_entry) < 5)
end

function RuntimeProfileExecutor:is_at_destination(destination, tolerance)
    return _G.SentinelCore.IsInZone(destination)
end

return RuntimeProfileExecutor