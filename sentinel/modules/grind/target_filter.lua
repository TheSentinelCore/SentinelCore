local Compat = require("shared/compat")

local TargetFilter = {}

local CLUSTER_GRID_SIZE = 10

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
        local ok, name = pcall(unit.get_name, unit)
        return ok and name == ref
    end

    if type(ref) == "table" and ref.npc_id then
        local ok, npc_id = pcall(unit.get_npc_id, unit)
        if ok and npc_id and npc_id ~= 0 then
            return npc_id == ref.npc_id
        end
        -- Fall back to name match
        local ok_n, name = pcall(unit.get_name, unit)
        return ok_n and name == ref.name
    end

    return false
end

---Check if a single unit passes all filters for a given spot config.
---@param unit table Game object
---@param spot table Spot config with center, radius, level_min, level_max, mob_blacklist, mob_whitelist, creature_types, blackspots
---@param player_level number Current player level
---@param player table|nil Player game object (for can_attack check)
---@return boolean
function TargetFilter.passes(unit, spot, player_level, player)
    -- 1. Must be alive
    local ok_alive, alive = pcall(unit.is_alive, unit)
    if not ok_alive or not alive then
        return false
    end

    -- 2. Must be attackable by player
    if player and type(player.can_attack) == "function" then
        local ok, attackable = pcall(player.can_attack, player, unit)
        if ok and not attackable then
            return false
        end
    end

    -- 3. Must not be elite, rare, or worldboss (via get_classification)
    local ok_cls, classification = pcall(unit.get_classification, unit)
    if ok_cls and (classification == 1 or classification == 2 or classification == 3 or classification == 4) then
        return false
    end

    -- 4. Must be within spot's level range
    local ok_lv, level = pcall(unit.get_level, unit)
    if not ok_lv or type(level) ~= "number" then
        return false
    end
    if level < (spot.level_min or 1) or level > (spot.level_max or 70) then
        return false
    end

    -- 4b. Must match creature_types if specified
    if spot.creature_types and #spot.creature_types > 0 then
        local ok, ctype = pcall(unit.get_creature_type, unit)
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
    local ok_pos, upos = pcall(unit.get_position, unit)
    if not ok_pos or type(upos) ~= "table" then
        return false
    end
    local ux, uy, uz = upos.x, upos.y, upos.z
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

---Score a valid target using weighted multi-factor evaluation.
---Higher score = better target. All factors normalized to 0-1.
---@param unit table Game object
---@param player_pos table { x, y, z }
---@param player_level number
---@param spot table Spot config
---@param cluster_counts table Pre-computed cluster density counts per grid cell
---@return number score
local function score_target(unit, player_pos, player_level, spot, cluster_counts, opts)
    local ok_pos, upos = pcall(unit.get_position, unit)
    if not ok_pos or type(upos) ~= "table" then return 0 end
    local ux, uy, uz = upos.x, upos.y, upos.z

    -- Distance score (0.30): closer = higher, normalized over spot radius
    local dist = distance_3d(ux, uy, uz, player_pos.x, player_pos.y, player_pos.z)
    local max_dist = spot.radius or 80
    local dist_score = math.max(0, 1 - dist / max_dist)

    -- Level delta score (0.20): prefer targets at or slightly below player level
    local ok_lv, unit_level = pcall(unit.get_level, unit)
    if not ok_lv or type(unit_level) ~= "number" then unit_level = player_level end
    local delta = math.abs(unit_level - player_level)
    local level_score = math.max(0, 1 - delta / 5)
    -- Bonus for targets 1-2 levels below
    if unit_level >= player_level - 2 and unit_level <= player_level then
        level_score = math.min(1, level_score + 0.2)
    end

    -- Health score (0.20): prefer full-health targets (not already fighting)
    local hp_score = 1
    local ok_hp, cur_hp = pcall(unit.get_health, unit)
    local ok_mhp, max_hp = pcall(unit.get_max_health, unit)
    if ok_hp and ok_mhp and type(max_hp) == "number" and max_hp > 0 then
        hp_score = cur_hp / max_hp
    end

    -- In-combat penalty (0.10): penalize mobs already fighting something
    local combat_score = 1
    local ok_ic, in_combat = pcall(unit.is_in_combat, unit)
    if ok_ic and in_combat then
        combat_score = 0
    end

    -- Cluster density score (0.05): O(1) lookup using pre-computed spatial bucketing
    local cell_x = math.floor(ux / CLUSTER_GRID_SIZE)
    local cell_y = math.floor(uy / CLUSTER_GRID_SIZE)
    local cell_key = cell_x .. "," .. cell_y
    local nearby_count = (cluster_counts[cell_key] or 1) - 1 -- Exclude self
    local cluster_score = math.max(0, 1 - nearby_count / 4)

    -- Threat heat score (0.15): penalize targets in high-threat areas
    local threat_score = 1
    if opts and opts.threat_map and opts.now_ms then
        local heat = opts.threat_map:get_heat({x = ux, y = uy, z = uz}, 20, opts.now_ms)
        if heat > 0 then
            threat_score = math.max(0, 1 - heat / 20)
        end
    end

    return dist_score * 0.30
         + level_score * 0.20
         + hp_score * 0.20
         + combat_score * 0.10
         + cluster_score * 0.05
         + threat_score * 0.15
end

---Pre-compute cluster density counts using spatial bucketing (O(N) total).
---@param units table[] All valid units with pre-fetched positions
---@return table cluster_counts Grid cell key → count
local function compute_cluster_counts(units)
    local counts = {}
    for _, data in ipairs(units) do
        local cell_x = math.floor(data.ux / CLUSTER_GRID_SIZE)
        local cell_y = math.floor(data.uy / CLUSTER_GRID_SIZE)
        local key = cell_x .. "," .. cell_y
        counts[key] = (counts[key] or 0) + 1
    end
    return counts
end

---Find the best valid target from a list of units using weighted scoring.
---@param units table[] Array of game objects
---@param spot table Spot config
---@param player_level number Current player level
---@param player_pos table { x, y, z } player position
---@param player table|nil Player game object
---@param opts table|nil Optional { threat_map, now_ms } for threat-aware scoring
---@return table|nil unit The best scoring valid unit, or nil
function TargetFilter.select_best(units, spot, player_level, player_pos, player, opts)
    -- Pre-filter: collect all valid targets with pre-fetched positions (O(N))
    local valid = {}
    for _, unit in ipairs(units) do
        local ok, result = pcall(TargetFilter.passes, unit, spot, player_level, player)
        if ok and result then
            local ok_pos, upos = pcall(unit.get_position, unit)
            if ok_pos and type(upos) == "table" then
                valid[#valid + 1] = {
                    unit = unit,
                    ux = upos.x or 0,
                    uy = upos.y or 0,
                    uz = upos.z or 0,
                }
            end
        end
    end

    if #valid == 0 then return nil end

    -- Pre-compute cluster density once (O(N) total, replaces O(N²) inner loop)
    local cluster_counts = compute_cluster_counts(valid)

    -- Score and pick best
    local best = nil
    local best_score = -1
    for _, data in ipairs(valid) do
        local ok, s = pcall(score_target, data.unit, player_pos, player_level, spot, cluster_counts, opts)
        if ok and type(s) == "number" and s > best_score then
            best_score = s
            best = data.unit
        end
    end

    return best
end

return TargetFilter
