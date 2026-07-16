local JSON = require("lib/JSON")
local ProfileValidator = require("modules/grind/profile_validator")
local Autoloader = require("modules/grind/autoloader")

local ProfileManager = {}
ProfileManager.__index = ProfileManager

local PROFILE_DIR = "sentinel/grinding_profiles"

---Compute 3D distance between two {x,y,z} points.
---@param a table {x=number, y=number, z=number}
---@param b table {x=number, y=number, z=number}
---@return number
local function distance_3d(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Log a message through the Sylvannas core logger.
---@param msg string
local function log(msg)
    if core and core.log then
        core.log("[SentinelCore] ProfileManager: " .. msg)
    end
end

---Log an error message through the Sylvannas core logger.
---@param msg string
local function log_error(msg)
    if core and core.log_error then
        core.log_error("[SentinelCore] ProfileManager: " .. msg)
    end
end

---Create a new ProfileManager instance.
---@param event_bus table EventBus instance
---@param blackboard table Blackboard instance
---@return table ProfileManager
function ProfileManager:new(event_bus, blackboard)
    return setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _profile = nil,
        _profile_filename = nil,
        _hotspot_index = 1,
        _dry_spell_start = nil,
        _loops_completed = 0,
    }, self)
end

---Ensure the profile directory exists.
function ProfileManager:initialize()
    pcall(core.create_data_folder, PROFILE_DIR)
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

---Load a grinding profile from a JSON file.
---@param filename string Filename within PROFILE_DIR
---@return boolean success
---@return string[]|nil errors Validation errors (nil on success)
function ProfileManager:load_profile(filename)
    if type(filename) ~= "string" or filename == "" then
        return false, { "filename must be a non-empty string" }
    end

    local path = PROFILE_DIR .. "/" .. filename

    local read_ok, content = pcall(core.read_data_file, path)
    if not read_ok or not content or content == "" then
        local err_msg = "failed to read profile: " .. path
        log_error(err_msg)
        self._event_bus:publish("grind:profile_load_failed", {
            filename = filename,
            errors = { err_msg },
        })
        return false, { err_msg }
    end

    local data, decode_err = JSON.decode(content)
    if not data then
        local err_msg = "failed to decode JSON: " .. tostring(decode_err)
        log_error(err_msg)
        self._event_bus:publish("grind:profile_load_failed", {
            filename = filename,
            errors = { err_msg },
        })
        return false, { err_msg }
    end

    local valid, errors = ProfileValidator.validate(data)
    if not valid then
        log_error("profile validation failed for " .. filename .. ": " .. table.concat(errors, "; "))
        self._event_bus:publish("grind:profile_load_failed", {
            filename = filename,
            errors = errors,
        })
        return false, errors
    end

    -- Store profile state
    self._profile = data
    self._profile_filename = filename
    self._hotspot_index = 1
    self._loops_completed = 0
    self._dry_spell_start = nil

    -- Inject first hotspot into blackboard
    self:_inject_hotspot()

    log("loaded profile: " .. tostring(data.metadata and data.metadata.name or filename))
    self._event_bus:publish("grind:profile_loaded", {
        filename = filename,
        name = data.metadata and data.metadata.name or "",
        hotspot_count = #data.hotspots,
    })

    return true
end

---Unload the current profile and clear all blackboard state.
function ProfileManager:unload_profile()
    local bb = self._blackboard
    local was_loaded = self._profile ~= nil
    local old_name = self._profile and self._profile.metadata and self._profile.metadata.name or nil

    self._profile = nil
    self._profile_filename = nil
    self._hotspot_index = 1
    self._loops_completed = 0
    self._dry_spell_start = nil

    bb:clear("module.grind.current_spot")
    bb:clear("module.grind.profile_active")
    bb:clear("module.grind.profile_name")
    bb:clear("module.grind.zone_profile_id")
    bb:clear("module.grind.current_hotspot_index")
    bb:clear("module.grind.hotspot_count")
    bb:clear("module.grind.target_filters")

    if was_loaded then
        log("unloaded profile: " .. tostring(old_name))
        self._event_bus:publish("grind:profile_unloaded", {
            name = old_name,
        })
    end
end

---Check if a profile is currently loaded.
---@return boolean
function ProfileManager:is_profile_loaded()
    return self._profile ~= nil
end

---Get the currently loaded profile table.
---@return table|nil
function ProfileManager:get_active_profile()
    return self._profile
end

---Get the filename of the currently loaded profile.
---@return string|nil
function ProfileManager:get_profile_filename()
    return self._profile_filename
end

-- ---------------------------------------------------------------------------
-- Scanning
-- ---------------------------------------------------------------------------

---Scan the profile directory and return metadata for all valid profiles.
---@return table[] entries Array of {filename, name, min_level, max_level}
function ProfileManager:scan_profiles()
    local results = {}

    local ok, files = pcall(core.read_dir, PROFILE_DIR)
    if not ok or not files then
        return results
    end

    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local path = PROFILE_DIR .. "/" .. filename
            local read_ok, content = pcall(core.read_data_file, path)
            if read_ok and content and content ~= "" then
                local data = JSON.decode(content)
                if type(data) == "table"
                    and type(data.metadata) == "table"
                    and type(data.metadata.name) == "string"
                then
                    results[#results + 1] = {
                        filename = filename,
                        name = data.metadata.name,
                        min_level = data.requirements and data.requirements.min_level or nil,
                        max_level = data.requirements and data.requirements.max_level or nil,
                    }
                end
            end
        end
    end

    -- Sort by min_level ascending (nil sorts to end)
    table.sort(results, function(a, b)
        local a_lvl = a.min_level or 999
        local b_lvl = b.min_level or 999
        return a_lvl < b_lvl
    end)

    return results
end

-- ---------------------------------------------------------------------------
-- Hotspot Management
-- ---------------------------------------------------------------------------

---Get the current hotspot table from the loaded profile.
---@return table|nil
function ProfileManager:get_current_hotspot()
    if not self._profile or not self._profile.hotspots then
        return nil
    end
    return self._profile.hotspots[self._hotspot_index]
end

---Get the current hotspot index (1-based).
---@return number
function ProfileManager:get_current_hotspot_index()
    return self._hotspot_index
end

---Get the total number of hotspots in the loaded profile.
---@return number
function ProfileManager:get_hotspot_count()
    if not self._profile or not self._profile.hotspots then
        return 0
    end
    return #self._profile.hotspots
end

---Advance to the next hotspot in the profile.
---Wraps to hotspot 1 when looping is enabled, otherwise publishes profile_complete.
---@param reason string Reason for advancing (e.g. "dry_spell", "manual", "outlevel")
---@return table|nil hotspot The new current hotspot, or nil if profile complete
function ProfileManager:advance_hotspot(reason)
    if not self._profile or not self._profile.hotspots then
        return nil
    end

    local from_index = self._hotspot_index
    local count = #self._profile.hotspots
    local next_index = self._hotspot_index + 1

    if next_index > count then
        local should_loop = self._profile.options == nil or self._profile.options.loop ~= false
        if should_loop then
            next_index = 1
            self._loops_completed = self._loops_completed + 1
            log("loop completed (" .. self._loops_completed .. " total), wrapping to hotspot 1")
        else
            log("reached last hotspot, profile complete")
            self._event_bus:publish("grind:profile_complete", {
                filename = self._profile_filename,
                loops_completed = self._loops_completed,
            })
            return nil
        end
    end

    self._hotspot_index = next_index
    self._dry_spell_start = nil

    log("advanced hotspot " .. from_index .. " -> " .. next_index .. " (reason: " .. tostring(reason) .. ")")
    self._event_bus:publish("grind:hotspot_advanced", {
        from_index = from_index,
        to_index = next_index,
        reason = reason or "unknown",
    })

    self:_inject_hotspot()

    return self._profile.hotspots[next_index]
end

---Find the nearest hotspot to a given position.
---@param position table {x=number, y=number, z=number}
---@return table|nil hotspot The nearest hotspot table
---@return number|nil index The 1-based index of the nearest hotspot
function ProfileManager:get_nearest_hotspot(position)
    if not self._profile or not self._profile.hotspots or not position then
        return nil, nil
    end

    local best = nil
    local best_index = nil
    local best_dist = math.huge

    for i, hs in ipairs(self._profile.hotspots) do
        local hs_pos = { x = hs.x, y = hs.y, z = hs.z }
        local dist = distance_3d(position, hs_pos)
        if dist < best_dist then
            best_dist = dist
            best = hs
            best_index = i
        end
    end

    return best, best_index
end

---Advance to the safest hotspot (lowest threat heat).
---Used by death loop response to relocate away from danger.
---@param threat_map table ThreatMap instance
---@param now_ms number Current time in milliseconds
---@return table|nil hotspot The new hotspot, or nil
---@return number best_heat The heat of the chosen hotspot
function ProfileManager:advance_to_safest_hotspot(threat_map, now_ms)
    if not self._profile or not self._profile.hotspots then
        return nil, math.huge
    end

    local count = #self._profile.hotspots
    if count == 0 then return nil, math.huge end

    -- Build spots array with center field for threat_map API
    local spots = {}
    for i, hs in ipairs(self._profile.hotspots) do
        spots[i] = { center = { x = hs.x, y = hs.y, z = hs.z } }
    end

    local safest_idx = threat_map:get_safest_hotspot(spots, now_ms)
    if not safest_idx then return nil, math.huge end

    local best_heat = threat_map:get_heat(spots[safest_idx].center, 60, now_ms)

    if safest_idx ~= self._hotspot_index then
        local from_index = self._hotspot_index
        self._hotspot_index = safest_idx
        self._dry_spell_start = nil

        log("death loop: advanced to safest hotspot " .. safest_idx .. " (heat: " .. string.format("%.1f", best_heat) .. ")")
        self._event_bus:publish("grind:hotspot_advanced", {
            from_index = from_index,
            to_index = safest_idx,
            reason = "death_loop_safest",
        })

        self:_inject_hotspot()
    end

    return self._profile.hotspots[safest_idx], best_heat
end

-- ---------------------------------------------------------------------------
-- Filters
-- ---------------------------------------------------------------------------

---Merge profile-level target_defaults with per-hotspot target_overrides.
---Hotspot overrides take precedence for any field they define.
---@param hotspot table Hotspot entry with optional target_overrides
---@return table filters Merged filter table
function ProfileManager:get_merged_filters(hotspot)
    local defaults = self._profile and self._profile.target_defaults or {}
    local overrides = hotspot and hotspot.target_overrides or {}

    return {
        level_min = overrides.level_min or defaults.level_min,
        level_max = overrides.level_max or defaults.level_max,
        creature_types = overrides.creature_types or defaults.creature_types,
        npc_whitelist = overrides.npc_whitelist or defaults.npc_whitelist,
        npc_blacklist = overrides.npc_blacklist or defaults.npc_blacklist,
    }
end

-- ---------------------------------------------------------------------------
-- Blackspots
-- ---------------------------------------------------------------------------

---Check if a position falls within any of the profile's blackspots.
---@param position table {x=number, y=number, z=number}
---@return boolean
function ProfileManager:is_in_blackspot(position)
    if not self._profile or not self._profile.blackspots or not position then
        return false
    end

    for _, bs in ipairs(self._profile.blackspots) do
        local bs_pos = { x = bs.x, y = bs.y, z = bs.z }
        local dist = distance_3d(position, bs_pos)
        if dist <= (bs.radius or 20) then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Vendors
-- ---------------------------------------------------------------------------

---Get vendors from the loaded profile, optionally filtered by service type.
---@param service_filter string|nil Service name to filter by (e.g. "repair", "sell")
---@return table[] vendors
function ProfileManager:get_vendors(service_filter)
    if not self._profile or not self._profile.vendors then
        return {}
    end

    if service_filter == nil then
        return self._profile.vendors
    end

    local filtered = {}
    for _, vendor in ipairs(self._profile.vendors) do
        if vendor.services then
            for _, svc in ipairs(vendor.services) do
                if svc == service_filter then
                    filtered[#filtered + 1] = vendor
                    break
                end
            end
        end
    end

    return filtered
end

---Find the nearest vendor to a position, optionally filtered by service.
---@param pos table {x=number, y=number, z=number}
---@param service string|nil Service name to filter by
---@return table|nil vendor The nearest vendor entry
function ProfileManager:get_nearest_vendor(pos, service)
    local vendors = self:get_vendors(service)
    if #vendors == 0 or not pos then
        return nil
    end

    local best = nil
    local best_dist = math.huge

    for _, vendor in ipairs(vendors) do
        local v_pos = { x = vendor.x, y = vendor.y, z = vendor.z }
        local dist = distance_3d(pos, v_pos)
        if dist < best_dist then
            best_dist = dist
            best = vendor
        end
    end

    return best
end

-- ---------------------------------------------------------------------------
-- Save / Create / Delete
-- ---------------------------------------------------------------------------

---Save a profile table as JSON to the profile directory.
---Validates the profile before writing.
---@param profile table Profile data table
---@param filename string Target filename within PROFILE_DIR
---@return boolean success
function ProfileManager:save_profile(profile, filename)
    if type(profile) ~= "table" then
        log_error("save_profile: profile must be a table")
        return false
    end
    if type(filename) ~= "string" or filename == "" then
        log_error("save_profile: filename must be a non-empty string")
        return false
    end

    local valid, errors = ProfileValidator.validate(profile)
    if not valid then
        log_error("save_profile: validation failed: " .. table.concat(errors, "; "))
        return false
    end

    pcall(core.create_data_folder, PROFILE_DIR)

    local json_str, encode_err = JSON.encode(profile, true)
    if not json_str or json_str == "" then
        log_error("save_profile: JSON encode failed: " .. tostring(encode_err))
        return false
    end

    local path = PROFILE_DIR .. "/" .. filename
    pcall(core.create_data_file, path)
    local write_ok = pcall(core.write_data_file, path, json_str)
    if not write_ok then
        log_error("save_profile: failed to write file: " .. path)
        return false
    end

    log("saved profile: " .. path)
    return true
end

---Delete a profile by overwriting it with empty content.
---If the deleted profile is the active profile, it is unloaded first.
---@param filename string Filename within PROFILE_DIR
---@return boolean success
function ProfileManager:delete_profile(filename)
    if type(filename) ~= "string" or filename == "" then
        log_error("delete_profile: filename must be a non-empty string")
        return false
    end

    -- Unload if this is the active profile
    if self._profile_filename == filename then
        self:unload_profile()
    end

    local path = PROFILE_DIR .. "/" .. filename
    local write_ok = pcall(core.write_data_file, path, "")
    if not write_ok then
        log_error("delete_profile: failed to overwrite file: " .. path)
        return false
    end

    log("deleted profile: " .. path)
    return true
end

-- ---------------------------------------------------------------------------
-- Runtime Update
-- ---------------------------------------------------------------------------

---Per-frame update. Checks for outlevel, dry spells, and ensures blackboard
---state is consistent with the loaded profile.
---@param player_level number Current player level
---@param map_id number Current map ID
function ProfileManager:update(player_level, map_id)
    if not self._profile then
        return
    end

    local bb = self._blackboard

    -- Check outlevel: player has exceeded the profile's max level
    local max_level = self._profile.requirements and self._profile.requirements.max_level
    if max_level and player_level > max_level then
        log("player level " .. player_level .. " exceeds profile max " .. max_level)
        self._event_bus:publish("grind:profile_outleveled", {
            filename = self._profile_filename,
            player_level = player_level,
            max_level = max_level,
        })

        -- Attempt autoloader transition (guard against reloading the same profile)
        local resolved = Autoloader.resolve(player_level)
        if resolved and resolved ~= self._profile_filename then
            log("autoloader resolved next profile: " .. resolved)
            self:load_profile(resolved)
        elseif resolved then
            log("autoloader resolved same profile (" .. resolved .. "), skipping reload")
        end
        return
    end

    -- Check dry spell: no target found for too long at current hotspot
    local now_ms = bb:get("system.now_ms")
    local has_target = bb:get("module.grind.current_target") ~= nil

    if not has_target and now_ms then
        if self._dry_spell_start == nil then
            self._dry_spell_start = now_ms
        else
            local dry_spell_secs = self._profile.options
                and self._profile.options.dry_spell_secs
                or 15
            local elapsed_ms = now_ms - self._dry_spell_start
            if elapsed_ms > dry_spell_secs * 1000 then
                log("dry spell exceeded " .. dry_spell_secs .. "s, advancing hotspot")
                self:advance_hotspot("dry_spell")
                self._dry_spell_start = nil
            end
        end
    else
        self._dry_spell_start = nil
    end

    -- Ensure blackboard has current_spot (re-inject if cleared externally)
    if not bb:has("module.grind.current_spot") then
        self:_inject_hotspot()
    end
end

-- ---------------------------------------------------------------------------
-- Autoload Helper
-- ---------------------------------------------------------------------------

---Attempt to auto-load a profile for the given player level using the Autoloader.
---@param player_level number Current player level
---@param map_id number Current map ID (reserved for future use)
---@return boolean success
function ProfileManager:try_autoload(player_level, map_id)
    if not Autoloader.is_loaded() then
        return false
    end

    local resolved = Autoloader.resolve(player_level)
    if not resolved then
        return false
    end

    local success, errors = self:load_profile(resolved)
    if not success then
        log_error("autoload failed for " .. resolved .. ": " .. table.concat(errors or {}, "; "))
        self._event_bus:publish("grind:autoload_failed", {
            filename = resolved,
            errors = errors,
        })
    end
    return success
end

-- ---------------------------------------------------------------------------
-- Private: Hotspot Injection
-- ---------------------------------------------------------------------------

---Transform the current hotspot into the "spot" format consumed by grind phases
---and inject it into the blackboard along with profile metadata.
function ProfileManager:_inject_hotspot()
    if not self._profile or not self._profile.hotspots then
        return
    end

    local hotspot = self._profile.hotspots[self._hotspot_index]
    if not hotspot then
        return
    end

    local filters = self:get_merged_filters(hotspot)

    local spot = {
        center = { x = hotspot.x, y = hotspot.y, z = hotspot.z },
        radius = hotspot.radius or 40,
        level_min = filters.level_min or 1,
        level_max = filters.level_max or 70,
        mob_whitelist = filters.npc_whitelist or {},
        mob_blacklist = filters.npc_blacklist or {},
        creature_types = filters.creature_types or {},
        allow_neutral = hotspot.allow_neutral == true,  -- Skip can_attack check for passive mobs
        blackspots = self._profile.blackspots or {},
        aoe_enabled = false,
        hotspot_id = hotspot.id,
        hotspot_label = hotspot.label or hotspot.id,
    }

    local bb = self._blackboard
    bb:set("module.grind.current_spot", spot)
    bb:set("module.grind.profile_active", true)
    bb:set("module.grind.profile_name", self._profile.metadata and self._profile.metadata.name or "")
    bb:set("module.grind.zone_profile_id", self._profile_filename)
    bb:set("module.grind.current_hotspot_index", self._hotspot_index)
    bb:set("module.grind.hotspot_count", #self._profile.hotspots)
    bb:set("module.grind.target_filters", filters)

    self._event_bus:publish("grind:hotspot_entered", {
        hotspot_index = self._hotspot_index,
        hotspot_id = hotspot.id,
        hotspot_label = hotspot.label or hotspot.id,
    })
end

-- ---------------------------------------------------------------------------
-- Shutdown
-- ---------------------------------------------------------------------------

---Shut down the profile manager and unload the active profile.
function ProfileManager:shutdown()
    self:unload_profile()
end

-- ---------------------------------------------------------------------------
-- Accessors for internal counters
-- ---------------------------------------------------------------------------

---Get the number of completed hotspot loops.
---@return number
function ProfileManager:get_loops_completed()
    return self._loops_completed
end

---Set a preview profile (unsaved editor data) for visualization.
---@param editor_state table|nil The editor state table with hotspots, vendors, blackspots, etc.
function ProfileManager:set_preview(editor_state)
    self._preview = editor_state
end

---Get the preview profile for visualization, or nil if none set.
---@return table|nil A profile-shaped table built from editor state
function ProfileManager:get_preview()
    if not self._preview then return nil end
    local ed = self._preview
    if (not ed.hotspots or #ed.hotspots == 0)
        and (not ed.vendors or #ed.vendors == 0)
        and (not ed.blackspots or #ed.blackspots == 0) then
        return nil
    end
    return {
        hotspots = ed.hotspots or {},
        vendors = ed.vendors or {},
        blackspots = ed.blackspots or {},
        target_defaults = {
            npc_whitelist = ed.whitelist or {},
            npc_blacklist = ed.blacklist or {},
        },
        options = { loop = true },
    }
end

return ProfileManager
