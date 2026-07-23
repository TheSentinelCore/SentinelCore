-- NOTE: this test originally exercised `modules/combat/target_selector.lua`
-- (v1), which was dead code (audit finding E5 — no production requirer;
-- `modules/combat/module.lua` uses `target_selector_v2`). E5's deletion left
-- this the only test requiring the v1 module, so it has been re-targeted at
-- the live `target_selector_v2` module while keeping this file's own path
-- (and therefore its entry in run_offline.lua's test_modules list) intact.
local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local TargetSelector = require("modules/combat/target_selector_v2")
local T = require("tests/test_util")

local M = {}

local function make_unit(opts)
    opts = opts or {}
    local unit = {}
    unit._hostile = opts.hostile == true
    function unit:get_guid() return opts.guid end
    function unit:get_position() return opts.position end
    function unit:is_dead() return false end
    function unit:get_target() return opts.target end
    function unit:get_health_percentage() return opts.health_pct or 1.0 end
    function unit:has_buff() return false end
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
    local bb = Blackboard:new()
    local bus = EventBus:new()
    local selector = TargetSelector:new(bus, bb)

    local player = make_unit({ guid = "player", position = { x = 0, y = 0, z = 0 } })
    local healer = make_unit({ guid = "healer", position = { x = 8, y = 0, z = 0 }, health_pct = 0.9, hostile = true })
    local dps = make_unit({ guid = "dps", position = { x = 2, y = 0, z = 0 }, health_pct = 0.9, hostile = true })
    local ram = make_unit({ guid = "ram", position = { x = 1, y = 0, z = 0 }, health_pct = 1.0, hostile = true, is_player = false })

    -- v2 delegates enemy scanning to the active strategy (default), which
    -- holds its own `_unit_helper` reference — unlike v1, the top-level
    -- selector does not read `_unit_helper` itself.
    selector._strategies.default._unit_helper = {
        get_enemy_list_around = function() return { ram, healer, dps } end,
        is_healer = function(_self, unit) return unit == healer end,
    }

    local set_calls = 0

    _G.core = {
        input = {
            set_target = function()
                set_calls = set_calls + 1
                return true
            end,
        },
    }
    _G.spell_helper = {
        is_spell_in_line_of_sight = function() return true end,
    }

    bb:set("player.object", player)
    bb:set("player.position", { x = 0, y = 0, z = 0 })
    bb:set("combat.leash_radius", 25)
    local best = selector:get_best_target({ require_player = true })
    T.assert_equal(best, healer)
    T.assert_equal(set_calls, 1)
    bb:set("combat.target", healer)
    selector:get_best_target({ require_player = true })
    T.assert_equal(set_calls, 1)
    T.assert_true(selector:is_valid_enemy(ram, { require_player = true }))
end

return M
