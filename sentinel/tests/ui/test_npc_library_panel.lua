-- sentinel/tests/ui/test_npc_library_panel.lua
-- Tests for ui/panels/npc_library_panel.lua

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== NPCLibraryPanel Tests ===")

    -- Set up mock core and globals
    _G.core = _G.core or {}
    _G.core.game_time = function() return 1000 end

    -- Mock blackboard and event_bus
    local blackboard = {
        get = function(self, key, default)
            if key == "module.ui.npc_library" then
                return self._mock_npc_library
            end
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

    -- Import the panel class
    local NPCLibraryPanel = require("ui/panels/npc_library_panel")

    -- Test 1: Panel creation
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        assert(panel ~= nil, "Failed to create panel")
        assert(panel._blackboard == blackboard, "Blackboard not set")
        assert(panel._event_bus == event_bus, "Event bus not set")
        print("✓ Panel creation")
    end

    -- Test 2: Init UI
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        local success = panel:init()
        assert(success == true, "Init failed")
        assert(panel._ui ~= nil, "UI not created")
        print("✓ UI initialization")
    end

    -- Test 3: Empty library
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        panel:init()
        blackboard._mock_npc_library = {}
        panel:update() -- trigger update
        -- Should show empty state
        print("✓ Empty library handling")
    end

    -- Test 4: With NPC data
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        panel:init()
        blackboard._mock_npc_library = {
            {
                entry = 1,
                name = "NPC One",
                zone = "Elwynn Forest",
                roles = { "vendor" }
            },
            {
                entry = 2,
                name = "NPC Two",
                zone = "Dun Morogh",
                roles = { "questgiver" }
            }
        }
        panel:update()
        -- Should have processed the NPCs
        assert(panel._npcs ~= nil and #panel._npcs == 2, "NPCs not loaded")
        print("✓ NPC data loading")
    end

    -- Test 5: Search filter
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        panel:init()
        blackboard._mock_npc_library = {
            { entry = 1, name = "Aldurin", zone = "Elwynn", roles = { "vendor" } },
            { entry = 2, name = "Banthar", zone = "Dun Morogh", roles = { "questgiver" } }
        }
        panel._search_query = "aldur"
        panel:update()
        local filtered = panel:_npc_matches_filter(blackboard._mock_npc_library[1])
        assert(filtered == true, "Should match")
        filtered = panel:_npc_matches_filter(blackboard._mock_npc_library[2])
        assert(filtered == false, "Should not match")
        print("✓ Search filter")
    end

    -- Test 6: Role filter
    do
        local panel = NPCLibraryPanel:new(blackboard, event_bus)
        panel:init()
        blackboard._mock_npc_library = {
            { entry = 1, name = "Aldurin", zone = "Elwynn", roles = { "vendor" } },
            { entry = 2, name = "Banthar", zone = "Dun Morogh", roles = { "questgiver" } }
        }
        panel._role_filter = "vendor"
        local filtered = panel:_npc_matches_filter(blackboard._mock_npc_library[1])
        assert(filtered == true, "Vendor should match vendor filter")
        filtered = panel:_npc_matches_filter(blackboard._mock_npc_library[2])
        assert(filtered == false, "Questgiver should not match vendor filter")
        print("✓ Role filter")
    end

    print("NPCLibraryPanel tests done")
end

return M