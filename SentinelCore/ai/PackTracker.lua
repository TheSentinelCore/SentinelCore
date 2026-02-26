local Helpers = require("lib/Helpers")

---@class PackTracker
---@field _pack table
local PackTracker = {}
PackTracker.__index = PackTracker

function PackTracker:new()
    return setmetatable({
        _pack = {
            targets = {},
            count = 0,
            centroid = { x = 0, y = 0, z = 0 },
            spread = 0,
            nearest_dist = math.huge,
            gathered_count = 0,
        },
    }, self)
end

---@return table
function PackTracker:get_pack()
    return self._pack
end

---Update pack state from visible hostile objects.
---@param hostiles table[] Array of game_object references
---@param player_pos table {x,y,z}
---@param player_guid string Player GUID for gathered detection
function PackTracker:update(hostiles, player_pos, player_guid)
    local targets = {}
    local positions = {}
    local sum_x, sum_y, sum_z = 0, 0, 0
    local nearest_dist = math.huge
    local gathered = 0

    for i = 1, #hostiles do
        local mob = hostiles[i]
        local ok, pos = pcall(function() return mob:get_position() end)
        if ok and pos then
            targets[#targets + 1] = mob
            positions[#positions + 1] = pos
            sum_x = sum_x + (pos.x or 0)
            sum_y = sum_y + (pos.y or 0)
            sum_z = sum_z + (pos.z or 0)

            local dist = Helpers.distance_3d(player_pos, pos)
            if dist < nearest_dist then
                nearest_dist = dist
            end

            -- Check if mob is aggroed to player
            local ok_c, in_combat = pcall(function() return mob:is_in_combat() end)
            if ok_c and in_combat then
                local ok_t, mob_target = pcall(function() return mob:get_target() end)
                if ok_t and mob_target then
                    local ok_g, tguid = pcall(function() return mob_target:get_guid() end)
                    if ok_g and tguid == player_guid then
                        gathered = gathered + 1
                    end
                end
            end
        end
    end

    local count = #targets
    local centroid = { x = 0, y = 0, z = 0 }
    local spread = 0

    if count > 0 then
        centroid.x = sum_x / count
        centroid.y = sum_y / count
        centroid.z = sum_z / count

        -- Spread = max distance from centroid (reuse cached positions)
        for i = 1, count do
            local d = Helpers.distance_3d(centroid, positions[i])
            if d > spread then spread = d end
        end
    end

    self._pack = {
        targets = targets,
        count = count,
        centroid = centroid,
        spread = spread,
        nearest_dist = count > 0 and nearest_dist or math.huge,
        gathered_count = gathered,
    }
end

---Find spatial clusters of hostiles using distance-based grouping.
---@param hostiles table[] Array of game_object references
---@param radius number Cluster radius in yards
---@return table[] Array of {centroid, count, targets} sorted by count desc
function PackTracker:find_clusters(hostiles, radius)
    local clusters = {}

    for i = 1, #hostiles do
        local mob = hostiles[i]
        local ok, pos = pcall(function() return mob:get_position() end)
        if ok and pos then
            local assigned = false
            for c = 1, #clusters do
                local cluster = clusters[c]
                if Helpers.distance_3d(cluster.centroid, pos) <= radius then
                    -- Add to existing cluster and recompute centroid
                    cluster.count = cluster.count + 1
                    cluster.targets[#cluster.targets + 1] = mob
                    cluster.centroid.x = (cluster.centroid.x * (cluster.count - 1) + pos.x) / cluster.count
                    cluster.centroid.y = (cluster.centroid.y * (cluster.count - 1) + pos.y) / cluster.count
                    cluster.centroid.z = (cluster.centroid.z * (cluster.count - 1) + pos.z) / cluster.count
                    assigned = true
                    break
                end
            end
            if not assigned then
                clusters[#clusters + 1] = {
                    centroid = { x = pos.x, y = pos.y, z = pos.z },
                    count = 1,
                    targets = { mob },
                }
            end
        end
    end

    -- Sort by count descending
    table.sort(clusters, function(a, b) return a.count > b.count end)
    return clusters
end

return PackTracker
