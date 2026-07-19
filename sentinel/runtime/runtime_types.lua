-- sentinel/runtime/runtime_types.lua
-- SENT-6.8: Runtime Profile Types
-- ADR 008 §10, §77-78
-- Runtime types: RuntimeProfile, RuntimeOperation, RuntimeAction

local RuntimeTypes = {}

-- Default retry policy for actions (ADR 008 §77)
local DEFAULT_RETRY_POLICY = {
    max_attempts = 3,
    backoff_ms = 1000,
    backoff_multiplier = 1.0,
}

-- Default timeout for actions (milliseconds, ADR 008 §78)
local DEFAULT_TIMEOUT_MS = 10000

-- RuntimeAction - A compiled action ready for the runtime engine
-- ADR 008 §77-78: { id, payload, retry_policy, timeout, generated_from }
-- @param action table Source action
-- @return table RuntimeAction
function RuntimeTypes.new_runtime_action(action)
    local generated_from = action.generated_from

    -- Preserve generated_from if it's a single value
    if action.generated_from then
        if type(action.generated_from) == "table" then
            generated_from = action.generated_from[1] or action.generated_from.action_id
        end
    end

    -- Normalize action_type to payload.type for ADR 008 compliance
    local payload = action.payload or { type = action.action_type or action.type or "unknown" }

    return {
        id = action.id or action.action_id,
        payload = payload,
        retry_policy = action.retry_policy or DEFAULT_RETRY_POLICY,
        timeout = action.timeout or action.timeout_ms or DEFAULT_TIMEOUT_MS,
        generated_from = generated_from,
    }
end

-- RuntimeOperation - A compiled operation ready for the runtime engine
-- @param operation table Source operation
-- @return table RuntimeOperation
function RuntimeTypes.new_runtime_operation(operation)
    local runtime_actions = {}
    for _, action in ipairs(operation.actions or {}) do
        table.insert(runtime_actions, RuntimeTypes.new_runtime_action(action))
    end

    return {
        id = operation.id,
        name = operation.name,
        action_type = operation.action_type,
        entry_conditions = operation.entry_conditions,
        exit_conditions = operation.exit_conditions,
        goals = operation.goals,
        priority = operation.priority,
        actions = runtime_actions,
    }
end

-- RuntimeProfile - Immutable, fully resolved execution profile
-- @param profile table Source profile
-- @param profile_id string Source profile ID
-- @return table RuntimeProfile
function RuntimeTypes.new_runtime_profile(profile, profile_id)
    local operations = {}
    for _, op in ipairs(profile.operations or {}) do
        table.insert(operations, RuntimeTypes.new_runtime_operation(op))
    end

    local profile_hash = ""
    if profile then
        profile_hash = RuntimeTypes._compute_content_hash(profile)
    end

    return {
        schema_version = "1.0",
        compiler_version = "0.1.0",
        profile_id = profile_id or profile.id or profile.name,
        source_profile_id = profile_id,
        metadata = {
            compiled_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            source_hash = profile_hash,
            duration_ms = 0,
        },
        operations = operations,
        diagnostics = {
            errors = {},
            warnings = {},
        },
    }
end

-- Compute simple hash for a string
-- @param str string String to hash
-- @return string hex hash
function RuntimeTypes._compute_simple_hash(str)
    local hash = 5381
    for i = 1, #str do
        local byte = string.byte(str, i)
        hash = ((hash * 33) + byte) % 2^32
    end
    return string.format("%08x", hash)
end

-- Deterministic content hash over an arbitrary Lua table. Walks keys and
-- values directly (not via JSON) so it captures every field — including
-- action `params` and numeric keys — that the JSON encoder silently drops.
-- Used for the ADR-008 §15 source_profile_hash cache key.
-- @param value any Table/value to hash
-- @param seen table|nil Cycle guard (internal)
-- @return string hex hash
function RuntimeTypes._compute_content_hash(value, seen)
    seen = seen or {}
    local hash = 5381
    local function mix(n)
        hash = ((hash * 33) + (n % 256)) % 2^32
    end
    local t = type(value)
    if t == "nil" then mix(0)
    elseif t == "boolean" then mix(value and 1 or 2)
    elseif t == "number" then
        -- Normalize so 1.0 and 1 hash identically.
        mix(math.floor(value) % 256)
        mix(math.floor((value - math.floor(value)) * 1000000) % 256)
    elseif t == "string" then
        for i = 1, #value do mix(string.byte(value, i)) end
    elseif t == "table" then
        if seen[value] then mix(255); return string.format("%08x", hash) end
        seen[value] = true
        -- Mix a stable signature per table, then each key/value pair.
        mix(99)
        local keys = {}
        for k in pairs(value) do table.insert(keys, k) end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, k in ipairs(keys) do
            local ks = tostring(k)
            for i = 1, #ks do mix(string.byte(ks, i)) end
            local h = RuntimeTypes._compute_content_hash(value[k], seen)
            -- fold the nested hash's integer value in
            local int_val = tonumber(h, 16) or 0
            mix(int_val % 256); mix(math.floor(int_val / 256) % 256)
        end
    else
        mix(7) -- unsupported type (function/userdata): hash as opaque
    end
    return string.format("%08x", hash)
end

-- Validate a RuntimeProfile structure
-- @param profile table RuntimeProfile to validate
-- @return table diagnostics
function RuntimeTypes.validate_runtime_profile(profile)
    local Diagnostics = require("runtime/diagnostics")
    local errors = {}
    local warnings = {}

    if not profile.profile_id then
        table.insert(errors, {
            code = "C-7001",
            message = "RuntimeProfile missing profile_id",
            stage = Diagnostics.Stage.Lowering,
            severity = Diagnostics.Severity.ERROR,
        })
    end

    if not profile.operations then
        table.insert(errors, {
            code = "C-7002",
            message = "RuntimeProfile missing operations array",
            stage = Diagnostics.Stage.Lowering,
            severity = Diagnostics.Severity.ERROR,
        })
    else
        for i, op in ipairs(profile.operations) do
            if not op.id then
                table.insert(errors, {
                    code = "C-7003",
                    message = "RuntimeOperation missing id",
                    stage = Diagnostics.Stage.Lowering,
                    severity = Diagnostics.Severity.ERROR,
                    entity = "operation[" .. i .. "]",
                })
            end
            if not op.actions then
                table.insert(errors, {
                    code = "C-7004",
                    message = "RuntimeOperation '" .. (op.name or "?") .. "' missing actions array",
                    stage = Diagnostics.Stage.Lowering,
                    severity = Diagnostics.Severity.ERROR,
                    entity = op.name,
                })
            end
        end
    end

    return { errors = errors, warnings = warnings }
end

return RuntimeTypes