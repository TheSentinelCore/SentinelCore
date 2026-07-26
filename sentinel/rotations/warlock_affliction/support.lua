-- rotations/warlock_affliction/support.lua
-- The plugin's own utilities. Requires nothing but `sentinel_api`.
--
-- ================================================================================
-- WHAT THIS FILE REPLACES, AND WHY IT IS A COPY RATHER THAN A SHARE
-- ================================================================================
-- Before the port, `affliction_actions.lua` reached `modules/combat/action_library.lua`, which
-- reached `shared/combat_helpers.lua`, which reached `module.combat.dispatcher` off the blackboard.
-- Two of those three are cross-package requires the require audit forbids, and the third is the
-- coupling that audit cannot see at all -- it travels through a string key at runtime rather than
-- through an import.
--
-- `shared/combat_helpers.lua` was two different things wearing one name, and this file keeps only
-- the halves a rotation legitimately owns:
--
--   1. PURE UTILITIES -- `num`, `safe_call`, `player_and_target`. Three lines each, no engine
--      coupling, no shared state. Copying them into the plugin is correct: they are not an API gap,
--      and putting them on the kernel surface would make `Sentinel.num` a thing, which is absurd.
--
--   2. THE CAST PATH -- `queue_target`. It emits a `cast` intent under a CASTING lease instead of
--      calling `SpellDispatcher:queue_spell`. See the section further down.
--
-- Everything here is ported from `rotations/mage_frost/frost_support.lua`, which converted first.
-- Only `OWNER` and the `require` path differ; the reasoning in the comments below is that file's,
-- reproduced because it explains code that lives here now.

local API = require("rotations/warlock_affliction/sentinel_api")

local Support = {}

--- ADR §6.3's mapping. Affliction never emits at INTERRUPT -- it has no interrupt -- but the
--- constant is kept so the band mapping below stays a total function rather than one that silently
--- falls back for a value it was never told about.
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

-- ---------------------------------------------------------------------------
-- Catalog access
-- ---------------------------------------------------------------------------

---Resolve a spell key to the best rank the character actually knows.
---
---The BLACKBOARD catalog only. Falling back to `Sentinel.catalogs.spell` when the blackboard has
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
-- ================================================================================
-- WHAT SUCCESS MEANS NOW
-- ================================================================================
-- SUCCESS is "the intent was accepted for this tick", not "the spell was queued at the SDK". The
-- packet leaves later, in COMMIT, if the lease is still live and every gate agrees. That is strictly
-- more information than before: the dispatcher collapsed refusal and success into one boolean, while
-- a rejected intent is named in the tick report.

local Status_FAILURE_SAFE = nil  -- resolved live; `Support.status()` may be nil before the kernel is up

--- Who is casting, for lease ownership and for the SDK breadcrumb's fallback. Must match
--- `manifest.lua`'s `id`; duplicated rather than read from it because manifest.lua requires
--- affliction_tbc.lua, which requires this file.
local OWNER = "sentinel.rotation.warlock_affliction"

--- The band each queue priority maps onto.
---
--- NOT arbitrary and NOT new: `Bands.spell_queue_priority` sends bands >= 70 to spell_queue priority
--- 7 (the documented interrupt slot) and everything else to 1 -- which is exactly the
--- DEFAULT/INTERRUPT split this file already had.
local BAND_FOR_PRIORITY = {
    [Support.QueuePriorities.DEFAULT] = "COMBAT",
    [Support.QueuePriorities.INTERRUPT] = "SURVIVAL",
}

---Does the kernel's catalog CORROBORATE that this ability is fired off the global cooldown?
---
---Returns false for every uncertainty -- no surface, no catalog, no method, a throwing method, or
---an answer that is not literally `true`. The safe default is "it is on the GCD": an ability wrongly
---granted the bypass sends a packet into a live GCD, where the SERVER refuses it and the kernel's
---own report says it went fine.
---
---`is_ogcd_spell` and not `is_gcd_spell`, because the two default in opposite directions on a key
---neither has heard of: `is_gcd_spell("typo") -> false` reads as "not on the GCD" and GRANTS the
---bypass, while `is_ogcd_spell("typo") -> false` reads as "not off the GCD" and refuses it.
---
---NO AFFLICTION ACTION DECLARES `off_gcd` TODAY, and none should without measuring
---`spell_template.StartRecoveryCategory` for that spell in tbcmangos.sqlite first. The check is
---carried anyway so `opts` means the same thing in both rotations -- a `queue_target` that silently
---ignored the flag would be worse than one that refuses it.
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
--- ALWAYS THE GUID, never the symbolic `"target"`. A guid pins the unit the rotation ACTUALLY CHOSE;
--- `"target"` is re-resolved at commit, one stage later, so a selection that moved mid-tick would
--- send the cast somewhere the rotation did not decide. The symbolic vocabulary stays for callers
--- that genuinely mean "whatever is targeted when this runs" -- `pet_command`'s attack, for one.
--- A cast is not one of those.
---
--- MINTED THROUGH THE KERNEL, never open-coded here. A guid is a value with no expiry: cached in
--- tick N and submitted in tick N+5 it commits a packet aimed by five-tick-old reasoning, and the
--- LEASE generation cannot catch it, because a lease is measured in ticks and is supposed to span
--- many of them. So the ref is generation-stamped by `Sentinel.units:mint_ref` against the frozen
--- snapshot. A stamp the caller applies to itself is not a stamp.
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
    -- to the tick this rotation is actually running in.
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

---@param action_id string The rotation's name for this decision. Becomes the SDK breadcrumb.
---@param opts table|nil { fast?: boolean, off_gcd?: boolean } -- `off_gcd` is a REQUEST, not a
---            statement of fact: it is honoured only if the kernel catalog corroborates it.
function Support.queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local Status = Support.status()
    if not Status then return Status_FAILURE_SAFE end
    priority = priority or Support.QueuePriorities.DEFAULT

    -- Resolved HERE rather than by the dispatcher.
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
    -- `fast` and `off_gcd` are NOT the same request. `fast` picks the SDK verb that skips the SPELL
    -- QUEUE's own GCD check; `off_gcd` tells the KERNEL's gate not to wait on the GCD. Asking for
    -- `off_gcd` without `fast` would let the kernel through and leave the queue's own check to
    -- swallow the cast silently, which is why the two travel together.
    if opts and opts.off_gcd and catalog_confirms_off_gcd(spell_key) then
        payload.off_gcd = true
    end

    if submit_cast(payload, priority) then return Status.SUCCESS end
    return Status.FAILURE
end

return Support
