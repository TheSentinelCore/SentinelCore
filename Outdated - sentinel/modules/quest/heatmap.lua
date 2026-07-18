local Heatmap = {}
Heatmap.__index = Heatmap

local CELL_SIZE = 50 -- yards
local REBUILD_INTERVAL_MS = 30000 -- 30 seconds

---Create new heatmap
---@param blackboard table
---@return Heatmap
function Heatmap.new(blackboard)
    return setmetatable({
        _blackboard = blackboard,
        cells = {}, -- key -> {score, spawns{}, objectives{}, center_x, center_y}
        dirty = true,
        last_rebuild = 0,
    }, Heatmap)
end

---Get grid cell key for position
---@param x number
---@param y number
---@return string
function Heatmap._cell_key(x, y)
    local cx = math.floor(x / CELL_SIZE)
    local cy = math.floor(y / CELL_SIZE)
    return cx .. ":" .. cy
end

---Get cell center position
---@param key string
---@return number x, number y
function Heatmap._cell_center(key)
    local cx, cy = key:match("(-?%d+):(-?%d+)")
    cx = tonumber(cx)
    cy = tonumber(cy)
    return cx * CELL_SIZE + CELL_SIZE / 2, cy * CELL_SIZE + CELL_SIZE / 2
end

---Add a spawn to the heatmap
---@param x number
---@param y number
---@param z number
---@param weight number
---@param objective_id integer
function Heatmap:add_spawn(x, y, z, weight, objective_id)
    local key = Heatmap._cell_key(x, y)
    local cell = self.cells[key]
    
    if not cell then
        local cx, cy = Heatmap._cell_center(key)
        cell = {
            score = 0,
            spawns = {},
            objectives = {},
            center_x = cx,
            center_y = cy,
        }
        self.cells[key] = cell
    end
    
    cell.score = cell.score + weight
    cell.spawns[#cell.spawns + 1] = {x = x, y = y, z = z, weight = weight, objective_id = objective_id}
    cell.objectives[objective_id] = true
end

---Get average density in area
---@param x number
---@param y number
---@param radius number
---@return number average_score
function Heatmap:get_density(x, y, radius)
    local cells_in_radius = math.ceil(radius / CELL_SIZE)
    local cx = math.floor(x / CELL_SIZE)
    local cy = math.floor(y / CELL_SIZE)
    
    local total_score = 0
    local cell_count = 0
    
    for dx = -cells_in_radius, cells_in_radius do
        for dy = -cells_in_radius, cells_in_radius do
            local key = (cx + dx) .. ":" .. (cy + dy)
            local cell = self.cells[key]
            if cell then
                total_score = total_score + cell.score
                cell_count = cell_count + 1
            end
        end
    end
    
    if cell_count == 0 then return 0 end
    return total_score / cell_count
end

---Get top N cells by score
---@param n number
---@return table[] {center_x, center_y, score, spawns, objectives}
function Heatmap:get_top_cells(n)
    local sorted = {}
    for _, cell in pairs(self.cells) do
        sorted[#sorted + 1] = cell
    end
    
    table.sort(sorted, function(a, b) return a.score > b.score end)
    
    local result = {}
    for i = 1, math.min(n, #sorted) do
        local c = sorted[i]
        result[#result + 1] = {
            center_x = c.center_x,
            center_y = c.center_y,
            score = c.score,
            spawn_count = #c.spawns,
            objectives = c.objectives,
        }
    end
    
    return result
end

---Check if heatmap needs rebuilding
---@return boolean
function Heatmap:needs_rebuild()
    if self.dirty then return true end
    local now = self._blackboard:get("system.now_ms", 0)
    return (now - self.last_rebuild) > REBUILD_INTERVAL_MS
end

---Mark heatmap as dirty
function Heatmap:mark_dirty()
    self.dirty = true
end

---Clear heatmap
function Heatmap:clear()
    self.cells = {}
    self.dirty = true
    self.last_rebuild = 0
end

---Rebuild heatmap from active quests
---@param active_quests table[]
---@param query_client table
function Heatmap:rebuild(active_quests, query_client)
    self:clear()
    
    for _, quest in ipairs(active_quests) do
        for _, obj in ipairs(quest.objectives or {}) do
            local weight = 1.0
            
            -- Higher weight for remaining objectives
            if obj.type == "KILL" then
                weight = obj.count / math.max(1, obj.current or obj.count)
            elseif obj.type == "COLLECT" then
                weight = obj.count / math.max(1, obj.current or obj.count)
            end
            
            -- Get spawn positions from Mangos DB via QueryClient
            local spawns = {}
            if obj.target_id then
                spawns = self:_fetch_creature_spawns(obj.target_id, query_client)
            elseif obj.item_id then
                spawns = self:_fetch_gameobject_spawns(obj.item_id, query_client)
            end
            
            -- Fallback to Questie positions
            if #spawns == 0 and obj.questie_positions then
                for _, pos in ipairs(obj.questie_positions) do
                    spawns[#spawns + 1] = {x = pos.x, y = pos.y, z = pos.z, objective_id = obj.quest_id or 0}
                end
            end
            
            -- Add all spawns to heatmap
            for _, spawn in ipairs(spawns) do
                self:add_spawn(spawn.x, spawn.y, spawn.z, weight, obj.quest_id or 0)
            end
        end
    end
    
    self.dirty = false
    self.last_rebuild = self._blackboard:get("system.now_ms", 0)
end

---Fetch creature spawn positions from QueryClient
---@param creature_id integer
---@param query_client table
---@return table[]
function Heatmap:_fetch_creature_spawns(creature_id, query_client)
    if not query_client or not query_client.fetch_creature_spawns then return {} end
    
    -- Would need new QueryClient endpoint
    -- For now return empty - integration point
    return {}
end

---Fetch gameobject spawn positions
---@param gameobject_id integer
---@param query_client table
---@return table[]
function Heatmap:_fetch_gameobject_spawns(gameobject_id, query_client)
    if not query_client or not query_client.fetch_gameobject_spawns then return {} end
    return {}
end

return Heatmap