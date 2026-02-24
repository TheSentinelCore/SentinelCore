local BT = require("ai/BehaviorTree")
local S = BT.Status

local MaintenanceSubTree = {}

-- Rank tables: highest rank first. Resolved once at build time.
local SANCTITY_AURA_RANKS = { 20218 }
local BLESSING_OF_MIGHT_RANKS = { 27140, 25291, 19838, 19837, 19836, 19835, 19834, 19740 }
local SEAL_OF_BLOOD_RANKS = { 31892 }             -- Horde only
local SEAL_OF_COMMAND_RANKS = { 27170, 20920, 20919, 20918, 20915, 20375 }

--- Find the highest learned rank from a list of spell IDs (highest first).
---@param ranks number[]
---@return number|nil
local function best_rank(ranks)
    if not core or not core.spell_book or not core.spell_book.is_spell_learned then
        return ranks[1]
    end
    for i = 1, #ranks do
        if core.spell_book.is_spell_learned(ranks[i]) then
            return ranks[i]
        end
    end
    return nil
end

function MaintenanceSubTree.build(bb)
    -- Resolve best ranks once at tree-build time (spells don't change mid-session)
    local aura_id = best_rank(SANCTITY_AURA_RANKS)
    local bom_id = best_rank(BLESSING_OF_MIGHT_RANKS)
    local sob_id = best_rank(SEAL_OF_BLOOD_RANKS)
    local soc_id = best_rank(SEAL_OF_COMMAND_RANKS)

    return BT.Sequence:new("maintenance", {
        -- Gate: not in combat
        BT.Condition:new("not_in_combat", function()
            return not bb:get("player.in_combat", false)
        end),

        -- Fire-and-forget buff refresh. Always returns FAILURE so the
        -- ReactiveSelector continues to FindTarget/Pull/Explore.
        BT.Action:new("ensure_buffs", function()
            local player = bb:get("player.object")
            if not player then return S.FAILURE end

            local function has_aura(spell_id)
                if not spell_id then return true end -- skip if no rank available
                local ok, result = pcall(function()
                    if player.has_buff then return player:has_buff(spell_id) end
                    return false
                end)
                return ok and result
            end

            local function cast_on_self(spell_id)
                if not spell_id then return end
                if core.input and core.input.cast_target_spell then
                    pcall(function() core.input.cast_target_spell(spell_id, player) end)
                end
            end

            -- Cast one missing buff per tick (GCD limits us to one anyway)
            if not has_aura(aura_id) then
                cast_on_self(aura_id)
            elseif not has_aura(bom_id) then
                cast_on_self(bom_id)
            else
                -- Seal check: need explicit nil guard (has_aura(nil) returns true)
                local has_seal = (sob_id and has_aura(sob_id)) or (soc_id and has_aura(soc_id))
                if not has_seal then
                    cast_on_self(sob_id or soc_id)
                end
            end

            -- Always FAILURE: non-blocking side effect, selector continues
            return S.FAILURE
        end),
    })
end

return MaintenanceSubTree
