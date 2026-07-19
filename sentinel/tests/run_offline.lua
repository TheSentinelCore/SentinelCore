-- sentinel/tests/run_offline.lua
-- Offline test harness with mock Sylvannas APIs
-- Usage: lua sentinel/tests/run_offline.lua

-- Mock Sylvannas global API
_G.SentinelCore = {}

-- Mock core namespace
_G.core = {
    object_manager = {
        GetTarget = function() return nil end,
        GetTargetInfo = function() return {} end,
        GetFriends = function() return {} end,
        GetEnemies = function() return {} end,
        GetObjects = function() return {} end,
        GetUnits = function() return {} end,
        GetUnitById = function(id) return nil end,
        GetPlayer = function() return nil end,
        GetPlayerInfo = function() return { guid = "player-guid", name = "TestPlayer", race = "Human", class = "Warrior", level = 1, map = 0, x = 0, y = 0, z = 0 } end,
    },
    input = {
        interact = function() return true end,
        interact_unit = function(guid) return true end,
        move = function(x, y, z) return true end,
        stop_movement = function() return true end,
        face = function(x, y) return true end,
        jump = function() return true end,
    },
    quests = {
        is_quest_flagged_completed = function(quest_id) return false end,
    },
    flight_paths = {
        is_known = function(node_id) return false end,
    },
    player = {
        get_level = function() return 1 end,
    },
    spell = {
        cast = function(id, target) return true end,
        stop_casting = function() return true end,
        is_casting = function() return false end,
        get_cooldown = function(id) return 0 end,
        is_usable = function(id) return true end,
        get_spell_info = function(id) return { name = "Test Spell", rank = 1, cast_time = 0, range = 30 } end,
    },
    unit = {
        get_health = function(guid) return 100 end,
        get_max_health = function(guid) return 100 end,
        get_power = function(guid) return 50 end,
        get_max_power = function(guid) return 100 end,
        get_position = function(guid) return 0, 0, 0 end,
        get_facing = function(guid) return 0 end,
        is_in_combat = function(guid) return false end,
        is_dead = function(guid) return false end,
        is_in_range = function(guid, range) return true end,
        get_target = function(guid) return nil end,
    },
    geometry = {
        distance = function(x1, y1, z1, x2, y2, z2) return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2) end,
        distance_2d = function(x1, y1, x2, y2) return math.sqrt((x2-x1)^2 + (y2-y1)^2) end,
    },
    http_get = function(url)
        -- Mock HTTP responses
        if url:match("/health") then
            return '{"status":"ok"}'
        elseif url:match("/api/v1/quests/search") then
            return '{"results":[{"id":33,"title":"Wolves Across the Border","level":1,"zone":"Northshire"}]}'
        elseif url:match("/api/v1/quests/") then
            return '{"id":33,"title":"Wolves Across the Border","level":1,"zone":"Elwynn"}'
        elseif url:match("/api/v1/npcs/search") then
            return '{"results":[{"entry":197,"name":"Marshal McBride","zone":"Northshire"}]}'
        elseif url:match("/api/v1/npcs/") then
            return '{"entry":197,"name":"Marshal McBride","zone":"Northshire","position":{"x":-8912.5,"y":-132.3,"z":83.2}}'
        else
            return nil
        end
    end,
    event_bus = {
        on = function(event, callback) return function() end end,
        off = function(event, handler) end,
        send = function(event, ...) end,
        publish = function(event, ...) end,
    },
    -- Sylvannas utility
    GetTime = function() return os.clock() end,
    print = function(...) print(...) end,
}

-- Mock JSON module
_G.JSON = {
    parse = function(str)
        -- Simple JSON parse using loadstring for Lua tables
        -- In production this would use a real JSON parser
        local ok, result = pcall(function()
            return assert(loadstring("return " .. str))()
        end)
        if ok then return result end
        return nil
    end,
    stringify = function(tbl)
        -- Simple table to JSON string
        local function serialize(val, indent)
            local indent = indent or ""
            local t = type(val)
            if t == "string" then
                return string.format("%q", val)
            elseif t == "number" then
                return tostring(val)
            elseif t == "boolean" then
                return tostring(val)
            elseif t == "nil" then
                return "null"
            elseif t == "table" then
                local parts = {}
                local is_array = true
                local max_key = 0
                for k, v in pairs(val) do
                    if type(k) ~= "number" then is_array = false end
                    if type(k) == "number" and k > max_key then max_key = k end
                end
                if is_array and max_key == #val then
                    for i, v in ipairs(val) do
                        table.insert(parts, serialize(v, indent .. "  "))
                    end
                    return "[" .. table.concat(parts, ", ") .. "]"
                else
                    for k, v in pairs(val) do
                        table.insert(parts, string.format("%s%q: %s", indent .. "  ", k, serialize(v, indent .. "  ")))
                    end
                    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
                end
            end
            return tostring(val)
        end
        return serialize(tbl)
    end,
}

-- Mock core data file APIs
_G.core.read_data_file = function(path)
    return nil, "Mock: file not found"
end

_G.core.write_data_file = function(path, content)
    return true, nil
end

-- Set up package path for sentinel modules
package.path = table.concat({
    "sentinel/?.lua",
    "sentinel/?/?.lua",
    "sentinel/?/?/?.lua",
    "sentinel/?/?/?/?.lua",
    "sentinel/?/?/?/?/?.lua",
    package.path,
}, ";")

-- Run test modules
local test_modules = {
    -- Core
    "tests/core/test_event_bus",
    "tests/core/test_blackboard",
    "tests/core/test_bt",

    -- Runtime
    "tests/runtime/test_sensor_hub",
    "tests/runtime/test_nav_adapter",
    "tests/runtime/test_query_client",
    "tests/runtime/test_profile_manager",
    "tests/runtime/test_operation_scheduler",
    "tests/runtime/test_runtime_action_executor",
    "tests/runtime/test_runtime_engine",
    "tests/runtime/test_migration_registry",
    "tests/runtime/test_compiler_bridge",
    "tests/runtime/test_compile_pipeline",
    "tests/runtime/test_validation_service",
    "tests/runtime/test_validation_panel_wiring",
    "tests/runtime/test_variable_store",
    "tests/runtime/test_event_dispatcher",
    "tests/runtime/test_profile_state",
    "tests/runtime/test_dry_run",
    "tests/runtime/test_telemetry",
    "tests/runtime/test_command_history",
    "tests/runtime/test_compiler_stages",
    "tests/runtime/test_runtime_context",
    "tests/runtime/test_module_registry",
    "tests/runtime/test_stage_optimization",
    "tests/runtime/test_route_analysis",
    "tests/runtime/test_storage_manager",

    -- Combat module
    "tests/modules/combat/test_spell_catalog",
    "tests/modules/combat/test_spell_dispatcher",
    "tests/modules/combat/test_target_selector",
    -- Quest module (runtime execution)
    "tests/modules/quest/test_quest_module",
    "tests/modules/quest/test_goal_checking",
    "tests/modules/quest/test_sub_operations",
    -- UI module (IDE core)
    "tests/ui/test_window",
    "tests/ui/test_toolbar",
    "tests/ui/test_toolbar_undo_wiring",
    "tests/ui/test_explorer_panel",
    "tests/ui/test_inspector_panel",
    "tests/ui/test_timeline_panel",
    -- UI module (utility panels)
    "tests/ui/test_action_palette_panel",
    "tests/ui/test_variables_panel",
    "tests/ui/test_validation_panel",
    "tests/ui/test_console_panel",
    -- Operation module (Phase 5)
    "tests/modules/operation/test_all",
    -- Integrations (Phase 7)
    "tests/integrations/test_bridge_traits",
    -- E2E Integration Tests (SENT-6.12)
    "tests/integration/test_northshire_e2e",
}

local passed = 0
local failed = 0
local errors = {}

for _, mod_name in ipairs(test_modules) do
    local ok, result = pcall(function()
        local test_suite = require(mod_name)

        -- Support two patterns:
        --   1. Module has a `run()` function (legacy pattern)
        --   2. Module has individual `test*` functions (new pattern)
        if type(test_suite.run) == "function" then
            local run_ok, run_err = pcall(test_suite.run)
            if run_ok then
                passed = passed + 1
                io.write(".")
            else
                failed = failed + 1
                table.insert(errors, string.format("FAIL: %s.run: %s", mod_name, tostring(run_err)))
                io.write("F")
            end
        else
            -- Fallback: look for individual test functions
            local found = false
            for name, fn in pairs(test_suite) do
                if type(fn) == "function" and name:match("^test") then
                    found = true
                    local test_ok, test_err = pcall(fn)
                    if test_ok then
                        passed = passed + 1
                        io.write(".")
                    else
                        failed = failed + 1
                        table.insert(errors, string.format("FAIL: %s.%s: %s", mod_name, name, tostring(test_err)))
                        io.write("F")
                    end
                end
            end
            if not found then
                failed = failed + 1
                table.insert(errors, string.format("ERROR: %s has no run() or test* functions", mod_name))
                io.write("E")
            end
        end
    end)
    if not ok then
        failed = failed + 1
        table.insert(errors, string.format("ERROR loading %s: %s", mod_name, tostring(result)))
        io.write("E")
    end
end

print(string.format("\n\n%d passed, %d failed", passed, failed))
if failed > 0 then
    print("\nFailures:")
    for _, err in ipairs(errors) do
        print("  " .. err)
    end
    os.exit(1)
else
    os.exit(0)
end