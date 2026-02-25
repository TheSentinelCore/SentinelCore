-- Regression tests for zone config overrides and session-cap defaults.
--
-- Covers:
-- (1)  Defaults.zone_overrides is an empty table by default
-- (2)  Defaults.policy.max_session_minutes defaults to 240
-- (3)  Defaults.mount.min_level defaults to 40
-- (4)  Defaults.build_runtime() includes zone_overrides, mount, and logging keys
-- (5)  Config:get_zone_override() returns nil when zone_overrides is empty
-- (6)  Config:get_zone_override() matches by numeric zone_id
-- (7)  Config:get_zone_override() matches by string zone_id
-- (8)  Config:get_zone_override() returns nil for unmatched zone
-- (9)  Zone override set at build_runtime time is accessible via Config
-- (10) Defaults.logging.global_level defaults to "INFO"
-- (11) Config instance respects zone_overrides injected via overrides param

local TU = require("tests/TestUtil")

local M = {}

function M.run()
    local env = TU.install_core_stub()

    local Defaults = require("core/Defaults")
    local Config   = require("core/Config")

    -- -----------------------------------------------------------------------
    -- Test 1: Defaults.zone_overrides is an empty table
    -- -----------------------------------------------------------------------
    assert(type(Defaults.zone_overrides) == "table",
        "Test 1: Defaults.zone_overrides should be a table")
    local count = 0
    for _ in pairs(Defaults.zone_overrides) do count = count + 1 end
    assert(count == 0,
        "Test 1: Defaults.zone_overrides should be empty, got " .. count .. " entries")

    -- -----------------------------------------------------------------------
    -- Test 2: Defaults.policy.max_session_minutes defaults to 240
    -- -----------------------------------------------------------------------
    assert(Defaults.policy.max_session_minutes == 240,
        "Test 2: max_session_minutes should default to 240, got " ..
        tostring(Defaults.policy.max_session_minutes))

    -- -----------------------------------------------------------------------
    -- Test 3: Defaults.mount.min_level defaults to 40
    -- -----------------------------------------------------------------------
    assert(Defaults.mount ~= nil, "Test 3: Defaults.mount should exist")
    assert(Defaults.mount.min_level == 40,
        "Test 3: Defaults.mount.min_level should be 40, got " ..
        tostring(Defaults.mount.min_level))

    -- -----------------------------------------------------------------------
    -- Test 4: Defaults.build_runtime() includes zone_overrides, mount, logging
    -- -----------------------------------------------------------------------
    local rt = Defaults.build_runtime()
    assert(type(rt.zone_overrides) == "table",
        "Test 4: build_runtime should include zone_overrides table")
    assert(type(rt.mount) == "table",
        "Test 4: build_runtime should include mount table")
    assert(rt.mount.min_level == 40,
        "Test 4: build_runtime mount.min_level should be 40")
    assert(type(rt.logging) == "table",
        "Test 4: build_runtime should include logging table")

    -- -----------------------------------------------------------------------
    -- Test 5: Config:get_zone_override() returns nil for empty zone_overrides
    -- -----------------------------------------------------------------------
    local cfg_empty = Config:new()
    assert(cfg_empty:get_zone_override(530) == nil,
        "Test 5: get_zone_override should return nil when no overrides are set")
    assert(cfg_empty:get_zone_override("530") == nil,
        "Test 5 (str): get_zone_override should return nil when no overrides are set")

    -- -----------------------------------------------------------------------
    -- Test 6: Config:get_zone_override() matches by numeric zone_id
    -- -----------------------------------------------------------------------
    local zone_override_val = { targeting = { min_level = 55 } }
    local cfg_num = Config:new({
        zone_overrides = {
            [530] = zone_override_val,
        },
    })
    local result_num = cfg_num:get_zone_override(530)
    assert(type(result_num) == "table",
        "Test 6: expected table result for numeric zone_id=530")
    assert(result_num.targeting ~= nil,
        "Test 6: result should contain targeting subtable")
    assert(result_num.targeting.min_level == 55,
        "Test 6: targeting.min_level should be 55, got " ..
        tostring(result_num.targeting and result_num.targeting.min_level))

    -- -----------------------------------------------------------------------
    -- Test 7: Config:get_zone_override() matches by string zone_id
    -- -----------------------------------------------------------------------
    local cfg_str = Config:new({
        zone_overrides = {
            ["3518"] = { combat = { max_pull_range = 20 } },
        },
    })
    local result_str = cfg_str:get_zone_override("3518")
    assert(type(result_str) == "table",
        "Test 7: expected table result for string zone_id='3518'")
    assert(result_str.combat ~= nil,
        "Test 7: result should contain combat subtable")
    assert(result_str.combat.max_pull_range == 20,
        "Test 7: combat.max_pull_range should be 20")

    -- -----------------------------------------------------------------------
    -- Test 8: Config:get_zone_override() returns nil for unmatched zone
    -- -----------------------------------------------------------------------
    local result_miss = cfg_num:get_zone_override(999)
    assert(result_miss == nil,
        "Test 8: get_zone_override should return nil for non-matching zone_id=999")

    -- -----------------------------------------------------------------------
    -- Test 9: Numeric key stored as number is also found by numeric lookup
    -- -----------------------------------------------------------------------
    -- The internal implementation: overrides[id_num] or overrides[id_str]
    -- Test that passing numeric key and then querying with numeric ID works.
    local cfg_cross = Config:new({
        zone_overrides = {
            [1234] = { loot = { range = 5.0 } },
        },
    })
    local r_cross = cfg_cross:get_zone_override(1234)
    assert(type(r_cross) == "table",
        "Test 9: should find zone 1234 stored as numeric key")
    assert(r_cross.loot and r_cross.loot.range == 5.0,
        "Test 9: loot.range mismatch")

    -- -----------------------------------------------------------------------
    -- Test 10: Defaults.logging.global_level defaults to "INFO"
    -- -----------------------------------------------------------------------
    assert(Defaults.logging ~= nil, "Test 10: Defaults.logging should exist")
    assert(Defaults.logging.global_level == "INFO",
        "Test 10: Defaults.logging.global_level should be 'INFO', got " ..
        tostring(Defaults.logging.global_level))
    assert(Defaults.logging.max_history == 200,
        "Test 10: Defaults.logging.max_history should be 200")

    -- -----------------------------------------------------------------------
    -- Test 11: build_runtime extra param correctly overrides mount.min_level
    -- -----------------------------------------------------------------------
    local rt_custom = Defaults.build_runtime({ mount = { min_level = 60 } })
    assert(rt_custom.mount.min_level == 60,
        "Test 11: build_runtime extra override should set mount.min_level=60, got " ..
        tostring(rt_custom.mount.min_level))
    -- And the base Defaults.mount should be unaffected
    assert(Defaults.mount.min_level == 40,
        "Test 11: Defaults.mount.min_level should still be 40 after build_runtime")

    env.restore()
    return true
end

return M
