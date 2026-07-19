-- sentinel/tests/ui/test_toolbar_undo_wiring.lua
-- SENT-10.17 / SENT-8.9: toolbar Undo/Redo reflects CommandHistory state and
-- routes toolbar:undo / toolbar:redo events to the engine's command history.

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")
local RuntimeEngine = require("runtime/runtime_engine")
local CommandHistory = require("runtime/command_history")
local Toolbar = require("ui/toolbar")

local M = {}

function M.run()
    print("=== Toolbar Undo/Redo Wiring Tests ===")

    local bb = Blackboard:new()
    local eb = EventBus:new()

    -- Toolbar starts with undo/redo disabled until a command_history:changed
    -- event arrives.
    local toolbar = Toolbar:new(nil, eb, nil)
    toolbar:init()
    T.assert_false(toolbar._can_undo, "toolbar starts unable to undo")
    T.assert_false(toolbar._can_redo, "toolbar starts unable to redo")

    eb:publish("command_history:changed", { can_undo = true, can_redo = false })
    T.assert_true(toolbar._can_undo, "toolbar enables undo on command_history:changed")
    T.assert_false(toolbar._can_redo, "toolbar keeps redo disabled when nothing to redo")

    -- Engine + command history: executing a command then publishing
    -- toolbar:undo should revert it.
    local profile = { id = "prof-t", operations = { { id = "op-t", actions = {} } } }
    local pm = {
        get_active_profile = function() return profile end,
        get_active_profile_id = function() return "prof-t" end,
    }
    local eng = RuntimeEngine:new(bb, eb, pm, { _state = "idle" })
    eng:set_command_history(CommandHistory:new(bb))

    local target = {
        add_action = function(op_id, action)
            for _, op in ipairs(profile.operations) do
                if op.id == op_id then table.insert(op.actions, action) end
            end
        end,
        remove_action_by_id = function(op_id, action_id)
            for _, op in ipairs(profile.operations) do
                if op.id == op_id then
                    for i, a in ipairs(op.actions) do
                        if a.id == action_id then table.remove(op.actions, i) end
                    end
                end
            end
        end,
    }
    eng:set_command_target(target)
    local add_cmd = eng:get_command_history():create_add_action_command(
        "op-t", { id = "a1", action_type = "loot" })
    eng:execute_command(add_cmd, target)
    T.assert_equal(#profile.operations[1].actions, 1, "action added via command")

    -- Simulate the toolbar's Undo button click (publishes toolbar:undo).
    eb:publish("toolbar:undo", {})
    T.assert_equal(#profile.operations[1].actions, 0, "toolbar:undo reverted the action")

    -- Redo via toolbar:redo restores it.
    eb:publish("toolbar:redo", {})
    T.assert_equal(#profile.operations[1].actions, 1, "toolbar:redo restored the action")

    print("  PASS")
    print("\n=== All Toolbar Undo/Redo Wiring Tests PASSED ===")
end

return M
