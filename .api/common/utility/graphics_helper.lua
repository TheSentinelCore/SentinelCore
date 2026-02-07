
--[[
Example usage:
---@type graphics_helper
local gfx = require("common/utility/graphics_helper")
gfx: -> IntelliSense available
-- Warning: Access with ":", not "."
]]

--- @class graphics_helper
--- A helper library for drawing text with effects (e.g. outlined, shadowed) in 2D and 3D.
--- Provides default settings and style enums for efficient text drawing.
--- 
--- Default configuration:
---  * text_size (number): Default font size (30).
---  * style (number): Default text style. Use graphics_helper.styles.OUTLINED or graphics_helper.styles.SHADOWED (default is OUTLINED).
---  * text_color (color): Default main text color (color.white(255)).
---  * outline_color (color): Default outline/shadow color (color.black(255)).
---  * outline_thickness (number): Thickness of the outline (3).
---  * outline_steps (number): Number of steps for the outline (16).
---
--- @field defaults table
--- @field styles table
--- @field draw_text_outlined_2d fun(self: graphics_helper, text: string, position: vec2, options: table|nil): nil
--- @field draw_text_outlined_3d fun(self: graphics_helper, text: string, position: vec3, options: table|nil): nil

---@type graphics_helper
local tbl
return tbl
