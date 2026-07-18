local ProfileInterface = {}

-- Required methods (must be implemented by all profiles)
ProfileInterface.REQUIRED_METHODS = {
    "tick_maintenance",
    "tick_off_gcd",
    "tick_gcd",
    "reset",
}

-- Optional methods (profiles may implement for additional functionality)
ProfileInterface.OPTIONAL_METHODS = {
    "get_pull_strategy",
    "tick_pull",
    "prepare_rest",
}

-- Check if a profile implements the required interface
function ProfileInterface.validate(profile)
    if not profile then
        return false, "Profile is nil"
    end
    for _, method in ipairs(ProfileInterface.REQUIRED_METHODS) do
        if type(profile[method]) ~= "function" then
            return false, "Missing required method: " .. method
        end
    end
    return true
end

-- Safe call a required method
function ProfileInterface.call_required(profile, method, ...)
    if not profile or type(profile[method]) ~= "function" then
        error("Profile does not implement required method: " .. method)
    end
    return profile[method](profile, ...)
end

-- Safe call an optional method, returns nil if not implemented
function ProfileInterface.call_optional(profile, method, ...)
    if profile and type(profile[method]) == "function" then
        return profile[method](profile, ...)
    end
    return nil
end

-- Create a profile wrapper that validates on construction
function ProfileInterface.wrap(profile)
    local ok, err = ProfileInterface.validate(profile)
    if not ok then
        error("Invalid profile: " .. err)
    end
    return setmetatable({}, {
        __index = function(t, k)
            if ProfileInterface.call_optional(profile, k) then
                return function(...) return ProfileInterface.call_optional(profile, k, ...) end
            end
            return profile[k]
        end
    })
end

return ProfileInterface