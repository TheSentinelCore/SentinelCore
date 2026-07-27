-- sentinel/ui/panels/database.lua
-- The Database panel's render layer (Phase 4, PR-4a/4b — Spawn Scanner F9,
-- Grinding Area Generator F13).
--
-- THIS FILE CONTAINS NO BRANCH, AND THAT IS THE POINT
-- ------------------------------------------------
-- Code inside `register_on_render_window_callback` cannot be entered outside the injector, so a
-- decision taken here is a decision no test can reach. Every one of them lives in
-- `database_state.lua`, which builds the draw plan; this file looks each item's kind up in a
-- table and calls the widget.
--
-- WHAT THE HOST GETS BACK
-- -----------------------
-- `render` returns the COMMAND a control activation produced, never the effect.
-- The shell dispatches the command instead.

local Theme = require("ui/theme")
local Widgets = require("ui/widgets")
local DatabaseState = require("ui/panels/database_state")

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
            Theme.color[item.token](item.alpha or Theme.interaction.resting.border),
            item.rounding or Theme.radius.none,
            item.thickness or Theme.metrics.border_thickness)
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

    section_header = function(window, item)
        return Widgets.section_header(window, item.bounds, item) and item.id or nil
    end,

    empty_state = function(window, item)
        return Widgets.empty_state(window, item.bounds, item) and item.id or nil
    end,

    badge = function(window, item)
        Widgets.badge(window, item.bounds, item)
        return nil
    end,
}

local Database = {}

Database.id = "database"
Database.title = "Database"
Database.order = 5

---Draw the panel and report what the operator asked for.
---
---Every item is drawn on every frame even after one has fired: an immediate-mode frame that
---stopped painting at the first activation would blank the rest of the panel for exactly the one
---frame in which the operator pressed something.
---@return table|nil command { kind, ... }
function Database.render(window, bounds, view)
    local plan = DatabaseState.build_plan(view, bounds)
    local items = plan.items
    local fired = nil

    for i = 1, #items do
        local item = items[i]
        local handler = HANDLERS[item.kind]
        local activated = handler(window, item)
        fired = fired or activated
    end

    return DatabaseState.reduce(fired), plan
end

return Database
