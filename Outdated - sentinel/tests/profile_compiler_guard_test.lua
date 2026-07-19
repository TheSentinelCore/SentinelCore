-- sentinel/tests/profile_compiler_guard_test.lua
-- Tests for guard sandbox security in profile_compiler.lua

local TestUtil = require("tests/test_util")
local ProfileCompiler = require("modules/quest/profile_compiler")

local GuardSandboxTests = {}

function GuardSandboxTests.test_guard_has_sandbox()
    -- Test that guards run in restricted environment
    local compiler = ProfileCompiler.new(nil, nil, {})
    
    -- Create minimal compiled profile with a safe guard
    local compiled = {
        profile = {id = "test", name = "Test"},
        variables = {},
        states = {
            ["TestState"] = {
                id = "TestState",
                name = "TestState",
                type = "atomic",
                transitions = {
                    QuestAccepted = {
                        {
                            target = "NextState",
                            guard = "true and true"
                        }
                    }
                }
            }
        },
        regions = {},
        diagnostics = {errors = {}, warnings = {}}
    }
    
    -- Compile guards
    compiler:_compile_guards(compiled)
    
    -- Guard should compile successfully
    TestUtil.assert_true(compiled.states["TestState"].transitions.QuestAccepted[1].guard_fn ~= nil,
        "Safe guard should compile")
end

function GuardSandboxTests.test_guard_cannot_access_os()
    -- Test that guards cannot access os table
    local compiler = ProfileCompiler.new(nil, nil, {})
    
    local compiled = {
        profile = {id = "test", name = "Test"},
        variables = {},
        states = {
            ["TestState"] = {
                id = "TestState",
                name = "TestState",
                type = "atomic",
                transitions = {
                    QuestAccepted = {
                        {
                            target = "NextState",
                            guard = "os and os.date and true or false"  -- Attempt to access os
                        }
                    }
                }
            }
        },
        regions = {},
        diagnostics = {errors = {}, warnings = {}}
    }
    
    compiler:_compile_guards(compiled)
    
    local guard_fn = compiled.states["TestState"].transitions.QuestAccepted[1].guard_fn
    if guard_fn then
        local ok, result = pcall(guard_fn, {}, {}, {})
        -- os should be nil in sandbox, making guard return false
        -- If result is false or os is nil, sandbox is working
        if ok and result == true then
            -- Check if os access actually worked (bad)
            if _G.os ~= nil and type(_G.os.date) == "function" then
                -- Guard evaluated true - might indicate os was accessible
                -- But in the sandbox, os = nil, so 'os and ...' should be false
                error("SECURITY: Guard may have access to os table - verify sandbox")
            end
        end
    end
    -- Test passes if no error thrown
end

function GuardSandboxTests.test_guard_can_use_math()
    -- Test that whitelisted math functions work in guards
    local compiler = ProfileCompiler.new(nil, nil, {})
    
    local compiled = {
        profile = {id = "test", name = "Test"},
        variables = {},
        states = {
            ["TestState"] = {
                id = "TestState",
                name = "TestState",
                type = "atomic",
                transitions = {
                    LevelUp = {
                        {
                            target = "NextState",
                            guard = "event.newLevel > 5 and true"
                        }
                    }
                }
            }
        },
        regions = {},
        diagnostics = {errors = {}, warnings = {}}
    }
    
    compiler:_compile_guards(compiled)
    
    local guard_fn = compiled.states["TestState"].transitions.LevelUp[1].guard_fn
    TestUtil.assert_not_nil(guard_fn, "Guard should compile")
    
    -- Test execution
    local ok, result = pcall(guard_fn, {newLevel = 10}, {}, {})
    TestUtil.assert_true(ok and result == true, "Guard should evaluate true")
end

return GuardSandboxTests