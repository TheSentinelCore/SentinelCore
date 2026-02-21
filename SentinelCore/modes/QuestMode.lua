local BT = require("lib/BehaviorTree")

---@class QuestModePlaceholder
local QuestMode = {}
QuestMode.__index = QuestMode

function QuestMode:new()
    return setmetatable({}, QuestMode)
end

function QuestMode:id()
    return "quest"
end

function QuestMode:can_enter(ctx)
    return false
end

function QuestMode:build_tree(services)
    return nil
end

function QuestMode:on_enter(ctx) end
function QuestMode:tick(ctx) return BT.FAILURE end
function QuestMode:on_exit(ctx, reason) end

function QuestMode:get_capability_flags()
    return {
        functional = false,
        reason = "out_of_scope_p0_p1_p1_5",
    }
end

return QuestMode
