-- sentinel/runtime/diagnostics.lua
-- SENT-6.9: Diagnostics System
-- ADR 002 §19, ADR 008 §12
-- Unified diagnostic format with severity levels and stage attribution

local Diagnostics = {}
Diagnostics.__index = Diagnostics

-- Diagnostic severity levels
Diagnostics.Severity = {
    ERROR = "ERROR",
    WARNING = "WARNING",
    INFO = "INFO",
}

-- Compilation stages (matches Rust Stage enum)
Diagnostics.Stage = {
    StructuralValidation = "Structural Validation",
    ReferenceResolution = "Reference Resolution",
    BlueprintExpansion = "Blueprint Expansion",
    DependencyResolution = "Operation Dependency Resolution",
    GoalCoverage = "Goal Coverage Validation",
    Optimization = "Cross-Operation Optimization",
    Lowering = "Lowering",
}

-- Create an error diagnostic
-- @param code string Error code (e.g., "C-7001")
-- @param stage string Stage that produced this diagnostic
-- @param message string Human-readable message
-- @param entity string|nil Optional entity reference (e.g., operation name)
-- @return table Diagnostic
function Diagnostics.error(code, stage, message, entity)
    return {
        severity = Diagnostics.Severity.ERROR,
        code = code,
        stage = stage,
        message = message,
        entity = entity,
    }
end

-- Create a warning diagnostic
-- @param code string Warning code (e.g., "C-7002")
-- @param stage string Stage that produced this diagnostic
-- @param message string Human-readable message
-- @param entity string|nil Optional entity reference
-- @return table Diagnostic
function Diagnostics.warning(code, stage, message, entity)
    return {
        severity = Diagnostics.Severity.WARNING,
        code = code,
        stage = stage,
        message = message,
        entity = entity,
    }
end

-- Create an info diagnostic
-- @param code string Info code (e.g., "C-7003")
-- @param stage string Stage that produced this diagnostic
-- @param message string Human-readable message
-- @param entity string|nil Optional entity reference
-- @return table Diagnostic
function Diagnostics.info(code, stage, message, entity)
    return {
        severity = Diagnostics.Severity.INFO,
        code = code,
        stage = stage,
        message = message,
        entity = entity,
    }
end

-- Create diagnostic with suggested fix
-- @param diagnostic table Base diagnostic
-- @param suggested_fix string Suggested fix text
-- @return table Diagnostic with suggested_fix
function Diagnostics.with_fix(diagnostic, suggested_fix)
    diagnostic.suggested_fix = suggested_fix
    return diagnostic
end

return Diagnostics