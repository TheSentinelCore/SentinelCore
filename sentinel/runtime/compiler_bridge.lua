-- sentinel/runtime/compiler_bridge.lua
-- SENT-6.11: Bridge between Lua runtime and the Rust compiler
-- Handles serialization, validation, and RuntimeProfile creation
-- Connects all 7 compiler stages

local MigrationRegistry = require("runtime/migration_registry")
local BlueprintRegistry = require("runtime/blueprint_registry")
local ReferenceResolutionStage = require("runtime/stage_reference_resolution")
local BlueprintExpansionStage = require("runtime/stage_blueprint_expansion")
local DependencyResolutionStage = require("runtime/stage_dependency_resolution")
local GoalCoverageStage = require("runtime/stage_goal_coverage")
local OptimizationStage = require("runtime/stage_optimization")
local LoweringStage = require("runtime/stage_lowering")
local Diagnostics = require("runtime/diagnostics")
local RuntimeTypes = require("runtime/runtime_types")

local CompilerBridge = {}
CompilerBridge.__index = CompilerBridge

-- ============================================================================
-- Construction
-- ============================================================================

---Create a new CompilerBridge
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param profile_manager table The ProfileManager instance
---@return table CompilerBridge instance
function CompilerBridge:new(blackboard, event_bus, profile_manager, old_profile)
    local o = setmetatable({}, CompilerBridge)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._last_result = nil
    o._is_compiling = false
    o._old_profile = old_profile -- For incremental compilation
    o._dirty_tracker = nil
    o._migration_registry = MigrationRegistry:new()
    o._blueprint_registry = BlueprintRegistry:new()
    o._reference_stage = ReferenceResolutionStage:new(nil)
    o._expansion_stage = BlueprintExpansionStage:new(o._blueprint_registry)
    o._dependency_stage = DependencyResolutionStage:new()
    o._goal_coverage_stage = GoalCoverageStage:new()
    o._optimization_stage = OptimizationStage:new()
    o._lowering_stage = LoweringStage:new()
    return o
end

-- ============================================================================
-- Public API
-- ============================================================================

---Compile the active profile
---@param callback function callback(err, runtime_profile)
function CompilerBridge:compile(callback)
    if self._is_compiling then
        if callback then
            callback("already compiling", nil)
        end
        return
    end

    self._is_compiling = true
    -- Full compile recomputes from scratch. The lowering cache is global
    -- (keyed by profile name), so clear it to avoid returning a stale
    -- result from an unrelated earlier compile in the same VM.
    LoweringStage.clear_cache()
    local start_time = os.clock()

    self:_publish("compile:started", {})

    -- Step 1: Get active profile
    local profile = self._profile_manager:get_active_profile()
    if not profile then
        self._is_compiling = false
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = { { code = "C-1001", message = "no active profile", stage = Diagnostics.Stage.StructuralValidation, severity = Diagnostics.Severity.ERROR } },
                warnings = {},
            },
            duration_ms = 0,
        }
        self._last_result = result
        self:_publish("compile:failed", result.diagnostics)
        if callback then
            callback(result.diagnostics, nil)
        end
        return
    end

    -- Step 2: Run migration
    local migrate_start = os.clock()
    local migrate_result = self._migration_registry:migrate(profile)
    local migrate_duration = (os.clock() - migrate_start) * 1000
    profile = migrate_result.profile

    self:_publish("compile:stage_complete", {
        stage = "migration",
        duration = migrate_duration,
    })

    -- Step 3: Run inline validation (Stage 1)
    local validate_start = os.clock()
    local validation_diagnostics = self:_run_structural_validation(profile)
    local validate_duration = (os.clock() - validate_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "structural_validation",
        duration = validate_duration,
    })

    -- If validation has errors, fail
    if validation_diagnostics.errors and #validation_diagnostics.errors > 0 then
        local duration_ms = (os.clock() - start_time) * 1000
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = validation_diagnostics,
            duration_ms = duration_ms,
        }
        self._last_result = result
        self._is_compiling = false
        -- Store in blackboard
        if self._blackboard then
            self._blackboard:set("module.runtime.last_compile", result)
        end
        self:_publish("compile:failed", result.diagnostics)
        if callback then
            callback(result.diagnostics, nil)
        end
        return
    end

    -- Stage 3.1: Reference Resolution (Stage 2)
    local all_warnings = {}
    for _, w in ipairs(validation_diagnostics.warnings or {}) do table.insert(all_warnings, w) end

    local ref_start = os.clock()
    local ref_result = self._reference_stage:run(profile)
    profile = ref_result.profile
    local ref_duration = (os.clock() - ref_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "reference_resolution",
        duration = ref_duration,
    })

    -- Stage 3.2: Blueprint Expansion (Stage 3)
    local exp_start = os.clock()
    local exp_result = self._expansion_stage:run(profile)
    profile = exp_result.profile
    local exp_duration = (os.clock() - exp_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "blueprint_expansion",
        duration = exp_duration,
    })

    -- Combine expansion diagnostics
    for _, w in ipairs(exp_result.diagnostics and exp_result.diagnostics.warnings or {}) do table.insert(all_warnings, w) end

    -- Stage 4: Operation Dependency Resolution
    local dep_start = os.clock()
    local ordered_op_ids, dep_diagnostics = self._dependency_stage:run(profile)
    local dep_duration = (os.clock() - dep_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "dependency_resolution",
        duration = dep_duration,
    })

    if dep_diagnostics and dep_diagnostics.errors and #dep_diagnostics.errors > 0 then
        local duration_ms = (os.clock() - start_time) * 1000
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = dep_diagnostics.errors,
                warnings = dep_diagnostics.warnings or {},
            },
            duration_ms = duration_ms,
        }
        self._last_result = result
        self._is_compiling = false
        if self._blackboard then
            self._blackboard:set("module.runtime.last_compile", result)
        end
        self:_publish("compile:failed", result.diagnostics)
        if callback then
            callback(result.diagnostics, nil)
        end
        return
    end

    -- Stage 5: Goal Coverage Validation
    local goal_start = os.clock()
    local goal_diagnostics = self._goal_coverage_stage:run(profile)
    local goal_duration = (os.clock() - goal_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "goal_coverage",
        duration = goal_duration,
    })

    if goal_diagnostics and goal_diagnostics.errors and #goal_diagnostics.errors > 0 then
        local duration_ms = (os.clock() - start_time) * 1000
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = goal_diagnostics.errors,
                warnings = goal_diagnostics.warnings or {},
            },
            duration_ms = duration_ms,
        }
        self._last_result = result
        self._is_compiling = false
        if self._blackboard then
            self._blackboard:set("module.runtime.last_compile", result)
        end
        self:_publish("compile:failed", result.diagnostics)
        if callback then
            callback(result.diagnostics, nil)
        end
        return
    end

    -- Stage 6: Cross-Operation Optimization
    local opt_start = os.clock()
    local opt_result = self._optimization_stage:run(profile, ordered_op_ids or {})
    profile = opt_result.profile
    local opt_duration = (os.clock() - opt_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "optimization",
        duration = opt_duration,
        optimizations = opt_result.optimizations_applied,
    })

    -- Stage 7: Lowering to RuntimeProfile
    local lowering_start = os.clock()
    local lowering_result = self._lowering_stage:run(profile, profile.id or profile.name)
    local runtime_profile = lowering_result.runtime_profile
    local lowering_duration = (os.clock() - lowering_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "lowering",
        duration = lowering_duration,
    })

    -- Combine lowering diagnostics
    if lowering_result.diagnostics.errors and #lowering_result.diagnostics.errors > 0 then
        local duration_ms = (os.clock() - start_time) * 1000
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = lowering_result.diagnostics.errors,
                warnings = all_warnings,
            },
            duration_ms = duration_ms,
        }
        self._last_result = result
        self._is_compiling = false
        if self._blackboard then
            self._blackboard:set("module.runtime.last_compile", result)
        end
        self:_publish("compile:failed", result.diagnostics)
        if callback then
            callback(result.diagnostics, nil)
        end
        return
    end

    for _, w in ipairs(lowering_result.diagnostics.warnings or {}) do table.insert(all_warnings, w) end

    local compile_duration = (os.clock() - start_time) * 1000
    local total_duration = (os.clock() - start_time) * 1000

    -- Success
    local result = {
        success = true,
        runtime_profile = runtime_profile,
        diagnostics = {
            errors = {},
            warnings = all_warnings,
        },
        duration_ms = total_duration,
        optimizations = opt_result.optimizations_applied,
    }
    self._last_result = result
    self._is_compiling = false

    -- Store in blackboard
    if self._blackboard then
        self._blackboard:set("module.runtime.last_compile", result)
    end

    self:_publish("compile:completed", {
        runtime_profile = runtime_profile,
        diagnostics = result.diagnostics,
    })

    if callback then
        callback(nil, runtime_profile)
    end
end

---Compile asynchronously (same as compile for now)
---@param callback function callback(err, runtime_profile)
function CompilerBridge:compile_async(callback)
    -- For now, same implementation as compile
    -- In the future, this will use HTTP or process invocation
    self:compile(callback)
end

---Get the last compile result
---@return table { success = boolean, runtime_profile = table|nil, diagnostics = table, duration_ms = number }
function CompilerBridge:get_last_result()
    return self._last_result
end

---Check if currently compiling
---@return boolean
function CompilerBridge:is_compiling()
    return self._is_compiling
end

---Compile with dirty tracking (incremental compilation)
---@param callback function callback(err, runtime_profile)
---@param profile table|nil Optional new profile; uses active profile if nil
function CompilerBridge:compile_incremental(callback, profile)
    if not profile then
        profile = self._profile_manager:get_active_profile()
    end
    if not profile then
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = { errors = {{ code = "C-3101", message = "no active profile" }}, warnings = {} },
        }
        self._last_result = result
        if callback then callback(result.diagnostics, nil) end
        return
    end

    -- Initialize dirty tracker if needed
    if not self._dirty_tracker then
        self._dirty_tracker = {
            operations = {}, -- op_id -> DirtyState
            structure_dirty = false,
            _dirty_op_ids = function(self) return {} end,
        }
    end

    -- Run regular compile (the Rust side handles the actual incremental logic)
    self:compile(callback)
end

---Mark operation as modified for incremental tracking
---@param op_id string|number Operation ID
function CompilerBridge:mark_dirty(op_id)
    if self._dirty_tracker then
        self._dirty_tracker.operations[op_id] = "Modified"
    end
end

---Get dirty operations list
---@return table Array of dirty operation IDs
function CompilerBridge:get_dirty_operations()
    if self._dirty_tracker then
        return self._dirty_tracker.operations
    end
    return {}

end

---Publish event to event bus
---@param event_name string
---@param payload table
function CompilerBridge:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

-- ============================================================================
-- Private: Structural Validation (Stage 1)
-- ============================================================================

---Inline validation for CompilePipeline
---@param profile table
---@return table errors, table warnings
function CompilerBridge:_inline_validate(profile)
    local diags = self:_run_structural_validation(profile)
    return diags.errors or {}, diags.warnings or {}
end

---Run structural validation on a profile (Stage 1)
---@param profile table
---@return table diagnostics
function CompilerBridge:_run_structural_validation(profile)
    local errors = {}
    local warnings = {}

    if not profile then
        table.insert(errors, {
            code = "V-1001",
            message = "profile is nil",
            stage = Diagnostics.Stage.StructuralValidation,
            severity = Diagnostics.Severity.ERROR
        })
        return { errors = errors, warnings = warnings }
    end

    -- Check profile has a name/ID
    if not profile.name or profile.name == "" then
        table.insert(errors, {
            code = "V-1002",
            message = "profile missing name",
            stage = Diagnostics.Stage.StructuralValidation,
            severity = Diagnostics.Severity.ERROR
        })
    end

    -- Check operations array
    if not profile.operations then
        table.insert(errors, {
            code = "V-1003",
            message = "profile missing operations",
            stage = Diagnostics.Stage.StructuralValidation,
            severity = Diagnostics.Severity.ERROR
        })
        return { errors = errors, warnings = warnings }
    end

    if type(profile.operations) ~= "table" then
        table.insert(errors, {
            code = "V-1004",
            message = "operations must be a table",
            stage = Diagnostics.Stage.StructuralValidation,
            severity = Diagnostics.Severity.ERROR
        })
        return { errors = errors, warnings = warnings }
    end

    -- Check for duplicate operation IDs
    local seen_op_ids = {}
    for i, op in ipairs(profile.operations) do
        if type(op) ~= "table" then
            table.insert(errors, {
                code = "V-1005",
                message = "operation " .. i .. " is not a table",
                stage = Diagnostics.Stage.StructuralValidation,
                severity = Diagnostics.Severity.ERROR
            })
        else
            if op.id then
                if seen_op_ids[op.id] then
                    table.insert(errors, {
                        code = "V-1006",
                        message = "duplicate operation id: " .. tostring(op.id),
                        stage = Diagnostics.Stage.StructuralValidation,
                        severity = Diagnostics.Severity.ERROR
                    })
                else
                    seen_op_ids[op.id] = true
                end
            end

            -- Check for duplicate action IDs
            if op.actions and type(op.actions) == "table" then
                local seen_action_ids = {}
                for j, action in ipairs(op.actions) do
                    if type(action) == "table" and action.id then
                        if seen_action_ids[action.id] then
                            table.insert(errors, {
                                code = "V-1007",
                                message = "duplicate action id in operation '" .. tostring(op.name or "?") .. "': " .. tostring(action.id),
                                stage = Diagnostics.Stage.StructuralValidation,
                                severity = Diagnostics.Severity.ERROR
                            })
                        else
                            seen_action_ids[action.id] = true
                        end
                    end
                end
            end

            -- Check entry conditions structure
            if op.entry_conditions then
                if type(op.entry_conditions) ~= "table" then
                    table.insert(errors, {
                        code = "V-1008",
                        message = "entry_conditions must be a table for operation '" .. tostring(op.name or "?") .. "'",
                        stage = Diagnostics.Stage.StructuralValidation,
                        severity = Diagnostics.Severity.ERROR
                    })
                elseif #op.entry_conditions == 0 then
                    table.insert(warnings, {
                        code = "V-2001",
                        message = "operation '" .. tostring(op.name or "?") .. "' has empty entry_conditions",
                        stage = Diagnostics.Stage.StructuralValidation,
                        severity = Diagnostics.Severity.WARNING
                    })
                end
            end

            -- Check goals structure
            if op.goals then
                if type(op.goals) ~= "table" then
                    table.insert(errors, {
                        code = "V-1009",
                        message = "goals must be a table for operation '" .. tostring(op.name or "?") .. "'",
                        stage = Diagnostics.Stage.StructuralValidation,
                        severity = Diagnostics.Severity.ERROR
                    })
                end
            end
        end
    end

    return { errors = errors, warnings = warnings }
end

-- ============================================================================
-- Public: RuntimeProfile Validation (SENT-6.11)
-- ============================================================================

---Validate that RuntimeProfile is ready for RuntimeExecutor
---@param runtime_profile table RuntimeProfile to validate
---@return table diagnostics
function CompilerBridge:validate_runtime_profile(runtime_profile)
    return self:_run_runtime_profile_validation(runtime_profile)
end

---Run runtime profile validation for RuntimeProfile
---@param runtime_profile table RuntimeProfile to validate
---@return table diagnostics
function CompilerBridge:_run_runtime_profile_validation(runtime_profile)
    local errors = {}
    local warnings = {}

    if not runtime_profile then
        return { errors = { { code = "C-7010", message = "RuntimeProfile is nil", stage = Diagnostics.Stage.Lowering, severity = Diagnostics.Severity.ERROR } }, warnings = warnings }
    end

    if not runtime_profile.profile_id then
        return { errors = { { code = "C-7011", message = "RuntimeProfile missing profile_id", stage = Diagnostics.Stage.Lowering, severity = Diagnostics.Severity.ERROR } }, warnings = warnings }
    end

    if not runtime_profile.operations then
        return { errors = { { code = "C-7012", message = "RuntimeProfile missing operations", stage = Diagnostics.Stage.Lowering, severity = Diagnostics.Severity.ERROR } }, warnings = warnings }
    end

    for _, op in ipairs(runtime_profile.operations) do
        if not op.actions then
            return { errors = { { code = "C-7013", message = "RuntimeOperation '" .. (op.name or "?") .. "' missing actions", stage = Diagnostics.Stage.Lowering, severity = Diagnostics.Severity.ERROR } }, warnings = warnings }
        end
    end

    return { errors = errors, warnings = warnings }
end

return CompilerBridge
