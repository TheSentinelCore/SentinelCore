local JSON = require("lib/JSON")

local ZoneProfile = {}

local PROFILE_DIR = "sentinel/grinding_profiles"

---Parse a JSON string into a zone profile table.
---@param json_str string
---@return table|nil profile Parsed profile or nil if invalid
function ZoneProfile.parse(json_str)
    if type(json_str) ~= "string" or json_str == "" then
        return nil
    end

    local data, err = JSON.decode(json_str)
    if not data or err then
        return nil
    end

    -- Must be a table with spots array containing at least one spot
    if type(data) ~= "table" then
        return nil
    end
    if type(data.spots) ~= "table" or #data.spots == 0 then
        return nil
    end

    -- Validate each spot has required fields
    for i, spot in ipairs(data.spots) do
        if type(spot) ~= "table" then
            return nil
        end
        if type(spot.center) ~= "table" then
            return nil
        end
        if not spot.center.x or not spot.center.y or not spot.center.z then
            return nil
        end
        -- Default optional fields
        if spot.radius == nil then
            spot.radius = 80
        end
        if spot.level_min == nil then
            spot.level_min = 1
        end
        if spot.level_max == nil then
            spot.level_max = 70
        end
        if spot.aoe_enabled == nil then
            spot.aoe_enabled = false
        end
        if spot.mob_whitelist == nil then
            spot.mob_whitelist = {}
        end
        if spot.mob_blacklist == nil then
            spot.mob_blacklist = {}
        end
    end

    -- Default rest_spot and flee_spot to first spot's center
    local first_center = data.spots[1].center
    if type(data.rest_spot) ~= "table" or not data.rest_spot.x then
        data.rest_spot = { x = first_center.x, y = first_center.y, z = first_center.z }
    end
    if type(data.flee_spot) ~= "table" or not data.flee_spot.x then
        data.flee_spot = { x = first_center.x, y = first_center.y, z = first_center.z }
    end

    return data
end

---Select the best spot for a given player level.
---Returns the first spot whose level range contains the player level,
---or falls back to the first spot.
---@param profile table Parsed profile
---@param player_level number Current player level
---@return table spot The selected spot
function ZoneProfile.select_spot(profile, player_level)
    for _, spot in ipairs(profile.spots) do
        if player_level >= (spot.level_min or 1) and player_level <= (spot.level_max or 70) then
            return spot
        end
    end
    return profile.spots[1]
end

---List all available zone profiles from the data directory.
---Uses core.read_dir and core.read_data_file to discover and load profiles.
---@return table[] profiles Array of parsed profile tables
function ZoneProfile.list_profiles()
    local profiles = {}

    local files = core.read_dir(PROFILE_DIR)
    if not files then
        return profiles
    end

    for _, filename in ipairs(files) do
        if filename:match("%.json$") then
            local path = PROFILE_DIR .. "/" .. filename
            local content = core.read_data_file(path)
            if content then
                local profile = ZoneProfile.parse(content)
                if profile then
                    table.insert(profiles, profile)
                end
            end
        end
    end

    return profiles
end

return ZoneProfile
