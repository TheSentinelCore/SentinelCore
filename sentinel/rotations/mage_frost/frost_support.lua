-- rotations/mage_frost/frost_support.lua
-- The plugin's own utilities. Requires nothing but `sentinel_api`.
--
-- ================================================================================
-- WHAT BELONGS HERE AND WHAT DOES NOT
-- ================================================================================
-- This file exists because the port found that `shared/combat_helpers.lua` was two different things
-- wearing one name:
--
--   1. PURE UTILITIES -- `num`, `safe_call`, `player_and_target`. Three lines each, no engine
--      coupling, no shared state. Copying them into the plugin is correct: they are not an API gap,
--      and putting them on the kernel surface would make `Sentinel.num` a thing, which is absurd.
--
--   2. THE CAST PATH -- `queue_target`, `queue_position`, `queue_resolved_target`. These emit `cast`
--      intents under a CASTING lease. See the section further down.
--
-- ================================================================================
-- THE COUPLING THE REQUIRE AUDIT COULD NOT SEE IS GONE (Phase 4c D4)
-- ================================================================================
-- This header used to record a finding: `queue_target` read `module.combat.dispatcher` off the
-- blackboard -- a live dependency on the combat module that
-- `tests/kernel/test_plugin_require_audit.lua` could never catch, because it is not a `require`. The
-- audit inspects import statements, and that coupling travelled through a string key at runtime.
--
-- It was left in place deliberately for one step (ADR §13 risk 5: "Port them; do not rewrite them"),
-- so that a behaviour difference could be attributed to the move or to the rewrite but never to
-- both at once. The files moved first. The cast path converted second, as its own test-first pass,
-- and this is that pass.
--
-- There is now NO dispatcher reference in the package. `CROSS_NAMESPACE_LEDGER` for this file went
-- 2 -> 1; the survivor is `module.combat.catalog`, which rank resolution still needs.
--
-- THE BLIND SPOT ITSELF IS NOT FIXED. A plugin can still reach the whole combat engine through
-- `blackboard:get("module.combat.*")` while the require audit reports clean. What closes it here is
-- the namespace audit's ratchet, not the require audit -- and only for the files it scans.

local API = require("rotations/mage_frost/sentinel_api")

local Support = {}

--- ADR §6.3's mapping, as the two values this rotation actually uses. `1` is "everything you
--- author", `7` is the documented interrupt slot -- Counterspell is the only user of INTERRUPT here.
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
-- Action combinators
-- ---------------------------------------------------------------------------
-- Ported from `modules/combat/action_library.lua`, which the profile required for exactly these two
-- functions. They are NOT BT composites despite the names -- they compose ACTION FUNCTIONS
-- (`fn(blackboard) -> Status`) into another action function, and never build a node. So
-- `Sentinel.bt.sequence` is not a substitute, and this is not an API gap: ten lines of pure control
-- flow over the plugin's own actions belongs in the plugin.

---Run actions in order; stop at the first that does not SUCCEED, returning its status.
function Support.sequence(actions)
    return function(blackboard)
        local Status = Support.status()
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status ~= Status.SUCCESS then
                return status
            end
        end
        return Status.SUCCESS
    end
end

---Try actions in order until one succeeds. RUNNING short-circuits so the action can continue next
---frame rather than the next alternative firing on top of it.
function Support.selector(actions)
    return function(blackboard)
        local Status = Support.status()
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status == Status.SUCCESS then
                return Status.SUCCESS
            end
            if status == Status.RUNNING then
                return Status.RUNNING
            end
        end
        return Status.FAILURE
    end
end

-- ---------------------------------------------------------------------------
-- Catalog access
-- ---------------------------------------------------------------------------

---Resolve a spell key to the best rank the character actually knows.
---
---Prefers the kernel's shared catalog (`Sentinel.catalogs.spell`) and falls back to the blackboard's
---`module.combat.catalog` only because the existing rotation tests inject a catalog stub there. Both
---reach the same DB-baked rank data; the kernel one is authoritative once the app is up.
function Support.spell_id_for(blackboard, spell_key, mode)
    -- The BLACKBOARD catalog only. Falling back to `Sentinel.catalogs.spell` when the blackboard
    -- has none looked like an improvement and was a behaviour change: the ported code returns nil
    -- (and the action returns FAILURE) when no catalog is present, and a test pins exactly that.
    -- ADR §6.3 forbids fallback logic on the cast path for this reason -- it turns a loud failure
    -- into a quiet different behaviour.
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then return nil end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

-- ---------------------------------------------------------------------------
-- The cast path -- now the kernel's, not the combat module's
-- ---------------------------------------------------------------------------
-- Phase 4c D4. These two functions carry 36 of the frost profile's 38 cast sites, which is why the
-- conversion happens HERE and the 36 call sites are untouched: the plan's "38 sites" figure counted
-- call expressions, and the conversion surface is four places.
--
-- The blackboard route to `module.combat.dispatcher` is gone. That coupling was recorded in this
-- file's header as a live dependency the require audit could not see -- a plugin reaching the whole
-- combat engine through a string key while auditing clean. It is not merely relocated; there is now
-- no dispatcher reference in this package at all.
--
-- ================================================================================
-- WHAT SUCCESS MEANS NOW
-- ================================================================================
-- SUCCESS is "the intent was accepted for this tick", not "the spell was queued at the SDK". The
-- packet leaves later, in COMMIT, if the lease is still live and every gate agrees. Same change
-- `use_item` made in Phase 4b, and strictly more information than before: the dispatcher collapsed
-- refusal and success into one boolean, while a rejected intent is named in the tick report.

local Status_FAILURE_SAFE = nil  -- resolved live; `Support.status()` may be nil before the kernel is up

--- Who is casting, for lease ownership and for the SDK breadcrumb's fallback.
local OWNER = "sentinel.rotation.mage_frost"

--- The band each queue priority maps onto.
---
--- The mapping is NOT arbitrary and NOT new: `Bands.spell_queue_priority` sends bands >= 70 to
--- spell_queue priority 7 (the documented interrupt slot) and everything else to 1 -- which is
--- exactly the DEFAULT/INTERRUPT split this file already had. Counterspell is the only INTERRUPT
--- user, so SURVIVAL is the band that reproduces today's behaviour rather than reinterpreting it.
local BAND_FOR_PRIORITY = {
    [Support.QueuePriorities.DEFAULT] = "COMBAT",
    [Support.QueuePriorities.INTERRUPT] = "SURVIVAL",
}

-- ---------------------------------------------------------------------------
-- The off-GCD bypass (Phase 4d)
-- ---------------------------------------------------------------------------
--
-- ================================================================================
-- THE BUG: A FLAG WITH A READER AND NO WRITER
-- ================================================================================
-- `intent_executors.lua:217` lets `payload.off_gcd` skip the GCD gate, and `:438` uses the same flag
-- to decide whether the cast is charged against the GCD estimate. Nothing in `sentinel/` ever SET it.
-- The three actions in the rotation's off-GCD tree passed `{ fast = true }` and nothing else, so
-- every one of them was refused with `gcd_running` whenever the global cooldown was turning -- which
-- is the only moment a panic button is reached for. The gate's own comment describes the failure it
-- was suffering: "gating the panic button behind a GCD it does not use makes it unreachable exactly
-- when it is needed."
--
-- ================================================================================
-- "THE OFF-GCD TREE" IS NOT THE SAME CLAIM AS "OFF THE GCD"
-- ================================================================================
-- `frost_tbc.lua:353` wraps a subtree it ticks every cycle rather than once per global cooldown.
-- That is a SCHEDULING statement about when the rotation reconsiders those decisions. Whether the
-- resulting spell triggers the global cooldown is a GAME statement, and the game answers it in
-- `spell_template.StartRecoveryCategory`. Setting the flag on the whole tree would conflate the two,
-- and the conflation is dangerous in one direction only: an ability wrongly granted the bypass sends
-- a packet into a live GCD, where the SERVER refuses it and the kernel's own report says it went
-- fine. Measured against tbcmangos.sqlite (TBC 2.4.3):
--
--     SpellName                  StartRecoveryCategory  StartRecoveryTime   on the GCD?
--     Icy Veins       (12472)                        0                  0       NO
--     Cold Snap       (11958)                        0                  0       NO
--     Ice Barrier     (11426..33405, all 6 ranks)  133               1500      YES
--     Ice Block       (45438)                      133               1500      YES
--
-- Two of the three tree actions may bypass. Ice Barrier may not: it is a mage shield and every mage
-- shield triggers the global cooldown in TBC.
--
-- ================================================================================
-- TWO AUTHORITIES, COMBINED WITH `AND`, AND WHY THAT IS NOT MERELY "TWO LISTS"
-- ================================================================================
-- The obvious design is to ask the catalog and be done -- one list cannot drift from itself. It was
-- rejected on evidence: `kernel/catalogs/spell.lua:36` marks `ice_barrier` `gcd = false, ogcd = true`
-- and the game says otherwise, so a catalog-only rule would hand a GCD-bound shield a bypass TODAY.
-- The equally obvious alternative -- a hardcoded list in this package -- is the drift the catalog
-- exists to prevent.
--
-- So both must agree: the ACTION declares `opts.off_gcd`, and the CATALOG must corroborate. The `AND`
-- is not belt-and-braces, it is directional. Either authority being wrong on its own CLOSES the gate
-- rather than opening it, so drift can only ever cost a delayed cast -- never an illegal one. That is
-- the same direction `kernel/timing.lua:56` already chose for itself: "over-gating delays a cast by
-- one window, under-gating double-casts."
--
-- ================================================================================
-- WHY `is_ogcd_spell` AND NOT `is_gcd_spell`
-- ================================================================================
-- `is_gcd_spell` is the member `api.lua:132` publishes, and it is the WRONG predicate here, for a
-- reason that is invisible until it bites. Both return a plain boolean and neither can say "I have
-- never heard of this key" -- but they default in opposite directions:
--
--   is_gcd_spell("typo")  -> false  ... which reads as "not on the GCD" -> BYPASS GRANTED
--   is_ogcd_spell("typo") -> false  ... which reads as "not off the GCD" -> bypass refused
--
-- An unknown key is exactly what a renamed spell key or a stale catalog produces, so the predicate
-- whose ignorance is safe is the one to ask. `is_ogcd_spell` is not in `api.lua`'s published member
-- list even though it lives on the same published object; the guard below treats its absence as a
-- refusal, so an older catalog fails closed rather than throwing.
--
-- ================================================================================
-- WHAT THIS CANNOT SEE
-- ================================================================================
--   * WHETHER THE CATALOG IS RIGHT. It reads the catalog; it cannot audit it. `ice_barrier` is
--     wrong there today and this function has no way to know that -- what protects the rotation is
--     the action-side declaration, not this check. Fix the catalog and nothing here notices.
--   * WHETHER THE CLIENT AGREES. The GCD the gate consults is `kernel/timing.lua`'s ESTIMATE, exact
--     only for casts the kernel committed itself. A human pressing a key opens a GCD neither the
--     estimate nor this flag can see.
--   * GROUND-TARGETED CASTS. `queue_position` takes no `opts` and gets no bypass. Every ground-
--     targeted frost spell (Blizzard, Flamestrike) is on the GCD, so there is nothing to plumb --
--     but if an off-GCD ground spell is ever added, this is where it will be missing.

---Does the kernel's catalog CORROBORATE that this ability is fired off the global cooldown?
---
---Returns false for every uncertainty -- no surface, no catalog, no method, a throwing method, or
---an answer that is not literally `true`. See the header: the safe default is "it is on the GCD".
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
--- ALWAYS THE GUID, never the symbolic `"target"`, and that is a deliberate choice rather than a
--- shortcut:
---
---   * A guid pins the unit the rotation ACTUALLY CHOSE. `"target"` is re-resolved at commit, one
---     stage later, so a selection that moved mid-tick would send the cast somewhere the rotation
---     did not decide -- the divergence ADR 08 §13.1 item 19 names, arriving through the back door.
---   * Deciding between `"player"` and `"target"` here would mean reading `player.object` and
---     `combat.target` off the blackboard to compare identities: two raw handle reads, added by a
---     conversion whose whole purpose is to remove that coupling. The kernel already holds the
---     player and works out self-ness itself.
---
--- The symbolic vocabulary stays in the kernel for callers that genuinely mean "whatever is targeted
--- when this runs" -- `pet_command`'s attack, for one. A cast is not one of those.
---
--- ================================================================================
--- MINTED THROUGH THE KERNEL, NOT OPEN-CODED (Phase 4d D5)
--- ================================================================================
--- This used to be `pcall(unit.get_guid, unit)` right here, and that was the bypass. A guid is a
--- value with no expiry: cached in tick N and submitted in tick N+5 it commits a packet aimed by
--- five-tick-old reasoning, and the LEASE generation cannot catch it, because a lease is measured in
--- ticks and is supposed to span many of them.
---
--- So the ref is generation-stamped, and the stamp is minted by `Sentinel.units:mint_ref` against
--- the frozen snapshot -- never by this file. A stamp the caller applies to itself is not a stamp;
--- it is a number the caller could just as easily have made up. Every hand-rolled `get_guid` call
--- site is a place the check can be bypassed, so there is now exactly one, and it is in the kernel.
---
--- FLAT SCALARS. The two returned values are spread into the payload as two fields and never nested
--- into one -- `IntentQueue:dedupe_key` flattens a single level, so a nested ref table would key on
--- its address and defeat dedupe. See `kernel/units.lua`'s `REF_TICK_FIELD` for the full reasoning.
---
--- WHAT THIS DOES NOT BUY. The stamp proves the ref was minted this tick. It does not prove the mob
--- is alive, in range, or still worth casting at; `unit_unresolved` and the castable gate are the
--- separate refusals for those, one stage later.
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
---generation check, one stage later and silently. The TTL retires the lease instead. Same reasoning
---as `frost_actions.lua`'s ITEMS lease; the mistake is easy enough to make twice.
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
---            statement of fact: it is honoured only if the kernel catalog corroborates it. See the
---            off-GCD section above for why both authorities have to agree.
function Support.queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local Status = Support.status()
    if not Status then return Status_FAILURE_SAFE end
    priority = priority or Support.QueuePriorities.DEFAULT

    -- Resolved HERE rather than by the dispatcher. `spell_id_for` reads the blackboard catalog and
    -- returns nil when there is none -- no fallback to `Sentinel.catalogs.spell`, because §6.3
    -- forbids fallback on the cast path and a test pins exactly that refusal.
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
    -- `fast` and `off_gcd` are NOT the same request and are deliberately not folded together.
    -- They are the same fact told to two different authorities: `fast` picks the SDK verb that
    -- skips the SPELL QUEUE's own GCD check (spell-queue.md: "Same as `queue_spell_target` but
    -- skips GCD checks"), while `off_gcd` tells the KERNEL's gate not to wait on the GCD. This
    -- comment previously described `fast` as skipping a dispatcher-era verification round-trip;
    -- that was the legacy SpellDispatcher, not the SDK, and it is corrected here and at the verb
    -- selection in `kernel/intent_executors.lua`.
    --
    -- All three off-GCD-tree actions want the first; only the two the game agrees about get the
    -- second. Asking for `off_gcd` WITHOUT `fast` would let the kernel through and leave the
    -- queue's own GCD check to swallow the cast silently, which is why the three travel together.
    if opts and opts.off_gcd and catalog_confirms_off_gcd(spell_key) then
        payload.off_gcd = true
    end

    if submit_cast(payload, priority) then return Status.SUCCESS end
    return Status.FAILURE
end

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

---Emit a cast at a unit named directly, for the two sites that never used the helpers.
---
---`finish_low_add` and `emergency_escape` reached `SpellDispatcher` themselves, resolving the spell
---id first. They keep that shape -- they genuinely differ from the 36 -- but they no longer reach
---past the kernel to do it.
---@return boolean submitted
function Support.queue_resolved_target(blackboard, action_id, spell_id, target, priority)
    if not spell_id then return false end
    local destination = name_unit(target)
    if not destination then return false end
    return submit_cast({
        spell_id = spell_id,
        unit_guid = destination.unit_guid,
        unit_ref_tick = destination.unit_ref_tick,
        label = action_id,
    }, priority or Support.QueuePriorities.DEFAULT)
end

return Support
