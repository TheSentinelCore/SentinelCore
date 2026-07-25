local Blackboard = require("core/blackboard")
local T = require("tests/test_util")

local M = {}

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

function M.run()
    -- health_below: returns true when health is below threshold
    local bb = make_bb({ health_pct = 0.30 })
    local Cond = require("modules/combat/profiles/mage/frost_conditions")
    T.assert_true(Cond.health_below(0.50)(bb), "health_below 0.50 should be true at 0.30")
    T.assert_false(Cond.health_below(0.20)(bb), "health_below 0.20 should be false at 0.30")

    -- health_above: returns true when health is above threshold
    bb = make_bb({ health_pct = 0.80 })
    T.assert_true(Cond.health_above(0.50)(bb), "health_above 0.50 should be true at 0.80")
    T.assert_false(Cond.health_above(0.90)(bb), "health_above 0.90 should be false at 0.80")

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
