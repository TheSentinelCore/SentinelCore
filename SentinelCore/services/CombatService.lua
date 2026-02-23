local Helpers = require("lib/Helpers")
local Events = require("events/Events")
local ErrorCodes = require("events/ErrorCodes")

local OBJECT_UNWRAP_KEYS = {
    "object",
    "raw_object",
    "game_object",
}

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
---@param value number
---@param min_value number
---@param max_value number
---@return number
local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
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
---@param unit game_object|nil
---@return number|nil
local function resolve_unit_health_pct(unit)
    if not unit then
        return nil
    end

    local current = tonumber(safe_method(unit, "get_health"))
    local maximum = tonumber(safe_method(unit, "get_max_health"))
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
---@param value any
---@return any
local function unwrap_game_object(value)
    if type(value) ~= "table" then
        return value
    end
    for i = 1, #OBJECT_UNWRAP_KEYS do
        local candidate = rawget(value, OBJECT_UNWRAP_KEYS[i])
        if candidate ~= nil then
            return candidate
        end
    end
    return value
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
---@field private _pull_in_range_since number
---@field private _pull_auto_attack_last_at number
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
    o._pull_in_range_since = 0
    o._pull_auto_attack_last_at = 0
    o._combat_nav_last_dest = nil
    o._combat_nav_last_move_at = 0
    o._combat_nav_last_repath_at = 0
    o._combat_nav_repath_pending = false
    o._combat_chasing = false
    o._combat_face_last_at = 0
    o._combat_face_last_target_pos = nil
    o._last_error = nil
    o._combat_target_last_health_pct = nil
    o._combat_target_was_in_combat = false
    o._los_check_at = 0
    o._los_blocked = false
    o:_set_state("idle")
    return o
end

---@return boolean
function CombatService:is_active()
    return self._state == "pull" or self._state == "combat"
end

---@private
---@param value string
function CombatService:_set_state(value)
    self._state = tostring(value or "idle")
    self._blackboard:set("combat.state", self._state)
end

---@private
---@param pull_profile table|nil
---@return number
function CombatService:_resolve_pull_melee_range(pull_profile)
    local from_profile = tonumber(pull_profile and pull_profile.melee_engage_range)
    if from_profile and from_profile > 0 then
        return from_profile
    end
    local movement = self:_resolve_movement_profile()
    local chase_range = tonumber(movement and movement.combat_chase_range)
    if chase_range and chase_range > 0 then
        return chase_range
    end
    return 5.5
end

---@private
---@param pull_profile table|nil
---@param melee_range number
---@return number
function CombatService:_resolve_pull_auto_attack_commit_range(pull_profile, melee_range)
    local profile_value = tonumber(pull_profile and pull_profile.auto_attack_commit_range)
    local cfg_value = tonumber(self._cfg.pull_auto_attack_commit_range)
    local commit_range = profile_value or cfg_value
    if commit_range == nil or commit_range <= 0 then
        commit_range = math.max(3.5, (tonumber(melee_range) or 5.5) - 1.0)
    end

    local max_commit = tonumber(melee_range) or 5.5
    commit_range = clamp(commit_range, 1.5, max_commit)
    return commit_range
end

---@private
---@param target game_object|nil
---@param now number
---@return boolean
function CombatService:_try_start_auto_attack(target, now)
    if not target then
        return false
    end

    local repeat_cooldown = tonumber(self._cfg.pull_auto_attack_repeat_cooldown) or 0.35
    if repeat_cooldown < 0 then
        repeat_cooldown = 0
    end
    if (now - (tonumber(self._pull_auto_attack_last_at) or 0)) < repeat_cooldown then
        return false
    end
    self._pull_auto_attack_last_at = now

    if not core or not core.input then
        return false
    end

    if type(core.input.set_target) == "function" then
        pcall(core.input.set_target, target)
    end

    local start_methods = {
        "start_auto_attack",
        "start_attack",
        "attack_target",
        "attack",
    }
    for i = 1, #start_methods do
        local fn = core.input[start_methods[i]]
        if type(fn) == "function" then
            local ok, result = pcall(fn, target)
            if ok and result ~= false then
                return true
            end
        end
    end

    -- WoW "Attack" spell id fallback for runtimes that expose only cast APIs.
    if type(core.input.cast_target_spell) == "function" then
        local ok, result = pcall(core.input.cast_target_spell, 6603, target)
        if ok and result ~= false then
            return true
        end
    end

    return false
end

---@private
---@param value number|nil
---@param default number
---@return number
function CombatService:_read_ratio_metric(value, default)
    local n = tonumber(value)
    if n == nil then
        return default
    end
    if n < 0 then
        n = 0
    end
    return n
end

---@private
---@param player game_object|nil
---@return number|nil
function CombatService:_resolve_player_mana_pct(player)
    local mana_pct = resolve_unit_mana_pct(player)
    if mana_pct ~= nil then
        return mana_pct
    end

    local current = tonumber(self._blackboard:get("player.mana", 0))
    local maximum = tonumber(self._blackboard:get("player.max_mana", 0))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    return nil
end

---@private
---@param player game_object|nil
---@return number|nil
function CombatService:_resolve_player_health_pct(player)
    local health_pct = resolve_unit_health_pct(player)
    if health_pct ~= nil then
        return health_pct
    end

    local current = tonumber(self._blackboard:get("player.health", 0))
    local maximum = tonumber(self._blackboard:get("player.max_health", 0))
    if current ~= nil and maximum ~= nil and maximum > 0 then
        return normalize_pct(current / maximum)
    end

    return nil
end

---@private
---@param defensive boolean
---@return table
function CombatService:_resolve_recovery_governor(defensive)
    local base_mana_threshold = tonumber(self._cfg.min_pull_mana_pct) or 0
    local base_health_threshold = tonumber(self._cfg.min_pull_health_pct) or 0
    local player = self._blackboard:get("player.object")
    local mana_pct = self:_resolve_player_mana_pct(player)
    local health_pct = self:_resolve_player_health_pct(player)

    local deaths_per_hour = self:_read_ratio_metric(self._blackboard:get("telemetry.rates.deaths_per_hour", 0), 0)
    local idle_full_resource_pct = self:_read_ratio_metric(self._blackboard:get("telemetry.rates.idle_full_resource_pct", 0), 0)

    local death_low = tonumber(self._cfg.recovery_deaths_per_hour_low) or 0.20
    local death_high = tonumber(self._cfg.recovery_deaths_per_hour_high) or 1.50
    if death_high <= death_low then
        death_high = death_low + 0.01
    end
    local death_t = clamp((deaths_per_hour - death_low) / (death_high - death_low), 0.0, 1.0)

    local idle_relax_start = tonumber(self._cfg.recovery_idle_relax_start_pct) or 0.18
    local idle_relax_full = tonumber(self._cfg.recovery_idle_relax_full_pct) or 0.35
    if idle_relax_full <= idle_relax_start then
        idle_relax_full = idle_relax_start + 0.01
    end
    local idle_t = clamp((idle_full_resource_pct - idle_relax_start) / (idle_relax_full - idle_relax_start), 0.0, 1.0)

    local mana_bonus = death_t * (tonumber(self._cfg.recovery_mana_bonus_max) or 0.20)
    local health_bonus = death_t * (tonumber(self._cfg.recovery_health_bonus_max) or 0.10)
    local mana_relief = idle_t * (tonumber(self._cfg.recovery_idle_mana_relief_max) or 0.06)
    local health_relief = idle_t * (tonumber(self._cfg.recovery_idle_health_relief_max) or 0.04)

    local mana_threshold = base_mana_threshold + mana_bonus - mana_relief
    local health_threshold = base_health_threshold + health_bonus - health_relief

    local mana_floor = tonumber(self._cfg.recovery_mana_floor_pct) or 0
    local mana_ceiling = tonumber(self._cfg.recovery_mana_ceiling_pct) or 0.65
    local health_floor = tonumber(self._cfg.recovery_health_floor_pct) or 0
    local health_ceiling = tonumber(self._cfg.recovery_health_ceiling_pct) or 0.95
    mana_threshold = clamp(mana_threshold, mana_floor, mana_ceiling)
    health_threshold = clamp(health_threshold, health_floor, health_ceiling)

    local hold_for_mana = defensive ~= true
        and base_mana_threshold > 0
        and mana_pct ~= nil
        and mana_pct < mana_threshold
    local hold_for_health = defensive ~= true
        and base_health_threshold > 0
        and health_pct ~= nil
        and health_pct < health_threshold

    self._blackboard:set("combat.recovery_governor.mana_threshold", mana_threshold)
    self._blackboard:set("combat.recovery_governor.health_threshold", health_threshold)
    self._blackboard:set("combat.recovery_governor.deaths_per_hour", deaths_per_hour)
    self._blackboard:set("combat.recovery_governor.idle_full_resource_pct", idle_full_resource_pct)
    self._blackboard:set("combat.recovery_governor.hold_for_mana", hold_for_mana)
    self._blackboard:set("combat.recovery_governor.hold_for_health", hold_for_health)
    self._blackboard:set("combat.recovery_governor.hold", hold_for_mana or hold_for_health)

    return {
        hold = hold_for_mana or hold_for_health,
        hold_for_mana = hold_for_mana,
        hold_for_health = hold_for_health,
        mana_pct = mana_pct,
        health_pct = health_pct,
        mana_threshold = mana_threshold,
        health_threshold = health_threshold,
        deaths_per_hour = deaths_per_hour,
        idle_full_resource_pct = idle_full_resource_pct,
    }
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
    local governor = nil
    if not should_run and self._rotation.should_hold_maintenance then
        local ok_hold, hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
        if ok_hold and hold == true then
            should_run = true
        end
    end
    if not should_run then
        governor = self:_resolve_recovery_governor(false)
        if governor.hold == true then
            should_run = true
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
    local hold = false
    if self._rotation and self._rotation.should_hold_maintenance then
        local ok, provider_hold = pcall(self._rotation.should_hold_maintenance, self._rotation)
        hold = ok and provider_hold == true
    end

    if not hold then
        local governor = self:_resolve_recovery_governor(false)
        hold = governor.hold == true
    end
    if not hold then
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
    self._pull_in_range_since = 0
    self._pull_auto_attack_last_at = 0
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
---@return table|nil
function CombatService:_resolve_chase_move_opts()
    local lateral_gate = tonumber(self._cfg.chase_destination_lateral_gate)
    local vertical_gate = tonumber(self._cfg.chase_destination_vertical_gate)
    if (lateral_gate == nil or lateral_gate <= 0) and (vertical_gate == nil or vertical_gate <= 0) then
        return nil
    end

    local opts = {}
    if lateral_gate and lateral_gate > 0 then
        opts.destination_lateral_gate = lateral_gate
    end
    if vertical_gate and vertical_gate > 0 then
        opts.destination_vertical_gate = vertical_gate
    end
    return opts
end

---@private
---@return boolean|nil
---@return boolean|nil
---@return boolean
function CombatService:_resolve_nav_motion_state()
    local moving = nil
    local awaiting = nil

    if self._nav and type(self._nav.is_moving) == "function" then
        local ok_moving, value = pcall(self._nav.is_moving, self._nav)
        if ok_moving then
            moving = value == true
        end
    end

    if self._nav and type(self._nav.get_full_state) == "function" then
        local ok_state, full_state = pcall(self._nav.get_full_state, self._nav)
        if ok_state and type(full_state) == "string" then
            awaiting = string.find(full_state, "awaiting_path", 1, true) ~= nil
        end
    end

    return moving, awaiting, moving ~= nil or awaiting ~= nil
end

---@private
---@param target game_object|nil
---@return number
function CombatService:_resolve_enemy_count(target)
    local player = self._blackboard:get("player.object")
    if not player then
        return target and 1 or 0
    end

    if player.get_enemies_in_range then
        local ok_enemies, enemies = pcall(player.get_enemies_in_range, player, 30)
        if ok_enemies and type(enemies) == "table" then
            local fast_count = 0
            for i = 1, #enemies do
                local enemy = enemies[i]
                if safe_method(enemy, "is_valid") == true
                    and safe_method(enemy, "is_dead") ~= true then
                    fast_count = fast_count + 1
                end
            end
            if fast_count > 0 then
                return fast_count
            end
        end
    end

    local count = 0
    local seen = {}
    local function add_unit(unit)
        if not unit then
            return
        end
        if safe_method(unit, "is_valid") ~= true then
            return
        end
        if safe_method(unit, "is_dead") == true or safe_method(unit, "is_ghost") == true then
            return
        end

        local guid = tonumber(safe_method(unit, "get_guid"))
            or tonumber(safe_method(unit, "get_object_guid"))
        local key = guid and guid > 0 and ("guid:" .. tostring(guid)) or tostring(unit)
        if seen[key] then
            return
        end
        seen[key] = true
        count = count + 1
    end

    add_unit(target)

    if core and core.object_manager and core.object_manager.get_visible_objects then
        local ok_objects, objects = pcall(core.object_manager.get_visible_objects)
        if ok_objects and type(objects) == "table" then
            for i = 1, #objects do
                local candidate = unwrap_game_object(objects[i])
                if candidate and not is_same_unit(candidate, target) then
                    local candidate_in_combat = safe_method(candidate, "is_in_combat") == true
                    if candidate_in_combat and is_defensive_target(candidate, player) then
                        add_unit(candidate)
                    end
                end
            end
        end
    end

    if count <= 0 and target then
        return 1
    end
    return count
end

---@private
---@param target game_object|nil
function CombatService:_sync_enemy_count(target)
    local count = self:_resolve_enemy_count(target)
    self._blackboard:set("combat.enemy_count", count)
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
    local mode = "move_to"
    local prefer_soft_repath = reason == "target_shift"
    local used_soft_repath = false

    if prefer_soft_repath
        and self._nav
        and type(self._nav.soft_repath) == "function"
        and self._pull_nav_repath_pending ~= true then
        self._pull_nav_repath_pending = true
        local ok_soft, started = pcall(
            self._nav.soft_repath,
            self._nav,
            destination,
            function()
                self._pull_nav_repath_pending = false
            end,
            self:_resolve_chase_move_opts()
        )
        if ok_soft and started == true then
            used_soft_repath = true
            mode = "soft_repath"
            self._pull_nav_last_repath_at = now
        else
            self._pull_nav_repath_pending = false
        end
    end

    if not used_soft_repath and self._nav and self._nav.move_to then
        self._nav:move_to(destination, nil, self:_resolve_chase_move_opts())
        self._pull_nav_repath_pending = false
    end

    self._event_bus:emit(Events.COMBAT_CHASE_UPDATE, {
        timestamp = now,
        phase = "pull",
        reason = tostring(reason or "refresh"),
        mode = mode,
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
    local repath_cooldown = tonumber(self._cfg.pull_chase_repath_cooldown) or math.max(0.20, move_to_cooldown * 0.5)
    local refresh_cooldown = tonumber(self._cfg.pull_chase_refresh_cooldown) or (move_to_cooldown * 3.0)
    local since_last_move = now - (tonumber(self._pull_nav_last_move_at) or 0)
    local since_last_repath = now - (tonumber(self._pull_nav_last_repath_at) or 0)
    local repath_pending_timeout = math.max(1.5, repath_cooldown * 4.0)
    if self._pull_nav_repath_pending == true and since_last_repath >= repath_pending_timeout then
        self._pull_nav_repath_pending = false
    end
    local moving, awaiting, state_known = self:_resolve_nav_motion_state()
    local can_soft_repath = self._nav
        and type(self._nav.soft_repath) == "function"
        and moving == true
        and awaiting ~= true
    local nav_stalled = state_known ~= true or (moving == false and awaiting ~= true)
    local should_issue = false
    local issue_reason = "refresh"

    if self._pull_nav_last_dest == nil then
        should_issue = true
        issue_reason = "initial"
    elseif destination_changed then
        if can_soft_repath
            and self._pull_nav_repath_pending ~= true
            and since_last_repath >= repath_cooldown then
            should_issue = true
            issue_reason = "target_shift"
        elseif not can_soft_repath
            and nav_stalled
            and since_last_move >= move_to_cooldown then
            should_issue = true
            issue_reason = "target_shift"
        end
    elseif not destination_changed and since_last_move >= refresh_cooldown and nav_stalled then
        -- Sparse keepalive refresh so moving-target chase can recover from stalled nav.
        should_issue = true
        issue_reason = "refresh"
    end

    if should_issue then
        self:_issue_pull_move_to(target_pos, now, issue_reason)
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
    local mode = "move_to"
    local prefer_soft_repath = reason == "target_shift"
    local used_soft_repath = false

    if prefer_soft_repath
        and self._nav
        and type(self._nav.soft_repath) == "function"
        and self._combat_nav_repath_pending ~= true then
        self._combat_nav_repath_pending = true
        local ok_soft, started = pcall(
            self._nav.soft_repath,
            self._nav,
            destination,
            function()
                self._combat_nav_repath_pending = false
            end,
            self:_resolve_chase_move_opts()
        )
        if ok_soft and started == true then
            used_soft_repath = true
            mode = "soft_repath"
            self._combat_nav_last_repath_at = now
        else
            self._combat_nav_repath_pending = false
        end
    end

    if not used_soft_repath and self._nav and self._nav.move_to then
        self._nav:move_to(destination, nil, self:_resolve_chase_move_opts())
        self._combat_nav_repath_pending = false
    end

    self._event_bus:emit(Events.COMBAT_CHASE_UPDATE, {
        timestamp = now,
        phase = "combat",
        reason = tostring(reason or "refresh"),
        mode = mode,
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
    local repath_cooldown = tonumber(self._cfg.combat_chase_repath_cooldown) or math.max(0.20, move_to_cooldown * 0.5)
    local refresh_cooldown = tonumber(self._cfg.combat_chase_refresh_cooldown) or (move_to_cooldown * 3.0)
    local since_last_move = now - (tonumber(self._combat_nav_last_move_at) or 0)
    local since_last_repath = now - (tonumber(self._combat_nav_last_repath_at) or 0)
    local repath_pending_timeout = math.max(1.5, repath_cooldown * 4.0)
    if self._combat_nav_repath_pending == true and since_last_repath >= repath_pending_timeout then
        self._combat_nav_repath_pending = false
    end
    local moving, awaiting, state_known = self:_resolve_nav_motion_state()
    local can_soft_repath = self._nav
        and type(self._nav.soft_repath) == "function"
        and moving == true
        and awaiting ~= true
    local nav_stalled = state_known ~= true or (moving == false and awaiting ~= true)
    local should_issue = false
    local issue_reason = "refresh"

    if self._combat_nav_last_dest == nil then
        should_issue = true
        issue_reason = "initial"
    elseif destination_changed then
        if can_soft_repath
            and self._combat_nav_repath_pending ~= true
            and since_last_repath >= repath_cooldown then
            should_issue = true
            issue_reason = "target_shift"
        elseif not can_soft_repath
            and nav_stalled
            and since_last_move >= move_to_cooldown then
            should_issue = true
            issue_reason = "target_shift"
        end
    elseif not destination_changed and since_last_move >= refresh_cooldown and nav_stalled then
        -- Sparse keepalive refresh so moving-target chase can recover from stalled nav.
        should_issue = true
        issue_reason = "refresh"
    end

    if should_issue then
        self:_issue_combat_move_to(target_pos, now, issue_reason)
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
    elseif reason == "TARGET_EVADED" then
        ttl = tonumber(self._cfg.target_memory_ttl_target_evaded) or 8.0
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
function CombatService:_update_los_state(target, now)
    local los_interval = tonumber(self._cfg.los_check_interval) or 0.50
    if (now - self._los_check_at) < los_interval then
        return
    end
    self._los_check_at = now

    if not core or not core.graphics or type(core.graphics.is_line_of_sight) ~= "function" then
        self._los_blocked = false
        return
    end

    local player = self._blackboard:get("player.object")
    if not player then
        self._los_blocked = false
        return
    end

    local ok, has_los = pcall(core.graphics.is_line_of_sight, player, target)
    if ok then
        self._los_blocked = (has_los ~= true)
    else
        self._los_blocked = false
    end
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

    -- Don't issue movement commands while casting/channelling (prevents interrupting
    -- Drain Life, Drain Soul, Shadow Bolt, etc.)
    local player = self._blackboard:get("player.object")
    if safe_method(player, "is_casting_spell") == true
        or safe_method(player, "is_channelling_spell") == true then
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

    local ok_facing, already_facing = pcall(player.is_looking_at_unit, player, target)
    if ok_facing and already_facing == true then
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
        self:_set_state("combat")
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

    local player = self._blackboard:get("player.object")
    local defensive = is_defensive_target(target, player)
    local governor = self:_resolve_recovery_governor(defensive)
    if governor.hold == true then
        if self._nav and self._nav.stop then
            pcall(self._nav.stop, self._nav)
        end
        return false, ErrorCodes.MAINTENANCE_REQUIRED
    end

    local now = (core and core.time and core.time()) or 0
    self._active_target = target
    self._blackboard:set("combat.target", target)
    self:_sync_enemy_count(target)
    self:_set_state("pull")
    self._started_at = now
    self._pull_started_at = now
    self._pull_sent = false
    self:_reset_pull_navigation()
    self:_reset_combat_navigation()
    self._last_error = nil

    -- Cancel eating/drinking so the pull cast isn't blocked by the food/water buff
    if core and core.input and type(core.input.cancel_spells) == "function" then
        pcall(core.input.cancel_spells)
    end

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
    self:_set_state("idle")
    self._active_target = nil
    self._pull_sent = false
    self:_reset_pull_navigation()
    self:_reset_combat_navigation()
    self._blackboard:clear("combat.target")
    self._blackboard:set("combat.enemy_count", 0)
    self._combat_target_last_health_pct = nil
    self._combat_target_was_in_combat = false
    self._los_check_at = 0
    self._los_blocked = false
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
    local engage_padding = tonumber(self._cfg.pull_engage_range_padding) or 0.35
    local engage_range = math.max(1.0, pull_range - math.max(0, engage_padding))
    local distance = self:_distance_to_target(target)

    if distance > engage_range then
        self._pull_in_range_since = 0
        local target_pos = safe_method(target, "get_position")
        if not target_pos then
            return false, ErrorCodes.TARGET_LOST
        end
        self:_update_pull_navigation(target_pos, now)

        -- Let pull pipeline pre-cast setup actions while approaching (e.g. Seal).
        local should_tick_approach = pull_profile.pull_spell_id ~= nil
            or pull_profile.tick_rotation_while_approaching == true
        if should_tick_approach then
            local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
            if not ok_call then
                return false, ErrorCodes.ROTATION_UNAVAILABLE
            end
            if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED and err ~= ErrorCodes.TARGET_NOT_FOUND then
                return false, err
            end
        end
        return true, nil
    end

    local boundary_band = tonumber(self._cfg.pull_in_range_stability_band) or 1.25
    local stability_window = tonumber(self._cfg.pull_in_range_stability_window) or 0.20
    local near_boundary = distance >= math.max(0, engage_range - math.max(0, boundary_band))
    if near_boundary and stability_window > 0 then
        if self._pull_in_range_since <= 0 then
            self._pull_in_range_since = now
            return true, nil
        end
        if (now - self._pull_in_range_since) < stability_window then
            return true, nil
        end
    else
        self._pull_in_range_since = now
    end

    if core and core.input and core.input.set_target then
        pcall(core.input.set_target, target)
    end

    local target_pos_for_face = safe_method(target, "get_position")
    if target_pos_for_face and core and core.input and type(core.input.look_at) == "function" then
        pcall(core.input.look_at, target_pos_for_face)
    end

    if pull_profile.pull_spell_id then
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            return false, ErrorCodes.ROTATION_UNAVAILABLE
        end
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED then
            return false, err
        end
    elseif pull_profile.tick_rotation_in_pull == true then
        local ok_call, ok, err = pcall(self._rotation.tick_once, self._rotation)
        if not ok_call then
            return false, ErrorCodes.ROTATION_UNAVAILABLE
        end
        if not ok and err ~= ErrorCodes.CAST_GUARD_BLOCKED and err ~= ErrorCodes.TARGET_NOT_FOUND then
            return false, err
        end
    end

    local player = self._blackboard:get("player.object")
    local player_in_combat = safe_method(player, "is_in_combat") == true
        or self._blackboard:get("player.in_combat", false) == true
    local target_in_combat = safe_method(target, "is_in_combat") == true

    if not player_in_combat and not target_in_combat
        and pull_profile.disable_auto_attack ~= true then
        local melee_range = self:_resolve_pull_melee_range(pull_profile)
        local commit_range = self:_resolve_pull_auto_attack_commit_range(pull_profile, melee_range)
        local trigger_range = tonumber(self._cfg.pull_auto_attack_trigger_range) or melee_range
        trigger_range = math.max(trigger_range, commit_range)

        local target_pos = safe_method(target, "get_position")
        if not target_pos then
            return false, ErrorCodes.TARGET_LOST
        end

        if distance > commit_range then
            if distance <= trigger_range then
                self:_try_start_auto_attack(target, now)
            end
            self:_update_pull_navigation(target_pos, now)
            return true, nil
        end

        self:_try_start_auto_attack(target, now)
    end

    if self._nav and self._nav.stop then
        pcall(self._nav.stop, self._nav)
    end

    self._pull_sent = true
    self:_set_state("combat")
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
    self:_sync_enemy_count(target)

    -- Evade/leash detection
    local target_hp = resolve_unit_health_pct(target)
    local target_in_combat_now = safe_method(target, "is_in_combat") == true
    if target_hp ~= nil and self._combat_target_last_health_pct ~= nil then
        if target_hp - self._combat_target_last_health_pct > 0.15 then
            return self:_fail_and_reset("TARGET_EVADED", now, target)
        end
    end
    if self._combat_target_was_in_combat and not target_in_combat_now then
        if safe_method(target, "is_dead") ~= true then
            return self:_fail_and_reset("TARGET_EVADED", now, target)
        end
    end
    if target_hp ~= nil then
        self._combat_target_last_health_pct = target_hp
    end
    if target_in_combat_now then
        self._combat_target_was_in_combat = true
    end

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
        self:_update_los_state(target, now)
        if self._los_blocked then
            local los_target_pos = safe_method(target, "get_position")
            if los_target_pos then
                self:_update_combat_navigation(los_target_pos, now)
            end
        else
            self:_apply_combat_chase(target, now, distance)
        end
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
