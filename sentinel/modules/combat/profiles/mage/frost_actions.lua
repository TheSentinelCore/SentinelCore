local QueuePriorities = require("shared/queue_priorities")
local Status = require("core/bt/status")

local Act = {}

local function spell_id_for(blackboard, spell_key, mode)
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then
        return nil
    end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

local function dispatcher(blackboard)
    return blackboard:get("module.combat.dispatcher")
end

local function player_and_target(blackboard)
    return blackboard:get("player.object"), blackboard:get("combat.target") or blackboard:get("player.target")
end

local function queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local d = dispatcher(blackboard)
    local spell_id = spell_id_for(blackboard, spell_key, mode)
    if not d or not spell_id then
        return Status.FAILURE
    end
    if d:queue_target(action_id, spell_id, target, priority, action_id, opts) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

local function queue_position(blackboard, action_id, spell_key, position, priority, mode)
    local d = dispatcher(blackboard)
    local spell_id = spell_id_for(blackboard, spell_key, mode)
    if not d or not spell_id or type(position) ~= "table" then
        return Status.FAILURE
    end
    if d:queue_position(action_id, spell_id, position, priority, action_id) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- GCD actions
-- ---------------------------------------------------------------------------

function Act.queue_frostbolt(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "frostbolt", "frostbolt", target, QueuePriorities.PRIMARY)
end

function Act.queue_fire_blast(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "fire_blast", "fire_blast", target, QueuePriorities.PRIMARY)
end

function Act.queue_frost_nova(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "frost_nova", "frost_nova", player, QueuePriorities.DEFENSIVE)
end

function Act.queue_cone_of_cold(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "cone_of_cold", "cone_of_cold", player, QueuePriorities.PRIMARY)
end

function Act.queue_blizzard(blackboard)
    local _, target = player_and_target(blackboard)
    if not target then
        return Status.FAILURE
    end
    local ok_pos, pos = pcall(target.get_position, target)
    if not ok_pos or type(pos) ~= "table" then
        return Status.FAILURE
    end
    return queue_position(blackboard, "blizzard", "blizzard", pos, QueuePriorities.PRIMARY)
end

function Act.queue_ice_lance(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "ice_lance", "ice_lance", target, QueuePriorities.PRIMARY)
end

function Act.queue_counterspell(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "counterspell", "counterspell", target, QueuePriorities.INTERRUPT)
end

function Act.queue_ice_block(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "ice_block", "ice_block", player, QueuePriorities.DEFENSIVE)
end

function Act.queue_blink(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "blink", "blink", player, QueuePriorities.DEFENSIVE)
end

function Act.queue_mana_shield(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "mana_shield", "mana_shield", player, QueuePriorities.DEFENSIVE)
end

function Act.queue_evocation(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "evocation", "evocation", player, QueuePriorities.UTILITY)
end

-- ---------------------------------------------------------------------------
-- Off-GCD actions
-- ---------------------------------------------------------------------------

function Act.queue_ice_barrier(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "ice_barrier", "ice_barrier", player, QueuePriorities.DEFENSIVE, { fast = true })
end

function Act.queue_icy_veins(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "icy_veins", "icy_veins", player, QueuePriorities.BURST, { fast = true })
end

function Act.queue_cold_snap(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "cold_snap", "cold_snap", player, QueuePriorities.DEFENSIVE, { fast = true })
end

-- ---------------------------------------------------------------------------
-- Maintenance actions
-- ---------------------------------------------------------------------------

function Act.queue_frost_armor(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "frost_armor", "frost_armor", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_ice_armor(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "ice_armor", "ice_armor", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_arcane_intellect(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "arcane_intellect", "arcane_intellect", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_conjure_food(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "conjure_food", "conjure_food", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_conjure_water(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "conjure_water", "conjure_water", player, QueuePriorities.MAINTENANCE)
end

-- ---------------------------------------------------------------------------
-- Fallback
-- ---------------------------------------------------------------------------

function Act.noop()
    return Status.FAILURE
end

return Act
