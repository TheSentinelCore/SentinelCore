local PaladinRetTBC = require("modules/combat/profiles/paladin/retribution_tbc")
local MageFrostTBC = require("modules/combat/profiles/mage/frost_tbc")

local Registry = {}

local PROFILE_REGISTRY = {
    [8] = MageFrostTBC,  -- Mage
    [2] = PaladinRetTBC, -- Paladin
}

function Registry.resolve(class_id, _spec_id)
    local profile_module = PROFILE_REGISTRY[class_id]
    if not profile_module then
        -- Fallback to paladin for unknown classes
        profile_module = PaladinRetTBC
    end
    return profile_module
end

-- Validate that profile modules have the required interface (without building)
-- This checks the module structure, not the actual instance
for class_id, profile_module in pairs(PROFILE_REGISTRY) do
    -- Check that the module has a build function
    if type(profile_module.build) ~= "function" then
        error("[ProfileRegistry] Profile for class_id=" .. class_id .. " missing 'build' function")
    end

    -- Check that the module is a table (class)
    if type(profile_module) ~= "table" then
        error("[ProfileRegistry] Profile for class_id=" .. class_id .. " is not a module table")
    end
end

return Registry