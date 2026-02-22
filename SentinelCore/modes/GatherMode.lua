local BT = require("lib/BehaviorTree")
local CombatKernelTree = require("behaviors/trees/CombatKernelTree")
local ModeState = require("core/ModeState")
local Defaults = require("core/Defaults")
local WaypointObjectiveProvider = require("modes/providers/WaypointObjectiveProvider")

---@class GatherMode
local GatherMode = {}
GatherMode.__index = GatherMode

---@return GatherMode
function GatherMode:new()
    local o = setmetatable({}, GatherMode)
    o._tree = nil
    o._services = nil
    o._objective_provider = WaypointObjectiveProvider:new({
        mode_id = "gather",
        queue_key = "objective.gather.queue",
        index_key = "objective.gather.queue_index",
        loop_key = "objective.gather.loop",
        default_loop = true,
        arrive_distance = 4.0,
        reissue_secs = 1.0,
        timeout_secs = 150.0,
    })
    o._definition = ModeState.normalize_definition({
        id = "gather",
        phases = {
            "scout",
            "acquire",
            "objective",
            "pull",
            "combat",
            "loot",
            "vendor",
            "recover",
        },
        default_phase = "scout",
        functional = true,
        capability_flags = {
            supports_combat = true,
            supports_loot = true,
            supports_vendor = true,
            supports_gather = true,
            supports_objectives = true,
            objective_provider = "waypoint_queue",
            execution_kernel = "shared_combat",
        },
        description = "Gather mode scaffold with waypoint objective queue on shared combat kernel.",
    })
    return o
end

---@return string
function GatherMode:id()
    return self._definition.id
end

---@param ctx table
---@return boolean
function GatherMode:can_enter(ctx)
    if not ctx then
        return false
    end
    if ctx.dependencies_ok ~= true then
        return false
    end
    if not ctx.canonical_context then
        return false
    end
    return self._definition.functional == true
end

---@param services table
---@param command_handlers table
---@return table
function GatherMode:build_tree(services, command_handlers)
    self._services = services
    self._tree = CombatKernelTree.create(services, command_handlers)
    return self._tree
end

---@param ctx table
function GatherMode:on_enter(ctx)
    if self._services and self._services.blackboard then
        self._services.blackboard:set("core.mode_anchor", self._services.blackboard:get("player.position"))
    end
end

---@param ctx table
---@return string
function GatherMode:tick(ctx)
    if not self._tree then
        return BT.FAILURE
    end

    return self._tree:tick(self._services.blackboard, 0)
end

---@param ctx table
---@param reason? string
function GatherMode:on_exit(ctx, reason)
    if self._tree then
        self._tree:reset()
    end
end

---@return table
function GatherMode:get_capability_flags()
    return Defaults.copy(self._definition.capability_flags)
end

---@return table
function GatherMode:get_definition()
    return Defaults.copy(self._definition)
end

---@return table|nil
function GatherMode:get_objective_provider()
    return self._objective_provider
end

return GatherMode
