-- sentinel/runtime/runtime_engine.lua
-- Runtime Engine: Main tick loop that ties scheduler + executor + profile_manager together
-- Called once per frame from the app loop

local OperationScheduler = require("runtime/operation_scheduler")
local ActionExecutor = require("runtime/action_executor")

local RuntimeEngine = {}
RuntimeEngine.__index = RuntimeEngine

local ENGINE_STATUSES = {
    IDLE = "idle",
    RUNNING = "running",
    PAUSED = "paused",
    COMPLETED = "completed",
    STOPPED = "stopped",
    ERROR = "error",
}

---Create a new RuntimeEngine
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param profile_manager table The ProfileManager instance
---@param nav_adapter table|nil The NavAdapter instance
---@return table RuntimeEngine instance
function RuntimeEngine:new(blackboard, event_bus, profile_manager, nav_adapter)
    local o = setmetatable({}, RuntimeEngine)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._profile_manager = profile_manager
    o._nav_adapter = nav_adapter
    o._scheduler = OperationScheduler:new(blackboard, event_bus)
    o._executor = ActionExecutor:new(blackboard, event_bus, nav_adapter)
    o._status = ENGINE_STATUSES.IDLE
    o._profile_id = nil
    o._total_elapsed = 0
    o._tick_count = 0
    return o
end

---Start the engine: initialize, load active profile, set status to running
function RuntimeEngine:start()
    self._status = ENGINE_STATUSES.RUNNING
    self._total_elapsed = 0
    self._tick_count = 0

    -- Load active profile from profile_manager
    local profile = self._profile_manager:get_active_profile()
    local profile_id = self._profile_manager:get_active_profile_id()
    if profile then
        self._profile_id = profile_id
        self._scheduler:set_profile(profile)
    end

    -- Store engine status in blackboard
    self._blackboard:set("module.runtime.engine_status", self._status)
    self._blackboard:set("module.runtime.profile_id", self._profile_id)

    self:_publish("engine_started", {
        profile_id = self._profile_id,
        profile_name = profile and profile.name or nil,
    })
end

---Stop the engine: stop execution, set status to stopped
function RuntimeEngine:stop()
    self._status = ENGINE_STATUSES.STOPPED
    self._blackboard:set("module.runtime.engine_status", self._status)
    self:_publish("engine_stopped", { profile_id = self._profile_id })
end

---Pause the engine: pause execution, keep current state
function RuntimeEngine:pause()
    if self._status == ENGINE_STATUSES.RUNNING then
        self._status = ENGINE_STATUSES.PAUSED
        self._blackboard:set("module.runtime.engine_status", self._status)
        self:_publish("engine_paused", { profile_id = self._profile_id })
    end
end

---Resume the engine: resume execution from paused state
function RuntimeEngine:resume()
    if self._status == ENGINE_STATUSES.PAUSED then
        self._status = ENGINE_STATUSES.RUNNING
        self._blackboard:set("module.runtime.engine_status", self._status)
        self:_publish("engine_resumed", { profile_id = self._profile_id })
    end
end

---Set a new profile to execute
---@param profile table RuntimeProfile
function RuntimeEngine:set_profile(profile)
    if not profile then
        return
    end
    self._scheduler:set_profile(profile)
    self._profile_manager:set_active_profile(profile)
    if profile.id then
        self._profile_id = profile.id
        self._profile_manager:activate(self._blackboard, profile.id)
    end
    self._blackboard:set("module.runtime.profile_id", self._profile_id)
end

---Main per-frame tick
---@param delta_ms number Milliseconds since last tick
---@return table Result info: { status, current_operation, current_action, profile_id }
function RuntimeEngine:tick(delta_ms)
    if self._status ~= ENGINE_STATUSES.RUNNING then
        return self:get_state()
    end

    self._total_elapsed = self._total_elapsed + (delta_ms or 0)
    self._tick_count = self._tick_count + 1

    -- Step 1: Ensure profile is loaded
    if not self._scheduler._profile then
        local profile = self._profile_manager:get_active_profile()
        if profile then
            self._scheduler:set_profile(profile)
        else
            -- No profile loaded; nothing to do
            return self:get_state()
        end
    end

    -- Step 2: Tick the scheduler (evaluates conditions, selects next operation)
    local sched_state = self._scheduler:tick()

    -- Step 3: If no current operation, check if all done
    if not sched_state.current_op_id then
        local ready_ops = self._scheduler:get_ready_operations()
        if #ready_ops == 0 then
            -- No more ready operations - mark engine as completed
            self._status = ENGINE_STATUSES.COMPLETED
            self._blackboard:set("module.runtime.engine_status", self._status)
            self:_publish("engine_completed", {
                profile_id = self._profile_id,
                total_elapsed = self._total_elapsed,
                tick_count = self._tick_count,
            })
        end
        return self:get_state()
    end

    -- Step 4: Get current action
    local current_op = self._scheduler:get_current_operation()
    local current_action = self._scheduler:get_current_action()

    if not current_action then
        -- No more actions in current operation, advance
        self._scheduler:advance_operation()
        return self:get_state()
    end

    -- Step 5: Execute or poll the current action
    local exec_state = self._executor:get_state()
    local result

    if exec_state.status == "running" then
        -- Poll running action
        result = self._executor:poll(current_action)
    else
        -- Execute new action
        result = self._executor:execute(current_action)
    end

    -- Step 6: Handle result
    if result.status == "succeeded" then
        -- Action succeeded, advance
        local next_action = self._scheduler:advance_action()
        if not next_action then
            -- No more actions in this operation
            self._scheduler:advance_operation()
        end

    elseif result.status == "failed" then
        -- Action failed, apply retry or mark operation failed
        if result.error == "retrying" then
            -- Retry is scheduled, nothing to do this tick
        else
            self:_publish("action_failed", {
                op_id = sched_state.current_op_id,
                action_type = current_action.action_type,
                error = result.error,
            })
            self._scheduler:fail_operation()
        end

    elseif result.status == "running" then
        -- Action still in progress, will be polled next tick
    end

    return self:get_state()
end

---Get the current engine state
---@return table { status = string, current_operation = table|nil, current_action = table|nil, profile_id = string|nil, total_elapsed = number, tick_count = number }
function RuntimeEngine:get_state()
    local current_op = self._scheduler:get_current_operation()
    local current_action = self._scheduler:get_current_action()
    local exec_state = self._executor:get_state()

    return {
        status = self._status,
        current_operation = current_op,
        current_action = current_action,
        profile_id = self._profile_id,
        total_elapsed = self._total_elapsed,
        tick_count = self._tick_count,
        action_status = exec_state.status,
    }
end

---Publish an event
---@param event_name string
---@param payload table
function RuntimeEngine:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

return RuntimeEngine
