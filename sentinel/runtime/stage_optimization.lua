-- sentinel/runtime/stage_optimization.lua
-- SENT-6.6/6.7: Stage 6 — Cross-Operation Optimization
-- ADR 008 §9, ADR 007 §8-9
-- Walks adjacent Operations in compile order and applies merge rules

local Geometry = require("core/geometry")
local RouteAnalysis = require("runtime/route_analysis")
local GoalCoverage = require("modules/operation/goal_coverage")
local Diagnostics = require("runtime/diagnostics")

local OptimizationStage = {}
OptimizationStage.__index = OptimizationStage

-- Diagnostic codes for this stage (C-6xxx)
OptimizationStage.ErrorCodes = {
    OptimizationRejected = "C-6001",
    GoalValidationFailed = "C-6002",
}

-- Merge distance threshold in game yards (ADR 008 §9)
OptimizationStage.MERGE_DISTANCE_THRESHOLD = 50.0

---Create a new OptimizationStage
---@param query_client table|nil Optional QueryClient for route analysis
---@return table
function OptimizationStage:new(query_client)
    local o = setmetatable({}, OptimizationStage)
    o._query_client = query_client
    o._route_analysis = RouteAnalysis:new(query_client)
    return o
end

---Run Stage 6: Cross-operation optimization
---@param profile table Profile with resolved operations
---@param ordered_op_ids table Array of operation ids in compile order
---@return table result { profile = modified_profile, optimizations_applied = {}, diagnostics = {} }
function OptimizationStage:run(profile, ordered_op_ids)
    local profile_copy = self:_deep_copy(profile)
    local optimizations_applied = {}
    local diagnostics = { errors = {}, warnings = {} }

    if not profile_copy.operations then
        return {
            profile = profile_copy,
            optimizations_applied = optimizations_applied,
            diagnostics = diagnostics,
        }
    end

    -- Build operation lookup
    local op_by_id = {}
    for _, op in ipairs(profile_copy.operations) do
        op_by_id[op.id] = op
    end

    -- Phase 1: Within each operation, reorder if allowed (SENT-6.7)
    for _, op in ipairs(profile_copy.operations) do
        local policy = op.optimization_policy or {}
        if policy.allow_reordering then
            local reordered, reorder_diagnostics = self:_attempt_reordering(op)
            if reordered then
                op.actions = reordered
                for _, d in ipairs(reorder_diagnostics) do
                    table.insert(diagnostics.warnings, d)
                end
            else
                for _, d in ipairs(reorder_diagnostics) do
                    if d.level == "error" then
                        table.insert(diagnostics.errors, d)
                    else
                        table.insert(diagnostics.warnings, d)
                    end
                end
            end
        end
    end

    -- Phase 2: Collapse consecutive Vendor + Repair within each operation (SENT-6.7)
    for _, op in ipairs(profile_copy.operations) do
        local new_actions = {}
        local actions = op.actions or {}
        local i = 1

        while i <= #actions do
            local action = actions[i]

            -- Check for Vendor followed by Repair
            if i < #actions and
               action.action_type == "Vendor" and
               actions[i + 1].action_type == "Repair" then
                -- Validate goal coverage before merge
                if not self:_would_break_goals(op, action, actions[i + 1]) then
                    -- Merge: add Vendor with repair flag, skip Repair
                    local merged_action = self:_merge_vendor_repair(action)
                    merged_action.generated_from = { action.id, actions[i + 1].id }
                    table.insert(new_actions, merged_action)
                    table.insert(optimizations_applied, {
                        description = "Collapsed Vendor '" .. (action.name or "?") .. "' + Repair into single action",
                        operation_id = op.id,
                        action_ids = { action.id, actions[i + 1].id },
                    })
                    i = i + 2
                else
                    table.insert(diagnostics.warnings, {
                        code = OptimizationStage.ErrorCodes.GoalValidationFailed,
                        message = "Skipped Vendor+Repair merge in '" .. (op.name or "?") .. "': would break goal coverage",
                        stage = Diagnostics.Stage.Optimization,
                        severity = Diagnostics.Severity.WARNING,
                        operation_id = op.id,
                        entity = op.name,
                        suggested_fix = "Consider keeping Vendor and Repair as separate actions or adjust goals",
                    })
                    table.insert(new_actions, action)
                    i = i + 1
                end
            else
                table.insert(new_actions, action)
                i = i + 1
            end
        end

        op.actions = new_actions
    end

    -- Phase 3: Redundant GoTo removal across operation boundaries (SENT-6.7)
    -- Check if any trailing action with position into leading GoToAction
    for i = 1, #ordered_op_ids - 1 do
        local prev_id = ordered_op_ids[i]
        local curr_id = ordered_op_ids[i + 1]

        local prev_op = op_by_id[prev_id]
        local curr_op = op_by_id[curr_id]

        if prev_op and curr_op and curr_op.actions and #curr_op.actions > 0 then
            local last_action = prev_op.actions[#prev_op.actions]
            local goto_action = curr_op.actions[1]

            -- Check if first action of curr is GoToAction
            if last_action and goto_action.action_type == "GoToAction" then
                local prev_end_pos = self:_get_operation_end_position(prev_op)
                local goto_dest = self:_extract_goto_destination(goto_action)

                if prev_end_pos and goto_dest then
                    local distance = Geometry.distance(prev_end_pos, goto_dest)

                    if distance <= OptimizationStage.MERGE_DISTANCE_THRESHOLD then
                        -- Validate goal coverage before removal
                        if not self:_would_break_operation_goals(curr_op, goto_action) then
                            local removed_action = table.remove(curr_op.actions, 1)
                            table.insert(optimizations_applied, {
                                description = "Dropped redundant GoToAction '" .. (removed_action.name or "?") .. "' — already at destination from trailing action",
                                operation_id = curr_id,
                                action_ids = { removed_action.id },
                            })
                        else
                            local goto_name = goto_action.name or "?"
                            table.insert(diagnostics.warnings, {
                                code = OptimizationStage.ErrorCodes.GoalValidationFailed,
                                message = "Retained GoToAction '" .. goto_name .. "' in '" .. (curr_op.name or "?") .. "': required by goal coverage",
                                stage = Diagnostics.Stage.Optimization,
                                severity = Diagnostics.Severity.WARNING,
                                operation_id = curr_id,
                                entity = curr_op.name,
                                suggested_fix = "Keep the GoToAction as it is required to reach the destination for a goal",
                            })
                        end
                    end
                end
            end
        end
    end

    return {
        profile = profile_copy,
        optimizations_applied = optimizations_applied,
        diagnostics = diagnostics,
    }
end

---Attempt in-operation reordering using route analysis (SENT-6.7)
---@param op table Operation with actions to potentially reorder
---@return table|nil reordered_actions, table diagnostics
function OptimizationStage:_attempt_reordering(op)
    local actions = op.actions or {}
    if #actions <= 1 then
        return nil, {}
    end

    local policy = op.optimization_policy or {}
    if not policy.allow_reordering then
        return nil, {}
    end

    -- Use route analysis to compute improved ordering
    local reordered = self._route_analysis:reorder_actions(
        actions,
        true,
        function(op_actions)
            return GoalCoverage.analyze_goal_coverage({ actions = op_actions, goals = op.goals })
        end
    )

    if reordered then
        return reordered, { { level = "info", message = "Reordered actions in '" .. (op.name or "?") .. "' for reduced travel distance", stage = Diagnostics.Stage.Optimization, severity = Diagnostics.Severity.INFO } }
    else
        return nil, { { level = "info", message = "No ordering improvement found for '" .. (op.name or "?") .. "'", stage = Diagnostics.Stage.Optimization, severity = Diagnostics.Severity.INFO } }
    end
end

---Check if merging Vendor+Repair would break goal coverage (SENT-6.7)
---@param op table Operation
---@param vendor_action table
---@param repair_action table
---@return boolean would_break
function OptimizationStage:_would_break_goals(op, vendor_action, repair_action)
    if not op.goals then return false end

    -- Check if Repair has explicit goal coverage implications
    -- (e.g., repairing gear is sometimes explicitly tracked)
    for _, goal in ipairs(op.goals) do
        if goal.type == "RepairEquipment" then
            return true
        end
    end

    return false
end

---Check if removing a GoTo action would break operation goal coverage (SENT-6.7)
---@param op table Operation
---@param goto_action table GoToAction to remove
---@return boolean would_break
function OptimizationStage:_would_break_operation_goals(op, goto_action)
    if not op.goals then return false end

    -- Check if the GoTo action is the only coverage for any goal
    for _, goal in ipairs(op.goals) do
        if goal.required ~= false then
            local is_covered_by_goto = false
            if goal.type == "ReachZone" then
                local dest = goto_action.params and goto_action.params.destination
                if dest and dest.zone == goal.zone_name then
                    is_covered_by_goto = true
                end
            elseif goal.type == "ReachWaypoint" then
                is_covered_by_goto = true
            end

            if is_covered_by_goto then
                -- Check if other actions cover this goal
                local other_covered = false
                for _, action in ipairs(op.actions or {}) do
                    if action.id ~= goto_action.id and GoalCoverage.check_action_coverage_for_goal(action, goal) then
                        other_covered = true
                        break
                    end
                end
                if not other_covered then
                    return true
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

---Deep copy a profile table
---@param profile table
---@return table
function OptimizationStage:_deep_copy(profile)
    local function copy_value(v)
        if type(v) ~= "table" then
            return v
        end
        local new_table = {}
        for k, val in pairs(v) do
            new_table[copy_value(k)] = copy_value(val)
        end
        return new_table
    end

    return copy_value(profile)
end

---Merge Vendor + Repair into single Vendor action with repair flag
---@param vendor_action table
---@return table merged_action
function OptimizationStage:_merge_vendor_repair(vendor_action)
    local merged = {}
    for k, v in pairs(vendor_action) do
        merged[k] = v
    end
    merged.params = merged.params or {}
    merged.params.repair = true
    return merged
end

---Extract position from Vendor action
---@param action table
---@return table|nil position {x, y, z, map}
function OptimizationStage:_extract_position_from_vendor(action)
    local params = action.params or {}
    local vendor = params.vendor or params.quest_giver or params.trainer

    if vendor then
        if vendor.npc and vendor.npc.position then
            return vendor.npc.position
        end
        if vendor.position then
            return vendor.position
        end
    end
    -- Check for position in params
    if params.x and params.y then
        return { x = params.x, y = params.y, z = params.z or 0, map = params.map }
    end
    return nil
end

---Extract destination from GoToAction
---@param action table
---@return table|nil position {x, y, z, map}
function OptimizationStage:_extract_goto_destination(action)
    local params = action.params or {}
    if params.destination then
        return params.destination
    end
    if params.x and params.y then
        return { x = params.x, y = params.y, z = params.z or 0, map = params.map }
    end
    return nil
end

---Get the end position of an operation (last action with position)
---@param op table Operation
---@return table|nil position
function OptimizationStage:_get_operation_end_position(op)
    if not op.actions or #op.actions == 0 then
        return nil
    end

    return self:_extract_position_from_action(op.actions[#op.actions])
end

---Extract position from any action payload
---@param action table Action
---@return table|nil position
function OptimizationStage:_extract_position_from_action(action)
    local params = action.params or {}

    -- Check action type first (support both snake_case and display names)
    local action_type = action.action_type or action.type
    if action_type == "GoToAction" or action_type == "goto" then
        return params.destination
    elseif action_type == "TalkToNpc" or action_type == "talk_to_npc" then
        if params.npc and params.npc.position then
            return params.npc.position
        end
    elseif action_type == "PickupQuest" or action_type == "pickup_quest" then
        local npc_guid = params.npc_guid
        if npc_guid and npc_guid ~= "" then
            -- Position not directly available from params
            return nil
        end
    elseif action_type == "TurnInQuest" or action_type == "turnin_quest" then
        if params.npc and params.npc.position then
            return params.npc.position
        end
    elseif action_type == "Vendor" or action_type == "vendor" then
        -- Check for vendor position in various places
        if params.vendor and params.vendor.position then
            return params.vendor.position
        end
        if params.vendor and params.vendor.npc and params.vendor.npc.position then
            return params.vendor.npc.position
        end
    elseif action_type == "Repair" or action_type == "repair" then
        if params.vendor and params.vendor.position then
            return params.vendor.position
        end
        if params.vendor and params.vendor.npc and params.vendor.npc.position then
            return params.vendor.npc.position
        end
    elseif action_type == "FlightPath" then
        if params.to then
            return { x = params.to.x, y = params.to.y, z = params.to.z or 0, map = params.to.map }
        end
    end

    -- Fallback: check for generic position
    if params.x and params.y then
        return { x = params.x, y = params.y, z = params.z or 0 }
    end

    return nil
end

return OptimizationStage