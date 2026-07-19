-- sentinel/runtime/dry_run.lua
-- Simulation mode that exercises the scheduler + executor pipeline without real game actions.
-- Uses the real OperationScheduler to select operations but replaces action dispatch
-- with simulation stubs via DryRunExecutor.

local DryRunExecutor = {}
DryRunExecutor.__index = DryRunExecutor

---Create a new DryRunExecutor
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param query_client table|nil Optional QueryClient for data lookups
---@return table DryRunExecutor instance
function DryRunExecutor:new(blackboard, event_bus, query_client)
    local o = setmetatable({}, DryRunExecutor)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._query_client = query_client
    return o
end

---Reset internal state between runs
function DryRunExecutor:reset()
    -- Nothing to reset currently
end

---Simulate an action execution. Returns immediately (no async polling in dry run).
---@param action table RuntimeAction with at minimum: { action_type = string }
---@return table Result: { status = "succeeded"|"failed", result = "pass"|"warn"|"fail", message = string }
function DryRunExecutor:execute(action)
    if not action or not action.action_type then
        return { status = "failed", result = "fail", message = "invalid action: missing action_type" }
    end

    local handler = self._sim_handlers[action.action_type]
    if not handler then
        -- Unknown action type: pass with "not simulated" message
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("action '%s' not simulated — passed by default", tostring(action.action_type)),
        }
    end

    local ok, result = pcall(handler, self, action)
    if not ok then
        return {
            status = "failed",
            result = "fail",
            message = "simulation error: " .. tostring(result),
        }
    end

    return result
end

---Poll is a no-op in dry run (all actions complete synchronously)
---@return table
function DryRunExecutor:poll()
    return { status = "succeeded", result = "pass", message = "dry run does not poll" }
end

---Get current executor state (minimal in dry run)
---@return table
function DryRunExecutor:get_state()
    return { status = "idle", current_action = nil }
end

-- ============================================================================
-- Simulation Handlers
-- ============================================================================

DryRunExecutor._sim_handlers = {}

---goto: Check if QueryServer route exists. Pass if yes, warn otherwise.
DryRunExecutor._sim_handlers["goto"] = function(self, action)
    local target = action.target or action.position
    if not target then
        return {
            status = "succeeded",
            result = "warn",
            message = "goto: no target position specified — cannot verify route",
        }
    end

    local route_ok = self:_check_route_exists(target)
    if route_ok then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("goto: route to (%.1f, %.1f, %.1f) exists", target.x or 0, target.y or 0, target.z or 0),
        }
    else
        return {
            status = "succeeded",
            result = "warn",
            message = string.format("goto: route to (%.1f, %.1f, %.1f) could not be verified", target.x or 0, target.y or 0, target.z or 0),
        }
    end
end

---grind_area: Check creature exists in DB. Pass if yes, fail otherwise.
DryRunExecutor._sim_handlers["grind_area"] = function(self, action)
    local mob_ids = action.mob_ids or {}
    if #mob_ids == 0 then
        return {
            status = "succeeded",
            result = "warn",
            message = "grind_area: no mob_ids specified — area will be empty",
        }
    end

    local all_exist = true
    for _, entry in ipairs(mob_ids) do
        if not self:_check_creature_exists(entry) then
            all_exist = false
        end
    end

    if all_exist then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("grind_area: all %d creature(s) exist in DB", #mob_ids),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = "grind_area: one or more creature entries not found in DB",
        }
    end
end

---kill_target: Check creature exists in DB. Pass if yes, fail otherwise.
DryRunExecutor._sim_handlers["kill_target"] = function(self, action)
    local entry = action.creature_entry or action.entry
    if not entry then
        return {
            status = "succeeded",
            result = "fail",
            message = "kill_target: no creature_entry specified",
        }
    end

    if self:_check_creature_exists(entry) then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("kill_target: creature entry %s exists in DB", tostring(entry)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("kill_target: creature entry %s not found in DB", tostring(entry)),
        }
    end
end

---pickup_quest: NPC + quest exist in DB? Pass. Quest unavailable? Warn.
DryRunExecutor._sim_handlers["pickup_quest"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    local quest_id = action.quest_id

    local npc_ok = self:_check_npc_exists(npc_guid)
    local quest_ok = quest_id and self:_check_quest_exists(quest_id)

    if npc_ok and quest_ok then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("pickup_quest: NPC %s and quest %s exist", tostring(npc_guid), tostring(quest_id)),
        }
    elseif npc_ok and not quest_ok then
        return {
            status = "succeeded",
            result = "warn",
            message = string.format("pickup_quest: NPC %s exists but quest %s unavailable", tostring(npc_guid), tostring(quest_id)),
        }
    elseif not npc_ok and quest_ok then
        return {
            status = "succeeded",
            result = "warn",
            message = string.format("pickup_quest: quest %s exists but NPC %s not found", tostring(quest_id), tostring(npc_guid)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("pickup_quest: NPC %s and quest %s not found", tostring(npc_guid), tostring(quest_id)),
        }
    end
end

---turn_in_quest: NPC + quest exist in DB? Pass. Quest unavailable? Warn.
DryRunExecutor._sim_handlers["turn_in_quest"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    local quest_id = action.quest_id

    local npc_ok = self:_check_npc_exists(npc_guid)
    local quest_ok = quest_id and self:_check_quest_exists(quest_id)

    if npc_ok and quest_ok then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("turn_in_quest: NPC %s and quest %s exist", tostring(npc_guid), tostring(quest_id)),
        }
    elseif npc_ok and not quest_ok then
        return {
            status = "succeeded",
            result = "warn",
            message = string.format("turn_in_quest: NPC %s exists but quest %s unavailable", tostring(npc_guid), tostring(quest_id)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("turn_in_quest: NPC %s and/or quest %s not found", tostring(npc_guid), tostring(quest_id)),
        }
    end
end

---vendor: NPC exists with vendor role? Pass. Else fail.
DryRunExecutor._sim_handlers["vendor"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    if not npc_guid then
        return { status = "succeeded", result = "fail", message = "vendor: no npc_guid specified" }
    end

    if self:_check_npc_exists(npc_guid) then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("vendor: NPC %s exists (assuming vendor role)", tostring(npc_guid)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("vendor: NPC %s not found", tostring(npc_guid)),
        }
    end
end

---repair: NPC exists with repair role? Pass. Else fail.
DryRunExecutor._sim_handlers["repair"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    if not npc_guid then
        return { status = "succeeded", result = "fail", message = "repair: no npc_guid specified" }
    end

    if self:_check_npc_exists(npc_guid) then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("repair: NPC %s exists (assuming repair role)", tostring(npc_guid)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("repair: NPC %s not found", tostring(npc_guid)),
        }
    end
end

---train: NPC exists with trainer role? Pass. Else fail.
DryRunExecutor._sim_handlers["train"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    if not npc_guid then
        return { status = "succeeded", result = "fail", message = "train: no npc_guid specified" }
    end

    if self:_check_npc_exists(npc_guid) then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("train: NPC %s exists (assuming trainer role)", tostring(npc_guid)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("train: NPC %s not found", tostring(npc_guid)),
        }
    end
end

---flight_path: NPC exists with flight master role? Pass. Else fail.
DryRunExecutor._sim_handlers["flight_path"] = function(self, action)
    local npc_guid = action.npc_guid or action.target_guid
    if not npc_guid then
        return { status = "succeeded", result = "fail", message = "flight_path: no npc_guid specified" }
    end

    if self:_check_npc_exists(npc_guid) then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("flight_path: NPC %s exists (assuming flight master role)", tostring(npc_guid)),
        }
    else
        return {
            status = "succeeded",
            result = "fail",
            message = string.format("flight_path: NPC %s not found", tostring(npc_guid)),
        }
    end
end

---wait: Skip immediately (pass)
DryRunExecutor._sim_handlers["wait"] = function(self, action)
    return {
        status = "succeeded",
        result = "pass",
        message = "wait: skipped immediately in dry run",
    }
end

---set_variable: Execute normally via VariableStore (blackboard)
DryRunExecutor._sim_handlers["set_variable"] = function(self, action)
    local name = action.name or action.variable
    local value = action.value
    if not name then
        return { status = "succeeded", result = "fail", message = "set_variable: missing name" }
    end
    self._blackboard:set("module.runtime.var." .. tostring(name), value)
    return {
        status = "succeeded",
        result = "pass",
        message = string.format("set_variable: %s = %s", tostring(name), tostring(value)),
    }
end

---branch: Evaluate condition normally
DryRunExecutor._sim_handlers["branch"] = function(self, action)
    local result = self:_evaluate_branch_condition(action)
    self._blackboard:set("module.runtime.branch_result", result)
    return {
        status = "succeeded",
        result = "pass",
        message = string.format("branch: condition evaluated to %s", tostring(result)),
    }
end

---hearth: Check hearthstone in inventory model
DryRunExecutor._sim_handlers["hearth"] = function(self, action)
    local item_id = action.item_id or 6948 -- Default Hearthstone
    local has_hearth = self:_check_has_item(item_id)

    if has_hearth then
        return {
            status = "succeeded",
            result = "pass",
            message = string.format("hearth: item %d found in inventory", item_id),
        }
    else
        return {
            status = "succeeded",
            result = "warn",
            message = string.format("hearth: item %d not in inventory (may still work in-game)", item_id),
        }
    end
end

---All other action types: Pass with "not simulated" message
local function default_handler(self, action)
    return {
        status = "succeeded",
        result = "pass",
        message = string.format("action '%s' not simulated — passed by default", tostring(action.action_type)),
    }
end

setmetatable(DryRunExecutor._sim_handlers, {
    __index = function(_, action_type)
        return default_handler
    end,
})

-- ============================================================================
-- Lookup Helpers (use query_client or blackboard for data checks)
-- ============================================================================

---Check if a route to the given target exists
---@param target table Position { x, y, z }
---@return boolean
function DryRunExecutor:_check_route_exists(target)
    -- First check blackboard for pre-populated route data
    local known_routes = self._blackboard:get("module.runtime.dry_run_routes")
    if known_routes then
        for _, route in ipairs(known_routes) do
            if route.target_x == (target.x or 0) and route.target_y == (target.y or 0) then
                return route.exists ~= false
            end
        end
    end

    -- Fall back: check query_client cache for route data
    if self._query_client and self._query_client._cache then
        for key, _ in pairs(self._query_client._cache) do
            if key:find("^route:") then
                return true
            end
        end
    end

    -- No data available: return false (unable to verify)
    return false
end

---Check if a creature entry exists in the DB
---@param entry number|string
---@return boolean
function DryRunExecutor:_check_creature_exists(entry)
    -- Check blackboard for pre-populated creature data
    local known_creatures = self._blackboard:get("module.runtime.dry_run_creatures")
    if known_creatures then
        local entry_key = tostring(entry)
        for _, creature in ipairs(known_creatures) do
            if tostring(creature.entry) == entry_key or tostring(creature.id) == entry_key then
                return creature.exists ~= false
            end
        end
    end

    -- Check query_client cache
    if self._query_client and self._query_client._cache then
        for key, _ in pairs(self._query_client._cache) do
            if key:find("^creatures:") and key:match(":(.+)$") == tostring(entry) then
                return true
            end
        end
    end

    return false
end

---Check if an NPC exists
---@param npc_guid string|nil
---@return boolean
function DryRunExecutor:_check_npc_exists(npc_guid)
    if not npc_guid then
        return false
    end

    -- Check blackboard for pre-populated NPC data
    local known_npcs = self._blackboard:get("module.runtime.dry_run_npcs")
    if known_npcs then
        for _, npc in ipairs(known_npcs) do
            if tostring(npc.guid) == tostring(npc_guid) or tostring(npc.entry) == tostring(npc_guid) then
                return npc.exists ~= false
            end
        end
    end

    -- Check query_client cache
    if self._query_client and self._query_client._cache then
        for key, _ in pairs(self._query_client._cache) do
            local id_part = key:match("^npcs:(.+)$")
            if id_part and tostring(id_part) == tostring(npc_guid) then
                return true
            end
        end
    end

    -- If npc_guid looks like a numeric entry, try creature check
    local entry_num = tonumber(npc_guid)
    if entry_num then
        return self:_check_creature_exists(entry_num)
    end

    return false
end

---Check if a quest exists
---@param quest_id number|string|nil
---@return boolean
function DryRunExecutor:_check_quest_exists(quest_id)
    if not quest_id then
        return false
    end

    -- Check blackboard for pre-populated quest data
    local known_quests = self._blackboard:get("module.runtime.dry_run_quests")
    if known_quests then
        for _, quest in ipairs(known_quests) do
            if tostring(quest.id) == tostring(quest_id) or tostring(quest.quest_id) == tostring(quest_id) then
                return quest.exists ~= false
            end
        end
    end

    -- Check query_client cache
    if self._query_client and self._query_client._cache then
        for key, _ in pairs(self._query_client._cache) do
            local id_part = key:match("^quests:(.+)$")
            if id_part and tostring(id_part) == tostring(quest_id) then
                return true
            end
        end
    end

    return false
end

---Check if an item exists in the player's inventory
---@param item_id number
---@return boolean
function DryRunExecutor:_check_has_item(item_id)
    -- Check blackboard for inventory data
    local inventory = self._blackboard:get("player.inventory") or {}
    for _, item in ipairs(inventory) do
        if type(item) == "table" and item.id == item_id then
            return true
        elseif type(item) == "number" and item == item_id then
            return true
        end
    end

    -- Check blackboard for known items
    local known_items = self._blackboard:get("module.runtime.dry_run_items")
    if known_items then
        for _, item in ipairs(known_items) do
            if tostring(item.id) == tostring(item_id) then
                return item.exists ~= false
            end
        end
    end

    -- Default to false for realistic simulation (no hearthstone = warn)
    return false
end

---Evaluate a branch condition (mirrors action_executor logic)
---@param action table
---@return boolean
function DryRunExecutor:_evaluate_branch_condition(action)
    if not action.condition then
        return true
    end
    local cond = action.condition

    if cond.type == "has_item" then
        local items = self._blackboard:get("player.inventory") or {}
        for _, item in ipairs(items) do
            if type(item) == "table" and (item == cond.item_id or item.id == cond.item_id) then
                return true
            elseif type(item) == "number" and item == cond.item_id then
                return true
            end
        end
        return false
    elseif cond.type == "quest_completed" then
        local completed = self._blackboard:get("player.completed_quests") or {}
        for _, qid in ipairs(completed) do
            if qid == cond.quest_id then
                return true
            end
        end
        return false
    elseif cond.type == "quest_active" then
        local active = self._blackboard:get("player.active_quests") or {}
        for _, qid in ipairs(active) do
            if qid == cond.quest_id then
                return true
            end
        end
        return false
    elseif cond.type == "variable_equals" then
        local val = self._blackboard:get("module.runtime.var." .. tostring(cond.name))
        return val == cond.value
    elseif cond.type == "level_above" then
        local level = self._blackboard:get("player.level") or 0
        return level >= (cond.min_level or 0)
    elseif cond.type == "level_below" then
        local level = self._blackboard:get("player.level") or 0
        return level < (cond.max_level or 999)
    end
    return true
end

-- ============================================================================
-- Public API: Proxy methods for lookup configuration
-- ============================================================================

---Register known routes for simulation lookups
---@param routes table List of { target_x, target_y, exists }
function DryRunExecutor:set_known_routes(routes)
    self._blackboard:set("module.runtime.dry_run_routes", routes)
end

---Register known creatures for simulation lookups
---@param creatures table List of { entry, exists }
function DryRunExecutor:set_known_creatures(creatures)
    self._blackboard:set("module.runtime.dry_run_creatures", creatures)
end

---Register known NPCs for simulation lookups
---@param npcs table List of { guid, exists }
function DryRunExecutor:set_known_npcs(npcs)
    self._blackboard:set("module.runtime.dry_run_npcs", npcs)
end

---Register known quests for simulation lookups
---@param quests table List of { id, exists }
function DryRunExecutor:set_known_quests(quests)
    self._blackboard:set("module.runtime.dry_run_quests", quests)
end

---Register known items for simulation lookups
---@param items table List of { id, exists }
function DryRunExecutor:set_known_items(items)
    self._blackboard:set("module.runtime.dry_run_items", items)
end

-- ============================================================================
-- DryRun Orchestrator
-- ============================================================================

local DryRun = {}
DryRun.__index = DryRun

---Create a new DryRun orchestrator
---@param scheduler table OperationScheduler instance
---@param executor table ActionExecutor instance (will not be used directly)
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param query_client table|nil Optional QueryClient instance
---@return table DryRun instance
function DryRun:new(scheduler, executor, blackboard, event_bus, query_client)
    local o = setmetatable({}, DryRun)
    o._scheduler = scheduler
    o._executor = executor         -- reference kept but not used for dispatch
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._dry_executor = DryRunExecutor:new(blackboard, event_bus, query_client)
    o._trace = {}
    o._paused = false
    o._started = false
    o._profile = nil
    o._action_counter = 0
    return o
end

---Shortcut to access DryRunExecutor's lookup configuration
DryRun.__index.set_known_routes = DryRunExecutor.set_known_routes
DryRun.__index.set_known_creatures = DryRunExecutor.set_known_creatures
DryRun.__index.set_known_npcs = DryRunExecutor.set_known_npcs
DryRun.__index.set_known_quests = DryRunExecutor.set_known_quests
DryRun.__index.set_known_items = DryRunExecutor.set_known_items

---Set the profile for the dry run
---@param profile table RuntimeProfile
function DryRun:set_profile(profile)
    self._profile = profile
    self._scheduler:set_profile(profile)
end

---Start the dry run: reset state, set blackboard flag
function DryRun:start()
    self._paused = false
    self._started = true
    self._action_counter = 0
    self._trace = {}
    self._dry_executor:reset()
    self._blackboard:set("module.runtime.dry_run", true)

    -- Ensure scheduler has a profile
    if self._profile then
        self._scheduler:set_profile(self._profile)
    end

    -- Notify via event bus
    if self._event_bus then
        self._event_bus:publish("dry_run_started", {})
    end
end

---Pause the dry run
function DryRun:pause()
    self._paused = true
    if self._event_bus then
        self._event_bus:publish("dry_run_paused", {})
    end
end

---Resume a paused dry run
function DryRun:resume()
    self._paused = false
    if self._event_bus then
        self._event_bus:publish("dry_run_resumed", {})
    end
end

---Advance exactly one action through the pipeline
---@return table|nil Result of the step, or nil if nothing to process
function DryRun:step()
    if not self._started then
        return nil, "dry run not started"
    end
    if self._paused then
        return nil, "dry run paused"
    end

    -- Step 1: Tick the scheduler (evaluates conditions, transitions locked→ready)
    local sched_state = self._scheduler:tick()

    -- Step 2: If no current operation, try to select one
    if not sched_state.current_op_id then
        local selected = self._scheduler:select_next()
        if not selected then
            -- No more operations to process
            self._blackboard:set("module.runtime.dry_run", nil)
            if self._event_bus then
                self._event_bus:publish("dry_run_completed", {
                    actions_simulated = self._action_counter,
                })
            end
            return nil, "no more operations"
        end
    end

    -- Step 3: Get current action
    local current_action = self._scheduler:get_current_action()
    if not current_action then
        -- No more actions in current operation, advance to next operation
        local next_op = self._scheduler:advance_operation()
        if not next_op then
            self._blackboard:set("module.runtime.dry_run", nil)
            if self._event_bus then
                self._event_bus:publish("dry_run_completed", {
                    actions_simulated = self._action_counter,
                })
            end
            return nil, "no more operations"
        end
        -- Try again with the new operation's first action
        current_action = self._scheduler:get_current_action()
        if not current_action then
            return nil, "operation has no actions"
        end
    end

    -- Step 4: Simulate the action
    local result = self._dry_executor:execute(current_action)
    self._action_counter = self._action_counter + 1

    -- Build trace entry
    local entry = {
        action_id = current_action.id or tostring(self._action_counter),
        action_type = current_action.action_type or "unknown",
        result = result.result or "pass",
        message = result.message or "",
    }
    table.insert(self._trace, entry)

    -- Publish trace event
    if self._event_bus then
        self._event_bus:publish("dry_run_action_simulated", entry)
    end

    -- Step 5: Handle simulation result
    if result.status == "succeeded" then
        -- Advance to next action
        local next_action = self._scheduler:advance_action()
        if not next_action then
            -- No more actions in operation, advance operation
            self._scheduler:advance_operation()
        end
    elseif result.status == "failed" then
        -- Fail the current operation
        self._scheduler:fail_operation()
    end

    return entry
end

---Reset the dry run to initial state
function DryRun:reset()
    self._paused = false
    self._started = false
    self._trace = {}
    self._action_counter = 0
    self._dry_executor:reset()
    self._blackboard:set("module.runtime.dry_run", nil)

    -- Reset scheduler state by re-setting the profile
    if self._profile then
        self._scheduler:set_profile(self._profile)
    end

    if self._event_bus then
        self._event_bus:publish("dry_run_reset", {})
    end
end

---Get the current trace of simulated actions
---@return table Ordered list of trace entries
function DryRun:get_trace()
    return self._trace
end

---Get the count of actions simulated so far
---@return number
function DryRun:get_action_count()
    return self._action_counter
end

---Check if dry run is active
---@return boolean
function DryRun:is_active()
    return self._started and not self._paused
end

---Check if dry run is paused
---@return boolean
function DryRun:is_paused()
    return self._paused
end

---Check if dry run has started
---@return boolean
function DryRun:is_started()
    return self._started
end

return DryRun
