local BT = require("lib/BehaviorTree")

---@class BgModePlaceholder
local BgMode = {}
BgMode.__index = BgMode

function BgMode:new()
    return setmetatable({}, BgMode)
end

function BgMode:id()
    return "bg"
end

function BgMode:can_enter(ctx)
    return false
end

function BgMode:build_tree(services)
    return nil
end

function BgMode:on_enter(ctx) end
function BgMode:tick(ctx) return BT.FAILURE end
function BgMode:on_exit(ctx, reason) end

function BgMode:get_capability_flags()
    return {
        functional = false,
        reason = "out_of_scope_p0_p1_p1_5",
    }
end

return BgMode
