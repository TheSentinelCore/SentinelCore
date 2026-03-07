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

function Act.queue_avenging_wrath(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "avenging_wrath", "avenging_wrath", player, QueuePriorities.BURST, { fast = true })
end

function Act.queue_hammer_of_justice(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "hammer_of_justice_interrupt", "hammer_of_justice", target, QueuePriorities.INTERRUPT)
end

function Act.queue_seal_of_command_rank1(blackboard)
    local player = blackboard:get("player.object")
    local result = queue_target(blackboard, "seal_twist_prime_soc_r1", "seal_of_command", player, QueuePriorities.PRIMARY, nil, "lowest")
    if result == Status.SUCCESS then
        blackboard:set("rotation.twist.pending_reseal", true)
        blackboard:set("rotation.twist.last_prime_at_ms", blackboard:get("system.now_ms", 0))
    end
    return result
end

function Act.queue_hammer_of_wrath(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "hammer_of_wrath_execute", "hammer_of_wrath", target, QueuePriorities.PRIMARY)
end

function Act.queue_judgement(blackboard)
    local _, target = player_and_target(blackboard)
    local result = queue_target(blackboard, "judgement", "judgement", target, QueuePriorities.PRIMARY)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", true)
    end
    return result
end

function Act.queue_seal_of_blood(blackboard)
    local player = blackboard:get("player.object")
    local result = queue_target(blackboard, "seal_of_blood", "seal_of_blood", player, QueuePriorities.MAINTENANCE)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", false)
        blackboard:set("rotation.twist.pending_reseal", false)
    end
    return result
end

function Act.queue_seal_of_command(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "seal_of_command_aoe_maintain", "seal_of_command", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_crusader_strike(blackboard)
    local _, target = player_and_target(blackboard)
    return queue_target(blackboard, "crusader_strike", "crusader_strike", target, QueuePriorities.PRIMARY)
end

function Act.queue_consecration(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "consecration", "consecration", player, QueuePriorities.LOW)
end

function Act.queue_retribution_aura(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "retribution_aura", "retribution_aura", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_blessing_of_might(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "blessing_of_might", "blessing_of_might", player, QueuePriorities.MAINTENANCE)
end

function Act.queue_blessing_of_kings(blackboard)
    local player = blackboard:get("player.object")
    return queue_target(blackboard, "blessing_of_kings", "blessing_of_kings", player, QueuePriorities.MAINTENANCE)
end

function Act.noop()
    return Status.FAILURE
end

return Act
