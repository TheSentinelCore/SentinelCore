-- kernel/manifest.lua
-- The plugin contract's schema, and the validator that refuses a bad manifest BY NAME.
--
-- ADR 08 §12 puts this in Phase 3 explicitly, with the reasoning: "RXPGuides ships without one --
-- an unresolved `#completewith foo` silently never fires. LazyBot is worse: GrindingProfile
-- .LoadFile is eight independent `try { } catch { }` blocks with EMPTY CATCH BODIES, each falling
-- back to a hardcoded default, so a profile can be 90% broken and still 'load'. Fail-closed
-- loading must exist before anything depends on it."
--
-- Every refusal therefore names the field AND the requirement: `missing_field:api`,
-- `band_not_permitted_for_kind:ambient/SAFETY`, `config_default_out_of_range:blink_threshold`.
-- "Validation failed" would leave the author exactly where RXPGuides leaves them.
--
-- ================================================================================
-- THE CONFIG TYPE VOCABULARY IS AN INVENTION
-- ================================================================================
-- ADR §8.2's sample shows only `bool` and `int` and never states the full set. This module
-- defines it as:
--
--     bool · int · float · string · enum
--
-- Chosen because it is the smallest set that covers the sample plus the two things a rotation
-- obviously needs (a threshold that is not an integer, and a named mode), and because every one of
-- them is representable in a Sylvanas menu element and in the namespaced persist store without
-- encoding tricks. Recorded here as a decision, not a derivation -- if the ADR later names a
-- different set, this is the place it disagrees.

local Bands = require("kernel/bands")
local Semver = require("kernel/semver")

local Manifest = {}

-- ADR 08 §8.2's `kind` vocabulary.
Manifest.KINDS = { "rotation", "activity", "behavior", "strategy", "sensor", "ambient" }
local KIND_SET = {}
for _, k in ipairs(Manifest.KINDS) do KIND_SET[k] = true end

Manifest.CONFIG_TYPES = { "bool", "int", "float", "string", "enum" }
local CONFIG_TYPE_SET = {}
for _, t in ipairs(Manifest.CONFIG_TYPES) do CONFIG_TYPE_SET[t] = true end

-- §8.2's `applies_to`. Enumerated rather than open so a typo is a refusal instead of a predicate
-- that silently never matches -- the RXPGuides failure mode, one field down.
Manifest.APPLIES_TO_KEYS = {
    class = true, spec = true, min_level = true, max_level = true,
    race = true, faction = true,
}

local function is_list_of_strings(value)
    if type(value) ~= "table" then return false, "not_a_list" end
    for _, v in ipairs(value) do
        if type(v) ~= "string" then return false, "not_a_string_in_list" end
    end
    return true
end

local function validate_capability_lists(m)
    for _, field in ipairs({ "provides", "requires", "conflicts" }) do
        local value = m[field]
        if value ~= nil then
            local ok, why = is_list_of_strings(value)
            if not ok then
                return false, why .. ":" .. field
            end
        end
    end
    for _, c in ipairs(m.conflicts or {}) do
        if c == m.id then
            -- Almost certainly a confusion between capability names and plugin ids.
            return false, "self_conflict"
        end
    end
    return true
end

local function validate_applies_to(applies_to)
    if applies_to == nil then return true end
    if type(applies_to) ~= "table" then return false, "not_a_table:applies_to" end

    for key in pairs(applies_to) do
        if not Manifest.APPLIES_TO_KEYS[key] then
            return false, "unknown_applies_to_key:" .. tostring(key)
        end
    end
    for _, key in ipairs({ "min_level", "max_level" }) do
        if applies_to[key] ~= nil and type(applies_to[key]) ~= "number" then
            return false, "applies_to_" .. key .. "_not_a_number"
        end
    end
    if applies_to.min_level and applies_to.max_level
        and applies_to.min_level > applies_to.max_level then
        return false, "applies_to_level_range_inverted"
    end
    return true
end

local function type_matches(declared, value)
    if declared == "bool" then return type(value) == "boolean" end
    if declared == "int" then return type(value) == "number" and value == math.floor(value) end
    if declared == "float" then return type(value) == "number" end
    if declared == "string" then return type(value) == "string" end
    if declared == "enum" then return type(value) == "string" end
    return false
end

local function validate_config(config)
    if config == nil then return true end
    if type(config) ~= "table" then return false, "not_a_table:config" end

    local seen = {}
    for _, entry in ipairs(config) do
        if type(entry) ~= "table" then return false, "config_entry_not_a_table" end
        if type(entry.key) ~= "string" or entry.key == "" then
            return false, "config_entry_missing_key"
        end
        if seen[entry.key] then
            -- A duplicate key makes get/set ambiguous.
            return false, "duplicate_config_key:" .. entry.key
        end
        seen[entry.key] = true

        if not CONFIG_TYPE_SET[entry.type] then
            return false, "unknown_config_type:" .. entry.key .. "/" .. tostring(entry.type)
        end
        if entry.default == nil then
            -- Without a default, `get` before the first `set` returns nil for a value the plugin
            -- declared -- indistinguishable from a missing key.
            return false, "config_entry_missing_default:" .. entry.key
        end
        if entry.type == "enum" then
            local ok = is_list_of_strings(entry.values)
            if not ok or #entry.values == 0 then
                return false, "enum_requires_values:" .. entry.key
            end
        end
        if not type_matches(entry.type, entry.default) then
            return false, "config_default_type_mismatch:" .. entry.key
        end
        if entry.type == "enum" then
            local found = false
            for _, v in ipairs(entry.values) do
                if v == entry.default then found = true break end
            end
            if not found then
                return false, "config_default_not_in_enum:" .. entry.key
            end
        end
        -- A default that violates its own declared range is incoherent, and the violation would
        -- only surface the first time someone opened the settings UI.
        if entry.min ~= nil and type(entry.default) == "number" and entry.default < entry.min then
            return false, "config_default_out_of_range:" .. entry.key
        end
        if entry.max ~= nil and type(entry.default) == "number" and entry.default > entry.max then
            return false, "config_default_out_of_range:" .. entry.key
        end
    end
    return true
end

local function validate_priority(m)
    if m.priority == nil then
        -- Legal: `ambient` and `strategy` hold no band at all, and §5.3 says strategies choose
        -- rather than act. A plugin that never acquires needs no band.
        return true
    end
    if type(m.priority) ~= "table" then
        return false, "priority_band_must_be_named"
    end
    if type(m.priority.band) ~= "string" then
        return false, "priority_band_must_be_named"
    end
    if Bands.BANDS[m.priority.band] == nil then
        return false, "invalid_band:" .. m.priority.band
    end

    -- THE FIRST REAL CONSUMER of Bands.TIER_PERMISSIONS (ADR 08 §6.2: "the kernel rejects a
    -- manifest requesting a band its tier is not permitted -- an Ambient plugin cannot declare
    -- SAFETY").
    local permitted = Bands.permits(m.kind, m.priority.band)
    if not permitted then
        return false, "band_not_permitted_for_kind:" .. m.kind .. "/" .. m.priority.band
    end

    local resolved, reason = Bands.resolve({ band = m.priority.band, offset = m.priority.offset })
    if resolved == nil then
        if reason == "offset_out_of_band" then
            return false, "offset_out_of_band:" .. m.priority.band .. "/"
                .. tostring(m.priority.offset)
        end
        return false, reason
    end
    return true
end

---Validate a manifest against ADR 08 §8.2.
---@param m table the manifest
---@param opts table { api_version = "1.0.0" }
---@return boolean valid, string|nil reason -- always names the field and the requirement
function Manifest.validate(m, opts)
    opts = opts or {}
    if type(m) ~= "table" then return false, "not_a_table" end

    for _, field in ipairs({ "id", "kind", "version", "api" }) do
        if type(m[field]) ~= "string" or m[field] == "" then
            return false, "missing_field:" .. field
        end
    end

    if not KIND_SET[m.kind] then
        return false, "invalid_kind:" .. m.kind
    end

    if Semver.parse(m.version) == nil then
        return false, "invalid_version:" .. m.version
    end

    -- The version gate (§8.2: `api = "^1.0"` against Sentinel.API_VERSION).
    local api_version = opts.api_version
    if type(api_version) ~= "string" then
        -- Fail closed: with nothing to check against, the gate is not "open", it is broken.
        return false, "no_api_version_to_check_against"
    end
    local satisfied, why = Semver.satisfies(api_version, m.api)
    if not satisfied then
        if why == "unsupported_range" or why == "invalid_range" then
            return false, "api_range_unsupported:" .. m.api
        end
        return false, "api_incompatible:" .. m.api
    end

    local ok, reason = validate_priority(m)
    if not ok then return false, reason end

    ok, reason = validate_capability_lists(m)
    if not ok then return false, reason end

    ok, reason = validate_applies_to(m.applies_to)
    if not ok then return false, reason end

    ok, reason = validate_config(m.config)
    if not ok then return false, reason end

    for _, field in ipairs({ "preflight", "build", "tick" }) do
        if m[field] ~= nil and type(m[field]) ~= "function" then
            return false, "not_a_function:" .. field
        end
    end

    -- §8.2 offers `build` (declarative, preferred) or `tick` (imperative escape hatch). Neither
    -- means the plugin would load, occupy a band, and do nothing.
    if m.build == nil and m.tick == nil then
        return false, "no_entry_point"
    end

    return true
end

---The integer priority a validated manifest resolves to, or nil when it declares no band.
function Manifest.resolved_priority(m)
    if type(m) ~= "table" or type(m.priority) ~= "table" then return nil end
    return Bands.resolve({ band = m.priority.band, offset = m.priority.offset })
end

return Manifest
