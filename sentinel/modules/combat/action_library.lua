local QueuePriorities = require("shared/queue_priorities")
local Status = require("core/bt/status")
local AuraCatalog = require("modules/combat/aura_catalog")
local H = require("shared/combat_helpers")

local ActionLibrary = {}

-- ============================================================================
-- BASIC ACTIONS
-- ============================================================================

--- Cast spell at target
-- @param spell_key string Spell identifier from spell catalog
-- @param target_fn function(blackboard) -> game_object|nil Optional target selector (defaults to combat.target)
-- @param priority number Queue priority (defaults to QueuePriorities.DEFAULT)
-- @param opts table Optional queue options (e.g. { fast = true })
-- @return function(blackboard) -> BT.Status
function ActionLibrary.cast_target(spell_key, target_fn, priority, opts)
    target_fn = target_fn or function(bb) return bb:get("combat.target") or bb:get("player.target") end
    priority = priority or QueuePriorities.DEFAULT
    return function(blackboard)
        local _, target = H.player_and_target(blackboard)
        local actual_target = target_fn and target_fn(blackboard) or target
        if not actual_target then
            return Status.FAILURE
        end
        return H.queue_target(blackboard, spell_key .. "_target", spell_key, actual_target, priority, opts)
    end
end

--- Cast spell at self
-- @param spell_key string Spell identifier from spell catalog
-- @param priority number Queue priority (defaults to QueuePriorities.DEFAULT)
-- @param opts table Optional queue options
-- @return function(blackboard) -> BT.Status
function ActionLibrary.cast_self(spell_key, priority, opts)
    priority = priority or QueuePriorities.DEFAULT
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then
            return Status.FAILURE
        end
        return H.queue_target(blackboard, spell_key .. "_self", spell_key, player, priority, opts)
    end
end

--- Cast spell at position (ground targeted AoE)
-- @param spell_key string Spell identifier from spell catalog
-- @param position_fn function(blackboard) -> {x,y,z}|nil Position selector
-- @param priority number Queue priority (defaults to QueuePriorities.DEFAULT)
-- @param opts table Optional queue options
-- @return function(blackboard) -> BT.Status
function ActionLibrary.cast_position(spell_key, position_fn, priority, opts)
    priority = priority or QueuePriorities.DEFAULT
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then
            return Status.FAILURE
        end
        local position = position_fn and position_fn(blackboard)
        if not position or type(position) ~= "table" then
            return Status.FAILURE
        end
        return H.queue_position(blackboard, spell_key .. "_position", spell_key, position, priority, opts)
    end
end

--- Use item from inventory
-- @param item_id number|string Item ID or name
-- @param priority number Queue priority (defaults to QueuePriorities.DEFAULT)
-- @return function(blackboard) -> BT.Status
function ActionLibrary.use_item(item_id, priority)
    priority = priority or QueuePriorities.DEFAULT
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then
            return Status.FAILURE
        end
        -- Use spell queue for items that support it (consistent with spell casting)
        local d = H.dispatcher(blackboard)
        if d and d.queue_item_self then
            local ok, result = pcall(d.queue_item_self, d, item_id, priority, "use_item")
            if ok and result ~= false then
                return Status.SUCCESS
            end
        end
        -- Fallback to direct input (for items without spell queue support)
        if core and core.input and type(core.input.use_item) == "function" then
            pcall(core.input.use_item, item_id)
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

--- Use item on target
-- @param item_id number|string Item ID or name
-- @param target_fn function(blackboard) -> game_object|nil Optional target selector
-- @param priority number Queue priority (defaults to QueuePriorities.DEFAULT)
-- @return function(blackboard) -> BT.Status
function ActionLibrary.use_item_on_target(item_id, target_fn, priority)
    target_fn = target_fn or function(bb) return bb:get("combat.target") or bb:get("player.target") end
    priority = priority or QueuePriorities.DEFAULT
    return function(blackboard)
        local player = blackboard:get("player.object")
        if not player then
            return Status.FAILURE
        end
        local target = target_fn and target_fn(blackboard)
        if not target then
            return Status.FAILURE
        end
        -- Try spell queue first
        local d = H.dispatcher(blackboard)
        if d and d.queue_item_target then
            local ok, result = pcall(d.queue_item_target, d, item_id, target, priority, "use_item_on_target")
            if ok and result ~= false then
                return Status.SUCCESS
            end
        end
        -- Fallback to direct input
        if core and core.input and type(core.input.use_item_target) == "function" then
            pcall(core.input.use_item_target, item_id, target)
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

-- ============================================================================
-- INTERRUPT ACTIONS (High priority)
-- ============================================================================

--- Interrupt cast with specified spell
-- @param spell_key string Spell identifier for interrupt (e.g. "counterspell", "pummel")
-- @param priority number Queue priority (defaults to QueuePriorities.INTERRUPT)
-- @param opts table Optional queue options
-- @return function(blackboard) -> BT.Status
function ActionLibrary.interrupt(spell_key, priority, opts)
    priority = priority or QueuePriorities.INTERRUPT
    return function(blackboard)
        local _, target = H.player_and_target(blackboard)
        if not target then
            return Status.FAILURE
        end
        return H.queue_target(blackboard, spell_key .. "_interrupt", spell_key, target, priority, opts)
    end
end

--- Cancel current cast
-- @return function(blackboard) -> BT.Status
function ActionLibrary.cancel_cast()
    return function(blackboard)
        if core and core.input and type(core.input.cancel_spells) == "function" then
            pcall(core.input.cancel_spells)
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

-- ============================================================================
-- MOVEMENT ACTIONS
-- ============================================================================

--- Stop movement
-- @return function(blackboard) -> BT.Status
function ActionLibrary.stop_movement()
    return function(blackboard)
        if core and core.input then
            -- Stop all movement
            if core.input.move_forward_stop then pcall(core.input.move_forward_stop) end
            if core.input.move_backward_stop then pcall(core.input.move_backward_stop) end
            if core.input.strafe_left_stop then pcall(core.input.strafe_left_stop) end
            if core.input.strafe_right_stop then pcall(core.input.strafe_right_stop) end
            if core.input.turn_left_stop then pcall(core.input.turn_left_stop) end
            if core.input.turn_right_stop then pcall(core.input.turn_right_stop) end
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

-- ============================================================================
-- PET ACTIONS
-- ============================================================================

--- Pet attack target
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_attack()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        local target = blackboard:get("combat.target") or blackboard:get("player.target")
        if not pet_ctrl or not target then
            return Status.FAILURE
        end
        if pet_ctrl:already_sent_to(target) then
            return Status.FAILURE
        end
        pet_ctrl:attack(target)
        return Status.SUCCESS
    end
end

--- Pet follow target
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_follow()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        local target = blackboard:get("combat.target") or blackboard:get("player.target")
        if not pet_ctrl or not target then
            return Status.FAILURE
        end
        pet_ctrl:follow(target)
        return Status.SUCCESS
    end
end

--- Pet stay/stop
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_stop()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        if not pet_ctrl then
            return Status.FAILURE
        end
        pet_ctrl:stop()
        return Status.SUCCESS
    end
end

--- Pet passive mode
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_passive()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        if not pet_ctrl then
            return Status.FAILURE
        end
        pet_ctrl:passive()
        return Status.SUCCESS
    end
end

--- Pet defensive mode
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_defensive()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        if not pet_ctrl then
            return Status.FAILURE
        end
        pet_ctrl:defensive()
        return Status.SUCCESS
    end
end

--- Pet aggressive mode
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_aggressive()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        if not pet_ctrl then
            return Status.FAILURE
        end
        pet_ctrl:aggressive()
        return Status.SUCCESS
    end
end

--- Pet assist mode
-- @return function(blackboard) -> BT.Status
function ActionLibrary.pet_assist()
    return function(blackboard)
        local pet_ctrl = blackboard:get("module.combat.pet_controller")
        if not pet_ctrl then
            return Status.FAILURE
        end
        pet_ctrl:assist()
        return Status.SUCCESS
    end
end

-- ============================================================================
-- BUFF/DEBUFF ACTIONS
-- ============================================================================

--- Cancel specific buff
-- @param buff_id number|string Buff ID to cancel
-- @return function(blackboard) -> BT.Status
function ActionLibrary.cancel_buff(buff_id)
    return function(blackboard)
        if core and core.input and type(core.input.cancel_buff) == "function" then
            pcall(core.input.cancel_buff, buff_id)
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

-- ============================================================================
-- LOOT ACTIONS
-- ============================================================================

--- Loot target corpse
-- @return function(blackboard) -> BT.Status
function ActionLibrary.loot_target()
    return function(blackboard)
        local target = blackboard:get("combat.target")
        if not target then
            return Status.FAILURE
        end
        if core and core.input and type(core.input.loot_object) == "function" then
            pcall(core.input.loot_object, target)
            return Status.SUCCESS
        end
        return Status.FAILURE
    end
end

-- ============================================================================
-- COMPOSITE ACTIONS
-- ============================================================================

--- Create a sequence of actions that all must succeed
-- @param actions table List of action functions
-- @return function(blackboard) -> BT.Status
function ActionLibrary.sequence(actions)
    return function(blackboard)
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status ~= Status.SUCCESS then
                return status
            end
        end
        return Status.SUCCESS
    end
end

--- Create a selector that tries actions in order until one succeeds
-- @param actions table List of action functions
-- @return function(blackboard) -> BT.Status
function ActionLibrary.selector(actions)
    return function(blackboard)
        for _, action in ipairs(actions) do
            local status = action(blackboard)
            if status == Status.SUCCESS then
                return Status.SUCCESS
            end
            -- Continue on FAILURE, but stop on RUNNING (let it continue next frame)
            if status == Status.RUNNING then
                return Status.RUNNING
            end
        end
        return Status.FAILURE
    end
end

return ActionLibrary