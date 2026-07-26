-- rotations/warlock_affliction/maintenance_tree.lua
--
-- MVP scope: no self-buff maintenance yet. Demon Skin/Demon Armor were called out as optional in the
-- design and are explicitly DEFERRED (see design Open Questions) -- adding them means baking their
-- rank arrays into spell_catalog and a real ensure_* sequence here, same shape as Paladin's
-- ensure_blessing_of_might/kings. Kept as an explicit no-op selector (rather than omitting the file)
-- so Profile.build's lifecycle wiring (Runner:new/tick/reset) matches the Mage/Paladin convention
-- exactly.
--
-- The only thing the port changed: `BT` is the KERNEL's tree library, reached through
-- `Sentinel.bt`, rather than `require("core/bt/factory")`. Late-bound through `__index` so a tree
-- built before the kernel published still resolves once it has.

local API = require("rotations/warlock_affliction/sentinel_api")

local BT = setmetatable({}, { __index = function(_, k) return API.bt and API.bt[k] or nil end })

local MaintenanceTree = {}

function MaintenanceTree.build()
    return BT.selector("warlock_affliction_maintenance", {
        BT.sequence("noop", {
            BT.condition("always_false", function() return false end),
        }),
    })
end

return MaintenanceTree
