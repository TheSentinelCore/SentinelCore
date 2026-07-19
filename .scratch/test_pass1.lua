-- Test script for source_ast and compiler_pass1
-- Run with: luajit test_source_ast.lua

package.path = package.path .. ";/home/levi/Projects/SentinelCore/sentinel/modules/quest/?.lua;" ..
               ";/home/levi/Projects/SentinelCore/?.lua"

local SourceAST = require("sentinel.modules.quest.source_ast")
local CompilerPass1 = require("sentinel.modules.quest.compiler_pass1")

local project_dir = "/home/levi/Projects/SentinelCore/sentinel/data/profiles/quests/example_project"

print("Parsing project in:", project_dir)
local parse_result = SourceAST:parse_project(project_dir)

if not parse_result.ok then
  print("FAILED: Parsing failed with errors:")
  for _, err in ipairs(parse_result.errors) do
    print("  -", err)
  end
  os.exit(1)
end

print("SUCCESS: Parsed project without errors")
print("Project name:", parse_result.ast.project.name)

-- Count operations and blueprints
local op_count = 0
for _ in pairs(parse_result.ast.operations) do op_count = op_count + 1 end
local bp_count = 0
for _ in pairs(parse_result.ast.blueprints) do bp_count = bp_count + 1 end
print("Number of operations:", op_count)
print("Number of blueprints:", bp_count)

-- Run the Compiler Pass 1
print("\nRunning Compiler Pass 1 (DB Resolution)...")
local pass1 = CompilerPass1.new()
local pass1_result = pass1:run(parse_result.ast)

if not pass1_result.ok then
  print("FAILED: Pass 1 failed with errors:")
  for _, err in ipairs(pass1_result.errors) do
    print("  -", err)
  end
  os.exit(1)
end

print("SUCCESS: Pass 1 completed without errors")

-- Inspect the operations to see if resolution worked
for op_name, op in pairs(pass1_result.ast.operations) do
  print("\nOperation:", op_name)
  for i, action in ipairs(op.actions) do
    print("  Action", i, "type:", action.action_type)
    if action.action_type == "TalkToNPC" then
      print("    Args:")
      for k, v in pairs(action.args) do
        print("      ", k, "=", v)
      end
      -- Check if we have the resolved ID and data
      if action.args.npc_id then
        print("    Resolved NPC ID:", action.args.npc_id)
        if action.args.npc_data then
          print("    NPC Data: name=", action.args.npc_data.name, "zone_id=", action.args.npc_data.zone_id)
        end
      end
    end
  end
end

print("\nDone.")