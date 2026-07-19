-- Test script for source_ast module
-- Run with: luajit test_source_ast.lua

-- Adjust the package path to include the sentinel directory
local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or ""
package.path = package.path .. ";"
    .. script_dir .. "../sentinel/?.lua;"
    .. script_dir .. "../sentinel/?/init.lua;"
    .. script_dir .. "../sentinel/modules/?.lua;"
    .. script_dir .. "../sentinel/modules/?/init.lua"

local SourceAST = require("sentinel.modules.quest.source_ast")

-- Change this to the path of your example project
local project_dir = "/home/levi/Projects/SentinelCore/sentinel/data/profiles/quests/example_project"

print("Parsing project in:", project_dir)
local result = SourceAST:parse_project(project_dir)

if result.ok then
    print("SUCCESS: Parsed project without errors")
    print("Project name:", result.ast.project.name)
    print("Number of operations:", #result.ast.operations)
    print("Number of blueprints:", #result.ast.blueprints)
else
    print("FAILED: Parsing failed with errors:")
    for i, err in ipairs(result.errors) do
        print(string.format("  %d. %s", i, err))
    end
    os.exit(1)
end