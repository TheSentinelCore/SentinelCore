---@module BGBOT.core.intent.pathing
-- Path-aware anchor helpers for intent target selection.

local utils = require("shared/utils")

local pathing = {}

local abs = math.abs

local PATH_QUERY_METHODS = {
    "get_path_length",
    "get_path_distance",
    "get_estimated_path_length",
}

local BG_VERTICAL_WEIGHT = {
    ab = 3.0,
    eots = 3.2,
    av = 1.8,
}

local DEFAULT_VERTICAL_WEIGHT = 2.2
local CLIFF_DZ_THRESHOLD = 18
local CLIFF_D2_THRESHOLD = 45
local CLIFF_PENALTY = 90

local function is_valid_pos(pos)
    return pos and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil
end

local function copy_pos(pos)
    if not is_valid_pos(pos) then
        return nil
    end
    return { x = pos.x, y = pos.y, z = pos.z }
end

local function get_nav_client()
    local root = _G.SentinelNavClient
    if not root then
        return nil
    end
    return root.client
end

local function try_path_length(from_pos, to_pos)
    local nav_client = get_nav_client()
    if not nav_client then
        return nil
    end

    for _, method_name in ipairs(PATH_QUERY_METHODS) do
        local fn = nav_client[method_name]
        if type(fn) == "function" then
            local ok, value = pcall(function()
                return fn(nav_client, from_pos, to_pos)
            end)
            if ok and type(value) == "number" and value > 0 then
                return value
            end
        end
    end

    return nil
end

local function heuristic_cost(from_pos, to_pos, bg_type)
    local d2 = utils.distance_2d(from_pos, to_pos)
    local dz = abs((from_pos.z or 0) - (to_pos.z or 0))
    local vertical_weight = BG_VERTICAL_WEIGHT[bg_type] or DEFAULT_VERTICAL_WEIGHT
    local cost = d2 + (dz * vertical_weight)

    if dz >= CLIFF_DZ_THRESHOLD and d2 <= CLIFF_D2_THRESHOLD then
        cost = cost + CLIFF_PENALTY
    end

    return cost
end

---@param from_pos table {x,y,z}
---@param to_pos table {x,y,z}
---@param opts table|nil { bg_type?: string }
---@return number cost
---@return string source "nav"|"heuristic"
function pathing.estimate_cost(from_pos, to_pos, opts)
    local bg_type = opts and opts.bg_type or "unknown"
    local nav_cost = try_path_length(from_pos, to_pos)
    if nav_cost then
        return nav_cost, "nav"
    end
    return heuristic_cost(from_pos, to_pos, bg_type), "heuristic"
end

---@param from_pos table {x,y,z}
---@param anchors table[] array of {x,y,z}
---@param opts table|nil { bg_type?: string, max_linear_distance?: number }
---@return table|nil best_pos
---@return number|nil best_cost
---@return string|nil source
function pathing.select_best_anchor(from_pos, anchors, opts)
    if not is_valid_pos(from_pos) or not anchors then
        return nil, nil, nil
    end

    local max_linear = opts and opts.max_linear_distance or nil
    local best_pos = nil
    local best_cost = nil
    local best_source = nil

    for _, pos in ipairs(anchors) do
        if is_valid_pos(pos) then
            local direct = utils.distance_3d(from_pos, pos)
            if not max_linear or direct <= max_linear then
                local cost, source = pathing.estimate_cost(from_pos, pos, opts)
                if best_cost == nil or cost < best_cost then
                    best_cost = cost
                    best_pos = pos
                    best_source = source
                end
            end
        end
    end

    return copy_pos(best_pos), best_cost, best_source
end

---@param from_pos table {x,y,z}
---@param anchors table[] array of {x,y,z}
---@param opts table|nil { bg_type?: string, max_linear_distance?: number }
---@return number|nil index
function pathing.find_best_index(from_pos, anchors, opts)
    if not is_valid_pos(from_pos) or not anchors then
        return nil
    end

    local max_linear = opts and opts.max_linear_distance or nil
    local best_index = nil
    local best_cost = nil

    for i, pos in ipairs(anchors) do
        if is_valid_pos(pos) then
            local direct = utils.distance_3d(from_pos, pos)
            if not max_linear or direct <= max_linear then
                local cost = select(1, pathing.estimate_cost(from_pos, pos, opts))
                if best_cost == nil or cost < best_cost then
                    best_cost = cost
                    best_index = i
                end
            end
        end
    end

    return best_index
end

pathing.is_valid_pos = is_valid_pos
pathing.copy_pos = copy_pos

return pathing
