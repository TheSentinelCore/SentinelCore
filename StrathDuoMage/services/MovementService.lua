local MovementService = {}
MovementService.__index = MovementService

---@class MovementService
function MovementService:new(cfg, logger)
    local o = setmetatable({}, MovementService)
    o._cfg = cfg or {}
    o._log = logger
    return o
end

function MovementService:_nav_client()
    if _G.SentinelNavClient and _G.SentinelNavClient.client then
        return _G.SentinelNavClient.client
    end
    return nil
end

---@param pos table
---@return boolean
function MovementService:move_to(pos)
    local nav = self:_nav_client()
    if nav and type(nav.move_to) == "function" and type(pos) == "table" then
        local ok = pcall(nav.move_to, nav, pos)
        return ok == true
    end
    return false
end

function MovementService:stop()
    local nav = self:_nav_client()
    if nav and type(nav.stop) == "function" then
        pcall(nav.stop, nav)
    end
end

---@return boolean|nil
function MovementService:is_moving()
    local nav = self:_nav_client()
    if nav and type(nav.is_moving) == "function" then
        local ok, moving = pcall(nav.is_moving, nav)
        if ok then
            return moving == true
        end
    end
    return nil
end

return MovementService
