local BT = require("ai/BehaviorTree")

---@class TacticalPlanner
---@field _tactic Tactic|nil
---@field _current_phase table|nil
local TacticalPlanner = {}
TacticalPlanner.__index = TacticalPlanner

function TacticalPlanner:new()
    return setmetatable({
        _tactic = nil,
        _current_phase = nil,
    }, self)
end

---@param tactic Tactic
function TacticalPlanner:set_tactic(tactic)
    if self._tactic ~= tactic then
        self:reset()
        self._tactic = tactic
    end
end

---@return string|nil
function TacticalPlanner:get_current_phase_name()
    return self._current_phase and self._current_phase.name or nil
end

---@param ctx table
---@param deps table
---@return number BT.Status
function TacticalPlanner:tick(ctx, deps)
    if not self._tactic then return BT.Status.FAILURE end

    local phases = self._tactic:get_phases()
    if #phases == 0 then return BT.Status.FAILURE end

    -- Check exit condition on current phase
    if self._current_phase then
        local ok_exit, should_exit = pcall(self._current_phase.exit_if, ctx)
        if ok_exit and should_exit then
            self._current_phase = nil
        end
    end

    -- If no current phase (or just exited), find best eligible phase
    if not self._current_phase then
        for i = 1, #phases do
            local phase = phases[i]
            local ok_enter, can_enter = pcall(phase.enter_if, ctx)
            if ok_enter and can_enter then
                self._current_phase = phase
                break
            end
        end
    end

    -- No eligible phase found
    if not self._current_phase then
        return BT.Status.FAILURE
    end

    -- Tick current phase
    local ok_tick, status = pcall(self._current_phase.tick, ctx, deps)
    if not ok_tick then
        return BT.Status.FAILURE
    end

    return status or BT.Status.FAILURE
end

--- Reset phase state (current phase cleared). Tactic assignment is preserved.
function TacticalPlanner:reset()
    self._current_phase = nil
end

return TacticalPlanner
