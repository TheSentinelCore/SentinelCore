---@module BGBOT.core.perception.filters
-- Object-type and ring filtering for Perception layer.
-- Filters raw game_objects from scans into trackable entities.

local constants = require("shared/constants")

local filters = {}

local function safe_call_method(obj, method_name, ...)
    if not obj then
        return nil, false
    end
    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil, false
    end

    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, false
    end
    return result, true
end

local function safe_bool(obj, method_name, ...)
    local value, ok = safe_call_method(obj, method_name, ...)
    return ok and value == true
end

----------------------------------------------------------------------
-- Player Classification
----------------------------------------------------------------------
-- Some client builds may expose PvP players as generic units where
-- is_player() is false but npc_id == 0 and class_id > 0.
----------------------------------------------------------------------

---@param obj game_object
---@return boolean
function filters.is_player_like(obj)
    if not safe_bool(obj, "is_valid") then return false end

    if safe_bool(obj, "is_player") then
        return true
    end

    if not safe_bool(obj, "is_unit") or safe_bool(obj, "is_basic_object") then
        return false
    end

    local npc_id = tonumber(select(1, safe_call_method(obj, "get_npc_id"))) or 0
    if npc_id ~= 0 then
        return false
    end

    local class_id = tonumber(select(1, safe_call_method(obj, "get_class"))) or 0
    if class_id <= 0 then
        return false
    end

    local name = select(1, safe_call_method(obj, "get_name"))
    if not name or name == "" then
        return false
    end

    return true
end

----------------------------------------------------------------------
-- Object Type Filter
----------------------------------------------------------------------
-- Only track:
--   • Players (is_player() == true) and player-like unit fallback
--   • Basic objects matching known WSG NPC IDs (flags, power-ups)
-- Ignore: critters, items, pets, minions, non-WSG objects.
----------------------------------------------------------------------

---@param obj game_object
---@return boolean  true if this object should be tracked
function filters.is_trackable(obj)
    if not safe_bool(obj, "is_valid") then return false end

    -- Players (including player-like unit fallback) are always tracked
    if filters.is_player_like(obj) then return true end

    -- BG-specific basic objects (flags, buffs, banners, cap points)
    if safe_bool(obj, "is_basic_object") then
        local npc_id = select(1, safe_call_method(obj, "get_npc_id"))
        -- Check unified cross-BG table first, then legacy WSG table for compat
        if npc_id and (constants.BG_OBJECT_IDS[npc_id] or constants.WSG_OBJECT_IDS[npc_id]) then
            return true
        end
    end

    return false
end

----------------------------------------------------------------------
-- Ring Assignment
----------------------------------------------------------------------
-- Near:     0 – NEAR_MAX yards   (high-frequency updates)
-- Tactical: NEAR_MAX – TACTICAL_MAX  (medium-frequency)
-- Far:      > TACTICAL_MAX       (low-frequency / full-scan only)
----------------------------------------------------------------------

---@param distance number  yards from local player
---@return string  "near" | "tactical" | "far"
function filters.assign_ring(distance)
    if distance <= constants.RING.NEAR_MAX then
        return "near"
    elseif distance <= constants.RING.TACTICAL_MAX then
        return "tactical"
    else
        return "far"
    end
end

----------------------------------------------------------------------
-- Scan Priority (for budget overflow)
----------------------------------------------------------------------
-- Returns a numeric priority; higher = scan first.
----------------------------------------------------------------------

---@param obj game_object
---@param local_player game_object
---@return number  priority value (higher = more important)
function filters.scan_priority(obj, local_player)
    -- Self is always highest
    if obj == local_player then return 1000 end

    local score = 0

    -- Flag carriers are critical
    local auras = select(1, safe_call_method(obj, "get_auras"))
    if auras then
        for _, aura in pairs(auras) do
            local id = aura.buff_id or 0
            if id == constants.FLAG_AURAS.HORDE_FLAG
            or id == constants.FLAG_AURAS.ALLIANCE_FLAG then
                score = score + 500
                break
            end
        end
    end

    -- Enemies targeting us
    local target = select(1, safe_call_method(obj, "get_target"))
    if target and target == local_player then
        score = score + 200
    end

    -- Enemy vs ally
    if safe_bool(obj, "is_enemy_with", local_player) then
        score = score + 100
    else
        score = score + 50
    end

    return score
end

return filters
