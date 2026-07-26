-- tests/modules/combat/test_helper_call_shapes.lua
-- The CooldownTracker and the Paladin's `spell_ready` agree on how the spell-book helper is called.
--
-- ============================================================================
-- WHAT THE PALADIN KERNEL PORT CHANGED HERE, AND WHAT IT DID NOT
-- ============================================================================
-- BOTH ASSERTIONS ARE UNCHANGED. What moved is the route `spell_ready` takes to the spell-book
-- helper:
--
--   BEFORE  retribution_conditions -> require("shared/spell_helper") -> spell_helper (SDK/mock)
--   AFTER   retribution_conditions -> Sentinel.spells -> shared/spell_helper -> spell_helper
--
-- A plugin may not `require("shared/spell_helper")` -- that is a cross-package require
-- `tests/kernel/test_plugin_require_audit.lua` refuses -- so the condition now asks
-- `Sentinel.spells:castability`, which is where `runtime/app.lua:97` already sends every other
-- caller: `Spells:new({ spell_helper = SpellHelper, ... })`.
--
-- THE SURFACE IS PUBLISHED HERE ON PURPOSE. With no `_G.Sentinel` the condition's shim
-- short-circuits to "fail open" and the assertion below would pass WITHOUT the helper ever being
-- consulted -- which is precisely the kind of green this file exists to refuse. Wiring the real
-- `kernel/spells` over the real `shared/spell_helper` keeps the call shape under test end to end.

local Api = require("kernel/api")
local Blackboard = require("core/blackboard")
local CooldownTracker = require("modules/combat/cooldown_tracker")
local SpellCatalog = require("kernel/catalogs/spell")
local Spells = require("kernel/spells")
local SpellHelper = require("shared/spell_helper")
local Cond = require("rotations/paladin_retribution/retribution_conditions")
local T = require("tests/test_util")

local M = {}

local function make_unit()
    return {
        get_position = function()
            return { x = 0, y = 0, z = 0 }
        end,
        is_dead = function()
            return false
        end,
    }
end

function M.run()
    local saved_surface = _G.Sentinel

    local bb = Blackboard:new()
    local player = make_unit()
    local target = make_unit()

    spell_helper = nil
    package.loaded["common/utility/spell_helper"] = nil
    package.preload["common/utility/spell_helper"] = function()
        return {
            is_spell_castable = function(spell_id, source, dest)
                return spell_id == 20271 and source == player and dest == target
            end,
            get_spell_cooldown = function(spell_id)
                if spell_id == 35395 or spell_id == 20271 then
                    return 0
                end
                return 99
            end,
        }
    end

    bb:set("player.object", player)
    bb:set("player.target", target)
    bb:set("combat.target", target)
    bb:set("module.combat.catalog", SpellCatalog:new())

    local cooldowns = CooldownTracker:new(bb:get("module.combat.catalog"), bb)
    bb:set("module.combat.cooldowns", cooldowns)

    -- Production wiring, reproduced: `runtime/app.lua:97` builds `Spells` over
    -- `shared/spell_helper`, so this is the same object the live Paladin condition reaches.
    _G.Sentinel = Api.build({ spells = Spells:new({ spell_helper = SpellHelper }) })

    local ok, err = pcall(function()
        T.assert_equal(cooldowns:get_cooldown(35395), 0)
        T.assert_true(Cond.spell_ready("judgement")(bb))
    end)

    _G.Sentinel = saved_surface
    package.preload["common/utility/spell_helper"] = nil
    package.loaded["common/utility/spell_helper"] = nil

    if not ok then error(err, 0) end
end

return M
