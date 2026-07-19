-- sentinel/runtime/command_history.lua
-- Undo/Redo system using the Command pattern
-- Each reversible action creates a Command object with execute() and undo() methods

local CommandHistory = {}
CommandHistory.__index = CommandHistory

---Create a new CommandHistory
---@param blackboard table The SentinelCore blackboard (optional, for storing state)
---@return table CommandHistory instance
function CommandHistory:new(blackboard)
    local o = setmetatable({}, CommandHistory)
    o._blackboard = blackboard
    o._undo_stack = {}
    o._redo_stack = {}
    o._event_bus = nil
    return o
end

---Set the event bus for publishing state changes
---@param event_bus table
function CommandHistory:set_event_bus(event_bus)
    self._event_bus = event_bus
end

---Publish a state change event
---@param event string Event name
---@param payload table Event payload
function CommandHistory:_publish(event, payload)
    if self._event_bus and self._event_bus.publish then
        self._event_bus:publish(event, payload)
    end
end

-- ============================================================================
-- Command Interface
-- ============================================================================

---Create an AddAction command
---@param operation_id string
---@param action table Action to add
---@return table
function CommandHistory:create_add_action_command(operation_id, action)
    local cmd = {
        type = "add_action",
        operation_id = operation_id,
        action = action,
    }
    function cmd.execute(target)
        if target and type(target.add_action) == "function" then
            target.add_action(cmd.operation_id, cmd.action)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.remove_action_by_id) == "function" then
            target.remove_action_by_id(cmd.operation_id, cmd.action.id)
        end
        return true
    end
    return cmd
end

---Create a RemoveAction command
---@param operation_id string
---@param action table The removed action
---@param index number The index where action was removed
---@return table
function CommandHistory:create_remove_action_command(operation_id, action, index)
    local cmd = {
        type = "remove_action",
        operation_id = operation_id,
        action = action,
        index = index,
    }
    function cmd.execute(target)
        if target and type(target.remove_action_by_id) == "function" then
            target.remove_action_by_id(cmd.operation_id, cmd.action.id)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.insert_action_at) == "function" then
            target.insert_action_at(cmd.operation_id, cmd.index, cmd.action)
        end
        return true
    end
    return cmd
end

---Create an EditField command
---@param operation_id string
---@param action_id string
---@param field string Field name
---@param old_value any Original value
---@param new_value any New value
---@return table
function CommandHistory:create_edit_field_command(operation_id, action_id, field, old_value, new_value)
    local cmd = {
        type = "edit_field",
        operation_id = operation_id,
        action_id = action_id,
        field = field,
        old_value = old_value,
        new_value = new_value,
    }
    function cmd.execute(target)
        if target and type(target.set_action_field) == "function" then
            target.set_action_field(cmd.operation_id, cmd.action_id, cmd.field, cmd.new_value)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.set_action_field) == "function" then
            target.set_action_field(cmd.operation_id, cmd.action_id, cmd.field, cmd.old_value)
        end
        return true
    end
    return cmd
end

---Create a CreateVariable command
---@param scope string
---@param key string
---@param value any
---@return table
function CommandHistory:create_create_variable_command(scope, key, value)
    local cmd = {
        type = "create_variable",
        scope = scope,
        key = key,
        value = value,
    }
    function cmd.execute(target)
        if target and type(target.set) == "function" then
            target.set(cmd.scope, cmd.key, cmd.value)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.delete) == "function" then
            target.delete(cmd.scope, cmd.key)
        end
        return true
    end
    return cmd
end

---Create a DeleteVariable command
---@param scope string
---@param key string
---@param value any The deleted value (for restoration)
---@return table
function CommandHistory:create_delete_variable_command(scope, key, value)
    local cmd = {
        type = "delete_variable",
        scope = scope,
        key = key,
        value = value,
    }
    function cmd.execute(target)
        if target and type(target.delete) == "function" then
            target.delete(cmd.scope, cmd.key)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.set) == "function" then
            target.set(cmd.scope, cmd.key, cmd.value)
        end
        return true
    end
    return cmd
end

---Create a CaptureNPC command
---@param npc table NPC data captured
---@return table
function CommandHistory:create_capture_npc_command(npc)
    local cmd = {
        type = "capture_npc",
        npc = npc,
    }
    function cmd.execute(target)
        if target and type(target.add) == "function" then
            target.add(cmd.npc)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.delete) == "function" then
            target.delete(cmd.npc.entry)
        end
        return true
    end
    return cmd
end

---Create a MoveAction command (for reordering)
---@param operation_id string
---@param action_id string
---@param from_index number Original index
---@param to_index number Target index
---@return table
function CommandHistory:create_move_action_command(operation_id, action_id, from_index, to_index)
    local cmd = {
        type = "move_action",
        operation_id = operation_id,
        action_id = action_id,
        from_index = from_index,
        to_index = to_index,
    }
    function cmd.execute(target)
        if target and type(target.move_action) == "function" then
            target.move_action(cmd.operation_id, cmd.action_id, cmd.to_index)
        end
        return true
    end
    function cmd.undo(target)
        if target and type(target.move_action) == "function" then
            target.move_action(cmd.operation_id, cmd.action_id, cmd.from_index)
        end
        return true
    end
    return cmd
end

-- ============================================================================
-- Public API
-- ============================================================================

---Execute a command and push to undo stack
---@param command table Command object with execute() and undo() methods
---@param target any Target object to pass to execute/undo
---@return boolean success
function CommandHistory:execute(command, target)
    if not command or not command.execute then
        return false
    end
    
    local ok, err = pcall(function()
        if type(command.execute) == "function" then
            command.execute(target)
        end
    end)
    
    if ok then
        table.insert(self._undo_stack, command)
        self._redo_stack = {} -- Clear redo stack on new action
        self:_publish("command_history:changed", {
            can_undo = true,
            can_redo = false,
        })
    end
    
    return ok
end

---Undo the last command
---@param target any Target object to pass to undo
---@return boolean success
function CommandHistory:undo(target)
    if #self._undo_stack == 0 then
        return false
    end
    
    local command = table.remove(self._undo_stack)
    local ok, err = pcall(function()
        if type(command.undo) == "function" then
            command.undo(target)
        end
    end)
    
    if ok then
        table.insert(self._redo_stack, command)
        self:_publish("command_history:changed", {
            can_undo = #self._undo_stack > 0,
            can_redo = #self._redo_stack > 0,
        })
    end
    
    return ok
end

---Redo the last undone command
---@param target any Target object to pass to execute
---@return boolean success
function CommandHistory:redo(target)
    if #self._redo_stack == 0 then
        return false
    end
    
    local command = table.remove(self._redo_stack)
    local ok, err = pcall(function()
        if type(command.execute) == "function" then
            command.execute(target)
        end
    end)
    
    if ok then
        table.insert(self._undo_stack, command)
        self:_publish("command_history:changed", {
            can_undo = #self._undo_stack > 0,
            can_redo = #self._redo_stack > 0,
        })
    end
    
    return ok
end

---Check if undo is available
---@return boolean
function CommandHistory:can_undo()
    return #self._undo_stack > 0
end

---Check if redo is available
---@return boolean
function CommandHistory:can_redo()
    return #self._redo_stack > 0
end

---Clear all history (typically on save)
function CommandHistory:clear()
    self._undo_stack = {}
    self._redo_stack = {}
    self:_publish("command_history:changed", {
        can_undo = false,
        can_redo = false,
    })
end

---Get the current undo stack size
---@return number
function CommandHistory:get_undo_size()
    return #self._undo_stack
end

---Get the current redo stack size
---@return number
function CommandHistory:get_redo_size()
    return #self._redo_stack
end

return CommandHistory