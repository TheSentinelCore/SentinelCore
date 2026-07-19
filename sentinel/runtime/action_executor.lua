-- sentinel/runtime/action_executor.lua
-- Action Executor: dumb dispatch of individual actions by action_type
-- Supports retry_policy, timeout_ms, and async polling for long-running actions

local ActionExecutor = {}
ActionExecutor.__index = ActionExecutor

---Create a new ActionExecutor
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param nav_adapter table|nil The NavAdapter instance (for move/goto actions)
---@return table ActionExecutor instance
function ActionExecutor:new(blackboard, event_bus, nav_adapter)
    local o = setmetatable({}, ActionExecutor)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._nav_adapter = nav_adapter
    o._current_action = nil
    o._current_status = nil
    o._start_time = nil
    o._retry_count = 0
    o._async_state_key = "module.runtime.action_state"
    return o
end

---Execute an action immediately (or start it for async actions)
---@param action table RuntimeAction table with at minimum: { action_type = string }
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil }
function ActionExecutor:execute(action)
    if not action or not action.action_type then
        return { status = "failed", error = "invalid action: missing action_type" }
    end

    self._current_action = action
    self._current_status = "running"
    self._start_time = self._start_time or self:_get_time()
    self._retry_count = self._retry_count or 0

    -- Check timeout
    if action.timeout_ms and self._start_time then
        local elapsed = self:_get_time() - self._start_time
        if elapsed > action.timeout_ms then
            self._current_status = "failed"
            self:_publish("action_timed_out", { action_type = action.action_type, error = "timeout exceeded" })
            return { status = "failed", error = "timeout exceeded" }
        end
    end

    local handler = self._handlers[action.action_type]
    if not handler then
        self._current_status = "failed"
        return { status = "failed", error = "unknown action_type: " .. tostring(action.action_type) }
    end

    local ok, result = pcall(handler, self, action)
    if not ok then
        self._current_status = "failed"
        self:_publish("action_handler_error", { action_type = action.action_type, error = tostring(result) })
        return { status = "failed", error = tostring(result) }
    end

    self._current_status = result.status

    -- Track async state in blackboard
    if result.status == "running" then
        self._blackboard:set(self._async_state_key, {
            action_type = action.action_type,
            status = "running",
            start_time = self._start_time,
        })
    elseif result.status == "succeeded" then
        self._blackboard:set(self._async_state_key, nil)
        self._start_time = nil
        self._retry_count = 0
        self:_publish("action_succeeded", { action_type = action.action_type })
    elseif result.status == "failed" then
        -- Check retry policy
        if self:_should_retry(action) then
            self._retry_count = (self._retry_count or 0) + 1
            local delay = self:_get_retry_delay(action)
            self._blackboard:set(self._async_state_key, {
                action_type = action.action_type,
                status = "retrying",
                retry_count = self._retry_count,
                next_retry_at = self:_get_time() + delay,
            })
            self:_publish("action_retrying", { action_type = action.action_type, retry = self._retry_count, delay = delay })
            return { status = "running", error = "retrying" }
        end

        self._blackboard:set(self._async_state_key, nil)
        self._start_time = nil
        self._retry_count = 0
        self:_publish("action_failed", { action_type = action.action_type, error = result.error })
    end

    return result
end

---Poll a running action to check completion
---@param action table|nil The action to poll (uses current action if nil)
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil }
function ActionExecutor:poll(action)
    action = action or self._current_action
    if not action then
        return { status = "failed", error = "no action to poll" }
    end

    -- Check timeout
    if action.timeout_ms and self._start_time then
        local elapsed = self:_get_time() - self._start_time
        if elapsed > action.timeout_ms then
            self._current_status = "failed"
            self:_publish("action_timed_out", { action_type = action.action_type, error = "timeout exceeded" })
            self._blackboard:set(self._async_state_key, nil)
            return { status = "failed", error = "timeout exceeded" }
        end
    end

    -- Check if retry delay has elapsed
    local async_state = self._blackboard:get(self._async_state_key)
    if async_state and async_state.status == "retrying" then
        if self:_get_time() >= (async_state.next_retry_at or 0) then
            -- Execute again
            self._start_time = self:_get_time()
            self._blackboard:set(self._async_state_key, nil)
            return self:execute(action)
        end
        return { status = "running", error = "waiting for retry" }
    end

    -- Delegate to action-specific poll handler
    local poll_handler = self._poll_handlers[action.action_type]
    if not poll_handler then
        -- No poll handler = action is either done or not async
        return { status = "succeeded" }
    end

    local ok, result = pcall(poll_handler, self, action)
    if not ok then
        return { status = "failed", error = tostring(result) }
    end

    if result.status == "succeeded" then
        self._blackboard:set(self._async_state_key, nil)
        self._start_time = nil
        self._retry_count = 0
    elseif result.status == "failed" then
        if self:_should_retry(action) then
            self._retry_count = (self._retry_count or 0) + 1
            local delay = self:_get_retry_delay(action)
            self._blackboard:set(self._async_state_key, {
                action_type = action.action_type,
                status = "retrying",
                retry_count = self._retry_count,
                next_retry_at = self:_get_time() + delay,
            })
            return { status = "running", error = "retrying" }
        end
        self._blackboard:set(self._async_state_key, nil)
        self._start_time = nil
        self._retry_count = 0
    end

    return result
end

---Get the current executor state
---@return table { current_action = table|nil, status = string|nil, elapsed_ms = number|nil }
function ActionExecutor:get_state()
    local state = {
        current_action = self._current_action,
        status = self._current_status,
        elapsed_ms = nil,
    }
    if self._start_time and self._current_status == "running" then
        state.elapsed_ms = self:_get_time() - self._start_time
    end
    return state
end

-- ============================================================================
-- Retry Policy Helpers
-- ============================================================================

---Check if the action should be retried based on its retry policy
---@param action table
---@return boolean
function ActionExecutor:_should_retry(action)
    if not action.retry_policy or not action.retry_policy.max_retries then
        return false
    end
    return (self._retry_count or 0) < action.retry_policy.max_retries
end

---Get the delay before the next retry (with optional backoff)
---@param action table
---@return number delay in ms
function ActionExecutor:_get_retry_delay(action)
    local base_delay = action.retry_policy.delay_ms or 1000
    local multiplier = action.retry_policy.backoff_multiplier or 1.0
    return base_delay * (multiplier ^ (self._retry_count or 0))
end

---Get current time (from Sylvannas or os.clock)
---@return number time in ms
function ActionExecutor:_get_time()
    if core and core.game_time then
        return core.game_time()
    end
    return os.clock() * 1000
end

---Publish an event
---@param event_name string
---@param payload table
function ActionExecutor:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

-- ============================================================================
-- Action Handlers (one per action_type)
-- ============================================================================

ActionExecutor._handlers = {}

---pickup_quest: Interact NPC, simulate quest selection & accept
ActionExecutor._handlers["pickup_quest"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "pickup_quest: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "pickup_quest: interact failed: " .. tostring(err) }
        end
    end
    -- Simulate quest selection and acceptance
    self:_publish("quest_pickup_attempt", { npc_guid = guid, quest_id = action.quest_id })
    return { status = "succeeded" }
end

---turn_in_quest: Interact NPC, complete quest, simulate reward selection
ActionExecutor._handlers["turn_in_quest"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "turn_in_quest: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "turn_in_quest: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("quest_turn_in_attempt", { npc_guid = guid, quest_id = action.quest_id })
    return { status = "succeeded" }
end

---goto: Invoke NavigationAdapter:move_to, poll until arrived or failed
ActionExecutor._handlers["goto"] = function(self, action)
    if not self._nav_adapter then
        return { status = "failed", error = "goto: nav_adapter not available" }
    end
    local target = action.target or action.position
    if not target then
        return { status = "failed", error = "goto: missing target position" }
    end
    local ok, err = self._nav_adapter:move_to(target)
    if not ok then
        return { status = "failed", error = "goto: " .. tostring(err) }
    end
    return { status = "running" }
end

ActionExecutor._poll_handlers = {}
ActionExecutor._poll_handlers["goto"] = function(self, action)
    if not self._nav_adapter then
        return { status = "failed", error = "goto: nav_adapter not available" }
    end
    self._nav_adapter:poll()
    local nav_state = self._nav_adapter:get_state()
    if nav_state == "idle" then
        return { status = "succeeded" }
    elseif nav_state == "failed" then
        return { status = "failed", error = "goto: navigation failed" }
    end
    return { status = "running" }
end

---grind_area: Hand off to combat module via blackboard signal + position polling
ActionExecutor._handlers["grind_area"] = function(self, action)
    local area = action.area or action.position
    self._blackboard:set("module.runtime.grind_area", {
        position = area,
        radius = action.radius or 50,
        mob_ids = action.mob_ids or {},
        active = true,
    })
    self:_publish("grind_area_started", { position = area, radius = action.radius })
    return { status = "running" }
end

ActionExecutor._poll_handlers["grind_area"] = function(self, action)
    local area_state = self._blackboard:get("module.runtime.grind_area")
    if not area_state or not area_state.active then
        return { status = "succeeded" }
    end
    return { status = "running" }
end

---kill_target: Select target by creature entry, engage combat
ActionExecutor._handlers["kill_target"] = function(self, action)
    local entry = action.creature_entry or action.entry
    if not entry then
        return { status = "failed", error = "kill_target: missing creature_entry" }
    end
    self._blackboard:set("module.runtime.kill_target", {
        entry = entry,
        count = action.count or 1,
        active = true,
    })
    self:_publish("kill_target_started", { entry = entry })
    return { status = "running" }
end

ActionExecutor._poll_handlers["kill_target"] = function(self, action)
    local state = self._blackboard:get("module.runtime.kill_target")
    if not state or not state.active then
        return { status = "succeeded" }
    end
    return { status = "running" }
end

---vendor: Interact vendor NPC, sell/buy configured items
ActionExecutor._handlers["vendor"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "vendor: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "vendor: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("vendor_opened", { npc_guid = guid, sell = action.sell_items, buy = action.buy_items })
    return { status = "succeeded" }
end

---repair: Interact repair NPC, repair all
ActionExecutor._handlers["repair"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "repair: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "repair: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("repair_completed", { npc_guid = guid })
    return { status = "succeeded" }
end

---train: Interact trainer NPC, learn spells
ActionExecutor._handlers["train"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "train: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "train: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("training_completed", { npc_guid = guid, spells = action.spells })
    return { status = "succeeded" }
end

---flight_path: Interact flight master, select destination
ActionExecutor._handlers["flight_path"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "flight_path: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "flight_path: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("flight_path_used", { npc_guid = guid, destination = action.destination })
    return { status = "running" }
end

ActionExecutor._poll_handlers["flight_path"] = function(self, action)
    if core and core.player then
        local ok, is_moving = pcall(core.player.is_moving)
        if ok and is_moving then
            return { status = "running" }
        end
    end
    return { status = "succeeded" }
end

---hearth: Use hearthstone item from inventory
ActionExecutor._handlers["hearth"] = function(self, action)
    local item_id = action.item_id or 6948 -- Default Hearthstone
    if core and core.input and core.input.use_item then
        local ok, err = pcall(core.input.use_item, item_id)
        if not ok then
            return { status = "failed", error = "hearth: use_item failed: " .. tostring(err) }
        end
    end
    self:_publish("hearthstone_used", { item_id = item_id })
    return { status = "succeeded" }
end

---mailbox: Interact mailbox
ActionExecutor._handlers["mailbox"] = function(self, action)
    local guid = action.object_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "mailbox: missing object_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "mailbox: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("mailbox_opened", { guid = guid })
    return { status = "succeeded" }
end

---bank: Interact banker
ActionExecutor._handlers["bank"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "bank: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "bank: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("bank_opened", { npc_guid = guid })
    return { status = "succeeded" }
end

---use_item: Use item from inventory by name/ID
ActionExecutor._handlers["use_item"] = function(self, action)
    local item_id = action.item_id or action.item
    if not item_id then
        return { status = "failed", error = "use_item: missing item_id" }
    end
    if core and core.input and core.input.use_item then
        local ok, err = pcall(core.input.use_item, item_id)
        if not ok then
            return { status = "failed", error = "use_item: " .. tostring(err) }
        end
    end
    self:_publish("item_used", { item_id = item_id })
    return { status = "succeeded" }
end

---wait: Sleep/block for configured duration_ms
ActionExecutor._handlers["wait"] = function(self, action)
    local duration = action.duration_ms or 1000
    self._blackboard:set("module.runtime.wait_until", self:_get_time() + duration)
    return { status = "running" }
end

ActionExecutor._poll_handlers["wait"] = function(self, action)
    local wait_until = self._blackboard:get("module.runtime.wait_until")
    if not wait_until then
        return { status = "succeeded" }
    end
    if self:_get_time() >= wait_until then
        self._blackboard:set("module.runtime.wait_until", nil)
        return { status = "succeeded" }
    end
    return { status = "running" }
end

---set_variable: Write to Variable Store / blackboard
ActionExecutor._handlers["set_variable"] = function(self, action)
    local name = action.name or action.variable
    local value = action.value
    if not name then
        return { status = "failed", error = "set_variable: missing name" }
    end
    self._blackboard:set("module.runtime.var." .. tostring(name), value)
    self:_publish("variable_set", { name = name, value = value })
    return { status = "succeeded" }
end

---branch: Evaluate condition, route to true/false action lists
ActionExecutor._handlers["branch"] = function(self, action)
    local result = self:_evaluate_branch_condition(action)
    self._blackboard:set("module.runtime.branch_result", result)
    self:_publish("branch_evaluated", { condition = action.condition, result = result })
    return { status = "succeeded" }
end

function ActionExecutor:_evaluate_branch_condition(action)
    if not action.condition then
        return true
    end
    local cond = action.condition

    if cond.type == "has_item" then
        local items = self._blackboard:get("player.inventory") or {}
        for _, item in ipairs(items) do
            if item == cond.item_id or item.id == cond.item_id then
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

---dungeon_marker: Set flag in blackboard, return succeeded
ActionExecutor._handlers["dungeon_marker"] = function(self, action)
    local marker = action.marker or action.name or "default"
    self._blackboard:set("module.runtime.dungeon_marker." .. tostring(marker), true)
    self:_publish("dungeon_marker_set", { marker = marker })
    return { status = "succeeded" }
end

---death_skip: Die via core.player.kill(), wait for spirit healer
ActionExecutor._handlers["death_skip"] = function(self, action)
    if core and core.player and core.player.kill then
        local ok, err = pcall(core.player.kill)
        if not ok then
            return { status = "failed", error = "death_skip: kill failed: " .. tostring(err) }
        end
    end
    self._blackboard:set("module.runtime.death_resurrecting", true)
    self:_publish("death_skip_initiated", {})
    return { status = "running" }
end

ActionExecutor._poll_handlers["death_skip"] = function(self, action)
    if core and core.player then
        local ok, is_dead = pcall(core.player.is_dead)
        if ok and is_dead then
            return { status = "succeeded" }
        end
        local ok2, is_ghost = pcall(core.player.is_ghost)
        if ok2 and not is_ghost then
            self._blackboard:set("module.runtime.death_resurrecting", nil)
            return { status = "succeeded" }
        end
    end
    return { status = "running" }
end

---talk_to_npc: Interact NPC with optional gossip selection
ActionExecutor._handlers["talk_to_npc"] = function(self, action)
    local guid = action.npc_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "talk_to_npc: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "talk_to_npc: interact failed: " .. tostring(err) }
        end
    end
    -- Gossip selection would happen here
    self:_publish("npc_interacted", { npc_guid = guid, gossip = action.gossip_option })
    return { status = "succeeded" }
end

---loot_object: Interact lootable object, wait for loot window
ActionExecutor._handlers["loot_object"] = function(self, action)
    local guid = action.object_guid or action.target_guid
    if not guid then
        return { status = "failed", error = "loot_object: missing object_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "loot_object: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("loot_attempted", { guid = guid })
    return { status = "succeeded" }
end

---patrol: Follow configured waypoint path
ActionExecutor._handlers["patrol"] = function(self, action)
    local waypoints = action.waypoints or action.path
    if not waypoints or #waypoints == 0 then
        return { status = "failed", error = "patrol: no waypoints" }
    end
    self._blackboard:set("module.runtime.patrol", {
        waypoints = waypoints,
        current_index = 1,
        loop = action.loop or false,
        active = true,
    })
    self:_publish("patrol_started", { waypoint_count = #waypoints })
    return { status = "running" }
end

ActionExecutor._poll_handlers["patrol"] = function(self, action)
    local patrol_state = self._blackboard:get("module.runtime.patrol")
    if not patrol_state or not patrol_state.active then
        return { status = "succeeded" }
    end
    if not self._nav_adapter then
        return { status = "failed", error = "patrol: nav_adapter not available" }
    end
    self._nav_adapter:poll()
    local nav_state = self._nav_adapter:get_state()
    if nav_state == "idle" then
        -- Move to next waypoint
        patrol_state.current_index = patrol_state.current_index + 1
        if patrol_state.current_index > #patrol_state.waypoints then
            if patrol_state.loop then
                patrol_state.current_index = 1
            else
                patrol_state.active = false
                self._blackboard:set("module.runtime.patrol", patrol_state)
                return { status = "succeeded" }
            end
        end
        local next_wp = patrol_state.waypoints[patrol_state.current_index]
        self._nav_adapter:move_to(next_wp)
        self._blackboard:set("module.runtime.patrol", patrol_state)
    elseif nav_state == "failed" then
        return { status = "failed", error = "patrol: navigation failed at waypoint " .. patrol_state.current_index }
    end
    return { status = "running" }
end

---escort: Follow/guard escort target
ActionExecutor._handlers["escort"] = function(self, action)
    local target_guid = action.target_guid or action.npc_guid
    if not target_guid then
        return { status = "failed", error = "escort: missing target_guid" }
    end
    self._blackboard:set("module.runtime.escort", {
        target_guid = target_guid,
        follow_distance = action.follow_distance or 5,
        active = true,
    })
    self:_publish("escort_started", { target_guid = target_guid })
    return { status = "running" }
end

ActionExecutor._poll_handlers["escort"] = function(self, action)
    local escort_state = self._blackboard:get("module.runtime.escort")
    if not escort_state or not escort_state.active then
        return { status = "succeeded" }
    end
    if core and core.object_manager then
        local ok, objects = pcall(core.object_manager.get_all_objects)
        if ok then
            local target_found = false
            for _, obj in ipairs(objects) do
                if obj.get_guid and obj:get_guid() == escort_state.target_guid then
                    target_found = true
                    break
                end
            end
            if not target_found then
                escort_state.active = false
                self._blackboard:set("module.runtime.escort", escort_state)
                return { status = "succeeded" }
            end
        end
    end
    return { status = "running" }
end

---record_path: Start/stop recording player movement path
ActionExecutor._handlers["record_path"] = function(self, action)
    local mode = action.mode or "start"
    if mode == "start" then
        self._blackboard:set("module.runtime.recording_path", {
            points = {},
            active = true,
        })
        self:_publish("path_recording_started", {})
    elseif mode == "stop" or mode == "finish" then
        local recording = self._blackboard:get("module.runtime.recording_path")
        if recording then
            recording.active = false
            self._blackboard:set("module.runtime.recording_path", recording)
        end
        self:_publish("path_recording_stopped", {})
    end
    return { status = "succeeded" }
end

return ActionExecutor
