local PaladinRetTBC = require("modules/combat/profiles/paladin/retribution_tbc")

local Registry = {}

function Registry.resolve(_class_id, _spec_id)
    return PaladinRetTBC
end

return Registry
