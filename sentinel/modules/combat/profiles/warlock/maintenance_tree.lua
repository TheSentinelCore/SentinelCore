local BT = require("core/bt/factory")

local MaintenanceTree = {}

-- MVP scope: no self-buff maintenance yet. Demon Skin/Demon Armor were called
-- out as optional in the design and are explicitly DEFERRED (see design Open
-- Questions) -- adding them means baking their rank arrays into spell_catalog
-- and a real ensure_* sequence here, same shape as Paladin's
-- ensure_blessing_of_might/kings. Kept as an explicit no-op selector (rather
-- than omitting the file) so Profile.build's lifecycle wiring
-- (Runner:new/tick/reset) matches the Mage/Paladin convention exactly.
function MaintenanceTree.build()
    return BT.selector("warlock_affliction_maintenance", {
        BT.sequence("noop", {
            BT.condition("always_false", function() return false end),
        }),
    })
end

return MaintenanceTree
