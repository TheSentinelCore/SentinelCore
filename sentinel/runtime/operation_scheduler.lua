-- sentinel/runtime/operation_scheduler.lua
-- Operation Scheduler: selects which Operation to run based on priority, status, and entry conditions
-- Each Operation follows state machine: Locked → Ready → Active → Completed / Failed / Aborted / Skipped

local OperationScheduler = {}
OperationScheduler.__index = OperationScheduler

---Create a new OperationScheduler
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return table OperationScheduler instance
function OperationScheduler:new(blackboard, event_bus)
    local o = setmetatable({}, OperationScheduler)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile = nil
    o._current_op_id = nil
    o._current_action_index = 1
    return o
end

---Set the runtime profile to schedule from
---@param profile table RuntimeProfile (must have operations table)
function OperationScheduler:set_profile(profile)
    self._profile = profile
    self._current_op_id = nil
    self._current_action_index = 1

    -- Initialize all operation statuses to "ready" if not already set
    if profile and profile.operations then
        for _, op in ipairs(profile.operations) do
            local status = self:get_status(op.id)
            if not status then
                self:set_status(op.id, "locked")
            end
        end
    end
end

---Get the status of an operation
---@param op_id string Operation ID
---@return string|nil Status: "locked" | "ready" | "active" | "completed" | "failed" | "aborted" | "skipped"
function OperationScheduler:get_status(op_id)
    return self._blackboard:get("module.runtime.op_status." .. tostring(op_id))
end

---Set the status of an operation, publishing events on transitions
---@param op_id string Operation ID
---@param status string Status to set
function OperationScheduler:set_status(op_id, status)
    local key = "module.runtime.op_status." .. tostring(op_id)
    local prev = self._blackboard:get(key)
    self._blackboard:set(key, status)

    -- Publish status change event
    if self._event_bus and status ~= prev then
        self._event_bus:publish("operation_status_changed", {
            op_id = op_id,
            previous_status = prev,
            new_status = status,
        })
        if status == "completed" then
            self._event_bus:publish("operation_completed", { op_id = op_id })
        elseif status == "failed" then
            self._event_bus:publish("operation_failed", { op_id = op_id })
        elseif status == "active" then
            self._event_bus:publish("operation_started", { op_id = op_id })
        end
    end
end

---Get the current operation
---@return table|nil
function OperationScheduler:get_current_operation()
    if not self._current_op_id then
        return nil
    end
    return self:_find_op(self._current_op_id)
end

---Get the current action within the current operation
---@return table|nil
function OperationScheduler:get_current_action()
    local op = self:get_current_operation()
    if not op or not op.actions or #op.actions == 0 then
        return nil
    end
    return op.actions[self._current_action_index]
end

---Evaluate a single entry condition against blackboard player state
---@param condition table Condition table with type field
---@return boolean True if condition is satisfied
function OperationScheduler:_evaluate_condition(condition)
    if not condition or not condition.type then
        return true -- no condition = eligible
    end

    if condition.type == "level_below" then
        local level = self._blackboard:get("player.level") or 0
        return level < (condition.max_level or 999)
    elseif condition.type == "level_above" then
        local level = self._blackboard:get("player.level") or 0
        return level >= (condition.min_level or 0)
    elseif condition.type == "race_is" then
        local race = self._blackboard:get("player.race") or ""
        return race == condition.race
    elseif condition.type == "class_is" then
        local class = self._blackboard:get("player.class") or ""
        return class == condition.class
    elseif condition.type == "quest_completed" then
        local completed = self._blackboard:get("player.completed_quests") or {}
        for _, qid in ipairs(completed) do
            if qid == condition.quest_id then
                return true
            end
        end
        return false
    elseif condition.type == "quest_active" then
        local active = self._blackboard:get("player.active_quests") or {}
        for _, qid in ipairs(active) do
            if qid == condition.quest_id then
                return true
            end
        end
        return false
    elseif condition.type == "variable_equals" then
        local var_val = self._blackboard:get(condition.name)
        return var_val == condition.value
    end

    -- Unknown condition types are skipped (treated as eligible)
    return true
end

---Check if all entry conditions for an operation are met
---@param op table Operation
---@return boolean
function OperationScheduler:_check_entry_conditions(op)
    if not op.entry_conditions or #op.entry_conditions == 0 then
        return true
    end
    for _, cond in ipairs(op.entry_conditions) do
        if not self:_evaluate_condition(cond) then
            return false
        end
    end
    return true
end

---Get operations that are ready to run (status=Ready, entry conditions met, sorted by priority)
---@return table List of ready operations
function OperationScheduler:get_ready_operations()
    if not self._profile or not self._profile.operations then
        return {}
    end

    local ready = {}
    for _, op in ipairs(self._profile.operations) do
        local status = self:get_status(op.id)
        if not status then
            status = "locked"
        end

        -- Skip completed/failed/aborted/skipped operations
        if status == "completed" or status == "failed" or status == "aborted" or status == "skipped" then
            -- Skip
        elseif status == "locked" then
            -- Check if entry conditions are now met → transition to ready
            if self:_check_entry_conditions(op) then
                self:set_status(op.id, "ready")
                table.insert(ready, op)
            end
        elseif status == "ready" then
            table.insert(ready, op)
        elseif status == "active" then
            -- Already active, include it
            table.insert(ready, op)
        end
    end

    -- Sort by priority (highest first), then by declaration order (index in operations array)
    -- Build index map for stable sort by declaration order
    local order = {}
    if self._profile and self._profile.operations then
        for i, op in ipairs(self._profile.operations) do
            order[op.id] = i
        end
    end

    table.sort(ready, function(a, b)
        local pa = a.priority or 0
        local pb = b.priority or 0
        if pa ~= pb then
            return pa > pb
        end
        return (order[a.id] or 0) < (order[b.id] or 0)
    end)

    return ready
end

---Select the next operation to execute (highest priority ready operation)
---@return table|nil The selected operation
function OperationScheduler:select_next()
    local ready = self:get_ready_operations()
    if #ready == 0 then
        return nil
    end

    -- Pick the first ready operation (already sorted by priority then declaration order)
    local next_op = ready[1]

    -- If we already have an active operation that's still in the ready list, continue it
    if self._current_op_id then
        local current_status = self:get_status(self._current_op_id)
        if current_status == "active" then
            -- Check if current operation is still the highest priority eligible one
            for _, op in ipairs(ready) do
                if op.id == self._current_op_id then
                    return self:get_current_operation()
                end
            end
        end
    end

    -- Transition selected operation to active
    self._current_op_id = next_op.id
    self._current_action_index = 1
    self:set_status(next_op.id, "active")
    return next_op
end

---Advance to the next action in the current operation
---@return table|nil The next action, or nil if no more actions
function OperationScheduler:advance_action()
    local op = self:get_current_operation()
    if not op or not op.actions then
        return nil
    end

    self._current_action_index = self._current_action_index + 1
    if self._current_action_index > #op.actions then
        return nil
    end

    return op.actions[self._current_action_index]
end

---Mark the current operation as completed and select the next one
---@return table|nil The next operation, or nil if no more ready operations
function OperationScheduler:advance_operation()
    if self._current_op_id then
        self:set_status(self._current_op_id, "completed")
    end
    self._current_op_id = nil
    self._current_action_index = 1
    return self:select_next()
end

---Mark the current operation as failed and select the next one
---@return table|nil The next operation, or nil if no more ready operations
function OperationScheduler:fail_operation()
    if self._current_op_id then
        self:set_status(self._current_op_id, "failed")
    end
    self._current_op_id = nil
    self._current_action_index = 1
    return self:select_next()
end

---Main tick function - called once per frame
---@return table Status info: { current_op_id, current_action_index, status }
function OperationScheduler:tick()
    -- Ensure locked operations get evaluated
    if self._profile then
        for _, op in ipairs(self._profile.operations) do
            local status = self:get_status(op.id)
            if not status or status == "locked" then
                if self:_check_entry_conditions(op) then
                    self:set_status(op.id, "ready")
                elseif not status then
                    self:set_status(op.id, "locked")
                end
            end
        end
    end

    -- If no current operation, try to select one
    if not self._current_op_id then
        self:select_next()
    end

    -- Check if current operation still has a valid status
    if self._current_op_id then
        local current_status = self:get_status(self._current_op_id)
        if current_status == "completed" or current_status == "failed" or current_status == "aborted" or current_status == "skipped" then
            self._current_op_id = nil
            self._current_action_index = 1
            self:select_next()
        end
    end

    return {
        current_op_id = self._current_op_id,
        current_action_index = self._current_action_index,
        status = self._current_op_id and self:get_status(self._current_op_id) or "idle",
    }
end

---Find an operation by ID in the current profile
---@param op_id string
---@return table|nil
function OperationScheduler:_find_op(op_id)
    if not self._profile or not self._profile.operations then
        return nil
    end
    for _, op in ipairs(self._profile.operations) do
        if op.id == op_id then
            return op
        end
    end
    return nil
end

return OperationScheduler
