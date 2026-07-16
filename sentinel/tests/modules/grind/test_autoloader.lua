local T = require("tests/test_util")
local JSON = require("lib/JSON")

local M = {}

function M.run()
    -- Setup mock core before requiring Autoloader
    local _mock_files = {}
    local _mock_dir = {}

    local _orig_core = core
    core = {
        read_dir = function(dir) return _mock_dir[dir] end,
        read_data_file = function(path) return _mock_files[path] end,
        write_data_file = function(path, data) _mock_files[path] = data end,
        create_data_folder = function() end,
        log = function() end,
    }

    -- Force re-require Autoloader with mocked core
    package.loaded["modules/grind/autoloader"] = nil
    local Autoloader = require("modules/grind/autoloader")

    -- Prepare a valid autoloader JSON
    local valid_autoloader = {
        schema_version = "1.0",
        name = "Test Autoloader",
        author = "UnitTest",
        entries = {
            { min_level = 1, max_level = 20, profile = "lowbie.json" },
            { min_level = 15, max_level = 40, profile = "mid.json" },
            { min_level = 41, max_level = 60, profile = "high.json" },
        },
    }
    local valid_json = JSON:encode(valid_autoloader)

    local invalid_autoloader = {
        schema_version = "9.9",
        name = "Bad Schema",
        entries = {
            { min_level = 1, max_level = 10, profile = "x.json" },
        },
    }
    local invalid_json = JSON:encode(invalid_autoloader)

    -- scan() returns empty table when directory is empty/nil
    do
        Autoloader.unload()
        _mock_dir["sentinel/autoloaders"] = nil
        local results = Autoloader.scan()
        T.assert_not_nil(results, "scan should return a table")
        T.assert_equal(#results, 0, "scan should return empty table for nil directory")
    end

    -- scan() returns entries for valid autoloader files
    do
        _mock_dir["sentinel/autoloaders"] = { "test.json", "readme.txt" }
        _mock_files["sentinel/autoloaders/test.json"] = valid_json
        local results = Autoloader.scan()
        T.assert_equal(#results, 1, "scan should return 1 entry for 1 .json file")
        T.assert_equal(results[1].filename, "test.json", "scan entry should have correct filename")
        T.assert_equal(results[1].name, "Test Autoloader", "scan entry should have correct name")
    end

    -- load() returns true for valid autoloader
    do
        Autoloader.unload()
        _mock_files["sentinel/autoloaders/valid.json"] = valid_json
        local ok = Autoloader.load("valid.json")
        T.assert_true(ok, "load should return true for valid autoloader")
    end

    -- load() returns false for invalid schema_version
    do
        Autoloader.unload()
        _mock_files["sentinel/autoloaders/bad.json"] = invalid_json
        local ok = Autoloader.load("bad.json")
        T.assert_false(ok, "load should return false for invalid schema_version")
    end

    -- resolve() returns correct profile for player level in range
    do
        Autoloader.unload()
        _mock_files["sentinel/autoloaders/valid.json"] = valid_json
        Autoloader.load("valid.json")
        local profile = Autoloader.resolve(10)
        T.assert_equal(profile, "lowbie.json", "resolve(10) should return lowbie.json")
    end

    -- resolve() returns nil when no entry matches
    do
        local profile = Autoloader.resolve(70)
        T.assert_true(profile == nil, "resolve(70) should return nil when no entry matches")
    end

    -- resolve() returns first match when ranges overlap
    do
        -- Level 15 matches both entry 1 (1-20) and entry 2 (15-40), first-match-wins
        local profile = Autoloader.resolve(15)
        T.assert_equal(profile, "lowbie.json", "resolve(15) should return first matching entry (lowbie.json)")
    end

    -- is_loaded() returns true after load, false after unload
    do
        Autoloader.unload()
        _mock_files["sentinel/autoloaders/valid.json"] = valid_json
        Autoloader.load("valid.json")
        T.assert_true(Autoloader.is_loaded(), "is_loaded should be true after load")
        Autoloader.unload()
        T.assert_false(Autoloader.is_loaded(), "is_loaded should be false after unload")
    end

    -- Cleanup: restore core and clear module cache
    core = _orig_core
    package.loaded["modules/grind/autoloader"] = nil
end

return M
