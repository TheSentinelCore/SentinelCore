local AuraCatalog = require("modules/combat/aura_catalog")

local ContextBuilder = {}
ContextBuilder.__index = ContextBuilder

local function num(value)
    return tonumber(value) or 0
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end


function ContextBuilder:new(blackboard, izi_bridge)
    local o = setmetatable({}, ContextBuilder)
    o._blackboard = blackboard
    o._izi_bridge = izi_bridge
    o._last_active_seal = nil
    o._last_vengeance = 0
    return o
end

function ContextBuilder:refresh(event_bus)
    local player = self._blackboard:get("player.object")
    local target = self._blackboard:get("combat.target") or self._blackboard:get("player.target")
    local active_seal = nil
    if player then
        if AuraCatalog.has_any(player, AuraCatalog.seal_of_blood) then
            active_seal = "blood"
        elseif AuraCatalog.has_any(player, AuraCatalog.seal_of_command_ranks) then
            active_seal = "command"
        end
    end

    if self._last_active_seal ~= active_seal then
        event_bus:publish("rotation:seal_changed", {
            from_seal = self._last_active_seal,
            to_seal = active_seal,
            reason = "context_refresh",
        })
        self._last_active_seal = active_seal
    end

    local player_pos = self._blackboard:get("player.position")
    local ok_target_pos, target_pos = safe_call(target, "get_position")
    local target_distance = ok_target_pos and distance(player_pos, target_pos) or 99999
    self._blackboard:set("combat.target_distance", target_distance)

    local vengeance = AuraCatalog.get_stacks(player, AuraCatalog.vengeance_proc_auras)
    if vengeance ~= self._last_vengeance then
        event_bus:publish("rotation:vengeance_changed", {
            previous_stacks = self._last_vengeance,
            stacks = vengeance,
        })
        self._last_vengeance = vengeance
    end
    self._blackboard:set("rotation.vengeance_stacks", vengeance)

    local player_in_combat = self._blackboard:get("player.in_combat", false) == true
    local combat_state = tostring(self._blackboard:get("combat.state", "IDLE") or "IDLE")
    local target_valid = false
    if target ~= nil then
        local ok_dead, dead = safe_call(target, "is_dead")
        target_valid = (not ok_dead) or dead ~= true
    end
    local hp = num(self._blackboard:get("player.health_pct", 0))
    local burst_enabled = self._blackboard:get("module.combat.enable_burst", true) == true
    local in_combat_context = player_in_combat or combat_state ~= "IDLE"

    -- Use combat forecast to gate burst if available
    local burst_context = burst_enabled
        and in_combat_context
        and target_valid
        and target_distance <= 10.0
        and hp > 0.40
    if burst_context and self._izi_bridge then
        local forecast = self._izi_bridge:get_forecast()
        local min_burst_duration = 6.0
        if forecast and forecast < min_burst_duration then
            burst_context = false
        end
    end
    self._blackboard:set("combat.burst_context", burst_context)

    local preferred_primary_seal = tostring(self._blackboard:get("module.combat.primary_seal_preference", "blood") or "blood")
    if preferred_primary_seal ~= "command" then
        preferred_primary_seal = "blood"
    end

    local primary_seal = preferred_primary_seal
    self._blackboard:set("rotation.primary_seal", primary_seal)

    local desired_seal = nil
    local desired_reason = "ooc_no_seal"
    if in_combat_context and target_valid then
        if num(self._blackboard:get("combat.enemy_count_10yd", 0)) >= 2 then
            -- Use TTD to decide if worth switching to Command for AoE
            local worth_switching = true
            if self._izi_bridge then
                local ttd = self._izi_bridge:get_time_to_die(target)
                if ttd and ttd < 3.0 then
                    worth_switching = false
                end
            end
            if worth_switching then
                desired_seal = "command"
                desired_reason = "aoe"
            else
                desired_seal = primary_seal
                desired_reason = "single_target_fast_kill"
            end
        else
            desired_seal = primary_seal
            desired_reason = "single_target"
        end
    end

    self._blackboard:set("rotation.desired_seal", desired_seal)
    self._blackboard:set("rotation.desired_seal_reason", desired_reason)
end

return ContextBuilder
