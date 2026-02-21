---@module BGBOT.core.intent.intents.carry_flag
-- Carry flag intent:
-- 1) If we have enemy flag, run home.
-- 2) Otherwise push enemy base and attempt interaction on visible flag object.

local intent_base  = require("core/intent/intent_base")
local constants    = require("shared/constants")
local utils        = require("shared/utils")
local wsg_helpers  = require("core/intent/intents/wsg_helpers")

local carry_flag = {}
carry_flag.__index = carry_flag
setmetatable(carry_flag, { __index = intent_base })

function carry_flag.new()
    local self = intent_base.create("carry_flag")
    setmetatable(self, carry_flag)
    self._nav_goal = nil
    self._interact_target = nil
    self._has_flag = false
    self._repath_at = 0
    return self
end

function carry_flag:enter(world_model, params)
    intent_base.enter(self, world_model, params)
    self._nav_goal = nil
    self._interact_target = nil
    self._has_flag = false
    self._repath_at = 0
end

function carry_flag:choose_goal(world_model)
    local self_state = world_model:get_self()
    if not self_state or not self_state.position then
        self._nav_goal = nil
        self._interact_target = nil
        return
    end

    local bg = world_model:get_bg_state()
    local team = wsg_helpers.get_team_positions(self_state)
    local self_handle = self_state.handle
    local live_self = core.object_manager.get_local_player()
    if wsg_helpers.is_valid_handle(live_self) then
        self_handle = live_self
    end

    local _, enemy_flag_aura = wsg_helpers.get_team_flag_auras(self_state)
    local carried_aura = wsg_helpers.get_flag_aura_id(self_handle)
    local have_flag = wsg_helpers.has_enemy_flag_aura(self_handle, self_state)
    if not have_flag and self_state.has_flag and enemy_flag_aura == 0 then
        -- Unknown faction mapping fallback: trust scanner self-flag bit.
        have_flag = true
    end

    self._has_flag = have_flag
    self._interact_target = nil

    if have_flag then
        local hold_target = nil
        local our_base = team.our_base
        local our_tunnel = team.our_tunnel

        -- Resolve home-side endpoints from the carried flag aura first.
        -- This is more reliable than faction APIs on private servers.
        if carried_aura == constants.FLAG_AURAS.ALLIANCE_FLAG then
            our_base = constants.WSG_POSITIONS.horde_flag_room or our_base
            our_tunnel = constants.WSG_POSITIONS.horde_tunnel or our_tunnel
        elseif carried_aura == constants.FLAG_AURAS.HORDE_FLAG then
            our_base = constants.WSG_POSITIONS.alliance_flag_room or our_base
            our_tunnel = constants.WSG_POSITIONS.alliance_tunnel or our_tunnel
        end

        if bg and wsg_helpers.is_valid_handle(bg.their_flag_carrier) then
            hold_target = our_tunnel or our_base or team.midfield
        else
            hold_target = our_base or team.midfield
        end
        self._nav_goal = wsg_helpers.to_goal(hold_target, 0.10)
    else
        if not self_state.is_in_combat then
            local observed_ally_carrier = select(1, wsg_helpers.find_flag_carriers(world_model, self_state))
            if observed_ally_carrier and wsg_helpers.is_valid_handle(observed_ally_carrier)
                and not wsg_helpers.same_handle(observed_ally_carrier, self_handle) then
                local carrier_pos = wsg_helpers.handle_to_pos(observed_ally_carrier)
                if carrier_pos then
                    self._nav_goal = wsg_helpers.to_goal(carrier_pos, 1.0)
                    self._repath_at = core.time() + 1.0 + (math.random() * 1.0)
                    return
                end
            end
        end

        local enemy_base = team.their_base or team.midfield
        local enemy_approach = team.their_tunnel or enemy_base or team.midfield
        local base_distance = enemy_base and utils.distance_2d(self_state.position, enemy_base) or 999999
        if base_distance > 55 then
            self._nav_goal = wsg_helpers.to_goal(enemy_approach, 0.75)
        else
            self._nav_goal = wsg_helpers.to_goal(enemy_base or enemy_approach, 0.75)
        end

        -- Prefer the flag object near enemy base (avoid interacting own base flag).
        local flag_obj, _ = wsg_helpers.find_nearest_flag_object(
            world_model, enemy_base or enemy_approach, 24, self_state, "their"
        )
        if flag_obj and flag_obj.handle and flag_obj.position then
            local dist = utils.distance_3d(self_state.position, flag_obj.position)
            if dist <= (constants.HUMAN.FLAG_INTERACT_RANGE + 2) then
                self._interact_target = flag_obj.handle
                self._nav_goal = wsg_helpers.to_goal(flag_obj.position, 0.25)
            end
        end

        if flag_obj and flag_obj.handle and flag_obj.position and not self._interact_target then
            local to_flag = utils.distance_3d(self_state.position, flag_obj.position)
            if to_flag <= 30 then
                self._nav_goal = wsg_helpers.to_goal(flag_obj.position, 0.5)
            end
        end
    end

    self._repath_at = core.time() + 1.5 + (math.random() * 1.5)
end

function carry_flag:tick(world_model)
    local now = core.time()
    local self_state = world_model:get_self()

    if self._nav_goal == nil or now >= self._repath_at then
        self:choose_goal(world_model)
    elseif self_state and self_state.position and self._nav_goal then
        local dist = utils.distance_3d(self_state.position, self._nav_goal)
        if dist <= 6 then
            self:choose_goal(world_model)
        end
    end

    return {
        nav_goal        = self._nav_goal,
        interact_target = self._interact_target,
        face_target     = nil,
    }
end

function carry_flag:exit()
    intent_base.exit(self)
    self._nav_goal = nil
    self._interact_target = nil
    self._has_flag = false
end

function carry_flag:get_context()
    return {
        engage_allowed      = true,
        max_chase_range     = self._has_flag and constants.COMBAT.CARRIER_CHASE_RANGE
            or constants.COMBAT.DEFAULT_CHASE_RANGE,
        priority_target     = nil,
        disengage_requested = false,
    }
end

function carry_flag:is_interruptible(next_intent_id)
    return next_intent_id == "escort_carrier" or next_intent_id == "intercept_carrier"
end

return carry_flag
