-- tests/modules/combat/test_seal_availability.lua
-- Level 1-70 seal handling.
--
-- Captured live on 2026-07-23 from a level-3 Paladin (class_id 2) in Elwynn:
--   spell book = 6603 (Attack), 635 (Holy Light), 465 (Devotion Aura), 20154 (Seal of Righteousness)
--   catalog:resolve_best_rank("seal_of_blood")  -> nil   (31892 not known until 64)
--   catalog:resolve_best_rank("seal_of_command") -> nil  (talent)
--   catalog:resolve_best_rank("seal_of_righteousness") -> 20154
--
-- ContextBuilder nonetheless published rotation.desired_seal = "blood", so
-- apply_seal_before_combat (which requires seal_of_blood to be castable) never
-- fired, no seal was ever active, and judgement -- gated on active_seal_present --
-- was permanently dead. The rotation collapsed to auto-attack at every level
-- below 64. desired_seal must be resolved against spells the character ACTUALLY
-- knows, preferring blood > command > righteousness.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local ContextBuilder = require("modules/combat/context_builder")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    unit._hostile = opts.hostile == true
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:is_dead() return false end
    function unit:has_buff() return false end
    function unit:get_buff_data() return { is_active = false, stack_count = 0 } end
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    function unit:is_in_combat() return opts.in_combat == true end
    function unit:is_enemy_with(other) return unit._hostile == true and other ~= nil end
    function unit:can_attack(other) return other and other._hostile == true end
    return unit
end

--- Catalog stub that only resolves the seal keys listed in `known`.
local function make_catalog(known)
    return {
        resolve_best_rank = function(_, key) return known[key] end,
        resolve_lowest_rank = function(_, key) return known[key] end,
    }
end

--- Blackboard primed for an in-combat single-target context.
local function make_bb(catalog, preference)
    local bb = Blackboard:new()
    local player = make_unit({ in_combat = true })
    local target = make_unit({ position = { x = 3, y = 0, z = 0 }, hostile = true, in_combat = true })

    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_casting", false)
    bb:set("player.is_channeling", false)
    bb:set("module.combat.enable_burst", true)
    bb:set("module.combat.primary_seal_preference", preference or "blood")
    bb:set("module.combat.cooldowns", { is_gcd_ready = function() return true end })
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.target", target)
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("system.now_ms", 1000)
    if catalog then
        bb:set("module.combat.catalog", catalog)
    end
    return bb
end

--- Level 3: only Seal of Righteousness is trainable.
function M.test_low_level_falls_back_to_righteousness()
    local bb = make_bb(make_catalog({ seal_of_righteousness = 20154 }))
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), "righteousness")
end

--- Level 64+ Blood Elf: Seal of Blood known, so the preference stands.
function M.test_high_level_keeps_blood()
    local bb = make_bb(make_catalog({
        seal_of_blood = 31892,
        seal_of_command = 20375,
        seal_of_righteousness = 20154,
    }))
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), "blood")
end

--- Level 20-63 with the Ret talent: no Seal of Blood yet, Command is the best known.
function M.test_mid_level_prefers_command_over_righteousness()
    local bb = make_bb(make_catalog({
        seal_of_command = 20375,
        seal_of_righteousness = 20154,
    }))
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), "command")
end

--- AoE wants Command, but a character that has not learned it must not be told to
--- cast it -- it degrades to the best seal it actually has.
function M.test_aoe_does_not_demand_unlearned_command()
    local bb = make_bb(make_catalog({ seal_of_righteousness = 20154 }))
    bb:set("combat.enemy_count_10yd", 3)
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), "righteousness")
end

--- No catalog on the blackboard (offline tests, early boot) must not regress the
--- existing behaviour: the raw preference is published unchanged.
function M.test_no_catalog_keeps_preference()
    local bb = make_bb(nil)
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), "blood")
end

--- A character with no seals at all must publish nil rather than a seal it cannot cast.
function M.test_no_known_seal_publishes_nil()
    local bb = make_bb(make_catalog({}))
    ContextBuilder:new(bb):refresh(EventBus:new())
    T.assert_equal(bb:get("rotation.desired_seal"), nil)
end

-- ============================================================================
-- End-to-end: the GCD tree of a level-3 Paladin must actually queue a seal.
-- This is the behaviour the live client proved broken -- combat reached ENGAGING
-- with a valid target and queued nothing at all, falling through to auto-attack.
-- ============================================================================

local Profile = require("modules/combat/profiles/paladin/retribution_tbc")
local SpellCatalog = require("kernel/catalogs/spell")

local function make_rotation_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:get_target() return nil end
    function unit:has_buff(buff_id)
        local buffs = opts.buffs or {}
        if type(buff_id) == "table" then
            for _, id in ipairs(buff_id) do
                if buffs[id] then return true end
            end
            return false
        end
        return buffs[buff_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return false end
    function unit:is_channelling_spell() return false end
    function unit:is_active_spell_interruptable() return true end
    return unit
end

--- Drive one GCD tick for a Paladin whose spell book contains only `known_ids`.
--- Returns the list of queued actions.
local function tick_gcd_with_spellbook(known_ids)
    local previous_has_spell = _G.core.spell_book.has_spell
    _G.core.spell_book.has_spell = function(spell_id)
        return known_ids[spell_id] == true
    end

    local actions = {}
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local player = make_rotation_unit({ guid = "player" })
    local target = make_rotation_unit({ guid = "target", position = { x = 3, y = 0, z = 0 }, health_pct = 1.0 })

    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("combat.swing.remaining_ms", 999)
    bb:set("rotation.active_seal", nil)
    bb:set("module.combat.primary_seal_preference", "blood")
    bb:set("module.combat.catalog", SpellCatalog:new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })
    bb:set("module.combat.dispatcher", {
        queue_target = function(_self, _action_id, spell_id, _target, _priority, message)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
    })

    -- Publish the level-aware primary seal the same way the live loop does.
    ContextBuilder:new(bb):refresh(bus)

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)

    _G.core.spell_book.has_spell = previous_has_spell
    return actions, bb
end

--- Level 3: only Seal of Righteousness (20154) is in the spell book.
function M.test_level_3_paladin_queues_righteousness()
    package.loaded["modules/combat/profiles/paladin/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil

    local actions, bb = tick_gcd_with_spellbook({ [20154] = true })
    T.assert_equal(bb:get("rotation.primary_seal"), "righteousness")
    T.assert_true(#actions > 0, "level-3 Paladin must queue something, not fall through to noop")
    T.assert_equal(actions[1].action, "seal_of_righteousness")
    T.assert_equal(actions[1].spell_id, 20154)
end

--- Level 64+: Seal of Blood is known, so the level-70 behaviour is unchanged.
function M.test_level_70_paladin_still_queues_blood()
    package.loaded["modules/combat/profiles/paladin/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil

    local actions, bb = tick_gcd_with_spellbook({ [31892] = true, [20154] = true, [20271] = true })
    T.assert_equal(bb:get("rotation.primary_seal"), "blood")
    T.assert_equal(actions[1].action, "seal_of_blood")
    T.assert_equal(actions[1].spell_id, 31892)
end

return M
