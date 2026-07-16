local Builder = {}
Builder.__index = Builder

function Builder:new(blackboard)
    local o = setmetatable({}, Builder)
    o._blackboard = blackboard
    return o
end

function Builder:refresh(summary)
    summary = summary or {}
    self._blackboard:set("bg.active", summary.active == true)
    self._blackboard:set("bg.key", summary.bg_key)
    self._blackboard:set("bg.side", summary.side)
    self._blackboard:set("bg.state", summary.state)
    self._blackboard:set("bg.objective_id", summary.objective_id)
    self._blackboard:set("bg.nav_target", summary.nav_target)
    self._blackboard:set("bg.route_id", summary.route_id)
    self._blackboard:set("bg.strategy_id", summary.strategy_id)
    self._blackboard:set("bg.strategy_label", summary.strategy_label)
    self._blackboard:set("bg.selected_objective_id", summary.selected_objective_id)
    self._blackboard:set("bg.selected_objective", summary.selected_objective)
    self._blackboard:set("bg.selection_meta", summary.selection_meta)
    self._blackboard:set("bg.selection_failure_reason", summary.selection_failure_reason)
    self._blackboard:set("bg.candidates_top3", summary.candidates_top3)
    self._blackboard:set("bg.objective_states", summary.objective_states)
    self._blackboard:set("bg.capture_focus_objective_id", summary.capture_focus_objective_id)
    self._blackboard:set("bg.momentum_score", summary.momentum_score)
    self._blackboard:set("bg.bootstrap.phase", summary.bootstrap_phase)
    self._blackboard:set("bg.bootstrap.route_id", summary.bootstrap_route_id)
    self._blackboard:set("bg.bootstrap.ready", summary.bootstrap_ready == true)
    self._blackboard:set("bg.bootstrap.failed_attempts", tonumber(summary.bootstrap_failed_attempts) or 0)
    self._blackboard:set("bg.bootstrap.reason", summary.bootstrap_reason)
    self._blackboard:set("bg.objective_approach.mode", summary.objective_approach_mode)
    self._blackboard:set("bg.objective_approach.objective_id", summary.objective_approach_objective_id)
    self._blackboard:set("bg.objective_approach.stage", summary.objective_approach_stage)
    self._blackboard:set("bg.objective_approach.variant", tonumber(summary.objective_approach_variant) or 1)
    self._blackboard:set("bg.objective_approach.last_variant_shift_at_ms", tonumber(summary.objective_approach_last_variant_shift_at_ms) or 0)
    self._blackboard:set("bg.objective_anchor", summary.objective_anchor)
    self._blackboard:set("bg.objective_approach_source", summary.objective_approach_source)
    self._blackboard:set("bg.route_source", summary.route_source)
    self._blackboard:set("bg.nav_authority", summary.nav_authority)
end

return Builder
