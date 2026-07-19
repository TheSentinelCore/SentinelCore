-- sentinel/runtime/storage_manager.lua
-- Phase 2 storage: Tier1 (compiled runtime profiles) <-> Tier2 (authoring profiles)
-- with per-operation file storage, atomic writes, and schema migration on load.
--
-- Design notes (deep module):
--   * Storage is decoupled from the Sylvannas `core` globals via an injectable
--     `file_io` adapter. The default adapter wraps _G.core.{read,write,create}_data_file
--     plus an atomic rename; tests inject an in-memory adapter.
--   * A profile is stored as a MANIFEST (<profile_id>.json) plus one file per
--     operation (<profile_id>/ops/<op_id>.json). This keeps per-operation edits
--     from rewriting the entire profile and lets the engine reload a single op.
--   * Tier2 = authoring profile (what the author writes). Tier1 = compiled runtime
--     profile (what the engine executes). load_tier1() resolves from Tier2 when the
--     compiled copy is missing or stale.

local JSON = require("lib/JSON")
local MigrationRegistry = require("runtime/migration_registry")

local StorageManager = {}
StorageManager.__index = StorageManager

local TIER1_DIR = "sentinel/profiles/compiled"
local TIER2_DIR = "sentinel/profiles/authoring"

-- ============================================================================
-- Construction
-- ============================================================================

---@param opts table|nil { file_io = adapter, migration_registry = MigrationRegistry }
---  adapter interface:
---    read(path) -> (string|nil content, string|nil err)
---    write(path, content) -> (boolean ok, string|nil err)
---    rename(src, dst) -> (boolean ok, string|nil err)   -- atomic move
---    mkdir(path) -> (boolean ok, string|nil err)
---    list(dir) -> (table paths|nil, string|nil err)
function StorageManager:new(opts)
    opts = opts or {}
    local o = setmetatable({}, StorageManager)
    o._file_io = opts.file_io or StorageManager._default_core_adapter()
    o._migration = opts.migration_registry or MigrationRegistry:new()
    return o
end

---Default adapter wrapping the Sylvannas `core` globals.
---Atomicity: write to a `.tmp` sibling then rename; if `core.rename_data_file`
---is unavailable, fall back to overwrite-write (best effort).
function StorageManager._default_core_adapter()
    local core = _G.core or {}
    return {
        read = function(path)
            if not core.read_data_file then return nil, "no reader" end
            return core.read_data_file(path)
        end,
        write = function(path, content)
            if not core.write_data_file then return false, "no writer" end
            return core.write_data_file(path, content)
        end,
        rename = function(src, dst)
            if core.rename_data_file then
                return core.rename_data_file(src, dst)
            end
            -- Fallback: read src, write dst, then best-effort delete src.
            local content = core.read_data_file and core.read_data_file(src)
            if not content then return false, "rename source unreadable" end
            local ok = core.write_data_file and core.write_data_file(dst, content)
            if not ok then return false, "rename write failed" end
            if core.delete_data_file then
                pcall(core.delete_data_file, src)
            end
            return true, nil
        end,
        mkdir = function(path)
            if core.create_data_folder then
                return pcall(core.create_data_folder, path)
            end
            return true, nil
        end,
        list = function(dir)
            if core.list_data_files then
                return core.list_data_files(dir)
            end
            return {}, nil
        end,
    }
end

-- ============================================================================
-- JSON helpers
-- ============================================================================

function StorageManager:_decode(str)
    if not str or str == "" then return nil, "empty content" end
    local data, err = JSON.decode(str)
    if err then return nil, "JSON decode error: " .. tostring(err) end
    return data, nil
end

function StorageManager:_encode(data)
    local str, err = JSON.encode(data, true)
    if err then return nil, "JSON encode error: " .. tostring(err) end
    return str, nil
end

-- ============================================================================
-- Atomic write
-- ============================================================================

---Write content atomically: temp file then rename over target.
---@param path string
---@param content string
---@return boolean ok, string|nil err
function StorageManager:_atomic_write(target_path, content)
    local final_path = target_path
    local dir = final_path:match("^(.+)/[^/]+$")
    if dir then
        self._file_io.mkdir(dir)
    end
    local tmp_path = final_path .. ".tmp"
    local ok, werr = self._file_io.write(tmp_path, content)
    if not ok then
        return false, "temp write failed: " .. tostring(werr)
    end
    local rok, rerr = self._file_io.rename(tmp_path, final_path)
    if not rok then
        -- Last-ditch: write directly to the target.
        ok, werr = self._file_io.write(final_path, content)
        if not ok then
            return false, "atomic rename failed and direct write failed: " .. tostring(rerr)
        end
    end
    return true, nil
end

-- ============================================================================
-- Path helpers
-- ============================================================================

function StorageManager:_tier2_manifest_path(profile_id)
    return TIER2_DIR .. "/" .. profile_id .. ".json"
end
function StorageManager:_tier2_op_path(profile_id, op_id)
    return TIER2_DIR .. "/" .. profile_id .. "/ops/" .. op_id .. ".json"
end
function StorageManager:_tier1_manifest_path(profile_id)
    return TIER1_DIR .. "/" .. profile_id .. ".json"
end

-- ============================================================================
-- Migration on load
-- ============================================================================

---Load a raw profile table, migrating it to the latest schema version.
---@return table profile, table warnings
function StorageManager:_load_and_migrate(path)
    local content, rerr = self._file_io.read(path)
    if not content then
        return nil, { "read failed: " .. tostring(rerr) }
    end
    local profile, derr = self:_decode(content)
    if not profile then
        return nil, { "decode failed: " .. tostring(derr) }
    end
    local result = self._migration:migrate(profile)
    return result.profile, result.warnings or {}
end

-- ============================================================================
-- Tier2 (authoring) storage
-- ============================================================================

---Save an authoring profile split into a manifest + per-operation files.
---@param profile table Authoring profile (must have profile_id + operations)
---@return boolean ok, string|nil err
function StorageManager:save_tier2(profile)
    if not profile or not profile.profile_id then
        return false, "profile missing profile_id"
    end
    local pid = profile.profile_id

    -- Marshal the manifest WITHOUT the full operations payload.
    local manifest = self:_deep_copy(profile)
    manifest.operations = {}
    for _, op in ipairs(profile.operations or {}) do
        table.insert(manifest.operations, { id = op.id, name = op.name })
    end
    manifest.storage_layout = "per-operation"
    manifest.tier = "tier2"

    local mcontent, merr = self:_encode(manifest)
    if merr then return false, merr end
    local ok, werr = self:_atomic_write(self:_tier2_manifest_path(pid), mcontent)
    if not ok then return false, werr end

    -- Write each operation to its own file.
    for _, op in ipairs(profile.operations or {}) do
        if not op.id then return false, "operation missing id" end
        local oc, oerr = self:_encode(op)
        if oerr then return false, oerr end
        local ok2, werr2 = self:_atomic_write(self:_tier2_op_path(pid, op.id), oc)
        if not ok2 then return false, werr2 end
    end
    return true, nil
end

---Load a Tier2 authoring profile, reassembling manifest + operation files.
---@param profile_id string
---@return table|nil profile, table warnings, string|nil err
function StorageManager:load_tier2(profile_id)
    local manifest, warns = self:_load_and_migrate(self:_tier2_manifest_path(profile_id))
    if not manifest then
        return nil, warns, "manifest load failed"
    end

    local operations = {}
    for _, ref in ipairs(manifest.operations or {}) do
        local op, owarns = self:_load_and_migrate(self:_tier2_op_path(profile_id, ref.id))
        if not op then
            return nil, warns, "operation load failed: " .. tostring(ref.id)
        end
        table.insert(operations, op)
        if owarns then
            for _, w in ipairs(owarns) do table.insert(warns, w) end
        end
    end
    manifest.operations = operations
    return manifest, warns, nil
end

-- ============================================================================
-- Tier1 (compiled runtime) storage
-- ============================================================================

---Save a compiled runtime profile (single file; operations are nested).
---@param runtime_profile table
---@return boolean ok, string|nil err
function StorageManager:save_tier1(runtime_profile)
    if not runtime_profile or not runtime_profile.profile_id then
        return false, "runtime profile missing profile_id"
    end
    local snapshot = self:_deep_copy(runtime_profile)
    snapshot.tier = "tier1"
    snapshot.storage_layout = "single-file"
    local content, err = self:_encode(snapshot)
    if err then return false, err end
    return self:_atomic_write(self:_tier1_manifest_path(runtime_profile.profile_id), content)
end

---Load a Tier1 compiled profile, resolving from Tier2 if missing.
---If a compiler_fn is supplied and Tier1 is absent, the Tier2 profile is loaded
---and passed through compiler_fn(profile) to produce the Tier1 artifact.
---@param profile_id string
---@param compiler_fn function|nil function(tier2_profile) -> tier1_profile|nil, err
---@return table|nil runtime_profile, table warnings, string|nil err
function StorageManager:load_tier1(profile_id, compiler_fn)
    local content, rerr = self._file_io.read(self:_tier1_manifest_path(profile_id))
    if content then
        local profile, derr = self:_decode(content)
        if profile then
            return profile, {}, nil
        end
        -- Corrupt Tier1; fall through to resolution from Tier2.
    end

    -- Resolve from Tier2.
    local tier2, warns, lerr = self:load_tier2(profile_id)
    if not tier2 then
        return nil, warns, lerr or "tier1 and tier2 both unavailable"
    end
    if not compiler_fn then
        -- No compiler available: return the Tier2 profile as a best-effort Tier1.
        tier2.tier = "tier1"
        return tier2, warns, nil
    end
    local compiled, cerr = compiler_fn(tier2)
    if not compiled then
        return nil, warns, cerr or "compilation failed"
    end
    -- Persist the freshly compiled Tier1 for next time.
    self:save_tier1(compiled)
    return compiled, warns, nil
end

-- ============================================================================
-- Helpers
-- ============================================================================

function StorageManager:_deep_copy(profile)
    local function copy(v)
        if type(v) ~= "table" then return v end
        local t = {}
        for k, val in pairs(v) do t[copy(k)] = copy(val) end
        return t
    end
    return copy(profile)
end

return StorageManager
