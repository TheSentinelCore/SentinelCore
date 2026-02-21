local BT = require("lib/BehaviorTree")

---@class GatherModePlaceholder
local GatherMode = {}
GatherMode.__index = GatherMode

function GatherMode:new()
    return setmetatable({}, GatherMode)
end

function GatherMode:id()
    return "gather"
end

function GatherMode:can_enter(ctx)
    return false
end

function GatherMode:build_tree(services)
    return nil
end

function GatherMode:on_enter(ctx) end
function GatherMode:tick(ctx) return BT.FAILURE end
function GatherMode:on_exit(ctx, reason) end

function GatherMode:get_capability_flags()
    return {
        functional = false,
        reason = "out_of_scope_p0_p1_p1_5",
    }
end

return GatherMode
