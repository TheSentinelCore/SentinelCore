local BT = require("lib/BehaviorTree")

local NeedsRecovery = require("behaviors/conditions/NeedsRecovery")
local NeedsVendor = require("behaviors/conditions/NeedsVendor")
local HasActiveCombat = require("behaviors/conditions/HasActiveCombat")
local HasObjectiveWork = require("behaviors/conditions/HasObjectiveWork")
local HasCanonicalContext = require("behaviors/conditions/HasCanonicalContext")

local RunRecovery = require("behaviors/actions/RunRecovery")
local RunVendor = require("behaviors/actions/RunVendor")
local RunLoot = require("behaviors/actions/RunLoot")
local RunObjective = require("behaviors/actions/RunObjective")
local RunCombat = require("behaviors/actions/RunCombat")
local Scout = require("behaviors/actions/Scout")

local CombatKernelTree = {}

---@param services table
---@param command_handlers table
---@return table
function CombatKernelTree.create(services, command_handlers)
    local root = BT.ReactiveSequence:new("CombatKernelRoot")
    root:add(HasCanonicalContext(services.blackboard))

    local selector = BT.Selector:new("CombatKernelSelector")

    local recovery_branch = BT.Sequence:new("RecoveryBranch")
    recovery_branch:add(NeedsRecovery(services.recovery))
    recovery_branch:add(RunRecovery(services.recovery, command_handlers))

    local vendor_branch = BT.Sequence:new("VendorBranch")
    vendor_branch:add(NeedsVendor(services.inventory, services.vendor))
    vendor_branch:add(RunVendor(services.vendor))

    local loot_branch = RunLoot(services.loot)

    local objective_branch = BT.Sequence:new("ObjectiveBranch")
    objective_branch:add(HasObjectiveWork(services.objective))
    objective_branch:add(RunObjective(services.objective))

    local combat_active_branch = BT.Sequence:new("CombatActiveBranch")
    combat_active_branch:add(HasActiveCombat(services.combat))
    combat_active_branch:add(RunCombat(services.targeting, services.combat))

    selector:add(recovery_branch)
    selector:add(vendor_branch)
    selector:add(loot_branch)
    selector:add(combat_active_branch)
    selector:add(objective_branch)
    selector:add(RunCombat(services.targeting, services.combat))
    selector:add(Scout())

    root:add(selector)

    return BT.Tree:new(root, "CombatKernelTree")
end

return CombatKernelTree
