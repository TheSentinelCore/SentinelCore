-- sentinel/tests/modules/quest/test_compiler_pass3.lua
-- Tests for Compiler Pass 3: Dead Code Elimination (Ticket 006).

local TestUtil = require("tests/test_util")
local CompilerPass3 = require("modules/quest/compiler_pass3")

local M = {}

local function raw_action(atype, args, condition)
  return { type = atype, args = args or {}, condition = condition }
end

local function mock_provider()
  local p = { _quests = { [100] = { prev_quest_id = 99 } } }
  function p:getQuest(id) return self._quests[id] end
  return p
end

function M.run()
  local pass = CompilerPass3.new(mock_provider())

  local ast = {
    project = {
      name = "test",
      variables = {
        usedVar = { type = "number", default = 0 },
        unusedVar = { type = "number", default = 0 },
      },
    },
    operations = {
      op1 = {
        name = "op1",
        variables = { localUsed = { type = "boolean" }, localUnused = { type = "boolean" } },
        actions = {
          -- references $usedVar and $localUsed -> both kept
          raw_action("KillCreature", { quest_id = 100 }, "$usedVar and $localUsed"),
          -- impossible condition -> eliminated
          raw_action("Vendor", {}, "false"),
          -- normal action, kept
          raw_action("TravelTo", { method = "walk" }),
        },
      },
    },
    blueprints = {
      used_bp = { name = "used_bp", expands_to = { raw_action("TalkToNPC", { npc_name = "X" }) } },
      orphan_bp = { name = "orphan_bp", expands_to = { raw_action("Repair", {}) } },
    },
  }
  -- Make used_bp referenced by op1 so it is NOT eliminated.
  table.insert(ast.operations.op1.actions, { type = "BlueprintReference", blueprint_name = "used_bp" })

  local result = pass:run(ast)
  TestUtil.assert_true(result.ok, "pass3 runs successfully")

  -- Unused blueprint removed, used blueprint kept.
  TestUtil.assert_nil(ast.blueprints.orphan_bp, "unused blueprint should be removed")
  TestUtil.assert_not_nil(ast.blueprints.used_bp, "referenced blueprint should be kept")

  -- Unused project/operation variables removed; referenced ones kept.
  TestUtil.assert_nil(ast.project.variables.unusedVar, "unused project variable removed")
  TestUtil.assert_not_nil(ast.project.variables.usedVar, "referenced project variable kept")
  TestUtil.assert_nil(ast.operations.op1.variables.localUnused, "unused operation variable removed")
  TestUtil.assert_not_nil(ast.operations.op1.variables.localUsed, "referenced operation variable kept")

  -- Impossible-condition action eliminated (Vendor removed -> 3 remaining actions).
  TestUtil.assert_equal(#ast.operations.op1.actions, 3, "impossible action removed, 3 remain")
  local has_vendor = false
  for _, a in ipairs(ast.operations.op1.actions) do
    if (a.type or a.action_type) == "Vendor" then has_vendor = true end
  end
  TestUtil.assert_false(has_vendor, "Vendor with 'false' condition is eliminated")

  -- Elimination recorded for traceability.
  TestUtil.assert_equal(#result.eliminated.blueprints, 1, "one blueprint recorded eliminated")
  TestUtil.assert_equal(#result.eliminated.actions, 1, "one impossible action recorded")
  TestUtil.assert_equal(#result.eliminated.variables, 2, "two unused variables recorded")
  TestUtil.assert_equal(#result.eliminated.operations, 1, "disconnected operation recorded")
  TestUtil.assert_equal(result.eliminated.operations[1].missing[1], 99, "missing prereq 99 recorded")
end

return M
