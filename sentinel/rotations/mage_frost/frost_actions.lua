local API = require("rotations/mage_frost/sentinel_api")
local H = require("rotations/mage_frost/frost_support")

local QueuePriorities = H.QueuePriorities
local Status = setmetatable({}, { __index = function(_, k)
    local s = H.status()
    return s and s[k] or nil
end })
local AuraCatalog = setmetatable({}, { __index = function(_, k)
    local c = API.catalogs
    return c and c.aura and c.aura[k] or nil
end })
local AoeHelper = {
    find_optimal_position = function(spell_id, range, min_targets, radius)
        local s = API.spells
        if not s then return nil, 0 end
        return s:find_aoe_position(spell_id, range, min_targets, radius)
    end,
}

local Act = {}

-- ---------------------------------------------------------------------------
-- GCD actions
-- ---------------------------------------------------------------------------

function Act.queue_frostbolt(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "frostbolt", "frostbolt", target, QueuePriorities.DEFAULT)
end

function Act.queue_fireball(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "fireball", "fireball", target, QueuePriorities.DEFAULT)
end

function Act.queue_fire_blast(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "fire_blast", "fire_blast", target, QueuePriorities.DEFAULT)
end

function Act.queue_frost_nova(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "frost_nova", "frost_nova", player, QueuePriorities.DEFAULT)
end

function Act.queue_cone_of_cold(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "cone_of_cold", "cone_of_cold", player, QueuePriorities.DEFAULT)
end

function Act.queue_blizzard(blackboard)
    -- Use AOE helper to find optimal position for maximum target hits
    local spell_id = H.spell_id_for(blackboard, "blizzard")
    if not spell_id then
        -- Fallback to original behavior if spell ID not found
        local _, target = H.player_and_target(blackboard)
        if not target then
            return Status.FAILURE
        end
        local ok_pos, pos = pcall(target.get_position, target)
        if not ok_pos or type(pos) ~= "table" then
            return Status.FAILURE
        end
        return H.queue_position(blackboard, "blizzard", "blizzard", pos, QueuePriorities.DEFAULT)
    end
    
    -- Try to get optimal position using AOE helper
    local optimal_pos, hit_count = AoeHelper.find_optimal_position(
        spell_id, 
        30,    -- Blizzard range
        2,     -- Minimum targets for AOE (lowered from 3 to be more permissive)
        6      -- Blizzard radius
    )
    
    -- If we found a good position with enough targets, use it
    if optimal_pos and hit_count >= 2 then
        return H.queue_position(blackboard, "blizzard", "blizzard", optimal_pos, QueuePriorities.DEFAULT)
    end
    
    -- Fallback to target position if AOE positioning doesn't find enough targets
    local _, target = H.player_and_target(blackboard)
    if not target then
        return Status.FAILURE
    end
    local ok_pos, pos = pcall(target.get_position, target)
    if not ok_pos or type(pos) ~= "table" then
        return Status.FAILURE
    end
    return H.queue_position(blackboard, "blizzard", "blizzard", pos, QueuePriorities.DEFAULT)
end

function Act.queue_ice_lance(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "ice_lance", "ice_lance", target, QueuePriorities.DEFAULT)
end

function Act.queue_counterspell(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "counterspell", "counterspell", target, QueuePriorities.INTERRUPT)
end

function Act.queue_ice_block(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "ice_block", "ice_block", player, QueuePriorities.DEFAULT)
end

function Act.queue_blink(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "blink", "blink", player, QueuePriorities.DEFAULT)
end

function Act.queue_mana_shield(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "mana_shield", "mana_shield", player, QueuePriorities.DEFAULT)
end

function Act.queue_evocation(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "evocation", "evocation", player, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- The off-GCD TREE -- which is a scheduling name, not a claim about the GCD
-- ---------------------------------------------------------------------------
--
-- These three sit under `frost_tbc.lua`'s off-GCD subtree, which is ticked every cycle rather than
-- once per global cooldown. That says when the rotation RECONSIDERS them. Whether the resulting
-- spell triggers the global cooldown is a separate question the game answers, and the two answers
-- do NOT agree across these three -- so `off_gcd` is declared per action, not per tree.
--
-- Measured in tbcmangos.sqlite (`spell_template`, TBC 2.4.3):
--
--     Icy Veins   12472                      StartRecoveryCategory 0    -> off the GCD
--     Cold Snap   11958                      StartRecoveryCategory 0    -> off the GCD
--     Ice Barrier 11426/13031/13032/13033/27134/33405
--                                            StartRecoveryCategory 133  -> ON the GCD
--
-- `H.queue_target` will not honour a declaration the kernel catalog denies, so this list cannot on
-- its own grant a bypass -- see the off-GCD section in frost_support.lua for why both must agree.

--- NO `off_gcd`, DELIBERATELY, and this is the line most likely to be "corrected" by someone
--- reading the section heading instead of the data. Ice Barrier is a mage shield, and every mage
--- shield triggers the global cooldown in TBC -- all six ranks carry StartRecoveryCategory 133.
--- `kernel/catalogs/spell.lua:36` currently claims otherwise (`gcd = false, ogcd = true`); it is
--- wrong, it is outside this package, and it is reported rather than edited here. Adding
--- `off_gcd = true` on this line is all it would take for the catalog's error to become a live
--- bypass, which is exactly why the declaration is required in the first place.
function Act.queue_ice_barrier(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "ice_barrier", "ice_barrier", player, QueuePriorities.DEFAULT, { fast = true })
end

function Act.queue_icy_veins(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "icy_veins", "icy_veins", player, QueuePriorities.DEFAULT,
        { fast = true, off_gcd = true })
end

function Act.queue_cold_snap(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "cold_snap", "cold_snap", player, QueuePriorities.DEFAULT,
        { fast = true, off_gcd = true })
end

-- ---------------------------------------------------------------------------
-- Maintenance actions
-- ---------------------------------------------------------------------------

function Act.queue_frost_armor(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "frost_armor", "frost_armor", player, QueuePriorities.DEFAULT)
end

function Act.queue_ice_armor(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "ice_armor", "ice_armor", player, QueuePriorities.DEFAULT)
end

function Act.queue_arcane_intellect(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "arcane_intellect", "arcane_intellect", player, QueuePriorities.DEFAULT)
end

function Act.queue_conjure_food(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "conjure_food", "conjure_food", player, QueuePriorities.DEFAULT)
end

function Act.queue_conjure_water(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "conjure_water", "conjure_water", player, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- Kill-secure actions (elevated priority)
-- ---------------------------------------------------------------------------

function Act.queue_fire_blast_kill(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "fire_blast_kill", "fire_blast", target, QueuePriorities.DEFAULT)
end

function Act.queue_ice_lance_frozen(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "ice_lance_frozen", "ice_lance", target, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- CC actions
-- ---------------------------------------------------------------------------

function Act.queue_polymorph(blackboard)
    local player = blackboard:get("player.object")
    local _, primary = H.player_and_target(blackboard)
    if not player then
        return Status.FAILURE
    end

    -- Find best secondary target to poly
    local ok_enemies, enemies = H.safe_call(player, "get_enemies_in_range", 30)
    if not ok_enemies or type(enemies) ~= "table" then
        return Status.FAILURE
    end

    local best_target = nil
    local best_dist = 999
    for _, enemy in ipairs(enemies) do
        local dominated = false

        -- Skip primary target
        if not dominated and primary then
            local ok_guid_a, guid_a = H.safe_call(enemy, "get_guid")
            local ok_guid_b, guid_b = H.safe_call(primary, "get_guid")
            if ok_guid_a and ok_guid_b and tostring(guid_a) == tostring(guid_b) then
                dominated = true
            end
        end

        -- Skip dead
        if not dominated then
            local ok_dead, dead = H.safe_call(enemy, "is_dead")
            if ok_dead and dead == true then dominated = true end
        end

        -- Skip already polymorphed
        if not dominated and AuraCatalog.has_any_debuff(enemy, AuraCatalog.polymorph_debuffs) then
            dominated = true
        end

        -- Skip bosses
        if not dominated then
            local ok_boss, is_boss = H.safe_call(enemy, "is_boss")
            if ok_boss and is_boss == true then dominated = true end
        end

        -- Pick closest
        if not dominated then
            local ok_dist, d = H.safe_call(enemy, "distance")
            if ok_dist and H.num(d) < best_dist then
                best_dist = H.num(d)
                best_target = enemy
            end
        end
    end

    if not best_target then
        return Status.FAILURE
    end

    return H.queue_target(blackboard, "polymorph", "polymorph", best_target, QueuePriorities.DEFAULT)
end

function Act.queue_polymorph_target(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "polymorph_target", "polymorph", target, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- Spellsteal
-- ---------------------------------------------------------------------------

function Act.queue_spellsteal(blackboard)
    local _, target = H.player_and_target(blackboard)
    return H.queue_target(blackboard, "spellsteal", "spellsteal", target, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- AoE actions
-- ---------------------------------------------------------------------------

function Act.queue_arcane_explosion(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "arcane_explosion", "arcane_explosion", player, QueuePriorities.DEFAULT)
end

function Act.queue_flamestrike(blackboard)
    -- Use AOE helper to find optimal position for maximum target hits
    local spell_id = H.spell_id_for(blackboard, "flamestrike")
    if not spell_id then
        -- Fallback to original behavior if spell ID not found
        local _, target = H.player_and_target(blackboard)
        if not target then
            return Status.FAILURE
        end
        local ok_pos, pos = H.safe_call(target, "get_position")
        if not ok_pos or type(pos) ~= "table" then
            return Status.FAILURE
        end
        return H.queue_position(blackboard, "flamestrike", "flamestrike", pos, QueuePriorities.DEFAULT)
    end
    
    -- Try to get optimal position using AOE helper
    local optimal_pos, hit_count = AoeHelper.find_optimal_position(
        spell_id, 
        30,    -- Flamestrike range
        2,     -- Minimum targets for AOE
        8      -- Flamestrike radius
    )
    
    -- If we found a good position with enough targets, use it
    if optimal_pos and hit_count >= 2 then
        return H.queue_position(blackboard, "flamestrike", "flamestrike", optimal_pos, QueuePriorities.DEFAULT)
    end
    
    -- Fallback to target position if AOE positioning doesn't find enough targets
    local _, target = H.player_and_target(blackboard)
    if not target then
        return Status.FAILURE
    end
    local ok_pos, pos = H.safe_call(target, "get_position")
    if not ok_pos or type(pos) ~= "table" then
        return Status.FAILURE
    end
    return H.queue_position(blackboard, "flamestrike", "flamestrike", pos, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- Ward / Summon / Utility
-- ---------------------------------------------------------------------------

function Act.queue_frost_ward(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "frost_ward", "frost_ward", player, QueuePriorities.DEFAULT)
end

function Act.queue_fire_ward(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "fire_ward", "fire_ward", player, QueuePriorities.DEFAULT)
end

function Act.queue_summon_water_elemental(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "summon_water_elemental", "summon_water_elemental", player, QueuePriorities.DEFAULT)
end

function Act.queue_invisibility(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "invisibility", "invisibility", player, QueuePriorities.DEFAULT)
end

-- ---------------------------------------------------------------------------
-- Mana gem conjure (maintenance, best rank by level)
-- ---------------------------------------------------------------------------

local CONJURE_GEM_SPELLS = {
    { key = "conjure_mana_emerald", min_level = 68 },
    { key = "conjure_mana_ruby",    min_level = 58 },
    { key = "conjure_mana_citrine", min_level = 48 },
    { key = "conjure_mana_jade",    min_level = 38 },
    { key = "conjure_mana_agate",   min_level = 28 },
}

function Act.queue_conjure_mana_gem(blackboard)
    local player = blackboard:get("player.object")
    local level = H.num(blackboard:get("player.level", 0))
    for _, entry in ipairs(CONJURE_GEM_SPELLS) do
        if level >= entry.min_level then
            local spell_id = H.spell_id_for(blackboard, entry.key)
            if spell_id then
                return H.queue_target(blackboard, "conjure_mana_gem", entry.key, player, QueuePriorities.DEFAULT)
            end
        end
    end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- Combat consumables (potions and the mana gem — items, not spells)
-- ---------------------------------------------------------------------------
--
-- ============================================================================
-- WHY THE TWO-MINUTE TIMER IS GONE
-- ============================================================================
-- Both actions used to track a hard-coded 120000 ms shared cooldown on
-- `combat.potion_cd_until_ms`, and gate themselves on it. The kernel's ITEMS gate asks
-- the client instead (`get_item_cooldown`), and the client is the one that actually
-- owns that number.
--
-- Two sources of truth for one fact do not merely duplicate -- they DIVERGE, and here in
-- both directions:
--
--   * TOO PERMISSIVE. A potion drunk by the human at the keyboard, or a trinket sharing
--     the potion cooldown, moves the client's number and not the blackboard's. The old
--     code then sent a packet into a live cooldown.
--   * TOO STRICT. Anything that clears the cooldown early leaves a stale blackboard
--     expiry vetoing a potion the client would have allowed.
--
-- The timer is therefore not re-implemented anywhere. `combat.potion_cd_until_ms` now has
-- NO writer -- see 08a_API_GAPS.md; three files still read it and each of those reads is
-- now permanently "ready".
--
-- ============================================================================
-- WHAT SUCCESS MEANS NOW
-- ============================================================================
-- SUCCESS is "the intent was accepted for this tick", not "the character drank". The
-- packet leaves later, in COMMIT, if the gate agrees. That is strictly more information
-- than before -- the old path could not tell a refusal from a drink, because it discarded
-- the SDK's return value inside a bare pcall.

--- The lease a potion acts under. ITEMS is a control channel, so drinking is an
--- authorised action rather than an ambient one: two plugins reaching for the same shared
--- potion cooldown in one tick is exactly the collision the broker exists to resolve.
---
--- COMBAT, not SURVIVAL, even though a health potion at 30% is defensive. The band is the
--- rotation's own; promoting these two entries into the defensive band is a separate,
--- arguable change and would not be measurable alongside the item conversion.
local ITEMS_LEASE = {
    channel = "ITEMS",
    owner = "sentinel.rotation.mage_frost",
    band = "COMBAT",
    offset = 0,
    tier = "rotation",
    ttl_ticks = 2,
}

---Emit a `use_item` intent under an ITEMS lease.
---
---THE LEASE IS DELIBERATELY NOT RELEASED HERE. `release` removes it from the broker's
---holdings, and the commit stage validates an intent's generation by looking its lease UP
---in those holdings -- so a tidy-looking release on the way out would make every intent
---this function submits fail its own generation check, one stage later and silently. The
---TTL retires the lease instead, which is what TTLs are for.
---@param item_id number
---@return boolean submitted
local function submit_use_item(item_id)
    local broker = API.control
    if not broker then return false end
    local caretaker = broker:acquire(ITEMS_LEASE)
    if not caretaker then return false end
    return caretaker:submit({ type = "use_item", payload = { item_id = item_id } }) == true
end

function Act.use_health_potion(blackboard)
    local pot_id = blackboard:get("combat.health_potion_id")
    if not pot_id then return Status.FAILURE end
    if submit_use_item(pot_id) then return Status.SUCCESS end
    return Status.FAILURE
end

function Act.use_mana_potion(blackboard)
    local pot_id = blackboard:get("combat.mana_potion_id")
    if not pot_id then return Status.FAILURE end
    if submit_use_item(pot_id) then return Status.SUCCESS end
    return Status.FAILURE
end

-- ============================================================================
-- THE MANA GEM, WHICH USED TO CALL A GLOBAL THAT DOES NOT EXIST
-- ============================================================================
-- This action lived a hundred lines further up, under a heading that announced the defect --
-- "direct spell_queue access" -- and called `SpellQueue.call("queue_item_self", ...)` twice, once
-- as a retry of itself. `frost_actions.lua` has never had a `local SpellQueue = require(...)`;
-- `modules/combat/spell_dispatcher.lua:2` is the file that does. So the moment a gem was actually in
-- the bag, the action threw `attempt to index a nil value (global 'SpellQueue')` -- and the retry,
-- being the identical call, could only ever throw the same way.
--
-- IT WAS UNTESTED, AND IT AUDITED CLEAN. `tests/kernel/test_plugin_core_access_audit.lua`'s
-- CORE_ACCESS_LEDGER matches `core.*`; an undefined global not spelled `core` is outside what it
-- looks at. Worth stating plainly: that audit's silence is evidence about `core` usage and about
-- nothing else. A `luacheck`-style undefined-global pass would have caught this in a second and the
-- repo does not run one.
--
-- MOVED RATHER THAN REWIRED IN PLACE. A gem is an item, so it takes the route the two potions
-- already take -- `submit_use_item`, one ITEMS lease, one `use_item` intent -- and it has to sit
-- below that helper to reach it. Nothing about the action's decision changed: same blackboard key,
-- same nil guard, same "no id, no gem" refusal.
--
-- WHAT CHANGED BEYOND NOT THROWING, and both are the item gate's doing rather than this action's:
-- the character is now asked whether the gem is actually in the bag (`has_item`), and the client is
-- asked for its real cooldown instead of nobody being asked at all.
--
-- The old `QueuePriorities.DEFAULT` argument is gone with the call that took it. A spell-queue
-- priority is not a thing a `use_item` intent carries -- the ITEMS lease's band is what arbitrates,
-- and it is COMBAT for the same reason the potions' is.
function Act.use_mana_gem(blackboard)
    local gem_id = blackboard:get("combat.mana_gem_item_id")
    if not gem_id then return Status.FAILURE end
    if submit_use_item(gem_id) then return Status.SUCCESS end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- Pet management (off-GCD commands)
-- ---------------------------------------------------------------------------

function Act.pet_attack(blackboard)
    local pet_ctrl = blackboard:get("module.combat.pet_controller")
    local target = blackboard:get("combat.target") or blackboard:get("player.target")
    if not pet_ctrl or not target then return Status.FAILURE end
    if pet_ctrl:already_sent_to(target) then return Status.FAILURE end
    pet_ctrl:attack(target)
    return Status.SUCCESS
end

function Act.pet_freeze(blackboard)
    local pet_ctrl = blackboard:get("module.combat.pet_controller")
    local target = blackboard:get("combat.target") or blackboard:get("player.target")
    if not pet_ctrl or not target then return Status.FAILURE end
    pet_ctrl:freeze(target)
    return Status.SUCCESS
end

function Act.pet_passive(blackboard)
    local pet_ctrl = blackboard:get("module.combat.pet_controller")
    if not pet_ctrl then return Status.FAILURE end
    pet_ctrl:passive()
    return Status.SUCCESS
end

-- ---------------------------------------------------------------------------
-- Add finishing (target low-HP secondary enemy with Fire Blast)
-- ---------------------------------------------------------------------------

--- One of the two sites that never used `H.queue_target`. The add is neither the player nor the
--- rotation's target, so before Phase 4c the intent vocabulary could not name it and this reached
--- `SpellDispatcher` directly. It now goes through the kernel like everything else; the unit travels
--- as a guid and is resolved back to a handle at commit.
function Act.finish_low_add(blackboard)
    local add = blackboard:get("combat.low_health_add")
    if not add then return Status.FAILURE end
    local spell_id = H.spell_id_for(blackboard, "fire_blast")
    if not spell_id then return Status.FAILURE end
    if H.queue_resolved_target(blackboard, "finish_low_add", spell_id, add, QueuePriorities.DEFAULT) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- Emergency escape (Blink + signal hard flee)
-- ---------------------------------------------------------------------------

--- The second direct site. SUCCESS here has never depended on the Blink landing -- the flee flag is
--- the action's real product and the cast is opportunistic -- so the return is unchanged.
function Act.emergency_escape(blackboard)
    blackboard:set("combat.emergency_flee", true)
    local player = blackboard:get("player.object")
    local blink_id = H.spell_id_for(blackboard, "blink")
    if blink_id and player then
        H.queue_resolved_target(blackboard, "emergency_blink", blink_id, player, QueuePriorities.DEFAULT)
    end
    return Status.SUCCESS
end

-- ---------------------------------------------------------------------------
-- Cast cancellation + kite start
-- ---------------------------------------------------------------------------

function Act.cancel_current_cast(blackboard)
    if core and core.input and type(core.input.move_forward_start) == "function" then
        pcall(core.input.move_forward_start)
        blackboard:set("combat._cancel_cast_pending", true)
        return Status.SUCCESS
    end
    return Status.FAILURE
end

function Act.start_kite(blackboard)
    blackboard:set("combat.kite_state", "NOVA_PENDING")
    blackboard:set("combat._kite_start_ms", blackboard:get("system.now_ms", 0))
    return Status.SUCCESS
end

-- ---------------------------------------------------------------------------
-- Fallback
-- ---------------------------------------------------------------------------

function Act.noop()
    return Status.FAILURE
end

return Act