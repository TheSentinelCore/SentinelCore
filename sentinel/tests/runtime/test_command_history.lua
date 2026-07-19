-- sentinel/tests/runtime/test_command_history.lua
-- Tests for runtime/command_history.lua

local T = require("tests/test_util")

local M = {}

function M.test_command_history_construction()
    print("Test: CommandHistory construction")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    T.assert_not_nil(ch, "CommandHistory instance should not be nil")
    T.assert_equal(ch:get_undo_size(), 0, "Initial undo stack should be empty")
    T.assert_equal(ch:get_redo_size(), 0, "Initial redo stack should be empty")
    T.assert_false(ch:can_undo(), "can_undo should be false initially")
    T.assert_false(ch:can_redo(), "can_redo should be false initially")
    print("  PASS")
end

function M.test_undo_redo_basic()
    print("Test: Undo/Redo basic")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    -- Simple command that increments a value
    local state = { value = 0 }
    local cmd = {
        type = "test_increment",
        old_value = 0,
        new_value = 1,
    }
    function cmd.execute(s) s.value = cmd.new_value end
    function cmd.undo(s) s.value = cmd.old_value end
    
    ch:execute(cmd, state)
    T.assert_equal(state.value, 1, "After execute, value should be 1")
    T.assert_true(ch:can_undo(), "can_undo should be true after execute")
    T.assert_equal(ch:get_undo_size(), 1, "Undo stack should have 1 item")
    
    local ok = ch:undo(state)
    T.assert_true(ok, "undo should succeed")
    T.assert_equal(state.value, 0, "After undo, value should be back to 0")
    T.assert_true(ch:can_redo(), "can_redo should be true after undo")
    
    ch:redo(state)
    T.assert_equal(state.value, 1, "After redo, value should be 1 again")
    T.assert_false(ch:can_redo(), "can_redo should be false after redo")
    print("  PASS")
end

function M.test_add_action_command()
    print("Test: AddAction command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    -- Mock profile manager using simple function notation
    local actions = {}
    local pm = {
        add_action = function(op_id, action)
            actions[action.id] = action
        end,
        remove_action_by_id = function(op_id, action_id)
            actions[action_id] = nil
        end,
    }
    
    local cmd = ch:create_add_action_command("op_1", { id = "action_1", type = "goto" })
    
    -- Execute the command
    cmd.execute(pm)
    
    -- Check the action was added
    local found = false
    for k, v in pairs(actions) do
        if k == "action_1" and v.type == "goto" then
            found = true
        end
    end
    T.assert_true(found, "Action should be added")
    
    -- Undo
    cmd.undo(pm)
    T.assert_nil(actions.action_1, "Action should be removed after undo")
    print("  PASS")
end

function M.test_remove_action_command()
    print("Test: RemoveAction command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    local actions = {
        action_1 = { id = "action_1", type = "goto" },
        action_2 = { id = "action_2", type = "kill" },
    }
    local pm = {
        remove_action_by_id = function(op_id, action_id)
            actions[action_id] = nil
        end,
        insert_action_at = function(op_id, index, action)
            actions[action.id] = action
        end,
    }
    
    local cmd = ch:create_remove_action_command("op_1", { id = "action_1", type = "goto" }, 1)
    cmd.execute(pm)
    
    T.assert_nil(actions["action_1"], "Action should be removed")
    
    cmd.undo(pm)
    T.assert_not_nil(actions["action_1"], "Action should be restored after undo")
    print("  PASS")
end

function M.test_edit_field_command()
    print("Test: EditField command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    local action = { id = "a1", type = "goto", target = "OldTarget" }
    local pm = {
        set_action_field = function(op_id, action_id, field, value)
            action[field] = value
        end,
    }
    
    local cmd = ch:create_edit_field_command("op_1", "a1", "target", "OldTarget", "NewTarget")
    cmd.execute(pm)
    
    T.assert_equal(action.target, "NewTarget", "Field should be updated to new value")
    
    cmd.undo(pm)
    T.assert_equal(action.target, "OldTarget", "Field should be restored to old value")
    print("  PASS")
end

function M.test_create_variable_command()
    print("Test: CreateVariable command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    local vars = {}
    local vs = {
        set = function(scope, key, value)
            vars[scope .. "." .. key] = value
        end,
        delete = function(scope, key)
            vars[scope .. "." .. key] = nil
        end,
    }
    
    local cmd = ch:create_create_variable_command("global", "test_var", 42)
    cmd.execute(vs)
    
    T.assert_equal(vars["global.test_var"], 42, "Variable should be created")
    
    cmd.undo(vs)
    T.assert_nil(vars["global.test_var"], "Variable should be deleted after undo")
    print("  PASS")
end

function M.test_delete_variable_command()
    print("Test: DeleteVariable command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    local vars = { ["global.old_var"] = "old_value" }
    local vs = {
        set = function(scope, key, value)
            vars[scope .. "." .. key] = value
        end,
        delete = function(scope, key)
            vars[scope .. "." .. key] = nil
        end,
    }
    
    local cmd = ch:create_delete_variable_command("global", "old_var", "old_value")
    cmd.execute(vs)
    
    T.assert_nil(vars["global.old_var"], "Variable should be deleted")
    
    cmd.undo(vs)
    T.assert_equal(vars["global.old_var"], "old_value", "Variable should be restored after undo")
    print("  PASS")
end

function M.test_clear_on_save()
    print("Test: Clear on save")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    -- Add some commands
    local cmd = {
        type = "test",
        execute = function() end,
        undo = function() end,
    }
    ch:execute(cmd, {})
    ch:execute(cmd, {})
    
    T.assert_true(ch:can_undo(), "can_undo should be true")
    T.assert_equal(ch:get_undo_size(), 2, "Undo stack should have 2 items")
    
    ch:clear()
    
    T.assert_false(ch:can_undo(), "can_undo should be false after clear")
    T.assert_equal(ch:get_undo_size(), 0, "Undo stack should be empty after clear")
    print("  PASS")
end

function M.test_redo_stack_cleared_on_new_action()
    print("Test: Redo stack cleared on new action")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    -- Create and execute first command
    local cmd1 = {
        type = "test",
        value = 1,
        execute = function() end,
        undo = function() end,
    }
    ch:execute(cmd1, {})
    
    -- Undo it
    ch:undo({})
    T.assert_true(ch:can_redo(), "can_redo should be true after undo")
    
    -- Execute a new command (should clear redo stack)
    local cmd2 = {
        type = "test",
        value = 1,
        execute = function() end,
        undo = function() end,
    }
    ch:execute(cmd2, {})
    
    T.assert_false(ch:can_redo(), "can_redo should be false after new action")
    print("  PASS")
end

function M.test_move_action_command()
    print("Test: MoveAction command")
    local CommandHistory = require("runtime/command_history")
    local ch = CommandHistory:new(nil)
    
    local pm = {
        move_action_calls = {},
    }
    function pm.move_action(op_id, action_id, index)
        table.insert(pm.move_action_calls, { op = op_id, action = action_id, idx = index })
    end
    
    local cmd = ch:create_move_action_command("op_1", "a1", 1, 3)
    cmd.execute(pm)
    
    T.assert_equal(pm.move_action_calls[1].idx, 3, "Action should be moved to index 3")
    
    cmd.undo(pm)
    T.assert_equal(pm.move_action_calls[2].idx, 1, "Undo should move action back to index 1")
    print("  PASS")
end

function M.run()
    print("=== Command History Tests ===")
    M.test_command_history_construction()
    M.test_undo_redo_basic()
    M.test_add_action_command()
    M.test_remove_action_command()
    M.test_edit_field_command()
    M.test_create_variable_command()
    M.test_delete_variable_command()
    M.test_clear_on_save()
    M.test_redo_stack_cleared_on_new_action()
    M.test_move_action_command()
    print("\n=== All Command History Tests PASSED ===")
end

return M