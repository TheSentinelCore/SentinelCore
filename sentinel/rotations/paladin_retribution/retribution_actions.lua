local API = require("rotations/paladin_retribution/sentinel_api")
local H = require("rotations/paladin_retribution/support")

local QueuePriorities = H.QueuePriorities

-- Resolved live. `H.status()` reads `API.bt.Status`, so capturing it at load time would pin nil
-- forever whenever this file loads before the kernel publishes (ADR 08 §2.4).
local Status = setmetatable({}, { __index = function(_, k)
    local s = H.status()
    return s and s[k] or nil
end })

local Act = {}

--- AoE placement, through the kernel's spell service rather than `shared/aoe_helper`.
---
--- `Sentinel.spells:find_aoe_position` wraps the same `spell_prediction.find_optimal_position` the
--- old helper reached for, and returns `(nil, 0)` on every failure -- which is exactly what the
--- caller below already treats as "no good position". Signature and failure shape are unchanged; a
--- lazy `require("shared/aoe_helper")` would be a cross-package require the audit refuses.
local AoeHelper = {
    find_optimal_position = function(spell_id, range, min_targets, radius)
        local s = API.spells
        if not s then return nil, 0 end
        return s:find_aoe_position(spell_id, range, min_targets, radius)
    end,
}

function Act.queue_avenging_wrath(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "avenging_wrath", "avenging_wrath", player, QueuePriorities.DEFAULT, { fast = true })
end

function Act.queue_hammer_of_justice(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "hammer_of_justice_interrupt", "hammer_of_justice", target, QueuePriorities.INTERRUPT)
end

function Act.queue_seal_of_command_rank1(blackboard)
    local player = blackboard:get("player.object")
    local result = H.queue_target(blackboard, "seal_twist_prime_soc_r1", "seal_of_command", player, QueuePriorities.DEFAULT, nil, "lowest")
    if result == Status.SUCCESS then
        blackboard:set("rotation.twist.pending_reseal", true)
        blackboard:set("rotation.twist.last_prime_at_ms", blackboard:get("system.now_ms", 0))
    end
    return result
end

function Act.queue_hammer_of_wrath(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "hammer_of_wrath_execute", "hammer_of_wrath", target, QueuePriorities.DEFAULT)
end

function Act.queue_judgement(blackboard)
    local _, target = H.player_and_target(blackboard)
    local result = H.queue_target(blackboard, "judgement", "judgement", target, QueuePriorities.DEFAULT)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", true)
    end
    return result
end

function Act.queue_seal_of_blood(blackboard)
    local player = blackboard:get("player.object")
    local result = H.queue_target(blackboard, "seal_of_blood", "seal_of_blood", player, QueuePriorities.DEFAULT)
    if result == Status.SUCCESS then
        blackboard:set("rotation.after_judgement_reseal", false)
        blackboard:set("rotation.twist.pending_reseal", false)
    end
    return result
end

function Act.queue_seal_of_command(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "seal_of_command_aoe_maintain", "seal_of_command", player, QueuePriorities.DEFAULT)
end

function Act.queue_seal_of_righteousness(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "seal_of_righteousness", "seal_of_righteousness", player, QueuePriorities.DEFAULT)
end

---Queue whichever seal the context builder resolved as castable.
---
---`rotation.primary_seal` is level-aware (blood > command > righteousness, filtered
---by what the spell book actually knows), so this is the one entry point that works
---for a Paladin at any level from 3 to 70. Falls back to the in-combat desired seal
---when no primary is published.
function Act.queue_desired_seal(blackboard)
    local seal = blackboard:get("rotation.primary_seal")
        or blackboard:get("rotation.desired_seal")
    if seal == "blood" then
        return Act.queue_seal_of_blood(blackboard)
    elseif seal == "command" then
        return Act.queue_seal_of_command(blackboard)
    elseif seal == "righteousness" then
        return Act.queue_seal_of_righteousness(blackboard)
    end
    return Status.FAILURE
end

function Act.queue_crusader_strike(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "crusader_strike", "crusader_strike", target, QueuePriorities.DEFAULT)
end

function Act.queue_consecration(blackboard)
    -- Use AOE helper to find optimal position for Consecration to hit maximum enemies
    local spell_id = H.spell_id_for(blackboard, "consecration")
    if not spell_id then
        -- Fallback to original behavior if spell ID not found
        local player = blackboard:get("player.object")
        return H.queue_target(blackboard, "consecration", "consecration", player, QueuePriorities.DEFAULT)
    end

    -- Try to get optimal position using AOE helper (consecration is centered on caster, but we can move to optimize)
    local optimal_pos, hit_count = AoeHelper.find_optimal_position(
        spell_id,
        0,    -- Consecration is centered on caster, so we don't range from target
        2,    -- Minimum targets for AOE (try to hit at least 2 enemies)
        8     -- Consecration radius
    )

    -- If we found a good position with enough targets, use it
    if optimal_pos and hit_count >= 2 then
        return H.queue_position(blackboard, "consecration", "consecration", optimal_pos, QueuePriorities.DEFAULT)
    end

    -- Fallback to casting on self (original behavior)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "consecration", "consecration", player, QueuePriorities.DEFAULT)
end

function Act.queue_retribution_aura(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "retribution_aura", "retribution_aura", player, QueuePriorities.DEFAULT)
end

function Act.queue_blessing_of_might(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "blessing_of_might", "blessing_of_might", player, QueuePriorities.DEFAULT)
end

function Act.queue_blessing_of_kings(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "blessing_of_kings", "blessing_of_kings", player, QueuePriorities.DEFAULT)
end

---Melee fallback: signals that no spell action is available but a valid
---target exists. Returns SUCCESS so the GCD tree doesn't signal "no legal
---action" -- the chase controller handles movement and WoW auto-attack
---deals damage. Also starts auto-attack if not already attacking and in
---melee range (spell ID 6603 = generic Attack ability).
---Returns RUNNING if no target yet (wait for target), FAILURE if target dead.
---
--- ================================================================================
--- THE ONE DIRECT SDK CALL LEFT IN THIS PACKAGE, AND WHY IT IS STILL HERE
--- ================================================================================
--- `core.input.cast_target_spell(6603, target)` starts the auto-attack swing. It is ledgered in
--- `tests/kernel/test_plugin_core_access_audit.lua` rather than converted, because THERE IS NO
--- INTENT TYPE FOR STARTING AN AUTO-ATTACK. The two candidate conversions are both behaviour
--- changes, not refactors:
---
---   * A `cast` intent carrying `spell_id = 6603` would route the swing through `spell_queue`
---     (a different SDK verb), through the castable gate, and through the GCD gate. Auto-attack is
---     none of those things: it is a stance, not a spell cast, and gating it on the global cooldown
---     would leave the Paladin standing still for the one action that works when nothing else does.
---   * A new `auto_attack` intent type is a KERNEL change, not a rotation change, and it belongs in
---     the deliverable that adds it -- with its own channel, gate and tests -- rather than being
---     invented inside a port whose whole contract is that behaviour does not move.
---
--- So this is an admitted gap with a name, which is what the ledger is for. The mage carries the
--- same shape for MOVEMENT (`kite_controller`'s `core.input.look_at` / `move_forward_start`) for
--- the same reason: the intent vocabulary does not cover it yet.
function Act.melee_fallback(blackboard)
    local player_obj, target = H.player_and_target(blackboard)
    if not target then
        -- No target yet — keep tree running so it doesn't trigger COOLDOWN->disengage
        return Status.RUNNING
    end
    local ok_dead, dead = pcall(target.is_dead, target)
    if ok_dead and dead == true then
        return Status.FAILURE
    end
    -- Start auto-attack if not already auto-attacking (spell 6603 = Attack)
    if player_obj and type(player_obj.is_auto_attacking) == "function" then
        local ok_aa, is_aa = pcall(player_obj.is_auto_attacking, player_obj)
        if (not ok_aa or not is_aa) and core and core.input
            and type(core.input.cast_target_spell) == "function" then
            pcall(core.input.cast_target_spell, 6603, target)
        end
    end
    -- Target is alive and valid — always SUCCESS, regardless of range.
    -- The chase controller is responsible for closing the gap. Returning
    -- FAILURE due to range would make the GCD tree return FAILURE,
    -- transition to COOLDOWN, and disengage after 2.5s — which is wrong
    -- when the chase is actively closing the gap.
    return Status.SUCCESS
end

function Act.noop()
    return Status.FAILURE
end

return Act
