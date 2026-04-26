-- StateBuffing.lua — Apply buffs and drink to mana before travel.
-- Designed to be resilient: SpellCatalog is used opportunistically but
-- the transition to the next state depends only on mana level + a short
-- timeout, NOT on successful buff detection.

local helpers = require("lib/helpers")

local StateBuffing = { name = "BUFFING" }

-- Fallback hardcoded spell IDs for level 50-70 range (highest first).
-- Used when SpellCatalog can't resolve a spell via has_spell().
local ICE_ARMOR_IDS           = { 10220, 10219, 7320, 7302 }              -- R4→R1
local ICE_BARRIER_IDS         = { 13033, 13032, 13031, 11426 }             -- R7→R4
local MANA_SHIELD_IDS         = { 27131, 10193, 10192, 10191, 8494, 8493 } -- R7→R2
local CONJURE_WATER_IDS_SPELL = { 27090, 10139, 10138, 7328 }              -- R8→R5

-- All known conjured water item IDs (ranks 1-8, TBC)
local CONJURE_WATER_ITEMS = {
    [5350]  = true,  -- R1/R2
    [7819]  = true,  -- R3
    [7820]  = true,  -- R4
    [7821]  = true,  -- R5
    [17711] = true,  -- R6
    [17712] = true,  -- R7 (Conjured Glacier Water, level 55 — most likely at 58)
    [22018] = true,  -- R8 TBC max
}

-- After this many ms with mana >= 80%, proceed without waiting for buffs.
local MANA_READY_PCT    = 0.80
-- Hard bail-out timeout regardless of mana.
local HARD_TIMEOUT_MS   = 20000
local MIN_CAST_GAP_MS   = 600

--- Check for any aura from a list of IDs.
local function has_any_aura(player, ids)
    if not player then return false end
    local ok, data = pcall(player.get_buff_data, player, ids)
    return ok and data ~= nil
end

--- Try to cast a self-spell from a list (first success wins).
local function try_cast_list(ids)
    local ok_pl, player = pcall(core.object_manager.get_local_player)
    if not ok_pl or not player then return false end
    for _, id in ipairs(ids) do
        local ok = select(1, pcall(core.input.cast_target_spell, id, player))
        if ok then return true end
    end
    return false
end

--- Count conjured water slots in bags 0-4 (1 count per slot).
local function count_water()
    local count = 0
    for bag_id = 0, 4 do
        local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
        if ok and type(items) == "table" then
            for _, slot_entry in ipairs(items) do
                local obj = slot_entry and slot_entry.object
                if obj then
                    local ok_id, item_id = pcall(obj.get_item_id, obj)
                    if ok_id and item_id and CONJURE_WATER_ITEMS[item_id] then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

--- Drink the first conjured water found in bags.
local function drink_water()
    for bag_id = 0, 4 do
        local ok, items = pcall(core.inventory.get_items_in_bag, bag_id)
        if ok and type(items) == "table" then
            for _, slot_entry in ipairs(items) do
                local obj = slot_entry and slot_entry.object
                if obj then
                    local ok_id, item_id = pcall(obj.get_item_id, obj)
                    if ok_id and item_id and CONJURE_WATER_ITEMS[item_id] then
                        pcall(core.input.use_item, item_id)
                        return true
                    end
                end
            end
        end
    end
    return false
end

function StateBuffing:create(ctx)
    local bb = ctx.bb
    local sc = ctx.spell_catalog  -- may be nil or have failing resolve()

    local last_cast_ms = 0
    local enter_ms     = 0
    local frame_count  = 0

    return {
        enter = function(_bb)
            helpers.log("[BUFFING] enter")
            last_cast_ms = 0
            enter_ms     = helpers.game_time_ms()
            frame_count  = 0
        end,

        update = function(_bb)
            -- Guard: if the player is dead or a ghost, hand off to DEAD immediately.
            if bb:get("player.is_dead", false) or bb:get("player.is_ghost", false) then
                return "DEAD"
            end

            local ok_pl, player = pcall(core.object_manager.get_local_player)
            if not ok_pl or not player then return end

            local gt     = helpers.game_time_ms()
            local mp_pct = bb:get("player.mp_pct", 1.0)
            frame_count  = frame_count + 1

            -- ── HARD TIMEOUT ────────────────────────────────────────────
            -- Use both ms-based and frame-based timeouts as backup.
            local elapsed_ms = (gt > enter_ms) and (gt - enter_ms) or 0
            if elapsed_ms > HARD_TIMEOUT_MS or frame_count > 1200 then
                helpers.log("[BUFFING] timeout (" .. elapsed_ms .. "ms / " .. frame_count
                    .. " frames) — proceeding with mp=" .. string.format("%.0f%%", mp_pct * 100))
                return "TRAVEL_TO_INSTANCE"
            end

            -- ── MANA-READY EXIT ─────────────────────────────────────────
            -- If mana is at the threshold and we've been in this state for
            -- at least 2 seconds (avoid immediate exit on enter), move on.
            if mp_pct >= MANA_READY_PCT and elapsed_ms >= 2000 then
                helpers.log("[BUFFING] mana ready — proceeding")
                return "TRAVEL_TO_INSTANCE"
            end

            -- ── DRINK ───────────────────────────────────────────────────
            if mp_pct < MANA_READY_PCT then
                if drink_water() then return end
            end

            -- ── SPELL CASTING ───────────────────────────────────────────
            if gt - last_cast_ms < MIN_CAST_GAP_MS then return end

            -- Ice Armor (try SpellCatalog first, fall back to hardcoded)
            if not has_any_aura(player, ICE_ARMOR_IDS) then
                local cast_ok = false
                if sc then
                    local id = sc:resolve("Ice Armor", player)
                    if id then
                        cast_ok = select(1, pcall(core.input.cast_target_spell, id, player))
                    end
                end
                if not cast_ok then
                    cast_ok = try_cast_list(ICE_ARMOR_IDS)
                end
                if cast_ok then last_cast_ms = gt; return end
            end

            -- Ice Barrier
            if not has_any_aura(player, ICE_BARRIER_IDS) then
                local cast_ok = false
                if sc then
                    local id = sc:resolve("Ice Barrier", player)
                    if id then
                        cast_ok = select(1, pcall(core.input.cast_target_spell, id, player))
                    end
                end
                if not cast_ok then
                    cast_ok = try_cast_list(ICE_BARRIER_IDS)
                end
                if cast_ok then last_cast_ms = gt; return end
            end

            -- Mana Shield
            if not has_any_aura(player, MANA_SHIELD_IDS) then
                local cast_ok = false
                if sc then
                    local id = sc:resolve("Mana Shield", player)
                    if id then
                        cast_ok = select(1, pcall(core.input.cast_target_spell, id, player))
                    end
                end
                if not cast_ok then
                    cast_ok = try_cast_list(MANA_SHIELD_IDS)
                end
                if cast_ok then last_cast_ms = gt; return end
            end

            -- Conjure Water if low
            if count_water() < 5 then
                local cast_ok = false
                if sc then
                    local id = sc:resolve("Conjure Water", player)
                    if id then
                        cast_ok = select(1, pcall(core.input.cast_target_spell, id, player))
                    end
                end
                if not cast_ok then
                    cast_ok = try_cast_list(CONJURE_WATER_IDS_SPELL)
                end
                if cast_ok then last_cast_ms = gt; return end
            end
        end,

        exit = function(_bb)
            helpers.log("[BUFFING] exit")
        end,
    }
end

return StateBuffing
