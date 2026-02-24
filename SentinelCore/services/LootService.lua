local BT = require("ai/BehaviorTree")
local BTStatus = BT.Status
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")
local Helpers = require("lib/Helpers")
local get_now = require("lib/TimeHelper").get_now
local UnitQueries = require("lib/UnitQueries")
local safe_method = UnitQueries.safe_method
local safe_target_name = UnitQueries.safe_target_name

---@class LootService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _cfg table
---@field private _nav NavigationAdapter|nil
---@field private _state string
---@field private _target game_object|nil
---@field private _started_at number
---@field private _attempts number
---@field private _last_attempt_at number
---@field private _approach_started_at number
---@field private _approach_last_move_at number
---@field private _approaching boolean
---@field private _last_error string|nil
---@field private _loot_blacklist table
local LootService = {}
LootService.__index = LootService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param cfg table
---@param navigation? NavigationAdapter
---@return LootService
function LootService:new(event_bus, blackboard, cfg, navigation)
    local o = setmetatable({}, LootService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._state = "idle"
    o._target = nil
    o._started_at = 0
    o._attempts = 0
    o._last_attempt_at = 0
    o._approach_started_at = 0
    o._approach_last_move_at = 0
    o._approaching = false
    o._last_error = nil
    o._loot_blacklist = {} -- corpses that yielded 0 items (bag full, etc.)
    return o
end

---@return boolean
function LootService:is_active()
    return self._state == "looting"
end

---@return string
function LootService:get_state()
    return self._state
end

---@return string|nil
function LootService:get_last_error()
    return self._last_error
end

---@param target game_object
---@return boolean
---@return string|nil
function LootService:start(target)
    if not target or safe_method(target, "is_valid") ~= true then
        return false, ErrorCodes.LOOT_FAILED
    end

    local now = get_now()
    self._state = "looting"
    self._target = target
    self._started_at = now
    self._attempts = 0
    self._last_attempt_at = 0
    self._approach_started_at = 0
    self._approach_last_move_at = 0
    self._approaching = false
    self._last_error = nil
    if self._blackboard then
        self._blackboard:set("combat.was_looting", true)
    end

    self._event_bus:emit(Events.LOOT_STARTED, {
        timestamp = now,
        target_name = safe_target_name(target),
    })

    return true, nil
end

function LootService:reset()
    self._state = "idle"
    self._target = nil
    self._attempts = 0
    self._last_attempt_at = 0
    self._approach_started_at = 0
    self._approach_last_move_at = 0
    self._approaching = false
    if self._blackboard then
        self._blackboard:set("combat.was_looting", false)
    end
end

---@private
---@return number|nil
function LootService:_distance_to_target()
    local player_pos = self._blackboard and self._blackboard.get and self._blackboard:get("player.position") or nil
    local corpse_pos = safe_method(self._target, "get_position")
    return Helpers.distance_3d(player_pos, corpse_pos)
end

---@private
---@param now number
---@return boolean
---@return string|nil
---@return boolean
function LootService:_ensure_loot_range(now)
    local max_distance = tonumber(self._cfg.loot_approach_max_distance) or 45.0
    local approach_timeout = tonumber(self._cfg.loot_approach_timeout) or 8.0
    local approach_reissue = tonumber(self._cfg.loot_approach_reissue_cooldown) or 2.0

    -- Primary range check: game API knows exact interact range + facing
    local can_loot = safe_method(self._target, "can_be_looted")
    if can_loot == true then
        if self._approaching and self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        self._approaching = false
        self._approach_started_at = 0
        return true, nil, false
    end

    -- Fallback distance check
    local distance = self:_distance_to_target()
    local interact_range = tonumber(self._cfg.loot_interact_range) or 5.0

    -- Already within interact range by distance — treat as in-range
    if distance and distance <= interact_range then
        -- Face corpse so can_be_looted() succeeds on next check
        local corpse_pos = safe_method(self._target, "get_position")
        if corpse_pos and core and core.input and type(core.input.look_at) == "function" then
            pcall(core.input.look_at, corpse_pos)
        end
        if self._approaching and self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        self._approaching = false
        self._approach_started_at = 0
        return true, nil, false
    end

    if distance == nil or distance > max_distance then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if not self._nav or type(self._nav.move_to) ~= "function" then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if self._approach_started_at <= 0 then
        self._approach_started_at = now
    end
    if (now - self._approach_started_at) > approach_timeout then
        return false, ErrorCodes.LOOT_FAILED, false
    end

    if self._approach_last_move_at <= 0 or (now - self._approach_last_move_at) >= approach_reissue then
        local corpse_pos = safe_method(self._target, "get_position")
        if corpse_pos then
            pcall(self._nav.move_to, self._nav, corpse_pos)
            self._approach_last_move_at = now
        end
    end

    self._approaching = true
    return true, nil, true
end

---@return boolean
---@return string|nil
function LootService:update()
    if self._state ~= "looting" then
        return true, nil
    end

    local now = get_now()
    local timeout = tonumber(self._cfg.loot_timeout) or 10.0
    local loot_settle = tonumber(self._cfg.loot_settle_delay) or 1.0

    -- Hard timeout
    if now - self._started_at > timeout then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_TIMEOUT
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    -- Target validity
    if not self._target or safe_method(self._target, "is_valid") ~= true then
        self._state = "failed"
        self._last_error = ErrorCodes.LOOT_FAILED
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end

    -- Approach if not in range
    local range_ok, range_err, approaching = self:_ensure_loot_range(now)
    if not range_ok then
        self._state = "failed"
        self._last_error = range_err or ErrorCodes.LOOT_FAILED
        self._event_bus:emit(Events.LOOT_FAILED, {
            timestamp = now,
            error_code = self._last_error,
        })
        return false, self._last_error
    end
    if approaching == true then
        return true, nil
    end

    -- Phase 1: Send loot_object once when first in range
    if self._attempts == 0 then
        self._attempts = 1
        self._last_attempt_at = now

        -- Stop movement before interacting
        if self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end

        -- Face the corpse for reliable interaction
        local corpse_pos = safe_method(self._target, "get_position")
        if corpse_pos and core and core.input and type(core.input.look_at) == "function" then
            pcall(core.input.look_at, corpse_pos)
        end

        if core and core.input and core.input.loot_object then
            pcall(core.input.loot_object, self._target)
        end
        -- Fall through to check loot window immediately (may open synchronously)
    end

    -- Check loot window for items
    local loot_count = 0
    if core and core.game_ui and core.game_ui.get_loot_item_count then
        loot_count = tonumber(core.game_ui.get_loot_item_count()) or 0
    end

    if loot_count > 0 then
        if core and core.input and core.input.loot_item then
            for i = 0, loot_count - 1 do -- API is 0-indexed
                pcall(core.input.loot_item, i)
            end
        end
        -- Re-check: if items remain after pickup, bags are full for those items
        local remaining = 0
        if core and core.game_ui and core.game_ui.get_loot_item_count then
            remaining = tonumber(core.game_ui.get_loot_item_count()) or 0
        end
        if core and core.input and core.input.close_loot then
            pcall(core.input.close_loot)
        end
        if remaining > 0 then
            -- Items couldn't be picked up (bag full / capped quest item) — blacklist
            self:_blacklist_corpse(self._target)
        end
        self._state = "completed"
        self._event_bus:emit(Events.LOOT_COMPLETED, {
            timestamp = now,
            looted_items = loot_count - remaining,
        })
        return true, nil
    end

    -- Wait for settle delay before deciding
    local elapsed = now - self._last_attempt_at
    if elapsed < loot_settle then
        return true, nil
    end

    -- Settle elapsed with no items — retry if corpse still shows lootable
    local max_retries = 2
    if self._attempts <= max_retries then
        local still_lootable = safe_method(self._target, "has_loot") == true
            or safe_method(self._target, "can_be_looted") == true
        if still_lootable then
            self._attempts = self._attempts + 1
            self._last_attempt_at = now

            -- Stop movement and face corpse before retry
            if self._nav and self._nav.stop then
                pcall(self._nav.stop, self._nav)
            end
            local corpse_pos = safe_method(self._target, "get_position")
            if corpse_pos and core and core.input and type(core.input.look_at) == "function" then
                pcall(core.input.look_at, corpse_pos)
            end

            if core and core.input and core.input.loot_object then
                pcall(core.input.loot_object, self._target)
            end
            return true, nil
        end
    end

    -- Done (either looted or corpse no longer shows loot)
    if core and core.input and core.input.close_loot then
        pcall(core.input.close_loot)
    end
    -- Blacklist this corpse so the scan doesn't re-discover it
    -- (handles bag-full / capped quest items that still show has_loot)
    self:_blacklist_corpse(self._target)
    self._state = "completed"
    self._event_bus:emit(Events.LOOT_COMPLETED, {
        timestamp = now,
        looted_items = 0,
    })
    return true, nil
end

--- Blacklist a corpse that yielded 0 items (bag full, unlootable quest item, etc.)
--- so the scan doesn't re-discover it every tick.
--- Uses GUID as key because object references change across ticks.
---@private
---@param target game_object
function LootService:_blacklist_corpse(target)
    if not target then return end
    local guid = safe_method(target, "get_guid")
    if not guid then return end
    local ttl = tonumber(self._cfg.loot_blacklist_ttl) or 60.0
    self._loot_blacklist[guid] = get_now() + ttl
end

--- Check whether a corpse is in the loot blacklist.
--- Uses GUID as key because object references change across ticks.
---@private
---@param target game_object
---@return boolean
function LootService:_is_blacklisted(target)
    if not target then return false end
    local guid = safe_method(target, "get_guid")
    if not guid then return false end
    local expiry = self._loot_blacklist[guid]
    if not expiry then return false end
    if get_now() > expiry then
        self._loot_blacklist[guid] = nil
        return false
    end
    return true
end

--- Check if any living enemy is actively targeting the player or pet.
--- Used for the soft combat gate: allows looting when combat flag lingers
--- after killing the last mob (1-3s delay before flag clears).
---@private
---@return boolean true if at least one living attacker is targeting us
function LootService:_has_living_attackers()
    local player = self._blackboard:get("player.object")
    if not player then return false end

    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok, value = pcall(core.object_manager.get_visible_objects)
        if ok and type(value) == "table" then objects = value end
    end

    for i = 1, #objects do
        local unit = objects[i]
        if unit and unit ~= player then
            local valid = safe_method(unit, "is_valid")
            local dead = safe_method(unit, "is_dead")
            local in_combat = safe_method(unit, "is_in_combat")
            if valid == true and dead ~= true and in_combat == true then
                local unit_target = safe_method(unit, "get_target")
                if unit_target then
                    -- Check if targeting player
                    local is_player = (unit_target == player)
                    if not is_player then
                        local ut_guid = safe_method(unit_target, "get_guid")
                        local p_guid = safe_method(player, "get_guid")
                        is_player = ut_guid and p_guid and ut_guid == p_guid
                    end
                    if is_player then return true end

                    -- Check if targeting player's pet
                    local pet = safe_method(player, "get_pet")
                    if pet then
                        local is_pet = (unit_target == pet)
                        if not is_pet then
                            local ut_guid2 = safe_method(unit_target, "get_guid")
                            local pet_guid = safe_method(pet, "get_guid")
                            is_pet = ut_guid2 and pet_guid and ut_guid2 == pet_guid
                        end
                        if is_pet then return true end
                    end
                end
            end
        end
    end
    return false
end

--- Scan nearby dead units with loot and build a distance-sorted queue.
---@private
---@return table[] array of lootable game_objects, nearest first
function LootService:_scan_loot_queue()
    local player_pos = self._blackboard:get("player.position")
    if not player_pos then return {} end

    local scan_radius = tonumber(self._cfg.loot_scan_radius) or 40.0
    local objects = {}
    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok, value = pcall(core.object_manager.get_visible_objects)
        if ok and type(value) == "table" then objects = value end
    end

    local lootable = {}
    for i = 1, #objects do
        local unit = objects[i]
        if unit then
            local valid = safe_method(unit, "is_valid")
            local dead = safe_method(unit, "is_dead")
            local has_loot = safe_method(unit, "has_loot")
            local can_loot = safe_method(unit, "can_be_looted")
            if valid == true and dead == true and (has_loot == true or can_loot == true) and not self:_is_blacklisted(unit) then
                local pos = safe_method(unit, "get_position")
                local dist = Helpers.distance_3d(player_pos, pos)
                if dist and dist <= scan_radius then
                    lootable[#lootable + 1] = { target = unit, distance = dist }
                end
            end
        end
    end

    table.sort(lootable, function(a, b) return a.distance < b.distance end)

    local result = {}
    for i = 1, #lootable do
        result[i] = lootable[i].target
    end
    return result
end

--- Build BT node for loot phase (used by GrindService).
--- Delegates actual looting to the service's start/update lifecycle.
--- Scans for all nearby lootable corpses and processes them in distance order.
---@return table BT node
function LootService:build()
    local bb = self._blackboard
    local loot_pending_since = nil
    local loot_queue = {}
    local queue_index = 0

    return BT.ReactiveSequence:new("loot", {
        BT.Condition:new("has_lootable", function()
            local pending = bb:get("loot.pending_target")
            local target = bb:get("combat.target")
            local in_combat = bb:get("player.in_combat", false)

            -- Kill detection: promote dead combat target to loot pending
            if not pending and target then
                local ok, dead = pcall(function() return target:is_dead() end)
                if ok and dead then
                    -- Only promote if corpse actually has loot
                    local has_loot = safe_method(target, "has_loot")
                    local can_loot = safe_method(target, "can_be_looted")
                    if has_loot == true or can_loot == true then
                        bb:set("loot.pending_target", target)
                        bb:clear("combat.target")
                        pending = target
                    else
                        -- Dead but no loot — just clear the target
                        bb:clear("combat.target")
                    end
                end
            end

            -- Discover AoE/DoT kills never promoted to pending
            if not pending and not in_combat then
                local queue = self:_scan_loot_queue()
                if #queue > 0 then
                    bb:set("loot.pending_target", queue[1])
                    pending = queue[1]
                end
            end

            -- Skip blacklisted pending targets (bag full, capped quest items)
            if pending and self:_is_blacklisted(pending) then
                bb:clear("loot.pending_target")
                pending = nil
            end

            -- Soft combat gate: allow looting when combat flag lingers
            -- but no living enemies are actually targeting us.
            if in_combat then
                if self:_has_living_attackers() then
                    return false
                end
                -- Combat flag lingers after kill — safe to loot
            end

            -- Pending check with timeout
            if pending then
                if not loot_pending_since then
                    loot_pending_since = get_now()
                end
                if (get_now()) - loot_pending_since > 15.0 then
                    bb:clear("loot.pending_target")
                    loot_pending_since = nil
                    return false
                end
                return true
            end

            loot_pending_since = nil
            return false
        end),

        BT.Timeout:new("loot_timeout", 10.0,
            BT.Action:new("loot_corpse", function()
                local target = bb:get("loot.pending_target")
                if not target then return BTStatus.SUCCESS end

                -- Detect stale looting state after BT preemption.
                -- ReactiveSelector reset does not call LootService:reset(),
                -- so internal state can persist with stale timers.
                if self:is_active() then
                    local age = get_now() - self._started_at
                    local stale_timeout = tonumber(self._cfg.loot_stale_reset_timeout) or 8.0
                    if age > stale_timeout or self._target ~= target then
                        self:reset()
                    end
                end
                -- Reset terminal states (completed/failed) only when pending
                -- target changed — avoids restarting a just-completed loot cycle
                -- that still needs its queue advance to run.
                local st = self:get_state()
                if st ~= "idle" and st ~= "looting" and self._target ~= target then
                    self:reset()
                end

                local state = self:get_state()

                -- Start looting if idle: scan for all nearby lootable corpses
                if state == "idle" then
                    loot_queue = self:_scan_loot_queue()
                    queue_index = 1

                    -- Use queue's first entry if pending target isn't in queue
                    local found_pending = false
                    for i = 1, #loot_queue do
                        if loot_queue[i] == target then
                            queue_index = i
                            found_pending = true
                            break
                        end
                    end
                    if not found_pending and #loot_queue > 0 then
                        target = loot_queue[1]
                        bb:set("loot.pending_target", target)
                    end

                    local ok = self:start(target)
                    if not ok then
                        bb:clear("loot.pending_target")
                        loot_pending_since = nil
                        return BTStatus.FAILURE
                    end
                    return BTStatus.RUNNING
                end

                -- Update active loot
                if self:is_active() then
                    self:update()
                    return BTStatus.RUNNING
                end

                -- Current target completed or failed — advance queue
                self:reset()
                queue_index = queue_index + 1
                if queue_index <= #loot_queue then
                    local next_target = loot_queue[queue_index]
                    -- Verify next target still has loot
                    local still_lootable = safe_method(next_target, "is_valid") == true
                        and safe_method(next_target, "is_dead") == true
                        and (safe_method(next_target, "has_loot") == true
                             or safe_method(next_target, "can_be_looted") == true)
                        and not self:_is_blacklisted(next_target)
                    if still_lootable then
                        bb:set("loot.pending_target", next_target)
                        local ok = self:start(next_target)
                        if ok then
                            return BTStatus.RUNNING
                        end
                    end
                end

                -- Queue exhausted or next target invalid
                bb:clear("loot.pending_target")
                loot_pending_since = nil
                loot_queue = {}
                queue_index = 0
                if state == "completed" then
                    return BTStatus.SUCCESS
                end
                return BTStatus.FAILURE
            end)
        ),
    })
end

return LootService
