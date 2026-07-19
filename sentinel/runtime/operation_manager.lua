-- sentinel/runtime/operation_manager.lua
-- SENT-8.4: Runtime Operation Manager
-- Executes RuntimeOperations sequentially via RuntimeActionExecutor
-- ADR 008 §22 - Interleave support, abort on failure, blackboard state tracking, event emission

local RuntimeActionExecutor = require("runtime/runtime_action_executor")

local OperationManager = {}
OperationManager.__index = OperationManager

local OPERATION_STATES = {
    IDLE = "idle",
    LOCKED = "locked",
    READY = "ready",
    ACTIVE = "active",
    COMPLETED = "completed",
    FAILED = "failed",
    ABORTED = "aborted",
    SKIPPED = "skipped",
}

---Create a new OperationManager
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param nav_adapter table|nil The NavAdapter instance
---@return table OperationManager instance
function OperationManager:new(blackboard, event_bus, nav_adapter)
    local o = setmetatable({}, OperationManager)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._nav_adapter = nav_adapter
    o._executor = RuntimeActionExecutor:new(blackboard, event_bus, nav_adapter)
    o._current_operation = nil
    o._current_action_index = 0
    o._start_time_ms = nil
    return o
end

---Get the current operation
---@return table|nil Current operation
function OperationManager:get_current_operation()
    return self._current_operation
end

---Get the current action index
---@return number Current action index (1-based)
function OperationManager:get_current_action_index()
    return self._current_action_index
end

---Get the operation status from blackboard
---@param op_id string|nil Operation ID (uses current if nil)
---@return string Status: one of OPERATION_STATES
function OperationManager:get_status(op_id)
    if not op_id then
        op_id = self._current_operation and self._current_operation.id
    end
    if not op_id then
        return OPERATION_STATES.IDLE
    end
    return self._blackboard:get("module.operation." .. tostring(op_id) .. ".status", OPERATION_STATES.LOCKED)
end

---Set operation status in blackboard with event emission
---@param op_id string Operation ID
---@param status string New status
---@param error_msg string|nil Optional error message for failed/aborted states
function OperationManager:set_status(op_id, status, error_msg)
    local key = "module.operation." .. tostring(op_id) .. ".status"
    local prev = self._blackboard:get(key)
    self._blackboard:set(key, status)

    if self._event_bus and status ~= prev then
        self._event_bus:publish("operation_status_changed", {
            op_id = op_id,
            previous_status = prev,
            new_status = status,
        })

        if status == OPERATION_STATES.COMPLETED then
            self._event_bus:publish("operation_completed", { op_id = op_id })
        elseif status == OPERATION_STATES.FAILED then
            self._event_bus:publish("operation_failed", { op_id = op_id, error = error_msg })
        elseif status == OPERATION_STATES.ABORTED then
            self._event_bus:publish("operation_aborted", { op_id = op_id, error = error_msg })
        elseif status == OPERATION_STATES.ACTIVE then
            self._event_bus:publish("operation_started", { op_id = op_id })
        end
    end
end

---Execute an operation, running all actions sequentially
---@param operation table RuntimeOperation with actions table
---@param context table|nil Execution context with allow_interleave option
---@return table Result: { status = "succeeded"|"failed"|"aborted", error = string|nil }
function OperationManager:execute_operation(operation, context)
    if not operation or not operation.id then
        return { status = "failed", error = "invalid operation: missing id" }
    end

    if not operation.actions or #operation.actions == 0 then
        self:set_status(operation.id, OPERATION_STATES.COMPLETED)
        return { status = "succeeded" }
    end

    self._current_operation = operation
    self._current_action_index = 1
    self._start_time_ms = self:_get_time_ms()

    -- Initialize status if locked
    local current_status = self:get_status(operation.id)
    if current_status == OPERATION_STATES.LOCKED then
        self:set_status(operation.id, OPERATION_STATES.ACTIVE)
    else
        self:set_status(operation.id, OPERATION_STATES.ACTIVE)
    end

    local allow_interleave = context and context.allow_interleave == true
    local action_results = {}

    for i, action in ipairs(operation.actions) do
        self._current_action_index = i

        -- Set current action in blackboard for context access
        self._blackboard:set("module.operation." .. tostring(operation.id) .. ".current_action", i)

        local result = self._executor:execute(action)

        -- Track result
        action_results[i] = {
            action_id = action.id,
            status = result.status,
            error = result.error,
        }

        if result.status == "succeeded" then
            -- Action succeeded, continue to next
        elseif result.status == "failed" then
            if result.error == "retrying" then
                -- Retry is in progress, will be polled on next tick
                return { status = "running", error = "action_retrying" }
            end
            -- Action failed - abort operation
            self:_cleanup_operation(operation.id)
            self:set_status(operation.id, OPERATION_STATES.FAILED, result.error)
            return { status = "failed", error = result.error }
        elseif result.status == "running" then
            -- Async action - if allow_interleave, yield; otherwise poll
            if allow_interleave then
                return { status = "running", error = "interleaved" }
            end
            -- Poll until completion (blocking behavior)
            while result.status == "running" do
                result = self._executor:poll(action)
            end
            if result.status == "succeeded" then
                -- Continue
            else
                self:_cleanup_operation(operation.id)
                self:set_status(operation.id, OPERATION_STATES.FAILED, result.error)
                return { status = "failed", error = result.error }
            end
        end
    end

    -- All actions completed successfully
    self:_cleanup_operation(operation.id)
    self:set_status(operation.id, OPERATION_STATES.COMPLETED)
    self._blackboard:set("module.operation." .. tostring(operation.id) .. ".current_action", nil)
    self._current_operation = nil
    self._current_action_index = 0

    return {
        status = "succeeded",
        elapsed_ms = self:_get_time_ms() - self._start_time_ms,
        action_results = action_results,
    }
end

---Execute a single action within the current operation (for interleaved execution)
---@param action table RuntimeAction to execute
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil }
function OperationManager:execute_action(action)
    if not self._current_operation then
        return { status = "failed", error = "no active operation" }
    end

    return self._executor:execute(action)
end

---Poll the current operation to check for running action completion
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil }
function OperationManager:poll()
    if not self._current_operation then
        return { status = "failed", error = "no active operation" }
    end

    local op = self._current_operation
    local action = op.actions[self._current_action_index]

    if not action then
        return { status = "failed", error = "no current action" }
    end

    local exec_state = self._executor:get_state()
    if exec_state.status ~= "running" then
        return { status = "failed", error = "action not running" }
    end

    local result = self._executor:poll(action)

    if result.status == "succeeded" then
        -- Advance to next action
        self._current_action_index = self._current_action_index + 1

        if self._current_action_index > #op.actions then
            -- Operation complete
            self:_cleanup_operation(op.id)
            self:set_status(op.id, OPERATION_STATES.COMPLETED)
            self._blackboard:set("module.operation." .. tostring(op.id) .. ".current_action", nil)
            self._current_operation = nil
            self._current_action_index = 0

            return { status = "succeeded" }
        else
            -- Continue with next action
            self._blackboard:set("module.operation." .. tostring(op.id) .. ".current_action", self._current_action_index)
            local next_action = op.actions[self._current_action_index]
            if next_action then
                return self._executor:execute(next_action)
            end
            return { status = "succeeded" }
        end

    elseif result.status == "failed" then
        if result.error ~= "retrying" then
            self:_cleanup_operation(op.id)
            self:set_status(op.id, OPERATION_STATES.FAILED, result.error)
            self._current_operation = nil
            self._current_action_index = 0
        end
        return result

    end

    return result
end

---Abort the current operation with cleanup
---@param error_msg string|nil Optional error message
function OperationManager:abort(error_msg)
    if self._current_operation then
        self:_cleanup_operation(self._current_operation.id)
        self:set_status(self._current_operation.id, OPERATION_STATES.ABORTED, error_msg)
        self._blackboard:set("module.operation." .. tostring(self._current_operation.id) .. ".current_action", nil)
        self._current_operation = nil
        self._current_action_index = 0
    end
end

---Cleanup operation state in blackboard
---@param op_id string Operation ID
function OperationManager:_cleanup_operation(op_id)
    self._blackboard:set("module.operation." .. tostring(op_id) .. ".current_action", nil)
    self._executor:clear_retry_state()
end

---Clear retry state from executor
function OperationManager:clear_retry_state()
    if self._executor.clear_retry_state then
        self._executor:clear_retry_state()
    else
        self._blackboard:set("module.runtime.retry_state", nil)
    end
end

---Get execution state
---@return table { current_operation, current_action_index, status, elapsed_ms }
function OperationManager:get_state()
    local exec_state = self._executor:get_state()
    return {
        current_operation = self._current_operation,
        current_action_index = self._current_action_index,
        action_status = exec_state.status,
        elapsed_ms = self._start_time_ms and (self:_get_time_ms() - self._start_time_ms) or nil,
    }
end

---Get current time in milliseconds
---@return number Time in ms
function OperationManager:_get_time_ms()
    if core and core.game_time then
        return core.game_time()
    end
    return os.clock() * 1000
end

---Reset operation state for a specific operation
---@param op_id string Operation ID to reset
function OperationManager:reset_operation(op_id)
    if not op_id then
        return
    end
    self._blackboard:set("module.operation." .. tostring(op_id) .. ".status", OPERATION_STATES.READY)
    self._blackboard:set("module.operation." .. tostring(op_id) .. ".current_action", nil)
end

---Clear all operation state from blackboard
function OperationManager:clear()
    local snapshot = self._blackboard:snapshot("module.operation.")
    for key, _ in pairs(snapshot) do
        self._blackboard:clear(key)
    end
    self._current_operation = nil
    self._current_action_index = 0
    self._start_time_ms = nil
end

return OperationManager