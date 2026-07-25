-- kernel/intent_executors.lua
-- Where intents become packets (ADR 08 §3.2, §6.3, justified by §2.6).
--
-- ================================================================================
-- THIS IS THE ONLY FILE IN THE KERNEL THAT MAKES THE GAME DO ANYTHING
-- ================================================================================
-- Everything upstream -- rotations, the ActivityStack, the ControlBroker -- produces DESCRIPTIONS of
-- desired actions. This file is the single point where a description becomes a side effect, and it
-- is deliberately small enough to audit in one sitting.
--
-- §2.6: "`core.input.cast_target_spell` performs ZERO validation -- no range, no facing, no ready
-- check; it only sends a packet. That is exactly the gap the commit stage exists to fill."
--
-- Three things must hold before a packet leaves, and each is a NAMED gate so a refusal is
-- diagnosable rather than a silent no-op (§12's complaint about LazyBot's empty catch blocks):
--
--   1. `generation` -- a live lease authorised it            (ControlBroker, §6.1)
--   2. `gcd`        -- the global cooldown is not running     (kernel/timing.lua, §2.5)
--   3. `castable`   -- the SDK agrees range and facing are ok (§2.6)
--
-- Gate order is load-bearing: the cheap in-memory checks run before the SDK call, so a rotation
-- spamming a spell during its GCD costs a table lookup rather than an injector round-trip.
--
-- ================================================================================
-- WHY THE KERNEL LAYERS ON `spell_queue` RATHER THAN CALLING `cast_target_spell`
-- ================================================================================
-- §2.6 again, and it is the most important discovery behind this file: `spell_queue` is NOT an
-- intra-rotation ordering mechanism. It is a CROSS-PLUGIN arbitration channel that other Sylvanas
-- plugins are already queueing into, with a documented priority convention. The kernel does not own
-- the bottom of the casting stack, so it maps onto that convention (§6.3) instead of fighting it.
--
-- Two rules follow, both from §6.3, and both easy to break by accident:
--   * COLON CALL CONVENTION. Every `common/` module is `mod:fn()`. A dot call silently shifts every
--     argument by one, putting the spell id where the receiver belongs.
--   * NO FALLBACK LOGIC ON `queue_position`. If the queue misbehaves, that is a fact to surface,
--     not a condition to paper over with a retry that casts twice.
--
-- ================================================================================
-- UNIT REFERENCES, AND WHY INTENTS CANNOT CARRY HANDLES
-- ================================================================================
-- §2.7: the frozen snapshot holds VALUES, not handles -- a rotation reading `target.health_pct`
-- never sees a `game_object`. But `queue_spell_target` needs a real handle.
--
-- So an intent names its unit SYMBOLICALLY ("player", "target") and this file resolves that to a
-- live handle at commit time, one stage after the rotation emitted it. Resolution failing is a
-- REFUSAL, never a nil handed to an SDK call that "only sends a packet".
--
-- This is logged as an API gap (08a_API_GAPS.md): the vocabulary is currently two words, and a
-- rotation that wants to cast at "the add that is casting" cannot say so.

local Bands = require("kernel/bands")

local Executors = {}

--- Unit references an intent may name. Deliberately a closed set: an open one would be a string
--- pointing at unvalidated SDK surface, resolved inside the commit stage.
Executors.UNIT_PLAYER = "player"
Executors.UNIT_TARGET = "target"

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

local function resolve_player(deps)
    local om = deps.object_manager
    if not om or type(om.get_local_player) ~= "function" then return nil end
    local ok, player = pcall(om.get_local_player)
    if ok then return player end
    return nil
end

---Resolve a symbolic unit reference to a live handle.
---@return table|nil handle, boolean is_self
local function resolve_unit(deps, reference)
    local player = resolve_player(deps)
    if reference == Executors.UNIT_PLAYER then
        return player, true
    end
    if reference == Executors.UNIT_TARGET then
        if type(deps.unit_target) == "function" then
            local ok, target = pcall(deps.unit_target, player)
            if ok then return target, false end
            return nil, false
        end
        if player and type(player.get_target) == "function" then
            local ok, target = pcall(player.get_target, player)
            if ok then return target, false end
        end
        return nil, false
    end
    return nil, false
end

-- ---------------------------------------------------------------------------
-- Gates
-- ---------------------------------------------------------------------------

---The GCD gate. Only casts are subject to it; a target switch is not a spell.
local function gcd_gate(deps)
    return function(intent)
        if intent.type ~= "cast" then return true end
        local payload = intent.payload or {}
        -- Off-GCD abilities are declared by the rotation, because only it knows. Ice Block is the
        -- case that matters: gating the panic button behind a GCD it does not use makes it
        -- unreachable exactly when it is needed.
        if payload.off_gcd then return true end
        local timing = deps.timing
        if not timing then return true end
        if timing:is_gcd_ready() then return true end
        return false, "gcd_running"
    end
end

---Range and facing, asked of the SDK rather than re-derived.
---
---`is_spell_castable` is documented as "the recommended way to check if you can cast a spell", and
---it is the only thing in the SDK that knows the real range table. Re-implementing that from
---snapshot positions would be a second source of truth that drifts.
local function castable_gate(deps)
    return function(intent)
        if intent.type ~= "cast" then return true end
        local payload = intent.payload or {}
        local caster = resolve_player(deps)
        if caster == nil then return false, "no_player" end

        local unit, is_self = resolve_unit(deps, payload.unit)
        if unit == nil then return false, "unit_unresolved" end

        local helper = deps.spell_helper
        if not helper or type(helper.is_spell_castable) ~= "function" then
            -- Fail CLOSED. An absent validator is not permission; §2.6 exists because the raw cast
            -- call validates nothing, so proceeding without the check is the exact failure mode.
            return false, "no_castable_check"
        end

        -- A self-cast has no meaningful facing or range, so both checks are skipped -- otherwise
        -- every self-buff would be rejected for not facing itself.
        local ok, castable = pcall(
            helper.is_spell_castable, payload.spell_id, caster, unit, is_self, is_self)
        if not ok then return false, "castable_check_error" end
        -- A LITERAL `true`, not merely truthy. `shared/spell_helper.lua` returns the string
        -- `SpellHelper.UNKNOWN` when the spell-book helper is unresolved, precisely so callers can
        -- distinguish "no" from "cannot say" -- and a truthy string sailing through `if not castable`
        -- would turn "cannot say" into permission to cast at anything, from anywhere.
        if castable ~= true then return false, "not_castable" end
        return true
    end
end

-- ---------------------------------------------------------------------------
-- Executors
-- ---------------------------------------------------------------------------

local function cast_executor(deps)
    return function(intent)
        local payload = intent.payload or {}
        local unit = resolve_unit(deps, payload.unit)
        if unit == nil then return false, "unit_unresolved" end

        local sq = deps.spell_queue
        if not sq or type(sq.queue_spell_target) ~= "function" then
            return false, "no_spell_queue"
        end

        local priority = Bands.spell_queue_priority(intent.band)
        -- COLON. See the header: a dot call here shifts every argument by one.
        local ok, queued = pcall(function()
            return sq:queue_spell_target(payload.spell_id, unit, priority, intent.owner)
        end)
        if not ok then return false, "spell_queue_error" end
        -- No fallback logic, no retry, no `queue_position` inspection (§6.3). The queue's answer is
        -- the answer.
        if queued == false then return false, "spell_queue_refused" end

        -- Record the cast on the SAME axis the estimate reads (game_time ms). This is what makes
        -- `gcd_remaining_est` an estimate of anything at all: the kernel only knows about casts it
        -- committed itself.
        if deps.timing and not payload.off_gcd then
            deps.timing:note_cast(payload.spell_id)
        end
        return true
    end
end

local function target_executor(deps)
    return function(intent)
        local payload = intent.payload or {}
        local unit = resolve_unit(deps, payload.unit)
        if unit == nil then return false, "unit_unresolved" end

        local input = deps.input
        if not input or type(input.set_target) ~= "function" then return false, "no_input" end
        local ok, result = pcall(input.set_target, unit)
        if not ok then return false, "set_target_error" end
        if result == false then return false, "set_target_refused" end
        return true
    end
end

-- ---------------------------------------------------------------------------
-- Installation
-- ---------------------------------------------------------------------------

---Register the gates and executors on an IntentQueue.
---
---Everything the injector provides is INJECTED rather than required at the top of this file, for
---the same reason the IziBridge require is guarded: `common/modules/spell_queue` does not exist
---outside the game, and a top-level require would make the whole kernel unloadable offline -- which
---would mean none of this could be tested, which is how a file that sends packets ends up untested.
---@param deps table { intent_queue, timing, spell_queue, object_manager, spell_helper, input,
---                    unit_target? }
function Executors.install(deps)
    local queue = deps.intent_queue
    if not queue then return false, "no_intent_queue" end

    -- Order matters: cheap in-memory checks before the SDK round-trip.
    queue:add_gate("gcd", gcd_gate(deps))
    queue:add_gate("castable", castable_gate(deps))

    queue:register_executor("cast", cast_executor(deps))
    queue:register_executor("target", target_executor(deps))
    return true
end

return Executors
