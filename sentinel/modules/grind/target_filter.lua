local TargetFilter = {}

local function distance_3d(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---Check if a single unit passes all filters for a given spot config.
---@param unit table Game object with get_position, get_level, get_name, is_alive, is_tapped_by_other, is_elite, is_rare
---@param spot table Spot config with center, radius, level_min, level_max, mob_blacklist, mob_whitelist
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

    -- 5. Must be within spot's radius from center
    local ux, uy, uz = unit:get_position()
    local center = spot.center
    local dist = distance_3d(ux, uy, uz, center.x, center.y, center.z)
    if dist > (spot.radius or 80) then
        return false
    end

    -- 6. Must not be in mob_blacklist (by name)
    local name = unit:get_name()
    if spot.mob_blacklist then
        for _, bl_name in ipairs(spot.mob_blacklist) do
            if name == bl_name then
                return false
            end
        end
    end

    -- 7. If mob_whitelist is non-empty, must be in whitelist (by name)
    if spot.mob_whitelist and #spot.mob_whitelist > 0 then
        local found = false
        for _, wl_name in ipairs(spot.mob_whitelist) do
            if name == wl_name then
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
