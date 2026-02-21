local JSON = require("lib/JSON")
local Defaults = require("core/Defaults")
local ErrorCodes = require("events/ErrorCodes")

---@class SentinelPersistence
---@field private _root string
---@field private _paths table
local Persistence = {}
Persistence.__index = Persistence

---@param root? string
---@return SentinelPersistence
function Persistence:new(root)
    local o = setmetatable({}, Persistence)
    o._root = root or "SentinelCore"
    o._paths = {
        policy = o._root .. "/config/vendor_inventory_policy.v1.json",
        profiles = o._root .. "/config/runtime_profiles.v1.json",
        runtime_state = o._root .. "/state/runtime_state.v1.json",
        vendor_cache = o._root .. "/cache/vendor_runtime_cache.v1.json",
    }
    return o
end

---@private
function Persistence:_ensure_dirs()
    if not core or not core.create_data_folder then
        return
    end
    core.create_data_folder(self._root)
    core.create_data_folder(self._root .. "/config")
    core.create_data_folder(self._root .. "/state")
    core.create_data_folder(self._root .. "/cache")
end

---@private
---@param path string
---@return table|nil
---@return string|nil
function Persistence:_read_json(path)
    if not core or not core.read_data_file then
        return nil, ErrorCodes.POLICY_IO_ERROR
    end
    local raw = core.read_data_file(path)
    if not raw or raw == "" then
        return nil, nil
    end

    local parsed, err = JSON.decode(raw)
    if not parsed then
        return nil, err or "decode_failed"
    end

    return parsed, nil
end

---@private
---@param path string
---@param data table
---@param expected_schema string
---@return boolean
---@return string|nil
function Persistence:_write_json_atomic(path, data, expected_schema)
    if not core or not core.create_data_file or not core.write_data_file then
        return false, ErrorCodes.POLICY_IO_ERROR
    end

    self:_ensure_dirs()

    local tmp_path = path .. ".tmp"
    local encoded, enc_err = JSON.encode(data, true)
    if not encoded or encoded == "" then
        return false, enc_err or "encode_failed"
    end

    -- Monotonic write guard for multi-client contention: do not overwrite a
    -- newer on-disk document with an older timestamped payload.
    local existing_raw = core.read_data_file(path) or ""
    if existing_raw ~= "" then
        local existing_parsed, _ = JSON.decode(existing_raw)
        if type(existing_parsed) == "table"
            and existing_parsed.schema_version == expected_schema
            and type(existing_parsed.updated_at_unix) == "number"
            and type(data.updated_at_unix) == "number"
            and existing_parsed.updated_at_unix > data.updated_at_unix then
            return false, ErrorCodes.POLICY_IO_ERROR
        end
    end

    core.create_data_file(tmp_path)
    core.write_data_file(tmp_path, encoded)

    -- Read-back validation before replace.
    local tmp_raw = core.read_data_file(tmp_path)
    local tmp_parsed, tmp_err = JSON.decode(tmp_raw or "")
    if not tmp_parsed then
        return false, "tmp_verify_failed:" .. tostring(tmp_err)
    end
    if tmp_parsed.schema_version ~= expected_schema then
        return false, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end

    core.create_data_file(path)
    core.write_data_file(path, tmp_raw)

    local final_raw = core.read_data_file(path)
    local final_parsed, final_err = JSON.decode(final_raw or "")
    if not final_parsed then
        return false, "final_verify_failed:" .. tostring(final_err)
    end
    if final_parsed.schema_version ~= expected_schema then
        return false, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end

    return true, nil
end

---@private
---@param list any
---@return boolean
local function is_numeric_array(list)
    if type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        if type(list[i]) ~= "number" then
            return false
        end
    end
    return true
end

---@private
---@param t table
---@param required string[]
---@return boolean
local function has_required_keys(t, required)
    for i = 1, #required do
        if t[required[i]] == nil then
            return false
        end
    end
    return true
end

---@private
---@param policy table
---@return boolean
---@return string|nil
function Persistence:_validate_policy(policy)
    if policy.schema_version ~= "vendor_inventory_policy.v1" then
        return false, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end

    if not is_numeric_array(policy.never_sell) then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end
    if not is_numeric_array(policy.always_sell) then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end

    if type(policy.keep_stack_min) ~= "table" then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end
    for k, v in pairs(policy.keep_stack_min) do
        if tonumber(k) == nil or type(v) ~= "number" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
    end

    if type(policy.special_rules) ~= "table" then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end

    local boolean_keys = {
        "repair_enabled",
        "sell_gray",
        "sell_white",
        "sell_green",
        "sell_blue",
        "sell_epic",
    }
    for i = 1, #boolean_keys do
        local key = boolean_keys[i]
        if type(policy[key]) ~= "boolean" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
    end

    if policy.sell_quality_max ~= nil and tonumber(policy.sell_quality_max) == nil then
        return false, ErrorCodes.INVENTORY_POLICY_INVALID
    end
    for i = 1, #policy.special_rules do
        local rule = policy.special_rules[i]
        if type(rule) ~= "table" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if rule.action ~= "keep" and rule.action ~= "sell" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if rule.match ~= nil and type(rule.match) ~= "table" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        local match = rule.match or {}
        if match.item_ids ~= nil and type(match.item_ids) ~= "table" then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if type(match.item_ids) == "table" then
            for j = 1, #match.item_ids do
                if tonumber(match.item_ids[j]) == nil then
                    return false, ErrorCodes.INVENTORY_POLICY_INVALID
                end
            end
        end
        if match.quality_min ~= nil and tonumber(match.quality_min) == nil then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if match.quality_max ~= nil and tonumber(match.quality_max) == nil then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if match.stack_min ~= nil and tonumber(match.stack_min) == nil then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if match.stack_max ~= nil and tonumber(match.stack_max) == nil then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
        if rule.keep_stack_min ~= nil and tonumber(rule.keep_stack_min) == nil then
            return false, ErrorCodes.INVENTORY_POLICY_INVALID
        end
    end

    return true, nil
end

---@private
---@param source table
---@param defaults table
---@return table
local function merge_defaults(source, defaults)
    local out = Defaults.copy(defaults)
    for k, v in pairs(source) do
        if type(v) == "table" and type(out[k]) == "table" then
            local merged = {}
            for dk, dv in pairs(out[k]) do
                merged[dk] = Defaults.copy(dv)
            end
            for sk, sv in pairs(v) do
                merged[sk] = Defaults.copy(sv)
            end
            out[k] = merged
        else
            out[k] = Defaults.copy(v)
        end
    end
    return out
end

---@return table policy
---@return string|nil error_code
---@return string[] warnings
function Persistence:load_policy()
    self:_ensure_dirs()
    local warnings = {}
    local parsed, err = self:_read_json(self._paths.policy)
    if err and err ~= "" then
        warnings[#warnings + 1] = "policy_decode_failed"
        parsed = nil
    end

    if not parsed then
        local default_policy = Defaults.copy(Defaults.policy)
        default_policy.updated_at_unix = core and core.time and math.floor(core.time()) or 0
        self:save_policy(default_policy)
        return default_policy, nil, warnings
    end

    if parsed.schema_version ~= "vendor_inventory_policy.v1" then
        return nil, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID, warnings
    end

    -- Policy file is user-owned: missing fields are recovered with defaults.
    local merged = merge_defaults(parsed, Defaults.policy)
    local valid, val_err = self:_validate_policy(merged)
    if not valid then
        return nil, val_err, warnings
    end

    return merged, nil, warnings
end

---@param policy table
---@return boolean
---@return string|nil
function Persistence:save_policy(policy)
    local valid, val_err = self:_validate_policy(policy)
    if not valid then
        return false, val_err
    end

    policy.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
    return self:_write_json_atomic(self._paths.policy, policy, "vendor_inventory_policy.v1")
end

---@return table|nil state
---@return string|nil error_code
function Persistence:load_runtime_state()
    self:_ensure_dirs()
    local parsed, err = self:_read_json(self._paths.runtime_state)
    if err and err ~= "" then
        return nil, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    if not parsed then
        local defaults = Defaults.copy(Defaults.runtime_state)
        defaults.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
        local ok = self:save_runtime_state(defaults)
        if not ok then
            return nil, ErrorCodes.POLICY_IO_ERROR
        end
        return defaults, nil
    end

    if parsed.schema_version ~= "runtime_state.v1" then
        return nil, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end

    local required = {
        "schema_version",
        "last_session_id",
        "last_state",
        "last_error_code",
        "auto_restart_attempts_used",
        "last_known_context",
        "last_grind_anchor",
        "updated_at_unix",
    }
    if not has_required_keys(parsed, required) then
        return nil, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    return parsed, nil
end

---@param runtime_state table
---@return boolean
---@return string|nil
function Persistence:save_runtime_state(runtime_state)
    runtime_state.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
    return self:_write_json_atomic(self._paths.runtime_state, runtime_state, "runtime_state.v1")
end

---@return table|nil cache
---@return string|nil error_code
function Persistence:load_vendor_cache()
    self:_ensure_dirs()
    local parsed, err = self:_read_json(self._paths.vendor_cache)
    if err and err ~= "" then
        return nil, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    if not parsed then
        local defaults = Defaults.copy(Defaults.vendor_cache)
        defaults.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
        local ok = self:save_vendor_cache(defaults)
        if not ok then
            return nil, ErrorCodes.POLICY_IO_ERROR
        end
        return defaults, nil
    end

    if parsed.schema_version ~= "vendor_runtime_cache.v1" then
        return nil, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end

    if type(parsed.entries) ~= "table" then
        return nil, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    local now = math.floor((core and core.time and core.time()) or 0)
    local pruned = {}
    for i = 1, #parsed.entries do
        local entry = parsed.entries[i]
        if type(entry) == "table" then
            local blacklist_until = tonumber(entry.blacklist_until_unix) or 0
            if blacklist_until > now then
                pruned[#pruned + 1] = entry
            end
        end
    end
    table.sort(pruned, function(a, b)
        return (tonumber(a.last_seen_unix) or 0) > (tonumber(b.last_seen_unix) or 0)
    end)
    while #pruned > 500 do
        table.remove(pruned)
    end
    parsed.entries = pruned

    return parsed, nil
end

---@param cache table
---@return boolean
---@return string|nil
function Persistence:save_vendor_cache(cache)
    cache.updated_at_unix = math.floor((core and core.time and core.time()) or 0)
    return self:_write_json_atomic(self._paths.vendor_cache, cache, "vendor_runtime_cache.v1")
end

---@private
---@param payload table
---@return boolean
---@return string|nil
function Persistence:_validate_profiles_payload(payload)
    if type(payload) ~= "table" then
        return false, ErrorCodes.CONFIG_SCHEMA_INVALID
    end
    if payload.schema_version ~= "runtime_profiles.v1" then
        return false, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID
    end
    if type(payload.profiles) ~= "table" or #payload.profiles < 1 then
        return false, ErrorCodes.CONFIG_SCHEMA_INVALID
    end

    local seen_ids = {}
    for i = 1, #payload.profiles do
        local profile = payload.profiles[i]
        if type(profile) ~= "table" then
            return false, ErrorCodes.CONFIG_SCHEMA_INVALID
        end
        local profile_id = tostring(profile.profile_id or "")
        local profile_name = tostring(profile.name or "")
        if profile_id == "" or profile_name == "" then
            return false, ErrorCodes.CONFIG_SCHEMA_INVALID
        end
        if seen_ids[profile_id] then
            return false, ErrorCodes.CONFIG_SCHEMA_INVALID
        end
        seen_ids[profile_id] = true

        if type(profile.runtime) ~= "table" then
            return false, ErrorCodes.CONFIG_SCHEMA_INVALID
        end
        if type(profile.policy) ~= "table" then
            return false, ErrorCodes.CONFIG_SCHEMA_INVALID
        end

        local ok_policy, policy_err = self:_validate_policy(profile.policy)
        if not ok_policy then
            return false, policy_err or ErrorCodes.INVENTORY_POLICY_INVALID
        end
    end

    local active = tostring(payload.active_profile_id or "")
    if active == "" or not seen_ids[active] then
        return false, ErrorCodes.CONFIG_SCHEMA_INVALID
    end

    return true, nil
end

---@param default_runtime? table
---@param default_policy? table
---@return table|nil profiles
---@return string|nil error_code
function Persistence:load_profiles(default_runtime, default_policy)
    self:_ensure_dirs()
    local parsed, err = self:_read_json(self._paths.profiles)
    if err and err ~= "" then
        return nil, ErrorCodes.PERSISTENCE_CORRUPTED
    end

    if not parsed then
        local now = math.floor((core and core.time and core.time()) or 0)
        local default_payload = Defaults.copy(Defaults.profiles)
        default_payload.active_profile_id = "default"
        default_payload.updated_at_unix = now
        default_payload.profiles = {
            {
                profile_id = "default",
                name = "Default",
                runtime = Defaults.copy(default_runtime or Defaults.build_runtime()),
                policy = Defaults.copy(default_policy or Defaults.policy),
                updated_at_unix = now,
            },
        }
        local ok, save_err = self:save_profiles(default_payload)
        if not ok then
            return nil, save_err or ErrorCodes.POLICY_IO_ERROR
        end
        return default_payload, nil
    end

    local valid, val_err = self:_validate_profiles_payload(parsed)
    if not valid then
        return nil, val_err or ErrorCodes.CONFIG_SCHEMA_INVALID
    end

    return parsed, nil
end

---@param payload table
---@return boolean
---@return string|nil
function Persistence:save_profiles(payload)
    local valid, val_err = self:_validate_profiles_payload(payload)
    if not valid then
        return false, val_err
    end

    local now = math.floor((core and core.time and core.time()) or 0)
    payload.updated_at_unix = now
    for i = 1, #payload.profiles do
        local profile = payload.profiles[i]
        profile.updated_at_unix = now
    end
    return self:_write_json_atomic(self._paths.profiles, payload, "runtime_profiles.v1")
end

---@return table
function Persistence:get_paths()
    return Defaults.copy(self._paths)
end

return Persistence
