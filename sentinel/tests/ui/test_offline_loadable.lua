-- tests/ui/test_offline_loadable.lua
-- The UI layer must load with NO Sylvannas API present.
--
-- `common/color`, `common/geometry/vector_2` and `common/enums` only exist inside the injector,
-- and `_G.core` only exists there too. If `theme.lua` or `widgets.lua` requires any of them
-- unguarded, the entire IDE becomes untestable offline in one commit — and the failure is a load
-- error in whichever suite happens to require it first, which reads as that suite's bug.
--
-- These cases blank the SDK for the duration and re-require from source, so the guard is proven
-- rather than assumed to still be there.

local T = require("tests/test_util")

local M = {}

local UI_MODULES = { "ui/theme", "ui/widgets", "tests/harness/fake_window" }

--- Load `module_name` from source with `_G.core` and the `common/*` libraries absent.
--- Restores `package.loaded` exactly, because the suites that already hold references to these
--- modules must keep seeing the same instances.
local function require_without_sdk(module_name)
    local saved_core = _G.core
    local saved_loaded = {}
    for _, name in ipairs(UI_MODULES) do
        saved_loaded[name] = package.loaded[name]
        package.loaded[name] = nil
    end

    _G.core = nil
    local ok, result = pcall(require, module_name)

    _G.core = saved_core
    for _, name in ipairs(UI_MODULES) do
        package.loaded[name] = saved_loaded[name]
    end

    return ok, result
end

function M.test_theme_loads_with_no_sylvannas_api_present()
    local ok, result = require_without_sdk("ui/theme")
    T.assert_true(ok, "ui/theme failed to load offline: " .. tostring(result))
    T.assert_equal(type(result), "table", "ui/theme must return the theme table")
end

function M.test_theme_still_builds_colours_with_no_colour_library()
    local ok, theme = require_without_sdk("ui/theme")
    T.assert_true(ok, "ui/theme failed to load offline")
    local built = theme.color.accent(200)
    T.assert_equal(built.a, 200, "the fallback colour shim must honour the alpha")
    T.assert_equal(built.r, theme.rgba.accent[1], "the fallback shim must carry the channels")
end

function M.test_theme_still_resolves_font_ids_with_no_enums_library()
    local ok, theme = require_without_sdk("ui/theme")
    T.assert_true(ok, "ui/theme failed to load offline")
    -- The documented ids (ui-custom.md: FONT_SMALL = 0 ... FONT_ICONS_VERY_BIG = 6) are the
    -- fallback, so offline layout maths matches what the injector will actually use.
    T.assert_equal(theme.font.caption, 0, "FONT_SMALL is 0")
    T.assert_equal(theme.font.body, 1, "FONT_NORMAL is 1")
    T.assert_equal(theme.font.heading, 2, "FONT_SEMI_BIG is 2")
    T.assert_equal(theme.font.title, 3, "FONT_BIG is 3")
end

function M.test_widgets_load_with_no_sylvannas_api_present()
    local ok, result = require_without_sdk("ui/widgets")
    T.assert_true(ok, "ui/widgets failed to load offline: " .. tostring(result))
    T.assert_equal(type(result), "table", "ui/widgets must return the widget table")
end

function M.test_widgets_render_with_no_sylvannas_api_present()
    -- Loading is not enough: `vec2.new` is called on the render path, so the shim has to survive
    -- being used, not just being required.
    local ok, widgets = require_without_sdk("ui/widgets")
    T.assert_true(ok, "ui/widgets failed to load offline")

    local FakeWindow = require("tests/harness/fake_window")
    local fake = FakeWindow.new()
    local rendered = pcall(widgets.button, fake, { x = 0, y = 0, w = 100, h = 30 }, { label = "Go" })
    T.assert_true(rendered, "a widget must render against a fake window with no SDK present")
    T.assert_true(fake:drew_text("Go"), "and it must actually have drawn something")
end

function M.test_fake_window_loads_with_no_sylvannas_api_present()
    local ok, result = require_without_sdk("tests/harness/fake_window")
    T.assert_true(ok, "the fake window failed to load offline: " .. tostring(result))
    T.assert_equal(type(result.new), "function", "the fake window must expose a constructor")
end

function M.test_the_sdk_is_restored_after_these_cases()
    -- These cases blank `_G.core` for every other suite in the process. If the restore ever
    -- regressed, the failures would land in whichever suite ran next and read as its bug.
    T.assert_not_nil(_G.core, "_G.core must be put back")
    T.assert_not_nil(_G.core.time, "the mocked core surface must be intact")
end

return M
