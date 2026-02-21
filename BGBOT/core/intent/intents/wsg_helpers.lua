---@module BGBOT.core.intent.intents.wsg_helpers
-- Shared tactical helpers for WSG intents and scoring.
-- Keeps role inference, local risk checks, and target lookups consistent.

local constants = require("shared/constants")
local config    = require("shared/config")
local utils     = require("shared/utils")

local helpers = {}

local max = math.max
local min = math.min
local abs = math.abs

local function safe_call_method(obj, method_name, ...)
    if not obj then
        return nil, false
    end
    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil, false
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, false
    end
    return result, true
end

-- When scanner faction stays UNKNOWN on some servers, infer once and keep it
-- stable to prevent base-goal ping-pong around midfield.
local cached_unknown_faction = constants.FACTION.UNKNOWN

function helpers.reset_runtime_state()
    cached_unknown_faction = constants.FACTION.UNKNOWN
end

function helpers.same_handle(a, b)
    if not a or not b then return false end
    return tostring(a) == tostring(b)
end

function helpers.is_valid_handle(handle)
    local t = type(handle)
    if t ~= "table" and t ~= "userdata" then
        return false
    end
    if handle.is_valid == nil then
        return false
    end

    local valid, ok = safe_call_method(handle, "is_valid")
    return ok and valid == true
end

function helpers.role_name(role_id)
    return constants.ROLE_NAME[role_id] or "auto"
end

function helpers.resolve_role(self_state)
    local forced = tonumber(config.role.mode) or constants.ROLE.AUTO
    if forced ~= constants.ROLE.AUTO then
        return forced
    end

    local group_role = tonumber(self_state and self_state.group_role) or constants.GROUP_ROLE.NONE
    if group_role == constants.GROUP_ROLE.HEALER then
        return constants.ROLE.HEALER
    end
    if group_role == constants.GROUP_ROLE.TANK then
        return constants.ROLE.TANKISH
    end
    if group_role == constants.GROUP_ROLE.DAMAGER then
        return constants.ROLE.DPS
    end

    local class_id = tonumber(self_state and self_state.class_id) or 0
    if class_id == constants.CLASS.PRIEST
        or class_id == constants.CLASS.PALADIN
        or class_id == constants.CLASS.SHAMAN
        or class_id == constants.CLASS.DRUID then
        return constants.ROLE.HEALER
    end

    if class_id == constants.CLASS.WARRIOR then
        return constants.ROLE.TANKISH
    end

    return constants.ROLE.DPS
end

function helpers.distance_mod(distance, falloff)
    local d = tonumber(distance) or 0
    local f = tonumber(falloff) or 45
    local v = 1.0 / (1.0 + (d / f))
    return max(0.20, min(1.0, v))
end

function helpers.to_goal(base_pos, jitter_radius)
    if not base_pos or base_pos.x == nil or base_pos.y == nil or base_pos.z == nil then
        return nil
    end

    local radius = tonumber(jitter_radius) or 0
    local x = base_pos.x
    local y = base_pos.y
    local z = base_pos.z

    if radius > 0 then
        x = x + ((math.random() - 0.5) * radius * 2.0)
        y = y + ((math.random() - 0.5) * radius * 2.0)
    end

    local terrain_z = core.get_height_for_position({ x = x, y = y, z = z })
    if terrain_z and abs(terrain_z) > 0.01 then
        z = terrain_z
    end

    return { x = x, y = y, z = z }
end

function helpers.handle_to_pos(handle)
    if not helpers.is_valid_handle(handle) then return nil end
    local p, ok = safe_call_method(handle, "get_position")
    if not ok or not p then return nil end
    return { x = p.x, y = p.y, z = p.z }
end

function helpers.get_team_flag_auras(self_state)
    local faction = tonumber(self_state and self_state.faction) or constants.FACTION.UNKNOWN
    if faction == constants.FACTION.UNKNOWN and cached_unknown_faction ~= constants.FACTION.UNKNOWN then
        faction = cached_unknown_faction
    end

    if faction == constants.FACTION.HORDE then
        -- Enemy (Alliance) carrying our flag has Horde flag aura; our carrier has Alliance aura.
        return constants.FLAG_AURAS.HORDE_FLAG, constants.FLAG_AURAS.ALLIANCE_FLAG
    elseif faction == constants.FACTION.ALLIANCE then
        -- Enemy (Horde) carrying our flag has Alliance flag aura; our carrier has Horde aura.
        return constants.FLAG_AURAS.ALLIANCE_FLAG, constants.FLAG_AURAS.HORDE_FLAG
    end

    return 0, 0
end

function helpers.get_flag_aura_id(handle)
    if not helpers.is_valid_handle(handle) then return 0 end
    local auras, ok = safe_call_method(handle, "get_auras")
    if not ok or not auras then return 0 end

    for _, aura in pairs(auras) do
        local id = tonumber(aura.buff_id) or 0
        if id == constants.FLAG_AURAS.HORDE_FLAG or id == constants.FLAG_AURAS.ALLIANCE_FLAG then
            return id
        end
    end

    return 0
end

function helpers.has_enemy_flag_aura(handle, self_state)
    local aura_id = helpers.get_flag_aura_id(handle)
    if aura_id == 0 then
        return false, 0
    end

    local _, enemy_flag_aura = helpers.get_team_flag_auras(self_state)
    if enemy_flag_aura == 0 then
        return true, aura_id
    end

    return aura_id == enemy_flag_aura, aura_id
end

function helpers.get_flag_object_npc_ids(self_state)
    local faction = tonumber(self_state and self_state.faction) or constants.FACTION.UNKNOWN
    if faction ~= constants.FACTION.UNKNOWN then
        cached_unknown_faction = faction
    elseif cached_unknown_faction ~= constants.FACTION.UNKNOWN then
        faction = cached_unknown_faction
    end

    local ids = (constants.WSG and constants.WSG.FLAG_OBJECT_NPC) or {}
    if faction == constants.FACTION.ALLIANCE then
        return tonumber(ids.ALLIANCE) or 0, tonumber(ids.HORDE) or 0
    elseif faction == constants.FACTION.HORDE then
        return tonumber(ids.HORDE) or 0, tonumber(ids.ALLIANCE) or 0
    end

    return 0, 0
end

function helpers.flag_object_matches_team(ent, self_state, team_tag)
    if not ent or not ent.is_flag_object then
        return false
    end

    if team_tag ~= "our" and team_tag ~= "their" then
        return true
    end

    local our_npc, their_npc = helpers.get_flag_object_npc_ids(self_state)
    if team_tag == "our" and our_npc ~= 0 then
        return tonumber(ent.npc_id) == our_npc
    end
    if team_tag == "their" and their_npc ~= 0 then
        return tonumber(ent.npc_id) == their_npc
    end

    -- Unknown faction mapping: allow both to avoid deadlocking behavior.
    return true
end

function helpers.find_flag_carriers(world_model, self_state)
    local ally_handle = nil
    local enemy_handle = nil
    local ally_best = 999999
    local enemy_best = 999999
    local self_pos = self_state and self_state.position or nil
    local our_flag_aura, enemy_flag_aura = helpers.get_team_flag_auras(self_state)

    if not world_model then
        return nil, nil
    end

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent and ent.is_player and ent.handle and not ent.is_dead and helpers.is_valid_handle(ent.handle) then
            local aura_id = helpers.get_flag_aura_id(ent.handle)
            if aura_id ~= 0 then
                local dist = 999999
                if self_pos and ent.position then
                    dist = utils.distance_3d(self_pos, ent.position)
                end

                if ent.is_ally and (enemy_flag_aura == 0 or aura_id == enemy_flag_aura) and dist < ally_best then
                    ally_best = dist
                    ally_handle = ent.handle
                elseif ent.is_enemy and (our_flag_aura == 0 or aura_id == our_flag_aura) and dist < enemy_best then
                    enemy_best = dist
                    enemy_handle = ent.handle
                end
            end
        end
    end

    return ally_handle, enemy_handle
end

function helpers.get_team_positions(self_state)
    local p = constants.WSG_POSITIONS or {}
    local faction = tonumber(self_state and self_state.faction) or constants.FACTION.UNKNOWN

    if faction ~= constants.FACTION.UNKNOWN then
        cached_unknown_faction = faction
    elseif cached_unknown_faction ~= constants.FACTION.UNKNOWN then
        faction = cached_unknown_faction
    elseif self_state and self_state.position
        and p.horde_flag_room and p.alliance_flag_room then
        local dist_h = utils.distance_2d(self_state.position, p.horde_flag_room)
        local dist_a = utils.distance_2d(self_state.position, p.alliance_flag_room)
        faction = (dist_h <= dist_a) and constants.FACTION.HORDE or constants.FACTION.ALLIANCE
        cached_unknown_faction = faction
    end

    if faction == constants.FACTION.ALLIANCE then
        return {
            our_base     = p.alliance_flag_room,
            their_base   = p.horde_flag_room,
            our_tunnel   = p.alliance_tunnel,
            their_tunnel = p.horde_tunnel,
            our_gy       = p.alliance_graveyard,
            their_gy     = p.horde_graveyard,
            midfield     = p.midfield,
        }
    end

    return {
        our_base     = p.horde_flag_room,
        their_base   = p.alliance_flag_room,
        our_tunnel   = p.horde_tunnel,
        their_tunnel = p.alliance_tunnel,
        our_gy       = p.horde_graveyard,
        their_gy     = p.alliance_graveyard,
        midfield     = p.midfield,
    }
end

function helpers.find_nearest_entity(world_model, from_pos, predicate, max_distance)
    if not world_model or not from_pos then return nil, nil end

    local best = nil
    local best_dist = tonumber(max_distance) or 999999

    for _, ent in pairs(world_model:get_all_entities()) do
        if ent and ent.position then
            local ok, keep = pcall(predicate, ent)
            if ok and keep then
                local d = utils.distance_3d(from_pos, ent.position)
                if d < best_dist then
                    best = ent
                    best_dist = d
                end
            end
        end
    end

    return best, best_dist
end

function helpers.find_nearest_enemy(world_model, from_pos, max_distance)
    return helpers.find_nearest_entity(world_model, from_pos, function(ent)
        return ent.is_player and ent.is_enemy and not ent.is_dead
    end, max_distance)
end

function helpers.find_nearest_ally(world_model, from_pos, max_distance, self_handle)
    return helpers.find_nearest_entity(world_model, from_pos, function(ent)
        if not (ent.is_player and ent.is_ally and not ent.is_dead) then
            return false
        end
        if self_handle and ent.handle and helpers.same_handle(ent.handle, self_handle) then
            return false
        end
        return true
    end, max_distance)
end

function helpers.find_nearest_buff(world_model, from_pos, max_distance)
    return helpers.find_nearest_entity(world_model, from_pos, function(ent)
        return ent.is_buff_object and ent.handle and helpers.is_valid_handle(ent.handle)
    end, max_distance)
end

function helpers.find_nearest_flag_object(world_model, from_pos, max_distance, self_state, team_tag)
    return helpers.find_nearest_entity(world_model, from_pos, function(ent)
        if not (ent and ent.handle and helpers.is_valid_handle(ent.handle)) then
            return false
        end
        return helpers.flag_object_matches_team(ent, self_state, team_tag)
    end, max_distance)
end

function helpers.count_players_near(world_model, center_pos, radius)
    local allies = 0
    local enemies = 0
    if not world_model or not center_pos then return allies, enemies end

    local r = tonumber(radius) or constants.WSG.LOCAL_RISK_RADIUS
    for _, ent in pairs(world_model:get_all_entities()) do
        if ent and ent.is_player and not ent.is_dead and ent.position then
            if utils.distance_3d(center_pos, ent.position) <= r then
                if ent.is_enemy then
                    enemies = enemies + 1
                elseif ent.is_ally then
                    allies = allies + 1
                end
            end
        end
    end
    return allies, enemies
end

function helpers.find_support_anchor(world_model, self_state)
    if not world_model or not self_state then return nil, nil, "none" end

    local bg = world_model:get_bg_state()
    if bg and helpers.is_valid_handle(bg.our_flag_carrier)
        and not helpers.same_handle(bg.our_flag_carrier, self_state.handle) then
        local p = helpers.handle_to_pos(bg.our_flag_carrier)
        if p then
            return p, bg.our_flag_carrier, "carrier"
        end
    end

    local ally = nil
    if self_state.position then
        ally = select(1, helpers.find_nearest_ally(world_model, self_state.position, 80, self_state.handle))
    end

    if ally and ally.position then
        return ally.position, ally.handle, "ally"
    end

    local pos = helpers.get_team_positions(self_state)
    return pos.our_tunnel or pos.our_gy or pos.midfield, nil, "fallback"
end

function helpers.pick_buff_detour(world_model, self_state, max_distance)
    if not config.wsg.enable_buff_pickups then
        return nil, nil, nil
    end
    if not self_state or not self_state.position then
        return nil, nil, nil
    end

    local max_dist = tonumber(max_distance) or tonumber(config.wsg.buff_detour_max) or constants.WSG.BUFF_DETOUR_MAX
    local buff, dist = helpers.find_nearest_buff(world_model, self_state.position, max_dist)
    if not buff or not buff.position then
        return nil, nil, nil
    end

    local allies, enemies = helpers.count_players_near(
        world_model,
        buff.position,
        constants.WSG.LOCAL_RISK_RADIUS
    )
    local enemy_adv_max = tonumber(config.wsg.buff_enemy_advantage_max)
        or constants.WSG.BUFF_ENEMY_ADVANTAGE_MAX
    if enemies > (allies + enemy_adv_max) then
        return nil, nil, nil
    end

    return helpers.to_goal(buff.position, 1.0), buff.handle, dist
end

return helpers
