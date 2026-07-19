-- sentinel/tests/runtime/test_storage_manager.lua
-- Tests for Phase 2 storage: per-operation files, atomic writes,
-- Tier1 <-> Tier2 resolution, and schema migration on load.

local T = require("tests/test_util")

local M = {}

---Build an in-memory file_io adapter (no real disk; no JSON dependency for storage logic).
---Stores raw content strings keyed by path, records rename calls for atomicity checks.
---NOTE: these are plain function values (invoked as adapter.read(path), not adapter:read),
---so the first parameter IS the path, not a self/table.
local function make_mem_adapter()
    local store = {}
    local rename_calls = 0
    local adapter = {
        _store = store,
        _rename_calls = function() return rename_calls end,
        _has = function(p) return store[p] ~= nil end,
        read = function(path)
            local v = store[path]
            if v == nil then return nil, "not found" end
            return v, nil
        end,
        write = function(path, content)
            store[path] = content
            return true, nil
        end,
        rename = function(src, dst)
            rename_calls = rename_calls + 1
            local v = store[src]
            if v == nil then return false, "src missing" end
            store[dst] = v
            store[src] = nil
            return true, nil
        end,
        mkdir = function() return true, nil end,
        list = function(dir)
            local out = {}
            for k in pairs(store) do
                if k:sub(1, #dir) == dir then table.insert(out, k) end
            end
            return out, nil
        end,
    }
    return adapter
end

---A minimal authoring profile with string-keyed params (lib/JSON drops numeric keys).
local function sample_profile()
    return {
        profile_id = "prof-abc",
        name = "Northshire Tutorial",
        author = "matt",
        schema_version = "1.0.0",
        operations = {
            {
                id = "op-1",
                name = "Grab Quest",
                actions = {
                    { id = "a1", action_type = "PickupQuest", params = { quest = "northshire-1" } },
                },
            },
            {
                id = "op-2",
                name = "Turn In",
                actions = {
                    { id = "a2", action_type = "TurnInQuest", params = { quest = "northshire-1" } },
                },
            },
        },
    }
end

function M.test_save_tier2_splits_into_op_files()
    print("Test: save_tier2 splits manifest + per-operation files")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    local ok, err = sm:save_tier2(sample_profile())
    T.assert_true(ok, "save_tier2 should succeed: " .. tostring(err))

    -- Manifest + 2 operation files must all exist.
    T.assert_true(adapter._has("sentinel/profiles/authoring/prof-abc.json"), "manifest missing")
    T.assert_true(adapter._has("sentinel/profiles/authoring/prof-abc/ops/op-1.json"), "op-1 missing")
    T.assert_true(adapter._has("sentinel/profiles/authoring/prof-abc/ops/op-2.json"), "op-2 missing")

    print("  PASS")
end

function M.test_load_tier2_reassembles_operations()
    print("Test: load_tier2 reassembles manifest + operations")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    local original = sample_profile()
    local ok = sm:save_tier2(original)
    T.assert_true(ok, "save_tier2 should succeed")

    local loaded, warns, err = sm:load_tier2("prof-abc")
    T.assert_not_nil(loaded, "load_tier2 should return a profile")
    T.assert_nil(err, "load_tier2 should not error")

    T.assert_equal(loaded.profile_id, "prof-abc", "profile_id preserved")
    T.assert_equal(#loaded.operations, 2, "two operations reassembled")
    T.assert_equal(loaded.operations[1].id, "op-1", "op-1 id preserved")
    T.assert_equal(loaded.operations[2].id, "op-2", "op-2 id preserved")

    -- String-keyed param survives the JSON round-trip.
    local p = loaded.operations[1].actions[1].params
    T.assert_equal(p.quest, "northshire-1", "string-keyed param preserved")

    print("  PASS")
end

function M.test_atomic_write_uses_rename()
    print("Test: atomic write performs temp-file + rename")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    sm:save_tier2(sample_profile())

    -- 1 manifest + 2 ops = 3 files, each written atomically (tmp -> rename).
    T.assert_true(adapter._rename_calls() >= 3, "expected >=3 rename calls, got " .. adapter._rename_calls())

    -- No .tmp siblings should remain.
    for path in pairs(adapter._store) do
        T.assert_false(path:sub(-4) == ".tmp", "stray temp file: " .. path)
    end

    print("  PASS")
end

function M.test_tier1_resolves_from_tier2_and_persists()
    print("Test: load_tier1 resolves from Tier2 via compiler and caches result")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    -- Only Tier2 is saved.
    local ok = sm:save_tier2(sample_profile())
    T.assert_true(ok, "save_tier2 should succeed")

    local compiled_calls = 0
    local compiler_fn = function(tier2)
        compiled_calls = compiled_calls + 1
        local rt = sm:_deep_copy(tier2)
        rt.compiled_at = "now"
        return rt, nil
    end

    local first, w1, e1 = sm:load_tier1("prof-abc", compiler_fn)
    T.assert_not_nil(first, "first load_tier1 should resolve")
    T.assert_nil(e1, "first load_tier1 should not error")
    T.assert_equal(first.compiled_at, "now", "compiler output used")
    T.assert_equal(compiled_calls, 1, "compiler called once on first load")

    -- Tier1 should now be persisted; second load without compiler reads the cache.
    T.assert_true(adapter._has("sentinel/profiles/compiled/prof-abc.json"), "tier1 persisted")

    local second, w2, e2 = sm:load_tier1("prof-abc", nil)
    T.assert_not_nil(second, "second load_tier1 should read cache")
    T.assert_equal(compiled_calls, 1, "compiler NOT recalled on cached load")
    T.assert_equal(second.compiled_at, "now", "cached tier1 retains compiled marker")

    print("  PASS")
end

function M.test_tier1_falls_back_to_tier2_without_compiler()
    print("Test: load_tier1 returns Tier2 as best-effort when no compiler")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    sm:save_tier2(sample_profile())

    local profile, warns, err = sm:load_tier1("prof-abc", nil)
    T.assert_not_nil(profile, "should return a profile")
    T.assert_nil(err, "should not error")
    T.assert_equal(profile.tier, "tier1", "best-effort tier1 tagged")

    print("  PASS")
end

function M.test_migration_on_load()
    print("Test: load_tier2 migrates old schema_version to latest")

    local adapter = make_mem_adapter()
    local StorageManager = require("runtime/storage_manager")
    local sm = StorageManager:new({ file_io = adapter })

    -- Save directly with an old schema_version (bypass save_tier2's manifest munging by
    -- writing the manifest content ourselves, mimicking an on-disk legacy profile).
    -- Use an empty operations list so no per-op files are required for this migration check.
    local legacy = sample_profile()
    legacy.schema_version = "0.0.0"
    legacy.operations = {}
    local JSON = require("lib/JSON")
    adapter._store["sentinel/profiles/authoring/prof-abc.json"] = JSON.encode(legacy, true)

    local loaded, warns, err = sm:load_tier2("prof-abc")
    T.assert_not_nil(loaded, "legacy load should succeed after migration")
    T.assert_nil(err, "legacy load should not error")
    T.assert_equal(loaded.schema_version, "1.0.0", "schema migrated to 1.0.0")
    T.assert_true(#warns > 0, "migration should emit warnings")

    print("  PASS")
end

function M.run()
    print("=== Storage Manager Tests (Phase 2 storage) ===")
    M.test_save_tier2_splits_into_op_files()
    M.test_load_tier2_reassembles_operations()
    M.test_atomic_write_uses_rename()
    M.test_tier1_resolves_from_tier2_and_persists()
    M.test_tier1_falls_back_to_tier2_without_compiler()
    M.test_migration_on_load()
    print("\n=== All Storage Manager Tests PASSED ===")
end

return M
