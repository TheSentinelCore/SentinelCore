local BT = require("core/bt/factory")
local Safety = require("modules/grind/phases/safety")
local CorpseRun = require("modules/grind/phases/corpse_run")
local Rest = require("modules/grind/phases/rest")
local Loot = require("modules/grind/phases/loot")
local Combat = require("modules/grind/phases/combat")
local Pull = require("modules/grind/phases/pull")
local Acquire = require("modules/grind/phases/acquire")

local GrindTree = {}

--- Build the master grind behavior tree.
--- Priority order (highest first):
---   safety > corpse_run > rest > loot > combat > pull > acquire
---@param blackboard table Blackboard instance
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT root node (cooldown-wrapped selector)
function GrindTree.build(blackboard, event_bus, nav_adapter)
    return BT.cooldown("grind_root_cooldown", 100,
        BT.selector("grind_root", {
            Safety.build(event_bus, nav_adapter),
            CorpseRun.build(event_bus, nav_adapter),
            Rest.build(event_bus),
            Loot.build(event_bus, nav_adapter),
            Combat.build(),
            Pull.build(blackboard, event_bus, nav_adapter),
            Acquire.build(blackboard, nav_adapter),
        }),
        { key = "module.grind.root_cooldown" }
    )
end

return GrindTree
