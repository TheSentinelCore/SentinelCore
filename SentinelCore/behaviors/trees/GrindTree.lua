local BT = require("lib/BehaviorTree")

local NeedsRecovery = require("behaviors/conditions/NeedsRecovery")
local NeedsVendor = require("behaviors/conditions/NeedsVendor")
local HasActiveCombat = require("behaviors/conditions/HasActiveCombat")
local HasCanonicalContext = require("behaviors/conditions/HasCanonicalContext")

local RunRecovery = require("behaviors/actions/RunRecovery")
local RunVendor = require("behaviors/actions/RunVendor")
local RunLoot = require("behaviors/actions/RunLoot")
local RunCombat = require("behaviors/actions/RunCombat")
local Scout = require("behaviors/actions/Scout")

local GrindTree = {}

---@param services table
---@param command_handlers table
---@return table
function GrindTree.create(services, command_handlers)
    local root = BT.ReactiveSequence:new("GrindRoot")
    root:add(HasCanonicalContext(services.blackboard))

    local selector = BT.Selector:new("GrindSelector")

    local recovery_branch = BT.Sequence:new("RecoveryBranch")
    recovery_branch:add(NeedsRecovery(services.recovery))
    recovery_branch:add(RunRecovery(services.recovery, command_handlers))

    local vendor_branch = BT.Sequence:new("VendorBranch")
    vendor_branch:add(NeedsVendor(services.inventory, services.vendor))
    vendor_branch:add(RunVendor(services.vendor))

    local loot_branch = RunLoot(services.loot)

    local combat_active_branch = BT.Sequence:new("CombatActiveBranch")
    combat_active_branch:add(HasActiveCombat(services.combat))
    combat_active_branch:add(RunCombat(services.targeting, services.combat))

    selector:add(recovery_branch)
    selector:add(vendor_branch)
    selector:add(loot_branch)
    selector:add(combat_active_branch)
    selector:add(RunCombat(services.targeting, services.combat))
    selector:add(Scout())

    root:add(selector)

    return BT.Tree:new(root, "GrindTree")
end

return GrindTree
