local BT = require("lib/BehaviorTree")
local CombatKernelTree = require("behaviors/trees/CombatKernelTree")
local ModeState = require("core/ModeState")
local Defaults = require("core/Defaults")
local WaypointObjectiveProvider = require("modes/providers/WaypointObjectiveProvider")

---@class QuestMode
local QuestMode = {}
QuestMode.__index = QuestMode

---@return QuestMode
function QuestMode:new()
    local o = setmetatable({}, QuestMode)
    o._tree = nil
    o._services = nil
    o._objective_provider = WaypointObjectiveProvider:new({
        mode_id = "quest",
        queue_key = "objective.quest.queue",
        index_key = "objective.quest.queue_index",
        loop_key = "objective.quest.loop",
        default_loop = false,
        arrive_distance = 4.5,
        reissue_secs = 1.25,
        timeout_secs = 180.0,
    })
    o._definition = ModeState.normalize_definition({
        id = "quest",
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
            supports_quest = true,
            supports_objectives = true,
            objective_provider = "waypoint_queue",
            execution_kernel = "shared_combat",
        },
        description = "Quest mode scaffold with waypoint objective queue on shared combat kernel.",
    })
    return o
end

---@return string
function QuestMode:id()
    return self._definition.id
end

---@param ctx table
---@return boolean
function QuestMode:can_enter(ctx)
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
function QuestMode:build_tree(services, command_handlers)
    self._services = services
    self._tree = CombatKernelTree.create(services, command_handlers)
    return self._tree
end

---@param ctx table
function QuestMode:on_enter(ctx)
    if self._services and self._services.blackboard then
        self._services.blackboard:set("core.mode_anchor", self._services.blackboard:get("player.position"))
    end
end

---@param ctx table
---@return string
function QuestMode:tick(ctx)
    if not self._tree then
        return BT.FAILURE
    end

    return self._tree:tick(self._services.blackboard, 0)
end

---@param ctx table
---@param reason? string
function QuestMode:on_exit(ctx, reason)
    if self._tree then
        self._tree:reset()
    end
end

---@return table
function QuestMode:get_capability_flags()
    return Defaults.copy(self._definition.capability_flags)
end

---@return table
function QuestMode:get_definition()
    return Defaults.copy(self._definition)
end

---@return table|nil
function QuestMode:get_objective_provider()
    return self._objective_provider
end

return QuestMode
