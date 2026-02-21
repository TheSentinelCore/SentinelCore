local T = require("tests/TestUtil")

local function run()
    local env = T.install_core_stub()

    local Persistence = require("core/Persistence")
    local Config = require("core/Config")
    local ErrorCodes = require("events/ErrorCodes")

    local p = Persistence:new("SentinelCore")
    local paths = p:get_paths()

    -- Unknown schema must fail closed.
    env.fs[paths.runtime_state] = [[{"schema_version":"runtime_state.v0"}]]
    local state, err = p:load_runtime_state()
    T.assert_true(state == nil, "runtime_state with unknown schema should fail")
    T.assert_eq(err, ErrorCodes.CONFIG_SCHEMA_VERSION_INVALID, "wrong schema error code")

    -- Valid config load/save path.
    env.fs[paths.runtime_state] = ""
    local cfg = Config:new({}, p)
    local ok, load_err = cfg:load_persistence()
    T.assert_true(ok == true, "config persistence load failed: " .. tostring(load_err))

    local policy = cfg:get_policy()
    T.assert_eq(policy.min_free_slots, 2, "default min_free_slots mismatch")

    local profiles = cfg:list_profiles()
    T.assert_true(#profiles >= 1, "default profile should be created")
    T.assert_eq(cfg:get_active_profile_id(), profiles[1].profile_id, "default active profile mismatch")

    cfg:set_runtime_value("vendor", "search_radius", 333)
    local save_profile_ok, save_profile_err = cfg:save_as_profile("test_profile", "Test Profile")
    T.assert_true(save_profile_ok == true, "save_as_profile failed: " .. tostring(save_profile_err))
    local save_profiles_ok, save_profiles_err = cfg:save_profiles()
    T.assert_true(save_profiles_ok == true, "save_profiles failed: " .. tostring(save_profiles_err))

    local set_active_ok, set_active_err = cfg:set_active_profile("test_profile")
    T.assert_true(set_active_ok == true, "set_active_profile failed: " .. tostring(set_active_err))
    local runtime = cfg:get_runtime()
    T.assert_eq(runtime.vendor.search_radius, 333, "profile runtime overrides not applied")

    local rename_ok, rename_err = cfg:rename_profile("test_profile", "Renamed Profile")
    T.assert_true(rename_ok == true, "rename_profile failed: " .. tostring(rename_err))
    local listed = cfg:list_profiles()
    local renamed = nil
    for i = 1, #listed do
        if listed[i].profile_id == "test_profile" then
            renamed = listed[i]
            break
        end
    end
    T.assert_true(renamed ~= nil and renamed.name == "Renamed Profile", "profile rename not reflected")

    -- Stricter runtime rotation policy validation should fail closed.
    local invalid_runtime = cfg:get_runtime()
    invalid_runtime.rotation.paladin.retribution.health_potion_hp_pct = 1.25
    local set_runtime_ok, set_runtime_err = cfg:set_runtime_value("rotation", "paladin", invalid_runtime.rotation.paladin)
    T.assert_true(set_runtime_ok == false, "invalid runtime update should be rejected")
    T.assert_eq(set_runtime_err, ErrorCodes.CONFIG_INVALID, "invalid runtime update should return CONFIG_INVALID")

    -- set_active_profile should reject invalid runtime profile payloads.
    cfg._profiles.profiles[#cfg._profiles.profiles + 1] = {
        profile_id = "bad_profile",
        name = "Bad Profile",
        runtime = {
            rotation = {
                paladin = {
                    retribution = {
                        drink_mana_pct = 0.45,
                        eat_health_pct = 0.80,
                        loh_hp_pct = 0.10,
                        divine_shield_hp_pct = 0.20,
                        divine_protection_hp_pct = 0.35,
                        holy_light_hp_pct = 0.35,
                        holy_light_min_mana_pct = 0.25,
                        flash_light_hp_pct = 0.60,
                        heal_low_mana_threshold = 0.20,
                        heal_critical_mana_threshold = 0.30, -- invalid: critical > low threshold
                        health_potion_hp_pct = 0.30,
                        mana_potion_mana_pct = 0.15,
                        mana_potion_min_hp_pct = 0.35,
                        consecration_st_min_mana_pct = 0.35,
                        consecration_aoe_min_mana_pct = 0.45,
                        holy_wrath_aoe_min_mana_pct = 0.30,
                    },
                },
            },
        },
        policy = cfg:get_policy(),
        updated_at_unix = 0,
    }
    local active_before = cfg:get_active_profile_id()
    local activate_ok, activate_err = cfg:set_active_profile("bad_profile")
    T.assert_true(activate_ok == false, "activating invalid profile should fail")
    T.assert_eq(activate_err, ErrorCodes.CONFIG_INVALID, "invalid profile should return CONFIG_INVALID")
    T.assert_eq(cfg:get_active_profile_id(), active_before, "active profile should remain unchanged on invalid activation")

    -- Vendor cache startup prune should keep only non-expired blacklist entries.
    env.fs[paths.vendor_cache] = [[
{"schema_version":"vendor_runtime_cache.v1","entries":[
{"vendor_id":1,"canonical_map_id":530,"last_result":"move_failed","failure_count":1,"blacklist_until_unix":900,"last_path_cost":10,"last_seen_unix":100},
{"vendor_id":2,"canonical_map_id":530,"last_result":"move_failed","failure_count":1,"blacklist_until_unix":5000,"last_path_cost":8,"last_seen_unix":200}
],"updated_at_unix":1000}
]]
    local cache, cache_err = p:load_vendor_cache()
    T.assert_true(cache ~= nil, "load_vendor_cache failed: " .. tostring(cache_err))
    T.assert_eq(#cache.entries, 1, "vendor cache prune should drop expired entries")
    T.assert_eq(cache.entries[1].vendor_id, 2, "vendor cache prune kept wrong entry")

    -- Monotonic timestamp guard should fail writes older than on-disk timestamp.
    env.fs[paths.policy] = [[
{"schema_version":"vendor_inventory_policy.v1","updated_at_unix":2000,"min_free_slots":2,"sell_quality_max":1,"repair_enabled":true,"sell_gray":true,"sell_white":false,"sell_green":false,"never_sell":[],"always_sell":[],"keep_stack_min":{},"special_rules":[]}
]]
    local save_policy_ok, save_policy_err = cfg:save_policy()
    T.assert_true(save_policy_ok == false, "save_policy should fail monotonic guard")
    T.assert_eq(save_policy_err, ErrorCodes.POLICY_IO_ERROR, "monotonic guard should return policy io error")

    return {
        sc003_schema_validation = true,
        sc003_atomic_write_path = true,
        sc003_profiles = true,
    }
end

return { run = run }
