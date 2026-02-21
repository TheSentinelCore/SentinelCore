---@module BGBOT.bg.wsg.wsg_module
-- WSG BG Module: implements BgModule interface.
-- Map ID validation, static positions, WSG detection, intent scoring stub.
-- Q-001 (map_ids) and Q-007 (positions) are HARD M1 GATES.

local constants = require("shared/constants")
local config    = require("shared/config")
local utils     = require("shared/utils")
local helpers   = require("core/intent/intents/wsg_helpers")

local wsg_module = {}
wsg_module.__index = wsg_module

local max = math.max

----------------------------------------------------------------------
-- BgModule interface fields
----------------------------------------------------------------------

wsg_module.id = "wsg"

-- HARD M1 GATE: must be filled via runtime core.get_map_id() validation
-- before any intent logic is written.  (Q-001, DEC-012)
wsg_module.map_ids = constants.WSG_MAP_IDS

----------------------------------------------------------------------
-- BG Detection
----------------------------------------------------------------------

---@param map_id number|nil current map ID from core.get_map_id()
---@param _ui_map_id number|nil unused; kept for backward-compatible callsites
---@return boolean  true if we are inside WSG
function wsg_module:is_active(map_id, _ui_map_id)
    for _, id in ipairs(self.map_ids) do
        if map_id == id then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Static Positions (NON-AUTHORITATIVE — Q-007)
----------------------------------------------------------------------

function wsg_module:get_static_positions()
    return constants.WSG_POSITIONS
end

----------------------------------------------------------------------
-- Objectives  (reads World Model BG state)
----------------------------------------------------------------------

---@param world_model WorldModel
---@return table  { our_flag, their_flag, our_score, their_score }
function wsg_module:get_objectives(world_model)
    local bg = world_model:get_bg_state()
    return {
        our_flag    = bg.our_flag_state,
        their_flag  = bg.their_flag_state,
        our_score   = bg.our_score,     -- may be nil (DEC-013)
        their_score = bg.their_score,   -- may be nil (DEC-013)
    }
end

----------------------------------------------------------------------
-- Score Intents  (M1: roam only.  M2: full WSG scoring per spec.)
----------------------------------------------------------------------

---@param world_model WorldModel
---@param intent_registry table { [intent_id] = Intent }
---@return table { [intent_id] = score }
function wsg_module:score_intents(world_model, intent_registry)
    local scores = {}
    local self_state = world_model:get_self()
    local bg = world_model:get_bg_state()

    -- Baseline fallback is always available.
    scores.roam = 20

    if not self_state or not self_state.position or not bg or bg.bg_type ~= "wsg" then
        return scores
    end

    local role = helpers.resolve_role(self_state)
    local low_hp = (self_state.health_pct or 100) <= (config.combat.retreat_hp_pct or constants.COMBAT.RETREAT_HEALTH_PCT)
    local self_in_combat = self_state.is_in_combat == true

    local allies_near, enemies_near = 0, 0
    if self_state.position then
        allies_near, enemies_near = helpers.count_players_near(
            world_model,
            self_state.position,
            constants.WSG.LOCAL_RISK_RADIUS
        )
    end
    local outnumbered = enemies_near > (allies_near + (config.wsg.outnumbered_margin or constants.WSG.OUTNUMBERED_MARGIN))

    local self_handle = self_state.handle
    local live_self = core.object_manager.get_local_player()
    if helpers.is_valid_handle(live_self) then
        self_handle = live_self
    end

    local have_enemy_flag = helpers.has_enemy_flag_aura(self_handle, self_state)
    if not have_enemy_flag and self_state.has_flag then
        local _, enemy_flag_aura = helpers.get_team_flag_auras(self_state)
        if enemy_flag_aura == 0 then
            have_enemy_flag = true
        end
    end

    local observed_ally_carrier, observed_enemy_carrier = helpers.find_flag_carriers(world_model, self_state)

    local ally_has_enemy_flag = observed_ally_carrier
        and helpers.is_valid_handle(observed_ally_carrier)
        and not helpers.same_handle(observed_ally_carrier, self_handle)

    if not ally_has_enemy_flag then
        ally_has_enemy_flag = bg.our_flag_carrier
            and helpers.is_valid_handle(bg.our_flag_carrier)
            and not helpers.same_handle(bg.our_flag_carrier, self_handle)
    end

    local enemy_has_our_flag = observed_enemy_carrier and helpers.is_valid_handle(observed_enemy_carrier)
    if not enemy_has_our_flag then
        enemy_has_our_flag = bg.their_flag_carrier and helpers.is_valid_handle(bg.their_flag_carrier)
    end

    if intent_registry.carry_flag then
        if have_enemy_flag then
            scores.carry_flag = 100
        else
            -- If neither carrier is known, pressure enemy base.
            if not ally_has_enemy_flag and not enemy_has_our_flag then
                scores.carry_flag = 62
            end
        end
    end

    if intent_registry.escort_carrier and ally_has_enemy_flag and not self_in_combat then
        local carrier_handle = observed_ally_carrier or bg.our_flag_carrier
        local carrier_pos = helpers.handle_to_pos(carrier_handle)
        local dist = carrier_pos and utils.distance_3d(self_state.position, carrier_pos) or 60
        scores.escort_carrier = max(90, 75 * helpers.distance_mod(dist))
    end

    if intent_registry.intercept_carrier and enemy_has_our_flag then
        local carrier_handle = observed_enemy_carrier or bg.their_flag_carrier
        local carrier_pos = helpers.handle_to_pos(carrier_handle)
        local dist = carrier_pos and utils.distance_3d(self_state.position, carrier_pos) or 70
        scores.intercept_carrier = 80 * helpers.distance_mod(dist)
    end

    if intent_registry.return_flag and not enemy_has_our_flag then
        local flag_obj, dist = helpers.find_nearest_flag_object(
            world_model,
            self_state.position,
            75,
            self_state,
            "our"
        )
        if flag_obj and dist and flag_obj.position then
            local team = helpers.get_team_positions(self_state)
            local at_home = false
            if team.our_base then
                at_home = utils.distance_2d(flag_obj.position, team.our_base)
                    <= (constants.WSG.FLAG_HOME_RADIUS or 14)
            end
            if not at_home then
                scores.return_flag = 72 * helpers.distance_mod(dist)
            end
        end
    end

    if intent_registry.fight then
        local enemy, dist = helpers.find_nearest_enemy(world_model, self_state.position, 35)
        if enemy and dist then
            scores.fight = 42 + max(0, 25 - dist)
        end
    end

    if intent_registry.retreat then
        if low_hp then
            scores.retreat = max(scores.retreat or 0, 70 + max(0, (30 - (self_state.health_pct or 0))))
        end
        if outnumbered then
            local disadvantage = enemies_near - allies_near
            scores.retreat = max(scores.retreat or 0, 60 + (disadvantage * 8))
        end
    end

    -- Role bias
    if role == constants.ROLE.HEALER then
        if scores.escort_carrier then scores.escort_carrier = scores.escort_carrier + 15 end
        if scores.fight then scores.fight = scores.fight - 8 end
    elseif role == constants.ROLE.TANKISH then
        if scores.carry_flag then scores.carry_flag = scores.carry_flag + 8 end
        if scores.intercept_carrier then scores.intercept_carrier = scores.intercept_carrier + 6 end
    elseif role == constants.ROLE.DPS then
        if scores.intercept_carrier then scores.intercept_carrier = scores.intercept_carrier + 10 end
        if scores.fight then scores.fight = scores.fight + 6 end
    end

    -- Team safety penalty
    if outnumbered and not have_enemy_flag then
        if scores.fight then scores.fight = scores.fight * 0.60 end
        if scores.carry_flag then scores.carry_flag = scores.carry_flag * 0.85 end
    end

    return scores
end

return wsg_module
