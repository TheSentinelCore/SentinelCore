-- sentinel/tests/modules/quest/test_compiler_pass4.lua
-- Tests for Compiler Pass 4: Backend Emit JSON (Ticket 007).
-- Includes a unit test for pass4 and an end-to-end pipeline test (pass1->2->3->4).

local TestUtil = require("tests/test_util")
local CompilerPass1 = require("modules/quest/compiler_pass1")
local CompilerPass2 = require("modules/quest/compiler_pass2")
local CompilerPass3 = require("modules/quest/compiler_pass3")
local CompilerPass4 = require("modules/quest/compiler_pass4")

local M = {}

local function raw_action(atype, args, condition)
  return { type = atype, args = args or {}, condition = condition }
end

local function mock_qprovider()
  local p = {
    _quests = { [100] = { Method = 0, ReqItemId1 = 3456, ReqItemCount1 = 2 } },
  }
  function p:getQuest(id) return self._quests[id] end
  function p:getQuestNPCs(id, role)
    if id == 100 and role == "turnin" then return { { id = 5678, name = "Innkeeper" } } end
    return nil
  end
  function p:getTravelTime(_, _, _) return 45 end
  return p
end

function M.run()
  -- ---- Unit test: pass4 structure ----
  local ast = {
    project = { name = "elwynn", variables = { bagSlots = { type = "number", default = 0 } } },
    operations = {
      op1 = {
        name = "op1",
        actions = {
          raw_action("KillCreature", { creature_name = "Guard Maxwell", creature_name_id = 1234, quest_id = 100 }),
          raw_action("TravelTo", { method = "flight" }),
        },
      },
    },
    blueprints = {},
  }
  local pass4 = CompilerPass4.new()
  local res = pass4:run(ast)
  TestUtil.assert_true(res.ok, "pass4 emits a profile")
  local profile = res.profile

  TestUtil.assert_equal(profile.schemaVersion, "1.0.0", "schema version present")
  TestUtil.assert_equal(profile.metadata.projectName, "elwynn", "project name in metadata")
  TestUtil.assert_not_nil(profile.variables.bagSlots, "project variable emitted")
  TestUtil.assert_equal(profile.variables.bagSlots.type, "number", "variable type preserved")

  -- Region + states
  TestUtil.assert_not_nil(profile.regions["op:op1"], "region created")
  TestUtil.assert_equal(profile.regions["op:op1"].initial, "op:op1#1", "region initial is first action")
  TestUtil.assert_not_nil(profile.states["op:op1#1"], "state #1 exists")
  TestUtil.assert_not_nil(profile.states["op:op1#2"], "state #2 exists")
  TestUtil.assert_not_nil(profile.states["op:op1#final"], "final state exists")
  TestUtil.assert_equal(profile.states["op:op1#final"].type, "final", "final state typed")

  -- Action descriptor shape matches the executor's `core` action.
  local enter1 = profile.states["op:op1#1"].onEnter
  TestUtil.assert_equal(#enter1, 1, "one onEnter action")
  TestUtil.assert_equal(enter1[1].type, "core", "onEnter action is 'core'")
  TestUtil.assert_equal(enter1[1].name, "KillCreature", "core action name is the action type")

  -- Transitions chain action -> action -> final on "advance".
  TestUtil.assert_equal(profile.states["op:op1#1"].transitions["advance"][1].target, "op:op1#2", "transitions to #2")
  TestUtil.assert_equal(profile.states["op:op1#2"].transitions["advance"][1].target, "op:op1#final", "transitions to final")

  -- Source mapping in _debug.
  TestUtil.assert_equal(profile._debug.states["op:op1#1"].operation, "op1", "source mapping records operation")
  TestUtil.assert_equal(profile._debug.states["op:op1#1"].actionIndex, 1, "source mapping records index")

  -- JSON serialization round-trips.
  local json_str, jerr = pass4:toJSON(res)
  TestUtil.assert_not_nil(json_str, "profile serializes to JSON (" .. tostring(jerr) .. ")")
  local JSON = require("lib/JSON")
  local dec_ok, decoded2 = pcall(function() return JSON.decode(json_str) end)
  TestUtil.assert_true(dec_ok, "JSON decodes back")
  TestUtil.assert_equal(decoded2.schemaVersion, "1.0.0", "decoded schema version matches")

  -- bindGuards converts literal true/false but preserves unknown guard strings.
  local bp = { states = { s1 = { transitions = { e = { { guard = "true" }, { guard = "player.avgDurability < 0.5" } } } } } }
  CompilerPass4.bindGuards(bp)
  TestUtil.assert_equal(bp.states.s1.transitions.e[1].guard_fn(), true, "literal true bound")
  TestUtil.assert_nil(bp.states.s1.transitions.e[2].guard_fn, "unknown guard left as string for runtime binder")

  -- ---- End-to-end pipeline: pass1 -> pass2 -> pass3 -> pass4 ----
  local pipe_ast = {
    project = { name = "pipe", variables = {} },
    operations = {
      kill_op = {
        name = "kill_op",
        actions = {
          raw_action("KillCreature", { creature_name = "Guard Maxwell", quest_id = 100 }),
        },
      },
    },
    blueprints = {},
  }

  local p1 = CompilerPass1.new()
  local r1 = p1:run(pipe_ast)
  TestUtil.assert_true(r1.ok, "pass1 resolves names in pipeline")

  local p2 = CompilerPass2.new(mock_qprovider())
  local r2 = p2:run(pipe_ast)
  TestUtil.assert_true(r2.ok, "pass2 inserts implied actions in pipeline")

  local p3 = CompilerPass3.new(mock_qprovider())
  local r3 = p3:run(pipe_ast)
  TestUtil.assert_true(r3.ok, "pass3 eliminates dead code in pipeline")

  local p4 = CompilerPass4.new()
  local r4 = p4:run(pipe_ast)
  TestUtil.assert_true(r4.ok, "pass4 emits profile in pipeline")

  -- The kill action resolved to id 1234 and the implied Loot (item 3456) became a state.
  local found_loot = false
  for _, state in pairs(r4.profile.states) do
    if state._debug and state._debug.actionType == "Loot" then
      found_loot = true
    end
  end
  TestUtil.assert_true(found_loot, "implied Loot action is present as a state after full pipeline")
end

return M
