local ModeState = require("core/ModeState")
local Defaults = require("core/Defaults")
local WaypointObjectiveProvider = require("modes/providers/WaypointObjectiveProvider")

---@class GrindMode
local GrindMode = {}
GrindMode.__index = GrindMode

---@return GrindMode
function GrindMode:new()
    local o = setmetatable({}, GrindMode)
    o._services = nil
    o._objective_provider = WaypointObjectiveProvider:new({
        mode_id = "grind",
        queue_key = "objective.grind.queue",
        index_key = "objective.grind.queue_index",
        loop_key = "objective.grind.loop",
        default_loop = true,
        arrive_distance = 5.0,
        reissue_secs = 1.5,
        timeout_secs = 120.0,
    })
    o._definition = ModeState.normalize_definition({
        id = "grind",
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
            supports_quest = false,
            supports_gather = false,
            supports_bg = false,
            supports_objectives = true,
        },
        description = "Primary XP/hr grinding mode with optional waypoint objective queue.",
    })
    return o
end

---@return string
function GrindMode:id()
    return self._definition.id
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
    -- Legacy tree not used; grind mode uses GrindService reactive BT.
    -- Return non-nil so _bind_mode_tree considers the bind successful.
    return {}
end

---@param ctx table
function GrindMode:on_enter(ctx)
    if self._services and self._services.blackboard then
        local anchor = self._services.blackboard:get("player.position")
        self._services.blackboard:set("core.mode_anchor", anchor)
        self._services.blackboard:set("grind.anchor", anchor)
    end
end

---@param ctx table
---@return string
function GrindMode:tick(ctx)
    -- Legacy tick unused; Client.update() drives GrindService tree directly.
    return "success"
end

---@param ctx table
---@param reason? string
function GrindMode:on_exit(ctx, reason)
    -- No legacy tree to reset; GrindService tree is owned by Client.
end

---@return table
function GrindMode:get_capability_flags()
    return Defaults.copy(self._definition.capability_flags)
end

---@return table
function GrindMode:get_definition()
    return Defaults.copy(self._definition)
end

---@return table|nil
function GrindMode:get_objective_provider()
    return self._objective_provider
end

return GrindMode
