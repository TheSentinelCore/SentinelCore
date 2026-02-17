local Version = require("version")
local unit_helper = require("common/utility/unit_helper")
local vec3 = require("common/geometry/vector_3")
local BlackspotManager = require("modules/BlackspotManager")
local RotationManager = require("modules/RotationManager")

local GrindBuddy = {}
GrindBuddy.__index = GrindBuddy

GrindBuddy.NAME = "GrindBuddy"
GrindBuddy.VERSION = Version.to_string()

local _instance = nil

local function copy_vec3(v)
    return vec3.new(v.x, v.y, v.z)
end

local function safe_state_name(state)
    if state == nil then
        return "unknown"
    end
    return tostring(state)
end

local function call_method(obj, name, ...)
    if not obj then
        return nil
    end
    local fn = obj[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil
    end
    return result
end

local function now_time()
    return core.time()
end

local function current_map_id()
    if core.get_map_id then
        return core.get_map_id()
    end
    if core.game_ui and core.game_ui.get_current_map_id then
        return core.game_ui.get_current_map_id()
    end
    return nil
end

function GrindBuddy:get_instance()
    if not _instance then
        _instance = setmetatable({
            _initialized = false,
            _running = false,
            _state = "idle",
            _status = "Idle",
            _last_tick = 0,
            _tick_interval = 0.10,
            _last_scan = 0,
            _scan_interval = 0.40,
            _movement = nil,
            _nav_error = nil,
            _move_inflight = false,
            _move_started_at = 0,
            _move_timeout = 20.0,
            _waypoints = {},
            _waypoint_index = 1,
            _route_radius = 35.0,
            _route_radius_min = 35.0,
            _route_radius_max = 140.0,
            _route_expand_step = 20.0,
            _route_expand_interval = 12.0,
            _last_target_seen_at = 0,
            _last_route_expand_at = 0,
            _anchor = nil,

            -- Targeting and combat flow
            _target = nil,
            _target_guid = nil,
            _target_acquired_at = 0,
            _last_pull_attempt = 0,
            _pull_cooldown = 1.5,
            _target_timeout = 22.0,
            _pull_range = 28.0,
            _chase_stop_range = 24.0,
            _scan_radius = 300.0,
            _stickiness_bonus = 8.0,
            _auto_mount_enabled = true,
            _mount_threshold = 42.0,
            _mount_index = 1,
            _last_mount_attempt = 0,
            _mount_attempt_interval = 2.0,
            _last_dismount_attempt = 0,
            _dismount_attempt_interval = 1.0,
            _min_target_level_delta = 0,
            _max_target_level_delta = 2,
            _ignore_players = true,
            _only_hostile_targets = true,
            _prefer_player_target = true,
            _combat_retarget_interval = 0.35,
            _last_combat_retarget = 0,
            _loot_enabled = true,
            _loot_range = 7.0,
            _loot_attempt_interval = 0.8,
            _last_loot_attempt = 0,

            -- Blacklist
            _blacklist_guid = {},
            _blacklist_zones = {},
            _blacklist_ttl = 120.0,
            _zone_blacklist_ttl = 90.0,
            _zone_blacklist_radius = 8.0,

            -- Combat bookkeeping
            _last_combat_seen = 0,
            _blackspots = nil,
            _blackspot_radius = 10.0,
            _blackspot_ttl = 0.0,
            _rotation = nil,
        }, GrindBuddy)
    end
    return _instance
end

function GrindBuddy:_set_state(next_state)
    local instance = self:get_instance()
    local prev_state = instance._state
    if prev_state ~= next_state then
        instance._state = next_state
        core.log(string.format("[GrindBuddy] State: %s -> %s", safe_state_name(prev_state), safe_state_name(next_state)))
    end
end

function GrindBuddy:_set_status(text)
    local instance = self:get_instance()
    instance._status = text or ""
end

function GrindBuddy:_ensure_nav_movement()
    local instance = self:get_instance()
    if instance._movement then
        return true
    end

    local navlib = _G.NavLib
    if navlib then
        local facade = nil
        if navlib.facade then
            facade = navlib.facade
        elseif type(navlib.create) == "function" then
            local ok, created = pcall(navlib.create)
            if ok then
                facade = created
            end
        end

        if facade and facade.movement then
            instance._movement = facade.movement
            instance._nav_error = nil
            return true
        end
    end

    instance._nav_error = "NavLib facade unavailable (waiting for NavLib load)."
    return false
end

function GrindBuddy:_build_default_route(local_player)
    local instance = self:get_instance()
    local pos = local_player:get_position()
    instance._anchor = copy_vec3(pos)

    local r = instance._route_radius
    local points = {}
    for i = 0, 7 do
        local angle = (math.pi * 0.25) * i
        points[#points + 1] = vec3.new(
            pos.x + (math.cos(angle) * r),
            pos.y + (math.sin(angle) * r),
            pos.z
        )
    end

    instance._waypoints = points
    instance._waypoint_index = 1
end

function GrindBuddy:_maybe_expand_search(local_player, now)
    local instance = self:get_instance()
    if instance._target then
        return
    end

    local movement = instance._movement
    local moving = movement and movement.is_moving and movement:is_moving() or false
    if moving or instance._move_inflight then
        return
    end

    if (now - instance._last_target_seen_at) < instance._route_expand_interval then
        return
    end
    if (now - instance._last_route_expand_at) < instance._route_expand_interval then
        return
    end
    if instance._route_radius >= instance._route_radius_max then
        return
    end

    instance._route_radius = math.min(instance._route_radius_max, instance._route_radius + instance._route_expand_step)
    instance._last_route_expand_at = now
    instance._last_target_seen_at = now
    self:_build_default_route(local_player)

    core.log(string.format("[GrindBuddy] Expanding patrol radius to %.0f yd", instance._route_radius))
    self:_set_status(string.format("No enemies, expanding search (%.0f yd)", instance._route_radius))
end

function GrindBuddy:_advance_waypoint()
    local instance = self:get_instance()
    if #instance._waypoints == 0 then
        return
    end
    instance._waypoint_index = instance._waypoint_index + 1
    if instance._waypoint_index > #instance._waypoints then
        instance._waypoint_index = 1
    end
end

function GrindBuddy:_current_waypoint()
    local instance = self:get_instance()
    return instance._waypoints[instance._waypoint_index]
end

function GrindBuddy:_distance_to(pos_a, pos_b)
    if not pos_a or not pos_b then
        return math.huge
    end
    return pos_a:dist_to(pos_b)
end

function GrindBuddy:_is_player_mounted(local_player)
    if not local_player then
        return false
    end
    return call_method(local_player, "is_mounted") == true
end

function GrindBuddy:_maybe_dismount(local_player, reason)
    local instance = self:get_instance()
    if not self:_is_player_mounted(local_player) then
        return false
    end
    if not core.input or not core.input.dismount then
        return false
    end

    local now = now_time()
    if (now - instance._last_dismount_attempt) < instance._dismount_attempt_interval then
        return true
    end

    local movement = instance._movement
    local moving = movement and movement.is_moving and movement:is_moving() or false
    if moving and movement.stop then
        movement:stop()
        instance._move_inflight = false
    end

    core.input.dismount()
    instance._last_dismount_attempt = now
    self:_set_status(reason or "Dismounting")
    return true
end

function GrindBuddy:_maybe_mount_for_patrol(local_player, travel_distance)
    local instance = self:get_instance()
    if not instance._auto_mount_enabled then
        return false
    end
    if self:_is_player_mounted(local_player) then
        return false
    end
    if not core.input or not core.input.mount then
        return false
    end
    if call_method(local_player, "is_in_combat") == true then
        return false
    end
    if call_method(local_player, "is_indoors") == true then
        return false
    end
    if call_method(local_player, "is_casting_spell") == true or call_method(local_player, "is_channelling_spell") == true then
        return false
    end
    if travel_distance < instance._mount_threshold then
        return false
    end

    local now = now_time()
    if (now - instance._last_mount_attempt) < instance._mount_attempt_interval then
        return true
    end

    local mount_index = math.max(1, math.floor(instance._mount_index or 1))
    if core.spell_book and core.spell_book.get_mount_count then
        local mount_count = core.spell_book.get_mount_count()
        if type(mount_count) == "number" and mount_count >= 1 then
            if mount_index > mount_count then
                mount_index = mount_count
            end
        end
    end

    local movement = instance._movement
    local moving = movement and movement.is_moving and movement:is_moving() or false
    if moving and movement.stop then
        movement:stop()
        instance._move_inflight = false
    end

    core.input.mount(mount_index)
    instance._last_mount_attempt = now
    self:_set_state("patrol")
    self:_set_status("Mounting for patrol travel")
    return true
end

function GrindBuddy:_cleanup_blacklists(now)
    local instance = self:get_instance()

    for guid, expires_at in pairs(instance._blacklist_guid) do
        if expires_at <= now then
            instance._blacklist_guid[guid] = nil
        end
    end

    local kept = {}
    for _, zone in ipairs(instance._blacklist_zones) do
        if zone.expires_at > now then
            kept[#kept + 1] = zone
        end
    end
    instance._blacklist_zones = kept
end

function GrindBuddy:_is_guid_blacklisted(guid, now)
    local instance = self:get_instance()
    local expires_at = instance._blacklist_guid[guid]
    return expires_at ~= nil and expires_at > now
end

function GrindBuddy:_is_pos_blacklisted(pos)
    local instance = self:get_instance()
    for _, zone in ipairs(instance._blacklist_zones) do
        if zone.pos and self:_distance_to(pos, zone.pos) <= zone.radius then
            return true
        end
    end
    local map_id = current_map_id()
    if instance._blackspots and map_id and instance._blackspots:is_blackspotted(pos, map_id) then
        return true
    end
    return false
end

function GrindBuddy:_blacklist_target(target, reason)
    local instance = self:get_instance()
    local now = now_time()

    local guid = call_method(target, "get_guid")
    local pos = call_method(target, "get_position")

    if guid then
        instance._blacklist_guid[guid] = now + instance._blacklist_ttl
    end

    if pos then
        instance._blacklist_zones[#instance._blacklist_zones + 1] = {
            pos = copy_vec3(pos),
            radius = instance._zone_blacklist_radius,
            expires_at = now + instance._zone_blacklist_ttl,
        }
    end

    core.log(string.format("[GrindBuddy] Blacklisted target (%s)", tostring(reason or "unknown")))
end

function GrindBuddy:_is_target_attackable(target)
    local attackable = call_method(target, "is_attackable")
    if attackable == nil then
        attackable = call_method(target, "can_be_attacked")
    end
    if attackable == nil then
        return true
    end
    return attackable == true
end

function GrindBuddy:_is_target_tapped(target)
    local tapped = call_method(target, "is_tapped")
    if tapped == nil then
        tapped = call_method(target, "is_tagged")
    end
    return tapped == true
end

function GrindBuddy:_is_target_alive(target)
    local dead = call_method(target, "is_dead")
    if dead ~= nil then
        return dead == false
    end
    return true
end

function GrindBuddy:_is_unit_lootable(target)
    if not target then
        return false
    end
    local can_be_looted = call_method(target, "can_be_looted")
    if can_be_looted ~= nil then
        return can_be_looted == true
    end
    local has_loot = call_method(target, "has_loot")
    if has_loot ~= nil then
        return has_loot == true
    end
    return false
end

function GrindBuddy:_set_target(target, now, label)
    local instance = self:get_instance()
    local guid = call_method(target, "get_guid")
    local local_player = core.object_manager.get_local_player()
    local my_pos = local_player and local_player:is_valid() and local_player:get_position() or nil
    local tgt_pos = call_method(target, "get_position")
    local dist = self:_distance_to(my_pos, tgt_pos)

    instance._target = target
    instance._target_guid = guid
    instance._target_acquired_at = now
    instance._last_target_seen_at = now

    self:_set_state("targeting")
    self:_set_status(string.format("%s (dist=%.1f)", label or "Target acquired", dist))
    core.log(string.format("[GrindBuddy] Target acquired guid=%s dist=%.1f", tostring(guid), dist))
end

function GrindBuddy:_find_combat_target(local_player, now)
    local selected = call_method(local_player, "get_target")
    if self:_is_valid_target(local_player, selected, now) then
        return selected
    end

    local instance = self:get_instance()
    local my_pos = local_player:get_position()
    local my_guid = call_method(local_player, "get_guid")
    local enemies = unit_helper:get_enemy_list_around(
        my_pos,
        math.max(instance._scan_radius, 90.0),
        true,
        false,
        false,
        false
    )

    if not enemies or #enemies == 0 then
        return nil
    end

    local best = nil
    local best_score = -math.huge
    for _, enemy in ipairs(enemies) do
        if self:_is_valid_target(local_player, enemy, now) then
            local score = 0
            local pos = call_method(enemy, "get_position")
            score = score - self:_distance_to(my_pos, pos)

            local enemy_target = call_method(enemy, "get_target")
            if enemy_target and my_guid then
                if enemy_target == my_guid then
                    score = score + 120.0
                else
                    local enemy_target_guid = call_method(enemy_target, "get_guid")
                    if enemy_target_guid and enemy_target_guid == my_guid then
                        score = score + 120.0
                    end
                end
            end

            if score > best_score then
                best = enemy
                best_score = score
            end
        end
    end

    return best
end

function GrindBuddy:_try_loot_target(local_player, target, now)
    local instance = self:get_instance()
    if not instance._loot_enabled or not target then
        return false
    end
    if call_method(local_player, "is_in_combat") == true then
        return false
    end
    if self:_is_target_alive(target) then
        return false
    end
    if not self:_is_unit_lootable(target) then
        return false
    end

    local my_pos = local_player:get_position()
    local tgt_pos = call_method(target, "get_position")
    local dist = self:_distance_to(my_pos, tgt_pos)

    if dist > instance._loot_range then
        local movement = instance._movement
        local moving = movement and movement.is_moving and movement:is_moving() or false
        if not moving and not instance._move_inflight and tgt_pos then
            self:_set_state("looting")
            self:_begin_move(tgt_pos, string.format("Moving to loot (%.1f yd)", dist))
        end
        return true
    end

    if (now - instance._last_loot_attempt) < instance._loot_attempt_interval then
        return true
    end
    instance._last_loot_attempt = now

    if tgt_pos and core.input and core.input.look_at then
        core.input.look_at(tgt_pos)
    end
    if core.input then
        if core.input.use_object then
            core.input.use_object(target)
        elseif core.input.interact_with_object then
            core.input.interact_with_object(target)
        elseif core.input.interact_with_unit then
            core.input.interact_with_unit(target)
        end
    end

    self:_set_state("looting")
    self:_set_status("Looting")
    return true
end

function GrindBuddy:_is_target_hostile(local_player, target)
    local local_enemy = call_method(local_player, "is_enemy_with", target)
    if local_enemy ~= nil then
        return local_enemy == true
    end
    local target_enemy = call_method(target, "is_enemy_with", local_player)
    if target_enemy ~= nil then
        return target_enemy == true
    end
    local can_attack = call_method(local_player, "can_attack", target)
    if can_attack ~= nil then
        return can_attack == true
    end
    return false
end

function GrindBuddy:_is_valid_target(local_player, target, now)
    local instance = self:get_instance()
    if not target then
        return false
    end
    if call_method(target, "is_valid") == false then
        return false
    end
    if not self:_is_target_alive(target) then
        return false
    end
    if not self:_is_target_attackable(target) then
        return false
    end
    if self:_is_target_tapped(target) then
        return false
    end
    if instance._ignore_players and call_method(target, "is_player") == true then
        return false
    end
    if instance._only_hostile_targets and not self:_is_target_hostile(local_player, target) then
        return false
    end

    local my_level = call_method(local_player, "get_level")
    local target_level = call_method(target, "get_level")
    if my_level and target_level then
        local delta = target_level - my_level
        if delta < instance._min_target_level_delta then
            return false
        end
        if delta > instance._max_target_level_delta then
            return false
        end
    end

    local guid = call_method(target, "get_guid")
    if guid and self:_is_guid_blacklisted(guid, now) then
        return false
    end

    local pos = call_method(target, "get_position")
    if pos and self:_is_pos_blacklisted(pos) then
        return false
    end

    return true
end

function GrindBuddy:_target_score(local_player, target)
    local instance = self:get_instance()
    local my_pos = local_player:get_position()
    local tgt_pos = call_method(target, "get_position")
    local distance = self:_distance_to(my_pos, tgt_pos)
    local score = 100.0 - distance

    local target_of_target = call_method(target, "get_target")
    local my_guid = call_method(local_player, "get_guid")
    if target_of_target and my_guid then
        if target_of_target == my_guid then
            score = score + 40.0
        else
            local target_guid = call_method(target_of_target, "get_guid")
            if target_guid and target_guid == my_guid then
                score = score + 40.0
            end
        end
    end

    local guid = call_method(target, "get_guid")
    if guid and guid == instance._target_guid then
        score = score + instance._stickiness_bonus
    end

    return score, distance
end

function GrindBuddy:_acquire_target(local_player)
    local instance = self:get_instance()
    local now = now_time()

    if now - instance._last_scan < instance._scan_interval then
        return nil
    end
    instance._last_scan = now

    if instance._prefer_player_target then
        local selected = call_method(local_player, "get_target")
        if self:_is_valid_target(local_player, selected, now) then
            self:_set_target(selected, now, "Using selected target")
            return selected
        end
    end

    local player_pos = local_player:get_position()
    local enemies = unit_helper:get_enemy_list_around(
        player_pos,
        instance._scan_radius,
        true,
        false,
        false,
        false
    )

    if not enemies or #enemies == 0 then
        self:_maybe_expand_search(local_player, now)
        return nil
    end

    local best = nil
    local best_score = -math.huge
    local best_dist = math.huge

    for _, enemy in ipairs(enemies) do
        if self:_is_valid_target(local_player, enemy, now) then
            local score, dist = self:_target_score(local_player, enemy)
            if score > best_score then
                best = enemy
                best_score = score
                best_dist = dist
            end
        end
    end

    if best then
        self:_set_target(best, now, "Target acquired")
        if instance._route_radius > instance._route_radius_min then
            instance._route_radius = instance._route_radius_min
        end
    else
        self:_maybe_expand_search(local_player, now)
    end

    return best
end

function GrindBuddy:_clear_target()
    local instance = self:get_instance()
    instance._target = nil
    instance._target_guid = nil
    instance._target_acquired_at = 0
end

function GrindBuddy:_attempt_pull(target)
    local instance = self:get_instance()
    local now = now_time()
    if now - instance._last_pull_attempt < instance._pull_cooldown then
        return
    end
    instance._last_pull_attempt = now

    local target_pos = call_method(target, "get_position")
    if target_pos and core.input and core.input.look_at then
        core.input.look_at(target_pos)
    end

    if core.input then
        if core.input.interact_with_unit then
            core.input.interact_with_unit(target)
        elseif core.input.use_object then
            core.input.use_object(target)
        elseif core.input.interact_with_object then
            core.input.interact_with_object(target)
        end
    end

    self:_set_state("pulling")
    self:_set_status("Attempting pull")
end

function GrindBuddy:_begin_move(target, status_text)
    local instance = self:get_instance()
    local movement = instance._movement
    if not movement or not target then
        return false
    end

    instance._move_inflight = true
    instance._move_started_at = now_time()
    self:_set_state("moving")
    self:_set_status(status_text or "Moving")

    movement:move_to(target, function(success, reason)
        instance._move_inflight = false
        if not success then
            self:_set_status("Navigation failed: " .. tostring(reason or "unknown"))
            core.log("[GrindBuddy] Navigation failed: " .. tostring(reason or "unknown"))
        end
    end, {
        use_navmesh = true,
    })

    return true
end

function GrindBuddy:_tick_patrol(local_player)
    local instance = self:get_instance()
    local movement = instance._movement

    local moving = movement.is_moving and movement:is_moving() or false
    if moving then
        self:_set_state("patrol")
        self:_set_status("Patrolling")
        return
    end

    if instance._move_inflight then
        return
    end

    local target = self:_current_waypoint()
    if not target then
        return
    end

    if self:_is_pos_blacklisted(target) then
        self:_set_status("Skipping blackspotted waypoint")
        self:_advance_waypoint()
        return
    end

    if local_player and local_player:is_valid() then
        local my_pos = local_player:get_position()
        local travel_distance = self:_distance_to(my_pos, target)
        if self:_maybe_mount_for_patrol(local_player, travel_distance) then
            return
        end
    end

    self:_begin_move(target, string.format("Patrol waypoint %d/%d", instance._waypoint_index, #instance._waypoints))
    self:_advance_waypoint()
end

function GrindBuddy:_tick_target(local_player)
    local instance = self:get_instance()
    local target = instance._target
    local now = now_time()
    local in_combat = call_method(local_player, "is_in_combat") == true
    local mounted = self:_is_player_mounted(local_player)

    if not target then
        return
    end

    if mounted and in_combat then
        if self:_maybe_dismount(local_player, "Dismounting for combat") then
            self:_set_state("combat")
            return
        end
    end

    if not self:_is_target_alive(target) then
        if self:_try_loot_target(local_player, target, now) then
            return
        end

        self:_clear_target()
        if in_combat then
            local retarget = self:_find_combat_target(local_player, now)
            if retarget then
                self:_set_target(retarget, now, "Retarget (combat)")
                target = instance._target
            end
        end

        if not target then
            self:_set_state("patrol")
            self:_set_status("Target down, back to patrol")
            return
        end
    end

    if not self:_is_valid_target(local_player, target, now) then
        if in_combat then
            local retarget = self:_find_combat_target(local_player, now)
            if retarget then
                self:_set_target(retarget, now, "Retarget (combat)")
                target = instance._target
            else
                self:_clear_target()
                self:_set_state("combat")
                self:_set_status("In combat (retargeting)")
                return
            end
        else
            self:_clear_target()
            self:_set_state("patrol")
            self:_set_status("Target invalid, back to patrol")
            return
        end
    end

    if in_combat then
        instance._last_combat_seen = now
        if (now - instance._last_combat_retarget) >= instance._combat_retarget_interval then
            local retarget = self:_find_combat_target(local_player, now)
            local retarget_guid = call_method(retarget, "get_guid")
            local current_guid = call_method(target, "get_guid")
            if retarget and retarget_guid and retarget_guid ~= current_guid then
                self:_set_target(retarget, now, "Retarget (add)")
                target = instance._target
            end
            instance._last_combat_retarget = now
        end

        self:_set_state("combat")
        if instance._rotation then
            instance._rotation:tick(local_player, target)
        end
        self:_set_status("In combat")
        return
    end

    if (now - instance._target_acquired_at) > instance._target_timeout then
        self:_blacklist_target(target, "target timeout")
        self:_clear_target()
        self:_set_state("patrol")
        self:_set_status("Target timed out")
        return
    end

    local my_pos = local_player:get_position()
    local tgt_pos = call_method(target, "get_position")
    local distance = self:_distance_to(my_pos, tgt_pos)

    local movement = instance._movement
    local moving = movement.is_moving and movement:is_moving() or false

    if distance > instance._chase_stop_range then
        if not moving and not instance._move_inflight then
            self:_begin_move(tgt_pos, string.format("Chasing target (%.1f yd)", distance))
        else
            self:_set_state("chasing")
            self:_set_status(string.format("Chasing target (%.1f yd)", distance))
        end
        return
    end

    if moving and movement.stop then
        movement:stop()
        instance._move_inflight = false
    end

    if distance <= instance._pull_range then
        if self:_is_player_mounted(local_player) then
            if self:_maybe_dismount(local_player, "Dismounting to pull target") then
                self:_set_state("pulling")
                return
            end
        end

        local casted = false
        if instance._rotation then
            casted = instance._rotation:tick(local_player, target)
        end
        if not casted then
            self:_attempt_pull(target)
        end
    end
end

function GrindBuddy:initialize()
    local instance = self:get_instance()
    if instance._initialized then
        return true
    end

    if not self:_ensure_nav_movement() then
        core.log_warning("[GrindBuddy] " .. tostring(instance._nav_error))
    end

    if not instance._blackspots then
        instance._blackspots = BlackspotManager:new({
            default_radius = instance._blackspot_radius,
            max_entries = 500,
        })
        instance._blackspots:load()
    end

    if not instance._rotation then
        instance._rotation = RotationManager:new({
            tick_interval = 0.20,
        })
    end

    instance._initialized = true
    core.log(string.format("[GrindBuddy] Initialized v%s", GrindBuddy.VERSION))
    local local_player = core.object_manager.get_local_player()
    if instance._rotation and local_player and local_player:is_valid() then
        instance._rotation:detect_default_profile(local_player)
        core.log("[GrindBuddy] Rotation profile: " .. tostring(instance._rotation:get_active_profile_label()))
    end
    return true
end

function GrindBuddy:start()
    local instance = self:get_instance()
    if not instance._initialized and not self:initialize() then
        return false
    end

    if instance._running then
        return true
    end

    if not self:_ensure_nav_movement() then
        core.log_error("[GrindBuddy] Cannot start: " .. tostring(instance._nav_error))
        return false
    end

    local local_player = core.object_manager.get_local_player()
    if not local_player or not local_player:is_valid() then
        core.log_error("[GrindBuddy] Cannot start: local player unavailable")
        return false
    end

    if #instance._waypoints == 0 then
        instance._route_radius = instance._route_radius_min
        self:_build_default_route(local_player)
    end

    self:_clear_target()
    instance._running = true
    instance._move_inflight = false
    instance._move_started_at = 0
    instance._last_target_seen_at = now_time()
    instance._last_route_expand_at = 0
    instance._last_mount_attempt = 0
    instance._last_dismount_attempt = 0
    self:_set_state("patrol")
    self:_set_status("Patrol started")
    core.log("[GrindBuddy] Started")
    return true
end

function GrindBuddy:stop()
    local instance = self:get_instance()
    if not instance._running then
        return
    end

    if instance._movement and instance._movement.stop then
        instance._movement:stop()
    end

    instance._running = false
    instance._move_inflight = false
    instance._move_started_at = 0
    self:_clear_target()
    self:_set_state("idle")
    self:_set_status("Stopped")
    core.log("[GrindBuddy] Stopped")
end

function GrindBuddy:update()
    local instance = self:get_instance()
    if not instance._running then
        return
    end

    local now = now_time()
    if now - instance._last_tick < instance._tick_interval then
        return
    end
    instance._last_tick = now

    self:_cleanup_blacklists(now)

    local local_player = core.object_manager.get_local_player()
    if not local_player or not local_player:is_valid() then
        self:_set_state("waiting")
        self:_set_status("Waiting for local player")
        return
    end

    if call_method(local_player, "is_dead") == true then
        self:_set_state("waiting")
        self:_set_status("Player dead")
        return
    end

    if not instance._movement then
        self:_ensure_nav_movement()
    end

    local movement = instance._movement
    if not movement then
        self:_set_state("waiting")
        self:_set_status("Waiting for NavLib")
        return
    end

    local moving = movement.is_moving and movement:is_moving() or false
    if moving and instance._move_inflight and (now - instance._move_started_at) > instance._move_timeout then
        -- No local unstuck logic: just cancel this move and continue behavior loop.
        if movement.stop then
            movement:stop()
        end
        instance._move_inflight = false
        local me = core.object_manager.get_local_player()
        local pos = me and me:is_valid() and me:get_position() or nil
        local map_id = current_map_id()
        if instance._blackspots and pos and map_id then
            instance._blackspots:add(pos, map_id, instance._blackspot_radius, "move-timeout", instance._blackspot_ttl)
            self:_set_status("Move timeout, blackspot added")
            core.log("[GrindBuddy] Move timeout, blackspot added")
        else
            self:_set_status("Move timeout, continuing")
            core.log("[GrindBuddy] Move timeout, continuing")
        end
    end

    if instance._target then
        self:_tick_target(local_player)
        return
    end

    self:_acquire_target(local_player)
    if instance._target then
        self:_tick_target(local_player)
        return
    end

    self:_tick_patrol(local_player)
end

function GrindBuddy:is_running()
    return self:get_instance()._running
end

function GrindBuddy:get_state()
    return self:get_instance()._state
end

function GrindBuddy:get_status()
    return self:get_instance()._status
end

function GrindBuddy:get_grind_settings()
    local instance = self:get_instance()
    return {
        scan_radius = instance._scan_radius,
        pull_range = instance._pull_range,
        chase_stop_range = instance._chase_stop_range,
        auto_mount_enabled = instance._auto_mount_enabled,
        mount_threshold = instance._mount_threshold,
        min_target_level_delta = instance._min_target_level_delta,
        max_target_level_delta = instance._max_target_level_delta,
        ignore_players = instance._ignore_players,
        only_hostile_targets = instance._only_hostile_targets,
    }
end

function GrindBuddy:set_grind_settings(settings)
    local instance = self:get_instance()
    if not settings then
        return
    end

    if settings.scan_radius then
        local scan = tonumber(settings.scan_radius) or instance._scan_radius
        instance._scan_radius = math.max(20.0, math.min(300.0, scan))
    end
    if settings.pull_range then
        instance._pull_range = math.max(5.0, tonumber(settings.pull_range) or instance._pull_range)
    end
    if settings.chase_stop_range then
        instance._chase_stop_range = math.max(instance._pull_range, tonumber(settings.chase_stop_range) or instance._chase_stop_range)
    end
    if settings.auto_mount_enabled ~= nil then
        instance._auto_mount_enabled = settings.auto_mount_enabled == true
    end
    if settings.mount_threshold then
        local threshold = tonumber(settings.mount_threshold) or instance._mount_threshold
        instance._mount_threshold = math.max(10.0, math.min(120.0, threshold))
    end
    if settings.mount_index then
        local mount_index = tonumber(settings.mount_index) or instance._mount_index
        instance._mount_index = math.max(1, math.floor(mount_index))
    end
    if settings.min_target_level_delta ~= nil then
        instance._min_target_level_delta = math.floor(tonumber(settings.min_target_level_delta) or instance._min_target_level_delta)
    end
    if settings.max_target_level_delta ~= nil then
        instance._max_target_level_delta = math.floor(tonumber(settings.max_target_level_delta) or instance._max_target_level_delta)
    end
    if instance._max_target_level_delta < instance._min_target_level_delta then
        instance._max_target_level_delta = instance._min_target_level_delta
    end
    if settings.ignore_players ~= nil then
        instance._ignore_players = settings.ignore_players == true
    end
    if settings.only_hostile_targets ~= nil then
        instance._only_hostile_targets = settings.only_hostile_targets == true
    end
    if instance._chase_stop_range < instance._pull_range then
        instance._chase_stop_range = instance._pull_range
    end
end

function GrindBuddy:get_rotation_profiles()
    local instance = self:get_instance()
    if not instance._rotation then
        return {}
    end
    return instance._rotation:get_all_profile_descriptors()
end

function GrindBuddy:set_rotation_profile_index(index)
    local instance = self:get_instance()
    if not instance._rotation then
        return false
    end
    return instance._rotation:set_profile_by_index(index)
end

function GrindBuddy:get_rotation_profile_index()
    local instance = self:get_instance()
    if not instance._rotation then
        return nil
    end
    local active_id = instance._rotation:get_active_profile_id()
    return instance._rotation:get_profile_index_by_id(active_id)
end

function GrindBuddy:set_rotation_auto_select(enabled)
    local instance = self:get_instance()
    if not instance._rotation then
        return
    end
    instance._rotation:set_auto_select(enabled)
end

function GrindBuddy:is_rotation_auto_select()
    local instance = self:get_instance()
    if not instance._rotation then
        return true
    end
    return instance._rotation:is_auto_select_enabled()
end

function GrindBuddy:get_rotation_profile_label()
    local instance = self:get_instance()
    if not instance._rotation then
        return "none"
    end
    return instance._rotation:get_active_profile_label()
end

function GrindBuddy:get_version_info()
    return Version
end

function GrindBuddy:destroy()
    if _instance then
        self:stop()
    end
    _instance = nil
end

return GrindBuddy
