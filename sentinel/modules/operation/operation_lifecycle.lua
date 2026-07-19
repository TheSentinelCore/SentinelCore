-- sentinel/modules/operation/operation_lifecycle.lua
-- SENT-5.6: Operation Lifecycle State Machine
-- ADR 007 §13-14

local OperationLifecycle = {}
OperationLifecycle.__index = OperationLifecycle

OperationLifecycle.Status = {
    Locked = "Locked",
    Ready = "Ready",
    Active = "Active",
    Completed = "Completed",
    Failed = "Failed",
    Aborted = "Aborted",
    Skipped = "Skipped",
}

function OperationLifecycle:new(blackboard)
    local o = setmetatable({}, OperationLifecycle)
    o._blackboard = blackboard
    o._states = {}
    return o
end

function OperationLifecycle:create(operation_id)
    if not operation_id then
        return nil
    end

    self._states[operation_id] = {
        status = OperationLifecycle.Status.Locked,
        transitions = {},
        skip_reason = nil
    }

    return operation_id
end

function OperationLifecycle:set_status(operation_id, status, skip_reason)
    if not operation_id or not status then
        return false
    end

    local state = self._states[operation_id]
    if not state then
        self:create(operation_id)
        state = self._states[operation_id]
    end

    local valid_transition = OperationLifecycle._validate_transition(
        state.status, status)

    if not valid_transition then
        return false
    end

    state.previous_status = state.status
    state.status = status

    if status == OperationLifecycle.Status.Skipped then
        state.skip_reason = skip_reason
    end

    if self._blackboard then
        self._blackboard:set("operation." .. operation_id .. ".status", status)
    end

    return true
end

function OperationLifecycle._validate_transition(from_status, to_status)
    local valid_transitions = {
        [OperationLifecycle.Status.Locked] = {
            Ready = true,
            Skipped = true,
        },
        [OperationLifecycle.Status.Ready] = {
            Active = true,
            Skipped = true,
            Locked = true,
        },
        [OperationLifecycle.Status.Active] = {
            Completed = true,
            Failed = true,
            Aborted = true,
        },
        [OperationLifecycle.Status.Completed] = {},
        [OperationLifecycle.Status.Failed] = {},
        [OperationLifecycle.Status.Aborted] = {},
        [OperationLifecycle.Status.Skipped] = {},
    }

    local valid_to = valid_transitions[from_status]
    if not valid_to then
        return true
    end

    return valid_to[to_status] == true
end

function OperationLifecycle:get_status(operation_id)
    if not operation_id then
        return nil
    end

    local state = self._states[operation_id]
    if not state then
        return OperationLifecycle.Status.Locked
    end

    if self._blackboard then
        local bb_status = self._blackboard:get("operation." .. operation_id .. ".status")
        if bb_status then
            return bb_status
        end
    end

    return state.status
end

function OperationLifecycle:get_skip_reason(operation_id)
    local state = self._states[operation_id]
    if not state then
        return nil
    end
    return state.skip_reason
end

function OperationLifecycle:can_transition(operation_id, to_status)
    local current = self:get_status(operation_id)
    return OperationLifecycle._validate_transition(current, to_status)
end

function OperationLifecycle:is_terminal(operation_id)
    local status = self:get_status(operation_id)
    return status == OperationLifecycle.Status.Completed
        or status == OperationLifecycle.Status.Failed
        or status == OperationLifecycle.Status.Aborted
        or status == OperationLifecycle.Status.Skipped
end

function OperationLifecycle:transition_to_ready(operation_id, entry_conditions_met, goals_already_satisfied)
    if goals_already_satisfied then
        return self:set_status(operation_id, OperationLifecycle.Status.Skipped, "Goals already satisfied")
    end

    if not entry_conditions_met then
        return self:set_status(operation_id, OperationLifecycle.Status.Locked)
    end

    return self:set_status(operation_id, OperationLifecycle.Status.Ready)
end

function OperationLifecycle:transition_to_active(operation_id)
    return self:set_status(operation_id, OperationLifecycle.Status.Active)
end

function OperationLifecycle:transition_to_completed(operation_id)
    return self:set_status(operation_id, OperationLifecycle.Status.Completed)
end

function OperationLifecycle:transition_to_failed(operation_id)
    return self:set_status(operation_id, OperationLifecycle.Status.Failed)
end

function OperationLifecycle:transition_to_aborted(operation_id)
    return self:set_status(operation_id, OperationLifecycle.Status.Aborted)
end

function OperationLifecycle:evaluate_exit_and_transition(operation, context)
    if not operation or not operation.id then
        return nil
    end

    local ConditionEvaluator = require("modules/operation/condition_evaluator")
    local eval = ConditionEvaluator:new(self._blackboard)

    local exit_result = eval.evaluate_exit_conditions(operation, context)

    if exit_result.abort then
        self:transition_to_aborted(operation.id)
        return OperationLifecycle.Status.Aborted
    end

    if exit_result.failure then
        self:transition_to_failed(operation.id)
        return OperationLifecycle.Status.Failed
    end

    if exit_result.success then
        self:transition_to_completed(operation.id)
        return OperationLifecycle.Status.Completed
    end

    return nil
end

function OperationLifecycle:get_all_states()
    return self._states
end

function OperationLifecycle:reset(operation_id)
    if operation_id then
        self._states[operation_id] = {
            status = OperationLifecycle.Status.Locked,
            transitions = {},
            skip_reason = nil
        }
    end
end

return OperationLifecycle