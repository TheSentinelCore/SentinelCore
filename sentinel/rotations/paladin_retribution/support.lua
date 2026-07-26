-- rotations/paladin_retribution/support.lua
-- The plugin's own utilities. Requires nothing but `sentinel_api`.
--
-- Ported from `rotations/mage_frost/frost_support.lua`, which is where the reasoning below was first
-- worked out. This is a PORT of the retribution profile onto the kernel, not a rewrite of it: every
-- threshold, priority and seal-twist decision in this package is byte-for-byte the behaviour that
-- was in `modules/combat/profiles/paladin/`. What changed is the route a cast takes out of the
-- plugin, and nothing else.
--
-- ================================================================================
-- WHAT BELONGS HERE AND WHAT DOES NOT
-- ================================================================================
-- This file replaces `shared/combat_helpers.lua`, which the old profile required and which was two
-- different things wearing one name:
--
--   1. PURE UTILITIES -- `num`, `safe_call`, `player_and_target`, `distance`. Three lines each, no
--      engine coupling, no shared state. Copying them into the plugin is correct: they are not an
--      API gap, and putting them on the kernel surface would make `Sentinel.num` a thing, which is
--      absurd.
--
--   2. THE CAST PATH -- `queue_target`, `queue_position`. These emitted through
--      `blackboard:get("module.combat.dispatcher")`, a live dependency on the combat module that
--      the require audit could never see because it travelled through a string key rather than an
--      import. They now emit `cast` intents under a CASTING lease. There is NO dispatcher reference
--      anywhere in this package.

local API = require("rotations/paladin_retribution/sentinel_api")

local Support = {}

--- ADR §6.3's mapping, as the two values this rotation actually uses. `1` is "everything you
--- author", `7` is the documented interrupt slot -- Hammer of Justice is the only user of
--- INTERRUPT here, exactly as it was before the port.
Support.QueuePriorities = { DEFAULT = 1, INTERRUPT = 7 }

---BT status strings, resolved live so this file does not capture nil at load time.
function Support.status()
    local bt = API.bt
    return bt and bt.Status or nil
end

-- ---------------------------------------------------------------------------
-- Pure utilities (category 1 above)
-- ---------------------------------------------------------------------------

function Support.num(value)
    return tonumber(value) or 0
end

---Safe method call, returning (ok, result). Mirrors the pattern used across the combat engine.
function Support.safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

---@return table|nil player, table|nil target
function Support.player_and_target(blackboard)
    return blackboard:get("player.object"),
        blackboard:get("combat.target") or blackboard:get("player.target")
end

---3D distance between two position tables.
---
---INLINED FROM `core/geometry.lua`, not reached for: `require("core/geometry")` is a cross-package
---require and the audit refuses it. `Geometry` is not on the public surface, and a rotation asking
---the kernel to subtract three numbers would be a worse API than this copy.
---
---The `math.huge` sentinel is load-bearing and is reproduced exactly: `in_melee` and
---`in_judgement_range` compare the result against a range, so an unmeasurable distance must answer
---"further than anything" rather than 0, which would read as "in melee" whenever a position could
---not be read.
---@return number
function Support.distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---------------------------------------------------------------------------
-- Catalog access
-- ---------------------------------------------------------------------------

---Resolve a spell key to the best rank the character actually knows.
---
---THE BLACKBOARD CATALOG ONLY. Falling back to `Sentinel.catalogs.spell` when the blackboard has
---none looks like an improvement and is a behaviour change: the ported code returns nil (and the
---action returns FAILURE) when no catalog is present. ADR §6.3 forbids fallback logic on the cast
---path for exactly this reason -- it turns a loud failure into a quiet different behaviour.
function Support.spell_id_for(blackboard, spell_key, mode)
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then return nil end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

-- ---------------------------------------------------------------------------
-- The cast path -- the kernel's, not the combat module's
-- ---------------------------------------------------------------------------
--
-- WHAT SUCCESS MEANS NOW. SUCCESS is "the intent was accepted for this tick", not "the spell was
-- queued at the SDK". The packet leaves later, in COMMIT, if the lease is still live and every gate
-- agrees. This matters to two actions in this package that BRANCH on their own return value --
-- `queue_seal_of_command_rank1` sets `rotation.twist.pending_reseal` and `queue_judgement` sets
-- `rotation.after_judgement_reseal` -- so both now latch on acceptance rather than on delivery.
-- That is the same shift the mage made and it is a real difference: a cast rejected at commit
-- leaves the twist flag set. It is preserved rather than corrected because the old dispatcher's
-- boolean collapsed refusal and success into one answer too, and "fix it while porting" is how a
-- port stops being one.

local Status_FAILURE_SAFE = nil  -- resolved live; `Support.status()` may be nil before the kernel is up

--- Who is casting, for lease ownership and for the SDK breadcrumb's fallback.
local OWNER = "sentinel.rotation.paladin_retribution"

--- The band each queue priority maps onto.
---
--- NOT arbitrary and NOT new: `Bands.spell_queue_priority` sends bands >= 70 to spell_queue
--- priority 7 (the documented interrupt slot) and everything else to 1 -- which is exactly the
--- DEFAULT/INTERRUPT split this rotation already had. Hammer of Justice is the only INTERRUPT user,
--- so SURVIVAL is the band that REPRODUCES today's behaviour rather than reinterpreting it.
local BAND_FOR_PRIORITY = {
    [Support.QueuePriorities.DEFAULT] = "COMBAT",
    [Support.QueuePriorities.INTERRUPT] = "SURVIVAL",
}

---Does the kernel's catalog CORROBORATE that this ability is fired off the global cooldown?
---
---NO RETRIBUTION ACTION REQUESTS THIS, and the reason is MEASURED rather than assumed. The one
---off-GCD-tree action is Avenging Wrath, and `tests/kernel/test_spell_catalog_gcd_truth.lua`
---(`test_avenging_wrath_opens_no_gcd_and_is_still_blocked_by_one`) pins it against
---tbcmangos.sqlite: `StartRecoveryTime 0` -- casting it opens no global cooldown -- but
---`StartRecoveryCategory 133`, so it is still BLOCKED by one. It is the catalog's witness that the
---two flags are not complements, and it means a bypass here would send a packet the server refuses.
---
---So the action keeps `{ fast = true }` and nothing else, exactly as before the port. Even if
---someone added `off_gcd = true` to it, this guard would refuse: `is_ogcd_spell("avenging_wrath")`
---is `false`, and that is pinned.
---
---The guard is kept so that `opts.off_gcd` is GATED rather than SILENTLY IGNORED the day a
---genuinely off-GCD Paladin ability is added. Returns false for every uncertainty -- no surface, no
---catalog, no method, a throwing method, or an answer that is not literally `true`. The safe
---default is "it is on the GCD": a wrongly granted bypass sends a packet into a live GCD, where the
---server refuses it and the kernel's own report says it went fine.
---
---`is_ogcd_spell` and not `is_gcd_spell`, because the two default in opposite directions on an
---unknown key: `is_gcd_spell("typo") -> false` reads as "not on the GCD" and GRANTS the bypass,
---while `is_ogcd_spell("typo") -> false` reads as "not off the GCD" and refuses it.
---@param spell_key string
---@return boolean
local function catalog_confirms_off_gcd(spell_key)
    local catalogs = API.catalogs
    local catalog = catalogs and catalogs.spell
    if not catalog or type(catalog.is_ogcd_spell) ~= "function" then return false end
    local ok, is_ogcd = pcall(catalog.is_ogcd_spell, catalog, spell_key)
    return ok and is_ogcd == true
end

--- Name a live unit handle in terms an intent may carry.
---
--- A handle can never ride in a payload (§2.7): the pointer can die inside the tick that captured
--- it. So the caller's handle is turned into a VALUE -- its guid -- and the kernel resolves that
--- back to a handle at commit, inside the tick that uses it.
---
--- ALWAYS THE GUID, never the symbolic `"target"` or `"player"`. A guid pins the unit the rotation
--- ACTUALLY CHOSE; `"target"` is re-resolved at commit, one stage later, so a selection that moved
--- mid-tick would send the cast somewhere the rotation did not decide. This matters more here than
--- it did for the mage: `player_and_target` prefers `combat.target` over `player.target`, so the
--- rotation's target and the client's target are routinely different objects.
---
--- MINTED THROUGH THE KERNEL, never open-coded. A guid is a value with no expiry: cached in tick N
--- and submitted in tick N+5 it commits a packet aimed by five-tick-old reasoning, and the LEASE
--- generation cannot catch it, because a lease is measured in ticks and is supposed to span many of
--- them. `Sentinel.units:mint_ref` stamps the guid with the tick index of the frozen snapshot; a
--- stamp the caller applies to itself is not a stamp.
---
--- FLAT SCALARS. The two returned values are spread into the payload as two fields and never nested
--- into one -- `IntentQueue:dedupe_key` flattens a single level, so a nested ref table would key on
--- its address and defeat dedupe.
---@return table|nil payload_fields { unit_guid, unit_ref_tick }
local function name_unit(unit)
    if unit == nil then return nil end
    local units = API.units
    if not units or type(units.mint_ref) ~= "function" then return nil end
    -- `API.snapshot` is a LIVE GETTER onto the scheduler's current frozen snapshot, so it resolves
    -- to the tick this rotation is actually running in. Handing over an older one would not forge a
    -- fresh stamp -- it would produce an old one, which commit refuses.
    local ok, guid, stamp = pcall(units.mint_ref, units, API.snapshot, unit)
    if not ok or guid == nil or stamp == nil then return nil end
    return { unit_guid = guid, unit_ref_tick = stamp }
end

---Emit a `cast` intent under a CASTING lease.
---
---THE LEASE IS DELIBERATELY NOT RELEASED. `release` removes it from the broker's holdings, and the
---commit stage validates an intent's generation by looking its lease UP in those holdings -- so a
---tidy-looking release on the way out would make every intent this function submits fail its own
---generation check, one stage later and silently. The TTL retires the lease instead.
---@return boolean submitted
local function submit_cast(payload, priority)
    local broker = API.control
    if not broker then return false end
    local caretaker = broker:acquire({
        channel = "CASTING",
        owner = OWNER,
        band = BAND_FOR_PRIORITY[priority] or "COMBAT",
        offset = 0,
        tier = "rotation",
        ttl_ticks = 2,
    })
    if not caretaker then return false end
    return caretaker:submit({ type = "cast", payload = payload }) == true
end

---@param action_id string The rotation's name for this decision. Becomes the SDK breadcrumb --
---            `intent_executors.lua` passes `payload.label` as the spell queue's `message`, which
---            is the same string the old dispatcher carried, so the breadcrumb is unchanged.
---@param opts table|nil { fast?: boolean, off_gcd?: boolean } -- `off_gcd` is a REQUEST, not a
---            statement of fact: it is honoured only if the kernel catalog corroborates it.
function Support.queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local Status = Support.status()
    if not Status then return Status_FAILURE_SAFE end
    priority = priority or Support.QueuePriorities.DEFAULT

    -- Resolved HERE rather than by the dispatcher. `spell_id_for` reads the blackboard catalog and
    -- returns nil when there is none -- no fallback to `Sentinel.catalogs.spell`, because §6.3
    -- forbids fallback on the cast path.
    local spell_id = Support.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end

    local destination = name_unit(target)
    if not destination then return Status.FAILURE end

    local payload = {
        spell_id = spell_id,
        unit_guid = destination.unit_guid,
        -- Spread FLAT alongside the guid, never nested -- see `name_unit`.
        unit_ref_tick = destination.unit_ref_tick,
        label = action_id,
    }
    if opts and opts.fast then payload.fast = true end
    -- `fast` and `off_gcd` are NOT the same request and are deliberately not folded together. They
    -- are the same fact told to two different authorities: `fast` picks the SDK verb that skips the
    -- SPELL QUEUE's own GCD check, while `off_gcd` tells the KERNEL's gate not to wait on the GCD.
    if opts and opts.off_gcd and catalog_confirms_off_gcd(spell_key) then
        payload.off_gcd = true
    end

    if submit_cast(payload, priority) then return Status.SUCCESS end
    return Status.FAILURE
end

---Emit a ground-targeted `cast` intent. Consecration's AoE-optimised placement is the only user.
---
---Takes no `opts` and gets no bypass, matching the mage: every ground-targeted spell either
---rotation casts is on the GCD, so there is nothing to plumb.
function Support.queue_position(blackboard, action_id, spell_key, position, priority, mode)
    local Status = Support.status()
    if not Status then return Status_FAILURE_SAFE end
    if type(position) ~= "table" then return Status.FAILURE end
    priority = priority or Support.QueuePriorities.DEFAULT

    local spell_id = Support.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end

    if submit_cast({ spell_id = spell_id, point = position, label = action_id }, priority) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

return Support
