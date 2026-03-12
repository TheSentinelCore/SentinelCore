local KiteController = {}
KiteController.__index = KiteController

-- Kite states
local STATE_NONE = "NONE"
local STATE_NOVA_PENDING = "NOVA_PENDING"
local STATE_RUNNING_AWAY = "RUNNING_AWAY"
local STATE_CASTING_FROM_RANGE = "CASTING_FROM_RANGE"

local SAFE_DISTANCE = 25
local RE_ENGAGE_DISTANCE = 8

local function num(value)
    return tonumber(value) or 0
end

local function safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

function KiteController:new(blackboard)
    local o = setmetatable({}, KiteController)
    o._bb = blackboard
    o._running = false
    return o
end

function KiteController:get_state()
    return self._bb:get("combat.kite_state", STATE_NONE)
end

function KiteController:set_state(state)
    self._bb:set("combat.kite_state", state)
end

function KiteController:start()
    self:set_state(STATE_NOVA_PENDING)
end

function KiteController:update(bb)
    local state = self:get_state()
    if state == STATE_NONE then
        self:_ensure_stopped()
        return
    end

    local target = bb:get("combat.target") or bb:get("player.target")
    local player = bb:get("player.object")
    if not target or not player then
        self:stop()
        return
    end

    -- Keep combat.target_distance updated while chase controller is gated off
    self:_update_target_distance(bb, player, target)

    if state == STATE_NOVA_PENDING then
        self:_tick_nova_pending(bb, player, target)
    elseif state == STATE_RUNNING_AWAY then
        self:_tick_running_away(bb, player, target)
    elseif state == STATE_CASTING_FROM_RANGE then
        self:_tick_casting_from_range(bb, player, target)
    end
end

-- ---------------------------------------------------------------------------
-- NOVA_PENDING: wait for target to actually be frozen, then start running
-- ---------------------------------------------------------------------------
function KiteController:_tick_nova_pending(bb, player, target)
    local frozen = bb:get("combat.target_frozen", false)
    if frozen then
        self:set_state(STATE_RUNNING_AWAY)
        self:_start_running(player, target)
        return
    end

    -- Timeout: if nova didn't land after 1 second, bail
    local now = num(bb:get("system.now_ms", 0))
    local start = num(bb:get("combat._kite_start_ms", 0))
    if start == 0 then
        bb:set("combat._kite_start_ms", now)
    elseif now - start > 1000 then
        self:stop()
    end
end

-- ---------------------------------------------------------------------------
-- RUNNING_AWAY: sprint away from target, fire instants while running
-- ---------------------------------------------------------------------------
function KiteController:_tick_running_away(bb, player, target)
    local d = num(bb:get("combat.target_distance", 0))

    -- Reached safe distance: stop and face target
    if d >= SAFE_DISTANCE then
        self:_stop_running()
        self:_face_target(player, target)
        self:set_state(STATE_CASTING_FROM_RANGE)
        return
    end

    -- Keep running: refresh escape direction in case target moved
    self:_start_running(player, target)
end

-- ---------------------------------------------------------------------------
-- CASTING_FROM_RANGE: stand and cast, re-enter kite if target closes
-- ---------------------------------------------------------------------------
function KiteController:_tick_casting_from_range(bb, player, target)
    local d = num(bb:get("combat.target_distance", 0))

    -- Target closed the gap: cycle back to NONE so GCD tree can nova again
    if d <= RE_ENGAGE_DISTANCE then
        self:set_state(STATE_NONE)
        return
    end

    -- Ensure facing target for casting
    self:_face_target(player, target)
end

-- ---------------------------------------------------------------------------
-- Distance tracking (chase controller is gated off during kite)
-- ---------------------------------------------------------------------------
function KiteController:_update_target_distance(bb, player, target)
    local ok_p, p_pos = safe_call(player, "get_position")
    local ok_t, t_pos = safe_call(target, "get_position")
    if ok_p and ok_t and type(p_pos) == "table" and type(t_pos) == "table" then
        local dx = num(p_pos.x) - num(t_pos.x)
        local dy = num(p_pos.y) - num(t_pos.y)
        local dz = num(p_pos.z) - num(t_pos.z)
        bb:set("combat.target_distance", math.sqrt(dx * dx + dy * dy + dz * dz))
    end
end

-- ---------------------------------------------------------------------------
-- Movement helpers
-- ---------------------------------------------------------------------------
function KiteController:_start_running(player, target)
    local ok_ppos, player_pos = safe_call(player, "get_position")
    local ok_tpos, target_pos = safe_call(target, "get_position")
    if not ok_ppos or not ok_tpos or type(player_pos) ~= "table" or type(target_pos) ~= "table" then
        return
    end

    -- Calculate escape point: direction away from target on XY plane, 30 yards out
    -- Flatten to 2D to avoid running into terrain/underground on slopes
    local dx = num(player_pos.x) - num(target_pos.x)
    local dy = num(player_pos.y) - num(target_pos.y)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then
        dx, dy, len = 1, 0, 1
    end

    local escape_point = {
        x = num(player_pos.x) + (dx / len) * 30,
        y = num(player_pos.y) + (dy / len) * 30,
        z = num(player_pos.z),
    }

    -- Face away from target and run forward
    if core and core.input then
        pcall(core.input.look_at, escape_point)
        if not self._running then
            pcall(core.input.move_forward_start)
            self._running = true
        end
    end
end

function KiteController:_stop_running()
    if self._running and core and core.input then
        pcall(core.input.move_forward_stop)
        self._running = false
    end
end

function KiteController:_face_target(player, target)
    local ok_tpos, target_pos = safe_call(target, "get_position")
    if ok_tpos and type(target_pos) == "table" and core and core.input then
        pcall(core.input.look_at, target_pos)
    end
end

function KiteController:_ensure_stopped()
    self:_stop_running()
end

function KiteController:stop()
    self:_stop_running()
    self:set_state(STATE_NONE)
    self._bb:set("combat._kite_start_ms", nil)
end

function KiteController:reset()
    self:stop()
end

return KiteController
