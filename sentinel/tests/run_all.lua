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
    "tests/core/test_event_bus",
    "tests/core/test_blackboard",
    "tests/core/test_bt",
    "tests/runtime/test_sensor_hub",
    "tests/runtime/test_sensor_hub_battleground",
    "tests/runtime/test_nav_adapter",
    "tests/modules/combat/test_spell_catalog",
    "tests/modules/combat/test_spell_dispatcher",
    "tests/modules/combat/test_helper_call_shapes",
    "tests/modules/combat/test_retribution_tbc",
    "tests/modules/combat/test_seal_policy",
    "tests/modules/combat/test_swing_tracker",
    "tests/modules/combat/test_target_selector",
    "tests/modules/combat/test_module",
    "tests/modules/battleground/test_bg_detector",
    "tests/modules/battleground/test_module",
    "tests/modules/battleground/test_queue_manager",
    "tests/modules/battleground/test_leave_manager",
    "tests/modules/battleground/test_mount_manager",
    "tests/modules/battleground/test_ghost_manager",
    "tests/modules/battleground/test_objective_approach",
    "tests/modules/battleground/test_objective_tracker",
    "tests/modules/battleground/test_strategy_engine",
    "tests/modules/battleground/test_nav_controller",
    "tests/modules/battleground/test_nav_failures",
    "tests/modules/battleground/test_av",
    "tests/modules/battleground/test_wsg",
    "tests/modules/battleground/test_ab",
    "tests/modules/battleground/test_eots",
    "tests/modules/grind/test_zone_profile",
    "tests/modules/grind/test_target_filter",
    "tests/modules/grind/test_stuck_detector",
    "tests/modules/combat/profiles/mage/test_frost_conditions",
    "tests/modules/combat/profiles/mage/test_frost_actions",
}

local failures = 0
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

if failures > 0 then
    os.exit(1)
end
