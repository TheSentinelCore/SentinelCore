local FarmService = {}
FarmService.__index = FarmService

local function safe_method(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return nil
    end
    local ok, value = pcall(obj[method], obj, ...)
    if ok then
        return value
    end
    return nil
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return math.huge
    end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@class FarmService
function FarmService:new(bb, cfg, deps, logger)
    local o = setmetatable({}, FarmService)
    o._bb = bb
    o._cfg = cfg or {}
    o._deps = deps or {}
    o._log = logger
    o._phase = "idle"
    o._last_segment_advance_at = 0
    return o
end

function FarmService:_has_live_target()
    local target = self._bb:get("combat.target")
    if not target then
        return false
    end
    return safe_method(target, "is_valid") == true and safe_method(target, "is_dead") ~= true
end

function FarmService:_acquire_target_if_needed()
    if self:_has_live_target() then
        return self._bb:get("combat.target")
    end

    if self._deps.targeting then
        return self._deps.targeting:acquire_target()
    end

    return nil
end

function FarmService:_run_route_collect_step(now)
    local route = self._deps.route
    if not route then
        return false
    end

    local point = route:get_current_pull_point()
    if type(point) == "table" then
        local player_pos = self._bb:get("player.position")
        local tolerance = route:get_reach_tolerance()
        if distance(player_pos, point) > tolerance then
            if self._deps.movement then
                self._deps.movement:move_to(point)
            end
            self._phase = "positioning"
            return true
        end
    else
        route:finish_collection(now)
        return false
    end

    local target = self:_acquire_target_if_needed()
    if target and self._deps.combat then
        local pulled = self._deps.combat:pull_target(target, now)
        if pulled then
            route:advance_pull_point(now)
        end
        return true
    end

    if route:should_skip_current_point(now) then
        route:advance_pull_point(now)
        return true
    end

    return false
end

---@param now number
function FarmService:update(now)
    local route = self._deps.route
    if route and type(route.ensure_started) == "function" then
        route:ensure_started(now)
    end

    if self._bb:get("player.is_dead", false) then
        self._phase = "dead"
        return
    end

    if self._bb:get("vendor.needs_trip", false) then
        self._phase = "vendor_pending"
        return
    end

    if self._bb:get("player.in_combat", false) then
        local collect_active = false
        if route and route:is_collecting() then
            if route:is_collect_complete(now) then
                route:finish_collection(now)
            else
                collect_active = true
                self:_run_route_collect_step(now)
            end
        end

        self._phase = collect_active and "collect" or "combat"
        if self._deps.combat then
            self._deps.combat:tick(now)
        end
        return
    end

    if route and route:is_collecting() then
        if route:is_collect_complete(now) then
            route:finish_collection(now)
        else
            self._phase = "collect"
            if self:_run_route_collect_step(now) then
                return
            end
        end
    end

    local target = self:_acquire_target_if_needed()
    if target then
        self._phase = "pull"
        if self._deps.combat then
            local pulled = self._deps.combat:pull_target(target, now)
            if pulled and route and route:is_collecting() then
                route:advance_pull_point(now)
            end
        end
        return
    end

    if route and not route:is_collecting() and (now - self._last_segment_advance_at) >= 1.0 then
        if route:next_segment(now) then
            self._last_segment_advance_at = now
            self._phase = "route_advance"
            return
        end
    end

    self._phase = "idle"
end

function FarmService:get_phase()
    return self._phase
end

return FarmService
