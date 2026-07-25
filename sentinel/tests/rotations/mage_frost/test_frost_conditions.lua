-- PHASE 4C: `health_below` / `health_above` read the FROZEN SNAPSHOT through `Sentinel.cond`.
--
-- They are the rotation's first consumers of the kernel's predicate set, and the first place a
-- `Truth` value crosses into plugin code. `make_bb` therefore publishes a real surface carrying a
-- real frozen snapshot built from the same health figure the blackboard gets, so the four original
-- assertions below are unchanged -- the reading moved, the answers did not.
--
-- What DID change is the unreadable case, and it changed on purpose. See
-- `test_unreadable_health_no_longer_reads_as_critical` at the bottom.
local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local Snapshot = require("kernel/snapshot")
local T = require("tests/test_util")

local M = {}

--- A surface whose `snapshot` getter hands back `frozen`.
---
--- The real `Sentinel.snapshot` resolves through `scheduler:current_snapshot()`, so the smallest
--- honest stand-in is a scheduler that answers that one question. Stubbing the surface field
--- directly would bypass the getter these conditions actually read through.
local function publish_snapshot(frozen)
    _G.Sentinel = Api.build({ scheduler = { current_snapshot = function() return frozen end } })
end

local function with_published(frozen, fn)
    local saved = _G.Sentinel
    publish_snapshot(frozen)
    local ok, err = pcall(fn)
    _G.Sentinel = saved
    if not ok then error(err, 0) end
end

--- A frozen snapshot of a readable player at `health_pct`.
local function snapshot_with_health(health_pct)
    local builder = Snapshot.builder({ tick_index = 1 })
    builder:put("player.available", true)
    builder:put("player.health_pct", health_pct)
    return builder:freeze()
end

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    function unit:get_guid() return opts.guid or "guid" end
    function unit:get_position() return opts.position or { x = 0, y = 0, z = 0 } end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:is_dead() return false end
    function unit:get_target() return opts.target end
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
    function unit:get_buff_stacks(_spell_id) return 0 end
    function unit:get_buffs() return {} end
    function unit:is_casting_spell() return opts.casting == true end
    function unit:is_channelling_spell() return opts.channeling == true end
    function unit:is_active_spell_interruptable() return opts.interruptible ~= false end
    function unit:is_moving() return opts.moving == true end
    return unit
end

local function make_bb(overrides)
    overrides = overrides or {}

    spell_helper = {
        is_spell_castable = function(_self, _spell_id, _source, _target, _ignore_facing, _ignore_range)
            return true
        end,
    }

    local bb = Blackboard:new()
    local player = make_unit(overrides.player_opts or { guid = "player" })
    local target = make_unit(overrides.target_opts or { guid = "target", position = { x = 3, y = 0, z = 0 } })

    bb:set("system.now_ms", overrides.now_ms or 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", overrides.health_pct or 1.0)
    bb:set("player.mana_pct", overrides.mana_pct or 1.0)
    bb:set("player.in_combat", overrides.in_combat or false)
    bb:set("player.is_moving", overrides.is_moving or false)
    bb:set("player.level", overrides.level or 70)
    bb:set("combat.target", target)
    bb:set("combat.enemy_count_10yd", overrides.enemy_count or 0)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function(_self, _now) return overrides.gcd_ready ~= false end,
    })

    return bb
end

--- The health pair, now read from the snapshot. Assertions unchanged from the blackboard era.
function M.test_health_conditions_read_the_frozen_snapshot()
    local Cond = require("rotations/mage_frost/frost_conditions")
    local bb = make_bb({ health_pct = 0.30 })
    with_published(snapshot_with_health(0.30), function()
        T.assert_true(Cond.health_below(0.50)(bb), "health_below 0.50 should be true at 0.30")
        T.assert_false(Cond.health_below(0.20)(bb), "health_below 0.20 should be false at 0.30")
    end)

    bb = make_bb({ health_pct = 0.80 })
    with_published(snapshot_with_health(0.80), function()
        T.assert_true(Cond.health_above(0.50)(bb), "health_above 0.50 should be true at 0.80")
        T.assert_false(Cond.health_above(0.90)(bb), "health_above 0.90 should be false at 0.80")
    end)
end

--- THE MEASURED BEHAVIOUR CHANGE, and the reason the conversion is worth making.
---
--- The blackboard version was `H.num(blackboard:get("player.health_pct", 0)) < threshold`. The
--- default of 0 means UNREADABLE HEALTH READ AS 0% -- so on any tick the sensor had not filled that
--- key, `health_below(0.15)` answered true and the profile fired Ice Block: a ten-second self-stun,
--- triggered by missing data rather than by danger, on every such tick.
---
--- The snapshot answers Unknown instead, and the call site resolves it with `TreatFalse` -- stated
--- in the open, because `Truth.resolve` refuses to be called without a policy. Unreadable health is
--- no longer a panic signal.
function M.test_unreadable_health_no_longer_reads_as_critical()
    local Cond = require("rotations/mage_frost/frost_conditions")
    local bb = make_bb({})
    local builder = Snapshot.builder({ tick_index = 1 })
    builder:put("player.available", true)   -- the tier ran; health specifically is missing
    with_published(builder:freeze(), function()
        T.assert_false(Cond.health_below(0.15)(bb),
            "unreadable health must not fire the emergency defensive")
        T.assert_false(Cond.health_above(0.60)(bb),
            "and must not claim the player is healthy either -- Unknown is neither")
    end)
end

--- A tick where SENSE never ran at all, or a plugin that loaded before the kernel published.
function M.test_health_conditions_are_false_when_there_is_no_kernel()
    local Cond = require("rotations/mage_frost/frost_conditions")
    local bb = make_bb({ health_pct = 0.10 })
    local saved = _G.Sentinel
    _G.Sentinel = nil
    local ok, err = pcall(function()
        T.assert_false(Cond.health_below(0.15)(bb),
            "no kernel means no reading, and no reading must not mean 'critically hurt'")
    end)
    _G.Sentinel = saved
    if not ok then error(err, 0) end
end

function M.run()
    local bb
    local Cond = require("rotations/mage_frost/frost_conditions")

    -- CALLED EXPLICITLY. `run_offline.lua` runs a suite's `run()` OR its `test*` functions, never
    -- both -- so a `test_` function added to a file that already has `run()` is silently never
    -- executed, and the suite count does not move to tell you. These three were written and
    -- appeared to pass for exactly that reason.
    M.test_health_conditions_read_the_frozen_snapshot()
    M.test_unreadable_health_no_longer_reads_as_critical()
    M.test_health_conditions_are_false_when_there_is_no_kernel()

    -- mana_below: returns true when mana is below threshold
    bb = make_bb({ mana_pct = 0.15 })
    T.assert_true(Cond.mana_below(0.20)(bb), "mana_below 0.20 should be true at 0.15")
    T.assert_false(Cond.mana_below(0.10)(bb), "mana_below 0.10 should be false at 0.15")

    -- mana_above: returns true when mana is above threshold
    bb = make_bb({ mana_pct = 0.80 })
    T.assert_true(Cond.mana_above(0.50)(bb), "mana_above 0.50 should be true at 0.80")
    T.assert_false(Cond.mana_above(0.90)(bb), "mana_above 0.90 should be false at 0.80")

    -- enemies_in_melee: returns true when enemy count >= min_count
    bb = make_bb({ enemy_count = 3 })
    T.assert_true(Cond.enemies_in_melee(2)(bb), "enemies_in_melee 2 should be true with 3 enemies")
    T.assert_true(Cond.enemies_in_melee(3)(bb), "enemies_in_melee 3 should be true with 3 enemies (equal)")
    T.assert_false(Cond.enemies_in_melee(4)(bb), "enemies_in_melee 4 should be false with 3 enemies")

    -- not_in_combat / in_combat
    bb = make_bb({ in_combat = false })
    T.assert_true(Cond.not_in_combat(bb), "not_in_combat should be true when not in combat")
    T.assert_false(Cond.in_combat(bb), "in_combat should be false when not in combat")

    bb = make_bb({ in_combat = true })
    T.assert_false(Cond.not_in_combat(bb), "not_in_combat should be false when in combat")
    T.assert_true(Cond.in_combat(bb), "in_combat should be true when in combat")

    -- level_at_least
    bb = make_bb({ level = 40 })
    T.assert_true(Cond.level_at_least(40)(bb), "level_at_least 40 should be true at level 40")
    T.assert_true(Cond.level_at_least(30)(bb), "level_at_least 30 should be true at level 40")
    T.assert_false(Cond.level_at_least(41)(bb), "level_at_least 41 should be false at level 40")

    -- gcd_ready: true when cooldowns report ready
    bb = make_bb({ gcd_ready = true })
    T.assert_true(Cond.gcd_ready(bb), "gcd_ready should be true when GCD is ready")

    bb = make_bb({ gcd_ready = false })
    T.assert_false(Cond.gcd_ready(bb), "gcd_ready should be false when GCD is not ready")

    -- target_valid: true when target exists and is not dead
    bb = make_bb()
    T.assert_true(Cond.target_valid(bb), "target_valid should be true for a living target")

    -- target_valid: false when no target
    local bb_no_target = Blackboard:new()
    bb_no_target:set("player.object", make_unit())
    T.assert_false(Cond.target_valid(bb_no_target), "target_valid should be false with no target")

    -- player_is_moving
    bb = make_bb({ is_moving = true })
    T.assert_true(Cond.player_is_moving(bb), "player_is_moving should be true when moving")
    bb = make_bb({ is_moving = false })
    T.assert_false(Cond.player_is_moving(bb), "player_is_moving should be false when not moving")

    -- target_casting_interruptible: true when target is casting an interruptible spell
    bb = make_bb({ target_opts = { guid = "target", casting = true, interruptible = true } })
    T.assert_true(Cond.target_casting_interruptible(bb), "should detect interruptible cast")

    bb = make_bb({ target_opts = { guid = "target", casting = false } })
    T.assert_false(Cond.target_casting_interruptible(bb), "should be false when not casting")

    -- missing_frost_armor: true when player does not have frost armor buff
    bb = make_bb({ player_opts = { guid = "player", buffs = {} } })
    T.assert_true(Cond.missing_frost_armor(bb), "missing_frost_armor should be true without buff")

    bb = make_bb({ player_opts = { guid = "player", buffs = { [7301] = true } } })
    T.assert_false(Cond.missing_frost_armor(bb), "missing_frost_armor should be false with buff")

    -- missing_ice_armor: true when player does not have ice armor buff
    bb = make_bb({ player_opts = { guid = "player", buffs = {} } })
    T.assert_true(Cond.missing_ice_armor(bb), "missing_ice_armor should be true without buff")

    bb = make_bb({ player_opts = { guid = "player", buffs = { [27124] = true } } })
    T.assert_false(Cond.missing_ice_armor(bb), "missing_ice_armor should be false with buff")

    -- missing_arcane_intellect: true when player does not have arcane intellect buff
    bb = make_bb({ player_opts = { guid = "player", buffs = {} } })
    T.assert_true(Cond.missing_arcane_intellect(bb), "missing_arcane_intellect should be true without buff")

    bb = make_bb({ player_opts = { guid = "player", buffs = { [27126] = true } } })
    T.assert_false(Cond.missing_arcane_intellect(bb), "missing_arcane_intellect should be false with buff")

    -- spell_ready: returns closure that checks spell castability
    bb = make_bb()
    local frostbolt_ready = Cond.spell_ready("frostbolt")
    T.assert_true(frostbolt_ready(bb), "spell_ready frostbolt should be true with working helper")
end

return M
