-- sentinel/runtime/migration_registry.lua
-- Schema version migration system for SentinelCore profiles
-- Handles version-to-version migration with error codes M-1001 through M-1004

local MigrationRegistry = {}
MigrationRegistry.__index = MigrationRegistry

local CURRENT_VERSION = "1.0.0"

-- ============================================================================
-- Construction
-- ============================================================================

---Create a new MigrationRegistry
---@return table MigrationRegistry instance
function MigrationRegistry:new()
    local o = setmetatable({}, MigrationRegistry)
    o._migrations = {}         -- { [from..to] = fn }
    o._version_chain = {}      -- ordered list of { from, to }
    o._latest_version = "0.0.0"
    return o
end

-- ============================================================================
-- Registration
-- ============================================================================

---Register a migration step
---@param from_version string Source schema version
---@param to_version string Target schema version
---@param migration_fn function Function(profile) -> profile, errors, warnings
function MigrationRegistry:register(from_version, to_version, migration_fn)
    local key = from_version .. ".." .. to_version
    self._migrations[key] = migration_fn
    table.insert(self._version_chain, { from = from_version, to = to_version })

    -- Track the latest version by lexical comparison (semver-like)
    if self:_version_greater(to_version, self._latest_version) then
        self._latest_version = to_version
    end
end

---Get the current (latest registered) version
---@return string
function MigrationRegistry:get_current_version()
    return self._latest_version
end

---Get the version history (all registered migrations)
---@return table List of { from, to } objects
function MigrationRegistry:get_version_history()
    local history = {}
    for _, entry in ipairs(self._version_chain) do
        table.insert(history, { from = entry.from, to = entry.to })
    end
    return history
end

-- ============================================================================
-- Migration Execution
-- ============================================================================

---Migrate a profile to the latest version
---@param profile table The profile to migrate
---@return table result { profile = table, errors = table, warnings = table }
function MigrationRegistry:migrate(profile)
    local errors = {}
    local warnings = {}
    local profile_version = profile.schema_version or "0.0.0"

    -- Validate version format
    if type(profile_version) ~= "string" then
        table.insert(errors, {
            code = "M-1004",
            message = "unknown profile version format: " .. tostring(profile_version),
        })
        return { profile = profile, errors = errors, warnings = warnings }
    end

    -- Check for downgrade
    if self:_version_greater(profile_version, self._latest_version) then
        table.insert(errors, {
            code = "M-1003",
            message = "version downgrade detected: profile is " .. profile_version
                .. ", latest is " .. self._latest_version,
        })
        return { profile = profile, errors = errors, warnings = warnings }
    end

    -- Walk the migration chain
    local current = profile_version
    while current ~= self._latest_version do
        local found = false
        for _, entry in ipairs(self._version_chain) do
            if entry.from == current then
                local key = entry.from .. ".." .. entry.to
                local migration_fn = self._migrations[key]
                if migration_fn then
                    local ok, result = pcall(migration_fn, profile)
                    if not ok then
                        table.insert(errors, {
                            code = "M-1002",
                            message = "migration function failed: " .. tostring(result),
                        })
                        return { profile = profile, errors = errors, warnings = warnings }
                    end
                    -- migration_fn returns { profile, step_errors, step_warnings }
                    profile = result.profile or profile
                    if result.errors then
                        for _, e in ipairs(result.errors) do
                            table.insert(errors, e)
                        end
                    end
                    if result.warnings then
                        for _, w in ipairs(result.warnings) do
                            table.insert(warnings, w)
                        end
                    end
                    current = entry.to
                    found = true
                    break
                end
            end
        end
        if not found then
            table.insert(errors, {
                code = "M-1001",
                message = "migration not found for version jump from " .. current
                    .. " to " .. self._latest_version,
            })
            break
        end
    end

    return { profile = profile, errors = errors, warnings = warnings }
end

-- ============================================================================
-- Version Comparison Helpers
-- ============================================================================

---Compare two semver-like version strings
---@param a string
---@param b string
---@return boolean true if a > b
function MigrationRegistry:_version_greater(a, b)
    local parts_a = self:_parse_version(a)
    local parts_b = self:_parse_version(b)
    for i = 1, 3 do
        if (parts_a[i] or 0) ~= (parts_b[i] or 0) then
            return (parts_a[i] or 0) > (parts_b[i] or 0)
        end
    end
    return false
end

---Parse a version string into numeric parts
---@param version string e.g. "1.0.0"
---@return table { major, minor, patch }
function MigrationRegistry:_parse_version(version)
    if type(version) ~= "string" then
        return { 0, 0, 0 }
    end
    local parts = {}
    for part in version:gmatch("(%d+)") do
        table.insert(parts, tonumber(part) or 0)
    end
    -- Ensure at least 3 parts
    while #parts < 3 do
        table.insert(parts, 0)
    end
    return parts
end

-- ============================================================================
-- Built-in Migration: v0.0.0 → v1.0.0
-- ============================================================================

---Built-in migration from v0 to v1
---@param profile table
---@return table { profile, errors, warnings }
function MigrationRegistry:_migrate_v0_to_v1(profile)
    local errors = {}
    local warnings = {}

    -- Ensure schema_version
    if not profile.schema_version then
        profile.schema_version = "1.0"
        table.insert(warnings, "added missing schema_version")
    end

    -- Ensure metadata.compiler_version
    profile.metadata = profile.metadata or {}
    if not profile.metadata.compiler_version then
        profile.metadata.compiler_version = "1.0.0"
        table.insert(warnings, "added missing metadata.compiler_version")
    end

    -- Ensure operations array exists
    if not profile.operations then
        profile.operations = {}
        table.insert(warnings, "added missing operations array")
    end
    if type(profile.operations) ~= "table" then
        profile.operations = {}
        table.insert(warnings, "replaced non-table operations with empty array")
    end

    -- Ensure each operation has an id field
    for i, op in ipairs(profile.operations) do
        if not op.id then
            op.id = self:_generate_id()
            table.insert(warnings, "generated id for operation " .. i)
        end
    end

    return { profile = profile, errors = errors, warnings = warnings }
end

---Generate a simple UUID-like string
---@return string
function MigrationRegistry:_generate_id()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return template:gsub("[xy]", function(c)
        local v = (math.random(0, 15))
        if c == "x" then
            return string.format("%x", v)
        else
            return string.format("%x", v % 4 + 8)
        end
    end)
end

-- ============================================================================
-- Initialize default migration
-- ============================================================================

-- Register the built-in v0 → v1 migration
-- This runs when the registry is first required
local function setup_default_migrations(registry)
    registry:register("0.0.0", "1.0.0", function(profile)
        return registry:_migrate_v0_to_v1(profile)
    end)
end

-- Override new() to auto-setup defaults
local original_new = MigrationRegistry.new
function MigrationRegistry:new(...)
    local o = original_new(self, ...)
    setup_default_migrations(o)
    return o
end

return MigrationRegistry
