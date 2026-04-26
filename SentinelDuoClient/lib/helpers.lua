-- helpers.lua — Shared utility functions for SentinelDuoClient
-- All modules should require this and use these helpers.

local M = {}

--- Apply timing jitter to a base value.
--- Returns base_ms ± (pct * base_ms) randomly.
---@param base_ms number
---@param pct number|nil default 0.15 (15%)
---@return number
function M.jitter(base_ms, pct)
    pct = pct or 0.15
    local variance = base_ms * pct
    return base_ms + math.random() * variance * 2 - variance
end

--- Log an info message with the [DuoFarm] prefix.
---@param msg string
function M.log(msg)
    pcall(core.log, "[DuoFarm] " .. tostring(msg))
end

--- Log a warning message.
---@param msg string
function M.log_warn(msg)
    pcall(core.log, "[DuoFarm] WARN: " .. tostring(msg))
end

--- Log an error message.
---@param msg string
function M.log_err(msg)
    pcall(core.log_error, "[DuoFarm] ERROR: " .. tostring(msg))
end

--- Compute the 3D distance between two vec3 tables.
---@param a table {x,y,z}
---@param b table {x,y,z}
---@return number
function M.dist3d(a, b)
    if not a or not b then return 999999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Compute the 2D (XY) distance between two vec3 tables.
---@param a table {x,y,z}
---@param b table {x,y,z}
---@return number
function M.dist2d(a, b)
    if not a or not b then return 999999 end
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

--- Apply a random lateral (XY) displacement to a position.
---@param pos table {x,y,z}
---@param max_yards number
---@return table new position with jittered x/y
function M.apply_lateral_jitter(pos, max_yards)
    local angle = math.random() * math.pi * 2
    local dist  = math.random() * max_yards
    return {
        x = pos.x + math.cos(angle) * dist,
        y = pos.y + math.sin(angle) * dist,
        z = pos.z,
    }
end

--- Safely get local player (nil if not available).
---@return any|nil
function M.get_player()
    local ok, player = pcall(function()
        return core.object_manager.get_local_player()
    end)
    if ok then return player end
    return nil
end

--- Get game time in milliseconds (server-synced).
---@return number
function M.game_time_ms()
    local ok, t = pcall(core.game_time)
    if ok and type(t) == "number" then return t end
    return 0
end

return M
