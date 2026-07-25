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
--
-- The escape hatch from that closed vocabulary is a GUID, and a guid is a value with no expiry --
-- so it carries a generation stamp minted by `kernel/units.lua` and re-checked here. See
-- `resolve_unit_by_guid` below for what that check does and does not prove.

local Bands = require("kernel/bands")
local MovementRelease = require("kernel/movement_release")
-- For `generation_of` and the two payload field names. The re-check MUST read the tick the same way
-- the mint wrote it, and a second local reading here is exactly how the two drift into
-- always-equal or never-equal.
local Units = require("kernel/units")

local Executors = {}

--- Unit references an intent may name. Deliberately a closed set: an open one would be a string
--- pointing at unvalidated SDK surface, resolved inside the commit stage.
Executors.UNIT_PLAYER = "player"
Executors.UNIT_TARGET = "target"
Executors.UNIT_PET = "pet"

--- ONE INTENT TYPE PER CHANNEL (ADR 08 §3.2).
---
--- An intent is authorised by exactly ONE lease, because the commit stage re-checks the
--- generation of the lease that produced it (§6.1). An intent spanning two channels would have
--- no single authorising lease, so there would be nothing well-defined for that check to
--- validate against -- and FACING and MOVEMENT are deliberately separate channels so a rotation
--- can face while an activity moves (§6.1's kiting case).
---
--- This table is the declaration, and tests assert against it. It is not consulted at commit
--- time: the lease a plugin holds is what actually authorises, and duplicating that decision
--- here would be a second authority that drifts.
Executors.CHANNEL_FOR = {
    cast = "CASTING",
    target = "TARGETING",
    pet_command = "PET",
    use_item = "ITEMS",
    face = "FACING",
    move = "MOVEMENT",
}

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

---Resolve the player's pet to a live handle.
---
---Separate from `resolve_unit` because a pet is not a target: it is reached THROUGH the player
---(`get_pet`), and its liveness is a precondition the PET gate checks rather than a property
---of the reference.
local function resolve_pet(deps)
    local player = resolve_player(deps)
    if player == nil or type(player.get_pet) ~= "function" then return nil end
    local ok, pet = pcall(player.get_pet, player)
    if not ok or not pet then return nil end
    return pet
end

---Resolve a symbolic unit reference to a live handle.
---@return table|nil handle, boolean is_self
local function resolve_unit(deps, reference)
    local player = resolve_player(deps)
    if reference == Executors.UNIT_PLAYER then
        return player, true
    end
    if reference == Executors.UNIT_PET then
        return resolve_pet(deps), false
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

---Resolve a unit named by GUID.
---
---The escape hatch from the closed symbolic vocabulary, added in Phase 4c when re-measuring the
---frost cast path found two sites naming a unit that is neither player, target nor pet -- Polymorph's
---secondary enemy and `combat.low_health_add`. A guid is a VALUE, so it may ride in a payload
---without violating §2.7, and it is resolved HERE, at commit, in the tick that uses it: exactly the
---"guard before every use" discipline the SDK asks for. A handle captured at submit time and stored
---for one stage is the unsound artefact §2.7 forbids.
local function resolve_unit_by_guid(deps, guid)
    local om = deps.object_manager
    if not om or type(om.get_object_from_guid) ~= "function" then return nil end
    local ok, unit = pcall(om.get_object_from_guid, guid)
    if not ok then return nil end
    return unit
end

---Re-check the generation stamp a guid ref carries (Phase 4d D5).
---
---================================================================================
---WHY A GUID NEEDS A STAMP WHEN THE LEASE ALREADY HAS A GENERATION
---================================================================================
---The lease generation closes the REVOCATION race: an intent emitted under a lease that died later
---in the same tick does not commit. It cannot close the STALENESS one, and not by oversight -- a
---lease is measured in ticks and is SUPPOSED to span many of them, so an intent submitted five
---ticks after the grant passes the lease check by design. A guid cached in tick N and submitted in
---tick N+5 rides that entirely legitimate lease while aiming by reasoning five ticks old.
---
---So the ref carries its own generation, minted against the snapshot the caller reasoned against
---and compared here against the snapshot COMMIT is running under. `kernel/units.lua` owns both the
---mint and the reading of the tick; this is only the comparison.
---
---Three distinct refusals, because they are three different bugs in three different places:
---  * `unstamped_unit_ref` -- the caller built the payload by hand instead of minting. FAIL CLOSED,
---    for the reason `no_castable_check` does: a stamp that may be omitted is never enforced, and
---    grandfathering the pre-4d shape would leave the hole open under a new name.
---  * `no_tick_index`      -- the snapshot cannot say what tick it is, so the check cannot run.
---    Also closed. Treating an unanswerable tick as "close enough" would evaporate the check
---    wherever the snapshot is a stub, which is precisely where nobody is looking.
---  * `stale_unit_ref`     -- minted in another tick. The case the deliverable exists for.
---
---================================================================================
---WHAT THIS CHECK CANNOT SEE
---================================================================================
---It proves the ref was minted THIS tick, and nothing else:
---  * NOT that the unit still exists -- the mob can die between ACT and COMMIT in the same tick.
---    `unit_unresolved` below is the separate refusal that speaks to that, and it is a resolve
---    rather than a liveness proof even then.
---  * NOT that the unit is in range or in front of the caster. That is the castable gate, asked of
---    the SDK, and it runs after this.
---  * NOT that the unit is the same entity the rotation reasoned about. A guid is stable; the world
---    is not. Fear, phasing, mind control and CC all leave the guid untouched and the reasoning
---    void, and this check reads such a ref as fresh -- because it IS fresh.
---@return true|nil ok, string|nil reason
local function check_unit_ref_generation(payload, snapshot)
    local stamped = payload[Units.REF_TICK_FIELD]
    if type(stamped) ~= "number" then return nil, "unstamped_unit_ref" end
    local now = Units.generation_of(snapshot)
    if now == nil then return nil, "no_tick_index" end
    if stamped ~= now then return nil, "stale_unit_ref" end
    return true
end

---A world position: three numbers, all present.
local function is_point(value)
    return type(value) == "table"
        and type(value.x) == "number"
        and type(value.y) == "number"
        and type(value.z) == "number"
end

---What a `cast` intent is aimed at, and how it must be sent.
---
---A cast names EXACTLY ONE destination. Naming two is a caller bug and is refused rather than
---resolved by precedence, because a silent precedence rule means the site that got it wrong keeps
---working while aiming somewhere the author did not choose.
---
---`unit_ref_tick` is NOT counted as naming a destination -- it is the stamp on `unit_guid`, not a
---fourth way to name a unit, and counting it would make every correctly minted ref look
---overspecified.
---@param snapshot table|nil the snapshot COMMIT is running under -- the authority the guid ref's
---       generation stamp is re-checked against
---@return table|nil resolved { kind = "unit"|"point", unit?, is_self?, point? }
---@return string|nil reason
local function resolve_cast_destination(deps, payload, snapshot)
    local named = 0
    if payload.unit ~= nil then named = named + 1 end
    if payload.unit_guid ~= nil then named = named + 1 end
    if payload.point ~= nil then named = named + 1 end
    if named == 0 then return nil, "no_cast_destination" end
    if named > 1 then return nil, "overspecified_cast_destination" end

    if payload.point ~= nil then
        if not is_point(payload.point) then return nil, "malformed_point" end
        return { kind = "point", point = payload.point }
    end

    if payload.unit_guid ~= nil then
        -- BEFORE the object-manager round-trip: a stale ref is refused on a table lookup rather
        -- than on an SDK call, the same cheap-checks-first ordering the gates themselves use.
        local fresh, stale_reason = check_unit_ref_generation(payload, snapshot)
        if not fresh then return nil, stale_reason end

        local unit = resolve_unit_by_guid(deps, payload.unit_guid)
        if unit == nil then return nil, "unit_unresolved" end
        -- SELF-NESS IS THE KERNEL'S CALL, not the caller's. A self-buff addressed by guid still has
        -- no facing or range to check, and a plugin could only work that out by reading
        -- `player.object` off the blackboard -- a raw handle read the namespace audit counts, made
        -- to answer a question the executor is already holding the player to answer.
        --
        -- Compared by GUID rather than by table identity: `get_object_from_guid` is not documented
        -- to hand back the same pointer `get_local_player` did, so `==` would silently report
        -- "not self" for the player.
        local player = resolve_player(deps)
        local player_guid = nil
        if player ~= nil and type(player.get_guid) == "function" then
            local ok, guid = pcall(player.get_guid, player)
            if ok then player_guid = guid end
        end
        return {
            kind = "unit",
            unit = unit,
            is_self = player_guid ~= nil and player_guid == payload.unit_guid,
        }
    end

    local unit, is_self = resolve_unit(deps, payload.unit)
    if unit == nil then return nil, "unit_unresolved" end
    return { kind = "unit", unit = unit, is_self = is_self }
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
    -- The snapshot is the SECOND argument `IntentQueue:commit` hands every gate. It is taken here
    -- rather than injected because it is per-TICK, not per-app: a captured one would be the stale
    -- reasoning this gate now refuses.
    return function(intent, snapshot)
        if intent.type ~= "cast" then return true end
        local payload = intent.payload or {}
        local caster = resolve_player(deps)
        if caster == nil then return false, "no_player" end

        local destination, reason = resolve_cast_destination(deps, payload, snapshot)
        if destination == nil then return false, reason end

        local helper = deps.spell_helper
        if not helper or type(helper.is_spell_castable) ~= "function" then
            -- Fail CLOSED. An absent validator is not permission; §2.6 exists because the raw cast
            -- call validates nothing, so proceeding without the check is the exact failure mode.
            return false, "no_castable_check"
        end

        -- A GROUND-TARGETED cast is asked the only question the SDK can answer about it. It has no
        -- target unit, and `is_spell_castable` takes one -- so the caster stands in for the unit
        -- and BOTH facing and range are skipped. That reduces the check to "do I know this spell,
        -- and is it off cooldown".
        --
        -- STATED LIMIT: the kernel does NOT verify that the point is in range. Nothing in the SDK
        -- answers that through this call, and a gate that appeared to check it would be trusted for
        -- something it never did. The rotation picks the point; the spell queue's own refusal is the
        -- backstop.
        local unit, skip_facing, skip_range
        if destination.kind == "point" then
            unit, skip_facing, skip_range = caster, true, true
        else
            -- A self-cast has no meaningful facing or range, so both checks are skipped --
            -- otherwise every self-buff would be rejected for not facing itself.
            unit = destination.unit
            skip_facing, skip_range = destination.is_self, destination.is_self
        end

        local ok, castable = pcall(
            helper.is_spell_castable, payload.spell_id, caster, unit, skip_facing, skip_range)
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
-- Gates for the Phase 4b intent types
-- ---------------------------------------------------------------------------
--
-- EACH TYPE GETS ITS OWN GATE. `use_item` asking the player about a bag item's cooldown is not
-- the same check as `cast` asking the spell book about a spell's, even though the two rhyme.
-- A gate shared between them would have to weaken to the union of what both can verify, which
-- means verifying neither properly.
--
-- A THIN GATE IS HONEST. `face` can confirm that a point is well-formed and nothing more --
-- the kernel does not know where the character may legally look. Inventing a check it cannot
-- perform would be worse than stating the limit, because the next reader would trust it.

-- `is_point` is defined once, up with cast-destination resolution: `face` and a ground-targeted
-- `cast` ask the same question of the same shape, and two copies is how the two answers drift.

local function face_gate()
    return function(intent)
        if intent.type ~= "face" then return true end
        local payload = intent.payload or {}
        if not is_point(payload.point) then return false, "malformed_point" end
        return true
    end
end

---MOVEMENT. Validates the vocabulary WITHOUT storing it -- a gate that mutated state would
---leave a desire behind on an intent a later gate went on to refuse.
local function move_gate()
    return function(intent)
        if intent.type ~= "move" then return true end
        local payload = intent.payload or {}

        if payload.stop == true then return true end
        if type(payload.keys) ~= "table" then return false, "move_states_nothing" end

        local any = false
        for key, wanted in pairs(payload.keys) do
            if not MovementRelease.is_movement_key(key) then return false, "unknown_movement_key" end
            if wanted then any = true end
        end
        -- `keys = {}` and `keys = { move_forward = false }` are a stop expressed by omission.
        -- Saying so explicitly costs nothing and removes the ambiguity.
        if not any then return false, "move_states_nothing" end
        return true
    end
end

---ITEMS. Fails CLOSED on a missing validator, for the reason `no_castable_check` does: an
---absent check is not permission. The reasons are distinct so a diagnostic can tell "you do not
---have it" apart from "I could not ask".
local function item_gate(deps)
    return function(intent)
        if intent.type ~= "use_item" then return true end
        local payload = intent.payload or {}
        if type(payload.item_id) ~= "number" then return false, "missing_item_id" end

        local player = resolve_player(deps)
        if player == nil then return false, "no_player" end

        if type(player.has_item) ~= "function" then return false, "no_item_check" end
        local ok, present = pcall(player.has_item, player, payload.item_id)
        if not ok then return false, "item_check_error" end
        if present ~= true then return false, "item_absent" end

        -- The SDK knows the real remaining cooldown. The converted code tracked a hard-coded
        -- two minutes on the blackboard instead, which is a second source of truth for a number
        -- the client already owns -- and the two drift the moment a trinket shares the cooldown.
        if type(player.get_item_cooldown) ~= "function" then return false, "no_cooldown_check" end
        local ok_cd, remaining = pcall(player.get_item_cooldown, player, payload.item_id)
        if not ok_cd then return false, "cooldown_check_error" end
        if type(remaining) == "number" and remaining > 0 then return false, "item_on_cooldown" end
        return true
    end
end

--- The commands a pet may be given. Closed, like the unit vocabulary and for the same reason.
local PET_COMMANDS = {
    attack = true,
    cast = true,
    passive = true,
    follow = true,
}

---PET. Validates what is READABLE: the pet exists and is alive.
---
---ADR 08's taxonomy also lists "the pet's own cooldown" and "pet range". Neither is exposed --
---there is no per-pet cooldown or range query anywhere in the SDK docs -- so this gate does not
---pretend to check them. A refusal that named a check the kernel never performed would be a
---lie that outlives whoever wrote it. Logged in 08a_API_GAPS.md instead.
local function pet_gate(deps)
    return function(intent)
        if intent.type ~= "pet_command" then return true end
        local payload = intent.payload or {}
        if not PET_COMMANDS[payload.command] then return false, "unknown_pet_command" end

        local pet = resolve_pet(deps)
        if pet == nil then return false, "no_pet" end

        if type(pet.is_alive) ~= "function" then return false, "no_liveness_check" end
        local ok, alive = pcall(pet.is_alive, pet)
        if not ok then return false, "liveness_check_error" end
        if alive ~= true then return false, "pet_dead" end

        -- A command that names a unit must be able to RESOLVE it, and that is a precondition,
        -- so it is refused HERE rather than left to the executor. The difference is not
        -- cosmetic: a gate refusal lands in `rejected` with the gate's name attached, while an
        -- executor refusal lands in `failed` -- which reads as "the kernel tried and the game
        -- said no". It did not try. The same reasoning puts `unit_unresolved` in the castable
        -- gate for a cast.
        if payload.command == "attack" or payload.command == "cast" then
            if resolve_unit(deps, payload.unit) == nil then return false, "unit_unresolved" end
        end
        return true
    end
end

-- ---------------------------------------------------------------------------
-- Executors
-- ---------------------------------------------------------------------------

local function cast_executor(deps)
    -- `snapshot` for the same reason the castable gate takes it: `resolve_cast_destination` runs
    -- again here, and the guid ref's generation must be re-checked against the tick that is
    -- actually committing, not against one captured at install time.
    return function(intent, snapshot)
        local payload = intent.payload or {}
        local destination, reason = resolve_cast_destination(deps, payload, snapshot)
        if destination == nil then return false, reason end

        -- ================================================================================
        -- FOUR VERBS, ONE PER (DESTINATION x SPEED) COMBINATION -- AND `fast` IS A DELIVERY
        -- VARIANT, NOT A SECOND INTENT TYPE WEARING ONE NAME
        -- ================================================================================
        -- The distinction matters because ADR 08 §3.2 makes an intent's TYPE the thing a channel
        -- and a lease attach to. `fast` changes NEITHER: no gate reads it. `gcd_gate` branches on
        -- `payload.off_gcd`, `castable_gate` branches on neither, and the channel is CASTING
        -- either way. It selects which SDK verb carries an already-authorised packet, which is a
        -- transport detail -- so it stays a payload flag rather than becoming `cast_fast`.
        --
        -- WHAT `_fast` ACTUALLY DOES. docs/SylvannasAPI/dev/libraries/spell-queue.md, on
        -- `queue_spell_target_fast`: "Same as `queue_spell_target` but SKIPS GCD CHECKS. Use for
        -- off-GCD abilities." This comment previously said it skipped a "post-queue verification
        -- round-trip" -- that was the legacy SpellDispatcher's behaviour, carried over during the
        -- Phase 4c conversion, and it is not what the SDK does. Corrected here because a comment
        -- describing a mechanism that no longer exists is worse than none: the next reader would
        -- reason about latency where the real axis is the GCD.
        --
        -- THE CONSEQUENCE, AND THE BLIND SPOT. `fast` and `off_gcd` are the same fact told to two
        -- different authorities -- `off_gcd` tells the KERNEL's gate not to wait on the GCD,
        -- `fast` tells the QUEUE not to. THE KERNEL DOES NOT MAKE THEM AGREE, and both mismatches
        -- are reachable:
        --   * `off_gcd` without `fast` -- the kernel lets it through and the queue's own GCD check
        --     may still swallow it. Silent, because the queue's refusal is not a named gate here.
        --   * `fast` without `off_gcd` -- the kernel's gate holds it during the GCD. Strictly
        --     safer, so it is left alone.
        -- Not fused, because only the rotation knows which it means and the catalog is the
        -- corroborating authority for `off_gcd` (see `frost_support.queue_target`). Stated rather
        -- than fixed, so the gap is visible where the verb is chosen.
        --
        -- Serving a `fast` request with the slow verb because the SDK lacks the fast one would
        -- silently undo the only reason it was requested, so an absent verb is a refusal like any
        -- other.
        local sq = deps.spell_queue
        local verb
        if destination.kind == "point" then
            verb = payload.fast and "queue_spell_position_fast" or "queue_spell_position"
        else
            verb = payload.fast and "queue_spell_target_fast" or "queue_spell_target"
        end
        if not sq or type(sq[verb]) ~= "function" then
            return false, "no_spell_queue"
        end

        local priority = Bands.spell_queue_priority(intent.band)
        local aim = destination.kind == "point" and destination.point or destination.unit
        -- The SDK's `message` is a debugging breadcrumb. The rotation's action name says WHICH
        -- decision cast; the owner only says which plugin did. Prefer the former, fall back to the
        -- latter so an unlabelled cast is still attributable.
        local message = payload.label or intent.owner
        -- COLON. See the header: a dot call here shifts every argument by one.
        local ok, queued = pcall(function()
            return sq[verb](sq, payload.spell_id, aim, priority, message)
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

local function face_executor(deps)
    return function(intent)
        local payload = intent.payload or {}
        local input = deps.input
        if not input or type(input.look_at) ~= "function" then return false, "no_look_at" end
        -- `look_at` is the horizontal-only form. `look_at_3d` adds pitch, which matters for a
        -- flying mount and not for anything this kernel does yet; when it does, that is a
        -- second payload field on this same intent, not a second intent type.
        local ok, result = pcall(input.look_at, payload.point)
        if not ok then return false, "look_at_error" end
        if result == false then return false, "look_at_refused" end
        return true
    end
end

---MOVEMENT, and the one executor that reaches no SDK surface at all.
---
---It records a DESIRED STATE. `kernel/movement_release.lua` reconciles actual keys against it
---after the commit stage, and clears it on revocation so the release falls out as a
---consequence rather than as a plugin's courtesy. See that file for why the desire is a key
---set and not a point.
local function move_executor()
    return function(intent)
        local payload = intent.payload or {}
        if payload.stop == true then
            MovementRelease.set_desired(nil)
            return true
        end
        local ok, reason = MovementRelease.set_desired(payload.keys)
        if not ok then return false, reason end
        return true
    end
end

local function use_item_executor(deps)
    return function(intent)
        local payload = intent.payload or {}
        local input = deps.input
        if not input or type(input.use_item) ~= "function" then return false, "no_use_item" end
        -- The self-cast form. `use_item_target` and `use_item_position` are separate SDK verbs
        -- with separate preconditions (a target's range, a position's validity), so they belong
        -- behind separate payload shapes with their own gate arms -- not behind a nil check.
        local ok, result = pcall(input.use_item, payload.item_id)
        if not ok then return false, "use_item_error" end
        if result == false then return false, "use_item_refused" end
        return true
    end
end

local function pet_command_executor(deps)
    return function(intent)
        local payload = intent.payload or {}
        local input = deps.input
        if not input then return false, "no_input" end

        local command = payload.command
        local verb, args
        if command == "attack" or command == "cast" then
            -- Resolved HERE, one stage after the rotation named it. This is the whole reason a
            -- pet command is an intent: `pet_attack` takes a live handle, and a handle is valid
            -- only for the tick that produced it.
            local unit = resolve_unit(deps, payload.unit)
            if unit == nil then return false, "unit_unresolved" end
            if command == "attack" then
                verb, args = "pet_attack", { unit }
            else
                if type(payload.spell_id) ~= "number" then return false, "missing_spell_id" end
                verb, args = "pet_cast_target_spell", { payload.spell_id, unit }
            end
        elseif command == "passive" then
            verb, args = "set_pet_passive", {}
        elseif command == "follow" then
            verb, args = "set_pet_follow", {}
        else
            return false, "unknown_pet_command"
        end

        local fn = input[verb]
        if type(fn) ~= "function" then return false, "no_" .. verb end
        local ok, result = pcall(fn, args[1], args[2])
        if not ok then return false, verb .. "_error" end
        if result == false then return false, verb .. "_refused" end
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

    -- Order matters: cheap in-memory checks before the SDK round-trip. Every gate here
    -- short-circuits on `intent.type`, so a `face` intent costs five type comparisons and one
    -- shape check -- not five SDK round-trips for questions about a spell it does not cast.
    queue:add_gate("gcd", gcd_gate(deps))
    queue:add_gate("castable", castable_gate(deps))
    queue:add_gate("face", face_gate())
    queue:add_gate("move", move_gate())
    queue:add_gate("item", item_gate(deps))
    queue:add_gate("pet", pet_gate(deps))

    queue:register_executor("cast", cast_executor(deps))
    queue:register_executor("target", target_executor(deps))
    queue:register_executor("face", face_executor(deps))
    queue:register_executor("move", move_executor())
    queue:register_executor("use_item", use_item_executor(deps))
    queue:register_executor("pet_command", pet_command_executor(deps))
    return true
end

return Executors
