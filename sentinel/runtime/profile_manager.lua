-- sentinel/runtime/profile_manager.lua
-- Handles loading, saving, validating, and activating authoring profiles
-- Uses Sylvannas file I/O (core.read_data_file / core.write_data_file)

local JSON = require("lib/JSON")

local ProfileManager = {}
ProfileManager.__index = ProfileManager

local DEFAULT_PROFILES_DIR = "sentinel/profiles"

---Create a new ProfileManager
---@param opts table|nil Optional config: { profiles_dir }
---@return table ProfileManager instance
function ProfileManager.new(opts)
    opts = opts or {}
    local o = setmetatable({}, ProfileManager)
    o._profiles_dir = opts.profiles_dir or DEFAULT_PROFILES_DIR
    o._active_profile_id = nil
    o._active_profile = nil  -- full profile table
    o._is_dirty = false
    return o
end

-- ============================================================================
-- Configuration
-- ============================================================================

---Get the profiles directory
---@return string
function ProfileManager:get_profiles_dir()
    return self._profiles_dir
end

-- ============================================================================
-- Dirty Tracking
-- ============================================================================

---Mark the active profile as dirty (modified)
function ProfileManager:mark_dirty()
    self._is_dirty = true
end

---Check if the active profile has unsaved changes
---@return boolean
function ProfileManager:is_dirty()
    return self._is_dirty
end

---Clear dirty flag (after save)
function ProfileManager:clear_dirty()
    self._is_dirty = false
end

-- ============================================================================
-- Load / Save (Sylvannas file I/O)
-- ============================================================================

---Load a profile from disk
---@param path string Relative path within scripts_data
---@return table|nil profile
---@return string|nil error
function ProfileManager:load(path)
    if not path or path == "" then
        return nil, "no path provided"
    end

    if not core or not core.read_data_file then
        return nil, "core.read_data_file not available"
    end

    local content = core.read_data_file(path)
    if not content or content == "" then
        return nil, "failed to read file: " .. path
    end

    local profile, parse_err = self:parse_json(content)
    if parse_err then
        return nil, parse_err
    end

    -- Validate basic structure
    local errors = self.validate(profile)
    if #errors > 0 then
        return nil, "validation failed: " .. table.concat(errors, "; ")
    end

    return profile, nil
end

---Save a profile to disk
---@param path string Relative path within scripts_data
---@param profile table Profile to save
---@return boolean|nil success
---@return string|nil error
function ProfileManager:save(path, profile)
    if not profile then
        return nil, "no profile to save"
    end

    if not path or path == "" then
        return nil, "no path provided"
    end

    -- Ensure parent folder exists
    if core and core.create_data_folder then
        -- Extract folder from path (everything before last /)
        local folder = path:match("^(.+)/[^/]+$")
        if folder then
            core.create_data_folder(folder)
        end
    end

    -- Update metadata
    profile.metadata = profile.metadata or {}
    profile.metadata.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")

    local json_str, serialize_err = self:encode_json(profile)
    if serialize_err then
        return nil, serialize_err
    end

    if not core or not core.write_data_file then
        return nil, "core.write_data_file not available"
    end

    local ok, write_err = pcall(core.write_data_file, path, json_str)
    if not ok then
        return nil, "failed to write file: " .. tostring(write_err)
    end

    self._is_dirty = false
    return true, nil
end

-- ============================================================================
-- JSON Helpers (wrappers for the JSON library)
-- ============================================================================

---Parse a JSON string into a Lua table
---@param json_str string
---@return table|nil data
---@return string|nil error
function ProfileManager:parse_json(json_str)
    if not json_str or json_str == "" then
        return nil, "empty JSON string"
    end
    local data, err = JSON.decode(json_str)
    if err then
        return nil, "JSON decode error: " .. tostring(err)
    end
    return data, nil
end

---Encode a Lua table to JSON string
---@param data table
---@return string|nil json_str
---@return string|nil error
function ProfileManager:encode_json(data)
    if not data then
        return nil, "no data to encode"
    end
    local json_str, err = JSON.encode(data, true)
    if err then
        return nil, "JSON encode error: " .. tostring(err)
    end
    return json_str, nil
end

-- ============================================================================
-- Validation
-- ============================================================================

---Validate a profile table against the canonical schema
---@param profile table
---@return table errors List of error strings (empty if valid)
function ProfileManager.validate(profile)
    local errors = {}

    if not profile then
        table.insert(errors, "profile is nil")
        return errors
    end

    -- Required root fields
    if not profile.name or profile.name == "" then
        table.insert(errors, "missing required field: name")
    end
    if not profile.author or profile.author == "" then
        table.insert(errors, "missing required field: author")
    end
    if not profile.schema_version or profile.schema_version == "" then
        table.insert(errors, "missing required field: schema_version")
    end

    -- Validate operations
    if profile.operations then
        if type(profile.operations) ~= "table" then
            table.insert(errors, "operations must be a table")
        else
            local seen_op_ids = {}
            for i, op in ipairs(profile.operations) do
                if not op.id then
                    table.insert(errors, "operation " .. i .. " missing id")
                elseif seen_op_ids[op.id] then
                    table.insert(errors, "duplicate operation id: " .. tostring(op.id))
                else
                    seen_op_ids[op.id] = true
                end

                if not op.name or op.name == "" then
                    table.insert(errors, "operation " .. i .. " missing name")
                end

                -- Check for duplicate action IDs within operation
                if op.actions and type(op.actions) == "table" then
                    local seen_action_ids = {}
                    for j, action in ipairs(op.actions) do
                        if action.id then
                            if seen_action_ids[action.id] then
                                table.insert(errors,
                                    "duplicate action id in operation '" ..
                                    tostring(op.name or "?") .. "': " .. tostring(action.id))
                            else
                                seen_action_ids[action.id] = true
                            end
                        end
                    end
                end
            end
        end
    end

    return errors
end

-- ============================================================================
-- Compile (placeholder for #18 Rust compiler integration)
-- ============================================================================

---Compile a profile for runtime execution (placeholder)
---@param profile table
---@return table|nil compiled
---@return string|nil error
function ProfileManager:compile(profile)
    if not profile then
        return nil, "no profile to compile"
    end
    -- For now, return the profile as-is
    -- This will be replaced with actual compiler integration in #18
    return profile, nil
end

-- ============================================================================
-- Activate / Deactivate
-- ============================================================================

---Activate a profile (store in blackboard)
---@param blackboard table The SentinelCore blackboard
---@param profile_id string|integer The profile identifier
---@return boolean|nil success
---@return string|nil error
function ProfileManager:activate(blackboard, profile_id)
    if not profile_id then
        return nil, "no profile id provided"
    end
    if not blackboard then
        return nil, "no blackboard provided"
    end

    blackboard:set("module.runtime.active_profile", profile_id)
    self._active_profile_id = profile_id
    return true, nil
end

---Deactivate the current profile
---@param blackboard table
---@return boolean|nil success
---@return string|nil error
function ProfileManager:deactivate(blackboard)
    if not blackboard then
        return nil, "no blackboard provided"
    end

    blackboard:set("module.runtime.active_profile", nil)
    self._active_profile_id = nil
    self._active_profile = nil
    self._is_dirty = false
    return true, nil
end

---Get the active profile ID
---@return string|integer|nil
function ProfileManager:get_active_profile_id()
    return self._active_profile_id
end

---Set the active profile table (after load/compile)
---@param profile table
function ProfileManager:set_active_profile(profile)
    self._active_profile = profile
end

---Get the active profile table
---@return table|nil
function ProfileManager:get_active_profile()
    return self._active_profile
end

-- ============================================================================
-- Profile Listing
-- ============================================================================

---List available profiles in the profiles directory
---@return table List of profile filenames
function ProfileManager:list_profiles()
    -- Sylvannas may not have a directory listing API
    -- This will be populated when such an API becomes available
    -- For now, consumers track their own known profiles
    return {}
end

return ProfileManager
