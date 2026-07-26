-- sentinel/ui/panels/runner.lua
-- The Runner panel's render layer (ADR 09b §2.1, §6 U5).
--
-- THIS FILE CONTAINS NO BRANCH, AND THAT IS THE POINT
-- --------------------------------------------------
-- Code inside `register_on_render_window_callback` cannot be entered outside the injector, so a
-- decision taken here is a decision no test can reach. Every one of them lives in
-- `runner_panel_state.lua`, which emits a flat ordered list of draw items; this file looks each
-- item's kind up in a table and calls the widget. `tests/ui/test_runner_panel.lua` scans this
-- source for `if`, `elseif` and `while` and fails on any of them, because "keep the render layer
-- thin" is an instruction that decays and a scan does not.
--
-- WHAT THE HOST GETS BACK
-- -----------------------
-- `render` returns the COMMAND a control activation produced, never the effect. Calling
-- `module:stop()` from inside a render callback would put a side effect somewhere untestable and
-- somewhere Sylvannas re-enters at arbitrary times; the shell dispatches the command instead.
--
-- No `core.menu.*` (elements are built in the tick callback, §2.2), no IO, no object-manager scan:
-- this runs every frame (§2.4).

local Theme = require("ui/theme")
local Widgets = require("ui/widgets")
local PanelState = require("ui/panels/runner_panel_state")

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    return (ok and mod ~= nil and mod) or fallback
end

-- Guarded exactly as `theme.lua` and `widgets.lua` guard theirs: `common/geometry/vector_2` exists
-- only inside the injector, and an unguarded require makes the panel unloadable offline.
local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

local function v2(x, y) return Vec2.new(x, y) end

---Each handler paints one item and answers with the action id it activated, or nil. Uniform
---returns are what let the caller collect activations without asking which kind it just drew.
local HANDLERS = {
    rect = function(window, item)
        window:render_rect_filled(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
            Theme.color[item.token](item.alpha), item.rounding)
    end,

    outline = function(window, item)
        window:render_rect(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
            Theme.color[item.token](item.alpha), item.rounding, item.thickness)
    end,

    text = function(window, item)
        window:render_text(item.font, v2(item.x, item.y),
            Theme.color[item.token](item.alpha), item.text)
    end,

    button = function(window, item)
        return Widgets.button(window, item.bounds, item) and item.id or nil
    end,

    chip = function(window, item)
        return Widgets.chip(window, item.bounds, item) and item.id or nil
    end,

    section_header = function(window, item)
        return Widgets.section_header(window, item.bounds, item) and item.id or nil
    end,

    empty_state = function(window, item)
        return Widgets.empty_state(window, item.bounds, item) and item.id or nil
    end,
}

local Runner = {}

-- The shape the shell registers. `id` keys the panel, `title` labels its tab, `order` puts the
-- Runner first because the bot running correctly matters more often than authoring does
-- (ADR 09b §4).
Runner.id = "runner"
Runner.title = "Runner"
Runner.order = 1
Runner.state = PanelState

---The panel-local state the shell owns between frames (selection, filter, disclosure).
function Runner.new_model(opts)
    return PanelState.new_model(opts)
end

---Draw the panel and report what the operator asked for.
---
---Every item is drawn on every frame even after one has fired: an immediate-mode frame that
---stopped painting at the first activation would blank the rest of the panel for exactly the one
---frame in which the operator pressed something.
---@return table|nil command { kind, ... } for the host to dispatch, and the plan that produced it
function Runner.render(window, bounds, model)
    local plan = PanelState.build(model, bounds)
    local items = plan.items
    local fired = nil

    for i = 1, #items do
        local item = items[i]
        local activated = HANDLERS[item.kind](window, item)
        fired = fired or activated
    end

    return PanelState.reduce(model, fired), plan
end

return Runner
