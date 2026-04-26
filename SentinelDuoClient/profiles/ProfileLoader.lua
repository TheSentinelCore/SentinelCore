-- ProfileLoader.lua — Load and validate a profile by name.

local helpers = require("lib/helpers")

local REQUIRED_FIELDS = {
    "id", "instance_map_id", "entrance_position", "entrance_walk_path",
    "exit_position", "pulls", "vendor_route",
}

local ProfileLoader = {}
ProfileLoader.__index = ProfileLoader

---@param profile_name string
---@return table|nil, string|nil  profile, error_message
function ProfileLoader:load(profile_name)
    local ok, profile = pcall(require, "profiles/" .. profile_name)
    if not ok then
        local err = "failed to require profile '" .. profile_name .. "': " .. tostring(profile)
        helpers.log_err("[ProfileLoader] " .. err)
        return nil, err
    end

    if type(profile) ~= "table" then
        return nil, "profile '" .. profile_name .. "' did not return a table"
    end

    -- Validate required fields
    for _, field in ipairs(REQUIRED_FIELDS) do
        if profile[field] == nil then
            local err = "profile '" .. profile_name .. "' missing required field: " .. field
            helpers.log_err("[ProfileLoader] " .. err)
            return nil, err
        end
    end

    -- Validate pulls array
    if type(profile.pulls) ~= "table" or #profile.pulls == 0 then
        return nil, "profile '" .. profile_name .. "' has empty pulls array"
    end

    helpers.log("[ProfileLoader] loaded '" .. profile_name .. "' with " .. #profile.pulls .. " pulls")
    return profile, nil
end

return ProfileLoader
