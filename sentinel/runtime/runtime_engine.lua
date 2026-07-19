-- sentinel/runtime/runtime_engine.lua
-- Runtime Engine: Main tick loop that ties scheduler + runtime_context + operation_manager together
-- Called once per frame from the app loop
-- Architecture: RuntimeEngine → RuntimeContext → OperationManager → RuntimeActionExecutor

local OperationScheduler = require("runtime/operation_scheduler")
local RuntimeContext = require("runtime/runtime_context")

local RuntimeEngine = {}
RuntimeEngine.__index = RuntimeEngine

local ENGINE_STATUSES = {
    IDLE = "idle",
    RUNNING = "running",
    PAUSED = "paused",
    COMPLETED = "completed",
    STOPPED = "stopped",
    ERROR = "error",
}

---Create a new RuntimeEngine
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param profile_manager table The ProfileManager instance
---@param nav_adapter table|nil The NavAdapter instance
---@return table RuntimeEngine instance
function RuntimeEngine:new(blackboard, event_bus, profile_manager, nav_adapter)
    local o = setmetatable({}, RuntimeEngine)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._scheduler = OperationScheduler:new(blackboard, event_bus)
    o._context = RuntimeContext:new(blackboard, event_bus)
    o._status = ENGINE_STATUSES.IDLE
    o._profile_id = nil
    o._total_elapsed = 0
    o._tick_count = 0
    o._validation_service = nil
    o._dirty_op_ids = {}
    o._validation_failures = {}
    o._command_history = nil
    o._command_target = nil
    return o
end

---Set the document/target that commands mutate (SENT-8.9). The editor passes
---the profile (or an adapter exposing add_action/remove_action_by_id, etc.).
---@param target any
function RuntimeEngine:set_command_target(target)
    self._command_target = target
end

---Wire the undo/redo command history (SENT-8.9).
---@param command_history table CommandHistory instance
function RuntimeEngine:set_command_history(command_history)
    self._command_history = command_history
    -- Toolbar Undo/Redo buttons publish toolbar:undo / toolbar:redo; route them
    -- to the wired command history (Phase 10 / SENT-10.17).
    if self._event_bus and self._event_bus.subscribe then
        self._event_bus:subscribe("toolbar:undo", function()
            self:undo(nil)
        end)
        self._event_bus:subscribe("toolbar:redo", function()
            self:redo(nil)
        end)
    end
end

---Execute a command through the wired command history (no-op if none).
---@param command table
---@param target any
function RuntimeEngine:execute_command(command, target)
    if self._command_history then
        self._command_history:execute(command, target)
    end
end

---Undo the last command (SENT-8.9). Returns the command history's result.
function RuntimeEngine:undo(target)
    if self._command_history then
        return self._command_history:undo(target or self._command_target)
    end
    return false
end

---Redo the last undone command (SENT-8.9).
function RuntimeEngine:redo(target)
    if self._command_history then
        return self._command_history:redo(target or self._command_target)
    end
    return false
end

---@return table|nil CommandHistory instance
function RuntimeEngine:get_command_history()
    return self._command_history
end

---Wire the continuous-validation service (SENT-8.7).
---@param validation_service table ValidationService instance
function RuntimeEngine:set_validation_service(validation_service)
    self._validation_service = validation_service
end

---Mark an operation dirty so it is revalidated on the next tick.
---@param op_id string
function RuntimeEngine:mark_operation_dirty(op_id)
    if op_id then
        self._dirty_op_ids[op_id] = true
    end
end

---Continuous validation: revalidate only dirty operations. Returns nil if no
---validation service is configured or nothing is dirty. Otherwise returns the
---ValidationService result. If a dirty operation now fails validation, the
---engine halts and publishes `validation_failed`.
function RuntimeEngine:validate()
    if not self._validation_service then
        return nil
    end
    local dirty = {}
    for op_id, _ in pairs(self._dirty_op_ids) do
        table.insert(dirty, op_id)
    end
    if #dirty == 0 then
        return nil
    end

    local profile = self._profile_manager:get_active_profile()
    local result = self._validation_service:validate_profile(profile, dirty)

    -- Clear the dirty set; re-mark any ops that still fail so they are retried.
    self._dirty_op_ids = {}
    self._validation_failures = {}
    if not result.is_valid then
        for _, err in ipairs(result.errors or {}) do
            if err.op_id then
                self._dirty_op_ids[err.op_id] = true
                self._validation_failures[err.op_id] = err
            end
        end
        self._status = ENGINE_STATUSES.STOPPED
        self._blackboard:set("module.runtime.engine_status", self._status)
        -- Surface each error to the ValidationPanel via its existing contract.
        self:_publish("validation:clear", {})
        for _, err in ipairs(result.errors or {}) do
            self:_publish("validation:add", {
                severity = "error",
                code = err.code,
                message = err.message,
                entity_ref = err.op_id,
            })
        end
        self:_publish("validation_failed", {
            profile_id = self._profile_id,
            errors = result.errors,
        })
        self:_publish("log:runtime", {
            level = "ERROR",
            message = "Continuous validation failed: " .. #(result.errors or {}) .. " error(s)",
        })
    else
        -- Clean revalidation: wipe any stale errors from the panel.
        self:_publish("validation:clear", {})
    end
    return result
end

---Hot reload (SENT-8.8): swap in a new profile without tearing down an
---in-flight operation. Re-validates; rejects the swap (keeping the old
---profile) if validation fails. The currently-executing operation is preserved
---if its id still exists in the new profile.
---@param new_profile table Prepared (flat) profile
---@return boolean accepted
function RuntimeEngine:reload_profile(new_profile)
    if not new_profile then
        return false
    end

    if self._validation_service then
        local vr = self._validation_service:validate_profile(new_profile)
        if not vr.is_valid then
            self:_publish("reload_rejected", {
                profile_id = new_profile.id,
                errors = vr.errors,
            })
            self:_publish("log:runtime", {
                level = "ERROR",
                message = "Hot reload rejected (profile '" .. tostring(new_profile.id)
                    .. "' failed validation: " .. #(vr.errors or {}) .. " error(s))",
            })
            return false
        end
    end

    -- Preserve in-flight execution if the current op survives the swap.
    local prev_op_id = self._scheduler._current_op_id
    local prev_idx = self._scheduler._current_action_index
    local keeps_current = false
    for _, op in ipairs(new_profile.operations or {}) do
        if op.id == prev_op_id then
            keeps_current = true
            break
        end
    end

    self._profile_manager:set_active_profile(new_profile)
    self._profile_id = new_profile.id
    self._scheduler:set_profile(new_profile)
    self._context:set_profile(new_profile)

    if keeps_current then
        self._scheduler._current_op_id = prev_op_id
        self._scheduler._current_action_index = prev_idx or 1
    end

    -- Re-validate all operations on next tick.
    for _, op in ipairs(new_profile.operations or {}) do
        self._dirty_op_ids[op.id] = true
    end

    self._blackboard:set("module.runtime.profile_id", self._profile_id)
    self:_publish("profile_reloaded", { profile_id = self._profile_id })
    self:_publish("log:runtime", {
        level = "INFO",
        message = "Hot reload applied (profile '" .. tostring(self._profile_id) .. "')",
    })
    return true
end

---Set the NavAdapter for operation execution
---@param nav_adapter table NavAdapter instance
function RuntimeEngine:set_nav_adapter(nav_adapter)
    self._context:set_nav_adapter(nav_adapter)
end

---Start the engine: initialize, load active profile, set status to running
function RuntimeEngine:start()
    self._status = ENGINE_STATUSES.RUNNING
    self._total_elapsed = 0
    self._tick_count = 0

    -- Load active profile from profile_manager
    local profile = self._profile_manager:get_active_profile()
    local profile_id = self._profile_manager:get_active_profile_id()
    if profile then
        self._profile_id = profile_id
        self._scheduler:set_profile(profile)
        self._context:set_profile(profile)
    end

    -- Store engine status in blackboard
    self._blackboard:set("module.runtime.engine_status", self._status)
    self._blackboard:set("module.runtime.profile_id", self._profile_id)

    self:_publish("engine_started", {
        profile_id = self._profile_id,
        profile_name = profile and profile.name or nil,
    })
end

---Stop the engine: stop execution, set status to stopped
function RuntimeEngine:stop()
    self._status = ENGINE_STATUSES.STOPPED
    self._blackboard:set("module.runtime.engine_status", self._status)
    self:_publish("engine_stopped", { profile_id = self._profile_id })
    self._context:clear()
end

---Pause the engine: pause execution, keep current state
function RuntimeEngine:pause()
    if self._status == ENGINE_STATUSES.RUNNING then
        self._status = ENGINE_STATUSES.PAUSED
        self._blackboard:set("module.runtime.engine_status", self._status)
        self:_publish("engine_paused", { profile_id = self._profile_id })
    end
end

---Resume the engine: resume execution from paused state
function RuntimeEngine:resume()
    if self._status == ENGINE_STATUSES.PAUSED then
        self._status = ENGINE_STATUSES.RUNNING
        self._blackboard:set("module.runtime.engine_status", self._status)
        self:_publish("engine_resumed", { profile_id = self._profile_id })
    end
end

---Set a new profile to execute
---@param profile table RuntimeProfile
function RuntimeEngine:set_profile(profile)
    if not profile then
        return
    end
    self._scheduler:set_profile(profile)
    self._context:set_profile(profile)
    self._profile_manager:set_active_profile(profile)
    if profile.id then
        self._profile_id = profile.id
        self._profile_manager:activate(self._blackboard, profile.id)
    end
    self._blackboard:set("module.runtime.profile_id", self._profile_id)
end

---Main per-frame tick
---@param delta_ms number Milliseconds since last tick
---@return table Result info: { status, current_operation, current_action, profile_id }
function RuntimeEngine:tick(delta_ms)
    if self._status ~= ENGINE_STATUSES.RUNNING then
        return self:get_state()
    end

    self._total_elapsed = self._total_elapsed + (delta_ms or 0)
    self._tick_count = self._tick_count + 1

    -- Step 1: Ensure profile is loaded in scheduler
    if not self._scheduler._profile then
        local profile = self._profile_manager:get_active_profile()
        if profile then
            self._scheduler:set_profile(profile)
            self._context:set_profile(profile)
        else
            -- No profile loaded; nothing to do
            return self:get_state()
        end
    end

    -- Step 1b: Continuous validation of dirty operations (SENT-8.7). If a
    -- dirty op now fails, the engine halts and returns here.
    local validation_result = self:validate()
    if validation_result and not validation_result.is_valid then
        return self:get_state()
    end

    -- Step 2: Tick the scheduler (evaluates conditions, selects next operation)
    local sched_state = self._scheduler:tick()

    -- Step 3: If no current operation, check if all done
    if not sched_state.current_op_id then
        local ready_ops = self._scheduler:get_ready_operations()
        if #ready_ops == 0 then
            -- No more ready operations - mark engine as completed
            self._status = ENGINE_STATUSES.COMPLETED
            self._blackboard:set("module.runtime.engine_status", self._status)
            self:_publish("engine_completed", {
                profile_id = self._profile_id,
                total_elapsed = self._total_elapsed,
                tick_count = self._tick_count,
            })
        end
        return self:get_state()
    end

    -- Step 4: Get current operation and action from scheduler
    local current_op = self._scheduler:get_current_operation()

    if not current_op then
        return self:get_state()
    end

    -- Step 5: Get OperationManager and check current operation status
    local op_manager = self._context:get_operation_manager()
    local op_state = op_manager:get_state()

    -- Step 6: Execute or continue operation via OperationManager
    local exec_result
    local context = { allow_interleave = current_op.interleave ~= false }

    -- Check if OperationManager is already executing this operation
    if op_state.current_operation and op_state.current_operation.id == current_op.id then
        -- OperationManager is already handling this operation; poll for async completion
        if op_state.action_status == "running" then
            exec_result = op_manager:poll()
        else
            -- Previous tick completed all actions synchronously; advance
            exec_result = { status = "succeeded" }
        end
    else
        -- Scheduler selected a new operation; execute it via OperationManager
        -- OperationManager will set _current_operation and run actions
        exec_result = op_manager:execute_operation(current_op, context)
    end

    -- Step 7: Handle operation result
    if exec_result.status == "succeeded" then
        -- Operation completed, advance to next
        self._scheduler:advance_operation()
        op_manager:clear_retry_state()
    elseif exec_result.status == "failed" then
        if exec_result.error ~= "retrying" and exec_result.error ~= "interleaved" then
            self:_publish("operation_failed", {
                op_id = current_op.id,
                error = exec_result.error,
            })
            -- Apply the per-operation failure policy (ADR 002 §23).
            local policy = current_op.failure_policy or { on_fail = "skip" }
            self:_handle_failure(current_op.id, exec_result.error, policy)
        end
    elseif exec_result.status == "running" then
        -- Operation in progress (async or interleaved), continue next tick
    end

    return self:get_state()
end

---Get the current engine state
---@return table { status = string, current_operation = table|nil, current_action = table|nil, profile_id = string|nil, total_elapsed = number, tick_count = number }
function RuntimeEngine:get_state()
    local op_manager = self._context:get_operation_manager()
    local exec_state = op_manager:get_state()
    local current_op = exec_state.current_operation

    -- Get current action from OperationManager's tracked operation
    local current_action
    if current_op and exec_state.current_action_index and exec_state.current_action_index > 0 then
        current_action = current_op.actions and current_op.actions[exec_state.current_action_index]
    end

    -- Fall back to scheduler if OperationManager doesn't have active op
    if not current_op then
        current_op = self._scheduler:get_current_operation()
        current_action = self._scheduler:get_current_action()
    end

    return {
        status = self._status,
        current_operation = current_op,
        current_action = current_action,
        profile_id = self._profile_id,
        total_elapsed = self._total_elapsed,
        tick_count = self._tick_count,
        action_status = exec_state.action_status,
        current_action_index = exec_state.current_action_index,
    }
end

---Apply the failure-recovery hierarchy (ADR 002 §23).
--- Escalation ladder: Retry (handled in ActionExecutor) -> Skip ->
--- Abort Operation -> Abort Profile. The ladder step is chosen by the
--- operation's `failure_policy.on_fail`:
---   "skip"            -> mark op skipped, engine continues (default)
---   "abort_operation" -> mark op aborted, engine continues
---   "abort_profile"   -> abort op AND move engine to error state
---@param op_id string
---@param error string
---@param policy table { on_fail = "skip"|"abort_operation"|"abort_profile" }
function RuntimeEngine:_handle_failure(op_id, error, policy)
    policy = policy or { on_fail = "skip" }
    local action = policy.on_fail or "skip"

    -- Mark the operation per the policy.
    if action == "abort_operation" or action == "abort_profile" then
        self._scheduler:set_status(op_id, "aborted")
    else
        self._scheduler:set_status(op_id, "skipped")
    end

    self:_publish("operation_" .. (action == "skip" and "skipped" or "aborted"), {
        op_id = op_id,
        error = error,
        policy = action,
    })

    if action == "abort_profile" then
        self._status = ENGINE_STATUSES.ERROR
        self._blackboard:set("module.runtime.engine_status", self._status)
        self:_publish("profile_aborted", { op_id = op_id, error = error })
    end
end

---Publish an event
---@param event_name string
---@param payload table
function RuntimeEngine:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

return RuntimeEngine
