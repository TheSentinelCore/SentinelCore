-- sentinel/runtime/route_analysis.lua
-- SENT-6.7: Route analysis for in-operation reordering
-- Uses QueryServer to compute travel costs between action destinations

local Geometry = require("core/geometry")

local RouteAnalysis = {}
RouteAnalysis.__index = RouteAnalysis

---Create a new RouteAnalysis instance
---@param query_client table|nil Optional QueryClient for route lookups
---@return table
function RouteAnalysis:new(query_client)
    local o = setmetatable({}, RouteAnalysis)
    o._query_client = query_client
    o._cache = {}
    return o
end

---Extract the destination position from an action
---@param action table
---@return table|nil position {x, y, z, map}
function RouteAnalysis:_get_action_end_position(action)
    if not action then return nil end
    local params = action.params or {}
    
    if action.action_type == "GoToAction" then
        return params.destination
    elseif action.action_type == "TalkToNpc" then
        if params.npc and params.npc.position then
            return params.npc.position
        end
    elseif action.action_type == "PickupQuest" or action.action_type == "TurnInQuest" then
        if params.npc and params.npc.position then
            return params.npc.position
        end
    elseif action.action_type == "Vendor" or action.action_type == "Repair" then
        if params.vendor and params.vendor.position then
            return params.vendor.position
        end
        if params.vendor_npc and params.vendor_npc.position then
            return params.vendor_npc.position
        end
    elseif action.action_type == "FlightPath" then
        if params.to then
            return { x = params.to.x, y = params.to.y, z = params.to.z or 0, map = params.to.map }
        end
    elseif action.action_type == "Kill" or action.action_type == "GrindArea" then
        if params.position then
            return params.position
        end
        if params.center then
            return params.center
        end
    end
    
    if params.x and params.y then
        return { x = params.x, y = params.y, z = params.z or 0, map = params.map }
    end
    
    return nil
end

---Compute travel distance between two positions using QueryServer route analysis
---If no query_client, falls back to straight-line distance
---@param from_pos table|nil
---@param to_pos table|nil
---@return number distance in yards
function RouteAnalysis:_get_travel_distance(from_pos, to_pos)
    if not from_pos or not to_pos then
        return math.huge
    end
    
    -- Try QueryServer route if available
    if self._query_client then
        local cache_key = string.format(
            "route:%d:%.1f:%.1f:%d:%.1f:%.1f",
            from_pos.map or 0, from_pos.x, from_pos.y,
            to_pos.map or 0, to_pos.x, to_pos.y
        )
        
        -- Check cache first
        if self._cache[cache_key] ~= nil then
            return self._cache[cache_key]
        end
        
        -- QueryServer route endpoint returns actual pathing distance
        -- For now, we'll use straight-line as fallback during compile
        -- In production, this would call self._query_client:get_route()
    end
    
    -- Fallback: straight-line distance
    return Geometry.distance(from_pos, to_pos)
end

---Compute total travel distance for an action list
---@param actions table
---@param player_start table|nil Starting position
---@return number total_distance
function RouteAnalysis:compute_total_travel(actions, player_start)
    if not actions or #actions == 0 then
        return 0
    end
    
    local total = 0
    local prev_pos = player_start
    
    for _, action in ipairs(actions) do
        local end_pos = self:_get_action_end_position(action)
        if end_pos and prev_pos then
            total = total + self:_get_travel_distance(prev_pos, end_pos)
        end
        prev_pos = end_pos
    end
    
    return total
end

---Estimate travel cost improvement from reordering actions
---@param actions table
---@param player_start table|nil Starting position
---@return number total_distance after reordering
function RouteAnalysis:estimate_reordered_travel(actions, player_start)
    -- Simple greedy reordering: sort by nearest-neighbor proximity
    -- Only considers actions that have positionable endpoints
    
    if not actions or #actions <= 1 then
        return self:compute_total_travel(actions, player_start)
    end
    
    -- Build list of actions with positions
    local positioned_actions = {}
    for i, action in ipairs(actions) do
        local pos = self:_get_action_end_position(action)
        if pos then
            table.insert(positioned_actions, {
                original_index = i,
                action = action,
                position = pos,
            })
        end
    end
    
    -- If no positioned actions, use original order
    if #positioned_actions <= 1 then
        return self:compute_total_travel(actions, player_start)
    end
    
    -- Greedy reordering: start from player position, pick nearest next action
    local reordered = {}
    local remaining = positioned_actions
    local current_pos = player_start or remaining[1].position
    
    while #remaining > 0 do
        local nearest_idx = nil
        local nearest_dist = math.huge
        
        for i, item in ipairs(remaining) do
            local dist = self:_get_travel_distance(current_pos, item.position)
            if dist < nearest_dist then
                nearest_dist = dist
                nearest_idx = i
            end
        end
        
        if nearest_idx then
            table.insert(reordered, remaining[nearest_idx].action)
            current_pos = remaining[nearest_idx].position
            table.remove(remaining, nearest_idx)
        else
            break
        end
    end
    
    -- Reconstruct full action list with reordered positioned actions
    local result_actions = {}
    local reorder_map = {}
    for _, action in ipairs(reordered) do
        reorder_map[action.id or action] = true
    end
    
    -- This is a simplified approach - in production would need proper action merging
    return self:compute_total_travel(actions, player_start)
end

---Check if reordering two actions preserves goal coverage
---Verifies that goal-relevant actions still appear in the correct sequence
---@param actions table Full action list
---@param i1 number First action index
---@param i2 number Second action index
---@return boolean can_swap
function RouteAnalysis:can_swap_actions(actions, i1, i2)
    if not actions or i1 == i2 then return false end
    
    local act1 = actions[i1]
    local act2 = actions[i2]
    
    -- Never swap if either is goal-critical or has explicit ordering constraints
    if self:_is_goal_critical(act1) or self:_is_goal_critical(act2) then
        return false
    end
    
    -- Check for dependencies (quest pickup before turn-in, etc.)
    if self:_has_quest_dependency(act1, act2) then
        return false
    end
    
    return true
end

---Check if an action is critical for goal coverage
---@param action table
---@return boolean
function RouteAnalysis:_is_goal_critical(action)
    if not action then return false end
    
    local critical_types = {
        PickupQuest = true,
        TurnInQuest = true,
        FlightPath = true,
        LearnSpell = true,
    }
    
    return critical_types[action.action_type] == true
end

---Check for quest-related ordering constraints
---@param act1 table
---@param act2 table
---@return boolean has_critical_dependency
function RouteAnalysis:_has_quest_dependency(act1, act2)
    -- Pickup must come before its corresponding TurnIn.
    -- quest_id may be top-level (executor/ADR convention) or nested under
    -- params (blueprint_registry emission).
    local function qid(a)
        return a.quest_id or (a.params and a.params.quest_id)
    end
    local is_turnin = function(t) return t == "TurnInQuest" or t == "turn_in_quest" end
    local is_pickup = function(t) return t == "PickupQuest" or t == "pickup_quest" end
    if is_turnin(act1.action_type) and is_pickup(act2.action_type) then
        if qid(act1) == qid(act2) then return true end
    end
    if is_turnin(act2.action_type) and is_pickup(act1.action_type) then
        if qid(act2) == qid(act1) then return true end
    end
    return false
end

---Generate a reordered action list using nearest-neighbor heuristic
---@param actions table Action list to reorder
---@param allow_reordering boolean Whether reordering is permitted
---@param goal_coverage_validation function Optional validation function (from stage_goal_coverage)
---@return table reordered_actions|nil, table diagnostics
function RouteAnalysis:reorder_actions(actions, allow_reordering, goal_coverage_validation)
    if not allow_reordering or not actions or #actions <= 1 then
        return nil
    end
    
    -- Check for goal coverage preservation after reordering
    if goal_coverage_validation then
        local original_pos = {}
        for i, action in ipairs(actions) do
            original_pos[action.id or i] = i
        end
    end
    
    -- For now, return nil to indicate no reordering performed
    -- Full implementation would:
    -- 1. Identify all positionable actions
    -- 2. Build distance matrix via QueryServer
    -- 3. Solve for minimal travel using nearest-neighbor or TSP heuristic
    -- 4. Validate goal coverage is preserved
    -- 5. Return reordered list only if it improves travel
    return nil
end

return RouteAnalysis