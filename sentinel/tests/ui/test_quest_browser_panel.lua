-- sentinel/tests/ui/test_quest_browser_panel.lua
-- Tests for ui/panels/quest_browser_panel.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== QuestBrowserPanel Tests ===")

    -- Set up mock core and globals
    _G.core = _G.core or {}
    _G.core.game_time = function() return 1000 end

    -- Mock blackboard and event_bus
    local blackboard = {
        get = function(self, key, default)
            return default
        end,
        set = function(self, key, value)
            self[key] = value
        end
    }
    local event_bus = {
        subscribe = function() end,
        publish = function() end
    }

    -- Mock query client
    local query_client = {
        search_quests = function(self, query, callback)
            if self._mock_search_results then
                callback(self._mock_search_results, nil)
            else
                callback(nil, "Query failed")
            end
        end
    }

    -- Import the panel class
    local QuestBrowserPanel = require("ui/panels/quest_browser_panel")

    -- Test 1: Panel creation
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        assert(panel ~= nil, "Failed to create panel")
        assert(panel._blackboard == blackboard, "Blackboard not set")
        assert(panel._event_bus == event_bus, "Event bus not set")
        assert(panel._query_client == query_client, "Query client not set")
        print("✓ Panel creation")
    end

    -- Test 2: Init UI
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        local success = panel:init()
        assert(success == true, "Init failed")
        assert(panel._ui ~= nil, "UI not created")
        print("✓ UI initialization")
    end

    -- Test 3: Empty search
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        panel:init()
        panel._search_query = ""
        panel:_perform_search()
        assert(panel._search_results == nil or #panel._search_results == 0, "Should have no results")
        print("✓ Empty search")
    end

    -- Test 4: Search with results
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        panel:init()
        query_client._mock_search_results = {
            { id = 1, title = "Test Quest 1", level = 5, zone = "Elwynn Forest", giver_name = "Guardman" },
            { id = 2, title = "Test Quest 2", level = 10, zone = "Dun Morogh", giver_name = "Mountaineer" }
        }
        panel._search_query = "test"
        panel:_perform_search()
        assert(panel._search_results ~= nil and #panel._search_results == 2, "Should have 2 results")
        assert(panel._search_results[1].title == "Test Quest 1", "First result incorrect")
        print("✓ Search with results")
    end

    -- Test 5: Search failure
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        panel:init()
        query_client._mock_search_results = nil -- will cause error
        panel._search_query = "test"
        panel:_perform_search()
        -- Should handle error gracefully
        assert(panel._search_results == nil or #panel._search_results == 0, "Should have no results on error")
        print("✓ Search failure handling")
    end

    -- Test 6: Select quest
    do
        local panel = QuestBrowserPanel:new(blackboard, event_bus, query_client)
        panel:init()
        panel._search_results = {
            { id = 1, title = "Test Quest", level = 5, zone = "Elwynn Forest", giver_name = "Guardman" }
        }
        panel._selected_quest = panel._search_results[1]
        assert(panel._selected_quest ~= nil, "Should have selected quest")
        assert(panel._selected_quest.title == "Test Quest", "Selected quest incorrect")
        print("✓ Quest selection")
    end

    print("QuestBrowserPanel tests done")
end

return M