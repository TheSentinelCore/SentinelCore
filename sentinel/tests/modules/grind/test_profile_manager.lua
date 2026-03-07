local T = require("tests/test_util")
local JSON = require("lib/JSON")

local M = {}

function M.run()
    -- Setup mock core
    local _mock_files = {}
    local _mock_dir = {}

    local _orig_core = core
    core = {
        read_dir = function(dir) return _mock_dir[dir] end,
        read_data_file = function(path) return _mock_files[path] end,
        write_data_file = function(path, data) _mock_files[path] = data end,
        create_data_folder = function() end,
        create_data_file = function() end,
        log = function() end,
        log_error = function() end,
    }

    -- Force re-require with mocked core
    package.loaded["modules/grind/profile_manager"] = nil
    package.loaded["modules/grind/profile_validator"] = nil
    package.loaded["modules/grind/autoloader"] = nil
    local ProfileManager = require("modules/grind/profile_manager")

    local function make_mock_blackboard()
        local store = {}
        return {
            get = function(self, key, default)
                local v = store[key]
                if v == nil then return default end
                return v
            end,
            set = function(self, key, value)
                store[key] = value
            end,
            has = function(self, key) return store[key] ~= nil end,
            clear = function(self, key) store[key] = nil end,
            _store = store,
        }
    end

    local function make_mock_event_bus()
        local events = {}
        return {
            publish = function(self, name, data)
                events[#events + 1] = { name = name, data = data }
            end,
            _events = events,
        }
    end

    -- Prepare valid profile JSON
    local valid_profile = {
        schema_version = "2.0",
        metadata = { name = "Test" },
        requirements = { map_id = 1 },
        hotspots = {
            { id = "a", x = 0, y = 0, z = 0, radius = 50 },
            { id = "b", x = 100, y = 0, z = 0, radius = 50 },
        },
        options = { loop = true, dry_spell_secs = 15 },
    }
    _mock_files["sentinel/grinding_profiles/test.json"] = JSON:encode(valid_profile)
    _mock_dir["sentinel/grinding_profiles"] = { "test.json" }

    -- load_profile() with valid profile -> is_profile_loaded() true
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        local ok = pm:load_profile("test.json")
        T.assert_true(ok, "load_profile should return true for valid profile")
        T.assert_true(pm:is_profile_loaded(), "is_profile_loaded should be true after load")
    end

    -- load_profile() with invalid JSON -> returns false
    do
        _mock_files["sentinel/grinding_profiles/bad.json"] = "not json{{"
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        local ok = pm:load_profile("bad.json")
        T.assert_false(ok, "load_profile should return false for invalid JSON")
    end

    -- load_profile() sets module.grind.current_spot on blackboard
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        T.assert_true(bb:has("module.grind.current_spot"), "blackboard should have current_spot after load")
        local spot = bb:get("module.grind.current_spot")
        T.assert_not_nil(spot, "current_spot should be non-nil")
        T.assert_not_nil(spot.center, "current_spot should have a center")
    end

    -- load_profile() sets module.grind.profile_active = true
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        T.assert_equal(bb:get("module.grind.profile_active"), true, "profile_active should be true after load")
    end

    -- unload_profile() clears blackboard keys
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        T.assert_true(bb:has("module.grind.current_spot"), "current_spot should exist before unload")
        pm:unload_profile()
        T.assert_false(bb:has("module.grind.current_spot"), "current_spot should be cleared after unload")
        T.assert_false(bb:has("module.grind.profile_active"), "profile_active should be cleared after unload")
        T.assert_false(bb:has("module.grind.profile_name"), "profile_name should be cleared after unload")
    end

    -- scan_profiles() returns entries for files in mock directory
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        local entries = pm:scan_profiles()
        T.assert_equal(#entries, 1, "scan_profiles should return 1 entry")
        T.assert_equal(entries[1].filename, "test.json", "scan entry should have correct filename")
        T.assert_equal(entries[1].name, "Test", "scan entry should have correct name")
    end

    -- get_current_hotspot() returns first hotspot after load
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        local hs = pm:get_current_hotspot()
        T.assert_not_nil(hs, "get_current_hotspot should return non-nil after load")
        T.assert_equal(hs.id, "a", "first hotspot should be 'a'")
    end

    -- advance_hotspot() moves to next hotspot
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        local next_hs = pm:advance_hotspot("manual")
        T.assert_not_nil(next_hs, "advance_hotspot should return next hotspot")
        T.assert_equal(next_hs.id, "b", "advance should move to hotspot 'b'")
        T.assert_equal(pm:get_current_hotspot_index(), 2, "hotspot index should be 2")
    end

    -- advance_hotspot() wraps to 1 when loop=true
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("test.json")
        pm:advance_hotspot("manual")  -- -> hotspot 2
        local wrapped = pm:advance_hotspot("manual")  -- -> should wrap to 1
        T.assert_not_nil(wrapped, "advance should wrap when loop=true")
        T.assert_equal(wrapped.id, "a", "should wrap back to hotspot 'a'")
        T.assert_equal(pm:get_current_hotspot_index(), 1, "hotspot index should be 1 after wrap")
    end

    -- get_merged_filters() merges target_defaults with overrides
    do
        local profile_with_defaults = {
            schema_version = "2.0",
            metadata = { name = "Merged" },
            requirements = { map_id = 1 },
            target_defaults = {
                level_min = 10,
                level_max = 30,
                creature_types = { 1, 7 },
            },
            hotspots = {
                { id = "h1", x = 0, y = 0, z = 0, target_overrides = { level_min = 15 } },
            },
        }
        _mock_files["sentinel/grinding_profiles/merged.json"] = JSON:encode(profile_with_defaults)

        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("merged.json")

        local hs = pm:get_current_hotspot()
        local filters = pm:get_merged_filters(hs)
        T.assert_equal(filters.level_min, 15, "override level_min should be 15")
        T.assert_equal(filters.level_max, 30, "default level_max should carry through as 30")
    end

    -- save_profile() writes JSON to mock files
    do
        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        local new_profile = {
            schema_version = "2.0",
            metadata = { name = "Saved" },
            requirements = { map_id = 530 },
            hotspots = {
                { id = "s1", x = 10, y = 20, z = 0 },
            },
        }
        local ok = pm:save_profile(new_profile, "saved.json")
        T.assert_true(ok, "save_profile should return true")
        T.assert_not_nil(_mock_files["sentinel/grinding_profiles/saved.json"], "file should be written")
    end

    -- is_in_blackspot() returns true when position is inside blackspot
    do
        local profile_with_bs = {
            schema_version = "2.0",
            metadata = { name = "BS Test" },
            requirements = { map_id = 1 },
            hotspots = {
                { id = "h1", x = 0, y = 0, z = 0 },
            },
            blackspots = {
                { x = 50, y = 50, z = 0, radius = 10 },
            },
        }
        _mock_files["sentinel/grinding_profiles/bs.json"] = JSON:encode(profile_with_bs)

        local bb = make_mock_blackboard()
        local bus = make_mock_event_bus()
        local pm = ProfileManager:new(bus, bb)
        pm:load_profile("bs.json")

        local inside = pm:is_in_blackspot({ x = 52, y = 50, z = 0 })
        T.assert_true(inside, "position inside blackspot should return true")

        local outside = pm:is_in_blackspot({ x = 200, y = 200, z = 0 })
        T.assert_false(outside, "position outside blackspot should return false")
    end

    -- Cleanup: restore core and clear module cache
    core = _orig_core
    package.loaded["modules/grind/profile_manager"] = nil
    package.loaded["modules/grind/profile_validator"] = nil
    package.loaded["modules/grind/autoloader"] = nil
end

return M
