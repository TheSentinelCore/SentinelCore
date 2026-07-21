local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local SentinelCombat = require("modules/combat/module")
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
        buffs = {
            [31892] = true,
            [27140] = true,
            [27150] = true,
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
end

return M
