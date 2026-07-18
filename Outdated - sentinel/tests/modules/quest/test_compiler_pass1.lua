-- sentinel/tests/modules/quest/test_compiler_pass1.lua
-- Tests for Compiler Pass 1: DB Resolution and Validation.
-- Covers the Ticket-004 blocker: process_operation must not crash on a
-- missing/nil `actions` list, must process every action, and must return
-- properly structured error tables on validation failure.

local TestUtil = require("tests/test_util")
local CompilerPass1 = require("modules/quest/compiler_pass1")

local M = {}

local function raw_action(atype, args)
  return { type = atype, args = args or {} }
end

local function fake_ast(operations, blueprints)
  return {
    operations = operations or {},
    blueprints = blueprints or {},
  }
end

function M.run()
  -- 1. process_operation must NOT throw when `actions` is nil; it must capture
  --    a structured error and keep the operations table untouched.
  local pass = CompilerPass1.new()
  local broken_op = { name = "broken" } -- no `actions` field at all
  local errs = pass:process_operation(broken_op)
  TestUtil.assert_equal(#errs, 1, "nil actions should yield exactly one structured error")
  TestUtil.assert_equal(errs[1].code, "STRUCT_ACTIONS", "error code should be STRUCT_ACTIONS")
  TestUtil.assert_equal(type(errs[1].message), "string", "error must carry a message")

  -- 2. process_operation must process every action in a well-formed operation.
  local ok_op = {
    name = "northshire",
    actions = {
      raw_action("TalkToNPC", { npc_name = "Guard Maxwell" }),
      raw_action("KillCreature", { creature_name = "Innkeeper Allison" }),
      raw_action("CollectItem", { item_name = "Rugged Leather Pants" }),
    },
  }
  local ok_errs = pass:process_operation(ok_op)
  TestUtil.assert_equal(#ok_errs, 0, "all names resolve against the mock DB -> no errors")
  -- Resolution results must be annotated onto the args.
  TestUtil.assert_equal(ok_op.actions[1].args.npc_name_id, 1234, "Guard Maxwell resolves to 1234")
  TestUtil.assert_equal(ok_op.actions[2].args.creature_name_id, 5678, "Innkeeper Allison resolves to 5678")
  TestUtil.assert_equal(ok_op.actions[3].args.item_name_id, 9012, "Rugged Leather Pants resolves to 9012")

  -- 3. Unresolved names must be reported as structured errors, not thrown.
  local bad_op = {
    name = "bad",
    actions = {
      raw_action("TalkToNPC", { npc_name = "Nobody Here" }),
    },
  }
  local bad_errs = pass:process_operation(bad_op)
  TestUtil.assert_equal(#bad_errs, 1, "unresolved name yields one error")
  TestUtil.assert_equal(bad_errs[1].code, "RESOLVE_FAIL", "unresolved name code is RESOLVE_FAIL")
  TestUtil.assert_equal(bad_errs[1].severity, "error", "severity is 'error'")

  -- 4. process_action must normalize the AST node shape (`action_type`).
  local node_shape = { action_type = "TalkToNPC", args = { npc_name = "Guard Maxwell" } }
  local node_errs = pass:process_action(node_shape)
  TestUtil.assert_equal(#node_errs, 0, "AST node shape (action_type) resolves correctly")
  TestUtil.assert_equal(node_shape.args.npc_name_id, 1234, "node-shape resolution annotates args")

  -- 5. run() must aggregate operation errors into the public flat-string list.
  local ast = fake_ast({
    good = ok_op,
    bad = bad_op,
  })
  local result = pass:run(ast)
  TestUtil.assert_false(result.ok, "run() should fail when an operation has errors")
  TestUtil.assert_equal(#result.errors, 1, "run() aggregates one error for the bad operation")
  TestUtil.assert_true(result.errors[1]:find("Operation 'bad':"), "error is prefixed with operation name")

  -- 6. A fully clean AST must pass.
  local clean_ast = fake_ast({ good = ok_op })
  local clean_result = pass:run(clean_ast)
  TestUtil.assert_true(clean_result.ok, "clean AST passes pass1")

  -- 7. Blueprint references that are undefined must be reported.
  local bp_ast = fake_ast({}, {
    hub = {
      name = "hub",
      expands_to = {
        raw_action("TalkToNPC", { npc_name = "Guard Maxwell" }),
        { type = "BlueprintReference", blueprint_name = "does_not_exist" },
      },
    },
  })
  local bp_result = pass:run(bp_ast)
  TestUtil.assert_false(bp_result.ok, "undefined blueprint reference fails pass1")
end

return M
