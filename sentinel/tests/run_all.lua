package.path = table.concat({
    "sentinel/?.lua",
    "sentinel/?/?.lua",
    "sentinel/?/?/?.lua",
    "sentinel/?/?/?/?.lua",
    "sentinel/?/?/?/?/?.lua",
    package.path,
}, ";")

local TestUtil = require("tests/test_util")

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
    "tests/runtime/test_action_executor",
    "tests/runtime/test_runtime_action_executor",
    "tests/runtime/test_runtime_engine",
    "tests/runtime/test_runtime_context",
    "tests/runtime/test_module_registry",
    "tests/runtime/test_operation_manager",

    -- Combat module
    "tests/modules/combat/test_spell_catalog",
    "tests/modules/combat/test_spell_dispatcher",
    "tests/modules/combat/test_helper_call_shapes",
    "tests/modules/combat/test_seal_policy",
    "tests/modules/combat/test_swing_tracker",
    "tests/modules/combat/test_target_selector",
    "tests/modules/combat/test_module",

    -- Combat profiles (mage)
    "tests/modules/combat/profiles/mage/test_frost_conditions",
    "tests/modules/combat/profiles/mage/test_frost_actions",
    "tests/modules/combat/profiles/mage/test_maintenance_tree",
    "tests/modules/combat/profiles/mage/test_aoe_tree",
    "tests/modules/combat/profiles/mage/test_frost_tbc",
    "tests/modules/combat/profiles/mage/test_pet_controller",

    -- Shared
    "tests/shared/test_compat",
    "tests/shared/test_izi_bridge",
    "tests/shared/test_humanization",

    -- Operation module (Phase 5)
    "tests/modules/operation/test_goal_coverage",
    "tests/modules/operation/test_condition_evaluator",
    "tests/modules/operation/test_dependency_graph",
    "tests/modules/operation/test_cycle_detector",
    "tests/modules/operation/test_topological_sort",
    "tests/modules/operation/test_operation_lifecycle",
    "tests/modules/operation/test_sub_operation_composer",

    -- Integration
    "tests/integration/test_combat_dummy",

    -- Bridge traits (SENT-7.1 through SENT-7.7)
    "tests/integrations/test_bridge_traits",
}

local failures = 0

local function run_retribution_parity()
    local mod = require("tests/modules/combat/test_retribution_tbc")
    local result = TestUtil.run("tests/modules/combat/test_retribution_tbc.legacy", mod.test_legacy_path)
    if result.ok then
        print("PASS " .. result.name)
    else
        return "FAIL " .. result.name .. " :: " .. tostring(result.err)
    end
    local result2 = TestUtil.run("tests/modules/combat/test_retribution_tbc.dsl", mod.test_dsl_path)
    if result2.ok then
        print("PASS " .. result2.name)
    else
        return "FAIL " .. result2.name .. " :: " .. tostring(result2.err)
    end
    return nil
end

for _, module_name in ipairs(test_modules) do
    local mod = require(module_name)
    local result = TestUtil.run(module_name, mod.run)
    if result.ok then
        print("PASS " .. result.name)
    else
        failures = failures + 1
        print("FAIL " .. result.name .. " :: " .. tostring(result.err))
    end
end

local err = run_retribution_parity()
if err then
    failures = failures + 1
    print(err)
end

if failures > 0 then
    return "FAILED " .. failures .. " tests"
end

print("\n=== ALL TESTS PASSED ===")