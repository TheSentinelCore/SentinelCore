-- sentinel/runtime/validation_service.lua
-- SENT-8.7: Continuous Validation Service (ADR 002 §11, §19)
-- Revalidates only dirty Operations. Aggregates diagnostics in the four
-- ADR 002 §19 categories: structural, goal-coverage, dependency, reference.

local GoalCoverage = require("modules/operation/goal_coverage")
local Diagnostics = require("runtime/diagnostics")

local ValidationService = {}
ValidationService.__index = ValidationService

---Create a new ValidationService
---@return table
function ValidationService:new()
    return setmetatable({}, ValidationService)
end

---Validate a single operation (goal coverage + dependency sanity).
---@param operation table
---@param profile table|nil Full profile (for dependency references)
---@return table { all_covered = boolean, errors = {}, warnings = {} }
function ValidationService:validate_operation(operation, profile)
    local errors = {}
    local warnings = {}

    -- Goal coverage (reuses the compiler-stage logic, ADR 008 §8).
    if operation.goals and #operation.goals > 0 then
        local cov = GoalCoverage.analyze_goal_coverage(operation)
        for _, g in ipairs(cov.uncovered_required or {}) do
            table.insert(errors, {
                code = "V-GOAL",
                message = "Required goal '" .. (g.type or "?") .. "' on Operation '"
                    .. (operation.name or "?") .. "' not covered by any action",
                stage = Diagnostics.Stage.GoalCoverage,
                severity = Diagnostics.Severity.ERROR,
                entity = operation.name,
                op_id = operation.id,
            })
        end
        for _, g in ipairs(cov.uncovered_optional or {}) do
            table.insert(warnings, {
                code = "V-GOAL-OPT",
                message = "Optional goal '" .. (g.type or "?") .. "' on Operation '"
                    .. (operation.name or "?") .. "' not covered by any action",
                stage = Diagnostics.Stage.GoalCoverage,
                severity = Diagnostics.Severity.WARNING,
                entity = operation.name,
                op_id = operation.id,
            })
        end
    end

    -- Dependency sanity (per-op, ADR 008 §7): referenced ops exist, no self-dep.
    if profile and operation.dependencies then
        local ids = {}
        for _, op in ipairs(profile.operations or {}) do ids[op.id] = true end
        for _, dep in ipairs(operation.dependencies) do
            local dep_id = dep.operation_id or dep.id
            if dep_id == operation.id then
                table.insert(errors, {
                    code = "V-DEP-SELF",
                    message = "Operation '" .. operation.name .. "' depends on itself",
                    stage = Diagnostics.Stage.Dependency,
                    severity = Diagnostics.Severity.ERROR,
                    entity = operation.name,
                    op_id = operation.id,
                })
            elseif dep_id and not ids[dep_id] then
                table.insert(errors, {
                    code = "V-DEP-MISSING",
                    message = "Operation '" .. operation.name .. "' depends on missing Operation '"
                        .. tostring(dep_id) .. "'",
                    stage = Diagnostics.Stage.Dependency,
                    severity = Diagnostics.Severity.ERROR,
                    entity = operation.name,
                    op_id = operation.id,
                })
            end
        end
    end

    return {
        all_covered = #errors == 0,
        errors = errors,
        warnings = warnings,
    }
end

---Validate a profile, scoped to dirty operations when provided.
---@param profile table
---@param dirty_op_ids table|nil List of operation ids to validate; nil = all
---@return table { errors = {}, warnings = {} }
function ValidationService:validate_profile(profile, dirty_op_ids)
    local errors = {}
    local warnings = {}

    if not profile or not profile.operations then
        return { errors = errors, warnings = warnings }
    end

    local scope = profile.operations
    if dirty_op_ids then
        local wanted = {}
        for _, id in ipairs(dirty_op_ids) do wanted[id] = true end
        scope = {}
        for _, op in ipairs(profile.operations) do
            if wanted[op.id] then table.insert(scope, op) end
        end
    end

    for _, op in ipairs(scope) do
        local res = self:validate_operation(op, profile)
        for _, e in ipairs(res.errors) do table.insert(errors, e) end
        for _, w in ipairs(res.warnings) do table.insert(warnings, w) end
    end

    return { is_valid = #errors == 0, errors = errors, warnings = warnings }
end

return ValidationService
