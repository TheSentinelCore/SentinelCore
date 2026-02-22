local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

---@private
---@param obj any
---@param method string
---@param ... any
---@return any
local function safe_method(obj, method, ...)
    if not obj then
        return nil
    end
    local fn = obj[method]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, value = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return value
end

---@private
---@param target game_object|nil
---@return string
local function safe_target_name(target)
    local name = safe_method(target, "get_name")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "unknown"
end

---@private
---@param pos vec3|table|nil
---@return vec3|nil
local function copy_vec3(pos)
    if type(pos) ~= "table" then
        return nil
    end

    return {
        x = tonumber(pos.x) or 0,
        y = tonumber(pos.y) or 0,
        z = tonumber(pos.z) or 0,
    }
end

---@private
---@param value any
---@return number|nil
local function normalize_pct(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    if n > 1.0 then
        n = n / 100.0
    end
    if n < 0 then
        n = 0
    elseif n > 1 then
        n = 1
    end
    return n
end

---@private
---@param unit game_object|nil
---@return number|nil
local function resolve_unit_mana_pct(unit)
    if not unit then
        return nil
    end

    local current = tonumber(safe_method(unit, "get_power", 0))
    local maximum = tonumber(safe_method(unit, "get_max_power", 0))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    current = tonumber(safe_method(unit, "get_mana"))
    maximum = tonumber(safe_method(unit, "get_max_mana"))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    return nil
end

---@private
---@param lhs game_object|nil
---@param rhs game_object|nil
---@return boolean
local function is_same_unit(lhs, rhs)
    if not lhs or not rhs then
        return false
    end
    if lhs == rhs then
        return true
    end

    local lhs_guid = tonumber(safe_method(lhs, "get_guid"))
        or tonumber(safe_method(lhs, "get_object_guid"))
        or 0
    local rhs_guid = tonumber(safe_method(rhs, "get_guid"))
        or tonumber(safe_method(rhs, "get_object_guid"))
        or 0
    if lhs_guid > 0 and rhs_guid > 0 then
        return lhs_guid == rhs_guid
    end

    return false
end

---@private
---@param target game_object|nil
---@param player game_object|nil
---@return boolean
local function is_defensive_target(target, player)
    if not target or not player then
        return false
    end

    local target_target = safe_method(target, "get_target")
    if is_same_unit(target_target, player) then
        return true
    end

    local pet = safe_method(player, "get_pet")
    if is_same_unit(target_target, pet) then
        return true
    end

    return false
end

---@class CombatService
---@field private _event_bus EventBus
---@field private _blackboard Blackboard
---@field private _nav NavigationAdapter
---@field private _targeting TargetingService
---@field private _rotation RotationEngine
---@field private _cfg table
---@field private _state string
---@field private _active_target game_object|nil
---@field private _started_at number
---@field private _pull_started_at number
---@field private _pull_sent boolean
---@field private _pull_nav_last_dest vec3|nil
---@field private _pull_nav_last_move_at number
---@field private _pull_nav_last_repath_at number
---@field private _pull_nav_repath_pending boolean
---@field private _combat_nav_last_dest vec3|nil
---@field private _combat_nav_last_move_at number
---@field private _combat_nav_last_repath_at number
---@field private _combat_nav_repath_pending boolean
---@field private _combat_chasing boolean
---@field private _combat_face_last_at number
---@field private _combat_face_last_target_pos vec3|nil
---@field private _last_error string|nil
local CombatService = {}
CombatService.__index = CombatService

---@param event_bus EventBus
---@param blackboard Blackboard
---@param navigation NavigationAdapter
---@param targeting TargetingService
---@param rotation RotationEngine
---@param cfg table
---@return CombatService
function CombatService:new(event_bus, blackboard, navigation, targeting, rotation, cfg)
    local o = setmetatable({}, CombatService)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav = navigation
    o._targeting = targeting
    o._rotation = rotation
    o._cfg = cfg or {}
    o._state = "idle"
    o._active_target = nil
    o._started_at = 0
    o._pull_started_at = 0
    o._pull_sent = false
    o._pull_nav_last_dest = nil
    o._pull_nav_last_move_at = 0
    o._pull_nav_last_repath_at = 0
    o._pull_nav_repath_pending = false
    o._combat_nav_last_dest = nil
    o._combat_nav_last_move_at = 0
    o._combat_nav_last_repath_at = 0
    o._combat_nav_repath_pending = false
    o._combat_chasing = false
    o._combat_face_last_at = 0
    o._combat_face_last_target_pos = nil
    o._last_error = nil
    return o
end

---@return boolean
function CombatService:is_active()
    return self._state == "pull" or self._state == "combat"
end

---@return boolean
---@return string|nil
function CombatService:run_maintenance(force)
    if self:is_active() then
        return false, nil
    end
    if not self._rotation or not self._rotation.tick_maintenance_once then
        return false, nil
    end
    local should_run = force == true
    if not should_run and self._rotation.should_hold_maintenance then
        local ok_hold, hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
        if ok_hold and hold == true then
            should_run = true
        else
            return false, nil
        end
    end
    if not should_run then
        return false, nil
    end

    local ok_tick, executed, err = pcall(self._rotation.tick_maintenance_once, self._rotation)
    if not ok_tick then
        return false, ErrorCodes.ROTATION_UNAVAILABLE
    end
    if executed == true then
        return true, nil
    end
    if err == ErrorCodes.CAST_GUARD_BLOCKED or err == ErrorCodes.ROTATION_UNAVAILABLE then
        return false, nil
    end
    return false, err
end

---@return boolean
function CombatService:should_hold_for_maintenance()
    if self:is_active() then
        return false
    end
    if not self._rotation or not self._rotation.should_hold_maintenance then
        return false
    end

    local ok, hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
    if not ok or hold ~= true then
        return false
    end

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

    return true
end

---@return string
function CombatService:get_state()
    return self._state
end

---@return string|nil
function CombatService:get_last_error()
    return self._last_error
end

---@private
function CombatService:_reset_pull_navigation()
    self._pull_nav_last_dest = nil
    self._pull_nav_last_move_at = 0
    self._pull_nav_last_repath_at = 0
    self._pull_nav_repath_pending = false
end

---@private
function CombatService:_reset_combat_navigation()
    self._combat_nav_last_dest = nil
    self._combat_nav_last_move_at = 0
    self._combat_nav_last_repath_at = 0
    self._combat_nav_repath_pending = false
    self._combat_chasing = false
    self._combat_face_last_at = 0
    self._combat_face_last_target_pos = nil
end

---@private
---@return table
function CombatService:_resolve_movement_profile()
    local resolved = nil
    if self._rotation and self._rotation.get_movement_profile then
        local ok_profile, profile = pcall(self._rotation.get_movement_profile, self._rotation)
        if ok_profile and type(profile) == "table" then
            resolved = profile
        end
    end

    resolved = resolved or {}
    return {
        combat_chase_range = tonumber(resolved.combat_chase_range) or tonumber(self._cfg.combat_chase_range) or 5.5,
    }
end

---@private
---@param target_pos vec3
---@return boolean
function CombatService:_pull_destination_changed(target_pos)
    if not self._pull_nav_last_dest then
        return true
    end

    local delta = Helpers.distance_3d(self._pull_nav_last_dest, target_pos)
    local threshold = tonumber(self._cfg.pull_chase_repath_distance) or 3.0
    return delta > threshold
end

---@private
---@param target_pos vec3
---@param now number
---@param reason string|nil
function CombatService:_issue_pull_move_to(target_pos, now, reason)
    local destination = copy_vec3(target_pos) or target_pos
    if self._nav and self._nav.move_to then
        self._nav:move_to(destination)
    end
    self._event_bus:emit(Events.COMBAT_CHASE_UPDATE, {
        timestamp = now,
        phase = "pull",
        reason = tostring(reason or "refresh"),
        x = tonumber(destination and destination.x) or 0,
        y = tonumber(destination and destination.y) or 0,
        z = tonumber(destination and destination.z) or 0,
    })
    self._pull_nav_last_dest = copy_vec3(destination)
    self._pull_nav_last_move_at = now
    self._pull_nav_repath_pending = false
end

---@private
---@param target_pos vec3
---@param now number
function CombatService:_update_pull_navigation(target_pos, now)
    local destination_changed = self:_pull_destination_changed(target_pos)
    local move_to_cooldown = tonumber(self._cfg.pull_chase_move_to_cooldown) or 0.75
    local since_last = now - (tonumber(self._pull_nav_last_move_at) or 0)
    local should_issue = false

    if self._pull_nav_last_dest == nil then
        should_issue = true
    elseif destination_changed and since_last >= move_to_cooldown then
        should_issue = true
    elseif since_last >= (move_to_cooldown * 2.0) then
        -- Keep chase alive if nav finished/failed without requiring direct path calls here.
        should_issue = true
    end

    if should_issue then
        local reason = "refresh"
        if self._pull_nav_last_dest == nil then
            reason = "initial"
        elseif destination_changed then
            reason = "target_shift"
        end
        self:_issue_pull_move_to(target_pos, now, reason)
    end
end

---@private
---@param target_pos vec3
---@return boolean
function CombatService:_combat_destination_changed(target_pos)
    if not self._combat_nav_last_dest then
        return true
    end

    local delta = Helpers.distance_3d(self._combat_nav_last_dest, target_pos)
    local threshold = tonumber(self._cfg.combat_chase_repath_distance) or 3.0
    return delta > threshold
end

---@private
---@param target_pos vec3
---@param now number
---@param reason string|nil
function CombatService:_issue_combat_move_to(target_pos, now, reason)
    local destination = copy_vec3(target_pos) or target_pos
    if self._nav and self._nav.move_to then
        self._nav:move_to(destination)
    end
    self._event_bus:emit(Events.COMBAT_CHASE_UPDATE, {
        timestamp = now,
        phase = "combat",
        reason = tostring(reason or "refresh"),
        x = tonumber(destination and destination.x) or 0,
        y = tonumber(destination and destination.y) or 0,
        z = tonumber(destination and destination.z) or 0,
    })
    self._combat_nav_last_dest = copy_vec3(destination)
    self._combat_nav_last_move_at = now
    self._combat_nav_repath_pending = false
    self._combat_chasing = true
end

---@private
---@param target_pos vec3
---@param now number
function CombatService:_update_combat_navigation(target_pos, now)
    local destination_changed = self:_combat_destination_changed(target_pos)
    local move_to_cooldown = tonumber(self._cfg.combat_chase_move_to_cooldown) or 0.75
    local since_last = now - (tonumber(self._combat_nav_last_move_at) or 0)
    local should_issue = false

    if self._combat_nav_last_dest == nil then
        should_issue = true
    elseif destination_changed and since_last >= move_to_cooldown then
        should_issue = true
    elseif since_last >= (move_to_cooldown * 2.0) then
        -- Keep chase alive if nav finished/failed without requiring direct path calls here.
        should_issue = true
    end

    if should_issue then
        local reason = "refresh"
        if self._combat_nav_last_dest == nil then
            reason = "initial"
        elseif destination_changed then
            reason = "target_shift"
        end
        self:_issue_combat_move_to(target_pos, now, reason)
    end
end

---@private
---@param target game_object|nil
---@param reason string|nil
function CombatService:_mark_target_failed(target, reason)
    if not target
        or not self._targeting
        or type(self._targeting.mark_target_failed) ~= "function" then
        return
    end

    local ttl
    if reason == ErrorCodes.COMBAT_TIMEOUT then
        ttl = tonumber(self._cfg.target_memory_ttl_combat_timeout) or 30.0
    elseif reason == ErrorCodes.PULL_FAILED then
        ttl = tonumber(self._cfg.target_memory_ttl_pull_failed) or 20.0
    elseif reason == ErrorCodes.TARGET_LOST then
        ttl = tonumber(self._cfg.target_memory_ttl_target_lost) or 10.0
    elseif reason == ErrorCodes.NAV_MOVE_FAILED then
        ttl = tonumber(self._cfg.target_memory_ttl_nav_failed) or 15.0
    else
        ttl = tonumber(self._cfg.target_memory_ttl_default) or 12.0
    end

    pcall(self._targeting.mark_target_failed, self._targeting, target, reason, ttl)
end

---@private
---@param error_code string|nil
---@param now number
---@param target game_object|nil
---@return boolean
---@return string
function CombatService:_fail_and_reset(error_code, now, target)
    self._last_error = error_code or ErrorCodes.PULL_FAILED
    self:_mark_target_failed(target or self._active_target, self._last_error)
    self._event_bus:emit(Events.COMBAT_FAILED, {
        timestamp = now,
        error_code = self._last_error,
    })
    self:reset()
    return false, self._last_error
end

---@private
---@param target game_object
---@param now number
---@param distance number|nil
function CombatService:_apply_combat_chase(target, now, distance)
    local profile = self:_resolve_movement_profile()
    local chase_range = tonumber(profile.combat_chase_range) or tonumber(self._cfg.combat_chase_range) or 5.5
    if chase_range <= 0 then
        return
    end

    distance = tonumber(distance) or self:_distance_to_target(target)
    if distance > chase_range then
        local target_pos = safe_method(target, "get_position")
        if target_pos then
            self:_update_combat_navigation(target_pos, now)
        end
        return
    end

    if self._combat_chasing then
        if self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        self:_reset_combat_navigation()
    end
end

---@private
---@param target game_object
---@param now number
---@param distance number
function CombatService:_maintain_combat_facing(target, now, distance)
    if not core or not core.input or type(core.input.look_at) ~= "function" then
        return
    end
    if self._combat_chasing then
        return
    end

    local max_face_distance = tonumber(self._cfg.combat_face_max_distance)
    if max_face_distance == nil then
        local profile = self:_resolve_movement_profile()
        local chase_range = tonumber(profile.combat_chase_range) or tonumber(self._cfg.combat_chase_range) or 5.5
        max_face_distance = math.max(6.5, chase_range + 1.0)
    end
    if distance > max_face_distance then
        return
    end

    local player = self._blackboard:get("player.object")
    if safe_method(player, "is_casting_spell") == true or safe_method(player, "is_channelling_spell") == true then
        return
    end

    local target_pos = safe_method(target, "get_position")
    if not target_pos then
        return
    end

    local face_cooldown = tonumber(self._cfg.combat_face_cooldown) or 0.20
    local realign_distance = tonumber(self._cfg.combat_face_realign_distance) or 0.75
    local target_moved = false
    if self._combat_face_last_target_pos then
        target_moved = Helpers.distance_3d(self._combat_face_last_target_pos, target_pos) >= realign_distance
    end

    if not target_moved and (now - self._combat_face_last_at) < face_cooldown then
        return
    end

    pcall(core.input.look_at, target_pos)
    self._combat_face_last_at = now
    self._combat_face_last_target_pos = copy_vec3(target_pos)
end

---@private
---@param target game_object
---@param now number
---@return game_object
function CombatService:_maybe_switch_to_attacker(target, now)
    if not self._targeting or not self._targeting.acquire_defensive_target then
        return target
    end

    local ok_defensive, defensive = pcall(self._targeting.acquire_defensive_target, self._targeting, target)
    if not ok_defensive or not defensive or defensive == target then
        return target
    end

    self._active_target = defensive
    self._blackboard:set("combat.target", defensive)
    if safe_method(target, "is_dead") == true then
        self._blackboard:set("loot.pending_target", target)
    end
    if self._state == "pull" then
        self._state = "combat"
        self._pull_sent = true
        self:_reset_pull_navigation()
    end

    self._event_bus:emit(Events.TARGET_SWITCHED, {
        timestamp = now,
        reason = "defensive_retarget",
        from_target_name = safe_target_name(target),
        to_target_name = safe_target_name(defensive),
    })

    if core and core.input and core.input.set_target then
        pcall(core.input.set_target, defensive)
    end

    return defensive
end

---@param target game_object
---@return boolean
---@return string|nil
function CombatService:start(target)
    if not target then
        return false, ErrorCodes.TARGET_NOT_FOUND
    end

    if not self:_target_valid(target) then
        return false, ErrorCodes.TARGET_NOT_FOUND
    end

    if self._rotation and self._rotation.should_hold_maintenance then
        local ok_hold, hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
        if ok_hold and hold == true then
            if self._nav and self._nav.stop then
                pcall(self._nav.stop, self._nav)
            end
            return false, ErrorCodes.MAINTENANCE_REQUIRED
        end
    end

    local min_pull_mana_pct = tonumber(self._cfg.min_pull_mana_pct)
    if min_pull_mana_pct and min_pull_mana_pct > 0 then
        local player = self._blackboard:get("player.object")
        local mana_pct = resolve_unit_mana_pct(player)
        local defensive = is_defensive_target(target, player)
        if mana_pct ~= nil and mana_pct < min_pull_mana_pct and defensive ~= true then
            if self._nav and self._nav.stop then
                pcall(self._nav.stop, self._nav)
            end
            return false, ErrorCodes.MAINTENANCE_REQUIRED
        end
    end

    local now = (core and core.time and core.time()) or 0
    self._active_target = target
    self._blackboard:set("combat.target", target)
    self._state = "pull"
    self._started_at = now
    self._pull_started_at = now
    self._pull_sent = false
    self:_reset_pull_navigation()
    self:_reset_combat_navigation()
    self._last_error = nil

    self._event_bus:emit(Events.PULL_STARTED, {
        timestamp = now,
        target_name = safe_target_name(target),
    })

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

    return true, nil
end

function CombatService:reset()
    self._state = "idle"
    self._active_target = nil
    self._pull_sent = false
    self:_reset_pull_navigation()
    self:_reset_combat_navigation()
    self._blackboard:clear("combat.target")
    if self._targeting and self._targeting.clear_target then
        pcall(self._targeting.clear_target, self._targeting, "combat_reset")
    end
end

---@private
---@param target game_object
---@return boolean
function CombatService:_target_valid(target)
    if not target then
        return false
    end

    local valid = safe_method(target, "is_valid")
    if valid ~= true then
        return false
    end

    local dead = safe_method(target, "is_dead")
    if dead == nil or dead == true then
        return false
    end

    local ghost = safe_method(target, "is_ghost")
    if ghost == nil or ghost == true then
        return false
    end

    return true
end

---@private
---@param target game_object
---@return number
function CombatService:_distance_to_target(target)
    local player_pos = self._blackboard:get("player.position")
    local target_pos = safe_method(target, "get_position")
    return Helpers.distance_3d(player_pos, target_pos)
end

---@private
---@param target game_object
---@return boolean
---@return string|nil
function CombatService:_execute_pull(target)
    local now = (core and core.time and core.time()) or 0
    local pull_timeout = tonumber(self._cfg.pull_timeout) or 8.0
    if now - self._pull_started_at > pull_timeout then
        return false, ErrorCodes.PULL_FAILED
    end

    local pull_profile = nil
    local ok_profile, resolved = pcall(self._rotation.get_pull_profile, self._rotation)
    if ok_profile and type(resolved) == "table" then
        pull_profile = resolved
    else
        pull_profile = {}
    end
    local pull_range = tonumber(pull_profile.max_pull_range) or 30
    local distance = self:_distance_to_target(target)

    if distance > pull_range then
        local target_pos = safe_method(target, "get_position")
        if not target_pos then
            return false, ErrorCodes.TARGET_LOST
        end
        self:_update_pull_navigation(target_pos, now)
        return true, nil
    end

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end
    self:_reset_pull_navigation()

    if core and core.input and core.input.set_target then
        pcall(core.input.set_target, target)
    end

    if pull_profile.pull_spell_id then
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            return false, ErrorCodes.ROTATION_UNAVAILABLE
        end
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            return false, err
        end
    end

    local player = self._blackboard:get("player.object")
    local player_in_combat = safe_method(player, "is_in_combat") == true
        or self._blackboard:get("player.in_combat", false) == true
    local target_in_combat = safe_method(target, "is_in_combat") == true

    if pull_profile.pull_spell_id then
        -- Do not advance to combat state until pull has actually engaged combat.
        if not player_in_combat and not target_in_combat then
            return true, nil
        end
    end

    self._pull_sent = true
    self._state = "combat"
    self:_reset_pull_navigation()
    self:_reset_combat_navigation()
    return true, nil
end

---@return boolean
---@return string|nil
function CombatService:update()
    if self._state == "idle" then
        return true, nil
    end

    local now = (core and core.time and core.time()) or 0
    local timeout = tonumber(self._cfg.combat_timeout) or 30.0

    local target = self._active_target
    if not target then
        local ok_get, resolved = pcall(self._targeting.get_target, self._targeting)
        if ok_get then
            target = resolved
        end
        self._active_target = target
    end

    if not target then
        return self:_fail_and_reset(ErrorCodes.TARGET_LOST, now, nil)
    end

    target = self:_maybe_switch_to_attacker(target, now)

    local target_dead = safe_method(target, "is_dead")
    if target_dead == true then
        self._blackboard:set("loot.pending_target", target)
        self._event_bus:emit(Events.KILL_CONFIRMED, {
            timestamp = now,
            target_name = safe_target_name(target),
        })
        self:reset()
        return true, nil
    end

    if target_dead == nil then
        return self:_fail_and_reset(ErrorCodes.TARGET_LOST, now, target)
    end

    if not self:_target_valid(target) then
        return self:_fail_and_reset(ErrorCodes.TARGET_LOST, now, target)
    end

    if now - self._started_at > timeout then
        return self:_fail_and_reset(ErrorCodes.COMBAT_TIMEOUT, now, target)
    end

    if self._state == "pull" then
        local ok, err = self:_execute_pull(target)
        if not ok then
            return self:_fail_and_reset(err or ErrorCodes.PULL_FAILED, now, target)
        end
        return true, nil
    end

    if self._state == "combat" then
        local distance = self:_distance_to_target(target)
        self:_apply_combat_chase(target, now, distance)
        self:_maintain_combat_facing(target, now, distance)
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            return self:_fail_and_reset(ErrorCodes.ROTATION_UNAVAILABLE, now, target)
        end
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            return self:_fail_and_reset(err, now, target)
        end
        return true, nil
    end

    return true, nil
end

return CombatService
