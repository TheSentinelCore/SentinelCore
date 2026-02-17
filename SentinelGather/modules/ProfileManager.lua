---@class ProfileMetadata
---@field name string
---@field author string|nil
---@field description string|nil
---@field game_version string|nil
---@field estimated_time_minutes number|nil

---@class ProfileRequirements
---@field min_skill table|nil
---@field zone string|nil
---@field map_id number
---@field continent_id number|nil Navigation map ID (0=Eastern Kingdoms, 1=Kalimdor, etc.)
---@field requires_flying boolean|nil

---@class ProfileSettings
---@field loop boolean
---@field node_search_radius number|nil
---@field waypoint_tolerance number|nil
---@field mount_threshold_distance number|nil
---@field enemy_detection_radius number|nil
---@field skip_if_enemies_near boolean|nil

---@class Waypoint
---@field id number
---@field x number
---@field y number
---@field z number
---@field type string
---@field radius number|nil
---@field linger_time number|nil
---@field note string|nil

---@class Blackspot
---@field x number
---@field y number
---@field z number
---@field radius number
---@field reason string|nil

---@class Profile
---@field version string
---@field metadata ProfileMetadata
---@field requirements ProfileRequirements
---@field settings ProfileSettings
---@field waypoints Waypoint[]
---@field blackspots Blackspot[]|nil
---@field vendors table[]|nil
---@field mailboxes table[]|nil

---@class ProfileManager
---@field private _event_bus EventBus
---@field private _current_profile Profile|nil
---@field private _current_waypoint_index number
---@field private _available_profiles string[]
---@field private _log Logger|nil
local ProfileManager = {}
ProfileManager.__index = ProfileManager

-- Import dependencies (relative paths since we're in SentinelGather folder)
local JSON = require("lib/JSON")
local Helpers = require("lib/Helpers")
local Constants = require("core/Constants")

local EVENTS = Constants.EVENTS
local WAYPOINT_TYPES = Constants.WAYPOINT_TYPES

-- Profile storage path
local PROFILES_PATH = "profiles"

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
        return Logger:new("ProfileManager")
    end
    return nil
end

---Create a new ProfileManager instance
---@param event_bus EventBus
---@return ProfileManager
function ProfileManager:new(event_bus)
    local instance = setmetatable({}, ProfileManager)

    instance._event_bus = event_bus
    instance._current_profile = nil
    instance._current_waypoint_index = 1
    instance._available_profiles = {}
    instance._log = get_logger()
    instance._loops_completed = 0
    instance._route_start_time = nil

    instance:_setup_subscriptions()

    -- Ensure example profiles exist
    instance:ensure_profiles_exist()

    return instance
end

---Setup event subscriptions
function ProfileManager:_setup_subscriptions()
    if not self._event_bus then return end

    self._event_bus:subscribe(EVENTS.PROFILE_LOAD_REQUEST, function(data)
        if data and data.path then
            self:load_profile(data.path)
        end
    end, 100, false, "ProfileManager")

    self._event_bus:subscribe(EVENTS.BOT_STOP, function()
        -- Don't unload profile on stop, just reset progress
        self._current_waypoint_index = 1
        self._loops_completed = 0
        self._route_start_time = nil
    end, 100, false, "ProfileManager")
end

---Load a profile from file
---@param path string Profile file path (relative to scripts_data/)
---@return boolean success
function ProfileManager:load_profile(path)
    if self._log then
        self._log:info("Loading profile: %s", path)
    end

    -- Read file
    local json_str = core.read_data_file(path)
    if not json_str or json_str == "" then
        local error_msg = "Profile file not found: " .. path
        if self._log then
            self._log:error(error_msg)
        end
        self:_publish_load_failed(path, {error_msg})
        return false
    end

    -- Parse JSON
    local data, parse_err = JSON.decode(json_str)
    if not data then
        local error_msg = "Failed to parse profile JSON: " .. tostring(parse_err)
        if self._log then
            self._log:error(error_msg)
        end
        self:_publish_load_failed(path, {error_msg})
        return false
    end

    -- Log parsed requirements at debug level
    if self._log and data.requirements then
        local keys = {}
        for k, v in pairs(data.requirements) do
            keys[#keys + 1] = k .. "=" .. tostring(v)
        end
        self._log:debug("Profile requirements: %s", table.concat(keys, ", "))
    end

    -- Validate profile
    local valid, errors = self:validate_profile(data)
    if not valid then
        if self._log then
            self._log:error("Profile validation failed: %d errors", #errors)
            for _, err in ipairs(errors) do
                self._log:error("  - %s", err)
            end
        end
        self:_publish_load_failed(path, errors)
        return false
    end

    -- Store profile
    self._current_profile = data
    self._current_waypoint_index = 1
    self._loops_completed = 0
    self._route_start_time = core.time()

    if self._log then
        self._log:info("Profile loaded: %s (%d waypoints)",
            data.metadata and data.metadata.name or "Unknown",
            #data.waypoints)
    end

    -- Publish success event
    if self._event_bus then
        self._event_bus:publish(EVENTS.PROFILE_LOADED, {
            name = data.metadata and data.metadata.name or "Unknown",
            path = path,
            waypoint_count = #data.waypoints,
            map_id = data.requirements and data.requirements.map_id or 0,
            profile = data
        })
    end

    return true
end

---Publish load failed event
function ProfileManager:_publish_load_failed(path, errors)
    if self._event_bus then
        self._event_bus:publish(EVENTS.PROFILE_LOAD_FAILED, {
            path = path,
            errors = errors
        })
    end
end

---Validate a profile structure
---@param data table Profile data to validate
---@return boolean valid, string[] errors
function ProfileManager:validate_profile(data)
    local errors = {}

    -- Check required fields
    if not data.version then
        table.insert(errors, "Missing required field: version")
    end

    if not data.waypoints or type(data.waypoints) ~= "table" then
        table.insert(errors, "Missing or invalid required field: waypoints")
    elseif #data.waypoints == 0 then
        table.insert(errors, "Profile must have at least one waypoint")
    end

    if not data.requirements then
        table.insert(errors, "Missing required field: requirements")
    elseif not data.requirements.map_id then
        table.insert(errors, "Missing required field: requirements.map_id")
    end

    -- Validate waypoints
    if data.waypoints and type(data.waypoints) == "table" then
        for i, wp in ipairs(data.waypoints) do
            local wp_errors = self:_validate_waypoint(wp, i)
            for _, err in ipairs(wp_errors) do
                table.insert(errors, err)
            end
        end
    end

    -- Validate blackspots if present
    if data.blackspots and type(data.blackspots) == "table" then
        for i, bs in ipairs(data.blackspots) do
            if not bs.x or not bs.z or not bs.radius then
                table.insert(errors, string.format("Blackspot %d: missing x, z, or radius", i))
            end
        end
    end

    return #errors == 0, errors
end

---Validate a single waypoint
---@param wp table Waypoint data
---@param index number Waypoint index (for error messages)
---@return string[] errors
function ProfileManager:_validate_waypoint(wp, index)
    local errors = {}
    local prefix = string.format("Waypoint %d", index)

    if wp.x == nil then
        table.insert(errors, prefix .. ": missing x coordinate")
    end
    if wp.y == nil then
        table.insert(errors, prefix .. ": missing y coordinate")
    end
    if wp.z == nil then
        table.insert(errors, prefix .. ": missing z coordinate")
    end
    if not wp.type then
        table.insert(errors, prefix .. ": missing type")
    elseif not self:_is_valid_waypoint_type(wp.type) then
        table.insert(errors, prefix .. ": invalid type '" .. wp.type .. "'")
    end

    -- Hotspots should have radius
    if wp.type == WAYPOINT_TYPES.HOTSPOT and not wp.radius then
        table.insert(errors, prefix .. ": hotspot missing radius")
    end

    return errors
end

---Check if a waypoint type is valid
---@param type_name string
---@return boolean
function ProfileManager:_is_valid_waypoint_type(type_name)
    for _, valid_type in pairs(WAYPOINT_TYPES) do
        if type_name == valid_type then
            return true
        end
    end
    return false
end

---Unload the current profile
function ProfileManager:unload_profile()
    if self._current_profile and self._log then
        self._log:info("Unloading profile: %s",
            self._current_profile.metadata and self._current_profile.metadata.name or "Unknown")
    end

    self._current_profile = nil
    self._current_waypoint_index = 1
    self._loops_completed = 0
    self._route_start_time = nil

    if self._event_bus then
        self._event_bus:publish(EVENTS.PROFILE_UNLOADED, {})
    end
end

---Get the current profile
---@return Profile|nil
function ProfileManager:get_current_profile()
    return self._current_profile
end

---Check if a profile is loaded
---@return boolean
function ProfileManager:is_profile_loaded()
    return self._current_profile ~= nil
end

---Get the current waypoint
---@return Waypoint|nil
function ProfileManager:get_current_waypoint()
    if not self._current_profile or not self._current_profile.waypoints then
        return nil
    end

    return self._current_profile.waypoints[self._current_waypoint_index]
end

---Get the current waypoint index
---@return number
function ProfileManager:get_current_waypoint_index()
    return self._current_waypoint_index
end

---Get total waypoint count
---@return number
function ProfileManager:get_waypoint_count()
    if not self._current_profile or not self._current_profile.waypoints then
        return 0
    end
    return #self._current_profile.waypoints
end

---Advance to the next waypoint
---@return Waypoint|nil next_waypoint
function ProfileManager:advance_waypoint()
    if not self._current_profile then
        return nil
    end

    local current = self:get_current_waypoint()
    local is_hotspot = current and current.type == WAYPOINT_TYPES.HOTSPOT

    -- Publish waypoint reached event
    if self._event_bus and current then
        self._event_bus:publish(EVENTS.WAYPOINT_REACHED, {
            waypoint = current,
            index = self._current_waypoint_index,
            is_last = self._current_waypoint_index >= #self._current_profile.waypoints
        })

        -- If leaving a hotspot, publish hotspot exited
        if is_hotspot then
            self._event_bus:publish(EVENTS.HOTSPOT_EXITED, {
                waypoint = current,
                time_spent = 0 -- Could track this if needed
            })
        end
    end

    -- Move to next waypoint
    self._current_waypoint_index = self._current_waypoint_index + 1

    -- Handle end of route
    if self._current_waypoint_index > #self._current_profile.waypoints then
        self._loops_completed = self._loops_completed + 1

        -- Check if should loop
        local should_loop = self._current_profile.settings and
                           self._current_profile.settings.loop

        if should_loop then
            self._current_waypoint_index = 1
            if self._log then
                self._log:info("Route completed, looping (loop %d)", self._loops_completed)
            end
        else
            if self._log then
                self._log:info("Route completed, stopping")
            end
        end

        -- Publish route completed
        if self._event_bus then
            self._event_bus:publish(EVENTS.ROUTE_COMPLETED, {
                total_time = self._route_start_time and (core.time() - self._route_start_time) or 0,
                loops_completed = self._loops_completed
            })
        end

        if not should_loop then
            return nil
        end
    end

    local next_wp = self:get_current_waypoint()

    -- If entering a hotspot, publish event
    if next_wp and next_wp.type == WAYPOINT_TYPES.HOTSPOT and self._event_bus then
        self._event_bus:publish(EVENTS.HOTSPOT_ENTERED, {
            waypoint = next_wp,
            radius = next_wp.radius or 30,
            linger_time = next_wp.linger_time or 5
        })
    end

    return next_wp
end

---Set current waypoint index directly
---@param index number
---@return boolean success
function ProfileManager:set_waypoint_index(index)
    if not self._current_profile then
        return false
    end

    if index < 1 or index > #self._current_profile.waypoints then
        return false
    end

    self._current_waypoint_index = index
    return true
end

---Add a new waypoint to the current profile
---@param waypoint Waypoint|table Waypoint data (x, y, z required; id auto-generated if missing)
---@return number|nil id The ID of the added waypoint, or nil if failed
function ProfileManager:add_waypoint(waypoint)
    -- Ensure we have a profile (create empty one if needed)
    if not self._current_profile then
        self._current_profile = {
            version = "1.0",
            metadata = { name = "Custom Route", author = "User" },
            requirements = { map_id = 0, continent_id = 0 },
            settings = { loop = true },
            waypoints = {}
        }
        if self._log then
            self._log:info("Created new empty profile for waypoint management")
        end
    end

    -- Ensure waypoints array exists
    if not self._current_profile.waypoints then
        self._current_profile.waypoints = {}
    end

    -- Validate required fields
    if waypoint.x == nil or waypoint.y == nil or waypoint.z == nil then
        if self._log then
            self._log:error("Cannot add waypoint: missing x, y, or z coordinate")
        end
        return nil
    end

    -- Generate ID if not provided (find max ID and add 1)
    if not waypoint.id then
        local max_id = 0
        for _, wp in ipairs(self._current_profile.waypoints) do
            if wp.id and wp.id > max_id then
                max_id = wp.id
            end
        end
        waypoint.id = max_id + 1
    end

    -- Default type to "path" if not specified
    if not waypoint.type then
        waypoint.type = WAYPOINT_TYPES.PATH
    end

    -- Validate waypoint type
    if not self:_is_valid_waypoint_type(waypoint.type) then
        if self._log then
            self._log:error("Cannot add waypoint: invalid type '%s'", waypoint.type)
        end
        return nil
    end

    -- Hotspots need radius
    if waypoint.type == WAYPOINT_TYPES.HOTSPOT and not waypoint.radius then
        waypoint.radius = 30  -- Default radius
    end

    -- Insert at end of waypoints array
    table.insert(self._current_profile.waypoints, waypoint)

    if self._log then
        self._log:info("Added waypoint #%d at (%.1f, %.1f, %.1f) type=%s",
            waypoint.id, waypoint.x, waypoint.y, waypoint.z, waypoint.type)
    end

    -- Publish event
    if self._event_bus then
        self._event_bus:publish(EVENTS.WAYPOINT_ADDED, {
            waypoint = waypoint,
            index = #self._current_profile.waypoints,
            total_count = #self._current_profile.waypoints
        })
    end

    return waypoint.id
end

---Add a new waypoint at a position (convenience method)
---@param pos vec3|table Position {x, y, z}
---@param wp_type? string Waypoint type ("path" or "hotspot"), defaults to "path"
---@param radius? number Radius for hotspots
---@return number|nil id The ID of the added waypoint
function ProfileManager:add_waypoint_at_position(pos, wp_type, radius)
    if not pos or pos.x == nil or pos.y == nil or pos.z == nil then
        if self._log then
            self._log:error("Cannot add waypoint: invalid position")
        end
        return nil
    end

    local waypoint = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        type = wp_type or WAYPOINT_TYPES.PATH,
        radius = radius
    }

    return self:add_waypoint(waypoint)
end

---Remove a waypoint by ID or index
---@param id_or_index number Waypoint ID or array index
---@param by_id? boolean If true, treat as ID; if false, treat as index (default: true)
---@return boolean success
function ProfileManager:remove_waypoint(id_or_index, by_id)
    if not self._current_profile or not self._current_profile.waypoints then
        if self._log then
            self._log:error("Cannot remove waypoint: no profile loaded")
        end
        return false
    end

    if by_id == nil then
        by_id = true  -- Default to ID-based removal
    end

    local remove_index = nil
    local removed_waypoint = nil

    if by_id then
        -- Find waypoint by ID
        for i, wp in ipairs(self._current_profile.waypoints) do
            if wp.id == id_or_index then
                remove_index = i
                removed_waypoint = wp
                break
            end
        end
    else
        -- Treat as array index
        if id_or_index >= 1 and id_or_index <= #self._current_profile.waypoints then
            remove_index = id_or_index
            removed_waypoint = self._current_profile.waypoints[id_or_index]
        end
    end

    if not remove_index then
        if self._log then
            self._log:error("Cannot remove waypoint: not found (id_or_index=%d, by_id=%s)",
                id_or_index, tostring(by_id))
        end
        return false
    end

    -- Remove from array
    table.remove(self._current_profile.waypoints, remove_index)

    -- Adjust current waypoint index if needed
    if self._current_waypoint_index > #self._current_profile.waypoints then
        self._current_waypoint_index = math.max(1, #self._current_profile.waypoints)
    elseif self._current_waypoint_index > remove_index then
        self._current_waypoint_index = self._current_waypoint_index - 1
    end

    if self._log then
        self._log:info("Removed waypoint #%d (was at index %d), %d waypoints remaining",
            removed_waypoint.id or 0, remove_index, #self._current_profile.waypoints)
    end

    -- Publish event
    if self._event_bus then
        self._event_bus:publish(EVENTS.WAYPOINT_REMOVED, {
            waypoint = removed_waypoint,
            removed_index = remove_index,
            total_count = #self._current_profile.waypoints
        })
    end

    return true
end

---Clear all waypoints from the current profile
---@return boolean success
function ProfileManager:clear_waypoints()
    if not self._current_profile then
        if self._log then
            self._log:error("Cannot clear waypoints: no profile loaded")
        end
        return false
    end

    local count = self._current_profile.waypoints and #self._current_profile.waypoints or 0

    -- Clear waypoints array
    self._current_profile.waypoints = {}

    -- Reset index
    self._current_waypoint_index = 1

    if self._log then
        self._log:info("Cleared %d waypoints", count)
    end

    -- Publish event
    if self._event_bus then
        self._event_bus:publish(EVENTS.WAYPOINTS_CLEARED, {
            cleared_count = count
        })
    end

    return true
end

---Find the nearest waypoint to a position
---@param pos table|vec3 Position to search from
---@return Waypoint|nil waypoint, number|nil index
function ProfileManager:get_nearest_waypoint(pos)
    if not self._current_profile or not pos then
        return nil, nil
    end

    local nearest_wp = nil
    local nearest_index = nil
    local nearest_dist = math.huge

    for i, wp in ipairs(self._current_profile.waypoints) do
        local wp_pos = { x = wp.x, y = wp.y, z = wp.z }
        local dist = Helpers.distance_3d(pos, wp_pos)

        if dist < nearest_dist then
            nearest_dist = dist
            nearest_wp = wp
            nearest_index = i
        end
    end

    return nearest_wp, nearest_index
end

---Check if a position is within any blackspot
---@param pos table|vec3 Position to check
---@return boolean is_blacklisted
function ProfileManager:is_in_blackspot(pos)
    if not self._current_profile or not self._current_profile.blackspots or not pos then
        return false
    end

    for _, bs in ipairs(self._current_profile.blackspots) do
        local bs_pos = { x = bs.x, y = bs.y, z = bs.z }
        local dist = Helpers.distance_3d(pos, bs_pos)

        if dist <= bs.radius then
            return true
        end
    end

    return false
end

---Get a profile setting with fallback to defaults
---@param key string Setting key
---@param default any Default value
---@return any
function ProfileManager:get_setting(key, default)
    if not self._current_profile or not self._current_profile.settings then
        return default
    end

    local value = self._current_profile.settings[key]
    if value == nil then
        return default
    end

    return value
end

---List available profile files
---@return string[] profile_paths
function ProfileManager:list_available_profiles()
    -- Note: Since Sylvannas doesn't have a directory listing API,
    -- we need to maintain a list or check for known profiles
    -- For now, return cached list or empty

    -- This would need to be populated by scanning the directory
    -- which would require either:
    -- 1. A manifest file listing profiles
    -- 2. Or iterating through known profile paths

    return self._available_profiles
end

---Add a profile to the available list
---@param path string Profile path
function ProfileManager:register_profile(path)
    if not Helpers.table_contains(self._available_profiles, path) then
        table.insert(self._available_profiles, path)
    end
end

---Get loops completed
---@return number
function ProfileManager:get_loops_completed()
    return self._loops_completed
end

---Get route start time
---@return number|nil
function ProfileManager:get_route_start_time()
    return self._route_start_time
end

---Install example profiles to scripts_data folder
---@return boolean success
function ProfileManager:install_example_profiles()
    -- Create the profiles directory
    core.create_data_folder("gatherbuddy")
    core.create_data_folder("gatherbuddy/profiles")

    -- Example profile: Elwynn Forest
    -- Coordinates use Sylvannas/WoW format: X=north-south, Y=west-east, Z=height
    local example_profile = [[{
  "version": "1.0",
  "metadata": {
    "name": "Elwynn Forest - Copper & Peacebloom",
    "author": "SentinelGather",
    "description": "Starter zone route around Goldshire",
    "game_version": "Classic"
  },
  "requirements": {
    "min_skill": { "mining": 1, "herbalism": 1 },
    "zone": "Elwynn Forest",
    "map_id": 37,
    "continent_id": 0,
    "requires_flying": false
  },
  "settings": {
    "loop": true,
    "node_search_radius": 80,
    "waypoint_tolerance": 3.0,
    "mount_threshold_distance": 40,
    "skip_if_enemies_near": true,
    "enemy_detection_radius": 25
  },
  "filters": {
    "gather_types": ["herb", "ore"]
  },
  "waypoints": [
    { "id": 1, "x": -9456.2, "y": 64.8, "z": 56.0, "type": "path", "note": "Start at Goldshire" },
    { "id": 2, "x": -9502.3, "y": 85.7, "z": 58.1, "type": "hotspot", "radius": 35, "linger_time": 6 },
    { "id": 3, "x": -9545.8, "y": 110.2, "z": 59.0, "type": "path" },
    { "id": 4, "x": -9612.5, "y": 142.8, "z": 50.8, "type": "hotspot", "radius": 40, "linger_time": 8 },
    { "id": 5, "x": -9678.3, "y": 180.5, "z": 49.2, "type": "path" },
    { "id": 6, "x": -9720.1, "y": 225.9, "z": 49.4, "type": "hotspot", "radius": 30, "linger_time": 5 },
    { "id": 7, "x": -9685.4, "y": 280.3, "z": 46.9, "type": "path" },
    { "id": 8, "x": -9610.2, "y": 320.8, "z": 49.1, "type": "hotspot", "radius": 45, "linger_time": 7 },
    { "id": 9, "x": -9548.7, "y": 285.2, "z": 53.8, "type": "path" },
    { "id": 10, "x": -9498.3, "y": 210.6, "z": 53.8, "type": "hotspot", "radius": 35, "linger_time": 6 },
    { "id": 11, "x": -9445.9, "y": 165.4, "z": 56.2, "type": "path" },
    { "id": 12, "x": -9456.2, "y": 64.8, "z": 56.0, "type": "path", "note": "Loop back to start" }
  ],
  "blackspots": [
    { "x": -9530.5, "y": 95.8, "z": 45.2, "radius": 20, "reason": "Inside Fargodeep Mine" }
  ]
}]]

    -- Write the example profile
    local profile_path = "gatherbuddy/profiles/elwynn_copper.json"
    core.create_data_file(profile_path)
    core.write_data_file(profile_path, example_profile)

    -- Register it
    self:register_profile(profile_path)

    if self._log then
        self._log:info("Installed example profile: %s", profile_path)
    end

    return true
end

---Ensure profiles folder exists and has example profiles
function ProfileManager:ensure_profiles_exist()
    -- Check if profile folder exists by trying to read a known file
    local test_content = core.read_data_file("gatherbuddy/profiles/elwynn_copper.json")
    if not test_content or #test_content == 0 then
        if self._log then
            self._log:info("No profiles found, installing examples...")
        end
        self:install_example_profiles()
    end
end

---Clean up resources
function ProfileManager:destroy()
    if self._event_bus then
        self._event_bus:unsubscribe_by_owner("ProfileManager")
    end
end

---Run unit tests
---@return table<string, boolean> Test results
function ProfileManager:_test()
    local results = {}

    -- Create mock event bus
    local mock_bus = {
        events = {},
        subscribe = function() return 1 end,
        unsubscribe_by_owner = function() end,
        publish = function(self, event, data)
            table.insert(self.events, { event = event, data = data })
        end
    }

    local pm = ProfileManager:new(mock_bus)

    -- Test 1: Validate valid profile
    local valid_profile = {
        version = "1.0",
        metadata = { name = "Test" },
        requirements = { map_id = 37 },
        settings = { loop = true },
        waypoints = {
            { id = 1, x = 0, y = 0, z = 0, type = "path" },
            { id = 2, x = 10, y = 0, z = 10, type = "hotspot", radius = 30 }
        }
    }
    local valid, errors = pm:validate_profile(valid_profile)
    results.valid_profile = (valid == true and #errors == 0)

    -- Test 2: Validate invalid profile (missing waypoints)
    local invalid_profile = {
        version = "1.0",
        requirements = { map_id = 37 }
    }
    valid, errors = pm:validate_profile(invalid_profile)
    results.invalid_missing_waypoints = (valid == false and #errors > 0)

    -- Test 3: Validate invalid profile (missing coordinates)
    local bad_waypoint_profile = {
        version = "1.0",
        metadata = { name = "Test" },
        requirements = { map_id = 37 },
        settings = {},
        waypoints = {
            { id = 1, type = "path" }  -- Missing x, y, z
        }
    }
    valid, errors = pm:validate_profile(bad_waypoint_profile)
    results.invalid_waypoint = (valid == false)

    -- Test 4: Blackspot check (simulate loaded profile)
    pm._current_profile = {
        blackspots = {
            { x = 100, y = 50, z = 100, radius = 20 }
        }
    }
    results.in_blackspot = pm:is_in_blackspot({ x = 105, y = 50, z = 105 })
    results.outside_blackspot = not pm:is_in_blackspot({ x = 200, y = 50, z = 200 })

    -- Test 5: Nearest waypoint
    pm._current_profile = valid_profile
    local nearest, index = pm:get_nearest_waypoint({ x = 5, y = 0, z = 5 })
    results.nearest_waypoint = (nearest ~= nil and index ~= nil)

    -- Test 6: Get setting with fallback
    pm._current_profile = valid_profile
    results.get_setting_exists = (pm:get_setting("loop", false) == true)
    results.get_setting_default = (pm:get_setting("nonexistent", 123) == 123)

    -- Test 7: Is profile loaded
    results.is_loaded = pm:is_profile_loaded()
    pm._current_profile = nil
    results.is_not_loaded = not pm:is_profile_loaded()

    return results
end

---Scan for available profiles using directory listing
---@return table[] profiles Array of {name, path, zone, map_id, waypoint_count}
function ProfileManager:scan_available_profiles()
    local profiles = {
        { name = "Select profile...", path = nil }
    }

    local base_path = "gatherbuddy/profiles/"
    local entries = core.read_dir("gatherbuddy/profiles")
    if not entries then
        return profiles
    end

    for _, filename in ipairs(entries) do
        if filename:match("%.json$") and filename ~= "manifest.json" then
            local full_path = base_path .. filename
            local json_str = core.read_data_file(full_path)
            if json_str and json_str ~= "" then
                local data, _ = JSON.decode(json_str)
                if data then
                    profiles[#profiles + 1] = {
                        name = (data.metadata and data.metadata.name) or filename:match("(.+)%.json$"),
                        path = full_path,
                        zone = data.requirements and data.requirements.zone,
                        map_id = data.requirements and data.requirements.map_id,
                        waypoint_count = data.waypoints and #data.waypoints or 0,
                    }
                end
            end
        end
    end

    return profiles
end

return ProfileManager
