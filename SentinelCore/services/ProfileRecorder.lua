-- SentinelCore/services/ProfileRecorder.lua
-- Records grind profiles by capturing player positions as hotspots, vendors, and blackspots.

local Schema = require("profiles/ProfileSchema")
local Validator = require("profiles/ProfileValidator")
local Events = require("events/Events")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

---@param value any
---@return any
local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[deep_copy(k)] = deep_copy(v)
    end
    return out
end

--------------------------------------------------------------------------------
-- ProfileRecorder
--------------------------------------------------------------------------------

---@class ProfileRecorder
---@field private _bus EventBus
---@field private _bb Blackboard
---@field private _log table
---@field private _keybind key_checkbox|nil
---@field private _state string
---@field private _working_profile table|nil
---@field private _history table[]
---@field private _hotspot_radius number
---@field private _hotspot_counter number
---@field private _keybind_was_pressed boolean
local ProfileRecorder = {}
ProfileRecorder.__index = ProfileRecorder

---@param event_bus EventBus
---@param blackboard Blackboard
---@param logger table
---@param keybind_element key_checkbox|nil
---@return ProfileRecorder
function ProfileRecorder:new(event_bus, blackboard, logger, keybind_element)
    local o = setmetatable({}, ProfileRecorder)
    o._bus = event_bus
    o._bb = blackboard
    o._log = logger
    o._keybind = keybind_element
    o._state = "idle"
    o._working_profile = nil
    o._history = {}
    o._hotspot_radius = 40
    o._hotspot_counter = 0
    o._keybind_was_pressed = false
    return o
end

--------------------------------------------------------------------------------
-- Accessors
--------------------------------------------------------------------------------

---@return string
function ProfileRecorder:get_state()
    return self._state
end

---@return table|nil
function ProfileRecorder:get_working_profile()
    return self._working_profile
end

---@param r number
function ProfileRecorder:set_hotspot_radius(r)
    self._hotspot_radius = r
end

---@return number
function ProfileRecorder:get_hotspot_radius()
    return self._hotspot_radius
end

--------------------------------------------------------------------------------
-- Recording lifecycle
--------------------------------------------------------------------------------

---Start a new recording session, or edit an existing profile.
---@param existing_profile? table  If provided, deep-copies and edits it
---@return boolean ok
function ProfileRecorder:start_recording(existing_profile)
    if self._state == "recording" then
        return false
    end

    local profile
    if existing_profile then
        profile = deep_copy(existing_profile)
    else
        profile = Schema.defaults()
    end

    -- Auto-fill map_id from blackboard when creating new or when existing has 0
    local map_id = self._bb:get("player.map_id", 0)
    if profile.requirements.map_id == 0 and map_id ~= 0 then
        profile.requirements.map_id = map_id
    end

    self._working_profile = profile
    self._history = {}
    self._hotspot_counter = #profile.hotspots
    self._state = "recording"

    -- Write blackboard keys
    self._bb:set("recorder.state", "recording")
    self._bb:set("recorder.working_profile", self._working_profile)
    self._bb:set("recorder.hotspot_count", #self._working_profile.hotspots)

    self._bus:emit(Events.RECORDER_STARTED, { profile = self._working_profile })
    return true
end

---Add a hotspot at the player's current position.
---@param label? string
---@return boolean ok
function ProfileRecorder:add_hotspot(label)
    if self._state ~= "recording" then
        return false
    end

    local pos = self._bb:get("player.position")
    if not pos then
        return false
    end

    self._hotspot_counter = self._hotspot_counter + 1
    local hotspot = {
        id = "hs_" .. self._hotspot_counter,
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = self._hotspot_radius,
        label = label or "",
    }

    local hotspots = self._working_profile.hotspots
    hotspots[#hotspots + 1] = hotspot
    self._history[#self._history + 1] = { type = "hotspot" }

    self._bb:set("recorder.hotspot_count", #hotspots)
    self._bb:set("recorder.working_profile", self._working_profile)

    self._bus:emit(Events.RECORDER_HOTSPOT_ADDED, { hotspot = hotspot })
    return true
end

---Add a vendor at the player's current position.
---@return boolean ok
function ProfileRecorder:add_vendor()
    if self._state ~= "recording" then
        return false
    end

    local pos = self._bb:get("player.position")
    if not pos then
        return false
    end

    local vendor = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        name = "",
        npc_id = 0,
        sell = true,
        repair = true,
        food = false,
        water = false,
    }

    local vendors = self._working_profile.vendors
    vendors[#vendors + 1] = vendor
    self._history[#self._history + 1] = { type = "vendor" }

    self._bb:set("recorder.working_profile", self._working_profile)
    return true
end

---Add a blackspot at the player's current position.
---@param radius? number  Default 20
---@return boolean ok
function ProfileRecorder:add_blackspot(radius)
    if self._state ~= "recording" then
        return false
    end

    local pos = self._bb:get("player.position")
    if not pos then
        return false
    end

    local blackspot = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        radius = radius or 20,
    }

    local blackspots = self._working_profile.blackspots
    blackspots[#blackspots + 1] = blackspot
    self._history[#self._history + 1] = { type = "blackspot" }

    self._bb:set("recorder.working_profile", self._working_profile)
    return true
end

---Remove the last added item (hotspot, vendor, or blackspot) in reverse chronological order.
---@return boolean ok
function ProfileRecorder:remove_last()
    if self._state ~= "recording" then
        return false
    end
    if #self._history == 0 then
        return false
    end

    local entry = table.remove(self._history)
    local list_key = entry.type .. "s"  -- "hotspot" -> "hotspots"
    local list = self._working_profile[list_key]
    if list and #list > 0 then
        table.remove(list)
    end

    if entry.type == "hotspot" then
        self._bb:set("recorder.hotspot_count", #self._working_profile.hotspots)
        self._bus:emit(Events.RECORDER_HOTSPOT_REMOVED, {})
    end

    self._bb:set("recorder.working_profile", self._working_profile)
    return true
end

---Finish recording. Validates the profile and returns it on success.
---@return table|nil profile
---@return string|nil error
function ProfileRecorder:finish_recording()
    if self._state ~= "recording" then
        return nil, "not recording"
    end

    local profile = self._working_profile
    local ok, errors = Validator.validate(profile)
    if not ok then
        local msg = table.concat(errors, "; ")
        return nil, msg
    end

    self._working_profile = nil
    self._history = {}
    self._state = "idle"

    self._bb:clear("recorder.state")
    self._bb:clear("recorder.working_profile")
    self._bb:clear("recorder.hotspot_count")

    self._bus:emit(Events.RECORDER_STOPPED, { profile = profile })
    return profile
end

---Cancel recording and discard working copy.
function ProfileRecorder:cancel_recording()
    self._working_profile = nil
    self._history = {}
    self._state = "idle"

    self._bb:clear("recorder.state")
    self._bb:clear("recorder.working_profile")
    self._bb:clear("recorder.hotspot_count")

    self._bus:emit(Events.RECORDER_STOPPED, { cancelled = true })
end

---@return key_checkbox|nil
function ProfileRecorder:get_keybind()
    return self._keybind
end

---Per-frame update. If recording and keybind is pressed (rising edge), adds a hotspot.
function ProfileRecorder:update()
    if self._state ~= "recording" then
        return
    end
    local pressed = self._keybind and self._keybind:get_keybind_state() or false
    if pressed and not self._keybind_was_pressed then
        self:add_hotspot()
    end
    self._keybind_was_pressed = pressed
end

return ProfileRecorder
