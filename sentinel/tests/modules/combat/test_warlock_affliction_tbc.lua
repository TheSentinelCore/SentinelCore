-- Warlock Affliction TBC leveling profile, after the port onto the kernel architecture.
--
-- ================================================================================
-- WHAT CHANGED IN THIS FILE, AND WHY EACH CHANGE WAS FORCED
-- ================================================================================
-- Every ASSERTION below is the one that was here before the port. The HARNESS underneath them is
-- new, because two things the old harness stood on stopped existing:
--
--  1. THE DISPATCHER IS GONE. Casts used to reach `module.combat.dispatcher` off the blackboard, so
--     a table with a `queue_target` function was enough to observe them. They now leave as `cast`
--     intents under a CASTING lease and reach `spell_queue` at COMMIT, one stage later. So the
--     recorder moved from the dispatcher to the SDK verb the kernel's executor calls, and every pin
--     drains the queue before it looks.
--
--     The recorded shape is UNCHANGED -- `{ spell_id, action }` -- because
--     `intent_executors.lua:530` passes `payload.label` to the SDK as its `message` argument, and
--     `payload.label` is the rotation's own action id. `corruption_target` still says
--     `corruption_target`.
--
--  2. HEALTH READS THE FROZEN SNAPSHOT. `Cond.health_below` / `health_above` resolve through
--     `Sentinel.cond` against the tick's snapshot instead of `blackboard:get("player.health_pct", 0)`.
--     So the health figure a scenario sets up moved from the blackboard to a frozen snapshot.
--
--     THE ONE DELIBERATE BEHAVIOUR CHANGE IN THE PORT lives here, and only in the "no reading" case.
--     The blackboard default of 0 meant UNREADABLE HEALTH READ AS 0%: on any tick the sensor had not
--     filled the key, `health_below(0.40)` answered true and the warlock channelled Drain Life
--     instead of casting, while `health_above(0.50)` answered false and blocked Life Tap at the same
--     moment. The snapshot answers Unknown, and the call site resolves it with `TreatFalse` -- so an
--     unreadable tick now behaves as "not an emergency" rather than as "at death's door".
--     `test_health_gates_are_closed_when_health_is_unreadable` pins that directly.
--
-- WHAT IS DELIBERATELY NOT PINNED HERE: WHEN the packet leaves. In the dispatcher era the SDK call
-- happened inside the action; now it happens at COMMIT. Every pin commits before asserting, so the
-- ordering difference is invisible to this file on purpose -- the two-phase timing is pinned in
-- tests/kernel/test_scheduler.lua.
--
-- Structural template: tests/rotations/mage_frost/test_frost_cast_intents.lua (the kernel harness)
-- + this file's own pre-port scenarios (the assertions).

local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local ControlBroker = require("kernel/control_broker")
local EventBus = require("core/event_bus")
local Executors = require("kernel/intent_executors")
local IntentQueue = require("kernel/intent_queue")
local Snapshot = require("kernel/snapshot")
local SpellCatalog = require("kernel/catalogs/spell")
local SpellHelper = require("shared/spell_helper")
local Spells = require("kernel/spells")
local Units = require("kernel/units")
local PetCtrl = require("rotations/warlock_affliction/pet_controller")
local Profile = require("rotations/warlock_affliction/affliction_tbc")
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
local SHADOW_BOLT_R1, SHADOW_BOLT_MAX = 686, 27209
local SUMMON_VOIDWALKER = 697

--- Clear an action log in place. The recorder closure captures the TABLE REFERENCE, so
--- `actions = {}` between sub-scenarios would only rebind the local and leave the closure appending
--- to the old one.
local function clear_actions(actions)
    for i = #actions, 1, -1 do
        actions[i] = nil
    end
end

-- ---------------------------------------------------------------------------
-- The kernel harness
-- ---------------------------------------------------------------------------
--
-- A REAL ControlBroker, a REAL IntentQueue with the REAL executors installed, and a REAL
-- `_G.Sentinel` published over them. The only doubles are the SDK boundary itself (`spell_queue`,
-- the object manager, the handles they hand back), because that boundary is the one thing that
-- cannot exist offline. A fake intent queue would prove the rotation emits a table -- not that the
-- kernel would accept it, gate it, resolve its unit ref, or reach the verb the rotation meant.

---@param opts table|nil { health_pct?, mana_pct?, in_combat?, target?, pet?, unreadable_health? }
---@param body fun(h: table)
local function with_kernel(opts, body)
    opts = opts or {}
    local saved_surface = _G.Sentinel

    local actions = {}
    local function record(spell_id, unit, priority, message)
        actions[#actions + 1] = {
            spell_id = spell_id, action = message, unit = unit, priority = priority,
        }
        return true
    end

    -- The SDK verbs the kernel's cast executor calls. Both are recorded: `fast` picks the second,
    -- and a pin that watched only one would go quiet rather than red if the flag ever appeared.
    local spell_queue = {}
    function spell_queue:queue_spell_target(id, unit, priority, message)
        return record(id, unit, priority, message)
    end
    function spell_queue:queue_spell_target_fast(id, unit, priority, message)
        return record(id, unit, priority, message)
    end

    local bb = Blackboard:new()
    bb:set("system.now_ms", 1000)
    bb:set("player.mana_pct", opts.mana_pct or 1.0)
    bb:set("player.in_combat", opts.in_combat ~= false)
    bb:set("module.combat.catalog", SpellCatalog:new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })

    local player = make_unit({ guid = "player", pet = opts.pet })
    bb:set("player.object", player)
    if opts.target ~= false then
        bb:set("combat.target", opts.target or make_unit({ guid = "target" }))
    end

    local queue = IntentQueue:new()
    local broker = ControlBroker:new({ intent_queue = queue })
    -- ADR 08 §6.1 -- the revocation race check, wired exactly as runtime/app.lua wires it.
    queue:set_generation_validator(function(intent)
        return broker:is_generation_valid(intent)
    end)

    local pet_calls = {}
    Executors.install({
        intent_queue = queue,
        spell_queue = spell_queue,
        object_manager = {
            get_local_player = function() return bb:get("player.object") end,
            -- Resolved LIVE off the blackboard rather than from a captured table: several scenarios
            -- swap `combat.target` between ticks (a fresh mob with new debuffs), and a captured map
            -- would resolve the guid back to the mob the previous tick was aimed at.
            get_object_from_guid = function(guid)
                if guid == "player" then return bb:get("player.object") end
                if guid == "target" then return bb:get("combat.target") end
                return nil
            end,
        },
        unit_target = function() return bb:get("combat.target") or bb:get("player.target") end,
        spell_helper = { is_spell_castable = function() return true end },
        input = {
            pet_attack = function(unit)
                pet_calls[#pet_calls + 1] = { verb = "pet_attack", unit = unit }
                return true
            end,
            set_pet_passive = function()
                pet_calls[#pet_calls + 1] = { verb = "set_pet_passive" }
                return true
            end,
            set_pet_follow = function()
                pet_calls[#pet_calls + 1] = { verb = "set_pet_follow" }
                return true
            end,
        },
    })

    -- ONE snapshot for the whole scenario, so the tick a unit ref is MINTED under is the tick COMMIT
    -- runs under. Two would make every cast stale -- which is the generation check working, but it
    -- would be measuring the harness rather than the rotation.
    local builder = Snapshot.builder({ tick_index = 1 })
    if not opts.unreadable_health then
        builder:put("player.available", true)
        builder:put("player.health_pct", opts.health_pct or 1.0)
    end
    local frozen = builder:freeze()

    _G.Sentinel = Api.build({
        blackboard = bb,
        broker = broker,
        intent_queue = queue,
        spell_catalog = SpellCatalog:new(),
        scheduler = { current_snapshot = function() return frozen end },
        units = Units:new(),
        -- `Cond.spell_ready` asks `Sentinel.spells`, which reaches `shared/spell_helper`, which
        -- reads the `_G.spell_helper` the scenarios install. Wiring it keeps `set_spell_helper()`
        -- meaningful; omitting it would make the castability check fail OPEN and the scenarios
        -- would stop testing what they say they test.
        spells = Spells:new({ spell_helper = SpellHelper }),
    })

    local h = {
        bb = bb,
        actions = actions,
        pet_calls = pet_calls,
        queue = queue,
        broker = broker,
        player = player,
        commit = function() return queue:commit(frozen) end,
        called = function(verb)
            for _, c in ipairs(pet_calls) do
                if c.verb == verb then return c end
            end
            return nil
        end,
    }

    ---Run a tree and drain whatever it queued. A no-op in the dispatcher era, where the packet had
    ---already left by the time the action returned.
    h.tick_gcd = function(profile)
        local status = profile:tick_gcd(bb)
        h.commit()
        return status
    end
    h.tick_off_gcd = function(profile)
        local status = profile:tick_off_gcd(bb)
        h.commit()
        return status
    end

    local ok, err = pcall(body, h)
    _G.Sentinel = saved_surface
    if not ok then error(err, 0) end
end

-- ---------------------------------------------------------------------------
-- The rotation identity
-- ---------------------------------------------------------------------------

function M.test_rotation_identity_full_spellbook()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    -- Single blackboard/profile reused across sub-scenarios (advancing system.now_ms each tick) --
    -- a fresh Blackboard per tick would reset the GCD Cooldown decorator's key-based state, and the
    -- decorator would then fall back to its OWN instance field, carrying stale cooldown state from
    -- the previous tick's SAME profile instance and spuriously blocking every subsequent tick.
    with_kernel(nil, function(h)
        local profile = Profile.build(h.bb, EventBus:new())

        -- No DoTs up yet -> Corruption wins (highest priority).
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "corruption_target",
            "Corruption is prioritized over CoA/Immolate")

        -- Corruption up, CoA/Immolate missing -> Curse of Agony next.
        clear_actions(h.actions)
        h.bb:set("system.now_ms", 1100)
        h.bb:set("combat.target", make_unit({ guid = "target", debuffs = { [CORRUPTION_MAX] = true } }))
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "curse_of_agony_target",
            "CoA queued once Corruption is up")

        -- Corruption + CoA up, Immolate missing -> Immolate next.
        clear_actions(h.actions)
        h.bb:set("system.now_ms", 1200)
        h.bb:set("combat.target", make_unit({ guid = "target", debuffs = {
            [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true,
        } }))
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "immolate_target",
            "Immolate queued once Corruption+CoA are up")

        -- All three DoTs up, full mana -> Shadow Bolt filler.
        clear_actions(h.actions)
        h.bb:set("system.now_ms", 1300)
        h.bb:set("combat.target", make_unit({ guid = "target", debuffs = {
            [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
        } }))
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "shadow_bolt_target",
            "Shadow Bolt fires as filler once DoTs are maintained")
    end)

    clear_spell_book()
end

local function target_with_all_dots()
    return make_unit({ guid = "target", debuffs = {
        [CORRUPTION_MAX] = true, [CURSE_OF_AGONY_MAX] = true, [IMMOLATE_MAX] = true,
    } })
end

function M.test_sustain_drain_life_on_low_health()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    -- 0.30 is below the 0.40 sustain threshold.
    with_kernel({ health_pct = 0.30, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "drain_life_target",
            "Drain Life fires ahead of filler when health is low")
    end)

    clear_spell_book()
end

function M.test_sustain_life_tap_on_low_mana()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    -- mana below 0.30 (life tap threshold), health above both 0.40 (drain life) and 0.50 (life tap).
    with_kernel({ mana_pct = 0.20, health_pct = 0.80, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "life_tap_self",
            "Life Tap fires when mana is low and health can afford it")
    end)

    clear_spell_book()
end

function M.test_drain_life_recovery_when_low_mana_and_low_hp()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    -- The wedge: HP below 50% blocks Life Tap (health_above(0.50)) and HP above 40% blocks
    -- drain_life_sustain (health_below(0.40)); with mana below 30% Shadow Bolt is unaffordable too,
    -- so the lock wanded forever. The recovery branch must convert enemy HP into ours via Drain Life.
    with_kernel({ mana_pct = 0.20, health_pct = 0.45, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "drain_life_target",
            "Drain Life recovery must fire when mana < 30% and HP < 50%")
    end)

    clear_spell_book()
end

function M.test_wand_final_fallback_when_drain_life_untrained_in_wedge()
    set_spell_helper()
    -- Same wedge, but Drain Life untrained: wand must remain the final fallback.
    local SpellCatalogMod = SpellCatalog:new()
    local drain_life_ids = {}
    for _, id in ipairs(SpellCatalogMod:get("drain_life").ranks) do
        drain_life_ids[id] = true
    end
    set_spell_book({
        is_spell_known = function(id) return not drain_life_ids[id] end,
    })

    with_kernel({ mana_pct = 0.20, health_pct = 0.45, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "shoot_target",
            "Wand stays the final fallback when Drain Life is untrained in the wedge")
    end)

    clear_spell_book()
end

function M.test_wand_fallback_when_shadow_bolt_unknown()
    set_spell_helper()
    -- Shadow Bolt untrained; everything else known. Mana-rich, DoTs maintained, health/mana high
    -- enough that neither sustain spell fires. Be explicit about the excluded ids rather than using
    -- a range check, which would false-positive against other spells' ids.
    local SpellCatalogMod = SpellCatalog:new()
    local shadow_bolt_ids = {}
    for _, id in ipairs(SpellCatalogMod:get("shadow_bolt").ranks) do
        shadow_bolt_ids[id] = true
    end
    T.assert_true(shadow_bolt_ids[SHADOW_BOLT_R1] and shadow_bolt_ids[SHADOW_BOLT_MAX],
        "the exclusion set must cover the whole Shadow Bolt rank chain")
    set_spell_book({
        is_spell_known = function(id) return not shadow_bolt_ids[id] end,
    })

    with_kernel({ mana_pct = 0.80, health_pct = 1.0, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "shoot_target", "Wand fires when Shadow Bolt is untrained")
    end)

    clear_spell_book()
end

function M.test_wand_fallback_when_mana_poor()
    set_spell_helper()
    -- Life Tap untrained too, so low mana can't be resolved by tapping -- wand must be the fallback
    -- rather than stalling on fallback_noop.
    local SpellCatalogMod = SpellCatalog:new()
    local life_tap_ids = {}
    for _, id in ipairs(SpellCatalogMod:get("life_tap").ranks) do
        life_tap_ids[id] = true
    end
    set_spell_book({
        is_spell_known = function(id) return not life_tap_ids[id] end,
    })

    -- mana too low for Shadow Bolt's mana_above(0.40) as well.
    with_kernel({ mana_pct = 0.10, health_pct = 0.80, target = target_with_all_dots() }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "shoot_target",
            "Wand fires when mana is too poor for Life Tap/Shadow Bolt")
    end)

    clear_spell_book()
end

function M.test_low_level_graceful_skip()
    set_spell_helper()
    -- Only Corruption rank 1 + Shadow Bolt rank 1 known -- everything else (Curse of Agony,
    -- Immolate, Drain Life, Life Tap, Summon Voidwalker) untrained. This must not error and must
    -- still select a legal action.
    set_spell_book({
        is_spell_known = function(id)
            return id == CORRUPTION_R1 or id == SHADOW_BOLT_R1
        end,
    })

    with_kernel(nil, function(h)
        local ok, profile = pcall(Profile.build, h.bb, EventBus:new())
        T.assert_true(ok, "Profile.build must not throw for a low-level spellbook")

        -- No debuffs yet -> only Corruption is trained and applicable.
        local tick_ok = pcall(function() h.tick_gcd(profile) end)
        T.assert_true(tick_ok, "tick_gcd must not throw when most spells are untrained")
        T.assert_equal(h.actions[1].action, "corruption_target",
            "Known Corruption is queued; untrained DoTs are skipped cleanly")

        -- Corruption now up -> CoA/Immolate skip (untrained), Drain Life/Life Tap skip (untrained),
        -- Shadow Bolt (trained, mana-rich) should fire.
        clear_actions(h.actions)
        h.bb:set("system.now_ms", 1100)
        h.bb:set("combat.target", make_unit({ guid = "target", debuffs = { [CORRUPTION_R1] = true } }))
        local tick_ok2 = pcall(function() h.tick_gcd(profile) end)
        T.assert_true(tick_ok2, "second tick_gcd must not throw")
        T.assert_equal(h.actions[1].action, "shadow_bolt_target",
            "Falls through untrained DoTs/sustain to the highest-priority trained action")
    end)

    clear_spell_book()
end

function M.test_resolve_known_rank_partial_spellbook()
    -- Direct SpellCatalog:resolve_known_rank unit check (not routed through the profile): a
    -- mid-leveled character knows ranks 1-4 of Corruption but not 5-8 -- resolve_known_rank must
    -- pick rank 4 (7648), not the max rank.
    set_spell_book({
        is_spell_known = function(id)
            return id == 172 or id == 6222 or id == 6223 or id == 7648
        end,
    })
    local catalog = SpellCatalog:new()
    T.assert_equal(catalog:resolve_known_rank("corruption"), 7648,
        "picks the highest KNOWN rank, not the catalog max")
    clear_spell_book()
end

-- ---------------------------------------------------------------------------
-- The health gates, now read from the frozen snapshot
-- ---------------------------------------------------------------------------

--- THE ONE BEHAVIOUR THE PORT DELIBERATELY CHANGED.
---
--- The blackboard version defaulted `player.health_pct` to 0, so a tick on which the sensor had not
--- filled the key read as 0% health: `health_below(0.40)` fired Drain Life and `health_above(0.50)`
--- blocked Life Tap, both driven by an absent reading rather than by danger. `Sentinel.cond` answers
--- Unknown instead, and `Truth.Policy.TreatFalse` at the call site turns that into "not an
--- emergency".
---
--- Asserted through the ROTATION rather than the condition, because that is where the consequence
--- lives: with mana at 20% and health unreadable, neither sustain branch may claim the tick -- the
--- wand does, exactly as it would for a healthy warlock too poor to cast.
function M.test_health_gates_are_closed_when_health_is_unreadable()
    set_spell_helper()
    set_spell_book({ is_spell_known = function() return true end })

    with_kernel({
        unreadable_health = true, mana_pct = 0.20, target = target_with_all_dots(),
    }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "shoot_target",
            "an unreadable health snapshot must not fire Drain Life or block Life Tap")
    end)

    clear_spell_book()
end

-- ---------------------------------------------------------------------------
-- The pet, through the off-GCD tree
-- ---------------------------------------------------------------------------

function M.test_pet_summons_voidwalker_when_absent()
    set_spell_helper()
    -- Summon is gated out-of-combat AND "usable" (Soul Shard reagent present).
    set_spell_book({
        is_spell_known = function(id) return id == SUMMON_VOIDWALKER end,
        is_usable_spell = function() return true end,
    })

    with_kernel({ in_combat = false, pet = nil }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_off_gcd(profile)
        T.assert_equal(h.actions[1].action, "summon_voidwalker_self",
            "Voidwalker is summoned when no pet is active")
    end)

    clear_spell_book()
end

function M.test_no_summon_mid_combat()
    set_spell_helper()
    set_spell_book({
        is_spell_known = function(id) return id == SUMMON_VOIDWALKER end,
        is_usable_spell = function() return true end,
    })

    with_kernel({ pet = nil }, function(h)  -- in_combat defaults true
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_off_gcd(profile)
        T.assert_equal(h.actions[1], nil,
            "the summon cast must not fire mid-combat (it stalls the chase)")
    end)

    clear_spell_book()
end

function M.test_no_summon_without_shard_falls_back_petless()
    set_spell_helper()
    -- Trained but NOT usable (zero Soul Shards): the summon must not retry forever — combat
    -- proceeds pet-less.
    set_spell_book({
        is_spell_known = function() return true end,
        is_usable_spell = function() return false end,
    })

    with_kernel({ in_combat = false, pet = nil }, function(h)
        local profile = Profile.build(h.bb, EventBus:new())
        h.tick_off_gcd(profile)
        T.assert_equal(h.actions[1], nil, "no summon may be queued without a Soul Shard")

        -- Pet-less combat still works: the GCD rotation is unaffected.
        h.tick_gcd(profile)
        T.assert_equal(h.actions[1].action, "corruption_target",
            "the rotation must proceed pet-less when the summon is not usable")
    end)

    clear_spell_book()
end

-- ---------------------------------------------------------------------------
-- The pet controller, command by command
-- ---------------------------------------------------------------------------
--
-- REWRITTEN, and the reason is the conversion rather than the assertions. `passive()` used to call
-- `core.input.set_pet_passive` / `set_pet_follow` itself with the results DISCARDED, so a missing
-- pet, a dead pet or a vanished target all produced silence. Commands now leave as `pet_command`
-- intents under a PET lease, and the kernel refuses each of those BY NAME before the SDK is touched.
--
-- Every CLAIM the old test made survives -- passive() transitions state, both verbs are sent in
-- order, the sent guid is cleared, and an absent SDK never throws. What changed is that they are
-- observed after COMMIT rather than at the call, because that is where the packet now leaves.

function M.test_pet_controller_passive_recall()
    set_spell_helper()
    with_kernel({ pet = make_unit({ guid = "pet" }) }, function(h)
        local ctrl = PetCtrl:new()
        ctrl:attack(make_unit({ guid = "t" }))
        h.commit()

        local ok, reason = ctrl:passive()
        T.assert_true(ok, "both recall commands must be accepted: " .. tostring(reason))
        T.assert_equal(ctrl:get_state(), "passive", "passive() must transition the controller state")

        local report = h.commit()
        T.assert_equal(#report.committed, 2, "passive and follow are two intents, and both commit")
        T.assert_equal(report.committed[1].payload.command, "passive", "passive goes first")
        T.assert_equal(report.committed[2].payload.command, "follow",
            "follow goes second, so the pet returns")
        T.assert_not_nil(h.called("set_pet_passive"), "passive() must send set_pet_passive")
        T.assert_not_nil(h.called("set_pet_follow"), "passive() must send set_pet_follow")

        T.assert_false(ctrl:already_sent_to(make_unit({ guid = "t" })),
            "recall must clear the sent guid so the next engagement re-sends attack")
    end)
end

--- The old test proved "SDK absence must never error" by deleting `_G.core`. The controller no
--- longer names `core` at all, so the equivalent claim is about the KERNEL being absent -- and it is
--- a stronger one: an unauthorised command is now REFUSED BY NAME rather than sent on ambient
--- authority, which is the whole return on the conversion.
function M.test_pet_controller_is_safe_and_named_without_a_kernel()
    local saved = _G.Sentinel
    _G.Sentinel = nil

    local ctrl = PetCtrl:new()
    local ok_call, ok, reason, results = pcall(function()
        return ctrl:passive()
    end)
    _G.Sentinel = saved

    T.assert_true(ok_call, "passive() must not throw when the kernel is absent")
    T.assert_false(ok, "no broker means no authority")
    T.assert_equal(reason, "no_control", "and the refusal must be named, not swallowed")
    T.assert_equal(#results, 0, "a lease that was never granted commands nothing")
    T.assert_equal(ctrl:get_state(), "passive",
        "the local state machine is unchanged by the conversion")
end

--- ADR 08 §2.7 / invariant 2: a handle in an intent payload is a defect even when it works, because
--- the pointer can die inside the tick that produced it.
function M.test_a_pet_command_names_its_unit_symbolically_and_carries_no_handle()
    set_spell_helper()
    with_kernel({ pet = make_unit({ guid = "pet" }) }, function(h)
        local live_handle = make_unit({ guid = "mob1" })
        PetCtrl:new():attack(live_handle)

        T.assert_equal(h.queue:pending_count(), 1, "exactly one intent must be pending")
        local intent = h.queue._pending[1]
        T.assert_equal(intent.type, "pet_command")
        T.assert_equal(intent.payload.command, "attack")
        T.assert_equal(intent.payload.unit, "target", "the unit must be the symbolic reference")

        for key, value in pairs(intent.payload) do
            T.assert_true(type(value) ~= "table" and type(value) ~= "userdata",
                "payload field '" .. tostring(key) .. "' carries a handle-shaped value")
        end

        h.commit()
        T.assert_not_nil(h.called("pet_attack"), "and the SDK verb is reached at commit")
    end)
end

--- Old behaviour: `pcall(core.input.pet_attack, target)` with no pet did nothing and said nothing.
--- Now the gate refuses it, by name, before the SDK is touched.
function M.test_a_pet_command_with_no_pet_is_refused_by_name()
    set_spell_helper()
    with_kernel({ pet = nil }, function(h)
        PetCtrl:new():attack(make_unit({ guid = "mob1" }))
        local report = h.commit()
        T.assert_equal(#report.committed, 0)
        T.assert_equal(#report.rejected, 1)
        T.assert_equal(report.rejected[1].gate, "pet")
        T.assert_equal(report.rejected[1].reason, "no_pet")
        T.assert_nil(h.called("pet_attack"), "the SDK must not be reached without a pet")
    end)
end

--- ADR 08 §2.2: PET is a channel precisely so a rotation holding CASTING does not implicitly own the
--- pet. A command that acquired nothing would be acting on ambient authority.
function M.test_a_pet_command_acquires_the_pet_channel_under_the_plugin_id()
    set_spell_helper()
    with_kernel({ pet = make_unit({ guid = "pet" }) }, function(h)
        T.assert_nil(h.broker:who_owns(ControlBroker.Channel.PET),
            "nothing may hold PET before the first command")
        PetCtrl:new():attack(make_unit({ guid = "mob1" }))
        T.assert_equal(h.broker:who_owns(ControlBroker.Channel.PET),
            "sentinel.rotation.warlock_affliction",
            "the command must hold PET under the plugin's id")
    end)
end

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------

function M.test_registry_resolves_warlock_class_id()
    local resolved = Registry.resolve(9)
    T.assert_equal(resolved, Profile, "class_id 9 resolves to the Warlock Affliction profile module")
end

--- The manifest is not reached at runtime (nothing calls `PluginRegistry:discover`), so nothing else
--- in the suite would notice it drifting out of validity. Checked against the real validator, with
--- the real published API version, for the same reason the mage's is.
function M.test_the_manifest_validates_against_the_published_api()
    local Manifest = require("kernel/manifest")
    local manifest = require("rotations/warlock_affliction/manifest")
    local ok, reason = Manifest.validate(manifest, { api_version = Api.API_VERSION })
    T.assert_true(ok, "the warlock manifest must validate: " .. tostring(reason))
    T.assert_equal(manifest.id, "sentinel.rotation.warlock_affliction",
        "the id must match the lease OWNER in support.lua and pet_controller.lua")
    T.assert_equal(manifest.applies_to.class, "Warlock",
        "applies_to.class is compared against the Title-Case name the snapshot carries")
end

--- Every capability the manifest names must be one the kernel actually satisfies. `Capabilities`
--- rejects an unknown name at discovery, which is a failure nothing offline would otherwise reach.
function M.test_the_manifest_requires_only_kernel_capabilities()
    local manifest = require("rotations/warlock_affliction/manifest")
    for _, capability in ipairs(manifest.requires) do
        T.assert_true(Api.KERNEL_CAPABILITIES[capability] == true,
            "manifest requires '" .. capability .. "', which the kernel does not provide")
    end
end

return M
