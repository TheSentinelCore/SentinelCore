---@class FlyBuddy
---@field private _event_bus EventBus
---@field private _state_machine StateMachine
---@field private _profile_mgr ProfileManager|nil
---@field private _movement Movement|nil
---@field private _nav_client Navigation|nil
---@field private _log Logger|nil
---@field private _recording boolean
---@field private _recorded_count number
---@field private _record_start_time number|nil
---@field private _last_sample_time number
---@field private _last_recorded_pos table|nil
---@field private _sample_interval number
---@field private _min_distance number
---@field private _example_profile_path string
---@field private _cruise_altitude number
---@field private _approach_distance number
---@field private _cruise_trigger_distance number
---@field private _midpoint_distance number
---@field private _vertical_deadzone number
---@field private _travel_timeout number
---@field private _traveling boolean
---@field private _travel_target table|nil
---@field private _travel_cruise_z number|nil
---@field private _travel_start_time number|nil
---@field private _travel_callback function|nil
---@field private _vertical_state string
---@field private _collision_flag number|nil
---@field private _forward_probe_distance number
---@field private _forward_probe_min_distance number
---@field private _probe_spread_deg number
---@field private _probe_height_offset number
---@field private _probe_interval number
---@field private _obstacle_altitude_step number
---@field private _obstacle_altitude_decay_per_sec number
---@field private _max_obstacle_altitude_bonus number
---@field private _obstacle_altitude_bonus number
---@field private _probe_blocked boolean
---@field private _last_probe_time number
---@field private _last_control_time number
---@field private _terrain_clearance number
---@field private _ground_sample_interval number
---@field private _last_ground_sample_time number
---@field private _last_ground_height number|nil
---@field private _ground_height_pending boolean
local FlyBuddy = {}
FlyBuddy.__index = FlyBuddy

-- Import dependencies (relative paths since we're in GatherBuddy folder)
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")
local enums = nil
do
    local ok, result = pcall(require, "common/enums")
    if ok then
        enums = result
    end
end

local EVENTS = Constants.EVENTS
local WAYPOINT_TYPES = Constants.WAYPOINT_TYPES

-- Import logger if available
local Logger
local function get_logger()
    if not Logger then
        local success, result = pcall(require, "lib/Logger")
        if success then
            Logger = result
        end
    end
    if Logger then
        return Logger:new("FlyBuddy")
    end
    return nil
end

local function now_iso8601()
    if os and os.date then
        return os.date("!%Y-%m-%dT%H:%M:%SZ")
    end
    return tostring(core.time())
end

local function call_input(name)
    if core and core.input and type(core.input[name]) == "function" then
        core.input[name]()
    end
end

---Create a new FlyBuddy instance
---@param event_bus EventBus
---@param state_machine StateMachine
---@param profile_mgr ProfileManager|nil
---@param movement Movement|nil
---@param nav_client Navigation|nil
---@param config? table
---@return FlyBuddy
function FlyBuddy:new(event_bus, state_machine, profile_mgr, movement, nav_client, config)
    local instance = setmetatable({}, FlyBuddy)

    instance._event_bus = event_bus
    instance._state_machine = state_machine
    instance._profile_mgr = profile_mgr
    instance._movement = movement
    instance._nav_client = nav_client
    instance._log = get_logger()

    config = config or {}
    instance._sample_interval = config.sample_interval or 0.35
    instance._min_distance = config.min_distance or 8.0
    instance._example_profile_path = "gatherbuddy/profiles/fly_example_elwynn.json"

    instance._cruise_altitude = config.cruise_altitude or 22.0
    instance._approach_distance = config.approach_distance or 30.0
    instance._cruise_trigger_distance = config.cruise_trigger_distance or 25.0
    instance._midpoint_distance = config.midpoint_distance or 80.0
    instance._vertical_deadzone = config.vertical_deadzone or 2.5
    instance._travel_timeout = config.travel_timeout or 60.0

    instance._collision_flag = nil
    if enums and enums.collision_flags then
        instance._collision_flag = enums.collision_flags.Collision or enums.collision_flags.LineOfSight
    end
    instance._forward_probe_distance = config.forward_probe_distance or 14.0
    instance._forward_probe_min_distance = config.forward_probe_min_distance or 6.0
    instance._probe_spread_deg = config.probe_spread_deg or 18.0
    instance._probe_height_offset = config.probe_height_offset or 1.2
    instance._probe_interval = config.probe_interval or 0.15
    instance._obstacle_altitude_step = config.obstacle_altitude_step or 6.0
    instance._obstacle_altitude_decay_per_sec = config.obstacle_altitude_decay_per_sec or 8.0
    instance._max_obstacle_altitude_bonus = config.max_obstacle_altitude_bonus or 45.0
    instance._terrain_clearance = config.terrain_clearance or 18.0
    instance._ground_sample_interval = config.ground_sample_interval or 0.8

    instance._recording = false
    instance._recorded_count = 0
    instance._record_start_time = nil
    instance._last_sample_time = 0
    instance._last_recorded_pos = nil

    instance._traveling = false
    instance._travel_target = nil
    instance._travel_cruise_z = nil
    instance._travel_start_time = nil
    instance._travel_callback = nil
    instance._vertical_state = "neutral"
    instance._obstacle_altitude_bonus = 0
    instance._probe_blocked = false
    instance._last_probe_time = 0
    instance._last_control_time = 0
    instance._last_ground_sample_time = 0
    instance._last_ground_height = nil
    instance._ground_height_pending = false

    instance:_setup_subscriptions()
    instance:_ensure_example_profile()

    return instance
end

---Setup event subscriptions
function FlyBuddy:_setup_subscriptions()
    if not self._event_bus then
        return
    end

    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        -- Stop recording silently on bot stop to avoid stale state.
        if self._recording then
            self:stop_recording({ save = false })
        end
        self:_cancel_active_travel("bot_stop", true)
    end, 100, false, "FlyBuddy")
end

---Ensure example flying profile exists on disk
function FlyBuddy:_ensure_example_profile()
    local existing = core.read_data_file(self._example_profile_path)
    if existing and existing ~= "" then
        return
    end

    core.create_data_folder("gatherbuddy")
    core.create_data_folder("gatherbuddy/profiles")

    local example = [[{
  "version": "1.0",
  "metadata": {
    "name": "Fly Example - Elwynn Loop",
    "author": "FlyBuddy",
    "description": "Simple flying loop example with safe altitude waypoints",
    "created": "2026-02-16T00:00:00Z",
    "updated": "2026-02-16T00:00:00Z",
    "game_version": "Classic"
  },
  "requirements": {
    "zone": "Elwynn Forest",
    "map_id": 37,
    "continent_id": 0,
    "requires_flying": true
  },
  "settings": {
    "loop": true,
    "node_search_radius": 80,
    "waypoint_tolerance": 4.0,
    "mount_threshold_distance": 15,
    "skip_if_enemies_near": false,
    "enemy_detection_radius": 20
  },
  "waypoints": [
    { "id": 1, "x": -9456.2, "y": 64.8, "z": 96.0, "type": "path", "note": "Goldshire high start" },
    { "id": 2, "x": -9540.8, "y": 175.6, "z": 108.0, "type": "path" },
    { "id": 3, "x": -9664.9, "y": 256.4, "z": 114.0, "type": "path" },
    { "id": 4, "x": -9738.2, "y": 178.5, "z": 104.0, "type": "path" },
    { "id": 5, "x": -9620.5, "y": 72.4, "z": 100.0, "type": "path" },
    { "id": 6, "x": -9456.2, "y": 64.8, "z": 96.0, "type": "path", "note": "Loop complete" }
  ],
  "blackspots": []
}]]

    core.create_data_file(self._example_profile_path)
    core.write_data_file(self._example_profile_path, example)

    if self._profile_mgr and self._profile_mgr.register_profile then
        self._profile_mgr:register_profile(self._example_profile_path)
    end

    if self._log then
        self._log:info("Installed FlyBuddy example profile: %s", self._example_profile_path)
    end
end

---Record a waypoint into the active profile
---@param pos table
---@param note? string
---@return boolean
function FlyBuddy:_record_waypoint(pos, note)
    if not self._profile_mgr then
        return false
    end

    local id = self._profile_mgr:add_waypoint_at_position(pos, WAYPOINT_TYPES.PATH)
    if not id then
        return false
    end

    local profile = self._profile_mgr:get_current_profile()
    if profile and profile.waypoints and profile.waypoints[#profile.waypoints] and note then
        profile.waypoints[#profile.waypoints].note = note
    end

    self._recorded_count = self._recorded_count + 1
    return true
end

---Start recording a flying route from player movement
---@param options? table {name, description, map_id, continent_id, zone, min_distance, sample_interval}
---@return boolean success, string|nil message
function FlyBuddy:start_recording(options)
    options = options or {}

    if self._recording then
        return false, "already_recording"
    end

    if not self._profile_mgr then
        return false, "profile_manager_unavailable"
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false, "player_unavailable"
    end

    local pos = player:get_position()
    if not pos then
        return false, "player_position_unavailable"
    end

    local name = options.name or ("Fly Route " .. tostring(math.floor(core.time())))
    local description = options.description or "Recorded by FlyBuddy"

    self._profile_mgr:create_empty_profile({
        name = name,
        author = "FlyBuddy",
        description = description,
        map_id = options.map_id or 0,
        continent_id = options.continent_id or 0,
        zone = options.zone,
        requires_flying = true,
        loop = options.loop ~= false,
    })

    if options.sample_interval and options.sample_interval > 0 then
        self._sample_interval = options.sample_interval
    end
    if options.min_distance and options.min_distance > 0 then
        self._min_distance = options.min_distance
    end

    self._recorded_count = 0
    local first_ok = self:_record_waypoint(pos, "Record start - " .. now_iso8601())
    if not first_ok then
        return false, "failed_to_record_first_waypoint"
    end

    self._recording = true
    self._record_start_time = core.time()
    self._last_sample_time = self._record_start_time
    self._last_recorded_pos = { x = pos.x, y = pos.y, z = pos.z }

    if self._log then
        self._log:info("Fly recording started: %s", name)
    end

    return true, nil
end

---Stop recording and optionally save to disk
---@param options? table {save, path}
---@return boolean success, string|nil path_or_error
function FlyBuddy:stop_recording(options)
    options = options or {}

    if not self._recording then
        return false, "not_recording"
    end

    -- Capture the final position when stopping.
    local player = core.object_manager.get_local_player()
    if player and player:is_valid() then
        local pos = player:get_position()
        if pos and self._last_recorded_pos then
            local dist = Helpers.distance_3d(self._last_recorded_pos, pos)
            if dist >= 1.0 then
                self:_record_waypoint(pos, "Record stop - " .. now_iso8601())
            end
        end
    end

    self._recording = false
    local elapsed = self._record_start_time and (core.time() - self._record_start_time) or 0
    self._record_start_time = nil
    self._last_recorded_pos = nil

    if self._log then
        self._log:info("Fly recording stopped: %d waypoints in %.1fs", self._recorded_count, elapsed)
    end

    local should_save = options.save
    if should_save == nil then
        should_save = true
    end

    if should_save then
        if not self._profile_mgr then
            return false, "profile_manager_unavailable"
        end

        local ok, path_or_err = self._profile_mgr:save_current_profile(options.path)
        if not ok then
            return false, path_or_err or "save_failed"
        end
        return true, path_or_err
    end

    return true, nil
end

---Load the bundled example flying profile
---@return boolean success
function FlyBuddy:load_example_profile()
    if not self._profile_mgr then
        return false
    end

    self:_ensure_example_profile()
    return self._profile_mgr:load_profile(self._example_profile_path)
end

---Check whether the currently loaded profile requires flying.
---@return boolean
function FlyBuddy:is_flying_profile()
    if not self._profile_mgr then
        return false
    end

    local profile = self._profile_mgr:get_current_profile()
    return profile
        and profile.requirements
        and profile.requirements.requires_flying == true
        or false
end

---Apply vertical movement key state.
---@param state string "up"|"down"|"neutral"
function FlyBuddy:_set_vertical_state(state)
    if state == self._vertical_state then
        return
    end

    if state == "up" then
        call_input("move_down_stop")
        call_input("move_up_start")
    elseif state == "down" then
        call_input("move_up_stop")
        call_input("move_down_start")
    else
        state = "neutral"
        call_input("move_up_stop")
        call_input("move_down_stop")
    end

    self._vertical_state = state
end

---Get the currently active movement target (next waypoint if available).
---@return table|nil
function FlyBuddy:_get_active_flight_target()
    if self._movement and self._movement.get_current_path and self._movement.get_path_index then
        local path = self._movement:get_current_path()
        if path and #path > 0 then
            local idx = self._movement:get_path_index() or 1
            local point = path[idx] or path[#path]
            if point then
                return { x = point.x, y = point.y, z = point.z }
            end
        end
    end
    return self._travel_target
end

---Trace a line and return whether the segment is clear.
---@param origin table
---@param destination table
---@return boolean
function FlyBuddy:_trace_is_clear(origin, destination)
    if not self._collision_flag then
        return true
    end

    local ok, result = pcall(core.graphics.trace_line, origin, destination, self._collision_flag)
    if not ok then
        return true
    end

    -- In this runtime: true means clear, false means blocked.
    return result == true
end

---Probe ahead with center/left/right rays to detect obstacles.
---@param from_pos table
---@param target_pos table
---@param probe_distance number
---@return boolean blocked
function FlyBuddy:_probe_forward_blocked(from_pos, target_pos, probe_distance)
    if not self._collision_flag then
        return false
    end
    if not from_pos or not target_pos then
        return false
    end

    local dx = (target_pos.x or 0) - (from_pos.x or 0)
    local dy = (target_pos.y or 0) - (from_pos.y or 0)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then
        return false
    end

    dx = dx / len
    dy = dy / len

    local dist = math.min(probe_distance or self._forward_probe_distance, len)
    if dist < 1.0 then
        return false
    end
    local origin = {
        x = from_pos.x,
        y = from_pos.y,
        z = (from_pos.z or 0) + self._probe_height_offset,
    }

    local spread_rad = math.rad(self._probe_spread_deg)
    local cos_s = math.cos(spread_rad)
    local sin_s = math.sin(spread_rad)

    local dirs = {
        { dx = dx, dy = dy },
        { dx = dx * cos_s - dy * sin_s, dy = dx * sin_s + dy * cos_s },
        { dx = dx * cos_s + dy * sin_s, dy = -dx * sin_s + dy * cos_s },
    }

    for i = 1, #dirs do
        local dir = dirs[i]
        local probe_end = {
            x = origin.x + dir.dx * dist,
            y = origin.y + dir.dy * dist,
            z = origin.z,
        }
        if not self:_trace_is_clear(origin, probe_end) then
            return true
        end
    end

    return false
end

---Refresh navmesh ground height (async) near current position.
---@param pos table
---@param now number
function FlyBuddy:_refresh_ground_height(pos, now)
    if not self._nav_client or not self._nav_client.get_height then
        return
    end
    if self._ground_height_pending then
        return
    end
    if (now - self._last_ground_sample_time) < self._ground_sample_interval then
        return
    end

    self._last_ground_sample_time = now
    self._ground_height_pending = true

    self._nav_client:get_height(pos, function(ok, data, _err)
        self._ground_height_pending = false
        if ok and data and type(data.height) == "number" then
            self._last_ground_height = data.height
        end
    end)
end

---Compute a safe cruise altitude between two points.
---@param from_pos table
---@param target table
---@return number
function FlyBuddy:_compute_cruise_altitude(from_pos, target)
    local highest = math.max(from_pos.z or 0, target.z or 0)
    return highest + self._cruise_altitude
end

---Build a basic 3D flight path with one or two cruise waypoints.
---@param from_pos table
---@param target table
---@param cruise_z number
---@return table
function FlyBuddy:_build_flight_path(from_pos, target, cruise_z)
    local distance_2d = Helpers.distance_2d(from_pos, target)
    local path = {}

    if distance_2d >= self._cruise_trigger_distance then
        local first = Helpers.lerp_vec3(from_pos, target, 0.35)
        first.z = cruise_z
        path[#path + 1] = first

        if distance_2d >= self._midpoint_distance then
            local second = Helpers.lerp_vec3(from_pos, target, 0.70)
            second.z = cruise_z
            path[#path + 1] = second
        end
    end

    path[#path + 1] = { x = target.x, y = target.y, z = target.z }
    return path
end

---Finalize active travel and trigger callback once.
---@param success boolean
---@param reason string|nil
function FlyBuddy:_complete_travel(success, reason)
    if not self._traveling and not self._travel_callback then
        return
    end

    local callback = self._travel_callback

    self._traveling = false
    self._travel_target = nil
    self._travel_cruise_z = nil
    self._travel_start_time = nil
    self._travel_callback = nil
    self:_set_vertical_state("neutral")
    self._obstacle_altitude_bonus = 0
    self._probe_blocked = false
    self._last_probe_time = 0
    self._last_control_time = 0
    self._last_ground_height = nil
    self._ground_height_pending = false

    if callback then
        local ok, err = pcall(callback, success, reason)
        if not ok and self._log then
            self._log:error("Fly travel callback error: %s", tostring(err))
        end
    end
end

---Cancel current travel.
---@param reason? string
---@param silent? boolean
function FlyBuddy:_cancel_active_travel(reason, silent)
    if not self._traveling and not self._travel_callback then
        self:_set_vertical_state("neutral")
        return
    end

    if self._movement and self._movement.stop then
        self._movement:stop()
    end

    if silent then
        self._traveling = false
        self._travel_target = nil
        self._travel_cruise_z = nil
        self._travel_start_time = nil
        self._travel_callback = nil
        self:_set_vertical_state("neutral")
        self._obstacle_altitude_bonus = 0
        self._probe_blocked = false
        self._last_probe_time = 0
        self._last_control_time = 0
        self._last_ground_height = nil
        self._ground_height_pending = false
        return
    end

    self:_complete_travel(false, reason or "travel_cancelled")
end

---Update up/down assistance while following a fly route.
function FlyBuddy:_update_travel_controls()
    if not self._traveling or not self._travel_target then
        return
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        self:_cancel_active_travel("player_unavailable")
        return
    end

    if player.is_mounted and not player:is_mounted() then
        self:_set_vertical_state("neutral")
        return
    end

    if self._travel_start_time and (core.time() - self._travel_start_time) > self._travel_timeout then
        self:_cancel_active_travel("fly_timeout")
        return
    end

    local pos = player:get_position()
    if not pos then
        return
    end

    local now = core.time()
    local dt = 0.05
    if self._last_control_time > 0 then
        dt = math.max(0.01, now - self._last_control_time)
    end
    self._last_control_time = now

    local active_target = self:_get_active_flight_target()
    if not active_target then
        self:_cancel_active_travel("target_unavailable")
        return
    end

    local distance_2d = Helpers.distance_2d(pos, active_target)
    local desired_z = self._travel_target.z
    if self._travel_cruise_z and distance_2d > self._approach_distance then
        desired_z = self._travel_cruise_z
        self:_refresh_ground_height(pos, now)
        if self._last_ground_height then
            desired_z = math.max(desired_z, self._last_ground_height + self._terrain_clearance)
        end
    end

    if (now - self._last_probe_time) >= self._probe_interval then
        self._last_probe_time = now
        local probe_dist = math.min(self._forward_probe_distance, distance_2d)
        if probe_dist >= self._forward_probe_min_distance then
            self._probe_blocked = self:_probe_forward_blocked(pos, active_target, probe_dist)
            if self._probe_blocked then
                self._obstacle_altitude_bonus = math.min(
                    self._max_obstacle_altitude_bonus,
                    self._obstacle_altitude_bonus + self._obstacle_altitude_step
                )
            end
        else
            self._probe_blocked = false
        end
    end

    if not self._probe_blocked then
        local decay = self._obstacle_altitude_decay_per_sec * dt
        self._obstacle_altitude_bonus = math.max(0, self._obstacle_altitude_bonus - decay)
    end

    if self._obstacle_altitude_bonus > 0 then
        desired_z = (desired_z or 0) + self._obstacle_altitude_bonus
    end

    local z_error = (desired_z or 0) - (pos.z or 0)
    if self._probe_blocked and z_error < self._vertical_deadzone then
        z_error = self._vertical_deadzone + 0.1
    end

    if z_error > self._vertical_deadzone then
        self:_set_vertical_state("up")
    elseif z_error < -self._vertical_deadzone then
        self:_set_vertical_state("down")
    else
        self:_set_vertical_state("neutral")
    end
end

---Move to a waypoint in fly mode (no ground navmesh validation).
---@param waypoint table
---@param callback? fun(success: boolean, reason: string|nil)
---@return boolean started, string|nil reason
function FlyBuddy:travel_to_waypoint(waypoint, callback)
    if not self._movement or not self._movement.follow_path then
        return false, "movement_unavailable"
    end

    if not waypoint or waypoint.x == nil or waypoint.y == nil or waypoint.z == nil then
        return false, "invalid_waypoint"
    end

    if self._traveling or (self._movement.is_moving and self._movement:is_moving()) then
        return false, "movement_busy"
    end

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return false, "player_unavailable"
    end

    local from_pos = player:get_position()
    if not from_pos then
        return false, "player_position_unavailable"
    end

    local target = { x = waypoint.x, y = waypoint.y, z = waypoint.z }
    local distance_2d = Helpers.distance_2d(from_pos, target)

    local cruise_z = nil
    local path
    if distance_2d >= self._cruise_trigger_distance then
        cruise_z = self:_compute_cruise_altitude(from_pos, target)
        path = self:_build_flight_path(from_pos, target, cruise_z)
    else
        path = { target }
    end

    self._traveling = true
    self._travel_target = target
    self._travel_cruise_z = cruise_z
    self._travel_start_time = core.time()
    self._travel_callback = callback
    self:_set_vertical_state("neutral")
    self._obstacle_altitude_bonus = 0
    self._probe_blocked = false
    self._last_probe_time = 0
    self._last_control_time = self._travel_start_time
    self._last_ground_sample_time = 0
    self._last_ground_height = nil
    self._ground_height_pending = false

    if self._log then
        self._log:debug(
            "Fly travel start -> wp #%s (%.1f, %.1f, %.1f) via %d points",
            tostring(waypoint.id or "?"),
            target.x, target.y, target.z,
            #path
        )
    end

    self._movement:follow_path(path, function(success, reason)
        self:_complete_travel(success, reason)
    end)

    return true, nil
end

---Update recording and travel loops
function FlyBuddy:update()
    if self._traveling then
        self:_update_travel_controls()
    end

    if not self._recording then
        return
    end

    local now = core.time()
    if now - self._last_sample_time < self._sample_interval then
        return
    end
    self._last_sample_time = now

    local player = core.object_manager.get_local_player()
    if not player or not player:is_valid() then
        return
    end

    local pos = player:get_position()
    if not pos then
        return
    end

    if not self._last_recorded_pos then
        if self:_record_waypoint(pos) then
            self._last_recorded_pos = { x = pos.x, y = pos.y, z = pos.z }
        end
        return
    end

    local dist = Helpers.distance_3d(self._last_recorded_pos, pos)
    if dist >= self._min_distance then
        if self:_record_waypoint(pos) then
            self._last_recorded_pos = { x = pos.x, y = pos.y, z = pos.z }
        end
    end
end

---Get module status
---@return table
function FlyBuddy:get_status()
    return {
        recording = self._recording,
        recorded_waypoints = self._recorded_count,
        sample_interval = self._sample_interval,
        min_distance = self._min_distance,
        flying_profile = self:is_flying_profile(),
        traveling = self._traveling,
        vertical_state = self._vertical_state,
        cruise_altitude = self._cruise_altitude,
        obstacle_blocked = self._probe_blocked,
        obstacle_altitude_bonus = self._obstacle_altitude_bonus,
        last_ground_height = self._last_ground_height,
    }
end

---Check if currently recording
---@return boolean
function FlyBuddy:is_recording()
    return self._recording
end

---Clean up resources
function FlyBuddy:destroy()
    self:_cancel_active_travel("destroy", true)
    if self._event_bus then
        self._event_bus:unsubscribe_by_owner("FlyBuddy")
    end
end

return FlyBuddy
