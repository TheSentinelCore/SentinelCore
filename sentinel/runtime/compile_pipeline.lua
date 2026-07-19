-- sentinel/runtime/compile_pipeline.lua
-- Orchestrates the full compile flow: migrate → validate → compile → swap
-- Listens for "toolbar:compile" event to trigger the pipeline

local CompilePipeline = {}
CompilePipeline.__index = CompilePipeline

local PIPELINE_STATES = {
    IDLE = "idle",
    RUNNING = "running",
    SUCCESS = "success",
    ERROR = "error",
}

-- ============================================================================
-- Construction
-- ============================================================================

---Create a new CompilePipeline
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param profile_manager table The ProfileManager instance
---@param compiler_bridge table The CompilerBridge instance
---@param migration_registry table|nil The MigrationRegistry instance (optional)
---@return table CompilePipeline instance
function CompilePipeline:new(blackboard, event_bus, profile_manager, compiler_bridge, migration_registry)
    local o = setmetatable({}, CompilePipeline)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._compiler_bridge = compiler_bridge
    o._migration_registry = migration_registry
    o._state = PIPELINE_STATES.IDLE
    o._last_diagnostics = nil
    o._subscription_tokens = {}

    -- Subscribe to toolbar:compile event
    o:_subscribe_to_events()

    return o
end

-- ============================================================================
-- Public API
-- ============================================================================

---Run the full pipeline: migrate → validate → compile → swap
---@return table { success = boolean, runtime_profile = table|nil, diagnostics = table|nil }
function CompilePipeline:run()
    -- Reject if already running
    if self._state == PIPELINE_STATES.RUNNING then
        return {
            success = false,
            runtime_profile = nil,
            diagnostics = { errors = { { code = "P-1001", message = "pipeline is already running" } }, warnings = {} },
        }
    end

    self._state = PIPELINE_STATES.RUNNING
    self._last_diagnostics = nil
    local start_time = os.clock()

    self:_publish("pipeline:started", {})

    -- Step 1: Get active profile
    local profile = self._profile_manager:get_active_profile()
    if not profile then
        local diagnostics = {
            errors = { { code = "P-1002", message = "no active profile to compile" } },
            warnings = {},
        }
        self._last_diagnostics = diagnostics
        self._state = PIPELINE_STATES.ERROR
        self:_publish("pipeline:failed", { diagnostics = diagnostics })
        return { success = false, runtime_profile = nil, diagnostics = diagnostics }
    end

    -- Step 2: Run migration
    local migrate_start = os.clock()
    local migrate_result
    if self._migration_registry then
        migrate_result = self._migration_registry:migrate(profile)
    else
        migrate_result = { profile = profile, errors = {}, warnings = {} }
    end
    local migrate_duration = (os.clock() - migrate_start) * 1000
    profile = migrate_result.profile

    self:_publish("pipeline:migration_complete", { duration = migrate_duration })

    -- Step 3: Run validation (via compiler bridge)
    local validate_start = os.clock()
    local validation_errors = {}
    local validation_warnings = {}
    if self._compiler_bridge then
        validation_errors, validation_warnings = self._compiler_bridge:_inline_validate(profile)
    end
    local validate_duration = (os.clock() - validate_start) * 1000

    self:_publish("pipeline:validation_complete", {
        errors = validation_errors,
        warnings = validation_warnings,
    })

    -- Combine migration and validation diagnostics
    local all_errors = {}
    for _, e in ipairs(migrate_result.errors or {}) do
        table.insert(all_errors, e)
    end
    for _, e in ipairs(validation_errors) do
        table.insert(all_errors, e)
    end
    local all_warnings = {}
    for _, w in ipairs(migrate_result.warnings or {}) do
        table.insert(all_warnings, w)
    end
    for _, w in ipairs(validation_warnings) do
        table.insert(all_warnings, w)
    end

    -- If validation has errors, stop
    if #all_errors > 0 then
        local diagnostics = {
            errors = all_errors,
            warnings = all_warnings,
        }
        self._last_diagnostics = diagnostics
        self._state = PIPELINE_STATES.ERROR
        self:_publish("pipeline:failed", { diagnostics = diagnostics })
        return { success = false, runtime_profile = nil, diagnostics = diagnostics }
    end

    -- Step 4: Run compiler_bridge:compile()
    local compile_result = nil
    local compile_duration = 0

    if self._compiler_bridge then
        local compile_start = os.clock()
        -- Use compile synchronously for pipeline
        local compile_done = false
        self._compiler_bridge:compile(function(err, runtime_profile)
            compile_done = true
            compile_result = { err = err, runtime_profile = runtime_profile }
        end)
        -- Wait for compile to complete (it's synchronous internally)
        if not compile_done then
            compile_result = { err = "compile did not complete", runtime_profile = nil }
        end
        compile_duration = (os.clock() - compile_start) * 1000
    end

    self:_publish("pipeline:compile_complete", { duration = compile_duration })

    -- Check compile result
    if compile_result and compile_result.err then
        local diagnostics = {
            errors = compile_result.err.errors or compile_result.err,
            warnings = all_warnings,
        }
        if type(diagnostics.errors) ~= "table" then
            diagnostics.errors = { { code = "P-1003", message = tostring(compile_result.err) } }
        end
        self._last_diagnostics = diagnostics
        self._state = PIPELINE_STATES.ERROR
        self:_publish("pipeline:failed", { diagnostics = diagnostics })
        return { success = false, runtime_profile = nil, diagnostics = diagnostics }
    end

    local runtime_profile = compile_result and compile_result.runtime_profile

    -- Step 5: Swap RuntimeProfile into profile_manager
    if runtime_profile then
        self._profile_manager:set_active_profile(runtime_profile)
        if runtime_profile.profile_id then
            self._profile_manager:activate(self._blackboard, runtime_profile.profile_id)
        end
    end

    -- Step 6: Log to console and notify engine
    -- (In-game, this would write to the Sylvannas console)
    -- For the offline test, we publish the event

    self._state = PIPELINE_STATES.SUCCESS
    self:_publish("pipeline:completed", {
        runtime_profile = runtime_profile,
        diagnostics = {
            errors = all_errors,
            warnings = all_warnings,
        },
    })

    return {
        success = true,
        runtime_profile = runtime_profile,
        diagnostics = {
            errors = all_errors,
            warnings = all_warnings,
        },
    }
end

---Run migration + validation only, no compile
---@return table { diagnostics = { errors, warnings } }
function CompilePipeline:validate_only()
    local profile = self._profile_manager:get_active_profile()
    if not profile then
        return {
            diagnostics = {
                errors = { { code = "P-1002", message = "no active profile" } },
                warnings = {},
            },
        }
    end

    -- Run migration
    local migrate_result
    if self._migration_registry then
        migrate_result = self._migration_registry:migrate(profile)
    else
        migrate_result = { profile = profile, errors = {}, warnings = {} }
    end

    -- Run validation
    local validation_errors = {}
    local validation_warnings = {}
    if self._compiler_bridge then
        validation_errors, validation_warnings = self._compiler_bridge:_inline_validate(profile)
    end

    local all_errors = {}
    for _, e in ipairs(migrate_result.errors or {}) do
        table.insert(all_errors, e)
    end
    for _, e in ipairs(validation_errors) do
        table.insert(all_errors, e)
    end
    local all_warnings = {}
    for _, w in ipairs(migrate_result.warnings or {}) do
        table.insert(all_warnings, w)
    end
    for _, w in ipairs(validation_warnings) do
        table.insert(all_warnings, w)
    end

    return {
        diagnostics = {
            errors = all_errors,
            warnings = all_warnings,
        },
    }
end

---Get current pipeline state
---@return string One of "idle", "running", "success", "error"
function CompilePipeline:get_pipeline_state()
    return self._state
end

-- ============================================================================
-- Internal: Event Subscription
-- ============================================================================

---Subscribe to toolbar:compile event
function CompilePipeline:_subscribe_to_events()
    if not self._event_bus then
        return
    end

    local token = self._event_bus:subscribe("toolbar:compile", function(payload)
        -- When the toolbar "Compile" button is pressed, run the pipeline
        local result = self:run()

        -- Log to console (print works in offline test harness)
        if result.success then
            print("[CompilePipeline] Compile completed successfully")
            print("[CompilePipeline] Profile: " .. tostring(
                result.runtime_profile and result.runtime_profile.profile_id or "unknown"))
        else
            local err_msg = "unknown error"
            if result.diagnostics and result.diagnostics.errors then
                local msgs = {}
                for _, e in ipairs(result.diagnostics.errors) do
                    table.insert(msgs, e.message or tostring(e))
                end
                err_msg = table.concat(msgs, "; ")
            end
            print("[CompilePipeline] Compile failed: " .. err_msg)
        end
    end)

    table.insert(self._subscription_tokens, token)
end

-- ============================================================================
-- Cleanup
-- ============================================================================

---Clean up event subscriptions
function CompilePipeline:destroy()
    if self._event_bus and self._subscription_tokens then
        for _, token in ipairs(self._subscription_tokens) do
            self._event_bus:unsubscribe(token)
        end
    end
    self._subscription_tokens = {}
end

-- ============================================================================
-- Internal: Event Publishing
-- ============================================================================

---Publish an event
---@param event_name string
---@param payload table
function CompilePipeline:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

return CompilePipeline
