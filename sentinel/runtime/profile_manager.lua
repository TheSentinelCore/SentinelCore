-- sentinel/runtime/profile_manager.lua
-- Handles loading, saving, validating, and activating authoring profiles
-- Uses Sylvannas file I/O (core.read_data_file / core.write_data_file)
-- ADR 002 §4: load/save/compile/validate/activate/deactivate operations

local JSON = require("lib/JSON")

local ProfileManager = {}
ProfileManager.__index = ProfileManager

local DEFAULT_PROFILES_DIR = "sentinel/profiles"

---Create a new ProfileManager
---@param opts table|nil Optional config: { profiles_dir, blackboard, event_bus, compiler_bridge }
---@return table ProfileManager instance
function ProfileManager:new(opts)
    opts = opts or {}
    local o = setmetatable({}, ProfileManager)
    o._profiles_dir = opts.profiles_dir or DEFAULT_PROFILES_DIR
    o._blackboard = opts.blackboard
    o._event_bus = opts.event_bus
    o._compiler_bridge = opts.compiler_bridge
    o._runtime_context = opts.runtime_context
    o._active_profile_id = nil
    o._active_profile = nil
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

---Set the compiler bridge for integration
---@param bridge table CompilerBridge instance
function ProfileManager:set_compiler_bridge(bridge)
    self._compiler_bridge = bridge
end

---Set the runtime context
---@param ctx table RuntimeContext instance
function ProfileManager:set_runtime_context(ctx)
    self._runtime_context = ctx
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

    self._active_profile = profile
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
    if self._active_profile then
        self._active_profile.metadata = self._active_profile.metadata or {}
        self._active_profile.metadata.updated_at = profile.metadata.updated_at
    end
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
-- Validation (ADR 002 §11)
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
-- Compile (ADR 002 §4 - wires Phase 2 storage to Phase 6 compiler)
-- ============================================================================

---Compile a profile for runtime execution
---@param profile table The authoring profile to compile
---@return table|nil runtime_profile The compiled runtime profile
---@return string|nil error Error message if compilation failed
function ProfileManager:compile(profile)
    if not profile then
        return nil, "no profile to compile"
    end

    profile = profile or self._active_profile

    -- If compiler bridge is available, use full compilation pipeline
    if self._compiler_bridge then
        local runtime_profile, err = self:_run_compile_pipeline(profile)
        if err then
            return nil, err
        end
        return runtime_profile, nil
    end

    -- Fallback: basic structure validation without compiler bridge
    local errors = self.validate(profile)
    if #errors > 0 then
        return nil, "validation failed: " .. table.concat(errors, "; ")
    end

    -- Return as-is for now (backward compatibility)
    return profile, nil
end

---Run full compile pipeline via CompilerBridge (ADR 002 §4)
---@param profile table The authoring profile
---@return table|nil runtime_profile
---@return string|nil error
function ProfileManager:_run_compile_pipeline(profile)
    local compile_done = false
    local result = nil

    self._compiler_bridge:compile(function(err, runtime_profile)
        compile_done = true
        if err then
            result = { err = err, profile = nil }
        else
            result = { profile = runtime_profile, err = nil }
        end
    end)

    -- Synchronous wait for compile to finish (Lua is single-threaded)
    if not compile_done then
        return nil, "compile did not complete"
    end

    return result.profile, result.err
end

---Compile synchronously and return result immediately
---@param profile table The authoring profile to compile
---@return table result { success = boolean, runtime_profile = table|nil, diagnostics = table|nil }
function ProfileManager:compile_sync(profile)
    if not profile then
        return {
            success = false,
            runtime_profile = nil,
            diagnostics = {
                errors = { { code = "C-1001", message = "no profile to compile" } },
                warnings = {},
            },
        }
    end

if self._compiler_bridge and self._compiler_bridge.compile_sync then
         return self._compiler_bridge:compile_sync(profile)
     end

    return {
        success = true,
        runtime_profile = profile,
        diagnostics = { errors = {}, warnings = {} },
    }
end

---Run sync compile using compiler stages directly
---@param profile table
---@return table
function ProfileManager:_run_sync_compile(profile)
    -- Placeholder for direct stage execution
    return {
        success = true,
        runtime_profile = profile,
        diagnostics = { errors = {}, warnings = {} },
    }
end

-- ============================================================================
-- Activate / Deactivate (ADR 002 §4)
-- ============================================================================

---Activate a profile (store in blackboard and runtime context)
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

    -- Also sync to runtime context if available
    if self._runtime_context then
        local profile = self:get_active_profile()
        if profile then
            self._runtime_context:set_profile(profile)
        end
    end

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

    -- Clear runtime context if available
    if self._runtime_context then
        self._runtime_context:clear()
    end

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

    -- Also sync to runtime context
    if self._runtime_context and profile then
        self._runtime_context:set_profile(profile)
    end

    if profile and profile.profile_id then
        self._active_profile_id = profile.profile_id
    end
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
    return {}
end

-- ============================================================================
-- Hot Reload Support (ADR 002 §12)
-- ============================================================================

---Hot reload: swap to a new compiled profile without interrupting execution
---@param new_profile table The newly compiled RuntimeProfile
---@return boolean success
function ProfileManager:hot_reload(new_profile)
    if not new_profile then
        return false
    end

    -- Validate the new profile
    if not new_profile.operations or type(new_profile.operations) ~= "table" then
        return false
    end

    -- Swap to the new profile
    self._active_profile = new_profile

    if new_profile.profile_id then
        self._active_profile_id = new_profile.profile_id
        if self._blackboard then
            self._blackboard:set("module.runtime.active_profile", new_profile.profile_id)
        end
    end

    -- Clear and update runtime context
    if self._runtime_context then
        self._runtime_context:set_profile(new_profile)
    end

    return true
end

return ProfileManager