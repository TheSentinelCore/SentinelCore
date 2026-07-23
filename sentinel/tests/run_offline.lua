-- sentinel/tests/run_offline.lua
-- Offline test harness with mock Sylvannas APIs (combat-only)
-- Usage: lua sentinel/tests/run_offline.lua

-- Mock Sylvannas global API (placeholder - Sylvannas uses core.* not _G.SentinelCore)
-- These are no longer used by runtime_action.lua which now uses core.quests.* and core.input.*
_G.SentinelCore = {
    -- Deprecated APIs - kept as stubs for backward compatibility
}

-- Mock core namespace (Sylvannas API compliant)
_G.core = {
    -- Sylvannas core.object_manager APIs
    object_manager = {
        get_local_player = function()
            return {
                is_valid = function() return true end,
                is_unit = function() return true end,
                is_dead = function() return false end,
                is_game_object = function() return false end,
                get_position = function() return { x = 0, y = 0, z = 0 } end,
                get_npc_id = function() return nil end,
                get_entry_id = function() return nil end,
                get_level = function() return 1 end,
                get_class = function() return "Warrior" end,
                get_race = function() return "Human" end,
                get_health = function() return 100 end,
            }
        end,
        get_all_objects = function() return {} end,
        get_object_from_guid = function(guid) return nil end,
        GetUnits = function() return {} end,
    },
    -- Sylvannas core.input APIs
    input = {
        interact_with_object = function(obj) return true end,
        use_item = function(item_id) return true end,
        release_spirit = function() return true end,
        resurrect_corpse = function() return true end,
        move_forward_start = function() return true end,
        move_forward_stop = function() return true end,
        strafe_left_start = function() return true end,
        strafe_left_stop = function() return true end,
        jump = function() return true end,
    },
    -- Sylvannas core.quests APIs
    quests = {
        is_quest_flagged_completed = function(quest_id) return false end,
        is_on_quest = function(quest_id) return false end,
        accept_quest = function() return true end,
        complete_quest = function() return true end,
        get_quest_reward = function(choice) return true end,
        get_num_quest_log_entries = function() return 0 end,
        get_quest_log_title = function(idx) return nil end,
        select_gossip_option = function(id) return true end,
    },
    -- Sylvannas core.inventory APIs
    inventory = {
        get_gold = function() return 0 end,
        get_items_in_bag = function(bag_id) return {} end,
        sell_greys = function() return true end,
        repair_all_items = function(use_guild) return true end,
    },
    -- Sylvannas core.time API (replaces forbidden GetTime)
    time = function() return os.clock() end,
    game_time = function() return os.clock() * 1000 end,
    geometry = {
        distance = function(p1, p2)
            if not p1 or not p2 then return math.huge end
            return math.sqrt((p2.x-p1.x)^2 + (p2.y-p1.y)^2 + (p2.z-p1.z)^2)
        end,
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
}

-- Mock JSON module — a real, round-trippable JSON encoder/decoder pair.
-- `stringify(x)` emits valid JSON; `parse(stringify(x))` must reproduce `x`
-- for the table/array/string/number/boolean/nested shapes used by
-- runtime_profile.lua's persistence save/load (RE9).
_G.JSON = {}

local function json_escape(str)
    return (str:gsub('[%z\1-\31"\\]', function(c)
        if c == '"' then return '\\"'
        elseif c == "\\" then return "\\\\"
        elseif c == "\n" then return "\\n"
        elseif c == "\r" then return "\\r"
        elseif c == "\t" then return "\\t"
        else return string.format("\\u%04x", string.byte(c))
        end
    end))
end

local function json_encode_value(val)
    local t = type(val)
    if t == "string" then
        return '"' .. json_escape(val) .. '"'
    elseif t == "number" then
        return tostring(val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "nil" then
        return "null"
    elseif t == "table" then
        local is_array = true
        local max_key = 0
        local count = 0
        for k in pairs(val) do
            count = count + 1
            if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
                is_array = false
            elseif k > max_key then
                max_key = k
            end
        end
        if is_array and max_key == count then
            local parts = {}
            for i = 1, max_key do
                parts[i] = json_encode_value(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, '"' .. json_escape(tostring(k)) .. '":' .. json_encode_value(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function json_skip_ws(str, pos)
    local _, e = str:find("^%s*", pos)
    return e + 1
end

local function json_decode_string(str, pos)
    -- `pos` points at the opening quote.
    pos = pos + 1
    local parts = {}
    while true do
        local c = str:sub(pos, pos)
        if c == "" then
            error("Unterminated JSON string")
        elseif c == '"' then
            return table.concat(parts), pos + 1
        elseif c == "\\" then
            local nc = str:sub(pos + 1, pos + 1)
            if nc == "n" then parts[#parts + 1] = "\n"; pos = pos + 2
            elseif nc == "t" then parts[#parts + 1] = "\t"; pos = pos + 2
            elseif nc == "r" then parts[#parts + 1] = "\r"; pos = pos + 2
            elseif nc == '"' then parts[#parts + 1] = '"'; pos = pos + 2
            elseif nc == "\\" then parts[#parts + 1] = "\\"; pos = pos + 2
            elseif nc == "/" then parts[#parts + 1] = "/"; pos = pos + 2
            elseif nc == "u" then
                local hex = str:sub(pos + 2, pos + 5)
                parts[#parts + 1] = string.char(tonumber(hex, 16) % 256)
                pos = pos + 6
            else
                parts[#parts + 1] = nc; pos = pos + 2
            end
        else
            parts[#parts + 1] = c
            pos = pos + 1
        end
    end
end

local function json_decode_value(str, pos)
    pos = json_skip_ws(str, pos)
    local c = str:sub(pos, pos)
    if c == '"' then
        return json_decode_string(str, pos)
    elseif c == "{" then
        local obj = {}
        pos = json_skip_ws(str, pos + 1)
        if str:sub(pos, pos) == "}" then return obj, pos + 1 end
        while true do
            pos = json_skip_ws(str, pos)
            local key
            key, pos = json_decode_string(str, pos)
            pos = json_skip_ws(str, pos)
            assert(str:sub(pos, pos) == ":", "expected ':' in JSON object")
            pos = pos + 1
            local val
            val, pos = json_decode_value(str, pos)
            obj[key] = val
            pos = json_skip_ws(str, pos)
            local sep = str:sub(pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep == "}" then
                return obj, pos + 1
            else
                error("expected ',' or '}' in JSON object")
            end
        end
    elseif c == "[" then
        local arr = {}
        pos = json_skip_ws(str, pos + 1)
        if str:sub(pos, pos) == "]" then return arr, pos + 1 end
        local i = 0
        while true do
            local val
            val, pos = json_decode_value(str, pos)
            i = i + 1
            arr[i] = val
            pos = json_skip_ws(str, pos)
            local sep = str:sub(pos, pos)
            if sep == "," then
                pos = pos + 1
            elseif sep == "]" then
                return arr, pos + 1
            else
                error("expected ',' or ']' in JSON array")
            end
        end
    elseif c:match("[%-%d]") then
        local _, e, num = str:find("^(%-?%d+%.?%d*[eE]?[%-%+]?%d*)", pos)
        return tonumber(num), e + 1
    elseif str:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif str:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif str:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    else
        error("Unexpected JSON token at position " .. pos .. ": " .. str:sub(pos, pos + 10))
    end
end

-- Back the harness JSON with the SHIPPED parser (core/JSON) rather than the local encoder above.
-- The runtime uses core/JSON in-game (the Sylvannas sandbox has no global JSON), so a separate
-- harness implementation meant tests exercised a parser production never runs — which is exactly
-- how the "runtime cannot load any profile in-game" bug stayed invisible. One implementation,
-- exercised by both. The local json_* helpers remain as the fallback if core/JSON is unavailable.
-- Resolved lazily: this block runs BEFORE package.path is configured below, so an eager
-- require would silently fail and leave the harness on its own encoder — reintroducing the very
-- test/production split this is meant to remove.
local CoreJson, core_json_checked = nil, false
local function core_json()
    if not core_json_checked then
        core_json_checked = true
        local ok, mod = pcall(require, "core/JSON")
        if ok and type(mod) == "table" and mod.decode and mod.encode then CoreJson = mod end
    end
    return CoreJson
end

_G.JSON.stringify = function(tbl)
    local J = core_json()
    if J then
        local ok, str = pcall(J.encode, tbl)
        if ok and str then return str end
    end
    return json_encode_value(tbl)
end

_G.JSON.parse = function(str)
    if type(str) ~= "string" then return nil end
    local J = core_json()
    if J then
        local ok, result = pcall(J.decode, str)
        if ok then return result end
        return nil
    end
    local ok, result = pcall(json_decode_value, str, 1)
    if ok then return result end
    return nil
end

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

-- Run test modules (combat + core + infrastructure + questing)
local test_modules = {
    -- Harness (offline-only; exercises _G.JSON mocked above)
    "tests/harness/test_json_mock",

    -- Entry point (main.lua diagnostics sink, C4)
    "tests/test_main_diagnostics",

    -- Core
    "tests/core/test_event_bus",
    "tests/core/test_blackboard",
    "tests/core/test_bt",
    "tests/core/test_geometry",

    -- Infrastructure (runtime sensors, nav, module registry)
    "tests/runtime/test_sensor_hub",
    "tests/runtime/test_nav_adapter",
    "tests/runtime/test_module_registry",
    "tests/runtime/test_tick_isolation",
    "tests/runtime/test_app_tick",

    -- Combat module
    "tests/modules/combat/test_spell_catalog",
    "tests/modules/combat/test_spell_dispatcher",
    "tests/modules/combat/test_target_selector",
    "tests/modules/combat/test_module",
    "tests/modules/combat/test_helper_call_shapes",
    "tests/modules/combat/test_seal_policy",
    "tests/modules/combat/test_seal_availability",
    "tests/modules/combat/test_swing_tracker",
    "tests/modules/combat/test_combat_zone_detector",
    "tests/modules/combat/test_pvp_target_selector",
    "tests/modules/combat/test_retribution_tbc",
    "tests/modules/combat/test_context_builder_distance",

    -- Combat profiles
    "tests/modules/combat/profiles/mage/test_frost_conditions",
    "tests/modules/combat/profiles/mage/test_frost_actions",
    "tests/modules/combat/profiles/mage/test_maintenance_tree",
    "tests/modules/combat/profiles/mage/test_aoe_tree",
    "tests/modules/combat/profiles/mage/test_frost_tbc",
    "tests/modules/combat/profiles/mage/test_pet_controller",

    -- Questing module
    "tests/modules/questing/test_runtime_action",
    "tests/modules/questing/test_runtime_profile",
    "tests/modules/questing/test_runner_state",
    "tests/modules/questing/test_module_control",
    "tests/modules/questing/test_runtime_persistence",
    "tests/modules/questing/test_runtime_nav",
    "tests/modules/questing/test_runtime_arch_polish",
    "tests/modules/questing/test_quest_objectives",
    "tests/modules/questing/test_kill_pursuit",

    -- Shared libs
    "tests/shared/test_compat",
    "tests/shared/test_humanization",
    "tests/shared/test_class_names",
    "tests/shared/test_aoe_helper",

    -- Integration
    "tests/integration/test_combat_dummy",
}

local passed = 0
local failed = 0
local errors = {}

for _, mod_name in ipairs(test_modules) do
    local ok, result = pcall(function()
        local test_suite = require(mod_name)

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
