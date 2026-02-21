---@module BGBOT.core.action_arbiter
-- Resolve intent output + combat command into a single executable frame command.

local action_arbiter = {}
action_arbiter.__index = action_arbiter

local constants = require("shared/constants")

local MAX_OVERRIDE_DISTANCE = math.max(
    tonumber(constants.COMBAT.INTERCEPT_CHASE_RANGE) or 50,
    tonumber(constants.COMBAT.DEFAULT_CHASE_RANGE) or 30
)

local function is_finite_number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function to_vec3(input)
    if type(input) ~= "table" then
        return nil
    end

    local x = tonumber(input.x)
    local y = tonumber(input.y)
    local z = tonumber(input.z)
    if not is_finite_number(x) or not is_finite_number(y) or not is_finite_number(z) then
        return nil
    end

    return { x = x, y = y, z = z }
end

local function distance_2d(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function sanitize_movement_override(override, world_model)
    local move_goal = to_vec3(override)
    if not move_goal then
        return nil
    end

    local self_state = world_model and world_model:get_self() or nil
    local self_pos = to_vec3(self_state and self_state.position or nil)
    if not self_pos then
        return move_goal
    end

    if distance_2d(self_pos, move_goal) > MAX_OVERRIDE_DISTANCE then
        return nil
    end

    return move_goal
end

local function safe_copy(output)
    if type(output) ~= "table" then
        return {
            nav_goal = nil,
            interact_target = nil,
            face_target = nil,
        }
    end

    return {
        nav_goal = output.nav_goal,
        interact_target = output.interact_target,
        face_target = output.face_target,
    }
end

function action_arbiter.new()
    return setmetatable({}, action_arbiter)
end

---Merge commands with objective safety priorities.
---Priority order:
---1) Objective interaction
---2) Combat disengage
---3) Combat target/face
---4) Intent movement/face fallback
---@param intent_output IntentOutput|nil
---@param combat_command table|nil
---@param world_model WorldModel|nil
---@return table
function action_arbiter:resolve(intent_output, combat_command, world_model)
    local out = safe_copy(intent_output)

    if not combat_command then
        return out
    end

    -- Objective interactions remain top-priority and untouched.
    if out.interact_target then
        return out
    end

    local ctype = tostring(combat_command.type or "")
    if ctype == "stop_attack" then
        out.stop_attack = true
        out.face_target = nil
        return out
    end

    if ctype == "set_target" or ctype == "face_target" then
        if combat_command.target then
            out.combat_target = combat_command.target
            -- Use combat target for facing when not interacting.
            out.face_target = combat_command.target
        end
    end

    if combat_command.halt_movement then
        out.nav_goal = nil
    elseif combat_command.movement_override then
        local safe_override = sanitize_movement_override(combat_command.movement_override, world_model)
        if safe_override then
            out.nav_goal = safe_override
        end
    end

    return out
end

return action_arbiter
