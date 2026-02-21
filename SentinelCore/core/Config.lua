local Defaults = require("core/Defaults")
local Persistence = require("core/Persistence")
local ErrorCodes = require("events/ErrorCodes")

---@class SentinelConfig
---@field private _runtime table
---@field private _policy table
---@field private _runtime_state table
---@field private _vendor_cache table
---@field private _profiles table
---@field private _persistence SentinelPersistence
local Config = {}
Config.__index = Config

---@private
---@param base table
---@param override table
---@return table
local function merge_table(base, override)
    local out = Defaults.copy(base or {})
    if type(override) ~= "table" then
        return out
    end
    for k, v in pairs(override) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = merge_table(out[k], v)
        else
            out[k] = Defaults.copy(v)
        end
    end
    return out
end

---@param overrides? table
---@param persistence? SentinelPersistence
---@return SentinelConfig
function Config:new(overrides, persistence)
    local o = setmetatable({}, Config)
    o._runtime = Defaults.build_runtime(overrides)
    o._policy = Defaults.copy(Defaults.policy)
    o._runtime_state = Defaults.copy(Defaults.runtime_state)
    o._vendor_cache = Defaults.copy(Defaults.vendor_cache)
    o._profiles = Defaults.copy(Defaults.profiles)
    o._profiles.profiles = {
        {
            profile_id = "default",
            name = "Default",
            runtime = Defaults.copy(o._runtime),
            policy = Defaults.copy(o._policy),
            updated_at_unix = 0,
        },
    }
    o._persistence = persistence or Persistence:new("SentinelCore")
    return o
end

---@private
---@param value any
---@return boolean
local function is_number_list(value)
    if type(value) ~= "table" then
        return false
    end
    for i = 1, #value do
        if type(value[i]) ~= "number" then
            return false
        end
    end
    return true
end

---@return boolean
---@return string|nil
function Config:validate_runtime()
    local cfg = self._runtime

    if cfg.recovery.auto_restart_max_attempts ~= 3 then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if not is_number_list(cfg.recovery.auto_restart_backoff_secs)
        or #cfg.recovery.auto_restart_backoff_secs ~= 3 then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if type(cfg.world_data.base_url) ~= "string" or cfg.world_data.base_url == "" then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if cfg.world_data.expected_game_version ~= "tbc" then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if cfg.vendor.min_free_slots == nil or tonumber(cfg.vendor.min_free_slots) == nil then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if cfg.vendor.min_free_slots < 0 then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if cfg.vendor.search_radius <= 0 then
        return false, ErrorCodes.CONFIG_INVALID
    end

    if cfg.targeting.base_radius <= 0 or cfg.targeting.max_radius < cfg.targeting.base_radius then
        return false, ErrorCodes.CONFIG_INVALID
    end

    return true, nil
end

---@return boolean
---@return string|nil
function Config:load_persistence()
    local policy, policy_err = self._persistence:load_policy()
    if not policy then
        return false, policy_err or ErrorCodes.POLICY_IO_ERROR
    end

    local runtime_state, state_err = self._persistence:load_runtime_state()
    if not runtime_state then
        return false, state_err or ErrorCodes.PERSISTENCE_CORRUPTED
    end

    local vendor_cache, cache_err = self._persistence:load_vendor_cache()
    if not vendor_cache then
        return false, cache_err or ErrorCodes.PERSISTENCE_CORRUPTED
    end

    local profiles, profiles_err = self._persistence:load_profiles(self._runtime, policy)
    if not profiles then
        return false, profiles_err or ErrorCodes.PERSISTENCE_CORRUPTED
    end

    self._policy = policy
    self._runtime_state = runtime_state
    self._vendor_cache = vendor_cache
    self._profiles = profiles

    local profile_ok = self:set_active_profile(self._profiles.active_profile_id)
    if not profile_ok then
        return false, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    return true, nil
end

---@return boolean
---@return string|nil
function Config:save_policy()
    return self._persistence:save_policy(self._policy)
end

---@return boolean
---@return string|nil
function Config:save_runtime_state()
    return self._persistence:save_runtime_state(self._runtime_state)
end

---@return boolean
---@return string|nil
function Config:save_vendor_cache()
    return self._persistence:save_vendor_cache(self._vendor_cache)
end

---@return boolean
---@return string|nil
function Config:save_profiles()
    return self._persistence:save_profiles(self._profiles)
end

---@return table
function Config:get_runtime()
    return Defaults.copy(self._runtime)
end

---@return table
function Config:get_policy()
    return Defaults.copy(self._policy)
end

---@param policy table
function Config:set_policy(policy)
    self._policy = Defaults.copy(policy)
    if type(self._policy.min_free_slots) == "number" then
        self._runtime.vendor.min_free_slots = self._policy.min_free_slots
    end
end

---@return table
function Config:get_runtime_state()
    return Defaults.copy(self._runtime_state)
end

---@param runtime_state table
function Config:set_runtime_state(runtime_state)
    self._runtime_state = Defaults.copy(runtime_state)
end

---@return table
function Config:get_vendor_cache()
    return Defaults.copy(self._vendor_cache)
end

---@param cache table
function Config:set_vendor_cache(cache)
    self._vendor_cache = Defaults.copy(cache)
end

---@param section string
---@param key string
---@param value any
function Config:set_runtime_value(section, key, value)
    if not self._runtime[section] then
        self._runtime[section] = {}
    end
    self._runtime[section][key] = value
end

---@param section string
---@param key string
---@param default any
---@return any
function Config:get_runtime_value(section, key, default)
    local sec = self._runtime[section]
    if not sec then
        return default
    end
    local value = sec[key]
    if value == nil then
        return default
    end
    return value
end

---@return SentinelPersistence
function Config:get_persistence()
    return self._persistence
end

---@private
---@param profile_id string
---@return number|nil
function Config:_find_profile_index(profile_id)
    local profiles = self._profiles and self._profiles.profiles or {}
    for i = 1, #profiles do
        if tostring(profiles[i].profile_id) == tostring(profile_id) then
            return i
        end
    end
    return nil
end

---@private
---@param profile table
function Config:_apply_profile(profile)
    self._runtime = Defaults.build_runtime(profile.runtime or {})
    self._policy = merge_table(Defaults.policy, profile.policy or {})

    if type(self._policy.min_free_slots) == "number" then
        self._runtime.vendor.min_free_slots = self._policy.min_free_slots
    end
end

---@return table
function Config:get_profiles()
    return Defaults.copy(self._profiles)
end

---@return table[]
function Config:list_profiles()
    local out = {}
    local profiles = self._profiles and self._profiles.profiles or {}
    for i = 1, #profiles do
        local p = profiles[i]
        out[#out + 1] = {
            profile_id = p.profile_id,
            name = p.name,
            updated_at_unix = p.updated_at_unix,
        }
    end
    return out
end

---@return string
function Config:get_active_profile_id()
    return tostring(self._profiles and self._profiles.active_profile_id or "default")
end

---@param profile_id string
---@return boolean
---@return string|nil
function Config:set_active_profile(profile_id)
    local index = self:_find_profile_index(profile_id)
    if not index then
        return false, ErrorCodes.PROFILE_NOT_FOUND
    end

    local profile = self._profiles.profiles[index]
    self._profiles.active_profile_id = profile.profile_id
    self:_apply_profile(profile)
    return true, nil
end

---@param profile_id string
---@param profile_name string
---@return boolean
---@return string|nil
function Config:save_as_profile(profile_id, profile_name)
    local id = tostring(profile_id or "")
    local name = tostring(profile_name or "")
    if id == "" or name == "" then
        return false, ErrorCodes.CONFIG_SCHEMA_INVALID
    end

    local snapshot = {
        profile_id = id,
        name = name,
        runtime = Defaults.copy(self._runtime),
        policy = Defaults.copy(self._policy),
        updated_at_unix = math.floor((core and core.time and core.time()) or 0),
    }

    local index = self:_find_profile_index(id)
    if index then
        self._profiles.profiles[index] = snapshot
    else
        self._profiles.profiles[#self._profiles.profiles + 1] = snapshot
    end
    self._profiles.active_profile_id = id
    return true, nil
end

---@param profile_name? string
---@return boolean
---@return string|nil
function Config:save_current_profile(profile_name)
    local active = self:get_active_profile_id()
    local index = self:_find_profile_index(active)
    if not index then
        return false, ErrorCodes.PROFILE_NOT_FOUND
    end

    local profile = self._profiles.profiles[index]
    profile.runtime = Defaults.copy(self._runtime)
    profile.policy = Defaults.copy(self._policy)
    profile.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
    if profile_name and tostring(profile_name) ~= "" then
        profile.name = tostring(profile_name)
    end
    return true, nil
end

---@param profile_id string
---@return boolean
---@return string|nil
function Config:delete_profile(profile_id)
    local profiles = self._profiles and self._profiles.profiles or {}
    if #profiles <= 1 then
        return false, ErrorCodes.PROFILE_DELETE_LAST
    end

    local index = self:_find_profile_index(profile_id)
    if not index then
        return false, ErrorCodes.PROFILE_NOT_FOUND
    end

    table.remove(profiles, index)
    if tostring(self._profiles.active_profile_id) == tostring(profile_id) then
        self._profiles.active_profile_id = profiles[1].profile_id
        self:_apply_profile(profiles[1])
    end
    return true, nil
end

---@param profile_id string
---@param new_name string
---@return boolean
---@return string|nil
function Config:rename_profile(profile_id, new_name)
    local name = tostring(new_name or "")
    if name == "" then
        return false, ErrorCodes.CONFIG_SCHEMA_INVALID
    end

    local index = self:_find_profile_index(profile_id)
    if not index then
        return false, ErrorCodes.PROFILE_NOT_FOUND
    end

    local profile = self._profiles.profiles[index]
    profile.name = name
    profile.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
    return true, nil
end

return Config
