local PaladinRetTBC = require("modules/combat/profiles/paladin/retribution_tbc")
local MageFrostTBC = require("modules/combat/profiles/mage/frost_tbc")

local Registry = {}

function Registry.resolve(class_id, _spec_id)
    if class_id == 8 then
        return MageFrostTBC
    end
    return PaladinRetTBC
end

return Registry
