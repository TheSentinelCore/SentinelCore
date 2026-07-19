-- sentinel/runtime/runtime_action_executor.lua
-- SENT-8.5: Runtime Action Executor
-- ADR 008 §14 — Executes RuntimeAction objects at runtime

local RuntimeActionExecutor = {}
RuntimeActionExecutor.__index = RuntimeActionExecutor

local DEFAULT_TIMEOUT_MS = 10000
local DEFAULT_MAX_ATTEMPTS = 3

---Create a new RuntimeActionExecutor
---@param blackboard table The SentinelCore blackboard
---@param event_bus table The SentinelCore event bus
---@param nav_adapter table|nil The NavAdapter instance (for movement actions)
---@return table RuntimeActionExecutor instance
function RuntimeActionExecutor:new(blackboard, event_bus, nav_adapter)
    local o = setmetatable({}, RuntimeActionExecutor)
    o._blackboard = blackboard
    o._event_bus = event_bus
    o._nav_adapter = nav_adapter
    o._current_action = nil
    o._current_status = nil
    o._start_time_ms = nil
    o._attempt_count = 0
    o._result_cache_key = "module.runtime.action_cache"
    return o
end

---Execute a RuntimeAction immediately
---@param action table RuntimeAction with payload, retry_policy, timeout, generated_from
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil, cached = boolean|nil }
function RuntimeActionExecutor:execute(action)
    if not action or not action.payload then
        return { status = "failed", error = "invalid action: missing payload" }
    end

    local action_id = action.id or action.action_id

    -- Check if result is cached
    local cached = self:_get_cached_result(action_id)
    if cached then
        return { status = "succeeded", cached = true, result = cached }
    end

    self._current_action = action
    self._current_status = "running"
    self._start_time_ms = self:_get_time_ms()
    self._attempt_count = 0

    -- Check timeout
    local timeout_ms = action.timeout or DEFAULT_TIMEOUT_MS
    if self._start_time_ms and timeout_ms > 0 then
        if self:_get_time_ms() - self._start_time_ms > timeout_ms then
            self._current_status = "failed"
            self:_publish("action_timed_out", { action_id = action_id, error = "timeout exceeded" })
            return { status = "failed", error = "timeout exceeded" }
        end
    end

    local ok, result = pcall(function()
        return self:_execute_payload(action.payload, action)
    end)

    if not ok then
        self._current_status = "failed"
        self:_publish("action_handler_error", { action_id = action_id, error = tostring(result) })
        return { status = "failed", error = tostring(result) }
    end

    self._current_status = result.status

    if result.status == "succeeded" then
        self:_cache_result(action_id, result)
        self:_publish("action_succeeded", { action_id = action_id })
    elseif result.status == "failed" then
        local is_validation_error = string.find(result.error or "", "missing") ~= nil
        if not is_validation_error and self:_should_retry(action) then
            self._attempt_count = self._attempt_count + 1
            local delay_ms = self:_get_retry_delay(action)
            self._blackboard:set("module.runtime.retry_state", {
                action_id = action_id,
                status = "retrying",
                attempt_count = self._attempt_count,
                next_retry_at = self:_get_time_ms() + delay_ms,
                pending_action = action,
            })
            self:_publish("action_retrying", { action_id = action_id, attempt = self._attempt_count, delay_ms = delay_ms })
            return { status = "running", error = "retrying" }
        end
        self:_publish("action_failed", { action_id = action_id, error = result.error })
    end

    -- Clear retry state for this action after non-retry failure
    if result.status ~= "running" and not self:_should_retry(action) then
        self._blackboard:set("module.runtime.retry_state", nil)
    end

    return result
end

---Clear retry state (called on operation abort/cleanup)
function RuntimeActionExecutor:clear_retry_state()
    self._blackboard:set("module.runtime.retry_state", nil)
end

---Poll a running action to check completion
---@param action table|nil The action to poll (uses current action if nil)
---@return table Result: { status = "running"|"succeeded"|"failed", error = string|nil }
function RuntimeActionExecutor:poll(action)
    action = action or self._current_action
    if not action then
        return { status = "failed", error = "no action to poll" }
    end

    local action_id = action.id or action.action_id

    -- Check timeout
    local timeout_ms = action.timeout or DEFAULT_TIMEOUT_MS
    if timeout_ms > 0 and self._start_time_ms then
        if self:_get_time_ms() - self._start_time_ms > timeout_ms then
            return { status = "failed", error = "timeout exceeded" }
        end
    end

    -- Check retry state
    local retry_state = self._blackboard:get("module.runtime.retry_state")
    if retry_state and retry_state.action_id == action_id and retry_state.status == "retrying" then
        if self:_get_time_ms() >= (retry_state.next_retry_at or 0) then
            self._blackboard:set("module.runtime.retry_state", nil)
            return self:execute(retry_state.pending_action)
        end
        return { status = "running", error = "waiting for retry" }
    end

    -- Delegate to action-specific poll handler
    local action_type = action.payload and action.payload.type
    local poll_handler = self._poll_handlers and self._poll_handlers[action_type]

    if not poll_handler then
        return { status = "succeeded" }
    end

    local ok, result = pcall(poll_handler, self, action)
    if not ok then
        return { status = "failed", error = tostring(result) }
    end

    if result.status == "succeeded" then
        self._blackboard:set("module.runtime.retry_state", nil)
    elseif result.status == "failed" then
        if not self:_should_retry(action) then
            self._blackboard:set("module.runtime.retry_state", nil)
        end
    end

    return result
end

---Get current executor state
---@return table { current_action = table|nil, status = string|nil, elapsed_ms = number|nil }
function RuntimeActionExecutor:get_state()
    return {
        current_action = self._current_action,
        status = self._current_status,
        elapsed_ms = self._start_time_ms and (self:_get_time_ms() - self._start_time_ms) or nil,
    }
end

-- ============================================================================
-- Retry Policy Helpers
-- ============================================================================

---Check if action should be retried
---@param action table
---@return boolean
function RuntimeActionExecutor:_should_retry(action)
    local policy = action.retry_policy or {}
    local max_attempts = policy.max_attempts or DEFAULT_MAX_ATTEMPTS
    return self._attempt_count < max_attempts
end

---Get delay before next retry with backoff
---@param action table
---@return number delay in ms
function RuntimeActionExecutor:_get_retry_delay(action)
    local policy = action.retry_policy or {}
    local base_delay = policy.backoff_ms or 1000
    local multiplier = policy.backoff_multiplier or 1.0
    return base_delay * (multiplier ^ self._attempt_count)
end

---Get current time in milliseconds
---@return number
function RuntimeActionExecutor:_get_time_ms()
    if core and core.game_time then
        return core.game_time()
    end
    return os.clock() * 1000
end

---Publish event to event bus
---@param event_name string
---@param payload table
function RuntimeActionExecutor:_publish(event_name, payload)
    if self._event_bus then
        self._event_bus:publish(event_name, payload)
    end
end

-- ============================================================================
-- Action Result Cache (per RuntimeContext)
-- ============================================================================

---Get cached result for action
---@param action_id string Action ID
---@return table|nil Cached result
function RuntimeActionExecutor:_get_cached_result(action_id)
    if not action_id then
        return nil
    end
    local cache = self._blackboard:get(self._result_cache_key)
    if not cache then
        return nil
    end
    return cache[action_id]
end

---Cache action result
---@param action_id string Action ID
---@param result table Result to cache
function RuntimeActionExecutor:_cache_result(action_id, result)
    if not action_id then
        return
    end
    local cache = self._blackboard:get(self._result_cache_key) or {}
    cache[action_id] = result
    self._blackboard:set(self._result_cache_key, cache)
end

---Execute payload by type
---@param payload table ResolvedActionPayload
---@param action table Full action with policy/timeout
---@return table Result
function RuntimeActionExecutor:_execute_payload(payload, action)
    local action_type = payload.type

    if action_type == "pickup_quest" then
        return self:_handle_pickup_quest(payload)
    elseif action_type == "turn_in_quest" then
        return self:_handle_turn_in_quest(payload)
    elseif action_type == "goto" then
        return self:_handle_goto(payload)
    elseif action_type == "grind_area" then
        return self:_handle_grind_area(payload)
    elseif action_type == "kill_target" then
        return self:_handle_kill_target(payload)
    elseif action_type == "vendor" then
        return self:_handle_vendor(payload)
    elseif action_type == "repair" then
        return self:_handle_repair(payload)
    elseif action_type == "train" then
        return self:_handle_train(payload)
    elseif action_type == "flight_path" then
        return self:_handle_flight_path(payload)
    elseif action_type == "hearth" then
        return self:_handle_hearth(payload)
    elseif action_type == "mailbox" then
        return self:_handle_mailbox(payload)
    elseif action_type == "bank" then
        return self:_handle_bank(payload)
    elseif action_type == "use_item" then
        return self:_handle_use_item(payload)
    elseif action_type == "wait" then
        return self:_handle_wait(payload)
    elseif action_type == "set_variable" then
        return self:_handle_set_variable(payload)
    elseif action_type == "branch" then
        return self:_handle_branch(payload)
    elseif action_type == "dungeon_marker" then
        return self:_handle_dungeon_marker(payload)
    elseif action_type == "death_skip" then
        return self:_handle_death_skip(payload)
    elseif action_type == "talk_to_npc" then
        return self:_handle_talk_to_npc(payload)
    elseif action_type == "loot_object" then
        return self:_handle_loot_object(payload)
    else
        return { status = "failed", error = "unknown payload type: " .. tostring(action_type) }
    end
end

-- ============================================================================
-- Payload Handlers (use core.input.* and core.object_manager.*)
-- ============================================================================

function RuntimeActionExecutor:_handle_pickup_quest(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "pickup_quest: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "pickup_quest: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("quest_pickup_attempt", { npc_guid = guid, quest_id = payload.quest_id })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_turn_in_quest(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "turn_in_quest: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "turn_in_quest: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("quest_turn_in_attempt", { npc_guid = guid, quest_id = payload.quest_id })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_goto(payload)
    if not self._nav_adapter then
        return { status = "failed", error = "goto: nav_adapter not available" }
    end
    local target = payload.target or payload.position
    if not target then
        return { status = "failed", error = "goto: missing target position" }
    end
    local ok, err = self._nav_adapter:move_to(target)
    if not ok then
        return { status = "failed", error = "goto: " .. tostring(err) }
    end
    return { status = "running" }
end

RuntimeActionExecutor._poll_handlers = {}
RuntimeActionExecutor._poll_handlers["goto"] = function(self, action)
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

function RuntimeActionExecutor:_handle_grind_area(payload)
    local area = payload.area or payload.position
    self._blackboard:set("module.runtime.grind_area", {
        position = area,
        radius = payload.radius or 50,
        mob_ids = payload.mob_ids or {},
        active = true,
    })
    self:_publish("grind_area_started", { position = area, radius = payload.radius })
    return { status = "running" }
end

RuntimeActionExecutor._poll_handlers["grind_area"] = function(self, action)
    local area_state = self._blackboard:get("module.runtime.grind_area")
    if not area_state or not area_state.active then
        return { status = "succeeded" }
    end
    return { status = "running" }
end

function RuntimeActionExecutor:_handle_kill_target(payload)
    local entry = payload.creature_entry or payload.entry
    if not entry then
        return { status = "failed", error = "kill_target: missing creature_entry" }
    end
    self._blackboard:set("module.runtime.kill_target", {
        entry = entry,
        count = payload.count or 1,
        active = true,
    })
    self:_publish("kill_target_started", { entry = entry })
    return { status = "running" }
end

RuntimeActionExecutor._poll_handlers["kill_target"] = function(self, action)
    local state = self._blackboard:get("module.runtime.kill_target")
    if not state or not state.active then
        return { status = "succeeded" }
    end
    return { status = "running" }
end

function RuntimeActionExecutor:_handle_vendor(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "vendor: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "vendor: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("vendor_opened", { npc_guid = guid, sell = payload.sell_items, buy = payload.buy_items })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_repair(payload)
    local guid = payload.npc_guid or payload.target_guid
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

function RuntimeActionExecutor:_handle_train(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "train: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "train: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("training_completed", { npc_guid = guid, spells = payload.spells })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_flight_path(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "flight_path: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "flight_path: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("flight_path_used", { npc_guid = guid, destination = payload.destination })
    return { status = "running" }
end

RuntimeActionExecutor._poll_handlers["flight_path"] = function(self, action)
    if core and core.player then
        local ok, is_moving = pcall(core.player.is_moving)
        if ok and is_moving then
            return { status = "running" }
        end
    end
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_hearth(payload)
    local item_id = payload.item_id or 6948
    if core and core.input and core.input.use_item then
        local ok, err = pcall(core.input.use_item, item_id)
        if not ok then
            return { status = "failed", error = "hearth: use_item failed: " .. tostring(err) }
        end
    end
    self:_publish("hearthstone_used", { item_id = item_id })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_mailbox(payload)
    local guid = payload.object_guid or payload.target_guid
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

function RuntimeActionExecutor:_handle_bank(payload)
    local guid = payload.npc_guid or payload.target_guid
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

function RuntimeActionExecutor:_handle_use_item(payload)
    local item_id = payload.item_id or payload.item
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

function RuntimeActionExecutor:_handle_wait(payload)
    local duration = payload.duration_ms or 1000
    self._blackboard:set("module.runtime.wait_until", self:_get_time_ms() + duration)
    return { status = "running" }
end

RuntimeActionExecutor._poll_handlers["wait"] = function(self, action)
    local wait_until = self._blackboard:get("module.runtime.wait_until")
    if not wait_until then
        return { status = "succeeded" }
    end
    if self:_get_time_ms() >= wait_until then
        self._blackboard:set("module.runtime.wait_until", nil)
        return { status = "succeeded" }
    end
    return { status = "running" }
end

function RuntimeActionExecutor:_handle_set_variable(payload)
    local name = payload.name or payload.variable
    local value = payload.value
    if not name then
        return { status = "failed", error = "set_variable: missing name" }
    end
    self._blackboard:set("module.runtime.var." .. tostring(name), value)
    self:_publish("variable_set", { name = name, value = value })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_evaluate_branch_condition(payload)
    local cond = payload.condition
    if not cond then
        return true
    end

    if cond.type == "has_item" then
        local items = self._blackboard:get("player.inventory") or {}
        for _, item in ipairs(items) do
            if item == cond.item_id or (item.id == cond.item_id) then
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

function RuntimeActionExecutor:_handle_branch(payload)
    local result = self:_evaluate_branch_condition(payload)
    self._blackboard:set("module.runtime.branch_result", result)
    self:_publish("branch_evaluated", { condition = payload.condition, result = result })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_dungeon_marker(payload)
    local marker = payload.marker or payload.name or "default"
    self._blackboard:set("module.runtime.dungeon_marker." .. tostring(marker), true)
    self:_publish("dungeon_marker_set", { marker = marker })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_death_skip(payload)
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

RuntimeActionExecutor._poll_handlers["death_skip"] = function(self, action)
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

function RuntimeActionExecutor:_handle_talk_to_npc(payload)
    local guid = payload.npc_guid or payload.target_guid
    if not guid then
        return { status = "failed", error = "talk_to_npc: missing npc_guid" }
    end
    if core and core.input and core.input.interact_unit then
        local ok, err = pcall(core.input.interact_unit, guid)
        if not ok then
            return { status = "failed", error = "talk_to_npc: interact failed: " .. tostring(err) }
        end
    end
    self:_publish("npc_interacted", { npc_guid = guid, gossip = payload.gossip_option })
    return { status = "succeeded" }
end

function RuntimeActionExecutor:_handle_loot_object(payload)
    local guid = payload.object_guid or payload.target_guid
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

return RuntimeActionExecutor