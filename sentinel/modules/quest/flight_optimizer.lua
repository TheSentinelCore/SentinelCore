local FlightOptimizer = {}
FlightOptimizer.__index = FlightOptimizer

---@class TaxiNode
---@field id integer
---@field name string
---@field x number
---@field y number
---@field z number
---@field map_id integer
---@field faction string "Alliance" | "Horde" | "Both"

---@class FlightPath
---@field from integer
---@field to integer
---@field cost integer copper
---@field time number seconds

---@class FlightOptimizer
---@field _taxi_nodes table<integer, TaxiNode>
---@field _taxi_paths table<integer, FlightPath[]>
---@field _continents table<integer, integer[]> map_id -> node_ids
---@field _cache table
---@field _blackboard table

---Create new FlightOptimizer
---@param blackboard table
---@return FlightOptimizer
function FlightOptimizer.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        _taxi_nodes = {},
        _taxi_paths = {},
        _continents = {
            [0] = {}, -- Eastern Kingdoms
            [1] = {}, -- Kalimdor
        },
        _cache = {},
        _cache_ttl = 300000, -- 5 minutes
    }, FlightOptimizer)
end

---Load taxi data from Mangos DB via QueryClient
---@param query_client table
function FlightOptimizer:load_taxi_data(query_client)
    if not query_client then return end
    
    -- Would need QueryClient endpoints:
    -- /api/v1/taxi/nodes?map=X&faction=Y
    -- /api/v1/taxi/paths?from=X
    -- For now, leave empty - integration point
end

---Add taxi node manually
---@param node TaxiNode
function FlightOptimizer:add_node(node)
    self._taxi_nodes[node.id] = node
    local cont = self._continents[node.map_id] or {}
    cont[#cont + 1] = node.id
    self._continents[node.map_id] = cont
end

---Add taxi path
---@param from integer
---@param to integer
---@param cost integer
---@param time number
function FlightOptimizer:add_path(from, to, cost, time)
    if not self._taxi_paths[from] then
        self._taxi_paths[from] = {}
    end
    self._taxi_paths[from][#self._taxi_paths[from] + 1] = {
        to = to,
        cost = cost or 0,
        time = time or 0,
    }
end

---Find optimal route: walk -> taxi -> walk
---@param origin table {x,y,z}
---@param destination table {x,y,z}
---@param player_faction string "Alliance" | "Horde"
---@return table route {mode, waypoints[], time_min, cost_copper}
function FlightOptimizer:find_route(origin, destination, player_faction)
    local cache_key = string.format("%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%s",
        origin.x, origin.y, origin.z,
        destination.x, destination.y, destination.z,
        player_faction)
    
    if self._cache[cache_key] then
        local cached = self._cache[cache_key]
        if cached.timestamp and (self._blackboard:get("system.now_ms", 0) - cached.timestamp < self._cache_ttl) then
            return cached.route
        end
    end
    
    local routes = {}
    
    -- 1. Direct walk
    local walk_dist = self:_distance(origin, destination)
    local walk_time = walk_dist / 100 -- ~100 yd/min
    routes[#routes + 1] = {
        mode = "walk",
        waypoints = {origin, destination},
        distance = walk_dist,
        time_min = walk_time,
        cost = 0,
    }
    
    -- 2. Taxi routes (if flying available)
    if self:_can_fly(player_faction) then
        local taxi_routes = self:_find_taxi_routes(origin, destination, player_faction)
        for _, r in ipairs(taxi_routes) do
            routes[#routes + 1] = r
        end
    end
    
    -- 3. Hearthstone
    local hearth_route = self:_hearthstone_route(origin, destination)
    if hearth_route then
        routes[#routes + 1] = hearth_route
    end
    
    -- Sort by time
    table.sort(routes, function(a, b) return a.time_min < b.time_min end)
    
    local best = routes[1]
    if best then
        self._cache[cache_key] = {route = best, timestamp = self._blackboard:get("system.now_ms", 0)}
    end
    
    return best or routes[1]
end

---Find taxi routes from origin to destination
---@return table[]
function FlightOptimizer:_find_taxi_routes(origin, destination, faction)
    local routes = {}
    
    -- Find nearest taxi nodes to origin and destination
    local origin_nodes = self:_nearest_taxi_nodes(origin, faction, 3)
    local dest_nodes = self:_nearest_taxi_nodes(destination, faction, 3)
    
    for _, onode in ipairs(origin_nodes) do
        for _, dnode in ipairs(dest_nodes) do
            -- Check if path exists
            local path = self:_find_taxi_path(onode.id, dnode.id)
            if path then
                local walk1 = self:_distance(origin, onode)
                local walk2 = self:_distance(dnode, destination)
                local taxi_time = self:_sum_taxi_time(path)
                local taxi_cost = self:_sum_taxi_cost(path)
                
                routes[#routes + 1] = {
                    mode = "taxi",
                    waypoints = {origin, onode, dnode, destination},
                    walk_distance = walk1 + walk2,
                    taxi_time = taxi_time,
                    time_min = (walk1 + walk2) / 100 + taxi_time,
                    cost = taxi_cost,
                    path = path,
                }
            end
        end
    end
    
    return routes
end

---Find path between two taxi nodes (Dijkstra)
---@return table[]|nil
function FlightOptimizer:_find_taxi_path(from, to)
    -- Simple BFS since taxi graph is small
    local queue = {{node = from, path = {from}, cost = 0, time = 0}}
    local visited = {[from] = true}
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        if current.node == to then
            return current.path
        end
        
        local paths = self._taxi_paths[current.node]
        if paths then
            for _, p in ipairs(paths) do
                if not visited[p.to] then
                    visited[p.to] = true
                    local new_path = {table.unpack(current.path)}
                    new_path[#new_path + 1] = p.to
                    queue[#queue + 1] = {
                        node = p.to,
                        path = new_path,
                        cost = current.cost + p.cost,
                        time = current.time + p.time,
                    }
                end
            end
        end
    end
    return nil
end

---Get nearest taxi nodes to position
---@return TaxiNode[]
function FlightOptimizer:_nearest_taxi_nodes(pos, faction, limit)
    local nodes = {}
    for _, node_id in ipairs(self._continents[self:_get_continent(pos)] or {}) do
        local node = self._taxi_nodes[node_id]
        if node and self:_faction_matches(node, faction) then
            local dist = self:_distance(pos, node)
            nodes[#nodes + 1] = {node = node, dist = dist}
        end
    end
    
    table.sort(nodes, function(a, b) return a.dist < b.dist end)
    
    local result = {}
    for i = 1, math.min(limit or 3, #nodes) do
        result[i] = nodes[i].node
    end
    return result
end

---Check if player can use flight paths
function FlightOptimizer:_can_fly(faction)
    -- Would check level, flight license, etc.
    return true
end

---Hearthstone route
---@return table|nil
function FlightOptimizer:_hearthstone_route(origin, destination)
    local bind_pos = self._blackboard:get("player.hearthstone_position")
    if not bind_pos then return nil end
    
    local to_bind = self:_distance(origin, bind_pos)
    local from_bind = self:_distance(bind_pos, destination)
    local total_walk = to_bind + from_bind
    local walk_time = total_walk / 100
    
    -- Hearth if significant time savings
    if walk_time > 10 then -- 10+ min walk
        return {
            mode = "hearth",
            waypoints = {origin, bind_pos, destination},
            time_min = 0.5 + from_bind / 100, -- 30s hearth + walk from bind
            cost = 0,
        }
    end
    return nil
end

---Distance helper
function FlightOptimizer:_distance(a, b)
    if not a or not b then return math.huge end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

---Sum taxi time
function FlightOptimizer:_sum_taxi_time(path)
    local total = 0
    for i = 1, #path - 1 do
        local paths = self._taxi_paths[path[i]]
        if paths then
            for _, p in ipairs(paths) do
                if p.to == path[i + 1] then
                    total = total + p.time
                    break
                end
            end
        end
    end
    return total
end

---Sum taxi cost
function FlightOptimizer:_sum_taxi_cost(path)
    local total = 0
    for i = 1, #path - 1 do
        local paths = self._taxi_paths[path[i]]
        if paths then
            for _, p in ipairs(paths) do
                if p.to == path[i + 1] then
                    total = total + p.cost
                    break
                end
            end
        end
    end
    return total
end

---Get continent from position
function FlightOptimizer:_get_continent(pos)
    if not pos then return 0 end
    -- Simple heuristic: Kalimdor (map 1) has negative Y typically
    return (pos.y and pos.y < 0) and 1 or 0
end

---Check faction match
function FlightOptimizer:_faction_matches(node, faction)
    return node.faction == "Both" or node.faction == faction
end

return FlightOptimizer