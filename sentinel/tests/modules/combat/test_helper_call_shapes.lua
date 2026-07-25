local Blackboard = require("core/blackboard")
local CooldownTracker = require("modules/combat/cooldown_tracker")
local SpellCatalog = require("kernel/catalogs/spell")
local Cond = require("modules/combat/profiles/paladin/retribution_conditions")
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

    T.assert_equal(cooldowns:get_cooldown(35395), 0)
    T.assert_true(Cond.spell_ready("judgement")(bb))

    package.preload["common/utility/spell_helper"] = nil
    package.loaded["common/utility/spell_helper"] = nil
end

return M
