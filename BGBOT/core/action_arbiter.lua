---@module BGBOT.core.action_arbiter
-- Resolve intent output + combat command into a single executable frame command.

local action_arbiter = {}
action_arbiter.__index = action_arbiter

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
---@param _world_model WorldModel|nil
---@return table
function action_arbiter:resolve(intent_output, combat_command, _world_model)
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

    return out
end

return action_arbiter
