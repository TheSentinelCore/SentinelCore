local ProfileValidator = {}

local VALID_SERVICES = { repair = true, sell = true, food = true, ammo = true }

---Check if a value is a non-empty string.
---@param v any
---@return boolean
local function is_non_empty_string(v)
    return type(v) == "string" and v ~= ""
end

---Validate an NpcRef table (npc_id + name).
---@param ref any
---@param context string Human-readable location for error messages
---@return string[] errors
local function validate_npc_ref(ref, context)
    local errors = {}
    if type(ref) ~= "table" then
        errors[#errors + 1] = context .. " must be a table"
        return errors
    end
    if type(ref.npc_id) ~= "number" then
        errors[#errors + 1] = context .. ".npc_id must be a number"
    end
    if not is_non_empty_string(ref.name) then
        errors[#errors + 1] = context .. ".name must be a non-empty string"
    end
    return errors
end

---Validate target filter fields (level_min, level_max, creature_types, npc_whitelist, npc_blacklist).
---@param filters any
---@param context string Human-readable location for error messages
---@return string[] errors
local function validate_target_filters(filters, context)
    local errors = {}
    if type(filters) ~= "table" then
        errors[#errors + 1] = context .. " must be a table"
        return errors
    end

    if filters.level_min ~= nil and type(filters.level_min) ~= "number" then
        errors[#errors + 1] = context .. ".level_min must be a number"
    end
    if filters.level_max ~= nil and type(filters.level_max) ~= "number" then
        errors[#errors + 1] = context .. ".level_max must be a number"
    end

    if filters.creature_types ~= nil then
        if type(filters.creature_types) ~= "table" then
            errors[#errors + 1] = context .. ".creature_types must be an array of numbers"
        else
            for i, v in ipairs(filters.creature_types) do
                if type(v) ~= "number" then
                    errors[#errors + 1] = context .. ".creature_types[" .. i .. "] must be a number"
                end
            end
        end
    end

    if filters.npc_whitelist ~= nil then
        if type(filters.npc_whitelist) ~= "table" then
            errors[#errors + 1] = context .. ".npc_whitelist must be an array"
        else
            for i, ref in ipairs(filters.npc_whitelist) do
                local ref_errors = validate_npc_ref(ref, context .. ".npc_whitelist[" .. i .. "]")
                for _, e in ipairs(ref_errors) do
                    errors[#errors + 1] = e
                end
            end
        end
    end

    if filters.npc_blacklist ~= nil then
        if type(filters.npc_blacklist) ~= "table" then
            errors[#errors + 1] = context .. ".npc_blacklist must be an array"
        else
            for i, ref in ipairs(filters.npc_blacklist) do
                local ref_errors = validate_npc_ref(ref, context .. ".npc_blacklist[" .. i .. "]")
                for _, e in ipairs(ref_errors) do
                    errors[#errors + 1] = e
                end
            end
        end
    end

    return errors
end

---Validate a single hotspot entry.
---@param hs any
---@param index number 1-based index in the hotspots array
---@param seen_ids table Set of already-seen hotspot IDs
---@return string[] errors
local function validate_hotspot(hs, index, seen_ids)
    local errors = {}
    local prefix = "hotspots[" .. index .. "]"

    if type(hs) ~= "table" then
        errors[#errors + 1] = prefix .. " must be a table"
        return errors
    end

    if not is_non_empty_string(hs.id) then
        errors[#errors + 1] = prefix .. ".id must be a non-empty string"
    else
        if seen_ids[hs.id] then
            errors[#errors + 1] = prefix .. ".id '" .. hs.id .. "' is a duplicate"
        end
        seen_ids[hs.id] = true
    end

    if type(hs.x) ~= "number" then
        errors[#errors + 1] = prefix .. ".x must be a number"
    end
    if type(hs.y) ~= "number" then
        errors[#errors + 1] = prefix .. ".y must be a number"
    end
    if type(hs.z) ~= "number" then
        errors[#errors + 1] = prefix .. ".z must be a number"
    end

    if hs.radius ~= nil and type(hs.radius) ~= "number" then
        errors[#errors + 1] = prefix .. ".radius must be a number"
    end

    if hs.target_overrides ~= nil then
        local override_errors = validate_target_filters(hs.target_overrides, prefix .. ".target_overrides")
        for _, e in ipairs(override_errors) do
            errors[#errors + 1] = e
        end
    end

    return errors
end

---Validate a single vendor entry.
---@param v any
---@param index number 1-based index in the vendors array
---@return string[] errors
local function validate_vendor(v, index)
    local errors = {}
    local prefix = "vendors[" .. index .. "]"

    if type(v) ~= "table" then
        errors[#errors + 1] = prefix .. " must be a table"
        return errors
    end

    if type(v.npc_id) ~= "number" then
        errors[#errors + 1] = prefix .. ".npc_id must be a number"
    end
    if not is_non_empty_string(v.name) then
        errors[#errors + 1] = prefix .. ".name must be a non-empty string"
    end
    if type(v.x) ~= "number" then
        errors[#errors + 1] = prefix .. ".x must be a number"
    end
    if type(v.y) ~= "number" then
        errors[#errors + 1] = prefix .. ".y must be a number"
    end
    if type(v.z) ~= "number" then
        errors[#errors + 1] = prefix .. ".z must be a number"
    end

    if type(v.services) ~= "table" or #v.services == 0 then
        errors[#errors + 1] = prefix .. ".services must be a non-empty array of strings"
    else
        for i, svc in ipairs(v.services) do
            if type(svc) ~= "string" then
                errors[#errors + 1] = prefix .. ".services[" .. i .. "] must be a string"
            elseif not VALID_SERVICES[svc] then
                errors[#errors + 1] = prefix .. ".services[" .. i .. "] '" .. tostring(svc) .. "' is not a valid service (repair, sell, food, ammo)"
            end
        end
    end

    return errors
end

---Validate a single blackspot entry.
---@param bs any
---@param index number 1-based index in the blackspots array
---@return string[] errors
local function validate_blackspot(bs, index)
    local errors = {}
    local prefix = "blackspots[" .. index .. "]"

    if type(bs) ~= "table" then
        errors[#errors + 1] = prefix .. " must be a table"
        return errors
    end

    if type(bs.x) ~= "number" then
        errors[#errors + 1] = prefix .. ".x must be a number"
    end
    if type(bs.y) ~= "number" then
        errors[#errors + 1] = prefix .. ".y must be a number"
    end
    if type(bs.z) ~= "number" then
        errors[#errors + 1] = prefix .. ".z must be a number"
    end
    if type(bs.radius) ~= "number" then
        errors[#errors + 1] = prefix .. ".radius must be a number"
    elseif bs.radius <= 0 then
        errors[#errors + 1] = prefix .. ".radius must be greater than 0"
    end

    return errors
end

---Validate a decoded v2.0 grinding profile table.
---Collects all errors instead of stopping at the first.
---@param data any Decoded JSON profile
---@return boolean valid True if valid
---@return string[] errors Array of error messages (empty if valid)
function ProfileValidator.validate(data)
    local errors = {}

    -- Root must be a table
    if type(data) ~= "table" then
        return false, { "profile must be a table" }
    end

    -- schema_version
    if data.schema_version ~= "2.0" then
        errors[#errors + 1] = "schema_version must be \"2.0\""
    end

    -- metadata
    if type(data.metadata) ~= "table" then
        errors[#errors + 1] = "metadata must be a table"
    elseif not is_non_empty_string(data.metadata.name) then
        errors[#errors + 1] = "metadata.name must be a non-empty string"
    end

    -- requirements
    if type(data.requirements) ~= "table" then
        errors[#errors + 1] = "requirements must be a table"
    else
        if type(data.requirements.map_id) ~= "number" then
            errors[#errors + 1] = "requirements.map_id must be a number"
        end
        if data.requirements.min_level ~= nil and type(data.requirements.min_level) ~= "number" then
            errors[#errors + 1] = "requirements.min_level must be a number"
        end
        if data.requirements.max_level ~= nil and type(data.requirements.max_level) ~= "number" then
            errors[#errors + 1] = "requirements.max_level must be a number"
        end
    end

    -- hotspots
    if type(data.hotspots) ~= "table" or #data.hotspots == 0 then
        errors[#errors + 1] = "hotspots must be a non-empty array"
    else
        local seen_ids = {}
        for i, hs in ipairs(data.hotspots) do
            local hs_errors = validate_hotspot(hs, i, seen_ids)
            for _, e in ipairs(hs_errors) do
                errors[#errors + 1] = e
            end
        end
    end

    -- target_defaults (optional)
    if data.target_defaults ~= nil then
        local td_errors = validate_target_filters(data.target_defaults, "target_defaults")
        for _, e in ipairs(td_errors) do
            errors[#errors + 1] = e
        end
    end

    -- vendors (optional)
    if data.vendors ~= nil then
        if type(data.vendors) ~= "table" then
            errors[#errors + 1] = "vendors must be an array"
        else
            for i, v in ipairs(data.vendors) do
                local v_errors = validate_vendor(v, i)
                for _, e in ipairs(v_errors) do
                    errors[#errors + 1] = e
                end
            end
        end
    end

    -- blackspots (optional)
    if data.blackspots ~= nil then
        if type(data.blackspots) ~= "table" then
            errors[#errors + 1] = "blackspots must be an array"
        else
            for i, bs in ipairs(data.blackspots) do
                local bs_errors = validate_blackspot(bs, i)
                for _, e in ipairs(bs_errors) do
                    errors[#errors + 1] = e
                end
            end
        end
    end

    -- options (optional)
    if data.options ~= nil then
        if type(data.options) ~= "table" then
            errors[#errors + 1] = "options must be a table"
        else
            if data.options.loop ~= nil and type(data.options.loop) ~= "boolean" then
                errors[#errors + 1] = "options.loop must be a boolean"
            end
            if data.options.dry_spell_secs ~= nil then
                if type(data.options.dry_spell_secs) ~= "number" then
                    errors[#errors + 1] = "options.dry_spell_secs must be a number"
                elseif data.options.dry_spell_secs < 5 then
                    errors[#errors + 1] = "options.dry_spell_secs must be >= 5"
                end
            end
            if data.options.travel_engage ~= nil and type(data.options.travel_engage) ~= "boolean" then
                errors[#errors + 1] = "options.travel_engage must be a boolean"
            end
        end
    end

    if #errors == 0 then
        return true, {}
    end
    return false, errors
end

return ProfileValidator
