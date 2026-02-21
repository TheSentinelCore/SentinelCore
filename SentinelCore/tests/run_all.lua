local tests = {
    "tests/test_sc001_skeleton",
    "tests/test_sc002_core_systems",
    "tests/test_sc003_config_persistence",
    "tests/test_sc004_client_lifecycle",
    "tests/test_sc005_navigation_adapter",
    "tests/test_sc006_world_data_adapter",
    "tests/test_sc007_targeting_service",
    "tests/test_sc008_rotation_engine",
    "tests/test_sc009_combat_service",
    "tests/test_sc010_loot_service",
    "tests/test_sc011_inventory_service",
    "tests/test_sc012_vendor_service",
    "tests/test_sc013_recovery_and_grind",
    "tests/test_sc014_telemetry_and_smoke",
}

---@return table
local function create_test_spell_queue()
    local queue = {}
    local entries = {}

    function queue:queue_spell_target(spell_id, target, priority, owner, allow_movement)
        entries[#entries + 1] = {
            spell_id = spell_id,
            target = target,
            priority = priority,
            owner = owner,
            allow_movement = allow_movement,
        }
        return true
    end

    function queue:get_entries()
        return entries
    end

    return queue
end

---@return table
local function snapshot_globals()
    return {
        core = rawget(_G, "__SentinelCoreHostCore") or rawget(_G, "core"),
        SentinelNavClient = rawget(_G, "SentinelNavClient"),
        SentinelCore = rawget(_G, "SentinelCore"),
    }
end

---@param snapshot table
local function restore_globals(snapshot)
    rawset(_G, "core", snapshot.core)
    rawset(_G, "SentinelNavClient", snapshot.SentinelNavClient)
    rawset(_G, "SentinelCore", snapshot.SentinelCore)
end

---@return table<string, boolean>
local function snapshot_loaded_modules()
    local loaded = {}
    for name, _ in pairs(package.loaded) do
        loaded[name] = true
    end
    return loaded
end

---@param snapshot table<string, boolean>
local function unload_new_modules(snapshot)
    for name, _ in pairs(package.loaded) do
        if not snapshot[name] then
            package.loaded[name] = nil
        end
    end
end

local function run_all()
    local results = {}
    local passed = 0
    local failed = 0
    local suite_globals = snapshot_globals()
    local suite_modules = snapshot_loaded_modules()

    local function run_suite()
        for i = 1, #tests do
            local name = tests[i]
            local globals_before = snapshot_globals()
            local modules_before = snapshot_loaded_modules()
            local previous_spell_queue = package.loaded["common/modules/spell_queue"]
            package.loaded["common/modules/spell_queue"] = create_test_spell_queue()
            local ok, mod = pcall(require, name)
            if ok then
                local run_ok, run_result = pcall(mod.run)
                if run_ok then
                    results[name] = run_result
                    passed = passed + 1
                else
                    results[name] = { error = tostring(run_result) }
                    failed = failed + 1
                end
            else
                results[name] = { error = tostring(mod) }
                failed = failed + 1
            end
            package.loaded["common/modules/spell_queue"] = previous_spell_queue
            restore_globals(globals_before)
            unload_new_modules(modules_before)
        end

        local smoke_snapshot = snapshot_globals()
        local smoke_modules = snapshot_loaded_modules()
        local smoke_ok, smoke_mod = pcall(require, "tests/smoke_suite")
        if smoke_ok and smoke_mod and smoke_mod.run then
            local run_ok, run_result = pcall(smoke_mod.run)
            if run_ok then
                results["tests/smoke_suite"] = run_result
            else
                results["tests/smoke_suite"] = { error = tostring(run_result) }
            end
        end
        restore_globals(smoke_snapshot)
        unload_new_modules(smoke_modules)
    end

    local run_ok, run_err = pcall(run_suite)

    restore_globals(suite_globals)
    unload_new_modules(suite_modules)

    if not run_ok then
        failed = failed + 1
        results["tests/run_all"] = { error = tostring(run_err) }
    end

    if core and core.log then
        core.log(string.format("[SentinelCore Tests] passed=%d failed=%d", passed, failed))
    end

    return {
        passed = passed,
        failed = failed,
        results = results,
    }
end

return {
    run_all = run_all,
}
