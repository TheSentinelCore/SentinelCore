-- sentinel/runtime/compiler_bridge.lua
-- Bridge between Lua runtime and the Rust compiler
-- Handles serialization, validation, and RuntimeProfile creation

local MigrationRegistry = require("runtime/migration_registry")
local JSON = require("lib/JSON")

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
function CompilerBridge:new(blackboard, event_bus, profile_manager)
    local o = setmetatable({}, CompilerBridge)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._last_result = nil
    o._is_compiling = false
    o._migration_registry = MigrationRegistry:new()
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
                errors = { { code = "C-1001", message = "no active profile" } },
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

    -- Step 3: Run inline validation
    local validate_start = os.clock()
    local validation_errors, validation_warnings = self:_inline_validate(profile)
    local validate_duration = (os.clock() - validate_start) * 1000

    self:_publish("compile:stage_complete", {
        stage = "validation",
        duration = validate_duration,
    })

    -- If validation has errors, fail
    if #validation_errors > 0 then
        local duration_ms = (os.clock() - start_time) * 1000
        local result = {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = validation_errors,
                warnings = validation_warnings,
            },
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

    -- Step 4: Build RuntimeProfile wrapper
    local compile_start = os.clock()

    local runtime_profile = self:_build_runtime_profile(profile)

    local compile_duration = (os.clock() - compile_start) * 1000
    local total_duration = (os.clock() - start_time) * 1000

    self:_publish("compile:stage_complete", {
        stage = "compile",
        duration = compile_duration,
    })

    -- Success
    local result = {
        success = true,
        runtime_profile = runtime_profile,
        diagnostics = {
            errors = validation_errors,
            warnings = validation_warnings,
        },
        duration_ms = total_duration,
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

-- ============================================================================
-- Internal: Inline Validation
-- ============================================================================

---Run structural validation on a profile
---@param profile table
---@return table errors, table warnings
function CompilerBridge:_inline_validate(profile)
    local errors = {}
    local warnings = {}

    if not profile then
        table.insert(errors, { code = "V-1001", message = "profile is nil" })
        return errors, warnings
    end

    -- Check profile has a name
    if not profile.name or profile.name == "" then
        table.insert(errors, { code = "V-1002", message = "profile missing name" })
    end

    -- Check operations array
    if not profile.operations then
        table.insert(errors, { code = "V-1003", message = "profile missing operations" })
        return errors, warnings
    end

    if type(profile.operations) ~= "table" then
        table.insert(errors, { code = "V-1004", message = "operations must be a table" })
        return errors, warnings
    end

    -- Check for duplicate operation IDs
    local seen_op_ids = {}
    for i, op in ipairs(profile.operations) do
        if type(op) ~= "table" then
            table.insert(errors, {
                code = "V-1005",
                message = "operation " .. i .. " is not a table",
            })
        else
            if op.id then
                if seen_op_ids[op.id] then
                    table.insert(errors, {
                        code = "V-1006",
                        message = "duplicate operation id: " .. tostring(op.id),
                    })
                else
                    seen_op_ids[op.id] = true
                end
            end

            -- Check for dangling references
            if op.actions and type(op.actions) == "table" then
                local seen_action_ids = {}
                for j, action in ipairs(op.actions) do
                    if type(action) == "table" and action.id then
                        if seen_action_ids[action.id] then
                            table.insert(errors, {
                                code = "V-1007",
                                message = "duplicate action id in operation '"
                                    .. tostring(op.name or "?") .. "': " .. tostring(action.id),
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
                        message = "entry_conditions must be a table for operation '"
                            .. tostring(op.name or "?") .. "'",
                    })
                elseif #op.entry_conditions == 0 then
                    table.insert(warnings, {
                        code = "V-2001",
                        message = "operation '" .. tostring(op.name or "?")
                            .. "' has empty entry_conditions",
                    })
                end
            end

            -- Check goals structure
            if op.goals then
                if type(op.goals) ~= "table" then
                    table.insert(errors, {
                        code = "V-1009",
                        message = "goals must be a table for operation '"
                            .. tostring(op.name or "?") .. "'",
                    })
                end
            end
        end
    end

    return errors, warnings
end

-- ============================================================================
-- Internal: Build RuntimeProfile
-- ============================================================================

---Build a RuntimeProfile from a migrated/validated profile
---@param profile table The validated authoring profile
---@return table RuntimeProfile
function CompilerBridge:_build_runtime_profile(profile)
    -- Transform operations into runtime format
    local runtime_operations = {}
    for _, op in ipairs(profile.operations or {}) do
        local runtime_op = {
            id = op.id,
            name = op.name,
            action_type = op.action_type,
            entry_conditions = op.entry_conditions,
            goals = op.goals,
            priority = op.priority,
            actions = self:_transform_actions(op.actions or {}),
        }
        table.insert(runtime_operations, runtime_op)
    end

    local runtime_profile = {
        schema_version = "1.0",
        compiler_version = "0.1.0",
        profile_id = profile.id or profile.name,
        metadata = {
            compiled_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            source_hash = self:_simple_hash(profile),
            duration_ms = self._last_result and self._last_result.duration_ms or 0,
        },
        operations = runtime_operations,
        diagnostics = {
            errors = {},
            warnings = {},
        },
    }

    return runtime_profile
end

---Transform action tables into runtime-ready format
---@param actions table
---@return table
function CompilerBridge:_transform_actions(actions)
    local runtime_actions = {}
    for _, action in ipairs(actions or {}) do
        local runtime_action = {
            id = action.id,
            action_type = action.action_type,
            params = action.params or {},
            conditions = action.conditions,
        }
        table.insert(runtime_actions, runtime_action)
    end
    return runtime_actions
end

-- ============================================================================
-- Internal: Simple hash function
-- ============================================================================

---Simple string hash for profile content
---@param obj table
---@return string hex hash
function CompilerBridge:_simple_hash(obj)
    local str = JSON.encode(obj) or tostring(obj)
    -- Simple djb2-like hash
    local hash = 5381
    for i = 1, #str do
        local byte = string.byte(str, i)
        hash = ((hash * 33) + byte) % 2^32
    end
    return string.format("%08x", hash)
end

-- ============================================================================
-- Internal: Event publishing
-- ============================================================================

---Publish an event to the event bus
---@param event_name string
---@param payload table
function CompilerBridge:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

return CompilerBridge
