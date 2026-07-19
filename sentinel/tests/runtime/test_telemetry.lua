-- sentinel/tests/runtime/test_telemetry.lua
-- Tests for runtime/telemetry.lua

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

-- Track saved files for testing save/load roundtrip
local _saved_files = {}

-- Mock core with telemetry-appropriate mocks
local function setup_core_mocks()
    _G.core = _G.core or {}
    _G.core.game_time = function() return 0 end
    _G.core.write_data_file = function(path, content)
        _saved_files[path] = content
        return true
    end
    _G.core.read_data_file = function(path)
        local content = _saved_files[path]
        if content then
            return content, nil
        end
        return nil, "file not found"
    end
end

local function cleanup_mocks()
    _saved_files = {}
end

-- Helper to advance mock time
local _current_time = 0
local function mock_time()
    return _current_time
end

local function advance_time(ms)
    _current_time = _current_time + (ms or 0)
end

function M.run()
    print("=== Telemetry Tests ===")

    setup_core_mocks()

    -- =====================================================================
    -- Test 1: Construction and basic API surface
    -- =====================================================================
    print("Test 1: Construction and API surface")
    local bb = Blackboard:new()
    local eb = EventBus:new()

    package.loaded["runtime/telemetry"] = nil
    local Telemetry = require("runtime/telemetry")
    local tel = Telemetry:new(bb, eb)

    T.assert_not_nil(tel, "Telemetry should construct")
    T.assert_not_nil(tel.start, "should have start method")
    T.assert_not_nil(tel.stop, "should have stop method")
    T.assert_not_nil(tel.record_action, "should have record_action method")
    T.assert_not_nil(tel.record_operation, "should have record_operation method")
    T.assert_not_nil(tel.record_death, "should have record_death method")
    T.assert_not_nil(tel.record_xp_gained, "should have record_xp_gained method")
    T.assert_not_nil(tel.record_gold_spent, "should have record_gold_spent method")
    T.assert_not_nil(tel.get_summary, "should have get_summary method")
    T.assert_not_nil(tel.get_operation_timeline, "should have get_operation_timeline method")
    T.assert_not_nil(tel.save, "should have save method")
    T.assert_not_nil(tel.load, "should have load method")
    print("  PASS")

    -- =====================================================================
    -- Test 2: record_action shows in get_summary
    -- =====================================================================
    print("Test 2: record_action shows in get_summary")
    local bb2 = Blackboard:new()
    local eb2 = EventBus:new()
    local tel2 = Telemetry:new(bb2, eb2)
    tel2:start("profile-2")

    tel2:record_action("act-1", "wait", 100, true, 0)
    local summary2 = tel2:get_summary()

    T.assert_equal(summary2.total_actions, 1, "should have 1 action")
    T.assert_equal(summary2.succeeded_actions, 1, "should have 1 succeeded action")
    T.assert_equal(summary2.failed_actions, 0, "should have 0 failed actions")
    T.assert_equal(summary2.actions_by_type["wait"], 1, "wait should have count 1")
    print("  PASS")

    -- =====================================================================
    -- Test 3: record_action with multiple actions aggregates correctly
    -- =====================================================================
    print("Test 3: multiple action records aggregate correctly")
    local bb3 = Blackboard:new()
    local eb3 = EventBus:new()
    local tel3 = Telemetry:new(bb3, eb3)
    tel3:start("profile-3")

    tel3:record_action("act-1", "wait", 100, true, 0)
    tel3:record_action("act-2", "goto", 500, true, 0)
    tel3:record_action("act-3", "kill_target", 3000, false, 2, "creature not found")
    tel3:record_action("act-4", "wait", 50, true, 0)

    local summary3 = tel3:get_summary()
    T.assert_equal(summary3.total_actions, 4, "should have 4 actions")
    T.assert_equal(summary3.succeeded_actions, 3, "3 succeeded")
    T.assert_equal(summary3.failed_actions, 1, "1 failed")
    T.assert_equal(summary3.actions_by_type["wait"], 2, "2 wait actions")
    T.assert_equal(summary3.actions_by_type["goto"], 1, "1 goto action")
    T.assert_equal(summary3.actions_by_type["kill_target"], 1, "1 kill_target action")
    T.assert_equal(summary3.completion_rate, 0.75, "completion rate should be 0.75")
    print("  PASS")

    -- =====================================================================
    -- Test 4: Death counter increments
    -- =====================================================================
    print("Test 4: death counter increments")
    local bb4 = Blackboard:new()
    local eb4 = EventBus:new()
    local tel4 = Telemetry:new(bb4, eb4)
    tel4:start("profile-4")

    tel4:record_death({ x = 1, y = 2, z = 3 }, "Ragnaros")
    tel4:record_death({ x = 4, y = 5, z = 6 }, "Onyxia")

    local summary4 = tel4:get_summary()
    T.assert_equal(summary4.total_deaths, 2, "should have 2 deaths")
    print("  PASS")

    -- =====================================================================
    -- Test 5: XP and gold recording
    -- =====================================================================
    print("Test 5: XP and gold recording")
    local bb5 = Blackboard:new()
    local eb5 = EventBus:new()
    local tel5 = Telemetry:new(bb5, eb5)
    tel5:start("profile-5")

    tel5:record_xp_gained(100)
    tel5:record_xp_gained(250)
    tel5:record_gold_spent(50)
    tel5:record_gold_spent(25)

    local summary5 = tel5:get_summary()
    T.assert_equal(summary5.total_xp, 350, "total XP should be 350")
    T.assert_equal(summary5.total_gold_spent, 75, "total gold spent should be 75")
    print("  PASS")

    -- =====================================================================
    -- Test 6: Operation recording
    -- =====================================================================
    print("Test 6: operation recording")
    local bb6 = Blackboard:new()
    local eb6 = EventBus:new()
    local tel6 = Telemetry:new(bb6, eb6)
    tel6:start("profile-6")

    tel6:record_operation("op-1", 1500, 3, 0)
    tel6:record_operation("op-2", 5000, 5, 1)

    local summary6 = tel6:get_summary()
    T.assert_equal(summary6.operations_completed, 1, "1 operations completed")
    T.assert_equal(summary6.operations_failed, 1, "1 operations failed")
    print("  PASS")

    -- =====================================================================
    -- Test 7: get_operation_timeline returns ordered actions
    -- =====================================================================
    print("Test 7: get_operation_timeline returns ordered actions")
    local bb7 = Blackboard:new()
    local eb7 = EventBus:new()
    local tel7 = Telemetry:new(bb7, eb7)
    tel7:start("profile-7")

    -- Record actions with operation context
    tel7:record_action("act-a", "wait", 100, true, 0)
    tel7:record_action("act-b", "goto", 200, true, 0)
    tel7:record_action("act-c", "kill_target", 300, false, 1)

    -- Operation timeline returns all actions (since none are tagged with op_id)
    local timeline = tel7:get_operation_timeline("op-1")
    T.assert_equal(#timeline, 3, "timeline should have 3 entries")
    T.assert_equal(timeline[1].action_id, "act-a", "first action in timeline")
    T.assert_equal(timeline[2].action_id, "act-b", "second action in timeline")
    T.assert_equal(timeline[3].action_id, "act-c", "third action in timeline")
    print("  PASS")

    -- =====================================================================
    -- Test 8: Save to disk
    -- =====================================================================
    print("Test 8: save() writes telemetry data")
    local bb8 = Blackboard:new()
    local eb8 = EventBus:new()
    local tel8 = Telemetry:new(bb8, eb8)
    tel8:start("profile-8")

    tel8:record_action("act-s1", "wait", 100, true, 0)
    tel8:record_action("act-s2", "vendor", 200, true, 0)
    tel8:record_death(nil, "mob-1")
    tel8:record_xp_gained(500)
    tel8:record_gold_spent(100)

    local ok, err = tel8:save("profile-8")
    T.assert_true(ok, "save should succeed")
    T.assert_nil(err, "no error on save")

    -- Check that data was written
    T.assert_not_nil(_saved_files["sentinel/analytics/profile-8.json"], "file should be saved")
    print("  PASS")

    -- =====================================================================
    -- Test 9: Load from disk (roundtrip)
    -- =====================================================================
    print("Test 9: load() restores saved telemetry data")
    local bb9 = Blackboard:new()
    local eb9 = EventBus:new()
    local tel9 = Telemetry:new(bb9, eb9)
    tel9:start("profile-9")

    -- Load data saved from test 8
    local data, err = tel9:load("profile-8")
    T.assert_not_nil(data, "load should return data")
    T.assert_nil(err, "no error on load")
    T.assert_equal(data.profile_id, "profile-8", "profile_id should match")

    -- Verify loaded data
    local summary = tel9:get_summary()
    T.assert_equal(summary.total_deaths, 1, "should have 1 death")
    T.assert_equal(summary.total_xp, 500, "XP should be 500")
    T.assert_equal(summary.total_gold_spent, 100, "gold spent should be 100")
    print("  PASS")

    -- =====================================================================
    -- Test 10: Start/stop lifecycle with auto-save from engine events
    -- =====================================================================
    print("Test 10: start/stop lifecycle")
    local bb10 = Blackboard:new()
    local eb10 = EventBus:new()
    local tel10 = Telemetry:new(bb10, eb10)
    tel10:start("profile-10")

    T.assert_equal(tel10._active, true, "should be active after start")

    tel10:stop() -- no auto-save
    T.assert_equal(tel10._active, false, "should not be active after stop")

    -- Can restart
    tel10:start("profile-10-restart")
    T.assert_equal(tel10._active, true, "should be active after restart")
    print("  PASS")

    -- =====================================================================
    -- Test 11: Event bus subscriptions auto-record
    -- =====================================================================
    print("Test 11: Event bus subscriptions auto-record")
    local bb11 = Blackboard:new()
    local eb11 = EventBus:new()
    local tel11 = Telemetry:new(bb11, eb11)
    tel11:start("profile-11")

    -- Publish events that telemetry subscribes to
    eb11:publish("action_succeeded", { action_id = "auto-act-1", action_type = "wait" })
    eb11:publish("action_succeeded", { action_id = "auto-act-2", action_type = "goto" })
    eb11:publish("action_failed", { action_type = "kill_target", error = "not found", retry_count = 2 })
    eb11:publish("player_died", { position = { x = 0, y = 0, z = 0 }, killer = "boss" })
    eb11:publish("xp_gained", { amount = 1000 })
    eb11:publish("gold_spent", { amount = 200 })

    local summary11 = tel11:get_summary()
    T.assert_equal(summary11.total_actions, 3, "should have 3 actions from auto-record")
    T.assert_equal(summary11.total_deaths, 1, "should have 1 death from auto-record")
    T.assert_equal(summary11.total_xp, 1000, "XP should be 1000 from auto-record")
    T.assert_equal(summary11.total_gold_spent, 200, "gold spent should be 200 from auto-record")
    print("  PASS")

    -- =====================================================================
    -- Test 12: Summary includes empty actions_by_type when no actions
    -- =====================================================================
    print("Test 12: Summary structure completeness")
    local bb12 = Blackboard:new()
    local eb12 = EventBus:new()
    local tel12 = Telemetry:new(bb12, eb12)
    tel12:start("profile-12")

    local summary12 = tel12:get_summary()
    T.assert_equal(summary12.total_actions, 0, "no actions recorded")
    T.assert_equal(summary12.operations_completed, 0, "no operations")
    T.assert_equal(summary12.total_deaths, 0, "no deaths")
    T.assert_not_nil(summary12.actions_by_type, "actions_by_type should be present")
    print("  PASS")

    cleanup_mocks()
    print("\n=== All Telemetry Tests PASSED ===")
end

return M
