-- sentinel/runtime/runtime_context.lua
-- Runtime context for executing profiles - ADR 002 §8-9
-- RuntimeContext is read-only for most systems; only VariableStore mutates shared runtime state
-- Initializes and manages module lifecycle via ModuleRegistry - SENT-8.1

local VariableStore = require("runtime/variable_store")
local ModuleRegistry = require("runtime/module_registry")
local OperationManager = require("runtime/operation_manager")

local RuntimeContext = {}
RuntimeContext.__index = RuntimeContext

-- Profile states per ADR 002 §22
local PROFILE_STATES = {
    DRAFT = "draft",
    VALIDATED = "validated",
    COMPILED = "compiled",
    EXECUTING = "executing",
    PAUSED = "paused",
    COMPLETED = "completed",
}

-- Runtime states per ADR 002 §7
local RUNTIME_STATES = {
    IDLE = "idle",
    READY = "ready",
    EXECUTING = "executing",
    WAITING = "waiting",
    FINISHED = "finished",
    RECOVERING = "recovering",
    FAILED = "failed",
}

---Create a new RuntimeContext
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@return table RuntimeContext instance
function RuntimeContext:new(blackboard, event_bus)
    local o = setmetatable({}, RuntimeContext)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._variable_store = VariableStore:new(blackboard)
    o._module_registry = ModuleRegistry:new()
    o._nav_adapter = nil
    o._operation_manager = nil
    return o
end

---Get the ModuleRegistry instance
---@return table ModuleRegistry instance
function RuntimeContext:get_module_registry()
    return self._module_registry
end

---Initialize modules before RuntimeContext creation - SENT-8.1
---Modules are registered and initialized before any profile execution
---@param app table The application context to pass to module:init()
---@return boolean success
function RuntimeContext:_initialize_modules(app)
    local registered = self._module_registry:register_all(self._blackboard, self._event_bus)
    return self._module_registry:initialize_all(app)
end

---Public initialize method for module lifecycle - SENT-8.1
---Should be called after RuntimeContext is created to initialize modules
---@param app table The application context
---@return boolean success
function RuntimeContext:initialize(app)
    return self:_initialize_modules(app)
end

---Shutdown modules on RuntimeContext destruction - SENT-8.1
function RuntimeContext:_shutdown_modules()
    self._module_registry:shutdown_all()
end

---Destroy the RuntimeContext: shutdown modules and clear state - SENT-8.1
function RuntimeContext:destroy()
    self:_shutdown_modules()
    self:clear()
end

---Get the VariableStore (sole mutator of shared runtime state)
---@return table VariableStore instance
function RuntimeContext:get_variable_store()
    return self._variable_store
end

---Get or create the OperationManager instance - SENT-8.4
---@return table OperationManager instance
function RuntimeContext:get_operation_manager()
    if not self._operation_manager then
        self._operation_manager = OperationManager:new(
            self._blackboard,
            self._event_bus,
            self._nav_adapter
        )
    end
    return self._operation_manager
end

---Set the NavAdapter for operation execution
---@param nav_adapter table NavAdapter instance
function RuntimeContext:set_nav_adapter(nav_adapter)
    self._nav_adapter = nav_adapter
    if self._operation_manager then
        self._operation_manager._nav_adapter = nav_adapter
        self._operation_manager._executor._nav_adapter = nav_adapter
    end
end

---Get the operation status from blackboard - SENT-8.4
---@param op_id string Operation ID
---@return string Status
function RuntimeContext:get_operation_status(op_id)
    if not op_id then
        return "idle"
    end
    return self._blackboard:get("module.operation." .. tostring(op_id) .. ".status", "locked")
end

---Set operation status in blackboard - SENT-8.4
---@param op_id string Operation ID
---@param status string Status to set
---@param error_msg string|nil Optional error message
function RuntimeContext:set_operation_status(op_id, status, error_msg)
    self._blackboard:set("module.operation." .. tostring(op_id) .. ".status", status)
    if error_msg and self._event_bus then
        self._event_bus:publish("operation_error", { op_id = op_id, error = error_msg })
    end
end

---Get the current operation - SENT-8.4
---@return table|nil Current operation
function RuntimeContext:get_active_operation()
    return self._blackboard:get("module.runtime.current_operation")
end

---Set the current operation - SENT-8.4
---@param op table|nil Operation
function RuntimeContext:set_active_operation(op)
    self._blackboard:set("module.runtime.current_operation", op)
    if op then
        self._blackboard:set("module.operation." .. tostring(op.id) .. ".current_action", nil)
    end
end

---Set the active profile
---@param profile table The RuntimeProfile
function RuntimeContext:set_profile(profile)
    if not profile then
        return
    end
    self._blackboard:set("module.runtime.active_profile", profile)
    self._blackboard:set("module.runtime.profile_id", profile.profile_id or profile.id)
    self._blackboard:set("module.runtime.profile_state", PROFILE_STATES.EXECUTING)
    self:reset_runtime_state()
end

---Get the active profile
---@return table|nil RuntimeProfile
function RuntimeContext:get_profile()
    return self._blackboard:get("module.runtime.active_profile")
end

---Get profile ID
---@return string|nil
function RuntimeContext:get_profile_id()
    return self._blackboard:get("module.runtime.profile_id")
end

---Get current runtime state
---@return string One of IDLE, READY, EXECUTING, WAITING, FINISHED, RECOVERING, FAILED
function RuntimeContext:get_runtime_state()
    return self._blackboard:get("module.runtime.runtime_state", RUNTIME_STATES.IDLE)
end

---Set runtime state (triggered by engine state transitions)
---@param state string Target state
function RuntimeContext:set_runtime_state(state)
    local prev = self:get_runtime_state()
    if prev == state then
        return true
    end

    self._blackboard:set("module.runtime.runtime_state", state)

    if self._event_bus then
        self._event_bus:publish("runtime_state_changed", {
            from = prev,
            to = state,
        })
    end
    return true
end

---Reset runtime state to IDLE
function RuntimeContext:reset_runtime_state()
    self:set_runtime_state(RUNTIME_STATES.IDLE)
end

---Transition to READY state
function RuntimeContext:transition_to_ready()
    self:set_runtime_state(RUNTIME_STATES.READY)
end

---Transition to EXECUTING state
function RuntimeContext:transition_to_executing()
    self:set_runtime_state(RUNTIME_STATES.EXECUTING)
end

---Transition to WAITING state
function RuntimeContext:transition_to_waiting()
    self:set_runtime_state(RUNTIME_STATES.WAITING)
end

---Transition to RECOVERING state
function RuntimeContext:transition_to_recovering()
    self:set_runtime_state(RUNTIME_STATES.RECOVERING)
end

---Transition to FAILED state
function RuntimeContext:transition_to_failed()
    self:set_runtime_state(RUNTIME_STATES.FAILED)
end

---Transition to FINISHED state
function RuntimeContext:transition_to_finished()
    self:set_runtime_state(RUNTIME_STATES.FINISHED)
end

---Get player state from blackboard
---@return table Player state snapshot
function RuntimeContext:get_player_state()
    return {
        level = self._blackboard:get("player.level"),
        class = self._blackboard:get("player.class"),
        race = self._blackboard:get("player.race"),
        zone = self._blackboard:get("player.zone"),
        position = self._blackboard:get("player.position"),
        is_dead = self._blackboard:get("player.is_dead", false),
    }
end

---Get completed quests
---@return table List of completed quest IDs
function RuntimeContext:get_completed_quests()
    return self._blackboard:get("player.completed_quests") or {}
end

---Get active quests
---@return table List of active quest IDs
function RuntimeContext:get_active_quests()
    return self._blackboard:get("player.active_quests") or {}
end

---Get known NPC entries
---@return table NPC info keyed by GUID or entry ID
function RuntimeContext:get_known_npcs()
    return self._blackboard:get("module.runtime.known_npcs") or {}
end

---Add or update a known NPC
---@param npc table NPC info with entry_id, name, position, etc.
function RuntimeContext:set_known_npc(npc)
    if not npc or not npc.entry_id then
        return
    end
    local known = self:get_known_npcs()
    known[npc.entry_id] = npc
    self._blackboard:set("module.runtime.known_npcs", known)
end

---Get known objects
---@return table Object info keyed by entry ID
function RuntimeContext:get_known_objects()
    return self._blackboard:get("module.runtime.known_objects") or {}
end

---Add or update a known object
---@param obj table Object info
function RuntimeContext:set_known_object(obj)
    if not obj or not obj.entry_id then
        return
    end
    local known = self:get_known_objects()
    known[obj.entry_id] = obj
    self._blackboard:set("module.runtime.known_objects", known)
end

---Get inventory snapshot
---@return table List of items with entry_id, count, etc.
function RuntimeContext:get_inventory()
    return self._blackboard:get("module.runtime.inventory_snapshot") or {}
end

---Set inventory snapshot
---@param items table List of items
function RuntimeContext:set_inventory(items)
    self._blackboard:set("module.runtime.inventory_snapshot", items or {})
end

---Get current operation
---@return table|nil Current operation
function RuntimeContext:get_current_operation()
    return self._blackboard:get("module.runtime.current_operation")
end

---Set current operation
---@param op table|nil Operation
function RuntimeContext:set_current_operation(op)
    self._blackboard:set("module.runtime.current_operation", op)
end

---Get current action
---@return table|nil Current action
function RuntimeContext:get_current_action()
    return self._blackboard:get("module.runtime.current_action")
end

---Set current action
---@param action table|nil Action
function RuntimeContext:set_current_action(action)
    self._blackboard:set("module.runtime.current_action", action)
end

---Clear all runtime state (used for profile reload)
function RuntimeContext:clear()
    self._blackboard:clear("module.runtime.active_profile")
    self._blackboard:clear("module.runtime.profile_id")
    self._blackboard:clear("module.runtime.profile_state")
    self._blackboard:clear("module.runtime.runtime_state")
    self._blackboard:clear("module.runtime.current_operation")
    self._blackboard:clear("module.runtime.current_action")
    self:clear_inventory()
    self:clear_action_cache()
    self._blackboard:clear("module.runtime.known_npcs")
    self._blackboard:clear("module.runtime.known_objects")

    -- Clear operation state - SENT-8.4
    local op_snapshot = self._blackboard:snapshot("module.operation.")
    for key, _ in pairs(op_snapshot) do
        self._blackboard:clear(key)
    end
    self._operation_manager = nil
end

---Clear inventory
function RuntimeContext:clear_inventory()
    self._blackboard:clear("module.runtime.inventory_snapshot")
end

-- ============================================================================
-- Action Result Cache (per ADR 008 §14)
-- ============================================================================

---Get cached action result
---@param action_id string Action ID
---@return table|nil Cached result
function RuntimeContext:get_action_result(action_id)
    local cache = self._blackboard:get("module.runtime.action_cache")
    if not cache then
        return nil
    end
    return cache[action_id]
end

---Cache action result
---@param action_id string Action ID
---@param result table Result to cache
function RuntimeContext:cache_action_result(action_id, result)
    if not action_id then
        return
    end
    local cache = self._blackboard:get("module.runtime.action_cache") or {}
    cache[action_id] = result
    self._blackboard:set("module.runtime.action_cache", cache)
end

---Clear action cache (used for profile reload)
function RuntimeContext:clear_action_cache()
    self._blackboard:clear("module.runtime.action_cache")
end

return RuntimeContext