local UnifiedStateMachine = {}
UnifiedStateMachine.__index = UnifiedStateMachine

local Events = require("modules/combat/events")
local BT = require("core/bt/factory")
local Status = require("core/bt/status")

-- State constants (combines grind phases + combat states)
UnifiedStateMachine.STATES = {
    -- Grind states (higher priority)
    SAFETY = "SAFETY",
    CORPSE_RUN = "CORPSE_RUN",
    PVP_AVOIDANCE = "PVP_AVOIDANCE",
    REST = "REST",
    LOOT = "LOOT",
    VENDOR = "VENDOR",
    -- Combat states
    COMBAT_IDLE = "COMBAT_IDLE",
    COMBAT_ENGAGING = "COMBAT_ENGAGING",
    COMBAT_CASTING = "COMBAT_CASTING",
    COMBAT_COOLDOWN = "COMBAT_COOLDOWN",
    -- Grind states (lower priority)
    PULL = "PULL",
    ACQUIRE = "ACQUIRE",
    IDLE = "IDLE",
}

-- State priorities (lower number = higher priority)
UnifiedStateMachine.PRIORITIES = {
    SAFETY = 1,
    CORPSE_RUN = 2,
    PVP_AVOIDANCE = 3,
    REST = 4,
    LOOT = 5,
    VENDOR = 6,
    COMBAT_ENGAGING = 7,
    COMBAT_CASTING = 8,
    COMBAT_COOLDOWN = 9,
    PULL = 10,
    ACQUIRE = 11,
    COMBAT_IDLE = 12,
    IDLE = 13,
}

function UnifiedStateMachine:new(event_bus, blackboard, nav_adapter, izi_bridge)
    local o = setmetatable({
        _event_bus = event_bus,
        _blackboard = blackboard,
        _nav_adapter = nav_adapter,
        _izi_bridge = izi_bridge,
        _state = UnifiedStateMachine.STATES.IDLE,
        _previous_state = nil,
        _state_data = {},
        _subscriptions = {},
        _phase_nodes = {},
    }, self)

    -- Build phase nodes
    o:_build_phase_nodes()

    -- Subscribe to events
    o:_subscribe_events()

    return o
end

function UnifiedStateMachine:_build_phase_nodes()
    -- Import phases
    local Safety = require("modules/grind/phases/safety")
    local CorpseRun = require("modules/grind/phases/corpse_run")
    local Rest = require("modules/grind/phases/rest")
    local Loot = require("modules/grind/phases/loot")
    local Vendor = require("modules/grind/phases/vendor")
    local Pull = require("modules/grind/phases/pull")
    local Acquire = require("modules/grind/phases/acquire")
    local Patrol = require("modules/grind/patrol")

    local Combat = require("modules/grind/phases/combat")
    local ProfileInterface = require("modules/combat/profile_interface")

    local bb = self._blackboard

    -- Grind phase nodes
    self._phase_nodes.SAFETY = Safety.build(self._event_bus, self._nav_adapter)
    self._phase_nodes.CORPSE_RUN = CorpseRun.build(self._event_bus, self._nav_adapter)
    self._phase_nodes.REST = Rest.build(self._event_bus, self._nav_adapter)
    self._phase_nodes.LOOT = Loot.build(self._event_bus, self._nav_adapter)
    self._phase_nodes.VENDOR = Vendor.build(bb, self._event_bus, self._nav_adapter)

    -- Combat node (delegates to combat module)
    self._phase_nodes.COMBAT = Combat.build()

    -- Pull node
    self._phase_nodes.PULL = Pull.build(bb, self._event_bus, self._nav_adapter)

    -- Acquire nodes (profile and patrol)
    local profile_acquire = Acquire.build(bb, self._event_bus, self._nav_adapter)
    local patrol_acquire = Patrol.build_acquire(self._event_bus, self._nav_adapter)

    self._phase_nodes.ACQUIRE = BT.action("mode_acquire", function(bb)
        local mode = bb:get("module.grind.mode", "profile")
        if mode == "patrol" then
            return patrol_acquire:tick(bb)
        else
            return profile_acquire:tick(bb)
        end
    end)
end

function UnifiedStateMachine:_subscribe_events()
    local subs = self._subscriptions
    subs[#subs + 1] = self._event_bus:subscribe(Events.ENGAGED, function(payload)
        self:transition(UnifiedStateMachine.STATES.COMBAT_ENGAGING, "engaged")
    end)
    subs[#subs + 1] = self._event_bus:subscribe(Events.DISENGAGED, function(payload)
        self:transition(UnifiedStateMachine.STATES.COMBAT_IDLE, "disengaged")
    end)
    subs[#subs + 1] = self._event_bus:subscribe("grind:death", function(payload)
        self:transition(UnifiedStateMachine.STATES.CORPSE_RUN, "death")
    end)
    subs[#subs + 1] = self._event_bus:subscribe("grind:paused", function(payload)
        self:transition(UnifiedStateMachine.STATES.IDLE, "paused")
    end)
end

function UnifiedStateMachine:get_state()
    return self._state
end

function UnifiedStateMachine:transition(new_state, reason)
    if self._state == new_state then
        return
    end
    self._previous_state = self._state
    self._state = new_state
    self._blackboard:set("unified.state", new_state)

    self._event_bus:publish(Events.STATE_CHANGED, {
        from = self._previous_state,
        to = new_state,
        reason = reason or "transition",
    })
end

function UnifiedStateMachine:_evaluate_priority_state(bb)
    -- Check grind phases in priority order
    if bb:get("module.grind.enabled") == true then
        -- Safety check (highest priority)
        if self:_check_safety(bb) then
            return UnifiedStateMachine.STATES.SAFETY
        end

        -- Corpse run
        if bb:get("player.is_dead", false) == true or bb:get("player.is_ghost", false) == true then
            return UnifiedStateMachine.STATES.CORPSE_RUN
        end

        -- PvP avoidance
        if bb:get("module.grind.pvp_avoidance", true) == true
            and bb:get("module.grind.pvp_threat_nearby", false) == true then
            return UnifiedStateMachine.STATES.PVP_AVOIDANCE
        end

        -- Rest
        local hp = bb:get("player.health_pct", 1)
        local mana = bb:get("player.mana_pct", 1)
        local eat = bb:get("module.grind.health_eat_pct", 0.5)
        local drink = bb:get("module.grind.mana_drink_pct", 0.4)
        if hp < eat or mana < drink then
            return UnifiedStateMachine.STATES.REST
        end

        -- Loot
        if bb:get("module.grind.is_looting", false) == true then
            return UnifiedStateMachine.STATES.LOOT
        end

        -- Vendor
        if bb:get("module.grind.needs_vendor", false) == true then
            return UnifiedStateMachine.STATES.VENDOR
        end
    end

    -- Combat states
    local combat_source = bb:get("combat.source")
    if combat_source then
        if bb:get("player.is_casting", false) or bb:get("player.is_channeling", false) then
            return UnifiedStateMachine.STATES.COMBAT_CASTING
        end

        local combat_state = bb:get("combat.state")
        if combat_state == "COOLDOWN" then
            return UnifiedStateMachine.STATES.COMBAT_COOLDOWN
        elseif combat_state == "ENGAGING" then
            return UnifiedStateMachine.STATES.COMBAT_ENGAGING
        end

        return UnifiedStateMachine.STATES.COMBAT_ENGAGING
    end

    -- Pull
    if bb:get("module.grind.enabled") == true
        and bb:get("module.grind.current_target") ~= nil
        and bb:get("combat.source") == nil then
        return UnifiedStateMachine.STATES.PULL
    end

    -- Acquire
    if bb:get("module.grind.enabled") == true then
        return UnifiedStateMachine.STATES.ACQUIRE
    end

    -- Idle
    return UnifiedStateMachine.STATES.IDLE
end

function UnifiedStateMachine:_check_safety(bb)
    local hp = bb:get("player.health_pct", 1)
    local flee_pct = bb:get("module.grind.health_flee_pct", 0.2)
    return hp <= flee_pct
end

function UnifiedStateMachine:update()
    local bb = self._blackboard
    local now = bb:get("system.now_ms", 0)

    -- Update combat module
    local combat = self._blackboard:get("module.combat.object")
    if combat then
        combat:update(bb)
    end

    -- Determine priority state
    local desired_state = self:_evaluate_priority_state(bb)

    if desired_state ~= self._state then
        self:transition(desired_state, "priority_change")
    end

    -- Execute current phase
    self:_execute_phase(bb, now)
end

function UnifiedStateMachine:_execute_phase(bb, now)
    local state = self._state
    local node = self._phase_nodes[state]

    if not node then
        return
    end

    -- Add state to blackboard for debugging
    bb:set("unified.active_phase", state)

    local status = node:tick(bb)

    -- Handle phase completion
    if status == Status.SUCCESS then
        -- Phase completed, will re-evaluate next tick
    elseif status == Status.FAILURE then
        -- Phase failed, will re-evaluate next tick
    end
end

function UnifiedStateMachine:reset()
    self:transition(UnifiedStateMachine.STATES.IDLE, "reset")
    for _, node in pairs(self._phase_nodes) do
        if node and node.reset then
            node:reset()
        end
    end
end

function UnifiedStateMachine:shutdown()
    for _, token in ipairs(self._subscriptions) do
        self._event_bus:unsubscribe(token)
    end
    self._subscriptions = {}
end

return UnifiedStateMachine