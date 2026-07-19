-- sentinel/integrations/sentinel_bridge/render_surface_trait.lua
-- RenderSurface trait interface - ADR 009 §7
-- Abstract rendering interface with headless/no-op mode for CI

local RenderSurfaceTrait = {}

---Panel descriptor structure
---@class PanelDescriptor
---@field id string Unique panel identifier
---@field title string Panel title
---@field x number X position (optional)
---@field y number Y position (optional)
---@field w number Width (optional)
---@field h number Height (optional)
RenderSurfaceTrait.PanelDescriptor = {
    id = "",
    title = "",
    x = 10,
    y = 10,
    w = 200,
    h = 100,
}

---Map element structure
---@class MapElement
---@field type string "waypoint" or "polygon"
---@field point table Waypoint (for waypoint type)
---@field points table Array of points (for polygon type)
---@field color table { r, g, b, a } optional color
---@field filled boolean? Whether polygon is filled (optional)
RenderSurfaceTrait.MapElement = {
    type = "waypoint",
    point = { x = 0, y = 0, z = 0 },
    points = {},
    color = { r = 1, g = 0, b = 0, a = 0.8 },
    filled = true,
}

---Register a panel for rendering
---@param descriptor table PanelDescriptor
---@param render_fn function Function to call for rendering panel contents
function RenderSurfaceTrait.register_panel(descriptor, render_fn)
    error("RenderSurfaceTrait.register_panel: must be implemented by concrete class")
end

---Draw all registered panels
---@param input_events table Array of UI events from input system
function RenderSurfaceTrait.draw(input_events)
    error("RenderSurfaceTrait.draw: must be implemented by concrete class")
end

---Draw a map overlay element (waypoints, polygons, etc.)
---@param elements table Array of MapElement
function RenderSurfaceTrait.draw_map_overlay(elements)
    error("RenderSurfaceTrait.draw_map_overlay: must be implemented by concrete class")
end

---Set window visibility
---@param visible boolean Whether the window should be visible
function RenderSurfaceTrait.set_visible(visible)
    error("RenderSurfaceTrait.set_visible: must be implemented by concrete class")
end

---Get screen size
---@return table size { x, y }
function RenderSurfaceTrait.get_screen_size()
    error("RenderSurfaceTrait.get_screen_size: must be implemented by concrete class")
end

---Capture the next keyboard input
---@param callback function Function to receive captured key
function RenderSurfaceTrait.capture_keyboard(callback)
    error("RenderSurfaceTrait.capture_keyboard: must be implemented by concrete class")
end

---Capture the next mouse input
---@param callback function Function to receive captured mouse event
function RenderSurfaceTrait.capture_mouse(callback)
    error("RenderSurfaceTrait.capture_mouse: must be implemented by concrete class")
end

---Create a headless/no-op implementation for CI/testing
---@return table headless_implementation
function RenderSurfaceTrait.create_headless()
    local HeadlessMeta = {}
    HeadlessMeta.__index = HeadlessMeta

    local headless = {
        _elements = {},
        _visible = false,
    }
    setmetatable(headless, HeadlessMeta)

    function HeadlessMeta:register_panel(descriptor, render_fn)
        if descriptor and descriptor.id then
            self._elements[descriptor.id] = { descriptor = descriptor, render_fn = render_fn }
        end
    end

    function HeadlessMeta:draw(input_events)
        for _, element in pairs(self._elements) do
            if element.render_fn then
                local ok = pcall(element.render_fn, input_events)
                if not ok then
                    -- Silent no-op in headless mode
                end
            end
        end
    end

    function HeadlessMeta:draw_map_overlay(elements)
        -- Silent no-op in headless mode
    end

    function HeadlessMeta:set_visible(visible)
        self._visible = visible == true
    end

    function HeadlessMeta:get_screen_size()
        return { x = 1920, y = 1080 }
    end

    function HeadlessMeta:capture_keyboard(callback)
        -- Silent no-op in headless mode
    end

    function HeadlessMeta:capture_mouse(callback)
        -- Silent no-op in headless mode
    end

    return headless
end

return RenderSurfaceTrait