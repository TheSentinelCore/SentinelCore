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

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local function num(value)
    return tonumber(value) or 0
end

-- Import AOE helper for optimal positioning
local AoeHelper = nil
local function get_aoe_helper()
    if not AoeHelper then
        AoeHelper = require("shared/aoe_helper")
    end
    return AoeHelper
end

function Act.queue_avenging_wrath(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "avenging_wrath", "avenging_wrath", player, QueuePriorities.DEFAULT, { fast = true })
end

function Act.queue_hammer_of_justice(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "hammer_of_justice_interrupt", "hammer_of_justice", target, QueuePriorities.INTERRUPT)
end

function Act.queue_seal_of_command_rank1(blackboard)
    local player = blackboard:get("player.object")
    local result = queue_target(blackboard, "seal_twist_prime_soc_r1", "seal_of_command", player, QueuePriorities.DEFAULT, nil, "lowest")
    if result == Status.SUCCESS then
        blackboard:set("rotation.twist.pending_reseal", true)
        blackboard:set("rotation.twist.last_prime_at_ms", blackboard:get("system.now_ms", 0))
    end
    return result
end

function Act.queue_hammer_of_wrath(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "hammer_of_wrath_execute", "hammer_of_wrath", target, QueuePriorities.DEFAULT)
end

function Act.queue_judgement(blackboard)
    local _, target = player_and_target(blackboard)
    local result = queue_target(blackboard, "judgement", "judgement", target, QueuePriorities.DEFAULT)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", true)
    end
    return result
end

function Act.queue_seal_of_blood(blackboard)
    local player = blackboard:get("player.object")
    local result = queue_target(blackboard, "seal_of_blood", "seal_of_blood", player, QueuePriorities.DEFAULT)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", false)
        blackboard:set("rotation.twist.pending_reseal", false)
    end
    return result
end

function Act.queue_seal_of_command(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "seal_of_command_aoe_maintain", "seal_of_command", player, QueuePriorities.DEFAULT)
end

function Act.queue_crusader_strike(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "crusader_strike", "crusader_strike", target, QueuePriorities.DEFAULT)
end

function Act.queue_consecration(blackboard)
    -- Use AOE helper to find optimal position for Consecration to hit maximum enemies
    local spell_id = spell_id_for(blackboard, "consecration")
    if not spell_id then
        -- Fallback to original behavior if spell ID not found
        local player = blackboard:get("player.object")
        return queue_target(blackboard, "consecration", "consecration", player, QueuePriorities.DEFAULT)
    end
    
    -- Try to get optimal position using AOE helper (consecration is centered on caster, but we can move to optimize)
    local optimal_pos, hit_count = get_aoe_helper().find_optimal_position(
        spell_id, 
        0,    -- Consecration is centered on caster, so we don't range from target
        2,    -- Minimum targets for AOE (try to hit at least 2 enemies)
        8     -- Consecration radius
    )
    
    -- If we found a good position with enough targets, use it
    if optimal_pos and hit_count >= 2 then
        return queue_position(blackboard, "consecration", "consecration", optimal_pos, QueuePriorities.DEFAULT)
    end
    
    -- Fallback to casting on self (original behavior)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "consecration", "consecration", player, QueuePriorities.DEFAULT)
end

function Act.queue_retribution_aura(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "retribution_aura", "retribution_aura", player, QueuePriorities.DEFAULT)
end

function Act.queue_blessing_of_might(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "blessing_of_might", "blessing_of_might", player, QueuePriorities.DEFAULT)
end

function Act.queue_blessing_of_kings(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "blessing_of_kings", "blessing_of_kings", player, QueuePriorities.DEFAULT)
end

function Act.noop()
    return Status.FAILURE
end

return Act