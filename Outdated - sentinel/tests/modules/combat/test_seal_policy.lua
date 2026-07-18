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
    function unit:is_dead() return opts.dead == true end
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
    function unit:get_buff_stacks() return 0 end
    function unit:get_buffs() return {} end
    function unit:is_in_combat() return opts.in_combat == true end
    function unit:is_enemy_with(other)
        return unit._hostile == true and other ~= nil
    end
    function unit:can_attack(other)
        return other and other._hostile == true
    end
    return unit
end

function M.run()
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local builder = ContextBuilder:new(bb)

    local player = make_unit({
        position = { x = 0, y = 0, z = 0 },
        in_combat = false,
    })
    local target = make_unit({
        position = { x = 25, y = 0, z = 0 },
        in_combat = false,
        hostile = true,
    })

    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("player.health_pct", 1.0)
    bb:set("player.in_combat", false)
    bb:set("player.is_casting", false)
    bb:set("player.is_channeling", false)
    bb:set("module.combat.enable_burst", true)
    bb:set("module.combat.primary_seal_preference", "blood")
    bb:set("module.combat.cooldowns", {
        is_gcd_ready = function() return true end,
    })
    bb:set("combat.state", "IDLE")
    bb:set("combat.target", target)
    bb:set("combat.enemy_count_10yd", 0)
    bb:set("system.now_ms", 1000)

    builder:refresh(bus)
    T.assert_equal(bb:get("rotation.desired_seal"), nil)
    T.assert_equal(bb:get("rotation.desired_seal_reason"), "ooc_no_seal")
    T.assert_false(bb:get("combat.burst_context", true))
    T.assert_equal(bb:get("rotation.primary_seal"), "blood")

    bb:set("player.in_combat", true)
    bb:set("combat.state", "ENGAGING")
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("system.now_ms", 1100)
    builder:refresh(bus)
    T.assert_equal(bb:get("rotation.primary_seal"), "blood")
    T.assert_equal(bb:get("rotation.desired_seal"), "blood")
    T.assert_equal(bb:get("rotation.desired_seal_reason"), "single_target")

    bb:set("combat.enemy_count_10yd", 2)
    bb:set("system.now_ms", 1200)
    builder:refresh(bus)
    T.assert_equal(bb:get("rotation.desired_seal"), "command")
    T.assert_equal(bb:get("rotation.desired_seal_reason"), "aoe")

    local close_target = make_unit({
        position = { x = 5, y = 0, z = 0 },
        hostile = true,
    })
    bb:set("combat.target", close_target)
    bb:set("player.target", close_target)
    bb:set("combat.enemy_count_10yd", 1)
    bb:set("system.now_ms", 1400)
    builder:refresh(bus)
    T.assert_true(bb:get("combat.burst_context", false))
end

return M
