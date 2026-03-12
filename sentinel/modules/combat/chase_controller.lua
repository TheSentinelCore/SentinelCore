local ChaseController = {}
ChaseController.__index = ChaseController

local function num(value)
    return tonumber(value) or 0
end

local function distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

local CHASE_RESUME_BUFFER = 3

function ChaseController:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, ChaseController)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._last_target_position = nil
    o._last_move_ms = 0
    o._in_range = false
    return o
end

function ChaseController:update(target)
    local owner = self._blackboard:get("nav.owner")
    if owner and owner ~= "combat" then
        return false
    end

    local player_pos = self._blackboard:get("player.position")
    local ok_target_pos, target_pos = safe_call(target, "get_position")
    if type(player_pos) ~= "table" or not ok_target_pos or type(target_pos) ~= "table" then
        return false
    end

    local dist = distance(player_pos, target_pos)
    self._blackboard:set("combat.target_distance", dist)

    -- Always face the target
    if core and core.input and core.input.look_at then
        pcall(core.input.look_at, target_pos)
    end

    local combat_range = tonumber(self._blackboard:get("module.combat.combat_range")) or 4.5
    if dist <= combat_range then
        self._in_range = true
        -- Stop any active navigation — including stale grind phase nav
        -- that wasn't started by the chase controller (nav.owner unset).
        if self._nav_adapter:is_active() then
            self._nav_adapter:stop("combat_in_range")
        end
        self._blackboard:set("nav.owner", nil)
        return false
    end

    -- Hysteresis: don't resume chasing until target moves well beyond combat range
    if self._in_range and dist <= combat_range + CHASE_RESUME_BUFFER then
        return false
    end
    self._in_range = false

    local now_ms = num(self._blackboard:get("system.now_ms", 0))

    local should_move = true
    if self._last_target_position then
        local target_moved = distance(self._last_target_position, target_pos) > 2.0
        local nav_idle = not self._nav_adapter:is_active()
        should_move = target_moved or nav_idle
    end

    -- Debounce: don't re-request move_to() more than once per 500ms
    if should_move and (now_ms - self._last_move_ms) < 500 and self._nav_adapter:is_active() then
        should_move = false
    end

    if should_move then
        self._blackboard:set("nav.owner", "combat")
        self._blackboard:set("nav.command", "move_to")
        self._blackboard:set("nav.destination", target_pos)
        self._nav_adapter:move_to(target_pos, { use_navmesh = true })
        self._last_target_position = target_pos
        self._last_move_ms = now_ms
        return true
    end

    return false
end

function ChaseController:stop(reason)
    if self._blackboard:get("nav.owner") == "combat" then
        self._nav_adapter:stop(reason or "combat_stop")
        self._blackboard:set("nav.owner", nil)
    end
    self._last_target_position = nil
    self._in_range = false
end

return ChaseController
