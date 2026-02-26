-- SentinelCore/services/ProfileCoordinator.lua
local Events = require("events/Events")
local Validator = require("profiles/ProfileValidator")
local Schema = require("profiles/ProfileSchema")

local ProfileCoordinator = {}
ProfileCoordinator.__index = ProfileCoordinator

local function get_now()
    return tonumber(core.time()) or 0
end

local function distance_3d(a, b)
    if not a or not b then return math.huge end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function ProfileCoordinator:new(event_bus, blackboard, cfg, navigation, targeting, logger)
    local o = setmetatable({}, self)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._cfg = cfg or {}
    o._nav = navigation
    o._targeting = targeting
    o._log = logger

    o._state = "idle"
    o._profile = nil
    o._hotspot_index = 0
    o._dry_spell_start = 0
    o._loop_count = 0
    o._loop_start_time = 0
    o._resume_hotspot_id = nil
    o._move_issued = false
    o._vendor_trip_done = false -- set by event listener when VendorService finishes

    -- Listen for VendorService terminal events
    event_bus:on(Events.VENDOR_COMPLETED, function()
        if o._state == "vendor_trip" then
            o._vendor_trip_done = true
        end
    end)
    event_bus:on(Events.VENDOR_FAILED, function()
        if o._state == "vendor_trip" then
            o._vendor_trip_done = true
        end
    end)

    return o
end

function ProfileCoordinator:get_state()
    return self._state
end

function ProfileCoordinator:load_profile(profile)
    local ok, errors = Validator.validate(profile)
    if not ok then
        local msg = table.concat(errors, "; ")
        self._log:error("profile validation failed: %s", msg)
        self._event_bus:emit(Events.PROFILE_LOAD_FAILED, { errors = errors })
        return false, msg
    end

    self._profile = profile
    self._hotspot_index = 1
    self._loop_count = 0
    self._loop_start_time = get_now()
    self._dry_spell_start = 0

    self._blackboard:set("profile.active", true)
    self._blackboard:set("profile.blackspots", profile.blackspots or {})
    self._blackboard:set("profile.vendors", profile.vendors or {})
    self._blackboard:set("profile.rest_spots", profile.rest_spots or {})

    self:_enter_hotspot(self._hotspot_index)

    self._event_bus:emit(Events.PROFILE_LOADED, {
        name = profile.metadata and profile.metadata.name or "Unknown",
        hotspot_count = #profile.hotspots,
        map_id = profile.requirements and profile.requirements.map_id or 0,
    })

    self._log:info("profile loaded: %s (%d hotspots)",
        profile.metadata and profile.metadata.name or "?", #profile.hotspots)

    return true
end

function ProfileCoordinator:unload_profile()
    if not self._profile then return end

    local name = self._profile.metadata and self._profile.metadata.name or "?"
    self._profile = nil
    self._state = "idle"
    self._hotspot_index = 0

    self._blackboard:clear("profile.active")
    self._blackboard:clear("profile.state")
    self._blackboard:clear("profile.current_hotspot")
    self._blackboard:clear("profile.target_filters")
    self._blackboard:clear("profile.blackspots")
    self._blackboard:clear("profile.vendors")
    self._blackboard:clear("profile.rest_spots")
    self._blackboard:clear("grind.anchor")
    self._blackboard:clear("exploration.max_grind_radius")

    self._event_bus:emit(Events.PROFILE_UNLOADED, { name = name })
    self._log:info("profile unloaded: %s", name)
end

function ProfileCoordinator:update()
    if not self._profile then return true end

    if self._state == "at_hotspot" then
        self:_tick_at_hotspot()
    elseif self._state == "traveling" then
        self:_tick_traveling()
    elseif self._state == "vendor_trip" then
        self:_tick_vendor_trip()
    end

    return true
end

-- Private: state entry

function ProfileCoordinator:_enter_hotspot(index)
    local hs = self._profile.hotspots[index]
    if not hs then return end

    self._state = "at_hotspot"
    self._hotspot_index = index
    self._dry_spell_start = 0
    self._move_issued = false

    local filters = Schema.merge_target_filters(
        self._profile.target_defaults,
        hs.targets
    )

    self._blackboard:set("profile.state", "at_hotspot")
    self._blackboard:set("profile.current_hotspot", hs)
    self._blackboard:set("profile.target_filters", filters)
    self._blackboard:set("grind.anchor", { x = hs.x, y = hs.y, z = hs.z })
    self._blackboard:set("exploration.max_grind_radius", tonumber(hs.radius) or 40)

    self._event_bus:emit(Events.HOTSPOT_ENTERED, {
        hotspot_id = hs.id,
        index = index,
        label = hs.label,
    })

    self._log:info("entered hotspot [%d] %s (r=%d)",
        index, tostring(hs.id), tonumber(hs.radius) or 40)
end

function ProfileCoordinator:_enter_traveling(next_index)
    local from_hs = self._profile.hotspots[self._hotspot_index]
    local to_hs = self._profile.hotspots[next_index]
    if not to_hs then return end

    self._state = "traveling"
    self._hotspot_index = next_index
    self._move_issued = false

    self._blackboard:set("profile.state", "traveling")
    self._blackboard:clear("grind.anchor")

    local dist = distance_3d(from_hs, to_hs)
    self._event_bus:emit(Events.HOTSPOT_TRAVEL_START, {
        from_id = from_hs and from_hs.id,
        to_id = to_hs.id,
        distance = dist,
    })

    self._log:info("traveling to hotspot [%d] %s (%.0f yd)",
        next_index, tostring(to_hs.id), dist)
end

function ProfileCoordinator:_enter_vendor_trip()
    local current_hs = self._profile.hotspots[self._hotspot_index]
    self._resume_hotspot_id = current_hs and current_hs.id or nil

    self._state = "vendor_trip"
    self._vendor_trip_done = false
    self._blackboard:set("profile.state", "vendor_trip")
    self._blackboard:clear("grind.anchor")

    self._event_bus:emit(Events.VENDOR_TRIP_START, {
        resume_hotspot_id = self._resume_hotspot_id,
    })

    self._log:info("vendor trip started, will resume at %s", tostring(self._resume_hotspot_id))
end

-- Private: state ticks

function ProfileCoordinator:_tick_at_hotspot()
    local now = get_now()

    local free_slots = tonumber(self._blackboard:get("inventory.free_slots")) or 999
    local durability = tonumber(self._blackboard:get("player.durability_pct")) or 1.0
    local dur_threshold = tonumber(self._cfg.vendor_durability_threshold) or 0.25
    local has_vendors = self._profile.vendors and #self._profile.vendors > 0

    if has_vendors and (free_slots <= 0 or durability < dur_threshold) then
        self:_enter_vendor_trip()
        return
    end

    local candidates = self._targeting:get_visible_candidates()
    local count = type(candidates) == "table" and #candidates or 0

    if count > 0 then
        self._dry_spell_start = 0
        return
    end

    if self._dry_spell_start == 0 then
        self._dry_spell_start = now
        return
    end

    local dry_secs = tonumber(self._cfg.dry_spell_secs) or 15
    if (now - self._dry_spell_start) >= dry_secs then
        local next_idx = self:_next_hotspot_index()
        if next_idx then
            local from_hs = self._profile.hotspots[self._hotspot_index]
            local to_hs = self._profile.hotspots[next_idx]
            self._event_bus:emit(Events.HOTSPOT_ADVANCED, {
                from_id = from_hs and from_hs.id,
                to_id = to_hs and to_hs.id,
                reason = "dry_spell",
            })
            self:_enter_traveling(next_idx)
        end
    end
end

function ProfileCoordinator:_tick_traveling()
    local hs = self._profile.hotspots[self._hotspot_index]
    if not hs then
        self._state = "idle"
        return
    end

    if not self._move_issued then
        self._nav:move_to({ x = hs.x, y = hs.y, z = hs.z })
        self._move_issued = true
    end

    local player_pos = self._blackboard:get("player.position")
    local radius = (tonumber(hs.radius) or 40) * (tonumber(self._cfg.hotspot_arrival_radius_mult) or 1.0)
    local dist = distance_3d(player_pos, hs)

    if dist <= radius then
        self:_enter_hotspot(self._hotspot_index)
    end
end

function ProfileCoordinator:_tick_vendor_trip()
    -- _vendor_trip_done is set by VENDOR_COMPLETED/VENDOR_FAILED event listeners.
    -- This avoids polling a blackboard key that may not be written.
    if not self._vendor_trip_done then
        return
    end

    self._event_bus:emit(Events.VENDOR_TRIP_COMPLETE, {
        resume_hotspot_id = self._resume_hotspot_id,
    })

    if self._resume_hotspot_id then
        local idx = self:_find_hotspot_index(self._resume_hotspot_id)
        if idx then
            self:_enter_traveling(idx)
            self._resume_hotspot_id = nil
            return
        end
    end
    self:_resume_nearest_hotspot()
end

-- Private: helpers

function ProfileCoordinator:_next_hotspot_index()
    local total = #self._profile.hotspots
    local next_idx = self._hotspot_index + 1

    if next_idx > total then
        if self._profile.loop ~= false and self._cfg.loop ~= false then
            self._loop_count = self._loop_count + 1
            local now = get_now()
            self._event_bus:emit(Events.PROFILE_LOOP_COMPLETE, {
                loop_count = self._loop_count,
                elapsed_secs = now - self._loop_start_time,
            })
            self._loop_start_time = now
            return 1
        end
        return nil
    end

    return next_idx
end

function ProfileCoordinator:_find_hotspot_index(hotspot_id)
    if not self._profile or not self._profile.hotspots then return nil end
    for i = 1, #self._profile.hotspots do
        if self._profile.hotspots[i].id == hotspot_id then
            return i
        end
    end
    return nil
end

function ProfileCoordinator:_resume_nearest_hotspot()
    local player_pos = self._blackboard:get("player.position")
    if not player_pos or not self._profile then
        self._state = "idle"
        return
    end

    local best_idx = 1
    local best_dist = math.huge
    for i = 1, #self._profile.hotspots do
        local hs = self._profile.hotspots[i]
        local d = distance_3d(player_pos, hs)
        if d < best_dist then
            best_dist = d
            best_idx = i
        end
    end

    self:_enter_traveling(best_idx)
end

-- ── File I/O ─────────────────────────────────────

local PROFILE_DIR = "SentinelCore/profiles/"

--- Load a profile from a JSON file in scripts_data/SentinelCore/profiles/.
---@param filename string  e.g. "netherstorm_manaforge.json"
---@return boolean ok, string|nil error
function ProfileCoordinator:load_profile_from_file(filename)
    local path = PROFILE_DIR .. filename
    local content = core.read_data_file(path)
    if not content or content == "" then
        local msg = "file not found or empty: " .. path
        self._log:error(msg)
        return false, msg
    end

    local JSON = require("lib/JSON")
    local profile, parse_err = JSON.decode(content)
    if not profile or type(profile) ~= "table" then
        local msg = "JSON parse error: " .. tostring(parse_err or "unknown")
        self._log:error(msg)
        return false, msg
    end

    return self:load_profile(profile)
end

--- Save the active profile to a JSON file.
---@param filename string
---@return boolean ok, string|nil error
function ProfileCoordinator:save_profile_to_file(filename)
    if not self._profile then
        return false, "no active profile"
    end

    local JSON = require("lib/JSON")
    self._profile.metadata.updated_at = math.floor(get_now())

    local content, enc_err = JSON.encode(self._profile, true)
    if not content then
        return false, "encode failed: " .. tostring(enc_err)
    end

    local path = PROFILE_DIR .. filename
    core.create_data_folder("SentinelCore/profiles")
    core.write_data_file(path, content)

    self._log:info("profile saved to %s", path)
    self:_update_manifest(filename, self._profile.metadata.name)
    return true
end

---@private
---@param filename string
---@param profile_name string|nil
function ProfileCoordinator:_update_manifest(filename, profile_name)
    local manifest_path = PROFILE_DIR .. "manifest.json"
    local JSON = require("lib/JSON")

    local content = core.read_data_file(manifest_path)
    local profiles = {}
    if content and content ~= "" then
        local parsed = JSON.decode(content)
        if type(parsed) == "table" then
            profiles = parsed.profiles or parsed
            if type(profiles) ~= "table" then profiles = {} end
        end
    end

    local found = false
    for i = 1, #profiles do
        local entry = profiles[i]
        if type(entry) == "table" and entry.filename == filename then
            entry.name = profile_name or filename
            found = true
            break
        end
    end

    if not found then
        profiles[#profiles + 1] = {
            filename = filename,
            name = profile_name or filename,
        }
    end

    local out = JSON.encode({ profiles = profiles }, true)
    if out then
        core.write_data_file(manifest_path, out)
    end
end

--- List profile JSON files via manifest in scripts_data/SentinelCore/profiles/.
---@return table[]  array of { filename, name }
function ProfileCoordinator:list_profile_files()
    local manifest_path = PROFILE_DIR .. "manifest.json"
    local content = core.read_data_file(manifest_path)
    if not content or content == "" then
        return {}
    end

    local JSON = require("lib/JSON")
    local data = JSON.decode(content)
    if type(data) ~= "table" then
        return {}
    end

    local files = {}
    local items = data.profiles or data
    if type(items) == "table" then
        for i = 1, #items do
            local entry = items[i]
            if type(entry) == "table" and entry.filename then
                files[#files + 1] = {
                    filename = entry.filename,
                    name = entry.name or entry.filename,
                }
            elseif type(entry) == "string" then
                files[#files + 1] = { filename = entry, name = entry }
            end
        end
    end

    return files
end

return ProfileCoordinator
