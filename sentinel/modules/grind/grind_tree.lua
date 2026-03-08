local BT = require("core/bt/factory")
local Safety = require("modules/grind/phases/safety")
local CorpseRun = require("modules/grind/phases/corpse_run")
local Rest = require("modules/grind/phases/rest")
local Loot = require("modules/grind/phases/loot")
local Vendor = require("modules/grind/phases/vendor")
local Combat = require("modules/grind/phases/combat")
local Pull = require("modules/grind/phases/pull")
local Acquire = require("modules/grind/phases/acquire")
local Patrol = require("modules/grind/patrol")

local GrindTree = {}

--- Build the master grind behavior tree.
--- Priority order (highest first):
---   safety > corpse_run > loot > rest > vendor > combat > pull > acquire
--- Acquire phase switches between profile-based and patrol-based
--- depending on module.grind.mode ("profile" or "patrol").
---@param blackboard table Blackboard instance
---@param event_bus table EventBus instance
---@param nav_adapter table NavAdapter instance
---@return table BT root node (cooldown-wrapped selector)
function GrindTree.build(blackboard, event_bus, nav_adapter)
    local profile_acquire = Acquire.build(blackboard, event_bus, nav_adapter)
    local patrol_acquire = Patrol.build_acquire(event_bus, nav_adapter)

    -- Mode-switching acquire: delegates to profile or patrol based on bb mode.
    -- Safe because both delegates are leaf action nodes (no composite _running_index).
    local mode_acquire = BT.action("mode_acquire", function(bb)
        local mode = bb:get("module.grind.mode", "profile")
        if mode == "patrol" then
            return patrol_acquire:tick(bb)
        else
            return profile_acquire:tick(bb)
        end
    end)

    return BT.cooldown("grind_root_cooldown", 100,
        BT.priority_selector("grind_root", {
            Safety.build(event_bus, nav_adapter),
            CorpseRun.build(event_bus, nav_adapter),
            Loot.build(event_bus, nav_adapter),
            Rest.build(event_bus, nav_adapter),
            Vendor.build(blackboard, event_bus, nav_adapter),
            Combat.build(),
            Pull.build(blackboard, event_bus, nav_adapter),
            mode_acquire,
        }),
        { key = "module.grind.root_cooldown" }
    )
end

return GrindTree
