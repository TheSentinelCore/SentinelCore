local BT = require("lib/BehaviorTree")
local GrindTree = require("behaviors/trees/GrindTree")

---@class GrindMode
local GrindMode = {}
GrindMode.__index = GrindMode

---@return GrindMode
function GrindMode:new()
    local o = setmetatable({}, GrindMode)
    o._tree = nil
    o._services = nil
    return o
end

---@return string
function GrindMode:id()
    return "grind"
end

---@param ctx table
---@return boolean
function GrindMode:can_enter(ctx)
    if not ctx then
        return false
    end
    if ctx.dependencies_ok ~= true then
        return false
    end
    if not ctx.canonical_context then
        return false
    end
    return true
end

---@param services table
---@param command_handlers table
---@return table
function GrindMode:build_tree(services, command_handlers)
    self._services = services
    self._tree = GrindTree.create(services, command_handlers)
    return self._tree
end

---@param ctx table
function GrindMode:on_enter(ctx)
    if self._services and self._services.blackboard then
        self._services.blackboard:set("grind.anchor", self._services.blackboard:get("player.position"))
    end
end

---@param ctx table
---@return string
function GrindMode:tick(ctx)
    if not self._tree then
        return BT.FAILURE
    end

    return self._tree:tick(self._services.blackboard, 0)
end

---@param ctx table
---@param reason? string
function GrindMode:on_exit(ctx, reason)
    if self._tree then
        self._tree:reset()
    end
end

---@return table
function GrindMode:get_capability_flags()
    return {
        supports_combat = true,
        supports_loot = true,
        supports_vendor = true,
        supports_quest = false,
        supports_gather = false,
        supports_bg = false,
    }
end

return GrindMode
