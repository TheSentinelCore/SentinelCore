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
-- Off-GCD actions
-- ---------------------------------------------------------------------------

function Act.queue_ice_barrier(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "ice_barrier", "ice_barrier", player, QueuePriorities.DEFAULT, { fast = true })
end

function Act.queue_icy_veins(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "icy_veins", "icy_veins", player, QueuePriorities.DEFAULT, { fast = true })
end

function Act.queue_cold_snap(blackboard)
    local player = blackboard:get("player.object")
    return H.queue_target(blackboard, "cold_snap", "cold_snap", player, QueuePriorities.DEFAULT, { fast = true })
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
-- Mana gem USE (item, not spell — direct spell_queue access)
-- ---------------------------------------------------------------------------

function Act.use_mana_gem(blackboard)
    local gem_id = blackboard:get("combat.mana_gem_item_id")
    if not gem_id then
        return Status.FAILURE
    end

    -- Try queue_item_self(self, item_id, priority, message)
    local ok, result = SpellQueue.call("queue_item_self", gem_id, QueuePriorities.DEFAULT, "mana_gem")
    if not ok then
        ok, result = SpellQueue.call("queue_item_self", gem_id, QueuePriorities.DEFAULT, "mana_gem")
    end

    if ok and result ~= false then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- Combat consumables (potions — off-GCD items)
-- ---------------------------------------------------------------------------

function Act.use_health_potion(blackboard)
    local pot_id = blackboard:get("combat.health_potion_id")
    if not pot_id then return Status.FAILURE end
    local now = blackboard:get("system.now_ms", 0)
    local cd = blackboard:get("combat.potion_cd_until_ms", 0)
    if now < cd then return Status.FAILURE end
    if core and core.input and type(core.input.use_item) == "function" then
        pcall(core.input.use_item, pot_id)
        blackboard:set("combat.potion_cd_until_ms", now + 120000) -- 2min shared CD
        return Status.SUCCESS
    end
    return Status.FAILURE
end

function Act.use_mana_potion(blackboard)
    local pot_id = blackboard:get("combat.mana_potion_id")
    if not pot_id then return Status.FAILURE end
    local now = blackboard:get("system.now_ms", 0)
    local cd = blackboard:get("combat.potion_cd_until_ms", 0)
    if now < cd then return Status.FAILURE end
    if core and core.input and type(core.input.use_item) == "function" then
        pcall(core.input.use_item, pot_id)
        blackboard:set("combat.potion_cd_until_ms", now + 120000)
        return Status.SUCCESS
    end
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

function Act.finish_low_add(blackboard)
    local add = blackboard:get("combat.low_health_add")
    if not add then return Status.FAILURE end
    local d = H.dispatcher(blackboard)
    local spell_id = H.spell_id_for(blackboard, "fire_blast")
    if not d or not spell_id then
        return Status.FAILURE
    end
    if d:queue_target("finish_low_add", spell_id, add, QueuePriorities.DEFAULT, "finish_low_add") then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

-- ---------------------------------------------------------------------------
-- Emergency escape (Blink + signal hard flee)
-- ---------------------------------------------------------------------------

function Act.emergency_escape(blackboard)
    blackboard:set("combat.emergency_flee", true)
    local player = blackboard:get("player.object")
    local d = H.dispatcher(blackboard)
    local blink_id = H.spell_id_for(blackboard, "blink")
    if d and blink_id and player then
        d:queue_target("emergency_blink", blink_id, player, QueuePriorities.DEFAULT, "emergency_blink")
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