-- sentinel/integrations/sentinel_bridge/render_bridge.lua
-- Immediate-mode rendering bridge to Sylvanas core.graphics API
-- Implements RenderSurfaceTrait - ADR 009 §7

local RenderSurfaceTrait = require("integrations/sentinel_bridge/render_surface_trait")

local RenderBridge = {}
RenderBridge.__index = RenderBridge

setmetatable(RenderBridge, { __index = RenderSurfaceTrait })

---Create a new RenderBridge
---@return table RenderBridge instance
function RenderBridge:new()
    local o = setmetatable({}, RenderBridge)
    o._elements = {}
    o._window_id = "SentinelQuestIDE"
    o._visible = true
    return o
end

---Register a panel for rendering
---@param panel_descriptor table PanelDescriptor
---@param render_fn function Render function
function RenderBridge:register_panel(panel_descriptor, render_fn)
    self._elements[panel_descriptor.id] = {
        type = "panel",
        descriptor = panel_descriptor,
        render_fn = render_fn,
    }
end

---Draw all registered panels
---@param input_events table Array of UI events
function RenderBridge:draw(input_events)
    if not self._visible then return end

    if not self._registered then
        self._registered = true
        if core and type(core.register_on_render_callback) == "function" then
            core.register_on_render_callback(function()
                self:_draw_all_panels()
            end)
        else
            self._headless_mode = true
        end
    end

    self._input_events = input_events or {}
    if self._headless_mode then
        self:_draw_all_panels()
    end
end

---Internal draw function
---@private
function RenderBridge:_draw_all_panels()
    for _, element in pairs(self._elements) do
        if element.type == "panel" and element.render_fn then
            local desc = element.descriptor
            if desc.w and desc.h and core and core.graphics then
                local ok, err = pcall(function()
                    core.graphics.rect_2d_filled(
                        vec2.new(desc.x or 10, desc.y or 10),
                        desc.w,
                        desc.h,
                        { r = 0.1, g = 0.1, b = 0.15, a = 0.9 }
                    )
                end)
                if not ok then
                    if core.log_error then
                        core.log_error("Panel draw error: " .. tostring(err))
                    end
                end
            end

            local ok, err = pcall(element.render_fn, self._input_events)
            if not ok then
                if core and core.log_error then
                    core.log_error("Panel render error: " .. tostring(err))
                end
            end
        end
    end
end

---Draw map overlay elements
---@param elements table Array of MapElement
function RenderBridge:draw_map_overlay(elements)
    if not core or not core.graphics then return end

    for _, elem in ipairs(elements or {}) do
        if elem.type == "waypoint" and elem.point then
            pcall(function()
                core.graphics.circle_3d(
                    elem.point,
                    3.0,
                    elem.color or { r = 1, g = 0, b = 0, a = 0.8 },
                    2.0
                )
            end)
        elseif elem.type == "polygon" and elem.points then
            pcall(function()
                core.graphics.render_polygon_3d(
                    elem.points,
                    elem.color or { r = 0, g = 1, b = 0, a = 0.5 },
                    elem.filled ~= false
                )
            end)
        end
    end
end

---Capture next keyboard input
---@param callback function Handler function
function RenderBridge:capture_keyboard(callback)
    if core and core.graphics and type(core.graphics.capture_next_keyboard_input) == "function" then
        core.graphics.capture_next_keyboard_input()
    end
end

---Capture next mouse input
---@param callback function Handler function
function RenderBridge:capture_mouse(callback)
    if core and core.graphics and type(core.graphics.capture_next_mouse_input) == "function" then
        core.graphics.capture_next_mouse_input()
    end
end

---Set window visibility
---@param visible boolean
function RenderBridge:set_visible(visible)
    self._visible = visible == true
end

---Get screen size
---@return table size
function RenderBridge:get_screen_size()
    if core and type(core.graphics.get_screen_size) == "function" then
        local ok, size = pcall(core.graphics.get_screen_size)
        if ok and size then
            return size
        end
    end
    return { x = 1920, y = 1080 }
end

---Create headless/no-op implementation for CI
---@return table headless_implementation
function RenderBridge.create_headless()
    return RenderSurfaceTrait.create_headless()
end

return RenderBridge