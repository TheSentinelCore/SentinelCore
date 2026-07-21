-- tests/modules/questing/test_runtime_action.lua
-- Unit tests for runtime action execution

local RuntimeAction = require("modules/questing/runtime_action")

local M = {}

function M.test_runtime_action_table()
    assert(type(RuntimeAction) == "table", "RuntimeAction should be a table")
    assert(type(RuntimeAction.execute) == "function", "RuntimeAction.execute should be a function")
end

function M.test_execute_comment()
    local ctx = { variables = {} }
    local action = { type = "Comment", payload = { text = "Test comment" } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "Comment action should succeed")
end

function M.test_execute_set_variable()
    local ctx = { variables = {} }
    local action = { type = "SetVariable", payload = { name = "test_var", value = 42 } }
    local result = RuntimeAction.execute(action, ctx)
    assert(result == "success", "SetVariable action should succeed")
    assert(ctx.variables.test_var == 42, "Variable should be set")
end

return M