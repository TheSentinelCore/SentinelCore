local BT = require("core/bt/factory")
local Status = require("core/bt/status")
local Safety = require("modules/grind/phases/safety")
local CorpseRun = require("modules/grind/phases/corpse_run")
local Rest = require("modules/grind/phases/rest")
local Loot = require("modules/grind/phases/loot")
local Vendor = require("modules/grind/phases/vendor")
local Combat = require("modules/grind/phases/combat")
local Pull = require("modules/grind/phases/pull")
local Acquire = require("modules/grind/phases/acquire")
local Patrol = require("modules/grind/patrol")
local QuestPhases = require("modules/quest/quest_phases")

local GrindTree = {}

-- Diagnostic: throttled phase-level tracing
local _phase_diag_last_ms = 0
local _PHASE_DIAG_MS = 500

--- Wrap a BT node to log when it returns non-FAILURE (i.e. it's the active phase).
--- Propagates reset() so Sequence._running_index is preserved.
local function diag_phase(name, node)
    return {
        _inner = node,
        tick = function(self, bb)
            local status = self._inner:tick(bb)
            local now = bb:get("system.now_ms", 0)
            if now - _phase_diag_last_ms >= _PHASE_DIAG_MS then
                if status ~= Status.FAILURE then
                    _phase_diag_last_ms = now
                    if core and core.log then
                        pcall(core.log, "[GrindTree] ACTIVE: " .. name .. "=" .. tostring(status))
                    end
                end
            end
            return status
        end,
        reset = function(self)
            if self._inner and self._inner.reset then self._inner:reset() end
        end,
    }
end

--- Build the master grind behavior tree.
--- Priority order (highest first):
---   safety > corpse_run > pvp_avoidance > rest > loot > vendor > combat > pull > acquire
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

    -- PvP avoidance: stop and wait when enemy player detected nearby
    local pvp_avoidance = BT.sequence("pvp_avoidance", {
        BT.condition("pvp_enabled", function(bb)
            return bb:get("module.grind.pvp_avoidance", true) == true
        end),
        BT.condition("pvp_threat", function(bb)
            return bb:get("module.grind.pvp_threat_nearby", false) == true
        end),
        BT.action("pvp_wait", function(_bb)
            nav_adapter:stop("pvp_avoidance")
            return Status.RUNNING
        end),
    })

    return BT.cooldown("grind_root_cooldown", 100,
        BT.priority_selector("grind_root", {
            diag_phase("safety", Safety.build(event_bus, nav_adapter)),
            diag_phase("corpse_run", CorpseRun.build(event_bus, nav_adapter)),
            diag_phase("pvp", pvp_avoidance),
            diag_phase("rest", Rest.build(event_bus, nav_adapter)),
            diag_phase("loot", Loot.build(event_bus, nav_adapter)),
            diag_phase("vendor", Vendor.build(blackboard, event_bus, nav_adapter)),
            diag_phase("quest", QuestPhases.build_quest_tree()),
            diag_phase("combat", Combat.build()),
            diag_phase("pull", Pull.build(blackboard, event_bus, nav_adapter)),
            diag_phase("acquire", mode_acquire),
            -- Fallback: logs when ALL phases return FAILURE
            BT.action("diag_all_fail", function(bb)
                local now = bb:get("system.now_ms", 0)
                if now - _phase_diag_last_ms >= _PHASE_DIAG_MS then
                    _phase_diag_last_ms = now
                    if core and core.log then
                        pcall(core.log, string.format(
                            "[GrindTree] ALL_FAIL: src=%s tgt=%s rest=%s loot=%s cast=%s",
                            tostring(bb:get("combat.source")),
                            tostring(bb:get("module.grind.current_target") ~= nil),
                            tostring(bb:get("module.grind.is_resting")),
                            tostring(bb:get("module.grind.is_looting")),
                            tostring(bb:get("player.is_casting", false))))
                    end
                end
                return Status.FAILURE
            end),
        }),
        { key = "module.grind.root_cooldown" }
    )
end

return GrindTree
