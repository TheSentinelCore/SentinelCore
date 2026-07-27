-- sentinel/ui/panels/explorer.lua
-- The Explorer panel's render layer (ADR 09b §2.1, §6 U6).
--
-- THIS FILE CONTAINS NO BRANCH, AND THAT IS THE POINT
-- ------------------------------------------------
-- Code inside `register_on_render_window_callback` cannot be entered outside the injector, so a
-- decision taken here is a decision no test can reach. Every one of them lives in
-- `explorer_state.lua`, which builds the draw plan; this file looks each item's kind up in a
-- table and calls the widget.
--
-- WHAT THE HOST GETS BACK
-- -----------------------
-- `render` returns the COMMAND a control activation produced, never the effect.
-- The shell dispatches the command instead.

local Theme = require("ui/theme")
local Widgets = require("ui/widgets")
local ExplorerState = require("ui/panels/explorer_state")

local function require_or(module_name, fallback)
    local ok, mod = pcall(require, module_name)
    return (ok and mod ~= nil and mod) or fallback
end

local Vec2 = require_or("common/geometry/vector_2", {
    new = function(x, y) return { x = x or 0, y = y or 0 } end,
})

local function v2(x, y) return Vec2.new(x, y) end

local HANDLERS = {
    rect = function(window, item)
        window:render_rect_filled(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
            Theme.color[item.token](item.alpha or 255), item.rounding or Theme.radius.none)
    end,

    outline = function(window, item)
        window:render_rect(
            v2(item.bounds.x, item.bounds.y),
            v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h),
            Theme.color[item.token](item.alpha or Theme.interaction.active.border),
            item.rounding or Theme.radius.none, item.thickness or Theme.metrics.border_thickness)
    end,

    text = function(window, item)
        window:render_text(item.font, v2(item.x, item.y),
            Theme.color[item.token](item.alpha or Theme.interaction.resting.text), item.text)
    end,

    button = function(window, item)
        return Widgets.button(window, item.bounds, item) and item.id or nil
    end,

    chip = function(window, item)
        return Widgets.chip(window, item.bounds, item) and item.id or nil
    end,

    list_row = function(window, item)
        return Widgets.list_row(window, item.bounds, item) and item.id or nil
    end,

    -- The only widget that answers with a TABLE rather than a boolean, because Enter and Escape are
    -- different commands. The typed value is not threaded through the id: it is already on the
    -- model the item carries, so `reduce` never has to split a user-typed string.
    text_input = function(window, item)
        local result = Widgets.text_input(window, item.bounds, item)
        return result and (item.id .. "_" .. result.kind) or nil
    end,

    section_header = function(window, item)
        return Widgets.section_header(window, item.bounds, item) and item.id or nil
    end,

    badge = function(window, item)
        local mn = v2(item.bounds.x, item.bounds.y)
        local mx = v2(item.bounds.x + item.bounds.w, item.bounds.y + item.bounds.h)
        window:is_mouse_hovering_rect(mn, mx)
        window:render_rect_filled(mn, mx, Theme.color.accent(255), Theme.radius.pill)
        local label = tostring(item.label or "")
        local tx = item.bounds.x + (item.bounds.w - #label * 7) * 0.5
        window:render_text(Theme.font.caption,
            v2(tx, item.bounds.y + (item.bounds.h - Theme.line_height.caption) * 0.5),
            Theme.color.surface(255), label)
    end,

    empty_state = function(window, item)
        return Widgets.empty_state(window, item.bounds, item) and item.id or nil
    end,
}

local Explorer = {}

Explorer.id = "explorer"
Explorer.title = "Explorer"
Explorer.order = 2

---Draw the panel and report what the operator asked for.
---
---Every item is drawn on every frame even after one has fired: an immediate-mode frame that
---stopped painting at the first activation would blank the rest of the panel for exactly the one
---frame in which the operator pressed something.
---@return table|nil command { kind, ... }
function Explorer.render(window, bounds, view)
    local plan = ExplorerState.build_plan(view, bounds)
    local items = plan.items
    local fired = nil

    for i = 1, #items do
        local item = items[i]
        local handler = HANDLERS[item.kind]
        local activated = handler(window, item)
        fired = fired or activated
    end

    return ExplorerState.reduce(fired), plan
end

return Explorer
