local BT = require("ai/BehaviorTree")
local S = BT.Status
local get_now = require("lib/TimeHelper").get_now

local MaintenanceService = {}

-- How often to re-check which spell rank the player has trained (seconds).
local RANK_REFRESH_INTERVAL = 30.0

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

-- Per-class buff definitions. Each entry is a list of rank arrays resolved via
-- best_rank(). Keys match slot names stored in the rank cache.
local CLASS_BUFFS = {
    -- Paladin (class_id = 2)
    [2] = {
        { key = "aura_id",  ranks = { 20218 } },                                                     -- Sanctity Aura
        { key = "bom_id",   ranks = { 25291, 19838, 19837, 19836, 19835, 19834, 19740 } },           -- Blessing of Might
        { key = "sob_id",   ranks = { 31892 } },                                                      -- Seal of Blood (Horde)
        { key = "soc_id",   ranks = { 27170, 20920, 20919, 20918, 20915, 20375 } },                  -- Seal of Command
    },
    -- Warlock (class_id = 9)
    [9] = {
        { key = "fel_armor_id",   ranks = { 28189, 28176 } },                                        -- Fel Armor (preferred)
        { key = "demon_armor_id", ranks = { 27260, 11735, 11734, 11733, 1086, 706 } },               -- Demon Armor (fallback)
        { key = "demon_skin_id",  ranks = { 696, 687 } },                                            -- Demon Skin (last resort)
    },
}

function MaintenanceService.build(bb)
    -- Lazy rank cache: refreshed every RANK_REFRESH_INTERVAL seconds so that
    -- training a new rank mid-session is picked up without a full relog.
    local rank_cache = { at = 0, class_id = 0 }

    local function refresh_ranks(now, class_id)
        if (now - rank_cache.at) < RANK_REFRESH_INTERVAL and rank_cache.class_id == class_id then
            return
        end
        local defs = CLASS_BUFFS[class_id] or {}
        for i = 1, #defs do
            rank_cache[defs[i].key] = best_rank(defs[i].ranks)
        end
        rank_cache.class_id = class_id
        rank_cache.at = now
    end

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

            local class_id = tonumber(bb:get("player.class_id", 0)) or 0
            local now = get_now()
            refresh_ranks(now, class_id)

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
            if class_id == 2 then
                -- Paladin: Sanctity Aura → Blessing of Might → active Seal
                local aura_id = rank_cache.aura_id
                local bom_id  = rank_cache.bom_id
                local sob_id  = rank_cache.sob_id
                local soc_id  = rank_cache.soc_id
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
            elseif class_id == 9 then
                -- Warlock: Fel Armor preferred, Demon Armor fallback, Demon Skin last resort
                local fel_id   = rank_cache.fel_armor_id
                local demon_id = rank_cache.demon_armor_id
                local skin_id  = rank_cache.demon_skin_id
                -- Nil-guard each component: has_aura(nil) returns true (skip), so we must
                -- check fel_id/demon_id/skin_id are non-nil before calling has_aura().
                -- Without the guard, a nil fel_id (not yet trained) would short-circuit the
                -- whole check to true and no armor would ever be cast.
                local has_armor = (fel_id and has_aura(fel_id))
                               or (demon_id and has_aura(demon_id))
                               or (skin_id and has_aura(skin_id))
                if not has_armor then
                    cast_on_self(fel_id or demon_id or skin_id)
                end
            end

            -- Always FAILURE: non-blocking side effect, selector continues
            return S.FAILURE
        end),
    })
end

return MaintenanceService
