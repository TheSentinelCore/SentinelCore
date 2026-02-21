---@module BGBOT.core.combat_micro.generic_combat
-- Safe generic combat policy: target select/face/auto-attack guardrails only.

local generic_combat = {}
generic_combat.__index = generic_combat

local function safe_call_method(obj, method_name, ...)
    if not obj then
        return nil, false
    end
    local fn = obj[method_name]
    if type(fn) ~= "function" then
        return nil, false
    end
    local ok, result = pcall(fn, obj, ...)
    if not ok then
        return nil, false
    end
    return result, true
end

local function is_valid_handle(handle)
    local valid, ok = safe_call_method(handle, "is_valid")
    return ok and valid == true
end

local function same_handle(a, b)
    if not a or not b then
        return false
    end
    return tostring(a) == tostring(b)
end

function generic_combat.new()
    return setmetatable({}, generic_combat)
end

---Return one generic combat command.
---@param target EntityRecord|nil
---@param world_model WorldModel
---@param intent_context table|nil
---@return table|nil
function generic_combat:get_next_action(target, world_model, intent_context)
    local self_state = world_model and world_model:get_self() or nil
    if not self_state or not self_state.handle or not is_valid_handle(self_state.handle) then
        return nil
    end

    if intent_context and intent_context.disengage_requested then
        return {
            type = "stop_attack",
            priority = 9,
            reason = "intent_disengage",
        }
    end

    if not target or not target.handle or not is_valid_handle(target.handle) then
        local auto_attacking, ok = safe_call_method(self_state.handle, "is_auto_attacking")
        if ok and auto_attacking then
            return {
                type = "stop_attack",
                priority = 5,
                reason = "no_target",
            }
        end
        return nil
    end

    local current_target, got_target = safe_call_method(self_state.handle, "get_target")
    if (not got_target) or (not same_handle(current_target, target.handle)) then
        return {
            type = "set_target",
            target = target.handle,
            priority = 4,
            reason = "target_switch",
        }
    end

    return {
        type = "face_target",
        target = target.handle,
        priority = 2,
        reason = "maintain_face",
    }
end

return generic_combat
