-- tests/kernel/test_manifest.lua
-- ADR 08 §8.2 -- the manifest, and the validator that refuses a bad one BY NAME.
--
-- ADR §12 puts the validator in Phase 3 explicitly and says why: "RXPGuides ships without one --
-- an unresolved `#completewith foo` silently never fires. LazyBot is worse: GrindingProfile
-- .LoadFile is eight independent `try { } catch { }` blocks with EMPTY CATCH BODIES, each falling
-- back to a hardcoded default, so a profile can be 90% broken and still 'load'. Fail-closed
-- loading must exist before anything depends on it."
--
-- So every refusal here names the FIELD and the REQUIREMENT. "Validation failed" is useless.

local Manifest = require("kernel/manifest")
local T = require("tests/test_util")

local M = {}

--- The minimum viable manifest, used as a base so each test perturbs exactly one thing.
local function base(overrides)
    local m = {
        id = "sentinel.rotation.dummy",
        kind = "rotation",
        version = "1.0.0",
        api = "^1.0",
        priority = { band = "COMBAT", offset = 0 },
        tick = function() return "DONE" end,
    }
    for k, v in pairs(overrides or {}) do m[k] = v end
    return m
end

local function invalid(overrides)
    return Manifest.validate(base(overrides), { api_version = "1.0.0" })
end

-- ---------------------------------------------------------------------------
-- Happy path
-- ---------------------------------------------------------------------------

function M.test_a_minimal_valid_manifest_passes()
    local ok, err = Manifest.validate(base(), { api_version = "1.0.0" })
    T.assert_true(ok, "the base manifest must validate: " .. tostring(err))
end

function M.test_a_fully_populated_manifest_passes()
    local ok, err = Manifest.validate(base({
        applies_to = { class = "Mage", spec = "Frost", min_level = 10, max_level = 70 },
        provides = { "combat_routine" },
        requires = { "nav" },
        conflicts = { "sentinel.rotation.mage_generic" },
        config = {
            { key = "use_water_elemental", type = "bool", default = true },
            { key = "blink_threshold", type = "int", default = 35, min = 0, max = 100 },
        },
        preflight = function() return true end,
        build = function() return {} end,
    }), { api_version = "1.0.0" })
    T.assert_true(ok, tostring(err))
end

-- ---------------------------------------------------------------------------
-- Required fields -- each refused by NAME
-- ---------------------------------------------------------------------------

function M.test_missing_required_fields_are_refused_naming_the_field()
    local cases = {
        { "id", "missing_field:id" },
        { "kind", "missing_field:kind" },
        { "version", "missing_field:version" },
        { "api", "missing_field:api" },
    }
    for _, case in ipairs(cases) do
        local m = base()
        m[case[1]] = nil
        local ok, reason = Manifest.validate(m, { api_version = "1.0.0" })
        T.assert_false(ok, case[1] .. " must be required")
        T.assert_equal(reason, case[2])
    end
end

function M.test_an_unknown_kind_is_refused_naming_the_valid_set()
    local ok, reason = invalid({ kind = "wizard" })
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_kind:wizard")
end

function M.test_the_six_documented_kinds_are_accepted()
    -- §8.2: rotation | activity | behavior | strategy | sensor | ambient
    for _, kind in ipairs({ "rotation", "activity", "behavior", "strategy", "sensor", "ambient" }) do
        local m = base({ kind = kind })
        -- ambient and strategy hold no band at all, so drop priority for those.
        if kind == "ambient" or kind == "strategy" then m.priority = nil end
        if kind == "activity" then m.priority = { band = "GOAL", offset = 0 } end
        if kind == "behavior" then m.priority = { band = "HOUSEKEEP", offset = 0 } end
        if kind == "sensor" then m.priority = { band = "IDLE", offset = 0 } end
        local ok, reason = Manifest.validate(m, { api_version = "1.0.0" })
        T.assert_true(ok, kind .. " must be a valid kind: " .. tostring(reason))
    end
end

function M.test_a_non_table_manifest_is_refused()
    local ok, reason = Manifest.validate("not a manifest", { api_version = "1.0.0" })
    T.assert_false(ok)
    T.assert_equal(reason, "not_a_table")
end

function M.test_an_empty_id_is_refused()
    local ok, reason = invalid({ id = "" })
    T.assert_false(ok)
    T.assert_equal(reason, "missing_field:id")
end

-- ---------------------------------------------------------------------------
-- The version gate
-- ---------------------------------------------------------------------------

function M.test_an_incompatible_api_range_is_refused_by_name()
    local ok, reason = Manifest.validate(base({ api = "^2.0" }), { api_version = "1.0.0" })
    T.assert_false(ok, "^2.0 must not load against API 1.0.0")
    T.assert_equal(reason, "api_incompatible:^2.0")
end

function M.test_a_compatible_api_range_passes()
    T.assert_true(Manifest.validate(base({ api = "^1.0" }), { api_version = "1.5.0" }))
    T.assert_true(Manifest.validate(base({ api = "^1.5" }), { api_version = "1.10.0" }),
        "1.10 satisfies ^1.5 -- the lexical trap must not bite here either")
end

function M.test_an_api_range_above_the_kernel_is_refused()
    local ok, reason = Manifest.validate(base({ api = "^1.5" }), { api_version = "1.2.0" })
    T.assert_false(ok, "a plugin needing 1.5 must not load on a 1.2 kernel")
    T.assert_equal(reason, "api_incompatible:^1.5")
end

function M.test_an_unsupported_api_range_syntax_is_refused_by_name()
    local ok, reason = Manifest.validate(base({ api = "~1.0" }), { api_version = "1.0.0" })
    T.assert_false(ok)
    T.assert_equal(reason, "api_range_unsupported:~1.0")
end

function M.test_the_plugins_own_version_must_be_parseable()
    local ok, reason = invalid({ version = "one point oh" })
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_version:one point oh")
end

-- ---------------------------------------------------------------------------
-- Priority / bands -- the first real consumer of TIER_PERMISSIONS
-- ---------------------------------------------------------------------------

function M.test_a_bare_integer_priority_is_refused()
    local ok, reason = invalid({ priority = 55 })
    T.assert_false(ok, "ADR 08 §6.2 -- bands are named")
    T.assert_equal(reason, "priority_band_must_be_named")
end

function M.test_an_unknown_band_is_refused_by_name()
    local ok, reason = invalid({ priority = { band = "URGENT", offset = 0 } })
    T.assert_false(ok)
    T.assert_equal(reason, "invalid_band:URGENT")
end

--- The exit criterion: "an ambient manifest declaring any control band is refused."
function M.test_an_ambient_manifest_declaring_any_band_is_refused()
    local Bands = require("kernel/bands")
    for _, band in ipairs(Bands.ORDER) do
        local ok, reason = Manifest.validate(
            base({ kind = "ambient", priority = { band = band, offset = 0 } }),
            { api_version = "1.0.0" })
        T.assert_false(ok, "ambient must not be able to declare " .. band)
        T.assert_equal(reason, "band_not_permitted_for_kind:ambient/" .. band)
    end
end

function M.test_an_ambient_manifest_with_no_priority_is_accepted()
    -- Built by hand: `pairs` skips nil values, so `base({ priority = nil })` cannot express
    -- "remove this field".
    local m = base({ kind = "ambient" })
    m.priority = nil
    local ok, err = Manifest.validate(m, { api_version = "1.0.0" })
    T.assert_true(ok, "an ambient plugin declaring no band at all is exactly what it should do: "
        .. tostring(err))
end

function M.test_a_rotation_cannot_declare_the_goal_band()
    local ok, reason = invalid({ priority = { band = "GOAL", offset = 0 } })
    T.assert_false(ok, "a rotation is not the goal")
    T.assert_equal(reason, "band_not_permitted_for_kind:rotation/GOAL")
end

function M.test_an_offset_overflowing_its_band_is_refused()
    local ok, reason = invalid({ priority = { band = "COMBAT", offset = 50 } })
    T.assert_false(ok)
    T.assert_equal(reason, "offset_out_of_band:COMBAT/50")
end

--- A rotation that omits priority gets its band's floor rather than an implicit zero, so the
--- resolved value can never be silently outside the declared band.
function M.test_a_missing_offset_defaults_to_the_band_floor()
    local ok = Manifest.validate(base({ priority = { band = "COMBAT" } }), { api_version = "1.0.0" })
    T.assert_true(ok)
    local resolved = Manifest.resolved_priority(base({ priority = { band = "COMBAT" } }))
    T.assert_equal(resolved, 50)
end

-- ---------------------------------------------------------------------------
-- Entry points (ADR 08 §8.3)
-- ---------------------------------------------------------------------------

--- §8.2 offers `build` (declarative, preferred) or `tick` (imperative escape hatch). A manifest
--- with neither is inert -- it would load, occupy a band, and do nothing.
function M.test_a_manifest_with_neither_build_nor_tick_is_refused()
    local m = base()
    m.tick = nil
    local ok, reason = Manifest.validate(m, { api_version = "1.0.0" })
    T.assert_false(ok)
    T.assert_equal(reason, "no_entry_point")
end

function M.test_build_alone_is_sufficient()
    local m = base({ build = function() return {} end })
    m.tick = nil
    T.assert_true(Manifest.validate(m, { api_version = "1.0.0" }))
end

function M.test_entry_points_must_be_functions()
    for _, field in ipairs({ "tick", "build", "preflight" }) do
        local ok, reason = invalid({ [field] = "not a function" })
        T.assert_false(ok, field .. " must be a function")
        T.assert_equal(reason, "not_a_function:" .. field)
    end
end

-- ---------------------------------------------------------------------------
-- applies_to
-- ---------------------------------------------------------------------------

function M.test_applies_to_rejects_unknown_keys()
    local ok, reason = invalid({ applies_to = { clazz = "Mage" } })
    T.assert_false(ok, "a typo in applies_to would silently never match")
    T.assert_equal(reason, "unknown_applies_to_key:clazz")
end

function M.test_applies_to_level_bounds_must_be_ordered()
    local ok, reason = invalid({ applies_to = { min_level = 60, max_level = 10 } })
    T.assert_false(ok)
    T.assert_equal(reason, "applies_to_level_range_inverted")
end

function M.test_applies_to_levels_must_be_numbers()
    local ok, reason = invalid({ applies_to = { min_level = "ten" } })
    T.assert_false(ok)
    T.assert_equal(reason, "applies_to_min_level_not_a_number")
end

-- ---------------------------------------------------------------------------
-- Capability lists
-- ---------------------------------------------------------------------------

function M.test_capability_lists_must_be_arrays_of_strings()
    for _, field in ipairs({ "provides", "requires", "conflicts" }) do
        local ok, reason = invalid({ [field] = "nav" })
        T.assert_false(ok, field .. " must be a list, not a bare string")
        T.assert_equal(reason, "not_a_list:" .. field)

        local ok2, reason2 = invalid({ [field] = { 42 } })
        T.assert_false(ok2)
        T.assert_equal(reason2, "not_a_string_in_list:" .. field)
    end
end

--- Requiring what you provide is legal (see the capability resolver), but requiring your own ID
--- is a confusion between capability names and plugin ids and is worth catching early.
function M.test_conflicting_with_yourself_is_refused()
    local ok, reason = invalid({ conflicts = { "sentinel.rotation.dummy" } })
    T.assert_false(ok)
    T.assert_equal(reason, "self_conflict")
end

-- ---------------------------------------------------------------------------
-- Config schema
-- ---------------------------------------------------------------------------

function M.test_each_supported_config_type_validates()
    for _, entry in ipairs({
        { key = "a", type = "bool", default = true },
        { key = "b", type = "int", default = 1 },
        { key = "c", type = "float", default = 1.5 },
        { key = "d", type = "string", default = "x" },
        { key = "e", type = "enum", default = "one", values = { "one", "two" } },
    }) do
        local ok, reason = invalid({ config = { entry } })
        T.assert_true(ok, entry.type .. " must be a supported config type: " .. tostring(reason))
    end
end

function M.test_an_unknown_config_type_is_refused_by_name()
    local ok, reason = invalid({ config = { { key = "a", type = "colour", default = "red" } } })
    T.assert_false(ok)
    T.assert_equal(reason, "unknown_config_type:a/colour")
end

function M.test_a_config_default_must_match_its_declared_type()
    local ok, reason = invalid({ config = { { key = "a", type = "int", default = "five" } } })
    T.assert_false(ok)
    T.assert_equal(reason, "config_default_type_mismatch:a")
end

function M.test_an_int_config_rejects_a_fractional_default()
    local ok, reason = invalid({ config = { { key = "a", type = "int", default = 1.5 } } })
    T.assert_false(ok)
    T.assert_equal(reason, "config_default_type_mismatch:a")
end

function M.test_a_config_default_outside_its_own_bounds_is_refused()
    local ok, reason = invalid({
        config = { { key = "a", type = "int", default = 200, min = 0, max = 100 } },
    })
    T.assert_false(ok, "a default that violates its own declared range is incoherent")
    T.assert_equal(reason, "config_default_out_of_range:a")
end

function M.test_an_enum_must_declare_its_values()
    local ok, reason = invalid({ config = { { key = "a", type = "enum", default = "one" } } })
    T.assert_false(ok)
    T.assert_equal(reason, "enum_requires_values:a")
end

function M.test_an_enum_default_must_be_one_of_its_values()
    local ok, reason = invalid({
        config = { { key = "a", type = "enum", default = "three", values = { "one", "two" } } },
    })
    T.assert_false(ok)
    T.assert_equal(reason, "config_default_not_in_enum:a")
end

function M.test_a_config_entry_needs_a_key()
    local ok, reason = invalid({ config = { { type = "bool", default = true } } })
    T.assert_false(ok)
    T.assert_equal(reason, "config_entry_missing_key")
end

function M.test_duplicate_config_keys_are_refused()
    local ok, reason = invalid({ config = {
        { key = "a", type = "bool", default = true },
        { key = "a", type = "int", default = 1 },
    } })
    T.assert_false(ok, "a duplicate key makes get/set ambiguous")
    T.assert_equal(reason, "duplicate_config_key:a")
end

--- Every config entry needs a default, or `get` before the first `set` has nothing to return and
--- the plugin sees nil for a value it declared.
function M.test_a_config_entry_needs_a_default()
    local ok, reason = invalid({ config = { { key = "a", type = "bool" } } })
    T.assert_false(ok)
    T.assert_equal(reason, "config_entry_missing_default:a")
end

return M
