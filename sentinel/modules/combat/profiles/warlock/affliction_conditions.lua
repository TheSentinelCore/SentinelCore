local AuraCatalog = require("kernel/catalogs/aura")
local H = require("shared/combat_helpers")

local Cond = {}

-- ============================================================================
-- DOT MAINTENANCE
-- ============================================================================

--- True when the current target is missing EVERY known rank of `spell_key`'s
--- debuff. Reads the rank array straight off the catalog entry (spell_catalog.lua)
--- rather than hardcoding a single debuff id, so a refresh check stays correct
--- across the whole 1-70 rank range without per-level bookkeeping.
--- Returns true (treat as "missing" -> let spell_available gate the cast) when
--- there is no catalog/target to check against, matching the fail-open shape
--- ConditionLibrary.spell_available uses (never errors, degrades gracefully).
function Cond.target_missing_dot(spell_key)
    return function(blackboard)
        local catalog = blackboard:get("module.combat.catalog")
        local _, target = H.player_and_target(blackboard)
        if not catalog or not target then
            return true
        end
        local spell = catalog:get(spell_key)
        if not spell then
            return true
        end
        local ids = spell.ranks or (spell.id and { spell.id }) or {}
        if #ids == 0 then
            return true
        end
        return not AuraCatalog.has_any_debuff(target, ids)
    end
end

-- ============================================================================
-- PET (VOIDWALKER)
-- ============================================================================

--- Set by warlock/pet_controller.lua:refresh on every tick_off_gcd.
function Cond.has_voidwalker(blackboard)
    return blackboard:get("combat.has_voidwalker", false) == true
end

function Cond.missing_voidwalker(blackboard)
    return blackboard:get("combat.has_voidwalker", false) ~= true
end

return Cond
