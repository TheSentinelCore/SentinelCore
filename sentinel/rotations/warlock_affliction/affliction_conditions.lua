-- rotations/warlock_affliction/affliction_conditions.lua
-- Every condition the Affliction rotation evaluates, in the package that evaluates them.
--
-- ================================================================================
-- WHY THIS FILE GREW FROM THREE FUNCTIONS TO THIRTEEN
-- ================================================================================
-- Before the port, `affliction_tbc.lua` mixed three local conditions with nine borrowed from
-- `modules/combat/condition_library.lua`. That require is a cross-package reach the require audit
-- forbids (`tests/kernel/test_plugin_require_audit.lua`), and `condition_library.lua` is itself a
-- `Scope.PROMOTION_CANDIDATE` -- a file scheduled to move INTO the kernel, at which point it owns no
-- `module.*` namespace at all. Depending on it from a plugin would make that move harder, not
-- easier.
--
-- So the nine came across, UNCHANGED except where the snapshot section below says otherwise. Each
-- one is a copy of the condition_library function it replaces, not a reinterpretation of it: the
-- thresholds, the fail-open/fail-closed direction and the blackboard keys are the tuned artefact
-- and had to survive the move byte-for-byte in behaviour.
--
-- ================================================================================
-- WHAT COULD NOT MOVE ONTO THE FROZEN SNAPSHOT, AND WHY (measured, not assumed)
-- ================================================================================
-- `kernel/cond/init.lua` ports 17 predicates. Of the conditions below:
--
--   MOVED   health_below, health_above      -- `player.health_pct` is in the snapshot's HOT tier.
--   BLOCKED mana_below                      -- `power_below` exists, but `mana_above` has no
--                                              `power_above` twin, and splitting one tuned pair
--                                              across two sources of truth is how the two halves
--                                              drift. Both stay on the blackboard together.
--   BLOCKED mana_above                       -- no `power_above` predicate.
--   BLOCKED gcd_ready                        -- reads `module.combat.cooldowns`; no cooldown tier.
--   BLOCKED spell_ready / spell_available    -- no cooldown and no spell-book tier.
--   BLOCKED target_missing_dot               -- no aura tier. `AuraCatalog.has_any_debuff` walks a
--                                              live handle, and there is nothing frozen to read.
--   BLOCKED has_voidwalker / missing_        -- no PET tier at all. `kernel/cond/init.lua:305` says
--           voidwalker                         so in as many words: "`_ = PET` keeps the ref named
--                                              here: it is the one unit with no sensor behind it".
--   BLOCKED not_in_combat                    -- `in_combat` exists, but see its own note below.
--   BLOCKED target_valid                     -- `has_target` exists and answers the OPPOSITE way on
--                                              an unreadable target; see its own note below.

local API = require("rotations/warlock_affliction/sentinel_api")
local H = require("rotations/warlock_affliction/support")

-- Resolved at CALL time, never captured at load time: `_G.Sentinel` may not exist yet when this
-- file loads (ADR 08 §2.4 -- the getter fixes reads, the queue fixes registration).
local AuraCatalog = setmetatable({}, { __index = function(_, k)
    local c = API.catalogs
    return c and c.aura and c.aura[k] or nil
end })
local SpellHelper = {
    -- FAIL OPEN on "cannot say", preserving the ported behaviour: `condition_library.spell_ready`
    -- called `SpellHelper.is_spell_castable` directly and tested `if not castable`, so the truthy
    -- `UNKNOWN` string read as castable. That default is right HERE -- the commit gate is the real
    -- check now, and a condition that went false on an unresolved helper would stop the warlock
    -- casting entirely.
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

-- ============================================================================
-- SNAPSHOT-BACKED HEALTH
-- ============================================================================
-- The rotation's only consumer of `Sentinel.cond`, and the only place a `Truth` crosses into this
-- package.
--
-- WHY THE HEALTH PAIR AND NOTHING ELSE. These three call sites -- `drain_life_sustain`,
-- `drain_life_recovery` and `life_tap_sustain` -- are the rotation's survivability wedge, and the
-- blackboard version read `H.num(blackboard:get("player.health_pct", 0)) < threshold`. That default
-- of 0 means UNREADABLE HEALTH READS AS 0%, so on any tick the sensor had not filled the key,
-- `health_below(0.40)` answered true and the warlock started channelling Drain Life instead of
-- casting -- and `health_above(0.50)` answered false, blocking Life Tap at the same moment. A
-- missing sensor read, not danger, drove both.
--
-- THE POLICY IS STATED, NOT DEFAULTED. `Truth.resolve` refuses to run without one. `TreatFalse` here
-- says "if I cannot read health, do not treat that as an emergency" in the open, where a reviewer
-- sees it. It is the same policy `rotations/mage_frost/frost_conditions.lua` chose for the same
-- pair, for the same reason.
--
-- THIS IS THE ONE BEHAVIOUR THE PORT DELIBERATELY CHANGES, and only in the "no reading" case: with
-- a readable snapshot the answers are identical to the blackboard era. See the suite note in
-- tests/rotations/warlock_affliction/test_affliction_conditions.lua.

---Resolve one kernel predicate against the tick's frozen snapshot.
---
---Reads `Sentinel.snapshot` and `Sentinel.cond` at CALL time through the plugin's API shim, so a
---condition built before the kernel published still works once it has.
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

function Cond.health_below(threshold)
    return function()
        return snapshot_predicate("health_below", threshold)
    end
end

function Cond.health_above(threshold)
    return function()
        return snapshot_predicate("health_above", threshold)
    end
end

-- ============================================================================
-- MANA (still the blackboard -- see the header)
-- ============================================================================

function Cond.mana_below(threshold)
    return function(blackboard)
        return H.num(blackboard:get("player.mana_pct", 0)) < threshold
    end
end

function Cond.mana_above(threshold)
    return function(blackboard)
        return H.num(blackboard:get("player.mana_pct", 0)) > threshold
    end
end

-- ============================================================================
-- PLAYER / TARGET STATE
-- ============================================================================

function Cond.gcd_ready(blackboard)
    local cooldowns = blackboard:get("module.combat.cooldowns")
    return cooldowns and cooldowns:is_gcd_ready(blackboard:get("system.now_ms", 0)) or false
end

--- NOT converted to `cond.in_combat`, even though the predicate exists.
---
--- The blackboard version reads `== false` against a default of `false`, so an unfilled key answers
--- "out of combat" and the summon is ALLOWED. `not snapshot_predicate("in_combat")` under
--- `TreatFalse` answers the same way -- but only by coincidence of double negation, and the summon
--- gate is the one place in this rotation where "I could not read combat state" and "you are out of
--- combat" must not be conflated: a 10-second summon cast started mid-chase stalls the pull. Left on
--- the key that has a writer until a `not_in_combat` predicate exists that can say Unknown out loud.
function Cond.not_in_combat(blackboard)
    return blackboard:get("player.in_combat", false) == false
end

--- NOT converted to `cond.has_target`, and the reason is a polarity flip rather than a missing
--- predicate. This version returns TRUE when the `is_dead` read FAILS (`not ok_dead or dead ~= true`)
--- -- fail-open, so an unreadable target still gets cast at and the commit gate makes the real
--- decision. `has_target` under `TreatFalse` is fail-CLOSED, which would silently stop the rotation
--- on any tick the snapshot could not read the target. Porting is not rewriting; the polarity stays.
function Cond.target_valid(blackboard)
    local _, target = H.player_and_target(blackboard)
    if not target then
        return false
    end
    local ok_dead, dead = H.safe_call(target, "is_dead")
    return not ok_dead or dead ~= true
end

-- ============================================================================
-- SPELL AVAILABILITY
-- ============================================================================

--- Cooldown + castability + line of sight, for a spell already assumed trained.
function Cond.spell_ready(spell_key, mode, cast_target)
    mode = mode or "best"
    cast_target = cast_target or "target"
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

--- Distinct from `spell_ready`: this one gates on TRAINED status, via
--- `SpellCatalog:resolve_known_rank`. A priority entry gated on a catalog key auto-resolves to the
--- highest known rank and auto-skips when nothing is known -- graceful 1-70 degradation with no
--- hand-typed level checks, which is the whole reason every DoT and filler entry carries one.
---
--- `mode`:
---   "known" (default) -- trained status only.
---   "usable"          -- trained status AND the client says the spell is castable right now, which
---                        for Summon Voidwalker means a Soul Shard is in the bag. "known" alone
---                        retried the summon forever with zero shards.
---
--- ================================================================================
--- THE ONE PLACE THIS PACKAGE STILL TOUCHES THE SDK, AND WHY
--- ================================================================================
--- `core.spell_book.is_usable_spell` has NO equivalent on `_G.Sentinel`. `Sentinel.spells` answers
--- castability, line of sight and AoE placement; `Sentinel.catalogs.spell` answers rank resolution.
--- Neither can answer "does the character hold the reagent". Dropping the check would change
--- behaviour in the direction a test already pins (`no summon may be queued without a Soul Shard`),
--- and inventing an answer would be worse.
---
--- So it is ledgered rather than hidden: two entries in `CORE_ACCESS_LEDGER`
--- (tests/kernel/test_plugin_core_access_audit.lua) and an API gap to close by publishing a
--- reagent/usability query on the kernel surface. The ledger may only shrink, so this cannot drift
--- into a habit.
function Cond.spell_available(spell_key, mode)
    mode = mode or "known"
    return function(blackboard)
        local catalog = blackboard:get("module.combat.catalog")
        if not catalog then
            return false
        end
        local spell_id = catalog:resolve_known_rank(spell_key)
        if not spell_id then
            return false
        end
        if mode == "usable" then
            if not (core and core.spell_book and core.spell_book.is_usable_spell) then
                return false
            end
            local ok, usable = pcall(core.spell_book.is_usable_spell, spell_id)
            return ok and usable == true
        end
        return true
    end
end

-- ============================================================================
-- DOT MAINTENANCE
-- ============================================================================

--- True when the current target is missing EVERY known rank of `spell_key`'s debuff. Reads the rank
--- array straight off the catalog entry (spell_catalog.lua) rather than hardcoding a single debuff
--- id, so a refresh check stays correct across the whole 1-70 rank range without per-level
--- bookkeeping.
---
--- Returns true (treat as "missing" -> let `spell_available` gate the cast) when there is no
--- catalog/target to check against, matching the fail-open shape `spell_available` uses (never
--- errors, degrades gracefully).
function Cond.target_missing_dot(spell_key)
    return function(blackboard)
        local catalog = blackboard:get("module.combat.catalog")
        local _, target = H.player_and_target(blackboard)
        if not catalog or not target then
            return true
        end
        local spell = catalog:get(spell_key)
        if not spell then
            return true
        end
        local ids = spell.ranks or (spell.id and { spell.id }) or {}
        if #ids == 0 then
            return true
        end
        return not AuraCatalog.has_any_debuff(target, ids)
    end
end

-- ============================================================================
-- PET (VOIDWALKER)
-- ============================================================================

--- Set by pet_controller.lua:refresh on every tick_off_gcd.
function Cond.has_voidwalker(blackboard)
    return blackboard:get("combat.has_voidwalker", false) == true
end

function Cond.missing_voidwalker(blackboard)
    return blackboard:get("combat.has_voidwalker", false) ~= true
end

function Cond.pet_not_attacking_target()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        local target = blackboard:get("combat.target") or blackboard:get("player.target")
        if not pet_ctrl or not target then return false end
        return not pet_ctrl:already_sent_to(target)
    end
end

return Cond
