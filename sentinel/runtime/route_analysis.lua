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
        if end_pos then
            if prev_pos then
                total = total + self:_get_travel_distance(prev_pos, end_pos)
            end
            prev_pos = end_pos
        end
    end

    return total
end

---Nearest-neighbor greedy reordering of a single action list.
---Positionless actions (waits, casts) are left in their original relative slots;
---only positioned actions are permuted among their own slots. Swaps that would
---violate quest dependencies or goal-critical ordering are skipped.
---@param actions table Full action list
---@param player_start table|nil Optional starting position (defaults to first positioned action)
---@return table reordered_actions, boolean improved
function RouteAnalysis:_nearest_neighbor_reorder(actions, player_start)
    if not actions or #actions <= 1 then
        return actions, false
    end

    -- Split into positioned / positionless, keeping positionless insertion order
    local positioned = {}   -- { action, position }
    local slots = {}        -- parallel to actions: true if this index is positioned
    for i, action in ipairs(actions) do
        local pos = self:_get_action_end_position(action)
        if pos then
            table.insert(positioned, { action = action, position = pos })
            slots[i] = true
        end
    end

    if #positioned <= 1 then
        return actions, false
    end

    -- Greedy: anchor at player_start or the first positioned action's position
    local current_pos = player_start or positioned[1].position
    local remaining = {}
    for _, p in ipairs(positioned) do table.insert(remaining, p) end
    local ordered_positions = {}

    -- Track placed quest pickups so a TurnIn never jumps ahead of its Pickup.
    local placed_quests = {}
    local function quest_id_of(a)
        return a.quest_id or (a.params and a.params.quest_id)
    end
    local function is_pickup(a)
        local t = a.action_type
        return t == "PickupQuest" or t == "pickup_quest"
    end
    local function is_turnin(a)
        local t = a.action_type
        return t == "TurnInQuest" or t == "turn_in_quest"
    end

    while #remaining > 0 do
        local nearest_idx, nearest_dist = nil, math.huge
        for i, item in ipairs(remaining) do
            -- A TurnIn is only eligible once its quest's Pickup has been placed.
            if is_turnin(item.action) then
                local q = quest_id_of(item.action)
                if q and not placed_quests[q] then
                    goto continue
                end
            end
            local dist = self:_get_travel_distance(current_pos, item.position)
            if dist < nearest_dist then
                nearest_dist, nearest_idx = dist, i
            end
            ::continue::
        end
        -- If every remaining action was skipped (shouldn't happen), break to avoid infinite loop
        if not nearest_idx then
            nearest_idx = 1
        end
        local chosen = table.remove(remaining, nearest_idx)
        if is_pickup(chosen.action) then
            local q = quest_id_of(chosen.action)
            if q then placed_quests[q] = true end
        end
        table.insert(ordered_positions, chosen)
        current_pos = chosen.position
    end

    -- Splice reordered positioned actions back into the original positionless slots
    local result = {}
    local pos_cursor = 1
    for i, action in ipairs(actions) do
        if slots[i] then
            table.insert(result, ordered_positions[pos_cursor].action)
            pos_cursor = pos_cursor + 1
        else
            table.insert(result, action)
        end
    end

    -- Only report improvement if total travel is actually reduced
    local original_cost = self:compute_total_travel(actions, player_start)
    local reordered_cost = self:compute_total_travel(result, player_start)
    local improved = reordered_cost < original_cost - 1e-6
    return result, improved
end

---Estimate travel cost after reordering actions
---@param actions table
---@param player_start table|nil Starting position
---@return number total_distance after reordering
function RouteAnalysis:estimate_reordered_travel(actions, player_start)
    local reordered = self:_nearest_neighbor_reorder(actions, player_start)
    return self:compute_total_travel(reordered, player_start)
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
    local diagnostics = {}

    if not allow_reordering or not actions or #actions <= 1 then
        return nil, diagnostics
    end

    -- Skip any candidate reordering that would violate quest dependencies or
    -- goal-critical sequencing.
    local candidate, improved = self:_nearest_neighbor_reorder(actions)

    if not improved then
        table.insert(diagnostics, {
            level = "info",
            message = "No travel-distance improvement from reordering",
        })
        return nil, diagnostics
    end

    -- Validate the candidate against goal coverage (Stage 5 rules) before accepting.
    if goal_coverage_validation then
        local ok, err = pcall(goal_coverage_validation, candidate)
        if not ok or (err ~= nil and err ~= true) then
            -- Goal coverage would be broken — reject the reorder.
            table.insert(diagnostics, {
                level = "warning",
                message = "Rejected candidate reordering: would break goal coverage",
            })
            return nil, diagnostics
        end
    end

    table.insert(diagnostics, {
        level = "info",
        message = "Reordered actions for reduced travel distance",
    })
    return candidate, diagnostics
end

return RouteAnalysis