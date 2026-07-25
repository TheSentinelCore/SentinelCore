local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local Profile = require("modules/combat/profiles/paladin/retribution_tbc")
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

function M.run()
    -- Reset module cache to ensure clean state
    package.loaded["modules/combat/profiles/paladin/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil
end

function M.test_legacy_path()
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

    local actions = {}
    spell_queue = {
        queue_spell_target = function(_self, spell_id, _target, _priority, message)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
        queue_spell_target_fast = function(_self, spell_id, _target, _priority, message)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
    }

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = { [31892] = true } })
    local target = make_unit({ guid = "target", position = { x = 3, y = 0, z = 0 }, health_pct = 0.50 })
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.ally_count_30yd", 2)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("rotation.active_seal", "blood")
    bb:set("rotation.desired_seal", "blood")
    bb:set("combat.swing.remaining_ms", 999)
    bb:set("module.combat.twist_window_ms", 350)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
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

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "judgement")

    actions = {}
    bb:set("system.now_ms", 1200)
    bb:set("rotation.after_judgement_reseal", true)
    bb:set("rotation.active_seal", nil)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "seal_of_blood")

    -- Test seal missing case in legacy path (the fix for combat not starting)
    actions = {}
    bb:set("rotation.active_seal", nil)  -- No seal active
    bb:set("rotation.desired_seal", "blood")
    bb:set("system.now_ms", 1500)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "seal_of_blood", "Legacy path should queue seal when seal missing")
end

function M.test_dsl_path()
    package.loaded["modules/combat/profiles/paladin/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil
    
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

    local actions = {}
    spell_queue = {
        queue_spell_target = function(_self, spell_id, _target, _priority, message)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
        queue_spell_target_fast = function(_self, spell_id, _target, _priority, message)
            actions[#actions + 1] = { spell_id = spell_id, action = message }
            return true
        end,
    }

    local bb = Blackboard:new()
    local bus = EventBus:new()
    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 }, buffs = { [31892] = true } })
    local target = make_unit({ guid = "target", position = { x = 3, y = 0, z = 0 }, health_pct = 0.50 })
    bb:set("system.now_ms", 1000)
    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.mana_pct", 1.0)
    bb:set("player.in_combat", true)
    bb:set("player.is_auto_attacking", true)
    bb:set("player.attack_speed_s", 3.0)
    bb:set("combat.target", target)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("combat.ally_count_30yd", 2)
    bb:set("combat.gcd_until_ms", 0)
    bb:set("rotation.active_seal", "blood")
    bb:set("rotation.desired_seal", "blood")
    bb:set("combat.swing.remaining_ms", 999)
    bb:set("module.combat.twist_window_ms", 350)
    bb:set("module.combat.catalog", require("kernel/catalogs/spell"):new())
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
    bb:set("module.combat.rotation_engine", "dsl")

    local profile = Profile.build(bb, bus)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "judgement", "DSL path should queue judgement")

    actions = {}
    bb:set("system.now_ms", 1200)
    bb:set("rotation.after_judgement_reseal", true)
    bb:set("rotation.active_seal", nil)
    profile:tick_gcd(bb)
    T.assert_equal(actions[1].action, "seal_of_blood", "DSL path should queue seal_of_blood after judgement")

    actions = {}
    bb:set("combat.target", nil)
    profile:tick_gcd(bb)
    T.assert_nil(actions[1], "DSL path should have no action when target invalid")

    -- Test seal missing case (the fix for combat not starting)
    package.loaded["modules/combat/profiles/paladin/retribution_tbc"] = nil
    package.loaded["kernel/lib/priority_builder"] = nil
    local profile3 = Profile.build(bb, bus)
    bb:set("combat.target", target)
    bb:set("rotation.active_seal", nil)  -- No seal active
    bb:set("rotation.desired_seal", "blood")
    actions = {}
    profile3:tick_gcd(bb)
    T.assert_equal(actions[1].action, "seal_of_blood", "Should queue seal when seal missing")
end

return M
