-- Debug YAML parsing
package.path = package.path .. ";./sentinel/?.lua;./sentinel/modules/?.lua;./sentinel/modules/quest/?.lua"

local core = {
    read_file = function(path)
        local f = io.open(path, "r")
        if f then local c = f:read("*a"); f:close(); return c end
        return nil
    end,
}
_G.core = core

local ProfileCompiler = require("modules/quest/profile_compiler")

local yaml = core.read_file("sentinel/data/profiles/quests/test_profile.yaml")
print("=== Raw YAML ===")
print(yaml)

-- Access the private yaml_parse function
local compiler = ProfileCompiler.new(nil, nil, {})
print("\n=== Parsed AST ===")
-- Can't access local function, let's just check the test_profile directly

-- Let's use the parser in the compiler
local test_compiler = ProfileCompiler.new(nil, nil, {})
-- We need to test the parser directly - let's add a test function

print("\nDone")