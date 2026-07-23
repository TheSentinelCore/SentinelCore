-- Unit D: Warlock Affliction TBC leveling profile.
-- Structural template: tests/modules/combat/test_retribution_tbc.lua (make_unit
-- helper) + test_condition_spell_available.lua (core.spell_book mock lifecycle).
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SpellCatalog = require("modules/combat/spell_catalog")
local Profile = require("modules/combat/profiles/warlock/affliction_tbc")
local Registry = require("modules/combat/profiles/registry")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return (opts.health_pct or 1.0) * 100 end
    function unit:is_dead() return opts.dead == true end
    function unit:get_target() return opts.target end
    function unit:has_debuff(spell_id)
        local debuffs = opts.debuffs or {}
        if type(spell_id) == "table" then
            for _, id in ipairs(spell_id) do
                if debuffs[id] then return true end
            end
            return false
        end
        return debuffs[spell_id] == true
    end
    function unit:get_debuffs() return {} end
    function unit:get_pet() return opts.pet end
    function unit:is_alive() return opts.alive ~= false end
    function unit:is_casting_spell() return false end
    function unit:is_channelling_spell() return false end
    return unit
end

local function set_spell_book(mock)
    _G.core = _G.core or {}
    _G.core.spell_book = mock
end

local function clear_spell_book()
    if _G.core then
        _G.core.spell_book = nil
    end
end

local function set_spell_helper()
    _G.spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
        get_spell_cooldown = function(_self, _spell_id)
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }
end

-- Known spell ids (from spell_catalog.lua, rank-ascending; verified via
-- tbcmangos.sqlite spell_chain, see D0 extraction):
local CORRUPTION_R1, CORRUPTION_MAX = 172, 27216
local CURSE_OF_AGONY_MAX = 27218
local IMMOLATE_MAX = 27215
local DRAIN_LIFE_MAX = 27220
local LIFE_TAP_MAX = 27222
local SHADOW_BOLT_R1, SHADOW_BOLT_MAX = 686, 27209
local SUMMON_VOIDWALKER = 697

-- The dispatcher mock's queue_target closure captures the `actions` TABLE
-- REFERENCE at fresh_bb() call time -- `actions = {}` between sub-scenarios
-- only rebinds the local variable and does nothing to what the closure
-- appends to. Clear in place instead when reusing one blackboard/profile
-- across multiple ticks within a single test function.
local function clear_actions(actions)
    for i = #actions, 1, -1 do
        actions[i] = nil
    end
end

local function fresh_bb(actions)
    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("module.combat.catalog", SpellCatalog:new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })
    bb:set("module.combat.dispatcher", {
        queue_target = function(_self, _action_id, spell_id, _target, _priority, message, _opts)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
    })
    return bb
end

function M.test_rotation_identity_full_spellbook()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    -- Single blackboard/profile reused across sub-scenarios (advancing
    -- system.now_ms each tick) -- mirrors test_retribution_tbc.lua's
    -- convention. A fresh Blackboard per tick would reset the GCD Cooldown
    -- decorator's key-based state on the blackboard, but the decorator falls
    -- back to its OWN instance field when the (new) blackboard has no stored
    -- value yet -- which would carry over stale cooldown state from the
    -- previous tick's SAME profile instance and spuriously block every
    -- subsequent tick.
    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    bb:set("player.object", player)
    bb:set("combat.target", make_unit({ guid = "target" }))

    local profile = Profile.build(bb, bus)

    -- No DoTs up yet -> Corruption wins (highest priority).
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "corruption_target", "Corruption is prioritized over CoA/Immolate")

    -- Corruption up, CoA/Immolate missing -> Curse of Agony next.
    clear_actions(actions)
    bb:set("system.now_ms", 1100)
    bb:set("combat.target", make_unit({ guid = "target", debuffs = { [CORRUPTION_MAX] = true } }))
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "curse_of_agony_target", "CoA queued once Corruption is up")

    -- Corruption + CoA up, Immolate missing -> Immolate next.
    clear_actions(actions)
    bb:set("system.now_ms", 1200)
    bb:set("combat.target", make_unit({ guid = "target", debuffs = { [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true } }))
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "immolate_target", "Immolate queued once Corruption+CoA are up")

    -- All three DoTs up, full mana -> Shadow Bolt filler.
    clear_actions(actions)
    bb:set("system.now_ms", 1300)
    bb:set("combat.target", make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } }))
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "shadow_bolt_target", "Shadow Bolt fires as filler once DoTs are maintained")

    clear_spell_book()
end

function M.test_sustain_drain_life_on_low_health()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    local target = make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } })
    bb:set("player.object", player)
    bb:set("combat.target", target)
    bb:set("player.health_pct", 0.30) -- below 0.40 sustain threshold

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "drain_life_target", "Drain Life fires ahead of filler when health is low")

    clear_spell_book()
end

function M.test_sustain_life_tap_on_low_mana()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    local target = make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } })
    bb:set("player.object", player)
    bb:set("combat.target", target)
    bb:set("player.mana_pct", 0.20)   -- below 0.30 life tap threshold
    bb:set("player.health_pct", 0.80) -- above both 0.40 (drain life) and 0.50 (life tap) thresholds

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "life_tap_self", "Life Tap fires when mana is low and health can afford it")

    clear_spell_book()
end

function M.test_wand_fallback_when_shadow_bolt_unknown()
    set_spell_helper()
    -- Shadow Bolt untrained; everything else known. Mana-rich, DoTs maintained,
    -- health/mana high enough that neither sustain spell fires.
    set_spell_book({
        is_spell_known = function(id)
            if id >= SHADOW_BOLT_R1 and id <= SHADOW_BOLT_MAX then
                -- crude range check would false-positive against other spells'
                -- ids; be explicit instead.
                return false
            end
            return true
        end,
    })
    -- Be explicit: only Shadow Bolt ranks are excluded.
    local SpellCatalogMod = SpellCatalog:new()
    local shadow_bolt_ids = {}
    for _, id in ipairs(SpellCatalogMod:get("shadow_bolt").ranks) do
        shadow_bolt_ids[id] = true
    end
    set_spell_book({
        is_spell_known = function(id) return not shadow_bolt_ids[id] end,
    })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    local target = make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } })
    bb:set("player.object", player)
    bb:set("combat.target", target)
    bb:set("player.mana_pct", 0.80)
    bb:set("player.health_pct", 1.0)

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "shoot_target", "Wand fires when Shadow Bolt is untrained")

    clear_spell_book()
end

function M.test_wand_fallback_when_mana_poor()
    set_spell_helper()
    -- Life Tap untrained too, so low mana can't be resolved by tapping -- wand
    -- must be the fallback rather than stalling on fallback_noop.
    local SpellCatalogMod = SpellCatalog:new()
    local life_tap_ids = {}
    for _, id in ipairs(SpellCatalogMod:get("life_tap").ranks) do
        life_tap_ids[id] = true
    end
    set_spell_book({
        is_spell_known = function(id) return not life_tap_ids[id] end,
    })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    local target = make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } })
    bb:set("player.object", player)
    bb:set("combat.target", target)
    bb:set("player.mana_pct", 0.10) -- too low for Shadow Bolt's mana_above(0.40) too
    bb:set("player.health_pct", 0.80)

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "shoot_target", "Wand fires when mana is too poor for Life Tap/Shadow Bolt")

    clear_spell_book()
end

function M.test_low_level_graceful_skip()
    set_spell_helper()
    -- Only Corruption rank 1 + Shadow Bolt rank 1 known -- everything else
    -- (Curse of Agony, Immolate, Drain Life, Life Tap, Summon Voidwalker)
    -- untrained. This must not error and must still select a legal action.
    set_spell_book({
        is_spell_known = function(id)
            return id == CORRUPTION_R1 or id == SHADOW_BOLT_R1
        end,
    })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player" })
    bb:set("player.object", player)
    bb:set("combat.target", make_unit({ guid = "target" }))

    local ok, profile = pcall(Profile.build, bb, bus)
    T.assert_true(ok, "Profile.build must not throw for a low-level spellbook")

    -- No debuffs yet -> only Corruption is trained and applicable.
    local tick_ok = pcall(function() profile:tick_gcd(bb) end)
    T.assert_true(tick_ok, "tick_gcd must not throw when most spells are untrained")
    T.assert_equal(actions[1].action, "corruption_target", "Known Corruption is queued; untrained DoTs are skipped cleanly")

    -- Corruption now up -> CoA/Immolate skip (untrained), Drain Life/Life Tap
    -- skip (untrained), Shadow Bolt (trained, mana-rich) should fire.
    -- Reuses the same blackboard/profile (see test_rotation_identity_full_spellbook
    -- for why a fresh Blackboard would spuriously trip the GCD Cooldown gate).
    clear_actions(actions)
    bb:set("system.now_ms", 1100)
    bb:set("combat.target", make_unit({ guid = "target", debuffs = { [CORRUPTION_R1] = true } }))
    local tick_ok2 = pcall(function() profile:tick_gcd(bb) end)
    T.assert_true(tick_ok2, "second tick_gcd must not throw")
    T.assert_equal(actions[1].action, "shadow_bolt_target",
        "Falls through untrained DoTs/sustain to the highest-priority trained action")

    clear_spell_book()
end

function M.test_resolve_known_rank_partial_spellbook()
    -- Direct SpellCatalog:resolve_known_rank unit check (not routed through the
    -- profile): a mid-leveled character knows ranks 1-4 of Corruption but not
    -- 5-8 -- resolve_known_rank must pick rank 4 (7648), not the max rank.
    set_spell_book({
        is_spell_known = function(id)
            return id == 172 or id == 6222 or id == 6223 or id == 7648
        end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("corruption"), 7648, "picks the highest KNOWN rank, not the catalog max")
    clear_spell_book()
end

function M.test_pet_summons_voidwalker_when_absent()
    set_spell_helper()
    set_spell_book({ is_spell_known = function(id) return id == SUMMON_VOIDWALKER end })

    local actions = {}
    local bb = fresh_bb(actions)
    local bus = EventBus:new()
    local player = make_unit({ guid = "player", pet = nil }) -- no pet yet
    bb:set("player.object", player)
    bb:set("combat.target", make_unit({ guid = "target" }))

    local profile = Profile.build(bb, bus)
    profile:tick_off_gcd(bb)
    T.assert_equal(actions[1].action, "summon_voidwalker_self", "Voidwalker is summoned when no pet is active")

    clear_spell_book()
end

function M.test_registry_resolves_warlock_class_id()
    local resolved = Registry.resolve(9)
    T.assert_equal(resolved, Profile, "class_id 9 resolves to the Warlock Affliction profile module")
end

return M
