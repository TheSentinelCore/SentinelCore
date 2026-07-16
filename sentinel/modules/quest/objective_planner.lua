local ObjectivePlanner = {}
ObjectivePlanner.__index = ObjectivePlanner

local DBSCAN = {}
DBSCAN.__index = DBSCAN

---Create a new DBSCAN clusterer
---@param eps number Epsilon radius in yards (default 50)
---@param min_pts number Minimum points to form cluster (default 3)
---@return table
function DBSCAN.new(eps, min_pts)
    return setmetatable({
        eps = eps or 50,
        min_pts = min_pts or 3,
        visited = {},
        cluster_id = 0,
    }, DBSCAN)
end

---Run DBSCAN on points
---@param points table[] Array of {x, y, z, data}
---@return table[] clusters, table noise
function DBSCAN:run(points)
    self.visited = {}
    self.cluster_id = 0
    local clusters = {}
    local noise = {}
    
    for i, point in ipairs(points) do
        if not self.visited[i] then
            self.visited[i] = true
            local neighbors = self:region_query(points, i)
            
            if #neighbors < self.min_pts then
                noise[#noise + 1] = point
            else
                self.cluster_id = self.cluster_id + 1
                local cluster = {}
                self:expand_cluster(points, i, neighbors, cluster)
                clusters[self.cluster_id] = cluster
            end
        end
    end
    
    return clusters, noise
end

---Find all points within eps of point at index
---@param points table[]
---@param idx integer
---@return integer[]
function DBSCAN:region_query(points, idx)
    local p = points[idx]
    local neighbors = {}
    local eps_sq = self.eps * self.eps
    
    for j, other in ipairs(points) do
        if j ~= idx then
            local dx = (p.x or 0) - (other.x or 0)
            local dy = (p.y or 0) - (other.y or 0)
            local dz = (p.z or 0) - (other.z or 0)
            if dx*dx + dy*dy + dz*dz <= eps_sq then
                neighbors[#neighbors + 1] = j
            end
        end
    end
    
    return neighbors
end

---Expand cluster from seed point
---@param points table[]
---@param idx integer
---@param neighbors integer[]
---@param cluster table
function DBSCAN:expand_cluster(points, idx, neighbors, cluster)
    cluster[#cluster + 1] = points[idx]
    points[idx]._cluster = self.cluster_id
    
    local i = 1
    while i <= #neighbors do
        local n_idx = neighbors[i]
        if not self.visited[n_idx] then
            self.visited[n_idx] = true
            local n_neighbors = self:region_query(points, n_idx)
            if #n_neighbors >= self.min_pts then
                -- Merge neighbors
                for _, nn in ipairs(n_neighbors) do
                    local found = false
                    for _, existing in ipairs(neighbors) do
                        if existing == nn then found = true break end
                    end
                    if not found then
                        neighbors[#neighbors + 1] = nn
                    end
                end
            end
        end
        
        if not points[n_idx]._cluster then
            cluster[#cluster + 1] = points[n_idx]
            points[n_idx]._cluster = self.cluster_id
        end
        i = i + 1
    end
end

---Calculate cluster center from points
---@param points table[]
---@return table center {x, y, z}
local function cluster_center(points)
    if #points == 0 then return {x=0, y=0, z=0} end
    local sum_x, sum_y, sum_z = 0, 0, 0
    for _, p in ipairs(points) do
        sum_x = sum_x + (p.x or 0)
        sum_y = sum_y + (p.y or 0)
        sum_z = sum_z + (p.z or 0)
    end
    return {x = sum_x / #points, y = sum_y / #points, z = sum_z / #points}
end

---Calculate cluster radius
---@param points table[]
---@param center table
---@return number radius
local function cluster_radius(points, center)
    local max_dist = 0
    for _, p in ipairs(points) do
        local dx = (p.x or 0) - (center.x or 0)
        local dy = (p.y or 0) - (center.y or 0)
        local dz = (p.z or 0) - (center.z or 0)
        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
        max_dist = math.max(max_dist, dist)
    end
    return max_dist
end

---Nearest-neighbor TSP approximation for cluster sequencing
---@param clusters table[] Each has center
---@param start_pos table {x,y,z}
---@return table[] ordered_clusters
local function sequence_clusters(clusters, start_pos)
    local unvisited = {}
    for i, c in ipairs(clusters) do
        unvisited[i] = c
    end
    
    local ordered = {}
    local current = start_pos
    
    while #unvisited > 0 do
        local best_idx, best_dist = 1, math.huge
        for i, cluster in ipairs(unvisited) do
            local center = cluster.center
            local dx = (current.x or 0) - (center.x or 0)
            local dy = (current.y or 0) - (center.y or 0)
            local dz = (current.z or 0) - (center.z or 0)
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            if dist < best_dist then
                best_dist = dist
                best_idx = i
            end
        end
        
        ordered[#ordered + 1] = unvisited[best_idx]
        current = unvisited[best_idx].center
        table.remove(unvisited, best_idx)
    end
    
    return ordered
end

---Generate waypoints for a cluster (spiral around center)
---@param cluster table
---@return table[] waypoints
local function generate_cluster_waypoints(cluster)
    local waypoints = {}
    local center = cluster.center
    local radius = cluster.radius
    
    -- Add center point
    waypoints[#waypoints + 1] = {x = center.x, y = center.y, z = center.z}
    
    -- Add perimeter points at 90 degree intervals
    for i = 0, 3 do
        local angle = i * math.pi / 2
        waypoints[#waypoints + 1] = {
            x = center.x + math.cos(angle) * radius * 0.7,
            y = center.y + math.sin(angle) * radius * 0.7,
            z = center.z,
        }
    end
    
    return waypoints
end

---ObjectivePlanner module
function ObjectivePlanner.new()
    return setmetatable({
        _dbscan = DBSCAN.new(50, 3),
    }, ObjectivePlanner)
end

---Cluster objectives by spawn positions
---@param objectives table[] Each has {type, target_id, count, spawn_positions[], text}
---@param eps number Clustering radius
---@param min_pts number Min points per cluster
---@return table[] clusters, table noise
function ObjectivePlanner:cluster_objectives(objectives, eps, min_pts)
    self._dbscan.eps = eps or 50
    self._dbscan.min_pts = min_pts or 3
    
    -- Build points from spawn positions
    local points = {}
    local point_to_obj = {}
    
    for obj_idx, obj in ipairs(objectives) do
        local positions = obj.spawn_positions or {}
        if #positions == 0 and obj.questie_positions then
            -- Fallback to Questie data
            positions = obj.questie_positions
        end
        
        for _, pos in ipairs(positions) do
            local point = {
                x = pos.x, y = pos.y, z = pos.z,
                objective = obj,
                objective_index = obj_idx,
                spawn_id = pos.spawn_id,
            }
            points[#points + 1] = point
            point_to_obj[#points] = obj
        end
    end
    
    if #points == 0 then
        return {}, {}
    end
    
    local clusters, noise = self._dbscan:run(points)
    
    -- Convert to cluster format
    local result_clusters = {}
    for cid, cluster_points in pairs(clusters) do
        local center = cluster_center(cluster_points)
        local radius = cluster_radius(cluster_points, center)
        
        -- Collect unique objectives and spawn IDs in this cluster
        local cluster_objectives = {}
        local spawn_ids = {}
        local obj_seen = {}
        
        for _, point in ipairs(cluster_points) do
            if not obj_seen[point.objective_index] then
                obj_seen[point.objective_index] = true
                cluster_objectives[#cluster_objectives + 1] = point.objective
            end
            if point.spawn_id then
                spawn_ids[point.spawn_id] = true
            end
        end
        
        -- Convert spawn_ids set to array
        local spawn_id_array = {}
        for id, _ in pairs(spawn_ids) do
            spawn_id_array[#spawn_id_array + 1] = id
        end
        
        local cluster_obj = {
            id = cid,
            center = center,
            radius = radius,
            objectives = cluster_objectives,
            spawn_ids = spawn_id_array,
            points = cluster_points,
            waypoints = {},
        }
        
        cluster_obj.waypoints = generate_cluster_waypoints(cluster_obj)
        result_clusters[#result_clusters + 1] = cluster_obj
    end
    
    -- Convert noise points to individual micro-clusters
    local noise_clusters = {}
    for _, point in ipairs(noise) do
        local cluster_obj = {
            id = #result_clusters + #noise_clusters + 1,
            center = {x = point.x, y = point.y, z = point.z},
            radius = 0,
            objectives = {point.objective},
            spawn_ids = point.spawn_id and {point.spawn_id} or {},
            points = {point},
            waypoints = {{x = point.x, y = point.y, z = point.z}},
        }
        noise_clusters[#noise_clusters + 1] = cluster_obj
    end
    
    return result_clusters, noise_clusters
end

---Sequence clusters by travel distance (nearest-neighbor TSP approx)
---@param clusters table[] Each has center
---@param start_pos table {x,y,z}
---@return table[] ordered
function ObjectivePlanner:sequence_clusters(clusters, start_pos)
    local start = start_pos or {x = 0, y = 0, z = 0}
    return sequence_clusters(clusters, start)
end

---Plan routes between clusters using NavAdapter
---@param clusters table[]
---@param nav_adapter table
---@return table[] clusters with route data
function ObjectivePlanner:plan_routes(clusters, nav_adapter)
    if not nav_adapter or not nav_adapter.plan_route then
        return clusters
    end
    
    for i = 1, #clusters - 1 do
        local from = clusters[i].center
        local to = clusters[i + 1].center
        
        -- NavAdapter expects move_to target - we'd need to call async
        -- For now, store the route request
        clusters[i].next_cluster = clusters[i + 1].id
        clusters[i].route_to_next = {
            from = from,
            to = to,
        }
    end
    
    return clusters
end

---Full planning pipeline
---@param objectives table[]
---@param start_pos table
---@param nav_adapter table|nil
---@param strategy string "cluster" | "minimize_travel" | "maximize_overlap"
---@return table plan
function ObjectivePlanner:plan(objectives, start_pos, nav_adapter, strategy)
    strategy = strategy or "cluster"
    
    -- Cluster objectives
    local clusters, noise = self:cluster_objectives(objectives)
    
    -- Merge noise into clusters
    for _, nc in ipairs(noise) do
        clusters[#clusters + 1] = nc
    end
    
    -- Sequence clusters
    local ordered = self:sequence_clusters(clusters, start_pos)
    
    -- Plan routes
    if nav_adapter then
        ordered = self:plan_routes(ordered, nav_adapter)
    end
    
    -- Apply strategy modifications
    if strategy == "minimize_travel" then
        -- Already done by nearest-neighbor
    elseif strategy == "maximize_overlap" then
        -- Re-sort by objective density (more objectives per cluster first)
        table.sort(ordered, function(a, b)
            return #a.objectives > #b.objectives
        end)
    end
    -- "cluster" = default (keep spatial grouping)
    
    return {
        clusters = ordered,
        total_clusters = #ordered,
        estimated_time = self:_estimate_time(ordered),
        strategy = strategy,
    }
end

---Estimate time to complete all clusters
---@param clusters table[]
---@return number minutes
function ObjectivePlanner:_estimate_time(clusters)
    local total = 0
    for _, c in ipairs(clusters) do
        -- Travel to cluster
        total = total + (c.radius / 100) -- ~100 yd/min walking
        -- Objective completion
        for _, obj in ipairs(c.objectives) do
            if obj.type == "KILL" then
                total = total + (obj.count * 0.5) -- 30 sec per kill
            elseif obj.type == "COLLECT" then
                total = total + (obj.count * 0.3) -- 20 sec per collect
            elseif obj.type == "ESCORT" then
                total = total + 5
            end
        end
    end
    return total / 60 -- minutes
end

---Get spawn positions for objective from Mangos DB (via QueryClient)
---@param objective table
---@param query_client table
---@return table[] positions
function ObjectivePlanner.get_spawn_positions(objective, query_client)
    if objective.type == "KILL" and objective.target_id then
        -- Would query creature table via QueryClient
        -- For now return empty - integration point
        return {}
    elseif objective.type == "COLLECT" and objective.item_id then
        -- Would query gameobject table
        return {}
    end
    return {}
end

return ObjectivePlanner