-- SentinelCore/profiles/ProfileValidator.lua
local Validator = {}

function Validator.validate(profile)
    local errors = {}

    if type(profile) ~= "table" then
        return false, { "profile is not a table" }
    end

    if not profile.version or type(profile.version) ~= "string" or profile.version == "" then
        errors[#errors + 1] = "missing or empty 'version'"
    end

    local meta = profile.metadata
    if type(meta) ~= "table" then
        errors[#errors + 1] = "missing 'metadata' table"
    elseif not meta.name or type(meta.name) ~= "string" or meta.name == "" then
        errors[#errors + 1] = "missing or empty 'metadata.name'"
    end

    local req = profile.requirements
    if type(req) ~= "table" then
        errors[#errors + 1] = "missing 'requirements' table"
    elseif not req.map_id or type(req.map_id) ~= "number" or req.map_id <= 0 then
        errors[#errors + 1] = "missing or invalid 'requirements.map_id'"
    end

    local hotspots = profile.hotspots
    if type(hotspots) ~= "table" or #hotspots == 0 then
        errors[#errors + 1] = "at least one hotspot is required"
    else
        local seen_ids = {}
        for i = 1, #hotspots do
            local hs = hotspots[i]
            if type(hs) ~= "table" then
                errors[#errors + 1] = string.format("hotspot[%d] is not a table", i)
            else
                if type(hs.x) ~= "number" or type(hs.y) ~= "number" or type(hs.z) ~= "number" then
                    errors[#errors + 1] = string.format("hotspot[%d] missing x/y/z coordinates", i)
                end
                if hs.radius ~= nil and (type(hs.radius) ~= "number" or hs.radius <= 0) then
                    errors[#errors + 1] = string.format("hotspot[%d] invalid radius", i)
                end
                local id = hs.id or tostring(i)
                if seen_ids[id] then
                    errors[#errors + 1] = string.format("duplicate hotspot id '%s'", tostring(id))
                end
                seen_ids[id] = true
            end
        end
    end

    if profile.vendors and type(profile.vendors) == "table" then
        for i = 1, #profile.vendors do
            local v = profile.vendors[i]
            if type(v) == "table" then
                if type(v.npc_id) ~= "number" or v.npc_id <= 0 then
                    errors[#errors + 1] = string.format("vendor[%d] missing or invalid npc_id", i)
                end
                if type(v.x) ~= "number" or type(v.y) ~= "number" or type(v.z) ~= "number" then
                    errors[#errors + 1] = string.format("vendor[%d] missing x/y/z coordinates", i)
                end
            end
        end
    end

    if profile.blackspots and type(profile.blackspots) == "table" then
        for i = 1, #profile.blackspots do
            local bs = profile.blackspots[i]
            if type(bs) == "table" then
                if type(bs.x) ~= "number" or type(bs.y) ~= "number" or type(bs.z) ~= "number" then
                    errors[#errors + 1] = string.format("blackspot[%d] missing x/y/z coordinates", i)
                end
                if bs.severity and bs.severity ~= "hard" and bs.severity ~= "soft" then
                    errors[#errors + 1] = string.format("blackspot[%d] invalid severity (must be 'hard' or 'soft')", i)
                end
            end
        end
    end

    return #errors == 0, errors
end

return Validator
