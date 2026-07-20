-- sentinel/tests/ui/test_sentinel_ui_render_aliases.lua
-- Regression test for the "UI doesn't show up / can't click to pop up" bug:
-- RotationSettingsUI (the SentinelUI used by every panel) previously exposed
-- only on_render / on_menu_render, so panel calls to render()/render_window()/
-- render_menu() were silent no-ops and no window was ever drawn. Also verify the
-- _force_visible flag lets editor panels render without the rotation toggle.

local T = require("tests/test_util")

local M = {}

function M.run()
    print("=== SentinelUI Render Alias Tests ===")

    -- Ensure we load the REAL module (not a test mock).
    package.loaded["shared/ui/sentinel_ui"] = nil
    local SentinelUI = require("shared/ui/sentinel_ui")
    local ui = SentinelUI.new({
        id = "alias-test",
        title = "Alias Test",
        default_x = 10, default_y = 10, default_w = 200, default_h = 200,
        tabs = { { id = "t1", label = "T1" } },
    })

    T.assert_equal(type(ui.render), "function", "render() method exists")
    T.assert_equal(type(ui.render_window), "function", "render_window() method exists")
    T.assert_equal(type(ui.render_menu), "function", "render_menu() method exists")

    -- Without force-visible, _is_enabled is gated by the (default-off) menu toggle.
    T.assert_false(ui:_is_enabled(), "disabled by default (no force_visible)")

    -- Editor panels opt in to always-visible.
    ui:set_visible(true)
    T.assert_true(ui:_is_enabled(), "force_visible makes window renderable")

    print("  PASS")
    print("\n=== All SentinelUI Render Alias Tests PASSED ===")
end

return M
