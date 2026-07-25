local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local Profile = require("rotations/mage_frost/frost_tbc")
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
    function unit:is_channelling_spell() return false end
    function unit:is_active_spell_interruptable() return opts.interruptible ~= false end
    return unit
end

local function make_bb()
    spell_helper = {
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

    local bb = Blackboard:new()
    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = {} })
    local target = make_unit({ guid = "target", position = { x = 25, y = 0, z = 0 }, health_pct = 0.80 })
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.level", 70)
    bb:set("player.in_combat", true)
    bb:set("player.is_moving", false)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 0)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
    bb:set("module.combat.cooldowns", {
        spell_ready = function() return true end,
        is_gcd_ready = function() return true end,
    })
    bb:set("module.combat.dispatcher", {
        queue_target = function(_self, _action_id, _spell_id, _target, _priority, _message, _opts)
            return true
        end,
        queue_position = function(_self, _action_id, _spell_id, _position, _priority, _message)
            return true
        end,
    })
    return bb
end

function M.run()
    -- build() returns profile with correct id
    local bb = make_bb()
    local bus = EventBus:new()
    local profile = Profile.build(bb, bus)
    T.assert_not_nil(profile, "build() should return a non-nil profile")
    T.assert_equal(profile.id, "mage_frost_tbc", "profile id should be mage_frost_tbc")

    -- rotation.profile_id set on blackboard
    T.assert_equal(bb:get("rotation.profile_id"), "mage_frost_tbc",
        "rotation.profile_id should be set on blackboard")

    -- Has tick_maintenance, tick_off_gcd, tick_gcd, reset methods
    T.assert_true(type(profile.tick_maintenance) == "function", "should have tick_maintenance method")
    T.assert_true(type(profile.tick_off_gcd) == "function", "should have tick_off_gcd method")
    T.assert_true(type(profile.tick_gcd) == "function", "should have tick_gcd method")
    T.assert_true(type(profile.reset) == "function", "should have reset method")

    -- Grind-era hooks (prepare_rest, tick_pull, get_pull_strategy, _aoe_tree)
    -- were removed with ADR-001 (audit E3) — they had no caller left.
    T.assert_nil(profile.prepare_rest, "prepare_rest should be removed (dead grind-era hook)")
    T.assert_nil(profile.tick_pull, "tick_pull should be removed (dead grind-era hook)")
    T.assert_nil(profile.get_pull_strategy, "get_pull_strategy should be removed (dead grind-era hook)")

    -- reset() doesn't error
    local ok, err = pcall(function() profile:reset() end)
    T.assert_true(ok, "reset() should not error: " .. tostring(err))

    -- tick methods don't error
    local ok2, err2 = pcall(function() profile:tick_maintenance(bb) end)
    T.assert_true(ok2, "tick_maintenance should not error: " .. tostring(err2))

    local ok3, err3 = pcall(function() profile:tick_off_gcd(bb) end)
    T.assert_true(ok3, "tick_off_gcd should not error: " .. tostring(err3))

    local ok4, err4 = pcall(function() profile:tick_gcd(bb) end)
    T.assert_true(ok4, "tick_gcd should not error: " .. tostring(err4))
end

return M
