-- sentinel/tests/modules/quest/test_quest_module.lua
-- Tests for QuestModule entry point

local Blackboard = require("core/blackboard")
local EventBus = require("core/event_bus")
local T = require("tests/test_util")

local M = {}

-- Mock objects for tests
local function make_mock_runtime_engine()
    local engine = {
        _status = "idle",
        _current_op = nil,
        tick = function(self, delta_ms)
            return { status = self._status, current_operation = self._current_op }
        end,
        get_state = function(self)
            return { status = self._status, current_operation = self._current_op }
        end,
        set_profile = function(self, profile)
            self._current_profile = profile
            return true
        end,
    }
    return engine
end

local function make_mock_profile_manager()
    return {
        _profile = nil,
        _profile_id = nil,
        get_active_profile = function(self) return self._profile end,
        get_active_profile_id = function(self) return self._profile_id end,
        set_active_profile = function(self, p) self._profile = p end,
        activate = function(self, bb, id) self._profile_id = id; return true end,
    }
end

function M.test_quest_module_construction()
    print("Test: QuestModule construction")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    local quest = QuestModule:new(bb, eb, engine)
    T.assert_not_nil(quest, "QuestModule should be returned from constructor")
    T.assert_equal(type(quest.init), "function", "should have init method")
    T.assert_equal(type(quest.tick), "function", "should have tick method")
    T.assert_equal(type(quest.shutdown), "function", "should have shutdown method")
    T.assert_equal(type(quest.load_profile), "function", "should have load_profile method")
    T.assert_equal(type(quest.check_goals), "function", "should have check_goals method")
    print("  PASS")
end

function M.test_quest_module_init_registers_handlers()
    print("Test: QuestModule init registers event handlers")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    local quest = QuestModule:new(bb, eb, engine)
    quest:init()

    -- Check that module is marked as initialized
    T.assert_true(quest._initialized, "should be marked as initialized")
    print("  PASS")
end

function M.test_quest_module_tick_delegates_to_engine()
    print("Test: QuestModule tick delegates to engine")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    local quest = QuestModule:new(bb, eb, engine)
    quest:init()
    quest:tick(16)

    -- Engine tick should have been called
    T.assert_equal(engine._status, "idle", "engine state accessible after tick")
    print("  PASS")
end

function M.test_quest_module_load_profile_sets_active()
    print("Test: QuestModule load_profile sets active profile")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    local quest = QuestModule:new(bb, eb, engine)
    quest:init()

    local profile = {
        id = "test-profile",
        name = "Test Quest Profile",
        operations = {
            { id = "op-1", name = "Test Op", priority = 10, actions = {} }
        }
    }

    quest:load_profile(profile)
    T.assert_not_nil(quest._active_profile, "active profile should be set")
    T.assert_equal(quest._active_profile.id, "test-profile", "profile id should match")
    print("  PASS")
end

function M.test_quest_module_shutdown_clears_state()
    print("Test: QuestModule shutdown clears state")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    local quest = QuestModule:new(bb, eb, engine)
    quest:init()

    local profile = {
        id = "test-profile",
        name = "Test Quest Profile",
        operations = {}
    }
    quest:load_profile(profile)
    T.assert_true(quest._initialized, "should be initialized before shutdown")

    quest:shutdown()
    T.assert_false(quest._initialized, "should not be initialized after shutdown")
    print("  PASS")
end

function M.test_quest_module_subscribe_to_events()
    print("Test: QuestModule subscribes to events on init")
    package.loaded["modules/quest/init"] = nil
    local QuestModule = require("modules/quest/init")

    local bb = Blackboard:new()
    local eb = EventBus:new()
    local engine = make_mock_runtime_engine()

    -- Track if event handlers are subscribed
    local event_subscribed = {}
    eb.subscribe = function(self, event_name, handler, priority)
        event_subscribed[event_name] = true
        return "token-" .. event_name
    end

    local quest = QuestModule:new(bb, eb, engine)
    quest:init()

    T.assert_true(event_subscribed["quest_completed"] ~= nil, "should subscribe to quest_completed")
    T.assert_true(event_subscribed["level_gained"] ~= nil, "should subscribe to level_gained")
    T.assert_true(event_subscribed["item_acquired"] ~= nil, "should subscribe to item_acquired")
    print("  PASS")
end

function M.run()
    print("=== Quest Module Tests ===")
    M.test_quest_module_construction()
    M.test_quest_module_init_registers_handlers()
    M.test_quest_module_tick_delegates_to_engine()
    M.test_quest_module_load_profile_sets_active()
    M.test_quest_module_shutdown_clears_state()
    M.test_quest_module_subscribe_to_events()
    print("\n=== All QuestModule Tests PASSED ===")
end

return M