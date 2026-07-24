local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SentinelCombat = require("modules/combat/module")
local CombatStateMachine = require("modules/combat/state_machine")
local ProximitySensor = require("runtime/sensors/proximity_sensor")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    unit._hostile = opts.hostile == true
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return opts.dead == true end
    function unit:get_target() return opts.target end
    function unit:has_buff(spell_id)
        local buffs = opts.buffs or {}
        if type(spell_id) == "table" then
            for _, id in ipairs(spell_id) do
                if buffs[id] then
                    return true
                end
            end
            return false
        end
        return buffs[spell_id] == true
    end
    function unit:get_buff_data(spell_id)
        return { is_active = unit:has_buff(spell_id), stack_count = 0 }
    end
    function unit:get_buff_stacks(_spell_id) return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return false end
    function unit:is_channelling_spell() return false end
    function unit:is_auto_attacking() return true end
    function unit:get_attack_speed() return 3.0 end
    function unit:get_health() return 100 end
    function unit:get_max_health() return 100 end
    function unit:get_power() return 100 end
    function unit:get_max_power() return 100 end
    function unit:is_enemy_with(other)
        return unit._hostile == true and other ~= nil
    end
    function unit:can_attack(other)
        return other and other._hostile == true
    end
    function unit:is_player()
        return opts.is_player ~= false
    end
    function unit:is_valid()
        return opts.invalid ~= true
    end
    return unit
end

function M.run()
    spell_helper = {
        is_spell_castable = function()
            return true
        end,
        get_spell_cooldown = function()
            return 0
        end,
        is_spell_in_line_of_sight = function()
            return true
        end,
    }

    local queued = {}
    spell_queue = {
        queue_spell_target = function(_self, spell_id, _target, _priority, message)
            queued[#queued + 1] = { spell_id = spell_id, message = message }
            return true
        end,
        queue_spell_target_fast = function(_self, spell_id, _target, _priority, message)
            queued[#queued + 1] = { spell_id = spell_id, message = message }
            return true
        end,
    }

    core = {
        spell_book = {
            get_specialization_id = function()
                return 0
            end,
        },
    }

    local nav = {
        move_to = function() end,
        stop = function() end,
        release = function() end,
        is_active = function() return false end,
    }

    local target = make_unit({
        guid = "enemy",
        position = { x = 3, y = 0, z = 0 },
        health_pct = 0.5,
        hostile = true,
    })
    local friendly_target = make_unit({
        guid = "friendly",
        position = { x = 3, y = 0, z = 0 },
        health_pct = 1.0,
        hostile = false,
    })
    local player = make_unit({
        guid = "player",
        position = { x = 0, y = 0, z = 0 },
        target = target,
        -- Give the player the maintenance auras the frost-mage maintenance tree
        -- checks (frost armor 168, arcane intellect 1459) so tick_maintenance is a
        -- genuine no-op in IDLE. Without them the module correctly queues Frost
        -- Armor as a self-buff, which is unrelated to (and would mask) the
        -- "don't act on a non-hostile direct target" assertion below.
        buffs = {
            [168] = true,   -- Frost Armor (rank 1) — see frost_conditions.frost_armor_aura_ids
            [1459] = true,  -- Arcane Intellect (rank 1) — see frost_conditions.arcane_intellect_aura_ids
        },
    })

    local function make_blackboard()
        local bb = Blackboard:new()
        bb:set("system.now_ms", 1000)
        bb:set("player.object", player)
        bb:set("player.target", target)
        bb:set("player.position", { x = 0, y = 0, z = 0 })
        bb:set("player.health_pct", 1.0)
        bb:set("player.mana_pct", 1.0)
        bb:set("player.in_combat", false)
        bb:set("player.is_casting", false)
        bb:set("player.is_channeling", false)
        bb:set("player.is_auto_attacking", true)
        bb:set("player.attack_speed_s", 3.0)
        bb:set("combat.enemy_count_10yd", 1)
        bb:set("combat.ally_count_30yd", 2)
        bb:set("combat.gcd_until_ms", 0)
        bb:set("combat.leash_radius", 25)
        return bb
    end

    -- Test 1: Ensure auto_engage_world is disabled by default, module stays IDLE
    local bb1 = make_blackboard()
    local bus1 = EventBus:new()
    local combat1 = SentinelCombat:new(bus1, bb1, nav)
    combat1:initialize()

    combat1:update(bb1)

    T.assert_equal(combat1:get_state(), "IDLE", "combat should stay IDLE when auto_engage_world is disabled and no engagement source")

    -- Test 2: Don't auto-engage non-hostile direct targets
    queued = {}
    local bb_friendly = make_blackboard()
    local bus_friendly = EventBus:new()
    local combat_friendly = SentinelCombat:new(bus_friendly, bb_friendly, nav)
    combat_friendly:initialize()
    bb_friendly:set("player.target", friendly_target)
    combat_friendly:update(bb_friendly)

    T.assert_equal(combat_friendly:get_state(), "IDLE", "combat should ignore non-hostile direct targets")
    T.assert_equal(queued[1], nil, "combat should not queue spells for non-hostile direct targets")

    -- Test 3 (B2): class detection defers instead of silently latching a
    -- default. Without a readable player object, the module must still be
    -- usable (unconfirmed placeholder), but must not mark class_confirmed.
    -- Once a real numeric class_id becomes readable, confirmation must
    -- happen exactly once and rebuild the profile for that class.
    local bb3 = make_blackboard()
    local bus3 = EventBus:new()
    local combat3 = SentinelCombat:new(bus3, bb3, nav)
    combat3:initialize()
    T.assert_false(combat3._class_confirmed, "class should not be confirmed without a readable player object")
    T.assert_equal(bb3:get("player.class_id"), 8, "unconfirmed class should fall back to the mage placeholder without erroring")

    local prev_core = core
    core = {
        object_manager = {
            get_local_player = function()
                return { get_class = function() return 2 end } -- Paladin
            end,
        },
    }
    combat3:_confirm_class_detection(bb3)
    core = prev_core
    T.assert_true(combat3._class_confirmed, "class should confirm once a real numeric class_id is read")
    T.assert_equal(bb3:get("player.class_id"), 2, "profile should rebuild for the confirmed class")

    -- Test 4 (B3): combat.leash_center must only be set on entry into combat
    -- from a non-engaged state, not on every engage() call (execute_kill
    -- re-publishes engage_requested every tick while in range).
    local bb4 = make_blackboard()
    local bus4 = EventBus:new()
    local combat4 = SentinelCombat:new(bus4, bb4, nav)
    combat4:initialize()
    combat4:engage(target, { source = "auto", leash_center = { x = 10, y = 0, z = 0 } })
    local first_center = bb4:get("combat.leash_center")
    T.assert_equal(first_center and first_center.x, 10, "leash_center should be set on first engage")
    bb4:set("player.position", { x = 50, y = 0, z = 0 })
    combat4:engage(target, { source = "auto", leash_center = bb4:get("player.position") })
    local second_center = bb4:get("combat.leash_center")
    T.assert_equal(second_center and second_center.x, 10, "leash_center should not move on a repeat engage call while already in combat")

    -- Test 5 (B6): an "outnumbered" disengage must back off re-engagement
    -- for a cooldown window, so questing/auto-engage can't re-trigger
    -- engage/disengage every frame while still outnumbered.
    local bb5 = make_blackboard()
    local bus5 = EventBus:new()
    local combat5 = SentinelCombat:new(bus5, bb5, nav)
    combat5:initialize()
    bb5:set("system.now_ms", 1000)
    combat5:engage(target, { source = "auto" })
    T.assert_equal(combat5:get_state(), "ENGAGING", "sanity: engage should transition out of IDLE")
    combat5:disengage("outnumbered")
    T.assert_equal(combat5:get_state(), "IDLE", "disengage should return to IDLE")
    combat5:engage(target, { source = "auto" })
    T.assert_equal(combat5:get_state(), "IDLE", "engage should be blocked during the outnumbered backoff window")
    bb5:set("system.now_ms", 1000 + 2000 + 1)
    combat5:engage(target, { source = "auto" })
    T.assert_equal(combat5:get_state(), "ENGAGING", "engage should succeed again once the outnumbered backoff window elapses")

    -- Test 6 (C7): transition() must reject unlisted states instead of
    -- silently accepting any string.
    local bb6 = Blackboard:new()
    local bus6 = EventBus:new()
    local sm = CombatStateMachine:new(bus6, bb6)
    sm:transition("BOGUS_STATE", "typo")
    T.assert_equal(sm:get_state(), "IDLE", "illegal transition should be rejected and state should remain unchanged")
    sm:transition("ENGAGING", "engage")
    T.assert_equal(sm:get_state(), "ENGAGING", "legal transition should still succeed")

    -- Test 7 (B9): proximity sensor must recompute unit counts on the
    -- FIRST frame, not the third — frames 1-2 previously published the
    -- constructor's zeros after every load/reload.
    local bb7 = Blackboard:new()
    bb7:set("player.position", { x = 0, y = 0, z = 0 })
    local sensor = ProximitySensor:new(bb7)
    local recompute_calls = 0
    sensor._get_enemy_counts = function(_self, _pos)
        recompute_calls = recompute_calls + 1
        return 0, 0
    end
    sensor:refresh(nil, 0)
    T.assert_equal(recompute_calls, 1, "proximity sensor should recompute counts on the first frame, not the third")

    -- Test 8 (F4): _find_attacker's get_all_objects scan must be cached for the duration of
    -- one tick (keyed by blackboard system.now_ms, the module's own per-frame clock) so a
    -- second lookup within the same tick does not pay for a second full scan, while a genuinely
    -- new tick still gets a fresh one.
    local bb8 = make_blackboard()
    local bus8 = EventBus:new()
    local combat8 = SentinelCombat:new(bus8, bb8, nav)
    combat8:initialize()
    bb8:set("system.now_ms", 5000)
    bb8:set("player.object", player)

    local scan_count = 0
    local prev_core8 = core
    core = {
        object_manager = {
            get_all_objects = function()
                scan_count = scan_count + 1
                return {}
            end,
        },
    }
    combat8:_find_attacker()
    combat8:_find_attacker()
    T.assert_equal(scan_count, 1, "two lookups within the same tick (same system.now_ms) must share one scan")

    bb8:set("system.now_ms", 6000)
    combat8:_find_attacker()
    T.assert_equal(scan_count, 2, "a lookup on a new tick (system.now_ms changed) must get a fresh scan")
    core = prev_core8

    -- Test 9: a forced quest engagement must expose the forced target's GUID (the
    -- strategy's neutral exemption is scoped to exactly that unit) WITHOUT flipping the
    -- global attack_neutral grind flag — the blanket flag made every neutral mob a valid
    -- idle auto-engage target while a quest kill was in flight.
    local bb9 = make_blackboard()
    local bus9 = EventBus:new()
    local combat9 = SentinelCombat:new(bus9, bb9, nav)
    combat9:initialize()
    combat9:engage(friendly_target, { source = "questing" })
    T.assert_equal(combat9:get_state(), "ENGAGING",
        "forced quest engage should enter combat even on a neutral target")
    T.assert_equal(bb9:get("combat.forced_target_guid"), "friendly",
        "forced engage must publish the forced target's guid for the strategy exemption")
    T.assert_false(bb9:get("module.grind.attack_neutral") == true,
        "the global attack_neutral grind flag must NOT be flipped by quest engagements")

    -- While the forced target lives, a non-forced engage (idle auto-engage, bg) must not
    -- steal the current target.
    combat9:engage(target, { source = "auto" })
    T.assert_equal(combat9._current_target, friendly_target,
        "an auto engage must not preempt a live forced quest target")

    combat9:disengage("test")
    T.assert_equal(bb9:get("combat.forced_target_guid"), nil,
        "disengage must clear the forced-target guid")

    -- Test 10: when the forced quest target dies, combat must NOT self-select a
    -- replacement — the selector has no notion of which entries the quest needs, which
    -- is how the bot ended up fighting neutral vermin and a RABBIT under
    -- source="questing" while its chase deadlocked against the kill action's navigation
    -- (live log: out_of_range dist=38 range=5 spam, nav thrash, frozen in place).
    -- Control goes back to the kill action via disengage.
    local bb10 = make_blackboard()
    local bus10 = EventBus:new()
    local combat10 = SentinelCombat:new(bus10, bb10, nav)
    combat10:initialize()
    local dying_opts = { guid = "quest-mob", position = { x = 3, y = 0, z = 0 }, hostile = false }
    local dying = make_unit(dying_opts)
    combat10:engage(dying, { source = "questing" })
    T.assert_equal(combat10:get_state(), "ENGAGING", "sanity: forced engage entered combat")
    dying_opts.dead = true
    -- A perfectly valid hostile target is available to the selector (player.target in
    -- the blackboard) — it must still not be taken.
    local got = combat10:_ensure_target()
    T.assert_equal(got, nil, "questing combat must not self-select a replacement target")
    T.assert_equal(combat10:get_state(), "IDLE",
        "combat must disengage and return control to the kill action when the quest target dies")

    -- Test 11: low-HP safety must not oscillate. While an attacker is still actively
    -- attacking the player, tripping the low-health threshold must NOT disengage
    -- (fighting back beats standing there dying). Once combat genuinely ends with low
    -- HP, a recovery latch must block idle AUTO-engage until HP recovers, a timeout
    -- passes, or the player is attacked again. Explicit/forced engages bypass it.
    local bb11 = make_blackboard()
    local bus11 = EventBus:new()
    local combat11 = SentinelCombat:new(bus11, bb11, nav)
    combat11:initialize()
    local attacker = make_unit({
        guid = "attacker",
        hostile = true,
        is_player = false,
        target = player,
        position = { x = 2, y = 0, z = 0 },
    })
    local prev_core11 = core
    core = { object_manager = { get_all_objects = function() return { attacker } end } }
    bb11:set("player.in_combat", true)
    bb11:set("combat.gcd_until_ms", 1e9) -- hold the GCD so rotation ticks stay inert
    combat11:engage(target, { source = "auto" })
    T.assert_equal(combat11:get_state(), "ENGAGING", "sanity: engaged before the low-HP dip")
    bb11:set("player.health_pct", 0.20)
    combat11:update(bb11)
    T.assert_true(combat11:get_state() ~= "IDLE",
        "low HP with an attacker still on the player must keep fighting, not disengage")

    -- Attacker gone, combat over: the low-HP disengage must latch recovery.
    core = { object_manager = { get_all_objects = function() return {} end } }
    bb11:set("system.now_ms", 2000)
    bb11:set("player.in_combat", false)
    combat11:update(bb11)
    T.assert_equal(combat11:get_state(), "IDLE", "low HP with no attacker must disengage")

    -- The latch must block idle auto-engage even where it would otherwise fire.
    -- (bg.active, not bg.combat_zone — CombatZoneDetector recomputes the latter
    -- every update() and would erase a hand-set value.)
    bb11:set("bg.active", true)
    bb11:set("system.now_ms", 3000)
    combat11:update(bb11)
    T.assert_equal(combat11:get_state(), "IDLE",
        "recovery latch must block idle auto-engage while HP is low")

    -- Explicit (forced) engagement is never blocked by the latch.
    combat11:engage(target, { source = "questing", force = true })
    T.assert_equal(combat11:get_state(), "ENGAGING", "explicit engage bypasses the recovery latch")
    combat11:disengage("test")

    -- Recovering past the exit threshold releases the latch.
    bb11:set("system.now_ms", 4000)
    bb11:set("player.health_pct", 0.70)
    combat11:update(bb11)
    T.assert_equal(combat11:get_state(), "ENGAGING",
        "auto engage resumes once HP recovers past the exit threshold")
    combat11:disengage("test")
    core = prev_core11

    -- Test 12: the recovery latch must break IMMEDIATELY when the player is attacked
    -- again (enters combat with a live attacker) — even while HP is still low.
    local bb12 = make_blackboard()
    local bus12 = EventBus:new()
    local combat12 = SentinelCombat:new(bus12, bb12, nav)
    combat12:initialize()
    local attacker12 = make_unit({
        guid = "attacker12",
        hostile = true,
        is_player = false,
        target = player,
        position = { x = 2, y = 0, z = 0 },
    })
    local prev_core12 = core
    core = { object_manager = { get_all_objects = function() return {} end } }
    bb12:set("combat.gcd_until_ms", 1e9)
    combat12:engage(target, { source = "auto" })
    bb12:set("player.health_pct", 0.20)
    combat12:update(bb12)
    T.assert_equal(combat12:get_state(), "IDLE", "sanity: latched after a low-HP disengage")
    core = { object_manager = { get_all_objects = function() return { attacker12 } end } }
    bb12:set("system.now_ms", 2000)
    bb12:set("player.in_combat", true)
    combat12:update(bb12)
    T.assert_equal(combat12:get_state(), "ENGAGING",
        "the latch must break immediately when the player is attacked again")
    combat12:disengage("test")
    core = prev_core12

    -- Test 13: a forced quest target must be cleared when it despawns / leash-resets
    -- (is_valid() false) even though is_dead() never flips — evade left the bot
    -- chasing a full-HP ghost mob forever.
    local bb13 = make_blackboard()
    local bus13 = EventBus:new()
    local combat13 = SentinelCombat:new(bus13, bb13, nav)
    combat13:initialize()
    local disengaged13 = nil
    bus13:subscribe("combat:disengaged", function(payload) disengaged13 = payload end)
    local q13_opts = { guid = "q13", hostile = false, position = { x = 3, y = 0, z = 0 } }
    local q13 = make_unit(q13_opts)
    combat13:engage(q13, { source = "questing" })
    T.assert_equal(combat13:get_state(), "ENGAGING", "sanity: forced engage entered combat")
    q13_opts.invalid = true
    local got13 = combat13:_ensure_target()
    T.assert_equal(got13, nil, "a despawned (is_valid=false) forced target must be cleared")
    T.assert_equal(combat13:get_state(), "IDLE",
        "clearing an invalid forced target must return control to the kill action")
    T.assert_equal(bb13:get("combat.forced_target_guid"), nil,
        "the forced-target guid must be cleared with the target")
    T.assert_true(disengaged13 ~= nil,
        "the disengaged event must publish so questing's Kill handler can react")

    -- Test 14: a forced target whose HP makes zero progress for the stall window
    -- (evading / unreachable) must be cleared; HP progress must reset the window.
    local bb14 = make_blackboard()
    local bus14 = EventBus:new()
    local combat14 = SentinelCombat:new(bus14, bb14, nav)
    combat14:initialize()
    local q14_opts = { guid = "q14", hostile = false, health_pct = 0.9, position = { x = 3, y = 0, z = 0 } }
    local q14 = make_unit(q14_opts)
    bb14:set("system.now_ms", 1000)
    combat14:engage(q14, { source = "questing" })
    T.assert_true(combat14:_ensure_target() ~= nil, "forced target valid on the first check")
    bb14:set("system.now_ms", 15000)
    q14_opts.health_pct = 0.6 -- damage landed: progress resets the stall window
    T.assert_true(combat14:_ensure_target() ~= nil, "HP progress must reset the stall window")
    bb14:set("system.now_ms", 30000)
    T.assert_true(combat14:_ensure_target() ~= nil,
        "an engagement inside the stall window since last progress stays alive")
    bb14:set("system.now_ms", 35001)
    T.assert_equal(combat14:_ensure_target(), nil,
        "20s with zero target-HP progress must clear the forced target")
    T.assert_equal(combat14:get_state(), "IDLE", "the stall clear must disengage back to the kill action")

    -- Test 15: combat.target_has_immunity must be CONSUMED. A forced target flagged
    -- immune is cleared via the invalid-target path; a grind/auto target flagged
    -- immune is blacklisted so the selector skips it for a period.
    local bb15 = make_blackboard()
    local bus15 = EventBus:new()
    local combat15 = SentinelCombat:new(bus15, bb15, nav)
    combat15:initialize()
    local q15 = make_unit({ guid = "q15", hostile = false, position = { x = 3, y = 0, z = 0 } })
    combat15:engage(q15, { source = "questing" })
    bb15:set("combat.target_has_immunity", true)
    T.assert_equal(combat15:_ensure_target(), nil, "an immune forced target must be cleared")
    T.assert_equal(combat15:get_state(), "IDLE", "immune forced target clears through the disengage path")

    bb15:set("combat.target_has_immunity", false)
    combat15:engage(target, { source = "auto" })
    T.assert_equal(combat15:get_state(), "ENGAGING", "sanity: auto engage on the hostile target")
    bb15:set("combat.target_has_immunity", true)
    combat15:_ensure_target()
    local blacklist15 = bb15:get("combat.immune_target_guids")
    T.assert_true(type(blacklist15) == "table" and blacklist15["enemy"] ~= nil,
        "an immune grind target must be blacklisted by GUID")
    T.assert_false(bb15:get("combat.target_has_immunity") == true,
        "the immunity flag must be consumed (reset) once acted upon")
    T.assert_false(combat15._target_selector:is_valid_enemy(target, { require_player = true }),
        "the selector must skip a blacklisted GUID while the blacklist entry is live")
    bb15:set("system.now_ms", bb15:get("system.now_ms", 0) + 30001)
    T.assert_true(combat15._target_selector:is_valid_enemy(target, { require_player = true }),
        "the blacklist entry must expire so the mob becomes targetable again")
    combat15:disengage("test")

    -- Test 16: disengage must recall the pet (passive/follow) so a Voidwalker stops
    -- attacking and cannot chain-pull between kills.
    local bb16 = make_blackboard()
    local bus16 = EventBus:new()
    local combat16 = SentinelCombat:new(bus16, bb16, nav)
    combat16:initialize()
    local recalled = 0
    bb16:set("module.combat.pet_controller", { passive = function() recalled = recalled + 1 end })
    combat16:engage(target, { source = "auto" })
    combat16:disengage("test")
    T.assert_equal(recalled, 1, "disengage must send the pet passive/follow via the pet controller")

    -- Test 17: independent no-progress guard — engaged with a target whose HP is not
    -- dropping AND whose distance is not closing for 15s must disengage (the COOLDOWN
    -- no-legal-action timeout is unreachable when fallbacks always return SUCCESS).
    local bb17 = make_blackboard()
    local bus17 = EventBus:new()
    local combat17 = SentinelCombat:new(bus17, bb17, nav)
    combat17:initialize()
    bb17:set("combat.gcd_until_ms", 1e9) -- hold the GCD so the COOLDOWN timeout can't preempt
    bb17:set("system.now_ms", 1000)
    combat17:engage(target, { source = "auto" })
    combat17:update(bb17)
    bb17:set("system.now_ms", 10000)
    combat17:update(bb17)
    T.assert_true(combat17:get_state() ~= "IDLE",
        "engagement persists while inside the no-progress window")
    bb17:set("system.now_ms", 16001)
    combat17:update(bb17)
    T.assert_equal(combat17:get_state(), "IDLE",
        "15s with no HP and no distance progress must disengage with no_progress")

    -- Progress (target HP dropping) must keep the engagement alive past 15s.
    local bb18 = make_blackboard()
    local bus18 = EventBus:new()
    local combat18 = SentinelCombat:new(bus18, bb18, nav)
    combat18:initialize()
    local t18_opts = { guid = "t18", hostile = true, health_pct = 0.9, position = { x = 3, y = 0, z = 0 } }
    local t18 = make_unit(t18_opts)
    bb18:set("combat.gcd_until_ms", 1e9)
    bb18:set("system.now_ms", 1000)
    combat18:engage(t18, { source = "auto" })
    combat18:update(bb18)
    bb18:set("system.now_ms", 12000)
    t18_opts.health_pct = 0.5 -- damage is landing
    combat18:update(bb18)
    bb18:set("system.now_ms", 20000)
    combat18:update(bb18)
    T.assert_true(combat18:get_state() ~= "IDLE",
        "target-HP progress must reset the no-progress window")
    combat18:disengage("test")
end

return M
