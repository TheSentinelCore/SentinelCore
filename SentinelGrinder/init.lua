local Version = require("version")
local unit_helper = require("common/utility/unit_helper")
local vec3 = require("common/geometry/vector_3")
local BlackspotManager = require("modules/BlackspotManager")
local RotationManager = require("modules/RotationManager")
local GrindProfileManager = require("modules/GrindProfileManager")

local GrindBuddy = {}
GrindBuddy.__index = GrindBuddy

GrindBuddy.NAME = "GrindBuddy"
GrindBuddy.VERSION = Version.to_string()

local _instance = nil
local ROUTE_MODE_CIRCLE = 1
local ROUTE_MODE_PROFILE = 2

local function copy_vec3(v)
    return vec3.new(v.x, v.y, v.z)
end

local function sq_distance_xy(a, b)
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    return (dx * dx) + (dy * dy)
end

local function sq_segment_distance_xy(p, a, b)
    local ax = a.x or 0.0
    local ay = a.y or 0.0
    local bx = b.x or 0.0
    local by = b.y or 0.0
    local px = p.x or 0.0
    local py = p.y or 0.0

    local dx = bx - ax
    local dy = by - ay
    if dx == 0.0 and dy == 0.0 then
        local qx = px - ax
        local qy = py - ay
        return (qx * qx) + (qy * qy)
    end

    local t = ((px - ax) * dx + (py - ay) * dy) / ((dx * dx) + (dy * dy))
    if t < 0.0 then
        t = 0.0
    elseif t > 1.0 then
        t = 1.0
    end

    local cx = ax + (dx * t)
    local cy = ay + (dy * t)
    local qx = px - cx
    local qy = py - cy
    return (qx * qx) + (qy * qy)
end

local function clone_points(points)
    local out = {}
    for i, p in ipairs(points or {}) do
        out[#out + 1] = vec3.new(p.x, p.y, p.z)
    end
    return out
end

local function simplify_points_near_duplicates(points, min_step)
    if type(points) ~= "table" or #points <= 1 then
        return clone_points(points)
    end

    local step = math.max(0.10, tonumber(min_step) or 0.50)
    local sq_step = step * step
    local out = { vec3.new(points[1].x, points[1].y, points[1].z) }

    for i = 2, #points do
        local p = points[i]
        if sq_distance_xy(out[#out], p) >= sq_step then
            out[#out + 1] = vec3.new(p.x, p.y, p.z)
        end
    end

    if #out == 1 and #points > 1 then
        local last = points[#points]
        out[#out + 1] = vec3.new(last.x, last.y, last.z)
    end

    return out
end

local function simplify_points_douglas_peucker(points, tolerance)
    if type(points) ~= "table" or #points <= 2 then
        return clone_points(points)
    end

    local sq_tolerance = math.max(0.01, tonumber(tolerance) or 2.0)
    sq_tolerance = sq_tolerance * sq_tolerance

    local n = #points
    local markers = {}
    markers[1] = true
    markers[n] = true

    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = stack[#stack]
        stack[#stack] = nil

        local first = seg[1]
        local last = seg[2]
        local max_sq_dist = 0.0
        local index = nil

        for i = first + 1, last - 1 do
            local sq_dist = sq_segment_distance_xy(points[i], points[first], points[last])
            if sq_dist > max_sq_dist then
                max_sq_dist = sq_dist
                index = i
            end
        end

        if index and max_sq_dist > sq_tolerance then
            markers[index] = true
            stack[#stack + 1] = { first, index }
            stack[#stack + 1] = { index, last }
        end
    end

    local out = {}
    for i = 1, n do
        if markers[i] then
            local p = points[i]
            out[#out + 1] = vec3.new(p.x, p.y, p.z)
        end
    end

    if #out < 2 and n >= 2 then
        return { vec3.new(points[1].x, points[1].y, points[1].z), vec3.new(points[n].x, points[n].y, points[n].z) }
    end

    return out
end

local function simplify_route_points(points, tolerance, min_step)
    if type(points) ~= "table" or #points < 3 then
        return clone_points(points)
    end

    local compact = simplify_points_near_duplicates(points, min_step)
    if #compact < 3 then
        return compact
    end

    local reduced = simplify_points_douglas_peucker(compact, tolerance)
    if #reduced < 2 then
        return compact
    end

    return simplify_points_near_duplicates(reduced, min_step)
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

--- Return a value with random jitter applied: value * (1 +/- jitter_pct).
--- E.g. jitter(1.0, 0.2) returns a random value between 0.8 and 1.2.
local function jitter(value, jitter_pct)
    local pct = jitter_pct or 0.15
    return value * (1.0 + (math.random() * 2.0 - 1.0) * pct)
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

local function bag_get_num_slots(bag_id)
    if C_Container and type(C_Container.GetContainerNumSlots) == "function" then
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag_id)
        if ok and type(slots) == "number" then
            return slots
        end
    end

    if type(GetContainerNumSlots) == "function" then
        local ok, slots = pcall(GetContainerNumSlots, bag_id)
        if ok and type(slots) == "number" then
            return slots
        end
    end

    return 0
end

local function bag_get_item_info(bag_id, slot_id)
    if C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag_id, slot_id)
        if ok and type(info) == "table" then
            return info
        end
    end

    if type(GetContainerItemInfo) == "function" then
        local ok, texture, item_count, locked, quality, readable, lootable, hyperlink = pcall(GetContainerItemInfo, bag_id,
            slot_id)
        if ok and texture then
            return {
                iconFileID = texture,
                stackCount = item_count,
                isLocked = locked,
                quality = quality,
                isReadable = readable,
                hasLoot = lootable,
                hyperlink = hyperlink
            }
        end
    end

    return nil
end

local function bag_use_item(bag_id, slot_id)
    if C_Container and type(C_Container.UseContainerItem) == "function" then
        local ok = pcall(C_Container.UseContainerItem, bag_id, slot_id)
        if ok then
            return true
        end
    end

    if type(UseContainerItem) == "function" then
        local ok = pcall(UseContainerItem, bag_id, slot_id)
        if ok then
            return true
        end
    end

    return false
end

local function is_merchant_frame_open()
    if type(MerchantFrame) ~= "table" then
        return false
    end

    if type(MerchantFrame.IsShown) == "function" then
        local ok, shown = pcall(MerchantFrame.IsShown, MerchantFrame)
        if ok and shown == true then
            return true
        end
    end

    if type(MerchantFrame.IsVisible) == "function" then
        local ok, visible = pcall(MerchantFrame.IsVisible, MerchantFrame)
        if ok and visible == true then
            return true
        end
    end

    return false
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
            _session_started_at = 0,
            _session_elapsed_at_stop = 0,
            _session_kills = 0,
            _session_deaths = 0,
            _session_loot_attempts = 0,
            _session_vendor_runs = 0,
            _session_vendor_completions = 0,
            _session_junk_sold = 0,
            _session_repairs = 0,
            _session_last_reset_at = 0,
            _was_player_dead = false,
            _movement = nil,
            _nav_error = nil,
            _move_inflight = false,
            _move_request_id = 0,
            _move_target = nil,
            _move_status_text = nil,
            _move_started_at = 0,
            _move_timeout = 20.0,
            _move_stall_timeout = 4.0,
            _move_progress_min = 0.9,
            _move_last_progress_at = 0,
            _move_last_progress_pos = nil,
            _unstuck_enabled = true,
            _unstuck_attempt_count = 0,
            _unstuck_max_attempts = 5,
            _unstuck_action = nil,
            _unstuck_last_reason = nil,
            _unstuck_cooldown_until = 0,
            _waypoints = {},
            _waypoint_index = 1,
            _waypoint_direction = 1,
            _route_radius = 35.0,
            _route_radius_min = 35.0,
            _route_radius_max = 140.0,
            _route_expand_step = 20.0,
            _route_expand_interval = 12.0,
            _route_simplify_tolerance = 2.2,
            _route_simplify_min_step = 1.0,
            _last_target_seen_at = 0,
            _last_route_expand_at = 0,
            _route_mode = ROUTE_MODE_CIRCLE,
            _route_profiles = nil,
            _last_route_profile_refresh = 0,
            _route_profile_refresh_interval = 2.0,
            _last_route_profile_id = nil,
            _anchor = nil,

            -- Targeting and combat flow
            _target = nil,
            _target_guid = nil,
            _target_dead_counted = false,
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
            _loot_max_attempts = 8,
            _loot_current_attempts = 0,
            _last_loot_attempt = 0,

            -- Replenish / vendor flow
            _auto_replenish_enabled = false,
            _replenish_min_free_slots = 2,
            _vendor_npc_id = 0,
            _vendor_scan_radius = 120.0,
            _vendor_interact_range = 5.0,
            _auto_vendor_sell_junk = true,
            _auto_vendor_repair = true,
            _replenish_active = false,
            _replenish_started_at = 0,
            _replenish_timeout = 90.0,
            _replenish_cooldown = 20.0,
            _replenish_cooldown_until = 0,
            _last_vendor_interact = 0,
            _vendor_interact_interval = 1.1,
            _last_vendor_action = 0,
            _vendor_action_interval = 0.8,
            _inventory_helper = nil,
            _cached_free_slots = nil,
            _cached_total_slots = nil,
            _last_inventory_snapshot = 0,
            _inventory_snapshot_interval = 0.5,

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

function GrindBuddy:_select_closest_waypoint_index(local_player, points)
    if not local_player or not points or #points == 0 then
        return 1
    end

    local my_pos = local_player:get_position()
    local best_index = 1
    local best_dist = math.huge

    for i, p in ipairs(points) do
        local d = self:_distance_to(my_pos, p)
        if d < best_dist then
            best_dist = d
            best_index = i
        end
    end

    return best_index
end

function GrindBuddy:_set_waypoints(points, start_at_closest, there_and_back, local_player)
    local instance = self:get_instance()
    local original_points = points or {}
    local simplified_points = simplify_route_points(
        original_points,
        instance._route_simplify_tolerance,
        instance._route_simplify_min_step
    )

    if #simplified_points >= 2 then
        instance._waypoints = simplified_points
    else
        instance._waypoints = clone_points(original_points)
    end
    instance._waypoint_direction = 1

    if #instance._waypoints == 0 then
        instance._waypoint_index = 1
        return
    end

    if start_at_closest and local_player and local_player:is_valid() then
        instance._waypoint_index = self:_select_closest_waypoint_index(local_player, instance._waypoints)
        if there_and_back and instance._waypoint_index >= #instance._waypoints then
            instance._waypoint_direction = -1
        end
    else
        instance._waypoint_index = 1
    end
end

function GrindBuddy:_maybe_refresh_route_profile(local_player, now, force)
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return false
    end

    local t = now or now_time()
    if not force and (t - instance._last_route_profile_refresh) < instance._route_profile_refresh_interval then
        return false
    end
    instance._last_route_profile_refresh = t

    if manager:is_auto_select_enabled() then
        manager:detect_default_profile(local_player, current_map_id())
    end

    local active_id = manager:get_active_profile_id()
    if active_id ~= instance._last_route_profile_id then
        instance._last_route_profile_id = active_id
        core.log("[GrindBuddy] Route profile: " .. tostring(manager:get_active_profile_label()))

        if instance._running and instance._route_mode == ROUTE_MODE_PROFILE and not instance._target then
            instance._waypoints = {}
            instance._waypoint_index = 1
            instance._waypoint_direction = 1
        end
        return true
    end

    return false
end

function GrindBuddy:_build_profile_route(local_player, start_at_closest)
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return false
    end

    self:_maybe_refresh_route_profile(local_player, now_time(), true)

    local profile = manager:get_active_profile()
    if not profile then
        return false
    end

    local map_id = current_map_id()
    if profile.map_id and profile.map_id > 0 and map_id and map_id > 0 and profile.map_id ~= map_id then
        return false
    end

    local points = manager:get_active_points()
    if #points < 2 then
        return false
    end

    instance._anchor = copy_vec3(local_player:get_position())
    self:_set_waypoints(points, start_at_closest ~= false, profile.there_and_back == true, local_player)
    return true
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

    self:_set_waypoints(points, false, false, nil)
end

function GrindBuddy:_build_patrol_route(local_player, start_at_closest)
    local instance = self:get_instance()
    if instance._route_mode == ROUTE_MODE_PROFILE then
        if self:_build_profile_route(local_player, start_at_closest) then
            return true
        end
    end

    self:_build_default_route(local_player)
    return true
end

function GrindBuddy:_maybe_expand_search(local_player, now)
    local instance = self:get_instance()
    if instance._target then
        return
    end
    if instance._route_mode ~= ROUTE_MODE_CIRCLE then
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
    local count = #instance._waypoints
    if count == 0 then
        return
    end

    if instance._route_mode == ROUTE_MODE_PROFILE and instance._route_profiles then
        local profile = instance._route_profiles:get_active_profile()
        if profile and profile.there_and_back then
            if count <= 1 then
                instance._waypoint_index = 1
                return
            end

            local next_idx = instance._waypoint_index + instance._waypoint_direction
            if next_idx > count then
                instance._waypoint_direction = -1
                next_idx = count - 1
            elseif next_idx < 1 then
                instance._waypoint_direction = 1
                next_idx = 2
            end

            instance._waypoint_index = math.max(1, math.min(count, next_idx))
            return
        end
    end

    instance._waypoint_index = instance._waypoint_index + 1
    if instance._waypoint_index > count then
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
    if moving then
        self:_cancel_inflight_move("dismount")
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
    if moving then
        self:_cancel_inflight_move("mount")
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
    instance._target_dead_counted = false
    instance._target_acquired_at = now
    instance._last_target_seen_at = now
    instance._loot_current_attempts = 0

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

    if (now - instance._last_loot_attempt) < jitter(instance._loot_attempt_interval, 0.25) then
        return true
    end
    instance._last_loot_attempt = now
    instance._loot_current_attempts = (instance._loot_current_attempts or 0) + 1

    -- Loot timeout: give up after max attempts to prevent infinite loot loops
    if instance._loot_current_attempts > instance._loot_max_attempts then
        core.log_warning("[GrindBuddy] Loot timeout: giving up after " .. tostring(instance._loot_max_attempts) .. " attempts")
        instance._loot_current_attempts = 0
        return false
    end

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
    instance._session_loot_attempts = (instance._session_loot_attempts or 0) + 1

    self:_set_state("looting")
    self:_set_status(string.format("Looting (%d/%d)", instance._loot_current_attempts, instance._loot_max_attempts))
    return true
end

function GrindBuddy:_get_bag_slot_count(bag_id)
    if bag_id == 0 then
        local slots = bag_get_num_slots(0)
        if slots > 0 then
            return slots
        end
        return 16
    end

    local instance = self:get_instance()
    if instance._inventory_helper == nil then
        local ok, helper = pcall(require, "common/utility/inventory_helper")
        instance._inventory_helper = ok and helper or false
    end

    if instance._inventory_helper and instance._inventory_helper.get_character_bag_slots then
        local slots = instance._inventory_helper:get_character_bag_slots()
        if slots then
            local max_slot = 0
            for _, slot_data in ipairs(slots) do
                if slot_data.bag_id == bag_id and slot_data.bag_slot > max_slot then
                    max_slot = slot_data.bag_slot
                end
            end
            if max_slot > 0 then
                return max_slot
            end
        end
    end

    return math.max(0, bag_get_num_slots(bag_id))
end

function GrindBuddy:_get_bag_item_count(bag_id)
    if core.inventory and core.inventory.get_items_in_bag then
        local items = core.inventory.get_items_in_bag(bag_id)
        if items then
            local count = 0
            for _, item in ipairs(items) do
                if item and item.id and item.id > 0 then
                    count = count + 1
                end
            end
            return count
        end
    end

    local slot_count = bag_get_num_slots(bag_id)
    if slot_count <= 0 then
        return 0
    end

    local count = 0
    for slot_id = 1, slot_count do
        local info = bag_get_item_info(bag_id, slot_id)
        if info and (info.hyperlink or info.itemID or info.itemLink) then
            count = count + 1
        end
    end
    return count
end

function GrindBuddy:_get_free_bag_slots()
    local total_slots = 0
    local free_slots = 0

    for bag_id = 0, 4 do
        local bag_slots = self:_get_bag_slot_count(bag_id)
        if bag_slots > 0 then
            total_slots = total_slots + bag_slots
            local bag_items = self:_get_bag_item_count(bag_id)
            if bag_items > bag_slots then
                bag_items = bag_slots
            end
            free_slots = free_slots + (bag_slots - bag_items)
        end
    end

    if total_slots <= 0 then
        return nil, nil
    end
    return free_slots, total_slots
end

function GrindBuddy:_is_replenish_needed()
    local instance = self:get_instance()
    if not instance._auto_replenish_enabled then
        return false, nil, nil
    end
    if instance._vendor_npc_id <= 0 then
        return false, nil, nil
    end
    if now_time() < (instance._replenish_cooldown_until or 0) then
        return false, nil, nil
    end

    local free_slots, total_slots = self:_get_free_bag_slots()
    if free_slots == nil then
        return false, nil, nil
    end

    return free_slots <= instance._replenish_min_free_slots, free_slots, total_slots
end

function GrindBuddy:_find_vendor_target(local_player)
    local instance = self:get_instance()
    if instance._vendor_npc_id <= 0 then
        return nil, math.huge
    end

    local all_objects = core.object_manager.get_all_objects()
    if not all_objects then
        return nil, math.huge
    end

    local my_pos = local_player:get_position()
    local best = nil
    local best_dist = math.huge

    for _, obj in ipairs(all_objects) do
        if obj and call_method(obj, "is_valid") ~= false and call_method(obj, "is_unit") == true and call_method(obj, "is_player") ~= true then
            local npc_id = tonumber(call_method(obj, "get_npc_id")) or -1
            if npc_id == instance._vendor_npc_id then
                local obj_pos = call_method(obj, "get_position")
                local dist = self:_distance_to(my_pos, obj_pos)
                if dist <= instance._vendor_scan_radius and dist < best_dist then
                    best = obj
                    best_dist = dist
                end
            end
        end
    end

    return best, best_dist
end

function GrindBuddy:_interact_with_object(target, target_pos)
    if not target or not core.input then
        return false
    end

    if target_pos and core.input.look_at then
        core.input.look_at(target_pos)
    end

    if core.input.interact_with_object then
        core.input.interact_with_object(target)
        return true
    end
    if core.input.interact_with_unit then
        core.input.interact_with_unit(target)
        return true
    end
    if core.input.use_object then
        core.input.use_object(target)
        return true
    end

    return false
end

function GrindBuddy:_get_bag_slot_quality(bag_id, slot_id)
    local info = bag_get_item_info(bag_id, slot_id)
    if not info then
        return nil
    end

    local quality = tonumber(info.quality)
    if quality ~= nil then
        return quality
    end

    local link = info.hyperlink or info.itemLink
    if link and type(GetItemInfo) == "function" then
        local ok, _, _, link_quality = pcall(GetItemInfo, link)
        if ok then
            return tonumber(link_quality)
        end
    end

    return nil
end

function GrindBuddy:_count_junk_slots()
    local junk = 0
    for bag_id = 0, 4 do
        local slot_count = bag_get_num_slots(bag_id)
        if slot_count > 0 then
            for slot_id = 1, slot_count do
                local quality = self:_get_bag_slot_quality(bag_id, slot_id)
                if quality == 0 then
                    junk = junk + 1
                end
            end
        end
    end
    return junk
end

function GrindBuddy:_sell_junk_items()
    local sold = 0
    for bag_id = 0, 4 do
        local slot_count = bag_get_num_slots(bag_id)
        if slot_count > 0 then
            for slot_id = slot_count, 1, -1 do
                local quality = self:_get_bag_slot_quality(bag_id, slot_id)
                if quality == 0 and bag_use_item(bag_id, slot_id) then
                    sold = sold + 1
                end
            end
        end
    end
    return sold
end

function GrindBuddy:_needs_repair()
    if type(CanMerchantRepair) == "function" then
        local ok, can_repair = pcall(CanMerchantRepair)
        if ok and can_repair ~= true then
            return false
        end
    end

    if type(GetRepairAllCost) ~= "function" then
        return false
    end

    local ok, cost, can_repair = pcall(GetRepairAllCost)
    if not ok then
        return false
    end
    return (tonumber(cost) or 0) > 0 and can_repair == true
end

function GrindBuddy:_repair_items()
    if type(RepairAllItems) ~= "function" then
        return false
    end
    if not self:_needs_repair() then
        return false
    end

    local ok = pcall(RepairAllItems)
    if not ok then
        ok = pcall(RepairAllItems, false)
    end
    return ok == true
end

function GrindBuddy:_run_vendor_actions(now)
    local instance = self:get_instance()
    if (now - instance._last_vendor_action) < instance._vendor_action_interval then
        return false
    end
    instance._last_vendor_action = now

    local repaired = false
    local sold_count = 0

    if instance._auto_vendor_repair then
        repaired = self:_repair_items()
    end
    if instance._auto_vendor_sell_junk then
        sold_count = self:_sell_junk_items()
    end

    if repaired then
        core.log("[GrindBuddy] Vendor: repaired items")
    end
    if sold_count > 0 then
        instance._session_junk_sold = (instance._session_junk_sold or 0) + sold_count
        core.log(string.format("[GrindBuddy] Vendor: sold %d junk items", sold_count))
    end
    if repaired then
        instance._session_repairs = (instance._session_repairs or 0) + 1
    end

    local remaining_junk = instance._auto_vendor_sell_junk and self:_count_junk_slots() or 0
    local remaining_repair = instance._auto_vendor_repair and self:_needs_repair() or false
    local completed = remaining_junk == 0 and remaining_repair == false
    return completed, sold_count, repaired
end

function GrindBuddy:_tick_replenish(local_player, now)
    local instance = self:get_instance()
    if not instance._auto_replenish_enabled then
        instance._replenish_active = false
        return false
    end
    if instance._vendor_npc_id <= 0 then
        if instance._replenish_active then
            instance._replenish_active = false
            self:_set_state("patrol")
            self:_set_status("Replenish disabled (vendor NPC ID not set)")
        end
        return false
    end

    if call_method(local_player, "is_in_combat") == true then
        return false
    end

    local should_replenish, free_slots, total_slots = self:_is_replenish_needed()
    if not should_replenish and not instance._replenish_active then
        return false
    end

    if not instance._replenish_active then
        self:_cancel_inflight_move("replenish-start")
        self:_clear_target()
        instance._replenish_active = true
        instance._replenish_started_at = now
        instance._session_vendor_runs = (instance._session_vendor_runs or 0) + 1
        instance._last_vendor_interact = 0
        instance._last_vendor_action = 0
        self:_set_state("replenish")
        if free_slots and total_slots then
            self:_set_status(string.format("Replenish started (%d/%d free)", free_slots, total_slots))
        else
            self:_set_status("Replenish started")
        end
        core.log(string.format("[GrindBuddy] Replenish started (vendor npc_id=%d)", instance._vendor_npc_id))
    end

    if (now - instance._replenish_started_at) > instance._replenish_timeout then
        instance._replenish_active = false
        instance._replenish_fail_count = (instance._replenish_fail_count or 0) + 1
        -- Exponential backoff: double the cooldown each consecutive failure (max 5 min)
        local backoff = math.min(300.0, instance._replenish_cooldown * math.pow(2, instance._replenish_fail_count - 1))
        instance._replenish_cooldown_until = now + backoff
        self:_set_state("patrol")
        self:_set_status(string.format("Replenish timeout (%d fails, next in %.0fs)", instance._replenish_fail_count, backoff))
        core.log_warning(string.format("[GrindBuddy] Replenish timeout (fail #%d), cooldown %.0fs", instance._replenish_fail_count, backoff))
        return false
    end

    local vendor, dist = self:_find_vendor_target(local_player)
    if not vendor then
        self:_set_state("replenish")
        self:_set_status(string.format("Searching vendor npc_id=%d", instance._vendor_npc_id))
        return true
    end

    local vendor_pos = call_method(vendor, "get_position")
    local movement = instance._movement
    local moving = movement and movement.is_moving and movement:is_moving() or false

    if dist > instance._vendor_interact_range then
        if not moving and not instance._move_inflight and vendor_pos then
            self:_begin_move(vendor_pos, string.format("Moving to vendor (%.1f yd)", dist))
        else
            self:_set_state("replenish")
            self:_set_status(string.format("Approaching vendor (%.1f yd)", dist))
        end
        return true
    end

    if moving then
        self:_cancel_inflight_move("vendor-in-range")
    end

    if not is_merchant_frame_open() then
        if (now - instance._last_vendor_interact) >= instance._vendor_interact_interval then
            if self:_interact_with_object(vendor, vendor_pos) then
                instance._last_vendor_interact = now
                self:_set_state("replenish")
                self:_set_status("Opening vendor")
            end
        else
            self:_set_state("replenish")
            self:_set_status("Waiting vendor window")
        end
        return true
    end

    local completed, sold_count, repaired = self:_run_vendor_actions(now)
    if completed then
        instance._replenish_active = false
        instance._replenish_fail_count = 0
        instance._session_vendor_completions = (instance._session_vendor_completions or 0) + 1
        if sold_count == 0 and repaired ~= true then
            instance._replenish_cooldown_until = now + instance._replenish_cooldown
        end
        self:_set_state("patrol")
        self:_set_status("Replenish complete")
        core.log("[GrindBuddy] Replenish complete")
        return false
    end

    self:_set_state("replenish")
    self:_set_status("Vendor actions in progress")
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

    if now - instance._last_scan < jitter(instance._scan_interval, 0.25) then
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
    instance._target_dead_counted = false
    instance._target_acquired_at = 0
end

function GrindBuddy:_attempt_pull(target)
    local instance = self:get_instance()
    local now = now_time()
    if now - instance._last_pull_attempt < jitter(instance._pull_cooldown, 0.20) then
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

function GrindBuddy:_invalidate_move_request()
    local instance = self:get_instance()
    instance._move_request_id = (instance._move_request_id or 0) + 1
    return instance._move_request_id
end

function GrindBuddy:_reset_unstuck_runtime(reset_attempts)
    local instance = self:get_instance()
    instance._unstuck_action = nil
    instance._unstuck_last_reason = nil
    instance._unstuck_cooldown_until = 0
    if reset_attempts then
        instance._unstuck_attempt_count = 0
    end
end

function GrindBuddy:_track_move_progress(local_player, now)
    local instance = self:get_instance()
    if not local_player or not local_player:is_valid() then
        return 0.0
    end

    local pos = local_player:get_position()
    if not pos then
        return 0.0
    end

    if not instance._move_last_progress_pos then
        instance._move_last_progress_pos = copy_vec3(pos)
        instance._move_last_progress_at = now
        return 0.0
    end

    local moved = pos:dist_to(instance._move_last_progress_pos)
    if moved >= instance._move_progress_min then
        instance._move_last_progress_pos = copy_vec3(pos)
        instance._move_last_progress_at = now
        if instance._unstuck_attempt_count > 0 then
            instance._unstuck_attempt_count = 0
        end
    end

    return moved
end

function GrindBuddy:_add_blackspot_here(pos, reason, ttl)
    local instance = self:get_instance()
    local map_id = current_map_id()
    if not (instance._blackspots and pos and map_id) then
        return false
    end
    return instance._blackspots:add(pos, map_id, instance._blackspot_radius, reason, ttl or instance._blackspot_ttl) == true
end

function GrindBuddy:_cancel_inflight_move(reason)
    local instance = self:get_instance()
    local had_inflight = instance._move_inflight == true

    self:_invalidate_move_request()

    if instance._movement and instance._movement.stop then
        instance._movement:stop()
    end

    instance._move_inflight = false
    if had_inflight and reason then
        core.log("[GrindBuddy] Move canceled: " .. tostring(reason))
    end
end

function GrindBuddy:_retry_move_after_unstuck(reason)
    local instance = self:get_instance()
    local target = instance._move_target
    if not target then
        return false
    end

    -- Set a cooldown so the stall detector doesn't immediately re-trigger
    instance._unstuck_cooldown_until = now_time() + 3.0

    local attempt = instance._unstuck_attempt_count or 0
    local status = string.format("Recovering (%d/%d)", attempt, instance._unstuck_max_attempts)
    if reason and reason ~= "" then
        status = status .. ": " .. reason
    end
    return self:_begin_move(target, status)
end

function GrindBuddy:_start_unstuck_action(local_player, action_name, duration, start_fn, stop_fn, jump_after, retry_reason)
    local instance = self:get_instance()
    local now = now_time()

    self:_cancel_inflight_move("unstuck-" .. tostring(action_name))

    if start_fn then
        start_fn()
    end

    if duration and duration > 0 then
        instance._unstuck_action = {
            name = action_name,
            ends_at = now + duration,
            stop_fn = stop_fn,
            jump_after = jump_after == true,
            retry_reason = retry_reason,
        }
        self:_set_state("recovering")
        self:_set_status("Unstuck: " .. tostring(action_name))
        return true
    end

    if jump_after and core.input and core.input.jump then
        core.input.jump()
    end

    self:_set_state("recovering")
    self:_set_status("Unstuck: " .. tostring(action_name))

    return self:_retry_move_after_unstuck(retry_reason or action_name)
end

function GrindBuddy:_attempt_unstuck(local_player, now, stall_reason)
    local instance = self:get_instance()
    if instance._unstuck_enabled ~= true then
        return false
    end

    if instance._unstuck_action then
        return true
    end

    -- Cooldown guard: prevent rapid re-entry after a retry move
    if now < (instance._unstuck_cooldown_until or 0) then
        return true
    end

    instance._unstuck_attempt_count = (instance._unstuck_attempt_count or 0) + 1
    local attempt = instance._unstuck_attempt_count
    instance._unstuck_last_reason = stall_reason

    core.log(string.format("[GrindBuddy] Unstuck attempt %d/%d (%s)", attempt, instance._unstuck_max_attempts, tostring(stall_reason)))

    if attempt > instance._unstuck_max_attempts then
        local pos = local_player and local_player:is_valid() and local_player:get_position() or nil
        local tagged = self:_add_blackspot_here(pos, "unstuck-failed", instance._blackspot_ttl)

        self:_cancel_inflight_move("unstuck-failed")
        self:_set_state("patrol")
        self:_set_status(tagged and "Unstuck failed, blackspot added" or "Unstuck failed, skipping current move")

        if instance._target then
            self:_blacklist_target(instance._target, "unstuck-failed")
            self:_clear_target()
        else
            self:_advance_waypoint()
        end

        self:_reset_unstuck_runtime(true)
        return true
    end

    local input = core.input
    if attempt == 1 then
        return self:_start_unstuck_action(local_player, "jump", 0.0, nil, nil, true, "jump")
    end

    if attempt == 2 and input and input.strafe_left_start and input.strafe_left_stop then
        return self:_start_unstuck_action(local_player, "strafe-left", 0.45, function()
            input.strafe_left_start()
        end, function()
            input.strafe_left_stop()
        end, true, "strafe-left")
    end

    if attempt == 3 and input and input.strafe_right_start and input.strafe_right_stop then
        return self:_start_unstuck_action(local_player, "strafe-right", 0.45, function()
            input.strafe_right_start()
        end, function()
            input.strafe_right_stop()
        end, true, "strafe-right")
    end

    if attempt == 4 and input and input.move_backward_start and input.move_backward_stop then
        return self:_start_unstuck_action(local_player, "backward", 0.80, function()
            input.move_backward_start()
        end, function()
            input.move_backward_stop()
        end, true, "backward")
    end

    if attempt == 5 and input and input.turn_left_start and input.turn_left_stop then
        return self:_start_unstuck_action(local_player, "turn-left", 0.50, function()
            input.turn_left_start()
        end, function()
            input.turn_left_stop()
        end, false, "turn-left")
    end

    -- Fallback: no low-level input available for this step, just retry the move directly.
    self:_cancel_inflight_move("unstuck-retry-direct")
    self:_set_state("recovering")
    self:_set_status("Unstuck: direct retry")
    return self:_retry_move_after_unstuck("retry")
end

function GrindBuddy:_process_unstuck_action(local_player, now)
    local instance = self:get_instance()
    local action = instance._unstuck_action
    if not action then
        return false
    end

    if now < action.ends_at then
        self:_set_state("recovering")
        self:_set_status("Unstuck: " .. tostring(action.name))
        return true
    end

    if action.stop_fn then
        action.stop_fn()
    end

    if action.jump_after and core.input and core.input.jump then
        core.input.jump()
    end

    instance._unstuck_action = nil
    self:_retry_move_after_unstuck(action.retry_reason or action.name)
    return true
end

function GrindBuddy:_monitor_inflight_move(local_player, now)
    local instance = self:get_instance()
    if self:_process_unstuck_action(local_player, now) then
        return true
    end

    if not instance._move_inflight then
        return false
    end

    self:_track_move_progress(local_player, now)

    local started = instance._move_started_at or now
    local last_progress = instance._move_last_progress_at or started
    local stall_age = now - last_progress
    local total_age = now - started

    if stall_age >= instance._move_stall_timeout then
        return self:_attempt_unstuck(local_player, now, "stalled")
    end

    if total_age >= instance._move_timeout then
        return self:_attempt_unstuck(local_player, now, "timeout")
    end

    return false
end

function GrindBuddy:_begin_move(target, status_text)
    local instance = self:get_instance()
    local movement = instance._movement
    if not movement or not target then
        return false
    end

    local request_id = self:_invalidate_move_request()
    local started = now_time()
    local player = core.object_manager.get_local_player()

    instance._move_target = copy_vec3(target)
    instance._move_status_text = status_text
    instance._move_inflight = true
    instance._move_started_at = started
    instance._move_last_progress_at = started
    instance._move_last_progress_pos = (player and player:is_valid()) and copy_vec3(player:get_position()) or nil
    self:_set_state("moving")
    self:_set_status(status_text or "Moving")

    movement:move_to(target, function(success, reason)
        if request_id ~= instance._move_request_id then
            return
        end

        instance._move_inflight = false
        if success then
            self:_reset_unstuck_runtime(true)
            return
        end

        if reason and tostring(reason) == "stopped" then
            return
        end

        if not instance._unstuck_action then
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

    -- Waypoint lookahead: if we're close to the current waypoint while still
    -- moving, advance to the next one early so there's no pause between them.
    if moving and local_player and local_player:is_valid() then
        local wp = self:_current_waypoint()
        if wp then
            local my_pos = local_player:get_position()
            local dist_to_wp = self:_distance_to(my_pos, wp)
            if dist_to_wp and dist_to_wp < 5.0 then
                self:_advance_waypoint()
            end
        end
        self:_set_state("patrol")
        self:_set_status("Patrolling")
        return
    end

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
        self:_build_patrol_route(local_player, true)
        target = self:_current_waypoint()
        if not target then
            return
        end
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
        if not instance._target_dead_counted then
            instance._target_dead_counted = true
            instance._session_kills = (instance._session_kills or 0) + 1
        end

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

    if moving then
        self:_cancel_inflight_move("target-in-range")
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

    if not instance._route_profiles then
        instance._route_profiles = GrindProfileManager:new({
            default_radius = instance._route_radius_min,
            default_point_count = 8,
        })
    end

    instance._initialized = true
    core.log(string.format("[GrindBuddy] Initialized v%s", GrindBuddy.VERSION))
    local local_player = core.object_manager.get_local_player()
    if instance._rotation and local_player and local_player:is_valid() then
        instance._rotation:detect_default_profile(local_player)
        core.log("[GrindBuddy] Rotation profile: " .. tostring(instance._rotation:get_active_profile_label()))
    end

    if instance._route_profiles then
        local anchor = nil
        if local_player and local_player:is_valid() then
            anchor = local_player:get_position()
        end
        instance._route_profiles:load(anchor)
        if local_player and local_player:is_valid() then
            instance._route_profiles:detect_default_profile(local_player, current_map_id())
        end
        instance._last_route_profile_id = instance._route_profiles:get_active_profile_id()
        core.log("[GrindBuddy] Route profile: " .. tostring(instance._route_profiles:get_active_profile_label()))
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

    if instance._route_profiles then
        self:_maybe_refresh_route_profile(local_player, now_time(), true)
    end

    instance._route_radius = instance._route_radius_min
    self:_build_patrol_route(local_player, true)

    self:_clear_target()
    instance._running = true
    self:_invalidate_move_request()
    instance._move_inflight = false
    instance._move_target = nil
    instance._move_status_text = nil
    instance._move_started_at = 0
    instance._move_last_progress_at = 0
    instance._move_last_progress_pos = nil
    instance._last_target_seen_at = now_time()
    instance._last_route_expand_at = 0
    instance._last_route_profile_refresh = 0
    instance._last_mount_attempt = 0
    instance._last_dismount_attempt = 0
    instance._session_started_at = now_time()
    instance._session_elapsed_at_stop = 0
    instance._session_kills = 0
    instance._session_deaths = 0
    instance._session_loot_attempts = 0
    instance._session_vendor_runs = 0
    instance._session_vendor_completions = 0
    instance._session_junk_sold = 0
    instance._session_repairs = 0
    instance._session_last_reset_at = instance._session_started_at
    instance._was_player_dead = false
    instance._cached_free_slots = nil
    instance._cached_total_slots = nil
    instance._last_inventory_snapshot = 0
    instance._replenish_active = false
    instance._replenish_started_at = 0
    instance._replenish_cooldown_until = 0
    instance._last_vendor_interact = 0
    instance._last_vendor_action = 0
    self:_reset_unstuck_runtime(true)
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

    self:_cancel_inflight_move("stop")
    instance._running = false
    if instance._session_started_at and instance._session_started_at > 0 then
        instance._session_elapsed_at_stop = math.max(0, now_time() - instance._session_started_at)
    else
        instance._session_elapsed_at_stop = 0
    end
    instance._move_target = nil
    instance._move_status_text = nil
    instance._move_started_at = 0
    instance._move_last_progress_at = 0
    instance._move_last_progress_pos = nil
    instance._replenish_active = false
    instance._replenish_started_at = 0
    instance._replenish_cooldown_until = 0
    instance._last_vendor_interact = 0
    instance._last_vendor_action = 0
    instance._was_player_dead = false
    instance._cached_free_slots = nil
    instance._cached_total_slots = nil
    instance._last_inventory_snapshot = 0
    self:_reset_unstuck_runtime(true)
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
    if now - instance._last_tick < jitter(instance._tick_interval, 0.20) then
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

    local player_dead = call_method(local_player, "is_dead") == true
    if player_dead and not instance._was_player_dead then
        instance._session_deaths = (instance._session_deaths or 0) + 1
    end
    instance._was_player_dead = player_dead

    if player_dead then
        self:_set_state("waiting")
        self:_set_status("Player dead")
        return
    end

    self:_maybe_refresh_route_profile(local_player, now, false)

    if not instance._movement then
        self:_ensure_nav_movement()
    end

    local movement = instance._movement
    if not movement then
        self:_set_state("waiting")
        self:_set_status("Waiting for NavLib")
        return
    end

    if self:_monitor_inflight_move(local_player, now) then
        return
    end

    if instance._target then
        self:_tick_target(local_player)
        return
    end

    if self:_tick_replenish(local_player, now) then
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

function GrindBuddy:get_runtime_stats()
    local instance = self:get_instance()
    local now = now_time()

    local duration_seconds = 0
    if instance._running and instance._session_started_at > 0 then
        duration_seconds = math.max(0, now - instance._session_started_at)
    else
        duration_seconds = math.max(0, instance._session_elapsed_at_stop or 0)
    end

    local hours = duration_seconds / 3600.0
    local kills = instance._session_kills or 0
    local loot_attempts = instance._session_loot_attempts or 0
    local vendor_runs = instance._session_vendor_runs or 0
    local vendor_completions = instance._session_vendor_completions or 0
    local guid_count = 0
    for _ in pairs(instance._blacklist_guid) do
        guid_count = guid_count + 1
    end

    local free_slots = instance._cached_free_slots
    local total_slots = instance._cached_total_slots
    if (now - (instance._last_inventory_snapshot or 0)) >= (instance._inventory_snapshot_interval or 0.5) then
        local snapshot_free, snapshot_total = self:_get_free_bag_slots()
        instance._cached_free_slots = snapshot_free
        instance._cached_total_slots = snapshot_total
        instance._last_inventory_snapshot = now
        free_slots = snapshot_free
        total_slots = snapshot_total
    end

    local total_seconds = math.floor(duration_seconds + 0.5)
    local hours_whole = math.floor(total_seconds / 3600)
    local minutes = math.floor((total_seconds % 3600) / 60)
    local seconds = total_seconds % 60
    local duration_formatted = string.format("%02d:%02d:%02d", hours_whole, minutes, seconds)

    return {
        started_at = instance._session_started_at,
        duration_seconds = duration_seconds,
        duration_formatted = duration_formatted,
        kills = kills,
        kills_per_hour = hours > 0 and (kills / hours) or 0,
        deaths = instance._session_deaths or 0,
        loot_attempts = loot_attempts,
        loot_attempts_per_hour = hours > 0 and (loot_attempts / hours) or 0,
        vendor_runs = vendor_runs,
        vendor_completions = vendor_completions,
        junk_sold = instance._session_junk_sold or 0,
        repairs = instance._session_repairs or 0,
        free_slots = free_slots,
        total_slots = total_slots,
        blacklisted_guid_count = guid_count,
        blacklisted_zone_count = #instance._blacklist_zones,
        blackspot_count = instance._blackspots and instance._blackspots:get_count() or 0,
        running = instance._running == true,
        replenish_active = instance._replenish_active == true,
    }
end

function GrindBuddy:reset_runtime_stats()
    local instance = self:get_instance()
    local now = now_time()
    instance._session_kills = 0
    instance._session_deaths = 0
    instance._session_loot_attempts = 0
    instance._session_vendor_runs = 0
    instance._session_vendor_completions = 0
    instance._session_junk_sold = 0
    instance._session_repairs = 0
    instance._session_last_reset_at = now
    instance._cached_free_slots = nil
    instance._cached_total_slots = nil
    instance._last_inventory_snapshot = 0
    if instance._running then
        instance._session_started_at = now
    else
        instance._session_elapsed_at_stop = 0
    end
end

function GrindBuddy:clear_runtime_blacklists()
    local instance = self:get_instance()
    local guid_count = 0
    for _ in pairs(instance._blacklist_guid) do
        guid_count = guid_count + 1
    end
    local zone_count = #instance._blacklist_zones
    instance._blacklist_guid = {}
    instance._blacklist_zones = {}
    return guid_count, zone_count
end

function GrindBuddy:get_grind_settings()
    local instance = self:get_instance()
    local route_profiles = instance._route_profiles
    local active_route_id = route_profiles and route_profiles:get_active_profile_id() or nil
    local active_route_index = route_profiles and route_profiles:get_profile_index_by_id(active_route_id) or 1
    return {
        scan_radius = instance._scan_radius,
        pull_range = instance._pull_range,
        chase_stop_range = instance._chase_stop_range,
        pull_cooldown = instance._pull_cooldown,
        target_timeout = instance._target_timeout,
        stickiness_bonus = instance._stickiness_bonus,
        combat_retarget_interval = instance._combat_retarget_interval,
        auto_mount_enabled = instance._auto_mount_enabled,
        mount_threshold = instance._mount_threshold,
        prefer_player_target = instance._prefer_player_target,
        min_target_level_delta = instance._min_target_level_delta,
        max_target_level_delta = instance._max_target_level_delta,
        ignore_players = instance._ignore_players,
        only_hostile_targets = instance._only_hostile_targets,
        loot_enabled = instance._loot_enabled,
        loot_range = instance._loot_range,
        loot_attempt_interval = instance._loot_attempt_interval,
        unstuck_enabled = instance._unstuck_enabled,
        unstuck_max_attempts = instance._unstuck_max_attempts,
        move_timeout = instance._move_timeout,
        move_stall_timeout = instance._move_stall_timeout,
        move_progress_min = instance._move_progress_min,
        tick_interval = instance._tick_interval,
        scan_interval = instance._scan_interval,
        route_mode = instance._route_mode,
        route_radius_min = instance._route_radius_min,
        route_radius_max = instance._route_radius_max,
        route_expand_step = instance._route_expand_step,
        route_expand_interval = instance._route_expand_interval,
        route_profile_refresh_interval = instance._route_profile_refresh_interval,
        route_auto_profile = route_profiles and route_profiles:is_auto_select_enabled() or true,
        route_profile_index = active_route_index,
        blacklist_ttl = instance._blacklist_ttl,
        zone_blacklist_ttl = instance._zone_blacklist_ttl,
        zone_blacklist_radius = instance._zone_blacklist_radius,
        blackspot_radius = instance._blackspot_radius,
        blackspot_ttl = instance._blackspot_ttl,
        auto_replenish_enabled = instance._auto_replenish_enabled,
        replenish_min_free_slots = instance._replenish_min_free_slots,
        vendor_npc_id = instance._vendor_npc_id,
        vendor_scan_radius = instance._vendor_scan_radius,
        vendor_interact_range = instance._vendor_interact_range,
        replenish_timeout = instance._replenish_timeout,
        replenish_cooldown = instance._replenish_cooldown,
        auto_vendor_sell_junk = instance._auto_vendor_sell_junk,
        auto_vendor_repair = instance._auto_vendor_repair,
    }
end

function GrindBuddy:set_grind_settings(settings)
    local instance = self:get_instance()
    if not settings then
        return
    end
    local was_replenish_active = instance._replenish_active == true
    local route_geometry_changed = false

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
    if settings.pull_cooldown ~= nil then
        local cooldown = tonumber(settings.pull_cooldown) or instance._pull_cooldown
        instance._pull_cooldown = math.max(0.2, math.min(4.0, cooldown))
    end
    if settings.target_timeout ~= nil then
        local timeout = tonumber(settings.target_timeout) or instance._target_timeout
        instance._target_timeout = math.max(6.0, math.min(90.0, timeout))
    end
    if settings.stickiness_bonus ~= nil then
        local bonus = tonumber(settings.stickiness_bonus) or instance._stickiness_bonus
        instance._stickiness_bonus = math.max(0.0, math.min(40.0, bonus))
    end
    if settings.combat_retarget_interval ~= nil then
        local interval = tonumber(settings.combat_retarget_interval) or instance._combat_retarget_interval
        instance._combat_retarget_interval = math.max(0.1, math.min(2.0, interval))
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
    if settings.prefer_player_target ~= nil then
        instance._prefer_player_target = settings.prefer_player_target == true
    end
    if settings.loot_enabled ~= nil then
        instance._loot_enabled = settings.loot_enabled == true
    end
    if settings.loot_range ~= nil then
        local loot_range = tonumber(settings.loot_range) or instance._loot_range
        instance._loot_range = math.max(2.0, math.min(15.0, loot_range))
    end
    if settings.loot_attempt_interval ~= nil then
        local loot_interval = tonumber(settings.loot_attempt_interval) or instance._loot_attempt_interval
        instance._loot_attempt_interval = math.max(0.2, math.min(3.0, loot_interval))
    end
    if settings.unstuck_enabled ~= nil then
        instance._unstuck_enabled = settings.unstuck_enabled == true
    end
    if settings.unstuck_max_attempts ~= nil then
        local attempts = tonumber(settings.unstuck_max_attempts) or instance._unstuck_max_attempts
        instance._unstuck_max_attempts = math.max(1, math.min(12, math.floor(attempts)))
    end
    if settings.move_timeout ~= nil then
        local move_timeout = tonumber(settings.move_timeout) or instance._move_timeout
        instance._move_timeout = math.max(5.0, math.min(60.0, move_timeout))
    end
    if settings.move_stall_timeout ~= nil then
        local stall_timeout = tonumber(settings.move_stall_timeout) or instance._move_stall_timeout
        instance._move_stall_timeout = math.max(0.8, math.min(12.0, stall_timeout))
    end
    if settings.move_progress_min ~= nil then
        local progress_min = tonumber(settings.move_progress_min) or instance._move_progress_min
        instance._move_progress_min = math.max(0.1, math.min(3.0, progress_min))
    end
    if settings.tick_interval ~= nil then
        local tick_interval = tonumber(settings.tick_interval) or instance._tick_interval
        instance._tick_interval = math.max(0.03, math.min(0.6, tick_interval))
    end
    if settings.scan_interval ~= nil then
        local scan_interval = tonumber(settings.scan_interval) or instance._scan_interval
        instance._scan_interval = math.max(0.10, math.min(2.0, scan_interval))
    end
    if settings.auto_replenish_enabled ~= nil then
        instance._auto_replenish_enabled = settings.auto_replenish_enabled == true
        if not instance._auto_replenish_enabled then
            instance._replenish_active = false
            if was_replenish_active then
                self:_cancel_inflight_move("replenish-disabled")
            end
        end
    end
    if settings.replenish_min_free_slots ~= nil then
        local min_slots = tonumber(settings.replenish_min_free_slots) or instance._replenish_min_free_slots
        instance._replenish_min_free_slots = math.max(0, math.min(16, math.floor(min_slots)))
    end
    if settings.vendor_npc_id ~= nil then
        local npc_id = tonumber(settings.vendor_npc_id) or instance._vendor_npc_id
        instance._vendor_npc_id = math.max(0, math.floor(npc_id))
        if instance._vendor_npc_id <= 0 and was_replenish_active then
            instance._replenish_active = false
            self:_cancel_inflight_move("replenish-vendor-cleared")
        end
    end
    if settings.vendor_scan_radius ~= nil then
        local radius = tonumber(settings.vendor_scan_radius) or instance._vendor_scan_radius
        instance._vendor_scan_radius = math.max(20.0, math.min(250.0, radius))
    end
    if settings.vendor_interact_range ~= nil then
        local interact_range = tonumber(settings.vendor_interact_range) or instance._vendor_interact_range
        instance._vendor_interact_range = math.max(2.0, math.min(12.0, interact_range))
    end
    if settings.replenish_timeout ~= nil then
        local replenish_timeout = tonumber(settings.replenish_timeout) or instance._replenish_timeout
        instance._replenish_timeout = math.max(20.0, math.min(240.0, replenish_timeout))
    end
    if settings.replenish_cooldown ~= nil then
        local replenish_cooldown = tonumber(settings.replenish_cooldown) or instance._replenish_cooldown
        instance._replenish_cooldown = math.max(0.0, math.min(120.0, replenish_cooldown))
    end
    if settings.auto_vendor_sell_junk ~= nil then
        instance._auto_vendor_sell_junk = settings.auto_vendor_sell_junk == true
    end
    if settings.auto_vendor_repair ~= nil then
        instance._auto_vendor_repair = settings.auto_vendor_repair == true
    end
    if settings.blacklist_ttl ~= nil then
        local blacklist_ttl = tonumber(settings.blacklist_ttl) or instance._blacklist_ttl
        instance._blacklist_ttl = math.max(10.0, math.min(900.0, blacklist_ttl))
    end
    if settings.zone_blacklist_ttl ~= nil then
        local zone_blacklist_ttl = tonumber(settings.zone_blacklist_ttl) or instance._zone_blacklist_ttl
        instance._zone_blacklist_ttl = math.max(10.0, math.min(900.0, zone_blacklist_ttl))
    end
    if settings.zone_blacklist_radius ~= nil then
        local zone_blacklist_radius = tonumber(settings.zone_blacklist_radius) or instance._zone_blacklist_radius
        instance._zone_blacklist_radius = math.max(2.0, math.min(30.0, zone_blacklist_radius))
    end
    if settings.blackspot_radius ~= nil then
        local blackspot_radius = tonumber(settings.blackspot_radius) or instance._blackspot_radius
        instance._blackspot_radius = math.max(3.0, math.min(30.0, blackspot_radius))
    end
    if settings.blackspot_ttl ~= nil then
        local blackspot_ttl = tonumber(settings.blackspot_ttl) or instance._blackspot_ttl
        instance._blackspot_ttl = math.max(0.0, math.min(7200.0, blackspot_ttl))
    end
    if settings.route_radius_min ~= nil then
        local route_radius_min = tonumber(settings.route_radius_min) or instance._route_radius_min
        local clamped = math.max(20.0, math.min(200.0, route_radius_min))
        if math.abs(clamped - instance._route_radius_min) > 0.001 then
            instance._route_radius_min = clamped
            route_geometry_changed = true
        end
    end
    if settings.route_radius_max ~= nil then
        local route_radius_max = tonumber(settings.route_radius_max) or instance._route_radius_max
        local clamped = math.max(40.0, math.min(400.0, route_radius_max))
        if math.abs(clamped - instance._route_radius_max) > 0.001 then
            instance._route_radius_max = clamped
            route_geometry_changed = true
        end
    end
    if instance._route_radius_max < instance._route_radius_min then
        if math.abs(instance._route_radius_max - instance._route_radius_min) > 0.001 then
            route_geometry_changed = true
        end
        instance._route_radius_max = instance._route_radius_min
    end
    if settings.route_expand_step ~= nil then
        local route_expand_step = tonumber(settings.route_expand_step) or instance._route_expand_step
        local clamped = math.max(2.0, math.min(80.0, route_expand_step))
        if math.abs(clamped - instance._route_expand_step) > 0.001 then
            instance._route_expand_step = clamped
            route_geometry_changed = true
        end
    end
    if settings.route_expand_interval ~= nil then
        local route_expand_interval = tonumber(settings.route_expand_interval) or instance._route_expand_interval
        local clamped = math.max(2.0, math.min(90.0, route_expand_interval))
        if math.abs(clamped - instance._route_expand_interval) > 0.001 then
            instance._route_expand_interval = clamped
            route_geometry_changed = true
        end
    end
    if settings.route_profile_refresh_interval ~= nil then
        local route_refresh = tonumber(settings.route_profile_refresh_interval) or instance._route_profile_refresh_interval
        instance._route_profile_refresh_interval = math.max(0.5, math.min(20.0, route_refresh))
    end
    local clamped_route_radius = math.max(instance._route_radius_min, math.min(instance._route_radius_max, instance._route_radius))
    if math.abs(clamped_route_radius - instance._route_radius) > 0.001 then
        instance._route_radius = clamped_route_radius
        route_geometry_changed = true
    end
    if instance._chase_stop_range < instance._pull_range then
        instance._chase_stop_range = instance._pull_range
    end

    if settings.route_mode ~= nil then
        self:set_route_mode(settings.route_mode)
    end

    local route_auto_requested = nil
    if settings.route_auto_profile ~= nil then
        route_auto_requested = settings.route_auto_profile == true
        self:set_route_auto_select(route_auto_requested)
    end

    local auto_enabled = route_auto_requested
    if auto_enabled == nil then
        auto_enabled = self:is_route_auto_select()
    end
    if settings.route_profile_index and not auto_enabled then
        self:set_route_profile_index(settings.route_profile_index)
    end

    if route_geometry_changed and instance._running and instance._route_mode == ROUTE_MODE_CIRCLE then
        local local_player = core.object_manager.get_local_player()
        if local_player and local_player:is_valid() then
            self:_cancel_inflight_move("route-geometry-change")
            self:_build_patrol_route(local_player, true)
        end
    end
end

function GrindBuddy:get_route_profiles()
    local instance = self:get_instance()
    if not instance._route_profiles then
        return {}
    end
    return instance._route_profiles:get_all_profile_descriptors()
end

function GrindBuddy:set_route_profile_index(index)
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return false
    end

    local wanted_index = math.floor(tonumber(index) or -1)
    if wanted_index < 1 then
        return false
    end

    local current_index = manager:get_profile_index_by_id(manager:get_active_profile_id())
    if current_index == wanted_index then
        return true
    end

    local ok = manager:set_profile_by_index(wanted_index)
    if not ok then
        return false
    end

    instance._last_route_profile_id = manager:get_active_profile_id()

    if instance._running and instance._route_mode == ROUTE_MODE_PROFILE then
        local local_player = core.object_manager.get_local_player()
        if local_player and local_player:is_valid() then
            self:_cancel_inflight_move("route-profile-change")
            self:_build_patrol_route(local_player, true)
        end
    end

    return true
end

function GrindBuddy:get_route_profile_index()
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return nil
    end
    local active_id = manager:get_active_profile_id()
    return manager:get_profile_index_by_id(active_id)
end

function GrindBuddy:set_route_auto_select(enabled)
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return
    end

    local next_enabled = enabled == true
    if manager:is_auto_select_enabled() == next_enabled then
        return
    end

    manager:set_auto_select(next_enabled)
    local local_player = core.object_manager.get_local_player()
    if manager:is_auto_select_enabled() and local_player and local_player:is_valid() then
        manager:detect_default_profile(local_player, current_map_id())
        instance._last_route_profile_id = manager:get_active_profile_id()
    end

    if instance._running and instance._route_mode == ROUTE_MODE_PROFILE and local_player and local_player:is_valid() then
        self:_cancel_inflight_move("route-auto-select-change")
        self:_build_patrol_route(local_player, true)
    end
end

function GrindBuddy:is_route_auto_select()
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return true
    end
    return manager:is_auto_select_enabled()
end

function GrindBuddy:get_route_profile_label()
    local instance = self:get_instance()
    local manager = instance._route_profiles
    if not manager then
        return "none"
    end
    return manager:get_active_profile_label()
end

function GrindBuddy:get_route_mode()
    local instance = self:get_instance()
    return instance._route_mode
end

function GrindBuddy:set_route_mode(mode)
    local instance = self:get_instance()
    local parsed = tonumber(mode) or ROUTE_MODE_CIRCLE
    local next_mode = parsed == ROUTE_MODE_PROFILE and ROUTE_MODE_PROFILE or ROUTE_MODE_CIRCLE
    if instance._route_mode == next_mode then
        return
    end

    instance._route_mode = next_mode

    if instance._running then
        local local_player = core.object_manager.get_local_player()
        if local_player and local_player:is_valid() then
            self:_cancel_inflight_move("route-mode-change")
            self:_build_patrol_route(local_player, true)
        end
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
