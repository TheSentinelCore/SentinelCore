local BT = require("ai/BehaviorTree")
local DeathRecoverySubTree = require("bt/DeathRecoverySubTree")
local CombatInterruptSubTree = require("bt/CombatInterruptSubTree")
local CombatSubTree = require("bt/CombatSubTree")
local FleeSubTree = require("bt/FleeSubTree")
local LootSubTree = require("bt/LootSubTree")
local RestSubTree = require("bt/RestSubTree")
local VendorSubTree = require("bt/VendorSubTree")
local MaintenanceSubTree = require("bt/MaintenanceSubTree")
local PullSubTree = require("bt/PullSubTree")
local FindTargetSubTree = require("bt/FindTargetSubTree")
local ExploreSubTree = require("bt/ExploreSubTree")

local GrindTree = {}

---@param deps table { bb, evaluator, swing_timer, human_timing, spell_executor, navigation, targeting, vendor_service, exploration_service }
---@return table BT Selector node
function GrindTree.build(deps)
    return BT.Selector:new("grind_root", {
        DeathRecoverySubTree.build(deps.bb, deps.navigation),
        CombatInterruptSubTree.build(deps.bb),
        CombatSubTree.build(deps.bb, deps.evaluator, deps.swing_timer, deps.human_timing, deps.spell_executor),
        FleeSubTree.build(deps.bb, deps.navigation),
        LootSubTree.build(deps.bb, deps.navigation),
        RestSubTree.build(deps.bb),
        VendorSubTree.build(deps.bb, deps.vendor_service),
        MaintenanceSubTree.build(deps.bb),
        PullSubTree.build(deps.bb, deps.navigation),
        FindTargetSubTree.build(deps.bb, deps.targeting),
        ExploreSubTree.build(deps.bb, deps.navigation, deps.exploration_service),
    })
end

return GrindTree
