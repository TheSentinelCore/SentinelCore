local API = require("rotations/paladin_retribution/sentinel_api")
local H = require("rotations/paladin_retribution/support")

-- Resolved at CALL time, never captured at load time: `_G.Sentinel` may not exist yet when this
-- file loads (ADR 08 §2.4 -- the getter fixes reads, the queue fixes registration).
local AuraCatalog = setmetatable({}, { __index = function(_, k)
    local c = API.catalogs
    return c and c.aura and c.aura[k] or nil
end })

local SpellHelper = {
    -- FAIL OPEN on "cannot say", preserving the ported behaviour EXACTLY: the original called
    -- `shared/spell_helper.is_spell_castable` directly and tested `if not castable`, and that
    -- helper returns the truthy string `UNKNOWN` when the spell-book helper is unresolved -- so
    -- "cannot say" already read as castable. `Spells:castability` is the tri-state version of the
    -- same question, so `~= false` reproduces the old answer for all three cases rather than
    -- tightening it. A condition that went false on an unresolved helper would stop the Paladin
    -- casting anything at all; the commit gate is the real check now.
    is_spell_castable = function(id, src, dst)
        local s = API.spells
        if s == nil then return true end
        return s:castability(id, src, dst) ~= false
    end,
    -- Fail open on "cannot say", for the same reason as `is_spell_castable` above.
    is_spell_in_los = function(id, src, dst)
        local s = API.spells
        if s == nil then return true end
        return s:los_state(id, src, dst) ~= false
    end,
}

local Cond = {}

--- The kernel's forecast service, RESOLVED AT CALL TIME.
---
--- Phase 4d D1: this used to be `blackboard:get("module.combat.izi_bridge")`, then a direct
--- `_G.Sentinel.forecast` read. It is the same resolution either way -- `sentinel_api` IS the read
--- of `_G.Sentinel` -- but routing it through the shim keeps this package's coupling to the kernel
--- in the one file that is supposed to hold it.
local function forecast()
    return API.forecast
end

-- ---------------------------------------------------------------------------
-- Snapshot-backed health
-- ---------------------------------------------------------------------------
-- The rotation's only consumer of `Sentinel.cond`, and the only place a `Truth` crosses into this
-- package. Copied from `rotations/mage_frost/frost_conditions.lua`, where the shape was worked out.
--
-- WHAT MOVED, AND WHAT DID NOT. `health_above` is the ONE condition in this file with an equivalent
-- kernel predicate whose data is in the snapshot's HOT tier. Everything else stays on the
-- blackboard, and the list of why is worth stating rather than leaving to be re-derived:
--
--   * `mana_above`      -- there is no `power_above` predicate. Only `power_below` is ported.
--   * `in_melee` / `in_judgement_range` -- `cond.target_within` exists, and it reads
--     `target.position` from a tier captured off `player:get_target()` (snapshot_source.lua:132).
--     This rotation aims at `combat.target or player.target`, and `combat.target` is chosen by the
--     combat module's target strategy -- routinely a DIFFERENT unit from the client's target.
--     Converting would silently re-aim two range gates at whatever the client happens to have
--     selected. That is a behaviour change wearing a refactor's clothes.
--   * `target_valid`    -- `cond.has_target` under TreatFalse is fail-CLOSED; the ported version
--     returns true when the `is_dead` read FAILS (`not ok_dead or dead ~= true`), i.e. fail-OPEN.
--     Converting flips the polarity of the gate that guards every offensive priority.
--   * `target_execute`'s HP fallback -- `cond.target_health_below` exists, but the forecast branch
--     above it cannot move, and splitting one condition across two data sources buys nothing.
--   * every `AuraCatalog.has_any*` check, every `rotation.*` key, `twist_window_open`,
--     `enemy_count_at_least`, `aoe_mode`, `burst_*`, `preferred_blessing_is_kings`,
--     `target_casting_interruptible`, `spell_ready`, `gcd_ready` -- no aura, cooldown, spell-book,
--     swing, hostile-census or target-cast tier exists in the snapshot. ADR §8.4.1 measured this:
--     42 of 65 combinators are blocked on warm/cold tiers that have not been built.
--
-- WHY `health_above` IS WORTH MOVING ANYWAY. It gates Avenging Wrath, the profile's one burst
-- cooldown, and the blackboard version read `H.num(blackboard:get("player.health_pct", 0))` -- so
-- an unreadable health read as 0%. For `health_above` that default happens to fail CLOSED, which is
-- why this conversion changes no answer in either the readable or the unreadable case; what it buys
-- is that the reading now comes from the tick's frozen snapshot rather than from whenever the
-- sensor last wrote the key, and the "I could not read it" case is named instead of impersonated by
-- a plausible-looking zero (ADR 07 §5.1.2).

---Resolve one kernel predicate against the tick's frozen snapshot.
---
---Reads `Sentinel.snapshot` and `Sentinel.cond` at CALL time through the plugin's API shim, so a
---condition built before the kernel published still works once it has.
---
---`predicates[name]` is indexed OUTSIDE the pcall on purpose: `Cond.bind` returns a namespace whose
---`__index` RAISES on an unknown key, so a typo'd predicate name throws here rather than being
---swallowed into a silent `false`.
---@param name string a predicate on `Sentinel.cond`
---@return boolean
local function snapshot_predicate(name, ...)
    local snapshot, cond, Truth = API.snapshot, API.cond, API.Truth
    -- No kernel, or no snapshot yet, is NOT a reading. Answering false here is the same decision
    -- `TreatFalse` makes below, taken one step earlier because there is nothing to bind against.
    if snapshot == nil or cond == nil or Truth == nil then return false end
    local ok, predicates = pcall(cond.bind, snapshot)
    if not ok then return false end
    local answered, verdict = pcall(predicates[name], ...)
    if not answered then return false end
    return Truth.resolve(verdict, Truth.Policy.TreatFalse) == true
end

function Cond.target_valid(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = H.safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

function Cond.in_melee(blackboard)
    local player = blackboard:get("player.position")
    local _, target = H.player_and_target(blackboard)
    local ok_target_pos, target_pos = H.safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return H.distance(player, target_pos) <= 5.0
end

function Cond.in_judgement_range(blackboard)
    local player = blackboard:get("player.position")
    local _, target = H.player_and_target(blackboard)
    local ok_target_pos, target_pos = H.safe_call(target, "get_position")
    if type(player) ~= "table" or not ok_target_pos then
        return false
    end
    return H.distance(player, target_pos) <= 10.0
end

function Cond.active_seal_present(blackboard)
    return blackboard:get("rotation.active_seal") ~= nil
end

function Cond.gcd_ready(blackboard)
    local cooldowns = blackboard:get("module.combat.cooldowns")
    return cooldowns and cooldowns:is_gcd_ready(blackboard:get("system.now_ms", 0)) or false
end

function Cond.spell_ready(spell_key, mode, cast_target)
    return function(blackboard)
        local player, target = H.player_and_target(blackboard)
        local spell_id = H.spell_id_for(blackboard, spell_key, mode)
        local cooldowns = blackboard:get("module.combat.cooldowns")
        if not spell_id or not cooldowns or not cooldowns:spell_ready(spell_id) then
            return false
        end
        local source = player
        local dest = cast_target == "self" and player or (target or player)
        if not SpellHelper.is_spell_castable(spell_id, source, dest) then
            return false
        end
        -- Check line of sight for targeted spells (not self-cast)
        if cast_target ~= "self" and dest and dest ~= source then
            if not SpellHelper.is_spell_in_los(spell_id, source, dest) then
                return false
            end
        end
        return true
    end
end

function Cond.twist_enabled(blackboard)
    return blackboard:get("rotation.twist.enabled", false) == true
        and blackboard:get("rotation.desired_seal", "blood") == "blood"
        and blackboard:get("rotation.active_seal") == "blood"
end

function Cond.twist_window_open(blackboard)
    local remaining_ms = H.num(blackboard:get("combat.swing.remaining_ms", 99999))
    local twist_window_ms = H.num(blackboard:get("module.combat.twist_window_ms", 350))
    return remaining_ms > 0 and remaining_ms <= twist_window_ms
end

function Cond.blood_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "blood"
end

function Cond.command_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "command"
end

function Cond.righteousness_not_active(blackboard)
    return blackboard:get("rotation.active_seal") ~= "righteousness"
end

function Cond.target_execute(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end

    -- Use TTD if available for more reliable execute detection
    local f = forecast()
    if f then
        local ttd = f:time_to_die(target)
        if ttd and ttd < 3.0 then
            return true
        end
    end

    -- Fallback to HP% check
    local ok_hp, hp_pct = H.safe_call(target, "get_health_percentage")
    return ok_hp and H.num(hp_pct) <= 0.20
end

function Cond.not_twisting(blackboard)
    return blackboard:get("rotation.twist.pending_reseal", false) ~= true
end

function Cond.aoe_mode(blackboard)
    return H.num(blackboard:get("combat.enemy_count_10yd", 0)) >= 2
end

function Cond.burst_enabled(blackboard)
    return blackboard:get("module.combat.enable_burst", true) ~= false
end

function Cond.burst_context(blackboard)
    return blackboard:get("combat.burst_context", false) == true
end

function Cond.in_combat_context(blackboard)
    return blackboard:get("player.in_combat", false) == true
        or tostring(blackboard:get("combat.state", "IDLE") or "IDLE") ~= "IDLE"
end

function Cond.desired_seal_is_blood(blackboard)
    return blackboard:get("rotation.desired_seal") == "blood"
end

function Cond.desired_seal_is_command(blackboard)
    return blackboard:get("rotation.desired_seal") == "command"
end

---Player health strictly above `threshold`, read from the tick's FROZEN SNAPSHOT.
---
---See the section header above. The blackboard version was
---`H.num(blackboard:get("player.health_pct", 0)) > threshold`; both agree in every case, including
---the unreadable one, which is why this is a route change rather than a behaviour change.
function Cond.health_above(threshold)
    return function()
        return snapshot_predicate("health_above", threshold)
    end
end

function Cond.mana_above(threshold)
    return function(blackboard)
        return H.num(blackboard:get("player.mana_pct", 0)) > threshold
    end
end

function Cond.enemy_count_at_least(count)
    return function(blackboard)
        return H.num(blackboard:get("combat.enemy_count_10yd", 0)) >= count
    end
end

function Cond.after_judgement_reseal(blackboard)
    return blackboard:get("rotation.after_judgement_reseal", false) == true
end

function Cond.twist_reseal_pending(blackboard)
    return blackboard:get("rotation.twist.pending_reseal", false) == true
        and blackboard:get("rotation.twist.swing_rolled", false) == true
end

function Cond.target_casting_interruptible(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_casting, casting = H.safe_call(target, "is_casting_spell")
    local ok_channel, channeling = H.safe_call(target, "is_channelling_spell")
    if (ok_casting and casting == true) or (ok_channel and channeling == true) then
        local ok_interruptible, interruptible = H.safe_call(target, "is_active_spell_interruptable")
        return not ok_interruptible or interruptible == true
    end
    return false
end

function Cond.preferred_blessing_is_kings(blackboard)
    return blackboard:get("module.combat.preferred_blessing", "might") == "kings"
end

function Cond.missing_retribution_aura(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.retribution_aura_ranks)
end

function Cond.missing_might(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.blessing_of_might_ranks)
end

function Cond.missing_kings(blackboard)
    local player = blackboard:get("player.object")
    return not AuraCatalog.has_any(player, AuraCatalog.blessing_of_kings)
end

---True when no seal at all is up. Any seal satisfies the baseline -- a level-3
---Paladin only has Righteousness, and refusing it would leave the character
---permanently sealless, which in turn kills judgement (active_seal_present).
function Cond.baseline_seal_missing(blackboard)
    return blackboard:get("rotation.active_seal") == nil
end

-- Maps the seal names published on the blackboard to spell catalog keys.
local SEAL_SPELL_KEYS = {
    blood = "seal_of_blood",
    command = "seal_of_command",
    righteousness = "seal_of_righteousness",
}

---True when the level-aware primary seal is known, off cooldown, and castable.
---Replaces the hardcoded spell_ready("seal_of_blood") gate, which could never
---pass below level 64 and so stranded the whole levelling rotation.
function Cond.primary_seal_castable(blackboard)
    local seal = blackboard:get("rotation.primary_seal")
        or blackboard:get("rotation.desired_seal")
    local spell_key = SEAL_SPELL_KEYS[seal]
    if not spell_key then
        return false
    end
    return Cond.spell_ready(spell_key, nil, "self")(blackboard)
end

---True when the seal the rotation wants is not the one currently up.
function Cond.primary_seal_not_active(blackboard)
    local seal = blackboard:get("rotation.primary_seal")
        or blackboard:get("rotation.desired_seal")
    return seal ~= nil and blackboard:get("rotation.active_seal") ~= seal
end

return Cond
