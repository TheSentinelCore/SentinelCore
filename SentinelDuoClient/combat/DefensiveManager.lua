-- DefensiveManager.lua — Tracks and uses defensive cooldowns.
-- Ice Barrier, Ice Block, Cold Snap.

local helpers = require("lib/helpers")

---@class DefensiveManager
local DefensiveManager = {}
DefensiveManager.__index = DefensiveManager

-- Spell IDs
local ICE_BARRIER_ID = 13033   -- rank 7
local ICE_BLOCK_ID   = 45438
local COLD_SNAP_ID   = 11958

local IB_DURATION_MS       = 10000
local ICE_BARRIER_BUFF_ID  = 13033

---@param spell_catalog table  SpellCatalog
---@param blackboard    table  Blackboard
---@return DefensiveManager
function DefensiveManager:new(spell_catalog, blackboard)
    return setmetatable({
        _sc             = spell_catalog,
        _bb             = blackboard,
        _last_cast_ms   = 0,
        _min_cast_gap   = 100,  -- ms between casts
    }, DefensiveManager)
end

local function has_buff(player, aura_id)
    if not player then return false end
    local ok, data = pcall(player.get_buff_data, player, { aura_id })
    return ok and data ~= nil
end

local function cast_self(spell_id)
    local ok_pl, player = pcall(core.object_manager.get_local_player)
    if not ok_pl or not player then return false end
    return select(1, pcall(core.input.cast_target_spell, spell_id, player))
end

--- Tick defensive logic. Should be called every frame in farm states.
---@param player table  game_object
---@param game_time_ms number
function DefensiveManager:tick(player, game_time_ms)
    if not player then return end
    if game_time_ms - self._last_cast_ms < self._min_cast_gap then return end

    local hp_pct = self._bb:get("player.hp_pct", 1.0)

    -- 1. Emergency Ice Block on HP < 20%
    if hp_pct < 0.20 then
        local ib_cast_ms = self._bb:get("duo.ice_block_cast_ms", 0)
        local ib_active  = (game_time_ms - ib_cast_ms) < IB_DURATION_MS
        if not ib_active then
            local ib_id = self._sc:resolve("Ice Block", player)
            if ib_id then
                if cast_self(ib_id) then
                    self._bb:set("duo.ice_block_cast_ms", game_time_ms)
                    self._last_cast_ms = game_time_ms
                    helpers.log("[Defensive] Ice Block — emergency HP=" .. math.floor(hp_pct*100) .. "%")
                    return
                end
                -- Try Cold Snap first if IB on CD
                local cs_id = self._sc:resolve("Cold Snap", player)
                if cs_id and self._sc:is_ready("Cold Snap", player) then
                    cast_self(cs_id)
                    self._last_cast_ms = game_time_ms
                end
            end
        end
    end

    -- 2. Ice Barrier if missing
    if not has_buff(player, ICE_BARRIER_BUFF_ID) then
        local bar_id = self._sc:resolve("Ice Barrier", player)
        if bar_id and self._sc:is_ready("Ice Barrier", player) then
            if cast_self(bar_id) then
                self._last_cast_ms = game_time_ms
                helpers.log("[Defensive] Ice Barrier refreshed")
            end
        end
    end
end

--- Returns true if the player is currently in Ice Block.
---@param game_time_ms number
---@return boolean
function DefensiveManager:is_in_ice_block(game_time_ms)
    local cast_ms = self._bb:get("duo.ice_block_cast_ms", 0)
    return (game_time_ms - cast_ms) < IB_DURATION_MS
end

return DefensiveManager
