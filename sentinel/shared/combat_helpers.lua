-- shared/combat_helpers.lua
-- Canonical utilities for combat BT actions and conditions.
-- Eliminates the 5+ copies of player_and_target, spell_id_for,
-- dispatcher, queue_target, queue_position across action/condition/action files.

local QueuePriorities = require("shared/queue_priorities")
local Status = require("core/bt/status")

local CombatHelpers = {}

local function num(value)
    return tonumber(value) or 0
end

---Safe method call with pcall wrapper.
---Returns (ok, result) matching the pattern used across combat engine files.
---@param obj table|nil
---@param method string
---@param ... any
---@return boolean ok
---@return any|nil result
function CombatHelpers.safe_call(obj, method, ...)
    if not obj or type(obj[method]) ~= "function" then
        return false, nil
    end
    return pcall(obj[method], obj, ...)
end

---Convert value to number, defaulting to 0.
function CombatHelpers.num(value)
    return num(value)
end

---3D distance between two position tables.
---@return number
function CombatHelpers.distance(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return 99999
    end
    local dx = num(a.x) - num(b.x)
    local dy = num(a.y) - num(b.y)
    local dz = num(a.z) - num(b.z)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

---Resolve player and target from blackboard.
---@return table|nil player
---@return table|nil target
function CombatHelpers.player_and_target(blackboard)
    return blackboard:get("player.object"), blackboard:get("combat.target") or blackboard:get("player.target")
end

---Resolve a spell ID from the catalog by key.
---@param blackboard table
---@param spell_key string
---@param mode string|nil "lowest" for lowest rank, nil for best rank
---@return number|nil
function CombatHelpers.spell_id_for(blackboard, spell_key, mode)
    local catalog = blackboard:get("module.combat.catalog")
    if not catalog then
        return nil
    end
    if mode == "lowest" then
        return catalog:resolve_lowest_rank(spell_key)
    end
    return catalog:resolve_best_rank(spell_key)
end

---Get spell dispatcher from blackboard.
---@return table|nil
function CombatHelpers.dispatcher(blackboard)
    return blackboard:get("module.combat.dispatcher")
end

---Queue a targeted spell via the dispatcher (delegates to SpellDispatcher:queue_spell).
---Falls back to pre-resolved queue_target for backward compat with test mocks.
---@param blackboard table
---@param action_id string
---@param spell_key string
---@param target table
---@param priority number|nil
---@param opts table|nil
---@param mode string|nil "lowest" or nil
---@return string Status.SUCCESS or Status.FAILURE
function CombatHelpers.queue_target(blackboard, action_id, spell_key, target, priority, opts, mode)
    local d = CombatHelpers.dispatcher(blackboard)
    if not d then return Status.FAILURE end
    priority = priority or QueuePriorities.DEFAULT
    if d.queue_spell then
        if d:queue_spell(spell_key, target, priority, action_id, opts, mode) then
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
    -- Fallback: pre-resolve ID and call queue_target directly
    local spell_id = CombatHelpers.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end
    if d:queue_target(action_id, spell_id, target, priority, action_id, opts) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

---Queue a position-targeted spell via the dispatcher.
---Falls back to pre-resolved queue_position for backward compat with test mocks.
---@param blackboard table
---@param action_id string
---@param spell_key string
---@param position table
---@param priority number|nil
---@param mode string|nil "lowest" or nil
---@return string Status.SUCCESS or Status.FAILURE
function CombatHelpers.queue_position(blackboard, action_id, spell_key, position, priority, mode)
    local d = CombatHelpers.dispatcher(blackboard)
    if not d or type(position) ~= "table" then return Status.FAILURE end
    priority = priority or QueuePriorities.DEFAULT
    if d.queue_position_spell then
        if d:queue_position_spell(spell_key, position, priority, action_id, mode) then
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
    -- Fallback
    local spell_id = CombatHelpers.spell_id_for(blackboard, spell_key, mode)
    if not spell_id then return Status.FAILURE end
    if d:queue_position(action_id, spell_id, position, priority, action_id) then
        return Status.SUCCESS
    end
    return Status.FAILURE
end

return CombatHelpers
