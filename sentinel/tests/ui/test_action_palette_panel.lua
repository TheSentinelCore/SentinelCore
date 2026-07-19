-- sentinel/tests/ui/test_action_palette_panel.lua
-- Tests for ui/panels/action_palette_panel.lua

local T = require("tests/test_util")
local ActionPalettePanel = require("ui/panels/action_palette_panel")

local M = {}

function M.test_action_palette_construction()
    print("Test: ActionPalettePanel construction")
    local panel = ActionPalettePanel:new(nil, nil)
    T.assert_not_nil(panel, "Panel should not be nil")
    print("  PASS")
end

function M.test_action_categories_exist()
    print("Test: Action categories")
    -- Verify the panel's internal ACTION_CATEGORIES constant
    -- We can check the panel works without init by testing internal methods
    local panel = ActionPalettePanel:new(nil, nil)
    
    -- Manually set search_text to test _is_category_visible
    panel._search_text = ""
    local visible = panel:_is_category_visible({ actions = { { type = "test" } } })
    T.assert_true(visible, "Category should be visible when search is empty")
    
    panel._search_text = "nonexistent"
    local not_visible = panel:_is_category_visible({ actions = { { type = "test" } } })
    T.assert_false(not_visible, "Category should not be visible when search has no matches")
    print("  PASS")
end

function M.test_on_action_selected_publishes_event()
    print("Test: On action selected publishes event")
    local published = {}
    local mock_bus = {
        publish = function(_, event, payload)  -- Note: self is first arg with : syntax
            published.event = event
            published.payload = payload
        end,
    }
    
    local panel = ActionPalettePanel:new(nil, mock_bus)
    panel._event_bus = mock_bus  -- Ensure it's set
    panel:_on_action_selected("goto")
    
    T.assert_equal(published.event, "action:add", "Should publish action:add event")
    T.assert_equal(published.payload.type, "goto", "Payload should include action type")
    print("  PASS")
end

function M.test_on_blueprint_selected_publishes_event()
    print("Test: On blueprint selected publishes event")
    local published = {}
    local mock_bus = {
        publish = function(_, event, payload)
            published.event = event
            published.payload = payload
        end,
    }
    
    local panel = ActionPalettePanel:new(nil, mock_bus)
    panel._event_bus = mock_bus
    panel:_on_blueprint_selected({ id = "test_bp" })
    
    T.assert_equal(published.event, "blueprint:add", "Should publish blueprint:add event")
    T.assert_equal(published.payload.blueprint_id, "test_bp", "Payload should include blueprint id")
    print("  PASS")
end

function M.run()
    print("=== Action Palette Panel Tests ===")
    M.test_action_palette_construction()
    M.test_action_categories_exist()
    M.test_on_action_selected_publishes_event()
    M.test_on_blueprint_selected_publishes_event()
    print("\n=== All Action Palette Panel Tests PASSED ===")
end

return M