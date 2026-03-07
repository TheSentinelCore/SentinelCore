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

function ChaseController:new(event_bus, blackboard, nav_adapter)
    local o = setmetatable({}, ChaseController)
    o._event_bus = event_bus
    o._blackboard = blackboard
    o._nav_adapter = nav_adapter
    o._last_target_position = nil
    o._melee_range = 4.5
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

    if dist <= self._melee_range then
        if owner == "combat" then
            self._nav_adapter:stop("combat_in_range")
            self._blackboard:set("nav.owner", nil)
        end
        return false
    end

    local should_move = true
    if self._last_target_position then
        should_move = distance(self._last_target_position, target_pos) > 2.0 or not self._nav_adapter:is_active()
    end

    if should_move then
        self._blackboard:set("nav.owner", "combat")
        self._blackboard:set("nav.command", "move_to")
        self._blackboard:set("nav.destination", target_pos)
        self._nav_adapter:move_to(target_pos, { use_navmesh = true })
        self._last_target_position = target_pos
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
end

return ChaseController
