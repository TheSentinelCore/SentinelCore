local TargetFilter = {}

local function distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Check if a unit matches an NPC reference (table with npc_id/name, or legacy string).
---@param unit table Game object
---@param ref table|string NpcRef { npc_id = number, name = string } or plain name string
---@return boolean
local function matches_npc_ref(unit, ref)
    if type(ref) == "string" then
        return unit:get_name() == ref
    end

    if type(ref) == "table" and ref.npc_id then
        local ok, npc_id = pcall(function()
            return unit:get_npc_id()
        end)
        if ok and npc_id and npc_id ~= 0 then
            return npc_id == ref.npc_id
        end
        -- Fall back to name match
        return unit:get_name() == ref.name
    end

    return false
end

---Check if a single unit passes all filters for a given spot config.
---@param unit table Game object with get_position, get_level, get_name, is_alive, is_tapped_by_other, is_elite, is_rare
---@param spot table Spot config with center, radius, level_min, level_max, mob_blacklist, mob_whitelist, creature_types, blackspots
---@param player_level number Current player level (unused, reserved for future level-delta checks)
---@return boolean
function TargetFilter.passes(unit, spot, player_level)
    -- 1. Must be alive
    if not unit:is_alive() then
        return false
    end

    -- 2. Must not be tapped by other
    if unit:is_tapped_by_other() then
        return false
    end

    -- 3. Must not be elite or rare
    if unit:is_elite() or unit:is_rare() then
        return false
    end

    -- 4. Must be within spot's level range
    local level = unit:get_level()
    if level < (spot.level_min or 1) or level > (spot.level_max or 70) then
        return false
    end

    -- 4b. Must match creature_types if specified
    if spot.creature_types and #spot.creature_types > 0 then
        local ok, ctype = pcall(function()
            return unit:get_creature_type()
        end)
        if not ok then
            ctype = 0
        end
        local type_found = false
        for _, ct in ipairs(spot.creature_types) do
            if ctype == ct then
                type_found = true
                break
            end
        end
        if not type_found then
            return false
        end
    end

    -- 5. Must be within spot's radius from center
    local ux, uy, uz = unit:get_position()
    local center = spot.center
    local dist = distance_3d(ux, uy, uz, center.x, center.y, center.z)
    if dist > (spot.radius or 80) then
        return false
    end

    -- 5b. Must not be inside any blackspot
    if spot.blackspots and #spot.blackspots > 0 then
        for _, bs in ipairs(spot.blackspots) do
            local bs_dist = distance_3d(ux, uy, uz, bs.x, bs.y, bs.z)
            if bs_dist <= (bs.radius or 20) then
                return false
            end
        end
    end

    -- 6. Must not be in mob_blacklist (by NpcRef or name)
    if spot.mob_blacklist then
        for _, ref in ipairs(spot.mob_blacklist) do
            if matches_npc_ref(unit, ref) then
                return false
            end
        end
    end

    -- 7. If mob_whitelist is non-empty, must be in whitelist (by NpcRef or name)
    if spot.mob_whitelist and #spot.mob_whitelist > 0 then
        local found = false
        for _, ref in ipairs(spot.mob_whitelist) do
            if matches_npc_ref(unit, ref) then
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end

    return true
end

---Find the closest valid target from a list of units.
---@param units table[] Array of game objects
---@param spot table Spot config
---@param player_level number Current player level
---@param player_pos table { x, y, z } player position
---@return table|nil unit The closest valid unit, or nil
function TargetFilter.select_best(units, spot, player_level, player_pos)
    local best = nil
    local best_dist = math.huge

    for _, unit in ipairs(units) do
        if TargetFilter.passes(unit, spot, player_level) then
            local ux, uy, uz = unit:get_position()
            local dist = distance_3d(ux, uy, uz, player_pos.x, player_pos.y, player_pos.z)
            if dist < best_dist then
                best_dist = dist
                best = unit
            end
        end
    end

    return best
end

return TargetFilter
