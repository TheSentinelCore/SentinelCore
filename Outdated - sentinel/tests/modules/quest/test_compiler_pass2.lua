-- sentinel/tests/modules/quest/test_compiler_pass2.lua
-- Tests for Compiler Pass 2: Implied Action Insertion (Ticket 005).
-- Uses a mock quest_data provider so the pass is deterministic offline.

local TestUtil = require("tests/test_util")
local CompilerPass2 = require("modules/quest/compiler_pass2")

local M = {}

-- A small provider that mimics the Mangos quest_template fields the pass reads.
local function mock_provider()
  local p = {
    _quests = {
      -- Quest 100: requires two items, normal turn-in (Method 0).
      [100] = {
        Method = 0,
        ReqItemId1 = 3456, ReqItemCount1 = 3,
        ReqItemId2 = 9012, ReqItemCount2 = 1,
      },
      -- Quest 101: auto-complete on accept (Method 1).
      [101] = { Method = 1 },
    },
  }
  function p:getQuest(id) return self._quests[id] end
  function p:getQuestNPCs(id, role)
    if id == 100 and role == "turnin" then
      return { { id = 5678, name = "Innkeeper Allison" } }
    end
    return nil
  end
  function p:getTravelTime(_, _, _) return 45 end
  return p
end

local function raw_action(atype, args)
  return { type = atype, args = args or {} }
end

function M.run()
  local pass = CompilerPass2.new(mock_provider())

  -- 1. KillCreature with a quest that requires items -> Loot actions inserted.
  local kill_op = {
    name = "kill",
    actions = {
      raw_action("KillCreature", { creature_name = "Guard Maxwell", creature_name_id = 1234, quest_id = 100 }),
    },
  }
  pass:process_operation(kill_op)
  -- Original action + 2 implied Loot (items 3456 x3, 9012 x1).
  TestUtil.assert_equal(#kill_op.actions, 3, "kill op should gain 2 loot actions")
  TestUtil.assert_equal(kill_op.actions[1].type, "KillCreature", "original action preserved first")
  TestUtil.assert_equal(kill_op.actions[2].type, "Loot", "second action is implied Loot")
  TestUtil.assert_equal(kill_op.actions[2].args.item_id, 3456, "loot item 3456")
  TestUtil.assert_equal(kill_op.actions[2].args.count, 3, "loot count 3")
  TestUtil.assert_equal(kill_op.actions[3].args.item_id, 9012, "loot item 9012")
  TestUtil.assert_equal(kill_op.actions[2]._debug.generated_by, "level2_implied", "marked as compiler-generated")

  -- 2. AcceptQuest with a non-auto-complete quest -> no TurnIn.
  local accept_op = {
    name = "accept",
    actions = { raw_action("AcceptQuest", { quest_id = 100 }) },
  }
  pass:process_operation(accept_op)
  TestUtil.assert_equal(#accept_op.actions, 1, "normal accept yields no implied TurnIn")

  -- 3. AcceptQuest with auto-complete quest (Method 1) -> TurnIn inserted.
  local auto_op = {
    name = "auto",
    actions = { raw_action("AcceptQuest", { quest_id = 101 }) },
  }
  pass:process_operation(auto_op)
  TestUtil.assert_equal(#auto_op.actions, 2, "auto-complete accept yields a TurnIn")
  TestUtil.assert_equal(auto_op.actions[2].type, "TurnIn", "implied TurnIn present")
  TestUtil.assert_equal(auto_op.actions[2].args.auto_complete, true, "turn-in flagged auto_complete")
  TestUtil.assert_equal(auto_op.actions[2]._debug.generated_by, "level2_implied", "turn-in marked generated")

  -- 4. Vendor -> Repair guarded by durability threshold.
  local vendor_op = {
    name = "vendor",
    actions = { raw_action("Vendor", { npc_name = "Innkeeper Allison" }) },
  }
  pass:process_operation(vendor_op)
  TestUtil.assert_equal(#vendor_op.actions, 2, "vendor yields a Repair")
  TestUtil.assert_equal(vendor_op.actions[2].type, "Repair", "implied Repair present")
  TestUtil.assert_true(
    vendor_op.actions[2].condition:find("avgDurability"),
    "Repair carries a durability guard condition"
  )

  -- 5. Travel by flight -> Wait inserted with looked-up duration.
  local travel_op = {
    name = "travel",
    actions = { raw_action("TravelTo", { method = "flight", from = {0,0,0}, to = {1,1,1} }) },
  }
  pass:process_operation(travel_op)
  TestUtil.assert_equal(#travel_op.actions, 2, "flight travel yields a Wait")
  TestUtil.assert_equal(travel_op.actions[2].type, "Wait", "implied Wait present")
  TestUtil.assert_equal(travel_op.actions[2].args.duration_s, 45, "travel wait uses looked-up duration")

  -- 6. Fish heuristic: loot_enabled but no loot present -> Fish inserted once.
  local fish_op = {
    name = "fish",
    loot_enabled = true,
    actions = { raw_action("TravelTo", { method = "walk" }) },
  }
  pass:process_operation(fish_op)
  local fish_count = 0
  for _, a in ipairs(fish_op.actions) do
    if (a.type or a.action_type) == "Fish" then fish_count = fish_count + 1 end
  end
  TestUtil.assert_equal(fish_count, 1, "exactly one Fish implied when loot enabled")

  -- 7. Duplication prevention: user already placed the Loot -> not duplicated.
  local dup_op = {
    name = "dup",
    actions = {
      raw_action("KillCreature", { quest_id = 100, creature_name_id = 1234 }),
      raw_action("Loot", { item_id = 3456, count = 3, quest_id = 100 }),
    },
  }
  pass:process_operation(dup_op)
  local loot_count = 0
  for _, a in ipairs(dup_op.actions) do
    if (a.type or a.action_type) == "Loot" and a.args.item_id == 3456 then
      loot_count = loot_count + 1
    end
  end
  TestUtil.assert_equal(loot_count, 1, "user-placed Loot is not duplicated")

  -- 8. Nil-safety: operation without an actions list must not crash.
  local broken = { name = "broken" }
  local ok, err = pcall(function() pass:process_operation(broken) end)
  TestUtil.assert_true(ok, "process_operation must not throw on missing actions list")
end

return M
