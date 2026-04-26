-- AoeRotation.lua — Frost Mage AoE rotation for the farm loop.
-- Per design doc §7.3.

local helpers     = require("lib/helpers")
local unit_helper = require("common/izi_sdk")

---@class AoeRotation
local AoeRotation = {}
AoeRotation.__index = AoeRotation

-- Spell IDs (resolved via SpellCatalog for highest rank)
local BLIZZARD_ID    = 27085
local FROST_NOVA_ID  = 27088
local ICE_BLOCK_ID   = 45438
local COLD_SNAP_ID   = 11958
local EVOCATION_ID   = 12051
local ICE_BARRIER_ID = 13033

local BLIZZARD_CHANNEL_MS    = 7500   -- recast after this many ms
local MOB_SCAN_INTERVAL_MS   = 500
local EVOCATION_SAFE_RANGE   = 8.0
local MIN_CAST_GAP_MS        = 150

---@param spell_catalog table
---@param blackboard    table
---@return AoeRotation
function AoeRotation:new(spell_catalog, blackboard)
    return setmetatable({
        _sc                = spell_catalog,
        _bb                = blackboard,
        _last_cast_ms      = 0,
        _last_scan_ms      = 0,
        _empty_scans       = 0,
    }, AoeRotation)
end

local function cast_self(spell_id)
    local ok_pl, player = pcall(core.object_manager.get_local_player)
    if not ok_pl or not player then return false end
    return select(1, pcall(core.input.cast_target_spell, spell_id, player))
end

local function cast_position(spell_id, pos)
    return select(1, pcall(core.input.cast_position_spell, spell_id, pos))
end

local function has_buff(player, aura_id)
    if not player then return false end
    local ok, data = pcall(player.get_buff_data, player, { aura_id })
    return ok and data ~= nil
end

local function get_enemy_count(center, radius)
    local ok, enemies = pcall(unit_helper.get_enemy_list_around, unit_helper, center, radius, false, false)
    if ok and type(enemies) == "table" then return #enemies end
    return 0
end

--- Tick the AoE rotation. Call every frame during FARM_AOE_BOTH (and opener).
---@param player       table   game_object
---@param blizzard_center table  vec3
---@param game_time_ms  number
function AoeRotation:tick(player, blizzard_center, game_time_ms)
    if not player then return end
    if game_time_ms - self._last_cast_ms < MIN_CAST_GAP_MS then return end

    local hp_pct = self._bb:get("player.hp_pct", 1.0)
    local mp_pct = self._bb:get("player.mp_pct", 1.0)
    local ib_cast_ms = self._bb:get("duo.ice_block_cast_ms", 0)
    local ib_active  = (game_time_ms - ib_cast_ms) < 10000

    -- 1. Emergency Ice Block on HP < 20% — fires even while channeling
    if hp_pct < 0.20 and not ib_active then
        local ib_id = self._sc:resolve("Ice Block", player)
        if ib_id then
            cast_self(ib_id)
            self._bb:set("duo.ice_block_cast_ms", game_time_ms)
            self._last_cast_ms = game_time_ms
            helpers.log("[AoE] Ice Block emergency")
            return
        end
        -- Cold Snap to reset IB
        local cs_id = self._sc:resolve("Cold Snap", player)
        if cs_id and self._sc:is_ready("Cold Snap", player) then
            cast_self(cs_id)
            self._last_cast_ms = game_time_ms
            return
        end
    end

    -- Non-emergency actions: don't interrupt an active channel
    if self._bb:get("player.is_casting", false) then return end

    -- 2. Ice Barrier if missing
    if not has_buff(player, ICE_BARRIER_ID) then
        local bar_id = self._sc:resolve("Ice Barrier", player)
        if bar_id and self._sc:is_ready("Ice Barrier", player) then
            if cast_self(bar_id) then
                self._last_cast_ms = game_time_ms
                return
            end
        end
    end

    -- 3. Mob scan
    if game_time_ms - self._last_scan_ms >= MOB_SCAN_INTERVAL_MS and blizzard_center then
        self._last_scan_ms = game_time_ms
        local count = get_enemy_count(blizzard_center, 25)
        if count == 0 then
            self._empty_scans = self._empty_scans + 1
            if self._empty_scans >= 2 then
                self._bb:set("duo.all_mobs_dead", true)
                helpers.log("[AoE] all mobs dead — empty scan x2")
            end
        else
            self._empty_scans = 0
            self._bb:set("duo.all_mobs_dead", false)
        end
    end

    -- Don't cast if all dead
    if self._bb:get("duo.all_mobs_dead", false) then return end

    -- 4. Blizzard recast
    if blizzard_center then
        local channel_start = self._bb:get("duo.blizzard_channel_start_ms", 0)
        local blizz_id = self._sc:resolve("Blizzard", player)
        if blizz_id and (game_time_ms - channel_start >= BLIZZARD_CHANNEL_MS) then
            if cast_position(blizz_id, blizzard_center) then
                self._bb:set("duo.blizzard_channel_start_ms", game_time_ms)
                self._last_cast_ms = game_time_ms
                return
            end
        end
    end

    -- 5. Frost Nova if mobs not all rooted (off CD)
    local nova_id = self._sc:resolve("Frost Nova", player)
    if nova_id and self._sc:is_ready("Frost Nova", player) then
        if cast_self(nova_id) then
            self._last_cast_ms = game_time_ms
            return
        end
    end

    -- 6. Cold Snap if mana < 20%
    if mp_pct < 0.20 then
        local cs_id = self._sc:resolve("Cold Snap", player)
        if cs_id and self._sc:is_ready("Cold Snap", player) then
            cast_self(cs_id)
            self._last_cast_ms = game_time_ms
            return
        end
    end

    -- 7. Evocation if mana < 15% and safe
    if mp_pct < 0.15 then
        local evo_id = self._sc:resolve("Evocation", player)
        local ok_pos, player_pos = pcall(player.get_position, player)
        local safe = true
        if ok_pos and player_pos and blizzard_center then
            safe = (get_enemy_count(player_pos, EVOCATION_SAFE_RANGE) == 0)
        end
        if evo_id and safe and self._sc:is_ready("Evocation", player) then
            cast_self(evo_id)
            self._last_cast_ms = game_time_ms
            return
        end
    end
end

--- Reset mob-dead tracking when entering a new pull.
function AoeRotation:reset()
    self._empty_scans = 0
    self._last_scan_ms = 0
    self._last_cast_ms = 0
end

return AoeRotation
